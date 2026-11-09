# DeepSeek 截断修复验证

目标版本：3.2.1（4021）。

## 已确认的代码问题

- DeepSeek 连接测试只请求 50 个输出 token，列识别也只有 `200 + 40 × 列数`。请求没有控制思考模式。当前官方接口默认开启思考模式，输出上限包含思考与回答；这些预算可能在生成 JSON 前耗尽。
- 旧代码遇到 `finish_reason=length` / `stop_reason=max_tokens` 直接报错，没有提高预算或拆批恢复。独立 AI 分析一次发送整个报告，行数增加后输出仍固定为 8192 token。
- DeepSeek 官方默认模型仍是旧名称 `deepseek-chat`；当前官方文档列出的模型为 `deepseek-flash` 和 `deepseek-v4-pro`。

适配依据：[Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)、[思考模式](https://api-docs.deepseek.com/guides/thinking_mode/)、[JSON 输出](https://api-docs.deepseek.com/guides/json_mode/)、[模型说明](https://api-docs.deepseek.com/quick_start/pricing/)。以上是从代码和协议确认的问题；没有使用用户账号在线复现，因此不能断言这是该账号故障的唯一原因。

## 修复

- DeepSeek 结构化请求使用非思考模式与 JSON 输出，预算至少 4096 token；官方旧模型别名映射到 `deepseek-flash`，自定义网关模型名保留。
- 在配置的重试次数内，遇到截断提高预算（通常最多 16384 token）；仍失败则按行 / 列二分拆批。云端及混合核对默认每批 8 项，AI 分析每批最多 12 行并按约 32 KB 输入预算拆批。
- 不接受截断回答中的任何 JSON。成功子批次保留，失败单项保留缺失 / 未完成标记；AI 分析有任何不可恢复的单项时整体报错，不返回部分分析冒充成功。取消会停止后续批次。
- 失败重试及拆批的实际用量汇总到调用记录。AI 分析继续应用隐私选项、使用稳定别名，并丢弃不属于本批物料的发现。

## 验证

完整测试 138 项通过、7 项因缺少其他模型或客户样本跳过。新增 10 项覆盖 DeepSeek 连接、官方别名迁移、提高输出预算、空白 JSON 重试、到达预算上限仍拒绝截断结果、列识别拆批、云端完整行覆盖、失败单项与成功兄弟批次、混合核对、AI 分析别名与取消。

`flutter analyze --no-pub lib test tool` 通过，没有发现问题。

使用可控 HTTP 服务器模拟 OpenAI 兼容与 Anthropic 协议；不是 DeepSeek 账号在线效果验证。没有读取或导出用户 API Key。真实本地模型回归仍使用 Granite-Embedding-107M GGUF；模型选择与方向栏的界面验证见 [记录](2026-11-09-model-controls.md)。

复现命令在 **WSL Ubuntu** 的项目目录执行：

```bash
flutter test --concurrency=1 test/cloud_recovery_test.dart \
  test/provider_test.dart test/cloud_full_test.dart \
  test/hybrid_test.dart test/ai_privacy_test.dart
flutter analyze lib test tool
```
