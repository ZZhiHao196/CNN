 `timescale 1ns / 1ps

module weight_tb;

// Parameters - matching default weight.v parameters
parameter NUM_FILTERS = 3;
parameter INPUT_CHANNELS = 3;
parameter KERNEL_SIZE = 3;
parameter WEIGHT_WIDTH = 16;
parameter INIT_FILE = "weights_example.mem";

// Clock and reset
reg clk;
reg rst_n;

// Weight ROM interface
reg [$clog2(NUM_FILTERS)-1:0] filter_idx;
reg [$clog2(INPUT_CHANNELS)-1:0] channel_idx;
reg read_enable;

// Outputs
wire [KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] flattened_weight_out;
wire weight_valid;

// Test variables
integer i, j, k;
integer test_count;
integer pass_count;

// Instantiate the weight ROM module
weight #(
    .NUM_FILTERS(NUM_FILTERS),
    .INPUT_CHANNELS(INPUT_CHANNELS),
    .KERNEL_SIZE(KERNEL_SIZE),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .INIT_FILE(INIT_FILE)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .filter_idx(filter_idx),
    .channel_idx(channel_idx),
    .read_enable(read_enable),
    .flattened_weight_out(flattened_weight_out),
    .weight_valid(weight_valid)
);

// Clock generation
always #5 clk = ~clk;

// Test stimulus
initial begin
    // Initialize signals
    clk = 0;
    rst_n = 0;
    filter_idx = 0;
    channel_idx = 0;
    read_enable = 0;
    test_count = 0;
    pass_count = 0;
    
    // Create VCD file for waveform viewing
    $dumpfile("weight_tb.vcd");
    $dumpvars(0, weight_tb);
    
    $display("=== Weight ROM Testbench Started ===");
    $display("Configuration:");
    $display("  NUM_FILTERS = %d", NUM_FILTERS);
    $display("  INPUT_CHANNELS = %d", INPUT_CHANNELS);
    $display("  KERNEL_SIZE = %d", KERNEL_SIZE);
    $display("  WEIGHT_WIDTH = %d", WEIGHT_WIDTH);
    $display("  INIT_FILE = %s", INIT_FILE);
    $display("");
    
    // Reset sequence
    #10;
    rst_n = 1;
    #10;
    
    // Test 1: Basic functionality test
    $display("=== Test 1: Basic Weight Reading ===");
    test_basic_reading();
    
    // Test 2: All filter-channel combinations
    $display("=== Test 2: All Filter-Channel Combinations ===");
    test_all_combinations();
    
    // Test 3: Read enable control
    $display("=== Test 3: Read Enable Control ===");
    test_read_enable_control();
    
    // Test 4: Reset functionality
    $display("=== Test 4: Reset Functionality ===");
    test_reset_functionality();
    
    // Test 5: Timing test
    $display("=== Test 5: Timing Test ===");
    test_timing();
    
    // Summary
    $display("");
    $display("=== Test Summary ===");
    $display("Total tests: %d", test_count);
    $display("Passed tests: %d", pass_count);
    if (pass_count == test_count) begin
        $display("ALL TESTS PASSED!");
    end else begin
        $display("SOME TESTS FAILED!");
    end
    
    #100;
    $finish;
end

// Task: Basic reading test
task test_basic_reading;
begin
    $display("Testing basic weight reading for filter 0, channel 0...");
    
    filter_idx = 0;
    channel_idx = 0;
    read_enable = 1;
    
    // Wait for weight_valid
    wait_for_valid();
    
    if (weight_valid) begin
        $display("✓ Weight reading successful");
        $display("  Flattened weights: %h", flattened_weight_out);
        pass_count = pass_count + 1;
    end else begin
        $display("✗ Weight reading failed - no valid signal");
    end
    test_count = test_count + 1;
    
    read_enable = 0;
    #20;
end
endtask

// Task: Test all filter-channel combinations
task test_all_combinations;
begin
    for (i = 0; i < NUM_FILTERS; i = i + 1) begin
        for (j = 0; j < INPUT_CHANNELS; j = j + 1) begin
            $display("Testing filter %d, channel %d...", i, j);
            
            filter_idx = i;
            channel_idx = j;
            read_enable = 1;
            
            wait_for_valid();
            
            if (weight_valid) begin
                $display("✓ Filter %d, Channel %d: %h", i, j, flattened_weight_out);
                pass_count = pass_count + 1;
            end else begin
                $display("✗ Filter %d, Channel %d: Failed", i, j);
            end
            test_count = test_count + 1;
            
            read_enable = 0;
            #20;
        end
    end
end
endtask

// Task: Test read enable control
task test_read_enable_control;
begin
    $display("Testing read enable control...");
    
    filter_idx = 1;
    channel_idx = 1;
    read_enable = 0;  // Keep disabled
    
    #100;  // Wait some time
    
    if (!weight_valid) begin
        $display("✓ Read enable control working - no output when disabled");
        pass_count = pass_count + 1;
    end else begin
        $display("✗ Read enable control failed - unexpected output");
    end
    test_count = test_count + 1;
    
    // Now enable and check
    read_enable = 1;
    wait_for_valid();
    
    if (weight_valid) begin
        $display("✓ Read enable control working - output when enabled");
        pass_count = pass_count + 1;
    end else begin
        $display("✗ Read enable control failed - no output when enabled");
    end
    test_count = test_count + 1;
    
    read_enable = 0;
    #20;
end
endtask

// Task: Test reset functionality
task test_reset_functionality;
begin
    $display("Testing reset functionality...");
    
    // Start a read operation
    filter_idx = 2;
    channel_idx = 2;
    read_enable = 1;
    
    #30;  // Let it start
    
    // Apply reset
    rst_n = 0;
    #20;
    rst_n = 1;
    #20;
    
    if (!weight_valid && flattened_weight_out == 0) begin
        $display("✓ Reset functionality working");
        pass_count = pass_count + 1;
    end else begin
        $display("✗ Reset functionality failed");
    end
    test_count = test_count + 1;
    
    read_enable = 0;
    #20;
end
endtask

// Task: Test timing
task test_timing;
    integer start_time, end_time, duration;
begin
    $display("Testing timing characteristics...");
    
    filter_idx = 0;
    channel_idx = 0;
    read_enable = 1;
    
    // Measure time to valid
    start_time = $time;
    
    wait_for_valid();
    
    end_time = $time;
    duration = end_time - start_time;
    
    $display("Time to valid: %d ns", duration);
    
    if (duration > 0 && duration < 1000) begin  // Reasonable time
        $display("✓ Timing test passed");
        pass_count = pass_count + 1;
    end else begin
        $display("✗ Timing test failed");
    end
    test_count = test_count + 1;
    
    read_enable = 0;
    #20;
end
endtask

// Task: Wait for weight_valid signal
task wait_for_valid;
    integer timeout;
begin
    timeout = 0;
    
    while (!weight_valid && timeout < 1000) begin
        #10;
        timeout = timeout + 10;
    end
    
    if (timeout >= 1000) begin
        $display("WARNING: Timeout waiting for weight_valid");
    end
end
endtask

// Monitor for debugging
always @(posedge clk) begin
    if (read_enable && weight_valid) begin
        $display("Time %t: Weight valid for filter %d, channel %d", 
                 $time, filter_idx, channel_idx);
    end
end

endmodule