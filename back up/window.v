module window #(
    parameter DATA_WIDTH = 16,             // Width of each pixel data
    parameter IMG_WIDTH = 32,             // Width of input image
    parameter IMG_HEIGHT = 32,            // Height of input image
    parameter KERNEL_SIZE = 3,            // Size of convolution window (square)
    parameter STRIDE = 1,                 // Stride of convolution
    parameter PADDING = (KERNEL_SIZE - 1) / 2  // Padding size calculated for SAME mode
)
(
    input wire clk,                       // Clock signal
    input wire rst_n,                     // Active low reset
    input wire [DATA_WIDTH-1:0] pixel_in, // Input pixel data
    input wire pixel_valid,               // Input pixel valid signal
    input wire frame_start,               // Start of new frame signal, IDEL-->LOAD
    
    output reg [KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] window_out, // Flattened window output
    output reg window_valid              // Window data valid
);

//Internal signals
//32*32
reg [12:0]pixel_count;   //输入像素计数器
reg [6-1:0]x_pos,y_pos;  //包含padding的坐标
reg [6-1:0]x_window,y_window;//用于生成窗口,32=2^6，表示窗口中心位置
reg [DATA_WIDTH-1:0]line_buffer [0:KERNEL_SIZE][0:IMG_WIDTH+2*PADDING-1]; //行缓冲区，
reg [DATA_WIDTH-1:0]window_buffer [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1]; //窗口缓冲区
reg signed [6:0] src_y, src_x; // 用于计算实际图像坐标的临时变量

reg [1:0]current_state,next_state;
localparam 
            IDLE=2'b00,
            LOAD=2'b01, 
            PROCESS=2'b10;
//looping variables
integer i, j, k;

//FSM state machine
always @(posedge clk or negedge rst_n)begin
    if(!rst_n) current_state<=IDLE;
    else current_state<=next_state;
end

always @(*)begin
    next_state=current_state;
    case(current_state)
        IDLE: next_state=(frame_start)? LOAD:IDLE; //新帧的开始
        LOAD: next_state=(pixel_count >= (KERNEL_SIZE-1)*IMG_WIDTH)? PROCESS:LOAD; //简化条件：有足够数据开始生成第一行窗口
        PROCESS: next_state=(y_window >= IMG_HEIGHT && x_window == 0)? IDLE:PROCESS; //修正条件：确保最后一个窗口输出完成后才转换到IDLE
        default: next_state=IDLE;
    endcase
end


//couting variables
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        pixel_count<=0;
        x_pos<=0;
        y_pos<=0;
    end else begin
        if(current_state==IDLE)begin
            window_valid<=0;
            if(frame_start)begin
                pixel_count<=0;
                x_pos<=0;
                y_pos<=0;
            end
        end else begin
            if(pixel_valid)begin
                    pixel_count<=pixel_count+1;
                    if(x_pos==IMG_WIDTH-1)begin
                        x_pos<=0;
                        y_pos<=y_pos+1;
                    end else x_pos<=x_pos+1;
                    
            end
        end
    end
end

//line buffer
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        // Reset line_buffer: Initialize all stored lines to 0.
        // This also handles initial vertical padding at the top of the image.
        for(i=0; i<=KERNEL_SIZE; i=i+1)
            for(j=0; j<IMG_WIDTH+2*PADDING; j=j+1)
                line_buffer[i][j]<=0;

    end else begin
        if(current_state!=IDLE)begin 
            if(pixel_valid)begin     
                if (x_pos == 0) begin
                    for (k=0; k < IMG_WIDTH + 2*PADDING; k=k+1) begin
                        line_buffer[y_pos % (KERNEL_SIZE + 1)][k] <= 0;
                    end
                end
                line_buffer[y_pos % (KERNEL_SIZE + 1)][x_pos + PADDING] <= pixel_in;
            end
        end
    end
end


//Window Anchor Counters (x_window, y_window) - 表示窗口中心位置
always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        x_window <= 0;
        y_window <= 0;
    end else if (current_state == LOAD && next_state == PROCESS) begin // Reset when entering PROCESS
        x_window <= 0;
        y_window <= 0;
    end else if (current_state == PROCESS) begin        
           if (y_window < IMG_HEIGHT) begin 
                if(x_window + STRIDE >= IMG_WIDTH)begin
                    x_window <= 0;
                    y_window <= y_window + STRIDE;
                end else begin
                    x_window <= x_window + STRIDE;
                end
            end         
    end else if (frame_start) begin // Reset on new frame 
        x_window <= 0;
        y_window <= 0;
    end
end

//window buffer and output signals
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        window_valid<=0;
        for (i=0;i<KERNEL_SIZE;i=i+1)
            for(j=0;j<KERNEL_SIZE;j=j+1)
                window_buffer[i][j]<=0;
    end else begin
        window_valid <= 0; // Default to low
        if(current_state==PROCESS)begin
            // 窗口有效条件：确保有足够的行数据来生成当前窗口
            if(x_window < IMG_WIDTH && y_window < IMG_HEIGHT && 
               (y_window + (KERNEL_SIZE>>1) <= y_pos))begin // 修正：确保有足够行数据
                for(i=0; i<KERNEL_SIZE; i=i+1) begin // 遍历窗口行
                    for(j=0; j<KERNEL_SIZE; j=j+1) begin 
                        // 计算实际的图像坐标
                        src_y = y_window + i - (KERNEL_SIZE>>1);
                        src_x = x_window + j - (KERNEL_SIZE>>1);
                        // 检查是否在有效图像范围内
                        if (src_y >= 0 && src_y < IMG_HEIGHT && src_x >= 0 && src_x < IMG_WIDTH) begin
                            // 在有效范围内，从line_buffer读取
                            window_buffer[i][j] <= line_buffer[src_y % (KERNEL_SIZE + 1)][src_x + PADDING];
                        end else begin
                            // 超出边界，填充0（padding区域）
                            window_buffer[i][j] <= 0;
                        end
                    end
                end
                window_valid <= 1;
            end 
        end else window_valid<=0;  
    end
end

//flatten window buffer for output
always @(*)begin
    for(i=0;i<KERNEL_SIZE;i=i+1)begin
        for(j=0;j<KERNEL_SIZE;j=j+1)
            window_out[(KERNEL_SIZE*KERNEL_SIZE-(i*KERNEL_SIZE+j))*DATA_WIDTH-1 -: DATA_WIDTH] = window_buffer[i][j];
    end
end

endmodule