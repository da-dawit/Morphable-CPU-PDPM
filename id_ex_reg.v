// ID/EX Pipeline Register
module id_ex_reg (
    input         clk,
    input         reset,
    input         stall,
    input         flush,
    input  [31:0] id_pc,
    input  [31:0] id_pc_plus_4,
    input  [31:0] id_rd1,
    input  [31:0] id_rd2,
    input  [31:0] id_imm,
    input  [4:0]  id_rs1,
    input  [4:0]  id_rs2,
    input  [4:0]  id_rd,
    input  [3:0]  id_alu_sel,
    input         id_a_sel,
    input         id_b_sel,
    input         id_mem_wr,
    input         id_mem_read,
    input         id_reg_write_en,
    input  [1:0]  id_wb_sel,
    input         id_pc_sel,
    input         id_br_un,
    input  [2:0]  id_funct3,
    input         id_is_branch,
    input         id_is_jump,
    output reg [31:0] ex_pc,
    output reg [31:0] ex_pc_plus_4,
    output reg [31:0] ex_rd1,
    output reg [31:0] ex_rd2,
    output reg [31:0] ex_imm,
    output reg [4:0]  ex_rs1,
    output reg [4:0]  ex_rs2,
    output reg [4:0]  ex_rd,
    output reg [3:0]  ex_alu_sel,
    output reg        ex_a_sel,
    output reg        ex_b_sel,
    output reg        ex_mem_wr,
    output reg        ex_mem_read,
    output reg        ex_reg_write_en,
    output reg [1:0]  ex_wb_sel,
    output reg        ex_pc_sel,
    output reg        ex_br_un,
    output reg [2:0]  ex_funct3,
    output reg        ex_is_branch,
    output reg        ex_is_jump
);

    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            ex_pc           <= 32'b0;
            ex_pc_plus_4    <= 32'b0;
            ex_rd1          <= 32'b0;
            ex_rd2          <= 32'b0;
            ex_imm          <= 32'b0;
            ex_rs1          <= 5'b0;
            ex_rs2          <= 5'b0;
            ex_rd           <= 5'b0;
            ex_alu_sel      <= 4'b0;
            ex_a_sel        <= 1'b0;
            ex_b_sel        <= 1'b0;
            ex_mem_wr       <= 1'b0;
            ex_mem_read     <= 1'b0;
            ex_reg_write_en <= 1'b0;
            ex_wb_sel       <= 2'b0;
            ex_pc_sel       <= 1'b0;
            ex_br_un        <= 1'b0;
            ex_funct3       <= 3'b0;
            ex_is_branch    <= 1'b0;
            ex_is_jump      <= 1'b0;
        end
        else if (!stall) begin
            ex_pc           <= id_pc;
            ex_pc_plus_4    <= id_pc_plus_4;
            ex_rd1          <= id_rd1;
            ex_rd2          <= id_rd2;
            ex_imm          <= id_imm;
            ex_rs1          <= id_rs1;
            ex_rs2          <= id_rs2;
            ex_rd           <= id_rd;
            ex_alu_sel      <= id_alu_sel;
            ex_a_sel        <= id_a_sel;
            ex_b_sel        <= id_b_sel;
            ex_mem_wr       <= id_mem_wr;
            ex_mem_read     <= id_mem_read;
            ex_reg_write_en <= id_reg_write_en;
            ex_wb_sel       <= id_wb_sel;
            ex_pc_sel       <= id_pc_sel;
            ex_br_un        <= id_br_un;
            ex_funct3       <= id_funct3;
            ex_is_branch    <= id_is_branch;
            ex_is_jump      <= id_is_jump;
        end
    end

endmodule