# DOCX 数学公式

[格式合同目录](../formats.md)

### DOCX 行内分数

普通正文及普通单元格段落可读取直接嵌入的 `m:oMath/m:f` 横线分数。平面参数面板处理单层分数，分子和分母为普通 `m:r/m:t`；默认接受数字及简单运算标点，字母须显式声明 `m:sty m:val="p"` 正体。数学 run 可携带完整的 `w:rPr` 字体、字号和颜色；两项参数及各 run 要求同一外观。其他属性、混合数学样式和未知公式保留源并报告诊断。分数与脚标的组合读取归[嵌套行内数学](#docx-嵌套行内数学)。分子和分母均非空，合计最多 4096 个 UTF-16 单元。

宿主在现有字体 profile 中提供数学 run 显式指定的字体；没有完整的 run 外观时，使用设置部件 `m:mathFont`，默认 `Cambria Math`。核心需要实际字体的行度量及 U+2217 字形计算数学轴；缺少字体或字形明确拒绝布局。行内参数采用 0.76 字号系数，分子分母居中，横线宽度取两者较大值。公式参与逐行基线、行高和现有段落缓存预算，使用已有文字、矩形及变换图元输出 Canvas/PDF；语义文字为 `(分子)/(分母)`。

属性栏可插入、加载、修改和删除当前范围内的分数。`DocumentEditor.objects.insertMathFraction({numerator, denominator})` 在普通文字选区插入，替换所选文字并保留两侧文字和格式。核心复用段内原生对象插入路径，写入正体 `m:oMath/m:f`。两个参数要求非空单行文字，合计最多 4096 个 UTF-16 单元；目录最多 256 项。

`mathFractions()` 返回绑定 `documentId` 和 `revision` 的目录，项含原生 XML 身份 `id`、分子、分母及保护原因。可编辑项的 `format` 返回实际字体 `family`、字号 `size` 和颜色 `color`；受保护项为 `null`。`editMathFraction(source, id, value)` 修改指定分数，`value=null` 删除。插入和修改可携带完整的 `format`，统一设置分子分母外观；省略时，插入沿当前继承，修改保留原外观。字号为 0.5–409 pt 的半点值，颜色为六位 RGB，字体须提供实际资源。属性栏加载分数后显示对应控件。过期目录、受保护容器、修订和未知公式源明确拒绝；字体及完整布局预检失败时保留源和历史。相同参数及相同直接格式不创建历史，每项实际编辑可精确撤销/重做并保存重开。

公式在正文及普通格中占一个逻辑位置。插入后光标位于公式之后，默认面板恢复原生输入焦点；可在公式两侧键入、插入制表符/软换行、Enter 换段及边界合段。Delete/Backspace 和范围替换整体删除公式；保留的公式不改内部源。组合输入沿既有候选、取消及单项提交处理。搜索将公式计为一个对象位置，避免后续文字查找/替换错位；纯文字选择查询使用 `(分子)/(分母)`。点击受支持公式可选择其整体，不停止编辑。

原生富文本剪贴板已接通分数复制、剪切、正文范围粘贴及普通矩形单元格粘贴。纯文字和 TSV 使用线性表达式；原生片段保存可编辑 OMML，并写入实际数学字体、字号和颜色，避免单独复制公式时丢失外观。接收文档须供应该字体。粘贴复用现有段落/表格事务、资源和完整布局预检；支持目标公式覆盖、表格扩张、继续原生输入、一项精确历史和重开。分子/分母修改保留显式外观。未知、错位、混合外观及不完整源拒绝，文档分数总数限 256 项。

`queryFormatting()` 分别返回输入的 `inputReason`、通用格式的 `reason`，字体/字号/RGB 文字色的独立 `fontReason`，以及段落属性的 `paragraphReason`。宿主按核心输入状态设置原生输入框只读；格式不可用不再阻止已支持的输入。正文及普通格中的公式两侧文字可使用既有字符格式、格式查询及格式复制；光标可设置待输入格式，并修改所在段落的对齐、缩进和间距。组合输入、原生源及精确历史沿原路径处理。

非折叠选区包含完整、已支持的公式时，可通过既有字体、字号和文字颜色控件一起修改公式与周围普通文字。`fontReason` 为空表示这三项可用；`character.family/size/color` 返回实际共同或混合值，通用 `reason` 保留其他操作的保护原因。核心只接受这三项的 Set/Keep，保留每个未改属性；数学字号接受 0.5–409 点的半点值，文字色为六位 RGB。含公式选区可修改既有段落对齐、缩进、间距、制表位及分页属性；`paragraphReason` 为空表示可用，查询返回实际段落值，公式内部源保持不变。Clear 字符属性、自动色、粗体等其他字符属性、列表及格式刷继续保护。

公式原结构、文字和版式参数保持，只更新数学 run 及已有控制属性中的完整统一字体属性；新增 `w:rPr` 放在已有 `m:rPr` 之后。已有相同显式值不新增历史，首次设置可固化继承值。MoonBit `apply_format/set_character_format/set_paragraph_format` 在修改公式范围或含公式段落属性时使用 probe、profile 和 images 做完整布局预检，失败保留原包、选择和历史。Wasm/Worker 的 `applyFormat/setCharacterFormat/setParagraphFormat` 在 format 后接受可选字体 profile；默认编辑宿主传入已有资源 profile，普通文字命令不新增字体上下文要求。公式范围缺少上下文或字体映射时在提交前拒绝。

实现归 [math-range-format.mbt](../../../modules/formats/src/docx/math-range-format.mbt)，沿 [ONLYOFFICE 数学文字属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/base.js#L1016-L1071)的整体及控制属性语义；复用现有 OMML 属性写回。分数面板仍可显式修改平面分数的整体数学外观。未知公式、源注释/处理指令、修订、文档保护和未支持容器继续保护，失败保留源与历史。支持的数学结构已有 [MathML 交换输出](docx-output.md#docx-html-与-markdown)。局部/混合数学格式、更多 LaTeX 语法和完整数学排版仍待实现。

片段校验归 [`math-clipboard.mbt`](../../../modules/formats/src/docx/math-clipboard.mbt)，统一外观读取归 [`math-style.mbt`](../../../modules/formats/src/docx/math-style.mbt)。完整公式复制参考 [ONLYOFFICE ParaMath.Copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L594-L612)；数学 run 中的 Word 属性位置按 [Open XML SDK schema](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/data/schemas/schemas_openxmlformats_org_officeDocument_2006_math.json#L45-L59)核对。

整体数学格式参考 [ONLYOFFICE ParaMath.Apply_TextPr](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L1161-L1204)，沿现有分数候选、字体预检及原生属性写回，不增加独立格式状态。

段内文字及换段复用 [`body-field-input.mbt`](../../../modules/formats/src/docx/body-field-input.mbt)，源结构参照 [ONLYOFFICE Paragraph.Split](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L13838-L13881)及 [ParaMath.Split](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L3001-L3034)。当前仅开放公式两侧及整体操作，公式内部通过分数面板编辑。

编辑归 [`math-edit.mbt`](../../../modules/formats/src/docx/math-edit.mbt)，接口校验归 [`docx-math.ts`](../../../packages/docx/src/core/docx-math.ts)，默认面板归 [`docx-math.tsx`](../../../packages/docx/src/react/docx-math.tsx)。

读取归 [`math-read.mbt`](../../../modules/formats/src/docx/math-read.mbt)及 [`math-run.mbt`](../../../modules/formats/src/docx/math-run.mbt)，布局归 [`layout/math-fraction.mbt`](../../../modules/layout/src/math-fraction.mbt)。数学轴参考 [ONLYOFFICE Math.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L2520-L2525)，参数缩放、间距及横线规则参考 [fraction.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/fraction.js#L352-L459)和[分子分母间距](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/fraction.js#L821-L909)。私有测试使用带完整许可的 DejaVu Math 字体，公开构建不依赖私有资源。

### DOCX 嵌套行内数学

正文和普通单元格可读取 `m:oMath` 内的横线分数、上下标及横向组合。各参数可递归包含同类结构，保留原生 OMML。所有数学 run 要求统一字体、字号和颜色，文字与正体声明沿上述合同；未知结构、混合外观、修订和扩展继续保护。

核心使用 `MathExpression` 的 `Text`、`Row`、`Fraction`、`Scripts`、`Root`、`Delimited`、`Nary`、`Matrix`，统一由 `MathFormula` 承载。`Row` 和 `Delimited` 使用不可变子项数组。解析与布局在递归及缓存序列化前检查：根深度为 0，最大深度 16，最多 256 项结构/run 节点（横向组合计一项），文字合计 4096 个 UTF-16 单元。原生数学对象目录仍最多 256 项；超限原子拒绝。Web flow 使用 `kind="math"` 和 `{expression, style}`，沿同一预算校验。

子参数递归按 0.76 缩放，横向组合按基线对齐；分数及结构化基底的单/双脚标使用实际字体度量。Canvas/PDF 继续消费核心已定位图元。线性文字用括号表达嵌套关系，供语义层、选择、纯文字和 TSV 使用。

公式占一个逻辑位置，支持两侧原生输入、整式删除/替换、富文本复制/剪切、跨文档粘贴、精确历史及重开。周边编辑保留原公式源；富文本写回实际统一外观及递归结构。已有分数/脚标参数 API 和面板只修改平面参数，遇到嵌套内容返回保护原因，避免扁平化覆盖。嵌套参数可通过下述 LaTeX 表单或 SDK 替换；单式独立段落归[独立公式合同](#docx-独立公式段落)；多行公式归[多行公式合同](#docx-多行公式)；内部光标、局部格式与更多结构/语法仍待实现。

结构及边界归 [`math-expression.mbt`](../../../modules/layout/src/math-expression.mbt)，递归测量归 [`math-layout.mbt`](../../../modules/layout/src/math-layout.mbt)，读取归 [`math-read.mbt`](../../../modules/formats/src/docx/math-read.mbt)，写回归 [`math-markup.mbt`](../../../modules/formats/src/docx/math-markup.mbt)。脚标的文字/结构化基底分支沿上述 ONLYOFFICE 定位规则。

### DOCX 独立公式段落

正文和普通单元格支持 `m:oMathPara` 包装的单个 `m:oMath`，复用上述数学结构、统一外观和预算。包装整体占一个逻辑位置，目录不会把内层表达式重复列出。独立段落按 `m:oMathParaPr/m:jc` 对齐，接受 left、center、centerGroup 和 right；缺省沿设置中的 `m:defJc`，再回退居中。centerGroup 在单式范围内按居中处理。公式旁有普通文字或段落带编号时使用段落对齐；周边原生输入保留原包装。语义依据 [ONLYOFFICE 行内模式判断及数学对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L2269-L2332)。

默认数学面板提供“插入独立公式”。`DocumentEditor.objects.insertMath(value, true)` 和 Wasm/Worker 的 `{ action: "insert", latex, display: true, format? }` 走同一事务；MoonBit 为 `edit_math(..., display=true)`。省略或 false 保留行内插入。替换当前范围后，非空段落按插入点拆为前文、公式和后文；空段落直接承载公式。统一外观、结构修改和删除复用已有公式目录与命令，更新保留包装和对齐源，删除移除整个包装。独立插入、段落拆分和范围替换共用一项精确历史。

正文和普通格的原生富文本片段保留包装、有效对齐及统一数学外观，跨文档粘贴后可继续修改。保存重开保留原生内容；Canvas、语义与 PDF 使用同一数学基线和段落位置。未知包装/属性、多表达式、混合外观、源注释及既有未支持结构继续保护。软换行及页/栏控制符与独立包装混排仍需逐行块布局，导入给出诊断，普通输入原子拒绝；Enter 拆成相邻段落仍走既有路径。较大显示运算符和上下堆叠极限归下述[求和与积分](#docx-行内求和与积分)；局部格式继续实施。实现归 [math-display.mbt](../../../modules/formats/src/docx/math-display.mbt)、[math-read.mbt](../../../modules/formats/src/docx/math-read.mbt)、[math-edit.mbt](../../../modules/formats/src/docx/math-edit.mbt)和[原生输入](../../../modules/formats/src/docx/body-field-input.mbt)。

### DOCX 多行公式

正文和普通格支持原生 `m:eqArr`，可置于行内或独立公式包装。各行可嵌套已有分数、脚标、根式、括号、运算符和矩阵；整体仍占一个逻辑位置。顶层数学文字中的 `&` 按两段一组对齐，第一段右对齐、第二段左对齐，各组紧接；没有配对的末段按上游最大维度宽度居中。各行沿最大上升/下降距离、字号及默认最小间距排版，整体基线接受 top、center、bottom。空对齐段保持零宽，整行为空时使用数学字体的 `⬚` 占位。Canvas/PDF 共用核心定位结果。

默认公式面板及既有 `insertMath` / `editMath` 接受 `\begin{aligned}x&=1\\long&=2\end{aligned}` 和 `\begin{gathered}x\\y\end{gathered}`。可用 `[t]`、`[c]`、`[b]` 指定基线，末尾换行不额外增加一行。`aligned` 接受多组及不同段数；`gathered` 每行只有一个表达式。目录输出显式基线的规范化环境；没有对齐点时输出 `gathered`。独立插入沿原有范围替换和段落拆分事务，整体外观、结构替换、周边原生输入、富文本复制、精确历史及保存重开共用原入口。

模型为 `EquationArray(baseAlignment, rows)`，flow 为 `{kind:"equationArray", baseAlignment, rows}`；各行是表达式或 `null` 的数组。最多 64 行、每行 64 段，并沿整个公式的深度 16、256 节点和 4096 个文字单元预算检查，空段计入节点预算。语义及纯文字以分号分隔各行，不输出对齐标记。统一控制外观保存在原生 `ctrlPr`，全空公式也保留字体、字号和颜色。接受默认行距及 maxDist/objDist 的关闭值；自定义间距、局部/混合外观、对齐文字中的字面量 `&` 和未知元数据继续保护。单个包装内的多个 `oMath`、强制软换行及内部字符光标仍待实现。

读取及保护归 [`omml/math-equation-array.mbt`](../../../modules/formats/src/internal/omml/math-equation-array.mbt)，LaTeX 复用 [`latex-matrix.mbt`](../../../modules/formats/src/internal/omml/latex-matrix.mbt)，原生写回归 [`markup.mbt`](../../../modules/formats/src/internal/omml/markup.mbt)，布局归 [`layout/math-equation-array.mbt`](../../../modules/layout/src/math-equation-array.mbt)，类型和传输校验归 [`math.ts`](../../../packages/wasm/src/abi/math.ts)。定位依据 [ONLYOFFICE EqArray 度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/matrix.js#L1429-L1508)及[对齐偏移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/mathContent.js#L438-L479)。

### DOCX LaTeX 公式编辑

默认“数学公式”面板和 `DocumentEditor.objects.insertMath({latex, format?})` 可在正文/普通格中创建嵌套公式，替换当前文字范围并恢复原生输入焦点。支持横线 `\frac{分子}{分母}`、`_{下标}`、`^{上标}`、根式 `\sqrt{被开方项}` 与 `\sqrt[次数]{被开方项}`、花括号分组、横向组合、`\text{原文}`、[可伸展括号](#docx-可伸展括号)、[行内求和与积分](#docx-行内求和与积分)和[矩阵](#docx-行内矩阵)。单字符脚标可省略花括号，两个脚标可交换输入顺序；重复同类脚标和缺失参数拒绝。当前字母与文本均使用正体数学 run。

公式中的普通空格忽略，`\text{...}` 中的空格保留。文字内的 `{ } _ % $ # &` 使用反斜线转义；反斜线、尖号和波浪线可用 `\textbackslash{}`、`\textasciicircum{}`、`\textasciitilde{}` 表示。数学序列也接受 `\backslash` 与支持的单字符转义。宏、外部输入、注释、未映射的环境/排版命令和其他语法明确拒绝，不执行 TeX。

`mathExpressions()` 返回绑定文档身份和修订的原生目录，项含 `id`、规范化 `latex`、实际统一 `format` 和保护原因。规范化文字使用 `\text`，脚标按下标、上标顺序输出；无脚标作用的嵌套行分组展开，保留有脚标基底的结构。`editMath(source, id, value)` 替换指定公式的完整结构，`value=null` 删除。支持修改嵌套参数、切换根结构，以及统一字体/字号/颜色；省略格式沿插入继承或保留原外观。未知源、修订、源注释、受保护容器与过期目录继续拒绝。

LaTeX 源最多 131072 个 UTF-16 单元，语法嵌套最多 64 层。解析结果继续遵守上述深度 16、256 节点、4096 个文字单元和实际字体要求。源上限容纳规范化的文字转义。两个文字上限由核心定义，DOCX 与 PPTX 的 SDK 和界面使用构建生成的常量。候选原生 OMML 在字体与完整布局预检后提交，沿已有事务保存精确历史。无操作不新增历史。非法输入保留源、选择及历史，默认面板沿既有“恢复编辑”流程继续。保存重开后可加载规范化参数和实际外观再修改。

解析和规范化归 [`math-latex.mbt`](../../../modules/formats/src/docx/math-latex.mbt)，复用既有数学源编辑和排版。语法映射参考 ONLYOFFICE 的 [横线分数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/LaTeXParser.js#L286-L323)、[脚标及顺序](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/LaTeXParser.js#L1097-L1168)和[原文参数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/LaTeXParser.js#L821-L853)。输入范围比上游完整语法小，仅接受当前数学结构。

### DOCX 行内上下标

普通正文及普通单元格可读取直接嵌入的 `m:oMath/m:sSup`、`m:sSub` 和 `m:sSubSup`。平面基底和脚标为非空普通数学 run，合计最多 4096 个 UTF-16 单元。数字与简单运算符可省略正体声明；字母须声明 `m:sty m:val="p"`。各参数使用统一字体、字号和颜色，完整的 Word run 外观沿分数读取路径处理。当前接受空的结构属性；脚标对齐选项及其他扩展保留源并报告诊断。嵌套基底与参数归[嵌套行内数学](#docx-嵌套行内数学)。

核心用实际数学字体塑形基底，并按 0.76 比例塑形脚标。偏移使用 U+2B1A 的度量，下标偏移同时使用 U+2217；缺少字体或度量字形明确拒绝布局。上下标参与行基线、行高、段落缓存及资源预算，沿已有图元输出 Canvas/PDF。线性替代文字使用 `X_(下标)^(上标)`，省略不存在的一项。分数与上下标共用字体、文字边界、缓存计数和基线处理；支持的数学字号下限统一为 0.5 pt。

属性栏“上下标公式”可插入、加载、修改和删除。`DocumentEditor.objects.insertMathScript({base, subscript, superscript, format?})` 替换普通文字选区；基底非空，下标或上标可用空字符串省略，至少保留一项。核心按参数写为 `m:sSub`、`m:sSup` 或 `m:sSubSup`，修改可在三种形式之间切换，不留下旧参数。

`mathScripts()` 返回绑定 `documentId` 和 `revision` 的目录，项含原生 `id`、三个参数、保护原因及实际 `format`。`editMathScript(source, id, value)` 修改指定公式，`value=null` 删除。分数和脚标目录各返回所属的已知结构，未知源仍报告保护原因；总目录预算沿 256 项数学对象检查。过期目录、其他结构身份、修订、源注释及不支持容器明确拒绝。

`MathFormat` 为 DOCX 与 PPTX 数学共用的完整 `family`、`size` 和 `color`。插入省略格式时沿段落与数学字体设置继承，修改省略时保留原外观；显式格式写为统一 Word run 属性。相同参数及相同已有直接格式不创建历史。候选源先完成字体与完整布局预检，再提交一项精确历史；失败保持源、选择和历史。

脚标公式在正文及普通格中占一个逻辑位置。插入后光标位于公式之后，并恢复原生输入焦点。可在两侧原生输入、插入 Tab/软换行、Enter 换段及边界合段，并进行组合输入、周边文字格式和整式删除/替换。保留的公式不改内部源。包含完整数学对象的非折叠选区可统一设置字体、字号和 RGB 文字色，其余格式继续保护；基底和脚标通过属性栏或 SDK 显式编辑。

原生富文本复制/剪切、跨文档正文和普通矩形格粘贴已接通。纯文字/TSV 使用线性表达式，片段保存可编辑 OMML 及实际字体、字号和颜色；目标须供应该字体。目标脚标覆盖、表格扩张、整格清空、继续输入、精确历史及重开沿已有事务处理。片段与目标文档沿现有 256 项数学对象预算检查，未知源和字体/布局失败保留源与历史。HTML/Markdown 明确拒绝，避免丢失结构。局部/混合数学格式、斜体数学字形及更广脚标属性继续实施。

读取归 [`docx/math-read.mbt`](../../../modules/formats/src/docx/math-read.mbt)，布局归 [`layout/math-scripts.mbt`](../../../modules/layout/src/math-scripts.mbt)，共用度量与边界归 [`math-common.mbt`](../../../modules/layout/src/math-common.mbt)。偏移参考 [ONLYOFFICE 单脚标](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/degree.js#L182-L348)及[双脚标](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/degree.js#L817-L933)，度量字形归 [Math.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L2520-L2533)。

输入与源保护复用分数的对象路径。原生片段写回归 [`math-markup.mbt`](../../../modules/formats/src/docx/math-markup.mbt)，复制仍参考 [ParaMath.Copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L594-L612)，不在宿主重建数学源。

创建和参数修改复用 [`math-edit.mbt`](../../../modules/formats/src/docx/math-edit.mbt) 的候选与历史，分数和脚标共用 [`DocxMath`](../../../packages/docx/src/react/docx-math.tsx) 表单。结构参数及先后顺序按 [Open XML SDK schema](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/data/schemas/schemas_openxmlformats_org_officeDocument_2006_math.json#L1055-L1190)核对。

### DOCX 根式

正文及普通格支持 `m:rad` 平方根和带次数根式，可与分数、上下标及根式递归组合。平方根使用 `degHide=true` 和空 `m:deg`；次数可见时，次数和被开方项均非空。次数可包含受支持的数学结构。接受基本次数显示属性，未知属性、重复/缺失参数、隐藏但非空的次数及混合外观保留源并报告保护原因。

`MathExpression.Root` 保存可空次数和被开方项；flow 使用 `{kind:"root", degree, radicand}`，次数为空时明确传 `null`。参数共用实际统一字体、字号和颜色，次数按 0.6498 比例缩小。核心按字体 `5`、`g` 的实际字形度量选择根号高度，长被开方项使用伸长分支；根号横线覆盖被开方项。根号用既有向量路径输出 Canvas/PDF，字体仍须提供实际资源。小字号的根号末端按比例收敛，保持 0.5 pt 下限；路径节点计入段落缓存预算。

已有“数学公式”面板及 `insertMath` / `editMath` 支持 `\sqrt{...}` 和 `\sqrt[次数]{...}`。读取后的平方根、带次数根式及嵌套结构可修改参数、切换结构、统一外观和删除；目录提供规范化 LaTeX 和实际外观。分数/脚标专用目录跳过根式。公式仍占一个逻辑位置，沿现有原生输入、整式删除/替换、富文本复制、精确历史和重开路径处理。线性替代文字为 `sqrt(被开方项)` 或 `root[次数](被开方项)`。其他数学结构、局部/混合格式和更广根式源变体继续实施。

结构读取归 [`math-read.mbt`](../../../modules/formats/src/docx/math-read.mbt)，布局归 [`math-root.mbt`](../../../modules/layout/src/math-root.mbt)。尺寸和绘图参考 ONLYOFFICE [根号路径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/radical.js#L59-L201)、[字体度量与伸展](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/radical.js#L204-L330)及[次数/基底定位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/radical.js#L564-L681)，字号系数归 [Math.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L47-L48)。LaTeX 语法参考 [LaTeXParser.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/LaTeXParser.js#L1267-L1298)，原生参数顺序按 [Open XML SDK](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/data/schemas/schemas_openxmlformats_org_officeDocument_2006_math.json#L961-L1001)核对。

### DOCX 可伸展括号

正文及普通格支持 `m:d` 居中伸展括号，参数可嵌套分数、脚标、根式及括号。支持 `()`、`[]`、`{}`、`|`、`‖`、`⌈⌉`、`⌊⌋`、`⟨⟩`，任一侧可隐藏，左右字符可不同。每组有 1–64 个非空 `m:e` 参数，多个参数使用统一分隔符；默认是圆括号和竖线。接受省略属性、`grow=true` 与 `shp=centered`；固定大小、`match`、控制格式及其他源扩展继续保护。

核心模型为 `Delimited(open, close, separator, arguments)`，flow 使用 `{kind:"delimited", open, close, separator, arguments}`。隐藏字符为空字符串。单参数没有可见分隔符，读取时规范化为默认值，使加载后应用相同 LaTeX 保持原生源且不增加历史。公式语义、选择和纯文字按实际括号及分隔符输出，仍占一个逻辑位置。

“数学公式”面板及 `insertMath` / `editMath` 支持 `\left...\right`，用 `\middle` 分隔参数，用 `.` 隐藏一侧。字符命令包括 `\lbrace` / `\rbrace`、`\langle` / `\rangle`、`\lfloor` / `\rfloor`、`\lceil` / `\rceil`、`\vert` 和 `\Vert`；接受转义花括号及 `\|`。例如 `\left\{\frac{x_1}{2}\middle|\sqrt{q}\right.`。嵌套、统一外观、原生周边输入、整式删除、富文本复制、精确历史及重开沿既有公式路径处理。多个 `\middle` 必须使用同一字符；空参数、未配对命令与未知语法拒绝。

排版围绕数学轴确定括号高度，读取实际字体的 OpenType `MATH` 垂直变体；高度不足时按连接区拼接部件并均匀重复伸展部件。核心把实际字形轮廓转换为既有向量路径，Canvas/PDF 共用。字体须提供对应字形和足够的变体或拼接数据；缺失时原子拒绝。只读取所选字形的数据，不展开完整数学字体表。每字形最多 128 个变体、64 个部件定义，单括号最多拼接 256 个字形且轮廓少于 8192 段，单公式最多 65536 段；路径仍计入段落缓存。当前 PDF 括号以向量绘制，文字提取使用参数文字；完整线性替代文字由语义层提供。

读取与 LaTeX 分隔归 [`docx/math-delimiter.mbt`](../../../modules/formats/src/internal/omml/math-delimiter.mbt)，定位归 [`layout/math-delimiter.mbt`](../../../modules/layout/src/math-delimiter.mbt)，字体读取及轮廓归 [`math-font-variants.mbt`](../../../modules/layout/src/math-font-variants.mbt) 和 [`math-font-outline.mbt`](../../../modules/layout/src/math-font-outline.mbt)。数学轴和参数尺寸参考 [ONLYOFFICE operators.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/operators.js#L3546-L3671)，原生结构按 [Open XML SDK](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/data/schemas/schemas_openxmlformats_org_officeDocument_2006_math.json#L551-L587)核对，字体变体及连接区按 [OpenType MATH](https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathvariants-table)处理。固定大小、其他定位方式、局部数学格式及更多运算结构继续实施。

### DOCX 行内求和与积分

正文及普通格支持 `m:nary` 的求和、乘积、余积、单/双/三重积分、三种闭合积分，以及大并集、交集、逻辑或和逻辑与。参数可递归包含已有数学结构。上下限分别可见或隐藏；隐藏参数须为空，可见参数和主体须非空。接受省略 `chr` 的默认积分、`limLoc`、`grow=false` 和基本显隐属性；增长、空白可见占位、控制格式及其他扩展继续保护。

核心模型为 `Nary(operator, limitLocation, lower, upper, body)`，flow 使用 `{kind:"nary", operator, limitLocation, lower, upper, body}`，隐藏的上下限明确传 `null`。`limitLocation` 保留原生 `subSup` / `undOvr`。省略时读取对应文档设置 `intLim` / `naryLim`；默认分别为 `subSup` 和 `undOvr`。显式属性覆盖默认设置，未使用的错误设置不会影响其他数学结构。

行内公式按 ONLYOFFICE 的行内分支使用普通字号运算符和右侧上下限，保留原生位置属性供写回。核心按实际字形的墨迹宽度、上下边界和边距定位运算符；上下限按 0.76 缩小，复用单/双脚标度量，主体按数学基线对齐。符号与主体之间的间距随字号变化。Canvas/PDF 复用已有文字图元，行内 PDF 保留运算符及参数的文字映射；线性语义为 `∑_(下限)^(上限)(主体)` 等形式。

独立公式中的运算符使用字体 MATH 表的 `displayOperatorMinHeight` 及真实变体/拼装轮廓；`undOvr` 将上下限居中堆叠，`subSup` 保留右侧位置。单个或两个可见上下限沿同一布局处理。共享 `MathFormula` 的 `display` 布尔字段由段落上下文生成；DOCX 混排或编号段落、分子/分母及缩小脚标中的运算符仍用普通字号和右侧上下限。PPTX 独立数学段落沿同一实现。较大运算符在 Canvas/PDF 中以字体轮廓绘制，PDF 参数仍可提取文字，运算符本身不提供字形文字映射；完整线性语义保留。缺少 MATH 常量、变体或字体时明确失败，编辑事务保留源和历史。字号缩放继续复用路径及图元预算。

既有“数学公式”面板及 `insertMath` / `editMath` 接受 `\sum`、`\prod`、`\coprod`、`\int`、`\iint`、`\iiint`、`\oint`、`\oiint`、`\oiiint`、`\bigcup`、`\bigcap`、`\bigvee` 和 `\bigwedge`。使用 `_` / `^` 输入上下限，主体可为一个带脚标的原子或花括号分组，例如 `\sum_{i=0}^{n}{x_i}`、`\int_0^1{\frac{x}{2}}`。`\limits` 和 `\nolimits` 保留对应原生位置属性，当前行内显示均使用右侧上下限。目录提供带显式位置修饰的规范化 LaTeX。重复脚标、缺失主体、空参数及未知语法拒绝，沿现有输入与结构预算处理。

运算符沿现有公式路径完成统一外观、周边原生输入、整式删除/替换、富文本复制、精确历史及重开。分数/脚标专用目录跳过独立的 `m:nary`。相同参数与直接外观不增加历史，字体/布局失败保持文档。增长属性及局部格式继续实施；矩阵归[行内矩阵](#docx-行内矩阵)。较大运算符沿 [OpenType MATH 常量](https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathconstants-table)和字体变体，上下限间距及居中参考 [ONLYOFFICE 上下堆叠布局](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/nary.js#L1140-L1196)，未复制上游执行代码。

读取、默认设置和 LaTeX 归 [`docx/math-nary.mbt`](../../../modules/formats/src/docx/math-nary.mbt)，布局归 [`layout/math-nary.mbt`](../../../modules/layout/src/math-nary.mbt)。参考 ONLYOFFICE 的[行内分支](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/nary.js#L305-L356)、[行内符号与测量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/nary.js#L1220-L1262)、[墨迹宽度](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/mathText.js#L708-L829)及[默认位置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/math-settings.js#L308-L311)。原生结构按 [Open XML SDK](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/data/schemas/schemas_openxmlformats_org_officeDocument_2006_math.json#L875-L935)核对。

### DOCX 行内矩阵

正文及普通格支持 `m:m` 矩阵，可嵌套已有分数、脚标、根式、括号和行内运算符。每列可左对齐、居中或右对齐，整体基线可顶端、居中或底端对齐。读取原生列分组及重复列数；缺少的列描述按居中补足，较短行补为空单元格。空单元格保留为原生 `m:e`，按实际数学字体显示占位字形 `⬚`，不写成普通文字。

模型为 `Matrix(baseAlignment, columnAlignments, rows)`，flow 使用 `{kind:"matrix", baseAlignment, columnAlignments, rows}`。行、列均为不可变数组，单元格为数学表达式或明确的 `null`。最多 64 行、64 列且总格数不超过 256，空单元格也计入共用的 256 项结构预算，因此单独矩阵最多容纳 255 个空单元格。深度和文字仍沿整个公式检查。语义、选择和纯文字使用 `matrix(a,b;c,d)`；空单元格保留分隔位置。

核心按每行最大上升/下降距离和每列最大宽度排版。默认列距为一 em，行距按字号、相邻基线和最小间距计算。各格按所在行基线对齐，居中矩阵围绕数学轴定位；顶端和底端基线分别取首行和末行。Canvas/PDF 共用既有文字和矢量图元。完整的字体、字号和颜色可由矩阵 `ctrlPr` 的 Word run 属性承载，作用范围限于该矩阵参数；这使全空矩阵仍能保存外观、跨文档复制并重开。局部或混合控制格式继续保护。

“数学公式”面板及 `insertMath` / `editMath` 接受 `\begin{matrix}a&b\\c&d\end{matrix}`。`pmatrix`、`bmatrix`、`Bmatrix`、`vmatrix` 和 `Vmatrix` 复用已有可伸展分隔符。`array` 的列描述接受 `l` / `c` / `r`，可用 `[t]`、`[c]`、`[b]` 指定基线，例如 `\begin{array}[t]{lr}a&b\\c&d\end{array}`。矩阵环境中的 `&` 分列，`\\` 换行；空单元格和较短行的缺失项均保留为占位格，末尾换行不额外增加一行。文字中的保留字符沿 `\text{...}` 或转义规则处理。目录统一输出含显式对齐的 `array`，带括号矩阵输出 `\left...\right` 与该数组的组合。

矩阵沿统一公式路径完成结构/尺寸修改、整体外观、周边原生输入、整式删除/替换、富文本复制、精确历史和重开；分数/脚标专用目录跳过独立矩阵。字体、布局、语法、行列或结构预算失败保持文档。接受基本对齐、可见占位、默认间距及完整统一控制外观；隐藏占位、自定义间距、局部格式、未知源属性和其他环境明确保护或拒绝。

原生读取及 LaTeX 归 [`docx/math-matrix.mbt`](../../../modules/formats/src/internal/omml/math-matrix.mbt)，布局归 [`layout/math-matrix.mbt`](../../../modules/layout/src/math-matrix.mbt)，控制外观和递归写回归 [`math-markup.mbt`](../../../modules/formats/src/docx/math-markup.mbt)。定位参考 [ONLYOFFICE matrix.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/matrix.js#L361-L518)及[行列度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/matrix.js#L660-L715)，环境参考 [LaTeXParser.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/LaTeXParser.js#L1396-L1510)，原生结构按 [Open XML SDK](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/data/schemas/schemas_openxmlformats_org_officeDocument_2006_math.json#L10012-L10165)核对。
