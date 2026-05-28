module rom(
    input wire [31:0] addr,    // 接收来自 PC 的地址
    output reg [31:0] inst     // 输出读取到的指令
);

    reg [31:0] rom_mem [0:15]; // 16个槽位

    integer i;
    initial begin
        // 默认全部初始化为 NOP
        for (i = 0; i < 16; i = i + 1) begin
            rom_mem[i] = 32'h00000013; 
        end

        // -----------------------------------------------------------------
        // 新程序：包含所有支持的指令类型示例
        // -----------------------------------------------------------------
        // PC = 0x00: ADDI x1, x0, 10  (I-type) - 初始化 x1 = 10
      // PC = 0x00: ADDI x1, x0, 10
        rom_mem[0] = 32'h00a00093; 

        // PC = 0x04: ADDI x2, x0, 2
        rom_mem[1] = 32'h00200113; 

        // PC = 0x08: ADD  x3, x1, x2
        rom_mem[2] = 32'h002081b3; 

        // PC = 0x0C: SUB  x4, x1, x2
        rom_mem[3] = 32'h40208233; 

        // PC = 0x10: SW   x3, 0(x0)
        rom_mem[4] = 32'h00302023; 

        // PC = 0x14: LW   x5, 0(x0)
        rom_mem[5] = 32'h00002283; 

        // PC = 0x18: BLT  x4, x1, 8  ---> (修正后机器码，对应 BLT x4, x1, 8)
        rom_mem[6] = 32'h00124463; 

        // PC = 0x1C: ADDI x6, x0, 99 ---> (修正后机器码，末尾修改为 I-type 对应的 13)
        rom_mem[7] = 32'h06300313; 
        
        // PC = 0x20: ANDI x7, x5, 7  ---> (修正后机器码，对应 ANDI x7, x5, 7)
        rom_mem[8] = 32'h0072f393;

        // PC = 0x24: NOP 
        rom_mem[9] = 32'h00000013; 

        // PC = 0x28: BEQ  x7, x0, 8  ---> (修正后机器码，对应 BEQ x7, x0, 8)
        rom_mem[10] = 32'h00038463; 

        // PC = 0x2C: ADDI x8, x0, 100
        rom_mem[11] = 32'h06400413;
    end

    // 异步读取
    always @(*) begin
        inst = rom_mem[addr[5:2]]; 
    end
endmodule
