`timescale 1ns / 1ps

module conv_parallel_tb();

    // 测试参数
    parameter DATA_WIDTH = 8;
    parameter KERNEL_SIZE = 3;
    parameter IN_CHANNEL = 3;
    parameter NUM_FILTERS = 3;
    parameter IMG_WIDTH = 8;
    parameter IMG_HEIGHT = 8;
    parameter STRIDE = 1;
    parameter PADDING = (KERNEL_SIZE - 1) / 2;
    parameter WEIGHT_WIDTH = 8;
    parameter ACC_WIDTH = 2*DATA_WIDTH + 4;
    
    // 测试信号
    reg clk;
    reg rst_n;
    reg [IN_CHANNEL*DATA_WIDTH-1:0] pixel_in;  // 并行输入所有通道
    reg pixel_valid;
    reg frame_start;
    
    wire [NUM_FILTERS*DATA_WIDTH-1:0] conv_out;
    wire conv_valid;
    
    // 实例化被测模块
    conv_parallel #(
        .DATA_WIDTH(DATA_WIDTH),
        .KERNEL_SIZE(KERNEL_SIZE),
        .IN_CHANNEL(IN_CHANNEL),
        .NUM_FILTERS(NUM_FILTERS),
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .STRIDE(STRIDE),
        .PADDING(PADDING),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .pixel_in(pixel_in),
        .pixel_valid(pixel_valid),
        .frame_start(frame_start),
        .conv_out(conv_out),
        .conv_valid(conv_valid)
    );
    
    // 时钟生成 - 100MHz
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // 测试图像数据 (8x8x3图像)
    reg [DATA_WIDTH-1:0] test_image [0:IN_CHANNEL-1][0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    
    // 测试统计
    integer output_count = 0;
    integer cycle_count = 0;
    integer start_time = 0;
    integer end_time = 0;
    
    // 任务：初始化测试图像
    task init_test_image;
        integer ch, y, x;
        begin
            $display("初始化并行测试图像...");
            for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                    for (x = 0; x < IMG_WIDTH; x = x + 1) begin
                        // 创建不同的测试模式
                        case (ch)
                            0: test_image[ch][y][x] = (x + y) * 8;     // 通道0: 渐变
                            1: test_image[ch][y][x] = ((x + y) % 2) ? 128 : 32; // 通道1: 棋盘
                            2: test_image[ch][y][x] = (x == 0 || x == IMG_WIDTH-1 || 
                                                     y == 0 || y == IMG_HEIGHT-1) ? 200 : 50; // 通道2: 边缘
                        endcase
                    end
                end
            end
            
            // 打印测试图像
            for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                $display("通道 %0d:", ch);
                for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                    $write("  ");
                    for (x = 0; x < IMG_WIDTH; x = x + 1) begin
                        $write("%3d ", test_image[ch][y][x]);
                    end
                    $display("");
                end
            end
        end
    endtask
    
    // 任务：并行发送一帧图像数据
    task send_frame_parallel;
        integer x, y, ch;
        reg [IN_CHANNEL*DATA_WIDTH-1:0] packed_pixels;
        begin
            $display("开始并行发送帧数据...");
            start_time = cycle_count;
            
            // 发送frame_start信号
            @(posedge clk);
            frame_start = 1;
            @(posedge clk);
            frame_start = 0;
            
            // 按位置发送像素数据 (每个位置同时发送所有通道)
            for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                for (x = 0; x < IMG_WIDTH; x = x + 1) begin
                    @(posedge clk);
                    
                    // 打包所有通道的像素数据
                    packed_pixels = 0;
                    for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                        packed_pixels[(ch+1)*DATA_WIDTH-1 -: DATA_WIDTH] = test_image[ch][y][x];
                    end
                    
                    pixel_in = packed_pixels;
                    pixel_valid = 1;
                    
                    $display("发送像素 [%0d,%0d]: Ch0=%0d, Ch1=%0d, Ch2=%0d", 
                            x, y, test_image[0][y][x], test_image[1][y][x], test_image[2][y][x]);
                end
            end
            
            @(posedge clk);
            pixel_valid = 0;
            $display("并行帧数据发送完成");
        end
    endtask
    
    // 任务：等待并收集输出
    task collect_outputs_parallel;
        integer timeout_counter;
        begin
            $display("等待并行卷积输出...");
            timeout_counter = 0;
            
            while (timeout_counter < 2000) begin
                @(posedge clk);
                timeout_counter = timeout_counter + 1;
                
                if (conv_valid) begin
                    output_count = output_count + 1;
                    if (output_count == 1) end_time = cycle_count;
                    
                    $display("并行输出 %0d: 时间=%0t, 周期=%0d", output_count, $time, cycle_count);
                    
                    // 解析并显示每个滤波器的输出
                    for (integer f = 0; f < NUM_FILTERS; f = f + 1) begin
                        $display("  滤波器 %0d: %0d", f, 
                               conv_out[(f+1)*DATA_WIDTH-1 -: DATA_WIDTH]);
                    end
                    
                    // 对于8x8图像，SAME padding，stride=1，应该有8x8=64个输出
                    if (output_count >= 64) break;
                end
            end
            
            if (timeout_counter >= 2000) begin
                $display("警告: 等待并行输出超时");
            end
        end
    endtask
    
    // 主测试序列
    initial begin
        $display("========================================");
        $display("并行CNN卷积层性能测试");
        $display("图像尺寸: %0dx%0d, 通道数: %0d, 滤波器数: %0d", 
                IMG_WIDTH, IMG_HEIGHT, IN_CHANNEL, NUM_FILTERS);
        $display("并行输入: %0d位 (%0d通道 × %0d位)", 
                IN_CHANNEL*DATA_WIDTH, IN_CHANNEL, DATA_WIDTH);
        $display("========================================");
        
        // 初始化信号
        rst_n = 0;
        pixel_in = 0;
        pixel_valid = 0;
        frame_start = 0;
        
        // 复位序列
        repeat(10) @(posedge clk);
        rst_n = 1;
        repeat(5) @(posedge clk);
        
        // 初始化测试数据
        init_test_image();
        
        $display("\n=== 并行卷积性能测试 ===");
        
        // 并行发送一帧测试数据
        send_frame_parallel();
        
        // 等待并收集输出
        collect_outputs_parallel();
        
        // 等待额外的周期确保所有处理完成
        repeat(50) @(posedge clk);
        
        $display("\n=== 性能统计 ===");
        $display("总输出数: %0d", output_count);
        $display("总周期数: %0d", cycle_count);
        $display("输入周期数: %0d (8×8 = 64像素)", IMG_WIDTH * IMG_HEIGHT);
        $display("处理延迟: %0d周期", end_time - start_time);
        
        if (output_count > 0) begin
            $display("✓ 并行测试通过 - 产生了卷积输出");
            $display("平均吞吐量: %.2f 输出/周期", (output_count * 1.0) / cycle_count);
            
            // 计算性能提升
            integer serial_cycles = IMG_WIDTH * IMG_HEIGHT * IN_CHANNEL * NUM_FILTERS * 4; // 串行版本估计
            integer parallel_cycles = end_time - start_time;
            real speedup = (serial_cycles * 1.0) / parallel_cycles;
            
            $display("估计性能提升: %.1fx (串行: %0d周期 vs 并行: %0d周期)", 
                    speedup, serial_cycles, parallel_cycles);
        end else begin
            $display("✗ 并行测试失败 - 没有产生输出");
        end
        
        $display("========================================");
        $finish;
    end
    
    // 周期计数器
    always @(posedge clk) begin
        if (rst_n) begin
            cycle_count = cycle_count + 1;
        end
    end
    
    // 输出监控
    always @(posedge clk) begin
        if (conv_valid) begin
            $display("时间 %0t: 检测到并行有效输出", $time);
        end
    end
    
    // 波形转储
    initial begin
        $dumpfile("conv_parallel_tb.vcd");
        $dumpvars(0, conv_parallel_tb);
        
        // 限制仿真时间防止死锁
        #100000;
        $display("错误: 并行仿真超时!");
        $finish;
    end

endmodule 