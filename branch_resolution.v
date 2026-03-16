// Branch Resolution Unit
// Computes branch outcome in EX stage
//

// MATHEMATICAL FOUNDATION
// Branch Condition Evaluation:
//
// For signed comparison (BLT, BGE):
//   rs1 <_s rs2  <---->  (rs1[31] ∧ ¬rs2[31]) ∨ 
//                    (rs1[31] = rs2[31] ∧ rs1[30:0] < rs2[30:0])
//
// For unsigned comparison (BLTU, BGEU):
//   rs1 <_u rs2  <---->  rs1 < rs2  (simple unsigned comparison)
//
// Branch Instructions:
//   BEQ:  branch if rs1 == rs2
//   BNE:  branch if rs1 != rs2
//   BLT:  branch if rs1 <_s rs2  (signed)
//   BGE:  branch if rs1 >=_s rs2 (signed)
//   BLTU: branch if rs1 <_u rs2  (unsigned)
//   BGEU: branch if rs1 >=_u rs2 (unsigned)
//

// PIPELINEs
// - is_branch: indicates this is a branch instruction
// - is_jump: indicates this is JAL or JALR (always taken)
// - funct3: specifies which branch condition
// - br_un: 1 for unsigned comparison, 0 for signed
// - rs1_val, rs2_val: operand values (possibly forwarded)
//
// Output:
// - branch_taken: 1 if branch/jump should be taken
//


module branch_resolution (
    input  [31:0] rs1_val,      // Value of rs1 (possibly forwarded)
    input  [31:0] rs2_val,      // Value of rs2 (possibly forwarded)
    input  [2:0]  funct3,       // Branch type
    input         br_un,        // Unsigned comparison flag
    input         is_branch,    // This is a branch instruction
    input         is_jump,      // This is a jump (JAL/JALR)
    
    output reg    branch_taken  // Branch/jump should be taken
);

    // comp. results
    wire equal;
    wire less_than_signed;
    wire less_than_unsigned;
    
    // Equality comparison
    assign equal = (rs1_val == rs2_val);
    
    // Signed less-than comparison
    assign less_than_signed = $signed(rs1_val) < $signed(rs2_val);
    
    // Unsigned less-than comparison
    assign less_than_unsigned = rs1_val < rs2_val;
    
    // Select less-than result based on br_un flag
    wire less_than = br_un ? less_than_unsigned : less_than_signed;
    
    // Branch decision logic
    always @(*) begin
        branch_taken = 1'b0;
        
        if (is_jump) begin
            // JAL and JALR are always taken
            branch_taken = 1'b1;
        end
        else if (is_branch) begin
            case (funct3)
                3'b000: branch_taken = equal;           // BEQ
                3'b001: branch_taken = ~equal;          // BNE
                3'b100: branch_taken = less_than;       // BLT (signed via br_un=0)
                3'b101: branch_taken = ~less_than;      // BGE (signed)
                3'b110: branch_taken = less_than;       // BLTU (unsigned via br_un=1)
                3'b111: branch_taken = ~less_than;      // BGEU (unsigned)
                default: branch_taken = 1'b0;
            endcase
        end
    end

endmodule