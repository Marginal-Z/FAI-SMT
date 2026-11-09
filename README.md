<div align="center">

<img src="site/assets/icon.png" width="96" alt="SMT-FAI">

# SMT-FAI

**智能 BOM 核对：按内容理解未知 BOM、自动配对物料、严格校验参数；本地 / 混合 / 云端三种模式，无法确认的绝不判 PASS**

[![最新版本](https://img.shields.io/github/v/release/Marginal-Z/FAI-SMT?label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC)](https://github.com/Marginal-Z/FAI-SMT/releases/latest)
[![构建](https://img.shields.io/github/actions/workflow/status/Marginal-Z/FAI-SMT/build.yml?branch=main&label=%E6%9E%84%E5%BB%BA)](https://github.com/Marginal-Z/FAI-SMT/actions/workflows/build.yml)
![平台](https://img.shields.io/badge/%E5%B9%B3%E5%8F%B0-Windows%20%7C%20Android%20%7C%20Linux-0071e3)

[官网](https://marginal-z.github.io/FAI-SMT/) · [使用教程](https://marginal-z.github.io/FAI-SMT/#tutorial) · [下载](https://github.com/Marginal-Z/FAI-SMT/releases/latest) · [更新记录](https://github.com/Marginal-Z/FAI-SMT/releases)

<img src="site/assets/check.webp" width="900" alt="BOM 核对界面">

</div>

## 简介

SMT-FAI 用于 SMT 产线的 BOM 核对。导入作为基准的 A-BOM，再导入 B-BOM（以及可选的 C-BOM）：B 与 C 合并后（同一料号用量相加、位号合并），与 A-BOM 逐个料号比较物料描述、用量、位号和其他列，不一致的单元格填色、差异字符高亮。开启 AI 核对后，核对结果会交给你配置的大模型（OpenAI 兼容接口或 Anthropic）输出分析结果，并在表格中标记 AI 发现的问题。

三种核对模式：

| 模式 | 说明 |
| --- | --- |
| **本地** | 完全离线、不需要 API Key：程序识别字段、配对物料、按数值校验参数；可选的本地向量模型（默认 Granite-Embedding-278M，约 210 MB；另有更轻的 107M、EmbeddingGemma-300M 和 Qwen3-Embedding-0.6B 可选，随离线安装包提供或在软件内下载）为换了料号且没有位号的物料寻找对应项；配置低的电脑不开模型也能完整核对 |
| **混合** | 先本地核对，再把无法确定的物料交给你选择的云端 AI；云端结论经程序交叉校验，不能推翻已确认的冲突 |
| **云端** | 由云端 AI 识别字段并配对物料；程序校验记录覆盖、引用和每项数值，失败或不完整时不显示完成 |

本地核对不上传 BOM；自动检查更新和手动下载模型仍会联网。选择混合 / 云端模式或开启 AI 分析时，会把允许发送的核对数据发送到设置中的接口（可关闭料号、位号列表和其他列的结构化发送；描述自由文本需自行确认）；API Key 保存在系统安全存储中。

## 主要功能

| 功能 | 说明 |
| --- | --- |
| **三份文件** | A-BOM（基准）、B-BOM、C-BOM（可选）；拖到卡片上或点击选择 |
| **按内容识别列** | 不依赖表头名称：位号列看位号写法，用量列看是否与位号数一致，料号列看唯一编码，描述列看较长文字；表头名称不同或没有表头也能读取；品名 + 规格等多列描述自动拼接 |
| **描述参数与关键特征** | 阻值、容值、电压、精度、封装、型号等按数值或编码核对；通用名称允许不同写法，已知颜色、极性及电容类型等区别不能忽略，信息不足进入复核 |
| **其他列精确比较** | 用量、位号以及两边都有的其他列（品牌、类别、厂商料号等）必须百分之百一致；名称不同或无表头的列按内容自动配对 |
| **智能匹配** | 按料号、位号（支持拆分 / 合并）、厂商料号、替代料号、类别 + 参数以及本地语义模型配对，每条结果带匹配依据、置信度和原因 |
| **五种结果** | PASS、NG、需复核、未匹配、认可替代料；无法确认的一律「需复核」，不猜测；差异单元格填色、差异字符加粗高亮 |
| **云端 AI** | DeepSeek、OpenAI、Anthropic 与任意 OpenAI 兼容接口；结构化输出校验、超时重试、限流、取消、Token 与费用统计、请求日志；AI 分析输出总结与逐条发现，AI 标记的料号用青色标识 |
| **本地模型** | 本地模式必须由 Qwen3-4B 逐项分析全部物料后才生成结果；设置中下载（约 2.5 GB、断点续传、多镜像、SHA-256 校验）与自检；向量模型只辅助混合模式候选 |
| **Excel 报告** | 两边的值并排列出，结果按状态填色，差异单元格填黄色；每行带来源行号、匹配依据、原因、风险和标准化参数；「汇总」工作表；未完成的核对在表头醒目提示 |
| **使用体验** | 中文 / English / ไทย；现代 / 工业两种扁平界面风格；浅色 / 深色 / 跟随系统；新手引导；手机、平板竖屏与横屏各有专属布局；应用内自动更新 |

## 下载与安装

### 3.3.0 更新

本地核对必须完成本地语言模型对全部物料的逐项分析，包含原本一致的行；缺少模型、加载失败、超时、漏答或取消均不生成结果、报告或新历史记录。核对页显示校验/加载、已分析项数、分析请求数和耗时；行详情与 Excel 保存本地 AI 说明。程序保留数量、位号、覆盖完整性等硬约束，防止模型把已知冲突判成通过。

请在「管理 / 下载模型」先下载并自检 **Qwen3-4B Q4_K_M（约 2.5 GB）**。本地模式下分析必需开启；旧的关闭设置不能绕过。四种向量模型仍可用于混合模式，单独运行向量不能完成本地核对。现有 `full-setup.exe` 只含向量模型，语言模型仍需另行下载；下载完成后本地核对不上传 BOM。首次加载可能较慢，实际速度取决于设备。

上传卡片压缩为两行；结果页新增独立方向提醒区块，汇总需核对极性、Pin 1 和机械方向的元件与位号，可展开明细、定位物料、筛选结果。提醒要求人工对照规格书、PCB 丝印和实物确认方向。详见 [3.3.0 更新说明](docs/release-notes/v3.3.0.md)。以下旧版本段落仅描述当时行为。

### 3.2.1 更新

核对页的独立模型栏可直接开关本地模型、选择匹配模型，并显示每个模型的下载状态；「管理 / 下载模型」可进入模型设置。开关与选择保存在本机，下次核对生效，本次结果保留原来的模型调用记录。正在推理时会锁定切换。

结果表格新增独立「方向核对提醒」列，直接显示极性、Pin 1、缺口 / 卡扣等检查项及对应位号；窄屏显示在物料卡片的独立提醒区，点击物料仍可查看完整依据。未触发提醒的表格单元格显示 `—`，不表示已经确认实物方向。

修复 DeepSeek 云端核对被截断：结构化核对显式关闭思考模式、提高输出预算；截断时先增加预算重试，仍未完成的批次自动拆小。列识别、云端核对、混合核对及独立 AI 分析均保留完整性校验，单行仍失败时明确保留未完成状态。官方 DeepSeek 接口的旧模型别名迁移到 `deepseek-flash`，自定义网关的模型名称保留。详见 [3.2.1 更新说明](docs/release-notes/v3.2.1.md)。

### 3.2.0 更新

核对页现在明确显示本次本地模型是否实际调用：关闭、未就绪、无需调用、运行中、成功或失败，成功时列出处理描述数、候选数及耗时。设置 → 本地模型 →「运行推理自检」会真实请求向量；自检成功与本次 BOM 是否使用模型分别记录。当前核对仅使用向量模型给双侧未匹配项推荐候选，可选语言模型尚未接入核对流程。

结果的原因筛选增加「方向核对提醒」，行详情与 Excel 列出需核对极性、Pin 1 或机械方向的元件、位号及依据。BOM 一致仍需人工对照规格书、PCB 丝印和实物确认方向。

规则加强了重复料号内部冲突、重复位号、缺失/无效用量、缺列、Not fitted 表头、层级保留和中文区分特征的检查。完整缺陷、修复证据与未覆盖事项见 [BOM 审查报告](docs/reviews/2026-11-09-bom-review.md)、[验证记录](docs/reviews/2026-11-09-validation.md) 和 [3.2.0 更新说明](docs/release-notes/v3.2.0.md)。安装包见 Releases。

前往 [Releases](https://github.com/Marginal-Z/FAI-SMT/releases/latest) 或 [官网下载页](https://marginal-z.github.io/FAI-SMT/#download) 获取最新版本。

| 平台 | 系统要求 | 安装包 |
| --- | --- | --- |
| Windows | Windows 10 / 11，x64 或 ARM64 | `SMT-FAI-<版本>-windows-x64-setup.exe`（推荐）、`-arm64-setup.exe`；自带向量模型包 `-full-setup.exe`（约 650 MB，不含必需语言模型）；或 zip 绿色版 |
| Android | Android 7.0 及以上 | `SMT-FAI-<版本>-android-universal.apk`；或对应架构的 APK |
| Linux | Debian / Ubuntu 及衍生版，x64 或 ARM64 | `SMT-FAI-<版本>-linux-x64.deb`、`-arm64.deb`；或 tar.gz |

- **Windows**：安装程序按当前用户安装，无需管理员权限。安装程序暂未进行商业代码签名，如出现 SmartScreen 提示，点击「更多信息 → 仍要运行」。
- **Android**：首次安装需允许「安装未知来源应用」。
- **Linux**：`sudo apt install ./SMT-FAI-<版本>-linux-x64.deb`。

### 升级

新版本直接安装即可覆盖升级，设置会保留。软件启动时会自动检查更新，Windows 与 Android 可在应用内下载并安装。

> Android 1.3.0 及更早版本使用临时签名，升级到 1.4.0 及以后版本前需先卸载一次旧版。此后所有版本均使用同一正式签名，证书 SHA-256 指纹见 [`docs/signing/android-cert-sha256.txt`](docs/signing/android-cert-sha256.txt)。

## 快速上手

1. **导入文件**：把 A-BOM、B-BOM 拖到对应卡片（有 C-BOM 再导入 C-BOM），确认显示已读取项数；悬停查看列识别结果与提示。
2. **开始核对**：本地模式先下载并自检 Qwen3-4B，再点击「开始核对」（`F5`），等待全部物料分析完成。点击统计卡片筛选，点击一行查看逐列对比和本地 AI 说明。
3. **云端核对（可选）**：如需云端，切换为混合或云端模式，在设置中配置接口；这些模式可使用额外的「AI 核对」总结开关。本地模式只运行本地分析。
4. **导出报告**：点击「导出 Excel」（`Ctrl+E`）保存核对报告。
5. **核对记录**：每次核对完成后自动保存（原始文件副本、SHA-256、结果与当时的报告），点击右上角时钟图标按文件名、料号或描述查询，可重新载入核对或导出当时的报告。
6. **核对与输出**：在「设置 → 核对与输出」选择参与核对的字段（如只核对位号和用量）、报告包含的列以及报告列出的结果（如只输出 NG）。

完整图文教程见 [官网使用教程](https://marginal-z.github.io/FAI-SMT/#tutorial)；软件内「设置 → 使用说明」可随时查看，点击右上角问号可重新开始新手引导。

### 快捷键

| 按键 | 功能 |
| --- | --- |
| `F5` | 开始核对 |
| `Ctrl+E` | 导出 Excel 报告 |
| `Esc` | 关闭设置 |

## 输入文件

支持 `.xlsx`、`.csv`、`.txt`；文本文件自动识别 UTF-8 / UTF-16 / GBK 编码与分隔符。旧版 `.xls` 请先在 Excel 中另存为 `.xlsx`。多个工作表时自动选择最像 BOM 的一个；表头前可以有标题行，也可以完全没有表头。

- 位号支持 `,，;；、` 与空格分隔，以及 `R1-R5`、`R1~5` 范围写法；单元格内换行和只有位号的续行会归到上一个料号。
- 同一文件中重复出现的料号会合并；用量与位号数不符、位号重复会在导入卡片上提示。

## 核对规则

有 C-BOM 时先与 B-BOM 合并（同一料号用量相加、位号合并），再与 A-BOM 比较。

**配对草稿**（依次）：相同料号 → 共有位号（一行拆成两行或两行合成一行也能配上）→ 相同厂商料号 → 登记的替代料号 → 类别与参数完全相同且唯一。混合模式还可使用向量候选（只会得到「需复核」）。本地模式的草稿不会直接显示，全部行必须经过语言模型分析后才生成最终结果。

**比较**：

| 项目 | 规则 |
| --- | --- |
| 物料描述 | 参数按数值比较（10K = 10kΩ = 10000Ω，0.1uF = 100nF，C0G = NPO），标注「数值等价」；型号等含数字的内容必须一致；表示物料类别的通用词与中文写法可以不同；颜色、NPN/PNP 等区分性的词必须一致 |
| 用量、位号 | 完全相同；列出缺少、多出以及在另一边挂在其他料号下的位号 |
| 其他列 | 两边都有的列逐字比较；只有一边有的列不比较并在筛选栏旁列出 |
| 贴装标记、BOM 层级 | 按含义比较（「YES」与空白都可能表示贴装）；只有一边有贴装列时不判 NG，而是需复核 |

**结果**：

| 结果 | 含义 |
| --- | --- |
| PASS | 配对可靠（料号 / 位号 / 厂商料号 / 替代料）且各项一致 |
| NG | 配对可靠且有冲突 |
| 需复核 | 只靠参数或语义配对；料号不同且未登记替代；一方缺少参数；描述可能只是另一种语言的写法；贴装标记无法确认 |
| 未匹配 | 另一份 BOM 中没有对应物料 |
| 认可替代料 | 料号不同，但其中一份 BOM 明确登记为替代料，其余各项一致 |

## AI 核对

| 接口类型 | 接口地址 | 说明 |
| --- | --- | --- |
| OpenAI 兼容 | 留空为 `https://api.openai.com/v1`；其他服务填写其 `/v1` 地址 | 调用 `POST {地址}/chat/completions` |
| Anthropic | 留空为 `https://api.anthropic.com` | 调用 `POST {地址}/v1/messages` |

模型留空时使用默认模型。在设置页点「测试连接」可确认地址、Key 与模型可用。AI 收到的是本地核对结果（BOM 较大时只发送有差异的料号全文与一致料号的料号），返回总结和逐条发现，发现会显示在表格旁并写入 Excel 报告。

## 隐私

BOM 与报告在本机读取和保存。软件在检查更新时访问本仓库的 GitHub Releases；混合/云端核对或 AI 分析会把允许发送的核对数据发送到配置的接口。AI 分析同样应用料号、位号和其他列的隐私选项；API Key 保存在系统安全存储中。

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
lib/core/      表格读取、BOM 列识别、核对引擎、AI 接口、Excel 报告（纯 Dart，可单测）
lib/ui/        界面：BOM 核对（含文件导入与 AI 分析）、设置
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
