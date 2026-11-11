# 开发与模块边界

当前功能与格式限制归[格式合同](formats.md)，核心/宿主职责归 [SDK 合同](sdk.md)。四格式的领域拆包与共享加载结果归 [R1](../implemented/r1-domain-packages-shared-wasm.md)。

## Workspace

| 位置 | 所有权与依赖边界 |
| --- | --- |
| `modules/core` | text、failure、archive、XML 与 OPC；不依赖浏览器 |
| `modules/layout` | 字体塑形、分页、几何、图表/数学及绘制结果 |
| `modules/formats/src/docx`、`xlsx`、`pptx`、`pdf` | 各格式的权威状态、事务、读写与编辑语义 |
| `modules/bridge/src/common` | 有界字段/字节解析、字体输入、错误响应 |
| `modules/bridge/src/docx`、`xlsx`、`pptx`、`pdf` | 各格式独立上下文、命令、资源与关闭 |
| `modules/bridge/src/all` | 组装四类 ABI，链接唯一分发的 `engine.wasm` |
| `modules/bridge/src/probe` | 独立文本 POC 测试入口，不进入格式引擎导出 |
| `packages/wasm` | 共享 Wasm、构建身份、Loader 和基础 ABI；不导入格式绑定 |
| `packages/web-core` | 通用连接、原生输入、剪贴板、Renderer、Canvas 与快照 |
| `packages/ui` | 共用产品外壳、控件、本地化、样式和文件生命周期 |
| `packages/docx`、`xlsx`、`pptx`、`pdf` | 各自的绑定、协议、Worker、浏览器编辑宿主及 React 面板 |
| `packages/devtools` | 独立快照检查面板；产品包不依赖它 |

MoonBit workspace 保留 `core`、`layout`、`formats`、`bridge` 四个 module，以真实 package 分工。DOCX/PPTX 的嵌入工作簿继续复用 XLSX 核心，Office PDF 输出继续复用 PDF writer；这不引入其他格式的前端编辑器。公开类型留在其所属公共 package，跨包移动后的接口由 `moon info` 生成。

四个编辑宿主使用 `web-core/command-queue` 共用有界排队、空闲屏障和代次管理，每个编辑器持有自己的实例。输入法、草稿、错误恢复、后台重绘和关闭策略归领域宿主；DOCX 的恢复屏障在已接受工作之后执行。Office 队列上限为 64 项，PDF 为 128 项。

Editor 按职责拆文件，使用函数模块，不用继承链拆文件。PPTX 的 `PresentationEditor` 直接拥有编辑、保存和导出方法；输出生成沿用 `presentation-output` 函数，初始与更新快照共用 `presentationSnapshot`。

PDF Editor 不再继承 Viewer。`PdfView` 承载共用的阅读状态、队列、搜索、选区和表面生命周期，`PdfViewer.create` 提供独立阅读入口。Editor 组合该视图，负责草稿、提交和属性控件释放。无状态操作归 `createPdfOperations`，由 `editor.operations` 调用；属性控件呈现归 `renderPdfPropertyDraft`，保护原因仍在呈现前更新。

四格式的 Session/Client 直接使用受信任核心的输出类型。字节响应在 Wasm 边界解码一次；宿主输入检查、错误封装与核心资源预算保留。剪贴板、格式片段和编辑使用的标尺状态作为宿主输入时仍需校验。MoonBit 查询响应逐步使用私有 `derive(ToJson)` 结构，按既有字段序列化，不新增公共模型。

共享成功/错误响应、Office 预算及 DOCX 查询外层、文本项和编辑状态使用私有响应结构。原协议中的可空字段继续显式映射为值或 `Json::null()`；直接派生 `Option` 字段会省略 `None`，直接转换 `Some` 也会改变结构。DOCX 关系项和格式详情仍沿用原映射。

PDF 渲染在核心缓存最近一份编码主体，保留原有页面状态更新。固定切片在创建缓存时完成，`id/reused` 每次生成；页内容用原 `Json.stringify()` 序列化。缓存按不可变 regions 对象身份复用，最多 4,194,304 个 UTF-16 单元；更大的响应完整输出但不缓存。视图释放、编辑/字体失效和关闭均清理缓存。Bridge 的 `encoded_response` 只包装核心已编码 JSON，错误仍复用原映射；其他 PDF 响应继续标准序列化，ABI 对象形状保持。

包构建用固定工具链的 `moon-wasm-opt -Oz` 优化全格式和四个单格式引擎，并按分发字节生成 SHA-256 构建身份。任一优化产物超过 8 MiB 时，构建在写入包文件前失败。

`@open-document/wasm/engine.wasm` 是全格式入口。普通 JS 示例使用单格式 Wasm。宿主也可以显式提供同一包下的 `docx.wasm`、`xlsx.wasm`、`pptx.wasm` 或 `pdf.wasm`。调用 `loadEngine` 时传入该资产的绝对 URL，并从 `@open-document/wasm/engine-source` 读取对应的 `engineBuildIds` 字段。全格式入口使用 `engineBuildId`。核心和 Worker 使用相同的编译模块。

一个 Bun workspace 管理 `packages/*`，公开依赖由根 `bun.lock` 固定。领域包对 wasm/web-core 使用精确版本；React、React DOM 和公共 UI 是领域 React 入口的可选 peer。消费 React 入口时显式安装这些固定版本。`core`、`web` 不需要 React。

## 公开入口与共享加载

四个领域包提供 `core`、`headless`、`web`、`react`、`worker` 子路径。

| 入口 | 内容 |
| --- | --- |
| `@open-document/<format>/core` | 格式类型、校验和同步会话；`openDocx`、`openXlsx`、`openPptx` 或 `openPdf` |
| `@open-document/<format>/headless` | 异步 Worker 会话；`DocxWorkerSession`、`XlsxWorkerSession`、`PptxWorkerSession` 或 `PdfWorkerSession` |
| `@open-document/<format>/web` | Client 与框架无关的编辑宿主 |
| `@open-document/<format>/react` | `DocxEditor`、`XlsxEditor`、`PptxEditor` 或 `PdfEditor`，以及命令式 `mountEditor` |
| `@open-document/<format>/worker` | 本格式的独立 Worker 资源 |
| `@open-document/wasm` | `loadEngine`、不透明 `EngineHandle` 与公共错误 |
| `@open-document/wasm/engine.wasm` | 全格式引擎 |
| `@open-document/wasm/<format>.wasm` | 单格式引擎 |
| `@open-document/wasm/engine-source` | 按产物生成的 `engineBuildId` 和 `engineBuildIds` |
| `@open-document/wasm/assets` | `documentAssets` 解析静态资源位置，`loadDocumentAssets` 加载对应格式引擎 |

`loadEngine(source, signal?)` 接受 `{ url, build }`、`Uint8Array` 或已编译的 `WebAssembly.Module`。相同 URL 和构建身份复用获取和编译结果，缓存最多五个来源。加载失败后可重试。取消只结束当前等待者，其他调用方继续等待。Node 从文件读取 Wasm 字节后调用 Loader。

句柄持有编译结果。Client 首次将 `WebAssembly.Module` 结构化克隆到 Worker，由 Worker 实例化。同一运行环境中的同一 Module 复用一个 Wasm 实例，每个文档各有上下文。实例共享已解析字体和基础字形轮廓。字体别名、回退顺序和资源预算按文档计算。

每个打开的 Client 独占一个 Worker。随包提供的 Worker 确认释放上下文后，可由相同模块和脚本 URL 的后续 Client 复用。浏览器页面最多保留一个空闲 Worker，最长 15 秒。取消在途请求或通信失败时直接终止 Worker。

低层同步调用使用 `openDocx(engine)` 等格式工厂；浏览器使用 `FoundationClient.open(engine, workerUrl, signal?)`、`XlsxClient.open`、`PptxClient.open` 或 `PdfClient.open`。DOCX 的 `FoundationSession`/`FoundationClient` 名称仅表示 DOCX 绑定。每会话只拥有一种格式，公共连接通过类型参数接受该格式协议。

无 UI 的浏览器接入使用 `*WorkerSession.open(engine, workerUrl, signal?)`。会话接收同一格式的 `execute(command)` 调用。先执行打开或新建命令，再查询、编辑和生成输出。一次只发送一个在途请求。用 `dispose()` 取消在途请求或释放会话。重开文件时创建新会话。同步核心用 `close()` 释放。

无 UI 入口由核心处理支持的文件内容，调用方提供文件与字体字节。布局、渲染数据和输出分别按格式合同使用。剪贴板、平台位图解码、浏览器媒体探测与下载由交互宿主或显式适配器负责。交互客户端复用 Worker 会话，并保留既有资源准备流程。

### 无 UI 示例与静态资源

构建后，将对应格式的 Wasm 和 Worker 放在同一静态目录。Wasm 使用 `<format>.wasm` 和 `application/wasm`。Worker 使用 `<format>-worker.js` 和 JavaScript MIME 类型。`loadDocumentAssets` 接收格式和以 `/` 结尾的目录 URL，只加载所选格式的引擎。部署时发布同一构建的模块、Worker、Wasm 和字体。未带版本的入口应重新验证缓存，带内容哈希的分块可长期缓存。离线部署缓存同一版本的资源。

在仓库根目录执行 `bun run build`，再执行 `python3 -m http.server 4174 --bind 127.0.0.1 --directory examples/web-sdk`。Chrome 打开 `http://127.0.0.1:4174/`，用 **Open sample** 打开默认编辑器。打开 `http://127.0.0.1:4174/headless.html` 后，用 **Edit sample** 在 Worker 中添加前缀并下载结果。两个页面也接受宿主文件。部署时保留三个 HTML 页面、`example.css`、`sample.docx` 和完整的 `dist/` 目录。[可分发 DOCX 样本](../../examples/web-sdk/sample.docx)

Node 示例从已安装的包读取 Wasm。复制示例和样本到消费项目后，使用 Node 26 执行 `node headless-node.mjs sample.docx reviewed.docx`。输出文件名必须可新建。[浏览器 Worker 示例](../../examples/web-sdk/headless.js) · [Node 示例](../../examples/web-sdk/headless-node.mjs)

### CSP 与资源错误

同源部署已在 Chrome 下验证以下策略。服务端为每个 HTML 响应生成新的 nonce，将同一个值用于 `style-src` 和示例入口 `<script id="example-script">` 的 `nonce` 属性。示例把该值传给编辑器 `styleNonce`，供 Shadow DOM 样式和 Base UI 弹层使用。宿主自行挂载时也传入响应的 nonce。

```http
Content-Security-Policy: default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'nonce-<per-response-nonce>'; connect-src 'self'; worker-src 'self'; img-src 'self' blob: data:; media-src 'self' blob:; font-src 'self'
```

Wasm 编译失败提供 `engine` 阶段。Worker 创建或启动失败提供 `worker` 阶段。字体读取或注册失败提供 `font` 阶段。`DocumentError` 提供 `code`、`stage`、`resource` 和 `cause`。`resource` 为引擎或 Worker 的 URL、字体 URL，或注册时的字体标识。Worker 构造器抛出的 `DOMException` 保留异常名称，并附带同样的阶段、资源和原因。加载失败后可重试，已取消的调用继续返回其原取消原因。

### React integration

Import the editor from its format's `react` entry. Pass `document` and `resources` at mount. Keep the component mounted when changing the toolbar, theme, locale or mode. Use `onReady` to receive the instance and call `open(document)` to replace a file with the normal save and discard prompt. Unmounting releases the instance. Call `close()` before unmounting when the user should be offered the save prompt.

Use `slots.toolbar`, `navigation`, `properties`, `status` and `actions` to compose the shell. An omitted slot uses the default, a function renders the host's content, and `null` hides it. Use `EditorCommandButton` inside a slot or give it the instance's `commands` outside the editor. Save, undo, redo and copy are shared across formats. DOCX, XLSX and PPTX also expose `bold`, `italic`, `underline` and `strike`. The Save button, File menu and save shortcut use the same command.

`commands.getSnapshot(id)` returns the command state, including pressed, mixed and disabled states. Use `captureTarget()` before opening host controls that act on the current selection. Pass the returned target to `execute(id, target)`. Text format commands check it again in the edit queue before writing, so an earlier queued selection change invalidates the action. An instance in `view` mode guards changes at the browser command boundary. Complete any active draft, composition or gesture before switching modes.

Import `EditorFontControls` from `@open-document/ui` to reuse the font family selector and point-size field. Pass the current selection's family and size, the font profile, and the format's size limits. Use `null` for mixed values. The family selector includes the current family and the named base entries in the profile. The `apply(change, target)` callback receives a family or size change and the captured target. Use `commands.assertTarget(target)` inside the format method's queued verification callback before applying the change.

Use `EditorPanel` in a properties slot for the same panel frame, initial focus and Escape behavior as the default editor. Its `close` callback owns visibility and can call the slot's `focus()` to return to the document. `EditorColorPalette` and `EditorTablePicker` use the slot's `portal` for instance-local popups. Both capture a command target when the popup opens. Use `commands.assertTarget(target)` inside the queued format or insert callback. The palette accepts six RGB hex digits and uses `null` for mixed colors. The table picker uses an 8×8 grid with pointer and keyboard input. `EditorSymbolPicker` opens a symbol grid from a ribbon trigger, closes on choice and calls `insert(symbol)`; return focus to the document inside that callback. Pass `iconOnly` to `EditorCommandButton` for frequent toggles; the label stays the accessible name and tooltip. `AccentIcon` renders the decorative multi-shade icons used for format badges and notices, tinted by the CSS `color` of its container. Pass `icon` to `EditorPanel` and `EditorToolbarGroup` to title a panel or panel section. Inside a panel, unclassed sections, fieldsets and forms lay fields out on full rows and wrap actions inline; a heading that repeats the panel title is kept for assistive technology only.

Set the `--od-editor-*` CSS properties on the editor host or an ancestor. The supported color suffixes are `surface`, `subtle`, `workspace`, `ink`, `muted`, `line`, `hover`, `accent`, and `danger`. Use `radius` for button corners, `font-size` for UI text size, and `density` for control spacing. The defaults are `13px` for text and `1` for density. Density is limited to `0.8`–`1.25`. The active light or dark theme supplies values for properties the host leaves unset. These settings apply to the shell and its popups, with document zoom controlled independently. Shell motion stays under 250 ms and collapses to instant changes when the user enables reduced motion.

```css
.editor {
  --od-editor-accent: #0f766e;
  --od-editor-font-size: 15px;
  --od-editor-density: 1.2;
}
```

After building the example and starting the static server above, open `http://127.0.0.1:4174/react.html` in Chrome and choose **Open sample**. The example mounts the editor in React Strict Mode and shares bold between the editor and an external host control. Choose **Custom toolbar** and **Formatting panel** to open the host panel and apply text color. Toggle **Spacious UI** to apply host CSS settings to the mounted editor. **Close editor** runs the normal save prompt before React unmounts the editor. Open the sample again to create a fresh session. [React example](../../examples/web-sdk/react.tsx)

XLSX 的 `XlsxSession` 与 `XlsxClient` 统一使用 `execute(command)`。命令联合类型和返回类型从 core 的无状态处理函数推导，Worker 直接转发。连接使用 `{ id, command }` 区分请求编号与原生对象身份。宿主的查找组合流程位于 `SpreadsheetEditor.search`，共享既有草稿和编辑屏障。

XLSX 视口的单元格以紧凑数组穿过 Wasm 和 Worker。直接会话和浏览器 Client 交付相同的 `XlsxViewport` 字段。

`SpreadsheetEditor` 不再继承 Objects、Clipboard 和 Data 转发类。`objects/clipboard/data/search` 使用函数模块，读取 Editor 的当前状态并复用其 `read/change` 屏障；异步操作执行前继续提交已接受草稿。通用宿主的 `copy()` 委托同一剪贴板操作，验证警告开关仍归 Editor。

DOCX 的 `FoundationSession` 与 `FoundationClient` 使用同一模式。Session 保留修订记录状态和 UTC 时间；Client 在粘贴事务前准备平台图片。样式、主题、列表与格式刷位于 `DocumentEditor.formatting`，使用原宿主的输入分组、队列与历史事务。

`DocumentEditor` 已合并五个基类。审阅、来源、页面、对象、表格、剪贴板和查找归各自的函数模块；文字/段落格式与超链接也归 `formatting`。这些模块复用 `DocumentHost` 的读取、编辑、快照、布局和选区入口。审阅模块保留批注焦点，对象模块保留画笔设置；保存与导出继续由 Editor 的原有队列屏障生成结果。

四格式的 Canvas 共用 `CanvasSurface` 管理图片别名、位图、像素和颜色平面。宿主负责解码与原生资源注册，Surface 负责去重、裁剪与释放，并拒绝关闭后的异步资源入库。

字体由宿主显式提供。`addFont` 使用有界八位字符串进入各格式 ABI。单次输入上限由核心 `inputLimits` 提供，Session 缓存结果，Worker 初始化时带回连接。编码与结构化克隆前共用 `checkFontInput`。累计字体预算由核心字体库检查，见[共享格式合同](formats/shared.md)。ABI 4 将请求 JSON 与最多两个八位字符串分开传入 Wasm，核心按操作检查字节上限。响应 JSON 携带本次调用的输出槽位，宿主读取八位字符串后释放槽位。Wasm 和 Worker 各保留上一批绘制轮廓，重复路径只传键，SDK 交付完整绘制批次。错误类型归 wasm 基础层。Renderer 位于 `@open-document/web-core/drawing`，绘制合同位于 `@open-document/wasm/abi/drawing`。

PPTX 查询还返回导入文件、图片/海报、媒体及 RGBA 注册限额。数值归原生格式与图像模块；Session、Client、媒体准备和六处文件选择入口复用它们。共享 `WasmSession/OfficeSession/Connection` 用限额类型参数保留格式字段；共同字体检查保持。PPTX 的命令输入检查归 `checkPptxInput`，具体接口见[PPTX 合同](formats/pptx-editing.md#pptx)。

DOCX、XLSX、PDF 的 Session 与 Client 也返回各自的输入限额；Editor 的 `inputLimits` 字段复用初始化结果。`checkDocxByteInput/checkXlsxByteInput/checkPdfByteInput` 与共享 `checkByteInput` 在编码或结构化克隆前执行。既有图片和 PDF 文件选择入口在读取文件前使用同一查询。具体字段与累计预算的区别归[共享格式合同](formats/shared.md#输入字节限额)。

PDF 的全部 67 项公开命令与内部 `inputLimits` 已使用类型化请求及私有查找表分发。创建、打开与预算查询使用独立的生命周期表；候选会话查询成功后才关闭旧会话。非负整数、有限数和显式字体配置分别使用 bridge 共有的 `RequestInt/RequestNumber/RequestProfile`，保留原边界检查。固定工具链的默认整数解码会截断小数，默认 Double 解码接受字符串 `"NaN"`，不能直接用于这些输入。结构解码失败仍返回 `invalid-operation`、空 `part` 和 `offset=-1`；消息提供字段路径和解码原因。缺失显式预算仍返回 `invalid-budget`。会话准入先于解码，模型错误沿原错误封装返回。

XLSX 的全部 71 个顶层 ABI 入口已采用类型化解码和查表分发：62 项已打开会话操作、4 项保留特殊准入的分析操作、5 项生命周期和查询。原有会话准入、精确字段、列表与资源限额保持。Office 归档预算使用共有的 `RequestArchiveBudget`，保留七个严格整数字段与显式预算要求。透视表、分列、去重、合并计算、小计和排序的设置也使用类型化解码。打印响应使用 `derive(ToJson)`。

DOCX/PPTX 的创建和打开、PDF 转 Office 也复用该归档预算解码，已删除重复结构及字段映射。PDF 自身的 `PdfBudget` 继续由 PDF 核心定义。

PPTX 的 45 个顶层入口已采用类型化请求和查表分发。导入索引与对象身份保留各自的错误代码，图片缓存保留编辑页和放映页所需的资源。幻灯片和对象编辑的复杂字段仍由现有领域解析器处理。

DOCX 的 125 个顶层入口已迁移到查表分发。位置、选区、输入分组和输入法标识使用类型化字段。布局响应采用 `derive(ToJson)`，图片准备、修订失效和过期布局拒绝沿用原规则。页码、格式和表格等复杂内容由现有领域解析器处理。

共享 Worker 转移保存、导出和 PDF 提取、拆分、转换所返回的完整文件缓冲区。结果仍为原有字节数组及元数据。局部视图、共享缓冲区和图片资源查询沿用结构化克隆。

核心在绘制批次中标出图片裁剪框和可见交集，PPTX 放映媒体重写资源键时保留这两个字段。渐变裁剪保留指令索引，并携带轴向端点及变换顺序。Canvas 使用当前设备变换完成采样与像素对齐。

必填可空字段使用私有解码器，接受标量或 `null`，拒绝缺失字段。固定工具链的 `Option::from_json` 使用单元素数组表示非空值，不能直接用于现有可空标量协议；派生结构的直接可选字段接受标量或缺失，已用固定工具链检查。

页面列表、拆分组与拆分区域各自先检查 1024 项上限，再解码内容；画笔、表单选项、控件与脱敏区域保留各自的 4096 项上限，坐标数组最多 32768 项。脱敏仍区分修订参数错误与 `invalid-selection`。表单 `value/defaultValue` 必须出现，但可为 `null`；图片替换标识、图片 `size` 与打开密码区分缺失和 `null`。渲染缺失的 `activate/reuse` 分别补为 `true/false`。导入和 RGBA 字节沿原有有界字节入口。渲染直接返回核心缓存的编码字符串；其他表项各序列化一次 JSON，外层统一补成功或错误封装。转换与脱敏结果使用 `derive(ToJson)`，转换的空字节结果保留显式 `null`。Office 命令仍在迁移，原手工字段函数仅保留给现有调用者。

## 默认 Web UI

容器需要可测量的高度。格式由 React 入口确定，options 不再传 `format`：

```js
import { loadEngine } from "@open-document/wasm";
import { engineBuildId } from "@open-document/wasm/engine-source";

const engine = await loadEngine({
  url: new URL("/assets/engine.wasm", location.href),
  build: engineBuildId,
});
const { mountEditor } = await import("@open-document/docx/react");
const mounted = await mountEditor(container, {
  document: { name: "example.docx", bytes: docxBytes },
  resources: { engine, workerUrl, fonts, profile },
  locale: "zh-CN",
  onSave: persistDocument,
});
```

URL、字体、profile、容器和保存回调由宿主供应。四种格式入口支持 `{ name, blank: true }` 和挂载后的 `create({ name })`；PDF 核心直接创建空白页树。`core`/`web` 可独立接入，自定义 UI 复用已有编辑器队列。

`mountEditor` 追加实例自己的 open ShadowRoot，不替换宿主 DOM。领域包拥有文件准备、面板和输出动作；共用外壳处理候选替换、保存回调、确认与释放。输入、组合、拖拽和保存屏障仍归编辑宿主。`onSave` 成功后只确认该输出的 revision，浏览器下载不表示宿主已持久化。`close()` 保留未保存和草稿确认，`dispose()` 等待已接受工作后释放。具体合同见[默认 UI 与编辑宿主](formats/shared.md#默认-ui-与编辑宿主)。

Tailwind 在构建时扫描共用控件及领域面板，省略 Preflight。生成的 CSS 作为 ESM 字符串进入实例样式。Base UI Portal 和 `styleNonce` 归实例。标题栏的 Settings 菜单切换当前编辑器的界面主题和语言，宿主可用 `setTheme` 与 `setLocale` 切换同一状态。主题只作用于界面。

普通 JS 示例见 [`examples/web-sdk`](../../examples/web-sdk/app.js)。示例按扩展名动态导入领域 React 入口，共用一个 Loader；四个 Worker 使用各自资源地址。

## 命令与开发预览

使用 `moon-toolchain` 固定的 Moon CLI 0.1.20261104 和 `.bun-version` 固定的 Bun 1.4.2。对应的官方稳定归档版本为 `0.10.20+65efd5b93`。运行 `moon version --all` 核对 CLI 和编译器。升级后使用 `bun run format` 和 `bun run api` 更新源文件格式和生成接口。

```sh
bun install --frozen-lockfile
bun run build
bun run check
bun run api
bun run preview
```

`build` 先准备固定依赖并编译 MoonBit。随后 `tools/build-packages.mbtx` 分发 Wasm、构建公共层和领域层、打包各格式 Worker 并生成声明文件。领域 ESM 保留对共享包的外部导入。普通 JS 示例由 `tools/build-example.mbtx` 生成分块产物。公开构建独立于 `test-lab`。首次构建后执行 TS 检查，发布入口的类型解析到生成的 `.d.ts`。

`tools/prepare-dependencies.mbtx` 按[补丁清单](../../tools/harfbuzz-patches/index.json)核对固定上游源码及修改后 SHA-256；未知源码失败。依赖与补丁依据归[依赖记录](dependencies.md)。直接运行 Moon 命令前也执行此准备步骤。

Chrome 打开 `http://127.0.0.1:4173/`。中央按钮选择文件后全屏打开；文件菜单通过宿主回调选择文件。关闭后回到中央按钮。同格式候选失败保留旧文档，跨格式切换保留原确认。

Vite 直接加载领域及公共 TS 源码，dedupe 共享包与 React。构建身份随 Wasm 更新；修改 MoonBit 后先运行 `bun run build`，再重新打开文档。UI Fast Refresh 和样式更新保留已挂载会话。修改挂载适配器或 Worker 后重新打开文件。

DEV 宿主动态导入 `@open-document/devtools` 并调用 `setupDevTools(editor)`，替换或关闭时清理。面板只依赖 `getSnapshot`/`subscribe` 合同。产品包不引用它，生产 Vite 构建排除 DEV 分支。生产预览命令为 `bun node_modules/vite/bin/vite.js build --config examples/dev/vite.config.ts`。

本地消费可分别执行七个包的 `bun pm pack`。消费项目将共享包的 dependencies/overrides 指向同一份本地产物，领域包不再内嵌 Loader。直接加载原生浏览器 ESM 时，import map 的公开子路径和相对 `.js` 导入应指向相同的规范 URL；Worker 已独立 bundle。

检查按[测试说明](testing.md)选择相关用例，不因目录迁移重跑全量格式语料或性能矩阵。
