# 语料管理

本文描述数据管理与准备状态，不分发私有数据。所有 `cases/`、`fixtures/`、`tools/`、`.temp/` 路径和命令均相对父仓库的私有 `test-lab/`；无私有权限也可阅读本文件，不保证能执行测试。

`cases/catalog.json` 登记自建资产，`cases/compatibility.json` 登记固定上游输入、许可、操作与可执行的结构预期；`cases/text.json` 拥有 P0 文本操作的独立预期。`active` 参与当前 SDK 行为验收；`p2-verified-p3-prepared` 只表示 P2 窄操作；`p3-verified-limited` 表示有限 P3 渲染与输出；`p3-verified-negative` 表示明确拒绝布局且原内容保留；`prepared-not-sdk-verified` 是未来输入。执行的必选案例以 `cases/suites.json` 为准，状态或 readiness 测试不能抵扣行为断言。

## 当前数据

G2 另增加 `cases/lo-docx.json` 的 20 个 LibreOffice/core 固定回归 DOCX，revision 为 `1746b16a564f59fcaf8c5670bb292748408da54e`。原文件、对应上游断言源码和完整许可保留在私有目录；独立 unzip/xmllint 提取的正文文本及逐 part 字节保留是当前 oracle。生产工具及版本无法确认时记 unknown；列表的 CJK 特征不冒充正文语言。模板家族按特征保守归组，不作为来源多样性的额外数量。这批只验收 read/preserve，不把样式、编号、RTL 或 shape 的保留提升为布局支持。

`bun run test:office-candidates` 从成功 snapshot 复制原输入和 SDK 输出，生成待 Word 重开/导出/人工审核的候选字段，不创建 golden。SDK 输出是审核对象；必须另外记录 Word 版本、OS、字体 hash、profile、重开诊断、对应 PDF 和审核人。本机无 Word，全部候选仍未验证。新的 G2 Latin 原子输入与原含 emoji seed 分开保留；没有替换原文件来掩盖缺字。

- 17 个自建文本操作：ASCII、中文、emoji、空串、删除、追加、换行、RTL、组合字符、NUL、非法范围与 i32 边界。
- 一个自建 DOCX，源 XML 也保留：正文中英/emoji、未知属性、customXml 及关系，stored ZIP、固定日期。`unzip -t` 已检查包完整性；尚未做 Word/schema/layout 验证。
- 一个自建单页 PDF 1.4：独立对象/xref、标准 Helvetica、已知文本。qpdf 只作结构检查，不代表渲染或 PDF/A 验证。
- 一个故意截断的 XML 输入，用于之后检查明确拒绝行为。
- 三个自建 XML：命名空间/CDATA/未知属性、重复属性、外部实体。连同截断输入由 Moon overlay 直接执行固定字节；命名空间样本编辑后检查未知属性/节点保留。浏览器另验证拒绝 DTD 且外部请求计数为零。
- 四个 Apache POI DOCX：`poi-paragraphs`、`poi-tables`、`poi-page-breaks`、`poi-inline-image`，覆盖 7 个段落、6 个表格、2 个显式分页符及 1 个图片关系的结构断言。精确 XPath 和值在机器清单，不复制成第二份预期。
- 两个 PDFium PDF 及原始 `.in`：`pdfium-two-pages` 是有效双页输入；`pdfium-rectangles` 缺少 Resources，qpdf 12.4.1 报修复警告，专用于诊断/恢复策略，**不能当作合法 PDF writer 输出 golden**。
- 六个固定 Noto TrueType 字体：Noto Sans regular/bold/italic/bold-italic、Noto Naskh Arabic 与 Noto Sans SC variable TTF 默认实例；另有 CFF OTF 用作明确拒绝案例。`cases/fonts.json` 记录固定 commit/原路径/hash/SIL OFL、身份与独立 HarfBuzz 14.4.0；字体许可原文保留，不打包进公开 SDK。
- Unicode 15.0.0 的 LineBreakTest 原文件与许可。执行 6,424 个与已选 Unicode 13.0.0 字符数据和声明 tailoring 相符的向量；不宣称完整 UAX #14 符合性。差异与版本归[格式合同](formats.md)。
- 三个 POI DOCX 的 LibreOffice 25.8.2.2 参考 PDF，共六页；固定四样式字体和替换 profile。`cases/p3.json` 拥有不可变 hash、页数、几何与颜色判定，具体预期不复制到文档。
- P3 原子输入由私有 ZIP 工具从自建 seed 生成：样式、段落、图片、表格、空页、资源预算和生命周期；每次实际输入按 SHA-256 保留在运行目录，失败文件不会被重跑覆盖。四象限 RGBA PNG 独立生成，未调用 SDK writer 制作答案。
- W3C XML Test Suite 20130923 的 20 个 DTD-free Namespaces 1.0 案例：8 个 well-formed、12 个 not-wf；清单中 `invalid` 表示 DTD-validity 而非 XML 语法错误，因此非验证 parser 应接受这些 well-formed 输入。`cases/xml.json` 固定来源、SHA-256、Richard Tobin 原版权/允许再分发 notice 和原套件 verdict。不是 W3C 全套符合性声明。

四个 POI DOCX 在真实 WasmGC 中完成 no-op、两次文本替换和重复保存；独立 ZIP/XML 检查及非目标 part hash 全部执行。前三个另对照固定 LibreOffice 页面，检查预览/PDF 的文字、页数与几何。`poi-inline-image` 原文件实际是浮动 `wp:anchor`，P3 保留该负向输入并明确拒绝；正向内联图片使用独立自建输入。未验证 Microsoft Word、编辑保存后的参考应用重开或完整 OOXML schema。

`bun run test:corpus` 可单独复核这些数据；完整 loop 也会执行它们对应的 Bun 测试。所有输入先核对 SHA-256，再调用固定任务的独立工具，工具超时/退出码/诊断不符即失败。上游许可和 NOTICE 原样保存在各来源目录；仓库级许可不是所有第三方材料的无限再分发授权，新增样本仍须逐项检查。

首次导入由 `moon run tools/import-corpus.mbtx` 从固定 commit 的本地研究仓库提取，保留原路径，拒绝覆盖已有目录。日常测试直接使用已入库的文件，不依赖 `references/` 或联网下载。`.temp/corpus-quarantine/rtl.docx` 是本轮发现正文来源需要进一步核对后隔离的候选，不入正式清单；无关的 extractor 源码副本也保留在该临时目录，不随测试仓库提交。

生成器 `tools/prepare-corpus.mbtx` 使用私有源素材与独立系统工具，不调用 SDK writer 来生成它自己的答案。首次资产已生成；脚本拒绝覆盖存在的 reviewed binary。需要重建时在临时独立 checkout 中运行，比较 hash 后人工审阅，不删除既有样本取巧。

每个新样本带来源/commit/原路径、内容 hash、许可、特征、具体操作、预期及其证据。Office golden 另记引擎/字体/OS/profile；字体文件也须授权，不因来自本机而可再分发。

## 后续有选择地引入

P3 修复另引入 LibreOffice/core `1746b16a564f59fcaf8c5670bb292748408da54e` 的原始 `n778140.docx` 与 `tdf145716_nonHTMLspacing.docx`，未修改输入。许可与来源 NOTICE 保留在私有仓库；前者诊断自动间距，后者拒绝带内容页眉，二者执行保真保存。九个自建段距/固定行距/分页边界输入与这两份原文件使用固定 LibreOffice 25.8.2.2 生成独立参考，全部 20 页完成重复栅格校准。它们没有扩大 SDK 的自动段距或页眉支持范围。

| 来源 | 固定研究 revision | 首批引入条件 |
| --- | --- | --- |
| Apache POI | `ae62bb5116b9aee19ebd5834e3a82066132c9f7f` | 已引入上述 4 个 DOCX；P5 公式语料尚未引入 |
| LibreOffice | `2821d29a87b28785d74fa64d975465e4c99d4416` | P3 Word 分页/表格/图片，按 bug 和断言筛选 |
| Apache Tika | `c8d4fa1b6568b8ad69acd5981dcd2197314a2531` | P2/P7 内容与异常输入；不当视觉 golden |
| PDF.js | `24de17e81b3357b30ffd710ec080be00d65ac98d` | P7 文本/渲染/批注任务按类型取样，外链先核验下载与授权 |
| PDFium | `a84323421e94f484faca52dd9d027934eba42ab8` | 已引入上述 2 个 PDF 及 `.in`；不含字体/渲染 golden |
| W3C / Unicode | XML suite 20130923，NS1.0；BiDi 依赖目标 Unicode 16.0.0 | 已引入上述 XML 子集；不宣称完整 XML 或 Unicode 算法 conformance suite 已执行 |
| veraPDF / PDF Differences | 尚未导入 | 目标 profile/分歧特征明确、CC BY 等署名信息保留后引入 |

除明确标注已引入的 POI/PDFium 子集外，其余仍是候选来源。完整源码研究与数字口径见 [G1](../g1-compatibility-pipeline.md)。第一轮不下载 Govdocs1、Enron、Stressful PDF 全量，不把缺少 oracle 的大语料当硬验收集。

## 增长策略

先原子样本 → 对应真实回归 → 特征组合 → 有界生成/变异。共享模板和内容 hash 去重，按生产工具/语言/特征覆盖，不靠重复文件增加通过率。大文件与参考图片后续进入按 hash 固定的受控存储，Git 保留清单、小样本和人工断言。

不可信输入禁用宏、脚本、外部链接自动获取；未来转换器在有 CPU/内存/时间限制且无凭据的环境中运行。当前只引入自建输入和来源已登记的固定上游子集，不引入来源不明的二进制附件。
