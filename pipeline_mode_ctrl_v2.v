// // Pipeline Mode Controller V2
// // Manages switching between P3, P5, and P7 modes
// //
// // - P3: 3-stage pipeline (IF, ID+EX, MEM+WB) - lowest latency, best for branches
// // - P5: 5-stage pipeline (IF, ID, EX, MEM, WB) - balanced, standard RISC
// // - P7: 7-stage pipeline (IF1, IF2, ID, EX1, EX2, MEM, WB) - highest throughput
// //
// //encodings
// // - 2'b00: P3 mode (3 stages)
// // - 2'b01: P5 mode (5 stages) 
// // - 2'b10: P7 mode (7 stages)
// // - 2'b11: Reserved (d.c.)

// module pipeline_mode_ctrl_v2 (
//     input  wire        clk,
//     input  wire        reset,
    
//     // Mode selection inputs
//     input  wire [1:0]  mode_select,        // Target mode (00=P3, 01=P5, 10=P7)
//     input  wire        mode_switch_req,    // Request to switch modes
    
//     // Auto mode (perceptron-driven)
//     input  wire        auto_mode_enable,   // Enable perceptron-based switching
//     input  wire [1:0]  predicted_mode,     // Mode predicted by perceptron
//     input  wire [7:0]  prediction_confidence, // Confidence level
    
//     // Mode outputs
//     output reg  [1:0]  current_mode,       // Current active mode
//     output wire        is_p3_mode,
//     output wire        is_p5_mode,
//     output wire        is_p7_mode,
    
//     // Stage bypass controls
//     // P3: bypass IF2, EX2 stages (3 effective stages)
//     // P5: bypass IF2, EX2 stages partially (5 effective stages)
//     // P7: no bypass (all 7 stages active)
//     output wire        bypass_if2,         // Bypass IF2 stage
//     output wire        bypass_id_ex,       // Combine ID+EX in P3
//     output wire        bypass_ex2,         // Bypass EX2 stage
//     output wire        bypass_ex_mem,      // Combine EX+MEM in P3
    
//     // Mode switch control
//     output reg         mode_switch_flush,  // Flush pipeline for mode switch
//     output reg         mode_switching,     // Mode switch in progress
    
//     // Statistics for perceptron training
//     output reg [31:0]  cycles_in_p3,
//     output reg [31:0]  cycles_in_p5,
//     output reg [31:0]  cycles_in_p7,
//     output reg [15:0]  mode_switches
// );

//     // Mode encoding
//     localparam MODE_P3 = 2'b00;
//     localparam MODE_P5 = 2'b01;
//     localparam MODE_P7 = 2'b10;
    
//     // FSM states
//     localparam IDLE       = 2'b00;
//     localparam FLUSH_WAIT = 2'b01;
//     localparam SWITCH     = 2'b10;
    
//     // Confidence threshold for auto switching
//     localparam CONF_THRESHOLD = 8'd64;  // Only switch if confidence > 25%
    
//     reg [1:0] switch_state;
//     reg [3:0] flush_counter;  // Longer for P7
//     reg [1:0] target_mode;
    
//     // Mode decode outputs
//     assign is_p3_mode = (current_mode == MODE_P3);
//     assign is_p5_mode = (current_mode == MODE_P5);
//     assign is_p7_mode = (current_mode == MODE_P7);
    
//     // P3: Maximum bypass - 3 effective stages
//     // P5: Moderate bypass - 5 effective stages  
//     // P7: No bypass - all 7 stages active
//     assign bypass_if2    = is_p3_mode || is_p5_mode;  // IF2 only in P7
//     assign bypass_id_ex  = is_p3_mode;                 // ID+EX combined in P3
//     assign bypass_ex2    = is_p3_mode || is_p5_mode;  // EX2 only in P7
//     assign bypass_ex_mem = is_p3_mode;                 // EX+MEM combined in P3
    
//     // Determine flush cycles needed based on target mode
//     function [3:0] get_flush_cycles;
//         input [1:0] from_mode;
//         input [1:0] to_mode;
//         begin
//             // Need enough cycles to drain the deeper pipeline
//             case (from_mode)
//                 MODE_P3: get_flush_cycles = (to_mode == MODE_P7) ? 4'd7 : 4'd5;
//                 MODE_P5: get_flush_cycles = (to_mode == MODE_P7) ? 4'd7 : 4'd5;
//                 MODE_P7: get_flush_cycles = 4'd7;
//                 default: get_flush_cycles = 4'd5;
//             endcase
//         end
//     endfunction
    
//     // Auto mode switching logic
//     wire auto_switch_trigger;
//     wire [1:0] effective_target;
    
//     assign auto_switch_trigger = auto_mode_enable && 
//                                   (prediction_confidence > CONF_THRESHOLD) &&
//                                   (predicted_mode != current_mode) &&
//                                   (switch_state == IDLE);
    
//     assign effective_target = auto_mode_enable ? predicted_mode : mode_select;
    
//     // Mode switching FSM
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             current_mode      <= mode_select;  // Use selected mode on reset
//             switch_state      <= IDLE;
//             flush_counter     <= 4'b0;
//             target_mode       <= mode_select;
//             mode_switch_flush <= 1'b0;
//             mode_switching    <= 1'b0;
//             cycles_in_p3      <= 32'b0;
//             cycles_in_p5      <= 32'b0;
//             cycles_in_p7      <= 32'b0;
//             mode_switches     <= 16'b0;
//         end else begin
//             // Statistics tracking
//             case (current_mode)
//                 MODE_P3: cycles_in_p3 <= cycles_in_p3 + 1;
//                 MODE_P5: cycles_in_p5 <= cycles_in_p5 + 1;
//                 MODE_P7: cycles_in_p7 <= cycles_in_p7 + 1;
//             endcase
            
//             case (switch_state)
//                 IDLE: begin
//                     mode_switch_flush <= 1'b0;
//                     mode_switching    <= 1'b0;
                    
//                     // Manual switch request or auto switch
//                     if ((mode_switch_req && (mode_select != current_mode)) ||
//                         auto_switch_trigger) begin
//                         target_mode       <= effective_target;
//                         switch_state      <= FLUSH_WAIT;
//                         mode_switching    <= 1'b1;
//                         mode_switch_flush <= 1'b1;
//                         flush_counter     <= get_flush_cycles(current_mode, effective_target);
//                     end
//                 end
                
//                 FLUSH_WAIT: begin
//                     mode_switch_flush <= 1'b0;
                    
//                     if (flush_counter > 0)
//                         flush_counter <= flush_counter - 1;
//                     else
//                         switch_state <= SWITCH;
//                 end
                
//                 SWITCH: begin
//                     current_mode   <= target_mode;
//                     switch_state   <= IDLE;
//                     mode_switching <= 1'b0;
//                     mode_switches  <= mode_switches + 1;
//                 end
                
//                 default: switch_state <= IDLE;
//             endcase
//         end
//     end

// endmodule

//NEW
// Pipeline Mode Controller V3
// Manages switching between P3, P5, P7 modes AND clock speed selection
//
// NEW in V3:
//   - Outputs predicted_clk_idx for clock frequency scaling
//   - Autonomous evaluation mode: cycles through configs to find optimal
//   - Integrates with joint perceptron predictor V2
//
// Mode encoding: 00=P3, 01=P5, 10=P7
// Clock indices: 0=1.0x, 1=1.1x, 2=1.2x, 3=1.3x, 4=1.4x, 5=1.5x
// Physical constraints: P3 max=1, P5 max=3, P7 max=5

module pipeline_mode_ctrl_v3 (
    input  wire        clk,
    input  wire        reset,

    // Manual mode selection
    input  wire [1:0]  mode_select,
    input  wire        mode_switch_req,

    // Auto mode (perceptron-driven)
    input  wire        auto_mode_enable,
    input  wire [1:0]  predicted_mode,
    input  wire [2:0]  predicted_clk_idx,     // NEW: clock prediction
    input  wire [7:0]  prediction_confidence,

    // Mode outputs
    output reg  [1:0]  current_mode,
    output wire        is_p3_mode,
    output wire        is_p5_mode,
    output wire        is_p7_mode,

    // Clock output (active clock multiplier index)
    output reg  [2:0]  current_clk_idx,       // NEW: 0-5

    // Stage bypass controls
    output wire        bypass_if2,
    output wire        bypass_id_ex,
    output wire        bypass_ex2,
    output wire        bypass_ex_mem,

    // Mode switch control
    output reg         mode_switch_flush,
    output reg         mode_switching,

    // Statistics
    output reg [31:0]  cycles_in_p3,
    output reg [31:0]  cycles_in_p5,
    output reg [31:0]  cycles_in_p7,
    output reg [15:0]  mode_switches
);

    localparam MODE_P3 = 2'b00;
    localparam MODE_P5 = 2'b01;
    localparam MODE_P7 = 2'b10;

    // FSM states
    localparam IDLE       = 2'b00;
    localparam FLUSH_WAIT = 2'b01;
    localparam SWITCH     = 2'b10;

    // Confidence threshold for auto switching
    localparam CONF_THRESHOLD = 8'd32;

    reg [1:0] switch_state;
    reg [3:0] flush_counter;
    reg [1:0] target_mode;
    reg [2:0] target_clk_idx;

    // Mode decode
    assign is_p3_mode = (current_mode == MODE_P3);
    assign is_p5_mode = (current_mode == MODE_P5);
    assign is_p7_mode = (current_mode == MODE_P7);

    // Bypass signals
    assign bypass_if2    = is_p3_mode || is_p5_mode;
    assign bypass_id_ex  = is_p3_mode;
    assign bypass_ex2    = is_p3_mode || is_p5_mode;
    assign bypass_ex_mem = is_p3_mode;

    // Flush cycles needed
    function [3:0] get_flush_cycles;
        input [1:0] from_mode;
        input [1:0] to_mode;
        begin
            case (from_mode)
                MODE_P3: get_flush_cycles = (to_mode == MODE_P7) ? 4'd7 : 4'd5;
                MODE_P5: get_flush_cycles = (to_mode == MODE_P7) ? 4'd7 : 4'd5;
                MODE_P7: get_flush_cycles = 4'd7;
                default: get_flush_cycles = 4'd5;
            endcase
        end
    endfunction

    // Max clock index per mode
    function [2:0] max_clk;
        input [1:0] mode;
        begin
            case (mode)
                MODE_P3: max_clk = 3'd1;
                MODE_P5: max_clk = 3'd3;
                MODE_P7: max_clk = 3'd5;
                default: max_clk = 3'd3;
            endcase
        end
    endfunction

    // Auto switch trigger: only when mode changes (clock changes don't need flush)
    wire mode_change_requested;
    wire clk_change_only;
    wire auto_switch_trigger;

    assign mode_change_requested = (predicted_mode != current_mode);
    assign clk_change_only = !mode_change_requested &&
                              (predicted_clk_idx != current_clk_idx) &&
                              (predicted_clk_idx <= max_clk(current_mode));

    assign auto_switch_trigger = auto_mode_enable &&
                                  (prediction_confidence > CONF_THRESHOLD) &&
                                  mode_change_requested &&
                                  (switch_state == IDLE);

    // Switching FSM
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_mode      <= mode_select;
            current_clk_idx   <= max_clk(mode_select);  // Start at max clock
            switch_state      <= IDLE;
            flush_counter     <= 4'b0;
            target_mode       <= mode_select;
            target_clk_idx    <= 3'd3;
            mode_switch_flush <= 1'b0;
            mode_switching    <= 1'b0;
            cycles_in_p3      <= 32'b0;
            cycles_in_p5      <= 32'b0;
            cycles_in_p7      <= 32'b0;
            mode_switches     <= 16'b0;
        end else begin
            // Statistics
            case (current_mode)
                MODE_P3: cycles_in_p3 <= cycles_in_p3 + 1;
                MODE_P5: cycles_in_p5 <= cycles_in_p5 + 1;
                MODE_P7: cycles_in_p7 <= cycles_in_p7 + 1;
            endcase

            case (switch_state)
                IDLE: begin
                    mode_switch_flush <= 1'b0;
                    mode_switching    <= 1'b0;

                    // Clock-only changes: no flush needed!
                    if (auto_mode_enable && clk_change_only) begin
                        current_clk_idx <= predicted_clk_idx;
                    end

                    // Mode changes require pipeline flush
                    if ((mode_switch_req && (mode_select != current_mode)) ||
                        auto_switch_trigger) begin
                        target_mode       <= auto_mode_enable ? predicted_mode : mode_select;
                        target_clk_idx    <= auto_mode_enable ? predicted_clk_idx :
                                             max_clk(mode_select);
                        switch_state      <= FLUSH_WAIT;
                        mode_switching    <= 1'b1;
                        mode_switch_flush <= 1'b1;
                        flush_counter     <= get_flush_cycles(current_mode,
                                             auto_mode_enable ? predicted_mode : mode_select);
                    end
                end

                FLUSH_WAIT: begin
                    mode_switch_flush <= 1'b0;
                    if (flush_counter > 0)
                        flush_counter <= flush_counter - 1;
                    else
                        switch_state <= SWITCH;
                end

                SWITCH: begin
                    current_mode    <= target_mode;
                    current_clk_idx <= (target_clk_idx > max_clk(target_mode)) ?
                                        max_clk(target_mode) : target_clk_idx;
                    switch_state    <= IDLE;
                    mode_switching  <= 1'b0;
                    mode_switches   <= mode_switches + 1;
                end

                default: switch_state <= IDLE;
            endcase
        end
    end

endmodule