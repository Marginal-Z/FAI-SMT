# 验证记录

环境：Windows 主机、PowerShell 7；开发和测试使用 WSL2 Ubuntu 26.04.1、Flutter 3.47.7、Dart 3.13.5，与仓库 CI 的 Flutter 版本一致。源码与临时 SDK、缓存均位于 D 盘工作区。

保存的评估明细：[1000 份读取样本](evidence/reading-evaluation.md)、[400 份保留样本](evidence/holdout-evaluation.md)。界面证据：[浅色](evidence/orientation-light.png)、[深色](evidence/orientation-dark.png)。截图是实际 Flutter widget 渲染，使用仓库演示 BOM；不是 Windows 原生运行截图。

| 验证 | 结果与范围 |
|---|---|
| 原代码完整测试 | 88 通过，8 跳过 |
| 首批 12 个规则反例运行在原代码 | 1 通过，11 失败；原始代码副本与日志留在工作区 `.tools/baseline*` |
| 最终完整回归 | 122 通过，7 跳过；包括重启模型状态恢复、实际跨语言向量及真实 BOM 向量推理 |
| 静态分析 | `flutter analyze --no-pub lib test tool`：No issues found（53.9 秒） |
| 真实模型 | Granite-Embedding-107M Q8_0；真实跨语言向量、推理自检和 BOM 候选匹配；各次实测数据见下 |
| 读取生成器 | 1000 份；料号/描述/数量/位号列与记录读取均为 100%；厂商列 99.1%，DNP 列 85.4%，记录 DNP 98.6% |
| 独立保留生成器 | 400 份；6808 条未改动结果没有误判 NG、2247 条改动物料没有误判 PASS；层级列识别为 88.5%（139 份带层级样本） |
| 界面 | 390、800、1440 宽度的方向详情与本地模型设置交互通过；另检查 1600×1050 深色、浅色实际 Flutter 渲染 |
| 报告 | Excel 编码后重读，保留方向说明、位号与模型调用状态；历史保留原始输入副本及调用证据 |
| Linux x64 Release | 最终源码正式构建成功：`build/linux/x64/release/bundle/smt_fai`；依赖提取在工作区，没有向系统安装开发包 |
| Linux 原生启动 | Xvfb + 独立 DBus/配置目录，运行 12 秒后由 timeout 结束（124）；已初始化 Impeller 渲染，没有未处理异常。环境没有 Secret Service，本次未验证 Linux 密钥持久化 |
| Windows/Android/GPU | 没有原生运行或构建验证，不能从 Linux 测试外推 |
| 客户真实文件/实物方向 | 本次没有提供，未验证 |

真实模型文件 SHA-256：`15691dfe830257f569a1e3521977351d16eac18e48e414908dc98ed9b8455e07`，121,020,096 字节。测试读取真实 GGUF 文件，通过原生 llama.cpp 运行；不是模拟模型。本次没有单独验证 CPU/GPU 设备选择。初次自检实测 2391 ms，随后缓存模型核对 15 ms，处理两条描述、提出一对候选且结果为 REVIEW。耗时取决于缓存和设备，只是本次观测，不是性能承诺。

验证中的模拟云端服务只负责返回可控 JSON，用于核实程序的覆盖检查、拒绝错误答案、取消和隐私字段处理，不代表实际云端模型的效果。7 项跳过项来自未提供的其他模型/语言模型和客户真实样本。

本地原始日志位于 `.tools/`：`baseline-test.log`、`baseline-regressions.log`、`verified-tests.log`、`verified-analyze.log`、`eval-read.log`、`eval-holdout.log`、`verified-render.log`、`build-linux.log`、`native-smoke.log`。此目录被 Git 忽略，不包含交付源码；仓库中的回归测试、评估明细和本记录可用于重新验证。

复现命令在 **WSL Ubuntu** 的项目目录执行，前提是已安装 Flutter 3.47.7 和平台构建依赖：

```bash
flutter pub get
flutter test --concurrency=1
flutter analyze lib test tool
dart run tool/eval_read.dart 1000
dart run tool/eval_holdout.dart 400
flutter build linux --release
```

实际模型测试在 **WSL Ubuntu** 中额外设置模型目录：

```bash
SMT_FAI_MODELS=/path/to/models flutter test --concurrency=1 \
  test/local_ai_real_test.dart test/local_inference_smoke_test.dart
```

Flutter 原生构建与测试的 build hook 会共享原生资源目录，验证时顺序执行，避免构建过程暂时覆盖正在加载的运行库。
