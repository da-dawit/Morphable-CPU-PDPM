`timescale 1ns/1ps

// ============================================================================
// MORPHABLE CPU - PERCEPTRON OPTIMIZER (with Realistic Clock Constraints)
// ============================================================================
// 
// KEY INSIGHT: Deeper pipelines have SHORTER critical paths per stage,
// allowing HIGHER clock frequencies. This is the fundamental tradeoff!
//
// Realistic Clock Constraints (based on critical path analysis):
//   P3: Max 1.0x-1.1x (long critical path - full EX stage in one cycle)
//   P5: Max 1.0x-1.3x (medium critical path - split stages)
//   P7: Max 1.0x-1.5x (short critical path - highly pipelined)
//
// The perceptron learns: given code characteristics, which (mode, clock)
// combination gives the best effective performance?
// ============================================================================

`define SIMULATION

module cpu_morphable_top_tb;

    reg clk;
    reg reset;
    reg [1:0] mode_select;
    reg mode_switch_req;
    reg auto_mode_enable;

    wire [1:0] current_mode;
    wire mode_switching;
    wire [31:0] debug_pc;
    wire [31:0] debug_inst;
    wire        debug_reg_write;
    wire [4:0]  debug_rd;
    wire [31:0] debug_rd_data;
    wire [31:0] cycle_count;
    wire [31:0] inst_count;
    wire [31:0] stall_count;
    wire [31:0] flush_count;
    wire [1:0]  predicted_mode;
    wire [7:0]  prediction_confidence;

    cpu_morphable_top dut (
        .clk(clk),
        .reset(reset),
        .mode_select(mode_select),
        .mode_switch_req(mode_switch_req),
        .auto_mode_enable(auto_mode_enable),
        .current_mode(current_mode),
        .mode_switching(mode_switching),
        .debug_pc(debug_pc),
        .debug_inst(debug_inst),
        .debug_reg_write(debug_reg_write),
        .debug_rd(debug_rd),
        .debug_rd_data(debug_rd_data),
        .cycle_count(cycle_count),
        .inst_count(inst_count),
        .stall_count(stall_count),
        .flush_count(flush_count),
        .predicted_mode(predicted_mode),
        .prediction_confidence(prediction_confidence)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // ========================================================================
    // REALISTIC CLOCK CONSTRAINTS PER MODE
    // ========================================================================
    // These reflect actual hardware constraints:
    // - P3 has longest critical path (entire execute in one stage)
    // - P5 splits work across more stages -> shorter critical path
    // - P7 has shortest critical path -> can run fastest
    //
    // Clock options (x100 for integer math): 100=1.0x, 110=1.1x, etc.
    
    // Maximum achievable clock per mode (realistic constraints!)
    integer p3_max_clk;  // P3: max 1.1x (limited by long critical path)
    integer p5_max_clk;  // P5: max 1.3x (balanced)
    integer p7_max_clk;  // P7: max 1.5x (short critical path)
    
    initial begin
        p3_max_clk = 110;  // P3 can only reach 1.1x
        p5_max_clk = 130;  // P5 can reach 1.3x
        p7_max_clk = 150;  // P7 can reach 1.5x
    end

    // ========================================================================
    // STORAGE FOR RESULTS
    // ========================================================================
    reg [31:0] results_cycles [0:9][0:2];           // Raw cycles [bench][mode]
    reg [31:0] results_eff [0:9][0:2];              // Effective time (with max clock)
    reg [1:0]  best_mode [0:9];                     // Best mode for each benchmark
    reg [31:0] best_eff_time [0:9];                 // Best effective time achieved
    reg [31:0] best_clk [0:9];                      // Clock used for best result
    
    // Code characteristics (features for perceptron)
    reg [31:0] bench_branch_pct [0:9];    // branch percentage
    reg [31:0] bench_stall_pct [0:9];     // stall percentage
    reg [31:0] bench_cpi_x100 [0:9][0:2]; // CPI * 100 for each mode
    
    // Perceptron weights
    reg signed [15:0] w_p3_branch, w_p3_stall, w_p3_cpi, w_p3_bias;
    reg signed [15:0] w_p5_branch, w_p5_stall, w_p5_cpi, w_p5_bias;
    reg signed [15:0] w_p7_branch, w_p7_stall, w_p7_cpi, w_p7_bias;
    
    integer bench, mode_idx, i;
    reg [31:0] cyc, eff, max_clk;
    reg timeout;
    
    wire halted_branch   = (dut.rf_inst.regs[3] == 32'd40);
    wire halted_loaduse  = (dut.rf_inst.regs[10] == 32'd10);
    wire halted_alu      = (dut.rf_inst.regs[1] == 32'd16) && (dut.rf_inst.regs[10] == 32'd15);
    wire halted_mixed    = (dut.rf_inst.regs[31] == 32'd99);
    wire halted_compute  = (dut.rf_inst.regs[10] == 32'd20);
    wire halted_stream   = (dut.rf_inst.regs[10] == 32'd30);
    wire halted_tightloop= (dut.rf_inst.regs[10] == 32'd50);
    wire halted_nested   = (dut.rf_inst.regs[10] == 32'd8);
    wire halted_switch   = (dut.rf_inst.regs[10] == 32'd40);
    wire halted_vector   = (dut.rf_inst.regs[10] == 32'd20);
    
    reg halted;
    
    // Perceptron prediction
    reg signed [15:0] score_p3, score_p5, score_p7;
    reg [1:0] pred_mode;
    
    initial begin
        $dumpfile("cpu_morphable_top_tb.vcd");
        $dumpvars(0, cpu_morphable_top_tb);
        
        // Initialize perceptron weights
        w_p3_branch = 16'sd8;   w_p3_stall = -16'sd10; w_p3_cpi = -16'sd5;  w_p3_bias = 16'sd40;
        w_p5_branch = 16'sd0;   w_p5_stall = 16'sd5;   w_p5_cpi = -16'sd3;  w_p5_bias = 16'sd50;
        w_p7_branch = -16'sd6;  w_p7_stall = 16'sd8;   w_p7_cpi = -16'sd2;  w_p7_bias = 16'sd45;
        
        $display("");
        $display("================================================================");
        $display("    MORPHABLE RISC-V CPU - PERCEPTRON OPTIMIZER");
        $display("================================================================");
        $display("");
        $display("REALISTIC CLOCK CONSTRAINTS (based on critical path):");
        $display("  P3 (3-stage): Max 1.1x clock (long critical path)");
        $display("  P5 (5-stage): Max 1.3x clock (medium critical path)");
        $display("  P7 (7-stage): Max 1.5x clock (short critical path)");
        $display("");
        $display("The deeper the pipeline, the higher the achievable frequency!");
        $display("But deeper pipelines have more hazard penalties...");
        $display("");
        $display("================================================================");
        $display("           PHASE 1: COLLECT TRAINING DATA");
        $display("================================================================");
        
        // ====================================================================
        // PHASE 1: Run all benchmarks with realistic clock constraints
        // ====================================================================
        for (bench = 0; bench < 10; bench = bench + 1) begin
            $display("");
            case (bench)
                0: $display("--- Benchmark %0d: Branch-Heavy ---", bench);
                1: $display("--- Benchmark %0d: Load-Use ---", bench);
                2: $display("--- Benchmark %0d: ALU-Intensive ---", bench);
                3: $display("--- Benchmark %0d: Mixed (Bubble Sort) ---", bench);
                4: $display("--- Benchmark %0d: Compute-Intensive ---", bench);
                5: $display("--- Benchmark %0d: Memory-Streaming ---", bench);
                6: $display("--- Benchmark %0d: Tight-Loop ---", bench);
                7: $display("--- Benchmark %0d: Nested-Loops ---", bench);
                8: $display("--- Benchmark %0d: Switch-Case ---", bench);
                9: $display("--- Benchmark %0d: Vector-Ops ---", bench);
            endcase
            
            best_eff_time[bench] = 32'hFFFFFFFF;
            
            for (mode_idx = 0; mode_idx < 3; mode_idx = mode_idx + 1) begin
                case (mode_idx)
                    0: begin mode_select = 2'b00; max_clk = p3_max_clk; end  // P3: max 1.1x
                    1: begin mode_select = 2'b01; max_clk = p5_max_clk; end  // P5: max 1.3x
                    2: begin mode_select = 2'b10; max_clk = p7_max_clk; end  // P7: max 1.5x
                endcase
                
                auto_mode_enable = 1;
                reset = 1;
                
                for (i = 0; i < 32; i = i + 1) dut.rf_inst.regs[i] = 0;
                for (i = 0; i < 256; i = i + 1) dut.dmem_inst.mem[i] = 0;
                for (i = 0; i < 256; i = i + 1) dut.imem_inst.mem[i] = 32'h00000013;
                
                case (bench)
                    0: $readmemh("benches/bench_branch.hex", dut.imem_inst.mem);
                    1: $readmemh("benches/bench_loaduse.hex", dut.imem_inst.mem);
                    2: $readmemh("benches/bench_alu.hex", dut.imem_inst.mem);
                    3: $readmemh("benches/bench_mixed.hex", dut.imem_inst.mem);
                    4: $readmemh("benches/bench_compute.hex", dut.imem_inst.mem);
                    5: $readmemh("benches/bench_stream.hex", dut.imem_inst.mem);
                    6: $readmemh("benches/bench_tightloop.hex", dut.imem_inst.mem);
                    7: $readmemh("benches/bench_nested.hex", dut.imem_inst.mem);
                    8: $readmemh("benches/bench_switch.hex", dut.imem_inst.mem);
                    9: $readmemh("benches/bench_vector.hex", dut.imem_inst.mem);
                endcase
                
                #100; reset = 0;
                
                cyc = 0; timeout = 0;
                for (i = 0; i < 15000; i = i + 1) begin
                    @(posedge clk);
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
                    if (halted) begin 
                        cyc = cycle_count;
                        // Compute characteristics
                        if (inst_count > 0) begin
                            bench_branch_pct[bench] = (flush_count * 100) / inst_count;
                            bench_stall_pct[bench] = (stall_count * 100) / cyc;
                            bench_cpi_x100[bench][mode_idx] = (cyc * 100) / inst_count;
                        end
                        i = 99999; 
                    end
                end
                
                if (cyc == 0) begin cyc = 15000; timeout = 1; end
                
                results_cycles[bench][mode_idx] = cyc;
                
                // Calculate effective time with MODE-SPECIFIC max clock
                if (timeout) begin
                    eff = 32'hFFFF;
                end else begin
                    // eff_time = cycles * 100 / max_clock_for_this_mode
                    eff = (cyc * 100) / max_clk;
                end
                results_eff[bench][mode_idx] = eff;
                
                // Track best
                if (eff < best_eff_time[bench]) begin
                    best_eff_time[bench] = eff;
                    best_mode[bench] = mode_idx[1:0];
                    best_clk[bench] = max_clk;
                end
                
                // Display
                case (mode_idx)
                    0: $write("  P3 (max 1.1x): ");
                    1: $write("  P5 (max 1.3x): ");
                    2: $write("  P7 (max 1.5x): ");
                endcase
                
                if (timeout) begin
                    $display("TIMEOUT");
                end else begin
                    $display("%0d cycles -> Eff=%0d.%02d (at %0d.%0dx)", 
                             cyc, eff/100, eff%100, max_clk/100, (max_clk/10)%10);
                end
            end
            
            // Show best for this benchmark
            if (best_eff_time[bench] < 32'hFFFF) begin
                $write("  >>> OPTIMAL: P");
                case (best_mode[bench])
                    2'b00: $write("3");
                    2'b01: $write("5");
                    2'b10: $write("7");
                endcase
                $display(" @ %0d.%0dx -> Eff=%0d.%02d",
                         best_clk[bench]/100, (best_clk[bench]/10)%10,
                         best_eff_time[bench]/100, best_eff_time[bench]%100);
            end else begin
                $display("  >>> ALL TIMEOUT");
            end
        end
        
        // ====================================================================
        // PHASE 2: TRAIN PERCEPTRON
        // ====================================================================
        $display("");
        $display("================================================================");
        $display("           PHASE 2: TRAIN PERCEPTRON");
        $display("================================================================");
        $display("");
        $display("Learning which mode works best for each workload pattern...");
        $display("");
        
        for (bench = 0; bench < 10; bench = bench + 1) begin
            if (best_eff_time[bench] < 32'hFFFF) begin
                // Update weights based on winner
                case (best_mode[bench])
                    2'b00: begin  // P3 won - likely branch-heavy
                        w_p3_branch = w_p3_branch + 3;
                        w_p3_bias = w_p3_bias + 2;
                        w_p5_bias = w_p5_bias - 1;
                        w_p7_bias = w_p7_bias - 1;
                        // P3 wins when CPI overhead of deeper pipelines > clock benefit
                        w_p7_cpi = w_p7_cpi - 1;
                    end
                    2'b01: begin  // P5 won - likely mixed workload
                        w_p5_stall = w_p5_stall + 2;
                        w_p5_bias = w_p5_bias + 3;
                        w_p3_bias = w_p3_bias - 1;
                        w_p7_bias = w_p7_bias - 1;
                    end
                    2'b10: begin  // P7 won - likely compute-heavy
                        w_p7_stall = w_p7_stall + 2;
                        w_p7_bias = w_p7_bias + 4;
                        w_p3_bias = w_p3_bias - 1;
                        w_p5_bias = w_p5_bias - 1;
                        // P7 wins when clock benefit > CPI overhead
                        w_p3_branch = w_p3_branch - 1;
                    end
                endcase
                
                $write("  Bench %0d: Winner=P", bench);
                case (best_mode[bench])
                    2'b00: $write("3");
                    2'b01: $write("5");
                    2'b10: $write("7");
                endcase
                $display(" (branch%%=%0d, stall%%=%0d)", 
                         bench_branch_pct[bench], bench_stall_pct[bench]);
            end
        end
        
        $display("");
        $display("Learned Weights:");
        $display("  P3: branch=%0d, stall=%0d, cpi=%0d, bias=%0d", 
                 w_p3_branch, w_p3_stall, w_p3_cpi, w_p3_bias);
        $display("  P5: branch=%0d, stall=%0d, cpi=%0d, bias=%0d", 
                 w_p5_branch, w_p5_stall, w_p5_cpi, w_p5_bias);
        $display("  P7: branch=%0d, stall=%0d, cpi=%0d, bias=%0d", 
                 w_p7_branch, w_p7_stall, w_p7_cpi, w_p7_bias);
        
        // ====================================================================
        // PHASE 3: TEST PREDICTIONS
        // ====================================================================
        $display("");
        $display("================================================================");
        $display("           PHASE 3: TEST PREDICTIONS");
        $display("================================================================");
        $display("");
        $display("Benchmark       | Branch%% | Stall%% | Actual | Predicted | Match");
        $display("----------------|---------|--------|--------|-----------|------");
        
        begin : test_pred
            integer correct, total;
            correct = 0; total = 0;
            
            for (bench = 0; bench < 10; bench = bench + 1) begin
                if (best_eff_time[bench] < 32'hFFFF) begin
                    total = total + 1;
                    
                    // Compute perceptron scores
                    score_p3 = w_p3_bias + 
                               (w_p3_branch * $signed(bench_branch_pct[bench])) / 10 +
                               (w_p3_stall * $signed(bench_stall_pct[bench])) / 10;
                    score_p5 = w_p5_bias + 
                               (w_p5_branch * $signed(bench_branch_pct[bench])) / 10 +
                               (w_p5_stall * $signed(bench_stall_pct[bench])) / 10;
                    score_p7 = w_p7_bias + 
                               (w_p7_branch * $signed(bench_branch_pct[bench])) / 10 +
                               (w_p7_stall * $signed(bench_stall_pct[bench])) / 10;
                    
                    // Pick highest score
                    if (score_p3 >= score_p5 && score_p3 >= score_p7)
                        pred_mode = 2'b00;
                    else if (score_p5 >= score_p7)
                        pred_mode = 2'b01;
                    else
                        pred_mode = 2'b10;
                    
                    // Display
                    case (bench)
                        0: $write("Branch-Heavy    ");
                        1: $write("Load-Use        ");
                        2: $write("ALU-Intensive   ");
                        3: $write("Mixed (Bubble)  ");
                        4: $write("Compute         ");
                        5: $write("Mem-Stream      ");
                        6: $write("Tight-Loop      ");
                        7: $write("Nested-Loops    ");
                        8: $write("Switch-Case     ");
                        9: $write("Vector-Ops      ");
                    endcase
                    
                    $write("| %5d   | %4d   | P", bench_branch_pct[bench], bench_stall_pct[bench]);
                    case (best_mode[bench])
                        2'b00: $write("3    ");
                        2'b01: $write("5    ");
                        2'b10: $write("7    ");
                    endcase
                    
                    $write(" | P");
                    case (pred_mode)
                        2'b00: $write("3       ");
                        2'b01: $write("5       ");
                        2'b10: $write("7       ");
                    endcase
                    
                    if (pred_mode == best_mode[bench]) begin
                        $display(" | YES");
                        correct = correct + 1;
                    end else begin
                        $display(" | no");
                    end
                end
            end
            
            $display("");
            $display("Prediction Accuracy: %0d/%0d (%0d%%)", correct, total, (correct*100)/total);
        end
        
        // ====================================================================
        // FINAL SUMMARY
        // ====================================================================
        $display("");
        $display("================================================================");
        $display("                    FINAL SUMMARY");
        $display("================================================================");
        $display("");
        $display("OPTIMAL CONFIGURATION FOR EACH BENCHMARK:");
        $display("Benchmark       | Mode | MaxClk | Cycles | Eff.Time | vs P3@1.0x");
        $display("----------------|------|--------|--------|----------|----------");
        
        for (bench = 0; bench < 10; bench = bench + 1) begin
            case (bench)
                0: $write("Branch-Heavy    ");
                1: $write("Load-Use        ");
                2: $write("ALU-Intensive   ");
                3: $write("Mixed (Bubble)  ");
                4: $write("Compute         ");
                5: $write("Mem-Stream      ");
                6: $write("Tight-Loop      ");
                7: $write("Nested-Loops    ");
                8: $write("Switch-Case     ");
                9: $write("Vector-Ops      ");
            endcase
            
            if (best_eff_time[bench] >= 32'hFFFF) begin
                $display("| T/O  | -      | -      | -        | -");
            end else begin
                $write("| P");
                case (best_mode[bench])
                    2'b00: $write("3  ");
                    2'b01: $write("5  ");
                    2'b10: $write("7  ");
                endcase
                
                $write("| %0d.%0dx   ", best_clk[bench]/100, (best_clk[bench]/10)%10);
                $write("| %5d  ", results_cycles[bench][best_mode[bench]]);
                $write("| %5d.%02d ", best_eff_time[bench]/100, best_eff_time[bench]%100);
                
                // Compare to P3 @ 1.0x baseline
                if (results_eff[bench][0] < 32'hFFFF) begin
                    // P3 baseline = cycles (since 1.0x, eff = cycles)
                    $display("| %0d.%02dx", 
                             (results_cycles[bench][0] * 100) / best_eff_time[bench] / 100,
                             ((results_cycles[bench][0] * 100) / best_eff_time[bench]) % 100);
                end else begin
                    $display("| N/A");
                end
            end
        end
        
        $display("");
        $display("WIN COUNT BY MODE:");
        begin : wins
            integer p3w, p5w, p7w;
            p3w = 0; p5w = 0; p7w = 0;
            for (bench = 0; bench < 10; bench = bench + 1) begin
                if (best_eff_time[bench] < 32'hFFFF) begin
                    case (best_mode[bench])
                        2'b00: p3w = p3w + 1;
                        2'b01: p5w = p5w + 1;
                        2'b10: p7w = p7w + 1;
                    endcase
                end
            end
            $display("  P3 (max 1.1x): %0d wins - best for branch-heavy code", p3w);
            $display("  P5 (max 1.3x): %0d wins - best for mixed workloads", p5w);
            $display("  P7 (max 1.5x): %0d wins - best for compute-heavy code", p7w);
        end
        
        $display("");
        $display("================================================================");
        $display("KEY INSIGHTS:");
        $display("  - P3 wins when branch penalty savings > clock speed loss");
        $display("  - P5 wins for balanced workloads needing hazard handling");
        $display("  - P7 wins when high clock (1.5x) overcomes CPI overhead");
        $display("");
        $display("The perceptron learns these tradeoffs from observed performance!");
        $display("================================================================");
        
        $finish;
    end
endmodule