#include <stdio.h>
#include <stdlib.h>
#include <string.h> // For memset if needed for zeroing, though manual loop is used
#include <math.h>   // For ceilf
#include "convolution_c.h"

// Forward declaration for a function in convolution_c.c if it's not in the header and needed here
// (e.g. if free_3d_float_array was static but needed for main's own allocations)
// However, free_3d_float_array was made non-static and declared in convolution_c.h indirectly via its use in destroy.
// We need a way to free the kernel_weights if main allocates them before passing to create_convolution_layer_c
// and also for the input_image.

// Helper function to allocate a 3D float array (can be moved to convolution_c.c or a common utils.c)
// For main_c.c, we need it to prepare input_image and initial_kernel_weights in a C-compatible way.
static float ***main_allocate_3d_float_array(int d1, int d2, int d3)
{
    float ***array = (float ***)malloc(d1 * sizeof(float **));
    if (!array)
        return NULL;
    for (int i = 0; i < d1; ++i)
    {
        array[i] = (float **)malloc(d2 * sizeof(float *));
        if (!array[i])
        {
            for (int k = 0; k < i; ++k)
                free(array[k]);
            free(array);
            return NULL;
        }
        for (int j = 0; j < d2; ++j)
        {
            array[i][j] = (float *)malloc(d3 * sizeof(float));
            if (!array[i][j])
            {
                for (int k = 0; k < j; ++k)
                    free(array[i][k]);
                free(array[i]);
                for (int k = 0; k < i; ++k)
                { /*free nested previous*/
                    free(array[k]);
                } // This nested free is problematic.
                free(array);
                return NULL;
            }
        }
    }
    return array;
}

// Helper to free 3D array used by main
static void main_free_3d_float_array(float ***array, int d1, int d2)
{
    if (!array)
        return;
    for (int i = 0; i < d1; ++i)
    {
        if (array[i])
        {
            for (int j = 0; j < d2; ++j)
            {
                free(array[i][j]);
            }
            free(array[i]);
        }
    }
    free(array);
}

// Helper to allocate a 4D float array (for kernel_weights in main)
static float ****main_allocate_4d_float_array(int d1, int d2, int d3, int d4)
{
    float ****array = (float ****)malloc(d1 * sizeof(float ***));
    if (!array)
        return NULL;
    for (int i = 0; i < d1; ++i)
    {
        array[i] = (float ***)malloc(d2 * sizeof(float **));
        if (!array[i])
        { // Simplified cleanup, proper cleanup is more verbose
            for (int k = 0; k < i; ++k)
                free(array[k]); // Assuming inner parts not allocated for array[k]
            free(array);
            return NULL;
        }
        for (int j = 0; j < d2; ++j)
        {
            array[i][j] = (float **)malloc(d3 * sizeof(float *));
            if (!array[i][j])
            { // Simplified cleanup
                for (int k = 0; k < j; ++k)
                    free(array[i][k]);
                free(array[i]);
                // And then free previous array[0]...array[i-1]
                for (int l = 0; l < i; ++l)
                {
                    for (int m = 0; m < d2; ++m)
                    { // This is still not quite right for full cleanup
                      // free(array[l][m]) etc.
                    }
                    free(array[l]);
                }
                free(array);
                return NULL;
            }
            for (int k = 0; k < d3; ++k)
            {
                array[i][j][k] = (float *)malloc(d4 * sizeof(float));
                if (!array[i][j][k])
                { // Simplified cleanup
                    for (int l = 0; l < k; ++l)
                        free(array[i][j][l]);
                    free(array[i][j]);
                    // ... and so on upwards
                    free(array);
                    return NULL;
                }
            }
        }
    }
    return array;
}

// Helper to free 4D array used by main
static void main_free_4d_float_array(float ****array, int d1, int d2, int d3)
{
    if (!array)
        return;
    for (int i = 0; i < d1; ++i)
    {
        if (array[i])
        {
            for (int j = 0; j < d2; ++j)
            {
                if (array[i][j])
                {
                    for (int k = 0; k < d3; ++k)
                    {
                        free(array[i][j][k]);
                    }
                    free(array[i][j]);
                }
            }
            free(array[i]);
        }
    }
    free(array);
}

// Helper function to print a 3D float array (image)
void print_image_c(const float ***image, const OutputDimensions *dims, const char *label)
{
    if (!image || !dims)
    {
        printf("%s is NULL or dims are NULL.\\n", label);
        return;
    }
    printf("%s (Channels: %d, Height: %d, Width: %d)\\n",
           label, dims->channels, dims->height, dims->width);

    for (int c = 0; c < dims->channels; ++c)
    {
        printf("Channel %d:\\n", c);
        if (!image[c])
        {
            printf("  Channel %d is NULL.\\n", c);
            continue;
        }
        for (int h = 0; h < dims->height; ++h)
        {
            printf("  ");
            if (!image[c][h])
            {
                printf("Row %d in Channel %d is NULL.\\n", h, c);
                continue;
            }
            for (int w = 0; w < dims->width; ++w)
            {
                printf("%.2f\\t", image[c][h][w]);
            }
            printf("\\n");
        }
        printf("\\n");
    }
}

// External declaration for free_3d_float_array from convolution_c.c
// This is needed because main_c.c calls it directly to free the output_image
// and the prototype is not in convolution_c.h explicitly (it's only used by destroy_convolution_layer_c there)
// Making it extern here makes the linkage clear.
// Alternatively, add its prototype to convolution_c.h.
extern void free_3d_float_array(float ***array, int d1, int d2);

int main()
{
    const int KERNEL_SIZE = 3;
    const int STRIDE = 1;
    const PaddingModeC PADDING_MODE = PADDING_VALID;
    const int INPUT_CHANNELS = 3;
    const int OUTPUT_CHANNELS = 1;
    const int INPUT_HEIGHT = 32;
    const int INPUT_WIDTH = 32;

    printf("Initializing C Convolution Layer...\\n");
    printf("Kernel Size: %d\\n", KERNEL_SIZE);
    printf("Stride: %d\\n", STRIDE);
    printf("Padding Mode: %s\\n", (PADDING_MODE == PADDING_VALID ? "VALID" : "SAME"));
    printf("Input Channels: %d\\n", INPUT_CHANNELS);
    printf("Output Channels: %d\\n", OUTPUT_CHANNELS);
    printf("Input Dimensions: %dx%dx%d\\n", INPUT_CHANNELS, INPUT_HEIGHT, INPUT_WIDTH);

    // --- 1. Initialize Kernel Weights (Dynamically) ---
    float ****kernel_weights = main_allocate_4d_float_array(OUTPUT_CHANNELS, INPUT_CHANNELS, KERNEL_SIZE, KERNEL_SIZE);
    if (!kernel_weights)
    {
        fprintf(stderr, "Failed to allocate kernel_weights in main.\\n");
        return 1;
    }
    float val = 1.0f / (float)(KERNEL_SIZE * KERNEL_SIZE); // Ensure float division
    for (int oc = 0; oc < OUTPUT_CHANNELS; ++oc)
    {
        for (int ic = 0; ic < INPUT_CHANNELS; ++ic)
        {
            for (int kh = 0; kh < KERNEL_SIZE; ++kh)
            {
                for (int kw = 0; kw < KERNEL_SIZE; ++kw)
                {
                    kernel_weights[oc][ic][kh][kw] = val;
                }
            }
        }
    }
    if (INPUT_CHANNELS > 1 && KERNEL_SIZE == 3)
    { // Make sure indices are valid
        if (OUTPUT_CHANNELS > 0 && INPUT_CHANNELS > 1 && KERNEL_SIZE >= 3)
        {
            kernel_weights[0][1][0][0] = 0.0f;
            kernel_weights[0][1][0][1] = 0.0f;
            kernel_weights[0][1][0][2] = 0.0f;
            kernel_weights[0][1][1][0] = 0.0f;
            kernel_weights[0][1][1][1] = 1.0f;
            kernel_weights[0][1][1][2] = 0.0f;
            kernel_weights[0][1][2][0] = 0.0f;
            kernel_weights[0][1][2][1] = 0.0f;
            kernel_weights[0][1][2][2] = 0.0f;
        }
    }

    // --- 2. Create Input Image Data (Dynamically) ---
    float ***input_image = main_allocate_3d_float_array(INPUT_CHANNELS, INPUT_HEIGHT, INPUT_WIDTH);
    if (!input_image)
    {
        fprintf(stderr, "Failed to allocate input_image in main.\\n");
        main_free_4d_float_array(kernel_weights, OUTPUT_CHANNELS, INPUT_CHANNELS, KERNEL_SIZE);
        return 1;
    }
    for (int c = 0; c < INPUT_CHANNELS; ++c)
    {
        for (int h = 0; h < INPUT_HEIGHT; ++h)
        {
            for (int w = 0; w < INPUT_WIDTH; ++w)
            {
                input_image[c][h][w] = (float)(c * 100 + h * 10 + w);
            }
        }
    }

    // OutputDimensions input_dims_for_print = {INPUT_HEIGHT, INPUT_WIDTH, INPUT_CHANNELS};
    // print_image_c((const float***)input_image, &input_dims_for_print, "Input Image"); // Optional

    // --- 3. Create Convolution Layer ---
    ConvolutionLayerC *conv_layer = create_convolution_layer_c(
        KERNEL_SIZE, STRIDE, PADDING_MODE, INPUT_CHANNELS, OUTPUT_CHANNELS, (const float ****)kernel_weights);
    if (!conv_layer)
    {
        fprintf(stderr, "Failed to create convolution layer.\\n");
        main_free_3d_float_array(input_image, INPUT_CHANNELS, INPUT_HEIGHT);
        main_free_4d_float_array(kernel_weights, OUTPUT_CHANNELS, INPUT_CHANNELS, KERNEL_SIZE);
        return 1;
    }

    // --- 4. Perform Convolution ---
    printf("\\nPerforming C convolution...\\n");
    OutputDimensions output_dims;
    float ***output_image = forward_convolution_c(conv_layer, (const float ***)input_image, INPUT_HEIGHT, INPUT_WIDTH, &output_dims);

    if (!output_image)
    {
        fprintf(stderr, "Convolution failed.\\n");
        destroy_convolution_layer_c(conv_layer);
        main_free_3d_float_array(input_image, INPUT_CHANNELS, INPUT_HEIGHT);
        main_free_4d_float_array(kernel_weights, OUTPUT_CHANNELS, INPUT_CHANNELS, KERNEL_SIZE);
        return 1;
    }
    printf("C Convolution complete.\\n");

    // --- 5. Print Output Image ---
    print_image_c((const float ***)output_image, &output_dims, "Output Image (C)");

    // --- Clean up for first test case ---
    // The `output_image` is freed using the function from `convolution_c.c` (or a compatible one)
    // as it was allocated by `forward_convolution_c`.
    free_3d_float_array(output_image, output_dims.channels, output_dims.height);

    // --- Test with SAME padding and stride 2 ---
    const int STRIDE_2 = 2;
    const PaddingModeC PADDING_MODE_SAME = PADDING_SAME;
    printf("\\n\\nInitializing C Convolution Layer (Stride 2, SAME padding)...\\n");

    ConvolutionLayerC *conv_layer_same_s2 = create_convolution_layer_c(
        KERNEL_SIZE, STRIDE_2, PADDING_MODE_SAME, INPUT_CHANNELS, OUTPUT_CHANNELS, (const float ****)kernel_weights);
    if (!conv_layer_same_s2)
    {
        fprintf(stderr, "Failed to create convolution layer (SAME, Stride 2).\\n");
        destroy_convolution_layer_c(conv_layer);
        main_free_3d_float_array(input_image, INPUT_CHANNELS, INPUT_HEIGHT);
        main_free_4d_float_array(kernel_weights, OUTPUT_CHANNELS, INPUT_CHANNELS, KERNEL_SIZE);
        return 1;
    }

    printf("\\nPerforming C convolution (Stride 2, SAME padding)...\\n");
    OutputDimensions output_dims_same_s2;
    float ***output_image_same_s2 = forward_convolution_c(conv_layer_same_s2, (const float ***)input_image, INPUT_HEIGHT, INPUT_WIDTH, &output_dims_same_s2);

    if (!output_image_same_s2)
    {
        fprintf(stderr, "Convolution failed (SAME, Stride 2).\\n");
        destroy_convolution_layer_c(conv_layer_same_s2);
        destroy_convolution_layer_c(conv_layer);
        main_free_3d_float_array(input_image, INPUT_CHANNELS, INPUT_HEIGHT);
        main_free_4d_float_array(kernel_weights, OUTPUT_CHANNELS, INPUT_CHANNELS, KERNEL_SIZE);
        return 1;
    }
    printf("C Convolution complete (Stride 2, SAME padding).\\n");
    print_image_c((const float ***)output_image_same_s2, &output_dims_same_s2, "Output Image (C, Stride 2, SAME padding)");

    // --- Final Clean up ---
    printf("\\nCleaning up C resources...\\n");
    free_3d_float_array(output_image_same_s2, output_dims_same_s2.channels, output_dims_same_s2.height);
    destroy_convolution_layer_c(conv_layer_same_s2);
    destroy_convolution_layer_c(conv_layer);
    main_free_3d_float_array(input_image, INPUT_CHANNELS, INPUT_HEIGHT);
    main_free_4d_float_array(kernel_weights, OUTPUT_CHANNELS, INPUT_CHANNELS, KERNEL_SIZE);

    printf("C Demo finished.\\n");
    return 0;
}