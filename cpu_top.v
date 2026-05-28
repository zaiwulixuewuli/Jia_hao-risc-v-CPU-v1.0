module cpu_top(
    input wire clk,
    input wire rst
);

    // ----------------------------------------------------
    // 内部连线声明 (Wires)
    // ----------------------------------------------------
    wire [31:0] pc;
    wire [31:0] inst;
    
    wire [4:0]  rs1, rs2, rd;
    wire [31:0] imm;
    wire        alu_src;
    wire        reg_we;
    wire [3:0]  alu_op;
    wire        branch;
    wire [2:0]  br_type;
    wire        branch_taken;
    wire [31:0] pc_next;
    
    wire [31:0] reg_data1, reg_data2;
    wire [31:0] alu_operand_b;
    wire [31:0] alu_result;
    wire        alu_zero;
    
    // 内存相关信号
    wire        mem_we;        // 内存写使能 (来自译码器)
    wire [2:0]  mem_type;      // 内存读写宽度类型 (来自译码器)
    wire        mem_to_reg;    // 写回寄存器数据源选择 (来自译码器)
    wire [31:0] mem_read_data; // 从内存读出的数据
    wire [31:0] reg_write_data; // 实际写回寄存器的数据（ALU结果或内存数据）
    
    // J 类指令相关信号
    wire        jal;           // JAL 指令标志
    wire        jalr;          // JALR 指令标志
    wire        rd_from_pc;    // 寄存器数据源选择：1 = PC+4（用于 JAL/JALR 的返回地址）
    wire [31:0] pc_plus_4;     // PC + 4
    wire [31:0] jump_target;   // 跳转目标地址
    
    // LUI/AUIPC 指令相关信号
    wire        lui_sel;       // LUI 指令标志
    wire        auipc_sel;     // AUIPC 指令标志
    wire [31:0] lui_data;      // LUI 结果（立即数左移12位）
    wire [31:0] auipc_data;    // AUIPC 结果（PC + 立即数左移12位）

    // ----------------------------------------------------
    // 1. 取指阶段 (Fetch)
    // ----------------------------------------------------
    pc_reg u_pc_reg (
        .clk(clk),
        .rst(rst),
        .pc_next(pc_next),
        .pc(pc)
    );

    rom u_rom (
        .addr(pc),
        .inst(inst)
    );

    // ----------------------------------------------------
    // 2. 译码阶段 (Decode)
    // ----------------------------------------------------
    decoder u_decoder (
        .inst(inst),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .imm(imm),
        .alu_src(alu_src),
        .reg_we(reg_we),
        .alu_op(alu_op),
        .branch(branch),
        .br_type(br_type),
        .mem_we(mem_we),
        .mem_type(mem_type),
        .mem_to_reg(mem_to_reg),
        .jal(jal),
        .jalr(jalr),
        .rd_from_pc(rd_from_pc),
        .lui_sel(lui_sel),
        .auipc_sel(auipc_sel)
    );

    // ----------------------------------------------------
    // 3. 寄存器堆堆叠 (Register File)
    // ----------------------------------------------------
    regfile u_regfile (
        .clk(clk),
        .rst(rst),
        .we(reg_we),
        .waddr(rd),
        .wdata(reg_write_data), // 核心：把 ALU 结果或内存数据写回
        .raddr1(rs1),
        .rdata1(reg_data1),
        .raddr2(rs2),
        .rdata2(reg_data2)
    );

    // ----------------------------------------------------
    // 4. 执行阶段 (Execute) 与 核心控制 MUX
    // ----------------------------------------------------
    // 这就是我们说的那个“交警 MUX”，杜绝后患的关键点
    assign alu_operand_b = (alu_src == 1'b1) ? imm : reg_data2;

    alu u_alu (
        .a(reg_data1),
        .b(alu_operand_b),
        .alu_op(alu_op),
        .result(alu_result),
        .zero(alu_zero)
    );
    
    // =========================================================================
    // 5. 内存阶段 (Memory Access)
    // =========================================================================
    dmem u_dmem (
        .clk(clk),
        .mem_we(mem_we),
        .mem_type(mem_type),
        .addr(alu_result),
        .write_data(reg_data2),
        .read_data(mem_read_data)
    );
    
    // =========================================================================
    // 6. 写回阶段 (Write Back) - 数据选择器
    // 支持：Load/Store, JAL/JALR, LUI/AUIPC
    // =========================================================================
    // 首先处理 mem_to_reg 选择器（Load vs ALU）
    wire [31:0] alu_or_mem = (mem_to_reg == 1'b1) ? mem_read_data : alu_result;
    
    // 计算 PC+4（返回地址，用于 JAL/JALR）
    assign pc_plus_4 = pc + 32'd4;
    
    // 计算 LUI 结果（立即数已经是{imm[19:0], 12'b0}格式）
    assign lui_data = imm;
    
    // 计算 AUIPC 结果（PC + 立即数左移12位）
    assign auipc_data = pc + imm;
    
    // 最终的寄存器写入数据：优先级为 LUI > AUIPC > PC+4 > (内存或ALU)
    assign reg_write_data = (lui_sel == 1'b1) ? lui_data :
                            (auipc_sel == 1'b1) ? auipc_data :
                            (rd_from_pc == 1'b1) ? pc_plus_4 : alu_or_mem;
    
    // =========================================================================
    // 7. PC 更新逻辑（支持条件分支、无条件跳转、间接跳转）
    // =========================================================================
    reg branch_taken_reg;
    always @(*) begin
        if (branch) begin
            case (br_type)
                3'b000:  branch_taken_reg = alu_zero;          // BEQ: 减法结果为0则跳
                3'b001:  branch_taken_reg = ~alu_zero;         // BNE: 减法结果不为0则跳
                3'b100:  branch_taken_reg = alu_result[0];     // BLT: 比较结果为1则跳 ($signed(a) < $signed(b))
                3'b101:  branch_taken_reg = ~alu_result[0];    // BGE: 比较结果为0则跳 (即不小于，就是大于等于)
                3'b110:  branch_taken_reg = alu_result[0];     // BLTU: 无符号比较为1则跳
                3'b111:  branch_taken_reg = ~alu_result[0];    // BGEU: 无符号比较为0则跳
                default: branch_taken_reg = 1'b0;
            endcase
        end else begin
            branch_taken_reg = 1'b0;
        end
    end

    assign branch_taken = branch_taken_reg;
    
    // PC 下一步值的选择
    // 优先级：JALR > JAL > 条件分支 > 顺序执行
    assign jump_target = jalr ? (alu_result & 32'hFFFFFFFE) :     // JALR: (rs1 + imm) & ~1
                         jal  ? (pc + imm) :                       // JAL: PC + imm
                         branch_taken ? (pc + imm) : (pc + 32'd4); // 条件分支或顺序执行
    
    assign pc_next = jump_target;
endmodule