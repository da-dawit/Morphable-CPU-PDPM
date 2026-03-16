// Data Memory
// sp-RAM for load/store operations
//
// In pipelined CPU:
// - Access happens in MEM stage
// - Synchronous WRITE, Asynchronous READ
// - For simplicity, only word (32-bit) access
//   (LB/LH/SB/SH would require additional byte select logic)
//
// !!! Read must be asynchronous (combinational) so that:
// - MEM stage provides address
// - Data is immediately available for MEM/WB register to capture
// - WB stage has valid data on the next clock edge
//
// If read were synchronous, data would arrive one cycle late!

module dmem (
    input         clk,
    input         mem_wr,          // 1 = store, 0 = load
    input  [31:0] addr,            // Memory address
    input  [31:0] write_data,      // Data to write (from rs2)
    output [31:0] read_data        // Data read (combinational!)
);

    // 256 x 32-bit = 1KB data memory
    reg [31:0] mem [0:255];
    
    // Initialize to zero
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = 32'h00000000;
    end

    // Synchronous write
    always @(posedge clk) begin
        if (mem_wr)
            mem[addr[9:2]] <= write_data;   // Store (word-aligned)
    end
    
    // Asynchronous read (combinational)
    // Data is available immediately when address changes
    assign read_data = mem[addr[9:2]];      // Load (word-aligned)

endmodule