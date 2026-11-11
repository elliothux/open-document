# DOCX 表格、列表与剪贴板

[格式合同目录](../formats.md)

### 嵌套表格读取与文字编辑

DOCX Flow 保留内外表层级。`Table.rows` 只含单元格的直属段落；`nestedTables` 记录 `{ row, column, table }`，子表的 `beforeParagraph` 表示它在该单元格直属段落中的位置。按此顺序递归测量、绘制边框及底色，保留实际段落和单元格身份。字体、编号、字段、图片、搜索、光标和标尺读取内层内容；内层普通文字支持原生输入、精确撤销/重做及保存重开。

当前支持最多八层嵌套，以及能完整放入一页的包含嵌套表的行组。固定行高同时裁剪文字、内表底色与边框；超深、无效网格或需要跨页续排的嵌套行拒绝。内表网格修改、跨层范围、整表片段及 HTML/Markdown 输出继续保护，避免丢失内层源。已有普通表格结构操作沿下文合同。实现归 [`table-content.mbt`](../../../modules/layout/src/table-content.mbt)、[`table-nested.mbt`](../../../modules/layout/src/table-nested.mbt) 和 [DOCX 表格读取](../../../modules/formats/src/docx/objects.mbt)。

### 表格创建

`FoundationSession/Client.execute({ operation: "insertTable", revision, selection, rows, columns, profile })` 与 `DocumentEditor.tables.insertTable(rows, columns)` 在正文范围插入固定网格，默认 UI 提供行列输入。rows 为 1–1000，columns 为 1–63，总格数最多 4096，并受 XML、历史和输出预算限制。列宽按插入后目标节的实际起始栏分配整数 twip，余量逐列分配，每列至少 12 pt。沿用当前纸型解释，不改源页面设置。未知或受保护的正文、嵌套表格及无法解释的页面设置拒绝操作。

行、列和网格位置上限由核心定义，构建为 SDK 校验和默认界面生成相同的常量。

单节和多节共用创建、行列增删、合并/取消合并、拆格/拆表、属性、矩形粘贴和单元格片段事务。尺寸查询、跨格行高上限、边距校验和自动适配使用目标节的纸型及栏配置；不等宽分栏根据表格起始位置取宽度。原生节属性保留在正文，复制到单元格的段落格式不含 `sectPr`；跨节删除后，创建宽度按保留节重新计算。其他节与部件保留原源，精确历史及既有保护继续生效。定位与校验归[栏宽读取](../../../modules/formats/src/docx/table-column-width.mbt)、[网格事务](../../../modules/formats/src/docx/table-grid-structure.mbt)及[创建事务](../../../modules/formats/src/docx/table-editing.mbt)。按所属节和页面栏计算表宽的依据见 [ONLYOFFICE 表格创建](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L19763-L19855)，未复制上游执行代码。

核心先删除所选文字；在段中插入时拆分段落，在段首插入时保留原段落作为后续内容。新增表格使用 0.5 pt 黑色完整网格、5.4 pt 水平单元格边距与固定列宽。单元格复制插入起点的有效字符格式及支持的段落属性，并将缩进与段前分页显式归零。若段首已有段前分页，则转移到首格首段，保留表格在该页开始的位置；页首不生成额外空页。其他单元格的段前分页仍受原有布局保护。

范围删除、段落拆分与新增节点共同提交一项历史，选区进入首格。核心失败保留已提交源与历史。保存及混合文字编辑的撤销/重做精确恢复源节点、选择和其他部件。新增格可继续输入、设置已有字符/段落格式及用 Tab 导航。固定及自动适配布局均沿同一表格模型排版。

`FoundationSession/Client.execute({ operation: "editTable", revision, selection, change, profile })` 与 `DocumentEditor.tables.editTable(change)` 接收带 `action` 的对象。行列操作为 `{ action: "rowBefore" | "rowAfter" | "deleteRow" | "columnBefore" | "columnAfter" | "deleteColumn" }`。范围支持单格及下述[同表跨格选择](#跨格行列与矩形合并)，默认 UI 提供同样的六个命令。新增行复制当前行的行/格属性及各格首段格式；新增列复制邻格属性和首段格式，不复制文字，保留格式继承。固定宽表格保持总宽，按原列宽比例缩放为整数 twip；未指定固定宽的网格按插入/删除后的列宽计算。列编辑结果须在可用页宽内，各实际单元格至少 12 pt；重建出的细分网格可更窄。全部命令遵守创建时的行列、格数及资源上限；生成源片段时累计预算，超限即停止。

单格选择时，行操作作用于当前格所在的实际源行。插入位置穿过纵向合并时，新行延续该合并；在合并范围外插入时，新格保持横向跨度并独立。删除起始行会删除该行内容，后续延续格成为新起始格，不转移已删文字；删除延续行保留起始格内容。保留原网格、行属性、宽度偏好及固定/自动适配模式。新增行进入首个非延续格；整行均为延续格时进入覆盖它的起始格。候选源沿现有字体上下文检查可写性、有效宽度和分页，失败保留已提交状态。合并列删除遵循下述整格相交规则。行为依据 [ONLYOFFICE 行插入与删除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9997-L10293)，实现归 [`table-row-edit.mbt`](../../../modules/formats/src/docx/table-row-edit.mbt)及[`共享结构事务`](../../../modules/formats/src/docx/table-grid-structure.mbt)。

左右插列使用所选整格的有效宽度。每行在指定边界相邻的完整单元格前后插入，不切开已有格；各行插入位置可以不同。核心按插入后的实际格边界重建公共网格和 gridSpan，固定宽表格按比例保持总宽。原文字、段落身份和纵向合并归属保留；新格复制右邻格的格/首段格式，行末复制左邻格。新格可延续同一来源的纵向合并，保持空白；dxa/pct 格偏好按有效宽度写为 dxa，auto/nil 保留，整表适配模式不变。未知源、缺字体、格宽不足、分页或预算失败均不提交。依据 [ONLYOFFICE AddTableColumn 与网格重建](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L10516-L10788)及[公共边界计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L15005-L15155)，实现归 [`table-column-insert.mbt`](../../../modules/formats/src/docx/table-column-insert.mbt)。

列删除以当前整格的左右网格边界为范围，删除各行中与范围相交的完整单元格及全部内容。横向合并格不会只缩短跨度。核心按存活格的宽度重建公共网格；固定宽表格保持总宽，auto/nil 偏好保留。空行及修正后全部为纵向延续的行移除；其他纵向延续只能接到同一原始归属和相同边界，不能与无关格合并。删除最后所有格时移除表格并进入正文。依据 [ONLYOFFICE 列选择](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L19140-L19171)与[RemoveTableCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L14338-L14520)，实现归 [`table-column-delete.mbt`](../../../modules/formats/src/docx/table-column-delete.mbt)。

删除后各行可有不同的实际宽度，源 `trPr/gridAfter` 记录行尾空缺。解析、行列维护及拆格同步这些边界；空缺不产生单元格、填充或外框。`gridAfter` 须为 0–63 的整数，实际跨度加空缺必须等于公共网格列数。有效细分网格可小于 6 pt，实际单元格仍须留下文字宽度。当前支持从第 0 列开始的行，非零行首空缺及其余行宽属性仍待实现。未知源和保护内容在删除前检查；候选字体/分页、源、历史及输出预算失败保留已提交状态。

新增列将光标移到新列首行。删除操作将光标移到相邻的剩余行或列；删除最后一行或列时移除表格，进入后续正文段落，必要时创建空段落。首格段前分页随结构转移。末格 Tab 在最后一个实际源行之后新增一行并进入首格，即使最后一格的合并起始点位于前行，Shift+Tab 在首格保持原位。每次结构操作与新增身份、列宽及选择合为一次历史，保留未删文字与其他部件，支持保存重开和精确混合撤销/重做。未知结构、锚点、受保护内容或预算失败原子拒绝。行为依据 [ONLYOFFICE 行列操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9997-L10788)和[固定宽网格缩放](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L414-L425)。

`{ action: "merge", rows, columns }` 从当前格的左上网格位置合并指定矩形。范围为 1–1000 行、1–63 列且最多 4096 个网格位置，不能切开已有合并格。内容按行优先顺序进入左上格，保留段落、字符格式和空段落；列网格不变，更新格宽、gridSpan 与 vMerge。`{ action: "unmerge" }` 取消当前格的合并，恢复原网格各列和行，全部内容留在首格，新增格保留相应格式并置空。两者使用同一有界源历史，可与格内输入精确混合撤销，保存后继续编辑。相同合并范围或取消未合并格不新增历史。书签等受保护锚点、未知格属性及输出预算失败原子拒绝。内容顺序参考 [ONLYOFFICE 合并](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9466-L9530)。

`{ action: "splitCell", rows, columns }` 将当前单格或所选各主格分别拆成指定行列，默认 UI 提供同名操作和数量输入。普通格可新增 1–1000 行、1–63 列；纵向合并格的行数须不超过原合并行数，且能整除原行数。`1×1` 不改变源或历史。它与 `unmerge` 不同：列边界按当前有效宽度等分到整数 twip，合并原有边界后细分公共网格；未选格按新增边界更新跨度，保留原内容和横向范围。

跨格操作把各主格的列切点合为一个公共网格，保留全部旧边界。同一源行中的普通格共享新增行，不按目标格重复追加。纵向合并仍按原源行组分区；相邻普通格增行时，在对应组中加入延续格，保持请求的逻辑拆分行数。所有目标合为一项源事务，光标进入首个主格；1×1 保留整个原范围及 revision。

普通格新增行时复制原行属性，邻格通过纵向合并保持原内容和范围。原段落内容全部留在左上格；新格为空并复制相应格/首段格式。保留原段落身份、非目标内容和其他部件，光标进入左上格。dxa/pct 宽度偏好按列数分配并保持总量，auto/nil 保留；邻格的宽度偏好和整表固定/自动适配模式不变。

结果仍须满足最多 1000 行、63 个公共网格列和 4096 个网格位置，新增源、历史及输出受既有预算约束。核心使用字体 profile 先检查候选格内宽度与分页，边距不足、未知格/行属性、保留的属性注释、缺字体或预算失败时原子拒绝。操作与选择合为一次精确历史，可与文字输入混合撤销、保存重开并沿同一布局输出 PDF。当前合并行组仍须能完整放入一页。算法依据 [ONLYOFFICE SplitTableCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9609-L10001)，实现归 [`table-cell-split.mbt`](../../../modules/formats/src/docx/table-cell-split.mbt)。

`{ action: "splitTable" }` 在所选单元格所在行之前拆分正文表格，两表之间插入空正文段落，光标进入下表首格。首行、缺少段落的单元格、嵌套/受保护表格、未知结构及预算失败拒绝操作。两表保留列网格、宽度、边框、样式和单元格内容；原有行和未替换内容的身份保持。纵向合并跨越分界线时，内容留在上表，下表从对应位置创建空的合并起始格，复制原合并格格式并清除段前分页；后续延续格继续归属下表。分界、空格及选择一次提交历史，支持原样撤销、保存重开、继续输入及同布局 PDF。默认 UI 使用同一操作。拆表与跨度清理参考 [LibreOffice SplitTable](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/source/core/docnode/ndtbl.cxx#L3392-L3515)及[纵向跨度清理](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/source/core/table/swnewtable.cxx#L2021-L2110)。

布局读取横向跨度及纵向起始/延续格，文字、背景和边框使用合并后的矩形；Tab 跳过纵向延续格。纵向合并格可跨源行与页面继续，保持起始格的内容归属、底色、边框与逻辑位置。普通行已支持[逐格跨页](#表格行跨页)，重复表头见[当前合同](#重复表头)。包含可见内容的纵向延续格明确拒绝，避免隐藏其文字。含合并格的行增删遵循上述规则；列删除按所选整格的横向范围移除相交格。默认 UI 提供从当前格指定行列数量的合并，以及单格或跨格取消合并；鼠标属性选择归[跨单元格属性选择](#跨单元格属性选择)，已支持的范围编辑归[跨单元格属性选择](#跨单元格属性选择)，其他兼容归 [P14](../roadmap.md#p14-兼容与性能已完成)。

### 跨单元格属性选择

鼠标拖动或 Shift 扩选的两个端点位于同一受支持表格的不同格时，核心按端点的逻辑网格范围选择相交整格。横向跨度与纵向合并属于同一格；修改同步全部纵向延续节点。`EditState.formatting.cellSelection` 返回表身份、半开行列边界、实际格数、底色和垂直对齐的共同值或混合值。`value.margins` 的 `top/right/bottom/left` 分别返回有效边距的 `{ kind: "value", value }` 或 `{ kind: "mixed" }`，数值单位为 point，包含样式、整表及单格覆盖。无跨格范围时 `value` 为 null，保护失败另给 `reason`。同格内仍使用普通文字选区。

默认表格面板显示所选格数，提供批量底色、清除、顶部/居中/底部对齐与恢复继承。四边边距复用单格及整表的表单，各边分别显示共同数值或留空并提示混合；填齐四边后使用既有 `cellMargins` 命令设置全部所选格。“使用继承边距”移除各目标格的直接覆盖，再按各自样式和整表默认值求有效边距。表单随文档、revision 和原选择重新加载，保留数值校验及选择。混合查询和批量重置依据 [ONLYOFFICE Get_Props](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L472-L494)及[所选格边距修改](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L1094-L1155)。

`value.borders` 按 `top/right/bottom/left` 返回所选主格同名边的共同 `{ kind: "value", value: { style, width, color } }` 或 `{ kind: "mixed" }`。宽度为零仍是共同值；任一合并主格的同一边含不同线段时，该边保持混合。查询沿已有共享边冲突结果，保留单格查询的格式。默认面板复用 [`docx-borders.tsx`](../../../packages/docx/src/react/docx-borders.tsx)，提供单边或各格四边的线型、线宽、RGB、显式移除与恢复继承；范围面板只调用既有 `cellBorders`，整表入口保持独立。每个所选主格的同名边一起修改，不将“各格四边”解释为选区最外框。清除写入无边框覆盖，继承移除指定侧的直接定义；相邻格和表样式仍按[边框冲突规则](#表格边框)求最终线段。源属性和段落不变的范围外格保持。共同/混合比较参考 [ONLYOFFICE 所选格边框查询](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L397-L465)。

[行跨页开关](#表格行跨页)作用于端点覆盖的实际源行，逐行判断无变化。`value.rowSplit` 返回这些行有效设置的共同布尔值或混合状态，默认面板使用半选复选框显示混合值，点击后统一允许拆分，再次点击统一禁止。同一源行的其他格共享此开关，范围外行保持。属性共用候选布局检查、单项历史及输出预算，保留文字、网格、选区和其他部件；支持精确撤销、重做及保存重开。边距面板归 [`docx-margins.tsx`](../../../packages/docx/src/react/docx-margins.tsx)。

核心 `Session.selection_rects(layout, selection)` 从已有 `cellAreas` 返回完整所选格在各页的覆盖框，Wasm 和 Canvas 沿既有选择几何查询显示，不进入 PDF 或原格式。标尺在文字拖动期间保留当前显示，结束后再查询，避免中断鼠标捕获。参考 [ONLYOFFICE 相交格选择及合并归属](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L15872-L15976)，实现归 [`table-range.mbt`](../../../modules/formats/src/docx/table-range.mbt)。

`value.rowHeight` 与 `value.rowHeightRule` 分别返回所选实际源行的共同高度、共同 `atLeast/exact` 模式或混合值。自动高度为 `0/atLeast`。`value.maxRowHeight` 是这些行可统一设置的最小高度上限，单位为 point；核心按纵向合并行组扣除边框、未选行的最小高度和各行边距，不按旧高度逐行独立计算。候选仍须通过整组页面及边距校验。查询不改源或历史。

跨格选择调用既有 `editTable({ action: "rowHeight", value, rule })`，一次修改端点覆盖的实际行及其中未选列的格。单格与跨格共用默认行高表单，混合高度留空、混合模式显示占位，显式填齐后提交。固定值保留完整文字并沿既有规则裁剪；`0/atLeast` 恢复自动。修改保留所有格源内容、跨度、其他行属性、范围外行及原逻辑选择，合为一项精确历史；重复同值不增加历史，任一保护或预算失败整体拒绝。行范围依据 [ONLYOFFICE SetRowHeight](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L19045-L19059)，实现复用 [`table-size.mbt`](../../../modules/formats/src/docx/table-size.mbt)；表单归 [`docx-cell-selection.tsx`](../../../packages/docx/src/react/docx-cell-selection.tsx)。

字符与段落格式、样式应用、格式复制/应用和列表操作使用所选整格内的全部段落，包括空段落；手势端点位于文字中间时也不截断首尾格。有效格式查询沿相同范围返回共同值或混合值。字符与段落格式可合为一项历史，保留原选择端点、非目标格的源片段和其他部件；恢复后可在空段落继续原生输入。普通段落拆分候选继续按候选文档校验，不查询旧源中的新段落。规则参考 [ONLYOFFICE 所选格文字属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L6207-L6263)及[段落对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L7763-L7783)，写回复用既有格式事务。

#### 跨格内容输入与清空

所选整格的非空 `replaceRange` 输入只替换按源顺序的首个所选格，其余格保持原样。LF 在首格内拆段；Enter 先替换首格内容，再沿原有段落/列表规则处理。Delete/Backspace 或空文字替换清空全部所选格，每格留下一个空段落，光标落在首格。行列、合并归属、格属性和非目标格保持；清空后仍可 Tab 导航及原生输入。

每次操作沿现有源补丁合为一项有界历史，撤销恢复全部格和原始选择；单段内容相同或已空单段格清空时只收起选择，不增加 revision 或历史。成对书签随各自格内范围收缩，保留原格归属。组合预览每次从已提交网格和选择重建，取消保留源、选择和重做；提交只替换首格。输入框的无障碍说明报告所选格数。依据 [ONLYOFFICE 所选格删除与输入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L6288-L6335)，实现归 [`table-contents.mbt`](../../../modules/formats/src/docx/table-contents.mbt)。

#### 跨格纯文本剪贴板

`selectedText` 按源顺序读取所选整格的全部文字。格内段落以 LF 分隔并保留空段，同一源行的所选格之间用 Tab，每个所选行末尾保留 LF。合并格的内容只提取一次，纵向延续不重复，也不生成占位字段；段内 Tab 和软换行沿已有纯文本合同保留。正反选结果相同，分隔符全部计入 65536 UTF-16 单元上限。规则参考 [ONLYOFFICE 所选格提取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L7450-L7482)、[所选行末格判断](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableCell.js#L2281-L2304)及[段末分隔](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L3201-L3223)，换行统一为 SDK 已有的 LF。

默认 Copy/Cut 和原生快捷键复用同一入口。核心先完成提取与保护检查；宿主写入成功后核对 revision 和原选择，再沿现有整格清空事务剪切。复制不写历史，剪切合为一项历史，保留表格结构、属性、其他部件和精确撤销。写入拒绝时保留源和选择，沿现有显式恢复入口继续。当前复制仍输出纯文本，格式和表格片段继续实施；含图片或未知内容的跨格范围继续保护。

#### 单元格矩阵粘贴

`editTable({ action: "pasteCells", text })` 和默认“粘贴单元格”按钮显式读取矩形 TSV。Tab 分列，LF 分行，CRLF/CR 统一为 LF；带引号字段支持格内 Tab、换行和双写引号。空字段清空目标格，末尾行分隔不新增一行。各行字段数必须相同。普通原生粘贴继续沿已有文字输入规则处理。

矩阵从当前格或所选范围按源顺序的首个主格写入。矩阵决定写入尺寸，不重复填满或清空选区余下部分。缺少的底部行和右侧列一次补足，保留目标格格式；新格沿现有源模板继承文字和框格式，新行沿表尾行模板。新增列按整数 twip 比例分配当前有效总宽，保留余数；新列和修改后的实际格宽至少 12pt。未改文字、段落身份、表属性和其他部件保持。整个操作只提交一项历史，精确撤销恢复原选择；无变化保留源、选择和 revision。

目标必须是支持的普通格，覆盖任一合并格或缺失源格时整体拒绝。扩列要求源行完整。全表最多 1000 行、63 列、4096 个逻辑格，输入最多 65536 UTF-16 单元。逐格候选重解析累计最多 64 Mi UTF-16 单元，并沿既有源、历史、字体、布局和输出预算原子检查。默认按钮在读取后等待已接受输入，并核对文档、revision、选择和拖动状态；读取拒绝或目标变化保留文档，可重试。

普通纯文本 Copy/Cut 不携带矩形与合并信息，也不转义格内分隔符；含这些内容的结果不能视作可往返的 TSV。需要矩形往返时使用下述显式复制模式。覆盖和自动补足行列的操作依据 [ONLYOFFICE InsertTableContent](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L18018-L18118)。纯文本入口继续保护合并目标；富文本入口见下文。实现归 [`table-paste.mbt`](../../../modules/formats/src/docx/table-paste.mbt)；DOCX/XLSX 共用内部 [`TSV 解析器`](../../../modules/formats/src/internal/delimited/clipboard.mbt)。

#### 单元格矩阵复制与剪切

`DocumentEditor.copy(cut = false, mode?: "cells")` 的显式 `"cells"` 模式对应默认“复制单元格”和“剪切单元格”按钮。核心 `tableClipboard(revision, selection)` 返回 `{ text, selection, fragment, reason }`，查询不改源、选择或历史。`text` 为矩形 TSV，每行以 LF 结束。含 Tab、LF、CR 或双引号的字段用双引号包围，内部引号双写；格内段落和软换行统一为 LF。普通 Copy/Cut 和原生快捷键保持原合同。

矩形覆盖所选主格的完整跨度，TSV 文字只写在各主格左上角。合并覆盖位置、源空缺和边界扩展后未选择的格填空字段；不递归扩大文字选择，也不读取或清空未选择的主格。单格光标或同格文字选择均复制该格全部段落。TSV 不恢复源合并、样式或资源；`fragment` 另携带支持的富文本矩阵。

返回的 `selection` 是剪切清空范围：跨格保留原整格范围，单格扩展至该格全部段落。宿主写入剪贴板成功后，核对编辑器生命周期、原 revision 和选择，再沿既有 `replaceRange` 清空。写入失败或目标变化保留源；清空保留格属性、表结构和精确历史。含图片、字段或其他不支持内容时，在写入前保护拒绝。

矩形最多 4096 个位置，转义与分隔符计入 65536 UTF-16 单元上限。实现归 [`table-clipboard.mbt`](../../../modules/formats/src/docx/table-clipboard.mbt)，字段转义复用既有 XLSX 逻辑。整格内容依据 [ONLYOFFICE 所选格提取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L7450-L7483)，矩形分隔和引号依据 [ONLYOFFICE 工作表文字剪贴板](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/clipboard.js#L1828-L1850)。

#### 单元格富文本片段

支持的普通段落和完整矩形合并生成非空 `fragment`，`reason` 为空。片段由核心生成和解析，宿主将其视作不透明字符串。字符及段落样式解析为直接属性，保留混合字符、空段落、Tab/软换行、自定义制表位、底色、边距、垂直对齐及横纵合并。片段不引用源样式身份，复制后修改或关闭源文档不改变内容。

普通文字链接也随片段复制。核心保留目标、混合字符、提示文字及已支持的链接元数据，不携带源关系 ID。粘贴时在目标文档分配或复用外部链接关系，多条链接一次写入同一部件；相同目标共享关系。内部 `#书签名` 保持名称，须引用目标文档已有书签或同片段内完整复制的书签。链接遵循既有目标和 XML 校验，未知属性、源关系身份及失效书签整体拒绝。完整普通链接可被目标片段覆盖，未覆盖链接和已有关系保持。正文、关系创建及选择共用一次精确历史，失败保留源包及历史。

普通成对书签随完整范围复制，支持点锚点、跨段落/单元格，以及链接中的标记。范围内各段均须被选中；遗漏端点或中间格时只提供 TSV 和原因。片段使用局部身份，粘贴时为新名称分配目标中未占用的 ID；目标已有同名书签时保留原书签，跳过复制的标记，不重命名或覆盖原目标。名称按既有规则忽略大小写比较。书签、文字及资源沿同一历史提交；保存重开后可继续改名、跳转及输入。已有目标格中的书签仍保护覆盖，包括重复粘贴到刚创建书签的格。

普通编号与项目符号携带实际引用的原生定义、级别和重启值。目标重新分配编号及抽象定义身份，共享的源定义仍共享；不接入目标已有列表。标记从所带定义的起点计算，正文不包含伪造的编号文字。主题字体和颜色在复制时解析，段落标记字体保留来源外观。编号部件、关系、内容类型和正文合为一项历史；布局及制表位验证读取候选部件，保存重开后可继续输入和改级别。段落样式产生的不同标记下划线使用独立编号实例和原生级别覆盖，共享同一抽象定义以保持连续计数。起始覆盖只放在每个源实例的第一个样式变体中，避免遇到新样式时再次重启。已有显式级别下划线保持；未知编号资源继续保护。实现归 [`table-fragment-list-instance.mbt`](../../../modules/formats/src/docx/table-fragment-list-instance.mbt)，计数与首遇覆盖依据 [ONLYOFFICE NumberingInfoEngine](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L28785-L28924)。

行内 PNG/JPEG 图片随普通单元格片段复制，保留文字顺序、尺寸、四边裁剪、名称和描述。相同压缩资源共享目标关系，绘图身份分别分配，已有图片身份保留。压缩字节、正文、关系及内容类型合为一次历史，保存时移除片段中的私有载荷。锁定复制、外链图片、未知绘图扩展及浮动图片继续保护。实现归 [`table-fragment-images.mbt`](../../../modules/formats/src/docx/table-fragment-images.mbt)，元数据复制参考 [ONLYOFFICE Image.Copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L162-L200)，未复制上游执行代码。

`FoundationSession.execute({ operation: "tableFragmentImages", revision, fragment })` 和异步 `FoundationClient.tableFragmentImages` 返回 `{ revision, images: [{ key, bytes }] }`，其中 `bytes` 为 `Uint8Array`。查询在副本上校验片段及资源，不改源包、选择和历史。宿主须用 `addImage` 注册 RGBA，Web `editTable` 自动注册后提交核心事务。解码失败保留原文档，沿编辑器既有 `resume()` 路径恢复。

表格、正文和标记图片预检默认返回压缩字节。Web 请求携带 `preparePixels: true`，核心可为受支持的 PNG/JPEG 返回 `rgba: true`、宽高和 RGBA 字节。每次预检的原生 RGBA 合计最多 16 MiB。其余图片由宿主解码后注册。

`editTable({ action: "pasteFragment", fragment })` 从当前主格写入片段矩形。它可替换完全覆盖的目标合并，并补足底部行和右侧列；部分覆盖合并整体拒绝。列宽、行高和表属性沿目标网格，格宽按目标跨度更新。未改格、格间注释和其他部件保留，写入、扩展、选择与精确撤销合为一项历史；不含资源身份时，相同源片段无操作；列表、图片和基础图形片段每次分配独立身份。

简单 `PAGE`、`NUMPAGES` 域可随整格、跨格矩形及完整合并格转移。TSV 使用当前布局的实际值，富文本保留原生指令、显式编号格式和解析后的字符格式。布局要求及缓存规则复用[正文域片段](#正文富文本片段)；MoonBit `table_clipboard` 也接受可选 `layout`，同步及 Worker 桥传入当前布局。粘贴可覆盖目标简单域并扩展网格，只更新新域缓存；已有域缓存保持。域、图片、文字及扩表共用一项精确历史。原生输入、Enter 和组合输入沿所选主格处理，整格删除清空域并保留网格。含简单域段落的普通文字可查找替换；图片和域均占一个逻辑位置。

默认复制及显式“剪切单元格”同时写 `text/plain` 和 Chromium 自定义类型 `web application/x-open-document-docx-cells`。`tableClipboard(revision, selection, cut = false)` 在 `cut=true` 时检查图片和域的完整富文本及原生删除权限，查询保持只读。剪贴板写入成功后，Web 再核对文档、revision、选择和生命周期，沿既有范围删除事务清空所选完整单元格。写入失败不修改源；切出的图片资源仍留在源包，支持精确撤销。底层纯文本 selectedText(cut=true) 继续保护图片和域；默认正文富文本剪切归下节。

默认“粘贴单元格”及 Web foundation 导出的 `pasteDocxCells(editor)` 优先读取片段；只有缺少此类型时读取 TSV。无效片段不回退成文字。读取后核对文档、revision、选择和生命周期，再沿既有编辑队列提交。

富文本范围须包含完整所选矩形，合并边各段须有共同宽度和颜色。复杂列表、不完整或复杂书签、批注身份、复杂域和未知结构的资源转移继续实施；可提取文字但不能生成富文本时返回 `fragment: null` 及具体 `reason`，系统剪贴板保留原 TSV。图片格已有富文本复制和显式剪切。跨格 Delete/Backspace 清空全部所选主格；文字、Enter 和组合输入只替换首个主格，保留其余格图片和域。图片删除锁、引用保护和候选失败沿既有原子事务执行。结构操作仍沿原保护。文档默认 Tab 间隔、小数点符号及其他全局设置采用目标文档；源行高及表属性不转移。覆盖已有图片须通过原生删除保护，其他身份或未知源仍拒绝。整格输入与清空依据 [ONLYOFFICE Table.Remove](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L6288-L6335)。

每片段最多 256 张图片，逐图 base64 源最多 2 Mi 单元，解码后的压缩字节合计最多 2 MiB；共享资源的每次引用均计入检查。原生绘图身份分配最多扫描 16384 项，图片字节计入既有历史及输出预算。

片段最多 2 Mi UTF-16 单元、4096 条链接和 4096 个书签，目标书签目录最多 4096 项。编号和抽象定义各最多 4096 项，编号部件仍受片段的源码预算限制。既有 XML 深度、源字节、65536 文字单元、1000 行、63 列、4096 逻辑格及历史/字体/布局/输出预算继续执行。Web 在读 Blob 前另限 4 MiB；TS 不解析 WordML。未知引用、断裂合并、超预算和缺字体均保留原文档及历史。实现归 [`table-fragment-copy.mbt`](../../../modules/formats/src/docx/table-fragment-copy.mbt)、[`table-fragment-read.mbt`](../../../modules/formats/src/docx/table-fragment-read.mbt)、[`table-fragment-links.mbt`](../../../modules/formats/src/docx/table-fragment-links.mbt)、[`table-fragment-bookmarks.mbt`](../../../modules/formats/src/docx/table-fragment-bookmarks.mbt)、[`table-fragment-numbering.mbt`](../../../modules/formats/src/docx/table-fragment-numbering.mbt)及 [`table-fragment-paste.mbt`](../../../modules/formats/src/docx/table-fragment-paste.mbt)。编号资源依据 [ONLYOFFICE 所用编号定义与实例复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Serialize2.js#L4967-L5080)。结构依据 [ONLYOFFICE 所选内容](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L7524-L7748)与上述 `InsertTableContent`；链接复制参考 [ParaHyperlink.Copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Hyperlink.js#L80-L87)，同名书签处理参考 [addBookmarkStart/End](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Serialize2.js#L17511-L17533)，未移植上游可执行代码。

#### 跨格行列与矩形合并

同表跨格选择可使用既有六种行列命令，默认面板与 API 采用相同范围。插入行数等于所选格所属的不同源行数；向上插入复制首个所选行，向下插入复制末个所选行。删除这些源行及其全部内容，包括选区列外的格。纵向延续不重复计数；删除合并起始行后，存活的首个延续格成为新起始格，已删文字不转移。仅含延续的中间行可存活，仍保持正确归属。依据 [ONLYOFFICE 所选行增删](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9997-L10254)。

插入列数等于首个所选源行中的实际所选格数，横向跨度不重复计数。左插使用首个所选格的有效宽度，右插使用末个所选格的有效宽度；边界取全部实际所选格的最左/最右网格边界。新列复制每行相邻格的属性，分别维护纵向归属。删除列按同样的左右边界移除各行相交整格；沿既有公共网格重建、固定总宽、行尾空缺及空行清理规则。依据 [ONLYOFFICE 所选列删除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L10329-L10426)及[插列数量、宽度与边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L10512-L10658)。

跨格 `merge` 的 rows/columns 必须等于选区的逻辑矩形尺寸；默认面板自动填入并锁定这两个数量。已有合并格须完整位于矩形内，切开已有跨度时原子拒绝；内容按源顺序进入左上格。六种行列命令及合并均沿现有源补丁一次提交历史，撤销恢复原字节和正/反向选择，保留未删内容及其他部件。删除最后全部行或列时移除表格并进入正文。源、字体、布局及输出预算继续检查，失败不提交。

跨格 `unmerge` 按实际所选主格取消合并，保持原公共网格；相交的合并格整体处理，范围外合并格及普通格保持原源。每个主格的全部文字留在原格，新格为空并继承对应源行格的框与首段格式。所有修改及布局预检合为一项历史，光标定位首个所选主格；没有合并格时保留原源、范围和 revision。未知格源、无可用文字宽度、字体及预算失败整体拒绝。指定行列拆格支持同一范围，规则归上述 `splitCell` 合同。拆表仍须选择单格，默认面板在跨格时禁用。链接、书签及批注创建沿普通文字范围规则；跨格时链接查询给出原因，默认面板禁用对应创建。部分跨入单元格、跨不同表格端点及未知格内容沿既有保护规则；两端在正文的完整表格范围归[正文富文本片段](#正文富文本片段)；跨格边框/边距的默认面板、嵌套表格和其余结构范围操作继续实施。

### HTML/Markdown 水平线

HTML 的 `hr` 和 CommonMark 水平分隔符转换为独立段落中的原生 WordprocessingShape `line`。源格式保留引用和列表的缩进，水平线本身不带编号；首尾水平线与目标前后文字分段。源格式与匹配格式保留可编辑的矢量，默认形状面板可继续修改线宽、颜色、尺寸及删除。纯文本方式只保留段落边界，不写图形或分隔符文字。三种方式沿现有片段事务、精确历史及保存重开路径，无新增命令。

默认使用可用文字区的全部宽度、居中、`808080` 和 1.125 pt 描边。实际粘贴按接收节、分栏或单元格计算宽度；匹配格式计入目标缩进。HTML 导入格按原生固定网格和合并跨度计算，扣除默认边距与半边框宽度的较大值。HTML `width` 接受数字/px、pt 或大于 0、不超过 100% 的比例；`size` 接受数字/px、pt，转换为描边。内联 `width/height` 覆盖对应宽度和线宽，`color` 及 `text-align` 覆盖颜色和对齐，`align` 支持 left/center/right。尺寸换算为 EMU，宽度向下取整，避免超过可用文字区。描边最多 1584 pt，超宽及无可用宽度原子拒绝。资源预检只枚举内嵌图片，不读取目标布局；实际宽度和字体在粘贴前检查。

水平线和图片共用 256 个绘图及唯一身份预算，仍受 512 段落、输入、XML、布局、历史和输出上限约束。当前使用平面实线；阴影、立体效果及更广边框 CSS 继续实施。实现归[水平线转换](../../../modules/formats/src/docx/markup-rules.mbt)和[共享原生形状构造](../../../modules/formats/src/docx/shape-insert.mbt)。原生内联矢量、宽度、颜色、线宽和对齐依据 [ONLYOFFICE HTML 水平线](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/HtmlFile2/Tags/OOXMLTags.cpp#L674-L765)，未复制上游执行代码。

### HTML/Markdown 内嵌图片

HTML 的 img/src 和 Markdown 的直接/引用式图片接受 `data:image/png;base64,...` 或 `data:image/jpeg;base64,...`。核心校验 MIME、文件头、像素和尺寸预算，复用原生行内 DrawingML、关系、内容类型及图片部件。保留 alt/title；同片段重复字节共用源部件，绘图身份分别分配。源数据按原压缩字节保存，不重新编码。

默认图片框按 96 dpi 把原始像素换算为点。HTML 的 width/height 属性按像素处理，内联 width/height 支持数值、px、pt，覆盖相同属性；只设一边时保持原始比例，两边都设时使用明确尺寸。百分比、auto、裁剪、变换、浮动和链接内图片尚不在本入口范围；HTTP/file/cid 等来源不请求且明确拒绝。原有行内图片编辑、资源完整性和历史规则继续适用。

`FoundationSession.execute({ operation: "markupImages", revision, kind, input, mode: "source" })` 和异步 `FoundationClient.markupImages` 返回 `DocxFragmentImages`，其中 `kind` 为 html 或 markdown。查询保留源、选择、revision 和历史。宿主通过 `execute({ operation: "addImage", key, width, height, rgba })` 登记像素，再调用相同输入和方式的粘贴命令。Web 客户端自动准备并登记图片，再提交粘贴。损坏像素在提交前拒绝，浏览器创建的 bitmap 总会释放。

源格式和匹配目标格式都保留图片框及资源；纯文本方式保留 alt，省略无 alt 的图片，不创建图片部件。所有方式仍验证图片源及尺寸。每片段的图片与水平线合计最多 256 个绘图，图片压缩字节累计最多 2 MiB，元数据各最多 1024 个 UTF-16 单元；总输入仍限 65536 单元。单图最多 4096×4096、4194304 像素，解码缓存继续限 16 MiB/256 项。图片框沿原 0.1–14400 pt 范围。实现归[图片输入与预检](../../../modules/formats/src/docx/markup-images.mbt)及[共享原生图片构造](../../../modules/formats/src/docx/picture-markup.mbt)。尺寸换算参考 [ONLYOFFICE 图片尺寸处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L13583-L13625)，未移植上游可执行代码。

### HTML/Markdown 粘贴方式

两种输入均接受可选 `mode: DocxPasteMode = "source"`，类型从 Wasm/Web 的 `foundation` 导出。默认对话框在 HTML 或 Markdown 输入下显示三种方式：

| mode | 行为 |
| --- | --- |
| `source` | 保留已支持的源字符和段落格式；沿原生正文片段事务写入 |
| `merge` | 使用插入点的有效字体、字号、颜色、字符间距、突出显示及段落格式；保留源强调、上下标、链接、列表编号和标题级别 |
| `text` | 提取文字、图片 alt、Tab、换行及列表标记，表格转为 TSV；清除源格式和链接，沿普通文字替换事务，继承目标和待输入格式 |

匹配格式按范围文档顺序的起点取值，保留光标亲和；反向选择使用同一插入点。目标段落的对齐、方向、间距、缩进、Tab 和分页属性作用于导入段落，源编号/标题结构保留。不要求加载被替换的源字体，但保留的强调仍需目标字体对应资源。

纯文本方式先解释受支持的语法，不把 HTML 标签或 Markdown 标记作为文字。列表标记写为普通文字，段落和硬换行沿普通输入拆段；编号、链接和其他临时候选不写入文档。输入格式直接选“纯文本”时，仍按原输入文字粘贴。三种方式都执行原输入、资源、保护、范围及预算检查，不绕过未知结构限制。

每次粘贴最多一项历史，后续输入独立撤销；错误不改变源、选择或历史。普通系统剪贴板和私有原生片段仍默认保留源格式，方式选择作用于显式 HTML/Markdown 输入。实现归[粘贴方式](../../../modules/formats/src/docx/markup-mode.mbt)，原生属性合并参考 [ONLYOFFICE 段落与文字转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L3624-L3710)。

### HTML 粘贴

`FoundationSession`、`FoundationClient` 提供 `execute({ operation: "pasteHtml", revision, selection, html, profile, mode: "source" })`；`DocumentEditor.clipboard.pasteHtml(html, mode = "source")` 沿现有队列使用当前选择，方式归上节。默认粘贴对话框选择 HTML 后解释输入。普通 Ctrl/Cmd+V 或源格式粘贴先读私有原生片段，再读系统 `text/html`，最后读纯文本；显式单元格矩阵粘贴沿原规则。异步读取期间文档或选择变化时拒绝提交。

核心用固定 html 0.2.1 解析 HTML5，再写入与 Markdown 相同的[正文富文本片段](#正文富文本片段)。支持正文/单格范围替换、div/p、h1–h6、blockquote、pre/code、十进制 ol 起始值/ul、普通 li、span、b/strong、i/em、u、s/strike/del、sup/sub、br、hr、受支持的内嵌 img 和 HTTP/HTTPS/mailto 链接。HTML5 容错由解析库完成；普通 ASCII 空白折叠，NBSP 保留，pre 和指定保留模式写原生 Tab/换行。

仅使用 style、dir、hidden，以及 a 的 href/title、ol 的 start、img 的 src/alt/title/width/height 和上述[水平线属性](#htmlmarkdown-水平线)。字符格式支持 font-family、pt/px 字号、粗斜体、RGB 颜色、下划线/删除线和上下标；段落支持对齐、方向、标题 outlineLvl、引用及列表缩进。字号换算到原生半点。white-space 支持 normal/nowrap/pre/pre-wrap/break-spaces。display:none、visibility:hidden/collapse 和 hidden 属性移除对应子树。其他属性及未声明 CSS 丢弃，不把 CSS 写入 DOCX。

script/style/head 元数据和 iframe/object/embed/template/noscript 子树全部移除，事件属性不参与转换。核心不执行脚本，也不请求图片、样式、框架或链接。未知元素、未支持图片来源、SVG/MathML、本地锚点、逆序/逐项改号及不支持的已声明格式明确拒绝；不会回退成纯文本掩盖失败。普通表格归下节，更广 HTML 结构和图片引用形式仍待实施。

源最多 65536 个 UTF-16 单元及 2048 个 `<`；树最多 4096 个节点。转换沿共同的 32 层、512 段落、256 列表、9 级编号和片段/字体/历史/输出预算。格式、关系及编号共用一项事务，失败保留原源、选区和历史；保存重开后继续原生输入。实现归 [HTML 输入](../../../modules/formats/src/docx/html-input.mbt)及[内联格式](../../../modules/formats/src/docx/html-style.mbt)，参考 [ONLYOFFICE HTML 粘贴入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L12167-L12230)，未移植上游可执行代码。

### HTML 表格

HTML 输入支持 `table`、`caption`、`thead/tbody/tfoot` 行组、`tr`、`td/th` 及 `colgroup/col`。核心将网格写为原生 Word 表格，`rowspan/colspan` 生成纵向延续与列跨度；`rowspan=0` 延续到当前行组末尾，超过行组的跨度截到该边界。缺少的普通格补为空格。`th` 默认粗体和居中，显式字符/段落样式继续覆盖。格内段落、列表、链接及内嵌 PNG/JPEG 沿现有转换与资源事务，禁止嵌套表格。

可见 `thead` 行写为连续的原生 `tblHeader`，复用[重复表头](#重复表头)的跨页布局、合并格、原生编辑及输出。表头排在正文行组之前，`tfoot` 排在正文行组之后，各类行组内部保留源顺序。隐藏行不占表头行数，普通 `th` 不会自动成为重复表头。纯文本按相同可见顺序生成 TSV，不重复输出表头。标志写回参考 [ONLYOFFICE HTML 表头转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L10581-L10607)，多行和跨页沿本项目的原生表格合同。

题注转换为表格前后的普通 Word 段落，保留受支持的富文本、链接、多段内容及原生输入。默认置顶并沿普通段落宽度居中，CSS `text-align` 可覆盖。`caption-side: top/bottom` 支持题注自身设置及表格继承，旧 `align="bottom"` 作为无 CSS 时的底端位置。隐藏题注不输出。源格式的顶端题注通过 `keepNext` 与表格保留分页关系；匹配格式沿目标段落属性，纯文本按可见位置输出一次。默认位置、居中及段落转换参考 [LibreOffice HTML 题注](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/source/filter/html/htmltab.cxx#L4552-L4592)。自动编号与交叉引用仍按[序列编号字段](docx-pages.md#序列编号字段)和 P10 引用功能继续实施。

表格 `width` 属性或 CSS 支持数字/px、pt 和大于 0、不超过 100% 的宽度，默认 100% 的可用栏宽。`colgroup/col` 的 `span` 和数字/px/pt/% 宽度生成原生列宽与合并格宽度，列宽百分比大于 0、不超过 100%；子列未指定宽度时继承列组。含百分比列时，先按实际接收栏宽解析表格百分比，再将百分比列和绝对列写为整数 twip 网格；未指定列均分剩余宽度，取整余数按列顺序分配。绝对宽表格直接按指定宽度解析。后续宽度变化仍沿原生表格比例，网格和布局超限继续拒绝。仅含绝对列时保留既有比例与缺省 72 pt 列宽。单格 `bgcolor/background-color`、`valign/vertical-align` 与 table 的 0–16 px `border` 已接通原生底色、垂直对齐及黑色实线边框。其他 CSS 沿上述白名单处理；百分比列宽、按内容自动估算列宽及更广边框/尺寸继续实施。

源格式和匹配格式保留表格结构，匹配格式将插入点的字符/段落格式应用到各格，保留源强调、编号、链接和表格属性。纯文本按表格位置插入带引号的 TSV，跨列和纵向延续格留空，主格文字仅出现一次。正文可一次粘贴段落与表格；首尾段落与目标文字合并，表格两侧文字各自保留。段首插表不新增前置空段，段前分页随第一格转移。目标在单元格内时，含表格的源/匹配方式拒绝嵌套；纯文本方式仍沿普通输入。

既有正文片段读取和粘贴复用同一路径，允许最多 32 个普通表格、合计 4096 个网格单元，每表最多 1000 行和 63 列；HTML 的 512 段落上限包含各格及纵向延续。图片预检只读，实际像素解码后才提交，正文、编号、链接和媒体合为一项精确历史。未知/重叠网格、字体、布局、保护及预算失败整体拒绝。实现归[HTML 表格](../../../modules/formats/src/docx/html-table.mbt)和[正文片段事务](../../../modules/formats/src/docx/fragment-paste.mbt)，网格跨度及延续参考 [ONLYOFFICE 表格行转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L11763-L11901)；未移植上游可执行代码。

### Markdown 粘贴

`FoundationSession`、`FoundationClient` 提供 `execute({ operation: "pasteMarkdown", revision, selection, markdown, profile, mode: "source" })`。`DocumentEditor.clipboard.pasteMarkdown(markdown, mode = "source")` 在现有编辑队列中使用当前选择，沿上述三种粘贴方式。默认粘贴对话框选择 Markdown 后解释输入；原生普通文字粘贴不自动猜测语法。

核心用固定 cmark 0.4.12 解析 CommonMark，转换为[正文富文本片段](#正文富文本片段)，复用格式、编号、链接及源事务。支持普通正文或单个普通格的范围替换、ATX/Setext 标题、粗体/斜体、实体/转义、软换行和硬换行、引用缩进、行内/块代码、有序/无序嵌套列表、续行段落，以及 HTTP/HTTPS/mailto 的直接、引用式和自动链接。标题写原生 outlineLvl 与粗体；代码写 Courier New 和原生 Tab/换行，字体仍由宿主 profile 显式提供。

一次导入合为一项精确历史，保留目标前后文字及其他源部件，保存重开后继续编辑。编号定义、实例、外链和内嵌图片关系沿原片段事务分配身份；不访问链接。图片范围归上述[内嵌图片](#htmlmarkdown-内嵌图片)，水平分隔符归[水平线](#htmlmarkdown-水平线)。Markdown 内嵌 HTML、外链图片及本地锚点明确拒绝，不静默丢弃。扩展语法按普通 CommonMark 文字解释，不声明 GFM 表格、删除线、任务框、数学或脚注导入。独立 HTML 入口归[HTML 粘贴](#html-粘贴)；Markdown 内嵌 HTML 及更广交换结构仍待实施。

源文本最多 65536 个 UTF-16 单元；解析前限制 `[]()*_>` 及反引号共 1024 个。转换树最多 4096 个节点、32 层、512 个段落、256 个列表及 9 级编号；生成片段仍受原 XML、资源、字体、历史和输出预算限制。未知内容、缺字体、旧 revision、保护及预算失败均不提交源变化。实现归[Markdown 输入](../../../modules/formats/src/docx/markdown-input.mbt)。格式转换参考 [ONLYOFFICE 粘贴段落与文本](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L12167-L12230)，未移植上游可执行代码。

### 正文富文本片段

正文浮动图片和基础图形随原生锚点转移。复制保留两轴基准、偏移/对齐、层次、环绕侧向与四边间距；粘贴把逻辑锚点放入目标段落，按目标页面与段落布局解析。图形保留原生矢量，图片沿原压缩字节预检、解码和资源事务执行。

每次粘贴分别分配绘图身份。已携带的 `wp14:anchorId/editId` 须为八位十六进制值，核心为副本重分配未用值，避开主文档及声明的页眉/页脚身份。源与目标已有元数据、注释和非目标部件保持。未知元数据、引用及复制锁继续拒绝；删除锁阻止剪切和删除。浮动片段要求正文目标，粘入单元格原子拒绝。范围替换、资源与新锚点合为一项精确历史，重复粘贴生成独立对象。行为参考 [ONLYOFFICE ParaDrawing.Copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ParaDrawing.js#L1361-L1407)。

`FoundationSession.execute({ operation: "clipboard", revision, selection, cut: false })` 和异步 `FoundationClient.clipboard` 返回 `DocxClipboard`：`{ kind: "body" | "cells", text, fragment, reason, selection }`。普通正文和同一单元格中的文字范围可截取部分字符及跨段落内容；跨格整格范围沿既有矩形片段。查询保持源、选择和历史。不能转移的已知内容返回纯文本及原因，图片和域的剪切须成功生成富文本并通过原生删除保护。

两端都在普通正文段落时，范围可以完整包住中间的普通表格。复制按正文块顺序生成原生片段；正文和格内内容共用编号及书签身份，保留合并网格、原生表宽/对齐/边框/默认边距、行高/重复表头/跨页策略、字符格式、链接、简单域和行内图片。纯文本使用 LF 分隔正文块，表格按带引号 TSV 输出，合并续格留空。剪切、普通替换、输入法候选和范围格式复用同一结构校验与事务，首尾未选文字保留；取消和撤销恢复原字节。默认选择、Copy/Cut、源格式粘贴、格内继续输入、重开及 PDF 已检查。依据 [ONLYOFFICE 所选正文块遍历](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/DocumentContent.js#L4810-L4835)。部分跨入格内、嵌套表格及未知结构继续拒绝。表样式资源尚未随整表转移；带这些引用的富文本捕获给出原因，不丢弃引用后生成片段。

正文片段携带解析后的字符/段落格式、完整普通书签、链接、编号、行内/浮动 PNG/JPEG 及基础图形。资源校验和目标身份分配复用[单元格富文本片段](#单元格富文本片段)。`bodyFragmentImages(revision, fragment)` 只读预检图片。`pasteBodyFragment(revision, selection, fragment, profile)` 原子替换范围。Web 自动准备并注册像素，`DocumentEditor.clipboard.pasteFragment(fragment)` 沿既有编辑队列提交。字体、布局、资源、历史或输出失败保留原文档。

简单 `PAGE`、`NUMPAGES` 域也随正文片段转移，保留指令、显式编号格式及已解析的字符格式。纯文本输出取当前完整布局的实际结果，长度变化不改变用于剪切的逻辑范围；缺少、过时或不完整布局时拒绝读取所选域，不退回旧缓存。同步和 Worker 桥使用当前布局，调用方先完成相同 revision 的排版；MoonBit `selected_text`、`clipboard` 可显式传入 `layout`。粘贴按目标位置重算新域缓存，保留已有域的旧缓存，并与文字及资源合为一项历史。空结果域仍携带富文本片段，不视为空选择。整格/跨格及完整合并格中的简单域复用相同规则，范围归[单元格富文本片段](#单元格富文本片段)。依据 [ONLYOFFICE 原生简单域序列化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Serialize2.js#L5513-L5528)，实现归[域剪贴板值与格式](../../../modules/formats/src/docx/field-clipboard.mbt)。

单段粘贴保留目标段落属性，源字符格式随文字插入。多段粘贴使用源段落属性，保留目标前后文字的字符格式；最后一个部分段落当前也使用源段落属性。光标停在插入末尾，继续输入继承源字符格式。文字、资源、选择和所有段落合为一项精确历史。

默认 Copy/Cut 与原生快捷键携带 `text/plain` 及 Chromium 自定义类型 `web application/x-open-document-docx-body`。写入成功且文档、revision、选择仍一致时才剪切。默认粘贴面板的“保留源格式粘贴”、Ctrl/Cmd+V 和导出的 `pasteDocxSelection(editor)` 优先读取正文片段，其次读取单元格片段，缺少原生类型时粘贴纯文本。无效原生片段拒绝，读取期间目标变化保留文档。`paste(text)` 及原生普通 paste 事件继续采用纯文本路径。

最多 1024 个正文块、65536 文字单元；表格读取和粘贴另沿用[HTML 表格](#html-表格)的数量与网格预算。片段、图片、链接、书签及编号采用上述共享预算，Web 读取 Blob 前限 4 MiB。域另沿用每段 64 个及正文布局 4096 个位置的上限。跨不同表格端点、部分跨入格内、批注/修订/复杂域及部分书签转移继续实施；HTML/Markdown 输入范围归各自章节。实现归 [`fragment-copy.mbt`](../../../modules/formats/src/docx/fragment-copy.mbt)、[`fragment-import.mbt`](../../../modules/formats/src/docx/fragment-import.mbt) 和 [`fragment-paste.mbt`](../../../modules/formats/src/docx/fragment-paste.mbt)。段落拆分和首尾合并参考 [ONLYOFFICE SelectedContent](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/SelectedContent.js#L1021-L1198)，未复制上游执行代码。

### 表格尺寸

`editTable({ action: "tableWidth", value })` 设置当前格所在表的总宽度，单位为 pt。核心按原列宽比例分配整数 twip，精确保持目标总宽，同步 `tblW`、列网格和全部格的 `tcW`；横向合并按跨度求宽，纵向合并起始/延续关系和文字保持。最多 63 个逻辑列，各列至少 12 pt，格内边距须留出文字宽度，总宽不超过当前页的可用宽度。未修改的样式、边框、对齐、段落和其他部件保留。比例规则参考 [ONLYOFFICE 网格缩放](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L413-L429)。

`editTable({ action: "columnWidth", column, value })` 设置同表内指定逻辑列的宽度，column 从 0 开始，须小于当前列数。value 为 12–14400 pt 的整数 twip，整表仍须位于可用页宽内。其他列宽度保持，表格总宽随目标列增减；横向合并的格宽按所跨列求和，纵向延续节点一起更新。共享整表宽度的网格/属性序列化、保护、边距及半描边宽度预检、源历史和保存。规则参考 [ONLYOFFICE 列宽设置与网格重建](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L19008-L19039)；本 API 用逻辑列索引明确定位合并格覆盖的各列。默认 UI 显示从 1 开始的列号及对应宽度。

`editTable({ action: "rowHeight", value, rule })` 设置当前行或跨格选择覆盖的实际源行高度。`rule` 必须为 `atLeast` 或 `exact`，写入相应的 `trHeight hRule`。`atLeast` 允许内容撑高，值为 0 时删除行高属性并恢复自动；`exact` 固定行高并裁剪溢出，完整文字及逻辑位置仍保留。精确值另加同行最大上下边距，包含上边框，最小可见行距为一个 twip。纵向合并以末行模式决定是否允许内容撑高；末行为精确高度时裁剪到整个合并格。预览和 PDF 使用同一裁剪，光标及选区限制在格内，垂直移动跳过完全隐藏的行。重复表头保留相同裁剪。规则参考 [ONLYOFFICE 精确行高与边距](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L2660-L2700)、[内容裁剪](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L2775-L2900)及[合并格末行](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L3150-L3162)。尺寸须有限、非负、不超过 14400 pt，且为整数 twip；表宽须大于 0。核心保留合并行组的一页边界，拒绝超出可用页高的尺寸。

`queryFormatting(...).table` 在支持的表格上下文中返回 `{ id, autoFit, row, rows, column, columns, columnWidths, headerRows, width, rowHeight, rowHeightRule, align, tableMargins, tableBorders, cellFill, cellVerticalAlign, cellMargins, cellBorders, maxWidth, maxRowHeight }`，否则为 null。`id` 为当前表节点身份，`row` 从 0 开始，`columns` 为逻辑列数；`column` 为当前格左侧的逻辑列索引，`columnWidths` 为全部逻辑列宽（pt）；`width` 是列网格总宽，`rowHeight` 是源高度值，`rowHeightRule` 为 `atLeast` 或 `exact`；自动高度返回 `0/atLeast`。这些值均非浏览器测量。`DocxFlow.tables[].exactHeights` 按行携带精确模式。`align` 为整表的 `left`、`center` 或 `right`；`tableMargins` 是表格默认单元格边距，尚未叠加单格覆盖。`cellFill` 为当前格的六位 RGB 底色，无底色时为 null；`cellVerticalAlign` 为有效的 `top`、`center` 或 `bottom`；`cellMargins` 为该格有效的 `{ top, right, bottom, left }`。两类边距均以 pt 表示。默认 UI 读取同一查询，提交后反映实际属性；文档、所选段落或 revision 变化会重置未提交的属性输入。

尺寸操作保留逻辑选区和当前光标处的待输入格式，重排后清除旧布局定位提示，沿已有队列、源历史、保存重开和 PDF。无源变化不增加历史；未知行/格映射、网格标记、属性或预算失败原子拒绝。缺少的尺寸属性按 OOXML 顺序创建；恢复自动高度保留其他行属性，并重新显示被裁剪文字。其他格属性兼容归 [P14](../roadmap.md#p14-兼容与性能已完成)。

### 表格边框

表格工具的边框选择器用图示标记每条边及内部横线和竖线。图示与文字标签一起显示，支持原生键盘选择。确认后在编辑队列中核对目标选区，边框继续使用同一原生表格事务。

`editTable({ action: "tableBorders" | "cellBorders", value })` 修改整表默认边框或当前逻辑格的直接边框。`value` 为非空部分属性集：四边使用 `top/right/bottom/left`，整表另支持 `insideH/insideV`。每边 `DocxBorderEdit = { style, width, color, themeColor? }` 设置源属性，必填 style 为 `single/double/dashed/dotted/dashSmallGap/dotDash/dotDotDash`，`width: 0` 显式关闭，null 删除该边直接属性并恢复继承；省略的边保持。非零线宽为 0.25–12 pt，须为 1/8 pt 的整数倍；color 为六位 RGB。`themeColor` 省略或为 null 时使用固定 RGB，指定时使用与[页边框](docx-pages.md#页面边框)相同的原生 Word 主题槽，且线宽须大于零。默认 UI 提供表格/当前格、各边/全部、实线/双线/虚线/点线/小间隔虚线/点划线/双点划线、线宽、固定/主题颜色、移除及恢复继承。纵向合并起始与延续节点共同修改，内部合并边不绘制。

核心沿表格样式链与直接属性求有效值。单元格声明优先于表格默认；相邻单元格先取非空边，再取总占宽较大的边框；总占宽相同时，单条描边优先于双线，其余按 RGB 亮度规则求值。规则依据 [ONLYOFFICE 边框冲突](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L15267-L15342)。当前读取 `single/double/dashed/dotted/dashSmallGap/dotDash/dotDotDash/nil/none`、RGB/auto 和左右的 start/end 别名；auto 为黑色。主题边框支持原生 `themeColor/themeShade/themeTint`，沿[主题颜色](docx-content.md#docx-主题颜色)的槽映射和 HSL 明暗规则求值；样式、整表及单格共用解析。主题修改保留源槽、变换及缓存 RGB，仅更新派生边框颜色。未知主题槽、缺失主题色、非法变换、阴影、非零间隔及未知属性继续保护。

`queryFormatting(...).table.tableBorders` 返回六边的默认值，`cellBorders` 返回当前格四边的实际冲突结果；合并格某边包含不同线段时该边为 null，表示混合。`DocxFlow.tables[].borders` 为核心生成的 horizontal/vertical 网格，替代旧布尔值。边宽参与行高与分页预留，左右边界至少预留半个描边宽度。分页缓存、重复表头、Canvas 和 PDF 消费相同线段及颜色，Web 不重算边框。

属性沿现有单项源历史保存，保留文字、网格、选区、待输入格式和其他部件。无变化保留源片段及 revision；无文字宽度、未知目标、旧 revision、输出或历史预算失败原子拒绝。合并仍沿当前[结构规则](#表格创建)保留每行首格属性，取消合并复制相应格属性；跨格属性修改归[跨单元格属性选择](#跨单元格属性选择)，复杂边框仍归 P10/P14。实现归 [`table-borders.mbt`](../../../modules/formats/src/docx/table-borders.mbt)、[`table-border-editing.mbt`](../../../modules/formats/src/docx/table-border-editing.mbt)及[公共边框绘制](../../../modules/layout/src/table-borders.mbt)。

虚线和点线沿现有边缘分段绘制，分别使用按线宽缩放的 16:5 与 1:2 线段/间隙比。小间隔虚线 `dashSmallGap` 使用 6:2；点划线 `dotDash` 使用 16:5:5:5，双点划线 `dotDotDash` 使用 16:5:5:5:5:5，奇数位置为线段、偶数位置为空隙。末段裁剪到边界，落在尾部空隙时不添加线段。单条边缘最多 8192 段，单页表格描边最多 65536 段；所有候选线段先检查预算，再一次追加，超限返回 `limit-exceeded`。普通行、重复表头和纵向合并续排使用同一有界绘制，Canvas/PDF 沿相同普通描边输出。富文本单元格片段保留有效线型，粘贴后独立编辑。每段边缘重新起算节奏；其余复合线继续实施。原生名称依据 [ONLYOFFICE BorderType](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L10287-L10316)，其[非简单边框绘制仍有 TODO](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L15306-L15318)。分段依据第二参考 [LibreOffice GetDashing/GetLineDashing](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/svtools/source/control/ctrlbox.cxx#L247-L306)，未复制执行代码。

双线 `double` 保留原生每条线的 width，两线和等宽间隙总占 `3*width`。两条描边以原边缘为中心，分别偏移一个 width。行高、分页、左右最小留白和纵向合并续排使用总占宽；查询仍返回原生单线宽度。两条线共同检查描边预算。同页相邻行的共用边只绘制一次，换页后保留外边界；无操作、继承、富文本片段及精确历史沿原路径。ONLYOFFICE 尚未绘制复合边框，总宽和等分依据第二参考 [LibreOffice Word 双线换算](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/editeng/source/items/borderline.cxx#L205-L238)及[双线分配](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/editeng/source/items/borderline.cxx#L349-L357)，相同总宽的冲突参考 [HasPriority](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/editeng/source/items/borderline.cxx#L688-L707)。未复制执行代码。

显式设置某边 RGB 会解除该边的主题绑定，即使与当前显示颜色相同；再次应用相同直接 RGB 才是无操作。修改其他边保留未改边的完整声明，解除关联与主题修改各沿原有单项精确历史。查询和共享边冲突使用有效 RGB，Canvas/PDF 沿同一结果；跨文档富文本单元格片段固定源文档的有效 RGB，目标主题不改其外观。实现复用边框源事务与 [theme.mbt](../../../modules/formats/src/docx/theme.mbt)。

主题绑定的创建、改绑和解除使用原有边框提交。MoonBit 的 `TableEdit.TableBorders/CellBorders` 接收 DOCX 所有的 `TableBorderStyle`；TS 输入为 `DocxBorderEdit`，现有查询仍以 `DocxBorderStyle` 返回有效 RGB。首次绑定会按既有 Word 部件规则创建主题、关系及内容类型，与边框合为一项精确历史，预算失败全部拒绝。同一局部绑定只改线型/宽度时保留缓存 RGB、tint 和 shade；改绑时清除旧变换并按当前色表写新缓存，输入 color 仍校验但由核心主题结果覆盖。默认面板与页边框共用主题槽名称，固定颜色选择会解除绑定。主题锁保护新绑定及其修改；新建明暗变换和绑定专用查询草稿继续实施。实现归 [table-border-editing.mbt](../../../modules/formats/src/docx/table-border-editing.mbt)及[表格属性事务](../../../modules/formats/src/docx/table-properties.mbt)。

### 表格底色

`editTable({ action: "cellFill", value, themeColor? })` 修改当前格或所选完整单元格的底色。`value` 为不带 `#` 的六位 RGB；省略或清空 themeColor 时写固定 RGB，并解除原 `themeFill` 及明暗变换。指定主题槽时按当前主题取色，输入 RGB 仍校验，原生缓存使用实际色表。主题槽与[页边框](docx-pages.md#页面边框)相同；null value 删除直接底色并恢复表样式继承，不能同时指定主题槽。MoonBit `TableEdit.CellFill` 接收 RGB 和主题两个可空参数。纵向合并起始与延续节点一起修改，保留跨度、文字身份和其他属性。默认单格及跨格表单共用主题/固定颜色控件。

原生纯色底色读取表样式 `tcPr/shd` 的继承及单格覆盖，支持 `themeFill`、`themeFillTint`、`themeFillShade`、原生槽映射和 clear/nil。有效 RGB 驱动自动文字/列表求色、共同/混合查询、片段及 Canvas/PDF，清除后按继承或页面背景求色。修改主题保留缓存和绑定源；重复应用同一局部绑定保留原明暗变换与缓存，不增加历史。改绑清除旧变换，首次绑定所需主题、关系和内容类型与底色合为一次可恢复事务。固定颜色选择解除绑定，片段使用实际固定颜色。未知源、图案、主题锁、注释与预算失败保持保护。实现归 [table-shading.mbt](../../../modules/formats/src/docx/table-shading.mbt)及[既有属性事务](../../../modules/formats/src/docx/table-properties.mbt)，原生字段依据 [ONLYOFFICE CShading](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Common/ComplexTypes.cpp#L417-L526)。条件样式、图案和新明暗变换创作继续实施。

单格及跨格底色应用规则参考 [ONLYOFFICE CellsBackground](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L1989-L2100)。

### 单元格垂直对齐

`editTable({ action: "cellVerticalAlign", value })` 为当前逻辑格设置 `top`、`center` 或 `bottom`，写入直接 `vAlign`；null 删除直接属性，恢复表格样式继承，无继承值时为顶部。基础表格样式沿 `basedOn` 链求值，条件表格样式仍受既有保护。纵向合并起始与延续节点一起修改；底色、网格、文字身份和其他部件保留。修改复用底色的单格事务，保留逻辑选区、待输入格式和精确历史。无源变化不增加历史，未知属性/标记与预算失败原子拒绝。

核心先排完格内内容并计算整组合并行高，再按剩余高度平移全部文字和内联对象：居中取一半，底部取全部。边距、边框、段落间距及多行内容参与内容高度；内容撑满时不产生负位移。跨页普通格仅在首个含文字的片段应用垂直对齐，后续文字从顶部继续。命中先确定所属单元格，再选其文字位置，格内空白也不会落入邻格。位移与单元格区域参与缓存，光标、选区、预览和 PDF 共用同一几何。默认 UI 提供三种对齐按钮。跨页合并延续归[表格行跨页](#表格行跨页)，更广属性兼容归 [P14](../roadmap.md#p14-兼容与性能已完成)。行为依据 [ONLYOFFICE 垂直对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L3426-L3495)。

### 单元格边距

`editTable({ action: "cellMargins", value })` 为当前逻辑格设置四边独立边距。`value` 使用 `DocxCellMargins` 的 `{ top, right, bottom, left }`，四项均为有限、非负、不超过 14400 pt 的整数 twip 值；null 删除直接 `tcMar`，恢复逐边继承。纵向合并起始与延续格同步修改，属性按 OOXML 顺序插入；底色、垂直对齐、网格、文字身份和其他部件保留。继承先求基础表格样式与当前表的 `tblCellMar`，再叠加样式及当前格的 `tcMar`。未提供的边继续继承，最终默认左右各 5.4 pt、上下为 0。当前从左到右表格中，`start/end` 优先于同层 `left/right`，`nil` 为零；相对宽度、条件表格样式和未知扩展继续保护。

核心 `Table` 与 `DocxFlow.tables` 使用必需的逐格 `margins` 数组。排版从格宽扣除左右边距，采用本行最大的顶部边距与当前格的底部边距计算内容高度，再执行垂直对齐。该规则参考 [ONLYOFFICE 边距继承及同行顶部边距](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableCell.js#L1389-L1425) 和[同行顶部边距求值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableCell.js#L2765-L2784)。改变边距会更新塑形宽度、行组页缓存、光标/选区、预览和 PDF。修改不能挤掉文字宽度，显式行高与边距的合并行组下限须小于一页可用高度；实际文字仍受既有分页约束。插列、缩表及其他事务也核对有效格内宽度，失败时保留原包和历史。

默认 UI 提供四边输入、应用和恢复继承。操作沿已有单格事务保留待输入格式、精确撤销/重做及保存重开；未知源属性、注释和预算失败原子拒绝。矩形多格属性编辑归[跨单元格属性选择](#跨单元格属性选择)，其他兼容归 [P14](../roadmap.md#p14-兼容与性能已完成)。

### 整表对齐与默认边距

`editTable({ action: "tableAlign", value })` 为当前格所在的正文表格设置 `left`、`center` 或 `right`，写入表格 `jc`。核心按页面可用宽度定位整表，格内段落对齐保持。默认 UI 提供三个整表对齐按钮。行为参考 [ONLYOFFICE TableAlignment](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L1368-L1378)。

`editTable({ action: "tableMargins", value })` 设置表格默认单元格边距，使用相同的 `DocxCellMargins` 四边值和[边距边界](#单元格边距)，写入 `tblCellMar`；null 删除当前表的直接默认值，恢复表格样式和基础默认值。现有单格及单元格样式的覆盖保留，只有继承这些边的格随之改变。默认 UI 分别显示整表默认值和当前格有效值，两组输入复用同一四边表单。行为参考 [ONLYOFFICE TableDefaultMargins](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L1053-L1097)。

两项操作使用表格属性事务，保留文字身份、选区、待输入格式、其他属性与部件；必要的表格属性容器按 OOXML 顺序创建。无源变化不增加历史，未知目标属性/标记、无文字宽度、边距超过页高或预算失败原子拒绝。预览、空白区域命中、光标/选区与 PDF 使用同一位置；保存重开和精确撤销/重做沿已有路径。浮动表格及其他表格属性兼容归 [P14](../roadmap.md#p14-兼容与性能已完成)。

### 表格自动适配

省略 Word 兼容模式时，核心采用 [ONLYOFFICE 的 Word12 默认值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/commonDefines.js#L3720-L3724)。模式小于 15 的外层表格按外侧单元格边距修正位置；自动宽度上限和百分比基准也计入这两侧边距。页眉页脚使用相同规则，缓存键保留该策略。模式 15 及以后和嵌套表格沿普通网格定位。规则归 [ONLYOFFICE 表格偏移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L2607-L2704)、[自动宽度上限](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L550)及[百分比基准](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L3695-L3698)。

`editTable({ action: "autoFit", mode })` 支持 `content`、`page` 和 `fixed`。内容模式写 `tblLayout=autofit`、`tblW=auto/0` 与各格 `tcW=auto/0`，随后每次排版按内容重新求宽；页面模式改为 `tblW=pct/5000`，跟随当前可用页宽。固定模式测量当前有效列宽后写 `tblLayout=fixed`、整数 twip 的网格及表/格 dxa 宽度。每次切换共同提交一次历史，保留合并跨度、段落身份、文字、格式、选择、其他部件与待输入格式；同源无变化不增加历史。

缺省 `tblLayout` 按自动模式读取；表样式和直接 `tblPr` 决定模式及表宽，直接属性优先。偏好宽度使用 `{ value, percent }`：dxa 转为点值并设 `percent: false`，pct 的 0–5000 转为 0–1 并设 `percent: true`，在表格实际落栏时解析；auto/nil 使用零点值表示未指定。公共 `Table` 携带 `autoFit/preferredWidth/preferredWidths`，布局层使用授权字体的相同塑形结果求字素、单词和不换行宽度，再合入边距、半描边、行内图片、缩进、列表和制表位置。单列约束先求，合并格不足部分按源网格比例分配；不足以容纳最小单词时向字素下限收缩，字素或图片仍放不下则拒绝。列宽最终落在整数 twip，受可用页宽及既有资源上限约束。规则参考 [ONLYOFFICE 自动表格宽度](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L448-L648)及[合并格约束](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L864-L1050)。

低层 `FoundationSession/Client.editTable` 的第 4 个参数为字体 profile，测量操作必须提供所需映射；`DocumentEditor` 自动传入宿主 profile，图片沿已提供资源预检。`queryFormatting(...).table.autoFit` 返回当前模式。自动模式中的 `width/columnWidths` 为保存的回退网格，有效宽度来自布局；默认 UI 显示自动状态，并在冻结后开放手动宽度输入。程序化整表/单列宽度修改也会先测量并转为固定模式；目标列至少 12 pt，已有其他窄列保持。Canvas、命中、选择、缓存和 PDF 共用有效网格。未知属性/保留标记、缺字体/字形、无法排版或预算失败不提交。嵌套/浮动表格和更广宽度类型继续按原保护范围处理。

### 表格行跨页

`editTable({ action: "rowSplit", value })` 设置当前格所在行或跨格选区端点覆盖的实际源行是否允许拆分，`value` 必须为布尔值。核心写入 `cantSplit val="0"/"1"`，有效值相同时保留源及 revision。`queryFormatting(...).table.rowSplit` 和 `DocxFlow.tables[].splitRows` 返回有效设置，包含表格样式链继承，缺省允许拆分。跨格选择通过 `cellSelection.value.rowSplit` 返回 `{ kind: "value", value: boolean }` 或 `{ kind: "mixed" }`。默认 UI 提供单行及跨格复选框，混合时半选；所有目标合为一项历史，保留原选择和范围外行。结构操作保留并复制已有行属性；开关、文字、选择和待输入格式沿现有事务及精确历史恢复。

普通自动/最小高度行按每格的实际文字行分页，各格独立继续，保留横向跨度、图片及逻辑位置。每页片段保留边框、底色、边距和单元格命中区域，短格结束后的空白定位到原内容末尾。新页首行重新应用首行行距，跨页间距不重复累积；段末间距在页底截断，不单独生成空白续页。行最小高度仍占位，单行或边距超过可用页高时明确失败，沿现有 1024 页和 32768 行预算终止。

禁止拆分时先将行移到新页；整页仍放不下时继续分页，避免丢字或无限换页。规则来自 [OOXML cantSplit](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.cantsplit?view=openxml-3.0.1#remarks)；逐格继续及首个文字片段垂直对齐参考 [ONLYOFFICE TableRecalculate.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L2710-L3495)，未复制上游代码。精确高度仍沿[裁剪规则](#表格尺寸)。实现归 [`table-row-continuation.mbt`](../../../modules/layout/src/table-row-continuation.mbt)及 [`table-height.mbt`](../../../modules/formats/src/docx/table-height.mbt)。

纵向合并组先按源行推进边界，再分配每个逻辑格的页面片段。普通相邻格决定各行的最小结束位置，合并文字可穿过中间行，其结束行仅在自动/最小高度模式扩展。每个片段保留起始格的内容身份和填充，页边界补齐合并格的外边框，内部合并边保持关闭。居中/底部对齐只作用于首个含文字的片段；精确结束行继续裁剪超出格框的文字，不生成额外内容页。

能放进一页的首组合并行仍与前方 `keepNext` 标题整体保留；超长组保留首个可放片段。重复表头、原生输入、源历史、保存重开、空白区域命中、光标/选区和 PDF 沿现有路径工作。布局继续使用相同的 1024 页、32768 行及候选预算。合并内容归属与结束行计算参考 [ONLYOFFICE 合并格续排](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L2710-L2805)及[首个文字片段对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L3400-L3495)，未复制上游代码。实现归 [`table-merge-continuation.mbt`](../../../modules/layout/src/table-merge-continuation.mbt)；嵌套/浮动表格继续保护。

### 重复表头

`editTable({ action: "headerRows", value })` 将当前表开头的 `value` 行设为重复表头，并移除后续行的直接表头标志。0 清除全部，值须为 0–1000 且不超过表的行数。`queryFormatting(...).table.rows/headerRows` 返回总行数与有效表头行数，`DocxFlow.tables[].headerRows` 为相同的有效连续前缀。默认 UI 提供行数输入。

导入只读取开头连续开启的 `tblHeader`。纵向合并跨越表头边界时，缩短有效前缀；主动设置这样的边界原子拒绝。规则依据 [ONLYOFFICE private_RecalculateHeader](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L1836-L1891)。源标志、内容、段落身份、其他部件与待输入格式沿已有单项历史保存、撤销和重做。

自动分页在后续页重画表头，复用文字、图片、合并、边距、对齐、底色和边框几何；Canvas 与 PDF 使用同一结果。表头与下一行所需片段放不进一页时，该页省略副本，正文继续排版；最小行高仍参与判断。表头自身跨多页时不重复。副本不增加逻辑文字、查找结果、键盘导航或选区高亮；点击副本定位源表头，编辑源行后各副本同步。布局 `Line.repeated` 标记副本，增量缓存键包含表头依赖，复制行计入行预算。纵向合并组按最大需保留文字片段预留表头空间；放不下时该组的续页省略副本。

### 列表读取与标记排版

导入的 `ideographTraditional`、`ideographZodiac`、`ideographLegalTraditional` 和 `taiwaneseCountingThousand` 编号保留原格式。天干和地支超出符号表后显示十进制。繁体财务数字和繁体计数支持 0–999999。HTML 使用显式标记保留文字。[ONLYOFFICE 天干地支](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/editorscommon.js#L8501-L8521)、[财务数字](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/editorscommon.js#L8971-L9008)、[繁体计数](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/editorscommon.js#L9398-L9435)

`decimalFullWidth` 将十进制数字逐位转换为全角字符，包括零；`decimalEnclosedCircle` 使用 ①–⑳，零及超过 20 的值使用普通十进制数字。标点仍由列表模板决定。两项复用 [number-label.mbt](../../../modules/layout/src/number-label.mbt)，DOCX 的读取、创建、级别修改、重启和默认目录使用相同格式名；PPTX 的 `arabicDbPeriod/arabicDbPlain/circleNumDbPlain` 映射到同一转换并保留各自标点。原生输入续号、精确历史、保存重开、字体预检及 Canvas/PDF 沿现有路径。依据 [ONLYOFFICE 圆圈格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/editorscommon.js#L10496-L10510)、[全角转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/editorscommon.js#L10565-L10577)及[演示编号映射](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/PresentationNumbering.js#L188-L274)，未复制上游执行代码。


核心读取主文档及表格中的 `numPr`，合并默认/段落样式和直接 `numId/ilvl`；`numId=0` 取消继承。编号部件使用独立抽象定义、实例及 0–8 级别。支持 `decimal`、`decimalZero`、`decimalFullWidth`、`decimalEnclosedCircle`、大小写字母、大小写罗马数字和 Unicode 项目符号；读取级别的起始值、父级重启、`startOverride`、文字模板、对齐、后缀、段落及字符属性。正文与表格按源顺序计数，同一抽象定义的实例共享计数；首次遇到实例时应用当前级别的起始覆盖。`lvlOverride` 可覆盖已支持的级别属性，外层与内层 `ilvl` 必须一致。模板、文字和几何使用有效级别；计数起点及父级重启仍取抽象定义，缺失抽象级别的默认起点为 0。行为依据 [ONLYOFFICE 的编号计数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L28708-L28931)。

标记字符格式合并段落样式、段落标记直接属性和级别属性；级别定义最后覆盖。段落标记的直接下划线不传给列表标记，级别显式下划线仍可生效。依据 [ONLYOFFICE 的编号文字属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L1877-L1918)。

字母编号使用 `a…z, aa, bb…`，每 780 个值循环；罗马数字每 32767 个值循环。字母/罗马值为 0 时不输出数字字符，模板中的标点保留。依据 [ONLYOFFICE 数字格式化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/editorscommon.js#L8141-L8225)。整数不超过 2147483646；计数溢出明确失败。每份编号部件最多索引 4096 个抽象定义与 4096 个实例，标记最多 256 UTF-16 单元。编号身份一次建索引，重复数字身份、缺失引用、非法级别和未知有效属性拒绝解释，源包仍可原样保存。

派生 `Paragraph.marker` 为可选的 `{ text, style, align, suffix }`，只用于布局。`suffix` 为 tab、space 或 nothing。核心独立塑形标记，按首行位置和级别对齐放置，再计算正文的首行起点；续行使用段落缩进。RTL 按右侧起点定位，保留字形顺序；标记的字号和装饰参与行高及绘制，自动颜色沿正文/单元格背景计算。标记不进入正文 spans、光标 offset、命中区段或文字选区。`Line.marker` 保存其绘制区段，`markerText` 带输出后缀；缓存分别复制标记几何并计入原有预算。段首显式分页保留分页前标记，后续行不重复。

预览和 PDF 消费相同标记图元。PDF 的 ActualText 和默认 UI 的页面文字包含标记；`SemanticLine.marker` 是可选文字前缀，`text/start/end` 仍对应正文。支持的 `numPr` 已接入文字、段落格式与结构编辑；非空段落的 Enter 保留列表引用并重新计数。未知编号属性继续保护。

`FoundationSession/Client.execute({ operation: "enterDocx", revision })` 与原生 Enter 使用同一核心操作。空项在第一级退出列表并清除直接左/首行缩进，在更深级别降低一级。Enter 先删除已有选区，再判断空项规则；删除和列表变化合为一次历史。粘贴 LF 仍拆分段落，不触发空项退出。段首 Backspace 在更深级别降低一级并清除直接左/首行缩进；第一级退出时保留有效正文左边界 `max(left, left + first)`，首行缩进置零。右缩进和其他段落属性保留。规则依据 [ONLYOFFICE Enter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L19421-L19463) 与 [Backspace](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L4315-L4345)。

列表段首或从段首开始的选择使用 Tab/Shift+Tab 调整层级，范围限制为 0–8，触及边界不增加历史；跨段选择按各自级别调整。混合选择中的普通段落按 12.5 mm 网格调整左缩进，写回整数 twip。折叠在第一级且当前计数不大于 1 时，改为按文档默认制表间隔平移全部已定义级别，并清除当前段落的直接左/首行缩进；反向移动保持非负的标记位置。存在完整级别覆盖时修改该覆盖，否则修改共享抽象定义，相关实例一同重排。该特例要求有效零级定义有左缩进；缺少时保持原样。列表文字中间的 Tab/Shift+Tab 插入字面 Tab；原生 Ctrl+Tab、粘贴和表格导航仍沿原路径。编号部件与段落属性合为一项历史。规则依据 [ONLYOFFICE Tab](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L5146-L5205) 和 [编号缩进](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/Num.js#L461-L474)。修改或删除含未知注释/处理指令的属性时明确拒绝，保留源内容。

`FoundationSession/Client.execute({ operation: "lists", revision })` 返回 `{ revision, truncated, lists: [{ id, preview, reason, levels: [{ level, format, pattern, start, restart, align, suffix }] }] }`，最多 1024 项。不可编辑定义提供原因。`execute({ operation: "editList", revision, selection, change })` 支持 `{ action: "create", format }`、`{ action: "apply", id, level }`、`{ action: "remove" }`、`{ action: "restart", start }` 和 `{ action: "level", increase }`。`format` 为上述九种格式，`level` 为 0–8；`start` 为 0–2147483646，重启要求折叠选择且不接受项目符号。

`level` 命令要求选择包含列表，按各段当前级别升降一级并清除直接左/首行缩进；同选的普通段落按上述网格调整，合为一项历史。默认 UI 的级别按钮使用同一命令，支持混合状态。`DocxFormatting.list` 提供列表身份/级别的一致值、混合或不可用状态。

`DocumentEditor.formatting.lists()` 与 `editList(change)` 沿现有队列执行，默认 UI 提供目录、创建、应用、移除、级别调整和重启。创建提供九级默认定义；缺少编号部件时同步创建关系与内容类型。移除以 `numId=0` 取消继承并保留直接段落格式。重启复制独立定义，保留当前父级计数，并更新受影响的后续项目；依据 [ONLYOFFICE 重启编号](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L25105-L25218)。每次命令合为一项有界历史，失败保留原包；撤销、重做和保存重开恢复相同结果。自定义级别编辑归下文。

`FoundationSession/Client.execute({ operation: "updateListLevel", revision, id: listId, level, definition })` 与 `DocumentEditor.formatting.updateListLevel(listId, level, definition)` 修改已有级别，不要求正文选择。`DocxListLevelUpdate` 包含格式、模板、起点、父级重启、标记对齐和后缀；可同时修改左/首行缩进与标记字符属性。默认 UI 从列表目录读取这些参数，并提供同一修改入口。读取后若文档已改变，需重新读取列表再修改定义，防止旧参数覆盖新值。

`definition` 必须提供 `format`、`pattern`、`start`、`restart`、`align` 和 `suffix`。`pattern` 为 1–256 UTF-16 单元，`%1`–`%9` 只引用当前或之前已定义的级别，其他文字原样输出；拒绝控制字符和非法 XML 文字。引用项目符号级别时数字片段为空，模板标点保留，依据 [ONLYOFFICE 数字格式化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/editorscommon.js#L10428-L10439)。`start` 为 0–2147483646；`restart` 为 null（缺省父级规则）、0（永不重启），或 1–当前级别索引（对应从 1 开始的父级）。`align` 为 left/center/right，`suffix` 为 tab/space/nothing。

可选 `left/first` 沿用整数 twip 可表示的 pt 范围，null 清除级别上的直接值。可选 `character` 接受已有字符属性片段，禁止 `style` 引用；省略属性保持，null 清除。定义修改不覆盖正文直接格式，待输入字符格式也保留。已有完整级别覆盖时修改该覆盖，否则修改共享抽象定义；依据 [ONLYOFFICE SetLvl](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/Num.js#L131-L147)。改变级别起点不会删除实例的 `startOverride`；计数仍遵守前述抽象定义和实例覆盖规则。

编号 XML 的所有变化合为一项有界历史，主文档源内容不变。核心在提交前验证级别引用、已有编号结果、相关段落属性、包与历史预算；失败保留文档、选择和历史。修改会使相关编号重排，撤销/重做及保存重开保留相同模板、标记样式与缩进；预览和 PDF 沿已有标记路径输出。

当前不解释图片项目符号、编号样式链接、级别中的样式绑定、法律编号、修订编号及其他地区格式。使用中的定义含这些结构时明确失败，未知源内容照常保留；字体或字形缺失也不静默替换。页眉等内容区域仍受原有范围限制。
