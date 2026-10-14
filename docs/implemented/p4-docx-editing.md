# P4 DOCX 编辑与保真保存

状态：`implemented`，2026-10-14。已完成 Chrome/Chromium 中限定范围的 DOCX 编辑与保真保存。项目仍为 private/WIP，SDK 尚未发布。

## 已实现范围

开发者可以嵌入 `DocumentEditor`，打开真实 DOCX，编辑普通正文及单个表格单元格内的纯文本，保存后重新打开，并从当前布局导出 PDF。

| 用户操作 | 当前结果 |
| --- | --- |
| 选择与导航 | 点击、拖动、按字素移动、Shift 扩选，以及核心生成的光标与选区几何 |
| 文字与段落编辑 | 输入、替换、删除，跨 run 和相邻普通段落编辑；Enter 拆段，Backspace/Delete 合段 |
| 历史 | 撤销、重做及连续普通输入分组，恢复源内容和选区 |
| 输入与剪贴板 | 组合输入候选、提交、取消；纯文本复制、剪切和粘贴 |
| 保存与输出 | 保存绑定 revision 的 DOCX，重开核对正文与非目标内容；导出绑定当前布局的 PDF |
| 失败与关闭 | 拒绝不安全编辑、旧 revision/layout 及超预算操作；停止后显式恢复，关闭等待已接受工作并释放资源 |

排版范围沿用 [P3](p3-docx-preview.md)，API、位置规则和资源上限归[格式合同](../references/formats.md#p4-当前编辑-api-切片)。已实现能力与验证环境分别声明，系统输入的证据边界见下文。

## 接入与实现边界

浏览器通过 `FoundationClient.open(wasm, workerUrl)` 创建客户端。调用方供应字体并打开 DOCX，再调用 `DocumentEditor.create(root, client, profile, signal?)`。`saveDocx()` 和 `exportPdf()` 等待已接受输入，返回 `{ revision, bytes }`。调用方等待编辑器 `dispose()` 完成后，再复用或关闭客户端。实际入口和生命周期说明见[开发文档](../references/development.md#当前-foundation-api)。

MoonBit 拥有文档、选区、历史、布局和序列化。源 XML/OPC 是文档权威；编辑使用局部源补丁，保留范围外样式、未知内容和非目标部件。命令先检查 revision 和保护范围，失败不半提交。书签、字段、内容控件、图片等不能被危险范围编辑静默删除。

TypeScript 负责平台事件、Worker 通信和呈现。编辑队列保留已接受命令，保存/PDF 作为队列屏障；组合候选不创建已提交历史，最终文字只提交一次。权限失败、关闭或冲突不能让剪切丢失原文。

[R0 通用渲染架构](r0-renderer-foundation.md)已完成 DOCX/Web 首次接入。核心输出绘制指令及独立几何，Canvas Renderer 执行绘制；内容与交互覆盖层分开更新，复用当前页和平台资源。R0 的通用合同继续适用于后续格式与平台，P4 不限定其架构范围。

实现和兼容行为优先参考 ONLYOFFICE core/sdkjs，再参考 LibreOffice。保留已有参考的真实来源和用户明确选择的分页、导航、换行及纸张尺寸行为；固定源码与许可归[依赖记录](../references/dependencies.md)，具体格式规则归[格式合同](../references/formats.md)。

## 验证依据与边界

本次归档复用已有证据，不重新运行产品测试。以下记录分别绑定自己的产物与环境；历史完整运行和后续定向检查不能合称当前工作树全量通过。

| 证据入口 | 已证明的范围 | 限制 |
| --- | --- | --- |
| 私有 `cases/p4-input-transport.json`，run `1791943643486` | 完整功能运行 405/405：MoonBit 110、单元 43、集成 10、安装后 Node 23、Chromium 219 | 绑定 R0 接入前的产物；此前失败记录保留 |
| 私有 `cases/p4-native-input-current.json` | macOS 27.0.1、Chrome 154.0.8037.98 中，真实 POI DOCX 的普通 Latin 输入、撤销/重做、独立 ZIP/XML 检查及 SDK 重开 | 使用现有输入模式，未产生 composition 事件；不能作为中文组合输入证明，也未覆盖 R0 产物 |
| 私有 `cases/p4-office-gui-current.json` | 保存产物在 LibreOffice 26.8.1.1 GUI 打开，正文与两页可见，无修复提示 | 只证明绑定文件的打开结果；不证明 Word、像素一致或再次保存 |
| [R0 足够检查](r0-renderer-foundation.md#足够检查)，本地 `.temp/r0-renderer/` | 静态检查、release 构建、API 生成、4 项单元、1 项核心资源及分次完成的 17 项 Chromium 功能检查通过 | 覆盖绘制改动涉及的编辑、组合候选/取消、恢复、关闭和 Canvas/PDF；不是完整 loop |

历史 macOS/Chromium 中文组合输入结果仍绑定原产物。R0 后的组合事件检查不等同于新增系统输入法验收。沿用现有输入法；未验证所有输入法、OS 候选窗几何、其他浏览器、Windows/Word 或 VoiceOver。

详细输入、hash、输出与失败证据保留在私有记录中。检查方法和后续变更的最小检查选择归[测试说明](../references/testing.md)。

## 保留限制

- 编辑不覆盖跨单元格操作、表格结构修改、图片插入、Shift+Enter、富 HTML/RTF 粘贴、复杂修订/批注/字段更新或浮动对象。不能安全修改的范围明确拒绝。
- 当前不是完整 Word 编辑器，不包含移动端、协作或更广的格式排版。
- 文档、字形、历史、队列、页/行和 Canvas 上限继续生效。保留超时、原子拒绝、恢复与资源释放；缓存只复用依赖一致的成功结果。
- 性能专项、噪声校准和峰值内存结论延后。已有性能控制噪声失败保留原判断，R0 尚未证明性能收益。实际卡死、无法交互或资源失控时，再做解决当前阻断所需的最小诊断。

后续能力按具体用户需求进入，阶段安排见[路线图](../references/roadmap.md)。P4 归档不自动启动 P5，也不扩大兼容性承诺。
