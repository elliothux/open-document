# XLSX 格式、计算与引用

[格式合同目录](../formats.md)

### 条件格式

原生 `x14:conditionalFormatting` 的 `cellIs` 与 `expression` 已接入同一计算路径。`xm:f` 保留跨表、绝对和相对引用；内嵌 `x14:dxf` 复用既有差异样式。扩展规则与普通规则共用优先级和 `stopIfTrue`，重复优先级拒绝。范围、公式、样式和工作量沿既有预算校验。语义按 [MS-XLSX CT_CfRule](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-xlsx/025ea6e4-ad42-43ea-a016-16f4e4688ac8) 核对。

单元格输入后重算显示，原生规则 XML 保留。优先级调整可写回两类规则，并支持精确历史；扩展规则的改写、删除和相交范围清除保持保护。未知规则类型、扩展内容或命名空间保留诊断，不授予打印资格。实现归 [`conditional-extended.mbt`](../../../modules/formats/src/xlsx/conditional-extended.mbt) 与现有条件格式模块。

普通 `cellIs`、`expression`、`colorScale`、`dataBar`、`top10`、`aboveAverage`、`duplicateValues`、`uniqueValues`、`containsBlanks`、`notContainsBlanks`、`containsErrors`、`notContainsErrors`、`containsText`、`notContainsText`、`beginsWith`、`endsWith` 和 `timePeriod` 规则已在核心计算。值规则支持八项比较；数值、文字和布尔保持类型区别，文字比较忽略大小写，空格按零或空文字比较。表达式沿现有公式语法求值，相对引用以全部 `sqref` 的外接左上角为原点，保留绝对/混合及跨表引用；`ROW/COLUMN` 使用当前格。表达式的错误结果不命中，未知函数或引用给出诊断。

`priority` 越小越优先；命中的高优先级属性覆盖低优先级的相同属性，其余属性组合。命中 `stopIfTrue` 后不再使用后续规则，即使该规则没有差异样式。`dxfId` 从工作簿当前样式部件解析，不写回单元格样式。支持字体名、字号、粗斜体、文字色、纯色/无填充、四边标准边框线型、现有数字格式及基本对齐/换行。颜色复用主题、索引及 tint 解析；差异填充优先采用 `bgColor`，与 [ONLYOFFICE fixForDxf](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/model/WorkbookElems.js#L3502-L3509)一致。差异字体使用 profile 的精确映射或显式回退。

`XlsxConditionalFormat` 包含 `kind`（上述十七类）、`operator`、`formula1`、`formula2`、`stopIfTrue` 和部分属性 `format: XlsxCellFormat`。表达式的 operator 为空；仅 between/notBetween 使用第二个公式。颜色刻度的 stops、数据条的 bar、排名的 rank、平均值的 average、文字的 text 和相对日期的 timePeriod 见下文。`XlsxQuery.conditionalFormats` 返回当前表按优先级排序的全部普通规则，每项包含 `priority`、空格分隔的 A1 矩形 `ranges`、`rule` 和 `readOnlyReason`，容器也有保护原因。规则原点随完整 ranges 定位，不随当前选区变化。

`SpreadsheetEditor.objects.editSheet`、`XlsxClient.execute({ operation: "editXlsxSheet", revision, sheet, change })` 与同步 Wasm 共用以下操作。核心对应 `SheetEdit::ConditionalRule` 和 `ConditionalPriority`。

| action | 字段与行为 |
| --- | --- |
| `conditionalRule` | `ranges, priority, rule, sourceRevision`；priority 为 null 且 rule 非 null 时新增到最低优先级 |
| `conditionalRule` | priority 非 null 且 rule 非 null 时修改该完整规则的范围和属性；其他共享同一范围的规则保留 |
| `conditionalRule` | priority 非 null 且 rule 为 null 时删除该完整规则；ranges 可为空 |
| `conditionalRule` | priority 和 rule 均为 null 时，仅从 ranges 指定的单个矩形扣除条件规则；范围外公式随锚点平移，值及基础格式保留 |
| `conditionalPriority` | `priority, position, sourceRevision`；position 从 0 开始，将该规则移到完整列表中的指定位置，并重编规则优先级 |

修改、删除和排序要求 sourceRevision 等于执行时 revision，避免过期优先级命中另一规则。新增和选区清除使用显式范围，不依赖旧规则身份；仍沿 editSheet 的 revision 与原生草稿屏障执行。普通草稿先提交，新增规则单独进入历史；带过期身份的修改在草稿提交后拒绝，须按新查询重试。重复修改为相同范围/属性或移到原位置不新增历史。

规则、差异样式及派生尺寸共同提交一次事务。只修改条件或范围时保留原 dxfId、主题色及共享差异源。新差异样式复用现有样式池，保留旧的共享 dxf；缺样式部件时关系和内容类型一同创建/撤销。新数字格式沿原样式路径分配身份。普通和紧凑视口都在提交前按绘制规则检查可见单元格的有效字体。未知源、保留的规则注释/处理指令、工作表保护、缺字体或预算失败保留原文档。范围输入最多 4096 个矩形及 262144 UTF-16 单位；规则查询的范围/公式合计最多 1048576 单位，超出时返回管理保护原因。

默认条件格式面板提供新增、选择、修改、删除、上下调整优先级和仅清除选区规则，支持值/公式条件、停止后续规则、文字色/填充、粗斜体、字号、换行和数字格式。API 可使用全部现有 XlsxCellFormat 属性；面板未展示的导入属性保留。实现归 [`conditional-edit.mbt`](../../../modules/formats/src/xlsx/conditional-edit.mbt)、[`conditional-style-edit.mbt`](../../../modules/formats/src/xlsx/conditional-style-edit.mbt) 和 [`conditional-settings.mbt`](../../../modules/formats/src/xlsx/conditional-settings.mbt)。

排名使用 `kind: "top10"` 和 `rank: { rank, percent, bottom }`。`rank` 为 1–1000 的整数；percent 为 true 时限 1–100，取数字数量乘百分比后向下取整，至少保留一个数字。bottom 选择最小值，否则选择最大值；边界并列全部命中。平均值使用 `kind: "aboveAverage"` 和 `average: { above, equal, stdDev }`。above 选择高于或低于平均值，equal 包含等于最终阈值；stdDev 为 0–3 的整数，按总体标准差把阈值向相应方向移动。语义依据 [ONLYOFFICE 排名和均值计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7636-L7707)及[阈值比较](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L917-L931)。

两类统计规则的 operator、formula1、formula2 为空，不带 stops/bar，分别只带 rank 或 average；其他规则省略这两项，MoonBit 使用 None。统计取完整规则范围内的当前数字和公式结果，包含隐藏行，不重复统计交叠范围；空白、文字、布尔和错误不参与且不命中。阈值沿有界稀疏缓存计算，输入后重算，网格、颜色操作、自动尺寸和 PDF 共用有效样式。默认面板提供全部统计参数及既有差异外观，保留停止规则、原生 SpreadsheetML 属性、复制后的独立规则范围、精确历史和重开。实现归 [conditional-statistics.mbt](../../../modules/formats/src/xlsx/conditional-statistics.mbt)。

重复值和唯一值分别使用 `kind: "duplicateValues"` 与 `kind: "uniqueValues"`。operator、formula1、formula2 为空，不带 stops、bar、rank 或 average；format 和 stopIfTrue 沿既有差异样式规则。完整范围内按当前未格式化逻辑文字判断重复，包含隐藏行及公式结果，相交范围只统计实际格一次。文字区分大小写；数字与相同逻辑文字可同组，布尔、错误使用其逻辑文字，空白与空字符串不参与也不命中。数值的显示格式不改变重复性。行为依据 [ONLYOFFICE 重复键](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L3165-L3170)、[规则匹配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7734-L7746)及[未格式化值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L16253-L16267)。默认面板可创建和切换这两类规则；缓存按当前规则与计算上下文重建，计数文字消耗公式工作预算。复制保留独立规则范围、外观和精确历史，保存重开仍可编辑。实现归 [conditional-duplicates.mbt](../../../modules/formats/src/xlsx/conditional-duplicates.mbt)。

空白/非空白使用 `containsBlanks/notContainsBlanks`，错误/无错误使用 `containsErrors/notContainsErrors`。它们的 operator、formula1、formula2 为空，不带 stops、bar、rank 或 average。空白包含未存储格、空字符串及全部由 ASCII 空格组成的逻辑文字；制表符、不换行空格和全角空格均为非空白。错误按当前逻辑类型判断，错误文字字符串属于无错误；无错误规则也匹配空白。实际输入和公式结果变化后，网格、自动尺寸和打印沿现有差异样式重新计算。语义依据 [ONLYOFFICE 空白与错误判断](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7804-L7850)。

这四类原生规则可含一份互操作公式；核心按规则类型判断，API 查询保留空的 formula1/formula2。未修改规则保留原源，写回或复制时按当前范围锚点生成 `LEN(TRIM(A1))=0`、`ISERROR(A1)` 等公式；范围修改同步更新锚点，复制使用目标范围。生成形式依据 [ONLYOFFICE 规则公式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L1381-L1392)。这是规则的写回形式，单元格函数范围仍归[显示与计算](#显示与计算)。默认面板提供四种类型和既有外观，不要求输入这些公式。创建、修改、复制、精确历史和重开归 [conditional-predicate.mbt](../../../modules/formats/src/xlsx/conditional-predicate.mbt)及既有规则事务。

`kind: "colorScale"` 使用 `stops` 描述两个或三个颜色节点，operator、formula1、formula2 为空，format 为空对象，stopIfTrue 为 false。每个 `XlsxConditionalStop` 包含 `kind`、字符串 `value` 和六位 RGB `color`。节点类型为 min、max、num、percent、percentile 或 formula；min/max 的 value 为空，百分比和百分位范围为 0–100。普通值/公式规则不带 stops；MoonBit 的 ConditionalFormat 对应空数组。

颜色刻度使用完整规则范围内实际数字和已计算公式结果，忽略空格、文字、布尔和错误，不重复统计相交范围。不按可见窗口重新取范围，也不读取旧公式缓存作为当前结果。percent 按最小/最大值计算，percentile 按排序后的 `(n-1)*p` 位置线性插值；公式阈值在规则原点求值一次。阈值按数值排序，颜色保持节点顺序；超过端点时截定，所有值相同时使用末端颜色，无数字或阈值公式出错时不着色。RGB 插值使用 [ONLYOFFICE CGradient](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/model/ConditionalFormatting.js#L2637-L2680)的 256 步及通道向下取整，百分位参考 [getPercentile](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/model/FormulaObjects/statisticalFunctions.js#L356-L375)。

默认面板可在两/三节点间切换并编辑各节点的类型、值/公式和颜色；中间节点默认使用第 50 百分位。阈值与统计按当前计算缓存，编辑后重新计算，网格和 PDF 复用同一最终填充，不改基础单元格样式。只改范围时保留原规则源；修改阈值也保留未变的主题色/索引色节点。颜色刻度不创建 dxf，沿既有规则历史、局部清除与保存重开。统计、排序及阈值文本共同受规则工作预算限制，失败不留下部分缓存或半项编辑。实现归 [`conditional-scale.mbt`](../../../modules/formats/src/xlsx/conditional-scale.mbt)。

数据条使用 `kind: "dataBar"` 与 `bar: XlsxDataBar`。operator、formula1、formula2 为空，format 为空对象，stopIfTrue 为 false，不带 stops。bar 包含 minimum、maximum、六位 RGB color、showValue，以及整数 minLength/maxLength；条长范围为 0–100 且 minLength 不大于 maxLength。minimum/maximum 为 `XlsxConditionalThreshold { kind, value }`，沿用颜色刻度的六种阈值及字符串值。MoonBit 对应 DataBar、ConditionalThreshold 和 ConditionalFormat.bar；其他规则的 bar 为 None，JSON 省略。

普通 SpreadsheetML dataBar 默认显示值，最短/最长条长为 10%/90%。核心复用完整稀疏范围的当前数值、公式阈值和有界缓存，按值计算条长，超出阈值时截定。均匀值使用最短条长，无数字或阈值公式出错时不绘制；多条数据条使用首个有效的高优先级规则，并遵守更高优先级的停止规则。沿 [ONLYOFFICE legacy data bar](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/view/WorksheetView.js#L6273-L6385) 的条长、内边距和渐变端色计算，末端向白色混合 82.8%；全部非正数时从右侧绘制。普通规则采用同色、无轴线的旧格式语义，混合正负值仍沿最小/最大值计算。x14 的负值颜色、轴线、方向、实心条及边框设置尚未接入，保留源并保护相关输出与修改。

默认面板提供两个阈值、条色、显示值开关和最短/最长条长；新增、完整修改/删除、优先级及局部清除沿同一规则事务。只改阈值时保留未变的主题/索引色，不分配 dxf 或基础单元格样式。showValue 为 false 只隐藏网格/PDF 文字，值、公式、查询的逻辑 display 和原生输入保留；自动尺寸仍按实际值及有效文字格式计算。实现归 [conditional-bar.mbt](../../../modules/formats/src/xlsx/conditional-bar.mbt)。

共享绘制使用 `GradientRectangle(rect, stops)` 和 `gradientRect` 命令，均为从左到右的 RGBA 渐变。`stops` 含 2–32 项 `{ position, color, opacity }`；位置须有限、位于 0–1 并按非递减顺序排列，颜色为六位 RGB，`opacity` 须有限并位于 0–1。同位置色标形成突变，首尾外侧延续端点颜色。重复位置为零时使用最后一项，为一时使用第一项；Canvas 与 PDF 按相同非零区间延伸，避免在内圆或框角出现孤立端点颜色。数据条仍使用两个不透明端点，反向条交换颜色和起点。矩形坐标须有限、绝对值不超过 10^9，宽高非负。Canvas 按顺序添加色标，PDF 使用经矩形裁剪的轴向 shading，以 Type 3 函数拼接 Type 2 插值；非全不透明色标使用同位置灰度 shading 与 Luminosity 软遮罩，复用已有变换/裁剪并在局部作用域恢复状态。输出声明 PDF 1.4；PDF 相同色标序列共享资源，最多 4096 组，保留总输出预算。背景先绘制，随后数据条、边框和文字。实现归 [layout/gradient.mbt](../../../modules/layout/src/gradient.mbt) 与 [pdf/write-gradient.mbt](../../../modules/formats/src/pdf/write-gradient.mbt)。

网格、查询 `display`、自动适配和打印使用同一有效样式。依赖格输入或公式结果改变时，自动行/数值 bestFit 列按条件样式重算，与原编辑共享一次历史；固定尺寸保持原值。规则 XML、`dxf`、基础格式和范围外部件保留，保存重开继续计算。合并格按锚点求值。

图标集使用 `kind: "iconSet"` 与 `icons: XlsxIconSet`。支持全部 [17 种基础标准集](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.iconsetvalues?view=openxml-3.0.1)：`3Arrows`、`3ArrowsGray`、`3Flags`、`3Signs`、`3Symbols`、`3Symbols2`、`3TrafficLights1`、`3TrafficLights2`、`4Arrows`、`4ArrowsGray`、`4Rating`、`4RedToBlack`、`4TrafficLights`、`5Arrows`、`5ArrowsGray`、`5Rating`、`5Quarters`，包含 reverse、showValue、percent 和与图标级数一致的三至五个 thresholds；每个阈值使用 `{ kind, value, greaterOrEqual }`，类型和值沿既有六种阈值。operator、formula1、formula2 为空，format 为空对象，stopIfTrue 为 false，不带其他规则元数据。MoonBit 对应 IconSet 与 ConditionalIconThreshold。完整稀疏范围只统计当前数字和公式数字结果，按原生节点逆序比较，等值由 greaterOrEqual 控制；reverse 反转命中的图标，均未命中时使用索引零。percent 保留原生属性，各节点的 kind 决定计算方式。比较依据 [ONLYOFFICE getIndexRule](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L999-L1011)。

默认面板提供图标类型、阈值、等值、反向及显示值开关。切换级数时将草稿阈值重置为均匀百分比，级数不变时保留已编辑阈值。箭头的四级顺序为下、右下、右上、上，五级在中间增加向右；灰色使用中性填充，颜色沿既有红/黄/绿。方向顺序依据 [ONLYOFFICE 图标映射](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L3047-L3061)。原生读取、命令和跨工作簿规则剪贴板均校验级数与阈值数量，不能用五级名称配三个阈值。Canvas/PDF 复用有界矢量路径，文字为图标预留空间，自动尺寸包含图标。仅显示图标时，逻辑值和输入保留；可见格的 accessibleText 保留格式化值供无障碍网格使用。原生保存、精确历史和重开沿既有条件规则事务。符号提供带圆框和独立笔画两种外观，评级按原生级别增加四根蓝色柱，四分圆按顺时针从空心递增到实心；四色圆点和交通灯按各自顺序绘制。级别依据 [ONLYOFFICE 标准映射](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L3047-L3063)，新增几何归 [conditional-icon-symbols.mbt](../../../modules/formats/src/xlsx/conditional-icon-symbols.mbt)。x14 自定义图标及扩展属性保持诊断与保护。实现归 [conditional-icon.mbt](../../../modules/formats/src/xlsx/conditional-icon.mbt) 和 [conditional-icon-paint.mbt](../../../modules/formats/src/xlsx/conditional-icon-paint.mbt)。

规则及差异样式各限 4096 项，公式限 8192 UTF-16 单位；网格、整项打印或编辑适配共享 1048576 次规则/公式工作预算，不展开整列空格。未知规则、属性、装饰或扩展样式保留源并诊断；相关打印或适配拒绝，避免输出缺失效果。查询中的条件格式预算失败转成诊断，避免成功提交后被返回查询误报为失败；实际绘制和输出仍检查预算。扩展数据条、自定义图标与其他规则、边框仅改颜色及更广差异格式仍待实现。实现归 [`conditional-format.mbt`](../../../modules/formats/src/xlsx/conditional-format.mbt) 和 [`conditional-style.mbt`](../../../modules/formats/src/xlsx/conditional-style.mbt)，值比较参考 [ONLYOFFICE cellIs](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/model/ConditionalFormatting.js#L835-L913)。

四种文字规则使用 `containsText/notContainsText/beginsWith/endsWith` 和 `text: string`，MoonBit 对应 `text: Some(value)`。operator、formula1、formula2 为空，不带 stops、bar、rank 或 average；其他类型不带 text。按当前未格式化逻辑值忽略大小写比较，`*`、`?` 和 `~` 为普通文字。包含支持数字及布尔的逻辑文字，开头/结尾的非空文字只匹配文字值。包含不匹配空值和错误；不包含取反，因此可以匹配错误及空值。空文字的开头/结尾匹配所有非错误值。按 [ONLYOFFICE text operand](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L758-L830) 的规则，匹配文字恰为 TRUE/FALSE 时直接使用其布尔值，优先于上述文字比较。

原生 text 属性定义文字规则；缺失此属性的公式变体继续诊断和保护源。导入接受省略或与类型对应的 operator，API 统一为空。原生公式作为有界互操作缓存，保存未修改源；创建、复制或改变范围时生成当前锚点的 SEARCH/LEFT/RIGHT 公式，转义文字引号和 SEARCH 通配符。text 最多 8192 UTF-16 单位，生成公式仍须满足既有 8192 单位上限。默认面板可创建和修改四种规则与文字，复用差异样式、停止规则、当前输入重算、精确历史和保存重开。网格、自动适配和 PDF 沿同一有效样式。实现归 [conditional-text.mbt](../../../modules/formats/src/xlsx/conditional-text.mbt)，原生公式依据 [ONLYOFFICE 生成入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L1361-L1380)。

相对日期高亮使用 `kind: "timePeriod"` 与 `timePeriod`。`conditionalDatePeriods` 提供 `yesterday/today/tomorrow/last7Days/lastWeek/thisWeek/nextWeek/lastMonth/thisMonth/nextMonth`，MoonBit 为 `timePeriod: Some(period)`。operator、formula1、formula2 为空，不带 text、stops、bar、rank 或 average；其他类型不带 timePeriod。日、周和月使用完整公历区间，周从星期日开始，最近七天包含今天和之前六个公历日。区间含起点、不含终点，时间小数保留；沿工作簿 1900/1904 系统换算。按 [ONLYOFFICE 当前值匹配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7854-L7865)，数值及文字开头的十进制数字可参与，包含指数和后续文字；空值、布尔、错误及没有数字前缀的文字不命中。

原生 timePeriod 定义规则，零个或一个公式为互操作缓存。创建、范围修改和复制写回当前锚点的 TODAY/FLOOR/WEEKDAY/MONTH/YEAR 公式，普通单元格中的未知函数仍受保护。默认面板提供十种期间，复用差异样式、停止规则、当前公式结果、精确历史、保存重开和同一 Canvas/PDF 样式。日期沿[宿主日历上下文](xlsx-editing.md#相对日期筛选)提供；缺少日期时保留源并保护需要计算的显示、编辑和输出。区间依据 [ONLYOFFICE getTimePeriod](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L693-L756)，原生公式依据[同文件生成入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L1301-L1338)。实现归 [conditional-date.mbt](../../../modules/formats/src/xlsx/conditional-date.mbt)。

### 单元格超链接

`XlsxQuery.hyperlink` 返回 `{ target, mixed, readOnlyReason, navigationReason }`。target 为共同地址，未链接或混合选区为 null；mixed 区分混合范围。范围查询使用矩形运算，不展开整列空格。支持普通 `hyperlink`、外部关系及内部 location；未知属性/容器、组合外链与 location、未解析关系或相交的重复链接保护相关修改。

`HYPERLINK(link_location[, friendly_name])` 已进入普通公式求值、依赖重算及缓存。省略显示值时返回地址文字；给出显示值时保留文字、数值、布尔和错误类型，空白变为 0。两个参数均支持单格或按公式位置交叉取值的一行/一列引用；不能取唯一值的矩形返回 `#VALUE!`。参数错误先取地址错误，错误结果不生成公式链接。IF、IFERROR、IFNA 的已选结果、INDEX 标量和 XLOOKUP 未命中结果保留其公式链接；算术、普通文本函数及引用结果单元格只取得值，不继承地址。规则依据 [ONLYOFFICE HYPERLINK](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/lookupandreferenceFunctions.js#L1443-L1493)、[引用取值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L3424-L3442)及[范围交叉](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L18912-L18919)。

同格已有普通链接时，普通链接优先，沿 [ONLYOFFICE 命中顺序](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L12482-L12579)保留其独立来源。缺少普通链接时，查询、显式打开及 PDF 使用当前公式结果地址；未选分支和错误结果不激活公式链接。合并区域由主格拥有链接，其他源格不重复激活。直接链接面板对公式拥有的格显示修改原因，继续允许显式导航；地址和显示值通过原有公式栏修改。普通链接的设置/移除保留公式，移除显式普通链接后重新显示公式目标。公式不创建或清理普通链接节点、关系与字体样式，原文和精确历史沿既有事务保存。

公式地址仍执行既有 HTTP、HTTPS、mailto 与内部范围校验；不安全或过长地址保留公式显示值，在链接查询中给出原因并保护打印，不发出请求。未解析的内部目标保留导航原因，未打印的目标沿现有规则不生成注释。每次计算与缓存复用后的全部公式地址合计最多 1048576 个 UTF-16 单位；地址求值及本次打印的链接合并分别共享既有公式工作预算，超限不提交。实现归 [`formula-hyperlink.mbt`](../../../modules/formats/src/xlsx/formula-hyperlink.mbt)、[`formula-evaluate.mbt`](../../../modules/formats/src/xlsx/formula-evaluate.mbt)和 [`calculation.mbt`](../../../modules/formats/src/xlsx/calculation.mbt)。数组公式、动态引用及更多函数继续实施，未复制上游执行代码。

`SpreadsheetEditor.objects.editSheet({ action: "hyperlink", range, target })` 复用 `XlsxSession/Client.execute({ operation: "editXlsxSheet", revision, sheet, change })`。HTTP、HTTPS、mailto 或 `#范围/定义名称` 最多 2048 UTF-16 单元；内部目标须解析到现有可见表中的一个矩形，例如 `#'团队''s Data'!$A$1:B2` 或 `#Local`。核心使用现有公式词法、名称作用域与引用解析。null 移除范围内链接，保留单元格值、公式、富文本和直接格式；不自动套用链接颜色或下划线。显示文字继续通过原生输入编辑。

修改局部范围时拆分既有链接，范围外目标、提示、display、局部命名空间及间隙注释保留。单格命中合并区域时作用于整块；其他选区须包含相交的完整合并区域。新增关系复用同目标，不改写共用关系或清理旧关系；首次关系部件与链接 XML 合为一次历史。源、范围片段、历史及输出预算失败不提交。

默认面板提供地址、应用、混合移除及显式打开，原生草稿沿既有队列提交。打开文件、查询、设置链接和打印均不请求外链；外部打开使用新窗口及 `noopener noreferrer`。内部打开调用 `{ action: "openHyperlink", range, sourceRevision }`，核心检查当前选区与修订后定位，不增加历史。无效或隐藏目标返回 navigationReason，保留源并拒绝跳转。

已有改名、复制、删除工作表及行列/单元格结构事务继续更新普通链接范围与内部引用；名称改名同步内部 location，外部文件的 location 保持原值。删除定义名称时移除因此失去矩形目标的已知链接，包括名称别名链；其他已失效引用保留导航原因。保存重开支持继续编辑，链接和关系与原生输入、结构修改可精确混合撤销。PDF 已保留普通单元格的外链及内部目标注释，范围见下段。HYPERLINK 复用下文相同的打印注释路径，绘图对象链接继续实施。

既有 PDF 导出自动将本次实际打印的 HTTP、HTTPS、mailto 文字链接写为无边框注释。矩形来自核心文字块的实际位置，按单元格和纸张裁剪，保留对齐、换行、RTL、缩放、重复标题、多区域及多表页序。隐藏行列和空白文字不生成注释，不扩张打印范围。重叠链接或只覆盖部分合并格的链接保护打印；原有未知元数据和地址校验保持。内部 location 复用当前表、跨表及作用域名称解析，目标矩形的左上角映射到本次输出的实际格位置；合并格使用所属主格，空白目标也可定位。重复标题和多个区域中的同格使用首次打印位置。未输出、隐藏、缺失或不能解析为单一矩形的目标只保留文字。ONLYOFFICE [表格打印](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L6734-L6744)省略内部链接；本 SDK 扩展沿既有 [PDF 页目标语义](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/PdfWriter.cpp#L1207-L1227)输出 `GoTo/XYZ`。导出不改工作簿、选区、历史或未保存状态，也不请求链接地址。

核心打印结果的 `PositionedDocument.links` 随页面一起缓存，PDF 复用[现有链接注释](docx-content.md#docx-pdf-文字链接)序列化。每次最多 65536 个注释矩形、8388608 次链接与文字片段比较；目标解析共用本次打印的 1048576 项公式工作预算，继续执行既有打印及 PDF 字节预算。实现归 [`print-links.mbt`](../../../modules/formats/src/xlsx/print-links.mbt)与 [`print.mbt`](../../../modules/formats/src/xlsx/print.mbt)，未复制上游执行代码。

实现归 [`hyperlink-query.mbt`](../../../modules/formats/src/xlsx/hyperlink-query.mbt) 和 [`hyperlink-edit.mbt`](../../../modules/formats/src/xlsx/hyperlink-edit.mbt)。范围查找、设置/移除及保留直接格式的语义参考固定 [ONLYOFFICE Range hyperlinks](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L20760-L20849)，复用第一方范围拆分、关系与历史事务，未复制上游代码。

### 单元格便笺

`XlsxQuery.note` 返回查询单元格的 `{ address, exists, text, author, reason }`。单格或一个完整合并区域可编辑，合并区域使用左上角身份；多格返回选择原因。支持传统 comments XML 和普通 VML 便笺框。[线程批注](#单元格线程批注)使用独立入口，便笺面板保护其占位符。查询覆盖显式 `sheet/range`，不改变活动选区。

`XlsxSession/Client.execute({ operation: "editXlsxSheet", revision, sheet, change: { action: "note", cell, text, author } })` 和 `SpreadsheetEditor.objects.editSheet(change, sheet?)` 创建、修改或删除便笺。`cell` 是单个 A1 地址，`text: null` 删除；新文字必须非空，最多 32767 UTF-16 单元，CRLF/CR 归一为 LF。新建须显式提供非空 `author`，最多 255 单元且不含控制字符；修改保留原作者。空文本便笺可读取和删除，显式文字修改继承首个源 run 的字符属性。SpreadsheetML 转义由核心统一编码，字面的 `_x0041_` 不会变成 `A`。

默认面板复用 `EditorOptions.commentAuthor.name` 创建作者，未提供时仍可修改和删除已有便笺。应用前原生单元格草稿沿既有队列提交，值、公式、格式和计算结果保持。便笺输入以当前文档/工作表/单元格绑定；切换单元格更新输入，未应用的面板草稿不写入文档。同格单元格输入与保存保留尚未应用的便笺文字；绑定文字在布局阶段同步，避免挂载后的同步覆盖输入。显示文字与 VML 外观不进入单元格值、查找、CSV 或默认静态 PDF。面板继续提供便笺编辑；网格角标和悬停/选中提示见下段。

网格使用 R0 绘制橙色逻辑右上角标，RTL 镜像到左侧，尺寸随缩放变化；空格和合并锚点也可显示。位置与裁剪由核心沿用行列尺寸、隐藏、冻结和合并几何。`XlsxViewport.notes` 返回可见 `{ address, author, text, rect }`，rect 使用 point 的已裁剪画布坐标；跨冻结窗格的合并格可有多个可见片段，源便笺不重复。一次最多 4096 个片段及 5 Mi 文字/作者单元，含最多四窗格重复。仅便笺的远端单元格扩展网格滚动范围，不扩展默认打印区域。未知便笺继续沿既有保护和诊断处理，不暴露部分记录。

Web 复用核心矩形显示悬停或选中便笺的作者与纯文字提示，不改变选区、修订、历史或保存源。键盘选中格关联便笺描述，网格语义也提供作者和文字；Escape 隐藏提示，切换目标可重新显示。长文字可在有界提示中滚动；悬停提示内仍可读取。布局、工作表或修订变化后更新提示，释放实例时解除监听。角标和提示不进入静态 PDF，也不修改 VML 外观。角标参考 [ONLYOFFICE drawCommentCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L642-L690)，实现归 [`notes-grid.mbt`](../../../modules/formats/src/xlsx/notes-grid.mbt)及 [`spreadsheet-notes.ts`](../../../packages/xlsx/src/web/spreadsheet-notes.ts)。

首次创建把 comments、VML、工作表 `legacyDrawing`、关系和内容类型合为一项精确历史。普通备注框使用标准 `ObjectType="Note"` 及从零开始的 Row/Column、八项 Anchor。导入只有 comments 而无 VML 时，新增便笺会补齐全部现有便笺的框；若已有未解析的 `shapeId`，保护该创建。修改只替换文字正文，保留原作者、其他便笺、外围注释、局部命名空间和 VML 位置/外观。删除移除文字与对应框，最后一条删除后保留空部件和作者列表。每表最多 4096 条、合计 1 Mi 文字单元及 4096 个作者，并继续受包、输出与历史预算约束。

复制表创建独立 comments/VML 部件并重映射关系；副本可继续编辑。改名和删除沿已有工作表事务，删除仅回收独占部件和内容类型。新增部件按稳定顺序写入 ZIP，删除/撤销不改变相同状态的保存字节。重复地址、作者缺失、未知/不匹配的 VML、控件/图片、未知文字/扩展、共享/外部部件、保护、旧修订和预算失败原子拒绝。普通合并及取消合并的便笺归属见下段。未知 VML 保留未渲染诊断并拒绝打印；普通便笺输出按默认不打印批注处理，非默认批注打印设置继续保护。

整行/整列插删和四向单元格移位复用既有 `AxisChange`。便笺随所属格移动，范围外不变；删除所属格时移除该便笺及对应 VML shape，保留作者、空部件和关系。插入不得把空格上的便笺推出工作表。核心同步 comment 的 `ref` 和对应 `ClientData` 的 Row 或 Column，仅改动受影响轴的文字；Anchor 矩形、偏移、外观/标志、guid/shapeId、正文与其他源保留。范围插入后选区仍是插入区域，可定位到移后的便笺格；不单独修改既有选区规则。部件、值/公式、规则与选择共用一次精确历史；无法安全替换的 VML 文字或预算失败不提交。归属规则参考 [ONLYOFFICE updateCommentsDependencies](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L709-L838)，实现归 [`notes-transform.mbt`](../../../modules/formats/src/xlsx/notes-transform.mbt)。

普通行/列排序复用已有稳定位置映射，便笺与所属格一起移动，空值格也参与；标题、隐藏轴和范围外便笺保留。核心同步 `ref` 与 VML Row/Column，正文、作者和弹框外观保持。四向填充、自动序列与收缩填充保留每格原有便笺，不复制源便笺或覆盖目标便笺。清除内容/格式保留便笺；全部清除删除选区内文字与对应 VML shape，包括只有便笺的空格，保留范围外便笺、空部件与作者。各操作与值/公式/格式共同提交一次有界历史，支持精确撤销与重开；未知资源继续原子保护。语义参考 [ONLYOFFICE sortComments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L840-L863)、[自动填充](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22180-L22690)及[清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L16657-L16703)，实现复用同一便笺源编辑器与已有操作事务。

合并复用 [ONLYOFFICE mergeComments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L1395-L1431) 的源顺序选择：先取范围内首条便笺，后续便笺的行不更大且列更小时替换保留项。保留项移到合并左上角，其余文字与 VML shape 删除；单条便笺移动不产生便笺损失。`discardedNotes` 返回额外便笺数，范围 0–4095，沿现有 `discard` 显式确认；非锚点值/公式仍独立计入 `discarded`。保留项的正文、作者、shape 身份及框外观不变，范围外便笺保持。便笺、合并几何、单元格与派生样式共用一次精确历史；合并后修改便笺使用左上角身份。取消合并保留现有便笺和资源，不恢复已确认丢弃的便笺；撤销可精确恢复它们。未知/共享资源、无法替换的 VML 坐标或预算失败继续原子保护。

矩形剪切移动复用[单元格剪切移动](xlsx-objects.md#单元格剪切移动)事务。同表便笺沿原地址映射，跨表保留完整富文本、作者及已有 guid，并在目标作者表中匹配或追加作者。VML 框及所用形状类型带原外观和命名空间迁入，分配目标内未占用的身份，同步 `shapeId`、`ref` 与 Row/Column；原 Anchor、偏移和外观保持。目标缺少 comments/VML 时创建独立部件与关系，只有文字资源的导入便笺按已有创建规则补齐框。目标范围内的旧便笺被覆盖，范围外原节点保持；源端保留空部件、作者与关系。已移入的便笺可继续修改、删除或移回。身份冲突、无法匹配的原 `shapeId`、未知/共享资源及预算失败整体拒绝，文字和框源的迁移合计最多 2 Mi UTF-16 单元，其他便笺及事务预算继续生效。归属依据 [ONLYOFFICE moveRangeComments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L562-L586)，实现归 [`move-notes.mbt`](../../../modules/formats/src/xlsx/move-notes.mbt)及共用的 [`notes-import.mbt`](../../../modules/formats/src/xlsx/notes-import.mbt)。

部件及锚点格式参考 [ONLYOFFICE VmlDrawing.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/VmlDrawing.cpp#L295-L410)。实现独立使用已有 XML 编辑、单元格地址、关系及历史事务，归 [`notes-read.mbt`](../../../modules/formats/src/xlsx/notes-read.mbt)、[`notes-vml.mbt`](../../../modules/formats/src/xlsx/notes-vml.mbt)、[`notes-create.mbt`](../../../modules/formats/src/xlsx/notes-create.mbt)、[`notes-edit.mbt`](../../../modules/formats/src/xlsx/notes-edit.mbt)及 [`xlsx-format.tsx`](../../../packages/xlsx/src/react/xlsx-format.tsx)。线程回复/解决归[单元格线程批注](#单元格线程批注)；便笺外观编辑和其他资源变换兼容归 [P14](../roadmap.md#p14-兼容与性能已完成)。

### 单元格线程批注

`XlsxSession/Client.execute({ operation: "threadsXlsx", revision, sheet, cell })` 返回 `{ revision, sheet, cell, reason, items }`，合并格使用左上角身份。每条消息含 `id/parentId/personId/author/date/text/resolved`，主批注先于回复，回复保留源顺序。查询不改变选择或历史。无法安全读取的源返回原因与空目录；过期 revision、无效地址和已关闭会话仍拒绝请求。

`editThread(revision, sheet, change)` 提供五种操作。`{ action: "create", cell, text, author, date }` 新建单元格线程；`{ action: "reply", id, text, author, date }` 回复主批注；`{ action: "update", id, text }` 修改正文并保留身份和元数据；`{ action: "resolve", id, resolved }` 解决或重开；`{ action: "delete", id }` 删除单条回复或主批注及其全部回复。已解决线程须先重开才能回复。相同正文或状态不新增历史。

创建和回复须提供非空作者及 UTC 时间，支持整秒或三位毫秒。正文最多 32767 UTF-16 单元，CRLF/CR 归一为 LF；字面 SpreadsheetML 转义保持文字含义。作者按显式显示名复用，导入的 `userId/providerId` 原样保留。`SpreadsheetEditor.objects.threads(cell?)` 默认查询所选范围的左上角，`editThread(change)` 复用原生草稿屏障与操作队列。默认面板沿 `commentAuthor.name` 创建，已有消息可修改、删除、解决和重开。

核心维护原生 ThreadedComments、共享 personList、关系和内容类型，并同步 `tc={GUID}` 便笺占位符及 VML 锚点。新建、更新、删除和全部资源合为一项精确源历史，保留单元格值、公式、选择及范围外部件。删除最后一条后保留空部件和作者表。传统便笺可在其他单元格共存，同格普通便笺阻止创建线程。网格角标、提示及可访问描述使用原生主批注的作者和正文；占位文字及批注不进入默认静态 PDF。

整行/整列插删及四向单元格移位复用 `AxisChange` 的同一地址映射。主批注、有显式 `ref` 的回复、便笺占位符及 VML Row/Column 一起移动；无 `ref` 的回复保留继承写法。删除原格同时删除主批注及全部回复、占位文字和 VML shape。保留消息/作者身份、正文、日期、解决状态、已知 `xr:uid`、VML Anchor/外观和范围外源；插入不得把空格上的批注推出工作表。值、公式、选择及批注资源共用一次精确历史，候选整体验证后提交。实现归 [`thread-transform.mbt`](../../../modules/formats/src/xlsx/thread-transform.mbt)与 [`axis-edit.mbt`](../../../modules/formats/src/xlsx/axis-edit.mbt)，归属规则参考 [ONLYOFFICE updateCommentsDependencies](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L709-L838)，未复制上游代码。

普通区域的行/列排序复用既有位置映射，线程和占位符/VML 随记录移动；标题、隐藏轴和范围外批注保持。普通区域与原生表去重按保留记录移动线程，被删除记录的主批注及全部回复一并删除；尾部范围外线程保留，原生表范围沿既有事务缩小。保留原生身份、作者、日期、解决状态及正文，重复相同排序不新增历史。四向、自动序列、向外及收缩填充保留各格原有线程和资源源字节，既不复制源批注，也不覆盖目标批注。清内容与清格式保留线程；全部清除删除目标格的主批注、全部回复及对应占位符/VML，包含空格和完整合并区域。删除最后一条后保留空部件与作者表。所有操作沿既有 revision、源、输出与历史预算原子提交。默认去重预览说明会删除重复记录内的完整线程。实现复用 [`reorder-cells.mbt`](../../../modules/formats/src/xlsx/reorder-cells.mbt)、[`fill.mbt`](../../../modules/formats/src/xlsx/fill.mbt)及 [`clear.mbt`](../../../modules/formats/src/xlsx/clear.mbt)；排序归属依据 [ONLYOFFICE sortComments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L842-L863)，未复制上游代码。

工作表复制为全部主批注和回复分配新 GUID，重映射回复父身份、`tc={GUID}` 占位作者及已知 `xr:uid`，复用工作簿作者表。原生正文、日期、解决状态和缺少 `ref` 的回复写法保留，普通便笺及 VML 同时建立独立副本。原表与副本可分别编辑。删除仅回收目标表独占的线程、便笺、VML、关系和类型声明，保留全局作者及其他表资源。改名、移动和显隐保持批注身份与原生部件。所有变化复用一次有界源历史；未知出站关系或共享归属继续保护。实现归 [`thread-copy.mbt`](../../../modules/formats/src/xlsx/thread-copy.mbt)、[`sheet-copy.mbt`](../../../modules/formats/src/xlsx/sheet-copy.mbt)及 [`sheet-delete.mbt`](../../../modules/formats/src/xlsx/sheet-delete.mbt)，身份依据 [ONLYOFFICE clone/updateData](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L200-L233)，未复制上游代码。

合并沿[便笺源顺序规则](#单元格便笺)保留一条便笺或一个完整线程。保留线程的主批注、所有回复、占位符与 VML 坐标共同移到左上角；省略 `ref` 的回复保持继承写法。其余线程的主批注、全部回复及占位资源一起删除。既有 `discardedNotes` 按便笺或主批注计数，每个线程计一项；损失确认同时覆盖全部回复。身份、作者、正文、时间、解决状态、已知 `xr:uid`、VML Anchor/外观和范围外源保持。取消合并保留左上角线程，不恢复已确认删除的线程；精确撤销可恢复。主批注在合并格内继续沿左上角身份查询、修改和回复。候选整体验证后沿同一合并历史提交，未知源和预算失败保持文档与历史。实现复用 [`merge-query.mbt`](../../../modules/formats/src/xlsx/merge-query.mbt)、[`merge-edit.mbt`](../../../modules/formats/src/xlsx/merge-edit.mbt)及 [`thread-transform.mbt`](../../../modules/formats/src/xlsx/thread-transform.mbt)，保留规则依据 [ONLYOFFICE mergeComments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L1395-L1431)，未复制上游执行代码。

同一工作簿内的矩形剪切移动复用[单元格剪切移动](xlsx-objects.md#单元格剪切移动)事务。同表重叠按原区域快照映射，跨表把完整主批注及回复迁入目标原生部件，并保留消息/父身份、共享作者表及 `userId/providerId`。有 `ref` 的消息同步地址，省略 `ref` 的回复保留继承；正文、时间、解决状态和已知 `xr:uid` 保持。占位便笺与普通便笺沿既有源片段迁移，VML 按目标内可用身份重绑，保留原 Anchor 和外观。目标范围旧线程及全部回复整体删除，范围外拥有者保持；源端保留空资源和全局作者。目标缺少资源时在同一事务创建线程、便笺、VML、关系和内容类型。完整候选通过归属校验后提交一次精确历史，旧 revision、身份冲突、未知源和预算失败保留文档、选择及重做。原生消息和便笺迁移源各受 2 Mi UTF-16 单元限制，并沿用 4096 消息、1 Mi 文字和完整历史预算。默认剪切标记只绑定同一工作簿、revision 与区域，不携带批注或作者正文；跨工作簿或过期标记仍拒绝。实现归 [`thread-move.mbt`](../../../modules/formats/src/xlsx/thread-move.mbt)、[`move-notes.mbt`](../../../modules/formats/src/xlsx/move-notes.mbt)及 [`move-cells.mbt`](../../../modules/formats/src/xlsx/move-cells.mbt)，归属和目标覆盖依据 [ONLYOFFICE moveRangeComments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L562-L585)，未复制上游执行代码。

结构化区域复制将所选线程的全部消息及实际使用的原生作者纳入 `CopiedNotes`，支持同表、跨表、跨工作簿、重复与转置粘贴。副本分配新主批注/回复 GUID，重映射父身份、占位作者及已知 `xr:uid`，并避让源片段和目标的消息、作者及修订身份。作者按 `displayName/userId/providerId` 完整匹配，元数据不同的同名作者保持独立，重复粘贴复用已匹配作者；无关作者记录不进入片段。正文、日期、解决状态和省略 `ref` 的回复写法保持。仅 `all` 覆盖目标格的完整线程、回复、占位符及 VML；`notes: null` 清除该区批注，值/公式/格式模式保留目标批注。源保持快照语义，后续源编辑不改变已捕获片段，目标副本可独立修改。原生读取、作者合并、身份映射、VML 和目标资源共用既有粘贴事务及精确历史，未知源、身份/范围冲突或预算失败保留文档与重做。捕获和作者导入逐条限制命名空间展开后的源长度，防止合规大小的原始 XML 放大后耗尽资源。实现归 [`clipboard-threads.mbt`](../../../modules/formats/src/xlsx/clipboard-threads.mbt)、[`clipboard-notes.mbt`](../../../modules/formats/src/xlsx/clipboard-notes.mbt)及 [`thread-copy.mbt`](../../../modules/formats/src/xlsx/thread-copy.mbt)，身份规则依据 [ONLYOFFICE clone/updateData](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L200-L233)和[区域复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L550-L585)，未复制上游执行代码。

每表最多 4096 条消息、1 Mi 文字单元，作者最多 4096 条，沿用包、输出和 4 MiB 历史预算。重复身份、缺失作者、非直接回复、未知 mentions/扩展、共享或外部资源、不匹配的占位符/VML、保护和预算失败保留原文与历史。结构化复制沿用既有规则、合并、表格及绘图组合的资源保护；普通值编辑可保留线程。实现归 [`thread-read.mbt`](../../../modules/formats/src/xlsx/thread-read.mbt)、[`thread-edit.mbt`](../../../modules/formats/src/xlsx/thread-edit.mbt)和 [`thread-fallback.mbt`](../../../modules/formats/src/xlsx/thread-fallback.mbt)。原生源依据 [ONLYOFFICE ThreadedComments.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/XlsxFormat/Comments/ThreadedComments.cpp#L350-L510)，占位协调依据 [PrepareComments](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/XlsxFormat/Worksheets/SheetData.cpp#L5795-L5905)，未复制上游执行代码。

### 数据验证

普通 `dataValidation` 支持创建、修改、清除及核心输入校验，覆盖整数、小数、日期、时间、文字长度、列表和自定义公式，以及八种比较运算。源的 `showErrorMessage` 为 true 才限制输入，`allowBlank` 允许空值。日期和时间比较已有数值序列或公式结果，沿工作簿的 1900/1904 日期系统；不新增宿主日期字符串猜测。文字长度使用 UTF-16 单元。重叠范围沿源顺序选择首个规则，规则自身的多个范围使用首段锚点平移相对引用。

`SpreadsheetEditor.objects.editSheet({ action: "validation", range, rule })` 复用同步 Wasm、Worker 和 `XlsxClient.execute({ operation: "editXlsxSheet", revision, sheet, change })`。`rule` 为 `XlsxDataValidation`，null 清除目标范围的验证。新增和修改不改写已有值；相交旧规则扣除选区，范围外规则及相对公式保持含义。整列仍是范围描述，不展开空格子。一次提交一项精确历史，无变化不新增历史。未知规则属性、保留的注释/处理指令、非默认输入法设置及扩展验证保护修改；预算或公式检查失败不留下半项操作。实现归 [`validation-edit.mbt`](../../../modules/formats/src/xlsx/validation-edit.mbt)。

| `XlsxDataValidation` 字段 | 内容 |
| --- | --- |
| `kind` | `none/whole/decimal/date/time/textLength/list/custom`；none 允许任意值并保留提示 |
| `operator` | `between/notBetween/equal/notEqual/lessThan/lessThanOrEqual/greaterThan/greaterThanOrEqual` |
| `formula1/formula2` | 已支持的公式；比较范围需要两项，列表使用带引号的逗号文字或单行/单列引用 |
| `allowBlank/showErrorMessage` | 空值策略及是否检查非法输入 |
| `errorStyle/errorTitle/error` | `stop/warning/information`、错误标题和信息 |
| `showInputMessage/promptTitle/prompt` | 是否显示输入提示、提示标题和正文 |
| `showDropDown` | true 隐藏列表下拉；沿 OOXML 的反向开关保存 |

标题最多 32、提示/错误正文最多 255 UTF-16 单元。核心 `DataValidation::default()` 使用允许空值、启用停止错误的 1–10 整数规则。默认属性面板编辑以上字段，应用及清除只作用于所选范围。原生草稿沿现有队列先独立提交，规则变更可另行撤销。

`XlsxQuery.dataValidation` 返回选区首格的 `rule`、是否混合的 `mixed`、编辑保护原因、列表文字 `options/optionsReason` 及有效 `promptVisible`。规则公式已相对选区首格换算，混合查询和整列覆盖有范围片段及工作量上限。输入提示遵守工作表的 `disablePrompts`。`{ action: "validationValue", index, sourceRevision }` 选择当前单格或合并格的候选值；`sourceRevision` 使用显示选项时的 query revision，过期选择拒绝。核心重新读取列表，保留引用值类型，字面列表保持文字，等号开头的选项不执行为公式；选择与重算共用原值事务和历史。

自定义条件和边界公式复用既有公式解析、引用与计算，读取整次候选写入和受影响计算结果。字面列表按逗号拆分、移除每项开头的空格并按原文比较；单行/单列列表引用保留值类型。未知公式、名称/扩展引用、未知规则属性及扩展验证继续保护相关输入。每表最多检查 4096 条规则，单个列表最多 4096 项或单元格，验证共享 1048576 个求值步骤预算；规则公式各不超过 8192 UTF-16 单元。失败发生在缓存写回、自动尺寸、源提交和历史之前，整块粘贴不会留下部分值。

失败使用 `validation-stop` 或 `validation-warning`，消息包含表名、单元格及源错误标题/文字。同步 Wasm 和 `XlsxClient.execute({ operation: "replaceXlsx", revision, sheet, range, values, literal: false, acceptWarnings: false })`、`execute({ operation: "pasteXlsx", revision, text, acceptWarnings: false })` 提供显式警告授权。授权后仍重算并检查所有目标，只允许 `warning/information`，不绕过 `stop`、未知规则或预算。查找替换沿共享值事务校验，暂不提供警告授权参数。验证不因依赖值变化重新拒绝未直接修改的格子，也不重验撤销/重做。

`SpreadsheetEditor.acceptValidationWarnings` 默认为 false，作用于该编辑器的原生输入和粘贴。默认公式栏提供对应复选框，启用后允许这些输入触发警告，直至关闭或更换文档。非法原生输入保留草稿和焦点，用户可纠正、取消或启用警告后重试；停止规则始终生效。现有规则 XML、值类型、其他部件及精确历史保持。普通验证元数据不再阻止打印/PDF，输出仍使用原值和样式；未支持的条件格式及其他未呈现内容继续保护输出。命名/扩展公式和更广导入变体仍待兼容扩展。行为参考 [ONLYOFFICE 数据验证](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/model/DataValidation.js#L516-L619)，输入实现归 [`data-validation.mbt`](../../../modules/formats/src/xlsx/data-validation.mbt)。

### SUBTOTAL 汇总

`SUBTOTAL(function_num, ref1, ...)` 复用原生公式栏、公式解析和依赖图，支持总计 2–255 个参数。编号 1–11 依次执行 AVERAGE、COUNT、COUNTA、MAX、MIN、PRODUCT、STDEV、STDEVP、SUM、VAR、VARP；101–111 执行同一运算并排除手动隐藏行。两组均排除筛选隐藏，隐藏列不影响结果。引用格的公式只要含 SUBTOTAL，就排除该格，避免嵌套重复计数；不沿普通引用继续追踪嵌套。求值使用当前类型值，支持同表/跨表单格和矩形及多区域参数，重叠引用按出现次数计入。命名、三维、数组与引用返回形式仍按既有公式边界处理。

数值参与统计，引用文字、布尔与空白通常不参与数值统计；COUNTA 包括文字、布尔、空串公式与错误，COUNT 只计引用数值。PRODUCT 沿所选 ONLYOFFICE 行为转换引用中的有限数字文字，其余文字忽略。直接标量复用数值转换，直接错误先传播；COUNT 可忽略引用错误，COUNTA 计入引用错误，其余统计传播已纳入的引用错误。无数值时 SUM、PRODUCT、MIN、MAX 返回 0，平均、方差和标准差返回 `#DIV/0!`；样本统计不足两项也返回 `#DIV/0!`，总体单项统计返回 0。方差按有界在线均值/平方偏差计算，避免直接相减平方和造成的大数误差。非有限结果返回 `#NUM!`；无效或非整数编号返回 `#VALUE!`。所有读取、嵌套解析和汇总共用现有公式工作量、深度及引用上限，整列空域按实际单元格处理，不展开稠密矩阵。

已有[隐藏来源扩展](xlsx-editing.md#值筛选)时，1–11 仅排除 `filtered`，101–111 排除实际零高行；手动与筛选重叠时两组均排除。没有扩展的外部活动值筛选无法确定隐藏来源，此时 SUBTOTAL 将筛选体内全部已隐藏行视为筛选隐藏，筛选外隐藏行仍视为手动隐藏；重新应用后使用保存的来源。此限制也适用于外部程序丢弃扩展的文件。筛选/清除/移除/重新应用和手动行高变更在同一事务重算相关工作簿公式，缓存、跨表依赖和精确历史一起更新。没有 SUBTOTAL 的筛选继续保留原公式源及 calcChain，不为可见性变更重写无关缓存。撤销重做、保存重开、网格和 PDF 使用同一结果。

编号与嵌套排除参考 [ONLYOFFICE cSUBTOTAL](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L5087-L5243)及[引用读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L1195-L1213)。两类隐藏、隐藏列与嵌套结果同时按 [SUBTOTAL 合同](https://support.microsoft.com/en-us/excel/functions/subtotal-function)处理；对本项目记录的手动来源不采用旧上游“存在筛选就跳过全部隐藏行”的捷径。实现归 [`formula-subtotal.mbt`](../../../modules/formats/src/xlsx/formula-subtotal.mbt)。

### 显示与计算

`MDETERM(matrix)` 接受一个普通方阵引用，包含限定工作表与名称引用。复用共享公式、依赖、原生缓存、结构平移、精确历史和保存重开。`A1:A1` 返回该格数值，直接单格 `A1` 和其他标量按主参考返回 `#N/A`；非方阵返回 `#VALUE!`，缺格、空白和文字返回 `#N/A`。布尔和错误按原生数值转换参与消元，通常返回 `#N/A`；原生全零主元列会提前返回 0。最终 NaN 为 `#N/A`，无穷为 `#NUM!`。

行列式使用最大绝对主元和无分数消元，保留原生运算顺序、交换行后的符号及零主元提前结束。先扫描已存格检查缺格，再按公式工作预算分配方阵；主元扫描、交换及每次消元都计入预算。实现归 [formula-determinant.mbt](../../../modules/formats/src/xlsx/formula-determinant.mbt)，依据 [ONLYOFFICE MDETERM](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L2651-L2740)，未复制上游执行代码。通用数组表达式和跨多表范围继续保护。

`SUMX2MY2/SUMX2PY2/SUMXMY2` 接受两个数值标量或同尺寸矩形引用，分别累加 `x²-y²`、`x²+y²` 和 `(x-y)²`。矩阵的行数与列数分别匹配，单格可与 1×1 范围配对；反向端点沿既有矩形解释。矩阵元素必须为数值，文字、布尔、空白、缺格及错误均返回 `#VALUE!`；直接标量错误按参数顺序传播，其他非数值标量为 `#VALUE!`。最终非有限值为 `#NUM!`，保留原生运算顺序和消去行为。

限定工作表的范围保留原生第三维，两项均限定时逐格配对；限定与未限定范围混用按主参考返回 `#VALUE!`。名称展开保留本地引用形式，不把未限定引用改成限定引用；名称定义中的限定引用保持不变。整列不分配稠密矩阵，读取已存位置并检查缺格，沿既有公式工作预算。依赖、共享公式、原生缓存、结构变化、历史及保存重开共用已有事务。实现归 [formula-paired-squares.mbt](../../../modules/formats/src/xlsx/formula-paired-squares.mbt)，依据 [ONLYOFFICE sumxCalc](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L109-L199)、[三个运算符](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L5789-L5862)和[限定范围矩阵](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L1754-L1778)。未复制上游执行代码；通用数组和跨多表范围继续保护。

`SERIESSUM(x, n, m, coefficients)` 使用四个参数，按系数累加 `a[i] * x^(n+i*m)`。前三项沿现有数值转换；直接布尔为 `#VALUE!`，直接空白为 `#N/A`，空串转零。一格显式范围先取格值再转换，因此范围布尔和空白分别可转为 1/0 和 0；多格范围为 `#VALUE!`。系数可为数值标量或矩形引用。标量文字、布尔及错误返回 `#VALUE!`，空白为 `#N/A`。范围按行优先读取，数字文字可转换，错误按序传播；已存储空格为 `#N/A`，布尔为 `#VALUE!`。不存在的格跳过，但保留其指数位置。

范围中无效幂按主参考作为零参与累计；标量的无效幂及最终非有限值返回 `#NUM!`。读取和幂计算共用工作预算，整列范围不展开稠密数组。名称、共享、跨表、原生缓存、结构修改、精确历史和保存重开沿普通事务。实现归 [formula-series-sum.mbt](../../../modules/formats/src/xlsx/formula-series-sum.mbt)，依据 [ONLYOFFICE SERIESSUM](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L4700-L4857)及[按坐标读取范围](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L1225-L1243)。未复制上游执行代码；通用数组继续保护。

`MULTINOMIAL(number1, ...)` 接受 1–255 个参数，按原始数值总和的阶乘除以各项阶乘。每次阶乘独立向下取整，例如 `MULTINOMIAL(2.5,2.5)=30`。负数为 `#NUM!`，原始总和大于 170 为 `#VALUE!`；错误按读取顺序传播。直接文字、布尔和空白为 `#VALUE!`。单格引用先按主参考比较原始值，因此负数文字返回 `#NUM!`；范围中的文字仍为 `#VALUE!`。范围按行列顺序读取实际格，省略不存在的格，保留显式空格的类型错误，重叠引用重复计入。读取和阶乘乘法共用工作预算，名称、共享、跨表、缓存、结构修改、精确历史及重开复用普通事务。实现归 [formula-multinomial.mbt](../../../modules/formats/src/xlsx/formula-multinomial.mbt)，依据 [ONLYOFFICE MULTINOMIAL](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L3189-L3290)、[阶乘](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/editorscommon.js#L113-L126)及[稀疏范围取值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L1195-L1214)。未复制上游执行代码；通用数组继续保护。

`QUOTIENT(numerator, denominator)` 使用两个参数，沿既有数值转换和错误传播。分母为零返回 `#DIV/0!`，非有限商返回 `#NUM!`。普通商向零截断；沿主参考的 JavaScript `parseInt`，绝对值至少为 `1e21` 或非零且小于 `1e-6` 的商先转科学计数法，再取尾数的整数部分。例如 `QUOTIENT(1e21,1)=1`、`QUOTIENT(-1.5e-7,1)=-1`。该行为不承诺与其他 Office 引擎等价。单格、一维范围及整列隐式取值、名称、共享、跨表、缓存、结构修改、精确历史和重开复用普通计算事务。实现归 [formula-numeric.mbt](../../../modules/formats/src/xlsx/formula-numeric.mbt)，依据 [ONLYOFFICE QUOTIENT](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L3660-L3735)，未复制上游执行代码。通用数组继续保护。

`MROUND(number, multiple)` 使用两个参数，沿既有数值转换和错误传播。倍数为零返回 0，非零异号返回 `#NUM!`。同号按主参考的 15 位有效数字修正后取最近倍数，半值向远离零的方向取整。修正后的商沿原生 `ToInt32` 转为有符号 32 位整数，因此大数会回绕，例如 `MROUND(2147483648,1)=-2147483648`；中间非有限数或精度尺度下溢沿该转换得到零。普通输入、单格/一维范围/整列隐式取值、名称、共享、跨表、缓存和结构修改复用相同计算事务，支持精确历史和重开输入。实现归 [formula-numeric.mbt](../../../modules/formats/src/xlsx/formula-numeric.mbt)，依据 [ONLYOFFICE MROUND](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L3085-L3200)，未复制上游执行代码。通用数组继续保护。

`COMBIN/COMBINA` 各接受两个参数，先转换数值并依次传播错误，再拒绝任一原始负数或第一项小于第二项。COMBIN 沿主参考的阶乘商计算，分别向下取整 `n`、`k` 和原始差 `n-k`，例如 `COMBIN(5.1,2.9)=30`。阶乘上限为 170；超出时通常为 `#NUM!`，原始两项相等的 COMBIN 仍返回 1。COMBINA 先按原生十进制整数转换，再计算 `fact(n+k-1)/(fact(k)*fact(n-1))`，因此 `COMBINA(0,0)` 和原始 `n<k` 均为 `#NUM!`；大于等于 `1e21` 或小于 `1e-6` 的正数按科学记法首部转整数。单格/一维范围、名称、共享及跨表依赖复用现有隐式取值与重算，乘法逐次花费工作预算。读取接受裸名称及 `_xlfn.COMBINA`；新输入与共享展开保存原生前缀，结构修改保留导入源写法。缓存、精确历史、重开和输出沿同一事务。实现归 [formula-numeric.mbt](../../../modules/formats/src/xlsx/formula-numeric.mbt)，依据 [ONLYOFFICE COMBIN/COMBINA](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L1114-L1266)及[阶乘商](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/editorscommon.js#L113-L168)，未复制上游执行代码。通用数组继续保护。

`FACT/FACTDOUBLE` 各接受一个参数，先按普通数值规则转换，再拒绝负数并截去小数。FACT 逐个整数递减相乘，截断值最多 170；FACTDOUBLE 每次递减 2，截断值最多 300。零和小于 1 的非负数均返回 1；负数、超出上述界限或非有限结果为 `#NUM!`，类型与已有错误按原数值规则传播。单格、单行或单列范围复用现有隐式取值，不能确定唯一位置时为 `#VALUE!`；名称和跨表范围沿同一规则。乘法逐次花费公式工作预算，超限拒绝整个事务，IFERROR 不吞掉资源失败。两项已移出未计算隔离，沿普通依赖、共享公式、原生缓存、结构平移、精确历史和保存重开计算。实现归 [formula-numeric.mbt](../../../modules/formats/src/xlsx/formula-numeric.mbt)，规则依据 [ONLYOFFICE FACT/FACTDOUBLE](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L1786-L1895)、[FACT 的上限与乘法顺序](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/editorscommon.js#L113-L127)和[范围取值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L1308-L1323)，未复制上游执行代码。通用数组继续保护。

`GCD/LCM` 接受 1–255 个非负参数，截去小数后求最大公约数或最小公倍数。负数及超出原生整数边界的输入为 `#NUM!`；GCD 标量要求小于 `2^53`，范围允许等于该值，LCM 允许等于该值。数值文字可转换，错误按读取顺序传播。直接布尔参数及范围内布尔为 `#VALUE!`；显式空参数在 GCD 中为 `#N/A`，在 LCM 中为 1。单格引用按普通数值转换，稀疏范围只读取实际格；实际空格分别按上述空参数处理。LCM 的直接零值立即返回 0，范围仍逐格读取；连续两个范围零值的未定义中间结果最终为 `#NUM!`，后续直接零值仍可返回 0。LCM 沿上游十进制整数转换处理累计值，达到 `1e21` 时按科学记法首部转换。欧几里得迭代、范围读取和文字转换共用工作预算，失败拒绝整次编辑。名称、共享/跨表引用、结构平移、缓存、精确历史和重开复用普通计算事务；两项已移出未计算隔离。实现归 [formula-gcd-lcm.mbt](../../../modules/formats/src/xlsx/formula-gcd-lcm.mbt)，规则依据 [ONLYOFFICE GCD](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L2095-L2200)、[LCM](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L2285-L2448)及[范围/单格读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L1195-L1213)，未复制上游执行代码。通用数组仍按既有范围保护。

`RAND()` 在自动计算模式的单元格公式中返回 `[0,1)` 随机数，不接受参数。每次实际重算更新该公式及其依赖；普通查询不重新取样。名称、共享公式和跨表引用沿普通计算路径处理。宿主在打开、新建和文本导入时提供 32 字节平台随机种子，MoonBit 标准库负责各会话的随机数生成。直接调用 MoonBit API 时，可传入 `random_seed`，或使用平台可用的熵源；缺少熵源时拒绝求值，保留源和历史。撤销/重做恢复原计算值及链接目标，易变结果计入既有历史预算。元数据事务也同步重算后的缓存。条件格式、验证等单元格以外的 RAND 求值仍待实现；手工模式规则如下。规则依据 [ONLYOFFICE RAND](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L3782-L3795) 的零参数、易变标记和随机区间；随机序列不要求相同。实现归 [formula-random.mbt](../../../modules/formats/src/xlsx/formula-random.mbt)及既有计算、事务和历史路径。

手工计算工作簿打开时读取源缓存，不重新取样 `RAND`。数据或元数据编辑保留既有公式结果；输入新公式时只计算该公式，依赖公式继续使用缓存。`XlsxSession.execute({ operation: "recalculateXlsx", revision })`、`XlsxClient.execute({ operation: "recalculateXlsx", revision })` 和 `SpreadsheetEditor.data.recalculate()` 显式重算工作簿，默认公式栏提供“立即重算”按钮。公式、共享/跨表依赖、原生图表数据缓存和尺寸适配沿现有事务提交一项历史；撤销/重做恢复原值及源字节。普通查询和保存不触发取样，重开手工文件继续读取已保存的结果。保存保留 `calcMode`、`calcOnSave` 和导入重算标记；SDK 快照保存沿上述显式重算规则执行。

含公式来源的手工图表显示原生缓存，显式重算后更新数据点；只有普通值来源的图表继续即时更新。手工模式不会解除未知公式、循环依赖、保护及资源上限；显式计算遇到不能计算的公式时原子拒绝，保留源、缓存和重做。缓存缺值保持空值，直到输入公式或显式计算。原生图表的配置改写及复制边界保持。实现归 [`calculation.mbt`](../../../modules/formats/src/xlsx/calculation.mbt)、[`recalculate.mbt`](../../../modules/formats/src/xlsx/recalculate.mbt)和既有事务。依赖刷新与历史沿 [ONLYOFFICE 工作簿计算](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/cell/model/Workbook.js#L4310-L4342)；手工模式及新公式求值依据 [Excel 计算规则](https://learn.microsoft.com/en-us/office/vba/excel/concepts/excel-performance/excel-improving-calculation-performance)。固定版主参考在打开时仍会重算 RAND，补充引擎也改写缓存，其输出只用于数值核对；缓存保留直接对照冻结输入。

手工折线图、原生散点图、原生三维柱条图及原生面积图的来源均可读取时，已知源错误对应的系列值缓存零读作空点。数据目录报告空值；真实数值零和其他缓存点保持。面积图的空点仍沿现有堆积绘制规则处理。保存保留源错误及图表缓存，不把绘制判定写回原件。

`SIN/COS/TAN`、`RADIANS/DEGREES` 和 `PI` 已实际求值，复用普通数值转换、依赖重算、原生缓存和精确历史。三角函数读取弧度，角度换算显式执行；`PI()` 不接受参数，其余五项接受一个参数。数值文字、布尔、空白格及错误传播沿普通标量规则；参数数量错误拒绝整次编辑，非有限算术结果为 `#NUM!`。保留浮点微小结果，不把接近零的三角值截成零，也不把接近正切极点的有限结果改成除零错误。角度换算沿先乘后除的顺序，大数的中间乘积溢出同样返回 `#NUM!`。

`ACOS/ASIN/ATAN/ATAN2` 已接通相同的数值转换、依赖计算、原生缓存及精确历史。前三项各接受一个参数并返回弧度；`ACOS/ASIN` 的输入超出 -1–1 时返回 `#NUM!`。`ATAN2(x_num, y_num)` 接受两个参数，按坐标象限返回弧度；两坐标都是零时返回 `#DIV/0!`。计算直接使用 `atan2(y, x)`，避免先求商造成溢出或丢失象限。参数数量错误拒绝整次编辑，类型和错误传播沿普通数值规则；通用数组及范围隐式交集继续保护。它们支持导入公式、名称/共享/跨表引用、结构平移、保存重开和后续原生输入，旧导入缓存不再代替计算结果。规则对照 [ONLYOFFICE ACOS](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L227-L259)、[ASIN](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L648-L681)及 [ATAN/ATAN2](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L724-L829)，标量预期另核对其[独立测试](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/mathematicTests.js#L596-L644)。复用 MoonBit 标准数学函数，未复制执行代码。

`EXP/LN/LOG/LOG10` 已接通普通依赖重算、原生缓存及精确历史。`EXP`、`LN` 和 `LOG10` 各接受一个参数；`LOG(number, base)` 的底数省略时为 10，显式空参数仍按空白转换。对数的数值或底数非正时返回 `#NUM!`，有效数值配底数 1 返回 `#DIV/0!`；EXP 溢出返回 `#NUM!`，下溢可为零。类型转换和错误传播复用普通数值规则，先传播参数错误，再检查定义域。导入旧缓存不再代替实际计算；名称、共享/跨表引用、结构平移及保存重开沿同一事务。依据 [ONLYOFFICE EXP](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L1745-L1788)及[对数函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L2451-L2649)，EXP 标量与极值另核对[独立测试](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/mathematicTests.js#L8136-L8321)。复用 MoonBit 标准数学函数，未复制执行代码。

`ACOSH/ASINH` 各接受一个参数，复用数值转换、错误传播与有限结果检查。ACOSH 在输入小于 1 时返回 `#NUM!`，输入为 1 时返回 0；ASINH 保留正负号与极小非零值。两者支持极大有限输入，沿既有依赖、缓存、结构平移和精确历史保存重开。参数数目错误拒绝编辑。标量语义依据 [ONLYOFFICE ACOSH](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L265-L302)与 [ASINH](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L686-L723)，数值另核对[独立测试](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/mathematicTests.js#L849-L867)。复用 MoonBit 标准数学函数，未复制执行代码。

`ATANH` 接受一个标量，定义域为 `-1 < x < 1`；端点及域外返回 `#NUM!`。它保留正负号和极小非零值，沿现有数值转换、错误传播、依赖、缓存与编辑事务求值；参数数量错误拒绝编辑，不写 `_xlfn.` 前缀。实现复用 MoonBit 标准数学函数和有限结果检查，标量规则依据 [ONLYOFFICE ATANH](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L833-L873)，数值另核对[独立测试](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/mathematicTests.js#L3393-L3430)，未复制执行代码。

`SINH/COSH/TANH` 各接受一个参数，复用普通数值转换、错误传播和有限结果检查。SINH 保留输入符号，COSH 对正负输入对称；两者溢出时返回 `#NUM!`。TANH 对极大正负数趋于 1/-1，标准数学函数保留极小非零输入。导入、名称/共享/跨表引用、结构平移、原生缓存、精确历史及保存重开沿已有计算事务。参数数目错误拒绝编辑。标量规则依据 [ONLYOFFICE COSH](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L1306-L1343)、[SINH](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L4971-L5008)及 [TANH](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L5898-L5935)，零值、符号与文字数值另核对[独立测试](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/mathematicTests.js#L5608-L5634)。复用 MoonBit 标准数学函数，未复制执行代码。

这些函数支持现有名称、共享及跨表引用，首次查看计算但保留源缓存，后续有效事务同步实际值；普通输入、引用变换、保存重开及 PDF 沿同一结果。`SIN/COS/TAN` 不再属于未计算链。数组及动态引用仍按既有范围保护。实现归 [formula-numeric.mbt](../../../modules/formats/src/xlsx/formula-numeric.mbt)，规则参考 [ONLYOFFICE SIN](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L4907-L4940)、[角度换算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L3740-L3773)及[独立标量用例](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/mathematicTests.js#L18936-L18960)。复用 MoonBit 标准数学函数，未复制上游执行代码。

读取共享/内联字符串、数值、布尔值、错误、公式及缓存。富文本读出文字，保留原 XML并保护编辑。受保护工作表及含未知编辑语义的单元格只读。图表、未支持的条件格式、绘图等未呈现内容给出诊断，继续保留源部件。

网格读取行高、列宽、隐藏行列与合并区域。核心使用 Normal 字体和字号的最大数字宽度换算列宽；不依赖 DOM 度量。字体键沿用 `family|bold|italic`，宿主明确映射到已添加的字体身份。支持字体大小、粗斜体、基本文字色、纯色填充、实线边框、左中右/上中下对齐与换行。行列尺寸使用声明值，显式自动适配命令更新这些值；自动模式的内容和列宽变化在文档事务内同步尺寸。数字宽度不足时显示 `#`；文字按单元格裁剪。

数字展开先按 ONLYOFFICE 的 15 位有效数字消除二进制尾数，供固定小数、百分比和科学计数共用。General 默认按[原生显示掩码](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/NumFormat.js#L3377-L3530)的 11 字符预算选择普通或科学记法、舍入并去除尾零。例如 `20.009999999999998` 显示 `20.01`，`1234560000000` 显示 `1.23456E+12`。宽列中的精确小数 `0.000000001` 保留普通记法，更小的 `0.0000000001` 显示 `1E-10`。查询、TEXT、纯文字剪贴板、筛选标签和按显示文字去重保留默认预算。去重仍须先预览并由显式事务提交。计算、类型值、公式文字转换及 XLSX 源缓存保留原精度。

普通水平 General 数值在网格和 PDF 中按列宽调整显示精度。核心从 Normal 字体的最大数字宽度计算 1–11 的起始预算，再用当前样式逐次测量，减少精度直到文字可容纳；仍放不下时沿原有规则填充井号。科学计数的进位会按剩余预算重新选择掩码。该路径遵循 [ONLYOFFICE 逐次测量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L17424-L17471)。公式视图、旋转、换行、缩小适配、填充和分散对齐保持各自路径。五种列宽下的 80 个独立原生显示值通过，含固定小数控制；控制文件的完整 Canvas/PDF 均为 0/0，源字节保持。实现归 [`number-general.mbt`](../../../modules/formats/src/xlsx/number-general.mbt)与 [`grid-cells.mbt`](../../../modules/formats/src/xlsx/grid-cells.mbt)。

内置日期 14 按固定英语短日期显示为 `m/d/yyyy`，保留原生 ID 和数值；它与显式 `mm-dd-yy` 自定义代码分别处理。无效日期按[原生重复 `#` 规则](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/NumFormat.js#L2058-L2067)填满可用宽度。重复文字计入既有 262144 单元预算，超限保留源和历史；文字常量中的 `#` 不作为溢出处理。C42 的 D7/F7/G7 与原生整页核对。

数字格式目录提供 General、`@`、整数、0–4 位小数的普通/千分位/百分比、两位小数的美元与人民币、科学计数和日期时间，以及内置 1–4、9–11、14–22、46、49。自定义固定小数支持 0–30 位，沿用下述分节语法。核心、严格传输和默认控件使用同一支持范围。小数、百分比及缩放整数共用 15 位有效数字的十进制移位、舍入和进位，不先做浮点缩放。`1.005` 的两位小数为 `1.01`，`0.10005` 的两位百分比为 `10.01%`；大数 `1234560000000` 仍显示 `123456000000000.00%`。数值、公式和源缓存保持原精度。查询、TEXT、测量、网格和 PDF 共用结果；公式视图中的数值与货币显示原值，百分比显示未固定小数位的比例值。转义或引号内的 `%` 保留文字语义。日期保留数值，核心解释 1900/1904 系统，1900 序号 60 显示虚构的 2 月 29 日，序号 0 显示 1900-01-00，不使用宿主时区。其他格式保留声明并诊断。

数字分节接受最多四段，按正数、负数、零和文字选择；两段或三段中的末段 `@` 也可作为文字段。每段可带八个原生命名颜色之一，`Green` 为 `00ff00`。整数部分支持可选 `#/?` 前缀、`0` 后缀及千分组，小数部分只接受固定 `0`。数字占位末尾每个未转义的逗号把显示值除以 1,000，可与千分组、小数、百分比和分节组合。引号内或反斜杠转义的逗号仍按文字显示。每段至多一组数字或一个 `@`，支持引号、反斜杠文字和重复百分比。负数专用段使用绝对数字；自动负号在舍入成零时省略。未转义的 `+/-` 按原值符号显示，转义符号保持文字。规则依据 [ONLYOFFICE 分节选择](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/NumFormat.js#L2860-L2960)与[符号处理](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/NumFormat.js#L2438-L2458)。实现归 [`number-sections.mbt`](../../../modules/formats/src/xlsx/number-sections.mbt)与 [`number-section-display.mbt`](../../../modules/formats/src/xlsx/number-section-display.mbt)。 [Excel 自定义数字格式](https://support.microsoft.com/en-us/excel/review-guidelines-for-customizing-a-number-format)

`_x` 预留字符宽度但不绘制或提取文字，缺少的 `?` 位预留零字宽。`*x` 按剩余单元格宽度重复字符，列宽适配只计自然宽度。会计零值的 `DispValue` 保留 `-`，绘制另补空白；`TEXT` 不包含隐藏和重复填充。间距片段共用字体测量、颜色、缩小字体及文字预算。当前带 `_/*/?` 间距的格式仅支持单行、零旋转及普通对齐；换行、旋转和分散等组合明确拒绝。普通数字或颜色段继续复用既有文字布局。条件分节、分数及科学计数分节仍受保护。日期只支持下述区域文字段。实现归 [`number-section-layout.mbt`](../../../modules/formats/src/xlsx/number-section-layout.mbt)。C42 的全部七项自定义源代码和十三个样式现可读取；B2:I6 的四十个显示值及 B8/B9/B10 匹配原生 FormatTest。另五处 General/内置日期按同版原生输出核对。原件及默认控件修改后的全部三页 Canvas/PDF，在固定 Noto 字体替代下均为 0/0；不授予其他字体或上述未支持组合的资格。

科学计数接受一位整数占位 `0`、0–30 位固定小数及 `E+` 或 `E-` 后的 1–6 个零。指数位数为最小补齐位数；`E+` 保留正号，`E-` 省略非负指数的正号。`E/e` 不区分大小写，显示统一使用 `E`。尾数使用既有 15 位有效数字，处理进位而不重解析 Double，避免最大有限数及次正规数归一化溢出。文字、布尔、错误和空白保留原显示。内置 11 读取为 `0.00E+00`；导入自定义精度保留源代码。非法、超长掩码及尚未支持的颜色、分节、工程计数等组合继续保护。实现归 [`number-scientific.mbt`](../../../modules/formats/src/xlsx/number-scientific.mbt)。C42 原件 B4:I4 的八个显示值按 [ONLYOFFICE FormatTest](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/Test/Applications/AVSOfficeEWSEditorTest/AVSOfficeEWSEditorTest/Tests/FormatTest.cs#L284-L355)逐项核对。

整数掩码接受 `0` 占位、引号文字、反斜杠转义，以及紧接最后占位的尾随逗号；代码最长 256 个 UTF-16 单元。每个尾随逗号把显示值缩小一千倍，按既有 15 位有效十进制数字移位后舍入，不先做浮点除法。占位不足时补零，多余整数位写入第一个占位；舍入成零时省略负号。原数值、公式和缓存保持不变。`0\-0,,` 将 `1234560000000` 显示为 `123456-0`，将 `-25.78` 显示为 `0-0`。普通整数、小数和分节共用该十进制数字展开。`TEXT`、查询、网格和 PDF 共用结果，公式视图中的转义 `%` 保留文字语义。实现归 [`number-integer.mbt`](../../../modules/formats/src/xlsx/number-integer.mbt)，规则参考 [ONLYOFFICE 缩放与舍入](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/NumFormat.js#L1290-L1430)及[整数占位](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/NumFormat.js#L1608-L1676)。C42 原件 B6:I6 按同一原生 FormatTest 的八个预期逐项核对。可选整数位和分组沿上述分节语法；尾随逗号与其他格式组合继续保护。

自定义日期代码复用同一格式化路径，最长 256 个 UTF-16 单元。支持 `yy/yyyy`、`m/mm/mmm/mmmm/mmmmm`、`d/dd/ddd/dddd`、`h/hh`、`s/ss`、`AM/PM`、秒后的三位毫秒 `.000`、引号文字和反斜杠转义。默认语言为英语。`ddd` 与 `dddd` 使用工作簿的 1900 或 1904 日历。`mmmmm` 显示完整月份名称的首字符。英文 LCID 及上游未映射的 `F000`–`FFFF` 系统代码沿用默认语言。`m/mm` 按相邻时间字段区分月份和分钟，忽略中间文字。`TEXT` 保留引号文字大小写。毫秒进位及无毫秒格式的秒舍入遵循 [ONLYOFFICE NumFormat](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/NumFormat.js#L1182-L1280)和[日期拆分](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/NumFormat.js#L1533-L1606)，不使用宿主时区。星期和月份首字符遵循 [ONLYOFFICE 名称格式化](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/NumFormat.js#L2349-L2386)。实现归 [`number-date.mbt`](../../../modules/formats/src/xlsx/number-date.mbt)。默认格式面板保留当前导入代码的可选项。C42 的 B8/B9/B10 显示按同一原生 FormatTest 核对。

区域前缀 `[$-LCID]` 支持中文 `404/804/C04/1004/1404/7804/7C04`、日语 `11/411` 和韩语 `12/412` 的公历日期。使用源代码的月份、星期和上午下午名称。`aaa/aaaa` 分别等同于 `ddd/dddd`，可附加文字段 `;@`。其他区域标记、纪年代码和系统长日期 `F800` 继续受保护。[ONLYOFFICE 区域表](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/NumFormat.js#L6050-L6188)

累计时长接受一个 `[h]`、`[m]` 或 `[s]` 字段，重复字母可补齐两位。可与普通时分秒及一到三位小数秒组合。内置格式 46 使用 `[h]:mm:ss`。累计量以天数折算，不随 1900/1904 日期系统变化，负数沿用日期溢出显示。填充序列继续按数值时长计算，公式视图显示原序号。[ONLYOFFICE 累计时长对照](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/NumFormatParse.js#L650-L690)

公式支持数值、字符串和布尔常量，括号、一元正负、`+ - * / ^`、后缀百分比 `%`、文本连接 `&`、比较、A1 单格/矩形、整行/整列范围、绝对/混合引用、带引号的跨表引用，以及 `SUM/AVERAGE/MIN/MAX/COUNT/IF/AND/OR/XOR/NOT/IFERROR/IFNA/ISBLANK/ISNUMBER/ISTEXT/ABS/SIGN/CEILING/FLOOR/TRUNC/CEILING.MATH/FLOOR.MATH/CEILING.PRECISE/FLOOR.PRECISE/INT/MOD/MROUND/QUOTIENT/ROUND/ROUNDUP/ROUNDDOWN/SQRT/POWER/SIN/COS/TAN/SINH/COSH/TANH/ACOSH/ASINH/ATANH/ACOS/ASIN/ATAN/ATAN2/EXP/LN/LOG/LOG10/PI/RADIANS/DEGREES/FACT/FACTDOUBLE/COMBIN/COMBINA/MULTINOMIAL/SERIESSUM/SUMX2MY2/SUMX2PY2/SUMXMY2/MDETERM/GCD/LCM/PRODUCT/MEDIAN/MODE/MODE.SNGL/LARGE/SMALL/SUMSQ/SUMPRODUCT/DEVSQ/VAR/VAR.S/VARP/VAR.P/STDEV/STDEV.S/STDEVP/STDEV.P/LEN/LEFT/RIGHT/MID/TRIM/UPPER/LOWER/CONCAT/CONCATENATE/TEXTJOIN/FIND/SEARCH/SUBSTITUTE/EXACT/REPT/TEXT/DATE/YEAR/MONTH/DAY/TIME/HOUR/MINUTE/SECOND/DAYS/WEEKDAY/WEEKNUM/ISOWEEKNUM/COUNTA/COUNTBLANK/COUNTIF/COUNTIFS/SUMIF/SUMIFS/AVERAGEIF/AVERAGEIFS/MINIFS/MAXIFS/INDEX/MATCH/VLOOKUP/HLOOKUP/XLOOKUP/ROW/COLUMN/ROWS/COLUMNS/SUBTOTAL/HYPERLINK`。范围端点可以反向，核心按矩形解释。显式省略的函数参数作为空白处理，仍检查各函数参数数量。

`&` 将两个值按普通公式文字规则连接，布尔使用 TRUE/FALSE，空白使用空文字，公式错误按左侧优先传播。它低于加减、高于比较，同级从左到右；括号保留明确的计算顺序。一行/一列引用按公式位置取唯一值，其余非单值矩形返回 `#VALUE!`。它与 HYPERLINK 复用 [`formula-range.mbt`](../../../modules/formats/src/xlsx/formula-range.mbt) 中的标量取值，与文本函数共用 32767 个 UTF-16 单位及 1048576 单位工作预算；超长结果为 `#VALUE!`，工作量超限拒绝整次编辑。共享公式、填充、工作表改名与重开沿普通 token/引用路径，字符串常量内的表名或 `&` 保持文字。规则参考 [ONLYOFFICE cConcatSTROperator](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L4793-L4832)。例如 `HYPERLINK(A1&"#details","查看")` 使用拼接后的地址，保留既有安全导航及 PDF 规则；实现复用 [`formula-parser.mbt`](../../../modules/formats/src/xlsx/formula-parser.mbt) 和 [`formula-evaluate.mbt`](../../../modules/formats/src/xlsx/formula-evaluate.mbt)，未复制上游执行代码。

后缀 `%` 将数值除以 100，可重复使用，例如 `50%%` 为 0.005；单行/单列引用沿相同的标量取值规则。`^` 直接复用 POWER 的当前标量求值器和有限值、负数实根及错误规则；按所选 ONLYOFFICE 基线，`0^0` 为 1。优先级由高到低为前缀正负、`%`、`^`、乘除、加减、`&` 和比较；同级二元运算从左到右，`2^3^2` 为 64，`2^(3^2)` 为 512，`-2^2` 为 4。共享公式和填充将 `%` 保存到其已平移操作数之后，例如 `((A2)%^2)`，保留精确历史及重开计算。运算符保留原格数字格式：已有百分比格式可将 0.5 显示为 50%，General 继续显示 0.5；自动格式推断继续实施。规则参考 [ONLYOFFICE 百分比与乘方](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L4663-L4718)及[正负号优先级](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L4503-L4506)，实现沿 [`formula-parser.mbt`](../../../modules/formats/src/xlsx/formula-parser.mbt)、[`formula-evaluate.mbt`](../../../modules/formats/src/xlsx/formula-evaluate.mbt)和 [`formula-shift.mbt`](../../../modules/formats/src/xlsx/formula-shift.mbt)，未复制上游执行代码。

`SUMPRODUCT` 接受静态范围及其中的一元、算术、比较和文本连接表达式。名称、共享与跨表引用沿普通依赖重算；稀疏整列按已有单元格和逻辑空白区域求值，沿用工作量预算。标量函数子表达式仍使用原有求值规则，通用数组常量和数组函数形式继续实施。参数规则参考 [ONLYOFFICE SUMPRODUCT](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L5645-L5743)：数字文字转换，布尔和非数字文字计为零；单格空白引用返回 `#VALUE!`，空白范围元素计为零。顶层参数尺寸按依次增长的最大行列检查：后续较小参数返回 `#NUM!`，较早的小参数在后续坐标补空白。错误按行列及参数顺序传播。范围表达式内部的两个范围必须同尺寸；标量可参与逐元素运算。空白区域批量累计不承诺与 Excel 的浮点逐项累加位级一致。实现归 [`formula-sum-product.mbt`](../../../modules/formats/src/xlsx/formula-sum-product.mbt)。

整列 `A:A`、`$A:B` 和整行 `1:1`、`$1:2` 可带工作表限定并使用反向端点。行号只接受十进制整数，范围受 1048576 行、16384 列约束；混合行/列/单格端点拒绝。内部用一个有界矩形表示，未覆盖维度在复制时固定；原公式源码保持，复制及名称展开输出对应行列记法和 `$` 标记。依赖保留区间，聚合及条件函数查询实际单元格，空白计数按逻辑面积扣除非空值。线性查找在大范围内仅检查已有单元格及各空白区间的首个搜索位置，保留正反向、错误与近似候选规则；小范围保持直接读取，二分查找沿原路径。全部沿用工作量及输出限制，保留空项的超大连接仍可能原子拒绝。

结构编辑沿现有 [ONLYOFFICE 范围变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L675-L768)；范围末端贴住工作表上限，起点不固定在第一行/列。例如在 A 列前插列时，名称中的 `Sheet1!$2:$2` 变为 `Sheet1!B$2:XFD$2`，之后按名称调用位置求值，越界产生 `#REF!`。范围记法参考 [ONLYOFFICE getName](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L983-L1019)，稀疏值和空白数量参考 [cArea](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L1195-L1240)及[countCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L1326-L1335)。数组结果仍归 P14。

AND、OR 和 XOR 接受数值和布尔，忽略引用内的文本与空白；没有有效值时返回 `#VALUE!`。文字常量返回 `#VALUE!`，不沿用数学函数的数字转换。稀疏范围只访问已有单元格，不展开整张表；即使已有确定的布尔结果，范围和后续参数中的错误仍参与，范围内按行列顺序保留首个错误。XOR 接受 1–254 个参数，真值个数为奇数时返回 TRUE。NOT 接受布尔、数值、空白及 TRUE/FALSE 文字，其他文字返回 `#VALUE!`。三项类型判断不转换数字文字，区分空白格与空字符串；当前使用标量参数，多格范围返回 `#VALUE!`。公式结果引用空白格时计算为数值 0。

IF、IFERROR、IFNA 只求值选中的结果分支，依赖仍包含全部声明引用。IFERROR 捕获公式错误值，IFNA 只捕获 `#N/A`；两者不吞未知函数、循环、引用解析失败或资源超限。新输入及生成的 IFNA、XOR、CONCAT、TEXTJOIN、DAYS、XLOOKUP、VAR.S、VAR.P、STDEV.S、STDEV.P、MODE.SNGL、MINIFS、MAXIFS、CEILING.MATH、FLOOR.MATH、CEILING.PRECISE、FLOOR.PRECISE、ISOWEEKNUM 按 OOXML 写入对应 `_xlfn.` 函数前缀，读取也接受这些前缀；只替换函数 token，保留同名工作表和文字常量。查询继续返回实际公式源。

ABS 返回绝对值，INT 向负无穷取整；MOD 按 `n - d * floor(n / d)` 计算，零除数返回 `#DIV/0!`。三类舍入按有限 Double 的十进制表示处理，ROUND 的半值远离零，ROUNDUP 远离零，ROUNDDOWN 朝零；位数的小数部分朝零截断。ROUND 将低于半值、经 15 位有效数字舍入可恢复到半值的结果按半值处理。正负位数、进位及 `ROUND(1.005,2)=1.01` 使用同一路径，不先乘十进制倍率。精度至少 324 时保持原值；截断后的精度小于 -308 时，非零 ROUNDUP 返回 `#NUM!`，其余返回 0。结果非有限也返回 `#NUM!`，不按任意精度分配字符串。

CEILING 和 FLOOR 接受两个必需标量参数：数值和倍数。倍数为 0 返回 0，正数配负倍数返回 `#NUM!`；FLOOR 的负数配正倍数也返回 `#NUM!`。CEILING 对商向上、FLOOR 对商向下取整，并沿固定 ONLYOFFICE 修订使用带商符号的十五位容差；保留该修订的 `CEILING(-4,2)=-2` 行为。TRUNC 接受 1–2 个参数，缺省位数为 0；位数先限制到最大 20，再按绝对值半值远离零取整，随后用有限 Double 倍率截断数值。它保留 `TRUNC(0.29,2)=0.28` 等二进制缩放结果，区别于 ROUNDDOWN 的十进制路径；倍率下溢或中间值/结果非有限返回 `#NUM!`。三项复用普通数字转换、参数顺序错误传播、依赖与预算，不写 `_xlfn.` 前缀。规则依据 [ONLYOFFICE CEILING](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L934-L1013)、[FLOOR](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L1911-L1994) 和 [TRUNC](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L5946-L6049)，未复制执行代码。

SIGN 接受一个标量，返回负数 -1、零 0 或正数 1。CEILING.MATH 和 FLOOR.MATH 接受 1–3 个参数：数值、缺省为 1 的倍数、缺省为 0 的 mode；倍数符号忽略。缺省分别向正无穷和负无穷取整；负数且 mode 非零时反向，正数不受 mode 影响。CEILING.PRECISE/FLOOR.PRECISE 接受 1–2 个参数，不含 mode，分别向正/负无穷取整，倍数符号也忽略。显式空白倍数为 0；倍数或数值为 0 时结果为 0，参数错误仍按顺序传播。四项直接对有限 Double 商取 ceil/floor，再乘倍数，不额外套用 ROUND 的十进制修正；商或结果非有限时为 `#NUM!`。读写标准 `_xlfn.` 名称，结构变换后的表达式同样带前缀，查询保留实际源。规则依据 [ONLYOFFICE CEILING.MATH/PRECISE](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L1031-L1110)、[FLOOR.MATH/PRECISE](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L2011-L2088)及 [SIGN](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L4866-L4904)，未复制执行代码。

SQRT 计算非负平方根，负数返回 `#NUM!`。POWER 接受两个标量；零的负幂为 `#DIV/0!`，零的零次幂沿所选参考返回 1。负底数的非整数幂沿 [ONLYOFFICE POWER](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L3435-L3462) 计算负候选根，再以反向幂的整数舍入结果核对底数；不成立时为 `#NUM!`。非有限结果为 `#NUM!`，下溢可为 0。标量类型转换沿既有规则。

PRODUCT 按参数顺序及引用内的行列顺序相乘，重复/重叠引用按次数计入。引用中的数字文字可转换，布尔、空白与其他文字忽略，引用错误传播；直接布尔和数字文字转换，直接非法文字返回 `#VALUE!`，空参数忽略。没有数值返回 0；中间溢出立即返回 `#NUM!`，不会被后面的零消除。行为依据 [ONLYOFFICE PRODUCT](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L3574-L3665)。

MEDIAN 对实际数值排序，偶数项取中间两项的平均值。沿 [ONLYOFFICE MEDIAN](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L8541-L8620)，引用中的文字、布尔、空白及错误均忽略；直接布尔参与，直接文字忽略，直接错误及空参数返回 `#VALUE!`。没有数值也返回 `#VALUE!`，平均值的非有限结果为 `#NUM!`。PRODUCT/MEDIAN 支持跨表、名称展开和整行/列的稀疏引用，不展开空矩阵；隐藏及筛选行仍参与。遍历与排序预付现有公式工作预算，资源超限整体回滚，IFERROR 不吞资源失败。四项均参与实际依赖、缓存及精确历史，不再使用未计算保护。实现归 [`formula-numeric.mbt`](../../../modules/formats/src/xlsx/formula-numeric.mbt)及 [`formula-product-median.mbt`](../../../modules/formats/src/xlsx/formula-product-median.mbt)。

MODE/MODE.SNGL 返回出现次数最多的数，并列时取较小值；只有互不重复的数时返回 `#N/A`，没有数值返回 `#VALUE!`。两者复用已有有界数值收集与排序；引用中的文字、布尔、空白和错误均忽略，直接文字也忽略，直接布尔、错误和省略参数返回 `#VALUE!`。现代名称按标准 `_xlfn.MODE.SNGL` 读写。规则依据 [ONLYOFFICE MODE](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L8785-L8880)及[现代别名](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L8956-L8966)。

LARGE/SMALL 接受数据与标量 k，分别返回第 k 大/小值，重复值分别占位。引用文字与空白忽略，引用错误传播；LARGE 将引用布尔转为 1/0，SMALL 忽略它们。k 沿现有数值转换；沿所选 ONLYOFFICE 规则，LARGE 将正小数 k 向上取整，非正 k 先返回 `#N/A`，超过样本数为 `#NUM!`。SMALL 的范围形式只接受有效整数 k，否则返回 `#NUM!`，范围错误先传播。LARGE 要求显式区域数据，直接标量或单格引用返回 `#NUM!`；SMALL 的标量/单格形式可转换数值，且 k 必须为 1。规则依据 [ONLYOFFICE LARGE](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L7710-L7790)及 [SMALL](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L10540-L10632)，实现归 [`formula-order-statistics.mbt`](../../../modules/formats/src/xlsx/formula-order-statistics.mbt)。

四种名称均参与普通静态依赖、名称/共享/跨表重算、原生公式栏、缓存与精确历史。隐藏和筛选行仍参与，整行/列按已有单元格稀疏读取。遍历及排序消耗现有工作预算，超限不被 IFERROR 吞掉；未修改的导入公式源保留。数组与动态引用继续沿既有保护边界。

SUMSQ 按参数及引用内行列顺序累计平方和，重复引用按次数计入。直接布尔和数字文字转换，非法文字为 `#VALUE!`；引用中的文字、布尔和空白忽略。沿固定 [ONLYOFFICE SUMSQ](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L5732-L5797)，单格引用中的错误忽略，显式范围（含 `A1:A1`）及直接错误传播。没有数值返回 0，平方或累计非有限返回 `#NUM!`。跨表、名称、共享公式及整行/列稀疏引用复用已有依赖、工作预算、缓存和精确历史；不再使用未计算保护。实现归 [`formula-sum-squares.mbt`](../../../modules/formats/src/xlsx/formula-sum-squares.mbt)。

DEVSQ 返回离均差平方和，接受 1–255 个参数。引用仅统计数值，忽略文字、布尔、空白及错误；直接布尔转 1/0，直接文字（含数字文字）忽略，直接错误或空参数返回 `#VALUE!`。无数值返回 0，非有限累计返回 `#NUM!`。参数规则依据固定 [ONLYOFFICE DEVSQ](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L5743-L5822)，核心采用下述稳定累计替代上游直接均值算法。普通 DEVSQ 包含隐藏和筛选行；数组和动态引用仍未支持。实现归 [`formula-deviation-squares.mbt`](../../../modules/formats/src/xlsx/formula-deviation-squares.mbt)。

VAR/VAR.S 返回样本方差，VARP/VAR.P 返回总体方差。普通引用、名称、跨表、共享公式及稀疏整行/列沿现有依赖和缓存事务；引用中的文字、布尔及空白忽略，错误传播。直接布尔转为 1/0；按固定 ONLYOFFICE 规则，VAR 忽略直接文字和空白，VAR.S/VARP/VAR.P 将它们作为 0，数字文字也不按数值转换。样本少于两个数、总体没有数值时返回 `#DIV/0!`；非有限结果返回 `#NUM!`。普通方差包含隐藏和筛选行及嵌套 SUBTOTAL；可见行汇总仍使用 SUBTOTAL。

STDEV/STDEV.S 返回样本标准差，STDEVP/STDEV.P 返回总体标准差，共用方差累计并对结果开平方。按固定 ONLYOFFICE 规则，样本形式只统计引用中的数值，忽略引用和直接参数中的错误；直接数值文字、布尔和省略参数按现有数值转换，无法转换的文字忽略。样本没有数值成员时返回 0，仅有一个时返回 `#DIV/0!`。总体形式沿 VARP 的转换和错误规则：引用非数值忽略、错误传播，直接布尔转 1/0、文字和省略参数为 0；没有数值时返回 `#DIV/0!`。普通标准差包含隐藏和筛选行；现代名称读写标准 `_xlfn.` 前缀，保留未改的导入源。非有限累计返回 `#NUM!`，继续遵守现有工作预算。依据 [ONLYOFFICE STDEV/STDEV.S](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L10693-L10773)及 [STDEVP/STDEV.P](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L10841-L10938)。数字文字使用当前核心的数值转换；地区格式文字及数组仍待兼容扩展。

方差、标准差、DEVSQ 和 SUBTOTAL 共用平方偏差累计。先减去首个值，再逐项更新均值和平方偏差，避免大偏移下丢失相邻值的差，也避免直接作两个大平方和之差。规则依据 [ONLYOFFICE VAR/VARP/VAR.P/VAR.S](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L11619-L12008)。读取接受 `_xlfn.VAR.S`/`_xlfn.VAR.P`，新输入和生成的这两个现代名称带标准前缀；导入未改的源片段保留。独立结果、类型、空样本、错误、较大偏移、溢出、前缀、工作预算、重算和精确历史由定向用例检查；数组、动态引用及更广统计函数继续扩展。实现归 [`formula-variance.mbt`](../../../modules/formats/src/xlsx/formula-variance.mbt)和 [`formula-subtotal.mbt`](../../../modules/formats/src/xlsx/formula-subtotal.mbt)。

数值函数复用已有数值、数字文字、布尔及空白转换；ROUND/ROUNDDOWN 的文字引用保持 `#VALUE!`，文字常量仍可转换。标量函数的多格范围返回 `#VALUE!`。实现参考 [ONLYOFFICE 数值函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js)及其独立[舍入用例](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/mathematicTests.js#L16439-L16487)。核心已检查负数、半值、进位、类型转换、有限边界、跨表重算、缓存和精确历史；默认公式栏已检查组合数值公式、依赖修改、独立 XML、保存重开及 PDF。更广浮点兼容与地区化数值解析仍归后续扩展。

LEN、LEFT、RIGHT、MID、FIND、SEARCH 使用 UTF-16 单元计数和位置，不使用编辑光标的字素计数。LEFT/RIGHT 默认取 1；MID 起点至少为 1，数量非负，小数参数朝零截断并按实际长度截取。切开代理字符对返回 `#VALUE!`，不保存无效 XML。TRIM 只折叠和移除普通空格，保留 TAB 与不换行空格。UPPER/LOWER 使用固定 Unicode 16 完整大小写映射，包含扩张及希腊词尾 Sigma，暂不提供地区化规则。

FIND 按区分大小写的字面匹配返回从 1 起的位置。SEARCH 不区分大小写，支持 `*`、`?` 与 `~` 转义；通配符沿所选旧版参考行为不跨换行。核心使用计入工作量的动态规划，避免正则回溯。SUBSTITUTE 区分大小写，按非重叠字面匹配替换；指定实例必须为正数，省略则替换全部。

`TEXT(value, format)` 返回文字，复用受支持数字格式与 1900/1904 日期规则，包含 General、固定/分组数字、百分比、科学计数及日期/时间；格式代码不区分大小写，空格式把数值变为空文字。数值文字和空白先转为数值，布尔及普通文字保留原显示，错误按参数顺序传播。两个参数都参与依赖重算，修改格式引用也同步原生字符串缓存、结构平移和历史。有效但尚未支持的自定义代码明确返回 `unsupported-formula`，不静默退回 General；新输入整体拒绝，导入沿既有保护规则保留源码和缓存。资源失败不被 IFERROR 吞掉。复用[数字格式实现](../../../modules/formats/src/xlsx/number-format.mbt)与[文本求值](../../../modules/formats/src/xlsx/formula-text.mbt)，语义依据 [ONLYOFFICE TEXT](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/textanddataFunctions.js#L3213-L3280)及[独立格式用例](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/textAndDataTests.js#L8735-L8766)，未复制执行代码。

EXACT 把两个标量转换为既有逻辑文字后做区分大小写的精确比较，不折叠空格或规范化 Unicode；空白格按空字符串比较，错误按参数顺序传播。REPT 接受文字和数值次数，使用既有数值转换；按 [ONLYOFFICE REPT](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/textanddataFunctions.js#L1966-L2020) 先检查原始次数在 0–32767、UTF-16 长度乘原始次数不超过 32767，再向零截断次数并重复。因此 `REPT("ab",2.9)` 为 `abab`，`REPT("ab",16383.9)` 为 `#VALUE!`，空文字配超限次数也拒绝。两项复用依赖、重算、缓存、历史及保存，不再使用未计算缓存保护；比较和输出在执行前计入公式工作预算，资源失败不被 IFERROR 吞掉。当前为标量语义，数组和隐式求交继续扩展。实现归[文本求值](../../../modules/formats/src/xlsx/formula-text.mbt)，比较依据 [ONLYOFFICE EXACT](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/textanddataFunctions.js#L893-L934)及其[独立用例](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/textAndDataTests.js#L2672-L2710)。

CONCAT 按行列顺序连接范围，CONCATENATE 当前只接受标量。TEXTJOIN 的 ignore_empty 为 false 时保留首尾与中间空项，为 true 时跳过空项；分隔符范围按顺序循环使用。普通连接和忽略空项的连接只访问已有稀疏单元格。保留空项的范围先按面积检查剩余预算，再遍历，不能展开超大空矩形。

生成的文本最多 32767 个 UTF-16 单元，超过时返回 `#VALUE!`。复制、范围遍历及搜索共用既有 1048576 单位公式工作预算；耗尽返回 `limit-exceeded`，IFERROR 不吞此失败，候选源码、缓存和历史整体回滚。文本规则参考固定 [ONLYOFFICE 文本函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/textanddataFunctions.js)。MID 的无效起点与 TEXTJOIN 首部空项沿 [MID 合同](https://support.microsoft.com/en-us/excel/functions/mid-function)及 [TEXTJOIN 合同](https://support.microsoft.com/en-us/excel/functions/textjoin-function)处理，未沿用旧版参考的这两处实现缺口。现代 Excel 字符兼容版本、动态数组与更广地区化规则留待 P14。

WEEKDAY、WEEKNUM、ISOWEEKNUM 接受数值日期序号，小数时间向下取整，使用工作簿的 1900/1904 日期系统及同一末日上限。数值文字、布尔及空白按普通标量转换，不解释日期文字；参数错误按顺序传播。WEEKDAY 的负序号为 `#VALUE!`，两项周序号的负序号为 `#NUM!`，超出日历上限均为 `#NUM!`。

WEEKDAY 接受 1–2 个参数。returnType 缺省为 1；1/17 表示周日=1，2/11 表示周一=1，3 表示周一=0，12–16 分别表示周二至周六=1，其余日期按七天循环。WEEKNUM 同样接受 1–2 个参数；缺省/1/17 从周日开始，2/11 从周一开始，12–16 从周二至周六开始，含 1 月 1 日的周是第一周。returnType=21 使用 ISO 周，与单参数 ISOWEEKNUM 相同：周一开始，至少四天落在新年的周为第一周，年初/年末可归相邻年。returnType 必须匹配上述整数值，小数不截断；显式空白按 0 处理并返回 `#NUM!`。

按所选 ONLYOFFICE 行为，1900 系统的 `WEEKDAY(0)=7`、`WEEKDAY(1)=1`、`WEEKDAY(60)=4`；普通 `WEEKNUM(0)=0`，`ISOWEEKNUM(0/1)=52`。周序号将虚构闰日 60 归一化到 1900-03-01，与 61 同为 ISO 第 9 周。公历年份转换复用有界日历查找，星期沿已有工作日序列计算，均不依赖宿主 Date 或时区。普通输入、跨表重算、缓存、插行、精确历史和重开使用现有事务；新写或结构重写的 ISOWEEKNUM 使用 `_xlfn.ISOWEEKNUM`。依据固定 [ONLYOFFICE WEEKDAY/WEEKNUM](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/dateandtimeFunctions.js#L1967-L2148)、[ISOWEEKNUM](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/dateandtimeFunctions.js#L1330-L1365)与独立[日期用例](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/dateTimeTests.js#L3910-L4023)，实现归 [`formula-date.mbt`](../../../modules/formats/src/xlsx/formula-date.mbt)及 [`date.mbt`](../../../modules/formats/src/xlsx/date.mbt)，未复制执行代码。

DATE、YEAR、MONTH、DAY、DAYS 使用工作簿的 1900/1904 日期系统，返回数值。1900 系统保留序号 0 的 1900-01-00 和序号 60 的虚构闰日；1904 系统序号 0 为 1904-01-01。支持到 9999-12-31，当日的小数时间仍有效；负序号或超出末日返回 `#NUM!`。显示和计算复用核心日历转换，按有界查找确定年份，不按输入年份逐年循环。

DATE 的年参数先截断，0–1899 加 1900；月份和日期按公历归一化，显式 1900-02-29 保留虚构序号。年份必须在 0–9999，月份/日期绝对值最多 2147483647，超出返回 `#NUM!`。DAYS 按两个有效序号各自向下取整后相减。TIME 将三个参数分别朝零截断，合计非负时按 24 小时取余；非有限或负合计返回 `#NUM!`。HOUR/MINUTE 返回时分，SECOND 按参考规则舍入到整秒，不向时分进位。函数不自动改变单元格格式；默认 UI 可沿现有数字格式显示日期或时间。

提取和差值函数接受数字文字，以及明确的 `yyyy-mm-dd`、`yyyy/m/d`、`m/d/yyyy` 日期与 `h:mm[:ss[.ffffff]]` 时间，可用空格或 `T` 连接，时间可附 AM/PM。日期必须实际有效；不解释时区、月份名称或两位年份。沿所选参考的引用转换，HOUR/MINUTE/SECOND 的文本引用返回 `#VALUE!`；DAY 的引用可转换数字文字，其余日期文字引用返回 `#VALUE!`。YEAR/MONTH/DAYS 可解释上述日期文字引用。日期系统和转换都在 MoonBit 内执行，不调用宿主 Date 或当地时区。

日期与时间规则参考固定 [ONLYOFFICE 实现](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/dateandtimeFunctions.js)、[日期序号转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L4007-L4062)及独立[日期时间用例](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/dateTimeTests.js)。地区化日期解析、自动日期格式推断及更广历史兼容仍待扩展。

COUNTA 统计非空白值，包括错误和公式返回的空文字。COUNTBLANK 统计空白格及空文字，单格与矩形保持相同规则；参数必须为引用。计数按范围面积和已有单元格求得，不展开空矩阵，支持最大工作表矩形的精确计数。

COUNTIF/COUNTIFS、SUMIF/SUMIFS、AVERAGEIF/AVERAGEIFS 共用有类型的条件。条件支持 `= <> < <= > >=`；省略运算符表示等于。数值等值比较可转换数字文字，数值大小比较只使用数值。空白条件参数按 0 解释，空文字条件匹配空白及空文字。布尔条件保持类型；文字形式的错误条件可匹配相应错误值。文字比较当前使用简单 Unicode 映射和 UTF-16 顺序，地区化排序留待后续。

文字等值条件覆盖整个单元格，不区分大小写；`*`、`?` 与 `~` 转义按有界动态规划匹配，可包含换行。多条件取交集，范围行列数量必须一致，单元格位置及工作表可以不同。范围或条件数组不做隐式求交；非法形状返回 `#VALUE!`。普通条件聚合包含全部隐藏行；[SUBTOTAL](#subtotal-汇总) 区分筛选与手动隐藏。

SUMIF/AVERAGEIF 的可选结果范围从其左上角取与条件范围相同的形状；越过工作表边界返回 `#REF!`。隐含范围也进入依赖图，修改锚点之外的结果单元格会重算。已匹配结果中的数值参与求和/平均，文字和空白不参与；已匹配错误按行列顺序传播，未匹配错误不影响结果。没有数值时 SUMIF/SUMIFS 返回 0，AVERAGEIF/AVERAGEIFS 返回 `#DIV/0!`。非有限结果返回 `#NUM!`。

MINIFS/MAXIFS 在结果范围中返回满足全部条件的最小值/最大值，复用现有条件、稀疏范围及依赖图。结果范围和每个条件范围必须具有相同行列数。两项沿 ONLYOFFICE 先将条件转换为文字；空文字或空白条件也接受数值 0，显式 `"="` 仍只匹配空白及空文字。错误条件参数返回 `#VALUE!`，字面的错误文字仍可匹配相应错误值。只选择结果范围中的数值，忽略其文字、布尔、空白和错误；没有数值时返回 0。包含隐藏行，整列只遍历已有单元格。名称、跨表依赖、填充平移、精确历史和缓存沿同一事务。读取普通及 `_xlfn.` 名称，新输入和生成公式写回标准前缀。实现归 [`formula-conditional.mbt`](../../../modules/formats/src/xlsx/formula-conditional.mbt)，依据 [ONLYOFFICE MAXIFS/MINIFS](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L8313-L8542)。

条件范围遍历、文字比较和通配符共用现有公式工作预算；超限整体回滚，IFERROR 不吞资源失败。实现参考固定 [ONLYOFFICE 统计函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js)、[条件匹配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L12325-L12512)与[条件求和](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L5310-L5402)。结果范围投影及错误读取同时对照 [LibreOffice 条件聚合](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/tool/interpr1.cxx#L5871-L6094)。单格空文字计数与结果范围形状沿 [COUNTBLANK 合同](https://support.microsoft.com/en-us/excel/functions/countblank-function)及 [SUMIF 合同](https://support.microsoft.com/en-us/excel/functions/sumif-function)，不沿用旧参考中单格/区域及结果矩阵尺寸的不一致。

ROW/COLUMN 返回显式引用的左上角行列，省略参数时返回公式自身位置；ROWS/COLUMNS 返回矩形行列数量，不遍历单元格。四项位置函数只校验引用身份，不依赖引用内的值，`A1=ROW(A1)` 不产生值循环。公式来源位置属于核心求值上下文，不由宿主选区决定。

INDEX 当前返回一个单元格的值，支持二维行列索引、单行/单列简写及标量输入；索引朝零截断，越界返回 `#REF!`，负索引返回 `#VALUE!`，单一区域的 area_num 必须为 1。选中空白格返回 0。零行/列仅在对应维度本来为 1 时返回单格，其余数组结果仍未支持。MATCH 接受一维引用，0 为首个精确匹配，1 为升序的最后一个不大于项，-1 为降序的最后一个不小于项；省略时为 1。精确模式支持整格通配符和转义，不把数字文字与数值等同。

VLOOKUP/HLOOKUP 在首列/首行查找，返回指定列/行的标量值；省略 range_lookup 时沿升序近似规则，false 使用首个精确或通配符匹配。无匹配返回 `#N/A`，结果索引小于 1 返回 `#VALUE!`，超出表格返回 `#REF!`。近似匹配的重复键沿最后一个符合项，精确匹配沿首项。

XLOOKUP 当前使用同形的一维查找和返回引用，默认精确查找，支持 -1/1 的最近较小/较大项及 2 的通配符模式。search_mode 为 1/-1 时正向/反向扫描，为 2/-2 时按升序/降序二分；二分不接受通配符模式。二分和旧式近似模式要求输入已有正确排序，不替用户排序。未命中时才求值 if_not_found；省略或显式空参数返回 `#N/A`，查找值、查找过程和选中结果中的错误保留类型，不被回退值覆盖。

查找共享既有文字比较与工作预算，二分直接读取稀疏地址；线性或通配符工作超限整体回滚，IFERROR 不吞失败。值依赖目前保留声明的范围和回退分支；动态引用、引用形式 INDEX、整行/列返回及其他数组结果仍待扩展。实现参考固定 [ONLYOFFICE 查找引用函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/lookupandreferenceFunctions.js)及独立[位置与查找用例](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/lookupAndReferenceTests.js)。当前范围是标量计算，不授予完整数组或动态引用兼容。

逻辑、类型和扩展函数前缀参考 [ONLYOFFICE 逻辑函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/logicalFunctions.js)、[类型函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/informationFunctions.js)及[公式序列化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L3586-L3587)。范围迭代和错误参与与固定 [LibreOffice ScAnd/ScOr](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/tool/interpr1.cxx#L1234-L1413)交叉核对。独立用例覆盖类型、空白、错误、跨表重算、缓存、精确历史及失败；默认公式栏已检查组合公式、依赖变化、独立 XML、保存重开和 PDF。

首次打开计算支持的公式，编辑只重新求值受影响公式。首次有效事务同步与已计算结果不同的导入缓存，包括未受本次输入影响的陈旧缓存；无编辑打开不写回。语法、越界引用、未支持公式、新建循环和预算超限整体拒绝；除零等是带类型的公式结果。共享公式按锚点派生；编辑命中组时有界展开该组，其他组保留。

结构化/外部/三维引用、数组、动态数组、易变函数及迭代计算未支持。依赖无法确定、函数参数语义未核实或存在原有循环时，整个工作簿只读。公式不访问网络、宏或宿主脚本。

DEVSQ 已真实求值，接入名称、共享公式、跨表、稀疏引用及普通重算、缓存和历史事务。原 DEVSQ 专用未计算链及其隔离检查已移除。核心只把实际求值结果放入 `calculated`，缓存不参与新的公式、条件格式、验证或筛选计算。每格 `calculationReason` 在已计算/普通值时为空，未计算格返回自身或依赖原因，整本保护时返回工作簿原因。默认公式栏显示原因；有缓存时显示缓存，缺缓存显示未计算。选区含未计算公式时，计数仍可读，四项汇总均为 null 并给出原因。

导入的 `MINVERSE` 尚未求值，但其静态显式参数可沿既有依赖图解析。保存保留实际公式源；新建这些未计算公式仍拒绝。隔离依据 [ONLYOFFICE MINVERSE](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L2746-L2903)的显式首参数矩阵读取；嵌套动态、随机或自定义函数仍整本保护。核心标记这些公式及下游为未计算，保护完整上下游公式及其声明输入范围；不把导入缓存放入 `calculated`。无关联的普通输入及受支持公式可继续编辑和重算；纯格式及不影响结果的行显隐可提交。链中包含 SUBTOTAL 时，影响结果的隐藏来源变化原子拒绝。名称、共享公式及跨表引用沿现有解析，源公式和导入缓存保留，撤销重做恢复完整字节。隔离最多 4096 个范围，并沿用公式工作预算；结构、身份或引用变化及关联图表等资源仍遵守既有保护。实现归 [`calculation-protection.mbt`](../../../modules/formats/src/xlsx/calculation-protection.mbt)。

新增未支持公式及 CSV/TSV 中的未支持公式转换在提交前拒绝。导入含其他未核实函数、INDIRECT/OFFSET、CELL 等环境/格式查询、自定义函数及其嵌套时继续整本只读，保留原始源码和缓存。

未计算公式即使有缓存也不能作为计算结果打印；只含已计算内容的独立打印区域可输出。XLSX 原格式保存保留未计算公式及缓存，CSV 值导出沿既有有缓存才可导出的合同，不赋予缓存已计算状态。

### 名称引用

已有 `definedNames` 可用于单元格、条件格式和数据验证中的受支持表达式。名称不区分大小写，支持 Unicode 名称、工作簿/工作表作用域、常量、矩形及整行/整列引用和表达式组合。单元格中的未限定名称先查当前表，再查工作簿；`'表名'!名称` 先查指定表，再查工作簿。名称定义内部的未限定名称查工作簿作用域，局部名称须显式指定表；这沿用 ONLYOFFICE 的独立定义解析上下文。`localSheetId` 决定名称的查找范围，不为定义内部的单元格引用绑定工作表。

定义中的单元格引用须包含工作表。绝对行列保持固定，相对行列以 A1 为原点，按使用该名称的单元格偏移。展开后复用现有表达式、依赖图、范围函数、增量计算、规则及缓存事务。未定义名称产生 `#NAME?`，仍可继续编辑；命名循环、未支持表达式与超预算候选原子拒绝，导入后沿既有只读规则保留源和缓存。未使用的复杂定义不参与求值。

最多读取 4096 个定义，名称和定义合计不超过 1,048,576 UTF-16 单元；每条公式仍限 8192 单元，展开受 64 层表达式深度及现有工作预算保护。名称目录另计入重复的作用域身份，总计同样不超过 1,048,576 单元；目录超限返回保护原因，新增候选在提交前拒绝。名称源不会被展开结果替换。绝对、相对及混合定义的显式工作表引用随行列/单元格结构、表改名/复制/删除及局部作用域索引一起更新，精确历史和重开复用原路径。结构操作在定义保存的坐标上变换一次，保留 `$`、公式文字及非目标源；使用名称的单元格仍保存名称，不写入展开后的引用。删除完整目标时定义写为 `#REF!`，依赖与缓存一起重算。局部单元格移位沿既有范围交集规则，保留未覆盖的跨带引用。

相对定义在求值时按实际调用格偏移。同表调用格随结构移动后，使用新位置；跨表调用格保持自己的位置。例如 `Items!$A2` 在 `Items!E2` 调用时读 A3；在第 2 行上方插行后，定义为 `Items!$A3`、调用格为 E3，读取 A5，其他表的 E2 则读取 `Items!A4`。这是定义坐标和调用位置各自变化的结果，不额外补偿调用方。未限定工作表的单元格引用、需改写的不透明源及预算失败仍原子保护。规则中的名称复用同一候选定义与求值上下文。

`XlsxQuery.names` 返回 `entries` 和整体 `readOnlyReason`。每条名称包含 `name`、`scope`、原始 `formula`、`hidden` 及单项 `readOnlyReason`。`scope` 是稳定工作表部件身份，`null` 表示工作簿。默认名称面板与自定义 UI 共用下列 `editSheet` 命令：

| 命令 | 行为 |
| --- | --- |
| `{ action: "name", original, name, scope, formula }` | `original: null` 创建名称；否则按原名称和作用域修改定义或改名。编辑期间保持作用域，定义可带 `=` 前缀 |
| `{ action: "nameDelete", name, scope }` | 删除定义，保留单元格公式中的名称，重新计算为 `#NAME?` 或剩余作用域的值 |
| `{ action: "nameSelect", name, scope }` | 解析为单个矩形后定位到目标表，复用合并格、隐藏表和选区查询边界；不写源、不增加 revision 或历史 |

名称最多 255 UTF-16 单元，允许字母、Unicode 标记及既有名称字符；A1/R1C1 地址、R/C、布尔常量和 `_xlnm.` 系统名称不接受管理修改。新定义先检查语法、支持的函数、作用域及循环，再构造候选。一次增改删同步重算、缓存、尺寸与精确历史，重复设置不产生历史；新定义的可选 `=` 前缀不要求改写相同的导入源。改名按原作用域绑定同步单元格、共享公式锚点、规则、内部链接和其他定义，保留字符串、共享组和元数据。全局改名会被已有局部名称遮蔽时明确拒绝。源文本中的未知标记、资源引用或工作预算不能安全处理时，候选整体拒绝。

含受支持原生表的工作簿使用同一名称面板及命令，可新增、修改、改名、删除和定位名称。名称定义可引用 `Sales[Total]` 等已支持的结构化范围；候选验证、依赖计算和内部链接检查使用同一表上下文。改名同时更新原生 `calculatedColumnFormula/totalsRowFormula`，按所属工作表判断局部优先和显式限定，不改写列标题、结构化选择器或字符串常量。名称与现有表名冲突时拒绝，列标题不占用名称空间。删除保留表内公式源，再按剩余作用域计算。表定义、单元格、名称、缓存及选择共用一次精确历史；未知表资源、数组公式源、循环和预算失败保持原状态。

名称面板可从当前选区生成带表名的绝对矩形，也可输入常量或表达式。命令先提交原生单元格草稿；定位按当时焦点解析相对定义。常量和计算表达式不能作为矩形定位，隐藏目标表须先显示。导入的未支持语法或系统定义保留并显示保护原因，普通命令不改变隐藏属性。多区域、整行整列、作用域迁移和更广定义兼容另行扩展。

实现归 [`named-definitions.mbt`](../../../modules/formats/src/xlsx/named-definitions.mbt)与 [`name-edit.mbt`](../../../modules/formats/src/xlsx/name-edit.mbt)。作用域、定义上下文和相对偏移参考 [ONLYOFFICE DefName](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L457-L512)及 [cName](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L2173-L2262)。管理事务和改名绑定参考 [editDefinesNames](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L1086-L1125)及 [changeDefName](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L2261-L2275)。

结构变换参考 [ONLYOFFICE 名称公式通知](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L559-L574)及[按保存引用移动](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L10152-L10281)，实现复用 [`axis-reference.mbt`](../../../modules/formats/src/xlsx/axis-reference.mbt)和 [`axis-metadata.mbt`](../../../modules/formats/src/xlsx/axis-metadata.mbt)。

### 结构化表与引用

原生表行排序复用 `editSheet({ action: "sort", range, ... })`。选区完全位于一张表内时，核心扩展为整张表的数据行和全部列，固定标题与总计。默认排序面板同步这些边界；多键、文字自定义列表和颜色沿[区域排序](xlsx-editing.md#区域排序)规则。排序前冻结当前公式键和可见位置，手动或筛选隐藏记录留在原位；保留计算列模板、值/公式例外、富文本、便笺、链接和直接格式。候选计算后重新应用相关原生表及普通筛选，同步 SUBTOTAL 和最终值校验。

排序状态写入所属表根节点 `sortState`，移除竞争的嵌套筛选排序状态，保留无关源。已支持的排序范围、键及颜色差异样式随整轴和工作表复制维护；源、值、缓存与可见性合为精确历史，支持保存重开和打印。原生表保持整行排序；跨越表边界的选区及未知元数据继续保护。方向规则沿 [ONLYOFFICE 原生表排序设置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L25584-L25608)的锁定方向。已有排序的范围调整见下文。实现归 [`table-sort.mbt`](../../../modules/formats/src/xlsx/table-sort.mbt)，参考 [ONLYOFFICE 表数据排序范围](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L2574-L2659)。

`XlsxQuery.tables` 返回当前工作表的原生表定义，包括 `id`、`name`、A1 `range`、`headerRow/totalRow`、`columns`、`style`、`filter` 和 `readOnlyReason`。每列返回稳定的 `id`、`name` 及可空的 `formula/totalFunction/totalLabel/totalFormula` 原生设置；表和列身份来自所属 XML，不从位置或显示文字重新生成。`filter` 沿用 `XlsxFilterState` 的范围、条件、值目录和保护原因。核心校验表关系、名称、列数、重复身份、重叠范围和合并区域，单元格仍由原有稀疏工作表持有。

公式支持 `Sales[Amount]`、表内 `[Amount]`、`[@Amount]`、`[[First]:[Last]]`，以及 `#Data/#Headers/#Totals/#All/#This Row`。裸表名表示数据区域，标题和总计按定义排除；连续行段可组合。列名中的结构字符使用单引号转义。引用解析为现有单元格依赖和有界范围，保留原公式文字；跨表公式、名称引用，以及计算列和总计格中已有的单元格公式随普通数据重算。普通数据修改不自动补齐既有区域中缺失的计算列公式；扩展新行的补齐见下文。缺表返回 `#NAME?`，缺列或不存在的行段返回 `#REF!`，数据区域外的当前行引用返回 `#VALUE!`。不连续行列组合继续保护。

`editSheet({ action: "renameTable", id, name })` 修改表名称。`editSheet({ action: "renameTableColumn", id, column, name })` 修改列标题；`column` 是稳定列身份。表名遵循已有名称规则，表名和列名最多 255 个 UTF-16 单元。核心同时更新所属表部件、表头、工作簿名称及各表公式，按词法标记替换，保留字符串常量、列身份、表关系、样式定义和无关源。默认结构化表面板调用相同命令，先提交原生草稿。源、缓存和选区进入一项精确历史，相同名称不新增历史。

`editSheet({ action: "createTable", range, name })` 将当前工作表的矩形区域转为原生结构化表。区域至少包含标题和一行数据；首行作为标题，不插入新行。核心按已支持的单元格数字格式取得标题文字，空白使用 `Column1` 等唯一名称，重复标题追加从 2 开始的数字，并避开现有标题。标题公式转换为当前结果文字；共享公式标题继续保护。非标题单元格的值、公式和直接格式保持，已有结构化引用随新定义重算。

创建使用 `TableStyleMedium2` 行条纹，分配独立表/列身份、部件路径及关系，并添加内容类型和工作表引用。标题修改、源、缓存、资源及选区合为一项精确历史；已有表及无关部件保持。创建后可沿既有路径编辑数据、输入结构化公式及改名。默认面板使用当前选区，原生草稿先提交。重叠表、合并区域、普通筛选、名称冲突、受保护源或资源预算失败整体拒绝。标题超过 255 或总名称预算时拒绝，不静默截断。实现归 [`table-create.mbt`](../../../modules/formats/src/xlsx/table-create.mbt)及与便笺共用的 [`sheet-resource.mbt`](../../../modules/formats/src/xlsx/sheet-resource.mbt)。空白和重复标题规则参考 [ONLYOFFICE 标题生成](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L5545-L5627)。

`editSheet({ action: "resizeTable", id, range })` 调整行数及左右列边界。新范围保留首行、部分原有列和至少一行数据。保留列按原单元格位置保留身份与元数据；新列分配身份，并从原位置的逻辑值生成唯一标题。空白或重复标题使用空闲 `ColumnN`。有标题的表同步写入新列标题，无标题表保持首行数据。移出表的普通数据与直接格式留在原坐标；指向移除列的已绑定公式写为 `#REF!`，重新扩入同名列也不恢复旧引用。移出范围的普通局部结构化引用补上表名，保持归属；当前行引用在数据区外返回 `#VALUE!`。

已有总计行随末行移动：核心清除原总计行，在保留列的新位置恢复原文字/公式，目标已有内容时整体拒绝。原生 `calculatedColumnFormula` 为新增数据行中的空白格补公式，相对 A1 引用按首个数据行偏移，结构化引用保留；既有值或公式例外不覆盖。一次补齐最多涉及 4096 格，沿既有公式、输出及历史预算。此入口不新增计算列定义或总计设置，也不向整张工作表插入行列。

核心同步表范围、排除总计行的筛选范围、工作簿名称和各表依赖缓存。新范围完全包含原范围时，恰好覆盖整表或单列的条件格式按新末行延长，保留原锚点；缩小时不裁剪原规则。样式、自动适配和打印沿现有表定义派生。默认面板提供范围框与同一命令，先提交原生草稿；相同范围不增加历史。表排序或未知列/筛选元数据、跨边界的共享局部公式、未绑定的规则引用及超限候选继续保护。实现归 [`table-resize.mbt`](../../../modules/formats/src/xlsx/table-resize.mbt)及 [`table-resize-references.mbt`](../../../modules/formats/src/xlsx/table-resize-references.mbt)，范围与列身份依据 [ONLYOFFICE changeRefOnRange](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L8579-L8641)，条件格式范围依据 [af_changeTableRange](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L22631-L22708)。

`editSheet({ action: "tableColumnFormula", id, column, formula })` 创建或重填计算列。字符串公式可带开头的 `=`，相对 A1 引用从首个数据行偏移，结构化引用保留。命令改写所选列的全部数据格，包括已有值和公式例外；标题、总计及直接格式保持。`formula: null` 只移除原生模板，保留现有单元格公式，随后可按普通数据格编辑。相同模板且各格公式等价时不新增历史。每次最多 4096 个数据格、公式最多 8192 个 UTF-16 单元，沿现有 1048576 公式工作预算。实现归 [`table-column.mbt`](../../../modules/formats/src/xlsx/table-column.mbt)。

`editSheet({ action: "tableTotals", id, visible })` 显示或隐藏总计行。显示在表下方增加一行，不插入整张工作表的行；目标须为空且不与合并、表或普通筛选重叠。首次没有总计设置时，多列表的首列使用 `Summary`，末列按数据选择求和或非空计数；单列表仅生成聚合。隐藏缩小表范围、清除原总计格，保留设置和直接格式；缺失或不同于设置的导入总计内容先保存为标签或自定义公式。再次显示恢复这些设置，显式“无”不会恢复默认聚合。表筛选范围始终排除总计行。

`editSheet({ action: "tableTotal", id, column, total })` 修改可见总计行的所选列。`XlsxTableTotal` 支持 `{ kind: "none" }`、`{ kind: "label", text }`、`{ kind: "formula", formula }` 和 `{ kind: "aggregate", function }`。聚合为 `sum/average/count/countNums/min/max/stdDev/var`，分别使用已有 `SUBTOTAL` 的 109/101/103/102/105/104/107/110；标准差与方差使用样本口径。自定义公式最多 8192 个单元，标签最多 32767 个单元。修改总计保留计算列模板。全部公式及总计元数据累计最多 1048576 个单元；多次总计元数据写入受同量级源处理预算限制，超限整体拒绝。

计算列与总计命令沿同一事务更新原生定义、单元格、依赖和缓存，支持精确历史、保存重开及现有打印。默认面板调用相同命令并先提交原生草稿。共享/数组公式源、未知表/筛选元数据、非法结果、验证失败和输出预算失败均保留原状态。总计实现归 [`table-total.mbt`](../../../modules/formats/src/xlsx/table-total.mbt)及 [`table-totals.mbt`](../../../modules/formats/src/xlsx/table-totals.mbt)。默认设置及聚合映射参考 [ONLYOFFICE 总计行](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L10063-L10140)；其中数值计数沿现有 `SUBTOTAL(102)` 补齐。原生计算列和总计设置分别保留。

`editSheet({ action: "tableFilter", id, columns })` 设置原生表筛选。`id` 是表身份；范围由核心取标题和数据区域，排除总计行，不能由调用方另传。`columns` 沿用[普通筛选](xlsx-editing.md#值筛选)的值、自定义、排名、平均值、日期组、跨年日期、相对日期和颜色条件；列号仍是从 1 开始的工作表列号。多列取交集，空条件保留筛选范围并显示全部数据。`tableFilterClear/tableFilterRemove/tableFilterReapply` 同样携带 `id`，分别清除条件、移除原生筛选节点和按当前值重新应用。查询不重写导入源，普通数据输入也不自动重新筛选。

条件和隐藏来源写入所属表部件的原生 `autoFilter`，行隐藏和 `sheetPr/filterMode` 写入工作表。同一工作表上的多个原生表及普通筛选分别保留条件和筛选隐藏记录；实际隐藏取各筛选与手动隐藏的并集。清除或移除一个筛选保留其他来源。行高和分组折叠/展开同步手动来源，`SUBTOTAL` 的 1–11 与 101–111 继续区分筛选隐藏和手动隐藏。源、可见性、缓存和依赖合为一次精确历史，保存重开、工作表复制、网格和 PDF 复用同一结果。导入文件无法辨别重叠隐藏原因时，沿用普通筛选的来源限制。

默认结构化表面板复用现有条件控件，原生草稿先提交。筛选需要标题和至少一行数据，范围最多 4096 格、条件最多 256 列；文本、公式工作、输出及历史沿普通筛选预算。当前表目录共享 1048576 次工作预算，超限目录返回原因。未知条件、扩展、注释/处理指令、保护或预算失败保留原源、选区和历史。原生表筛选已随范围调整和整行/整列插删同步，具体规则见下文；表内行排序见下文。实现归 [`filter-visibility.mbt`](../../../modules/formats/src/xlsx/filter-visibility.mbt)及既有筛选读写，参考 [ONLYOFFICE 表/区域的共同筛选入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L1054-L1135)和[按表身份重新应用](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L1405-L1445)。没有复制上游代码。

筛选中的 `resizeTable` 保留仍在范围内的条件列和按钮标记，列号继续绑定原工作表列；移出列的条件随列移除。扩大后按当前值检查新增数据行，缩小后释放移出行的筛选隐藏，保留手动隐藏及其他表/普通筛选的来源。总计行仍不参加筛选，迁移目标须为空，已有值/公式例外沿范围调整规则保留。已有排序状态也可调整范围。扩大时保留仍有效的历史排序范围及源，不自动重排新增数据。缩小时把表根节点排序限制在新数据区，把筛选内排序限制在新筛选范围；裁剪各键范围，移除已离开的键，全部键移出时删除状态。键顺序、大小写、方法、自定义列表及颜色样式引用保持。颜色引用先按既有差异样式池校验，未知元数据或缺失样式仍原子拒绝。源、条件、生成格、总计和缓存共用一次精确历史。实现复用 [`sort-state.mbt`](../../../modules/formats/src/xlsx/sort-state.mbt) 与现有表范围事务；扩大时保留历史设置参考 [ONLYOFFICE changeRefOnRange](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L8579-L8642)，裁剪额外保证保存状态仍属于本表。

已有 `insertRows/deleteRows/insertColumns/deleteColumns` 同步维护原生表。表之前的插入移动范围，表内部的插入扩展范围；保留原列身份，新列使用空闲身份和唯一 `ColumnN` 标题。计算列模板的相对引用按新的首个数据行重定位，绝对引用沿工作表结构变化。插入的数据行按模板生成公式，原有值/公式例外不改写；每次最多生成 4096 格。总计和筛选范围一起移动，删除总计所在行时关闭总计并保留设置。

活动筛选随整轴操作移动条件列、按钮和手动/筛选隐藏记录。删去条件列时移除相应条件，仍保留其他列；插在总计之前的数据行也进入筛选。已支持的嵌套排序范围及键沿同一变换同步。候选公式先计算，再重新应用受影响的条件，最后重算 SUBTOTAL；生成格按最终结果执行数据验证。多表与普通筛选的行隐藏继续取并集，逐条合并记录，避免对手动隐藏数组反复扫描。原有排序/删除重复流程也复用同一重新应用路径。实现归 [`filter-axis.mbt`](../../../modules/formats/src/xlsx/filter-axis.mbt)和 [`filter-structure.mbt`](../../../modules/formats/src/xlsx/filter-structure.mbt)。

删列将所有已绑定的目标列引用写为永久 `#REF!`，包含单元格、名称及其他表的公式。删除覆盖整张表的行或列时，删除所属表部件、关系、内容类型和工作表引用，裸表名及行段引用也改为 `#REF!`。同时移除该表的筛选隐藏来源，保留其他筛选及手动隐藏。候选计算使用待删除部件列表，避免读取已删的导入表。同一工作表中的其他原生表及其资源继续保留。源、生成格、依赖、缓存和资源删除合为一次精确历史；撤销能恢复导入部件，也能恢复本会话新建的部件。

部分删除表首行、删除后没有数据行、插入导致表越界、未知表排序、未知表资源和超限候选继续拒绝。穿过表的局部单元格移位仍保护；无交集的移位保留表并同步已支持的引用。生成格沿数据验证检查。默认行列按钮使用原有命令，原生草稿先提交。实现归 [`table-axis.mbt`](../../../modules/formats/src/xlsx/table-axis.mbt)、[`table-axis-resources.mbt`](../../../modules/formats/src/xlsx/table-axis-resources.mbt)及 [`axis-edit.mbt`](../../../modules/formats/src/xlsx/axis-edit.mbt)，参考 [ONLYOFFICE 行范围变化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L2326-L2421)、[列身份维护](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L2117-L2170)及[首行删除保护](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L1468-L1478)。

普通数据格沿现有输入路径编辑。直接覆盖表头、总计格或已有计算列时，核心要求相应表命令；缓存重算不受此限制。连接、资源关系、扩展、未知规则引用、受保护工作表和超限候选原子拒绝。工作簿最多 256 张结构化表、4096 列定义；每表列名累计最多 65536 个单元，改名共享 1048576 公式工作预算和原有 4 MiB 历史上限。

`editSheet({ action: "tableStyle", id, style })` 修改所属表的原生样式。`style` 为 `XlsxTableStyle`，包含 `name: string | null` 和显式布尔字段 `firstColumn/lastColumn/rowStripes/columnStripes`。名称支持 `TableStyleLight1`–`TableStyleLight21`、`TableStyleMedium1`–`TableStyleMedium28` 和 `TableStyleDark1`–`TableStyleDark11`，共 60 种，以及工作簿中已有的受支持自定义样式。名称查找由核心执行，自定义名称按目录中的大小写保存。null 清除样式，保留数据、模板、筛选和直接格式。查询的 `style` 返回名称或 null，四个布尔字段另行返回。

缺失的原生节点按需创建，相同设置不增加修订或历史。未知元数据、保护及预算失败整体拒绝。自定义定义与内置名称相同时，以已有自定义定义为准；未知定义仍保护。默认面板、同步 Wasm 和 Worker 使用同一命令。样式源与自动尺寸变化合为精确历史，公式缓存、calcChain 和无关部件保持。实现归 [`table-style-edit.mbt`](../../../modules/formats/src/xlsx/table-style-edit.mbt)和 [`xlsx-table-style.tsx`](../../../packages/xlsx/src/react/xlsx-table-style.tsx)。

自定义样式沿标准 `tableStyles/tableStyle/tableStyleElement` 与 `dxfs/dxf` 读取。`query.tableStyles: XlsxTableStyleChoice[]` 返回 `{ name, readOnlyReason, elements }` 目录，默认面板列出可用项并禁用未知项；最多 256 个定义，每个名称最多 255 个 UTF-16 单元，首尾空白和控制字符拒绝。每个定义最多 13 类非重复区域：全表、两组行/列条纹、首末列、标题/总计行及四个角格。条纹尺寸为 1–1048576；按全表、列条纹、行条纹、末列、首列、标题、总计和角格顺序叠加。字体族/大小/粗斜体/颜色、纯色填充、数字格式、对齐/换行及已支持边框复用差异格式解析，内部横竖边按区域几何映射。直接属性逐项优先，条件格式随后覆盖；字体变体沿现有 4096 字体键和 1048576 工作预算收集。未知区域、缺失 dxf、复杂图案和对角线保持诊断与保护，不替换成内置外观。应用只改所属表的样式引用和标记，原样式定义、dxf 和其他部件保持。实现归 [`table-custom-style.mbt`](../../../modules/formats/src/xlsx/table-custom-style.mbt)，区域优先级依据 [ONLYOFFICE CTableStyle.initStyle](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Serialize.js#L14218-L14290)。

`editSheet({ action: "tableStyleDefinition", original, name, elements })` 新建或完整替换定义。`original: null` 表示新建，字符串表示已有名称；`name` 可同时改名。新名称按大小写不敏感规则避开已有定义及 60 种内置名称；同名导入定义仍可修改。`elements: XlsxTableStyleElement[]` 中每项必须包含 `{ kind, size, format, vertical, horizontal }`。`kind` 来自 Wasm/Web 导出的 `xlsxTableStyleRegions`；`format` 沿用 `XlsxCellFormat`，未提供的属性不再属于该区域。`vertical/horizontal` 为内部边框的 `XlsxCellBorder | null`。非条纹区域的合法 `size` 规范为 1；空数组保留一个无格式定义。查询按原生优先级返回区域，未知定义返回保护原因和空数组。

`editSheet({ action: "deleteTableStyle", name, replacement })` 删除定义。`replacement: string | null` 显式选择已有可用自定义/内置样式，或清除引用。定义修改影响使用它的全部表；改名和删除同步各工作表的引用及默认表样式，保留表标记、数据、公式和其他部件。任一受影响表受保护时整项拒绝。仍被默认透视样式使用的定义不能删除，透视样式编辑继续实施。

核心复用差异样式池，仅为变更区域派生 dxf，未变区域保留原身份及主题/索引色关联。删除不回收共享 dxf 或数字格式。缺少样式部件时创建原生部件、关系和内容类型；源、资源与自动尺寸合为一次精确历史。相同有效定义不新增历史，名称冲突、过期、未知源标记及输出预算失败原子拒绝。单个样式部件的编辑候选最多 2097152 个 UTF-16 单元，另受原有 XML 字节及 4 MiB 历史预算约束。默认面板提供新建、区域格式、条纹尺寸、改名和显式替代删除，先提交原生草稿。字体或引用变化使用旧、候选各自的表定义比较并重排行高；两次比较共用计算预算。实现归 [`table-style-definition.mbt`](../../../modules/formats/src/xlsx/table-style-definition.mbt)、[`autofit-reflow.mbt`](../../../modules/formats/src/xlsx/autofit-reflow.mbt)和 [`xlsx-table-style-definition.tsx`](../../../packages/xlsx/src/react/xlsx-table-style-definition.tsx)。

内置样式复用已有主题及 tint 解析。各组保留原生定义的差异：

| 名称范围 | 字体和底色 | 条纹、边框和总计 |
| --- | --- | --- |
| Medium1–7 | 深色标题，正文使用主题深色字 | 浅条纹，双线总计 |
| Medium8–14 | 深色标题、总计及强调列 | 较深条纹，主题浅色内部网格与粗分隔线 |
| Medium15–21 | 深色标题及强调列，普通总计不额外加粗 | 灰条纹，黑色双线总计；灰阶项保留完整网格 |
| Medium22–28 | 浅底色和主题深色字 | 较深条纹、完整网格与中等总计线 |
| Light1–7 | 有色文字，不新增标题底色 | 浅条纹，少量标题、总计及外侧横线 |
| Light8–14 | 深色标题，正文保留普通底色 | 行/列条纹开关分别控制内部横线/竖线，总计使用双线 |
| Light15–21 | 正文保留普通底色 | 浅条纹、完整网格、中等标题线和双线总计 |
| Dark1–7 | 深底浅字，强调列使用更深底色 | 标题、总计及强调列保留中等浅色分隔线 |
| Dark8–11 | 标题与正文使用配对主题色，未强调的标题不加粗 | 浅条纹，不新增内部网格，总计使用深色双线 |

Dark8–11 未声明的正文文字色和边框沿用正常单元格格式。字体请求只包含实际需要的粗体字形。直接格式按属性覆盖表样式，条件格式随后覆盖；网格、自动适配与打印使用同一结果。格式面板查询包含表样式；`none` 清除直接边框覆盖，恢复表样式。共享边只绘制一次，双线保留两条细线及间隙。宿主仍须提供字体和 profile。

原生属性依据 ONLYOFFICE 的 [Medium 定义](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Sheets/XlsxDefaults/presetTableStyles.xml#L3-L2668)、[Light 定义](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Sheets/XlsxDefaults/presetTableStyles.xml#L2668-L4536)和 [Dark 定义](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Sheets/XlsxDefaults/presetTableStyles.xml#L4537-L5598)。实现归 [`table-style.mbt`](../../../modules/formats/src/xlsx/table-style.mbt)，复用原有绘制模型。

含受支持原生表的工作表可沿现有 `rename/copy/delete` 命令和默认按钮操作。工作表改名同步各表的 `calculatedColumnFormula/totalsRowFormula`，保留表名、表/列身份及部件路径。复制为每张表分配独立身份、空闲 `TableN` 名称和部件，并复制工作表关系与内容类型；列身份和其他原生设置保留。副本的显式表引用、工作表自引用及导入的局部名称指向相应副本，字符串常量和全局名称保持原归属。表名分配避开已有表和名称，不重命名源表。实现归 [`table-sheet-copy.mbt`](../../../modules/formats/src/xlsx/table-sheet-copy.mbt)，参考 [ONLYOFFICE 工作表表副本及映射](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7096-L7120)及[表名分配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L1286-L1300)。

删除工作表清理其所属表部件、关系和内容类型，更新其他表的普通工作表引用及结构化依赖；失去目标的引用写为 `#REF!`。候选计算使用待删部件列表，保留仍存在的表。创建/删除部件、引用、缓存、视图和选择合为精确历史，支持保存重开和现有打印。已支持的原生筛选随副本保留独立的条件和隐藏来源；未知表资源归属、未知排序元数据、公式扩展和预算失败保持原子拒绝。复制仍受每工作簿 256 张表、4096 列定义及原有历史/输出上限。实现归 [`table-sheet.mbt`](../../../modules/formats/src/xlsx/table-sheet.mbt)、[`sheet-copy.mbt`](../../../modules/formats/src/xlsx/sheet-copy.mbt)及 [`sheet-delete.mbt`](../../../modules/formats/src/xlsx/sheet-delete.mbt)。

当前接通区域创建、范围调整、导入、查询、普通数据编辑、表/列改名、计算列创作/重填、总计设置、整行/列插删同步、工作表资源操作、含表工作簿的名称创作及原生表筛选。筛选中的范围及整轴结构同步已接通；表内行排序已接通；原生表保持整行排序，自定义样式定义创作沿上述命令；其余格式覆盖继续实施。未修改的样式定义保留；只有已支持的表定义和样式才解除 `tableParts` 未呈现诊断，其余仍保护打印。未知表筛选继续保护计算修改并保留源。

结构化引用依据 [ONLYOFFICE cStrucTable](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L2352-L2628)的行段、列身份、当前行及转义行为。实现归 [`table.mbt`](../../../modules/formats/src/xlsx/table.mbt)、[`structured-reference.mbt`](../../../modules/formats/src/xlsx/structured-reference.mbt)、[`table-rename.mbt`](../../../modules/formats/src/xlsx/table-rename.mbt)及 [`xlsx-tables.tsx`](../../../packages/xlsx/src/react/xlsx-tables.tsx)，复用既有事务和绘制模型。
