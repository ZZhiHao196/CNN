`timescale 1ns / 1ps

module window_tb();

    // 测试用参数 - 可以修改来测试不同配置
    parameter DATA_WIDTH = 8;
    parameter IMG_WIDTH = 6;
    parameter IMG_HEIGHT = 6;
    parameter KERNEL_SIZE = 3;
    parameter STRIDE = 1;
    parameter PADDING = (KERNEL_SIZE - 1) / 2;
    
    // 测试信号
    reg clk;
    reg rst_n;
    reg [DATA_WIDTH-1:0] pixel_in;
    reg pixel_valid;
    reg frame_start;
    
    wire [KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] window_out;
    wire window_valid;
    
    // 实例化被测模块
    window #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .KERNEL_SIZE(KERNEL_SIZE),
        .STRIDE(STRIDE),
        .PADDING(PADDING)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(pixel_in),
        .pixel_valid(pixel_valid),
        .frame_start(frame_start),
        .window_out(window_out),
        .window_valid(window_valid)
    );
    
    // 时钟生成 - 100MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // 测试数据存储 - 使用unpacked数组
    reg [DATA_WIDTH-1:0] test_image [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    
    // 窗口比较用的临时数组
    reg [DATA_WIDTH-1:0] expected_window [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    reg [DATA_WIDTH-1:0] actual_window [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
    
    // 测试计数器和状态
    integer test_count = 0;
    integer window_count = 0;
    integer error_count = 0;
    integer pass_count = 0;
    
    
    
    task reset_test_image;
          integer i, j;
          for(i = 0; i < IMG_HEIGHT; i = i + 1) begin
              for(j = 0; j < IMG_WIDTH; j = j + 1) begin
                  test_image[i][j] = 0;
              end
          end
    
    endtask
    
    // 任务：初始化测试图像
    task init_test_image;
        input integer pattern_type;
        integer i, j;
        begin
            case(pattern_type)
                0: begin // 顺序递增模式
                    for(i = 0; i < IMG_HEIGHT; i = i + 1) begin
                        for(j = 0; j < IMG_WIDTH; j = j + 1) begin
                            test_image[i][j] = i * IMG_WIDTH + j + 1;
                        end
                    end
                end
                1: begin // 棋盘模式
                    for(i = 0; i < IMG_HEIGHT; i = i + 1) begin
                        for(j = 0; j < IMG_WIDTH; j = j + 1) begin
                            test_image[i][j] = ((i + j) % 2) ? 8'hFF : 8'h00;
                        end
                    end
                end
                2: begin // 边界测试模式
                    for(i = 0; i < IMG_HEIGHT; i = i + 1) begin
                        for(j = 0; j < IMG_WIDTH; j = j + 1) begin
                            if(i == 0 || i == IMG_HEIGHT-1 || j == 0 || j == IMG_WIDTH-1)
                                test_image[i][j] = 8'hAA;
                            else
                                test_image[i][j] = 8'h55;
                        end
                    end
                end
                default: begin // 全零模式
                    for(i = 0; i < IMG_HEIGHT; i = i + 1) begin
                        for(j = 0; j < IMG_WIDTH; j = j + 1) begin
                            test_image[i][j] = 0;
                        end
                    end
                end
            endcase
        end
    endtask
    
    // 任务：显示测试图像
    task display_test_image;
        integer i, j;
        begin
            $display("\n=== Test Image Pattern ===");
            for(i = 0; i < IMG_HEIGHT; i = i + 1) begin
                $write("Row %0d: ", i);
                for(j = 0; j < IMG_WIDTH; j = j + 1) begin
                    $write("%3d ", test_image[i][j]);
                end
                $display("");
            end
            $display("===========================\n");
        end
    endtask
    
    // 任务：计算期望的窗口输出
    task calc_expected_window;
        input integer center_x, center_y;
        integer i, j, src_x, src_y;
        begin
            for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
                for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
                    src_x = center_x + j - PADDING;
                    src_y = center_y + i - PADDING;
                    
                    // 处理边界条件 - SAME padding用0填充
                    if(src_x < 0 || src_x >= IMG_WIDTH || src_y < 0 || src_y >= IMG_HEIGHT) begin
                        expected_window[i][j] = 0;
                    end else begin
                        expected_window[i][j] = test_image[src_y][src_x];
                    end
                end
            end
        end
    endtask
    
    // 任务：提取实际窗口输出
    task extract_actual_window;
        input [KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] window_data;
        integer i, j;
        begin
            for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
                for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
                    actual_window[i][j] = window_data[(KERNEL_SIZE*KERNEL_SIZE-(i*KERNEL_SIZE+j))*DATA_WIDTH-1 -: DATA_WIDTH];
                end
            end
        end
    endtask
    
    // 任务：比较窗口输出
    task compare_windows;
        input integer center_x, center_y;
        input [KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] actual_output;
        integer i, j;
        reg match;
        begin
            calc_expected_window(center_x, center_y);
            extract_actual_window(actual_output);
            
            match = 1;
            for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
                for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
                    if(expected_window[i][j] !== actual_window[i][j]) begin
                        match = 0;
                    end
                end
            end
            
            if(match) begin
                pass_count = pass_count + 1;
                $display("PASS: Window at (%0d,%0d) matches expected", center_x, center_y);
            end else begin
                error_count = error_count + 1;
                $display("FAIL: Window at (%0d,%0d) mismatch!", center_x, center_y);
                $display("Expected:");
                for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
                    $write("  [");
                    for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
                        $write("%3d ", expected_window[i][j]);
                    end
                    $display("]");
                end
                $display("Actual:");
                for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
                    $write("  [");
                    for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
                        $write("%3d ", actual_window[i][j]);
                    end
                    $display("]");
                end
            end
        end
    endtask
    
    // 任务：发送一帧图像数据
    task send_frame;
        input integer pattern_type;
        input integer add_noise; // 是否添加时序噪声
        integer i, j, wait_cycles;
        begin
            $display("Sending frame with pattern type %0d", pattern_type);
            init_test_image(pattern_type);
            if(pattern_type <= 2) display_test_image();
            
            // 发送frame_start信号
            @(posedge clk);
            frame_start = 1;
            @(posedge clk);
            frame_start = 0;
            
            // 逐像素发送数据
            for(i = 0; i < IMG_HEIGHT; i = i + 1) begin
                for(j = 0; j < IMG_WIDTH; j = j + 1) begin
                    @(posedge clk);
                    pixel_in = test_image[i][j];
                    pixel_valid = 1;
                    
                    // 可选：添加随机等待来测试时序鲁棒性
                    if(add_noise && ($random % 10 == 0)) begin
                        @(posedge clk);
                        pixel_valid = 0;
                        wait_cycles = $random % 3 + 1;
                        repeat(wait_cycles) @(posedge clk);
                    end
                end
            end
            
            @(posedge clk);
            pixel_valid = 0;
        end
    endtask
    
    // 任务：监控和验证窗口输出
    task monitor_windows;
        input integer expected_window_count;
        integer received_count;
        integer timeout_cycles;
        begin
            received_count = 0;
            timeout_cycles = 0;
            
            while(received_count < expected_window_count && timeout_cycles < 1000) begin
                @(posedge clk);
                timeout_cycles = timeout_cycles + 1;
                
                if(window_valid) begin
                    received_count = received_count + 1;
                    window_count = window_count + 1;
                    
                    $display("Window %0d: pos(%0d,%0d), time=%0t", 
                             received_count, dut.x_window, dut.y_window, $time);
                    
                    // 验证窗口内容
                    compare_windows(dut.x_window, dut.y_window, window_out);
                end
            end
            
            if(timeout_cycles >= 1000) begin
                $display("ERROR: Timeout waiting for windows. Expected %0d, got %0d", 
                         expected_window_count, received_count);
                error_count = error_count + 1;
            end else if(received_count == expected_window_count) begin
                $display("SUCCESS: Received all %0d expected windows", expected_window_count);
            end
        end
    endtask
    
    // 主测试序列
    initial begin
        $display("========================================");
        $display("Advanced Window Module Test Starting");
        $display("IMG_SIZE: %0dx%0d, KERNEL: %0dx%0d, STRIDE: %0d", 
                 IMG_WIDTH, IMG_HEIGHT, KERNEL_SIZE, KERNEL_SIZE, STRIDE);
        $display("========================================");
        
        // 初始化信号
        rst_n = 0;
        pixel_in = 0;
        pixel_valid = 0;
        frame_start = 0;
        reset_test_image();
        // 复位序列
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);
        
        // 测试1：基本功能测试 - 顺序递增模式
        test_count = test_count + 1;
        $display("\n--- Test %0d: Sequential Pattern ---", test_count);
        send_frame(0, 0); // pattern_type=0, no noise
        monitor_windows(IMG_WIDTH * IMG_HEIGHT); // 预期窗口数量
        
        // 等待状态机返回IDLE
        repeat(10) @(posedge clk);
        
        // 测试2：棋盘模式测试
        test_count = test_count + 1;
        $display("\n--- Test %0d: Checkerboard Pattern ---", test_count);
        send_frame(1, 0);
        monitor_windows(IMG_WIDTH * IMG_HEIGHT);
        repeat(10) @(posedge clk);
        
        // 测试3：边界测试模式
        test_count = test_count + 1;
        $display("\n--- Test %0d: Boundary Pattern ---", test_count);
        send_frame(2, 0);
        monitor_windows(IMG_WIDTH * IMG_HEIGHT);
        repeat(10) @(posedge clk);
        
        // 测试4：时序噪声测试
        test_count = test_count + 1;
        $display("\n--- Test %0d: Timing Noise Test ---", test_count);
        send_frame(0, 1); // 添加时序噪声
        monitor_windows(IMG_WIDTH * IMG_HEIGHT);
        repeat(10) @(posedge clk);
        
        // 测试5：连续多帧测试
        test_count = test_count + 1;
        $display("\n--- Test %0d: Multiple Frames ---", test_count);
        repeat(3) begin
            send_frame($random % 3, 0);
            monitor_windows(IMG_WIDTH * IMG_HEIGHT);
            repeat(5) @(posedge clk);
        end
        
        // 最终结果报告
        $display("\n========================================");
        $display("Test Summary:");
        $display("Total Tests: %0d", test_count);
        $display("Total Windows: %0d", window_count);
        $display("Passed Windows: %0d", pass_count);
        $display("Failed Windows: %0d", error_count);
        if(pass_count + error_count > 0) begin
            $display("Success Rate: %.1f%%", (pass_count * 100.0) / (pass_count + error_count));
        end else begin
            $display("Success Rate: N/A (no windows processed)");
        end
        
        if(error_count == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("SOME TESTS FAILED!");
        end
        $display("========================================");
        
        $finish;
    end
    
    // 状态机监控
    reg [1:0] prev_state = 2'b00;
    always @(posedge clk) begin
        if(dut.current_state != prev_state) begin
            case(dut.current_state)
                2'b00: $display("Time %0t: State -> IDLE", $time);
                2'b01: $display("Time %0t: State -> LOAD", $time);
                2'b10: $display("Time %0t: State -> PROCESS", $time);
                default: $display("Time %0t: State -> UNKNOWN(%0d)", $time, dut.current_state);
            endcase
            prev_state = dut.current_state;
        end
    end
    
    // 错误检测
    always @(posedge clk) begin
        // 检测非法状态转换
        if(dut.current_state == 2'b11) begin
            $display("ERROR: Illegal state detected at time %0t", $time);
            error_count = error_count + 1;
        end
        
        // 检测window_valid在错误状态下被断言
        if(window_valid && dut.current_state != 2'b10) begin
            $display("ERROR: window_valid asserted in non-PROCESS state at time %0t", $time);
            error_count = error_count + 1;
        end
    end
    
    // 波形转储
    initial begin
        $dumpfile("window_tb.vcd");
        $dumpvars(0, window_tb);
        
        // 限制仿真时间防止死锁
        #50000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule 