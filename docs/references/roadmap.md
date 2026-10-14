# 产品路线图

项目未发布，当前有 0 个用户。按当前需求从 Day One 设计，可以直接修改最底层架构，只保留一条实现路径。兼容代码仅限文档格式。浏览器只覆盖 Chrome/Chromium，发布和规模化建设按真实需求安排。

[P4 DOCX 编辑](../implemented/p4-docx-editing.md)和 [R0 通用渲染架构](../implemented/r0-renderer-foundation.md)已完成声明范围。[P5 XLSX](../implemented/p5-xlsx-editing.md)已完成限定网格、编辑、六个函数、保存重开与基础打印。后续阶段按实际需求进入。性能专项延后，保真、错误恢复和资源安全继续保留。

| 阶段 | 用户结果 | 状态 |
| --- | --- | --- |
| [P0 工程与运行底座](../implemented/p0-project-foundation.md) | 构建 SDK、文本会话与 Worker POC | implemented；不是 Office 功能 |
| [P1 字体与字形输出](../implemented/p1-sdk-foundation.md) | 塑形、BiDi、轮廓绘制和 PDF 路径验证 | implemented |
| [P2 文件与格式底座](../implemented/p2-format-foundation.md) | 有界 ZIP/XML/OPC、窄 DOCX 读写与保真保存 | implemented |
| [P3 DOCX 预览与 PDF](../implemented/p3-docx-preview.md) | 嵌入有限分页预览与同布局 PDF | implemented；非完整 Word 排版 |
| [P4 DOCX 编辑](../implemented/p4-docx-editing.md) | 限定正文/单个表格单元格编辑、撤销、剪贴板、保存重开 | implemented；非完整 Word 编辑器 |
| [P5 XLSX](../implemented/p5-xlsx-editing.md) | 网格、值、首批公式依赖、编辑、保存、基础打印 | implemented；限定公式与基础打印，非完整 Excel 兼容 |
| P6 PPTX | 主题/版式、基础形状/文字/图片、编辑、保存/PDF | planned；复用 P2 与已有布局/绘图能力 |
| P7 PDF 输入 | 解析、预览、提取与搜索 | planned；不要求先完成 Office 编辑 |
| P8 PDF 文档操作 | 页面操作、选定批注与表单、保存 | planned；依赖 P7 |
| P9 跨宿主 | CLI 和一个明确的非浏览器宿主 | planned；后续按实际需求实施 |

P5 的交付、限制与足够检查归所属结果。P6–P9 进入开发时再确定最小范围与对应检查。当前不做全公式库、动画播放、OCR、任意 PDF 正文编辑、数字签名、全语言绑定或发布流水线。P3 PDF writer 不依赖尚未实现的 P7 reader。

## 研究与实施

当前工作按所属产品阶段推进。新增依赖或机制先确认当前功能的具体缺口。核心/宿主职责归 [SDK 合同](sdk.md)，实际 API 与支持范围归[格式合同](formats.md)。

每次迭代选一个用户操作，写明输入、期望输出和当前范围，完成实现与直接覆盖风险的检查后交付。文件读写、交互、视觉分别声明范围。执行细节见[测试说明](testing.md)。
