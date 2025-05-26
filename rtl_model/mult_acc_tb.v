`timescale 1ns / 1ps

module mult_acc_tb();

    // 测试参数
    parameter DATA_WIDTH = 8;
    parameter KERNEL_SIZE = 3;
    parameter ACC_WIDTH = 2*DATA_WIDTH + 4;
    parameter PIPELINE_DELAY = 4; // 流水线延迟
    
    // 测试信号
    reg clk;
    reg rst_n;
    reg window_valid;
    reg [DATA_WIDTH*KERNEL_SIZE*KERNEL_SIZE-1:0] window_in;
    reg weight_valid;
    reg [DATA_WIDTH*KERNEL_SIZE*KERNEL_SIZE-1:0] weight_in;
    
    wire [2*DATA_WIDTH-1:0] conv_out;
    wire conv_valid;
    
    // 实例化被测模块
    mult_acc #(
        .DATA_WIDTH(DATA_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .window_valid(window_valid),
        .window_in(window_in),
        .weight_valid(weight_valid),
        .weight_in(weight_in),
        .conv_out(conv_out),
        .conv_valid(conv_valid)
    );
    
    // 时钟生成 - 100MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // 测试数据存储
    reg signed [DATA_WIDTH-1:0] test_window [0:8];
    reg signed [DATA_WIDTH-1:0] test_weight [0:8];
    reg signed [2*DATA_WIDTH-1:0] expected_result;
    
    // 测试统计
    integer test_count = 0;
    integer pass_count = 0;
    integer fail_count = 0;
    integer cycle_count = 0;
    integer valid_count = 0;
    
    // 结果验证队列（简单FIFO）
    reg [2*DATA_WIDTH-1:0] expected_fifo [0:31];
    reg [4:0] fifo_wr_ptr = 0;
    reg [4:0] fifo_rd_ptr = 0;
    reg [5:0] fifo_count = 0;
    
    // 任务：打包数据到输入端口
    task pack_data;
        integer i;
        begin
            window_in = 0;
            weight_in = 0;
            for (i = 0; i < 9; i = i + 1) begin
                window_in = window_in | (test_window[i] << (i * DATA_WIDTH));
                weight_in = weight_in | (test_weight[i] << (i * DATA_WIDTH));
            end
        end
    endtask
    
    // 任务：计算期望结果
    task calc_expected;
        integer i;
        begin
            expected_result = 0;
            for (i = 0; i < 9; i = i + 1) begin
                expected_result = expected_result + (test_window[i] * test_weight[i]);
            end
        end
    endtask
    
    // 任务：设置测试数据
    task set_test_data;
        input [71:0] window_data; // 9*8 = 72 bits
        input [71:0] weight_data;
        integer i;
        begin
            for (i = 0; i < 9; i = i + 1) begin
                test_window[i] = window_data[(i+1)*8-1 -: 8];
                test_weight[i] = weight_data[(i+1)*8-1 -: 8];
            end
        end
    endtask
    
    // 任务：发送测试数据
    task send_test;
        input [71:0] window_data;
        input [71:0] weight_data;
        input [255:0] test_name; // 测试名称
        begin
            test_count = test_count + 1;
            
            // 设置测试数据
            set_test_data(window_data, weight_data);
            calc_expected();
            pack_data();
            
            // 将期望结果加入FIFO
            expected_fifo[fifo_wr_ptr] = expected_result;
            fifo_wr_ptr = fifo_wr_ptr + 1;
            fifo_count = fifo_count + 1;
            
            // 发送数据
            @(posedge clk);
            window_valid = 1;
            weight_valid = 1;
            
            $display("Test %0d [%0s]: Expected = %0d", test_count, test_name, expected_result);
            $write("  Window: ");
            for (integer i = 0; i < 9; i = i + 1) $write("%0d ", test_window[i]);
            $write("\n  Weight: ");
            for (integer i = 0; i < 9; i = i + 1) $write("%0d ", test_weight[i]);
            $display("");
            
            @(posedge clk);
            window_valid = 0;
            weight_valid = 0;
        end
    endtask
    
    // 任务：验证结果
    task verify_result;
        input [2*DATA_WIDTH-1:0] actual;
        input [2*DATA_WIDTH-1:0] expected;
        begin
            if (actual == expected) begin
                pass_count = pass_count + 1;
                $display("  ✓ PASS: Actual = %0d, Expected = %0d", actual, expected);
            end else begin
                fail_count = fail_count + 1;
                $display("  ✗ FAIL: Actual = %0d, Expected = %0d", actual, expected);
            end
        end
    endtask
    
    // 任务：生成随机测试数据
    task generate_random_test;
        input [255:0] test_name;
        reg [71:0] rand_window, rand_weight;
        integer i;
        begin
            rand_window = 0;
            rand_weight = 0;
            for (i = 0; i < 9; i = i + 1) begin
                rand_window = rand_window | (($random % 256) << (i * 8));
                rand_weight = rand_weight | (($random % 256) << (i * 8));
            end
            send_test(rand_window, rand_weight, test_name);
        end
    endtask
    
    // 主测试序列
    initial begin
        $display("========================================");
        $display("Advanced Mult-Acc Module Test Suite");
        $display("DATA_WIDTH: %0d, KERNEL_SIZE: %0dx%0d", DATA_WIDTH, KERNEL_SIZE, KERNEL_SIZE);
        $display("Pipeline Delay: %0d cycles", PIPELINE_DELAY);
        $display("========================================");
        
        // 初始化信号
        rst_n = 0;
        window_valid = 0;
        weight_valid = 0;
        window_in = 0;
        weight_in = 0;
        
        // 复位序列
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);
        
        $display("\n=== 基础功能测试 ===");
        
        // 测试1：全零测试
        send_test(72'h000000000000000000, 72'h010203040506070809, "Zero Window");
        
        // 测试2：全一测试
        send_test(72'h010101010101010101, 72'h010101010101010101, "All Ones");
        
        // 测试3：简单乘法
        send_test(72'h020202020202020202, 72'h030303030303030303, "2x3 Multiplication");
        
        // 测试4：单位矩阵测试
        send_test(72'h000001000000000000, 72'h000005000000000000, "Unit Matrix");
        
        $display("\n=== 边界值测试 ===");
        
        // 测试5：最大正值
        send_test(72'h7F7F7F7F7F7F7F7F7F, 72'h010101010101010101, "Max Positive");
        
        // 测试6：最大负值
        send_test(72'h808080808080808080, 72'h010101010101010101, "Max Negative");
        
        // 测试7：混合正负值
        send_test(72'h7F80FF0001FE027F80, 72'h0102030405060708FF, "Mixed Pos/Neg");
        
        $display("\n=== 卷积核测试 ===");
        
        // 测试8：边缘检测核 (Sobel X)
        send_test(72'h050A0F14191E23282D, 72'hFF00010002000100FF, "Sobel X Edge");
        
        // 测试9：模糊核
        send_test(72'h050A0F14191E23282D, 72'h010101010101010101, "Blur Kernel");
        
        // 测试10：锐化核
        send_test(72'h050A0F14191E23282D, 72'hFF00FF00080000FF00, "Sharpen Kernel");
        
        $display("\n=== 流水线吞吐量测试 ===");
        
        // 连续发送多个数据测试流水线
        for (integer i = 0; i < 8; i = i + 1) begin
            generate_random_test("Pipeline Test");
            @(posedge clk); // 每周期发送一个
        end
        
        $display("\n=== 随机压力测试 ===");
        
        // 大量随机测试
        for (integer i = 0; i < 16; i = i + 1) begin
            generate_random_test("Random Stress");
            if (i % 4 == 0) repeat(2) @(posedge clk); // 偶尔插入间隔
        end
        
        $display("\n=== 时序测试 ===");
        
        // 测试不同的valid信号时序
        send_test(72'h010203040506070809, 72'h090807060504030201, "Timing Test 1");
        repeat(3) @(posedge clk);
        
        send_test(72'h0A0B0C0D0E0F101112, 72'h121110F0E0D0C0B0A, "Timing Test 2");
        repeat(1) @(posedge clk);
        
        send_test(72'h131415161718191A1B, 72'h1B1A191817161514, "Timing Test 3");
        
        // 等待所有结果
        repeat(20) @(posedge clk);
        
        // 最终报告
        $display("\n========================================");
        $display("测试完成统计:");
        $display("总测试数: %0d", test_count);
        $display("通过数: %0d", pass_count);
        $display("失败数: %0d", fail_count);
        $display("成功率: %.1f%%", (pass_count * 100.0) / test_count);
        $display("========================================");
        
        if (fail_count == 0) begin
            $display("🎉 所有测试通过！");
        end else begin
            $display("❌ 有测试失败，请检查！");
        end
        
        $display("\n性能统计:");
        $display("总时钟周期: %0d", cycle_count);
        $display("有效输出: %0d", valid_count);
        $display("吞吐量: %.2f outputs/cycle", (valid_count * 1.0) / cycle_count);
        
        $finish;
    end
    
    // 结果监控和验证
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
            
            if (conv_valid) begin
                valid_count = valid_count + 1;
                
                if (fifo_count > 0) begin
                    verify_result(conv_out, expected_fifo[fifo_rd_ptr]);
                    fifo_rd_ptr = fifo_rd_ptr + 1;
                    fifo_count = fifo_count - 1;
                end else begin
                    $display("WARNING: Unexpected conv_valid at time %0t", $time);
                end
            end
        end
    end
    
    // FIFO管理
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr <= 0;
            fifo_rd_ptr <= 0;
            fifo_count <= 0;
        end
    end
    
    // 错误检测
    always @(posedge clk) begin
        if (rst_n && fifo_count > 30) begin
            $display("ERROR: FIFO overflow at time %0t", $time);
            $finish;
        end
    end
    
    // 波形转储
    initial begin
        $dumpfile("mult_acc_tb.vcd");
        $dumpvars(0, mult_acc_tb);
        
        // 限制仿真时间防止死锁
        #5000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule 