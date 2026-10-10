# G1 — 文档兼容性测试与反馈流水线研究

本研究统一在父仓库维护。历史调查不代表当前 SDK 已实现；当前规则见[测试与反馈](references/testing.md)，产品交付范围见[路线图](references/roadmap.md)。测试代码、数据与原始报告仍私有。

研究日期：2026-10-07。状态：`research`。本文给出源码调查、语料选择和流水线建议，不表示其中全部工具已接入或 SDK 已通过全格式兼容性测试。产品范围由 [SDK 合同](references/sdk.md)决定；P1/P2 当前执行与证据归[测试说明](references/testing.md)，架构参考见 [G0](g0-foundation-review.md)。

## 1. 结论

建议采用 **BetterOffice 的 Office 基准与浏览器采集方式 + LibreOffice 的语义/布局/导出断言 + Office Oxide 的版本差分与外部对照**。不要整体移植任何一个测试平台，也不要把截图相似度当成兼容率。

第一版只需要：固定版本的样本清单、一个调用真实 SDK 的测试入口、几类独立判定器、JSON 结果和静态 HTML 差异报告。CI 负责执行与保存 artifact，不需要先建设数据库、调度服务或质量管理后台。

最值得优先取样的是 LibreOffice 和 Apache POI 的回归文档。它们既有真实格式边界，也常有对应测试说明“这个文件到底在验证什么”。大型网页或企业文档语料适合发现未知问题，但没有完整预期结果，不能直接变成验收集。

需要区分两条比较轴：

- **回归轴**：同一输入在 SDK 上个基准版本和当前版本中的变化。回答“有没有变坏”，看不见两个版本共有的错误。
- **兼容轴**：SDK 与人工确认的 Office 结果、格式断言、独立读取器之间的差异。回答“是不是正确”，但要识别参考引擎本身的限制。

## 2. 哪些项目的测试最值得参考

### 2.1 BetterOffice：最贴近我们的第一版视觉流水线

本地源码并不只有引擎和单元测试。其 [office-quality 工具](https://github.com/elliothux/betteroffice/tree/c10db4b848c1e74c920416986ec2e34bf95ee7f3/scripts/office-quality) 已经把以下步骤串起来：

1. `reference.py` 调用 macOS 桌面 Word、Excel、PowerPoint，导出本地 PDF 和页面 PNG。
2. 记录源文件 SHA-256、Office/macOS 版本、导出状态、DPI、页数和字体名称。
3. 浏览器加载实际 renderer，采集当前源码和已发布包两个通道。
4. `compare.py` 生成逐页 expected/actual/diff、JSON 和静态 HTML。
5. `reference.test.ts`、`results.test.ts` 验证来源匹配、空参考、页数、失败样本及统计覆盖率。

值得借鉴的是证据链，不是单个 SSIM 数字。这里也有明确边界：

- SSIM 在灰度图上计算，可能漏掉颜色错误；整页空白较多时，局部重要内容损坏也可能被平均值稀释。
- XLSX 的指定区域导出不是自动打印分页测试，更不是公式正确性测试。
- 文档指出失败样本不进入相似度均值，因此必须同时看 scored/total；覆盖率不同的均值不能直接比较。
- 某些样本的 Office 和浏览器采用不同但度量接近的字体，不能据此要求像素完全相同。
- 公共 corpus 的入口和清单在源码中存在，但本轮网页工具未能访问该域名；没有核实在线样本数量、可下载性或逐项授权，也没有下载其图片。

结论：优先参考其采集、溯源、差异报告和判定器测试；增加结构、内容、颜色及保存保真检查。不复制其自动更新 README 分数或远程发布流程。

### 2.2 LibreOffice：最值得学习的兼容性断言设计

阅读了 `sw/qa/extras/README`、`sw/qa/inc/swmodeltestbase.hxx` 和 `sw/qa/extras/ooxmlexport/ooxmlexport27.cxx`。其 [Writer 测试说明](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/qa/extras/README) 展示了三种互补方法：

- 导入后断言文档模型的具体属性。
- 导出、重新导入，再断言模型；区分导入已经错了与导出引入了错误。
- 对导出 XML 和排版 dump 做 XPath 断言，定位到特定节点或页面。

在实际测试中，有“图片与文本框应留在第一页”“页眉页脚不参与行号”“某个 DrawingML 节点使 Word 报损坏”等细粒度检查。这比一张整页 golden 更能解释失败原因。

适合我们的做法：核心提供确定性的模型/布局诊断数据，测试能定位到段落、单元格、shape、part 和页。它不是第二份可编辑模型，也不要求把 UNO 搬到 MoonBit。

注意：上游也有只断言不崩溃的测试、有待修复的注释和禁用断言。取文件时必须同时阅读所属测试，不能把“文件在测试目录”解释成所有特征都有正确答案。

### 2.3 Apache POI：格式与公式边界样本的优先来源

阅读了 [TestXWPFDocument](https://github.com/apache/poi/blob/ae62bb5116b9aee19ebd5834e3a82066132c9f7f/poi-ooxml/src/test/java/org/apache/poi/xwpf/usermodel/TestXWPFDocument.java) 和 `TestXSSFFormulaEvaluation.java`，并检查 `test-data/` 清单。

它的优势是格式问题与具体断言相连。例如共享公式的主单元格被求值替换后，其他共享公式仍必须正确计算；不能只检查公式文本存在。DOCX 测试还检查主题字体、metadata、图片内容和部件关系。

适合借鉴其 fixture + bug/test 的组织方式；POI 可作为独立读取/公式辅助检查器，但不是 Word 排版真值，也不能把它没实现的 Excel 函数判为我们的失败。

### 2.4 Office Oxide 与 Tika：持续发现“能打开但内容错了”

[Office Oxide regression-sweep](https://github.com/yfedoseev/office_oxide/blob/7fce6094b46c6a7afd133fedbffe305ddb1929a1/scripts/regression-sweep/README.md) 区分新旧版本状态变化、文本变化、外部参考差异、跨输出格式差异和 round-trip 丢失。它明确指出：词集合看不到重复段落，词频集合才看得到；新旧版本都错时，版本差分不会报警。

可以参考其逐文件结果、失败分类和外部对照，但不照搬词频阈值或“多数一致就正确”。例如 Tika 的 Office 解析依赖 POI，这两个结果不能当成两票独立证据。修订、隐藏文字、页眉页脚、图表缓存也会让提取结果因策略不同而变化。

本轮新读取的 [Tika ExtractComparer](https://github.com/apache/tika/blob/c8d4fa1b6568b8ad69acd5981dcd2197314a2531/tika-eval/tika-eval-app/src/main/java/org/apache/tika/eval/app/ExtractComparer.java) 记录内容、token 差异、编码、附件及解析异常。借鉴其“结果变化 + 错误变化”，不需要在早期引入整套 Java/H2 评估平台。

### 2.5 MoonBit office.mbt：离选型最近，但判定器不能原样信任

[pagelayout_fidelity.py](https://github.com/moonbitlang/office.mbt/blob/2f08f3b8041d9098d258969fe3902b34585163cc/scripts/pagelayout_fidelity.py) 通过 LibreOffice PDF 和 Poppler 的文本坐标比较页数、内容召回、同页情况及位置漂移。它正确区分词频召回与顺序对齐，并避免只拿少量匹配词计算“完美同页率”。

其缓存绑定输入内容和参考引擎身份；脚本也说明尚未覆盖字体与配置的完整指纹。默认目标是 native CLI，不能代替我们的真实浏览器 WasmGC 检查。

另外两个实现要谨慎：

- [semantic_parity.py](https://github.com/moonbitlang/office.mbt/blob/2f08f3b8041d9098d258969fe3902b34585163cc/scripts/semantic_parity.py) 的 fingerprint 主要检查部件数量、类型和关系路径，没有比较所有单元格值和公式语义；不能作为保存无损判定。
- [Open XML validator wrapper](https://github.com/moonbitlang/office.mbt/blob/2f08f3b8041d9098d258969fe3902b34585163cc/tools/openxml-validator/Program.cs) 用错误描述子串匹配 baseline，容易把不同位置的新错误一起忽略；其 Office 版本配置也必须结合我们的支持范围重新选择。

本轮运行了一个只针对 fingerprint 的小实验：在内存中创建两份最小 ZIP 部件集合，唯一差别是 A1 从 `1` 变成 `999`；调用上游 fingerprint 后，两份结果完全相等。该实验成功证明了比较器的覆盖边界，**不是合法 XLSX 验证，也不是 MoonBit 或 SDK 测试**。

### 2.6 IronCalc、ONLYOFFICE 和其他工具

- [IronCalc compare.rs](https://github.com/ironcalc/IronCalc/blob/09e81f53f4c021fc0ec212e95fb353a1c6c5c704/xlsx/src/compare.rs)：按单元格类型及数值容差比较，支持计算测试；但当前实现遍历第一份模型的单元格，且共享字符串分支比较索引，源码已有内容解析比较的 FIXME。跨引擎判定器应比较双方坐标并集及解析后的文本，不能复制这一局限。
- [ONLYOFFICE x2t-testing](https://github.com/ONLYOFFICE-QA/x2t-testing)：提供转换运行框架，但文档中的完整执行需要 S3 凭据和结果服务 token。公开工具不等于其全量语料公开；适合参考转换任务组织，不作为浏览器阶段的数据供应前提。
- [Playwright visual comparisons](https://playwright.dev/docs/test-snapshots)：适合真实浏览器采集、回归截图和交互 trace。官方要求 baseline 与运行环境一致；框架不会替我们决定 Office 兼容性。
- [diff-pdf](https://github.com/vslavik/diff-pdf)：可生成 PDF 视觉差异，项目明确不积极维护。可以作为人工诊断备选，不建议增加为第一版必需依赖。
- [veraPDF corpus](https://github.com/veraPDF/veraPDF-corpus)：按标准条款组织原子 PDF/A、PDF/UA 及部分 ISO 32000 样本，标注 CC BY 4.0。适合未来相关 PDF 输出承诺，不证明 Word 分页正确，也不表示普通 PDF 输出必须通过 PDF/A。

## 3. 可用语料：先取哪些，哪些后置

### 3.1 实际统计的上游文件清单

本轮按固定 commit 的 Git tree、指定路径和扩展名计数，未按内容去重、未验证文件格式、未打开这些二进制文件。以下数字是候选文件数，不是可直接采用的测试数。

| 来源与扫描范围 | DOCX | XLSX | PPTX | 优先用途 |
| --- | ---: | ---: | ---: | --- |
| Apache POI `test-data/` | 181 | 371 | 103 | 包结构、读写、公式与历史缺陷 |
| LibreOffice `sw/qa/`、`sc/qa/`、`sd/qa/` | 2,153 | 396 | 437 | 布局、格式兼容、导入导出缺陷 |
| Tika Microsoft parser 模块 `src/test/resources/test-documents/` | 58 | 33 | 27 | 文本、嵌入对象、异常输入 |

三个范围合计 **3,759 个 DOCX/XLSX/PPTX 路径**，不含旧二进制格式、宏文档和 ODF。样本间可能重叠，也可能是故意损坏或加密的文件；筛选后的数量会更少。

它们的优势不是大，而是可以追溯到测试预期。POI/Tika 的 Apache 许可、LibreOffice 的项目许可都不能代替逐文件来源与第三方声明核对。建议保留原文件、原测试路径、commit、hash、issue 和许可证据；不能统一换上本项目的 Apache-2.0 标头。

### 3.2 数据集分工

| 语料 | 有什么预期结果 | 推荐角色 | 限制与采用条件 |
| --- | --- | --- | --- |
| 自建原子文档 + 指定 Office 版本导出 | 我们明确书写的结构、内容、几何与编辑断言 | 第一优先，长期硬门禁 | 不能只用我们的 writer 生成；补 Word/Excel/PPT 原生保存版本 |
| POI / LibreOffice 回归文档 | 对应测试通常有局部明确预期 | 第一优先，按功能选取 | 不把上游通过解释为整个文档完全正确；逐样本检查授权 |
| BetterOffice corpus | 源码描述包含 Office 页面参考和 provenance | 视觉采集参考及候选补充 | 本轮未核实在线可用性；字体、截图 profile 和授权逐项核实 |
| Tika fixtures | 提取与异常输入断言 | 导入覆盖、未知部件、损坏输入 | 不提供完整编辑或布局真值 |
| SpreadsheetBench | 输入/答案工作簿、任务及结果区域 | XLSX 编辑与计算的补充任务 | 原项目声明 CC BY-SA 4.0；任务结果正确不等于整份工作簿无损 |
| OfficeComprehensionBenchmark | 文档问答与原子断言 | 将来结构提取/Agent API 的补充 | 不是渲染/保存 benchmark；下载转换与许可均有额外条件 |
| Govdocs1 | 大规模混合文件、来源和元信息 | 后期解析鲁棒性、分层抽样 | 不是百万份 Office 文档；无布局 golden；明确存在恶意文件 |
| Enron | 真实表格与相关邮件 | 后期复杂表格与真实使用分布 | 历史数据、敏感内容风险、缺少编辑/视觉答案，不优先全量下载 |
| W3C XML、Unicode 测试数据 | 标准规定的预期行为 | 底层库门禁，从早期开始 | 选择对应标准版本和支持 profile，保留许可声明 |

[SpreadsheetBench](https://github.com/RUCKBReasoning/SpreadsheetBench) 上游报告 912 个任务、2,729 个测试案例，并另有 400 个专家核验任务的子集。它先借 Excel 或 LibreOffice 重算，再用读取工具取缓存值。我们可抽取确定的编辑操作与结果断言，不必引入 LLM 执行整条任务链；也不能让外部 Excel 代算后的正确缓存掩盖我们计算引擎的错误。

[OCB 数据卡](https://huggingface.co/datasets/microsoft/OfficeComprehensionBenchmark) 区分 CDLA-Permissive-2.0 的发布内容和仍受原始授权约束的 URL 引用文件。伴随工具是 MIT；部分源文件经 PDF/HTML 转换为 Office，转换脚本还依赖 Adobe PDF Services。问答判分、转换器产物和原生 Office 兼容性不是同一目标，不作为首批门禁。

[Govdocs1](https://digitalcorpora.org/corpora/file-corpora/files/) 提供约百万级混合文件及较小的子集，并明确警告 corpus 内存在恶意文件。早期成功读取发布页，后续重访超时；本轮未下载。它用于找未知崩溃和极端输入，不用于证明布局正确。

[Enron 发布页](https://figshare.com/articles/dataset/Enron_Spreadsheets_and_Emails/1221767) 标注 CC BY 4.0，整包含邮件约 9.18 GB。公开许可不自动消除隐私与凭据风险；不把邮件正文、姓名和附件不加审核地放进公开 CI artifact。

EUSES、FUSE 也值得列入后续候选，但本轮未同时确认可用的原始下载、明确的逐项复用授权和可作为判定标准的标签，不把论文中的规模数字写成我们可立即接入的数据量。

### 3.3 我们需要自己补的覆盖

真实样本偏向特定年代、语言和生产工具。首批清单要显式包含：

- DOCX：分节、分页、列表编号、表格跨页、浮动图片、页眉页脚、字段、批注/修订和未知扩展。
- XLSX：稀疏数据、共享字符串、共享/数组公式、跨表依赖、日期系统、错误值、样式继承、合并、图表关系和打印区域。
- PPTX：母版/版式继承、主题、组合变换、文本溢出、图片裁剪、表格和 slide 关系。
- 共性：中文标点与断行、中英混排、RTL/组合字符、字体 fallback、空内容、损坏 ZIP/XML、重复/异常 part、资源预算。

这些是取样维度，不表示浏览器首版必须实现全部功能。每个特征分别标记能读、能保留、能显示、能编辑、能输出；“保留但不会渲染”不能报成“完全支持”。

## 4. 判定器怎么设计

### 4.1 分层，而不是一个总分

| 层次 | 检查什么 | 不能由它证明什么 |
| --- | --- | --- |
| 输入与结构 | ZIP/OPC、关系目标、XML、资源上限、schema profile | 排版和计算正确 |
| 语义 | 文字、表格单元格、样式含义、公式、图片/图表引用 | 视觉一致 |
| 保真保存 | 不修改保存、指定编辑、未知内容和相关关系保留 | 我们的 reader 能重开不等于 Office 能重开 |
| 计算 | 当前引擎实际重算及依赖传播结果 | 原文件缓存值正确不等于计算器正确 |
| 布局与绘制 | 页数、文本框几何、换行、溢出、颜色、逐页像素 | 编辑、剪贴板、IME 正确 |
| 浏览器交互 | WasmGC、Worker、选区、输入、撤销、保存下载 | moonrun/native 单测不能代替这一层 |

[Open XML SDK validator](https://learn.microsoft.com/en-us/office/open-xml/word/how-to-validate-a-word-processing-document) 可以作外部格式检查。固定 SDK 版本和 Office profile，区分 Strict/Transitional 及扩展处理，不用所有版本的规则混合判定。

真实输入本身可能带已有 validation error：记录输入 hash、profile、error ID、part、XPath 等精确签名，再检查输出是否新增不允许的错误；不能用描述子串或“错误总数没增加”放行。我们自己新建的合法样本则要求对应结构断言全部通过。

### 4.2 保存至少测三条路径

1. **不修改保存**：导入 → 导出 → 独立工具重开；已支持语义保持，承诺保留的未知内容及依赖关系不丢。
2. **最小编辑**：修改一个单元格/段落/shape → 导出；目标内容改变，未触及范围维持合同。
3. **重复往返**：再次导入导出；发现每次保存持续漂移、重复节点或内容累积丢失。

同时检查 SDK 模型与实际导出部件，避免 importer 和 writer 共享错误却互相“验证通过”。XML 规范化只能忽略明确无语义的差异，例如属性顺序；关系 ID 要解析到目标内容，不得一律抹掉数字。共享字符串和样式也要解析引用后比较。

未知内容保留不仅是未修改 ZIP entry 的 hash：已编辑的 XML part 中的未知属性、命名空间上下文、`mc:AlternateContent` 和关系也需要独立样本。带签名、宏、加密等文档若不支持相应操作，要明确拒绝或报告能力限制，不能保存后静默破坏还返回成功。

DOCX→PDF 等有损转换另列合同：页面和可见内容保持哪些信息，链接/书签/可访问性是否承诺。不用 Office 格式往返规则要求 PDF 可逆。

### 4.3 计算不要被缓存骗过

分别保存公式字符串、输入缓存、SDK 重算值、参考引擎重算值。测试必须改变依赖输入，触发我们的引擎，再比较输出；导出文件交给 Excel 重算后正确，只能证明部分导出语义，不证明我们的计算结果正确。

针对日期 1900/1904、空值/空字符串、错误传播、相对引用、跨表引用等分别写断言。数值采用按函数与条件确定的绝对/相对容差；字符串、布尔、错误种类不模糊比较。易变时间、随机函数、外部工作簿连接单列策略，不能靠“重跑几次总能过”。

### 4.4 视觉比较用“内容 + 几何 + 像素”

先检查页数、文本内容与出现次数，再检查位置、换行和对象边界，最后看像素/颜色差异。词频用于发现重复与丢失；顺序与坐标另查，不能用词频证明阅读顺序正确。

同环境的 SDK 自身回归可以严格；跨 Office/浏览器的参考对比先用于诊断，经过人工标定后才给具体场景设阈值。字体抗锯齿误差和整段换页不是同一种误差；禁止自动缩放/对齐截图掩盖页面尺寸和定位问题。

固定并记录：引擎版本、浏览器/OS、字体文件 hash、字体解析结果、DPR、缩放、DPI、locale、时区、导出 profile 和参考文件 hash。字体加载完成不等于正确字体被选中。打印布局和屏幕布局分开比较；不要为整张大表的屏幕截图强行套打印 golden。

自己的布局 dump 有助于定位，但仍须观察实际 Canvas/PDF 输出，否则绘制后端丢内容无法发现。

### 4.5 谁提供参考答案

如果目标是“接近 Microsoft Office”，使用指定版本 Word/Excel/PowerPoint 的人工核验产物作为重要参考。LibreOffice 是便于自动化的第二引擎，不替代 Microsoft Office，也不能用三家引擎多数投票替代规范和人工判断。

建议把基准生成与日常 CI 分开：受控、有适当授权的桌面环境生成并审核 golden；普通 CI 使用固定产物。并非每次提交都打开桌面 Office。

Microsoft 对[无人值守、非交互式服务端 Office 自动化](https://support.microsoft.com/en-us/visio/considerations-for-server-side-automation-of-office)有明确支持限制，不能假设装上 Office 和 COM 就成为稳定的 CI 服务。后续真要自动化生成，需单独核对适用授权、运行方式和可靠性；也不能把需要许可的字体直接提交到公开仓库。

### 4.6 判定器本身也要有失败测试

至少让它抓住：删除一段文字、重复表格行、改单元格值、交换图片关系、改变颜色、漏一页、增加一个隐藏单元格、公式缓存未更新、错用另一个文件的参考图、空结果和过期缓存。

空白文档可以是合法样本；“应有内容但变成空白”和“没执行任何测试”不能通过。每次运行核对 manifest 的 expected/executed 数量，区分失败、已知不支持、缺参考、超时与基础设施错误。

## 5. MoonBit + WasmGC 的具体落点

核心算法测试继续在 MoonBit 中，测试编排和外部验证放在开发工具中。这里的 TS/Python/.NET/Java 是测试宿主，不进入生产 SDK；“薄 TS 产品层”不等于测试也必须全用 MoonBit 重写。测试工具仍须核对自身及依赖许可，不能因为不随 SDK 打包就忽略授权条件。

[MoonBit core/quickcheck](https://mooncakes.io/docs/moonbitlang/core/quickcheck) 已提供属性测试、随机生成、缩小反例和结构化报告；[官方说明](https://www.moonbitlang.com/blog/property-based-testing-moonbit)支持固定 seed。API 仍需跟随项目实际固定的工具链，不混用早期独立 quickcheck 包的例子。

优先测具体不变量：合法子集的 parse/serialize 语义一致、ZIP entry 顺序不影响模型、撤销编辑恢复语义、无关单元格编辑不改变其他值、一次性与分块读取结果一致。生成器按实际支持范围构造输入，不能让大量 discard 冒充覆盖。

浏览器能力必须通过真实浏览器加载实际 WasmGC 产物，经正式 TS/Worker 调用边界执行。moonrun 可用于快测，但不覆盖浏览器资源加载、Worker 生命周期、传输开销、字体及 Canvas；native 跑过也不是浏览器证据。

初期以一个固定浏览器作为快速通道，其他声明支持的浏览器独立执行；不能把 Playwright WebKit 的结果直接宣称为所有 Safari 版本保证。CLI 和其他 runtime 在 P9 增加同一批合同用例，不预建多语言 SDK 矩阵。

模糊测试先从有 seed 的截断、长度/关系/编码变异和 XML/ZIP 边界开始，失败输入自动保留。后续再验证覆盖率引导工具与 MoonBit 目标是否真正接通；[OSS-Fuzz 当前语言说明](https://github.com/google/oss-fuzz)不能作为 MoonBit WasmGC 已获原生支持的证据。

[W3C XML conformance suite](https://www.w3.org/XML/Test/) 和 [Unicode 测试向量](https://www.unicode.org/Public/UCD/latest/ucd/auxiliary/) 比手写几十个 XML/断行例子更适合验证底层库。引入时固定实际版本，不能让 CI 每次取 `latest`；XML 解析器的非验证/禁止外部实体等 profile 必须与测试选择一致。

## 6. 最小可用流水线与反馈循环

```text
有来源与授权记录的样本 + 明确断言 + 固定参考产物
                         ↓
              manifest 校验与样本选择
                         ↓
       真实 SDK：导入 / 预览 / 指定编辑 / 保存
                         ↓
     结构、语义、重算、往返、几何、视觉分项检查
                         ↓
           JSON 结果 + 可打开的失败差异报告
                         ↓
       缩小复现 → 修复一般规则 → 重跑相关回归集
```

### 6.1 三档执行，不一开始跑全量

| 执行档 | 内容 | 输出与用途 |
| --- | --- | --- |
| 每次变更 | 判定器自测、原子用例、相关格式回归、真实浏览器小样本 | 快速阻止内容损坏、关键功能回退和运行边界错误 |
| 夜间/按需扩展 | 更多上游样本、分片往返、额外浏览器、随机 seed、资源预算 | 发现覆盖缺口；新发现先分诊，不自动重写 golden |
| 发布前/基准变更 | 全部声明支持范围、Office 人工复核、候选基准审阅、固定环境性能 | 决定能承诺什么，不用混合平均分决定发布 |

这只是建议的执行策略，本轮未创建 CI 或定时任务。改动 ZIP/XML/公共文本层时应扩大关联范围，不能机械地只跑一个格式。准确执行时长需要 SDK 实现后测量；当前不承诺几分钟跑完几千文件。

可从首个完整格式的 **30–50 个有明确断言的案例** 起步，覆盖原子行为、真实回归和失败路径，再扩到数百个筛选输入。数量是实施建议，不是验收指标；第一批没有可靠 oracle，堆到一万份也没有意义。

### 6.2 样本清单和产物

每个 case 至少记录：稳定 ID、原始 URL/commit/路径、SHA-256、许可及来源说明、生成工具、格式与特征、执行操作、预期能力/失败类型、参考产物身份。一个文件可以对应多个操作，不把文件数等同测试数。

小型合法样本和人工断言可进 Git；大文件与基准图按 hash 固定到本地缓存或受控 artifact 存储。PR 离线使用已固定样本，不临时抓取网页最新内容。保存原始输入，不用预处理转换覆盖它。

失败结果应包含 case、阶段、SDK revision、构建产物 hash、runtime、seed、part/XPath 或页/单元格、expected/actual、耗时和 artifact 路径。HTML 汇总源码版本与样本身份，提供原文件、导出文件、结构 diff 和逐页图片；私密语料不公开这些文件。

给 Agent 的反馈首先是精确断言，例如“编辑 B2 后 Sheet2!D7 的值由 17 变为 0”，而非“SSIM 0.87”。Agent 可以归类、最小化样本并修复通用规则，不得按文件名/hash 特判，也不得为了通过自动修改预期结果。

### 6.3 统计与基准更新

分格式、功能、生产工具、语言和操作报告覆盖；在私有报告中记录 planned/executed/pass/fail/unsupported/missing-oracle 数量。崩溃或缺参考不能从分母静默消失。未承诺功能可处于探索集，但必须显式显示，不能并入支持率。

保留一部分未用于日常调试的真实样本作留出集；内容去重、模板聚类和生产工具分层可以防止同一模板上千份刷高通过率。兼容率只描述这份版本化样本及判定条件，不声称覆盖世界上所有 Office 文档。

基准变更需要说明来源、差异和批准理由。Office、字体、浏览器升级与 SDK 改动尽量分开评估；不把更新全部 snapshots 作为消除失败的方法。已知失败必须绑定具体 case/能力/原因，不做宽泛忽略。

### 6.4 性能和不可信输入

分别记录解析、首次布局、首次可见绘制、编辑重算/重排、保存和跨 WASM 边界开销；冷启动、暖运行、包下载大小分开。对大图、多页、稀疏表、复杂公式等不同负载各设基准，不用一份小文档推断性能。

WasmGC 的对象不都在线性内存中，不能只用 `memory.buffer.byteLength` 当峰值内存。结合可用的浏览器/进程指标，记录测量范围；共享 CI 上的单次耗时仅作告警，在受控环境复测后判断回退。

外部 corpus 默认不可信：隔离转换进程与浏览器，禁止宏、外部链接自动更新和网络取资源，限定 CPU/时间/内存/解压量，输入只读且不挂载凭据。需要字体和图片的正常样本由宿主显式提供已固定资源。桌面 Office 自动化权限不是处理任意恶意文件的安全沙箱。

## 7. 实施顺序与尚需决定的事项

建议先做一条最小纵向链路：选首个格式和一组明确功能 → 选原子及真实样本 → 独立 oracle → 浏览器真实产物 → 一次编辑和保存 → 可读失败报告。完成之后再加更多语料、夜间分片和复杂统计。

进入实施前需确定：

1. 首个完整格式及具体支持特征；不能让测试建设反过来默认三种格式同时全做。
2. Microsoft Office 是否是主要视觉目标，以及使用哪个平台/版本生成参考；LibreOffice 的偏差单独记录。
3. 哪些字体能合法在浏览器和参考环境使用；缺字、fallback 是否允许。
4. 哪些公开样本允许随仓库分发，哪些仅限私有缓存；用户文档如何获得授权并脱敏。
5. 首批性能预算与浏览器支持范围；需要真实实现测量后填写，不从参考项目抄数字。

本轮不建议建设通用测试平台，也不建议把参考引擎嵌入生产 SDK。测试工具可多语言、可在 CI 使用本机程序；生产依然遵守 MoonBit + WasmGC + 薄 TS 的边界。

## 8. 本轮证据与复现范围

研究以下固定源码快照。使用浅克隆、blob filter 和 `--no-checkout`，通过 Git tree 与按需读取源码研究，没有全量检出/解压文档语料，也没有构建这些项目；本机研究副本不作为阅读入口或测试前置条件。

| 固定源码入口 | commit |
| --- | --- |
| [apache/poi](https://github.com/apache/poi/tree/ae62bb5116b9aee19ebd5834e3a82066132c9f7f) | `ae62bb5116b9aee19ebd5834e3a82066132c9f7f` |
| [LibreOffice/core](https://github.com/LibreOffice/core/tree/2821d29a87b28785d74fa64d975465e4c99d4416) | `2821d29a87b28785d74fa64d975465e4c99d4416` |
| [apache/tika](https://github.com/apache/tika/tree/c8d4fa1b6568b8ad69acd5981dcd2197314a2531) | `c8d4fa1b6568b8ad69acd5981dcd2197314a2531` |

其他重点源码快照：BetterOffice `c10db4b848c1e74c920416986ec2e34bf95ee7f3`（相邻项目已有副本）；office.mbt `2f08f3b8041d9098d258969fe3902b34585163cc`；IronCalc `09e81f53f4c021fc0ec212e95fb353a1c6c5c704`；Office Oxide `7fce6094b46c6a7afd133fedbffe305ddb1929a1`。

计数使用 `git ls-tree -r --name-only HEAD -- <范围>`，按小写扩展名汇总路径；不是测试运行。Tika 范围为 `tika-parsers/tika-parsers-standard/tika-parsers-standard-modules/tika-parser-microsoft-module/src/test/resources/test-documents/`。首次对整个 LibreOffice tree 使用 Node 默认输出缓冲时遇到 `ENOBUFS`，改为限定路径和足够缓冲后计数成功；这不是文档解析失败。

实际执行的比较器实验：macOS，Python 3.14.7，`python3 -B` 导入 office.mbt 的 `semantic_parity.fingerprint`，以 `io.BytesIO`/`zipfile.ZipFile` 构造 workbook 和 worksheet 两个部件；A1 分别为 1 和 999，断言源字节不同且 fingerprint 相等，退出码 0。未写入上游文件。

本轮未运行 Office/LibreOffice 导出、浏览器采集、公式评测或 SDK 用例，没有跨项目兼容率/性能实测。网站上的数据集统计是发布方说明；本地文件计数和上面的 fingerprint 实验才是本轮实测。

## 9. PDF 专项补充

本节补充 PDF 输入、渲染、编辑和输出测试。前面的 OOXML 语料统计不包含 PDF。当前产品方案明确列出的 Office 输入格式是 DOCX/XLSX/PPTX；本研究不自动把任意 PDF 编辑或 PDF→Office 纳入首版承诺。

### 9.1 先拆分能力，避免混成“支持 PDF”

| 能力 | 主要验收内容 |
| --- | --- |
| Office → PDF / PDF 创建 | PDF 结构、字体、页面画面、文本可提取性，以及明确承诺的链接、书签、标签 |
| PDF 读取与预览 | 对象解析、内容流、字体/图片解码、图形状态、页面几何与最终绘制 |
| PDF 文字提取 | Unicode 映射、顺序、坐标、重复/隐藏文字；扫描件无文本与解析丢失分开 |
| PDF 批注、表单和页面操作 | 修改值及外观流一致，保存后其他阅读器能正确显示，未修改对象保持 |
| PDF 原有文字/图形编辑 | 不同字体子集、编码、资源共享和绘图操作下的实际内容修改，不能仅覆盖一个文本框 |
| PDF → DOCX/XLSX/PPTX | 内容与结构重建；不承诺原始 Office 对象的可逆恢复，OCR 单列 |

PDF 内容不一定提供段落、表格和阅读顺序；画面上的一行文字可能对应多个定位绘图操作，也可能已经是图片或轮廓。因此，“渲染成功”“能复制文字”“像 Word 一样编辑”是独立承诺。

### 9.2 最值得参考的项目与源码

**PDF.js：浏览器测试的首要参考。** 本轮检查了 [test/driver.js](https://github.com/mozilla/pdf.js/blob/24de17e81b3357b30ffd710ec080be00d65ac98d/test/driver.js)、`test/test.mjs` 和 `test/test_manifest.json`。manifest 分开列出像素参考、文本层、加载等任务；`driver.js` 的保存用例会设置 annotation storage，调用 `saveDocument()`，销毁旧文档后重新加载输出，不只是检查当前 UI。

它适合参考浏览器采集、文字层/批注层分测、保存重载。PDF.js 的快照是该引擎的回归预期，不天然是所有 PDF 的标准答案。标为 `other` 的条目服务其他测试套件，不执行普通 reference test；`load` 也不能当视觉通过。

**PDFium：最小 PDF 样本与像素测试的首要参考。** [README 的测试章节](https://github.com/chromium/pdfium/blob/a84323421e94f484faca52dd9d027934eba42ab8/README.md)区分 unit、embedder、corpus、JavaScript、pixel 测试；本轮读取的 `run_pixel_tests.py` 和 `run_corpus_tests.py` 都要求 expected images。

其 `.in` 文件是带占位符的文本 PDF 模板，由 `testing/tools/fixup_pdf_template.py` 补齐偏移等信息。它非常适合缩小反例：去掉不相关对象后重新生成有效 PDF，不必每次手工修 xref。我们可以借鉴这一方法生成原子用例，不必复制整个 Chromium 构建系统。字体和渲染配置仍需固定。

**qpdf：结构检查器，不是完整 PDF validator。** [`qpdf --check`](https://qpdf.readthedocs.io/en/stable/cli.html#option-check)检查文件结构等问题，但官方明确说明无错误也可能存在内容流或规范问题；退出码 3 是警告，不能当无条件通过。输入容错与生成文件的合法性分别判定，不能先修复输出再拿修复后的文件替 SDK 过关。JSON 对象信息可辅助检查，但不依赖原始对象编号保持不变。

**MuPDF：独立渲染和提取对照。** [`mutool draw`](https://mupdf.readthedocs.io/en/1.28.5/tools/mutool-draw.html)提供栅格输出、文本等诊断能力，可作为 PDFium/PDF.js 分歧时的额外证据。它采用 [AGPL 或商业许可](https://mupdf.readthedocs.io/en/1.28.5/license.html)，不能顺手作为我们的宽松授权 SDK 默认组件；测试用途也要核对具体使用和分发条件。本轮只查官方工具文档，未审计其测试源码或运行工具。

**Arlington：规范规则参考。** [Arlington PDF Model](https://github.com/pdf-association/arlington-pdf-model)提供机器可读对象定义及完整性关系，适合补充结构规则；项目明确不定义完整词法、内容流操作符以及增量更新/xref 等文件结构规则。不能把接入 Arlington 等同完整规范符合性，更没必要在第一版另造一个全功能 validator。

### 9.3 PDF 数据集选择

| 来源 | 推荐用途 | 预期结果和限制 |
| --- | --- | --- |
| PDFium `testing/resources/` | 原子图形、字体、解析和缺陷回归 | `.in` 模板与相关测试很适合定位；目录中不是每个文件都有视觉 golden |
| PDF.js `test/pdfs/` + manifest | 浏览器渲染、文本层、批注/表单、真实问题文件 | 有内置文件也有外链；固定文件 hash、页范围和具体测试类型 |
| PDF Association PDF Differences | 跨阅读器分歧、规范边界 | 最小文件及解释性预期，适合作为首批难例 |
| veraPDF corpus | PDF/A、PDF/UA 及部分 ISO 32000 原子规则 | 只采用目标 profile；含正反例，不能要求所有输入都通过 |
| Stressful PDF Corpus | 后期畸形输入、崩溃、超时和极端资源用量 | 大型缺陷附件集合，无统一正确画面；逐项来源和授权仍需核实 |
| Ghent PDF Output Suite | 未来印刷、透明度、色彩输出验证 | 面向印刷流程；不作为普通浏览器预览的默认验收集 |

[PDF Differences](https://github.com/pdf-association/pdf-differences)有一个重要说明：README 中的截图经过缩放，**不能直接做像素 golden**；正确结果要结合每个案例的解释，重新生成固定条件的参考。其 PDF 文件采用 CC BY 4.0，源码采用 Apache-2.0，不能只读仓库顶部的许可标签。

[Stressful PDF Corpus](https://pdfa.org/stressful-pdf-corpus/)发布页说明：2020 年汇集 35 个 issue tracker、32 种 PDF 技术的附件，超过 32,500 个 PDF、约 31 GB。这是发布方历史统计，不是本轮下载或验证的数量。对浏览器阶段的价值主要是抽样发现输入边界，不应把这些文件统一列为“必须正确渲染”。

[Ghent 官方入口](https://gwg.org/gos5/)可检索到 Output Suite 信息，但本轮直接打开失败，没有确认当前下载条件与许可；先保留为印刷需求出现后的候选。

本轮固定 commit 的清单统计：

| 范围 | 统计 |
| --- | --- |
| PDF.js `test/test_manifest.json` | 1,403 条任务，引用 1,229 个唯一 file 路径；523 条任务标记 `link` |
| 同一 manifest 的任务类型 | `eq` 1,240；`text` 80；`load` 57；`other` 20；`fbf`、`highlight`、`extract` 各 2 |
| PDF.js `test/pdfs/` Git tree | 989 个 `.pdf` 路径，460 个 `.pdf.link` 路径 |
| PDFium `testing/resources/` Git tree | 301 个 `.pdf` 路径，508 个 `.in` 模板路径 |

任务数、唯一输入路径数、Git 内文件数和外链数不是同一统计口径，不相加计算测试覆盖；外链未下载，模板未生成，二进制样本未执行。代码许可不自动替第三方文档或嵌入字体授权。

### 9.4 PDF-specific 判定与负例

- **文件结构**：xref table/stream、object stream、增量更新链、对象引用、page tree、filter、加密和截断；区分严格接受、带诊断恢复、拒绝及超限。生成文件不应靠阅读器静默修复才可用。
- **绘制**：MediaBox/CropBox、旋转与 UserUnit、嵌入/未嵌入字体、CMap/ToUnicode、Type 3、透明度组、soft mask、裁剪、混合模式和颜色空间。固定后端、字体、DPI、颜色配置、批注与可选内容层的显示状态。
- **文本**：显示的字形正确不等于 Unicode 提取正确。给自建文档明确 expected text，分别检查内容、坐标及阅读顺序；对扫描 PDF 标记“无文本层”，不能把 OCR 猜测当作解析结果。
- **批注与表单**：既检查字段值，也检查 appearance stream；保存后用另一引擎重开。测试屏幕显示与打印行为、旋转后坐标、资源引用，不能只看输入框当前显示值。
- **原有内容与保存**：检查共享资源、页面外对象、链接、书签、附件、metadata 和承诺保留的标签。使用对象语义和可见内容比较，不要求整文件或对象编号恒等。
- **签名与修订**：签名图像不等于密码学数字签名；新增修订是否允许、旧签名覆盖哪个版本、验证状态是否变化需要单独验证，不能承诺普通编辑自动保持签名有效。
- **若以后提供 redaction**：黑色覆盖矩形不等于内容移除；检查提取、内容流、历史增量修订、附件等路径是否仍保留目标信息。该能力单独验收，不隐含在普通批注编辑中。

判定器反向测试要加入：去掉 ToUnicode 但仍能显示、表单值改了但外观没改、漏掉 transparency/clip、错误 CropBox、过期 appearance、仅画签名图片、黑框下仍有文字。它们证明“像素一致”和“内容正确”不能互相替代。

### 9.5 两条最小测试链路

**Office → PDF：** 先从已知模型生成 PDF，执行结构检查，再用 PDFium/PDF.js 等独立引擎读取与渲染，核对文本、字体、页数、几何和图像。之后与指定 Office 导出的参考页面比较，以区分 Office 排版错误与 PDF 后端错误。不能仅用我们自己的 PDF renderer 验证我们自己的 writer。

**PDF 输入与编辑：** 固定输入 → 我们的真实 WasmGC 路径 → 提取/渲染/明确的一次编辑 → 保存 → 外部引擎重开 → 检查目标变化及非目标不变性。PDF.js 可作为测试宿主中的对照，不能用它代跑我们的 PDF 核心后宣称 MoonBit 路径通过。

初期使用 qpdf + PDFium 作为结构/栅格检查候选，PDF.js 负责浏览器参考与不同引擎交叉检查；分歧样本再人工结合规范和其他引擎裁决。需要 PDF/A 或 PDF/UA 承诺时加入 veraPDF；通过自动化规则不等于语义阅读顺序和可访问性已经完整验收。MuPDF 不作为第一版必须依赖。

PDF 仍使用前文的 manifest、JSON/HTML 报告及分档执行，不另建流水线平台。先选择少量按特征分类的原子与真实样本；把大型 stressful corpus 留到隔离环境下扩展测试。禁用脚本、Launch action、自动外链及嵌入文件执行，限制对象深度、解码后图像大小、内容流操作数和时间；不能只限制压缩文件体积。

### 9.6 本轮补充证据

2026-10-07 研究固定快照：[PDF.js](https://github.com/mozilla/pdf.js/tree/24de17e81b3357b30ffd710ec080be00d65ac98d) 与 [PDFium](https://github.com/chromium/pdfium/tree/a84323421e94f484faca52dd9d027934eba42ab8)。采用浅克隆、blob-filter、无工作树检出，通过 `git show` 阅读上述文件，Node 解析 manifest，`git ls-tree` 统计路径。

没有安装或构建 PDF 引擎，没有下载外链/大型 corpus，没有执行 PDF 渲染或编辑测试。上述数值是清单统计，不是通过率。PDF.js/PDFium 原生与 JS 能力也不证明 MoonBit 实现已经具备相同能力。

返回[文档索引](README.md)。
