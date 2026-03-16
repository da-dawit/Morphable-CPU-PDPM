// Testbench for Perceptron Mode Predictor
// Tests the learning behavior and prediction accuracy

`timescale 1ns/1ps

module tb_perceptron;

    reg clk;
    reg reset;
    reg enable;
    
    // Event inputs
    reg branch_taken;
    reg branch_not_taken;
    reg load_inst;
    reg store_inst;
    reg alu_inst;
    reg hazard_stall;
    reg cache_miss;
    
    // Training
    reg window_complete;
    reg [1:0] actual_best_mode;
    reg train_enable;
    reg [1:0] current_mode;
    
    // Outputs
    wire [1:0] predicted_mode;
    wire [7:0] confidence;
    wire prediction_valid;
    
    // Instantiate predictor
    perceptron_predictor #(
        .HISTORY_LEN(16),
        .WEIGHT_BITS(8),
        .WINDOW_SIZE(32)
    ) uut (
        .clk(clk),
        .reset(reset),
        .enable(enable),
        .branch_taken(branch_taken),
        .branch_not_taken(branch_not_taken),
        .load_inst(load_inst),
        .store_inst(store_inst),
        .alu_inst(alu_inst),
        .hazard_stall(hazard_stall),
        .cache_miss(cache_miss),
        .window_complete(window_complete),
        .actual_best_mode(actual_best_mode),
        .train_enable(train_enable),
        .current_mode(current_mode),
        .predicted_mode(predicted_mode),
        .confidence(confidence),
        .prediction_valid(prediction_valid)
    );
    
    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;
    
    // Test sequences
    integer i;
    integer correct_predictions;
    integer total_predictions;
    
    initial begin
        $dumpfile("tb_perceptron.vcd");
        $dumpvars(0, tb_perceptron);
        
        // Initialize
        reset = 1;
        enable = 0;
        branch_taken = 0;
        branch_not_taken = 0;
        load_inst = 0;
        store_inst = 0;
        alu_inst = 0;
        hazard_stall = 0;
        cache_miss = 0;
        window_complete = 0;
        actual_best_mode = 2'b01;
        train_enable = 1;
        current_mode = 2'b01;
        
        correct_predictions = 0;
        total_predictions = 0;
        
        #100;
        reset = 0;
        enable = 1;
        
        $display("");
        $display("========================================");
        $display("PERCEPTRON PREDICTOR TEST");
        $display("========================================");
        
        // ================================================================
        // TEST 1: Branch-heavy workload (should predict P3)
        // ================================================================
        $display("");
        $display("TEST 1: Branch-heavy workload");
        $display("Expected: P3 mode (00)");
        
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk);
            // Simulate branch-heavy execution
            branch_taken <= (i % 3 == 0);
            branch_not_taken <= (i % 3 != 0) && (i % 2 == 0);
            alu_inst <= (i % 4 == 0);
            load_inst <= 0;
            hazard_stall <= 0;
            
            if (i % 20 == 19) begin
                window_complete <= 1;
                actual_best_mode <= 2'b00;  // P3 is best for branches
                @(posedge clk);
                window_complete <= 0;
                
                total_predictions = total_predictions + 1;
                if (predicted_mode == 2'b00)
                    correct_predictions = correct_predictions + 1;
                    
                $display("  Window %0d: pred=%0d actual=%0d conf=%0d", 
                         i/20, predicted_mode, actual_best_mode, confidence);
            end
        end
        
        // ================================================================
        // TEST 2: Memory-heavy workload (should predict P5)
        // ================================================================
        $display("");
        $display("TEST 2: Memory-heavy workload");
        $display("Expected: P5 mode (01)");
        
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk);
            // Simulate memory-heavy execution
            branch_taken <= 0;
            branch_not_taken <= 0;
            load_inst <= (i % 2 == 0);
            store_inst <= (i % 3 == 0);
            alu_inst <= (i % 4 == 0);
            hazard_stall <= (i % 3 == 0);  // Load-use hazards
            
            if (i % 20 == 19) begin
                window_complete <= 1;
                actual_best_mode <= 2'b01;  // P5 is best for memory
                @(posedge clk);
                window_complete <= 0;
                
                total_predictions = total_predictions + 1;
                if (predicted_mode == 2'b01)
                    correct_predictions = correct_predictions + 1;
                    
                $display("  Window %0d: pred=%0d actual=%0d conf=%0d", 
                         i/20, predicted_mode, actual_best_mode, confidence);
            end
        end
        
        // ================================================================
        // TEST 3: Compute-heavy with hazards (should predict P7)
        // ================================================================
        $display("");
        $display("TEST 3: Compute-heavy with hazards");
        $display("Expected: P7 mode (10)");
        
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk);
            // Simulate compute-heavy with hazards
            branch_taken <= 0;
            branch_not_taken <= 0;
            load_inst <= 0;
            store_inst <= 0;
            alu_inst <= 1;  // All ALU
            hazard_stall <= (i % 2 == 0);  // Lots of RAW hazards
            
            if (i % 20 == 19) begin
                window_complete <= 1;
                actual_best_mode <= 2'b10;  // P7 can hide hazards
                @(posedge clk);
                window_complete <= 0;
                
                total_predictions = total_predictions + 1;
                if (predicted_mode == 2'b10)
                    correct_predictions = correct_predictions + 1;
                    
                $display("  Window %0d: pred=%0d actual=%0d conf=%0d", 
                         i/20, predicted_mode, actual_best_mode, confidence);
            end
        end
        
        // ================================================================
        // TEST 4: Mixed workload (test adaptability)
        // ================================================================
        $display("");
        $display("TEST 4: Mixed workload (alternating patterns)");
        
        for (i = 0; i < 60; i = i + 1) begin
            @(posedge clk);
            
            // Alternate between different workload types
            case ((i / 20) % 3)
                0: begin  // Branch phase
                    branch_taken <= (i % 2 == 0);
                    load_inst <= 0;
                    hazard_stall <= 0;
                end
                1: begin  // Memory phase
                    branch_taken <= 0;
                    load_inst <= (i % 2 == 0);
                    hazard_stall <= (i % 3 == 0);
                end
                2: begin  // Compute phase
                    branch_taken <= 0;
                    load_inst <= 0;
                    hazard_stall <= (i % 2 == 0);
                end
            endcase
            alu_inst <= 1;
            
            if (i % 20 == 19) begin
                window_complete <= 1;
                case ((i / 20) % 3)
                    0: actual_best_mode <= 2'b00;
                    1: actual_best_mode <= 2'b01;
                    2: actual_best_mode <= 2'b10;
                endcase
                @(posedge clk);
                window_complete <= 0;
                
                total_predictions = total_predictions + 1;
                if (predicted_mode == actual_best_mode)
                    correct_predictions = correct_predictions + 1;
                    
                $display("  Window %0d: pred=%0d actual=%0d conf=%0d", 
                         i/20, predicted_mode, actual_best_mode, confidence);
            end
        end
        
        // ================================================================
        // RESULTS
        // ================================================================
        $display("");
        $display("========================================");
        $display("RESULTS");
        $display("========================================");
        $display("Total predictions: %0d", total_predictions);
        $display("Correct predictions: %0d", correct_predictions);
        $display("Accuracy: %0d%%", (correct_predictions * 100) / total_predictions);
        $display("");
        
        if (correct_predictions * 100 / total_predictions >= 60)
            $display("*** TEST PASSED (>60%% accuracy) ***");
        else
            $display("*** TEST NEEDS TUNING (<60%% accuracy) ***");
        
        $display("========================================");
        
        #100;
        $finish;
    end

endmodule