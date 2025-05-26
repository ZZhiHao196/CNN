module mult_acc #(
    parameter DATA_WIDTH = 8,
    parameter KERNEL_SIZE = 3,
    parameter ACC_WIDTH = 2*DATA_WIDTH + 4  // 累加器位宽，防止溢出
)
(   
    // 全局信号接口
    input clk,
    input rst_n,
    
    // 输入数据接口
    input window_valid,
    input [DATA_WIDTH*KERNEL_SIZE*KERNEL_SIZE-1:0] window_in,
    input weight_valid,
    input [DATA_WIDTH*KERNEL_SIZE*KERNEL_SIZE-1:0] weight_in,

    // 输出数据接口
    output reg [2*DATA_WIDTH-1:0] conv_out,
    output reg conv_valid
);

// 内部信号声明
// 解包后的窗口数据和权重数据
reg signed [DATA_WIDTH-1:0] window_data [0:KERNEL_SIZE*KERNEL_SIZE-1];
reg signed [DATA_WIDTH-1:0] weight_data [0:KERNEL_SIZE*KERNEL_SIZE-1];

// 流水线阶段1：乘法结果
reg signed [2*DATA_WIDTH-1:0] mult_results [0:KERNEL_SIZE*KERNEL_SIZE-1];
reg stage1_valid;

// 流水线阶段2：第一层加法树结果
reg signed [ACC_WIDTH-1:0] add_level1 [0:4]; // 9->5 (4个加法器 + 1个直通)
reg stage2_valid;

// 流水线阶段3：第二层加法树结果  
reg signed [ACC_WIDTH-1:0] add_level2 [0:2]; // 5->3 (2个加法器 + 1个直通)
reg stage3_valid;

// 临时变量用于最终计算
reg signed [ACC_WIDTH-1:0] temp_sum;

// 循环变量
integer i;

// 输入数据解包
always @(*) begin
    for (i = 0; i < KERNEL_SIZE*KERNEL_SIZE; i = i + 1) begin
        window_data[i] = window_in[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH];
        weight_data[i] = weight_in[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH];
    end
end

// 流水线阶段1：并行乘法
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < KERNEL_SIZE*KERNEL_SIZE; i = i + 1) begin
            mult_results[i] <= 0;
        end
        stage1_valid <= 0;
    end else begin
        // 并行执行9个乘法
        for (i = 0; i < KERNEL_SIZE*KERNEL_SIZE; i = i + 1) begin
            mult_results[i] <= window_data[i] * weight_data[i];
        end
        stage1_valid <= window_valid && weight_valid;
    end
end

// 流水线阶段2：第一层加法树 (9 -> 5)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 5; i = i + 1) begin
            add_level1[i] <= 0;
        end
        stage2_valid <= 0;
    end else begin
        // 加法树第一层：将9个乘积组合成5个部分和
        add_level1[0] <= mult_results[0] + mult_results[1];  // 第1组
        add_level1[1] <= mult_results[2] + mult_results[3];  // 第2组
        add_level1[2] <= mult_results[4] + mult_results[5];  // 第3组
        add_level1[3] <= mult_results[6] + mult_results[7];  // 第4组
        add_level1[4] <= mult_results[8];                    // 第5组（直通）
        
        stage2_valid <= stage1_valid;
    end
end

// 流水线阶段3：第二层加法树 (5 -> 3)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 3; i = i + 1) begin
            add_level2[i] <= 0;
        end
        stage3_valid <= 0;
    end else begin
        // 加法树第二层：将5个部分和组合成3个部分和
        add_level2[0] <= add_level1[0] + add_level1[1];  // 第1组
        add_level2[1] <= add_level1[2] + add_level1[3];  // 第2组  
        add_level2[2] <= add_level1[4];                  // 第3组（直通）
        
        stage3_valid <= stage2_valid;
    end
end

// 最终阶段：第三层加法树 (3 -> 1) 和输出
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        conv_out <= 0;
        conv_valid <= 0;
    end else begin
        // 直接计算最终结果并输出
        if (stage3_valid) begin
            temp_sum = add_level2[0] + add_level2[1] + add_level2[2];
            conv_out <= temp_sum[2*DATA_WIDTH-1:0];
            conv_valid <= 1;
        end else begin
            conv_out <= 0;
            conv_valid <= 0;
        end
    end
end

// 可选：饱和处理函数（防止溢出）
function [2*DATA_WIDTH-1:0] saturate;
    input signed [ACC_WIDTH-1:0] value;
    localparam signed [ACC_WIDTH-1:0] MAX_VAL = (1 << (2*DATA_WIDTH-1)) - 1;
    localparam signed [ACC_WIDTH-1:0] MIN_VAL = -(1 << (2*DATA_WIDTH-1));
    begin
        if (value > MAX_VAL)
            saturate = MAX_VAL[2*DATA_WIDTH-1:0];
        else if (value < MIN_VAL)
            saturate = MIN_VAL[2*DATA_WIDTH-1:0];
        else
            saturate = value[2*DATA_WIDTH-1:0];
    end
endfunction

endmodule