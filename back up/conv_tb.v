`timescale 1ns / 1ps

module conv_tb;

// Parameters
parameter DATA_WIDTH = 8;
parameter KERNEL_SIZE = 3;
parameter IN_CHANNEL = 3;
parameter NUM_FILTERS = 3;
parameter IMG_WIDTH = 8;
parameter IMG_HEIGHT = 8;
parameter STRIDE = 1;
parameter PADDING = (KERNEL_SIZE - 1) / 2;
parameter WEIGHT_WIDTH = 8;
parameter ACC_WIDTH = 2*DATA_WIDTH + 4;

// Clock and reset
reg clk;
reg rst_n;

// Input signals
reg [IN_CHANNEL*DATA_WIDTH-1:0] pixel_in;
reg pixel_valid;
reg frame_start;

// Output signals
wire [NUM_FILTERS*DATA_WIDTH-1:0] conv_out;
wire conv_valid;

// Test variables
integer i, j, ch, x, y;
reg [DATA_WIDTH-1:0] test_image [0:IN_CHANNEL-1][0:IMG_HEIGHT-1][0:IMG_WIDTH-1];
reg [DATA_WIDTH-1:0] channel_pixel;
integer pixel_count;
integer output_count;

// Instantiate the conv module
conv #(
    .DATA_WIDTH(DATA_WIDTH),
    .KERNEL_SIZE(KERNEL_SIZE),
    .IN_CHANNEL(IN_CHANNEL),
    .NUM_FILTERS(NUM_FILTERS),
    .IMG_WIDTH(IMG_WIDTH),
    .IMG_HEIGHT(IMG_HEIGHT),
    .STRIDE(STRIDE),
    .PADDING(PADDING),
    .WEIGHT_WIDTH(WEIGHT_WIDTH),
    .ACC_WIDTH(ACC_WIDTH)
) dut (
    .clk(clk),
    .rst_n(rst_n),
    .pixel_in(pixel_in),
    .pixel_valid(pixel_valid),
    .frame_start(frame_start),
    .conv_out(conv_out),
    .conv_valid(conv_valid)
);

// Clock generation
initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

// Initialize test image with simple pattern
initial begin
    for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
        for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
            for (x = 0; x < IMG_WIDTH; x = x + 1) begin
                test_image[ch][y][x] = (ch + 1) * 10 + y * IMG_WIDTH + x;
            end
        end
    end
end

// Test procedure
initial begin
    // Initialize signals
    rst_n = 0;
    pixel_in = 0;
    pixel_valid = 0;
    frame_start = 0;
    pixel_count = 0;
    output_count = 0;
    
    // Reset
    #20;
    rst_n = 1;
    #10;
    
    $display("=== CNN Convolution Layer Test Started ===");
    $display("Image size: %dx%d, Channels: %d, Filters: %d", IMG_WIDTH, IMG_HEIGHT, IN_CHANNEL, NUM_FILTERS);
    
    // Start frame
    frame_start = 1;
    #10;
    frame_start = 0;
    
    // Send image data
    for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
        for (x = 0; x < IMG_WIDTH; x = x + 1) begin
            // Pack all channels into pixel_in
            pixel_in = 0;
            for (ch = 0; ch < IN_CHANNEL; ch = ch + 1) begin
                channel_pixel = test_image[ch][y][x];
                pixel_in[(ch+1)*DATA_WIDTH-1 -: DATA_WIDTH] = channel_pixel;
            end
            
            pixel_valid = 1;
            #10;
            pixel_count = pixel_count + 1;
            
            if (pixel_count % 16 == 0) begin
                $display("Sent %d pixels...", pixel_count);
            end
        end
    end
    
    pixel_valid = 0;
    $display("All %d pixels sent", pixel_count);
    
    // Wait for outputs
    $display("Waiting for convolution results...");
    
    // Monitor outputs for a reasonable time
    repeat(1000) begin
        @(posedge clk);
        if (conv_valid) begin
            output_count = output_count + 1;
            $display("Output %d: Filter0=%d, Filter1=%d, Filter2=%d", 
                output_count,
                $signed(conv_out[1*DATA_WIDTH-1 -: DATA_WIDTH]),
                $signed(conv_out[2*DATA_WIDTH-1 -: DATA_WIDTH]),
                $signed(conv_out[3*DATA_WIDTH-1 -: DATA_WIDTH])
            );
        end
    end
    
    $display("=== Test Completed ===");
    $display("Total outputs received: %d", output_count);
    
    if (output_count > 0) begin
        $display("SUCCESS: Conv layer produced outputs");
    end else begin
        $display("WARNING: No outputs received");
    end
    
    $finish;
end

// Monitor state changes
always @(posedge clk) begin
    if (dut.current_state != dut.next_state) begin
        case (dut.next_state)
            3'b000: $display("State: IDLE");
            3'b001: $display("State: PROCESSING");
            3'b010: $display("State: LOAD_WEIGHTS");
            3'b011: $display("State: COMPUTE");
            3'b100: $display("State: OUTPUT");
            default: $display("State: UNKNOWN");
        endcase
    end
end

// Monitor window validity
always @(posedge clk) begin
    if (dut.all_windows_valid && !dut.all_windows_valid_reg) begin
        $display("All windows became valid");
    end
end

// Monitor weight validity
always @(posedge clk) begin
    if (dut.all_weights_valid && dut.weight_read_enable) begin
        $display("All weights became valid");
    end
end

// Timeout protection
initial begin
    #50000;
    $display("TIMEOUT: Test took too long");
    $finish;
end

endmodule 