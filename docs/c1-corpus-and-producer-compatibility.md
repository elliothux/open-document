# C1 兼容矩阵整合、开源语料引入与多生产工具覆盖

状态：`planned`，2026-11-02；2026-11-08 按 [R2 评审](implemented/r2-architecture-and-performance.md#三兼容矩阵覆盖审计)补充本机未用资产、新批次 C1.6 与每格式原件配额。本方案承接 [C0 真实文件可用性与兼容补齐](implemented/c0-real-file-compatibility.md)。C0 解决首批 51 个候选文件的打开与主要内容显示阻塞；C1 将分散的历史测试清单整合为统一的兼容性账本，建立局部不支持特性的分级降级（Graceful Degradation）基线，并系统引入本地参考仓库及公开标准语料，覆盖多生产工具（Producers）、公式/数字格式黄金向量与 CJK 真实排版。证据展示维护在[文件兼容性矩阵](references/compatibility.md)，资产管理遵循[语料管理](references/corpus.md)。

## 用户结果与范围

1. **分级容错不崩（P0 可用性底线）**：合法文档遇到未支持的长尾效果、扩展元素或局部损坏时，隔离在对象、单元格或页面局部只读/降级显示，保留源 XML/对象图与其余内容的可浏览、可编辑与安全保存，不整份拒绝打开或输出空白页。
2. **单一权威兼容账本**：合并 `compatibility.json`、`lo-docx.json`、`p5`、`p6`、`p7-p8`、`p14-*` 与 `c0-*`，按内容 SHA-256、生产工具、特征族和验证层级（打开、语义、视觉、编辑、保存重开）统一索引，剔除同质重复样本。
3. **高价值开源测试集批量接入**：直接复用本地 `references/` 中已检出的 `IronCalc`、`calamine`、`Open-XML-SDK`、`excelize`、`ONLYOFFICE core`、`office_oxide`、`anydoc`、`apache-tika`、`PDF.js` 与 `PDFium` 样本及断言。
4. **生产工具与 CJK 覆盖**：补齐 WPS、Google Workspace、Apple iWork、LibreOffice、Apache POI、openpyxl/python-docx/ReportLab 生成的文件变体，以及中日韩混排、默认字号与标点边界样本。

## 分批实施计划

| 批次 | 目标与覆盖范围 | 核心语料来源 | 足够检查 |
| --- | --- | --- | --- |
| C1.1 账本整合与分级降级基线 | 归并历史清单并去重；确立四格式局部不支持特性的降级与源保留规则 | 既有 `test-lab/cases/*.json` 全部已入库样本 | 账本校验脚本通过；既有正向与控制样本零回退；未知元素/效果不阻断整页显示 |
| C1.2 XLSX 公式、数字格式与引用黄金集 | 批量验证公式求值、错误传播、数字格式掩码与行列增删引用修正 | ONLYOFFICE sdkjs `formula-tests` 60,539 条断言与 `NumFormatParse`；LibreOffice `sc/qa/unit/data/functions` 548 份自校验表；`references/IronCalc`、`references/excelize`、`references/onlyoffice` 剩余 20+ 测试表 | `.mbtx` 黄金向量提取与核心对比测试通过；重算结果独立匹配上游断言与缓存值；XLSX 上游原件不少于 100 份 |
| C1.3 OOXML 怪异容器与复杂特性集 | 覆盖内联字符串、非标命名空间、缺失 calcChain、Markup Compatibility、Office 2016+ 扩展与大文件 | `references/calamine/tests/`、`references/Open-XML-SDK/test/`、`references/office_oxide/tests/` | 容器打开、结构提取、无损保存重开与预算边界检查通过 |
| C1.4 PDF 字体、色彩、表单与修复容错集 | 扩大无 cmap TrueType、CID/竖排、复杂渐变/遮罩、跨页表单外观及轻微 xref/流长度偏差恢复 | `references/pdfjs/test/pdfs/`、`references/pdfium/testing/resources/`、`qpdf` 向量 | 页面渲染与独立 Poppler/PDFium 对照、文本提取及源保存检查通过 |
| C1.5 多生产工具与 CJK 真实排版集 | 覆盖 WPS/Google/Apple/脚本工具生成差异，以及 CJK 字号、字体回退、表格公文与混排换行 | `references/apache-tika`、`openpreserve/format-corpus`、SheetJS `test_files`、python-docx/python-pptx/openpyxl 测试文件及固定生产工具导出样本 | 按生产工具分层统计打开、显示、编辑与外部工具重开结果 |
| C1.6 LibreOffice 布局 dump 黄金集 | 用上游布局 XPath 断言核对 DOCX 分页、行数、浮动对象与表格位置，再扩展到 PPTX 整稿 | `sw/qa/extras/layout/data` 468、`sw/qa/core/layout/data` 96、`sw/qa/core/text/data` 81 份 DOCX 及对应 `layout*.cxx`；`sd/qa/unit/data/pptx` 433 份 | 不少于 100 份 DOCX 的布局断言转为核心几何检查并通过；PPTX 上游原件不少于 100 份 |

---

## C1.1 账本整合与分级降级基线

### 1. 清单去重与状态刷新

R2.7 的私有 `cases/documentation.json` 只维护文档证据入口；`cases/history/*.json` 保留迁移前的历史文字。它们不提供文件级资格，也不代替本批的内容 hash、操作与构建账本。

私有 `cases/ledger.json` 已按内容哈希合并首批 11 份清单。C0 最终扫描的 48 份打开结果和 3 份控制拒绝已绑定原构建与环境。其他清单先登记输入身份，待核对分操作证据后再补资格。生成方式见[测试说明](references/testing.md#文档与证据索引)。

- `WithGIF.docx` 已从 P3 拒绝记录迁移到原件复核。Chromium 验证 GIF 颜色及尺寸、正文输入、精确历史和重开。其余 P2/P3 条目沿原范围记录。
- 保留 `cjklist30/31/34/35.docx`。四份原件分别验证天干、地支、繁体财务数字和繁体计数，并核对 18 pt 正文行框与单页 PDF。另对 `cjklist34.docx` 验证正文编辑、精确历史与保存重开。两份 `table-style-border` 原件分别覆盖右边线存在和底边颜色，保留独立记录。
- 统一生成结构化索引：每个样本明确标注 `sha256`、`producer`、`features`、`verificationLevels`（`open` / `semantics` / `visual` / `edit` / `roundtrip`）。

### 2. 分级降级（Graceful Degradation）规则

修改四格式解析与排版入口，将非致命未知特性从 `@failure.reject` 改为记录 `diagnostics` 并局部降级：

- **DOCX / PPTX**：未知 DrawingML 效果（如 3D 旋转、柔化边缘、未知预设几何、未支持图表子类型）保留源 XML 节点与只读包围盒；存在 fallback 图片或缓存形状时优先绘制后备内容，无后备时绘制占位框并标记该对象只读，不阻断同页其余对象渲染。
- **XLSX**：含未支持函数或外部引用的单元格保留导入缓存值显示与下游依赖只读保护，允许编辑工作簿内无依赖冲突的普通区域；缺失 `calcChain.xml` 或带扩展列表时正常建立会话。
- **PDF**：单个内容流指令、未知色彩空间或缺失外观的复杂批注在对象级隔离并标记 `displayComplete: false`，其余图元与页面正常渲染。

---

## C1.2 XLSX 公式、数字格式与引用黄金集

在 `test-lab/` 运行 `bun run probe:c1-formula-scalars` 可提取并比较首批 ONLYOFFICE 字面量断言。160 条覆盖 ABS、INT、MOD、ROUND、ROUNDUP 和 ROUNDDOWN，159 条精确匹配。向量、来源版本、哈希和断言行号归私有 `.temp/c1-formula-scalars/`。命令遇到差异会保留报告并以失败退出。

唯一差异是 `ROUND(9.99999999999999E+307, 0)`。ONLYOFFICE 断言期望 `1e308`，LibreOffice 26.8.1.1 与当前核心均保留输入值。保留现有行为和原断言。独立对照归根目录 `.temp/r2/c1-round-reference/`。本批只比较六种函数的字面量断言。

在 `test-lab/` 运行 `bun run probe:c1-ironcalc-caches` 可比较五份原版工作簿。探针移除公式缓存，再用 SDK 重算、保存并重开，逐格比较原缓存。三份原件因函数参数数量触发重算保护。`ROUND.xlsx` 的 137 个缓存中有 122 个精确匹配。剩余 15 个差异包括 14 个范围或参数转换结果，以及一个 `ROUNDUP` 末位差异。原件版本、哈希和报告归私有 `.temp/c1-ironcalc-caches/`。存在拒绝或差异时命令以失败退出。

支持 `_xlfn.XOR` 后，`AND_OR_XOR.xlsx` 可以重算并重开。317 个缓存中有 305 个精确匹配。其余 12 个差异都涉及 `AND`、`OR` 或 `XOR` 的直接文本参数。IronCalc 转换或忽略这些参数，SDK 返回 `#VALUE!`。范围内的文本和空白按 Excel 文档忽略，奇数个真值返回 TRUE。[Excel XOR](https://support.microsoft.com/en-us/excel/functions/xor-function)

修复 `ROUND` 半值判断后，两格从 `0.0062` 改为匹配原缓存的 `0.0063`。LibreOffice 26.8.1.1 对照覆盖正负半值和略低于半值的输入。对照归根目录 `.temp/r2/c1-ironcalc-round-reference/`。

在 `test-lab/` 运行 `bun run probe:c1-excelize-numfmt` 可比较 `TestNumFmt` 首张表的 4,290 条数字显示断言。探针保留三条非数值输入的原断言，单独登记。英文星期和月份首字母、尾逗号缩放、累计时长和部分中日韩日期格式依次将精确匹配从 101 增至 135、143、154 和 188。每次新增都保持了既有匹配。剩余 4,102 条差异中，4,042 条格式含 `[$-` 区域标记。台湾和日语的部分月份名称按 ONLYOFFICE 区域表显示，与 Excelize 断言不同。命令有差异时以失败退出。版本、源哈希、断言行号和逐条结果归私有 `.temp/c1-excelize-numfmt/`。

在 `test-lab/` 运行 `bun run probe:c1-excelize-adjust` 可比较 `TestAdjustFormula` 中 19 条普通公式的行列插删断言。17 条在编辑后和保存重开后都精确匹配，涵盖混合引用、单格引用、矩形范围、整行与整列。另两条在写入时触发 `invalid-address`，原用例引用了未创建的工作表 `Sheet 1`。命令保留原断言并以失败退出。版本、源哈希、断言行号和差异归私有 `.temp/c1-excelize-adjust/`。本批未比较数组、共享公式或链式范围。

直接复用本地 `/references` 中已检出的表格引擎测试资产，通过 `.mbtx` 脚本转换为 MoonBit 核心测试：

1. **IronCalc 公式黄金测试集（MIT / Apache-2.0）**
   - 入口：`references/IronCalc/xlsx/tests/calc_tests/`（含 `DATE_AND_TIME`、`FINANCIAL`、`INFORMATION`、`LOGICAL`、`LOOKUP_AND_REFERENCE`、`MATH_AND_TRIGONOMETRY`、`STATISTICAL`、`TEXT` 八大目录及 `arithmetic.xlsx`、`defined_names.xlsx`、`range_operator.xlsx` 等）与 `references/IronCalc/base/src/test/`。
   - 方法：读取工作簿公式单元格，清除缓存后由 MoonBit `Session::recalculate` 重算，保存重开后与原文件缓存值 `<v>` 及错误码逐格比对。
2. **Excelize 数字格式与引用调整向量（BSD-3-Clause）**
   - 入口：`references/excelize/numfmt_test.go`（443 KB 格式掩码用例）、`calc_test.go`（348 KB 公式用例）、`adjust_test.go`（行列插删引用平移用例）及 `references/excelize/test/*.xlsx`。
   - 方法：提取表驱动测试中的 `(format_code, raw_value, expected_display)` 与引用偏移断言，转化为 `modules/formats/src/xlsx` 的 `wbtest` 向量。
3. **ONLYOFFICE Core 剩余专项工作簿**
   - 入口：`references/onlyoffice/DocumentServer/core/Test/Applications/AVSOfficeEWSEditorTest/AVSOfficeEWSEditorTest/TestFiles/`。
   - 纳入样本：`DeleteRowsComplex.xlsx`、`MergeWrongValueSetAsTopLeft.xlsx`、`MergedAreas.xlsx`、`NameRanges_simple.xlsx`、`ChartsSheets.xlsx`、`CSV_confuser.xlsx`、`DataOfVarTypes.xlsx`、`Fibonacci_chain.xlsx`、`Hyperlinks.xlsx`、`MathTwoArgs*Template.xlsx`（8 份双参数数学函数全组合表）及西里尔字母空格文件名样本。

4. **ONLYOFFICE sdkjs 公式与数字格式断言（AGPL-3.0，仅提取数据）**
   - 入口：`references/onlyoffice/DesktopEditors/sdkjs/tests/cell/spreadsheet-calculation/formula-tests/`（11 个文件、544 个 QUnit 块、60,539 条断言）与同目录 `NumFormatParse.js`、`conditionalFormattingTests.js`、`DataValidationTests.js`、`DynamicArraysTests.js`、`PivotTests.js`。
   - 方法：私有 `.mbtx` 脚本解析 `oParser.parse(...)`/`assert.strictEqual(...)` 对，产出 `(公式, 工作表输入, 期望值或错误码, 来源文件:行)` 向量，存入私有 `test-lab`；不复制上游代码到任何公开包。先跑已实现函数族，失败项按函数登记，作为 [R2.5](implemented/r2-architecture-and-performance.md) 算法优先级依据。
5. **LibreOffice 函数自校验表（MPL-2.0）**
   - 入口：`references/libreoffice-core` 的 `sc/qa/unit/data/functions/<类别>/fods`，548 份，固定 revision `2821d29a87b`，用 `git show` 读取。
   - 方法：用固定 LibreOffice headless 转为 XLSX，核心清缓存重算后对比第一张表的 TRUE/FALSE 汇总列；转换产物与原件 hash 一并登记。

---

## C1.3 OOXML 怪异容器与复杂特性集

针对非 Microsoft Office 生成器常见的容器与 XML 变体，引入本地已有的三套测试库：

1. **Calamine 边缘案例集（MIT）**
   - 入口：`references/calamine/tests/`。
   - 首批导入：
     - 字符串与编码：`inlineStr_cdata.xlsx`、`inlineStr_with_value.xlsx`、`empty_shared_string.xlsx`、`empty_shared_string_value.xlsx`、`non_monotonic_si.xlsx`、`rph.xlsx`、`has_x000D_.xlsx`、`has_x000D_inline.xlsx`、`encoded_entities.xlsx`、`whitespace_trim.xlsx`；
     - 命名空间与路径：`nonstandard-xml-ns-prefix.xlsx`、`table_with_absolute_paths.xlsx`、`minimal_package.xlsx`、`empty_s_attribute.xlsx`；
     - 共享公式与表：`issue_565_multi_axis_shared.xlsx`、`issue_567_absolute_shared.xlsx`、`shared_formula_reversed.xlsx`、`table-multiple.xlsx`、`table_with_insertrow_attribute.xlsx`、`pivots.xlsx`。
2. **Open-XML-SDK 官方复杂特性集（MIT）**
   - 入口：`references/Open-XML-SDK/test/DocumentFormat.OpenXml.Tests.Assets/assets/TestFiles/`。
   - 首批导入：
     - DOCX：`Complex01.docx`（847 KB 综合长文）、`complex2010.docx`、`Of16-01.docx` 至 `Of16-08.docx`、`Data-Bound-Content-Controls.docx`、`EmptyRelationshipElement.docx`、`mcdoc.docx`、`mcinleaf.docx`、`Notes.docx`、`svg.docx`；
     - PPTX：`Presentation.pptx`（1 MB 综合演示稿）、`o09_Performance_typical.pptx`（1.5 MB 性能与渲染基准）、`Algn_tab_TabAlignment.pptx`、`animation.pptx`、`mcppt.pptx`、`mediareference.pptx`；
     - XLSX：`Complex01.xlsx`、`excel14.xlsx`、`extlst.xlsx`、`missingcalcchainpart.xlsx`、`vmldrawingroot.xlsx`。
3. **Office Oxide & Anydoc 鲁棒性与保真边界（MIT / Apache-2.0）**
   - 入口：`references/office_oxide/tests/`（`test_robustness_and_safety.rs`、`test_allocation_budget.rs`、`test_docx_ir_fidelity.rs`、`test_pptx_package_fidelity.rs`）与 `references/anydoc/tests/robustness.rs`。
   - 方法：复用其畸形 ZIP/XML 构造模式与保存重开幂等性（Idempotence）断言，验证预算拒绝与错误恢复。

---

## C1.4 PDF 字体、色彩、表单与修复容错集

从本地 `references/pdfjs/test/pdfs/`（989 份）与 `references/pdfium/testing/resources/`（301 份 PDF + 508 份 `.in`）中按未覆盖特征族补充代表样本：

1. **字体与编码**：无 ToUnicode 的 TrueType 子集、Type0 竖排（`Identity-V` / CJK CMap）、含复杂子程序的 Type1/CFF、多字体混合文本提取。
2. **图形与色彩**：径向渐变（Function-based / Radial shading）、Luminosity 软遮罩、DeviceN / Separation 色彩空间回退、嵌套 Form XObject 裁剪。
3. **交互表单与批注**：跨页共享字段、无外观流（`NeedAppearances`）的带值文本/列表控件、常见印章与自由文本（FreeText）批注。
4. **轻度结构容错**：借鉴 PDFium 与 `qpdf` 用例，对尾部多余字节、流 `/Length` 轻微偏差、空对象引用建立受控容错策略（仅在阅读路径容错，保存/脱敏仍遵守严格完整性保护）。
5. **标准与鲁棒性语料**：[veraPDF corpus](https://github.com/veraPDF/veraPDF-corpus)（CC BY 4.0）的 PDF/A 与 ISO 32000 原子用例补只读打开与声明范围；PDFium `testing/resources` 的像素预期 PNG 补独立栅格对照；[Stressful PDF Corpus](https://pdfa.org/stressful-pdf-corpus) 只在隔离环境抽样用于预算拒绝与恢复，不入仓。PDF 上游原件不少于 100 份。

---

## C1.5 多生产工具与 CJK 真实排版集

1. **按生产工具（Producer）分层采样**：
   - 从 `references/apache-tika`（通过 `git show` 提取 `test-documents`）及 [Open Preservation format-corpus](https://github.com/openpreserve/format-corpus) 中选取明确由 **WPS Office、Google Docs/Sheets/Slides、Apple Pages/Numbers/Keynote、LibreOffice、Apache POI、openpyxl、python-docx** 生成的样本。
2. **CJK 专项排版验证**：
   - 覆盖中文习惯字号（初号至八号 pt 映射）、中西文混排间距、行首行尾禁则（Line breaking rules for CJK punctuation）、全角标点与列表编号、竖排文本框及中文表单填写保存。

---

## C1.6 LibreOffice 布局 dump 黄金集

上游 `sw/qa/extras/layout/layout*.cxx` 与 `sw/qa/core/layout/*.cxx` 对 645 份 DOCX 用 `parseLayoutDump()` 的 XPath 断言核对页数、行数、框位置与表格几何。它们比整页像素对照更稳定，也更容易定位差异。

1. **提取**：私有脚本按测试函数抽取 `(文档, XPath, 期望值)`，与原件 hash、来源行号一并登记；原件用 `git show 2821d29a87b:<path>` 读取。
2. **映射**：XPath 中的页/段/行/框对应核心 `layout` 的 `regions`、`semantics` 与绘制几何；单位按 twip 与 pt 换算，容差沿用现有冻结参考规则。
3. **验收**：首批不少于 100 份 DOCX 通过；失败项按特性族登记为缺口，不放宽断言。PPTX 整稿用 `sd/qa/unit/data/pptx` 433 份中的多页原件补 C0.2/C0.3 缺口，首批不少于 100 份上游原件。
