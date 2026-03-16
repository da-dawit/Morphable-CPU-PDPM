// MEM/WB Pipeline Register
// Captures state between Memory and Writeback stages
//
//FINAL PIPELINE REGISTER BEFORE WB
// - ALU result: Passed through for R-type and I-type ALU operations
// - Memory data: Read data from DMEM for load instructions
// - PC+4: Return address for JAL/JALR
// - wb_sel: Selects which value to write back
//
// MEM/WB.rd is compared against ID/EX.rs1 and ID/EX.rs2 in forwarding unit.
// This is the "MEM hazard" - data from 2 instructions ago.
// Priority: EX hazard (1 instruction ago) takes precedence over MEM hazard.

module mem_wb_reg (
    input         clk,
    input         reset,
    
    // Inputs from MEM stage - Data
    input  [31:0] mem_pc_plus_4,
    input  [31:0] mem_alu_result,
    input  [31:0] mem_read_data,    // Data read from memory
    input  [4:0]  mem_rd,           // Destination register index
    
    // Inputs from MEM stage - Control signals
    input         mem_reg_write_en, // Register write enable
    input  [1:0]  mem_wb_sel,       // Writeback select
    
    // Outputs to WB stage - Data
    output reg [31:0] wb_pc_plus_4,
    output reg [31:0] wb_alu_result,
    output reg [31:0] wb_read_data,
    output reg [4:0]  wb_rd,
    
    // Outputs to WB stage - Control signals
    output reg        wb_reg_write_en,
    output reg [1:0]  wb_wb_sel
);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Initialize to NOP state
            wb_pc_plus_4    <= 32'b0;
            wb_alu_result   <= 32'b0;
            wb_read_data    <= 32'b0;
            wb_rd           <= 5'b0;
            
            wb_reg_write_en <= 1'b0;
            wb_wb_sel       <= 2'b0;
        end
        else begin
            // Normal operation - always latch (no stall in WB stage)
            wb_pc_plus_4    <= mem_pc_plus_4;
            wb_alu_result   <= mem_alu_result;
            wb_read_data    <= mem_read_data;
            wb_rd           <= mem_rd;
            
            wb_reg_write_en <= mem_reg_write_en;
            wb_wb_sel       <= mem_wb_sel;
        end
    end

endmodule