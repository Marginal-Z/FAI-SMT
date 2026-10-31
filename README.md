<div align="center">

<img src="site/assets/icon.png" width="96" alt="SMT-FAI">

# SMT-FAI

**SMT 首件检验工具：T100 BOM 与站位表自动核对，一键生成 FAI i450 坐标文件**

[![最新版本](https://img.shields.io/github/v/release/Marginal-Z/FAI-SMT?label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC)](https://github.com/Marginal-Z/FAI-SMT/releases/latest)
[![构建](https://img.shields.io/github/actions/workflow/status/Marginal-Z/FAI-SMT/build.yml?branch=main&label=%E6%9E%84%E5%BB%BA)](https://github.com/Marginal-Z/FAI-SMT/actions/workflows/build.yml)
![平台](https://img.shields.io/badge/%E5%B9%B3%E5%8F%B0-Windows%20%7C%20Android%20%7C%20Linux-0071e3)

[官网](https://marginal-z.github.io/FAI-SMT/) · [使用教程](https://marginal-z.github.io/FAI-SMT/#tutorial) · [下载](https://github.com/Marginal-Z/FAI-SMT/releases/latest) · [更新记录](https://github.com/Marginal-Z/FAI-SMT/releases)

<img src="site/assets/check.webp" width="900" alt="BOM 核对界面">

</div>

## 简介

SMT-FAI 面向 SMT 产线的首件检验（FAI）。导入 T100 导出的 BOM 与贴片机站位表后，软件逐料号核对插件位置、站位位号与用量，列出每一处差异及原因；核对结果与 EDA 坐标文件合并，生成 FAI i450 首件测试仪可直接导入的 CAD 坐标文件，并可在 PCB 导航图中对照实物查看。

所有文件只在本机处理，不上传任何数据。

## 主要功能

| 功能 | 说明 |
| --- | --- |
| **文件导入** | 在 BOM 核对页顶部拖入或选择 T100 BOM、站位表 A / B；按单元格内容自动定位表头与各列（列名不限），导入后立即显示文件检查结果 |
| **智能核对** | 三种模式：BOM 与 BOM、BOM 与单站位表、BOM 与站位表 A+B。识别引擎按内容判断每列作用（位号格式、料号编码、数量是否等于位号数、描述用词、站位编号、面别），不依赖表头名称；识别结果可逐列手动修正。结果可预览、逐格编辑（结果、备注、任意单元格），软件内显示分析报告，导出 Excel |
| **AI 核对** | 独立功能：把所选表格发送给 Claude（Anthropic API）或任意 OpenAI 兼容接口，显示 AI 的分析并可导出；不参与、不改变本地核对结果 |
| **BOM 核对** | 结果分为 PASS、NG、已排除物料、替代料四类，NG 项逐条说明原因；支持人工确认与备注 |
| **差异清单** | 汇总 BOM、站位表 A / B、坐标文件之间的全部不一致：缺失、多余、用量、描述、坐标、面别 |
| **核对报告** | 一键导出 Excel，包含核对结果、原因、人工确认记录与备注 |
| **FAI 坐标** | 按 FAI i450 导入模板输出 CAD 文件；单位自动识别；列、表头、格式、编码可自定义 |
| **PCB 导航图** | 从封装名和物料描述自动识别封装、引脚数、排数、间距与尺寸（兼容 KiCad / Altium 封装名和中文 BOM 写法），按真实引脚数绘制 64 种元件模型；按位号搜索并自动定位、发光提示；2D / 3D、镜像、旋转；NG 位号标框；拥挤元件等比例缩小且坐标不变 |
| **核对规则** | 排除关键字（默认为空，需人工填写并保存）、排除料号前缀、编程件、替代料对照表、忽略位号 |
| **使用体验** | 中文 / English / ไทย；现代 / 工业两种界面风格；浅色 / 深色 / 跟随系统；22 步新手引导；手机、平板竖屏与横屏各有专属布局；应用内自动更新 |

## 下载与安装

前往 [Releases](https://github.com/Marginal-Z/FAI-SMT/releases/latest) 或 [官网下载页](https://marginal-z.github.io/FAI-SMT/#download) 获取最新版本。

| 平台 | 系统要求 | 安装包 |
| --- | --- | --- |
| Windows | Windows 10 / 11，x64 或 ARM64 | `SMT-FAI-<版本>-windows-x64-setup.exe`（推荐）、`-arm64-setup.exe`；或 zip 绿色版 |
| Android | Android 7.0 及以上 | `SMT-FAI-<版本>-android-universal.apk`；或对应架构的 APK |
| Linux | Debian / Ubuntu 及衍生版，x64 或 ARM64 | `SMT-FAI-<版本>-linux-x64.deb`、`-arm64.deb`；或 tar.gz |

- **Windows**：安装程序按当前用户安装，无需管理员权限。安装程序暂未进行商业代码签名，如出现 SmartScreen 提示，点击「更多信息 → 仍要运行」。
- **Android**：首次安装需允许「安装未知来源应用」。
- **Linux**：`sudo apt install ./SMT-FAI-<版本>-linux-x64.deb`。

### 升级

新版本直接安装即可覆盖升级，设置与核对规则会保留。软件启动时会自动检查更新，Windows 与 Android 可在应用内下载并安装。

> Android 1.3.0 及更早版本使用临时签名，升级到 1.4.0 及以后版本前需先卸载一次旧版。此后所有版本均使用同一正式签名，证书 SHA-256 指纹见 [`docs/signing/android-cert-sha256.txt`](docs/signing/android-cert-sha256.txt)。

## 快速上手

1. **导入文件**：在「BOM 核对」页顶部把 T100 BOM 与站位表 A 拖到对应卡片（双面板再导入站位表 B），确认显示「检查通过」。
2. **开始核对**：点击「开始核对」（`F5`）。在「BOM 核对」页按统计卡筛选，点击料号查看原因，核对无误后点「确认」。
3. **导出报告**：点击「导出 Excel」（`Ctrl+E`）保存核对报告。
4. **生成坐标**：在「CAD 坐标」页导入坐标文件，确认单位与格式后点「生成 CAD」（`Ctrl+G`）。
5. **对照实物**：在「PCB 导航图」页查看元件位置、按面别和核对结果着色。

完整图文教程见 [官网使用教程](https://marginal-z.github.io/FAI-SMT/#tutorial)；软件内「设置 → 使用说明」可随时查看，点击右上角问号可重新开始新手引导。

### 快捷键

| 按键 | 功能 |
| --- | --- |
| `F5` | 开始核对 |
| `Ctrl+E` | 导出核对报告 |
| `Ctrl+G` | 生成 CAD 坐标文件 |
| `F11` / `Esc` | PCB 导航图进入 / 退出全屏 |

## 输入文件要求

支持 `.xlsx`、`.csv`、`.txt`，坐标文件另支持 `.pos` 等常见 EDA 导出格式。文本文件自动识别 UTF-8 / UTF-16 / GBK 编码与分隔符。旧版 `.xls` 请先在 Excel 中另存为 `.xlsx`。

| 文件 | 需要的内容（列名不限） | 说明 |
| --- | --- | --- |
| BOM | 料号、位号；可选描述（品名 / 规格）、用量、替代料号 | 列按内容识别，表头前可以有标题行，也可以没有表头 |
| 站位表 A / B | 料号、位号；可选站位、描述、数量、关联料号、面别 | 替代关系可写在「关联料号」列；有面别列时单表也能区分两面 |
| 坐标文件 | 位号、X、Y、角度，可选面别 | 兼容 Altium、`Name / X/mm / Y/mm / Orientation / Layer` 及无表头 `位号 X Y 角度 面` 等格式 |

- 插件位置支持 `,，;；、` 与空格分隔，以及 `R1-R5`、`R1~5` 范围写法；T100 在单元格内按固定宽度插入的换行和换到下一行的续行会自动拼回。
- 坐标单位自动识别 mm / mil / inch，也可手动指定。

## 核对规则

核对没有内置规则：软件按文件内容逐个位号比对 BOM 与站位表（A + B 合并），每个位号判断「站位表上料的是哪个料号、贴在哪一面」，再汇总到料号。

| 情况 | 结果 |
| --- | --- |
| BOM 位号全部由该料号贴装，用量、描述、站位数量一致 | PASS |
| 部分位号由有依据的替代料贴装，其余一致 | 替代料 |
| 位号缺少、多出、被其他料号占用、两个料号贴同一位号、同一位号出现在两面、同一站位两个料号、站位表料号不在 BOM 中、BOM 用量与位号数不符、BOM 位号重复或一位号多料号、描述不一致、站位数量与位号数不符、坐标缺少或面别不符 | NG |
| 品名 / 规格含**你填写的**排除关键字、料号以**你填写的**前缀开头，且站位表没有上料 | 已排除物料 |
| BOM 该行没有位号，站位表也没有该料号（没有可比对的贴装内容） | 已排除物料 |

- **替代关系只来自有依据的内容**：BOM 中按内容识别出的替代料号列、站位表中的关联料号列，以及你在「设置 → 核对规则 → 替代料」中登记的对照表（`主料号=替代料1,替代料2`）。不会根据某一行在表中的位置推断替代料；描述相同的料号只作提示，不会自动当作替代料。
- **规则全部默认为空**：排除关键字、排除料号前缀、替代料对照表、忽略位号（如 `MARK*`）都需要人工填写并保存后才生效。旧版本自动填入且未修改过的默认值，升级后会被清空。
- 四类结果互不重叠，数量之和等于物料行总数。

## 智能核对

在「智能核对」页选择模式并导入文件：

| 模式 | 需要的文件 | 找出的差异 |
| --- | --- | --- |
| BOM 与 BOM | BOM A（基准）、BOM B（对比） | 仅在一方的料号、料号变更（同一位号换料号）、登记替代料互换、用量、位号缺少 / 多出 / 改到其他料号、描述、替代料、两份文件共有的其他列（厂商、封装等）、各自 BOM 内用量与位号数不符、位号重复或一位号多料号 |
| BOM 与站位表 | BOM、站位表 | 与「BOM 核对」相同的逐位号比对；站位表有面别列（TOP/BOT、A/B 面）时自动分面 |
| BOM 与站位表 A+B | BOM、站位表 A、站位表 B | 同上，A、B 两表合并核对 |

- **识别不依赖表头**：每个文件先按内容找出表头行（也支持无表头的表格、带封面页的工作簿），再判断每列作用；表头文字只在两列内容相近时作为参考。两份文件的料号列会按共有的料号互相校正（例如误把厂商型号当成料号时）。
- **识别结果**页列出每列的识别结果、示例值与置信度，可手动改为其他作用，修改后自动重新核对。
- **结果预览**中点击任意单元格即可编辑整行（单元格、结果、备注），修改处高亮，可逐行或全部撤销；重新核对时未变化的行会保留修改。
- **分析报告**显示概览、文件识别情况和按严重程度 / 来源筛选的问题明细（每条包含原因说明）。
- **导出 Excel** 包含：核对结果（含修改标记与原始结果）、分析报告、位号对照（BOM 与 BOM）、识别结果。

## AI 核对

AI 核对是独立功能，不参与本地核对。在「AI 核对」页添加表格文件、填写核对要求，在「连接设置」中选择 Claude（Anthropic API，默认模型 `claude-opus-5-5`）或 OpenAI 兼容接口并填写 API Key 后开始。所选文件的内容会发送到所配置的服务；API Key 只保存在本机设置文件中。AI 结果仅供参考，可复制或导出为 Markdown。

## FAI i450 坐标文件

默认输出与 FAI 程序「CAD BOM 合并导出」模板一致的 Excel 文件，每个位号一行：

| Location | X | Y | Angle | Specification | PartNo | Layer | Qty |
| --- | --- | --- | --- | --- | --- | --- | --- |
| C10 | 45.565 | 24.411 | 90 | 贴片电容 10uF 6.3V X5R 0603 | K1103-0106K0-001A | TOP | 1 |

- 同一文件既可作为 CAD 文件，也可作为 BOM 文件导入 FAI。
- 坐标单位为 mm；Specification 为 BOM 品名，PartNo 为 BOM 料号（可改为上料料号）；坐标文件无面别时按站位表 A = TOP、B = BOTTOM 补齐。
- 生成前检查位号匹配、重复位号、坐标有效性与面别一致性；存在未确认的 NG 项时会先提示。
- 点击格式旁的齿轮可调整列顺序、表头、单位、小数位、面别文字，或改为 CSV / TXT 文本格式。

## 隐私

BOM、站位表、坐标文件与报告均只在本机读取和保存。软件仅在检查更新时访问本仓库的 GitHub Releases；只有在使用「AI 核对」时，才会把所选文件发送到用户自己配置的 AI 服务。

## 开发

基于 Flutter（Dart）开发，界面全部自绘。

```bash
flutter pub get
flutter analyze
flutter test                                              # 单元测试
flutter test tool/screenshot_test.dart --update-goldens   # 用演示数据渲染界面截图到 tool/screens/
dart run tool/gen_demo.dart                               # 重新生成 samples/demo 演示数据
```

构建发布版：

```bash
flutter build linux --release      # 需 clang、cmake、ninja-build、libgtk-3-dev
flutter build windows --release    # 需 Visual Studio「使用 C++ 的桌面开发」
flutter build apk --release
```

### 持续集成与发布

GitHub Actions（[`build.yml`](.github/workflows/build.yml)）在每次推送时运行分析与测试，并构建全部平台：

| 平台 | 架构 | 产物 |
| --- | --- | --- |
| Windows | x64、arm64 | 安装程序 `setup.exe`、zip 绿色版 |
| Linux | x64、arm64 | `.deb`、`.tar.gz` |
| Android | armeabi-v7a、arm64-v8a、x86_64 | 各架构 APK、通用 APK、AAB |

- 开发提交先推送到 `dev`，全部构建通过后再同步到 `main`。
- 发布新版本：同步修改 `pubspec.yaml` 的 `version` 与 `lib/version.dart`，编写 `docs/release-notes/v<版本>.md`，构建通过后推送 `v<版本>` 标签，安装包自动发布到 Releases。
- 官网源码位于 [`site/`](site/)，推送到 `main` 后由 [`pages.yml`](.github/workflows/pages.yml) 自动部署到 GitHub Pages。

### 目录结构

```
lib/core/      文件解析、核对引擎、差异清单、导出、元件库（纯 Dart，可单测）
lib/ui/        界面：BOM 核对（含文件导入）、CAD 坐标、PCB 导航图、设置
lib/l10n/      中文 / English / ไทย 文本
samples/demo/  演示数据
site/          官网
installer/     Windows 安装程序脚本
docs/          发布说明、签名证书指纹
tool/          演示数据生成、界面截图
```

## 第三方资源

- [Inter](https://rsms.me/inter/) 字体，SIL Open Font License 1.1
- [Lucide](https://lucide.dev/) 图标图形，ISC License
- [Phosphor](https://phosphoricons.com/) 图标字体，MIT License
- [Fluent UI System Icons](https://github.com/microsoft/fluentui-system-icons)，MIT License

字体许可文本见 [`assets/fonts/`](assets/fonts/)。
