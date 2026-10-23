# SMT-FAI

SMT 首件核对桌面工具（Windows / Linux，后续可出 Android）：

1. 导入 **T100 BOM** 与 **站位表 A / B**，按料号核对插件位置与站位表位号；
2. 结果分为 **PASS / NG / 已排除物料 / 替代料** 四个区，每行后方标注异常原因；每行可人工确认并填写备注，确认记录写入核对报告；
3. 核对结果与 **原始坐标文件** 合并，生成 **FAI i450 首件测试仪** 用的 CAD 坐标文件；
4. 界面支持 中文 / English / ไทย 切换；主题可选 浅色 / 深色 / 跟随系统（标题栏右上角一键切换，或「视图 → 主题」）。
5. 界面按功能分区：文件导入 / 核对 / 规则 / 坐标视图 / CAD 输出，每个标签对应一个功能页和它自己的功能区按钮；图标为自绘双色线性图标。
7. 差异清单：汇总 BOM、站位表 A/B、坐标文件之间的全部不一致（缺失、多余、用量、描述不符、坐标缺失、面别不符等），每条给出原因说明。
8. PCB 导航图：按元件库模型逼真绘制（63 种元件：阻容感、电解/钽电容、二极管、LED、晶体管与功率封装、SOP/QFP/QFN/BGA 等 IC 封装、晶振、FPC/BTB/Type-C 等连接器、开关、蜂鸣器、屏蔽框……），坐标不变、拥挤或上下两面重叠的元件自动收缩；实物配色 / 类型配色 / 核对结果配色；2D 平面或 3D 立体视图（可倾斜、旋转）；识别不准时右键（长按）元件更换模型；TOP 面 / BOT 面 / 所有面、镜像、旋转。
10. 文件导入页：点击或拖拽导入，逐个文件显示检查结果；首次启动有新手引导，「设置 → 使用说明」随时查看说明并可重新引导。
9. 设置：主题、语言、检查更新与应用内更新（来源为本仓库的 GitHub Releases）。
6. 界面缩放：安卓端自动按屏幕尺寸缩放（平板按 1280×800 布局铺满屏幕），也可在「设置 → 外观」手动选择 80%–150%。
   自适应布局：宽屏时核对页右侧停靠属性面板，窄屏时属性面板浮出、结果以卡片显示；触屏自动加大点击区域，坐标视图支持双指缩放。

## 安装与升级

- **Windows**：推荐使用 `SMT-FAI-<版本>-windows-x64-setup.exe`（ARM 设备用 `-arm64-setup.exe`），按当前用户安装，无需管理员权限；新版本直接运行安装程序即可覆盖升级，应用内更新也会自动完成。也可以使用 zip 绿色版。
- **Linux**：`sudo apt install ./SMT-FAI-<版本>-linux-x64.deb`（ARM 用 `-arm64.deb`），新版本同样方式覆盖升级；或解压 tar.gz 运行。
- **Android**：安装与设备架构对应的 APK（不确定时用 `-universal.apk`）。自 1.4.0 起所有 APK 使用同一正式签名，后续版本可直接覆盖升级；从 1.3.0 及更早版本升级需先卸载一次。

签名证书 SHA-256 指纹见 `docs/signing/android-cert-sha256.txt`，CI 会校验每个 APK 都由该证书签名。

技术栈：Flutter（Dart），界面全部自绘，不使用 Material 组件；图标为 Phosphor 图标字体（MIT）。

## 核对规则

| 情况 | 结果 |
| --- | --- |
| BOM 位号与站位表（A+B 合并）位号完全一致，用量 = 位号数 | PASS |
| 部分 / 全部位号由替代料贴装，其余一致 | 替代料 |
| 站位表缺少位号、多出位号、BOM 用量与位号数不符、位号被其他料号占用、同一位号出现在 A/B 两面、站位表料号不在 BOM | NG |
| 品名/规格含排除关键字（PCB、锡膏、DIP、插件、贴纸…）、料号前缀被排除、无插件位置、成品主件（用量 0），且站位表上没有该料 | 已排除物料 |
| 空白料与烧录料（品名含 烧录 / PRG / F/W）共用位号，烧录料已上料 | 已排除物料（由烧录料贴装） |

- 替代关系来源：站位表中主料下一行「站位、位号为空」的备料行；站位表「关联料号」与「料号」不同的行；BOM 的「替代料号」列（如有）；「规则 → 替代料」中手工维护的对照表（`主料号=替代料1,替代料2`）。
- Mark 点等位号可在「规则 → 常规 → 忽略位号」中配置（支持 `*` 通配）。
- 四个区互不重叠，数量相加等于全部。

## 文件识别

- 支持 `.xlsx` / `.csv` / `.txt`；文本文件自动识别 UTF-8 / UTF-16 / GBK 编码与分隔符。旧版 `.xls` 需先在 Excel 中另存为 `.xlsx`。
- 表头按关键字自动定位（可在表头前有标题行），例如 BOM：`料件编号 / 品名 / 规格 / 组成用量 / 插件位置 / 替代料号`；站位表：`站位 / 料号 / 关联料号 / 物料描述 / 数量 / 位号`；坐标：`Name / X/mm / Y/mm / Orientation / Layer` 或 `Designator / Center-X(mm) / Rotation`（Altium、无表头 `位号 X Y 角度 面` 等格式均可）。
- 插件位置支持 `,，;；、空格` 分隔和 `R1-R5`、`R1~5` 范围写法；T100 在单元格内按固定宽度插入的换行（如 `8R` ↵ `23`）会自动拼回；位号过长换到下一行的续行会自动合并。
- xlsx 由内置读取器解析，只读取单元格值，不受 ERP 导出的特殊样式影响。
- 坐标单位可自动识别（mm / mil / inch），也可在「规则 → 坐标单位」中强制指定。

## FAI i450 CAD 文件

默认输出与 FAI 程序自带的「CAD BOM 合并导出」模板（`db/template_bom.xlsx`）一致的 Excel 文件，每个位号一行：

| Location | X | Y | Angle | Specification | PartNo | Layer | Qty |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C10 | 45.565 | 24.411 | 90 | 贴片电容 10uF 6.3V X5R 0603 | K1103-0106K0-001A | TOP | 1 |

- FAI 按表头关键字识别列（`config/cad_property.ini`、`bom_property.ini`），面别按 `PcbLayer.dat` 识别 `TOP / BOTTOM`，因此同一个文件既能作为 CAD 也能作为 BOM 导入。
- 坐标单位 mm；Specification 为 BOM 品名，PartNo 为 BOM 料号（可改为上料料号）；坐标文件无面别时按站位表 A=TOP、B=BOTTOM 补齐。
- 生成检查：缺少坐标的位号、不在 BOM 中的坐标（空贴/非 SMT 点，默认不输出）、面别未知、坐标面别与站位表 A/B 面不符。
- 「输出 → CAD 格式」可改列顺序、表头、单位、小数位、面别文字，也可切换为 CSV/TXT 文本格式。

## 开发与构建

```bash
export PATH=$HOME/development/flutter/bin:$PATH
flutter pub get
flutter test                      # 核心逻辑单元测试
dart run tool/gen_demo.dart       # 生成 samples/demo 演示数据
flutter test tool/screenshot_test.dart --update-goldens   # 渲染界面截图到 tool/screens/
```

Linux 桌面版（需先安装系统依赖）：

```bash
sudo apt install -y clang cmake ninja-build libgtk-3-dev
flutter build linux --release     # 输出 build/linux/x64/release/bundle/
```

Windows 版需在 Windows 上安装 Flutter 与 Visual Studio（“使用 C++ 的桌面开发”工作负载）后执行：

```bash
flutter build windows --release   # 输出 build\windows\x64\runner\Release\
```

## 持续集成与分支

GitHub Actions（`.github/workflows/build.yml`）先跑分析和单元测试，再构建 Flutter 支持发布的全部架构：

| 平台 | 架构 | 产物 |
| --- | --- | --- |
| Windows | x64、arm64 | `SMT-FAI-<版本>-windows-<架构>.zip`（解压即用） |
| Linux | x64、arm64 | `.tar.gz` 与 `.deb`（安装到 `/opt/smt-fai`，带桌面图标） |
| Android | armeabi-v7a、arm64-v8a、x86_64 | 各架构 APK、通用 APK、AAB |

- Windows / Linux 的 arm64 版本在 GitHub 的 ARM 构建机上原生编译（Flutter 不支持交叉编译这两个平台）。Flutter 已不再支持 32 位 x86 的 Windows / Linux / Android 发布版；Linux riscv64 仍是实验性支持，GitHub 也没有对应构建机，因此不在列表中。
- 产物在 Actions 运行页的 Artifacts 中下载；打 `v*` 标签时自动发布到 Releases（说明取自 `docs/release-notes/<标签>.md`），应用内更新即从这里下载。
- 发布新版本：修改 `pubspec.yaml` 的 `version` 与 `lib/version.dart`（单元测试会检查两者一致），写好发布说明，构建通过后打标签。
- 开发提交先推送到 `dev` 分支，全部构建通过后再同步到 `main`，`main` 只包含构建成功的代码。
- 客户资料（`samples/` 下除 `demo/` 外的文件）和 FAI 程序不进入仓库。

快捷键：`F5` 开始核对，`Ctrl+E` 导出核对报告，`Ctrl+G` 生成 CAD。

## 目录

```
lib/core/      解析、核对引擎、导出（纯 Dart，可单测）
lib/ui/        功能区、结果表、坐标视图、CAD 预览、对话框
lib/l10n/      中 / 英 / 泰 文本
samples/       样例文件（demo/ 为生成的演示数据）
tool/          演示数据生成、界面截图
```
