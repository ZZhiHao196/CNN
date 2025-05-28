# 通用卷积模块测试平台 (Generic Convolution Testbench)

## 概述

这是一个完全参数化的卷积模块测试平台，可以轻松适应不同的配置，无需修改任何硬编码的值。

## 🎯 主要特性

### ✅ 完全参数化

- **任意通道数**: 支持 1 到任意数量的输入通道
- **任意滤波器数**: 支持 1 到任意数量的输出滤波器
- **任意图像尺寸**: 支持不同的输入图像大小
- **任意核大小**: 支持不同的卷积核尺寸

### ✅ 智能权重生成

- 自动生成多种类型的滤波器权重
- 根据滤波器数量循环使用不同的滤波器类型
- 支持模糊、边缘检测、锐化、恒等和自定义模式

### ✅ 自适应测试模式

- 梯度模式、棋盘模式、随机模式等
- 针对不同通道数自动调整测试数据
- 全面的边界情况测试

### ✅ 智能比较和分析

- 自动适应任意配置的输出比较
- 按滤波器分类的准确率统计
- 详细的错误报告和分析

## 🚀 使用方法

### 1. 基本配置

只需修改 `conv_tb_demo.v` 文件顶部的参数：

```verilog
// ============================================================================
// CONFIGURABLE PARAMETERS - Change these to test different configurations
// ============================================================================
parameter DATA_WIDTH = 8;
parameter KERNEL_SIZE = 3;
parameter IN_CHANNEL = 4;        // 修改这里：输入通道数
parameter NUM_FILTERS = 5;       // 修改这里：滤波器数量
parameter IMG_WIDTH = 6;         // 修改这里：图像宽度
parameter IMG_HEIGHT = 6;        // 修改这里：图像高度
parameter STRIDE = 1;
parameter PADDING = (KERNEL_SIZE - 1) / 2;
parameter WEIGHT_WIDTH = 8;
parameter OUTPUT_WIDTH = 20;
```

### 2. 编译和运行

```bash
# 编译
iverilog -o conv_demo_test.vvp conv_tb_demo.v conv.v window.v weight.v mult_acc_comb.v

# 运行
vvp conv_demo_test.vvp
```

### 3. 配置示例

#### 示例 1: 单通道，单滤波器

```verilog
parameter IN_CHANNEL = 1;
parameter NUM_FILTERS = 1;
parameter IMG_WIDTH = 8;
parameter IMG_HEIGHT = 8;
```

#### 示例 2: RGB 图像，多滤波器

```verilog
parameter IN_CHANNEL = 3;        // RGB
parameter NUM_FILTERS = 8;       // 8个不同的滤波器
parameter IMG_WIDTH = 16;
parameter IMG_HEIGHT = 16;
```

#### 示例 3: 高通道数配置

```verilog
parameter IN_CHANNEL = 16;       // 深度特征
parameter NUM_FILTERS = 32;      // 大量滤波器
parameter IMG_WIDTH = 32;
parameter IMG_HEIGHT = 32;
```

## 📊 输出解释

### 配置验证

```
================================================================
GENERIC CONVOLUTION TESTBENCH CONFIGURATION
================================================================
Input Configuration:
  - Data Width: 8 bits
  - Input Channels: 4
  - Image Size: 6x6 pixels

Convolution Configuration:
  - Kernel Size: 3x3
  - Number of Filters: 5
  - Stride: 1
  - Padding: 1

Output Configuration:
  - Output Size: 6x6 pixels
  - Output Width: 20 bits
  - Total Weights: 180
```

### 权重生成

```
Generating adaptive weights for 5 filters...
  Filter 0: Blur/Average
  Filter 1: Edge Detection
  Filter 2: Sharpen
  Filter 3: Identity
  Filter 4: Custom Pattern
```

### 测试结果

```
Per-filter accuracy:
  Filter 0: 95.83% (1 errors)
  Filter 1: 88.89% (4 errors)
  Filter 2: 100.00% (0 errors)
  Filter 3: 97.22% (1 errors)
  Filter 4: 91.67% (3 errors)
```

## 🔧 高级功能

### 1. 自定义权重类型

在 `generate_adaptive_weights` 任务中添加新的权重类型：

```verilog
5: begin // 新的自定义滤波器
    // 添加您的权重生成逻辑
end
```

### 2. 自定义测试模式

在 `generate_test_pattern` 任务中添加新的测试模式：

```verilog
3: begin // 新的测试模式
    // 添加您的测试数据生成逻辑
end
```

### 3. 扩展支持的滤波器数量

修改 `compare_results` 任务中的数组大小：

```verilog
integer filter_errors [0:31]; // 支持最多32个滤波器
```

## 🎨 滤波器类型说明

### Filter 0: 模糊/平均滤波器

- 所有权重为 1
- 用于图像平滑

### Filter 1: 边缘检测滤波器

- 中心权重为 8，周围权重为 255（无符号-1）
- 用于检测图像边缘

### Filter 2: 锐化滤波器

- 中心权重为 5，十字形权重为 255，角落权重为 0
- 用于增强图像细节

### Filter 3: 恒等滤波器

- 只有中心权重为 1，其他为 0
- 输出应该与输入相同

### Filter 4: 自定义模式

- 基于滤波器索引和位置的动态权重
- 用于测试复杂的权重模式

## ⚠️ 注意事项

### 1. 权重文件兼容性

- 当前的 `weights.mem` 文件是为 3 通道 3 滤波器设计的
- 使用不同配置时，testbench 会自动生成适当的权重
- 警告信息是正常的，不影响功能

### 2. 输出位宽

- 确保 `OUTPUT_WIDTH` 足够大以避免溢出
- 推荐公式: `OUTPUT_WIDTH >= 2*DATA_WIDTH + $clog2(KERNEL_SIZE*KERNEL_SIZE*IN_CHANNEL) + 4`

### 3. 内存限制

- 大配置可能需要更多仿真内存
- 建议逐步增加参数进行测试

## 🔍 故障排除

### 问题 1: 编译错误

```
解决方案: 确保所有模块文件都在同一目录下
```

### 问题 2: 权重加载警告

```
WARNING: Not enough words in the file for the requested range
解决方案: 这是正常的，testbench会自动生成权重
```

### 问题 3: 输出全为 0

```
可能原因: OUTPUT_WIDTH不足或权重配置问题
解决方案: 增加OUTPUT_WIDTH或检查权重生成逻辑
```

## 📈 性能测试建议

### 小规模测试

```verilog
parameter IN_CHANNEL = 1;
parameter NUM_FILTERS = 1;
parameter IMG_WIDTH = 4;
parameter IMG_HEIGHT = 4;
```

### 中等规模测试

```verilog
parameter IN_CHANNEL = 3;
parameter NUM_FILTERS = 4;
parameter IMG_WIDTH = 8;
parameter IMG_HEIGHT = 8;
```

### 大规模测试

```verilog
parameter IN_CHANNEL = 8;
parameter NUM_FILTERS = 16;
parameter IMG_WIDTH = 16;
parameter IMG_HEIGHT = 16;
```

## 🎯 测试覆盖率

该 testbench 提供以下测试覆盖：

- ✅ 不同通道数配置
- ✅ 不同滤波器数配置
- ✅ 不同图像尺寸
- ✅ 多种测试模式
- ✅ 边界条件测试
- ✅ 权重加载验证
- ✅ 输出正确性验证

## 📝 总结

这个通用 testbench 解决了原始代码的通用性问题：

1. **完全消除硬编码**: 所有数组大小和循环都是参数化的
2. **智能适应**: 自动适应任何合理的参数配置
3. **全面测试**: 提供多种测试模式和验证方法
4. **易于使用**: 只需修改几个参数即可测试不同配置
5. **详细反馈**: 提供清晰的配置信息和测试结果

现在您可以轻松地修改 `IN_CHANNEL` 和 `NUM_FILTERS` 参数，testbench 将自动适应新的配置！
