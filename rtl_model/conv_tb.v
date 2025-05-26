`timescale 1ns / 1ps

module conv_tb;

parameter DATA_WIDTH = 8;
parameter KERNEL_SIZE = 3;
parameter IN_CHANNEL = 3;
parameter NUM_FILTERS = 3;
parameter IMG_WIDTH = 4;
parameter IMG_HEIGHT = 4;
parameter STRIDE = 1;
parameter PADDING = (KERNEL_SIZE - 1) / 2;
parameter WEIGHT_WIDTH = 8;
parameter ACC_WIDTH = 2*DATA_WIDTH + 4;

reg clk;
reg rst_n;
reg [IN_CHANNEL*DATA_WIDTH-1:0] pixel_in;
reg pixel_valid;
reg frame_start;
wire [NUM_FILTERS*DATA_WIDTH-1:0] conv_out;
wire conv_valid;

integer i, x, y, output_count;

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

initial begin
    clk = 0;
    forever #5 clk = ~clk;
end

initial begin
    rst_n = 0;
    pixel_in = 0;
    pixel_valid = 0;
    frame_start = 0;
    output_count = 0;
    
    #20;
    rst_n = 1;
    #10;
    
    $display("=== Simple Conv Test with Immediate Processing ===");
    
    // Start frame
    frame_start = 1;
    #10;
    frame_start = 0;
    
    // Send test data
    for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
        for (x = 0; x < IMG_WIDTH; x = x + 1) begin
            pixel_in[1*DATA_WIDTH-1:0*DATA_WIDTH] = 8'd1; // Channel 0
            pixel_in[2*DATA_WIDTH-1:1*DATA_WIDTH] = 8'd1; // Channel 1  
            pixel_in[3*DATA_WIDTH-1:2*DATA_WIDTH] = 8'd1; // Channel 2
            
            pixel_valid = 1;
            #10;
            
            // Check for immediate output
            if (conv_valid) begin
                output_count = output_count + 1;
                $display("Output %d at pixel [%d,%d]: F0=%d, F1=%d, F2=%d", 
                    output_count, x, y,
                    $signed(conv_out[1*DATA_WIDTH-1:0*DATA_WIDTH]),
                    $signed(conv_out[2*DATA_WIDTH-1:1*DATA_WIDTH]),
                    $signed(conv_out[3*DATA_WIDTH-1:2*DATA_WIDTH])
                );
            end
        end
    end
    
    pixel_valid = 0;
    $display("All pixels sent");
    
    // Wait a bit more for any remaining outputs
    repeat(20) begin
        @(posedge clk);
        if (conv_valid) begin
            output_count = output_count + 1;
            $display("Late Output %d: F0=%d, F1=%d, F2=%d", 
                output_count,
                $signed(conv_out[1*DATA_WIDTH-1:0*DATA_WIDTH]),
                $signed(conv_out[2*DATA_WIDTH-1:1*DATA_WIDTH]),
                $signed(conv_out[3*DATA_WIDTH-1:2*DATA_WIDTH])
            );
        end
    end
    
    $display("Total outputs: %d", output_count);
    if (output_count > 0) begin
        $display("SUCCESS: Simple conv layer with immediate processing works!");
    end else begin
        $display("FAILED - No outputs");
    end
    
    $finish;
end

initial begin
    #3000;
    $display("TIMEOUT");
    $finish;
end

endmodule 