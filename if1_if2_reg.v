// IF1/IF2 Pipeline Register (for P7 mode)
// Splits instruction fetch into two stages for higher frequency!
//
// IF1: PC generation, branch target calculation
// IF2: Instruction memory access, instruction available
//
// This register sits between IF1 and IF2 stages.
// In P3/P5 modes, this register is bypassed.

module if1_if2_reg (
    input  wire        clk,
    input  wire        reset,
    input  wire        stall,      // Hold current values
    input  wire        flush,      // Clear register (branch misprediction)
    input  wire        bypass,     // Bypass this register (P3/P5 mode)
    
    // IF1 stage inputs
    input  wire [31:0] if1_pc,
    input  wire [31:0] if1_pc_plus_4,
    input  wire [31:0] if1_branch_target,  // Predicted branch target
    input  wire        if1_branch_predict, // Branch prediction
    
    // IF2 stage outputs
    output reg  [31:0] if2_pc,
    output reg  [31:0] if2_pc_plus_4,
    output reg  [31:0] if2_branch_target,
    output reg         if2_branch_predict,
    output reg         if2_valid           // Valid instruction in IF2
);

    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            if2_pc             <= 32'b0;
            if2_pc_plus_4      <= 32'b0;
            if2_branch_target  <= 32'b0;
            if2_branch_predict <= 1'b0;
            if2_valid          <= 1'b0;
        end else if (bypass) begin
            // In bypass mode, pass through immediately (combinational)
            if2_pc             <= if1_pc;
            if2_pc_plus_4      <= if1_pc_plus_4;
            if2_branch_target  <= if1_branch_target;
            if2_branch_predict <= if1_branch_predict;
            if2_valid          <= 1'b1;
        end else if (!stall) begin
            if2_pc             <= if1_pc;
            if2_pc_plus_4      <= if1_pc_plus_4;
            if2_branch_target  <= if1_branch_target;
            if2_branch_predict <= if1_branch_predict;
            if2_valid          <= 1'b1;
        end
    end

endmodule