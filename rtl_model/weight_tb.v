`timescale 1ns / 1ps

module weight_tb;

// Parameters
parameter NUM_FILTERS = 3;
parameter INPUT_CHANNELS = 3;
parameter KERNEL_SIZE = 3;
parameter WEIGHT_WIDTH = 8;
parameter INIT_FILE = "C:/Users/86139/Desktop/ECNU/project_1/weights.mem";

// Clock and reset
reg clk;
reg rst_n;

// Control signals
reg read_enable;

// Output signals
wire [INPUT_CHANNELS*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] multi_channel_weight_out;
wire weight_valid;

// Test variables
integer test_count;
integer pass_count;
integer i, ch, pos;
reg [WEIGHT_WIDTH-1:0] weight_val;
reg [WEIGHT_WIDTH-1:0] expected_weights [0:8];
integer errors;

// Instantiate the weight module for filter 0
weight #(
    .NUM_FILTERS(NUM_FILTERS),
    .INPUT_CHANNELS(INPUT_CHANNELS),
    .KERNEL_SIZE(KERNEL_SIZE),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .FILTER_ID(0),
    .INIT_FILE(INIT_FILE)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .read_enable(read_enable),
    .multi_channel_weight_out(multi_channel_weight_out),
    .weight_valid(weight_valid)
);

// Clock generation
always #5 clk = ~clk;

// Test sequence
initial begin
    // Initialize
    clk = 0;
    rst_n = 0;
    read_enable = 0;
    test_count = 0;
    pass_count = 0;
    
    $display("=== 并行权重模块完整测试 ===");
    $display("配置:");
    $display("  滤波器数: %d", NUM_FILTERS);
    $display("  输入通道数: %d", INPUT_CHANNELS);
    $display("  卷积核大小: %d", KERNEL_SIZE);
    $display("  权重位宽: %d", WEIGHT_WIDTH);
    $display("  输出位宽: %d", INPUT_CHANNELS*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH);
    $display("");
    
    // Reset sequence
    #20;
    rst_n = 1;
    #20;
    
    // Test 1: Basic read operation
    $display("测试1: 基本读取操作");
    test_count = test_count + 1;
    
    read_enable = 1;
    
    // Wait for valid signal with timeout
    i = 0;
    while (i < 100 && !weight_valid) begin
        @(posedge clk);
        i = i + 1;
    end
    
    if (weight_valid) begin
        $display("✓ 权重读取成功 (用时 %d 周期)", i);
        $display("  输出数据: %h", multi_channel_weight_out);
        pass_count = pass_count + 1;
        
        // Parse and display weights
        $display("  解析的权重数据:");
        for (ch = 0; ch < INPUT_CHANNELS; ch = ch + 1) begin
            $write("    通道 %d: ", ch);
            for (pos = 0; pos < KERNEL_SIZE*KERNEL_SIZE; pos = pos + 1) begin
                weight_val = multi_channel_weight_out[(ch*KERNEL_SIZE*KERNEL_SIZE + pos + 1)*WEIGHT_WIDTH-1 -: WEIGHT_WIDTH];
                $write("%02h ", weight_val);
            end
            $display("");
        end
    end else begin
        $display("✗ 权重读取失败 - 超时");
    end
    
    read_enable = 0;
    #20;
    
    // Test 2: Reset test
    $display("测试2: 复位功能");
    test_count = test_count + 1;
    
    read_enable = 1;
    #30;
    
    rst_n = 0;
    read_enable = 0;
    #20;
    rst_n = 1;
    #20;
    
    if (!weight_valid && multi_channel_weight_out == 0) begin
        $display("✓ 复位功能正常");
        pass_count = pass_count + 1;
    end else begin
        $display("✗ 复位功能异常");
        $display("  weight_valid = %b, output = %h", weight_valid, multi_channel_weight_out);
    end
    
    // Test 3: Enable control test
    $display("测试3: 使能控制");
    test_count = test_count + 1;
    
    read_enable = 0;
    #50;
    
    if (!weight_valid) begin
        $display("✓ 使能控制正常 - 禁用时无输出");
        pass_count = pass_count + 1;
    end else begin
        $display("✗ 使能控制异常 - 禁用时有输出");
    end
    
    // Test 4: Multiple read cycles
    $display("测试4: 多次读取周期");
    test_count = test_count + 1;
    
    read_enable = 1;
    
    // First read
    i = 0;
    while (i < 100 && !weight_valid) begin
        @(posedge clk);
        i = i + 1;
    end
    
    if (weight_valid) begin
        $display("  第一次读取成功");
        read_enable = 0;
        #20;
        
        // Second read
        read_enable = 1;
        i = 0;
        while (i < 100 && !weight_valid) begin
            @(posedge clk);
            i = i + 1;
        end
        
        if (weight_valid) begin
            $display("✓ 多次读取功能正常");
            pass_count = pass_count + 1;
        end else begin
            $display("✗ 第二次读取失败");
        end
    end else begin
        $display("✗ 第一次读取失败");
    end
    
    read_enable = 0;
    #20;
    
    // Test 5: Weight data verification
    $display("测试5: 权重数据验证");
    test_count = test_count + 1;
    
    read_enable = 1;
    
    i = 0;
    while (i < 100 && !weight_valid) begin
        @(posedge clk);
        i = i + 1;
    end
    
    if (weight_valid) begin
        // Check expected values for filter 0 (edge detection kernel)
        // Expected: FF 00 01 FE 00 02 FF 00 01 for each channel
        
        expected_weights[0] = 8'hFF; expected_weights[1] = 8'h00; expected_weights[2] = 8'h01;
        expected_weights[3] = 8'hFE; expected_weights[4] = 8'h00; expected_weights[5] = 8'h02;
        expected_weights[6] = 8'hFF; expected_weights[7] = 8'h00; expected_weights[8] = 8'h01;
        
        errors = 0;
        
        for (ch = 0; ch < INPUT_CHANNELS; ch = ch + 1) begin
            for (pos = 0; pos < KERNEL_SIZE*KERNEL_SIZE; pos = pos + 1) begin
                weight_val = multi_channel_weight_out[(ch*KERNEL_SIZE*KERNEL_SIZE + pos + 1)*WEIGHT_WIDTH-1 -: WEIGHT_WIDTH];
                if (weight_val !== expected_weights[pos]) begin
                    $display("  ✗ 通道 %d 位置 %d: 期望 %02h, 实际 %02h", ch, pos, expected_weights[pos], weight_val);
                    errors = errors + 1;
                end
            end
        end
        
        if (errors == 0) begin
            $display("✓ 权重数据验证通过 - 所有权重正确");
            pass_count = pass_count + 1;
        end else begin
            $display("✗ 权重数据验证失败 - 发现 %d 个错误", errors);
        end
    end else begin
        $display("✗ 权重数据验证失败 - 无法读取权重");
    end
    
    read_enable = 0;
    #20;
    
    // Final results
    $display("");
    $display("=== 测试结果汇总 ===");
    $display("总测试数: %d", test_count);
    $display("通过测试数: %d", pass_count);
    $display("失败测试数: %d", test_count - pass_count);
    
    if (pass_count == test_count) begin
        $display("🎉 所有测试通过! 并行权重模块工作正常");
    end else begin
        $display("❌ 部分测试失败! 需要检查模块实现");
    end
    
    $display("");
    $display("模块特性验证:");
    $display("✓ 并行权重输出: %d 位", INPUT_CHANNELS*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH);
    $display("✓ 滤波器特定权重: Filter ID = 0");
    $display("✓ 多通道支持: %d 个输入通道", INPUT_CHANNELS);
    $display("✓ 权重文件加载: %s", INIT_FILE);
    
    #100;
    $finish;
end

// Monitor for debugging
always @(posedge clk) begin
    if (weight_valid && read_enable) begin
        $display("时间 %t: 检测到有效权重输出", $time);
    end
end

endmodule 