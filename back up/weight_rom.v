// CNN权重ROM模块 - 载入所有权重，根据滤波器索引返回扁平化权重
module weight_rom #(
    parameter NUM_FILTERS = 64,           // 滤波器数量
    parameter INPUT_CHANNELS = 3,         // 输入通道数 (如RGB=3)
    parameter KERNEL_SIZE = 3,            // 卷积核大小
    parameter WEIGHT_WIDTH = 8,           // 权重数据位宽
    parameter INIT_FILE = "weights.mem"   // 初始化文件路径
)
(
    input wire clk,
    input wire rst_n,
    
    // 权重加载接口
    input wire load_enable,               // 权重加载使能
    input wire [WEIGHT_WIDTH-1:0] load_data,     // 加载的权重数据
    input wire [$clog2(NUM_FILTERS*INPUT_CHANNELS*KERNEL_SIZE*KERNEL_SIZE)-1:0] load_addr,  // 加载地址
    input wire load_valid,                // 加载数据有效
    
    // 权重读取接口
    input wire [$clog2(NUM_FILTERS)-1:0] filter_idx,        // 滤波器索引
    input wire [$clog2(INPUT_CHANNELS)-1:0] channel_idx,    // 通道索引
    input wire read_enable,               // 读取使能
    
    // 输出接口 - 返回指定滤波器指定通道的权重(扁平化)
    output reg [KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] flattened_weight_out,
    output reg weight_valid,             // 权重数据有效
    
    // 状态输出
    output reg load_done,                 // 权重加载完成
    output reg rom_ready                  // ROM就绪状态
);

// 计算总的权重数量和地址位宽
localparam TOTAL_WEIGHTS = NUM_FILTERS * INPUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE;
localparam WEIGHTS_PER_CHANNEL = KERNEL_SIZE * KERNEL_SIZE;
localparam WEIGHTS_PER_FILTER = INPUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE;
localparam ADDR_WIDTH = $clog2(TOTAL_WEIGHTS);

// 权重存储器
reg [WEIGHT_WIDTH-1:0] weight_memory [0:TOTAL_WEIGHTS-1];

// 初始化变量
integer init_i;

// 内部信号
reg [ADDR_WIDTH-1:0] load_counter;
reg loading_weights;

// 读取相关信号
reg [$clog2(NUM_FILTERS)-1:0] current_filter_idx;
reg [$clog2(INPUT_CHANNELS)-1:0] current_channel_idx;
reg reading_weights;
integer read_idx;
reg [ADDR_WIDTH-1:0] base_addr;

// 初始化权重存储器
initial begin
    if (INIT_FILE != "") begin
        $readmemh(INIT_FILE, weight_memory);
        $display("Weight ROM: Loaded weights from %s", INIT_FILE);
    end else begin
        // 如果没有初始化文件，填充为0
        for(init_i = 0; init_i < TOTAL_WEIGHTS; init_i = init_i + 1) begin
            weight_memory[init_i] = 0;
        end
        $display("Weight ROM: Initialized with zeros");
    end
end

// 权重加载逻辑
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        load_counter <= 0;
        loading_weights <= 0;
        load_done <= 0;
    end else begin
        if(load_enable && !loading_weights) begin
            loading_weights <= 1;
            load_counter <= 0;
            load_done <= 0;
            $display("Weight ROM: Starting weight loading...");
        end else if(loading_weights && load_valid) begin
            weight_memory[load_addr] <= load_data;
            load_counter <= load_counter + 1;
            
            if(load_counter >= TOTAL_WEIGHTS - 1) begin
                loading_weights <= 0;
                load_done <= 1;
                $display("Weight ROM: Weight loading completed. Total weights: %d", TOTAL_WEIGHTS);
            end
        end else if(!load_enable) begin
            load_done <= 0;
        end
    end
end

// 权重读取逻辑 - 返回指定滤波器指定通道的权重(扁平化)
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        flattened_weight_out <= 0;
        weight_valid <= 0;
        current_filter_idx <= 0;
        current_channel_idx <= 0;
        reading_weights <= 0;
        read_idx <= 0;
        base_addr <= 0;
    end else begin
        if(read_enable && !loading_weights && !reading_weights) begin
            // 开始读取指定滤波器指定通道的权重
            current_filter_idx <= filter_idx;
            current_channel_idx <= channel_idx;
            reading_weights <= 1;
            read_idx <= 0;
            weight_valid <= 0;
            
            // 计算基地址: filter_idx * WEIGHTS_PER_FILTER + channel_idx * WEIGHTS_PER_CHANNEL
            base_addr <= filter_idx * WEIGHTS_PER_FILTER + channel_idx * WEIGHTS_PER_CHANNEL;
        end else if(reading_weights) begin
            // 逐个读取权重并打包
            if(read_idx < WEIGHTS_PER_CHANNEL) begin
                // 从存储器读取权重并打包到输出
                flattened_weight_out[(read_idx+1)*WEIGHT_WIDTH-1 -: WEIGHT_WIDTH] <= 
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

// ROM就绪状态
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rom_ready <= 0;
    end else begin
        rom_ready <= !loading_weights;
    end
end

// 调试和监控
`ifdef DEBUG_WEIGHT_ROM
always @(posedge clk) begin
    if(read_enable && weight_valid) begin
        $display("Weight ROM: Filter[%d] Channel[%d] weights output ready", current_filter_idx, current_channel_idx);
    end
    
    if(load_valid && loading_weights) begin
        $display("Weight ROM Load: Addr[%d] = %h", load_addr, load_data);
    end
    
    if(reading_weights) begin
        $display("Weight ROM Read: Filter[%d] Channel[%d] Weight[%d] = %h", 
                 current_filter_idx, current_channel_idx, read_idx, 
                 weight_memory[base_addr + read_idx]);
    end
end
`endif

// 权重统计信息 (综合时会被优化掉)
`ifdef SYNTHESIS
`else
initial begin
    $display("=== CNN Weight ROM Configuration ===");
    $display("Number of Filters: %d", NUM_FILTERS);
    $display("Input Channels: %d", INPUT_CHANNELS);
    $display("Kernel Size: %dx%d", KERNEL_SIZE, KERNEL_SIZE);
    $display("Weight Width: %d bits", WEIGHT_WIDTH);
    $display("Weights per Channel: %d", WEIGHTS_PER_CHANNEL);
    $display("Weights per Filter: %d", WEIGHTS_PER_FILTER);
    $display("Total Weights: %d", TOTAL_WEIGHTS);
    $display("Memory Size: %d bytes", TOTAL_WEIGHTS * WEIGHT_WIDTH / 8);
    $display("Output Width: %d bits", KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH);
    $display("=====================================");
end
`endif

endmodule

//=============================================================================
// 权重ROM测试模块
//=============================================================================
module weight_rom_tb();

    parameter NUM_FILTERS = 4;
    parameter INPUT_CHANNELS = 3;
    parameter KERNEL_SIZE = 3;
    parameter WEIGHT_WIDTH = 8;
    
    reg clk, rst_n;
    reg load_enable, load_valid;
    reg [WEIGHT_WIDTH-1:0] load_data;
    reg [$clog2(NUM_FILTERS*INPUT_CHANNELS*KERNEL_SIZE*KERNEL_SIZE)-1:0] load_addr;
    
    reg [$clog2(NUM_FILTERS)-1:0] filter_idx;
    reg [$clog2(INPUT_CHANNELS)-1:0] channel_idx;
    reg read_enable;
    
    wire [KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] flattened_weight_out;
    wire weight_valid;
    wire load_done, rom_ready;
    
    // 实例化权重ROM
    weight_rom #(
        .NUM_FILTERS(NUM_FILTERS),
        .INPUT_CHANNELS(INPUT_CHANNELS),
        .KERNEL_SIZE(KERNEL_SIZE),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .INIT_FILE("")  // 不使用初始化文件
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .load_enable(load_enable),
        .load_data(load_data),
        .load_addr(load_addr),
        .load_valid(load_valid),
        .filter_idx(filter_idx),
        .channel_idx(channel_idx),
        .read_enable(read_enable),
        .flattened_weight_out(flattened_weight_out),
        .weight_valid(weight_valid),
        .load_done(load_done),
        .rom_ready(rom_ready)
    );
    
    // 时钟生成
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end
    
    // 测试流程
    initial begin
        $display("Starting Weight ROM Test...");
        
        // 初始化
        rst_n = 0;
        load_enable = 0;
        load_valid = 0;
        load_data = 0;
        load_addr = 0;
        read_enable = 0;
        filter_idx = 0;
        channel_idx = 0;
        
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);
        
        // 测试权重加载
        $display("Testing weight loading...");
        load_enable = 1;
        @(posedge clk);
        
        // 加载测试权重 (为每个位置加载不同的权重值)
        for(integer i = 0; i < NUM_FILTERS * INPUT_CHANNELS * KERNEL_SIZE * KERNEL_SIZE; i = i + 1) begin
            @(posedge clk);
            load_addr = i;
            load_data = (i % 256) + 1;  // 权重值为(地址%256)+1
            load_valid = 1;
        end
        
        @(posedge clk);
        load_valid = 0;
        load_enable = 0;
        
        // 等待加载完成
        wait(load_done);
        $display("Weight loading completed!");
        
        repeat(5) @(posedge clk);
        
        // 测试读取不同滤波器不同通道的权重
        for(integer f = 0; f < NUM_FILTERS; f = f + 1) begin
            for(integer c = 0; c < INPUT_CHANNELS; c = c + 1) begin
                $display("Testing filter %d channel %d weight read...", f, c);
                filter_idx = f;
                channel_idx = c;
                read_enable = 1;
                
                @(posedge clk);
                read_enable = 0;
                
                // 等待权重读取完成
                wait(weight_valid);
                $display("Filter %d Channel %d weights ready. First weight = %h", 
                         f, c, flattened_weight_out[WEIGHT_WIDTH-1:0]);
                
                repeat(2) @(posedge clk);
            end
        end
        
        repeat(10) @(posedge clk);
        
        $display("Weight ROM Test Completed!");
        $finish;
    end
    
    // 监控输出
    always @(posedge clk) begin
        if(weight_valid) begin
            $display("Time %0t: Filter %d Channel %d weights output ready", $time, filter_idx, channel_idx);
            // 显示前几个权重值作为验证
            $display("  Weight[0] = %h", flattened_weight_out[WEIGHT_WIDTH-1:0]);
            $display("  Weight[1] = %h", flattened_weight_out[2*WEIGHT_WIDTH-1:WEIGHT_WIDTH]);
            $display("  Weight[2] = %h", flattened_weight_out[3*WEIGHT_WIDTH-1:2*WEIGHT_WIDTH]);
        end
    end
    
    // 波形文件
    initial begin
        $dumpfile("weight_rom_tb.vcd");
        $dumpvars(0, weight_rom_tb);
    end

endmodule 