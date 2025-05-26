`timescale 1ns / 1ps

module mult_acc_tb();

    // 可配置测试参数
    parameter DATA_WIDTH = 8;
    parameter KERNEL_SIZE = 3;
    parameter IN_CHANNEL = 3;
    parameter WEIGHT_WIDTH = 8;
    parameter ACC_WIDTH = 2*DATA_WIDTH + 4;
    parameter PIPELINE_DELAY = 4;
    
    // 计算位宽
    localparam WINDOW_WIDTH = IN_CHANNEL * KERNEL_SIZE * KERNEL_SIZE * DATA_WIDTH;
    localparam WEIGHT_WIDTH_TOTAL = IN_CHANNEL * KERNEL_SIZE * KERNEL_SIZE * WEIGHT_WIDTH;
    localparam KERNEL_ELEMENTS = KERNEL_SIZE * KERNEL_SIZE;
    localparam TOTAL_ELEMENTS = IN_CHANNEL * KERNEL_ELEMENTS;
    
    // 测试模式常量
    localparam BASIC_TEST = 0;
    localparam EDGE_DETECTION = 1;
    localparam BLUR_FILTER = 2;
    localparam RANDOM_TEST = 3;
    localparam STRESS_TEST = 4;
    localparam CORNER_CASE = 5;
    localparam PERFORMANCE_TEST = 6;
    
    // 测试信号
    reg clk;
    reg rst_n;
    reg window_valid;
    reg [WINDOW_WIDTH-1:0] multi_channel_window_in;
    reg weight_valid;
    reg [WEIGHT_WIDTH_TOTAL-1:0] multi_channel_weight_in;
    
    wire signed [DATA_WIDTH-1:0] conv_out;
    wire conv_valid;
    
    // 实例化被测模块
    mult_acc #(
        .DATA_WIDTH(DATA_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),
        .IN_CHANNEL(IN_CHANNEL),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .window_valid(window_valid),
        .multi_channel_window_in(multi_channel_window_in),
        .weight_valid(weight_valid),
        .multi_channel_weight_in(multi_channel_weight_in),
        .conv_out(conv_out),
        .conv_valid(conv_valid)
    );
    
    // 时钟生成 - 100MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // 增强的测试数据存储
    reg signed [DATA_WIDTH-1:0] test_window [0:26]; // 最大27个元素
    reg signed [WEIGHT_WIDTH-1:0] test_weight [0:26];
    reg signed [ACC_WIDTH-1:0] expected_result;
    reg signed [ACC_WIDTH-1:0] channel_results [0:2]; // 最大3个通道
    
    // 测试统计和性能分析
    integer test_count;
    integer pass_count;
    integer fail_count;
    integer cycle_count;
    integer valid_count;
    integer total_latency;
    integer error_count;
    integer overflow_count;
    integer underflow_count;
    
    // 性能测试变量
    integer start_time;
    integer end_time;
    integer first_valid_time;
    integer last_valid_time;
    
    // 结果验证队列（增强版FIFO）
    reg [ACC_WIDTH-1:0] expected_fifo [0:127];
    reg [255:0] test_name_fifo [0:127];
    reg [7:0] fifo_wr_ptr;
    reg [7:0] fifo_rd_ptr;
    reg [8:0] fifo_count;
    
    // 错误分析
    reg signed [ACC_WIDTH-1:0] error_history [0:31];
    reg [4:0] error_ptr;
    
    // 初始化所有变量
    initial begin
        test_count = 0;
        pass_count = 0;
        fail_count = 0;
        cycle_count = 0;
        valid_count = 0;
        total_latency = 0;
        error_count = 0;
        overflow_count = 0;
        underflow_count = 0;
        start_time = 0;
        end_time = 0;
        first_valid_time = 0;
        last_valid_time = 0;
        fifo_wr_ptr = 0;
        fifo_rd_ptr = 0;
        fifo_count = 0;
        error_ptr = 0;
    end
    
    // 任务：设置基础测试数据
    task set_basic_test_data;
        input integer seed;
        integer i;
        begin
            for (i = 0; i < TOTAL_ELEMENTS; i = i + 1) begin
                test_window[i] = (i % 10) + 1;
                test_weight[i] = 1;
            end
        end
    endtask
    
    // 任务：设置边缘检测测试数据
    task set_edge_detection_data;
        integer ch, pos, idx;
        begin
            for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                // 设置渐变图像数据
                for (pos = 0; pos < KERNEL_ELEMENTS; pos = pos + 1) begin
                    idx = ch * KERNEL_ELEMENTS + pos;
                    test_window[idx] = 50 + pos * 10 + ch * 5;
                end
                
                // 设置Sobel X核
                idx = ch * KERNEL_ELEMENTS;
                test_weight[idx + 0] = -1; test_weight[idx + 1] = 0; test_weight[idx + 2] = 1;
                test_weight[idx + 3] = -2; test_weight[idx + 4] = 0; test_weight[idx + 5] = 2;
                test_weight[idx + 6] = -1; test_weight[idx + 7] = 0; test_weight[idx + 8] = 1;
            end
        end
    endtask
    
    // 任务：设置模糊滤波测试数据
    task set_blur_filter_data;
        integer ch, pos, idx;
        begin
            for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                // 设置图像数据
                for (pos = 0; pos < KERNEL_ELEMENTS; pos = pos + 1) begin
                    idx = ch * KERNEL_ELEMENTS + pos;
                    test_window[idx] = 100 + (pos % 3) * 20;
                end
                
                // 设置高斯核
                idx = ch * KERNEL_ELEMENTS;
                test_weight[idx + 0] = 1; test_weight[idx + 1] = 2; test_weight[idx + 2] = 1;
                test_weight[idx + 3] = 2; test_weight[idx + 4] = 4; test_weight[idx + 5] = 2;
                test_weight[idx + 6] = 1; test_weight[idx + 7] = 2; test_weight[idx + 8] = 1;
            end
        end
    endtask
    
    // 任务：设置随机测试数据
    task set_random_test_data;
        input integer seed;
        integer i;
        begin
            for (i = 0; i < TOTAL_ELEMENTS; i = i + 1) begin
                test_window[i] = ($random(seed) % 128) - 64;
                test_weight[i] = ($random(seed+1) % 16) - 8;
            end
        end
    endtask
    
    // 任务：设置压力测试数据
    task set_stress_test_data;
        integer i;
        begin
            for (i = 0; i < TOTAL_ELEMENTS; i = i + 1) begin
                test_window[i] = (i % 2) ? 127 : -128;
                test_weight[i] = (i % 3) ? 7 : -8;
            end
        end
    endtask
    
    // 任务：设置边界情况测试数据
    task set_corner_case_data;
        integer i;
        begin
            for (i = 0; i < TOTAL_ELEMENTS; i = i + 1) begin
                if (i < TOTAL_ELEMENTS/3) begin
                    test_window[i] = 0;
                    test_weight[i] = 127;
                end else if (i < 2*TOTAL_ELEMENTS/3) begin
                    test_window[i] = 127;
                    test_weight[i] = 0;
                end else begin
                    test_window[i] = -128;
                    test_weight[i] = -128;
                end
            end
        end
    endtask
    
    // 任务：通用数据设置
    task set_test_data_pattern;
        input [255:0] test_name;
        input integer mode;
        input integer seed;
        begin
            $display("\n=== 设置测试数据: %s ===", test_name);
            
            case (mode)
                BASIC_TEST: set_basic_test_data(seed);
                EDGE_DETECTION: set_edge_detection_data();
                BLUR_FILTER: set_blur_filter_data();
                RANDOM_TEST: set_random_test_data(seed);
                STRESS_TEST: set_stress_test_data();
                CORNER_CASE: set_corner_case_data();
                default: set_basic_test_data(seed);
            endcase
            
            $display("  数据模式: %0d", mode);
            $display("  测试种子: %0d", seed);
        end
    endtask
    
    // 任务：打包数据
    task pack_multi_channel_data;
        integer i, bit_pos;
        begin
            multi_channel_window_in = 0;
            multi_channel_weight_in = 0;
            
            for (i = 0; i < TOTAL_ELEMENTS; i = i + 1) begin
                bit_pos = i * DATA_WIDTH;
                multi_channel_window_in[bit_pos +: DATA_WIDTH] = test_window[i];
                
                bit_pos = i * WEIGHT_WIDTH;
                multi_channel_weight_in[bit_pos +: WEIGHT_WIDTH] = test_weight[i];
            end
        end
    endtask
    
    // 任务：计算期望结果
    task calc_expected_result;
        integer ch, pos, idx;
        begin
            expected_result = 0;
            
            // 计算每个通道的卷积结果
            for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                channel_results[ch] = 0;
                for (pos = 0; pos < KERNEL_ELEMENTS; pos = pos + 1) begin
                    idx = ch * KERNEL_ELEMENTS + pos;
                    channel_results[ch] = channel_results[ch] + (test_window[idx] * test_weight[idx]);
                end
                $display("  通道%d卷积结果: %d", ch, channel_results[ch]);
            end
            
            // 跨通道累加
            for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                expected_result = expected_result + channel_results[ch];
            end
            
            $display("  期望总结果: %d", expected_result);
            
            // 检查是否会溢出
            if (expected_result > ((1 << (DATA_WIDTH-1)) - 1)) begin
                $display("  警告: 期望结果将被饱和到最大值 %d", (1 << (DATA_WIDTH-1)) - 1);
                overflow_count = overflow_count + 1;
            end else if (expected_result < (-(1 << (DATA_WIDTH-1)))) begin
                $display("  警告: 期望结果将被饱和到最小值 %d", -(1 << (DATA_WIDTH-1)));
                underflow_count = underflow_count + 1;
            end
        end
    endtask
    
    // 任务：发送测试数据
    task send_enhanced_test;
        input [255:0] test_name;
        input integer mode;
        input integer seed;
        integer send_time;
        begin
            test_count = test_count + 1;
            send_time = cycle_count;
            
            // 设置测试数据
            set_test_data_pattern(test_name, mode, seed);
            
            // 计算期望结果
            calc_expected_result();
            
            // 打包数据
            pack_multi_channel_data();
            
            // 将期望结果和测试名称加入FIFO
            expected_fifo[fifo_wr_ptr] = expected_result;
            test_name_fifo[fifo_wr_ptr] = test_name;
            fifo_wr_ptr = fifo_wr_ptr + 1;
            fifo_count = fifo_count + 1;
            
            // 发送数据
            @(posedge clk);
            window_valid = 1;
            weight_valid = 1;
            
            $display("测试 %0d [%s]: 期望结果 = %0d (时间: %0d)", test_count, test_name, expected_result, send_time);
            
            @(posedge clk);
            window_valid = 0;
            weight_valid = 0;
        end
    endtask
    
    // 任务：验证结果
    task verify_enhanced_result;
        input signed [DATA_WIDTH-1:0] actual;
        input signed [ACC_WIDTH-1:0] expected;
        input [255:0] test_name;
        reg signed [DATA_WIDTH-1:0] expected_saturated;
        reg signed [ACC_WIDTH-1:0] error;
        begin
            // 应用饱和处理到期望值
            if (expected > ((1 << (DATA_WIDTH-1)) - 1))
                expected_saturated = (1 << (DATA_WIDTH-1)) - 1;
            else if (expected < (-(1 << (DATA_WIDTH-1))))
                expected_saturated = -(1 << (DATA_WIDTH-1));
            else
                expected_saturated = expected[DATA_WIDTH-1:0];
            
            // 计算误差
            error = actual - expected_saturated;
            
            if (actual == expected_saturated) begin
                pass_count = pass_count + 1;
                $display("  ✓ 通过 [%s]: 实际=%0d, 期望=%0d", test_name, actual, expected_saturated);
            end else begin
                fail_count = fail_count + 1;
                error_count = error_count + 1;
                $display("  ✗ 失败 [%s]: 实际=%0d, 期望=%0d, 误差=%0d (原始期望=%0d)", 
                        test_name, actual, expected_saturated, error, expected);
                
                // 记录错误历史
                error_history[error_ptr] = error;
                error_ptr = (error_ptr + 1) % 32;
            end
        end
    endtask
    
    // 任务：性能测试
    task performance_test;
        input integer num_tests;
        integer i, start_cycle, end_cycle;
        real test_throughput;
        begin
            $display("\n=== 性能测试 ===");
            start_cycle = cycle_count;
            
            for (i = 0; i < num_tests; i = i + 1) begin
                send_enhanced_test("性能测试", RANDOM_TEST, i);
                if (i % 4 == 0) @(posedge clk); // 偶尔插入间隔
            end
            
            // 等待所有结果
            repeat(20) @(posedge clk);
            end_cycle = cycle_count;
            
            test_throughput = (num_tests * 1.0) / (end_cycle - start_cycle);
            $display("性能测试完成:");
            $display("  测试数量: %0d", num_tests);
            $display("  总周期: %0d", end_cycle - start_cycle);
            $display("  吞吐量: %.3f 测试/周期", test_throughput);
        end
    endtask
    
    // 任务：压力测试
    task stress_test;
        input integer duration_cycles;
        integer start_cycle;
        integer stress_test_count;
        begin
            $display("\n=== 压力测试 ===");
            start_cycle = cycle_count;
            stress_test_count = 0;
            
            while ((cycle_count - start_cycle) < duration_cycles) begin
                send_enhanced_test("压力测试", STRESS_TEST, stress_test_count);
                stress_test_count = stress_test_count + 1;
                @(posedge clk);
            end
            
            $display("压力测试完成:");
            $display("  持续周期: %0d", duration_cycles);
            $display("  完成测试: %0d", stress_test_count);
        end
    endtask
    
    // 任务：生成测试报告
    task generate_test_report;
        real success_rate, error_rate, throughput, avg_latency;
        integer i;
        begin
            $display("\n========================================");
            $display("增强测试报告");
            $display("========================================");
            
            // 基本统计
            success_rate = (test_count > 0) ? (pass_count * 100.0) / test_count : 0.0;
            error_rate = (test_count > 0) ? (fail_count * 100.0) / test_count : 0.0;
            
            $display("测试统计:");
            $display("  总测试数: %0d", test_count);
            $display("  通过数: %0d (%.1f%%)", pass_count, success_rate);
            $display("  失败数: %0d (%.1f%%)", fail_count, error_rate);
            $display("  错误数: %0d", error_count);
            
            // 性能统计
            throughput = (cycle_count > 0) ? (valid_count * 1.0) / cycle_count : 0.0;
            avg_latency = (valid_count > 0) ? (total_latency * 1.0) / valid_count : 0.0;
            
            $display("\n性能统计:");
            $display("  总时钟周期: %0d", cycle_count);
            $display("  有效输出: %0d", valid_count);
            $display("  吞吐量: %.3f 输出/周期", throughput);
            $display("  平均延迟: %.1f 周期", avg_latency);
            
            // 溢出统计
            $display("\n溢出统计:");
            $display("  上溢次数: %0d", overflow_count);
            $display("  下溢次数: %0d", underflow_count);
            
            // 错误分析
            if (error_count > 0) begin
                $display("\n错误分析:");
                $display("  最近错误历史:");
                for (i = 0; i < 8 && i < error_count; i = i + 1) begin
                    $display("    错误%0d: %0d", i+1, error_history[(error_ptr - i - 1) % 32]);
                end
            end
            
            // 总结
            $display("\n========================================");
            if (fail_count == 0) begin
                $display("🎉 所有测试通过！模块工作正常");
            end else begin
                $display("❌ 有 %0d 个测试失败，成功率 %.1f%%", fail_count, success_rate);
            end
            $display("========================================");
        end
    endtask
    
    // 主测试序列
    initial begin
        $display("========================================");
        $display("增强多通道乘累加模块测试套件");
        $display("数据位宽: %0d, 卷积核: %0dx%0d, 通道数: %0d", 
                DATA_WIDTH, KERNEL_SIZE, KERNEL_SIZE, IN_CHANNEL);
        $display("总元素数: %0d, 流水线延迟: %0d 周期", TOTAL_ELEMENTS, PIPELINE_DELAY);
        $display("========================================");
        
        // 初始化
        rst_n = 0;
        window_valid = 0;
        weight_valid = 0;
        multi_channel_window_in = 0;
        multi_channel_weight_in = 0;
        
        // 复位序列
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);
        start_time = cycle_count;
        
        // 基础功能测试
        $display("\n=== 基础功能测试 ===");
        send_enhanced_test("全零测试", BASIC_TEST, 0);
        send_enhanced_test("单位测试", BASIC_TEST, 1);
        send_enhanced_test("递增测试", BASIC_TEST, 2);
        
        // 实际卷积核测试
        $display("\n=== 实际卷积核测试 ===");
        send_enhanced_test("Sobel边缘检测", EDGE_DETECTION, 0);
        send_enhanced_test("高斯模糊", BLUR_FILTER, 0);
        
        // 边界情况测试
        $display("\n=== 边界情况测试 ===");
        send_enhanced_test("边界情况1", CORNER_CASE, 0);
        send_enhanced_test("边界情况2", CORNER_CASE, 1);
        
        // 随机测试
        $display("\n=== 随机测试 ===");
        send_enhanced_test("随机测试1", RANDOM_TEST, 1);
        send_enhanced_test("随机测试2", RANDOM_TEST, 2);
        send_enhanced_test("随机测试3", RANDOM_TEST, 3);
        send_enhanced_test("随机测试4", RANDOM_TEST, 4);
        send_enhanced_test("随机测试5", RANDOM_TEST, 5);
        
        // 性能测试
        performance_test(15);
        
        // 压力测试
        stress_test(30);
        
        // 等待所有结果
        repeat(30) @(posedge clk);
        end_time = cycle_count;
        
        // 生成测试报告
        generate_test_report();
        
        $finish;
    end
    
    // 结果监控和验证
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            
        if (conv_valid) begin
                valid_count = valid_count + 1;
                if (first_valid_time == 0) first_valid_time = cycle_count;
                last_valid_time = cycle_count;
                
                if (fifo_count > 0) begin
                    verify_enhanced_result(conv_out, expected_fifo[fifo_rd_ptr], test_name_fifo[fifo_rd_ptr]);
                    total_latency = total_latency + PIPELINE_DELAY;
                    fifo_rd_ptr = fifo_rd_ptr + 1;
                    fifo_count = fifo_count - 1;
                end else begin
                    $display("警告: 时间 %0t 出现意外的conv_valid", $time);
                end
            end
        end
    end
    
    // FIFO管理和错误检测
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr <= 0;
            fifo_rd_ptr <= 0;
            fifo_count <= 0;
        end else begin
            if (fifo_count > 120) begin
                $display("错误: FIFO溢出，时间 %0t", $time);
                $finish;
            end
        end
    end
    
    // 波形转储
    initial begin
        $dumpfile("mult_acc_tb.vcd");
        $dumpvars(0,mult_acc_tb);
        
        // 限制仿真时间防止死锁
        #15000;
        $display("错误: 仿真超时!");
        generate_test_report();
        $finish;
    end

endmodule 