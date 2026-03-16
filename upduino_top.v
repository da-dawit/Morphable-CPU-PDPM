// UPduino 3.1 Top-Level Wrapper for Morphable RISC-V CPU
// Target: Lattice iCE40 UP5K

module upduino_top (
    // 12MHz oscillator on UPduino
    input  wire       clk_12mhz,
    
    // RGB LED (directly active low on UPduino 3.1)
    output wire       led_red,
    output wire       led_green,
    output wire       led_blue,
    
    // GPIO for mode selection and status
    input  wire       gpio_mode_0,    // Mode select bit 0
    input  wire       gpio_mode_1,    // Mode select bit 1
    input  wire       gpio_reset,     // External reset (directly active low)
    
    // Status outputs
    output wire       gpio_status_0,  // Current mode bit 0
    output wire       gpio_status_1   // Current mode bit 1
);

    
    // CLOCK AND RESET
    wire clk;
    wire reset_n;
    wire reset;
    
    // Use 12MHz directly (can add PLL later for higher speeds)
    assign clk = clk_12mhz;
    
    // Directly assign reset (active high internally)
    assign reset_n = gpio_reset;
    assign reset = ~reset_n;
    
    
    // MODE SELECTION (directly from GPIO)
    wire [1:0] mode_select;
    assign mode_select = {gpio_mode_1, gpio_mode_0};
    
    
    // CPU INSTANCE
    wire [1:0]  current_mode;
    wire        mode_switching;
    wire [31:0] debug_pc;
    wire [31:0] debug_inst;
    wire        debug_reg_write;
    wire [4:0]  debug_rd;
    wire [31:0] debug_rd_data;
    wire [31:0] cycle_count;
    wire [31:0] inst_count;
    wire [31:0] stall_count;
    wire [31:0] flush_count;
    wire [1:0]  predicted_mode;
    wire [7:0]  prediction_confidence;
    
    cpu_morphable_top cpu (
        .clk(clk),
        .reset(reset),
        .mode_select(mode_select),
        .mode_switch_req(1'b0),           // No dynamic switching for now
        .auto_mode_enable(1'b0),          // Disable auto mode for synthesis
        .current_mode(current_mode),
        .mode_switching(mode_switching),
        .debug_pc(debug_pc),
        .debug_inst(debug_inst),
        .debug_reg_write(debug_reg_write),
        .debug_rd(debug_rd),
        .debug_rd_data(debug_rd_data),
        .cycle_count(cycle_count),
        .inst_count(inst_count),
        .stall_count(stall_count),
        .flush_count(flush_count),
        .predicted_mode(predicted_mode),
        .prediction_confidence(prediction_confidence)
    );
    
    
    // STATUS OUTPUTS
    assign gpio_status_0 = current_mode[0];
    assign gpio_status_1 = current_mode[1];
    
    
    // LED DISPLAY (directly active low)
    
    // Show current mode on RGB LED:
    //   P3 (00): Red
    //   P5 (01): Green
    //   P7 (10): Blue
    //   Switching (11): All off (white-ish)
    
    assign led_red   = ~(current_mode == 2'b00);  // Active low
    assign led_green = ~(current_mode == 2'b01);  // Active low
    assign led_blue  = ~(current_mode == 2'b10);  // Active low

endmodule