// 多通道乘累加模块 - 同时处理所有输入通道的卷积运算
module mult_acc #(
    parameter DATA_WIDTH = 8,
    parameter KERNEL_SIZE = 3,
    parameter IN_CHANNEL = 3,
    parameter WEIGHT_WIDTH = 8,
    parameter ACC_WIDTH = 2*DATA_WIDTH + 4
)(
    // 全局信号接口
    input clk,
    input rst_n,

    // 多通道输入数据接口
    input window_valid,
    input [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] multi_channel_window_in,
    input weight_valid,
    input [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] multi_channel_weight_in,

    // 输出数据接口
    output reg signed [DATA_WIDTH-1:0] conv_out,
    output reg conv_valid
);

// 内部信号声明
// 解包后的多通道窗口数据和权重数据
reg signed [DATA_WIDTH-1:0] channel_window_data [0:IN_CHANNEL-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
reg signed [WEIGHT_WIDTH-1:0] channel_weight_data [0:IN_CHANNEL-1][0:KERNEL_SIZE*KERNEL_SIZE-1];

// 流水线阶段1：所有通道的乘法结果
reg signed [2*DATA_WIDTH-1:0] channel_mult_results [0:IN_CHANNEL-1][0:KERNEL_SIZE*KERNEL_SIZE-1];
reg stage1_valid;

// 流水线阶段2：每个通道的卷积结果
reg signed [ACC_WIDTH-1:0] channel_conv_results [0:IN_CHANNEL-1];
reg stage2_valid;

// 流水线阶段3：跨通道累加的第一层
reg signed [ACC_WIDTH-1:0] partial_sum;
reg stage3_valid;

// 临时累加变量
reg signed [ACC_WIDTH-1:0] temp_sum;
reg signed [ACC_WIDTH-1:0] temp_channel_sum;

// 循环变量
integer ch, i;

// 输入数据解包
always @(*) begin
    for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
        for (i = 0; i < KERNEL_SIZE*KERNEL_SIZE; i = i + 1) begin
            // 解包窗口数据
            channel_window_data[ch][i] = multi_channel_window_in[
                (ch*KERNEL_SIZE*KERNEL_SIZE + i + 1)*DATA_WIDTH-1 -: DATA_WIDTH
            ];
            // 解包权重数据
            channel_weight_data[ch][i] = multi_channel_weight_in[
                (ch*KERNEL_SIZE*KERNEL_SIZE + i + 1)*WEIGHT_WIDTH-1 -: WEIGHT_WIDTH
            ];
        end
    end
end

// 流水线阶段1：并行乘法 (所有通道，所有位置)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
            for (i = 0; i < KERNEL_SIZE*KERNEL_SIZE; i = i + 1) begin
                channel_mult_results[ch][i] <= 0;
            end
        end
        stage1_valid <= 0;
    end else begin
        // 并行执行所有通道的所有乘法
        for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
            for (i = 0; i < KERNEL_SIZE*KERNEL_SIZE; i = i + 1) begin
                channel_mult_results[ch][i] <= channel_window_data[ch][i] * channel_weight_data[ch][i];
            end
        end
        stage1_valid <= window_valid && weight_valid;
    end
end

// 流水线阶段2：每个通道内的累加
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
            channel_conv_results[ch] <= 0;
        end
        stage2_valid <= 0;
    end else begin
        // 每个通道内的卷积核乘积累加 - 通用于任意KERNEL_SIZE
        for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
            temp_channel_sum = 0;
            for (i = 0; i < KERNEL_SIZE*KERNEL_SIZE; i = i + 1) begin
                temp_channel_sum = temp_channel_sum + channel_mult_results[ch][i];
            end
            channel_conv_results[ch] <= temp_channel_sum;
        end
        stage2_valid <= stage1_valid;
    end
end

// 流水线阶段3：跨通道累加
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        partial_sum <= 0;
        stage3_valid <= 0;
    end else begin
        // 通用的跨通道累加 - 适用于任意IN_CHANNEL值
        temp_sum = 0;
        for (i = 0; i < IN_CHANNEL; i = i + 1) begin
            temp_sum = temp_sum + channel_conv_results[i];
        end
        partial_sum <= temp_sum;
        stage3_valid <= stage2_valid;
    end
end

// 最终阶段：输出
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        conv_out <= 0;
        conv_valid <= 0;
    end else begin
        if (stage3_valid) begin
            // 饱和处理并输出
            conv_out <= saturate(partial_sum);
            conv_valid <= 1;
        end else begin
            conv_out <= 0;
            conv_valid <= 0;
        end
    end
end

// 饱和处理函数（防止溢出）
function [DATA_WIDTH-1:0] saturate;
    input signed [ACC_WIDTH-1:0] value;
    localparam signed [ACC_WIDTH-1:0] MAX_VAL = (1 << (DATA_WIDTH-1)) - 1;
    localparam signed [ACC_WIDTH-1:0] MIN_VAL = -(1 << (DATA_WIDTH-1));
    begin
        if (value > MAX_VAL)
            saturate = MAX_VAL[DATA_WIDTH-1:0];
        else if (value < MIN_VAL)
            saturate = MIN_VAL[DATA_WIDTH-1:0];
        else
            saturate = value[DATA_WIDTH-1:0];
    end
endfunction

endmodule 