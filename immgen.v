// Immediate Generator
// Extracts and sign-extends immediate values from instruction

// I-type: inst[31:20] → sign-extend to 32 bits
//   Used by: ADDI, SLTI, ANDI, ORI, XORI, LW, JALR
//   imm[11:0] = inst[31:20]
//
// S-type: {inst[31:25], inst[11:7]} → sign-extend to 32 bits
//   Used by: SW, SH, SB
//   imm[11:0] = {inst[31:25], inst[11:7]}
//
// B-type: {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0} → sign-extend
//   Used by: BEQ, BNE, BLT, BGE, BLTU, BGEU
//   imm[12:1] = {inst[31], inst[7], inst[30:25], inst[11:8]}
//   imm[0] = 0 (branches are 2-byte aligned)
//
// U-type: {inst[31:12], 12'b0}
//   Used by: LUI, AUIPC
//   imm[31:12] = inst[31:12], imm[11:0] = 0
//
// J-type: {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0} → sign-extend
//   Used by: JAL
//   imm[20:1] = {inst[31], inst[19:12], inst[20], inst[30:21]}
//   imm[0] = 0 (jumps are 2-byte aligned)

module immgen (
    input  [31:0] inst,
    output reg [31:0] imm
);

    wire [6:0] opcode = inst[6:0];

    always @(*) begin
        case (opcode)
            // I-type: ADDI, SLTI, etc., Load, JALR
            7'b0010011,  // I-type ALU
            7'b0000011,  // Load
            7'b1100111:  // JALR
                imm = {{20{inst[31]}}, inst[31:20]};
            
            // S-type: Store
            7'b0100011:
                imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            
            // B-type: Branch
            7'b1100011:
                imm = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
            
            // U-type: LUI, AUIPC
            7'b0110111,  // LUI
            7'b0010111:  // AUIPC
                imm = {inst[31:12], 12'b0};
            
            // J-type: JAL
            7'b1101111:
                imm = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
            
            default:
                imm = 32'b0;
        endcase
    end

endmodule