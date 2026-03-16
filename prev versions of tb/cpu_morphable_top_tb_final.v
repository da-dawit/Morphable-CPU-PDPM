`timescale 1ns/1ps

// ============================================================================
// MORPHABLE CPU - HYBRID AI PREDICTOR
// ============================================================================
// Combines Decision Tree structure with Perceptron learning:
//   1. Decision tree provides the structure (handles non-linearity)
//   2. Perceptron weights fine-tune thresholds within each branch
//   3. Training adjusts thresholds based on misclassifications
//
// This is similar to a "Soft Decision Tree" used in modern ML!
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

    // Clock constraints
    integer p3_max_clk, p5_max_clk, p7_max_clk;
    initial begin
        p3_max_clk = 110;
        p5_max_clk = 130;
        p7_max_clk = 150;
    end

    // Results storage
    reg [31:0] results_cycles [0:9][0:2];
    reg [31:0] results_eff [0:9][0:2];
    reg [1:0]  best_mode [0:9];
    reg [31:0] best_eff_time [0:9];
    reg [31:0] best_clk [0:9];
    
    // Features
    reg signed [31:0] feat_branch [0:9];
    reg signed [31:0] feat_cpi_ratio [0:9];
    reg signed [31:0] feat_stall [0:9];
    
    // ========================================================================
    // HYBRID AI: Learnable thresholds + perceptron scores
    // ========================================================================
    
    // Learnable thresholds (adjusted during training)
    integer thresh_p3_branch;     // Branch% threshold for P3
    integer thresh_p7_branch;     // Branch% upper limit for P7
    integer thresh_p7_ratio;      // CPI ratio threshold for P7
    integer thresh_p5_stall;      // Stall% threshold for P5
    
    // Perceptron weights for tie-breaking within regions
    reg signed [15:0] w_p3_score, w_p5_score, w_p7_score;
    
    // Confidence scores
    reg signed [31:0] confidence;
    
    integer bench, mode_idx, i, epoch;
    reg [31:0] cyc, eff, max_clk, insts;
    reg timeout;
    reg [1:0] pred_mode;
    integer errors, prev_errors;
    
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
    
    // ========================================================================
    // PREDICTION FUNCTION (Hybrid Decision Tree + Perceptron)
    // ========================================================================
    // This function implements the hybrid predictor
    task predict_mode;
        input [31:0] branch_pct;
        input [31:0] ratio_pct;
        input [31:0] stall_pct;
        output [1:0] prediction;
        output [31:0] conf;
        
        reg signed [31:0] score_p3, score_p5, score_p7;
        begin
            // Compute weighted scores for each mode
            // These act as "soft" decision boundaries
            
            // P3 score: High when branch% is high, ratio is high (deep pipe hurts)
            score_p3 = w_p3_score + (branch_pct * 3) + (ratio_pct / 2) - (stall_pct * 2);
            
            // P5 score: High when moderate branch%, has stalls
            score_p5 = w_p5_score + (stall_pct * 4) + 20;
            
            // P7 score: High when branch% is low, ratio is low
            score_p7 = w_p7_score + (100 - branch_pct) + (100 - ratio_pct) / 2;
            
            // Decision tree with soft boundaries
            if (branch_pct >= thresh_p3_branch && ratio_pct > 40) begin
                // High branch region - likely P3
                if (score_p3 > score_p5 + 10) 
                    prediction = 2'b00;  // P3
                else
                    prediction = 2'b01;  // P5 (close call)
                conf = score_p3 - score_p5;
            end
            else if (branch_pct <= thresh_p7_branch && ratio_pct <= thresh_p7_ratio) begin
                // Low branch, low ratio region - likely P7
                if (score_p7 > score_p5 + 5)
                    prediction = 2'b10;  // P7
                else
                    prediction = 2'b01;  // P5 (close call)
                conf = score_p7 - score_p5;
            end
            else if (stall_pct >= thresh_p5_stall) begin
                // High stall region - P5
                prediction = 2'b01;
                conf = score_p5;
            end
            else begin
                // Ambiguous region - use perceptron scores
                if (score_p3 >= score_p5 && score_p3 >= score_p7)
                    prediction = 2'b00;
                else if (score_p7 > score_p5)
                    prediction = 2'b10;
                else
                    prediction = 2'b01;
                    
                // Confidence is margin between top 2
                if (score_p3 >= score_p5 && score_p3 >= score_p7)
                    conf = score_p3 - (score_p5 > score_p7 ? score_p5 : score_p7);
                else if (score_p7 >= score_p5)
                    conf = score_p7 - score_p5;
                else
                    conf = score_p5 - (score_p3 > score_p7 ? score_p3 : score_p7);
            end
        end
    endtask
    
    initial begin
        $dumpfile("cpu_morphable_top_tb.vcd");
        $dumpvars(0, cpu_morphable_top_tb);
        
        // Initialize hybrid AI parameters
        thresh_p3_branch = 28;   // Will be learned
        thresh_p7_branch = 12;   // Will be learned
        thresh_p7_ratio = 30;    // Will be learned
        thresh_p5_stall = 15;    // Will be learned
        
        w_p3_score = 16'sd50;
        w_p5_score = 16'sd40;
        w_p7_score = 16'sd60;
        
        $display("");
        $display("================================================================");
        $display("    MORPHABLE CPU - HYBRID AI PREDICTOR");
        $display("================================================================");
        $display("");
        $display("ARCHITECTURE: Decision Tree + Perceptron Hybrid");
        $display("  - Decision tree handles non-linear boundaries");
        $display("  - Perceptron weights fine-tune within each region");
        $display("  - Thresholds are learned from training data");
        $display("");
        $display("CLOCK CONSTRAINTS:");
        $display("  P3: Max 1.1x | P5: Max 1.3x | P7: Max 1.5x");
        $display("");
        $display("================================================================");
        $display("           PHASE 1: COLLECT TRAINING DATA");
        $display("================================================================");
        
        // ====================================================================
        // PHASE 1: Collect data
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
            feat_branch[bench] = 0;
            feat_cpi_ratio[bench] = 100;
            feat_stall[bench] = 0;
            
            for (mode_idx = 0; mode_idx < 3; mode_idx = mode_idx + 1) begin
                case (mode_idx)
                    0: begin mode_select = 2'b00; max_clk = p3_max_clk; end
                    1: begin mode_select = 2'b01; max_clk = p5_max_clk; end
                    2: begin mode_select = 2'b10; max_clk = p7_max_clk; end
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
                
                cyc = 0; timeout = 0; insts = 0;
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
                        insts = inst_count;
                        i = 99999; 
                    end
                end
                
                if (cyc == 0) begin cyc = 15000; insts = 1; timeout = 1; end
                
                results_cycles[bench][mode_idx] = cyc;
                
                // Extract features from P5 run
                if (mode_idx == 1 && !timeout && insts > 0) begin
                    feat_branch[bench] = (flush_count * 100) / insts;
                    feat_stall[bench] = (stall_count * 100) / cyc;
                end
                
                // CPI ratio from P7 vs P3
                if (mode_idx == 2 && !timeout && insts > 0) begin
                    if (results_cycles[bench][0] < 15000 && results_cycles[bench][0] > 0) begin
                        feat_cpi_ratio[bench] = ((cyc * 100 / insts) * 100) / (results_cycles[bench][0] * 100 / insts) - 100;
                    end
                end
                
                // Effective time
                if (timeout) eff = 32'hFFFF;
                else eff = (cyc * 100) / max_clk;
                results_eff[bench][mode_idx] = eff;
                
                if (eff < best_eff_time[bench]) begin
                    best_eff_time[bench] = eff;
                    best_mode[bench] = mode_idx[1:0];
                    best_clk[bench] = max_clk;
                end
                
                case (mode_idx)
                    0: $write("  P3: ");
                    1: $write("  P5: ");
                    2: $write("  P7: ");
                endcase
                
                if (timeout) $display("TIMEOUT");
                else $display("%0d cyc, Eff=%0d.%02d", cyc, eff/100, eff%100);
            end
            
            if (best_eff_time[bench] < 32'hFFFF) begin
                $write("  >>> BEST: P");
                case (best_mode[bench])
                    2'b00: $write("3");
                    2'b01: $write("5");
                    2'b10: $write("7");
                endcase
                $display(" | branch%%=%0d, cpi_ratio%%=%0d, stall%%=%0d",
                         feat_branch[bench], feat_cpi_ratio[bench], feat_stall[bench]);
            end
        end
        
        // ====================================================================
        // PHASE 2: TRAIN HYBRID AI (Gradient-free optimization)
        // ====================================================================
        $display("");
        $display("================================================================");
        $display("           PHASE 2: TRAIN HYBRID AI");
        $display("================================================================");
        $display("");
        $display("Training thresholds and weights...");
        $display("");
        
        prev_errors = 100;
        
        for (epoch = 0; epoch < 10; epoch = epoch + 1) begin
            errors = 0;
            
            for (bench = 0; bench < 10; bench = bench + 1) begin
                if (best_eff_time[bench] < 32'hFFFF) begin
                    // Get prediction
                    predict_mode(feat_branch[bench], feat_cpi_ratio[bench], feat_stall[bench], 
                                 pred_mode, confidence);
                    
                    // Check if wrong
                    if (pred_mode != best_mode[bench]) begin
                        errors = errors + 1;
                        
                        // Adjust thresholds and weights based on error type
                        case (best_mode[bench])
                            2'b00: begin  // Should have been P3
                                // Lower P3 threshold to catch this
                                if (feat_branch[bench] < thresh_p3_branch)
                                    thresh_p3_branch = thresh_p3_branch - 2;
                                w_p3_score = w_p3_score + 5;
                                w_p5_score = w_p5_score - 2;
                            end
                            2'b01: begin  // Should have been P5
                                w_p5_score = w_p5_score + 5;
                                if (pred_mode == 2'b00) w_p3_score = w_p3_score - 3;
                                if (pred_mode == 2'b10) w_p7_score = w_p7_score - 3;
                                // Adjust stall threshold if applicable
                                if (feat_stall[bench] > 5 && feat_stall[bench] < thresh_p5_stall)
                                    thresh_p5_stall = thresh_p5_stall - 2;
                            end
                            2'b10: begin  // Should have been P7
                                // Raise P7 thresholds to catch this
                                if (feat_branch[bench] > thresh_p7_branch)
                                    thresh_p7_branch = thresh_p7_branch + 2;
                                if (feat_cpi_ratio[bench] > thresh_p7_ratio)
                                    thresh_p7_ratio = thresh_p7_ratio + 3;
                                w_p7_score = w_p7_score + 5;
                                w_p5_score = w_p5_score - 2;
                            end
                        endcase
                    end
                end
            end
            
            $display("  Epoch %0d: %0d errors | Thresholds: P3_br>%0d, P7_br<%0d, P7_ratio<%0d, P5_stall>%0d",
                     epoch + 1, errors, thresh_p3_branch, thresh_p7_branch, thresh_p7_ratio, thresh_p5_stall);
            
            // Early stopping if perfect
            if (errors == 0) begin
                $display("  >>> Converged! Perfect accuracy.");
                epoch = 100;  // Exit loop
            end
            
            // Stop if no improvement
            if (errors >= prev_errors && epoch > 3) begin
                $display("  >>> No improvement, stopping.");
                epoch = 100;
            end
            prev_errors = errors;
        end
        
        $display("");
        $display("Final Learned Parameters:");
        $display("  Thresholds: P3_branch>%0d, P7_branch<%0d, P7_ratio<%0d, P5_stall>%0d",
                 thresh_p3_branch, thresh_p7_branch, thresh_p7_ratio, thresh_p5_stall);
        $display("  Weights: P3=%0d, P5=%0d, P7=%0d", w_p3_score, w_p5_score, w_p7_score);
        
        // ====================================================================
        // PHASE 3: FINAL TEST
        // ====================================================================
        $display("");
        $display("================================================================");
        $display("           PHASE 3: FINAL PREDICTIONS");
        $display("================================================================");
        $display("");
        $display("Benchmark       | Br%% | Ratio | Stall | Actual | Pred | Conf | OK?");
        $display("----------------|-----|-------|-------|--------|------|------|----");
        
        begin : final_test
            integer correct, total;
            correct = 0; total = 0;
            
            for (bench = 0; bench < 10; bench = bench + 1) begin
                if (best_eff_time[bench] < 32'hFFFF) begin
                    total = total + 1;
                    
                    predict_mode(feat_branch[bench], feat_cpi_ratio[bench], feat_stall[bench],
                                 pred_mode, confidence);
                    
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
                    
                    $write("| %3d | %5d | %5d ", feat_branch[bench], feat_cpi_ratio[bench], feat_stall[bench]);
                    
                    $write("| P");
                    case (best_mode[bench])
                        2'b00: $write("3    ");
                        2'b01: $write("5    ");
                        2'b10: $write("7    ");
                    endcase
                    
                    $write(" | P");
                    case (pred_mode)
                        2'b00: $write("3  ");
                        2'b01: $write("5  ");
                        2'b10: $write("7  ");
                    endcase
                    
                    $write(" | %4d ", confidence);
                    
                    if (pred_mode == best_mode[bench]) begin
                        $display("| YES");
                        correct = correct + 1;
                    end else begin
                        $display("| no");
                    end
                end
            end
            
            $display("");
            $display("============================================================");
            $display("PREDICTION ACCURACY: %0d/%0d (%0d%%)", correct, total, (correct*100)/total);
            $display("============================================================");
        end
        
        // ====================================================================
        // FINAL SUMMARY
        // ====================================================================
        $display("");
        $display("================================================================");
        $display("                    FINAL SUMMARY");
        $display("================================================================");
        $display("");
        $display("OPTIMAL CONFIGURATIONS:");
        $display("Benchmark       | Mode | Clock | Cycles | Eff.Time | Speedup");
        $display("----------------|------|-------|--------|----------|--------");
        
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
                $display("| T/O  | -     | -      | -        | -");
            end else begin
                $write("| P");
                case (best_mode[bench])
                    2'b00: $write("3  ");
                    2'b01: $write("5  ");
                    2'b10: $write("7  ");
                endcase
                
                $write("| %0d.%0dx  ", best_clk[bench]/100, (best_clk[bench]/10)%10);
                $write("| %5d  ", results_cycles[bench][best_mode[bench]]);
                $write("| %5d.%02d ", best_eff_time[bench]/100, best_eff_time[bench]%100);
                
                if (results_cycles[bench][0] > 0 && results_cycles[bench][0] < 15000) begin
                    $display("| %0d.%02dx", 
                             (results_cycles[bench][0] * 100) / best_eff_time[bench] / 100,
                             ((results_cycles[bench][0] * 100) / best_eff_time[bench]) % 100);
                end else begin
                    $display("| N/A");
                end
            end
        end
        
        $display("");
        $display("WIN COUNT: ");
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
            $display("  P3: %0d wins | P5: %0d wins | P7: %0d wins", p3w, p5w, p7w);
        end
        
        $display("");
        $display("================================================================");
        $display("HYBRID AI LEARNED RULES:");
        $display("  1. IF branch%% > %0d AND ratio > 40 -> P3", thresh_p3_branch);
        $display("  2. IF branch%% < %0d AND ratio < %0d -> P7", thresh_p7_branch, thresh_p7_ratio);
        $display("  3. IF stall%% > %0d -> P5", thresh_p5_stall);
        $display("  4. ELSE -> Use perceptron scores (P3=%0d, P5=%0d, P7=%0d)", 
                 w_p3_score, w_p5_score, w_p7_score);
        $display("================================================================");
        
        $finish;
    end
endmodule
