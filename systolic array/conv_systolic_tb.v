`timescale 1ns / 1ps

module conv_systolic_tb();

    // 测试参数
    parameter DATA_WIDTH = 8;
    parameter KERNEL_SIZE = 3;
    parameter WEIGHT_WIDTH = 8;
    parameter OUTPUT_WIDTH = 32;
    parameter NUM_FILTERS = 2;
    
    // 测试信号
    reg clk;
    reg rst_n;
    
    // 卷积模块接口
    reg [KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] window_in;
    reg window_valid;
    reg [NUM_FILTERS*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] weights;
    reg weights_valid;
    reg [NUM_FILTERS*OUTPUT_WIDTH-1:0] bias;
    reg bias_enable;
    
    wire [NUM_FILTERS*OUTPUT_WIDTH-1:0] conv_out;
    wire conv_valid;
    
    // 实例化Systolic Array卷积模块
    conv_systolic #(
        .DATA_WIDTH(DATA_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .OUTPUT_WIDTH(OUTPUT_WIDTH),
        .NUM_FILTERS(NUM_FILTERS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .window_in(window_in),
        .window_valid(window_valid),
        .weights(weights),
        .weights_valid(weights_valid),
        .bias(bias),
        .bias_enable(bias_enable),
        .conv_out(conv_out),
        .conv_valid(conv_valid)
    );
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // 测试数据
    reg [DATA_WIDTH-1:0] test_window [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    reg [WEIGHT_WIDTH-1:0] test_weights [0:NUM_FILTERS-1][0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    reg [OUTPUT_WIDTH-1:0] test_bias [0:NUM_FILTERS-1];
    
    // 计数器和结果
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    reg signed [OUTPUT_WIDTH-1:0] expected_results [0:NUM_FILTERS-1];
    
    // 性能计数器
    integer start_time, end_time;
    integer total_cycles = 0;
    integer total_tests = 0;
    
    // 任务：初始化测试数据
    task init_test_data;
        integer f, i, j;
        begin
            // 初始化测试窗口 (3x3)
            test_window[0][0] = 8'd1;  test_window[0][1] = 8'd2;  test_window[0][2] = 8'd3;
            test_window[1][0] = 8'd4;  test_window[1][1] = 8'd5;  test_window[1][2] = 8'd6;
            test_window[2][0] = 8'd7;  test_window[2][1] = 8'd8;  test_window[2][2] = 8'd9;
            
            // 初始化卷积核权重
            // Filter 0: 边缘检测核
            test_weights[0][0][0] = 8'sd0;   test_weights[0][0][1] = 8'sd1;   test_weights[0][0][2] = 8'sd0;
            test_weights[0][1][0] = 8'sd1;   test_weights[0][1][1] = 8'sd254; test_weights[0][1][2] = 8'sd1;  // -4 in 8-bit signed
            test_weights[0][2][0] = 8'sd0;   test_weights[0][2][1] = 8'sd1;   test_weights[0][2][2] = 8'sd0;
            
            // Filter 1: 均值滤波核
            for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
                for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
                    test_weights[1][i][j] = 8'sd1;  // 所有权重为1
                end
            end
            
            // 初始化偏置
            test_bias[0] = 32'sd10;
            test_bias[1] = 32'sd0;
        end
    endtask
    
    // 任务：打包窗口数据
    task pack_window_data;
        integer i, j;
        begin
            for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
                for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
                    window_in[(KERNEL_SIZE*KERNEL_SIZE-(i*KERNEL_SIZE+j))*DATA_WIDTH-1 -: DATA_WIDTH] = test_window[i][j];
                end
            end
        end
    endtask
    
    // 任务：打包权重数据
    task pack_weights_data;
        integer f, i, j;
        begin
            for(f = 0; f < NUM_FILTERS; f = f + 1) begin
                for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
                    for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
                        weights[(f*KERNEL_SIZE*KERNEL_SIZE + i*KERNEL_SIZE + j + 1)*WEIGHT_WIDTH-1 -: WEIGHT_WIDTH] = test_weights[f][i][j];
                    end
                end
            end
        end
    endtask
    
    // 任务：打包偏置数据
    task pack_bias_data;
        integer f;
        begin
            for(f = 0; f < NUM_FILTERS; f = f + 1) begin
                bias[(f+1)*OUTPUT_WIDTH-1 -: OUTPUT_WIDTH] = test_bias[f];
            end
        end
    endtask
    
    // 任务：计算期望结果
    task calc_expected_result;
        integer f, i, j;
        reg signed [OUTPUT_WIDTH-1:0] sum;
        begin
            for(f = 0; f < NUM_FILTERS; f = f + 1) begin
                sum = 0;
                for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
                    for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
                        sum = sum + ($signed(test_window[i][j]) * $signed(test_weights[f][i][j]));
                    end
                end
                if(bias_enable) begin
                    sum = sum + $signed(test_bias[f]);
                end
                expected_results[f] = sum;
            end
        end
    endtask
    
    // 任务：验证结果
    task verify_result;
        reg signed [OUTPUT_WIDTH-1:0] actual [0:NUM_FILTERS-1];
        integer f;
        reg test_pass;
        begin
            test_pass = 1;
            
            // 解包实际结果
            for(f = 0; f < NUM_FILTERS; f = f + 1) begin
                actual[f] = conv_out[(f+1)*OUTPUT_WIDTH-1 -: OUTPUT_WIDTH];
            end
            
            // 比较结果
            for(f = 0; f < NUM_FILTERS; f = f + 1) begin
                if(actual[f] !== expected_results[f]) begin
                    test_pass = 0;
                    $display("FAIL: Filter %0d - Expected: %0d, Got: %0d", f, expected_results[f], actual[f]);
                end else begin
                    $display("PASS: Filter %0d - Result: %0d", f, actual[f]);
                end
            end
            
            if(test_pass) begin
                pass_count = pass_count + 1;
                $display("Test %0d: PASSED", test_count);
            end else begin
                fail_count = fail_count + 1;
                $display("Test %0d: FAILED", test_count);
            end
        end
    endtask
    
    // 任务：性能测试
    task performance_test;
        integer i;
        begin
            $display("\n--- Performance Test: Systolic Array vs Traditional ---");
            
            start_time = $time;
            
            // 连续处理100个窗口
            for(i = 0; i < 100; i = i + 1) begin
                // 修改窗口数据
                test_window[1][1] = test_window[1][1] + 1;
                pack_window_data();
                
                @(posedge clk);
                window_valid = 1;
                @(posedge clk);
                window_valid = 0;
                
                wait(conv_valid);
                @(posedge clk);
            end
            
            end_time = $time;
            total_cycles = (end_time - start_time) / 10; // 10ns per cycle
            total_tests = 100;
            
            $display("Performance Results:");
            $display("  Total cycles: %0d", total_cycles);
            $display("  Total tests: %0d", total_tests);
            $display("  Cycles per convolution: %0d", total_cycles / total_tests);
            $display("  Throughput: %0.2f conv/cycle", 1.0 * total_tests / total_cycles);
        end
    endtask
    
    // 主测试流程
    initial begin
        $display("========================================");
        $display("Systolic Array Convolution Test Starting");
        $display("KERNEL_SIZE: %0d, NUM_FILTERS: %0d", KERNEL_SIZE, NUM_FILTERS);
        $display("Architecture: Systolic Array Optimized");
        $display("========================================");
        
        // 初始化
        rst_n = 0;
        window_in = 0;
        window_valid = 0;
        weights = 0;
        weights_valid = 0;
        bias = 0;
        bias_enable = 0;
        
        // 复位
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);
        
        // 初始化测试数据
        init_test_data();
        pack_weights_data();
        pack_bias_data();
        
        $display("Test Window:");
        $display("[%3d %3d %3d]", test_window[0][0], test_window[0][1], test_window[0][2]);
        $display("[%3d %3d %3d]", test_window[1][0], test_window[1][1], test_window[1][2]);
        $display("[%3d %3d %3d]", test_window[2][0], test_window[2][1], test_window[2][2]);
        $display("");
        
        // 设置权重有效
        weights_valid = 1;
        
        // 测试1：无偏置卷积
        test_count = test_count + 1;
        $display("--- Test %0d: Systolic Array Convolution without bias ---", test_count);
        bias_enable = 0;
        
        pack_window_data();
        @(posedge clk);
        window_valid = 1;
        @(posedge clk);
        window_valid = 0;
        
        // 等待结果
        wait(conv_valid);
        @(posedge clk);
        
        begin
            calc_expected_result();
            verify_result();
        end
        
        repeat(5) @(posedge clk);
        
        // 测试2：带偏置卷积
        test_count = test_count + 1;
        $display("\n--- Test %0d: Systolic Array Convolution with bias ---", test_count);
        bias_enable = 1;
        
        pack_window_data();
        @(posedge clk);
        window_valid = 1;
        @(posedge clk);
        window_valid = 0;
        
        // 等待结果
        wait(conv_valid);
        @(posedge clk);
        
        begin
            calc_expected_result();
            verify_result();
        end
        
        repeat(5) @(posedge clk);
        
        // 性能测试
        bias_enable = 0;
        performance_test();
        
        // 最终结果
        $display("\n========================================");
        $display("Test Summary:");
        $display("Total Tests: %0d", test_count);
        $display("Passed: %0d", pass_count);
        $display("Failed: %0d", fail_count);
        
        if(fail_count == 0) begin
            $display("ALL TESTS PASSED!");
            $display("Systolic Array optimization successful!");
        end else begin
            $display("SOME TESTS FAILED!");
        end
        $display("========================================");
        
        $finish;
    end
    
    // 监控输出
    always @(posedge clk) begin
        if(conv_valid) begin
            $display("Time %0t: Systolic convolution result available", $time);
            $display("  Filter 0 output: %0d", conv_out[OUTPUT_WIDTH-1:0]);
            $display("  Filter 1 output: %0d", conv_out[2*OUTPUT_WIDTH-1:OUTPUT_WIDTH]);
        end
    end
    
    // 波形文件
    initial begin
        $dumpfile("conv_systolic_tb.vcd");
        $dumpvars(0, conv_systolic_tb);
        
        // 超时保护
        #50000;
        $display("ERROR: Test timeout!");
        $finish;
    end

endmodule 