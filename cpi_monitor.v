// CPI Monitor
// Measures Cycles Per Instruction over sliding windows
// Provides training signal for perceptron mode predictor
// 1. Counts cycles and instructions over fixed windows
// 2. Computes CPI at window boundaries
// 3. Tracks which mode achieves best CPI
// 4. Generates training signal for perceptron

module cpi_monitor #(
    parameter WINDOW_SIZE = 32,          // Instructions per window
    parameter CPI_FRAC_BITS = 4          // Fractional bits for CPI
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,
    
    // Instruction tracking
    input  wire        inst_valid,       // Valid instruction completed
    input  wire        inst_retired,     // Instruction retired (for accurate count)
    input  wire        stall,            // Pipeline stalled
    
    // Current mode
    input  wire [1:0]  current_mode,     // 00=P3, 01=P5, 10=P7
    
    // CPI outputs
    output reg  [7:0]  current_cpi,      // Current window CPI (fixed point)
    output reg  [7:0]  best_cpi_p3,      // Best CPI seen in P3 mode
    output reg  [7:0]  best_cpi_p5,      // Best CPI seen in P5 mode
    output reg  [7:0]  best_cpi_p7,      // Best CPI seen in P7 mode
    
    // Training outputs
    output reg         window_complete,  // Window just finished
    output reg  [1:0]  best_mode,        // Mode with best CPI for current workload
    output reg  [7:0]  confidence        // Confidence in best_mode (based on margin)
);

    // Window counters
    reg [15:0] cycle_count;
    reg [7:0]  inst_count;
    
    // Historical CPI for each mode (exponential moving average)
    reg [11:0] ema_cpi_p3;  // 8.4 fixed point
    reg [11:0] ema_cpi_p5;
    reg [11:0] ema_cpi_p7;
    
    // EMA smoothing factor (alpha = 1/4 for simple shift)
    localparam EMA_SHIFT = 2;
    
    // Ideal CPI reference points for each mode
    // These are theoretical minimums under ideal conditions
    localparam [7:0] IDEAL_CPI_P3 = 8'h10;  // 1.0 in 4.4 fixed point
    localparam [7:0] IDEAL_CPI_P5 = 8'h10;  // 1.0
    localparam [7:0] IDEAL_CPI_P7 = 8'h10;  // 1.0
    
    // Compute CPI (cycles / instructions) in fixed point
    wire [15:0] cpi_raw;
    assign cpi_raw = (inst_count > 0) ? 
                     ((cycle_count << CPI_FRAC_BITS) / inst_count) : 
                     16'hFFFF;
    
    // Saturate to 8 bits
    wire [7:0] cpi_saturated;
    assign cpi_saturated = (cpi_raw > 16'h00FF) ? 8'hFF : cpi_raw[7:0];
    
    // Window state machine
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            cycle_count    <= 16'b0;
            inst_count     <= 8'b0;
            current_cpi    <= 8'h10;  // 1.0 default
            window_complete <= 1'b0;
            
            ema_cpi_p3     <= 12'h100;  // 1.0 in 8.4 fixed point
            ema_cpi_p5     <= 12'h100;
            ema_cpi_p7     <= 12'h100;
            
            best_cpi_p3    <= 8'hFF;
            best_cpi_p5    <= 8'hFF;
            best_cpi_p7    <= 8'hFF;
            
            best_mode      <= 2'b01;  // Default P5
            confidence     <= 8'b0;
        end else if (enable) begin
            window_complete <= 1'b0;
            
            // Always count cycles
            cycle_count <= cycle_count + 1;
            
            // Count retired instructions
            if (inst_retired) begin
                inst_count <= inst_count + 1;
            end
            
            // Window complete when enough instructions retired
            if (inst_count >= WINDOW_SIZE) begin
                window_complete <= 1'b1;
                current_cpi <= cpi_saturated;
                
                // Update EMA for current mode
                case (current_mode)
                    2'b00: begin  // P3
                        ema_cpi_p3 <= ema_cpi_p3 - (ema_cpi_p3 >> EMA_SHIFT) + 
                                      ({4'b0, cpi_saturated} >> EMA_SHIFT);
                        if (cpi_saturated < best_cpi_p3)
                            best_cpi_p3 <= cpi_saturated;
                    end
                    2'b01: begin  // P5
                        ema_cpi_p5 <= ema_cpi_p5 - (ema_cpi_p5 >> EMA_SHIFT) + 
                                      ({4'b0, cpi_saturated} >> EMA_SHIFT);
                        if (cpi_saturated < best_cpi_p5)
                            best_cpi_p5 <= cpi_saturated;
                    end
                    2'b10: begin  // P7
                        ema_cpi_p7 <= ema_cpi_p7 - (ema_cpi_p7 >> EMA_SHIFT) + 
                                      ({4'b0, cpi_saturated} >> EMA_SHIFT);
                        if (cpi_saturated < best_cpi_p7)
                            best_cpi_p7 <= cpi_saturated;
                    end
                endcase
                
                // Reset counters for next window
                cycle_count <= 16'b0;
                inst_count  <= 8'b0;
            end
        end
    end
    
    // Determine best mode based on historical EMAs
    // Use simple comparison of ema values
    wire [11:0] min_ema;
    wire [1:0] min_mode;
    wire [11:0] second_ema;
    
    // Find minimum EMA (best mode) and second minimum
    assign min_ema = (ema_cpi_p3 <= ema_cpi_p5 && ema_cpi_p3 <= ema_cpi_p7) ? ema_cpi_p3 :
                     (ema_cpi_p5 <= ema_cpi_p7) ? ema_cpi_p5 : ema_cpi_p7;
    
    assign min_mode = (ema_cpi_p3 <= ema_cpi_p5 && ema_cpi_p3 <= ema_cpi_p7) ? 2'b00 :
                      (ema_cpi_p5 <= ema_cpi_p7) ? 2'b01 : 2'b10;
    
    // Second minimum for confidence calculation
    assign second_ema = (min_mode == 2'b00) ? 
                        ((ema_cpi_p5 <= ema_cpi_p7) ? ema_cpi_p5 : ema_cpi_p7) :
                        (min_mode == 2'b01) ?
                        ((ema_cpi_p3 <= ema_cpi_p7) ? ema_cpi_p3 : ema_cpi_p7) :
                        ((ema_cpi_p3 <= ema_cpi_p5) ? ema_cpi_p3 : ema_cpi_p5);
    
    // Update best_mode and confidence at window "boundaries"?
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            best_mode  <= 2'b01;
            confidence <= 8'b0;
        end else if (window_complete) begin
            best_mode <= min_mode;
            
            // Confidence based on margin between best and second best
            // Higher margin = higher confidence
            if (second_ema > min_ema) begin
                // Normalize margin to 0-255 range
                // (second - min) / second * 255
                confidence <= ((second_ema - min_ema) > 12'hFF) ? 
                              8'hFF : (second_ema - min_ema);
            end else begin
                confidence <= 8'b0;
            end
        end
    end
    
    // Debug output
    `ifdef SIMULATION
    always @(posedge clk) begin
        if (window_complete) begin
            $display("[CPI_MON] mode=%0d cycles=%0d insts=%0d CPI=%0d.%0d | EMA: P3=%0d P5=%0d P7=%0d | best=%0d conf=%0d",
                     current_mode, cycle_count, inst_count,
                     current_cpi >> 4, (current_cpi & 4'hF) * 10 / 16,
                     ema_cpi_p3, ema_cpi_p5, ema_cpi_p7,
                     best_mode, confidence);
        end
    end
    `endif

endmodule