// 并行权重ROM模块 - 为特定滤波器输出所有通道的权重
module weight #(
    parameter NUM_FILTERS = 3,
    parameter INPUT_CHANNELS = 3,
    parameter KERNEL_SIZE = 3,
    parameter WEIGHT_WIDTH = 8,
    parameter FILTER_ID = 0,  // 当前滤波器ID
    parameter INIT_FILE = "weights.mem"
)
(
    input clk,
    input rst_n,

    // 权重读取接口
    input read_enable, // 读取使能

    // 多通道权重输出 - 输出当前滤波器的所有通道权重
    output reg [INPUT_CHANNELS*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] multi_channel_weight_out,
    output reg weight_valid // 权重有效
);

// 计算总的权重数量和地址位宽
localparam TOTAL_WEIGHTS = NUM_FILTERS * INPUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE;
localparam WEIGHTS_PER_CHANNEL = KERNEL_SIZE * KERNEL_SIZE; // 一个通道filter的权重数量
localparam WEIGHTS_PER_FILTER = INPUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE; // 一个filter的总权重数量
localparam ADDR_WIDTH = $clog2(TOTAL_WEIGHTS);

// 权重ROM存储器
reg [WEIGHT_WIDTH-1:0] weight_memory [0:TOTAL_WEIGHTS-1];

// 初始化变量
integer init_i;

// 读取相关信号
reg reading_weights;
integer read_idx;
reg [ADDR_WIDTH-1:0] base_addr;

// 初始化权重ROM
initial begin
    if(INIT_FILE != "") begin
        $readmemh(INIT_FILE, weight_memory);
        $display("Weight ROM (Filter %0d): Loaded weights from %s", FILTER_ID, INIT_FILE);
    end else begin
        for(init_i = 0; init_i < TOTAL_WEIGHTS; init_i = init_i + 1) begin
            weight_memory[init_i] = 0;
        end
        $display("Weight ROM (Filter %0d): Initialized with zeros", FILTER_ID);
    end
end

// 权重的读取逻辑
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        multi_channel_weight_out <= 0;
        weight_valid <= 0;
        reading_weights <= 0;
        read_idx <= 0;
        base_addr <= 0;
    end else begin
        if(read_enable && !reading_weights && !weight_valid) begin
            reading_weights <= 1;
            read_idx <= 0;
            weight_valid <= 0;
            // 计算当前滤波器的基地址
            base_addr <= FILTER_ID * WEIGHTS_PER_FILTER;
        end else if(reading_weights) begin
            // 逐个读取当前滤波器所有通道的权重并打包
            if(read_idx < WEIGHTS_PER_FILTER) begin
                multi_channel_weight_out[(read_idx+1)*WEIGHT_WIDTH-1 -: WEIGHT_WIDTH] <=
                    weight_memory[base_addr + read_idx];
                read_idx <= read_idx + 1;
            end else begin
                // 读取完成
                reading_weights <= 0;
                weight_valid <= 1;
                read_idx <= 0;
            end
        end else if(!read_enable) begin
            weight_valid <= 0;
        end
    end
end

endmodule 