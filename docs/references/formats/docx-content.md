# DOCX 内容、审阅与绘图

[格式合同目录](../formats.md)

### 水平标尺

`DocumentEditor.pages.ruler()` 返回绑定当前文档、revision、layoutId 和完整选择的 `DocumentRuler`。核心按焦点位置所在行提供页宽、物理原点、可用宽度和手柄位置；正文、普通单元格边距、实际分栏和 RTL 使用同一布局，不在 DOM 中推算文档结构。刻度以该原点为零，单位为磅，并跟随 Canvas 缩放和水平滚动。标尺值描述焦点段落，所改属性沿现有格式命令应用于选中段落。

`editRuler(source, change)` 使用既有输入队列及格式/页面源事务。每次修改合为一项历史；旧 revision、布局、选择及其他文档结果拒绝。未知源、编辑保护、格式和输出预算沿原路径校验。查询、拖动导线和取消均不修改源或历史。

| `change.kind` | 参数和结果 |
| --- | --- |
| `first` | `{ position, snap }`；只改首行相对起始缩进 |
| `hanging` | 同上；改起始缩进，并保持焦点段落首行的物理位置 |
| `left` / `right` | 同上；分别移动起始缩进（携带首行）和末尾缩进，RTL 按实际方向换算 |
| `marginLeft` / `marginRight` | 同上；修改单节左右页边距，保留尺寸、方向和其他边距；受保护节不提供手柄 |
| `tab` | `{ position, snap, index, align, remove }`；`index: -1` 新增，其余为查询中的当前索引；`align` 为 `left/right/center/decimal/bar`，`remove` 删除已有项 |

`position` 是纸张左边缘起算的物理点坐标。缩进/页边距默认按 4.5 pt 对齐，制表位按 3 pt 对齐；`snap: false` 使用 0.05 pt 精度。首行、起始缩进和制表位从实际段落原点吸附，末尾缩进从文字区域末端吸附；结果按 twip 归一化，保留小数页边距。手柄有界限制在纸张及当前文字边界内；参数还须满足现有格式上限。移动制表位保留引导线，重复位置拒绝；继承项移动/删除写入已有显式清除标记，保存重开不会复活。制表位仍最多 64 项。

默认标尺支持鼠标拖动、松开提交，Escape/指针取消保持原文档。方向键按上述步长移动，Shift 使用 36 pt，Home/End 移向纸张两端；Alt 关闭吸附。制表位可选择五类对齐后点击空白处新增，Delete/Backspace 或拖离标尺删除。制表位排序后键盘焦点跟随被移动项。UI 只保存指针导线，正文重排和源值由核心提交决定。

实现归 [`ruler.mbt`](../../../modules/formats/src/docx/ruler.mbt)，入口归 [`document-page.ts`](../../../packages/docx/src/web/document-page.ts)和[默认标尺](../../../packages/docx/src/react/docx-ruler.tsx)。参数与事务参考固定 [ONLYOFFICE Rulers.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/Rulers.js#L2245-L2310)；缩进、制表位及页边距仍使用各自已实现的 OOXML 序列化。当前为水平标尺和磅单位；多节标尺页边距、纵向标尺及通过标尺调整表格列边界未实现。

### 导入超链接文字

正文及普通单元格中的 `w:hyperlink` 已按源顺序读取其直接 run。链接内文字参与布局、命中、选区/复制、字面查找替换、格式查询与修改，以及原生输入/组合、Tab/软换行/分页符和段落拆分/合并。空链接 run 可继续输入。链接的 run 格式沿普通字符和段落样式计算；不强制替换源颜色、下划线或字符样式。Canvas 与静态 PDF 使用同一文字和格式。

文字编辑保留 `r:id`、anchor、docLocation、history、tgtFrame、tooltip、相邻注释和原关系。Enter 在新段落延续相同链接容器；合段保留原容器、局部命名空间和各 run 原段落继承的格式，不合并两个独立链接身份。文字、结构与格式仍沿同一有界历史精确撤销/重做。链接帧计入既有多段输入源预算，失败不提交源、关系或历史。

当前支持单层链接和直接 run；未知属性、目标缺失、非法 history、嵌套容器、字段及修订继续保留源并保护相关编辑。链接内插入图片暂时拒绝，避免创建当前图片编辑器不支持的容器。文字读取不获取或执行链接目标；目标操作见下节。实现归 [`hyperlink-read.mbt`](../../../modules/formats/src/docx/hyperlink-read.mbt)，容器读取与拆分参考固定 [ONLYOFFICE 链接读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Serialize2.js#L12003-L12037)及[链接拆分](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Hyperlink.js#L188-L197)。

普通左右箭头将非空文字选区收敛到对应边界，不再向右额外走一字；继续按箭头才移动。该规则与 [ONLYOFFICE MoveCursorRight](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L6051-L6092)一致，位置和保护仍由核心布局确定。

### DOCX 外部超链接

`FoundationSession/Client.execute({ operation: "setHyperlink", revision, selection, target, text })` 和 `DocumentEditor.formatting.setHyperlink(target, text?)` 创建、修改或移除正文/普通单元格的外链。target 为 HTTP、HTTPS 或 mailto 地址，null 移除链接但保留文字。地址最多 2048 UTF-16 单元，拒绝空目标、空白、控制字符、反斜杠及非法 XML/Unicode。`checkDocxHyperlink` 从两个 foundation 入口提供相同输入检查，核心仍独立校验。

非空选区只修改所选字符，可跨 run 和相邻段落。链接内光标修改当前完整链接容器；原生连续输入的末端按实际输入节点查询和修改。普通光标创建链接时须提供 text。text 为非空、至多 65536 UTF-16 单元的单行普通文字，提供时替换整个目标范围；链接内光标替换完整链接文字。替换可合并相邻段落，之后光标留在新链接末尾并可继续输入。空链接重复移除及相同目标不新增历史。

`DocxFormatting.hyperlink` 返回 `{ target, mixed, reason }`；非共同目标为 null，mixed 为 true 时可统一设置或移除，reason 说明目标保护原因。原字符格式保持，不自动套用 Hyperlink 字符样式；默认面板提供地址、显示文字、应用、移除和显式打开，外链使用新窗口及 `noopener noreferrer`。普通输入和临时组合状态不覆盖未提交地址草稿；非法地址在进入编辑队列前提示，原文档仍可编辑和保存。打开文件、查询、布局及应用链接都不请求外链。

复用字符边界拆分和关系事务。已选链接的提示、history、tgtFrame 与未选两端保留；移除容器时补齐 run 和书签的局部命名空间，保留文字、格式和注释。相同外部目标复用关系，不改写共用关系或清理旧关系。显示文字、链接 XML、新增/修改关系合为一项历史；过期 revision、活动候选、图片、未知源及源/输出预算失败均不提交。内部目标扩展见下节；docLocation、同时具有外链关系和 anchor 的组合目标及未知关系继续保护。链接样式管理归[当前格式合同](docx-editing.md#p10-当前格式编辑)，输出归[PDF 文字链接](#docx-pdf-文字链接)。范围与光标语义参考 [ONLYOFFICE 链接操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L7811-L8180)，实现归 [`hyperlink-edit.mbt`](../../../modules/formats/src/docx/hyperlink-edit.mbt)及 [`hyperlink-query.mbt`](../../../modules/formats/src/docx/hyperlink-query.mbt)。

### DOCX 绘图对象链接

正文和普通单元格的图片、基础图形目录中，`hyperlink` 返回 `{ target, reason }`。已有 `editPicture`、`editShape` 接受 `{ action: "hyperlink", id, target }`，target 为 HTTP、HTTPS、mailto 地址、`#书签名` 或 null。内部目标须对应当前可用书签，名称查找忽略大小写。默认属性面板提供应用、移除和显式打开；内部目标执行已有书签定位，外链使用新窗口及 `noopener noreferrer`。查询与应用不访问外链。

核心编辑原生 `wp:docPr/a:hlinkClick`，复用正文链接的地址检查、关系分配及有界事务。相同目标复用关系，无变化不增加历史；修改保留原提示、history、tgtFrame、身份、几何、资源和当前选择。旧关系保留。锁定、过期状态、未知动作、悬停/声音、重复或其他非可视所有者上的链接均保护原源。链接图片的 HTML/Markdown 输出沿[交换输出](docx-output.md#docx-html-与-markdown)保留地址、提示和目标窗口；基础图形共用相同链接路径输出 SVG；普通文本框保留装饰背景、可选择文字及独立的整体/文字链接。

原生富文本复制、剪切及跨文档正文、普通/合并单元格粘贴保留对象链接。片段以 `odClip:target` 携带地址；接收侧分配或复用关系，不接受对象链接的源 `r:id`。提示及点击元数据、对象身份分配和媒体沿既有片段事务处理；与普通文字的相同外链共用关系。内部目标须已存在或随完整书签一同复制，重名沿既有规则使用接收文档中的可用目标，缺失则原子拒绝。文本框整体链接与框内文字链接可同时转移。复制保留源；剪切和每次粘贴各为一项精确历史。默认按钮与原生剪切/粘贴快捷键共用入口，未解析的引用及悬停链接返回可恢复的保护原因。实现归 [`drawing-link-fragment.mbt`](../../../modules/formats/src/docx/drawing-link-fragment.mbt)，元数据独立复制依据 [ONLYOFFICE CNvPr.createDuplicate](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L8149-L8165)。

内部目标写入 `TargetMode="External"` 的 `#名称` 关系。书签改名同步所有已知对象共用的关系；删除书签仅移除点击节点，保留对象及旧关系。两者与文字 anchor 维护合为一项精确历史。扫描检查关系的全部 `r:*` 引用；以关系引用书签的文字链接、其他部件引用及未知所有者仍保护改名/删除。未使用的 XML 部件关系不参与修改。扫描最多 8388608 项节点/属性和 65536 个引用，源及历史继续受原预算约束。实现归 [`drawing-bookmark.mbt`](../../../modules/formats/src/docx/drawing-bookmark.mbt)。原生关系写法依据 [ONLYOFFICE WriteHyperlink](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Presentation/BinaryFileReaderWriter.cpp#L1898-L1928)。

PDF 使用最终对象框及原有 `URI`/`GoTo` 注释，按纸张和行内父格裁剪；浮动框使用页面坐标。内部链接指向书签的实际页和光标位置，零轴线形复用三点命中容差。文本框文字链接仍沿文字路径输出。实现归 [`drawing-link.mbt`](../../../modules/formats/src/docx/drawing-link.mbt)和 [`links-layout.mbt`](../../../modules/formats/src/docx/links-layout.mbt)。原生位置依据 [ONLYOFFICE docPr writer](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Document/BinWriter/BinaryWriterD.cpp#L7308-L7319)，属性依据其 [Hyperlink](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Hyperlink.cpp#L73-L89)；未复制上游执行代码。

### 书签与内部导航

`FoundationSession/Client.execute({ operation: "overview", revision })` 的 `bookmarks` 返回 `{ name, selection, reason }[]`，最多 4096 项。支持正文、普通单元格及单层链接内的成对书签；空光标、文字范围、跨段和交叠范围均不占逻辑文字宽度。重复名称/身份、缺失或倒置标记、列书签和未知容器保留源，以 reason 说明保护原因，selection 为 null。

`editBookmark(revision, change)` 与宿主 `DocumentEditor.review.editBookmark(change)` 接受四种命令：`{ action: "create", name, selection }`、`{ action: "rename", name, replacement }`、`{ action: "remove", name }`、`{ action: "goTo", name }`。创建/改名使用 1–40 个 ASCII 字母、数字或下划线，首字符不能为数字。名称查找及去重忽略大小写；重复创建拒绝。goTo 将光标移到当前书签起点，不改 revision 或历史。默认概览面板提供创建、改名、删除及跳转，复用原生输入和编辑队列。

`setHyperlink` 的 target 另接受 `#书签名`，必须对应当前可用书签。内部链接写入 `w:anchor`，不新增 OPC 关系；外部与内部目标可相互修改，保留原提示和直接格式。默认面板的“打开链接”执行核心定位。改名同时更新主文档及已知页眉页脚部件的 anchor 引用，包含共享和未启用变体；删除书签同时移除这些链接容器，保留文字、格式及命名空间。主文档已知简单 `PAGEREF` 随书签改名同步目标，删除目标后显示明确的缺失引用结果，缓存由显式字段刷新更新。其他 XML 部件、未关联页眉页脚中的 anchor，以及复杂或未知引用字段继续保护改名/删除；范围归[书签页码引用](docx-pages.md#书签页码引用)。

普通文字、组合输入、格式、查找替换和拆段/合段保留零宽标记。范围替换删除中间段落时，丢失的已知端点收缩到替换后的光标；同一位置的起点先于结束标记。删除含书签的表格行等其他结构操作若会破坏配对，则整项拒绝。未知标记源保持。每次创建、改名、删除及相关引用更改合为一次有界历史；保存重开保留范围和导航，预算失败不提交。当前 PDF 的可点击文字注释归[PDF 文字链接](#docx-pdf-文字链接)。


已验证字段内容之前的段首点书签可作为复杂域题注的定位目标，位置固定为零。读取检查原生字段代码和配对身份；同段的完整范围仍按原保护规则处理，普通复杂域输入权限保持。此边界由[题注目录](docx-pages.md#docx-题注目录)使用，校验归 [bookmark-read.mbt](../../../modules/formats/src/docx/bookmark-read.mbt)。

名称匹配及书签定位参考固定 [ONLYOFFICE Bookmarks.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Bookmarks.js#L353-L366)，配对插入及移除参考 [Document.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L24423-L24568)。未复制上游代码；实现归 [`bookmark-read.mbt`](../../../modules/formats/src/docx/bookmark-read.mbt)和 [`bookmark-edit.mbt`](../../../modules/formats/src/docx/bookmark-edit.mbt)。

### DOCX PDF 文字链接

既有 `FoundationSession/Client.exportPdf`、`DocumentEditor.exportPdf` 和默认导出入口自动保留正文、普通单元格、[文本框](#docx-文本框)及[页眉页脚](docx-pages.md#页眉页脚)中的已知文字链接。外链输出原始 HTTP、HTTPS 或 mailto 地址；内部链接及带 `\h` 的 `PAGEREF` 输出当前书签起点的实际页和坐标。未设置链接开关的字段只输出文字；缺少目标的 `PAGEREF` 保留缺失引用结果，不生成悬空动作。未知关系、组合目标及非法地址拒绝导出，保留原文档。

链接矩形复用已完成布局的逐行光标边界，支持换行、混合格式及单元格裁剪，不扩大到行尾空白。文本框复用核心最终行坐标，按实际溢出设置、行内父格及纸张裁剪；浮动框沿页面位置输出。PDF 写入无边框 `Link` 注释；外链使用 `URI` 动作，内部使用 `GoTo` 和真实页对象的 `XYZ` 目标，统一转换为 PDF 左下角坐标。导出不改源、选择、历史及未保存状态，不请求链接目标。

一次导出最多 65536 个矩形，目标定位与矩形查询共用 8388608 项行/光标工作预算。收集注释时预检字节，整体仍受现有 PDF 输出上限约束。图片和基础图形整体链接已接通，边界归[绘图对象链接](#docx-绘图对象链接)；更广导入兼容继续实施。MoonBit 入口归 [`links-layout.mbt`](../../../modules/formats/src/docx/links-layout.mbt)，几何归 [`links.mbt`](../../../modules/layout/src/links.mbt)，序列化归 [`write-links.mbt`](../../../modules/formats/src/pdf/write-links.mbt)。依据 [ONLYOFFICE 外链](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/PdfWriter.cpp#L1198-L1221)及[内部页目标](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/PdfWriter.cpp#L4123-L4138)，未复制上游执行代码。

### DOCX 本地批注

`FoundationSession/Client.execute({ operation: "comments", revision })` 返回 `{ revision, reason, items }`；宿主 `DocumentEditor.review.comments()` 另带 `documentId`。每项包含规范非负 `id`、`author`、`initials`、源 `date`、纯文字 `text`、逻辑 `selection`、保护 `reason`、`parent` 和 `done`。根批注的 parent 为 null，单层回复指向根 id，并使用根的范围及解决状态。支持正文、普通单元格及单层链接内的传统批注范围；单个 `commentReference` 可表示点锚点。未解析的条目保留源，selection 为 null 并说明原因；未知批注部件或不支持的扩展返回整体原因，不暴露部分列表。

`editComment(revision, change)` 和 `DocumentEditor.review.editComment(change)` 接受 `{ action: "add", text, author, initials, date, selection }`、`{ action: "update", id, text }`、`{ action: "remove", id }` 和 `{ action: "goTo", id }`。创建使用显式范围或光标，作者由宿主提供，时间为平台传入的有效 UTC ISO 字符串；核心不读账号或时钟。默认面板复用 `EditorOptions.commentAuthor`，未提供时仍可读取、修改和删除已有批注。跳转选中当前完整范围，不修改修订、源或历史；文字草稿在正文输入和拆段后保留。

`{ action: "addWord", text, author, initials, date, selection }` 要求折叠光标，由核心按 Unicode 单词边界扩展，跨字符格式和普通链接取词。光标正好位于词尾时选择前词，空白或无单词处保留点锚点；不切开代理对和组合字素。分段复用已安装的 UAX #29 实现，不使用浏览器 DOM 或词典分词。创建后选中该范围，撤销恢复原光标。默认面板在折叠光标处使用此命令；显式 `add` 仍按传入的范围或点创建。

`FoundationSession/Client.execute({ operation: "navigateComment", revision, direction: "previous" | "next" })` 返回 `{ comment: string | null, state: EditState }`；`DocumentEditor.review.navigateComment(direction)` 在现有队列内应用状态，并更新 `getCommentFocus()`。按正文和普通单元格的源顺序循环，跳过回复、已解决和不可定位的根批注。下一条选择起点严格在当前选择前端之后的批注；上一条选择终点不晚于该前端、起点更早的批注，末端循环。当前范围内的光标和点锚点按同一规则离开；没有可用项时返回 null，保留选择、源、修订和历史。默认面板提供上一条/下一条按钮。

光标处取词依据 [ONLYOFFICE AddComment](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L14184-L14227)，顺序导航目标依据 [GenOffice gotoComment](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/review-actions.ts#L284-L305)。未复制上游源码。实现归 [`comments-selection.mbt`](../../../modules/formats/src/docx/comments-selection.mbt)及 [`word-range.mbt`](../../../modules/layout/src/word-range.mbt)。

`{ action: "reply", id, text, author, initials, date }` 回复指定根批注，沿用相同文字/作者/时间上限，不创建重复正文标记。`{ action: "resolve", id, done }` 从根或回复设置整线程的解决状态，false 重新打开；已经一致时不新增历史。默认面板按根分组显示回复，提供回复编辑/单条删除、解决/重开及整线程删除。删除根同时删除其全部回复和扩展记录；单条回复删除保留根及其他回复。

`PageLayout.comments` 返回只读 `{ reason, items: [{ id, reason, rects }] }`，rect 含 `page/line/x/y/width/height`，单位为 point。仅未解决根批注产生高亮，回复共用根，点锚点显示窄条。几何复用核心塑形选区、跨页与普通单元格裁剪，并裁到物理页面；组合候选沿显示源更新，取消不改变已提交源。一次最多 4096 项、65536 个矩形，根数与页面 caret/行总数的乘积不超过 8 Mi；超限或缺失正文返回原因，不返回不完整的全局结果。单条不可定位时保留其原因和空矩形。

Web 编辑宿主按相同坐标绘制独立覆盖层。点击高亮沿既有指针/命令队列选择完整范围并定位面板，保留原生输入焦点；拖动、Shift 扩选及取消手势不触发批注跳转。重叠批注按返回顺序定位首项，其他条目仍可从面板选择。`DocumentEditor.review.getCommentFocus()` 返回最近一次成功跳转的只读 UI 身份 `{ id }`；其他批注修改会清除它。该视图状态不进入文档。解决后隐藏高亮，重新打开后恢复；缩放、翻页和选择覆盖层刷新保持核心位置。高亮不进入 R0 正文或默认静态 PDF，也不改变修订、源及历史。

新文字非空且最多 32767 UTF-16 单元，CRLF/CR 归一为 LF；作者非空且最多 255 单元，缩写最多 32，两者不接受控制字符。每文档最多 4096 条，包含回复，合计 1 Mi 文字单元。导入正文接受普通段落、字符属性及 Tab/软换行；文字替换继承首段及首 run 的属性，保留作者、日期、批注身份、外围注释和局部命名空间。可读取和删除空正文，也可显式修改。表格等未知批注正文、资源关系、共享/外部部件，以及不支持的现代扩展保持保护。

单层线程支持 `w15:commentsEx/commentEx`，用 `paraIdParent` 连接批注正文末段的 `w14:paraId`，用 `done` 记录状态。八位十六进制身份忽略大小写匹配，新增身份避开全部已有批注段落；正文修改保留线程使用的末段身份。首次回复或解决创建所需段落身份、commentsExtended 部件、主文档关系和内容类型，合为一项精确历史。空扩展部件继续可用，新根自动取得独立身份；最后删除后保留空部件和关系。缺失属性写入复用当前命名空间，保留源前缀、外围及节点内注释。缺失/重复身份、悬空或嵌套/循环回复、未知属性及共享/外部扩展继续原子保护。

已支持导入 `commentsIds` 和 `commentsExtensible`。`paraId` 连接批注末段，`durableId` 连接 UTC 元数据，两者均按八位十六进制、忽略大小写匹配；公开 id 仍为正文批注身份。修改正文保留映射、原 UTC 时间、已知 Office presenceInfo 和根批注的 follow-up 标志。向已有身份部件新增根或回复时，为新条目分配独立段落及持久 ID；已有 UTC 部件同时写入宿主提供的时间。首次线程为缺少身份的根补齐映射，不升级普通新建文件的格式。允许已有身份列表只覆盖部分批注；已有记录必须唯一且能定位，UTC 部件必须有对应身份部件。列表的 date 优先使用非空 dateUtc，缺少时读取批注正文 date；两处源属性均保持原值。

删除回复或整线程同时删除相应身份与 UTC 记录，其他记录、外围注释和关系保留；所有部件共用原子预算及精确历史。标准 `mc:Ignorable` 根属性可保留，仍逐项校验实际节点及属性，不因此忽略未知内容。重复/悬空映射、回复携带 follow-up 标志、未知 presence 扩展及共享/外部元数据返回保护原因。依据 [ONLYOFFICE 的段落及持久 ID 映射](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Document/BinWriter/BinaryWriterD.cpp#L8738-L8775)、[元数据写回](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Document/BinReader/ReaderClasses.cpp#L749-L780)及 [MS-DOCX CT_CommentExtensible](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-docx/a7b57225-42e5-43e7-8d98-d90eabf3ca25)。未复制上游源码。实现归 [`comments-modern.mbt`](../../../modules/formats/src/docx/comments-modern.mbt)；其他现代扩展继续实施。

首次创建把 comments、正文标记、主文档关系和内容类型合为一项有界事务。标记不占正文宽度；输入、格式、链接修改及拆段/合段维护范围，范围替换删除中间段落时丢失的端点收缩到替换后光标。与书签共用已有边界拆分及位置计算。其他结构操作若会破坏锚点，则原子拒绝。删除同时移除正文标记和批注正文，最后一条删除后保留空部件及关系。旧修订、活动候选和包/输出/历史预算失败不提交；保存重开及精确混合撤销重做沿原事务。正文查找、排版和默认静态 PDF 不包含批注文字。

标记与正文属性依据 [ONLYOFFICE Annotations.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Logic/Annotations.cpp#L70-L145)、[RunContent.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Logic/RunContent.cpp#L752-L803)及 [Comments.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Comments.cpp#L281-L291)；跨段端点参考 [Document.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L22584-L22616)。线程格式依据 [Comments.cpp 的扩展属性](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Comments.cpp#L420-L433)、[ReaderClasses.cpp 的末段身份与父关系](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Document/BinReader/ReaderClasses.cpp#L659-L748)及 [BinaryWriterD.cpp 的回复映射](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Document/BinWriter/BinaryWriterD.cpp#L8692-L8738)。高亮与命中参考 [Comments.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Comments.js#L923-L953)及[标记绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Comments.js#L1383-L1421)。未复制上游源码。实现归 [`comments-read.mbt`](../../../modules/formats/src/docx/comments-read.mbt)、[`comments-edit.mbt`](../../../modules/formats/src/docx/comments-edit.mbt)、[`comments-threads.mbt`](../../../modules/formats/src/docx/comments-threads.mbt)、[`comments-range.mbt`](../../../modules/formats/src/docx/comments-range.mbt)、[`comments-layout.mbt`](../../../modules/formats/src/docx/comments-layout.mbt)及 [`docx-comments.tsx`](../../../packages/docx/src/react/docx-comments.tsx)。其他现代批注兼容归 [P14](../roadmap.md#p14-兼容与性能已完成)。

### DOCX 修订审阅

`DocumentEditor.review.revisions()` 返回绑定 `documentId/revision` 的 `DocumentRevisions`。目录按正文源顺序列出 `id/sourceId/kind/element/author/date/text/paragraph/reason`；`kind` 为 `insert`、`delete`、`rowInsert`、`rowDelete`、`rowFormat`、`tableFormat`、`cellFormat`、`characterFormat`、`paragraphFormat` 或 `unsupported`。`id` 是当前 XML 节点身份，`sourceId` 保留原生修订编号，不能互换。查询不改变源、选择或历史。默认面板显示文字预览、作者和日期，提供作者与类型组合筛选、逐项接受/拒绝及所示条目的批量接受/拒绝。

批量按钮与列表共用当前作者和类型筛选结果。默认显示全部条目时处理全部修订；筛选后只提交所示身份，沿同一 `resolveRevisions` 核心事务形成一步精确历史。列表为空、目录过期、文档受保护、输入处于组合/拖动等未完成状态，或所示条目包含不支持内容时禁用整批操作；不跳过受保护条目部分提交。筛选到可处理条目后可继续，其他作者、类型及不透明源保持。

修订目录和单次批量处理共用 4,096 项上限，由核心通过 `inputLimits().revisionEntries` 提供。

`DocumentEditor.review.resolveRevisions(catalog, { action: "accept" | "reject", ids })` 显式处理目录内的一项或一批修订。Wasm/Worker 使用 `docxRevisions` 和 `resolveDocxRevisions`，携带 revision；同步会话提供对应方法。旧目录或其他文档的目录被拒绝。核心预检整批后提交一次源历史：接受插入或拒绝删除保留普通 run，接受删除或拒绝插入移除包装及内容。拒绝删除把 `delText` 恢复为 `t`，保留样式、命名空间、空白、Tab 和软换行；其他源内容及部件保持。撤销/重做恢复精确源，处理后的普通段落可继续输入。

受支持的待处理文字修订参与正文和普通单元格的同一份布局。插入文字加下划线，删除文字加删除线，保留原字体、颜色及其他字符属性；属性修订显示当前格式。语义文本、Canvas、页面图片和 PDF 共用这些标记，处理修订后恢复普通输出。默认面板明确说明导出页面也会包含待处理标记。仅含已知普通文字或属性修订的段落支持光标输入、删除和格式修改；未知内容继续保护。

`DocumentEditor.review.tracking()` 查询 `{ revision, enabled, author, reason }`，`setTracking(author: string | null)` 启用指定作者的记录或关闭。同步 `FoundationSession` 与 Worker `FoundationClient` 使用相同方法并显式携带 revision。默认审阅面板提供作者输入和开始/停止按钮。模式属于当前会话，切换不修改源或历史；保存保留原生修订，重开默认关闭记录。宿主明确提供作者，平台为各记录事务提供 UTC 时间。

记录范围包含普通正文及同一普通单元格内的文字替换、连续输入、删除、组合输入、跨段替换和段落拆合。新增文字保存为 `w:ins`，删除原文保存为 `w:del/w:delText`；连续输入复用本作者插入身份，删除本作者新增文字直接收缩该插入。已有删除文字保留，删除键跳过它；记录中删除其他作者的插入保持保护。关闭记录后可继续普通文字编辑，已有修订保留。源运行格式、Tab、软换行、其他部件和精确历史沿原事务保持，组合取消不提交。

段落标记保存为 `pPr/rPr/ins` 或 `pPr/rPr/del`，目录沿用插入/删除类型并预览为 `¶`。原生 Enter 将新增标记留在左段，原有段末属性移到右段。删除本作者新增标记直接合段；删除原有边界保留可见段落，Backspace 与 Delete 分别移到保留标记两侧。多段替换保留原删除文字，新文字在保留内容之后插入。接受新增标记或拒绝删除标记保留边界；相反操作合段，保留左段普通格式及右段文字格式和段末属性。字符、段落和文字修订处理后，从后向前处理标记，合为一项精确历史。段末定位继续使用 1.5 pt 审阅线。

正文与同格最多处理 512 个连续普通段落，单次输入最多创建 511 个边界。跨单元格、表格或分节的边界保持保护。合段前须处理会被丢弃的右段普通格式修订和左段标记格式修订；批次内可一并处理。实现归 [tracking-paragraph.mbt](../../../modules/formats/src/docx/tracking-paragraph.mbt)与 [revision-paragraph.mbt](../../../modules/formats/src/docx/revision-paragraph.mbt)。原生标记位置及拆段行为参考 [ONLYOFFICE DocumentContent.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/DocumentContent.js#L2946-L2960)、[Paragraph.Split](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L13842-L13875)及 [RunProperty.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Logic/RunProperty.cpp#L560-L566)。未复制上游执行代码。

字符和段落格式沿原有 `setCharacterFormat/setParagraphFormat/applyFormat` 记录原生 `rPrChange/pPrChange`，默认格式控件使用同一入口。支持部分运行、多个正文段落、矩形单元格及完整表格；正文范围可包含完整普通表格。首次修改保存旧直接属性，连续修改保留这份快照和修订身份，并写入当前作者及 UTC 时间；无变化不新增历史。拒绝恢复旧属性，接受保留当前属性。段落标记格式保留在段落快照之外，并单独记录；本作者的插入文字直接更新插入内容中的格式，已有删除文字保持。光标处字符格式用于后续插入，不单独创建空修订。

跨格格式沿既有网格扩展为完整矩形，支持反向选择和合并单元格；只修改可见拥有者段落，保留垂直续接格、网格、尺寸和范围外源。空段落的字符格式写为 `pPr/rPr/rPrChange`，与 `pPrChange` 独立保存；重开后输入继承当前标记格式，新文字不复制标记的旧修订。连续原生输入沿既有输入组形成一项撤销。部分接受/拒绝后，已知剩余修订中的光标保持可用。标记定位使用段末的 1.5 pt 审阅线。原生结构参考 [ONLYOFFICE 段落属性](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Logic/ParagraphProperty.cpp#L637-L647)和 [运行属性修订](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Logic/RunProperty.cpp#L317-L328)。

格式快照与文字插入/删除可以共存。批量处理先处理字符属性，再处理段落属性，最后展开或移除文字包装，仍合为一次原子源历史。关闭记录及保存重开后，已知属性修订保留，附近文字可继续输入；格式刷和各格式组共用既有校验、输出预算和精确历史。实现归 [tracking-format.mbt](../../../modules/formats/src/docx/tracking-format.mbt)。初次属性快照、范围拆分及后续元数据更新参考 [ONLYOFFICE Run.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L8180-L8196)、[属性修订更新](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L11125-L11138)及 [Paragraph.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L15866-L15883)，未复制上游执行代码。

普通正文表格的上方/下方插行、删除行和末格 Tab 追加行沿原入口记录 `trPr/ins` 或 `trPr/del`。跨格选择按源行批量操作，每行分配独立修订编号，合为一项历史。新增行复制当前行格格式、尺寸和合并续接关系，不复制已有文字或属性修订的身份。新增行内可继续原生输入及相邻插行。删除原有行保留整行及普通 `t` 文字；删除本作者新增行直接移除它，其他已有行修订须先显式处理。

目录用 `rowInsert/rowDelete` 区分行修订，预览各格文字；默认面板提供同一作者/类型筛选、定位及逐项/批量接受和拒绝。待处理行的可见文字沿同一布局显示下划线或删除线，并进入 Canvas、图片和 PDF。定位使用实际单元格区域，包含合并拥有者和续页区域，不改编辑选区或源。接受新增行或拒绝删除行保留内容并移除标记；相反操作沿既有删行逻辑移除整行，修复纵向合并续接。末行移除时删除表格、恢复正文光标，并延续表格的段前分页。批次先处理文字、格式及段落标记，再处理行，仍为一步精确历史；未受影响段落的选区保持。

行修订支持普通文字及已知文字/格式修订。未知行属性、冲突标记、字段、图形、书签/批注身份或不透明源继续保护。待处理行修订所在表格的其他网格修改须先处理行修订。实现归 [table-row-edit.mbt](../../../modules/formats/src/docx/table-row-edit.mbt)及 [revision-row.mbt](../../../modules/formats/src/docx/revision-row.mbt)。原生记录与接受/拒绝依据 [ONLYOFFICE 行创建](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRow.js#L91-L104)、[复制行格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L10073-L10111)、[接受](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L16737-L16745)和[拒绝](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L16855-L16876)，未复制上游执行代码。

行高（最小或精确）、允许跨页及重复表头沿原有 `editTable` 命令记录 `trPr/trPrChange/trPr`。首次修改保存旧直接属性，连续修改保留第一份快照和编号，并更新作者及 UTC 时间；跨行只为实际变化的源行建记录。重复应用不增加历史。关闭记录后继续编辑当前属性，保留旧快照；接受保留当前属性，拒绝恢复旧属性和继承。目录以 `rowFormat` 预览该行文字，默认面板沿已有筛选、定位及逐项/批量审阅入口处理。

本作者新增行的格式直接保存在该插入中，不再生成空格式快照；其他待处理行插删标记须先审阅。普通行的格式修订可与随后记录的行删除共存。拒绝格式时保留当前行插删标记，按行身份重新定位后继续处理同批行修订；文字、格式和行修改共用一次精确历史。插行只复制当前格式，清除副本中的旧格式快照和修订编号。合并拥有者、未受影响选区、原生输入及保存重开沿原路径保持。

当前和旧行属性必须为已知的行高、跨页、表头及相同尾部网格设置。未知属性、重复字段、嵌套快照、旧属性中的行插删标记、网格变化及不透明源保持保护。恢复后的行尺寸和表头边界先检查再提交。行格式定位复用实际单元格区域，当前行高同时进入 Canvas 和 PDF。实现归 [revision-row-format.mbt](../../../modules/formats/src/docx/revision-row-format.mbt)、[table-properties.mbt](../../../modules/formats/src/docx/table-properties.mbt)和 [table-size.mbt](../../../modules/formats/src/docx/table-size.mbt)。原生快照及处理依据 [ONLYOFFICE 行属性记录](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRow.js#L1105-L1160)和 [CTrPrChange](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Logic/TableProperty.cpp#L1232-L1302)，未复制上游执行代码。

整表对齐、边框和默认单元格边距沿现有命令记录 `tblPr/tblPrChange/tblPr`。与行格式共用首次快照、稳定编号、当前作者/UTC、重复应用及精确历史规则；关闭记录后可继续修改当前表属性，保留导入快照和元数据。目录以 `tableFormat` 预览全表文字，定位沿实际单元格区域返回全表范围。默认面板可筛选、定位、接受和拒绝，并与文字、行格式和行插删混合处理。接受保留当前表属性，拒绝恢复旧属性及继承；恢复后的边距和边框须先通过可排版检查。

当前和旧表属性支持已知宽度、布局模式、样式引用、对齐、边框、默认边距、表外观及零缩进。未知属性、重复字段、嵌套快照和不透明源继续保护。待处理表格式修订时，先完成审阅，再改变网格或拆表，避免复制旧身份及恢复不一致的尺寸。宽度和网格修改的记录仍待实现。实现归 [revision-table-format.mbt](../../../modules/formats/src/docx/revision-table-format.mbt)与行/表共用的 [tracking-table-format.mbt](../../../modules/formats/src/docx/tracking-table-format.mbt)。原生快照参考 [ONLYOFFICE 表属性记录](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L19165-L19209)、[接受与拒绝](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L19336-L19378)及 [CTblPrChange](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Logic/TableProperty.cpp#L954-L1060)，未复制上游执行代码。

单元格填充、边框、四边边距及垂直对齐沿原命令记录 `tcPr/tcPrChange/tcPr`。首次修改保存旧直接属性，连续修改保留第一份快照和编号，并更新作者及 UTC；重复应用不增加历史。普通源行的单元格修改还按主参考建立所属表格的属性快照。目录以 `cellFormat` 预览该格文字，定位沿合并拥有者的实际区域。默认类型筛选、定位及逐项/批量接受和拒绝沿既有入口，表、行、格和文字修订可合为一步处理。

合并格的各实际源格分别记录属性，宽度、横向跨度与纵向续接字段必须与旧快照一致。接受保留当前属性，拒绝恢复旧值及继承；不能排版的恢复原子拒绝。插行只复制当前格格式，清除副本中的旧属性快照和编号。本作者新增行内直接更新当前格格式，其他待处理行插删须先审阅。提升合并续接格前，须处理该格的属性修订；同一批次可先处理格属性再处理行。导入快照可在关闭记录后继续修改当前属性，保留原作者和编号。未知、重复、嵌套或不透明属性继续保护。

实现归 [revision-cell-format.mbt](../../../modules/formats/src/docx/revision-cell-format.mbt)与表/行/格共用的 [tracking-table-format.mbt](../../../modules/formats/src/docx/tracking-table-format.mbt)。快照、普通行限制及所属表格记录依据 [ONLYOFFICE 单元格属性修订](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableCell.js#L2640-L2697)与 [CTcPrChange](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Logic/TableProperty.cpp#L1693-L1797)，未复制上游执行代码。

单次文字最多 65536 个 UTF-16 单元，并沿字素边界校验。整表宽度、列和其余结构修改的记录继续实施；不支持的修改由核心拒绝，避免无记录写入。记录中修改其他作者的插入格式保持保护。字段、图形、书签/批注标记、嵌套文字修订或未知源的混合段落继续保护。核心实现归 [tracking.mbt](../../../modules/formats/src/docx/tracking.mbt)和 [tracking-text.mbt](../../../modules/formats/src/docx/tracking-text.mbt)，默认控件归 [docx-tracking.tsx](../../../packages/docx/src/react/docx-tracking.tsx)。

`DocumentEditor.review.showRevision(catalog, id)` 定位目录中的普通文字或属性修订。它复用现有队列，请求当前布局的核心区域，显示首个区域所在页并滚动、高亮；跨页范围返回各页区域，定位时高亮首段所在页。定位不改变正文编辑选区、revision、历史、源或修改状态。高亮是临时覆盖层，其他编辑或页面操作会清除，也不进入导出。同步会话和 `FoundationClient` 提供 `execute({ operation: "revisionGeometry", revision, layoutId, id })`，返回既有 `{ layoutId, revision, rects }` 结构；底层 `docxRevisionGeometry` 命令使用 `revisionId` 字段，避免与 Worker 消息序号混用。

核心从可显示的源节点计算范围，再沿塑形后的字符边界向外对齐，处理跨页、单元格裁剪和空修订的 1.5 pt 定位线。单次最多 65536 个区域，继续受布局预算限制。旧文档目录、旧 revision/layout、未知目标、活动候选、无可见范围或不完整段落布局拒绝定位；只读定位失败保留后续编辑入口。Web 在绘制前校验布局身份和页面边界，不自行解释 OOXML 位置。

当前处理正文直属段落及普通正文表格单元格内、直接包裹普通 run 的 `w:ins/w:del`，以及普通 run 的 `rPr/rPrChange` 和段落的 `pPr/pPrChange`；已知文字包装中的普通 run 也可含属性修订。属性修订必须含一份匹配的旧属性，当前与旧属性均沿已有结构属性校验；字符属性预览该 run 的文字，段落属性预览该段文字。接受移除修订记录并保留当前属性，拒绝恢复旧属性及其命名空间；拒绝段落属性保留当前段落标记的 `rPr`，不把标记格式当作旧段落属性覆盖。空旧属性恢复继承。属性和文字修订可在一个显式批次内处理，共用历史与预算。

字段、图片、嵌套文字修订、移动、跨区域结构修订、未知内容或元数据保持保护并给出条目原因。当前或旧属性中的未知项、重复属性、旧段落属性包含标记格式或节结构、属性源中的注释/处理指令，以及未知段落标记修订继续保护。启用的文档保护由核心拒绝接受/拒绝事务，保留保护标记；只读定位不移除保护。未支持内容继续给出布局诊断，不声明完整显示。更广格式与结构修改记录、作者颜色及显示模式兼容继续实施。

目录最多 4096 项，每项预览最多 32767 UTF-16 单元，总预览最多 1 Mi 单元；作者最多 255，日期及源编号最多 128。提交接受现有 XML、包输出和历史预算，空批次、重复或缺失身份、活动候选及任意受保护项使整批失败。保留选区位于未受影响段落时的原位置；受影响时移至首个可编辑的处理段落。结构删除后改选首个可编辑的幸存段落，找不到时清除选区。

行为依据 [ONLYOFFICE 接受修订](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L11139-L11226)及[拒绝修订](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L11232-L11340)，属性恢复依据 [Run.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L8755-L8771)及 [Paragraph.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L15855-L15865)。旧段落属性排除标记格式依据 [ParagraphProperty.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Logic/ParagraphProperty.cpp#L568-L571)。未复制上游执行代码。实现归 [`revisions.mbt`](../../../modules/formats/src/docx/revisions.mbt)、[`revision-properties.mbt`](../../../modules/formats/src/docx/revision-properties.mbt)、[`document-review.ts`](../../../packages/docx/src/web/document-review.ts)及 [`docx-revisions.tsx`](../../../packages/docx/src/react/docx-revisions.tsx)。

插入下划线和删除线依据 [ONLYOFFICE line-draw-state.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/draw/line-draw-state.js#L665-L695)；范围定位参考 [Document.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L18105-L18134)。当前定位保留编辑选区，使用独立审阅高亮。实现归 [`revision-layout.mbt`](../../../modules/formats/src/docx/revision-layout.mbt)、[`flow.mbt`](../../../modules/formats/src/docx/flow.mbt)及 [`page-canvas.ts`](../../../packages/docx/src/web/page-canvas.ts)。

### DOCX 只读编辑保护

`FoundationSession/Client.execute({ operation: "documentProtection", revision })` 返回 `DocxProtection = { revision, protected, passwordRequired, reason }`，不返回密码、盐或摘要。`execute({ operation: "setDocumentProtection", revision, enabled, password })` 启用 `readOnly` 保护或验证密码后解除。已识别的 `forms` 原件也可沿同一入口解除；保护启用时继续拒绝普通编辑。`DocumentEditor.pages.documentProtection()` 返回附有 `documentId` 的 `DocumentProtection`；`setDocumentProtection(source, enabled, password = "")` 核对文档和 revision 后提交。默认页面面板提供读取、密码确认、启用及解除，提交后清空密码输入。

保护写入原生 `w:documentProtection`，可不设密码。新密码使用平台生成的 16 字节随机盐、SHA-512 和 100000 轮散列；密码最多 255 个有效 UTF-16 单元。接受 `algorithmName="SHA-512"`、`hashValue`、`saltValue`、`spinCount` 的完整凭据，导入盐限 1–64 字节、轮数限 1000000；比较摘要时累计全部字节差异。文件内容仍可读取，保存、查询、选择、复制及现有输出保持可用。

核心统一提交入口拒绝受保护文档的正文、格式、表格、资源及其他部件修改；组合输入和图片缩放也在开始候选前检查。格式查询返回限制原因，默认格式控件和原生文字输入进入只读状态。缺少设置部件时，设置、关系及内容类型一并创建；解除只删除已知保护节点，保留其他设置和原部件。保护开关沿现有精确历史撤销/重做，重新打开不创建历史。错误密码、旧 revision、未知源、活动候选及预算失败保留文档和历史。

当前支持只读模式及上述完整 SHA-512 凭据。其他限制类型、格式保护、`cryptAlgorithmSid` 等旧式参数、未知/混合算法、重复节点及节点内注释继续保护，查询给出原因。细分授权和写入文件级加密仍待实现。加密文件的读取范围归[文件 profile 与保真](shared.md#文件-profile-与保真)。设置及算法依据 [ONLYOFFICE 设置序列化](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Settings/Settings.cpp#L872-L903)与[密码验证事务](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/api.js#L14372-L14483)。实现归[保护源及事务](../../../modules/formats/src/docx/protection.mbt)、[共享散列](../../../modules/formats/src/internal/protection/password.mbt)和[默认面板](../../../packages/docx/src/react/docx-protection.tsx)，未复制上游执行代码。

### DOCX 主题颜色

`FoundationSession/Client.execute({ operation: "themeColors", revision })` 返回 `DocxThemeColors = { revision, colors }`，包含 `dk1/lt1/dk2/lt2`、`accent1`–`accent6`、`hlink/folHlink` 十二项。每项含 `slot/color/reason`；无法读取的色项颜色为 null，限制原因单独返回。`DocxThemeSlot` 与查询类型沿 `wasm/foundation`、`web/foundation` 导出。查询不修改源或历史；没有主题时返回新主题的默认颜色。

`setThemeColor(revision, slot, color)` 接受上述色项和六位 RGB。`DocumentEditor.formatting.themeColors()` 与 `setThemeColor(slot, color)` 沿现有意图队列获取 revision；默认属性面板先加载色表，确认后提交，原生文字输入保留颜色草稿。已有主题从主文档的内部关系定位；缺少主题时，按现有 Word 部件事务分配名称和关系身份，同时创建完整主题、关系及内容类型，不覆盖同名孤立部件。默认字体为 Times New Roman，正文直接格式保持。

文字及列表标记按 `w:themeColor` 解析主题，覆盖缓存 `w:val`；段落/字符样式和普通单元格文字共用相同解析。支持 `clrSchemeMapping` 的文字/背景、强调色和链接映射。`themeShade` 后接 `themeTint`，沿 HSL 亮度应用十六进制字节比例；直接颜色保持。显式设置字符颜色会清除该项的主题颜色及明暗属性，恢复继承则移除整个直接定义。源主题引用和缓存颜色在主题修改后保留，预览与 PDF 消费派生颜色。明暗计算参考 [ONLYOFFICE RtfColor](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/RtfFile/Format/RtfProperty.cpp#L496-L514)。

主题修改、首次创建的元数据及选择合为一次有界历史。撤销/重做重新派生颜色；相同有效颜色保留源和布局，不新增 revision。系统颜色读取 `lastClr`，仅在改变颜色时替换为 RGB。目标颜色的未知属性、子节点、注释、处理指令、重复/外部主题关系，文档保护与主题锁保持拒绝；非法参数、旧修订、活动候选及预算失败不提交。表格边框已接通相同主题解析及联动，归[表格边框](docx-tables.md#表格边框)。整套主题导入、表格底色与绘图对象的主题色仍属后续范围。实现归 [`theme.mbt`](../../../modules/formats/src/docx/theme.mbt)和 [`theme-edit.mbt`](../../../modules/formats/src/docx/theme-edit.mbt)。

### DOCX 主题字体

`FoundationSession/Client.execute({ operation: "themeFonts", revision })` 返回 `DocxThemeFonts = { revision, fonts }`，按标题、正文的顺序各返回 Latin、EA、CS 三槽，共六项。每项包含 `kind: "major" | "minor"`、`script: "latin" | "ea" | "cs"`、原始 `font` 和限制 `reason`；无法读取时字体为 null，空串表示源定义为空。`DocxThemeFontEdit` 为 `{ kind, script, font }`。`execute({ operation: "setThemeFonts", revision, fonts, profile })` 接受 1–6 项互不重复的修改，一次提交指定槽，保留其他槽、补充脚本、扩展和已知字体元数据。Latin 必须为非空实际字体族；EA/CS 可设空串恢复现有回退。非空字体最多 200 UTF-16 单元；不接受主题占位符、字体键分隔符、非法 XML 文字和换行。

`DocumentEditor.formatting.themeFonts()` 与 `setThemeFonts(fonts)` 复用意图队列，宿主自动携带当前字体 profile。默认面板显式加载、修改和批量应用六槽；受保护槽禁用并显示原因，其余槽可继续修改。加载恢复源值，原生输入保留面板草稿。没有主题时沿已有 Word 部件事务创建主题、关系及内容类型；未使用的字体定义不要求加载对应字体。

字符样式逐层保留 ASCII、HAnsi、东亚及复杂文字的直接或主题字体绑定。相同槽内的主题引用优先于缓存字体，较高层直接定义覆盖较低层绑定；`major/minor` 的八个 Word 字体别名分别解析到 Latin/EA/CS。空的主题槽回退到正文 Latin，再回退 Arial，遵循 [ONLYOFFICE FontScheme.checkFont](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L10082-L10135)。直接字体保持；补充脚本编辑、语言匹配及整套主题导入仍待扩展。

字体槽按 [ONLYOFFICE FontClassification](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/Run/FontClassification.js#L48-L266) 的码点范围、东亚提示和中文语言提示选择。`w:cs/rtl` 强制复杂文字槽，东亚提示及私用区保留上游优先级；复杂文字使用独立 `bCs/iCs/szCs`。核心只在字素边界拆分派生 span，保留原文字节点及 UTF-16 逻辑位置；混合格式查询、光标、空段落、普通单元格和列表标记沿相同规则，保存不拆分源 run。

提交前校验修改列表、源定义、主题锁及受影响段落的实际字体键，包含粗斜体，并检查 profile 与已注册字体。预检覆盖正文、表格及所有已存页眉页脚变体，区域内段落身份分别比较。主题和新元数据合为一次有界历史，保留选择、后续输入格式、源别名和未改 XML；无变化不增加 revision 或清除布局。旧修订、活动候选、缺字体、未知目标定义及预算失败原子拒绝。主题改变后，现有排版缓存按派生字体失效，Canvas/PDF 使用重新排版的相同结果；后续绘制失败仍沿宿主已有保存和恢复路径处理。实现归 [`theme-font.mbt`](../../../modules/formats/src/docx/theme-font.mbt)与 [`font-slots.mbt`](../../../modules/formats/src/docx/font-slots.mbt)。

### 标题导航与正文统计

`Session.overview(revision)`、`FoundationSession/Client.execute({ operation: "overview", revision })` 和 `DocumentEditor.review.overview()` 查询已提交正文。标题采用样式继承和直接段落属性中的有效 `outlineLvl`；0–8 对应一级至九级，9 表示正文。新建文件提供 Heading1–Heading9。查询包含表格单元格内的标题，不按样式名称猜测层级。

段末原生 Enter 使用当前段落样式的有效 `w:next`，新建标题因此切回 Normal。中间拆段和粘贴换行保持原样式；缺失、同名或非段落目标也继续当前样式。新段落沿既有样式应用规则清除段落直接属性，并保留直接段落方向。选择删除、换段和样式切换合为一次历史；目标样式或预算失败保持原包。规则依据 [ONLYOFFICE 的段末新段落处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L19490)。

`DocumentEditor.review.selectHeading(result, index)` 定位到标题段落起点。结果绑定文档和修订；过期结果报 `stale-overview`，受保护标题带原因并禁止导航。默认属性面板展示标题和统计。

统计只计算支持的正文逻辑文字。字符按 Unicode 标量计数；空白分隔单词，文字区段相连，段落分别计词。制表符计为空白；显式换行和分页符不计字符。图片、自动编号标记及页眉页脚等其他区域不计入；受保护或排除的正文结构提供原因，不能据此声称全文统计完整。

查询最多扫描 1,048,576 个 UTF-16 单元，返回最多 4,096 个标题，每个标题显示最多 256 个 UTF-16 单元，截断会显式标记。17 个核心用例（含后续样式及列表回归）、一条 Chromium 导航/原生输入/组合取消/历史/重开/PDF 流程及 767 项安装包断言通过；严格宿主编译包含标题查询与导航调用。P10 仍为部分交付。

### DOCX 内嵌 OLE 预览

正文行内 `w:object` 可读取已存储的 EMF 预览。当前支持标准 VML 类型 75 的矩形图片框、内部嵌入对象关系及 point 尺寸。EMF 支持完整的 32 位 RGB/位域位图、整体与逐像素透明度，以及透明背景的水平 Unicode 文字。物理框换算、原始 UTF-16 字距、文字裁剪和逻辑字号共同决定绘制位置。字体继续由宿主显式提供。MoonBit 复用现有塑形和 Zeno 路径遮罩，将整个 DOCX 预览按 300 dpi 生成 RGBA；尺寸取整数，每轴为 10–2000 像素。文字原点在该网格取整数，源字距保持。Canvas 与 PDF 使用同一预览，PDF 另保留不可见标签供文字提取。PPTX 和直接元文件布局仍使用既有矢量命令。

Flow 内容为 `{ kind: "metafile", metafile: { identity, text, images } }`。`images` 是源位图的派生资源键。布局准备后，`imageBytes` 也可按当前绘图身份返回无损 PNG；`imagePixels` 按该身份返回核心 RGBA。身份包含宽、高及像素摘要，生成资源计入图片预算。查询 Flow 保留当前修订布局的资源，重新布局及关闭释放失效资源。原始 EMF 与嵌入工作簿保持原字节。对象占一个 `U+FFFC`，标签参与可访问文字。所在段落整体只读，页面背景等独立事务仍可使用，保持精确历史和保存重开。OLE 内容编辑、激活、复制及 HTML/Markdown 转换仍受保护。

预览最多 4000000 像素。路径坐标限制在 ±1048576 栅格单位；曲线、虚线展开和遮罩累计限制为 67108864 工作单位，超限在调用栅格库或分配遮罩前拒绝。透明像素保留初始化的白色 RGB。宿主接收原始 RGBA，避免图片解码丢失透明像素的颜色；带有原始像素、轴对齐且两轴缩小的非插值预览按完整源像素块求均值，颜色与 Alpha 分别取平均。普通解码图片、旋转或仅单轴缩小仍使用既有 Canvas 采样。

输入最多 4 MiB、8192 条记录及 256 个对象句柄。单个位图每轴最多 4096 像素，累计最多 4194304 像素；文字累计最多 32767 个 UTF-16 单元。共享读取另支持下述实色 GDI 路径和 EMF+ Dual 回退，最多 32 层保存状态和 65536 个路径点/段。未知记录、EMF+ Only、调色板、字形编号、旋转字体、位图源裁剪和不受支持的变换明确拒绝。外部预览、未知 VML 几何及与文档关系冲突的派生身份保持保护；这不是通用 EMF/WMF 支持。

实现归 [OLE 预览读取](../../../modules/formats/src/docx/ole-preview.mbt)、[EMF 读取](../../../modules/formats/src/internal/image/emf.mbt)、[共享元文件布局](../../../modules/layout/src/metafile.mbt)及[预览栅格化](../../../modules/layout/src/metafile-preview.mbt)。物理框与 `TA_TOP` 文字依据固定 ONLYOFFICE core `3250a848ee4ef20c2fb8c38dc86350ec579124b8` 的 [EMF 框处理](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/raster/Metafile/Emf/EmfParser/CEmfParserBase.cpp#L875-L906)和 [SVG 文字位置](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/raster/Metafile/Wmf/WmfInterpretator/CInterpretatorSvgBase.cpp#L383-L409)。预览尺寸依据同版 [PDF 纹理转换](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/PdfWriter.cpp#L3921-L3963)，缩小取样依据其 `PdfFile/lib/splash/Splash.cc` 的 `ImageMaskScaler::vertDownscaleHorizDownscale`。`BlendFlags` 按 [MS-EMF 2.3.1.1](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emf/34e07d4f-aee6-4b63-a4bb-96996ad47669)忽略。原件及视觉资格归[测试说明](../testing.md#当前兼容证据入口)。

### DOCX 绘图框与基础图形

正文 DrawingML 矩形、椭圆和线已接通读取与矢量 Canvas/PDF。支持无文字的 `wps:wsp`，普通文本内容见下方[文本框](#docx-文本框)。画笔支持显式 RGB/无填充、实线及匹配框尺寸的未旋转几何。行内框参与行宽和行高；正文浮动框复用既有定位、图层、上下型/方形环绕及缓存。线可有一个零尺寸轴。图形不生成位图资源。

Flow 使用 `spans[].drawing: DrawingFrame | null`。框为 `{ width, height, anchor, content }`；图片内容为 `{ kind: "picture", key, crop }`，基础图形内容为 `{ kind: "shape", preset, fill, stroke, lineWidth, points, strokeAlpha }`。`preset` 为 `rect/ellipse/line/polyline`；普通形状的 `points` 为空、`strokeAlpha` 为 1，墨迹折线归[下方合同](#docx-墨迹)，颜色为六位 RGB 或空字符串，尺寸和线宽使用 point。空颜色表示不绘制该项。共享锚点类型为 `DrawingAnchor/DrawingAxis`；原生定位结果为 `Line.drawings: PlacedDrawingFrame[]`，命中使用 `Hit.drawingStart`。图片源编辑命令、裁剪值和资源键继续表达图片本身。正文可访问文字把对象单元标为 `[drawing]`。

`DocumentEditor.objects.shapes()` 返回 `{ revision, items }`，每项包含 `{ id, name, selected, preset, width, height, fill, stroke, lineWidth, anchor, reason, sizeReason, deleteReason, positionReason, textBox, textReason }`。文本框的 `textBox` 返回下述文字区域属性，普通无文字图形返回 `null`；`textReason` 说明文字区域编辑的保护原因。同步 `FoundationSession` 与 Worker `FoundationClient` 使用 `execute({ operation: "shapes", revision })`。目录最多 256 项，节点身份仅在当前会话有效；重开后重新查询。

`editShape(revision, { action: "properties", id, width, height, fill, stroke, lineWidth })` 修改完整尺寸和画笔；`{ action: "delete", id }` 显式删除。尺寸范围为 0–14400 pt，矩形/椭圆的两轴必须正值，线允许一轴为零；线宽为 0–1584 pt，有线条颜色时必须正值。核心舍入到整数 EMU，颜色使用六位 RGB 或空字符串。同步和 Worker 客户端可传字体 profile，默认宿主沿原输入屏障与队列提交。默认图形面板提供目录选择、尺寸、填充/线条、线宽及删除；旧修订的控件需要重新读取目录。

`editShape(revision, { action: "insert", preset, width, height, fill, stroke, lineWidth })` 在当前文字选择处创建行内图形。`preset` 使用 `DocxShapePreset` 的 `rect/ellipse/line`。正文、空段和普通单元格复用图片插入的源事务；受支持的跨段范围先删除并合段，再插入图形。一次实际创建只记一项历史，光标落在图形之后，继承原运行格式。图形与图片共用主文档、页眉和页脚中的未用身份，不新增媒体或关系。失败保留源、选择和历史。默认面板提供类型和尺寸，创建后选中新图形属性；初始填充为 `4472C4`，线条为黑色、1 pt，可在属性面板修改。

属性事务保留对象身份、锚点、环绕、周围运行格式和非目标部件；删除只移除目标 `w:drawing`，保留共享资源和关系。每次实际修改记一项精确历史，无变化保持修订。`noResize` 只阻止尺寸变化，`noChangeAspect` 要求保持原比例，`noDelete` 和外部对象引用阻止删除；移动锁不阻止画笔修改。文档保护、修订容器、未知锁及将被覆盖的注释/处理指令保持保护。环绕重排沿原布局预检，失败保留源、选择和历史。

普通无文字图形已随正文富文本片段复制、剪切及跨文档粘贴，支持行内与已支持的浮动锚点。行内图形还可随完整普通/合并单元格转移。默认按钮和原生快捷键沿既有片段协议执行。复制保留原生几何、画笔、名称、描述、标题及图形内的源间隙；粘贴为 `wp:docPr` 和可选 `wps:cNvPr` 分配目标中的未用身份。重复粘贴生成独立对象，源图形和目标已有身份保持。`bodyFragmentImages`、`tableFragmentImages` 的纯图形预检返回空 `images`；混合片段只解码图片，无链接图形不创建媒体或关系；整体链接沿[绘图对象链接](#docx-绘图对象链接)转移。一次实际粘贴或剪切合为一项精确历史。

`noCopy` 阻止图形富文本复制和剪切，`noDelete` 只阻止剪切及删除。未知绘图元数据、引用属性及外部关系继续保护复制；图形只携带已支持的独立属性。正文及整格粘贴在最终候选上检查图片与图形合计不超过 256 项，先扣除被替换对象，满额时仍可等量替换。格式、布局、输出或数量预算失败保留原包、选择和历史。片段校验、身份重映射及源保留归 [fragment-drawings.mbt](../../../modules/formats/src/docx/fragment-drawings.mbt)，复制依据 [ONLYOFFICE Shape.copy/fillObject](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2772-L2833)。

受支持图形段落已接通前后原生/组合输入、字符格式、查找、拆段合段和范围删除。图形占一个逻辑 `U+FFFC`，输入同名字符仍是文字。保留图形源、资源和精确混合历史，删除继续检查独立锁与外部引用。普通文字光标可命中图形边界；绘图命中和句柄同时支持图片与基础图形。图片目录只返回图片。框内文字编辑见下方文本框，纯色艺术字见 [DOCX 基础艺术字](#docx-基础艺术字)；文字描边、主题画笔、渐变、旋转/翻转、箭头、复杂图形和未知扩展继续拒绝输出，保留原始源与历史。HTML/Markdown 的图形转换尚未接通。

实现归 [drawing-frame.mbt](../../../modules/layout/src/drawing-frame.mbt)、[drawing.mbt](../../../modules/formats/src/docx/drawing.mbt)、[shape-read.mbt](../../../modules/formats/src/docx/shape-read.mbt)、[shape-editing.mbt](../../../modules/formats/src/docx/shape-editing.mbt)、[shape-insert.mbt](../../../modules/formats/src/docx/shape-insert.mbt)、[共享插入事务](../../../modules/formats/src/docx/drawing-insert.mbt)、[文字事务](../../../modules/formats/src/docx/drawing-text.mbt)及[默认面板](../../../packages/docx/src/react/docx-shapes.tsx)。轮廓复用 [basic-shape.mbt](../../../modules/layout/src/basic-shape.mbt)。源结构参考 [ONLYOFFICE Shape 读取](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Shape.cpp#L89-L168)与 [DOCX 写出](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Shape.cpp#L238-L332)，独立锁参考 [CNvSpPr](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/CNvSpPr.cpp#L87-L122)。当前范围归 [P10](../../implemented/p10-docx-core.md)。

`editShape(revision, { action: "position", id, anchor, target? })` 修改图形定位。图形与图片共用 `DocxDrawingPositionEdit`、核心 `set_drawing_anchor` 和默认定位面板。`anchor` 为 `null` 时恢复行内；浮动框支持前置/后置、两轴基准与偏移/对齐、层次、方形/上下型环绕和四边间距，参数归[图片定位](#图片定位)。图形目录返回当前 `anchor` 及 `positionReason`。

`target` 显式把浮动图形重锚到正文段落，可跨页；偏移按移除前文档计算。事务保留原运行格式、命名空间、身份、矢量源和非目标部件，选择新逻辑范围，修改合为一项精确历史。`noMove`、`noChangeWrap` 阻止定位，`noResize`、`noCopy`、`noDelete` 不阻止定位。跨段迁移遵循 `wp:anchor locked`。浮动图形要求正文容器；源不明、位置无效、布局或预算失败保持原文档与历史。默认宿主已接通指针选择、四角及键盘缩放、浮动拖动、跨段/跨页重锚和边缘翻页。图形目录的 `selected` 标记当前单对象范围，默认面板自动跟随；`noSelect` 阻止图形手势。图形允许独立调整宽高，`noChangeAspect` 存在时保持比例，`noResize` 保护缩放；图片继续保持原比例与裁剪。矩形/椭圆的最小尺寸为一个 EMU；线允许零轴，交互命中与选择框将零轴扩展为 6 pt，源尺寸和绘制不变。候选、取消、最终坐标、原生删除、历史与持久化屏障复用[绘图对象手势](#绘图对象移动与缩放手势)。

### DOCX 墨迹

默认图形面板提供选择、画笔、荧光笔、整笔橡皮、RGB 颜色和 0.5–24 pt 线宽。`DocumentEditor.objects.setInkTool({ tool, color, width })` 设置临时工具，`tool` 为 `select/pen/highlighter/eraser`。输入仍使用现有 Chromium 指针与原生文字输入。按下、移动和抬起形成一笔；Escape、指针取消或窗口失焦丢弃未完成笔画。保存及其他编辑屏障先提交完整笔画。工具切换不改变源或历史。

同步 `FoundationSession` 和 Worker `FoundationClient` 提供 `execute({ operation: "previewInk", revision, layoutId, page, stroke })`、`execute({ operation: "insertInk", revision, layoutId, page, stroke, profile })`、`execute({ operation: "eraseInk", revision, layoutId, page, x, y })`。`stroke` 为 `{ points: [x,y][], color, width, highlighter }`。坐标使用当前页面的 pt。每笔上限为 4,096 个采样点，同步与 Worker 客户端均从核心的 `inputLimits().inkPoints` 读取。预览返回透明 R0 批次，保持源、选择和历史。Web 负责采样和重放。核心校验当前布局、样本和预算，生成轮廓与原生 XML。过期布局或失败候选保留文档、修订、选择与重做。

完成的一笔是无填充的 `wps:wsp` 自定义开放折线，使用原生 `a:custGeom`、圆端/圆连接和显式 RGB。普通笔不透明，荧光笔 `strokeAlpha=0.45`；单点用极短线段显示圆点。锚点归属当前页最近的可编辑正文段落，横向相对分栏、纵向相对段落，前置且不环绕。每笔占一个原生绘图单元并产生一项历史，保留原选择范围中的文字。图形目录返回 `preset: "polyline"`；Flow 的归一化 `points` 随宽高缩放。既有图形属性、定位、删除、正文富文本剪贴板、保存重开及 Canvas/PDF/矢量 SVG 输出复用同一对象。墨迹保持无填充且描边非空，修改颜色和线宽保留透明度与路径。

命中使用距真实线段不超过半线宽加 3 pt 的范围，空外接框区域不选择或擦除墨迹。橡皮删除命中的最上层整笔，保留其他图形与未命中的笔画，服从文档保护、删除锁、引用和现有 256 项绘图上限。多条开放线、曲线、压力元数据、未知填充/画笔与扩展几何继续保护；不把不支持的路径转成错误图像。更广导入和压力笔继续实施。

实现归 [ink.mbt](../../../modules/formats/src/docx/ink.mbt)、[原生折线读取](../../../modules/formats/src/docx/shape-polyline-read.mbt)、[共享命中](../../../modules/layout/src/drawing-frame.mbt)、[指针工具](../../../packages/docx/src/web/document-ink.ts)和[默认控件](../../../packages/docx/src/react/docx-ink.tsx)。原生开放几何、Word 零原点和无填充参考 [ONLYOFFICE PolyLine](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/PolyLine.js#L180-L300)，未复制上游执行代码。

### DOCX 普通图表

正文和普通单元格支持原生行内图表的读取、插入、类型/标题/TSV 数据/尺寸/图例修改与整图删除。类型、固定外观和五种图例位置复用 [PPTX 基础图表](pptx-objects.md#pptx-基础图表)。MoonBit 共用图表模型、排版和原生 XML；XLSX 模块读取矩形数据，生成实际嵌入工作簿。Canvas、PNG 和 PDF 重放同一组图元，语义文字包含标题与数据。

同步 `FoundationSession` 与 Worker `FoundationClient` 提供 `execute({ operation: "charts", revision })` 和 `execute({ operation: "editChart", revision, chart, profile })`。查询返回 `{ revision, items: [{ id, width, height, settings, anchor, selected, reason, deleteReason, sizeReason, positionReason }] }`；`settings` 是共用 `ChartSettings`，原生配置不受支持时为 `null`。已知图表即使内容锁定，仍返回数据与几何。`id` 是当前原生绘图节点身份。编辑使用 `{ action: "insert", ...settings, width, height }`、`{ action: "update", id, ...settings, width, height }`、`{ action: "resize", id, width, height }`、`{ action: "position", id, anchor, target? }` 或 `{ action: "delete", id }`。内容、删除、尺寸和位置分别检查对应的原因字段。

Web `DocumentEditor.objects.charts()` 增加 `documentId`，`insertChart(value)` 消费当前选择，`editChart(catalog, id, value | null)` 验证文档、修订与目录身份。默认图表面板调用相同接口，提供读取/选择、类型、标题、TSV、宽高、图例、圆环空心比例及创建/修改/删除。默认框为 360×240 pt。输入和持久化沿既有队列，图表占一个逻辑位置；相邻文字输入与整图范围删除保留原生源。

宽高分别为 180–14400 pt 与 150–14400 pt，插入前必须能完整排版。单次目录最多 256 项，输入及规范化 TSV 均最多 65536 个 UTF-16 单元；类别、系列与标签上限沿共用图表合同。插入、图表部件、XLSX、关系和内容类型合为一项历史；字体、布局、缓存、权限及预算失败保持源和历史。标题、类型、图例或尺寸变化保留未改数据的工作簿路径和字节；数据变化创建独立工作簿。删除保留未引用资源，沿现有包资源策略恢复精确历史。

当前编辑要求单独拥有图表部件、已支持的原生配置，以及一致的系列缓存和嵌入数据。未知配置、不透明图表源、共享图表和未支持的文档区域保持保护。`noTextEdit` 与 `noDelete` 分别限制内容修改和删除，缩放服从 `noResize/noChangeAspect`；定位服从 `noMove/noChangeWrap`，指针选择服从 `noSelect`。数据范围绑定及复杂样式继续实施。

正文图表复用 [绘图定位](#图片定位) 和既有几何手势，支持行内、前方、后方、四周与上下环绕，保留引用轴、偏移、距离及层序。`target` 可移到另一正文段落。默认面板提供独立尺寸与位置操作；Canvas 提供四角缩放、浮动移动、键盘方向键与 Escape 取消。候选不写历史，最终操作只记一项；尺寸和位置保持原图表 XML 与工作簿字节。环绕后的可访问文字保留图表标题和数据。单元格、页眉及页脚中的浮动图表仍受保护。

正文和普通格的范围复制/剪切、跨文档粘贴及完整单元格片段已支持行内图表，复用现有剪贴板 API、MIME 与默认按钮。副本保留原生图表 XML、嵌入 XLSX 字节、名称/描述和尺寸，分配独立绘图身份、部件、工作簿及关系；只更新复制后关系的目标，后续改数据互不影响。纯文本使用图表标题和数据。图表不会进入位图解码，资源预检仍只向平台返回实际图片。

复制检查 `noCopy`，剪切另检查 `noDelete`；`noTextEdit` 保留复制、粘贴和相邻文字输入，仍保护图表内容修改。片段最多 2097152 个 UTF-16 单元，图片与图表合计最多 2 MiB 解码资源。未知命名空间/元数据、不透明源、外部图表关系、缓存不一致、字体及预算失败保持文档和历史。资源与片段合为一项事务，源和副本支持精确混合历史与重开。正文浮动图表传递保留已支持的锚点和环绕；浮动图表粘贴到单元格及未知源继续保护。实现归 [图表片段](../../../modules/formats/src/docx/chart-fragment.mbt)，独立数据参考 [ONLYOFFICE 图表复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L4959-L4983)。

实现归 [DOCX 图表事务](../../../modules/formats/src/docx/chart-edit.mbt)、[共享原生图表](../../../modules/formats/src/internal/chart/read.mbt)、[图表排版](../../../modules/layout/src/chart-legend.mbt)、[XLSX 数据读取](../../../modules/formats/src/xlsx/chart-data.mbt)及[默认面板](../../../packages/docx/src/react/docx-charts.tsx)。源关系和工作簿编辑参考 [ONLYOFFICE Word 图表编辑](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/GraphicObjects/GraphicObjects.js#L1346-L1375)。阶段范围归 [P10](../../implemented/p10-docx-core.md)。

### DOCX 基础艺术字

`editShape(revision, { action: "insertWordArt", preset, text })` 在当前正文文字选择处创建原生艺术字文本框。五种纯色预设为 `blue/gold/red/purple/green-italic`，RGB 分别为 `4472C4/FFC000/C00000/7030A0/70AD47`。文字沿文档默认字体，使用 36 pt、粗体，绿色另带斜体；段落居中、单倍行距且段前后距为零。字符属性同时写入运行和段末属性，后续原生输入保留格式。

初始框为 2700000 × 720000 EMU（约 212.6 × 56.7 pt），透明、无边框。默认浮于正文前方，两轴分别以分栏和锚点段落为基准，偏移为零，不排斥周围文字。框内垂直居中，不自动换行，使用原生 `noAutofit`；长文字可溢出，用户通过现有尺寸、文字区域及字符控件继续调整。这里提供固定初始框，内容驱动的自动尺寸仍待实现。

创建复用图形范围替换、身份分配和浮动定位候选，全部源修改合为一项精确历史，失败保留原包、选择和历史。创建后全选框内文字，默认表单聚焦既有输入控件，用户可直接替换。文字排版、查找、剪贴板、手势、删除、Canvas/PDF 和重开输入沿普通文本框路径；不新增媒体、关系或私有艺术字状态。默认 DOCX 与 PPTX 表单共用 [word-art.tsx](../../../packages/ui/src/word-art.tsx)。

`text` 必须含非空白内容，沿文本框的 XML 字符、LF 段落、Tab、软换行及 32767/256/4096 上限。默认浮动创建要求普通正文位置；单元格、嵌套文本框及其他保护容器明确拒绝。字体 probe 可用时预检普通及粗体/粗斜体字体；缺字体、过期修订、活动候选、源或历史预算失败不提交。文字描边、渐变、阴影、变形和三维效果继续实施。

实现归 [word-art.mbt](../../../modules/formats/src/docx/word-art.mbt)。36 pt、透明无边框、居中和原生 Word 段落沿 [ONLYOFFICE createTextArt](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L8794-L8912)；字体大小的格式区分另见 [private_createWordArt](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/apiBuilder.js#L33296-L33365)。五种纯色配方与固定初始框取自 GenOffice 功能目标；未复制上游执行代码。

### 原生段落框

DOCX 导入识别 `pPr/framePr` 的 `notBeside` 框架。相邻同参数的段落按原生块顺序共享框架；表格从末行首格的首段读取框架参数，可以与后续同参数段落组成一组。`Paragraph.frame` 保留原生尺寸、锚点、位置、间距及四边单实线边框，缺省时省略该字段。源 `framePr` 和段落身份保留，普通文字编辑、搜索、光标、标尺与精确历史沿现有入口。

宽度为零时使用可用栏宽，并按原生单段或表格内容确定自动宽度；高度支持 `auto/atLeast/exact`。布局按 page/margin/text 锚点定位，框架占位参与正文上下避让；实际文字、底色和边框共用框架裁剪。纸张尺寸保留源整数 twip，不吸附到附近纸型。外层表格的兼容定位见[表格自动适配](docx-tables.md#表格自动适配)。

当前支持同一物理页内的框架和一致边框组。跨页框架、环绕排版、框内锚定绘图、脚注及混合段落边框继续拒绝；原件与历史保留。原生规则依据 [ONLYOFFICE 框架分组](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/DocumentContentBase.js#L2586-L2610)、[框架测量、定位及避让](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L4527-L4869)、[裁剪](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L5434-L5454)和[表格框架属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L3956-L3970)，未复制上游执行代码。实现归 [`paragraph-frame.mbt`](../../../modules/formats/src/docx/paragraph-frame.mbt) 与 [`frame-placement.mbt`](../../../modules/layout/src/frame-placement.mbt)。

### DOCX 文本框

普通 `wps:txbx/w:txbxContent` 已接通核心读取、富文本排版与 Canvas/PDF。内容使用原生 Word 段落、样式和字体整形，保留字符装饰、对齐、缩进、段距及行距。矩形与椭圆复用绘图框；椭圆先取内接文字区域，再应用四边边距。文字不转成图片。可访问页面文字包含框内各行。正文逻辑位置仍只计一个对象，框内文字使用自身的段落身份和偏移。

Flow 的文本框内容为 `{ kind: "textBox", shape, text }`。`shape` 包含原图形的 `preset/fill/stroke/lineWidth`，`text` 为 `{ paragraphs, insets, anchor, wrap, clip, flowFrames }`。`paragraphs` 使用原段落结构；`insets` 按上、右、下、左排列，单位为 pt，默认分别为 3.6、7.2、3.6、7.2。`anchor` 支持 `t/ctr/b`，`wrap` 对应 `square/none`。默认文字可溢出；两轴都声明 `clip` 时裁剪到框边界。普通框的 `flowFrames` 为空；链接框保存前序框及本框的可用宽高，单位为 pt。核心缓存包含文字、样式、框尺寸和链接文字区域，缩放后重新断行。

正文中的原生 `wps:txbx/wps:linkedTxbx` 链接框复用普通段落排版。核心按 `id/seq` 验证唯一起点和连续顺序，再把完整行送入各框；不同宽度重新断行，保留源偏移。XML 顺序不决定链顺序，绘制层保持原序，可访问文字按链顺序排列。当前支持最多 64 个水平、顶部对齐、无自动适配的矩形浮动框，文字按各框高度裁剪。框、框内文字、移动和删除均只读，保存保留原始链和内容。缺失起点、重复或跳号、错误属性、页边链、段落边框及 keepLines/keepNext 继续拒绝。实现归 [linked-text-box.mbt](../../../modules/formats/src/docx/linked-text-box.mbt)和[链接框排版](../../../modules/layout/src/linked-text-box.mbt)，源结构参考 [ONLYOFFICE LinkedTxbx](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Shape.cpp#L144-L168)。

浮动框允许通过严格校验的零相对宽高、`bwMode=auto` 和标准 hiddenFill/hiddenLine 备份。零百分比不改变绝对尺寸，隐藏画笔不覆盖活动画笔；正百分比、未知扩展和活动黑白变换仍保护。几何依据 [ONLYOFFICE 相对尺寸](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ParaDrawing.js#L421-L449)。

`editShape(revision, { action: "insert", preset, text, width, height, fill, stroke, lineWidth })` 创建原生文本框。提供 `text`（包括空字符串）时，`preset` 支持 `rect/ellipse`；省略 `text` 时仍创建上述无文字图形。初始文字以 LF 分段，支持 Tab 和 `U+2028` 软换行，拒绝 CR、无效 XML 字符及分页/分栏控制。正文、空段、普通单元格和受支持范围替换复用同一插入事务，不新增媒体或关系。创建只记一项历史，光标进入末段文字末尾；保存重开后仍可继续输入。

默认图形面板提供文本框类型与初始文字，创建矩形框后聚焦原输入控件。初始填充为白色，线条为黑色、1 pt；SDK 也可创建椭圆文本框。空框保留一个原生空段落。

普通文本框已随正文富文本片段复制、剪切及跨文档粘贴；行内文本框还可随完整普通/合并单元格转移。复制保留原生框、画笔、边距、垂直对齐、换行、溢出和锚点。框内段落复用原片段序列化，把源样式和主题转成明确格式；粘贴不依赖源文档的样式身份。文字、空段、Tab 和软换行保留，文字不转成图片。`docPr`、`cNvPr` 及可选 `txbx` 身份使用目标中的未用值，重复粘贴后可独立编辑。纯文本框预检不返回图片，也不创建媒体。框内外链通过既有片段协议携带目标并在接收文档重建关系；内部链接要求接收文档已有可用书签。

选择边框后，默认复制按钮和原生剪切/粘贴快捷键沿既有协议执行。框内文字范围也可复制为普通富文本片段，再粘贴到已有文字区域。一次剪切或粘贴只记一项精确历史，保存重开后仍可编辑。`noCopy` 阻止复制和剪切，`noDelete` 只阻止剪切；`noTextEdit` 保留在对象上，继续保护框内输入。未知文字元数据、未解析的样式/主题引用、嵌套绘图和不支持的内容继续保护。浮动文本框要求正文目标；最终布局、数量或历史预算失败保留源、选择及历史。行为参考 [ONLYOFFICE 文本框内容与 bodyPr 复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2772-L2833)，实现归 [fragment-drawings.mbt](../../../modules/formats/src/docx/fragment-drawings.mbt)。

已有文本框可通过 `shapes()`、`editShape` 和默认图形面板修改尺寸、画笔及定位，也可使用原绘图手势。事务保留 `txbxContent` 原文、样式与非目标部件，复用独立锁、单项历史和保存重开。创建与读取共用预设文字区域及边距校验，无可用区域时直接拒绝。提供字体 probe 时，框创建或修改同时预检内部文字排版；字体、尺寸或布局失败保留源与历史。

`editShape(revision, { action: "textBox", id, properties: { insets, anchor, wrap, clip } })` 修改已有文本框的文字区域。`DocxTextBoxProperties.insets` 为上、右、下、左四边距，单位为 pt，各值范围 0–14400，核心舍入到整数 EMU；预设文字区域扣除边距后必须仍有可用宽高。`anchor` 支持 `t/ctr/b`，`wrap` 控制框内换行，`clip` 同时控制两轴是否裁剪到框边界。默认面板提供对应控件与“应用文本框排版”。

命令只更新原生 `bodyPr` 对应属性，保留其他声明、子节点、注释、框内文字、绘图身份、框尺寸、锚点和选择。缺失 `bodyPr` 时创建普通无自动适配的声明；有效属性相同时不写源、不增加修订或历史。一次实际修改只记一项精确历史，保存重开后保留属性和框内输入能力。`noTextEdit`、`noSelect` 及文档保护阻止该命令；尺寸、移动和删除锁继续各自作用于框操作。提供字体 probe 时沿原布局预检；无效属性、无可用文字区域、缺字体或布局预算失败保留源、选择与历史。实现归 [text-box-properties.mbt](../../../modules/formats/src/docx/text-box-properties.mbt)及[默认控件](../../../packages/docx/src/react/docx-text-box-properties.tsx)，语义参考 [ONLYOFFICE 垂直对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L1942-L1968)与[边距修改](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2037-L2083)。自动适配、多栏、竖排及独立两轴溢出继续实施。

单击文本框内侧进入文字选择，边框仍用于选择整个对象。框内命中、光标、扩选、方向键与 Home/End 使用最终行几何；标尺使用框内可用文字区域。现有原生输入、组合候选/取消/最终提交、字符/段落格式及拆段合段复用同一源事务和精确历史。保存重开后仍可继续输入。查询中的文本节点带独立段落身份；正文与文本框、不同文本框之间的文字范围保持保护，不能把框内偏移当成正文偏移。查找按内容区域分组，框内段落不打断相邻正文段落。

框内普通文字超链接复用[已有文字链接](#docx-外部超链接)的读取、设置、移除、混合查询及显式打开。支持 HTTP、HTTPS、mailto 和指向可用正文/单元格书签的内部目标。原生输入、拆合段、格式和精确历史保留链接；整框及框内范围的富文本复制使用同一目标转移协议，避免携带失效关系身份。PDF 复用[文字链接输出](#docx-pdf-文字链接)，保留实际文字边界和源文件。行为参考 [ONLYOFFICE 文字链接与父框坐标](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L2886-L3000)。

当前每框限 256 段、32767 个 UTF-16 单元，单段沿既有 4096 单元上限。普通运行文字、Tab 和软换行可编辑。`noTextEdit` 和 `noSelect` 阻止框内文字编辑，沿既有文档保护检查；帧属性仍遵循各自的锁。候选和提交前校验段落结构及内容上限，失败保留最后有效候选或原文档。表格、列表、正文框内字段、嵌套绘图、多栏、竖排、旋转、自动适配及独立两轴溢出设置继续拒绝输出，保留源与历史。页眉页脚的普通框允许原生 PAGE/NUMPAGES，并随实际页号求值；其他字段仍保护。更多兼容继续实施；不支持的剪切仍受保护，避免把对象降成占位字符后删除原内容。

实现归 [shape-text.mbt](../../../modules/formats/src/docx/shape-text.mbt)、[drawing-text-box.mbt](../../../modules/layout/src/drawing-text-box.mbt)、[文字区域交互](../../../modules/layout/src/text-box-interaction.mbt)及[框内编辑保护](../../../modules/formats/src/docx/text-box-editing.mbt)。原生内容与 `bodyPr` 参考 [ONLYOFFICE Shape 读取](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Shape.cpp#L111-L168)，默认边距与文字区域参考 [Shape.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L1571-L1625)，默认 bodyPr 参考 [Format.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L11945-L11964)，文字命中与选区坐标转换参考 [selectionSetStart/End](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L5372-L5415)。当前范围归 [P10](../../implemented/p10-docx-core.md)。

文本框导入可选择已支持的 `AlternateContent/Choice`，否则使用可解释的 fallback；逻辑内容只排版一个分支，保存保留其他源分支。框内支持普通单条下边框及其空间和颜色，横向按原生规则各延伸 0.5 mm；更广段落边框继续保护。实现归 [alternate-content.mbt](../../../modules/formats/src/docx/alternate-content.mbt)和[text-box-border.mbt](../../../modules/formats/src/docx/text-box-border.mbt)。

### 行内图片尺寸与裁剪

共用行内绘图插入已支持普通正文/单元格中已知简单域及数学对象的两侧，可插入 PNG/JPEG、基础图形和普通图表。字段、数学对象和新绘图各占一个逻辑位置；绘图写在完整对象之前或之后，不拆入字段或 OMML 内部。新 run 复用相邻对象的字符属性，原字段/公式 XML 与未改资源保持；插入后可继续原生输入及修改对象，整体沿既有精确历史保存重开。未改字段中的已导入 XML 注释按原文保留；需要重写其结果的缓存刷新仍检查不透明源。未知/锁定字段、未支持数学、审阅及超限沿既有保护，失败不留下图表/图片关系或部件。实现归 [drawing-insert.mbt](../../../modules/formats/src/docx/drawing-insert.mbt)，复用 [paragraph_inline_source](../../../modules/formats/src/docx/body-field-insert.mbt) 的完整对象边界写入；行为对照 [ONLYOFFICE AddInlineImage](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/DocumentContent.js#L3106-L3157) 的选区替换与段落插入，未复制执行代码。

`editPicture(revision, { action: "insert", width, height, bytes })` 在核心当前文字选区插入正文行内 PNG/JPEG 图片；跨段范围复用既有删除与合段规则，单个普通表格单元格也可作为容器。`width/height` 为 0.1–14400 pt，舍入到整数 EMU；字节与像素预算同下方替换操作。空段、空 run 或段内位置都生成真正的绘图元素，保留周围文字、run 格式和范围外源。核心为新图片分配未用身份，避开主文档及页眉/页脚中的已有绘图；同时创建图片、关系和内容类型，合为一项有界历史。默认面板提供尺寸和文件选择，并读取新图片属性。选区替换与插入行为参考 [ONLYOFFICE controller_AddInlineImage](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Editor/Document.js#L19412-L19451)。

插入后把文字光标放到新图片之后，默认面板仍读取新图片属性，可以立即继续输入。受支持的正文及普通单元格段落中，图片与布局一致占一个 `U+FFFC`、一个 UTF-16 单元；`query().texts` 也包含该绘图片段。文字位置、范围、查找、格式与组合输入共用这个计数。纯文字中的 `U+FFFC` 仍是文字；核心用独立的保留位置区分原图片与输入字符，不把字符自动变成图片。图片两侧可输入、回车拆段及退格合段，保留图片原 XML、尺寸、裁剪及资源。范围替换和 Backspace/Delete 可以删除图片，并复用 `noDelete`、引用与修订保护；删除保留包内共享资源。行内绘图作为内容位置参考 [ONLYOFFICE Run 的绘图边界](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Editor/Run.js#L1448-L1467)。

纯文字复制只携带占位字符，不携带图片资源。`selectedText(revision, selection, cut = false)` 可用 `cut: true` 预检查剪切；核心对含实际图片的范围返回 `protected-content`，宿主在写剪贴板之前执行该检查。普通文字及字面 `U+FFFC` 仍可剪切。默认富文本复制、剪切与粘贴已携带行内/浮动图片及资源，按[正文富文本片段](docx-tables.md#正文富文本片段)校验和重分配身份。

撤销/重做精确恢复文字、图片、选区与资源。节点 ID 仅在当前会话有效，保存重开后须重新查询。未知图片源、扩展、效果或不支持的布局仍保护相应段落。含图片单元格的表格结构命令继续保护，避免绕过对象锁；受支持浮动定位与环绕见[下文](#图片定位)。

同步 Wasm 和 Worker 的 `pictures(revision)` 返回 `{ revision, images }`。每项包含会话内绘图节点 `id`、`name`、是否被当前单图片范围选中的 `selected`、point 单位的 `width/height`、四项 `crop`、尺寸/裁剪保护原因 `reason`、删除保护原因 `deleteReason`、替换保护原因 `replaceReason`，以及下方定位使用的 `anchor` 和 `positionReason`。`crop` 依次为源图左、上、右、下移除的比例。受尺寸/裁剪保护的项使用零尺寸及零裁剪，原因供 UI 显示；列表最多 256 项。宿主 `DocumentEditor.objects.pictures()` 复用现有队列，默认图片面板从列表选择目标。

点击受支持的行内图片会选择其一个逻辑单元，复用现有文字选择、历史与输入路径，不增加 revision 或历史。相同图片资源仍按各绘图的段内 offset 区分。布局 `PlacedDrawingFrame.start/level` 保留逻辑起点和双向级别，`Hit.drawingStart` 标记图片命中；左右半部返回相应文字边缘，RTL 调换逻辑方向。选择框按图片本身的框计算，并裁剪到行/单元格的可见区域，不按展开后的源裁剪尺寸命中。

`hitTest(layoutId, page, x, y)` 的 `DocxHit.drawing` 为图片或基础图形的 `DocxSelection` 或 null；`position` 仍是最近文字边缘。核心检查图片两端的逻辑位置和原有保护。默认宿主普通点击使用 drawing 范围，拖选和 Shift 点击沿 position 扩展文字范围。命中只查询当前布局，旧布局及无效坐标仍拒绝。默认面板在手势结束后读取 selected 项，自动切换尺寸/裁剪/删除目标；过期、组合、暂停和替换沿现有屏障，晚到的面板读取不覆盖新文档。

原生 Backspace/Delete 和输入可删除或替换被选图片，撤销恢复原图片及选区；列表和命中不改变源包。屏幕阅读文本将占位字符描述为 [image]。普通单元格复用同一位置与裁剪，结构操作和图片剪切仍保留前述保护。行为参考 [ONLYOFFICE ParaDrawing.select](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Editor/Paragraph/ParaDrawing.js#L2784-L2795) 与 [GraphicObjects.OnMouseDown](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Editor/GraphicObjects/GraphicObjects.js#L1594-L1606) 的图片选择与文字输入分工。本项目通过已有逻辑范围连接两者；实现归 [drawing-selection.mbt](../../../modules/formats/src/docx/drawing-selection.mbt) 和 [docx-hit.mbt](../../../modules/bridge/src/docx/docx-hit.mbt)。

`editPicture(revision, { action: "resize", id, width, height, crop })` 修改已有受支持的正文图片。宿主也显式传入图片列表的 revision，防止读取后改动文档而误用节点身份；默认面板过期后须重新读取。尺寸为 0.1–14400 pt，舍入到整数 EMU；裁剪输入为 0–1 的四个比例，按 1/100000 舍入，两侧之和须小于 1。保持目标框，只裁源图再拉伸至框；重置写四边零值。源图原字节、关系、替代文字、身份和范围外 XML 保持；同时更新行内框及图片变换尺寸。一次命令一项精确历史，保持原文字选择，重复有效值不新增 revision 或废弃布局。

`editPicture(revision, { action: "delete", id })` 只删除目标绘图元素，保留 run、段落和周围文字。目标段落可编辑时，光标落在图片原位置后的合法字素边界；若其他对象仍保护该段落，则保留原文字选择。删除保留包内图片和关系，避免误删共享资源；撤销/重做精确恢复源与选择。`noDelete`、外部对象引用及启用修订记录的文档保护删除；尺寸/裁剪锁不单独阻止删除。默认面板按 `deleteReason` 启用按钮。行为参考 [ONLYOFFICE 从 run 移除绘图](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L2899-L2963)。

`editPicture(revision, { action: "replace", id, bytes })` 替换目标图片的压缩源。`bytes` 为 `Uint8Array`，支持 PNG/JPEG，输入不超过 4 MiB，单轴不超过 4096 像素，总像素不超过 4194304；核心复用 PPTX 的文件头与尺寸校验，平台负责实际解码。目标框、裁剪、替代文字、身份和文字选择保持不变。核心创建独立资源、关系和内容类型，避免改变共享原图；这些修改合为一项历史，撤销移除新增资源，重做恢复相同字节。其他部件及原资源保留。相同字节不新增 revision；源保护、输出及 4 MiB 历史预算失败不留下部分资源。替换不受尺寸/裁剪锁单独限制，默认面板按 `replaceReason` 启用文件选择。固定框替换参考 [ONLYOFFICE replacePictureData](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/Drawings/Format/Image.js#L836-L859)；本操作保留已有裁剪。宿主在重新布局前准备新增图片；核心与 Canvas 回收当前流中不再使用的解码资源，撤销/重做时按需重新准备。

核心 `DrawingFrame.content` 的图片分支与 `PlacedDrawingFrame` 保留框和源裁剪；公共定位路径产生矩形裁剪及展开后的原图坐标，Canvas/PDF 使用同一结果。展开后的源图宽高各不超过 1e9 pt，沿用绘制坐标预算。资源仍按原键准备，不生成修改后的图片副本。缓存复制裁剪数组，调用者不能改写已保留的几何。未知裁剪/扩展、图片效果或锁定、修订容器、未知浮动锚点及旋转/翻转图片、外部图片及未支持节设置继续保护。现有 noChangeAspect 约束禁止改变宽高比；noCrop/noResize 保护整项编辑。受支持浮动环绕见[位置合同](#图片定位)，负裁剪扩边归 [P14](../roadmap.md#p14-兼容与性能已完成)。源比例对应 [ONLYOFFICE 图片裁剪系数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L946-L960)，实现归 [`picture-editing.mbt`](../../../modules/formats/src/docx/picture-editing.mbt)。

### 绘图对象移动与缩放手势

默认宿主在被准确选中的可编辑图片四角显示可聚焦手柄，复用核心选择框和原生指针队列。缩放始终保持原宽高比和裁剪，核心按初始尺寸与本次总位移生成候选，更新不累积上次预览。两轴都有位移时采用较大的比例；单轴位移用于键盘及沿轴缩放。四角编号 1–4 依次为左上、右上、右下、左下。尺寸继续限制为 0.1–14400 pt、整数 EMU 和原裁剪展开预算，越过相反角时钳制到最小尺寸，保留原逻辑位置。等比例追踪参考 [ONLYOFFICE ResizeTracks](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L670-L680)。自由比例侧边手柄、反转及更多浮动对象归 [P14](../roadmap.md#p14-兼容与性能已完成)。

同步 Wasm 和 Worker 的 `drawingGesture(revision, change)` 返回 `EditState`。`change` 分为 `{ action: "begin", drawing, handle }`、`{ action: "update" | "commit", id, dx, dy }` 和 `{ action: "cancel", id }`。`handle: 0` 移动正文浮动图片，1–4 缩放对应角；操作和句柄在开始时固定。`drawing` 是图片或图形列表中的绘图节点 ID，`id` 是开始后 `state.drawingGestureId` 的正整数手势身份。`dx/dy` 为 point 单位的有符号总位移，各不超过 ±14400；核心根据手柄方向换算尺寸，平台只换算 CSS 坐标。`DocxDrawingGestureCommand` 从 Wasm/Web foundation 导出。对应核心方法为 `begin_drawing_gesture/update_drawing_gesture/finish_drawing_gesture/cancel_drawing_gesture`。

可移动的选中浮动图片提供覆盖原框的移动目标，也可聚焦后使用方向键移动。移动保留尺寸、裁剪、层次和环绕。未传 `page` 的位移命令保留源段落锚点，偏移从初始位置计算。原轴为对齐时，核心按当前纸张、源边距、栏或段首布局解析偏移，只转换实际移动或参考原点改变的轴；零位移保持原对齐及源字节。数值继续按整数 EMU 舍入，移动后的偏移仍须在 ±14400 pt 内。指针点击移动目标仍聚焦正文，保持原生删除和文字替换。直接 MoonBit 移动对齐图片须提供 `probe/profile/images`；纯源偏移编辑继续可用。依据为 [ONLYOFFICE 移动追踪](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/GraphicObjects/DrawingStates.js#L2111-L2180)及[保留参考系的偏移换算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ParaDrawing.js#L1754-L1822)。指针跨段重锚和边缘翻页已接通同一手势。

指针更新和提交附带从 0 开始的 `page`。此时 `dx/dy` 是当前页内指针坐标相对起点页内坐标的总差，视口滚动计入页内坐标。核心从开始时的布局计算图片框，并在忽略图片覆盖层的最近文字位置确定锚点。同段、同页、同栏内移动保留原逻辑位置；跨段、跨页或跨栏迁移共用定位源事务。位置仍按原纸张、源页边距、栏或段落参考系写回。传入 `page` 的直接 MoonBit 调用须在开始时提供 `probe/profile/images`；未知页和受保护落点保留最后有效候选。

开始要求当前正好选中该绘图对象。缩放通过原尺寸编辑保护；移动通过独立的 `positionReason`、`noMove/noChangeWrap` 和文档保护，`noResize` 单独锁定时仍可移动。`EditState.drawingGestureId` 在普通状态为 null，与 `compositionId` 互斥。候选复用尺寸或定位命令的校验和源补丁；`flow`、布局和返回的 `selection` 展示候选；会话已提交源、选择、revision 和历史保持。更新失败保留最后有效候选；错误身份、过期 revision、未知图片源及资源上限继续拒绝。候选期间其他编辑、文字组合及直接 DOCX/PDF 持久化返回 busy。提交按最终坐标重新准备源，只新增一项历史；有效值未改变则不新增历史。取消恢复原显示和选择，不改变源与历史。图片字节、关系、替代文字、原裁剪及非目标部件保留。

松开提交，Escape、指针取消、捕获丢失及窗口失焦取消。移动目标和缩放手柄的方向键沿对应方向移动 1 pt，Shift 为 10 pt，每次按键产生一项有界编辑。普通命令、保存和暂停先处理末次坐标；`whenIdle()` 只等已接收的候选更新。恢复与销毁会取消未提交候选，已提交历史继续保留。手势使用当前 CSS 比例，DPR 留给原绘制层；图片移动复用视口边缘滚动和翻页；四角缩放仍在当前页进行。核心候选布局和正式布局共用 Canvas/PDF，平台不保存另一份文档树。实现归 [`drawing-gesture.mbt`](../../../modules/formats/src/docx/drawing-gesture.mbt)、[`document-drawing-gesture.ts`](../../../packages/docx/src/web/document-drawing-gesture.ts)及 [`document-pointer.ts`](../../../packages/docx/src/web/document-pointer.ts)。

### 图片定位

`editPicture(revision, { action: "position", id, anchor })` 在正文行内图片、前置/后置的无环绕浮动图片、上下型及方形环绕之间切换，也可修改既有锚点。默认图片面板提供相同操作。`anchor: null` 表示行内；浮动值为 `{ horizontal, vertical, behind, order, wrapping, wrapSide, distance }`。两轴使用 `{ relativeTo, offset, align }`：偏移为 point 数值并令 `align: null`；对齐则令 `offset: null`。水平基准支持 `page/margin/column`，对齐支持 `left/center/right`；垂直基准支持 `page/margin/paragraph`，对齐支持 `top/center/bottom`。段落对齐沿 ONLYOFFICE 规则落在段首，数值偏移相对段首计算。

定位命令可带 `target: DocxPosition`，把既有浮动图片迁移到普通正文段落的指定字符边界。目标偏移按迁移前文档计算；同段迁移时核心扣除被移走的图片字符。`anchor` 同时给出相对目标参考系的位置。源锚点、定位和新图片选区共用一项历史。图片保留原生身份、运行格式、资源和关系。命名空间随源运行保留，目标文字的格式保持。绘图节点 ID 可能变化，下一项命令重新查询图片列表。移到自身前后边界只修改定位，相同有效值不新增历史。

跨段迁移遵循 `wp:anchor locked`；独立的 `noDelete` 不阻止移动。未知运行元数据、字段/超链接内部、表格或受保护目标、非字符边界和超限输出原子拒绝。该能力已接通核心 `set_drawing_anchor(..., target?)`、同步 Wasm、Worker 和宿主定位命令。默认指针跨段迁移也使用同一源事务。依据为 [ONLYOFFICE 跨段移动及原运行格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/GraphicObjects/DrawingStates.js#L1845-L1895)。

偏移为有限的 ±14400 pt，按整数 EMU 舍入。`behind` 为布尔值；`order` 为 0–4294967295 的整数，传输为 JSON 数字。图片目录的 `anchor` 与 Flow 的 `DrawingFrame.anchor` 显式返回浮动值或 null。`positionReason` 独立于尺寸/裁剪锁，`noMove/noChangeWrap` 和文档保护继续拒绝定位。未知位置元数据或被覆盖的位置节点中的注释/处理指令保留源并拒绝覆盖；把含扩展身份的锚点改为行内也继续保护。表格、页眉页脚、简单定位、禁止重叠、效果和其他参考系仍不支持浮动编辑。

核心先按纸张、源页边距、当前栏或锚点段落放置图片；页眉页脚让出的正文空间不改变源页边距基准。浮动图片不增加文字行宽与行高，仍占一个逻辑单元。后置图片先于文字绘制，前置图片后于文字绘制；同层按顺序及源位置排列。前置图片优先命中；后置图片在文字区域外可选，方形环绕的空隙也可选择图片。浮动选区按完整图片框计算，沿同一 Canvas/PDF 输出。

`wrapping` 为 `none`、`topBottom` 或 `square`。`wrapSide` 为 `bothSides/left/right/largest`，非方形模式使用 `bothSides`。方形环绕按图片及间距切出可用文字区域，两侧文字按段落方向连续排入同一行，共用基线、行距、光标、选区和分页。段落测量结果在各片段间复用，保留 Unicode 连接上下文和原制表位基准；段落保留、孤行及与下段/表格同页使用实际环绕行。小于 18 pt 的页边空隙沿 ONLYOFFICE 并入排除区。当前表格整体或续页片段在相交图片下方排放。

`distance` 为 `{ top, right, bottom, left }`，各值为 0–14400 pt，按整数 EMU 舍入。上下型环绕在水平相交的栏中排除图片及间距覆盖的纵向区域；文字行、表格和续页避让同一区域。源锚点与文字行分离，整页图片留在原页，后续文字进入下一页。排除区域变化会使相关分页失效，稳定输入可复用缓存。核心锚点布局及方形行高度各最多迭代八次；循环依赖或超限明确失败。方形环绕仅排除与正文宽度实际相交的区域；仅接触边界不推移表格，四边间距仍参与交集。上下型环绕保留原边界规则。表格后锚点的边界振荡已修复，原始输入和缓存检查归 `wrappingEdgeCheckpoint`。

读取时支持 `wp:wrapTopAndBottom` 的 `distT/distB` 及 `wp:wrapSquare` 的四边间距覆盖锚点间距，方形侧向写为 `wrapText`；零效果范围保留支持。未设置的左右间距沿 ONLYOFFICE 使用 3.2 mm，显式零值保持。环绕属性写回原生 XML，保留图片字节、关系及未改源。依据为 [ONLYOFFICE 方形侧向与上下型排除区](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/GraphicObjects/WrapManager.js#L228-L305)、[页边空隙](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/GraphicObjects/WrapManager.js#L408-L421)及[图片间距默认值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ParaDrawing.js#L1712-L1716)。

同步 Wasm 和 Worker 的 `editPicture`、`pictureGesture` 接受第三个字体 `profile` 参数，默认 `{}`；宿主自动传入当前映射。涉及环绕的定位、尺寸、移动和缩放候选在提交前预检完整布局，缺字体、缺解码图片或排版失败保持文档、选择和历史；候选更新失败保留最后有效候选。直接 MoonBit 会话可显式传入 `probe/profile/images` 启用相同预检，纯源编辑继续使用既有有界事务。

未传 `target` 时定位保持原文字选择。资源、名称/替代文字及未改 XML 保留；一次命令一项精确历史，相同有效值不新增历史。旧修订、无效值、未知源和输出超限原子拒绝。实现归 [drawing-position.mbt](../../../modules/formats/src/docx/drawing-position.mbt)、[drawing-reanchor.mbt](../../../modules/formats/src/docx/drawing-reanchor.mbt)、[floating-image.mbt](../../../modules/layout/src/floating-image.mbt)、[image-wrapping.mbt](../../../modules/layout/src/image-wrapping.mbt)及[square-wrapping.mbt](../../../modules/layout/src/square-wrapping.mbt)，依据为 [ONLYOFFICE 图片放置属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ParaDrawing.js#L986-L1057)。更广浮动对象归 [P14](../roadmap.md#p14-兼容与性能已完成)。
