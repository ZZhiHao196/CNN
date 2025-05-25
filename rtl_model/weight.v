 // CNN weight ROM module
// 用于存储CNN卷积层权重ROM模块
// 存储该层的所有预设参数，返回指定通道和filter的权重
module weight #(
    parameter NUM_FILTERS = 3,
    parameter INPUT_CHANNELS = 3,
    parameter KERNEL_SIZE = 3,
    parameter WEIGHT_WIDTH = 16,
    parameter INIT_FILE = "weights.mem"
)
(
    input clk,
    input rst_n,

    //权重读取接口
    input [$clog2(NUM_FILTERS)-1:0] filter_idx, //滤波器索引
    input [$clog2(INPUT_CHANNELS)-1:0] channel_idx, //通道索引
    input read_enable, //读取使能

    //权重输出
    output reg [KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] flattened_weight_out, //权重输出
    output reg weight_valid //权重有效
);

// 计算总的权重数量和地址位宽
localparam TOTAL_WEIGHTS = NUM_FILTERS * INPUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE;
localparam WEIGHTS_PER_CHANNEL = KERNEL_SIZE * KERNEL_SIZE; // 一个通道filter 的权重数量
localparam WEIGHTS_PER_FILTER = INPUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE; //filter idx 为特定数目的filter 有INPUT_CHANNELS个
localparam ADDR_WIDTH = $clog2(TOTAL_WEIGHTS);

//权重ROM存储器
reg [WEIGHT_WIDTH-1:0] weight_memory [0:TOTAL_WEIGHTS-1];

//初始化变量
integer init_i;

//读取相关信号
reg [$clog2(NUM_FILTERS)-1:0] current_filter_idx;
reg [$clog2(INPUT_CHANNELS)-1:0] current_channel_idx;
reg reading_weights;
integer read_idx;
reg [ADDR_WIDTH-1:0] base_addr;

//初始化权重ROM
initial begin
    if(INIT_FILE != "") begin
        $readmemh(INIT_FILE, weight_memory);
        $display("Weight ROM: Loaded weights from %s", INIT_FILE);
    end else begin
        for(init_i = 0; init_i < TOTAL_WEIGHTS; init_i = init_i + 1) begin
            weight_memory[init_i] = 0;
        end
        $display("Weight ROM: Initialized with zeros");
    end
end

//权重的读取逻辑
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        flattened_weight_out <= 0;
        weight_valid <= 0;
        current_filter_idx <= 0;
        current_channel_idx <= 0;
        reading_weights <= 0;
        read_idx <= 0;
        base_addr <= 0;
    end else begin
        if(read_enable && !reading_weights)begin
            current_filter_idx <= filter_idx;
            current_channel_idx <= channel_idx;
            reading_weights <= 1;
            read_idx <= 0;
            weight_valid <= 0;
            //计算基地址
            base_addr <= filter_idx*WEIGHTS_PER_FILTER + channel_idx*WEIGHTS_PER_CHANNEL;
        end else if(reading_weights) begin
           //逐个读取权重并打包
           if(read_idx < WEIGHTS_PER_CHANNEL)begin
                flattened_weight_out[(read_idx+1)*WEIGHT_WIDTH-1-:WEIGHT_WIDTH] <=
                    weight_memory[base_addr+read_idx];
                read_idx <= read_idx + 1;
           end else begin
            //读取完成
            reading_weights <= 0;
            weight_valid <= 1;
            read_idx <= 0;
           end
        end else if(!read_enable)begin
            weight_valid <= 0;
        end
    end
end

endmodule