// // Perceptron-Based Pipeline Mode Predictor!! LETS GOOOO
// // 
// // so my new idea is: Uses perceptron learning to predict optimal pipeline mode
// // based on runtime workload characteristics. Unlike static heuristics,
// // this learns correlations between execution patterns and optimal modes.
// //
// // 1. Three perceptrons (one per mode: P3, P5, P7)
// // 2. Multi-feature history: branches, memory access, hazards
// // 3. Online learning with incremental weight updates
// // 4. Confidence output for gated switching
// //
// // Training Signal: CPI measured over instruction windows
// // - Lower CPI → better mode for current workload
// // - Perceptron learns which history patterns correlate with each mode being optimal
// //
// // - Perceptron output: y = w0 + Σ(wi * xi) where xi ∈ {-1, +1}
// // - Weight update: wi += α * (target - output) * xi
// // - Mode selection: argmax(y_p3, y_p5, y_p7)
// // - Confidence: max_y - second_max_y

// module perceptron_predictor #(
//     parameter HISTORY_LEN = 16,      // History register length
//     parameter WEIGHT_BITS = 8,       // Bits per weight (signed)
//     parameter WINDOW_SIZE = 32,      // Instructions per evaluation window
//     parameter LEARNING_RATE = 1      // Weight update magnitude
// )(
//     input  wire        clk,
//     input  wire        reset,
//     input  wire        enable,           // Enable predictor
    
//     // Runtime event inputs (updated each cycle)
//     input  wire        branch_taken,     // Branch was taken
//     input  wire        branch_not_taken, // Branch was not taken
//     input  wire        load_inst,        // Load instruction executed
//     input  wire        store_inst,       // Store instruction executed
//     input  wire        alu_inst,         // ALU instruction executed
//     input  wire        hazard_stall,     // Pipeline stalled due to hazard
//     input  wire        cache_miss,       // Cache miss (if applicable)
    
//     // Performance feedback for training
//     input  wire        window_complete,  // Instruction window finished
//     input  wire [1:0]  actual_best_mode, // Which mode had best CPI (training label)
//     input  wire        train_enable,     // Enable weight updates
    
//     // Current mode for context
//     input  wire [1:0]  current_mode,
    
//     // Prediction outputs
//     output reg  [1:0]  predicted_mode,   // 00=P3, 01=P5, 10=P7
//     output reg  [7:0]  confidence,       // Prediction confidence (0-255)
//     output wire        prediction_valid  // Prediction is ready
// );

    
//     // HISTORY REGISTER
    
//     // Encodes recent execution events as a bit vector
//     // Each bit represents an event type in a recent cycle
    
//     // History shift register (circular buffer of events)
//     reg [HISTORY_LEN-1:0] branch_history;      // Branch outcomes
//     reg [HISTORY_LEN-1:0] memory_history;      // Memory access patterns
//     reg [HISTORY_LEN-1:0] hazard_history;      // Hazard occurrences
//     reg [HISTORY_LEN-1:0] inst_type_history;   // Instruction type (0=ALU, 1=MEM)
    
//     // Combined feature vector (4 * HISTORY_LEN bits)
//     wire [4*HISTORY_LEN-1:0] feature_vector;
//     assign feature_vector = {branch_history, memory_history, hazard_history, inst_type_history};
    
//     // Update history on each valid cycle
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             branch_history    <= {HISTORY_LEN{1'b0}};
//             memory_history    <= {HISTORY_LEN{1'b0}};
//             hazard_history    <= {HISTORY_LEN{1'b0}};
//             inst_type_history <= {HISTORY_LEN{1'b0}};
//         end else if (enable) begin
//             // Shift in new events
//             branch_history    <= {branch_history[HISTORY_LEN-2:0], branch_taken};
//             memory_history    <= {memory_history[HISTORY_LEN-2:0], load_inst | store_inst};
//             hazard_history    <= {hazard_history[HISTORY_LEN-2:0], hazard_stall};
//             inst_type_history <= {inst_type_history[HISTORY_LEN-2:0], load_inst | store_inst};
//         end
//     end
    
    
//     // PERCEPTRON WEIGHTS
    
//     // Three perceptrons, one for each mode
//     // Each has weights for: bias + branch_history + memory_history + hazard_history + inst_type
    
//     localparam NUM_FEATURES = 4 * HISTORY_LEN;
//     localparam NUM_WEIGHTS = NUM_FEATURES + 1;  // +1 for bias
    
//     // Weight arrays (initialized to small random-ish values)
//     reg signed [WEIGHT_BITS-1:0] weights_p3 [0:NUM_WEIGHTS-1];
//     reg signed [WEIGHT_BITS-1:0] weights_p5 [0:NUM_WEIGHTS-1];
//     reg signed [WEIGHT_BITS-1:0] weights_p7 [0:NUM_WEIGHTS-1];
    
//     // Initialize weights
//     integer i;
//     initial begin
//         for (i = 0; i < NUM_WEIGHTS; i = i + 1) begin
//             // Slight bias towards each mode's "natural" use case
//             weights_p3[i] = (i < HISTORY_LEN) ? 8'sd2 : 8'sd0;      // Branch-sensitive
//             weights_p5[i] = 8'sd1;                                    // Neutral
//             weights_p7[i] = (i >= 2*HISTORY_LEN) ? 8'sd2 : 8'sd0;   // Hazard-sensitive
//         end
//     end
    
    
//     // PERCEPTRON COMPUTATION
    
//     // Compute dot product of features with weights
    
//     reg signed [15:0] y_p3, y_p5, y_p7;  // Perceptron outputs
    
//     // Compute perceptron outputs (combinational)
//     always @(*) begin
//         // Start with bias weights
//         y_p3 = {{8{weights_p3[0][WEIGHT_BITS-1]}}, weights_p3[0]};
//         y_p5 = {{8{weights_p5[0][WEIGHT_BITS-1]}}, weights_p5[0]};
//         y_p7 = {{8{weights_p7[0][WEIGHT_BITS-1]}}, weights_p7[0]};
//     end
    
//     // Note: Full dot product would be computed here
//     // For FPGA efficiency, we use a simplified version
    
//     // Simplified feature extraction (count-based)
//     wire [4:0] branch_count;
//     wire [4:0] memory_count;
//     wire [4:0] hazard_count;
    
//     // Popcount for each history type
//     assign branch_count = branch_history[0] + branch_history[1] + branch_history[2] + branch_history[3] +
//                           branch_history[4] + branch_history[5] + branch_history[6] + branch_history[7] +
//                           branch_history[8] + branch_history[9] + branch_history[10] + branch_history[11] +
//                           branch_history[12] + branch_history[13] + branch_history[14] + branch_history[15];
    
//     assign memory_count = memory_history[0] + memory_history[1] + memory_history[2] + memory_history[3] +
//                           memory_history[4] + memory_history[5] + memory_history[6] + memory_history[7] +
//                           memory_history[8] + memory_history[9] + memory_history[10] + memory_history[11] +
//                           memory_history[12] + memory_history[13] + memory_history[14] + memory_history[15];
    
//     assign hazard_count = hazard_history[0] + hazard_history[1] + hazard_history[2] + hazard_history[3] +
//                           hazard_history[4] + hazard_history[5] + hazard_history[6] + hazard_history[7] +
//                           hazard_history[8] + hazard_history[9] + hazard_history[10] + hazard_history[11] +
//                           hazard_history[12] + hazard_history[13] + hazard_history[14] + hazard_history[15];
    
    
//     // SCORING LOGIC
    
//     // Compute mode scores based on learned weights and current features
    
//     reg signed [15:0] score_p3, score_p5, score_p7;
    
//     // Learnable weight registers for simplified model
//     reg signed [7:0] w_p3_branch, w_p3_memory, w_p3_hazard, w_p3_bias;
//     reg signed [7:0] w_p5_branch, w_p5_memory, w_p5_hazard, w_p5_bias;
//     reg signed [7:0] w_p7_branch, w_p7_memory, w_p7_hazard, w_p7_bias;
    
//     // Initialize simplified weights
//     initial begin
//         // P3 weights: prefers branch-heavy, dislikes memory/hazards
//         w_p3_branch = 8'sd4;   // Branches favor P3 (lower penalty)
//         w_p3_memory = -8'sd2;  // Memory ops hurt P3 (no forwarding)
//         w_p3_hazard = -8'sd3;  // Hazards hurt P3
//         w_p3_bias   = 8'sd8;   // Base preference
        
//         // P5 weights: balanced
//         w_p5_branch = 8'sd0;
//         w_p5_memory = 8'sd2;   // Memory ops OK in P5
//         w_p5_hazard = 8'sd1;   // Handles hazards
//         w_p5_bias   = 8'sd10;  // Slight preference (safe default)
        
//         // P7 weights: prefers compute-heavy with hazards
//         w_p7_branch = -8'sd3;  // Branches hurt P7 (long flush) -->
//         w_p7_memory = 8'sd1;
//         w_p7_hazard = 8'sd3;   // Can hide hazards better
//         w_p7_bias   = 8'sd5;
//     end
    
//     // Compute scores
//     always @(*) begin
//         score_p3 = w_p3_bias + 
//                    (w_p3_branch * $signed({11'b0, branch_count})) +
//                    (w_p3_memory * $signed({11'b0, memory_count})) +
//                    (w_p3_hazard * $signed({11'b0, hazard_count}));
        
//         score_p5 = w_p5_bias + 
//                    (w_p5_branch * $signed({11'b0, branch_count})) +
//                    (w_p5_memory * $signed({11'b0, memory_count})) +
//                    (w_p5_hazard * $signed({11'b0, hazard_count}));
        
//         score_p7 = w_p7_bias + 
//                    (w_p7_branch * $signed({11'b0, branch_count})) +
//                    (w_p7_memory * $signed({11'b0, memory_count})) +
//                    (w_p7_hazard * $signed({11'b0, hazard_count}));
//     end
    
    
//     // MODE SELECTION & CONFIDENCE
    
    
//     reg signed [15:0] max_score, second_score;
//     reg [1:0] best_mode;
    
//     always @(*) begin
//         // Find maximum score and corresponding mode
//         if (score_p3 >= score_p5 && score_p3 >= score_p7) begin
//             best_mode = 2'b00;  // P3
//             max_score = score_p3;
//             second_score = (score_p5 >= score_p7) ? score_p5 : score_p7;
//         end else if (score_p5 >= score_p7) begin
//             best_mode = 2'b01;  // P5
//             max_score = score_p5;
//             second_score = (score_p3 >= score_p7) ? score_p3 : score_p7;
//         end else begin
//             best_mode = 2'b10;  // P7
//             max_score = score_p7;
//             second_score = (score_p3 >= score_p5) ? score_p3 : score_p5;
//         end
//     end
    
//     // Confidence = margin between top two scores (saturated to 8 bits)
//     wire signed [15:0] margin;
//     assign margin = max_score - second_score;
    
//     wire [7:0] conf_value;
//     assign conf_value = (margin > 16'sd255) ? 8'd255 : 
//                         (margin < 16'sd0) ? 8'd0 : margin[7:0];
    
//     // Register outputs
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             predicted_mode <= 2'b01;  // Default to P5
//             confidence     <= 8'd0;
//         end else if (enable) begin
//             predicted_mode <= best_mode;
//             confidence     <= conf_value;
//         end
//     end
    
//     assign prediction_valid = enable && (confidence > 8'd0);
    
    
//     // ONLINE LEARNING (WEIGHT UPDATES)
    
//     // When training is enabled, update weights based on actual best mode
    
//     always @(posedge clk or posedge reset) begin
//         if (reset) begin
//             // Reset to initial weights
//             w_p3_branch <= 8'sd4;
//             w_p3_memory <= -8'sd2;
//             w_p3_hazard <= -8'sd3;
//             w_p3_bias   <= 8'sd8;
            
//             w_p5_branch <= 8'sd0;
//             w_p5_memory <= 8'sd2;
//             w_p5_hazard <= 8'sd1;
//             w_p5_bias   <= 8'sd10;
            
//             w_p7_branch <= -8'sd3;
//             w_p7_memory <= 8'sd1;
//             w_p7_hazard <= 8'sd3;
//             w_p7_bias   <= 8'sd5;
//         end else if (train_enable && window_complete) begin
//             // Perceptron update rule!:
//             // If prediction was wrong OR margin was too small, update weights
            
//             if (actual_best_mode == 2'b00) begin
//                 // P3 was actually best - reinforce P3, penalize others
//                 if (score_p3 <= score_p5 || score_p3 <= score_p7) begin
//                     // Increase P3 weights toward current features
//                     w_p3_branch <= saturate_add(w_p3_branch, branch_count[3:0]);
//                     w_p3_memory <= saturate_add(w_p3_memory, memory_count[3:0]);
//                     w_p3_hazard <= saturate_add(w_p3_hazard, hazard_count[3:0]);
//                     w_p3_bias   <= saturate_add(w_p3_bias, 4'd1);
                    
//                     // Decrease others
//                     w_p5_bias <= saturate_sub(w_p5_bias, 4'd1);
//                     w_p7_bias <= saturate_sub(w_p7_bias, 4'd1);
//                 end
//             end else if (actual_best_mode == 2'b01) begin
//                 // P5 was actually best
//                 if (score_p5 <= score_p3 || score_p5 <= score_p7) begin
//                     w_p5_branch <= saturate_add(w_p5_branch, branch_count[3:0]);
//                     w_p5_memory <= saturate_add(w_p5_memory, memory_count[3:0]);
//                     w_p5_hazard <= saturate_add(w_p5_hazard, hazard_count[3:0]);
//                     w_p5_bias   <= saturate_add(w_p5_bias, 4'd1);
                    
//                     w_p3_bias <= saturate_sub(w_p3_bias, 4'd1);
//                     w_p7_bias <= saturate_sub(w_p7_bias, 4'd1);
//                 end
//             end else if (actual_best_mode == 2'b10) begin
//                 // P7 was actually best
//                 if (score_p7 <= score_p3 || score_p7 <= score_p5) begin
//                     w_p7_branch <= saturate_add(w_p7_branch, branch_count[3:0]);
//                     w_p7_memory <= saturate_add(w_p7_memory, memory_count[3:0]);
//                     w_p7_hazard <= saturate_add(w_p7_hazard, hazard_count[3:0]);
//                     w_p7_bias   <= saturate_add(w_p7_bias, 4'd1);
                    
//                     w_p3_bias <= saturate_sub(w_p3_bias, 4'd1);
//                     w_p5_bias <= saturate_sub(w_p5_bias, 4'd1);
//                 end
//             end
//         end
//     end
    
//     // Saturating add/subtract functions
//     function signed [7:0] saturate_add;
//         input signed [7:0] a;
//         input [3:0] b;
//         reg signed [8:0] result;
//         begin
//             result = a + $signed({5'b0, b});
//             if (result > 9'sd127)
//                 saturate_add = 8'sd127;
//             else if (result < -9'sd128)
//                 saturate_add = -8'sd128;
//             else
//                 saturate_add = result[7:0];
//         end
//     endfunction
    
//     function signed [7:0] saturate_sub;
//         input signed [7:0] a;
//         input [3:0] b;
//         reg signed [8:0] result;
//         begin
//             result = a - $signed({5'b0, b});
//             if (result > 9'sd127)
//                 saturate_sub = 8'sd127;
//             else if (result < -9'sd128)
//                 saturate_sub = -8'sd128;
//             else
//                 saturate_sub = result[7:0];
//         end
//     endfunction
    
    
//     // DEBUG OUTPUTS
    
//     `ifdef SIMULATION
//     always @(posedge clk) begin
//         if (window_complete && train_enable) begin
//             $display("[PERCEPTRON] branch=%0d mem=%0d hazard=%0d | scores: P3=%0d P5=%0d P7=%0d | pred=%0d actual=%0d conf=%0d",
//                      branch_count, memory_count, hazard_count,
//                      score_p3, score_p5, score_p7,
//                      predicted_mode, actual_best_mode, confidence);
//         end
//     end
//     `endif

// endmodule

//NEW UNDERNEATH
// Joint Pipeline-Depth + Clock-Frequency Perceptron Predictor V2
//
// NOVEL: Extends Jiménez & Lin's perceptron branch predictor to jointly
// predict both pipeline configuration AND clock frequency from runtime
// workload features — the first such system in a morphable RISC-V CPU.
//
// Architecture:
//   Stage 1: MODE PERCEPTRON (3 perceptrons, one per mode)
//     - Observes branch_count, memory_count, hazard_count
//     - Outputs: predicted_mode (P3/P5/P7) + mode_confidence
//
//   Stage 2: CLOCK PERCEPTRON (1 perceptron)
//     - Observes same features + selected mode
//     - Outputs: clock_index (0=1.0x to 5=1.5x, clamped to mode max)
//     - Higher score = higher clock is safe
//
// Training: Online perceptron update rule
//   - After each instruction window, CPI monitor reports actual_best_mode
//   - Weights reinforced toward correct, anti-reinforced away from wrong
//   - Clock weights adjusted based on whether max clock outperformed
//
// Physical Clock Constraints:
//   P3: max clock index 1 (1.0x, 1.1x)
//   P5: max clock index 3 (1.0x ... 1.3x)
//   P7: max clock index 5 (1.0x ... 1.5x)

module perceptron_predictor_v2 #(
    parameter HISTORY_LEN  = 16,
    parameter WEIGHT_BITS  = 8,
    parameter WINDOW_SIZE  = 32,
    parameter LEARNING_RATE = 1
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        enable,

    // Runtime event inputs
    input  wire        branch_taken,
    input  wire        branch_not_taken,
    input  wire        load_inst,
    input  wire        store_inst,
    input  wire        alu_inst,
    input  wire        hazard_stall,
    input  wire        cache_miss,

    // Training feedback
    input  wire        window_complete,
    input  wire [1:0]  actual_best_mode,
    input  wire        actual_best_max_clk,  // NEW: was max clock optimal?
    input  wire        train_enable,

    // Current state
    input  wire [1:0]  current_mode,

    // Prediction outputs
    output reg  [1:0]  predicted_mode,       // 00=P3, 01=P5, 10=P7
    output reg  [2:0]  predicted_clk_idx,    // NEW: 0-5 clock index
    output reg  [7:0]  confidence,
    output wire        prediction_valid
);

    // ============================================================
    // HISTORY REGISTERS
    // ============================================================

    reg [HISTORY_LEN-1:0] branch_history;
    reg [HISTORY_LEN-1:0] memory_history;
    reg [HISTORY_LEN-1:0] hazard_history;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            branch_history <= {HISTORY_LEN{1'b0}};
            memory_history <= {HISTORY_LEN{1'b0}};
            hazard_history <= {HISTORY_LEN{1'b0}};
        end else if (enable) begin
            branch_history <= {branch_history[HISTORY_LEN-2:0], branch_taken};
            memory_history <= {memory_history[HISTORY_LEN-2:0], load_inst | store_inst};
            hazard_history <= {hazard_history[HISTORY_LEN-2:0], hazard_stall};
        end
    end

    // ============================================================
    // FEATURE EXTRACTION (popcount)
    // ============================================================

    wire [4:0] branch_count, memory_count, hazard_count;

    assign branch_count = branch_history[0]  + branch_history[1]  + branch_history[2]  + branch_history[3]  +
                          branch_history[4]  + branch_history[5]  + branch_history[6]  + branch_history[7]  +
                          branch_history[8]  + branch_history[9]  + branch_history[10] + branch_history[11] +
                          branch_history[12] + branch_history[13] + branch_history[14] + branch_history[15];

    assign memory_count = memory_history[0]  + memory_history[1]  + memory_history[2]  + memory_history[3]  +
                          memory_history[4]  + memory_history[5]  + memory_history[6]  + memory_history[7]  +
                          memory_history[8]  + memory_history[9]  + memory_history[10] + memory_history[11] +
                          memory_history[12] + memory_history[13] + memory_history[14] + memory_history[15];

    assign hazard_count = hazard_history[0]  + hazard_history[1]  + hazard_history[2]  + hazard_history[3]  +
                          hazard_history[4]  + hazard_history[5]  + hazard_history[6]  + hazard_history[7]  +
                          hazard_history[8]  + hazard_history[9]  + hazard_history[10] + hazard_history[11] +
                          hazard_history[12] + hazard_history[13] + hazard_history[14] + hazard_history[15];

    // ============================================================
    // STAGE 1: MODE PERCEPTRON (3 perceptrons)
    // ============================================================

    // Learnable weights: 4 per mode (branch, memory, hazard, bias)
    reg signed [WEIGHT_BITS-1:0] w_p3_branch, w_p3_memory, w_p3_hazard, w_p3_bias;
    reg signed [WEIGHT_BITS-1:0] w_p5_branch, w_p5_memory, w_p5_hazard, w_p5_bias;
    reg signed [WEIGHT_BITS-1:0] w_p7_branch, w_p7_memory, w_p7_hazard, w_p7_bias;

    // Perceptron scores
    reg signed [15:0] score_p3, score_p5, score_p7;

    always @(*) begin
        score_p3 = w_p3_bias +
                   (w_p3_branch * $signed({11'b0, branch_count})) +
                   (w_p3_memory * $signed({11'b0, memory_count})) +
                   (w_p3_hazard * $signed({11'b0, hazard_count}));

        score_p5 = w_p5_bias +
                   (w_p5_branch * $signed({11'b0, branch_count})) +
                   (w_p5_memory * $signed({11'b0, memory_count})) +
                   (w_p5_hazard * $signed({11'b0, hazard_count}));

        score_p7 = w_p7_bias +
                   (w_p7_branch * $signed({11'b0, branch_count})) +
                   (w_p7_memory * $signed({11'b0, memory_count})) +
                   (w_p7_hazard * $signed({11'b0, hazard_count}));
    end

    // Mode selection (argmax)
    reg signed [15:0] max_score, second_score;
    reg [1:0] best_mode;

    always @(*) begin
        if (score_p3 >= score_p5 && score_p3 >= score_p7) begin
            best_mode = 2'b00;
            max_score = score_p3;
            second_score = (score_p5 >= score_p7) ? score_p5 : score_p7;
        end else if (score_p5 >= score_p7) begin
            best_mode = 2'b01;
            max_score = score_p5;
            second_score = (score_p3 >= score_p7) ? score_p3 : score_p7;
        end else begin
            best_mode = 2'b10;
            max_score = score_p7;
            second_score = (score_p3 >= score_p5) ? score_p3 : score_p5;
        end
    end

    // Mode confidence
    wire signed [15:0] mode_margin;
    assign mode_margin = max_score - second_score;

    wire [7:0] mode_conf;
    assign mode_conf = (mode_margin > 16'sd255) ? 8'd255 :
                       (mode_margin < 16'sd0)   ? 8'd0   : mode_margin[7:0];

    // ============================================================
    // STAGE 2: CLOCK PERCEPTRON
    // ============================================================
    //
    // Computes a "clock aggressiveness" score from features.
    // Higher score → use higher clock (more aggressive).
    // Low branch rate + low hazard rate = safe to clock higher.
    //
    // The score is mapped to a clock index, clamped to the
    // selected mode's maximum allowed clock.

    reg signed [WEIGHT_BITS-1:0] w_clk_branch, w_clk_memory, w_clk_hazard, w_clk_bias;

    reg signed [15:0] clk_score;

    always @(*) begin
        // Clock score: high = aggressive (higher clock safe)
        // Low branches (inverted) and low hazards favor higher clock
        clk_score = w_clk_bias +
                    (w_clk_branch * $signed({11'b0, ~branch_count[4:0] & 5'h1F})) +  // Inverted: fewer branches = higher
                    (w_clk_memory * $signed({11'b0, memory_count})) +
                    (w_clk_hazard * $signed({11'b0, ~hazard_count[4:0] & 5'h1F}));    // Inverted: fewer hazards = higher
    end

    // Map clock score to index (0-5)
    reg [2:0] raw_clk_idx;
    always @(*) begin
        if      (clk_score >= 16'sd80)  raw_clk_idx = 3'd5;  // 1.5x
        else if (clk_score >= 16'sd60)  raw_clk_idx = 3'd4;  // 1.4x
        else if (clk_score >= 16'sd40)  raw_clk_idx = 3'd3;  // 1.3x
        else if (clk_score >= 16'sd20)  raw_clk_idx = 3'd2;  // 1.2x
        else if (clk_score >= 16'sd5)   raw_clk_idx = 3'd1;  // 1.1x
        else                            raw_clk_idx = 3'd0;  // 1.0x
    end

    // Clamp to mode's maximum allowed clock
    reg [2:0] max_clk_for_mode;
    always @(*) begin
        case (best_mode)
            2'b00: max_clk_for_mode = 3'd1;  // P3: max 1.1x
            2'b01: max_clk_for_mode = 3'd3;  // P5: max 1.3x
            2'b10: max_clk_for_mode = 3'd5;  // P7: max 1.5x
            default: max_clk_for_mode = 3'd3;
        endcase
    end

    wire [2:0] clamped_clk_idx;
    assign clamped_clk_idx = (raw_clk_idx > max_clk_for_mode) ? max_clk_for_mode : raw_clk_idx;

    // ============================================================
    // OUTPUT REGISTERS
    // ============================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            predicted_mode    <= 2'b01;   // Default P5
            predicted_clk_idx <= 3'd3;    // Default 1.3x (P5 max)
            confidence        <= 8'd0;
        end else if (enable) begin
            predicted_mode    <= best_mode;
            predicted_clk_idx <= clamped_clk_idx;
            confidence        <= mode_conf;
        end
    end

    assign prediction_valid = enable && (confidence > 8'd0);

    // ============================================================
    // ONLINE LEARNING: MODE WEIGHTS
    // ============================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Initial mode weights (from Python simulation insights)
            // P3: positive for branch, positive for high CPI ratio
            w_p3_branch <=  8'sd4;
            w_p3_memory <= -8'sd2;
            w_p3_hazard <= -8'sd1;
            w_p3_bias   <=  8'sd5;

            // P5: balanced, slightly favors stalls
            w_p5_branch <=  8'sd0;
            w_p5_memory <=  8'sd2;
            w_p5_hazard <=  8'sd3;
            w_p5_bias   <=  8'sd8;

            // P7: negative for branch (long flush penalty)
            w_p7_branch <= -8'sd3;
            w_p7_memory <=  8'sd1;
            w_p7_hazard <=  8'sd1;
            w_p7_bias   <=  8'sd6;
        end else if (train_enable && window_complete) begin
            // Perceptron update: reinforce correct, anti-reinforce wrong
            case (actual_best_mode)
                2'b00: begin  // P3 was best
                    if (score_p3 <= score_p5 || score_p3 <= score_p7) begin
                        w_p3_branch <= sat_add(w_p3_branch, branch_count[3:0]);
                        w_p3_memory <= sat_add(w_p3_memory, memory_count[3:0]);
                        w_p3_hazard <= sat_add(w_p3_hazard, hazard_count[3:0]);
                        w_p3_bias   <= sat_add(w_p3_bias,   4'd1);
                        w_p5_bias   <= sat_sub(w_p5_bias,   4'd1);
                        w_p7_bias   <= sat_sub(w_p7_bias,   4'd1);
                    end
                end
                2'b01: begin  // P5 was best
                    if (score_p5 <= score_p3 || score_p5 <= score_p7) begin
                        w_p5_branch <= sat_add(w_p5_branch, branch_count[3:0]);
                        w_p5_memory <= sat_add(w_p5_memory, memory_count[3:0]);
                        w_p5_hazard <= sat_add(w_p5_hazard, hazard_count[3:0]);
                        w_p5_bias   <= sat_add(w_p5_bias,   4'd1);
                        w_p3_bias   <= sat_sub(w_p3_bias,   4'd1);
                        w_p7_bias   <= sat_sub(w_p7_bias,   4'd1);
                    end
                end
                2'b10: begin  // P7 was best
                    if (score_p7 <= score_p3 || score_p7 <= score_p5) begin
                        w_p7_branch <= sat_add(w_p7_branch, branch_count[3:0]);
                        w_p7_memory <= sat_add(w_p7_memory, memory_count[3:0]);
                        w_p7_hazard <= sat_add(w_p7_hazard, hazard_count[3:0]);
                        w_p7_bias   <= sat_add(w_p7_bias,   4'd1);
                        w_p3_bias   <= sat_sub(w_p3_bias,   4'd1);
                        w_p5_bias   <= sat_sub(w_p5_bias,   4'd1);
                    end
                end
                default: ;
            endcase
        end
    end

    // ============================================================
    // ONLINE LEARNING: CLOCK WEIGHTS
    // ============================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Initialize clock weights: bias toward max clock
            w_clk_branch <=  8'sd3;   // Low branches → higher clock
            w_clk_memory <=  8'sd1;
            w_clk_hazard <=  8'sd2;   // Low hazards → higher clock
            w_clk_bias   <=  8'sd15;  // Strong bias toward high clock
        end else if (train_enable && window_complete) begin
            // If max clock was best, reinforce aggressive clocking
            if (actual_best_max_clk) begin
                w_clk_bias <= sat_add(w_clk_bias, 4'd1);
            end else begin
                // Max clock wasn't optimal — be more conservative
                w_clk_bias   <= sat_sub(w_clk_bias,   4'd2);
                w_clk_branch <= sat_add(w_clk_branch,  4'd1);  // Be more sensitive to branches
                w_clk_hazard <= sat_add(w_clk_hazard,  4'd1);  // Be more sensitive to hazards
            end
        end
    end

    // ============================================================
    // SATURATING ARITHMETIC
    // ============================================================

    function signed [7:0] sat_add;
        input signed [7:0] a;
        input [3:0] b;
        reg signed [8:0] result;
        begin
            result = a + $signed({5'b0, b});
            if (result > 9'sd127)       sat_add = 8'sd127;
            else if (result < -9'sd128) sat_add = -8'sd128;
            else                        sat_add = result[7:0];
        end
    endfunction

    function signed [7:0] sat_sub;
        input signed [7:0] a;
        input [3:0] b;
        reg signed [8:0] result;
        begin
            result = a - $signed({5'b0, b});
            if (result > 9'sd127)       sat_sub = 8'sd127;
            else if (result < -9'sd128) sat_sub = -8'sd128;
            else                        sat_sub = result[7:0];
        end
    endfunction

    // ============================================================
    // DEBUG
    // ============================================================

    `ifdef SIMULATION
    always @(posedge clk) begin
        if (window_complete && train_enable) begin
            $display("[PERCEPTRON-V2] br=%0d mem=%0d haz=%0d | mode_scores: P3=%0d P5=%0d P7=%0d | clk_score=%0d | pred=P%0d@clk%0d | actual_best=P%0d max_clk=%0b conf=%0d",
                     branch_count, memory_count, hazard_count,
                     score_p3, score_p5, score_p7, clk_score,
                     (predicted_mode == 2'b00) ? 3 : (predicted_mode == 2'b01) ? 5 : 7,
                     predicted_clk_idx,
                     (actual_best_mode == 2'b00) ? 3 : (actual_best_mode == 2'b01) ? 5 : 7,
                     actual_best_max_clk, confidence);
        end
    end
    `endif

endmodule