# SMT-FAI

SMT 首件核对桌面工具（Windows / Linux，后续可出 Android）：

1. 导入 **T100 BOM** 与 **站位表 A / B**，按料号核对插件位置与站位表位号；
2. 结果分为 **PASS / NG / 已排除物料 / 替代料** 四个区，每行后方标注异常原因；
3. 核对结果与 **原始坐标文件** 合并，生成 **FAI i450 首件测试仪** 用的 CAD 坐标文件；
4. 界面支持 中文 / English / ไทย 切换，深色 / 浅色主题。

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

- GitHub Actions（`.github/workflows/build.yml`）：分析 + 单元测试 → 构建 Linux / Windows / Android，产物在 Actions 的 Artifacts 中下载；打 `v*` 标签时自动发布 Release。
- 开发提交先推送到 `dev` 分支，Actions 全部通过后再同步到 `main`，`main` 只包含构建成功的代码。
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
