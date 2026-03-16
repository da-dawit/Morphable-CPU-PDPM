// Pipeline Control Unit (Decoder)
// Modified from single-cycle control for pipelined execution
//
// A difference from single cycle is:
// In single-cycle, branch decision (pc_sel) was computed here based on br_eq, br_l.
// In pipeline, branch comparison happens in EX stage (after decode).
// So we output is_branch and is_jump flags, and actual pc_sel is computed in EX.
//
// - Extracts opcode, rd, rs1, rs2, funct3, funct7
// - Generates control signals based on opcode
// - Does NOT make branch decisions (that's in EX stage)

module control_pipeline (
    input  [31:0] inst,         // Instruction from IF/ID register
    
    // Instruction field outputs
    output [6:0]  opcode,
    output [4:0]  rd,
    output [4:0]  rs1,
    output [4:0]  rs2,
    output [2:0]  funct3,
    output [6:0]  funct7,
    
    // Control signal outputs
    output reg       reg_write_en,  // Write to register file
    output reg       mem_wr,        // Write to data memory
    output reg       mem_read,      // Read from data memory (for hazard detection)
    output reg       a_sel,         // ALU input A: 0=rs1, 1=PC
    output reg       b_sel,         // ALU input B: 0=rs2, 1=imm
    output reg [3:0] alu_sel,       // ALU operation
    output reg [1:0] wb_sel,        // Writeback: 00=MEM, 01=ALU, 10=PC+4
    output reg       br_un,         // Unsigned branch comparison
    output reg       is_branch,     // This is a branch instruction
    output reg       is_jump,       // This is a jump instruction (JAL/JALR)
    output reg       is_jalr        // Specifically JALR (target from rs1+imm)
);

    // Extract instruction fields (always, regardless of instruction type)
    assign opcode = inst[6:0];
    assign rd     = inst[11:7];
    assign funct3 = inst[14:12];
    assign rs1    = inst[19:15];
    assign rs2    = inst[24:20];
    assign funct7 = inst[31:25];

    // Control signal generation
    always @(*) begin
        // Default values (NOP-like)
        reg_write_en = 1'b0;
        mem_wr       = 1'b0;
        mem_read     = 1'b0;
        a_sel        = 1'b0;  // rs1
        b_sel        = 1'b0;  // rs2
        alu_sel      = 4'b0000;  // ADD
        wb_sel       = 2'b01;    // ALU result
        br_un        = 1'b0;
        is_branch    = 1'b0;
        is_jump      = 1'b0;
        is_jalr      = 1'b0;
        
        case (opcode)
            
            // R-type: ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA
            
            7'b0110011: begin
                reg_write_en = 1'b1;
                wb_sel       = 2'b01;  // ALU result
                
                case ({funct7, funct3})
                    10'b0000000_000: alu_sel = 4'b0000; // ADD
                    10'b0100000_000: alu_sel = 4'b0001; // SUB
                    10'b0000000_111: alu_sel = 4'b0010; // AND
                    10'b0000000_110: alu_sel = 4'b0011; // OR
                    10'b0000000_100: alu_sel = 4'b0100; // XOR
                    10'b0000000_010: alu_sel = 4'b0101; // SLT
                    10'b0000000_011: begin
                        alu_sel = 4'b0110;              // SLTU
                        br_un   = 1'b1;
                    end
                    10'b0000000_001: alu_sel = 4'b0111; // SLL
                    10'b0000000_101: alu_sel = 4'b1000; // SRL
                    10'b0100000_101: alu_sel = 4'b1001; // SRA
                    default:        alu_sel = 4'b0000;
                endcase
            end
            
            
            // I-type ALU: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI
            
            7'b0010011: begin
                reg_write_en = 1'b1;
                b_sel        = 1'b1;  // Immediate
                wb_sel       = 2'b01; // ALU result
                
                case (funct3)
                    3'b000: alu_sel = 4'b0000; // ADDI
                    3'b111: alu_sel = 4'b0010; // ANDI
                    3'b110: alu_sel = 4'b0011; // ORI
                    3'b100: alu_sel = 4'b0100; // XORI
                    3'b010: alu_sel = 4'b0101; // SLTI
                    3'b011: begin
                        alu_sel = 4'b0110;     // SLTIU
                        br_un   = 1'b1;
                    end
                    3'b001: alu_sel = 4'b0111; // SLLI
                    3'b101: begin
                        case (inst[30])
                            1'b0: alu_sel = 4'b1000; // SRLI
                            1'b1: alu_sel = 4'b1001; // SRAI
                        endcase
                    end
                    default: alu_sel = 4'b0000;
                endcase
            end
            
            
            // LOAD: LB, LH, LW, LBU, LHU
            
            7'b0000011: begin
                reg_write_en = 1'b1;
                mem_read     = 1'b1;  // Important for hazard detection!
                b_sel        = 1'b1;  // Immediate (offset)
                alu_sel      = 4'b0000; // ADD (base + offset)
                wb_sel       = 2'b00; // Memory read data
            end
            
            
            // STORE: SB, SH, SW
            
            7'b0100011: begin
                mem_wr  = 1'b1;
                b_sel   = 1'b1;       // Immediate (offset)
                alu_sel = 4'b0000;    // ADD (base + offset)
            end
            
            
            // BRANCH: BEQ, BNE, BLT, BGE, BLTU, BGEU
            
            7'b1100011: begin
                is_branch = 1'b1;
                a_sel     = 1'b1;     // PC (for target calculation)
                b_sel     = 1'b1;     // Immediate (offset)
                alu_sel   = 4'b0000;  // ADD (PC + offset)
                
                // Set unsigned flag for BLTU, BGEU
                case (funct3)
                    3'b110, 3'b111: br_un = 1'b1;  // BLTU, BGEU
                    default:        br_un = 1'b0;
                endcase
            end
            
            
            // JAL: Jump and Link
            
            7'b1101111: begin
                reg_write_en = 1'b1;
                is_jump      = 1'b1;
                a_sel        = 1'b1;  // PC
                b_sel        = 1'b1;  // Immediate (offset)
                alu_sel      = 4'b0000; // ADD (PC + offset)
                wb_sel       = 2'b10; // PC + 4 (return address)
            end
            
            
            // JALR: Jump and Link Register
            
            7'b1100111: begin
                reg_write_en = 1'b1;
                is_jump      = 1'b1;
                is_jalr      = 1'b1;
                a_sel        = 1'b0;  // rs1
                b_sel        = 1'b1;  // Immediate (offset)
                alu_sel      = 4'b0000; // ADD (rs1 + offset)
                wb_sel       = 2'b10; // PC + 4 (return address)
            end
            
            
            // LUI: Load Upper Immediate
            
            7'b0110111: begin
                reg_write_en = 1'b1;
                b_sel        = 1'b1;  // Immediate (already shifted by immgen)
                alu_sel      = 4'b0000; // ADD (0 + imm, since a_sel=0 and rs1 effect zeroed)
                wb_sel       = 2'b01; // ALU result
                // My approach: ALU should have path for imm passthrough.
                // For now, assume rs1=x0 in well-formed LUI, or handle in ALU mux.
            end
            
            
            // AUIPC: Add Upper Immediate to PC
            
            7'b0010111: begin
                reg_write_en = 1'b1;
                a_sel        = 1'b1;  // PC
                b_sel        = 1'b1;  // Immediate (already shifted)
                alu_sel      = 4'b0000; // ADD (PC + imm)
                wb_sel       = 2'b01; // ALU result
            end
            
            default: begin
                // Unknown instruction - treat as NOP
                reg_write_en = 1'b0;
                mem_wr       = 1'b0;
                mem_read     = 1'b0;
            end
        endcase
    end

endmodule