# 文档索引

| 内容 | 权威入口 |
| --- | --- |
| 当前目标、选型与核心/宿主合同 | [SDK 合同](references/sdk.md) |
| 当前字体/DOCX 支持面与预算 | [格式合同](references/formats.md) |
| 固定依赖、许可与本地缺口 | [依赖记录](references/dependencies.md) |
| 底座研究、备选比较与验证缺口 | [G0 底座参考项目研究](g0-foundation-review.md) |
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
| P4 | [DOCX 编辑与保真保存](p4-docx-editing.md) | `planned`：P4.1–P4.4 明确位置/事务、范围编辑、输入宿主、保真与性能验收；尚未实现 |

## 研究依据

| 编号 | 文档 | 当前状态 |
| --- | --- | --- |
| G0 | [底座参考项目研究](g0-foundation-review.md) | `research`：部分职责边界已纳入路线图；候选库集成与性能仍待验证 |
| G1 | [兼容性测试与反馈研究](g1-compatibility-pipeline.md) | `research`：上游项目、数据集与判定方法的调研依据 |
| G2 | [测试流水线与 Agent 改进闭环](implemented/g2-test-pipeline.md) | `implemented`：授权的本地 A–F、双路径报告、受控恢复、性能及 Docker 验收；不包含远端启用或盲测 |

先读[路线图](references/roadmap.md)中的 G0 → 阶段映射，再按 P0 → P1 → P2 → P3 → P4 进入产品与验收合同；P5–P9 的待细化范围在路线图中。全部文档统一在这里；测试实现、数据与原始证据仍在私有 `test-lab/`。P0–P9 阶段编号已分配，新增阶段不得复用。

索引只维护入口与状态；产品合同归所属方案，文档规则归维护规范。历史测试结果不代表当前工作树已经验收。

返回[项目介绍](../README.md)。
