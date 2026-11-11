# 上游参考项目

**功能与 UI 参考：本地 `references/genoffice` 源码。目标是复刻文档、表格、PPT、PDF 的全功能 SDK。** GenOffice App 仅用于视觉对比验收和交互参考。Office 能力、布局、算法、兼容行为与独立测试基准优先参考 ONLYOFFICE（[core](https://github.com/ONLYOFFICE/core)、[sdkjs](https://github.com/ONLYOFFICE/sdkjs)），其次 [LibreOffice](https://github.com/LibreOffice/core)。技术选型与边界归 [SDK 合同](sdk.md)。

下文保留按具体能力选读的补充入口。研究来源不等于构建依赖或已验证能力，当前采用的依赖见[依赖记录](dependencies.md)。

上游测试入口、原件数量和复用边界统一见[文件兼容性矩阵](compatibility.md#上游矩阵与可用语料)。本轮候选与固定 revision 登记在私有 `cases/c0-upstream-candidates.json`。

参考关系不是整体 fork，也不是逐行翻译。优先参考功能语义、数据结构、格式兼容规则、测试样本和真实行为，再按照本项目边界实现。

## 本地源码目录

`references/` 是各环境独立准备的研究副本，目录名称与检出状态可能不同。2026-10-30 本机用于测试语料调查的实际目录见下表；部分只有 Git 元数据和按需取得的 blob，可按固定 revision 用 `git show` 读取。该环境未找到此前记录的 `references/SOURCES.json` 和 `references/README.md`，不能将它们作为必需入口。固定上游链接仍可独立使用。

| 项目 | 本地目录 | 参考范围 |
| --- | --- | --- |
| GenOffice | `references/genoffice/` | 四类编辑器的功能、UI 与操作 |
| ONLYOFFICE core | `references/onlyoffice/DocumentServer/core/` | 首选格式、布局、字体与算法 |
| ONLYOFFICE sdkjs | `references/onlyoffice/DocumentServer/sdkjs/` | 首选编辑模型、交互与兼容行为 |
| LibreOffice core | `references/libreoffice-core/` | 次选格式、布局与独立回归依据；另有 `references/core/`，revision 不同，不混用 |
| [Collabora Online](https://github.com/CollaboraOnline/online.mirror) | `references/collabora-online/` | 浏览器集成与补充交互案例 |
| BetterOffice | `references/betteroffice/`（2026-11-11 按需检出） | SDK 架构、公开组件、命令状态与核心/宿主边界 |
| Univer | `references/univer/` | API、公式与能力组织 |
| Open XML SDK | `references/Open-XML-SDK/` | OPC、OOXML 与未知内容保留 |
| Typst | `references/typst/` | 布局与核心/宿主边界 |
| Parley | `references/parley/` | 文本布局与编辑几何 |
| IronCalc | `references/IronCalc/` | 公式与表格事务 |
| Excelize | `references/excelize/` | XLSX 读写与格式规则 |
| Krilla | `references/krilla/` | PDF 输出与字体子集 |
| PDF.js | `references/pdfjs/` | PDF 浏览器行为 |
| PDFium | `references/pdfium/` | PDF 独立读取与渲染 |
| [Poppler 26.05.0](https://poppler.freedesktop.org/poppler-26.05.0.tar.xz) | `references/poppler-26.05.0/` | 独立 PDF 栅格参考；按需提取 Splash 平铺采样源码及许可证 |
| Apache POI | `references/apache-poi/` | Office 原件、结构和往返断言 |
| ONLYOFFICE-QA x2t-testing | `references/onlyoffice-x2t-testing/` | 历史转换测试组织与公开小样本 |
| Calamine | `references/calamine/` | 真实世界怪异 XLSX/XLS 容器、命名空间、共享字符串与共享公式边缘案例（MIT） |
| Office Oxide | `references/office_oxide/` | OOXML 往返保真、内存分配预算与畸形包鲁棒性测试（MIT / Apache-2.0） |
| Anydoc | `references/anydoc/` | 多格式文档提取、快照对比与鲁棒性边界样本（MIT） |
| Apache Tika | `references/apache-tika/` | 多生产工具生成的真实文档语料（仅 `.git` 对象库，按 `git show` 读取，Apache-2.0） |

这些副本只用于源码对比；子模块与 Git LFS 大文件按实际构建需求另行获取。`references/` 由根 `.gitignore` 管理，公开 SDK 构建继续使用固定生产依赖。

## BetterOffice：架构与核心/宿主边界

2026-11-11 的 SDK/UI 研究使用 [revision `62605af397a309cb81c86aed8b8453a54a4edf22`](https://github.com/openooxml/betteroffice/tree/62605af397a309cb81c86aed8b8453a54a4edf22)。本地按需检出文档与相关 TypeScript 源码。公开 React 控件、命令与工具栏测试入口归 [G4](../implemented/g4-office-sdk-productization.md#9-固定源码依据)。下面保留早期引擎研究的固定来源。

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
