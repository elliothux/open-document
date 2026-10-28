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

一个 Bun workspace 管理 `packages/*`，公开依赖由根 `bun.lock` 固定。领域包对 wasm/web-core 使用精确版本；React、React DOM 和公共 UI 是领域 React 入口的可选 peer。消费 React 入口时显式安装这些固定版本。`core`、`web` 不需要 React。

## 公开入口与共享加载

四个领域包提供 `core`、`web`、`react`、`worker` 子路径：

| 入口 | 内容 |
| --- | --- |
| `@open-document/<format>/core` | 格式类型、校验和同步会话；`openDocx`、`openXlsx`、`openPptx` 或 `openPdf` |
| `@open-document/<format>/web` | Client 与框架无关的编辑宿主 |
| `@open-document/<format>/react` | 本格式的 `mountEditor`、options 与产品 UI |
| `@open-document/<format>/worker` | 本格式的独立 Worker 资源 |
| `@open-document/wasm` | `loadEngine`、不透明 `EngineHandle` 与公共错误 |
| `@open-document/wasm/engine.wasm` | 唯一分发二进制 |
| `@open-document/wasm/engine-source` | 与二进制一起生成的 `engineBuildId` |

`loadEngine({ url, build }, signal?)` 接受绝对 URL 和构建身份。相同身份合并在途获取/编译，失败后显式调用可重试。缓存只保留当前条目；旧请求完成不覆盖新构建。取消只结束当前等待者，不取消其他调用方的共享加载。

句柄持有编译结果，不持有文档状态。各 Client 把同一 `WebAssembly.Module` 结构化克隆到自己的 Worker，不加入 transfer 列表。Worker 各建独立 Instance 与会话，不再接收 Wasm 字节或重新编译。关闭文档释放自己的 Worker 和资源，编译结果仍可复用。共享范围限同一页面显式供应句柄的调用方。

低层同步调用使用 `openDocx(engine)` 等格式工厂；浏览器使用 `FoundationClient.open(engine, workerUrl, signal?)`、`XlsxClient.open`、`PptxClient.open` 或 `PdfClient.open`。DOCX 的 `FoundationSession`/`FoundationClient` 名称仅表示 DOCX 绑定。每会话只拥有一种格式，公共连接通过类型参数接受该格式协议。

字体仍由宿主显式提供。`addFont` 使用有界八位字符串进入各格式 ABI；Office 文档字节沿既有 JSON/Base64 路径传递。错误构造函数统一归 wasm 基础层。Renderer 位于 `@open-document/web-core/drawing`，绘制合同位于 `@open-document/wasm/abi/drawing`。

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

URL、字体、profile、容器和保存回调由宿主供应。Office 入口支持 `{ name, blank: true }` 和挂载后的 `create({ name })`；PDF 入口要求文件字节。`core`/`web` 可独立接入，自定义 UI 复用已有编辑器队列。

`mountEditor` 追加实例自己的 open ShadowRoot，不替换宿主 DOM。领域包拥有文件准备、面板和输出动作；共用外壳处理候选替换、保存回调、确认与释放。输入、组合、拖拽和保存屏障仍归编辑宿主。`onSave` 成功后只确认该输出的 revision，浏览器下载不表示宿主已持久化。`close()` 保留未保存和草稿确认，`dispose()` 等待已接受工作后释放。具体合同见[默认 UI 与编辑宿主](formats.md#默认-ui-与编辑宿主)。

Tailwind 在构建时扫描共用控件及领域面板，省略 Preflight。生成的 CSS 作为 ESM 字符串进入实例样式；Base UI Portal 和 `styleNonce` 归实例。主题不改变文档颜色。

普通 JS 示例见 [`examples/web-sdk`](../../examples/web-sdk/app.js)。示例按扩展名动态导入领域 React 入口，共用一个 Loader；四个 Worker 使用各自资源地址。

## 命令与开发预览

使用 `moon-toolchain` 固定的 MoonBit 0.1.20261023 和 `.bun-version` 固定的 Bun 1.4.2。MoonBit 升级后，用 `bun run format` 和 `bun run api` 同步官方格式及生成接口：

```sh
bun install --frozen-lockfile
bun run build
bun run check
bun run api
bun run preview
```

`build` 先准备固定依赖并编译 MoonBit，再由 `tools/build-packages.mbtx` 分发唯一 Wasm、生成 SHA-256 构建身份、构建公共层和领域层、分别 bundle Worker，并生成声明文件。领域 ESM 保留对共享包的外部导入；普通 JS 示例由 `tools/build-example.mbtx` 生成分块产物。公开构建不依赖 `test-lab`。首次构建后执行 TS 检查；发布入口的类型解析到生成的 `.d.ts`。

`tools/prepare-dependencies.mbtx` 按[补丁清单](../../tools/harfbuzz-patches/index.json)核对固定上游源码及修改后 SHA-256；未知源码失败。依赖与补丁依据归[依赖记录](dependencies.md)。直接运行 Moon 命令前也执行此准备步骤。

Chrome 打开 `http://127.0.0.1:4173/`。中央按钮选择文件后全屏打开；文件菜单通过宿主回调选择文件。关闭后回到中央按钮。同格式候选失败保留旧文档，跨格式切换保留原确认。

Vite 直接加载领域及公共 TS 源码，dedupe 共享包与 React。构建身份随 Wasm 更新；修改 MoonBit 后先运行 `bun run build`，再重新打开文档。UI Fast Refresh 和样式更新保留已挂载会话。修改挂载适配器或 Worker 后重新打开文件。

DEV 宿主动态导入 `@open-document/devtools` 并调用 `setupDevTools(editor)`，替换或关闭时清理。面板只依赖 `getSnapshot`/`subscribe` 合同。产品包不引用它，生产 Vite 构建排除 DEV 分支。生产预览命令为 `bun node_modules/vite/bin/vite.js build --config examples/dev/vite.config.ts`。

本地消费可分别执行七个包的 `bun pm pack`。消费项目将共享包的 dependencies/overrides 指向同一份本地产物，领域包不再内嵌 Loader。直接加载原生浏览器 ESM 时，import map 的公开子路径和相对 `.js` 导入应指向相同的规范 URL；Worker 已独立 bundle。

检查按[测试说明](testing.md)选择相关用例，不因目录迁移重跑全量格式语料或性能矩阵。
