`timescale 1ns/1ps

// Final Comprehensive Testbench - 10 Benchmarks
// Adjusted frequency scaling: P3=1.0x, P5=1.2x, P7=1.5x

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

    reg [31:0] results_cycles [0:9][0:2];
    reg [31:0] results_eff_time [0:9][0:2];
    
    integer bench, mode_idx, i;
    reg [31:0] cyc, ins, eff;
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
    wire halted_vector   = (dut.rf_inst.regs[10] == 32'd25);
    
    reg halted;
    
    initial begin
        $dumpfile("cpu_morphable_top_tb.vcd");
        $dumpvars(0, cpu_morphable_top_tb);
        
        $display("");
        $display("================================================================");
        $display("   MORPHABLE RISC-V CPU - 10 BENCHMARK SUITE");
        $display("================================================================");
        $display("Frequency: P3=1.0x (100MHz), P5=1.2x (120MHz), P7=1.5x (150MHz)");
        $display("================================================================");
        
        for (bench = 0; bench < 10; bench = bench + 1) begin
            $display("");
            case (bench)
                0: $display("--- BENCH %0d: Branch-Heavy ---", bench);
                1: $display("--- BENCH %0d: Load-Use ---", bench);
                2: $display("--- BENCH %0d: ALU-Intensive ---", bench);
                3: $display("--- BENCH %0d: Mixed (Bubble) ---", bench);
                4: $display("--- BENCH %0d: Compute ---", bench);
                5: $display("--- BENCH %0d: Mem-Stream ---", bench);
                6: $display("--- BENCH %0d: Tight-Loop ---", bench);
                7: $display("--- BENCH %0d: Nested-Loops ---", bench);
                8: $display("--- BENCH %0d: Switch-Case ---", bench);
                9: $display("--- BENCH %0d: Vector-Ops ---", bench);
            endcase
            
            for (mode_idx = 0; mode_idx < 3; mode_idx = mode_idx + 1) begin
                case (mode_idx)
                    0: begin mode_select = 2'b00; $write("P3: "); end
                    1: begin mode_select = 2'b01; $write("P5: "); end
                    2: begin mode_select = 2'b10; $write("P7: "); end
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
                    if (halted) begin cyc = cycle_count; i = 99999; end
                end
                
                if (cyc == 0) begin cyc = cycle_count; timeout = 1; end
                
                case (mode_idx)
                    0: eff = (cyc * 100) / 100;
                    1: eff = (cyc * 100) / 120;
                    2: eff = (cyc * 100) / 150;
                endcase
                
                results_cycles[bench][mode_idx] = cyc;
                results_eff_time[bench][mode_idx] = timeout ? 32'hFFFF : eff;
                
                if (timeout) $display("TIMEOUT");
                else $display("%0d cyc, eff=%0d.%02d", cyc, eff/100, eff%100);
            end
        end
        
        // Summary
        $display("");
        $display("================================================================");
        $display("                         SUMMARY");
        $display("================================================================");
        $display("EFFECTIVE TIME (lower=better):");
        $display("Benchmark       |   P3   |   P5   |   P7   | Winner");
        $display("----------------|--------|--------|--------|--------");
        
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
            
            if (results_eff_time[bench][0] >= 32'hFFFF) $write("| T/O    ");
            else $write("| %3d.%02d ", results_eff_time[bench][0]/100, results_eff_time[bench][0]%100);
            
            if (results_eff_time[bench][1] >= 32'hFFFF) $write("| T/O    ");
            else $write("| %3d.%02d ", results_eff_time[bench][1]/100, results_eff_time[bench][1]%100);
            
            if (results_eff_time[bench][2] >= 32'hFFFF) $write("| T/O    ");
            else $write("| %3d.%02d ", results_eff_time[bench][2]/100, results_eff_time[bench][2]%100);
            
            begin : winner
                reg [31:0] m;
                m = 32'hFFFFFFFF;
                if (results_eff_time[bench][0] < m) m = results_eff_time[bench][0];
                if (results_eff_time[bench][1] < m) m = results_eff_time[bench][1];
                if (results_eff_time[bench][2] < m) m = results_eff_time[bench][2];
                
                if (m >= 32'hFFFF) $display("| -");
                else if (results_eff_time[bench][0] == m) $display("| P3");
                else if (results_eff_time[bench][1] == m) $display("| P5");
                else $display("| P7");
            end
        end
        
        $display("");
        $display("WIN COUNT:");
        begin : wins
            integer p3, p5, p7;
            reg [31:0] m;
            p3 = 0; p5 = 0; p7 = 0;
            for (bench = 0; bench < 10; bench = bench + 1) begin
                m = 32'hFFFFFFFF;
                if (results_eff_time[bench][0] < m) m = results_eff_time[bench][0];
                if (results_eff_time[bench][1] < m) m = results_eff_time[bench][1];
                if (results_eff_time[bench][2] < m) m = results_eff_time[bench][2];
                if (m < 32'hFFFF) begin
                    if (results_eff_time[bench][0] == m) p3 = p3 + 1;
                    else if (results_eff_time[bench][1] == m) p5 = p5 + 1;
                    else p7 = p7 + 1;
                end
            end
            $display("  P3: %0d wins | P5: %0d wins | P7: %0d wins", p3, p5, p7);
        end
        
        $display("");
        $display("PERCEPTRON: Predicts P%0d (confidence: %0d%%)", 
                 predicted_mode, prediction_confidence*100/255);
        $display("================================================================");
        
        $finish;
    end
endmodule