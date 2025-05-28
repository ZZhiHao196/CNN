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
    parameter OUTPUT_WIDTH = 20,  // 增加输出位宽，避免饱和
    parameter ACC_WIDTH = 2*DATA_WIDTH + 4 + $clog2(KERNEL_SIZE*KERNEL_SIZE*IN_CHANNEL),
    parameter INIT_FILE = "weights.mem"
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
    output [NUM_FILTERS*OUTPUT_WIDTH-1:0] conv_out,
    output conv_valid
);

// 计算权重存储所需的参数
localparam TOTAL_WEIGHTS = NUM_FILTERS * IN_CHANNEL * KERNEL_SIZE * KERNEL_SIZE;
localparam WEIGHTS_PER_FILTER = IN_CHANNEL * KERNEL_SIZE * KERNEL_SIZE;

// 分离的通道输入信号
reg [DATA_WIDTH-1:0] channel_pixels [0:IN_CHANNEL-1];

// 窗口模块信号 (为每个通道实例化)
wire [KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] window_out [0:IN_CHANNEL-1];
wire window_valid [0:IN_CHANNEL-1];
wire all_windows_valid;

// 权重模块接口信号
wire [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] weight_rom_out [0:NUM_FILTERS-1];
wire weight_rom_valid [0:NUM_FILTERS-1];
reg [NUM_FILTERS-1:0] weight_read_enable;

// 权重寄存器 - 从weight模块加载后存储
reg [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] filter_weights [0:NUM_FILTERS-1];
reg weights_loaded;

// 权重加载状态机
reg [1:0] weight_load_state;
reg [NUM_FILTERS-1:0] weight_loaded_flags;
localparam WEIGHT_IDLE = 2'b00, WEIGHT_LOADING = 2'b01, WEIGHT_DONE = 2'b10;

// 多通道乘累加模块信号 (为每个滤波器实例化)
wire [OUTPUT_WIDTH-1:0] filter_conv_out [0:NUM_FILTERS-1];
wire filter_conv_valid [0:NUM_FILTERS-1];
wire [IN_CHANNEL*KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] multi_channel_window;

// 循环变量
integer i, load_idx;

// 权重加载状态机 - 从weight模块一次性加载权重到寄存器
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        weight_load_state <= WEIGHT_IDLE;
        weight_read_enable <= 0;
        weight_loaded_flags <= 0;
        weights_loaded <= 0;
        for (load_idx = 0; load_idx < NUM_FILTERS; load_idx = load_idx + 1) begin
            filter_weights[load_idx] <= 0;
        end
    end else begin
        case (weight_load_state)
            WEIGHT_IDLE: begin
                // 开始加载权重
                weight_read_enable <= {NUM_FILTERS{1'b1}}; // 启用所有滤波器的权重读取
                weight_load_state <= WEIGHT_LOADING;
                weights_loaded <= 0;
            end
            
            WEIGHT_LOADING: begin
                // 检查每个滤波器的权重是否加载完成
                for (load_idx = 0; load_idx < NUM_FILTERS; load_idx = load_idx + 1) begin
                    if (weight_rom_valid[load_idx] && !weight_loaded_flags[load_idx]) begin
                        // 将权重从ROM复制到寄存器
                        filter_weights[load_idx] <= weight_rom_out[load_idx];
                        weight_loaded_flags[load_idx] <= 1;
                        $display("Conv: Loaded weights for filter %0d", load_idx);
                    end
                end
                
                // 检查是否所有权重都已加载
                if (&weight_loaded_flags) begin
                    weight_read_enable <= 0; // 停止读取
                    weight_load_state <= WEIGHT_DONE;
                    weights_loaded <= 1;
                    $display("Conv: All weights loaded to registers - ROM access no longer needed");
                end
            end
            
            WEIGHT_DONE: begin
                // 权重加载完成，保持状态
                weights_loaded <= 1;
            end
            
            default: begin
                weight_load_state <= WEIGHT_IDLE;
            end
        endcase
    end
end

// 权重已经直接存储为展平格式，无需额外打包逻辑

// 输入数据解包 - 将并行输入分离到各个通道
always @(*) begin
    for (i = 0; i < IN_CHANNEL; i = i + 1) begin
        channel_pixels[i] = pixel_in[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH];
    end
end

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
            .INIT_FILE(INIT_FILE)
        ) weight_inst (
            .clk(clk),
            .rst_n(rst_n),
            .read_enable(weight_read_enable[filt]),
            .multi_channel_weight_out(weight_rom_out[filt]),
            .weight_valid(weight_rom_valid[filt])
        );
    end
endgenerate

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

// 为每个滤波器实例化多通道乘累加模块
genvar f;
generate
    for (f = 0; f < NUM_FILTERS; f = f + 1) begin : mult_acc_gen
        mult_acc_comb #(
            .DATA_WIDTH(DATA_WIDTH),
            .KERNEL_SIZE(KERNEL_SIZE),
            .IN_CHANNEL(IN_CHANNEL),
            .WEIGHT_WIDTH(WEIGHT_WIDTH),
            .OUTPUT_WIDTH(OUTPUT_WIDTH),
            .ACC_WIDTH(ACC_WIDTH)
        ) mult_acc_inst (
            .window_valid(all_windows_valid),
            .multi_channel_window_in(multi_channel_window),
            .weight_valid(weights_loaded),  // 权重始终有效（已加载到寄存器）
            .multi_channel_weight_in(filter_weights[f]),
            .conv_out(filter_conv_out[f]),
            .conv_valid(filter_conv_valid[f])
        );
    end
endgenerate

// 检查所有通道窗口是否都有效 - 组合逻辑
assign all_windows_valid = window_valid[0] & window_valid[1] & window_valid[2];

// 打包多通道窗口数据 - 组合逻辑
assign multi_channel_window = {window_out[2], window_out[1], window_out[0]};

// 输出逻辑 - 组合逻辑，权重始终有效，只需检查窗口有效性
assign conv_valid = all_windows_valid & weights_loaded;
assign conv_out = {filter_conv_out[2], filter_conv_out[1], filter_conv_out[0]};

endmodule 