# 阶段 3：本地 AI 模型实际集成

日期：2026-11-07。

## 交付

| 内容 | 位置 |
| --- | --- |
| llama.cpp 运行时（`llamadart` 0.17.2，经 Dart FFI；推理在后台 isolate，不阻塞界面）；只打包 llama.cpp：桌面 CPU + Vulkan，Android CPU（全部 ARM 变体） | `pubspec.yaml` |
| 模型目录：Qwen3-Embedding-0.6B（Q8_0，610 MB）与 Qwen3-4B（Q4_K_M，2.33 GB），均为 Apache-2.0；每个模型三个下载源（ModelScope、Hugging Face、hf-mirror），实测三处文件一致，SHA-256 固定在代码中 | `lib/core/local_ai/model_store.dart` |
| 下载管理：断点续传、服务器不支持续传时重新下载、依次尝试镜像（中文用户 ModelScope 优先）、校验 SHA-256 不符即删除、可取消；离线安装包放在程序目录 `models` 下的模型直接使用 | 同上 |
| 本地模型服务：向量（语义匹配）与按 JSON Schema 约束解码的结构化回答；模型缺失、加载失败、超时、输出不完整一律报错，不回退成规则结果冒充 AI | `lib/core/local_ai/local_ai.dart` |
| 列识别辅助：模型给出每列含义；程序只在内容符合时采纳，不推翻自己找到的料号 / 用量 / 位号列和按表头确认的列，分歧保留为记录 | `lib/core/local_ai/column_assist.dart`，`bom.dart`（`overrides`、`contentFits`） |
| 设置 → 本地模型：状态、大小、许可证、下载进度、校验进度、继续 / 取消 / 移除、启用开关、内存要求说明 | `settings_page.dart` |
| 基准测试工具：物料类别（40 条手写多语言 BOM 行）与列含义（生成表格，已知答案），对比程序、模型、程序 + 模型 | `tool/bench_local_ai.dart`、`tool/bench_items.dart` |
| 报告导出改用自己的 xlsx 写入器（`excel` 包停更且与 `archive` 4 冲突）；演示文件逐单元格不变 | `lib/core/xlsx_writer.dart` |
| 参数引擎（为阶段 4 提前完成）：阻值、容值、电感、电压、电流、功率（含 1/16W）、频率、精度、温漂、介质、尺寸、封装；单位换算后比较，区分相同 / 缺项 / 冲突 | `lib/core/params.dart` |
| 界面去掉紫色：AI 相关颜色改为青色 | `check_view.dart`、`settings_page.dart`、`report.dart` |

## 测试结果

- `flutter analyze` 无问题；`flutter test` 全部通过（下载管理 7 个，用本地 HTTP 服务器测试镜像回退、续传、哈希不符、服务器忽略续传、取消、随安装包模型；参数引擎 5 个；真实模型 3 个，只在本机有模型文件时运行）。
- CI 全平台构建通过。加入运行时后的安装包大小（未裁剪 → 裁剪后）：Linux x64 117 → 54 MB，Windows x64 115 → 45 MB，Windows ARM64 45 → 29 MB，Android（全部 APK + AAB）409 → 157 MB。阶段 2 时分别为 18 / 23 / 21 / 100 MB。

## 模型实测（本机：32 线程 CPU，14 GB 内存，无 GPU）

向量模型：200 条描述约 2.6 秒；同一物料中英文写法相似度 0.83，但德语电阻与「屏蔽罩」也有 0.65，**向量只能用来找候选，不能用来判定一致**。

语言模型基准（同一套题目）：

Qwen3-1.7B（不思考）：
```
items: model 62.5%  rules 90.0%  (40 lines, 490 ms/line)
  model wrong: NTC thermistor 10K 3950 0603 → capacitor; Ferrite bead 600R@100MHz 0603 → inductor; 磁珠 120R 0402 → inductor; 稳压二极管 5.1V SOD-323 → switch; LED green 0603 → transistor; 发光二极管 红色 0805 → diode; TPS62130RGTR QFN16 buck converter → switch; Crystal 24MHz 3225 20pF → ic; 无源晶振 32.768KHz → ic; FPC 0.5mm 30P → capacitor; Shield can 20x20mm → other; 屏蔽罩 SPTE 15x30 → connector; M2x4 screw → switch; ESD bag 100x150mm → other; 锡膏 SAC305 → switch
  rules wrong: AO3400 SOT-23 → unknown; NPN MMBT3904 → unknown; TPS62130RGTR QFN16 buck converter → unknown; STM32F103C8T6 LQFP48 → unknown
weak columns: program 96.2%  program+model 71.7%  (53 columns)
columns: program 99.3%  model 34.2%  program+model 95.0%  (298 columns, 40 sheets, 0 failed answers, 2462 ms/sheet)
```

Qwen3-4B（不思考）：
```
items: model 72.5%  rules 97.5%  (40 lines, 519 ms/line)
  model wrong: Ferrite bead 600R@100MHz 0603 → inductor; 磁珠 120R 0402 → inductor; TVS SMBJ5.0A → transistor; 发光二极管 红色 0805 → diode; STM32F103C8T6 LQFP48 → mechanical; 主控芯片 RK3566 BGA → other; Shield can 20x20mm → other; 屏蔽罩 SPTE 15x30 → other; M2x4 screw → switch; ESD bag 100x150mm → consumable; 锡膏 SAC305 → switch
  rules wrong: AO3400 SOT-23 → unknown
weak columns: program 96.2%  program+model 75.5%  (53 columns)
columns: program 99.3%  model 79.2%  program+model 95.6%  (298 columns, 40 sheets, 0 failed answers, 2853 ms/sheet)
```

1.7B 开启思考：物料类别 65.0%，列含义 35.8%，几乎没有改善。

峰值内存（含向量模型）：1.7B 2.1 GB，4B 3.3 GB。

## 结论与决定

1. **语言模型选 Qwen3-4B**：两项任务都明显好于 1.7B（列含义 79% 对 34%，物料类别 73% 对 63%），在本机速度相近；代价是多 1.2 GB 下载和约 1.2 GB 内存。上下文减到 4096 以降低内存。
2. **语言模型不自动改写列识别**：即使是 4B，只要允许它改写，整体准确率从 99.3% 降到 95.6%，程序把握不足的列上从 96.2% 降到 75.5%。按「无法确认不得自动判定通过」与「AI 不能覆盖已确认结论」的要求，这条通路保留在代码和基准测试中，但不接入默认核对流程；以后换更强的模型时重新测量再决定。
3. **语言模型的用处在阶段 4 用数据决定**：候选匹配中程序无法判断的情况（料号不同、参数不全）交给模型给出意见，结果仍由程序校验；若测得仍是负作用，本地模式只保留向量模型，并在报告中如实说明。
4. 列含义的判断目前主要靠程序（内容特征 + 通用知识），这不是关键词冒充 AI：界面和结果会标明每个结论来自程序还是模型。

## 发现的问题

1. 结构化输出把类别放在第一个字段时，1.7B 会把「MLCC」判成结构件；先让模型写出物料名称再给类别后修正。
2. JSON 输出 token 上限过小会被截断，已按列数放宽，并把失败计入基准结果而不是让程序崩溃。
3. 规则分类漏掉只写型号的器件（AO3400、MMBT3904、TPS62130、STM32F103）：已加入 NPN/PNP/N 沟道、buck/boost/converter 等通用词和「6 脚以上 IC 封装 → IC」规则。**因为这些规则是在看到这 40 条的错误后加的，规则在这套题上的 97.5% 不再算未见数据成绩**；独立测试集在阶段 9 建立。
4. `excel` 包已停更，无法与 `archive` 4 共存，已替换为自写的 xlsx 写入器。
