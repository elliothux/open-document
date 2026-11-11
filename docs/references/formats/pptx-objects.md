# PPTX 对象、文字与图表

[格式合同目录](../formats.md)

### PPTX 外阴影

原生 `outerShdw` 支持普通闭合形状和图片的填充轮廓。直接属性、主题和占位符继承沿既有样式链解析，保留颜色、透明度、距离、方向和 `rotWithShape`。阴影透明度乘以填充或图片透明度；移动、旋转、缩放预览和提交沿用既有几何。复制把有效阴影写为明确属性，避免目标主题改变外观。阴影读取与几何依据 [ONLYOFFICE GraphicObjectBase](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L1111-L1477)。

主题效果中的正面正交相机、三点灯光和圆形顶部斜面可作为平面元数据保留。相机旋转须为零；灯光方向接受八个标准方向，旋转角为 0–21599999，斜面宽高为 0–2147483647 EMU。缺省旋转和斜面尺寸保持源值。绘制只采用已有外阴影，与 [ONLYOFFICE GetOuterShdw](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L10176-L10185)一致；主题的场景与斜面不生成 3D 投影。独立原生控制只移除两项主题元数据，三个完整页面仍复现冻结 PNG。未知属性、重复节点、注释/处理指令、非平面相机、挤出和其他斜面继续保护；对象直接 3D 按下述范围验证。实现归上述 [shadow.mbt](../../../modules/formats/src/pptx/shadow.mbt)，证据归[测试说明](../testing.md#当前兼容证据入口)。

对象直接 `scene3d/sp3d` 在已验证范围内作为二维元数据保留。场景接受 `orthographicFront`、零相机旋转、0–10800000 视场角、标准灯光及八方向，灯光旋转仍限 0–21599999。形状接受标准材质、顶部/底部标准斜面、挤出高度、轮廓宽度及已支持的轮廓颜色；尺寸限 0–2147483647 EMU。复用颜色与数值校验，绘制保留既有二维填充、描边和外阴影，不生成 3D 投影。依据 [ONLYOFFICE SpPr 记录](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/SpPr.cpp#L350-L360)及 [ReadSpPr 跳过场景和形状 3D](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L5573-L5646)。独立原生控制移除 C13 两页的 34 个直接节点，完整页面仍逐字节复现冻结 PNG。普通编辑、复制、历史及保存重开保留源；SmartArt 缓存的既有编辑保护保持。未知属性/预设/命名空间、重复、注释/处理指令、非正面相机和扩展节点继续保护。实现归 [object-3d.mbt](../../../modules/formats/src/pptx/object-3d.mbt)。

`effectLst/innerShdw` 的导入元数据接受单个已支持颜色声明和 `blurRad/dist/dir`。前两项为 0–2147483647 EMU，方向为 0–21599999；缺省值为零，颜色和透明度复用现有校验。已验证元数据保留原始 XML，按 [ONLYOFFICE ReadEffectLst](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L5488-L5522)读取，绘制只采用 [getOuterShdw](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L1111-L1141)取得的外阴影。内阴影本身不创建绘制资源。直接和主题效果沿既有读取链，正文及填充编辑保留元数据；对象复制在固化外阴影时保留直接内阴影节点。独立原生控制验证无填充和实色填充的 C13 对象都不因该元数据改变页面图像。未知属性/颜色、重复效果、错误命名空间、注释/处理指令和扩展节点继续保护，非法数值沿原输入错误拒绝。

MoonBit 以 144 dpi 生成临时 PNG 遮罩，Canvas 和 PDF 复用既有图片通路。路径采用非零环绕填充，曲线有界细分；模糊使用可分离三角权重，参照 [LibreOffice 阴影模糊](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/drawinglayer/source/primitive2d/GlowSoftEgdeShadowTools.cxx#L32)及 [StackBlur](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/vcl/source/bitmap/BitmapFilterStackBlur.cxx)。固定 ONLYOFFICE 的上述形状阴影路径未执行 `blurRad`，因此没有据此授予模糊像素资格。遮罩按轮廓、颜色、模糊和有效透明度去重，按需生成；保存不新增图片部件，源效果保持。

形状的仅描边阴影复用共享[描边轮廓](../../../modules/layout/src/stroke-contour.mbt)。三次曲线按既有 1/32 pt 容差有界细分，保留回折超出端点的部分。平滑闭合凸曲线使用相反绕向的内外边界，保留透明孔洞；真实角点继续应用原端帽、连接与斜接上限。曲线最多细分 12 层、4096 点，最终轮廓最多 4096 段，超限拒绝。直线路径沿原算法生成，曲面图共用同一实现。

当前接受 `sx=sy=100000`、`kx=ky=0`。单遮罩最多 4194304 像素，每轴最多 4096，模糊半径最多 128 pt；轮廓、扫描、卷积及编码继续受工作和图片预算限制。非均匀填充透明度、缩放或倾斜阴影、组合/表格/图表阴影和其他扩展效果仍保护。高倍率输出沿用 144 dpi 遮罩，整份 C13 的 Office 视觉对照尚未通过。实现归 [shadow.mbt](../../../modules/formats/src/pptx/shadow.mbt)和 [shadow-raster.mbt](../../../modules/formats/src/pptx/shadow-raster.mbt)，验证范围归[测试说明](../testing.md#当前兼容证据入口)。

### PPTX WMF 图片

矩形图片可读取内部 `image/x-wmf` 的 placeable WMF 矢量内容。支持实色或空画刷、实线或空画笔、多边形、折线、窗口原点/有符号范围、对象选择及句柄复用。窗口反向范围保留原生翻转；图元通过既有元文件布局输出到 Canvas/PDF，保存保留原 WMF 和关系。移动、缩放、旋转、翻转及同稿复制沿已有对象事务，组成员保留原有保护。读取参照 [ONLYOFFICE WMF 多边形](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/raster/Metafile/Wmf/WmfParser/CWmfParserBase.cpp#L1178-L1194)与[窗口映射](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/raster/Metafile/Wmf/WmfParser/CWmfParserBase.cpp#L1657-L1694)。实现归 [wmf.mbt](../../../modules/formats/src/internal/image/wmf.mbt)。

`duotone` 接受两个不透明颜色端点，复用主题色及已有颜色变换。双色按原图颜色亮度映射，`alphaModFix` 乘入图元透明度。未见 ONLYOFFICE 的上述图片绘制通路执行双色变换；实现参照次级 [LibreOffice BitmapDuoToneFilter](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/vcl/source/bitmap/BitmapDuoToneFilter.cxx#L15-L49)与[整数亮度](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/include/tools/color.hxx#L274-L277)，GenOffice 仅作视觉验收。实现归 [picture-metafile.mbt](../../../modules/formats/src/pptx/picture-metafile.mbt)，原色和效果标记继续原样保存。

矩形 WMF 图片可读取并编辑 `a:srcRect`。核心把保留的源区域映射到原图框，沿图框裁剪 Canvas 和 PDF 的矢量内容。默认裁剪控件沿用原校验、锁定和精确历史。裁剪只写当前图片的源矩形，保留 WMF、双色效果和图框。

共享路径样式直接携带奇偶填充规则。WMF 与 EMF 共用 Canvas 的填充规则及 PDF 的 `f*/B*` 运算，取消同一路径的裁剪再填充，避免边缘覆盖重复计算。其他路径显式保持非零填充。实现归 [metafile.mbt](../../../modules/layout/src/metafile.mbt)、[positioned.mbt](../../../modules/layout/src/positioned.mbt)与 [PDF 写出](../../../modules/formats/src/pdf/write.mbt)，既有 TypeScript 绘制字段保持。

输入最多 4 MiB、8192 条记录、256 个对象句柄和 65536 个路径段。校验 placeable 校验和、文件与记录边界、对象状态及绘制坐标。未知记录、调色板、位图、文字及其他光栅运算继续保护。当前 WMF 图片的平铺、目标内缩、阴影和其他外观编辑仍保护；跨稿剪贴板复制也保持保护，避免遗漏原资源。整页资格见[测试说明](../testing.md#当前兼容证据入口)。

### PPTX 存储 OLE 预览

`graphicFrame` 的 OLE 对象可读取内部存储的 EMF 矢量预览。支持矩形、无裁剪、无图片效果且与外框一致的图片框。使用原生 `p:pic` 或 `mc:Fallback`，保留原始 XML、EMF 及关联数据。查询返回 `kind: "ole"`，标签进入可访问文字。对象外观、内容编辑、复制和激活保持保护；幻灯片背景仍可编辑，保持精确历史与保存重开。外链工作簿只保留来源，不发起获取。

共享 EMF 读取支持实色多边形、三次曲线、闭合路径、奇偶/非零填充、单矩形裁剪、正等比轴向变换及实色几何画笔。透明水平 Unicode 文字支持顶部/基线对齐，保留 UTF-16 原始字距。字体仍由宿主提供。绘制复用现有路径、裁剪与文字命令，单稿元文件输出计入既有 262144 单位预算。单文件、记录、句柄、位图及文字预算沿用[DOCX OLE](docx-content.md#docx-内嵌-ole-预览)。

按 [MS-EMFPLUS 的 Dual 结构](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-emfplus/8b9363ba-cf5b-4d35-bced-0620e3b5b5ef)，校验 EMF+ 记录边界后读取完整的传统 EMF 流。仅含 EMF+、非等比或旋转变换、复杂区域、颜色管理、未知画笔和栅格运算仍拒绝。PPTX 元文件内的位图资源尚未接通，遇到时保持诊断。

实现归 [PPTX OLE 读取](../../../modules/formats/src/pptx/ole-preview.mbt)、[GDI 状态](../../../modules/formats/src/internal/image/emf-state.mbt)、[GDI 路径](../../../modules/formats/src/internal/image/emf-path.mbt)及[共享元文件布局](../../../modules/layout/src/metafile.mbt)。固定 ONLYOFFICE 的 [FillPie 处理](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/raster/Metafile/Emf/EmfInterpretator/CEmfInterpretatorSvg.cpp#L1445)为空；该原件以预先准备的 LibreOffice 完整图像验收，并保留主参考缺口，见[测试说明](../testing.md#当前兼容证据入口)。

### PPTX 对象剪贴板

对象模式的 `copyPptx` 返回 `{ text, fragment, reason }`。本地顶层形状、PNG/JPEG/GIF 图片、普通表格、普通图表、嵌入音视频及完整组合可生成独立原生快照。复制保留源位置、层次、几何、旋转/翻转、图片裁剪、填充、描边、文字及点击/悬停外链和导航动作；主题字体、颜色和线性渐变写为明确源外观。继承占位符沿用既有复制保护；未选对象和其他源资源不进入快照。源文稿修改或关闭后仍可重复粘贴。

整表快照保留网格宽度、行高、合并归属、格内文字/段落、边距、锚定、底色和边框。源表样式的区域、字体和颜色冻结后随片段转移，目标分配独立样式身份；同名源样式不覆盖目标，未选样式不进入快照。直接边框与区域边框分别保存，保留原生共享边的优先级。样式目录不存在时原子创建中性默认目录，已有无样式表格不被附加新外观。一批多个表样式、图片和链接沿同一资源历史提交；重复粘贴保持独立，保存重开后仍可输入及修改表结构。源格式解析参考 [ONLYOFFICE 表格源格式复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicFrame.js#L1040-L1095)，实现归 [`object-clipboard-table.mbt`](../../../modules/formats/src/pptx/object-clipboard-table.mbt)及[既有表样式资源事务](../../../modules/formats/src/pptx/table-style-resource.mbt)；未复制上游执行代码。

普通图表快照保留当前支持类型的标题、标签、系列数值/空值、图例、圆环孔径和原生外观。复制先核对图表缓存与嵌入数据，片段只携带所用数据；粘贴时创建独立图表、关系及一个仅含普通值的 XLSX。文字标签保留前导零和字面等号，不转为公式；源工作簿的其他工作表和未选对象不进入快照。嵌入数据固定读取首个数据表，不受保存时的活动表影响。源数据不一致、公式、附加图表资源和未知外观继续保护。重复粘贴后可分别通过原图表数据面板修改，源修改/关闭不改变已有快照。实现归 [`object-clipboard-chart.mbt`](../../../modules/formats/src/pptx/object-clipboard-chart.mbt)、[严格原生缓存读取](../../../modules/formats/src/internal/chart/read.mbt)及 [XLSX 数据写入](../../../modules/formats/src/xlsx/chart-data.mbt)；源格式复制参考 [ONLYOFFICE 图表源格式复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L8855-L8870)，未复制上游执行代码。

`pastePptxObjects` 接受 `revision`、`fragment` 和字体 `profile`，向当前可写页插入快照并返回 `PptxQuery`。每次粘贴分配新对象身份和独立资源，重映射组内引用及目标关系。源位置保留，对象放到当前页顶层。对象、图片、图表及嵌入数据、关系、内容类型和选择合为一项精确历史。缺字体、损坏资源、引用不完整、冲突继承制表位、活动候选或预算失败均不提交。Web 通过 `objectFragmentResourcesPptx` 一次提取图片和媒体，并用 `verifyImages: true` 请求核心验证支持的 PNG/JPEG。浏览器验证其余图片和媒体，再复核 revision 与选择。预检失败保留文稿。

本地嵌入音视频快照携带原字节、封面、位置和循环/音量/静音。每次粘贴创建目标文稿自己的媒体部件和标准 audio/video、Microsoft media 双关系；播放属性使用新的对象与时间身份，保留目标已有动画及设置。静态输出沿用原封面，重开后可继续播放和修改属性。源媒体动作和其他动画时序不进入对象快照；外链、冲突关系和未知媒体元数据继续保护。`objectFragmentMediaPptx` 接受 revision/fragment，返回 Wasm/Web 导出的 `PptxFragmentMedia[]`，每项为 `{ kind, contentType, bytes }`，bytes 使用 Base64。核心检查容器与独立媒体预算，Web 使用现有本地解码器核实实际数据和类型；同步宿主承担解码。实现归 [`object-clipboard-media.mbt`](../../../modules/formats/src/pptx/object-clipboard-media.mbt)，原生媒体身份复制参考 [ONLYOFFICE UniMedia/NvPr](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L8230-L8307)和[图片对象复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L162-L197)，未复制上游执行代码。

默认 Copy/Cut 写入 `text/plain` 和 Chromium 自定义类型 `web application/x-open-document-pptx-objects`。默认源格式粘贴、`PresentationEditor.pasteClipboard()` 和对象输入的 Ctrl/Meta+V 走同一路径；剪切在系统写入成功并复核会话、revision 和选择后删除源。对象快照最多含 256 个顶层对象和 256 项资源，原生 XML 及每项图表 XML 最多 1 Mi UTF-16，完整 JSON 最多 96 Mi UTF-16。图片压缩字节合计最多 2 MiB，图片编码、表样式、图表 XML 和链接的资源值合计最多 2796204 UTF-16，输入及目标页解码图片各最多 16 MiB。媒体另限每项 16 MiB、合计 64 MiB 和 64 项，仍沿[媒体历史预算](pptx-show.md#嵌入音视频)。表格、图表数据、样式目录、ABI、包和显式宿主预算继续生效，可能先达到其上限。

组内局部选择、跨格富文本片段、字段/公式、具体幻灯片目标及未知对象源继续保护；带注释/处理指令的待重写表属性、样式和图表同样保护。对象复制失败不丢弃对象后降为纯文本。实现归 [`object-clipboard.mbt`](../../../modules/formats/src/pptx/object-clipboard.mbt)、[`object-clipboard-style.mbt`](../../../modules/formats/src/pptx/object-clipboard-style.mbt)、[`object-clipboard-read.mbt`](../../../modules/formats/src/pptx/object-clipboard-read.mbt)和 [`object-clipboard-paste.mbt`](../../../modules/formats/src/pptx/object-clipboard-paste.mbt)。复用既有原生对象复制、源格式解析、图片资源及多部件历史。

### PPTX 文字富文本片段

DrawingML `cap=all/none` 沿字符属性继承，缺省为 `none`。共享 `TextStyle.caps` 负责字形和显示文字，逻辑原文、UTF-16 光标与选区保持。普通输入和格式修改保留声明；清除字符格式移除直接 `cap` 并恢复继承。文字片段和完整对象复制把有效值写成明确的 `all/none`，避免目标样式改变大小写。有效的 `small` 和非法枚举继续保护；已被直接 `none` 覆盖的合法 `small` 不生效。枚举依据 [ONLYOFFICE TextCaps](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Limit/TextCaps.cpp#L42-L65)，读取映射依据 [ONLYOFFICE RunPr](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L8970-L8992)。实现归 [text-read.mbt](../../../modules/formats/src/pptx/text-read.mbt)及既有片段事务；尚无独立大小写控件或格式补丁。

`copyPptx` 返回 `{ text, fragment, reason }`。普通形状或一个表格主格的文字范围可生成独立原生片段，保留混合字体、字号、字符间距、粗斜体、颜色、下划线、删除线、高亮和上下标，以及段落对齐、方向、缩进、行段距、列表级别/起点/标记样式和制表位。核心把继承的字体和主题色写为明确字体名与 RGB。源文稿后续编辑、关闭或主题变化不改变快照。范围按 UTF-16 字素边界处理，保留软换行及空段落。

文字点击与悬停外链和导航动作分别随片段转移，保留 HTTP/HTTPS/mailto 地址、提示、目标窗口和已知点击标记。目标文稿创建或复用自己的关系，不沿用源关系 ID；一批多个地址与重复粘贴保留独立目标，同地址可以共用关系，修改一个副本时不改变其他副本。链接和文字合为一项精确源/资源历史，缺字体、无效地址或预算失败均不留下关系。点击和悬停可以指向不同地址，也可共享同一关系；只有悬停链接的文字范围同样支持。普通对象及完整组合使用相同的目标校验和资源重映射。两类链接分别保留原生 `hlinkClick` 与 `hlinkMouseOver`，修改点击链接保留悬停源。复制、粘贴及排版不请求外链。悬停源随原格式保存，PDF 仍只导出点击链接；自动悬停动作不属于此剪贴板增量。原生字段依据 [ONLYOFFICE RunProperties 读写](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/RunProperties.cpp#L288-L291)、[两类链接输出](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/RunProperties.cpp#L458-L459)及[对象链接独立复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L8149-L8165)。实现归 [`text-clipboard-links.mbt`](../../../modules/formats/src/pptx/text-clipboard-links.mbt)，链接值和提示随原生段落复制参考 [ONLYOFFICE ParaHyperlink.Copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Hyperlink.js#L80-L88)。

`pastePptxFragment` 接受 `revision`、`fragment` 和字体 `profile`，在当前文字选区内提交一次历史，返回 `PptxQuery`。目标限于一个形状或一个主格；跨格富文本粘贴仍受保护。范围外 run 保留原生源，保留前缀或尾部的边界段落沿用目标段落属性，完整替换的段落采用源属性。目标继承制表位若会额外混入来源段落，核心原子拒绝。缺字体、损坏 XML、关系/未知节点、无效范围、旧 revision、活动候选或预算失败不改变源、选择和历史。

默认 Copy/Cut 同时写 `text/plain` 和 Chromium 自定义类型 `web application/x-open-document-pptx-text`。`PresentationEditor.pasteClipboard()`、文字输入的 Ctrl/Meta+V 和默认“按源格式粘贴”读取原生片段；外部普通文字沿既有范围输入。异步读写后核对会话、revision 和选择。剪切仅在系统写入成功后删除源。显式 `paste(text)` 和原生纯文本粘贴事件继续接受普通文字。

片段最多 1 Mi UTF-16、256 段及 256 个不同链接目标；链接地址和单项元数据各不超过 2048 UTF-16。粘贴后的整个对象文字最多 32767 UTF-16。跨格复制保留既有 TSV；字段、公式、具体幻灯片目标、文字透明度和不支持的文字源返回 `fragment: null` 及原因，保留普通文字复制。具体幻灯片链接须先具备目标页转移，避免误指向另一文稿的同名路径。跨格富文本和更广文字格式继续实施。实现归 [`text-clipboard.mbt`](../../../modules/formats/src/pptx/text-clipboard.mbt)、[`text-fragment-paste.mbt`](../../../modules/formats/src/pptx/text-fragment-paste.mbt)及 [`clipboard-input.ts`](../../../packages/docx/src/web/clipboard-input.ts)。解析后冻结源字体/主题色参考 [ONLYOFFICE 源格式捕获](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L7837-L7846)；未复制上游执行代码。

### PPTX 自定义路径

原生 `custGeom` 复用已有路径、文字、填充、裁剪、命中与事务。对象查询的 `preset` 为 `custom`。当前接受单个路径的移动、直线、三次贝塞尔曲线、椭圆弧和闭合命令，保留 `fill=norm/none` 与独立 `stroke` 开关。公式支持 `val`、`*/`、`+-`、`?:`、`abs`、`min`、`pin` 和 `cos`；按声明顺序求值，未知或重复导引及其他命令继续保护。原生 XY 手柄元数据校验后保留，调节控件尚未实现。图形尺寸变化时重新计算路径、文字矩形和连接点，预览取消不改源。

导引沿 ONLYOFFICE 的毫米单位求值，数值路径坐标按 EMU 或声明的路径框缩放；文字框和连接点使用导引空间。椭圆射线角与路径比例先转换为参数角，再按象限生成原生三次曲线。填充采用非零绕数，支持非单调曲线、孔洞和框外部分；描边复用既有曲线命中。图片、渐变和阴影沿真实路径边界，未填充折线的外阴影使用端帽、连接和斜接轮廓，再进入既有覆盖与模糊计算。曲线的纯描边阴影仍保护。

每对象最多 128 个导引、256 个连接点及 4097 条展开路径命令；公式最多 256 字符，导引名最多 128 字符。常量采用有符号 32 位整数，除零、非有限值及超限值拒绝。每页路径继续受绘制、图片和阴影预算限制。连接点索引为 0–255，并按目标实际点数检查；无目标端点仍要求索引零。源导引、未改部件和组保护保持，移动、缩放、外观、复制与精确历史沿既有命令。实现归 [custom-geometry.mbt](../../../modules/formats/src/pptx/custom-geometry.mbt)、[custom-arc.mbt](../../../modules/formats/src/pptx/custom-arc.mbt)、[path-hit.mbt](../../../modules/formats/src/pptx/path-hit.mbt)和 [stroke-contour.mbt](../../../modules/layout/src/stroke-contour.mbt)。单位与公式依据 [ONLYOFFICE Geometry](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Geometry.js#L159-L285)、[路径缩放](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Path.js#L696-L842)和[圆弧转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/ArcTo.js#L43-L245)，未复制执行代码。

### 更改形状类型

扇形 `pie` 已接通读取、插入、类型修改、填充、图片裁剪、阴影、复制、变换及精确历史。原生 `adj1/adj2` 保留以 1/60000 度计的起止角，默认 0/16200000，计算时限制为 0–21599999。轮廓按顺时针跨越零度，起止相同表示一周；非圆椭圆先把中心射线转换为椭圆参数，再按象限分段。填充按扇区命中，空白角区不命中；两条半径和曲线描边可选择。文字采用椭圆内接矩形，四个连接点依次为右、下、左、上。角度调节控件尚未实现，未知或重复导引继续保护，非法数字拒绝打开。实现归 [pie.mbt](../../../modules/formats/src/pptx/pie.mbt)，依据 [ONLYOFFICE 扇形预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L6448-L6486)及[椭圆弧](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/ArcTo.js#L42-L245)，未复制上游执行代码。

圆角矩形标注 `wedgeRoundRectCallout` 已接通读取、插入、类型修改、文字、填充、描边、阴影、复制、变换及精确历史。`adj1/adj2` 分别表示尾尖相对框中心的横向宽度比例与纵向高度比例，`adj3` 表示圆角半径占短边的比例，默认 `-0.20833/0.625/0.16667`。原生导引按十万分之一保存，接受有符号 32 位整数常量；按原生公式显示，不将其钳制到普通圆角范围。四段圆弧、尾尖方向、文字留白和五个连接点共用核心几何。填充按真实轮廓命中，描边保持既有容差；框外尾部可选择，渐变、图片、平铺及阴影使用实际轮廓边界，资源上限保持。尾部和圆角调节控件尚未实现，原导引随普通编辑保留；未知、重复或扩展导引继续保护，非法数字拒绝打开。实现归 [callout.mbt](../../../modules/formats/src/pptx/callout.mbt)，依据 [ONLYOFFICE 圆角标注预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L9007-L9095)，未复制执行代码。

文字框继承的 `prstTxWarp=textNoShape` 表示不变形，按普通文字布局。读取采用最近的声明，并检查空导引及已知属性；其他变形和扩展元数据仍保护。读取与源保存继续沿 [text-read.mbt](../../../modules/formats/src/pptx/text-read.mbt)，语义依据 [ONLYOFFICE 普通文字判断](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2094-L2104)。

闪电形 `lightningBolt` 已接通创建、类型修改、复制、文字、精确历史和默认控件。十一顶点闭合轮廓沿原生 21600×21600 坐标缩放，凹口按多边形命中；描边沿既有屏幕容差处理。文字区域为 `(8757w/21600,7437h/21600,13917w/21600,14277h/21600)`，再叠加正文边距。七个连接点保留原生顺序并沿既有矩阵变换。预设没有调节导引；非空导引、注释和处理指令保留源并保护编辑。实现复用 [polygon-shapes.mbt](../../../modules/formats/src/pptx/polygon-shapes.mbt)和 [connection-sites.mbt](../../../modules/formats/src/pptx/connection-sites.mbt)，依据 [ONLYOFFICE 闪电形预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L5825-L5862)，未复制上游执行代码。

心形 `heart` 已接通创建、类型修改、复制、文字、精确历史和默认控件。原生轮廓由两段三次贝塞尔曲线闭合，Canvas/PDF 共用同一路径；凹口和下角不按矩形命中，曲线略超出对象框的部分仍可选择。文字区域为 `(w/6,h/4,5w/6,2h/3)`，再叠加正文边距。连接点按原生顺序为 0 凹口 `(w/2,h/4)` 和 1 底部 `(w/2,h)`，沿既有矩阵变换。心形没有调节导引；非空导引、注释和处理指令保留源并保护编辑。实现归 [heart.mbt](../../../modules/formats/src/pptx/heart.mbt)，依据 [ONLYOFFICE 心形预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L4573-L4595)，未复制上游执行代码。

圆环 `donut` 已接通原生预设、创建、类型修改、外观、复制、变换、历史和默认控件。`adj` 表示厚度占短边的比例，默认 0.25，编辑范围为 0–0.5；手柄在左侧中线水平移动。轮廓使用外椭圆和反向内椭圆，内圈的两个半径分别减去 `短边×adj`，Canvas/PDF 保留真实孔洞。空孔不命中环带，可选中下层对象；内外描边沿同一路径命中，已有文字仍可在原生内接文字矩形中进入编辑。文字矩形与八个连接点使用外椭圆的原生 45°/轴向位置，再叠加正文边距。厚度为 0 时无填充环带，为 0.5 时孔洞退化；无变化不写历史，未知导引表达式保留源并保护编辑，非法数字拒绝打开。实现归 [donut.mbt](../../../modules/formats/src/pptx/donut.mbt)，依据 [ONLYOFFICE 圆环预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L2928-L2967)，未复制上游执行代码。

左上双向箭头 `leftUpArrow` 和折弯向上箭头 `bentUpArrow` 已接通原生轮廓、文字区域、连接点和三个 XY 调节值，沿既有插入、类型修改、外观、复制、变换、历史及 Canvas/PDF 使用。`adj1/adj2/adj3` 默认均为 0.25，分别表示箭身宽度、箭头半宽和箭头长度占短边的比例。左上双向箭头的上限依次为 `2×有效 adj2`、0.5、`1−2×有效 adj2`，轮廓有 12 个顶点和 8 个连接点；折弯向上箭头三项独立限制为 0–0.5，轮廓有 9 个顶点和 6 个连接点。改变联动上限只改变有效值，保留其他源常量。两个预设的箭头宽度手柄在顶部沿水平移动，箭头长度沿垂直移动；箭身手柄分别位于弯角内侧及左边箭身上缘。文字区域按原生水平箭身矩形计算，再叠加 bodyPr 边距；细箭身仍检查固定框容量，可显式使用既有缩小或自动尺寸。折弯向上箭头允许箭身伸出原框，填充、描边命中和输出保留实际轮廓。未知导引仍保留源并诊断。实现归 [elbow-arrows.mbt](../../../modules/formats/src/pptx/elbow-arrows.mbt)，依据 [ONLYOFFICE 左上双向箭头](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L5773-L5829)及[折弯向上箭头](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L1275-L1321)，未复制执行代码。

单圆角 `round1Rect`、同侧圆角 `round2SameRect`、对角圆角 `round2DiagRect` 和剪圆角 `snipRoundRect` 已接通插入、类型修改、文字、命中、连接线、复制及默认控件。单圆角的 `adj` 默认 0.16667，控制右上圆角；同侧和对角圆角的 `adj1/adj2` 默认 0.16667/0，分别控制上下两组角和左上/右下与右上/左下。剪圆角默认 0.16667/0.16667，分别控制左上半径和右上剪角。各比例按短边计算并限制为 0–0.5，支持独立数值修改、水平 XY 手柄和恢复；旧 `roundRect` 沿同一逐角三次贝塞尔路径绘制。文字内框保留原生 0.29289 圆角留白和半剪角留白，再叠加框内边距。连接点顺序在单圆角为上、左、下、右，其余三种为右、下、左、上。填充与描边分别命中真实圆角或剪角；未知导引保持保护，旋转/翻转、原生输入、精确历史、保存重开和 Canvas/PDF 共用现有路径。实现归 [rounded-rectangles.mbt](../../../modules/formats/src/pptx/rounded-rectangles.mbt)，依据 [ONLYOFFICE 圆角预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L7101-L7219)及[剪圆角](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L7382-L7417)，未复制执行代码。

单剪角 `snip1Rect`、同侧剪角 `snip2SameRect` 和对角剪角 `snip2DiagRect` 已接通插入、类型修改、文字、命中、复制及默认控件。单剪角使用 `adj`，默认 0.16667；同侧剪角的 `adj1/adj2` 默认 0.16667/0，分别控制上下两组角；对角剪角默认 0/0.16667，分别控制左上/右下与右上/左下。剪角长度按短边计算，比例限制为 0–0.5；两个导引独立修改和恢复。文字区域按原生剪角避让，再叠加框内边距。水平 XY 手柄和连接点依次按原生定义定位，连接点顺序为右、下、左、上。未知、重复或非数值公式导引继续保护；旋转/翻转、精确历史、保存重开和 Canvas/PDF 复用既有几何。依据 [ONLYOFFICE 剪角矩形](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L7290-L7383)，实现归 [`polygon-shapes.mbt`](../../../modules/formats/src/pptx/polygon-shapes.mbt)及既有调节事务，未复制执行代码。

`editObjects({ action: "shapeType", preset })` 修改对象模式中所选本地闭合形状的原生 `prstGeom`，支持单选、多选及同组成员。目标采用已有插入目录的闭合预设，排除 `text` 和 `line`；两者分别是插入文本框的命令名称和开放路径。文本框的矩形源也可改为闭合形状，保留既有非可视属性。`PptxObject.shapeTypeReason` 返回修改保护原因。默认面板复用“对象类型”选择器，并提供“更改所选形状”按钮；Wasm/Web 的 `pptxInsertKinds` 共用同一目录。

修改保留对象身份、源变换、文字/格式、填充/描边、资源与关系。改变类型时移除旧调节值，采用目标预设默认值；选择当前类型不新增历史，也不重置已有调节值。缺少本地几何时按 XML 顺序添加覆盖。新文字内框沿既有布局与自动适配，在同一事务提交尺寸或缩小值。旋转/翻转、组边界、字体、包和历史预算继续适用；任一目标失败整体回滚。未知几何、保留标记、锁定及继承对象继续保护，组内未知几何同样保护。

已有连接引用随受支持闭合预设之间的类型修改重映射到最近的有效连接点，保留目标身份，并沿既有矩阵和连接线归一化更新源端点。目标预设尚无连接点支持时原子拒绝，保留原连接。连接点范围归[连接线](#连接线)。Canvas、PNG、PDF 和命中复用当前几何路径。类型修改、周边原生文字输入、无操作、精确混合历史及保存重开已检查。实现归 [`shape-type.mbt`](../../../modules/formats/src/pptx/shape-type.mbt)及[既有连接线事务](../../../modules/formats/src/pptx/connector-edit.mbt)，几何替换和重新适配参考 [ONLYOFFICE changePresetGeom](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L6380-L6405)，未复制上游执行代码。

圆角矩形使用 `roundRect`，实心箭头使用四个单向、左右/上下双向、三向及四向的标准 DrawingML 预设；新对象使用默认调节点。读取圆角 `adj`、单向/双向箭头 `adj1/adj2` 的 `val` 数值公式，按预设上下限和实际宽高计算路径、文字矩形及命中；未知调节点或公式保留源并诊断。文字矩形先于 bodyPr 内边距，新增/复制时继续检查实际容量。Canvas 与 PDF 使用同一路径，旋转和局部翻转使用同一矩阵。

三角形 `triangle`、直角三角形 `rtTriangle`、菱形 `diamond`、平行四边形 `parallelogram` 和梯形 `trapezoid` 已接通导入、插入、文字编辑、轮廓命中及 Canvas/PDF。路径和文字矩形依据 [ONLYOFFICE CreateGeometry](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8500-L8550)，实现归 [`polygon-shapes.mbt`](../../../modules/formats/src/pptx/polygon-shapes.mbt)。三角形的 `adj` 是顶点横向比例，默认 0.5，范围 0–1；平行四边形及梯形的 `adj` 是斜边偏移占短边的倍数，默认 0.25，上限分别为宽/短边及宽/(2×短边)。导入数值按几何上限夹取；编辑值越界则拒绝。直角三角形和菱形没有调节项。文字矩形先计算，再加框内边距。数值修改、恢复预设、多选保护、保存和精确历史复用既有命令；单一 `adj` 的面板批量修改要求相同预设。复杂自定义几何继续实施，已支持预设的指针调节沿下述候选入口。

七边形 `heptagon`、十边形 `decagon` 和十二边形 `dodecagon` 已接通插入、类型修改、文字、命中、复制、连接线和精确历史。三者为固定轮廓，无可编辑调节值或手柄；轮廓和原生连接点分别为 7、10、12 个，文字内框沿对应导引计算。七边形仅接受默认 `hf=102572`、`vf=105210`，十边形仅接受默认 `vf=105146`，十二边形保留原生 21600 坐标系的取整比例；未知、自定义归一化及公式导引继续保护。几何依据 [ONLYOFFICE heptagon](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L4594-L4634)、[decagon](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L2811-L2850) 和 [dodecagon](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L2890-L2927)，复用既有多边形模块，未复制执行代码。

五边形 `pentagon`、六边形 `hexagon`、八边形 `octagon`、十字 `plus` 和五角星 `star5` 已接通同一导入、插入、文字区域、命中、外观、变换、复制、历史和 Canvas/PDF。六边形的 `adj` 是短边偏移，默认 0.25，上限宽/(2×短边)；八边形切角默认 0.29289，十字内缩默认 0.25，五角星内半径默认 0.19098，三者上限均为 0.5。五边形没有可编辑调节项。默认面板提供类型及对应调节值、恢复预设。读取并保留默认 hf/vf 归一化参数，自定义比例及未知公式保持保护；零宽导入框不产生非有限坐标。依据 [ONLYOFFICE 六边形](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L4635-L4674)、[八边形与五边形](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L6348-L6451)、[十字](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L6570-L6607)及[五角星](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8052-L8111)，实现复用上述多边形模块。

四角星 `star4` 和八角星 `star8` 已接通同一插入、类型修改、内半径、连接点、文字和历史路径。两者 `adj` 范围均为 0–0.5，默认分别为 0.125 和 0.375；不含归一化导引，未知导引继续保护。四角星具有 8 个轮廓顶点、4 个轴向连接点，八角星具有 16 个轮廓顶点、8 个连接点；文本矩形和纵向 XY 手柄沿原生导引计算。几何依据 [ONLYOFFICE star4](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8022-L8051)与 [star8](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8218-L8274)，未复制执行代码。只有一个无项目符号的空段落时，保留字体和光标测量，但不把空行高度当作可见文字溢出；宽度检查保持。新增带文字固定框仍检查实际容量，原生输入继续保留溢出文字并报告诊断。

七角星 `star7`、十六角星 `star16`、二十四角星 `star24` 和三十二角星 `star32` 已接通相同编辑路径。七角星默认 `adj=0.34601`，仅接受标准归一化 `hf=1.02572`、`vf=1.05210`；其余三种默认 `adj=0.375`，四种均限制在 0–0.5。轮廓分别为 14/32/48/64 个顶点，保留原生取整系数；文字内框和纵向 XY 手柄沿原生导引计算。连接点数量分别为 7/16/4/4，按原生顺序写回。几何依据 [ONLYOFFICE star7](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8149-L8217)、[star16](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L7602-L7709)、[star24](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L7710-L7845) 和 [star32](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L7846-L8021)，未复制执行代码。

十角星 `star10` 和十二角星 `star12` 已沿同一插入、类型修改、内半径、文字、连接线与历史路径接通。两者 `adj` 均为 0–0.5，默认分别为 0.42533 和 0.375；十角星保留标准 `hf=105146`，自定义归一化继续保护。轮廓分别为 20/24 个顶点，连接点分别为 10/12 个，文字矩形与纵向手柄使用原生导引。依据 [ONLYOFFICE star10](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L7458-L7527)与 [star12](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L7528-L7601)，未复制执行代码。

六角星 `star6` 已接通相同的导入、插入、类型修改、文字输入、命中、复制与 Canvas/PDF 路径。内半径 `adj` 默认 0.28868，范围 0–0.5；标准横向归一化 `hf=115470` 保留，其他归一化继续保护。设框宽高为 `w/h`，内顶点横半径为 `w*1.1547*adj`，纵半径为 `h*adj*sin(π/3)`；文字矩形取其内接范围。六个原生连接点按右上、右下、下、左下、左上、上排列。内半径最大值可使两个顶点伸出原始框，命中按实际多边形轮廓判断。XY 手柄位于 `(w/2,h/2-h*adj)`，旋转和翻转沿既有逆矩阵。数值修改、恢复、预览/取消及提交沿同一历史，未知导引和预算失败保持保护。几何依据 [ONLYOFFICE star6](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8105-L8151)，未复制执行代码。

燕尾形 `chevron` 和五边形箭头 `homePlate` 沿同一插入、类型修改、外观、文字和资源事务使用。两者的 `adj` 表示箭头长度占短边的倍数，默认 0.5，上限宽/短边；数值控件和顶部 XY 手柄共用既有候选、取消和单项历史。燕尾形为六顶点凹多边形，缺口与箭头等长；缺口小于半宽时文字区域左右各内缩一个缺口，达到半宽时采用原生整框文字区域。五边形箭头保留平直左边，文字区域仅右边内缩半个箭头长度。四个连接点按原生顺序生成，并随调节及变换更新。路径、文字矩形和连接点参考 [ONLYOFFICE chevron](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L1839-L1864)与 [homePlate](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L4676-L4698)，实现复用 [`polygon-shapes.mbt`](../../../modules/formats/src/pptx/polygon-shapes.mbt)和 [`connection-sites.mbt`](../../../modules/formats/src/pptx/connection-sites.mbt)，未复制上游执行代码。

左右双向箭头使用 `leftRightArrow`，上下双向箭头使用 `upDownArrow`。两者沿原插入、查询、复制、变换与原生文字编辑命令使用，默认面板提供对应类型。核心生成十顶点的闭合轮廓，两端箭头及中间箭身共用命中、文字内框和 Canvas/PDF。`adj1` 控制箭身比例，`adj2` 控制每端箭头长度，默认均为 0.5；每端最多占方向长度的一半。文字内框在两端同时内缩，先于原有四边文字边距；细箭身仍检查固定框容量，可使用既有缩小或自动尺寸设置。两个 XY 手柄分别调整箭身及箭头，箭身手柄随当前箭头长度移动。预览不改源，取消保持原包，提交与文字适配合为一项精确历史；副本的调节值独立保存。导入超范围常量按预设钳制显示并保留源，未知公式继续保护。实现归 [`preset-shapes.mbt`](../../../modules/formats/src/pptx/preset-shapes.mbt)、[`shape-adjustment.mbt`](../../../modules/formats/src/pptx/shape-adjustment.mbt)和 [`adjustment-gesture.mbt`](../../../modules/formats/src/pptx/adjustment-gesture.mbt)，依据 [ONLYOFFICE 左右双向箭头](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L5280-L5317)和[上下双向箭头](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8594-L8634)，未复制上游执行代码。

四向箭头使用 `quadArrow`，默认 `adj1/adj2/adj3` 均为 0.225。核心按原生 24 顶点闭合轮廓绘制和命中，文字矩形先于四边文字边距。三个调节值均以短边为基准：`adj2` 是箭头半宽，范围 0–0.5；`adj1` 是箭身宽度，范围 0–2×有效 `adj2`；`adj3` 是箭头长度，范围 0–(0.5−有效 `adj2`)。默认控件和三个 XY 手柄使用同一联动上限，箭身手柄随有效箭头长度移动。范围以原生十万分之一表示，精确边界可写回。修改一个值可改变其他值的有效显示，源常量仍保留；指针提交只写实际改变的原生调节值，随后恢复上限仍可读取原值。预览取消、文字适配、旋转/翻转、复制、精确历史及重开沿现有事务。小固定框继续检查文字容量，可显式选择已有缩小或自动尺寸设置。未知公式保持源保护。依据 [ONLYOFFICE 四向箭头](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L6603-L6664)，实现归上述预设及调节模块，未复制上游执行代码。

三向箭头使用 `leftRightUpArrow`，指向左、右和上方。默认 `adj1/adj2/adj3` 均为 0.25，上限及源常量保留规则与四向箭头相同。原生轮廓有 17 个顶点，水平箭身中心位于底边上方一个有效箭头半宽，底边中部留空。文字矩形和四个连接点沿有效箭身位置计算，连接点依次为上尖端、左尖端、箭身下边中点、右尖端。默认插入、类型修改、三个数值控件和 XY 手柄复用既有事务；缩放、旋转/翻转、命中、复制和 Canvas/PDF 共用同一几何。规则依据 [ONLYOFFICE 三向箭头](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L5719-L5775)，实现复用上述预设、调节及 [`connection-sites.mbt`](../../../modules/formats/src/pptx/connection-sites.mbt)，未复制上游执行代码。

`editObjects({ action: "shapeAdjustment", name, value })` 修改所选本地预设形状的一个调节值，包含组成员。圆角 `adj` 为短边的 0–0.5 倍；单向/双向实心箭头的 `adj1` 为箭身占横向宽度的 0–1 倍，`adj2` 为箭头长度占短边的倍数，单向箭头的上限是方向边长除以短边，双向箭头再除以 2。数值按十万分之一保存，沿现有公式整数范围限制在 0–21474.83647。null 只移除该调节值，恢复预设默认值；其他调节值和源内容保留。规则依据 [ONLYOFFICE 预设几何](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/Drawings/Format/CreateGeometry.js#L6947-L6981)，实现归 [`shape-adjustment.mbt`](../../../modules/formats/src/pptx/shape-adjustment.mbt)。

对象查询的 `shapeAdjustments` 返回 `preset`、`reason` 和 `values`；各值包含 `name/value/maximum`，使用与命令相同的比例。默认面板显示百分比，支持分别应用、恢复预设值及相同调节项的多选混合查询。任一对象锁定 `noAdjustHandles`、未知调节源、所选形状不支持该项或数值越过几何上限时，整项拒绝。无变化不新增历史。修改与派生的字体缩小或形状自动尺寸合为一项历史，保留文字、身份、选择及非目标部件；保存重开后可继续修改。继承对象和任意自定义几何编辑继续实施。

缺口右箭头使用 `notchedRightArrow`，复用单向箭头的 `adj1/adj2`：默认均为 0.5，箭杆比例范围 0–1，箭头长度上限为宽度/短边。缺口横坐标为有效箭杆比例乘以有效箭头长度，原生轮廓共 8 个顶点；文字左右同时避开该长度，四个连接点依次位于上肩、缺口尖端、下肩和右尖端。箭杆手柄位于右边框，箭头长度手柄位于上肩。导入、默认插入、类型修改、数值与手柄编辑、命中、复制及 Canvas/PDF 共用现有事务与几何；越界编辑拒绝，未知公式继续保留源并诊断。规则依据 [ONLYOFFICE 缺口右箭头](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L6316-L6350)，实现归 [preset-shapes.mbt](../../../modules/formats/src/pptx/preset-shapes.mbt)、[connection-sites.mbt](../../../modules/formats/src/pptx/connection-sites.mbt)及[adjustment-gesture.mbt](../../../modules/formats/src/pptx/adjustment-gesture.mbt)。

单选可调本地形状时，`selectionPptx` 的 `adjustmentHandles` 返回最多三个 `{ name, x, y }` 页面坐标，顺序与 `shapeAdjustments.values` 一致。圆角矩形、单向/双向、三向/四向、左上双向及折弯向上箭头、三角形、平行四边形、梯形、六边形、八边形、十字、四角星、五角星、六角星、八角星、十角星、十二角星、燕尾形和五边形箭头使用标准 XY 调节位置；旋转、翻转及父容器缩放沿对象矩阵。受保护、多选、文字选择及无调节项时返回空数组。既有 `handles` 继续表示尺寸或连接线端点。

默认 Canvas 用黄色菱形绘制调节手柄，命中优先于尺寸手柄；参数面板继续提供键盘入口。`beginPptx` 使用 `kind="adjustment"`，后续 `dragPptx` 的 `handle=1/2` 对应该项顺序，`dx/dy` 是相对手势起始指针的页面位移。核心逆变换到局部轴，忽略垂直于该轴的位移，并限制在当前几何上限。候选显示预览，revision、已提交源及历史保持；回到起点无历史，松开将最终调节和必要文字适配合为一项历史，Escape、指针取消及丢失捕获使用现有取消路径。旧身份、锁定、无效手柄、字体/布局及资源失败保持最后有效候选和已提交源。位置与拖动规则参考 [ONLYOFFICE 预设 XY 调节](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L6950-L6982)及[逆变换与上下限](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/AdjustmentTracks.js#L195-L252)，实现归 [`adjustment-gesture.mbt`](../../../modules/formats/src/pptx/adjustment-gesture.mbt)。

旋转使用 `{ action: "rotate", angle }`，绝对角度为 -360°–360°，核心舍入到 1/60000°。`{ action: "flip", axis: "horizontal" | "vertical" }` 切换局部水平/垂直翻转。`{ action: "layer", order: "front" | "back" | "forward" | "backward" }` 调整本地顶层对象或同组成员的源顺序。三者均支持同一父容器中的本地对象集合，组作为一个对象处理。各操作保留位置、尺寸、对象身份、文字、裁剪和关系；相同角度与层次边界不新增历史。旋转独立保持各对象自身中心点；翻转分别反转各对象的局部轴状态。文字、图形、图片、命中和选区消费同一矩阵。`geometry` 返回源有效 `rotation/flipX/flipY`，`rotateReason/arrangeReason` 返回对应保护原因。`noRot` 仅阻止旋转；继承、跨父组选择与原有变换锁继续保护。默认 UI 提供角度、翻转及四种层次操作。

批量旋转/翻转要求对象模式，保留各成员位置、尺寸、源顺序、关系、选择顺序及活动对象；组成员的局部源几何保持，世界矩阵随组方向更新。一次提交一项历史，任一成员、源或包预算失败不提交部分对象；相同角度无变化时不新增历史。默认角度框在值混合时留空并显示提示，翻转按钮使用 `aria-pressed="mixed"` 表示混合状态；选择集合改变时刷新角度。旋转锁检查全部成员，`noRot` 不阻止翻转。

层次调整要求对象模式；空选择保持文档不变。`front/back` 按原源顺序将所选对象放到最上层/最下层。`forward` 从上到下、`backward` 从下到上处理，每个所选对象仅越过一个相邻未选对象，所选对象之间保持原顺序。组作为父容器中的单个对象移动，内部层次和完整矩阵保持；未知未选对象原样保留。核心只移除并插入所选源片段，保留注释、其他源内容、关系、选择顺序及活动对象。任一成员受保护或预算失败时整项拒绝，成功只提交一项历史；已到边界或全选而无变化时不新增历史。默认四个按钮支持多选。

文字与变换候选基于原范围重算，不写入已提交 XML，不累积中间历史。暂态查询/布局读取候选；提交一项历史，取消恢复原选择。保存、PDF 和普通编辑在候选期间失败。Enter 是普通段落分隔 `\n`，Shift+Enter 使用对象内软换行 `U+2028`；保存为 DrawingML `p` / `br`。跨 run/段落保留范围外字符与段落属性，不重建整个 `spTree` 或 `txBody`。普通逐字符输入目前各自成项。

对齐使用 `{ action: "align", alignment: "left" | "center" | "right" | "top" | "middle" | "bottom", relativeTo: "slide" | "selection" | "active" }`。相对页面使用页面边缘或中线；相对选区使用所有成员旋转后的矩形包围盒；相对活动对象使用 `selection.object` 的包围盒并保留该对象的位置。`center` 为水平居中，`middle` 为垂直居中。单对象相对自身选区或活动对象时不修改源。

分布使用 `{ action: "distribute", axis: "horizontal" | "vertical", relativeTo: "slide" | "selection" }`。页面分布至少需要两个对象，选区分布至少需要三个；不足时明确拒绝，不切换参考范围。按世界坐标矩形中心排序，中心相同则按选择顺序。选区分布固定排序后的首尾边缘，其余对象保持相等边缘间距。页面有余量时，内部间距与两端留白相等；总尺寸不小于页面时，两端贴页面边缘，内部间距允许为负。旋转矩形边界包含零尺寸线段，不计描边宽度。

对齐与分布要求对象模式，沿用 256 成员、同一父容器中的本地对象及现有锁定/继承/未知资源保护。只改成员位置，保留顺序、活动对象、尺寸、旋转、翻转、文字、裁剪和关系；位置舍入为整数 EMU。成员越界、输出或历史预算失败不提交任何成员，成功只新增一项历史，重复操作或对齐到自身的零位移不写源、不新增历史。默认面板提供参考范围、六种对齐和两种分布，活动对象参考下禁用分布。接口复用 `editPptxObjects` / `PresentationEditor.editObjects`。

组合使用 `{ action: "group" }`，至少选择两个同一父容器中的可编辑本地对象。核心分配新组身份，保留成员身份、相对顺序、格式及关系，转换局部坐标；新组在原父容器中放到所选最上层对象的位置，选择切到新组。原组也可参与嵌套组合。顶层组沿用整体移动、缩放（含非等比例）、旋转、翻转、层次、对齐和删除事务；候选同步派生成员世界矩阵，不写已提交源。多选集合的独立宽高缩放沿上文同一候选路径执行。

组的 `cNvPr` 可包含标准 `a16:creationId` 创建标识。核心验证扩展 UUID、命名空间、单一 GUID 属性及无额外子节点；此元数据不影响绘制，普通变换保留原 XML。未知扩展和非法 GUID 继续保护。原件的读取、组拖动、精确历史和独立保存重开范围见[测试说明](../testing.md#当前兼容证据入口)。

取消组合使用 `{ action: "ungroup" }`，选择须全部为同一父容器中的受支持组。包含非等比缩放及嵌套组，成员回到原组所在层次，选择展开为直接成员，最多 256 项。核心先把累计组缩放换算为成员框的位置与尺寸，再以旋转/翻转矩阵绘制；文字字号、边距及描边宽度保持原值，文字按新框排版。候选预览和源重读使用同一几何规则；取消组合还原世界位置、尺寸、旋转及翻转，保留成员身份、命名空间和组内注释。子组保留成员和页面姿态，可继续逐层取消组合。组内组合与显式取消组合沿相同事务，坐标与保护规则见下文。

组内组合先在父组方向计算包围盒，再按累计父组缩放写入原生 `off/ext` 和成员局部框；新组的 `chOff=0`、`chExt=ext`。父组保持身份、元数据及关系。取消组合把直接成员提升一级，转换到被移除组原父容器的坐标，不把嵌套成员直接提升到页面。两者保持成员页面位置、尺寸和方向，误差限于整数 EMU；组内成员集合变化与现有祖先边界重算合为一项历史。支持形状、图片和子组，混合父组及继承内容继续保护。

祖先进入/几何锁、`noGrp/noUngrp`、成员锁、未知扩展、拆散连接关系的分组、计时引用及取消组合所移除组的链接或引用继续整项拒绝。展开选择最多 256 个直接成员；几何、字体、源/输出及历史预算失败不提交任何源，也不消耗新组身份。默认按钮使用现有 `groupReason/ungroupReason`。共享坐标提升归 [`group-geometry.mbt`](../../../modules/formats/src/pptx/group-geometry.mbt)，保留原矩阵正交校验；删除的单成员提升共用它。分组框和局部坐标参考 [ONLYOFFICE getBoundsForGroup/getGroup](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L6945-L7006)，取消组合参考下文。

尺寸归一遵循 [ONLYOFFICE 组合缩放系数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L568-L607)及[成员 normalize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L629-L664)，取消组合参考 [unGroupCallback](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L7045-L7108)。核心已检查非等比嵌套、旋转/翻转、预览与提交一致、取消、文字/线宽、精确历史及重开；Chromium 已检查取消组合前后 Canvas 画面、独立同字号文本的 PDF 字形边界、XML、非目标部件、历史和重开后原生输入。

`PptxQuery.groupReason/ungroupReason` 返回当前选择的保护原因，默认 UI 用它禁用按钮。继承占位符、未知组效果/扩展、成员锁定、`noGrp/noUngrp`、拆散连接关系的组合、计时引用和取消组合所移除组的引用继续保护。操作只改所属 slide XML，保留其他部件及资源；一次提交一项有界历史，撤销恢复原源与选择，失败不消耗新身份或提交部分成员。

组内形状文字沿现有 `selectPptx`、`replacePptx`、格式、链接和查找替换命令编辑。`parent` 保留直接父组，`textReadOnlyReason` 独立于成员对象的 `readOnlyReason`；成员移动、缩放、旋转和翻转沿下文几何入口；复制、删除、层次及对齐复用下文同组事务，成员外观沿原属性命令编辑。`hitPptx` 的可选 `text: true` 返回最上层可编辑的文字成员及核心光标位置；普通命中仍返回顶层组，前方图片、形状或未知对象继续遮挡后方文字。核心使用累计组矩阵计算光标及选区，不在 Web 中反算文字坐标。

默认指针双击进入文字，文字拖选使用同一成员命中。对象列表按父子层次展开所选组及成员祖先；成员按钮进入文字，Escape 返回直接父组。文字输入、组合候选取消、字符/段落格式、框边距/垂直对齐/换行和三种适配共用原事务及默认面板。自动尺寸按累计组缩放还原局部整数 EMU，保留成员旋转/翻转和其他成员的页面姿态；本地父组外框与子坐标在同一事务中更新。缩放不改变字号、边距和线宽。

普通视图中的母版/版式成员、未知组效果、`noDrilldown/noSelect/noTextEdit` 及原文字保护继续拒绝编辑。祖先 `noMove/noResize` 不阻止固定框内输入，但阻止自动尺寸变更。缺字体、溢出及原有资源/输出预算失败整体拒绝，源与历史保持。行为参考 [ONLYOFFICE 组内文字选择与变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L196-L216)及[组内文字输入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L715-L730)，实现复用 [`group-geometry.mbt`](../../../modules/formats/src/pptx/group-geometry.mbt)、[`text-resize.mbt`](../../../modules/formats/src/pptx/text-resize.mbt)和[`文字命中`](../../../modules/formats/src/pptx/hit.mbt)。

组成员几何复用 `beginPptx`、`dragPptx`、`finishPptx` / `cancelPptx` 以及 `rotate` / `flip` 对象命令，`PresentationEditor.transform` 的增量仍为页面点值。对象的 `transformReason` 返回移动/缩放保护原因，`rotateReason` 返回旋转保护原因；`arrangeReason` 返回层次和对齐保护原因。最多 256 个所选对象须来自同一父组，父子或跨父组选择整项拒绝。绝对 `transformPptx` 使用归一化父组坐标及尺寸，与当前 `PptxObject.geometry` 的 x/y/width/height 一致；`dragPptx` 使用页面坐标增量。

核心逆变换页面增量和固定角点，再按累计组缩放还原成员局部坐标。预览舍入为原生整数 EMU，提交读取同一几何；旋转和翻转保持中心，子组变化同步其成员世界矩阵。同组多选使用父组方向的包围盒及手柄，沿原成员缩放轴交换规则调整中心和尺寸。文字、字号、边距、描边和成员身份保留；文字框自动适配共用同一局部写回，取消、撤销重做、保存重开沿原源事务。本地父组边界随成员变换及自动适配重算，坐标归一化规则见下文。

默认对象列表在成员对象模式中支持普通及 Shift 同组选择；Enter 进入文字，Escape 返回直接父组。已进入组后，普通画布命中返回当前父组的直接成员，双击继续使用文字命中。移动/缩放及旋转/翻转控件复用已有面板；受保护的删除、复制和混合范围方向键不修改源，也不停止编辑器。祖先组的 `noDrilldown/noSelect/noMove/noResize`、对应旋转锁、成员锁、未知组和继承内容继续保护；原生坐标、字体、布局、源/历史及输出上限失败整项拒绝。同组成员组合及逐级取消组合沿原命令和按钮开放。

同一父组中的形状、图片及子组复用 `duplicate/delete/layer/align/distribute`。复制的 `dx/dy` 为页面点值，核心逆变换到父组坐标，再写整数 EMU；副本留在原父组，按原源顺序置于该组最上层，选择顺序与活动对象对应副本。对象身份、域身份与副本内引用沿已有复制事务重映射，图片资源共享。层次调整只改直接父容器中的源顺序，不改成员或组的原生框。对齐/分布仍使用页面包围盒、页面/选区/活动对象参考，再将页面增量写回父组；非目标成员的页面姿态保持。默认按钮复用原保护原因，父子或跨父组混选整项拒绝。对象模式下 Ctrl/Cmd+A 选择当前直接父容器中的对象，Ctrl/Cmd+D 与 Delete/Backspace 使用原复制/删除入口。

删除后，从内到外移除空组，并将单个存活成员提升到组原来的层次。核心保留成员页面姿态、尺寸、文字、身份与资源，组间注释和命名空间随存活内容保留；原生坐标按 EMU 舍入。改变的成员集合和重建边界与删除合为同一历史。删除清空对象选择，撤销恢复原源和完整选择。待折叠组的点击/悬停链接、`noUngrp/noDelete` 或连接/计时引用，以及原对象/祖先保护，会整项拒绝；查询 `deleteReason` 也显示当前选择引发的组折叠保护。资源及关系继续保留，不做包清理。规则参考 [ONLYOFFICE removeInGroup](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L5275-L5358)，实现归 [`object-delete.mbt`](../../../modules/formats/src/pptx/object-delete.mbt)。

本地成员原生变换或已有组的成员集合改变时，核心按内层到外层重算祖先边界。范围采用 [ONLYOFFICE GroupShape](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L1246-L1384) 的旋转象限轴交换规则。受影响顶层组的子树归一化为 `chOff=0`、`chExt=ext`；按已舍入的父坐标写回子成员，保留页面中心、大小与方向，误差限于整数 EMU。成员文字、字体、边距、描边、身份、元数据和关系保留。未移动成员的局部 `x/y` 可以改变，宿主须读取当前查询，页面姿态保持。缺省 `chOff` 写入 `chExt` 之前。实现归 [`group-bounds.mbt`](../../../modules/formats/src/pptx/group-bounds.mbt)。

预览只更新派生几何；提交从候选原生源重读坐标，并与原操作共用一项修订和历史，撤销/重做精确恢复源。顶层组整体变换、顶层复制与顶层新建组合不强制归一化；组内成员集合变化更新现有祖先组边界。只有当前编辑的源部件被改写，其继承对象保持；母版/版式源视图使用同一边界事务。未知同组成员、原生坐标及输出/历史预算失败原子拒绝。主题字体与页码自动适配沿同一坐标写回，避免重复除以组缩放。

页面增量与组内原生坐标换算参考 [ONLYOFFICE MoveShapeImageTrack](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/MoveTracks.js#L95-L145)及[组缩放写回](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/MoveTracks.js#L301-L315)。独立父组权限及受支持的本地组边界为 SDK 实施范围；母版、版式组编辑仍待实现。实现归 [`member-geometry.mbt`](../../../modules/formats/src/pptx/member-geometry.mbt)、[`object-selection.mbt`](../../../modules/formats/src/pptx/object-selection.mbt)和[`变换面板`](../../../packages/pptx/src/react/pptx-arrange.tsx)。

组成员外观复用下列原命令和默认面板。支持形状纯色/无填充、线性渐变、图片填充、描边/端点/线型及不透明度，支持预设调节值；独立图片成员支持替换、裁剪、拉伸/平铺、不透明度与拉伸目标内缩。形状批量外观仍原子提交，图片属性要求唯一对象选择。纯外观修改保留所有成员与父组原生变换，不触发组边界归一化；调节值引起的自动适配沿已有框事务更新边界。图片替换新建资源及关系，其他共用旧资源的对象保持。

祖先组的 `noDrilldown/noSelect`、未知组源、继承内容、原对象保护及属性专用锁继续拒绝。祖先移动/缩放锁允许不改框的外观操作；调节值引起的框变化仍遵守自动适配保护。既有未知属性、图片解码、源/资源/输出和历史预算原样执行，失败不提交部分成员。权限归 [`object-paint.mbt`](../../../modules/formats/src/pptx/object-paint.mbt)，图片沿 [`image-edit.mbt`](../../../modules/formats/src/pptx/image-edit.mbt)。局部填充/描边覆盖参考下文 ONLYOFFICE `changeFill/changeLine`，调节锁参考 [canChangeAdjustments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L1065-L1070)。

`editPptxObjects` / `PresentationEditor.editObjects` 支持 `{ action: "fill", color }` 和 `{ action: "stroke", color, width }`。颜色为不带 `#` 的六位 RGB，核心统一小写；null 写显式 `noFill`，表示无填充或无边框。宽度为 0.1–1000 pt，舍入到整数 EMU。操作作用于对象模式下所选的本地形状（含组成员），包含文本框和基本形状；多选原子提交为一次历史。查询中每个对象带 `appearance: { fill, gradient, imageFill, imageFillMode, imageFillReason, stroke, width, fillOpacity, strokeOpacity, fillOpacityReason, strokeOpacityReason, dash, dashReason, cap, join, miterLimit, penReason, reason }`，颜色为有效 RGB 或 null，宽度为有效 pt，reason 说明保护原因。默认 UI 显示混合状态，分别应用填充和边框，草稿随选择或实际外观值更新。

修改只覆盖目标属性，保留几何、顺序、身份、文字、其他线条属性与部件。缺失的填充/边框按 DrawingML 顺序创建，空边框保留原属性；填充覆盖会关闭 `useBgFill`。直接设置相同值不增加历史；候选、过期 revision、锁定、未知填充属性/注释及预算失败不提交任何成员。组本身、继承装饰和独立图片的形状填充/描边仍受保护，非居中径向渐变及复杂效果编辑待扩展；图片拉伸填充见下节。纯色与受支持线型沿共同 Canvas/静态 PDF 路径绘制。实现参考 [ONLYOFFICE CShape.changeFill/changeLine](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L6421-L6461) 的局部属性覆盖及背景填充处理。

`editObjects({ action: "gradientFill", stops, angle, scaled })` 将所选本地形状（含组成员）设为多色标线性渐变。色标使用[页面背景](pptx-editing.md#pptx)的 2–32 项颜色、位置与不透明度规则。角度为 0–360° 并按 1/60000° 舍入，360° 归一为 0°；`scaled` 为必需布尔值。角度及比例规则复用页面背景，保留形状的轮廓、调节点、几何、描边和文字，随对象旋转/翻转。默认外观面板与背景共用色标增删、位置/颜色/不透明度控件，另有类型、角度和按形状比例缩放。查询 `appearance.gradient` 返回 `{ kind: "linear", stops, angle, scaled }`、`{ kind: "radial", stops }` 或 null；渐变时 `fill` 为 null、`fillOpacity` 为 1；整体填充不透明度命令受保护，各色标不透明度沿 `gradientFill` 或 `radialGradientFill` 编辑，纯色描边仍可调整。纯色/无填充命令可替换已有受支持渐变。

读取本地、版式/母版继承及主题的 2–32 项 RGBA 渐变色标；源的 `rotWithShape` 为缺省/真值，`flip` 为缺省或 `none`。固定页面方向、其他路径类型和未知标记保留源并诊断。线性渐变的 tileRect 四边仍须为零；圆形渐变的原生点与平铺元数据按下文读取。操作先校验全部成员，复用原子源事务、无操作和精确历史；非法值、保护成员和输出预算失败保持整个文档。定位图元 `ClipPath(path, evenOdd)` 复用既有绘制命令，Canvas/PDF 沿相同预设路径裁剪，矩形以外区域及后续图元保持原样。实现归 [`shape-gradient.mbt`](../../../modules/formats/src/pptx/shape-gradient.mbt)；参考 [ONLYOFFICE 形状渐变绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1970-L2037)的逐色标位置绘制。

形状使用 `editObjects({ action: "radialGradientFill", stops })` 设置居中圆形径向渐变，背景使用上述 `kind: "radial"`。两者共用 2–32 项 RGBA 色标、原子事务和默认控件；径向类型没有角度或比例参数。原生存储为 `a:path path="circle"`，接受省略 `fillToRect` 或有效的零面积点。点的四边为 0–100000 的整数，缺省为零，左右与上下之和各为 100000。径向 tileRect 接受 i32 整数边距，须保留正宽高；未知属性、文字、子节点和其他路径继续保护。普通编辑保留原始元数据，显式新建或替换渐变写入四边均为 50000 的中心点。

按首要参考 ONLYOFFICE 绘制，圆心保持原生框中心，外圆半径为较长边的一半，内圆半径为 1 mm（约 2.83465 pt）。原生角点与非零 tileRect 保留在源中，不改变此参考的圆形几何。该行为已由固定 x2t 的原件 PDF 坐标核对，并非任意焦点的完整 OOXML 语义。色标沿内外圆排列，原形状轮廓、对象变换及页面裁剪保持。共享绘制使用 `RadialGradientRectangle` / `radialGradientRect`；Canvas 和 PDF 使用相同内外圆，PDF 的颜色与灰度软遮罩也保持相同几何。PDF 资源按类型、色标和归一内圆半径复用，防止不同尺寸误用遮罩。复制、纯色替换、精确历史和保存重开沿原实现。依据为 [ONLYOFFICE Canvas 径向绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1992-L1998)及 [PDF 渐变几何](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L2380-L2391)。

PPTX 图片接受标准扩展 `{28A0092B-C50C-407E-A947-70E740481C1C}` 中的 `a14:useLocalDpi val=0/false`。它禁用图像本地 DPI，不是颜色或透明度效果。读取与图片裁剪保留扩展；插入 `alphaModFix` 时放在 `extLst` 之前。未知扩展、启用本地 DPI 和未支持的真实图片效果继续保护。两份 C0 原件的显示、裁剪、历史、保存重开和 PDF 通过独立对照，范围归[测试说明](../testing.md#当前兼容证据入口)。实现归 [`image-opacity.mbt`](../../../modules/formats/src/pptx/image-opacity.mbt)。

### 图片目标内缩

`editObjects({ action: "imageInsets", insets })` 设置所选本地图片及图片填充形状（含组成员）的目标矩形。`editSlides({ action: "backgroundImageInsets", insets }, slide?)` 设置图片背景，继承背景可创建本页覆盖并复用原资源。两者沿同步 Wasm、Worker、宿主和默认面板使用相同事务。对象查询返回 `imageInsets` 与 `imageInsetsReason`；图片背景的 `value.insets` 返回有效值。

`insets: [left, top, right, bottom]` 是对象或页面宽高的比例。正数向内，负数向外；四个零恢复完整目标。每项须在 DrawingML 有符号百分比范围 −21474.83648–21474.83647 内，按 1/100000 舍入后，左右与上下之和分别小于 1。默认控件使用百分比，支持四边设置、重置及一次应用。当前仅拉伸支持目标内缩；切为平铺会移除拉伸矩形，再切回拉伸使用零内缩，源裁剪继续保留。

核心先把有效源裁剪映射到目标矩形，再同时裁剪到该矩形与形状轮廓或页面。内缩留白不会露出被裁掉的源像素。目标随对象旋转/翻转，透明度乘源像素 alpha；Canvas、PNG/JPEG 和 PDF 复用同一图元。读取支持本地、版式、母版与主题来源；对象内缩编辑要求本地图片或填充。替换图片、透明度及同模式格式编辑保留目标矩形；不改变对象外框、文字、图片字节或现有关系。非目标源保持，同值不增加历史，混合输入和设置可精确撤销并保存重开。

目标展开后的图片宽高与位置绝对值不超过 1e9 pt，并继续遵守图片、输出和历史预算。空矩形、未知源、保护及预算失败整体拒绝。实现归 [`image-insets.mbt`](../../../modules/formats/src/pptx/image-insets.mbt)，目标与源矩形的组合依据 [ONLYOFFICE drawBlipFillStretch](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1778-L1834)，未复制上游源码。

### 形状图片填充

`execute({ operation: "rasterHeaderPptx", bytes })` 在 4 MiB 图片预算内读取 PNG、JPEG 或 GIF 的尺寸。结果包含像素尺寸或 `{ error }`。Web 客户端在提交插入、替换、形状填充、背景和媒体海报前附带 `verify: true`。核心能解码图片时返回 `coreVerified: true`，其余图片由浏览器核对解码尺寸。预检不改文稿、资源或历史。

`editObjects({ action: "imageFill", objects, bytes, mode })` 将所选本地闭合形状（含组成员）设为 PNG/JPEG/GIF 图片填充，`mode` 必须为 `stretch` 或 `tile`。`objects` 是文件读取前捕获的有序选择，提交时须与当前选择完全一致，防止异步读取后修改其他对象。图片沿既有 4 MiB、尺寸、资源数量、输出和历史预算校验，Web 提交前检查实际解码。多选共享一个新资源及关系，保留各自身份、几何、轮廓、描边、文字、已有裁剪和有效填充不透明度。核心沿既有图片事务提交，失败不增加资源或历史；相同本地图片无操作。默认面板选择图片后直接应用，清除和纯色/渐变命令可替换受支持图片填充。

查询 `appearance.imageFill` 返回资源键或 null，`imageFillMode` 返回 `stretch`、`tile` 或 null，`imageFillReason` 返回保护原因。读取本地、版式/母版和主题的内部图片关系，按来源部件解析；支持非负四边源裁剪及常量 `alphaModFix`。图片按预设形状轮廓裁剪，随对象旋转/翻转，Canvas/PDF 共用同一图元。已有本地图片填充可用 `fillOpacity` 修改透明度；继承图片先设置本地图片覆盖。带裁剪元数据的平铺复用 [ONLYOFFICE drawBlipFillTile](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1687-L1777)：使用整张源图的 96 DPI 尺寸、对齐和翻转，保留 `srcRect`；切回拉伸才应用裁剪。模式切换、替换、透明度和精确历史保留这些值；切回拉伸的扩展尺寸及平铺数量超限原子拒绝。目标内缩归[图片目标内缩](#图片目标内缩)；固定页面方向、外链、背景关联图片填充及未知/重复/不透明源继续保护，仍归 P12 后续实现。实现归 [`shape-image.mbt`](../../../modules/formats/src/pptx/shape-image.mbt)和 [`object-image.mbt`](../../../modules/formats/src/pptx/object-image.mbt)，语义参考 [ONLYOFFICE 图片拉伸、裁剪和透明度绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1778-L1848)，未复制上游源码。

`editObjects({ action: "imageFillMode", mode })` 在已有本地图片上切换拉伸和平铺，不新增图片或关系；继承填充须先设置本地覆盖。默认面板提供模式选择、应用及按所选模式上传文件。平铺采用 96 DPI，即源像素乘 0.75 pt，不读取嵌入 DPI。导入支持 `sx/sy`（1–100000000，以 100000 为一倍）、`tx/ty`（±182880000 EMU）、九种 `algn` 及 `flip=none/x/y/xy`；偏移和对齐确定原始格点，负索引仍保持交替镜像相位。换图保留已有平铺参数，切换回平铺使用默认顶左对齐、原尺寸和无翻转。非零源裁剪在平铺时保留，切回拉伸后生效；未知源继续保留并诊断。

核心只生成覆盖形状的有限图片图元，沿同一轮廓裁剪供 Canvas/PDF 使用。每页最多 65536 个重复单元；应用、复制、尺寸修改及单选/多选变换预览超过预算时，在资源、历史或候选变化前拒绝。已有超预算源仍可原样保存，输出受预算保护。实现归 [`shape-tile.mbt`](../../../modules/formats/src/pptx/shape-tile.mbt)，尺寸、对齐和交替镜像依据 [ONLYOFFICE 平铺绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1685-L1776)及[镜像纹理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/Graphics.js#L870-L949)。未复制上游源码，未增加渲染后端或依赖。

`editObjects({ action: "fillOpacity" | "strokeOpacity", opacity })` 分别设置纯色/本地图片填充和纯色边框的不透明度，值为 0–1，按 1/100000 舍入。默认 UI 使用百分比输入；查询返回两项有效值及各自保护原因，支持混合多选。无填充的一侧须先设置填充，0 保留形状和选择。100% 写入明确的不透明覆盖，不表示恢复继承。

读取已有颜色的 alpha、alphaMod 和 alphaOff，按声明顺序计算并归一到 0–1。修改保留 RGB/系统色/主题色及 tint、shade、lumMod、lumOff 等关联；继承填充写为本地声明，主题 phClr 绑定到原引用颜色，保留主题和父级源。颜色与线宽修改保留已有有效不透明度；明确移除填充后不保留隐藏的 alpha 状态。操作复用同一多选源事务、待输入文字屏障和精确历史。未知颜色标记、保留注释、只读对象及预算失败拒绝全部成员。文字和页面背景的透明度仍受原保护。算法参考 [ONLYOFFICE 颜色 alpha 变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L2089-L2108)，实现归 [`shape-opacity.mbt`](../../../modules/formats/src/pptx/shape-opacity.mbt)。

`editObjects({ action: "strokeDash", dash })` 修改所选本地形状（含组成员）的预设线型，适用已有多选、文字框和基础形状。`dash` 接受 `solid`、`dash`、`dashDot`、`dot`、`lgDash`、`lgDashDot`、`lgDashDotDot`、`sysDash`、`sysDashDot`、`sysDashDotDot` 或 `sysDot`；null 移除局部 `prstDash` 并恢复主题/父级，缺省为实线。`appearance.dash` 返回有效线型，`dashReason` 返回本操作的保护原因。默认 UI 提供线型选择、应用和恢复继承，混合选择继续显示混合状态。

修改只写目标 `prstDash`；缺少 `ln` 时按 DrawingML 顺序创建局部边框，保留颜色和宽度继承，明确的 `solid` 可覆盖主题虚线。行宽、颜色、填充、几何、文字、身份及其他部件保持，整组共用一次精确历史。重复同一直接值不新增历史，源注释/处理指令或未知线型属性保护修改；自定义 dash、重复声明及未知预设保留源并诊断。

预设使用 [ONLYOFFICE DashPatternPresets](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Metafile.js#L1767-L1820)的线宽倍数，普通短划线为 4/3，长划线为 8/3，系统短划线为 3/1。有效线宽变化同步缩放 dash。定位后的路径携带点值数组，Canvas 沿已有绘制样式执行并复原，PDF 使用单路径作用域中的 dash 指令，后续图元继续沿自身样式绘制。自定义 dash 继续实施。

`editObjects({ action: "strokeCap", cap })` 设置 `flat/rnd/sq` 平头/圆头/方头，null 恢复继承。`{ action: "strokeJoin", join }` 设置 `round/bevel` 圆角/斜角，null 恢复继承；`{ action: "strokeJoin", join: "miter", miterLimit }` 设置斜接，比例为 1–1000，按 1/100000 舍入。查询返回有效 `cap/join/miterLimit` 及 `penReason`，默认 UI 提供两类样式、斜接上限和各自恢复按钮。

有效描边取最近的完整 `a:ln`，再合入主题默认值；局部不完整描边不会继续合入父级描边，直接 `noFill` 保持不可见。连接类型相同时从主题补齐缺失的斜接上限。未声明连接时按首要参考 ONLYOFFICE 保留斜接与比例 10，端点缺省为平头；显式 `miter` 未给上限时仍继承同类主题值，最终缺省为 8。连接行为参考 [ONLYOFFICE ShapeDrawer](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L2098-L2129)，声明选择与主题合并依据 [getCompiledLine](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L1852-L1885)及 [recalculatePen](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L3136-L3173)，实现归 [objects.mbt](../../../modules/formats/src/pptx/objects.mbt)。操作沿用本地形状（含组成员）、多选原子事务、精确历史与既有预算，保留颜色、宽度、线型、其他源属性和部件；不修改共享主题或母版。未知/重复连接、保留的连接注释、未知端点或超出支持范围的斜接值保留源并保护修改。

定位路径使用 `PathStyle { fillAlpha, strokeAlpha, dash, cap, join, miter }`，数值端点 0/1/2 对应平头/圆头/方头，连接 0/1/2 对应斜接/圆角/斜角。Canvas 复用既有 `DrawStyle`，每条路径后复原；PDF 在独立图形作用域写相同端点、连接、斜接、dash 及独立填充/描边 alpha。普通及斜线的端点形状参与核心命中。预览与输出不再把导入端点或连接静默画成默认值。

### 直线端点样式

`editObjects({ action: "lineEnd", side, end })` 修改所选本地顶层直线或已知折线/曲线连接线的端点样式。`side` 为 `head/tail`，分别对应路径起点的 `headEnd` 和终点的 `tailEnd`。`end` 为 `{ kind, width, length }`：`kind` 接受 `none/triangle/stealth/diamond/oval/arrow`，分别为无、实心三角、凹尾、菱形、椭圆和开放箭头；宽度与长度各接受 `sm/med/lg`。`end=null` 移除该端的局部声明并恢复继承，`kind="none"` 显式覆盖继承。MoonBit 类型为 `LineEnd`，Wasm/Web 类型为 `PptxLineEnd`；查询返回 `appearance.headEnd/tailEnd/lineEndReason`，默认面板提供两端独立设置、混合状态和恢复按钮。

尺寸使用有效线宽的 2/3/5 倍，细线以 1.875 pt 为最低基准。该值将上游的 2.5 px 最小尺寸固定到源坐标，预览缩放与 DPR 不改变 PDF 几何。三角、凹尾和开放箭头朝外，菱形与椭圆以端点为中心；端点沿实际首末非零线段或曲线切线方向、旋转、翻转和既有组矩阵绘制；支持普通直线及已知折线/曲线连接线。轮廓参与核心命中，使用边框颜色和不透明度，保持主体虚线而以实线绘制端点。Canvas/PDF 复用相同路径。零长度线不派生端点轮廓，保留原源。

导入读取局部、版式/母版及主题声明，缺省为无端点和中尺寸。编辑只替换指定节点，保留线宽、颜色、几何、文字、身份及其他部件；多选共享原子事务、精确历史和保存重开。重复直接值不增加历史。`noChangeArrowheads` 锁、只读/继承/组内对象、未知类型/尺寸/属性/子节点、重复声明、端点内注释及预算失败继续保护。连接线端点拖动及目标联动见[连接线](#连接线)。尺寸参考 [ONLYOFFICE EndArrow](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L7331-L7400)，轮廓参考 [DrawLineEnd](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L51-L500)；未复制上游源码。实现归 [`line-end.mbt`](../../../modules/formats/src/pptx/line-end.mbt)、[`line-end-edit.mbt`](../../../modules/formats/src/pptx/line-end-edit.mbt)及 [`pptx-line-ends.tsx`](../../../packages/pptx/src/react/pptx-line-ends.tsx)。

主题颜色支持 sRGB、带 `lastClr` 的系统色、主题/颜色映射以及 tint、shade、lumMod、lumOff。支持无填充、纯色填充、实线及标准预设虚线、主题填充/边框/背景引用和无效果样式。未知颜色变换、填充或可见效果保留源并诊断，不静默宣称完整。占位符依类型/索引匹配，当前属性按具体声明覆盖继承值；写回不修改共享主题、母版或版式。

DrawingML `tint/shade` 先把 sRGB 转为线性 RGB，混色后再转回；`tint` 保留所给比例的原色，`shade` 乘该比例。两者仅接收 0–100000，按源顺序与 HSL、透明度变换组合。文字、形状、背景和表格共用此规则；既有表样式 XML 保持。参考 [ONLYOFFICE 色彩转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L2034-L2066)及 [tint/shade](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L2275-L2290)。

字体键为有效 family，按需附加 `|bold` / `|italic`。主/次字体、显式 Latin/EA/CS 字体及当前常见脚本映射参与解析；自动推断覆盖 Latin、简中 Han 缺省、Kana、Hangul、Arabic、Hebrew、Devanagari 和 Thai。语言敏感的 Han 区域字体推断尚未扩展；不声明全语言主题字体一致性。调用者提供授权字体及实际样式映射，缺失时明确失败。

文本框读取基本字号、粗体/斜体、文字色、段落对齐、内边距、缩进、点值/百分比段距及行距、软换行和字符项目符号的字体/大小/颜色。形状 `fontRef` 颜色覆盖母版默认值；显式文字颜色仍优先。默认允许框外文字，`horzOverflow/vertOverflow="clip"` 裁剪对应轴。可完整测量的原生溢出用于屏幕与 PDF，不报告为显示不完整；编辑时的适配校验保持。无法建立文字几何时保留诊断、边界占位和对象文本查询。默认与锚定依据 [ONLYOFFICE 文字溢出](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2396-L2434)。

导入字号按半点精度显示，原始 XML 保持。`normAutofit` 存有 `fontScale` 时应用比例，再将文字字号四舍五入到整数点，至少 1 pt。缺少该属性时保留读取字号和原生溢出；实际编辑或显式适配才重算，并保存明确比例。百分比列表标记基于缩放后的文字字号计算，固定点数标记保持所给大小。规则依据 [ONLYOFFICE 字号导入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L9075-L9083)、[缩放取整](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L13965-L13978)及[列表大小](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/PresentationNumbering.js#L390-L401)。

`lnSpcReduction` 只缩减继承的自动行距，显式段落行距优先。普通文字先将每种实际字体的升降部归一至字号的 120%，再分别取本行最大升部、降部并相加。混合字体的自然行高可以超过单个字体的 120%；基线使用合并后的升部。上下标或行内对象仍保留较大行框。规则依据 [ONLYOFFICE 字体归一](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/DrawingDocument.js#L69-L93)及[行度量合并](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js#L2955-L2978)。首尾段距默认不计入边界，由 `spcFirstLastPara` 控制。居中和右对齐不计行尾空格；文字对中的负剩余空间允许原生溢出。PPTX 默认关闭字偶距和可选连字，保留阿拉伯文必需塑形；显式字符间距继续按原值应用。

相邻段落取前段段后距与后段段前距的较大值。百分比段距分别按本段首行、末行的自然文字行高换算，独立于显式行距。原点值、百分比、继承和 XML 保留，空段落仍参与间距与高度测量。文字框、表格和 SmartArt 共用该排版规则。依据 [ONLYOFFICE 相邻段距合并](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L10809-L10837)及[百分比段距换算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L4149-L4159)，实现归 [layout.mbt](../../../modules/formats/src/pptx/layout.mbt)。独立控制及真实文件证据见[测试说明](../testing.md#当前兼容证据入口)。

椭圆文字先使用原生内接矩形，再叠加正文内边距。矩形沿水平与垂直半径的 45 度投影确定，行为依据 [ONLYOFFICE ellipse 文本框](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L3100-L3116)，实现归 [preset-shapes.mbt](../../../modules/formats/src/pptx/preset-shapes.mbt)。

百分比自动行距扩大行框时，首行基线取自然升部与扩展行高的 75% 中较大值。负行隙仍将基线向上移动完整差额。该规则由固定 ONLYOFFICE 的十组独立控制确认，覆盖 Calibri/Arial、8/11 pt 及 80%/100%/115%/150% 行距。原件 115% 控制的整页栅格与冻结参考逐字节一致。控制只验收基线与行高；增大行距或字体引起的表格自动增高尚未验收，证据归[测试说明](../testing.md#当前兼容证据入口)。

固定点值行距至少保留 1 pt，字体缩放后仍应用该下限。核心先按各实际字体的升降部比例归一到字号的 120%，再取当前行文本升部、降部的最大值；列表标记不参与这两个文本度量。基线取 `max(0.75 × 行高, min(文本升部, 行高 − 文本降部))`，保留混合字号、字体回退、上下标偏移和空行字体。该规则只作用于 PPTX；DOCX 沿原固定行距规则。字体归一依据 [ONLYOFFICE 演示文稿文字度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/DrawingDocument.js#L69-L93)；固定 10.0.0 脚本及 32 组独立原生控制核对基线和行高，覆盖两个字体族、两个字号、混合文本、大列表标记及极小点值。实现归 [paragraph-layout.mbt](../../../modules/formats/src/pptx/paragraph-layout.mbt)，资格与边界归[测试说明](../testing.md#当前兼容证据入口)。

编辑或显式适配时，以 5% 步长求解 25%–100% 的字体缩放，并将继承行距缩减设为字体缩减量的 20%；标题占位符最低为 90%。检查可用宽高，写回必要 `fontScale/lnSpcReduction` 并保留基准字号。依据 [ONLYOFFICE 自动适配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L5080-L5179)和[显式行距合并](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L11364-L11380)。字段所在框保持文字编辑保护；简单编号字段的显示见下节。其他字段、扩展图片列表、东亚字符直排及文字变形继续诊断或保护。

`editPptxObjects` / `PresentationEditor.editObjects` 已支持 `{ action: "textInsets", left, top, right, bottom }`、`{ action: "textAnchor", anchor }`、`{ action: "textWrap", wrap }` 和 `{ action: "textFit", fit }`。四边距离为 0–14400 pt，舍入为整数 EMU，须保留有效文字区域；anchor 为 `t`、`ctr` 或 `b`。布尔 wrap 控制框内换行。fit 为 `none`（固定框）、`shrink`（缩小字体）或 `resize`（形状随文字调整大小），分别保存 `noAutofit`、`normAutofit` 或 `spAutoFit`。它们作用于所选本地顶层文本形状，文字模式和对象模式均可调用，多选合为一次源事务。默认 UI 提供四边输入、垂直对齐、换行开关和适配模式，保留待提交的原生文字输入。

每个 `PptxObject.textFrame` 返回有效 `left/top/right/bottom/anchor/wrap/fit/columns/columnGap/rtlColumns/direction/rotation/upright` 及保护原因 `reason`。修改保留文字、字符格式、身份、选择和其他部件；缺失 `bodyPr` 与适配节点按 DrawingML 顺序创建，其他属性和非目标注释原样保留。`shrink` 重新测量并保存比例，最低允许字号仍无法容纳时原子拒绝。`none` 保留当前尺寸及原生溢出设置。

`PresentationEditor.editObjects({ action: "textDirection", direction })` 修改所选本地文本框的原生 `bodyPr@vert`。direction 接受 `horz`（横排）、`vert`（全部文字顺时针旋转 90°）和 `vert270`（全部文字逆时针旋转 90°），缺省为 `horz`。两种旋转方向交换排版宽高，并按旋转方向交换有效内边距；段落、字形、标记和公式作为完整文字平面旋转，再叠加形状的旋转、翻转和组变换。原生输入、选择、命中、显示链接、PDF 链接和裁剪共用该平面，复制写入有效方向。方向键按文字平面映射；例如 `vert` 中向下前进一个字符，`vert270` 中向上前进一个字符。默认面板提供三种方向。

缩小字体和形状自动尺寸在交换后的文字平面求解。开启换行时，旋转文字保持物理高度并调整物理宽度；关闭换行时两轴都可调整。锚定和段落对齐映射到对应物理边，形状自身已旋转时继续保持中心。方向及自动几何合为一次精确历史，无效值、无可用区域、未知源和预算失败原子拒绝。`eaVert/wordArtVert` 的字符直排、单元格独立角度及保持直立、文字变形继续保护。实现归 [`text-direction.mbt`](../../../modules/formats/src/pptx/text-direction.mbt)，依据 [ONLYOFFICE 旋转方向和边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2485-L2552)与[交换后的文字尺寸](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L3995-L4143)。

`PresentationEditor.editObjects({ action: "textRotation", angle })` 修改本地文本框的独立文字角度。angle 为 -360–360 的有限度数，舍入为原生 `bodyPr@rot` 的六万分之一度；查询 `textFrame.rotation` 返回有效角度。导入保留原生有符号 32 位范围。文字按实际内容矩形中心旋转，再叠加框方向、形状和组变换；内边距及垂直锚定参与中心计算。适配和框尺寸使用旋转前的文字测量，字号、形状几何与框裁剪保持。输入、光标命中、选择、复制和 Canvas/PDF 链接共用矩阵，多选与精确历史沿现有事务。表格单元格的独立角度及保持直立继续保护。旋转中心依据 [ONLYOFFICE 文字旋转矩阵](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2305-L2360)。

`PresentationEditor.editObjects({ action: "textUpright", upright })` 设置文字保持直立，upright 为布尔值，查询返回 `textFrame.upright`。核心读取继承的原生 `bodyPr@upright`，本地 false 可覆盖继承的 true。文字不随形状和组旋转或镜像，独立文字角度及 `vert/vert270` 方向仍生效。按累计形状旋转，45°–135° 和 225°–315° 使用交换后的排版宽高；内边距中心偏移沿页面轴，并随有效翻转反向。换行、缩小及自动形状尺寸共用该文字平面。

默认面板提供复选框，多选、输入、复制和精确历史复用框属性事务。框裁剪、指针命中及 PDF 文字链接使用保持直立后的有效框；组旋转下自动调整大小保持形状中心。单元格独立角度及保持直立继续保护。实现归 [`text-upright.mbt`](../../../modules/formats/src/pptx/text-upright.mbt)，尺寸与位置依据 [ONLYOFFICE upright 矩阵](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2570-L2699)，分界依据 [checkNormalRotate](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L185-L189)。

`PresentationEditor.editObjects({ action: "textColumns", columns, gap, rtl })` 设置文本框等宽分栏。columns 为 1–16 的整数，gap 为 0–14400 pt，rtl 为布尔值；距离舍入为整数 EMU，栏间距和内边距须留下正栏宽。核心读取继承的 `numCol/spcCol/rtlCol`，缺省为单栏、零间距和从左到右。设置多栏同时启用原生 `wrap="square"`；之后可独立修改换行。`rtlCol` 只控制栏顺序，不改变段落方向。默认面板提供栏数、栏间距及从右到左排列选项。

文字按当前栏高逐栏流动，不强制平均分配短文字；溢出时用 32 次有界搜索求所需栏高，固定框继续诊断和裁剪。缩小字体及自动形状尺寸沿同一分栏测量，关闭换行时按最长栏内行调整总宽度。光标命中先选最近栏，上下导航跨栏时保持栏内横向位置；字形、列表标记、公式、选择和 Canvas/PDF 使用同一几何。对象剪贴板写入有效分栏属性，跨文稿保留继承结果。实现归 [`text-columns.mbt`](../../../modules/formats/src/pptx/text-columns.mbt)；栏数依据 [ONLYOFFICE 原生范围](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Common/SimpleTypes_Drawing.cpp#L3713-L3738)，换行规则依据 [Shape.checkWrap](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L7040-L7087)，栏高依据 [DrawingContent.RecalculateContent](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/DrawingContent.js#L267-L302)。东亚字符直排和文字变形继续保护。

单栏文本框的左右边距耗尽可用宽度时，排版按 [ONLYOFFICE recalculateDocContent](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L3985-L4005) 保留 0.02 mm 的最小宽度。窄空框继续绘制原几何，保留文字光标。多栏间距仍须留下正栏宽。

`resize` 保留名义字号。开启换行时保持宽度、调整高度；关闭换行时按显式段落和软换行调整宽高，内容减少时也收缩。复用当前预设形状文字内框及段落测量，计入边距、列表和行段距。核心直接查找可容纳文字的最小整数 EMU，避免浮点上界取整多增一单位。未旋转对象按首段水平对齐与框垂直锚定保持对应位置；旋转对象保持中心及方向。原生输入、字符/段落格式、框属性、查找替换和变换完成时，几何与文字合为同一项精确历史。保存重开沿用已写入几何，后续编辑继续重算。行为依据 [ONLYOFFICE 文字内框及位置更新](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L3646-L3870)，实现归 [`text-resize.mbt`](../../../modules/formats/src/pptx/text-resize.mbt)。

无变化不增加历史。形状边长沿用 0.1–14400 pt，尺寸向上取整到 EMU；预设内框求逆不重复测字，最多 16 次文字重排。超限、无可用内框、不收敛、变换锁、缺字体、未知适配内容或输出/历史预算失败均原子拒绝。候选和旧 revision 保持既有保护。组内/继承对象及独立保持直立的旋转文字仍待对应编辑支持；普通水平文字沿用已有裁剪、Canvas 与 PDF 路径。

`editPptxObjects` / `PresentationEditor.editObjects` 支持 `{ action: "textFormat", format }`，其中 `PptxTextFormat` 可包含 `font/size/spacing/bold/italic/color/underline/strike/highlight/script`。至少提供一项，省略项保持；不接受 null 清除或未知字段。font 为不超过 200 UTF-16 单元的实际字体族，不能包含 `|`、换行或以 `+` 开头；主题字体编辑见[主题字体](pptx-editing.md#主题字体)。size 为 1–1024 pt，核心舍入到 0.01 pt。color 为六位 RGB 十六进制，查询和保存规范为小写。字体族同时写入 latin/ea/cs，授权字体与样式仍通过宿主 profile 供应。

`spacing` 为以 pt 表示的字符间距，正值扩展、负值紧缩、0 恢复正常间距。编辑范围为 −1584–1584 pt，核心舍入到 0.01 pt，读写 DrawingML `spc` 的整数百分之一点；无本地定义时沿段落、列表、版式和母版继承。普通范围、折叠光标后续输入、空段尾、多框、母版分级默认格式及字符清除共用现有事务、适配与公共塑形，Canvas/PDF 使用同一组位置。默认文本与母版面板提供同名控件。单位依据 [ONLYOFFICE 字符间距读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L9051-L9052)；本 SDK 使用共享塑形的 ±1584 pt 资源上限，未覆盖原生格式更大的完整数值范围，越界源保留并诊断。实现归 [`text-read.mbt`](../../../modules/formats/src/pptx/text-read.mbt)及 [`text-format-properties.mbt`](../../../modules/formats/src/pptx/text-format-properties.mbt)。

文字模式修改选中字符，光标处创建用于后续输入的格式；空段落写入 `endParaRPr`。对象模式作用于所选本地顶层文本框，混合多选合为一项事务。`{ action: "textAlign", alignment: "left" | "center" | "right" | "justify" }` 修改所涉段落，对象模式修改框内全部段落。`PptxQuery.formatting` 返回上述十项字符属性及 `alignment` 的共同有效值，混合值为 null；`reason` 返回保护原因。无可编辑选择时为 null 占位，不是源格式。两种类型从 `wasm/pptx` 和 `web/pptx` 导出。

`justify` 写回 DrawingML `algn="just"`，导入和继承使用相同有效值。默认格式面板提供“两端对齐”按钮；自动换行的中间行沿公共段落排版扩展间隔，末行保持自然宽度，原生输入、命中、光标、适配和 Canvas/PDF 使用同一组坐标。无变化时不增加历史；清除段落直接格式恢复继承。行为参考 [ONLYOFFICE 段落两端对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L5255-L5261)，源值参考 [TextAlign](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Limit/TextAlign.cpp#L44-L77)。分散对齐和 `justLow` 等变体仍保护，不将其默认为两端对齐。

underline/strike 为布尔值，保存为 DrawingML 的 `u="sng"/"none"` 和 `strike="sngStrike"/"noStrike"`。highlight 接受六位 RGB 或空串；空串清除高亮，写入含 `alpha=0` 的透明颜色以覆盖继承，并保留继承定义。查询空串表示无高亮，null 表示混合或保护占位。高亮沿既有纯色/主题颜色解析；未知内部标记及其他透明度仍保护。公共 `Line::positioned` 在文字前输出高亮，在文字后输出同文字颜色的下划线与删除线，使用塑形光标确定装饰范围；装饰修改保留 glyph、光标和逻辑文字。行尾普通空格保留逻辑文字、光标和高亮，下划线与删除线在内容末尾结束。行首、内部空格和不换行空格计入装饰范围。该规则由十二个独立原生控制及固定 [ONLYOFFICE 行装饰](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/draw/line-draw-state.js#L251-L264)核对。Canvas 与 PDF 共用此图元序列，PPTX 继续在框边界裁剪。DrawingML 属性及高亮写回参考 [ONLYOFFICE RunProperties](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/RunProperties.cpp#L233-L238)和[字符属性输出](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/RunProperties.cpp#L425-L452)。双线、波浪/虚线、自定义线色等其他装饰继续实施。

PPTX 文本框和表格单元格的下划线顶边取文字基线加该行最大文字降部的 40%，上下标沿既有偏移规则处理。文字降部复用按名义字号归一的演示文稿度量，列表标记不参与。线宽仍为名义字号的 1/18。文本、光标和删除线几何沿既有规则。依据 [ONLYOFFICE 下划线偏移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L3158-L3165)及[演示文稿字体度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/DrawingDocument.js#L69-L93)。

script 接受 `baseline`、`superscript` 或 `subscript`，分别写入 DrawingML `baseline=0/30000/-25000`。恢复基线写 0 覆盖继承，清除直接格式移除本地 baseline 并恢复继承。导入按首个有效 baseline 的正负识别上、下标，保留未改源值；此行为遵循 [ONLYOFFICE 读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L8957-L8966)和[写出](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/SerializeWriter.js#L2202-L2205)。查询字号保留名义值，公共布局按 65% 绘制字号及名义字号的 +35%/-14.1% 基线偏移排版，沿用 [ONLYOFFICE 脚本度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/commonDefines.js#L799-L802)。原生输入、命中、光标、选区、适配、Canvas 与 PDF 共用相同文字布局；任意数值偏移编辑仍待支持。

字符操作按需拆分 run，保留范围外文字、字符和段落属性、命名空间、对象身份、几何及其他部件。后续输入继承光标格式，替换范围继承首个选中字的格式。格式、对齐及原生文字共用精确历史；无变化不增加历史。已有缩小适配继续重新测量和保存比例，固定框继续诊断并裁剪溢出。候选、旧 revision、缺字体、锁定、未知 run/格式扩展或输出预算失败保持源和历史。字段、组内和继承对象继续保护。行为参考 [ONLYOFFICE 当前文本范围操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L1373-L1415)。更多文字装饰仍待实现。

`{ action: "clearTextFormat" }` 清除所选 run 的字体、字号、字符间距、粗斜体、下划线、删除线、文字色和上/下标直接定义，恢复段落、列表、版式及主题继承。保留高亮、语言、链接与源间隙；高亮使用独立的空串操作关闭。文字范围按需拆分 run；光标处建立用于后续输入的继承格式，空段落清除 `endParaRPr` 对应覆盖。对象模式清除所选本地文本框的 run 及段尾字符覆盖，保留段落默认字符定义。源中显式写出的默认值也会移除；再次清除不新增历史。语言与高亮保留规则参考 [ONLYOFFICE 字符清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L16926-L16947)。

`{ action: "clearParagraphFormat" }` 清除所涉段落的直接对齐、左/右/首行缩进、行段距、制表位/默认间隔及本地项目符号、编号、符号字体/大小/颜色定义，恢复继承。保留 `lvl`、`defRPr`、字符内容及其元信息；扩展图片项目符号和未支持的编号类型仍保护。段落选择沿用 `textParagraph` 的范围规则，对象模式处理全部所选框。清除沿现有源事务、字体预检、适配与输出预算执行；未知格式标记或失败保持源与历史，撤销精确恢复原属性和选择。默认 UI 提供两个清除按钮，宿主与 Worker 沿 `editObjects` 调用。语义参考 [ONLYOFFICE 段落清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L11606-L11663)。

`{ action: "textParagraph", format }` 修改段距、行距、缩进、方向及列表。`PptxParagraphFormat` 可含 `left/right/first/before/after/line/list/level/rtl/listFont/listSize/listColor/tabs/defaultTab`，至少提供一项，省略项保持。三个标记样式字段和两个制表位字段接受 null，含义见下文；拒绝其他 null 和未知字段。left/right 为 0–4032 pt，first 为 -4032–4032 pt，相对段落起始侧缩进指定首行或悬挂缩进，核心舍入为整数 EMU。before/after/line 使用 `PptxTextSpacing`：`{ unit: "point" | "percent", value }`。段前/段后点值为 0–1584 pt，百分比为 0–1000%；行距点值至少 0.01 pt，百分比至少 0.001%，上限相同。点值和百分比分别保存到百分之一点和千分之一百分比；100% 为单倍行距。输出范围与顺序参考 [ONLYOFFICE TextSpacing](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/TextSpacing.cpp#L90-L162)及[段落属性](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/TextParagraphPr.cpp#L196-L218)。

`tabs` 使用最多 32 项的 `PptxParagraphTab { position, align }`；position 为 0–1584 pt 内的整数 twip，严格递增且不重复，align 为 `left/center/right/decimal`。写入原生 `tabLst/tab`，对齐分别为 `l/ctr/r/dec`，不生成引导符或竖线。`defaultTab` 为 0–1584 pt，舍入到整数 EMU 后写 `defTabSz`；零关闭后续默认间隔。缺省沿 [ONLYOFFICE 演示文稿的 25.4 mm／72 pt](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2889-L2899)。查询返回共同有效值，混合项为 null。DrawingML 的位置和对齐定义见[原生制表位](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.tabstop?view=openxml-3.0.1)。

原生制表位沿段落、列表、版式/母版和默认样式读取，同位置由近层覆盖；合并依据 [ONLYOFFICE 段落继承](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L16450-L16456)及[同位置覆盖](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L15464-L15504)。无继承制表位时，数组替换本地定义，空数组清空；tabs=null 移除本地定义并恢复继承，defaultTab=null 单独恢复默认间隔。改写有效的继承制表位仍须样式级编辑，当前原子保护；恢复本地覆盖可执行。低于 twip 精度、超限或未知原生内容保留源并诊断，带内部注释的列表替换/清除保护。

公共制表位排版同时提供对齐后的字形、光标、选择、适配和 Canvas/PDF。字符、其他段落、属性、对象及部件保持。默认面板提供位置、对齐、间隔、清空及恢复；原生 Tab 文本沿既有粘贴入口，全部与源修改共用精确历史。实现归 [`paragraph-tabs.mbt`](../../../modules/formats/src/pptx/paragraph-tabs.mbt)。

`rtl` 为布尔值，写入 DrawingML 段落方向；读取沿本地、列表、版式/母版和默认属性继承。缺少显式对齐时，RTL 默认右对齐；已有显式对齐仍按物理左右解释。切换方向时镜像当前左右对齐，居中和两端对齐保持，遵循 [ONLYOFFICE SetParagraphBidi](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L16952-L16967)及[非文档段落的默认对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L11257-L11288)。缩进、标记和双向文字使用公共排版器；PPTX 显式提供 LTR/RTL 基础方向，避免阿拉伯文首字符覆盖段落设置。字体、光标、选区、Canvas/PDF 和适配共用同一结果，缓存区分基础方向。`paragraph.rtl` 返回有效布尔值或混合值 null；默认面板显示混合复选状态。清除段落直接格式同时清除方向并恢复继承。局部范围、多框、原生草稿、精确历史与重开沿用已有事务，非法方向源保留并诊断。竖排、多栏继续实施。

文字模式修改光标所在或范围所涉段落，终点恰在下一段开头时不修改下一段；对象模式修改所选本地文本框中的全部段落。`PptxQuery.paragraph` 返回各字段的共同有效值和 `reason`，混合项为 null；保护时为 null 占位。类型和动作从 `wasm/pptx`、`web/pptx` 导出，宿主沿 `editObjects` 队列执行。修改只写目标 `pPr`，保留字符、未改属性、源注释、继承定义、非目标段落、部件及选择。未知间距节点内容保护该框的间距/缩进操作；无变化不新增历史，旧 revision、候选、缺字体、无可用行宽和预算失败均不提交。已有适配框重新计算比例；固定框保留溢出诊断。默认面板按各字段的有效值更新草稿，其他格式命令完成时不清掉输入。

list 使用 `PptxListFormat`：`{ kind: "none" }`、`{ kind: "bullet", value }` 或 `{ kind: "number", value, start }`。字符符号限一个字素、最多 16 UTF-16 单元；编号支持十九种格式：`arabicPeriod/arabicParenBoth/arabicParenR/arabicPlain`，以及 `alphaLc/alphaUc/romanLc/romanUc` 分别与 `Period/ParenBoth/ParenR` 组合，以及 `arabicDbPeriod/arabicDbPlain/circleNumDbPlain`。后面三项使用下述全角/圆圈序号，原生 Period/Plain 标点保持。`Period` 使用句点，`ParenBoth` 使用左右括号，`ParenR` 使用右括号，`Plain` 不加标点；例如 `alphaUcParenBoth` 输出 `(A)`。start 为 1–32767。level 为 0–8；默认 UI 显示第 1–9 级。列表与级别可分别修改，也可和间距/缩进一起提交。查询返回有效列表定义及级别，混合值为 null。移除列表写 `buNone` 覆盖继承，清除段落直接格式移除本地列表定义并恢复继承，保留级别。

导入的 `a:buChar/@char` 允许 1–16 个 UTF-16 单元，整串仍检查 XML 字符及空白/控制符边界。显示与查询取首个 UTF-16 单元，原始属性逐字保留；该单元无效时保护正文。规则依据 [ONLYOFFICE GetPresentationBullet](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L17283-L17304)。例如源 `••` 显示 `•`，源 `AB` 显示 `A`。写入接口仍要求一个可见字素。普通正文编辑保留完整原属性，原样保存、撤销/重做及重开沿既有事务。

字符项目符号使用指定字体。该字体含 Microsoft 符号映射且缺少低字节字符时，排版读取其私用区别名。显示字形与原始字符分别保留。RTL 悬挂列表按段落缩进与符号宽度中的较大值留位，标记位于正文右侧。普通正文编辑保留原字体、方向和标记定义。[OpenType 字符映射](https://learn.microsoft.com/en-us/typography/opentype/spec/cmap)和 [ONLYOFFICE 列表绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/draw/content-draw-state.js#L697-L719)。

RTL 悬挂文字列表在测量时给文本框增加 0.01 mm。换行、正文和列表标记共用这一宽度，测量上限仍为 14400 pt。[ONLYOFFICE 文本框宽度](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L4065-L4070)

图片项目符号接受单个无效果的内嵌 `a:buBlip/a:blip r:embed`。关系按定义所在的源部件解析，复用 PNG/JPEG/GIF 读取、解码及资源预算。高度取有效标记字号除以 `4.043478260869565` 毫米，宽度保留原图比例，底边对齐首行正文基线；24 pt 对应约 16.82498 pt 高。规则依据 [ONLYOFFICE Measure](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/PresentationNumbering.js#L458-L469)及 [Draw](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/PresentationNumbering.js#L532-L544)。图片使用自身颜色，不按标记字体或颜色重绘。标记只出现在首行，不占正文字符或 UTF-16 范围；换行、方向、列、表格、分页及缓存沿共享坐标移动，Canvas/PDF 使用既有图片图元。共享模型以 `ParagraphMarker.image` 和 `Line.markerImage` 分别保存输入与已定位图片。实现归 [picture-bullets.mbt](../../../modules/formats/src/pptx/picture-bullets.mbt)和 [paragraph-marker.mbt](../../../modules/layout/src/paragraph-marker.mbt)。

`PptxParagraphFormatting.list` 的 `{ kind: "picture" }` 表示导入的图片列表，默认面板显示对应类型。正文输入、标记大小、移除或改为已有字符/编号格式、清除直接段落格式及保存重开沿原事务；跨文稿页面导入保留图片及关系。写入接口不接受 `picture`，图片标记创建与剪贴板图片关系迁移仍保护。未知属性、重复标记、注释/处理指令、图片效果、外链、缺失资源、内容类型不符及资源超限不静默降级；保留源或按既有输入错误拒绝。当前真实文件与严格视觉范围归[测试说明](../testing.md#当前兼容证据入口)。

编号在各文本框内计算：向前跳过更深层段落，遇到更浅层、不同类型或不同起始值时重新起算；同级空段落不推进后续数字。规则依据 [ONLYOFFICE GetBulletNum](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L10678-L10717)。字母与罗马数字沿用 DOCX 的公共序号格式化，字母采用 aa、bb 等重复规则。逻辑文字与复制内容保留原段落文字，编号是布局标记。

空段保留列表定义、标记测量、缩进、行高和光标范围；文档绘制省略字符、编号和图片标记，再次输入后恢复绘制。编号仍按既有规则跳过空段。规则依据 [ONLYOFFICE 空段标记绘制条件](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/draw/content-draw-state.js#L700-L725)。PPTX 在行定位后省略可见标记，保留共享排版器的测量与缓存，不改变 DOCX 行为。源属性、资源校验、精确历史和保存重开保持。

首次应用列表按首个字符字号建立悬挂缩进，移除列表恢复标记所在左边界；显式 left/first 优先。规则参考 [ONLYOFFICE 列表缩进](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L10616-L10643)。保留已有符号字体、字号、颜色和其他段落元信息。标记进入公共段落布局，参与换行、行高、字体预检、适配及 glyph 预算，使用当前 36 pt 默认制表间隔分开标记与正文；Canvas 和 PDF 共用相同位置。已有字符内容、非目标段落、部件、选择及精确历史保持。格式值沿 [ONLYOFFICE DrawingML 编号枚举](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Limit/TextAutonumberScheme.cpp#L46-L88)，括号与标点沿 [PresentationNumbering](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/PresentationNumbering.js#L188-L298)；源保留完整类型，导入、修改、原生续号和重开使用同一标记规则。默认面板列出各格式的标记示例，Wasm 与 Worker 参数/响应校验共享同一允许列表。扩展图片符号、地区编号和自定义制表设置仍待支持。

`listFont/listColor` 使用与字符格式相同的字体家族及六位 RGB 边界。`listSize` 使用 `{ unit: "point" | "percent", value }`，支持 1–1024 pt 或正文首字符字号的 1–400%，分别舍入到百分之一点和千分之一百分比。查询返回有效字体家族、颜色及继承后的大小单位/值；随文字大小返回 100%，混合字段为 null。显式样式分别写 `buFont/buSzPts/buSzPct/buClr`；传 null 写对应的 `buFontTx/buSzTx/buClrTx`，覆盖继承并跟随正文首字符。默认面板逐项设置，并可一次恢复三项正文样式；`clearParagraphFormat` 则移除本地定义并恢复列表/版式继承。规则依据 [ONLYOFFICE 标记属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L12797-L12876)。只修改所选段落的对应属性，保留字符、列表定义、字体元信息和其他部件；相同直接定义不新增历史。重复或带未知内容的目标属性保护整项事务，缺字体与输出预算失败也不提交。

字面查找由 `findPptx` 命令和 `PresentationEditor.find(text, options?)` 提供。`PptxFindOptions` 可含 `matchCase/wholeWord/all`；前两项默认 false，all 默认 true，并包含隐藏页。all=false 只搜索请求指定的 slide，结果导航后仍保留原搜索范围。扫描按页面顺序及本地对象源顺序进行，跨 run/段落匹配，不跨文本框或表格主格；母版/版式装饰与备注不参加本次查找。页面/对象顺序参考 [ONLYOFFICE Slide.Search](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L346-L355)。分组内或带字段/扩展的已解析文字可返回结果及保护原因，替换支持本地顶层文本框及普通表格，保留各自源与布局边界。

`PptxSearchResult` 返回 revision、truncated 及最多 1000 条 matches；每条含 `slide/object/anchor/focus/hidden/snippet/reason`。anchor/focus 是该对象文字的 UTF-16 范围，并对齐字素边界；跨段落使用 LF，软换行使用 U+2028，编号标记不属于逻辑文字。与 DOCX 共用公共字面搜索：简单 Unicode 小写映射、不忽略重音、全词使用字母/数字边界，结果不重叠；不提供正则、通配符或语言分词。查找不改变选择、源、revision 或历史。

`replacePptxMatches` 携带同一 revision、原 slide/text/options、replacement、可选 index 和字体 profile；不提供 index 时替换全部。核心重查结果后定位各对象，按对象范围提交一项跨页历史。普通段内替换合并源补丁并继承首个选中字的字符属性，保留未选 run、段落属性及其他部件；跨段落或 LF 替换复用结构编辑。有变化时，单个替换定位到新文字末尾，全部替换保留当前页/对象并调整已有文字选区。文字选区内按左右箭头时，只收起到对应边界；Shift 继续扩展选区。无变化不新增历史，任一保护、缺字体/字形、适配或输出失败均保留所有页面及历史。

表格按行顺序逐个主格匹配，延续格不重复参与；片段只包含该格，anchor/focus 仍为整表文字位置。普通格及合并格内可跨段落匹配和插入 LF/U+2028，不跨格串接相邻文字。替换沿既有单元格源补丁和行高适配，保留网格、跨度、框属性、未改格及部件；与文本框或隐藏页的结果合为一项原子历史。整页保护、文字锁、字体、资源及输出限制保持。依据 [ONLYOFFICE 逐格搜索](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L19680-L19689)；左右收起规则依据 [MoveCursorLeft](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L5931-L5968)和 [MoveCursorRight](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L6051-L6095)。

搜索文本与 replacement 各最多 32767 UTF-16 单元；replacement 接受 LF/U+2028，拒绝 CR 和非法 XML 字符。搜索总文字限 1048576 单元，截断结果禁止全部替换；结构批次另受源文字长度乘匹配数累计 64 Mi 单元和 4 MiB 历史预算限制，普通批次不按匹配重复解析整页。公共原生生成文字也在构造 XML 前限制到 2 Mi 单元。宿主的 `find/selectMatch/replaceMatches` 沿既有队列执行，并绑定 documentId/revision；换文档或文字变化后返回 stale-search。默认面板提供当前页/全部页、大小写/全词、结果定位、单个/全部替换、保护原因及过期提示。隐藏页结果可直接定位。

支持矩形、椭圆、直线与文本框的核心路径；PNG/JPEG、矩形源裁剪、旋转/翻转和组合坐标变换。普通视图的继承对象继续只读；源视图编辑当前部件。组内形状文字、几何、形状/图片外观和同组复制/删除/层次/对齐可编辑；同组组合及逐级取消组合可沿原入口编辑。图片不发起外链请求，源压缩字节与关系不改；只为当前页准备屏幕资源。全稿 PDF 临时准备所选页资源，仍受累计图片/输出预算约束，失败不返回截断文件。

未知可见对象阻止点穿；无确定边界时，该页直接画布编辑只读，查询/保存及其他页仍可用。静态 PDF 遇到可见未支持内容、效果或未解决适配时返回页/对象原因。动画/切换只保留源。保存及全部撤销保留原解压部件；输出重新校验 ZIP/XML/OPC，不承诺整个 ZIP 字节一致。

沿用文件、字体、图片、Canvas 和 PDF 预算，另有以下上限。预算不等同于堆峰值或性能保证。

| 对象 | 上限 |
| --- | --- |
| 页数 / 每页对象身份 / 全稿可见对象 | 256 / 4096 / 16384 |
| 依赖树 / 组合层级 | 2048 个源部件 / 16 层 |
| 幻灯片或对象尺寸、位置绝对值 | 14400 point；线可有一个零尺寸轴 |
| 幻灯片文本框 / 单段 / 全稿幻灯片文字 | 32767 / 4096 / 1048576 UTF-16；每框最多 256 段 |
| 字体键 / 图片资源 | 各 256；图片最大 4096×4096、单图 4194304 像素、RGBA 累计 16 MiB |
| 布局 / PDF 图元 | 每页 262144 glyph；整稿 PDF 1048576 图元；通用绘制仍受前述批次预算约束 |
| 历史 / 宿主队列 | undo+redo 共 100 项、XML/图片 payload 共 4 MiB，另有 64 MiB 音视频历史；编辑与指针意图队列各 64 项，指针预览只保留待发送末次坐标 |
| 内嵌音视频 | 单资源 16 MiB、累计 64 MiB、64 项，按原生关系去重；封面另受图片预算约束 |

P6 基础与检查边界归 [P6 结果](../../implemented/p6-pptx-editing.md)，已交付创作能力归 [P12](../../implemented/p12-pptx-core.md)，其他兼容归 [P14](../roadmap.md#p14-兼容与性能已完成)。Chromium 受控输入事件已验证；没有追加系统输入源、Windows/PowerPoint、VoiceOver、其他浏览器或性能验收。

### 连接线

`PresentationEditor.editObjects({ action: "insertConnector", kind, start, end })` 创建原生 `p:cxnSp`。必填 `kind` 与原生预设的对应关系见下表。`connectorEndpoints` 用相同的类型和两端参数修改唯一选中的连接线；显式切换类型与端点修改合为一项历史，新类型恢复默认调节点。MoonBit 使用 `InsertConnector(kind, start, end)` / `ConnectorEndpoints(kind, start, end)` 及 `ConnectorEnd`，Wasm/Web 导出 `PptxConnectorEnd`：`{ x, y, target, site }`。坐标使用磅；`target=""` 表示自由端点，`site` 必须为 0。创建时连接线及目标位于顶层。编辑时 `target` 须属于同一源部件、同一直接父容器；坐标由目标的原生连接点计算，输入坐标仍须有限且有界。自由端点与查询端点始终使用页面坐标。

| kind | 原生预设 | 调节导引 |
| --- | --- | --- |
| `straight` | `straightConnector1` | 无 |
| `rightAngle` | `bentConnector2` | 无 |
| `elbow` | `bentConnector3` | adj1 |
| `elbow4` | `bentConnector4` | adj1、adj2 |
| `elbow5` | `bentConnector5` | adj1、adj2、adj3 |
| `curved2` | `curvedConnector2` | 无 |
| `curved` | `curvedConnector3` | adj1 |
| `curved4` | `curvedConnector4` | adj1、adj2 |
| `curved5` | `curvedConnector5` | adj1、adj2、adj3 |

矩形、圆角矩形及矩形图片支持 0 上、1 左、2 下、3 右。椭圆和圆环支持 0 上、1 左上、2 左、3 左下、4 下、5 右下、6 右、7 右上。其余已支持的闭合预设也使用原生连接点：三角形、直角三角形、平行四边形、五边形、六边形及左右双向箭头各 6 个，八边形及上下双向箭头各 8 个，七边形 7 个、十边形 10 个、十二边形 12 个，四角星 4 个、五角星 5 个、六角星 6 个、七角星 7 个、八角星 8 个、十角星 10 个、十二角星 12 个、十六角星 16 个、二十四角星和三十二角星各 4 个，梯形、菱形、十字、燕尾形、五边形箭头及其他实心箭头各 4 个。端点索引的传输与原生读取上限为 15，连接时还须小于实际目标的连接点数量；自由端点索引保持 0。索引遵循 `CreateGeometry.AddCnx` 顺序；除上述命名点外，默认面板按原生序号显示。`PptxObject.connectionSiteCount` 返回实际数量，不能连接的对象为 0。连接点经过目标的旋转和翻转矩阵，再量化为整数 EMU。目标调节值修改、移动、独立宽高缩放、旋转、翻转和框适配时，同一事务更新连接线的 `xfrm`，保留 `stCxn/endCxn` 引用。变换候选使用相同规则，取消不写源。母版和版式沿源视图编辑，普通页继续保护继承对象。

`PptxObject.connector` 对连接线返回 `{ kind, start, end, reason }`，其他对象为 `null`。无法解析端点时，类型和两端均为 `null`，并返回保护原因。默认面板可创建或切换连接线类型，选择两端的对象和命名连接点，修改自由坐标或断开连接。线宽、颜色、虚线、装饰及 Canvas/PDF 路径复用既有直线实现。端点写入和目标联动各随本次编辑形成一项历史，保存重开后保留原生连接关系。

双段直角折线在局部框内沿 `(0,0)`、`(w,0)`、`(w,h)` 绘制，不含调节导引。翻转、旋转和零尺寸轴沿既有矩阵，箭头取首末非零段方向。命中、Canvas/PDF、端点拖动、目标联动、类型切换、组合复制和精确历史共用既有路径；未知导引继续保护。固定转折不自动避障。几何依据 [ONLYOFFICE 直角折线预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L1214-L1221)，未复制执行代码。

三段折线的原生 `adj1` 指定转折横坐标，缺省为框宽的 50%；当前支持框内 0–100%，原生导入、现有形状调节面板及拖动手柄使用同一值，恢复时移除局部声明。主体沿起点、转折上端、转折下端、终点绘制；箭头取实际首末非零段方向，水平或垂直退化仍保持。命中、Canvas 与 PDF 共用该路径。目标联动、端点拖动及组合复制保留类型与调节点；显式切换类型受 `noChangeShapeType` 锁保护。框外调节点、未知或含注释的几何替换继续保护源，不自动规划避障路径。依据 [ONLYOFFICE 折线预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L1222-L1232)。

四段折线 `bentConnector4` 使用两个原生导引。`adj1` 指定转折横坐标，`adj2` 指定转折纵坐标，均缺省为 0.5，当前沿用框内 0–1 范围。路径为 `(0,0)`、`(w*adj1,0)`、`(w*adj1,h*adj2)`、`(w,h*adj2)`、`(w,h)`。水平手柄位于 `(w*adj1,h*adj2/2)`，垂直手柄位于 `(w*(1+adj1)/2,h*adj2)`；默认面板分别显示水平和垂直转折位置。修改一个导引保留另一个，恢复只移除所选局部声明。原生导入、两个控件、旋转/翻转后的拖动候选、端点联动、类型切换、组合复制、箭头、命中、Canvas/PDF、精确历史及重开共用已有事务。框外导引及未知几何继续保护。依据 [ONLYOFFICE 四段折线预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L1234-L1252)，未复制执行代码。

五段折线 `bentConnector5` 使用三个原生导引，均缺省为 0.5，当前支持框内 0–1。设 `x1=w*adj1`、`y2=h*adj2`、`x3=w*adj3`，路径为 `(0,0)`、`(x1,0)`、`(x1,y2)`、`(x3,y2)`、`(x3,h)`、`(w,h)`。三个手柄分别位于 `(x1,y2/2)`、`((x1+x3)/2,y2)`、`(x3,(h+y2)/2)`，沿水平、垂直、水平轴修改各自导引，保留其余值。两个横坐标不强制排序，默认中段可重合。默认控件分别标记第一水平、垂直和第二水平转折位置；导入、候选取消、目标联动、类型切换、组合复制、箭头、Canvas/PDF 与精确历史沿上述路径。依据 [ONLYOFFICE 五段折线预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L1253-L1276)，未复制执行代码。

双段曲线沿相同的 `adj1`、默认值及框内范围编辑。设框宽高为 `w/h`，转折横坐标为 `x=w*adj1`；起点为 `(0,0)`，第一段的控制点为 `(x/2,0)`、`(x,h/4)`，终点为 `(x,h/2)`，第二段的控制点为 `(x,3h/4)`、`((w+x)/2,h)`，终点为 `(w,h)`。Canvas/PDF 保留两段原生三次贝塞尔命令。箭头取首末非零控制方向，包含调节点极值和零尺寸轴。核心命中按相同控制点细分，平直误差阈值为 0.01 pt、最多 12 层；绘制不使用采样折线。类型切换、目标联动、组合复制和历史沿上述连接线事务。几何依据 [ONLYOFFICE 曲线预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L2414-L2426)，细分参考 [partition_bezier4](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Path.js#L3779-L3812)；有界命中实现归 [`connector-path.mbt`](../../../modules/formats/src/pptx/connector-path.mbt)，未复制上游执行代码。

单段、三段和四段曲线分别使用原生 `curvedConnector2/4/5`，通过同一类型选择器创建或切换。单段没有导引，路径为 `M(0,0) C(w/2,0,w,h/2,w,h)`，非空导引列表受保护。三段/四段曲线分别带两个/三个导引，缺省均为 0.5，当前沿用框内 0–1；XY 手柄分别复用上述四段/五段折线的位置与轴，默认面板使用相同标签。核心按原生导引输出三段/四段三次贝塞尔，连续段保留各自控制点；绘制和 PDF 使用完整命令，命中按段复用现有有界细分，箭头取首末非零控制方向。类型切换、目标联动、组复制、零尺寸轴、旋转/翻转候选、精确历史及重开共用已有事务。几何依据 [ONLYOFFICE 单段曲线](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L2407-L2413)、[三段曲线](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L2428-L2450)和[四段曲线](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L2451-L2480)，实现归 [`connector-path.mbt`](../../../modules/formats/src/pptx/connector-path.mbt)，未复制执行代码。

单选受支持连接线时，`selectionPptx.handles` 按起点、终点返回两个实际页面坐标。默认画布可直接拖动这两个手柄；`beginPptx` 使用 `kind="connector"`，`dragPptx` 的 `handle=1/2` 对应起点/终点，`dx/dy` 始终相对手势起始端点，另一端保持。可选 `tolerance` 为 0–64 pt，缺省 0 表示不吸附；默认宿主按当前预览比例换算 6 CSS px，不乘 DPR。核心按上层对象优先、原生连接点索引顺序寻找半径内的同一直接父容器中的本地受支持目标，沿用上述旋转/翻转和 EMU 量化。离开连接点范围后，该端变为自由端点。候选只更新临时页，释放时写回端点及连接关系并提交一项历史，返回起始状态不增加历史；Escape、指针取消及丢失捕获沿原候选取消路径恢复。旧 revision/候选、错误手柄、越界、退化为零长度、锁定和输出预算失败保持最后有效候选与已提交源。

有连接的线通过画布端点或面板修改，直接变换继续保护。连接线与全部引用目标同时选择时可组合或复制；整个组可复制，副本的原生引用映射到副本目标。同一直接父容器中的闭合图形支持组内端点编辑/吸附、成员移动/旋转、组缩放/旋转/翻转、嵌套及取消/再次组合。核心逆变换页面端点并写整数 EMU，复用既有组边界归一化，候选与提交保持一致。重复原生端点及连接关系不增加历史。默认列表选择连接线时进入对象模式。拆散引用的组合/复制、仍被外部引用的目标删除、跨父容器连接、框外导引、自定义或未知预设连接点继续保护。未知连接元数据、非整数或越界索引、失去目标、锁定和输出预算失败保留源与历史；受保护连接线也阻止其目标发生无法写回的几何变化。沿用对象数量、坐标、XML、历史和输出预算。

连接点计算归 [`connection-sites.mbt`](../../../modules/formats/src/pptx/connection-sites.mbt)。三角形及箭头等点坐标依据 [ONLYOFFICE CreateGeometry](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8525-L8620) 的原生导引。实现归 [`connector.mbt`](../../../modules/formats/src/pptx/connector.mbt)、[`connector-edit.mbt`](../../../modules/formats/src/pptx/connector-edit.mbt)、[`connector-gesture.mbt`](../../../modules/formats/src/pptx/connector-gesture.mbt)及 [`pptx-connectors.tsx`](../../../packages/pptx/src/react/pptx-connectors.tsx)。吸附规则参考 [ONLYOFFICE ResizeTrackShapeImage](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L370-L450)及 [Geometry.findConnector](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Geometry.js#L1174-L1187)。组内连接重算及父组逆变换参考 [ONLYOFFICE CnxShape](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CnxShape.js#L624-L684)。原生点顺序参考 ONLYOFFICE `CreateGeometry` 的[矩形](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L6741)、[椭圆](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L3100)、[圆角矩形](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L7195)和[直线连接线](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8272)，未复制上游执行代码。

### 基础艺术字

`editObjects({ action: "insertWordArt", preset, text })` 在当前页面或源视图创建标准 DrawingML 文字框。`preset` 支持 `blue`、`gold`、`red`、`purple`、`green-italic` 五种纯色预设；颜色分别为 4472C4、FFC000、C00000、7030A0、70AD47。文字为 Arial、54 pt、粗体，绿色另带斜体。预设写入普通 run 和段末字符属性，不添加私有样式状态；后续文字、格式、查找、复制、变换和删除沿已有对象操作。宿主须提供对应粗体及粗斜体字体，缺字体不提交。

核心按实际字体度量生成不换行、水平/垂直居中、随文字调整大小的框，再置于页面中央。全部文字成为活动选择，默认面板把焦点交还原生输入，首次键入可直接替换。输入、字号或框设置变化复用既有自动适配；首次插入和后续输入各自进入一项精确历史。保存重开、Canvas、PNG/JPEG 和静态 PDF 使用同一排版。其他对象、关系及未改部件保留。

`text` 必须含非空白内容，沿现有对象文字规则接受有效 XML 字符、LF 段落、软换行和 Tab；最多 32767 个 UTF-16 单元、256 段，每段最多 4096 单元。旧 revision、活动候选、放映、保护、字体及尺寸/输出/历史预算失败原子拒绝。框尺寸沿既有 14400 pt 上限。文字描边、渐变、阴影、弯曲及三维艺术字继续实施，已有变形节点继续诊断并保护源。

不换行只关闭自动断行；对齐、RTL、制表位和命中继续使用实际框宽。核心不再用极大虚拟宽度对齐，并在段落缓存中区分是否换行。实现归 [`word-art.mbt`](../../../modules/formats/src/pptx/word-art.mbt)、[`text-frame.mbt`](../../../modules/layout/src/text-frame.mbt)和默认 [`word-art.tsx`](../../../packages/ui/src/word-art.tsx)。文字框、无底色/边框、54 pt、居中与自动适配参考 [ONLYOFFICE createTextArt](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L8794-L8912)，插入历史和整段选择参考 [AddTextArt](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L11071-L11103)。五种纯色配方按 GenOffice 功能清单选择；未复制上游执行代码。

### PPTX 数学公式

形状文字和普通表格中的 `a14:m/m:oMath` 已接通原生读取、数学排版及 Canvas、PNG 和 PDF。单个 `m:oMathPara` 支持左/中/右对齐，`centerGroup` 按居中处理；显示公式独占段落，行内公式可与普通文字混排。已知 `mc:AlternateContent/Choice` 选择 DrawingML 2010 数学内容，保留原兼容后备源。包装形式依据 [ONLYOFFICE MathParaWrapper](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Runs/MathParaWrapper.cpp#L111-L130)。

公式与 DOCX 共用[有界数学结构](docx-math.md#docx-行内分数)、字体度量和图元。分数、上下标、根式、定界符、求和/积分及矩阵的读取归 [共享 OMML 读取器](../../../modules/formats/src/internal/omml/math-read.mbt)。普通正体或数字沿既有规则读取，统一字体/字号/RGB 支持原生 Word 属性和基本 DrawingML `a:rPr`；DrawingML 可使用显式字号、纯 RGB 与相同的文字字体槽。主题字体、主题色、透明度和其他数学字符效果仍受保护。源未声明字体时使用 `Cambria Math`，由宿主提供实际字体及 profile。

独立公式使用较大的真实字体运算符，原生 `undOvr` / `subSup` 分别显示上下堆叠 / 右侧上下限，缩小参数仍用普通符号和右侧位置。模型、字体要求及 PDF 文字映射边界归[共享求和与积分布局](docx-math.md#docx-行内求和与积分)。文字框字号适配保留显示上下文，更新、无操作、精确历史及重开沿既有公式事务。

`editObjects({ action: "insertMath", latex, format, x, y, width, height })` 创建原生公式文字框。选中单个本地文字框后，`{ action: "appendMath", latex, format, position: "start" | "end" }` 在首尾插入独立公式段落。`latex` 复用 [DOCX 有界语法](docx-math.md#docx-latex-公式编辑)。共用的 `MathFormat` 为 `{ family, size, color }`；字体名最多 255 个单行单元，字号为 0.5–409 pt、精度 0.01 pt，颜色为六位 RGB。默认面板提供相同的插入和外观操作。

对象查询的 `equations` 返回 `{ node, latex, format, reason }[]`，其中 LaTeX 为共享打印器的规范化表达。选中所属对象后，`{ action: "updateMath", target, latex, format }` 修改整式，`{ action: "deleteMath", target }` 删除整式；`target` 为 `{ object, revision, node }`，必须来自当前查询。过期版本或错误对象拒绝执行。形状混排、显示公式和普通表格中的已有公式均可修改，保留周边文字与段落属性。无变化的修改不新增历史。

公式通过既有段落图形框参与基线、断行、框内边距、垂直锚定与表格单元格位移，不转换为图片。对象查询的 `text` 返回可读线性表达，普通文字输入仍通过 `textReadOnlyReason` 保护公式结构。空后备和已验证的单个纯文字后备可随对象或整页复制；修改表达时同步纯文字后备。未知后备、批注式 XML 内容、编辑锁和其他未知扩展保护相应操作。字体、布局和预算失败保留源与历史。创建、修改、删除、精确混合历史及保存重开沿核心事务，实现归[公式编辑](../../../modules/formats/src/pptx/math-edit.mbt)。局部数学格式和更多结构继续实施。

单式沿 16 层、256 个结构节点和 4096 个文字单元的上限，PPTX 单式 XML 另限 2048 节点。文字框、页面字形、图元、资源和历史预算沿既有路径；未支持的数学源给出对象诊断并保护源，缺数学字体时输出明确失败。实现归 [PPTX 数学读取](../../../modules/formats/src/pptx/math-read.mbt)和[段落绘制](../../../modules/formats/src/pptx/layout.mbt)。DrawingML 数学字符属性依据 [ONLYOFFICE 数学内容](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Math/oMathContent.cpp#L2393-L2406)。

### PPTX 基础图表

`editObjects({ action: "insertChart", kind, title, data, x, y, width, height })` 插入簇状柱形图 `column`、条形图 `bar`、堆积柱形图 `stackedColumn`、堆积条形图 `stackedBar`、百分比堆积柱形图 `percentStackedColumn`、百分比堆积条形图 `percentStackedBar`、带圆形数据点的折线图 `line`、堆积折线图 `stackedLine`、百分比堆积折线图 `percentStackedLine`、饼图 `pie`、面积图 `area`、堆积面积图 `stackedArea`、百分比堆积面积图 `percentStackedArea`、散点图 `scatter`、雷达图 `radar` 或圆环图 `doughnut`。选中单个本地图表后，`{ action: "chartData", kind, title, data }` 修改类型、标题和数据。对象查询的 `chart` 返回 `{ kind, title, data, legend }`，其他对象为 `null`。`chartDataReason` 返回当前对象数据修改的独立保护原因，空串表示可用；核心写入与默认面板使用相同原因。非图表对象返回具体原因，传输层拒绝缺失或非字符串字段。

`data` 为 TSV，首行给出类别轴标题和系列名，首列为类别，其余为有限数值或空值。支持 1–32 个系列、1–256 个类别，输入和规范化 TSV 均最多 65536 个 UTF-16 单元；标题及各标签最多 256 个单行单元。核心复用 XLSX 分隔文本导入，公式作为文字处理并在数值列拒绝。空值保留间隙，零值没有柱高；数轴包含零并采用 1/2/5/10 刻度间隔。参考 [ONLYOFFICE 数轴计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L2678-L2736)。

MoonBit 生成原生 `graphicFrame`、`barChart`、`lineChart`、`pieChart`、`doughnutChart`、`areaChart`、`scatterChart` 或 `radarChart`、系列公式/缓存、关系和实际嵌入 XLSX，使用固定配色、Arial 及图例。公共图元输出 Canvas 与静态 PDF。框最小为 180×150 点，移动、缩放、对齐、层级、删除复用对象事务。直接旋转和翻转保持保护。普通本地图表可与受支持对象组合；图表文字通过数据面板编辑，支持单选组内图表。

原生样式 18/118 的无标题饼图和环形图可读取为只读外观。图表和绘图区须声明透明背景、无描边与无效果。各数据点须有显式纯色填充，图例和标签须隐藏。图表自己的 `clrMapOvr` 优先于幻灯片映射。颜色变换和 Alpha 复用主题读取。环形图支持多系列、起始角度和系列分离量。各系列须共享类别缓存。单点分离量可覆盖系列值，超过系列值时仍保护。原 XML、缓存、嵌入工作簿和关系保持；数据修改和复制继续拒绝，普通保存和页面背景编辑可用。

此原生外观使用既有路径和 `ChartData`，没有新增宿主绘图协议。图表数据沿 32 个系列、256 个点和 1 MiB XML 上限。原生框为 24–14400 pt，默认内边距为 14 个 CSS 像素。分离量先缩小外半径，再沿扇区中线偏移。曲线在坐标轴处划分，内圈反向绕序。几何依据固定 [ONLYOFFICE 10.0.0.170](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Charts/ChartsDrawer.js) 的默认边距和 `drawDoughnutChart`，圆弧沿既有 ONLYOFFICE 椭圆算法。颜色覆盖另对照 [LibreOffice 原件断言](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sd/qa/unit/import-tests4.cxx#L904-L933)。实现归 [原生缓存读取](../../../modules/formats/src/internal/chart/native-pie.mbt)、[图表主题适配](../../../modules/formats/src/pptx/chart-read.mbt)与[共享扇区路径](../../../modules/layout/src/chart-pie.mbt)。未复制上游执行代码。

普通视图中的本地顶层图表支持 `editObjects({ action: "duplicate", dx, dy })` 和默认“复制对象”按钮。可与同父的普通对象一起多选复制，保留选择顺序、活动对象、内容、名称及非目标源。副本分配新对象身份、独立图表 XML、嵌入工作簿及关系；初始工作簿保留原始字节，后续改数据互不影响。复制、资源及内容类型合为一项精确历史。缓存与工作簿不一致、未知图表资源关系、复制锁、字体、布局或预算失败时整项拒绝。完整组合及组成员中的普通图表沿同一路径分配独立资源；复制前检查全部新成员的字体和布局。母版/版式图表复制继续保护。规则参考 [ONLYOFFICE 图表复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L4959-L5028)，实现归 [`chart-copy.mbt`](../../../modules/formats/src/pptx/chart-copy.mbt)和 [`object-copy.mbt`](../../../modules/formats/src/pptx/object-copy.mbt)。

系统复制、剪切及跨文稿重复粘贴归[对象剪贴板](#pptx-对象剪贴板)。该路径按已核对的缓存重建独立普通值工作簿，排除原嵌入文件中的其他工作表；同稿“复制对象”继续保留原工作簿字节。

普通图表可参与组合与逐级取消组合，成员顺序和原生资源归属保持。组整体移动、缩放、旋转和翻转使用既有组矩阵；成员移动后沿图表框重算祖先边界，其他成员的页面姿态保持。取消组合把继承旋转/翻转写到 `p:xfrm`，重开后 Canvas/PDF 继续使用同一姿态。原生组复制为每个子图表创建独立图表和完整工作簿；系统复制完整组时，子图表沿上述快照路径重建独立普通值工作簿。组内及取消组合后均可分别改数据。数据编辑仅更新图表 XML 和工作簿，保留原生组、成员框、继承姿态及其他成员源；资源写回沿一项精确历史，无变化时不改源。组选择/文字锁和共享图表资源保持保护，仅限制组缩放时允许改数据。工作簿与缓存一致性仍在写入前核对。该成员编辑沿 [ONLYOFFICE 图表设置入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L3847-L3870)的组内选择语义，复用 [chart-edit.mbt](../../../modules/formats/src/pptx/chart-edit.mbt)。直接图表旋转/翻转控件继续实施。表格组合归[普通表格](pptx-show.md#pptx-普通表格)。实现复用 [group-bounds.mbt](../../../modules/formats/src/pptx/group-bounds.mbt)、[object-group.mbt](../../../modules/formats/src/pptx/object-group.mbt) 和 [object-copy.mbt](../../../modules/formats/src/pptx/object-copy.mbt)，成员复制依据 [ONLYOFFICE GroupShape.copy2](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L310-L339)。

#### 图例显示与位置

`PptxChart.legend` 接受 `"none" | "top" | "bottom" | "left" | "right"`，插入、占位符填入及 `chartData` 共用此设置。省略时饼图/圆环图默认右侧，其他类型默认底部；查询总是返回实际 `legend`。默认数据面板提供相同选项。隐藏时不写 `c:legend`，四边位置写标准 `legendPos=t/b/l/r` 和 `overlay=0`。类型切换、独立对象/页面复制、精确历史及保存重开保留设置；数据未变时复用原工作簿路径和字节，不因修改图例、标题或类型而增加嵌入工作簿。

核心按真实字体度量安排顶部/底部图例的行列，并为绘图区预留空间；左右图例竖排。饼图/圆环图使用类别名称和扇区颜色，其他类型使用系列名称与相同颜色、线条或标记；堆积图的竖排图例按原生逆系列顺序排列。条目过多时显示剩余数量，单项文字裁剪在自身边界内。Canvas、PNG 和 PDF 共用核心布局。原生自定义字体/外观、覆盖图例、手动布局、条目删改和右上角位置继续保护源。位置与顺序参考 [ONLYOFFICE 图例布局](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L7725-L7855)，实现归 [`chart-legend.mbt`](../../../modules/layout/src/chart-legend.mbt)。

`editSlides({ action: "copy" })` 和默认“复制页”按钮也支持含图表的页面。每个本地图表部件及嵌入工作簿克隆到新路径，页面关系指向副本，原页和新页可分别改数据。原本不同的图表保持独立；源页内部共用同一图表部件的关系结构在新页中保留，数据编辑仍遵守共享资源保护。已删除图表留下的关系也按相同原生配置和数据一致性规则克隆，未知资源保持保护。图表与工作簿、备注、批注、对象引用、隐藏状态和页面引用沿现有整页事务共同进入精确历史。删除页面继续保留未回收的图表资源。实现复用上述图表资源模块及 [`slide-copy.mbt`](../../../modules/formats/src/pptx/slide-copy.mbt)、[`slide-add.mbt`](../../../modules/formats/src/pptx/slide-add.mbt)。

`stackedColumn` 和 `stackedBar` 按类别把正值与负值分别沿零轴累计，系列按源顺序相接；空值不推进累计，零值没有可见段。数轴根据每类正、负总和取界，沿相同 1/2/5/10 刻度规则生成。所有系列共用一个类别位置，`gapWidth=150`、`overlap=100`；条形图保留原类别方向。原生 `barChart` 按方向保存 `barDir=col/bar` 和 `grouping=stacked`，缓存、公式及嵌入工作簿保留原数值。插入、数据修改、占位符填入、复制及类型切换复用原事务、独立资源和精确历史，默认面板提供两种类型。总和超出数值范围时原子拒绝；其他重叠/样式及组合继续保护。算法依据 [ONLYOFFICE 堆积轴取界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L1520-L1606)及[同号序列累计](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L3554-L3570)，实现归下述图表数据及布局模块，未复制上游执行代码。

`percentStackedColumn` 和 `percentStackedBar` 把每类原数值除以该类的绝对值总和，再分别累计正负比例。归一化先按最大绝对值缩放再求和，极大值不会因分母求和溢出；空值不参与，零值不产生可见段。数轴按比例总和取界、包含零、沿已有刻度规则并限制在 −100%–100%，显示整数百分比；全空或全零使用 0–100%。原生分组为 `percentStacked`，数轴使用小数范围及 `numFmt=0%`，系列缓存、TSV 和嵌入工作簿继续保存原数值。类型切换、原生查询、默认控件、独立复制及精确历史共用原入口。归一化和同号累计依据上述 [ONLYOFFICE 堆积计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L1520-L1606)，轴边界参考[百分比轴取界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L2693-L2726)。核心数据和绘制共享归一化结果计算，未知数轴格式仍保留源保护。

折线图按类别中心连接相邻非空数据点，空值断线，孤立点及零值仍显示圆形标记。线宽固定为 1.5 点，标记直径为 5 点；图例采用相同线段与标记。原生配置为 `standard`、`smooth=0`、`dispBlanksAs=gap`，与布局共用数据。曲线、堆积、其他标记及跨空值连接继续保护。行为参考 [ONLYOFFICE 折线与空值处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L9042-L9185)和[圆形标记](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L3158-L3205)。

饼图显示首个系列，按绝对值计算扇区。零值和空值不占面积，全零或全空时绘图区留空。全部系列保留在查询、原生缓存及嵌入工作簿中，切回其他类型仍可使用。核心先按最大绝对值缩放再求和，避免有限数值的总和溢出。第一片从十二点方向顺时针开始，类别颜色循环使用八色。TSV 首格作为副标题，和主标题写入原生富文本标题的两个段落。饼图不生成数轴，默认右侧图例按框高显示，放不下时显示剩余项数量；完整数据仍可编辑。当前不提供角度、分离扇区、数据标签或配色设置。语义参考 [ONLYOFFICE 饼图与首个系列](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L12238-L12346)，实现归 [`chart-pie.mbt`](../../../modules/layout/src/chart-pie.mbt)。

圆环图使用 `kind: "doughnut"`，插入、数据修改及占位符填入接受可选 `holeSize`。它是 10–90 的整数百分比，省略时使用 75；其他图表类型拒绝此属性。圆环查询始终返回实际 `holeSize`，默认面板提供该数值控件。MoonBit 的 `InsertChart/ChartData/FillChart` 构造器末尾使用 `Int?` 传入同一设置，其他类型显式传 `None`。

每个系列按绝对值独立归一化，由内向外形成同心环，沿用饼图的类别颜色、标题和图例。径向可用宽度按系列数均分；没有任何数值点的空缓存不推进绘制环序号，零点仍保留所属环的位置。外弧与反向内弧构成闭合路径，Canvas、PNG 和 PDF 保留真实空心。原生 `doughnutChart` 保存每个系列的类别颜色及 `holeSize`，不生成数轴。空心比例、类型与数据修改沿一项精确历史；独立复制、缓存/工作簿核对和重开保留设置。范围沿用上述系列、类别、字号及资源预算；角度、分离扇区、数据标签、其他配色和更广原生配置继续保护。算法归 [`chart-pie.mbt`](../../../modules/layout/src/chart-pie.mbt)，依据 [ONLYOFFICE 默认空心比例](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L6183-L6192)、[系列半径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L14106-L14215)、[相反方向的内外弧](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L14270-L14316)及 [OpenXML 空心比例范围](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.charts.holesize?view=openxml-3.0.1)，未复制上游执行代码。

堆积折线图使用 `stackedLine`，百分比堆积使用 `percentStackedLine`。类别中心、1.5 点直线、5 点圆形标记和图例沿用普通折线；每个类别按系列顺序作代数累加，空白点贡献零并显示当前累计点。百分比按全部系列绝对值总和归一化，有限极大值先缩放再求和，零总量显示零点。数轴包含各步累计值，分别保存原生 `lineChart/grouping=stacked/percentStacked`，百分比轴使用 `0%`。缓存和嵌入工作簿保留原始值与空白。DOCX 正文/普通格、XLSX 实时来源及 PPTX 共用读写、默认类型控件和精确事务；普通折线仍按空白断线，柱形堆积仍分别累计正负值。未知分组、曲线、其他标记和轴配置继续保护。算法归 [`chart-data.mbt`](../../../modules/layout/src/chart-data.mbt)和[`chart-layout.mbt`](../../../modules/layout/src/chart-layout.mbt)，依据 [ONLYOFFICE 折线累计与空值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L9303-L9351)及[累计数轴](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L1520-L1609)，未复制上游执行代码。

面积图使用 `kind: "area"`。类别轴按 `crossBetween=midCat` 把首末类别点放在绘图区边缘，单类别居中。每个连续非空数据段沿零轴闭合，空值断开，孤立点和全零段不产生可见面积；正负部分保留原符号。系列按原顺序用固定不透明颜色绘制，后系列可覆盖前系列，不累计数据；图例沿相同系列顺序。当前无外轮廓和数据点标记，配置为 `standard`、`varyColors=0`、`dispBlanksAs=gap`。未知分组、透明度、标记及其他轴配置保持诊断和源保护。数据修改、切换类型、独立对象复制及精确历史复用原路径；Canvas、PNG 和 PDF 使用同一封闭图元。位置和空值规则依据 [ONLYOFFICE 面积图默认轴](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L6582-L6591)、[零轴闭合与断段](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L9735-L9840)及[系列绘制顺序与空值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L10796-L10884)。

堆积面积图使用 `stackedArea`，百分比堆积使用 `percentStackedArea`。两者按系列顺序累计带符号值，每条色带连接前后累计边界；空值按零参与累计，原生缓存保留空值。百分比分母为该类别各系列绝对值之和，先归一化再求和以避免有限大值溢出；零总量绘制零带。轴包含全部中间累计值，原生 `areaChart/grouping` 分别保存 `stacked/percentStacked`，百分比轴使用 `0%`。DOCX、XLSX、PPTX 共用以上类型、原生读写和默认控件；工作簿保留原值，类型切换不改数据源，XLSX 继续按当前公式值重算。累计与空值依据 [ONLYOFFICE 面积累计](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L10840-L10888)，色带依据[前后系列边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L9735-L9810)。

散点图使用 `kind: "scatter"`，TSV 首列为共享的有限数值 X 或空值，后续各列为 Y 系列。首格为 X 轴标题。X/Y 都存在时绘制直径 5 点的圆形标记；零值保留，缺失任一坐标时不画点。数值 X 按实际比例定位，重复、无序 X 和正负坐标保持；点之间不连线。两条数值轴分别沿相同零包含和 1/2/5/10 刻度规则取界，空数据轴使用 0–1；边界包含未成对的有限源数值。原生结构为 `scatterChart`、`scatterStyle=marker`、`varyColors=0`、两条 `valAx` 和各系列 `xVal/yVal` 数值引用/缓存，所有 X 引用同一工作簿首列。切换类型、独立复制、精确历史及重开沿既有事务。每系列独立 X、连线/平滑、气泡、其他标记和自定义轴继续保护。行为依据 [ONLYOFFICE 默认散点类型](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L6251-L6267)、[双数值轴](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L13462-L13494)及[数值定位与空值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L14843-L14934)。实现归 [`chart-scatter.mbt`](../../../modules/layout/src/chart-scatter.mbt)。

读取仅接受当前原生结构，未知图表类型、样式、轴配置或公式保持诊断与源保护。数据编辑前核对缓存与嵌入工作簿，拒绝共享图表资源。修改数据保留对象/图表身份，并新建嵌入工作簿以支持精确撤销。旧工作簿及删除后未引用的图表资源继续保留，受现有包和历史预算限制。更广导入、样式与资源回收继续实施。实现归 [`chart-data.mbt`](../../../modules/layout/src/chart-data.mbt)、[`chart-read.mbt`](../../../modules/formats/src/internal/chart/read.mbt)、[`chart-edit.mbt`](../../../modules/formats/src/pptx/chart-edit.mbt)及 [`chart-layout.mbt`](../../../modules/layout/src/chart-layout.mbt)。

### 原生 SmartArt 读取

原生 `graphicFrame` 的 diagram 通过内部 `diagramData` 关系读取数据模型，再解析数据模型记录的 `diagramDrawing` 关系。关系可归幻灯片或数据模型；外部、缺失和歧义目标不作为预览。缓存分支复用现有形状、图片、连接线、主题颜色与文字布局。读取视图只映射 DrawingML 容器命名空间，原 XML 和部件字节保持不变。

当前支持根部无附加组变换的平面缓存、纯色背景及独立文字框。`txXfrm` 的偏移和尺寸按形状框归一化，文字布局与裁剪共用该矩形，再叠加正文边距。文字框优先于预设形状的内接文字区域，依据 [ONLYOFFICE getTextRect](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2148-L2173)。文字与形状须使用相同旋转和翻转；不同方向、嵌套缓存组、未知对象或效果继续给出诊断。缓存和原生框均只读，不能通过形状编辑改写原生 SmartArt。空缓存或未提供缓存扩展时使用下述原生层级布局。共享对象、部件和文本预算继续生效。实现归 [`diagram-preview.mbt`](../../../modules/formats/src/pptx/diagram-preview.mbt)。

C0 原件的结构、源保留、背景编辑和保存重开已检查。Office 行框按 ONLYOFFICE 采用 OS/2 度量及负自动行间隙；PDF 源字体的度量保持。原件及背景编辑后的 Canvas、SDK PDF 和独立保存重开均匹配固定参考，沿用原容差。保留与 LibreOffice 的基线分歧。上述缓存资格独立保留；原生 SmartArt 编辑仍受保护，证据见[测试说明](../testing.md#当前兼容证据入口)。

C13 第 7–14 页的九个缓存图现已读取，独立文字框不再阻断整图。正常 UI 的八页显示、PDF 导出、背景编辑、精确历史、非目标部件保留和新 Worker 重开通过。`hierarchy4` 缓存现按布局定义识别字号重算规则。核心沿 `presOf` 关系关联内容节点，在同组可容纳的 5–65 pt 整数字号中取共同值；`custT` 自定义文字保留原字号。占位文字受自己的容量限制，不压低已填写内容的字号。显式边距、原行距和段前间距保持，其余边距随字号缩放。字号适配复用共享段落的最小词宽和高度测量。依据 [ONLYOFFICE 同组与占位文字适配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L4912-L5003)和[缓存层级分组](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Data.js#L8424-L8426)，实现归 [`diagram-cache-font.mbt`](../../../modules/formats/src/pptx/diagram-cache-font.mbt)及 [`diagram-font.mbt`](../../../modules/formats/src/pptx/diagram-font.mbt)。

第 7、8、11、12 页的非自定义字号已分别匹配固定原生 PDF 的 30、24、18、17 pt；第 8 页的 `Topic` 不再拆成两行。该输入的整页视觉仍失败，渐变及阴影继续核对，原生参考另有缺少透明组的软遮罩。其他缓存布局的字号重算继续实施。此结果不扩大前述 C0 缓存图的独立视觉资格。

原生布局读取内部 `diagramLayout`、`diagramQuickStyle` 和 `diagramColors` 关系。当前接受默认方向的 `orgChart1`：顶层节点可有叶子子节点及一个助手。核心按各层占用范围排列，再居中缩放。尺寸、间距、字体范围及边距取自布局约束。主题填充和描边复用现有形状解析。字号在整张图内取共同可容纳的整数值。默认段落使用 0.9 倍自动行高及字号 0.42 倍的段后间距，与固定 ONLYOFFICE 行为核对。

数据图限制 128 个内容节点、4096 个点、4096 条连接及 32 层验证。布局另限制为上述两层范围，文字总量不超过 32767。重复身份、断开图、循环或多个父节点拒绝。方向、分支、算法、非均匀尺寸/边距及未实现的直接样式覆盖保持诊断。原生数据、关系和 XML 字节保留，生成视图只读。原件及缓存回归的背景编辑、精确历史、源保留、SDK/外部保存重开和 PDF 输出通过。更深层、多个助手、挂起/反向分支及原生编辑继续实施。实现归 [`diagram-native.mbt`](../../../modules/formats/src/pptx/diagram-native.mbt)、[`diagram-native-layout.mbt`](../../../modules/formats/src/pptx/diagram-native-layout.mbt) 和 [`diagram-font.mbt`](../../../modules/formats/src/pptx/diagram-font.mbt)。

### 简化 SmartArt 图示

`PresentationEditor.editObjects({ action: "insertDiagram", template, items, x, y, width, height })` 插入一个可编辑形状组。`template` 为 `process`、`hierarchy` 或 `cycle`，分别按水平流程、首项为根的单层层级、顺时针循环排列。普通模板接受 2–16 项，循环接受 3–16 项。每项最多 4096 UTF-16 单元，总计最多 32767；文字沿原形状校验与转义规则。坐标及外框使用页面磅，沿既有对象边界校验。

MoonBit 使用 `InsertDiagram(DiagramSettings)` 计算布局，生成矩形、文字和带箭头的原生 `p:cxnSp` 直线连接线。连接线位于节点下方，端点引用原生连接点。形状、组及引用复用既有创建和子树复制的身份分配，保存为普通 `p:grpSp`，不创建原生 diagram 部件或模板元数据。插入后沿普通组/成员事务修改文字、格式、几何、复制及取消组合；连接点跟随目标变换，副本引用映射到副本节点。

默认面板提供三种模板及逐行标签，位置和大小使用现有对象输入，并说明保存为可编辑形状和连接线。一次插入一项历史，成功后选中新组。文字放不进节点、缺字体、身份耗尽、资源或输出预算失败时整项拒绝，保留源和选择，不消耗身份。画布、重开及 PDF 共用已有图元。原生 SmartArt 导入及更广模板兼容归 P14。

实现归 [`diagram.mbt`](../../../modules/formats/src/pptx/diagram.mbt)、[`object-markup.mbt`](../../../modules/formats/src/pptx/object-markup.mbt)及 [`pptx-diagram.tsx`](../../../packages/pptx/src/react/pptx-diagram.tsx)。模板布局是 SDK 的简化规则；底层对象参考 [ONLYOFFICE SmartArt 形状生成](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/SmartArts/SmartArtTree.js#L1838-L1864)，未复制其执行代码。连接点规则归[连接线](#连接线)。

### 对象超链接

`PresentationEditor.editObjects({ action: "hyperlink", link })` 修改所选本地顶层对象或其文字的点击链接。对象模式支持单个形状、图片或组；文字模式支持一个可编辑文本框或普通表格中的单个主格。`link` 为 `{ kind: "external", target }`、`{ kind: "slide", target }`、`{ kind: "action", target }` 或 null；null 移除点击链接。动作 target 接受 `firstslide`、`lastslide`、`nextslide`、`previousslide`、`lastslideviewed`、`endshow`；后两类仅在放映中执行。`PptxHyperlink` 从 `wasm/pptx` 和 `web/pptx` 导出。每个 `PptxObject.hyperlink` 返回对象链接的 `{ value, reason }`；`PptxQuery.textHyperlink` 返回当前文字范围的 `{ value, mixed, reason }`。链接不一致时 value 为 null 且 mixed 为 true，默认面板仍允许统一设置或移除。多对象与继承对象继续保护。

文字选区按 UTF-16 字素边界拆分 run，可跨样式、软换行及段落，只修改选中范围。链接内的光标修改当前段落中相邻且关系及提示等元数据一致的完整链接；不同提示或关系保持独立。普通光标通过空 run 或空段落末尾属性设置后续输入链接。原生输入继承链接，移除时同步对应段落末尾属性，避免清空后再次出现。保留直接字体、大小、粗斜体、颜色和源下划线。点击链接派生单下划线，并按主题 `hlink` 及当前颜色映射显示，覆盖用于显示的直接和继承颜色；移除后恢复原定义。项目符号保留源文字色及列表显式色。仅悬停链接保持原外观。文字链接写入 `rPr/endParaRPr`，与对象的 `cNvPr` 链接独立；累计生成源限制为 2 Mi UTF-16 单元。

外部地址最多 2048 UTF-16 单元，只允许 HTTP、HTTPS 和 mailto，拒绝空目标、空白、控制字符及反斜杠。内部页目标使用当前文稿的稳定 slide 部件身份，不能使用页序号；允许显式跳转隐藏页。默认面板创建、修改及移除链接，单独的打开入口才导航。外链使用新窗口和 `noopener noreferrer`。`PresentationEditor.followHyperlink()` 及 Wasm/Worker 命令 `{ operation: "followPptxHyperlink", revision }` 从当前单个对象或一致的文字链接解析内部页/动作，再由核心定位；拒绝混合链接、外链、旧修订及活动候选。四种动作按当前编辑页序执行，包含隐藏页；上一页/下一页在边界停留并保留选择。重排、复制及删除页后按新位置解析，不保存过期页序号。导航不改源、revision 或历史；显示、打开文件和布局不自动请求外链或执行动作。`lastslideviewed/endshow` 可创建、修改和移除，编辑器中的 `followHyperlink()` 明确拒绝执行；默认面板提示在放映中使用。脚本、文件地址、相对网址、宏及其他未支持动作继续保护源。

核心写 `cNvPr/a:hlinkClick`：外链使用 External hyperlink 关系，内链使用 slide 关系及 `ppaction://hlinksldjump`。六种导航动作写 `ppaction://hlinkshowjump?jump=…` 和空 `r:id`，不创建关系；导入时按 action 解析，允许省略、空或原有关系身份。与目标相同的关系可复用；修改不覆盖其他对象共用的关系，也不清理旧关系。保留 tooltip、tgtFrame、history、highlightClick、endSnd、相邻悬停链接、注释、文字和几何；未知属性、声音等子内容或无法解析的关系保护修改。新增关系与对象 XML 共用一项有界历史，旧 revision、活动候选、锁和输出预算失败均不提交。相同链接及重复清除不新增历史。

页面重排保持内部目标，页面复制复用既有自身链接重映射，删页移除相应入链并保留对象。对象复制保留链接；带自身点击或悬停链接的组不能直接取消组合，避免丢失组动作。普通点击链接移除后可取消组合，成员自己的链接保留。静态 Canvas 保留对象外观及文字，PDF 链接归[下段](#pptx-pdf-链接)。放映点击归[放映链接](pptx-show.md#放映链接)；其他悬停及一般动作编辑兼容归 [P14](../roadmap.md#p14-兼容与性能已完成)。语义参考固定 [ONLYOFFICE 对象链接操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L3503-L3683)、[文字链接拆分与光标操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L7811-L8180)、[PPTX 链接下划线](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L10545-L10565)、[内部页动作解析](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L9259-L9290)及[编辑器显式导航](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/api.js#L7243-L7264)，实现归 [`object-hyperlink.mbt`](../../../modules/formats/src/pptx/object-hyperlink.mbt)和 [`text-hyperlink.mbt`](../../../modules/formats/src/pptx/text-hyperlink.mbt)。

表格文字链接在单个主格内使用相同的局部范围及光标规则，包含跨行列合并格和空格；范围先转换为格内位置，不改其他格及延续格。跨主格选择返回保护原因，统一设置和移除均不写入，默认面板同步禁用。新关系与单元格源仍合为一项历史；已有格式、几何及其他部件保持。放映使用表格原有逐格文字几何命中。规则依据 [ONLYOFFICE 表格链接操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L4601-L4630)。整表对象链接编辑仍受保护。

### PPTX 雷达图

`PptxChart.kind: "radar"` 使用现有插入、修改数据、占位符填入和查询入口。首列仍为类别，各数据列为系列；1–256 个类别、1–32 个系列及文字预算沿基础图表合同。原生配置为 `radarChart`、`radarStyle=marker`、`varyColors=0`、类别轴与数值轴、5 点圆形标记及 1.5 点系列线。原生缓存、引用、实际嵌入 XLSX、对象身份、独立复制和精确历史复用原图表路径。

类别从顶部开始顺时针等角排列。数值轴包含零并沿已有 1/2/5/10 刻度规则取界；半径为 `(值 − 下界) / (上界 − 下界)` 的投影。负值保持原数值；下界映射到中心，零按共同刻度定位。全零/全空使用 0–1。相邻非空点连接，首末点也视为相邻；空值在两侧断线，孤立点和零值保留标记。单类别只画标记，两类别只保留一条连接。核心先绘制系列线再绘制标记，类别、刻度和系列图例沿相同字体路径输出。径向比例先归一化再乘显示半径，避免有限大数产生无穷坐标。

当前框使用内接圆和有界标签区域；默认面板可改类型、标题及数据，Canvas、PNG 和静态 PDF 共用位置。只读取当前原生配置；填充雷达、其他标记、轴配置和组合继续诊断并保留源。实现归 [`chart-radar.mbt`](../../../modules/layout/src/chart-radar.mbt)及既有图表读写模块。算法参考 [ONLYOFFICE 类别角度、径向坐标、空值及闭合](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L14406-L14563)、[半径和绘制层次](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L14793-L14812)及[原生样式与数轴](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L6094-L6116)。未复制上游执行代码。

### PPTX PDF 链接

既有 PDF 导出保留对象和文字的 HTTP、HTTPS、mailto 外链，以及本次输出中可用的内部页目标。首页、末页、上一页、下一页动作按原生页序解析，再映射到实际输出页序；当前页、全部页及隐藏页选项保持原有规则。目标未输出时不生成注释。上次查看页、结束放映和媒体播放动作在静态 PDF 中不执行。

对象链接使用实际几何边界，零宽或零高直线补入线宽。文字和表格文字复用核心布局的可见字形区间，按文本框、单元格及纸张裁剪。旋转、翻转和组变换作用于矩形四角，再取轴对齐包围框；不声明多边形或遮挡命中。导出不改源、选区、历史和未保存状态，也不请求链接地址。未知或非法动作保护输出。

核心通过 `PositionedDocument.links` 复用[共享注释输出](docx-content.md#docx-pdf-文字链接)。标称行高短于字体度量时，文字链接仍覆盖字体升降部，再应用文字平面变换与裁剪。每次最多 65536 个矩形、8388608 个文字几何工作单元；光标及字形遍历均计入该预算，并继续执行现有打印和 PDF 字节预算。实现归 [`print-links.mbt`](../../../modules/formats/src/pptx/print-links.mbt)，几何及动作语义参考 [ONLYOFFICE PDF 文字链接](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L2886-L2968)，未复制上游执行代码。
