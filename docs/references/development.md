# 开发与模块边界

当前实现工程/文本 POC、字体塑形、有界 ZIP/XML/OPC，以及限定 DOCX/XLSX/PPTX 编辑与 PDF 输入输出。DOCX 覆盖普通正文和单个表格单元格；XLSX 覆盖稀疏网格、值/首批公式、历史、剪贴板、保真保存与独立打印。PPTX 提供限定图文编辑、保真保存和静态 PDF；PDF 提供限定预览/查询、页面整理、批注、普通字段与源对象保存。当前支持面见[格式合同](formats.md)，固定第三方依赖见[依赖记录](dependencies.md)。

XLSX 交付及检查范围见 [P5](../implemented/p5-xlsx-editing.md)。MoonBit 负责源内容、计算及布局；平台绘制和事件继续由 TS 处理。

PPTX 的交付范围与检查依据见 [P6](../implemented/p6-pptx-editing.md)。三种格式共用有序定位图元、基础路径/矩阵及 PDF；原生输入事件与图片解码复用现有模块。

PDF 输入和文档操作见 [P7](../implemented/p7-pdf-input.md) 与 [P8](../implemented/p8-pdf-operations.md)。`formats/pdf/input-*` 按读取、内容、文字、资源、事务、页面、批注和字段分工；`modules/bridge/src/pdf.mbt` 分发类型化命令。`@open-document/wasm/pdf` 提供 `PdfSession`，`loadEngine(wasm).openPdf()` 创建同步会话；`@open-document/web/pdf` 提供 Worker `PdfClient`。`pdf-viewer`、`pdf-editor`、`pdf-canvas` 复用现有表面、绘制与剪贴板入口。API、嵌入示例和生命周期归[格式合同](formats.md#pdf-输入与文档操作)。

## Workspace

| 位置 | 所有权 | 允许依赖 |
| --- | --- | --- |
| `modules/core` | text、failure、archive、XML 源片段与 OPC 图 | 标准库、固定 flate/xml；不依赖宿主 |
| `modules/layout` | 字体塑形、几何、分页、图表布局与绘制结果 | core；不通过 DOM 决定布局 |
| `modules/formats` | docx/xlsx/pptx/pdf 的独立语义与读写；`internal/image` 共用 PNG/JPEG 输入预算与文件头校验 | core；需要输出布局时依赖 layout |
| `modules/bridge` | Wasm 导出、核心到宿主的批量 ABI | core、layout、formats/docx、formats/xlsx、formats/pptx、formats/pdf |
| `packages/wasm` | 实例化与 ABI 校验 | WasmGC 产物；不拥有第二份文档模型 |
| `packages/web` | Worker 请求、输入事件排序、页面呈现与生命周期 | wasm 包；不实现文本替换、撤销或排版 |
| `packages/ui` | 默认 React UI、ShadowRoot、文件候选、宿主保存回调 | web、React、Base UI；文档操作复用编辑宿主队列 |

根 `moon.work` 明确列举四个 module，各 module 内以 package 划分真实 concern。暂不为每种格式创建独立发布 module，也不创建 CLI 空壳。根 Bun workspace 只包含 `packages/*`，一个公开 `bun.lock`；私有工具是独立仓库和独立依赖域，不加入公开 workspace。

`layout/chart-*` 拥有图表系列模型和排版；`formats/internal/chart` 读写原生图表 XML 与关系，不依赖 XLSX。嵌入工作簿的矩形数据读取归 `formats/xlsx/chart-data.mbt`，DOCX/PPTX 各自维护源对象与资源事务。传输校验和默认面板共用图表字段，TS 不持有第二份图表状态。

`layout/math-*` 拥有数学结构、字体度量和图元；`formats/internal/omml` 共用有界原生读取、LaTeX 和 OMML 写回，DOCX 提供文档数学设置，PPTX 处理 DrawingML 与兼容包装。DOCX/PPTX 分别维护源锚点和编辑事务。TS 继续只处理平台输入和绘制。

文本 POC 使用 UTF-16 范围，不允许切断 surrogate pair；它不是字素导航或富文本编辑器。核心保留最多 100 条文本快照用于 POC 撤销；DOCX 编辑使用独立的局部源补丁历史。当前 ABI 使用 JS string builtins，尚不承诺其他 WasmGC runtime 等价运行。

## 当前 Foundation API

XML `Document.nodes()` 按当前文档顺序返回只读节点，数组位置不再是结构身份。`Node.id` 与 `Node.parent` 使用稳定 ID，`Document.node(id)` 查当前节点；删除身份失败，undo/redo 恢复事务登记的身份。DOCX 的 `WordTree`、文本清单、Flow 与源范围从此结果派生。Document 的可变容器均为私有，文本与空段写回由 XML 局部源补丁生成候选；Session 在 OPC 校验成功后统一提交，不再维护文本覆盖表。历史只留变动片段，不持有全篇状态快照。

公开源码入口为 `packages/wasm/src/foundation.ts` 和 `packages/web/src/foundation.ts`，与既有文本 POC 分属真实职责。底层 `(await loadEngine(wasm)).openFoundation()` 适用于受控同步调用；浏览器使用 `FoundationClient.open(wasm, workerUrl)`。宿主提供实际 release Wasm 字节和 bundle 后 Worker 的 URL，不依赖测试服务器。

客户端提供 `defaultBudget()`、`addFont(bytes, identity)`、`shape(text, size, language)`、`openDocx(bytes, budget)`、`query()`、`replaceNode(id, revision, text)`、`saveDocx()`、`flow()`、`imageBytes(key)`、`addImage(key,width,height,rgba)`、`layout(profile)`、`exportPdf(outputBytes,layoutId?)` 与 `dispose()`。DOCX 打开要求显式预算，可从核心默认值复制并收紧。`ShapeBatch` 包含字体身份、font units 度量、CSS px 位置和 UTF-16 clusters；布局使用 point。`addImage()` 返回内容绑定的资源标识。`layout()` 返回绘制指令、资源及独立语义信息；内部完整布局留在核心。`@open-document/web/drawing` 的 `CanvasRenderer` 执行指令，持有同会话派生的 Path2D，并在结束时 `dispose()`。数据类型和校验位于 `@open-document/wasm/drawing`，合同归[格式说明](formats.md#通用绘制输出)。

P4 编辑 API 提供 `editState()`、`selectDocx(revision, selection)`、`selectedText(revision, selection)`、`replaceRange(revision, selection, text)`、`deleteDocx(revision, direction)`、`undoDocx(revision)` 与 `redoDocx(revision)`，Node 同步 API 和 Worker Promise API 使用同一核心事务。页面几何查询为 `hitTest(layoutId, page, x, y)`、`caret(layoutId, position)`、`selectionGeometry(layoutId, selection)`；`navigateDocx(revision, layoutId, direction, extend = false)` 更新核心选区并返回光标，同样由核心计算。位置、导航、范围、保护规则及资源上限归[格式合同](formats.md#p4-当前编辑-api-切片)，交付范围与验证边界见 [P4](../implemented/p4-docx-editing.md)。

导航返回的 `DocxPosition` 可含 `bidiLevel` 和 `frameStart`。调用者重放光标时保留这些核心元数据；编辑和选区范围始终使用 `offset`。具体校验、清除和历史恢复规则归[格式合同](formats.md#p4-当前编辑-api-切片)。

编辑器停止后，普通 Undo 按钮或快捷键可以显式撤销已提交的编辑并恢复布局；不自动回滚。Redo 与新输入仍停止，外部 revision 变化须先调用 `resume()`，不能撤销未知外部编辑。恢复沿用同一队列，`whenIdle()` 和 `dispose()` 等待已接受的恢复工作；销毁后不重绘。剪切在写剪贴板成功后比较 revision 及完整位置元数据，不因逻辑范围相同而忽略方向或页框变化。

核心组合 API 为 `beginComposition(revision)`、`updateComposition(revision, compositionId, text)`、`commitComposition(revision, compositionId, text)` 与 `cancelComposition(revision, compositionId)`；同步 Node 与 Promise Worker 使用同一 MoonBit 候选/提交入口。`EditState` 和 `DocxQuery` 增加 `compositionId: number | null`。开始绑定当前选区，每次更新重算原范围，query/Flow/几何读取暂态；revision 与历史不变。结束使用显式最终文字，最多一条历史，取消或空结束保留原状态；过期组合身份明确失败。更新/结束/取消使旧 layout 失效，保存/PDF/普通编辑返回 busy。核心、正式 API 与 Chromium CDP composition 事件已有验证；此前固定产物在 macOS/Chromium 使用现有豆包拼音完成中文提交、取消、撤销重做和保存。归档产物另完成普通 Chrome 系统输入、撤销/重做及独立保存复验。R0 后的定向检查覆盖组合候选与取消，未重做系统中文输入验收；各记录的产物与范围见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)。按用户决定不切换输入源，不追加系统简体拼音或 VoiceOver 验收；历史中文组合证据不扩大为当前所有输入法或候选窗几何支持。

`@open-document/web/editor` 提供 `DocumentEditor.create(root, client, profile, signal?)`。调用者先供应字体并打开 DOCX，组件存活期间独占 client 操作。`dispose(): Promise<void>` 关闭 UI/监听器，等待在途回复并取消自身未提交组合；调用方须 await 后再复用或关闭 client。已发送的最终提交可能成功，不自动回滚。

`whenIdle()` 等待已接受意图；`saveDocx()` 和 `exportPdf(outputBytes?)` 返回屏障处的 `EditorOutput`，PDF 绑定已显示 layout ID。`downloadDocx()` / `downloadPdf()` 记录下载生成，`setZoom()` 调整显示。公开 `undo/redo`、`goToPage`、`copy(cut?)`、`paste(text)` 使用同一队列。组件保留点击/拖选、键盘输入与导航、拆合普通段落和组合输入。Shift+Enter 插入软换行，Ctrl/Cmd+Enter 插入分页符，Ctrl/Cmd+Shift+Enter 插入分栏符；参数控件保留浏览器焦点切换。输出、当前输入范围与恢复归[格式合同](formats.md#默认-ui-与编辑宿主)及[当前格式编辑](formats.md#p10-当前格式编辑)。富 HTML/RTF 粘贴继续实施。

普通 Chrome 系统输入的绑定产物与独立保存记录在私有 `cases/p4-native-input-current.json`。这不授予所有输入法或完整布局支持。[P4](../implemented/p4-docx-editing.md) 已按限定范围归档，性能专项延后。

`@open-document/web/preview` 的 `DocumentPreview` 复用 caller 的 `FoundationClient`，创建和关闭边界见[格式合同](formats.md)。宿主先加载所需授权字体；预览准备包内图片、请求核心布局、执行绘制及下载。TS 不持有可编辑文档树，不再塑形。

`tools/prepare-dependencies.mbtx` 是公开构建准备步骤，不依赖私有测试库。它让 Moon 下载精确固定依赖，再按[逐文件清单](../../tools/harfbuzz-patches/index.json)核对 HarfBuzz 0.1.0 的原始/修改后 SHA-256，并应用依赖记录中的修复及资源限制；重复运行核对已补丁 hash。未知源码直接失败，准备子命令的错误输出保留。`check`、`build`、`api` 调用此步骤；直接运行 Moon 命令前也需先运行它。补丁依据、移除条件和许可归[依赖记录](dependencies.md)。

连接代码只拥有一个 in-flight 请求和 Worker 生命周期。用户字节经 structured clone 进入 Worker。字体以八位字符串调用内部 `foundation_add_font`，核心构造字节后使用原字体校验与资源拥有者。公开 `addFont` 和 32 MiB 预算保持，旧 JSON font 分支已删除。DOCX 和图片仍使用原 JSON/Base64 路径。两种路径共用响应及错误解析；连接代码不维护可编辑文档树。

公开主线程入口保留 ESM 模块导入，`engine`、Wasm `foundation` 与 Web client 使用同一份 `DocumentError` 构造函数。共用错误和预算校验位于 `session.ts`，`foundation` 保留原导出；基础会话不反向依赖 DOCX 子类，XLSX 入口可单独加载。应用构建器需要解析 `@open-document/wasm` 的公开子路径；直接加载浏览器 ESM 时，需要 import map 将使用的 `foundation`、`preview`、`drawing`、`engine` 子路径映射到对应产物。内部运行时导入使用 `.js` 扩展名。Worker 单独打包，因此不依赖主页面的 import map。公开 tarball 包含这些模块及其内部依赖，测试服务器只提供资源路由。

## 默认 Web UI

DOCX、XLSX、PPTX 可用 `document: { name, blank: true }` 空白挂载，也可调用已挂载实例的 `create({ name })`。`OfficeDocument` 统一表示 Office 字节或空白输入，PDF 继续使用带字节的 `EditorDocument`。核心默认文档、创建 API 与首次保存规则归[格式合同](formats.md#默认-ui-与编辑宿主)。

[`@open-document/ui`](../../packages/ui/package.json) 提供 `mountEditor`，普通 JS 和 TS 使用同一个入口。调用者显式供应文档、release Wasm、已打包 Worker URL、授权字体及 profile。容器需要可测量的高度；SDK 追加自己的 open ShadowRoot，不替换调用者 DOM。

```js
import { mountEditor } from "@open-document/ui";

const mounted = await mountEditor(container, {
  format: "docx",
  document: { name: "example.docx", bytes: docxBytes },
  resources: { wasm: wasmBytes, workerUrl, fonts, profile },
  locale: "zh-CN",
  theme: "light",
  onSave: persistDocument,
});
const unsubscribe = mounted.subscribe(() => updateStatus(mounted.getSnapshot()));
await mounted.save();
unsubscribe();
await mounted.close();
```

示例资源变量及 `persistDocument` 由宿主提供。`editor` 按返回值的 `format` 区分类型，文件替换后重新获取当前宿主。保存回执、未保存提示、取消和释放的实际合同归[格式说明](formats.md#默认-ui-与编辑宿主)。自定义 UI 直接使用 Web 编辑宿主，不需要 React。

`packages/ui` 以 React `useSyncExternalStore` 观察宿主。Tailwind 只在构建时运行，省略 Preflight，CSS 文本随 ESM 入口进入实例 `<style>`。Base UI 的 Tabs/Menu/Dialog 使用实例内 Portal；`styleNonce` 同时供应自建样式和 Base UI CSP provider。关键尺寸为本地 px token，light/dark 不改变文档颜色。普通菜单非模态；关闭确认暂时限制整个页面交互并恢复焦点/滚动。

`bun run build` 生成三个包的 JS/types/样式、Wasm、Worker 和 [`examples/web-sdk`](../../examples/web-sdk/index.html) 普通 JS 示例。只重建示例时运行 `bun run build:example`，前提是三个包已有当前构建。使用静态 HTTP 服务托管整个示例目录，选择本地文档即可打开。示例自动加载随附替代字体并提示排版差异；额外字体和 profile 为可选覆盖，规则归[字体资源与替代](formats.md#字体资源与替代)。例如运行 `python3 -m http.server 4173 --bind 127.0.0.1 --directory examples/web-sdk`，在 Chrome 打开 `http://127.0.0.1:4173/`。示例每次加载为入口 JS 创建新请求标识，Wasm/Worker 在挂载时共用新标识，字体与 Wasm 禁用 HTTP 缓存，避免开发期 HTML 与旧执行资源混用。缺省输出下载；勾选宿主保存后，Chrome 选择目录，示例回调在文件流关闭成功后确认保存。示例没有私有路径、字体或测试服务器依赖。

三个包仍为 private/WIP，可分别用 `bun pm pack` 生成本地 tarball。消费项目将 `@open-document/wasm`、`@open-document/web`、`@open-document/ui` 指向这些 tarball，并将 Wasm/Web 的 overrides 指向同一份本地包；安装固定 React/React DOM peer 版本。主线程由消费项目构建器解析公开子路径；Worker 和 Wasm 由宿主部署到明确 URL，不自动加载字体。

## XLSX 嵌入入口

同步入口是 `(await loadEngine(wasm)).openXlsx()`，返回 `@open-document/wasm/xlsx` 的 `XlsxSession`。浏览器使用 `@open-document/web/xlsx` 的 `XlsxClient`，再挂载 `@open-document/web/spreadsheet-editor`。两个格式共用基础 WASM 调用、Worker 连接、Renderer、Canvas 表面与 PDF writer；同一个核心会话只打开一种格式。

```ts
import { XlsxClient } from "@open-document/web/xlsx";
import { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";

const client = await XlsxClient.open(wasmBytes, workerUrl);
const workbook = await client.openXlsx(xlsxBytes, await client.defaultBudget());
await client.addFont(regularFontBytes, "regular");
await client.addFont(boldFontBytes, "bold");
const profile = { Calibri: "regular", "Calibri|bold": "bold" };
const editor = await SpreadsheetEditor.mount(root, client, profile);
await editor.select("A2");
const saved = await editor.save();
const pdf = await editor.exportPdf({
  width: 595.28, height: 841.89,
  top: 36, right: 36, bottom: 36, left: 36,
  range: "A1:F40",
});
await editor.dispose();
client.dispose();
```

示例变量由应用提供。实际字体映射以 `workbook.fontKeys` 为准；可继续添加 CJK 等后备字体，字体身份与既有字体/嵌入预算保持。字体缺失返回明确错误，不使用浏览器字体度量代替核心。

编辑器独占 client 的在途请求。使用 `select`、`move`、`copy`、`paste`、`clear`、`undo/redo`、`setZoom`、`save`、`printLayout`、`showPrintPage`、`closePrintPreview`、`exportPdf` 与 `refresh`；读取 `currentState/currentLayout` 获取已呈现状态。保存/PDF 返回 `EditorOutput`。`whenIdle()` 等待已接受队列，不代表未来滚动请求或新平台事件已结束。调用者若直接修改 client，应等待队列结束，取消旧草稿后刷新；revision 冲突不会静默覆盖修改。

`XlsxClient.query/replace/copy/paste/clear/viewport/hit/selectionGeometry/printLayout` 的细节、输入语义、保真和资源上限归[格式合同](formats.md#p5-xlsx-合同)。同步会话结束用 `close()`，Worker 客户端结束用 `dispose()`。宿主自行打包 Worker 并提供 WASM、文件及字体，不依赖私有服务器。打印预览与 PDF 使用同一核心页面；PDF 不截取屏幕 Canvas。

## PPTX 入口

`@open-document/wasm/pptx` 提供 `PptxSession`、`PptxCommand` 及严格结果校验。同步会话通过 `loadEngine(wasm).openPptx()` 创建；浏览器用 `@open-document/web/pptx` 的 `PptxClient`，两者执行相同的类型化 `execute(command)`。一个会话只打开一种格式，所有修改携带当前 revision。

```ts
import { PptxClient } from "@open-document/web/pptx";
import { PresentationEditor } from "@open-document/web/presentation-editor";

const client = await PptxClient.open(wasmBytes, workerUrl);
const state = await client.execute({
  operation: "openPptx",
  bytes: pptxBytes,
  budget: await client.defaultBudget(),
});
// Supply licensed fonts and mappings for the document and intended input scripts.
await client.addFont(fontBytes, "regular");
const profile = Object.fromEntries(state.fontKeys.map(key => [key, "regular"]));
const editor = await PresentationEditor.create(root, client, profile);
const saved = await editor.save();
const pdf = await editor.exportPdf(true, false);
await editor.dispose();
client.dispose();
```

调用者应按实际字体样式提供映射；示例把全部键映射到一份字体，仅演示接入顺序。先供应所需脚本字体，缺失映射或字形时明确失败。组件存活期间独占 client；`dispose()` 等待已接受操作、取消未提交候选并释放画布/资源，调用者随后复用或关闭 client。

`PresentationEditor` 提供 `find()`、`selectMatch()`、`replaceMatches()`、`select()`、`showSlide()`、`setZoom()`、`transform(dx, dy, handle?)`、`copy(cut?)`、`paste()`、`undo()`、`redo()`、`save()`、`exportPdf(all = true, hidden = false, outputBytes?)`、`refresh()` 与异步 `dispose()`。`query` 返回展示状态，`layout` 为当前单页绘制结果；默认 UI 挂入稳定的 `objectList` 语义节点。保存/PDF 返回 `EditorOutput`，等待已接受队列，未结束的组合或拖动拒绝输出。呈现失败保留核心提交，刷新重取状态，Undo 显式撤销。

格式核心位于 `modules/formats/src/pptx`，按关系/继承、图文读取、文本框布局、源编辑、历史和几何拆分。共享定位输入归 `modules/layout/src/positioned.mbt`，PDF writer 按同一图元顺序输出。`NativeTextInput` 共用平台事件与组合机制；`decodeImage` 共用图片头校验、解码及 RGBA 接入。实际能力与上限归[格式合同](formats.md#pptx)。

## 工具与命令

固定 Bun 1.4.2；Moon 工具链 0.1.20261010（moonc v0.10.14+7080b3792-nightly）。本次按维护者选择使用已安装版本。使用官方工具链并将 `~/.moon/bin` 加入 PATH；`moon-toolchain` 是本项目的版本约定，不声称 Moon 会自动安装该版本。

[项目编辑器设置](../../.vscode/settings.json)排除 `.temp`、`.mooncakes` 和 `_build` 的文件监视。生成的测试 SDK 副本不应被语言服务器作为独立工程反复检查或同步依赖；否则后台同步会覆盖已验证的补丁，并与编译争用文件。若编辑器已登记这些临时工程，应用项目设置后重启该项目的 MoonBit 语言服务器。保留失败记录，不删除测试证据，也不通过升级全局工具链修复本项目的固定版本验证。

```sh
bun install --frozen-lockfile
bun run hooks:install
bun run check
bun run build
bun run api
```

- `check:moon`：WasmGC 类型检查，启用的编译器 warnings 全部视作错误。不增加一个与编译器重复的 MoonBit linter。
- `typecheck`：严格 TS，包括 unchecked index 与 exact optional property；不使用 `any`、忽略指令或类型双重断言。
- `lint`：固定版 Oxlint，警告阻止通过。
- `format` / `format:check`：Moon 原生 formatter + Prettier。前者修改格式，后者只检查。
- `api`：Moon 自动生成 `.mbti`，应审阅并跟随源码提交，禁止手改。
- `build`：release WasmGC、浏览器 JS、UI 类型/内联样式和普通 JS 示例；包输出到各自 `dist/`，示例输出到 `examples/web-sdk/dist/`。目前包为 private，未发布。

当前开发先补功能、修正确性和保真问题，不主动运行原生性能测量、A/B 或 CPU profile。现有测量入口保留为后续或实际卡死/不可交互问题的最小诊断工具，命令和边界见[独立执行档](testing.md#独立执行档)；测量状态不阻塞当前功能交付，资源安全和释放回归继续执行。

### Git hook

使用与 open-compute 相同的 `simple-git-hooks`，`pre-commit` 执行 `bun run check`。它检查整个当前工作树，不自动 format、不自动 stage、不自动运行私有测试，也不声称检查的是独立 index 快照。部分暂存时维护者仍须核对暂存差异；完整私有验收不由这个 hook 代替。

通过显式命令安装 hook，并保留已有 hook。GUI Git 客户端需要能找到 Bun/Moon；环境错误应修复后再使用。当前环境已安装本项目配置。

## 开源与私有边界

所有一方测试代码、数据、具体预期结果、原始报告和执行 loop 属于私有 `open-document-test`。产品、架构与测试文档统一在父仓库 `docs/`，不在子仓库重复维护。公开构建完全不依赖私有仓库。`test-lab/` 作为 Git submodule 固定到私有仓库的一个 commit；主仓库只保存 `.gitmodules` 和 gitlink，不包含私有文件。

首次准备私有测试环境时，在 `test-lab/` 执行 `bun install --frozen-lockfile` 和 `bun run browsers`，后者只安装固定 Chromium。日常按[测试说明](testing.md)选择受影响检查。需要覆盖局部检查无法验证的多条功能链风险时，在根目录执行 `bun run test`；它调用私有 loop，缺失 checkout 或任一步骤失败都会返回失败。根 `check` / `build` 和 pre-commit 独立于该测试入口。

空的、尚未初始化的 submodule 目录也会在入口失败。VS Code/Cursor 共用 `.vscode/settings.json`，显式扫描 `test-lab` 并启用 submodule 检测；没有私有权限的公开使用者仍可正常 check/build。

维护者获取私有仓库权限后，在根目录执行 `git submodule update --init --recursive`，按[测试说明](testing.md)安装测试依赖。不自动跟踪远端分支；更新测试时先提交私有仓库，再提交主仓库的 gitlink。普通公开使用者不需要初始化私有 submodule。

提交/推送需用户授权。先推送被引用的私有 commit，再推送主仓库提交，确保其他机器能获取对应 gitlink。

参考：[Moon workspace](https://docs.moonbitlang.com/en/latest/toolchain/moon/workspace.html)、[MoonBit FFI](https://docs.moonbitlang.com/en/stable/language/ffi.html)、[Bun workspaces](https://bun.sh/docs/pm/workspaces)。
