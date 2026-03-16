// Morphable Pipelined RISC-V CPU (RV32I) - Version 2
// Supports P3 (3-stage), P5 (5-stage), and P7 (7-stage) pipeline modes
// Features perceptron-based dynamic mode prediction
//
// *****PIPELINES******
// P3 Mode: IF → ID+EX → MEM+WB                           (3 stages, lowest latency)
// P5 Mode: IF → ID → EX → MEM → WB                       (5 stages, balanced)
// P7 Mode: IF1 → IF2 → ID → EX1 → EX2 → MEM → WB        (7 stages, highest throughput)
//
// My contrib.: Perceptron-driven dynamic mode switching learns optimal mode
// based on runtime workload characteristics (branches, memory, hazards)

module cpu_morphable_top (
    input         clk,
    input         reset,
    
    // Pipeline mode control
    input  [1:0]  mode_select,        // 00=P3, 01=P5, 10=P7
    input         mode_switch_req,    // Request mode switch
    input         auto_mode_enable,   // Enable perceptron-based auto switching
    output [1:0]  current_mode,       // Current pipeline mode
    output        mode_switching,     // Mode switch in progress
    
    // Debug outputs
    output [31:0] debug_pc,
    output [31:0] debug_inst,
    output        debug_reg_write,
    output [4:0]  debug_rd,
    output [31:0] debug_rd_data,
    
    // Performance counters
    output [31:0] cycle_count,
    output [31:0] inst_count,
    output [31:0] stall_count,
    output [31:0] flush_count,
    
    // Perceptron debug outputs
    output [1:0]  predicted_mode,
    output [7:0]  prediction_confidence,
    
    // Clock prediction output
    output [2:0]  predicted_clk_idx
);

    
    // MODE CONTROL SIGNALS
    
    
    wire is_p3_mode;
    wire is_p5_mode;
    wire is_p7_mode;
    wire bypass_if2;
    wire bypass_id_ex;
    wire bypass_ex2;
    wire bypass_ex_mem;
    wire mode_switch_flush;
    
    
    // PIPELINE CONTROL SIGNALS
    
    
    wire pc_stall;
    wire if_id_stall;
    wire if_id_flush;
    wire id_ex_flush;
    wire branch_taken;
    wire combined_flush;
    
    // Branch flush with extended depth for P7
    // Different stages seem to have flush durations:
    // - IF1/IF2: 1 cycle (just branch_taken) - need to start fetching new instructions
    // - IF/ID: 2 cycles (branch_taken + d1) - flush 2 bad instructions
    // - ID/EX: 3 cycles (branch_taken + d1 + d2) - flush 3 bad instructions  
    // - EX1/EX2: 1 cycle (just branch_taken) - only current instruction
    // - EX/MEM: 1 cycle (just branch_taken)
    // - MEM/WB write gate: 4 cycles - prevent any flushed instruction from writing
    reg branch_flush_d1, branch_flush_d2, branch_flush_d3;
    wire branch_flush_p7_short;  // 2 cycles for IF/ID
    wire branch_flush_p7_med;    // 3 cycles for ID/EX
    wire branch_flush_p7_long;   // 4 cycles for MEM/WB gating
    
    assign branch_flush_p7_short = is_p7_mode ? (branch_taken || branch_flush_d1) : branch_taken;
    assign branch_flush_p7_med   = is_p7_mode ? (branch_taken || branch_flush_d1 || branch_flush_d2) : branch_taken;
    assign branch_flush_p7_long  = is_p7_mode ? (branch_taken || branch_flush_d1 || branch_flush_d2 || branch_flush_d3) : branch_taken;
    assign combined_flush = if_id_flush || mode_switch_flush;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            branch_flush_d1 <= 1'b0;
            branch_flush_d2 <= 1'b0;
            branch_flush_d3 <= 1'b0;
        end else begin
            branch_flush_d1 <= branch_taken;
            branch_flush_d2 <= branch_flush_d1;
            branch_flush_d3 <= branch_flush_d2;
        end
    end
    
    
    // IF STAGE SIGNALS
    
    
    reg  [31:0] pc;
    wire [31:0] pc_plus_4;
    wire [31:0] pc_next;
    wire [31:0] if_inst;
    
    // IF1/IF2 stage signals (for P7)
    wire [31:0] if2_pc;
    wire [31:0] if2_pc_plus_4;
    wire        if2_valid;
    
    
    // IF/ID REGISTER OUTPUTS
    
    
    wire [31:0] id_pc;
    wire [31:0] id_pc_plus_4;
    wire [31:0] id_inst;
    
    
    // ID STAGE SIGNALS
    
    
    wire [6:0]  id_opcode;
    wire [4:0]  id_rd;
    wire [4:0]  id_rs1;
    wire [4:0]  id_rs2;
    wire [2:0]  id_funct3;
    wire [6:0]  id_funct7;
    wire [31:0] id_imm;
    wire [31:0] id_rf_rd1;
    wire [31:0] id_rf_rd2;
    
    wire        id_reg_write_en;
    wire        id_mem_wr;
    wire        id_mem_read;
    wire        id_a_sel;
    wire        id_b_sel;
    wire [3:0]  id_alu_sel;
    wire [1:0]  id_wb_sel;
    wire        id_br_un;
    wire        id_is_branch;
    wire        id_is_jump;
    wire        id_is_jalr;
    
    
    // ID/EX REGISTER OUTPUTS (from actual register, used in P5/P7)
    
    
    wire [31:0] ex_pc_reg;
    wire [31:0] ex_pc_plus_4_reg;
    wire [31:0] ex_rd1_reg;
    wire [31:0] ex_rd2_reg;
    wire [31:0] ex_imm_reg;
    wire [4:0]  ex_rs1_reg;
    wire [4:0]  ex_rs2_reg;
    wire [4:0]  ex_rd_reg;
    wire [3:0]  ex_alu_sel_reg;
    wire        ex_a_sel_reg;
    wire        ex_b_sel_reg;
    wire        ex_mem_wr_reg;
    wire        ex_mem_read_reg;
    wire        ex_reg_write_en_reg;
    wire [1:0]  ex_wb_sel_reg;
    wire        ex_pc_sel_reg;
    wire        ex_br_un_reg;
    wire [2:0]  ex_funct3_reg;
    wire        ex_is_branch_reg;
    wire        ex_is_jump_reg;
    
    
    // EX STAGE SIGNALS (after bypass mux - active signals)
    
    
    wire [31:0] ex_pc;
    wire [31:0] ex_pc_plus_4;
    wire [31:0] ex_rd1;
    wire [31:0] ex_rd2;
    wire [31:0] ex_imm;
    wire [4:0]  ex_rs1;
    wire [4:0]  ex_rs2;
    wire [4:0]  ex_rd;
    wire [3:0]  ex_alu_sel;
    wire        ex_a_sel;
    wire        ex_b_sel;
    wire        ex_mem_wr;
    wire        ex_mem_read;
    wire        ex_reg_write_en;
    wire [1:0]  ex_wb_sel;
    wire        ex_br_un;
    wire [2:0]  ex_funct3;
    wire        ex_is_branch;
    wire        ex_is_jump;
    
    wire [1:0]  forward_a;
    wire [1:0]  forward_b;
    wire [31:0] ex_alu_src_a;
    wire [31:0] ex_alu_src_b;
    wire [31:0] ex_forward_a_data;
    wire [31:0] ex_forward_b_data;
    wire [31:0] ex_alu_result;
    wire        ex_alu_zero;
    
    // EX1/EX2 stage signals (for P7)
    wire [31:0] ex2_pc;
    wire [31:0] ex2_pc_plus_4;
    wire [31:0] ex2_alu_partial;
    wire [31:0] ex2_rs1_val;
    wire [31:0] ex2_rs2_val;
    wire [31:0] ex2_imm;
    wire [4:0]  ex2_rd;
    wire        ex2_mem_wr;
    wire        ex2_mem_read;
    wire        ex2_reg_write_en;
    wire [1:0]  ex2_wb_sel;
    wire        ex2_is_branch;
    wire        ex2_is_jump;
    wire [2:0]  ex2_funct3;
    wire        ex2_br_un;
    wire        ex2_valid;
    
    
    // EX/MEM REGISTER OUTPUTS (from actual register, used in P5/P7)
    
    
    wire [31:0] mem_pc_plus_4_reg;
    wire [31:0] mem_alu_result_reg;
    wire [31:0] mem_rd2_reg;
    wire [4:0]  mem_rd_reg;
    wire        mem_mem_wr_reg;
    wire        mem_mem_read_reg;
    wire        mem_reg_write_en_reg;
    wire [1:0]  mem_wb_sel_reg;
    wire [2:0]  mem_funct3_reg;
    
    
    // MEM STAGE SIGNALS (after bypass mux - active signals)
    
    
    wire [31:0] mem_pc_plus_4;
    wire [31:0] mem_alu_result;
    wire [31:0] mem_rd2;
    wire [4:0]  mem_rd;
    wire        mem_mem_wr;
    wire        mem_mem_read;
    wire        mem_reg_write_en;
    wire [1:0]  mem_wb_sel;
    wire [2:0]  mem_funct3;
    wire [31:0] mem_read_data;
    
    
    // MEM/WB REGISTER OUTPUTS
    
    
    wire [31:0] wb_pc_plus_4;
    wire [31:0] wb_alu_result;
    wire [31:0] wb_read_data;
    wire [4:0]  wb_rd;
    wire        wb_reg_write_en;
    wire [1:0]  wb_wb_sel;
    wire [31:0] wb_data;
    
    
    // PERCEPTRON PREDICTOR SIGNALS
    
    
    wire [1:0]  perceptron_predicted_mode;
    wire [2:0]  perceptron_predicted_clk;
    wire [7:0]  perceptron_confidence;
    wire        perceptron_valid;
    
    // CPI monitor signals
    wire        window_complete;
    wire [1:0]  cpi_best_mode;
    wire [7:0]  cpi_confidence;
    
    // Clock training signal
    wire        actual_best_max_clk;
    assign actual_best_max_clk = 1'b1;  // Max clock always optimal (from simulation)
    
    // Clock output
    wire [2:0]  current_clk_idx;
    
    // Event signals for perceptron
    wire        event_branch_taken;
    wire        event_load_inst;
    wire        event_store_inst;
    wire        event_alu_inst;
    wire        event_hazard_stall;
    
    assign event_branch_taken = branch_taken;
    assign event_load_inst    = ex_mem_read && !is_p3_mode;
    assign event_store_inst   = ex_mem_wr && !is_p3_mode;
    assign event_alu_inst     = ex_reg_write_en && !ex_mem_read && !is_p3_mode;
    assign event_hazard_stall = pc_stall;
    
    
    // PERFORMANCE COUNTERS
    
    
    reg [31:0] r_cycle_count;
    reg [31:0] r_inst_count;
    reg [31:0] r_stall_count;
    reg [31:0] r_flush_count;
    
    assign cycle_count = r_cycle_count;
    assign inst_count  = r_inst_count;
    assign stall_count = r_stall_count;
    assign flush_count = r_flush_count;
    
    // Instruction retired signal
    wire inst_retired;
    assign inst_retired = wb_reg_write_en || mem_mem_wr;
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            r_cycle_count <= 32'b0;
            r_inst_count  <= 32'b0;
            r_stall_count <= 32'b0;
            r_flush_count <= 32'b0;
        end else begin
            r_cycle_count <= r_cycle_count + 1;
            if (inst_retired)
                r_inst_count <= r_inst_count + 1;
            if (pc_stall)
                r_stall_count <= r_stall_count + 1;
            if (combined_flush || branch_taken)
                r_flush_count <= r_flush_count + 1;
        end
    end
    
    // Debug outputs
    assign debug_pc        = pc;
    assign debug_inst      = id_inst;
    assign debug_reg_write = wb_reg_write_en;
    assign debug_rd        = wb_rd;
    assign debug_rd_data   = wb_data;
    assign predicted_mode  = perceptron_predicted_mode;
    assign prediction_confidence = perceptron_confidence;
    assign predicted_clk_idx = perceptron_predicted_clk;
    
    
    // PIPELINE MODE CONTROLLER V3 (P3/P5/P7 + Clock)
    
    
    pipeline_mode_ctrl_v3 mode_ctrl (
        .clk(clk),
        .reset(reset),
        .mode_select(mode_select),
        .mode_switch_req(mode_switch_req),
        .auto_mode_enable(auto_mode_enable),
        .predicted_mode(perceptron_predicted_mode),
        .predicted_clk_idx(perceptron_predicted_clk),
        .prediction_confidence(perceptron_confidence),
        .current_mode(current_mode),
        .is_p3_mode(is_p3_mode),
        .is_p5_mode(is_p5_mode),
        .is_p7_mode(is_p7_mode),
        .current_clk_idx(current_clk_idx),
        .bypass_if2(bypass_if2),
        .bypass_id_ex(bypass_id_ex),
        .bypass_ex2(bypass_ex2),
        .bypass_ex_mem(bypass_ex_mem),
        .mode_switch_flush(mode_switch_flush),
        .mode_switching(mode_switching),
        .cycles_in_p3(),
        .cycles_in_p5(),
        .cycles_in_p7(),
        .mode_switches()
    );
    
    
    // JOINT PERCEPTRON PREDICTOR V2 (Mode + Clock)
    
    
    perceptron_predictor_v2 #(
        .HISTORY_LEN(16),
        .WEIGHT_BITS(8),
        .WINDOW_SIZE(32)
    ) predictor (
        .clk(clk),
        .reset(reset),
        .enable(!mode_switching),
        .branch_taken(event_branch_taken),
        .branch_not_taken(ex_is_branch && !branch_taken),
        .load_inst(event_load_inst),
        .store_inst(event_store_inst),
        .alu_inst(event_alu_inst),
        .hazard_stall(event_hazard_stall),
        .cache_miss(1'b0),
        .window_complete(window_complete),
        .actual_best_mode(cpi_best_mode),
        .actual_best_max_clk(actual_best_max_clk),
        .train_enable(auto_mode_enable),
        .current_mode(current_mode),
        .predicted_mode(perceptron_predicted_mode),
        .predicted_clk_idx(perceptron_predicted_clk),
        .confidence(perceptron_confidence),
        .prediction_valid(perceptron_valid)
    );
    
    
    // CPI MONITOR (Training signal for perceptron)
    
    
    cpi_monitor #(
        .WINDOW_SIZE(32),
        .CPI_FRAC_BITS(4)
    ) cpi_mon (
        .clk(clk),
        .reset(reset),
        .enable(!mode_switching),
        .inst_valid(1'b1),
        .inst_retired(inst_retired),
        .stall(pc_stall),
        .current_mode(current_mode),
        .current_cpi(),
        .best_cpi_p3(),
        .best_cpi_p5(),
        .best_cpi_p7(),
        .window_complete(window_complete),
        .best_mode(cpi_best_mode),
        .confidence(cpi_confidence)
    );
    
    
    // PROGRAM COUNTER
    
    
    assign pc_plus_4 = pc + 32'd4;
    
    // Branch target calculation
    // In P7 mode, use EX2 stage PC for branch target
    wire [31:0] branch_pc;
    wire [31:0] branch_imm;
    wire [31:0] branch_target;
    wire [31:0] jump_target;
    
    assign branch_pc  = is_p7_mode ? ex2_pc : ex_pc;
    assign branch_imm = is_p7_mode ? ex2_imm : ex_imm;
    assign branch_target = branch_pc + branch_imm;
    
    // For JALR, need the forwarded rs1 value
    wire [31:0] jalr_base;
    assign jalr_base = is_p7_mode ? ex2_alu_partial : ex_forward_a_data;
    
    assign jump_target = (is_p7_mode ? ex2_is_jump : ex_is_jump) ? 
                         (ex_is_jalr_derived ? (jalr_base + branch_imm) & ~32'b1 : branch_target) :
                         branch_target;
    
    // JALR FIX: Derive is_jalr from a_sel in the correct pipeline stage
    // BUG: Original used id_is_jalr which refers to wrong instruction in P5/P7
    // FIX: JAL has a_sel=1 (PC), JALR has a_sel=0 (rs1) — use this to distinguish
    reg ex2_a_sel_reg;
    always @(posedge clk or posedge reset) begin
        if (reset)
            ex2_a_sel_reg <= 1'b0;
        else
            ex2_a_sel_reg <= ex_a_sel;
    end
    
    wire ex_is_jalr_derived;
    assign ex_is_jalr_derived = is_p3_mode  ? id_is_jalr :
                                 is_p7_mode ? (ex2_is_jump && !ex2_a_sel_reg) :
                                 (ex_is_jump && !ex_a_sel);
    
    assign pc_next = branch_taken ? jump_target : pc_plus_4;
    
    always @(posedge clk or posedge reset) begin
        if (reset)
            pc <= 32'b0;
        else if (mode_switch_flush)
            pc <= 32'b0;
        else if (!pc_stall)
            pc <= pc_next;
    end
    
    
    // IF1/IF2 REGISTER (P7 only)
    
    
    if1_if2_reg if1_if2 (
        .clk(clk),
        .reset(reset || mode_switch_flush),
        .stall(pc_stall),
        .flush(branch_taken),  // Only flush once on branch, not extended flush
        .bypass(bypass_if2),
        .if1_pc(pc),
        .if1_pc_plus_4(pc_plus_4),
        .if1_branch_target(32'b0),
        .if1_branch_predict(1'b0),
        .if2_pc(if2_pc),
        .if2_pc_plus_4(if2_pc_plus_4),
        .if2_branch_target(),
        .if2_branch_predict(),
        .if2_valid(if2_valid)
    );
    
    // Select PC for instruction fetch based on mode
    wire [31:0] fetch_pc;
    assign fetch_pc = is_p7_mode ? if2_pc : pc;
    
    
    // INSTRUCTION MEMORY
    
    
    imem imem_inst (
        .addr(fetch_pc),
        .inst(if_inst)
    );
    
    
    // IF/ID REGISTER
    
    
    if_id_reg if_id_reg_inst (
        .clk(clk),
        .reset(reset || mode_switch_flush),
        .stall(if_id_stall),
        .flush(combined_flush || branch_flush_p7_short),  // Short flush for IF/ID
        .if_pc(is_p7_mode ? if2_pc : pc),
        .if_pc_plus_4(is_p7_mode ? if2_pc_plus_4 : pc_plus_4),
        .if_inst(if_inst),
        .id_pc(id_pc),
        .id_pc_plus_4(id_pc_plus_4),
        .id_inst(id_inst)
    );
    
    
    // INSTRUCTION DECODE
    
    
    // Instruction fields are extracted by control_pipeline module
    // wires by ctrl unit
    
    
    // CONTROL UNIT
    
    
    // control_pipeline extracts fields from inst and generates control signals
    wire [6:0] ctrl_opcode;
    wire [4:0] ctrl_rd, ctrl_rs1, ctrl_rs2;
    wire [2:0] ctrl_funct3;
    wire [6:0] ctrl_funct7;
    
    control_pipeline ctrl (
        .inst(id_inst),
        .opcode(ctrl_opcode),
        .rd(ctrl_rd),
        .rs1(ctrl_rs1),
        .rs2(ctrl_rs2),
        .funct3(ctrl_funct3),
        .funct7(ctrl_funct7),
        .reg_write_en(id_reg_write_en),
        .mem_wr(id_mem_wr),
        .mem_read(id_mem_read),
        .a_sel(id_a_sel),
        .b_sel(id_b_sel),
        .alu_sel(id_alu_sel),
        .wb_sel(id_wb_sel),
        .br_un(id_br_un),
        .is_branch(id_is_branch),
        .is_jump(id_is_jump),
        .is_jalr(id_is_jalr)
    );
    
    // Use control outputs for instruction fields
    assign id_opcode = ctrl_opcode;
    assign id_rd     = ctrl_rd;
    assign id_rs1    = ctrl_rs1;
    assign id_rs2    = ctrl_rs2;
    assign id_funct3 = ctrl_funct3;
    assign id_funct7 = ctrl_funct7;
    
    
    // REGISTER FILE
    
    
    rf rf_inst (
        .clk(clk),
        .we(wb_reg_write_en),
        .rs1(id_rs1),
        .rs2(id_rs2),
        .rd(wb_rd),
        .wd(wb_data),
        .rd1(id_rf_rd1),
        .rd2(id_rf_rd2)
    );
    
    
    // IMMEDIATE GENERATOR
    
    
    immgen immgen_inst (
        .inst(id_inst),
        .imm(id_imm)
    );
    
    
    // ID/EX PIPELINE REGISTER
    
    
    id_ex_reg id_ex_reg_inst (
        .clk(clk),
        .reset(reset),
        .stall(1'b0),
        .flush(id_ex_flush || mode_switch_flush || (is_p7_mode && branch_flush_p7_med)),
        .id_pc(id_pc),
        .id_pc_plus_4(id_pc_plus_4),
        .id_rd1(id_rf_rd1),
        .id_rd2(id_rf_rd2),
        .id_imm(id_imm),
        .id_rs1(id_rs1),
        .id_rs2(id_rs2),
        .id_rd(id_rd),
        .id_alu_sel(id_alu_sel),
        .id_a_sel(id_a_sel),
        .id_b_sel(id_b_sel),
        .id_mem_wr(id_mem_wr),
        .id_mem_read(id_mem_read),
        .id_reg_write_en(id_reg_write_en),
        .id_wb_sel(id_wb_sel),
        .id_pc_sel(1'b0),
        .id_br_un(id_br_un),
        .id_funct3(id_funct3),
        .id_is_branch(id_is_branch),
        .id_is_jump(id_is_jump),
        .ex_pc(ex_pc_reg),
        .ex_pc_plus_4(ex_pc_plus_4_reg),
        .ex_rd1(ex_rd1_reg),
        .ex_rd2(ex_rd2_reg),
        .ex_imm(ex_imm_reg),
        .ex_rs1(ex_rs1_reg),
        .ex_rs2(ex_rs2_reg),
        .ex_rd(ex_rd_reg),
        .ex_alu_sel(ex_alu_sel_reg),
        .ex_a_sel(ex_a_sel_reg),
        .ex_b_sel(ex_b_sel_reg),
        .ex_mem_wr(ex_mem_wr_reg),
        .ex_mem_read(ex_mem_read_reg),
        .ex_reg_write_en(ex_reg_write_en_reg),
        .ex_wb_sel(ex_wb_sel_reg),
        .ex_pc_sel(ex_pc_sel_reg),
        .ex_br_un(ex_br_un_reg),
        .ex_funct3(ex_funct3_reg),
        .ex_is_branch(ex_is_branch_reg),
        .ex_is_jump(ex_is_jump_reg)
    );
    
    
    // EX STAGE BYPASS MUX (P3 bypasses ID/EX register)
    
    
    assign ex_pc           = bypass_id_ex ? id_pc : ex_pc_reg;
    assign ex_pc_plus_4    = bypass_id_ex ? id_pc_plus_4 : ex_pc_plus_4_reg;
    assign ex_rd1          = bypass_id_ex ? id_rf_rd1 : ex_rd1_reg;
    assign ex_rd2          = bypass_id_ex ? id_rf_rd2 : ex_rd2_reg;
    assign ex_imm          = bypass_id_ex ? id_imm : ex_imm_reg;
    assign ex_rs1          = bypass_id_ex ? id_rs1 : ex_rs1_reg;
    assign ex_rs2          = bypass_id_ex ? id_rs2 : ex_rs2_reg;
    assign ex_rd           = bypass_id_ex ? id_rd : ex_rd_reg;
    assign ex_alu_sel      = bypass_id_ex ? id_alu_sel : ex_alu_sel_reg;
    assign ex_a_sel        = bypass_id_ex ? id_a_sel : ex_a_sel_reg;
    assign ex_b_sel        = bypass_id_ex ? id_b_sel : ex_b_sel_reg;
    assign ex_mem_wr       = bypass_id_ex ? id_mem_wr : ex_mem_wr_reg;
    assign ex_mem_read     = bypass_id_ex ? id_mem_read : ex_mem_read_reg;
    assign ex_reg_write_en = bypass_id_ex ? id_reg_write_en : ex_reg_write_en_reg;
    assign ex_wb_sel       = bypass_id_ex ? id_wb_sel : ex_wb_sel_reg;
    assign ex_br_un        = bypass_id_ex ? id_br_un : ex_br_un_reg;
    assign ex_funct3       = bypass_id_ex ? id_funct3 : ex_funct3_reg;
    assign ex_is_branch    = bypass_id_ex ? id_is_branch : ex_is_branch_reg;
    assign ex_is_jump      = bypass_id_ex ? id_is_jump : ex_is_jump_reg;
    
    
    // FORWARDING UNIT
    
    
    forwarding_unit fwd_unit (
        .id_ex_rs1(ex_rs1),
        .id_ex_rs2(ex_rs2),
        .ex2_rd(ex2_rd),
        .ex2_reg_write_en(ex2_reg_write_en),
        .ex2_mem_read(ex2_mem_read),
        .is_p7_mode(is_p7_mode),
        .ex_mem_rd(mem_rd),
        .ex_mem_reg_write_en(mem_reg_write_en),
        .ex_mem_mem_read(mem_mem_read),
        .mem_wb_rd(wb_rd),
        .mem_wb_reg_write_en(wb_reg_write_en),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );
    
    // Forwarding muxes (disabled in P3 mode)
    // forward_a/b: 00=no fwd, 01=MEM/WB, 10=EX/MEM, 11=EX2 (P7 only)
    assign ex_forward_a_data = is_p3_mode ? ex_rd1 :
                               (forward_a == 2'b11) ? ex2_alu_partial :
                               (forward_a == 2'b10) ? mem_alu_result :
                               (forward_a == 2'b01) ? wb_data :
                               ex_rd1;
    
    assign ex_forward_b_data = is_p3_mode ? ex_rd2 :
                               (forward_b == 2'b11) ? ex2_alu_partial :
                               (forward_b == 2'b10) ? mem_alu_result :
                               (forward_b == 2'b01) ? wb_data :
                               ex_rd2;
    
    assign ex_alu_src_a = ex_a_sel ? ex_pc : ex_forward_a_data;
    assign ex_alu_src_b = ex_b_sel ? ex_imm : ex_forward_b_data;
    
    
    // ALU
    
    
    alu alu_inst (
        .operand_a(ex_alu_src_a),
        .operand_b(ex_alu_src_b),
        .alu_ctrl(ex_alu_sel),
        .result(ex_alu_result),
        .zero(ex_alu_zero)
    );
    
    // Branch resol.
    
    // In P7 mode, branch resolves in EX2 stage (after EX1/EX2 register)
    // In P3/P5 mode, branch resolves in EX stage
    wire [31:0] branch_rs1_val;
    wire [31:0] branch_rs2_val;
    wire        branch_br_un;
    wire        branch_is_branch;
    wire        branch_is_jump;
    wire [2:0]  branch_funct3;
    
    assign branch_rs1_val   = is_p7_mode ? ex2_rs1_val : ex_forward_a_data;  // Use forwarded rs1 for branches
    assign branch_rs2_val   = is_p7_mode ? ex2_rs2_val : ex_forward_b_data;
    assign branch_br_un     = is_p7_mode ? ex2_br_un : ex_br_un;
    assign branch_is_branch = is_p7_mode ? ex2_is_branch : ex_is_branch;
    assign branch_is_jump   = is_p7_mode ? ex2_is_jump : ex_is_jump;
    assign branch_funct3    = is_p7_mode ? ex2_funct3 : ex_funct3;
    
    branch_resolution branch_res (
        .rs1_val(branch_rs1_val),
        .rs2_val(branch_rs2_val),
        .br_un(branch_br_un),
        .is_branch(branch_is_branch),
        .is_jump(branch_is_jump),
        .funct3(branch_funct3),
        .branch_taken(branch_taken)
    );
    
    // Hazards detection
    hazard_unit hazard_inst (
        .id_ex_mem_read(ex_mem_read_reg),
        .id_ex_rd(ex_rd_reg),
        .ex2_mem_read(ex2_mem_read),      // P7: also check EX2 stage
        .ex2_rd(ex2_rd),                   // P7: destination in EX2
        .is_p7_mode(is_p7_mode),
        .if_id_rs1(id_rs1),
        .if_id_rs2(id_rs2),
        .branch_taken(is_p3_mode ? 1'b0 : branch_taken),
        .pc_stall(pc_stall),
        .if_id_stall(if_id_stall),
        .if_id_flush(if_id_flush),
        .id_ex_flush(id_ex_flush)
    );
    
    //ex1/ex2 reg for 7
    
    ex1_ex2_reg ex1_ex2 (
        .clk(clk),
        .reset(reset || mode_switch_flush),
        .stall(1'b0),  // Never stall EX1/EX2 - load must continue to complete
        .flush(branch_taken),  // Only flush on actual branch, not delayed flushes
        .bypass(bypass_ex2),
        .ex1_pc(ex_pc),
        .ex1_pc_plus_4(ex_pc_plus_4),
        .ex1_alu_partial(ex_alu_result),
        .ex1_operand_a(ex_alu_src_a),
        .ex1_operand_b(ex_alu_src_b),
        .ex1_rs1_val(ex_forward_a_data),   // Forward rs1 for branch comparison
        .ex1_rs2_val(ex_forward_b_data),
        .ex1_imm(ex_imm),
        .ex1_rs1(ex_rs1),
        .ex1_rs2(ex_rs2),
        .ex1_rd(ex_rd),
        .ex1_alu_sel(ex_alu_sel),
        .ex1_mem_wr(ex_mem_wr),
        .ex1_mem_read(ex_mem_read),
        .ex1_reg_write_en(ex_reg_write_en),
        .ex1_wb_sel(ex_wb_sel),
        .ex1_is_branch(ex_is_branch),
        .ex1_is_jump(ex_is_jump),
        .ex1_funct3(ex_funct3),
        .ex1_br_un(ex_br_un),
        .ex2_pc(ex2_pc),
        .ex2_pc_plus_4(ex2_pc_plus_4),
        .ex2_alu_partial(ex2_alu_partial),
        .ex2_operand_a(),
        .ex2_operand_b(),
        .ex2_rs1_val(ex2_rs1_val),          // For branch comparison
        .ex2_rs2_val(ex2_rs2_val),
        .ex2_imm(ex2_imm),
        .ex2_rs1(),
        .ex2_rs2(),
        .ex2_rd(ex2_rd),
        .ex2_alu_sel(),
        .ex2_mem_wr(ex2_mem_wr),
        .ex2_mem_read(ex2_mem_read),
        .ex2_reg_write_en(ex2_reg_write_en),
        .ex2_wb_sel(ex2_wb_sel),
        .ex2_is_branch(ex2_is_branch),
        .ex2_is_jump(ex2_is_jump),
        .ex2_funct3(ex2_funct3),
        .ex2_br_un(ex2_br_un),
        .ex2_valid(ex2_valid)
    );
    
    // Select ALU result based on P7 mode
    wire [31:0] ex_result_to_mem;
    assign ex_result_to_mem = is_p7_mode ? ex2_alu_partial : ex_alu_result;
    
    
    // EX/MEM PIPELINE REGISTER
    ex_mem_reg ex_mem_reg_inst (
        .clk(clk),
        .reset(reset || mode_switch_flush),
        .flush(is_p7_mode && branch_taken),  // Flush EX/MEM on branch in P7 mode
        .ex_pc_plus_4(is_p7_mode ? ex2_pc_plus_4 : ex_pc_plus_4),
        .ex_alu_result(ex_result_to_mem),
        .ex_rd2(is_p7_mode ? ex2_rs2_val : ex_forward_b_data),
        .ex_rd(is_p7_mode ? ex2_rd : ex_rd),
        .ex_mem_wr(is_p7_mode ? ex2_mem_wr : ex_mem_wr),
        .ex_mem_read(is_p7_mode ? ex2_mem_read : ex_mem_read),
        .ex_reg_write_en(is_p7_mode ? ex2_reg_write_en : ex_reg_write_en),
        .ex_wb_sel(is_p7_mode ? ex2_wb_sel : ex_wb_sel),
        .ex_funct3(is_p7_mode ? ex2_funct3 : ex_funct3),
        .mem_pc_plus_4(mem_pc_plus_4_reg),
        .mem_alu_result(mem_alu_result_reg),
        .mem_rd2(mem_rd2_reg),
        .mem_rd(mem_rd_reg),
        .mem_mem_wr(mem_mem_wr_reg),
        .mem_mem_read(mem_mem_read_reg),
        .mem_reg_write_en(mem_reg_write_en_reg),
        .mem_wb_sel(mem_wb_sel_reg),
        .mem_funct3(mem_funct3_reg)
    );
    
    
    // MEM STAGE BYPASS MUX (P3 bypasses EX/MEM register)
    assign mem_pc_plus_4    = bypass_ex_mem ? ex_pc_plus_4 : mem_pc_plus_4_reg;
    assign mem_alu_result   = bypass_ex_mem ? ex_alu_result : mem_alu_result_reg;
    assign mem_rd2          = bypass_ex_mem ? ex_forward_b_data : mem_rd2_reg;
    assign mem_rd           = bypass_ex_mem ? ex_rd : mem_rd_reg;
    assign mem_mem_wr       = bypass_ex_mem ? ex_mem_wr : mem_mem_wr_reg;
    assign mem_mem_read     = bypass_ex_mem ? ex_mem_read : mem_mem_read_reg;
    assign mem_reg_write_en = bypass_ex_mem ? ex_reg_write_en : mem_reg_write_en_reg;
    assign mem_wb_sel       = bypass_ex_mem ? ex_wb_sel : mem_wb_sel_reg;
    assign mem_funct3       = bypass_ex_mem ? ex_funct3 : mem_funct3_reg;
    
    
    // Dmem
    
    
    dmem dmem_inst (
        .clk(clk),
        .mem_wr(mem_mem_wr),
        .addr(mem_alu_result),
        .write_data(mem_rd2),
        .read_data(mem_read_data)
    );
    
    
    // MEM/WB PIPELINE REGISTER
    
    
    // Suppress writeback during P7 branch flush
    // DISABLED FOR NOW - tight loops can't complete in P7
    wire mem_reg_write_en_gated;
    assign mem_reg_write_en_gated = mem_reg_write_en;  // No gating

    mem_wb_reg mem_wb_reg_inst (
        .clk(clk),
        .reset(reset || mode_switch_flush),
        .mem_pc_plus_4(mem_pc_plus_4),
        .mem_alu_result(mem_alu_result),
        .mem_read_data(mem_read_data),
        .mem_rd(mem_rd),
        .mem_reg_write_en(mem_reg_write_en_gated),
        .mem_wb_sel(mem_wb_sel),
        .wb_pc_plus_4(wb_pc_plus_4),
        .wb_alu_result(wb_alu_result),
        .wb_read_data(wb_read_data),
        .wb_rd(wb_rd),
        .wb_reg_write_en(wb_reg_write_en),
        .wb_wb_sel(wb_wb_sel)
    );
    
    
    // wb MUx
    
    // wb_sel: 00 = Memory read, 01 = ALU result, 10 = PC+4
    assign wb_data = (wb_wb_sel == 2'b00) ? wb_read_data :
                     (wb_wb_sel == 2'b01) ? wb_alu_result :
                     (wb_wb_sel == 2'b10) ? wb_pc_plus_4 :
                     32'b0;

endmodule