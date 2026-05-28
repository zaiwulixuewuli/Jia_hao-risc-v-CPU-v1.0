module dmem (
    input  wire        clk,
    
    // 控制信号
    input  wire        mem_we,      // 内存写使能 (来自译码器)
    input  wire [2:0]  mem_type,    // 内存读写宽度类型 (来自译码器：funct3)
    
    // 地址与数据
    input  wire [31:0] addr,        // 读写物理地址 (来自 ALU 计算结果)
    input  wire [31:0] write_data,  // 准备写入的数据 (来自寄存器 rs2)
    output reg  [31:0] read_data    // 读出的数据 (送回寄存器堆写回端)
);

    // 定义 4KB 大小的 RAM (1024 个 32-bit 字)
    reg [31:0] ram [0:1023];

    // 将 32 位地址转换为字地址 (低 2 位用于字节偏移)
    wire [9:0] word_addr = addr[11:2];
    wire [1:0] byte_offset = addr[1:0];

    // =========================================================================
    // 1. 同步写入逻辑 (Store: SB, SH, SW)
    // =========================================================================
    always @(posedge clk) begin
        if (mem_we) begin
            case (mem_type[1:0]) // 区分 Byte(00), Half-word(01), Word(10)
                2'b00: begin // SB (Store Byte)
                    case (byte_offset)
                        2'b00: ram[word_addr][7:0]   <= write_data[7:0];
                        2'b01: ram[word_addr][15:8]  <= write_data[7:0];
                        2'b10: ram[word_addr][23:16] <= write_data[7:0];
                        2'b11: ram[word_addr][31:24] <= write_data[7:0];
                    endcase
                end
                
                2'b01: begin // SH (Store Half-word)
                    case (byte_offset[1])
                        1'b0: ram[word_addr][15:0]  <= write_data[15:0];
                        1'b1: ram[word_addr][31:16] <= write_data[15:0];
                    endcase
                end
                
                2'b10: begin // SW (Store Word)
                    ram[word_addr] <= write_data;
                end
                
                default: ; // 未定义宽度不写入
            endcase
        end
    end

    // =========================================================================
    // 2. 异步读取与数据格式化 (Load: LB, LH, LW, LBU, LHU)
    // =========================================================================
    // 取得当前地址所在的整字
    wire [31:0] raw_word = ram[word_addr];

    // 根据字节偏移，提取出对应的 Byte 和 Half-word
    reg [7:0]  selected_byte;
    reg [15:0] selected_half;

    always @(*) begin
        case (byte_offset)
            2'b00: selected_byte = raw_word[7:0];
            2'b01: selected_byte = raw_word[15:8];
            2'b10: selected_byte = raw_word[23:16];
            2'b11: selected_byte = raw_word[31:24];
        endcase
    end

    always @(*) begin
        case (byte_offset[1])
            1'b0: selected_half = raw_word[15:0];
            1'b1: selected_half = raw_word[31:16];
        endcase
    end

    // 根据 mem_type (即 funct3) 进行有符号或无符号扩展
    always @(*) begin
        case (mem_type)
            3'b000: read_data = {{24{selected_byte[7]}}, selected_byte}; // LB  (有符号字节)
            3'b001: read_data = {{16{selected_half[15]}}, selected_half}; // LH  (有符号半字)
            3'b010: read_data = raw_word;                                // LW  (32位字)
            3'b100: read_data = {24'b0, selected_byte};                  // LBU (无符号字节)
            3'b101: read_data = {16'b0, selected_half};                  // LHU (无符号半字)
            default: read_data = raw_word;
        endcase
    end

endmodule
