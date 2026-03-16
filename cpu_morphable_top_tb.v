`timescale 1ns/1ps

// MORPHABLE CPU - 100-BENCHMARK TESTBENCH
// =========================================
// Benchmarks 0-9:   Original (custom halt conditions)
// Benchmarks 10-99: New (universal halt: x31 == 0xDEAD = 57005)
// NEWEST

`define SIMULATION
`define NUM_BENCHMARKS 100

module cpu_morphable_top_tb;

    reg clk, reset;
    reg [1:0] mode_select;
    reg mode_switch_req, auto_mode_enable;

    wire [1:0]  current_mode;
    wire        mode_switching;
    wire [31:0] debug_pc, debug_inst;
    wire        debug_reg_write;
    wire [4:0]  debug_rd;
    wire [31:0] debug_rd_data;
    wire [31:0] cycle_count, inst_count, stall_count, flush_count;
    wire [1:0]  predicted_mode;
    wire [7:0]  prediction_confidence;

    cpu_morphable_top dut (
        .clk(clk), .reset(reset),
        .mode_select(mode_select),
        .mode_switch_req(mode_switch_req),
        .auto_mode_enable(auto_mode_enable),
        .current_mode(current_mode),
        .mode_switching(mode_switching),
        .debug_pc(debug_pc), .debug_inst(debug_inst),
        .debug_reg_write(debug_reg_write),
        .debug_rd(debug_rd), .debug_rd_data(debug_rd_data),
        .cycle_count(cycle_count), .inst_count(inst_count),
        .stall_count(stall_count), .flush_count(flush_count),
        .predicted_mode(predicted_mode),
        .prediction_confidence(prediction_confidence)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // ============================================================
    // RESULTS STORAGE
    // ============================================================
    reg [31:0] raw_cycles [0:`NUM_BENCHMARKS-1][0:2];
    reg [31:0] eff_time   [0:`NUM_BENCHMARKS-1][0:2][0:5];
    reg [1:0]  best_mode  [0:`NUM_BENCHMARKS-1];
    reg [2:0]  best_clk_idx [0:`NUM_BENCHMARKS-1];
    reg [31:0] best_eff   [0:`NUM_BENCHMARKS-1];

    reg signed [31:0] feat_branch [0:`NUM_BENCHMARKS-1];
    reg signed [31:0] feat_ratio  [0:`NUM_BENCHMARKS-1];
    reg signed [31:0] feat_stall  [0:`NUM_BENCHMARKS-1];

    integer clk_mult [0:5];
    initial begin
        clk_mult[0] = 100; clk_mult[1] = 110; clk_mult[2] = 120;
        clk_mult[3] = 130; clk_mult[4] = 140; clk_mult[5] = 150;
    end

    integer max_clk_idx [0:2];
    initial begin
        max_clk_idx[0] = 1;  // P3: max 1.1x
        max_clk_idx[1] = 3;  // P5: max 1.3x
        max_clk_idx[2] = 5;  // P7: max 1.5x
    end

    integer bench, mode_idx, clk_idx, i;
    reg [31:0] cyc, eff, insts;
    reg timeout;

    // ============================================================
    // HALT DETECTION
    // ============================================================
    // Original 10 benchmarks (custom halt)
    wire halted_branch    = (dut.rf_inst.regs[3] == 32'd40);
    wire halted_loaduse   = (dut.rf_inst.regs[10] == 32'd10);
    wire halted_alu       = (dut.rf_inst.regs[1] == 32'd16) && (dut.rf_inst.regs[10] == 32'd15);
    wire halted_mixed     = (dut.rf_inst.regs[31] == 32'd99);
    wire halted_compute   = (dut.rf_inst.regs[10] == 32'd20);
    wire halted_stream    = (dut.rf_inst.regs[10] == 32'd30);
    wire halted_tightloop = (dut.rf_inst.regs[10] == 32'd50);
    wire halted_nested    = (dut.rf_inst.regs[10] == 32'd8);
    wire halted_switch    = (dut.rf_inst.regs[10] == 32'd40);
    wire halted_vector    = (dut.rf_inst.regs[10] == 32'd20);

    // Universal halt for benchmarks 10-99: x31 == 0xDEAD (57005)
    wire halted_universal = (dut.rf_inst.regs[31] == 32'h0000DEAD);

    reg halted;

    // ============================================================
    // TRACE OUTPUT
    // ============================================================
    wire trace_retired = dut.wb_reg_write_en || dut.mem_mem_wr;
    wire trace_load    = dut.wb_reg_write_en && (dut.wb_wb_sel == 2'b00);
    wire trace_store   = dut.mem_mem_wr;
    wire trace_alu     = dut.wb_reg_write_en && (dut.wb_wb_sel == 2'b01);
    wire trace_jlink   = dut.wb_reg_write_en && (dut.wb_wb_sel == 2'b10);
    wire trace_stall   = dut.pc_stall;
    wire trace_flush   = dut.branch_taken;
    integer trace_file;

    // ============================================================
    // MAIN SIMULATION
    // ============================================================
    initial begin
        $dumpfile("cpu_morphable_top_tb.vcd");
        $dumpvars(0, cpu_morphable_top_tb);

        trace_file = $fopen("trace_log.csv", "w");
        if (trace_file == 0) begin
            $display("ERROR: Could not open trace_log.csv!");
            $finish;
        end
        $fwrite(trace_file, "EVENT,MODE,BENCH,CYCLE,TYPE,PC\n");

        $display("");
        $display("================================================================");
        $display("  MORPHABLE CPU - 100-BENCHMARK EVALUATION");
        $display("================================================================");
        $display("  Benchmarks 0-9:   Original (custom halt)");
        $display("  Benchmarks 10-99: Generated (universal halt x31=0xDEAD)");
        $display("");
        $display("  Modes: P3 (max 1.1x), P5 (max 1.3x), P7 (max 1.5x)");
        $display("================================================================");

        // ============================================================
        // PHASE 1: RUN ALL BENCHMARKS IN ALL MODES
        // ============================================================
        $display("");
        $display("PHASE 1: EXHAUSTIVE DATA COLLECTION");
        $display("====================================");

        for (bench = 0; bench < `NUM_BENCHMARKS; bench = bench + 1) begin
            if (bench % 10 == 0)
                $display("  Running benchmarks %0d-%0d...", bench, bench + 9);

            best_eff[bench] = 32'hFFFFFFFF;
            feat_branch[bench] = 0;
            feat_ratio[bench] = 100;
            feat_stall[bench] = 0;

            for (mode_idx = 0; mode_idx < 3; mode_idx = mode_idx + 1) begin
                mode_select = mode_idx[1:0];
                auto_mode_enable = 1;
                reset = 1;

                // Clear state
                for (i = 0; i < 32; i = i + 1) dut.rf_inst.regs[i] = 0;
                for (i = 0; i < 256; i = i + 1) dut.dmem_inst.mem[i] = 0;
                for (i = 0; i < 256; i = i + 1) dut.imem_inst.mem[i] = 32'h00000013; // NOP

                // Load benchmark
                case (bench)
                    0:  $readmemh("benches/bench_branch.hex", dut.imem_inst.mem);
                    1:  $readmemh("benches/bench_loaduse.hex", dut.imem_inst.mem);
                    2:  $readmemh("benches/bench_alu.hex", dut.imem_inst.mem);
                    3:  $readmemh("benches/bench_mixed.hex", dut.imem_inst.mem);
                    4:  $readmemh("benches/bench_compute.hex", dut.imem_inst.mem);
                    5:  $readmemh("benches/bench_stream.hex", dut.imem_inst.mem);
                    6:  $readmemh("benches/bench_tightloop.hex", dut.imem_inst.mem);
                    7:  $readmemh("benches/bench_nested.hex", dut.imem_inst.mem);
                    8:  $readmemh("benches/bench_switch.hex", dut.imem_inst.mem);
                    9:  $readmemh("benches/bench_vector.hex", dut.imem_inst.mem);
                    default: begin
                        // Dynamic file loading for benchmarks 10-99
                        // Verilog $readmemh doesn't support string concatenation,
                        // so we use a helper approach with individual cases.
                        // This is auto-generated for benchmarks 10-99.
                        case (bench)
                            10: $readmemh("benches/bench_010.hex", dut.imem_inst.mem);
                            11: $readmemh("benches/bench_011.hex", dut.imem_inst.mem);
                            12: $readmemh("benches/bench_012.hex", dut.imem_inst.mem);
                            13: $readmemh("benches/bench_013.hex", dut.imem_inst.mem);
                            14: $readmemh("benches/bench_014.hex", dut.imem_inst.mem);
                            15: $readmemh("benches/bench_015.hex", dut.imem_inst.mem);
                            16: $readmemh("benches/bench_016.hex", dut.imem_inst.mem);
                            17: $readmemh("benches/bench_017.hex", dut.imem_inst.mem);
                            18: $readmemh("benches/bench_018.hex", dut.imem_inst.mem);
                            19: $readmemh("benches/bench_019.hex", dut.imem_inst.mem);
                            20: $readmemh("benches/bench_020.hex", dut.imem_inst.mem);
                            21: $readmemh("benches/bench_021.hex", dut.imem_inst.mem);
                            22: $readmemh("benches/bench_022.hex", dut.imem_inst.mem);
                            23: $readmemh("benches/bench_023.hex", dut.imem_inst.mem);
                            24: $readmemh("benches/bench_024.hex", dut.imem_inst.mem);
                            25: $readmemh("benches/bench_025.hex", dut.imem_inst.mem);
                            26: $readmemh("benches/bench_026.hex", dut.imem_inst.mem);
                            27: $readmemh("benches/bench_027.hex", dut.imem_inst.mem);
                            28: $readmemh("benches/bench_028.hex", dut.imem_inst.mem);
                            29: $readmemh("benches/bench_029.hex", dut.imem_inst.mem);
                            30: $readmemh("benches/bench_030.hex", dut.imem_inst.mem);
                            31: $readmemh("benches/bench_031.hex", dut.imem_inst.mem);
                            32: $readmemh("benches/bench_032.hex", dut.imem_inst.mem);
                            33: $readmemh("benches/bench_033.hex", dut.imem_inst.mem);
                            34: $readmemh("benches/bench_034.hex", dut.imem_inst.mem);
                            35: $readmemh("benches/bench_035.hex", dut.imem_inst.mem);
                            36: $readmemh("benches/bench_036.hex", dut.imem_inst.mem);
                            37: $readmemh("benches/bench_037.hex", dut.imem_inst.mem);
                            38: $readmemh("benches/bench_038.hex", dut.imem_inst.mem);
                            39: $readmemh("benches/bench_039.hex", dut.imem_inst.mem);
                            40: $readmemh("benches/bench_040.hex", dut.imem_inst.mem);
                            41: $readmemh("benches/bench_041.hex", dut.imem_inst.mem);
                            42: $readmemh("benches/bench_042.hex", dut.imem_inst.mem);
                            43: $readmemh("benches/bench_043.hex", dut.imem_inst.mem);
                            44: $readmemh("benches/bench_044.hex", dut.imem_inst.mem);
                            45: $readmemh("benches/bench_045.hex", dut.imem_inst.mem);
                            46: $readmemh("benches/bench_046.hex", dut.imem_inst.mem);
                            47: $readmemh("benches/bench_047.hex", dut.imem_inst.mem);
                            48: $readmemh("benches/bench_048.hex", dut.imem_inst.mem);
                            49: $readmemh("benches/bench_049.hex", dut.imem_inst.mem);
                            50: $readmemh("benches/bench_050.hex", dut.imem_inst.mem);
                            51: $readmemh("benches/bench_051.hex", dut.imem_inst.mem);
                            52: $readmemh("benches/bench_052.hex", dut.imem_inst.mem);
                            53: $readmemh("benches/bench_053.hex", dut.imem_inst.mem);
                            54: $readmemh("benches/bench_054.hex", dut.imem_inst.mem);
                            55: $readmemh("benches/bench_055.hex", dut.imem_inst.mem);
                            56: $readmemh("benches/bench_056.hex", dut.imem_inst.mem);
                            57: $readmemh("benches/bench_057.hex", dut.imem_inst.mem);
                            58: $readmemh("benches/bench_058.hex", dut.imem_inst.mem);
                            59: $readmemh("benches/bench_059.hex", dut.imem_inst.mem);
                            60: $readmemh("benches/bench_060.hex", dut.imem_inst.mem);
                            61: $readmemh("benches/bench_061.hex", dut.imem_inst.mem);
                            62: $readmemh("benches/bench_062.hex", dut.imem_inst.mem);
                            63: $readmemh("benches/bench_063.hex", dut.imem_inst.mem);
                            64: $readmemh("benches/bench_064.hex", dut.imem_inst.mem);
                            65: $readmemh("benches/bench_065.hex", dut.imem_inst.mem);
                            66: $readmemh("benches/bench_066.hex", dut.imem_inst.mem);
                            67: $readmemh("benches/bench_067.hex", dut.imem_inst.mem);
                            68: $readmemh("benches/bench_068.hex", dut.imem_inst.mem);
                            69: $readmemh("benches/bench_069.hex", dut.imem_inst.mem);
                            70: $readmemh("benches/bench_070.hex", dut.imem_inst.mem);
                            71: $readmemh("benches/bench_071.hex", dut.imem_inst.mem);
                            72: $readmemh("benches/bench_072.hex", dut.imem_inst.mem);
                            73: $readmemh("benches/bench_073.hex", dut.imem_inst.mem);
                            74: $readmemh("benches/bench_074.hex", dut.imem_inst.mem);
                            75: $readmemh("benches/bench_075.hex", dut.imem_inst.mem);
                            76: $readmemh("benches/bench_076.hex", dut.imem_inst.mem);
                            77: $readmemh("benches/bench_077.hex", dut.imem_inst.mem);
                            78: $readmemh("benches/bench_078.hex", dut.imem_inst.mem);
                            79: $readmemh("benches/bench_079.hex", dut.imem_inst.mem);
                            80: $readmemh("benches/bench_080.hex", dut.imem_inst.mem);
                            81: $readmemh("benches/bench_081.hex", dut.imem_inst.mem);
                            82: $readmemh("benches/bench_082.hex", dut.imem_inst.mem);
                            83: $readmemh("benches/bench_083.hex", dut.imem_inst.mem);
                            84: $readmemh("benches/bench_084.hex", dut.imem_inst.mem);
                            85: $readmemh("benches/bench_085.hex", dut.imem_inst.mem);
                            86: $readmemh("benches/bench_086.hex", dut.imem_inst.mem);
                            87: $readmemh("benches/bench_087.hex", dut.imem_inst.mem);
                            88: $readmemh("benches/bench_088.hex", dut.imem_inst.mem);
                            89: $readmemh("benches/bench_089.hex", dut.imem_inst.mem);
                            90: $readmemh("benches/bench_090.hex", dut.imem_inst.mem);
                            91: $readmemh("benches/bench_091.hex", dut.imem_inst.mem);
                            92: $readmemh("benches/bench_092.hex", dut.imem_inst.mem);
                            93: $readmemh("benches/bench_093.hex", dut.imem_inst.mem);
                            94: $readmemh("benches/bench_094.hex", dut.imem_inst.mem);
                            95: $readmemh("benches/bench_095.hex", dut.imem_inst.mem);
                            96: $readmemh("benches/bench_096.hex", dut.imem_inst.mem);
                            97: $readmemh("benches/bench_097.hex", dut.imem_inst.mem);
                            98: $readmemh("benches/bench_098.hex", dut.imem_inst.mem);
                            99: $readmemh("benches/bench_099.hex", dut.imem_inst.mem);
                        endcase
                    end
                endcase

                #100; reset = 0;

                cyc = 0; timeout = 0; insts = 0;
                for (i = 0; i < 15000; i = i + 1) begin
                    @(posedge clk);
                    #1;

                    // Trace logging
                    if (!reset) begin
                        if (trace_stall)         $fwrite(trace_file, "T,%0d,%0d,%0d,S,%h\n", mode_idx, bench, i, debug_pc);
                        else if (trace_flush)    $fwrite(trace_file, "T,%0d,%0d,%0d,F,%h\n", mode_idx, bench, i, debug_pc);
                        else if (trace_store)    $fwrite(trace_file, "T,%0d,%0d,%0d,ST,%h\n", mode_idx, bench, i, debug_pc);
                        else if (trace_load)     $fwrite(trace_file, "T,%0d,%0d,%0d,LD,%h\n", mode_idx, bench, i, debug_pc);
                        else if (trace_jlink)    $fwrite(trace_file, "T,%0d,%0d,%0d,J,%h\n", mode_idx, bench, i, debug_pc);
                        else if (trace_alu)      $fwrite(trace_file, "T,%0d,%0d,%0d,A,%h\n", mode_idx, bench, i, debug_pc);
                        else if (trace_retired)  $fwrite(trace_file, "T,%0d,%0d,%0d,O,%h\n", mode_idx, bench, i, debug_pc);
                        else                     $fwrite(trace_file, "T,%0d,%0d,%0d,B,%h\n", mode_idx, bench, i, debug_pc);
                    end

                    // Halt detection
                    if (bench < 10) begin
                        case (bench)
                            0: halted = halted_branch;
                            1: halted = halted_loaduse;
                            2: halted = halted_alu;
                            3: halted = halted_mixed;
                            4: halted = halted_compute;
                            5: halted = halted_stream;
                            6: halted = halted_tightloop;
                            7: halted = halted_nested;
                            8: halted = halted_switch;
                            9: halted = halted_vector;
                        endcase
                    end else begin
                        halted = halted_universal;
                    end

                    if (halted) begin
                        cyc = cycle_count;
                        insts = inst_count;
                        $fwrite(trace_file, "TSUM,%0d,%0d,%0d,%0d,%0d,%0d\n",
                                mode_idx, bench, cyc, insts, stall_count, flush_count);
                        i = 99999;
                    end
                end

                if (cyc == 0) begin cyc = 15000; insts = 1; timeout = 1; end

                raw_cycles[bench][mode_idx] = cyc;

                // Extract features from P5 runs
                if (mode_idx == 1 && !timeout && insts > 0) begin
                    feat_branch[bench] = (flush_count * 100) / insts;
                    feat_stall[bench] = (stall_count * 100) / cyc;
                end

                // CPI ratio from P7 vs P3
                if (mode_idx == 2 && !timeout && raw_cycles[bench][0] < 15000 && raw_cycles[bench][0] > 0) begin
                    feat_ratio[bench] = ((cyc * 100) / raw_cycles[bench][0]) - 100;
                    if (feat_ratio[bench] < 0) feat_ratio[bench] = 0;
                end

                // Calculate effective time for each clock
                for (clk_idx = 0; clk_idx <= max_clk_idx[mode_idx]; clk_idx = clk_idx + 1) begin
                    if (timeout) begin
                        eff_time[bench][mode_idx][clk_idx] = 32'hFFFF;
                    end else begin
                        eff = (cyc * 100) / clk_mult[clk_idx];
                        eff_time[bench][mode_idx][clk_idx] = eff;
                        if (eff < best_eff[bench]) begin
                            best_eff[bench] = eff;
                            best_mode[bench] = mode_idx[1:0];
                            best_clk_idx[bench] = clk_idx[2:0];
                        end
                    end
                end
            end

            // Progress report every 10 benchmarks
            if ((bench + 1) % 10 == 0) begin
                $display("  Completed %0d/%0d benchmarks", bench + 1, `NUM_BENCHMARKS);
            end
        end

        // ============================================================
        // RESULTS SUMMARY
        // ============================================================
        $display("");
        $display("================================================================");
        $display("  RESULTS: %0d BENCHMARKS", `NUM_BENCHMARKS);
        $display("================================================================");
        $display("");
        $display("Bench | Mode | Clk  | Cycles | Eff.Time | Br%%  | Rat%% | St%%");
        $display("------|------|------|--------|----------|------|------|------");

        begin : summary
            integer p3w, p5w, p7w, valid;
            p3w = 0; p5w = 0; p7w = 0; valid = 0;

            for (bench = 0; bench < `NUM_BENCHMARKS; bench = bench + 1) begin
                if (best_eff[bench] < 32'hFFFF) begin
                    valid = valid + 1;
                    case (best_mode[bench])
                        2'b00: p3w = p3w + 1;
                        2'b01: p5w = p5w + 1;
                        2'b10: p7w = p7w + 1;
                    endcase

                    $write("%3d   | P", bench);
                    case (best_mode[bench])
                        2'b00: $write("3");
                        2'b01: $write("5");
                        2'b10: $write("7");
                    endcase
                    $display("   | %0d.%0dx | %5d  | %5d.%02d | %3d  | %3d  | %3d",
                             clk_mult[best_clk_idx[bench]]/100,
                             (clk_mult[best_clk_idx[bench]]/10)%10,
                             raw_cycles[bench][best_mode[bench]],
                             best_eff[bench]/100, best_eff[bench]%100,
                             feat_branch[bench], feat_ratio[bench], feat_stall[bench]);
                end else begin
                    $display("%3d   | T/O  | -    | -      | -        | -    | -    | -", bench);
                end
            end

            $display("");
            $display("Valid benchmarks: %0d / %0d", valid, `NUM_BENCHMARKS);
            $display("Win count: P3=%0d  P5=%0d  P7=%0d", p3w, p5w, p7w);
        end

        $fclose(trace_file);
        $display("");
        $display("=== TRACE SAVED TO trace_log.csv ===");
        $finish;
    end
endmodule
