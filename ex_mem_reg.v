// EX/MEM Pipeline Register
// Captures state between Execute and Memory stages
//
// - ALU result: Used as memory address (for load/store) or passed to WB
// - rd2: Store data (value to write to memory)
// - Control signals for memory operation and writeback
//
// EX/MEM.rd is compared against ID/EX.rs1 and ID/EX.rs2 in forwarding unit.
// Forward condition: (EX/MEM.rd == ID/EX.rs{1,2}) && (EX/MEM.rd != 0) && EX/MEM.reg_write_en

module ex_mem_reg (
    input         clk,
    input         reset,
    input         flush,      // For precise exceptions (optional, not used in basic impl)
    
    // Inputs from EX stage - Data
    input  [31:0] ex_pc_plus_4,
    input  [31:0] ex_alu_result,
    input  [31:0] ex_rd2,           // Store data (forwarded if necessary)
    input  [4:0]  ex_rd,            // Destination register index
    
    // Inputs from EX stage - Control signals
    input         ex_mem_wr,        // Memory write enable
    input         ex_mem_read,      // Memory read enable
    input         ex_reg_write_en,  // Register write enable
    input  [1:0]  ex_wb_sel,        // Writeback select
    input  [2:0]  ex_funct3,        // Memory access size (LB/LH/LW, SB/SH/SW)
    
    // Outputs to MEM stage - Data
    output reg [31:0] mem_pc_plus_4,
    output reg [31:0] mem_alu_result,
    output reg [31:0] mem_rd2,
    output reg [4:0]  mem_rd,
    
    // Outputs to MEM stage - Control signals
    output reg        mem_mem_wr,
    output reg        mem_mem_read,
    output reg        mem_reg_write_en,
    output reg [1:0]  mem_wb_sel,
    output reg [2:0]  mem_funct3
);

    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            // Initialize/flush to NOP state
            mem_pc_plus_4    <= 32'b0;
            mem_alu_result   <= 32'b0;
            mem_rd2          <= 32'b0;
            mem_rd           <= 5'b0;
            
            mem_mem_wr       <= 1'b0;
            mem_mem_read     <= 1'b0;
            mem_reg_write_en <= 1'b0;
            mem_wb_sel       <= 2'b0;
            mem_funct3       <= 3'b0;
        end
        else begin
            // Normal operation - always latch (no stall in MEM stage typically)
            mem_pc_plus_4    <= ex_pc_plus_4;
            mem_alu_result   <= ex_alu_result;
            mem_rd2          <= ex_rd2;
            mem_rd           <= ex_rd;
            
            mem_mem_wr       <= ex_mem_wr;
            mem_mem_read     <= ex_mem_read;
            mem_reg_write_en <= ex_reg_write_en;
            mem_wb_sel       <= ex_wb_sel;
            mem_funct3       <= ex_funct3;
        end
    end

endmodule