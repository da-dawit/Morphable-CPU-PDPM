// IF/ID Pipeline Register
module if_id_reg (
    input         clk,
    input         reset,
    input         stall,
    input         flush,
    input  [31:0] if_pc,
    input  [31:0] if_pc_plus_4,
    input  [31:0] if_inst,
    output reg [31:0] id_pc,
    output reg [31:0] id_pc_plus_4,
    output reg [31:0] id_inst
);

    always @(posedge clk or posedge reset) begin
        if (reset || flush) begin
            id_pc       <= 32'b0;
            id_pc_plus_4 <= 32'b0;
            id_inst     <= 32'h00000013; // NOP
        end
        else if (!stall) begin
            id_pc       <= if_pc;
            id_pc_plus_4 <= if_pc_plus_4;
            id_inst     <= if_inst;
        end
    end

endmodule