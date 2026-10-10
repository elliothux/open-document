# G1 — 文档兼容性测试与反馈流水线研究

本研究统一在父仓库维护。历史调查不代表当前 SDK 已实现；当前规则见[测试与反馈](references/testing.md)，产品交付范围见[路线图](references/roadmap.md)。测试代码、数据与原始报告仍私有。

初次研究：2026-10-07；流水线与 Agent 闭环设计补充：2026-10-10。状态：`research`。本文给出源码调查、语料选择和流水线建议，不表示其中全部工具已接入或 SDK 已通过全格式兼容性测试。产品范围由 [SDK 合同](references/sdk.md)决定；P0–P3 当前执行与证据归[测试说明](references/testing.md)，架构参考见 [G0](g0-foundation-review.md)。

本轮具体建设方案从[第 10 节](#10-librarybrowser-测试与-agent-改进闭环设计2026-10-10)开始：包括现状差距、执行分层、真实语料、性能判定、Agent 报告和分批落地。第 2–9 节保留上次调查及其日期边界；其中初版建议不覆盖本轮设计或当前执行合同。

## 1. 结论

建议以 **LibreOffice 的语义/布局/导出断言为主，Collabora 的浏览器交互与诊断为补充**；实现兼容性与逻辑同时参考 ONLYOFFICE。BetterOffice 的 Office 参考采集和 Office Oxide 的版本差分仍可借鉴，不作为测试用例的首要来源。不要整体移植任何一个测试平台，也不要把截图相似度当成兼容率。

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

## 10. Library、Browser 测试与 Agent 改进闭环设计（2026-10-10）

### 10.1 目标、约束和本轮边界

用户确认这里的 RSI 指「Agent 根据测试反馈持续修复代码、复测和积累回归用例」，不指训练模型或让 Agent 自行重写评价标准。

目标：同一批可追溯文件，在 library 和 browser 两条路径运行功能、兼容与性能测试；失败报告直接支持 Agent 复现、定位、修复和验证。改进必须由冻结的外部预期和回归集证明，不能只看 Agent 自己新增的测试。

本轮交付是设计报告，不是流水线已落地。保留现有 MoonBit + WasmGC + 薄 TS、Bun、Playwright、私有 `test-lab/` 和根 `bun run test`。不新增质量平台、数据库、常驻调度服务、通用测试 DSL 或产品 CLI；不部署 CI、不设置定时任务、不提交或推送。阶段边界仍归产品路线图。

报告设计放父仓库；具体输入、断言、失败任务、运行报告和可执行工具全部私有。真实文件可能包含敏感内容，不进入公开 PR 日志，也不默认上传第三方 Agent 服务。

### 10.2 现有基础与实际缺口

以下是本轮对工作树源码和配置的检查，不是重新执行后的通过声明。工作树存在并行修改；历史通过数见维护文档，本轮不拿它们证明当前源码通过。

| 已有基础 | 本轮看到的缺口 | 建议的最小补充 |
| --- | --- | --- |
| 根 `bun run test` 调用私有 `tools/loop.mbtx` | 顺序执行，前置失败后只有阶段状态；尚无所有层次的统一报告 | 保留入口，增加启动时计划、逐步事件和最终汇总；被阻断的任务也有记录 |
| MoonBit WasmGC overlay 测试、Bun 单元/集成测试 | Bun 单元中有不少是语料和判定器检查，不能等同完整 library API 验收 | 增加实际包入口的 WasmGC library 合同测试 |
| Chromium 正式 Worker、Canvas、PDF 验收 | 目前只有一个浏览器项目；浏览器报告依赖测试标题匹配固定全集 | 使用稳定 case/operation/surface/profile 身份；分片仍检查完整集合 |
| 源码、私有输入、Wasm/JS hash | 身份采集主要从浏览器开始，未覆盖完整构建窗口 | 构建前固定 snapshot，所有执行路径使用同一产物 |
| JSON/HTML、trace、截图、逐例附件 | 缺少跨 Moon/Bun/浏览器的统一差异、问题聚类和 Agent 任务包 | 一个规范化结果模型，派生 Markdown/HTML 和失败索引 |
| 四个 POI DOCX；三个有六页 LibreOffice 参考 | 没有 Word 参考应用重开证据；样本规模与来源分布很窄 | 按特征增补 LibreOffice 回归文件，并独立建设微软基准 |
| 记录冷/暖调用等计时 | 无重复采样、成对基线、噪声判定与可靠峰值内存 | 单独的固定机器 benchmark 通道，不把单次测试耗时当性能结论 |
| 错误预期、漏测的负向探针 | 尚不能证明整份新报告或 Agent 闭环可靠 | 增加报告缺失、构建失败、超时、产物变更、错误参考等故障验收 |

特别注意：目前 `compareReference` 将空白去掉后比较文本，并用词的纵横坐标排序。它可以服务当前小样本，但不能直接扩成保真文本、双向文本或多栏阅读顺序的通用判定器。扩语料时先按语义、逻辑顺序、几何分别比较，不能为迁就旧比较器放松文档合同。

### 10.3 本轮源码参考：学什么，不照搬什么

| 项目与已检查证据 | 采用的方法 | 不照搬的部分 |
| --- | --- | --- |
| [LibreOffice Writer 测试说明](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/qa/extras/README) | 模型、布局、导出 XML、往返独立断言 | UNO、C++ 构建体系及把自身重读当唯一正确性来源 |
| [LibreOffice Calc 性能测试](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/qa/perf/scperfobj.cxx) | 给具体操作划计量区间，同时检查结果 | Callgrind 原生指标不能当 WasmGC 浏览器指标 |
| [Collabora 测试说明](https://github.com/CollaboraOnline/online.mirror/blob/033854ea356ba65dae6618297257366cddb05bdf/cypress_test/README)、[缩放重绘案例](https://github.com/CollaboraOnline/online.mirror/blob/033854ea356ba65dae6618297257366cddb05bdf/cypress_test/integration_tests/desktop/writer/zoom_redraw_spec.js) | 真实交互、截图与行为断言、失败日志；以后需要协作时参考干扰测试 | 不引入协作产品、不迁移到 Cypress；不采用其 CI 自动重试和关闭浏览器安全检查的配置 |
| [ONLYOFFICE sdkjs CI](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/.github/workflows/check-build.yml) | 浏览器执行 API、公式、段落、表格、塑形、样式等分领域测试 | 有公开 CI 不等于全部测试或全量转换语料公开；不复制未固定依赖安装和 `--no-sandbox` |
| [ONLYOFFICE x2t-testing](https://github.com/ONLYOFFICE-QA/x2t-testing/blob/540e4308ce1fd4d7ea41220cc66b85fd03a74ae7/README.md)、[公开单元 CI](https://github.com/ONLYOFFICE-QA/x2t-testing/blob/540e4308ce1fd4d7ea41220cc66b85fd03a74ae7/.github/workflows/unit_test.yml) | 按输入/输出格式组织转换任务 | README 的全量测试依赖 S3 和结果服务凭据；公开单元 CI 不证明其全量功能 suite 已运行 |
| [Office Oxide regression sweep](https://github.com/yfedoseev/office_oxide/blob/7fce6094b46c6a7afd133fedbffe305ddb1929a1/scripts/regression-sweep/README.md) | 上一基线/候选版本、真实文件、外部对照、保留逐文件结果 | 多数引擎一致不是最终 oracle；并行负载下的超时不直接判性能回退 |

这次补充确认了 ONLYOFFICE 有具体领域测试的公开执行配置；不再只凭 WebDriver 框架评价它。上述是源码证据，没有构建或执行这些上游 suite，不能由此给它们排兼容率或运行覆盖率名次。

### 10.4 执行架构：一个计划，两条路径，独立判定

```text
冻结源码/工具链/语料/参考 → 构建一次 → 冻结实际执行计划
                                      ├─ library：MoonBit 算法 + 正式包 API
                                      └─ browser：Worker + Canvas + 宿主交互
                                                  ↓
                           结构 / 语义 / 往返 / 布局 / 绘制判定
                                                  ↓
                         统一结果 + 原始证据 + Agent 失败任务包
                                                  ↓
                 授权 Agent：复现 → 最小反例 → 修复 → 扩大回归
                                                  ↓
                           冻结判定器验收，保留前后两次报告
```

性能单独消费相同产物和固定工作负载，串行计量，结果汇入同一报告。不要让性能测量与构建、截图、语料扫描争抢 CPU。

**Library 分两层。**

- 算法层：沿用私有 MoonBit overlay，运行 WasmGC 下的 ZIP/XML/OPC、模型、文本与布局测试；有界属性测试记录 seed、生成器版本和缩小后的输入。moonrun 结果只标记算法层。
- 包合同层：从本次 tarball 安装真实包，通过 `@open-document/wasm/engine` 的 `loadEngine` 执行导入、查询、修改、布局、导出与资源释放。检查 export map、错误类型身份、调用顺序、多个 session、失败后状态和产物完整性，不直接 import `src/` 绕过打包。
- 首个包合同宿主建议固定版本 Node，由私有 runner 启动；先探测实际 WasmGC + `js-string` builtins + 当前桥接所需能力。不要假设用 Bun 编排就意味着 Bun 能执行该产物。能力缺失记宿主不可用，不能切 native 后报 library 通过。浏览器直接调用包 API 的补充探针可独立执行，但不冒充 Node 结果；该测试宿主不扩展产品的跨宿主支持承诺。

**Browser 分两类。**

- SDK 集成：保持真实 `@open-document/web` → Worker → WasmGC；测试启动、资源载入、取消/销毁、超限、错误传播、Canvas、PDF、下载和重新打开。相同 case 与 library 比较模型、导出语义和诊断，双方都还要过独立 oracle。
- 用户交互：测试宿主只调用正式 SDK；P3 检查预览/缩放/滚动/多页/生命周期，P4 有编辑接口后才增加选区、输入、撤销和剪贴板。不能通过私有测试接口直接修改模型后宣称键盘或 IME 通过；合成 composition 事件不等于真实 OS 输入法验收。
- Chromium 继续做当前硬门禁。先对 Firefox/WebKit 做产物能力探测和兼容性试跑，再决定支持矩阵；必选浏览器缺失必须阻止完整通过，不是 skip。Playwright WebKit 不等同所有 Safari，真实 Safari/移动端验证另记环境。

共享的是文件、操作数据、预期与报告格式，不是第二份产品实现。只抽取当前重复的 load/query/edit/export 等调用适配，不创造能够解释任意脚本的测试语言。

### 10.5 覆盖矩阵与判定顺序

每项分别记录「读取、保留、显示、编辑、输出」的支持范围，按 `format × feature × operation × surface × runtimeProfile` 查询覆盖。一个文件可以有多个 case；文件数、case 数、断言数和执行数分别报告。

| 范围 | 功能检查 | 兼容检查 | 性能检查 |
| --- | --- | --- | --- |
| 公共底层 | 正反输入、预算边界、原子失败、可重复调用 | 固定 XML/Unicode 向量、独立 ZIP/XML 检查 | 解压、解析、塑形、边界复制与资源量 |
| DOCX library | 查询、节点编辑、布局、保存；相邻未改区域不变 | 模型属性、导出 XML、未知内容、独立重开 | 导入、冷/暖布局、保存、PDF 导出 |
| DOCX browser | Worker 生命周期、资源失败、实际绘制与下载 | 页数、文字及出现次数、逻辑顺序、几何、颜色、局部像素 | 用户请求到首个正确页面、逐页绘制、主线程卡顿 |
| P4 以后编辑 | 输入、选区、撤销、重新加载；API 与 UI 分测 | 编辑后 Word 重开和非目标内容保持 | 输入到正确画面、重排范围、长会话资源趋势 |
| P5/P6 的 XLSX/PPTX | 按所属产品阶段增加，不由测试提前宣布支持 | Excel 实际重算、PPT 母版/主题/对象与导出 | 重算、区域渲染、幻灯片布局等独立工作负载 |
| PDF | 当前先验 Office→PDF；PDF 输入能力后续按 P7 | qpdf 结构 + 独立文本/栅格，后续取 PDFium/PDF.js 案例 | 导出耗时/大小；读取性能待相应能力实现 |

判定先结构和内容，再布局，最后视觉：页数、缺字、丢对象、表格错行不能由较高 SSIM 抵消。既保存整页图，也保存具体元素的 expected/actual/diff。视觉阈值按已校准场景冻结；禁止自动平移、缩放或模糊处理来隐藏定位错误。

三条保存链路沿用第 4 节：no-op、指定最小编辑、重复往返。直接检查输出 XML/对象和未知内容，再由独立工具读取；SDK 自读只是一项检查。PDF 输出用外部 reader，不用自己的 PDF 路径互相证明。

微软兼容性黄金结果来自固定 Word/Excel/PowerPoint、字体和配置的审核产物。LibreOffice/ONLYOFFICE 提供差分参考，不提供多数表决真值。参考冲突记 `oracle_conflict`，保留来源与差异，Agent 不得自动选择最有利答案。正常 CI 消费冻结产物；新的编辑结果若没有预先生成的对应参考，必须补参考或标记该项未验证，不能拿未编辑输入的 PDF 充数。

### 10.6 真实文件的取得、分组和扩容

先按 case 需要取文件，避免先下载海量 corpus 再猜预期。优先级是 LibreOffice 的 bug + fixture + 断言、Collabora 的真实交互案例，再补已有 POI 和经许可的用户文档。Collabora 常用 ODT；不把转换后的 DOCX 当成原生 Word 样本，也不顺带承诺 ODF 支持。

每个文件至少保留来源 URL/commit/原路径、SHA-256、来源类别、生产工具与版本（未知就写未知）、许可证据、隐私级别、语言/特征、模板家族、原始/缩小关系。另把操作、支持范围、oracle、字体和预期绑定为 case。原始业务文件、上游已缩小回归文件和自建原子文件分开计数，不能都叫「真实业务覆盖」。

建议首批工作量，均为待筛选目标，不是已下载或已验证数量：

| 批次 | 输入计划 | 成功条件 |
| --- | --- | --- |
| 第一条纵向链路 | 一个现有真实 DOCX + 一个最小原子反例 | 两个 surface 都能复现、输出具体差异、修复后恢复；不需要新下载 |
| DOCX 第一批 | 保留现有 4 个 POI，再筛选约 20 个 LibreOffice 回归文件 | 每个都有局部独立预期；按当前支持范围划入必过、明确拒绝或探索集 |
| 实际业务补充 | 获得授权后选 5–10 份不同模板/来源的业务文档 | 保留原文档、脱敏版本的区别，审核数据权限和参考结果；缺授权不下载 |
| 扩展扫描 | 前述链路稳定后扩至约 100–300 份去重输入 | 逐文件隔离和可重放；未知 oracle 不计兼容通过，不以数量代替特征覆盖 |

DOCX 按样式继承、段落间距/行高、分页、表格、内联/浮动图片、RTL/CJK、未知内容、损坏/超限分层。浮动图片等未承诺能力可以验证明确拒绝与保留；不能强制要求当前 renderer 成功，也不能把拒绝成功计为渲染成功。

语料分三种用途：

- **回归集**：预期明确，在声明支持范围内；每次完整验收必跑。
- **探索集**：发现新缺陷或能力缺口；报告原始结果，不自动提升产品范围。已支持能力的真实失败必须追踪，不能长期藏在探索标签下。
- **独立留出集**：以后由受限执行器持有、按模板家族隔离。当前 Agent 能读整个私有仓库，暂时只能叫未用于调试的验证集，不是真正盲测。已向 Agent 暴露的留出 case 转入回归集并补充新留出文件。

按内容 hash 和模板家族去重；同一原始文件及其缩小版、Office/LO 转存版放在同一数据分组，避免跨组泄漏。首次导入经过隔离检查，日常运行离线读固定文件，不从研究 checkout 或在线链接临时取数据。保留原文件，不先经 LibreOffice「修好」后替代原输入。

### 10.7 性能：先可重复，再设硬门槛

需要区分端到端与核心区间，分别记录起止点、单位和测量域：

- 冷启动：新进程/浏览器、Wasm 获取、编译实例化、Worker ready；缓存冷热条件明确。
- 核心操作：字节已准备好的导入、首次布局、暖布局、编辑后重排、保存、PDF 输出。
- 宿主成本：RPC 往返、序列化字节、字体/图片解码、Canvas 提交与首个正确页面。`requestAnimationFrame` 只能作为时序观测之一，不能直接声称测到屏幕呈现时间。
- 体积和资源：Wasm 原始/gzip/Brotli、JS、字体/图片、导出字节、存活 session/缓存量；大文件按页数、节点数、解压量和像素量分档，不能只按 ZIP 大小。

首批选择 6–10 个固定负载，包含真实文档和可控的规模增长样本。先在固定机器串行测基线 A 与候选 B，采用交错顺序减少热状态偏差；分别采冷启动和预热后的操作。建议先做 5 次不计入统计的暖运行与 20 次测量，保留所有原始值、median、离散度；该样本量下 p95 仅作描述，不能当稳定尾延迟 SLA。

阈值不是从 LibreOffice 或别的项目抄来：先重复测量无代码变化的 A/A 噪声，再按负载冻结绝对预算和相对退化预算。硬判定要同时超过可接受差异和测量噪声；高噪声标 `inconclusive`，额外测量保留为独立 attempt，不能把最优一次挑作通过。共享 CI 单次耗时只作发现线索。

性能比较还必须通过同一输出正确性断言。少排一页、漏掉图片或提前返回不算加速；修复后工作量增加时记录输出变化，不能直接标性能提升或回退。超时/OOM 保留原状态，不填成零耗时或正常延迟样本。

WasmGC 没有可靠测量时保留 `measured: false`。可用进程 RSS 或浏览器指标时注明包括哪些进程/对象、采样间隔及是否峰值；不要把 JS heap、线性内存或 session 自报字节冒充 WasmGC 总内存。资源预算失败可以硬验收，内存回归门槛等测量能力稳定后再建立。

### 10.8 统一运行结果与 Agent 任务包

复用已有 reporter，不另造一套测试框架。Bun JUnit、MoonBit 结果、Playwright 结果和独立工具输出统一归一化。现有失败 trace/截图/原始日志继续保留；可读报告是派生视图，不再维护一份手工结论。

建议每次运行在私有 `.temp/runs/<runId>/` 生成以下产物。以下文件名是待实现设计，不是现有命令输出承诺：

| 产物 | 必须回答的问题 |
| --- | --- |
| `run.json` | 测了哪个源码 snapshot、测试/语料/预期版本、构建产物、机器/浏览器/字体？属于 focused、full 还是 exploration？最终是否完整？ |
| `plan.json` | 本次冻结的 case/operation/surface/profile 全集、筛选原因、分片归属、依赖；运行途中不能偷偷少测 |
| `events.jsonl` | 启动/结束/超时/崩溃等追加事件；进程突然退出也能知道最后做到哪一步 |
| `results.jsonl` | 每次执行的原始状态、每条断言 expected/actual/delta、来源、定位、耗时、artifact 引用 |
| `summary.md` / `index.html` | 本次新增失败、已修复、仍失败、未执行、能力缺口、性能变化；可直接跳到差异和 trace |
| `failures/<fingerprint>.json` | 给 Agent 的可复现任务：受影响 case、最小反例、定位证据、建议检查范围、必跑回归集与停止条件 |
| `artifacts/` | 输入、输出、XML/模型/布局 diff、整页和局部图、trace、性能原始样本；每项带相对路径与 hash |

结果身份采用 `caseId + operationId + surface + runtimeProfile + attempt`，不是测试标题。每条断言有稳定 `assertionId`、判定器版本、参考身份、定位类型（part/XPath、节点、页/区域、单元格等）与单位；修复后即使页码改变，也能用 case/语义定位追踪原问题。

执行状态与期望行为分开：原始状态至少区分 `completed / error / timeout / crash / not_run`，判定分为 `pass / fail / inconclusive / blocked`；run 另有 `complete / incomplete` 的完成状态。期望拒绝的输入若得到指定错误且状态保持，可判 pass，但报告的支持类别仍是「拒绝」；已支持能力突然返回 unsupported 必须判 fail。缺 oracle、参考冲突、零执行、环境缺失不能进入兼容通过数。

Agent 任务包必须包含以下信息，而不是只有「截图不同」：

1. **身份**：运行、源码/产物、输入、操作、参考、判定器的固定标识和 hash。
2. **复现**：已验证的工作目录、程序与参数数组、所需非秘密环境变量；命令由受控 runner 生成，不执行文档正文中的命令。
3. **事实**：失败阶段、断言路径、expected/actual、是否两个 surface 都失败、上次已知结果；引用完整日志。
4. **定位材料**：相关 part/XML 片段、模型与布局节点、页图裁切、错误栈和最小反例；原文件始终保留。
5. **假设**：候选模块、推测根因及理由，与观测事实明确分栏；Agent 生成的解释不是判定依据。
6. **完成条件**：原输入与最小反例都恢复、相关家族无回退、要求的完整验收通过；不能只修缩小文件。

问题 fingerprint 优先按操作、错误类别、断言身份、归一化栈/语义位置聚类，不含易变时间或绝对路径。聚类只减少重复阅读，不合并或删除 case 结果，也不把「同类症状」写成已证明同一根因。

报告器必须在构建失败、解析失败、浏览器崩溃、命令超时和中途取消时输出部分报告。编排器预先写计划并实时留 stdout/stderr，正常异常都走 finalizer；被系统强杀而来不及 finalizer 时，下次恢复命令根据事件生成 `incomplete` 报告，不把缺结果当 pass。报告生成失败本身非零退出。

汇总展示各维度的 planned/executed/pass/fail/blocked/inconclusive，不用一个总分掩盖丢内容。全量计划缺一个必选组合就不能完整通过；分片合并拒绝遗漏、重复和版本混用。TS 覆盖率、MoonBit 可获得的代码覆盖率、功能矩阵和真实文件覆盖分别报告；未测的写未测，不合成一个「Office 覆盖率」。

### 10.9 RSI 风格的受控改进循环

建议第一版由现有 Agent 手动调用确定性 runner，暂不增加自主后台服务。每轮只处理一个有证据的失败类别：

1. **冻结本轮评价**：固定支持范围、输入集、判定器、阈值与基线，保存原始失败。
2. **分诊**：先分 SDK bug、环境/工具、样本错误、oracle 冲突、未承诺能力和性能噪声。环境问题不自动触发产品代码修改。
3. **复现与缩小**：用正式产物重现；在私有侧缩小文件或操作序列。缩小器必须保留同一个失败谓词、格式有效性/原有畸形条件和所需资源，不能把布局 bug 缩成 ZIP 损坏。
4. **修复通用规则**：只改拥有该责任的源码；不按文件名、hash 或 case ID 特判，不搬出 Wasm，不偷换预期。
5. **验证顺序**：原始失败 + 最小反例 → 同特征家族/同模块 → 两个 surface → 当前完整验收；共用 XML/ZIP/文本层改动扩展到全部已支持依赖格式。
6. **记录结果**：报告本轮 fixed/new-fail/unchanged/blocked 和性能变化。失败尝试也保留，禁止通过重试抹掉 flaky 结果。
7. **沉淀回归**：经审核的新反例进入下一版固定清单；实际未知能力进入所属产品阶段，不让 Agent 自行扩展产品目标。

评价器改进和产品修复分开：Agent 可以提出新 case、判定器 bug 或 golden 更正，但先用原有冻结评价验收产品补丁。修改判定器/阈值/期望需要独立证据和批准，另开评价版本，重测基线与候选。不能在同轮既改答案又宣称兼容性提高。

建议默认每个问题最多 3 个修复尝试或 30 分钟诊断预算，到先达到者暂停并交接；这只是待批准的执行预算，不是当前自动任务。出现参考冲突、需要新授权/产品范围、持续不能复现、评价器疑似错误时提前停止产品修改。部分修复可以保留，但必须交代未解决范围，不能标为完成。验证完成不自动 commit/push。

优先级按内容丢失/损坏、崩溃或超限、支持范围内功能错误、布局错误、确认的性能回退排序，再看受影响的独立文件家族。不能为了提高总通过率优先刷重复小样本，也不能奖励删掉功能得到的速度提升。

所谓「持续变好」至少同时满足：在同版本评价上修复目标、无新增必选失败、受影响家族通过、没有未解释的性能回退。没有隔离留出集时，只能声称这些可见用例改善，不能声称泛化能力已获独立证明。

### 10.10 如何搭建：复用位置、执行档和 CI 边界

实现继续放私有仓库，最小职责划分如下；这是建议修改点，不表示本轮已修改：

- `tools/loop.mbtx`：入口、前置检查、一次构建、冻结计划、进程隔离与超时、最终汇总。新进程编排继续用 `.mbtx`。
- `tools/reporter.ts`：只收集 Playwright 事件；新增小型结果归一化/报告模块消费 Moon/Bun/浏览器证据，不把所有逻辑塞到一个大 reporter。
- `cases/`：沿用现有清单的资产/预期归属；给 `suites.json` 增加稳定执行身份和 profile，不另造一份手工重复维护的总清单。
- `tests/moon/`、`tests/unit/`、`tests/integration/`：保留现有职责，增加正式包 API 合同测试；不要把 corpus readiness 冒充 SDK 功能测试。
- `tests/browser/`：同输入操作走真实 Worker 和宿主；`tests/support/` 保留有限调用适配与独立判定器。性能 workload 与功能用例共享输入，不混入性能计时区间。
- 现有私有 `document-test-loop` skill：在 runner 实现后更新为「读取 summary → 失败任务 → 复现 → 修复 → 完整验收」的入口；不增加多个互相重述政策的 skills。

建议分档，但保留根 `bun run test` 的完整验收语义：

| 执行档 | 选择和触发 | 判定用途 |
| --- | --- | --- |
| focused | 开发者/Agent 指定问题 + 受影响家族 | 快速诊断；报告明确不完整，不能替代根验收 |
| full | 根 `bun run test`；当前所有必选 case/surface/profile | 修复收尾、可信变更验收；尚未声明支持的浏览器不伪装必过 |
| explore | 人工触发扩展语料/属性变异，后续再设置定时运行 | 批量找问题；无 oracle 只能说明执行结果和差异 |
| perf | 固定机器上的同产物 A/B，独占资源 | 校准后用于性能判定；不是普通 full 测试总耗时 |
| reference | 单独受控环境生成候选 Office 参考 | 人工审核后冻结；不自动覆盖 golden |

目前完整入口不接受筛选参数，不能直接往后拼 `--case`。实现时保留该约束，为 focused 新增单独入口；可先继续用现有 Bun/Playwright 选测定位。新报告要标出 focused 选择集及距完整验收缺哪些项，不能只输出绿色通过页。

第一次可重现构建采用本地不可变源码 snapshot，包含用户未提交内容的内容 hash，测试也从对应 snapshot 读取；无需偷偷提交或创建分支。复制前后核对源文件清单与 hash，并核对副本；复制期间发生变更则本次 snapshot 无效，不能把混合版本作为验收输入。构建和两条执行路径都针对这个 snapshot，不能一边读活动工作树一边测另一份 dist。只读输入、每 case 独立输出目录；崩溃后重启执行器继续采集其他独立 case，基础构建失败则把下游标 blocked。根执行最后统一非零返回。

先串行实现正确的结果集合，规模需要时再分片。浏览器继续使用 Playwright 自带 JSON/HTML/trace；可采用其 [blob 报告与分片合并](https://playwright.dev/docs/test-sharding)，但额外检查全局计划全集。不要因 worker 数增加导致多个测试覆盖同名输出或删除其他分片证据。

远端阶段建议测试 workflow 位于私有仓库：显式输入公共 SDK 的确切 SHA、测试 SHA 和固定语料版本，在临时执行环境运行。SDK gitlink 固定默认测试版本；测试研发需要覆盖版本时必须显式记录，不能静默用测试仓库最新分支。初期只开人工触发，稳定后再批准定时/跨仓触发，不预建 webhook 服务。

公开 CI 仅执行公开的构建、类型/lint/format，不持有私有测试数据和结果。维护者审核后才把公共 PR 的确切 SHA 交给私有验收；不能在有私有凭据的 `pull_request_target` 中执行任意 PR。拉取凭据不传入产品执行子进程；不可信文档在无外网、无凭据、资源有界的进程/容器/VM 中处理。浏览器 request 拦截是补充，不代替宿主隔离。报告中的文档文本需转义为静态内容，不能让文档或日志成为 Agent 指令。

### 10.11 分批实施与完成证据

以下 A–F 是本研究的建设顺序，不新增或改写 P0–P9 产品编号。每批须先满足自己的验收再扩容；不是只写配置就算完成。

| 批次 | 具体交付 | 必须拿到的完成证据 |
| --- | --- | --- |
| A：可信报告 | 构建前 snapshot、计划/事件/统一结果、Markdown/HTML、失败任务包 | 正常执行、错误断言、缺 case、前置构建失败、超时、缺 oracle 都有可读报告；任何必选缺失非零退出；原始失败不被覆盖 |
| B：双路径纵向闭环 | 实际 tarball library + Chromium Worker 使用同一文件/操作/独立预期 | 正常导入、一次编辑、保存、独立重开；同时证明错误身份、多个 session 和原子失败；人为缺陷能在相应层被抓到 |
| C：真实文件兼容集 | 分层引入约 20 个 LO 文件，保留原有 POI；微软候选参考采集与审核流程 | 每个入库文件有来源/许可/hash/范围/局部预期；Word 基准与 LO 差分明确分开；无 Word 条件则如实显示微软验证缺口 |
| D：可重复性能 | 固定机器、6–10 个 workload、A/A 噪声与 A/B 原始样本 | 正确性不变时能识别注入的明显变慢；噪声不报硬回退；缺内存指标不报零；基线/环境/计时区间可追溯 |
| E：Agent 最小改进 POC | 现有 skill 驱动一次有限修复，保留前后任务与补丁证据 | 一个真实文件缺陷的复现 → 最小反例 → 一般规则修复 → 原文件及相关族恢复 → 完整验收；golden/阈值未变。若没有可用真实缺陷，先用受控故障验证管道并明确它不是产品能力改进 |
| F：扩展执行 | 额外浏览器、探索集、私有 CI、按需分片与真正留出隔离 | 各必选浏览器独立跑过、分片无漏重、结果无私有泄露；设置远端流程前获得相应授权。没有隔离则不标盲测 |

优先 A → B，再做小规模 C 和 E；D 可在工作负载正确性稳定后加入。F 不是第一轮 Agent 修复的前置条件。每批以可运行、可失败、可复现的纵向能力交付，不先铺满所有格式或所有浏览器。

### 10.12 本轮证据、限制与需确认项

本轮检查了当前 `loop.mbtx`、reporter、Playwright 配置、Bun/集成测试、DOCX browser 用例和参考比较器，以及实际包 exports/加载桥接。新增研究 checkout 使用浅克隆、blob-filter、无工作树检出，只读取需要的文件；文档中的上游链接均指 GitHub，不依赖被忽略的本地副本。

上游固定 revision：LibreOffice `1746b16a564f59fcaf8c5670bb292748408da54e`；Collabora `033854ea356ba65dae6618297257366cddb05bdf`；ONLYOFFICE sdkjs `72b0421c0bbf9d01eed9cf14834ae47eb2df1b50`；x2t-testing `540e4308ce1fd4d7ea41220cc66b85fd03a74ae7`。Collabora 的一个按需 Git blob 下载遇到 TLS 失败，改读相同 commit 的官方 raw 文件核对配置，没有将获取失败当测试失败或通过。

没有运行本项目完整 loop、Node library 探针或性能基准，没有导入新的二进制语料或生成 Office golden，也没有执行 Agent 修复。当前工作区存在并行源码/测试修改，因此本轮不做会重建其产物的验证。这里的规模、采样数和修复预算均是建议，不是实测性能或已批准 SLA。

实施 A/B 不需要新增云服务。C 的微软验证需要确认可用的 Office 平台/版本、字体和受控运行环境；真实业务文件需要授权来源。D 需要指定性能机器并校准预算。F 的远端运行/凭据、定时触发和留出访问隔离另行确认；本报告不构成这些外部操作的授权。

返回[文档索引](README.md)。
