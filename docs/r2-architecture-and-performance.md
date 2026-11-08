# R2 架构精简、核心下沉与性能重构

状态：`planned`，2026-11-02。本方案基于 [R0 通用渲染架构](implemented/r0-renderer-foundation.md)与 [R1 领域拆包与共享 Wasm 加载](implemented/r1-domain-packages-shared-wasm.md)，在不改变公开功能与文档格式兼容性的前提下，清理多层重复校验与转发胶水，将平台耦合的几何特判与图像预处理收归 MoonBit 核心，并消除 Wasm 边界与排版/计算热路径的性能瓶颈。职责边界归 [SDK 合同](references/sdk.md)，模块归属归[开发说明](references/development.md)。

## 用户结果与范围

1. **核心边界纯净化**：文档解析、图像头部校验、排版几何、像素对齐策略与绘制批次生成全部留在 MoonBit/Wasm。TypeScript 仅保留平台事件、Worker 通信、资源句柄与薄 Canvas 执行，便于直接嵌入非浏览器宿主。
2. **代码与协议瘦身**：消除 TS 对 Wasm 输出的冗余校验与 6–7 层无状态继承链；四格式统一采用单一 `execute(command)` 命令分发与共享宿主任务队列。
3. **传输与执行提速**：文件字节、字体与图像像素跨 ABI 和 Worker 边界采用 `Uint8Array` 与 `Transferable` 传输，移除 Base64 与单字节字符串转换；字形轮廓增量下发；修复 DOCX 段落缓存序列化、多节分页缓存及 XLSX 公式依赖扫描的复杂度瓶颈。
4. **单格式按需体积**：除全格式 `engine.wasm` 外，提供按格式拆分的 Wasm 编译产物，避免单格式接入触及浏览器主线程 8 MiB 限制。

## 分批实施计划

按依赖关系分为五个独立可验证批次。`R2.1–R2.3` 先于大规模兼容扩充执行，避免在旧胶水层上继续堆叠代码；`R2.4–R2.5` 与 [C1 语料扩展](c1-corpus-and-producer-compatibility.md)配合验证。

| 批次 | 用户与工程结果 | 涉及模块与文件 | 足够检查 |
| --- | --- | --- | --- |
| R2.1 输出校验瘦身与统一命令分发 | 移除 TS 对 Wasm 输出的二次全量校验；拍平 DOCX/XLSX 多层伪继承链；统一四格式宿主任务队列 | `packages/wasm/src/abi/drawing.ts`、`packages/*/src/core/`、`packages/*/src/worker/`、`packages/*/src/web/`、`packages/web-core/` | `bun run check`、公开 API 类型检查、四格式单元与现有 Worker/编辑闭环用例通过 |
| R2.2 边界二进制直通与增量资源传输 | 文件、字体、图片像素改用 `Uint8Array` 直通与 Worker `Transferable`；字形轮廓增量下发；剥离生产 `save()` 的整包重解析自检 | `modules/bridge/src/`、`modules/core/src/opc/package.mbt`、`modules/layout/src/`、`packages/wasm/src/abi/session.ts`、`packages/web-core/src/connection.ts` | 字体加载、大文件打开/保存、图片传输与轮廓缓存复用的核心与浏览器定向检查通过；记录同输入前后耗时与内存 |
| R2.3 渲染特判与图像预处理下沉 MoonBit | 移除 `pdf-pixels.ts` 与 `drawing.ts` 指令流偷看；图片头宽高解析、DOCX 图片依赖收集与 PPTX 片段预检下沉 MoonBit | `modules/layout/src/drawing.mbt`、`modules/formats/src/`、`packages/web-core/src/drawing.ts`、`packages/web-core/src/image.ts`、`packages/*/src/web/*-canvas.ts` | C0 既有 Canvas/PDF 像素对照保持通过；删除 `pdf-pixels.ts` 后 `CanvasRenderer` 无格式分支 |
| R2.4 排版缓存与表格计算热点优化 | DOCX 段落缓存 O(1) 键、多节分页缓存与选区单次查询；XLSX 强类型 `Address` 依赖图、空间索引与条件格式缓存 | `modules/layout/src/paragraph-cache.mbt`、`pagination.mbt`、`modules/formats/src/docx/`、`modules/formats/src/xlsx/calculation.mbt`、`grid-bands.mbt` | P14 性能基线与 C0 复杂文档/工作簿重算、分页、撤销重做及保存检查通过；对比优化前后中位数耗时 |
| R2.5 单格式 Wasm 拆分构建 | 支持按 `docx`、`xlsx`、`pptx`、`pdf` 生成独立 Wasm 产物，保留共享 `loadEngine` 合同与全量包 | `modules/bridge/src/`、`tools/build-packages.mbtx`、`packages/wasm/`、`packages/*/package.json` | 安装包消费检查通过；单格式 Wasm 体积与导出表核验通过；独立加载与多格式共存验证通过 |

---

## R2.1 输出校验瘦身与统一命令分发

### 1. 移除 TS 侧对受信任 Wasm 输出的重复校验

MoonBit `modules/bridge` 已在入口处完成请求参数、预算与状态校验，内部模型受严格类型约束。TS 侧不再对 Wasm 返回的 JSON 结果做二次递归校验：

- **绘制批次**：删除 [`packages/wasm/src/abi/drawing.ts`](../packages/wasm/src/abi/drawing.ts) 中 `drawingBatch()`、`drawingMatrix()`、`checkGradientStops()` 的 250 行运行时遍历、正则匹配与矩阵求逆计算。保留 TS 接口定义，核心在生成 `DrawingBatch` 时保证矩阵可逆与色标有序。
- **格式查询结果**：精简 [`packages/pptx/src/core/pptx.ts`](../packages/pptx/src/core/pptx.ts) 的 `pptxQuery()` / `pptxResult()`、[`packages/pdf/src/core/pdf.ts`](../packages/pdf/src/core/pdf.ts) 的 `pdfResult()`、[`packages/docx/src/core/foundation.ts`](../packages/docx/src/core/foundation.ts) 的 `docxQuery()` 以及 XLSX 对应结果校验器。仅保留外部调用方传入参数的必要前置检查与错误映射。

### 2. 拍平 DOCX 与 XLSX 的多层伪继承链

消除为迁就行数上限而拆出的无状态继承链：

- **DOCX**：将 `FoundationReviewSession` → `FoundationPageSession` → `FoundationClipboardSession` → `FoundationMathSession` → `FoundationInkSession` → `FoundationSelectionSession` → `FoundationSession` 收敛为单一 `DocxSession`（保留 `FoundationSession` 导出名直至调用方同步更新），模仿 `PptxSession.execute(command)` 按类型化 `DocxCommand` 联合类型分发。对应 `FoundationClient` 与 [`packages/docx/src/worker/index.ts`](../packages/docx/src/worker/index.ts) 的 480 行 `switch` 简化为直接转发 `execute(request)`。
- **XLSX**：将 `XlsxCommentsSession` → `XlsxDrawingSession` → `XlsxSession` 及对应 `XlsxDataClient` 继承链收敛为单一命令分发；功能域类型与辅助纯函数按文件拆分，不再通过抽象基类串联。

### 3. 提取公共编辑宿主队列与表面资源池

在 `@open-document/web-core` 中提取四格式共用的宿主基础设施：

- **有序命令队列**：将 `DocumentEditor`、`SpreadsheetEditor`、`PresentationEditor`、`PdfOperations` 中重复实现的 `tail: Promise<void>`、`pending`（上限 64）、`generation`、`paused`、`blocked`、`whenIdle()` 与 `dispose()` 抽为通用 `CommandQueue`。
- **表面图片缓存**：将 `PageCanvas`、`SpreadsheetCanvas`、`PresentationCanvas` 中重复的 `keys: Map<string, string>` 与 `images: Map<string, ImageBitmap>` 生命周期管理合并入 [`CanvasSurface`](../packages/web-core/src/canvas-surface.ts)。

---

## R2.2 边界二进制直通与增量资源传输

### 1. 消除 Base64 与单字节字符串编码

当前 `encodeBytes()` / `binaryString()`（[`packages/wasm/src/abi/session.ts`](../packages/wasm/src/abi/session.ts)）将文档字节、32 MiB 字体和 16 MiB RGBA 图像编码为 Base64 或单字节字符串塞入 JSON。改为二进制直通：

- **Wasm ABI 字节通道**：在 `modules/bridge/src/common` 提供共享字节缓冲区或 Host `Uint8Array` 导入读写入口。`open*`、`save*`、`export*`、`addFont`、`image*` 直接传递字节缓冲，不再经过 `@base64.encode` / `@base64.decode` 和 `JSON.stringify`。
- **Worker 零拷贝传输**：在 [`Connection`](../packages/web-core/src/connection.ts) 与 `serveWorker` 中自动收集请求与响应中的 `Uint8Array` / `ArrayBuffer`（或显式标记输出缓冲）加入 `postMessage` 的 `transfer` 列表，消除主线程与 Worker 间的冷拷贝。

### 2. 字形轮廓（Outlines）增量传输

- `TextProbe`（[`modules/layout/src/shape.mbt`](../modules/layout/src/shape.mbt)）按会话记录已导出的字形轮廓序号。
- 每次 `layout` / `viewport` / `renderPdfPage` 仅在 `DrawingBatch.outlines` 中返回本轮新增的 `{ key, path }`；`CanvasRenderer` 持久保有会话内已构建的 `Path2D` 字典，仅在字体变更或会话关闭时清理。

### 3. 剥离生产保存路径的整包重解析自检

- [`modules/core/src/opc/package.mbt`](../modules/core/src/opc/package.mbt) 的 `Package::save()` 当前在写出 ZIP 后立即调用 `Package::open(output)` 解压整包并重解析所有修改过的 XML。
- 将该重开与 XML 重解析提取为独立的 `Package::verify_output()` 测试辅助函数，供测试套件调用；生产 `save()` 仅执行 `validate_changes` 与流式写出，将大文档保存内存峰值与耗时减半。

---

## R2.3 渲染特判与图像预处理下沉 MoonBit

### 1. 移除 `pdf-pixels.ts` 与 `drawing.ts` 中的几何特判

遵守 [R0 合同](implemented/r0-renderer-foundation.md)“Renderer 不做几何与格式决策”的约束：

- 将 [`packages/web-core/src/pdf-pixels.ts`](../packages/web-core/src/pdf-pixels.ts) 中的 `fillStrokeDiamond`（同色不透明菱形外轮廓合并）、`pixelRectangleStroke`（开放/闭合矩形描边对齐）与 `pdfClipPath` 收回 MoonBit `modules/layout` 绘制生成阶段。
- 消除 [`packages/web-core/src/drawing.ts`](../packages/web-core/src/drawing.ts) 中向前偷看 `commands[index + 1]` / `commands[index + 2]` 的 `clipRect + image + restore` 与 `clipPath + gradientRect` 组合猜测；由核心直接生成明确的裁剪或源区域绘制指令。

### 2. 图像头部解析与资源清单收归核心

- **图像头校验下沉**：将 [`packages/web-core/src/image.ts`](../packages/web-core/src/image.ts) 中的 PNG/GIF/JPEG 头部尺寸解析移入 MoonBit `modules/formats/src/internal/image`，在核心接收图像字节时统一完成格式与尺寸预算校验。
- **消除 DOCX 整树拉取**：在 DOCX 核心提供 `imageKeys` 查询（包含正文、表格、页眉页脚、注释、水印与元文件引用的图片标识），替代 [`PageCanvas.prepare`](../packages/docx/src/web/page-canvas.ts) 中先拉取整棵 `DocxFlow` 到 TS 再递归遍历的做法。
- **简化 PDF 图像管线**：对于 PDF 中的常规 JPEG/PNG，复用 MoonBit 图像解码器或直接生成可绘制资源，消除 `PdfCanvas.prepare` 中 `Wasm -> TS decodeImage -> Wasm decodedImagePdf -> TS createImageBitmap` 的三趟往返。

---

## R2.4 排版缓存与表格计算热点优化

### 1. DOCX 排版与交互合并

- **O(1) 段落缓存键**：修改 [`modules/layout/src/paragraph-cache.mbt`](../modules/layout/src/paragraph-cache.mbt) 的 `ParagraphCache::key()`，不再对每个段落执行 `paragraph.to_json().stringify()`。改为在 `Paragraph` 上携带源节点版本号/内容摘要，结合 `(paragraph.id, source_hash, available, profile_id)` 生成轻量键。
- **多节文档分页缓存**：修改 [`modules/layout/src/pagination.mbt`](../modules/layout/src/pagination.mbt)，在 `PagePosition` 中记录当前分节索引与节内页码，移除 `!flow.sectionBreaks.is_empty()` 时清空 `probe.pagination` 的限制。
- **合并选区几何查询**：在 MoonBit 编辑与导航命令返回 `EditState` 时，若提供当前 `layoutId` 则一并返回 `caret`、`selectionGeometry` 与 `formatting`，将 [`DocumentEditor.presentSelection`](../packages/docx/src/web/editor.ts) 的 4 次串行 Worker 调用合并为 1 次。

### 2. XLSX 依赖图与网格绘制优化

- **强类型坐标与空间索引**：修改 [`modules/formats/src/xlsx/calculation.mbt`](../modules/formats/src/xlsx/calculation.mbt)，将公式表与计算值映射的键从 `(Int32, String)` 改为 `(Int32, Address)`（或打包 `Int64`），消除 `Calculation::visit` 和 `affected` 检查中内层循环的 `Address::parse` 调用；为公式位置建立按行列排序的区间索引，将区域依赖匹配从 $O(F)$ 降为对数查找。
- **条件格式规则缓存**：将 `ConditionalRules` 的全表统计（色阶极值、平均值、重复值集合）缓存于 `Session` 当前 `revision`，避免 `query()` 与每次滚动 `paint_grid()` 重复扫描全表单元格。

---

## R2.5 单格式 Wasm 拆分构建

- 在 `modules/bridge/src/` 下除 `all` 外，配置 `docx`、`xlsx`、`pptx`、`pdf` 四个独立 Wasm 导出入口。
- 更新 `tools/build-packages.mbtx` 与 `@open-document/wasm`，支持按格式加载对应的精简 Wasm 模块（如仅使用 PDF 或仅使用 DOCX 时无需加载其余格式核心），同时保留全格式 `engine.wasm` 供多格式切换宿主复用。
- 验证每个单格式优化后 Wasm 远低于 Chromium 8 MiB 同步编译上限。
