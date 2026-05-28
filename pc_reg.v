module pc_reg(
    input wire clk,
    input wire rst,
    input wire [31:0] pc_next,
    output reg [31:0] pc
);

    always @(posedge clk) begin
        if (rst == 1'b1) begin
            pc <= 32'h00000000; // 复位时，地址从 0 开始
        end else begin
            pc <= pc_next;      // 由外部提供下一 PC
        end
    end

endmodule