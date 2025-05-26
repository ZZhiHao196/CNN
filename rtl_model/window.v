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