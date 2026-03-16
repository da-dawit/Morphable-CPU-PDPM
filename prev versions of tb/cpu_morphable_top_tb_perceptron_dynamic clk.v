`timescale 1ns/1ps

// Enhanced Testbench for Morphable CPU with P3/P5/P7 modes
// Features:
// - Clock frequency scaling simulation (P7 runs at higher effective frequency)
// - Perceptron predictor learning and evaluation
// - Comprehensive benchmark suite

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

    // Instantiate DUT
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

    // ============================================
    // CLOCK FREQUENCY SCALING FACTORS
    // ============================================
    // Deeper pipelines can run at higher frequencies
    // These are realistic ratios based on pipeline depth
    // P3: 100 MHz (baseline)
    // P5: 130 MHz (1.3x faster clock)
    // P7: 160 MHz (1.6x faster clock)
    
    // To calculate effective time: cycles / frequency_factor
    // Lower effective time = better performance
    
    real P3_FREQ_FACTOR;
    real P5_FREQ_FACTOR;
    real P7_FREQ_FACTOR;
    
    initial begin
        P3_FREQ_FACTOR = 1.0;   // Baseline
        P5_FREQ_FACTOR = 1.3;   // 30% faster clock
        P7_FREQ_FACTOR = 1.6;   // 60% faster clock
    end
    
    // ============================================
    // SELECT BENCHMARK HERE (change this number)
    // ============================================
    // 0 = bench_branch (branch-heavy)
    // 1 = bench_loaduse (load-use patterns)
    // 2 = bench_alu (ALU-intensive)
    // 3 = bench_mixed (bubble sort)
    // 4 = bench_compute (independent ops)
    // 5 = bench_stream (memory streaming)
    localparam BENCH = 5; //CHANGE THIS !!!
    // ============================================

    initial begin
        #1;
        case (BENCH)
            0: $readmemh("benches/bench_branch.hex", dut.imem_inst.mem);
            1: $readmemh("benches/bench_loaduse.hex", dut.imem_inst.mem);
            2: $readmemh("benches/bench_alu.hex", dut.imem_inst.mem);
            3: $readmemh("benches/bench_mixed.hex", dut.imem_inst.mem);
            4: $readmemh("benches/bench_compute.hex", dut.imem_inst.mem);
            5: $readmemh("benches/bench_stream.hex", dut.imem_inst.mem);
        endcase
    end

    // Halt detection based on expected result
    wire halted_branch  = (dut.rf_inst.regs[3] == 32'd40);
    wire halted_loaduse = (dut.rf_inst.regs[10] == 32'd10);
    wire halted_alu     = (dut.rf_inst.regs[1] == 32'd16) && (dut.rf_inst.regs[10] == 32'd15);
    wire halted_mixed   = (dut.rf_inst.regs[31] == 32'd99);
    wire halted_compute = (dut.rf_inst.regs[10] == 32'd20);
    wire halted_stream  = (dut.rf_inst.regs[10] == 32'd30);
    
    wire halted = (BENCH == 0) ? halted_branch :
                  (BENCH == 1) ? halted_loaduse :
                  (BENCH == 2) ? halted_alu :
                  (BENCH == 3) ? halted_mixed :
                  (BENCH == 4) ? halted_compute :
                  halted_stream;

    initial begin
        $dumpfile("cpu_morphable_top_tb.vcd");
        $dumpvars(0, cpu_morphable_top_tb);
    end

    reg [31:0] p3_cycles, p3_insts;
    reg [31:0] p5_cycles, p5_insts;
    reg [31:0] p7_cycles, p7_insts;
    
    // Effective time (cycles adjusted for frequency) - stored as fixed point * 100
    reg [31:0] p3_eff_time_x100, p5_eff_time_x100, p7_eff_time_x100;
    
    integer i;
    
    initial begin
        // Initialize
        p3_cycles = 0; p3_insts = 0;
        p5_cycles = 0; p5_insts = 0;
        p7_cycles = 0; p7_insts = 0;
        
        $display("");
        $display("========================================");
        $display("MORPHABLE CPU BENCHMARK (P3/P5/P7)");
        $display("With Clock Frequency Scaling");
        $display("========================================");
        $display("Frequency Factors:");
        $display("  P3: 1.0x (100 MHz baseline)");
        $display("  P5: 1.3x (130 MHz)");
        $display("  P7: 1.6x (160 MHz)");
        $display("========================================");
        
        case (BENCH)
            0: $display("Test: BRANCH-HEAVY");
            1: $display("Test: LOAD-USE");
            2: $display("Test: ALU-INTENSIVE");
            3: $display("Test: MIXED (Bubble Sort)");
            4: $display("Test: COMPUTE-INTENSIVE");
            5: $display("Test: MEMORY-STREAMING");
        endcase
        $display("========================================");

        // ================================================================
        // P3 MODE (3-stage) - Enable perceptron learning
        // ================================================================
        mode_select = 2'b00;  // P3
        mode_switch_req = 0;
        auto_mode_enable = 1;  // Enable perceptron learning!
        reset = 1;
        #100;
        reset = 0;

        $display("");
        $display("Running P3 mode (3-stage)...");
        
        for (i = 0; i < 10000; i = i + 1) begin
            @(posedge clk);
            if (halted) begin
                p3_cycles = cycle_count;
                p3_insts  = inst_count;
                i = 99999;
            end
        end
        
        if (p3_cycles == 0) begin
            p3_cycles = cycle_count;
            p3_insts = inst_count;
            $display("  (TIMEOUT)");
        end
        
        // Effective time = cycles / freq_factor (multiply by 100 for precision)
        p3_eff_time_x100 = (p3_cycles * 100) / 100;  // / 1.0

        $display("  Cycles      : %0d", p3_cycles);
        $display("  Insts       : %0d", p3_insts);
        if (p3_insts > 0)
            $display("  CPI         : %0d.%02d", p3_cycles/p3_insts, ((p3_cycles*100)/p3_insts)%100);
        $display("  Eff. Time   : %0d.%02d", p3_eff_time_x100/100, p3_eff_time_x100%100);
        $display("  Prediction  : P%0d (confidence: %0d%%)", predicted_mode, prediction_confidence*100/255);
        $display("  x1=%0d x10=%0d x31=%0d", dut.rf_inst.regs[1], dut.rf_inst.regs[10], dut.rf_inst.regs[31]);

        // ================================================================
        // P5 MODE (5-stage)
        // ================================================================
        $display("");
        $display("Running P5 mode (5-stage)...");
        
        mode_select = 2'b01;  // P5
        auto_mode_enable = 1;  // Keep learning
        reset = 1;
        
        for (i = 0; i < 32; i = i + 1)
            dut.rf_inst.regs[i] = 0;
        for (i = 0; i < 256; i = i + 1)
            dut.dmem_inst.mem[i] = 0;
        
        #100;
        reset = 0;
        
        for (i = 0; i < 10000; i = i + 1) begin
            @(posedge clk);
            if (halted) begin
                p5_cycles = cycle_count;
                p5_insts  = inst_count;
                i = 99999;
            end
        end
        
        if (p5_cycles == 0) begin
            p5_cycles = cycle_count;
            p5_insts = inst_count;
            $display("  (TIMEOUT)");
        end
        
        // Effective time = cycles / 1.3 = cycles * 100 / 130
        p5_eff_time_x100 = (p5_cycles * 100) / 130;

        $display("  Cycles      : %0d", p5_cycles);
        $display("  Insts       : %0d", p5_insts);
        if (p5_insts > 0)
            $display("  CPI         : %0d.%02d", p5_cycles/p5_insts, ((p5_cycles*100)/p5_insts)%100);
        $display("  Eff. Time   : %0d.%02d", p5_eff_time_x100/100, p5_eff_time_x100%100);
        $display("  Prediction  : P%0d (confidence: %0d%%)", predicted_mode, prediction_confidence*100/255);
        $display("  x1=%0d x10=%0d x31=%0d", dut.rf_inst.regs[1], dut.rf_inst.regs[10], dut.rf_inst.regs[31]);

        // ================================================================
        // P7 MODE (7-stage)
        // ================================================================
        $display("");
        $display("Running P7 mode (7-stage)...");

        mode_select = 2'b10;  // P7
        auto_mode_enable = 1;  // Keep learning
        reset = 1;
        
        for (i = 0; i < 32; i = i + 1)
            dut.rf_inst.regs[i] = 0;
        for (i = 0; i < 256; i = i + 1)
            dut.dmem_inst.mem[i] = 0;

        // Clear and reload IMEM for P7 test
        for (i = 0; i < 256; i = i + 1)
            dut.imem_inst.mem[i] = 32'h00000013;
            
        case (BENCH)
            0: $readmemh("benches/bench_branch.hex", dut.imem_inst.mem);
            1: $readmemh("benches/bench_loaduse.hex", dut.imem_inst.mem);
            2: $readmemh("benches/bench_alu.hex", dut.imem_inst.mem);
            3: $readmemh("benches/bench_mixed.hex", dut.imem_inst.mem);
            4: $readmemh("benches/bench_compute.hex", dut.imem_inst.mem);
            5: $readmemh("benches/bench_stream.hex", dut.imem_inst.mem);
        endcase
        
        #100;
        reset = 0;
        
        for (i = 0; i < 10000; i = i + 1) begin
            @(posedge clk);
            if (halted) begin
                p7_cycles = cycle_count;
                p7_insts  = inst_count;
                i = 99999;
            end
        end
        
        if (p7_cycles == 0) begin
            p7_cycles = cycle_count;
            p7_insts = inst_count;
            $display("  (TIMEOUT)");
        end
        
        // Effective time = cycles / 1.6 = cycles * 100 / 160
        p7_eff_time_x100 = (p7_cycles * 100) / 160;

        $display("  Cycles      : %0d", p7_cycles);
        $display("  Insts       : %0d", p7_insts);
        if (p7_insts > 0)
            $display("  CPI         : %0d.%02d", p7_cycles/p7_insts, ((p7_cycles*100)/p7_insts)%100);
        $display("  Eff. Time   : %0d.%02d", p7_eff_time_x100/100, p7_eff_time_x100%100);
        $display("  Prediction  : P%0d (confidence: %0d%%)", predicted_mode, prediction_confidence*100/255);
        $display("  x1=%0d x10=%0d x31=%0d", dut.rf_inst.regs[1], dut.rf_inst.regs[10], dut.rf_inst.regs[31]);

        // ================================================================
        // RESULTS SUMMARY
        // ================================================================
        $display("");
        $display("========================================");
        $display("RESULTS SUMMARY");
        $display("========================================");
        
        $display("");
        $display("RAW CYCLES (same clock frequency):");
        $display("Mode   | Cycles | Insts | CPI");
        $display("-------|--------|-------|------");
        
        if (p3_insts > 0)
            $display("P3     | %6d | %5d | %0d.%02d", p3_cycles, p3_insts, 
                     p3_cycles/p3_insts, ((p3_cycles*100)/p3_insts)%100);
        else
            $display("P3     | TIMEOUT");
            
        if (p5_insts > 0)
            $display("P5     | %6d | %5d | %0d.%02d", p5_cycles, p5_insts,
                     p5_cycles/p5_insts, ((p5_cycles*100)/p5_insts)%100);
        else
            $display("P5     | TIMEOUT");
            
        if (p7_insts > 0)
            $display("P7     | %6d | %5d | %0d.%02d", p7_cycles, p7_insts,
                     p7_cycles/p7_insts, ((p7_cycles*100)/p7_insts)%100);
        else
            $display("P7     | TIMEOUT");
        
        $display("");
        $display("EFFECTIVE TIME (with frequency scaling):");
        $display("Mode   | Cycles | Freq  | Eff.Time | Speedup");
        $display("-------|--------|-------|----------|--------");
        $display("P3     | %6d | 1.0x  | %4d.%02d  | 1.00x", p3_cycles, 
                 p3_eff_time_x100/100, p3_eff_time_x100%100);
        $display("P5     | %6d | 1.3x  | %4d.%02d  | %0d.%02dx", p5_cycles,
                 p5_eff_time_x100/100, p5_eff_time_x100%100,
                 (p3_eff_time_x100*100/p5_eff_time_x100)/100, (p3_eff_time_x100*100/p5_eff_time_x100)%100);
        $display("P7     | %6d | 1.6x  | %4d.%02d  | %0d.%02dx", p7_cycles,
                 p7_eff_time_x100/100, p7_eff_time_x100%100,
                 (p3_eff_time_x100*100/p7_eff_time_x100)/100, (p3_eff_time_x100*100/p7_eff_time_x100)%100);
        
        $display("");
        
        // Find winner based on raw cycles
        begin : find_raw_winner
            reg [31:0] min_cycles;
            min_cycles = 32'hFFFFFFFF;
            
            if (p3_insts > 0 && p3_cycles < min_cycles) min_cycles = p3_cycles;
            if (p5_insts > 0 && p5_cycles < min_cycles) min_cycles = p5_cycles;
            if (p7_insts > 0 && p7_cycles < min_cycles) min_cycles = p7_cycles;
            
            $write(">>> RAW WINNER (same clock): ");
            if (min_cycles == p3_cycles) $display("P3 with %0d cycles", p3_cycles);
            else if (min_cycles == p5_cycles) $display("P5 with %0d cycles", p5_cycles);
            else $display("P7 with %0d cycles", p7_cycles);
        end
        
        // Find winner based on effective time
        begin : find_eff_winner
            reg [31:0] min_time;
            min_time = 32'hFFFFFFFF;
            
            if (p3_insts > 0 && p3_eff_time_x100 < min_time) min_time = p3_eff_time_x100;
            if (p5_insts > 0 && p5_eff_time_x100 < min_time) min_time = p5_eff_time_x100;
            if (p7_insts > 0 && p7_eff_time_x100 < min_time) min_time = p7_eff_time_x100;
            
            $write(">>> EFFECTIVE WINNER (with freq scaling): ");
            if (min_time == p3_eff_time_x100) $display("P3 with %0d.%02d eff. time", p3_eff_time_x100/100, p3_eff_time_x100%100);
            else if (min_time == p5_eff_time_x100) $display("P5 with %0d.%02d eff. time", p5_eff_time_x100/100, p5_eff_time_x100%100);
            else $display("P7 with %0d.%02d eff. time", p7_eff_time_x100/100, p7_eff_time_x100%100);
        end
        
        $display("");
        $display("========================================");
        $display("PERCEPTRON PREDICTOR STATUS");
        $display("========================================");
        $display("Final Prediction: P%0d", predicted_mode);
        $display("Confidence: %0d%%", prediction_confidence*100/255);
        $display("========================================");
        
        $finish;
    end

endmodule