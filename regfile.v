module regfile(
    input wire clk,
    input wire rst,
    
    // 写端口 (Write Port) - 时序逻辑
    input wire        we,       // 写使能信号 (Write Enable)
    input wire [4:0]  waddr,    // 要写入的寄存器地址 (rd)
    input wire [31:0] wdata,    // 要写入的数据
    
    // 读端口 1 (Read Port 1) - 组合逻辑
    input wire [4:0]  raddr1,   // 源寄存器 1 地址 (rs1)
    output wire [31:0] rdata1,  // 源寄存器 1 读出的数据
    
    // 读端口 2 (Read Port 2) - 组合逻辑
    input wire [4:0]  raddr2,   // 源寄存器 2 地址 (rs2)
    output wire [31:0] rdata2   // 源寄存器 2 读出的数据
);

    // 定义 32 个 32 位的寄存器阵列
    reg [31:0] regs [0:31];

    // ----------------------------------------------------
    // 1. 写操作：时钟上升沿触发
    // ----------------------------------------------------
    integer i;
    always @(posedge clk) begin
        if (rst == 1'b1) begin
            // 复位时，把所有寄存器清零 (可选，但仿真时习惯良好)
            for (i = 0; i < 32; i = i + 1) begin
                regs[i] <= 32'b0;
            end
        end else if (we == 1'b1 && waddr != 5'b0) begin
            // 只有当写使能有效，且目标地址不是 x0 (5'b0) 时才写入
            regs[waddr] <= wdata;
        end
    end

    // ----------------------------------------------------
    // 2. 读操作：组合逻辑，硬连线 x0 为 0
    // ----------------------------------------------------
    assign rdata1 = (raddr1 == 5'b0) ? 32'b0 : regs[raddr1];
    assign rdata2 = (raddr2 == 5'b0) ? 32'b0 : regs[raddr2];

endmodule