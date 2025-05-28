# Conv Testbench Usage Guide

## 概述

完整功能的 `conv_tb.v` 测试台现在提供详细的显示信息，包含所有关键的调试和验证内容。

## 显示内容

测试台按顺序显示以下内容：

### 0. 基本配置

- 图像尺寸、输出尺寸
- 通道数、滤波器数量
- 卷积核尺寸、步长、填充
- 数据位宽、权重位宽、输出位宽
- 权重文件名、选定的测试用例

### 1. 测试用例信息

- 测试用例类型和详细描述
- 测试模式的特点说明

### 2. 测试图片

- 显示所有通道的输入图像数据
- 按通道分别显示，便于查看输入模式

### 3. 滤波器权重

- 显示所有滤波器的权重值
- 按滤波器和通道分别显示
- 便于验证权重加载是否正确

### 4. 实际结果 vs 预期结果

- 详细的位置对比表
- 每个位置显示期望值、实际值和匹配状态
- 按滤波器分别显示

### 5. 错误统计和正确率

- 详细的错误分析
- 每个滤波器的准确率统计
- 总体准确率和通过状态

## 如何选择测试用例

在 `conv_tb.v` 文件的参数部分，修改 `TEST_CASE_SELECT` 参数的值：

```verilog
// Test case selection parameter - 修改这个值来选择不同的测试用例
parameter TEST_CASE_SELECT = 0;  // 修改这个值 (0-6)
```

## 可用的测试用例

| 测试用例 | 描述                 | 特点                                   |
| -------- | -------------------- | -------------------------------------- |
| 0        | Gradient Pattern     | 梯度模式，值从左上角到右下角递增       |
| 1        | Checkerboard Pattern | 棋盘模式，交替的 0xFF 和 0x00 值       |
| 2        | Random Pattern       | 随机模式，伪随机值                     |
| 3        | All-Zeros Pattern    | 全零模式，所有像素为 0x00              |
| 4        | All-Max Pattern      | 全最大值模式，所有像素为 0xFF          |
| 5        | Border Pattern       | 边界模式，边缘为 0xFF，中心为 0x00     |
| 6        | Diagonal Pattern     | 对角线模式，对角线为 0xFF，其他为 0x00 |

## 运行测试

1. 修改 `TEST_CASE_SELECT` 参数
2. 运行仿真：
   ```bash
   iverilog -o conv_tb conv_tb.v conv.v weight.v window.v mult_acc_comb.v
   ./conv_tb
   ```

## 示例输出

```
=== Comprehensive Conv Module Test ===
Configuration:
  Image size: 8x8
  Output size: 8x8
  Channels: 3, Filters: 3
  Kernel size: 3x3
  Stride: 1, Padding: 1
  Data width: 8 bits, Weight width: 8 bits
  Output width: 20 bits
  Weight file: weights.mem
  Selected test case: 0

Loading weights from weights.mem...
Golden weights loaded successfully (81 weights)

=== Weights (Unsigned Values) ===
Filter 0:
  Channel 0:
      1   2   3
      4   5   6
      7   8   9
  Channel 1:
     10  11  12
     13  14  15
     16  17  18
  Channel 2:
     19  20  21
     22  23  24
     25  26  27

================================================================================
Running Test Case 0 (Pattern Type 0)
================================================================================

=== Test Case Information ===
Pattern Type 0: Gradient Pattern - Values increase from top-left to bottom-right
=============================

Generating gradient test pattern

=== Test Image (Unsigned Values) ===
Channel 0:
    1   2   3   4   5   6   7   8
    9  10  11  12  13  14  15  16
   17  18  19  20  21  22  23  24
   25  26  27  28  29  30  31  32
   33  34  35  36  37  38  39  40
   41  42  43  44  45  46  47  48
   49  50  51  52  53  54  55  56
   57  58  59  60  61  62  63  64

Calculating golden reference (unsigned arithmetic, matching window.v logic)...
Golden reference calculation completed

DUT weights loaded successfully
Feeding image data...
Waiting for 64 outputs...

Output  1 at [0,0]: Filter0=12, Filter1=27, Filter2=42
Output  2 at [0,1]: Filter0=15, Filter1=30, Filter2=45
...

=== Expected vs Actual Results (Unsigned) ===
Filter 0:
  Position | Expected | Actual | Status
  ---------|----------|--------|--------
  [0,0]    |       12 |     12 | PASS
  [0,1]    |       15 |     12 | FAIL
  [0,2]    |       18 |     15 | FAIL
  ...

=== Detailed Comparison Results ===
Filter 0 detailed analysis:
  MISMATCH [0,1]: Expected=15, Actual=12, Diff=-3
  MISMATCH [0,2]: Expected=18, Actual=15, Diff=-3
  ...

=== Test Case 0 Summary ===
  Pattern Type: 0
  Total comparisons: 192
  Matches: 180
  Mismatches: 12
  Accuracy: 93.75%
  Status: FAILED
  Filter 0: 60/64 correct (93.75%)
  Filter 1: 60/64 correct (93.75%)
  Filter 2: 60/64 correct (93.75%)
```

## 调试建议

1. **配置验证**：首先检查基本配置是否符合预期
2. **权重检查**：验证权重是否正确加载
3. **输入验证**：检查测试图像是否按预期生成
4. **逐位对比**：查看详细的位置对比，找出错误模式
5. **滤波器分析**：分析每个滤波器的准确率，定位问题滤波器
6. **从简单开始**：建议先运行测试用例 3（全零模式）验证基本功能

这样的完整显示让你可以全面了解测试的每个环节，便于深入调试和问题定位！
