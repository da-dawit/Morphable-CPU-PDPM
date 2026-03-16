// Hazard Detection Unit
// For P7 mode, we need to check both EX1 (id_ex) and EX2 stages for load-use hazards
// because the pipeline is deeper and data takes longer to be available.

module hazard_unit (
    // From ID/EX register (instruction in EX1 stage)
    input        id_ex_mem_read,     // Is this a load instruction?
    input  [4:0] id_ex_rd,           // Destination register of load
    
    // From EX1/EX2 register (instruction in EX2 stage) - P7 only
    input        ex2_mem_read,       // Is EX2 instruction a load?
    input  [4:0] ex2_rd,             // Destination register in EX2
    input        is_p7_mode,         // P7 mode flag
    
    // From IF/ID register (instruction in ID stage)
    input  [4:0] if_id_rs1,          // Source register 1
    input  [4:0] if_id_rs2,          // Source register 2
    
    // Branch resolution from EX stage
    input        branch_taken,       // Branch was taken (misprediction)
    
    // Stall and flush control outputs
    output reg   pc_stall,           // Stall PC (hold current value)
    output reg   if_id_stall,        // Stall IF/ID register
    output reg   if_id_flush,        // Flush IF/ID register
    output reg   id_ex_flush         // Flush ID/EX register
);

    // Load-use hazard detection for EX1 stage (standard P5 hazard)
    wire load_use_hazard_ex1;
    assign load_use_hazard_ex1 = id_ex_mem_read && 
                                 (id_ex_rd != 5'b0) &&
                                 ((id_ex_rd == if_id_rs1) || (id_ex_rd == if_id_rs2));
    
    // Load-use hazard detection for EX2 stage (P7 only)
    // In P7, we also need to stall if the load is in EX2 and ID needs it
    wire load_use_hazard_ex2;
    assign load_use_hazard_ex2 = is_p7_mode && ex2_mem_read && 
                                 (ex2_rd != 5'b0) &&
                                 ((ex2_rd == if_id_rs1) || (ex2_rd == if_id_rs2));
    
    // Combined load-use hazard
    wire load_use_hazard;
    assign load_use_hazard = load_use_hazard_ex1 || load_use_hazard_ex2;

    always @(*) begin
        // Default: no stall, no flush
        pc_stall    = 1'b0;
        if_id_stall = 1'b0;
        if_id_flush = 1'b0;
        id_ex_flush = 1'b0;
        
        if (load_use_hazard) begin
            // Load-use hazard: stall IF and ID, insert bubble in EX
            pc_stall    = 1'b1;    // Hold PC
            if_id_stall = 1'b1;    // Hold IF/ID
            id_ex_flush = 1'b1;    // Insert NOP into EX stage
        end
        
        if (branch_taken) begin
            // Control hazard: flush both IF/ID and ID/EX (2 wrong instructions)
            // this overrides load-use stall if both happen (branch has priority)
            pc_stall    = 1'b0;    // Don't stall PC (we need to load branch target)
            if_id_stall = 1'b0;    // Don't stall IF/ID
            if_id_flush = 1'b1;    // Flush IF/ID
            id_ex_flush = 1'b1;    // Flush ID/EX
        end
    end

endmodule