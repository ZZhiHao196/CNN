module conv #(
    parameter DATA_WIDTH = 8,
    parameter KERNEL_SIZE = 3,
    parameter IN_CHANNEL = 3,
    parameter NUM_FILTERS = 3,
    parameter IMG_WIDTH = 32,
    parameter IMG_HEIGHT = 32,
    parameter STRIDE = 1,
    parameter PADDING = (KERNEL_SIZE - 1) / 2,
    parameter WEIGHT_WIDTH = 8,
    parameter ACC_WIDTH = 2*DATA_WIDTH + 4
)
(
    // 全局信号
    input clk,
    input rst_n,

    // 并行输入数据接口 - 同时输入所有通道
    input [IN_CHANNEL*DATA_WIDTH-1:0] pixel_in,  // 所有通道并行输入
    input pixel_valid,
    input frame_start,

    // 并行输出数据接口 - 同时输出所有滤波器结果
    output [NUM_FILTERS*DATA_WIDTH-1:0] conv_out,
    output conv_valid
);

// 分离的通道输入信号
reg [DATA_WIDTH-1:0] channel_pixels [0:IN_CHANNEL-1];

// 窗口模块信号 (为每个通道实例化)
wire [KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] window_out [0:IN_CHANNEL-1];
wire window_valid [0:IN_CHANNEL-1];
wire all_windows_valid;

// 权重模块信号 (为每个滤波器实例化) - 预加载权重
wire [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] filter_weights [0:NUM_FILTERS-1];
wire filter_weight_valid [0:NUM_FILTERS-1];
wire all_weights_valid;

// 多通道乘累加模块信号 (为每个滤波器实例化)
wire [DATA_WIDTH-1:0] filter_conv_out [0:NUM_FILTERS-1];
wire filter_conv_valid [0:NUM_FILTERS-1];
wire [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] multi_channel_window;

// 循环变量
integer i;

// 输入数据解包 - 将并行输入分离到各个通道
always @(*) begin
    for (i = 0; i < IN_CHANNEL; i = i + 1) begin
        channel_pixels[i] = pixel_in[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH];
    end
end

// 为每个输入通道实例化窗口模块
genvar ch;
generate
    for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin : window_gen
        window #(
            .DATA_WIDTH(DATA_WIDTH),
            .IMG_WIDTH(IMG_WIDTH),
            .IMG_HEIGHT(IMG_HEIGHT),
            .KERNEL_SIZE(KERNEL_SIZE),
            .STRIDE(STRIDE),
            .PADDING(PADDING)
        ) window_inst (
            .clk(clk),
            .rst_n(rst_n),
            .pixel_in(channel_pixels[ch]),
            .pixel_valid(pixel_valid),
            .frame_start(frame_start),
            .window_out(window_out[ch]),
            .window_valid(window_valid[ch])
        );
    end
endgenerate

// 为每个滤波器实例化权重模块 - 始终启用读取
genvar filt;
generate
    for (filt = 0; filt < NUM_FILTERS; filt = filt + 1) begin : weight_gen
        weight #(
            .NUM_FILTERS(NUM_FILTERS),
            .INPUT_CHANNELS(IN_CHANNEL),
            .KERNEL_SIZE(KERNEL_SIZE),
            .WEIGHT_WIDTH(WEIGHT_WIDTH),
            .FILTER_ID(filt),
            .INIT_FILE("weights.mem")
        ) weight_inst (
            .clk(clk),
            .rst_n(rst_n),
            .read_enable(1'b1),  // 始终启用读取
            .multi_channel_weight_out(filter_weights[filt]),
            .weight_valid(filter_weight_valid[filt])
        );
    end
endgenerate

// 为每个滤波器实例化多通道乘累加模块
genvar f;
generate
    for (f = 0; f < NUM_FILTERS; f = f + 1) begin : mult_acc_gen
        mult_acc_comb #(
            .DATA_WIDTH(DATA_WIDTH),
            .KERNEL_SIZE(KERNEL_SIZE),
            .IN_CHANNEL(IN_CHANNEL),
            .WEIGHT_WIDTH(WEIGHT_WIDTH),
            .ACC_WIDTH(ACC_WIDTH)
        ) mult_acc_inst (
            .window_valid(all_windows_valid),
            .multi_channel_window_in(multi_channel_window),
            .weight_valid(all_weights_valid),
            .multi_channel_weight_in(filter_weights[f]),
            .conv_out(filter_conv_out[f]),
            .conv_valid(filter_conv_valid[f])
        );
    end
endgenerate

// 检查所有通道窗口是否都有效 - 组合逻辑
assign all_windows_valid = window_valid[0] & window_valid[1] & window_valid[2];

// 检查所有权重是否都有效 - 组合逻辑
assign all_weights_valid = filter_weight_valid[0] & filter_weight_valid[1] & filter_weight_valid[2];

// 打包多通道窗口数据 - 组合逻辑
assign multi_channel_window = {window_out[2], window_out[1], window_out[0]};

// 输出逻辑 - 组合逻辑，立即输出
assign conv_valid = all_windows_valid & all_weights_valid;
assign conv_out = {filter_conv_out[2], filter_conv_out[1], filter_conv_out[0]};

endmodule 