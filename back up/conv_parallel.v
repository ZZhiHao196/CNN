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
reg [2:0] current_state, next_state;
localparam IDLE = 3'b000;
localparam PROCESSING = 3'b001;
localparam LOAD_WEIGHTS = 3'b010;
localparam COMPUTE = 3'b011;
localparam OUTPUT = 3'b100;

// 分离的通道输入信号
reg [DATA_WIDTH-1:0] channel_pixels [0:IN_CHANNEL-1];

// 窗口模块信号 (为每个通道实例化)
wire [KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] window_out [0:IN_CHANNEL-1];
wire window_valid [0:IN_CHANNEL-1];
reg all_windows_valid;
reg all_windows_valid_reg;

// 权重模块信号 (为每个滤波器实例化)
wire [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] filter_weights [0:NUM_FILTERS-1];
wire filter_weight_valid [0:NUM_FILTERS-1];
reg weight_read_enable;
reg all_weights_valid;
reg all_weights_loaded;

// 多通道乘累加模块信号 (为每个滤波器实例化)
wire [DATA_WIDTH-1:0] filter_conv_out [0:NUM_FILTERS-1];
wire filter_conv_valid [0:NUM_FILTERS-1];
reg [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] multi_channel_window;
reg all_conv_valid;

// 循环变量
integer i, j;

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

// 为每个滤波器实例化权重模块
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
            .read_enable(weight_read_enable),
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
            .window_valid(all_windows_valid && all_weights_loaded),
            .multi_channel_window_in(multi_channel_window),
            .weight_valid(all_weights_loaded),
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

// 检查所有权重是否都有效
always @(*) begin
    all_weights_valid = 1;
    for (i = 0; i < NUM_FILTERS; i = i + 1) begin
        all_weights_valid = all_weights_valid & filter_weight_valid[i];
    end
end

// 检查所有卷积结果是否都有效
always @(*) begin
    all_conv_valid = 1;
    for (i = 0; i < NUM_FILTERS; i = i + 1) begin
        all_conv_valid = all_conv_valid & filter_conv_valid[i];
    end
end

// 寄存窗口有效信号
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        all_windows_valid_reg <= 0;
    end else begin
        all_windows_valid_reg <= all_windows_valid;
    end
end

// 权重加载完成锁存
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        all_weights_loaded <= 0;
    end else begin
        if (current_state == LOAD_WEIGHTS && all_weights_valid) begin
            all_weights_loaded <= 1;
        end else if (current_state == IDLE) begin
            all_weights_loaded <= 0;
        end
    end
end

// 打包多通道窗口数据
always @(*) begin
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
            next_state = all_windows_valid ? LOAD_WEIGHTS : PROCESSING;
        LOAD_WEIGHTS:
            next_state = all_weights_loaded ? COMPUTE : LOAD_WEIGHTS;
        COMPUTE:
            next_state = all_windows_valid ? COMPUTE : IDLE; // Stay in compute while windows are valid
        OUTPUT:
            next_state = IDLE;
        default:
            next_state = IDLE;
    endcase
end

// 权重读取控制
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        weight_read_enable <= 0;
    end else begin
        case (current_state)
            LOAD_WEIGHTS:
                if (!all_weights_valid && !weight_read_enable) begin
                    weight_read_enable <= 1;  // Start reading weights
                end else if (all_weights_valid) begin
                    weight_read_enable <= 0;  // Stop reading when all valid
                end
            default:
                weight_read_enable <= 0;
        endcase
    end
end

// 输出逻辑 - 组合逻辑，立即输出
always @(*) begin
    if (current_state == COMPUTE && all_conv_valid) begin
        // 打包所有滤波器的输出
        for (i = 0; i < NUM_FILTERS; i = i + 1) begin
            conv_out[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH] = filter_conv_out[i];
        end
        conv_valid = 1;
    end else begin
        conv_out = 0;
        conv_valid = 0;
    end
end

endmodule 