# 已完成需求

| 阶段 | 已实现结果 |
| --- | --- |
| [P0 工程与 SDK 运行底座](p0-project-foundation.md) | 工程、纯文本 WasmGC/Worker POC 与测试反馈底座；不表示 Office 格式可用 |
| [P1 字体、塑形与字形输出](p1-sdk-foundation.md) | 固定字体、glyph/cluster/BiDi、Canvas 轮廓与 PDF 候选路径验证 |
| [P2 文件与格式公共底座](p2-format-foundation.md) | 有界 ZIP/XML/OPC 与 Transitional DOCX 已知文本节点保真保存 |
| [P3 DOCX 预览与 PDF 输出](p3-docx-preview.md) | 有限分页、表格/内联图片、只读 Canvas 预览与同布局 PDF |
| [P4 DOCX 编辑与保真保存](p4-docx-editing.md) | 普通正文与单个表格单元格内纯文本编辑、历史、剪贴板、保存重开及 PDF；仅 Chromium |
| [P5 XLSX 网格、计算与编辑](p5-xlsx-editing.md) | 稀疏网格、六个函数、编辑/历史、剪贴板、保存重开和基础打印；仅 Chromium |
| [P6 PPTX 预览、编辑与保真保存](p6-pptx-editing.md) | 单对象/文本框编辑、主题继承、图文、保存重开及静态 PDF；仅 Chromium |
| [P7 PDF 输入、预览与文字查询](p7-pdf-input.md) | 有界严格读取、源坐标图文、页内选择复制、提取与搜索；仅 Chromium |
| [P8 PDF 页面操作、批注与表单保存](p8-pdf-operations.md) | 页面整理、便笺/高亮、普通字段/复选框、局部历史和对象图保存；仅 Chromium |
| [P9 Web SDK 与默认 UI](p9-web-sdk-ui.md) | 四格式现有能力的 React/Shadow DOM UI、状态、保存回调、候选替换与普通 JS 接入；仅 Chromium |
| [P10 DOCX 核心功能](p10-docx-core.md) | 六批最低范围：格式、页面/表格、图文、引用/审阅、图表/数学及保存输出 |
| [P11 XLSX 核心功能](p11-xlsx-core.md) | 五批最低范围：工作簿/结构/格式、常用计算、数据规则、分析绘图与交换打印 |
| [P12 PPTX 核心功能](p12-pptx-core.md) | 五批最低范围：页面/对象、母版/文本、复合内容、放映媒体与输出 |
| [R0 通用渲染架构与薄 Renderer](r0-renderer-foundation.md) | DOCX/XLSX/PPTX/PDF Web 接入；有序路径/矩阵/样式与核心指令、共用 Canvas 表面、独立覆盖层与资源身份；其他平台待需求 |
| [R1 领域拆包与共享 Wasm 加载](r1-domain-packages-shared-wasm.md) | 四格式独立 core/web/react/worker、领域 Bridge、唯一 Wasm、共享 Module 与独立会话 |
| [G2 测试流水线与 Agent 改进闭环](g2-test-pipeline.md) | 冻结双路径报告、真实文件、受控恢复、独立性能与本地 Docker；不声明远端 CI 或盲测 |

设计和调研不等于产品实现，活动工作见[文档索引](../README.md)。

本目录文档的收尾、编号与证据要求遵循[文档规范](../references/README.md)。
