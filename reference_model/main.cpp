#include <iostream>
#include <vector>
#include <iomanip> // For fixed and setprecision
#include "convolution.h"

using namespace std;

// Helper function to print a 3D vector (image)
void print_image(const vector<vector<vector<float>>> &image, const string &label)
{
    if (image.empty())
    {
        cout << label << " is empty." << endl;
        return;
    }
    cout << label << " (Channels: " << image.size()
         << ", Height: " << (image.empty() ? 0 : image[0].size())
         << ", Width: " << (image.empty() || image[0].empty() ? 0 : image[0][0].size())
         << ")" << endl;

    for (size_t c = 0; c < image.size(); ++c)
    {
        cout << "Channel " << c << ":" << endl;
        if (image[c].empty())
        {
            cout << "  Empty channel." << endl;
            continue;
        }
        for (size_t h = 0; h < image[c].size(); ++h)
        {
            cout << "  ";
            if (image[c][h].empty())
            {
                cout << "Empty row." << endl;
                continue;
            }
            for (size_t w = 0; w < image[c][h].size(); ++w)
            {
                cout << fixed << setprecision(2) << image[c][h][w] << "\t";
            }
            cout << endl;
        }
        cout << endl;
    }
}

int main()
{
    // Define parameters based on readme.md defaults
    const int KERNEL_SIZE = 3;
    const int STRIDE = 1;                                // readme supports 1 and 2
    const PaddingMode PADDING_MODE = PaddingMode::VALID; // readme: 0 Valid; 1 Same
    const int INPUT_CHANNELS = 3;                        // readme: (默认为 3 RGB)
    const int OUTPUT_CHANNELS = 1;                       // readme: (默认为 1)
    const int INPUT_HEIGHT = 32;
    const int INPUT_WIDTH = 32;

    cout << "Initializing Convolution Layer..." << endl;
    cout << "Kernel Size: " << KERNEL_SIZE << endl;
    cout << "Stride: " << STRIDE << endl;
    cout << "Padding Mode: " << (PADDING_MODE == PaddingMode::VALID ? "VALID" : "SAME") << endl;
    cout << "Input Channels: " << INPUT_CHANNELS << endl;
    cout << "Output Channels: " << OUTPUT_CHANNELS << endl;
    cout << "Input Dimensions: " << INPUT_CHANNELS << "x" << INPUT_HEIGHT << "x" << INPUT_WIDTH << endl;

    // --- 1. Initialize Kernel Weights ---
    // kernel_weights_: [out_c][in_c][k_h][k_w]
    // For simplicity, let's create a simple averaging kernel for each input channel to the single output channel.
    vector<vector<vector<vector<float>>>> kernel_weights(
        OUTPUT_CHANNELS,
        vector<vector<vector<float>>>(
            INPUT_CHANNELS,
            vector<vector<float>>(
                KERNEL_SIZE,
                vector<float>(KERNEL_SIZE, 1.0f / (KERNEL_SIZE * KERNEL_SIZE)) // Averaging filter
                )));

    // Example: Make one kernel slightly different to show effect if multiple input channels contribute
    // If input_channels > 1, let's make the second channel's kernel identity-like in center
    if (INPUT_CHANNELS > 1 && KERNEL_SIZE == 3)
    {
        kernel_weights[0][1] = {
            {0.0f, 0.0f, 0.0f},
            {0.0f, 1.0f, 0.0f},
            {0.0f, 0.0f, 0.0f}};
    }

    // --- 2. Create Input Image Data ---
    // input_image: [in_c][height][width]
    // Simple ramp pattern for each channel for easy visual inspection
    vector<vector<vector<float>>> input_image(
        INPUT_CHANNELS,
        vector<vector<float>>(
            INPUT_HEIGHT,
            vector<float>(INPUT_WIDTH)));

    for (int c = 0; c < INPUT_CHANNELS; ++c)
    {
        for (int h = 0; h < INPUT_HEIGHT; ++h)
        {
            for (int w = 0; w < INPUT_WIDTH; ++w)
            {
                input_image[c][h][w] = static_cast<float>(c * 100 + h * 10 + w); // Example data
            }
        }
    }
    // print_image(input_image, "Input Image"); // Optional: print if small enough

    try
    {
        // --- 3. Create Convolution Layer ---
        ConvolutionLayer conv_layer(
            KERNEL_SIZE,
            STRIDE,
            PADDING_MODE,
            INPUT_CHANNELS,
            OUTPUT_CHANNELS,
            kernel_weights);

        // --- 4. Perform Convolution ---
        cout << "\nPerforming convolution..." << endl;
        vector<vector<vector<float>>> output_image = conv_layer.forward(input_image);
        cout << "Convolution complete." << endl;

        // --- 5. Print Output Image ---
        print_image(output_image, "Output Image");

        // --- Test with SAME padding and stride 2 ---
        const int STRIDE_2 = 2;
        const PaddingMode PADDING_MODE_SAME = PaddingMode::SAME;
        cout << "\n\nInitializing Convolution Layer (Stride 2, SAME padding)..." << endl;
        cout << "Kernel Size: " << KERNEL_SIZE << endl;
        cout << "Stride: " << STRIDE_2 << endl;
        cout << "Padding Mode: " << (PADDING_MODE_SAME == PaddingMode::VALID ? "VALID" : "SAME") << endl;
        cout << "Input Channels: " << INPUT_CHANNELS << endl;
        cout << "Output Channels: " << OUTPUT_CHANNELS << endl;
        cout << "Input Dimensions: " << INPUT_CHANNELS << "x" << INPUT_HEIGHT << "x" << INPUT_WIDTH << endl;

        ConvolutionLayer conv_layer_same_s2(
            KERNEL_SIZE,
            STRIDE_2,
            PADDING_MODE_SAME,
            INPUT_CHANNELS,
            OUTPUT_CHANNELS,
            kernel_weights);
        cout << "\nPerforming convolution (Stride 2, SAME padding)..." << endl;
        vector<vector<vector<float>>> output_image_same_s2 = conv_layer_same_s2.forward(input_image);
        cout << "Convolution complete." << endl;
        print_image(output_image_same_s2, "Output Image (Stride 2, SAME padding)");
    }
    catch (const runtime_error &e) // std::runtime_error also becomes runtime_error
    {
        cerr << "Error: " << e.what() << endl; // std::cerr also becomes cerr
        return 1;
    }

    return 0;
}