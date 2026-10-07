# 上游参考项目

本文件维护原有 Office 项目的参考范围、源码位置与阅读入口；新增 19 个仓库的研究结论与固定快照见 [G0 底座研究](../g0-foundation-review.md)。这些是研究来源，不是构建依赖或已通过资格验证的依赖清单。

参考关系不是整体 fork，也不是逐行翻译。优先参考功能语义、数据结构、格式兼容规则、测试样本和真实行为，再按照本项目边界实现。

## BetterOffice：架构与核心/宿主边界

- [上游仓库](https://github.com/openooxml/betteroffice)
- [本地研究副本](../../../lynx-os/references/betteroffice/)，本地 HEAD：`c10db4b848c1e74c920416986ec2e34bf95ee7f3`。
- 重点参考：OOXML 基础模块、文档会话、WASM 边界、布局与绘制分离、Worker 接入和无 DOM 计算入口。
- 不照搬其 Rust 技术栈，不把现有功能和兼容性覆盖当作最终目标。
- 其字体基础依赖 `skrifa`、`rustybuzz`、`unicode-linebreak`、`unicode-bidi`；换用 MoonBit 后需要验证对应能力，不能假设换语言后自动继承。

阅读入口：

- [字体与文本依赖](../../../lynx-os/references/betteroffice/crates/ooxml-text/Cargo.toml)
- [DOCX Canvas 后端](../../../lynx-os/references/betteroffice/packages/docx/src/layout/render/canvasBackend.ts)
- [DOCX Worker 接入](../../../lynx-os/references/betteroffice/packages/docx/src/yrs/residentEngineWorkerClient.ts)
- [DOCX 输入适配](../../../lynx-os/references/betteroffice/packages/docx-react/src/components/DocxEditor/YrsInput.tsx)
- [XLSX 无 DOM 计算入口](../../../lynx-os/references/betteroffice/packages/xlsx/src/headless.ts)

## GenOffice：功能语义与格式兼容性

- [上游仓库](https://github.com/genspark-ai/genoffice)
- [本地研究副本](../../../lynx-os/references/genoffice/)，本地 HEAD：`70e5149e814b4c8b46ae1304ea5f6c5ae39ceef0`。
- 重点参考：DOCX/PPTX 解析与生成、样式和布局规则、编辑功能、兼容性测试与案例。
- PPTX 的模型、RenderTree、文本布局和字体度量接口比较适合作为可移植计算管线的参考。
- DOCX 部分分页依赖 DOM 测量，headless 导出依赖隐藏的 Electron renderer。迁移这一部分需要重建计算能力，不是替换 I/O 即可。
- Sheets 集成了 Univer OSS 包；不能把 GenOffice 表格功能全部当成其自研且可独立搬走的引擎。已检查的集成不是以 Univer PRO 作为这套功能来源。
- 不移植桌面外壳、AI 面板、Electron IPC 和其他非 SDK 产品机制。

阅读入口：

- [DOCX 引擎](../../../lynx-os/references/genoffice/packages/docx-engine/src/)
- [PPTX 引擎](../../../lynx-os/references/genoffice/packages/pptx-engine/src/)
- [PPTX 文本布局](../../../lynx-os/references/genoffice/packages/pptx-render/src/text-layout.ts)
- [PPTX 字体度量](../../../lynx-os/references/genoffice/packages/pptx-render/src/metrics.ts)
- [DOCX 浏览器分页测量](../../../lynx-os/references/genoffice/apps/docs/src/renderer/pagination-measure.ts)
- [DOCX headless 导出](../../../lynx-os/references/genoffice/apps/docs/src/renderer/headless-export.ts)
- [Sheets 依赖清单](../../../lynx-os/references/genoffice/apps/sheets/package.json)

## Univer：SDK 目标与能力组织

- [上游仓库](https://github.com/dream-num/univer)
- [本地源码](../../../lynx-os/references/univer/)，本地 HEAD：`d61608dace76b0db299c552eb3d1dccf0f8986dc`。
- 重点参考：开发者 API、命令与模型的组织、公式计算、渲染/交互分层和可嵌入体验。
- 本地 `univer` 目录确实是源码，不是单纯的安装产物或 API 文档。
- 不依赖 Univer PRO 作为必需能力，不承诺兼容其全部 API 或插件协议。
- 不假设其 UI 可以直接接到 MoonBit 核心；模型、命令和渲染约定不同。

阅读入口：

- [核心](../../../lynx-os/references/univer/packages/core/src/)
- [公式引擎](../../../lynx-os/references/univer/packages/engine-formula/src/)
- [渲染引擎](../../../lynx-os/references/univer/packages/engine-render/src/)
- [文档交互层](../../../lynx-os/references/univer/packages/docs-ui/src/)
- [表格交互层](../../../lynx-os/references/univer/packages/sheets-ui/src/)

本地链接依赖当前与 `lynx-os` 并列的工作区布局；它们仅供研究，不是构建依赖。这三个原有项目未复制到本仓库；后续新增研究副本位于仓库根 `references/`，清单见 [G0](../g0-foundation-review.md)。复用源码、字体和测试文件前，应分别核对许可证与来源，保留必要声明；不以仓库顶层许可证代替逐项依赖核查。
