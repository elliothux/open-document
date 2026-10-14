# 上游参考项目

**功能与 UI 参考：本地 `references/genoffice` 源码。目标是复刻文档、表格、PPT、PDF 的全功能 SDK。** GenOffice App 仅用于视觉对比验收和交互参考。Office 能力、布局、算法、兼容行为与独立测试基准优先参考 ONLYOFFICE（[core](https://github.com/ONLYOFFICE/core)、[sdkjs](https://github.com/ONLYOFFICE/sdkjs)），其次 [LibreOffice](https://github.com/LibreOffice/core)。技术选型与边界归 [SDK 合同](sdk.md)。

下文保留按具体能力选读的补充入口。研究来源不等于构建依赖或已验证能力，当前采用的依赖见[依赖记录](dependencies.md)。

参考关系不是整体 fork，也不是逐行翻译。优先参考功能语义、数据结构、格式兼容规则、测试样本和真实行为，再按照本项目边界实现。

## BetterOffice：架构与核心/宿主边界

- [上游仓库](https://github.com/openooxml/betteroffice)
- [固定源码快照](https://github.com/elliothux/betteroffice/tree/c10db4b848c1e74c920416986ec2e34bf95ee7f3/)，研究 revision：`c10db4b848c1e74c920416986ec2e34bf95ee7f3`。
- 重点参考：OOXML 基础模块、文档会话、WASM 边界、布局与绘制分离、Worker 接入和无 DOM 计算入口。
- 不照搬其 Rust 技术栈，不把现有功能和兼容性覆盖当作最终目标。
- 其字体基础依赖 `skrifa`、`rustybuzz`、`unicode-linebreak`、`unicode-bidi`；换用 MoonBit 后需要验证对应能力，不能假设换语言后自动继承。

阅读入口：

- [字体与文本依赖](https://github.com/elliothux/betteroffice/blob/c10db4b848c1e74c920416986ec2e34bf95ee7f3/crates/ooxml-text/Cargo.toml)
- [DOCX Canvas 后端](https://github.com/elliothux/betteroffice/blob/c10db4b848c1e74c920416986ec2e34bf95ee7f3/packages/docx/src/layout/render/canvasBackend.ts)
- [DOCX Worker 接入](https://github.com/elliothux/betteroffice/blob/c10db4b848c1e74c920416986ec2e34bf95ee7f3/packages/docx/src/yrs/residentEngineWorkerClient.ts)
- [DOCX 输入适配](https://github.com/elliothux/betteroffice/blob/c10db4b848c1e74c920416986ec2e34bf95ee7f3/packages/docx-react/src/components/DocxEditor/YrsInput.tsx)
- [XLSX 无 DOM 计算入口](https://github.com/elliothux/betteroffice/blob/c10db4b848c1e74c920416986ec2e34bf95ee7f3/packages/xlsx/src/headless.ts)

## GenOffice：功能清单、默认 UI 与交互参考

- [上游仓库](https://github.com/genspark-ai/genoffice)
- [固定源码快照](https://github.com/genspark-ai/genoffice/tree/70e5149e814b4c8b46ae1304ea5f6c5ae39ceef0/)，研究 revision：`70e5149e814b4c8b46ae1304ea5f6c5ae39ceef0`。
- 重点核对：四类编辑器的实际功能、操作入口、默认 UI、保存结果与源码限制。详细差距见 [G3](../g3-genoffice-sdk-gap.md)。
- 早期研究中的模型、RenderTree、布局和字体度量入口保留来源；不据此改变 ONLYOFFICE、LibreOffice 的实现参考顺序。
- DOCX 部分分页依赖 DOM 测量，headless 导出依赖隐藏的 Electron renderer。迁移这一部分需要重建计算能力，不是替换 I/O 即可。
- Sheets 集成了 Univer OSS 包；不能把 GenOffice 表格功能全部当成其自研且可独立搬走的引擎。已检查的集成不是以 Univer PRO 作为这套功能来源。
- 桌面外壳和 Electron IPC 不移植；AI 等外围功能按路线图的功能优先级 P2 接入 SDK。

功能与 UI 研究以本地 `references/genoffice` 为依据，2026-10-14 核对的 revision 为 `5eab98adc8d0ebf6ecea687e42400a791ef58d64`。上面的早期格式研究快照继续保留原始依据。GenOffice App 仅用于视觉对比验收和交互参考；出现差异时先检查版本，不假定已安装 App 与源码版本相同。

UI 阅读入口：

- [共享 UI 与依赖](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/ui/package.json)：现有共享组件使用 React，并包含 AI 等应用依赖，按需提取而非整体依赖。
- [设计变量](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/ui/src/tokens.css)：颜色、圆角、文字尺寸与主题；UI 缩放和文档缩放分离。
- [DOCX Ribbon](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/components/Ribbon.tsx)：分组与操作参考；其中 Tiptap 命令改接本项目 SDK。
- [PPTX Ribbon](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/renderer/components/Ribbon.tsx)：标签、分组、图文控件与编辑选区恢复参考。
- [Sheets 界面](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/sheets/src/renderer/App.tsx)与[样式](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/sheets/src/renderer/styles.css)：参考外观和操作流程，保留本项目的 XLSX 核心与通用 Renderer。

阅读入口：

- [DOCX 引擎](https://github.com/genspark-ai/genoffice/tree/70e5149e814b4c8b46ae1304ea5f6c5ae39ceef0/packages/docx-engine/src/)
- [PPTX 引擎](https://github.com/genspark-ai/genoffice/tree/70e5149e814b4c8b46ae1304ea5f6c5ae39ceef0/packages/pptx-engine/src/)
- [PPTX 文本布局](https://github.com/genspark-ai/genoffice/blob/70e5149e814b4c8b46ae1304ea5f6c5ae39ceef0/packages/pptx-render/src/text-layout.ts)
- [PPTX 字体度量](https://github.com/genspark-ai/genoffice/blob/70e5149e814b4c8b46ae1304ea5f6c5ae39ceef0/packages/pptx-render/src/metrics.ts)
- [DOCX 浏览器分页测量](https://github.com/genspark-ai/genoffice/blob/70e5149e814b4c8b46ae1304ea5f6c5ae39ceef0/apps/docs/src/renderer/pagination-measure.ts)
- [DOCX headless 导出](https://github.com/genspark-ai/genoffice/blob/70e5149e814b4c8b46ae1304ea5f6c5ae39ceef0/apps/docs/src/renderer/headless-export.ts)
- [Sheets 依赖清单](https://github.com/genspark-ai/genoffice/blob/70e5149e814b4c8b46ae1304ea5f6c5ae39ceef0/apps/sheets/package.json)

## Univer：SDK 目标与能力组织

- [上游仓库](https://github.com/dream-num/univer)
- [固定源码快照](https://github.com/dream-num/univer/tree/d61608dace76b0db299c552eb3d1dccf0f8986dc/)，研究 revision：`d61608dace76b0db299c552eb3d1dccf0f8986dc`。
- 重点参考：开发者 API、命令与模型的组织、公式计算、渲染/交互分层和可嵌入体验。
- 本地 `univer` 目录确实是源码，不是单纯的安装产物或 API 文档。
- 不依赖 Univer PRO 作为必需能力，不承诺兼容其全部 API 或插件协议。
- 不假设其 UI 可以直接接到 MoonBit 核心；模型、命令和渲染约定不同。

阅读入口：

- [核心](https://github.com/dream-num/univer/tree/d61608dace76b0db299c552eb3d1dccf0f8986dc/packages/core/src/)
- [公式引擎](https://github.com/dream-num/univer/tree/d61608dace76b0db299c552eb3d1dccf0f8986dc/packages/engine-formula/src/)
- [渲染引擎](https://github.com/dream-num/univer/tree/d61608dace76b0db299c552eb3d1dccf0f8986dc/packages/engine-render/src/)
- [文档交互层](https://github.com/dream-num/univer/tree/d61608dace76b0db299c552eb3d1dccf0f8986dc/packages/docs-ui/src/)
- [表格交互层](https://github.com/dream-num/univer/tree/d61608dace76b0db299c552eb3d1dccf0f8986dc/packages/sheets-ui/src/)

## 其他能力参考

以下固定源码入口供对应功能需要时选读，不构成待实施清单：

| 项目 | 阅读范围 |
| --- | --- |
| [Open XML SDK](https://github.com/dotnet/Open-XML-SDK/tree/431ab05cf160248cc3885a4a766026d4f8243792) | OPC、类型化操作与未知内容保留 |
| [Typst](https://github.com/typst/typst/tree/e58a63af09032a486b12241d08ebd04131483221) | 核心/宿主边界与布局产物 |
| [Parley](https://github.com/linebender/parley/tree/80faa617c851679c2a925293224cd7cda4a17877) | 文本布局与编辑几何 |
| [IronCalc](https://github.com/ironcalc/IronCalc/tree/09e81f53f4c021fc0ec212e95fb353a1c6c5c704) | 表格、公式与编辑事务 |
| [Excelize](https://github.com/qax-os/excelize/tree/efb59188b3f56bbffdd614408ad85634292642db) | XLSX 读写与格式规则 |
| [Krilla](https://github.com/LaurenzV/krilla/tree/ce83e37f2913623b9283f7cb75c21b21d9c59a8a) | PDF 输出与字体子集 |
| [PDF.js](https://github.com/mozilla/pdf.js/tree/24de17e81b3357b30ffd710ec080be00d65ac98d) | PDF 浏览器参考 |
| [PDFium](https://github.com/chromium/pdfium/tree/a84323421e94f484faca52dd9d027934eba42ab8) | PDF 独立读取与渲染参考 |

阅读入口使用固定 commit 的上游链接，新检出不需要本机研究目录。复用源码、字体和测试文件前，应分别核对许可证与来源，保留必要声明；不以仓库顶层许可证代替逐项依赖核查。
