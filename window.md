我最近在从事一项很有意思的项目，我想在PFGA上部署CNN并实现手写图片的识别。而本篇文章，是我迈出的第一步。具体代码已发布在[github上](https://github.com/ZZhiHao196/CNN)

## 模块介绍

卷积神经网络（CNN)可以分为卷积层、池化层、激活层、全链接层结构，本篇要实现的，就是CNN的卷积层中的window窗。

在卷积过程中，最复杂的就是卷积运算，也就是Filter和图片（输入）相乘然后在相加的这一步骤。

![img](https://i-blog.csdnimg.cn/blog_migrate/3f6ed3c5d717ccc33b19dd8843b22900.gif)

我此处的构想就是将其卷积这个步骤进行拆分：加窗、载入权重、卷积运算。因而对应3个模块，而此处实现的就是加窗这个模块。而他主要负责的功能就是：==提取输入图片中的数据，生成对应的窗口==。 如上图所示，对x[:,:,0]图片进行窗口提起，提取的第一个窗口(左上角第一个)就是

$\begin{bmatrix}0&0&0\\0&0&1\\0&0&1\end{bmatrix} $



## 代码

1. **可配置参数、输入和输出定义**

STRIDE为窗口滑动的步长，KERNEL_SIZE对应输入卷积核的大小，PADDING 为补充的长度

pixel_in 为输出的图片数据，frame_start 为图片开始输入的标志，pixel_valid为输入有效标志

window_out是图片展成一维的窗口数据

```verilog
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
    input wire frame_start,               // Start of new frame signal
    
    output reg [KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] window_out, // Flattened window output
    output reg window_valid              // Window data valid
);
```

2. 内部信号定义

输入的图片数据是一个一个输入的，用x_pos和y_pos 来记录当前pixel位于图片中的位置

窗口在图片上滑动，用x_window，y_window用来判断窗口目前的位置

line_Buffer缓存输入的数据，同时进行padding操作, 形成数据窗口，而window_buffer 在line_buffer上进行滑动，形成窗口

然后是状态机，分为三个状态 IDLE, LOAD,PROCESS, 分别对应空闲，载入（开始载入数据），处理（形成window）

```verilog
// Internal signals
reg [5:0] x_pos, y_pos;                  // Current input pixel position
reg [5:0] x_window, y_window;            // Window center position
reg [DATA_WIDTH-1:0] line_buffer [0:KERNEL_SIZE][0:IMG_WIDTH+2*PADDING-1]; // Line buffer
reg [DATA_WIDTH-1:0] window_buffer [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1]; // Window buffer
reg signed [6:0] src_y, src_x;           // Temporary variables for coordinate calculation

// State machine
reg [1:0] current_state, next_state;
localparam IDLE = 2'b00, LOAD = 2'b01, PROCESS = 2'b10;

// Loop variables
integer i, j, k;
```

3. **状态的赋值以及跳转**

当接收到frame_start信号（图片开始输入），状态从空闲进入到LOAD状态；

当目前的图片数据可以已经足够，可以用来生成**稳定**的输出窗口时，进入到PROCESS状态

当目前滑窗口提取完对应数据窗口后，回到IDLE状态

注：y_pos从0到KERNEL_SIZE-1时，已经有了KERNEL_SIZE行数据了，可以进入窗口数据提取阶段；实际上可以更早进入，因为存在Padding。当y_pos=KERNEL_SIZE-Padding-1的时候，就可以进入了

```verilog
// FSM state transitions
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) 
        current_state <= IDLE;
    else 
        current_state <= next_state;
end

always @(*) begin
    case (current_state)
        IDLE:    next_state = frame_start ? LOAD : IDLE;
        LOAD:    next_state = (y_pos >= KERNEL_SIZE-1) ? PROCESS : LOAD;
        PROCESS: next_state = (y_window >= IMG_HEIGHT && x_window == 0) ? IDLE : PROCESS;
        default: next_state = IDLE;
    endcase
end
```



4. **状态执行**

推荐使用拆分的方法，把一个状态执行的大always块，分成很多子always块。

a. 输入图片数据位置捕获

当前状态为IDLE，图片即将开始输入时，将定位信号复原

当前状态不为IDLE, 同时输入有效，那么坐标根据情况自增

```verilog
// Input pixel position tracking
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_pos <= 0;
        y_pos <= 0;
    end else if (current_state == IDLE && frame_start) begin
        x_pos <= 0;
        y_pos <= 0;
    end else if (pixel_valid && current_state != IDLE) begin
        if (x_pos == IMG_WIDTH-1) begin
            x_pos <= 0;
            y_pos <= y_pos + 1;
        end else begin
            x_pos <= x_pos + 1;
        end
    end
end

```



```verilog
// Line buffer management
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i <= KERNEL_SIZE; i = i + 1)
            for (j = 0; j < IMG_WIDTH + 2*PADDING; j = j + 1)
                line_buffer[i][j] <= 0;
    end else if (pixel_valid && current_state != IDLE) begin
                if (x_pos == 0) begin
            // Clear the line buffer row at the start of each new line
            for (k = 0; k < IMG_WIDTH + 2*PADDING; k = k + 1)
                        line_buffer[y_pos % (KERNEL_SIZE + 1)][k] <= 0;
        end
        line_buffer[y_pos % (KERNEL_SIZE + 1)][x_pos + PADDING] <= pixel_in;
    end
end

// Window position tracking
always @(posedge clk or negedge rst_n) begin
    if (!rst_n || frame_start || (current_state == LOAD && next_state == PROCESS)) begin
        x_window <= 0;
        y_window <= 0;
    end else if (current_state == PROCESS && y_window < IMG_HEIGHT) begin
        if (x_window + STRIDE >= IMG_WIDTH) begin
                    x_window <= 0;
                    y_window <= y_window + STRIDE;
                end else begin
                    x_window <= x_window + STRIDE;
                end
    end
end

// Window generation and output
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        window_valid <= 0;
        for (i = 0; i < KERNEL_SIZE; i = i + 1)
            for (j = 0; j < KERNEL_SIZE; j = j + 1)
                window_buffer[i][j] <= 0;
    end else begin
        window_valid <= 0; // Default
        
        if (current_state == PROCESS && 
            x_window < IMG_WIDTH && 
            y_window < IMG_HEIGHT && 
            y_window + (KERNEL_SIZE>>1) <= y_pos) begin
            
            // Generate window
            for (i = 0; i < KERNEL_SIZE; i = i + 1) begin
                for (j = 0; j < KERNEL_SIZE; j = j + 1) begin
                    src_y = y_window + i - (KERNEL_SIZE>>1);
                    src_x = x_window + j - (KERNEL_SIZE>>1);
                    
                    if (src_y >= 0 && src_y < IMG_HEIGHT && 
                        src_x >= 0 && src_x < IMG_WIDTH) begin
                        window_buffer[i][j] <= line_buffer[src_y % (KERNEL_SIZE + 1)][src_x + PADDING];
                        end else begin
                        window_buffer[i][j] <= 0; // Padding
                        end
                    end
                end
                window_valid <= 1;
            end 
    end
end

// Flatten window buffer for output
always @(*) begin
    for (i = 0; i < KERNEL_SIZE; i = i + 1) begin
        for (j = 0; j < KERNEL_SIZE; j = j + 1) begin
            window_out[(KERNEL_SIZE*KERNEL_SIZE-(i*KERNEL_SIZE+j))*DATA_WIDTH-1 -: DATA_WIDTH] = window_buffer[i][j];
        end
    end
end

endmodule
```



## 测试



## 结果

