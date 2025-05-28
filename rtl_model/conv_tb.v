 `timescale 1ns / 1ps

module conv_tb;

// Parameters
parameter DATA_WIDTH = 8;
parameter KERNEL_SIZE = 3;
parameter IN_CHANNEL = 3;
parameter NUM_FILTERS = 3;
parameter IMG_WIDTH = 8;
parameter IMG_HEIGHT = 8;
parameter STRIDE = 1;
parameter PADDING = (KERNEL_SIZE - 1) / 2;
parameter WEIGHT_WIDTH = 8;
parameter OUTPUT_WIDTH = 20;
parameter ACC_WIDTH = 2*DATA_WIDTH + 4 + $clog2(KERNEL_SIZE*KERNEL_SIZE*IN_CHANNEL);
parameter INIT_FILE = "weights.mem";

// Calculated parameters
parameter OUTPUT_IMG_WIDTH = (IMG_WIDTH + 2*PADDING - KERNEL_SIZE) / STRIDE + 1;
parameter OUTPUT_IMG_HEIGHT = (IMG_HEIGHT + 2*PADDING - KERNEL_SIZE) / STRIDE + 1;

// Signals
reg clk;
reg rst_n;
reg [IN_CHANNEL*DATA_WIDTH-1:0] pixel_in;
reg pixel_valid;
reg frame_start;
wire [NUM_FILTERS*OUTPUT_WIDTH-1:0] conv_out;
wire conv_valid;

// Test data structures
reg [DATA_WIDTH-1:0] test_image [0:IN_CHANNEL-1][0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
reg [WEIGHT_WIDTH-1:0] golden_weights [0:NUM_FILTERS-1][0:IN_CHANNEL-1][0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
reg [OUTPUT_WIDTH-1:0] golden_output [0:NUM_FILTERS-1][0:OUTPUT_IMG_HEIGHT-1][0:OUTPUT_IMG_WIDTH-1];
reg [OUTPUT_WIDTH-1:0] actual_output [0:NUM_FILTERS-1][0:OUTPUT_IMG_HEIGHT-1][0:OUTPUT_IMG_WIDTH-1];

// Test control variables
integer row, col, ch, f, k_row, k_col;
integer output_count;
integer expected_outputs;
integer test_case;
integer errors;
integer current_output_row, current_output_col;

// Clock generation
always #5 clk = ~clk;

// DUT instantiation
conv #(
    .DATA_WIDTH(DATA_WIDTH),
    .KERNEL_SIZE(KERNEL_SIZE),
    .IN_CHANNEL(IN_CHANNEL),
    .NUM_FILTERS(NUM_FILTERS),
    .IMG_WIDTH(IMG_WIDTH),
    .IMG_HEIGHT(IMG_HEIGHT),
    .STRIDE(STRIDE),
    .PADDING(PADDING),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .OUTPUT_WIDTH(OUTPUT_WIDTH),
    .ACC_WIDTH(ACC_WIDTH),
    .INIT_FILE(INIT_FILE)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .pixel_in(pixel_in),
    .pixel_valid(pixel_valid),
    .frame_start(frame_start),
    .conv_out(conv_out),
    .conv_valid(conv_valid)
);

// Load weights from file for golden reference
task load_golden_weights;
    integer weight_file;
    integer weight_idx;
    reg [WEIGHT_WIDTH-1:0] temp_weight;
    reg [200*8-1:0] line_buffer; // Buffer for reading lines
    integer scan_result;
    integer line_count;
    integer file_open_success;
    integer eof_reached;
    integer valid_line;
    begin
        // Try to load from file first
        weight_file = $fopen("weights.mem", "r");
        file_open_success = (weight_file != 0);
        
        if (!file_open_success) begin
            $display("WARNING: Cannot open weights.mem file, using hardcoded weights");
            load_hardcoded_weights();
        end
        
        if (file_open_success) begin
            weight_idx = 0;
            line_count = 0;
            eof_reached = 0;
            $display("Reading weights from weights.mem...");
            
            while (!eof_reached && weight_idx < NUM_FILTERS*IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE) begin
                valid_line = $fgets(line_buffer, weight_file);
                if (valid_line) begin
                    line_count = line_count + 1;
                    
                    // Check if this is a comment or empty line
                    if (!(line_buffer[7:0] == "/" || line_buffer[15:8] == "/" || 
                          line_buffer[7:0] == " " || line_buffer[7:0] == "\n" || line_buffer[7:0] == "\r")) begin
                        
                        // Try to parse hex value from the line
                        scan_result = $sscanf(line_buffer, "%h", temp_weight);
                        if (scan_result == 1) begin
                            f = weight_idx / (IN_CHANNEL * KERNEL_SIZE * KERNEL_SIZE);
                            ch = (weight_idx % (IN_CHANNEL * KERNEL_SIZE * KERNEL_SIZE)) / (KERNEL_SIZE * KERNEL_SIZE);
                            k_row = ((weight_idx % (IN_CHANNEL * KERNEL_SIZE * KERNEL_SIZE)) % (KERNEL_SIZE * KERNEL_SIZE)) / KERNEL_SIZE;
                            k_col = ((weight_idx % (IN_CHANNEL * KERNEL_SIZE * KERNEL_SIZE)) % (KERNEL_SIZE * KERNEL_SIZE)) % KERNEL_SIZE;
                            
                            golden_weights[f][ch][k_row][k_col] = temp_weight;
                            $display("Loaded weight[%0d][%0d][%0d][%0d] = %02X", f, ch, k_row, k_col, temp_weight);
                            weight_idx = weight_idx + 1;
                        end
                    end
                end else begin
                    // End of file reached
                    eof_reached = 1;
                end
            end
            
            $fclose(weight_file);
            $display("Loaded %0d weights from %0d lines for golden reference", weight_idx, line_count);
            
            // If we didn't load enough weights, use hardcoded values
            if (weight_idx < NUM_FILTERS*IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE) begin
                $display("WARNING: Only loaded %0d weights, expected %0d. Using hardcoded weights.", 
                         weight_idx, NUM_FILTERS*IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE);
                load_hardcoded_weights();
            end
        end
    end
endtask

// Hardcoded weights as backup
task load_hardcoded_weights;
    begin
        $display("Loading hardcoded weights...");
        
        // Filter 0: Edge detection (Sobel-like) - UNSIGNED weights
        // All channels use the same weights
        for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
            golden_weights[0][ch][0][0] = 8'hFF; // 255 (unsigned)
            golden_weights[0][ch][0][1] = 8'h00; //   0
            golden_weights[0][ch][0][2] = 8'h01; //   1
            golden_weights[0][ch][1][0] = 8'hFE; // 254 (unsigned)
            golden_weights[0][ch][1][1] = 8'h00; //   0
            golden_weights[0][ch][1][2] = 8'h02; //   2
            golden_weights[0][ch][2][0] = 8'hFF; // 255 (unsigned)
            golden_weights[0][ch][2][1] = 8'h00; //   0
            golden_weights[0][ch][2][2] = 8'h01; //   1
        end
        
        // Filter 1: Blur (all weights = 1)
        for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
            for (k_row = 0; k_row < KERNEL_SIZE; k_row = k_row + 1) begin
                for (k_col = 0; k_col < KERNEL_SIZE; k_col = k_col + 1) begin
                    golden_weights[1][ch][k_row][k_col] = 8'h01;
                end
            end
        end
        
        // Filter 2: Sharpen - UNSIGNED weights
        for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
            golden_weights[2][ch][0][0] = 8'h00; //   0
            golden_weights[2][ch][0][1] = 8'hFF; // 255 (unsigned)
            golden_weights[2][ch][0][2] = 8'h00; //   0
            golden_weights[2][ch][1][0] = 8'hFF; // 255 (unsigned)
            golden_weights[2][ch][1][1] = 8'h05; //   5
            golden_weights[2][ch][1][2] = 8'hFF; // 255 (unsigned)
            golden_weights[2][ch][2][0] = 8'h00; //   0
            golden_weights[2][ch][2][1] = 8'hFF; // 255 (unsigned)
            golden_weights[2][ch][2][2] = 8'h00; //   0
        end
        
        $display("Hardcoded weights loaded successfully - ALL UNSIGNED VALUES");
        $display("NOTE: Hardware uses UNSIGNED arithmetic, so 0xFF=255, 0xFE=254");
    end
endtask

// Generate test patterns
task generate_test_pattern;
    input integer pattern_type;
    begin
        case (pattern_type)
            0: begin // Gradient pattern
                $display("Generating gradient test pattern");
                for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                    for (row = 0; row < IMG_HEIGHT; row = row + 1) begin
                        for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                            test_image[ch][row][col] = (ch * 64) + (row * 8) + col + 1;
                        end
                    end
                end
            end
            
            1: begin // Checkerboard pattern
                $display("Generating checkerboard test pattern");
                for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                    for (row = 0; row < IMG_HEIGHT; row = row + 1) begin
                        for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                            test_image[ch][row][col] = ((row + col + ch) % 2) ? 8'hFF : 8'h00;
                        end
                    end
                end
            end
            
            2: begin // Random pattern
                $display("Generating random test pattern");
                for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                    for (row = 0; row < IMG_HEIGHT; row = row + 1) begin
                        for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                            test_image[ch][row][col] = $random % 256;
                        end
                    end
                end
            end
            
            3: begin // Edge case pattern
                $display("Generating edge case test pattern");
                for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                    for (row = 0; row < IMG_HEIGHT; row = row + 1) begin
                        for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                            if (row == 0 || row == IMG_HEIGHT-1 || col == 0 || col == IMG_WIDTH-1)
                                test_image[ch][row][col] = 8'hFF;
                            else
                                test_image[ch][row][col] = 8'h00;
                        end
                    end
                end
            end
        endcase
    end
endtask

// Golden reference convolution calculation
task calculate_golden_reference;
    integer out_row, out_col;
    integer src_row, src_col;
    integer sum;
    begin
        $display("Calculating golden reference...");
        
        for (f = 0; f < NUM_FILTERS; f = f + 1) begin
            for (out_row = 0; out_row < OUTPUT_IMG_HEIGHT; out_row = out_row + 1) begin
                for (out_col = 0; out_col < OUTPUT_IMG_WIDTH; out_col = out_col + 1) begin
                    sum = 0;
                    
                    // Convolution calculation
                    for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                        for (k_row = 0; k_row < KERNEL_SIZE; k_row = k_row + 1) begin
                            for (k_col = 0; k_col < KERNEL_SIZE; k_col = k_col + 1) begin
                                src_row = out_row * STRIDE + k_row - PADDING;
                                src_col = out_col * STRIDE + k_col - PADDING;
                                
                                if (src_row >= 0 && src_row < IMG_HEIGHT && 
                                    src_col >= 0 && src_col < IMG_WIDTH) begin
                                    sum = sum + (test_image[ch][src_row][src_col] * 
                                               golden_weights[f][ch][k_row][k_col]);
                                end
                                // Padding is 0, so no addition needed for out-of-bounds
                            end
                        end
                    end
                    
                    // Apply saturation
                    if (sum > ((1 << OUTPUT_WIDTH) - 1))
                        golden_output[f][out_row][out_col] = (1 << OUTPUT_WIDTH) - 1;
                    else if (sum < 0)
                        golden_output[f][out_row][out_col] = 0;
                    else
                        golden_output[f][out_row][out_col] = sum;
                end
            end
        end
        $display("Golden reference calculation completed");
    end
endtask

// Display test image
task display_test_image;
    begin
        $display("\n=== Test Image ===");
        for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
            $display("Channel %0d:", ch);
            for (row = 0; row < IMG_HEIGHT; row = row + 1) begin
                $write("  ");
                for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                    $write("%02X ", test_image[ch][row][col]);
                end
                $write("\n");
            end
        end
    end
endtask

// Display weights
task display_weights;
    begin
        $display("\n=== Weights ===");
        for (f = 0; f < NUM_FILTERS; f = f + 1) begin
            $display("Filter %0d:", f);
            for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                $display("  Channel %0d:", ch);
                for (k_row = 0; k_row < KERNEL_SIZE; k_row = k_row + 1) begin
                    $write("    ");
                    for (k_col = 0; k_col < KERNEL_SIZE; k_col = k_col + 1) begin
                        $write("%02X ", golden_weights[f][ch][k_row][k_col]);
                    end
                    $write("\n");
                end
            end
        end
    end
endtask

// Compare results
task compare_results;
    integer match;
    integer total_comparisons;
    begin
        $display("\n=== Comparison Results ===");
        errors = 0;
        total_comparisons = 0;
        
        for (f = 0; f < NUM_FILTERS; f = f + 1) begin
            $display("Filter %0d comparison:", f);
            for (row = 0; row < OUTPUT_IMG_HEIGHT; row = row + 1) begin
                for (col = 0; col < OUTPUT_IMG_WIDTH; col = col + 1) begin
                    match = (actual_output[f][row][col] == golden_output[f][row][col]);
                    total_comparisons = total_comparisons + 1;
                    
                    if (!match) begin
                        errors = errors + 1;
                        $display("  MISMATCH at [%0d,%0d]: Expected=%0d, Actual=%0d", 
                                row, col, golden_output[f][row][col], actual_output[f][row][col]);
                    end else begin
                        $display("  MATCH at [%0d,%0d]: %0d", row, col, actual_output[f][row][col]);
                    end
                end
            end
        end
        
        $display("\nComparison Summary:");
        $display("  Total comparisons: %0d", total_comparisons);
        $display("  Matches: %0d", total_comparisons - errors);
        $display("  Mismatches: %0d", errors);
        $display("  Accuracy: %0.2f%%", (total_comparisons - errors) * 100.0 / total_comparisons);
    end
endtask

// Run test case
task run_test_case;
    input integer pattern_type;
    begin
        $display("\n" + "="*60);
        $display("Running Test Case %0d", pattern_type);
        $display("="*60);
        
        // Generate test pattern
        generate_test_pattern(pattern_type);
        
        // Calculate golden reference
        calculate_golden_reference();
        
        // Display test data
        display_test_image();
        display_weights();
        
        // Reset DUT
        rst_n = 0;
        pixel_in = 0;
        pixel_valid = 0;
        frame_start = 0;
        output_count = 0;
        current_output_row = 0;
        current_output_col = 0;
        
        #20 rst_n = 1;
        
        // Wait for weights to load
        wait(dut.weights_loaded == 1);
        $display("Weights loaded successfully");
        
        #20;
        
        // Start frame
        frame_start = 1;
        #10;
        frame_start = 0;
        
        // Feed image data
        $display("Feeding image data...");
        for (row = 0; row < IMG_HEIGHT; row = row + 1) begin
            for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                pixel_in = {test_image[2][row][col], test_image[1][row][col], test_image[0][row][col]};
                pixel_valid = 1;
                #10;
                pixel_valid = 0;
                $display("Fed pixel [%0d,%0d]: Ch0=%02X, Ch1=%02X, Ch2=%02X", 
                         row, col, test_image[0][row][col], test_image[1][row][col], test_image[2][row][col]);
            end
        end
        
        // Wait for all outputs
        expected_outputs = OUTPUT_IMG_WIDTH * OUTPUT_IMG_HEIGHT;
        $display("Waiting for %0d outputs...", expected_outputs);
        
        while (output_count < expected_outputs) begin
            #10;
        end
        
        #100; // Additional wait
        
        // Compare results
        compare_results();
    end
endtask

// Monitor outputs and store them
always @(posedge clk) begin
    if (conv_valid) begin
        if (current_output_col >= OUTPUT_IMG_WIDTH) begin
            current_output_col = 0;
            current_output_row = current_output_row + 1;
        end
        
        // Store actual outputs
        for (f = 0; f < NUM_FILTERS; f = f + 1) begin
            actual_output[f][current_output_row][current_output_col] = 
                conv_out[(f+1)*OUTPUT_WIDTH-1 -: OUTPUT_WIDTH];
        end
        
        output_count = output_count + 1;
        $display("Output %0d at [%0d,%0d]: Filter0=%05d, Filter1=%05d, Filter2=%05d", 
                 output_count, current_output_row, current_output_col,
                 conv_out[OUTPUT_WIDTH-1:0],
                 conv_out[2*OUTPUT_WIDTH-1:OUTPUT_WIDTH],
                 conv_out[3*OUTPUT_WIDTH-1:2*OUTPUT_WIDTH]);
        
        current_output_col = current_output_col + 1;
    end
end

// Main test sequence
initial begin
    clk = 0;
    errors = 0;
    
    $dumpfile("conv_tb.vcd");
    $dumpvars(0, conv_tb);
    
    $display("=== Comprehensive Conv Module Test ===");
    $display("Image size: %0dx%0d", IMG_WIDTH, IMG_HEIGHT);
    $display("Output size: %0dx%0d", OUTPUT_IMG_WIDTH, OUTPUT_IMG_HEIGHT);
    $display("Channels: %0d, Filters: %0d", IN_CHANNEL, NUM_FILTERS);
    $display("Output width: %0d bits", OUTPUT_WIDTH);
    
    // Load golden weights
    load_golden_weights();
    
    // Run multiple test cases
    for (test_case = 0; test_case < 4; test_case = test_case + 1) begin
        run_test_case(test_case);
    end
    
    // Final summary
    $display("\n" + "="*60);
    $display("FINAL TEST SUMMARY");
    $display("="*60);
    if (errors == 0) begin
        $display("SUCCESS: All test cases passed!");
    end else begin
        $display("FAILED: %0d errors found across all test cases", errors);
    end
    $display("="*60);
    
    $finish;
end

endmodule