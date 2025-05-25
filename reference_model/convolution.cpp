#include "convolution.h"
#include <iostream> // For potential debugging, can be removed later
#include <cmath>    // For std::ceil

ConvolutionLayer::ConvolutionLayer(
    int kernel_size,
    int stride,
    PaddingMode padding_mode,
    int input_channels,
    int output_channels,
    const std::vector<std::vector<std::vector<std::vector<float>>>> &initial_kernel_weights) : kernel_size_(kernel_size),
                                                                                               stride_(stride),
                                                                                               padding_mode_(padding_mode),
                                                                                               input_channels_(input_channels),
                                                                                               output_channels_(output_channels),
                                                                                               kernel_weights_(initial_kernel_weights)
{
    // Basic validation
    if (kernel_size <= 0)
    {
        throw std::runtime_error("Kernel size must be positive.");
    }
    if (stride <= 0)
    {
        throw std::runtime_error("Stride must be positive.");
    }
    if (input_channels <= 0)
    {
        throw std::runtime_error("Input channels must be positive.");
    }
    if (output_channels <= 0)
    {
        throw std::runtime_error("Output channels must be positive.");
    }
    if (kernel_weights_.empty() && output_channels_ > 0)
    {
        throw std::runtime_error("Initial kernel weights cannot be empty if output channels > 0.");
    }
    if (!kernel_weights_.empty())
    {
        if (kernel_weights_.size() != static_cast<size_t>(output_channels_))
        {
            throw std::runtime_error("Mismatch between output_channels and kernel_weights_ first dimension.");
        }
        if (!kernel_weights_[0].empty())
        {
            if (kernel_weights_[0].size() != static_cast<size_t>(input_channels_))
            {
                throw std::runtime_error("Mismatch between input_channels and kernel_weights_ second dimension.");
            }
            if (!kernel_weights_[0][0].empty())
            {
                if (kernel_weights_[0][0].size() != static_cast<size_t>(kernel_size_))
                {
                    throw std::runtime_error("Mismatch between kernel_size and kernel_weights_ third dimension.");
                }
                if (!kernel_weights_[0][0][0].empty())
                {
                    if (kernel_weights_[0][0][0].size() != static_cast<size_t>(kernel_size_))
                    {
                        throw std::runtime_error("Mismatch between kernel_size and kernel_weights_ fourth dimension.");
                    }
                }
            }
        }
    }
}

int ConvolutionLayer::calculate_padding_amount(int input_dim, int output_dim_target) const
{
    // pad = ((output_dim_target - 1) * stride + kernel_size - input_dim) / 2
    // This formula is derived for one side, so total padding is 2 * pad.
    // However, the problem usually refers to padding on each side.
    int pad = ((output_dim_target - 1) * stride_ + kernel_size_ - input_dim) / 2;
    return std::max(0, pad); // Ensure padding is not negative
}

std::vector<std::vector<std::vector<float>>> ConvolutionLayer::forward(
    const std::vector<std::vector<std::vector<float>>> &input_image) const
{
    if (input_image.empty() || input_image[0].empty() || input_image[0][0].empty())
    {
        throw std::runtime_error("Input image cannot be empty.");
    }
    if (input_image.size() != static_cast<size_t>(input_channels_))
    {
        throw std::runtime_error("Input image channels mismatch with layer input_channels.");
    }

    int input_height = input_image[0].size();
    int input_width = input_image[0][0].size();

    int output_height;
    int output_width;
    int padding_h = 0;
    int padding_w = 0;

    if (padding_mode_ == PaddingMode::VALID)
    {
        output_height = (input_height - kernel_size_) / stride_ + 1;
        output_width = (input_width - kernel_size_) / stride_ + 1;
    }
    else
    { // PaddingMode::SAME
        output_height = static_cast<int>(std::ceil(static_cast<float>(input_height) / stride_));
        output_width = static_cast<int>(std::ceil(static_cast<float>(input_width) / stride_));
        padding_h = calculate_padding_amount(input_height, output_height);
        padding_w = calculate_padding_amount(input_width, output_width);
    }

    if (output_height <= 0 || output_width <= 0)
    {
        throw std::runtime_error("Output dimensions are non-positive. Check kernel size, stride, and input dimensions.");
    }

    std::vector<std::vector<std::vector<float>>> output_image(
        output_channels_,
        std::vector<std::vector<float>>(
            output_height,
            std::vector<float>(output_width, 0.0f)));

    for (int out_c = 0; out_c < output_channels_; ++out_c)
    {
        for (int out_h = 0; out_h < output_height; ++out_h)
        {
            for (int out_w = 0; out_w < output_width; ++out_w)
            {
                float sum = 0.0f;
                for (int in_c = 0; in_c < input_channels_; ++in_c)
                {
                    for (int k_h = 0; k_h < kernel_size_; ++k_h)
                    {
                        for (int k_w = 0; k_w < kernel_size_; ++k_w)
                        {
                            int h_idx = out_h * stride_ + k_h - padding_h;
                            int w_idx = out_w * stride_ + k_w - padding_w;

                            float pixel_value = 0.0f;
                            if (h_idx >= 0 && h_idx < input_height && w_idx >= 0 && w_idx < input_width)
                            {
                                pixel_value = input_image[in_c][h_idx][w_idx];
                            }
                            // else: it's padding, pixel_value remains 0.0f as initialized

                            sum += pixel_value * kernel_weights_[out_c][in_c][k_h][k_w];
                        }
                    }
                }
                output_image[out_c][out_h][out_w] = sum;
            }
        }
    }

    return output_image;
}