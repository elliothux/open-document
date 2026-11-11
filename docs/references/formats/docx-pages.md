# DOCX 页面、字段与注释

[格式合同目录](../formats.md)

### 页面设置

`FoundationSession/Client.execute({ operation: "pageSetup", revision, section: 0 })` 与 `DocumentEditor.pages.pageSetup(section = 0)` 返回 `{ revision, sectionCount, page, reason, background, borders, numbering, columns }`。`section` 是源顺序从零开始的节序号，最多 1024 节；越界目标明确失败。`page` 包含 `section`、必填的 `startType` 及源尺寸 `width/height/top/right/bottom/left`，尺寸单位为 pt；缺少末节属性时使用 612×792 pt、四边 72 pt。未知分栏元数据、镜像页边距、装订线或保护返回 `page: null` 与原因；无法解释节目录时 `sectionCount` 为 0。查询不要求正文选区。页码和分栏同样读取指定节；其他属性仍遵守下文的编辑边界。

`setPageSetup(revision, page)` 同时修改指定节的尺寸与四边距，Web 编辑宿主省略 revision。`DocxPageSetup` 必须包含 `section` 和上述六个尺寸，可选 `footnotesAt: "pageBottom" | "beneathText"`、`orientation: "portrait" | "landscape"` 及 `startType: "nextPage" | "continuous" | "oddPage" | "evenPage"`。省略 startType 保留原起始方式；查询始终返回它，缺少原生类型时为 nextPage。默认页面表单的“节的起始方式”修改已选节，不插入新节。只改起始方式时保留纸型、边距及其原始属性，与尺寸一起改时合为一项历史；重复应用不产生历史。类型写在页边引用和注释配置之后、纸型之前，保留文字、选择、页码和其他节。重复类型、未知扩展及带注释的目标类型保持保护。规则依据 [ONLYOFFICE SectPr.Set_Type](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/sections/sect-pr.js#L253-L264)，分页沿下文多节规则。节序号与 revision 共同绑定目标，切换选区或可见页不会改变目标。省略方向时使用指定宽高；给出方向且与宽高不一致时，核心交换宽高并旋转四边距。横向时新左/上/右/下依次为原下/左/上/右，纵向反向旋转；正方形不旋转。规则依据 [ONLYOFFICE 的方向修改](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/sections/sect-pr.js#L1148-L1180)。

尺寸为 36–14400 pt，边距非负；所有数值须能表示为整数 twip，并为正文留下至少 12×12 pt。源尺寸原样写回 `pgSz/pgMar`；`Flow.page`、预览和 PDF 继续采用下文既有纸型解释规则，可能与源尺寸不同，例如 500 pt 的显示尺寸为 498.9 pt。再次应用相同源参数不产生历史，不能把显示尺寸自动写回源文档。

缺少末节属性时在正文末尾创建，缺少页面属性时按 OOXML 顺序插入。修改保留其他节、段落、稳定节点身份、节元数据、其他部件、页眉/页脚距离和零装订线；清除与新尺寸不一致的旧打印机纸型代码。尺寸与边距合为一项有界历史，保留待输入格式，撤销/重做及保存重开恢复相同源参数。非法值、过期 revision、未知目标属性/注释或预算失败保留已提交包。默认 UI 提供节选择、读取、修改和方向选项；草稿保留目标节，文档改变后要求重新读取。已有分栏时，修改尺寸也须为每栏保留至少 12 pt 宽度，并校验各节页边框。其余多节编辑继续实施，分节导入和继承读取见[多节分页](#多节分页)。

### 正文行网格

导入按节读取 `w:docGrid`。`type` 缺省或为 `default` 时停用，`type="lines"` 使用正整数 `linePitch`（twip）。正文自动行距至少占一格，较高的行占用整倍数网格。最小行距仍可抬高行框，固定行距和继承或直接关闭的 `w:snapToGrid` 沿既有排版。页眉、页脚、注释及默认表格行距沿各自排版。字符网格、启用表格网格的兼容开关和不受支持的网格声明继续诊断。正文输入保留网格源节点，Canvas 与 PDF 共用行框。HTML 按内容重排。行框计算参考 [LibreOffice Writer](https://github.com/LibreOffice/core/blob/master/sw/source/core/text/itrform2.cxx#L2147-L2222)。

### 多节分页

`FoundationSession/Client.execute({ operation: "insertSectionBreak", revision, kind, profile })` 与 `DocumentEditor.pages.insertSectionBreak(kind)` 支持 `nextPage/oddPage/evenPage/continuous`。默认页面面板提供相同操作。命令把选择折叠到源起点，保留原选择文字；正文在该处拆段，表格在当前行前拆开，首行则在表格前插入边界段落。跨行合并沿原拆表规则保留上表内容与下表空续接单元格。光标位于新段落或下表首单元格，可继续原生输入。

前节保留完整原生节配置，后节采用指定起始类型、继续编号并继承前节页眉页脚。源修改先通过完整布局和输出检查，再提交一项有界历史；缺字体、保护、旧 revision、节数及输出预算失败保持原文档与历史。实现归[分节创建](../../../modules/formats/src/docx/section-create.mbt)，依据 [ONLYOFFICE AddSectionBreak](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L14569-L14661)，未复制上游执行代码。

导入读取正文段落 `pPr/sectPr` 与正文末尾 `sectPr`，分别保留各节纸型、边距、页边框、分栏和页眉页脚距离。`Flow` 的页面字段描述首节；必需的 `sectionBreaks` 按正文段落及表格计数保存后续节配置。节边界会终止段落保留链；每节复用现有分栏、表格和页眉页脚分页，Canvas、PNG 和 PDF 使用逐页尺寸。

当前读取 `nextPage/oddPage/evenPage/continuous`。奇偶分节按续接或重启的页号补空白页；首节起号按原生类型修正奇偶。页号继续或按 `pgNumType@start` 重启，格式由本节决定。缺少页眉页脚引用时按变体继承，显式空部件清除继承内容；不同部件的段落身份独立。首页与奇偶变体按当前节选择，`NUMPAGES`、`SEQ` 和跨节 `PAGEREF/REF` 按全文求值，最多八轮重排。

连续分节 `continuous` 在纸型相同、前节末页无脚注且首项能放入余下区域时接续同一物理页。前节先完成末页栏平衡，后节采用自身横向边距和栏设置，从已用区域下方继续。共享页保留原页眉页脚、页边框、水印和纵向边距；后续新页采用后节完整配置。续号只计算一次共享页，全文字段继续按实际物理页求值。纸型变化、前页脚注、段前分页或首项放不下时换页；空尾节不额外生成空白页。正文及表格可连续多次插入，重复的原生类型属性按无修改处理；分节本身仍产生一项完整源历史。

分页接续归 [section-continuation.mbt](../../../modules/layout/src/section-continuation.mbt)、[节分页](../../../modules/layout/src/sections.mbt)及原分页/分栏/页边区域调用者。规则依据 [ONLYOFFICE 连续节与栏平衡](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L4155-L4205)及[连续节首页判定](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L14679-L14710)。多栏脚注等原有限制保持，不据此标记整个节编辑完成。

多节正文和普通单元格已接通原有原生输入、命中、方向键、范围替换、字符/段落格式及组合输入。Enter 或粘贴 LF 拆段时，原节属性移到最后的新段落，其余新段落保留原段落格式。Backspace/Delete 合段和跨段范围替换时，合并结果保留末段的节属性，删除范围内其他节边界；被合并内容采用下一节纸型、栏和编号。普通表格创建、网格与属性编辑复用[表格事务](docx-tables.md#表格创建)，按所属节及实际起始栏计算宽高限制。其余节功能继续实施。

删除节边界后，若紧随的保留节没有任何显式页眉/页脚引用，则继承被删节的显式引用；若该节已有引用，则保留其原生配置。连续删除多个边界沿相同规则传递，缺少末节属性时按需创建。页边部件和资源保留，格式修改保留 `sectPr` 及其原始子内容。组合预览使用候选节目录和布局，取消保留原包与历史；提交、节迁移、引用传递及原有书签/批注恢复共用一项有界历史。现有保护、未知源、过期命令和预算失败保持原子拒绝。实现归[节输入事务](../../../modules/formats/src/docx/section-input.mbt)与[结构范围编辑](../../../modules/formats/src/docx/range.mbt)；语义依据 [ONLYOFFICE 拆段](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L13861-L13868)、[合段](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L14075-L14083)及[删除节时保留页边引用](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/sections/document-sections.js#L293-L326)。

[页面设置](#页面设置)支持指定节的尺寸、方向和四边距，[页码设置](#页码格式与起点)支持起号、续号与格式，[分栏](#分栏)支持等宽、不等宽与分隔线，[页边框](#页面边框)支持独立设置、节内首页规则与移除。其他节属性编辑继续实施，不能据此标记分节编辑完成。跨节与多栏脚注归[脚注与尾注](#docx-脚注与尾注内容)，多节水印归[DOCX 水印](#docx-水印)。总量继续限制为 1024 页、32768 行和最多 1024 节；多节暂不复用整页分页缓存，保留段落塑形缓存。含节边界的富文本片段及 HTML/Markdown 导出继续保护。

实现归[节读取](../../../modules/formats/src/docx/flow-sections.mbt)与[公共节分页](../../../modules/layout/src/sections.mbt)。原生起号、奇偶和首页选择依据 [ONLYOFFICE 节页码计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L14679-L14795)，未复制上游执行代码。

### 分栏

`FoundationSession/Client.execute({ operation: "setPageColumns", revision, section, columns, profile })` 与 `DocumentEditor.pages.setPageColumns(section, columns)` 设置指定节的分栏。`section` 使用上述零起始源序号。`DocxColumns` 必须包含 `{ count, gap, separator, custom }`：栏数为 1–12 的整数，栏间距为 0–14400 pt 且须表示为整数 twip，分隔线为布尔值。`custom: []` 表示等宽；不等宽时提供恰好 `count` 项 `{ width, gap }`，分别为栏宽和栏后间距。宽度为 12–14400 pt，间距为 0–14400 pt，均须有限且为整数 twip。`null` 移除该节显式 `w:cols`，恢复单栏、36 pt 间距、无分隔线及空 `custom`。缺少末节属性时原子创建；`pageSetup(section).columns` 返回 `{ value, reason, availableWidth }`。`availableWidth` 是核心按该节物理纸型及边距计算的可用正文宽度，单位为 pt；不支持的源返回 null 值、null 宽度和原因。

等宽时从目标节的可用页宽扣除全部间距再等分。不等宽时读取 `w:equalWidth="0"` 及逐项 `w:col w:w/w:space`，栏数取子节点数。前面的栏使用各自宽度和间距，末栏延伸到正文右边界；末项源宽度/间距保留，几何不使用它们。全部实际栏宽至少 12 pt。默认面板共用节选择，可切换模式并编辑前面各栏的宽度和间距；末栏使用核心返回的 `availableWidth` 显示剩余量，按整数 twip 显示并保留原元数据。跨页导航不改变目标节。Wasm/Web 沿既有 foundation 模块导出类型和命令，面板沿原有读取、重置和过期草稿保护。

正文按栏顺序续排，末页在整数 twip 上有界求解平衡高度；显式分页符及段前分页进入下一张纸。进入不同宽度时，核心按原逻辑偏移重新断开剩余文字，保留整段双向分析、字体来源、光标和终止控制符；续段不重复首行缩进或列表标记。孤行和“与下段同页”按实际下一栏宽度预估，段落缓存包含续排偏移。页眉页脚保持整页宽度，页码和总页数按实际纸张计算。Canvas、PNG 和 PDF 消费同一物理页结果；分页缓存键包含全部栏参数及平衡高度。

不等宽栏中的表格改为按实际起始栏解析百分比与适配宽度，续栏保持同一列网格。创建、尺寸命令及布局后的属性查询已接入实际位置；未提供布局的原生查询仍返回最窄栏上限。默认编辑器在布局后刷新表格查询，使尺寸面板使用实际栏的上限。分页缓存记录表格起始栏拟合后的列宽，复用时保持同一网格；自动表格的内容变化会使相关宽度失效。创建、调宽、适配、插删列、拆格、历史、保存重开及 PDF 已做定向检查。普通行、合并格与重复表头按目标栏重新取横坐标，文字、边框、底色、命中、光标和选区共用几何。固定网格超出目的栏时拒绝候选，不自动改写网格。更广跨宽度表格兼容继续实施。

修改保留其他节、正文、选择、待输入格式、页码/页边属性及其他 OPC 部件，使用一项有界源历史。同值不新增历史，撤销/重做和保存重开恢复源与绘制结果。候选使用目标节的物理宽度校验，并预检全文分页、表格及字段；重置仍按原生分栏符重新分页。非法参数、旧 revision、保护、未知属性/子节点、不透明目标源、布局或输出预算失败原子拒绝，并保留待重做项。分栏符沿上文范围编辑；其余节属性编辑继续实施。

实现归 [`page-columns.mbt`](../../../modules/formats/src/docx/page-columns.mbt) 和 [`columns.mbt`](../../../modules/layout/src/columns.mbt)。等宽计算参考 [ONLYOFFICE SectionColumns](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/sections/section-columns.js#L200-L216)，栏位置和平衡参考 [DocumentPageSection](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/document/document-page-section.js#L78-L100)，分隔线参考 [Document.draw](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L5384-L5390)。未复制上游执行代码。

### 可编辑标题封面

`FoundationSession/Client.execute({ operation: "setCoverPage", revision, cover, profile })` 与 `DocumentEditor.pages.setCoverPage(cover)` 在正文前插入或替换标题封面。`DocxCoverPage` 为 `{ title: string, subtitle: string }`；`null` 移除本 SDK 标记的封面，无封面时不增加历史。标题须有非空白内容，最多 256 个 UTF-16 单位；副标题最多 512 个单位，可为空。两者须为有效 XML 文字，不含换行、Tab、控制符或段落分隔符。默认页面面板提供相同操作，插入后光标位于标题末尾，可继续输入及修改原生格式。

核心创建居中的普通段落：标题 32 pt 粗体、段前 144 pt，副标题 16 pt；每段段后 24 pt。字体继承文档默认值。末尾空段落带段前分页，将原正文移至后页。封面使用原生书签 `_OpenDocumentCoverPage` 标记范围；重开后仍可替换或移除。普通书签命令可定位该标记，改名、创建及删除由封面命令管理。书签身份分配复用已有实现，保留正文、其他书签及 OPC 部件。书签端点和单项历史参考 [ONLYOFFICE AddBookmark](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L24423-L24501)，段前分页参考 [SetParagraphPageBreakBefore](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L20916-L20944)。标题样式是本 SDK 的基础模板规则，未复制上游执行代码；实现归 [`cover-page.mbt`](../../../modules/formats/src/docx/cover-page.mbt)。

插入、替换及移除各使用一项有界源历史，撤销/重做恢复原字节和选择。候选先用现有字体、图片与完整分页校验，标题和副标题必须能放入一页；保存、预览及 PDF 沿用普通段落路径。替换/移除要求完整标记位于文档起始，范围内为受支持的普通段落，不含其他书签或不透明注释。封面外的内容保留；已有指向封面的链接或 PAGEREF 时，先移除引用再移除封面。旧修订、活动候选、保护、缺字体、布局或输出预算失败保持原文档与历史。当前仅支持单节单栏，保留已有页眉页脚及首页选项；更多封面模板、多节与分栏封面继续实施。

### 页面背景色

`FoundationSession/Client.execute({ operation: "setPageBackground", revision, color })` 与 `DocumentEditor.pages.setPageBackground(color)` 设置全稿纯色背景；`color` 为不带 `#` 的六位 RGB，`null` 移除背景并恢复默认白页。`pageSetup().background` 返回当前显式颜色或 null，以及修改保护原因。源 `w:background w:color` 位于正文前，修改保留正文、选择、待输入格式和其他部件，使用一项有界历史；相同颜色不增加历史。默认页面面板共用读取/过期草稿保护，并提供颜色和恢复默认按钮。

核心 `Flow` 与 `DocxFlow` 的必需 `background` 字段为有效六位 RGB；无背景为 `ffffff`。正文、透明单元格和列表标记按有效页面背景计算自动文字对比，有底色的单元格仍按自身底色计算，显式文字色保持原样。分页结束后在页面图元最前加入整页颜色，保留分页缓存中的原内容；换色、恢复白色及缓存复用不积累旧底色。Canvas 与静态 PDF 消费同一背景矩形，包含页边距区域。规则参考 [ONLYOFFICE DocumentBackground.draw](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/document/document-background.js#L54-L87)和 [setBackgroundColor 的历史](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L5638-L5645)；实现归 [`page-background.mbt`](../../../modules/formats/src/docx/page-background.mbt)。

非法颜色、旧 revision、活动候选、文档/设计保护及输出预算失败保持当前包与历史。重复背景、未知属性、主题色、图片/渐变/VML 及不透明目标源继续保护，布局保留诊断，不能用纯色替换来删除未知源。全稿主题背景继续实施，文字水印与页边框见下文。

### DOCX 水印

`FoundationSession/Client.execute({ operation: "watermark", revision, section })` 查询 `{ revision, section, value, mixed, reason, images }`；`DocumentEditor.pages.watermark(section)` 还返回 `documentId`。`section` 使用零起始源序号。`value` 为目标节有效默认页眉的水印或 null，`mixed` 表示该节三种有效页眉变体不同，`reason` 表示目标源的保护原因。`images` 提供全文已存变体的不重复图片资源键，供预览统一准备资源，最多 3072 项；受保护节仍可提供显示所需资源。只读查询允许组合和绘图候选，按候选节目录读取；写操作继续要求结束候选。`FoundationSession/Client.execute({ operation: "setWatermark", revision, section, value, profile })` 和 `DocumentEditor.pages.setWatermark(section, value)` 设置文字或图片水印，null 移除。设置同时更新目标节默认、首页和偶数页页眉，创建缺失的部件及关系，保留已有文字、字段和开关。以后切换首页或奇偶页设置仍保留水印。

目标节继承前节区域，或与其他节显式引用同一部件时，核心先复制完整区域及关系，再修改水印；其他显式区域保留原源。当前节独立部件的变化继续作用于仍继承它的后续节。已匹配的变体保留原引用，相同设置不新增历史；移除继承水印创建无水印的独立区域，保留文字和资源。复制、引用、图片、关系及内容类型合为一次事务，支持仅含关系 Override 的包。默认面板共用节选择，切节清除草稿，跨页导航保持目标。

文字值为 `{ kind: "text", value: DocxTextWatermark }`。`DocxTextWatermark` 包含八个必需字段：`text`、`font`、`size`、`color`、`opacity`、`diagonal`、`bold`、`italic`。文字和字体名各为最多 256 个 UTF-16 单元的非空单行文本，字体须在当前 profile 可用。字号为 0.5–1638 pt 的半磅倍数，颜色为不带 `#` 的六位 RGB，不透明度为 0–1 并舍入到 1/100000；后三项为布尔值。斜向使用原生 315° 旋转，水平为 0°。

图片值为 `{ kind: "picture", image, width, height, opacity }`。新图片的 `image` 是 PNG/JPEG 原字节；查询返回不透明资源键，调整已有图片时传回该键。宽高为 0.1–14400 pt，保存按 EMU 精度舍入；不透明度为 0–1 并舍入到 1/100000。原始图片不转码，页眉各自保存图片关系，三个变体可复用同一资源。尺寸或透明度修改不重复添加图片；同字节、同设置为无操作。新图片沿用 4 MiB 压缩输入、4096 像素单边、4 Mi 像素解码和整项 4 MiB 历史预算，实际还须容纳源 XML。Web 宿主在提交前验证解码，再通过现有资源加载器提供 RGBA。默认面板按 96 dpi 读取自然尺寸，在页边距内等比缩小，允许显式修改宽高和透明度。面板先读取当前值，再编辑或移除；文档身份或 revision 变化后须重新读取，混合变体明确提示。

`execute({ operation: "rasterHeaderDocx", bytes })` 在现有图片预算内返回像素尺寸或 `{ error }`。`DocumentEditor.pages.imageDimensions(bytes)` 提供异步尺寸查询。默认水印面板用它计算初始宽高。提交新图片时，宿主对已复制的字节请求 `verify: true`。核心能解码图片时返回 `coreVerified: true`，其余图片由浏览器核对解码尺寸。预检不创建图片资源或历史记录。

核心保存为页眉 `Watermarks` 图库内容控件中的 DrawingML 文字形状或图片。文字按真实字体测量；图片保存原生尺寸和 `a:alphaModFix`。两者在目标页的实际纸型及页边距内居中并置于正文后方，不占正文分页空间，不加入正文语义或字数。核心 `Layout.pageSections` 保存逐页的节序号与节内页序，奇偶分节补白页使用 `None`；水印按该节首页设置、实际编号奇偶和继承区域选择变体，补白页不绘制。普通页眉文字和 PAGE/NUMPAGES 编辑保留原水印 XML。Canvas、页面图片与 PDF 使用相同位置与透明度；文字颜色按页面纯色背景合成，图片保留源 alpha，后续正文和对象照常覆盖。受保护文档仍可显示既有水印。文字/图片互换、设置和移除共用目标节页面保护、原子资源事务、精确历史、输出预算和保存重开；缺字体、损坏图片、扩展源或预算失败保留源与重做历史。

当前可读写本合同的单节及多节原生文字和图片配置。导入 VML、图片裁剪/旋转及带额外属性、效果或其他结构的水印继续保护，不能用本操作覆盖未知源。实现归 [`watermark-source.mbt`](../../../modules/formats/src/docx/watermark-source.mbt)、[`watermark-picture.mbt`](../../../modules/formats/src/docx/watermark-picture.mbt)、[`watermark-edit.mbt`](../../../modules/formats/src/docx/watermark-edit.mbt)及 [`watermark-layout.mbt`](../../../modules/formats/src/docx/watermark-layout.mbt)。页眉内容控件依据 [ONLYOFFICE SetWatermarkProps](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L12823-L12909)，文字形状、字体测量和居中依据 [createWatermark](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/GraphicObjects/GraphicObjects.js#L590-L734)，图片适配和透明度依据[同一函数的图片分支](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/GraphicObjects/GraphicObjects.js#L533-L590)，未复制上游源码。

### 页面边框

`FoundationSession/Client.execute({ operation: "setPageBorders", revision, section, borders })` 与 `DocumentEditor.pages.setPageBorders(section, borders)` 修改指定节的页面边框。`section` 使用上述零起始源序号。`borders` 使用导出的 `DocxPageBorders`：`{ offsetFrom, display, zOrder, sides }`。`offsetFrom` 为 `page/text`，分别从该节纸张边缘或正文边距外侧计算；`display` 为 `allPages/firstPage/notFirstPage`，首页指该节的首页；`zOrder` 为 `front/back`。`sides` 最多四个互异的 `DocxPageBorder { side, style, color, themeColor, width, space }`，`side` 为 `top/left/bottom/right`，必填 `style` 为 `single/double/dashed/dotted`，`color` 为六位 RGB，必填 `themeColor` 为原生主题颜色名或 null，`width` 为 0.25–12 pt 且须为 1/8 pt 的倍数，`space` 为 0–31 的整数 pt。空 sides 保留设置但不绘制边框；null 只移除该节 `pgBorders`。`pageSetup(section).borders` 返回原生值和保护原因。

默认页面面板共用节选择，提供四边独立启用、单线/双线/虚线/点线样式、颜色、宽度和距离，以及基准、显示页面和前后层次。草稿绑定 revision 和已读取的节；同一修订内切节也重新加载，跨页导航不改变目标。原生输入先沿既有队列提交。核心按 OOXML 顺序写目标 `sectPr/pgBorders`，缺少末节属性时与边框一起创建；保留其他节、正文、选区、待输入格式和其他部件。重复设置不新增历史，移除、背景修改与边框共用精确混合历史和保存重开。页面尺寸变化及边框修改按各节实际纸型验证边框不交叉，失败不提交，并保留待重做项。

核心 `Flow.pageBorders` 为必需结构，无边框时使用空 sides。边框不改变正文分页；缓存复用后派生当前边框，不把装饰写进缓存原页。背面边框位于页面背景之后、正文与表格之前，正面边框通过 `PageFrame.pageBorders` 在正文之后绘制。四边先竖后横，横边覆盖交角；纸张基准的距离量到外缘，正文基准向外留空。Canvas 与 PDF 使用相同填充矩形。几何和顺序依据 [ONLYOFFICE DrawPageBorders](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L5519-L5635)，未复制上游源码；实现归 [`page-borders.mbt`](../../../modules/formats/src/docx/page-borders.mbt)、[公共边框布局](../../../modules/layout/src/page-borders.mbt)及 [`docx-page-borders.tsx`](../../../packages/docx/src/react/docx-page-borders.tsx)。

双线保留原生 `w:sz` 的每条线宽度，两条等宽线之间留同宽间隙，总占宽为 `3*width`。纸张基准从外线外缘起算；正文基准按总占宽向外留距。内框在相邻双线侧内缩两个线宽，单线侧保留原边界；允许四边混用样式。单线/双线使用同一矩形图元与缓存派生，不改变正文。线型名称依据 [ONLYOFFICE BorderType](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L10287-L10300)。其页面绘制尚未区分双线，线宽换算与等分采用第二参考 [LibreOffice ConvertBorderWidthFromWord](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/editeng/source/items/borderline.cxx#L205-L238)及 [getWidthImpl](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/editeng/source/items/borderline.cxx#L328-L355)，未复制执行代码。

虚线 `dashed` 和点线 `dotted` 沿相同边缘几何拆分为填充矩形，Canvas/PDF 共用每段位置。虚线的线段/间隙比为 16:5，点线为 1:2，均按该边线宽缩放；每边从起点开始，末段裁剪到边缘长度。横边仍在竖边之后绘制，允许与单线/双线及主题色混用。单页全部边框最多 8192 个填充片段，超出返回 `limit-exceeded`；页面或边框编辑在提交前检查该上限，保留源与历史。ONLYOFFICE 的页面绘制暂未区分这些线型，分段节奏采用第二参考 [LibreOffice GetDashing/GetLineDashing](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/svtools/source/control/ctrlbox.cxx#L247-L306)，未复制执行代码。

导入支持单线、双线、虚线、点线、显式 none/nil、RGB、按黑色解释的 auto，以及原生 `themeColor/themeTint/themeShade`。主题色复用文字的槽映射和 HSL 明暗变换，查询返回当前 RGB；主题修改同步更新各节边框及 Canvas/PDF。修改宽度、距离、样式或其他边时，绑定未变的边保留原生缓存颜色、主题槽与明暗属性。完整无操作保留输入字节。

`themeColor` 接受 `dark1/light1/dark2/light2`、`accent1`–`accent6`、`hyperlink/followedHyperlink` 和映射名 `text1/text2/background1/background2`。非空时，核心按当前主题解析颜色，传入 `color` 只需满足 RGB 格式；保持同一绑定时保留已有明暗变换，换到另一绑定时使用其基础色。设为 null 时使用传入 RGB，并解除该边原有的主题及明暗绑定；即使 RGB 与当前显示相同，也会解除绑定。默认四边均提供主题槽和固定 RGB 选择，直接修改颜色也解除绑定。无主题的可编辑文档首次绑定时，边框、默认主题、关系及内容类型合为一项预算内历史；撤销恢复缺主题状态。严格传输在查询中显式输出 `themeColor: null`。类型与校验归 [`docx-page-borders.ts`](../../../packages/docx/src/core/docx-page-borders.ts)，沿 `docx-format` 的原有导出提供。主题读取依据 [ONLYOFFICE Read_pgBorder](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Serialize2.js#L10086-L10123)，复用 [`theme.mbt`](../../../modules/formats/src/docx/theme.mbt)，未复制执行代码。

主题写出同时保留 RGB 缓存和原生颜色引用，依据 [ONLYOFFICE WritePgBorder](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Serialize2.js#L3067-L3097)，未复制执行代码。

未知线型、已有源中缺失或未知的主题槽、非法明暗值、艺术边框、阴影/框效果、重复节点、未知属性/子节点及目标注释保持保护和布局诊断。镜像/装订线、文档保护及预算沿页面设置保护；其余边框样式继续实施。

### 页码格式与起点

`DocumentEditor.pages.setPageNumbering(section, value)` 与 `FoundationSession/Client.execute({ operation: "setPageNumbering", revision, section, numbering: value, profile })` 修改指定节页码。`section` 使用上述零起始源序号。`value` 为 `DocxPageNumbering { start: number | null; format }`，start 是 0–4294967295 的整数，null 表示续接前节；首节续号从 1 开始。format 接受 `decimal`、`decimalZero`、`lowerLetter`、`upperLetter`、`lowerRoman`、`upperRoman`。整个 value 传 null 时移除该节 `w:pgNumType`，恢复十进制续号。`pageSetup(section).numbering` 返回原生 `{ value, reason }`，区分省略起号和显式起号；不支持的节属性返回 null 与原因。默认页面面板共用节选择，提供重启开关、起点、格式、应用和重置，跨页导航不改变目标节。

核心源模型 `docx.SectionNumbering` 以 `Int64?` 区分起号和续号；派生的 `layout.PageNumbering` 保留 UInt32 范围的 Int64 起点，公开 JSON 传精确数值或 null。必需的 `Flow.pageNumbering` 与各节配置参与页边文字派生。PAGE 为节起点加节内物理页序，NUMPAGES 为实际总页数，续号使用前节实际末页的下一号。字段显式格式优先于节格式，未指定格式的 NUMPAGES 使用十进制。字母/罗马数字复用既有 [Office 编号格式](../../../modules/layout/src/number-label.mbt)，包括零值和循环规则；页码加法使用 Int64，不在 UInt32 起点附近溢出。节内首个物理页的首页变体优先，其余页面按编号结果的奇偶选择 even/default；缓存中的对应空间随之更新。

原生 `chapStyle` 为 1–9 时作为章节元数据保留；修改起点或格式保留该值，显式重置随 `pgNumType` 一起清除。当前不生成章节页码前缀，`chapSep` 仍保护。元数据与渲染的边界沿固定 [ONLYOFFICE 节属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/sections/sect-pr.js#L520-L542)。

连续分节保留源起号声明，实际编号按前节续接，包括显式分页后的续接；依据 [ONLYOFFICE Get_SectionPageNumInfo2](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L14708-L14792)。前节分页留下的空白占位不确定下一页的页眉、页脚和正文起点；下一节在该页开始时使用自己的区域与边距，源光标位置仍保留。

操作沿现有目标节属性检查和源事务，按 OOXML 顺序插入或替换 `pgNumType`；续号省略 `start` 属性。修改前预检字体及全文分页，失败保留原源、选择、待输入格式和历史，包括待重做项。相同原生设置不新增历史；重置移除原属性。修改保留其他节、正文、页边 XML、字段代码和缓存，派生的 PAGE/PAGEREF 与实际页边变体同步重算；显式区域应用才写回当前字段结果。缺少末节属性时沿原有路径创建。章节前缀、未知格式、重复节点及带注释/处理指令的编号属性继续保护。

语义依据 [ONLYOFFICE 节起点与编号奇偶](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L14679-L14795)、[PAGE 的节格式/显式格式优先级](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L4828-L4845)及[字段格式映射](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFields/instruction-base.js#L133-L179)。实现归 [`page-numbering.mbt`](../../../modules/formats/src/docx/page-numbering.mbt)和[公共页码模型](../../../modules/layout/src/page-numbering.mbt)。更广页码格式与其他多节属性编辑仍继续实施。

### 页眉页脚

原生页眉页脚支持普通段落、表格、普通图片及已支持的 DrawingML 形状/文本框。`Flow.headers/footers` 及每节同名字段按变体保存 `RunningStory { paragraphs, tables }`；`DocxFlow` 使用相同结构。表格沿正文结构保留列宽、合并格、样式、嵌套表、底色与边框，复用正文块布局。单元格和普通文本框中的 PAGE/NUMPAGES 参与现有页码重排；框内段落使用所属页边身份，边框随身份映射。区域的行、底色、边框与图片作为独立 `PageFrame` 绘制，位于正文绘制之前；正文缓存保持独立。字体发现、链接和资源收集包含表格及框内段落。

区域始终只读。纯文字替换接口拒绝含表格或绘图的区域，失败保留源、修订和历史。每个区域最多 32768 个直接段落、4096 个顶层表格，嵌套和总行数沿用正文预算；活动区域须在一页内。超出下述范围的 VML、DrawingML 形状、图表、未知字段及溢出仍诊断。完整原件资格归[测试说明](../testing.md#当前兼容证据入口)。模型与布局归[RunningStory](../../../modules/layout/src/running-story.mbt)、[区域读取](../../../modules/formats/src/docx/running-read.mbt)及[区域布局](../../../modules/layout/src/running.mbt)。

原生 VML 支持绝对定位、无环绕的矩形和矩形文本框，包括标准类型 202。长度须为显式 point，几何沿既有绘图预算；样式、属性和子节点严格校验。文本复用普通 Word 段落与既有文本框布局，最多 256 段、32767 个 UTF-16 单元，每段最多 4096 单元。默认内边距按 [ONLYOFFICE CTextbox](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Logic/Vml.cpp#L1782-L1885) 保留；指向自身的续框引用按 [LibreOffice 处理](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/source/writerfilter/dmapper/DomainMapper_Impl.cxx#L6211-L6219)忽略，实际跨框链接仍拒绝。正文可显示此范围的矩形，并保护原生源；正文 VML 文本框仍须对应编辑隔离支持。实现归 [VML 读取](../../../modules/formats/src/docx/vml-read.mbt)和[共用文本框读取](../../../modules/formats/src/docx/text-box-read.mbt)。

页眉页脚中的命名 `STYLEREF "style name"` 保留每个缓存结果 run 及其字符样式，可带 `MERGEFORMAT`。核心不重算命名样式引用；纯文字替换拒绝该区域，避免删除原字段。该边界沿固定 [ONLYOFFICE 命名引用实现](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L981-L1035)的页边缓存行为。未知开关、锁定、缺失结果和正文中的该缓存配置仍保护。

普通 DrawingML 图片按所属页眉或页脚解析关系，沿现有解码器装载 PNG/JPEG，保留尺寸与裁剪。直接段落还支持无环绕定位图片；页面、页边距坐标保持物理页位置，段落坐标随区域移动。图片命中返回区域保护原因；正文文字与图形遮挡页眉图片时优先命中正文。非零 `effectExtent` 在无环绕定位中保留并验证边界，实际绘制效果仍按图片读取规则检查。表格内定位、文字环绕、旋转、外部图片及资源键冲突继续拒绝。实现归[图片读取](../../../modules/formats/src/docx/picture-read.mbt)，扩展边界语义参考 [Open XML effectExtent](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.wordprocessing.effectextent?view=openxml-3.0.1)。

`FoundationSession/Client.execute({ operation: "runningArea", revision, section, kind, variant })` 返回 `DocxRunningArea { revision, section, linked, content, distance, reason, differentFirst, differentEven, shared }`。`section` 使用上述零起始源序号；`linked` 表示该变体继承前节，首节恒为 false。`kind` 使用 `DocxRunningKind` 的 `header/footer`；`variant` 使用 `DocxRunningVariant` 的 `default/first/even`。`DocumentEditor.pages.runningArea(section, kind, variant)` 沿原生输入屏障查询。`content` 是 `DocxRunningContent[]`，每项为 `{ text: string; target?: string }` 或 `{ field: "PAGE" | "NUMPAGES"; format?: "decimal" | "lowerLetter" | "upperLetter" | "lowerRoman" | "upperRoman" }`，从 Wasm/Web foundation 模块导出。文字以 LF 分段，以 U+2028 表示软换行，保留 Tab；`distance` 为距纸张上边或下边的 pt，同一节同类区域的三种变体共用该距离。不支持的源返回保护原因。

`FoundationSession/Client.execute({ operation: "setRunningArea", revision, section, kind, variant, content, distance, profile })` 与 `DocumentEditor.pages.setRunningArea(section, kind, variant, content, distance)` 替换指定节区域的文字和页码字段。继承或显式共享的区域须先设为独立。编辑独立区域会同步影响仍继承它的后续节。核心使用 `RunningContent.Text(String)/Link(String, String)/Field(String)`，显式格式使用 `FormattedField(String, String)`。例如 `[{ text: "Page " }, { field: "PAGE" }, { text: " of " }, { field: "NUMPAGES" }]`。前者显式提供字体映射，编辑器复用当前映射。列表最多 256 项；文字与字段合计最多 8192 单位，文字按 UTF-16、每个字段按一单位计算。相邻文字会合并，空列表用于清空；段内最多 64 个字段。距离为 0–14400 pt 的整数 twip，并须给正文留出可用区域。缺失的 `hdr/ftr` 部件、关系、内容类型、节引用及距离在同一事务创建，候选排版和输出预算通过后提交。清空保留一个空段落和已创建部件，不清理未知资源。

文字项带 `target` 时生成普通原生超链接，移除该属性恢复普通文字。目标最多 2048 个 UTF-16 单元，接受 HTTP、HTTPS、mailto 或指向可用正文/单元格书签的 `#name`；空显示文字、非法地址及缺失目标拒绝整项修改。默认面板在每个文字项下提供链接地址，清空后移除链接。带链接的 LF 仍分段，软换行和 Tab 保留；相邻且目标相同的文字合并。查询保留链接目标，未改段落和仅改距离时保留原始 XML。目标书签改名或删除时，已知页眉页脚引用与正文合为一次事务，失败保留整包；共享和未启用变体也同步更新。未知跨部件引用继续保护。

外链关系归所属页眉/页脚部件，允许不同区域使用相同关系身份。首次关系部件及必要内容类型声明与文字共用一项精确历史；解除共享时沿既有路径复制。显示、编辑和输出不请求目标。PDF 按实际活动变体逐页生成[文字链接注释](docx-content.md#docx-pdf-文字链接)，复用实际文字边界与正文书签坐标，重复行计入原有预算。实现归 [running-links.mbt](../../../modules/formats/src/docx/running-links.mbt)、[有序内容](../../../modules/formats/src/docx/running-content.mbt)及[注释收集](../../../modules/formats/src/docx/links-layout.mbt)，PDF 语义参考 [ONLYOFFICE 文字链接](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L2886-L3000)。

`FoundationSession/Client.execute({ operation: "setRunningOptions", revision, section, first, even, profile })` 与 `DocumentEditor.pages.setRunningOptions(section, first, even)` 修改首页和奇偶页开关。`first` 写回目标节 `titlePg`，`even` 写回全文 `evenAndOddHeaders`；默认面板明确全文作用范围。按需创建节或设置部件；关闭保留所有区域和引用，重新开启恢复同一内容。开关不隐式创建文字部件。首页启用时优先选择 first；其余按节起点计算的偶数页在奇偶开关启用时选择 even；其他页选择 default。继承解析后仍缺失的活动变体显示空白，不回退到 default。选择依据 [ONLYOFFICE 页边区域解析](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Layout/Base.js#L85-L116)，未复制上游源码。

`FoundationSession/Client.execute({ operation: "setRunningLink", revision, section, kind, variant, linked, profile })` 与 `DocumentEditor.pages.setRunningLink(section, kind, variant, linked)` 设置目标变体的节间继承。false 为继承或显式共享区域创建独立部件；继承空内容时创建显式空部件。true 移除当前节引用并恢复前节继承，首节拒绝此操作。`shared` 只统计显式引用同一部件的别名，包含非活动变体；继承的后续节用 `linked` 表示。已独立且无共享时设 false，或已继承时设 true，均不增加历史。默认面板共用节选择，先读取区域，再提供独立或链接前节操作；切节重置草稿，跨页导航保持目标。

核心完整复制区域 XML 及其关系，保留注释、属性和关系 ID；内部目标改为包内绝对路径，外链保持原地址且不请求网络。图片等资源继续复用，旧部件保留；恢复继承也保留原部件和资源。新部件、关系、内容类型及选定引用合为一次有界事务，候选失败保留原文档，支持精确撤销/重做与重开。未知或带注释的区域源可独立保留，纯文字编辑限制继续适用；带注释的节引用继续保护。复制思路参考 [ONLYOFFICE 断开页边继承](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L11643-L11715)。实现归[节间链接事务](../../../modules/formats/src/docx/running-link.mbt)。

修改保留正文、选区、待输入格式和其他部件。距离单独变化时完整保留区域源；文字替换保留未改段落的原始 XML，修改的段落保留段落属性与首个 run 的字符属性，字段按该段原有字段顺序沿用结果字符属性，并写为标准简单域；新增段落沿用最后一段。重复设置不新增历史；开关、部件创建、文字和距离修改共用精确撤销重做及保存重开。默认页面面板提供区域、所属页面、读取、文字/字段、距离和两个开关，可在文字光标处插入当前页码或总页数，并更换字段种类、显式格式或移除，过期草稿须重新读取；应用开关保留尚未提交的文字草稿。

核心 `Flow.headers/footers` 按 `default/first/even` 保存区域的 `RunningStory`，配合 `headerDistance/footerDistance/differentFirst/differentEven` 派生各页正文上下空间。`Layout.running` 按页保存 `PageFrame`，其中 `lines` 保留页边与脚注行；区域绘制独立于正文，脚注随正文层绘制。页眉从上边距离开始，页脚在下边距离以上结束；实际行框、段距与正文边距共同确定避让。文字复用既有塑形、定位图元、Canvas/PDF 和语义文本；命中返回 `protected-content:running-area`，不产生正文编辑位置。活动区域的重复行计入原有总行数预算。几何依据 [ONLYOFFICE HeaderFooter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/HeaderFooter.js#L1735-L1804)。实现归 [`running-read.mbt`](../../../modules/formats/src/docx/running-read.mbt)、[`running-edit.mbt`](../../../modules/formats/src/docx/running-edit.mbt)、[开关事务](../../../modules/formats/src/docx/running-options.mbt)、[页边布局](../../../modules/layout/src/running.mbt)及 [`docx-running.tsx`](../../../packages/docx/src/react/docx-running.tsx)。

分页缓存包含三种活动页的正文空间。后缀复用同时检查当前空间和页序奇偶，首段变动不能把另一类页面的旧位置复用到当前页。普通表格行、纵向合并续页、保留段落链和孤行控制按当前页空间放置；纵向合并组的重复表头仍沿既有整组预留规则，按该组经过页面的最小可用高度判断，逐片段取舍继续完善。

已导入的页眉页脚支持 `PAGE` 和 `NUMPAGES` 的格式化计算，包括 `fldSimple` 和同段内的 begin/instrText/separate/result/end 成对域。接受缺省格式、十进制、大小写字母及罗马数字的显式格式开关，以及可组合的 `MERGEFORMAT`；保留首个结果 run 的有效字符样式。派生 `Span.field` 使用空串、字段名或带冒号格式后缀的字段名，格式归[页码格式与起点](#页码格式与起点)。`Span.text` 保留导入缓存，实际页边行按节编号、显式格式和物理总页数重新塑形。正文分页、历史和重开会重新计算，Canvas、语义文本和 PDF 使用相同结果。参考 [ONLYOFFICE PAGE 与 NUMPAGES](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L918-L928)。

字段结果改变换行时，核心按每页实际页边高度有界重排正文，最多八轮；不收敛时保留最后完整布局并给出诊断，输出沿既有诊断保护。正文空间和分页缓存包含逐页几何，跨页表格也使用该页空间。现有 1024 页和 32768 行预算继续生效，每段最多 64 个字段。未知指令/开关、锁定、嵌套、不完整或跨段域继续保护且不执行；多节继承读取见[多节分页](#多节分页)，更广编号格式继续实施。正文范围归[正文页码字段](#正文页码字段)。实现归[字段读取](../../../modules/formats/src/docx/running-fields.mbt)与[有界重排](../../../modules/layout/src/running-pagination.mbt)。

计算、保存和输出不改写域代码或缓存，不增加历史，也不改变原格式未保存状态。显式应用字段内容会把当前结果与内容修改放在同一项历史；内容和距离相同时，应用用于刷新已有缓存，结果相同则不新增历史。只改距离或开关仍保留区域 XML。刷新简单域和成对域时只替换结果文字，保留域代码、属性和字符样式；未知或带注释的源继续保护。缓存的 `PAGE` 使用目标节内该变体的首次出现页，并应用该节实际起号、续号及格式或字段显式格式；核心 `Layout.sectionNumbering` 保存各节已解析编号。首页取物理首页；偶数变体取编号后首次为偶数且未被首页占用的页面；默认变体取未被活动首页/偶数区域占用的首个页面。起点为 1 时仍分别遵循原有的 1、2 及默认区域 1/2/3 规则。非活动变体采用同一规则；`NUMPAGES` 使用当前文档总页数。屏幕/PDF 仍逐页计算。更新要求完整布局及原有历史/输出预算通过，失败保留原文档、选择和历史。行为参考 [ONLYOFFICE 字段创建与更新](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L23510-L23568)，当前写回归[有序内容及字段缓存](../../../modules/formats/src/docx/running-content.mbt)。

表格内容编辑、其他字段、更广页码格式、图片/审阅对象及页边原生光标仍待实现。共享同一部件的变体可显示，内容替换或缓存更新须先显式断开，避免改写其他区域；未知或带注释的目标源也不允许内容替换或缓存更新。非活动区域保持原源，启用前验证候选布局。正文查找和统计仍只覆盖既定正文范围。

### 正文页码字段

正文中的每个字段占一个逻辑对象位置，完整结果作为整体排版。位数改变或结果为空时保留该位置，光标和选区只落在字段前后。实际字形簇和完整显示文字用于语义文本、PNG 与 PDF，数字内部不拆行。页眉页脚保留原有排版方式。依据 [ONLYOFFICE 页码整体测量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/RunContent/PageNum.js#L154-L176)，实现归[字段行内排版](../../../modules/layout/src/field-run.mbt)。

导入的正文和普通单元格支持 `PAGE`、`NUMPAGES` 的简单域及同段成对域，沿用上述格式开关和首个结果 run 的有效样式。`PAGE` 使用字段所在行的物理页及当前节编号；`NUMPAGES` 使用实际纸张总数，分栏不增加页号。核心先用有界初始值分页，再按字段位置与总页数重排，和页眉页脚共用最多八轮的收敛限制。原段落、单元格及分页缓存参与同一路径，Canvas、语义文本、PNG 与 PDF 共用结果；布局与保存不改缓存或历史。

`FoundationSession/Client.execute({ operation: "updateBodyPageFields", revision, profile })` 和 `DocumentEditor.pages.updateBodyPageFields()` 显式刷新正文缓存，默认页面面板提供同名按钮。核心只改结果文字，清空多余缓存 run 的文字，保留域代码、属性、字符样式、其他部件和原选择，一次更新合为一项精确历史。结果相同不改 revision，保留当前显示布局和后续原生导航。缺字体、未知/锁定/嵌套指令、结果内注释或处理指令、保护及原有输出/历史预算失败时整体拒绝。

`FoundationSession/Client.execute({ operation: "insertBodyPageField", revision, field, profile })` 和 `DocumentEditor.pages.insertBodyPageField(field)` 将当前范围替换为一个原生简单域。`DocxBodyField` 接受 `DocxPageField` 的 `{ field: "PAGE" | "NUMPAGES", format? }`，以及下述[书签页码引用](#书签页码引用)、[序列编号字段](#序列编号字段)、[书签文字引用](#书签文字引用)和[脚注与尾注编号引用](#脚注与尾注编号引用)，可选格式沿用上述五种显式格式。默认页面面板提供“插入正文页码”和“插入正文总页数”。核心保留附近字符格式，写入实际布局值，将光标放到域后，插入与范围删除合为一项精确历史。正文、空段落和普通单元格共用事务。未知源、超限、缺字体及不完整布局整体拒绝，不改其他域的旧缓存。依据 [ONLYOFFICE 插入字段及直接格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L23510-L23565)，实现归[正文域插入](../../../modules/formats/src/docx/body-field-insert.mbt)。

仅含受支持简单域和普通内容的段落，已有原生光标、相邻文字输入、同段范围替换、整域 Delete/Backspace 和组合输入。一个域保持一个源位置，删除整个源元素，不把结果拆成可编辑数字。查找中的后续文字也沿用逻辑位置。域的正文范围及整格剪贴板分别沿用[正文富文本片段](docx-tables.md#正文富文本片段)与[单元格富文本片段](docx-tables.md#单元格富文本片段)；复杂域范围及其他指令继续保护。其他普通段落可继续输入并触发实时重算。实现归[正文域输入](../../../modules/formats/src/docx/body-field-input.mbt)。

正文及同一普通单元格内，Enter 可在简单域两侧拆段，段落边界 Delete/Backspace 可合并。跨段范围替换和组合输入将所选域完整移除，保留范围外的域、代码和缓存。合并时补齐移动元素的命名空间，将原段落继承的字符格式保留为直接属性。书签和批注锚点随拆合移动，被删段落中的锚点恢复到正确逻辑位置；源、选择及其他部件沿同一精确历史保存重开。跨容器、复杂/未知/锁定域和原有预算失败仍整体拒绝。依据 [ONLYOFFICE 域不可拆分](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Field.js#L169-L177)与[段落拆分及属性继承](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L13838-L13869)，实现归[正文域输入](../../../modules/formats/src/docx/body-field-input.mbt)和[跨段源事务](../../../modules/formats/src/docx/range.mbt)。

简单域整体参与已有字符格式查询和修改，也支持所在段落的对齐、间距等段落格式。默认格式面板、格式捕获和光标处的待输入格式共用原有命令。核心查询并修改首个实际结果 run，保留域代码、缓存文字、前置空 run 和其他缓存样式。域与邻接普通文字混合选择时，普通 run 按边界拆分，域保持完整；格式修改与后续输入各自沿精确历史保存重开。复杂域、未知字段或结果属性继续拒绝格式修改。依据 [ONLYOFFICE 字段结果格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1774-L1812)，实现归[格式查询](../../../modules/formats/src/docx/format-query.mbt)与[字符格式事务](../../../modules/formats/src/docx/format-character.mbt)。

`FoundationSession/Client.execute({ operation: "bodyPageField", revision, selection })` 返回 `DocxBodyPageField`：`{ revision, selection, field, reason }`。完整选择一个简单域，或把光标放在其前后的对应亲和侧时，`field` 为 `DocxBodyField`；没有可编辑域时返回 `null` 及原因。普通文字、多个域、跨段及复杂域不能作为一个域修改。查询保持原源、选择和历史。

`editBodyPageField(revision, selection, field, profile)` 修改该域的类型、书签目标、序列名称与显式编号格式。省略 `format` 时，PAGE/PAGEREF 沿用节格式，NUMPAGES/SEQ 使用十进制。核心只改指令属性和当前域的实际结果，保留 `MERGEFORMAT`、其他源属性、结果格式、空 run、选择及其他域缓存；多余结果文字清空。修改合为一项精确历史，相同语义指令不刷新缓存或增加历史。未知指令、锁定、缺字体、布局或预算失败保持原文档。显式结果刷新仍使用 `updateBodyPageFields`。

`DocumentEditor.pages.bodyPageField()` 返回附有 `documentId` 的 `DocumentBodyPageField`；`editBodyPageField(source, field)` 核对文档、revision 和选择后提交。默认页面面板提供读取、类型、编号格式和应用控件；切换选择后须重新读取。代码修改依据 [ONLYOFFICE ChangeInstruction](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L2074-L2095)，原生简单域结构沿用已有序列化。实现归[正文域代码事务](../../../modules/formats/src/docx/body-field-edit.mbt)，未移植上游执行代码。

每段最多 64 个字段，正文布局最多 4096 个字段位置。重复表头中的 `PAGE`、不可定位的结果及未收敛结果给出布局诊断，阻止不确定的刷新或输出。其他域及完整字段创作继续实施。依据 [ONLYOFFICE 字段行所在页](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L918-L928)与[实际页总数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1312-L1315)。实现归[正文字段布局](../../../modules/layout/src/body-fields.mbt)和[缓存刷新事务](../../../modules/formats/src/docx/body-field-edit.mbt)。

### 原生目录字段读取

正文中的普通跨段复杂 `TOC` 字段已有读取与结果保护。外层字段使用 `begin/instrText/separate/end`，缓存由连续正文段落组成；支持 `\o "1-3"` 等 1–9 级有序范围，以及可选 `\h`、`\z`、`\u`，未知或重复开关继续保护。范围按原生标记建立索引，目录中没有标记的中间段落同样只读，避免原生输入、格式或跨段删除改坏缓存。未知和超长跨段字段也保护其全部结果段落。

目录条目的内部文字链接、简单 `PAGEREF`，以及链接内的同段复杂 `PAGEREF` 复用已有书签页号、分页和 PDF 链接。Canvas、语义和 PDF 显示实际页码；布局、保存与查询不改旧缓存。默认“更新正文域”及现有 `updateBodyPageFields` 只刷新这些页码缓存并进入一项精确历史，不重建标题条目。目录外的输入、历史与保存重开保持原路径。

原生 MoonBit `Session::table_of_contents(revision)` 返回 `{ revision, items }`。每项含首尾段落 `paragraph/endParagraph`、`firstLevel/lastLevel`、`hyperlink/outline`、原生指令 `instruction` 和源结构保护原因 `reason`。查询最多 256 项，受支持字段最多 4096 个结果段落；指令解析上限为 256 个 UTF-16 单元，未知源的查询前缀最多保留 257 个单元，完整源始终保留。核心与 Web 已接通下述目录编辑入口；标准 SDT 包装沿下述范围处理；表格内目录、其他指令及复杂导入变体仍受保护或给出诊断。实现归 [`toc-read.mbt`](../../../modules/formats/src/docx/toc-read.mbt)和既有字段解析；语义参考 [ONLYOFFICE TOC 指令](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L239-L258)及[标题目录计算入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L929-L1000)。

### 目录创建与整体更新

同步和 Worker `tableOfContents(revision)` 返回 `DocxTableOfContents`；`DocumentEditor.pages.tableOfContents()` 附加 `documentId`。`insertTableOfContents(levels = 3)` 在当前普通正文段落前插入目录，深度为 1–9，保留正文和选择。`editTableOfContents(source, { action: "update" | "delete", paragraph })` 操作目录首段，核对文档和 revision；过期目录拒绝后仍可继续编辑。底层 `editTableOfContents(revision, change, profile)` 使用 `DocxTocEdit`，核心入口为 `Session::edit_table_of_contents`。默认目录面板提供级数、插入、整体更新和删除。

核心按有效大纲级别和正文顺序提取标题，包含普通表格标题，排除已有目录结果。标题取当前编号、文字和字段结果，Tab/软换行转为空格。复用可用的段首书签，缺失时创建独立原生锚点；保留已有 TOC 样式，缺失时复用内置样式预设。写回复杂 TOC、文字链接、点引导符及简单 PAGEREF，右制表位沿首栏宽度。整体更新保留原目录指令、级别和链接开关，重建全部条目；删除保留标题锚点与样式。没有标题时保留可更新的空目录。

生成后按实际分页重新提取标题字段结果，最多八轮收敛，再缓存实际页码。每次操作的正文、样式资源和选择共用一项精确历史，无变化不增加历史；布局、字体、保护或预算失败原子拒绝。最多 4096 条标题，每条标签最多 4096 个 UTF-16 单元，标签合计最多 1 Mi 单元，并沿用历史、包及布局预算。带绘图/数学的标题、含注释/修订/脚注等不可丢失内容的目录结果继续保护。自动更新、复杂控件及表格内目录编辑、富文本条目和其他 TOC 指令继续实施。实现归 [`toc-source.mbt`](../../../modules/formats/src/docx/toc-source.mbt)、[`toc-edit.mbt`](../../../modules/formats/src/docx/toc-edit.mbt)及[默认控件](../../../packages/docx/src/react/docx-toc.tsx)。标题与制表位依据上述 ONLYOFFICE 目录计算入口，未复制上游执行代码。

### DOCX 索引

正文及普通单元格支持原生简单域和同段复杂 `XE "term"`。已知条目隐藏显示，文字位置不计入域代码；条目修改只改指令，保留原生包装、隐藏属性和其他元数据。普通输入保留条目，富文本复制和粘贴保留术语；剪切、范围替换和跨段删除同步移除所选条目，沿同一精确历史恢复原源。术语接受冒号分隔的一至三级，每级非空，整体最多 255 个 UTF-16 单元。未知开关、混合可见内容、注释和未知属性继续保护。

默认索引面板提供标记、修改/删除条目及插入、更新/删除索引。标记放在选择终点，保留所选文字；插入在当前段落前生成原生跨段 `INDEX`。核心按各级不区分大小写的词典序排序，合并同名条目，去重同一物理页，按实际节页码输出 `PAGEREF`。父级可没有页码，空索引保留可更新的占位结果。生成结果保持只读；显式更新沿既有目录样式、书签、有界重排、缓存和精确历史，保存不会自动改写缓存。当前生成范围为单节、单栏普通正文；多节、多栏及复杂导入继续保护。

原生 `Session::indexes(revision)` 返回 `{revision, entries, indexes}`。条目含 `id/paragraph/label/reason`，生成索引含 `paragraph/endParagraph/instruction/reason`。`edit_index` 接受 `IndexEdit` 的六项操作。同步/Worker 的 `indexes`、`editIndex` 使用 `DocxIndexes` / `DocxIndexEdit`；命令为 `mark`、`updateEntry`、`deleteEntry`、`insert`、`update`、`delete`。Web 的 `DocumentEditor.pages.indexes()` 附加 `documentId`，`markIndexEntry(label)`、`insertIndex()` 和 `editIndex(source, change)` 校验当前文档与 revision；过期目录报错后可继续输入。查询上限为 4096 个条目、256 个索引；结果最多 4096 段，仍受原有布局和历史预算限制。

已知 `INDEX` 指令接受单栏 `\c 1` 和最多五字符的 `\e` 分隔符；无显式分隔符时使用逗号及空格，新建索引显式使用制表符。其他开关、自动更新、富文本条目、跨段 XE、语言专用排序、索引内部光标和完整导入变体仍待实现。读取归 [`index-read.mbt`](../../../modules/formats/src/docx/index-read.mbt)，条目与范围事务归 [`index-edit.mbt`](../../../modules/formats/src/docx/index-edit.mbt)，排序/页码归 [`index-source.mbt`](../../../modules/formats/src/docx/index-source.mbt)，索引结果复用 [`toc-edit.mbt`](../../../modules/formats/src/docx/toc-edit.mbt)，传输归 [`docx-index.ts`](../../../packages/docx/src/core/docx-index.ts)，界面归 [`docx-index.tsx`](../../../packages/docx/src/react/docx-index.tsx)。原生导出参考 [LibreOffice INDEX](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/source/filter/ww8/ww8atr.cxx#L2385-L2427)，术语层级和重复页规则参考 [Microsoft 创建索引](https://support.microsoft.com/en-us/word/create-and-update-an-index)，分隔符参考 [INDEX 指令](https://support.microsoft.com/en-us/word/field-codes-index-field)。未复制上游执行代码。

### DOCX 资料来源

默认“资料来源”面板支持新增、修改和删除文档来源。`DocumentEditor.sources.catalog()` 返回附带 `documentId` 的 `DocxSources`；`createSource(source)` 和 `editSource(catalog, change)` 沿同一编辑队列操作。同步/Worker 使用 `sources(revision)`、`editSource(revision, change)`；原生入口为 `Session::bibliography_sources` 与 `edit_bibliography_source`。命令接受 `create/update` 加 `source`，或 `delete` 加 `tag`。来源含必填七个字符串字段 `tag/kind/author/title/year/publisher/url`；标题非空，其余展示字段可为空。

`kind` 支持 `Book/JournalArticle/InternetSite/Report/Misc`。标签区分大小写，长度为 1–64 个 UTF-16 单元，首尾无空白，排除引号及反斜线；作者、标题、年份、出版商和网址分别上限 1024、1024、32、512、2048。所有字段校验 XML 文字、控制字符和完整 Unicode。作者按“姓, 名”写入一个原生 Person；已有 Corporate 保持机构作者。期刊名称对应 `JournalName`，网站名称对应 `InternetSiteTitle`，其他类型对应 `Publisher`；网址仅保存文字，不发起网络请求。

核心使用主文档内部 customXml 关系指向的原生 `b:Sources`，读取 2006 标准和 2004 旧命名空间。首次创建同时分配数据、itemProps、关系及内容类型，避开已有部件和 datastore 身份；这些资源与来源记录共用一项精确历史。修改只替换已改变的已知字段，保留根样式、GUID/LCID、其他记录、编辑者、卷期和页码等未改源。多作者、扩展姓名、注释及未知作者数据单独保护作者字段，仍可修改标题等其他字段；未知来源类型保持只读。标签作为稳定身份，修改时保持。

删除前扫描全部 Word 内容类型部件中的简单、分段复杂 `CITATION` 及 `\m` 合并标签；已引用或无法确认引用归属时拒绝删除。目录逐项返回 `reason/authorReason/deleteReason`。共享或多份来源表、重复标签及未知拥有关系保持保护；最多 512 条来源、64 条 customXml 关系和 32768 个来源 XML 节点，引用扫描最多 1048576 节点、32 层域和 1024 单元指令，另受既有包和历史预算约束。查询及无变化修改不新增历史。来源编辑保留正文、选择和待输入格式，保存不刷新引文缓存。Web 拒绝旧目录和重复标签后可继续编辑。

引文归[DOCX 引文](#docx-引文)，书目归[DOCX 书目](#docx-书目)；完整书目样式、完整多作者编辑及全局来源库继续实施。读取归 [bibliography-source-read.mbt](../../../modules/formats/src/docx/bibliography-source-read.mbt)，资源归 [bibliography-source-parts.mbt](../../../modules/formats/src/docx/bibliography-source-parts.mbt)，事务归 [bibliography-source-edit.mbt](../../../modules/formats/src/docx/bibliography-source-edit.mbt)，接口归 [docx-sources.ts](../../../packages/docx/src/core/docx-sources.ts)，面板归 [docx-sources.tsx](../../../packages/docx/src/react/docx-sources.tsx)。原生结构依据 [Microsoft 来源 XML](https://learn.microsoft.com/en-us/office/vba/word/concepts/working-with-word/working-with-bibliographies)、[标准 Source](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.bibliography.source?view=openxml-3.0.1)及 [LibreOffice customXml 保存](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/source/filter/ww8/docxexport.cxx#L1860-L1940)。未复制上游执行代码。

### DOCX 引文

资料来源面板提供“插入引文”和“更新引文”。`DocumentEditor.sources.insertCitation(sourceCatalog, tag)` 校验来源所属文档、revision 和可用作者后，在当前正文或普通单元格范围插入原生简单域；`updateCitations()` 显式刷新已支持的正文引文。同步/Worker 使用 `editCitation(revision, change, profile)`，严格命令为 `{action:"insert", tag}` 或 `{action:"update"}`。原生入口为 `Session::insert_citation` 和 `update_citations`。标签规则归[资料来源](#docx-资料来源)。

新建指令为 `CITATION "tag" \* MERGEFORMAT`，内部字段代码为 `CITATION:tag`，保留大小写、空格、冒号和中文标签。核心生成基础“(作者, 年份)”缓存；作者采用来源目录中的“姓, 名”或机构文字，作者为空时取标题，年份为空时省略分隔符。该显示不声明完整 APA/MLA 排版。未知来源类型、扩展或多作者数据继续保护引文格式操作，保留其原源。

读取支持一个带引号或不带引号的标签，以及可选 `\* MERGEFORMAT`。简单域与同段复杂域的多个结果 run 合并为一个显示结果，沿用首个结果格式；原包装、属性及所有缓存保持到显式更新。来源修改、普通字段刷新、预览、保存和重开不改写引文缓存。显式更新使用上述基础显示，包括导入引文；已有书目样式元数据保留。`\l/\m` 等其他开关和完整引用样式继续实施。

段内原生引用内容控件 `w:sdt` 的 `w:citation` 类型现可显示缓存。控件身份、结构、字段边界及每段 64 个字段预算有校验；一个控件只接受一个引用字段。控件独占未编号段落时，按原生规则忽略首行缩进，保留左缩进；有普通正文前缀时仍使用首行缩进。普通输入保护控件所在段落，已绑定来源的引用可沿现有显式更新命令刷新缓存。没有标签的导入引用保留原有错误结果，以 `CITATION:` 通过预览；插入和更新命令仍要求合法来源。未知控件属性、绑定、嵌套和跨控件字段继续保护。控件、指令及非目标源保留，缓存更新只改文本及必要的空白属性。实现归 [citation-control.mbt](../../../modules/formats/src/docx/citation-control.mbt)。原生依据见 [ONLYOFFICE Sdt 类型](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Logic/Sdt.cpp#L1309-L1320)、[独占控件判断](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L1462-L1534)及[首行偏移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js#L1128-L1183)。

插入复用一项范围替换和原生字段历史，光标落在域后；简单域占一个逻辑位置，原生输入、整域删除和字符格式沿既有规则。更新合为一项事务，保留选择和待输入格式，无变化不新增历史；提交前检查布局与字体，失败保留包和重做。已引用来源沿来源管理的删除保护。复杂域范围及页边/注释区域插入仍受保护。普通字段面板只说明引文由来源管理，不把它解释成页码。正文范围及整格矩形的富文本复制/剪切携带简单引文的完整原生来源记录，保留缓存、字符格式、多作者、编辑者和卷期等元数据。目标复用内容相同的记录；标签相同而内容不同时分配新的 `odCitationN` 标签，并更新所粘贴的域。相同 Guid 对应不同内容时拒绝粘贴。源记录不随剪切删除。缺少来源或携带未知资源扩展时保留纯文本复制，并返回保护原因。目标缺少来源表时创建原生 customXml、属性及关系部件；来源和正文合为一项可精确撤销的事务。预检和失败保留目标、选择与重做。

片段沿用既有命名空间，以 `citationSource` 属性携带一个原生 Sources XML 的 Base64，导入后移除片段元数据。核心校验所属简单域、标签、来源数量、原生命名空间及资源预算。标准 2006 与旧版 2004 来源可分别转移；混合命名空间、外部资源扩展及复杂域片段保持保护。最多 512 条目标来源和 4096 个所选引文，并沿用片段、包、布局及历史预算。实现归 [bibliography-clipboard.mbt](../../../modules/formats/src/docx/bibliography-clipboard.mbt)。

创建与刷新沿单节可编辑正文域边界，结果受既有 4096 个正文域、256 单元指令、包、布局和历史预算限制；合并引文、多作者格式、完整引用样式继续实施，书目归[DOCX 书目](#docx-书目)。原生指令与事务归 [bibliography-citation.mbt](../../../modules/formats/src/docx/bibliography-citation.mbt)，缓存读取归 [running-fields.mbt](../../../modules/formats/src/docx/running-fields.mbt) 和 [flow.mbt](../../../modules/formats/src/docx/flow.mbt)，严格接口归 [docx-sources.ts](../../../packages/docx/src/core/docx-sources.ts)，默认控件归 [docx-sources.tsx](../../../packages/docx/src/react/docx-sources.tsx)。原生标签与缓存依据 [Microsoft 来源与引文](https://learn.microsoft.com/en-us/office/vba/word/concepts/working-with-word/working-with-bibliographies)、[LibreOffice CITATION 指令](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/source/filter/ww8/ww8atr.cxx#L3221-L3229)及[导出缓存](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/source/filter/ww8/docxattributeoutput.cxx#L3390-L3394)。未复制上游执行代码。

### DOCX 书目

资料来源面板支持书目标题、生成、显式更新和删除。`DocumentEditor.sources.insertBibliography(sourceCatalog, title)` 在当前普通正文段落前插入书目；`editBibliography(sourceCatalog, {action:"update"|"delete", paragraph})` 操作完整生成结果。来源目录 `DocxSources` 现在同时包含必需的 `bibliographies` 数组，各项为 `paragraph/endParagraph/instruction/reason`。旧文档或 revision 的目录被拒绝后仍可编辑。同步/Worker 使用 `editBibliography(revision, change, profile)`，插入命令为 `{action:"insert", title}`；原生入口为 `Session::edit_bibliography` 和 `BibliographyFieldEdit`。

核心按存储顺序列出原生 `CITATION` 引用的来源，同一标签只生成一条记录。简单域、跨 run 复杂域和普通表格引文共用既有有界来源扫描；普通文字中的标签不算引用。未引用的来源保留原文，不生成条目；未知类型和扩展作者也不影响无关书目。基础文字依次为“作者. (年份). 标题. 出版商或刊物. 网址”，空字段省略；不声明完整 APA/MLA 排版。每条记录生成一个原生段落，保留已有 `Bibliography` 样式或创建继承正文的同名样式。新建书目使用 `BIBLIOGRAPHY` 域和 `Bibliographies` 内容控件，并在域前放置用户指定标题。标题沿用标题样式及基础加粗字号，不进入自动编号或标题目录。

读取支持普通正文跨段字段，以及一层标准 `Bibliographies` 控件和可选普通标题。接受无开关或仅 `\* MERGEFORMAT`；其他开关、绑定、锁定及未知结构保持保护。显式更新只替换字段结果段落，保留原控件包装、标题、样式和源记录。删除有控件时移除整个控件及标题，无控件时移除字段结果。来源记录、原生引文及其他部件保留；来源修改、保存和输出不会自动更新书目或引文缓存。没有被引用来源时保留可继续更新的占位结果。新增或删除引文后显式更新，按当前引用重建结果。

生成、更新和删除复用目录的资源、布局、选择及精确历史事务。生成结果保持直接输入保护，TOC、INDEX 和书目操作按字段类型校验；无变化更新不新增历史。失败保留包、选择及重做。标题为 1–255 个 UTF-16 单元，来源最多 512 条，书目目录最多 256 项，生成文字总量最多 1048576 单元，并受既有包、历史和布局预算限制。被引来源缺失、归属不明、类型未知或作者不支持时拒绝整项生成，避免静默遗漏。当前创建/更新沿单节普通正文边界。

原生入口与基础文字归 [bibliography-field.mbt](../../../modules/formats/src/docx/bibliography-field.mbt)，共用生成事务归 [toc-edit.mbt](../../../modules/formats/src/docx/toc-edit.mbt)，控件验证归 [toc-control.mbt](../../../modules/formats/src/docx/toc-control.mbt)，宿主命令归 [document-sources.ts](../../../packages/docx/src/web/document-sources.ts)，默认控件归 [docx-bibliography.tsx](../../../packages/docx/src/react/docx-bibliography.tsx)。原生结构依据 [LibreOffice 书目导出](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/source/filter/ww8/ww8atr.cxx#L2480-L2483)及 [Bibliographies 控件检查](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/qa/extras/ooxmlexport/ooxmlfieldexport.cxx#L352-L361)。引用收集另参考 [LibreOffice UpdateAuthorities](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/source/core/doc/doctxm.cxx#L1681-L1714)；创建及新增引用后的显式更新与 [Word 书目流程](https://support.microsoft.com/en-us/word/training/create-a-bibliography-citations-and-references)一致。完整引用样式、自动更新及更广导入继续实施。未复制上游执行代码。

### DOCX 题注目录

`DocumentEditor.pages.insertTableOfFigures(sequence)` 在当前普通正文段落前生成题注目录。同步/Worker 沿 `editTableOfContents(revision, {action:"insertCaptions", sequence}, profile)`，原生入口为 `InsertCaptionToc(sequence)`。序列标签采用既有 SEQ 标识符规则，最多 40 个 UTF-16 单元，接受中文。默认目录面板可选择标题级别或题注来源，并输入序列标签；已有条目沿原目录的更新和删除入口操作。查询中的题注目录附有可选 `sequence`，级别固定为 1–1。

原生代码为 `TOC \c "Figure" \h \z`。核心按文档顺序收集具有相同 SEQ 标识符的正文和普通格段落，每段一项，排除已有生成结果。条目取当前显示的完整题注，包括章节前缀、编号和说明；普通标题和其他序列不进入该目录。受支持的简单域和同段复杂 SEQ 均可读取，原指令及旧缓存保持原样。复用可用的段首书签，缺失时创建点书签；当前真实页号和内部链接共用既有 PAGEREF 与 PDF 输出。复杂域正文仍保持原有编辑保护。

已有 `TableofFigures` 或英文名 `table of figures` 的样式保持原源；没有时创建继承默认正文、段后间距为零的原生样式。生成、显式整体更新、删除、无变化处理、八轮重排、字体/资源预算、选择及精确历史复用目录事务。删除保留原题注与锚点；无匹配项时保留可更新的空题注目录。保存与输出不自动刷新源题注缓存。

读取接受 `\c` 及已有 `\h/\z/\u`，拒绝与 `\o` 混用或重复开关。`\a` 仅说明文字、浮动题注框、混合来源、自定义分隔符和更广内容控件继续实施；生成位置仍沿单节普通正文范围。读取归 [toc-read.mbt](../../../modules/formats/src/docx/toc-read.mbt)，条目与原生源归 [toc-source.mbt](../../../modules/formats/src/docx/toc-source.mbt)，事务归 [toc-edit.mbt](../../../modules/formats/src/docx/toc-edit.mbt)，严格接口归 [docx-toc.ts](../../../packages/docx/src/core/docx-toc.ts)，默认面板归 [docx-toc.tsx](../../../packages/docx/src/react/docx-toc.tsx)。依据 [ONLYOFFICE 题注收集与目录生成](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L950-L1058)、[原生指令](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L485-L491)及[默认样式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L7024-L7061)。未复制上游执行代码。

### 原生目录内容控件

正文顶层的标准 `w:sdt` 目录已有显示、整体更新与删除。核心验证 `sdtPr/docPartObj/docPartGallery` 为原生 `Table of Contents`，内容仅含受支持 TOC 和可选的单个普通 `TOCHeading` 标题段落。目录标题与缓存段落进入同一布局、页码和 PDF 路径，保持普通输入保护。现有目录查询、同步/Worker API 和默认面板直接操作其字段身份，无新增接口。

整体更新只替换字段段落，原样保留标题、包装、alias/tag/id 和已知末尾文字格式。删除移除整个目录控件与标题，保留正文标题及目标书签；控件为唯一正文内容时留下普通空段落，继续原生输入。两项操作共用已有候选校验、预算和精确历史；无变化不增加历史，保存重开仍可更新。

未知属性、数据绑定、锁定、嵌套控件、其他图库、额外内容及带书签等锚点的目录标题继续保护；普通标题编辑、通用内容控件、表格内目录及复杂导入变体继续实施。实现归 [`toc-control.mbt`](../../../modules/formats/src/docx/toc-control.mbt)及既有目录读写。原生图库身份依据 [ONLYOFFICE IsBuiltInTableOfContents](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/StructuredDocumentTags/SdtBase.js#L992-L995)，标题和字段归属依据 [ONLYOFFICE 目录创建](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L24612-L24641)。未复制上游执行代码。

### 书签页码引用

`DocxBodyField` 增加 `{ field: "PAGEREF", bookmark: string, format?, hyperlink?: boolean, relative?: boolean }`，从 Wasm/Web foundation 导出，沿现有 `insertBodyPageField`、`bodyPageField` 和 `editBodyPageField` 使用。默认正文域面板提供目标书签输入、插入、读取及修改。名称沿当前书签创建规则，最多 40 个 ASCII 字母、数字或下划线，首字符不是数字；创建和修改目标时必须存在可用书签。

正文及普通单元格中，核心按书签起点所在的实际纸张计算页号，采用当前单节编号或显式格式。简单域可插入、查询、修改、原生输入及整域替换；已知同段复杂域可显示和刷新，范围编辑保持保护。书签改名只修改已知简单域的目标 token，保留空白、格式开关及 `MERGEFORMAT`。删除或缺少目标时，显示 `Error! Bookmark not defined.`；原缓存仍由 `updateBodyPageFields` 显式刷新。源、选择和缓存共用既有精确历史，计算、保存和输出不隐式改写原缓存。原生格式依据 [ONLYOFFICE PAGEREF](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1259-L1312)。

`relative: true` 保留原生 `\p` 开关。同页按实际光标位置显示 `above` 或 `below`；跨页显示 `on page N`，其中 N 是从 1 开始的物理页号，不使用节编号格式。`hyperlink: true` 保留原生 `\h` 标记，默认面板通过“跳转到引用目标”显式定位已提交的目标。修改目标后须先应用，再跳转。PDF 输出保留此目标，范围归[PDF 文字链接](docx-content.md#docx-pdf-文字链接)。

`Flow.bookmarks` 保存忽略大小写的名称到 `[startParagraph, startOffset, endParagraph, endOffset]` 的范围绑定；页码与链接定位使用前两项，TypeScript 只验证传输。最多 4096 个目标与字段位置；一次分页轮次最多访问 1048576 个候选行和光标位置，沿用最多八轮重排。普通字段片段保留原生目标名，在目标文档中重新绑定；不会复制范围外的书签，缺失时显示上述错误。重复表头中的相对引用、未知或重复开关保持诊断和编辑保护。页眉页脚、未知/受保护目标、其他引用变体和目录继续实施。实现归 [`body-page-reference.mbt`](../../../modules/formats/src/docx/body-page-reference.mbt)及[字段布局](../../../modules/layout/src/body-fields.mbt)，未复制上游执行代码。

### 书签文字引用

`DocxBodyField` 接受 `{ field: "REF", bookmark: string, hyperlink?: boolean, numbering?: "noContext" | "relative" | "fullContext", relative?: boolean, separator?: string }`，沿现有正文域插入、查询与修改 API 使用。名称沿书签规则，创建和修改时须存在可用目标。默认正文域面板提供文字/页码引用选择、目标、三种编号模式与相对位置开关、插入、读取、修改及显式跳转。省略 `numbering` 时引用书签文字；REF 不接受页码格式。

当前支持正文或普通单元格内、同一段落中的书签文字范围。原生指令为 `REF name [\h] \* MERGEFORMAT`，保留结果 run 的字符格式。普通文字按逻辑边界截取，目标内的 PAGE、NUMPAGES、PAGEREF、NOTEREF、SEQ 使用当前计算值，嵌套 REF 按依赖计算；一个域仍占一个逻辑位置。缺少目标时显示 `Error! Reference source not found.`。已知简单域随书签改名更新目标 token；原生输入、格式和富文本片段沿既有事务维护。布局、保存及 PDF 不改写缓存，显式刷新合为一项精确历史。`hyperlink: true` 保留原生 `\h`，默认控件显式跳转，PDF 输出内部目标。

`numbering: "noContext"` 引用书签起始段落的当前编号，原生写为 `REF name \n [\h] \* MERGEFORMAT`，导入时也接受未带 MERGEFORMAT 的编号引用。目标可跨段，结果只读取起始段落的列表计数，不复制书签内容。编号保留前缀、中间分隔符及所有编号占位符，只省略末尾一个文字字符；例如 `(%1)` 得到 `(1`，`%1.%2)!` 得到 `1.a)`。普通段落及项目符号列表返回 `0`。列表格式和起始值修改后重算，显式缓存、书签改名、剪贴板和内部链接沿同一事务。每级编号文本最多 256 个 UTF-16 单元。依据为 [ONLYOFFICE 编号引用](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1529-L1594)、[末尾文字规则](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/Num.js#L725-L754)及[文字字符拆分](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/NumberingLvl.js#L1093-L1127)。

`numbering: "relative"` 写入 `\r`。当字段与目标属于同一编号实例时，逐级比较计数并省略共同的上级文本；相同级别及计数返回空结果。其他实例或普通段落使用目标当前级文本。`numbering: "fullContext"` 写入 `\w`，从第一级连接到目标级的原生编号文本，仅目标级省略末尾文字字符。例如三级模板 `%1.`、`%2)`、`[%3]!` 的完整结果为 `1.a)[I]`；第二级中的相对引用为 `[I]`。三种模式互斥，重复或混用的原生开关继续保护；缺少所需上级定义或其模板未支持时保留旧缓存并诊断，无上下文引用仍可使用。依据为上述 [ONLYOFFICE 相对与完整编号分支](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1541-L1577)。

`separator` 写入原生 `\d "text"`，只在完整编号的相邻级文本间插入，保留上级原有标点。例如 `separator: " / "` 得到 `1. / a) / [I]`。默认完整编号控件提供输入和清除；切换其他引用模式保留元数据，显示不使用分隔符。支持引号内空格、转义引号、Unicode、冒号和内部反斜杠，最多 32 个 UTF-16 单元；空值清除开关。控制字符、换行及首尾反斜杠拒绝，避免产生无法原生往返的指令。源中的缺少参数、引号未闭合或重复开关继续保护。依据为 [ONLYOFFICE 完整编号连接](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1562-L1574)和[原生引号读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L1488-L1522)，实现归 [`text-reference-instruction.mbt`](../../../modules/formats/src/docx/text-reference-instruction.mbt)。

`ParagraphMarker.numbering` 提供编号实例、是否为数值编号、当前级以内的计数快照及逐级文本；缺少的级文本为 `null`。最多九级，完整结果及比较工作沿用字段预算。元数据用于核心引用计算，TS 只校验传输。实现归 [`number-reference.mbt`](../../../modules/layout/src/number-reference.mbt)及[列表计数](../../../modules/formats/src/docx/numbering.mbt)。

`relative: true` 写入原生 `\p`，按正文与表格的文档顺序比较书签起点和字段位置，显示 `above` 或 `below`；跨页和 RTL 不改为视觉坐标判断。单独启用时只显示位置；与编号组合时显示如 `1 below`，普通段落及项目符号仍只返回 `0`。跨段书签和包含自身的位置引用不遍历目标内容，不产生文字依赖循环。导入允许不带 MERGEFORMAT 的位置引用，新建和修改保留既有结果格式。改名、富文本粘贴后的位置重算、显式缓存和精确历史沿用原路径；缺少目标仍显示同一错误。规则依据 [ONLYOFFICE REF 文档位置比较](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1364-L1416)及[编号与位置组合](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1524-L1590)。

文字结果最多 4096 个 UTF-16 单元，依赖深度最多 64，单轮查询工作量最多 1048576。循环、无效依赖、跨段文字目标、绘图或换行/控制字符保留各域原缓存并给出布局诊断，阻止不确定的刷新和输出。仍沿用正文域数量、八轮分页、字体、历史及输出预算。跨段及多行内容、未带 MERGEFORMAT 的目标格式复制、其他开关和完整 REF 创作继续实施；未知指令保留源并保护。实现归 [`text-reference.mbt`](../../../modules/layout/src/text-reference.mbt)、[书签源事务](../../../modules/formats/src/docx/body-page-reference.mbt)与[字段指令](../../../modules/formats/src/docx/running-fields.mbt)。行为依据 [ONLYOFFICE REF 与结果格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1417-L1495)及[目标内容和错误](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1496-L1595)，未复制上游执行代码。

### 脚注与尾注编号引用

`DocxBodyField` 接受 `{ field: "NOTEREF", bookmark: string, hyperlink?: boolean, relative?: boolean, superscript?: boolean }`，沿既有正文域插入、读取、修改与刷新入口使用。默认面板提供注释引用类型、目标书签、链接、上下位置和注释编号格式开关。普通书签可包围已支持的注释标记；创建、改名、删除及跳转复用原书签事务。

核心按正文和普通单元格的文档顺序，读取目标范围内第一处脚注或尾注标记的当前标签。目标可以跨段，并可包含多个注释；新增或删除较早的注释后，引用随原注释编号重算。书签缺失或范围内没有注释时显示 `Error! Bookmark not defined.`。此行为依据 [ONLYOFFICE NOTEREF](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1596-L1671)，实现归 [`note-reference.mbt`](../../../modules/layout/src/note-reference.mbt)。普通文字 REF 遇到真正的注释标记仍保留缓存并诊断，避免把注释语义降为普通文字。

原生 `\p` 对应 `relative`，仅显示书签相对字段的 `above/below`，按文档顺序及同段逻辑位置判断。`\f` 对应 `superscript`，编号沿既有字体上标规则绘制；与 `\p` 同用时保留开关，位置文字使用原结果格式。`\h` 对应 `hyperlink`，复用显式书签跳转和 PDF 内部链接。指令读取与写回沿 [ONLYOFFICE 开关解析](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L1855-L1889)；未知、重复开关及编号格式开关继续保护。内部代码为 `NOTEREF:name[:superscript][:hyperlink][:relative]`。

注释标签在分页前有界求值，保留字段结果格式与单个逻辑位置。缓存刷新、所选域修改、书签改名及普通富文本片段沿同一精确历史；布局和 PDF 不修改缓存或注释资源。目标范围查找最多访问 1048576 个候选，沿用字段、注释、字体与输出预算。页眉页脚及注释正文中的字段、复杂域范围编辑和其他未知内容仍按原边界保护。

### 序列编号字段

`DocxBodyField` 接受 `{ field: "SEQ", sequence: string, format?, restart?: number, repeat?: boolean, headingLevel?: number, hidden?: boolean }`，沿现有正文域插入、查询和修改 API 使用。默认正文域面板提供序列名称、计数方式、起始值、隐藏、插入、读取和修改控件。名称区分大小写，最多 40 个 UTF-16 单元；首字符为下划线或 Unicode 标识符起始字符，后续允许标识符续字符。每个名称独立从 1 计数，按正文与普通表格单元格的源顺序递增，不依赖 XML 节点编号或节页码。缺省格式为十进制，显式格式支持 `decimal/lowerLetter/upperLetter/lowerRoman/upperRoman`。

`restart` 为 0–2147483647 的整数，将当前域设为该值，后续同名域继续递增。`repeat: true` 显示最近的同名编号，不推进计数；前面没有同名编号时显示初始值 1。两项不能同时启用，`repeat: false` 等同默认递增。查询返回实际启用的属性；修改为普通递增时省略两项。核心使用 64 位计数，最大起始值之后仍可继续递增。开关读写依据 [ONLYOFFICE SEQ 解析](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L1941-L1993)，重新起算后的递增及最近编号语义依据 [Microsoft SEQ 定义](https://support.microsoft.com/en-us/word/field-codes-seq-sequence-field)。

`headingLevel` 为 1–9 的整数。当前域从最近的同级或更高层标题后重新计数，未出现对应标题时沿普通编号链计算。可与重复或显式起点组合；重复保持该标题范围的前值，显式起点优先。默认面板可设置或清除标题级别，切换计数方式或修改起点保留该设置。原生指令使用 `\\s n`，无效或重复级别保持源保护。标题来自有效大纲级别，复用文档默认值、样式继承及段落覆盖；普通表格内标题也按源顺序参与。`Flow.outlineLevels` 为必需的段落身份到 0–8 级别映射，省略正文段落并在无标题时返回空对象；数字键来自段落身份。核心按有界前缀计算混合编号，不使用递归，最多 1048576 个求值步骤及 40960 项缓存。样式修改更新显示，显式缓存和精确历史沿原事务。标题范围规则依据 [ONLYOFFICE 标题边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L819-L862)，常量指令语义归上述 Microsoft 定义，实现复用[有效大纲级别](../../../modules/formats/src/docx/outline-level.mbt)及[正文流](../../../modules/formats/src/docx/flow.mbt)。

原生指令为 `SEQ name`，接受上述编号格式开关、`MERGEFORMAT`、重新起算 `\r n`、重复 `\c` 、显式递增 `\n` 及标题重启 `\s n`。递增/重复/起点开关互斥，可与格式开关交换顺序；无效起始值、重复及冲突开关保持诊断和源保护。已知简单域和同段复杂域参与计算；简单域复用原生输入、格式修改、完整域剪贴板及一个逻辑位置。复杂域范围仍保护。新增、修改或粘贴只写当前域的实际缓存，其他域实时重算显示；`updateBodyPageFields` 显式刷新全部结果缓存，合为一项精确历史。布局、保存和 PDF 不隐式改写缓存。同名书签的改名不改变已知简单 SEQ 的序列名称。

`hidden: true` 写原生 `\h`，保留计数、重启和重复规则，结果显示为空。字段仍占一个逻辑位置，保留格式及完整富文本复制；缓存刷新写空结果，Canvas/PDF 不绘制编号。查询只返回有效的隐藏状态。沿 [ONLYOFFICE 隐藏规则](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L791-L816)，导入的 `\h` 遇到通用格式开关（包括 `MERGEFORMAT`）时仍显示，读取和保存保留原指令。API 中有效隐藏不能与显式 `format` 同时设置；默认面板勾选隐藏时清除待提交格式并禁用格式选择，修改已有域时也不保留会抵消隐藏的 `MERGEFORMAT`。取消隐藏后恢复默认十进制，再可选择显式格式。创建、修改、原生相邻输入、空结果复制、精确历史、重开及静态输出沿既有事务。

沿用每段 64 个字段、正文 4096 个字段位置及原有分页、字体、XML、历史和输出预算。当前范围为正文及普通单元格；页眉页脚及书签形式引用继续实施；题注创作归下文[DOCX 题注](#docx-题注)。未知指令和开关保留源、给出诊断并保护编辑。实现归[序列计算](../../../modules/layout/src/sequence-field.mbt)、[正文顺序](../../../modules/layout/src/body-fields.mbt)、[指令读取](../../../modules/formats/src/docx/running-fields.mbt)及[缓存和代码事务](../../../modules/formats/src/docx/body-field-edit.mbt)。依据 [ONLYOFFICE SEQ 指令](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L707-L756)、[正文计数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L789-L875)及[名称比较](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L906-L913)，未复制上游执行代码。

### DOCX 脚注与尾注内容

`DocumentEditor.review.notes()` 返回 `DocumentNotes = { documentId, revision, entries, endnotes }`。每项包含 `{ kind: "footnote" | "endnote", id, text, reason, references }`；id 是所属种类内的原生十进制身份，返回为 0–2147483647 的规范字符串。references 是正文中同类、同身份引用的数量，保留原 XML 中的身份写法。分隔符不进入普通目录；孤立内容仍可读取，缺失内容的引用返回受保护占位项。默认页面面板提供目录读取、内容选择与文字修改，复杂内容显示保护说明。

`endnotes` 是必需的文档设置 `{ position: "docEnd" | "sectEnd" | null, reason: string }`。已支持且未保护的设置返回位置和空 reason；无法读取或受保护时返回 null 与原因，普通内容目录仍可读取。`DocumentEditor.review.setEndnotePosition(source, position)` 绑定目录的文档身份和 revision，默认注释面板在读取目录后提供“尾注位置（整篇文档）”控件。同步与 Worker 客户端提供 `setEndnotePosition(revision, position, profile)`；`DocxEndnotePosition` 从 Wasm/Web foundation 导出，Wasm foundation 导出 `checkEndnotePosition`。核心只修改文档设置 `endnotePr/pos`，保留编号、起始值、重启方式、节内元数据和目标外原源；相同有效位置不新增历史。缺失设置部件及关系沿既有多部件事务创建，字体和完整候选布局在提交前检查；保护、过期、不透明目标或预算失败保留源与历史。依据 [ONLYOFFICE 全局尾注位置修改](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L19198-L19247)，实现归[尾注位置事务](../../../modules/formats/src/docx/notes-position.mbt)。

`DocumentEditor.review.editNote(source, { kind, id, text })` 绑定目录的文档身份和 revision，替换普通注释的多段文字，LF 表示段落边界，保留首尾空段。允许空文字，含 LF 最多 32767 个 UTF-16 单元；CR、Tab 和其他控制字符继续拒绝。默认创建和修改控件使用多行输入。同步 `FoundationSession` 和 Worker `FoundationClient` 提供 `execute({ operation: "notes", revision })`、`execute({ operation: "editNote", revision, note, profile })`；宿主沿用当前布局的字体映射。`DocxNotes`、`DocxNoteKind`、`DocxNoteEdit` 从 Wasm/Web foundation 导出，结果解码和编辑校验从 Wasm foundation 导出。可排版注释在提交前检查候选布局，缺字体、布局或资源预算失败保留原源和历史。过期目录、队列内的同源竞争及受保护目录查询保持当前会话可继续使用。

`DocumentEditor.review.noteNumbering(kind, section)` 查询从 0 开始的指定节，返回 `{ documentId, revision, kind, section, value, reason }`。可编辑 value 为 `{ format, start, restart }`；格式使用已有的 `decimal/decimalZero/lowerLetter/upperLetter/lowerRoman/upperRoman`，start 为 0–4294967295 的整数，restart 为 `continuous`、`eachSect`，脚注还支持 `eachPage`。保护或不支持的原生设置返回 null 与原因。`setNoteNumbering(source, value)` 绑定查询的文档、revision、种类和目标节；同步/Worker 客户端提供 `noteNumbering(revision, kind, section)` 和 `setNoteNumbering(revision, kind, section, value, profile)`。`DocxNoteNumbering`、`DocxNoteNumberingValue` 从 Wasm/Web foundation 导出，`noteNumberFormats` 为共用格式清单；Wasm foundation 导出解码和校验。默认页面面板复用所选节，提供独立编号读取与修改。连续编号按当前节的 start 加上此前同类引用数；每节或每页重新编号从 1 开始，保留原生 start 并禁用其输入。只修改有效值发生变化的属性，保留位置、其他种类/节、未改字段的继承和目标外注释。缺失节及属性沿原源事务创建；字体和完整候选布局检查后提交一项精确历史。依据 [ONLYOFFICE 脚注编号修改](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L19006-L19052)、[尾注编号修改](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L19198-L19247)、[脚注计数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Footnotes.js#L548-L617)和[尾注计数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Endnotes.js#L318-L377)。实现归[注释编号事务](../../../modules/formats/src/docx/notes-numbering.mbt)。

`DocumentEditor.review.insertNote({ kind, text })` 在当前选区按文档顺序的末尾插入引用，保留所选文字。`text` 采用上述多段文字限制，可为空。正文和普通表格使用同一源插入入口，引用保留附近 run 属性并设为上标。已有 FootnoteText/EndnoteText 样式继续使用；没有时新增内容采用 10 pt 文字与普通段落。缺少内容部件时创建原生关系、内容类型、正文标记及默认分隔符，已有部件只追加新内容。身份避开已有内容、特殊注释及正文引用。资源和正文共用一项精确历史，光标留在正文引用之后，面板自动选中新内容。

`DocumentEditor.review.removeNote(source, { kind, id })` 删除目录中的普通内容及其至多一个正文引用，保留其他内容、源格式、分隔符和部件关系。重复引用、其他 Word 内容区域中的引用、结构化或不透明内容继续保护。命令后选区回到原引用位置；撤销恢复内容、资源和原选区。最后一个引用删除后，该段落可继续普通输入。空部件继续保留，避免清理其他源数据。孤立普通内容允许从目录删除。

同步和 Worker 客户端分别提供 `insertNote(revision, note, profile)`、`removeNote(revision, note, profile)`，返回现有编辑状态。`DocxNoteCreate`、`DocxNoteIdentity` 从 Wasm/Web foundation 导出；`checkDocxNoteCreate`、`checkDocxNoteIdentity` 从 Wasm foundation 导出。创建/删除执行完整候选布局、文档保护、资源及历史预算检查，拒绝后会话可继续使用。正文中的普通引用占一个逻辑位置。原生文字输入、同一容器内的范围替换、拆段/合并和删除键保留引用源；新文字使用基线格式。删除唯一引用时，普通注释内容沿同一事务和精确历史删除。组合输入预览同步隐藏已删除引用的内容，取消恢复原源，提交只记录最终文字。复杂内容、重复引用及其他 Word 区域共享的引用保持删除保护。普通正文和所选单元格的字符、段落及列表格式已接通既有命令和默认控件。引用参与有效格式及混合查询，所选范围沿原 run 边界拆分，保留注释身份和内容部件。折叠处的待输入格式随实际文字提交，邻接引用的新文字保持基线。含引用的整格选择沿用矩形高亮、混合查询和底色等共用属性事务。原生输入及组合提交只替换首格，删除清空全部所选格；注释内容清理、预览取消及精确历史采用同一归属检查，范围外内容保持。含引用格的行列增删、合并/取消合并、拆格、尺寸、自动适配和拆表已接通既有命令与默认控件。移动保留原引用和内容，新空格清除仅属引用的样式与上标。删除格或最后一行时，普通内容随同一事务清理，结构化内容仍原子拒绝；撤销/重做精确恢复正文、资源和选择。含引用的正文位置已支持新建表格，拆段保留两侧引用，覆盖范围同步清理普通内容。新空格继承当前位置的基线与待输入格式。搜索在正文和普通格中将引用计为一个逻辑对象，保留后续文字偏移，不跨过引用匹配相邻文字；匹配选择及普通、跨段、批量替换复用同一源与资源历史。正文搜索不包含注释内容区域。引用旁的折叠光标查询与实际输入均清除仅属引用的样式和上标，显式待输入格式继续生效。注释区域光标继续实施。

普通单段或多段文字注释已随正文、单格范围及单元格矩形的富文本片段复制、剪切和粘贴。纯文本输出当前显示编号；原生片段携带注释内容、原生标记及解析后的字符/段落格式，保留混合文字样式。目标文档分配独立身份，创建或复用内容部件、关系、内容类型和默认分隔符；重复粘贴不共享内容。覆盖目标引用时同步删除其原内容，正文与资源合为一项精确历史。复制和资源预检不修改源，剪切先检查内容归属，并沿既有系统剪贴板写入成功后的删除入口。无内容的裸引用、错误标记、未知种类和缺字体拒绝粘贴；列表、结构化或不透明注释继续保护。默认 Copy/Cut、保留源格式粘贴及原生快捷键复用[正文富文本片段](docx-tables.md#正文富文本片段)，实现归 [`notes-clipboard.mbt`](../../../modules/formats/src/docx/notes-clipboard.mbt)。单元格片段也支持覆盖原引用和扩展目标网格。TSV 写入普通文字时，即使显示值与原编号相同，也会移除被覆盖的引用及其普通内容；原生片段则分配独立身份。含注释的表格布局预检保留整个文档及其注释区域。注释内容独立复制参考 [ONLYOFFICE FootnoteReference.Copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/RunContent/FootnoteReference.js#L108-L126)。

核心按原生关系查找内容部件，修改目标文字节点，保留正文引用、注释标记、段落/run 属性、源注释、分隔符和其他部件；新文字首尾空白显式保存。空段落在原位置新增普通文字 run。按 LF 保留或增删段落；新增段落继承最后文字 run 和段落属性，不复制段落源身份。仅有编号标记时，新文字清除标记专属样式与上标。原生标记必须唯一并位于首段。一次实际修改只记一项精确历史，无变化保持源和 revision；撤销/重做恢复原部件与选择。字段、其他结构、正文内未知标记、文字节点内不透明源及跟踪属性继续保护；外部/共享部件、重复身份及无效 XML 身份拒绝操作。每类最多 4096 项内容和 1048576 个文字单元，合并目录最多 8192 项，沿用 XML、历史及输出预算。

已有普通文字脚注和尾注已接入单栏、多栏及多节核心布局。正文和普通表格中的引用占一个逻辑位置，按所属节的原生格式和起始号显示；连续编号按同种注释的全文计数加当前起号，每节重启 `eachSect` 从 1 起算。编号设置的修改命令仍待接入。脚注按引用行预留页底空间，空间不足时移动引用，长文字可继续到后续节；纸型或边距改变时，剩余文字按新宽度从原逻辑偏移重排，保留编号、格式和独立身份。正文与续排脚注共用预留空间，空末节也可承接未完文字。

等宽和不等宽分栏使用所在栏的宽度与横坐标排脚注。正文与脚注在同栏预留空间，页底模式使用物理页边界；长脚注从原段落偏移继续到下一栏、下一页及下一节，保持编号、格式、文字与只读区域。含引用的可整体放置表格行组沿同一规则。末页平衡包含脚注，不增加物理页或向后节推迟更多未排文字；分栏符按原规则移动正文，页眉页脚与总页数按物理页计算。默认分栏表单提交与所示末栏剩余宽度一致，显式 SDK 原生宽度元数据仍保留。实现归 [栏分页](../../../modules/layout/src/columns.mbt)、[注释续排](../../../modules/layout/src/notes-continuation.mbt)及[注释布局](../../../modules/layout/src/notes.mbt)，依据 [ONLYOFFICE 逐栏脚注](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Footnotes.js#L272-L440)、[栏边界与平衡](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Layout/PrintView.js#L83-L138)和[物理栏底定位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L4394-L4410)。未复制上游执行代码。

脚注位置读取文档 `footnotePr/pos`，各节可独立覆盖；默认 `pageBottom` 使用物理页底，`beneathText` 紧随所在栏的正文或表格结束位置。原生脚注 `sectEnd` 和 `docEnd` 按主参考解释为 `beneathText`，保留原 XML。`DocxFlow.footnotesAt` 和各 `DocxSectionBreak.footnotesAt` 是必需字段，统一为 `"pageBottom" | "beneathText"`；MoonBit 与 TypeScript 均拒绝其他值或缺失字段。跨节续排采用当前节的位置和栏宽，空白续栏从该栏顶部开始；两种位置共用预留、页数、末页平衡及既有内容编辑事务。紧随正文使用实际分页游标，包含表格高度、尾注及段后间距，并限制在已预留的页底以内。默认页面面板已接通所选节的脚注位置修改。`setPageSetup({ ...page, footnotesAt })` 使用归一化的 `pageBottom` 或 `beneathText`，沿现有队列、保护、输出预算和精确历史提交；省略该项保留原生位置及继承，相同有效值不新增历史。只改变位置时保留编号、起始值、注释内容、纸型与其他节。缺失节或 `footnotePr` 沿同一事务创建，已有编号和目标属性外的注释保留；不透明目标属性保持保护。实现归 [注释设置](../../../modules/formats/src/docx/notes-settings.mbt)、[逐节模型](../../../modules/formats/src/docx/flow-sections.mbt)与[布局定位](../../../modules/layout/src/notes.mbt)，依据 [ONLYOFFICE 脚注位移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L4394-L4410)和[实际栏结束位置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L4251-L4253)及[逐节位置修改](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L19006-L19052)，未复制上游执行代码。

脚注 `eachPage` 按引用实际所在物理页重新编号，同页多栏、正文与普通表格按原生文档顺序共用计数。普通续排不会把上一页的编号带到新页；若一条脚注完全推迟到紧邻的下一页才开始，则该页后续新脚注接着编号，沿主参考避免两个不同内容共用标签。正文引用、注释标记和 NOTEREF 在既有八轮上限的字段分页中共同更新，语义内容及 Canvas/PDF 使用最终标签，保存不写回派生编号。尾注不接受 `eachPage`。普通正文域仍限 4096 项，动态脚注另沿既有 8192 项注释上限；页查找最多 1048576 步。实现归[每页脚注编号](../../../modules/layout/src/page-note-numbering.mbt)及[编号解析](../../../modules/layout/src/body-fields.mbt)，依据 [ONLYOFFICE 每页脚注计数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Footnotes.js#L548-L602)。

尾注按文档设置 `endnotePr/pos` 进入 `docEnd` 文末或 `sectEnd` 节末；默认文末，节内 `pos` 元数据不覆盖文档设置。`DocxFlow.endnotesAt` 是必需字段，取这两个原生值。正文与页眉页脚的 PAGE、NUMPAGES 使用包含注释页的最终页数，跨节 NOTEREF 使用所属注释的当前标签。节末段落中的有效书签可读取和定位，段落文字编辑仍受结构保护。各类字段保持一个逻辑位置，不能把展开的显示文字当成多个正文位置。注释复用字体、段落测量及输出管线，进入实际 Canvas、语义内容及 PDF。编号和分页为派生结果，保存不改写原 XML。

尾注接在文末或所属节正文之后，按所在等宽/不等宽栏的实际宽度连续排段。它与正文共同参与最后一页平衡，并避开同栏已预留的脚注区域；只有尾注的栏仍显示所选栏分隔线。多段尾注在整组排完前保留实际占位，后续段落继续到下方或下一栏，避免重置到栏顶重叠。编号、原生 XML、文字修改、历史、保存重开及 Canvas/PDF 继续使用同一份文档状态。依据 [ONLYOFFICE 尾注逐栏续排](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Endnotes.js#L417-L545)及[节末尾注与平衡](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L4100-L4134)，实现归 [注释布局](../../../modules/layout/src/notes.mbt)和[栏分页](../../../modules/layout/src/columns.mbt)。未复制上游执行代码。

实现归[原生注释设置](../../../modules/formats/src/docx/notes-settings.mbt)和[跨宽度续排](../../../modules/layout/src/notes-continuation.mbt)。连续与每节重启依据 [ONLYOFFICE 脚注编号](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Footnotes.js#L549-L674)及[尾注编号](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Endnotes.js#L315-L374)；默认文末位置依据[原生默认值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/sections/footnote-pr.js#L50-L63)，未复制上游执行代码。

`DocxFlow.notes` 是必需数组，每项为 `{ kind, key, paragraph, node, numbering, content }`。numbering 为必需的 `{ format, value, restart, marker }`；value 是布局前的派生序号，marker 标识注释故事中的原生编号节点。原生 start 保持 uint32 上限，连续递增的派生序号可再加此前最多 8191 项引用，使用原有格式化规则。paragraph、node 定位正文引用，content 使用独立的负段落身份和只读区域，避免与正文和页眉页脚源节点混淆。内容面板继续按种类和身份修改文字，画布中的注释区域暂不提供原生光标输入。含注释的页面重排暂不复用整页缓存，段落测量继续复用。最多 8192 项注释，沿用 1024 页、32768 行与字体/XML/输出预算。

当前支持普通文字段落及可整体放置的含脚注表格行组。超高含脚注行组的分片预留、注释内部的表格/对象/域、链接/审阅锚点、自定义引用标记和分隔符均待接入，不能解释时保留诊断或拒绝布局。复杂段落保持规则和完整分隔符保真仍待实现。注释区域光标及内容的富文本编辑继续按 P10 实施，不标记脚注功能或阶段完成。实现归 [`notes-read.mbt`](../../../modules/formats/src/docx/notes-read.mbt)、[`notes-edit.mbt`](../../../modules/formats/src/docx/notes-edit.mbt)、[`notes-create.mbt`](../../../modules/formats/src/docx/notes-create.mbt)、[`notes-remove.mbt`](../../../modules/formats/src/docx/notes-remove.mbt)、[`notes-layout.mbt`](../../../modules/formats/src/docx/notes-layout.mbt)、[`布局预留与续排`](../../../modules/layout/src/notes.mbt)和 [`docx-notes.tsx`](../../../packages/docx/src/react/docx-notes.tsx)。原生内容区域参考 [ONLYOFFICE FootEndnote](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/FootEndnote.js#L49-L69)，跨页续排参考 [ONLYOFFICE Footnotes](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Footnotes.js#L272-L351)，保留所选文字的插入行为参考 [ONLYOFFICE AddFootnote](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L18859-L18904)。

### DOCX 题注

`DocumentEditor.pages.insertCaption(caption)` 与同步 `FoundationSession`、Worker `FoundationClient.execute({ operation: "insertCaption", revision, caption, profile })` 接受 `DocxCaption = { label, text, position: "before" | "after", format?, chapter?: { level: number, separator: string } }`。`DocxCaption` 从 Wasm/Web foundation 导出，`checkDocxCaption` 从 Wasm foundation 导出。标签采用现有 SEQ 的标识符规则，最多 40 个 UTF-16 单元；说明是最多 1024 单元的有效单行文字，可为空。编号支持十进制、大小写字母及大小写罗马数字，缺省十进制。默认页面面板提供标签、说明、位置与格式控件。

核心在焦点所在正文段落或其所属普通表格前后插入一个题注段落，保留所选正文及表格内容。段落由标签、原生 SEQ 简单域和说明组成；同名编号按正文顺序重算显示，其他名称独立计数。只缓存新域，其他域的源缓存由现有显式刷新命令维护。既有 Caption 身份或英文名称对应的段落样式保持原源；没有时使用现有题注预设创建样式，缺少样式部件时一同创建关系和内容类型。上方题注带保持下段属性。新段落、缓存及样式资源合为一项精确历史，撤销恢复原选区；光标进入题注末尾，可继续原生输入和现有字段编辑。

可选 `chapter: { level, separator }` 创建带章节号的题注。`level` 为 1–9 级有效大纲标题，`separator` 是 1–5 个 UTF-16 单元的有效单行文字；默认面板提供级别和五种常用分隔符。例如 `{level:1, separator:"-"}` 生成 `Figure 3-1`，原生源由 `STYLEREF 1 \s`、分隔符和 `SEQ Figure \s 1` 组成。核心按继承后的大纲级别读取最近的同级前置标题；前面没有时使用第一个后置标题。编号沿现有列表定义及实际计数，未编号标题显示 `0`，没有目标标题时显示原生错误文字。插入同时缓存两个新域；标题及列表变化会重算显示，显式正文域刷新才写回其他缓存。

简单域和同段复杂数字级别 `STYLEREF` 可读取并保留原代码，支持可选 `MERGEFORMAT`。题注的周边输入、拆合段、完整域替换、富文本复制/剪切和目标位置重新计算沿既有路径；源、缓存、选择和样式一起精确撤销并保存重开。章节号通过题注参数创建，正文域查询对它返回专属保护原因，不把章节号解释成页码格式。按名称查找样式、其他 STYLEREF 开关、页眉页脚引用及浮动题注框继续实施。原生指令归 [`chapter-reference.mbt`](../../../modules/formats/src/docx/chapter-reference.mbt)，结果计算归 [`style-reference.mbt`](../../../modules/layout/src/style-reference.mbt)，严格接口归 [`docx-page.ts`](../../../packages/docx/src/core/docx-page.ts)。语义参考 [ONLYOFFICE 章节题注](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L25786-L25851)及 [STYLEREF 查找](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L981-L1170)。

文档保护、单节、字体、完整布局、XML、字段数量、资源及历史预算沿现有核心规则。斜体题注预设要求宿主提供对应字体映射；失败保留原包及历史。原生题注目录归[DOCX 题注目录](#docx-题注目录)；自动定位的浮动题注框继续实施。实现归 [`caption.mbt`](../../../modules/formats/src/docx/caption.mbt)和 [`docx-caption.tsx`](../../../packages/docx/src/react/docx-caption.tsx)。段落/表格旁插入及 Caption 样式依据 [ONLYOFFICE AddCaption](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L25688-L25828)，交互范围参考 GenOffice 的标签、SEQ 与说明入口。
