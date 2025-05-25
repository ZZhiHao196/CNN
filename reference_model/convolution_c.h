#ifndef CONVOLUTION_C_H
#define CONVOLUTION_C_H

#include <stdio.h>  // For printf (debugging, error messages)
#include <stdlib.h> // For malloc, free
#include <math.h>   // For ceilf

// Define an enum for padding modes in C
typedef enum
{
    PADDING_VALID,
    PADDING_SAME
} PaddingModeC;

// Forward declaration for the struct that will hold output dimensions
typedef struct
{
    int height;
    int width;
    int channels;
} OutputDimensions;

// ConvolutionLayer struct in C
typedef struct
{
    int kernel_size;
    int stride;
    PaddingModeC padding_mode;
    int input_channels;
    int output_channels;
    float ****kernel_weights; // [out_c][in_c][k_h][k_w] - will require careful dynamic allocation
} ConvolutionLayerC;

// Function prototypes

/**
 * @brief Creates and initializes a ConvolutionLayerC struct.
 *
 * Allocates memory for the layer and its weights.
 * The caller is responsible for calling destroy_convolution_layer_c to free memory.
 *
 * @param kernel_size Size of the convolution kernel.
 * @param stride Stride of the convolution.
 * @param padding_mode PADDING_VALID or PADDING_SAME.
 * @param input_channels Number of input channels.
 * @param output_channels Number of output channels.
 * @param initial_kernel_weights A 4D array representing kernel weights [out_c][in_c][k_h][k_w].
 *                               This function will copy these weights.
 * @return Pointer to the created ConvolutionLayerC, or NULL on failure.
 */
ConvolutionLayerC *create_convolution_layer_c(
    int kernel_size,
    int stride,
    PaddingModeC padding_mode,
    int input_channels,
    int output_channels,
    const float ****initial_kernel_weights // Assuming this is already allocated appropriately by caller for copying
);

/**
 * @brief Frees the memory allocated for a ConvolutionLayerC struct and its weights.
 *
 * @param layer Pointer to the ConvolutionLayerC struct to be destroyed.
 */
void destroy_convolution_layer_c(ConvolutionLayerC *layer);

/**
 * @brief Performs the forward convolution operation.
 *
 * The caller is responsible for freeing the returned 3D output_image array.
 * The dimensions of the output image are returned via the out_dims parameter.
 *
 * @param layer Pointer to the configured ConvolutionLayerC.
 * @param input_image 3D array [channels][height][width] representing the input image.
 * @param input_height Height of the input image.
 * @param input_width Width of the input image.
 * @param out_dims Pointer to an OutputDimensions struct to store the output dimensions.
 * @return 3D array [channels][height][width] representing the output image, or NULL on failure.
 *         The caller must free this memory (deep free).
 */
float ***forward_convolution_c(
    const ConvolutionLayerC *layer,
    const float ***input_image, // [in_c][input_height][input_width]
    int input_height,
    int input_width,
    OutputDimensions *out_dims);

#endif // CONVOLUTION_C_H