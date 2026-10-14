# 文档索引

项目未发布，当前有 0 个用户。[P4](implemented/p4-docx-editing.md) 已完成限定 DOCX 编辑，[R0](implemented/r0-renderer-foundation.md) 已完成通用渲染架构的 DOCX/Web 接入。[P5](implemented/p5-xlsx-editing.md) 已完成限定 XLSX 网格、计算、编辑和打印。只覆盖 Chrome/Chromium；性能专项延后，保留文档保真、错误恢复和资源安全。后续变更按风险选择[最小检查](references/testing.md)。

| 内容 | 权威入口 |
| --- | --- |
| 当前目标、选型与核心/宿主合同 | [SDK 合同](references/sdk.md) |
| 当前字体、DOCX/XLSX 支持面与预算 | [格式合同](references/formats.md) |
| 固定依赖、许可与本地缺口 | [依赖记录](references/dependencies.md) |
| 产品阶段与依赖关系 | [Roadmap](references/roadmap.md) |
| 实际模块、工具链与开发命令 | [开发说明](references/development.md) |
| 文档组织、编号与维护资料 | [文档与参考规范](references/README.md) |
| 上游源码阅读入口 | [上游参考项目](references/upstream-projects.md) |
| 测试执行、反馈与证据规则 | [测试说明](references/testing.md) |
| 数据集准备状态与来源管理 | [语料管理](references/corpus.md) |
| 已实现需求的结果 | [完成索引](implemented/README.md) |
| 外部条件阻塞的事项 | [阻塞索引](blocked/README.md) |

## 产品阶段（按实施顺序）

| 编号 | 文档 | 当前状态 |
| --- | --- | --- |
| P0 | [工程与 SDK 运行底座](implemented/p0-project-foundation.md) | `implemented`：工程、纯文本 WasmGC/Worker POC 与测试反馈，不是 Office 功能 |
| P1 | [字体、塑形与字形输出](implemented/p1-sdk-foundation.md) | `implemented`：独立参考、真实 Worker/Canvas 与 PDF 候选探针 |
| P2 | [文件与格式公共底座](implemented/p2-format-foundation.md) | `implemented`：有界 ZIP/XML/OPC、窄 DOCX 查询/替换/保真保存 |
| P3 | [DOCX 预览与 PDF 输出](implemented/p3-docx-preview.md) | `implemented`：有限段落/页面/表格/内联图片、只读 Canvas 与同布局 PDF |
| P4 | [DOCX 编辑与保真保存](implemented/p4-docx-editing.md) | `implemented`：普通正文与单个表格单元格内纯文本编辑、历史、剪贴板、保存重开及 PDF；仅 Chromium |
| P5 | [XLSX 网格、计算与编辑](implemented/p5-xlsx-editing.md) | `implemented`：稀疏网格、六个函数、编辑/历史、剪贴板、保存与基础打印 |

## 通用架构

| 编号 | 文档 | 当前状态 |
| --- | --- | --- |
| R0 | [通用渲染架构与薄 Renderer](implemented/r0-renderer-foundation.md) | `implemented`：DOCX/XLSX Web 接入；核心指令、共用 Canvas 表面与独立覆盖层；其他格式和平台待需求 |

## 测试基础设施

| 编号 | 文档 | 当前状态 |
| --- | --- | --- |
| G2 | [测试流水线与 Agent 改进闭环](implemented/g2-test-pipeline.md) | `implemented`：授权的本地 A–F、双路径报告、受控恢复、性能及 Docker 验收；不包含远端启用或盲测 |

后续开发从具体用户操作和实际缺口进入，复用已完成基础，完成对应实现、必要检查和操作说明。P5 的交付与限制归所属结果，P6–P9 见[路线图](references/roadmap.md)。测试实现、数据与详细证据在私有 `test-lab/`。

索引只维护入口与状态；产品合同归所属方案，文档规则归维护规范。历史测试结果不代表当前工作树已经验收。

返回[项目介绍](../README.md)。
