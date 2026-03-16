// Forwarding Unit
// Handles RAW (Read After Write) data hazards by forwarding values
// from later pipeline stages back to the EX stage
//
// Load instructions, we cannot forward from EX/MEM stage
// because the ALU result in EX/MEM is the memory addr, not the loaded DATA.
// Load data is only available after the MEM stage completes, so we MUST MUST
// either stall (handled by hazard unit) or forward from MEM/WB stage.
//
// For P7 mode, we also need to check EX2 stage for forwarding.

module forwarding_unit (
    // Source register indices from ID/EX stage (current instruction in EX)
    input  wire [4:0] id_ex_rs1,          // Source register 1
    input  wire [4:0] id_ex_rs2,          // Source register 2
    
    // P7: Destination register from EX1/EX2 stage (instruction ahead by 0.5 in P7)
    input  wire [4:0] ex2_rd,             // Destination register in EX2 stage
    input  wire       ex2_reg_write_en,   // Will EX2 stage write to register?
    input  wire       ex2_mem_read,       // Is EX2 stage instruction a load?
    input  wire       is_p7_mode,         // P7 mode flag
    
    // Destination register from EX/MEM stage (instruction ahead by 1)
    input  wire [4:0] ex_mem_rd,          // Destination register in MEM stage
    input  wire       ex_mem_reg_write_en, // Will MEM stage write to register?
    input  wire       ex_mem_mem_read,     // Is MEM stage instruction a load?
    
    // Destination register from MEM/WB stage (instruction ahead by 2)
    input  wire [4:0] mem_wb_rd,          // Destination register in WB stage
    input  wire       mem_wb_reg_write_en, // Will WB stage write to register?
    
    // Forwarding control signals
    // 00: No forwarding (use value from ID/EX register)
    // 01: Forward from MEM/WB stage
    // 10: Forward from EX/MEM stage (ALU result only, NOT for loads!)
    // 11: Forward from EX2 stage (P7 only, ALU result, NOT for loads!)
    output reg  [1:0] forward_a,     // Forwarding mux select for rs1)
    output reg  [1:0] forward_b      // Forwarding mux select for rs2
);

    // Forwarding logic for operand A (rs1)
    always @(*) begin
        // Default: no forwarding
        forward_a = 2'b00;
        
        // P7: EX2 hazard (priority 0 - most recent in P7)
        if (is_p7_mode && ex2_reg_write_en && (ex2_rd != 5'b0) && (ex2_rd == id_ex_rs1) && !ex2_mem_read) begin
            forward_a = 2'b11;  // Forward from EX2 (P7 only)
        end
        // EX/MEM hazard (priority 1)
        else if (ex_mem_reg_write_en && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs1) && !ex_mem_mem_read) begin
            forward_a = 2'b10;  // Forward from EX/MEM (ALU result)
        end
        // MEM/WB hazard (priority 2 - older value)
        else if (mem_wb_reg_write_en && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs1)) begin
            forward_a = 2'b01;  // Forward from MEM/WB
        end
    end
    
    // Forwarding logic for rs2
    always @(*) begin
        // Default: no forwarding
        forward_b = 2'b00;
        
        // P7: EX2 hazard (priority 0 - most recent in P7)
        if (is_p7_mode && ex2_reg_write_en && (ex2_rd != 5'b0) && (ex2_rd == id_ex_rs2) && !ex2_mem_read) begin
            forward_b = 2'b11;  // Forward from EX2 (P7 only)
        end
        // EX/MEM hazard (priority 1) - NOT for loads!
        else if (ex_mem_reg_write_en && (ex_mem_rd != 5'b0) && (ex_mem_rd == id_ex_rs2) && !ex_mem_mem_read) begin
            forward_b = 2'b10;  // Forward from EX/MEM (ALU result)
        end
        // MEM/WB hazard (priority 2)
        else if (mem_wb_reg_write_en && (mem_wb_rd != 5'b0) && (mem_wb_rd == id_ex_rs2)) begin
            forward_b = 2'b01;  // Forward from MEM/WB
        end
    end

endmodule