// 3x3 Systolic Array for Convolution
// 使用9个PE单元实现并行卷积运算
module systolic_array_3x3 #(
    parameter DATA_WIDTH = 16,
    parameter WEIGHT_WIDTH = 8,
    parameter ACCUM_WIDTH = 32
)
(
    input wire clk,
    input wire rst_n,
    input wire enable,
    
    // 窗口数据输入 (扁平化的3x3数据)
    input wire [9*DATA_WIDTH-1:0] window_data_flat,
    input wire window_valid,
    
    // 权重输入 (扁平化的3x3权重)
    input wire [9*WEIGHT_WIDTH-1:0] weights_flat,
    input wire weights_valid,
    
    // 卷积结果输出
    output wire [ACCUM_WIDTH-1:0] conv_result,
    output wire result_valid
);

// 解包输入数据
wire [DATA_WIDTH-1:0] window_data [0:8];
wire [WEIGHT_WIDTH-1:0] weights [0:8];

genvar k;
generate
    for(k = 0; k < 9; k = k + 1) begin : unpack_data
        assign window_data[k] = window_data_flat[(k+1)*DATA_WIDTH-1 -: DATA_WIDTH];
        assign weights[k] = weights_flat[(k+1)*WEIGHT_WIDTH-1 -: WEIGHT_WIDTH];
    end
endgenerate

// PE之间的连接信号
// 数据流：从左到右 (3行x4列)
wire [DATA_WIDTH-1:0] data_h [0:11];
wire data_valid_h [0:11];

// 权重流：从上到下 (4行x3列)
wire [WEIGHT_WIDTH-1:0] weight_v [0:11];
wire weight_valid_v [0:11];

// 部分和流：从左到右 (3行x4列)
wire [ACCUM_WIDTH-1:0] partial_sum_h [0:11];
wire partial_sum_valid_h [0:11];

// 输入数据到第一列 (行0,1,2的第0列)
assign data_h[0] = window_data[0];    // row 0, col 0
assign data_h[4] = window_data[3];    // row 1, col 0  
assign data_h[8] = window_data[6];    // row 2, col 0

assign data_valid_h[0] = window_valid;
assign data_valid_h[4] = window_valid;
assign data_valid_h[8] = window_valid;

assign partial_sum_h[0] = 0;
assign partial_sum_h[4] = 0;
assign partial_sum_h[8] = 0;

assign partial_sum_valid_h[0] = 0;
assign partial_sum_valid_h[4] = 0;
assign partial_sum_valid_h[8] = 0;

// 输入权重到第一行 (第0行的列0,1,2)
assign weight_v[0] = weights[0];      // row 0, col 0
assign weight_v[1] = weights[1];      // row 0, col 1
assign weight_v[2] = weights[2];      // row 0, col 2

assign weight_valid_v[0] = weights_valid;
assign weight_valid_v[1] = weights_valid;
assign weight_valid_v[2] = weights_valid;

// 实例化9个PE单元
// PE(0,0)
systolic_pe #(.DATA_WIDTH(DATA_WIDTH), .WEIGHT_WIDTH(WEIGHT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH))
pe_00 (.clk(clk), .rst_n(rst_n), .enable(enable),
       .data_in(data_h[0]), .data_valid_in(data_valid_h[0]),
       .data_out(data_h[1]), .data_valid_out(data_valid_h[1]),
       .weight_in(weight_v[0]), .weight_valid_in(weight_valid_v[0]),
       .weight_out(weight_v[4]), .weight_valid_out(weight_valid_v[4]),
       .partial_sum_in(partial_sum_h[0]), .partial_sum_valid_in(partial_sum_valid_h[0]),
       .partial_sum_out(partial_sum_h[1]), .partial_sum_valid_out(partial_sum_valid_h[1]));

// PE(0,1)
systolic_pe #(.DATA_WIDTH(DATA_WIDTH), .WEIGHT_WIDTH(WEIGHT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH))
pe_01 (.clk(clk), .rst_n(rst_n), .enable(enable),
       .data_in(data_h[1]), .data_valid_in(data_valid_h[1]),
       .data_out(data_h[2]), .data_valid_out(data_valid_h[2]),
       .weight_in(weight_v[1]), .weight_valid_in(weight_valid_v[1]),
       .weight_out(weight_v[5]), .weight_valid_out(weight_valid_v[5]),
       .partial_sum_in(partial_sum_h[1]), .partial_sum_valid_in(partial_sum_valid_h[1]),
       .partial_sum_out(partial_sum_h[2]), .partial_sum_valid_out(partial_sum_valid_h[2]));

// PE(0,2)
systolic_pe #(.DATA_WIDTH(DATA_WIDTH), .WEIGHT_WIDTH(WEIGHT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH))
pe_02 (.clk(clk), .rst_n(rst_n), .enable(enable),
       .data_in(data_h[2]), .data_valid_in(data_valid_h[2]),
       .data_out(data_h[3]), .data_valid_out(data_valid_h[3]),
       .weight_in(weight_v[2]), .weight_valid_in(weight_valid_v[2]),
       .weight_out(weight_v[6]), .weight_valid_out(weight_valid_v[6]),
       .partial_sum_in(partial_sum_h[2]), .partial_sum_valid_in(partial_sum_valid_h[2]),
       .partial_sum_out(partial_sum_h[3]), .partial_sum_valid_out(partial_sum_valid_h[3]));

// PE(1,0)
systolic_pe #(.DATA_WIDTH(DATA_WIDTH), .WEIGHT_WIDTH(WEIGHT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH))
pe_10 (.clk(clk), .rst_n(rst_n), .enable(enable),
       .data_in(data_h[4]), .data_valid_in(data_valid_h[4]),
       .data_out(data_h[5]), .data_valid_out(data_valid_h[5]),
       .weight_in(weight_v[4]), .weight_valid_in(weight_valid_v[4]),
       .weight_out(weight_v[8]), .weight_valid_out(weight_valid_v[8]),
       .partial_sum_in(partial_sum_h[4]), .partial_sum_valid_in(partial_sum_valid_h[4]),
       .partial_sum_out(partial_sum_h[5]), .partial_sum_valid_out(partial_sum_valid_h[5]));

// PE(1,1)
systolic_pe #(.DATA_WIDTH(DATA_WIDTH), .WEIGHT_WIDTH(WEIGHT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH))
pe_11 (.clk(clk), .rst_n(rst_n), .enable(enable),
       .data_in(data_h[5]), .data_valid_in(data_valid_h[5]),
       .data_out(data_h[6]), .data_valid_out(data_valid_h[6]),
       .weight_in(weight_v[5]), .weight_valid_in(weight_valid_v[5]),
       .weight_out(weight_v[9]), .weight_valid_out(weight_valid_v[9]),
       .partial_sum_in(partial_sum_h[5]), .partial_sum_valid_in(partial_sum_valid_h[5]),
       .partial_sum_out(partial_sum_h[6]), .partial_sum_valid_out(partial_sum_valid_h[6]));

// PE(1,2)
systolic_pe #(.DATA_WIDTH(DATA_WIDTH), .WEIGHT_WIDTH(WEIGHT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH))
pe_12 (.clk(clk), .rst_n(rst_n), .enable(enable),
       .data_in(data_h[6]), .data_valid_in(data_valid_h[6]),
       .data_out(data_h[7]), .data_valid_out(data_valid_h[7]),
       .weight_in(weight_v[6]), .weight_valid_in(weight_valid_v[6]),
       .weight_out(weight_v[10]), .weight_valid_out(weight_valid_v[10]),
       .partial_sum_in(partial_sum_h[6]), .partial_sum_valid_in(partial_sum_valid_h[6]),
       .partial_sum_out(partial_sum_h[7]), .partial_sum_valid_out(partial_sum_valid_h[7]));

// PE(2,0)
systolic_pe #(.DATA_WIDTH(DATA_WIDTH), .WEIGHT_WIDTH(WEIGHT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH))
pe_20 (.clk(clk), .rst_n(rst_n), .enable(enable),
       .data_in(data_h[8]), .data_valid_in(data_valid_h[8]),
       .data_out(data_h[9]), .data_valid_out(data_valid_h[9]),
       .weight_in(weight_v[8]), .weight_valid_in(weight_valid_v[8]),
       .weight_out(weight_v[11]), .weight_valid_out(weight_valid_v[11]),
       .partial_sum_in(partial_sum_h[8]), .partial_sum_valid_in(partial_sum_valid_h[8]),
       .partial_sum_out(partial_sum_h[9]), .partial_sum_valid_out(partial_sum_valid_h[9]));

// PE(2,1)
systolic_pe #(.DATA_WIDTH(DATA_WIDTH), .WEIGHT_WIDTH(WEIGHT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH))
pe_21 (.clk(clk), .rst_n(rst_n), .enable(enable),
       .data_in(data_h[9]), .data_valid_in(data_valid_h[9]),
       .data_out(data_h[10]), .data_valid_out(data_valid_h[10]),
       .weight_in(weight_v[9]), .weight_valid_in(weight_valid_v[9]),
       .weight_out(), .weight_valid_out(),  // 最后一行不需要输出权重
       .partial_sum_in(partial_sum_h[9]), .partial_sum_valid_in(partial_sum_valid_h[9]),
       .partial_sum_out(partial_sum_h[10]), .partial_sum_valid_out(partial_sum_valid_h[10]));

// PE(2,2)
systolic_pe #(.DATA_WIDTH(DATA_WIDTH), .WEIGHT_WIDTH(WEIGHT_WIDTH), .ACCUM_WIDTH(ACCUM_WIDTH))
pe_22 (.clk(clk), .rst_n(rst_n), .enable(enable),
       .data_in(data_h[10]), .data_valid_in(data_valid_h[10]),
       .data_out(data_h[11]), .data_valid_out(data_valid_h[11]),
       .weight_in(weight_v[10]), .weight_valid_in(weight_valid_v[10]),
       .weight_out(), .weight_valid_out(),  // 最后一行不需要输出权重
       .partial_sum_in(partial_sum_h[10]), .partial_sum_valid_in(partial_sum_valid_h[10]),
       .partial_sum_out(partial_sum_h[11]), .partial_sum_valid_out(partial_sum_valid_h[11]));

// 收集每行的最终结果
wire [ACCUM_WIDTH-1:0] row_result_0, row_result_1, row_result_2;
wire row_valid_0, row_valid_1, row_valid_2;

assign row_result_0 = partial_sum_h[3];
assign row_result_1 = partial_sum_h[7];
assign row_result_2 = partial_sum_h[11];

assign row_valid_0 = partial_sum_valid_h[3];
assign row_valid_1 = partial_sum_valid_h[7];
assign row_valid_2 = partial_sum_valid_h[11];

// 最终累加所有行的结果
reg [ACCUM_WIDTH-1:0] final_result;
reg final_valid;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        final_result <= 0;
        final_valid <= 0;
    end else if(enable) begin
        if(row_valid_0 && row_valid_1 && row_valid_2) begin
            final_result <= row_result_0 + row_result_1 + row_result_2;
            final_valid <= 1;
        end else begin
            final_valid <= 0;
        end
    end else begin
        final_valid <= 0;
    end
end

assign conv_result = final_result;
assign result_valid = final_valid;

endmodule 