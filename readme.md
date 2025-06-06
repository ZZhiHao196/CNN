# 目标

实现可配置卷积运算
（1）卷积核大小- Kernel Size
（2）卷积步幅- Stride
（3）填充-Padding （0 Valid ; 1 Same ）
（4）输入通道-Input Channels （默认为 3 RGB）
（5）输出通道-Output Channels (默认为 1)

输入数据：

- 输入（一张 RGB 图片， 3*32*32）
- 输出 (一张图片，1*30*30 or 1*32*32)（padding 和 stride 决定）

# 流程

（1）参数设置

- 卷积核的大小（Kernel Size）
- **卷积的步幅（Stride）**：支持步长 1 和 2
- **卷积的填充 (Padding)**：支持 Valid（无填充）和 Same（保持输出尺寸）
- 输入通道数（Input Channels 默认为 3）
- 输出通道数（Output Channels 默认为 1）

（2）数据预加载与处理

- 预加载输入图像数据到 ROM（通过 COE 文件初始化）
- 预加载卷积核权重到 ROM（通过 COE 文件初始化）
- 从 ROM 读取数据到行缓冲区进行窗口滑动
- 根据 padding 配置动态处理边界数据

（3）卷积运算（滑窗法）

```python
for out_c in range(out_channels):
    for out_h in range(out_height):
        for out_w in range(out_width):
            sum = 0
            for in_c in range(in_channels):
                for k_h in range(kernel_size):
                    for k_w in range(kernel_size):
                        # 考虑 padding 和 stride
                        h_idx = out_h*stride + k_h - padding
                        w_idx = out_w*stride + k_w - padding
                        # 边界检查
                        if h_idx < 0 or h_idx >= height or w_idx < 0 or w_idx >= width:
                            pixel = 0  # padding 为 0
                        else:
                            pixel = input[in_c][h_idx][w_idx]
                        sum += pixel * kernel[out_c][in_c][k_h][k_w]
            output[out_c][out_h][out_w] = sum
```

- 输出宽度：$\frac{Width-Kernel\_Size+2*Padding}{Stride}+1$
- 输出高度：$\frac{Height-Kernel\_Size+2*Padding}{Stride}+1$

（4）结果存储与验证

- 将卷积结果存入 RAM 以便读出验证
- 方便与软件参考模型结果对比

# 模块分割与设计

## 1. 顶层模块结构

```
┌─────────────────────────────────────────────────────────────────┐
│                         卷积运算顶层                            │
│                                                                 │
│  ┌────────────┐      ┌───────────────┐      ┌────────────────┐  │
│  │            │      │               │      │                │  │
│  │ 控制器模块 │─────→│  窗口生成模块  │─────→│  卷积计算模块   │  │
│  │(状态机+参数)│      │(行缓冲+滑窗)  │      │(MAC阵列)       │  │
│  └────────────┘      └───────────────┘      └────────┬───────┘  │
│         │                     ↑                      │          │
│         │                     │                      ↓          │
│         │               ┌─────┴──────┐         ┌────────────┐   │
│         └──────────────→│ 输入数据ROM │         │ 输出数据RAM │   │
│                         │ 权重数据ROM │←────────┤            │   │
│                         └─────────────┘         └────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## 2. 核心模块详细说明

### 2.1 控制器模块

- **功能**：整体调度，生成控制信号和地址
- **实现**：状态机
- **参数寄存器**：
  - Kernel Size 寄存器：设置卷积核大小
  - **Stride 寄存器**：配置卷积步长（1 或 2）
  - **Padding 寄存器**：配置填充模式（0:Valid 或 1:Same）
  - 通道数配置寄存器
- **控制信号**：
  - ROM 地址生成（考虑 stride 影响）
  - FIFO 写使能控制
  - 卷积计算启动/完成同步
  - 结果存储控制
- **地址计算**：
  - 根据 stride 和 padding 动态计算输入地址
  - 计算输出结果存储地址

### 2.2 数据存储模块

- **功能**：存储输入图像数据、权重和计算结果
- **实现**：
  - 输入图像 ROM：通过 COE 文件预加载图像数据
  - 权重 ROM：通过 COE 文件预加载卷积核参数
  - 输出结果 RAM：双端口 RAM 存储计算结果
- **工作流程**：
  - 控制器按序从 ROM 读取数据（考虑 stride 步进）
  - 数据流向行缓冲区用于窗口生成
  - 计算结果写入输出 RAM

### 2.3 窗口生成模块

- **功能**：动态生成当前卷积窗口数据
- **实现**：基于 FIFO 的行缓冲区
- **详细结构**：
  - 行缓冲区：多个 FIFO，数据深度大于输入图像宽度
  - 窗口寄存器：3×3 寄存器阵列捕获当前窗口
- **数据流**：
  - 从 ROM 读取的像素数据同时写入 FIFO
  - FIFO 输出数据经行缓冲移位产生滑动窗口
  - 当窗口数据有效时，传递至卷积计算模块
- **Stride 处理**：
  - 当 stride=2 时，控制器跳过相应的像素
  - 地址生成逻辑增加步长计算
- **Padding 处理**：
  - 边界检测逻辑，检查当前位置是否超出原始图像范围
  - 当需要 padding=0 时，提供零值信号
  - 当 padding 模式为 Same 时，自动计算填充量保持输出尺寸

### 2.4 卷积计算模块

- **功能**：执行卷积乘累加运算
- **实现**：多通道并行 MAC 单元
- **计算流程**：
  - 接收窗口生成模块的 3×3 窗口数据
  - 从权重 ROM 读取卷积核参数
  - 9 个乘法器并行计算，三个通道同时处理
  - 将三个通道结果累加得到最终输出
  - 处理边界 padding 情况下的数据
  - 产生计算完成信号，等待下一窗口

## 3. 数据存储设计优化

### 3.1 输入数据存储

- **存储结构**：单端口 ROM（通过 COE 文件初始化）
- **数据位宽**：48 位（3 通道 ×16 位/像素）
- **容量需求**：32×32×48 位 = 48KB
- **地址映射**：线性寻址（row × width + col）

### 3.2 卷积核权重存储

- **存储结构**：单端口 ROM（通过 COE 文件初始化）
- **数据位宽**：48 位（匹配输入数据格式）
- **组织方式**：按(输出通道,kernel_h,kernel_w)组织
- **容量需求**：
  - 3×3 卷积核 ×3 通道 ×1 输出通道：27×16 位 = 432 位

### 3.3 行缓冲区设计

- **存储结构**：两个 FIFO
- **FIFO 深度**：大于图像宽度（>32）
- **数据位宽**：16 位（单通道像素）
- **工作方式**：
  - 行数据顺序进入 FIFO
  - 当积累足够行时，滑窗操作生成窗口
  - 特殊地址生成逻辑处理 stride 和 padding

### 3.4 输出数据存储

- **存储结构**：双端口 RAM
- **数据位宽**：96 位（用于并行存储多个结果）
- **容量需求**：输出尺寸 × 输出通道 × 数据位宽
- **特点**：支持同时写入计算结果和读出验证

## 4. Stride 和 Padding 实现细节

### 4.1 Stride 实现

- **控制模块中的处理**：

  - 输入步进控制：地址生成时乘以 stride 系数
  - 计算处理量的减少：输出高宽减小，节省计算资源

- **窗口生成的调整**：

  - 当 stride=2 时，滑窗每次移动 2 个像素位置
  - 行缓冲区读取控制信号适应步长变化

- **地址计算公式**：
  - 输入索引 = 输出索引 × stride + kernel 偏移 - padding

### 4.2 Padding 实现

- **Valid 模式（无填充）**：
  - 不执行边界填充
  - 输出尺寸 = (输入尺寸 - kernel_size) / stride + 1
- **Same 模式（等尺寸输出）**：

  - 输出尺寸 = 输入尺寸 / stride（向上取整）
  - 计算需要的填充量：pad = ((输出-1)\*stride + kernel - 输入)/2
  - 实现方法：边界检查，超出范围返回 0

- **边界处理逻辑**：
  - 检测当前访问坐标是否超出原始图像范围
  - 如超出范围，根据 padding 配置返回 0 或边缘值
  - 在卷积计算模块中执行边界检查和 padding 处理

## 5. FPGA 实现优化策略

### 5.1 测试数据预加载

- 使用 COE 文件预加载测试图像和权重数据
- 避免设计复杂的外部数据接口
- 便于对比验证和重复测试

### 5.2 资源优化

- FIFO 深度合理设置，避免资源浪费
- 复用乘法器资源
- 多路复用存储器访问
- 针对不同的 stride 值优化计算路径

### 5.3 调试机制

- 添加状态指示信号和计数器
- 关键节点添加测试探针
- 结果验证逻辑自动检查计算正确性
- 支持不同 stride 和 padding 配置的结果验证

# 开发计划

## 1. 软件建模与测试数据生成

- 使用 Python 实现卷积算法参考模型，包含 stride 和 padding 变量
- 生成多组测试图像数据和标准卷积结果，覆盖各种配置组合
- 生成 ROM 初始化所需的 COE 文件

## 2. RTL 模块实现

- 控制器模块和状态机设计，包含 stride 和 padding 配置参数
- 窗口生成模块（基于 FIFO 的行缓冲设计）添加 stride 和 padding 支持
- 卷积计算模块（并行 MAC 单元）支持边界处理
- 数据存储接口（ROM/RAM 设计）

## 3. 系统集成与功能验证

- 模块级功能测试：分别验证不同 stride 和 padding 配置
- 顶层系统集成
- 与软件模型结果对比验证
- 验证所有参数组合的正确性

## 4. FPGA 原型验证

- 综合与实现
- 在 FPGA 上进行完整功能测试
- 性能分析与优化
- 验证各种参数组合的实际效果

## 5. 后续扩展（可选）

- 支持可配置卷积核大小
- 添加 Padding 类型扩展（如反射填充等）
- 添加 Stride 配置扩展（支持更大步长）
- 扩展到更多输入/输出通道
