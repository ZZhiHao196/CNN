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
    output reg [NUM_FILTERS*DATA_WIDTH-1:0] conv_out,
    output reg conv_valid
);

// 内部信号声明
// 状态机
reg [1:0] current_state, next_state;
localparam IDLE = 2'b00;
localparam PROCESSING = 2'b01;
localparam OUTPUT = 2'b10;

// 分离的通道输入信号
reg [DATA_WIDTH-1:0] channel_pixels [0:IN_CHANNEL-1];
reg [DATA_WIDTH-1:0] channel_pixels_reg [0:IN_CHANNEL-1];

// 窗口模块信号 (为每个通道实例化)
wire [KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] window_out [0:IN_CHANNEL-1];
wire window_valid [0:IN_CHANNEL-1];
reg all_windows_valid;

// 权重模块信号 (为每个滤波器实例化)
wire [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] filter_weights [0:NUM_FILTERS-1];
wire filter_weight_valid [0:NUM_FILTERS-1];

// 多通道乘累加模块信号 (为每个滤波器实例化)
wire [DATA_WIDTH-1:0] filter_conv_out [0:NUM_FILTERS-1];
wire filter_conv_valid [0:NUM_FILTERS-1];
reg [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] multi_channel_window;

// 循环变量
integer i, j;

// 输入数据解包 - 将并行输入分离到各个通道
always @(*) begin
    for (i = 0; i < IN_CHANNEL; i = i + 1) begin
        channel_pixels[i] = pixel_in[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH];
    end
end

// 输入数据寄存
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < IN_CHANNEL; i = i + 1) begin
            channel_pixels_reg[i] <= 0;
        end
    end else if (pixel_valid) begin
        for (i = 0; i < IN_CHANNEL; i = i + 1) begin
            channel_pixels_reg[i] <= channel_pixels[i];
        end
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
            .pixel_in(channel_pixels_reg[ch]),
            .pixel_valid(pixel_valid),
            .frame_start(frame_start),
            .window_out(window_out[ch]),
            .window_valid(window_valid[ch])
        );
    end
endgenerate

// 为每个滤波器实例化权重模块
genvar filt;
generate
    for (filt = 0; filt < NUM_FILTERS; filt = filt + 1) begin : weight_gen
        weight_parallel #(
            .NUM_FILTERS(NUM_FILTERS),
            .INPUT_CHANNELS(IN_CHANNEL),
            .KERNEL_SIZE(KERNEL_SIZE),
            .WEIGHT_WIDTH(WEIGHT_WIDTH),
            .FILTER_ID(filt),
            .INIT_FILE("weights.mem")
        ) weight_inst (
            .clk(clk),
            .rst_n(rst_n),
            .read_enable(all_windows_valid),
            .multi_channel_weight_out(filter_weights[filt]),
            .weight_valid(filter_weight_valid[filt])
        );
    end
endgenerate

// 为每个滤波器实例化多通道乘累加模块
genvar f;
generate
    for (f = 0; f < NUM_FILTERS; f = f + 1) begin : mult_acc_gen
        mult_acc_multi_channel #(
            .DATA_WIDTH(DATA_WIDTH),
            .KERNEL_SIZE(KERNEL_SIZE),
            .IN_CHANNEL(IN_CHANNEL),
            .WEIGHT_WIDTH(WEIGHT_WIDTH),
            .ACC_WIDTH(ACC_WIDTH)
        ) mult_acc_inst (
            .clk(clk),
            .rst_n(rst_n),
            .window_valid(all_windows_valid),
            .multi_channel_window_in(multi_channel_window),
            .weight_valid(filter_weight_valid[f]),
            .multi_channel_weight_in(filter_weights[f]),
            .conv_out(filter_conv_out[f]),
            .conv_valid(filter_conv_valid[f])
        );
    end
endgenerate

// 检查所有通道窗口是否都有效
always @(*) begin
    all_windows_valid = 1;
    for (i = 0; i < IN_CHANNEL; i = i + 1) begin
        all_windows_valid = all_windows_valid & window_valid[i];
    end
end

// 打包多通道窗口数据
always @(*) begin
    multi_channel_window = 0;
    for (i = 0; i < IN_CHANNEL; i = i + 1) begin
        multi_channel_window[(i+1)*KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1 -: KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH] = window_out[i];
    end
end

// 状态机时序逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        current_state <= IDLE;
    else
        current_state <= next_state;
end

// 状态机组合逻辑
always @(*) begin
    case (current_state)
        IDLE: 
            next_state = frame_start ? PROCESSING : IDLE;
        PROCESSING:
            next_state = filter_conv_valid[0] ? OUTPUT : PROCESSING;  // 使用第一个滤波器作为参考
        OUTPUT:
            next_state = all_windows_valid ? PROCESSING : IDLE;
        default:
            next_state = IDLE;
    endcase
end

// 输出逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        conv_out <= 0;
        conv_valid <= 0;
    end else begin
        // 当所有滤波器都有有效输出时，打包输出
        if (current_state == OUTPUT && filter_conv_valid[0]) begin
            // 检查所有滤波器是否都有有效输出
            if (filter_conv_valid[0] && filter_conv_valid[1] && filter_conv_valid[2]) begin
                // 打包所有滤波器的输出
                for (i = 0; i < NUM_FILTERS; i = i + 1) begin
                    conv_out[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH] <= filter_conv_out[i];
                end
                conv_valid <= 1;
            end else begin
                conv_valid <= 0;
            end
        end else begin
            conv_valid <= 0;
        end
    end
end

endmodule 