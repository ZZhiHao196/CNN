#ifndef CONVOLUTION_H
#define CONVOLUTION_H

#include <vector>
#include <string>
#include <stdexcept> // Required for std::runtime_error

// Define an enum for padding modes
enum class PaddingMode
{
    VALID,
    SAME
};

class ConvolutionLayer
{
public:
    // Constructor
    ConvolutionLayer(
        int kernel_size,
        int stride,
        PaddingMode padding_mode,
        int input_channels,
        int output_channels,
        const std::vector<std::vector<std::vector<std::vector<float>>>> &initial_kernel_weights);

    // Perform convolution
    std::vector<std::vector<std::vector<float>>> forward(
        const std::vector<std::vector<std::vector<float>>> &input_image) const;

private:
    int kernel_size_;
    int stride_;
    PaddingMode padding_mode_;
    int input_channels_;
    int output_channels_;
    std::vector<std::vector<std::vector<std::vector<float>>>> kernel_weights_; // [out_c][in_c][k_h][k_w]

    // Helper to get padding amount for SAME mode
    int calculate_padding_amount(int input_dim, int output_dim_target) const;
};

#endif // CONVOLUTION_H