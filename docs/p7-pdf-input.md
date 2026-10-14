# P7 PDF 输入、预览与文字查询

状态：`planned`，2026-10-14。[P6](implemented/p6-pptx-editing.md) 已完成；本文细化下一阶段，不声明 PDF reader 已交付。阶段关系归[路线图](references/roadmap.md)，后续写回归 [P8](p8-pdf-operations.md)。

## 用户结果与范围

用户可以打开本地 PDF、切页和缩放，选择并复制页内文字，提取文字和逐页搜索。核心返回页面、文字与定位结果；Web 提供可嵌入的只读视图。文件始终留在本地，只覆盖 Chrome/Chromium。

| 能力 | 首版范围与边界 |
| --- | --- |
| 文件结构 | 未加密 PDF 1.0–1.7；传统 xref、xref stream、object stream、混合引用及增量更新链，读取最新声明的修订；结构错误明确失败，不回退旧版本或自动修复 |
| 流解码 | 无过滤流、FlateDecode 与合法 TIFF/PNG Predictor；DCTDecode 仅用于下述范围内的 JPEG 图片。其他过滤器及组合明确诊断 |
| 页面 | 页树、继承资源、MediaBox/CropBox、90° 倍数 Rotate 和有界 UserUnit；按原页序查看，不重新分页 |
| 路径与图形状态 | 直线、矩形、三次曲线、填充/描边、两种填充规则、线端/连接/虚线、仿射变换及路径裁剪；DeviceGray/DeviceRGB、普通混合和常量透明度 |
| 文字显示 | 嵌入 glyf TrueType；简单字体常见编码与 Differences、Type0/CIDFontType2 的 Identity-H、CIDToGIDMap；支持填充文字与不可见文字层，保持 PDF 原始字距和变换 |
| 图片与复用内容 | JPEG，以及 Flate 解码的 8-bit Gray/RGB 图片和同尺寸灰度 SMask；有界 Form XObject，解析其 Matrix/BBox/Resources；首版不支持 inline image |
| 既有批注与表单显示 | 显示可支持的 normal appearance（`/AP /N`），按状态选择并应用 BBox/Matrix；尊重隐藏标志。缺少或不能解释外观时列出诊断，不伪装为完整页面 |
| 文字查询 | ActualText、ToUnicode 和可确定的编码映射；页内选择/复制、按页提取、区分大小写的字面搜索与定位 |

未嵌入字体只使用调用方明确提供的替代字体。核心按 PDF 宽度和位置绘制，并标记字体替代；不让浏览器自行选字或重排。缺少可靠字形映射时，该段显示能力受限，但独立的 Unicode 提取仍可用。

本阶段不做 OCR、正文编辑、保存改写、密码解密或签名验证。CFF/Type1/Type3、竖排 CMap、文字描边/文字裁剪、CMYK/ICC/专色、渐变/图案、透明组/非普通混合、复杂蒙版、JPX/JBIG2/CCITT、可选内容层和 PDF 2.0 暂不纳入正向显示范围。依赖能够解析某个对象，不等于 SDK 已支持其显示。

每页分别报告结构、显示和文字可用性。损坏的文件结构拒绝打开；页面内容不支持时保留页号、尺寸和原因，其他页仍可访问。只有已知影响范围时才显示局部占位；无法判断裁剪、遮挡或图形状态影响时，整页显示为不可完整预览。图片页可以完整显示且没有可提取文字，两种状态独立。

## 现有基础与实际缺口

| 当前代码 | P7 的使用方式 |
| --- | --- |
| `modules/formats/src/pdf/` | 当前仅封装 Office 布局到 PDF 的 writer；在同包增加读取、内容解释、文字查询与会话，保留输出入口 |
| 固定 `moonbitlang/pdflite` 0.3.8 | 已有严格 reader、对象/流、页树、内容操作符、字体/CMap 和文字矩阵；优先直接复用，不再写一套 PDF 语法解析器 |
| `modules/layout/src/drawing.mbt`、`positioned.mbt`、字体轮廓与图片资源 | 复用定位绘制、路径、矩阵与资源身份；补齐 PDF 已证明需要的通用绘制属性 |
| `packages/wasm`、`packages/web` | 复用会话 ABI、Worker、`CanvasSurface`、`CanvasRenderer`、图片解码、下载与释放；增加 PDF 类型和视图 |

已核对依赖源码：`pdf_read_classic_document_from_view` 虽带 classic 名称，也处理 xref stream、object stream 和 `/Prev`，且不进入修复扫描。高层 `pdf_read_document_from_view` 会自动重建损坏引用，P7 不使用这个策略。

依赖没有项目级的统一读取预算。默认 Flate 解码上限为 1 GiB，内容入口还会先解码并合并流。P7 必须在分配和循环前接入预算；调用结束后计数不足以保护不可信输入。沿[依赖准备机制](references/dependencies.md)补最窄的读取/解码预算入口，记录固定源码与许可，不另建 parser，也不把研究 checkout 加入构建。

依赖的 `codepoints_of_text` 在部分 ToUnicode 缺项时会返回原字符码。SDK 不把这种回退当作有效 Unicode；复用映射解析，保留“已映射/未知”的区别，避免产生错误搜索命中。

## 核心数据流与绘制

```text
PDF 字节 → 有界 reader → 原始对象图、页树与源身份
                           ├→ 内容解释 → 定位绘制批次 → 平台 Renderer
                           └→ 字符映射与几何 → 提取、搜索、选择、语义
```

MoonBit 拥有对象图、流解码、资源解析、内容状态机、字体映射及文字几何。会话保留原始字节和对象号/代数；解析缓存与源对象分开，查询不得把解码流写回源对象。页身份绑定源页对象，不用会变化的显示页码作身份。[P8](p8-pdf-operations.md) 在同一会话上增加编辑，不另建一份可编辑模型。

PDF 已经定位，不能走 DOCX/PPTX 的换行、塑形或分页。读取 `Tj/TJ`、字距、水平缩放、文字矩阵及 CTM 后，直接把字符码映射到 glyph，使用现有字体轮廓接口。Unicode 仅用于语义，不能先提取字符串再重新 shape 成画面。

核心合并 CropBox、Rotate、UserUnit 与坐标轴翻转，统一输出左上原点的 point 坐标，并保留到原 PDF 坐标的逆变换。路径、图片、文字四边形、命中与后续批注共用这个变换。Web 只增加滚动、zoom、DPR；不计算 PDF 页框或 `/QuadPoints`。

内容解释复用 pdflite 操作符和文字状态。在核心维护有界 `q/Q`、当前路径、资源与 Form 调用栈；检测循环引用。按源顺序输出绘制，Form 返回时恢复状态。未知操作符或资源影响可见结果时，给出页/对象/原因，不静默跳过。

### 对 R0 的最小补充

现有 R0 已有有序路径、矩阵和矩形裁剪，尚缺路径裁剪、填充规则、完整描边样式及常量透明度。直接补到共享绘制类型、批次校验、Canvas 执行与 PDF 编码中，调用方显式给出原有默认值。删除被替代的字段表示，不保留新旧协议双路。

PDF 的零宽描边表示设备可呈现的细线。核心保留这一明确语义，由 Renderer 按设备像素执行，PDF 编码继续写入零宽；不能直接设置无效的 Canvas `lineWidth = 0`。

这些字段描述绘图能力，不能包含 PDF 操作符、字体字典或格式分支。PDF 核心可直接生成 `DrawingBatch`，无需硬套 Office 的 `PositionedText`。文字语义仍独立；共享的填充/描边/裁剪样式只保留一套定义。P8 新生成的外观需要序列化时，再复用同一绘制属性。

普通路径透明度由 Renderer 按明确值执行；图片 alpha 复用 RGBA。Flate、Predictor、采样值及 SMask 合成放在核心。JPEG 沿现有宿主解码通路，由核心校验颜色、尺寸和 Decode 范围；Web 只交回已验证尺寸的 RGBA。该平台解码边界继续归[SDK 合同](references/sdk.md)，不声明已实现无浏览器等价输出。

### 文字、搜索与语义

核心为字符区段保留源身份、UTF-16 范围、Unicode 映射来源和页面四边形。ActualText 替换所属 marked-content 的文字，不重复输出底层字符；一个字形对应多个字符时，共享其几何，不伪造不存在的光标位置。缺失映射保留不可搜索的间隔，避免把两侧文字拼成错误命中。

首版按内容流文字顺序提取，同一规则补入可确定的空格与换行，并保留索引到源区段的映射。不承诺复杂多栏、任意 RTL 源顺序或结构树的语义阅读顺序。不可见文字层可以提取，并标注来源；扫描图本身不产生文字。

正文查询覆盖页面 Contents 及其 Form XObject。批注文字和字段值由 P8 的独立列表提供，不把 appearance 再计入正文，避免重复提取。

搜索与复制使用同一份核心文本。首版为逐页、区分大小写的字面匹配，不跨页，不做正则、模糊匹配或 Unicode 规范化。搜索返回源范围、四边形及页面完成状态；不完整提取不能报成“全文无结果”。Web 逐页调度，显示当前进度，取消后停止提交下一页请求；不建设全文索引服务。

Web 复用覆盖层绘制选区与命中结果。可访问文本和页导航使用核心语义，DOM 不反推字序或坐标。提供键盘页导航、搜索结果前后跳转、复制及可达诊断；不声明完整 Tagged PDF 或 PDF/UA 支持。

## 会话、资源与失败恢复

以下是拟新增入口，不是当前 API。`loadEngine(wasm).openPdf()` 创建同步 `PdfSession`，Web 使用 `PdfClient.open(wasm, workerUrl)` 与 `PdfViewer.create()`。沿现有 Worker 连接传输有类型的页面批次，不新建 RPC 或运行时。

| 调用组 | 最小合同 |
| --- | --- |
| `defaultPdfBudget` / `openPdf` / `queryPdf` | 显式预算；成功后替换会话文档，失败保留原文档；返回稳定页身份、尺寸、诊断和各项能力 |
| `renderPdfPage` | 按页生成绘制身份、批次及资源需求；不同时解释整篇页面 |
| `extractPdfText` / `searchPdfPage` | 按页返回文字、来源与定位；结果有大小限制，不静默截断 |
| `hitTestPdf` / `selectPdf` / `selectedPdfText` | 校验当前页面绘制身份；核心生成页内选择和复制结果，不修改文件 |
| `close` / `dispose` | 释放源、对象、派生缓存及宿主资源；旧请求回复不能覆盖新页面或新文档 |

只保留当前展示页所需画布和有界资源，页列表先用页号，不建设缩略图流水线。搜索高亮只更新覆盖层；缩放不重新解析源内容。复用现有资源身份和缓存，关闭时释放。暂不建设瓦片、GPU 后端、OffscreenCanvas、多 Worker 或跨会话缓存。

初始预算作为实现目标写入核心默认值，可收紧，不是性能或堆峰值保证：

| 对象 | 首版上限 |
| --- | --- |
| 输入 / 间接对象 / 对象号 | 64 MiB / 100000 / 1000000；对象号使用稀疏索引，避免按恶意 `/Size` 分配 |
| 页数 / xref 版本链 | 1024 / 128；页树、引用、Form 都检测循环 |
| 对象/页树深度 / Form 与绘制栈 | 64 / 32 |
| 单流解码 / 单次操作累计解码 | 16 MiB / 64 MiB；xref、对象流、内容、字体、图片及 Predictor 输出全部计入 |
| 解码缓存 / 单次操作工作量 | 64 MiB / 10000000 个解析或解释步骤；重试不能重置同一次操作的耗尽状态 |
| 字体、图片、Canvas 与绘制批次 | 沿用[现有预算](references/formats.md#预算)；先检查尺寸、乘积、路径段数和坐标，再分配 |
| 文字 / 搜索 | 单页 262144 UTF-16 单元；查询 1024 单元、每页 10000 命中；超限返回明确状态 |

同步 Wasm 无法抢占。预算必须覆盖解析循环、引用追踪、CMap 范围展开和解码；Worker 终止只是宿主取消手段。拒绝加密、外部流和不支持的解码器；不执行 JavaScript、Launch、OpenAction、表单动作或附件，不发起外链请求。签名文件可只读并显示“未验证”，不能暗示签名有效。

## 实施顺序与影响面

1. 接入严格 reader 和读取预算。用独立 PDF 完成页树、资源与结构诊断，保留源对象身份。
2. 解释当前页图文，补共享绘制缺口。完成切页、缩放、资源释放与受限页面提示。
3. 接入文字映射、页内选择、提取与搜索。完成核心几何、Web 覆盖层和文本语义。
4. 完成功能检查与使用说明。更新实际支持面，再开始 P8 写回。

实现落在 `modules/formats/src/pdf`，通用绘制落在 `modules/layout/src`；按 reader、内容、文字、会话职责拆分，遵守单文件 800 行。桥接增加 PDF 分发；`packages/wasm/src/engine.ts`、类型校验和 exports，`packages/web/src/worker.ts`、协议、PDF client/viewer、构建入口同步更新。只在真实公共差异处修改现有 Office 调用方。

依赖补丁通过现有准备工具生成和核验。私有用例登记输入、许可与独立预期；公开构建不依赖 `test-lab/`。交付时更新[格式](references/formats.md)、[开发](references/development.md)、[依赖](references/dependencies.md)及 R0 的实际结果，不提前把本计划写成支持声明。

## 足够检查与参考依据

以少量功能链覆盖：打开独立图文 PDF → 切页/缩放 → 选择复制 → 搜索定位；另覆盖图片页、无映射文字和受限页面。输入包含固定 ONLYOFFICE 导出，并以 LibreOffice 导出补充；已有 Office writer 产物只作共享路径回归，不能作为唯一正确性依据。

结构检查用 qpdf，文字和选定页面用 Poppler 独立核对。xref/object stream、增量更新、Rotate/CropBox、TJ 字距、ActualText、裁剪与 alpha 合并进上述输入或少量定向例。损坏引用、循环、解码超限、CMap 展开、取消/换文档和关闭补直接风险检查。新增共享绘制属性只重跑受影响的 Office 图文/静态 PDF 功能链。

当前方案只查文档。实现时按[测试说明](references/testing.md)选择必要静态检查、构建与用例；不默认全量 loop、跨浏览器矩阵、性能专项或全 PDF 规范测试集。

机制优先参考 ONLYOFFICE 的[核心输出适配](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/SrcReader/RendererOutputDev.h#L59)与[页面/文字分离接口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/pdf/src/file.js#L159)。其 Web 路径接收核心页面像素；本项目沿已实现 R0 输出定位指令，借用职责分离，不再增加整页光栅化引擎。

依赖能力依据固定 office.mbt 快照中的[严格读取](https://github.com/moonbitlang/office.mbt/blob/2f08f3b8041d9098d258969fe3902b34585163cc/pdflite/pdf_reader_document_classic.mbt)、[文字矩阵用例](https://github.com/moonbitlang/office.mbt/blob/2f08f3b8041d9098d258969fe3902b34585163cc/pdflite/pdf_content_text_test.mbt)与[读写/ToUnicode 用例](https://github.com/moonbitlang/office.mbt/blob/2f08f3b8041d9098d258969fe3902b34585163cc/pdflite/pdf_native_acceptance_cases_test.mbt)。它们是源码依据，不是本项目已通过结果。ONLYOFFICE 的 `PdfToPdf` 测试含 `GTEST_SKIP()`，不能引用为自动通过证据。研究不复制 AGPL 实现，不新增生产引擎依赖。
