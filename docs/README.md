# 文档索引

项目未发布，当前有 0 个用户。目标是复刻 GenOffice 的文档、表格、PPT、PDF 全功能 SDK。GenOffice 提供功能与 UI 参考；Office 实现、布局和算法仍优先参考 ONLYOFFICE，其次 LibreOffice。

阶段 P0–P8 已完成各自有限范围，四类格式共用 [R0](implemented/r0-renderer-foundation.md)。后续按“功能优先级 P0 核心功能、P1 兼容与性能、P2 次要与外围能力”推进；与历史阶段编号分开。只覆盖 Chrome/Chromium，文档完整性、恢复、资源安全和无障碍随功能保留。按风险选择[最小检查](references/testing.md)。

| 内容 | 权威入口 |
| --- | --- |
| 当前目标、选型与核心/宿主合同 | [SDK 合同](references/sdk.md) |
| 当前字体、DOCX/XLSX/PPTX/PDF 支持面与预算 | [格式合同](references/formats.md) |
| 固定依赖、许可与本地缺口 | [依赖记录](references/dependencies.md) |
| 产品阶段与依赖关系 | [Roadmap](references/roadmap.md) |
| GenOffice 四类功能、当前缺口与优先级 | [G3 功能对照](g3-genoffice-sdk-gap.md) |
| 实际模块、工具链与开发命令 | [开发说明](references/development.md) |
| 文档组织、编号与维护资料 | [文档与参考规范](references/README.md) |
| 上游源码阅读入口 | [上游参考项目](references/upstream-projects.md) |
| 测试执行、反馈与证据规则 | [测试说明](references/testing.md) |
| 数据集准备状态与来源管理 | [语料管理](references/corpus.md) |
| 已实现需求的结果 | [完成索引](implemented/README.md) |
| 外部条件阻塞的事项 | [阻塞索引](blocked/README.md) |

## 已完成产品阶段

| 编号 | 文档 | 当前状态 |
| --- | --- | --- |
| P0 | [工程与 SDK 运行底座](implemented/p0-project-foundation.md) | `implemented`：工程、纯文本 WasmGC/Worker POC 与测试反馈，不是 Office 功能 |
| P1 | [字体、塑形与字形输出](implemented/p1-sdk-foundation.md) | `implemented`：独立参考、真实 Worker/Canvas 与 PDF 候选探针 |
| P2 | [文件与格式公共底座](implemented/p2-format-foundation.md) | `implemented`：有界 ZIP/XML/OPC、窄 DOCX 查询/替换/保真保存 |
| P3 | [DOCX 预览与 PDF 输出](implemented/p3-docx-preview.md) | `implemented`：有限段落/页面/表格/内联图片、只读 Canvas 与同布局 PDF |
| P4 | [DOCX 编辑与保真保存](implemented/p4-docx-editing.md) | `implemented`：普通正文与单个表格单元格内纯文本编辑、历史、剪贴板、保存重开及 PDF；仅 Chromium |
| P5 | [XLSX 网格、计算与编辑](implemented/p5-xlsx-editing.md) | `implemented`：稀疏网格、六个函数、编辑/历史、剪贴板、保存与基础打印 |
| P6 | [PPTX 预览、编辑与保真保存](implemented/p6-pptx-editing.md) | `implemented`：限定主题/版式、基础图文、单对象/文本框编辑、保存重开与静态 PDF |
| P7 | [PDF 输入、预览与文字查询](implemented/p7-pdf-input.md) | `implemented`：有界读取、限定图文预览、页内选择、提取与搜索 |
| P8 | [PDF 页面操作、批注与表单保存](implemented/p8-pdf-operations.md) | `implemented`：页面整理、便笺/高亮、文本字段/复选框与保留源对象的保存 |

后续阶段均为 `planned`：P9 Web SDK/UI，P10–P13 四类核心功能，P14 兼容与性能，P15 次要与外围能力，P16 跨宿主。跨宿主按功能优先级 P2 最后实施。具体顺序和范围只在[路线图](references/roadmap.md#后续阶段与顺序)维护。

## 待实现方案

| 编号 | 文档 | 当前状态 |
| --- | --- | --- |
| P9 | [Web SDK 与默认 UI](p9-web-sdk-ui.md) | `planned`：独立 UI 包、四格式现有操作、状态通知、保存/关闭、Shadow DOM 与普通 JS 接入 |

## 活动研究

| 编号 | 文档 | 当前状态 |
| --- | --- | --- |
| G3 | [GenOffice 功能对照与全功能 SDK 差距](g3-genoffice-sdk-gap.md) | `research`：本地源码对照，分别记录功能证据、当前缺口和 P0/P1/P2 优先级；不是运行验收 |

## 通用架构

| 编号 | 文档 | 当前状态 |
| --- | --- | --- |
| R0 | [通用渲染架构与薄 Renderer](implemented/r0-renderer-foundation.md) | `implemented`：DOCX/XLSX/PPTX/PDF Web 接入；有序图元、路径/矩阵/样式、共用 Canvas 表面与独立覆盖层 |

## 测试基础设施

| 编号 | 文档 | 当前状态 |
| --- | --- | --- |
| G2 | [测试流水线与 Agent 改进闭环](implemented/g2-test-pipeline.md) | `implemented`：授权的本地 A–F、双路径报告、受控恢复、性能及 Docker 验收；不包含远端启用或盲测 |

[P7](implemented/p7-pdf-input.md) 与 [P8](implemented/p8-pdf-operations.md) 已完成限定 PDF 输入和操作；P16 跨宿主仍按[路线图](references/roadmap.md)延后。测试实现、数据与详细证据在私有 `test-lab/`。

索引只维护入口与状态；产品合同归所属方案，文档规则归维护规范。历史测试结果不代表当前工作树已经验收。

返回[项目介绍](../README.md)。
