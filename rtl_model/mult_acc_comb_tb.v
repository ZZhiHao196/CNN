`timescale 1ns / 1ps

module mult_acc_comb_tb;

parameter DATA_WIDTH = 8;
parameter KERNEL_SIZE = 3;
parameter IN_CHANNEL = 3;
parameter WEIGHT_WIDTH = 8;
parameter ACC_WIDTH = 2*DATA_WIDTH + 4;

reg window_valid;
reg [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] multi_channel_window_in;
reg weight_valid;
reg [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] multi_channel_weight_in;

wire [DATA_WIDTH-1:0] conv_out;
wire conv_valid;

// Localparams for saturation (UNSIGNED) - Assuming previous corrections for unsigned are intended
localparam MAX_UNSIGNED_OUT_VAL = (1 << DATA_WIDTH) - 1;

// Example: Test 2 raw sum for unsigned context
localparam EXPECTED_SUM_TEST2_UNSIGNED_RAW = 3 * 9 * 2 * 3; // 162
localparam EXPECTED_CONV_OUT_TEST2_UNSIGNED_SAT = (EXPECTED_SUM_TEST2_UNSIGNED_RAW > MAX_UNSIGNED_OUT_VAL) ? MAX_UNSIGNED_OUT_VAL : EXPECTED_SUM_TEST2_UNSIGNED_RAW;
localparam MAX_ELEMENT_VAL_TB = (1 << DATA_WIDTH) -1;
localparam MAX_WEIGHT_ELEMENT_VAL_TB = (1 << WEIGHT_WIDTH) -1;

mult_acc_comb #(
    .DATA_WIDTH(DATA_WIDTH),
    .KERNEL_SIZE(KERNEL_SIZE),
    .IN_CHANNEL(IN_CHANNEL),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
) dut (
    .window_valid(window_valid),
    .multi_channel_window_in(multi_channel_window_in),
    .weight_valid(weight_valid),
    .multi_channel_weight_in(multi_channel_weight_in),
    .conv_out(conv_out),
    .conv_valid(conv_valid)
);

reg all_tests_passed_flag; // Renamed for clarity
integer test_id_counter;
integer num_errors;

// Task to check results and display Expected/Actual for all
task check_and_report;
    input [DATA_WIDTH-1:0] expected_out_val;
    input expected_valid_val;
    // Test description is displayed before calling this task
    begin
        test_id_counter = test_id_counter + 1;
        
        // Always display Expected and Actual
        $display("    Expected: conv_valid=%b, conv_out=%d", expected_valid_val, expected_out_val);
        $display("    Actual:   conv_valid=%b, conv_out=%d", conv_valid, conv_out);

        if (conv_valid === expected_valid_val &&
            ( (expected_valid_val === 1'b0) ? (conv_out === {DATA_WIDTH{1'b0}}) : (conv_out === expected_out_val) ) ) begin
            $display("    Test ID %0d: Status: PASSED", test_id_counter);
        end else begin
            $display("    Test ID %0d: Status: FAILED", test_id_counter);
            all_tests_passed_flag = 1'b0;
            num_errors = num_errors + 1;
        end
        $display("--------------------------------------------------");
    end
endtask

initial begin
    $display("=== Comprehensive UNSIGNED Combinational MultAcc Test ===");
    all_tests_passed_flag = 1'b1; 
    test_id_counter = 0;
    num_errors = 0;
    
    // Initialize
    window_valid = 0;
    weight_valid = 0;
    multi_channel_window_in = 0;
    multi_channel_weight_in = 0;
    
    #10;
    
    // Test 1
    $display("Test Description: Simple Positive Values (1*1, sum 27)");
    multi_channel_window_in = {27{8'd1}}; 
    multi_channel_weight_in = {27{8'd1}}; 
    window_valid = 1;
    weight_valid = 1;
    #1; 
    check_and_report(27, 1'b1);
    
    #10;
    
    // Test 2
    $display("Test Description: Positive Values with Saturation (2*3, raw %0d, sat %0d)", EXPECTED_SUM_TEST2_UNSIGNED_RAW, EXPECTED_CONV_OUT_TEST2_UNSIGNED_SAT);
    multi_channel_window_in = {27{8'd2}};
    multi_channel_weight_in = {27{8'd3}};
    #1; 
    check_and_report(EXPECTED_CONV_OUT_TEST2_UNSIGNED_SAT, 1'b1);
        
    #10;
    
    // Test 3
    $display("Test Description: Invalid Inputs (both valid_n low)");
    window_valid = 0;
    weight_valid = 0;
    #1;
    check_and_report(0, 1'b0); 
    
    #10;

    // Test 4
    $display("Test Description: Zero Window Data, Non-zero Weights");
    window_valid = 1;
    weight_valid = 1;
    multi_channel_window_in = {27{8'd0}}; 
    multi_channel_weight_in = {27{8'd5}}; 
    #1;
    check_and_report(0, 1'b1);

    #10;

    // Test 5
    $display("Test Description: Non-zero Window, Zero Weight Data");
    multi_channel_window_in = {27{8'd5}}; 
    multi_channel_weight_in = {27{8'd0}}; 
    #1;
    check_and_report(0, 1'b1);

    #10;

    // Test 6
    $display("Test Description: All Zero Inputs");
    multi_channel_window_in = {27{8'd0}}; 
    multi_channel_weight_in = {27{8'd0}}; 
    #1;
    check_and_report(0, 1'b1);

    #10;
    
    // Test 7
    $display("Test Description: Saturation to MAX_UNSIGNED_OUT_VAL (%0d)", MAX_UNSIGNED_OUT_VAL);
    multi_channel_window_in = {27{8'd5}}; 
    multi_channel_weight_in = {27{8'd5}}; 
    #1;
    check_and_report(MAX_UNSIGNED_OUT_VAL, 1'b1);

    #10;
    
    // Test 8
    $display("Test Description: Max Val Inputs (Win=%d, Wgt=%d), saturate to %d", MAX_ELEMENT_VAL_TB, MAX_WEIGHT_ELEMENT_VAL_TB, MAX_UNSIGNED_OUT_VAL);
    multi_channel_window_in = {27{{DATA_WIDTH{1'b1}}}};
    multi_channel_weight_in = {27{{WEIGHT_WIDTH{1'b1}}}};
    #1;
    check_and_report(MAX_UNSIGNED_OUT_VAL, 1'b1);

    #10;

    // Test 9: Window valid toggles
    $display("--- Test Sequence 9: Window Valid Toggles (base inputs 1*1, sum 27) ---");
    multi_channel_window_in = {27{8'd1}};
    multi_channel_weight_in = {27{8'd1}};
    weight_valid = 1; 
    
    $display("  Sub-Test Description: WinValid=1 (Start)");
    window_valid = 1; #1; check_and_report(27, 1'b1);
    $display("  Sub-Test Description: WinValid=0");
    window_valid = 0; #1; check_and_report(0,  1'b0);
    $display("  Sub-Test Description: WinValid=1 (End)");
    window_valid = 1; #1; check_and_report(27, 1'b1);

    #10;

    // Test 10: Weight valid toggles
    $display("--- Test Sequence 10: Weight Valid Toggles (base inputs 1*1, sum 27) ---");
    window_valid = 1; 
    // inputs are still 1s
    
    $display("  Sub-Test Description: WeightValid=1 (Start)");
    weight_valid = 1; #1; check_and_report(27, 1'b1);
    $display("  Sub-Test Description: WeightValid=0");
    weight_valid = 0; #1; check_and_report(0,  1'b0);
    $display("  Sub-Test Description: WeightValid=1 (End)");
    weight_valid = 1; #1; check_and_report(27, 1'b1);
    
    #10;

    // Final Summary
    $display("==================================================");
    if (all_tests_passed_flag) begin
        $display("FINAL STATUS: SUCCESS! All %0d UNSIGNED Combinational MultAcc tests passed!", test_id_counter);
    end else begin
        $display("FINAL STATUS: FAILED. %0d out of %0d UNSIGNED Combinational MultAcc tests did not pass.", num_errors, test_id_counter);
    end
    $display("==================================================");
    
    $finish;
end

endmodule 