///Updiuno ALU
module alu (
    input  [31:0] operand_a,
    input  [31:0] operand_b,
  	input  [3:0]  alu_ctrl,
    output reg [31:0] result,
    output        zero
);
  
// ALUops
localparam ALU_ADD  = 4'b0000;
localparam ALU_SUB  = 4'b0001;
localparam ALU_AND  = 4'b0010;
localparam ALU_OR   = 4'b0011;
localparam ALU_XOR  = 4'b0100;
localparam ALU_SLT  = 4'b0101;  // Set Less Than
localparam ALU_SLTU = 4'b0110;  // Set Less Than Unsigned
localparam ALU_SLL  = 4'b0111;  // Shift Left Logical
localparam ALU_SRL  = 4'b1000;  // Shift Right Logical
localparam ALU_SRA  = 4'b1001;  // Shift Right Arithmetic
  
  always @(*) begin
    case (alu_ctrl) //32 bits
      	ALU_ADD:  result = operand_a + operand_b;
        ALU_SUB:  result = operand_a - operand_b;
        ALU_AND:  result = operand_a & operand_b;
        ALU_OR:   result = operand_a | operand_b;
        ALU_XOR:  result = operand_a ^ operand_b;
        ALU_SLT:  result = ($signed(operand_a) < $signed(operand_b)) ? 32'd1 : 32'd0;
        ALU_SLTU: result = (operand_a < operand_b) ? 32'd1 : 32'd0;
        ALU_SLL:  result = operand_a << operand_b[4:0];
        ALU_SRL:  result = operand_a >> operand_b[4:0];
        ALU_SRA:  result = $signed(operand_a) >>> operand_b[4:0];
        default:  result = 32'd0;
    endcase
  end
  
  assign zero = (result == 32'd0);
  
endmodule