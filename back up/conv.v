module conv #(
    parameter DATA_WIDTH = 16,             // Width of each pixel data
    parameter KERNEL_SIZE = 3,             // Size of convolution kernel (square)
    parameter WEIGHT_WIDTH = 8,            // Width of each weight data
    parameter OUTPUT_WIDTH = 32,           // Width of output data (to accommodate accumulation)
    parameter NUM_FILTERS = 1              // Number of convolution filters
)
(
    input wire clk,                        // Clock signal
    input wire rst_n,                      // Active low reset
    
    // Interface with window module
    input wire [KERNEL_SIZE*KERNEL_SIZE*DATA_WIDTH-1:0] window_in,  // Flattened window input from window module
    input wire window_valid,               // Window data valid signal
    
    // Convolution kernel weights (can be loaded externally)
    input wire [NUM_FILTERS*KERNEL_SIZE*KERNEL_SIZE*WEIGHT_WIDTH-1:0] weights, // Flattened weights for all filters
    input wire weights_valid,              // Weights valid signal
    
    // Optional bias
    input wire [NUM_FILTERS*OUTPUT_WIDTH-1:0] bias,  // Bias values for each filter
    input wire bias_enable,                // Enable bias addition
    
    // Output interface
    output reg [NUM_FILTERS*OUTPUT_WIDTH-1:0] conv_out,  // Convolution output for all filters
    output reg conv_valid                  // Convolution result valid
);

// Internal signals
reg [DATA_WIDTH-1:0] window_data [0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];  // Unpacked window data
reg [WEIGHT_WIDTH-1:0] filter_weights [0:NUM_FILTERS-1][0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];  // Unpacked weights
reg [OUTPUT_WIDTH-1:0] filter_bias [0:NUM_FILTERS-1];  // Unpacked bias values

// Intermediate computation signals
reg signed [DATA_WIDTH+WEIGHT_WIDTH-1:0] products [0:NUM_FILTERS-1][0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
reg signed [OUTPUT_WIDTH-1:0] partial_sums [0:NUM_FILTERS-1][0:KERNEL_SIZE-1];
reg signed [OUTPUT_WIDTH-1:0] conv_results [0:NUM_FILTERS-1];

// Pipeline registers for timing
reg window_valid_d1, window_valid_d2;
reg weights_valid_d1;

// Loop variables
integer f, i, j;

// Unpack input window data
always @(*) begin
    for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
        for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
            window_data[i][j] = window_in[(KERNEL_SIZE*KERNEL_SIZE-(i*KERNEL_SIZE+j))*DATA_WIDTH-1 -: DATA_WIDTH];
        end
    end
end

// Unpack weights for all filters
always @(*) begin
    for(f = 0; f < NUM_FILTERS; f = f + 1) begin
        for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
            for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
                filter_weights[f][i][j] = weights[(f*KERNEL_SIZE*KERNEL_SIZE + i*KERNEL_SIZE + j + 1)*WEIGHT_WIDTH-1 -: WEIGHT_WIDTH];
            end
        end
    end
end

// Unpack bias values
always @(*) begin
    for(f = 0; f < NUM_FILTERS; f = f + 1) begin
        filter_bias[f] = bias[(f+1)*OUTPUT_WIDTH-1 -: OUTPUT_WIDTH];
    end
end

// Pipeline stage 1: Element-wise multiplication
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        window_valid_d1 <= 0;
        for(f = 0; f < NUM_FILTERS; f = f + 1) begin
            for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
                for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
                    products[f][i][j] <= 0;
                end
            end
        end
    end else begin
        window_valid_d1 <= window_valid && weights_valid;
        
        if(window_valid && weights_valid) begin
            for(f = 0; f < NUM_FILTERS; f = f + 1) begin
                for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
                    for(j = 0; j < KERNEL_SIZE; j = j + 1) begin
                        // Perform signed multiplication
                        products[f][i][j] <= $signed(window_data[i][j]) * $signed(filter_weights[f][i][j]);
                    end
                end
            end
        end
    end
end

// Pipeline stage 2: Partial sums (sum across columns for each row)
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        window_valid_d2 <= 0;
        for(f = 0; f < NUM_FILTERS; f = f + 1) begin
            for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
                partial_sums[f][i] <= 0;
            end
        end
    end else begin
        window_valid_d2 <= window_valid_d1;
        
        if(window_valid_d1) begin
            for(f = 0; f < NUM_FILTERS; f = f + 1) begin
                for(i = 0; i < KERNEL_SIZE; i = i + 1) begin
                    // Sum across columns for each row
                    partial_sums[f][i] <= products[f][i][0] + products[f][i][1] + products[f][i][2];
                end
            end
        end
    end
end

// Pipeline stage 3: Final sum and bias addition
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        conv_valid <= 0;
        for(f = 0; f < NUM_FILTERS; f = f + 1) begin
            conv_results[f] <= 0;
        end
    end else begin
        conv_valid <= window_valid_d2;
        
        if(window_valid_d2) begin
            for(f = 0; f < NUM_FILTERS; f = f + 1) begin
                // Sum all partial sums
                conv_results[f] <= partial_sums[f][0] + partial_sums[f][1] + partial_sums[f][2];
                
                // Add bias if enabled
                if(bias_enable) begin
                    conv_results[f] <= partial_sums[f][0] + partial_sums[f][1] + partial_sums[f][2] + $signed(filter_bias[f]);
                end
            end
        end
    end
end

// Pack output data
always @(*) begin
    for(f = 0; f < NUM_FILTERS; f = f + 1) begin
        conv_out[(f+1)*OUTPUT_WIDTH-1 -: OUTPUT_WIDTH] = conv_results[f];
    end
end

// Weights valid pipeline
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        weights_valid_d1 <= 0;
    end else begin
        weights_valid_d1 <= weights_valid;
    end
end

endmodule