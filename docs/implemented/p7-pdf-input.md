# P7 PDF 输入、预览与文字查询

状态：`implemented`，2026-10-14。用户可以在本地打开 PDF、切页、缩放、选择复制、提取文字和逐页搜索。只覆盖 Chrome/Chromium。操作与保存见 [P8](p8-pdf-operations.md)，实际 API 和预算归[格式合同](../references/formats.md#pdf-输入与文档操作)。

## 已交付范围

| 能力 | 当前实现 |
| --- | --- |
| 严格读取 | 未加密 PDF 1.0–1.7；传统 xref、xref/object stream、混合引用及 `/Prev`；读取最新修订，结构错误拒绝，不修复或回退旧修订 |
| 页面 | 页树继承、MediaBox/CropBox、90° 倍数 Rotate、有界 UserUnit；稳定对象号/代数身份，不重新分页 |
| 路径 | 直线、矩形、三次曲线、填充/描边、填充规则、线端/连接/虚线、仿射变换与路径裁剪 |
| 颜色 | DeviceGray/DeviceRGB、常量 alpha、Normal 和高亮所需 Multiply |
| 文字显示 | 嵌入 glyf TrueType；简单编码/Differences、符号字体自身 cmap、Identity-H CIDFontType2/CIDToGIDMap；填充和不可见文字，使用源位置与字距 |
| 图片与复用 | 8-bit Gray/RGB Flate、同尺寸 Gray SMask、限定 JPEG；TIFF/PNG Predictor；Form Matrix/BBox/Resources 与循环保护 |
| 既有外观 | normal `/AP /N`、状态选择、BBox/Matrix 放置及隐藏标志；未知外观给诊断 |
| 文字语义 | ActualText、ToUnicode、可确定的编码；页内选择/复制、按页提取、区分大小写的字面搜索 |

MoonBit 拥有源对象图、内容解释、源字形与几何；TypeScript 只处理 Worker、平台图片解码、Canvas 和事件。复用固定 pdflite 严格 reader，不新增 PDF parser、PDF.js 或整页光栅引擎。通用绘制增加样式和路径裁剪；轮廓身份绑定字体 SHA-256，切页不能混用字形。

`PdfSession`、Worker `PdfClient` 和可嵌入 `PdfViewer` 已接通。viewer 只保留当前页资源，提供可访问文本、诊断、键盘切页、搜索定位及有界意图队列。缩放复用源解析结果。替换文档失败保留旧会话；旧 layout、取消搜索及关闭后的回复不能覆盖当前视图。

缺可靠 Unicode 的范围使用未知标记，不产生假搜索命中，复制含未知范围时明确失败。Unicode 提取与字形显示分别报告完整性。调用方可以显式供应替代字体，核心保留源字距并列出替代诊断。

## 边界与安全

结构损坏拒绝打开。页面不支持时保留尺寸、页身份和原因；已知图片/批注影响可以局部诊断，未知图形状态影响使整页预览不完整。其他页仍可访问。

不执行 JavaScript、Launch、OpenAction、字段动作、附件或外链请求。加密与外部 stream 拒绝。签名只读并显示未验证；非零对象代数可读，但固定 writer 无法安全改写时保护编辑。

不含 OCR、任意正文编辑、密码解密、签名验证或 PDF 2.0。CFF/Type1/Type3、竖排 CMap、文字描边/裁剪、inline image、CMYK/ICC/专色、渐变/图案、透明组、其他混合模式、复杂 mask、JPX/JBIG2/CCITT 和可选内容层不在正向显示范围。JPEG 仅支持 8-bit Gray/RGB 分量、匹配尺寸、无 ICC profile、无 DecodeParms 的 DCT 图片。

读取预算在词法、对象深度、xref、流分配、Flate、Predictor、CMap/CID 范围和内容循环前检查。嵌套操作共享耗尽状态，依赖的错误回退不能重置预算。默认单流 16 MiB、累计解码 64 MiB、100000 个对象、1024 页、10000000 步；完整上限归[格式合同](../references/formats.md#pdf-输入与文档操作)。这些是工作量与载荷限制，不是堆峰值或延迟保证。同步 Wasm 不能被抢占。

## 足够检查与依据

私有 `cases/p7-p8-pdf.json` 登记五条 Chromium 功能链、固定输入和输出证据。P7 链覆盖严格读取、xref/object stream、最新增量修订、源字距、ActualText、Rotate/CropBox、选择复制、搜索、换文档及旧 layout 拒绝。独立输入包含固定 ONLYOFFICE 模板和 LibreOffice 导出。

qpdf 检查结构；Poppler 核对文字及 CropBox 页面中的裁剪、alpha、Flate/SMask、Form 和 JPEG 像素。未知映射、受限图片、循环、加密、解码/CMap 超限和失败后源保留并入恢复链。共享字体/绘制和 Office 输出只运行直接受影响的功能用例。

未运行完整 loop、性能专项、其他浏览器、Windows/Word、VoiceOver 或新增系统输入法验收。固定样本通过不代表完整 PDF 规范兼容。

实现依据为固定 pdflite [严格读取](https://github.com/moonbitlang/office.mbt/blob/2f08f3b8041d9098d258969fe3902b34585163cc/pdflite/pdf_reader_document_classic.mbt)与[源文字矩阵](https://github.com/moonbitlang/office.mbt/blob/2f08f3b8041d9098d258969fe3902b34585163cc/pdflite/pdf_content_text_test.mbt)，职责参考 ONLYOFFICE [页面/文字接口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/pdf/src/file.js#L159)。本地补丁与许可证归[依赖记录](../references/dependencies.md#pdflite-输入预算与源映射补丁)。引用不代表上游测试已通过，不复制 AGPL 实现。
