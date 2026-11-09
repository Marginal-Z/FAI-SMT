# 本地模型选择与方向提醒栏

本记录对应目标版本 v3.2.1 的模型选择与方向栏改动。

核对页新增独立模型栏：启用开关、四种匹配模型的下拉选择、下载状态和模型管理入口。选择与开关在下次核对生效，当前结果仍显示原来模型的调用证据。设置页复用同一个选择控件。正在推理或释放旧模型时锁定切换；选择未就绪模型不会自动下载或改用别的模型，已开启的偏好仍允许关闭。云端完整模式会说明本次不使用本地模型。

模型下拉支持鼠标、触摸、方向键、Enter 和 Escape；菜单按可用空间向上或向下展开。模型切换会先释放旧实例，下次推理加载新选择。设置改为保存快照并串行写入，避免快速切换时并发覆盖设置文件。

新增横栏后，一些手机首次引导目标可能位于屏幕外；引导浮层会对不可见目标使用居中说明，并限制位置在窗口内，保证「下一步」可点击。

结果表格新增独立「方向核对提醒」列，显示极性、Pin 1、缺口 / 卡扣等具体提醒和位号。手机卡片显示独立提醒区；完整描述、依据和位号仍在详情和 Excel 中。未触发提醒的表格单元格显示 `—`，不代表已经确认实物方向，BOM 核对状态与方向提醒分别保留。

界面证据为实际 Flutter widget 渲染，使用仓库演示 BOM 对照自身：[浅色](evidence/model-controls-direction-light.png)、[深色](evidence/model-controls-direction-dark.png)。不是 Windows 原生运行截图。

已完成的针对性验证：22 项通过，包含 390 / 800 / 1440 宽度、鼠标与键盘选择、缺失模型、启用和关闭、模型实例切换、调用证据保留、忙时锁定和设置文件重读。另有 1600 宽度浅色 / 深色及 390 宽度手机布局的三项渲染检查通过。

完整回归：128 项通过、7 项因缺少其他模型或客户样本跳过；包含手机首次引导与 80% / 150% 缩放交互。引擎切换和忙时测试使用可控测试模型；真实推理回归使用 Granite-Embedding-107M GGUF，不代表四种模型均已实际推理验证。

`flutter analyze --no-pub lib test tool` 无问题。Linux x64 Release 构建成功，Xvfb 隔离启动持续运行 12 秒后由 timeout 结束（退出码 124），没有未处理异常；当前环境缺少 Secret Service，因此没有验证 Linux 密钥存储。此次本地没有原生运行 Windows / Android，跨平台构建与安装包发布由后续发布流水线验证。

可在 **WSL Ubuntu** 的项目目录复现核心交互和状态测试：

```bash
flutter test --concurrency=1 test/local_model_controls_test.dart \
  test/review_ui_test.dart test/local_usage_test.dart test/orientation_test.dart
flutter analyze lib test tool
```
