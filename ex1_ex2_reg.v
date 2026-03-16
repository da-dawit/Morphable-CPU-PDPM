// EX1/EX2 Pipeline Register (for P7 mode)
// Splits execute stage into two stages for higher frequency
//
// EX1: ALU operation begins, operand selection
// EX2: ALU completes, branch resolution
//
// this register is just between EX1 and EX2 stages.
// In P3/P5 modes, this register is bypassed.

module ex1_ex2_reg (
    input  wire        clk,
    input  wire        reset,
    input  wire        stall,      // Hold current values
    input  wire        flush,      // Clear register
    input  wire        bypass,     // Bypass this register (P3/P5 mode)
    
    // EX1 stage inputs
    input  wire [31:0] ex1_pc,
    input  wire [31:0] ex1_pc_plus_4,
    input  wire [31:0] ex1_alu_partial,    // Partial ALU result (if pipelined ALU)
    input  wire [31:0] ex1_operand_a,      // ALU operand A
    input  wire [31:0] ex1_operand_b,      // ALU operand B
    input  wire [31:0] ex1_rs1_val,        // RS1 value for branches (forwarded)
    input  wire [31:0] ex1_rs2_val,        // RS2 value for stores/branches
    input  wire [31:0] ex1_imm,
    input  wire [4:0]  ex1_rs1,
    input  wire [4:0]  ex1_rs2,
    input  wire [4:0]  ex1_rd,
    input  wire [3:0]  ex1_alu_sel,
    input  wire        ex1_mem_wr,
    input  wire        ex1_mem_read,
    input  wire        ex1_reg_write_en,
    input  wire [1:0]  ex1_wb_sel,
    input  wire        ex1_is_branch,
    input  wire        ex1_is_jump,
    input  wire [2:0]  ex1_funct3,
    input  wire        ex1_br_un,
    
    // EX2 stage outputs
    output reg  [31:0] ex2_pc,
    output reg  [31:0] ex2_pc_plus_4,
    output reg  [31:0] ex2_alu_partial,
    output reg  [31:0] ex2_operand_a,
    output reg  [31:0] ex2_operand_b,
    output reg  [31:0] ex2_rs1_val,
    output reg  [31:0] ex2_rs2_val,
    output reg  [31:0] ex2_imm,
    output reg  [4:0]  ex2_rs1,
    output reg  [4:0]  ex2_rs2,
    output reg  [4:0]  ex2_rd,
    output reg  [3:0]  ex2_alu_sel,
    output reg         ex2_mem_wr,
    output reg         ex2_mem_read,
    output reg         ex2_reg_write_en,
    output reg  [1:0]  ex2_wb_sel,
    output reg         ex2_is_branch,
    output reg         ex2_is_jump,
    output reg  [2:0]  ex2_funct3,
    output reg         ex2_br_un,
    output reg         ex2_valid
);

    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            ex2_pc           <= 32'b0;
            ex2_pc_plus_4    <= 32'b0;
            ex2_alu_partial  <= 32'b0;
            ex2_operand_a    <= 32'b0;
            ex2_operand_b    <= 32'b0;
            ex2_rs1_val      <= 32'b0;
            ex2_rs2_val      <= 32'b0;
            ex2_imm          <= 32'b0;
            ex2_rs1          <= 5'b0;
            ex2_rs2          <= 5'b0;
            ex2_rd           <= 5'b0;
            ex2_alu_sel      <= 4'b0;
            ex2_mem_wr       <= 1'b0;
            ex2_mem_read     <= 1'b0;
            ex2_reg_write_en <= 1'b0;
            ex2_wb_sel       <= 2'b0;
            ex2_is_branch    <= 1'b0;
            ex2_is_jump      <= 1'b0;
            ex2_funct3       <= 3'b0;
            ex2_br_un        <= 1'b0;
            ex2_valid        <= 1'b0;
        end else if (!stall) begin
            ex2_pc           <= ex1_pc;
            ex2_pc_plus_4    <= ex1_pc_plus_4;
            ex2_alu_partial  <= ex1_alu_partial;
            ex2_operand_a    <= ex1_operand_a;
            ex2_operand_b    <= ex1_operand_b;
            ex2_rs1_val      <= ex1_rs1_val;
            ex2_rs2_val      <= ex1_rs2_val;
            ex2_imm          <= ex1_imm;
            ex2_rs1          <= ex1_rs1;
            ex2_rs2          <= ex1_rs2;
            ex2_rd           <= ex1_rd;
            ex2_alu_sel      <= ex1_alu_sel;
            ex2_mem_wr       <= ex1_mem_wr;
            ex2_mem_read     <= ex1_mem_read;
            ex2_reg_write_en <= ex1_reg_write_en;
            ex2_wb_sel       <= ex1_wb_sel;
            ex2_is_branch    <= ex1_is_branch;
            ex2_is_jump      <= ex1_is_jump;
            ex2_funct3       <= ex1_funct3;
            ex2_br_un        <= ex1_br_un;
            ex2_valid        <= 1'b1;
        end
    end

endmodule