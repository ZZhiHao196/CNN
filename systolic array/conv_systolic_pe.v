// Systolic Array Processing Element (PE)
// 实现基本的乘法累加运算单元
module systolic_pe #(
    parameter DATA_WIDTH = 16,
    parameter WEIGHT_WIDTH = 8,
    parameter ACCUM_WIDTH = 32
)
(
    input wire clk,
    input wire rst_n,
    input wire enable,
    
    // 数据输入（从左侧PE或外部输入）
    input wire [DATA_WIDTH-1:0] data_in,
    input wire data_valid_in,
    
    // 权重输入（从上方PE或外部输入）
    input wire [WEIGHT_WIDTH-1:0] weight_in,
    input wire weight_valid_in,
    
    // 部分和输入（从左侧PE）
    input wire [ACCUM_WIDTH-1:0] partial_sum_in,
    input wire partial_sum_valid_in,
    
    // 数据输出（传递到右侧PE）
    output reg [DATA_WIDTH-1:0] data_out,
    output reg data_valid_out,
    
    // 权重输出（传递到下方PE）
    output reg [WEIGHT_WIDTH-1:0] weight_out,
    output reg weight_valid_out,
    
    // 部分和输出（传递到右侧PE）
    output reg [ACCUM_WIDTH-1:0] partial_sum_out,
    output reg partial_sum_valid_out
);

// 内部寄存器
reg [DATA_WIDTH-1:0] data_reg;
reg [WEIGHT_WIDTH-1:0] weight_reg;
reg [ACCUM_WIDTH-1:0] accum_reg;
reg data_valid_reg, weight_valid_reg, partial_sum_valid_reg;

// 乘法结果
wire signed [DATA_WIDTH+WEIGHT_WIDTH-1:0] mult_result;
assign mult_result = $signed(data_reg) * $signed(weight_reg);

// 主要计算逻辑
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        data_reg <= 0;
        weight_reg <= 0;
        accum_reg <= 0;
        data_valid_reg <= 0;
        weight_valid_reg <= 0;
        partial_sum_valid_reg <= 0;
    end else if(enable) begin
        // 寄存输入数据和权重
        data_reg <= data_in;
        weight_reg <= weight_in;
        data_valid_reg <= data_valid_in;
        weight_valid_reg <= weight_valid_in;
        partial_sum_valid_reg <= partial_sum_valid_in;
        
        // 执行乘法累加
        if(data_valid_in && weight_valid_in) begin
            if(partial_sum_valid_in) begin
                // 累加到输入的部分和
                accum_reg <= partial_sum_in + mult_result;
            end else begin
                // 开始新的累加
                accum_reg <= mult_result;
            end
        end else if(partial_sum_valid_in) begin
            // 只传递部分和，不进行乘法
            accum_reg <= partial_sum_in;
        end
    end
end

// 输出逻辑
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        data_out <= 0;
        weight_out <= 0;
        partial_sum_out <= 0;
        data_valid_out <= 0;
        weight_valid_out <= 0;
        partial_sum_valid_out <= 0;
    end else if(enable) begin
        // 传递数据到右侧
        data_out <= data_reg;
        data_valid_out <= data_valid_reg;
        
        // 传递权重到下方
        weight_out <= weight_reg;
        weight_valid_out <= weight_valid_reg;
        
        // 传递累加结果到右侧
        partial_sum_out <= accum_reg;
        partial_sum_valid_out <= (data_valid_reg && weight_valid_reg) || partial_sum_valid_reg;
    end
end

endmodule 