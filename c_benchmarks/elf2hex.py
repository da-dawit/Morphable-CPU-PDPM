#!/usr/bin/env python3
"""
Convert a raw binary file to Verilog $readmemh format.

Usage: python elf2hex.py input.bin output.hex

Output format: one 32-bit hex word per line (big-endian), no addresses.
This is what $readmemh("file.hex", mem) expects.

Example output:
  00500113
  00000093
  00108093
  ...
"""

import sys
import struct

def bin_to_hex(bin_path, hex_path, max_words=256):
    with open(bin_path, 'rb') as f:
        data = f.read()
    
    # Pad to word boundary
    while len(data) % 4 != 0:
        data += b'\x00'
    
    n_words = len(data) // 4
    if n_words > max_words:
        print(f"WARNING: Binary has {n_words} words, truncating to {max_words}")
        n_words = max_words
    
    with open(hex_path, 'w') as f:
        f.write(f"// Generated from {bin_path}\n")
        f.write(f"// {n_words} words ({n_words * 4} bytes)\n")
        for i in range(n_words):
            # RISC-V is little-endian, but $readmemh expects the 32-bit word
            # as a hex string. struct.unpack with '<I' reads little-endian.
            word = struct.unpack('<I', data[i*4:(i+1)*4])[0]
            f.write(f"{word:08X}\n")
    
    print(f"  Converted: {bin_path} -> {hex_path} ({n_words} words)")

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: python {sys.argv[0]} input.bin output.hex")
        sys.exit(1)
    
    bin_to_hex(sys.argv[1], sys.argv[2])
