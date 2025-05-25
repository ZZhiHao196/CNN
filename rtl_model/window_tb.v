`timescale 1ns / 1ps

module window_tb();

    // 测试用参数 - 使用小尺寸便于观察
    parameter DATA_WIDTH = 8;
    parameter IMG_WIDTH = 5;
    parameter IMG_HEIGHT = 5;
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
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // 测试数据 - 5x5图像
    reg [DATA_WIDTH-1:0] test_image [0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
    
    // 窗口计数器
    integer window_count = 0;
    
    // 初始化测试图像
    
      task reset_test_image;
        integer i, j;
        begin
            for(i = 0; i < IMG_HEIGHT; i = i + 1) begin
                for(j = 0; j < IMG_WIDTH; j = j + 1) begin
                    test_image[i][j] =0;
                end
            end
        end
    endtask
    
    task init_test_image;
        integer i, j;
        begin
            for(i = 0; i < IMG_HEIGHT; i = i + 1) begin
                for(j = 0; j < IMG_WIDTH; j = j + 1) begin
                    test_image[i][j] = i * IMG_WIDTH + j + 1;
                end
            end
        end
    endtask
    
    // 显示测试图像
    task display_test_image;
        integer i, j;
        begin
            $display("\n=== 4x4 Test Image ===");
            for(i = 0; i < IMG_HEIGHT; i = i + 1) begin
                $write("Row %0d: ", i);
                for(j = 0; j < IMG_WIDTH; j = j + 1) begin
                    $write("%3d ", test_image[i][j]);
                end
                $display("");
            end
            $display("======================\n");
        end
    endtask
    
    // 发送一帧图像数据
    task send_frame;
        integer i, j;
        begin
            $display("Sending 4x4 frame...");
            init_test_image();
            display_test_image();
            
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
                    $display("Sending pixel[%0d][%0d] = %0d at time %0t", i, j, pixel_in, $time);
                end
            end
            
            @(posedge clk);
            pixel_valid = 0;
            $display("All pixels sent at time %0t", $time);
        end
    endtask
    
    // 主测试序列
    initial begin
        $display("========================================");
        $display("Window Test - Focus on Last Window");
        $display("IMG_SIZE: %0dx%0d, KERNEL: %0dx%0d", IMG_WIDTH, IMG_HEIGHT, KERNEL_SIZE, KERNEL_SIZE);
        $display("Expected windows: %0d", IMG_WIDTH * IMG_HEIGHT);
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
        
        // 发送测试帧
        send_frame();
        
        // 等待所有窗口输出
        repeat(50) @(posedge clk);
        
        $display("\n========================================");
        $display("Test Summary:");
        $display("Total Windows Generated: %0d", window_count);
        $display("Expected Windows: %0d", IMG_WIDTH * IMG_HEIGHT);
        if(window_count == IMG_WIDTH * IMG_HEIGHT) begin
            $display("SUCCESS: All windows generated!");
        end else begin
            $display("FAILURE: Missing windows!");
        end
        $display("========================================");
        
        $finish;
    end
    
    // 窗口监控
    always @(posedge clk) begin
        if(window_valid) begin
            window_count = window_count + 1;
            $display("Window %0d: pos(%0d,%0d) at time %0t", 
                     window_count, dut.x_window, dut.y_window, $time);
            
            // 显示窗口内容
            $write("Window content: ");
            $write("[%0d %0d %0d] ", 
                   window_out[71:64], window_out[63:56], window_out[55:48]);
            $write("[%0d %0d %0d] ", 
                   window_out[47:40], window_out[39:32], window_out[31:24]);
            $write("[%0d %0d %0d]", 
                   window_out[23:16], window_out[15:8], window_out[7:0]);
            $display("");
        end
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
    
    
    // 波形转储
    initial begin
        $dumpfile("window_tb.vcd");
        $dumpvars(0, window_tb);
        
        // 限制仿真时间
        #2000;
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule 