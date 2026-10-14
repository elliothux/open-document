# 产品路线图

项目未发布，当前有 0 个用户。按当前需求从 Day One 设计，可以直接修改最底层架构，只保留一条实现路径。兼容代码仅限文档格式。浏览器只覆盖 Chrome/Chromium，发布和规模化建设按真实需求安排。

[P4 DOCX 编辑](../implemented/p4-docx-editing.md)、[P5 XLSX](../implemented/p5-xlsx-editing.md)和 [R0 通用渲染架构](../implemented/r0-renderer-foundation.md)已完成声明范围。[P6 PPTX](../implemented/p6-pptx-editing.md)也已完成限定主题/版式、基础图文、单对象/文本框编辑、保真保存和静态 PDF。性能专项延后，保真、错误恢复和资源安全继续保留。

| 阶段 | 用户结果 | 状态 |
| --- | --- | --- |
| [P0 工程与运行底座](../implemented/p0-project-foundation.md) | 构建 SDK、文本会话与 Worker POC | implemented；不是 Office 功能 |
| [P1 字体与字形输出](../implemented/p1-sdk-foundation.md) | 塑形、BiDi、轮廓绘制和 PDF 路径验证 | implemented |
| [P2 文件与格式底座](../implemented/p2-format-foundation.md) | 有界 ZIP/XML/OPC、窄 DOCX 读写与保真保存 | implemented |
| [P3 DOCX 预览与 PDF](../implemented/p3-docx-preview.md) | 嵌入有限分页预览与同布局 PDF | implemented；非完整 Word 排版 |
| [P4 DOCX 编辑](../implemented/p4-docx-editing.md) | 限定正文/单个表格单元格编辑、撤销、剪贴板、保存重开 | implemented；非完整 Word 编辑器 |
| [P5 XLSX](../implemented/p5-xlsx-editing.md) | 网格、值、首批公式依赖、编辑、保存、基础打印 | implemented；限定公式与基础打印，非完整 Excel 兼容 |
| [P6 PPTX](../implemented/p6-pptx-editing.md) | 主题/版式、基础形状/文字/图片、编辑、保存/PDF | implemented；限定图文与静态 PDF，非完整 PowerPoint 兼容 |
| [P7 PDF 输入](../implemented/p7-pdf-input.md) | 有界解析、限定图文预览、页内选择、提取与搜索 | implemented；源坐标与独立文字映射，复用 R0 和固定 pdflite |
| [P8 PDF 文档操作](../implemented/p8-pdf-operations.md) | 页面重排/旋转/删除、便笺/高亮、文本字段/复选框、保存重开 | implemented；源对象图局部事务、保护规则与有界历史 |
| P9 跨宿主 | CLI 和一个明确的非浏览器宿主 | planned；后续按实际需求实施 |

P5–P8 的交付与限制归所属结果。P7/P8 已完成限定范围与定向检查；P9 进入开发时再确定宿主与操作。当前不做全公式库、动画播放、OCR、任意 PDF 正文编辑、数字签名、全语言绑定或发布流水线。

已有 Office → PDF writer 不依赖 P7 reader。P7 复用通用绘制，按 PDF 原坐标显示；P8 在原对象图上修改和保存，不通过页面重绘替代文档写回。共用同一核心/宿主合同，不按格式新建 Renderer。

## 研究与实施

当前工作按所属产品阶段推进。新增依赖或机制先确认当前功能的具体缺口。核心/宿主职责归 [SDK 合同](sdk.md)，实际 API 与支持范围归[格式合同](formats.md)。

每次迭代选一个用户操作，写明输入、期望输出和当前范围，完成实现与直接覆盖风险的检查后交付。文件读写、交互、视觉分别声明范围。执行细节见[测试说明](testing.md)。
