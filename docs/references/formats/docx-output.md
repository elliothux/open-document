# DOCX 布局与输出

[格式合同目录](../formats.md)

### DOCX 页面 PNG

Web 宿主 `DocumentEditor.exportPng(scale = 1, outputBytes = 67108864)` 返回当前页的 PNG `EditorOutput`。先调用 `goToPage(index)` 可逐页获取，index 从 0 开始。`scale` 是每 point 的像素数，允许 0.25–4；默认 1 对应 72 DPI。图片尺寸为页宽高乘 scale 后向上取整，不跟随预览 zoom 或设备 DPR。默认文件菜单提供“当前页 PNG”，沿既有 `onSave` 或下载路径输出原文件基名的 `.png`，不清除 DOCX 修改状态。

`DocumentEditor.exportPageImages(scale = 1, outputBytes = 67108864)` 一次返回全部页面的只读 `EditorOutput[]`，按页序排列且共享文档身份与 revision。总字节预算计算所有 PNG 的字节数之和，不是每页单独授予预算。页面依次编码并释放临时 Canvas，保留的 PNG 总量受同一预算约束；全部成功后才返回集合和登记输出，编码失败不交付前缀集合。导出不改变当前页、缩放、选择、源或历史。

默认菜单的“全部页面 PNG”先生成完整集合，再按页序等待既有 `onSave`；文件名使用 `<原文件基名>-01.png`、`-02.png`，页号至少两位并随总页数补齐。回调期间可以继续编辑，已生成页面仍绑定原 revision。宿主中途失败时显示已完成页数，保留已完成的外部保存，不继续后续回调，也不清除 DOCX 修改；重试重新导出当前修订的全部页面。无 `onSave` 时逐页发起下载并报告生成进度，不确认磁盘持久化；多文件下载受 [Chrome 站点下载权限](https://support.google.com/chrome/answer/114662?hl=en)约束。

输出进入同一原生输入队列。它包含已接受的编辑，绑定文档身份和 revision，后续排队编辑不改变已产生的图片。当前布局须匹配 revision，并且无未支持布局诊断；活动组合或图片缩放候选须先结束或取消。核心继续拥有分页、正文、表格、页面背景/边框及图片位置；平台只用现有 R0、轮廓和已准备位图绘制到独立 Canvas 后编码。选区、光标、批注高亮等覆盖层不进入 PNG。

输出 Canvas 与保留的预览/覆盖层合计最多 16777216 像素，输出字节预算为 1–67108864；尺寸在分配前检查，编码后检查实际字节数，并在成功或失败后释放临时 Canvas。PNG 失败保留源、选择及历史，不停止编辑；下一项成功操作清除 PNG 错误。销毁期间不交付图片。原格式保存与 PDF 继续沿原有恢复规则。

图片输出目标参考 [GenOffice exportImages](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/file-actions.ts#L1463-L1540)。当前复用已有核心绘制和 [Canvas 编码](../../../packages/web-core/src/canvas-surface.ts)，未移植其 Electron/PDF.js 导出路径；队列与入口归 [`document-page.ts`](../../../packages/docx/src/web/document-page.ts)及 [`document-output.ts`](../../../packages/docx/src/web/document-output.ts)。这是 Chrome/Chromium 的 Web 输出；其他编码和无浏览器图片输出继续实施。

### DOCX HTML 与 Markdown

核心 `Session.export_markup(revision, format, output_bytes, layout?)` 与同步/异步 `FoundationSession/Client.execute({ operation: "exportMarkup", revision, format, outputBytes: 67108864 })` 返回 UTF-8 字节。`format` 为 `html` 或 `markdown`。Web `DocumentEditor.exportHtml/exportMarkdown(outputBytes = 67108864)` 沿既有输出屏障返回 `EditorOutput`，绑定文档身份与修订。默认文件菜单输出原基名的 `.html`/`.md`，复用 `onSave` 或浏览器下载；导出不改变源、选择、历史和 DOCX 保存基线。

正文及普通/合并格中的已支持简单域沿当前原生布局输出静态结果，保留首个结果的字符格式及字面文字转义。PAGE、NUMPAGES 使用实际分页和节页码设置，SEQ 保留隐藏计数，REF/PAGEREF 保留当前引用值及有效书签链接；目标忽略大小写匹配，输出实际书签名称，缺失目标沿核心错误文字输出且不生成链接。空缓存不额外增加空段落换行，多个旧结果 run 只输出已计算的首个结果。含字段、图表或注释时，核心调用须传入当前完整 `layout`；其余内容可以省略。Wasm/Worker 使用已有最近布局，默认编辑宿主沿输出屏障提供它；缺失或陈旧布局、诊断和不可用字段位置均拒绝。导出不刷新原生缓存、清除未保存状态或修改历史。页码是原 DOCX 布局的静态值，读取器重新换行后不会重算。实现归 [markup-fields.mbt](../../../modules/formats/src/docx/markup-fields.mbt)，复用现有字段布局与 PDF 引用链接，结果展开参考 [ONLYOFFICE 字段内容复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L689-L691)。

正文及普通/合并格中已支持的公式输出原生 MathML。横向组合、分数、单/双脚标、平方根及带次数根、可伸展分隔符、多参数分隔、求和/积分、矩阵和多行对齐组保留结构；单式独立段落使用 block，其余使用 inline。上下堆叠极限仅在独立显示且源指定 `undOvr` 时使用，行内及缩小参数保留右侧上下限。矩阵保留列对齐和空格占位，基线设置转为 CSS 垂直对齐；多行公式使用零列间距的成对左右对齐，单独末项跨两列居中。单元格输出标准 `text-align` 后，追加 [Chromium MathML 默认样式所用的 `-webkit-` 值](https://github.com/chromium/chromium/blob/main/third_party/blink/renderer/core/css/mathml.css#L89-L95)，使匿名数学行实际对齐。统一字体、字号、颜色及线性无障碍标签沿现有模型输出，内部排列为 LTR，不随周围 RTL 段落镜像。

Markdown 中含公式的段落或整个列表使用 HTML 块，避免数学文字里的 `*`、`_` 和方括号被重新解释；格内公式随原 HTML 表格输出。读取器须允许 HTML、CSS 和 [MathML Core](https://www.w3.org/TR/mathml-core/)。字体不嵌入，字形度量、表格基线、间距与分页由读取器决定；不承诺与 Canvas/PDF 像素一致。导出不把 MathML 加入现有 HTML 粘贴的公式输入范围。未知或不支持的数学源仍拒绝，不输出残缺公式或源缓存替代图形。公式、文字、标签和 CSS 均沿原输出预算和转义规则。实现归 [markup-math.mbt](../../../modules/formats/src/docx/markup-math.mbt)，结构映射已对照 [ONLYOFFICE MathML 读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/math-ml.js#L345-L484)及 [表格结构](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/math-ml.js#L980-L1036)，未复制上游执行代码。

正文及普通/合并格的脚注、尾注引用输出为具名链接，保留当前布局的实际编号和字符格式。连续编号、分节编号格式及按节重启沿原 DOCX 规则，不按导出顺序重新编号；脚注与尾注的同名数字身份分别分配。注释按正文引用顺序归入文末脚注、尾注两个分组，保留普通段落、空段落、字符/段落格式、字面符号及返回引用的链接；未引用注释保留在原包中。Markdown 中的注释正文使用 HTML 块，读取器须允许 HTML。多节正文按源顺序连续输出；原生页底、节尾和文末的注释位置统一降级为文末分组，页面尺寸、分栏及分页几何不转移。所有节的页眉页脚仍检查并明确拒绝。注释布局、内容或编号位置不完整时拒绝导出，未知对象、字段、列表及审阅/链接身份保持保护。实现归 [markup-notes.mbt](../../../modules/formats/src/docx/markup-notes.mbt)，复用当前注释布局及段落序列化；链接与附注结构对照 [ONLYOFFICE 注释引用](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L563-L589)及[附注内容](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L2500-L2568)，未复制执行代码。

正文与普通表格按源顺序输出，保留逻辑文字、空段落、Tab/换行、前六级标题、粗斜体、下划线、删除线、上下标、内外链接、提示及书签锚点。HTML 使用解析后的字体、字号、颜色、高亮、背景、段距、缩进、方向与对齐；表格携带网格列宽、合并跨度、表头、底色、边距和共同边线。列表使用原生 `ol/ul/li`、`start/value` 和 `aria-level`，保留多级嵌套、实际起点、续号与重启。计数复用核心编号规则；正文和各单元格分别关闭列表容器，跨区域的计数仍连续。空项保留行高，标记与正文各自使用有效格式；RTL 列表使用逻辑起始边缩进。简单标签使用原生 HTML 计数器；复杂标签、装饰、超过 z 的 Word 字母序列及超出浏览器罗马计数范围的标签，使用已计算样式文字保留外观，同时保留列表结构与实际数值。

行内 PNG/JPEG 内嵌原始压缩字节，保留替代文字、显示尺寸及裁剪；原生 `wp:docPr/a:hlinkClick` 的图片链接输出为包住图片框的 `a`，保留安全地址、提示和目标窗口；指定窗口时加入 `noopener noreferrer`。内部目标忽略大小写查找，并输出书签实际名称，文字链接采用相同规则。图片源仍仅内嵌本地资源；复制锁、未知动作、悬停或声音、嵌套链接和未知图片沿原保护；基础图形与普通文本框沿下文输出。Markdown 使用原生标题、转义文字、硬换行及普通十进制/圆点列表。子项和续行按父项标记宽度缩进，保留非 1 起点、空项和中断后的续号。编号实例切换、特殊标签、超过九位的序号、跳级或 RTL 无法直接表达时，使用嵌套 HTML 列表；字符装饰、链接、图片及表格也使用内嵌 HTML，读取器须允许这些 HTML。HTML 列表片段及表格保留源背景，避免自动白色文字落在默认白底。普通 Markdown 段落不携带字体、颜色和页面几何；导出后的自动换行由读取器决定。分页/分栏断点转为换行；页面边框、分页约束及制表对齐不转移。

正文和普通/合并格中的无文字矩形、椭圆及线形输出内嵌 SVG，保留核心共用轮廓、填充、描边和无障碍名称。画布使用原框局部坐标，并在四周增加半个描边宽度，避免裁掉边线；零轴线形保留可见描边。无描边的零轴视口最小为 0.1 pt。整体链接与图片共用地址、提示和目标窗口规则。浮动对象按源顺序内联输出，保留形状与尺寸；页面位置、层次及文字环绕不转移。Markdown 读取器还须允许 SVG。未知图形继续拒绝，原包与历史保持。轮廓复用 [`basic-shape.mbt`](../../../modules/layout/src/basic-shape.mbt)，与 Canvas/PDF 使用同一几何。

正文及普通/合并格中的普通图表输出独立 SVG，复用当前布局的图表图元及实际字形轮廓。现有 14 种配置的柱/条、堆叠/百分比、线、面积、饼、圆环、散点和雷达保留尺寸、配色、坐标、图例、路径、裁剪与变换顺序；标题及完整数据提供无障碍标签，标签分别转义，不产生脚本或外部请求。字形与裁剪使用每个插图独立的引用身份，按导出顺序编号，重开后保持相同输出。字形以轮廓保存，不请求或嵌入字体文件。Markdown 中含图表的段落或整个列表使用 HTML 块，保留字面标签；读取器须支持 SVG 及内部 `use`/裁剪引用。图表是静态插图，不携带可编辑工作簿或实时绑定；浮动位置按源顺序内联，沿其他绘图的降级。当前布局、图表内容/尺寸、位置、字形和绘图状态不完整时明确拒绝；序列化逐段检查剩余输出预算，失败保留原包、历史和重做。实现归 [markup-charts.mbt](../../../modules/formats/src/docx/markup-charts.mbt)，复用 [共享图表布局](../../../modules/layout/src/chart-legend.mbt)，静态绘图转换依据 [ONLYOFFICE 绘图复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L534-L551)的渲染结果及尺寸语义；未复制上游执行代码。

普通文本框输出具名分组、可选择的 HTML 文字及装饰 SVG。段落和标题保留语义、解析后的格式、空段落及链接。文本区域复用核心 `DrawingFrame.text_box_rect`，包含预置图形文本区与四边距；CSS 表达顶部/居中/底部、换行及溢出裁剪。整体链接覆盖背景及未另设链接的文字片段；显式文字链接保留自己的目标，不生成嵌套链接。文字可选择，背景 SVG 不占用文字的无障碍语义。Markdown 中含文本框的段落或列表整体输出 HTML 块，保留框内字面符号；读取器须允许这些 HTML、CSS 和 SVG。浮动文本框同样按源顺序内联，字体与断行由读取器决定。复制锁、未知文本/图形元数据及不支持的容器沿原保护，导出保留源、选择和历史。几何归 [`drawing-text-box.mbt`](../../../modules/layout/src/drawing-text-box.mbt)，框内文字复用现有段落序列化。

含页眉页脚、批注、待处理修订、复杂字段或布局不支持内容时明确拒绝。合并格边线不统一时也拒绝。未知资源、非法链接、活动候选、旧 revision 及超限保留原包。文字、属性和 CSS 字符串分别转义；链接沿既有 HTTP/HTTPS/mailto/书签白名单，不输出脚本、事件、外链图片或外部样式。默认上限 64 MiB，并取原会话输出预算的较小值；UTF-16 中间结果和最终 UTF-8 字节分别检查，图片编码前预检剩余预算。Web 输出失败后可继续原生编辑。

实现归 [`markup-output.mbt`](../../../modules/formats/src/docx/markup-output.mbt)、[`markup-drawings.mbt`](../../../modules/formats/src/docx/markup-drawings.mbt)、[`markup-text-box.mbt`](../../../modules/formats/src/docx/markup-text-box.mbt)及 [`markup-lists.mbt`](../../../modules/formats/src/docx/markup-lists.mbt)。列表嵌套与续号参考 [ONLYOFFICE 列表栈](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L858-L951)，实际数值沿本项目共享的 `NumberCounter.advance`。链接属性与避免嵌套规则参考 [ONLYOFFICE CopyRunContent](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L661-L677)。标题和普通段落转换参考 [ONLYOFFICE CopyParagraph](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L728-L858)，合并格参考 [CopyCell](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L1035-L1066)。未复制上游执行代码。更广区域和 HTML/Markdown 导入继续实施。

## DOCX 布局与 PDF 输出

`FoundationSession/Client.execute({ operation: "layout", profile, prepareImages: true })` 返回 `PageLayout | { missingImages: string[] }`。核心列出正文、表格、各节页眉页脚、便笺和水印缺少的图片资源；宿主通过 `imageBytes` 解码并 `addImage` 后再请求布局。没有缺失资源时直接返回布局。`PageCanvas` 使用该路径，不再为图片准备读取完整 `flow` 和水印查询。`execute({ operation: "layout", profile })` 仍要求图片资源已准备完成。

DOCX 的 PDF 图片和 Alpha 遮罩写入 `/Interpolate false`，沿 [ONLYOFFICE 图片写入](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/SrcWriter/Image.cpp)省略该项时的原生默认行为。Canvas 保留平台平滑缩放，参照 [ONLYOFFICE drawImage2](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/Graphics.js#L570-L643)。两种输出的图片采样可以不同；文字、图形和图片位置继续共享核心布局。

`DrawingFrame.effectExtent` is a required `[left, top, right, bottom]` tuple in points. Width and height describe the drawing ink; inline layout reserves the extents around it. Ordinary frames without extents use four zeros. Extents must be finite and nonnegative, and the total dimensions must stay within 14,400 pt. Floating drawings and math require zero effect extents.

行内图片的非零 `wp:effectExtent` 参与换行和行高，不拉伸图片。裁剪与名义图片范围共用既有屏幕/PDF 布局、缓存和命中。实际阴影等图片效果仍拒绝，源 XML 与非目标部件照常保留。共用 Canvas 把单张静态图片的矩形裁剪直接交给 `drawImage` 的源区域参数，保留外层裁剪、透明度和变换；动态资源沿用普通命令执行。该路径消除额外矩形 clip 引入的边缘混色，没有增加绘制协议。

省略字号时，常规和复杂脚本默认均为 10 pt；文档默认、样式和直接格式继续按源覆盖。上述行为依据固定 ONLYOFFICE 的[行内占位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ParaDrawing.js#L1227-L1256)、[默认文字属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L13574-L13600)和[图片源裁剪](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/Graphics.js#L624-L683)。`ImageCrop.docx` 原件及改后文件的默认 UI、历史、独立颜色和输出检查见[测试说明](../testing.md#当前兼容证据入口)。

结构属性检查接受并保留 `w:noProof`，避免普通校对标记阻断布局。该属性不改变文字外观；未知属性、错误命名空间及重复声明仍保护。两份 C0 原件的属性检查与未编辑源保存通过，其他绘图和页眉页脚问题仍单列。

普通数字使用默认字形；共享塑形入口禁止固定依赖将 `frac/numr/dnom` 全局应用到所有数字。四种固定 Noto 字体的独立默认字形/位置已核对。当前没有 OpenType feature 编辑 API，也未实现 U+2044 上下文触发的自动数字分数排版；字符和 DOCX 源照常保留，不冒充完整 HarfBuzz 行为。原有连字、BiDi、字素及测宽/绘制共用路径保持。

DOCX 的显式页面宽、高按源整数 twip 精确保留，不再吸附到邻近纸型。500 pt 保持 500 pt；原 pgSz XML 和无编辑包字节保持。旧 LibreOffice 25.8.2.2 捕获中的 498.9 pt 等纸型归一化结果继续留作参考差异，不作为当前页面尺寸预期。普通换行候选仍在布局层排除补充码点之前的边界，强制换行、段末、字素紧急回退和 Unicode 分段模块保持。固定 CJK 行内容、换行和边界亲和性沿原独立参考检查，页面尺寸另按源 XML 核对。

DOCX 与 PPTX 的自然行度量使用字体原始 ascent、descent 和行隙，保留浮点 point 精度；例如固定 Noto Sans 的 11 pt 自然高度为 14.982 pt。低层 TextStyle 的 fontLeading=false 路径保留原有 LibreOffice MSO1 参考设备取整：每 pt 120 单位，ascent/descent 先取整，再换算为整数 twip。旧捕获与字体二进制分别核对，两种度量不混用；源字号、字形 advance、轮廓和 API 单位保持。

字体自然高度优先使用有效 USE_TYPO_METRICS，随后是有效 hhea，最后回退到已验证的 Win 度量；缺失或截断 hhea 原子拒绝。`FontInfo` 的 ascent/descent 随此选择，CJK 与 Arabic 的预定变化已由固定字体二进制独立核对。光标在单文字区段复用行框，多区段按前侧文字区段取自然高度并裁剪到当前页段落底部；`caret`、`hitTest`、导航共用计算。原 CJK 与六组垂直控制已匹配固定参考。十二组独立原生对照另验证中西文自动间距、不同字号和窄行，以及 Arabic/Asian 进入和退出区段的差别；测宽、字形和光标共用间距，行尾仅在宽度允许时保留。有效 autoSpaceDE/DN 源属性按固定 LibreOffice 25.8.2.2 导入行为保留但不应用，非法或重复声明继续保护。两份 Arabic/Asian 原件已验证折叠 Left/Right 的 after/before 坐标及高度、70 个独立鼠标位置和 36 个默认逻辑按键位置；真实编辑器按键在 Chromium 验证。所有脚本分类、嵌套 BiDi、小字号间距命中及其他导航配置仍未全面验收；证据与范围见 [P4](../../implemented/p4-docx-editing.md#验证依据与边界)。

P4 自动行距曾通过完整运行 `1791779829628`。当前保留其中的段距与分页规则：按固定 LibreOffice 的[导入取整](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/sw/source/writerfilter/dmapper/DomainMapper_Impl.cxx#L5303)，先将 auto 值换成整数百分比；0 按 100%，非零最小为 50%。[首行与后续行](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/sw/source/core/text/itrform2.cxx#L2335-L2422)分别处理正间隙与收缩，[段间间隙](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/sw/source/core/layout/flowfrm.cxx#L1644-L1743)归属前段，换页清除。单元格和空页眉末段按[专用路径](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/sw/source/core/layout/flowfrm.cxx#L1934-L1942)及[名义字号的 1.15 系数](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/sw/source/core/layout/frmtool.cxx#L2674-L2683)留出底部间隙。ONLYOFFICE sdkjs 的[比例间隙](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js#L2988-L2996)另有浮点路径；当前沿用已冻结 LibreOffice profile 的间距规则。P14 将字体贡献改为原始度量，并读取显式段落标记字号；23 组参考保留原生捕获，按固定字体度量换算后严格检查字高、基线、分页和段距。安装 Node 与生产 Worker 还核对源保存和历史状态。磁盘及后续失败记录保留。图片自动行距及原生 caret/选区仍未获得本批几何验收，证据见[测试记录](../testing.md)。

行距保留 `{ rule, value }` 的原始 OOXML 数值，先合并默认值、`basedOn` 与直接格式，再解释单位。`auto` 的单位为 1/240 行；`exact` 和 `atLeast` 为 twip。仅覆盖段前或段后距不改变行距；最小值 0 使用自然行高。固定行距采用 LibreOffice 25.8.2.2 参考配置：基线位于行高的 4/5，段尾手动换行的空行保持相同行高。共享布局的 `clip` 指令让 Canvas 和 PDF 在行的垂直范围内裁剪文字与内联图片；最小行距保留自然基线。该配置依据 [LibreOffice 行度量](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/source/core/text/itrform2.cxx)，不声明各 Office 应用采用相同基线。

`flow().additiveSpacing` 指明段距策略。普通同页相邻段落在 `settings.xml` 存在且 `doNotUseHTMLParagraphAutoSpacing` 缺省或为 false/0/off 时，合并为 `max(previous.after, current.before)`；该标志开启时累加。缺少整个 settings 部件时，保留固定 LibreOffice 配置的累加默认值。正文和同一单元格使用相同规则；自然换页舍弃跨页间距，显式段前分页保留当前段前距，单元格首段前距与末段后距计入行高。段内显式分页结束时舍弃该段段后距。固定参考转换分别核对了这几类边界。

上述策略结合 [ONLYOFFICE 普通段距与特殊分支](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L10805-L10860)、[LibreOffice 布局分支](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/source/core/layout/flowfrm.cxx#L1582-L1770) 与固定引擎结果；不是完整 Word 间距规则。`contextualSpacing` 的支持范围归 [P10 当前格式编辑](docx-editing.md#p10-当前格式编辑)。`beforeAutospacing/afterAutospacing` 按默认值、样式链和直接格式继承，自动值使用 ONLYOFFICE 的 14 pt；内容区域首段不加自动段前距，单元格末段不加自动段后距，同样式、同编号实例的相邻段落抑制自动段距。显式设置段前/段后距同时关闭对应自动标志，清除则恢复继承。实现归 [automatic-spacing.mbt](../../../modules/formats/src/docx/automatic-spacing.mbt)，数值依据 [ONLYOFFICE 自动段距](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles/para-spacing.js#L321-L339)。按行指定的段距及上述范围外的编号仍不支持，直接格式和实际应用的默认值、样式链都会报告部件与特性，例如 `unsupported-layout:word/styles.xml:w:vanish`。未使用的命名样式不产生诊断。原始内容照常保留，应用不能把带诊断的结果称为保真布局。

自动断行前只解析一次整段 BiDi 层级；选定行执行 UAX #9 L1/L2，塑形沿用该层级与镜像规则。同样式源 run 拆分不会改变阅读顺序；使用独立 FriBidi 1.0.16 的整段层级核对 RTL、数字、括号及拉丁后缀，不以片段重新推断方向生成答案。

浏览器预览只接受 PNG、JPEG 与 GIF。宿主先检查有界编码头的尺寸与像素预算，再调用原生解码器；解码结果仍核对预算与头部尺寸，失败或取消关闭已创建的 ImageBitmap 并保留宿主。GIF 使用原生解码器选取的静态帧，不支持动画播放；其他编码明确失败。该检查不保证浏览器或 WasmGC 的进程峰值内存。

`flow()` 返回派生的段落、样式、页面设置、表格、内联图片引用和诊断；不能修改它来编辑文档。段落与表格数组各自保持源顺序；顶层表格的必需 `beforeParagraph` 是当前源 XML 中先于该表格的正文段落数，同位置连续表格按表格数组顺序插入。稳定 `id` 不表示文档位置，拆段后也不按 ID 排序。`layout(profile)` 在核心中生成 `PageLayout`，profile 将 DOCX 字体键（含 `|bold` / `|italic`）映射到已供应字体 identity。缺字体或字形明确失败，宿主不提供 DOM 测量。布局长度单位为 point；字体内部度量仍用 font units，源范围使用节点局部 UTF-16 offset。

支持 docDefaults、段落/字符样式 basedOn、主题 Latin 字体、直接格式、字号/颜色/粗斜体、段前段后、缩进、左/中/右对齐、auto/exact/atLeast 行距、空段落及显式分页。正文、表格和页眉页脚共用段落间距校验，负间距/最小行距/单元格 padding 明确失败。页面按[多节分页](docx-pages.md#多节分页)读取独立节配置，指定节页面几何与多节原生输入已接通，其余分节编辑继续实施。分页的断行使用固定 Unicode 数据、上述 Office 单词规则与基本 BiDi；同样式跨文本节点一起塑形并保留源映射。`unicode_linebreak` 的 Unicode 15 测试向量按上游规则排除 30.22/999.0 做依赖回归，其字符表源自 Unicode 13；不宣称完整 UAX #14 符合性。当前 fallback 仍按码点选择，复杂 script、彩色字形和任意字体质量不在承诺范围。

基础表格使用固定列宽、当前支持的线型/无边框、RGB 单色填充、四边 cell margin 和最小/精确行高；普通行[逐格跨页](docx-tables.md#表格行跨页)，纵向合并行组整体换页。边框编辑与冲突规则归[表格边框](docx-tables.md#表格边框)。相邻行共享边框只占一次高度，表尾另留底边，分页判断包含当前页底边空间。自然字高使用上述字体原始度量；固定 Noto 表格的旧原生取整差异单独核对，共享边按实际解析结果只绘制一次。不扩大为所有应用或水平几何一致。嵌套读取与文字编辑沿[当前合同](docx-tables.md#嵌套表格读取与文字编辑)，更广结构编辑保持保护；精确行高沿[裁剪规则](docx-tables.md#表格尺寸)。不绘制浮动、旋转或翻转图片；页眉页脚已接通[文字、实际避让与逐页输出](docx-pages.md#页眉页脚)。已识别但未实现的正文属性给诊断，原包仍由 P2 保存；不是完整属性/schema 检查器，主题颜色、条件表格样式与复杂页眉页脚不在支持面。图片仅支持包内内联 extent；宿主解码已授权资源为 RGBA，外链图片明确拒绝、不自动下载。

表格左/中/右对齐按基础样式、派生样式、直接属性依次覆盖，start/end 沿用 left/right 归一化；未知有效值报 `unsupported-layout`。明确零 dxa 缩进仅在可选符号后全零数字、已知属性且无子节点/文本时视为无位移；非零、非法或未知声明仍诊断/保护。此规则不增加非零缩进、RTL 表格语义或复杂表格支持。Word compatibilityMode 对表格外侧边距和定位的版本差异尚未实现，零缩进声明可读不等于版本布局已经一致；固定网格超过正文可用宽度仍明确拒绝，不通过缩小原件或统一左移获得通过。原 POI 表格的显式 `w:kern` 阈值已支持，`w14:ligatures` 等未知扩展仍诊断和保护；普通核心源事务可用不等于可视编辑可用。

文字 `auto` color 延后到所在单元格背景确定后解析，正文背景为白色，显式 RGB 保持原值。固定参考 profile 采用 sRGB 相对亮度乘 255 小于 88 时白字、否则黑字，与已检查的 LibreOffice [automatic text color](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/source/core/txtnode/fntcache.cxx) / [Color::IsDark](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/tools/source/generic/color.cxx) 规则相符；不承诺任意 Word 主题的颜色结果。

成功的字体添加、图片添加、打开或正文替换令旧布局失效。`layout` 每次生成新的会话内 `id`；profile 改变必须重排。`exportPdf(outputBytes, layoutId?)` 使用当前核心布局，可指定展示时的 ID 防止旧预览下载新内容；没有布局或 ID 过期时失败。`DocumentPreview` 始终传自己的 ID。失败的图片替换不覆盖已加载资源；PDF 失败不提交部分输出。

`PageLayout.shapedParagraphs` / `reusedParagraphs` 是本次实际塑形/复用的段落几何数量（含表头、单元格及复用页面内的段落）；`reflowedPages` / `reusedPages` 是重新处理分页状态及直接复用的整页数，二者之和等于当前页数。它们不是耗时指标。完整源输入和字体/page/profile/间距依赖匹配时，核心复用局部行及页面前缀，在首个变化边界所在页继续原分页规则；只有未变后缀和纵坐标、段后间距及页内文字/边框有无全部匹配，才接回旧几何。表格按行检查稳定点，显式空白页规则不变；旧后缀仍检查当前图片及行/页预算。仅保留上次成功布局：塑形和分页各自最多 1024 条输入、1048576 个载荷单位，超限仍正常塑形/分页，不缩减文档支持。一个原始字段或字符串 UTF-16 单元计一单位，不代表堆字节或峰值内存；失败不提交候选缓存，成功增加字体后清空，关闭释放，返回的可变数组与缓存隔离。阶段范围与性能边界见 [P4](../../implemented/p4-docx-editing.md#保留限制)。

Office PDF 输出使用同一字形坐标、TrueType 子集、字体宽度、CIDToGIDMap、ToUnicode 与行级 ActualText，支持图片及 alpha mask。RGB 与 Alpha 流使用已有 Flate 无损压缩，保留解码像素、图片复用和插值设置；源 RGBA 仍受未压缩字节预算限制。字体 fsType 禁止嵌入/子集时失败。默认 variation 坐标与 face 0；不支持 CFF、PDF/A、PDF/UA、签名或浏览器打印。PDF outputBytes 是 1–67,108,864 字节的产物上限；在最终文档序列化前核对已构建对象 payload，再核对最终确切大小。它不是字体子集、临时对象或整个进程的内存上限。

一次段落布局内的候选测宽另保留最多 128 个成功宽度，每个精确键最多 4096 UTF-16 单元，键合计不超过 524288 单元，另有 128 个 Double。键绑定文本、字号、主字体和当前 BiDi 上下文；字体集合在该同步调用内不变。超限重新测量，图片和最终绘制不使用此表；返回或失败即释放，不形成跨段落或跨编辑的持久缓存。此载荷计数不代表实际堆峰值。

每段最多 4096 UTF-16 单元，最多 1024 页 / 32768 行。图片最多 256 个，每边最多 4096 像素，总 RGBA 16 MiB；当前页内容与编辑覆盖层合计最多 16777216 像素，zoom 0.25–4。预算分别约束核心资源、产物与宿主 Canvas，不等于进程峰值内存上限。

断行对候选前缀重新塑形以保留上下文，长无空格段落存在二次成本。Worker 隔离主线程，当前没有延迟 SLA。实际交互被阻断时再诊断，不能以每字符 advance 或 DOM 测量替代正确布局。

性能校准和进一步优化延后。已有输入/字形/历史/队列/布局/Canvas 上限、拒绝恢复和释放要求保持。

`DocumentPreview.create(root, client, profile, signal?)` 显示只读页面、文本和诊断，支持滚动、切页、缩放、键盘与 PDF 下载。`dispose()` 释放自己持有的 Canvas、Path2D、ImageBitmap、监听器和 DOM，保留宿主其他子节点并恢复属性；调用方另需 `client.dispose()` 释放 Worker/核心。取消在异步准备步骤之间检查，不能抢占正在执行的同步 Wasm。基础文本语义与可达按钮不是完整文档无障碍认证。
