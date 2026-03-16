module bc (
    input  [31:0] d1, //value of rs1
    input  [31:0] d2, //value of rs2
    input         br_un,   // 1 = unsigned compare, 0 = signed compare
    output reg    br_eq,
    output reg    br_l
);

    always @(*) begin
        // Equality flag
        br_eq = (d1 == d2);

        // Less-than flag
        if (br_un)
            br_l = (d1 < d2);   // unsigned compare
        else
            br_l = ($signed(d1) < $signed(d2)); // signed compare
    end

endmodule
