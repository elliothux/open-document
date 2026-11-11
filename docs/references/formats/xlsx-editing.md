# XLSX 工作表与单元格编辑

[格式合同目录](../formats.md)

## P5 XLSX 合同

`XlsxSession.inputLimits()`、`XlsxClient.inputLimits()` 与 `SpreadsheetEditor.inputLimits` 提供核心字节限额，字段与累计预算的区别归[共享合同](shared.md#输入字节限额)。

共享公式按相对/绝对引用展开，保留源运算符、括号、字符串及工作表名；改单元格或删行后沿既有依赖、缓存和精确历史事务重算。已识别且不含单元格引用的工作簿路径、修订标识与计算能力标志，以及行 `dyDescent`，随结构操作保留；未知扩展仍受保护。已支持的颜色 tint 可用于布局和自动尺寸。

`XlsxSession.execute({ operation: "createXlsx", budget })` 与 `XlsxClient.execute({ operation: "createXlsx", budget })` 创建一张可见的空白 `Sheet1`，选区为 A1，revision 与历史为 0。基础样式为 11 pt Calibri、General 数字格式、黑字、无填充/边框；工作簿使用自动计算。核心创建 workbook、worksheet、styles、关系与内容类型，之后沿相同读取、计算、编辑、历史及保存路径运行。默认 UI 与 `mountEditor`、实例 `create/open` 接通该入口；首次保存规则见上文。工作表和单元格身份由核心生成，不从文件名推导。

`XlsxSession.execute(command)` 和 `XlsxClient.execute(command)` 分别提供同步 WASM 与 Worker Promise API。`XlsxCommand` 从命令处理函数推导，`XlsxResult<C>` 按 operation 推导结果；完整字段与可选项归 [`xlsx-command.ts`](../../../packages/xlsx/src/core/xlsx-command.ts)。两者保留 `defaultBudget/addFont` 入口；同步会话用 `close()` 关闭，Client 用 `dispose()` 释放 Worker。核心持有 OPC/XML、稀疏单元格、公式依赖、选区、历史及几何；TS 只处理平台输入与呈现。工作表 `id` 来自包内关系目标。查询包含隐藏表，界面只列出可见表。

`SpreadsheetEditor` 使用函数模块组合领域操作，共享原生草稿、操作队列和编辑屏障。`objects` 提供工作表选择/结构、批注、绘图、图表和透视控件；`clipboard` 提供文字、单元格和绘图剪贴板；`data` 提供重算、汇总、重复项、分列与合并计算；`search` 提供查找替换。下文省略前缀的宿主操作按这些分组调用，例如 `objects.editSheet(...)`、`clipboard.pasteCells(...)` 和 `data.duplicates(...)`。通用宿主仍直接使用 `copy()`；保存、输出、历史、格式和原生草稿入口保持在 Editor 上。

| API | 结果与约束 |
| --- | --- |
| `execute({ operation: "openXlsx", bytes, budget })` | 打开 Transitional XLSX 或只读 Strict XLSX；签名、加密和其他扩展格式拒绝 |
| `execute({ operation: "queryXlsx", sheet, range })` | 默认当前选区；返回实际存在的稀疏单元格，单格查询包含空格；A1 地址，查询矩形端点有序 |
| `execute({ operation: "selectXlsx", revision, sheet, range })` | 更新可见表的核心选区；隐藏表须先显示；单格合并区域定位锚点 |
| `execute({ operation: "editXlsxSheet", revision, sheet, change })` | 工作表新增、复制、删除、重排、改名、可见性、行高/列宽及矩形合并/取消合并事务；返回 `XlsxQuery` |
| `execute({ operation: "autoFitXlsx", revision, sheet, first, last, axis, profile })` | 按当前显示值和字体测量自动适配行高或列宽；返回 `XlsxQuery` |
| `execute({ operation: "replaceXlsx", revision, sheet, range, values, literal: false })` | 一项矩形事务；字段为输入字符串，核心识别值与公式；清空保留样式 |
| `execute({ operation: "findXlsx", revision, sheet, text, options: {} })` | 返回有界单元格结果；支持当前表/工作簿、大小写、整格、公式源/计算值，不改选区 |
| `execute({ operation: "replaceXlsxMatches", revision, sheet, text, options, replacement, index })` | 重新计算同一查询；有 index 时替换该格全部匹配，否则替换全部结果；一次原子历史 |
| `execute({ operation: "navigateXlsx", revision, direction, extend: false })` | `left/right/up/down/home`；跳过隐藏行列，Shift 扩展选区 |
| `execute({ operation: "copyXlsx", revision })` / `execute({ operation: "pasteXlsx", revision, text })` / `execute({ operation: "clearXlsx", revision })` | 核心显示值 TSV、矩形粘贴及清空；核心识别数值/布尔，`=` 不执行 |
| `execute({ operation: "undoXlsx", revision })` / `execute({ operation: "redoXlsx", revision })` | 源片段、选区和计算结果原子恢复；revision 每次成功修改递增 |
| `execute({ operation: "saveXlsx" })` | 返回完整 XLSX；无编辑及全部撤销后保留原解压部件字节 |
| `execute({ operation: "viewportXlsx", ...options })` | 逻辑滚动、point 尺寸、sheet、字体 profile、可选 `reveal`；一个绘制区域及可见网格语义 |
| `execute({ operation: "hitXlsx", layoutId, x, y })` / `execute({ operation: "selectionXlsx", layoutId })` | 核心地址命中与选区矩形；旧布局身份或 revision 拒绝 |
| `execute({ operation: "printXlsx", revision, sheet, options, profile })` | 独立打印区域，返回有身份的页面绘制批次 |
| `execute({ operation: "exportXlsxPdf", layoutId, outputBytes })` | 使用当前打印布局；编辑、字体变更或新打印布局使旧输出身份失效 |

`XlsxQuery` 返回 `sheets`、`sheet`、`selection`、`revision`、历史状态、`date1904`、`fontKeys` 和诊断。每格分别返回 `value`、`formula`、`cached`、`calculated`、`calculation`、`calculationReason`、`display`、`input` 与 `readOnlyReason`。空格、空字符串、零、布尔值与错误独立表示。`input` 是核心生成的可编辑源码，文字带前导单引号，避免重新提交时误作公式或数值。

工作簿可包含原生 `chartsheet`。核心核对关系、内容类型与 XML 根类型，保留表顺序、身份和原始部件。`sheets[].kind` 区分 `worksheet` 与 `chartsheet`。图表页复用已有绘图与图表读取，不创建单元格、网格线或行列标题；查询及可访问网格的单元格数组为空，命中单元格拒绝，选区几何为空。单元格写入、格式、行列尺寸及冻结窗格均拒绝。Web 禁用公式输入，图表对象仍沿已有绘图入口处理。已支持图表可绑定其他工作表的实时数据，并沿同一事务维护缓存、精确历史及保存重开；未知图表结构仍报告显示缺口。C0 原件的主图已显示导入缓存，范围与未通过项归[工作表图表](xlsx-objects.md#工作表图表)。图表页的新建和完整结构编辑继续受现有能力限制。

图表页可沿现有打印预览及 PDF 接口输出一页，使用源纸张、方向、边距及页眉页脚。核心按原生隐式网格和字体标题尺寸计算缩放，保留图框完整描边。已计算图表正常输出；含未计算来源时，只允许未编辑且明确声明手工计算的导入缓存快照。输出不重算公式、不改写源。自动计算模式、编辑后的未计算快照、未绘制内容、单元格打印区域及源自定义缩放继续拒绝。页数、图元、文字及工作簿数据预算沿既有打印限制。实现归 [`chart-sheet-print.mbt`](../../../modules/formats/src/xlsx/chart-sheet-print.mbt)。

Strict XLSX 复用基础工作表、共享字符串、普通样式、主题颜色及已有公式读取。工作簿、工作表、样式和共享字符串命名空间须与关系匹配。可切换工作表、选择单元格和逐字节保存原件。Strict 专用日期、边框和绘图的视觉尚未验收。

### 工作表保护

`editSheet({ action: "protection", enabled, password? })` 启用或解除当前工作表保护。同步 Wasm、Worker 和编辑宿主复用同一入口；宿主先提交已接受的原生草稿。`password` 省略或为空串时创建无密码保护，否则使用原字符串，不裁剪或归一化。密码最多 255 个 UTF-16 单元，须为有效 XML 文字。已保护表须先解除，才能更改密码；解除未保护表不增加历史。

新密码使用标准 `SHA-512`、16 字节安全随机盐及 100000 次迭代。平台通过 Web Crypto 提供盐，MoonBit 计算散列，写入 `algorithmName/hashValue/saltValue/spinCount`，不把明文密码写入源、历史或查询。解除支持 SHA-512 与旧式 `password` 摘要；旧式摘要只用于导入验证，不用于新建密码。SHA-512 输入盐限 1–64 字节，摘要为 64 字节，迭代接受 0–1000000；编码属性先检查长度。未知算法、混合或残缺凭据、超限与未知保护元数据明确拒绝。

`XlsxQuery.protection` 返回 `{ protected, passwordRequired, reason }`，Wasm/Web 导出 `XlsxProtection`。`reason` 说明当前保护改写限制，不包含密码或散列。默认 UI 显示状态，提供密码输入和新密码确认；操作结束后清空输入。工作表保护限制编辑，不加密文件内容。新保护使用标准默认操作权限，保留选择锁定和未锁定格；细分操作授权及选择限制创作仍待实现。

保护节点按工作表标准顺序插入或移除，沿既有有界源事务与精确历史。错误密码、无效输入、旧 revision 和输出失败保留文档、选择及历史；锁定格、未锁定格、隐藏公式与重算规则见下文。节点内注释、处理指令或未知文字阻止保护改写，保留原内容。默认无密码保护、错误密码恢复、保存重开、混合历史与 PDF 已检查。[工作簿结构保护](#工作簿结构保护)见下节，授权区域及其他密码算法继续实施。

实现归 [`protection-edit.mbt`](../../../modules/formats/src/xlsx/protection-edit.mbt)和 [`protection-password.mbt`](../../../modules/formats/src/xlsx/protection-password.mbt)。复用固定版本 `moonbitlang/x` 的 SHA-512，无新增依赖。标准凭据及旧式摘要参考 [ONLYOFFICE 保护入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookProtection.js#L521-L531)、[默认盐与迭代](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/editorscommon.js#L14917-L14919)、[写保护散列](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OfficeCryptReader/source/CryptTransform.cpp#L905-L928)及[旧式密码摘要](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookProtection.js#L132-L147)。未复制上游执行代码。

### 工作簿结构保护

`editSheet({ action: "workbookProtection", enabled, password? })` 启用或解除整本工作簿的结构保护。入口沿现有 `editSheet` 传递表身份；操作作用于工作簿，保留活动表、选区、表身份及原有资源。保护期间，新增、复制、删除、移动、改名、隐藏和显示工作表由核心拒绝，默认管理控件按 `sheetEditReason/sheetRenameReason` 禁用。单元格内容、格式、行列和工作表保护继续遵守各自规则，不把结构保护当作整本只读。

`XlsxQuery.workbookProtection` 使用同一 `XlsxProtection` 类型，返回 `{ protected, passwordRequired, reason }`。`protected` 表示 `lockStructure`，与 `sheets[].protected` 的工作表保护分开；`reason` 是保护设置改写限制。默认 UI 提供独立状态、密码和确认表单，操作后清空输入。错误密码及预算失败不提交修改；解除未保护的工作簿不新增历史。关闭状态的标准保护节点可重新启用。

新密码复用上述长度、随机盐、SHA-512 与迭代预算，保存为原生 `workbookAlgorithmName/workbookHashValue/workbookSaltValue/workbookSpinCount`。旧式 `workbookPassword` 摘要可用于解除导入保护；无密码保护可直接解除。保护节点按工作簿标准顺序插入或移除，单次保护改写只修改 workbook 部件；内容编辑、保护与结构操作可精确混合撤销，保存重开后权限仍有效。

未知保护属性、节点文字/注释/处理指令、活动窗口/修订保护及修订凭据继续保护原源；当前只改工作簿结构保护。其他密码算法与细分工作表授权仍待实现。核心、默认 UI、独立散列/原生 XML、失败保持、保存重开及 PDF 已检查。保护限制编辑，不加密文件内容。

实现归 [`workbook-protection.mbt`](../../../modules/formats/src/xlsx/workbook-protection.mbt)，密码算法复用 [`protection-password.mbt`](../../../modules/formats/src/xlsx/protection-password.mbt)。字段和行为参考 [ONLYOFFICE 工作簿保护模型](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookProtection.js#L588-L610)、[凭据字段](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookProtection.js#L687-L696)及[结构保护入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookProtection.js#L826-L839)。未复制上游执行代码。

### 受保护工作表的单元格输入

导入的 `sheetProtection sheet="1"` 工作表按有效 `locked` 格式判断输入权限。默认格锁定；显式单元格样式优先于行样式和列样式，基础 `cellStyleXfs` 及 `applyProtection` 沿既有样式继承解析。条件格式只改变显示，不授予编辑权限。查询和视口的每格 `readOnlyReason` 使用同一判断，默认原生输入随活动格更新。

`formatCells({ locked?, formulaHidden? })` 设置普通矩形单元格的锁定和公式隐藏格式。两项均为布尔值，省略时保留有效值；修改其中一项时保留另一项的基础样式继承结果，不激活原本被 `applyProtection="0"` 忽略的局部值。核心派生 `cellXfs`，写入标准 `protection` 和 `applyProtection="1"`；保留值、公式、其他样式及无关部件。`formatting.locked/formulaHidden` 返回共同布尔值或混合态 null；默认格式面板提供保留/开/关及生效提示。设置仅在工作表启用保护时生效，当前受保护表仍拒绝格式修改。未知保护元数据和输出预算失败保留原源。

格式刷和结构化复制/粘贴的完整格式携带这两项属性，沿既有矩形、合并及精确历史规则转移。完整复制格式必须包含两项；普通格式补丁仍可省略。条件格式和自定义表样式不接受保护属性，不把显示规则当作权限。行为参考 [ONLYOFFICE 单元格保护入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/api.js#L6506-L6514)及[范围格式写入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L19768-L19809)，实现复用 [`style-derive.mbt`](../../../modules/formats/src/xlsx/style-derive.mbt)和既有格式事务。

未锁定格可输入、清除内容、粘贴 TSV、选择验证列表和替换查找结果。混合范围含锁定格时整项拒绝，不提交部分内容或历史；数据验证、富文本和未知单元格结构继续沿原保护。输入引起的锁定公式缓存重算仍允许，公式源及原有保护设置保持。每项成功编辑共用既有精确历史、保存、重开与 PDF 路径。隐藏公式不出现在输入源码或公式查找结果中，无论该格是否锁定。

工作簿只读原因优先；未知工作表保护属性、子节点、根扩展、授权区域 `protectedRanges` 或选择限制继续阻止受保护表的输入。内容输入保留原密码凭据；启用、解除和凭据校验归[工作表保护](#工作表保护)。格式、结构及其他尚未接通的授权操作仍受工作表保护限制。内容输入复用 `replace`、`paste`、`clear`、`replaceMatches` 和验证选择入口。

权限判断归 [`sheet-protection.mbt`](../../../modules/formats/src/xlsx/sheet-protection.mbt)，所有内容事务在 [`cell-transaction.mbt`](../../../modules/formats/src/xlsx/cell-transaction.mbt)复查原始目标。行为参考 [ONLYOFFICE 受保护范围编辑](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L27030-L27104)和[范围锁定判断](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L13956-L14052)。未复制上游执行代码。

### 选区统计

`XlsxQuery.statistics` 返回 `{ range, count, countNumbers, sum, average, min, max, reason }`，Wasm/Web 导出 `XlsxStatistics`。`range` 是此次查询的矩形；默认 UI 状态栏使用当前选区。查询及选区变化不改 revision、文档源、历史或保存状态。输入草稿期间显示已提交值；提交后使用当前公式结果，随历史、筛选及行隐藏更新。

`count` 计算非空值，包含文本、布尔值和错误；空白及空串不计。其余五项只计算数值，包括数值公式结果和日期序列值；数字文本与布尔值不转成数值。隐藏行（含筛选隐藏和零高度）不参与，隐藏列仍参与。行为依据 [ONLYOFFICE 的选区统计](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L13248)。当前只处理已有矩形选区，不包含非连续区域。

没有数值时，`sum/average/min/max` 为 null。当前输出原始数值，不应用活动单元格的数字格式；日期、百分比和货币的状态栏格式仍待扩展。核心使用缩放及补偿求和；总和超出有限数值范围时，`sum` 为 null 并在 `reason` 说明，仍返回有效计数、平均与极值。选区含未计算公式时，计数按已知值/缓存类型返回，四项汇总均为 null，`reason` 说明原因。源文件只读原因也进入 `reason`，不把导入缓存标为新计算结果。沿用查询最多 4096 个已有单元格的限制；统计复用此次查询的稀疏列表，不遍历大矩形中的空格。

### 单元格查找替换

`XlsxFindOptions` 包含 `matchCase`、`wholeCell`、`formulas`、`workbook`，默认依次为 false、false、true、false。查找使用非空字面文本，不解释正则或通配符；不区分大小写时使用固定 Unicode 简单大写映射。匹配保留完整 Unicode 字符，位置与长度按 UTF-16 计。公式模式搜索带 `=` 的源码，其余格搜索逻辑值；值模式搜索未应用数字格式的计算值或导入缓存。普通文本不包含编辑输入使用的转义单引号。

`XlsxSearchResult` 返回 `revision`、`truncated` 和 `matches`。每个匹配格只有一项，包含稳定部件路径 `sheet`、表名 `name`、`address`、`hidden`、`snippet` 和替换保护原因 `reason`，按工作表顺序、行、列排列。工作簿范围包含隐藏表；选择隐藏结果前须先显示该表。保护内容和公式计算结果仍可查找；值模式的公式结果不能替换，须切换公式模式修改源码。

`SpreadsheetEditor.search.find(text,options)` 先提交已接受的原生草稿，返回增加 `documentId`、查询表、文本与选项的 `SpreadsheetSearchResult`。`search.selectMatch(result,index)` 定位可见结果；`search.replaceMatches(result,replacement,index?)` 使用同一队列。组合输入未完成时拒绝；文档身份或 revision 变化后须重新查找。默认 UI 提供这三项操作和四个选项。

核心重新查找，不信任调用方给出的结果格。替换当前结果会替换该格全部不重叠匹配；替换全部跨表提交一次历史，保留当前选区，包含隐藏表。已有文本格保持文本类型，替换产生的 `=` 不执行；只有公式模式命中的真实公式会重新解析源码。数值/布尔格沿已有输入转换。任何匹配格受保护、公式无效或预算失败时，整项替换不提交；无变化不增加历史。

查询和替换文本各限 32767 UTF-16 单位；最多返回 4096 格，并在发现后续匹配时设置 `truncated`。截断结果不能全部替换。扫描文本总量限 8 Mi UTF-16 单位；每格输出限 32767、一次替换输入总量限 1 Mi UTF-16 单位，继续受工作簿、计算、历史和输出预算约束。结果片段最多 80 个完整 Unicode 字符。名称定位、格式化显示值搜索及正则/通配符不在当前范围。

### 工作表顺序、名称与可见性

`XlsxSheetEdit` 从 `wasm/xlsx` 和 `web/xlsx` 导出。`{ action: "move", index }` 将指定表移动到从 0 开始的目标索引，索引覆盖可见和隐藏表；`{ action: "visibility", state: "visible" | "hidden" | "veryHidden" }` 修改可见性。同步 Wasm、Worker 使用 `editSheet(revision, sheet, change)`；编辑宿主为 `SpreadsheetEditor.objects.editSheet(change, sheet?)`，省略身份时操作队列执行时的活动表，先沿现有屏障提交单格草稿。无效状态、越界索引、旧 revision、隐藏最后可见表和预算超限不修改文档或历史。同位置/同状态不新增历史。

`{ action: "add" }` 在指定表后新增可见空白表，并激活 A1。核心分配唯一的 `SheetN` 名称、sheetId、部件路径和关系 ID，保留已有或未引用的同名源部件；会话内撤销后重新新增也不复用该身份。新表沿用工作簿基础样式。工作表 XML、关系、内容类型、局部名称索引、视图和选区合为一次有界历史；后续编辑与新增可混合精确撤销/重做。最多 256 张表，结构保护或预算失败不留下新增部件。默认 UI 提供同一新增入口。新增空表保留既有公式缓存、共享字符串计数和 calcChain。

工作表身份是 OPC 部件路径，移动保留 sheetId、关系、名称及公式源。历史中的 XML 编辑也按部件路径定位。核心同步名称的 `localSheetId`、窗口的 `activeTab/firstSheet` 与工作表 `tabSelected`，按新顺序重建计算索引。隐藏活动表时先向右查找可见表，再向左查找；显示表会将其激活并定位 A1。打开时沿首个 workbook view 恢复活动表，隐藏活动页则定位邻近可见表。仅改顺序/视图不清除 calcChain 或改写单元格缓存、共享字符串计数；实际单元格编辑继续沿已有计算元数据规则保存。

`XlsxQuery.sheetEditReason` 是工作表级管理操作的保护原因，空串表示可用。当前继续保护未知单元格公式、锁定结构的 workbookProtection、三维名称引用、无法解释的名称语法、未支持的工作簿扩展、自定义工作簿视图及未知根内容。源内容保留；不通过放开按钮改变引用语义。默认 UI 提供前移/后移、隐藏与显示普通 hidden 表；veryHidden 仅由显式 API 修改。

含受支持透视表、切片器与时间线的工作簿可沿原入口新增、重排和隐藏/显示表。核心校验已知工作簿扩展，保留原生 sheetId/tabId、控件身份、连接、缓存记录、数据来源及待刷新值。新增/重排同步既有名称作用域、窗口和计算索引；可见性及精确历史沿同一事务。未知扩展、工作簿结构保护、最后可见表和既有资源预算继续校验。

可见控件的成员/日期筛选及显式刷新同时更新隐藏报表。隐藏源表仍提供实际来源；隐藏报表仍执行工作表保护、范围冲突、输出和历史预算检查，任一报表失败时整项回滚。直接通过 API 刷新或改字段的独立隐藏报表保留当前选区；显示表后继续原生编辑。实现复用 [sheet-order.mbt](../../../modules/formats/src/xlsx/sheet-order.mbt)和[pivot-refresh.mbt](../../../modules/formats/src/xlsx/pivot-refresh.mbt)。稳定身份重排及可见性参考 [ONLYOFFICE replaceWorksheet](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L4062-L4084)与 [setHidden](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7990-L8010)，未复制上游执行代码。

`sheetRenameReason`、`sheetCopyReason` 和 `sheetDeleteReason` 分别说明改名、复制和删除的资源保护原因。默认面板按命令分别禁用控件；其他管理操作的保护不阻止可用的改名。最后一张可见表、名称合法性和容量等条件仍由各命令检查。普通图表已有工作表改名、复制和删除时的引用维护。

`{ action: "rename", name }` 修改表名，保持 OPC 路径、sheetId、关系、顺序、可见性及选区。名称为 1–31 个 UTF-16 单元，须是有效 XML 文本，不能含控制字符或 `[]:*?/\`，不能以单引号开头或结尾，不能与其他表名大小写不敏感地重复。相同名称不新增历史；无效名称、旧 revision 或预算失败不修改文档。

核心复用公式词法分析，仅替换 `!` 前匹配旧名称的标记。新引用使用单引号包围名称，并转义名称内的单引号。更新范围包括单元格公式、定义名称、既有条件格式/数据验证公式和内部超链接 `location`；带关系 ID 的外部链接保留其目标内位置。字符串常量、共享公式组与源格式保持不变；事务重建计算并沿既有计算元数据规则保存，撤销恢复原部件字节。规则呈现与编辑范围分别归[条件格式](xlsx-calculation.md#条件格式)和[数据验证](xlsx-calculation.md#数据验证)。

受支持原生透视表、切片器和时间线的源表及报表也可改名，支持共享结果缓存、独立日期缓存及仍在目录中声明的未使用普通缓存。核心先核对缓存、视图和连接，再更新普通及独立日期缓存的 `worksheetSource@sheet`；缓存记录、成员状态、日期选区、无效标志及待刷新源值保持。改名不刷新报表，保存重开后仍可筛选并显式协调刷新。OPC 路径、sheetId/tabId、对象与缓存身份、单元格及绘图选择沿一次精确历史保留。未知扩展、不支持的透视源、冲突引用、结构保护和超限继续原子拒绝。实现归 [`analysis-rename.mbt`](../../../modules/formats/src/xlsx/analysis-rename.mbt)与[原改名事务](../../../modules/formats/src/xlsx/sheet-rename.mbt)，来源绑定依据 [ONLYOFFICE WorksheetSource](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L14895-L14920)。含分析资源的整行插删及完整数据源/报表的整列平移归[行列插入与删除](#行列插入与删除)；删除被使用字段及局部单元格结构继续实施。

`{ action: "delete" }` 删除指定表，至少保留一张可见表。删除活动表时优先选择右侧可见表，再向左查找，定位 A1；删除其他表保留活动表与范围。同步剩余名称的 `localSheetId`、工作簿窗口及工作表视图；移除被删表的局部名称。将指向该表的已支持单元格/区域引用整体替换为 `#REF!`，覆盖单元格公式、保留的定义名称和既有条件格式/数据验证公式；移除指向它的内部超链接，保留外部链接及字符串常量。共享公式组继续保存为共享组，失去目标的错误参与依赖计算和缓存写回。核心现可解析七种标准公式错误常量，保留错误传播和 IF 的按需求值规则。引用错误在网格和 PDF 中使用同一结果。

`{ action: "copy" }` 在目标表后复制，分配新的 sheetId、部件及关系身份。名称从 `原名 (1)` 起避让重名，长度不超过 31 个 UTF-16 单元且不切断代理对。副本保留内容、格式、尺寸和可见性，更新自身显式引用与复制的局部名称；其他表的引用及字符串常量不变。已有普通便笺及对应 VML 复制为独立部件，清除副本的可选 guid/shapeId，源便笺不变；外部链接只保留地址。可见副本激活 A1，隐藏副本保留当前选择。副本部件和元数据使用同一有界历史，失败不修改文档。[结构化表](xlsx-calculation.md#结构化表与引用)和[普通图片](xlsx-objects.md#工作表图片)同时建立各自独立部件；[原生线程批注](xlsx-calculation.md#单元格线程批注)同时复制为独立资源；复杂绘图、非便笺 VML 及未知身份扩展仍受保护。便笺范围归[单元格便笺](xlsx-calculation.md#单元格便笺)。

普通透视表已随 `copy` 复制为独立定义和关系部件，名称用 `原名_1` 起避让重名。原生 cacheId、缓存定义/记录和数据源继续共享，即使源数据与报表位于同一张被复制的工作表，也保留原表数据来源。复制不刷新旧缓存或待刷新源值；副本的数据格可独立修改，只有原数据源变化才使共享报表待刷新。显式刷新沿既有协调事务更新各报表，保留其独立字段设置。多报表复制分别保留各自的缓存图，删除单个报表继续保留其他拥有者的缓存。

定义、关系、内容类型、选择及工作表内容合为一项精确历史，保存重开后可继续输入和刷新。复制后全文最多 16 个透视报表，沿用每个源部件 2 MiB、历史 4 MiB 和包预算；未知扩展定义及异常关系保持复制保护；受支持的控件连接图见下文。实现归 [pivot-sheet-copy.mbt](../../../modules/formats/src/xlsx/pivot-sheet-copy.mbt)，共享语义依据 [ONLYOFFICE 工作表透视复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7246-L7252)及 [cloneShallow](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L3553-L3559)。未复制上游执行代码。

带受支持切片器和时间线的工作表可沿原复制入口创建副本。核心为关联缓存定义、本表控件视图分配独立部件、名称及可选 revision UID；本表报表连接映射到副本名称和 tabId，远端连接保持。普通透视缓存、记录、独立日期数据缓存及原数据源继续共享。复制源数据和报表所在表时也保持原来源；缺失来源副本保留旧身份，须显式改源。原始部件、待刷新数值、成员选择及日历分组区间保持。

绘图引用、控件扩展、关系、内容类型、工作簿和必要行高合为一项精确历史。候选自动适配读取完整新工作簿；锁、未知元数据、异常归属或预算失败保持文档、选择及重做。复制形成的重叠切片/日期连接沿原筛选与刷新入口同步；后续创建控件仅在既有缓存状态一致时复用。仍沿用全文 16 张报表、每部件 2 MiB、历史 4 MiB 及包预算。实现归 [analysis-sheet-copy.mbt](../../../modules/formats/src/xlsx/analysis-sheet-copy.mbt)。本地连接映射与远端连接保持参考 [ONLYOFFICE SlicerCacheDefinition.copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Slicer.js#L1772-L1779)及[工作表缓存克隆](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7198-L7204)，未复制上游执行代码。

普通透视报表已随 `delete` 删除。独立定义和关系同步移除；仍被其他报表使用的缓存保留，最后一个拥有者删除时回收缓存定义、记录、关系、内容类型及工作簿目录。多报表与多缓存一次校验和提交，复用单个透视表删除的资源归属检查。删除源数据表时保留其他报表的已有结果、缓存记录及原来源名称/范围，标记待刷新；不把缓存数据改写成新工作表。

缺失来源的报表仍可保存、输出缓存 PDF，以及继续范围外输入和复制。目录返回 `sourceSheet:null/settings:null` 和原因；通过原生字段与缓存校验时，另附 `recovery`，类型为 `Omit<XlsxPivotSettings,"sourceSheet">`。该对象只包含已验证的旧字段设置和范围，不提供推测的来源身份。默认字段面板要求显式选择现有工作表后预览和应用；既有 `updatePivot` 校验列身份、重建缓存，并协调更新同缓存的全部报表，保留各自字段布局。直接刷新保持禁用，失败保留文档与重做。单个缺失来源报表也可显式删除。

删除、资源回收和来源失效共用工作表事务的选择、公式引用及精确历史；显式改源沿既有透视事务，保存重开后继续使用。外部来源、未知缓存及异常归属仍保持整表删除保护。资源归 [pivot-delete-parts.mbt](../../../modules/formats/src/xlsx/pivot-delete-parts.mbt)，批量缓存目录归 [pivot-delete-cache.mbt](../../../modules/formats/src/xlsx/pivot-delete-cache.mbt)，整表计划归 [pivot-sheet-delete.mbt](../../../modules/formats/src/xlsx/pivot-sheet-delete.mbt)，恢复读取归 [pivot.mbt](../../../modules/formats/src/xlsx/pivot.mbt)和[pivot-refresh.mbt](../../../modules/formats/src/xlsx/pivot-refresh.mbt)。原生来源属性与未解析位置依据 [ONLYOFFICE 来源序列化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L14809-L14849)及[来源属性更新](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L14895-L14931)。未复制上游执行代码。

带受支持切片器和时间线的工作表也可删除。核心在候选事务中断开该表报表连接，移除本表控件视图；其他报表继续使用的共享缓存保留。最后报表拥有者删除时，沿已有单表删除路径清理远端控件及独占切片、时间线和日期缓存资源。后续远端资源校验失败时，整次删除保留文档、选择、revision 和重做；不提前提交已通过的清理。

删除源表后，现有切片器和时间线仍按原生缓存记录筛选，可清除成员及日期条件，保留已有报表布局、原来源名称/范围和缓存记录。普通结果缓存、独立日期缓存及目录中的未使用来源缓存同步标记失效。默认字段面板可显式选新来源，沿已有协调刷新重新绑定各报表；缓存筛选不将剩余报表当作实时来源。缺失来源期间仍可复制受支持连接图，保留原来源身份，随后显式改源。实现归 [analysis-sheet-delete.mbt](../../../modules/formats/src/xlsx/analysis-sheet-delete.mbt)和[cached pivot](../../../modules/formats/src/xlsx/pivot-cached.mbt)，复用既有切片器/时间线删除与刷新。

删除移除工作表 XML、其关系、失效 calcChain 及其关系，以及独占的普通便笺 XML/VML、结构化表和普通图片绘图 XML/关系，更新工作簿关系和内容类型。其余源资源及可能共享的图片字节保留，不回收共享字符串条目或重排字符串索引；保存更新使用计数并沿现有规则标记重算。删除部件快照、引用、缓存和选择共同提交一项有界历史，可与新增、输入和改名精确混合撤销/重做；损坏回放或预算失败保留已提交文档。选择与错误引用规则参考 [ONLYOFFICE 删除工作表](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L4122-L4188)和[引用转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L10419-L10455)。

`XlsxQuery.sheetRenameReason` 包含结构保护原因，并保护尚未接入引用更新的工作簿/工作表资源关系、未知工作表内容、非空扩展及非普通/共享公式组。复制和删除通过各自查询字段返回引用保护；复制另保护未知身份属性，删除另拒绝未知的部件入站引用。默认 UI 显示原因，提供名称输入、复制、改名与删除入口，并禁用最后可见表的删除。未支持的复杂资源与引用归 [P14](../roadmap.md#p14-兼容与性能已完成)。

`{ action: "rowHeight" | "columnWidth", first, last, size }` 设置包含两端的行或列范围，索引从 1 开始。行高为 0–409.5 磅，一次最多 4096 行；列宽为 0–255 个 OOXML 字符宽度单位，列索引上限为 16384。零值隐藏并保留已有尺寸；正值设置固定尺寸并显示目标行列，列宽同时取消 bestFit。列宽由核心按 Normal 字体和字号的最大数字宽度换算为实际几何。设置行高可创建空行记录，不展开空单元格；拆分列区间保留各段的样式与轮廓属性。目标列包含未知属性或子元素时拒绝修改，保留源内容。

`XlsxQuery.dimensions` 返回查询范围的 `rowHeight`、`columnWidth` 和 `readOnlyReason`。尺寸不一致时返回 `null`，隐藏行列按 0 参与查询。默认 UI 对所选行/列设置尺寸。未知公式仍沿现有只读边界，受保护工作表拒绝尺寸修改；仅锁定工作簿结构不禁止该操作。一次修改进入既有历史，保持表身份和选区；重复设置相同源状态不增加历史。保存保留单元格源、公式缓存、共享字符串计数和 calcChain；实际单元格或公式变化继续触发原有计算元数据更新。自动适配及持续更新见下节；未编辑导入默认行的首次测量沿[自动适配](#自动适配尺寸)执行。

### 行列插入与删除

`editSheet({ action: "insertRows" | "deleteRows" | "insertColumns" | "deleteColumns", first, count })` 操作整行或整列。first 从 1 开始；插入发生在该索引前，删除覆盖从 first 开始的 count 项。count 为 1–4096，区间须位于 1048576 行或 16384 列内。默认 UI 根据当前矩形选区确定行/列区间，先提交已接受的原生草稿。核心遍历实际单元格和区间，不展开整张空表。

核心沿既有词法位置重写受影响的 A1 引用，保留字符串、非目标表的本地引用和范围外源片段。绝对标记只限制复制平移，行列结构变化仍移动绝对引用。相交区域扩展或缩短，全部失去目标则写入 `#REF!`；共享公式涉及结构变化时有界展开为普通公式。名称、打印区域/标题、合并、行列尺寸、冻结边界、滚动/选择位置、既有条件格式/验证范围及公式、内部链接同步更新。删除规则锚点时，先定位存活格原本使用的相对公式，再应用结构变换。完整删除的打印名称或规则移除，普通失效名称保留引用错误。

插入复制上方行或左侧列的已有尺寸与字符/单元格格式，清空新增格的值和公式，并显示新增行列；新增列取消 bestFit。首行/首列无前项时使用缺省格式。单元格、引用、计算缓存和选区合为一次源历史；撤销恢复精确包，保存重开可继续输入和输出 PDF。自动轴沿原有字体与工作量预算更新。规则依据 [ONLYOFFICE 行插入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L8313-L8369)及[列插入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L8473-L8554)。实现归 [`axis-edit.mbt`](../../../modules/formats/src/xlsx/axis-edit.mbt)、[`axis-reference.mbt`](../../../modules/formats/src/xlsx/axis-reference.mbt)、[`axis-cells.mbt`](../../../modules/formats/src/xlsx/axis-cells.mbt)与 [`axis-metadata.mbt`](../../../modules/formats/src/xlsx/axis-metadata.mbt)。

普通值、自定义、数值排名及平均值筛选随整行/整列插删同步。范围前插入移动整个筛选，范围内插入扩展矩形并重新匹配新增空行；删除缩短矩形，删除的条件列和按钮标记一起移除。手动隐藏及筛选隐藏来源随行移动；删除标题后，首个存活行成为标题并清除其筛选隐藏来源。失去全部列或数据行时移除筛选，仅保留存活的手动隐藏。嵌套标准排序范围和键沿既有结构变换维护。候选公式重算后重新应用条件，再更新 SUBTOTAL 缓存，与源和选区合为一次精确历史；范围后的操作保留既有筛选源及隐藏状态。变换后的矩形继续受 4096 格上限约束，插入不得裁掉工作表边缘的筛选端点。规则参考 [ONLYOFFICE 列筛选变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/AutoFilters.js#L2115-L2215)和[行筛选变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/AutoFilters.js#L2326-L2395)，实现归 [`filter-axis.mbt`](../../../modules/formats/src/xlsx/filter-axis.mbt)。

含受支持透视表、切片器和时间线时，整行插删及不改变源字段数的整列插删维护源范围和完整报表位置。操作可位于报表前后；切开或删除整个报表时原子拒绝。普通、共享、独立日期及已声明未使用缓存的 `worksheetSource@ref` 同步，变化的来源标记 `invalid=1`，缓存记录保留到显式刷新。源范围至少保留标题和一行数据。固定、随格移动与随区域缩放的控件锚点沿原绘图规则维护，连接身份和日期选区保持。候选分析资源图通过校验后，与单元格及绘图选择合为一次精确历史；移动后的报表继续受结果保护。保存重开后可继续筛选与协调刷新。在源范围前插列、删除源前的列或在源后操作，可整体平移来源并保留字段序号。源内插列及未用源列删除见下文；删除仍被使用的字段继续保护。局部单元格结构、完整报表删除和未知分析资源继续保护。实现归 [`analysis-axis.mbt`](../../../modules/formats/src/xlsx/analysis-axis.mbt)，依据 [ONLYOFFICE 来源引用变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L14729-L14771)及[透视结果整体移动与局部保护](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L11680-L11726)。

整列插入可在受支持的透视源内增加空字段。核心为原生缓存生成不重名的占位字段和空成员，并在每条已有记录中插入索引 0；源单元格保持空白。既有报表、值基准及日历派生字段同步映射，控件、缓存结果和待刷新值保留。用户填写新标题后，普通、共享及连接控件的刷新可更新未被任何报表或控件引用的字段名；仍被引用的字段必须保持原位置身份。空标题继续拒绝实时刷新。源宽度最多 64 列，原生字段最多 80 个，记录最多 65536 格，并沿用包、输出及历史预算。核心检查覆盖多列插入、两套日期系统、分组、新字段创建切片器、精确历史与失败回滚；默认插列及原生标题输入已通过 Chromium，包含缓存筛选、显式刷新、独立 XML、精确历史和保存重开。

整列删除可移除未被报表、值基准、分组或分析控件引用的源字段。核心从已有缓存投影字段和记录列，保留其余成员索引及待刷新源值；普通结果缓存、独立日期缓存和已声明未用缓存同步处理。报表的行列、页筛选、值/基准字段以及日历派生字段的 base/par 同步映射。控件名称、连接、视图和现有结果保持，来源缩短并标记失效；随后可继续缓存筛选、显式刷新和保存重开。原生删列按钮复用同一事务，完整精确历史包含单元格、公式引用及所有缓存部件。

多个缓存定义共用记录部件时，各拥有者必须都在已知资源图内，并使用相同来源字段映射；记录只写一次。记录数量、宽度、类型、成员索引及关系异常时整项回滚。跨独立缓存定义的实时记录刷新继续保护，避免其他定义保留旧成员表而读取新索引；同一缓存的多报表协调刷新保持可用。仍沿用原生字段、65536 个记录格、输出、历史和包预算。

字段投影归 [analysis-column-fields.mbt](../../../modules/formats/src/xlsx/analysis-column-fields.mbt)，记录校验归 [analysis-column-records.mbt](../../../modules/formats/src/xlsx/analysis-column-records.mbt)，实时记录归属检查复用 [pivot-refresh.mbt](../../../modules/formats/src/xlsx/pivot-refresh.mbt)及其共享/时间线调用者。原生字段映射依据 [ONLYOFFICE 旧/新字段映射](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L6572-L6605)及[页/值/基准和行列索引](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L6715-L6763)。保留缓存快照的列投影由本项目实现，未复制上游执行代码。

插入会推掉实际源行、单元格或便笺时拒绝。[传统便笺](xlsx-calculation.md#单元格便笺)、[原生线程批注](xlsx-calculation.md#单元格线程批注)、[结构化表](xlsx-calculation.md#结构化表与引用)和[普通图片](xlsx-objects.md#工作表图片)沿各自合同维护归属。Mac Excel 的 `ArchID Flags="2"` 和默认 `PLV` 逐字节保留，允许按现有规则更新单元格、打印区域和绘图锚点。工作表保护、未知公式/引用/属性、未知扩展、未知筛选、未知绘图及未知批注资源继续保护，保留文档与历史；仅锁定工作簿结构不禁止行列插删。筛选表的局部单元格移位仍受保护。四向单元格移位插删见下节；未支持的引用资源按 [P14](../roadmap.md#p14-兼容与性能已完成) 扩展。

### 单元格移位插入与删除

`editSheet({ action: "insertCells", range, direction })` 支持 `down/right`；`deleteCells` 支持 `up/left`。`range` 为当前目标表中的一个 A1 矩形，最多 4096 格；已有 `sheet` 参数可指定表。上下移位只作用于该矩形的列带，左右移位只作用于其行带；数量为所选高度或宽度。默认 UI 使用现有选区并先提交已接受的原生草稿，成功后保持该矩形选择。插入格只复制上侧或左侧的有效格式，不复制内容；到达首行/首列时使用默认格式。

事务移动稀疏单元格源，保留值、公式、富文本和有效格式；移入另一行/列后仍使用原有效单元格样式。新源片段保留命名空间，原行属性与格间注释继续保留。固定行高、列宽、隐藏/轮廓及冻结分割保持坐标；普通自动尺寸继续沿已有内容重排事务更新。实际数据会被推出工作表边缘时原子拒绝，格式、生成源、输出与历史继续受既有预算约束。

普通/共享公式、跨表引用、绝对标记、定义名称、内部链接、已支持合并区域、有效范围和计算缓存共用一次源历史。相交共享公式有界展开。单个引用及完全位于移动带中的区域按插删轴调整；跨越带边界的引用通常保持，删除完全覆盖其轴区间且切到另一轴边缘时裁掉相交边。整轴引用仍覆盖工作表末端。规则依据 [ONLYOFFICE Range.isIntersectForShift/forShift](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L614-L790)和[公式移位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L10152-L10280)，不把移动当成相对复制。

带普通图片或已支持图表的工作表也可执行四向移位。局部操作保留固定、随格移动和随区域缩放三种锚点的标记；固定行列尺寸时，绘图 XML、位置、尺寸、文字和媒体字节保持。有自动行高变化时，需跟随尺寸的对象继续按候选尺寸重排。本表及跨表图表引用沿相同移动带变换，分类、系列标题、独立数值长度和失效缓存归[工作表图表](xlsx-objects.md#工作表图表)。单元格、公式、引用和缓存共用一次精确历史；未知资源、无法表示的矩形及预算失败继续原子拒绝。实现归 [`axis-edit.mbt`](../../../modules/formats/src/xlsx/axis-edit.mbt)、[`picture-axis.mbt`](../../../modules/formats/src/xlsx/picture-axis.mbt)和 [`chart-axis.mbt`](../../../modules/formats/src/xlsx/chart-axis.mbt)。锚点规则依据 [ONLYOFFICE 局部移位与整轴绘图更新](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/DrawingObjects.js#L3232-L3558)，沿用本项目的引用和绘图实现。

既有条件格式/数据验证的 `sqref` 按移动带拆分或删除；普通公式保持各格的相对、绝对和跨表引用。公式型 `cfvo` 阈值按整条规则更新引用，不随覆盖格偏移。需要不同公式的区域按各条 `cfRule` 分组保存，避免其他色阶或数据条随之拆分统计样本；保留规则属性、源注释和命名空间。条件格式保留原优先顺序并分配唯一优先级，验证同步 `count`，与单元格共用一次精确历史。常量、全绝对公式及整条规则阈值按区间处理，不展开整列空格。逐格相对公式每次操作最多求值 100000 个规则覆盖格、处理 4 Mi 字符，累计最多 4096 个规则片段；克隆源另受单部件与 4 Mi 字符上限约束。未知规则结构、无法解析的公式、克隆身份扩展或预算不足时原子拒绝。范围变换参考 [ONLYOFFICE 条件格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L564-L643)和[数据验证](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/DataValidation.js#L976-L1067)，整条规则阈值沿[统一求值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L1029-L1086)。

范围变换复用源规则与引用事务。普通条件格式的呈现与验证执行/编辑已接通，范围归[条件格式](xlsx-calculation.md#条件格式)和[数据验证](xlsx-calculation.md#数据验证)；未呈现效果的 PDF 继续原子拒绝。传统便笺与[原生线程批注](xlsx-calculation.md#单元格线程批注)按所选行/列带移动归属，删除目标格时同时删除批注、回复及对应 VML 框，范围外批注保留。移动带切开合并或矩形链接、依赖无法隔离的公式/引用、未接入的筛选/绘图/表格资源、未知批注及工作表保护继续原子拒绝。可用的整行/整列操作保持原有规则支持。保存重开后继续沿同一编辑与 PDF 路径工作；其他结构与资源组合归 [P14](../roadmap.md#p14-兼容与性能已完成)。

### 四向填充

`editSheet({ action: "fill", range, direction })` 支持 `down/up/right/left`，作用于 A1 矩形；源和目标合计最多 4096 格。向下/上以首行/末行为源，向右/左以首列/末列为源；沿填充轴只有一行/列时，源为方向相反的相邻行/列。相邻源越界时保持文档。数字直接重复，不推导序列。

核心复制类型值及有效格式，文字中的 `=` 保持文字；公式只平移相对引用，保留绝对与跨表引用，越界生成 `#REF!`。受影响共享公式有界展开。值、格式、依赖缓存和选区共用既有事务、自动尺寸及一次精确历史；保存重开后可继续编辑。复制文字和公式源码累计最多 1 Mi 字符，单公式最多 8192 字符，候选、源和历史仍受既有预算约束。

四向填充、序列和向外填充柄已支持普通条件格式与数据验证，细节见下段。普通链接已接通完整源范围复制及目标裁剪；传统便笺保留各格原有文字与框，不随源复制，见[单元格便笺](xlsx-calculation.md#单元格便笺)；已识别迷你图随源模式复制并平移数据源，见[单元格迷你图](xlsx-objects.md#单元格迷你图)；合并几何见下段；未知扩展、表格/透视及未知批注继续保护。范围外规则与元数据保留。默认按钮使用当前选区，沿既有队列提交原生草稿。核心已检查四向、相邻边界、类型值、有效格式、共享公式、重算、精确历史、重开及原子失败；Chromium 已检查四向按钮、原生草稿、独立公式/样式/缓存源、混合历史、保存重开和 PDF。重新打包的参数检查与严格宿主调用通过。数字序列见[数字序列](#数字序列)，基本拖动与键盘操作见[填充柄](#填充柄)。来源选择参考 [ONLYOFFICE prepareFillHandle](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L27533-L27590)，实现归 [`fill.mbt`](../../../modules/formats/src/xlsx/fill.mbt)。

#### 合并格填充

四向按钮以起始行/列为源；若该边穿过合并格，核心沿填充轴扩至完整源块。值、公式和各格有效格式按该源块循环，合并区域一起平铺到目标。尾块不足源尺寸时裁到目标边界；裁成单格时保持普通格，不写单格合并。自动/文本/数字趋势沿现有源槽位和实际格位置推导；仅被合并覆盖而没有锚点的数字序列行/列循环源值和格式。显式日期模式每行/列仍只接收一个数字种子，可由一个完整合并格承载，按合并跨度推进日期。

源和已有目标合并必须完整包含，不能切开；目标几何已等于源平铺结果时可重复填充。需要替换其他目标合并时，源与目标须由同尺寸合并格完整平铺，否则原子拒绝。未知合并元数据继续保护，范围外节点、注释和未改部件保留。填充复制各物理格的值和格式，不执行另一次合并命令的丢弃策略。

单个合并锚点可作为序列和填充柄的完整源。预览的 `source` 保留原选择地址，`range` 使用核心合并边界；宿主沿核心返回的单元格几何放置填充柄。Ctrl、四向方向键、拖动及源内合并的相邻延伸复用同一事务。向内清除仅清完整合并区域的内容，保留合并和格式；切开合并的清除拒绝。相邻区域中源外的合并向导仍待支持。

值、公式缓存、合并几何和选区先在候选中校验，再提交一次精确历史；仅几何变化也可撤销。沿用 4096 个受影响物理格、1024 个工作表合并区域、内容/公式和输出/历史预算，失败保持源、选择和历史。保存重开继续编辑，网格和 PDF 使用同一合并几何；跨打印页边界的合并仍遵守既有 `print-overflow` 保护。

尺寸保护和平铺参考 [ONLYOFFICE 合并填充](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21799-L21920)及[尾块裁短](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22594-L22616)，四向和趋势结果核对其[独立合并用例](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/SerialTests.js#L5006-L5210)。实现归 [`fill-merge.mbt`](../../../modules/formats/src/xlsx/fill-merge.mbt)、[`fill.mbt`](../../../modules/formats/src/xlsx/fill.mbt)与 [`cell-transaction.mbt`](../../../modules/formats/src/xlsx/cell-transaction.mbt)，不新增公开 API。

#### 本地化文本循环

`auto` 在核心识别九组常用文字表：英文星期与月份的全称/缩写、`星期日`–`星期六`、`周日`–`周六`、`週日`–`週六`、`一月`–`十二月` 和 `1月`–`12月`。按源文字识别，不依赖浏览器或界面语言。`May` 同时属于月全称和缩写时，优先采用相邻源格的同类表；单独出现时使用全称。匹配忽略大小写、两端空白和末尾句点，源格原文仍保留。

同类文字转成循环索引后沿既有整数趋势推导，跨周/月/年边界延续，四向填充自然反推。单值按一个位置推进，多值可推导跳项；非整数趋势沿文本模式重复源。常量、规则空白槽位和不同类别的独立分组复用原逻辑。目标仍循环采用对应源格的格式和大小写风格：前两字母全大写时输出大写，首字母大写时输出首字母大写，其余输出小写；中文文字保持不变。

仅字面文字参与识别。公式缓存中的星期/月名继续按公式平移，带数字后缀的其他文字仍按文本编号推导；数字与数值日期沿既有路径处理。显式 `text` 模式不使用这些词表，Ctrl 及 `copy` 继续循环复制。按钮、拖动/方向键和相邻区域延伸共用该推导与一次精确历史，保存重开和 PDF 使用生成的文字。不增加新 API 或语言配置；其他语言、别名和用户自定义循环表尚未接入。

词表、大小写及相邻源消歧参考 [ONLYOFFICE 时间名称自动填充](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22051-L22165)及 [中文文化数据](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/NumFormat.js#L6090-L6120)。循环的展开/反推复用本项目整数趋势；实现归 [`series-cycle.mbt`](../../../modules/formats/src/xlsx/series-cycle.mbt)与 [`series-text.mbt`](../../../modules/formats/src/xlsx/series-text.mbt)。

#### 条件格式与验证

条件格式和数据验证随源范围按原周期扩展，覆盖目标内旧规则并保留范围外部分。复制、自动、线性、增长、日期及文本序列共用此事务。核心保留原生规则与差异样式引用、优先级相对顺序、验证提示和容器元数据；色阶、数据条的最小/最大值仍按源和新范围共同计算。向上/左填充重新绑定相对公式锚点，绝对引用及全局阈值沿既有规则变换。条件格式裁短最后一块；数据验证仅复制目标能完整容纳的源规则片段，部分尾块不保留旧验证。生成值按最终规则校验，失败保留原包、选区、修订和历史。向内缩减只清内容，保留规则与格式。

规则、值、公式缓存及合并几何合为一次精确历史。相同值仍可转移不同规则，重复同一结果不新增历史。沿已有 4096 格、4096 规则/范围和 1 Mi 单元格源限制；相对规则变换沿既有 100000 格、4 Mi 公式工作及历史/输出预算，超限原子拒绝。未知规则元数据、表/透视资源及未知批注继续保护。普通链接沿下段合同复制，不自动打开外链。实现归 [`fill-rules.mbt`](../../../modules/formats/src/xlsx/fill-rules.mbt)，语义参考 [ONLYOFFICE promote 的验证与条件规则扩展](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22638-L22755)；未复制上游执行代码。

#### 链接填充

四向、复制、自动和其他序列只复制完整落在源范围内的普通链接，并按源周期放到能完整容纳链接的目标片段。部分源链接及不足的尾块不复制。外部 HTTP/HTTPS/mailto 目标与内部 `#` 目标保持原字符串，不按公式相对引用平移；提示与显示标签保留，格内值仍沿所选填充模式生成。核心不请求链接，默认界面继续由用户显式打开或导航。

目标旧链接按本 SDK 既有矩形粘贴规则裁剪，保留范围外片段；新范围没有源链接时清除旧链接。链接、值、公式缓存、格式和普通规则合为一次精确历史；同值也能更新链接，重复结果不新增历史。关系复用现有目标身份，重开后可继续输入和内部跳转；向内缩减只清内容，保留链接及其元数据。未知/组合元数据、重叠链接、不安全地址、未解析关系及超限原子拒绝。沿 4096 格/链接、1 Mi 复制链接文字、单项标签/提示 32767 单元和 2 Mi 目标链接源码上限，以及已有历史/输出预算。

完整范围与尾块规则参考 [ONLYOFFICE promote 的链接复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22619-L22636)，缩减参考 [cleanText](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21114-L21129)。目标裁剪复用本项目的链接粘贴事务；实现归 [`fill-hyperlinks.mbt`](../../../modules/formats/src/xlsx/fill-hyperlinks.mbt)和 [`clipboard-hyperlinks.mbt`](../../../modules/formats/src/xlsx/clipboard-hyperlinks.mbt)，不新增公开 API。

### 填充柄

普通网格在选区末格显示填充柄；RTL 使用左下角。拖动向外扩展一条行带或列带，核心按物理距离选择轴。向内拖动选择要清除的末尾行带或列带，只清内容和公式并保留格式；边界按命中格的半格位置吸附，角点附近未越过边界时无操作。拖到源起点可清空整块内容。聚焦填充柄后，方向键延伸一行或一列，左右键遵循 RTL 的物理方向。支持缩放、冻结窗格和边缘滚动。Ctrl 将向外填充切换为循环复制；单个普通数值改为逐格加一。日期/时间、文字及公式按源模式复制，公式仍平移相对引用。拖动中按下或松开 Ctrl 即可切换，释放使用当时的状态；方向键也支持 Ctrl。向内清除规则不变。双击填充柄，或聚焦后按 Enter/Space，按相邻连续区域向下自动填充。下方首行全部有内容时延伸至首个缺格行之前；部分有内容时不操作；全空时从左右及对角相连的区域推导末行，并停在目标列下一处内容之前。样式空格不延长区域，隐藏行仍参与推导；相邻筛选区域不能借作跨区向导。源内的完整合并可沿填充事务复制；源外参与推导的合并向导仍明确拒绝。没有可延伸范围时不增加修订或历史。

`XlsxSession/XlsxClient.execute({ operation: "fillPreviewXlsx", layoutId, target })` 接受 `{ kind: "point", x, y }`、`{ kind: "direction", direction }` 或 `{ kind: "adjacent" }`。三种 target 都接受可选布尔字段 `ctrl`，默认 false。核心返回 `source/range/direction/mode/geometry/end`。Ctrl 向外操作返回 `mode=copy` 或单个普通数字的 `mode=linear`，range 与自动向外操作相同。`mode=auto` 的 range 是源与向外目标的并集，`mode=shrink` 的 range 是待清尾带；geometry 显示此操作区域，end 定位提交后的末格。预览不改文档、选区、revision 或历史。过期布局、非法目标和超过 4096 格的范围拒绝。宿主只发送指针与键盘意图，范围和冻结裁剪由核心计算。

原生草稿先独立提交，再恢复拖动前的源范围。预览不写源；释放时按预览的自动、复制、线性或缩减模式执行一次事务，后续保存排在该操作之后。未释放时，Escape、失焦、指针取消、暂停和销毁取消拖动。普通规则沿下述填充合同扩展；向内清除内容保留原规则和格式。普通链接随同一次填充复制，向内缩减保留链接；其他未知资源继续保护，合并源沿下述几何规则处理；失败保持源和历史。普通支持的链接不阻止静态 PDF；未知工作表扩展仍明确拒绝完整输出。

`editSheet({ action: "series", mode: "shrink", source, range, direction })` 提供同一缩减操作。source 是原选区，range 必须是其中完整的末尾行带（direction=up）或末尾列带（direction=left），原范围限 4096 格。保留左上区域成为选区；全清时仍选择原范围。没有内容可清时仅调整选区，不新增 revision 或历史。共享公式展开和依赖缓存复用已有单元格事务；其他单元格、行列尺寸及源元信息保持。规则依据 [ONLYOFFICE canPromote](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21961-L22003)及[缩减仅清内容](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22296-L22303)，实现归 [`fill-shrink.mbt`](../../../modules/formats/src/xlsx/fill-shrink.mbt)。

`editSheet` 的 `series` 支持 `mode=copy`，循环复制源值及格式并平移公式相对引用。Ctrl 规则参考 [ONLYOFFICE 数值切换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22408-L22421)。

双击范围依据 [ONLYOFFICE applyFillHandleDoubleClick](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L15248-L15306)及[连续区域扩展](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L4528-L4783)。实现归 [`fill-adjacent.mbt`](../../../modules/formats/src/xlsx/fill-adjacent.mbt)，以非空行列索引查询边界，避免逐格扫描稀疏工作表；最终范围继续受 4096 格限制。

方向选择参考 [ONLYOFFICE changeSelectionFillHandle](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L14754-L14825)，未复制上游代码。实现归 [`fill-preview.mbt`](../../../modules/formats/src/xlsx/fill-preview.mbt) 和 [`spreadsheet-pointer.ts`](../../../packages/xlsx/src/web/spreadsheet-pointer.ts)。

### 数字序列

`editSheet({ action: "series", mode, source, range, direction })` 的缩减模式见[填充柄](#填充柄)。生成序列时，从显式源矩形填充序列，`mode` 为 `linear`、`growth`、`date`、`text` 或 `auto`，`direction` 支持四个方向。日期模式另需 `unit` 和 `step`，其他模式拒绝这两个字段。核心使用 `SeriesMode.Linear/Growth/Date(unit, step)/TextSeries/Automatic`。`range` 包含源和全部目标，最多 4096 格；源须占据方向起始边，且完整覆盖垂直方向的列带或水平方向的行带。源与目标相同时为无操作。

各列/行独立使用源数字和实际位置拟合趋势，保留全部种子；空白不参与拟合，也不压缩其位置。每条序列至少有一个字面数字。线性模式按最小二乘拟合，单值种子的步长为 1，向上/左自然反推。增长模式对正数取自然对数后拟合，再还原指数值；单值或恒定种子保持原值。公式、文字、布尔及错误种子明确拒绝，增长模式另拒绝零和负数。两种模式均支持非等差样本及四向外推。

目标沿用该行/列首个数字种子的有效格式，写入数字并同步依赖缓存。增长计算在对数域合成，避免先指数溢出再缩放；非有限结果原子拒绝，极小结果沿 IEEE 754 下溢为零。行为及格式来源参考 [ONLYOFFICE 数字取对数与趋势拟合](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L24917-L25039)，未复制上游代码。

日期模式每条序列使用一个字面数字种子；垂直源为一行，水平源为一列，可同时填充多条。`unit` 为 `day/weekday/month/year`，`step` 为有限数字，绝对值不超过 2958465；仅天允许小数，其余单位使用整数，零复制原值。向下/右按步长前进，向上/左反向，负步长反转。核心使用工作簿的 1900/1904 日期系统，保留时间小数；结果须在序列零点至 9999-12-31 当日内。1900 系统保留序列 60 的虚构闰日。工作日跳过周六、周日，不含节假日；按整周及有界余数计算，避免大步长逐天遍历。月序列按原日号截到目标月末，后续月份恢复原日号；年序列按上游规则把非闰年的 2 月 29 日进位至 3 月 1 日，再沿该日期继续。规则参考 [ONLYOFFICE 日期序列](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L24665-L24757)及 [cDate 年月变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L4063-L4075)；小数时间按本项目日期值模型保留，不采用上游的整数日期截断。

文本模式接受字面文本或空白。按填充方向把相邻同前缀的 ASCII 数字后缀分组；不同前缀或非空普通文字结束当前组。每组独立拟合整数截距和步长，单值向下/右步长为 1，向上/左为 -1。组与普通文字沿源槽位循环。保留前缀，采用该序列最长的前导零宽度；超出宽度时自然增长。向上/左反推，跨零后按上游取绝对值。纯数字文本仍输出文本，各目标循环采用对应源格的有效格式。规则空白间隔且数值等差时，按种子顺序拟合并保留空白槽位；间隔或差值不规则时，按实际位置拟合，整数趋势同时填入组内空白槽位。源中的空白保持原样，生成值保持文本类型及对应源格格式。纯文本和非整数趋势重复原值，本地化星期/月名由自动模式推导。后缀及结果限于精确整数范围 0–9007199254740991，单格最多 32767 UTF-16 单位；单条序列处理的内容和全部生成内容各限 1 Mi 单位，超过预算原子拒绝。大编号先减去首值再拟合，避免均值抹去相邻整数差。后缀、补零和跨零规则参考 [ONLYOFFICE 文本填充](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22360-L22385)、[整数趋势与最长补零](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L23185-L23334)及 [跨零处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L23447-L23453)。未复制上游代码。

自动模式按源槽位同时处理数字、文本和公式。数字与文字前缀分别分组；数字可使用小数趋势，单格数字源复制原值，多格源中的单个数字组按 1 或 -1 延续。文字沿文本分组规则推导，布尔、错误和普通文字按原类型重复。公式分隔相邻组，再按对应源格平移相对引用；绝对引用不动，越界引用写为 `#REF!`。所有目标循环复制对应源格的有效格式，源格保持原样，填充与依赖重算合为一次历史；公式与文本共用 1 Mi 单位预算，单条公式最多 8192 单位。数字的非有限结果原子拒绝。自动模式也按既有数字格式识别日期、日期时间与时间，规则见下段；指定日期单位和步长仍使用显式 `date` 模式。本模式复用已有趋势、文本分组和公式平移；[`series-auto.mbt`](../../../modules/formats/src/xlsx/series-auto.mbt) 负责合成，不增加计算服务。

默认面板提供序列开关、线性/增长/日期/文本/自动模式、日期单位和步长、源范围输入及使用当前选区的按钮；随后选择包含源的完整目标，再用四向填充按钮执行。更换工作表后须重新指定源，重开文档恢复普通填充模式。原生草稿先独立提交，填充复用同一共享公式展开、自动适配、重算、保存及精确历史；无值、格式或合并几何变化时不新增 revision。有限数值或日期计算失败、被切开的合并及既有填充资源保护均原子拒绝。手动隐藏行列按实际位置参与；相交的已启用筛选保护，后续再接可见格序列。规则资源复制仍按 P11 实施。文本实现归 [`series-text.mbt`](../../../modules/formats/src/xlsx/series-text.mbt)，共用实现归 [`series.mbt`](../../../modules/formats/src/xlsx/series.mbt)和 [`series-date.mbt`](../../../modules/formats/src/xlsx/series-date.mbt)。

自动日期使用源格的有效数字格式，日期组与普通数字组分开。纯日期按整数天拟合，常量或非整数趋势循环源值；单日期按方向延续一天。同一日号且日历间隔为整数时，推导月序列；月份也相同时可推导年序列。月份截到月末后恢复原日号，年份沿既有闰日进位规则。规则空白保留槽位，不规则空白参与实际位置推导。源日期、时间小数及格式保持原样，各目标循环源格格式。

日期时间保留数值时间差；月/年模式分别推进日历与时间差，避免时刻越过午夜后改变后续月份。混合日期和日期时间使用整数日期趋势及首个日期时间格的固定时间部分。不形成有效日期趋势时重复源模式；同日但不一致的小数时间趋势按上游规则保持起始时刻。单时间按一小时推进，多时间拟合小数天，反向越过午夜时回到当天时刻。日期仍使用工作簿的 1900/1904 系统；非法源或超出日历范围的结果整项拒绝，包括其他组已推导出候选值的情况。工作日仍由显式日期模式指定，不自动猜测节假日或工作日序列。

识别与拟合参考 [ONLYOFFICE 日期/时间自动填充](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L23237-L23346)及[月/年识别](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L23607-L23633)。实现归 [`series-calendar.mbt`](../../../modules/formats/src/xlsx/series-calendar.mbt)，复用已有日期步进和填充事务，未复制上游代码。

### 区域排序

已识别迷你图的普通行列排序和原生表行排序沿同一事务执行。目标地址、源范围及原生扩展字节保持，图形从排序后的当前格值重绘。图形位置与便笺归属分别处理，便笺仍随单元格移动。详细边界归[单元格迷你图](xlsx-objects.md#单元格迷你图)。

同一工作表含受支持原生表时，表外普通矩形仍可按行或列排序。核心检查表资源归属，保留表范围、列身份、计算列模板和原生排序状态。按当前全部筛选来源冻结可见位置，候选计算后重新应用相关条件；手动隐藏和各筛选来源分别保留，最终隐藏取并集。普通筛选内的排序状态仍写入所属筛选，其他普通排序写入工作表；原生表的排序状态独立保存。选区与表相交时沿[原生表行排序](xlsx-calculation.md#结构化表与引用)规则，跨表边界仍保护。范围归属参考 [ONLYOFFICE searchRangeInTableParts](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L1479-L1500)。

`editSheet({ action: "sort", range, rows, header, caseSensitive, keys })` 对最多 4096 格的显式 A1 矩形排序。`rows=true` 按行重排，键 `index` 是工作表从 1 开始的列号；`rows=false` 按列重排，键为行号。`keys` 为 1–16 个互异条件 `{ index, descending, customList?, sortBy?, color?, iconSet?, iconId? }`，索引必须在范围内，按数组顺序比较。三个布尔字段必须显式提供，`header=true` 保留所选范围的第一行或第一列。默认面板使用当前选区，提供方向、标题、大小写、增删多键、每键自定义列表、颜色及图标依据。`XlsxSortSettings/XlsxSortKey` 从 Wasm/Web XLSX 模块导出。

核心冻结排序前的当前键值，不用导入缓存代替未计算公式。数值及可解析为有限十进制数的文字键按数字比较，保留原单元格类型；布尔和错误按显示文字参与文字比较。空格与空串不同；空单元格和空串结果在升降序中均置后。相同键按原行列顺序稳定排列。`caseSensitive=false` 使用固定 Unicode 16 大写映射，文字按 UTF-16 字符序比较，不使用 MoonBit 默认的长度优先比较；语言区域校对顺序仍待兼容扩展。隐藏行或列的位置、内容与手动隐藏状态保留，不参加对应方向的置换。普通比较、隐藏位置和多键路径参考 [ONLYOFFICE _getSortElems](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21327-L21649)；该上游的 localeCompare 与本期固定字符序不同。

每个值键可选 `customList: string[]`，缺省或空数组使用普通排序。非空列表按给定顺序定义文字优先级，各键可使用不同列表。沿既有归一化，数字及数字文字继续按数值比较，布尔和错误按显示文字参与匹配。列表先精确匹配原文字，未命中时使用固定 Unicode 大写映射查找列表中的第一项；仅大小写不同的标签可以分别列出，精确命中保留各自顺序。此列表匹配规则不受 `caseSensitive` 改变，该选项继续控制未列出文字的普通比较。升序时列出项排在未列出文字之前，未列出项按普通顺序比较；降序反转文字比较结果，空单元格和空串仍排在末尾。相同优先级继续比较后续键，再保持源顺序。

每份列表最多 4096 项，逗号连接后的长度最多 32767 UTF-16 单元。标签必须互不相同且非空，前后空格保持，不能包含逗号、回车或换行。引号、制表符及看似 OOXML 转义的文字通过既有文字编码保存；原始和编码后的列表载荷另受 1 Mi 单元预算约束，失败不提交。默认面板按键提供每行一项的输入，留空恢复普通排序。核心 `SortKey.custom_list` 使用空数组表示普通顺序；TS 的 `customList` 可省略。列表与单元格、排序状态、筛选和缓存合为同一项历史，不另建应用级自定义列表目录。

已检查 ONLYOFFICE 的上述排序路径，其文字分支没有自定义列表比较。因此文字优先级参考下一顺位的 [LibreOffice GetSubIndex/Compare](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/tool/userlist.cxx#L60-L142)与[文字键排序入口](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/data/table3.cxx#L1534-L1585)。实际大小写映射和未列出项排序继续采用本项目的固定规则，不执行地区化校对。每键顺序写入标准 `sortCondition@customList`，导入、无关编辑、工作表复制/改名及既有排序状态引用维护保留它；实现归 [`sort-list.mbt`](../../../modules/formats/src/xlsx/sort-list.mbt)。

`sortBy` 缺省或为 `value` 时按值比较；`cellColor` 按填充色，`fontColor` 按单元格字体色。颜色键必须给出 `color`，使用六位 RGB 十六进制文字；填充色的空串表示无填充，与白色不同。颜色键不能同时使用非空自定义列表，值键不能指定非空颜色。同一轴可设置不同颜色或依据，例如先红色、再绿色，最后按该列数值；完全重复的条件仍拒绝。`descending=false` 把命中色放在前面，`true` 放在后面，同组继续比较后续键，再保持原顺序。空内容格也按其有效颜色参加此分组；隐藏行列继续保留位置。

颜色取自排序前的有效样式，包含已支持条件格式及主题/索引颜色的解析。核心冻结颜色匹配结果，再使用原有单元格置换；条件规则仍留原范围，排序后重新求色，依赖位置的规则可能改变最终颜色。默认面板提供依据、RGB 输入、无填充及命中色位置。颜色条件写标准 `sortBy` 与 `dxfId`，一次批量复用或新增差异样式；首次样式部件也与数据、关系和历史一起提交。原有规则和样式身份保持，颜色引用缺失时拒绝重排或引用相关的表操作。普通富文本文字色沿[颜色筛选](#颜色筛选)的文字段规则匹配；未知源继续保护。

`sortBy: "icon"` 按当前条件格式实际显示的图标匹配。`iconSet` 使用已支持的 17 种标准名称，`iconId` 是从零开始的图案索引；两项同时省略时匹配无图标的格。其他依据不能指定图标，图标键不能携带非空颜色或自定义列表。默认控件按一开始编号，切换级数时裁到有效图案范围；规则反转不改变图案身份。`descending=false/true` 分别将匹配项置前/置后，同组沿后续键及原顺序比较；同轴可指定多个不同图标。核心在置换前冻结有效图标，保留规则优先级、停止规则、当前公式和空值语义；规则仍留原坐标，排序后按新内容重绘。普通行/列和原生表行排序复用相同事务、隐藏位置及精确历史。标准 `sortCondition` 写 `sortBy="icon"` 和明确的 `iconSet/iconId`，无图标条件省略两项，不新增差异样式。读取校验分组及索引，既有复制/结构引用维护保留这些属性。MoonBit `SortKey` 增加 `icon_set/icon_id`，非图标键使用空串及零。图标身份和方向按 [OOXML SortCondition](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.sortcondition?view=openxml-3.0.1)核对，既有 ONLYOFFICE 顺位的稳定重排与多键事务保持；实现归 [`sort-icon.mbt`](../../../modules/formats/src/xlsx/sort-icon.mbt)。

有效样式冻结及按命中色分组参考 [ONLYOFFICE _getSortElems/colorFillCmp](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21427-L21600)，`dxfId` 存储参考 [CSortCondition](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/XlsxFormat/Table/Autofilter.cpp#L96-L106)。实现归 [`sort-color.mbt`](../../../modules/formats/src/xlsx/sort-color.mbt)，差异样式复用 [`conditional-style-edit.mbt`](../../../modules/formats/src/xlsx/conditional-style-edit.mbt)，没有新增绘制模型或复制上游源码。

排序移动单元格值、富文本 XML、有效样式及已支持公式，局部补齐命名空间，保留源格式。公式相对引用按实际位移平移，绝对引用保持，越界生成 `#REF!`；受影响共享组有界展开。区域外公式引用继续指向原坐标，并按排序后的内容重算。单格超链接随内容移动，矩形链接保持原坐标，关系和目标不变。条件格式、验证及名称保持原坐标范围，效果和输入约束基于候选值计算；验证失败整项拒绝。行列尺寸保留原位置，已有自动尺寸仍按新内容重排。公式、依赖缓存与值/源/链接使用同一有界历史，精确撤销/重做，保存重开及 PDF 使用已排序内容；原生草稿先独立提交。恒等置换不新增 revision 或历史。重排及公式位移参考 [ONLYOFFICE _sortByArray](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21651-L21770)。

已有普通值/自定义筛选的工作表也使用相同排序入口和显式范围。核心先按排序前的可见性冻结参加坐标；行排序保留手动及筛选隐藏记录的位置，列排序保留隐藏列位置。筛选范围、条件及按钮属性保持原坐标，不随单元格移动。候选值、格式和公式生成后，重新应用筛选，保留原手动隐藏来源，并重算依赖可见性的 SUBTOTAL 缓存；排序后可见行可因当前位置的公式结果而变化。单格链接和便笺沿内容移动，区域外源保持。单元格、筛选掩码、公式缓存与选区共同提交一次精确历史；恒等置换不新增历史。默认排序面板沿相同原生草稿屏障执行，保存重开保留当前顺序和筛选；清除条件只恢复筛选隐藏。

实际发生置换时，核心把范围、键顺序、升降序、行/列方向和大小写选项保存为标准 `sortState`，与内容和筛选共用一次历史。`ref` 排除显式标题；值键写 `sortBy="value"`，颜色键写相应依据与差异样式引用，图标键写相应集合和图案索引，固定字符序写 `sortMethod="none"`。排序范围位于已有筛选内时写入该筛选，否则写入工作表；另一位置的历史排序设置保持。恒等置换不改排序信息或历史。导入可保留合法空状态及最多 64 个不同排序条件及其自定义文字顺序；同轴颜色条件按依据和差异样式引用区分，`none`/`pinYin`/`stroke` 标志在无关修改和筛选重新应用时保留源内容；这不表示执行地区化排序。新命令仍限 16 键。工作表改名、复制与重开保留设置；工作表级排序信息随整行列及完整覆盖排序区域的单元格移位同步范围和键引用，删除键时移除该键，失去全部键时移除状态。只跨过排序区域一部分的移位保留上次排序记录。清除筛选条件保留其排序信息；新筛选范围不能容纳旧排序范围时移除旧信息，移除筛选也移除其排序信息。其他位置和未知源保持。

上述存储和引用维护参考 [ONLYOFFICE SortState](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L9742-L10000)、[OOXML 排序定义](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/Test/Applications/DocxFormatCodeGen/codegen/Resource/sml.xsd#L148-L182)及[写入代码](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/XlsxFormat/Table/Autofilter.cpp#L320-L352)，没有复制上游源码。

排序键归一化共享 1048576 次公式工作预算，移动片段累计最多 1 Mi UTF-16，继续使用公式、候选、源和 4 MiB 历史上限。合并区域、未知筛选/排序元数据、绘图、未支持的结构化表操作/透视、未知批注、未知资源或关系、未知单元格/公式标记和工作表保护继续原子拒绝。更广合并/资源支持归 [P14](../roadmap.md#p14-兼容与性能已完成)。实现归 [`sort.mbt`](../../../modules/formats/src/xlsx/sort.mbt)、[`sort-state.mbt`](../../../modules/formats/src/xlsx/sort-state.mbt)、[`sort-source.mbt`](../../../modules/formats/src/xlsx/sort-source.mbt)、[`reorder-cells.mbt`](../../../modules/formats/src/xlsx/reorder-cells.mbt)及 [`xlsx-sort.tsx`](../../../packages/xlsx/src/react/xlsx-sort.tsx)。

### 分类汇总

`SpreadsheetEditor.data.subtotals(settings)` 预览相邻分组的汇总行、总计及大纲。settings 为 `{ range, groupColumn, valueColumn, operation }`；range 包含首行标题，列号为工作表中从 1 开始的绝对列号，两个列号必须不同且位于选区内。operation 为 `sum/count/average`，生成标准 SUBTOTAL 9、3、1；count 计算非空格。同步/Worker 客户端提供 `subtotals(revision, sheet, settings)`。`XlsxSubtotalSettings`、`XlsxSubtotals`、`subtotalFunctions` 和校验/解码从 Wasm/Web XLSX 入口导出。

返回值包含设置、`revision`、`sheet`、`resultRange`、`grandTotalRow`、`groups: [{ label, firstRow, lastRow, totalRow }]` 和前十行 `preview`。核心按当前格式化标签严格比较相邻记录，空标签接续当前组，尾部全空记录不参加分组。同标签再次出现会建立新组。预览保留文件、选择和历史。默认面板提供两列及三种计算方式，预览后执行 `editSheet({ action: "createSubtotals", settings, sourceRevision }, sheet?)`。

核心从下向上插入汇总行，再插入总计。每组使用原生绝对范围公式，总计跳过内部 SUBTOTAL；源数值变化沿既有计算更新。标题和明细顺序保持，插行同步公式、便笺和已有资源引用。汇总标签和值加粗，明细大纲级别为 2、组汇总为 1、总计为 0，汇总位于明细之后。所有插行、格式、引用及大纲合为一次事务，完整撤销恢复原文件。分组标签或边界改变后需撤销并重新创建。

首行标题后至少有一条记录、至少两列，源和结果各最多 4096 格，最多 200 组。源必须为没有交叉合并格、结构化表、筛选、大纲或已有 SUBTOTAL 的普通区域。未知结构资源、保护、过期修订和预算失败原子拒绝；外围引用与文件资源继续使用已有结构编辑保护。核心累计限制结构源扫描为 8 MiB、单元格扫描为 1048576，历史负载及保存还受既有预算约束。

实现归[分类汇总](../../../modules/formats/src/xlsx/subtotal.mbt)。GenOffice 定义功能和界面；插行、公式和大纲复用现有核心。尾部空行、未排序的空标签接续及延迟写公式参考 [LibreOffice DoSubTotals](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/data/table3.cxx#L2122-L2245)，未复制上游执行代码。

### 合并计算

`SpreadsheetEditor.data.consolidation(settings)` 返回 `{ revision, sheet, sources, target, operation, leftLabels, resultRange, overwrittenCells, preview }`。settings 为 `{ sources: [{ sheet, range }], target, operation, leftLabels }`；来源 sheet 使用查询中的稳定工作表身份，range 为 A1 矩形，target 为当前表的单个目标格。operation 支持 `sum/count/average/max/min`，分别生成 SUM、COUNTA、AVERAGE、MAX、MIN；count 计算非空来源格。同步/Worker 客户端提供 `consolidation(revision, sheet, settings)`；`XlsxConsolidateSettings`、`XlsxConsolidation`、`consolidateFunctions` 及校验/解码从 Wasm/Web XLSX 入口导出。

默认面板提供多表来源、目标格、计算方式、最左列标签开关和前十行预览。按位置取各来源相同偏移，以最大行列范围输出；没有来源覆盖的位置为空。按标签时以当前格式化文字严格匹配，按来源及行的首次出现顺序建立结果行，跳过空标签，值列保持相对列偏移。标签作为普通文字写入，`*`、`?` 及大小写保持字面身份。结果使用原生绝对单元格引用，来源数值变化后沿既有重算更新；标签分组在创建时确定，标签变化后需重新合并计算。数字、文本、布尔、空白和错误继续使用既有聚合函数语义。

预览保留源、选择和历史。`editSheet({ action: "consolidate", settings, sourceRevision, overwrite }, sheet?)` 绑定预览修订，复用整项单元格事务、验证、保护、缓存、选区及精确历史。已有目标内容需要 `overwrite: true`；源与目标重叠、目标含合并格、过期、保护或预算失败原子拒绝。目标格式、来源和目标外资源保留，工作表改名及行列结构继续维护引用。最多 32 个同工作簿来源、65536 个源格、4096 个输出格、每个结果 255 个来源引用，引用文字累计最多 1 MiB。输出边界沿工作表、公式、XML 与保存预算。

实现归[合并计算](../../../modules/formats/src/xlsx/consolidate.mbt)及[候选预览](../../../modules/formats/src/xlsx/cell-plan-preview.mbt)。GenOffice 定义界面和功能入口；聚合复用既有公式引擎。标签和固定链接参考 [LibreOffice 首次标签顺序](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/tool/consoli.cxx#L160-L206)、[非空计数与来源归属](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/tool/consoli.cxx#L303-L355)及[绝对引用](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/tool/consoli.cxx#L430-L474)，未复制上游执行代码。首行标签、外部工作簿及更广合并方式继续实施。

### 文本分列

`XlsxSession/Client.execute({ operation: "textColumnsXlsx", revision, sheet, settings })` 返回只读预览，宿主入口为 `SpreadsheetEditor.data.textColumns(settings)`。`XlsxTextColumnSettings` 包含同列 A1 范围 `range`，以及二选一的分隔符 `delimiter` 或固定宽度位置 `breaks`；不能同时提供。分隔符支持逗号、分号、空格及制表符。可选 `types` 指定每列转换，`formulas` 默认关闭。返回 `XlsxTextColumns`，含归一化设置、revision、sheet、`resultRange`、原始字段数 `splitColumns`、实际输出列数 `columns`、将覆盖的非空单元格数 `overwrittenCells` 和转换后的前十行 `preview`。设置、预览及 `XlsxTextColumnType` 从 Wasm/Web XLSX 模块导出。MoonBit 的 `TextColumnSettings.split` 使用 `Delimited(String)` 或 `Fixed(Array[Int])`，`types=[]` 表示全部文字。预览不改源、选择或历史；原生草稿和组合屏障沿既有宿主队列处理。

提交使用 `editSheet({ action: "textToColumns", settings, sourceRevision, overwrite })`。源列的编辑值从选区左上角向右拆分，包含隐藏行；公式使用带 `=` 的编辑文字，普通数值使用原值文字，不使用格式化显示或导入缓存。分隔符模式中，双引号包围字段内的分隔符保持，两个连续引号还原为一个；连续/末尾分隔符产生空字段，短行补空至最大列数。保留单元格内的换行，不把它扩成额外工作表行。默认全部写为文字，前导零和公式样式文字保持。空字段清空对应内容，单元格格式、链接、便笺和行隐藏状态保持原坐标；条件/验证范围也保持。

`types` 非空时必须覆盖全部原始字段。`text` 保留文字，`general` 复用现有数字及布尔解析；只有常规列且明确选择 `formulas=true` 才解析公式，无法计算的公式拒绝整项操作。`ymd`、`mdy`、`dmy` 分别按明确年月日顺序转换，要求四位年及数字日期，接受 `/`、`-`、`.` 和既有时间解析。无效日期保留原文；有效日期使用工作簿 1900/1904 日历，并设置 `yyyy-mm-dd` 或 `yyyy-mm-dd hh:mm:ss`，其余样式保持。`skip` 丢弃该字段，其余字段向左紧排；必须保留至少一列，实际输出矩形之外保持原样。默认面板先预览，再逐列选择类型，公式另有勾选项；候选日期、计算值和格式与提交一致。地区化数字、月份名称及任意日期格式不在当前范围。

固定宽度使用 1–4095 个严格递增的整数位置，范围为 1–65534；`breaks: [3,7]` 依次取宽 3、宽 4 和余下文字，始终输出三列。宽度复用 Unicode 16 的 W/F 两列、其余默认一列及默认可忽略字符零列的顺序；不是字体像素宽度。沿现有字素分段整体推进，宽字符或组合簇跨过指定位置时整体留在当前段，不拆代理对或字素；随后按下一段宽度继续。忽略簇附在前段末尾，短行补空。每段仅裁掉尾部 ASCII 空格，再移除成对外层双引号；内部引号、分隔符及前导空格保持。固定模式不执行分隔符引号解析。默认面板提供方式切换及位置输入；无效位置阻止预览，修改方式或位置会清除旧预览和覆盖确认。

原源列之外的非空目标值或公式计入覆盖数量，仅带格式的空单元格不计入。核心重算方案并复核 sourceRevision；需要覆盖时，只有 `overwrite=true` 才提交。默认面板先显示输出矩形、数量和前十行，再要求勾选覆盖并明确提交。设置、选区、表、文档或修订变化使旧预览失效。目标写入、日期样式及首次样式部件、公式依赖缓存、验证及自动适配共用已有单元格事务和一次精确历史；无实际变化不新增历史。保存重开与静态 PDF 使用同一结果。

源最多 4096 行，原始字段矩形和实际输出矩形均最多 4096 格，实际输出不能越过 XFD 列；输入累计最多 1 Mi UTF-16，每格最多 32767 单元，并受原包、XML、输出和 4 MiB 历史预算约束。分隔符模式的错误引号、非法固定位置、合并格、富文本等既有只读单元格、工作表保护、不透明公式/元数据或验证失败原子拒绝。CSV/TSV 文件导入仍只接受逗号或制表符，原转换选项保持。更广地区化转换和格式组合继续实施。

功能入口参考 GenOffice 单列分列操作，编辑值与文本粘贴事务参考固定 [ONLYOFFICE asc_TextToColumns](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/api.js#L846-L902)及 [getRangeText](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L23563-L23594)。固定宽度参考 [LibreOffice 列宽推进](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/ui/docshell/impex.cxx#L529-L557)、[段落提取](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/ui/docshell/impex.cxx#L1490-L1534)及[分列事务](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/ui/docshell/impex.cxx#L1641-L1689)，补齐字素完整性。本实现默认保留文字，转换需要明确选择，不声称覆盖完整文本导入向导；未复制上游源码。实现归 [`text-columns.mbt`](../../../modules/formats/src/xlsx/text-columns.mbt)、[`text-columns-convert.mbt`](../../../modules/formats/src/xlsx/text-columns-convert.mbt)、[`text-columns-fixed.mbt`](../../../modules/formats/src/xlsx/text-columns-fixed.mbt)、既有 [`delimited.mbt`](../../../modules/formats/src/xlsx/delimited.mbt)和 [`xlsx-text-columns.tsx`](../../../packages/xlsx/src/react/xlsx-text-columns.tsx)。

### 删除重复行

已识别迷你图的普通区域与原生表去重沿同一预览和事务执行。移除原始重复行内的图形，幸存图形保留坐标和数据源；具体归属见[单元格迷你图](xlsx-objects.md#单元格迷你图)。

`XlsxSession/Client.execute({ operation: "duplicatesXlsx", revision, sheet, settings })` 返回只读预览，宿主入口为 `SpreadsheetEditor.data.duplicates(settings)`。`XlsxDuplicateSettings` 包含显式 A1 矩形 `range`、`header` 和工作表从 1 开始的比较列 `columns`；至少选一列，各列互异且在有效范围内。普通区域的 `header=true` 保留首行。返回 `XlsxDuplicates`，包含有效设置、`totalRow`、revision、sheet、完整 `keptRows/removedRows`、有效结果 `resultRange` 及前十条保留记录的格式化值 `preview`。`totalRow` 表示不参加比较的原生总计行，普通区域为 false。两个类型从 Wasm/Web XLSX 模块导出。核心预览不修改源、选择、修订或历史；宿主沿既有队列先处理原生草稿和组合输入。

提交使用 `editSheet({ action: "removeDuplicates", settings, sourceRevision })`。默认面板先选择比较列和标题，再预览删除数量、原行号及保留内容，最后明确提交。设置、选区、表或修订变化后旧预览不能提交；换文档须丢弃旧结果。核心重新计算方案并核对 sourceRevision，不信任传入的删除行列表。无重复或候选源没有实际变化时不新增历史。

比较使用当前已计算结果和格式化文字，区分大小写及空格；显示相同的数字与文字可匹配，不因底层类型不同而保留两份。保留首次出现的记录，包含手动隐藏行。存活单元格按原顺序向区域顶部压紧，移动值、富文本源、有效格式及相对公式；绝对引用和区域外引用坐标保持，依赖缓存同步重算。清空尾部内容及显式单元格格式，行列继承格式仍有效，不删除整张表的物理行，也不移动选区外单元格。手动尺寸和隐藏状态保留原坐标，自动尺寸沿现有路径重排。条件格式、验证及名称保留坐标，候选输入继续校验。

单格链接和便笺随保留记录移动。删除重复记录时，同步移除对应便笺/VML 和完整落在该选区删除行内的链接；跨行链接保持原坐标。其他部件及源片段保留，值、公式、样式、链接、便笺和缓存合为一次精确历史；撤销、重开后输入、查找替换及 PDF 沿相同内容路径。有效范围一次最多 4096 格，格式化及条件计算共享 1048576 工作预算，搬移片段累计最多 1 Mi UTF-16，继续遵守输出和 4 MiB 历史上限。合并格、跨表边界、透视、绘图、未知排序/便笺及单元格/公式元数据等沿重排保护原子拒绝；这些组合继续实施。

已有普通值/自定义筛选时，去重比较仍包含筛选隐藏行，保留首条记录。筛选范围、条件和已知按钮标记保留；按压紧后的当前公式结果重新应用条件，重写筛选隐藏来源和实际行可见性，手动隐藏继续保留原行号。SUBTOTAL 及依赖缓存随可见性一起重算。整个过程只有一次历史；重开后清除条件仍只恢复筛选隐藏行。未知筛选条件或不透明源原子拒绝，导入隐藏来源的歧义沿[值筛选](#值筛选)处理。

选区完整位于一张原生表时，核心将有效范围扩展为整表。`header` 取原生设置，比较列可选整表中的任意列。标题和总计不参加比较，预览的 `range` 和 `resultRange` 包含它们。默认面板显示整表范围并锁定标题开关。删除后保留表/列身份、计算列模板、存活例外和样式，范围按删除数缩小；总计文字、公式和格式迁至新末行，公式沿范围调整规则保持原文。根及筛选内的已知排序范围同步裁剪，保留历史设置，不重新排序。表外普通区域也可去重，保留原生表范围，并重新计算依赖该区域的原生与普通筛选。多来源可见性、手动隐藏、依赖缓存及源变化共用一次历史；没有标题或筛选的表沿相同路径处理。

比较和稳定压紧依据 [ONLYOFFICE setRemoveDuplicates](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L25977-L26181)、[清空单元格](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21142-L21166)及前述 `_sortByArray`；未复制上游源码。实现归 [`duplicates.mbt`](../../../modules/formats/src/xlsx/duplicates.mbt)、[`reorder-cells.mbt`](../../../modules/formats/src/xlsx/reorder-cells.mbt)及 [`xlsx-duplicates.tsx`](../../../packages/xlsx/src/react/xlsx-duplicates.tsx)。更多数据工具兼容归 [P14](../roadmap.md#p14-兼容与性能已完成)。

### 值筛选

`editSheet({ action: "filter", range, columns })` 设置普通工作表的值、日期组、跨年日期、相对日期、自定义、数值排名、平均值、颜色或图标筛选。`range` 是含标题首行、至少一行数据且最多 4096 格的 A1 矩形。`columns` 最多含 256 个互异的 值条件 `{ kind: "values", column, values, blank }` 、自定义条件 `{ kind: "custom", column, conditions, all }` 、排名条件 `{ kind: "rank", column, value, top, percent }` 、平均值条件 `{ kind: "average", column, above }` 、日期组条件 `{ kind: "dates", column, groups, values, blank }` 、跨年日期条件 `{ kind: "calendar", column, unit, value }` 、相对日期条件 `{ kind: "relativeDate", column, period }` 、颜色条件 `{ kind: "color", column, cellColor, color }` 或图标条件 `{ kind: "icon", column, iconSet, iconId }`；`column` 是范围内从 1 开始的工作表列号，`values` 是最多 4096 项互异文字，`blank` 显式决定空白是否通过。各列取交集，同列文字取并集；空条件数组显示全部数据并保留筛选范围。文字按当前已计算值和已支持的有效格式（含条件格式）显示，去除两端空白后使用固定 Unicode 16 小写映射匹配；不改变单元格类型、值、样式、公式或记录位置。未计算公式不使用导入缓存代替。普通文字匹配参考 [ONLYOFFICE Filters.isHideValue](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L10785-L10805)和 [AutoFilter.setRowHidden](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L9585-L9640)。日期组、跨年日期、颜色、数值排名与平均值条件见下文；高级筛选继续保护。

自定义筛选的 `conditions` 含一至两个 `{ operator, value }`，`all` 为 `true` 时取 AND，`false` 时取 OR。`operator` 接受标准 `equal/notEqual/greaterThan/greaterThanOrEqual/lessThan/lessThanOrEqual`，`value` 为最多 32767 单元的文字。有限数字文字按当前数值比较，包含可转换的数值文字单元格，不使用四舍五入后的显示值或导入公式缓存；空白不当作零。其他条件按去除两端空白和相同大小写映射后的标签比较，数值单元格不参与文字匹配；等于/不等于支持 `*`、`?` 和 `~` 转义，`?` 对应一个 UTF-16 单元。空文字等于可匹配空白/公式空串。比较符必须放在 `operator`，条件值内的 `<`/`>` 不被重新解析。自定义日期比较使用数值序号；日历前缀使用下节日期组，本地化解析继续实施。双条件和数值/文字分流参考 [ONLYOFFICE CustomFilters/CustomFilter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L11130-L11456)，文字/通配符复用已有有界条件匹配。

GenOffice 的“高级筛选”入口使用上述同列最多两个自定义条件和 AND/OR，当前 API 与默认自定义面板已覆盖这一入口。条件区域式高级筛选仍按 P11 计划实施；二者不另建相同的条件模型。

同一列仅有一类条件，值、日期组、跨年日期、相对日期、自定义、排名、平均值和颜色面板相互替换，其他列保留并继续取交集。`query.filter.columns` 返回相同带 `kind` 的联合类型；日期组、跨年日期、相对日期、自定义、排名、平均值和颜色列的值目录不投影条件结果，值选择初始为全部，应用后切换为值条件。默认面板支持比较符、条件值、第二条件及 AND/OR。MoonBit 使用 `FilterColumn { column, rule }` 和 `FilterRule::Values/Dates/Calendar/Relative/Custom/Rank/Average/Color/ColorStyle`；Wasm/Web 另导出 `XlsxFilterColumn/XlsxCustomFilter/XlsxFilterCondition/XlsxFilterOperator`。

`filterClear` 清除全部条件并保留范围，`filterRemove` 同时移除范围，`filterReapply` 按当前值重新应用。原生输入先按原队列提交；普通编辑保留现有隐藏结果，由重新应用更新。每项使用已有 revision 和单项源历史，保持选择；相同结果不新增历史。网格、自动尺寸及 PDF 共用核心隐藏行。`query.filter` 提供 `range/columns/reason` 和逐列 `catalog`；每列返回 `column/title/blank/blankSelected` 及 `{ value, count, selected }` 选项，按归一化值合并大小写，保留当前条件中的零计数值。默认面板使用当前选区创建范围，选择列和值、空白，并提供清除、移除和重新应用。Wasm/Web 导出 `XlsxFilterSettings/XlsxFilterValues/XlsxFilterState`。

保存使用标准 `autoFilter/filterColumn/filters/filter` 或 `customFilters/customFilter`（`and` 与 `operator/val`）、`sheetPr.filterMode` 和行 `hidden`。行高、原属性与非目标部件保留。`autoFilter/extLst` 内的 `urn:open-document:xlsx:filter-state` 扩展记录 `manual` 与 `filtered` 行号，可同时包含同一行；清除筛选只恢复筛选隐藏，手动隐藏继续保留。已有行高/隐藏命令同步手动来源，正行高也不能展开仍被筛选隐藏的行。复制、改名、撤销重做和保存重开保留此来源；扩展与实际隐藏行不一致时拒绝编辑。外部文件只有一个 `hidden` 字段，无法判断同一行是否同时被手动和筛选隐藏；无来源扩展时，将不匹配条件的隐藏行视为筛选隐藏，其余视为手动隐藏。外部程序若丢弃扩展，也会恢复此导入限制。

每项匹配/目录共用 1048576 次公式工作预算，条件文字累计最多 1048576 个 UTF-16 单元，目录数据/标题累计最多 1048576 个单元；继续受包、源和 4 MiB 历史预算约束。未知条件、日历声明、扩展、属性、筛选内注释/处理指令、工作表保护或无法计算的显示值拒绝修改，保留源与历史。保留已知 `hiddenButton/showButton` 标记。已支持条件的排序和整行/整列插删复用候选重算与隐藏来源事务，局部单元格移位仍保护；原生表筛选归[结构化表](xlsx-calculation.md#结构化表与引用)；其余交互及复杂组合按 [P14](../roadmap.md#p14-兼容与性能已完成) 扩展。实现归 [`filter-model.mbt`](../../../modules/formats/src/xlsx/filter-model.mbt)、[`filter-values.mbt`](../../../modules/formats/src/xlsx/filter-values.mbt)、[`filter-custom.mbt`](../../../modules/formats/src/xlsx/filter-custom.mbt)、[`filter-source.mbt`](../../../modules/formats/src/xlsx/filter-source.mbt)、[`filter-edit.mbt`](../../../modules/formats/src/xlsx/filter-edit.mbt)及 [`xlsx-filter.tsx`](../../../packages/xlsx/src/react/xlsx-filter.tsx)。

### 跨年日期筛选

Wasm/Web 导出 `XlsxCalendarFilter`，使用 `{ kind: "calendar", column, unit, value }`。`unit` 接受 `month` 或 `quarter`，`value` 分别为 1–12 月或 1–4 季度，匹配所有年份。普通区域与原生表共用条件、默认控件、同列替换和其他列交集。

核心按当前数值的日期序号匹配月份，使用工作簿的 1900/1904 系统，保留 1900 年虚构闰日。显示格式不影响结果；普通数值和时间小数也按日期序号解释，文字、布尔、错误、空白及日历范围外数值不匹配。公式使用当前计算值，不读取过期缓存。输入后沿原筛选规则保留隐藏结果，显式重新应用再更新。手动隐藏、SUBTOTAL、整行/列结构维护、精确历史及保存重开复用已有事务和工作预算。

源写为标准 `dynamicFilter type="M1"… "M12"` 或 `"Q1"… "Q4"`。导入查询保留原源和按钮标记；有限 `val/maxVal` 缓存只作源校验，重新应用按当前值计算。未知类型、属性和子节点继续保护。依赖当前日期的条件归[相对日期筛选](#相对日期筛选)。月份与季度边界参考 [ONLYOFFICE DynamicFilter.isHideValue](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L11896-L11990)，原生类型名归同文件的 `ToXml_ST_DynamicFilterType`。实现归 [`filter-calendar.mbt`](../../../modules/formats/src/xlsx/filter-calendar.mbt)和 [`xlsx-date-filter.tsx`](../../../packages/xlsx/src/react/xlsx-date-filter.tsx)。

### 相对日期筛选

Wasm/Web 导出 `XlsxRelativeDateFilter`，条件为 `{ kind: "relativeDate", column, period }`。`period` 接受 `yesterday/today/tomorrow`、`lastWeek/thisWeek/nextWeek`、`lastMonth/thisMonth/nextMonth`、`lastQuarter/thisQuarter/nextQuarter`、`lastYear/thisYear/nextYear` 和 `yearToDate`，可从 `xlsxRelativeDatePeriods` 读取目录。默认面板提供对应的中英文期间。

宿主只提供本地公历日期 `YYYY-MM-DD`，核心沿工作簿 1900/1904 系统计算起止序号。周从星期日开始；日、周、月、季度和年使用完整日历边界，年初至今包含今天。起点包含，终点不包含，数值按日期序号匹配，类型规则与[跨年日期](#跨年日期筛选)一致。普通区域与原生表共用多列交集、手动隐藏、SUBTOTAL、重新应用和源历史。

同步 `XlsxSession.execute` 和 Worker `XlsxClient.execute` 的 `createXlsx/openXlsx/editXlsxSheet` 命令可显式传入 `date` 日期文字，默认由 `spreadsheetDate()` 取得本地今天；无时区转换或计时器。Worker 协议随创建、打开和工作表命令发送 `date`。MoonBit 对应方法接受可省略的 `date=Some("2024-02-29")`，相对条件使用 `Relative(period, cache)`；新条件传 `None`，缓存为可选的序号起止二元组。成功的命令日期留在会话中，供后续相对日期条件格式和计算使用；失败恢复原日期，并保留原源和历史。日期变化使网格缓存失效，自身不改变源、revision 或文档历史。核心不自动读取系统日期或启动计时器。范围与原生表的筛选仍按下面的显式重新应用规则更新。实现归 [sheet-date.mbt](../../../modules/formats/src/xlsx/sheet-date.mbt)。

保存使用标准 `dynamicFilter type/val/maxVal`。查询和重开保留原窗口、隐藏行和源；跨日、普通输入或撤销重做不自动重新筛选。显式应用或重新应用按当日计算窗口，并与隐藏来源及缓存合为一次精确历史。原生导入按保存的窗口推断未记录的隐藏来源，随后重新应用才采用新日期，避免将昨日筛选隐藏误作手动隐藏。两个缓存都缺省时，计算使用显式会话日期；缺少日期时拒绝需要计算的操作。单边、非有限或倒置缓存及未知期间、属性和子节点继续保护。

区间名称、星期日起始和边界参考 [ONLYOFFICE DynamicFilter.init 的 referenceValues](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L11673-L11700)，匹配沿该文件的 `DynamicFilter.isHideValue`。完整期间按其参考边界构造，不沿用 `_calcDateInterval` 中额外加一的日/月/年终点。实现归 [`filter-relative.mbt`](../../../modules/formats/src/xlsx/filter-relative.mbt)、[`xlsx-filter.ts`](../../../packages/xlsx/src/core/xlsx-filter.ts)及[默认日期控件](../../../packages/xlsx/src/react/xlsx-date-filter.tsx)。

### 颜色筛选

Wasm/Web 导出 `XlsxColorFilter`，使用 `{ kind: "color", column, cellColor, color }`。`cellColor=true` 比较填充，false 比较字体色；`color` 接受六位 RGB（不带 `#`，忽略大小写）或 null。null 分别表示无填充或自动黑色字体；查询将黑色字体归一化为 `000000`。无填充与白色填充不同。普通区域与原生表使用同一条件和默认面板，替换同列条件并保留其他列交集。

核心比较直接、表样式及条件格式叠加后的当前有效颜色，包含有格式的空白格。手动隐藏、SUBTOTAL、重新应用、结构变换、源历史与输出预算复用既有筛选事务；修改颜色后须显式重新应用。标准 `colorFilter` 保存 `dxfId/cellColor`；比较色沿共享差异样式池写入填充字段，字体模式也如此。导入的字体字段可读取；相同颜色重新设置保留已有样式引用和主题关联。未知样式和超限输入原子拒绝。图标与高级条件仍待实现。

普通行内及共享富文本按任一文字段的颜色匹配，字体色排序使用同一规则。显式 RGB、主题/索引色、明暗变换及自动黑色沿既有解析；缺省颜色继承当前单元格的有效字体色，包含条件格式。共享字符串的比较色集合按身份复用，继承色仍逐格求值，不能固化为第一个引用格的颜色。排序保留文字段及共享字符串源，富文本的文字修改继续只读；相邻普通格仍可原生输入。

基本文字段的字体、字号、粗斜体、颜色、单下划线、删除线和上下标已进入共同排版，预览、静态 PDF、自动行高及列宽使用相同文字段。空文字段的大字号也参与行高；同文异字号的格重排后，自动尺寸随文字段源重新测量。字体资源由原有 `probe/profile` 提供，重开后沿既有规则重新绑定。文字块保留完整绘制指令，页眉页脚和 PDF 表单沿相同坐标变换消费。双线及会计下划线、未知文字段或注音保留源并给出诊断，受影响的自动测量及输出继续保护。颜色归 [`rich-colors.mbt`](../../../modules/formats/src/xlsx/rich-colors.mbt)，文字段归 [`rich-layout.mbt`](../../../modules/formats/src/xlsx/rich-layout.mbt)，共同块排版归 [`positioned.mbt`](../../../modules/layout/src/positioned.mbt)。任一文字段匹配参考 [ONLYOFFICE ColorFilter.isHideValue](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L12110-L12185)与 [colorFillCmp](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21522-L21538)；未复制上游可执行代码。

比较及存储参考 [ONLYOFFICE ColorFilter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L12110-L12260)，未复制上游源码。实现归 [`filter-color.mbt`](../../../modules/formats/src/xlsx/filter-color.mbt)、已有颜色排序的 [`sort-color.mbt`](../../../modules/formats/src/xlsx/sort-color.mbt)及 [`xlsx-color-filter.tsx`](../../../packages/xlsx/src/react/xlsx-color-filter.tsx)。

### 图标筛选

Wasm/Web 导出 `XlsxIconFilter`，使用 `{ kind: "icon", column, iconSet, iconId }`，沿普通区域与原生表的现有筛选命令替换同列条件。`iconSet` 使用已支持的 17 种标准名称，`iconId` 是从零开始的实际图案索引；`null` 匹配没有图标的格。默认面板按一开始显示编号，切换级数时裁到有效范围，并提供无图标开关。边界拒绝未知名称、越界索引、缺少字段及混合条件。

核心与[图标排序](#区域排序)共用实际显示图案的匹配，保留反转、规则优先级、停止规则、当前公式及文字/空白语义。各列取交集，手动隐藏和其他筛选来源分别保留；SUBTOTAL、整行插删、精确历史与重开沿既有事务。输入后保留现有隐藏结果，显式重新应用再按当前图案筛选。规则、原样式和数据坐标不变，不新增差异样式。

标准 `iconFilter` 写 `iconSet` 和有值的 `iconId`；无图标条件省略 `iconId`。该语义依据 [OOXML IconFilter](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.iconfilter?view=openxml-3.0.1)；已检查的 ONLYOFFICE `WorkbookElems.js` 图标筛选字段仍标为待实现，因此复用本项目现有图案求值与筛选事务。未知属性、子节点和自定义 x14 图标继续保护，未复制上游源码。实现归 [`conditional-icon.mbt`](../../../modules/formats/src/xlsx/conditional-icon.mbt)、[`filter-values.mbt`](../../../modules/formats/src/xlsx/filter-values.mbt)及 [`xlsx-icon-filter.tsx`](../../../packages/xlsx/src/react/xlsx-icon-filter.tsx)。

### 日期组筛选

Wasm/Web 导出 `XlsxDateFilter`，使用 `{ kind: "dates", column, groups, values, blank }`，沿既有 `editSheet({ action: "filter", range, columns })` 替换同列条件。`groups` 是至少一项的日历前缀：`YYYY`、`YYYY-MM`、`YYYY-MM-DD`、`YYYY-MM-DDTHH`、`YYYY-MM-DDTHH:mm` 或 `YYYY-MM-DDTHH:mm:ss`，分别匹配整年、月、日、小时、分钟或秒。年为四位 0001–9999，其他分量须补两位；只接受有效日历、24 小时及 0–59 分秒，不接受时区或地区日期文字。普通数字、文字和布尔值等使用 `values` 的既有格式化标签匹配，空白由 `blank` 单独决定。默认面板按行编辑前缀和其他文字，并提供空白开关。

核心只把当前数值和已计算数值公式、且有效格式为日期或日期时间的单元格交给日期组；有效格式包含条件格式。General 数值、日期样式下的文字、布尔和错误、纯时间格式均沿普通标签匹配，不隐式转换为日期。同列日期组和普通标签分别作用于对应类型，各列仍取交集。每组比较 `[起点, 下一组起点)`，时间小数直接使用工作簿序列值，不经过 JavaScript Date、宿主时钟或时区。1900 系统保留序列 60 的虚构 1900-02-29；1904 系统的序列 0 对应 1904-01-01。日期组固定在明确的日历前缀上，不随“今天”变化。

每列日期组与普通标签合计最多 4096 项，分别拒绝完全重复项；跨粒度重叠合法。派生区间先排序合并，再有界二分匹配，沿既有 1048576 个求值步骤和文字预算，不按记录数与日期组数做全交叉扫描。值改变后保留现有隐藏结果，重新应用更新筛选隐藏及 SUBTOTAL 缓存；手动隐藏、源格式、选择、精确历史、整行/整列结构同步、工作表复制/改名和保存重开沿同一事务。错误日历、未知源及输出预算失败均不提交部分结果。

标准 `filters/dateGroupItem` 使用 `dateTimeGrouping` 与对应的 `year/month/day/hour/minute/second` 前缀字段，可与普通 `filter` 和 `blank` 共存。读取不改写源；修改保留筛选按钮、排序状态和隐藏来源。未知粒度、缺少前置字段、多余细分字段、`calendarType` 声明及未知属性/子节点继续保护。相对当前日期的 `dynamicFilter` 归[相对日期筛选](#相对日期筛选)；其他日历和本地化解析仍归 P11 后续范围。读取及区间规则参考 [ONLYOFFICE 的日期分组匹配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L10785-L10835)、[日期类型分流](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/AutoFilters.js#L1288-L1304)及[六种区间构造](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L12769-L12834)。未复制上游源码；实现归 [`filter-date.mbt`](../../../modules/formats/src/xlsx/filter-date.mbt)和 [`xlsx-date-filter.tsx`](../../../packages/xlsx/src/react/xlsx-date-filter.tsx)。

### 数值排名筛选

`XlsxRankFilter` 从 Wasm/Web XLSX 模块导出，使用 `{ kind: "rank", column, value, top, percent }`。`value` 为整数：项数模式 1–500，百分比模式 1–100；`top=true` 取最大值，false 取最小值。它与值/自定义条件共用 `editSheet({ action: "filter", range, columns })`，替换同列条件，保留其他列并取交集。默认面板提供方向、项数/百分比、数量和应用按钮，保存重开后恢复当前设置。

排名只采用标题后、明确范围内的当前数值及已计算数值公式结果，包含手动和筛选隐藏记录。文字形式的数字、布尔、错误及空白不参与；其他列条件不改变排名样本。重复值按记录计数，阈值上的并列项全部保留。百分比先按数值记录数向下取整，至少一项；项数超过记录数时保留全部数值记录，无数值时全部数据行不匹配。标题与范围外的数字不参与。原生编辑保留现有可见性，使用重新应用按当前值计算阈值；手动隐藏继续保留，SUBTOTAL 的 9/109 及依赖缓存与筛选共享一次历史。

标准 `top10` 的 `val/top/percent` 已接通读取与写回，缺省 top=true、percent=false；已知有限 `filterVal` 可读取，重新应用按当前数值计算，不信任导入阈值。写回保留设置和实际可见行，不持久化派生阈值缓存。采用 [ONLYOFFICE Top10 的方向、百分比与标准字段](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L12306-L12490)及 [1–500 项交互](https://github.com/ONLYOFFICE/web-apps/blob/9c0ca538c3b211052347df09d2a4d6781f023403/apps/spreadsheeteditor/main/app/view/AutoFilterDialog.js)。已检查的 ONLYOFFICE 分支使用 parseFloat 和去重集合；本实现沿已有类型模型只接受数值，并按 [LibreOffice TopTenQuery 的数值记录和包含边界](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/data/table3.cxx#L2487-L2545)保留重复记录，避免将数字文字或不同值个数当作记录数。百分比沿 ONLYOFFICE 的统一向下取整规则。未复制上游源码；实现归 [`filter-rank.mbt`](../../../modules/formats/src/xlsx/filter-rank.mbt)。

排名复用当前最多 4096 格、公式工作、输出及历史预算。未知属性/子节点、非法标准参数或非有限缓存值保留原子拒绝；依赖畸形筛选的 SUBTOTAL 也可能在打开时拒绝。工作表复制和改名保留排名条件；整行/整列变换见[行列插入与删除](#行列插入与删除)，局部单元格移位仍受保护。图标与高级筛选继续实施。

### 平均值筛选

`XlsxAverageFilter` 从 Wasm/Web XLSX 模块导出，使用 `{ kind: "average", column, above }`。`above=true` 严格高于平均值，false 严格低于；等于平均值不通过。沿同一 `editSheet({ action: "filter", range, columns })` 替换同列条件，其他列仍取交集。默认筛选面板提供两个按钮，并显示当前方向。

样本使用标题后、范围内的当前数值和已计算数值公式结果，包含隐藏记录及重复值；文字数字、布尔、错误和空白不参与，也不通过此条件。其他列条件不改变样本。无数值时全部数据行不匹配。原生输入保留现有可见性，重新应用后更新阈值、筛选隐藏及 SUBTOTAL 缓存；手动隐藏、结构变换、复制/改名、精确历史和保存重开复用既有事务。清除条件后，原先隐藏的错误值重新参与普通公式计算。

标准 `dynamicFilter` 的 `aboveAverage/belowAverage` 已接通读取和写回；已知 `val/maxVal` 必须有限，重新应用按当前值计算并移除派生缓存。规则参考 [ONLYOFFICE 平均值计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L11728-L11745)和[严格比较](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L11865-L11871)。上游样本使用 parseFloat；本实现沿排名筛选的已有类型模型只接受数值记录，避免隐式转换文字。复用 4096 格、公式工作、输出及历史上限，非有限平均值、未知属性/子节点和其他动态类型继续原子拒绝。实现归 [`filter-rank.mbt`](../../../modules/formats/src/xlsx/filter-rank.mbt)及既有筛选读写与面板。

### 自动适配尺寸

单元格使用字体 OS/2 的 WinAscent/WinDescent；缺少该表时使用字体边界。上下范围分别按 96 dpi 向上取整，下方包含一个网格像素。完整塑形簇的字宽按同一像素网格取整，供换行、光标、对齐和打印共用；普通文档段落保留原度量，排版缓存区分两种规则。依据 [ONLYOFFICE 单元格字体范围](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/libfont/file.js#L1705-L1722)、[行框](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/StringRender.js#L732-L744)及[塑形簇字宽](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/StringRender.js#L223-L265)。

源 `col.width/defaultColWidth` 已包含留白，换算像素时不再额外加五个像素。缺少默认列宽时，从 `baseColWidth`（缺省 8）计算留白，再向上对齐八像素网格。自动适配与内容导入使用相反换算，保留显式默认宽度。三份固定 Noto 中性文件已核对显式列、默认列及基础列宽。规则归 [ONLYOFFICE 列宽转换](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/cell/model/Workbook.js#L5147-L5160)与[默认打印列宽](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/cell/view/WorksheetView.js#L1076-L1084)。单元格右对齐包含原生网格边缘，不套用对称段落留白。

单元格关闭字偶距与可选连字，保留必需的阿拉伯文塑形。普通段落继续使用自己的文字规则和缓存。依据 [ONLYOFFICE 片段塑形默认值](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/libfont/textshaper.js#L135-L138)，并用原生 PDF 的 `Text` 字形推进核对；Noto 11 pt 的推进为 21.75 pt。

自动列宽先扣除公式视图的列宽倍率，再加入五像素边距。字符数按原生规则保留两位；不足一字符时按比例换算。源宽度写为 1/256 字符单位，沿既有上限和自动增长规则维护。固定 Noto Sans 11 pt 的五组原生 AutoFit 控制覆盖数值、公式视图、普通文字、窄字符及一字符边界。原公式视图现与独立原生的 201 pt 列宽及 `16.75390625` 源宽度相同。实现归 [autofit.mbt](../../../modules/formats/src/xlsx/autofit.mbt)，依据 [ONLYOFFICE AutoFit](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L18321-L18417)及[字符数与源宽度换算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L5014-L5038)。

未固定的默认行高由 Normal 字体计算；`sheetFormatPr.defaultRowHeight` 仅在 `customHeight` 为真时固定默认值。该标记不继承到单行；普通行仍按内容适配，单行的 `customHeight` 才固定该行。未固定的 `ht` 是缓存，首次布局按当前字体重新测量；固定行和隐藏行沿源声明。源行声明及无编辑保存字节保持。11 pt Carlito 的默认行高为 14.25 pt，Noto Sans 为 16.5 pt，均与独立字体范围及原生 PDF 核对。默认值依据 [ONLYOFFICE getDefaultHeight](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L8916-L8923)。实现归 [`cell-metrics.mbt`](../../../modules/formats/src/xlsx/cell-metrics.mbt)与共享文字测量。

同步 Wasm 与 Worker 使用 `autoFit(revision, sheet, first, last, axis, profile)`；`axis` 为 `rows/columns`，索引从 1 开始且包含两端。宿主使用 `SpreadsheetEditor.autoFit(axis)`，作用于执行时选区覆盖的完整行或列，先提交单格草稿。默认尺寸面板提供两个按钮。每项命令独立进入既有历史，保持当前表和选区；重复写入相同源状态不增加 revision。

核心遍历所选轴上实际存在的单元格，使用显示数字格式、已计算值、有效字体与当前列宽测量；不按公式源码长度估算。换行及显式换行沿既有文本布局。行高至少为有效默认值，并包含原生行框的网格像素，上限 409.5 磅；列宽按 Normal 字体最大数字宽度换算，向上取足像素并保留 1/256 单位，上限 255。无可测内容的轴回到默认尺寸。适配后的行高随内容、有效字体/字号、换行、数字格式、合并及列宽变化重算；bestFit 列随数值、布尔、错误及公式结果扩宽，不因值变短缩列，也不因普通文字编辑扩列。自动扩宽复用原有列宽，只重新测量数值、公式结果或有效格式实际变化的格；不因未改动的未知格式重新测量整列。改动未知内容、影响其他行或显式适配时，原有保护继续生效。显式调用仍可重新缩放到当前内容。

多列合并不参与列宽测量，多行合并不参与行高测量；单行横向合并的换行文本使用单行字体高度。行高适配保留隐藏行；隐藏列仍按其底层声明宽度测量换行文本，保留隐藏状态。列宽适配显示目标列。修改保留列样式、轮廓、折叠属性、相邻尺寸、单元格源、样式部件、公式缓存与 calcChain，只提交目标工作表的尺寸片段。行记录写入 `customHeight="0"`，列记录写入 `bestFit="1"`。核心在同一候选事务内先更新依赖数值列，再重算行高；派生尺寸与值、缓存、样式共用一次 revision 和历史，撤销不重新测量。手动设置正行高或正列宽切回固定尺寸，手动隐藏列不被数值更新显示。未固定高度的普通默认行，也在带字体的编辑中重算并写入 `ht`。工作表的固定默认值不固定单行；行的 `customHeight` 独立读取。未绑定字体时，原本不带 `ht` 的行保留自动声明，可继续仅数据编辑和保存；原本缓存 `ht` 的自动行仍须先绑定字体再修改。尚未编辑的导入普通自动行，在首次带字体布局中测量，包含已有缓存 `ht` 的行；网格、命中、图片锚点和打印共用派生高度。此过程不写入 XML、revision 或历史，保存保留原行声明；后续编辑继续沿既有适配事务更新源。

首次行高测量可见的普通自动行，包含实际含格的行及显式声明缓存 `ht` 的行，不展开隐式空行。工作表默认值与单行固定标记分别沿源读取；多行合并不扩展行高。五份固定 Noto 中性文件独立核对短缓存、长缓存、固定工作表默认值、固定行和隐藏行。只读布局复用文字测量，省去仅为写回所需的筛选和扩展资源编辑限制；工作表保护、非文字扩展及其他部件保持。无法测量的未知字符或条件样式保留源高度及既有诊断，缺字体和资源超限明确失败。首次布局沿用 4096 行、4096 次文字格测量、262144 个文本单元和公式工作上限；缓存自动行也计入预算，固定行除外。更大表仍需增量测量能力。查询在存在同 revision、同表的有效网格时报告实际行高，未布局时报告源高度。实现归 [`initial-row-height.mbt`](../../../modules/formats/src/xlsx/initial-row-height.mbt)及既有适配器；默认/缓存/隐藏行行为依据 [ONLYOFFICE 行高读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L2932-L2966)和[测量后更新非固定行](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9860-L9900)。

一次事务累计最多 4096 次轴适配、4096 次单元格测量及 262144 个文本单元，不展开空单元格矩阵。字体缺失、富文本/未知样式、保护、未计算公式、未支持的条件规则、未知筛选/表格/透视及扩展资源继续拒绝，保留包和历史。显式适配、成功的网格布局或打印布局会在会话内保留调用者的字体探针和 profile 副本。探针由调用者持有并须保持可用；重新打开后，影响自动轴的编辑须先完成一次带字体 profile 的布局或适配。缺映射、未知布局或预算失败会拒绝整个候选编辑，保留原值、缓存、样式、尺寸及撤销/重做。默认宿主打开时已完成字体布局。尺寸片段使用原有历史和输出预算。核心已检查换行、大小字体、数字显示、合并、隐藏行及零高行、原列区间属性、Normal 与第 0 个单元格样式分离、精确历史、重开和失败；Chromium 已检查默认按钮、草稿与尺寸分项撤销、独立 XML、同步 Wasm/Worker 结果、保存重开及 PDF。实现依据 [ONLYOFFICE 列宽适配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L18321-L18500)、[行高适配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L18504-L18576)及[合并格行高规则](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9820-L9880)。

自动模式更新依据 [ONLYOFFICE 数值列扩宽](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9558-L9610)及[行高失效与重算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9915-L9975)。核心已检查数值/布尔/错误和跨表依赖结果扩列、短值不缩列、行高增减、改窄列后的换行高度、手动固定覆盖、稀疏目标间未知列声明保留，以及字体/文本预算失败的原子性和重开恢复。Chromium 已检查原生输入自动扩列、一次撤销恢复输入和尺寸，换行输入及列宽变化重算行高，固定行高继续输入保持；沿同一流程保存、重开和导出 PDF。

默认行的带字体编辑已检查原生输入、换行、字号、列宽及固定覆盖，源行高与输入共同进入精确历史；清除内容和格式后空白 Normal 行回到默认高度。列宽修改只更新与实际变化列相交的实际行；合并变化按受影响行区间更新，不展开空单元格。未触及行的只读内容和原 XML 保留。普通值/表达式条件规则已按有效差异样式测量，并在依赖变化时重算受影响自动轴，见[条件格式](xlsx-calculation.md#条件格式)。未支持的效果继续保护。默认行高变化可改变分页；现有原生输入流程已通过独立 XML 核对两条普通行 16.5 pt、双行文字行 33 pt，以及 120 pt 可打印高度下的 6 页预览。

### 合并与取消合并

`editSheet(revision, sheet, { action: "merge", range, discard })` 合并指定矩形；`{ action: "unmerge", range }` 取消相交的合并。`range` 是 A1 矩形，单格地址自动扩展到已有完整合并范围。两种操作一次最多 4096 格，工作表最多保留 1024 个不重叠合并范围；合并须完整包含相交的旧合并。重复合并同一范围和取消未合并范围不增加历史。活动表操作选择目标范围，非活动表操作保留当前选择。

`XlsxQuery.merging` 返回查询范围的 `range`、是否相交合并的 `merged`、非左上角非空格数 `discarded`、会丢弃的额外便笺数 `discardedNotes`，以及 `mergeReason/unmergeReason`。合并只有收到布尔 `discard: true` 才能丢弃非锚点内容或额外便笺；否则以 `merge-data-loss` 拒绝。默认属性栏使用同一复选框确认值/公式或便笺损失，即使单元格值全空也须确认便笺损失；宿主沿现有队列先提交草稿。核心重新检查当前数据和保护状态，失败保留已提交包与历史。

合并保留左上角值/公式和各格非边框格式，清除其余值/公式；共享公式存活成员转换为普通公式，依赖缓存和保存计算元数据同步更新。非锚点验证范围从规则中移除，锚点验证和条件格式保留。单元格与合并 XML、验证和缓存一起提交一项有界历史，保留原样式记录和不相关资源，新增边框样式按需派生并复用。取消合并只移除相交合并记录，保留各格内容/格式及计算源；被此前合并丢弃的内容通过撤销恢复。合并后格式查询、编辑及清除可从单格锚点作用于完整范围。

文字与填充沿用左上角样式；边框组合读取起止格的声明，补齐右边和下边。合并时只保留整条外围上各格一致的线型及颜色声明，缺失或不一致时移除整边；内部边框清除。新边框保留主题色、索引色等源声明，不按当前 RGB 固定化。单行和单列遵循同一规则；合并后设置某侧边框只作用于外围对应边，不在内部加线。各格的字体、填充和数字格式保持不变，原样式记录保留源字节。格式查询、网格和打印使用同一边框组合，读取起止格不展开巨大导入合并区。派生样式仍受每类记录数、样式源码长度和历史预算限制；候选总长度超限时也不清除内容、不提交历史。工作表保护、部分旧合并、未知合并属性、超出预算、富文本/未知目标样式，以及未知便笺、非锚点超链接、表格/透视表和扩展资源拒绝合并；取消合并沿自身保护检查，不清理未知资源。合并格格式刷归[格式刷](#格式刷)。核心已检查内容策略、验证、共享公式、依赖、XML 顺序、纯取消合并的部件保真、精确历史和失败；Chromium 已检查键盘范围、确认控件、合并内命中、填充、保存重开和 PDF。操作依据 [ONLYOFFICE 范围合并与验证调整](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L20316-L20706)；边框归并及外围写回遵循同一上游过程。核心已检查四边、内线、单行/单列、不一致边的移除、主题/索引色源声明、精确历史、重复样式复用及预算失败。Chromium 用独立 XML 检查派生边框和原样式记录，网格及打印绘制数据保持颜色、线宽，保存重开及 PDF 沿已有流程。

网格和打印按相邻可见格的跨度分割共用边。合并格横跨多个相邻格时，各段独立选择线型、颜色和线宽，避免一段的优先级盖掉整边。分段沿既有绘制预算。实现归 [`grid-border.mbt`](../../../modules/formats/src/xlsx/grid-border.mbt)。[ONLYOFFICE 合并格边框绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L7439-L7470)

### 单元格格式编辑

边框交点依据 [ONLYOFFICE 线段端点](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/cell/view/WorksheetView.js#L8039-L8081)。C41 原生 PDF 的 73 条线段已提取，八组粗细交点及横向打印边界逐项核对。共享栅格器将轴向实线的平端点按设备像素取整，六条独立 PDF 线段已核对。XLSX 打印预览复用已有 PDF 栅格模式。固定 Noto 替代下，原件及修改后第一页 Canvas、PDF 均为 0/0；完整六页仍未通过，详见[测试说明](../testing.md#当前兼容证据入口)。

居中单元格及横向合并格的文字原点包含一个网格像素，按 96 dpi 取整；左、右对齐留白保持原规则。RTL 先按逻辑坐标定位，再反射到显示区域。六个固定 Noto 原生坐标已独立核对，源和精确历史保持。依据 [ONLYOFFICE 水平文字位置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L10479-L10499)，实现归 [`cell-text.mbt`](../../../modules/formats/src/xlsx/cell-text.mbt)。

四边支持 `none/thin/medium/thick/double/hair/dotted/dashed/dashDot/dashDotDot/mediumDashed/mediumDashDot/mediumDashDotDot/slantDashDot`。核心统一读取普通样式、条件差异样式和自定义表格样式，沿原有格式、格式刷与片段事务保留源、混合状态和精确历史。`thin/hair/dotted/dashed/dashDot/dashDotDot` 使用 0.75 pt，`medium` 及中等宽度点划线使用 1.5 pt，`thick/double` 使用 2.25 pt；双线保留两条 0.75 pt 细线。四边使用开放线段和平端点，交点按相邻线宽伸缩；共享边沿原有格式优先级选择。打印末列按半边框的整数像素扩展裁剪。虚线和点划线沿原生 dash 数组，Canvas/PDF 共用 point 尺寸，网格线先于所有显式边框绘制。`hair` 和 `slantDashDot` 的线宽与节奏按 [ONLYOFFICE BorderProp](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L3862-L3920) 处理，后者显示为中等宽度点划线；未复制上游执行代码。默认格式、条件格式及自定义表格样式面板共用导出的线型目录。未知线型、对角线和其他未支持属性继续保护，未增加独立渲染或平台排版路径。实现归 [`grid-border.mbt`](../../../modules/formats/src/xlsx/grid-border.mbt)及 [`xlsx-format.ts`](../../../packages/xlsx/src/core/xlsx-format.ts)。

同步 Wasm 与 Worker 使用 `formatCells(revision, patch)`，宿主使用 `SpreadsheetEditor.formatCells(patch)`。命令作用于队列执行时的选区，宿主先提交单格草稿。`XlsxCellFormat` 从 `wasm/xlsx` 和 `web/xlsx` 导出；省略的属性保持原值。字段为 `family`、`size`、`bold`、`italic`、`underline`、`strike`、`script`、`color`、`fill`、`horizontal`、`vertical`、`wrap`、`shrinkToFit`、`indent`、`textRotation`、`numberFormat` 及 `left/right/top/bottom`。`underline` 为单下划线，`strike` 为删除线，均使用布尔值；`script` 为 `baseline | superscript | subscript`。颜色为六位十六进制，空 `fill` 清除填充；四边使用 `{ style, color }`，`style` 为导出的 `xlsxBorderStyles` 标准值。字号为 1–409 磅，水平对齐为 general/left/center/right/justify/centerContinuous/distributed/fill，垂直对齐为 top/center/bottom/justify/distributed；数字格式限下节已有集合。宿主先验证新字体键存在于字体 profile。

`XlsxQuery.formatting` 返回这些属性，不同值返回 `null`，并返回 `readOnlyReason` 和所选字体键 `fontKeys`。一次最多 4096 格；依赖无法隔离的公式、受保护表、富文本/未知样式及只覆盖部分合并格的范围继续保护。单格合并锚点的格式查询和编辑扩展到完整合并范围。空白格继承行样式，其次列样式，再使用基础样式；显式单元格样式优先。派生格式保留原共享记录，不改写其他格。样式和目标格共同提交有界历史，缺失样式部件时关系及内容类型一起创建和撤销。仅改格式保留值、公式源、缓存和 calcChain，后续输入保持格样式；重复设置有效状态不新增历史。格式化的空白格参与使用范围和打印。默认 UI 使用可滚动属性栏，保留网格工作区。单下划线、删除线和上下标沿共同字体度量进入网格、自动适配及 PDF；格式刷、单元格片段和三种清除沿相同样式事务保留或移除。条件格式与自定义表格样式支持这些差异属性，直接字体组件的覆盖规则保持。未知、重复、双线及会计下划线继续诊断并保护编辑和输出。共同读取归 [`font-decorations.mbt`](../../../modules/formats/src/xlsx/font-decorations.mbt)，原生属性依据 [ONLYOFFICE Font 读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L988-L1030)。Chromium 已检查格式设置、草稿顺序、格式刷、装饰绘制、混合历史、缺失字体恢复、保存重开和格式化公式的 PDF 输出；更多装饰和格式代码归 [P14](../roadmap.md#p14-兼容与性能已完成)。

`horizontal: "centerContinuous"` 从非空单元格向右扩展到同一原生样式索引、相同有效对齐的连续显式空单元格，忽略缩进并在整个范围居中。空文字值视为空格，公式保留独立文字源；非空内容、不同样式、缺失格、合并格或行末中断范围。原单元格内容、矩形、命中、选择及合并记录保持。自动行高按整个范围测量换行，自动列宽保留自然文字宽度。滚动与冻结窗格沿既有裁剪绘制；源格在可见片段之外时补绘其文字，隐藏源列不补绘。打印片段使用相同文字坐标，链接边界按片段裁剪。补绘文字源计入 4096 格与文字预算；范围文字宽度不超过 14400 pt。原生 XF/DXF、API、默认控件、格式复制及精确历史沿既有路径维护。实现归 [`alignment-ranges.mbt`](../../../modules/formats/src/xlsx/alignment-ranges.mbt)、[`grid-cells.mbt`](../../../modules/formats/src/xlsx/grid-cells.mbt)和 [`autofit.mbt`](../../../modules/formats/src/xlsx/autofit.mbt)。同一原生样式要求依据 [Apache POI CENTER_SELECTION](https://poi.apache.org/apidocs/3.17/org/apache/poi/ss/usermodel/HorizontalAlignment.html#CENTER_SELECTION)；ONLYOFFICE 和 LibreOffice 的基础读取仅映射普通居中，未作为跨列绘制基线。

`vertical: "justify" | "distributed"` 将自然排版后的剩余高度平均分到各行之间，首末行贴近已有上下内边距。显式空行参与行数，混合字号保留各行自然高度。只有一行时，`justify` 靠上，`distributed` 居中；高度不足时不增加间距，沿原单元格矩形裁剪。两者不改变换行设置、源文字、字号、公式或自动尺寸。绘制和链接边界使用同一逐行偏移，边界不包含额外行间空白。原生 XF/DXF、格式查询、格式刷、单元格片段、默认控件及精确历史共用既有入口。原生值归 [Microsoft 垂直对齐定义](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.verticalalignmentvalues?view=openxml-3.0.1)，多行间距参考 [LibreOffice 垂直行距](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/editeng/source/editeng/impedit3.cxx#L4425-L4475)及 [Excel 行距说明](https://support.microsoft.com/en-us/excel/change-line-spacing)。实现归 [`cell-text.mbt`](../../../modules/formats/src/xlsx/cell-text.mbt)，未复制上游执行代码。

`horizontal: "fill"` 将格式化后的显示值作为整体重复，保留混合字体、装饰及上下文塑形；只添加完整值，首个值超宽时沿原范围裁剪。连续显式空单元格在原生样式索引与有效对齐相同时延续范围，非空内容、公式、缺失格、其他样式及合并格中断延续。跨列范围和范围外源文字补绘复用跨列居中的预算及裁剪，单元格值、公式、选择、命中和合并保持独立。填充忽略缩进并优先于缩小字体适应，保留源字号；开启换行时改用普通类型对齐和换行，不重复。显式多行不重复。自动列宽测量原显示值，自动行高及格式提交检查扩展文字预算，不按重复值撑宽列。扩展沿每块 32767 个 UTF-16 单位/文字片段及现有 262144 单位总预算，文字范围宽度不超过 14400 pt；达到预算而未确定完整边界时拒绝，失败不留下格式或资源变化。原生 XF/DXF、查询、复制、默认控件和精确历史使用原入口；Canvas/PDF 及链接边界使用同一文字坐标。实现归 [`fill-text.mbt`](../../../modules/formats/src/xlsx/fill-text.mbt)、[`alignment-ranges.mbt`](../../../modules/formats/src/xlsx/alignment-ranges.mbt)及 [`grid-cells.mbt`](../../../modules/formats/src/xlsx/grid-cells.mbt)。规则归 [Apache POI FILL](https://poi.apache.org/apidocs/3.17/org/apache/poi/ss/usermodel/HorizontalAlignment.html#FILL)及 [Microsoft 填充对齐](https://learn.microsoft.com/en-us/troubleshoot/microsoft-365-apps/excel/format-cells-settings#alignment-tab)。ONLYOFFICE 的基础读取映射普通两端对齐，重复度量参考 [LibreOffice 完整值重复](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/ui/view/output2.cxx#L1933-L1972)；当前按完整候选实际塑形确定最后一个可放值，未复制上游执行代码。

`horizontal: "distributed"` 对每行的词间空白分配剩余宽度，包括末行和未换行的单行；连续空格合为一个间隙，不拉开词内字母或组合字素。没有可扩展间隙时保留塑形结果并居中，超宽内容沿格裁剪。左右均保留 `indent`，文字区减去两侧缩进。此对齐隐式换行，优先于缩小字体适应；源 `wrapText`、字号、文字、值和公式不变。自动行高按实际换行测量，显式自动列宽测量未扩展的自然宽度并计入两侧缩进。XF/DXF、查询、复制、默认控件及精确历史沿既有路径；Canvas/PDF 与链接边界使用同一逐行坐标。原生词与双侧缩进定义归 [Apache POI DISTRIBUTED](https://poi.apache.org/apidocs/3.17/org/apache/poi/ss/usermodel/HorizontalAlignment.html#DISTRIBUTED)，隐式换行参考 [ONLYOFFICE 分散对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9527-L9530)，末行扩展参考 [LibreOffice 分散末行](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/editeng/source/editeng/impedit3.cxx#L1693-L1700)。实现复用 [`cell-text.mbt`](../../../modules/formats/src/xlsx/cell-text.mbt)、[`positioned.mbt`](../../../modules/layout/src/positioned.mbt)及既有词间距算法，未复制上游执行代码。

`horizontal: "justify"` 按词间空白扩展非末行，连续空格合为一个间隙；不拉开没有空白的字母。末行保持自然宽度，LTR 靠左，RTL 靠右。普通文字、混合字号、装饰、显式换行与自动换行共用核心图元，换行开关仍独立保存；两端对齐忽略缩进。计算不改变源文字、字号、公式或缓存。自动行高保留文字高度，自动列宽使用未扩展词间距的度量。原生 XF/DXF、混合查询、格式刷及单元格片段复用既有事务，Canvas/PDF 使用同一位置，RTL 的打印与链接边界计入行偏移。旋转等仍待实现。实现归 [`cell-text.mbt`](../../../modules/formats/src/xlsx/cell-text.mbt)、[`positioned.mbt`](../../../modules/layout/src/positioned.mbt)和 [`justification.mbt`](../../../modules/layout/src/justification.mbt)，词间距及末行规则依据 [ONLYOFFICE 词间扩展](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/StringRender.js#L1209-L1242)和[末行方向](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/StringRender.js#L1318-L1325)，未复制上游执行代码。

`indent` 为 0–250 的整数，缺省为 0，省略补丁保留原值，显式 0 清除缩进。每级使用 Normal 字体的三个空格；空格宽先按固定 96 dpi 舍入，再换算为磅，不随当前格字号或缩放改变。按有效左/右对齐向格内缩进，General 依类型选择方向，居中不平移。换行按缩进减少可用宽度，数值溢出检查、自动行高、自动列宽及 PDF 复用同一度量。缩进不自动改变水平对齐。原生 `alignment.indent`、混合查询、格式刷、完整格式快照、片段、条件格式与自定义表格样式沿现有事务维护，保留原值、公式和精确历史。相对缩进继续诊断并保护。实现归 [`cell-text.mbt`](../../../modules/formats/src/xlsx/cell-text.mbt)、[`cell-format.mbt`](../../../modules/formats/src/xlsx/cell-format.mbt)和 [`autofit.mbt`](../../../modules/formats/src/xlsx/autofit.mbt)。距离依据 [ONLYOFFICE Normal 空格](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L619-L622)、[文字位置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L6709-L6725)及[换行和度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9642-L9668)，未复制上游执行代码。

`shrinkToFit` 为布尔值，缺省 false；省略保留，显式 false 关闭。换行优先于缩小。核心按实际格宽与缩进测量普通或混合字号文字，以半磅步长缩小各 run，最低 2.5 pt；源字号低于该值时保持，不放大。达到下限仍超宽时沿格边裁剪，数值保留格式化文字，不替换为井号。网格、自动行高及 PDF 复用同一结果；显式自动列宽测量未缩小文字，后续缩小格不自动撑宽 bestFit 列。显示计算不写回字号、值或源，格式补丁、混合查询、格式刷、完整快照、片段及条件/自定义表格样式沿既有精确历史维护。每次缩小最多 16 轮，沿用字体与文字预算；文字旋转见下节。实现归 [`cell-text.mbt`](../../../modules/formats/src/xlsx/cell-text.mbt)及 [`autofit.mbt`](../../../modules/formats/src/xlsx/autofit.mbt)。行为依据 [ONLYOFFICE 字体缩小](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/StringRender.js#L1162-L1185)、[换行优先](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L10161)及[列宽和文字度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9568-L9674)，未复制上游执行代码。

### 单元格文字旋转

`XlsxCellFormat.textRotation` 直接使用 OOXML 整数：0 为水平，1–90 为逆时针角度，91–180 按 `90 − value` 转成顺时针角度，255 为逐字素竖排。省略保留，显式 0 恢复水平。查询返回共同值或 `null`；格式刷、完整格式快照、单元格片段、条件格式和自定义表格样式沿既有源事务保留。默认控件提供水平、正负 45/90 度及竖排预设，API 可写全部有效角度。

核心先用原字体、装饰、混合字号及换行规则测量，再变换整个文字块并按旋转外框对齐。数值沿原格式显示，旋转不改写源字号、内容或公式。缩小字体按投影宽度测量，自动行高/列宽采用旋转后的尺寸；竖排按已有扩展字素边界分行，保留跨 run 的组合字符，General 水平对齐居中。实际文字、裁剪和 PDF 链接使用共同图元与边界，格选择和命中保留原矩形。选中行列超过可用视口时，定位起始边缘，避免顶部文字藏在标题后方。竖排派生文字仍受每块 32767 个 UTF-16 单元预算限制，失败保持源和历史。

实现归 [`text-rotation.mbt`](../../../modules/formats/src/xlsx/text-rotation.mbt)、[`cell-text.mbt`](../../../modules/formats/src/xlsx/cell-text.mbt)及 [`autofit.mbt`](../../../modules/formats/src/xlsx/autofit.mbt)。编码参考 [ONLYOFFICE Align.getAngle](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L5277-L5286)，旋转投影与竖排参考 [WorksheetView](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9556-L9640)及 [StringRender](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/StringRender.js#L974-L1030)。未复制上游执行代码；竖排不等同于东亚竖向字形替换。

### 格式刷

同步 Wasm/Worker 的 `captureFormat(revision)` 返回 `CopiedCellFormat { cells: Required<XlsxCellFormat>[][]; merges: CellRange[] }`；`applyFormat(revision, format)` 将它应用到当前选区。merges 使用相对 cells 左上角的 1 起始行列，包含 top/left/bottom/right；范围须在矩阵内、互不重叠且至少覆盖两格。宿主对应 `SpreadsheetEditor.captureFormat()` 和 `applyFormat(format)`，复制与应用前均提交单格草稿。快照保存逐格有效属性及完整合并范围，不含样式索引或源工作表身份；复制本身不修改文档和历史。MoonBit 的 `apply_format(revision, cells, merges)` 接收同一矩阵和范围。

普通单格目标按源矩形尺寸扩展；选中已有合并格的单格锚点时，源和目标均取完整合并范围。其他目标按源行列顺序重复平铺，格式及合并范围的末块截到目标边界，退化成单格的合并不写入。目标内部的旧合并由快照替换；不含合并的快照会取消目标内部合并。只覆盖部分旧合并时拒绝。格式刷保留包括被合并格遮住的全部值、公式、缓存和共享组；取消合并后仍能读取它们。这与明确丢弃内容的合并命令分别处理。

源和目标各最多 4096 格，矩阵须非空、等宽且携带全部属性；快照及最终工作表各最多 1024 个合并范围。工作表边界、未知属性、字体、只读内容和预算失败均保留已提交文档。格式、合并元数据及已有自动适配合为一次有界历史，重复应用不新增历史；移除最后一个合并时删除空容器。样式复用按元素/属性的命名空间与名称、值及子结构判断，忽略前缀和属性顺序，原有源记录保持原样。实现归[格式快照](../../../modules/formats/src/xlsx/format-painter.mbt)、[合并平铺](../../../modules/formats/src/xlsx/format-merge.mbt)和[格式事务](../../../modules/formats/src/xlsx/format-edit.mbt)。

默认 UI 的格式刷单击后对下一个新选区应用一次；双击或在按钮上按 Shift+Enter 锁定，可连续应用及切换工作表。Esc 或再次点击按钮取消，替换文档时释放状态。复制/平铺参考 [ONLYOFFICE 的目标扩展与格式复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21916-L21960)，合并替换、底层内容保留和末块裁短沿其[格式及合并复制路径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22578-L22616)。单次/锁定/取消参考 [GenOffice 格式刷](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/sheets/src/renderer/format-painter.ts)。

### 清除单元格

同步 Wasm/Worker 使用 `clear(revision, mode = "contents")`，宿主使用 `SpreadsheetEditor.clear(mode = "contents")`。`XlsxClearMode` 从 `wasm/xlsx` 和 `web/xlsx` 导出，取值为 `contents/formats/all`。缺省和原生 Delete/Backspace 保持清除内容；默认 UI 分别提供清除单元格、清除格式和全部清除。宿主先提交单格草稿；输入与清除各占一项历史。

`formats` 将目标格恢复为工作簿内置 Normal 样式，派生或复用 cellXF，保留原共享样式、值、公式、缓存和 calcChain。两种格式清除都会取消完整合并，并从选区清除既有条件格式。`all` 还清除值和公式、选区内验证规则及完整覆盖的超链接；部分覆盖的超链接保持原范围；被清除的共享公式组将存活成员展开为普通公式，并重算受影响依赖。行列尺寸与范围外单元格保持原样，内容变化沿既有保存路径更新计算元数据及共享字符串计数。

一次最多 4096 格，单格合并锚点扩展到完整合并范围。`XlsxQuery.normalFont` 返回 Normal 样式的字体键；宿主在格式清除前检查对应 profile。Normal 不等同于第 0 个 cellXF，也不依赖本地化样式名。未知模式、受保护内容、缺失字体和预算失败不提交清除。部分覆盖的合并、需要平移且无法解析的规则公式，以及未知规则结构继续保护；未支持的非空扩展、表格/透视表资源及未知批注也继续保护；传统便笺的清除归[单元格便笺](xlsx-calculation.md#单元格便笺)，已识别迷你图的清除归[单元格迷你图](xlsx-objects.md#单元格迷你图)。规则之外的资源不推断所有权。

条件格式和验证的 `sqref` 从各原矩形扣除选区，保留不相交区域，最多留下 4096 个矩形。条件格式按范围外接矩形左上角定位，验证按第一个 `sqref` 区域定位；锚点变化时复用核心公式解析器平移相对引用，保持绝对/混合引用、跨表引用和字符串。条件公式、验证的两个公式及公式阈值一并更新，越界引用变为 `#REF!`。锚点不变时保留公式源；清空全部范围才删除规则，验证容器计数同步更新。规则计算、显示与编辑范围分别归[条件格式](xlsx-calculation.md#条件格式)和[数据验证](xlsx-calculation.md#数据验证)。范围扣除参考 [ONLYOFFICE 条件规则清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L13347-L13386)与[验证范围清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/DataValidation.js#L1068-L1088)；验证公式源位置参考 [LibreOffice 导入](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/filter/oox/worksheethelper.cxx#L1096-L1119)。核心已检查四块残留、多个原范围、混合引用、字符串、阈值越界、上限拒绝和精确历史；Chromium 通过默认按钮清除并用独立 XML 检查范围与公式，保存重开后可继续输入。

核心已检查 Normal 派生、取消合并、条件格式/验证/链接清除、共享公式、依赖缓存及精确混合历史；Chromium 已检查原生草稿后清除格式、全部清除、独立 XML、保存重开和 PDF。行为参考 [ONLYOFFICE 范围清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21093-L21175)和[清除选项](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L16669-L16695)。
