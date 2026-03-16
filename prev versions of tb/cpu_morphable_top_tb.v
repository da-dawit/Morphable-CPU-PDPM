//But I do find that for p7, since this is running in the same clock frequency, P7 will be slow no matter what.
`timescale 1ns/1ps

// Testbench for Morphable CPU with P3/P5/P7 modes
// Tests all three pipeline configurations and perceptron prediction

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

    // Instantiate DUT - use v2 with P7 support
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
    // SELECT BENCHMARK HERE (change this number)
    // ============================================
    // 0 = bench_branch (x3 should be 40)
    // 1 = bench_loaduse (x10 reaches 10)
    // 2 = bench_alu (x10 reaches 15)
    // 3 = bench_mixed (x31 should be 99)
    // 4 = bench_compute (x10 reaches 20)
    // 5 = bench_stream (x10 reaches 30) - memory streaming
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
    integer i;

    initial begin
        // Initialize
        p3_cycles = 0; p3_insts = 0;
        p5_cycles = 0; p5_insts = 0;
        p7_cycles = 0; p7_insts = 0;
        
        $display("");
        $display("========================================");
        $display("MORPHABLE CPU BENCHMARK (P3/P5/P7)");
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
        // P3 MODE (3-stage)
        // ================================================================
        mode_select = 2'b00;  // P3
        mode_switch_req = 0;
        auto_mode_enable = 0;
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

        $display("  Cycles : %0d", p3_cycles);
        $display("  Insts  : %0d", p3_insts);
        if (p3_insts > 0)
            $display("  CPI    : %0d.%02d", p3_cycles/p3_insts, ((p3_cycles*100)/p3_insts)%100);
        $display("  x1=%0d x2=%0d x3=%0d x10=%0d x31=%0d", 
                 dut.rf_inst.regs[1], dut.rf_inst.regs[2], 
                 dut.rf_inst.regs[3], dut.rf_inst.regs[10],
                 dut.rf_inst.regs[31]);

        // ================================================================
        // P5 MODE (5-stage)
        // ================================================================
        $display("");
        $display("Running P5 mode (5-stage)...");
        
        mode_select = 2'b01;  // P5
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

        $display("  Cycles : %0d", p5_cycles);
        $display("  Insts  : %0d", p5_insts);
        if (p5_insts > 0)
            $display("  CPI    : %0d.%02d", p5_cycles/p5_insts, ((p5_cycles*100)/p5_insts)%100);
        $display("  x1=%0d x2=%0d x3=%0d x10=%0d x31=%0d", 
                 dut.rf_inst.regs[1], dut.rf_inst.regs[2], 
                 dut.rf_inst.regs[3], dut.rf_inst.regs[10],
                 dut.rf_inst.regs[31]);

        // ================================================================
        // P7 MODE (7-stage)
        // ================================================================
        $display("");
        $display("Running P7 mode (7-stage)...");

        mode_select = 2'b10;  // P7
        reset = 1;
        
        for (i = 0; i < 32; i = i + 1)
            dut.rf_inst.regs[i] = 0;
        for (i = 0; i < 256; i = i + 1)
            dut.dmem_inst.mem[i] = 0;

        // Clear and reload IMEM for P7 test
        for (i = 0; i < 256; i = i + 1)
            dut.imem_inst.mem[i] = 32'h00000013;  // Fill with NOPs first
            
        case (BENCH)
            0: $readmemh("benches/bench_branch.hex", dut.imem_inst.mem);
            1: $readmemh("benches/bench_loaduse.hex", dut.imem_inst.mem);
            2: $readmemh("benches/bench_alu.hex", dut.imem_inst.mem);
            3: $readmemh("benches/bench_mixed.hex", dut.imem_inst.mem);
            4: $readmemh("benches/bench_compute.hex", dut.imem_inst.mem);
            5: $readmemh("benches/bench_stream.hex", dut.imem_inst.mem);
        endcase

        $display("IMEM[0]=%h IMEM[1]=%h IMEM[2]=%h IMEM[3]=%h", 
                 dut.imem_inst.mem[0], dut.imem_inst.mem[1], 
                 dut.imem_inst.mem[2], dut.imem_inst.mem[3]);
        
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

        $display("  Cycles : %0d", p7_cycles);
        $display("  Insts  : %0d", p7_insts);
        if (p7_insts > 0)
            $display("  CPI    : %0d.%02d", p7_cycles/p7_insts, ((p7_cycles*100)/p7_insts)%100);
        $display("  x1=%0d x2=%0d x3=%0d x10=%0d x31=%0d", 
                 dut.rf_inst.regs[1], dut.rf_inst.regs[2], 
                 dut.rf_inst.regs[3], dut.rf_inst.regs[10],
                 dut.rf_inst.regs[31]);

        $display("  x1=%0d x2=%0d x3=%0d x10=%0d x20=%0d x31=%0d", 
                 dut.rf_inst.regs[1], dut.rf_inst.regs[2], 
                 dut.rf_inst.regs[3], dut.rf_inst.regs[10],
                 dut.rf_inst.regs[20], dut.rf_inst.regs[31]);

        // ================================================================
        // RESULTS SUMMARY
        // ================================================================
        $display("");
        $display("========================================");
        $display("RESULTS SUMMARY");
        $display("========================================");
        
        $display("");
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
        
        // Find winner
        begin : find_winner
            reg [31:0] min_cycles;
            reg [7:0] winner_name;
            
            min_cycles = 32'hFFFFFFFF;
            winner_name = "?";
            
            if (p3_insts > 0 && p3_cycles < min_cycles) begin
                min_cycles = p3_cycles;
                winner_name = "3";
            end
            if (p5_insts > 0 && p5_cycles < min_cycles) begin
                min_cycles = p5_cycles;
                winner_name = "5";
            end
            if (p7_insts > 0 && p7_cycles < min_cycles) begin
                min_cycles = p7_cycles;
                winner_name = "7";
            end
            
            $display(">>> WINNER: P%0s with %0d cycles", winner_name, min_cycles);
        end
        
        $display("========================================");
        $finish;
    end

endmodule