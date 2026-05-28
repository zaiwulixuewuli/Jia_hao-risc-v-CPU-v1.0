module dmem (
    input  wire        clk,
    
    // 控制信号
    input  wire        mem_we,      // 内存写使能
    input  wire [2:0]  mem_type,    // 内存读写宽度类型 (funct3)
    
    // 地址与数据
    input  wire [31:0] addr,        // 来自 ALU 的地址
    input  wire [31:0] write_data,  // 来自 rs2 的数据
    output reg  [31:0] read_data    // 送回寄存器堆
);

    // 定义 4KB 大小的 RAM (1024 个 32-bit 字)
    reg [31:0] ram [0:1023];

    // 初始化内存，防止开机时读出 X (红线)
    integer idx;
    initial begin
        for (idx = 0; idx < 1024; idx = idx + 1) begin
            ram[idx] = 32'h00000000;
        end
    end

    // 将 32 位地址转换为字地址
    wire [9:0] word_addr = addr[11:2];
    wire [1:0] byte_offset = addr[1:0];

    // =========================================================================
    // 1. 同步写入逻辑 (Store: SB, SH, SW) —— 使用老实人的分段赋值，绝无左值拼接错误
    // =========================================================================
    always @(posedge clk) begin
        if (mem_we) begin
            case (mem_type[1:0]) 
                2'b00: begin // SB (Store Byte)
                    case (byte_offset)
                        2'b00: ram[word_addr][7:0]   <= write_data[7:0];
                        2'b01: ram[word_addr][15:8]  <= write_data[7:0];
                        2'b10: ram[word_addr][23:16] <= write_data[7:0];
                        2'b11: ram[word_addr][31:24] <= write_data[7:0];
                        default: ;
                    endcase
                end
                
                2'b01: begin // SH (Store Half-word)
                    case (byte_offset[1])
                        1'b0: ram[word_addr][15:0]  <= write_data[15:0];
                        1'b1: ram[word_addr][31:16] <= write_data[15:0];
                        default: ;
                    endcase
                end
                
                2'b10: begin // SW (Store Word)
                    ram[word_addr] <= write_data;
                end
                
                default: ; 
            endcase
        end
    end

    // =========================================================================
    // 2. 异步读取与数据格式化 (Load: LB, LH, LW, LBU, LHU)
    // =========================================================================
    wire [31:0] raw_word = ram[word_addr];

    reg [7:0]  selected_byte;
    reg [15:0] selected_half;

    always @(*) begin
        case (byte_offset)
            2'b00: selected_byte = raw_word[7:0];
            2'b01: selected_byte = raw_word[15:8];
            2'b10: selected_byte = raw_word[23:16];
            2'b11: selected_byte = raw_word[31:24];
            default: selected_byte = raw_word[7:0];
        endcase
    end

    always @(*) begin
        case (byte_offset[1])
            1'b0: selected_half = raw_word[15:0];
            1'b1: selected_half = raw_word[31:16];
            default: selected_half = raw_word[15:0];
        endcase
    end

    // 数据扩展输出
    always @(*) begin
        case (mem_type)
            3'b000: read_data = {{24{selected_byte[7]}}, selected_byte}; // LB
            3'b001: read_data = {{16{selected_half[15]}}, selected_half}; // LH
            3'b010: read_data = raw_word;                                // LW
            3'b100: read_data = {24'b0, selected_byte};                  // LBU
            3'b101: read_data = {16'b0, selected_half};                  // LHU
            default: read_data = raw_word;
        endcase
    end

endmodule
