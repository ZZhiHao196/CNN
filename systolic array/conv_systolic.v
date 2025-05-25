// Systolic Array Based Convolution Module
// 使用Systolic Array优化的卷积运算模块
module conv_systolic #(
    parameter DATA_WIDTH = 16,             // Width of each pixel data
    parameter KERNEL_SIZE = 3,             // Size of convolution kernel (square)
    parameter WEIGHT_WIDTH = 8,            // Width of each weight data
    parameter OUTPUT_WIDTH = 32,           // Width of output data (to accommodate accumulation)
    parameter NUM_FILTERS = 1              // Number of convolution filters
)
(
    input wire clk,                        // Clock signal
    input wire rst_n,                      // Active low reset
    
    // Interface with window module
    input wire [KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] window_in,  // Flattened window input from window module
    input wire window_valid,               // Window data valid signal
    
    // Convolution kernel weights (can be loaded externally)
    input wire [NUM_FILTERS*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] weights, // Flattened weights for all filters
    input wire weights_valid,              // Weights valid signal
    
    // Optional bias
    input wire [NUM_FILTERS*OUTPUT_WIDTH-1:0] bias,  // Bias values for each filter
    input wire bias_enable,                // Enable bias addition
    
    // Output interface
    output reg [NUM_FILTERS*OUTPUT_WIDTH-1:0] conv_out,  // Convolution output for all filters
    output reg conv_valid                  // Convolution result valid
);

// Systolic Array实例化信号
wire [OUTPUT_WIDTH-1:0] systolic_results [0:NUM_FILTERS-1];
wire systolic_valid [0:NUM_FILTERS-1];
reg [OUTPUT_WIDTH-1:0] filter_bias [0:NUM_FILTERS-1];

// 解包偏置数据
integer f;
always @(*) begin
    for(f = 0; f < NUM_FILTERS; f = f + 1) begin
        filter_bias[f] = bias[(f+1)*OUTPUT_WIDTH-1 -: OUTPUT_WIDTH];
    end
end

// 为每个滤波器实例化Systolic Array
genvar filter_idx;
generate
    for(filter_idx = 0; filter_idx < NUM_FILTERS; filter_idx = filter_idx + 1) begin : systolic_filter
        
        // 提取当前滤波器的权重
        wire [KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] current_filter_weights;
        assign current_filter_weights = weights[(filter_idx+1)*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1 -: KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH];
        
        // 实例化Systolic Array (简化版本，直接计算)
        systolic_array_simple #(
            .DATA_WIDTH(DATA_WIDTH),
            .WEIGHT_WIDTH(WEIGHT_WIDTH),
            .OUTPUT_WIDTH(OUTPUT_WIDTH)
        ) systolic_inst (
            .clk(clk),
            .rst_n(rst_n),
            .enable(1'b1),
            .window_data(window_in),
            .window_valid(window_valid),
            .weights(current_filter_weights),
            .weights_valid(weights_valid),
            .conv_result(systolic_results[filter_idx]),
            .result_valid(systolic_valid[filter_idx])
        );
    end
endgenerate

// 输出处理和偏置加法
reg [OUTPUT_WIDTH-1:0] final_results [0:NUM_FILTERS-1];
reg final_valid;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        final_valid <= 0;
        for(f = 0; f < NUM_FILTERS; f = f + 1) begin
            final_results[f] <= 0;
        end
    end else begin
        // 检查所有滤波器是否都有有效结果
        final_valid <= systolic_valid[0]; // 假设所有滤波器同步
        
        for(f = 0; f < NUM_FILTERS; f = f + 1) begin
            if(systolic_valid[f]) begin
                if(bias_enable) begin
                    final_results[f] <= systolic_results[f] + $signed(filter_bias[f]);
                end else begin
                    final_results[f] <= systolic_results[f];
                end
            end
        end
    end
end

// 打包输出数据
always @(*) begin
    conv_valid = final_valid;
    for(f = 0; f < NUM_FILTERS; f = f + 1) begin
        conv_out[(f+1)*OUTPUT_WIDTH-1 -: OUTPUT_WIDTH] = final_results[f];
    end
end

endmodule

// 简化的Systolic Array实现 (单滤波器)
module systolic_array_simple #(
    parameter DATA_WIDTH = 16,
    parameter WEIGHT_WIDTH = 8,
    parameter OUTPUT_WIDTH = 32
)
(
    input wire clk,
    input wire rst_n,
    input wire enable,
    
    input wire [9*DATA_WIDTH-1:0] window_data,
    input wire window_valid,
    input wire [9*WEIGHT_WIDTH-1:0] weights,
    input wire weights_valid,
    
    output reg [OUTPUT_WIDTH-1:0] conv_result,
    output reg result_valid
);

// 解包数据和权重
wire [DATA_WIDTH-1:0] data [0:8];
wire [WEIGHT_WIDTH-1:0] weight [0:8];

genvar i;
generate
    for(i = 0; i < 9; i = i + 1) begin : unpack
        assign data[i] = window_data[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH];
        assign weight[i] = weights[(i+1)*WEIGHT_WIDTH-1 -: WEIGHT_WIDTH];
    end
endgenerate

// Systolic Array计算 - 并行乘法累加
reg signed [DATA_WIDTH+WEIGHT_WIDTH-1:0] products [0:8];
reg signed [OUTPUT_WIDTH-1:0] sum;
reg valid_d1, valid_d2;

// 第一级：并行乘法
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        valid_d1 <= 0;
        products[0] <= 0; products[1] <= 0; products[2] <= 0;
        products[3] <= 0; products[4] <= 0; products[5] <= 0;
        products[6] <= 0; products[7] <= 0; products[8] <= 0;
    end else if(enable) begin
        valid_d1 <= window_valid && weights_valid;
        if(window_valid && weights_valid) begin
            products[0] <= $signed(data[0]) * $signed(weight[0]);
            products[1] <= $signed(data[1]) * $signed(weight[1]);
            products[2] <= $signed(data[2]) * $signed(weight[2]);
            products[3] <= $signed(data[3]) * $signed(weight[3]);
            products[4] <= $signed(data[4]) * $signed(weight[4]);
            products[5] <= $signed(data[5]) * $signed(weight[5]);
            products[6] <= $signed(data[6]) * $signed(weight[6]);
            products[7] <= $signed(data[7]) * $signed(weight[7]);
            products[8] <= $signed(data[8]) * $signed(weight[8]);
        end
    end
end

// 第二级：累加
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        sum <= 0;
        valid_d2 <= 0;
    end else if(enable) begin
        valid_d2 <= valid_d1;
        if(valid_d1) begin
            sum <= products[0] + products[1] + products[2] + 
                   products[3] + products[4] + products[5] + 
                   products[6] + products[7] + products[8];
        end
    end
end

// 输出
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        conv_result <= 0;
        result_valid <= 0;
    end else begin
        conv_result <= sum;
        result_valid <= valid_d2;
    end
end

endmodule 