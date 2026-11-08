# 阶段 10：Windows 安装包集成与性能优化

日期：2026-11-08。

## 交付

| 内容 | 位置 |
| --- | --- |
| 完整离线安装包：CI 下载向量模型、校验 SHA-256 后打入 `SMT-FAI-<版本>-windows-<架构>-full-setup.exe`，模型放在程序目录 `models` 下，软件直接使用（无需下载、无需配置运行环境）；普通安装包不变 | `installer/windows/smt-fai.iss`，`.github/workflows/build.yml` |
| 应用内更新只会选普通安装包，不会下载带模型的完整包 | `core_test.dart`（更新测试） |
| 语言模型（Qwen3-4B）改为可选：默认核对不使用（阶段 3 实测读列不如程序），不计入必需下载，也不打入离线包；需要时仍可在设置中下载 | `model_store.dart`、`local_ai.dart`、`settings_page.dart` |
| 位号分组改用并查集：5000 行改料号 BOM 从 2.6 秒降到 0.46 秒 | `bom_compare.dart` |
| 向量匹配：分批嵌入（每批 128 条，带进度、可取消），相似度计算放到后台 isolate，只比较类别兼容的物料，不阻塞界面 | `semantic_match.dart`，`app_state.dart` |
| 性能基准工具 | `tool/bench_perf.dart` |

## 性能（本机 CPU，读表 + 核对，不含模型）

```
500 lines: read 94 ms; same numbers 117 ms (500 pass); renumbered by designators 77 ms (500 review); no designators 36 ms (756 unmatched)
2000 lines: read 162 ms; same numbers 195 ms (2000 pass); renumbered by designators 179 ms (2000 review); no designators 98 ms (4000 unmatched)
5000 lines: read 295 ms; same numbers 448 ms (5000 pass); renumbered by designators 455 ms (5000 review); no designators 458 ms (10000 unmatched)
```

- 5000 行 BOM 读入约 0.3 秒，核对约 0.45 秒。
- 本地向量模型：200 条描述约 2.6 秒（阶段 3 实测），10000 条约 2 分钟，期间界面可操作、可取消。
- 安装包大小（阶段 3 裁剪后）：Windows x64 约 45 MB；完整离线包另加约 610 MB 模型。

## 待确认

- 完整离线安装包的实际构建在下一次 CI 运行中验证（模型从 Hugging Face 下载，GitHub 单文件 2 GB 限制以内）。
