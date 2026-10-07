# G0 — Office SDK 底座参考项目研究

研究日期：2026-10-07。状态：`research`。源码调查与局部验证已完成，架构建议仍待决策及 WasmGC 验证；不是实现完成声明，也不替代 [P0 中已确定的选型与目标](p0-sdk-foundation.md)。MoonBit + WasmGC + 薄 TS 保持不变。

本轮新克隆 19 个仓库，检查关键源码、依赖、目标声明、测试和许可证，并对两个 Rust 项目运行聚焦测试。原有 BetterOffice、GenOffice、Univer 继续使用相邻 `lynx-os/references` 中的源码。仓库快照见文末。

## 1. 结论

不建议把 GenOffice、UniOffice、AnyDoc 或 Office Oxide 中任何一个整体翻译成 MoonBit。

如果必须给出一个“底座架构的首要参考”，选择 **Typst 的核心/宿主边界、布局产物与增量计算设计**。但它不提供 OOXML 编辑模型，不能单独作为 Office SDK 蓝图。完整建议如下：

| 我们要解决的问题 | 首要参考 | 实际采用方式 |
| --- | --- | --- |
| Office 编辑器中核心、会话、Worker、视图的分工 | BetterOffice | 保留宏观方向，不复制整套实现 |
| 无 DOM 排版、布局缓存、多输出后端 | Typst | 学习 `World`、布局阶段和 `Frame`；不移植其语言与编译器 |
| OPC、OOXML 类型、未知内容和延迟解析 | Open XML SDK | 学习保真读写；不生成完整 OOXML 类型宇宙 |
| 文本塑形、字形簇、命中测试、选区 | Parley；MoonBit 的 moon_cosmic | Parley 用于设计对照，先验证已有 MoonBit 库 |
| 表格模型、公式语义、编辑事务与撤销 | IronCalc | 学习职责和测试，不假设其计算调度已经适合超大交互表格 |
| XLSX 文件兼容、流式读写与原始部件保留 | Excelize、Calamine | 分别学习写入/兼容规则和读取路径 |
| PDF 输出、字体子集和可验证的导出 | Krilla | 学习布局之后的 PDF 后端，不把 PDF 库当 Office 排版引擎 |
| MoonBit 中可以复用的实现 | flate、Milky2018/xml、moon_cosmic 等 | 小范围接入验证，避免重新实现已有底层算法 |

这是一组阅读与实现参考，不是一组需要同时引入的运行时依赖。P0 不引入 Rust 引擎拼盘，也不为这些参考项目分别建设适配框架。

对 GenOffice 的判断应更具体：其 DOCX 分页和导出带有 DOM/Electron 耦合，表格集成 Univer，因而不适合作为纯计算 SDK 的总体底座；PPTX 的 RenderTree、度量接口和格式处理仍值得研究。不能从“功能多”“文件大”直接推出整个项目代码质量差。

## 2. 判断标准

“优雅、可扩展、高性能”在这里分别落实为：

- 权威状态清楚：一处修改文档，不在 TS、XML DOM、编辑树之间维护三份可独立改变的状态。
- 扩展有边界：新增格式不要求改动 ZIP、字体或宿主；新增输出不要求重写格式解析；具体 Word/Excel/PPT 语义不强行通用化。
- 成本可控：局部编辑尽量不触发全包复制、全量解压、整本文档重排或逐字跨 WASM 边界调用。
- 保存不损坏：保留不认识的内容，明确已修改部件中的未知 XML 如何处理，而不只是保留未打开的文件。
- 能够证明：源文件重开、差分测试、布局快照、失败路径测试与真实浏览器性能，分别验证不同承诺。

本轮没有统一基准，因此下文讨论的是性能机制与风险，不是跨项目速度排名。各项目对“解析成功”“兼容”“转换”的定义也不同，不能直接比较 README 中的百分比。

## 3. 用户列出的五个项目

### 3.1 UniOffice：API 分层值得看，不能作为开放实现底座

可以学习它把 OOXML schema 类型、包关系和高层 `document` / `spreadsheet` / `presentation` 操作分开的方式。对开发者暴露有语义的操作，而不是要求调用者直接拼 XML，这一点符合我们的目标。

但有两个决定性限制：

1. 当前仓库 [LICENSE.md](../references/unioffice/LICENSE.md) 明确标注商业产品和授权要求，不是看到 GitHub 源码就能自由移植。
2. [document/document.go](../references/unioffice/document/document.go) 等实现注明由 `unitwist` 混淆生成。大量混淆标识符和压缩代码不适合逐步理解、维护或作为 Agent 翻译底稿。

结论：参考公开 API 的职责设计；不选作代码移植源。若实际复用代码，必须先单独核对授权，不能认为“换成 MoonBit”消除了原代码授权条件。

### 3.2 UniPDF：属于 PDF 层，且有同样的授权与可读性障碍

[LICENSE.md](../references/unipdf/LICENSE.md) 同样是商业授权；[model/model.go](../references/unipdf/model/model.go) 也有混淆生成标识。`core` / `model` / `creator` 等层次可以帮助理解 PDF 原语与高层生成 API 的区别。

PDF 库不替我们解决 DOCX 分页、表格公式或 PPT 母版继承。对于“把已布局的页面写成 PDF”，Krilla 是更适合深入阅读的开放参考。

结论：不作为底座或默认依赖，也不因 PDF 功能多而把它放在文档语义层之下。

### 3.3 AnyDoc：好的提取管线，不是可编辑文档内核

其核心方向是多格式转 Markdown。[src/model/block.rs](../references/anydoc/src/model/block.rs) 的统一模型围绕段落、标题、列表、表格、代码块等内容组织。这很适合搜索、RAG、文本提取，却不能表示完整的工作簿、幻灯片与 Word 编辑语义。

[src/lib.rs](../references/anydoc/src/lib.rs) 中的 PDF Markdown 路径还直接走 `pdf-inspector`，没有强行经过统一 `Document` 模型。这也说明“支持很多格式”不代表存在一个可逆的通用编辑模型。

最值得参考的是 [src/package/archive.rs](../references/anydoc/src/package/archive.rs)：

- 按需读取 ZIP 部件，缓存重复读取的结果。
- 对实际读取/解压出来的字节施加预算，不只相信 ZIP 头部声明。
- 重复读取命中缓存时，不重复消耗总读取预算。

不过，提取场景中“跳过坏掉的可选部件、继续输出正文”可以成立；编辑后保存时采用相同策略可能丢数据。我们需要保留原始内容或明确拒绝相关修改。

结论：采用其包读取与资源预算思路；Markdown 等统一内容模型只作为派生输出，不作为 SDK 的权威模型。

### 3.4 Calamine：读取设计有价值，但 Range 不能用作编辑器数据底座

Calamine 的定位是表格读取。解析到公式字符串不等于计算公式，也不包含交互编辑、撤销和布局。

[src/lib.rs](../references/calamine/src/lib.rs) 的 `Reader<RS: Read + Seek>`、`ReaderRef` 和 [XLSX 单元格读取器](../references/calamine/src/xlsx/cells_reader.rs) 值得参考：读取和存储介质分离，部分路径减少字符串复制。

需要特别防止误用 `Range<T>`：它的内部是矩形范围对应的 `Vec<T>`；`Range::from_sparse` 最后仍按矩形面积分配 `vec![T::default(); len]`。这不是持久的稀疏存储。两个距离很远的单元格也可能形成巨大矩形。

结论：参考导入器与读取路径，不照搬 Range 作为工作簿的权威存储。我们的编辑模型应按实际存在的单元格保存数据，并明确整行/整列操作的表示方式。

### 3.5 Office Oxide：比 AnyDoc 更接近文件操作 SDK，仍不是 Office 编辑器底座

这个项目值得认真读，不能简单归类为“只有提取”。除了读取，它还有结构化 IR、创建和有限的原文件编辑；[WASM 接口](../references/office_oxide/src/wasm.rs) 包含文本替换、设置单元格和返回保存字节。

其中 [EditablePackage](../references/office_oxide/src/core/editable.rs) 的原始部件保留和局部修改思路适合我们：不认识的文件不必因为没有建模就丢掉。DOCX 文本替换也考虑了文字跨 run 的情况，见 [src/docx/edit.rs](../references/office_oxide/src/docx/edit.rs)。

但检查实现后，有以下边界：

- `EditablePackage::from_reader` 将部件读入 `HashMap<PartName, Vec<u8>>`，是急切读取，不是大文件按需部件存储。
- 保存会重新写 ZIP，并重新生成关系和 content types。不能把“未修改部件的内容保留”解释成“整个源文件字节不变”。
- `replaceText`、`setCell` 不等于富文本编辑会话。仍缺我们需要的布局、命中测试、IME 语义、撤销和增量绘制闭环。
- 当前 WASM 接口明确没有涵盖全部 native builder / 创建 / `saveAs` 能力。不能从 native API 数量推导浏览器可用范围。
- README 的大规模样本结果主要服务解析/提取回归，并不证明 Word 视觉保真或交互编辑保真。

其 [regression-sweep](../references/office_oxide/scripts/regression-sweep/README.md) 区分解析状态与内容差异，也讨论词频而不是只比词集合，很值得学习。真实 corpus 没有随库完整分发，我们没有复现其总体兼容率。

结论：在用户列出的五个项目里，它最值得作为“开放的多 Office 格式读写实现”继续研究；但作为整体底座，优先级仍低于下面的分层组合。

## 4. 更适合我们架构的参考

### 4.1 Typst：最值得参考的总体计算管线

Typst 的价值不在于 Rust 语法，而在于它把“从语义内容得到页面”和“获取外部资源/输出页面”分开。

- [World](../references/typst/crates/typst-library/src/lib.rs) 明确列出 source、file、font 等外部资源访问，缓存归属也有说明。我们的宿主可以预先提供资源字节，核心不必直接读文件或调用 DOM。
- [Frame](../references/typst/crates/typst-library/src/layout/frame.rs) 保存已定位的文本、形状、图片、分组等内容。布局结果不是某个浏览器 DOM 的副作用。
- [inline](../references/typst/crates/typst-layout/src/inline/mod.rs) 与 [flow](../references/typst/crates/typst-layout/src/flow/mod.rs) 有实际的 `comemo::memoize` 边界。缓存与输入依赖相关，而不只是渲染结果全量重用。

我们应该学习这些边界，不应该移植其脚本语言、求值器、宏系统或完整 `comemo` 框架。Typst 的内容语义也不是 Word 的内容语义；把 DOCX 转成 Typst 再转回，不会自动保留原文档。

落地建议：先用显式 revision 和受影响段落/页面范围管理缓存，正确性成立以后再考虑更细的依赖追踪。不要为了“像 Typst”先建增量计算平台。

### 4.2 Open XML SDK：格式底座不应该因为不是 Rust 就被排除

这是 OPC/OOXML 保真设计最有价值的参考之一。

- [OpenXmlPart](../references/Open-XML-SDK/src/DocumentFormat.OpenXml.Framework/Packaging/OpenXmlPart.cs) 区分部件存在与 root DOM 已加载，支持需要时才解析。
- [OpenXmlUnknownElement](../references/Open-XML-SDK/src/DocumentFormat.OpenXml.Framework/OpenXmlUnknownElement.cs) 可以保存 `RawOuterXml`，未解析时直接写出；已解析时按结构写出。
- [OpenXmlPartReader](../references/Open-XML-SDK/src/DocumentFormat.OpenXml.Framework/OpenXmlPartReader.cs) 提供另一种读取形态，不要求所有操作都建立完整 DOM。

值得采用的是“已理解内容的类型化操作 + 未理解内容的保留”以及 OPC 包图。没有必要一次生成全部 schema，也不要承诺所有 XML/ZIP 字节原封不动。

未知节点并不是唯一问题：关系引用、命名空间声明、属性值中的前缀、`mc:AlternateContent` 等都可能影响语义。修改已解析部件时也要保留这些上下文。

它没有 Office 布局引擎；schema 验证通过也不代表画面正确。

### 4.3 Parley：文本布局和编辑几何的设计参考

Parley 将字体、塑形、文本布局与编辑几何作为专门问题处理，不把它们埋在某种 Office 格式中。

[LayoutContext](../references/parley/parley/src/context.rs) 复用分析、塑形与样式构建的 scratch space；[Cursor](../references/parley/parley/src/editing/cursor.rs) 处理 affinity、字形簇、RTL 和视觉移动，而不是简单用字符数量决定光标坐标。

这些设计对 MoonBit 仍然有价值：GC 不会消除短命数组、重复字符串和临时对象的成本。但 Rust 里的生命周期、借用和共享所有权不需要逐字翻译。

由于已找到 `moon_cosmic`，P0 应先验证它是否满足这些合同，不直接开启 Parley 全量移植。Parley 保留为发现接口缺口与检查复杂文本行为的参考。

### 4.4 IronCalc：表格业务内核参考，不是现成的最优增量计算器

[Model](../references/IronCalc/base/src/model.rs) 管理工作簿、解析公式及计算状态；[UserModel](../references/IronCalc/base/src/user_model/common.rs) 将用户修改、diff、历史和撤销重做放在核心。这种“编辑动作改变同一核心状态”的方向适合薄 TS。

需要避免夸大其增量能力：[evaluation.rs](../references/IronCalc/base/src/evaluation.rs) 的 `evaluate` 路径遍历公式并处理动态数组等情形，不能说它已经只重算 dirty 依赖子图。我们可以先采用其公式语义和测试思路，但必须单独测量改单元格的成本。

不应把它的同步队列、所有用户操作外围机制或前端相关高度启发式一起移植。我们当前没有协作服务目标。

### 4.5 Excelize：Go 项目同样能提供重要的格式经验

Excelize 将结构化工作表对象、包中原始内容和流式写入结合使用。[file.go](../references/excelize/file.go) 的保存路径会处理已改动的模型与保留的包内容；流式能力适合批量读写，而不是要求所有数据常驻同一种完整 DOM。

它使用文件系统临时文件等 native 能力，不能原样搬到浏览器。值得取的是部件级处理、XLSX 兼容规则与测试，不是照搬 Go 的 runtime、锁和文件缓存机制。

这也是“Rust 语法更像 MoonBit，所以 Go 参考价值低”的反例。OOXML 的语义与保存策略不由编程语言决定。

### 4.6 Krilla：布局结束后，PDF 后端该做什么

[Surface](../references/krilla/crates/krilla/src/surface.rs) 同时提供高层文字绘制与接受既定字形位置的 `draw_glyphs`。对我们而言，后者更重要：PDF 后端消费同一份排版结果，不应该再次决定换行。

字体嵌入/子集、文字提取映射、图片、PDF 结构与验证都有独立复杂性，不能简化成“把 Canvas 画面截图进 PDF”。Krilla 的测试组织也提示我们同时检查渲染与 PDF 结构。

它不是 PDF 编辑器，也不替代 DOCX 分页。可参考后端设计和测试；当前没有建议把整个 Rust 库直接混入 MoonBit 核心。

## 5. MoonBit 生态：哪些可以直接试，哪些还要补

以下版本取本轮本地源码 manifest；不保证它们都已以相同版本发布到 registry。检查 CI 配置只表示项目声明的测试路径，不表示本轮实际运行通过。

| 能力 | 候选及本地版本 | 检查结果 | 建议 |
| --- | --- | --- | --- |
| DEFLATE / ZIP | `moonbit-community/flate` 0.8.5 | 无 I/O 压缩核心、资源限制、取消、原始记录保留；CI 明确覆盖 WasmGC | 第一顺位 |
| ZIP 备选 | `hustcer/fzip` 0.8.7 | fflate 移植，checked API、校验与边界处理；同步 ZIP 路径仍是全缓冲 | 作为对照，不同时引入两套 |
| XML | `Milky2018/xml` 0.5.0 | 命名空间感知 pull reader、checked writer、源范围；多 target 声明 | 第一顺位，保真策略由 SDK 补齐 |
| 文本布局与字形缓存 | `Milky2018/moon_cosmic` 0.3.7 | 字形 ID、文本范围、offset、BiDi level；命中测试、轮廓/位图缓存；CI `--target all` | 优先做浏览器 WasmGC 探针 |
| 字体塑形 | `moonbit-community/harfbuzz` 0.1.0 | 已有多脚本实现；moon_cosmic 当前实际调用它 | 随文本链统一验证，不并列建第二套 shaping |
| Unicode BiDi | `moonbit-community/bidi` 0.5.2 | Unicode 16 数据与官方测试向量；typecheck all，conformance native | 对照/候选，避免和 moon_cosmic 的实现重复拥有状态 |
| 字体轮廓/表读取 | `mizchi/font` 0.7.4 | TTF/OTF/WOFF 等；不实现 GSUB/GPOS/GDEF | 专项备选，不是完整文本引擎 |
| Office 解析、布局与 PDF | `moonbitlang/office.mbt` workspace | 已有 ooxml、mbtexcel、docx2html、pptx、pagelayout、pdflite 等 | 分模块研究，不整体采用 |

### 5.1 flate：最有希望直接使用，但默认行为不是我们的最终包策略

[ZIP API](../references/flate/flate/zip/pkg.generated.mbti) 包含读取预算、取消、流式 Writer，以及 `write_preserving` / `write_preserving_limited`，可以复用未修改条目的原始记录。

几个不能省略的限制：

- [read](../references/flate/flate/zip/reader.mbt) 明确解码每个 entry。压缩器支持流式处理，不等于 ZIP 包读取已经懒解压。
- [ReadLimits::default](../references/flate/flate/zip/types.mbt) 使用接近 Int 上限的默认值，不是适合浏览器的资源预算。SDK 必须显式传入限制。
- 当前 `read` 返回 CRC 信息但不验证 CRC。需要完整性检查时，应使用 checksum API 校验，而不是以“成功解压”代替 CRC 校验。
- 保留原始压缩数据可能增加驻留内存；需要同时限制解压内容和保留的源记录。

P0 小样本可以先用有明确预算的现有读取路径。真正面向大文档的底座应将 ZIP 索引与部件解压分开；这是待实现/验证的能力，不能在文档里写成已获得。

### 5.2 XML：pull 事件不等于字节流解析，语法正确不等于保真

[xml-mbt](../references/xml-mbt/README.md) 当前接受 UTF-8 输入，不覆盖所有 XML 编码。事件与属性 span 使用 UTF-16 code unit，方便切 MoonBit String；它们不是源文件 UTF-8 字节偏移。

对于保留未知 XML，这比完全丢失源位置信息更有用。但仍需选择：保留未变更部件字节；对修改部件保留未触及的原始片段及命名空间上下文；或者完整解析并保证扩展节点可逆。不能只接一个 parser 就宣称无损。

遇到非 UTF-8 OOXML 部件需要明确支持转换还是返回不支持，不能解码错了继续保存。DTD/外部实体并非 Office SDK 的默认需求，不必为了“完整 XML”扩大输入能力。

### 5.3 moon_cosmic：本轮发现的最直接文本基础候选

它是 Rust cosmic-text 的 MoonBit 移植。比单独找到字体 parser 更重要的是，它已经把布局、字形和编辑几何接在一起。

- [LayoutGlyph](../references/moon_cosmic/src/layout.mbt) 有 `glyph_id`、`font_id`、文本 `start/end`、`x/y`、`x_offset/y_offset` 和 BiDi level。
- [shape.mbt](../references/moon_cosmic/src/shape.mbt) 当前通过 harfbuzz.mbt 进行塑形，构建 cluster 映射；README 中仅强调 moon_swash 的文字不足以描述当前实现。
- [SwashCache](../references/moon_cosmic/src/swash.mbt) 可以获取字形图像和轮廓命令，不必每次把字符串交给浏览器重新塑形。
- 自带 Buffer、命中测试、编辑动作与缓存，可参考文本段落内的行为，但不把其 Editor 直接变成整个 DOCX 编辑模型。

仍需验证：

1. transitive dependencies 的固定版本在浏览器 WasmGC 下能构建、链接并运行；`moon test --target all` 不是浏览器 Worker 集成测试。
2. [unicode_linebreak](../references/moon_cosmic/src/unicode_linebreak/unicode_linebreak_test.mbt) 的向量测试存在显式跳过集合；分段源码也有简化规则，不能宣称完整 Unicode 一致性。
3. [该子包 manifest](../references/moon_cosmic/src/unicode_linebreak/moon.pkg) 将 `moonbitlang/x/fs` 列为普通 import，而其测试读取本地文件。需要检查最终浏览器 imports 是否剔除了无关 I/O；不能只看库声明。
4. 实际塑形路径使用默认语言 `und`。语言相关替换、CJK 字形、不同字体与变体轴须单独检查。
5. 绘制 API 有逐像素回调形式；不能把回调逐次跨到 TS。应在 WASM 内组装位图/图集或轮廓资源，再批量传输。

因此把它排在“第一轮验证”，还不能称为生产可直接采用。它若满足需要，可以省去大量从 Parley 手工移植的工作；若不满足，应优先定位缺失模块，而不是重写整条文本链。

### 5.4 harfbuzz、Unicode 和 font：功能重叠需要收敛

[harfbuzz.mbt](../references/harfbuzz.mbt/) 已有阿拉伯、Indic 等脚本相关实现，不能说 MoonBit 完全缺少复杂塑形。也不能从名字或移植清单推断与上游 HarfBuzz 全量等价；应使用相同字体和文本比对 glyph、cluster、advance 与 offset。

[Unicode 仓库](../references/unicode/) 带 `BidiTest.txt` / `BidiCharacterTest.txt` 等向量，发布模块与测试文件 I/O 分开，这是好的测试组织。需要验证它如何衔接段落分析、软换行后的行级重排和编辑位置；并核对它与 shaping 库的 Unicode 数据版本。

[mizchi/font](../references/font/README.md) 可提取字体轮廓与度量，但明确没有 GSUB/GPOS/GDEF，因此不能代替 HarfBuzz，也不单独解决双向文本和换行。`moon_cosmic` 已依赖 swash/skrifa 路线，不应再为了“生态完整”把另一套字体 parser 全部引入。

### 5.5 office.mbt：非常相关，但不能因为官方组织维护就整体采用

它已经有与我们需求重叠的模块，也在复用 flate 和 xml；[PPTX 来源记录](../references/office.mbt/pptx/UPSTREAM.md) 清楚记录了移植来源和改动。这些代码比另起炉灶实现所有 Office 解析器更值得先看。

但当前底座仍有需要回避的实现选择：

- [ooxml/opc/package.mbt](../references/office.mbt/ooxml/opc/package.mbt) 先 `zip.read`，再复制所有 entry 数据到 parts；保存新建 Archive，不走 flate 的 preserving write。增加内存和重写成本。
- [ooxml XML adapter](../references/office.mbt/ooxml/README.md) 明确不保留注释、PI、命名空间声明拼写，以及属性值里的前缀等内容。不能把它直接当高保真编辑底座。
- [pagelayout 的 GlyphRun](../references/office.mbt/pagelayout/page_model.mbt) 是 `text + advances_pt`，advance 按 UTF-16 code unit 索引，没有完整的 glyph ID / cluster / offset。命名叫 GlyphRun，不代表已满足复杂塑形后的通用输出合同。
- [pagelayout/pdf/moon.pkg](../references/office.mbt/pagelayout/pdf/moon.pkg) 明确 `supported_targets = "native+wasm"`，不包含 `wasm-gc`。不能把“MoonBit PDF 后端存在”当作我们的 P0 PDF 已解决，也不能因此推断整个 pdflite 都不支持 GC。
- 当前 [XLSX 存储](../references/office.mbt/mbtexcel/xlsx/worksheet_types.mbt) 已有 cell index；[索引实现](../references/office.mbt/mbtexcel/xlsx/worksheet_cell_index.mbt) 使用字符串坐标键。旧文档里没有索引的描述不能代替当前源码，索引分配成本也需要实测。

建议按格式读取、写入、URI、样式、字体与测试分别筛选。选择它的现成算法，不自动接受它所有中间表示和依赖边界。

## 6. 建议的通用底座形态

下面是职责划分，不是预先要创建的 package 清单。

```text
Web TS / Worker bridge                         CLI host（P1）
文件、字体、IME、指针、无障碍、绘制执行             文件/参数/输出
                 │                                 │
                 └────── bytes / commands ──────────┘
                                   │
                      MoonBit DocumentSession
                      编辑事务、撤销、变更范围
                                   │
                 ┌─────────────────┼─────────────────┐
              FlowDoc            Workbook           Slides
         DOCX 语义、流式分页    稀疏网格、公式计算    场景、母版、文本框
                 └─────────────────┼─────────────────┘
                      共享样式/资源/文本排版
                                   │
                         Frame / DisplayList
                                   │
                       Web 绘制 / PDF 等导出

              ZIP / OPC / XML / 原始未知内容保留
                 为各格式导入与保存提供共同基础
```

### 6.1 共享基础，不共享一棵万能文档树

Word 是流式内容，Excel 是网格和公式，PPT 是场景与母版。它们可以共用资源、字体、绘制原语与会话外壳，但不能因为都能画出文字就共用同一编辑 AST。

PDF 属于固定版面，Markdown 属于信息投影，也不应反向成为所有格式的权威模型。格式转换逐对定义能力和损失诊断。

### 6.2 三种表示各有职责，但只有一个编辑权威

1. 原始 package / 未知数据：不可变源事实和保存材料，不提供另一套自由修改入口。
2. 格式语义模型：命令修改的唯一权威，记录变更的对象与源部件关系。
3. 布局结果：由模型与字体/视口推导的缓存，失效后可重建，不反向修改源内容。

这不是双写设计。保存按明确的变更映射生成被修改部分，其他材料保留。仅保存“未修改部件”还不够；同一已修改 XML 部件里的未知扩展也要覆盖测试。

保存策略要区分：确定性输出、未修改部件内容一致、未修改压缩记录复用、整个 ZIP 字节一致。它们是不同的保证。数字签名等也可能因编辑失效，不能承诺通用“无损”。

### 6.3 WASM / TS 分界必须到字形这一层

不能由 WASM 算一组字符宽度，再让 TS `fillText` 接管复杂文本。Canvas `fillText` 接受字符串和文字设置，不接受我们给出的 glyph ID 序列；浏览器仍会处理文本。见 [Canvas API](https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/fillText)。

建议先验证两条最小输出路径之一：

- WASM 输出缓存的字形轮廓及位置，TS 批量重放路径；同一轮廓资源只传一次。
- WASM 生成字形位图/图集，TS 批量合成；不同缩放/DPR 下重新生成必要资源。

现有 moon_cosmic 两类接口都有可研究入口。先测一条，不预建双渲染器。路径会遇到小字号栅格质量和复杂页面带宽问题；位图会遇到缩放、缓存体积和颜色格式问题。

语义文本与 cluster 映射仍须保留，供选区、复制、无障碍及 PDF 文本提取使用。字形变成路径不代表可以丢弃文本。

### 6.4 扩展点只建在已经存在的变化处

现在需要：资源输入、格式导入/保存、布局结果的消费边界。

现在不需要：任意第三方插件容器、全格式 schema 生成平台、多语言 native ABI、通用 RPC、CRDT、分布式缓存、事件溯源。

单 Worker 内一个会话持有模型，命令返回受影响范围；UI 只取需要的状态。撤销使用足以恢复语义的操作/差分，不每次复制整个包。

## 7. Rust 更接近 MoonBit，所以更有参考价值吗？

对具体算法，通常更容易阅读和迁移；对总体架构，不构成排序依据。

`enum`、模式匹配、泛型、显式错误和分层模块，让不少 Rust 算法在 MoonBit 中有自然表达。Parley、Typst、Krilla 中布局与几何数据结构是好例子。但关键差异比语法更重要：

| Rust 中的惯用设计 | MoonBit / WasmGC 中要重新判断的事情 |
| --- | --- |
| lifetime、借用、`Arc` / `Rc`、arena | GC 下的可变性、别名、共享与保留生命周期；不照抄所有权外壳 |
| UTF-8 字符串与 byte offset | MoonBit String 使用 UTF-16；外部字节、code unit、code point、grapheme、glyph cluster 必须区分 |
| `usize`、大文件寻址、mmap | MoonBit 数值范围、WASM 内存和浏览器输入缓冲约束；不能直接平移大小计算 |
| 宏、derive、trait blanket impl | 保留业务合同，减少依赖语言技巧的框架机制 |
| Rayon、锁、多线程缓存 | P0 单 Worker owner 和批量任务先成立，不复制 native 并行结构 |
| wasm-bindgen 的 JS ABI | 不能拿来直接暴露 WasmGC 对象；需要我们自己的小型批量数据边界 |

MoonBit 的字符串与 FFI 以 [语言文档](https://docs.moonbitlang.com/en/stable/language/fundamentals.html) 和 [FFI 文档](https://docs.moonbitlang.com/en/stable/language/ffi.html) 为准。Rust 项目能编译成传统 WASM，也不代表它能作为 WasmGC 对象库直接链接进 MoonBit。

更有用的优先顺序是：

1. 语义与运行边界是否符合需求。
2. 能否合法复用，源码与测试是否可读、可验证。
3. 数据结构和成本模型是否适合浏览器及 GC。
4. 是否已经有合适的 MoonBit 实现。
5. 最后才是语法迁移成本。

因此 Open XML SDK（C#）在 OPC 保真方面优先于不少 Rust 解析库；Excelize（Go）的 XLSX 兼容经验仍值得借鉴；moon_cosmic 则可能比从 Rust 重写文本引擎更省成本。

## 8. 开始建设前，最值得做的验证

无需先写完整 SDK。用两个小切片决定核心风险是否可控，以下是建议，不是已获验证的结论。

### A. 先验证文本链和浏览器输出

固定 MoonBit 及依赖版本，使用 moon_cosmic / harfbuzz 路线完成：字体字节 → 复杂文本塑形 → 布局 → 字形轮廓或位图 → 浏览器 Worker 绘制。覆盖中文、组合字符、连字、阿拉伯文、混合 RTL、emoji、替代字体及变体轴。

验证 glyph/cluster 与参考实现的差异、命中测试和选区、最终 WASM imports、冷启动和缓存后重复布局。TS 不补做文本布局；无法实现时记录具体缺口。

这比先把三种 Office 文件都解析出来，更早暴露选型的硬问题。

### B. 再验证保真包编辑

在同一 OOXML 文件内保留未知元素、扩展属性、关系、嵌入图片和未识别部件，只修改一处已知文字或单元格。检查保存后内容、关系可达性与参考应用重开结果。

同时记录输入字节、解压字节、模型和原始保留材料的峰值内存；比对 flate 普通写与 preserving write 的耗时和输出差异。大稀疏表格不允许因矩形范围扩张而按面积分配全部单元格。

通过后再把两个切片结合到首个格式编辑会话。PPTX 文本框更容易先接固定几何；DOCX 分页更容易暴露高风险。首个完整格式仍由产品样本决定，不在本报告中擅自锁定。

所有性能结果都应记录样本、字体、浏览器、工具链、debug/release、原始/压缩 WASM 大小，并区分冷启动、热路径、局部编辑与全量保存。当前不给未经测量的毫秒或包体承诺。

## 9. 本轮证据与限制

实际运行环境：macOS；Cargo 1.98.0。当前 PATH 未发现 `moon` / `moonc`，所以没有运行 MoonBit 测试或浏览器 WasmGC 集成，未安装新的工具链。

运行结果：

```text
references/anydoc
cargo test --locked --lib package::archive::tests -- --nocapture
3 passed; 0 failed

references/office_oxide
cargo test --locked --lib core::editable:: -- --nocapture
4 passed; 0 failed
```

AnyDoc 覆盖部件路径归一化、总读取预算、重复读取缓存。Office Oxide 覆盖属性中 `>` 的文本替换、重复保存确定性、原地保存失败不损坏源文件及成功替换。

Office Oxide 第一次使用 `core::editable::tests` 过滤得到 0 tests；不计作测试通过证据。随后核对实际模块名并使用上面的过滤条件重跑。

没有运行所有项目的全量测试、作者私有兼容 corpus、完整渲染差分或性能横评。两个 Rust 构建共享下载和编译缓存，不能拿其构建时间比较语言迭代效率。克隆和测试没有修改参考仓库的产品源码，也没有把任何库接入 SDK。

下面的许可证是所查仓库顶层声明，不能替代依赖、字体、测试样本及移植代码的逐项核查；UniDoc 商业授权项目不作为可自由移植来源。

| 本地目录 / 上游 | 本轮固定 HEAD | 顶层授权 |
| --- | --- | --- |
| [unioffice](https://github.com/unidoc/unioffice) | `7b4037da94004ef23fd6cdc927caa51c06210dff` | 商业 |
| [unipdf](https://github.com/unidoc/unipdf) | `e279a3aa2c1ac0d5b55581e2a9b990b851eb5406` | 商业 |
| [anydoc](https://github.com/firecrawl/anydoc) | `261fc257d17c3eab0f673be31c408fd9fdc2171a` | MIT |
| [calamine](https://github.com/tafia/calamine) | `0af05f4f6030351e3b8a999ea0810c8618368776` | MIT |
| [office_oxide](https://github.com/yfedoseev/office_oxide) | `7fce6094b46c6a7afd133fedbffe305ddb1929a1` | MIT OR Apache-2.0 |
| [typst](https://github.com/typst/typst) | `e58a63af09032a486b12241d08ebd04131483221` | Apache-2.0 |
| [Open-XML-SDK](https://github.com/dotnet/Open-XML-SDK) | `431ab05cf160248cc3885a4a766026d4f8243792` | MIT |
| [IronCalc](https://github.com/ironcalc/IronCalc) | `09e81f53f4c021fc0ec212e95fb353a1c6c5c704` | MIT OR Apache-2.0 |
| [excelize](https://github.com/qax-os/excelize) | `efb59188b3f56bbffdd614408ad85634292642db` | BSD-3-Clause |
| [parley](https://github.com/linebender/parley) | `80faa617c851679c2a925293224cd7cda4a17877` | MIT OR Apache-2.0 |
| [krilla](https://github.com/LaurenzV/krilla) | `ce83e37f2913623b9283f7cb75c21b21d9c59a8a` | MIT OR Apache-2.0 |
| [office.mbt](https://github.com/moonbitlang/office.mbt) | `2f08f3b8041d9098d258969fe3902b34585163cc` | 分模块；保留各模块 LICENSE / NOTICE / UPSTREAM |
| [xml-mbt](https://github.com/moonbit-community/xml-mbt) | `2468d70e4c49e3b017cabe7d5d8ef7b29bcff141` | Apache-2.0 |
| [flate](https://github.com/moonbit-community/flate) | `63f4f9fe51356670ca951f2b5da1d726a0bba52e` | Apache-2.0 |
| [fzip](https://github.com/hustcer/fzip) | `370997daaedc41b3a73f0c8a4067ed433666ef20` | Apache-2.0 |
| [harfbuzz.mbt](https://github.com/moonbit-community/harfbuzz.mbt) | `143eb274d414145dd9ee4d402ad25b2085f220a1` | Apache-2.0，另保留上游声明 |
| [font](https://github.com/mizchi/font) | `59ffb553b04d4334326ed073e562c430d23685ee` | Apache-2.0 |
| [unicode](https://github.com/moonbit-community/tonyfettes-unicode) | `6ebcc801a8251e81b2b78b00b40edc9bcd7ad4bc` | Apache-2.0，另核对 Unicode 数据声明 |
| [moon_cosmic](https://github.com/moonbit-community/moon_cosmic) | `b307f2599accac591199a7cd16ab6594067ba272` | Apache-2.0，另保留移植来源声明 |

原有三个项目的本地路径和 HEAD 见[上游参考项目](references/upstream-projects.md)。所有副本只供研究，不是当前项目构建依赖。
