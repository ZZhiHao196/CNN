module conv #(
    parameter DATA_WIDTH=8,
    parameter KERNEL_SIZE=3,
    parameter IN_CHANNEL=3,
    parameter NUM_FILTERS=3,
    parameter IMG_WIDTH=32,
    parameter IMG_HEIGHT=32,
    parameter STRIDE=1,
    parameter PADDING= (KERNEL_SIZE - 1) / 2,
    parameter WEIGHT_WIDTH=8,
    parameter ACC_WIDTH=2*DATA_WIDTH+4
)
(
    //全局信号
    input clk,
    input rst_n,

    //输入数据接口
    input [DATA_WIDTH-1:0] pixel_in,
    input pixel_valid,
    input frame_start,
    input [$clog2(IN_CHANNEL)-1:0] channel_idx, // 当前输入通道索引

    //输出数据接口
    output reg [NUM_FILTERS*DATA_WIDTH-1:0] conv_out,
    output reg conv_valid
);

// 内部信号声明
// 状态机
reg [2:0] current_state, next_state;
localparam IDLE = 3'b000;
localparam LOAD_WINDOW = 3'b001; 
localparam PROCESS_FILTERS = 3'b010;
localparam WAIT_RESULT = 3'b011;
localparam OUTPUT_RESULT = 3'b100;

// 计数器
reg [$clog2(IN_CHANNEL)-1:0] channel_counter;
reg [$clog2(NUM_FILTERS)-1:0] filter_counter;
reg [3:0] pipeline_counter; // 用于等待mult_acc流水线结果

// 窗口模块信号 (为每个通道实例化)
wire [KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] window_out [0:IN_CHANNEL-1];
wire window_valid [0:IN_CHANNEL-1];
reg [DATA_WIDTH-1:0] channel_pixel_in [0:IN_CHANNEL-1];
reg channel_pixel_valid [0:IN_CHANNEL-1];

// 权重模块信号
wire [KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] weight_out;
wire weight_valid;
reg weight_read_enable;
reg [$clog2(NUM_FILTERS)-1:0] weight_filter_idx;
reg [$clog2(IN_CHANNEL)-1:0] weight_channel_idx;

// 乘累加模块信号
wire [2*DATA_WIDTH-1:0] mult_acc_out;
wire mult_acc_valid;
reg mult_acc_window_valid;
reg mult_acc_weight_valid;
reg [KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] mult_acc_window_in;
reg [KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] mult_acc_weight_in;

// 累加器 - 为每个滤波器存储跨通道累加结果
reg signed [ACC_WIDTH-1:0] filter_accumulator [0:NUM_FILTERS-1];
reg filter_acc_valid [0:NUM_FILTERS-1];

// 窗口位置跟踪
reg window_position_valid;
reg all_channels_ready;

// 循环变量
integer i;

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
            .pixel_in(channel_pixel_in[ch]),
            .pixel_valid(channel_pixel_valid[ch]),
            .frame_start(frame_start),
            .window_out(window_out[ch]),
            .window_valid(window_valid[ch])
        );
    end
endgenerate

// 权重ROM模块实例化
weight #(
    .NUM_FILTERS(NUM_FILTERS),
    .INPUT_CHANNELS(IN_CHANNEL),
    .KERNEL_SIZE(KERNEL_SIZE),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .INIT_FILE("weights.mem")
) weight_inst (
    .clk(clk),
    .rst_n(rst_n),
    .filter_idx(weight_filter_idx),
    .channel_idx(weight_channel_idx),
    .read_enable(weight_read_enable),
    .flattened_weight_out(weight_out),
    .weight_valid(weight_valid)
);

// 乘累加模块实例化
mult_acc #(
    .DATA_WIDTH(DATA_WIDTH),
    .KERNEL_SIZE(KERNEL_SIZE),
    .ACC_WIDTH(ACC_WIDTH)
) mult_acc_inst (
    .clk(clk),
    .rst_n(rst_n),
    .window_valid(mult_acc_window_valid),
    .window_in(mult_acc_window_in),
    .weight_valid(mult_acc_weight_valid),
    .weight_in(mult_acc_weight_in),
    .conv_out(mult_acc_out),
    .conv_valid(mult_acc_valid)
);

// 输入数据分发到对应通道
always @(*) begin
    for (i = 0; i < IN_CHANNEL; i = i + 1) begin
        if (channel_idx == i) begin
            channel_pixel_in[i] = pixel_in;
            channel_pixel_valid[i] = pixel_valid;
        end else begin
            channel_pixel_in[i] = 0;
            channel_pixel_valid[i] = 0;
        end
    end
end

// 检查所有通道是否都有有效窗口
always @(*) begin
    all_channels_ready = 1;
    for (i = 0; i < IN_CHANNEL; i = i + 1) begin
        all_channels_ready = all_channels_ready & window_valid[i];
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
            next_state = frame_start ? LOAD_WINDOW : IDLE;
        LOAD_WINDOW:
            next_state = all_channels_ready ? PROCESS_FILTERS : LOAD_WINDOW;
        PROCESS_FILTERS:
            next_state = weight_valid ? WAIT_RESULT : PROCESS_FILTERS;
        WAIT_RESULT:
            next_state = (pipeline_counter >= 4) ? OUTPUT_RESULT : WAIT_RESULT;
        OUTPUT_RESULT:
            next_state = (filter_counter >= NUM_FILTERS-1) ? 
                        (all_channels_ready ? PROCESS_FILTERS : LOAD_WINDOW) : PROCESS_FILTERS;
        default:
            next_state = IDLE;
    endcase
end

// 主控制逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        channel_counter <= 0;
        filter_counter <= 0;
        pipeline_counter <= 0;
        weight_read_enable <= 0;
        weight_filter_idx <= 0;
        weight_channel_idx <= 0;
        mult_acc_window_valid <= 0;
        mult_acc_weight_valid <= 0;
        conv_valid <= 0;
        
        for (i = 0; i < NUM_FILTERS; i = i + 1) begin
            filter_accumulator[i] <= 0;
            filter_acc_valid[i] <= 0;
        end
    end else begin
        case (current_state)
            IDLE: begin
                channel_counter <= 0;
                filter_counter <= 0;
                pipeline_counter <= 0;
                conv_valid <= 0;
                weight_read_enable <= 0;
                mult_acc_window_valid <= 0;
                mult_acc_weight_valid <= 0;
                
                for (i = 0; i < NUM_FILTERS; i = i + 1) begin
                    filter_accumulator[i] <= 0;
                    filter_acc_valid[i] <= 0;
                end
            end
            
            LOAD_WINDOW: begin
                conv_valid <= 0;
                if (next_state == PROCESS_FILTERS) begin
                    filter_counter <= 0;
                    channel_counter <= 0;
                end
            end
            
            PROCESS_FILTERS: begin
                if (!weight_read_enable) begin
                    // 开始读取当前滤波器和通道的权重
                    weight_filter_idx <= filter_counter;
                    weight_channel_idx <= channel_counter;
                    weight_read_enable <= 1;
                end else if (weight_valid && !mult_acc_window_valid) begin
                    // 权重准备好，发送到mult_acc
                    mult_acc_window_in <= window_out[channel_counter];
                    mult_acc_weight_in <= weight_out;
                    mult_acc_window_valid <= 1;
                    mult_acc_weight_valid <= 1;
                    weight_read_enable <= 0;
                    pipeline_counter <= 0;
                end else begin
                    mult_acc_window_valid <= 0;
                    mult_acc_weight_valid <= 0;
                end
            end
            
            WAIT_RESULT: begin
                mult_acc_window_valid <= 0;
                mult_acc_weight_valid <= 0;
                pipeline_counter <= pipeline_counter + 1;
            end
            
            OUTPUT_RESULT: begin
                if (mult_acc_valid) begin
                    // 累加当前通道的结果到对应滤波器
                    if (channel_counter == 0) begin
                        filter_accumulator[filter_counter] <= mult_acc_out;
                    end else begin
                        filter_accumulator[filter_counter] <= filter_accumulator[filter_counter] + mult_acc_out;
                    end
                    
                    if (channel_counter >= IN_CHANNEL-1) begin
                        // 当前滤波器的所有通道处理完成
                        filter_acc_valid[filter_counter] <= 1;
                        channel_counter <= 0;
                        
                        if (filter_counter >= NUM_FILTERS-1) begin
                            // 所有滤波器处理完成，输出结果
                            filter_counter <= 0;
                        end else begin
                            filter_counter <= filter_counter + 1;
                        end
                    end else begin
                        channel_counter <= channel_counter + 1;
                    end
                end
            end
        endcase
    end
end

// 输出逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        conv_out <= 0;
        conv_valid <= 0;
    end else begin
        // 当所有滤波器都完成时输出
        if (current_state == OUTPUT_RESULT && filter_counter == NUM_FILTERS-1 && 
            channel_counter == IN_CHANNEL-1 && mult_acc_valid) begin
            
            // 打包所有滤波器的结果
            for (i = 0; i < NUM_FILTERS; i = i + 1) begin
                conv_out[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH] <= filter_accumulator[i][DATA_WIDTH-1:0];
            end
            conv_valid <= 1;
            
            // 清除累加器有效标志
            for (i = 0; i < NUM_FILTERS; i = i + 1) begin
                filter_acc_valid[i] <= 0;
            end
        end else begin
            conv_valid <= 0;
        end
    end
end

endmodule