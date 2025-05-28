// 组合逻辑多通道乘累加模块 - 立即处理窗口数据 (UNSIGNED)
module mult_acc_comb #(
    parameter DATA_WIDTH = 8,
    parameter KERNEL_SIZE = 3,
    parameter IN_CHANNEL = 3,
    parameter WEIGHT_WIDTH = 8,
    parameter OUTPUT_WIDTH = 20,  // 可配置的输出位宽
    parameter ACC_WIDTH = 2*DATA_WIDTH + 4 + $clog2(KERNEL_SIZE*KERNEL_SIZE*IN_CHANNEL) // Ensure ACC_WIDTH is sufficient
)(
    // 输入数据接口
    input window_valid,
    input [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] multi_channel_window_in,
    input weight_valid,
    input [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] multi_channel_weight_in,

    // 输出数据接口
    output [OUTPUT_WIDTH-1:0] conv_out, // 使用可配置的输出位宽
    output conv_valid
);

// 计算权重相关参数
localparam WEIGHTS_PER_FILTER = IN_CHANNEL * KERNEL_SIZE * KERNEL_SIZE;

// 解包后的多通道窗口数据和权重数据
wire [DATA_WIDTH-1:0] channel_window_data [0:IN_CHANNEL-1][0:KERNEL_SIZE*KERNEL_SIZE-1]; // UNSIGNED
wire [WEIGHT_WIDTH-1:0] channel_weight_data [0:IN_CHANNEL-1][0:KERNEL_SIZE*KERNEL_SIZE-1]; // UNSIGNED

// 每个通道每个位置的乘法结果
wire [DATA_WIDTH+WEIGHT_WIDTH-1:0] mult_results [0:IN_CHANNEL-1][0:KERNEL_SIZE*KERNEL_SIZE-1]; // UNSIGNED

// 每个通道的累加结果
wire [ACC_WIDTH-1:0] channel_sums [0:IN_CHANNEL-1]; // UNSIGNED

// 最终跨通道累加结果
wire [ACC_WIDTH-1:0] total_sum; // UNSIGNED

// 循环变量
genvar ch, i_idx, k_idx, c_idx; // Renamed loop variables to avoid conflict with port `i` if it existed

// 输入数据解包
generate
    for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin : unpack_gen
        for (i_idx = 0; i_idx < KERNEL_SIZE*KERNEL_SIZE; i_idx = i_idx + 1) begin : element_gen
            // 解包窗口数据
            assign channel_window_data[ch][i_idx] = multi_channel_window_in[
                (ch*KERNEL_SIZE*KERNEL_SIZE + i_idx)*DATA_WIDTH +: DATA_WIDTH // Corrected indexing
            ];
            // 解包权重数据 - 修正位序以匹配weight.v的打包顺序
            assign channel_weight_data[ch][i_idx] = multi_channel_weight_in[
                (WEIGHTS_PER_FILTER - 1 - (ch*KERNEL_SIZE*KERNEL_SIZE + i_idx))*WEIGHT_WIDTH +: WEIGHT_WIDTH
            ];
        end
    end
endgenerate

// 并行乘法 - 所有通道所有位置同时计算
generate
    for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin : mult_ch_gen
        for (i_idx = 0; i_idx < KERNEL_SIZE*KERNEL_SIZE; i_idx = i_idx + 1) begin : mult_elem_gen
            assign mult_results[ch][i_idx] = channel_window_data[ch][i_idx] * channel_weight_data[ch][i_idx];
        end
    end
endgenerate

// 每个通道内累加 - 使用组合逻辑加法树
generate
    for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin : sum_ch_gen
        if (KERNEL_SIZE == 3) begin : kernel3_sum
            assign channel_sums[ch] = 
                mult_results[ch][0] + mult_results[ch][1] + mult_results[ch][2] +
                mult_results[ch][3] + mult_results[ch][4] + mult_results[ch][5] +
                mult_results[ch][6] + mult_results[ch][7] + mult_results[ch][8];
        end else begin : general_sum
            wire [ACC_WIDTH-1:0] partial_sums [0:KERNEL_SIZE*KERNEL_SIZE-1];
            assign partial_sums[0] = mult_results[ch][0];
            for (k_idx = 1; k_idx < KERNEL_SIZE*KERNEL_SIZE; k_idx = k_idx + 1) begin : acc_gen
                assign partial_sums[k_idx] = partial_sums[k_idx-1] + mult_results[ch][k_idx];
            end
            assign channel_sums[ch] = partial_sums[KERNEL_SIZE*KERNEL_SIZE-1];
        end
    end
endgenerate

// 跨通道累加 - 组合逻辑
generate
    if (IN_CHANNEL == 3) begin : channel3_sum
        assign total_sum = channel_sums[0] + channel_sums[1] + channel_sums[2];
    end else begin : general_channel_sum
        wire [ACC_WIDTH-1:0] channel_partial_sums [0:IN_CHANNEL-1];
        assign channel_partial_sums[0] = channel_sums[0];
        for (c_idx = 1; c_idx < IN_CHANNEL; c_idx = c_idx + 1) begin : ch_acc_gen
            assign channel_partial_sums[c_idx] = channel_partial_sums[c_idx-1] + channel_sums[c_idx];
        end
        assign total_sum = channel_partial_sums[IN_CHANNEL-1];
    end
endgenerate

// 输出逻辑 - 组合逻辑
assign conv_valid = window_valid && weight_valid;
assign conv_out = conv_valid ? saturate(total_sum) : {OUTPUT_WIDTH{1'b0}};

// 饱和处理函数（组合逻辑）- UNSIGNED
function [OUTPUT_WIDTH-1:0] saturate;
    input [ACC_WIDTH-1:0] value; // UNSIGNED
    localparam [ACC_WIDTH-1:0] MAX_UNSIGNED_VAL_SAT = (1 << OUTPUT_WIDTH) - 1;
    // MIN_UNSIGNED_VAL is 0
    begin
        if (value > MAX_UNSIGNED_VAL_SAT)
            saturate = MAX_UNSIGNED_VAL_SAT[OUTPUT_WIDTH-1:0]; // 使用OUTPUT_WIDTH进行截取
        else
            saturate = value[OUTPUT_WIDTH-1:0]; // 使用OUTPUT_WIDTH进行截取
    end
endfunction

endmodule