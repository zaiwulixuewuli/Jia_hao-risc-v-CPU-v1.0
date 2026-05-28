module alu(
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  alu_op,
    output reg  [31:0] result,
    output wire        zero
);
    // 定义操作码
    parameter ALU_ADD = 4'b0000;
    parameter ALU_SUB = 4'b0001;
    parameter ALU_AND = 4'b0010;
    parameter ALU_OR  = 4'b0011;
    parameter ALU_XOR = 4'b0100;
    parameter ALU_SLL = 4'b0101; // 逻辑左移
    parameter ALU_SRL = 4'b0110; // 逻辑右移
    parameter ALU_SRA = 4'b0111; // 算术右移
    parameter ALU_SLT = 4'b1000; // 有符号比较小于
    parameter ALU_SLTU = 4'b1001; // 无符号比较小于

    always @(*) begin
        case (alu_op)
            ALU_ADD: result = a + b;
            ALU_SUB: result = a - b;
            ALU_AND: result = a & b;
            ALU_OR:  result = a | b;
            ALU_XOR: result = a ^ b;
            ALU_SLL: result = a << b[4:0]; // 移位量取低5位
            ALU_SRL: result = a >> b[4:0];
            ALU_SRA: result = $signed(a) >>> b[4:0];
            ALU_SLT: result = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            ALU_SLTU: result = (a < b) ? 32'd1 : 32'd0;
            default: result = 32'b0;
        endcase
    end

    assign zero = (result == 32'b0);
endmodule