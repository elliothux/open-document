# XLSX 视图、剪贴板与绘图

[格式合同目录](../formats.md)

### 冻结窗格

`editSheet({ action: "freeze", rows, columns })` 冻结起始的指定数量行列，`0, 0` 取消冻结。`rows` 为 0–1048575，`columns` 为 0–16383 的整数。`XlsxQuery.frozen` 返回数量和 `readOnlyReason`。默认属性栏提供首行、首列、所选范围之前及取消冻结；命令沿队列先提交原生草稿。RTL 视图的起始列位于右侧。

核心修改主窗口 `sheetView` 的 pane 和 selection，保留视图属性、注释及其他窗口的源内容。一次操作进入既有历史，相同数量不增加历史；预算或保护失败保持原状态。操作不改变单元格、样式、公式缓存、calcChain 或打印。工作簿窗口保护和未知视图元数据阻止修改，未知公式继续遵循既有只读边界。

网格读取普通 LTR/RTL 的 `frozen` / `frozenSplit` 视图；普通 split 仍拒绝布局。一个 R0 区域内最多绘制四个裁剪窗格，共享 4096 格和 262144 UTF-16 文字预算；核心负责命中、滚动定位及合并格跨边界。`XlsxViewport.cells[].clip` 给出所属窗格，合并格按地址去重。`XlsxSelectionGeometry` 保留锚点矩形并返回最多四个 `rects`；覆盖层绘制这些矩形，原生输入受所属窗格裁剪。

### 行列分组与折叠

`XlsxQuery.outline` 返回 `{ rows, columns, reason }`。两个轴各含 `summaryAfter` 及 `groups`；每组包含从 1 开始的 `first/last`、1–7 的 `level`、汇总项 `summary` 和 `collapsed`。缺省汇总位于明细之后。组由标准 `outlineLevel` 的连续区间派生；共用汇总项的组使用外层按钮，没有可用汇总项时禁用折叠。未知属性、自动应用样式或超限结构返回原因，保留原源。

`editSheet` 接通以下修改，`axis` 为 `"rows" | "columns"`：

| action | 其他字段 | 结果 |
| --- | --- | --- |
| `group` / `ungroup` | `first, last` | 所选行列增加/减少一级，级别下限为 0 |
| `collapseGroup` | `first, last, level, collapsed` | 匹配当前组并折叠/展开 |
| `clearOutline` | 无 | 清除该轴的分组并显示明细 |
| `outlineSummary` | `after` | 设置汇总在明细之前/之后，并迁移折叠标记 |

一次范围操作最多修改 4095 项明细，另预留一个汇总项；一次元数据修改最多 4096 项，每轴最多 1024 组、七级。沿现有源补丁保留行高、列宽、样式、自动适配标记、文字、公式和其他部件；级别缓存及汇总标记一同更新。默认分组面板提供所选范围分组/取消、折叠/展开、清除及汇总位置，原生草稿先提交。修改沿现有 revision、保护及有界历史，重复状态不新增历史；非法范围、层级溢出、未知源和输出预算失败原子拒绝。

折叠隐藏全部明细；展开显示组内手动隐藏项，保留仍折叠的内组及筛选隐藏。清除分组同样显示明细并保留筛选结果，遵循 [ONLYOFFICE 分组展开](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L24846-L24938)与[清除大纲](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L25323-L25415)。行隐藏复用[筛选来源记录](xlsx-editing.md#值筛选)，`SUBTOTAL` 缓存随可见性重算并与折叠合为一项历史。网格、命中、语义单元格及 PDF 复用相同尺寸，隐藏内容仍保存在源单元格中。

整行/整列插删同步分组级别和汇总位置，插入项继承前项的分组级别，并在所在组折叠时保持隐藏；筛选来源和缓存共同提交。删除后仍存在的组保留折叠状态；没有合法汇总位置时原子拒绝。取消分组只减少级别，不自行显示原隐藏项。复制、改名、保存重开与精确混合历史保留分组；保护设置与更广导入变体继续实施。实现归 [`outline.mbt`](../../../modules/formats/src/xlsx/outline.mbt)、[`outline-edit.mbt`](../../../modules/formats/src/xlsx/outline-edit.mbt)、[`outline-axis.mbt`](../../../modules/formats/src/xlsx/outline-axis.mbt)及 [`xlsx-outline.tsx`](../../../packages/xlsx/src/react/xlsx-outline.tsx)。

### 工作表网格线与标题

`editSheet({ action: "view", gridLines, headings, rtl, formulas })` 设置当前表的网格线、行列标题、RTL 方向和公式显示，四项均为布尔值。`XlsxQuery.view` 返回这四项及 `readOnlyReason`。默认属性栏的四个开关调用相同命令，先提交原生草稿。主窗口缺省显示网格线/标题，采用 LTR 和计算结果；读取 `0/1/false/true`。修改只写变化的属性，保留其他窗口、窗格、选区和未知部件。缺少主窗口时创建。相同设置不增加历史，失败不提交部分结果。

核心同时调整绘制、滚动范围、冻结窗格、命中和选区。`XlsxViewport.headerWidth/headerHeight` 在显示标题时为 `36/18` pt，隐藏时为 `0/0`，并返回空的标题行列数组。`rtl` 为真时，行标题和起始列在右侧；所有矩形仍使用画布左上角坐标，`scrollX` 始终是从起始列向后的非负距离。Web 换算 Chromium 的 RTL 滚动值，并沿核心矩形绘制覆盖层和定位原生输入；无标题时仍保留可访问的单元格语义。

RTL 改变列排列，不镜像字形，也不改变单元格值、格式、计算缓存和 calcChain。网格方向键按视觉左右移动；Tab/Shift+Tab 沿逻辑列次序前进/后退，原生草稿的文字方向键保持浏览器行为。程序化 `navigate` 的左右继续表示逻辑列方向。打印使用相同列方向、分页与重复标题，在页边距和缩放内排列单元格；页眉页脚保留各自对齐。网格线和行列标题开关不改变打印，隐藏网格线也不隐藏显式边框。

`formulas=true` 保存主视图的 `showFormulas`，网格、查询 `display`、可访问单元格及 PDF 显示带 `=` 的逻辑公式源。共享公式沿现有展开规则显示，原共享源与缓存保留。物理列宽加倍，隐藏列仍为零，行高和源列宽不变；冻结、RTL、命中、选区及打印使用相同尺寸。数值不再因过窄显示井号；常规对齐及数值采用左对齐，其他显式文字对齐保留。非公式数值显示编辑形式：一般数值不强制补位或分组，百分比保留 `%`，日期/时间使用固定 ISO 日期及 24 小时时间，不使用宿主区域设置。

自动适配测量当前显示文字，并将物理宽度换回源字符宽度；后续原生输入沿既有自动尺寸事务更新。统计、筛选及 CSV/TSV 值输出继续使用实际计算值。公式显示不写公式结果缓存，也不移除 calcChain。受保护表的隐藏公式在公式视图中不显示，公式栏输入为空，查询 `formula` 为 `null`；隐藏标记读取本地及基础样式，显式保护覆盖沿 `applyProtection` 解释。源包保留，支持正常保存和计算。

操作沿冻结窗格的普通视图和保护边界执行。窗口保护、未知视图元数据及既有未知公式只读边界仍会拒绝修改。普通分割窗格及辅助诊断仍待实现。行为参考 [ONLYOFFICE 显示开关与方向事务](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L8020-L8094)、[公式视图文字](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9493-L9674)、[编辑文字与保护](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L16152-L16252)和 [WorksheetView.checkRtl](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L27778-L27812)。

### 输入与保存

CSV 输出拒绝 SpreadsheetML 转义产生的 NUL 等非 XML 控制字符，保留原工作簿。

`XlsxSession.execute({ operation: "importXlsxDelimited", bytes, delimiter, budget, options: {} })` 与 `XlsxClient.execute({ operation: "importXlsxDelimited", bytes, delimiter, budget, options })` 创建一张新工作表，分隔符明确为 `","` 或 `"\t"`。只接受 UTF-8，可带 BOM；引号字段、双引号转义及字段内 CR/LF 保留。不等宽行按实际字段写入，导出时补空字段到矩形。`XlsxDelimitedOptions` 的 `numbers`、`dates`、`formulas` 均默认 false，字段默认完整保留文字。默认 XLSX UI 的文件入口接受 `.csv/.tsv`，按后缀选择分隔符，显示每次重置的转换选项，导入后改用 `.xlsx` 文件名并等待首次保存。宿主可在 `EditorDocument.delimited` 指定同一组选项；非 CSV/TSV 输入不接受此属性。取消选项或导入失败保留旧文档。

`numbers` 采用既有核心有限数值解析，前导零会消失；布尔及单引号前缀仍为文字。`dates` 采用核心 1900 日期系统，接受四位年份的数字 ISO/美国日期及可选时间、独立时间；非法日期仍保留文字。日期、时间和日期时间分别持久化 `yyyy-mm-dd`、`hh:mm:ss`、`m/d/yy h:mm` 格式，后者显示到分钟但保留秒与小数。日期列过窄时沿现有规则显示 `######`，可用列宽自动适配。`formulas` 仅把原文首字符为 `=` 的字段交给既有公式解析和计算引擎，写回源公式与结果缓存；不支持的公式、循环或预算失败拒绝整次导入。有效公式错误结果保留为错误值。导入初始 revision 为 0，无撤销历史；后续编辑沿正常历史重算。数字/日期分类与样式参考 [ONLYOFFICE CellFormatController](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Sheets/Reader/CellFormatController/CellFormatController.cpp#L136-L280)，默认文字及显式执行是本 SDK 的策略。

导入最多 4 MiB 文件、1048576 UTF-16 单元、65536 字段与 16384 列，每格最多 32767 UTF-16 单元，并受既有 OPC 预算约束。空字段和行列位置保留；不支持的编码、引号结构、非法 XML 字符或预算失败不产生可用的半份工作簿。

`XlsxSession.execute({ operation: "exportXlsxCsv", revision, selection: false })` 与 `XlsxClient.execute({ operation: "exportXlsxCsv", revision, selection })` 输出 UTF-8 CSV 字节；宿主 `SpreadsheetEditor.exportCsv(selection = false)` 先提交原生草稿，返回上述 `EditorOutput`。false 导出当前表从 A1 到已用边界的矩形，true 导出当前选区，均最多 65536 格。输出原始逻辑值、布尔值与已计算/缓存公式结果，空合并延续格输出空字段，不导出公式、样式、其他表或图形。公式没有可信结果时拒绝，不伪造空值。

CSV 采用 CRLF 行尾，含逗号、引号、CR/LF 的字段加引号，内部引号成对转义。文字去前导空白后以 `= + - @` 开头，或原文以 Tab/CR/LF 开头时，加一个单引号防止外部表格执行；负数值保持数值。该单引号在文字模式重导入时保留。输出最多 4194304 UTF-16 单元并受 outputBytes 限制。默认文件菜单明确提示范围、格式损失和文字前缀策略，CSV 输出不确认 XLSX 已保存。引号/分隔符行为参考 [ONLYOFFICE CSVReader](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Sheets/Reader/CSVReader.cpp#L328-L366) 和 [CSVWriter](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Sheets/Writer/CSVWriter.cpp#L907-L925)；安全前缀为本 SDK 的明确策略。

前导 `=` 进入公式，单引号强制文字。未做日期自动识别与地区化输入推断。TSV 粘贴保留以 `=` 或单引号开头的文字，其余字段由核心识别数值、布尔或文字。CRLF/CR 统一为 LF，支持带引号的字段、字段内换行和双引号转义；不等宽行或未闭合引号拒绝。矩形写入、粘贴和清空与任意合并区域相交时拒绝，单格按锚点修改。

候选源片段、依赖、计算缓存和历史一起提交。新文字使用内联字符串；共享字符串顺序不变，同步计数。保存保留非目标源内容，移除失效 `calcChain`、其关系与 content type，并设置 `calcPr` 重算属性。输出重新检查 OPC 完整性；失败保留会话，不返回部分文件。不承诺整个 ZIP 字节相等。

`SpreadsheetEditor` 持有一个原生 textarea 草稿。双击/F2 编辑，Enter/Tab 提交并移动，Shift+Enter 在草稿内换行，Esc 取消。草稿开始与导航进入同一队列，快速输入绑定确认后的单元格，保留原生文字与选择。离格或切表先提交；错误保留草稿与旧值。组合结束只更新草稿，提交产生一项历史。草稿中使用原生文本撤销，退出后使用核心工作簿历史。保存/打印等待命令队列，组合未结束拒绝输出。外部 revision 冲突需取消草稿并刷新，不覆盖外部修改。

屏幕使用固定视口 Canvas 与独立覆盖层。滚动/尺寸/缩放请求按动画帧合并，过期结果丢弃；成功几何、文字和轮廓在预算内复用。选区只更新覆盖层。可见单元格提供有界 grid 语义、地址、值和只读原因，保留焦点和键盘入口。调用者拥有 client 生命周期；关闭 editor 后另行关闭 client。

`SpreadsheetEditor.formulaBar` 是可挂载的稳定 DOM 节点。默认 UI 在网格上方展示公式栏和范围框。公式栏显示核心的 `cell.input`；编辑时与网格使用同一个原生 textarea，另一处显示只读镜像。切换保留草稿、目标、光标和原生撤销；组合期间不移动节点。Enter/Tab、Esc、草稿错误、切格和输出继续遵循上述队列和屏障；关闭编辑器时移除公式栏。自定义宿主可挂载该节点，组合期间保持挂载；未挂载时继续使用网格输入。

`XlsxQuery.selection.address` 返回当前选择的规范 A1 地址或矩形地址。默认范围框将输入交给既有 `select`；选择只改变运行时范围和滚动，不新增文档历史。无效或倒序地址保留原选择，已有草稿先沿队列提交。当前范围框定位当前表的单格或矩形；名称目录提供受支持矩形名称的跨表定位，归[名称引用](xlsx-calculation.md#名称引用)。

### 结构化单元格剪贴板

`XlsxSession/Client.execute({ operation: "captureXlsxCells", revision })` 返回核心生成的 `CopiedCells`：源 `top/left`、`date1904`、矩形 `cells`、相对合并范围 `merges`、`conditional`、`validations`、`hyperlinks`、`notes` 和 `sparklines`。每格包含类型化 `value`、公式字符串或 `null` 和全部已支持格式属性。值是复制时的已计算结果；公式保留源表达式和位置。片段独立于之后的源编辑，不持有源会话句柄。

`pasteCells(revision, copied, mode = "all", transpose = false, acceptWarnings = false)` 从当前选择的左上角写入一次片段大小的矩形，不平铺到更大的选择。`all` 写入值、相对平移公式、支持的格式/合并、两类规则、链接、便笺及迷你图；`values` 只写复制时的类型值与公式结果；`formulas` 写入平移公式及非公式常量；`format` 保留目标值、公式和数据验证，只写格式、合并及条件格式。`values/formulas` 保留目标格式和两类规则，目标须未合并。文字 `=literal` 仍是文字，不经输入解析变成公式。

`transpose` 交换行列、合并范围和四边边框。公式先绕复制矩形原点交换引用坐标，再执行粘贴位移；绝对标记沿原引用保留，整行/列引用交换轴。引用越界按既有规则写为 `#REF!`。行为依据 [ONLYOFFICE 选择性粘贴模式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/clipboard.js#L186-L247)、[转置后应用位移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L29818-L29881)和[引用坐标翻转](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L11010-L11034)。

格式与新样式部件、内容、合并、依赖、缓存、验证、自动尺寸和选择共用一次候选事务。已有共享公式按必要范围展开；只贴格式保留目标文字源。失败保留文档与历史。支持完整包含的普通合并格；相交但不完整的目标合并拒绝。源与目标继续复用既有填充资源保护，富文本、原生表/透视和未知工作表扩展保持显式保护。便笺和迷你图随全部粘贴传递，其余模式保持目标便笺及迷你图。更广资源转移继续实施。不含规则/便笺，且单元格、链接与迷你图均相同的片段只更新选择；携带规则或便笺的粘贴可重建原生范围、优先级及身份。

源与目标的 `date1904` 不同时，核心按源格式识别已支持的日期及日期时间数值，换算 1462 天并保留日内小数。纯时间、普通数字、文字及其他类型保持原值；`format` 不转换数值。`all/formulas` 保留公式，在目标日期系统重算；`values` 转换已计算的日期结果。公式内部的普通数字常量不改写。日期验证的数字字面边界同步换算，`DATE`、引用及其他表达式沿目标公式语义处理。源或目标日历无法表示的日期整项拒绝，保留文档与历史；两本工作簿的日期系统不变。

换算复用核心日期序列与格式分类，实现归 [`clipboard-date.mbt`](../../../modules/formats/src/xlsx/clipboard-date.mbt)。工作簿日期标志参考 [ONLYOFFICE setDate1904](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L5813-L5825)；跨日期系统粘贴及 1462 天差值依据 [Microsoft 日期系统说明](https://support.microsoft.com/en-us/excel/date-systems-in-excel)。定向核心和默认系统剪贴板浏览器流程已检查，覆盖双向日期换算、值粘贴、精确历史、重开输入及 PDF。

每项 `conditional` / `validations` 包含 `ranges`、`anchor` 和 `settings`，类型分别为 `CopiedConditional` / `CopiedValidation`。`ranges` 是复制矩形内的源绝对地址交集；`anchor` 保留原规则的公式原点。条件设置沿已有 `XlsxConditionalFormat`，验证设置沿 `XlsxDataValidation`。条件样式与主题颜色解析为支持的直接格式，目标重新分配差异样式，保留源规则次序；不沿用源工作簿的 `dxfId`。

全部粘贴裁去目标两类规则的覆盖区，再写入复制交集；格式粘贴只处理条件格式。范围外规则及目标容器的显示设置保留。格内公式按原锚点和复制位移转换；转置复用同一引用坐标交换规则。公式型色阶/数据条阈值按整条规则处理，新覆盖区共同计算统计。复制不移动源引用或其他表的依赖；源和目标使用各自的名称定义，定义及关联资源不随片段转移。规则引用语法和支持范围沿既有合同。

全部粘贴在规则替换后检查新值；值/公式粘贴沿目标原验证检查。只贴格式不重新验证已有值，可保留导入文件中的无效值；后续输入仍受原验证限制。差异样式和普通格样式可同时创建同一个样式部件，关系、内容类型及全部源一起撤销。候选字体、规则、输入、工作量或输出失败保留原文档、选择和历史。

两类规则各最多 4096 项，范围合计最多 4096 个矩形，设置文字合计最多 1048576 UTF-16 单元；原单格、公式、XML、样式和事务预算继续生效。非默认验证 IME 设置、未知身份与扩展继续保护。源全局提示设置留在源文档，目标全局提示设置留在目标文档。实现归 [`clipboard-rules.mbt`](../../../modules/formats/src/xlsx/clipboard-rules.mbt)和 [`clipboard-rule-paste.mbt`](../../../modules/formats/src/xlsx/clipboard-rule-paste.mbt)。交集复制及转置规则依据 [ONLYOFFICE 条件规则复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L13432-L13505)和[验证复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L13233-L13262)；未移植可执行代码。

每项 `hyperlinks` 使用 `CopiedHyperlink`，含复制矩形内的源绝对 `range`、`target` 和可空的 `display/tooltip`。捕获范围与普通原生链接取交集，保留目标及元数据；未知或重叠链接保护复制。只有 `all` 替换目标覆盖区的链接，范围外片段和属性保持；值、公式及格式模式均保留目标链接。无源链接时清除目标覆盖区，单独链接变化也进入同一历史。转置交换链接所属格，内部目标文字保持原值，不执行公式位移；跨表或工作簿后仍按目标文档解析。外链按目标表分配或复用安全关系，保留旧共享资源，不自动发起请求。链接、单元格、样式与全部关系共用候选、验证和精确历史；同值、迷你图相同且不含规则/便笺的片段保持空操作。

链接目录最多 4096 项，范围须在片段内且互不重叠；目标及元数据合计最多 1048576 UTF-16 单元，`display/tooltip` 各最多 32767 单元。目标沿已有 HTTP/HTTPS/mailto 和内部引用校验。候选链接输出仍限制为 4096 项及 2 Mi UTF-16 单元，全部输出和历史预算继续执行。实现归 [`clipboard-hyperlinks.mbt`](../../../modules/formats/src/xlsx/clipboard-hyperlinks.mbt)，关系及原生范围裁剪复用 [`hyperlink-edit.mbt`](../../../modules/formats/src/xlsx/hyperlink-edit.mbt)。目标复制与所属范围位移参考 [ONLYOFFICE 范围链接复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22619-L22631)；本 SDK 同时裁剪源交集和目标覆盖，未复制上游源码。

`notes` 为 `CopiedNotes | null`。非空项有四个必需字段：原生便笺 XML 的 `comments` 字符串，以及可空的 `vml/threads/people` 字符串。`threads/people` 须同时为空或同时提供；它们分别承载所选原生消息及其实际作者 XML，范围归[单元格线程批注](xlsx-calculation.md#单元格线程批注)。传统便笺与 VML 只包含所选便笺、实际作者及相关框类型。MoonBit 沿既有严格读取器验证原生结构、富文本、所属地址、VML 类型及框匹配；Web 只校验载荷形状和长度。源 `guid` 不进入副本，目标重新分配部件/框身份及作者索引，保留富文本、外观、原 Anchor 与偏移；`ref` 和 VML Row/Column 随目标或转置更新。仅 `all` 替换目标覆盖区的便笺；`notes: null` 清除该区便笺，值/公式/格式粘贴保持原便笺。范围外原节点、原作者和空资源保留，源文档不变。

目标缺少 comments/VML 时沿既有资源事务创建；只有文字的导入便笺补齐默认框。源、作者、资源、关系、内容类型与值/公式共用一次精确历史及预算检查，失败保留文档。`comments/vml/threads/people` 四个字符串合计最多 2 Mi UTF-16 单元，捕获时逐条检查实际展开长度，包含命名空间、作者和框类型；沿原有 4096 项及 1048576 单元便笺文字限制。未知/共享/外链 VML、未知线程结构、源身份注入、范围外地址和异常 XML 继续保护。默认便笺面板、角标和可访问描述读取同一结果，静态 PDF 继续排除便笺。实现归 [`clipboard-notes.mbt`](../../../modules/formats/src/xlsx/clipboard-notes.mbt)与 [`notes-import.mbt`](../../../modules/formats/src/xlsx/notes-import.mbt)，复制范围、目标覆盖与独立身份依据 [ONLYOFFICE moveRangeComments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L550-L586)；未复制上游源码。

`SpreadsheetEditor.clipboard.copyCells()` 先提交原生草稿，再将片段及普通 TSV 写入系统剪贴板。`pasteCells(mode = "all", transpose = false)` 读取相同载荷，沿队列检查字体、revision 和生命周期后提交；默认面板提供四种模式和转置开关。载荷类型为 Chromium 的 `web application/x-open-document-cells`。普通原生粘贴及 `paste(text)` 保持上述 TSV 语义；普通 `copy()` 也先提交已接受草稿。读取/写入权限失败保留源，晚到读取不能修改已关闭的编辑器。

片段最多 4096 格、1024 个合并范围、1048576 UTF-16 单元的值/公式文字；每格文字最多 32767 单元，公式最多 8192 单元。Web 写入的 JSON 最多 4194304 UTF-16 单元，读取最多 8 MiB。Wasm、Worker 和核心分别校验载荷，现有样式、历史、源、字体及输出预算继续生效。实现归 [`cell-fragment.mbt`](../../../modules/formats/src/xlsx/cell-fragment.mbt)、[`clipboard-transpose.mbt`](../../../modules/formats/src/xlsx/clipboard-transpose.mbt)及 [`spreadsheet-clipboard.ts`](../../../packages/xlsx/src/web/spreadsheet-clipboard.ts)。

### 单元格剪切移动

`editSheet(revision, targetSheet, { action: "moveCells", sourceSheet, source, destination })` 在同一工作簿内移动普通矩形。目标从 `destination` 左上角开始，大小取源范围。完整单个合并格按实际跨度移动；部分合并相交拒绝。源与目标可重叠，目标覆盖和源清除读取同一个原始快照。内容、直接格式、完整合并、链接及便笺一起移动；行列尺寸及行列格式保留。便笺的作者、富文本、VML 及跨表归属归[单元格便笺](xlsx-calculation.md#单元格便笺)。多表公式、名称、内部链接的目标、计算缓存、自动尺寸与选择共用一次精确历史。未变化的公式保留原表达式。

完整落在源范围内的引用随格移动，包含绝对引用；部分相交的范围保持。相对及混合名称在定义保存的坐标上移动一次，保留 `$`、作用域、属性及调用公式中的名称。跨表移动把定义中的目标表改为目标表，求值仍按实际调用格偏移；调用格自身移动时使用新位置，不额外补偿。此规则与上述结构操作一致，依据 [ONLYOFFICE 名称定义事务](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L561-L580)及[调用格偏移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L2249-L2256)。移动到另一工作表时，原来指向源范围外的无表名引用和名称保留原表语义，不按复制规则偏移。依据 [ONLYOFFICE 移动事务与跨表公式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L9800-L9858)和[完整包含引用的移动规则](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L10155-L10227)。

完整包含的普通外链与内链随所属格移动，保留提示文字、显示文字和命名空间；源选择须包含完整链接范围。目标链接只裁掉被覆盖的范围，范围外源与容器注释保留。跨表外链在目标表复用相同目标的已有关系，或分配未占用的关系身份；旧源关系保留。内链目标沿同一次引用变换，重叠移动也只变换一次。链接归属参考 [ONLYOFFICE 合并与链接移动](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L9543-L9609)。未知链接属性、混合内外目标、失效关系及不安全协议继续保护；打开外链仍须用户明确操作。

普通条件格式和数据验证按实际交集随格移动，目标规则只裁掉覆盖区。重叠移动按原始归属计算，跨表复制原生规则片段并补齐命名空间；范围外规则、容器显示设置和提示保持。逐格公式保留原位置的引用语义，完整落在源区的引用随格移动；跨表未移动的本地引用保留原表。其他表内的依赖规则同步更新，公式型色阶/数据条阈值按整条规则处理。不同公式分组、优先级和验证 `count` 复用上述规则变换；同表保留的色阶/数据条覆盖区共用统计样本。规则归属沿 [ONLYOFFICE 条件格式迁移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L13432-L13507)和[数据验证迁移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L13233-L13257)，引用处理复用本节的移动合同。

`SpreadsheetEditor.clipboard.copyCells(true)` 和默认“剪切单元格”按钮先写系统剪贴板，源格在粘贴成功前保留。剪切只携带显示值 TSV 和 `web application/x-open-document-cut` 的工作簿身份、源范围与 revision；核心在 `pasteCells("all", false)` 时校验并移动实际源内容，不要求先生成复制片段。网格原生剪切/粘贴复用该入口，草稿文字仍沿原生文字输入。消费后、源文档编辑后或重开工作簿后的旧载荷拒绝；跨工作簿、选择性粘贴及转置剪切也拒绝。普通 TSV 和复制片段沿原合同。

移动最多 4096 格和 1024 个合并范围；工作簿源、公式、链接及迷你图组节点源合计最多 1 Mi UTF-16 单元，搬移与改写的单元格源合计最多 1 Mi 单元。每表最多 4096 个链接，单表生成的链接源最多 2 Mi 单元。规则沿既有 100000 格、4 Mi 字符和 4096 片段工作上限；每表至多 4096 条条件规则和 4096 条验证。全部变动仍受 4 MiB 历史及包输出预算约束。被保护的源、目标或受影响公式/链接/规则/迷你图拒绝。未知资源、原生表、透视及带筛选/排序的工作簿保持保护，未限定工作表的名称引用及需改写的不透明名称源继续保护；跨表打印范围的归属转移继续实施。实现归 [`move-cells.mbt`](../../../modules/formats/src/xlsx/move-cells.mbt)、[`move-reference.mbt`](../../../modules/formats/src/xlsx/move-reference.mbt)、[`move-hyperlinks.mbt`](../../../modules/formats/src/xlsx/move-hyperlinks.mbt)、[`move-rules.mbt`](../../../modules/formats/src/xlsx/move-rules.mbt)、[`rule-fragments.mbt`](../../../modules/formats/src/xlsx/rule-fragments.mbt)和 [`move-resources.mbt`](../../../modules/formats/src/xlsx/move-resources.mbt)。

### 工作表绘图复制

`SpreadsheetEditor.objects.editSheet({ action: "duplicateDrawing", objectId })` 在当前表复制一个普通图片、图形、文本框或图表。同步 `XlsxSession` 和异步 `XlsxClient` 使用显式 revision、sheet 的 `editXlsxSheet` 命令。默认属性面板提供“复制对象”，复制后选择副本并加载其属性。副本分配新的本地身份，放在最上层，向右、向下各偏移 12 pt；保留原名称、替代文字、三种锚点、尺寸、零轴直线、裁剪、文字、可见及打印策略。

核心在原生片段中补丁修改身份和坐标，保留未改源、注释及命名空间。图片共享不可变媒体字节，后续更换沿既有资源隔离规则。图表获得独立部件和关系，保留数据引用、缓存及配色；修改副本外观不改原图，两者仍读取同一单元格来源。新增部件、关系、内容类型和选择合为一次精确历史，支持撤销、重做、保存重开及后续输入。Canvas/PDF 继续使用共用绘制管线。

每表最多 256 个对象，全部变更沿既有包、输出及 4 MiB 历史预算。越界、旧 revision、复制/选择锁、工作表保护、未知身份扩展和未支持的关系原子拒绝；需改写的锚点数字内部有注释时也拒绝。图表附加资源仍受保护。此命令完成同表独立复制；同工作簿转移归[绘图剪切](#工作表绘图剪切)，图片、基础图形和普通图表系统复制归[绘图剪贴板复制](#工作表绘图剪贴板复制)；跨工作簿剪切继续实施。实现归 [`drawing-copy.mbt`](../../../modules/formats/src/xlsx/drawing-copy.mbt)。原生对象、图像填充及图表独立复制参考 [ONLYOFFICE Image.copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L162-L187)和 [ChartSpace.copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L4959-L4999)；未复制上游执行代码。

### 工作表绘图剪贴板复制

`SpreadsheetEditor.clipboard.copyDrawing(id)` 复制一个普通 PNG/JPEG 图片、矩形、椭圆、直线、文本框或工作表图表。默认图片、图形和图表面板提供“复制绘图”，对象和已选择绘图的网格支持 Ctrl/Meta+C。`pasteDrawing()` 与“粘贴绘图”支持同表、跨表和跨工作簿；本页面的网格原生粘贴也识别复制片段。新对象放在选区左上格和最上层，分配独立本地身份。保留三种锚点、尺寸、零轴直线、裁剪、名称、替代文字、可见和打印策略。

剪贴板格式为 `web application/x-open-document-drawing`。核心快照携带选中对象的原生片段、所需图片或图表数据及字体名/主题色。图表只携带当前标签、系列值和独立可见性，不复制来源公式或无关单元格。源文稿后续修改、关闭或替换不改变快照，允许重复粘贴。图片使用快照内的压缩字节；每次粘贴创建目标媒体、关系及内容类型。字体和主题会改变图形解释时，核心在目标对象中写明源字体与 RGB，保留原外观；宿主仍须提供该字体。未改源、命名空间和图片注释保留，需要重建的样式源若带注释则保护，避免丢失内容。

普通图表的快照保留完整系列长度、空值、散点数值轴、原配色及各来源的可见性。每次粘贴创建独立隐藏数据表和原生图表，绑定新表中的普通值，目标格不被覆盖。数据表可沿既有表管理显示并编辑；副本之间独立，后续输入自动更新所属图表。来源公式保存为当前计算值。图表和数据表、关系及内容类型共用一项精确历史；工作簿结构保护会拒绝该粘贴。删除图表保留数据表，避免删除后续输入；用户可显式删除数据表。实现归 [`chart-fragment.mbt`](../../../modules/formats/src/xlsx/chart-fragment.mbt)，从缓存重建数据表参考 [ONLYOFFICE getWorksheetsFromCache](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L2169-L2264)。

同步 `XlsxSession` 和异步 `XlsxClient` 提供 `execute({ operation: "captureDrawingXlsx", revision, sheet, objectId: id, profile })`，返回 `{ fragment, text }`；`execute({ operation: "pasteDrawingXlsx", revision, sheet, fragment, profile })` 导入片段。`execute({ operation: "drawingFragmentImageXlsx", revision, fragment })` 返回核心校验后的压缩图片或 `null`，供宿主沿现有图片入口预解码。默认编辑宿主自动完成预检、解码和提交。核心验证解码尺寸后，才把绘图、资源、关系和选择合为一次精确历史。失败保留文稿，撤销、重做、重开输入及 Canvas/PDF 继续共用既有管线。

片段最多 4 Mi UTF-16 单元，原生框源最多 1 Mi 单元，单图最多 2 MiB；平台读取 Blob 最多 8 MiB。JSON 使用标准库有界解析，XML 深度、像素、累计图片、256 对象、历史及包输出沿既有预算。字段、资源、复制/选择锁、工作表保护、宏/绑定、外链、不支持的原生结构或越界失败原子拒绝。图表含附加关系、源注释或内容内处理指令时继续保护；同表独立复制和同工作簿剪切沿相邻合同。实现归 [`drawing-fragment.mbt`](../../../modules/formats/src/xlsx/drawing-fragment.mbt)、[`drawing-paste.mbt`](../../../modules/formats/src/xlsx/drawing-paste.mbt)及 [`spreadsheet-clipboard-host.ts`](../../../packages/xlsx/src/web/spreadsheet-clipboard-host.ts)。图形复制和源外观保留参考 [ONLYOFFICE Shape.copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2829-L2858)及 [saveSourceFormatting](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L7639-L7659)；未复制执行代码。

### 工作表绘图剪切

`SpreadsheetEditor.clipboard.cutDrawing(id)` 先写系统剪贴板，保留源对象和文稿历史。默认图片、图形和图表属性面板提供“剪切绘图”，对象键盘支持 Ctrl/Meta+X；网格已选择的绘图也沿同一入口。`pasteDrawing()` 和默认“粘贴绘图”把对象搬到当前选区左上格，网格原生粘贴识别同一标记。剪切载荷 `web application/x-open-document-drawing-cut` 只包含工作簿身份、源表、对象 ID 和 revision，最多 4096 字节。写剪贴板失败不删源；编辑、重开或已经成功搬移后的旧标记拒绝。跨工作簿剪切仍拒绝。

核心命令为 `editSheet(revision, targetSheet, { action: "moveDrawing", sourceSheet, objectId })`。普通图片、图形、文本框和图表可在同表或同一工作簿的不同表之间搬移。保留三种锚点、尺寸、零轴直线、裁剪、文字、可见及打印策略；对象放在目标绘图最上层。同表保留 ID，跨表只在本地 ID 冲突时重映射。坐标与身份沿源补丁修改，保留未改注释和命名空间。相同位置的同表搬移不新增历史。

图片沿用原媒体字节，目标绘图复用已有关系或新建独立关系，不重复同一内容类型声明。图表沿用原部件，目标获得关系并移除旧绘图的关系。跨表搬移把无表名引用限定到原来源表，显式外表引用保持；不会改读目标表的同坐标。移动后的来源输入仍同步缓存和绘制，后续整表复制继续使用独立图表规则。源移除、目标插入、新建绘图、关系、引用和选择合为一项精确历史；失败不留下部分资源。

源/目标工作表保护、选择/移动锁、未知身份和关系扩展、越界、256 对象或历史/包预算失败均原子拒绝。需要改写的不透明锚点文字、图表引用或关系源继续保护；复制锁不阻止搬移。图片、基础图形和普通图表系统复制归[绘图剪贴板复制](#工作表绘图剪贴板复制)；跨工作簿剪切及更广原生变体继续实施。实现归 [`drawing-move.mbt`](../../../modules/formats/src/xlsx/drawing-move.mbt)、[`drawing-transfer-source.mbt`](../../../modules/formats/src/xlsx/drawing-transfer-source.mbt)及 [`spreadsheet-clipboard.ts`](../../../packages/xlsx/src/web/spreadsheet-clipboard.ts)。延后删除及同文档剪切归属参考 [ONLYOFFICE Clipboard.copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/clipboard.js#L434-L441)和 [_checkCutBefore](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/clipboard.js#L2119-L2153)；未复制执行代码。

### 工作表图片

内嵌图片由 `prepareImageXlsx` 准备。核心解码并注册符合条件的 PNG。其他输入返回原始字节，由宿主解码并用 `imageXlsx` 注册。

`SpreadsheetEditor.objects.pictures()` 返回当前表的 `{ revision, sheet, reason, items }`。每项包含稳定的原生 `id`、名称、替代文字、锚点、point 几何、源裁剪及图片资源键。`insertPicture(bytes, width, height, name?, description?)` 在选定单元格插入普通 PNG/JPEG；`setPicture(id, settings)` 修改锚点、位置、尺寸及文字，`deletePicture(id)` 删除目标锚点。`replacePicture(id, bytes)` 更换目标的 PNG/JPEG 压缩资源，保留身份、名称、替代文字、三种锚点、几何及源裁剪。默认面板提供独立文件选择，不提交其他未应用的属性草稿。默认图片面板复用这些入口，调整尺寸保留当前比例。同步 `XlsxSession` 和异步 `XlsxClient` 提供对应显式 revision/sheet/profile 接口；Web 在提交前完成图片预检和像素解码。

Web 插入、替换和粘贴图片时，向 `pictureResourceXlsx` 请求 `preparePixels: true`。核心能解码时，预检返回解码宽高及 `bytes` 中的 RGBA。Worker 转移该缓冲区。默认预检只返回资源键和头部尺寸，其余图片仍由浏览器解码。

`anchor` 接受 `fixed`、`move`、`size`，分别保存 `absoluteAnchor`、`oneCellAnchor` 和普通 `twoCellAnchor`。核心按原生行高/列宽解释几何，尺寸编辑在同一历史中同步图片姿态。网格按冻结窗格裁剪图片，RTL 只移动对象位置；打印沿现有分页、区域和缩放裁剪，保留隐藏和 `fPrintsWithSheet` 策略。源裁剪参与同一 Canvas/PDF 绘制。打印预览在两轴缩小裁剪图片时，先对完整源图采样，再应用裁剪边界。资源、关系、源补丁和原生输入共用精确历史，撤销与重做恢复相同字节，失败保留文档。删除保留可能共享的关系和媒体，解码缓存只保留实际引用的图片。

双格锚点的起止标记重合时，图片仍保留源标记和媒体，网格与打印省略该图片。有有效 DrawingML 尺寸的 `twoCellAnchor editAs="oneCell"` 按 `move` 读取，以起点定位，以原生尺寸绘制。普通单元格编辑只同步实际改变几何的对象。隐藏填充、隐藏描边和关闭本地 DPI 的压缩元数据按源保留。依据 [LibreOffice 锚点读取](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sc/source/filter/oox/drawingfragment.cxx#L278-L304)及 [Office DrawingML 隐藏填充](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.office2010.drawing.hiddenfillproperties?view=openxml-3.0.1)。

更换图片时，核心分配新媒体路径及关系，只修改所选图片的 `a:blip/@r:embed`。旧关系与媒体保留，共用原资源的其他对象不改变；新 MIME 与内容类型跟随实际字节，不依赖文件扩展名。同字节替换不新增历史。新资源、关系和源补丁合为一项事务，撤销移除本次新增资源，重做恢复同一字节。单图上限为 2 MiB，解码与累计资源沿现有图片上限；Web 先提交原生单元格草稿，再预检和解码，失败保留源。文件读取期间文稿版本或工作表变化时，默认面板拒绝提交并要求重新加载图片。实现归 [`picture-replace.mbt`](../../../modules/formats/src/xlsx/picture-replace.mbt)，图片源修改参考 [ONLYOFFICE 图像属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L4191-L4203)，锚点、源裁剪和元数据继续沿本 SDK 的保留规则。

`XlsxPictureSettings.crop` 必填，按左、上、右、下保存四个源裁剪比例；每项为 0–1 之间的有限数，不含 1。核心按原生 1/100000 精度舍入，再检查对边之和小于 1。裁剪保留框的位置与尺寸，不改压缩图片字节；全零移除原生 `srcRect`。拖动、缩放和整表复制保留裁剪。默认图片面板提供四边百分比，步长为 0.001%，沿原属性按钮提交；“重置裁剪”只恢复完整图片，不提交其他未应用草稿。

`noCrop` 锁阻止改变裁剪，原有对象选择/尺寸锁继续生效。未知裁剪属性、子内容、注释和处理指令保护源；裁剪展开后的每轴尺寸最多 1e9 pt。无效值、舍入后为空或预算失败整体拒绝；相同裁剪、位置、尺寸及文字不新增历史。实现归 [`picture-crop.mbt`](../../../modules/formats/src/xlsx/picture-crop.mbt)，复用 DOCX 裁剪精度与现有图片事务。比例解释参考 [ONLYOFFICE 图片裁剪系数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L947-L959)，原生顺序沿 [BlipFill 序列化](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Fills/BlipFill.cpp#L159-L173)。

每表图片和基础图形合计最多 256 项，压缩图片源合计最多 16 MiB；新输入最多 2 MiB，尺寸为 0.1–14400 pt。字体、RGBA、历史及包输出继续沿用共享预算。工作表保护、对象锁、未知锚点及复杂图形、旋转/翻转、外链及不支持的绘图样式保持保护并返回原因。`twoCellAnchor editAs="absolute"` 和复杂图形继续实施；其余资源迁移沿现有保护。实现归 [`picture-read.mbt`](../../../modules/formats/src/xlsx/picture-read.mbt)、[`picture-edit.mbt`](../../../modules/formats/src/xlsx/picture-edit.mbt)、[`picture-reflow.mbt`](../../../modules/formats/src/xlsx/picture-reflow.mbt)及 [`spreadsheet-canvas.ts`](../../../packages/xlsx/src/web/spreadsheet-canvas.ts)。

普通图片随整表复制、改名及删除，沿现有 `editSheet` 命令和默认表管理按钮操作。复制创建独立绘图 XML 与关系，保留三种锚点、图层、文字、裁剪及部件内图片身份；不可变 PNG/JPEG 字节共用。副本图片可单独修改，源图片保持；同表便笺和结构化表继续各自建立副本。改名沿原有引用事务保留绘图归属。删除移除该表的绘图 XML、关系及内容类型，保留可能共享的图片字节。源与副本的编辑、删除及输入共用精确历史；保存重开后可继续编辑。

表管理先验证普通图片及独立绘图归属；未知对象、共享绘图、图片链接/扩展身份和非图片绘图关系继续保护。原始客户端先提供字体 profile，默认宿主在首次资源测量后沿现有队列刷新可用状态。工作簿结构保护、资源和历史预算继续生效。实现归 [`picture-sheets.mbt`](../../../modules/formats/src/xlsx/picture-sheets.mbt)，锚点及对象独立复制参考 [ONLYOFFICE copyObjects](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7391-L7421)。

整行、整列插入或删除复用原有 `editSheet` 命令和默认按钮。固定图片保持位置与尺寸；单格锚点只随起点之前的行列移动；双格锚点同时维护起止标记，在图片内部插入或删除时改变尺寸。删除覆盖单格锚点时保留原索引与偏移；覆盖双格起点时截到删除起点，至少保留一格跨度。截断只清零受影响轴的偏移，另一轴保留。图片身份、替代文字、裁剪、锁和资源保持，自动行高重排后同步最终原生姿态；几何未变的姿态片段保留原源。图片、单元格、引用和选择共用一次精确历史，重开后可继续输入及输出 PDF。

结构编辑先验证工作簿中的全部支持绘图。原始客户端须先以相同 revision 的 `pictures` 或 `viewport` 提供字体 profile，默认宿主自动准备。未知绘图、共享绘图部件、工作表保护、锚点越界及候选预算失败整体拒绝。局部单元格移位保留三种锚点标记，需要跟随尺寸的对象仍响应自动行高重排。依赖行列变化沿锚点策略调整，直接对象修改仍遵守对象锁。实现归 [`picture-axis.mbt`](../../../modules/formats/src/xlsx/picture-axis.mbt)，移动和缩放策略依据 [ONLYOFFICE 行列绘图更新](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/DrawingObjects.js#L3232-L3511)。

画布图片可以选择、拖动及四角等比缩放。图片覆盖范围和可见手柄由核心按冻结窗格裁剪，重叠图片沿源顺序命中；方向键以 1 pt 操作，Shift 改为 10 pt，Delete 删除对象。核心保留图片选择，普通单元格选择结束图片选择；原生事务及撤销/重做同步恢复它。候选完整网格沿同一 Canvas 绘制，抬笔只提交一项历史。Escape、失焦、捕获丢失、滚动及过期几何取消候选。保存及常规修改入口先取消候选；其他命令改变几何后也会取消过期候选。只读查询保留候选。

`XlsxSession/XlsxClient.execute({ operation: "selectDrawingXlsx", revision, layout, objectId })` 绑定当前网格选择图片或基础图形，null 清除选择。`execute({ operation: "drawingGestureXlsx", revision, layout, gesture: { handle, dx, dy, commit }, profile })` 返回 `{ query, drawing, selection }`。handle 为移动 0，或屏幕左上/右上/右下/左下 1–4；增量为屏幕方向的 point，核心处理 RTL。commit=false 返回候选网格及 null query，保留源、revision 和历史；commit=true 沿已有原生位置事务写入，返回 query 及 null drawing。候选只分配新的绘制身份，不能据此确认保存。手势增量每轴限 ±14400 pt，沿用原生尺寸、位置、锁定、资源及历史预算。缩放固定对角；图片保留当前比例，图形自由调整宽高，noChangeAspect 锁要求等比。翻转继续实施。实现归 [`drawing-pointer.mbt`](../../../modules/formats/src/xlsx/drawing-pointer.mbt)及 [`spreadsheet-drawing-pointer.ts`](../../../packages/xlsx/src/web/spreadsheet-drawing-pointer.ts)，参考 [ONLYOFFICE 缩放候选及比例保护](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L634-L678)。

绘图拖动及四角缩放复用现有指针调度器，在视口边缘持续滚动。可选 `gesture.viewport = { originX, originY, scrollX, scrollY }` 使用 point：origin 是开始时相对原网格画布的屏幕坐标，scroll 是当前绝对滚动量，两轴均非负，RTL 水平量也为正。核心从原布局换算冻结/滚动区域及 RTL 位移，候选网格和对象选框使用当前滚动位置。候选保留源、revision 和历史，抬笔只提交一项位置事务；Escape、手动滚动、保存和释放实例沿已有取消屏障恢复原对象。起点必须位于原视口内，滚动量每轴最多 10⁹ pt，换算后的总增量继续受 ±14400 pt 限制。宿主按候选网格更新滚动范围，保留原手势布局身份；外部视口变化仍取消手势。坐标依据参考 [ONLYOFFICE 绘图区域偏移换算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/DrawingObjects.js#L4172-L4193)。

`editSheet(revision, sheet, { action: "drawingOrder", objectId, direction })` 调整图片与基础图形层次。direction 接受 `front`、`back`、`forward`、`backward`，对应置顶、置底及移动一层。默认图片和图形面板使用四个图层按钮。核心移动原始锚点片段，保留身份、位置、尺寸、文字、裁剪、资源和片段间的注释/空白；网格显示、命中及 PDF 采用同一原生顺序。一次实际调整只记一项历史，并选择目标图片；已经位于边界时保持源、revision、选择和历史。普通单元格输入可以继续，撤销/重做和重开保持原生内容。同步核心或原始客户端先用相同 revision 的 `pictures` 或 `viewport` 提供字体 profile，默认宿主自动准备。锁定、工作表保护、失效身份、未知绘图或预算失败整体拒绝。基础图形共用原生顺序；组内层次继续实施。实现归 [`drawing-order.mbt`](../../../modules/formats/src/xlsx/drawing-order.mbt)，参考 [ONLYOFFICE 图层顺序操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L9589-L9688)。

### 工作表基础图形

`SpreadsheetEditor.objects.shapes()` 返回当前表的 `{ revision, sheet, reason, items }`。`insertShape(kind, width, height, text)` 在所选单元格插入矩形、椭圆、直线或文本框，kind 分别为 `rect`、`ellipse`、`line`、`textBox`。`setShape(id, settings)` 修改完整属性，`deleteShape(id)` 删除目标。同步 `XlsxSession` 和 Worker `XlsxClient` 使用对应的显式 revision/sheet/profile 参数。宿主复用现有草稿屏障和串行队列。默认图形面板提供创建、完整属性修改和删除；原生文字输入与属性提交沿用同一文档历史。

属性包含锚点、point 位置/尺寸、名称和替代文字、六位 RGB 填充/描边、线宽及普通文字。`fill`、`stroke` 为 null 时不绘制。文字支持统一字体、字号、粗体、斜体、颜色、换行、水平/垂直对齐，以及 `insets: { left, top, right, bottom }`。字号为 1–400 pt，线宽为 0–1000 pt，每项内边距为 0–14400 pt；文字最多 32767 个 UTF-16 单位。矩形、椭圆及文本框的宽高至少 0.1 pt；直线允许一个轴为零，另一个轴至少 0.1 pt。对象每轴尺寸不超过 14400 pt，位置沿工作表边界校验。

基础图形与图片共用原生绘图顺序、身份、三种锚点、行列重排及工作表资源事务，每表合计最多 256 项。图形保存 `xdr:sp`、预设几何及 DrawingML 文字，不另建 TS 文档模型。轮廓复用 PPTX 的基础路径，文字复用共享塑形与换行；椭圆先采用原生内接文字矩形，再加文字内边距。字体键随绘图加入 `fontKeys`。网格、Canvas 和 PDF 使用同一 R0 图元。 `XlsxViewport.objects` 按原生顺序返回 `{ id, kind, name, selected, regions }`；kind 为 picture、chart 或四种基础图形。可见区域与手柄归核心计算，零轴直线的命中矩形每轴至少 6 pt，再按窗格裁剪。

无描边的实心矩形使用现有矩形填充图元。核心保留源几何、颜色、文字和锚点，Canvas 复用共享的像素边界处理。50%、100%、150% 三种缩放下，固定、随格移动和随格缩放三种锚点的独立原生整页 Canvas/PDF 均为 0/0。有描边及其他几何保留原路径；本项不增加宿主采样规则。范围与右到左剩余差异见[测试说明](../testing.md#当前兼容证据入口)。

相同属性不新增历史；修改、层次、行列插入、复制、删除与普通输入共用精确历史，保存后可继续编辑。核心手势区分图形自由缩放与图片等比缩放，候选保留源及历史；默认画布控件支持选择、拖动、四角缩放、方向键、Shift 大步移动及 Delete 删除；图片和图形按各自原生事务处理。选择、移动、尺寸、比例、文字和形状类型锁分别保护对应修改。未知属性、扩展、注释、处理指令、复杂文字、旋转/翻转及复杂几何受保护，候选资源或输出超限整体拒绝。这里只覆盖普通统一文字图形，尚不代表完整 DrawingML 支持。

实现归 [`shape-read.mbt`](../../../modules/formats/src/xlsx/shape-read.mbt)、[`shape-edit.mbt`](../../../modules/formats/src/xlsx/shape-edit.mbt)、[`shape-preserve.mbt`](../../../modules/formats/src/xlsx/shape-preserve.mbt)、[`shape-paint.mbt`](../../../modules/formats/src/xlsx/shape-paint.mbt)及 [`xlsx-shapes.ts`](../../../packages/xlsx/src/core/xlsx-shapes.ts)。椭圆文字矩形参考 [ONLYOFFICE CreateGeometry](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L3100-L3117)，锁定分类参考 [GraphicObjectBase](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L166-L183)。

### 工作表图表

工作表绘图锚点和图表关系有效时，视口保留能绘制的对象，并为不支持的图表内容报告部件路径。绘图编辑和该工作表的打印仍要求完整读取绘图目录。原样保存保留全部图表部件。[兼容性验证](../testing.md#当前兼容证据入口)

图表目录允许导入缓存的类别、系列名或数值使用字面量，没有来源引用时保留空绑定。曲面与气泡的目录保留原生类型。读取沿现有字段、数量、文字及绘图边界校验；插入和配置修改仍要求完整引用，并保留原生配置的编辑保护。宿主复用同一字段校验，分别执行读取与编辑的绑定要求。

原生三维柱条图现支持 `box` 的标准透视柱图，以及零旋转、直角轴的堆积条图。缓存最多 32 个系列、256 个分类；来源、轴关联、有限投影参数和样式均校验。系列沿深度排列，普通路径输出可见面，沿用现有 Canvas/PDF；透明系列仍占堆积位置。分类、值和系列轴、标题、右侧图例、纯色底面及线条复用现有字体和主题规则。两个底部轴标题分别预留空间，原生边框保留完整描边裁剪。数轴顶部另留半个文字框，刻度沿三维方向投影；系列轴文字沿深度中心定位。分类轴标题贴近图框底部，纵轴标题按投影后的刻度文字范围定位。标准柱面按最近顶点深度排列，同深度按首点纵坐标排序。面路径画回起点并保留线段端头，点顺序与原生路径一致。三维面的尖角描边限制采用独立原生 PDF 的 10 倍线宽。绘图区和最终文字分别采用原生的 16px、17px 边距。其他形状、堆积透视、非零旋转直角轴、网格及源改写和复制继续保护。

C43 的两处原始锚点和源保存已接通。固定 Arimo 与缓存图框下，零旋转堆积条图的完整 Canvas、整页 PDF 均为 0/0，原样保存和新 Worker 的 PDF 字节一致。透视柱图的完整 Canvas/PDF 也已通过严格对照；整文件范围归[测试说明](../testing.md#当前兼容证据入口)。实现归 [`native-bar3d.mbt`](../../../modules/formats/src/internal/chart/native-bar3d.mbt)、[`native-bar3d-project.mbt`](../../../modules/formats/src/internal/chart/native-bar3d-project.mbt)及 [`native-bar3d-paint.mbt`](../../../modules/formats/src/internal/chart/native-bar3d-paint.mbt)。独立实现依据 [ONLYOFFICE 深度和比例](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/3DTransformation.js#L1030-L1124)、[相机拟合](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/3DTransformation.js#L1125-L1300)、[轴标题留量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L995-L1020)和[文字框](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L3396-L3475)。面顺序、路径端头和投影文字范围分别依据 [ONLYOFFICE 最近深度排序](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L6703-L6800)、[面路径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L4350-L4471)及[三维文字范围](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L7522-L7582)。最终文字边距已同时核对该源码和独立参考使用的 10.0.0 包。证据归[测试说明](../testing.md#当前兼容证据入口)。

三维柱图和曲面图的深度轴标题沿选定 ONLYOFFICE 外观处理。自动位置标题不可见，绘图区仍预留标题空间，源文字与属性保留。水平标题支持显式 `xMode=edge` 与 `yMode=edge`，坐标分别按图框宽高的比例读取，范围为 0 到 1。手工位置只移动标题；能容纳时，带内边距的标题框限制在图框内。[ONLYOFFICE 标题定位分支](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L655-L708) [Office 边缘定位](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/bb8565e7-dfea-453f-868b-ae680ab8a823)

短图框的水平堆积条图按分类标签高度预留纵向空间。在预留数值轴文字前后各测一次分类间距，用两次留量调整绘图区的上下边界。[原生坐标轴留量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L6960-L7043)

原生双轴散点图复用折线的轴、平滑曲线、图例与主题路径。当前配置支持一至两组 `lineMarker`、共同数值 X、各组 Y 轴及逐点 RGB 样式；双组要求手工外边界。双组图按系列列出图例。单系列组启用 `varyColors` 时，沿固定 ONLYOFFICE 规则在绘图区只画曲线，源标记属性和图例规则保留。X 按数值比例定位，空 X 断开曲线，显式轴范围外的标记省略；次轴采用散点的 5% 范围留量。三角、星、加号、点及短横标记复用共用路径；叉形、星形及加号可绘制标记填充的外框。标题允许多个仅语言不同的同样式文字段，文字和资源预算保持。独立 X 来源、对数或反向轴、其他散点样式和源改写继续保护。[ONLYOFFICE 系列标记初始化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L10153-L10305)

散点图只有一组和一个系列时，`varyColors` 或显式逐点形状样式启用逐点图例。标签用从 1 开始的源点编号，缺失点保留空位。右侧图例按绘图区高度容纳条目，底部图例按图框宽度分列换行。[ONLYOFFICE 图例编排](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L7810-L8415)

稀疏散点缓存沿选定主引擎的绘制顺序取标记画笔。缓存位置缺项时，沿用此前标记的填充和描边，标记坐标保持。C43 缺首点时，首个有效 X 使用此前的品红画笔；独立真实零值控制恢复源青色，后续坐标相同。原件的缓存零值、工作表错误和标记属性分别保留，手工缓存与已计算绑定值沿既有计算规则显示。[ONLYOFFICE 缓存画笔](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L3040-L3084) [散点缓存路径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L14845-L14925) [测试说明](../testing.md#当前兼容证据入口)

C43 的五个散点系列、原锚点及源保存已接通。70 项相关核心检查通过，原始隔离图的完整 Canvas 和整页 PDF 均为 0/0，原样保存及新 Worker 的 PDF 字节一致。原工作表第 5 页两种输出也为 0/0，其他页面继续逐项验收。浏览器用例、独立参考和阈值保持；证据归[测试说明](../testing.md#当前兼容证据入口)。实现归共用 [`native-line-read.mbt`](../../../modules/formats/src/internal/chart/native-line-read.mbt)、[`native-line-layout.mbt`](../../../modules/formats/src/internal/chart/native-line-layout.mbt)及 [`native-line-style.mbt`](../../../modules/formats/src/internal/chart/native-line-style.mbt)。数值范围、标记形状和旋转标题分别参考 [ONLYOFFICE 散点范围](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L2693-L2713)、[标记](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L3175-L3256)及[轴标题](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L750-L817)。

原生折线图和散点图的标记沿用显式实线描边宽度。宽度为零时使用设备细线，`a:noFill` 关闭描边。显式设置填充的标记可省略描边。使用系列配色时，系列按源 `idx` 取工作簿主题配色和线宽，逐点样式沿用系列标记描边。单系列逐点配色时，省略的描边依次取显式逐点形状、系列标记、系列曲线。缺少可解析来源时继续保护。散点图区的菱形描边在左侧顶点开口，图例的菱形闭合。[实现](../../../modules/formats/src/internal/chart/native-line-read.mbt) [ONLYOFFICE 标记继承](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L10217-L10322) [独立对照](../testing.md#当前兼容证据入口)

原生二维饼图与圆环图已接通只读缓存和矢量绘制。饼图要求一个系列，圆环图沿用 1–32 个系列上限；分类与各值缓存须对齐，最多 256 点。缺少分类来源时生成从 1 开始的标签，依赖与隐藏索引使用实际值来源。支持显式 RGB、`diagBrick/pct80/pct90` 两色图案、实线或无轮廓、旋转、内孔、系列及点的爆炸偏移。圆环图只偏移最外环，扇区受图框限制。原生源改写和复制继续保护；现有生成图表保留可写路径。

圆环图逐环按点编号递增绘制，数据标签沿用同一顺序。原生圆环扇区从内弧端点起笔，沿外弧返回，再沿内弧回到起点，保留开放的描边接缝。普通饼图按点编号递减绘制。[ONLYOFFICE 圆环绘制](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Charts/ChartsDrawer.js#L13328-L13354) [原生扇区路径](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Charts/ChartsDrawer.js#L13543-L13550)

支持的原生工作表图表允许省略系列名称。显示名采用源 `idx + 1` 生成 `Series N`，名称不绑定单元格；分类、数值及气泡尺寸仍逐系列保留各自引用。显式空引用继续拒绝，保存不补写名称节点。依据 [ONLYOFFICE 默认系列名称](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/Drawings/Format/ChartFormat.js#L4105-L4124)。

原生折线数据标签的正文宽度限于图框宽度的五分之一，扣除两侧内边距。长名称和值按现有文字规则换行，各行使用原生字符推进量居中；短标签保持原位置。实现复用趋势线文字的推进量和装饰线计算。依据 [ONLYOFFICE 标签宽度](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/Drawings/Format/ChartFormat.js#L3262-L3323)及[内容排版](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/Drawings/Format/ChartFormat.js#L3384-L3467)。

当前原生圆形配置支持单段标题、右侧单列图例及可选手工位置。标签保留系列、分类、值、百分比和分隔符；饼图支持中心、内基部、内端、外端及自动适配位置，圆环图支持中心和内基部。字号按原生 DrawingML 导入规则舍入到半磅；缺失点、零值和可见索引沿缓存语义处理。有限的 RGB 外阴影元数据校验后保留，按原生图表路径仅消费画笔与填充的行为省略阴影绘制。未知效果和布局继续诊断。

圆形数据标签按原生一毫米内容留量，在最大行宽内逐行居中。标题框计入相同留量和正文边距，顶部由七个 96 dpi 像素与 0.508 mm 正文内边距组成。源文字、字号、扇区、图案及图例保持。依据 [ONLYOFFICE 内容留量与边界](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Drawings/Format/ChartFormat.js#L3604-L3680)、[正文内边距](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Drawings/Format/ChartFormat.js#L3592-L3597)及[标题位置](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Charts/ChartsDrawer.js#L738-L748)。四份独立字面 XML 控制的整页 Canvas/PDF 均为 0/0，原始两图的完整 Canvas/PDF 已通过，范围见[测试说明](../testing.md#当前兼容证据入口)。

圆形绘图区的背景使用居中正方形，左、上各延伸一个 96 dpi 像素。缺省分类中的缺失点保留空图例文字，标记使用所属工作簿主题的缺省图表配色；零值保留原分类文字和显式样式。图案图例使用标记自身的局部原点。实现复用共享主题颜色运算，依据 [ONLYOFFICE 圆形图区](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L9037-L9090)、[背景边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L17431-L17503)及[主题循环配色](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L12365-L12435)。

实现归 [`native-circular.mbt`](../../../modules/formats/src/internal/chart/native-circular.mbt)、[`native-circular-paint.mbt`](../../../modules/formats/src/internal/chart/native-circular-paint.mbt)、[`native-circular-label.mbt`](../../../modules/formats/src/internal/chart/native-circular-label.mbt)、[`native-circular-fill.mbt`](../../../modules/formats/src/internal/chart/native-circular-fill.mbt)及共用 [`chart-pie.mbt`](../../../modules/layout/src/chart-pie.mbt)。几何与标签独立实现依据 [ONLYOFFICE 饼图](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L12239-L12323)、[圆环图](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L14102-L14383)、[标签适配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L13507-L13855)、[标签内容和边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L3232-L3270)及[半磅字号](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L9074-L9083)。原始两锚点、完整可见图框及整页 PDF 已通过独立颜色对照；原生图案规则与范围见[测试说明](../testing.md#当前兼容证据入口)。

手工计算下，缺省分类的原生饼图将已知源错误对应的缓存零绘为空点。源数值零保留图例文字和样式。此绘制判定保留源错误和导入缓存。[ONLYOFFICE 图例的缺省文字](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L7945-L7973)与[缺失点标记](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L8010-L8021)。

饼图、圆环图和复合饼图的空值点仍可设置图例填充。点的 `c:dPt/c:spPr` 含显式填充时，图例沿用点的样式。省略点填充时使用现有主题色。空值仍不占绘图区面积。[OOXML 数据点属性](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.charts.datapoint?view=openxml-3.0.1) [独立对照](../testing.md#当前兼容证据入口)

普通饼图与圆环图复用工作表的打印锚点顺序。前面有可打印的原生三维条柱图时，绘图区采用 17 个 96 dpi 像素的边距。其他情况采用 14 像素。独立顺序对照见[测试说明](../testing.md#当前兼容证据入口)。[ONLYOFFICE 圆形绘图区](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L1091-L1122) [三维绘图后的边距](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L3482-L3491)

工作区的扇区底纹从路径边界左上角开始平铺，边界计入三次曲线控制点。扇区路径裁剪底纹，随后绘制轮廓。固定图案周期和源色保留。打印沿选定 ONLYOFFICE 外观省略单曲线扇区的底纹，保留跨象限扇区的底纹和全部轮廓。独立 0°、45°、90° 旋转控制支持此区别；源图案属性原样保存。[ONLYOFFICE 画刷边界](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/PdfWriter.cpp#L3976-L4020) [路径控制点](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/SrcWriter/States.cpp#L600-L650) [独立对照](../testing.md#当前兼容证据入口)

图表工作区使用源底纹的 8×8 设备像素单元，保留图框、绘图区和扇区各自的小数起点。打印预览和 PDF 的矩形图框、绘图区及图例底纹仍按 6 pt 周期绘制。[测试说明](../testing.md#当前兼容证据入口)

原生饼图和圆环图读取 `openDmnd` 与 `smCheck` 底纹。逐点标签完整重复所属系列设置时，复用系列标签绘制。接受 `General` 缓存格式和默认方形换行声明。真正的逐点覆盖和重复编号继续报告未支持。源标签与图形属性随原文件保存。[ONLYOFFICE 底纹位图](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/Drawings/HatchPattern.js)

普通饼图的 `bestFit` 标签沿选定 ONLYOFFICE 的扇区定位，保留原生自动适配位置。已启用的引导线从扇区外缘接到最终标签边界，保留源实线颜色和宽度。间隔小于图框对角线的 1% 时省略。[Office 饼图标签默认位置](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oe376/7dd610ae-d805-40a4-ae3b-c171b6bf08e3) · [ONLYOFFICE 标签适配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L13507-L13855)

原生圆形图工作区按整数设备坐标放置轴对齐字形。TrueType 轮廓按视口的实际设备倍率执行字体内置指令。文字原点、字距和字号保持原值，打印沿用矢量轮廓。[ONLYOFFICE 字形落点](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/graphics/Graphics.cpp#L1024-L1065)

原生图表现可随已计算的绑定数据更新缓存。现有单元格事务只改 `strCache/numCache` 的数据点和值，并按数据长度维护点数；源公式、轴组、绘图区、样式和缓存数字格式保留。系列名称、分类、数值 X/Y 及有来源的气泡尺寸沿同一事务更新。数值零保留；空值或公式错误移除对应数值点，恢复数值后沿原编号补回。未改变的数值保留源文本，命名空间沿源声明写入。数据点外的注释保持；需要覆盖或移除含注释的数据点时原子拒绝。新缓存须重新通过原生读取器及既有资源限制。配置改写、源重绑定和原生复制仍受保护；手工计算沿[显示与计算](xlsx-calculation.md#显示与计算)的显式重算规则，未知公式继续保护。

实现归 [`worksheet-cache.mbt`](../../../modules/formats/src/internal/chart/worksheet-cache.mbt)和既有绑定事务。缓存含义依据 [OOXML 数值缓存](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.charts.numberingcache?view=openxml-3.0.1)与[数值引用](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.charts.numberreference?view=openxml-3.0.1)；缺失数值点与点数沿 [ONLYOFFICE 缓存数据更新](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Drawings/Format/ChartSpace.js#L5872-L5892)处理，代码独立实现。此处只扩大缓存数据更新，不授予原件手工重算或完整视觉资格。

原生柱线混合图复用只读折线模型，目录沿用 `line`，不增加插入类型。当前支持柱组在前、折线组在后，各自链接一套分类轴和数轴；第二分类轴隐藏，右数轴可见，绘图区自动布局。柱图限竖向簇集、零重叠与 0–500 的整数间距；保留源系列在簇内的位置，按 `order` 绘制，逐点填充和描边随原点编号筛选。打印自动布局按工作表锚点顺序选取边距。前面有可打印的原生三维条柱图时，组合图采用 17 个 96 dpi 像素的边距。其余情况采用 14 像素。柱体先于轴线绘制，折线和标记随后绘制。X 标记保留原生中心移笔、对角线方向及子路径顺序。未知轴组、反向组顺序、其他堆积/重叠、标题或图例及源重写继续保护。实现归 [`native-column.mbt`](../../../modules/formats/src/internal/chart/native-column.mbt)和既有折线读取、布局、绘制；簇宽依据 [ONLYOFFICE 柱宽与间距](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Charts/ChartsDrawer.js#L6735-L6745)，代码独立实现。

三维柱图、曲面、圆形及折线图的手工图例沿 [ONLYOFFICE 边界定位](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Drawings/Format/ChartSpace.js#L6083-L6101)移回图框内。确实放不下的三维图例仍拒绝。独立小图框控制及原始工作表的绘制检查见[测试说明](../testing.md#当前兼容证据入口)，实现归 [`native-legend.mbt`](../../../modules/formats/src/internal/chart/native-legend.mbt)。

原生条形复合饼图与饼形复合饼图复用只读圆形模型，按用户选择的 ONLYOFFICE 兼容行为显示为普通饼图。一个系列的原始点值、分类和逐点样式参与绘制，起始角为零。次图及连接线不绘制，原始拆分定义、尺寸、间距和连接线属性保留在源 XML。目录沿用原生 `pie` 类别；配置改写、可见数据标签和爆炸偏移继续受保护。[ONLYOFFICE 普通饼图转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L12845-L12856) [输入校验](../../../modules/formats/src/internal/chart/native-circular-split.mbt)

拆分属性继续严格校验：位置计数接受 `0` 至 `32000` 的整数，百分比阈值接受 0 到 100。自定义成员须唯一且保留两个非空分组；非法索引、冲突规则、非有限数值及越界尺寸拒绝。不同的有效拆分规则使用相同的普通饼图显示，保存后各自源定义保持。[Office 范围](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oe376/99656dce-2698-452b-ad7d-63ba27d19f7b) [独立对照](../testing.md#当前兼容证据入口)

复合饼图省略 `gapWidth` 或 `secondPieSize` 时，分别按 100 和 75 校验。空节点也采用对应默认值；这些保留属性不改变当前显示。[Office 间距默认值](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oe376/9b53973a-1c02-4231-ad7c-02996b79021b)

复合饼图接受显式关闭的数据标签，并保留圆角描边和单段格式化标题。可见的数据标签继续受保护。普通工作表中的图表复用绘图锚点读取，双单元格锚点标为 `oneCell` 时随单元格移动并保持源尺寸。[OOXML 圆角连接](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.round?view=openxml-3.0.1)

缺省标题沿用源系列名称，采用 18 pt 粗体。它与显式图表文字共用字体原生行距，并关闭字距调整，避免自动标题的基线偏高。同名、同字体的显式标题控制核对行高与文字宽度；导入和保存保留源标题节点、拆分规则及缓存。实现归 [native-circular.mbt](../../../modules/formats/src/internal/chart/native-circular.mbt)。

原生气泡图按用户选择的 ONLYOFFICE 外观显示为无连线散点标记。当前配置要求无标题、共同数字 X、单对自动数轴及受支持的实色样式；支持无图例或右侧单列图例，保留原生手工位置。系列编号决定标记形状和主题色，默认尺寸为原生 7 号。可见的 X/Y 决定标记位置，零、负或空的气泡尺寸不再控制显示。原始尺寸、系列及点的 `bubble3D` 属性保留在源包，目录继续报告 `kind: "bubble"`。[ONLYOFFICE 气泡转散点](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L9789-L9838)

尺寸仍读取独立的数字引用或字面缓存，并参与未计算来源保护和缓存更新。省略 `bubbleSize` 时保留空尺寸，不补写固定半径或缓存。显式尺寸与 X/Y 必须对齐。非有限数值、重复或非整数系列编号、非顺序系列、非法标签与未支持开关继续拒绝。显式源系列颜色保留；显示沿主引擎转换结果采用主题标记，已支持的逐点画笔优先。原始定义、图框、数据和精确历史保持，配置改写继续受保护。

气泡图共用原生散点的轴线、文字、图例和裁剪路径。数字 X 轴为末端标签预留半个字宽，右图例另预留自身宽度及标准间距。图例三角形使用闭合包围框几何，绘图区三角形保持原生等边路径。前面有可打印的三维条柱图时，自动边距采用 17 个 96 dpi 像素；单独打印采用 14 像素。默认图框沿主题解析，显式图框优先。屏幕与打印均使用正常对象裁剪，图表页沿共同的 0.75 pt 起笔规则。旧的圆面积缩放、字体校准、`PixelCenters` 和气泡专用打印适配已移除。[原生图例三角形](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L17074-L17084) [数轴边界修正](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L6950-L7041)

实现归 [`native-bubble.mbt`](../../../modules/formats/src/internal/chart/native-bubble.mbt)、[`native-bubble-paint.mbt`](../../../modules/formats/src/internal/chart/native-bubble-paint.mbt)及共用的原生折线布局和绘制。独立屏幕、同倍率打印、尺寸缓存和源保存的实际检查归[测试说明](../testing.md#当前兼容证据入口)。旧 LibreOffice 圆形输出保留为历史诊断。

原生百分比堆积面积图现可读取共同分类和全部系列缓存，保留显式 RGB 填充、实线轮廓、网格、百分比轴和统一文字标题。分类轴标题水平放置，数值轴标题支持原生 −90° 方向；字体映射保留粗体身份。系列按原顺序作带符号累计，以各分类绝对值总和归一化，空值按零绘制，源缓存保持。标题内边距参与绘图区计算。无图例、单对可见轴及 `dispBlanksAs=zero` 的当前原生配置保持只读；未知样式、手工范围和源重写继续保护。实现归 [`native-area.mbt`](../../../modules/formats/src/internal/chart/native-area.mbt)及 [`native-area-paint.mbt`](../../../modules/formats/src/internal/chart/native-area-paint.mbt)，依据 [ONLYOFFICE 面积累计与空值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L10840-L10891)、[相邻累计边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L9744-L9815)及[同版标题尺寸](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Drawings/Format/ChartFormat.js#L3604-L3685)，未复制上游执行代码。

面积图的可见轴支持 `none/in/out/cross` 主次刻度。主刻度单侧长 3.75 pt，次刻度为 2.25 pt。分类次刻度位于分类中点，数值次刻度将主间隔分为五段。分类轴及其刻度先于数轴绘制。显式图框保留源颜色和线宽，已关闭的标签可保留文字格式和引导线扩展。源 `round` 节点保留，绘制沿用原生面积图的斜接输出。移除这些节点的独立对照产生相同的 PDF 内容流。[ONLYOFFICE 刻度尺寸](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/Charts/ChartsDrawer.js#L16584-L16629) · [独立对照](../testing.md#当前兼容证据入口)

工作表打印按绘图锚点顺序布局原生百分比堆积面积图。前面有可打印的原生三维条柱图时，面积图采用 17 个 96 dpi 像素的边距。面积图排在前面或单独打印时，边距为 14 像素。打印布局在各工作表内计算此顺序，跨页沿用。[ONLYOFFICE 三维图边距赋值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L3480-L3491)、[独立顺序对照](../testing.md#当前兼容证据入口)。

零旋转、直角轴的三维堆积面积图已接通读取和绘制，保留手工外绘图区、隐藏数值轴、分类网格及全部源系列。数轴沿选定 ONLYOFFICE 用紧凑的非空缓存位置累计，几何仍按源点编号累计。编号 0 的点缺失时，省略该系列的面；真实零值保留。缓存零、绑定错误和其他有效数据随原件保存。非零旋转和其他三维配置继续保护。三维面沿用原生同色 0.2 mm 轮廓，零旋转的底面描边用源线宽的水平直线。手工外绘图区扣除分类标签留量，按分类数 n 将纵向范围收缩为 (n−1)/n；标题使用三维最终边距。独立字号控制已验证布局，原件及显式零值控制的完整 Canvas/PDF 四组均为 0/0。源改写继续保护。[ONLYOFFICE 范围累计](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L1520-L1608) [缓存位置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L2020-L2090) [系列面选择](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L11045-L11078) [测试说明](../testing.md#当前兼容证据入口)

原生曲面图已接通透视曲面、俯视等高线和线框绘制。当前支持 2–32 个系列、每系列 2–256 个对齐数值缓存、缺省数字分类和系列名称、General 数轴、显式墙面及已有手工外图框。空值按零参与绘制，源引用与缓存分别保留；非法缓存、轴标识、重复顺序、未知区间格式、直角投影和源改写继续保护。数据目录报告只读 `surface`，插入和普通图表重写接口保持原类型范围。核心复用三维相机与普通路径，以工作簿主题生成数值区间色带，线框使用相同切分边界；每次切分最多 131072 项工作量。填充色带的边框由核心复用共享[描边轮廓](../../../modules/layout/src/stroke-contour.mbt)，与 PPTX 矢量阴影使用同一实现。面填充和轮廓分别输出，保留源线宽、平端头与尖角限制；轮廓最多 4096 条命令，曲线继续拒绝。系列标签在投影前预留空间，数轴标题按文本框起点投影。读取与保存保护、独立透视坐标及三组标题/字号控制已通过。实现归 [`native-surface.mbt`](../../../modules/formats/src/internal/chart/native-surface.mbt)、[`区间切分`](../../../modules/formats/src/internal/chart/native-surface-bands.mbt)与[`绘制`](../../../modules/formats/src/internal/chart/native-surface-paint.mbt)，依据 [ONLYOFFICE 曲面拆分](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L15766-L16390)、[主题区间样式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L10010-L10114)、[同版系列标签边界](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Drawings/Format/ChartSpace.js#L7574-L7654)及[三维轴标题投影](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Charts/ChartsDrawer.js#L751-L888)，未复制上游执行代码。完整验收状态归[测试说明](../testing.md#当前兼容证据入口)。

曲面分类轴采用 `between` 时，网格绘制在分类边界，数量为分类数加一。分类标签及曲面采样仍位于分类中心。分类网格从后墙顶端经后墙底端画到前地板，保留原生路径方向。[ONLYOFFICE 分类网格边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L5122-L5194) [三维路径方向](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L5267-L5333)

曲面数轴省去数据范围外多余的一格，负值范围保留零端点。色带切分直接保留恰好落在分界值的源顶点，避免重新插值得到重复的近似坐标。源数值、刻度间距和资源上限保持。[ONLYOFFICE 三维刻度裁边](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L2310-L2344)

曲面图和三维柱图共用系列轴标题的 `edge` 定位。水平标题的 `x` 和 `y` 使用 0–1 的图框比例，按原生文本内边距落位。显式位置只移动标题，绘图区继续保留标题留量。

C43 原件的 26 个系列已通过原始锚点、源保存和重开检查。固定图表页框内的独立控制仅沿既有纸面对齐与 Arimo 常规/粗体替代，正常 Canvas 及整页 PDF 均为 0/0。共享图表容量现为 1–32 个系列，生成引用支持 Z 列后的 AA–AG；输入、规范化文字、XML、布局和历史预算继续生效。32 个系列的 Worker 编辑、精确历史、保存重开及 33 个系列的原子拒绝已检查。C43 原始工作表及重算后完整可见页已通过整页严格对照，范围归[测试说明](../testing.md#当前兼容证据入口)。

无标题、隐藏双轴的原生雷达图已接通缓存读取和矢量绘制。当前支持共同数字或文字分类、显式 RGB 线条、实线及 `sysDash`、方形/圆形/菱形标记、实色填充和相对绘图区。刻度间距复用普通数轴，范围保留雷达图端点；填充图将缺失点作为零值。网格保留隐藏轴下的原生行为，标记阴影 XML 保留，绘制沿 ONLYOFFICE 当前忽略阴影的规则。自动标记、可见轴、手工数轴范围及其他样式继续保护；源重写拒绝。实现归 [`native-radar.mbt`](../../../modules/formats/src/internal/chart/native-radar.mbt)及 [`native-radar-paint.mbt`](../../../modules/formats/src/internal/chart/native-radar-paint.mbt)，独立实现依据 [ONLYOFFICE 雷达几何与填充](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L14380-L14811)和[雷达刻度](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L2278-L2307)。

雷达图的分类轴可反向。显式图框保留源颜色和线宽，线条和网格支持源圆角连接。缺少标记描边时，按系列源编号复用工作簿主题的颜色和线宽。已关闭的标签可带文字格式和引导线扩展。隐藏轴可保留刻度和文字格式；可见标签及反向数值轴继续保护。LibreOffice 另存件的方向检查依据只切换分类轴方向的独立 PDF 对照。[LibreOffice 雷达分类轴方向](https://github.com/LibreOffice/core/blob/bf6ef2662401c7d6dce671ab4deb26ee0af3a7c1/oox/source/drawingml/chart/axisconverter.cxx#L371-L380) · [ONLYOFFICE 标记主题继承](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/Drawings/Format/ChartSpace.js#L10043-L10164)

C43 的两张雷达图已用原始锚点完成核心读取、绘制及源保存检查。原图定义置入固定图表页框后，独立控制仅调整纸面左、上边距，使原框在 144 dpi 下从整数像素起始。图表、图框及全部非目标部件逐字节保持。方形标记沿 [ONLYOFFICE 开放方框](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L3232-L3238)回到起点，Canvas 对齐描边两侧并保留端帽。比较覆盖完整可见 Canvas 图框及整页 PDF；两图 Canvas/PDF 均为 0/0，保存与新 Worker 重开通过。共享曲线描边轮廓消除了线框图圆形标记的最后一个差异像素。早期不同像素原点及画布外透明像素的比较保留为诊断。C43 原始工作表及重算后完整可见页的当前资格归[测试说明](../testing.md#当前兼容证据入口)。

原生二维折线图可显示导入缓存。当前支持单轴自动布局及手工外边界的双轴布局。每组系列绑定独立数轴，保留原分组顺序。数轴支持 General 自动范围或显式上下限。分类共用同一来源，缺失值断线；隐藏系列保留样式对应关系。

直线按相邻数据点分别绘制，每段保留自己的虚线起点。重合点不产生零长描边，后续线段仍按原点编号取样式。平滑线保留既有分段和裁剪规则。[ONLYOFFICE 直线分组](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L9107-L9190)

线条保留显式 RGB、实线、`dash/sysDashDotDot` 虚线和平滑曲线。平滑线在数据坐标中计算切线，每段按 0.1 参数间隔取样，数值沿所属轴范围裁剪。标记支持菱形、方形、圆形、叉形及隐藏；每组先绘制线条，再绘制不受图区裁剪的标记。圆形标记沿[原生右侧起笔与开放描边](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L3158-L3203)。标题保留字体、粗斜体、单下划线和单删除线。轴标题支持正负九十度；其他角度按原角度测量文本框，字形沿原生当前规则保持水平。圆角标志保留源元数据。图例支持右侧单列或底部单行及原生手工位置。数值、系列名称标签保留底色和原生文本框边距。网格先于轴线绘制，轴文字晚于数据标签；同一数轴的主、次刻度共用描边路径，最上端只画主刻度。多项式趋势线支持二至六阶、方程和 R²；有效点不足时降低阶数，少于两点时省略趋势线。方程的混合字号、下划线端点与标签共用原生字符宽度精度，文本框保留内边距。

趋势线标签按图框宽度的五分之四扣除两侧内边距后换行。居中和下划线按各行的可见文字宽度计算。[原生标签宽度](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L3274-L3305)

实现扩展既有 [`native-line.mbt`](../../../modules/formats/src/internal/chart/native-line.mbt)，读取归 [`native-line-read.mbt`](../../../modules/formats/src/internal/chart/native-line-read.mbt)，布局归 [`native-line-layout.mbt`](../../../modules/formats/src/internal/chart/native-line-layout.mbt)，曲线和拟合归 [`native-line-curve.mbt`](../../../modules/formats/src/internal/chart/native-line-curve.mbt)。自动范围、平滑切线和趋势线分别依据 [ONLYOFFICE 数轴](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L2678-L2738)、[曲线](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L3688-L3805)和[多项式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L18484-L18535)，未复制上游执行代码。数轴文字宽度沿[原生字符定点截断](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/RunContent/Text.js#L305-L307)。未知样式、主题字体及下述范围外的自动双轴或混合图继续保护。原生源不会由普通图表生成器重写。完整视觉资格见[测试说明](../testing.md#当前兼容证据入口)。

原生折线图从工作簿主题读取缺省背景、文本色和首个实线笔宽。显式外框保留自己的填充、颜色、线宽和虚线。外框使用原生线性色彩混合，裁剪向外扩展一个笔宽；未知主题线型继续保护。边距采用对应转换器版本的 [ONLYOFFICE 普通图表规则](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Charts/ChartsDrawer.js#L1269-L1304)，标签间隔、图例及裁剪参考 [ChartSpace](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Drawings/Format/ChartSpace.js#L7925-L7968)。分类轴在自动零值处交叉，数据标记按[原生尺寸换算](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Charts/ChartsDrawer.js#L3360-L3368)绘制，图例保留独立标记尺寸及字体基线。代码为本项目独立实现。

`c0-43.xlsx` 主图的两条曲线、数字分类、52 个数据标记和源字体已接通缓存视图。原件的 RAND 共享公式已完整展开，后续单元格保留正确的公式引用。手工模式现保留源结果并允许普通输入；显式重算、精确历史、原样保存和新 Worker 重开通过。固定缓存、固定 Arimo 下，正常整图 Canvas 和整页 PDF 对照均为 0/0。该视觉资格覆盖未编辑缓存主图；手工重算的数值与历史另见[显示与计算](xlsx-calculation.md#显示与计算)，重算后的完整视觉及其他图表仍逐项验收。

来源包含已隔离的未计算公式时，已有普通图表可显示导入缓存。`bindingReason` 返回未计算原因，默认面板显示缓存提示，网格诊断包含 `uncalculated-chart`。核心保留图表源及全部缓存，不将其作为单元格计算结果。缓存长度须匹配有效来源范围；无法解释的缓存继续保护。无关联输入、格式和图框布局可沿原事务提交；分类、标题和数值来源的值、公式或行列显隐变化原子拒绝，保留草稿、历史与重做。纯格式不改变来源值时可编辑。

未计算图表不能转换成剪贴板数值来源。普通工作表的打印区域实际覆盖该图表时拒绝输出；图表页另有上述未编辑手工缓存快照入口。未覆盖图表且单元格已计算的独立区域可打印。显式将全部未计算来源改绑到已计算格后，图表恢复实时缓存与 PDF；只改外观仍须先处理未计算来源。动态或未核实函数继续沿工作簿保护。实现归 [`chart-calculation.mbt`](../../../modules/formats/src/xlsx/chart-calculation.mbt)及既有图表读取、候选事务与打印路径。缓存保留复用现有原生路径，参考 [ONLYOFFICE 未解析来源保留缓存](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L12551-L12568)；未计算来源的编辑与输出沿本项目已计算值合同保护，未复制上游代码。

`SpreadsheetEditor.objects.charts()` 返回当前表的 `{ revision, sheet, reason, items }`。每项包含原生 `id`、名称、替代文字、三种锚点、point 位置/尺寸、图表外观、数据源引用和当前值 TSV。同步 `XlsxSession` 与异步 `XlsxClient` 提供对应显式 revision/sheet/profile 接口。`XlsxViewport.objects.kind` 增加 `chart`；选择、移动、自由缩放和删除沿既有画布入口。

`insertChartRange(range, kind, title, width, height)` 使用当前表的普通矩形：第一行为系列标题，第一列为类别，其余为数值系列。核心生成带表名的绝对引用，在当前选择处插入 `oneCellAnchor`。`insertChart(settings, width, height)` 使用显式 `XlsxChartSettings`：`kind/title/label/legend/holeSize/categories/names/values`。`categories` 为一行或一列的本工作簿来源，`names` 的每项引用一个标题格，`values` 的对应项引用各自的一行或一列，分类与系列允许独立长度。允许本表或跨表普通引用；不接受表达式、外部或三维来源。空标题显示默认系列名，非数值点留空，公式读取当前计算值。

支持簇状、堆积、百分比堆积柱形图/条形图、普通及堆积（含百分比）折线、饼、圆环、普通及堆积/百分比堆积面积图、散点和雷达图。类型、图例、空心比例及实际绘制沿[PPTX 基础图表](pptx-objects.md#pptx-基础图表)的共用模型。`setChart(id, settings)` 修改外观和引用；`setChartFrame(id, frame)` 修改锚点、位置、尺寸及文字；`deleteChart(id)` 删除锚点并保留旧资源。默认面板提供区域插入、引用修改、当前值预览和独立尺寸编辑。宿主先提交原生输入草稿，再执行图表命令。

MoonBit 维护原生 `graphicFrame`、图表 XML、关系、内容类型及系列缓存。普通编辑后，依赖公式、图表缓存、源补丁和布局共用一次候选事务与精确历史，不生成嵌入工作簿。打开时按当前单元格值派生图表，首次查看保留源。修改、保存重开、Canvas 和静态 PDF 使用同一数据及图元。相同设置不新增历史；失败保留文档与历史。

工作表改名同步本表及其他表中普通图表的分类、系列标题和数值引用。核心沿已有词法标记只替换匹配旧表名的片段，保留地址、绝对标记、固定标题、缓存、绘图身份和其他源。名称匹配不区分大小写，中文及名称内单引号使用原生转义；注释和处理指令保留。需要替换的引用文字内部若带这些内容，整项改名保持保护。工作簿名称、普通单元格公式、图表引用和计算共用一次精确历史，重开后可继续改名与输入。实现归 [`chart-rename.mbt`](../../../modules/formats/src/xlsx/chart-rename.mbt)，依据 [ONLYOFFICE 跨表绘图引用改名](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L5550-L5582)。

复制工作表时，已引用的普通图表和所属绘图分别获得独立部件与关系。图表对原表的显式引用改指副本，未限定表名的引用继续按新所属表解释；其他工作表的来源保持。对象在新绘图中保留本地 ID、名称、替代文字、三种锚点和几何，图片沿既有规则共享不可变媒体。源图表、固定标题和非目标字节保留，副本后续改值、改类型或标题不影响原图表。

新表、绘图、图表、关系、内容类型和引用进入既有复制事务，支持混合输入/图表编辑的精确撤销、重做与保存重开。部件路径避让当前包、会话和未引用的同名资源；全部新增源仍受 4 MiB 历史和输出预算约束。源注释保留；需要重写的引用内部若带注释或处理指令，整项复制拒绝。共享图表部件、图表的附加资源及未知绘图身份扩展保持保护。实现归 [`chart-copy.mbt`](../../../modules/formats/src/xlsx/chart-copy.mbt)，依据 [ONLYOFFICE 复制绘图与重绑定本表来源](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7391-L7440)。

删除工作表时，所属绘图、图表、关系和内容类型沿既有部件快照一起移除。共享图片等媒体保留，未知的部件入站引用拒绝整项删除。其他表的图表将被删来源的完整引用写为 `#REF!`，对象及最后有效缓存保留；尚有效的系列继续读取当前单元格值。支持原生带地址尾部的失效引用，例如 `#REF!$A$2:$A$4`。工作表删除、引用、计算及资源共用一次精确历史；打开已保存的失效图表不改源。

`XlsxChart.bindingReason` 在来源失效或未计算时返回原因，正常时为空串。默认图表属性面板显示缓存提示，保留标题、类型和引用编辑入口。修改已有失效图表的外观时保留其缓存；重新绑定后恢复实时更新并清除提示。新建图表不能使用缺少缓存的失效来源。缓存只是最后有效值，不表示已删除来源仍在更新。原生输入、撤销、重开和 Canvas/PDF 共用这一状态。实现复用 [`chart-rename.mbt`](../../../modules/formats/src/xlsx/chart-rename.mbt)、[`chart-bindings.mbt`](../../../modules/formats/src/xlsx/chart-bindings.mbt)及 [`sheet-delete.mbt`](../../../modules/formats/src/xlsx/sheet-delete.mbt)。依据 [ONLYOFFICE 删除表时处理图表来源](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L5498-L5541)、[失效引用写回](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L12116-L12128)和[无法解析来源时的缓存保留](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L12551-L12568)。

整行、整列插删已同步本表及跨表的分类、系列标题和数值引用。来源内部插入扩大范围，删除缩小范围；完整删除来源后写为 `#REF!` 并保留最后有效缓存与提示。绝对地址也随结构变化，已失效引用保持。固定、随单元格移动和随区域缩放三种锚点复用已有图片规则；引用、原生缓存、公式计算和几何共用一次精确历史。几何预检与提交重排读取插删后的候选数据，散点图不会误读旧位置。

纯引用平移只补丁修改原生引用文字，保留其他注释及处理指令。引用内部有注释，或数据变化需要改写带注释的缓存时，整项操作保持保护。来源扩大超过 256 格、对象越界或其他预算失败也原子拒绝。默认行列按钮先提交原生输入草稿，再提交结构历史；重开后输入及 Canvas/PDF 沿同一数据。实现归 [`chart-axis.mbt`](../../../modules/formats/src/xlsx/chart-axis.mbt)、[`picture-axis.mbt`](../../../modules/formats/src/xlsx/picture-axis.mbt)及 [`transaction.mbt`](../../../modules/formats/src/xlsx/transaction.mbt)。依据 [ONLYOFFICE 行列操作维护图表来源](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L5583-L5634)和[引用移动及范围调整](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L12107-L12115)。复用已有结构引用算法，未复制上游执行代码。

普通图表按原生 `plotVisOnly=1` 排除来源表的隐藏行列。类别和各系列分别按各自来源压紧可见点；没有可见来源的系列不绘制，也不进入图例。保留原始系列及扇区配色，隐藏第一系列不会使第二系列变蓝。手动隐藏、筛选和分组共同沿有效尺寸计算；目标表相同坐标的隐藏状态不影响跨表来源。全部来源隐藏时保留标题和图框，恢复显示后继续绘制。

有效来源的原生引用、完整当前值缓存及 `charts().data` 保留全部来源值，可见性只派生到 Canvas/PDF。单独隐藏不改图表 XML；隐藏格的公式仍重算并更新完整缓存。保存重开保留来源尺寸和可见结果，查看与输出保持只读。已有失效引用继续采用缓存。

删除来源表或整行整列删除使分类、数值引用失效时，将对应引用最后可见的点冻结到原生缓存。分类和各数值引用独立保存长度，支持 `ptCount=0`，全部隐藏的系列不重新出现。饼图和圆环图将保留的类别颜色写入标准 `dPt`，其他系列保留原生 RGB 配色。引用、缓存、资源清理及源补丁共用一项精确历史，状态写回标准图表部件。

尚有效的来源继续计算，长度可以与其他有效来源或冻结缓存不同。核心按可见点顺序派生共同绘制矩阵，普通分类缺少的标签用序号，显式散点 X 缺项及缺少的数值留空；TSV 查询使用相同补齐规则，原生缓存保留独立长度。已有失效图表仍可修改外观、保存重开及继续输入；重新绑定后恢复当前来源及可见性。默认删除、外观面板、精确混合历史、实际 Canvas 和独立 PDF 已检查。需要改写缓存时，带源注释或处理指令的图表仍原子拒绝。实现归 [`chart-cache.mbt`](../../../modules/formats/src/xlsx/chart-cache.mbt)、[`worksheet.mbt`](../../../modules/formats/src/internal/chart/worksheet.mbt)及 [`worksheet-palette.mbt`](../../../modules/formats/src/internal/chart/worksheet-palette.mbt)。缓存规则参考 [ONLYOFFICE 失效来源保留及零点缓存](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L12551-L12568)与[按可见来源保存点数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L12586-L12685)。共用绘制模型的普通矩阵校验保持等长、非空；独立来源缓存另受相同字符、系列、点数和数值预算约束。

可见性与配色实现归 [`xlsx/chart-visibility.mbt`](../../../modules/formats/src/xlsx/chart-visibility.mbt)、[`layout/chart-visibility.mbt`](../../../modules/layout/src/chart-visibility.mbt)及共用图表绘制。依据 [ONLYOFFICE 数值来源可见性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L12551-L12612)和[类别来源可见性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L14111-L14208)。本项目保留完整缓存并单独派生可见数据，未复制上游执行代码。

每个数据区域最多 256 格，每图 1–32 个系列，每表绘图合计最多 256 项；框至少 180×150 pt，每轴不超过 14400 pt，位置沿工作表边界校验。引用最多 1024 个字符；文字、字体、计算工作和历史沿共用预算。当前只编辑共用模型能完整识别的普通图表。`plotVisOnly=0`、其他缓存结构、共享图表部件、复杂样式、旋转/翻转和未知原生变体保持保护。带源注释或处理指令的图表不进行整图及缓存改写，带这些内容的姿态或锚点不重写；源仍保留。普通图片及图表已有局部单元格插删，跨工作簿图表复制沿[绘图剪贴板合同](#工作表绘图剪贴板复制)保存独立数据；跨工作簿剪切继续实施。

实现归 [`chart-bindings.mbt`](../../../modules/formats/src/xlsx/chart-bindings.mbt)、[`chart-edit.mbt`](../../../modules/formats/src/xlsx/chart-edit.mbt)、[`chart-range.mbt`](../../../modules/formats/src/xlsx/chart-range.mbt)、[`worksheet.mbt`](../../../modules/formats/src/internal/chart/worksheet.mbt)及 [`xlsx-charts.ts`](../../../packages/xlsx/src/core/xlsx-charts.ts)。引用和缓存检查参考 [ONLYOFFICE 系列来源](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L2390-L2435)及[工作表与缓存比较](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L2495-L2540)。未复制上游执行代码。

### 单元格迷你图

`editSheet(revision, sheet, { action: "sparkline", cell, source, kind })` 在未合并的目标格创建或修改迷你图。`kind` 为 `line`、`column` 或 `winLoss`；`source` 为同一工作簿中一行或一列的区域，缺省使用本表，也可加工作表名称，例如 `'Source data'!A1:D1`。名称匹配忽略大小写，名称中的单引号写成两个单引号。`source: null` 删除该目标格的迷你图。每表最多 256 个目标，每个数据源最多 256 格。查询 `sparklines` 返回 `items: { cell, source, kind }[]` 及 `readOnlyReason`；本表源返回规范化区域，跨表源返回带引号的表名及区域。原有目标格内容保留，文字按原有规则显示。

核心单独保存来源表归属，从该表当前计算结果及行列可见性取数。来源改值或公式结果变化后，目标 Canvas/PDF 读取新数据；来源格隐藏时排除该格，目标表同坐标的值和尺寸不参与取数。目标表与来源表的整轴和局部单元格插删分别更新目标位置与实际源范围，沿现有范围、端点和 256 格上限。来源表缺失的新命令拒绝；导入的缺失来源保留原始定义，并在查询和诊断中说明原因，静态输出拒绝遗漏内容。外部工作簿及三维来源仍保护。数据绑定参考 [ONLYOFFICE sparkline.setF](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L8430-L8442)，绘制仍归共同迷你图图元。

清除内容和清除格式保留迷你图的原生定义及便笺。全部清除移除目标格在选区内的迷你图，包括空白目标；同次提交清除值、样式、规则及所属便笺。移除最后一个目标后删除本功能的空扩展。仅清除数据源时，选区外迷你图继续绑定原地址，图形随空值留空；重新输入数据后恢复 Canvas/PDF，无需重新绑定。已有 `#REF!` 保持失效。相关操作沿同一历史和输出预算，未知迷你图配置及未知扩展继续保护。默认三种清除按钮沿既有接口接入。行为参考 [ONLYOFFICE 清除选项](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L16669-L16704)，实现复用 [`clear.mbt`](../../../modules/formats/src/xlsx/clear.mbt)及 [`clear-rules.mbt`](../../../modules/formats/src/xlsx/clear-rules.mbt)。

四向填充及向外序列按源矩形循环复制迷你图的类型和位置。数据源按每个副本的行列位移平移，已有绝对地址也沿迷你图规则移动；每个端点裁到工作表边界，`#REF!` 保持失效。尾块只复制落入目标的格。目标原有迷你图先移除，因此源模式中的空白图形位置也会清除对应目标；范围外迷你图和各格便笺保留。只有图形变化时同样生成一项历史，重复填充有效状态不新增历史。向内缩减保留图形、绑定、格式和便笺，仅清除内容。新目标仍须未合并；合并源覆盖旧目标图形时先移除旧图形，保留新合并。每表 256 个目标及已有包/历史预算继续生效，失败不提交。默认四向按钮、原生改值、保存重开和 Canvas/PDF 沿同一核心结果。复制依据 [ONLYOFFICE 目标替换与平铺](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22677-L22691)、[迷你图数据源位移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L8070-L8091)及[端点边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L930-L972)。实现归 [`sparkline-fill.mbt`](../../../modules/formats/src/xlsx/sparkline-fill.mbt)，复用现有填充事务。

整行、整列插入或删除时，核心用现有范围算法同步目标格和数据源。区域内部插入扩大源，删除缩小源；删除整个源后保留目标，原生公式与查询 `source` 为 `#REF!`，图形留空。用户重新填写区域可恢复显示；重新提交 `#REF!` 可保留失效绑定。目标格被删除时移除对应迷你图，最后一个目标删除后移除本功能的空扩展。源、单元格、公式缓存和选择共用一项精确历史。插入会丢失目标、丢失源端点或使数据源超过 256 格时，整项拒绝。结构位移与目标删除依据 [ONLYOFFICE updateSparklineGroupOffset](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L10369-L10418)。

局部 `insertCells` 的 down/right 与 `deleteCells` 的 up/left 沿同一事务更新迷你图。目标格在移动带内时移动或删除，源完整落在移动带内时按区域规则移动、扩缩或变为 `#REF!`。跨带源复用普通公式的引用规则：例如源为 `A1:D1` 时，在 `B1` 向下插入仍引用 `A1:D1`；删除 `A1:B1` 并向上移动后引用 `C1:D1`。插入只对完整落入移动带的源检查端点越界，不相交的源保持原样。目标格的便笺沿既有位移规则同步。依据 [ONLYOFFICE Range.isIntersectForShift](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L614-L637)；普通合并、筛选、原生表及未知资源的保护继续生效。

工作表 `rename` 更新所有已识别迷你图数据公式中的表名，保留绝对地址、命名空间前缀和失效绑定。`copy` 把表内迷你图复制到新表，本表数据引用改到副本，跨表数据引用保留原来源表；原表数据与图形保持独立。隐表副本沿用隐藏状态与原有活动选择。`delete` 通过既有事务删除表内迷你图及独占资源；其他表引用该来源的迷你图变为可重新绑定的 `#REF!`，其他来源保持可编辑。既有便笺复制、公式/名称和依赖更新规则继续生效。改名及其撤销/重做按工作簿中的实际表名刷新迷你图模型。复制与数据归属参考 [ONLYOFFICE 工作表复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7439-L7444)及 [sparkline.updateWorksheet](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L8434-L8442)。

MoonBit 写入原生 x14 `sparklineGroups` 扩展、xm 数据公式与目标引用。每个目标单独保存类型，修改与删除只替换本功能拥有的扩展。其他部件和未知扩展保留。没有变化时不新增历史；源、选择及已有文档预算沿用同一事务。保存重开后仍可修改。类型与原生结构参考 [ONLYOFFICE sparklineGroup](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L7804-L7842)，数据绑定与共用图表绘制参考 [CSparklineView](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/DrawingObjects.js#L682-L755)。未复制上游实现源码。

Canvas 和静态 PDF 复用单元格绘制。核心从当前计算结果取数，直接改值与公式结果变化会更新图形。源格隐藏时从序列中排除，空白、文字、布尔与错误值留空。折线在空值处断开，孤立点保留小标记；柱形与盈亏用蓝色表示正值、橙色表示负值，零值不画柱。盈亏只显示正负方向。线宽固定 0.75pt，图形在格内留 2pt 边距。自动行高只测量文字，迷你图跟随目标格尺寸。默认可访问网格通过描述暴露类型和源区域。

普通行列排序和原生表行排序保留迷你图目标地址、类型、数据源公式与原生扩展字节。即使目标格在排序范围内，图形仍读取原地址中的当前值；例如目标 `F2` 的源为 `B2:C2` 时，行排序后继续显示新 `B2:C2` 的值。标题、手动隐藏及筛选后的可见位置沿现有排序规则处理，便笺随所属单元格移动。原生表排序仍扩至完整数据行，保留筛选来源、计算模板及例外。再次改值继续更新图形，撤销/重做与保存重开保留同一绑定。未知配置、资源和预算失败保持原子拒绝。此行为沿 [ONLYOFFICE 单元格排序](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21651-L21777)及[排序后的便笺和绘制更新](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L20693-L20700)。实现只为 [`sort-source.mbt`](../../../modules/formats/src/xlsx/sort-source.mbt)、[`sort.mbt`](../../../modules/formats/src/xlsx/sort.mbt)及原生表排序入口放行已验证扩展，复用既有排序与重绘。

普通区域和原生表去重移除原始重复行中、且目标格在有效选区内的迷你图；最后一个目标移除后删除本功能的空扩展。幸存图形保留原坐标与数据源，读取压紧后的当前格值；尾部格清空后，仍在该处的图形继续保留并显示空数据。范围外目标和 `#REF!` 绑定沿同一归属规则处理。便笺、链接及单元格按既有去重规则移动或删除；原生表继续缩小范围、迁移总计并保留模板、例外与筛选来源。预览保持只读，数据、图形和资源清理共用一项精确历史及输出预算，重复提交无变化时不新增历史。默认预览和删除入口沿核心资源校验；再次输入、撤销/重做、重开及 Canvas/PDF 共用当前模型。依据 [ONLYOFFICE 删除原始重复行资源后压紧](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L26112-L26136)。实现复用 [`duplicates.mbt`](../../../modules/formats/src/xlsx/duplicates.mbt)、[`reorder-cells.mbt`](../../../modules/formats/src/xlsx/reorder-cells.mbt)及既有迷你图删除。

区域复制通过结构化单元格剪贴板传递三种迷你图及失效绑定。`CopiedCells.sparklines` 为最多 256 项 `CopiedSparkline[]`，每项含源绝对目标格 `cell: { row, column }`、数据坐标 `source: CellRange | null` 和 `kind`；`null` 表示 `#REF!`。仅捕获选区内目标，快照不随之后的源图形编辑变化。源格须在矩形内、不重复且未合并；数据坐标须为有效的一行/列且至多 256 格。

仅 `all` 替换目标覆盖区的迷你图，源空白位置清除原目标，范围外图形保持。复制到同表、其他表或其他工作簿时，数据坐标随粘贴起点位移，并绑定目标表；原外表来源也按此规则转为目标本表来源。绝对标记不阻止迷你图位移，越界端点截定到表边界。转置交换目标格位置，数据区域保留原方向并应用同一粘贴位移。`values/formulas/format` 保留目标图形；若格式粘贴会合并目标图形格，整项拒绝。目标容量、未知配置及包输出失败保留源、选择和历史。图形、单元格、规则、链接及便笺使用同一事务，后续输入、精确撤销/重做、重开及 Canvas/PDF 读取当前目标数据。实现归 [`clipboard-sparklines.mbt`](../../../modules/formats/src/xlsx/clipboard-sparklines.mbt)；数据归属与位移依据 [ONLYOFFICE 迷你图粘贴入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L28529-L28539)及 [moveSparklineGroup](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L10420-L10558)。

区域剪切复用同一工作簿内的 `moveCells` 事务。目标格随所选图形移动，目标覆盖区的旧图形移除；重叠区域先按源身份映射，空白源位置也清除旧目标。仅移动图形时，数据坐标和来源表保持：例如把 Sheet1 中读取 `A1:D1` 的图形搬到 Sheet2，仍读取 `'Sheet1'!A1:D1`。移动完整数据区域时，全工作簿中引用该区域的迷你图同步新坐标和来源表，保留其他表的目标位置；图形和数据一起移动时，共同归到新表。绝对地址不阻止内容移动，`#REF!` 绑定继续保留。

同表沿一行/列的数据轴移动部分端点时，范围按新端点扩缩；端点越过另一端时规范为升序范围。移动中间格、跨轴搬动端点及跨表移动部分来源时，原数据区域保持，继续读取原位置中的剩余值。单区域模型不生成多区域或跨表联合来源。变换后的来源和目标各受 256 格/项上限约束，受影响图形在受保护表中时整项拒绝。图形、便笺、超链接、原生部件和计算缓存共用一项精确历史与原有输出预算，创建资源后继续添加关系的组合也可完整撤销。默认剪切/原生粘贴、后续输入、重开及 Canvas/PDF 沿同一模型；跨工作簿、转置和选择性剪切继续按剪切合同拒绝。实现归 [`move-sparklines.mbt`](../../../modules/formats/src/xlsx/move-sparklines.mbt)，范围移动与端点规则依据 [ONLYOFFICE moveSparklineGroup](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L10420-L10558)。

当前支持固定颜色、独立数轴、同一工作簿内的本表或跨表单区域及普通未合并目标。日期轴、组合轴、自定义颜色/标记、外部/三维来源和其他原生配置继续实施；未知配置保留并给出只读原因，静态 PDF 拒绝遗漏内容。其他表编辑沿各操作的资源保护。普通绘图锚点及图表当前范围归[工作表图表](#工作表图表)。实现归 [`sparkline.mbt`](../../../modules/formats/src/xlsx/sparkline.mbt)、[`sparkline-edit.mbt`](../../../modules/formats/src/xlsx/sparkline-edit.mbt)、[`sparkline-axis.mbt`](../../../modules/formats/src/xlsx/sparkline-axis.mbt)及 [`sparkline-paint.mbt`](../../../modules/formats/src/xlsx/sparkline-paint.mbt)。工作表操作复用 [`sheet-rename.mbt`](../../../modules/formats/src/xlsx/sheet-rename.mbt)、[`sheet-copy.mbt`](../../../modules/formats/src/xlsx/sheet-copy.mbt)和 [`sheet-order.mbt`](../../../modules/formats/src/xlsx/sheet-order.mbt)。
