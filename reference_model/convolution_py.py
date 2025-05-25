import math

class ConvolutionLayer:
    def __init__(self, kernel_size, stride, padding_mode, input_channels, output_channels, initial_kernel_weights):
        if not (isinstance(kernel_size, int) and kernel_size > 0):
            raise ValueError("Kernel size must be a positive integer.")
        if not (isinstance(stride, int) and stride > 0):
            raise ValueError("Stride must be a positive integer.")
        if padding_mode not in [0, 1]: # 0 for VALID, 1 for SAME
            raise ValueError("Padding mode must be 0 (VALID) or 1 (SAME).")
        if not (isinstance(input_channels, int) and input_channels > 0):
            raise ValueError("Input channels must be a positive integer.")
        if not (isinstance(output_channels, int) and output_channels > 0):
            raise ValueError("Output channels must be a positive integer.")
        if not initial_kernel_weights:
            raise ValueError("Initial kernel weights cannot be empty.")

        self.kernel_size = kernel_size
        self.stride = stride
        self.padding_mode = padding_mode # Now stores 0 or 1
        self.input_channels = input_channels
        self.output_channels = output_channels
        self.kernel_weights = initial_kernel_weights # Expected: [out_c][in_c][k_h][k_w]

        # Validate kernel weights dimensions
        if len(self.kernel_weights) != self.output_channels:
            raise ValueError(f"Kernel weights outer dimension mismatch. Expected {self.output_channels}, got {len(self.kernel_weights)}")
        for oc_weights in self.kernel_weights:
            if len(oc_weights) != self.input_channels:
                raise ValueError(f"Kernel weights input_channels dimension mismatch. Expected {self.input_channels}, got {len(oc_weights)}")
            for ic_weights in oc_weights:
                if len(ic_weights) != self.kernel_size:
                    raise ValueError(f"Kernel weights height dimension mismatch. Expected {self.kernel_size}, got {len(ic_weights)}")
                for k_row in ic_weights:
                    if len(k_row) != self.kernel_size:
                        raise ValueError(f"Kernel weights width dimension mismatch. Expected {self.kernel_size}, got {len(k_row)}")

    def _calculate_padding_amount(self, input_dim, target_output_dim):
        """Calculates padding needed on one side for 'SAME' padding."""
        padding = ((target_output_dim - 1) * self.stride + self.kernel_size - input_dim) / 2
        return max(0, int(padding))

    def forward(self, input_image):
        """
        Performs convolution.
        input_image: 3D list [input_channels][input_height][input_width]
        Returns: 3D list [output_channels][output_height][output_width]
        """
        if not input_image or not input_image[0] or not input_image[0][0]:
            raise ValueError("Input image cannot be empty.")
        if len(input_image) != self.input_channels:
            raise ValueError(f"Input image channels mismatch. Expected {self.input_channels}, got {len(input_image)}")

        input_height = len(input_image[0])
        input_width = len(input_image[0][0])

        padding_h = 0
        padding_w = 0

        if self.padding_mode == 0: # VALID padding
            output_height = (input_height - self.kernel_size) // self.stride + 1
            output_width = (input_width - self.kernel_size) // self.stride + 1
        elif self.padding_mode == 1: # SAME padding
            output_height = math.ceil(input_height / self.stride)
            output_width = math.ceil(input_width / self.stride)
            padding_h = self._calculate_padding_amount(input_height, output_height)
            padding_w = self._calculate_padding_amount(input_width, output_width)
        else:
            # This case should ideally not be reached due to __init__ validation
            raise ValueError("Invalid padding mode internal state.") 

        if output_height <= 0 or output_width <= 0:
            raise ValueError("Output dimensions are non-positive. Check kernel size, stride, and input dimensions.")

        output_image = [
            [[0.0 for _ in range(output_width)] for _ in range(output_height)]
            for _ in range(self.output_channels)
        ]

        for out_c in range(self.output_channels):
            for out_h in range(output_height):
                for out_w in range(output_width):
                    current_sum = 0.0
                    for in_c in range(self.input_channels):
                        for k_h in range(self.kernel_size):
                            for k_w in range(self.kernel_size):
                                h_idx = out_h * self.stride + k_h - padding_h
                                w_idx = out_w * self.stride + k_w - padding_w

                                pixel_value = 0.0
                                if 0 <= h_idx < input_height and 0 <= w_idx < input_width:
                                    pixel_value = input_image[in_c][h_idx][w_idx]
                                
                                current_sum += pixel_value * self.kernel_weights[out_c][in_c][k_h][k_w]
                    output_image[out_c][out_h][out_w] = current_sum
        
        return output_image

def print_image_py(image, label):
    if not image:
        print(f"{label} is empty.")
        return

    channels = len(image)
    height = len(image[0]) if channels > 0 else 0
    width = len(image[0][0]) if height > 0 else 0

    print(f"{label} (Channels: {channels}, Height: {height}, Width: {width})")
    for c_idx, channel_data in enumerate(image):
        print(f"Channel {c_idx}:")
        if not channel_data:
            print("  Empty channel.")
            continue
        for r_idx, row_data in enumerate(channel_data):
            print("  ", end="")
            if not row_data:
                print("Empty row.")
                continue
            for val in row_data:
                print(f"{val:8.2f}", end="")
            print()
        print()

if __name__ == "__main__":
    # Parameters from readme.md
    KERNEL_SIZE = 3
    STRIDE = 1
    PADDING_MODE_VALID = 0 # readme: 0 Valid
    PADDING_MODE_SAME = 1   # readme: 1 Same
    INPUT_CHANNELS = 3  # readme: (默认为 3 RGB)
    OUTPUT_CHANNELS = 1 # readme: (默认为 1)
    INPUT_HEIGHT = 32
    INPUT_WIDTH = 32

    print("Initializing Python Convolution Layer...")
    print(f"Kernel Size: {KERNEL_SIZE}")
    print(f"Input Channels: {INPUT_CHANNELS}, Output Channels: {OUTPUT_CHANNELS}")
    print(f"Input Dimensions: {INPUT_CHANNELS}x{INPUT_HEIGHT}x{INPUT_WIDTH}")

    # --- 1. Initialize Kernel Weights ---
    avg_kernel_val = 1.0 / (KERNEL_SIZE * KERNEL_SIZE)
    kernel_weights = [
        [
            [
                [avg_kernel_val for _ in range(KERNEL_SIZE)] for _ in range(KERNEL_SIZE)
            ] for _ in range(INPUT_CHANNELS)
        ] for _ in range(OUTPUT_CHANNELS)
    ]

    if INPUT_CHANNELS > 1 and KERNEL_SIZE == 3 and OUTPUT_CHANNELS > 0:
        kernel_weights[0][1] = [
            [0.0, 0.0, 0.0],
            [0.0, 1.0, 0.0],
            [0.0, 0.0, 0.0]
        ]

    # --- 2. Create Input Image Data ---
    input_image_data = [
        [
            [float(c * 100 + h * 10 + w) for w in range(INPUT_WIDTH)] for h in range(INPUT_HEIGHT)
        ] for c in range(INPUT_CHANNELS)
    ]

    # --- Test Case 1: VALID padding (0), Stride 1 ---
    current_padding_mode_val = PADDING_MODE_VALID
    print(f"\n--- Test Case 1: Stride {STRIDE}, Padding Mode: {current_padding_mode_val} ({'VALID' if current_padding_mode_val == 0 else 'SAME'}) ---")
    try:
        conv_layer_valid = ConvolutionLayer(
            kernel_size=KERNEL_SIZE,
            stride=STRIDE,
            padding_mode=current_padding_mode_val,
            input_channels=INPUT_CHANNELS,
            output_channels=OUTPUT_CHANNELS,
            initial_kernel_weights=kernel_weights
        )
        print("Performing convolution...")
        output_image_valid = conv_layer_valid.forward(input_image_data)
        print("Convolution complete.")
        print_image_py(output_image_valid, f"Output Image (Padding {current_padding_mode_val}, Stride {STRIDE})")

    except ValueError as e:
        print(f"Error: {e}")

    # --- Test Case 2: SAME padding (1), Stride 2 ---
    STRIDE_2 = 2
    current_padding_mode_val = PADDING_MODE_SAME
    print(f"\n--- Test Case 2: Stride {STRIDE_2}, Padding Mode: {current_padding_mode_val} ({'VALID' if current_padding_mode_val == 0 else 'SAME'}) ---")
    try:
        conv_layer_same_s2 = ConvolutionLayer(
            kernel_size=KERNEL_SIZE,
            stride=STRIDE_2,
            padding_mode=current_padding_mode_val,
            input_channels=INPUT_CHANNELS,
            output_channels=OUTPUT_CHANNELS,
            initial_kernel_weights=kernel_weights
        )
        print("Performing convolution...")
        output_image_same_s2 = conv_layer_same_s2.forward(input_image_data)
        print("Convolution complete.")
        print_image_py(output_image_same_s2, f"Output Image (Padding {current_padding_mode_val}, Stride {STRIDE_2})")

    except ValueError as e:
        print(f"Error: {e}")

    print("\nPython convolution demo finished.") 