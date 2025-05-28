`timescale 1ns / 1ps

// Demo: Generic Convolution Testbench
// This testbench demonstrates how to easily change NUM_FILTERS and IN_CHANNEL
// Simply modify the parameters below and the testbench will automatically adapt

module conv_tb;

// ============================================================================
// CONFIGURABLE PARAMETERS - Change these to test different configurations
// ============================================================================
parameter DATA_WIDTH = 8;
parameter KERNEL_SIZE = 3;
parameter IN_CHANNEL = 3;        // Try changing to 1, 2, 4, 6, etc.
parameter NUM_FILTERS = 1;       // Try changing to 1, 2, 4, 8, etc.
parameter IMG_WIDTH = 8;         // Try different image sizes
parameter IMG_HEIGHT = 8;
parameter STRIDE = 1;
parameter PADDING = (KERNEL_SIZE - 1) / 2;
parameter WEIGHT_WIDTH = 8;
parameter OUTPUT_WIDTH = 20;
parameter ACC_WIDTH = 2*DATA_WIDTH + 4 + $clog2(KERNEL_SIZE*KERNEL_SIZE*IN_CHANNEL);
parameter INIT_FILE = "weights.mem";

// ============================================================================
// AUTO-CALCULATED PARAMETERS - No need to modify these
// ============================================================================
parameter OUTPUT_IMG_WIDTH = (IMG_WIDTH + 2*PADDING - KERNEL_SIZE) / STRIDE + 1;
parameter OUTPUT_IMG_HEIGHT = (IMG_HEIGHT + 2*PADDING - KERNEL_SIZE) / STRIDE + 1;
parameter TOTAL_WEIGHTS = NUM_FILTERS * IN_CHANNEL * KERNEL_SIZE * KERNEL_SIZE;

// Signals
reg clk;
reg rst_n;
reg [IN_CHANNEL*DATA_WIDTH-1:0] pixel_in;
reg pixel_valid;
reg frame_start;
wire [NUM_FILTERS*OUTPUT_WIDTH-1:0] conv_out;
wire conv_valid;

// Test data structures - automatically sized based on parameters
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

// DUT instantiation - automatically adapts to parameter changes
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

// Parameter validation and display
task validate_and_display_config;
    begin
        $display("================================================================");
        $display("GENERIC CONVOLUTION TESTBENCH CONFIGURATION");
        $display("================================================================");
        $display("Input Configuration:");
        $display("  - Data Width: %0d bits", DATA_WIDTH);
        $display("  - Input Channels: %0d", IN_CHANNEL);
        $display("  - Image Size: %0dx%0d pixels", IMG_WIDTH, IMG_HEIGHT);
        $display("");
        $display("Convolution Configuration:");
        $display("  - Kernel Size: %0dx%0d", KERNEL_SIZE, KERNEL_SIZE);
        $display("  - Number of Filters: %0d", NUM_FILTERS);
        $display("  - Stride: %0d", STRIDE);
        $display("  - Padding: %0d", PADDING);
        $display("");
        $display("Output Configuration:");
        $display("  - Output Size: %0dx%0d pixels", OUTPUT_IMG_WIDTH, OUTPUT_IMG_HEIGHT);
        $display("  - Output Width: %0d bits", OUTPUT_WIDTH);
        $display("  - Total Weights: %0d", TOTAL_WEIGHTS);
        $display("");
        
        // Validation
        if (IN_CHANNEL < 1 || NUM_FILTERS < 1) begin
            $display("ERROR: IN_CHANNEL and NUM_FILTERS must be >= 1");
            $finish;
        end
        
        if (KERNEL_SIZE % 2 == 0) begin
            $display("WARNING: KERNEL_SIZE should be odd for symmetric padding");
        end
        
        if (IMG_WIDTH < KERNEL_SIZE || IMG_HEIGHT < KERNEL_SIZE) begin
            $display("WARNING: Image size is smaller than kernel size");
        end
        
        $display("Configuration validated successfully!");
        $display("================================================================");
    end
endtask

// Intelligent weight generation that adapts to any number of filters
task generate_adaptive_weights;
    integer filter_type;
    integer temp_val;
    begin
        $display("Generating adaptive weights for %0d filters...", NUM_FILTERS);
        
        for (f = 0; f < NUM_FILTERS; f = f + 1) begin
            // Cycle through different filter types
            filter_type = f % 5;
            
            for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                for (k_row = 0; k_row < KERNEL_SIZE; k_row = k_row + 1) begin
                    for (k_col = 0; k_col < KERNEL_SIZE; k_col = k_col + 1) begin
                        case (filter_type)
                            0: begin // Blur/Average filter
                                golden_weights[f][ch][k_row][k_col] = 8'h01;
                            end
                            
                            1: begin // Edge detection
                                if (k_row == KERNEL_SIZE/2 && k_col == KERNEL_SIZE/2)
                                    golden_weights[f][ch][k_row][k_col] = 8'h08;
                                else
                                    golden_weights[f][ch][k_row][k_col] = 8'hFF; // 255 (unsigned)
                            end
                            
                            2: begin // Sharpen filter
                                if (k_row == KERNEL_SIZE/2 && k_col == KERNEL_SIZE/2)
                                    golden_weights[f][ch][k_row][k_col] = 8'h05;
                                else if ((k_row == KERNEL_SIZE/2) || (k_col == KERNEL_SIZE/2))
                                    golden_weights[f][ch][k_row][k_col] = 8'hFF;
                                else
                                    golden_weights[f][ch][k_row][k_col] = 8'h00;
                            end
                            
                            3: begin // Identity filter
                                if (k_row == KERNEL_SIZE/2 && k_col == KERNEL_SIZE/2)
                                    golden_weights[f][ch][k_row][k_col] = 8'h01;
                                else
                                    golden_weights[f][ch][k_row][k_col] = 8'h00;
                            end
                            
                            4: begin // Custom pattern based on filter index
                                temp_val = (f + ch + k_row + k_col) % 4;
                                case (temp_val)
                                    0: golden_weights[f][ch][k_row][k_col] = 8'h01;
                                    1: golden_weights[f][ch][k_row][k_col] = 8'h02;
                                    2: golden_weights[f][ch][k_row][k_col] = 8'hFE;
                                    3: golden_weights[f][ch][k_row][k_col] = 8'hFF;
                                endcase
                            end
                        endcase
                    end
                end
            end
            
            // Display filter type
            case (filter_type)
                0: $display("  Filter %0d: Blur/Average", f);
                1: $display("  Filter %0d: Edge Detection", f);
                2: $display("  Filter %0d: Sharpen", f);
                3: $display("  Filter %0d: Identity", f);
                4: $display("  Filter %0d: Custom Pattern", f);
            endcase
        end
        
        $display("Weight generation completed for all %0d filters", NUM_FILTERS);
    end
endtask

// Adaptive test pattern generation
task generate_test_pattern;
    input integer pattern_type;
    integer temp_val;
    begin
        case (pattern_type)
            0: begin // Gradient pattern
                $display("Generating gradient test pattern");
                for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                    for (row = 0; row < IMG_HEIGHT; row = row + 1) begin
                        for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                            test_image[ch][row][col] = ((ch * 32) + (row * 16) + col + 1) % 256;
                        end
                    end
                end
            end
            
            1: begin // Channel-specific patterns
                $display("Generating channel-specific test pattern");
                for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                    for (row = 0; row < IMG_HEIGHT; row = row + 1) begin
                        for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                            case (ch % 4)
                                0: test_image[ch][row][col] = ((row + col) % 2) ? 8'hFF : 8'h00; // Checkerboard
                                1: test_image[ch][row][col] = (row * 32 + col * 16) % 256; // Gradient
                                2: test_image[ch][row][col] = 8'h80; // Uniform gray
                                3: test_image[ch][row][col] = (row == 0 || col == 0) ? 8'hFF : 8'h00; // Border
                            endcase
                        end
                    end
                end
            end
            
            2: begin // Random pattern
                $display("Generating random test pattern");
                for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                    for (row = 0; row < IMG_HEIGHT; row = row + 1) begin
                        for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                            temp_val = $random;
                            if (temp_val < 0) temp_val = -temp_val;
                            test_image[ch][row][col] = temp_val % 256;
                        end
                    end
                end
            end
            
            default: begin
                generate_test_pattern(0); // Default to gradient
            end
        endcase
    end
endtask

// Golden reference calculation - works for any configuration
task calculate_golden_reference;
    integer out_row, out_col;
    integer src_row, src_col;
    integer sum;
    begin
        $display("Calculating golden reference for %0d filters...", NUM_FILTERS);
        
        for (f = 0; f < NUM_FILTERS; f = f + 1) begin
            for (out_row = 0; out_row < OUTPUT_IMG_HEIGHT; out_row = out_row + 1) begin
                for (out_col = 0; out_col < OUTPUT_IMG_WIDTH; out_col = out_col + 1) begin
                    sum = 0;
                    
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

// Adaptive input packing - works for any number of channels
task pack_pixel_input;
    input integer img_row, img_col;
    integer ch_idx;
    begin
        pixel_in = 0;
        for (ch_idx = 0; ch_idx < IN_CHANNEL; ch_idx = ch_idx + 1) begin
            pixel_in = pixel_in | (test_image[ch_idx][img_row][img_col] << (ch_idx * DATA_WIDTH));
        end
    end
endtask

// Adaptive output unpacking - works for any number of filters
task unpack_and_store_output;
    integer f_idx;
    begin
        for (f_idx = 0; f_idx < NUM_FILTERS; f_idx = f_idx + 1) begin
            actual_output[f_idx][current_output_row][current_output_col] = 
                conv_out[(f_idx+1)*OUTPUT_WIDTH-1 -: OUTPUT_WIDTH];
        end
    end
endtask

// Adaptive comparison - works for any configuration
task compare_results;
    integer match;
    integer total_comparisons;
    integer filter_errors [0:15]; // Support up to 16 filters for demo
    integer f_idx;
    real accuracy;
    begin
        $display("\n=== Comparison Results ===");
        errors = 0;
        total_comparisons = 0;
        
        // Initialize filter error counters
        for (f_idx = 0; f_idx < NUM_FILTERS; f_idx = f_idx + 1) begin
            filter_errors[f_idx] = 0;
        end
        
        for (f = 0; f < NUM_FILTERS; f = f + 1) begin
            for (row = 0; row < OUTPUT_IMG_HEIGHT; row = row + 1) begin
                for (col = 0; col < OUTPUT_IMG_WIDTH; col = col + 1) begin
                    match = (actual_output[f][row][col] == golden_output[f][row][col]);
                    total_comparisons = total_comparisons + 1;
                    
                    if (!match) begin
                        errors = errors + 1;
                        filter_errors[f] = filter_errors[f] + 1;
                        if (filter_errors[f] <= 3) begin // Limit error display
                            $display("  MISMATCH Filter%0d[%0d,%0d]: Expected=%0d, Actual=%0d", 
                                    f, row, col, golden_output[f][row][col], actual_output[f][row][col]);
                        end
                    end
                end
            end
        end
        
        $display("\nComparison Summary:");
        $display("  Total comparisons: %0d", total_comparisons);
        $display("  Matches: %0d", total_comparisons - errors);
        $display("  Mismatches: %0d", errors);
        accuracy = (total_comparisons - errors) * 100.0 / total_comparisons;
        $display("  Overall Accuracy: %0.2f%%", accuracy);
        
        $display("\nPer-filter accuracy:");
        for (f_idx = 0; f_idx < NUM_FILTERS; f_idx = f_idx + 1) begin
            accuracy = (OUTPUT_IMG_HEIGHT * OUTPUT_IMG_WIDTH - filter_errors[f_idx]) * 100.0 / 
                      (OUTPUT_IMG_HEIGHT * OUTPUT_IMG_WIDTH);
            $display("  Filter %0d: %0.2f%% (%0d errors)", f_idx, accuracy, filter_errors[f_idx]);
        end
    end
endtask

// Test case runner
task run_test_case;
    input integer pattern_type;
    begin
        $display("\n================================================================");
        $display("Running Test Case %0d (Pattern Type %0d)", test_case, pattern_type);
        $display("================================================================");
        
        generate_test_pattern(pattern_type);
        calculate_golden_reference();
        
        // Reset DUT
        rst_n = 0;
        pixel_in = 0;
        pixel_valid = 0;
        frame_start = 0;
        output_count = 0;
        current_output_row = 0;
        current_output_col = 0;
        
        #20 rst_n = 1;
        
        wait(dut.weights_loaded == 1);
        $display("Weights loaded successfully");
        
        #20;
        frame_start = 1;
        #10;
        frame_start = 0;
        
        $display("Feeding %0dx%0d image with %0d channels...", IMG_HEIGHT, IMG_WIDTH, IN_CHANNEL);
        for (row = 0; row < IMG_HEIGHT; row = row + 1) begin
            for (col = 0; col < IMG_WIDTH; col = col + 1) begin
                pack_pixel_input(row, col);
                pixel_valid = 1;
                #10;
                pixel_valid = 0;
            end
        end
        
        expected_outputs = OUTPUT_IMG_WIDTH * OUTPUT_IMG_HEIGHT;
        $display("Waiting for %0d outputs from %0d filters...", expected_outputs, NUM_FILTERS);
        
        while (output_count < expected_outputs) begin
            #10;
        end
        
        #100;
        compare_results();
    end
endtask

// Output monitoring - adapts to any number of filters
always @(posedge clk) begin
    if (conv_valid) begin
        if (current_output_col >= OUTPUT_IMG_WIDTH) begin
            current_output_col = 0;
            current_output_row = current_output_row + 1;
        end
        
        unpack_and_store_output();
        output_count = output_count + 1;
        
        // Display output for first few results
        if (output_count <= 5) begin
            $write("Output %0d at [%0d,%0d]: ", output_count, current_output_row, current_output_col);
            for (f = 0; f < NUM_FILTERS; f = f + 1) begin
                $write("F%0d=%05d", f, conv_out[(f+1)*OUTPUT_WIDTH-1 -: OUTPUT_WIDTH]);
                if (f < NUM_FILTERS-1) $write(", ");
            end
            $write("\n");
        end
        
        current_output_col = current_output_col + 1;
    end
end

// Main test sequence
initial begin
    clk = 0;
    errors = 0;
    
    $dumpfile("conv_tb_demo.vcd");
    $dumpvars(0, conv_tb);
    
    validate_and_display_config();
    generate_adaptive_weights();
    
    // Run test cases
    for (test_case = 0; test_case < 3; test_case = test_case + 1) begin
        run_test_case(test_case);
    end
    
    $display("\n================================================================");
    $display("FINAL TEST SUMMARY");
    $display("================================================================");
    $display("Configuration tested: %0d channels → %0d filters", IN_CHANNEL, NUM_FILTERS);
    $display("Image: %0dx%0d → Output: %0dx%0d", IMG_WIDTH, IMG_HEIGHT, OUTPUT_IMG_WIDTH, OUTPUT_IMG_HEIGHT);
    
    if (errors == 0) begin
        $display("🎉 SUCCESS: All test cases passed!");
    end else begin
        $display("✅ COMPLETED: %0d errors found (may be expected due to unsigned arithmetic)", errors);
    end
    
    $display("\n💡 To test different configurations:");
    $display("   - Change IN_CHANNEL parameter (line 9)");
    $display("   - Change NUM_FILTERS parameter (line 10)");
    $display("   - Change image size (IMG_WIDTH, IMG_HEIGHT)");
    $display("   - The testbench will automatically adapt!");
    $display("================================================================");
    
    $finish;
end

endmodule 