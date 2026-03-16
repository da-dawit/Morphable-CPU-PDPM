#!/usr/bin/env python3
#assembler for dawit
import sys
import re

class RISCVAssembler:
    def __init__(self):
        # Register mapping
        self.registers = {}
        for i in range(32):
            self.registers[f'x{i}'] = i
        self.registers.update({
            'zero':0, 'ra':1, 'sp':2, 'gp':3, 'tp':4,
            't0':5, 't1':6, 't2':7,
            's0':8, 'fp':8, 's1':9,
            'a0':10,'a1':11,'a2':12,'a3':13,'a4':14,'a5':15,
            'a6':16,'a7':17,
            's2':18,'s3':19,'s4':20,'s5':21,'s6':22,'s7':23,
            's8':24,'s9':25,'s10':26,'s11':27,
            't3':28,'t4':29,'t5':30,'t6':31
        })
        self.labels = {}

    def reg(self, r):
        """Parse register name"""
        r = r.strip().lower()
        if r not in self.registers:
            raise ValueError(f"Unknown register: {r}")
        return self.registers[r]

    def imm(self, s):
        """Parse immediate value"""
        s = s.strip()
        if s.startswith("0x"):
            return int(s, 16)
        return int(s)

    # Encoding functions
    def R(self, funct7, rs2, rs1, funct3, rd, opcode):
        """R-type encoding"""
        return ((funct7 & 0x7F) << 25) | ((rs2 & 0x1F) << 20) | \
               ((rs1 & 0x1F) << 15) | ((funct3 & 7) << 12) | \
               ((rd & 0x1F) << 7) | (opcode & 0x7F)

    def I(self, imm, rs1, funct3, rd, opcode):
        """I-type encoding"""
        imm = imm & 0xFFF
        return (imm << 20) | ((rs1 & 0x1F) << 15) | \
               ((funct3 & 7) << 12) | ((rd & 0x1F) << 7) | (opcode & 0x7F)

    def S(self, imm, rs2, rs1, funct3, opcode):
        """S-type encoding"""
        imm &= 0xFFF
        imm_11_5 = (imm >> 5) & 0x7F
        imm_4_0 = imm & 0x1F
        return (imm_11_5 << 25) | ((rs2 & 0x1F) << 20) | \
               ((rs1 & 0x1F) << 15) | ((funct3 & 7) << 12) | \
               (imm_4_0 << 7) | opcode

    def B(self, imm, rs2, rs1, funct3, opcode):
        """B-type encoding"""
        imm &= 0x1FFF
        imm_12 = (imm >> 12) & 1
        imm_10_5 = (imm >> 5) & 0x3F
        imm_4_1 = (imm >> 1) & 0xF
        imm_11 = (imm >> 11) & 1
        return (imm_12 << 31) | (imm_10_5 << 25) | \
               ((rs2 & 0x1F) << 20) | ((rs1 & 0x1F) << 15) | \
               ((funct3 & 7) << 12) | (imm_4_1 << 8) | \
               (imm_11 << 7) | opcode

    def U(self, imm, rd, opcode):
        """U-type encoding"""
        return ((imm << 12) & 0xFFFFF000) | ((rd & 0x1F) << 7) | opcode

    def J(self, imm, rd, opcode):
        """J-type encoding"""
        imm &= 0x1FFFFF
        imm_20 = (imm >> 20) & 1
        imm_19_12 = (imm >> 12) & 0xFF
        imm_11 = (imm >> 11) & 1
        imm_10_1 = (imm >> 1) & 0x3FF
        return (imm_20 << 31) | (imm_19_12 << 12) | \
               (imm_11 << 20) | (imm_10_1 << 21) | \
               ((rd & 0x1F) << 7) | opcode

    def first_pass(self, lines):
        """First pass - collect labels"""
        pc = 0
        for line in lines:
            clean = re.sub(r'#.*', '', line).strip()
            if not clean:
                continue
            if ':' in clean:
                label = clean.split(':')[0].strip()
                self.labels[label] = pc
                clean = clean.split(':', 1)[1].strip()
            if clean:
                pc += 4

    def assemble(self, lines):
        """Second pass - assemble instructions"""
        machine = []
        pc = 0

        for line in lines:
            clean = re.sub(r'#.*', '', line).strip()
            if not clean:
                continue

            if ':' in clean:
                clean = clean.split(':', 1)[1].strip()
                if not clean:
                    continue

            parts = re.split(r'[,\s()]+', clean)
            parts = [p for p in parts if p]
            op = parts[0].lower()

            # R-type instructions
            if op == 'add':
                machine.append(self.R(0, self.reg(parts[3]), self.reg(parts[2]), 0, self.reg(parts[1]), 0b0110011))
            elif op == 'sub':
                machine.append(self.R(0x20, self.reg(parts[3]), self.reg(parts[2]), 0, self.reg(parts[1]), 0b0110011))
            elif op == 'xor':
                machine.append(self.R(0, self.reg(parts[3]), self.reg(parts[2]), 0b100, self.reg(parts[1]), 0b0110011))
            elif op == 'or':
                machine.append(self.R(0, self.reg(parts[3]), self.reg(parts[2]), 0b110, self.reg(parts[1]), 0b0110011))
            elif op == 'and':
                machine.append(self.R(0, self.reg(parts[3]), self.reg(parts[2]), 0b111, self.reg(parts[1]), 0b0110011))
            elif op == 'sll':
                machine.append(self.R(0, self.reg(parts[3]), self.reg(parts[2]), 0b001, self.reg(parts[1]), 0b0110011))
            elif op == 'srl':
                machine.append(self.R(0, self.reg(parts[3]), self.reg(parts[2]), 0b101, self.reg(parts[1]), 0b0110011))
            elif op == 'sra':
                machine.append(self.R(0x20, self.reg(parts[3]), self.reg(parts[2]), 0b101, self.reg(parts[1]), 0b0110011))
            elif op == 'slt':
                machine.append(self.R(0, self.reg(parts[3]), self.reg(parts[2]), 0b010, self.reg(parts[1]), 0b0110011))
            elif op == 'sltu':
                machine.append(self.R(0, self.reg(parts[3]), self.reg(parts[2]), 0b011, self.reg(parts[1]), 0b0110011))

            # I-type instructions
            elif op == 'addi':
                machine.append(self.I(self.imm(parts[3]), self.reg(parts[2]), 0, self.reg(parts[1]), 0b0010011))
            elif op == 'xori':
                machine.append(self.I(self.imm(parts[3]), self.reg(parts[2]), 0b100, self.reg(parts[1]), 0b0010011))
            elif op == 'ori':
                machine.append(self.I(self.imm(parts[3]), self.reg(parts[2]), 0b110, self.reg(parts[1]), 0b0010011))
            elif op == 'andi':
                machine.append(self.I(self.imm(parts[3]), self.reg(parts[2]), 0b111, self.reg(parts[1]), 0b0010011))
            elif op == 'slli':
                machine.append(self.I(self.imm(parts[3]), self.reg(parts[2]), 0b001, self.reg(parts[1]), 0b0010011))
            elif op == 'srli':
                machine.append(self.I(self.imm(parts[3]), self.reg(parts[2]), 0b101, self.reg(parts[1]), 0b0010011))
            elif op == 'srai':
                machine.append(self.I(0x400 | self.imm(parts[3]), self.reg(parts[2]), 0b101, self.reg(parts[1]), 0b0010011))
            elif op == 'slti':
                machine.append(self.I(self.imm(parts[3]), self.reg(parts[2]), 0b010, self.reg(parts[1]), 0b0010011))
            elif op == 'sltiu':
                machine.append(self.I(self.imm(parts[3]), self.reg(parts[2]), 0b011, self.reg(parts[1]), 0b0010011))

            # Load instructions
            elif op == 'lw':
                machine.append(self.I(self.imm(parts[2]), self.reg(parts[3]), 0b010, self.reg(parts[1]), 0b0000011))
            elif op == 'lh':
                machine.append(self.I(self.imm(parts[2]), self.reg(parts[3]), 0b001, self.reg(parts[1]), 0b0000011))
            elif op == 'lhu':
                machine.append(self.I(self.imm(parts[2]), self.reg(parts[3]), 0b101, self.reg(parts[1]), 0b0000011))
            elif op == 'lb':
                machine.append(self.I(self.imm(parts[2]), self.reg(parts[3]), 0b000, self.reg(parts[1]), 0b0000011))
            elif op == 'lbu':
                machine.append(self.I(self.imm(parts[2]), self.reg(parts[3]), 0b100, self.reg(parts[1]), 0b0000011))

            # Store instructions
            elif op == 'sw':
                machine.append(self.S(self.imm(parts[2]), self.reg(parts[1]), self.reg(parts[3]), 0b010, 0b0100011))
            elif op == 'sh':
                machine.append(self.S(self.imm(parts[2]), self.reg(parts[1]), self.reg(parts[3]), 0b001, 0b0100011))
            elif op == 'sb':
                machine.append(self.S(self.imm(parts[2]), self.reg(parts[1]), self.reg(parts[3]), 0b000, 0b0100011))

            # Branch instructions
            elif op == 'beq':
                offset = self.labels[parts[3]] - pc
                machine.append(self.B(offset, self.reg(parts[2]), self.reg(parts[1]), 0b000, 0b1100011))
            elif op == 'bne':
                offset = self.labels[parts[3]] - pc
                machine.append(self.B(offset, self.reg(parts[2]), self.reg(parts[1]), 0b001, 0b1100011))
            elif op == 'blt':
                offset = self.labels[parts[3]] - pc
                machine.append(self.B(offset, self.reg(parts[2]), self.reg(parts[1]), 0b100, 0b1100011))
            elif op == 'bge':
                offset = self.labels[parts[3]] - pc
                machine.append(self.B(offset, self.reg(parts[2]), self.reg(parts[1]), 0b101, 0b1100011))
            elif op == 'bltu':
                offset = self.labels[parts[3]] - pc
                machine.append(self.B(offset, self.reg(parts[2]), self.reg(parts[1]), 0b110, 0b1100011))
            elif op == 'bgeu':
                offset = self.labels[parts[3]] - pc
                machine.append(self.B(offset, self.reg(parts[2]), self.reg(parts[1]), 0b111, 0b1100011))

            # Jump instructions
            elif op == 'jal':
                offset = self.labels[parts[2]] - pc
                machine.append(self.J(offset, self.reg(parts[1]), 0b1101111))
            elif op == 'jalr':
                machine.append(self.I(self.imm(parts[2]), self.reg(parts[3]), 0, self.reg(parts[1]), 0b1100111))

            # Upper immediate instructions
            elif op == 'lui':
                machine.append(self.U(self.imm(parts[2]) >> 12, self.reg(parts[1]), 0b0110111))
            elif op == 'auipc':
                machine.append(self.U(self.imm(parts[2]) >> 12, self.reg(parts[1]), 0b0010111))

            # Pseudo-instructions
            elif op == 'nop':
                machine.append(0x00000013)
            elif op == 'li':
                machine.append(self.I(self.imm(parts[2]), 0, 0, self.reg(parts[1]), 0b0010011))
            elif op == 'mv':
                machine.append(self.I(0, self.reg(parts[2]), 0, self.reg(parts[1]), 0b0010011))

            else:
                raise ValueError(f"Unknown instruction: {op}")

            pc += 4

        return machine


def main():
    if len(sys.argv) < 2:
        print("use like: python assembler.py <input.s> [output.hex]")
        sys.exit(1)

    infile = sys.argv[1]
    outfile = sys.argv[2] if len(sys.argv) > 2 else "prog.hex"

    with open(infile, 'r', encoding='utf-8') as f:
        lines = f.read().splitlines()

    asm = RISCVAssembler()
    asm.first_pass(lines)
    mc = asm.assemble(lines)

    with open(outfile, 'w') as f:
        for inst in mc:
            f.write(f"{inst:08x}\n")

    print(f" Assembly successful!")
    print(f"  Input:  {infile}")
    print(f"  Output: {outfile}")
    print(f"  Instructions: {len(mc)}")

if __name__ == "__main__":
    main()