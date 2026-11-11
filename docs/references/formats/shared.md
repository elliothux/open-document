# 共享字体、绘制与宿主

[格式合同目录](../formats.md)

本文维护各格式的当前支持面；产品目标与核心/宿主职责归 [SDK 合同](../sdk.md)。公开包仍为 private/WIP，API 尚未发布。内部架构直接按当前需求修改，删除旧模型与旧路径；兼容处理仅限文档格式。

XLSX 的网格、值/公式编辑、保真保存与基础打印见 [P5](../../implemented/p5-xlsx-editing.md)。以下分别声明文件读取、计算、显示和编辑边界。

PPTX 已交付限定幻灯片编辑、源保留及静态 PDF，结果与检查依据见 [P6](../../implemented/p6-pptx-editing.md)。

PDF 包含 Office 布局输出、[P7](../../implemented/p7-pdf-input.md) 的输入/查询、[P8](../../implemented/p8-pdf-operations.md) 的源对象保存，以及 [P13](../../implemented/p13-pdf-core.md) 已交付的新建、阅读、对象编辑、表单、批注、页面编排与派生输出。当前能力和保护边界归本文；P13 的交付状态与验证仍归阶段方案。

后续实现与测试基准优先使用 ONLYOFFICE core/sdkjs，其次使用 LibreOffice。下文 LibreOffice profile 记录已有实现和证据；对应功能调整时按当前优先级核对，并保留历史结果的真实来源。

P4 已完成限定 DOCX 编辑，只对声明范围负责。已验证输入不授予全部控制符编辑或布局支持；性能专项延后。交付范围见 [P4](../../implemented/p4-docx-editing.md)，运行证据入口见[测试说明](../testing.md#证据与正确性)。

U+202A–U+202E 与 U+2066–U+2069 保留在逻辑文字中，不要求可见字体字形，也不输出控制符轮廓。核心保留这些零宽区段的方向、字体和字号。十类输入的全部 234 个 Right/Left 矩形及真实输入框在 Node/Worker 匹配重复 LibreOffice 参考；原 51 处差异已修复。五组反向阿拉伯塑形向量在两个宿主匹配原生字形。内部 `PlacedRun.size` 以 pt 提供区段字号；完整布局留在核心。固定源码见[依赖记录](../dependencies.md)，阶段验证范围见 [P4](../../implemented/p4-docx-editing.md#验证依据与边界)。

DOCX 文字区段的实际宽度和后续起点按固定 LibreOffice 的整数 twip 放置，初始断行 advance 和公开 `shape()` 保留浮点设计值。具体未支持范围与历史差异由私有 case 记录维护，不用行宽通过代替光标和选区验证。

共享段落在判断换行时不计行末 U+0020 空格。原文、UTF-16 范围、完整空格宽度和光标位置继续保留。居中、右对齐及 PPTX 框适配使用内容宽度；制表位和不换行空格保留各自语义。强制换行、分页和分栏前的空格不产生额外空行。行为依据 [ONLYOFFICE 延迟结算空格宽度](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L4131-L4168)及[不含末尾空格的段落对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js#L1951-L2070)。实现归 [paragraph.mbt](../../../modules/layout/src/paragraph.mbt)与 [line-measure.mbt](../../../modules/layout/src/line-measure.mbt)，PPTX 复用同一内容宽度。

全由 U+0020 空格组成的文字运行按源字号计宽，并保留光标与偏移。有正文的行用正文计算文字行框，较大的空格不会让链接文本框提前续行。空行沿用现有度量。[ONLYOFFICE 行度量](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Editor/Run.js#L5051-L5133)

DOCX/PPTX 共享单词断行规则。词内斜杠 U+002F、Unicode 连字符 U+2010 和短破折号 U+2013 后不产生可选断点；普通连字符 U+002D 和长破折号 U+2014 保留已有断点。样式分段不产生新断点。原文、UTF-16 范围、不换行空格、强制边界、字素回退和缺字保护保持。规则依据 [ONLYOFFICE 词后断点](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/RunContent/Text.js#L571-L582)及[段落单词换行](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js#L4283-L4311)，实现归 [paragraph.mbt](../../../modules/layout/src/paragraph.mbt)。独立原生控制和检查范围见[测试说明](../testing.md#当前兼容证据入口)。

## 字体资源与替代

低层 `TextStyle.kerning` 使用 `all/words/none`，分别控制完整字偶距、词内字偶距及禁用；`fontLeading` 控制是否采用字体原始行隙。DOCX 未声明字偶距时禁用；显式 `w:kern` 按半磅字号阈值继承，字号达到阈值时启用，格式化改变字号后重新判断。PPTX 按词塑形。字体行隙计入基线上方，字形轮廓仍保留原始精度。

字体缺少 U+00A0 字形时，预检允许 HarfBuzz 使用该字体的普通空格字形。已有 U+00A0 字形仍优先；两者均缺失时继续报告缺字。逻辑字符和不换行属性保持，未将源文字改为空格。此行为复用固定塑形依赖的[空格回退](https://github.com/harfbuzz/harfbuzz/blob/14.4.0/src/hb-ot-shape-normalize.cc#L163-L174)，实现归 [shape.mbt](../../../modules/layout/src/shape.mbt)。

`CanvasRenderer/CanvasSurface` 接受 `integer/fractional/pdf` 三种固定栅格策略。DOCX 宿主选择 `fractional`，图形保留矢量坐标。轴对齐、仅填充字形按四档横向子像素和整数设备行定位。缓存高度按实际字体上下边界的设备整数差加 3 像素计算；超过 50 像素时，横向按整像素定位。规则依据 [ONLYOFFICE 字形缓存](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/splash/SplashFont.h#L31-L34)及[缓存高度与相位上限](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/splash/SplashFont.cc#L65-L122)。反射与负坐标使用相同向下取整规则。表格默认使用 `integer`，截去轴对齐、仅填充字形的设备原点小数，参照 [ONLYOFFICE 位图定位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/Graphics.js#L1433-L1454)。PDF 宿主选择 `pdf`，普通轴对齐、仅填充字形复用四档横向子像素和字体缓存高度规则，参照 [ONLYOFFICE 字形原点分档](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/splash/Splash.cc#L5580-L5595)。90° 字形继续保留横向小数；两者纵向均向下取整到设备行，包括负坐标。纵向规则参照 [FreeType 的横向子像素与整数行](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/splash/SplashFTFont.cc#L226-L247)。原生 `PixelCenters` 字形、描边及其余旋转或剪切字形沿既有路径。策略只影响栅格绘制，不改变核心布局、光标、源坐标或 PDF 输出。

核心 `DrawGlyph.fontBounds` 携带实际字形字体的设计单位 `[xMin,yMin,xMax,yMax]`，包括回退字体。各轴边界为有序整数，范围为 ±65536。没有 SFNT 字体边界的原生矢量轮廓使用 `null`。绘制指令按连续且绘制参数相同的字形共用单位、字体边界、描边宽度和缩放，每个字形携带轮廓键与位置。

`fractional` 策略的正负 90° 填充字形用字体左右边界计算设备缓存高度。高度为旋转后两个边界的整数差加 3 像素。50 像素以内保留四档横向相位，超过 50 像素使用整像素。纵向沿设备整数行。规则只用于已知字体边界的矢量字形。[Poppler 字体边界变换](https://gitlab.freedesktop.org/poppler/poppler/-/blob/3a79c6217fe185311e4905204d99c7a53a480883/splash/SplashFTFont.cc#L80-118)

`setGlyphRasterMode(mode)` 为字形选择上述定位规则，几何与图片继续使用构造时的策略。`CanvasRenderer` 返回规则是否变化；`CanvasSurface` 在变化时使绘制缓存失效，覆盖层与图片导出使用相同规则。PPTX 选择 `fractional` 字形并保留整数几何绘制。XLSX 图表工作表也选择 `fractional` 字形；其整数 em 位图路径保持四档采样，切回普通工作表恢复 `integer` 字形。描边字形及其他回退规则保持。DOCX 与 PDF 的默认字形策略保持。

PDF 绘制命令的六个矩阵分量与字形原点用 Double 组合，进入设备栅格前保留输入精度。保存与恢复同时保存这份矩阵，避免 Canvas 或 DOMMatrix 提前舍入整数边界附近的原点。普通内容流的小数按原生顺序读取；源对象词法和字典数值身份保持。读取依据与固定补丁归[依赖记录](../dependencies.md#pdflite-输入预算与源映射补丁)。

PDF Canvas 的矩形命令与矩形路径共用裁剪。常规矩形裁剪下，填充字形使用整数像素边界，矢量保留横向小数并包住纵向覆盖行。嵌套矩形先求交，绘制完毕后恢复裁剪范围。整数与分数策略、图片源裁剪沿各自规则。[Poppler 矩形边界](https://gitlab.freedesktop.org/poppler/poppler/-/blob/3a79c6217fe185311e4905204d99c7a53a480883/splash/SplashClip.cc#L99-131)、[字形像素裁剪](https://gitlab.freedesktop.org/poppler/poppler/-/blob/3a79c6217fe185311e4905204d99c7a53a480883/splash/Splash.cc#L2719-2738)。

独立实心轴对齐线段分别取整两侧设备边界，窄正向跨度保留最接近原中心的一像素。平端和方端的切向边界也按设备像素取整，方端先计入半线宽扩展；反射、90° 及非等比缩放沿用相同规则。独立线段可合并为一次填充，交点只计算一次透明度。圆端保留圆弧延伸；其余路径沿下述轮廓或原生 Canvas 回退规则绘制。实现归 [`pdf-pixels.ts`](../../../packages/web-core/src/pdf-pixels.ts)，行为依据 [ONLYOFFICE 的两侧边界与窄跨度规则](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/splash/SplashMath.h#L304-L375)。独立原件和像素检查范围归[测试说明](../testing.md#当前兼容证据入口)。

PDF 轴对齐线性渐变前的矩形裁剪使用四档横向覆盖率及 1.5 次方校正。渐变有效区间内的中间行按原生规则补齐至少半像素的侧边；首末行及区间外保留边缘覆盖率。未延伸的渐变端点按设备整数位置判断是否着色，边界外不留下半像素颜色。判断合并裁剪后的变换、样式及渐变色标区间，反射与 90° 旋转使用同一设备规则。宽高至少一设备像素时，复用普通路径裁剪表达边界。更小的裁剪、径向渐变、剪切和非矩形路径沿既有规则。Office 整数与分数策略保持，未增加遮罩、像素缓存或栅格器。原生边缘与有效区间依据 [Poppler 裁剪采样](https://gitlab.freedesktop.org/poppler/poppler/-/blob/3a79c6217fe185311e4905204d99c7a53a480883/splash/SplashClip.cc#L273-324)、[渐变侧边校正](https://gitlab.freedesktop.org/poppler/poppler/-/blob/3a79c6217fe185311e4905204d99c7a53a480883/splash/Splash.cc#L6492-6606)及[有效区间判断](https://gitlab.freedesktop.org/poppler/poppler/-/blob/3a79c6217fe185311e4905204d99c7a53a480883/poppler/SplashOutputDev.cc#L318-328)。

三种策略对闭合实心矩形的斜接描边，也分别对齐四边的内外边界。孔洞、原填充、透明度和裁剪保持；轴对齐、反射、90° 及非等比缩放适用。PDF 还处理矩形圆角连接；斜接上限不足、零宽及其他连接或变换沿原生回退规则。

单个矩形的正值虚线可沿四边连续取样。零相位、平端与斜接连接使用设备像素边界，并保留跨角连接。闭合路径连接首尾，显式回到起点的开放路径保留两个平端。虚线掩模裁剪完整描边，透明度只计算一次；每次最多拆分 8192 个区间，超限及其他样式在绘制前回退。相位与闭合连接依据 [ONLYOFFICE 虚线路径](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/splash/Splash.cc#L5134-L5294)，实现复用上述矩形描边。

`integer/pdf` 策略下，不透明、普通混合的矩形填充也对齐设备边界，避免后画底色部分覆盖前景。轴对齐、反射、90° 及非等比缩放适用；原裁剪和绘制状态保持。分数策略、`PixelCenters`、透明填充、其他混合、斜变换及取整后塌缩的矩形保留原生 Canvas 绘制。规则依据 [ONLYOFFICE 矩形填充对齐](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/splash/Splash.cc#L5402-L5516)，实现归上述共享绘制模块。

同色、不透明、无虚线的闭合菱形在普通混合下，以一次填充绘制斜接描边的外轮廓，避免填充与描边重复叠加边缘覆盖。非等比、反射及剪切共用原矩阵；透明度、不同颜色、其他连接及斜接超限保留分开的原生绘制。源路径和 PDF 输出保持。

`integer/pdf` 策略下，三次曲线描边先按设备空间拆成折线。采用原生一像素平坦度和十层拆分上限；整条路径超过 8192 段时，在绘制前回退。平端、斜接且无虚线时，将线段矩形与外侧连接合成一次轮廓填充。开放端点与闭合连接分别处理，近反向斜接退为斜角。透明度只计算一次，原变换与裁剪保持。轮廓超过 8192 条命令时，在绘制前回退到已拆分的 Canvas 描边；其他线帽、连接及虚线沿原描边，PDF 圆头虚线另按下段规则。填充保留原曲线。`pdf` 策略下，细分结果若能由已有轴对齐矩形规则绘制，描边先复用该规则；包括开放路径回到起点的端帽、显式闭合连接、绕序、虚线与一次透明度。不能识别的轮廓继续原轮廓或 Canvas 绘制，8192 段与轮廓预算保持。无填充的开放直线和折线现复用同一轮廓，保留多个子路径、透明度及变换。无填充的闭合或回到起点的纯直线路径继续沿既有矩形、菱形及 Canvas 规则；带填充纯直线的 PDF 描边另按下述覆盖规则。空路径、未以移笔起始及预算超限在绘制前回退。分数策略及 `PixelCenters` 保留原 Canvas 绘制。描边实现归 [pdf-stroke.ts](../../../packages/web-core/src/pdf-stroke.ts)，矩形与像素边界仍归上述模块。依据 [ONLYOFFICE 描边细分](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/splash/Splash.cc#L5008-L5130)及[描边轮廓](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/splash/Splash.cc#L7630-L8050)。

`pdf` 策略的正值虚线在圆头、圆角连接时，沿拆分后的未填充路径或曲线路径计算相位，并合并闭合首尾段。纯轴线复用原描边对齐；其余路径把线段、圆头与连接合为一个遮罩。按 4×4 网格计数路径触及的子像素，再应用 1.5 次幂覆盖校正，保留细线与一次透明度合成。源形状、颜色、混合、外层裁剪及绘制状态保持。虚线切分和轮廓分别最多 8192 步；遮罩最多 1,048,576 个子像素，单边最多 8192。零长度虚线、其他端点或连接、非纯色画笔及预算超限沿原 Canvas 回退。Office 与分数策略保持既有绘制。覆盖依据 [Poppler 26.05 网格扫描](https://gitlab.freedesktop.org/poppler/poppler/-/blob/3a79c6217fe185311e4905204d99c7a53a480883/splash/SplashXPathScanner.cc#L209-404)及[覆盖校正](https://gitlab.freedesktop.org/poppler/poppler/-/blob/3a79c6217fe185311e4905204d99c7a53a480883/splash/Splash.cc#L1432-1512)，代码复用平台 Canvas 生成有界遮罩，没有复制上游扫描器。独立控制、原件与剩余差异见[测试说明](../testing.md#当前兼容证据入口)。

`integer/pdf` 策略下，带填充的曲线路径在不透明 `source-over` 描边、平端、斜接且无虚线时，对合并后的描边轮廓使用 4×4 覆盖遮罩。相接线段的描边带在同一遮罩中计数。带填充的纯直线路径在两种策略下复用相同规则。遮罩计入仅触及上界的子像素，保留显式闭合与返回起点的端点语义。分数策略、`PixelCenters` 和不支持的描边样式继续原生绘制。

遮罩最多 4,194,304 个子像素，单边最多 8192。遮罩与输出画布计入 16,777,216 像素总表面预算，包含主画布和已分配父层。超限时，曲线路径沿原轮廓填充，纯直线路径用 Canvas 描边。圆头虚线共用表面预算，并采用自己的子像素上限。

Office 椭圆从左侧中心起画，保留原生虚线起点。四段 90° 曲线使用 `(sqrt(7)-1)/3` 控制系数，依据 [ONLYOFFICE 椭圆预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L3100-L3124)及[圆弧转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/ArcTo.js#L215-L246)。圆环内圈使用相同系数和相反方向，保留真实孔洞。实现归 [`basic-shape.mbt`](../../../modules/layout/src/basic-shape.mbt)及 [`donut.mbt`](../../../modules/formats/src/pptx/donut.mbt)，Canvas 和 PDF 共用核心路径，未复制上游执行代码。

排版使用宿主提供的实际字体字节和 `profile`，不使用浏览器 CSS 字体度量。显式字体键映射优先；宿主可提供 `*`、`*|bold`、`*|italic`、`*|bold|italic` 开启替代。缺少精确映射时，核心先取对应粗体/斜体替代，再取 `*`。没有这些项时保留严格的 `missing-font` 行为；已明确映射的字体身份无效时仍报错。字体缺字时继续在已加载字体中查找，全部缺字或格式不支持时保留诊断与保护。独立视觉验收须核对参考实际使用的字体文件与样式映射；`*` 映射到常规字体不能证明原生粗斜体字形一致。解析归 [font-profile.mbt](../../../modules/layout/src/font-profile.mbt)。

当 `TextStyle.font` 请求 `bold` 而实际字形字体不是粗体时，核心按 `fontUpem * 0.343 / 12` 计算描边宽度，随后随字号缩放。实际粗体只填充。正文、编号、字段、制表符引导符和元文件文字共用规则。普通 `shape()` 和 PDF 输入字形输出零。Canvas 使用小数矢量原点，PDF 先填充再描边并恢复绘图状态。[实际字体样式判定](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/fontengine/FontManager.cpp#L742-L780)

PPTX 文本框和表格单元格共用模拟粗体宽度。连续模拟粗体沿用进入该状态时的实际点宽，跨字号、颜色、换行和相邻段落均适用。普通字形或真实粗体结束该状态。段前高亮、段后装饰线、图形标记和单元格边界重开批次。含行内绘图的行使用各字形本身的宽度。[原生文字批次和描边公式](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/SrcWriter/States.cpp#L105-L179)

`Glyph/DrawGlyph.strokeWidth` 以字体单位表示，零值只填充。绘制宽度通常限于 `0..1024`。定位后的字体单位数值可超出 1024，条件是存在非零缩放且实际描边宽度不超过 32 pt。Canvas 和 PDF 读取同一定位结果。

PPTX 混排行的文字升降部由可见文字和不换行空格参与计算。仅含普通空格的文字段保留字宽。全空格行沿用原有度量。实现归 [paragraph-layout.mbt](../../../modules/formats/src/pptx/paragraph-layout.mbt)，原生对照见[测试说明](../testing.md#当前兼容证据入口)。

替代只改变排版所用字体，不修改 Office 源中的字体声明。默认 UI 在启用替代模式时提示换行、分页可能不同。当前仍接收独立 TrueType 轮廓，字体合计最多 8 个、32 MiB；CFF、集合、未支持字形和嵌入许可沿既有保护处理。PDF 优先使用受支持的嵌入字体；显式替代仍保留其原有诊断。

### 输入字节限额

四格式 Session 与 Client 的 `inputLimits()` 返回只读、按会话缓存的核心限额；Editor 的同名字段提供给文件输入界面。Worker 初始化返回同一查询结果。共有字段 `fontBytes` 表示单次字体输入上限，当前为 32 MiB。PPTX 的额外字段归[其输入合同](pptx-editing.md#pptx)。其他格式使用以下字段：

| 格式 | 类型 | 字段与上限 |
| --- | --- | --- |
| DOCX | `DocxInputLimits` | `imageBytes`：4 MiB；`rgbaBytes`：16 MiB |
| XLSX | `XlsxInputLimits` | `imageBytes`：2 MiB；`rgbaBytes`：16 MiB；`delimitedBytes`：4 MiB |
| PDF | `PdfInputLimits` | `rgbaBytes`：16 MiB；`importBytes`：64 MiB |

`imageBytes` 限制编码图片，`rgbaBytes` 限制一次解码像素注册，`delimitedBytes` 限制 CSV/TSV 输入，`importBytes` 限制 PDF 页面导入。打开文件仍使用命令显式传入的预算，Office 同时检查 `fileBytes/retainedBytes`；CSV/TSV 还取这两者与 `delimitedBytes` 的最小值。PDF 打开使用 `PdfBudget.fileBytes`。

DOCX、XLSX 和 PPTX 的 `inputLimits()` 还返回 `exportBytes`。它是原生 PDF 及 DOCX HTML/Markdown 导出的上限和默认值，当前为 64 MiB。DOCX 和 PPTX 编辑器的图片导出也用它作为默认值，浏览器继续执行像素和编码输出限额。

剪贴板片段以 UTF-16 单元计。XLSX 的 `drawingFragmentUnits` 为 4,194,304。PPTX 的 `textFragmentUnits` 和 `objectFragmentUnits` 分别为 1,048,576 和 100,663,296。同步会话在序列化前检查，Worker 客户端在克隆前检查。浏览器读取剪贴板 Blob 时仍使用独立的字节上限。

`addFont`、文档字节和图片在编码或向 Worker 克隆前检查；超限返回 `DocumentError("limit-exceeded", …)`。DOCX 的图片与水印属性校验器只检查结构，完整会话入口另用 `checkDocxByteInput` 应用字节限额。核心继续独立检查字体合法性、图片格式、历史与累计资源预算；RGBA 缓存累计仍最多 16 MiB。查询表示输入上限，不能解释为剩余额度；关闭后不能使用缓存继续操作。

公开示例默认随附 Liberation Sans 四种样式、Noto Sans SC 常规和 DejaVu Math TeX Gyre，共六个字体。文件与 profile 可以留空；可提供至多两个额外字体及精确映射覆盖。中文后备目前只有常规样式，替代不承诺原版分页。字体资产、来源与许可证归[示例 NOTICE](../../../examples/web-sdk/fonts/NOTICE)；构建不依赖私有测试库。当前不自动读取系统字体或访问远程字体服务，示例从自身静态资源加载字体。

策略参考 [ONLYOFFICE 字体默认项与选择](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/libfont/map.js#L2830-L2855)、[LibreOffice 字形后备](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/vcl/source/font/PhysicalFontCollection.cxx#L108-L179)；GenOffice 的[随附替代字体](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/fonts/fonts.css#L1-L8)和[非阻塞提示](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/renderer/App.tsx#L3618-L3640)定义用户体验参考。

## 默认 UI 与编辑宿主

各领域的 `@open-document/<format>/react` 提供 `mountEditor(container, options)`，分别挂载 DOCX、XLSX、PPTX 或 PDF 默认 UI。`container` 由宿主提供可测量的高度。格式由入口确定；`document` 为 `{ name, bytes }`，`resources` 明确提供 `{ engine, workerUrl, fonts, profile }`，可传对应 `budget`、`theme: "light" | "dark"`、`locale: "zh-CN" | "en-US"`、异步 `onSave`、初始 `signal` 和 `styleNonce`。接入代码与普通 JS 示例归[开发说明](../development.md#默认-web-ui)。

DOCX、XLSX、PPTX 也接受 `document: { name, blank: true }`，`OfficeDocument` 类型排除同时传入 `bytes`。包与模板由各自 MoonBit 格式模块生成，继续使用现有输入、包与输出预算；字体仍由宿主显式提供。DOCX 的 `FoundationSession/Client.execute({ operation: "createDocx", budget })` 使用 Letter 页面、一英寸边距、11 pt Times New Roman 和一个空段落。XLSX/PPTX 的具体入口和默认值归下文各格式合同。PDF 同样接受空白创建，默认生成一页 595 × 842 point 的 PDF。

返回的 `MountedEditor` 按 `format` 区分，`editor` 是当前文件的对应 Web 编辑宿主，只读属性在替换成功后指向新宿主。旧宿主释放后拒绝操作。实例提供以下方法：

| 方法 | 行为 |
| --- | --- |
| `open({ name, bytes })` | 只替换同格式文件；处理草稿/未保存修改，暂停新编辑并等待已接受队列；独立候选完成字体和首屏后替换，失败或取消保留旧会话；成功 `true`，用户取消 `false`，失败拒绝 Promise |
| `save()` | 产生原格式输出，等待 `onSave`；重复调用复用同一在途结果，回调期间可以继续编辑 |
| `create({ name })` / `open({ name, blank: true })` | 四种格式复用替换确认与独立候选，成功后成为新文件 |
| `saveAs(name)` | 使用新名称产生原格式输出；目标由宿主决定。失败保留旧名称和修改状态；成功后更新名称。不同名称不复用同一个在途输出 |
| `print()` | 使用当前核心 PDF 请求 Chrome 打印对话框，返回 `Promise<void>`；范围与平台条件见[浏览器打印](#浏览器打印) |
| `getSnapshot()` / `subscribe(listener)` | 转发当前宿主的稳定快照；外部订阅跨文件替换保持，监听器异常不改变事务 |
| `close()` | 询问草稿和未保存修改；取消 `false`，完成关闭 `true`；等待在途保存回调后重新检查 |
| `dispose()` | 明确放弃内存会话，不弹确认；取消候选、等待已接受核心操作、释放 Worker/Canvas/React/自建 DOM；重复调用等待同一个 Promise，清理失败仍继续其他清理 |
| `setTheme()` / `setLocale()` | 更新 UI；保留文档会话、Canvas 和原生输入节点 |

每个实例追加一个自建容器与 open ShadowRoot，保留调用者原有 DOM。菜单与 Dialog 的 Portal 位于实例内；关闭确认是模态，会暂时限制整个页面交互。主题、关键尺寸与基础样式在实例内定义，宿主无需 Tailwind。当前目标只有 Chrome/Chromium。

可选 `onOpen()` 将文件菜单的“打开”交给宿主，例如选择任意支持格式后重新挂载。未提供时使用当前格式的内置选择器。回调在菜单点击中直接调用，允许打开原生文件选择器；异常显示在编辑器中。宿主仍须通过 `open()` 或 `close()` 处理未保存修改，选择文件本身不确认放弃。关闭完成后，公开快照的 `closed` 为 `true`，宿主可据此显示空白页或打开入口。

框架无关的四类编辑宿主提供 `getSnapshot()`、`subscribe()`、`focus()`、`setPaused()`、`markSaved(output)` 和 `markDownloaded(output)`。快照包含会话身份、revision、导航、缩放、选区摘要、历史、诊断、停止/错误、在途操作及组合/拖动/草稿状态，并附格式当前查询。未变化时保持对象身份；已提交但绘制失败仍发布新 revision，保留保存与恢复入口。低层宿主借用 client，调用者等待宿主释放后另行关闭 client。

编辑宿主的原格式保存、Office PDF、DOCX/PPTX PNG、PPTX JPEG、XLSX CSV 和 DOCX HTML/Markdown 输出统一返回 `EditorOutput = { documentId, revision, format, bytes }`。`format` 另包含 `csv`、`png`、`jpeg`、`html` 和 `markdown`；编辑器输入格式仍为 DOCX/XLSX/PPTX/PDF。默认 UI 另加文件名 `name`。PDF 还提供 PNG/JPEG、HTML/Markdown 和原生 Office 转换；选页、分文件和清理副本即使格式仍为 PDF，也不能用 `markSaved` 确认源保存。全页图片返回按页序排列的只读 `EditorOutput` 数组，具体合同见[DOCX 页面 PNG](docx-output.md#docx-页面-png)及[PPTX 图片输出](pptx-show.md#当前页-png-输出)。此约定不改变原始 Wasm/client 的保存结果。只有该宿主 `save()` 实际产生的原格式输出可以 `markSaved`；旧会话、其他格式和任意裸 revision 都不能确认保存。确认的是输出 revision，其后新编辑仍显示未保存。导航、缩放和 UI 变化不修改文档。

原格式 `onSave` 成功才确认保存基线；失败保留修改并允许重试。缺省下载只提示“已生成下载”，不确认磁盘持久化，也不清除修改。PDF、PNG 和 CSV 导出不清除 Office 修改。关闭前选择“导出并继续”明确包含放弃内存会话。`dispose` 不等待宿主存储回调，晚到回执不更新已释放实例。

默认 UI 快照增加 `newDocument`。空白创建后即使 revision 为 0，`modified` 仍为 true；首次原格式 `onSave` 成功才清除此标记。下载不清除它，关闭与替换仍需确认。文件名去首尾空白、拒绝空名、路径分隔和控制字符；缺少当前格式扩展名时补齐。

保存回调期间若又有编辑，关闭/替换保留会话并返回 `false`。候选已经切换后，旧宿主清理失败只发布清理提示；新会话保持可用，`open` 返回 `true`。

DOCX/PPTX 的组合或拖动需要结束/取消。XLSX 保存先提交已支持的单格草稿；PDF 属性草稿须显式应用/取消。替换最多准备一个独立候选，加载界面的“取消”释放候选并恢复旧会话。核心保留原有文档校验、只读规则和预算。

### 浏览器打印

`MountedEditor.print()` 与文件菜单“打印…”共用既有输出队列。DOCX 打印全部页面，XLSX 按工作簿顺序打印全部可见表，PPTX 打印全部可见幻灯片；沿各自核心 PDF 路径保留页面设置、分页、字体、图形、诊断和输出预算。PDF 编辑器使用当前原格式输出。原生输入先经过现有屏障：XLSX 提交支持的单格草稿，其他格式的组合、拖动或属性草稿仍须结束或取消。重复打印请求复用在途输出，不再生成第二个预览。

平台将本地 PDF Blob 放入一个临时 iframe，加载后调用该窗口的 `print()`；Chrome 负责原生预览、页范围和打印机选择。实现参考 [MDN 打印示例](https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Media_queries/Printing#print_an_external_page_without_opening_it)，不使用 HTML 重新分页或截图代替矢量 PDF。宿主需允许 `blob:` iframe、内置 PDF 查看器及浏览器打印；受限容器仍遵循 Chrome 权限。Promise 完成只表示已发出打印请求，不表示用户已打印或保存。取消预览不作为文档错误，也不触发 `onSave`、下载或清除未保存状态。

每个实例最多保留一个打印 frame 与 Blob。`afterprint`、下一次打印、文件替换及释放实例会清理资源；部分 PDF 查看器不发送 `afterprint` 时保留到后三种操作。加载失败、30 秒未加载或原生调用抛错时拒绝并清理，文档与历史保持可用；释放实例会取消仍在等待加载的请求。当前验收只包含 Chromium 原生预览与生成的 PDF，不包含实体打印机或其他浏览器。

## 通用绘制输出

`@open-document/wasm/abi/drawing` 定义 `DrawingBatch`、`DrawingRegion` 和 `DrawCommand`。`DrawingBatch.regions` 是绘制区域数组。DOCX 每区对应一页，XLSX 屏幕结果对应一个视口，PPTX 对应当前幻灯片。区域包含 `width`、`height` 和有序 `commands`。区域原点在左上，坐标为 point，x 向右、y 向下。Renderer 使用 `drawRegion`。

ABI 7 在区域首条矩形裁剪覆盖整个区域时标记 `backingClip: true`。设备矩阵为原点处正向缩放、且画布尺寸等于区域缩放后向上取整的像素数时，Canvas 将该裁剪对齐至画布边界。其余裁剪使用源坐标。SDK Loader 要求 Wasm 与渲染器使用同一 ABI。

当前指令如下：

| `op` | 数据与作用 |
| --- | --- |
| `fillRect` | `rect: { x, y, width, height, color }`；颜色是六位十六进制 RGB |
| `gradientRect` / `radialGradientRect` | `rect` 与 RGBA `stops`。核心从 2–32 项源色标中保留位置 0 的最后一项、位置 1 的第一项及所有中间色标。径向指令另带 `circles: [x0, y0, r0, x1, y1, r1]`，坐标与半径单位为 point |
| `patternRect` | `rect`、point 单位的 `period`、八字节 `mask` 与两种 RGB 颜色 `zero/one`。每字节表示一行，最高位在左。`screenDevice` 为真时，轴对齐的工作区画布从矩形左上角按设备像素重复 8×8 位图 |
| `strokeRect` | `rect`、`color`、point 单位的 `lineWidth`。`screenFractional: true` 保留工作区描边的小数坐标与像素覆盖。PDF 模式沿用既有描边规则 |
| `glyphs` | 批次原点 `x/y`、`color` 和 `glyphs`；每个字形给出 `outline`、字体 em 单位数 `upem`、字体单位描边宽度 `strokeWidth`、相对 `x/y` 及 `scaleX/scaleY`，核心已确定方向与位置；`upem` 为 1–65536 的必填整数 |
| `image` | `image: { key, x, y, width, height, interpolate }`，消费已解码的图片；`interpolate` 必须为 boolean 或 null，null 使用宿主采样规则 |
| `path` | `path` 为 move/line/cubic/close 数值段，`fill`/`stroke` 为 RGB 或空串，`lineWidth` 为 point。`textRule: true` 标记一条有颜色、正线宽、无填充的水平文字装饰线 |
| `transform` | 压入有限、可逆的仿射 `matrix: { a, b, c, d, e, f }`；与当前矩阵合成 |
| `style` | fillAlpha/strokeAlpha、evenOdd、cap/join/miter、dash/dashOffset、blend（normal/multiply/difference）；设置当前图形状态 |
| `pixelCenters` | 当前作用域内的矢量路径使用设备半像素原点和分数线宽。零线宽描边把端点和控制点吸附到设备像素中心。轴对齐字形保留水平 em 宽度，按各自 `upem` 量化高度。字形原点舍入到最近的水平四分之一像素和整数行。PDF 栅格模式忽略该提示 |
| `integerScreenGlyphs` | 当前作用域内的工作区字形使用整数设备落点。字形轮廓和字号沿用原值，PDF 模式沿用原落点 |
| `clipPath` | 路径与 evenOdd；压入路径裁剪，空路径产生空裁剪 |
| `clipRect` / `restore` | 压入矩形裁剪 / 恢复最近矩阵、裁剪、样式及栅格策略；批次须平衡 |
| `layer` | opacity 为 0–1，commands 在独立透明表面绘制后按当前混合模式整体合成；子内容重叠不重复应用整层透明度 |
| `mask` | mask 与 commands 分别绘制到透明表面，以 mask 的 alpha 裁减内容后按当前混合模式合成；遮罩 RGB 不影响结果 |
| `tile` | 正数 width/height、整数 columns/rows、matrix、正数 resolution.x/y 和单格 commands；按设备采样率绘制一个图块，再用 Canvas 重复纹理合成；重复格最多 4096 个 |

临时层最多四级，layer 与 tile 各占一级，mask 占两级。子命令共享原指令/资源预算，裁剪分别平衡。单次绘制的目标与活动临时表面合计最多 16777216 像素，按各表面的实际尺寸计数。Web 按层级复用表面，分配前清理不再使用的深层表面；尺寸变化和释放时回收像素。图层不包含格式规则。

气泡图屏幕标签可提供轻度调整的字形轮廓，复用现有轮廓表和字节预算。资源键由原轮廓键、`:screen:` 和百分之一毫米字号组成，路径单位为 96 dpi 设备像素。Canvas 仅在 `pixelCenters` 作用域、轴对齐的 96 dpi 比例和无模拟描边时选用该轮廓，两个方向的原点均舍入到最近的四分之一像素。其他缩放沿用原轮廓。打印保留逻辑字形和推进量。

Canvas 对轴对齐实线的独立 move/line 子路径统一对齐轮廓与端帽，再一次填充。重叠部分只应用一次描边透明度；斜切、斜线、连通折线及虚线沿既有 Canvas 路径绘制。分数字形策略中的正负九十度文字复用 PDF 行网格，保留水平设备原点。其他角度保持原矩阵。实现归 [`pdf-pixels.ts`](../../../packages/web-core/src/pdf-pixels.ts) 和 [`drawing.ts`](../../../packages/web-core/src/drawing.ts)。

DOCX 排版将下划线和删除线标记为文字装饰线。分数栅格策略下，无旋转或剪切的装饰线复用现有轴对齐描边。PDF 按同一条矢量路径输出。[ONLYOFFICE 屏幕横线绘制](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Drawing/Graphics.js#L2178-L2230)

模拟粗体先填充原字形轮廓，再描边。Canvas 对不透明、普通混合、等比轴对齐的矢量描边，按一个设备像素的原生曲线容差分段。预算允许时用 8×8 遮罩识别窄角覆盖，同一 4×4 格内任一细格被触及即计一次。覆盖率仍按 4×4 计数和 1.5 次方换算。预算不足时使用 4×4 遮罩。位图策略、其他变换或混合状态、无法界定的轮廓和超出表面预算的描边使用 Canvas 原生描边。分段超出工作上限时，以原轮廓继续采样。

采样复用现有描边表面预算，按实际遮罩尺寸扣减。每个字形最多使用 4194304 个样本，每次区域绘制累计最多 67108864 个样本，独立于图片颜色面工作预算。实现归 [`drawing-glyphs.ts`](../../../packages/web-core/src/drawing-glyphs.ts) 与 [`pdf-stroke.ts`](../../../packages/web-core/src/pdf-stroke.ts)。原生文字对照与适用范围见[测试说明](../testing.md#当前兼容证据入口)。

位图图案的周期为 0.01–14400 pt，颜色须为六位 RGB，掩码须有八个整数行字节。Canvas 平铺一个临时表面。普通 Office 模式平滑采样。PDF 模式缩小时平均纹理，放大时通常取最近像素。轴对齐的正向平铺在宽高均为 8–30 个整数设备像素且源像素占非整数设备宽度或高度时，按原生 PDF 栅格重新取样，并向下取整平铺原点。表面计入既有层级和像素预算。PDF 导出使用无损 RGB 图像与平铺图案，保留当前变换、裁剪和局部原点，每份输出最多 4096 个图案资源。矩形外的绘制状态恢复。两色掩码和普通 Office 模式分别参照 [ONLYOFFICE 图案行](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/agg-2.4/include/agg_span_hatch.h#L746-L764)与[重复纹理的双线性采样](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/graphics/Graphics.cpp#L1676-L1708)。三份独立 Letter 控制在两种分辨率下的六组完整原生 PNG 均为 0/0。A4 原生输出的整数像素网格与固定倍率预览分别记录。资格范围见[测试说明](../testing.md#当前兼容证据入口)。

核心 `PositionedDocument.drawing(images)` 默认填充白底。`clear=false` 为透明对象层生成图元，仍保留页面裁剪；它不改变布局或源文档。

PDF 图案原点按五位小数写出，变换基向量与页面内容保留布局精度。实现归 [`write-pattern.mbt`](../../../modules/formats/src/pdf/write-pattern.mbt)，依据 [ONLYOFFICE 图案矩阵](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/SrcWriter/Pattern.cpp#L58-L74)及[实数写出精度](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/SrcWriter/Utils.cpp#L164-L199)。独立字面 PDF 的四页控制覆盖平移、剪切、反射与旋转，完整页面均为 0/0。该规则只调整派生 PDF 图案的相位精度，源像素、图案周期和屏幕绘制保持。原件与检查范围见[测试说明](../testing.md#当前兼容证据入口)。

插值随每张图片传递。PDF 读取源 `Interpolate`，省略时为 false；EMF 位图及生成的阴影明确使用 true。普通 Office 图片使用 null。DOCX 宿主对轴对齐或 90°、两个设备轴均放大的已解码位图保留源像素；缩小、剪切及实时图片保持平滑。明确的 true/false 优先，每次绘图恢复本图策略。图片字段始终序列化，包括 null，旧全局样式字段已移除。

PPTX 宿主为含透明像素的图片缓存独立颜色位图，全透明像素的 RGB 归白，颜色面的 Alpha 为 255。原始 RGBA、压缩源和资源身份保持。全不透明图片跳过该资源。普通图片的插值为 null、平滑开启且设备矩阵为正向轴缩放时，Canvas 按相同小数几何独立采样颜色与原始透明遮罩；最终八位 Alpha 合并对象透明度，再以一次像素拷贝合成。完整源覆盖的优化裁剪使用相同路径。实际源裁剪、旋转、剪切、明确的 true/false 及最近像素路径保留既有采样。派生位图随资源淘汰、替换和表面销毁关闭。

采样目标限制在 backing canvas 内。每次区域绘制按两次 RGBA 回读计入累计 67108864 像素工作预算，并沿用 16777216 活跃层像素和四层上限。源图沿用单边 4096、总计 4194304 像素上限。归白及独立遮罩依据固定 [ONLYOFFICE `CPdfWriter::LoadImage`](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/PdfWriter.cpp#L3367-L3448)，由三个透明调色板控制和普通图片编辑流程核对；未增加 JPEG 编码器。

完整页面的首个矩形裁剪与无偏移、正向轴缩放的 backing canvas 完全对应时，Canvas 将裁剪边界对齐到 backing 像素，避免最外列重复混色。保存/恢复作用域保持，页面后的批注继续绘制。局部裁剪、较大表面、偏移、反射及剪切保留原边界。DOCX 实心斜接矩形复用既有像素边缘绘制；其他路径保持原规则。

核心生成完整区域的绘制顺序和裁剪。`outlines: { key, path }[]` 与 `images: string[]` 独立于区域；批次中每个轮廓仅保留一份，TrueType 键为字体 SHA-256 与 glyph ID，原生 Type1/CFF 键为归一轮廓的 SHA-256。`addImage(key,width,height,rgba)` 返回由尺寸及 RGBA SHA-256 组成的资源身份；同一源键替换像素后返回新身份。平台位图按此身份缓存。Canvas 按完整批次淘汰上一页轮廓，开始绘制时重设样式。路径 `lineWidth: 0` 表示设备细线。

整数及 PDF 策略下，不透明的零宽实线折线在设备坐标中逐行覆盖，端点计入末行。每条路径最多生成 8192 行跨度，范围限制在画布内并沿用当前裁剪。曲线、虚线、透明描边和超出上限的路径沿原有策略绘制。行为依据固定 Poppler 的 `Splash.cc:2014–2092`，由独立 PDF 和原生散点控制核对。[实现](../../../packages/web-core/src/pdf-stroke.ts)

PDF 的矩形裁剪保留横向小数覆盖，纵向取完整设备行。细线两边舍入后重合时，向较大坐标扩展一个像素。单个及复合矩形的斜接、圆角描边共用一个轮廓。重叠区域只应用一次透明度，孔洞保持反向绕序。单条轴向线支持平头、方头与圆头。端点长度和法向线宽分别按变换计算。其他连接、虚线和混合路径沿原生 Canvas 绘制。

PDF 中声明插值的图片使用平台 `medium` 插值滤波。轴向字形保留横向小数原点，纵向取整。Office 的整数策略保持。渐变沿既有整数裁剪，普通 PDF 路径保留小数覆盖。描边几何参照 [ONLYOFFICE Splash](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/splash/Splash.cc#L7628-L8125)。PDF 的行裁剪、细线与采样按固定 [Poppler 26.05.0](https://poppler.freedesktop.org/poppler-26.05.0.tar.xz) 的 `SplashClip.cc:99–138,273–325`、`SplashXPath.cc:121–150` 核对。渐变的二值裁剪见 `Splash.cc:2431–2472`。实现归 [`pdf-pixels.ts`](../../../packages/web-core/src/pdf-pixels.ts)，未复制上游执行代码。

`layout(profile)` 返回 `PageLayout`：绘制批次、会话内 `id`、`revision`、复用计数、字体信息、profile、诊断，以及独立的 `semantics`。语义页按阅读顺序保留行文字、源位置、方向、只读原因与文字边界。宿主用它展示文本并初始化焦点；命中、光标和选区仍查询核心。完整 run、carets、图片布局和表格模型留在内部 `Layout`，供编辑几何及 PDF 使用。

宿主校验有限数值、尺寸、颜色、路径、矩阵、嵌套栈和全部资源引用。每批指令/路径段/glyph 累计最多 1048576 项，栈深度最多 32，数值绝对值最多 1e9；轮廓仍最多 8 MiB。矩阵的行列式按线性分量最大值的平方检查条件，允许尺度很小但条件良好的变换；正向与逆向的六个分量均须有限且不超过 1e9。未知指令、无效输出及缺资源明确失败。`@open-document/web-core/drawing` 的 `CanvasRenderer` 只执行这些指令，并保留独立 `shape()` 探针的绘制入口。

`CanvasSurface` 共用尺寸、DPR、透明覆盖层、绘制身份与资源释放。DOCX 的 `PageCanvas` 继续准备文档图片。相同 `id`、区域、zoom、DPR 和字形规则下，只清除并重画覆盖层；仅像素尺寸变化时重设画布尺寸。缩放、窗口 DPR 或字形规则变化重新呈现，覆盖层几何须匹配当前布局身份与 revision。

预览与编辑共用此路径。宿主在关闭时释放 Canvas、Path2D 和 ImageBitmap；内容与覆盖层共同计入像素预算。JSON/Worker 仍按批次传输。PDF writer 消费 `PositionedDocument.pages[].primitives` 的有序矩形、边框、文字、独立图片、路径、矩阵、裁剪和恢复操作。DOCX 从内部布局转换，XLSX 从独立打印布局生成，PPTX 从幻灯片布局生成；旧分组结构已删除。字体嵌入、Unicode 与裁剪仍由核心处理。

## 预算

| 字段 | 核心默认值 | 归属与约束 |
| --- | --- | --- |
| `fileBytes` | 32 MiB | archive：输入 ZIP 字节 |
| `retainedBytes` | 32 MiB | archive：保留一份原始 ZIP；不代表整个进程内存上限 |
| `entryBytes` | 16 MiB | archive/XML：单条目实际解压与修改后 XML 字节 |
| `totalBytes` | 128 MiB | archive：累积已缓存解压字节；保存校验最终包总解压大小 |
| `entries` | 4096 | archive：目录条目数 |
| `xmlDepth` | 128 | XML：元素层级，根为 1 |
| `outputBytes` | 64 MiB | archive：输出 ZIP 大小，分配前校验 |

数值必须为非负 i32；所有长度/offset 经过 checked 校验。目录索引不解压 payload，未访问条目实际解压量为零；XML/content type/关系读取计入同一缓存预算。保存核验所有原始条目，故打开成功不保证尚未读到的损坏资源能保存。预算是字节/深度边界，没有伪造耗时或峰值内存指标。

字体 probe 另固定最多 8 个字体、32 MiB 字体总量、4096 UTF-16 文本单元、1024 CSS px 字号、64 单元语言标签与 8 MiB ASCII 轮廓缓存。输入字体按顺序逐码点 fallback，face 0/default variation；BiDi 库目标 Unicode 16.0.0。glyph 的 cluster 是原文 UTF-16 offset，度量用 font units，绘制位置用 CSS px。缺字和 emoji/ZWJ/variation selector 有可定位诊断；没有完整 grapheme fallback、彩色 emoji、CFF/TTC 或任意字体质量承诺。

GSUB 每个中间字形数组最多 65536 项，cluster/mask 数组同步受限。直接、上下文替换及未匹配尾部超限均在增加长度前返回 `limit-exceeded`，不输出截断布局。失败回收本次新增轮廓，保留既有缓存和文档状态；极端字体即使格式合法，也可能因扩张数量被拒绝。

一次段落塑形的全部字体/script run 另共用 67108864 单位的查表预算。指定 OpenType 查表函数的 Result 入口、循环迭代和按长度计费的批量操作递减同一计数器；GSUB/GPOS、Coverage/ClassDef、GDEF 过滤及试探查表超限统一返回 `limit-exceeded`。字体表初次解析另有同限额。该限制可能拒绝工作量过大的合法字体，不能代表整次文档操作的时间上限、所有字体分配或进程峰值内存；具体范围与补丁身份见[依赖说明](../dependencies.md#累计查表工作量)。

## 文件 profile 与保真

ZIP 支持单磁盘非加密 ZIP32、stored/deflate、UTF-8 或未标记的 ASCII 名称、12/16 字节 data descriptor。拒绝 ZIP64、加密、未知 method/flag、截断、重叠、重复名字/目录、错误 CRC 与解压长度。保留源记录用于未改条目；ZIP 包级 comment 和修改条目的压缩方式不保证词法恒等。

旧版 Office 文件和加密 OOXML 可使用 OLE 复合容器。DOCX 打开路径读取根目录中的 `EncryptionInfo` 和 `EncryptedPackage`，检查分配链、范围和预算。旧二进制内容沿用 `unsupported-package`。依据 [Microsoft Compound File Header](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/05060311-bfce-4b12-874d-71fd4ce63aea)。

XML 支持 XML 1.0/Namespaces 1.0、UTF-8 和带 BOM 的 UTF-16 LE/BE；编码声明与实际字节必须一致。源片段 offset 统一是解码后的 UTF-16，ZIP 错误 offset 是字节，未知位置为 −1。禁止 DTD 和外部实体；没有文件/网络 entity resolver。允许普通转义/数字字符引用、CDATA、注释、PI、空元素；拒绝重复属性、无效 namespace/PI 名称、非法字符与错误语法。未改 XML 保留原字节；编辑 XML 写成 UTF-8，并更新声明，保留 standalone。

OPC 识别 content types、package/part relationships 与相对 target。关系 ID 只在 owner 内唯一，外链只作为数据返回、从不加载；内部路径不能逃出包。part 名称按 ASCII URI 和 UTF-8 percent escapes 校验，拒绝路径分隔符/非规范 unreserved escapes、尾点、大小写身份冲突和悬空关系。

DOCX 依据 officeDocument relationship、main content type 与 Word namespace 识别，支持 Transitional 主部件。查询正文中直接属于 paragraph/run 的 `w:t`，包括表格内正文；其他结构保留，未知直接 body 结构给诊断。不是 OOXML schema validator，不将未读 customXml/资源当作已理解能力。替换只允许无子元素的已知文本节点，自动转义和设置 `xml:space="preserve"`；未知 markup 保留在原位置，重复保存不累积转义。

`FoundationSession/Client.execute({ operation: "openDocx", bytes, budget, password })` 可解锁使用 ECMA-376 Standard 或指定 Agile 配置的 Transitional DOCX。Standard 使用 SHA-1 和 AES。Agile 支持 AES-128 CBC／SHA-1 和 AES-256 CBC／SHA-512。两种配置均使用单一密码密钥、16 字节盐和最多 100 万次密码迭代。Agile 在解密正文前校验整个加密流的 HMAC。[Standard Encryption](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-offcrypto/2895eba1-acb1-4624-9bde-2cdad3fea015) · [Agile 完整性校验](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-offcrypto/63d9c262-82b9-4fa3-a06d-d087b93e3b00)

原容器和明文合计受保留预算限制，解出的 ZIP 沿用正常校验。缺少密码或密码错误返回 `docx-password-required`。默认编辑器可重试和取消，密码空白原样保留。解锁后可只读查看，保存返回原加密字节。

Strict XLSX 的基础工作表可只读打开。其他 Strict 格式、上述范围以外的 Office 加密、ZIP 加密、宏主部件、签名安全改写和旧二进制格式不在支持面。签名关系可在打开阶段拒绝；签名材料仅被识别时允许只读查询，但编辑/保存拒绝，不能把签名图片或未验证的 signature 当作有效签名。

## 失败

MoonBit 共用 `Failure`，浏览器暴露 `DocumentError(code, message, part, offset)`。主要类别为 `malformed-package/xml/opc/docx/font`、`unsupported-package/xml/docx/font`、`limit-exceeded`、`missing-part/font`、`stale-revision`、`invalid-operation/budget/position`、`protected-content` 和 `closed-session`。Worker 关闭或宿主错误仍是普通 Error。失败不能返回空文档或伪造 revision；测试分别检查错误身份与输入/编辑状态。

当前使用固定 Chromium release WasmGC、独立 ZIP/XML 对照、HarfBuzz 塑形及 qpdf/Poppler 输出检查。P3 的 LibreOffice 固定参考与真实 Canvas/PDF 检查不代表全 Word 兼容；系统输入法的全面覆盖、完整 schema、PDF/A 和 PDF/UA 尚未验证。执行入口与证据规则见[测试说明](../testing.md)。
