module decoder(
    input  wire [31:0] inst,        // 输入 32 位指令
    
    // 1. 盲切分的寄存器地址 (不管用不用，先切出来)
    output wire [4:0]  rs1,
    output wire [4:0]  rs2,
    output wire [4:0]  rd,
    
    // 2. 盲切分的立即数 (不管用不用，全部生成好)
    output reg  [31:0] imm,
    
    // 3. 控制信号矩阵 (指挥数据流向的开关)
    output reg         alu_src,     // 0: 选寄存器rs2, 1: 选立即数imm
    output reg         reg_we,      // 寄存器写使能
    output reg  [3:0]  alu_op,      // 喂给 ALU 的操作码
    output reg         branch,      // 分支指令标志
    output reg  [2:0]  br_type,     // 分支类型：funct3 直接传给顶层判断
    
    // --- 新增控制信号：用于支持加载/存储指令 ---
    output reg         mem_we,      // 内存写使能 (Store 指令有效)
    output reg         mem_to_reg,  // 写回寄存器的数据源选择：0: 选ALU结果, 1: 选内存读出数据 (Load 指令有效)
    output reg  [2:0]  mem_type,    // 内存读写宽度类型：直接传递 funct3 区分 Byte/Half-word/Word
    
    // --- 新增控制信号：用于支持 J 类指令 (JAL/JALR) ---
    output reg         jal,         // JAL 指令标志 (无条件跳转，rd = PC+4)
    output reg         jalr,        // JALR 指令标志 (间接跳转，rd = PC+4, PC = rs1+imm)
    output reg         rd_from_pc,  // 寄存器数据源选择：0: ALU/内存, 1: PC+4
    
    // --- 新增控制信号：用于支持 LUI/AUIPC 指令 ---
    output reg         lui_sel,     // LUI 指令标志 (直接返回立即数左移12位)
    output reg         auipc_sel    // AUIPC 指令标志 (PC + 立即数左移12位)
);

    // 无论什么指令，寄存器位置在 RISC-V 里是绝对固定的，直接连线！
    assign rs1 = inst[19:15];
    assign rs2 = inst[24:20];
    assign rd  = inst[11:7];

    // 提取常用的部分字段用于后面的条件判断
    wire [6:0] opcode = inst[6:0];
    wire [2:0] funct3 = inst[14:12];
    wire [6:0] funct7 = inst[31:25];

    // 控制矩阵与立即数生成
    always @(*) begin
        // --- 赋默认值，防止产生锁存器(Latch) ---
        imm         = 32'b0;
        alu_src     = 1'b0;
        reg_we      = 1'b0;
        alu_op      = 4'b0000; // 默认加法
        branch      = 1'b0;
        br_type     = 3'b000;
        mem_we      = 1'b0;    // 默认不写内存
        mem_to_reg  = 1'b0;    // 默认寄存器写回源选择 ALU 结果
        mem_type    = 3'b000;
        jal         = 1'b0;    // 默认不是 JAL
        jalr        = 1'b0;    // 默认不是 JALR
        rd_from_pc  = 1'b0;    // 默认寄存器数据源不从 PC+4
        lui_sel     = 1'b0;    // 默认不是 LUI
        auipc_sel   = 1'b0;    // 默认不是 AUIPC

        case (opcode)
            // ----------------------------------------------------
            // 1. Load 加载指令 (例如: LB, LH, LW, LBU, LHU)
            // ----------------------------------------------------
            7'b0000011: begin
                alu_src    = 1'b1;     // 地址计算：Base_addr(rs1) + Offset(imm)
                reg_we     = 1'b1;     // 需要写回目的寄存器 rd
                alu_op     = 4'b0000;  // 借用 ALU 的加法计算地址
                mem_we     = 1'b0;     // 只读不写内存
                mem_to_reg = 1'b1;     // 写回寄存器的数据源选择内存
                mem_type   = funct3;   // 将读类型（如 LB:000, LW:010）传递给顶层

                // I 型指令立即数提取：高12位进行符号扩展到32位
                imm        = {{20{inst[31]}}, inst[31:20]};
            end

            // ----------------------------------------------------
            // 2. Store 存储指令 (例如: SB, SH, SW)
            // ----------------------------------------------------
            7'b0100011: begin
                alu_src    = 1'b1;     // 地址计算：Base_addr(rs1) + Offset(imm)
                reg_we     = 1'b0;     // 不需要写回寄存器
                alu_op     = 4'b0000;  // 借用 ALU 的加法计算地址
                mem_we     = 1'b1;     // 开启内存写使能
                mem_to_reg = 1'b0;     // 写回使能已关，此项选 0 即可
                mem_type   = funct3;   // 将写类型（如 SB:000, SW:010）传递给顶层

                // S 型立即数拼接（精确对应指令格式）：高7位 (inst[31:25]) + 低5位 (inst[11:7])
                imm        = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            end

            // ---------------------------------------------------
            // 2.5 LUI 指令 (Load Upper Immediate)
            // 功能：rd = {imm[19:0], 12'b0} (立即数左移12位)
            // opcode = 0110111
            // 立即数格式：20位立即数在 inst[31:12]
            // ---------------------------------------------------
            7'b0110111: begin
                reg_we   = 1'b1;     // 需要写回 rd
                lui_sel  = 1'b1;     // 标记为 LUI 指令
                
                // 提取 20 位立即数（inst[31:12]），在cpu_top中左移12位
                imm = {inst[31:12], 12'b0};
            end
            
            // ---------------------------------------------------
            // 2.6 AUIPC 指令 (Add Upper Immediate to PC)
            // 功能：rd = PC + {imm[19:0], 12'b0}
            // opcode = 0010111
            // 立即数格式：20位立即数在 inst[31:12]
            // 用于地址计算和位置无关代码 (PIC)
            // ---------------------------------------------------
            7'b0010111: begin
                reg_we    = 1'b1;    // 需要写回 rd
                auipc_sel = 1'b1;    // 标记为 AUIPC 指令
                
                // 提取 20 位立即数（inst[31:12]），在cpu_top中与PC相加
                imm = {inst[31:12], 12'b0};
            end

            // ------------------------------------------------
            // 1.5 B型分支指令 (全面支持 BEQ, BNE, BLT, BGE, BLTU, BGEU)
            // ----------------------------------------------------
            7'b1100011: begin
                alu_src   = 1'b0;   // 比较 rs1 和 rs2
                reg_we    = 1'b0;   // 不写回寄存器
                branch    = 1'b1;   // 点亮分支使能
                br_type   = funct3; // 直接传给顶层判断

                // 修正后的 B 型立即数拼接（精确到每一位）
                imm = {{20{inst[31]}}, inst[7], inst[30:25], inst[11:8], 1'b0};

                // 根据不同的分支指令，给 ALU 分配最适合的工具
                case (funct3)
                    3'b000, 3'b001: alu_op = 4'b0001; // BEQ, BNE 借用 ALU_SUB (算 zero)
                    3'b100, 3'b101: alu_op = 4'b1000; // BLT, BGE 借用 ALU_SLT (算有符号比较)
                    3'b110, 3'b111: alu_op = 4'b1001; // BLTU, BGEU 借用 ALU_SLTU (算无符号比较)
                    default:        alu_op = 4'b0000;
                endcase
            end

            // ----------------------------------------------------
            // 3. R型指令 (例如: ADD, SUB, AND, OR)
            // ----------------------------------------------------
            7'b0110011: begin
                alu_src = 1'b0; // 核心：选择 rs2 寄存器的数据输入 ALU
                reg_we  = 1'b1; // 需要把结果写回 rd
                
                case (funct3)
                    3'b000: alu_op = (funct7 == 7'b0100000) ? 4'b0001 : 4'b0000; // SUB : ADD
                    3'b001: alu_op = 4'b0101; // SLL
                    3'b010: alu_op = 4'b1000; // SLT
                    3'b011: alu_op = 4'b1001; // SLTU
                    3'b100: alu_op = 4'b0100; // XOR
                    3'b110: alu_op = 4'b0011; // OR
                    3'b111: alu_op = 4'b0010; // AND
                    3'b101: alu_op = (funct7 == 7'b0100000) ? 4'b0111 : 4'b0110; // SRA : SRL
                    default: alu_op = 4'b0000;
                endcase
            end

            // ----------------------------------------------------
            // 4. JAL 指令 (Jump and Link)
            // 功能：rd = PC + 4，PC = PC + imm
            // 立即数：20位立即数拼接成 32位带符号整数
            // 立即数格式：inst[31]=bit20, inst[30:21]=bits[19:10], inst[20]=bit11, inst[19:12]=bits[10:3]
            // 最终拼接：{imm20, imm[19:12], imm[11], imm[10:1], 1'b0}
            // ----------------------------------------------------
            7'b1101111: begin
                reg_we    = 1'b1;     // 需要写回 rd (返回地址 PC+4)
                jal       = 1'b1;     // 标记为 JAL 指令
                rd_from_pc = 1'b1;    // rd 的数据源选择为 PC+4
                
                // J 型立即数提取：20位立即数拼接成 32位带符号整数，最后一位补0
                // inst[31]=bit[20], inst[30:21]=bits[19:10], inst[20]=bit[11], inst[19:12]=bits[10:3]
                imm = {{12{inst[31]}}, inst[19:12], inst[20], inst[30:21], 1'b0};
            end
            
            // ----------------------------------------------------
            // 4.5 JALR 指令 (Jump and Link Register)
            // 功能：rd = PC + 4，PC = (rs1 + imm) & ~1
            // 立即数：12位立即数进行符号扩展到 32位
            // funct3 = 3'b000
            // ----------------------------------------------------
            7'b1100111: begin
                reg_we     = 1'b1;     // 需要写回 rd (返回地址 PC+4)
                jalr       = 1'b1;     // 标记为 JALR 指令
                alu_src    = 1'b1;     // 选择立即数与 rs1 相加计算新 PC
                rd_from_pc = 1'b1;     // rd 的数据源选择为 PC+4
                alu_op     = 4'b0000;  // ALU 借用加法计算 rs1 + imm
                
                // I 型立即数：高 12 位进行符号扩展到 32 位
                imm = {{20{inst[31]}}, inst[31:20]};
            end
            
            // ----------------------------------------------------
            // 5. I型指令 (例如: ADDI, ANDI, SLLI, SRLI, SRAI)
            // 原来的 I 型是 0010011，这里单独处理
            // JALR 的 opcode 为 1100111，两者不冲突
            // ----------------------------------------------------
            7'b0010011: begin
                alu_src = 1'b1; // 核心：切断 rs2，选择立即数 imm 输入 ALU
                reg_we  = 1'b1; // 需要把结果写回 rd
                
                // I型指令立即数提取：高12位进行符号扩展到32位
                imm = {{20{inst[31]}}, inst[31:20]}; 
                
                case (funct3)
                    3'b000: alu_op = 4'b0000; // ADDI (直接用加法)
                    3'b001: begin
                        alu_op = 4'b0101; // SLLI
                        imm    = {27'b0, inst[24:20]};
                    end
                    3'b010: alu_op = 4'b1000; // SLTI
                    3'b011: alu_op = 4'b1001; // SLTIU
                    3'b101: begin
                        alu_op = (funct7 == 7'b0100000) ? 4'b0111 : 4'b0110; // SRAI : SRLI
                        imm    = {27'b0, inst[24:20]};
                    end
                    3'b111: alu_op = 4'b0010; // ANDI (直接用与运算)
                    3'b100: alu_op = 4'b0100; // XORI
                    3'b110: alu_op = 4'b0011; // ORI
                    default: alu_op = 4'b0000;
                endcase
            end

            default: begin
                // 未知指令，保持默认安全状态
                alu_src    = 1'b0;
                reg_we     = 1'b0;
                alu_op     = 4'b0000;
                mem_we     = 1'b0;
                mem_to_reg = 1'b0;
                jal        = 1'b0;
                jalr       = 1'b0;
                rd_from_pc = 1'b0;
                lui_sel    = 1'b0;
                auipc_sel  = 1'b0;
            end
        endcase
    end

endmodule
