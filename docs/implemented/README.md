# 已完成需求

| 阶段 | 已实现结果 |
| --- | --- |
| [P0 工程与 SDK 运行底座](p0-project-foundation.md) | 工程、纯文本 WasmGC/Worker POC 与测试反馈底座；不表示 Office 格式可用 |
| [P1 字体、塑形与字形输出](p1-sdk-foundation.md) | 固定字体、glyph/cluster/BiDi、Canvas 轮廓与 PDF 候选路径验证 |
| [P2 文件与格式公共底座](p2-format-foundation.md) | 有界 ZIP/XML/OPC 与 Transitional DOCX 已知文本节点保真保存 |
| [P3 DOCX 预览与 PDF 输出](p3-docx-preview.md) | 有限分页、表格/内联图片、只读 Canvas 预览与同布局 PDF |
| [P4 DOCX 编辑与保真保存](p4-docx-editing.md) | 普通正文与单个表格单元格内纯文本编辑、历史、剪贴板、保存重开及 PDF；仅 Chromium |
| [R0 通用渲染架构与薄 Renderer](r0-renderer-foundation.md) | DOCX/Web 首次接入；核心指令、独立覆盖层、当前页复用与资源身份；后续格式和平台尚未接入 |
| [G2 测试流水线与 Agent 改进闭环](g2-test-pipeline.md) | 冻结双路径报告、真实文件、受控恢复、独立性能与本地 Docker；不声明远端 CI 或盲测 |

设计和调研不等于产品实现，活动工作见[文档索引](../README.md)。

本目录文档的收尾、编号与证据要求遵循[文档规范](../references/README.md)。
