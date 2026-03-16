// imem.v 
`timescale 1ns/1ps

module imem (
    input         clk,       
    input  [31:0] addr,
    output [31:0] inst
);

    reg [31:0] mem [0:255];
    integer i;

    // Initialize memory
    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = 32'h00000013; // NOP (addi x0, x0, 0)

        // Default program
        $readmemh("prog.hex", mem);
    end

    // Combinational read (most likely what your CPU expects)
    assign inst = mem[addr[9:2]];

endmodule
