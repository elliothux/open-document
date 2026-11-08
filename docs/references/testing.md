# 测试说明

## 当前兼容证据入口

2026-11-07，C0 登记范围全部通过：核心 251/251；浏览器 PPTX 28/28、DOCX 10/10、PDF 28/28、XLSX 62/62，共 128 条。有界扫描的 48 份正向输入通过，3 份控制按预期拒绝。最终记录为私有 `cases/c0-current.json` 的 `finalCompatibilityQualification`，完整汇总为 `.temp/c0/final-qualification.json`。

C43 原始工作表 15 页的 30 组、重算后全部可见页的 32 组完整 Canvas/PDF 比较均为 0/0。源保存、新 Worker 的相同 PDF、104 个非随机值、26 个 RAND 范围及 19 张图表缓存检查通过。当前 `native-line-final` 构建修复零长线段、曲面端点和色带精度，并按 ONLYOFFICE 将相邻直线分别绘制。原件、参考和阈值保持。旧连续路径断言现检查全部数据线段与图例线，独立视觉断言保持。

最终 XLSX、登记核心和扫描绑定优化 WASM `333765a20c69f6bc0f0a9a2feefda289ccdb2fde830f61603b9a0bee7cb14cad`。PPTX、DOCX、PDF 复用下面共享 Renderer 构建的全部登记结果；后续产品修改仅影响原生工作表图表。最终 XLSX 逐文件记录为 `.temp/c0/xlsx-registered-geometry-current/summary.json`，图表定向复查为 `.temp/c0/native-line-final/browser-summary.json`。固定工具链为 MoonBit 0.1.20261023 / moonc 0.10.17+d971670cd、Node 24.19.0、Bun 1.4.2 和 Chromium 153.0.8010.12。

C13 的 130 组、C17 的 28 组严格比较保持 0/0。用户批准的原图 RGB 独立参考、ONLYOFFICE 降级外观与气泡同倍率对照继续生效。未跑全仓或性能套件；本结论限 C0 固定输入及登记操作。持续边界归[格式合同](formats.md)，交付归[C0](../implemented/c0-real-file-compatibility.md)。

### 历史批次与定向证据

以下按各批构建读取，保留当时的失败与未执行项。当前完整资格以上方最终记录为准。

2026-11-07 的共享描边构建通过 250 项登记核心检查。全部登记 PPTX 28/28、DOCX 10/10、PDF 28/28 浏览器流程通过，C13 的 130 组严格比较保持 0/0。构建与逐文件日志归私有 `.temp/c0/cross-format-primary-current/summary.json`。后续 XLSX 圆形图修改使用新构建，资格按下面的独立批次读取；未跑全仓和性能测试。

2026-11-06 的回归归私有 `registeredCompatibilityReplay`。正常发行构建通过 10 条登记的 DOCX 浏览器用例。复用同批已构建的 Wasm，原扫描器完成 51 份输入，48 份正向通过，3 个控制项按预期拒绝。扫描范围仍限打开和选定核心布局。

首次复扫使用本机 `0.1.20261105`，编译在 HarfBuzz 的 JSON 调用报错。临时替换该调用后，严格检查另报 46 处旧 `derive` 语法。临时修改已恢复。

改用固定的 MoonBit `0.1.20261023` 和 moonc `0.10.17+d971670cd` 后，正常发行构建与 237 项登记核心测试通过。用 Node `24.19.0` 和 Bun `1.4.2` 运行正式扫描，48 份正向通过，3 个控制项按预期拒绝。C08 和画布页面边界的两条 Chromium 流程通过。C17 在固定 MoonBit 构建上复查仍为 27/28，仅未旋转的第 11 页为 0/8。证据归私有 `registeredCompatibilityReplay.pinnedReplay`。

此前同一份固定构建的四格式登记浏览器用例共 126 条，107 条通过。DOCX 10/10、PDF 27/28、PPTX 22/28、XLSX 48/60。19 条失败都发生在严格视觉对照。该批 DOCX 复跑覆盖裁剪、双栏、字段、链接文本框、内嵌 EMF、页眉图片、VML 和三份加密原件。

该批其余 27 条登记 PDF 浏览器用例全部通过。合并 C17 的正式复查，当时 PDF 浏览器用例为 27/28，唯一失败为 C17。用例、参考和阈值沿用登记版本。

当前固定构建已通过全部 28 条登记 PDF 浏览器用例，Node 为 `24.19.0`。C17 的 14 页及旋转共 28 组均为 0/0；28 张 SDK 栅格与前批候选逐字节相同，27 张参考与旧工具相同。唯一修正的参考是未旋转第 11 页。源文件、保存字节、997 个源对象、精确历史和阈值保持。结果归私有 `nativePdfRegisteredSuiteCurrent` 与 `nativePdfShadingCacheDiagnosis.formalReplay`，不授予完整 C0 资格。

通用 PDF 颜色和覆盖用例现统一使用固定的 Poppler 缓存范围修复。它在参数超出缓存区间时调用原函数，不按样本选择工具。从根目录运行私有 `moon run test-lab/tools/c0-poppler-reference.mbtx`，校验源码包、补丁、工具、动态库及四个字面采样控制。工具缺失时按固定配方构建；当前复用前批已核验的二进制，另查验了解包与正式补丁重放，未重复原生编译。旧工具、旧参考及失败证据保留。首次未固定 Node 的运行已中止，不计入结果。

Poppler 26.11.0 的轴向渐变取色、缓存构建和参数范围函数与固定 26.05.0 版逐字节相同。两版进入缓存插值前均只检查缓存非空。此项只核对正式发布源码，C17 栅格结果仍以固定版实测为准。[Poppler 发布记录](https://poppler.freedesktop.org/releases/)

前批 C17 图表构建复跑中，冻结参考为 27/28，缓存边界候选为 28/28。两次运行的 28 张 SDK 栅格逐字节相同，27 张参考栅格相同；候选仅将未旋转第 11 页从 0/8 修正为 0/0。与更早的固定构建相比，22 张 SDK 栅格相同，6 张变化后仍通过候选整页对照。精确历史、保存字节和 997 个非目标源对象通过检查。当时尚未切换生成器。证据归私有 `nativePdfShadingCacheDiagnosis.currentReplay`。

2026-11-07，独立单页只保留 C17 第 11 页的源渐变、裁剪、坐标变换、取样函数和 ICC 配置。固定 Poppler 在同一行复现蓝通道回绕。加缓存边界检查后，中心像素由 `[169, 200, 0]` 恢复为 `[169, 205, 255]`，两张栅格仅该行九个像素不同。证据归私有 `nativePdfShadingCacheDiagnosis.originalShadingReproduction`。

同日复跑登记核心套件。C10 的两条旧断言仍从外缘起笔。现按冻结 ONLYOFFICE PDF 检查内缘起点和径向边，并保留原外缘点及坐标容差。登记核心从 236/238 恢复为 238/238。C10 的 Chromium 原件、改后和导出整页对照通过，保存、精确历史和重开通过。证据归私有 `nativeCircularChart.pinnedRingPathReplay`。

2026-11-07 用同一构建复查 C43。15 页导出的 PDF、30 组 SDK 与参考栅格的哈希和计数均与前批一致。原样保存通过，严格对照仍为 10/30。

同一构建分四批复跑 `test:c0-xlsx` 的全部 60 条 Chromium 用例，48 条通过。13 条工作簿流程和 25 条打印与图表对照全部通过。21 条图表用例中 10 条通过，11 条在严格视觉断言处失败。C43 整表用例仍为 10/30。

C41、C42、C44–C47 及两份手工重算工作簿通过工作簿流程。C43 原件重算后导出 16 页，精确历史和新 Worker 重开通过，重开前后 PDF 字节一致。

同一构建复跑 `test:c0-pptx` 的全部 28 条 Chromium 用例，22 条通过。6 条均在 C13 的严格视觉断言处失败，涉及整稿、圆角标注、SmartArt、两条表格流程和原色 WMF 组件。SmartArt 的 16 组对照有 4 组通过，双色 WMF 组件的 Canvas 和 PDF 均为 0/0。

两条表格用例关闭浏览器下载落盘后复跑。保存字节、非目标部件、精确历史及新 Worker 重开检查通过。两份对照报告逐字节等同于调整前，严格视觉仍失败。

C13 首轮完成 48 页原稿，随后在第 42 页重做时触及四分钟上限。通过 Playwright 直接传输 `Uint8Array` 后，整条流程在约 2.4 分钟内完成。编辑、精确历史和新 Worker 重开通过。原稿 78/96、改后 5/6，102 组结果和栅格哈希均与前批一致。严格用例仍在第 3 页 Canvas 的 99/218 处报错。

Word 2010 的 Agile 加密 DOCX 归私有 `nativeDocxAgile2010PasswordOpen`。LibreOffice 上游断言和固定 ONLYOFFICE 均读出 `abc`。浏览器与参考共用 Arial，整页 Canvas 和导出 PDF 均为 0/0。三份加密 DOCX 在同构建下的六组整页对照均为 0/0，错密重试、取消、只读、原样保存及新 Worker 重开通过。五项核心通过，包含两种 Agile 密文改一位后的完整性拒绝。[LibreOffice 上游断言](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/qa/extras/ooxmlexport/ooxmlencryption.cxx#L33-L40)

PDF.js 的 `vertical.pdf` 归私有 `nativePdfIdentityV`。原件首页显示 8 个嵌入 TrueType 字形，另两页保留页边细线。默认 Chromium 编辑器的三页 Canvas 对 Poppler 26.05.0 的 144 dpi 参考均为 0/0，原样保存和新 Worker 重开通过。核心另核对 `W2`、`DW2`、`TJ`、两字节字距和源编辑保护。首页缺少可信 Unicode 映射，仍报告提取不完整。[PDF.js 上游用例](https://github.com/mozilla/pdf.js/blob/24de17e81b3357b30ffd710ec080be00d65ac98d/test/test_manifest.json#L7816-L7820)

独立 PDF.js 6.4.299 对照的三页均为 998/1497，首批差异坐标都落在页边细线上。Poppler 参考沿用原件和绘制规则，通过本地数据目录加载 Adobe-Japan1 后生成。

两份加密 DOCX 的整页检查归私有 `nativeDocxPasswordVisual`。C49 使用 Times New Roman，Word 2013 原件使用 Carlito，与各自 ONLYOFFICE 10.0.0.170 参考同字体。Poppler 26.05.0 以 144 dpi 栅格化。两份原件的 Canvas 与导出 PDF 各为一页，四组整页颜色对照均为 0/0。两条 Chromium 流程还核对错密重试、取消、原样保存及新 Worker 重开的 Canvas 和 PDF 字节。

Word 2013 的 Agile 加密 DOCX 归私有 `nativeDocxAgilePasswordOpen`。LibreOffice 上游断言和固定 ONLYOFFICE 转换均读出 `ABC`。默认 Chromium 编辑器通过错密重试、取消保留旧文档、只读、原样保存和新 Worker 解锁。密文改一位后，核心在读取 ZIP 前拒绝。四项核心和四条 Chromium 定向检查通过。此原件单列于 51 份固定扫描之外。[LibreOffice 上游断言](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/qa/extras/ooxmlexport/ooxmlencryption.cxx#L43-L51)

PDF AES-128 解锁归私有 `nativePdfAesV2PasswordOpen`。qpdf 12.4.1 用 C50 原件生成 V4/R4 AESV2 对照，核对字符串、流和压缩对象。Poppler 26.05.0 的 AESV2 与 RC4 栅格逐字节相同。两份 SDK Canvas 也逐字节相同，各自整页笔画覆盖为 0/0。错密重试、取消、只读、原样保存和新 Worker 重开通过。AESV2 禁止打印、RC4 禁止复制及 AESV2 版本不匹配的对照均拒绝，并保留当前文档。13 项定向核心和五条 Chromium 流程通过。

PDF 文件尾偏移恢复归私有 `nativePdfClassicXrefRecovery`。只改 C22 原件末尾四个偏移数字，原交叉引用表和对象保持。Poppler 26.05.0 的原件与损坏件栅格逐字节相同。Chromium 打开损坏件，整页笔画覆盖为 0/0，源保存和新 Worker 重开通过。13 项定向核心与五条 Chromium 流程通过，包含三种错误偏移、旧修订链接拒绝及 C51 的原文档保留。

C49 的 Standard 加密 DOCX 归私有 `nativeDocxPasswordOpen`。LibreOffice 上游测试与固定 ONLYOFFICE 转换均读出 `ABC`。默认 Chromium 编辑器显示该段，布局诊断为空。错密重试、取消保留旧文档、原生输入只读、原样保存和新 Worker 解锁通过。两项核心测试覆盖密码验证、FAT 循环、保留预算与写入保护。三条 Chromium 流程通过，包含共享 PDF 密码对话框和失败替换回归。

同构建扫描 51 份固定原件。48 份正向原件通过已有打开及有界检查，C48 旧版 PPT、未提供密码的 C50 和 C51 损坏 PDF 按预期拒绝。

语料登记同步了 12 个已更新的项目自有测试文件的哈希，九项完整性检查通过。五条图元文件白盒测试已移入私有测试登记，源码逐字节相同。公开 `bun run check` 和图元文件与 DOCX OLE 的八项定向检查通过。当前构建的画布页面边界用例通过 24 组精确像素对照。

C14 渐变原件的当前证据归私有 `nativeC14GradientVerification`。原件和改后 Canvas 各从 1/0 降为 0/0。原件和改后 SDK PDF、LibreOffice 重开也为 0/0。原件 PDF 检查已加入既有 Chromium 用例。两张 ONLYOFFICE 参考栅格与前批逐字节相同。文字输入、源保留、精确历史和新 Worker 重开通过。共用测试助手的 C11 回归四组对照也为 0/0。

C44 条件格式的完整打印预览归私有 `nativeC44PrintPreview`。原件和跨表编辑后各有两页，四张 Canvas 对同一独立 ONLYOFFICE 参考均为 0/0。原有十组对照的实际栅格和参考哈希均相同。精确历史、十个非目标部件、SDK 重开和独立保存重开通过。

C31、C32 的 AcroForm 后备字段归私有 `nativePdfXfaFallbackFields`。C32 的只读列表从父字段继承空字符串，查询现返回空选区。两份原件分别读取七个、五个后备字段，保留已选值并报告 XFA 保护。核心验证拒绝修改后原样保存。四条 Chromium 流程通过，覆盖两份原件的字形、旋转重开，以及 C34 和跨页共享字段的编辑回归。

C33 的无外观线批注归私有 `nativePdfLineAnnotationEdit`。默认编辑器读取原 4 pt 宽度，可修改颜色、宽度和批注文字。qpdf 核对原对象编号、端点及 14 个非目标源对象。Poppler 重开改后文件，在原矩形之外核对红色笔画像素。原样保存、逐字节撤销重做和新 Worker 重开通过。12 项定向核心及十条 Chromium 流程通过，覆盖原件与旋转页的既有 Poppler 对照，以及表单、绘图和批注关系回归。

C23 原生图片编辑归私有 `nativePdfCmykImageMove`。默认编辑器把图片横坐标移到 80 pt。独立参考用 qpdf 只改原页的横向平移。Poppler 26.05.0 以 144 dpi 栅格化，改后 Canvas 和保存 PDF 的整页颜色对照均为 0/0。qpdf 核对 34 个源对象，包含原 CMYK JPEG 和内容流。改后调用仍在原可选内容层和绘制状态内。精确撤销重做及新 Worker 重开通过，重开的属性框显示 `80`。五条定向 Chromium 流程通过。

C18 正文编辑归私有 `nativePdfKitSourceTextEdit`。默认编辑器拒绝再次嵌入受限的源 Palatino。显式选择 Arial 后可替换正文，宿主为该名称供应 Noto Sans。qpdf 核对原字体、原内容流等 11 个源对象，Poppler 提取出替换文字。改后 Canvas 与 Poppler 重开保存 PDF 的整页笔画覆盖为 0/0。精确撤销重做、新 Worker 重开及五条定向 Chromium 流程通过。

C47 的 Strict XLSX 只读查看归私有 `nativeC47StrictXlsxReadOnly`。原件打开三张表，显示主题蓝字、黄色填充及公式结果 13。LibreOffice 26.8.1.1 另存核对公式和结果。核心保护单元格编辑。默认 Chromium 界面通过切表、黄色填充、可访问只读状态和新 Worker 原样重开。混合关系命名空间的派生文件会保留原编辑器并报告打开失败。一项定向核心和三条 Chromium 流程通过。有界扫描的 47 份正向原件和四份控制均符合预期。

C47 的打印证据归私有 `nativeC47StrictXlsxPrint`。ONLYOFFICE 10.0.0 将纸型代码 `0` 和省略纸型的工作表均按 A4 导出。独立参考只在样式和次要主题字体中将 Calibri 换成固定 Noto Sans，另 11 个包部件逐字节相同。浏览器加载原件，核对网格长文本、两张有内容的表、原样保存及新 Worker 的相同 PDF。qpdf 结构检查通过，144 dpi 的两页 Canvas 和两页 PDF 均为 0/0。另有核心检查核对空格、有值邻格及显式打印区域。

C47 的横向滚动归私有 `nativeC47StrictXlsxScrollOverflow`。滚出 A4 后，先确认 A4 从视口单元格列表移除，再检查蓝色文字尾部仍在 Canvas 中。修复前该像素检查失败。新构建的四条 Chromium 流程覆盖原样保存、重开、两页打印、冻结窗格和绘图滚动。打印 PDF 与上批逐字节相同，四组整页对照均为 0/0。九项核心检查通过。

PDF 2.0 只读查看归私有 `nativePdf2ReadOnly`。复用 ONLYOFFICE 10.0.0 的两页原件。qpdf 验证结构和版本，Poppler 26.05.0 的两页 144 dpi 整页笔画覆盖均为 0/0。第二页按源 `TJ` 位移恢复词间空格，提取与 Poppler 一致，前后栅格逐字节相同。原样保存、新 Worker 重开及旋转和提取成新 PDF 的保护通过。目录声明 2.0 的独立控制可打开；新版本和缺失文件头拒绝并保留当前会话。十二项定向核心和十一条 Chromium 流程通过。

C50 加密 PDF 归私有 `nativePdfPasswordOpen`。默认打开流程以错密重试，取消保留原编辑器。四个空格解锁后可只读查看，保存和新 Worker 重开均保留原加密字节。qpdf 核对加密方式及权限。Poppler 26.05.0 核对原件的提取文字和 144 dpi 整页笔画覆盖，结果为 0/0。qpdf 解压确认挖空组内容为空。独立禁止复制的对照文件会拒绝打开并保留当前会话。十二项定向核心和七条 Chromium 流程通过。

C43 气泡图的打印裁剪归私有 `nativeC43BubblePrintOverflow`。LibreOffice 固定参考在图框下边缘之外绘制蓝色气泡。打印沿用页面或打印带裁剪，屏幕沿图框裁剪。SDK 的独立打印对照从 47603/48128 降至 47004/47876，从 45224/45444 降至 44612/45186。两张对照仍有差异，原样保存和新 Worker 的 PDF 字节一致检查通过。

三个气泡图核心检查通过。无图例视图为 0/0，有图例视图为 5/4。原件 15 页的 30 张 SDK 栅格及全部参考栅格与前批逐字节相同，正式通过 10/30。

C43 的打印底纹取样归私有 `nativeC43FractionalBitmapCells`。独立 PDF 以 144 dpi 绘制双色索引底纹，6 pt 周期对应 12 个设备像素。首行取样沿用原生平铺的末行。新对照与 Poppler 逐像素相同，整数格、变换裁剪和缩小回归均通过。

15 页原件保留源字节，沿原参考和容差执行 30 组比较，通过 10 组。第 7 页圆环图区的 Canvas 从 1773/347 降为 0/1，PDF 为 0/0。第 4 页原参考省略部分源底纹，修正后该页 SDK 一侧的差异增加。整表通过临时测试从内存 PDF 取样，沿用整页断言；本次跳过 qpdf 结构检查。两次同构建对照的导出 PDF 字节一致。

C43 的复合饼图连接线归私有 `nativeC43OfPieConnectors`。LibreOffice 的等价末尾 12 点拆分对照保留原值和样式。其两条连接线均从主饼外缘向次图延伸。C43 原件和合成条形检查先失败，修复后四项核心检查通过，覆盖条形和饼形次图的切点。

Chromium 中，两张隔离图的原样保存和新 Worker 重开通过，完整视觉仍有差异。原工作簿保留源字节和 18 个绘图对象，打印导出 15 页。全部 30 张参考栅格与前批相同，26 张 SDK 栅格相同。变化集中在第 7、10 页，两页的 Canvas 和 PDF 仍有差异。正式结果为 10/30。

C43 的主饼合并扇区样式探针归私有 `nativeC43OfPieConnectors.aggregateStyleProbe`。仅在上述原生对照加入编号 16 的着色点，PDF 页面操作流逐字节相同。LibreOffice 的读取器只为编号 0–15 的源数据点创建样式属性。该对照无法验证合并扇区的显式样式。[LibreOffice 数据点读取](https://github.com/LibreOffice/core/blob/bf6ef2662401c7d6dce671ab4deb26ee0af3a7c1/chart2/source/model/main/DataSeries.cxx#L285-L328)

C43 的复合饼图默认值归私有 `nativeC43OfPieDefaults`。LibreOffice 另存位置拆分对照时省略间距和次图尺寸。原生间距归零、尺寸改为 100 和省略两项的三个对照，均与原生位置拆分对照的 PDF 操作流逐字节相同，因此该引擎无法验证这两项的几何响应。

复合饼图的位置拆分边界归私有 `nativeC43PositionalOfPie.boundaries`。LibreOffice 对照只改拆分位置。`0` 仅绘主饼，`15` 和 `16` 均保留主饼合并扇区、15 段条形和两条连接线。SDK 接受 Office 规定的整数范围 `0` 至 `32000`。超过可拆点数时保留首点给主组，沿用微软二进制格式记载的行为。LibreOffice 对 `32000` 只绘次图。五项定向检查覆盖零值、缺失值、非法位置和原样保存。[Office 的 OOXML 范围](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oe376/99656dce-2698-452b-ad7d-63ba27d19f7b) [微软二进制格式的超限规则](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xls/810df3fd-6503-4545-9bf5-09ab2061818a)

自动拆分归私有 `nativeC43PositionalOfPie.automatic`。条形和饼形两套 LibreOffice 对照只改拆分规则。两套的 `auto`、空节点和省略节点均与显式末尾两点的 PDF 内容流逐字节相同。Chromium 的自动和显式两点版均绘出两段条形，Canvas、PDF 及 PDF 栅格逐字节相同。四条浏览器流程通过原样保存和新 Worker 重开。46 项定向核心检查通过。C43 原件复跑保留源字节、18 个绘图对象和 15 页 PDF，30 组比较与前批一致。

原件的 15 页 PDF 字节及 30 组整页对照与前批一致。两张隔离复合饼图均通过原样保存和新 Worker 重开，正式视觉仍失败。冻结参考将两张图都绘成普通饼图。

C43 原件派生对照先因缺少 `gapWidth` 失败，修复后四项核心检查通过。Chromium 的显式默认值、省略节点和空节点三份对照各保留源字节及新 Worker 重开。三份 Canvas、PDF 和 PDF 栅格逐字节相同，对冻结参考的严格比较仍失败。

C43 条形复合饼图的 LibreOffice 另存件归私有 `nativeC43OfPieLibreOfficeRoundtrip`。在首张工作表中，Chromium Canvas 和 SDK 导出的单页 A4 PDF 均绘出原生对照中的 12 段颜色。原样保存和新 Worker 的 PDF 字节一致通过。原生整页诊断仍有 164104/164105 个差异。第二张工作表仍报告未绘制对象，原件两条复合饼图严格对照仍失败。

空值点的图例填充归同条记录的 `emptyPointLegendFill`。LibreOffice 对照只把首点显式颜色从 `9999FF` 改为 `D24726`，原生 PDF 仅变化一条图例填充指令。正常 Chromium 的 Canvas 绘图指令与 SDK PDF 均保留原件的 `9999FF`。另存件保留源字节，新 Worker 导出相同 PDF。46 项定向核心和两条 Chromium 流程通过。另存件的整页诊断为 164115/164120，图例文字仍有差异。C43 原件的 15 页 PDF 和 30 组比较与前批一致，整页严格对照仍为 10/30。

另存件的第二张工作表现可预览条形和饼形复合饼图，其他 16 张图表按部件报告。Chromium 核对了两张图的源颜色、编辑器诊断、打印拒绝和原样保存。52 项定向核心检查通过，覆盖重复绘图编号的拒绝。C43 原件的主图表页仍通过严格对照，18 张工作表图表可读，15 页 PDF 与新 Worker 重开后的输出逐字节相同。两张隔离复合饼图的严格对照仍失败，SDK 与参考的输出均与前批逐字节相同。原件整表视觉沿前批结果。

同一 LibreOffice 另存件新增显示第二张表的四系列圆环图。104 条重复标签的绘制指令与仅保留系列设置的控制逐项相同。真实逐点覆盖继续拒绝。固定 ONLYOFFICE 的工作区输出验证两种底纹；LibreOffice 的 PDF 保留标签，标签字段顺序与 SDK 有差异。正常 Chromium 核对底纹、扇区颜色、原样保存和新 Worker 的相同画面。47 项定向核心通过，第二张表还有 15 张图表未显示，整表打印仍受保护。C43 原件的 15 张打印预览和整份 PDF 与前批逐字节相同。证据归私有 `nativeC43OfPieLibreOfficeRoundtrip.doughnutPreview`。

另存件第二张表的普通饼图现显示外置标签和源引导线。LibreOffice 对照只关闭源开关，原生 PDF 少 15 条黑色细线，其余绘制指令一致。SDK 使用文件声明的红色细线，在现有标签位置画出 7 条。47 项核心检查通过，包含关闭开关后省略引导线。Chromium 通过原样保存和新 Worker 重开。第二张表还有 14 张图表未显示，整表打印仍受保护。C43 原件的 15 张打印预览和整份 PDF 逐字节一致。证据归私有 `nativeC43OfPieLibreOfficeRoundtrip.pieLeaders`。

同一普通饼图的 25 个标签均保留，文字区域重叠从 27 对降到零。Chromium 原样保存和新 Worker 重开均画出 11 条源红色引导线。48 项定向核心通过。C43 原件的 15 张打印预览和整份 PDF 与前批逐字节相同。两张气泡图的四组同倍率整页打印对照仍为 0/0。证据归私有 `nativeC43OfPieLibreOfficeRoundtrip.pieBestFit`。

LibreOffice 另存件的两张雷达图现可在默认编辑器预览。独立 PDF 只切换分类轴方向，蓝色系列的第二点随之从左移到右。ONLYOFFICE 对照保留红、蓝标记填充，并分别使用主题的蓝、红描边及 0.75 pt 线宽。核心复用既有主题解析，保留显式图框和圆角连接，可见标签和反向数值轴继续保护。51 项定向核心和四条 Chromium 流程通过。C43 原件两张隔离雷达图的 Canvas/PDF 四组均为 0/0，15 张打印预览和整份 PDF 与前批逐字节相同。另存件还有 12 张图表未显示，整表打印仍受保护。证据归私有 `nativeC43OfPieLibreOfficeRoundtrip.radarPreview`。

同一另存件的百分比面积图现显示全部 26 个系列。独立 ONLYOFFICE 控制分别关闭分类轴和数值轴刻度，核对主次刻度尺寸及位置。移除全部 `round` 节点后，原生 PDF 内容流逐字节相同。修正两条轴的绘制顺序后，整图 Canvas 和整页 PDF 从 4/0 降至 0/0。52 项定向核心和三条 Chromium 流程通过，包含原件面积图的两组 0/0、另存件预览、源保存及新 Worker 重开。C43 原件完整用例仍为 10/30，30 张实际栅格和全部参考栅格与前批逐字节相同。PDF 字节随轴绘制顺序变化。另存件还有 11 张图表未显示，整表打印仍受保护。证据归私有 `nativeC43OfPieLibreOfficeRoundtrip.areaPreview`。

原生图表的缺省系列名称归私有 `nativeC43OfPieLibreOfficeRoundtrip.defaultSeriesNames`。六种图表读取控制省略中间系列名称，并把源 `idx` 设为 77；显示名均为 `Series 78`，其他引用与缓存保持。气泡图继续更新无名称系列的数值及独立尺寸缓存，保留精确历史、源保存和重开。显式空引用仍拒绝。独立 ONLYOFFICE 对缺省名称与显式同名产生逐字节相同的栅格。该控制暴露长数据标签未换行；修正后完整 Canvas 从 3023/1990、整页 PDF 从 3007/2017 均降为 0/0。53 项核心检查和新增名称、原件折线两条 Chromium 流程通过。两张气泡图的四组同倍率整页对照及另存件预览在换行修正前通过。C43 原件整表仍为 10/30，PDF 和全部 30 张实际、参考栅格与前批逐字节相同。另存件两张气泡图仍被后续样式阻挡，未显示数仍为 11。

另存件的两张气泡图现可在默认编辑器预览，未显示图表减为 9 张。核心保留缺省名称、缺失尺寸、显式图框、主次刻度及关闭的逐点标签。无尺寸系列采用 ONLYOFFICE 绘制源码的 4 mm 半径；14 个圆的直径已核对，保存不补写名称或尺寸。固定 ONLYOFFICE 的独立导出画为散点标记，LibreOffice 导出省略无尺寸系列，两份结果均保留为诊断。55 项定向核心和三条 Chromium 流程通过，包含原样保存、新 Worker 相同预览和原件两张气泡图的四组同倍率整页 0/0。C43 原件的 15 张打印预览和整份 PDF 与前批逐字节相同；整表沿用 10/30 的严格失败。整图视觉资格与另存件整表打印仍未通过。证据归私有 `nativeC43OfPieLibreOfficeRoundtrip.bubblePreview`。

C43 的气泡图打印缩放归私有 `nativeC43BubblePrintFitRoutes`。同一份 chart14 工作簿在 ONLYOFFICE 和 SDK 中均按 62% 打印。仅将工作簿默认字体换成 Noto Sans，ONLYOFFICE 的变换保持，LibreOffice 的图框从 470.395 pt 缩至 455.921 pt。

C43 的整文件目标已确认为贴近固定 ONLYOFFICE 10.0，包括其降级外观；原始数据和属性保留。现有独立工作表参考及固定字体、100% 打印设置继续使用。无需等待其他引擎完整实现所有源特征。源保留、保存重开与整页零差异断言保持。两张隔离气泡图沿用已批准的同倍率独立打印对照。参考选择归私有 `nativeC43ReferenceContract`。

后续共享描边结果归私有 `nativeC43IntegerFilledStroke`。普通 `integer` Canvas 的填充直线多边形现复用已有 PDF 描边覆盖。未修改的透视柱图正式流程在旧构建复现 Canvas 0/5，修复后为 0/0，整页 PDF 保持 0/0。两张三维柱图的 Canvas/PDF 四组全部为 0/0，源保存与新 Worker 相同 PDF 通过。WASM 字节、独立参考和阈值保持，发行构建及私有类型检查通过。

同构建六项渲染回归通过。独立多边形在 `integer/pdf` 两种模式下共 32 组比较通过；表面预算包含父层，两个模式的四项边界检查通过。曲线、设备像素控制及七种不支持样式的原生回退通过。这些通用控制在修改前已通过，实际回归基线是透视柱图的 0/5。跨格式验收结果见本节开头，完整 XLSX 验收继续开放。

重算后的整本对照归私有 `nativeC43RecalculatedPagesCurrent`。原件在默认界面编辑并执行 Calculate now，已记录精确历史和新 Worker 缓存。独立引擎用相同数值的字面控制，避免再次生成随机数。主图页与 15 张工作表页按可见页顺序无损合并，32 组整页 Canvas/PDF 对照中 23 组为 0/0。源保存和新 Worker 的相同 PDF 通过，19 张图表缓存与已保存单元格数值全部一致。第 5、6、12、14、15 页仍有差异，完整 C43 未通过。

后续原生旋转控制只修改饼图起始角。0° 和 90° 省略单象限扇区底纹，45° 保留跨象限底纹。核心已按路径曲线数量修正打印分支，并移除主引擎没有的纵向标签避让。六项相关核心、发行构建和类型检查通过；新构建的六条圆形图流程通过。原始与重算后的完整页面仍在复跑，旧 23/32 结果继续保留。

最新结果归私有 `nativeC43BubblePrimaryDisplay`。气泡图复用原生散点布局，保留原始尺寸、编号、引用、缓存错误和属性。单点尺寸变化不改变显示，零尺寸系列仍显示标记。三维图之后的自动边距、数值 X 轴末端字宽和图例三角形均沿主引擎；工作区复用分数描边与字体适配。曲面 `between` 网格已从六个中心改为七条边界，并保留原生路径方向。相关回归在旧行为下先失败，修复后 73 项核心、正常发行构建及 `moon info` 通过。[格式合同](formats.md#工作表图表)

八条正式流程全部通过。两张气泡图的原件和新 Worker 完整 Canvas、62% 与 65% 整页 PDF 共八组均为 0/0。三张原始曲面图的 Canvas/PDF 六组均为 0/0。原始工作表的 15 页预览及 PDF 共 30 组均为 0/0，原样保存通过；全部 30 张冻结参考与此前通过的 20 张 SDK 栅格逐字节保持。透视柱图工作区及剩余登记流程尚未在该构建完成，完整 C43 和 C0 仍开放，未跑全仓。

气泡图的 14 份主引擎资产固定在私有 `cases/c0-bubble-reference/`。62% 原生 PDF 与栅格逐字节保留。65% 控制只把右边距改为 0.35 英寸，并固定原生打印倍率；SDK 的显式纸张得到同一倍率。完整 2304×650 工作区由原生引擎按同一 96 dpi 分两块绘制，再无损拼接，绕过单图 2000 像素限制；前 1000 列与原生单图逐字节相同。期望不使用 SDK 布局、像素或合成留白。独立生成脚本和旧二级输出保留。从根目录运行 `moon run test-lab/tools/c0-bubble-reference.mbtx` 校验固定资产及单页 PDF。

前批三维堆积面积批次归私有 `nativeC43Area3dPrimaryDisplay`。数轴用紧凑缓存位置累计，面几何仍按原点编号累计。主引擎为全部堆积面使用编号 0 的样式点，缺少该点时不画该系列的面。原件保留全部四个系列、缓存零和工作表错误；真实零值仍画出 25 个黄色面。原生首点空值、第二点空值和真实零控制支持这一规则。旧行为的核心断言先以 `25 != 0` 失败，修复后 70 项相关核心通过，正常发行构建及 `moon info` 通过。[格式合同与上游依据](formats.md#工作表图表)

原始三维面积图的正式用例和独立真实零值流程均通过，完整 Canvas/PDF 四组均为 0/0。原样保存及新 Worker 的相同 PDF 检查通过。整表沿用原浏览器用例、参考和严格断言，从 18/30 提高到 20/30。仅第 8 页两张 SDK 栅格变化，并新增两组 0/0；其他 28 张 SDK 栅格及全部 30 张冻结参考逐字节保持。第 10–14 页仍失败，完整 C43 未通过，未跑全仓。

前批深度轴标题归私有 `nativeC43AutomaticDepthTitlePrimaryDisplay`。固定主引擎未对 `SerAx` 计算自动标题位置，原生图框裁剪使其不可见。柱图和曲面图现沿此显示，保留标题源属性及布局留量。显式边缘位置和贴边限制保持。两个旧行为回归先失败，修复后 70 项相关核心全部通过，正常发行构建及 `moon info` 通过。[ONLYOFFICE 标题定位分支](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L655-L708)

未修改的三张曲面图及堆积条图正式流程通过，Canvas/PDF 八组均为 0/0。透视柱图整页 PDF 为 0/0，Canvas 仍有 0/5 差异；五张图均通过源保存及新 Worker 的相同 PDF 检查。完整工作表沿用冻结参考和严格断言，从 16/30 提高到 18/30。第 1 页两种输出新增 0/0，第 14 页差异减少；其余 26 张 SDK 栅格及全部 30 张参考逐字节保持。六条流程共四条通过，两条保持严格失败。完整 C43 未通过，未跑全仓。

前批圆形图归私有 `nativeC43CircularPrintHatches`。现有打印上下文传到圆形图扇区：打印省略图案填充并保留轮廓，矩形图框、绘图区和图例底纹保持；工作区及源属性保持。定向回归先在旧实现得到 5 项中 1 项失败，修复后 34 项相关核心全部通过。正常发行构建及 `moon info` 通过。

两条正式圆形图流程已通过，完整工作区 Canvas 和整页 PDF 四组均为 0/0。源保存及新 Worker 的 PDF 字节一致。完整工作表沿用原用例、固定参考和严格断言，结果由 14/30 提高到 16/30。第 4 页两种输出新增通过；其余 28 张 SDK 栅格和全部 30 张参考逐字节相同。完整工作表仍失败，未跑全仓。

圆形组件的工作区现与同倍率原生直接绘图比较。八份资产固定在私有 `cases/c0-circular-reference/`，原输入、原生 PDF 和打印栅格字节保持。独立生成脚本另保留；从根目录运行 `moon run test-lab/tools/c0-circular-reference.mbtx` 校验资产及单页 PDF。该工具只校验登记资产。

前批散点结果归私有 `nativeC43ScatterPrimaryDisplay`。单系列逐点配色组沿主引擎省略绘图区标记，源属性和图例规则保留。稀疏缓存的标记画笔按原生路径位置读取，缺项沿用此前填充和描边。两个定向回归在旧行为下先失败，修改后 70 项相关核心检查通过；真实零、空位、坐标、范围、隐藏及主题检查保持。正常发行构建和 `moon info` 通过。

未修改的原始散点浏览器用例已通过，完整 Canvas 和整页 PDF 均为 0/0。原始输入、保存及新 Worker 的 PDF 一致。完整工作表继续使用冻结参考和原断言，严格结果由 12/30 提高到 14/30。第 5 页两种输出新增 0/0，其余 28 张 SDK 栅格及全部 30 张参考逐字节相同。完整工作表仍失败，未跑全仓。

当前复合饼图显示沿 ONLYOFFICE 转为普通饼图。拆分专用几何和内部状态已移除，源规则、非法索引和尺寸校验保持。等价普通饼图的核心控制先在旧实现复现失败，修改后 69 项相关检查通过。正常发行构建及 `moon info` 通过。两条登记组件用例完整通过，Canvas 和整页 PDF 共四组均为 0/0；原始组件输入、保存及新 Worker 的 PDF 保持。证据归私有 `nativeC43OnlyOfficeDisplay`。

组件旧参考的自动标题实际使用 Avenir。独立对照现将全部显式字体统一到整表相同的 Arimo 配置，图表 XML、缓存、几何和纸张设置保持。原生直接图形生成同倍率的完整工作区图，原生 PDF 则生成整页打印图。两张 SDK PDF 与修正参考前的失败批次逐字节相同。十份原始输入、字体别名输入及图像/PDF 资产已移到私有 `cases/c0-ofpie-reference/`，从根目录运行 `moon run test-lab/tools/c0-ofpie-reference.mbtx` 校验。该工具只校验登记资产；独立生成脚本及旧参考另保留。

同构建复跑完整工作表，严格结果由 10/30 提高到 12/30，第 7 页两种输出新增 0/0。原件保存、18 个绘图对象和 15 页导出检查通过。第 7、8、10、11、12 页的差异计数减少，其余 20 张 SDK 栅格逐字节相同；全部 30 张参考栅格及参考身份保持。完整工作表用例仍失败，不能据两张组件通过授予完整 C43 资格。

手工面积图现复用已有的源错误与缓存零区分。两种面积图的数据目录均以空值报告已知源错误。独立控制只把 E2 换成真实数值零，两份图表部件保持，零值仍读取为零。六项面积图检查包含在 55 项相关核心检查中，全部通过。Chromium 的默认编辑器、原样保存及新 Worker 数据目录和 PDF 一致检查通过。15 张打印预览和完整 SDK PDF 与前批逐字节相同；整表沿用 10/30，未重跑或增加视觉资格。证据归私有 `nativeC43ManualAreaErrorGap`。

C43 的自动标题现采用与显式文字相同的字体原生行距及字距设置。等价显式标题控制先复现 20.1 与 20.6982421875 pt 的行高差异，修复后两种原件的行高和宽度均一致。55 项相关核心及最后一项定向复验通过。三个非空标题字形的轮廓与独立原生 PDF 相同；基线的 SVG 坐标误差从约 0.5803 缩至 0.0028 pt。中性字形层在既有像素容差下，修复前后都为 0/0，因此不增加像素资格。直接裁图会混入穿过标题的原生扇区，失败诊断另存。

自动标题批次曾复跑两张隔离复合图及完整工作表。源保存和新 Worker 检查通过，三条严格视觉用例当时仍失败。整表 30 组对照为 10/30；仅第 7、8 页的四张 SDK 栅格变化，其余 26 张及全部参考保持。当时普通饼图路线只作诊断，完整拆分绘制保持；后续按选定主引擎显示的结果见上方。历史证据归私有 `nativeC43AutomaticTitleMetrics`。

只将图表绝对锚点的宽高减半后，ONLYOFFICE 和 SDK 都按 100% 打印。LibreOffice 图框为 363.005 × 224.646 pt，SDK 为 363.770 × 225.411 pt。半尺寸整页仍有 3829/4077 个差异，图框和绘图区尺寸也有差异。诊断件的原样保存和新 Worker 的 PDF 字节一致检查通过。正式参考与共享缩放规则沿用原验收。

C43 的气泡图打印锚点适配归私有 `nativeC43BubblePrintEmbedding`。LibreOffice 三份对照仅改变图框描边。白底和绘图区随描边加宽而内缩，图框外边界的最大差异小于 0.02 pt。修复后半尺寸对照的 SDK 图框四条边与原生各差不足 0.008 pt，整页 PDF 从 3829/4077 降至 0/1。三个核心检查通过。原样保存及新 Worker 的 PDF 字节一致通过。[LibreOffice 图表边界](https://github.com/LibreOffice/core/blob/bf6ef2662401c7d6dce671ab4deb26ee0af3a7c1/svx/source/svdraw/charthelper.cxx#L89-L95)

半尺寸对照的余差位于左轴短刻度与气泡描边之间。临时 PDF 只将该刻度的纵坐标移至原生位置，相差 0.032 pt，整页即为 0/0。26 根纵轴刻度的坐标误差有正有负。诊断归私有 `nativeC43BubblePrintEmbedding.halfAnchorTickProbe`，产品输出仍为 0/1。

两张全尺寸气泡图的 PDF 差异增加，分别为 51147/52015、48640/49268。无图例和有图例的屏幕对照仍为 0/0、5/4。C43 整表导出 15 页，保留 18 个绘图对象和原文件字节。第 10 至 14 页的 Canvas/PDF 栅格发生变化，其余 20 张与前批相同。第 10、11、13、14 页的差异减少，第 12 页的差异增加。全部参考栅格逐字节相同，正式通过仍为 10/30。

全尺寸气泡图的同倍率对照归私有 `nativeC43BubblePrintMatchedScale`。诊断只将 SDK PDF 的打印倍率从 62% 改到 65%，两张整页均为 0/0。只对齐原点时，两张仍有差异。LibreOffice 转存记录的默认列宽分别为 0.5492、0.6728 英寸，原始锚点各占 19、16 列。原字体与 Noto Sans 的打印倍率分别为 65%、63%。半尺寸 PDF 的一个余差在原点对齐后仍存在。[LibreOffice 分页缩放](https://github.com/LibreOffice/core/blob/bf6ef2662401c7d6dce671ab4deb26ee0af3a7c1/sc/source/ui/view/printfun.cxx#L2607-L2678)

两个独立 XLSX 候选只将图表页右边距从 0.7 调到 1.05 英寸，使 LibreOffice 按 62% 打印。其余包部件逐字节相同。Chromium 读取未改的两份 XLSX，原样保存和新 Worker 重开通过。两张 SDK PDF 与前批逐字节相同，对候选均为 0/0。ODS 另存改变了有图例图的绘图区宽度，该路线单列。冻结的 65% 参考和正式结果保持。登记的 227 项 C0 核心检查全部通过。

旧 LibreOffice 圆形气泡方案的两条打印用例分别验收默认 62% 和纸张右边距为 0.45 英寸时的 65%；当前主引擎方案见上方。62% 使用新增的独立 LibreOffice 对照，65% 沿用冻结参考。两条用例核对 PDF 实际倍率、整页 0/0、原样保存和新 Worker 的 PDF 字节一致。私有工具 `moon run test-lab/tools/c0-bubble-print-62-reference.mbtx` 从根目录重建 62% 参考，两个整页栅格与登记件逐字节相同。

四条气泡图 Chromium 用例在前批全部通过。两张图在 62% 和 65% 的四组整页 PDF 均为 0/0。两张完整 Canvas 在原件和新 Worker 重开后的四组比较也为 0/0。确认同倍率验收后，当前构建复跑两条打印用例，四组整页 PDF 仍为 0/0。源保存及新 Worker 的 PDF 字节一致通过。证据归私有 `nativeC43BubblePrintMatchedScale.currentReplay`、`currentPrintReplay` 和 `approvedPrintReplay`。C43 整表最近一次严格结果仍为 10/30。

C47 的历史拒绝批次在主关系解析前报告 `unsupported-xlsx`，错误为 `Strict OOXML is unsupported`。旧实现误报主关系缺失。原件断言先失败，修复后通过。`bun run test:c0-core` 现从已有登记装载共用测试助手，执行 63 份 C0 测试文件的 227 项检查，全部通过。两条 PPTX 断言同步了源 XML 省略缩放的表示，实际 100% 缩放、原生几何及精确历史断言保持。复跑有界扫描，46 个正向候选打开，五个控制项在打开阶段拒绝。仅 C47 的错误信息变化，证据归私有 `nativeC47StrictXlsxRejection`。

C13 的 SmartArt 参考诊断归私有 `nativeC13SmartArtMaskGroupCandidate`。固定原生 PDF 有 117 个亮度软遮罩 Form 缺少透明组。候选只补这些字典。全部 216 个 PDF 流逐字节相同，42 页参考栅格逐字节相同。受影响六页的 Poppler 软遮罩警告消失。

首轮复用已核验哈希的 SDK 栅格。第 8–12 页的十组 Canvas/PDF 均为 0/0。第 14 页仍为 Canvas 960/970、PDF 954/948。候选的整稿结果为 88/96，正式结果为 78/96。直接原生 PNG 作为独立补充，第 8 页两组均为 0/0。

第 14 页行高归私有 `nativeC13SmartArtWhitespaceMetrics`。固定原生对照只调整段首空格字号。16、19、22 pt 的三行基线相同，同行横向位置随空格宽度变化。将空格换成可见字母后，三行基线分别移动 −1.620、+0.828、+1.620 pt。核心按可见文字计算混排行高，保留空格宽度。36 项 SmartArt 和 43 项相关排版检查通过，两批有重叠。

新构建对软遮罩候选复查第 8–12 页均为 0/0。第 14 页 PDF 降为 0/0，Canvas 降为 9/26。剩余点位集中在右侧竖排 `Topic` 字形。原件、背景编辑、精确历史及新 Worker 重开通过。[ONLYOFFICE 行度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L5060-L5134)

正式参考复跑全部 48 页，仅第 14 页的两张 SDK 栅格变化。全部参考和其余 94 张 SDK 栅格逐字节相同。正式结果为 78/96，软遮罩候选为 89/96，候选待确认。

第 14 页两个竖排标签的对照归 `nativeC13SmartArtRotatedRasterRoutes`。同一固定引擎的屏幕 PNG 与软遮罩 PDF 候选在两个区域合计为 26/0。SDK Canvas 对屏幕 PNG 为 3/2，对 PDF 候选为 9/26。SDK PDF 对候选整页为 0/0。两个区域的结果只用于区分绘制路径。

C13 第 14 页旋转字形归私有 `nativeC13QuarterTurnGlyphPhases`。独立参考的 Carlito 28 和 32 像素字形旋转后，设备缓存高度分别为 48 和 54 像素。沿用原生的 50 像素分界后，Canvas 对软遮罩 PDF 候选从 9/26 降为 0/0，对原生屏幕 PNG 从 464/700 降为 446/437。PDF 栅格保持。正式整稿为 78/96，软遮罩候选为 90/96。仅第 9、13、14 页 Canvas 栅格变化，第 9 页对候选保持 0/0，第 13 页对正式参考保持 0/0。

首轮浏览器在编辑重开阶段超时。关闭测试浏览器的下载副本后，原件及编辑流程的 102 组对照全部执行。编辑、精确历史及新 Worker 重开通过，正式视觉仍失败。227 项核心与六条共用浏览器像素回归通过。

C13 第 7 页的 SmartArt 背景编辑现有独立整页对照。原生输入只在该页加入黄色背景，其他 282 个部件逐字节相同。固定 ONLYOFFICE 输出只改变一条背景绘制指令，另有时间与交叉引用元数据变化。正式 Chromium 用例新增改后 Canvas/PDF 对照，两组均为 0/0。背景修改后的保存、精确撤销重做及新 Worker 重开通过。原稿 16 组对冻结参考通过 4 组，对软遮罩候选通过 16 组。关闭重复下载后的正式报告逐字节相同。证据归私有 `nativeC13SmartArtMaskGroupCandidate.backgroundEdit`。

文件替换的最新证据归私有 `c0CompoundContainerDiagnostics`。Chromium 使用 C47–C51 五个固定对照。旧版 PPT 和加密 DOCX 识别为 OLE 复合容器，报告 `unsupported-package`。Strict XLSX 报告 `unsupported-xlsx`。加密 PDF 和损坏 PDF 分别报告加密限制和交叉引用错误。

五项归档核心检查与两条 Chromium 流程通过。51 份有界扫描中，46 个正向输入通过，五个对照按预期拒绝。只有 C48 和 C49 的诊断与前批不同。截断 ZIP 仍报告包损坏，超预算输入先按预算拒绝。

PPTX 和 PDF 各另触发一次字体和画布故障。九次失败均清理候选，保留原编辑器及 revision。四份当前文档均可逐字节原样保存。前批归 `c0AllReplacementControls` 和 `c0DocumentFailureStages`。损坏 GIF 在后者的构建报告 `image`，保留 `InvalidStateError` 名称，当前编辑稿仍可逐字节原样保存。

同构建的七条 Chromium 流程全部通过，覆盖四种格式的保存、重开和会话保留。XLSX 检查核对分段边线、滚动后可见单元格的格式刷及列宽更新。DOCX 检查核对撤销后工具栏的键盘焦点。

C13 第 42 页的 GIF 颜色候选归私有 `nativeC13GifBulletReferenceCandidate`。原件和独立编辑参考各有两条 GIF 转成的 JPEG 颜色流。两份 PDF 的透明遮罩均与对应源 GIF 的 Alpha 逐字节相同。候选只恢复两条颜色流。两份候选各有 47 页栅格逐字节相同。

对照复用已核验哈希的 SDK 原件和改后栅格。第 42 页两张 Canvas 各消除四处颜色差异，两张 PDF 继续为 0/0。候选合计四组为 0/0。正式参考与验收计数保持，候选待确认。

联合诊断归私有 `nativeC13CombinedReferenceCandidate`。SmartArt 遮罩修正只影响第 8 至 12、14 页。GIF 颜色修正只影响第 42 页。其余 41 页参考栅格逐字节相同。

当前构建完成 102 组 Chromium 对照。原稿通过 91/96，改后通过 6/6。48 次 PDF 导出、原生输入、精确历史和新 Worker 重开通过。102 张 SDK 栅格与正式批次逐字节相同。候选仍有第 3、15、28、36 页的五组差异。正式参考的通过数仍为原稿 78/96、改后 5/6。

C43 扇区底纹的定位归私有 `nativeC43SectorPatternBounds`。图案以扇区路径边界为原点。核心依据原生画刷的位置和尺寸断言，修复前失败，修复后 13 项定向检查通过。

冻结的原生 PDF 为图案扇区选中画刷，却以空路径填充。诊断仅复用紧随其后的原生红色描边路径。底纹图像、图案矩阵和页面其余内容保持。整表另外 14 页栅格逐字节相同。修复后，第 4 页 PDF 对诊断候选从 2/8 降至 0/0，隔离饼图 PDF 从 2850/2450 降至 0/0。第 4 页 Canvas 对候选仍为 11376/4819。

正式整表比较仍为 10/30，除第 4 页外的 28 张 SDK 栅格和全部冻结参考栅格逐字节相同。第 4 页正式 Canvas 为 1907/9162，PDF 为 10/11719。原件保存、重开及四份圆形图控制共五条 Chromium 流程通过。两条隔离圆形图流程仍失败，正式参考保持冻结。

同一构建的隔离圆环图 Canvas 对直接原生 PNG 为 85/71，对冻结原生 PDF 栅格为 11555/9903。PDF 正式对照为 0/0。直接输出与 PDF 的底纹周期不同，这组结果用于归因。

C43 圆环图的绘制顺序归私有 `nativeC43DoughnutPaintOrder`。修复后，103 个扇区的颜色顺序和 PDF 提取的标签顺序与原生一致。七项核心检查通过。隔离图 Canvas 对直接原生 PNG 从 85/71 变为 67/74。只把两处底纹改为纯白的对照从 29/5 变为 11/8。

圆环图的正式 Canvas 仍为 11555/9903，PDF 为 0/0。普通饼图的 Canvas、PDF 和栅格逐字节相同。C43 整表保留 18 个绘图对象，原样保存通过。15 页 PDF 结构检查通过，30 组比较仍为 10/30。第 4、7 页四张 SDK 栅格发生变化，第 7 页 Canvas 减少一个差异像素。全部正式参考栅格相同，三条严格用例均仍失败。

原生圆环扇区路径归私有 `nativeC43DoughnutPath`。新版 PDF 的 103 条路径操作顺序与独立原生 PDF 一致。2,252 个坐标的最大误差为 0.00024 pt。旧版路径断言失败，修复后七项核心及 C10 的 Chromium 回归通过。

圆环图正式 PDF 为 0/0，Canvas 为 11558/9903，参考一侧比前批多三个差异像素。直接原生 PNG 对照仍为 67/74，纯白底纹对照由 11/8 变为 11/7。普通饼图的 Canvas 和 PDF 逐字节相同。C43 整表第 4、5、7、8 页共八张 SDK 栅格变化，全部比较计数保持，正式结果仍为 10/30。三条 C43 严格用例仍失败。

圆环图的原生 PNG 按输出像素宽高与 A4 纸张尺寸分别计算横纵比例。Chromium 诊断使用这两个比例和原生打印原点后，原始底纹版从 67/74 降至 7/2，纯白对照从 11/7 降至同一组 7/2。九次差异中，最后绘制的是七次文字和两次扇区填充。普通重放逐字节复现 SDK 原图。证据归私有 `nativeC43DoughnutPath.directPageMapping`，正式结果沿用上批记录。[ONLYOFFICE 页面比例](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/graphics/Graphics.cpp#L301-L346)

前批构建复跑 C43 正式整表，30 张 SDK 栅格与上一批逐字节相同。原样保存、15 页 PDF 结构检查及 18 个绘图对象断言通过，严格整表仍为 10/30。第 4 页对恢复扇区底纹的诊断候选，Canvas 和 PDF 均为 0/0。隔离饼图对同样修正的参考，PDF 为 0/0，工作区 Canvas 为 737/944。冻结参考和断言沿用原验收。证据归私有 `nativeC43SectorPatternBounds.currentVerification`。

当前构建复跑整表与隔离圆形图候选。原生打印候选只在第 4 页和隔离饼图的空填充指令前复用同一原生扇区轮廓。另 14 页的 PDF 内容流和栅格逐字节相同。SDK 的 15 页 PDF 与 30 组正式比较复现上一批。整表第 4 页两组候选均为 0/0，整表候选为 12/30。隔离饼图和圆环图的同倍率工作区 Canvas 与整页 PDF 四组均为 0/0，圆环图 75% 另有两组为 0/0。四条 Chromium 流程通过，包含源保存及隔离图的新 Worker 重开。正式参考维持冻结，候选待确认。证据归私有 `nativeC43SectorPatternBounds.reviewedCandidate`。

GenOffice 0.11.727 在 C43 原件的 `Лист1!A57` 显示饼图，但把源扇区底纹画成纯色。先前的 ONLYOFFICE 直接 PNG 来自打印转换。现在用同一固定构建的工作区绘制函数，从未改的隔离工作簿导出图表。绘制前在内存应用原图表锚点尺寸，按工作区缩放输出。两个图框区块共 51,744 个像素与 8×8 源掩码逐值一致，绘图区沿用小数起点。

工作区按设备像素平铺后，圆环图对原生工作区从 14037/13736 降至 6/5，另一档缩放的重放从 12998/4262 降至 12/4。普通饼图从 1973/1034 降至 991/401。两张 SDK PDF 与前批逐字节相同，原样保存和新 Worker 重开通过。四条 Canvas 流程与 11 项核心检查通过。两条正式 Canvas 仍比较冻结的打印参考，圆环图为 12732/12255，饼图为 4/6124。整表沿用前批证据。本批归私有 `nativeC43ChartScreenHatches`。

圆环图仅跳过文字绘制后，两边整图为 0/0。478 个可见字形编号逐个一致，设备原点最大横向误差低于 0.0003 像素。工作区按整数设备坐标落字后，93% 缩放的圆环图从 6/5 降至 0/1，75% 缩放整图为 0/0。普通饼图对原生工作区为 974/398。正常 Worker 原样保存和重开通过，两张导出 PDF 逐字节相同。11 项核心检查和 4 条共享 Canvas 流程通过。93% 的两条正式用例仍用冻结的打印参考，圆环图 Canvas 为 12732/12260，饼图为 20/6137。整表未复跑。证据归私有 `nativeC43ChartScreenGlyphs`。[ONLYOFFICE 字形落点](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/graphics/Graphics.cpp#L1024-L1065)

C43 普通饼图的图例描边归私有 `nativeC43PieLegendScreenStroke`。原生跟踪逐字节复现工作区参考。0.25 pt 图例外框与 1 pt 标记描边均使用小数设备坐标。Chromium 重放只改外框时从 974/398 降至 0/397，再改标记后为 0/0。正常 SDK 工作区在 93% 缩放下复现整图 0/0。

11 项核心及 6 条共享 Canvas 流程通过。两张图的导出 PDF 与前批逐字节相同，原样保存和新 Worker 重开通过。圆环图 75% 工作区为 0/0，93% 为 0/1。两条正式用例沿用冻结打印参考，饼图 Canvas 为 988/6561、PDF 为 0/4483，圆环图为 12732/12260、0/0。整表未复跑。

圆环图 93% 工作区的余差归私有 `nativeC43CircularGlyphSizeProbe`。整数落点重放逐字节复现 75% 和 93% 的 SDK 原图。余差落在百分号，原生该点无文字覆盖。用同一字体的设备字号轮廓替换 8 pt 百分号后，两档均为 0/0。所有字形统一取整也使圆环图为 0/0，但普通饼图新增四点。完整设备轮廓对照中，普通饼图仍为 0/0，圆环图仍为 0/1。产品沿用现有字号和绘制规则。[FreeType 整数像素字号](https://github.com/freetype/freetype/blob/VER-2-10-4/src/truetype/ttobjs.c#L1245-L1277)

固定 ONLYOFFICE 的单字形输出定位到 8 pt 粗体百分号。随附 FreeType 执行字体内置指令后，复算该区域的 RGB 与原生最多相差一级。MoonBit 复用现有轮廓库按设备倍率执行内置指令，保留原点及字距。正常 Chromium 的圆环图 93% 和 75%、普通饼图 93% 均为 0/0。两张隔离 PDF 对各自独立对照为 0/0，普通饼图的冻结参考仍有 0/4483。完整原件的 15 页 PDF 与此前通过 qpdf 的文件逐字节相同，30 组整页栅格和差异计数也相同。239 项登记核心通过。证据归私有 `nativeC43CircularGlyphSizeProbe.deviceFit`。

C43 第 12 页的气泡图例归私有 `nativeC43WorksheetChartResiduals`。固定原生打印使用蓝色菱形、红色方形和绿色三角形。SDK 按源系列样式绘制圆形。独立打印保留气泡图的原始锚点。加入前置三维柱图，或只更改第一个气泡系列的填充色，第 12 页均逐字节相同。

第 10、11 页的冻结 PDF 复现了隔离参考中的两种降级，复合饼图只显示普通饼图，气泡只显示散点。正式整表结果仍为 10/30。

C43 第 1 页的深度轴标题初始诊断归私有 `nativeC43Page1DepthTitle`。源标题布局为空。固定 ONLYOFFICE 把标题放在页面原点附近，图框裁剪使它不可见。两个独立对照只给标题设置显式位置，第一页操作流均只改一条平移指令。该批 Canvas 为 42/315，PDF 为 45/318，标题区域外均为 0/0。核心两项通过，包括当时的标题留量、图框内显示及移除后不再绘制。当前按用户选择跟随主引擎，结果见上方深度轴标题批次。[ONLYOFFICE 标题定位分支](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L655-L674)

显式深度轴标题位置归私有 `nativeC43DepthTitleEdgeLayout`。两份对照先因手工布局受保护而失败。修复后两项核心检查通过，标题原点与独立 PDF 相差小于 0.001 pt，绘图区保持同一位置。Chromium 三条流程保留 18 个绘图对象、源字节和 15 页导出。两个显式位置对照的首页 Canvas/PDF 四组均为 0/0。自动位置原件的 15 页 PDF 与前批逐字节相同，首页的正式差异保持。

显式贴边标题现按含内边距的标题框限制位置。独立 C43 对照只改标题坐标，`0.99` 和 `1.0` 得到相同的标题平移，其余首页绘制指令相同。修复前核心测试复现标题越界，修复后五项三维柱图和曲面图检查通过。正常 Chromium 的贴边对照首页 Canvas/PDF 均为 0/0，原样保存及新 Worker 的预览和 15 页 PDF 字节一致。原件 30 组正式对照仍通过 10 组，首页仍为 Canvas 42/315、PDF 45/318，全部冻结参考栅格保持。证据归 `nativeC43DepthTitleEdgeLayout.clamped`。[ONLYOFFICE 位置限制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L5780-L5796)

LibreOffice 在 C43 原件和隔离柱图中均显示自动深度轴标题。仅加长隔离图标题，右端位置保持在 0.02 pt 内。SDK 的宽标题控制曾超出图框约 10 pt，该批采用显式标题的边界限制，绘图区保持。五项核心和正常 Chromium 的完整标题提取、原样保存通过。该批 C43 原件 15 页 PDF 和 30 张栅格与前批逐字节相同，冻结参考下为 10/30。证据归 `nativeC43Page1DepthTitle.automaticBounds`，当前自动标题显示已跟随选定主引擎。[LibreOffice 自动标题边界](https://github.com/LibreOffice/core/blob/bf6ef2662401c7d6dce671ab4deb26ee0af3a7c1/chart2/source/view/main/ChartView.cxx#L1023-L1042)

C43 曲面图的显式系列轴标题归私有 `nativeC43SurfaceSeriesTitleEdgeLayout`。只在隔离 chart11 中给 `YYY` 设置 `edge` 位置，其他解包部件逐字节相同。ONLYOFFICE 导出的页面内容流只改了一条平移指令。修复后五项曲面图和三维柱图核心检查通过，首字原点与原生相差小于 0.001 pt。

显式位置对照的 Canvas 与 PDF 整页均为 0/0。原样保存、新 Worker 重开和 PDF 字节一致通过。三张自动位置原图的 PDF 和两种栅格与固定批次逐字节相同。chart12 和 chart13 两条用例通过，chart11 对冻结参考仍为 Canvas 0/48、PDF 0/48。整表未复跑。

C43 第 13 页归私有 `nativeC43Page13BubbleSize`。现有一像素邻域与颜色容差下，PDF 的 38687/42104 个差异全在顶部气泡图区。中部柱线组合图和底部等高线图均为 0/0。

隔离对照只把首个气泡的绑定单元格 `C2` 与对应缓存改为原值的四分之一。其余解包部件逐字节相同。ONLYOFFICE 两张整页 PNG 与旧隔离参考逐字节一致。LibreOffice 首个气泡的 PDF 路径高度由 60.729 pt 缩为 30.365 pt。该对照只验证源尺寸的影响，正式验收仍使用冻结参考。[ONLYOFFICE 气泡转散点路径](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/common/Drawings/Format/ChartFormat.js)

C43 第 14 页和第 5 页的整页 PDF 分区归私有 `nativeC43WorksheetPageAttribution`。第 14 页的面积图区为 0/0。顶部为 1440/2000，集中在上一页延续的气泡图。中间为 22/154，其中 `YYY` 标题所在区域占 17/151。第 5 页的 1057/1194 个差异中有 1049/1194 在中间带，主要集中在逐点着色的散点标记。固定参考省略了这组标记。两页使用最近正式批次的栅格和容差，严格通过仍为 10/30。

第 5 页顶部的八个差异坐标在 Canvas 和 PDF 中相同。原件指定第 23 号点使用灰色圆形标记，冻结 PDF 保留同色曲线但省略圆形。临时重放仅略过该圆形，顶部 Canvas 从 8/0 降为 0/0。正式结果保留原件标记。证据归私有 `nativeC43WorksheetPageAttribution.page5TopMarker`。

C43 第 8 页的面积图对照归私有 `nativeC43Area3dCachedReference`。同一固定引擎只把第三系列的工作表引用换成原有 26 个缓存数值，首点仍为零。原生输出增加 25 个黄色面。只改变第 8 页的面积图区，其余 14 页栅格逐字节相同。

Chromium 用未改的原件复查。SDK 两张栅格及 15 页 PDF 与正式批次逐字节相同，原样保存通过。候选的面积图区 Canvas/PDF 均为 0/0，整页仍为 Canvas 3790/3513、PDF 3142/2883。正式第 8 页仍为 20484/20798、19843/20173。

当前 PDF 对面积图候选的 3142/2883 个差异全部位于页底 190 个像素行。原件 `chart17.xml` 定义带自定义分组的复合饼图。页底是该图跨页的起始区域，冻结参考绘制普通饼图。证据归私有 `nativeC43Area3dCachedReference.currentContinuation`。

第 8 页预览另有 487 个差异位于面积图底边。独立 PDF 的四种设备相位和三种线宽确认，往返重叠的水平描边与单条直线在线段内部覆盖相同。核心把零旋转的底面描边输出为单条直线，五项检查和独立显式零值图的完整 Canvas/PDF 通过。第 8 页预览与 SDK PDF 从 487/0 降至 0/0。与面积图候选相比，两种输出的余差均只在页底复合饼图区。正式整表仍通过 10/30，另 28 张 SDK 栅格与全部参考逐字节相同。第 8 页 PDF 仅右端一个像素变化，仍在原容差内。证据归私有 `nativeC43Area3dCachedReference.floorStroke`。

C43 的 15 页打印预览与 SDK PDF 用相同容差逐页比较。第 5 页的旋转轴标题从 121/137 降至 0/0。预览按旋转后的字体高度选择横向四分之一像素或整像素落点，现有字形回归覆盖 50 和 51 像素的边界。第 5 页 Canvas 对冻结参考从 1185/1303 降至 1050/1182。其余三张有字节变化的预览保持原比较结果。15 页 PDF、全部冻结栅格和原样保存的工作簿字节一致。整表对冻结参考通过 10/30。证据归私有 `nativeC43WorksheetPageAttribution.rotatedTitlePhases`。

第 12 页的曲线图例描边先拆成线段，再复用零宽描边规则。独立 PDF 的直线和曲线覆盖均与预览逐像素一致。第 12 页的预览与导出从 25/0 降至 0/0，至此 15 页均为 0/0。其余 29 张实际栅格、全部冻结参考及 SDK PDF 字节一致。第 12 页 Canvas 对冻结参考为 4943/5124，整表正式结果仍为 10/30。证据归私有 `nativeC43WorksheetPageAttribution.curvedHairlines`。[Poppler 的字体缓存规则](https://gitlab.freedesktop.org/poppler/poppler/-/blob/poppler-26.05.0/splash/SplashFont.cc) · [Poppler 的零宽描边](https://gitlab.freedesktop.org/poppler/poppler/-/blob/poppler-26.05.0/splash/Splash.cc)

最终构建通过 17 条 Chromium 定向用例，覆盖字形、直线和曲线描边及两张气泡图的预览、打印和重开。两张图按 62% 和 65% 复跑，四组整页 PDF 均为 0/0。

C43 的 15 页严格整表用例已纳入 `bun run test:c0-xlsx`。在 `test-lab/` 运行该命令并加 `--grep 'Complete original C43 worksheet'` 可单独复跑。用例读取已冻结的 100% 比例参考，核对其 PDF、源工作簿、字体和各页栅格的哈希。

C43 圆形图的打印顺序归私有 `nativeC43CircularDrawingOrder`。原生对照保留饼图和图框，只改绘图锚点列表。单独打印或先于三维柱图时，饼图半径为 175.31 pt。三维柱图在前时，半径为 173.40 pt。定向核心共 11 项通过，包括三份顺序对照和原样保存。

复跑全部 15 页，第 4、5、7、8 页的 Canvas/PDF 差异均减少。第 4 页 Canvas 从 24312/30406 降到 1904/9170，PDF 从 22379/32940 降到 8/11731。其余 22 张 SDK 栅格及全部参考栅格逐字节相同，严格通过仍为 10/30。五条 Chromium 流程通过，包括原件保存和新 Worker 重开。隔离饼图与圆环图的 PDF 字节与前批一致，圆环图 PDF 为 0/0。两张隔离圆形图的 Canvas 及两张复合饼图仍有差异。

C43 第 7 页分区对照归私有 `nativeC43Page7CircularResiduals`。整页 PDF 的 3994/4411 个差异全在下方复合饼图区，冻结参考在那里绘制普通饼图。中间雷达图区和上方圆环图区的 PDF 均为 0/0。圆环图区 Canvas 为 1773/347，只打开底纹平滑采样的诊断降至 1257/298。诊断沿用正式颜色容差，保留现有 PDF 画布的像素单元规则。

复合饼图的数值阈值选中源数据末尾 12 点，首个错误单元格继续视为空值。只将诊断文件的拆分方式改为等价的位置规则，LibreOffice PDF 的次图由默认两段变为 12 段。这份对照用于核对分组。[LibreOffice 拆分导入](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/oox/source/drawingml/chart/typegroupconverter.cxx#L474-L480)

2026-11-07 的正式 15 页用例通过源字节和 qpdf 结构检查，整页对照仍为 10/30。第 7 页的圆环图区和雷达图区在两种输出中均为 0/0。Canvas 的 3981/4417 和 PDF 的 3992/4428 差异全部位于第 1500 行起的复合饼图区。现有核心用例按上述 LibreOffice PDF 核对条形次图 12 段的颜色、自下而上的顺序和相对高度，三项定向核心检查通过。证据归私有 `nativeC43Page7CircularResiduals.currentVerification`。

C43 的位置拆分读取归私有 `nativeC43PositionalOfPie`。两项核心检查通过，覆盖等价拆分、原样保存和非法点数。Chromium 的隔离图对照中，末尾 12 点版与数值阈值版的 Canvas 和 PDF 逐字节相同。两版均通过原样保存及新 Worker 重开，冻结视觉对照仍失败。正式整表的 30 组栅格与前批一致，仍为 10/30。

C43 的百分比拆分归私有 `nativeC43OfPiePercent`。8.25% 与末尾 12 点版的两页打印指令完全相同。四项核心检查覆盖阈值相等、空值、零总和与非法范围。旧 Chromium 探针改的是未显示的 `chart16.xml`。当前复跑改用实际显示的 `chart1.xml`，两版均绘出 12 段条形，Canvas、导出 PDF 和 PDF 栅格逐字节相同。原样保存及新 Worker 重开通过。冻结视觉对照继续失败。

C43 的饼形次图尺寸和间距归私有 `nativeC43OfPieGeometryControls`。把原图表定义放入单页幻灯片，GenOffice 0.11.727 的三个对照测得次图直径为主图的 169.6%、59.8%、169.8%，间距为次图直径的 120.9%、121.2%、354.8%。已有核心测试新增原件的 170% 和 120% 几何断言，两项通过。幻灯片使用替代分组，条形次图也被绘成饼形。工作表对照均绘成柱图，三份栅格逐字节相同。

C43 第 17 张图的自定义拆分归私有 `nativeC43OfPieCustomNative`。将 11 个源成员移到字面数值序列末尾，保留两组内的顺序、数值和逐点样式。LibreOffice 的位置拆分对照与 SDK 原件导出的 25 个源扇区颜色相同，含合并扇区的角度最大差为 0.029°。原件核心用例现核对全部 11 个次图扇区的颜色和两条径向边，五项定向核心通过。该对照的合并扇区颜色和尺寸不同，完整视觉仍以冻结参考验收。[OOXML 拆分方式](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.charts.splitvalues?view=openxml-3.0.1)

第 10、11 页的正式 PDF 分区沿用同一容差。堆积条图与曲面图区均为 0/0，全部差异位于复合饼图及气泡图区。区域结果归 `nativeC43WorksheetPageAttribution`，最近正式整表仍为 10/30。

C39 文字装饰线归私有 `nativeC39TextRuleGrid`。全页差异定位到七条像素行。核心标记 DOCX 文字装饰线，Canvas 复用已有轴对齐实线描边。原件 Canvas 从 855/178 降至 0/0，原件及改后 SDK PDF 均与前批逐字节一致。独立改后参考只在末尾空白正文段插入 `!`。原件及改后 Canvas/PDF 四组整页均为 0/0。正常界面的源保留、精确撤销重做和新 Worker 重开通过。LibreOffice 重开 SDK 保存文件的页面栅格与独立改后参考逐字节相同。最终构建通过 21 项定向核心及三条 Chromium 流程。PPTX 字号回归分别校验源 XML 的 22.35 pt 和显示的 22.5 pt。[ONLYOFFICE 屏幕横线绘制](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Drawing/Graphics.js#L2178-L2230)

C39 混合字号空格归私有 `nativeC39SpaceMetrics`。ONLYOFFICE 对照只缩小五处空格，横向位置和断行变化，同行基线一致。原件采用 LibreOffice 的字体替代配置及三份固定 Liberation 字体。SDK 续框首行与该参考一致。该批原件 144 dpi 整页 PDF 从 32196/34112 降至 0/0，Canvas 从 32664/34201 降至 855/178。六项核心和四条浏览器流程覆盖空格宽度、全空格行、链接框分配、原生输入、精确历史及保存重开。

C01 的母版及版式归私有 `nativeC01MasterLayouts`。默认界面按源顺序读取 11 个版式，空白页隐藏母版提示。输入 `Native title` 保留居中标题占位符及 39 个非目标包部件，包括母版和版式的日期域。固定 Carlito 和 144 dpi 时，原件与独立编辑参考的四组 Canvas/PDF 整页对照均为 0/0。精确撤销重做及新 Worker 重开通过。ONLYOFFICE 重开 SDK 保存文件后，页面栅格与独立编辑参考逐字节相同。[LibreOffice 上游用例](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sd/qa/unit/export-tests-ooxml5.cxx#L1194-L1209)

C43 三维柱图的错误占位零归私有 `nativeC43BarErrorGap`。独立对照仅把 E2 从 `#DIV/0!` 改为数值零，原生 PDF 随即绘出零高度柱面。核心把对应缓存零绘为空点，保存保留源错误和缓存。实际数值零的源控制通过，10 项定向核心全部通过。15 页严格复查中，第 1 页 Canvas 从 46/341 降到 43/316，PDF 从 48/344 降到 45/318。其余 28 张 SDK 栅格及全部参考栅格逐字节相同，整表仍为 10/30。

原工作簿的原样保存和新 Worker 重开通过。独立堆积条图的 Canvas/PDF 保持 0/0。透视柱图的隔离用例仍为 Canvas 0/130、PDF 0/125，包含源轴标题区域。首页完整视觉仍待通过。

C43 首页的虚线图框归私有 `nativeC43OpenDashedFrame`。固定原生 PDF 的图框路径显式回到起点，首尾为平端。核心保留这一路径，Canvas 复用矩形虚线的相位与像素边界规则。两项核心检查和三条 Chromium 流程通过，独立双轴折线的 Canvas/PDF 均为 0/0。整表首页 Canvas 从 43/316 降至 42/315，其余 29 张 SDK 栅格及全部参考栅格逐字节相同。原样保存通过，整表严格结果仍为 10/30。

C43 气泡图例的细线归私有 `nativeC43BubbleLegendHairline`。三枚圆形标记在固定原生 SVM 中都使用零线宽。核心按设备细线绘制图例，数据气泡沿用源线宽。两项核心检查通过。无图例屏幕用例原件和重开均为 0/0，有图例从 4/4 变为 5/4。旧描边差异消失，另有两个描边差异点。原生圆弧有两个控制点与 SDK 相差 0.01 mm。两张气泡图的严格 PDF 对照仍失败。

整表仅第 12 页的 SDK 栅格变化。Canvas 从 4301/5234 降到 4280/5164，PDF 从 4294/5251 变为 4302/5159。全部冻结参考逐字节相同，原样保存通过，整表仍为 10/30。

C43 气泡图例圆弧归私有 `nativeC43BubbleLegendCoordinates`。按图表坐标取整后，Chromium 实际绘制指令的 111 个坐标点全部匹配三枚原生 SVM 圆形描边。两项核心检查通过。无图例原件与重开仍为 0/0，有图例两组仍为 5/4，隔离 PDF 仍为 45224/45444。原样保存及新 Worker 重开通过。整表仅第 12 页栅格变化，Canvas 从 4280/5164 变为 4281/5165，PDF 差异计数相同。冻结参考相同，严格整表仍为 10/30。

当前构建的有图例气泡图在 Chromium 逐字节重放后仍为 5/4。七处差异最后由轴标签或图例文字绘制写入，两处落在黄色图例标记的细描边。给文字统一加四分之一像素偏移后，有图例为 1/4，无图例从 0/0 变为 0/1。绘制保留现有取样位置，证据归私有 `nativeC43BubbleLegendCoordinates.remainingViewRaster`。

固定 LibreOffice 重放原生气泡图，输出与冻结 PNG 逐字节一致。只把三个图例圆形描边从零线宽改为 96 dpi 下的一设备像素后，整图从 5/4 降为 4/3。消失的坐标是 `(899, 307)` 和 `(899, 299)`，其余七处位置相同。该对照验证细线与几何描边的差异。正式视图仍为 5/4。[LibreOffice 描边实现](https://github.com/LibreOffice/core/blob/bf6ef2662401c7d6dce671ab4deb26ee0af3a7c1/vcl/skia/gdiimpl.cxx#L1124-L1203)

Chromium 预先换算设备坐标、使用软件 Canvas 或将线宽改为 0.999 像素时，整页输出逐字节相同。逐段绘制三枚图例标记时，圆端和方端覆盖了上述两处差异，平端仍为 5/4。原生闭合路径使用平端，因此这些对照只用于定位覆盖率差异。证据归私有 `nativeC43BubbleLegendCoordinates.remainingViewRaster.browserHairlineReplay`。[Skia 细线绘制](https://github.com/google/skia/blob/ad8ecedbfdef9f4ae4b1e73347b6dd56e6637d38/src/core/SkDraw.cpp#L852-L908)

同一份原生视口文件显式用 LibreOffice 的 `svp` 后端渲染时，PNG 与冻结参考逐字节一致。只允许默认字体 hinting 后，1,712 个像素改变，对 SDK 为 4/6，原有两处描边差异坐标的 RGB 保持。切到 macOS 的 Skia 后端后，27,285 个像素改变，对 SDK 为 80/4。两处描边差异消失，其他位置出现差异。证据归私有 `nativeC43BubbleLegendCoordinates.remainingViewRaster.nativeBackendReplay`。[LibreOffice 后端选择](https://github.com/LibreOffice/core/blob/bf6ef2662401c7d6dce671ab4deb26ee0af3a7c1/vcl/source/app/salplug.cxx#L229-L245) [Cairo 字体选项](https://github.com/LibreOffice/core/blob/bf6ef2662401c7d6dce671ab4deb26ee0af3a7c1/vcl/unx/generic/gdi/cairotextrender.cxx#L459-L497)

Chromium 将三枚细线标记的坐标按 1/256 设备像素取整，并核对闭合路径和同次描边的分离曲线。取整改变部分像素，三组重放均仍为 5/4。该批四条正式用例通过三条，四组打印均为 0/0。两张图的原件与新 Worker Canvas 栅格均与上一批逐字节一致。有图例视图两组仍为 5/4，正式参考及断言保持。[Cairo 细线绘制](https://github.com/LibreOffice/core/blob/bf6ef2662401c7d6dce671ab4deb26ee0af3a7c1/vcl/headless/CairoCommon.cxx#L1079-L1114)

气泡图屏幕字形保留逻辑宽度，高度仍按设备像素取整。固定 LibreOffice 随附的 Cairo 1.18.4 与 FreeType 用原生 SVM 的 17 段文字重放。13 像素宽时没有一段逐像素相同，约 13.34 像素宽时有七段相同。Chromium 的字形覆盖回归由 63 修正到预期 127。五项共享绘制测试通过。无图例原件和新 Worker 均为 0/0，有图例两组从 5/4 降到 1/3，仍有两处图例细线和两处轴标签边缘差异。62% 和 65% 四组打印为 0/0，PDF 字节与修改前相同。证据归私有 `nativeC43BubbleLegendCoordinates.remainingViewRaster.fractionalEmWidth`。[Cairo 1.18.4 源码](https://www.cairographics.org/releases/cairo-1.18.4.tar.xz)

关闭固定 LibreOffice 的细线吸附后，原生 PNG 与一像素描边对照逐字节相同。仅轮换闭合曲线的起点时，PNG 与冻结参考逐字节相同。Canvas 现按原生 Cairo 图元规则把零线宽描边的端点和贝塞尔控制点吸附到设备像素中心。变换后的曲线回归通过，六项既有共享绘制测试通过。有图例原件和新 Worker 从 1/3 降到 0/2，只剩轴标签 `6` 上缘的两点。无图例为 0/0。四组打印为 0/0，PDF 字节与修改前相同。证据归私有 `nativeC43BubbleLegendCoordinates.remainingViewRaster.hairlinePixelCenters`。[LibreOffice Cairo 路径吸附](https://github.com/LibreOffice/core/blob/bf6ef2662401c7d6dce671ab4deb26ee0af3a7c1/drawinglayer/source/processor2d/cairopixelprocessor2d.cxx#L282-L350)

固定 FreeType 的轻度字形调整配合四分之一像素基线后，两张气泡图的完整视图重放均为 0/0。固定 Fontations 移植复现该结果。正式产品复用轮廓资源，原件和新 Worker 的四组 Canvas 均为 0/0，保存字节和重开栅格一致。62% 和 65% 的四组整页 PDF 均为 0/0，导出字节与前批一致。五项核心检查和十一项 Chromium 用例通过。首轮构建因依赖调试日志引入 Wasm 导入而无法打开，补丁移除日志后通过。证据归私有 `nativeC43BubbleLegendCoordinates.remainingViewRaster.lightScreenOutlines`。

C43 的散点图例归私有 `nativeC43ScatterLegendPointColors`。独立控制只关闭第二组的 `varyColors`，原生 PDF 恢复该系列的图例标记。核心按双组散点图的系列图例规则绘制，保留图内源标记。11 项核心检查通过。复跑 15 页后，第 6 页 Canvas 从 77/102 降为 0/0，PDF 从 78/103 降为 0/0。整表由 8/30 增至 10/30，其余 28 张 SDK 栅格及全部参考栅格逐字节相同。原工作簿和双轴折线的 Chromium 流程通过。隔离散点图仍为 Canvas 291/363、PDF 294/380。[ONLYOFFICE 标记编译](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L10164-L10257) [ONLYOFFICE 图例绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L7884-L7908)

C13 原图 RGB 验收归私有 `nativeC13SourceRgbReference`。正式参考从旧 ONLYOFFICE PDF 派生。四个图片流与原 PNG 解码的 RGB 逐字节相同。第 3、15、36、43 页的参考栅格变化，其余 44 页逐字节相同。旧参考保留。浏览器沿用五个固定字体、144 dpi、一像素和每通道 96 的容差。

C13 现从 `test:c0-pptx` 运行原稿全部 48 页。78/96 组为 0/0，旧参考已通过的 74 组保持通过。全部 96 张 SDK 栅格与旧参考那批相同。第 3、36 页 PDF 和第 43 页 Canvas/PDF 新增通过。第 15 页 Canvas 从 3/1 降至 3/0，第 36 页从 1678/393 降至 41/125。48 次 PDF 导出、无布局诊断及原样保存通过。11 页共 18 组视觉差异保留。

第 20、23、42 页的原生输入、源保留、精确历史及新 Worker 重开通过。六组改后对照中五组为 0/0，第 42 页 Canvas 为 0/4。第 36 页标注用例的框外指针选择、透明度编辑、精确历史和保存重开通过。两条正式用例的整页零差异断言仍失败。

C13 裁剪采样诊断归私有 `nativeC13OpaqueCropSampling`。以 PDF 像素边界取整，第 3、15、36 页的 Canvas 对正式参考均为 0/0。对独立的 ONLYOFFICE 直接 PNG，第 3、15 页从 0/0 退为 79/60、3/5，第 36 页从 78/35 退为 126/158。产品保留现有采样，正式参考和通过数量保持。

当前构建的裁剪图片复核归 `nativeC13OpaqueCropSampling.pinnedRouteReview`。第 3 页的原图 RGB 与冻结 PDF 图片流逐字节相同。按 PDF 图像矩阵取整，再按 Poppler 的双线性规则取样，图像内部 1,300,776 个像素全部相同。SDK Canvas 对原生直接 PNG 为 0/0，两者对冻结 PDF 栅格分别为 99/218 和 42/97。

全稿诊断只将第 3、15 页的 Canvas 与原生直接 PNG 比较，两页均为 0/0。其余 100 张参考栅格和全部 102 张 SDK 栅格哈希一致。48 次 PDF 导出、原生输入、精确历史及新 Worker 重开通过。该诊断为 80/96，首个严格失败为第 8 页。正式原稿仍为 78/96。

C13 第 36 页的分区复核归私有 `nativeC13Page36PhotoRoutes`。以原有容差比较，正式 PDF 栅格与原生直接 PNG 本身相差 156/188。仅保留原生 PDF 底图后，正式 Canvas 对照的 41/125 个差异坐标处，参考像素全部一致。SDK PDF 对正式参考为 0/0。SDK Canvas 对原生直接 PNG 的 78/35 个差异中，32/27 个在底图之外，集中在页首重叠文字。两种对照的 SDK 侧差异坐标无交集。

Chromium 与固定 ONLYOFFICE 的单页控制复现了页首的 32/27。移除白色标题后为 45/36，移除黑色模拟粗体文本框后为 0/0。单页原样版的两张完整栅格各自与整稿同页逐字节相同，四次原样保存通过。直接 PNG 将字形遮罩向右加一像素，原生 PDF 使用轮廓描边。用同源常规字重复算首个 `E` 和 `G`，343 个字形像素逐值一致。[ONLYOFFICE 字形遮罩](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/fontengine/FontFile.cpp#L929-L999)

单独比较第 36 页的照片层，SDK Canvas 对原生直接 PNG 为 0/0。固定采样规则在 144 dpi 复算照片内部的 982,760 个像素，全部逐值一致。加入前景后，标题下方的 46/8 个差异均涉及 SDK 的标注描边。诊断将 Canvas 的尖角连接改成斜角后，该区对原生 PNG 为 0/0，整页对冻结 PDF 参考从 41/125 变为 50/171。原生 PNG 和 PDF 的描边连接规则各自记录于 `nativeC13Page36PhotoRoutes.photoAndOutlineIsolation`。[原生 PNG 画笔默认值](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/graphics/structures.h#L205-L220)

第 36 页的独立诊断将原生直接 PNG 的照片采样放入原生 PDF，只替换照片绘制指令。照片框外像素全部一致。Chromium 以此对照 Canvas，以冻结参考对照 PDF，整页均为 0/0。尾部点击、半透明填充、精确历史及新 Worker 重开均通过。原件和改后的四张 SDK 栅格与正式运行的对应哈希相同。正式参考仍冻结，证据归 `nativeC13Page36PhotoRoutes.photoComposite`。

C09 媒体占位符归私有 `nativeC09MediaPlaceholder`。默认对象列表可选中空槽，媒体面板填入 VP8 WebM。对象 ID、`media` 类型、`quarter` 尺寸、索引 13 和禁止分组设置均保留。34 个非目标包部件逐字节保持。精确撤销重做、新 Worker 重开和实际解码放映通过。原件由固定 ONLYOFFICE 渲染，改后参考由同一工具重开 SDK 保存的 PPTX 生成。两种状态各两组 Canvas/PDF 整页对照均为 0/0。八项核心和四条 Chromium 流程通过。

本机 LibreOffice 26.8.1.1 另存未经编辑的原件时，将版式槽改为正文槽，并在幻灯片写入内部图标。这复现上游用例所记的旧问题。另存 SDK 改后文件时，该版本保留原 WebM 字节和两条媒体关系，省略占位符身份及分组限制。两份另存结果单独保留。[LibreOffice 上游用例](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sd/qa/unit/export-tests-ooxml4.cxx#L1019-L1036)

C12 的版式继承证据归私有 `nativeC12LayoutText`。两页显示同一个只读版式文本框。第二页显示上标 `nd` 和源页脚。母版占位提示在两页均隐藏。默认输入把首页副标题改为 `First page revised`，其他包部件逐字节保持。撤销重做和新 Worker 重开通过。固定 Carlito 和 144 dpi 时，原件和改后共八组 Canvas/PDF 整页对照均为 0/0。LibreOffice 另存保留改后副标题、共享文字、页脚和上标。[Apache POI 上游用例](https://github.com/apache/poi/blob/ae62bb5116b9aee19ebd5834e3a82066132c9f7f/poi-ooxml/src/test/java/org/apache/poi/xslf/extractor/TestXSLFPowerPointExtractor.java#L181-L211)

C08 的 RTL 项目符号归私有 `nativeC08RtlSymbolBullet`。原件声明 Wingdings 和 `v`，固定 ONLYOFFICE 参考绘制菱形。核心从实际符号字体读取对应字形。原件和四组独立控制核对悬挂缩进、换行及三种对齐方式。42 项核心检查和七条 Chromium 流程通过。

默认界面把 `Text` 改为 `Bext`。字形映射、原段落和非目标包部件保持，文字框按内容重算高度。精确撤销重做及新 Worker 重开通过。相同字体和 144 dpi 下，原件、改后 Canvas/PDF 四组整页对照均为 0/0。LibreOffice 另存保留 RTL、Wingdings 和正文，将标记改写为等价的私用区字符。[LibreOffice 上游用例](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sd/qa/unit/export-tests-ooxml1.cxx#L894-L907)

精确字宽改动曾使原件正文起点左移 0.029 pt。正文和标记共用原生文本框宽度后，原件和四份原生对照的正文起点误差均小于 0.001 pt。最终构建通过全部 237 项登记的 C0 核心检查，C08 四组整页对照继续为 0/0。证据归私有 `nativeC08RtlSymbolBullet.precisePortionRegression`。

C45 原生大纲透视表归私有 `nativeC45OutlinePivot`。原件缓存的紧凑行标题为 `Row Labels`，字段名为 `K`。将源表 `A2` 从 1 改为 11 后，刷新将两组汇总由 5、5 更新为 15、5，总计为 20。样式、修订标识、已识别扩展和 11 个非目标部件保持。53 项核心检查与四条 Chromium 流程通过。LibreOffice 26.8.1.1 用 `K` 显示行标题，原件及改后汇总值均符合独立预期。另存改后文件仍包含原生透视表、缓存定义和记录。[LibreOffice 上游用例](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sc/qa/unit/pivottable_filters_test.cxx#L2577-L2613)

C45 样式证据归私有 `nativeC45PivotStyle`。固定 Carlito 和 144 dpi 时，指定 `A1:B6` 的原件及刷新版各打印一页，四组整页 Canvas/PDF 对照为 0/0。六个采样位置的颜色也与 ONLYOFFICE 一致，覆盖 `D8D8D8` 灰底、白底及 `A5A5A5` 边线。同构建通过 69 项核心检查和六条 Chromium 流程。

C45 整本打印证据归私有 `nativeC45PrintOrigin`。工作簿无适页设置，原比例为 100%。SDK 默认从 `A1` 开始，保留报表前两行空白。ONLYOFFICE 显式使用工作簿比例时，原件和刷新版各三页，12 组整页 Canvas/PDF 对照均为 0/0。同构建通过 82 项核心检查和 11 条 Chromium 流程，其中四条复查 C41 和 C42 的原件及改后整本打印。旧参考沿用转换器的自动适页，整本共两页。该参考的两条整本对照继续失败，首张报表页均为 0/0。[ONLYOFFICE 转换器打印设置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/api.js#L7134-L7159)

C46 隐藏锚点归私有 `nativeC46HiddenAnchors`。固定原件有五个绘图对象。网格为可见图片返回显示区域，重合锚点图片没有显示区域。ONLYOFFICE 原件 PDF 为可见图片绘制有面积的路径，重合锚点只产生空路径。SDK 原件和改后单页 PDF 各包含一张 672 × 581 的图片及其遮罩。检查依据包括 [LibreOffice 原件测试](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sc/qa/unit/subsequent_filters_test4.cxx#L379-L399)。

正常界面输入保留 13 个非目标包部件，包含绘图、关系和两份媒体。工作簿只更新计算标记。撤销和重做精确恢复源文件。新 Worker 重开的改后 PDF 字节一致。ONLYOFFICE 重开改后文件后读出新文字，两张图片的页面操作与原件逐字节相同。37 项定向核心和六条 Chromium 流程通过。该轮使用固定 Arimo 替代。

C46 同字体打印证据归私有 `nativeC46CropSampling`。SDK 和 ONLYOFFICE 都使用系统 Arial、Tahoma、Palatino 和源文件的 80% 缩放。原件和改后文件各打印两页，第二页为空白。合并格边框分段后，两份首页 Canvas 各剩 18 个像素差异。只替换原生 PDF 图片流的无损对照确认，这列像素来自相邻源像素的平均值。打印预览复用缩小采样后，八组整页 Canvas/PDF 对照均为 0/0，两个输入均可逐字节原样保存。一项核心检查与八条 Chromium 流程通过，覆盖原件、改后文件、常规图片编辑及共享图片采样。旧转换器的 78% 适页证据单列。

C46 插列证据归私有 `nativeC46StructureEdit`。首列前插一列后，五个对象的起止列均加一，偏移和尺寸保持，打印区域从 `A1:H34` 移到 `B1:I34`。已识别的 Mac 工作簿和页面视图元数据逐字节保持。含未知引用的扩展仍原子拒绝。37 项核心检查和五条 Chromium 流程通过，覆盖插列、精确历史及新 Worker 重开。ONLYOFFICE 重开保存后的文件，同字体和 80% 比例下两页 Canvas/PDF 四组为 0/0。

C43 手工散点图的错误占位零归私有 `nativeC43ManualScatterErrorGap`。只将 E2 从 `#DIV/0!` 改为数值零的原生控制，在第 5 页绘出 `1 / x` 的首段。原件省略该段。修复后 SDK PDF 曲线起点与原生相差小于 0.001 pt。11 项核心检查通过，包含首点为空、真实零、后续缓存点及原样保存。

C43 全部 15 页仍为 8/30。第 5 页 Canvas 从 7809/8200 降为 6607/6195，PDF 从 7063/7872 降为 5847/5857。其余 28 张 SDK 栅格和全部原生栅格逐字节一致。三条 Chromium 流程通过，覆盖双轴折线、组合图和原件保存重开。新 Worker 导出的 15 页 PDF 字节一致。隔离散点图仍为 Canvas 303/385、PDF 306/404。

C43 第 5 页纵轴标题归私有 `nativeC43ScatterAxisTitleMargin`。独立原生控制只移除前置三维柱图的锚点，两侧标题各向外移动 2.25 pt，纵坐标保持。核心沿用已有打印顺序传入标题留量。旧实现未通过横坐标检查，修复后五项定向核心检查通过。[ONLYOFFICE 轴标题定位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L789-L806)

复跑原件 15 页，第 5 页 Canvas 从 4630/4341 降为 1895/1575，PDF 从 3825/3980 降为 1057/1194。其余 28 张 SDK 栅格和全部原生栅格逐字节相同。双轴折线和原件主图的 Chromium 流程通过，原样保存与新 Worker 重开通过。隔离散点图仍为 Canvas 291/363、PDF 294/380，整表仍为 10/30。

C43 柱线组合图的打印顺序归私有 `nativeC43MixedDrawingOrder`。单独打印或排在柱图前时，原生绘图区底色宽约 508.203 pt。排在三维柱图后时，宽约 505.578 pt。原生第 10 页在组合图先出现的两份控制中逐字节相同。核心复用面积图已有的打印顺序，三份独立尺寸断言通过。严格对照每组还剩 53–55 个底边像素差异。单独调整分类轴线宽或改用等价的描边路径，诊断栅格逐字节相同。

C43 复跑全部 15 页，整表仍为 8/30。第 13 页 Canvas 从 62563/67209 降至 39047/42022，PDF 从 62548/67263 降至 39077/42104。第 14 页 Canvas 从 15462/16999 降至 1515/2144，PDF 从 15463/17021 降至 1515/2154。其余 26 张 SDK 栅格和全部原生栅格逐字节相同。十项核心检查与三条正式 Chromium 流程通过，覆盖组合图、面积图和原件保存重开。

C43 组合图的柱形裁剪归私有 `nativeC43MixedColumnClip`。打印时按原生边界裁剪柱形，随后恢复绘制范围再画坐标轴。三份原生控制的裁剪坐标误差小于 0.001 pt，三项定向核心检查通过。隔离组合图和原件主图的 Canvas/PDF 均为 0/0，保存及新 Worker 重开通过。[ONLYOFFICE 柱形裁剪](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L6488-L6499)

复跑原件全部 15 页，第 13 页 Canvas 和 PDF 各减少 390 个差异像素，第 14 页各减少 53 个。其余 26 张 SDK 栅格及全部冻结参考栅格逐字节相同。整表通过仍为 10/30。

C43 面积图打印顺序归私有 `nativeC43AreaDrawingOrder`。保持两张图的锚点和所有其他部件，仅交换它们在绘图 XML 中的顺序。面积图在柱图前时，原生第 14、15 页与仅面积图版本逐字节相同。柱图在前时，绘图区宽度从 429.663 pt 缩至 425.163 pt。核心按各工作表的可打印锚点顺序计算边距。十项核心检查通过，三份顺序控制的六组第 14 页 Canvas/PDF 对照均为 0/0。

复跑 C43 全部 15 页。第 15 页 Canvas 从 2782/2816 降到 0/0，PDF 从 2770/2831 降到 0/0。第 14 页 Canvas 从 48741/49251 降至 15462/16999，PDF 从 48706/49362 降至 15463/17021。其余 26 张 SDK 栅格和全部原生栅格逐字节相同。整表通过从 6/30 增至 8/30。七条 Chromium 流程通过，覆盖原样保存及新 Worker 重开。隔离透视柱图仍为 Canvas 0/130、PDF 0/125。

C43 字形裁剪归私有 `nativeGlyphRectangleClip`。字面 PDF 控制在同一半像素边界保留整列字形像素，矢量边缘仍有部分覆盖。PDF Canvas 复用矩形裁剪范围，按绘制类型选择整像素或分数边界。嵌套裁剪回归先失败，修复后通过。

复跑 C43 全部 15 页。第 2 页 Canvas 从 4/0 降到 0/0，整页通过从 5/30 增至 6/30。第 3、9 页保持通过。其余仍失败的 Canvas 页单向计数最多增加七点，原生栅格与 SDK PDF 逐字节一致。17 条 Chromium 流程通过，覆盖 C41、C42、C46 的原件及改后整本打印。C17 复查仍为 27/28，仅未旋转第 11 页为 0/8。

C43 手工饼图的错误占位零归私有 `nativeC43ManualPieErrorGap`。只把 E2 的 `#DIV/0!` 改成数值零，固定原生参考的首项图例从深蓝无字变为带红边的浅紫色块和 `1`。核心将已知源错误对应的缓存零绘为空点，保留源错误和图表缓存。原件断言先失败，修复后十项定向核心通过。六条 Chromium 流程通过，两条隔离的饼图及圆环图严格视觉仍失败。原件可原样保存，新 Worker 的 15 页 PDF 逐字节一致。

复跑全部 15 页，整页对照从 4/30 增至 5/30。第 2 页 PDF 从 196/311 降到 0/0，Canvas 从 200/311 降到 4/0。四点位于折线图文字和打印左边界的交界。第 8 页两组差异也减少，其余 26 张 SDK 栅格与全部原生栅格逐字节相同。仍有 25 组整页对照未通过。

C43 短图框的堆积条图证据归私有 `nativeC43ShortBarLabels`。两份独立控制保留原始 528 × 267.75 pt 锚点，仅增删前置三维柱图。两份原生页面逐字节相同，横条内部像素与冻结第 10 页一致。旧实现的纵坐标最大偏差为 2.731 pt。按两次标签留量调整后，26 个可见面与原生坐标相差不足 0.001 pt。57 项核心检查通过。混合图的既有测试同时检查源缓存零和绘制空点。

C43 复跑全部 15 页，仍为 4/30。第 10 页 Canvas 从 314260/316807 降为 244658/247154，PDF 从 314217/316940 降为 244593/247269。第 11 页两组对照也减少。其余 26 张 SDK 栅格与全部原生栅格逐字节一致。堆积条图、柱线混合图和原工作簿的三条 Chromium 流程通过。原件可原样保存，新 Worker 的 15 页 PDF 逐字节一致。整份工作表的严格视觉仍失败。

三维堆积面积的首点分歧已用独立控制复现。只将 E2 置空，原生 PDF 的页面操作流与 E2 为 `#DIV/0!` 时逐字节相同，整组黄色面都省略。E2 为数值零时，将 E3 置空或改为同类错误，原生仍绘制 25 个黄色面，两份操作流一致。控制均保留图表缓存及其他包部件。该批 SDK 仍显示有效黄色面；当前已按用户选择跟随主引擎，结果见上方三维堆积面积批次。原件、参考与严格断言保持。

C43 手工折线图的错误占位零归私有 `nativeC43ManualLineErrorGap`。固定原生控制只把源单元格 E2 从 `#DIV/0!` 改成数值零，图表缓存和其他包部件逐字节一致。错误版本的青色折线从第二点开始，数值零版本保留第一段。核心绘制按源值类型区分两者，保存保留图表缓存与源错误。旧实现的点值断言先失败，修复后 28 项定向核心和两条正式 Chromium 流程通过。原件原样保存，新 Worker 导出的 15 页 PDF 字节一致。

原件 15 页的严格对照仍为 4/30。第 1 页 Canvas 从 48/899 降为 45/349，PDF 从 51/903 降为 48/344。第 13 页的柱线混合图也引用同一源错误。该页 Canvas 从 64302/69672 降为 62565/67204，PDF 从 64282/69727 降为 62548/67263。其他 26 张输出栅格和全部原生栅格逐字节一致。仍有 26 组未通过严格对照。

C43 趋势线方程换行归私有 `nativeC43TrendLabelWrap`。固定原生 PDF 的 672 pt 图框将方程末项单独排一行。旧实现把整个方程排在同一行。修复后三行原点与原生相差均小于 0.001 pt，原有宽图框坐标检查通过。两批共十项定向核心检查通过。独立双轴折线和原工作簿的 Chromium 用例通过，主图 Canvas/PDF 均为 0/0。原样保存通过，新 Worker 导出的 15 页 PDF 逐字节一致。

整页对照复跑 15 页，仍为 4/30。相较前一构建，第 1 页 Canvas 从 764/2444 降为 48/899，PDF 从 774/2458 降为 51/903。第 2 页 Canvas 从 6454/5416 降为 200/311，PDF 从 6411/5356 降为 196/311。第 3、9 页继续通过。另有九页 Canvas 的计数随构建变化。只有第 1、2 页 PDF 栅格发生变化。全部原生栅格逐字节一致，18 个图表可读，原样保存通过。第 6 页的 Canvas 77/102、PDF 78/103 全部集中在散点图图例的黄色三角。源系列声明该标记，固定主参考在图例中省略了它。

C13 第 28 页复核归私有 `nativeC13P28PdfTextAdvance`。原件对固定整页参考为 Canvas 3070/3749、PDF 3048/3665。仅移除 WMF 双色效果的控制为 Canvas 92/123、PDF 97/226。两条流程都通过原生输入、精确历史、单元格属性、282 个非目标部件及新 Worker 重开。各三次 PDF 导出成功，布局诊断为空。四组严格视觉对照仍失败。

两行 Carlito 正文的 17 个词，按固定 ONLYOFFICE 的 PDF 字宽取整和相邻字形合批复算，横坐标最大误差为 0.002 pt。Arial 页脚一行的 16 个词最大误差为 0.005 pt。SDK PDF 中这 33 个词与未取整的源字体推进相差不足 0.000001 pt。主参考的 WMF 图标仍缺少源双色效果。复算只解释所测文字的 PDF 位置，原件仍需通过固定整页参考。[字宽取整](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/SrcWriter/FontCidTT.cpp#L543-L550)、[字形合批](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/SrcWriter/Pages.cpp#L1754-L1780)。

在原始色 WMF 控制的 SDK PDF 副本中重放这两条规则，正文从 96/99 降为 0/0。页脚文字两次均为 0/0。整页剩下的 1/127 全在图标内。原生 PDF 将 WMF 存成 196 × 226 的 JPEG 和透明遮罩，SDK 保留矢量。正式整页仍失败，SDK PDF 继续沿用预览的字形位置。

用固定 ONLYOFFICE 转换 C13 原件两次，截取第 28 页写入 PDF 前的绘图指令。两份指令逐字节相同。两次输出在 144 dpi 下均与冻结栅格逐字节相同。同一批 33 个词的横坐标，SDK PDF 距原生绘图指令最多 0.006 pt，原生 PDF 最多 0.160 pt。以原生的 1/16384 mm 网格截断每个字形的推进量，可将三行 152 个可见字形的最大复算误差降至 0.0004 pt。该排版精度与 PDF 写出偏差分别记录于 `nativeC13P28PdfTextAdvance.prePdfMetafile`。

C13 第 28 页的精确字宽归私有 `nativeC13P28PrecisePortions`。演示稿文本框不再采用 Writer 的整数 twip 字宽。旧版居中表头向右偏 0.023 pt，紧接粗体的短横线向左偏 0.045 pt。两处修复后都与原生绘图指令相差小于 0.001 pt，四项表格核心测试通过。

C13 第 28 页的 WMF 裁剪归私有 `nativeC13WmfCrop`。原件编辑只改 `a:srcRect`，其余幻灯片 XML 和包部件逐字节相同。核心测试核对保存、精确撤销重做、重开及空裁剪原子拒绝。Chromium 从默认控件裁去合成 WMF 的左、上各 25%，Canvas/PDF 对独立字面 PDF 均为 0/0。五项核心和三条浏览器流程通过。原色组件流程仍失败，四张 SDK 组件栅格和参考与该流程的前批逐字节相同。

两条第 28 页浏览器流程均通过输入、精确历史、源保留和新 Worker 重开。对同一固定参考，原件为 Canvas 3100/3804、PDF 3078/3716，去除双色效果的控制为 Canvas 122/178、PDF 127/277。整稿仍为 78/96，改后仍为 5/6。102 张参考栅格逐字节相同，只有第 28 页的差异计数变化。C08 的 RTL 项目符号与 C39 的 DOCX 链接框浏览器回归通过。

第 28 页的直接 PNG 边框复核归私有 `nativeC13P28TableBorderSampling`。表格区 6,528 个原生 PNG 侧差异中，4,512 个位于两条一磅横边的四条灰色像素行。只向下移动表格 0.25 和 0.5 pt 后，原生 PDF 保留相同的边框宽度及局部坐标。三组对照的 PNG 灰度按像素覆盖率复算，最大误差为一级。PDF 栅格按边界取整，216 个采样点逐值一致。这些边框差异属于输出路径，正式第 28 页的文字和图标差异仍开放。

第 28 页的双色参考诊断归私有 `nativeC13P28DuotoneCandidate`。ONLYOFFICE 的直接 PNG 和 PDF 均省略源双色效果。LibreOffice 与 App 的图标区域为 0/0，整页仍有 15877/23658 差异。

诊断只把固定 PDF 图标的 RGB 和 Alpha 换成 LibreOffice 的原生流。原生位置、图案变换和页面内容流逐字节相同，图标框外的像素逐值相同。SDK Canvas 对候选为 187/190，PDF 为 208/219。两组余差都在图标和表格正文。候选与 App 的图标区域为 0/0。正式参考继续冻结。

第 28 页矢量与文字位置候选归私有 `nativeC13P28VectorPageCandidate`。先用 LibreOffice 从原始 WMF 导出的独立矢量替换原生 PDF 的图标绘制。双色沿用独立原生 PNG 验证过的三种颜色。两份参考的图标框外像素逐值一致，原色和双色的 Canvas/PDF 图标区域均为 0/0。此时两份整页 Canvas 均为 122/152，PDF 均为 126/150。

再按固定 ONLYOFFICE 写入 PDF 前的绘图指令恢复 1,740 个字形的横坐标。56 条文字显示指令按原字体、字号、基线和字符顺序逐一匹配，九个旋转字形沿用原指令。两份候选的其他 PDF 对象相同，提取文字去除空白后相同。四组整页 Canvas/PDF 均为 0/0，四张 SDK 栅格的哈希与正常复跑一致。原生输入、282 个非目标部件、精确历史和新 Worker 重开通过。两条正式用例仍沿用冻结参考。

整稿联合复跑归私有 `nativeC13IntegratedReferenceCandidate`。第 3、15 页的 Canvas 使用原生直接 PNG，第 36 页的 Canvas 使用独立照片合成参考，第 28 页两种输出使用双色矢量与文字位置候选。其余沿用 SmartArt 和 GIF 联合候选。48 页原稿 96 组、三页编辑后六组整页对照均为 0/0。48 份 SDK PDF 和 102 张 SDK 栅格与最近的冻结参考复跑逐字节一致。原生输入、精确历史和新 Worker 重开通过。正式参考继续冻结，最近正式结果为原稿 78/96、改后 5/6。

当前发行构建复跑整稿、圆角标注、SmartArt、两条表格用例和 WMF 组件。六条 Chromium 用例在候选参考下通过，合计 130 组均为 0/0。整稿的 48 份 SDK PDF 和 102 张 SDK 栅格均与冻结参考复跑逐字节相同。候选在整稿中只改变 21 份参考栅格。候选结果和正式结果分开登记。

切换前的图表构建复验六条 C13 候选流程，130 组对照均为 0/0，额外的共享 WMF 填充回归也通过。运行前后核对六份独立候选资产哈希。整稿的 102 张 SDK 栅格、102 张参考栅格和 48 份 SDK PDF 与前批候选复跑逐字节相同，28 条组件比较记录也相同。证据归私有 `nativeC13IntegratedReferenceCandidate.currentReplay`，保留当时的冻结失败。

2026-11-07，经用户批准，完整独立参考已成为正式参考。九份带哈希的资产保存在私有 `cases/c0-pptx-c13/`，正式用例直接读取。包括原图 RGB、原生透明组及已核验的屏幕、矢量和照片采样路线。SDK 输出和比较阈值保持。根目录运行 `moon run test-lab/tools/c0-c13-reference.mbtx` 可核对全部资产、原件身份和 PDF 结构。

正式复跑七条 Chromium 用例全部通过。六条 C13 流程包含原稿 96 组、三页修改后六组及组件 28 组，130 组严格比较均为 0/0；另含一条共享 WMF 填充回归。源输入、282 个非目标部件、精确历史和新 Worker 重开通过。整稿的 102 条比较记录及 48 份 SDK PDF 与获批候选相同。结果归私有 `nativeC13ApprovedReference`。C43 与 C17 仍按各自未完成状态记录。

当前构建已复跑 `test:c0-pptx` 的全部 28 项登记测试，15 份测试文件分三组执行，全部通过。覆盖该批 16 份固定 PPTX 原件的登记显示、编辑、保存与重开操作，以及大小写、阴影和 WMF 填充控制。每组前后核对临时用量，测试源码及构建哈希保持。C13 子集的 130 组比较均为 0/0；整稿 102 条比较记录与 48 份 SDK PDF 复现获批正式批次。结果归私有 `nativePptxRegisteredSuiteCurrent`，资格限定于这些原件与操作。

固定 ONLYOFFICE 和 LibreOffice 分别计算第 28 页的双色端点。源色 `4F81BD` 依次应用 `shade=45000` 和 `satMod=135000` 后，ONLYOFFICE 得到 `275791`，与 SDK 相同。LibreOffice 得到 `295A93`，与其原生图标相同。把 ONLYOFFICE 端点预先写入临时 WMF 画笔和画刷后，SDK 的双色 Canvas 对原生直接 PNG 为 0/0。[ONLYOFFICE 颜色变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L2225-L2284)

原色 WMF 的候选从 LibreOffice 导出的 12 条矢量路径生成 PDF，沿用原图框位置和尺寸。在保留图框外两像素的独立对照中，原色 Canvas、SDK PDF 和 ONLYOFFICE 直接 PNG 对该候选均为 0/0。冻结 ONLYOFFICE PDF 使用 196×226 的 JPEG 图标。证据归私有 `nativeC13P28DuotoneCandidate.sourcePaletteAndVector`。

Chromium 按正式用例的原 96×112 裁图和容差复跑。候选原色 Canvas/PDF 均为 0/0，双色的 GenOffice 对照也均为 0/0。四张 SDK 栅格与正式批次逐字节相同。候选待确认，整页表格继续按原参考验收。

模拟粗体遮罩细化归私有 `nativeRefinedGlyphCornerCoverage`。独立字形角点的红通道从 147 降至原生的 89。15 份独立字面 PDF 控制在三种 Canvas 模式下共 45 组为 0/0。九项定向浏览器测试通过，覆盖曲线、相接轮廓、原有预算回退、图片颜色面及后续绘制。

C13 正常构建复跑全部 48 页，整页对照从 73 增至 74/96。仅第 32 页 Canvas 的差异计数发生变化，从 3/0 降为 0/0。前批通过的 73 组全部保持。48 份 SDK PDF、SDK PDF 栅格及原生参考栅格逐字节相同，48 次导出、无布局诊断及原样保存检查通过。仍有 12 页共 22 组差异。

第 45 页正式整页对照及编辑通过。正文效果的 30 组正式对照从 24 增至 25 组为 0/0，新增第 32 页原稿 Canvas。原生输入、282 个非目标部件、精确历史和新 Worker 重开通过。首个严格失败仍为第 15 页 Canvas 3/1。

八条跨格式回归最终七条通过。C10 首轮在 LibreOffice 保存重开时退出，使用同版转换器单独复跑后四组整页均为 0/0，保存字节和参考栅格相同。C17 全部 28 组栅格与前批逐字节相同，仍为 27/28。C43 主图 Canvas/PDF 为 0/0，完整 15 页 PDF 与前批及重开后逐字节相同。本轮未重跑 C43 的 30 组整页视觉对照。正常构建、私有类型、定向 lint 和格式通过。

第 42 页四个余差来自 12×12 GIF 项目符号。两张项目符号的原生 PDF 遮罩与源 GIF 的 Alpha 逐字节相同。两张原生颜色流均为 JPEG，12×12 图的原始不透明色与原生解码最大相差 117 级。独立候选保留遮罩和几何，只恢复原始颜色。当前 Canvas 对固定 PDF 仍为 0/4，对无损候选为 0/0，对原生直接 PNG 为 195/77，前批为 185/68。三种图片采样候选均未使固定对照通过。原件、参考和断言按各自用途保留。

PPTX 下划线的证据归私有 `nativePptxUnderlineDescent`。独立 Arial 控制与原件 Carlito 超链接核对四条原生 PDF 描边中心。旧实现复现位置误差，复用演示文稿行下降部后，19 项定向核心检查通过。范围覆盖共享装饰、文本框、表格及超链接。

下划线批次复跑 C13 全部 48 页。严格整页对照从 68 增至 73/96，第 31、38 页 Canvas/PDF 和第 32 页 PDF 新增通过。第 32 页 Canvas 从 6/0 降为 3/0。前批通过的 68 组全部保持，原生参考逐字节相同。48 次导出成功，布局诊断为空，原样保存通过。

下划线批次的第 45 页正式用例通过。当批正文效果的 30 组正式对照从 23 增至 24 组为 0/0。原生输入、282 个非目标部件、精确历史及重开通过。另四条 Chromium 回归通过，覆盖 PPTX 文本框和表格超链接、DOCX 超链接及 XLSX 单元格装饰。正常构建、加载私有测试后的严格检查、类型、格式及接口生成通过。

曲线描边覆盖的正式证据归私有 `nativeFilledCurveCoverage`。同一展开轮廓在普通 Canvas 填充下丢失急角重叠处的覆盖。复用有界 4×4 遮罩后，独立曲线的四档相位及反射共 16 组整页对照为 0/0。选定急角像素与原生逐值相同。九项定向浏览器测试通过，覆盖既有多边形、描边预算、裁剪与图片采样。

曲线描边批次将 C13 的 96 组原稿对照从 67 增至 68 组为 0/0。第 6 页 Canvas 从 3/0 降为 0/0，第 15 页从 19/1 降为 3/1，第 36 页从 1681/393 降为 1678/393。当批 48 份 SDK PDF、SDK 栅格及原生参考栅格与前批逐字节一致，全部导出成功，布局诊断为空，原样保存通过。

曲线描边批次的第 45 页正式整页对照、背景编辑、精确历史及新 Worker 重开通过。当批正文效果的 30 组正式对照中，23 组为 0/0，仅第 15 页原稿 Canvas 栅格有变化。原生输入、282 个非目标部件、精确历史及重开通过。

第 15 页照片采样诊断归私有 `nativeC13PhotoSamplingRoutes`。在固定原生 PDF 和无损颜色候选中，四个余差点均由照片决定。分离阴影和描边后，四点保持相同。按 Poppler 的整数图像边界和双线性取样复算，无损候选照片内部 868210 点逐像素一致。

正常 Canvas 对固定 PDF 为 3/1，对无损 PDF 候选为 3/0，对 ONLYOFFICE 直接 PNG 为 0/0。单独调整裁剪方式仍为相同计数。照片按整数设备边界绘制的两项候选使两份 PDF 对照为 0/0，但直接 PNG 分别变为 3/5 和 4/6。四种浏览器绘制均完成整页对照和原样保存。正式验收仍使用固定参考，照片试验仅用于区分两条原生输出路线。

曲线描边批次的八条跨格式回归中七条通过，覆盖 C10 环形图、C33 PDF 标注、C43 原件和四个圆形标签控制。C17 保持 27/28，第 11 页未旋转时仍为 0/8。28 组 SDK 和原生栅格身份与前批相同。C43 主图 Canvas/PDF 为 0/0，完整 15 页 PDF 与前批和重开后逐字节相同。当批未重跑 C43 全部 30 组整页视觉对照。正常构建、私有类型、定向 lint 及格式通过，未跑全仓。

PPTX 模拟粗体的文字批次证据归私有 `nativePptxBoldPenBatches`。15 个原生控制覆盖升降字号、换行、段落、颜色、真实粗体、装饰及表格单元格。原生在同一批连续模拟粗体中沿用首个宽度，遇到普通字形、真实粗体或独立图形时按批次重置。旧版核心测试复现 0.343 pt 与 0.57167 pt 的差异。修复后 26 项定向核心测试和绘图参数边界检查通过。

C13 正常构建复跑 48 页原稿，96 组对照从 66 增至 67 组为 0/0。第 6 页 Canvas 从 5/0 降至 3/0，PDF 从 1/0 降至 0/0。第 6、36 页的 PDF 字节发生变化。全部原生参考栅格逐字节相同，48 次导出成功，布局诊断为空，原样保存通过。仍有 16 页共 29 组差异。

模拟粗体批次复跑时，第 45 页原件的整页对照、背景编辑、精确历史和新 Worker 重开通过。正文效果用例完成原生输入、精确历史、源保留与重开。当批全部 30 张对照栅格与前批逐字节一致，23 组为 0/0，首个严格失败在第 15 页。

模拟粗体的曲线分段证据归私有 `nativeGlyphCurveFlattening`。第 46 页的原生数字分层诊断在差异位置得到填充灰度 251、描边灰度 24。Canvas 旧值分别为 255 和 129。按 Poppler 的设备像素容差分段后，Canvas 描边灰度为 24。14 个独立嵌入字体文字控制覆盖三种画布策略，42 组整页均为 0/0。半像素两侧灰度均保持 165。八项定向浏览器测试通过，包含原有状态、预算和图片采样检查。

C13 全部 48 页原稿在正常界面复跑。96 组严格对照从 64 增至 66 组为 0/0，前批 64 组全部通过。第 34、46 页的 Canvas 新增通过。第 6 页 Canvas 从 3/0 增至 5/0，新增点为 (709,916) 和 (420,918)。仍有 16 页共 30 组差异。48 份 SDK PDF、PDF 栅格和原生参考栅格逐字节一致。布局诊断均为空，48 次导出成功，原样保存通过。

前批采样证据归私有 `nativeBoldGlyphCoverage`。第 45 页正常构建的 Canvas 从 1/0 降为 0/0，PDF 为 0/0。背景编辑、精确历史、282 个非目标部件及新 Worker 重开通过。前批 39 组原生文字对照、12 个预算及回退控制通过。独立预算压力控制确认字形预算耗尽后仍可采样图片颜色面。

十二页原稿和三页编辑后的 30 组正式对照从 22 增至 23 组 0/0。编辑后的第 20 页 Canvas 从 1/0 降为 0/0。原生输入、非目标部件、精确历史和新 Worker 重开通过。第 15 页 Canvas 仍为 19/1，严格用例失败。第 45 页独立用例和 C43 工作簿流程通过，后者的完整 15 页 PDF 与前批逐字节一致。DOCX 两份原件及改后布局没有模拟粗体描边，沿用前批结果。四字体 C43 整稿沿用前批 4/30 资格。正常构建、私有类型、定向 lint 和格式通过。

前批第 6 页修正了 Grade 文字的模拟粗体宽度。其后余下三点位于标注的白色斜描边。原生的完整轮廓和相接斜边均覆盖三点，共用曲线描边助手的普通填充则得到红通道 141、123、105。相同轮廓经 4×4 采样，在三个点均完全覆盖。

修复前的诊断归 `nativeBoldGlyphCoverageProbe`。第 45 页余差位于 Writing 的第二个 i 字干角点：SDK 灰度为 105，原生邻域只有黑白，超出 96 级颜色容差。隔离采样复现了修复方向，正式实现沿用原字形和布局，只调整描边覆盖。候选使用的 SVG DOM 边界测量未进入产品。

Office 放大图案采样的当前证据归私有 `nativeOfficeHatchSampling`。普通画布现始终平滑采样，PDF 策略保留放大像素单元和缩小平均规则。修改只增加既有模式判断，没有改变核心、图案周期、坐标、源文件或公共接口。三份独立 Letter 控制覆盖两种点纹、砖纹和两种分辨率。六组完整原生 PNG 比较均为 0/0，源字节保持；修改前两组高倍率点纹分别为 51638/37482、25782/18780。

正常构建、严格类型、lint、格式和源码上限通过。十二条浏览器流程中十条通过，两条原始圆形严格用例仍失败。既有 PDF 像素单元、嵌套变换、裁剪、缩小采样及四页 PDF 原点控制通过。原饼图和圆环图的 Canvas/PDF 与前批逐字节相同，C43 正常原件及新 Worker 的完整十五页 PDF 保持相同字节。本批未重跑 C43 全部三十组，PDF 策略和 Wasm 保持，沿前批完整比较读取；未跑完整 C13/C17 或全仓。

A4 两倍输出的 185/188、87/91 余差已定位为网格密度不同。原生把纸张映射到整数 PNG 宽高，普通预览采用固定像素倍率。诊断仅按原生纸面像素网格绘制未改的 Worker 批次，三种底纹的完整 A4 比较均为 0/0。正常预览几何、A4 固定倍率诊断和原始 PDF 参考保持，未用该诊断替换原件验收。参考代码与完整身份归上述私有记录。C0 尚未通过。

图案采样诊断归私有 `nativeOfficePatternSamplingDiagnostic`。三份字面空图表控制覆盖两种点纹、对角砖纹及两倍、三倍分辨率，源字节保持。打印预览采用 PDF 策略，只改普通画布的候选没有改变六张输出。隔离的全模式平滑试验使三倍分辨率两种点纹从 48256/36060、24257/18068 降为 0/0，砖纹保持零差异；两倍点纹仍为 185/188、87/91。六组中四组通过，两组失败。本批没有修改产品或正式参考，既有 PDF 像素合同仍待独立复核，未授予原件资格。初次选错工作表及视口超出资源预算的准备失败保留，重复栅格和已结束的编译缓存按长期授权清理。C0 尚未通过。

右到左绘图打印的当前证据归私有 `nativeRtlDrawingPrint`。绘图以纸张宽度作镜像基准，裁剪端点先沿原逻辑轴量化，再镜像。修改前冻结的十二份原生控制覆盖两个方向、左右不等边距互换及 50%/100%/150% 比例。显式 A1:B8 区域有意裁切第三个矩形，三种锚点的源位置与尺寸保持。正常打印预览 Canvas 和完整 PDF 的 24 组对照均为 0/0。修正前六份右到左控制的十二组比较均失败，六份左到右控制保持零差异。

十三项定向核心检查通过，包含独立原生变换坐标、镜像后的裁剪、源字节与查询状态，以及打印区域、重复标题和整本打印保护。公共接口、正常构建、严格类型、lint、格式与源码上限通过。原生自动选择绘图打印范围仍可能裁掉有效源内容，自动范围诊断继续单列；显式区域的通过不授予该路线资格。

九条既有界面流程通过，包含页面设置、区域与重复标题、整本打印、图片、形状及 C43 原件。C43 主图 Canvas/PDF 保持 0/0，18 个图表、源保存和新 Worker 保持。完整 15 页工作表 PDF 与前批逐字节相同，重开后也相同。本批未重跑 C43 全部 30 组图像比较，沿前批 `nativePatternOriginPrecision` 的四组零差异和 26 组失败读取。自动范围的三份右到左原生 PNG 与显式 A1:B8 参考逐字节相同；SDK 保留被其额外裁掉的蓝色矩形部分，六组严格比较继续失败。未跑全仓或完整 C13/C17；C0 尚未通过。

前批 PDF 图案原点证据归私有 `nativePatternOriginPrecision`。核心写出图案原点时保留五位小数，变换基向量保持布局精度。独立字面 PDF 的四页平移、剪切、反射与旋转控制均为 0/0。七项核心和十一条图案、圆形与不同边距流程通过；原件默认操作及新 Worker 另有一条通过。

原饼图的六个新增缺点已消除，完整 PDF 从 6/4493 恢复为 0/4488，源中有效的底纹仍保留。原圆环 PDF 保持 0/0。两张屏幕 PNG 与前批逐字节相同，原始严格用例继续失败。六个点实际位于黄色图案图例标记，前批“字形余差”的归因已纠正。单独套用原生矩阵或调整纸张高度未消除这些点；诊断与失败均保留，正式参考和容差保持。

本批已复跑 C43 全部 15 页、30 组严格对照。所有差异计数与前批相同，第 3、9 页 Canvas/PDF 为 0/0，其余 26 组失败。15 张 Canvas 和 14 张 PDF PNG 逐字节保持；第 5 页 PDF 的 PNG 有变化，计数仍为 7063/7872。正常默认流程与新 Worker 导出的 15 页 PDF 字节相同，源保存保持。正常构建、所属包严格检查、公共接口、类型、lint、格式和源码上限通过。未跑全仓或完整 C13/C17；C0 尚未通过。

前批图表页打印原点证据归私有 `nativeChartSheetPrintOriginPrecision`。物理坐标现按原生元文件向零截断到十万分之一毫米。修改前冻结的四份控制只改变页边距，覆盖两种拟合比例；正常预览可显示，原样保存保持，完整 SDK PDF 的四组对照均为 0/0。基础控制修正前为 129/0，另外三组保持零差异。核心另核对独立原生 PDF 的变换坐标，十项定向检查通过。

原圆环图 PDF 从 129/0 降为 0/0；两张圆形图的屏幕 PNG 与前批逐字节相同。原饼图继续保留原生漏画的源底纹，PDF 从 0/4488 变为 6/4493，新增少量图例字形余差完整保留。两条原始严格用例均仍失败。C43 主图 Canvas/PDF 保持 0/0，18 个图表目录、原样保存及新 Worker 保持。正常工作表的完整 15 页 PDF 与前批逐字节相同；其前批全部 30 组比较继续按明确构建读取，第 3、9 页为零，其余 26 组失败。本批未重新授予整稿 Canvas 资格。

14 条既有图表流程全部通过，覆盖面积图、原尺寸工作表打印、32 系列上限、三维条图、双轴折线、混合图、雷达、曲面及四份圆形文字控制。正常构建、所属包严格检查、公共接口保持、私有类型、lint、格式及源码上限通过。本批只修改 XLSX 图表页打印原点。四份新控制只授予完整 PDF 资格，打印预览 PNG 留作诊断；屏幕与 PDF 的纹理周期差异继续开放。未跑全仓或完整 C13/C17；C0 尚未通过。

前批圆形文字边距证据归私有 `nativeCircularTextInsets`。数据标签现保留原生一毫米内容留量，并逐行居中。标题计入正文边距，顶部按七个 96 dpi 像素计算。修改前冻结的四份字面 XML 控制包含饼图、双圈圆环、单行百分比和多行分类标签，使用不同常规/粗体字号与标题。相同 Arimo 字节下，正常打印预览 Canvas 与完整 SDK PDF 的八组对照均为 0/0。十二个原生水平文字起点和四个标题基线另有核心检查，修正前失败，修正后通过。

主批 28 项核心检查通过；复合饼图补查的五项中有三项重叠，合计 30 项不同核心检查。正常原件流程保持主图、18 个工作表图表、15 页打印、原样保存和新 Worker 的相同 PDF。两条原始圆形严格用例仍失败：饼图 Canvas 从 232/4972 降为 2/4765，PDF 从 227/4693 降为 0/4488；圆环 Canvas 从 11978/10234 降为 11550/9901，PDF 从 540/319 降为 129/0。逐点审计确认，圆环 PDF 的全部 129 点都在 y=108 的顶部底纹边缘，以七像素周期重复。完整直接原生 PNG 诊断仍保留，未替换正式 PDF 参考。原生漏画的饼图底纹继续保留源内容。

C43 全部 30 组严格对照已复跑，第 3、9 页 Canvas/PDF 保持 0/0，其他 26 组仍失败。第 5、8 页 Canvas/PDF 计数均有所增加，完整结果保留，未用错误文字位置抵消原生跨图表状态差异。本批只修改 XLSX 圆形绘制；宿主渲染器和公共接口保持。正常构建、严格检查、类型、lint、格式、链接及源码上限通过。未跑全仓或完整 C13/C17；其他格式沿各自明确构建的证据读取。准备错误、标题基线失败、容量守卫及原始严格失败均保留，可重建缓存和与当前逐字节相同的重复栅格已清理。C0 尚未通过。

前批填充多边形描边证据归私有 `nativeFilledPolygonStroke`。PDF 策略复用既有描边轮廓和 4×4 覆盖遮罩，保留仅触及边界的子像素。修改产品前冻结的 16 份独立字面 PDF，覆盖四种相位、显式闭合、返回起点和相邻色带。当批正常产品全部为 0/0。初版遮罩在四个角点失败的证据保留，最终规则没有平移几何或放宽容差。

菱形回归归私有 `nativeFilledPolygonStroke.diamondOracle`。210 组中，185 组仍逐像素比较。其余 25 组用同一几何、颜色和透明度生成字面 PDF，以固定 Poppler 栅格比较 RGB 总误差。每组误差均低于浏览器直接描边，诊断中 25 组的颜色覆盖均为 0/0。停用 PDF 多边形描边时，新断言复现失败。14 条共享绘制和 5 条 C43 面积图 Chromium 用例通过。产品渲染和真实文件参考沿用同一构建。

原始 528 × 293.25 pt 图框的仅面积图控制，正常 Worker 整页 Canvas 从 0/63 降为 0/0，PDF 保持 0/0。15 页输出及原样保存保持。该页正常预览在本机 Chromium 中实测约 0.5 秒；修改前同一流程约 1 ms，覆盖遮罩增加绘制成本。十条绘制流程和三条面积图流程通过，包含独立多边形、耗尽共享资源预算后的精确回退、父层资源、七种不适用描边样式、曲线、圆头虚线、裁剪和遮罩。C43 全部 30 组严格对照已执行，第 3、9 页 Canvas/PDF 保持 0/0，其余 26 组仍失败。第 5、8 页 Canvas 的差异计数有所增加，完整结果保留；15 页 PDF 及全部 PDF 栅格逐字节保持。完整 C0 尚未通过。

最终构建的四格式回归为 34 条通过、一条失败。C17 仍为第 11 页未旋转的 0/8，其余 27 组为 0/0；全部 SDK 和原生 PNG 身份与前批相同。图表补查为七条通过、两条失败，范围包含堆积条图、双轴折线、组合图、雷达和曲面。饼图与圆环图仍失败；正常流程替换为修改前的两个渲染模块后，两图 Canvas、PDF 和参考 PNG 均逐字节相同。原有失败未授予资格。Wasm 保持，复用前批 32 项核心结果。正常构建、严格类型、lint、格式、链接与源码上限通过，未跑全仓及完整 C13。可重建脚本缓存已按授权清理，源快照、独立参考和失败证据保持。

前批面积图 Canvas 裁剪证据归私有 `nativeAreaCanvasClip`。PDF 策略的矩形命令复用已有矩形路径覆盖规则。当批原始尺寸面积图的 Canvas 从 2/119 降为 0/63，PDF 保持 0/0。正常 Worker 的 PNG 与修改前隔离裁剪试验逐字节相同。全量像素审计及逐次绘制追踪保留；当批 63 个余差全部位于三条色带描边覆盖行。

248 组绘制检查通过，涵盖两种等价裁剪命令、渐变、变换、小范围、零面积、透明度和后续状态。旧页面边界用例的 PDF 预期先由四份独立字面 PDF 核对，再保留 24 组精确像素断言；平移的实心填充预期同时扣除了重复的边缘混色。原始失败和全部 24 组像素明细保留。四格式回归首轮为 32 条通过、两条失败；边界预期校正后通过，C17 继续保持第 11 页未旋转的 0/8，其余 27 组通过。未推广待定参考或改变容差。

C43 全部 30 组对照再次执行，第 3、9 页 Canvas/PDF 保持 0/0，其余 26 组仍失败。第 14 页 Canvas 为 48798/50360，较前批增加；原生跨图表边距状态差异继续保留，未用错误裁剪抵消它。全部 PDF 栅格及完整 15 页 PDF 与前批逐字节相同。原样保存和新 Worker 保持。Wasm 未变，复用前批 32 项核心结果；本批正常构建、严格类型、lint、格式、链接及源码上限通过。可重建临时安装依赖已清理，源、清单和证据保持。未跑全仓或完整 C13，C0 尚未通过。

前批工作表绘图打印裁剪证据归私有 `nativeWorksheetDrawingClip`。核心先按 96 dpi 量化绘图裁剪端点，再保留原生元文件的十万分之一毫米截断。缩放后的物理边界参与计算。单元格裁剪、源锚点、对象位置和宿主渲染器保持。三种缩放的独立原生 PDF 端点新增核心回归，修改前失败，修改后通过。

32 项核心和十九条正常界面流程通过。范围包含 C41/C42 原件及编辑后全部页面、C43 主图、固定图框面积图、系列容量、图片与裁剪、重复标题、整本打印、形状、切片器及时间线。三种缩放的左到右整页 Canvas/PDF 六组保持 0/0；双向诊断的十二组全部执行，六组右到左仍失败，计数与前批相同。公共接口、正常构建、严格检查和格式通过。

原始尺寸的仅面积图控制，完整第 14 页 PDF 从 164/0 降为 0/0；Canvas 从 150/119 降为 2/119。附带三维柱图的控制仍受原生共享边距状态影响，四组严格比较完整保留。C43 原件全部 15 页、30 组比较已复跑。第 9 页 Canvas/PDF 首次均为 0/0，第 3 页保持 0/0，其余 26 组仍失败。18 个图表、原样保存和新 Worker 的完整 15 页 PDF 保持。各页差异及两个独立流程的 PDF 身份均归私有记录，未将页数相同当作视觉通过。

旧构建的二进制与 CMake 编译缓存已按授权清理，当前必要基线、原生参考、补丁源码、可执行文件和紧凑失败证据保留。完整 C43/C0 尚未通过，未跑全仓。下一步继续核对原始尺寸面积图的 Canvas 边界；原生跨图表状态、右到左定位及 C13/C17 的参考决定仍保持。

四格式兼容状态、历史证据强度和上游测试方式统一见[文件兼容性矩阵](compatibility.md)，补齐顺序见 [C0](../implemented/c0-real-file-compatibility.md)。`cases/c0-upstream-candidates.json` 保留候选身份快照；后续执行见 `cases/c0-current.json`，不将候选清单的 `not-run` 当作当前运行状态。

C43 原始尺寸面积图的前批上下文诊断归私有 `nativeAreaContextDiagnosis`，该批未改产品。当批构建复跑固定图框面积图和系列容量，两条流程通过，固定图框 Canvas/PDF 保持 0/0。该图框不是原工作表的 528 × 293.25 pt 图框，不能据此授予原件整页资格。

两份独立原生控制仅保留面积图锚点，或额外保留一个不在第 14 页的三维柱图锚点。其他 OPC 部件逐字节保持，包含面积图定义、缓存、原始锚点、字体和页面设置。固定转换器均输出完整 15 页 PDF。增加柱图后，原生第 14 页面积图左右各收缩 2.25 pt，纵向共收缩 3 pt；SDK 两份第 14 页 Canvas 和 PDF 栅格分别逐字节相同。原生两控制间的完整页面差异为 32337/33241。固定版本源码将共享边距从 14 改为 17 像素且未恢复，控制结果确认了跨图表状态影响。

四组原始尺寸严格比较全部执行并保留失败：仅面积图的 Canvas 为 150/119、PDF 为 164/0；附带三维柱图后分别为 31088/32571、33410/32350。仅面积图的 PDF 余差全部位于打印右边缘。PDF 运算符确认原生绘图裁剪先量化到 96 dpi 像素，再按元文件的十万分之一毫米截断；SDK 仍使用未量化裁剪。本项尚待修正，Canvas 另有边界余差待核对。原件、正式参考、阈值及失败断言保持；完整 C43/C0 尚未通过，未跑全仓。

工作表实心矩形填充的当前证据归私有 `nativeWorksheetRectangleFill`。无描边矩形在核心复用已有矩形填充图元。固定、随格移动及随格缩放锚点在 50%、100%、150% 下，由默认 UI 的正常预览 Canvas 和 PDF 对照同一份修改前冻结的 ONLYOFFICE 参考，六组全部为 0/0。此前两个 Canvas 各三个角点失败已消除，源字节保持。带描边与其他形状保留原路径，宿主、渲染器、字体与阈值保持。

31 项核心和九条正常界面流程通过，覆盖三个新原生控制、形状默认控件与同步 SDK、绘图滚动、图片及裁剪和 C43 原件。完整双向诊断的十二组比较均已执行，六组左到右通过；三组右到左的 Canvas/PDF 差异计数现分别一致，定位、不等边距及原生自动范围裁剪仍待核对，严格失败保留。C43 原件的 15 页完整 PDF 与前批逐字节相同，原样保存及新 Worker 保持，主图 Canvas/PDF 仍为 0/0。其余整稿视觉继续复用前批明确构建身份的结果，本批未重跑全部 30 组。第 14 页增加的差异、C13/C17 及两个参考决定继续保持。

正常构建、所属包严格检查、公共 XLSX 接口保持、私有 TypeScript、定向 lint、格式、链接与源码上限通过，未跑全仓。首轮将 worker 选项放入 describe 的准备失败保留。两个旧 XLSX 可重建二进制缓存已清理，源快照、脚本和失败记录保留。完整 C0 尚未通过。

前批工作表绘图打印原点与 C43 整表证据归私有 `nativeWorksheetDrawingOrigin`。核心在绘图打印坐标加入原生的一个网格像素偏移，保留源锚点、尺寸、网格视图和单元格打印。六个独立原生控制在修改前冻结，覆盖固定、随格移动、随格缩放锚点、50%/100%/150% 以及两个方向。左到右的三个完整 PDF 均为 0/0；150% Canvas 也为 0/0，50% 和 100% 各为 0/3。完整十二组严格断言仍失败，矩形路径角点与右到左不等边距、原生自动范围裁剪差异均保留，未授予全部控制资格。

31 项定向核心和十四条 Chromium 流程通过，覆盖打印设置、区域、重复标题、整本输出、源保存、精确历史、新 Worker、形状、图片裁剪、绘图滚动、切片器和时间线。C41 原件/改后全部六页、C42 原件/改后全部三页的 Canvas/PDF 仍为 0/0。C43 主图保持 0/0，18 个原始图表可查询，15 页打印与新 Worker 的 PDF 字节保持一致。正常构建、所属包严格检查、格式、源码上限和公共 XLSX 接口保持通过；宿主与渲染器未改，未跑全仓。

C43 全部 15 页、30 组严格对照已完整重跑。第 3 页 Canvas/PDF 首次均为 0/0。首面从 Canvas 14774/15956、PDF 15076/16590 降为 788/2497、802/2470。第 14 页反而从 Canvas 38999/41448、PDF 39697/42681 增为 46577/49556、48903/49360；其余页面的比较结果完整保留。该页尚无完整视觉资格，继续定位局部布局，不能靠恢复错误打印原点抵消差异。原样保存保持，冻结参考及容差保持。剩余 28 组仍失败，完整 C43/C0 尚未通过。准备错误、初始化字体上下文前的查询快照失败、容量守卫和修复前后严格失败均保留。后续核对矩形角点、右到左打印及 C43 余差；两个参考决定仍待答复。

前批 General 列宽适配与 C43 整表复核归私有 `nativeGeneralColumnWidth`。五种列宽、十五个 General 数值与一行固定小数控制的 80 个预期，均在修改产品前由固定 ONLYOFFICE 的独立字面 XML 控制生成。原生 PDF 文字只按源行距和原生表头坐标提取。核心现按 Normal 数字宽度给出预算，再测量并减少精度，科学计数进位沿原生剩余预算处理。80 个网格显示值及完整打印文字全部匹配；控制文件的正常整页 Canvas/PDF 均为 0/0，原样保存保持。

30 项定向核心和十二条 Chromium 流程通过，覆盖原件、格式输入、精确历史、公式、TEXT、缩小适配、页面设置、打印区域、整本打印及新 Worker。C42 原件与改后全部三页的 Canvas/PDF 继续为 0/0；C43 主图也保持 0/0，原件全部 18 个图表可读取，15 页打印及新 Worker PDF 字节保持一致。正常构建、所属包严格检查、格式、源码上限与公共 XLSX 接口保持通过，未跑全仓。

C43 原件的全部 15 页、30 组严格比较已重新执行。首面 Canvas 从 20468/26457 降为 14774/15956，PDF 从 20576/27467 降为 15076/16590；其余 14 页的 28 张 PNG 逐字节保持。30 组仍全部非零，完整 C43/C0 尚未通过。源、冻结参考、96 通道与一像素容差保持。初始井号失败、科学计数进位失败及一次准备语法错误保留。后续继续核对原尺寸图表布局与已知原生漏画、气泡退化；C13/C17 的参考决定仍待答复。

C43 前批整表打印与目录证据归私有 `nativeWorksheetPrintBounds`。绘图尾端按右、下开区间计算占用范围，边界恰好贴合行列时止于前一个可见格；零宽高线保留锚点。原件工作表在相同 Arimo 字体下从 18 页修正为独立原生的 15 页。原生转换器未指定比例时把全部内容缩成一页；该路线完整保留，正式诊断显式选择 SDK 合同的 100% 并关闭拟合。参考从既有独立字面缓存控制生成，只替换明确的字体属性，原始锚点、缓存与页面设置保持。

宿主目录现保留曲面类型及字面缓存的空绑定，原件全部 18 个图表可查询。读取与编辑共用字段校验，编辑仍要求完整引用；未知类型、非法字段和原生配置保护保持。23 项核心、56 个宿主边界断言和十条 Chromium 流程通过，覆盖原件末页预览与完整 PDF、新 Worker 字节一致、图表编辑、C41 完整页、C44 条件格式、页面设置、打印区域、整本打印、形状和绘图滚动。主图的完整 Canvas/PDF 仍为 0/0。正常核心构建、宿主模块与 Worker 重建、公共接口保持、类型、lint、格式和源码上限通过。

该前批构建的全部 15 页正常预览 Canvas 与 PDF 共 30 组严格比较已完整执行，均仍有差异。原样保存保持；96 通道与一像素容差保持。整表结果包含既有原生漏画与气泡退化，以及仍待定位的数值 General 列显示和原尺寸图表布局差异，未授予整稿视觉资格。首次诊断被目录校验阻断；宿主单元检查通过后曾遗漏 Worker 重建，补齐后完成全部比较。准备错误、旧 Worker 失败和最终严格失败均保留。下一步先核对原始列宽下的数值显示，再处理图表整页差异。其余 C13/C17 的参考决定与 C0 缺口继续保持。

C43 前批工作表打印修复归私有 `nativeWorksheetPhoneticDefaults`。原件的空 `phoneticPr fontId="1" type="noConversion"` 曾被误报为未绘制内容，整张工作表因此无法导出 PDF。核心现校验并保留该默认设置。固定 ONLYOFFICE 的独立控制只增删这项元数据，完整原生页 PNG 逐字节相同。九种合法默认设置保持打印几何；十一种非法声明仍保留诊断并拒绝打印，实际 `rPh` 文本的编辑与打印保护保持。十五项定向核心检查通过，公共接口保持。

该前批构建的正常 Chromium 界面可预览原件工作表末页并导出当时的 18 页 PDF。18 个原始图表对象可读取，原样保存保持，新 Worker 的完整 PDF 逐字节相同。主图的完整 Canvas 与整页 PDF 对照仍为 0/0。该原件流程及六条相关回归通过，覆盖 C41 原件/改后完整页、C44 条件格式、打印区域、页面设置与整本输出。正常构建、所属包严格检查、私有 TypeScript、格式及行数上限通过。此项修复只证明打印通路恢复；整张工作表和重算后输出的独立视觉对照仍待补齐。其余 C13、C17、C43 的严格失败与两个参考决定继续保持，完整 C0 尚未通过。

C40 当前证据归私有 `nativeMetafilePreviews`。完整默认流程的原稿、改后 Canvas 与 SDK PDF 四组独立整页比较均为 0/0。原始 EMF、工作簿和非目标部件保留，背景输入、对象保护、精确撤销重做及新 Worker 保存重开通过。核心生成 321×209 的完整预览，PDF 提取仍包含源标签。原件、固定字体、参考工具及 96 通道/1 像素容差保持。实现与预算归[格式合同](formats.md#docx-内嵌-ole-预览)。

本批复用已安装 Zeno 的路径遮罩，沿既有图片资源与无损 PNG 管线输出核心 RGBA。宿主保留透明像素的源颜色，并对该预览按原生源像素块缩小；普通 PDF 图片保持既有采样。8 项定向核心、7 条 DOCX、9 条 Canvas 和 16 条 PDF 回归通过。完整 C17 的 28 组比较中 27 组为 0/0，仅原稿第 11 页保留已确认的八个参考工具差异；首轮通用缩小引入的第 2 页两点回归已消除，失败证据保留。51 文件有界扫描无意外失败：46 个正向输入通过，五个控制项拒绝。扫描范围仅为打开与选定核心布局，XLSX 只检查打开。正常构建、严格 MoonBit、类型、lint、格式和源码产物重建核对通过。全仓未跑，C13、C43 及页面边缘差异仍待处理；C17 参考工具变更仍待单独决定。

C13 当前完整原稿证据归私有 `nativeOfficeTextDecorationSpaces`。2026-11-05 的 48 页正常 Canvas 与整页 SDK PDF 复查中，第 32 页下划线余差从 Canvas 111/33、PDF 102/33 降为 12/0、3/0。其余 47 页的 94 组 PNG 和全部原生 PNG 逐字节保持。96 组比较仍有 57 组为 0/0；25 页保留 39 组严格失败。全部布局诊断为空，48 次 PDF 导出成功，原样保存保持。原件、五个字体、冻结参考及 96 通道/1 像素容差保持，没有新增整页或编辑资格。

12 个独立原生控制核对行首、内部、行尾及全空格、格式 run 边界、软换行、显式换行、不换行空格和删除线。共享布局复用已有行尾内容边界，只收窄下划线和删除线；逻辑文字、塑形、光标与高亮保留。17 项装饰/间距/单元格核心及 42 项 PPTX 核心通过。六条正常 Chromium 流程覆盖 DOCX 超链接输入、PPTX 文字/表格链接与字符/段落格式、XLSX 装饰；源、精确历史和保存重开通过。

正式 C13 的 30 组比较完整执行，原生输入、282 个非目标部件、精确历史及新 Worker 重开通过，严格视觉仍失败。同构建 51 文件有界扫描符合预期：46 个正向输入打开，五个控制项在打开时拒绝；扫描只覆盖打开和选定布局，XLSX 仅检查打开。正常构建、所属 MoonBit 包严格检查、公共接口保持、格式、XML、登记和源码上限通过。宿主 TS 与渲染模块保持，复用前批类型/lint 和 JS 重建证据。未跑全仓；C13、C43、页面边缘及 C17 参考工具决定仍待处理。首轮私有未改文件的格式差异另存，公共源码和本批私有文件分别完成格式检查。

C13 图片颜色补充诊断归私有 `nativeOfficeImageRouteDiagnosis`。固定原生 PDF 将四个不透明 PNG 转为 JPEG85。临时使用 Chromium 现成编码器，第 43 页 Canvas/PDF 及第 36 页 PDF 均为 0/0；第 36 页 Canvas 为 34/23，第 26 页仍保持 0/0。三个原稿的正常 Canvas/PDF 先逐字节复现当前构建，原样保存保持；该临时路径未进入产品。另对完整 48 页复查两条原生路线，当前 Canvas 对直接 PNG 为 4/48 零差异，对冻结 PDF 为 23/48。直接 PNG 还改变字体等绘制结果，因此没有整批替换参考。

同一 P12 原图经原生直接 PNG 保留红色 255/0/0、绿色 0/255/0、蓝色 0/0/255；经原生 PDF 为 252/1/0、0/255/0、0/1/251。现有 P12 显示与 PDF 精确颜色断言及核心源 RGBA 保留检查要求原色。直接加入有损转码会改变这个合同。已准备独立无损颜色候选：只把四个唯一关联的原生 JPEG 图片流替换为包内 PNG 解码 RGB，保留原生字体、内容、几何、图案、裁剪与顺序。44 页原生 PNG 逐字节保持，变化仅在第 3、15、36、43 页。未改 SDK 的全部 96 组比较对候选为 61 组零差异，原已通过项保持；第 3 页 Canvas 仍为 99/218，第 36 页仍为 46/125，其他缺口继续保留。

57/96 是旧 JPEG 参考在当时构建的诊断基线。该批新增三条诊断浏览器流程，并复用 59 项核心、六条界面和 51 文件有界扫描。用户随后确认保留原图 RGB，采用上方正式参考。C17 的参考工具选择另行记录。

前批图片采样完整原稿证据归私有 `nativeOfficeImageAlpha`。2026-11-05 的正常 UI 复查覆盖全部 48 页 Canvas 与整页 SDK PDF。96 组冻结原生比较中 57 组为 0/0，25 页仍有 39 组差异。第 26、30、41、44 页 Canvas 从 2/0 降为 0/0；第 31、32、42 页也减少差异。48 页 PDF、其余 41 页 Canvas 及全部原生参考 PNG 与上轮逐字节一致。全部布局诊断为空，48 次 PDF 导出成功，原样保存保持。原件、五个固定字体及 96 通道/1 像素容差保持。

普通 PPTX 图片现独立采样颜色与透明遮罩。三个独立原生控制只改变 GIF 全透明调色板项的 RGB；原生整页 PNG、颜色面与遮罩均逐字节相同。固定 ONLYOFFICE 源码也将全透明 RGB 归白，再独立写入遮罩。宿主按现有资源身份缓存派生颜色位图，原始 RGBA 与压缩源保持。非透明图跳过派生资源；替换、淘汰和销毁关闭位图。最终遮罩按八位 Alpha 合并对象透明度，解决既有平铺图片半透明回归。采样范围及预算见[格式合同](formats.md#通用绘制输出)。

10 条 Canvas、5 条原件/阴影/GIF/OLE、6 条图片编辑和 2 条页面图片导出流程通过。既有 P12 平铺透明度断言保持。正式 C13 的十二页原稿及三页编辑共 30 组比较完整执行；原生输入、282 个非目标部件保留、精确历史、新 Worker 重开及重开 PDF 栅格一致性通过，严格视觉仍失败。新通过的四页仅增加原稿 Canvas 显示证据，不增加编辑资格。正常构建、根与私有类型/lint、定向格式、登记、源码上限及五个 JS 模块重建核对通过。Wasm 与核心解码器保持，复用前批 8 项核心和 51 文件有界扫描；扫描仅检查打开及选定布局，XLSX 仅检查打开。未跑全仓，C13、C43、页面边缘及 C17 参考工具决定仍待处理。首轮过宽浏览器组超时及平铺透明度失败证据保留。

前批混合字体完整原稿证据归私有 `nativePptxMixedFontLines`，首次审计归 `nativeC13FullPageAudit`。正常 UI 逐页显示全部 48 页，并分别导出整页 PDF。96 组固定原生对照中 53 组为 0/0；29 页仍有 43 组差异。全部布局诊断为空，48 次 PDF 导出成功，原样保存保持。整轮在既有 180 秒时限内完成。正式用例检查十二页原稿及第 20、23、42 页编辑，共 30 组整页比较。原生输入、精确历史、非目标源保留及新 Worker 流程通过，严格视觉仍失败。

本批修复混合字体的自动行度量。核心先按每种实际字体归一升降部，再合并最大值，复用固定行距的度量读取。16 个独立原生控制核对三个字体族、字体顺序、混合字号、软换行、百分比与固定行距、继承缩减及存储缩放，含两组重复固定行距控制。48 处行基线及冷热缓存的完整行几何匹配。41 项定向核心及九条相关 Chromium 流程通过，覆盖文字框、列、适配、母版默认值、列表、表格文字/组合及图示。第 5 页整页 Canvas 从 930/980 降为 5/0，PDF 从 909/964 降为 0/0。其余 47 页的 94 组完整比较和图片 hash 均逐字节保持，没有回退。原件、字体、冻结参考、渲染器及容差保持。

同构建的 51 文件有界扫描无意外失败：46 个正向输入通过，五个既有控制项在打开时拒绝。XLSX 仅检查打开，其他格式仅覆盖选定布局。正常构建、严格 MoonBit、私有类型、lint、格式、XML、登记、源码上限及 1355 个本地链接检查通过。未跑全仓；本批新增第 5 页 PDF 显示资格，Canvas 和整稿仍失败，没有新增该页编辑资格。

SmartArt 补充诊断归私有 `nativeC13ShadowRoutes`。同一固定主引擎导出 16 个中性阴影控制的 PDF 与直接 PNG。同类控制的四种模糊半径在 PNG 控制区内逐像素相同，印证原生绘制未使用该半径。50% 渐变阴影在直接 PNG 中为灰色，PDF 则丢失透明度并报告缺少软遮罩组；纯色控制仍保留透明度。另对原件 48 页完成 144 组补充整页比较。第 8 页 SDK Canvas/PDF 对直接 PNG 均为 0/0，对冻结 PDF 仍失败。该诊断绑定修复前构建，只用于归因；冻结 PDF、严格断言和原有阴影功能保持，不据此增加资格。其余页面的差异继续独立处理。

前批字体资源证据归 `nativeC13FontResources`。原生字体清单覆盖全部 48 页。冻结 PDF 实际使用五个字体，正式验收此前只加载两个。该批补齐固定字体表中已有的 Carlito Italic、Arial Bold 和 Times New Roman，保留原始字节和来源。五页独立诊断后，全部原稿与扩展正式流程重新验收。首次扩展因重复传送字体触及时限；复用字体字节后，各新 Worker 仍独立注册全部字体，最终流程在 180 秒内完成。超时及严格视觉失败证据均保留。该批产品代码和正常构建保持，复用同构建核心、相关界面及 51 文件有界扫描证据；未重跑核心或全仓。私有类型、lint、格式及源码上限通过。

前批段距证据归 `nativePptxParagraphGaps`。16 个独立原生控制核对相邻段距、点值与百分比、继承、空段、软换行、混合字号、固定行距及存储缩放。PPTX 现合并相邻段距，百分比按自然文字行高换算。48 处原生基线与冷热缓存的完整行几何匹配。该批 40 项定向核心通过，覆盖正文、框适配、列表、数学、表格、SmartArt 及编辑历史。第 20 页真实原生输入、282 个非目标部件保留、原段落与文字段属性检查及新 Worker 重开通过；编辑后 Canvas/PDF 字节保持。

该段距批次的九条相关 Chromium 流程取得通过记录，覆盖文字框、列、适配、母版默认值、列表、表格文字/组合及图示。首轮为 8/9，组合表格停在禁用的复制按钮；独立复查未重现该状态。用例现等待组合选中后再读取组身份，单条完整复验通过；复制、取消组合像素、历史和 PDF 断言保持。修复前构建在该处的查询与当前构建相同，其后因探针缺少 `pdftotext` 路径失败，该环境失败保留。同构建的 51 文件有界扫描无意外失败；XLSX 只检查打开，其余格式只覆盖选定布局，不授予完整视觉或编辑资格。

前批断行证据归 `nativeOfficePunctuationBreaks`。24 个独立原生控制核对 Calibri/Arial 的十二种分隔符。共享段落现取消词内斜杠、Unicode 连字符及短破折号后的可选断点，保留普通连字符与长破折号的断点。单段和跨样式分段共 48 种情况，96 次冷热缓存查询均匹配原生行文字，逻辑源和不换行空格保持。控制显式使用与原生相同的本机 Helvetica 回退资源；字体校验和公共构建保持。该批 105 项定向核心通过，包含 27 项共享布局、41 项 PPTX 和 37 项 DOCX；资源迁移后另复验新增用例。

该断行批次的 Chromium 流程通过 11/12 条，包含五条 PPTX 与六条 DOCX。C40 原有 EMF 白底残差仍使严格用例失败：原件 Canvas 为 9/0、PDF 为 6/0，编辑后两种输出均为 0/0。四份完整差异报告及坐标与前批相同。链接文字框仅通过功能流程，未补授其缺少的独立原稿视觉资格。该批 51 文件有界打开与选定布局扫描无意外失败；其范围不含完整视觉或编辑验收。

前批 C40 诊断归 `nativeEmfRasterDiagnosis`。该批构建重跑完整默认流程，仍为原稿 Canvas 9/0、PDF 6/0，改后均为 0/0；原稿 SDK PNG 与固定原生 PNG 分别保持前批字节。[原生纹理路线](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/PdfWriter.cpp#L3921-L3963)按 300 dpi 将整个 EMF 预览转成 321×209 图像，再放入 PDF 平铺图案。隔离对照只替换该图像的颜色或透明度流，保持页面、图案、尺寸和原生采样；原生遮罩对照逐字节复现固定整页 PNG。SDK 字形按同一中间尺寸绘制，再使用无损 RGB 和自身遮罩时，三种既有字形策略的完整 PDF 对照均为 0/0。这说明该用例无需先增加 JPEG 编码或字体提示解释器，但尚未构成产品修复。浏览器直接缩放同一图像仍失败；现有像素字号策略虽降为 3/0，却新增差异位置，均未采用。正式用例、阈值和 SDK 实现保持，后续须核对共享元文件预览与图像采样，不能只改变这一原件。

前批字号证据归 `nativePptxScaledSizes`。20 个独立原生控制核对字号导入、缩放取整及列表大小；额外控制证明空 `normAutofit` 在 10×1 pt 框内仍保留 10.5 pt 原字号。MoonBit 现按半点导入字号，缩放后取整数点；百分比标记跟随缩放文字，固定点数标记保持大小。读取不重新缩小原稿，实际编辑才重算并保存明确比例；核心检查精确历史和重开字号保持。该批 41 项定向核心及十条 Chromium 流程通过，覆盖文字框、列、主题字体、列表、页码、数学和形状调节。

前批颜色和文字段偏移修复归 `nativeHyperlinkThemeColors`。四个独立原生控制核对点击链接与项目符号颜色。点击文字使用映射后的主题 `hlink`；直接和继承颜色的源定义保持，移除链接后恢复。悬停文字及项目符号保留源颜色。正文和表格同步文字段的全文偏移，修复样式分段导致的 PDF 提取错字。该批记录的合并表格行高失败保留，当前结论见下段。

两条 P12 旋转用例曾在新旧渲染器下均报告缺墨。固定 ONLYOFFICE 重开两份保存稿，点击链接文字均使用主题色 `0563C1`，源 XML 仍保留 `0055AA`。按独立结果校正取色后，两条旋转用例及 C08 原件通过。像素容差、文字几何、链接和历史断言保持。证据归私有 `nativeHyperlinkThemeColors.rotationReplay`。

表格最小行高复查归 `nativePptxTableMinimums`。三个独立单元格控制使用 18 pt Arial、上下各 4 pt 边距，源行高分别为 12、30、12 pt；第三格含四段文字。固定 ONLYOFFICE 10.0.0 的 PDF 单元格填充路径给出 29.6、30、94.4 pt。当前核心匹配原生结果，三处旧精确断言仍沿用早期字体行框，现按独立结果更新。44 项 PPTX 表格定向核心全部通过，覆盖合并、拆分、尺寸、变换、文字、选择、保护与历史；新增控制另检查源保存、精确撤销重做和重开行高。SDK 源码、发布产物、真实原件和冻结整页参考保持，本次不增加整页视觉资格。

字体资源批次将首次审计的 33 组 0/0 增至 52 组。该批新增第 24、39 页的完整 Canvas/PDF 及第 25、34 页 PDF。第 25、34 页 Canvas 仍为 2/0、3/0，第 38 页两种输出仍为 1/2。第 28 页 Canvas 降为 3070/3749，PDF 降为 3048/3665，剩余 WMF 等差异继续保留。其余 41 页的 82 组完整比较与图片 hash 均与段距修复构建相同，没有新增退步。正式用例中前批二十组比较也逐字节保持。第 20 页原稿与编辑后的输出仍为 Canvas 3/0、PDF 0/0。完整 C13/C0 仍未通过；第 24、39 页原稿通过不授予新增编辑资格。

C17 前批整稿证据归私有 `nativePdfGradientClips`，首次完整审计归 `nativeType1FullPageAudit`。正常用例检查全部 14 页及其 90° 旋转，共 28 组完整页面。该批 27 组为 0/0，仅第 11 页原稿有 0/8 差异。该页原稿从 6/8 降为 0/8，旋转从 2/0 降为 0/0。其余 26 组完整比较及 PNG hash 逐字节保持。前批第 2、4、5、6、7、13 页保持通过。原样保存、整稿旋转、精确撤销重做、保存重开和 997 个独立源记录检查通过。图形子集的空 ToUnicode 保留不完整标记。

八点颜色诊断归私有 `nativePdfShadingCacheDiagnosis`。固定 Poppler 按裁剪范围缓存渐变函数，再对缓存起点前的首行像素外推。第 11 页蓝色分量由源函数的 1 外推至 `1.002139…`，转成 8 位值时从 256 回绕为 0。独立复算原函数、缓存及 LittleCMS 转换，得到与冻结画面相同的 `169/200/0`。原采样函数自身仍有界。源码依据 [Poppler 缓存插值](https://gitlab.freedesktop.org/poppler/poppler/-/blob/3a79c6217fe185311e4905204d99c7a53a480883/poppler/GfxState.cc#L3689-3820)及[ICC 输入编码](https://gitlab.freedesktop.org/poppler/poppler/-/blob/3a79c6217fe185311e4905204d99c7a53a480883/poppler/GfxState.cc#L1902-1950)。

四个独立控制用字面采样表、ICC/RGB 两种色彩空间及两个裁剪相位复现该问题。仅第一组 ICC 的首行 81 个像素受影响，另外三组及其他像素逐字节保持。候选参考只加一行缓存范围守卫，超出范围时复用原函数求值。未修正源码重编译的第 11 页 PNG 与冻结参考逐字节相同。加入守卫后，未修改 SDK 和正式用例完成全部 28 组整页零差异检查，997 个源记录、精确历史和保存重开也通过。28 份 SDK PNG 全部保持，27 份参考 PNG 保持，仅第 11 页原稿参考改变。候选尚未切换为正式对照，当前正式门槛仍为 27/28。

固定 ONLYOFFICE 10.0.0 的 PDF 直接栅格路线另生成原件全部 14 页，八点所在区域保持蓝色方向。该主引擎第 11 页与 SDK 的整页比较为 351/492，不能据此授予整页资格。原工具、冻结参考和旧失败均保留。通用缓存修复已纳入正式参考工具，当前结果见[本页入口](#当前兼容证据入口)，产品像素和既有阈值保持。

本批修复线性渐变前的矩形裁剪。逐像素追踪证明，原生残差行已经进入彩色柱体，SDK 仍显示后方灰色阴影。原始 RGBA、图像矩阵和图像绘制保持；此前按图像重采样归因不够准确。16 个独立控制覆盖横纵渐变、四种小数相位、两组颜色及透明度。旧构建原稿为 472/0，旋转为 114/0；最终原稿、旋转及 16 个控制区均为 0/0。内容流、透明度定义、精确历史、保存重开及实际加载字节检查通过。120 组既有裁剪像素、透明度和状态检查通过；PDF 线性渐变预期改为独立四档覆盖率常量，Office、径向、实心与其他变换预期保持。边界规则归[格式合同](formats.md#字体资源与替代)。

仅复用普通 PDF 裁剪可清除该页旋转残差，但独立控制仍失败。把两侧全部取整会让旋转侧边退步。最终按四档覆盖率、校正及渐变有效区间表达普通裁剪路径，没有新增遮罩、缓存或栅格器。首轮其余 PDF 复查发现 C30 未延伸端点的一个新增旋转边角像素；按设备整数位置限制着色范围后，四种延伸组合均恢复通过。前述候选和失败控制保留，原件、参考及容差保持。

前批内容数值证据归 `nativePdfContentDecimals`。PDF 内容操作数按原生顺序累加小数，源对象仍使用原词法器。绘制器直接组合六个双精度矩阵分量，保留字形定位前的精度及保存恢复状态。16 个独立控制覆盖四种字号、相位及相消的文字移动。当前原稿与旋转仍为 0/0，各 16 个原稿控制区也为 0/0。嵌入 URW 字体与原件对象 8 逐字节相同，嵌入许可声明保留。内容流、字体流、文字、透明度语义、精确历史和重开保持。42 组字形几何及缓存页面、覆盖层、图片导出的四次策略切换继续通过，包含低于整数边界的轴对齐及旋转控制。

第 5 页的 67 次文字移动在标准小数转换下得到横向位置 `54.00000000000003`，原生逐位累加得到 `53.99999999999997`，设备取整相差一行。浏览器矩阵运算也会提前舍入该边界。两处修复共同保留原生采样位置。全局数值转换曾改变源对象的 BBox，已撤回；重复转换并增加工作计费曾触及第 11 页预算，也已撤回。最终替换内容操作数的普通转换，保留既有整数、异常回退及逐字节工作计费。对象词法器逐字节保持，没有提高预算。轮廓定点量化未改善差异，没有采用。

前批字形相位证据归 `nativePdfGlyphPhases`。PDF 普通轴对齐填充字形复用已有横向四档定位，保留字体缓存高度上限。此前 16 个独立 `fi/n/e` 控制在当前构建仍通过原稿、旋转及控制区对照。字形和策略切换的旧 PDF 横向坐标预期按原生四档值更新，逐像素断言保持。

将四档规则同时应用到 90° 字形，会让第 6 页旋转从 0/0 退为 0/1；该候选已撤回。仅量化字体矩阵也未清除三处字形差异。最终只复用轴对齐路径，旋转字形保持原规则。没有新增字体栅格器、缓存、模型、配置或依赖。

前批图案证据归 `nativePdfPatternCells`。按最终设备重复格数直接绘制小图案，并仅在这些格内对齐正向轴对齐图片的设备边界。32 个独立控制的原稿与旋转共四组整页仍为 0/0，各 16 个原稿控制区也为 0/0。内容流、透明度语义、历史及重开检查继续通过。单格表面、深度、4096 格预算、直接重放工作上限及缓存回退保持。

前批曲线描边证据归 `nativePdfFlattenedRectangles`。曲线细分后复用已有矩形描边，保留回到起点但未显式闭合的端帽规则。16 个独立控制的原稿与旋转仍为 0/0，原稿控制区、内容流、透明度语义、历史及重开检查继续通过。

前批圆头虚线证据归 `nativePdfRoundDashes`。其相位、闭合连接、轴线对齐与有界子像素遮罩保持。该批的 16 组独立控制在当前构建的完整原稿与旋转仍为 0/0；颜色、一次透明度、外层裁剪、状态和五类回退检查继续通过。

最终构建的其余十六条 PDF 原件流程及 C34 双页表单全部通过。二十四条 Canvas 检查中二十三条通过，平移页边界仍为原输入失败；修改前绘制模块已独立复现，原断言保持。七条共用 PDF 策略的表格打印流程通过，含 C41/C42 原稿及改后整本的 36 组 Canvas/PDF 对照、保存重开，以及打印范围、设置、页序和缓存。正常构建、公共与私有 TypeScript、lint、格式、登记、源码上限及本地文档链接通过。首轮四处字面量精度 lint 警告改用相等分数表达，独立数值断言、定向像素复验及最终六项静态检查通过。Wasm、图案与描边模块逐字节保持。复用前批同引擎的七项核心与 51 文件扫描：46 份正向输入通过，五份控制项在打开时拒绝。该扫描只检查有界打开和选定布局，不授予完整视觉或编辑资格。C02、C13 等其他格式保留各自完整流程的原构建身份，本批未重复其完整流程或全仓检查。

八组失败邻域追踪逐字节重放当时的正式画面。第 4、6 页同为 Type1 连字，现已按横向分档修复；第 5 页旋转已按内容小数和矩阵精度修复。第 7 页来自小曲线描边。第 13 页余差来自条形边框附近的图案图片上边缘；此前边框归因仍不够精确。第 11 页八点已定位为固定对照工具的渐变缓存外推溢出，详见上方诊断。旧全局图片边界对齐、重采样和取消圆角边界的候选继续只作诊断。该批尚未采用缓存修复，完整 C17/C0 当时未通过正式门槛；当前正式结果见[本页入口](#当前兼容证据入口)。

前批私有绘制助手复用一次旋转、历史与重开，逐页生成画面后调用 `releasePdfView`。首轮因未释放视图触发九页/16 MiB 上限，修正调用后完成全稿。180 秒时限、核心预算、原件、参考、每通道 96 及一像素邻域均保持。该批另 16 条 PDF 原件流程全部通过；C34 保留当时同构建的完整通过结果。私有类型、lint、格式及源码上限通过，该批产品和正常构建未变，未重跑核心或全仓。

首次四页诊断逐字节复现当时画面。第 2 页残差由圆头虚线绘制产生，第 4 页涉及 Type1 连字轮廓，第 11 页涉及带 Alpha 图像覆盖灰色网格；第 13 页当时尚未确定来源，当前归因见上方八组邻域追踪。仅在诊断中将轴对齐图片边界取整，第 11 页从 6/8 退为 10/8；该候选未进入产品。继续沿原生虚线、字体实例与图像下采样规则定位，严格用例保持失败。

前批圆头虚线诊断归私有 `nativeRoundDashControls`。显式切分虚线后，四页画面仍与原基线逐字节相同。按原生平坦度生成圆头轮廓后，第 2 页整页对照为 0/0，另三页差异保持。16 个独立 PDF 控制覆盖轴线、斜线、转角、曲线、闭合路径、粗细线、透明度、变换及相位。首个轮廓候选让原本通过的细线变为 0/4；改用端点方向并复用已有轴线描边后，水平、垂直及转角控制为 0/0，细线仍退为 0/1，闭合框保持 448/673。当批候选只作诊断，没有新增资格。其退步证据继续保留，当前结果见上方记录。

C34 双页表单与路径闭合修复归私有 `nativeTwoPageForms`。未改原件包含四个独立文本域和两个受保护按钮，每个字段只有一个 widget；候选标签不能证明跨页共享同一字段。原生输入分别修改两页的 `Text1/Text3`，其余值保持。精确撤销重做、新 Worker 重开、51 个非目标源对象及两个按钮的安全拒绝均通过。

核心现省去重复闭合指令。八组独立控制覆盖 `re/h/s/b/b*`、显式闭合、复合矩形和空路径，先复现旧实现的六段矩形，再验证规范化的五段结构。原件两页及编辑后两页的完整 Canvas 对照由每组 1191/0 降到 0/0。原件参考来自独立 Poppler；编辑后对照采用独立引擎读取 SDK 保存的外观，并核对各页文字和值，不授予原生作者引擎的外观放置资格。字体显式使用固定 Arimo，实际加载的 Wasm、绘制模块及像素模块字节均有断言。规则归[格式合同](formats.md#表单与批注)。

26 项 PDF 核心、C34 完整流程及九条既有 Chromium 回归通过。范围覆盖 CFF、渐变、透明组、平铺、批注及表单导入、重命名、移除和选项。正常构建、严格 MoonBit、私有类型、lint、格式、源码上限与新增登记通过。最终构建的固定 51 份有界扫描仍为 46 个正向通过、五个控制项打开时拒绝。首轮测试准备误用了字段页序、错误信息中的代码和绘制前的当前页快照；这些准备失败及真正的严格视觉失败均保留。未改原件、参考或容差，未跑全仓，完整 C0 继续实施。

补充原件 `issue14023.pdf` 归私有 `nativeSharedPdfFields`。测试从固定的本地 PDF.js Git 修订提取原始 blob 并核对 SHA-256。从第 1、5 页编辑时保留当前页，第 1、2、5 页同步文本与复选值，单选组仅激活所选 widget。qpdf 和 Poppler 核对两次保存的字段值、外观及 51 个非目标源对象。撤销精确恢复中间版本和原件，重做恢复末版，新 Worker 读回同一字段树。共八条 Chromium 表单流程通过，含同构建 C34 的四组整页 0/0。补充原件的验收范围为字段同步、保存和历史。预期来自 [PDF.js 原件测试](https://github.com/mozilla/pdf.js/blob/24de17e81b3357b30ffd710ec080be00d65ac98d/test/integration/annotation_spec.mjs#L300-L395)。

同批 C13 诊断逐字节重放第 15、23、41、42、47 页。第 47 页四个残差均对应合成粗体年份标题；其他页还涉及图片和形状。主引擎对合成粗体采用填充加描边，并从 FreeType 的字体实例取得路径。该证据尚不足以修改通用字形算法。本批只改 PDF 输入的路径闭合；C13 保留前批构建的严格失败与完整流程证据。

C13 字形采样实现归私有 `nativeFontBoundGlyphSampling`。核心从实际字形字体提供上下边界，通用 Canvas 采样按原生缓存高度选择四档或整数横向原点。PPTX 保留整数几何，字形采用该规则。无 SFNT 字体的 PDF 原生矢量轮廓显式携带空边界。规则和职责归[格式合同](formats.md#字体资源与替代)，未增加样本特判。

21 项 PPTX 与 17 项跨格式核心检查通过。ABI 用例的 97 个断言覆盖空边界、缺失字段及非法边界。六条 Canvas 回归覆盖 36 组字形变换，包括缓存高度 50/51 像素、负坐标及反射。九条跨格式 Chromium 流程通过，覆盖两份 PPTX 表格、DOCX 裁剪、页眉图片、双栏、XLSX 主图及三类 CFF PDF。严格检查、正常构建、类型检查、lint、格式、源码上限及已有用例登记通过。

最终构建的十四组 C13 整页比较均完成。第 47 页实际 Canvas 从 426/500 降为 4/0，四个余差点仍在白色年份标题。第 23 页原件及编辑后 Canvas/PDF 四组保持 0/0；七组 PDF 全为 0/0。原生输入、282 个非目标部件、完整形状属性、精确历史和新 Worker 的画面及 PDF 字节一致通过。第 15、41、42 页及编辑后第 42 页 Canvas 仍为 19/1、2/0、3/4 和 3/4。正式用例首先在第 15 页失败，严格零差异断言保持。七条相关 PPTX 流程复用前一构建通过结果；两次构建之间只修正 PDF 空边界序列化，PPTX 字形数据及宿主产物相同。

最终构建复查固定 51 份语料：46 份正向候选及五个打开时拒绝的控制项符合预期。首轮新增字段曾使五份 PDF 因空值字段被省略而校验失败，核心现显式序列化 `null`，未放宽宿主校验。DOCX 独立参考首轮缺少字体配置而超时，补充双栏流程另缺少 `pdffonts`；修正工具环境后各自完整重跑通过。失败日志保留。扫描只覆盖各格式既有打开与有界布局，不授予整稿视觉或编辑资格。原件、参考、容差和旧记录保持，未跑全仓，完整 C0 仍未完成。

C13 前批小字形重放诊断归私有 `nativeGlyphCacheDiagnosis`，保留当时构建身份。同一正常构建的第 15、23、41、42、47 页，整数规则重放逐字节复现原 UI PNG。二十组整页比较只改变字形设备原点，不改布局、图片、源、参考或容差。按字体原始边界计算缓存高度，并复现固定 [ONLYOFFICE Splash 字形缓存](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/splash/SplashFont.cc#L65-L69)及[大字形无小数相位规则](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/splash/SplashFont.cc#L117-L122)，第 47 页诊断从 426/500 降为 4/0；四个余差点均在白色年份标题。第 23 页仍为 0/0，其他三页余差保持。统一改为小数规则会使第 23 页退为 692/696。该批只校准固定 PDF 栅格的采样，没有改变产品或授予整稿资格；当前实现及验收见上方记录。

同构建重新执行固定 51 份语料的有界扫描：46 份正向候选均通过打开及各格式已有检查，五个控制项均在打开时拒绝。PPTX/PDF 沿首、中、末页，DOCX 保留原有布局及源保存检查，XLSX 只检查打开；图片复用正常 Chromium 解码。该结果不授予整稿视觉、编辑或独立重开资格。详细记录为 `scan-after-exact-lines/scan.json`；原扫描、字体替代、产品身份和前批资格均保留。

C13 固定行距证据归私有 `nativeExactLineBaselines`。固定 ONLYOFFICE 10.0.0 的两份独立单页控制覆盖 32 组 Calibri/Arial、16/32 pt、16/33/52 pt 行高、混合字体字号、大标记及 0.01/0.5/1/2 pt 下限。原生 PDF 操作流给出每行基线；固定脚本与原生 Builder 内部度量另行交叉核对，预期不来自 SDK。核心按各字体原生比例计算基线，并将有效固定行距限制到至少 1 pt。共享 DOCX 固定行距保持，规则归[格式合同](formats.md#pptx)。

21 项 PPTX 定向核心和六项共享文字度量检查通过。范围覆盖全部 32 组控制、重复缓存读取、原件编辑、精确历史、重开、空行、字体资源边界、列表、图片标记、文本框和公式。正常构建、严格检查、格式、生成接口、源码上限及三项新增登记通过。七条相关 Chromium 回归通过，原正式整页用例仍保持失败，未改参考、原件、容差或断言。

第 23 页首行基线现为原生 172.35 pt。原件及独立 `Familiarize`→`EDIT` 后的整页 Canvas/PDF 四组均为 0/0。原生输入、282 个非目标部件、完整形状属性、精确历史和新 Worker 的画面及 PDF 字节一致通过。第 15 页 PDF 从 1792/1744 降到 0/0，Canvas 从 1810/1714 降到 19/1。第 41、42、47 页及编辑后第 42 页 PDF 保持 0/0；Canvas 分别为 2/0、3/4、426/500 和 3/4。十四组整页比较均完成，正式用例首先在第 15 页 Canvas 的非零差异处失败。其他 C0 缺口和整稿资格保持未完成，未跑全仓。

C13 第 28 页的行距证据归私有 `nativeExpandedLineSpacing`。扩大百分比自动行距时，基线取自然升部与扩展行高 75% 中较大值；负行隙规则保持。固定 ONLYOFFICE 的十组独立控制覆盖两个字体族、两个字号及四档行距。字体映射与原参考相同；未改 115% 行距的单页控制，其整页 PNG 与冻结第 28 页逐字节一致。九项直接检查和三十四项排版回归通过。规则归[格式合同](formats.md#pptx)。

独立对照只将 `Grade` 单元格的行距改为 150%。固定 ONLYOFFICE 的首行从 15.62386 pt 增至 19.79997 pt。四项定向核心检查通过，覆盖首行高度、文字基线和其余行高。默认 Chromium 界面编辑后，表格外框增高 4.17614 pt。原样保存、精确撤销重做和新 Worker 重开通过。整页严格结果仍为 Canvas 3100/3804、PDF 3078/3716，两份栅格与前批相同。证据归私有 `nativeExpandedLineSpacing.rowGrowth`。

正常 UI/Worker 的原生输入、精确历史、单元格属性、282 个非目标部件及新 Worker 重开保持。三次 PDF 导出成功，诊断为空。原件整页 Canvas 从前批 5289/4009 降为 5139/3865，PDF 从 3213/3813 降为 3048/3665，严格零差异仍失败。新增派生控制仅移除原图标的双色效果，对同一固定整页参考仍为 Canvas 2161/239、PDF 97/226。该控制也完成全部输入、历史、源保留与重开流程；它只定位双色效果之外的差异，不授予原件资格。首轮控制准备因 XPath 输出末尾换行未能替换 XML，修正准备后重跑整条控制流程，原件结果复用。

对已有完整 PNG 逐像素归类，复核了全部残差数量。原色控制的标题、表头与竖排区域没有剩余像素；Canvas 的差异位于正文和页脚，PDF 的差异位于正文及 WMF。字形栅格与路径边缘的具体原因尚未确认，本批未调整渲染器。

后续栅格诊断归私有 `nativeC13RasterDiagnosis`。正常 Canvas 和整数模式重放与原产物逐字节一致。小数字形模式对冻结 PDF 降为 564/123，仍未通过；考虑字体边界的缓存候选没有进一步改善。原生 PDF 的字宽取整和相邻字形合并已查到固定源码，但近似重放仍失败，不能据此修改布局。相同源页和字体映射的 ONLYOFFICE 直接 PNG 也忽略双色效果，且与它自己的 PDF 相差 323/6768。正常 Canvas 对直接 PNG 为 180/4644，小数模式反而为 415/6288。单一模式切换不能同时改善两种原生输出，因此产品、主参考和严格断言保持。

最终构建的十条 Chromium PPTX 回归通过，覆盖两个 SmartArt、两份表格、制表位、方向、列、框适配与旋转。前批四条 DOCX 回归保留其构建身份；本批只改 PPTX 行距，未重复执行。严格构建、MoonBit、私有 TypeScript、格式、lint 及源码上限通过，未跑全仓。

主参考仍未应用原图标双色效果。次选 LibreOffice 26.8.1.1 的未改原件显示蓝色图标，与 GenOffice 和 SDK 一致；但它将标题换为两行并覆盖表格，不能替换完整页面预期。固定主参考该页没有图片流，图标是矢量，不能将余差归因于 JPEG。两套参考和原件保持；基线控制、次选诊断及严格失败均保留在私有记录。

C13 第 28 页的前批换行证据归私有 `nativeTrailingSpaces`。共享排版延迟结算行末普通空格，按可见内容判断换行、对齐和 PPTX 框适配。原文、UTF-16 范围、完整空格几何与光标保持；不换行空格沿塑形器既有空格字形回退，制表位和强制换行保留语义。独立原生首行宽 246.83 pt，小于可用 247.09 pt；旧实现因末尾空格将其判为 249.32 pt。两项直接检查先复现旧失败，修复后的 42 项定向核心与十四条 PPTX/DOCX Chromium 回归通过。三份 DOCX 原件、改后 Canvas/PDF 和独立保存重开保持零差异。表格回归首轮因缺少测试环境的 `OPEN_DOCUMENT_PDFTOTEXT` 路径中断；补上路径后单独重跑整条流程通过。该批保留原构建身份，当前结果见上方行距批次。换行边界归[格式合同](formats.md#字体资源与替代)。

C13 第 28 页的字体前批证据归私有 `nativePresentationTextDefaults`。普通文字框按演示稿默认样式优先于母版合成，标题现读取固定原生 PDF 的 18 pt Arial Bold。占位符、表格及本地覆盖保持原有优先级。两项新增核心检查先在旧实现上失败，修复后的 17 项定向检查全部通过。原件表头的显式 Calibri Bold 保持；初轮新检查漏写该粗体预期的准备错误另存日志。

该字体批次的四条 Chromium 流程中，母版文字编辑及 C15/C16 两份原生表格通过。C13 原生输入、精确历史、单元格属性、282 个非目标部件与新 Worker 重开保持，三次 PDF 导出成功且诊断为空。当时整页 Canvas 从 13508/13506 降为 7877/6780，PDF 从 11503/13198 降为 5777/6463；严格零差异继续失败。固定原件、字体、参考与容差未改。该批证据保留原构建身份，当前结果见上方换行批次。样式顺序归[格式合同](formats.md#母版与版式编辑视图)。

C13 第 28 页的图片证据归私有 `nativeWmfPictures`，保留其原构建身份。核心现读取有界 Placeable WMF 的实心多边形与折线，保留有符号窗口映射、对象槽复用、原生填充规则和图片变换。双色效果按次选 LibreOffice 的整数亮度规则处理；主选 ONLYOFFICE 的固定 PDF 未应用该效果。该批 38 项定向核心通过，覆盖 WMF、EMF、浮动图片、PDF 提取及既有 PPTX 图片、主题与表格路径。边界与来源归[格式合同](formats.md#pptx-wmf-图片)。

共享路径直接携带填充规则，取消同一路径的裁剪再填充。Chromium 的独立同向内外轮廓检查确认奇偶填充留孔、非零填充实心，Canvas 与 PDF 均通过。固定 96×112 原图框的双色 Canvas、PDF 对 GenOffice 0.11.727 均为 0/0；去除双色后的原色控制对固定 ONLYOFFICE 仍为 Canvas 2/26、PDF 3/127。此比较只覆盖图片，不授予整页资格。

该 WMF 批次的原件、编辑后和新 Worker 重开均已无诊断，三次 PDF 导出成功。原生输入、精确历史、完整单元格属性和 282 个非目标部件保持。当时整页 Canvas 为 13508/13506，PDF 为 11503/13198，严格零差异断言继续失败；上方字体批次记录当前结果。

本批七条 Chromium 流程共四条通过、三条失败。通过项为独立填充规则、C07 OLE、图片透明度和柔边阴影。失败项为原色 WMF 组件、C13 整页及 C40 原件。C40 保持此前的 Canvas 9/0、PDF 6/0，改后深色背景均为 0/0。原件、固定参考、容差与失败断言保持。构建、MoonBit、私有 TypeScript、格式、lint 和源码上限通过，未跑全仓。

C13 原生表格前批证据归私有 `nativeTablePens`。第 28 页的十行、三列表格现可读取显式边框默认值、无箭头端标和原生下划线。17 项定向核心通过，覆盖直接/样式边框、共享边、文字格式、输入、源保留和非法标记。恢复旧画笔与文字解析规则后，两条旧行高断言仍失败；现按 120% 行距与单元格内边距改为 65.6 pt 和保留 40 pt 源行高。

八条既有 Chromium 回归通过，覆盖普通表格、底色/边框透明度、虚线、剪贴板、表样式、表格及普通文字格式。旧解析路径另复现两项浏览器预期差异：`#1268ac` 在线性 RGB 中保留 40%/20% 的 tint 得到 `#ccd4e3/#e7ebf1`；36 pt 文字按 120% 行距，加 6 pt 段前及上下各 4 pt 内边距，仍容纳于 60 pt 源行。断言按这些既有规则修正后，两条完整流程通过。严格构建、MoonBit、私有 TypeScript、格式、lint 和源码上限通过。本批未重跑 SmartArt 八页或全仓，其既有资格保留原构建身份。

该表格批次已完成原件显示、原生输入、精确撤销重做、282 个非目标部件保留及新 Worker 重开。文字修改保留完整 `tcPr`、`heavy` 和 `uFill`。当时第 28 页 Canvas 为 14393/14074，原图标报告 `Unsupported picture effect`，三次 PDF 导出均失败。该失败基线保留原构建身份；上方 WMF 批次记录当前结果。

本机 GenOffice 0.11.727 的第 7、8、28 页仅用于视觉核对。第 7、8 页保留柔边阴影，第 28 页的下划线使用文字色。单独诊断副本为冻结 PDF 的 117 个缺失透明组的亮度遮罩 Form 补上 `Group`；第 7 页栅格逐字节不变，第 8 页不再报告软遮罩错误，但橙色渐变仍不同。该副本不替换主参考，不参与资格判定。原件、固定 PDF、严格浏览器断言与产品阴影保持；字体映射不同的 App 画面不能充当整页像素预期。

C13 内阴影元数据批次归 `nativeInnerShadowMetadata`。独立原生控制只移除第 23 页正文对象的 `innerShdw`，完整 144 dpi PNG 逐字节复现冻结原件。另两份控制为同一源对象增加实色填充，带/不带内阴影的整页 PNG 也逐字节相同。第四份原生控制只把 `Familiarize` 改为 `EDIT`，其余解包内容保持，供完整编辑页面对照。核心现验证并保留该元数据，沿主引擎二维路径绘制；混合外阴影复制保留直接内阴影。

38 项定向核心通过，覆盖直接/主题属性、外阴影不变、复制、填充与正文编辑、精确历史、重开、元数据数值边界及未知/重复/注释保护。原件 48 页原样保存保持，读取清单已无对象诊断；这项清点不授予整稿视觉资格。同构建七条相关 Chromium 回归通过。第 23 页正常原生输入、282 个非目标部件、完整形状属性、精确历史和新 Worker 的页面图像及 PDF 字节一致通过。第 15 页透明度、第 47 页背景和第 42 页输入流程继续通过。

内阴影前批中，冻结第 23 页字体资源明确为 Carlito 正文、Arial 标记；首轮漏配 Arial 的失败与修正后日志均保留。该批原件第 23 页 Canvas/PDF 为 37470/37187 和 37203/36967，编辑后为 36731/36432 和 36453/36205。正式用例保留十四组整页零差异断言，继续失败。第 41、42、47 页及编辑后第 42 页的整页 PDF 仍为 0/0，其余十组既有比较保持。原生操作流给出第 23 页首行基线 172.35 pt，SDK 为 174 pt；这项基线缺口现由上述固定行距批次补齐。原件、冻结参考及容差未改，其他 C0 视觉/格式缺口保持，未跑全仓。

C13 空列表标记前批证据归 `nativeEmptyListMarkers`。冻结第 47 页在空段标记中心为背景色 `[211,242,220]`，前批 SDK 多画了黑点；普通标记中心两者均为黑色。独立原生控制只将该空段的 `buChar` 改为 `buNone`，其余 XML 和解包部件保持，整页 144 dpi PNG 逐字节复现冻结原件。核心保留原列表与测量，只省略空段绘制。

35 项定向核心检查通过，覆盖字符、编号和图片空列表、原始多字符符号、测量缓存、行高/宽度、续号、重新输入、资源、精确历史及保存重开。三项既有用例扩展了这些行为，原实现下均失败。构建、严格 MoonBit、格式、登记和源码行数检查通过。七条 Chromium 回归通过；第 15 页透明度、第 47 页背景编辑、281 个非目标部件、3D 源、精确历史和新 Worker 重开继续通过。

第 47 页整页 PDF 从 117/71 降至 0/0，Canvas 为 426/500，严格原件用例仍失败。第 15 页 Canvas/PDF 仍为 1810/1714 和 1792/1744。原件第 41、42 页及独立原生编辑后的第 42 页整页 PDF 仍为 0/0，既有 Canvas 残差保持。十组完整页面对照及零差异断言保持，原件、冻结参考和容差未改。全稿仍有一处对象 `effectLst` 诊断及其他格式/视觉缺口，未授予完整 C0 资格，未跑全仓。

C13 对象直接 3D 元数据前批证据归 `nativeObject3DMetadata`。固定原生控制只移除第 15 页及第 47 页 SmartArt 缓存的 34 个 `scene3d/sp3d` 节点，两张完整 144 dpi PNG 均与冻结原件逐字节相同。当前读取验证并保留已支持的场景、材质、斜面和轮廓，沿原生二维路径绘制。32 项定向核心通过，覆盖源保留、外阴影、复制、透明度、精确历史、保存重开与未知/重复/注释/非法数值保护。48 页原样保存保持，17 处直接 3D 诊断已消除，剩一处对象 `effectLst`。

七条 Chromium 回归通过。正常 Worker 已验证第 15 页透明度、第 47 页背景修改、281 个非目标部件、直接 3D 源、精确历史和新 Worker 的页面图像一致。原件第 15、47 页整页 Canvas 为 1810/1714、541/570，PDF 为 1792/1744、117/71，严格原件用例保持失败。第 41、42 页及独立原生编辑后的第 42 页整页 PDF 仍为 0/0，原有 Canvas 2/0 和 3/4 保持。该批有十组完整页面对照，没有裁剪、参考或容差变更。第 47 页缓存正文现能绘制，SmartArt 缓存编辑仍按既有保护；整稿和全部 C0 未完成，未跑全仓。

C13 字符项目符号前批证据归 `nativeCharacterBulletPrefix`。第 47 页四个 SmartArt 缓存文本框含十六处 `char="••"`。独立原生控制只将它们改为单点，其余解包内容保持，整页 144 dpi PNG 与冻结原件逐字节相同。核心按原生首个 UTF-16 单元解析，同时保留完整源属性；写入接口仍要求单个字素。23 项列表、导入、段落与效果定向检查通过，覆盖中性多字符/组合字符源、编辑、保存重开、精确历史及空值、控制符、超长和无效首单元保护。48 页原样保存保持，字符列表诊断已消除。四个文本框仍因直接 `scene3d` 受保护；当前清单为十七处对象 `scene3d` 和一处对象效果。第 47 页尚未取得可编辑或视觉资格，全部 C0 仍未完成。 本批构建、严格 MoonBit 检查、格式、登记、源码行数及 1340 个本地文档链接检查通过。七条 Chromium 回归通过；原件第 41、42 页及编辑后的第 42 页整页 PDF 仍为 0/0，Canvas 仍为 2/0 和 3/4，严格原件用例保持失败。未跑全仓。

C13 图片项目符号批次归 `nativePictureBullets`。原件第 42 页使用 15×15 和 12×12 的两张 GIF，十二处标记现复用既有图片解码。固定原生 PDF 的图片矩阵、24 pt 字号及正文坐标独立验证约 16.82498 pt 高度、比例、首行位置和基线。共享图片标记不占正文或光标范围，首行、换行、RTL、缓存、资源校验及坐标移动已有检查。图片关系按源部件读取，跨文稿导入使用待提交资源，保持精确历史和保存重开。支持范围归[格式合同](formats.md#pptx)。

50 项 PPTX 与 18 项共享布局定向核心通过，另有三项宿主边界检查通过。核心覆盖原件、长方形图片、文字替换、清除/移除列表、跨文稿图片映射、源保留、精确历史、非法或外链关系和未知标记。七条 Chromium 回归通过，覆盖 PPTX 普通列表/标记样式、DOCX/PPTX 全角及圆圈编号、形状阴影、母版文字和主题字体。共享标记首轮的固定文字没有换行，缩窄中性页宽后覆盖换行；缺图检查改在与既有图片相同的绘制序列化边界执行，准备失败日志保留。

图片列表批次的原件第 41、42 页整页 PDF 均为 0/0，导出诊断为空。Canvas 分别为 2/0 与 3/4，严格用例仍失败，原件、冻结参考及容差保持。第 42 页图片列表的正常原生输入、十二处标记源码、282 个非目标部件、精确历史及新 Worker 的 Canvas 和完整 PDF 栅格一致检查通过。独立原生控制只把原件的首个 `English` 改为 `EDIT`，其余解包内容保持；改后整页 PDF 为 0/0，Canvas 仍为 3/4，完整视觉资格未授予。48 页原样保存保持，图片列表诊断已消除，仍有十三处对象 `scene3d`、一处对象效果及四处字符项目符号诊断。整稿、其他残差及全部 C0 仍未完成；未跑全仓。

C13 平面主题元数据前批证据归 `nativeFlatThemeMetadata`。固定原生转换器只移除主题第三效果样式的场景与顶部斜面，其余解包部件保持；第 41、42、44 页原样重导、独立控制和冻结 PNG 分别逐字节相同。核心现验证并保留支持范围内的正面相机、灯光和顶部斜面，按原生路径使用外阴影，不创建 3D 投影。非平面、扩展和对象自身的 3D 继续保护，合同与来源见[格式合同](formats.md#pptx-外阴影)。

37 项定向核心通过，覆盖正常源、缺省值、边界、非法数值、重复/未知节点、注释、非目标主题部件和精确历史。三条形状阴影、母版文字及主题字体界面回归通过。第 41 页已成功导出完整 PDF，与冻结原件为 0/0；整页 Canvas 为 2/0，残差坐标为 (1077,1021)、(1078,1021)，严格验收仍失败。第 42 页 Canvas 为 28891/54257，PDF 只由两处图片列表保护阻断。原生正文输入、282 个非目标部件、精确历史及新 Worker 重开完成；编辑后与新 Worker 的完整 PDF 栅格一致，不据此授予改后原生视觉资格。

48 页原样保存保持，三处主题 `scene3d` 诊断已消除。对象 `scene3d` 十三处、对象效果一处、图片列表两处及字符项目符号四处仍在。初次负例因未声明测试命名空间中断，改为合法未知命名空间后保持保护，原日志保留。构建、严格类型、格式、lint、补丁、注册及源码上限通过。此前椭圆批次的 SmartArt 与曲面图证据保留其构建身份，本批未重复；未跑全仓，整稿与全部 C0 仍未授予资格。

C13 椭圆正文与曲线描边前批证据归 `nativeEllipseText`。第 41 页按最近一级完整描边合入主题默认值，恢复原生蓝色 0.75 pt 轮廓。椭圆使用内接文字矩形；未给缩放值的普通适配按 100% 读取，编辑时继续重算。原生 PDF 的线宽、颜色、28 pt 字号、六行换行及首行坐标分别用于独立检查。只描边的曲线阴影复用共享有界轮廓，平滑凸曲线保留内孔，真实拐角、反向控制点和资源上限均有检查。

35 项 PPTX/轮廓、36 项 SmartArt 和 56 项图表定向核心分别通过，部分用例重叠。四条阴影、方向、列和框适配界面回归通过。当前原件第 41 页整页 Canvas 从 62090/62178 降为 4802/0；第 42 页为 34719/54257。两页 PDF 继续因主题 3D 和图片列表拒绝，严格用例保持失败。正文原生输入、282 个非目标部件、精确历史及新 Worker 重开通过。第 45 页 PDF 仍为 0/0，Canvas 仍在 (401,456) 为 1/0。

共享路径复核保持前批结果：SmartArt 八页的十六组整页 Canvas/PDF 对照逐项一致，第 7 页均为 0/0，其余七页仍失败；背景编辑、源保留、精确历史及新 Worker 重开完成。曲面图 12、13 的整页 Canvas/PDF 和新 Worker 通过，图 11 保持原有 0/48，严格用例仍失败。48 页原样保存通过，剩余诊断类别与前批一致。构建、严格类型、格式、补丁、注册和源码上限检查通过。原件、冻结参考、渲染器与容差未改，未运行全仓，整稿与全部 C0 仍未授予资格。

C13 文字效果与空域段落属性前批证据归 `nativeTextEffects`。核心验证并保留空效果列表、支持范围内的文字外阴影及不可见轮廓，绘制遵循 ONLYOFFICE 跳过文字效果记录的行为。独立控制只移除第 41、42 页三个文字框中的十处效果，其余解包内容不变；两页分别与冻结原件及原样重导的 PNG 字节相同。形状阴影继续绘制，未知效果、扩展颜色、非数值属性和带内容的域段落属性继续保护。

第 41 页正文已恢复读取和绘制。十一处圆角标注均无几何或文字诊断。简单页码与日期域现接受单个空 `pPr`，原字段 ID、缓存和源保持；重复、带属性/子元素、注释或处理指令的段落属性仍保留缓存并诊断。42 项定向核心通过，覆盖有效样式、非法输入、格式/源保留、精确历史、动态页码、日期及页脚。三条日期/形状阴影界面回归通过。原件的正文原生输入、282 个非目标部件、精确历史与新 Worker 重开完成。

整页验收仍失败：第 41、42 页 Canvas 分别为 62090/62178 与 34719/57569，PDF 仍因主题 3D 及图片项目符号拒绝。两个标题已读出文字，但主题保护保留；第 42 页两段正文仍由图片列表保护。48 页原样保存保持，原有十五处文字效果诊断已消除，其余对象/主题 3D、对象效果和列表缺口仍在。首次界面检查暴露的空 `pPr` 页码误判已修正，原失败日志保留。没有据此授予整页或整稿资格，冻结输入、参考、容差及零差异断言保持。

C13 第 45 页空文字轮廓与主题字体修复归 `nativeEmptyTextOutline`。三个空 `a:ln` 曾让正文整框拒绝。核心现保留空标签并读取正文，带属性、子元素、注释或处理指令的轮廓仍保护。原始 48 页包与只移除三个空标签的独立原生控制，其余解包内容一致。两份原生导出在 144 dpi 下均复现冻结第 45 页 PNG，三个 PNG 字节相同。

界面测试使用原生实际加载的 Carlito 与 Arial；初次将 Arial 映射到 Carlito 的 496/503 与 495/497 失败保留。加入 Arial 后，标题暴露主题字体引用被继承 Arial 越过的核心错误；该失败同样保留。读取器现按格式链在主/次主题引用和直接脚本字体间选择。28 项定向核心通过，覆盖拉丁、东亚和复杂文字、直接格式、母版、表格、片段、轮廓保护及精确历史。第 45 页整页 PDF 为 0/0；Canvas 在正文边缘的 (401,456) 仍为 1/0，正式用例保持失败，未调整容差或补像素。背景编辑、282 个非目标部件、精确历史与新 Worker 重开通过。两条主题字体和母版编辑界面回归通过。既有轮廓迁移的两处私有调用已改到共享函数；装饰路径与半磅上下标检查保持原数量和独立原生规则。

修复前的同轮 SmartArt 复核仍归前一构建：第 7 页整页 Canvas/PDF 已为 0/0，其余七页继续失败，完整十六组结果保留。该批 48 页清点已消除第 45 页的文字轮廓诊断，其余文字效果、列表、对象效果和 3D 缺口仍在。第 15 页十二个框原本没有正文，不把段末阴影保护误记为正文丢失。C13 整稿与全部 C0 文件仍未授予完整资格。

C13 字号修复的历史批次归私有 `nativeSmartArtFonts`。`hierarchy4` 缓存沿布局与内容关系重算同组字号，保留自定义文字、显式边距及段落行距。第 7、8、11、12 页分别匹配固定原生 PDF 的 30、24、18、17 pt；第 8 页的 `Topic` 已保持一行。36 项 PPTX 定向核心与一项共享表格回归通过，覆盖占位文字、无效属性、关系、容量上限、组变换及既有文字适配。

八条 Chromium 回归通过，覆盖缓存图、空缓存组织图、组内输入、文字方向、列、框适配、直立文字和 DOCX 表格适配。最终构建另重跑缓存图、原生组织图及 C13 八页；前两项的原件和改后独立对照保持 0/0。其余六条复用本批未变路径的结果。恢复旧内联文字布局与默认词宽测量后，两项旧尺寸断言仍得到 114.4 pt 和 478.8 pt。断言现按 120% 行高和 Word 表格外边距更新；输入、精确历史、保存重开和 PDF 检查继续通过。严格构建、MoonBit、私有 TypeScript、格式、lint 和源码上限通过，未跑全仓。

C13 八页的背景编辑、源保留、精确历史和新 Worker 重开保持。原生 PDF、原件与字体字节未变，十六组完整页面颜色对照仍未达到 0/0。第 8 页 Canvas 由 32231/32227 降至 2090/4961，第 11 页由 33826/33573 降至 4375/9082。原生参考第 8 页的一处渐变阴影软遮罩指向缺少 `Group` 字典的 Form，已另存对象证据；第 7 页只用普通透明度，没有该软遮罩。此问题不能解释所有差异，也未用于修改参考或降低断言。渐变、阴影和其他布局继续核对。

C13 独立 SmartArt 文字框的首批证据归私有 `nativeSmartArtTextFrames`。原件第 7–14 页共九个缓存图，独立偏移和尺寸不再阻断读取。33 项定向核心检查覆盖原件文字框、缩放、直立裁剪、非法输入、组变换与既有文字布局。自动适配直接查找可容纳文字的整数 EMU，避免浮点上界多取一单位；旧直立文字预期按现有 120% 自动行高更新。原实现的尺寸失败另存，未归为本次回归。

正常 UI/Worker 已逐页显示这八页并导出单页 PDF。背景编辑、精确撤销重做、全部非目标部件保留和新 Worker 重开通过。固定原生 PDF 的十六组完整页面颜色对照均已执行，均未达到 0/0，严格用例继续失败。该批第 8 页直接采用缓存声明的 31/25 pt，原生 PDF 正文为 24 pt，字号和换行当时仍有差异；原生 PDF 另报告 `Invalid soft mask in ExtGState - missing group`。参考字节和容差保持，不据此删去产品阴影。现有缓存图、空缓存组织图和直立文字的三条 Chromium 回归通过；前两项的独立原件/改后对照保持 0/0。严格构建、MoonBit 检查、私有 TypeScript、格式、lint 和源码上限通过，未跑全仓。

同批保留 C02 虚线椭圆的设备坐标重放诊断。当时原件和修改后 Canvas 为 1/2，SDK PDF 为 0/0。当前共享描边修复后的完整流程已为 0/0，归 `nativeCubicStroke`。仅把虚线路径变换到设备坐标仍为 1/2，变换全部描边则为 1/5；均未接入产品，原断言保持。临时探针已移出正式浏览器用例，脚本、对照和失败记录保留。

共享曲线描边、两张雷达、C02 与双轴折线的当前通过证据归私有 `nativeCurveStrokeOutline`，前批细分证据归 `nativeCubicStroke`，前批底色证据归 `nativeDualLineRectangleFill`，前批边框证据归 `nativeDualLineDashedFrame`，打印证据归 `nativeDualLinePrint`，绘制证据归 `nativeDualLinePaint`，全图清点归 `nativeDualLine`，上一批归 `nativeBubbleLegend`，圆形批次归 `nativeCircularCharts`。19 张原生图表现已全部可读取：主折线、双轴折线、双轴散点、三维柱图、零旋转堆积条图、饼图、百分比面积、零旋转三维堆积面积、圆环图、两张雷达、两张气泡图、三张曲面图、两张复合饼图与柱线混合图。这是读取清点，不证明整份 C43 完整通过。两张圆形图表的独立参考已在产品修改前保存：仅显式替代为固定 Arimo，其他缓存工作簿部件逐字节保持；控制沿用既有原生图表页框。圆环图原始 XML 实有四个系列，先前“五环”描述已更正。

三维柱条图当前证据归 `nativeBar3dStroke`，投影修正归 `nativeBar3dProjection`，首批归 `nativeBar3dCharts`。独立参考、原件和容差保持。全部 388 个控制面已匹配坐标、RGB、顶点顺序和绘制顺序。三维面尖角描边限制从 8 修正为原生 PDF 的 10；其余路径保留原限制。原件缓存零值和已解析控制空值分别保持。27 项定向核心检查通过，新增原生端头、连接和尖角限制断言；修正前的尖角断言失败。正常 Worker 原样保存和新 Worker 重开通过，两图分别保持相同 PDF 字节。同构建十条 Chromium 流程九条通过，包含堆积条图、面积、32 系列边界、双轴折线、两张雷达及共享曲线和菱形回归。堆积条图完整 Canvas/PDF 保持 0/0。透视柱图 Canvas 从 75/130 降至 0/130，整页 PDF 从 73/125 降至 0/125，严格断言继续失败。主参考将有效系列轴标题放在页面原点，产品保留该源标题；抽样仍有五个 Canvas 柱边缘位置，其余差异尚未全部归因。位置抽样不能证明差异仅来自标题。共享直线描边试验未改善原件，已撤回。补充证据归 `nativeBar3dCoverage`。回放与产品 PNG 字节一致，五处边缘位置最后均由同一浅紫色侧面描边覆盖；对应参考的 3×3 邻域全黑，产品仍有浅色细缝。源线宽与独立 PDF 均为 1 pt，具体栅格原因仍待核对。同一控制文件的 LibreOffice 补充输出把有效系列轴标题保留在图框内；其字体有替代，只证明标题行为分歧。chart7 三维面积的独立原生参考已在实现前固定，本批读取与绘制结果见下。源改写、复制及手工计算保护保持。该柱图构建的读取清点为十二张可读、七张保护；当前读取清点见下。未跑全仓，完整 C43 与 C0 继续开放。

双轴散点前批证据归 `nativeScatterCharts`。修改前冻结原图定义，仅替代固定 Arimo，其余缓存工作簿部件逐字节保持。五个系列、逐点样式、四个数轴标题及共同数字 X 接入共用折线路径。25 项定向核心检查覆盖原始锚点、源保存、非等距 X、范围外标记及非法来源；曲线首点和右标题在 0.001 pt 内匹配独立 PDF。正常 Worker 的原样保存、打印与新 Worker 重开通过，新旧 PDF 字节一致。同构建六条 Chromium 流程五条通过：面积、32 系列边界、双轴折线与两张雷达保持原断言通过。散点的严格整图断言仍失败，Canvas 从 2792/3985 降为 303/378，整页 PDF 从 2745/3982 降为 306/404。主参考未显示单系列 `varyColors` 组的逐点标记，产品保留实际源标记；该批差异尚未全部归因。当前 Canvas 完整归因见后文 `nativeScatterFullResidualAudit`，不替换预期或修改容差。该批全十九图读取清点通过，当时原件完整工作表先受三维柱图保护。完整 C43 与 C0 均未通过。

前批散点参考复核归 `nativeScatterSparseAudit`。当时重跑原严格用例，Canvas 为 303/384，PDF 为 306/404。新增的六个 Canvas 差异已定位到首个正数 `1 / x` 点的青色 X，不是源标记路径顺序改变。新旧不可变绘制指令分别配合两种通用直线描边策略重放，只有轮廓策略使额外像素从 378 变为 384，缺失像素始终为 303；正常重放 PNG 与当时产品逐字节相同。六点均由同一青色描边覆盖，主参考对应区域却为品红色。

原生独立控制只将工作表 E2 的错误值改成图表缓存已有的零，图表 XML 和其他部件逐字节保持。固定 ONLYOFFICE 在首个正数点绘制完全相同的路径和坐标，却从前一系列的品红填充/描边恢复为源青色描边。全部六个新增像素通过这一独立控制的原有颜色阈值。新增一项核心检查通过：缺首点与显式零分别绘制 25/26 个源青色 X，后续点坐标完全相同，首个正数点在 0.001 pt 内匹配原生。检查保留源输入字节。

固定上游[散点绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L14845-L14935)和[标记画笔选择](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L3040-L3084)存在按位置压入路径、按点编号取样式及沿用旧画笔的组合。它解释了可能机制；已交付转换器的实际表现由上述原生控制证明，不把静态源码当成二进制执行证据。补充 LibreOffice 在相同输入上保留 X 形和逐点标记，但采用系列线色、字体替代及不同轴布局，不能授予颜色或整页资格。

另一独立诊断仅把零值控制的 `varyColors` 从 1 改为 0，保留全部显式逐点定义。主参考绘出更多标记，却仍把不同源形状画成统一三角；该诊断严格比较仍为 Canvas 116/75、PDF 117/80。两项浏览器归因检查通过，不授予整张散点资格。产品、原始错误、原始图表定义、原始严格用例和阈值保持；完整散点及其余 C43/C0 视觉失败继续处理。前批手工计算的 54 项核心及五条浏览器结果沿相同产品字节复用，本批未重复全 C0。

透视柱图完整余差复核归 `nativeBar3dFullResidualAudit`。相同正常构建重跑两条原严格流程，堆积条图完整 Canvas/PDF 保持 0/0，透视柱图保持 0/130 和 0/125。重新比较全部像素后，Canvas 的五个柱边差异与另外 125 个标题区域差异分开。PDF 的全部 125 个差异都在对应标题区域；其中 122 个坐标与 Canvas 的标题余差相同。五处柱边在正常 SDK PDF 和原生 PDF 中均为黑色，Canvas 留有色缝。

独立 PDF 副本分别隔离该侧面、移除该侧面、代入 SDK 精确坐标，并交叉原生/SDK 等价变换及序列化线宽。孤立侧面在这些坐标控制中均保持黑色，排除坐标或线宽舍入及矩阵分解作为五处色缝的解释。全部 388 个面的通用描边轮廓诊断仍为 Canvas 0/130。该试验只触发现有轮廓算法，没有改变非退化几何、实际线宽、源文件或原生参考。产品未修改；五处 Canvas 覆盖和有效标题的原生分歧继续保留，未授予原件资格。

当前构建的五处柱面接缝归私有 `nativeBar3dSeamRasterRoutes`。ONLYOFFICE 直接导出的 PNG 与 SDK Canvas 在五点最多相差五个色阶。以 Cairo 栅格化原生及 SDK PDF 时，五点分别逐值相同。按两道描边之间的实际未覆盖面积复算，原生直接 PNG 和 Cairo 的最大通道误差均为一级。同一原生 PDF 经冻结的 Splash 路径栅格化时，这五点是纯黑。

两条正式 Chromium 用例复跑。堆积条图通过，透视柱图仍为 Canvas 0/130、PDF 0/125。两图的 SDK 和参考栅格与先前结果逐字节相同。直接 PNG 全图仍有差异，这次只确认五个接缝点的原因。

固定 ONLYOFFICE 另用工作区绘制入口直接输出两张原始尺寸图表。堆积条图的工作区输出对 SDK 和冻结打印栅格均为 3556/52。条形边沿可见原生工作区的小数覆盖，SDK 与打印栅格落在整像素行。透视柱图的工作区输出对 SDK 为 446/1164，主要差异涉及右侧边线、轴标题和细线。两条正式用例仍复现 0/0 与 0/130、0/125。工作区结果单列，沿用原严格测试和冻结参考。证据归私有 `nativeBar3dSeamRasterRoutes.workspace`。

散点完整 Canvas 归因续批归 `nativeScatterFullResidualAudit`。正常重放与产品 PNG 逐字节相同，全部 303/384 个差异像素覆盖 526 个坐标。首个稀疏点的错误着色对应 88/62 个；次轴组缺失的源标记对应 203/300 个；图例标记对应 12/22 个。三类覆盖全部差异坐标，没有未归类坐标。此归因只针对已记录的 Canvas 输出，不把整页 PDF 的 306/404 个差异自动归入同类。

独立原生控制仅把五个系列及逐点定义的 28 个标记符号设为 `none`。曲线、数据缓存、工作表错误、轴、文字、线条及其他包部件保持。相同产品构建的完整 Canvas 和整页 PDF 均为 0/0；原样保存和新 Worker 重开保持相同 PDF。该控制验证不带标记的完整图框几何，不替代原件或其严格断言。原件仍为 Canvas 303/384、PDF 306/404；全部标记及完整 C43/C0 仍未取得视觉资格。本批没有修改产品代码。

前批散点标记复核归私有 `nativeScatterCurrentMarkerAttribution`。同一无标记对照的完整 Canvas 和整页 PDF 为 0/0，原样保存和新 Worker 重开通过。当时正式原件 Canvas 的 291/363 与 PDF 的 294/380 全落在绘图区的标记范围内。首个稀疏点在两种输出中均为 88/62，其余均落在 SDK 次轴逐点标记范围内。该批正式原件仍失败；后续通过结果见[本页入口](#当前兼容证据入口)。

散点标记描边归私有 `nativeScatterMarkerOutline`。原生对照只改首系列的描边。固定 ONLYOFFICE 的 PDF 对 26 个菱形和一枚图例标记分别保留 2 pt、0 pt 或无描边。省略描边节点会改用主题色。旧解析拒绝 2 pt 和 0 pt，修复后 10 项定向核心检查通过。

独立整页对照从无标记控制恢复首系列的菱形。三份 PDF 均为 0/0。散点图区沿原生保留菱形左侧开口后，2 pt Canvas 从 1/0 降至 0/0，无描边 Canvas 保持 0/0。0 pt Canvas 仍为 0/5。首轮共用开口路径令双轴折线图新增 6 个 Canvas 差异。限定到散点图区后，双轴折线图、混合图和两张雷达图均为 0/0。各控制保留源字节，新 Worker 导出相同 PDF。正式散点原件 Canvas 为 290/362、PDF 为 294/379，严格视觉仍失败。

C43 原件导出 15 页，保留源字节与 18 个绘图对象，qpdf 结构检查通过。最终仅第 5 页的 SDK 栅格变化，Canvas 从 1182/1303 变为 1185/1303，PDF 从 1057/1194 变为 1057/1192。其余 28 张 SDK 栅格及全部参考栅格逐字节相同。30 组严格比较仍通过 10 组。

零宽描边的设备行覆盖归私有 `nativeScatterMarkerOutline.hairlineReplay`。独立字面 PDF 覆盖反射、横竖斜线、闭合路径和画布边缘。整数及 PDF 两种 Canvas 策略的灰度值逐像素相同。原生散点的三份隔离控制现在全部为 Canvas/PDF 0/0，保存源字节和新 Worker 导出一致。原件散点仍为 Canvas 290/362、PDF 294/379。C43 的 30 张实际栅格、参考栅格及整表 PDF 字节与上批一致，严格通过 10/30。14 条共享 Chromium 用例通过 13 条。半透明菱形在启用和停用新路径时均在同一断言失败。四条气泡图用例复跑通过。

主题描边继承归私有 `nativeScatterMarkerOutline.themeOutline`。三个独立原生控制分别核对默认主题 0.75 pt、按源 `idx` 选中的自定义主题 1.5 pt，以及只改填充的点保留系列 2 pt 描边。三个整图 Canvas 和整页 PDF 均为 0/0，源字节和新 Worker 导出的 PDF 字节保持。11 项核心和 7 条 Chromium 用例通过，包含双轴折线、混合图和两张雷达图。C43 整表 30 张实际和参考栅格及 15 页 PDF 与上批逐字节相同，仍通过 10/30。原件散点仍为 Canvas 290/362、PDF 294/379。

单系列逐点配色的描边归私有 `nativeScatterMarkerOutline.pointOutline`。固定 ONLYOFFICE 的图例显示系列蓝色 2 pt 和逐点红色 1.25 pt。LibreOffice 的绘图区确认同一点由蓝色改为红色。两个引擎都省略了控制文件明确指定的黄色标记填充，因此整页原生比较用于诊断。正常 Worker 的三个控制验证 2、1.25 和 1 pt 描边、Canvas/PDF 黄色填充、原样保存及新 Worker 的 PDF 字节。11 项核心和 5 条 Chromium 用例通过。原件散点的 Canvas、PDF 和参考栅格均与上批逐字节相同。C43 整表复跑仍通过 10/30，30 张实际栅格及 15 页 PDF 与上批逐字节相同。

单系列散点的逐点图例归私有 `nativeScatterMarkerOutline.pointLegend`。原生控制核对源点编号、缺失点留空和显式逐点样式。三种右侧尺寸分别容纳 20、13、26 项，底部控制在第 15 项后换行。12 项核心检查通过。旧构建的 PDF 只显示系列名，新构建的三份 PDF 各匹配原生的 20 个图例编号，原样保存和新 Worker 的 PDF 字节一致。原始双轴折线和混合图通过。原件散点仍有视觉差异，C43 整表严格通过 10/30，30 张实际和参考栅格及 15 页 PDF 与前批逐字节相同。

圆形图表已接通缺省分类、标题、右侧图例、标签、扇区填充与轮廓、旋转及外环爆炸偏移。原始两个锚点分别读取和绘制，源字节保持；全隐藏时保留背景与标题。22 项定向核心、公共扇区接口示例及三条相关 UI 回归通过。两个固定控制均通过正常 Worker 打开、打印、源保存和新 Worker 重开，活动图表不再有未呈现诊断；非活动数据表的既有诊断仍保留。圆形批次的原工作表整组读取当时在 `chart2.xml` 的重复 `lineChart` 失败；下述双轴批次已消除该处失败，完整工作表仍受其他图表保护。

圆形图区背景现已修正为居中正方形，缺失点图例沿所属主题取色，图案标记使用局部原点。22 项核心和三条相关 UI 回归通过。完整可见图框的 Canvas 与整页 SDK PDF 对照仍失败：饼图现为 Canvas 232/4970、PDF 227/4693；圆环图为 Canvas 11979/10235、PDF 540/319。未修改容差或原始断言。原生 PDF 的饼图图案扇区只有 `scn` 和 `f`，缺少填充路径；同输入、同字体的直接原生 PNG 也省略该扇区底纹。SDK 保留实际源图案，两张图及整份 C43 均未授予资格。

圆环底纹的完整诊断区分直接 PNG 与 PDF 栅格。固定原生 PDF 的纹理每 7 像素重复；同输入的直接原生 PNG 和 Canvas 保留 7.44 像素周期。缩小纹理平滑采样后，圆环 Canvas 对直接原生 PNG 的完整图框差异从 14520/8370 降为 323/299。PDF 与直接 PNG 自身相差 9861/11864；该诊断解释取样差异，不替换原始严格断言。标签、边界和剩余像素继续核对。当前包、完整失败图像及诊断归私有 `nativeCircularPlotAndLegend`，旧 `nativeCircularCharts` 保留原包身份和失败。

零旋转三维堆积面积的当前布局结果归 `nativeFlatArea3dProjection`，初步失败归 `nativeFlatArea3dInitial`。原始 chart7 保留四个系列、26 个分类、全部实色面及只读源保护。手工外绘图区现按分类数收缩纵向范围，分类标签占用留量；三维标题使用最终 17 像素边距。28 项定向核心检查全部通过，包含原始锚点、保存重开、六项非法配置、独立首面坐标及三组仅改字号的原生控制。原件图表缓存的首个黄色系列值为零，但绑定 E2 实为 `#DIV/0!`；冻结的原生错误值控制省略黄色面，且使用 450 上限。只将该单元格改为数值零、其他部件逐字节保留后，所有缓存与绑定值一致；独立原生输出恢复 25 个黄色面并使用 500 上限。该诊断件的正常 Worker 完整 Canvas 与整页 PDF 均为 0/0，原样保存、新 Worker 重开和相同 PDF 字节通过。同输入 LibreOffice 补充输出也显示黄色系列；其字体替代与三维布局不同，只证明有效源系列的保留行为，不能替代主参考。原始错误值控制的完整严格断言继续失败，当前数值见私有记录；未改原件、原始参考或容差。同构建八条原始 Chromium 流程为六条通过、两条失败；百分比面积、32 系列边界、堆积条图、双轴折线和两张雷达保持通过，透视柱图保留既有严格失败。该面积图构建的读取清点为十三张可读、六张保护；当前曲面结果见下。显式零值诊断不授予原始错误值文件、完整 C43 或 C0 视觉资格；未跑全仓。

气泡图的打印检查范围修正归 `nativeBubblePrintScope`。旧用例把 0.93 倍屏幕 Canvas 与打印 PDF 裁剪作零差异比较。独立原生 PDF 的图框宽度为 940.790 px，屏幕同一源框仅为 902.150 px；仅将工作簿默认字体统一为 Noto 后，原生打印仍为 911.842 px。该跨缩放断言不能证明屏幕正确性，原测试源码、图像及失败记录完整保留。正式屏幕检查继续使用未修改 SVM 的完整 2448×650 原生视口，全部断言保持；打印用例只比较独立整页 PDF，并新增原样保存后新 Worker 导出的 PDF 字节一致检查。四条用例仍为一条通过、三条失败，未增加任何视觉通过资格。

相同构建的两张原始打印 PDF 仍为 47603/48128 与 45229/45458；新 Worker 的保存字节、对象与 PDF 一致检查通过。仅改默认字体的独立控制，PDF 为 18078/17544，旧跨缩放 Canvas 诊断为 15700/11313。早期 secondary 身份文字声称所有 Arial 声明都已替换，实际只替换了图表声明；工作簿默认字体仍为 Arial Cyr，其原生回退字体未确立。SDK 当前打印缩放为 0.62，独立原生图框反推约为 0.64656，统一默认字体后约为 0.62666；该推算只定位拟合差异，未确立根因。打印原点、尺寸与边界继续核对，不据此修改共享分页或源内容。

原生气泡文字的位图诊断归 `nativeBubbleGlyphBitmaps`。相同构建重跑两个完整原生视口，chart14 在保存前及新 Worker 重开后保持 0/0，chart15 均为 4/4。逐次绘制重放与正常产品 PNG 字节相同；四个缺失点与三个额外点最后由数字 `6`、`4` 和图例 `cos2` 的 `o` 绘制；另一个额外点 (899, 298) 位于图例圆形标记的描边边缘，不能归因于字形。两份固定原生 SVM 各自重放，PNG 均与冻结参考逐字节相同。随后只删除非文字绘制动作，保留全部字体、原点、字距、变换、状态和裁剪；同版 LibreOffice 与相同 Noto 字节直接导出完整文字页。SDK 也只滤除非文字绘制，全部字形指令保持。完整文字页的独立颜色对照分别为 0/0 与 4/3，说明有图例残差存在于字形覆盖。透明 PNG 导出曾得到全黑页，已拒绝；当前使用经目视核对的白底文字位图。新增诊断通过，原产品、原图、原参考与严格阈值保持；这些结果不授予有图例视口或气泡打印资格。下一步处理气泡打印的默认字体及图框拟合，暂不重复 hinting、原点或裁剪候选。

三张原生曲面图的当前结果归 `nativeSurfaceContour`，布局依据归 `nativeSurfaceMargins`，首批归 `nativeSurfaceInitial`。chart11 透视曲面、chart12 俯视等高线与 chart13 线框曲面的独立 PDF/PNG 在产品修改前固定，仅替代 Arimo 字体。矩形缓存、缺省分类与系列名、源引用、视角、墙面及手工图框保持；切分沿原生对角线与数值区间，标签先预留空间再投影。独立首面、旋转标题与三组标题/字号控制坐标误差小于 0.001 pt。源改写、复制及非法配置继续保护。

填充色带现在复用 MoonBit 的现有描边轮廓，分开输出面填充与边框填充。该轮廓从 PPTX 阴影目录移入共享布局层，PPTX 调用同一实现。顶点、线宽、端头和尖角限制保持；正常 Canvas 不再自行扩宽色带边框。等高线交点的单像素差异已消除，chart12 完整 Canvas 与整页 PDF 均为 0/0；chart13 继续为 0/0。两图的原样保存、新 Worker 重开及相同 PDF 字节通过。chart11 完整 Canvas/PDF 仍为 0/48；有效系列轴标题 `YYY` 保留，主参考把它放在图框外的页面原点，该严格失败继续保留。原件、参考和容差保持。

同构建 56 项图表/计算核心与四项 PPTX 阴影检查通过；新增独立直角轮廓检查覆盖端头、尖角、曲线拒绝及输出预算。三条曲面浏览器流程两条通过、一条严格失败。五条相关正常 UI/Worker 流程通过，覆盖主图、混合图、数据编辑、显式重算、精确历史及新 Worker 重开。旧 55/56 核心结果来自测试仍按已替换的画笔字段查找填充面，独立坐标预期保持后复跑为 56/56。未运行全部 22 条图表流程或全量 C0；其他已记录视觉失败及重算后的完整视觉继续开放。

两张复合饼图的首批结果归 `nativeOfPieInitial`。产品修改前已冻结 chart16 条形复合饼图与 chart17 饼形复合饼图的原生 PDF/PNG；其他工作簿部件逐字节保持，仅替代显式字体。主参考把两图转换成普通饼图；同字节 LibreOffice 补充输出显示第二图，但仅采用末尾两点，未执行原件的数值阈值或自定义点集，也未保留全部尺寸和线型设置。两套参考均保留。SDK 现按原件阈值或源点编号拆分，保留第二图比例、间距、逐点颜色、聚合扇区及实线/虚线连接；隐藏后仍使用原点编号。第二图避让手工图例，修正前新增留量检查失败，修正后通过。32 项定向核心全部通过，另有两项字面检查覆盖严格阈值、隐藏编号、条图矩形及连接端点。拆分语义已有证据，间距当前按第二图宽度解释，完整 Office 布局仍待独立核对。正常 Worker 的打开、打印、原样保存及新 Worker 重开通过，两图分别保持相同 PDF 字节。与原生普通饼图的完整 Canvas/PDF 严格对照均失败；未替换参考或降低断言。首批同构建十条 Chromium 流程四条通过、六条失败，折线、两张雷达及线框曲面的 0/0 保持；圆形图与另两张曲面的既有严格失败继续保留。源重写和复制、未知拆分规则及拆分图数据标签/爆炸偏移仍受保护。该复合饼图构建当时为十八张可读、一张保护；当前清点和整表流程见下述混合图结果。完整 C43 与 C0 尚未通过，未跑全仓。

柱线混合图的结果归 `nativeMixedInitial`。修改产品前已冻结 chart18 的独立原生 PDF/PNG，仅替代显式字体，其他工作簿部件逐字节保持。SDK 保留三组柱体、两组右轴折线、源簇内位置、绘制顺序、逐点颜色及三角/X 标记。独立绘图区与四种柱体首面坐标误差小于 0.001 pt。34 项定向核心全部通过，包含两套轴、隐藏原点编号、非法配置、只读复制保护及原样保存重开。原始工作表的十八个对象均按源尺寸绘制，视口不再因三维图例越界拒绝。480×369.75 pt 的独立原生控制证明手工图例应移回图框；共享边界修正另通过一项字面检查。

固定图框和 Arimo 替代的 chart18 控制，完整 Canvas 与整页 SDK PDF 均为 0/0，源保存及新 Worker 重开保持相同 PDF。最初 Canvas 的一个差异像素已通过字节相同的绘制重放定位到青色 X 标记。修正源路径顺序后差异仍在；复用共享描边轮廓后消除。直线轮廓仅扩展至无填充的开放路径，闭合及带填充直线保留既有覆盖规则；早期回归失败完整保留。12 条共享 Canvas 流程通过，其中 66 组直线/曲线变体与 31 组独立轮廓几何检查通过，覆盖透明度、变换、虚线、裁剪及预算回退。原件默认打开、切表、主图显示/打印、原样保存及新 Worker 重开通过；缓存查询在编辑器接管 Worker 前完成，避免测试绕过编辑器队列。十九张原件现全部可读取；这不授予整份 C43 或手工易变公式重算资格。同构建的 22 条图表流程为 10 条通过、12 条严格视觉失败；百分比面积、堆积条图、双轴折线、两张雷达、线框曲面和无图例气泡的既有通过范围保持。另有五条跨格式原件/编辑回归通过。散点 Canvas 现为 303/384，额外像素较本批描边修改前增加六个；PDF 保持 306/404。该批差异当时未归因，当前新增六点的参考样式原因见 `nativeScatterSparseAudit`；严格失败及前后结果均保留。复合饼图的额外像素也按当前产物记录，不声称全部失败计数不变。

手工计算的当前证据归 `manualCalculation`。54 项定向核心通过，覆盖原件缓存、普通输入、新公式、共享/跨表依赖、显式计算、十九张图表缓存、精确历史和重开，也复查隔离公式、自动 RAND、链接、公式视图及图表打印。C43 原件的三次数据输入保留全部源缓存，随后一次重算更新十九张图表；缓存数据点外的图表 XML 逐字节保持。未知公式和无熵计算失败保留源与历史；拒绝计算后原重做仍有效。源缓存和公式依赖保留分别核对。

固定 ONLYOFFICE 对原件 A2=2 的显式重算，与 SDK 的全部 104 个非随机公式格一致，绝对误差不超过 1e-10；26 个随机结果分别落在源基础值加 `[0,10)` 的区间，随机序列不要求相同。中性文件在实现前固定，含共享、跨表、链接和错误缓存。主参考虽然保存手工模式，打开时仍重算 RAND；LibreOffice 的 never/always 导入也均取样并移除手工模式。它们不授予手工缓存保留资格，原始输出和失败保留。核心直接对照输入缓存与源字节。

同构建五条 Chromium 流程通过。默认 UI 在中性文件及 C43 原件中执行公式栏输入、点击“立即重算”、两轮精确撤销/重做和新 Worker 重开。原件主图、混合图及混合图修改固定控制继续通过，后两者完整 Canvas/整页 PDF 均为 0/0。纯数值控制继续即时更新；含公式来源的手工图表等待显式重算。原件功能流使用显式 Noto 字体映射，不授予原件重算后的整页视觉资格。十二项原有严格图表失败继续保留；散点新增六点的参考样式原因见 `nativeScatterSparseAudit`；本批未重跑完整图表视觉集合和全 C0。

重算后的整本导出归私有 `nativeC43RecalculatedWorkbookPrint`。两条手工计算流程现由 `test:c0-xlsx` 收录，在固定 Arimo 下通过。C43 改写 A2 后显式重算，默认文件菜单导出 16 页。PDF 提取确认主图表页在前，工作表在后。导出保留保存字节，新 Worker 重开后的 PDF 逐字节相同。核心另验证四个状态的分页，Arimo 均为 16 页，Noto Sans 均为 19 页。

同一保存稿的视觉对照归私有 `nativeC43RecalculatedPrintVisual`。诊断副本只去掉 129 个公式节点并固定 Arimo，保留单元格缓存和图表数据，交给固定 ONLYOFFICE 渲染。Chromium 重开保留公式的保存稿。主图表的整图 Canvas 与单页 PDF 均为 0/0。工作表完成 15 页共 30 组比较，第 2、3、6、9、15 页的两组及第 4 页 PDF 通过，共 11/30。原件正式整表仍为 10/30，两个结果分别记录。

原生图表缓存更新的证据归 `nativeChartCacheUpdates`。36 项定向核心全部通过。由 C43 只改计算模式得到的自动副本，连续三次修改 A2 后，十九张图表的缓存与已计算来源一致；剔除缓存数据点后，其他图表 XML 逐字节相同。三轮精确撤销/重做、易变公式状态和保存重开保持。该副本只隔离缓存事务，未授予原件手工模式资格。气泡尺寸来源现可修改，独立检查缓存、精确历史及重开；图框修改继续保留原定义。带前缀和缺省命名空间、名称转义、空值移除/恢复、缓存元数据、外部注释及含注释数据点的拒绝均有检查。气泡尺寸来源按稳定节点编号读取，缓存编辑后的节点编号不再被当成数组位置。

浏览器对照在产品修改前冻结：仅将既有混合图固定控制的工作表 B2 从 100 改为 600，图表缓存和其他部件逐字节保持，再由固定 ONLYOFFICE 独立生成参考。默认公式栏输入、精确撤销/重做、完整 Canvas 和整页 SDK PDF 通过，两个视觉对照均为 0/0。SDK 保存文件由新 Worker 重开，保留相同文件及 PDF；再由 ONLYOFFICE 重开，其整页 PNG 与预先冻结的参考逐字节一致。同构建的混合图原控制和原件主图流程也通过。新增输入用例等待编辑器队列完成公式栏切换后，再使用已有原生键盘流程；早期镜像输入等待失败保留。该缓存更新批次未验收原件手工计算；当前结果见 `manualCalculation`。其他严格视觉失败保留，未跑全仓。

原生图表底纹所需的共享 8×8 两色位图原语已实现。两页独立单比特图像 PDF 覆盖局部原点、剪切、反射、嵌套裁剪和后续实色绘制；SDK PDF 的两页完整颜色对照均为 0/0。Canvas 按独立字面行网格与逆变换检查：第一页全部 3072 像素、第二页避开抗锯齿外边与采样临界点的 2338 像素均精确匹配。新增二分之一缩小检查覆盖 88 个完整内部像素，各值符合独立 2×2 面积平均；修复前失败，修复后通过。Poppler 会平滑参考 PDF 的图案单元；放大 Canvas 对该栅格的差异 18/189、66/123 保留为诊断，不作为原生图表资格。非法输入与输出预算有核心及宿主检查。产品边界归[通用绘制输出](formats.md#通用绘制输出)，初版证据归私有 `nativeBitmapPatternFill`，本次采样回归归 `nativeCircularPlotAndLegend`。

C43 气泡图当前视图与裁剪证据归私有 `nativeBubbleClipGrid`，前批外框证据归 `nativeBubbleFrame`，字形修复归 `nativeBubbleGlyphRaster`，独立视图参考归 `nativeBubbleView`。固定 LibreOffice 将原生 SVM 按原尺寸直接绘到完整视口，独立核对屏幕显示。参考包含原生背景，不裁图、不缩放栅格、不合成留白。私有 `tools/c0-bubble-view-reference.mbtx` 从同字节输入重建 SVM、FODG 和 PNG，结果与修正前基准一致。早期缺少样式上下文的载体及打印裁图继续作为诊断保留。

本批统一了气泡几何与视图裁剪的 1/100 毫米尺寸。原生 SVM 首选范围为 25666×15905，旧裁剪仍使用未取整的源框。独立重放与正常 PNG 逐字节一致；仅统一裁剪后，无图例图从 3/0 降至 0/0，有图例图从 7/4 降至 4/4。正常 Worker 的原样保存和新 Worker 重开确认相同结果；原件、字体、参考和阈值保持。21 项气泡、图例及共享图表核心检查通过。四条正式 Chromium 流程一条通过、三条失败：无图例完整视图通过，有图例视图及两张图的打印对照继续失败。有图例图全部 17 段文字的原点、每个字距均匹配独立 SVM；这项几何检查不能证明剩余字形像素已正确。后续字形重放归 `nativeBubbleGlyphCandidates`。同一字体的嵌入指令、自动拟合及 Chromium 原生文字候选均未通过完整视图；原生文字减少缺失时又引入额外像素，并使已通过的无图例图回退。候选保留为诊断，当前产品与严格断言保持。现有结果尚不能证明具体的字体后端差异。

C43 双轴折线复用既有原生折线模型。五组系列沿两个 `lineChart` 的源顺序读取，各用所属数轴；固定 20–160 主轴与自动 1850–2250 副轴分别生效。平滑曲线、菱形/方形/圆形/叉形标记、数据标签、六阶趋势线、方程、R²、文字装饰、旋转轴标题和底部图例均接入。原锚点读取和绘制、显式外框保留、源保存、隐藏系列及非法轴链接通过检查。26 项相关核心、独立六阶函数拟合及五项扩展锚点回归通过。

独立 ONLYOFFICE 控制在产品修改前冻结。只替代三个原字体为固定 Arimo，并保留原粗斜体；其他缓存工作簿部件逐字节保持。绘图区四项边界、标题、刻度、受右边界约束的数据标签、方程、R² 及打印原点在 0.001 pt 内匹配独立 PDF。全部六种曲线的 1,948 个边端点逐一核对，最大误差低于 0.00004 pt；原主折线坐标断言保持。图表页打印原点沿原生页边距加一个逻辑像素，不随外框笔宽移动。文字装饰使用顶边描边和原生字符宽度；上下标字号按半磅舍入，段落保留原字号行高。26 项图表核心、16 项共享文字检查及九条 Canvas 回归通过。五条编辑流程回归覆盖主折线、DOCX 原生域与链接样式、PPTX 字符格式及 XLSX 单元格装饰，主折线完整 Canvas/PDF 保持 0/0。

正常 Worker 的打开、单页打印、原样保存和新 Worker 重开成功。整页 SDK PDF 从 4/4 降至 0/0；完整可见 Canvas 从 13/64 经 2/58、2/2 和 2/0 降至 0/0，原始严格断言通过。分数路径取样和原生输出精度重放仅作诊断。九十度字形复用既有 PDF 行网格，圆形标记按原生路径起笔并保留开放接缝。虚线边框保留相位和转角，不透明标签底色沿设备边界覆盖前景。75 组矩形控制和 54 组曲线控制通过，十二条 Canvas 回归通过。25 组曲线另与独立解析轮廓核对 44,800 个位置；拆段及轮廓预算、近反向斜接与闭合后续线检查通过。主折线 Canvas/PDF 保持 0/0，前批五条共享编辑流程保留原构建证据。诊断正常 PNG 与产品逐字节一致。仅按原生平坦度拆分描边即可消除两处圆形缺失；填充、参考与容差保持。同构建复验中，两张雷达、主折线、双轴折线和 C02 的 Canvas/PDF 均为 0/0。原工作表首个剩余图表读取失败仍在 `chart3.xml` 的三维柱图，完整 C43 未授予资格。

C43 第二张气泡图已接通右侧图例及系列、点的 `bubble3D` 元数据读取。显示沿原生平面圆规则，源标志不改写。27 个非零气泡、三个图例标记、零尺寸系列图例、可见系列重排、原始锚点及原样保存通过核心检查。非法布尔值、越界或重复点、未知点外观和过宽图例继续拒绝。24 项定向核心及一项全图清点通过，证据归 `nativeBubbleLegend`。

新图的独立原生 SVM 来自既有固定字体输入，按自身首选尺寸绘制完整 2448×650 视口。绘图区与图例边界均和原生向量精确一致；图例空间修正后，完整视图从 11200/10811 经 7/4 降为 4/4，保存和新 Worker 重开结果一致。无图例视图现为 0/0，参考生成器仍逐字节重建其原 PNG。正常 Worker 的打印、源保存和新会话显示均执行成功；有图例视图及两张图的打印用例仍在严格视觉断言失败。新图与既有独立打印参考的 Canvas 对照为 45429/42324，整页 SDK PDF 为 45229/45458，打印边界和默认字体继续验收。固定 ONLYOFFICE 导出仍把该气泡图降为普通散点，该输出独立保留；产品保持气泡尺寸和源填充。无图例完整视图已通过；有图例视图、两图打印及完整 C43 仍未通过。

前批正常 Worker 在 100% 缩放下，整幅 Canvas 的严格颜色差异由 72/4752 经 6/8 降至 3/0。原样保存和新 Worker 重开得到相同结果。气泡图使用独立绘制作用域，保留分数线宽和设备半像素原点，屏幕裁剪限制到图框。绘制批次现携带实际字体的 `upem`，屏幕字号按当前设备缩放量化到整数像素。直接设置量化后的 em 比例，避免矩阵再乘一次产生舍入偏差。字形按最近的水平四分之一像素及整数基线取样，文字差异已消除。剩余三处缺失均在图框底边；原生图保留的部分覆盖仍待核对。路径裁剪诊断未改善结果，整数外扩会引入大量额外像素；两者均已恢复并保留失败证据。

前批将默认外框修正为原生 `D9D9D9`，并保留工作簿主题处理前后的颜色及输入校验。最终完整视图仍为 3/0，保存重开一致。整组软遮罩候选为 1/0；采用正确外框色后，整数裁剪候选为 0/138。两者均未通过，已撤回。原生填充、轮廓及单圆对照可分别复现底边颜色，具体裁剪组合仍待核对。绘制宿主与缩放检查已逐字节恢复到前批版本。

本批 19 项 XLSX 核心检查通过，包含默认外框、主题处理及无效颜色拒绝。17 项 DOCX/PPTX/PDF 核心、5 项 PDF 提取和 80 个绘制协议断言沿用 `nativeBubbleGlyphRaster` 的通过记录。最终构建的九项共享绘制检查覆盖不同 em 单位、缩放、反射、模拟粗体、零像素字号、混合对象、状态恢复、PDF 像素与页面裁剪。四格式另有九条功能回归通过：DOCX 双栏、PDF 阿拉伯文字及两种 CFF 表单、PPTX 图表、XLSX 主折线图、面积图、填充雷达图和系列容量。其中 DOCX 双栏及 XLSX 主折线、面积、填充雷达图的独立 Canvas/PDF 对照均保持 0/0。其余回归按各自用例核对字形覆盖、像素、保存、历史或重开。四种字号的精确几何与发布优化证据仍归 `nativeBubbleCircles`；Noto 字节、许可和逻辑坐标归 `nativeBubbleLayout`。

正常 Worker 目录返回 `bubble`，PDF 输出已执行。既有打印裁图与屏幕比较仍为 47896/44894，整页 PDF 为 47603/48128，两项均失败。该裁图不作为原生视图资格依据，断言与阈值保留。初始实现和 20 项跨格式回归归 `nativeWorksheetBubble`，保留原构建证据。ONLYOFFICE 丢失尺寸的散点输出另记 `nativeBubbleReferenceInvestigation`，未采用为预期。原工作表其他图表、3D 配置和整文件验收继续实施。

后续打印诊断归 `nativeBubblePrintFontControl`。既有参考只替换了图表字体，工作簿默认字体仍为 `Arial Cyr`。仅将默认字体替换为同一 Noto Sans 后，原生 PDF 图框宽度由 470.395 点变为 455.921 点，仍未匹配当前 SDK 输出。原生 SVM 预览还包含图框裁剪，原生 PDF 则保留外伸气泡。因此，打印裁图尚不能证明原生视图的完整预期；后续分别核对视图裁剪和打印边界。原始严格失败及四组独立逻辑坐标检查均保留。

C43 百分比面积图当前证据归私有 `nativeWorksheetArea`。原始锚点的 26 个系列、轴、标题、缓存、源保护与重开通过核心检查。独立控制保留图表定义及原框，仅沿既有纸面对齐和 Arimo 常规/粗体替代。十二个字体声明和全部非目标部件均另行校验，参考生成不调用 SDK 布局。正常 Canvas 和整页 PDF 均为 0/0，保存字节及新 Worker 重开保持。32 个系列的 Worker 创建、显式设置、精确撤销/重做和重开通过。33 个系列或超过 XML 节点预算的候选均拒绝，源字节及修订保持。16 项定向 XLSX 核心与 20 项 DOCX/PPTX 图表、图片回归通过。

C43 雷达图的当前通过证据归私有 `nativeCurveStrokeOutline`，前批方形标记证据归 `nativeRadarSquareEdges`，同构建回归归 `nativeWorksheetArea`，纸面对齐控制归 `nativeRadarPixelGrid`，第一批归 `nativeWorksheetRadar`。原件两张图的原始锚点、隐藏轴、线条、标记、网格、填充、零值、源保存和重开已检查。13 项定向核心检查包含既有折线图、来源筛选、图表计算及数轴回归。两项雷达测试另按注册入口独立执行；附加校验逐字节核对纸面对齐控制的全部非目标部件。参考生成不调用 SDK 布局。

原始 chart9/chart10 定义置入固定图表页框，单元格缓存沿既有控制保留。旧比较的纸面原点与视口不同，还读取了画布外的负坐标。新的控制仅调整纸面左、上边距，将原框对齐 144 dpi 的整数像素；图表、图框及其他部件全部保持。方形标记现用原生开放路径，Canvas 对齐两侧边缘并保留起点端帽。正式比较覆盖完整可见 Canvas 图框和整页 PDF，保持原像素邻域与颜色容差。三条正常 Chromium 流程全部通过：两张雷达图及主折线图 Canvas/PDF 均为 0/0。保存字节及新 Worker 重开保持。

共享矩形检查扩展至 192 种描边组合及 120 种裁剪组合，覆盖开放路径、透明度、反射、旋转、非均匀变换、端帽及回退。菱形、蒙版、页边、图表、图片和打印流程另有通过记录。独立字面 PDF 的 32 个开放矩形中，30 个逐像素一致；其余两个各有一个像素相差 4 级颜色，精确比较仍记失败。当前共享曲线描边按原生线段矩形与连接轮廓一次填充，两张雷达控制均通过。曲线检查保留逐字节 RGBA 断言，预期使用独立冻结的原生子路径；另以平行偏移线交点生成解析包络，核对轮廓几何。预期生成不调用产品代码，原参考与阈值保持。此前自定义覆盖率候选保留为诊断。

旧比较的 19/19、10/18 保留为历史失败。圆弧路径候选没有改变结果，已撤回。早期原生曲线分段重放曾为 1/5，当时未采用。当前实现与完整对照归 `nativeCurveStrokeOutline`，前批 `nativeCubicStroke` 的 0/1 及更早失败继续保留。原件普通工作表还被其他不支持的图表阻断，整文件未授予资格。范围归[工作表图表](formats.md#工作表图表)。

自动列宽证据归私有 `nativeColumnAutoFit`。固定 ONLYOFFICE Builder 10.0.0 与 Noto Sans 11 pt 的五组控制核对源字符宽度及物理列宽。公式视图的原生结果为 201 pt，SDK 原来为 198 pt；现已修复。原断言使用段落字宽 199.6 pt 推导范围，现采用独立原生源宽度及物理宽度的双重等值断言。窄字符和一字符边界另有固定结果。原生输出的厂商水印保留，仅其单元格列宽作为参考；原始失败和转换日志保留。

20 组、66 项定向核心检查全部通过，覆盖自动尺寸、公式视图、缩小字体、RAND、图表及拒绝边界。同一优化构建的九条 Chromium 流程通过，包含正常界面的 201 pt 列宽、精确历史、保存重开及 PDF 文字。C41 八次输入、缓存和历史通过；其首页面视觉沿用前批证据。C43 主图及整页 PDF、C44 十组颜色对照已在本批重新通过。首次界面校验仅因工具输出末尾换行失败，处理输出后保留原数字断言并通过。严格构建、TypeScript、lint、格式与源码上限通过；未跑全仓，也未重跑其他格式的完整集合。

自动计算模式的 RAND 证据另见私有 `volatileRandom`。三个核心用例及 64 个随机格覆盖平台种子、独立 Worker、共享和跨表依赖、链接目标、元数据缓存、精确历史及新会话重开；新建和文本导入也已检查。C43 的 C2:C27 共享公式完整，手工模式缓存主图仍为 Canvas/PDF 0/0。派生自动计算副本的 26 个噪声结果和单页输出已检查，该批次尚未验收原件手工计算，当前功能流与数值结果见 `manualCalculation`；十九张图表已可读取，完整视觉资格继续按上述各图证据判断。

C43 主图的栅格修复证据归私有 `nativeChartRaster`。固定缓存及 Arimo 下，正常 Worker/SpreadsheetEditor 的完整主图 Canvas 与整页 PDF 均为 0/0。切回普通工作表后再返回，主图 PNG 逐字节保持。切表、只读保护、原样保存及新 Worker 重开通过。原件、字体、冻结参考和阈值保持；该栅格批次未验收手工重算；当前数值与功能流见 `manualCalculation`，各图剩余视觉差异和重算后的完整视觉继续实施，整份 XLSX 尚未通过。

图表工作表为字形选择既有四档横向子像素规则，几何绘制保持原策略。普通工作表恢复整数字形。菱形同色、不透明的填充与描边现共用一个外轮廓，消除重复边缘覆盖。210 个固定几何控制覆盖反射、非等比、剪切、透明度、连接、虚线和后续状态；策略切换另检查缓存、覆盖层、PNG 导出、无效输入与释放。完整 `fractional` 策略曾为 1284/37，未采用；文字单独重放为 2/1，外轮廓候选为 0/0。诊断源码已压缩保留。

同一 Wasm 和 JS 的两组定向结果共 36 条，35 条通过。17 条 PDF 中 16 条通过，多页 Type1 的第 2 页仍有原来的一个缺失像素。C35 原件/改后六页、C37、两份 PPTX 图片裁剪、C44 十组颜色对照、工作表图表/图片/打印及八条共享 Canvas 检查通过。两项新控制首次因测试调用参数及参考图元遗漏失败，修正后原断言通过，日志保留。严格构建及私有 TypeScript/lint 通过；核心与 Wasm 未变，复用前批 41 项定向结果，139 项整批保留更早构建。全仓未跑。

C35 全页证据归私有 `nativeFloatingMark`。正式流程现逐页检查全部六页，原件与修改后的 24 组 Canvas/PDF 颜色对照均为 0/0。原生输入、精确历史、37 个非目标部件及保存重开通过；重开后六页 PNG 与改后画面逐字节一致。原件、字体、独立参考和阈值保持。新覆盖的第二页曾为原件 82/78、改后 97/88，Canvas/PDF 数值相同；原失败完整保留。

只含浮动对象的段落现使用段落标记字体度量，消除了正文及页眉的累计偏移。21 项布局、20 项 C0 DOCX 核心通过；其中三项在主题字体预检补齐后再次检查。三组新控制覆盖普通/一倍半/固定行距、标记字号、后续段落及缓存。最终正常包的 11 条浏览器流程全部通过，覆盖六条 C0 DOCX、浮动图片/形状剪贴板、默认页眉页脚及两条主题字体恢复。严格构建、私有 TypeScript/lint 和格式检查通过。前批 139 项整批结果保留原构建，本批未重跑全仓。

早期 C43 独立重放先逐字节复现正常 Canvas 的 42/13。相同轮廓按四档横向子像素及整数行重放后为 2/1，三处余差位于图例菱形区域；未修改产品策略。纯横向小数候选为 35/27。参考、固定 Arimo、几何及阈值保持，诊断归 `chart-glyph-phases`，不能授予正常 Canvas 资格。

前批图片采样证据归私有 `nativeImageSampling`。最终空值/布尔值序列化版本通过全部 139 项、35 组 C0 核心，覆盖四格式及拒绝边界。原件和修改后 C35 的第 1、3、6 页 Canvas/PDF 均为 0/0，保持同一字体、原件及容差。正常输入、精确历史、37 个非目标部件和保存重开通过。该批仅检查第 1、3、6 页；全部六页的最新结果见上。

定向浏览器集合共 39 条，含一条诊断。先通过 33 条；显式布尔插值的六条流程失败。修正后仅重跑这六条、C35 及其诊断，六条通过，两条保留原视觉失败。合并为 37 条通过、两条失败，记录分别固定构建身份；这不是同一 Wasm 的 37/39 单次运行。CCITT、JBIG2、JPX 和 CMYK JPEG 的原页及旋转页恢复通过。其余已通过流程复用相同 TS 绘制和空值语义，覆盖 DOCX 裁剪、双栏、字段、链接框、页眉图片、PPTX 两份图片裁剪、XLSX 图片、字体及字段控件。

共享 Canvas 的八条检查通过。图片裁剪覆盖 70 个采样/变换组合；页面边缘覆盖 24 个完整、局部、嵌套、偏移、反射、剪切及后续绘图控制。独立 4.75 pt PDF 在 144 dpi 下的 10×10 像素均为不透明黑色，支持 backing 边界规则。C35 整页重放与正常 PNG 字节一致。遮罩、重复图块、字形、矩形和后续状态保持。严格构建、根及私有 TypeScript/lint、定向格式和 69 个绘图校验断言通过。早期字段缺失、布尔数组编码及裁剪栈回归的日志保留；全仓未跑。

该图片采样批次的 C40 原件为 Canvas 9/0、PDF 6/0，改后深色背景均为 0/0。当前 C40 结果见上方 `nativeMetafilePreviews`。该批原生 PDF 将图标及 Tahoma 文字表示为带 Alpha 遮罩的 321×209 JPEG；SDK 保留矢量文字。这证明表示方式不同，尚不能将全部余差归因于 JPEG。多页 Type1 PDF 的第 2 页严格颜色对照仍失败。C41 当前全部六页结果见下；C43 及其他 C0 缺口保持未完成。下述批次保留各自历史构建。

C41 的依赖与行高证据归私有 `nativeDependencies`。上游八次赋值通过默认公式输入，二十个依赖结果与缓存一致；一次同值输入不新增历史，七次修改可精确撤销/重做。公式、旧计算链清理及其声明、其余源部件和新 Worker 重开通过。独立 ONLYOFFICE 重开修改后原件，深层结果 `4356618` 与 `1883328` 保持。五份中性原生文件确认短、长缓存均重测，固定默认值、固定行和隐藏行保持；未知测量保留原缓存及源字节。

C41 的居中与边框核心证据归私有 `nativeCellEdges`、`nativeBorderJunctions`。六个独立 Noto 原点匹配；原生 PDF 的 73 条描边线段、八组粗细交点和横向页带边界已核对。共享边优先级保持，端点按相邻线宽伸缩，末列细线沿原生页带裁剪。2 项 C0 核心、13 项对齐/边框/表格和 20 项打印检查通过；该批 MoonBit 与 Wasm 保持同一身份，保留当时的 35 项结果。原样式池越界及度量混用的失败证据保留。

C41 当前全部页面通过证据归私有 `nativePrintPageOrder`，前批栅格证据归 `nativeCellRaster`。共享分页沿 ONLYOFFICE 当前循环先向右再向下；源、参考页及页序未重排。续页切口按原优先级选择相邻可见格的边框，原生第二页的 0.75 pt 线段已独立提取并固定。该线段此前造成原件和改后 Canvas/PDF 各 63 个缺失像素。修复后，固定 Noto 替代下，两份文件全部六页的正常 Canvas、整本 SDK PDF 均为 0/0。输入、精确历史、源保留及新 Worker 的相同 PDF 通过。22 项打印核心和 13 项居中/边框/合并/表格检查通过；百万格隐藏及稀疏轴的邻格检查通过。8 条正常 Chromium 流程全部通过，包含 C41 输入、原件/改后全页、C42 原件/改后三页、C44 十组对照、重复标题及整本打印。参考字体、原件和阈值保持；全量 C0 与全仓未跑。

前批三个定向批次覆盖 22 条不同 Chromium 用例，其中含两条诊断。19 条通过，包括 C41 输入、C42 原件/修改后三页 0/0、C44 十组对照、打印设置/范围/整本、图片及图表。两条 C41 六页用例和一条 C43 整图用例继续失败；C43 保持 Canvas 42/13、PDF 0/0。整本打印回归的旧夹具漏写新增工作表内容类型，补齐声明后原断言通过，首轮失败保留。严格构建、私有 TypeScript 及定向静态检查通过；139 项 C0 整批与全仓未跑。

C42 的七项自定义源代码及十三个样式现可读取。B2:I6 的四十个显示值和 B8/B9/B10 匹配原生 FormatTest，包括颜色分节、会计空白及大数百分比。11 项定向核心、1 项传输检查的 84 个断言及两条 Chromium 默认控件流程通过。C4、B10、D6、C2 与 C3 的输入和格式共用九项精确历史，非目标部件、保存及新 Worker 重开通过。单格 PDF 文字、红色 RGB 和会计零值通过 qpdf 与提取检查。另通过七个 SDK 包的独立安装检查，共 3907 个断言，覆盖精确文件清单、无 DOM 导入及公开宿主编译。前批分节语义证据归私有 `nativeSectionFormats`；科学、日期及缩放批次保留各自旧构建。带间距格式的换行、旋转仍未支持；整页最新结果见下，格式范围见[数字格式合同](formats.md#显示与计算)。

C42 最新证据归私有 `nativeCellGeometry`。原件和默认控件九项修改后的文件，分别由同版 ONLYOFFICE 独立重开并生成完整三页参考。控制文件只把唯一的 Arial 字体名替代为固定 Noto Sans，其余十一份部件及样式文字保持。打印明确使用 100% 缩放，横纵适配均为 0。正常 Worker 的 DPR 2 打印预览及整本 PDF，六页均通过严格颜色对照；容差保持一像素邻域及每通道 96。原件源字节、九项精确混合历史、非目标部件和新 Worker 重开通过；重开输出相同 PDF。

| C42 输入   | Canvas 三页 | PDF 三页 |
| ---------- | ----------- | -------- |
| 原件       | 均为 0/0    | 均为 0/0 |
| 修改后保存 | 均为 0/0    | 均为 0/0 |

21 项数字、自动尺寸及条件格式核心检查通过；20 项打印和 27 项绘图回归也通过，两组包含三项相同的计算检查。它们覆盖列宽正反换算、固定默认值、11 个独立 General 数值、内置短日期、无效日期填充与文字预算、原生字形推进及普通段落缓存隔离。C44 的十组独立对照、既有数字/TEXT、CSV/TSV 和 PDF 转 XLSX 流程通过。严格 MoonBit、release、接口与包/示例构建，以及私有 TypeScript/lint 通过。139 项 C0 整批未重跑，其他文件资格保留原构建。

旧列宽、日期、General 和字距差异按各自构建保留；前批三页失败归 `nativeNumberPages`，分节语义归 `nativeSectionFormats`。原打印核心日志曾被后续脚本覆盖，已明确标注缺失；本批独立保存 20/20 新日志，未重造旧证据。原件及修改后参考均在比较前冻结，字体、内容、页面和阈值未按失败位置调整。带间距格式的换行/旋转及更窄 General 列的动态精度仍未授予资格。

先前科学计数批次还恢复漏登记的 15 项既有用例，对应三份文件的 19 项检查通过；PDF 定向集合仅放行未使用的共享测试导入警告，产品严格检查保持。当前登记 139 项、35 组 C0 核心，整批未重跑；原 134 项、33 组结果和十九项补登记检查保留各自构建。后续数字格式批次没有重新授予其他文件兼容资格。

原生折线缓存批次归私有 `nativeLineCharts`。前批 134 项、33 组 C0 核心及 23 项既有图表回归保留原构建身份。图表打印批次的 18 项定向核心通过，覆盖原生图框、标记尺寸、62% 打印缩放、缓存和原样保存，以及自动计算、编辑后快照、区域及预算的拒绝边界。27 项既有 XLSX 图表及绘图检查再次通过。两项图片锚点用例中的旧行高常量已按独立上游规则校正，旧 25/27 失败日志保留。零位移点击保留选择且不提交修改，实际移动继续受保护。

固定 Noto Sans 11 pt 的 Win 上下界为 1069/293，单位为 1000 em。[ONLYOFFICE 行高度量](https://github.com/ONLYOFFICE/sdkjs/blob/3679e0375a758d7dc59d31337a45461be3525ed8/cell/view/StringRender.js#L783-L804)在 96 dpi 分别向上取整，再加一个边框像素，得到 22 px，即 16.5 pt。三份中性 XML 现已独立转成原生 PDF；普通行、缺少中间行及工作表固定默认值三种情况，首行与第三行的文字位置均相差 33 pt。SDK 派生尺寸现逐项一致。工作表固定默认值曾错误固定普通行，已改为独立读取单行标记；现有自动行高测试保留固定行、缓存、隐藏及编辑检查。图片锚点的 13.5 pt 位移、63.5 pt 高度和原有 33 pt 锚点维持原构建资格，本次未重授 C43 视觉资格。原缓存空间失败、字体名检查失败及继承错误日志均保留。

早期 Chromium Worker/SpreadsheetEditor 已显示 C43 主图的两条缓存折线、数字分类、52 个数据标记及源字体。切页、公式输入禁用、原样保存及新 Worker 重开后的相同曲线通过。边距、图例、刻度及隐式主题采用与转换器相同的 ONLYOFFICE 10.0.0.170 源码规则，绘图区四项独立坐标误差均小于 0.001 pt。数据标记按原生单位换算后，整图 Canvas 为 42/13，严格用例继续失败。比较包含完整外框及一像素纸面，保留全部原比较像素；阈值仍为一像素邻域和每通道 96。差异集中在小字栅格覆盖。原件转换即使声明手工计算也会重算 RAND，且使用系统 Arial；该原始输出完整保留。另一个控制文件仅移除公式、保留单元格缓存，并明确将主图字体替代为固定 Arimo，用于缓存对照。它不证明原文件的随机数计算或字体匹配。

同一正常 Worker 流程现覆盖图表页打印预览、PDF 导出和新 Worker 重开后打印。未编辑手工计算快照的整页 PDF 在 144 dpi 下为 0/0；qpdf 校验通过，保存保持原字节。此前 0/1 的 PDF 差异位于数据标记交叠处，修正尺寸后消除，原失败保留。打印缩放采用原生标题及网格预留，并独立核对图框纸面原点。核心另检查混合工作簿输出两页；图表页不占用单元格预算，绘图的每页及整次上限分别校验。该打印批次未验收其他图表及公式编辑；当前公式功能流见 `manualCalculation`，各图与重算后的完整视觉继续逐项验收。

小数横坐标栅格候选为 35/28，未采用。另一次独立重绘先逐字节复现正常 PNG，再检查全部小数坐标及浏览器 `FontFace`：分别为 23/37、整数原点 33/13、小数原点 27/30，均未通过。参考 PDF 的十六个可见字形轮廓、指令程序及 `cvt/fpgm/prep` 表与固定 Arimo 一致；源 `gasp` 表在原生子集中缺失，影响尚未验证。这些结果不能授予栅格资格。诊断代码已压缩保留并移除，正式用例、产品规则、参考和阈值保持。

共享 Canvas 对矩形路径和 `strokeRect` 使用同一描边规则，整数策略的实心轴线复用已有像素描边。前批七条共享 Canvas 检查通过，包含 60 组渐变裁剪、93 组矩形描边及 34 组直线/裁剪组合，覆盖变换、透明度、状态恢复和原生回退。前批五条普通宿主流程及 C44 的十组 0/0 对照保留原构建身份，本轮未重跑。首次宿主运行因缺少 `pdffonts`/`pdftotext` 停止，补齐现有 Poppler 26.05.0 路径后五条通过。C43 本轮核对实际加载的 Wasm、`drawing.js` 和 `pdf-pixels.js` 字节。

重建 C43 参考时，从根目录依次运行 `moon run test-lab/tools/c0-chart-reference.mbtx`、`moon run test-lab/tools/c0-chart-cache.mbtx`、`moon run test-lab/tools/c0-chart-reference.mbtx cache`。工具核对固定输入、转换器和字体身份，并保护已有参考目录。普通浏览器流程使用 `test-lab/` 的 `bun run test:c0-xlsx`。当前批次已通过严格 MoonBit 检查、release、接口生成、正常包/示例构建，以及公开和私有 TypeScript/lint。未执行整仓全量、固定工具链或默认 App。

原生条件格式批次归私有 `nativeConditionalFormatting`。该批 131 项 C0 核心、40 项既有 XLSX 回归和三条普通输入、导入行高及缩小字体流程通过。七项定向核心覆盖原生规则、字体度量、字宽取整、缓存隔离及固定/缓存/隐藏行。正常 Chromium Worker/SpreadsheetEditor 已通过跨表输入、精确历史、源保留和 SDK 重开。原件与改后双表 PDF、首表 A1/A3 的四处 Canvas 单元格内部及独立保存重开的双页，共十组固定阈值对照均为 0/0；PDF 提取文字一致。Canvas 包含完整大写字形和填充，排除屏幕网格边缘，未覆盖整视口。旧 409/421、409/424 及取整前十个残余像素的失败图按原构建归档。其他格式的历史资格与失败保留原构建身份。未跑整仓全量、固定工具链及默认 App 界面。

从 `test-lab/` 运行 `bun run prepare:c0` 核对并恢复 51 份原件及来源声明，`bun run test:c0-core` 执行当前登记的 C0 定向回归，`bun run test:c0-scan` 重编译核心并扫描候选。扫描结果在 `.temp/c0/current/scan.json`；正向失败或控制项意外接受均使命令失败。当前 51 份有界扫描均符合预期；扫描结果仍不授予完整兼容资格。XLSX 目前只检查打开，PPTX/PDF 检查首/中/末页；遇到显示不完整页即记录失败，文字完整性另记。DOCX 解码正文、表格及各节页眉页脚图片，检查完整核心布局、空诊断和未编辑源保存。旧扫描漏报的字段/对象缺口已计入失败；双栏与字段原件已修复核心读取；字段 Canvas 仍失败。旧扫描结果保留于 `docxScanPrior`。字体由宿主显式替代。PPTX 的 Arial 使用固定 Arimo 四种字体，常规 Calibri 使用 Carlito，其他族/样式使用 Noto Sans；DOCX/PDF 仍使用 Noto Sans。相比此前统一 Noto Sans 的扫描，两份表格通过且无新增失败；旧结果和字体 hash 另存。PPTX 图片由 Chromium 调用正常 SDK 解码器，并经核心尺寸/预算验证；非空布局诊断计为失败。此前仅看布局调用返回，漏报了组、主题效果、表格和文字溢出等问题，旧统计不得作为完整显示通过。

该批的 `bun run test:c0-xlsx --list` 列出 25 个文件中的 58 条 Chromium 用例。入口按 `c0-xlsx` 文件名前缀纳入图表、打印及保存重开流程，并包含 `xlsx-manual.spec.ts`。此前的显式文件列表只列出 24 条。

早期批次本机使用 MoonBit 0.1.20261010、Node 26.12.1/26.13.0、Bun 1.4.2。前两者不匹配项目固定环境，结果仍需在固定工具链复核。此前字体与布局批次的 124 项核心回归、`bun run check:moon`、release 编译、SDK 正常打包及私有 TypeScript/lint 检查通过。另通过十三项表格、两项字体度量、两项既有 PPTX 图片透明度和两项 P14 文本适配回归、五项既有 PDF 回归（文字矩阵、裁剪选择、ActualText、软遮罩/Matte）、七项 CMap 回归及一项依赖补丁原子准备/幂等检查。CCITT、xref 空白和五项 CFF 补丁已从固定原始源码重放并核对结果 hash；CFF 再次准备保持幂等。本机旧 CMap 缓存与已登记补丁不符，保留漂移证据后按固定上游原件恢复并应用既有补丁。共享排版的生成接口增加 `paragraph_lines` 可选 `ligatures` 参数，以及绘图帧必填的四侧 `effectExtent` 元组。该文件保留工具生成的 Int32/Int 别名变化；其他接口的纯别名差异已丢弃。

JBIG2 批次新增三项核心回归，当时合计 110 项、28 组通过。原始 `c0-25` 的 12,288 个像素与独立 Poppler 解码逐点相同；另覆盖 MMR 的五种区域合成、非字节对齐裁剪、页默认合成、完整/嵌入文件头、截断、未知模式及预算释放。该批 51 份扫描剩三项正向失败；当前扫描见下述 JPX 结果。正常打包 Worker/PdfCanvas 的 JBIG2 与既有 CCITT 两条流程通过，核对实际 Wasm/Renderer 字节、精确历史、六个源记录逐项保留检查及 SDK 保存重开。JBIG2 原页及旋转页的 PNG 字节与固定 ONLYOFFICE `BasicImageScaler` 参考一致，颜色检查保持原容差。

参考的解码输入仅移除独立工具不接受的 JBIG2 文件容器头尾，页面和区域的压缩数据不变；产品始终打开未修改原件。独立解码样本再交给未修改的固定 ONLYOFFICE 缩放类；PNG 编码及 90° 像素置换不调用产品 Renderer。该参考覆盖单图整页的缩放行为，不授予完整 ONLYOFFICE PDF 导入资格。原 Poppler PDF 后端在小于四倍放大时强制插值，原页和旋转仍分别为 0/570、0/569；Cairo 诊断为 0/12。全部分歧、原始失败和各自构建身份保留在私有 `jbig2Images`。本轮通过严格 MoonBit 检查/release、正常包/示例构建及私有 TypeScript/lint；未执行固定工具链或全仓验收。

JPX 批次新增五项核心回归，当时 115 项、29 组通过；补充裁剪与大坐标边界后，115 项均在该批最终产品源上通过。14 组独立 OpenJPEG 2.5.4 样本覆盖 5/3、9/7、奇数尺寸、多块、瓦片、多质量层、LRCP/RLCP、RGB 变换、SOP/EPH、RESET/VSC/SEGSYM 和分段；无损差异为零，有损最大为一个 8 位等级。另检查原件四个图像的全部分量、JPX 灰度软遮罩、截断、未支持模式、几何冲突与预算释放。该批 51 份扫描剩空缓存 SmartArt 和 PDF 组混合色彩空间两项失败；当前组结果见下段。

未修改的 `jpx_smaskindata.pdf` 经正常 Worker/PdfCanvas 显示，原页与旋转页 PNG 和固定 PDF.js 6.4.299（`d0991a0d5`）独立整页渲染逐字节一致。参考直接读取原件，使用官方随附 OpenJPEG；资源身份、许可及冻结图归私有 `c0-jpx-pdfjs-reference.json`。SDK 未引入 PDF.js 或其他解码运行依赖。原样保存、九个源记录保留、精确历史及 SDK 重开通过；第一图右半裁剪还保留四个原始 JPX 流，重开像素一致。裁剪的独立参考只移除透明像素对应的绘制调用，属于另行编辑结果验收。

本机 Poppler 26.05.0 未按内嵌 alpha 分离四分量，原页及旋转均为 7140/7442；原始失败、栅格对、历史与构建身份保存在 `.temp/c0/baseline/jpx-poppler-rgba/`。该差异未隐藏，严格零缺失断言与原容差保持。CCITT、JBIG2 和 CMYK JPEG 在同一产品构建通过，记录归私有 `jpxImages`。本轮严格 MoonBit 检查/release、正常包/示例、私有 TypeScript/lint 和生成接口检查通过；默认示例 UI 未挂载，历史 UI 和失败项保留各自身份，固定工具链与全仓未验收。

透明组批次新增原件、非中性外层、实数往返、指数渐变及 BBox 证明五项，该批 120 项、30 组 C0 核心通过。`transparency_group.pdf` 现完整显示，原页和旋转页的正常 Worker/PdfCanvas 与原 Poppler 整页颜色参考均为 0/0；沿用一像素邻域和每通道 96 的容差。43 个源记录、精确历史、SDK 保存重开、qpdf 检查和源重构保护通过。七条关联 PDF 流程在同一最终构建复跑通过；六条共享 Canvas 结果复用相同 Renderer 字节，包含路径、图片裁剪、透明度、图块、变换和恢复。遮罩用例另验证 44 个原有精确样本和四个 Difference 样本，新增样本允许一个 8 位预乘舍入等级，原有断言保持。

原件还暴露了保存精度和重复裁剪问题。固定 pdflite 写入器已移除 12 位与固定六位舍入，非目标矩阵数值由独立 qpdf 严格比较；极小数按实际输出长度预检，保存超限后仍能撤销、恢复原件和重做。BBox 只在可证明内部控制点、描边余量和裁剪均不越界时省去；尖角、突出描边、细线、无界着色与不平衡作用域保留裁剪。几何与指数遍历扣预算，指数函数另检查负域、零次方、极陡曲线和分配上限。原始舍入失败与 0/5、0/4 栅格对保留在私有 `differenceGroups`，诊断移除 BBox 的结果不当作产品资格。

透明组批次的 51 份扫描尚有一项失败；该记录保留原构建。严格 MoonBit 检查/release、正常包/示例、公开与私有 TypeScript、lint、生成接口、格式和文档检查通过。`DrawBlend` 替换原 multiply 布尔值，各调用方和保护检查已更新；没有配置开关或额外运行依赖。默认示例 UI 未挂载，固定工具链与全仓仍未验收。历史视觉失败和各批构建身份保持。

空缓存组织图批次新增四项回归，当前 124 项、31 组 C0 核心通过。51 份有界扫描的 46 个正向与五个控制项均符合预期。未修改的 `c0-06` 保留五个文字框、两段经理文字、助手与三条连接线。尺寸和字号按原生约束计算；独立变体检查身份替换、兄弟顺序、缩放及高宽比。无效关系、算法、覆盖样式、断开或循环图与预算边界继续拒绝。

正常 Worker/PresentationCanvas 的原生及缓存 SmartArt 两条流程通过。实际加载的 Wasm、Renderer 和 PDF 像素模块均核对字节。原件与背景编辑后的 Canvas、SDK PDF 对固定 ONLYOFFICE 的整页颜色比较均为 0/0；外部保存重开比较也为 0/0。源部件保留、精确历史及新 SDK 会话重开通过。144 dpi、一像素和每通道 96 的容差保持。LibreOffice 的组织图布局分歧作为补充结果保留。首轮新增断言误写无填充为字符串的失败另存，现按既有 `null` 合同检查。

当前资格归私有 `smartartHierarchy`。透明组及更早的 PDF、UI 结果保留各自构建。严格 MoonBit/release、正常包/示例、私有 TypeScript/lint、生成接口、格式与文档检查通过。公开接口未变，未新增运行依赖。默认示例 UI、固定工具链和全仓验收未执行；其他历史视觉失败、48 页整稿及 XLSX 图表/公式缺口仍在。

`bun run test:c0-visual` 当前登记 25 条流程，含 C50 密码打开、两条 PDF 2.0 流程、两条表单流程、C18 正文编辑、C23 图片移动、C33 批注编辑及下述 17 条历史流程（十三条单页流程、透明组、JBIG2 原生缩放、JPX 独立 PDF.js 及多页 Type1），其中十三份单页原件为：`ArabicCIDTrueType.pdf`、`ccitt_EndOfBlock_false.pdf`、`pdfkit_compressed.pdf`、`simpletype3font.pdf`、`nonembedded_type1_tounicode.pdf`、`annotation-text-widget.pdf`、`annotation-choice-widget.pdf`、`annotation-line-without-appearance.pdf`、`cid_cff.pdf`、`cmykjpeg.pdf`、`shading_extend.pdf`、`nonisolated_blend_smask.pdf` 和 `tiling_patterns_variations.pdf`。Chromium 153.0.8010.12 使用正常 SDK 包的 Worker、优化 Wasm 和 PdfCanvas，并核对实际加载字节。同独立 Poppler 26.05.0 的 144 dpi 参考比较，沿用一像素覆盖容差。九份原件及其旋转页的双向缺失笔画像素均为零。CMYK JPEG、轴向渐变、Alpha 遮罩和平铺另比较全部栅格颜色，沿用一像素邻域和每通道 96 的容差，四份原件与旋转页均为 0/0。十三条单页流程全部通过；下述多页 Type1 流程仍有颜色失败。无嵌入 Type1 在两引擎中显式使用同一份 Arimo，字体选择有断言、日志和 hash；ToUnicode 与显示编码分别核对。

旋转参考由 qpdf 从原件生成，先于 SDK 执行。另核对精确撤销/重做、保存、SDK 重开及 qpdf 独立读取的内容对象与压缩流。`--decode-level=none` 保留压缩 payload 对照，并给原件的 Illustrator 私有流保留有界输出缓冲；初次缓冲不足的失败日志仍保存。旧 xref 流、trailer 容器字段和 Linearized 标记按既有保存合同重建；其他非目标字段与压缩 payload 必须相等。Type3 的未知 Unicode 仍断言 `textComplete=false`。CFF 原件覆盖裸流、OpenType 和空白只读控件；指令预算、截断、隐式编码和 CID 字符集有核心检查，`cid_cff.pdf` 的整页显示和文字已通过；sRGB ICC 的矩阵/曲线有验证，默认可见图层按源配置显示。另有三项颜色和四项可选内容核心回归，覆盖设备色定点边界、损坏配置、真实 Adobe RGB 转换、隐藏绘制/文字、保留状态、条件表达式和递归预算。Adobe RGB 页面组及 ICC LUT/参数曲线仍未支持；已支持的 RGB/Gray matrix/TRC 图像现由核心转换。DeviceCMYK 的 JPEG 在核心解码，RGBA 经正常 Worker/PdfCanvas 显示。RGB 页面组的内容在隔离图层合成，批注随后绘制。缺失 Line 外观复用现有路径，核对旧式 Border 宽度、零宽隐藏、锁定只读、非零引线/标题及复杂端点拒绝。分组页重构仍保护，源对象与缺失 AP 原样保存。CFF 源重构继续保护；有值、样式、列表内容、选择索引或非法几何的缺 AP 控件仍不完整。

`bun run test:c0-pptx` 检查 `crop-to-shape.pptx` 和 `customshape-bitmapfill-srcrect.pptx` 两份单页原件。正常 SDK Worker/PresentationCanvas 完成显示、原图片裁剪、精确撤销/重做、保存和新会话重开。独立检查所有非目标 ZIP 部件及原 `useLocalDpi` 扩展保留。参考先从原件和只修改裁剪 XML 的独立派生输入生成。椭圆裁剪按仓库优先级使用 ONLYOFFICE；占位图片保留 LibreOffice 参考。原件、裁剪结果、LibreOffice 保存重开和 SDK PDF 均为 0/0，沿用 144 dpi、一像素和每通道 96 的容差。椭圆的两引擎原稿相差 2/0，SDK Canvas 对 LibreOffice 为 6/0，PDF 为 2/0，作为次要对照保留。LibreOfficeDev 26.8.0.0.alpha0（`2c87e51eeaa2b413ff4ae097b2705eea1995d8e5`）仍负责外部保存重开。页框先独立核对，再按源 EMU 裁掉栅格填充，不缩放参考。当前 9 项扫描失败沿用更强断言与后续修复。比较归 `.temp/c0/current/pptx/` 和本次补充的 `.temp/c0/current/ellipse-crop/`。

从 `test-lab/` 运行 `moon run tools/prepare-c0-office.mbtx`，准备固定 ONLYOFFICE DocumentBuilder v10.0.0 的 macOS arm64 参考。x2t 实际版本为 10.0.0.170；归档与二进制 hash 在准备和浏览器检查中断言。参考位于 `references/onlyoffice-builder/10.0.0/`，输入只在本机转换，不进入公开 SDK。

同一 PPTX 命令检查 `SampleShow.pptx`（`c0-11`）完整两页，证据归私有 `nativeC11CompleteSlides`。SDK 与 ONLYOFFICE 使用相同的 Carlito 常规和斜体。第 2 页项目符号与正文分别使用固定 Arial、Arial Black 字节。十组 Canvas、SDK PDF 和 LibreOffice 保存重开对照均为 0/0。首屏原有四组栅格及参考逐字节相同。首屏副标题编辑、固定外框、精确历史、新 Worker 重开、非目标 ZIP 部件及文字框以外 XML 保留通过。

三份文字溢出原件的核心检查核对全部原文、完整文字几何、无修改保存及空历史。屏幕与 PDF 均接受可测量的原生溢出。另通过七项既有适配、日期与编号回归，保留编辑失败的原子保护。

普通 PPTX 的自动行高使用标称字号的 120%，避免字体较高的行框累积到段落位置。上下标和行内对象保留较大行框。字偶距和可选连字默认关闭，阿拉伯文保留必需塑形，参照 [ONLYOFFICE 连字选择](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/TextShaper.js#L51-L120)。120% 行高和文字起点由固定 ONLYOFFICE 原件 PDF 独立核对，标题和副标题误差均小于 0.025 pt。四项排版回归检查连字规则交替缓存、制表位、阿拉伯文及既有宽度边界；共享接口默认行为保持。旧位置差异、探针及当前结果归私有 `textPositionPrior/textPosition`。

同一 PPTX 命令还检查 `smartart-background-drawingml-fallback.pptx`（`c0-05`），当前已通过。真实缓存的背景、四个文字框、变换、只读保护、页面背景编辑、精确历史、ZIP 源保留、新 SDK 会话和 LibreOffice 保存重开通过。ONLYOFFICE 与 SDK 使用同一份 Carlito；参考在 SDK 前从原件和独立修改背景的输入生成。原件和编辑后的 Canvas、SDK PDF、外部保存重开均为 0/0。沿用一像素、每通道 96 的容差。

此前 LibreOffice 参考与 ONLYOFFICE 的文字基线约差 2 pt。按仓库规则，以 ONLYOFFICE 为首要实现参考，并保留 LibreOffice 的独立差异。源码表明 Office 行框需使用 OS/2 度量；`USE_TYPO_METRICS` 生效时保留 Typo 度量，并保留较高的 hhea 行高。修正前 ONLYOFFICE 对照与初次 LibreOffice 失败均保存在 `.temp/c0/baseline/smartart/`。Carlito 来源、hash 和 OFL 归私有 `fixtures/fonts/c0-carlito/`。空缓存组织图和 EMF OLE 仍不完整。

背景修改后的四个边角差异来自未声明连接时套用圆角。固定 ONLYOFFICE PDF 使用 `0 j`、`10 M`，其 [ShapeDrawer](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L2098-L2129)也保留 Renderer 的斜接默认值。隔离同一绘制批次后，圆角为 4/0，斜接为 0/0。微软文档给出圆角与比例 8 的基础缺省值；本项目按首要参考选择 ONLYOFFICE 的未声明连接行为。显式连接及同类斜接上限继承保持，两项核心和两条浏览器描边回归通过。旧差异与独立探针归私有 `strokeJoinPrior/strokeJoin`。

同一 PPTX 命令还检查 `table-with-theme.pptx` 与 `table-with-no-theme.pptx` 两份 POI 原件。核心结构、布局、文字/颜色/粗斜体通过；Chromium Worker 的首格文字插入、精确历史、新 SDK 会话重开、非目标 ZIP 部件和编辑格以外 XML 保留均通过。ONLYOFFICE 与 SDK 加载同一组 macOS 系统 Arial 字节；字体选择路径与四种字体 hash 有断言和记录。轴对齐字形原点截去设备坐标小数后，两份原件和编辑后的 Canvas、保存后 LibreOffice 重开、SDK PDF 对 ONLYOFFICE 均为 0/0，容差保持。

按 POI 原断言及 ONLYOFFICE 实际输出，无 `tableStyleId` 的表不继承目录 `def`，缺省边为一磅黑色格线，直接边框格式优先。漏画格线的旧结果保存在 `.temp/c0/baseline/table/`。已有预设回归显式引用同一预设，保留全部填充、文字及共享边断言；无样式行为由原件回归覆盖。未知行列扩展和越界编号仍拒绝。已登记十条 PPTX 浏览器流程，按各自产物记录为八条通过、两条视觉失败，不能授予整批兼容资格。

PPTX 字形定位修复使用共享 Canvas 的整数原点路径。`canvas-glyphs.spec.ts` 检查 1.5 倍设备矩阵、正负小数原点、反射、剪切、上下文恢复及后续图形的原始精度；像素预期独立给定。它与字体回退、PPTX 文字旋转/翻转、XLSX 图表编辑共六条 Chromium 流程通过，十条 C0 PDF 也重新通过。C0 的 PDF/PPTX/XLSX 浏览器记录同时核对实际加载的 Wasm 与 `drawing.js` 字节及 hash，防止复用旧 Renderer 结果。此前已重跑当时的 C0 核心、51 份有界扫描和上述浏览器流程。此轮未重跑要求 Poppler 25.03.0 的 P14 PDF 几何案，本机 Poppler 为 26.05.0。

默认 UI 另需更新 `examples/web-sdk/dist`。初次共享 UI 检查仍用了旧示例 Wasm，不能证明当前 SDK。示例生成器已移除旧脚本分隔符，现可正常执行。共享 `prepareUi` 在挂载前核对示例端点返回的 Wasm 与当前包身份。新构建暴露的 XLSX 测试夹具缺少工作表内容类型声明，已补齐合法声明，产品验证保持。PPTX 的 PDF 文字链接框现覆盖字体升降部；变换、裁剪和工作预算继续检查，两项链接核心回归通过。旋转字形的独立栅格改为 144 dpi 并归一到点值，避免 72 dpi 漏掉细笔画尖端；颜色阈值和 1.5 pt 边界容差保持。初次失败与修正归私有 `sharedUiArtifact/presentationLinks`。

`group-rot.pptx`（`c0-02`）现通过核心扫描。标准 `a16:creationId` 结构和 GUID 有验证，原 XML 随组编辑保留；未知扩展和非法 GUID 继续保护。单栏宽度被边距耗尽时按 ONLYOFFICE 钳制到 0.02 mm，多栏仍检查可用宽度。正常 Worker 完成外层组 12/8 pt 拖动、精确历史、独立预期 XML、非目标 ZIP 部件、新 SDK 会话及 LibreOffice 保存重开。椭圆使用 ONLYOFFICE 的四段 90° 圆弧和左侧起点；矩形描边分别对齐内外像素边界。Canvas 原件与编辑结果由 186/139 经 1/2 降到 0/0；SDK PDF 由 47/45 降到 0/0，外部重开保持 0/0。共享描边采用原生曲线细分后，原件、改后、整页 SDK PDF 与独立保存重开均通过 0/0。原容差保持，旧失败与独立圆弧输出归私有 `groupEllipsePrior/ellipseGeometry`，当前通过证据归 `nativeCubicStroke`。

嵌套组核心检查按源坐标单位换算的精度核对世界坐标，并将其上限限制到 144 dpi 的一像素。此原件在父组放大下的舍入差约 0.003 pt；旧 0.001 pt 检查的失败日志保留在 `.temp/c0/baseline/group/`。x2t 为无文字原件声明了未使用的 Helvetica 资源；参考检查保留字体清单，并独立断言提取文字为空，不再把零字体资源当作无文字的条件。

DrawingML 色相偏移按有符号角度读取，饱和度倍率和偏移按 HSL 处理，并覆盖 ONLYOFFICE 的灰色偏移规则。颜色向量、透明度和拒绝边界有核心断言。`customGeo.pptx`（`c0-13`）的 48 页现可打开并保持原字节；其主题阴影等效果仍阻塞布局，没有整稿显示资格。另通过四项既有组及两项主题颜色回归。

CMYK 新增三项核心回归，覆盖原件、工作预算、错误扫描/组件、Decode 与 CMYK Matte、1 位和 8 位原始样本、初始颜色及图形状态恢复。依赖的 76 项 baseline、43 项 progressive 回归通过，补丁重放和幂等检查通过。渐进式 CMYK、CMYK ICC、DCT DecodeParms 和实际调整描边仍待补齐。

扫描与浏览器分别记录原始核心 Wasm 和正常打包产物身份。输入、参考、Canvas、保存 hash 及结果记入 `cases/c0-current.json`，当前图片和日志在 `.temp/c0/current/visual/`。C0 关闭含完整 Wasm 响应的 Playwright trace，保留页面图片、比较结果与紧凑失败日志，以遵守临时容量上限。

PDFKit 原件的 xref 前置换行和错误 trailer Size 仍由独立工具明确告警。源保存保持原字节；修改后文件通过严格 `qpdf --check`。首次像素对照发现 `S` 误画为感叹号，旧图与 11/259 个双向差异像素保留在 `.temp/c0/baseline/pdfkit/`，没有调整容差。PDF 正文/图片编辑及其余原件的视觉和保存重开尚未验收。

`bun run test:c0-xlsx` 使用正常包的 Worker/SpreadsheetEditor，核对实际 Wasm 字节、原件两类表的身份、切页、无虚构单元格、禁用公式输入、空白点击/双击、原样保存和新 Worker 重开。原件 `chart_7_full_1.xlsx` 的图表仍因数值分类缓存等结构不完整；共享公式仍触发现有 `Unsupported formula group` 保护。初次错误假定返回普通表即可编辑的失败日志保留，现按原件已有保护核对前后状态。三项核心检查另覆盖关系/类型/根不一致、非法单元格内容、14,400 pt 视口、命中和写入拒绝；已支持图表的实时缓存、精确历史和重开通过。十二项既有空白创建、表结构及图表回归通过。此打开流程不授予原件图表视觉、公式编辑或打印资格。

DrawingML `tint/shade` 的线性混色与原色权重已修正。`SampleShow.pptx` 的正常 SDK 绘制批次现包含独立参考的 `898989`。固定 ONLYOFFICE `CColorModifiers` 与原取整函数在隔离参考中执行，五组颜色全部匹配；revision、两份源码 hash 与宿主适配范围归私有 `tintShade` 记录。两项旧表格颜色预期已按该参考更正，保留所有源、透明度、复制和历史断言。十三项表格和两项主题回归通过；首屏视觉结果见上文。

`shading_extend.pdf` 的三项核心回归覆盖 RGB/Gray 线性函数、拼接与反向 Encode、硬颜色边界、四种 Extend、BBox、后续绘制状态及递归/数量拒绝。渐变批次的 `bun run test:c0-visual` 十一条全部通过。渐变原稿和独立旋转原稿的整页颜色均为 0/0，沿用一像素/每通道 96 的容差。正常包还通过精确历史、保存重开、文字完整性及 28 个独立源对象保留。SDK 与 Poppler 共用固定 Arimo 常规/粗体，选择路径与 hash 有断言。

PDF Canvas 的矩形裁剪、实心单线及轴对齐/90° 字形采用各自的设备像素规则。三种栅格策略共 24 组独立字形像素检查通过，包含反射、负行、90°、剪切和状态恢复。另有 16 组固定直线/裁剪检查。新增 45 组矩形描边像素检查，覆盖三种策略、反射、90° 数值残差、非等比缩放、孔洞、填充、透明度、窄线、退化矩阵、斜接上限及原生回退。九条共享 Canvas/字体回退/PPTX 旋转/XLSX 图表流程均通过；既有圆环 UI、孔洞命中、历史、重开与 Canvas/PDF 流程通过。首轮四条流程因缺少 `pdftotext` 停止，补齐 PATH 后只重跑这四条和圆环，五条通过。PDF/PPTX 核对实际 Wasm、`drawing.js` 和 `pdf-pixels.js` 字节。旧失败、分项探针及放弃的字体引擎试验归私有 `pdfRaster/axialShadingPriorRaster`。

`bun run test:c0-docx` 的裁剪案使用正常打包的默认 UI、Worker 和相同 Arial 四种字体，对照固定 ONLYOFFICE 10.0.0.170。`ImageCrop.docx` 的原生输入、裁剪编辑、精确撤销重做、原样保存、新会话重开与 16 个非目标部件保留通过。原件/改后 Canvas 与 SDK PDF 在 144 dpi 的四组整页颜色对照均为 0/0，沿用一像素/每通道 96。省略字号由 11 pt 修正为主参考的 10 pt；源默认与直接字号仍优先。六项 DOCX 核心、十七项布局、十九项格式/历史回归、二十四项默认字号/样式继承/片段回归、两条既有图片 Chromium 流程及 Flow 接口检查通过。共用 Canvas 新增一条检查，十五组固定像素验证源裁剪、反射/剪切、外层裁剪、透明度、空交集、动态图片回退及状态恢复。初始字号差异、旧缺省字号断言和裁剪边缘探针留在私有 `docxCrop`；只更正省略或清除字号的精确预期，显式 11 pt、源保留和历史断言保持。此裁剪案不授予浮动扩展边距或实际图片效果的兼容资格。

`bun run test:c0-docx` 包含裁剪、双栏、字段、VML、链接框、内嵌预览和页眉图片，共七条已登记流程；命令清单已核对。裁剪、双栏和字段三条通过；VML 首屏和内嵌预览仍有余差，链接框只授予已列功能资格。`2col-header.docx` 使用固定 core-fonts 的 Liberation Serif 与 Carlito，在 SDK 和 ONLYOFFICE 中共用相同字节。正文保持双栏宽度，页眉页脚保持整宽，三条基线与独立参考相差小于 0.025 pt。默认 UI 输入、精确历史、18 个非目标部件、源开关、新 SDK 会话和 PDF 文字检查通过；原件/改后 Canvas 与 PDF 四组整页颜色对照为 0/0，沿用原容差。无活动网格的 `adjustRightInd` 和无尾注引用的 `noEndnote` 不改变布局；活动网格、实际抑制、错误语法和未知属性仍保护，后续插入尾注也原子拒绝。DOCX PageCanvas 保留横向子像素，填充字形采用整数设备行；图形和共享默认整数路径保持。十组独立路径像素检查覆盖两种策略、反射、剪切、状态恢复及后续图形。参考用矩形路径执行矢量覆盖；整数像素矩形预期保持。

`99_Fields.docx` 的原件、独立改动首段的参考和保存后的文件，均由固定 ONLYOFFICE 与同一份 Carlito 常规/粗体读取。字体选择路径、源码身份及实际加载的优化 Wasm/示例 app 字节有核对。空文献目录、无结果区的 `BIDIOUTLINE` 和无来源引用的原缓存完整显示。默认 UI 首段输入、精确历史、新 Worker 重开、14 个非目标 ZIP 部件及首段以外 XML 保留通过。独占引用控件保留左缩进并忽略首行缩进；普通文字前缀保留首行缩进，四份独立原生派生输入和核心断言覆盖该差别。原件/改后 Canvas、PDF 与独立保存重开均为 0/0，保持 144 dpi、一像素和每通道 96 的容差。现有 DOCX 策略对轴对齐填充字形采用四档横向子像素及整数设备行；冻结原件的重放先与正常 Canvas 逐字节核对，再与独立参考比较。负坐标、反射、剪切、90°、描边字形和后续状态由既有固定像素检查覆盖。当前证据归私有 `nativeWordGlyphPhases`，原 41/39 和三策略诊断保留。

字段批次通过四十九项 C0 核心及三十二项 DOCX 定向检查，其中九项重叠。新增三项覆盖原件、控件缓存显式更新、格式边界和原子失败；既有页眉页脚/正文字段、引文、书目、来源、目录控件和普通输入回归通过。宿主的一项校验检查通过 112 个断言，预览接受无标签缓存，创建命令继续拒绝空标签。初始比较表达式和保存回调遗漏的测试准备失败保留日志；超时、重试和视觉断言未放宽。该批次正常包另通过裁剪与双栏两条流程；字段流程单独运行并保留失败产物。该批次未改 PPTX、PDF、XLSX 和共享绘制，沿用各自记录的既有结果，`reusedBrowserPackages` 固定更早产物身份。前批字段核心证据归 `docxFields/docxColumns/docxCrop`，包身份归 `gradientPriorPackages`。当前仅修改 TS 绘制，正常 Worker 的字段输入、精确历史、源保留与新会话重开再次通过。18 条不同 Chromium 用例中 16 条通过，含一条诊断；两条失败为 C35 与 C40 的原有视觉缺口。图片裁剪、双栏、链接框、页眉图片、既有字段控件、字体回退及共享绘制通过。PDF 的 Alpha 遮罩和旋转轴向渐变保持 0/0。C35 的原件/改后第 3、6 页 Canvas 与所测 PDF 均为 0/0；第一页 Canvas 降至 537/300。C40 白底原件 Canvas 降至 9/0，PDF 仍为 6/0；改后深色背景保持 0/0。VML 用例现直接读取此前压缩保存的原字体清单，字体路径和视觉断言保持；首次缺少解压文件、空测试筛选及像素参考绘制方式错误的证据保留。成功后的 PNG/PDF 和字体生成表可重建，保留比较、hash、日志及紧凑失败证据。未重跑全量和要求旧 Poppler 的 P14 几何案。

`minimal-gradient-fill-issue.pptx`（`c0-14`）已加入同一 PPTX 命令。原件六个对象完整读取，文字插入、精确历史、非目标 ZIP 部件、文字框以外 XML 和新 Worker 重开通过。SDK 与 ONLYOFFICE 共用固定 Carlito 字节，并核对实际字体选择路径。严格读取 `flip=none`、零面积点和有效 tileRect；保留原元数据，按首要参考绘制框中心圆形和 1 mm 内圆。原件/改后 Canvas 从 10146/9482 降到各 1/0，剩余位置为 741,435，仍使视觉检查失败。改后 SDK PDF 和 LibreOffice 保存重开均为 0/0，保持 144 dpi、一像素/每通道 96 的容差。此流程未另导出原件的 SDK PDF。ONLYOFFICE 参考 PDF 有无效软遮罩告警；SDK 透明度另由既有 UI 的独立颜色方程和每通道 4 的阈值检查，不能据此声称原生透明合成完全一致。

渐变批次通过五十二项 C0 核心和十五项定向核心，其中三项新用例重叠；宿主校验通过 31 个断言。三条既有渐变默认 UI 与两条共享描边/裁剪流程通过。新增的六十组固定像素检查独立给定设备边界，覆盖线性/径向/局部变换、反射、90°、剪切、多边形、三种栅格模式、透明度及后续绘制恢复。首轮用纯色参考比较渐变时出现 Chromium 抖色差，已改用原生渐变绘制，精确像素断言保持；只复跑该失败用例并通过，先前五项 PASS 保留。矩形裁剪后的一个字形附近像素仍未消除，没有改动全局字形策略。渐变批次的正常包核对 Wasm、Renderer 和 PDF 像素 helper 响应身份；默认 UI 核对该批次 Wasm，未单独核对 app 响应 hash。其他格式与既有 C0 浏览器结果仍绑定各自产物，字段批次身份归 `gradientPriorPackages`，更早结果归 `reusedBrowserPackages`。渐变证据归 `nativeGradient`，包身份归 `maskPriorPackages`；未重跑全量或 P14 旧 Poppler 几何案。

`nonisolated_blend_smask.pdf`（`c0-28`）原件与独立旋转稿通过整页颜色对照，均为 0/0。正常 Worker/PdfCanvas 使用固定 Arimo，字体路径、字节与实际加载的 SDK 身份有核对。五段原文、精确历史、新会话重开和 16 项 qpdf 内容记录通过；保存不改组字典与压缩流。沿用 144 dpi、一像素及每通道 96 的容差。透明组批次的正常包重新通过全部十二条 C0 PDF 流程；其他格式的原件结果仍绑定各自记录的产物。

透明组与遮罩新增四项核心检查，覆盖设置时坐标、Matrix/BBox、None/q/Q、外层 alpha/Multiply、填充/描边分开遮罩、Type3、文字/图片编辑保护、损坏元数据、循环和图层耗尽。五十六项 C0 核心通过。宿主校验通过 28 个断言。六条 Chromium 定向流程通过；新用例用 44 组独立 RGB 预期覆盖遮罩颜色、半透明填充/描边重叠、空组、裁剪、图片、反射/旋转/剪切、状态恢复和超限恢复，既有隔离透明层、渐变、描边与淡入/推入继续通过。共享临时层最多四级，遮罩占两级，总像素上限保持。复杂非隔离合成、挖空、Luminosity 和其他转移函数仍保护。透明组证据归 `alphaMask`，该批次包身份归 `patternPriorPackages`，旧失败归 `alphaMaskPrior`。本次未重跑整仓全量或 P14 旧 Poppler 几何案。

`tiling_patterns_variations.pdf`（`c0-29`）通过核心显示、源保存、页面旋转、精确历史及 SDK 重开。五个图案字典/流和十项 qpdf 内容记录通过保留检查。最终正常包的十三条 PDF 流程全部通过；平铺原件和旋转稿的整页颜色均为 0/0，保持 144 dpi、一像素及每通道 96 的容差。实际加载的 Wasm、Renderer 和 PDF 像素模块字节均已核对。其他格式继续绑定各自已记录的产物。

平铺共五项核心检查，连同新增设备色检查，六十二项 C0 全部通过。覆盖小图案、TilingType 1–3、页面/Form 基准坐标、后续 cm、无着色分量、q/Q、alpha、内部文字语义隔离、重叠与间隔、错误输入、循环、不完整程序、4096 格上限及原子失败。设备 RGB/Gray 沿 ONLYOFFICE 的 16.16 转换；ICC 继续按配置处理。原生重构、图案描边、普通字形裁剪和着色图案仍保护。Tile 协议的宿主校验通过 41 个断言；七条共享 Chromium 流程通过，包含 24 组独立颜色/资源/裁剪/遮罩/变换预期和超限恢复。共享检查使用与最终包相同的 Renderer 字节，Wasm 保留检查时的中间身份；随后仅核心的小图案条件发生变化。严格 MoonBit、根与私有 TS、定向 lint 及格式检查通过。

早期连续矢量结果为 88/0、112/0，局部位图试验为 11/295、11/297，设备位图试验为 84/0、115/9，均作为失败保留。按固定 Poppler 26.05 的重复区域取整规则缓存一个图块后，差异降为 1/0、2/0。剩余小图案在取整后由四格变成六格；移除取整前的格数判断后，原件与旋转稿均为 0/0。Canvas 原生重复纹理与大位图试验结果相同，产品只分配单格表面。独立矢量边缘采样试验没有解决差异，未进入产品。当前证据归 `tilingPattern/sdkPackages`，旧扫描、矢量与中间采样分别归 `tilingPatternPrior/tilingPatternVectorPrior/tilingPatternSamplingPrior`；共享绘制证据归 `sharedTileRendererChecks`。本批未跑全量或 P14 旧 Poppler 几何案。

`tracemonkey.pdf`（`c0-17`）的 14 页通过核心完整显示与源保存，沿用每次操作一千万步的默认预算。六项新增检查覆盖二进制 Type1 的隐式编码、lenIV、子程序、FontMatrix、精确历史、截断/循环/未知 OtherSubr、Gray ICC 图像与颜色缓存耗尽、一维采样插值、停点压缩误差，以及小尺度矩阵与逆变换上限；共六十八项 C0 核心通过。原生轮廓复用 `glyphs` 资源并按内容 hash 标识，颜色转换缓存最多 256 项。绘制时只保留四个包围框数值，缓存轮廓不重复序列化，分配和运算继续计入预算。

正常 SDK 的首屏原件与 90° 旋转颜色已为 0/0；整稿旋转、精确历史、SDK 重开及独立 qpdf 源对象保留通过。前批多页流程比较第 2、4、8、11、13、14 页，图形页仍有颜色差异，未授予整份文件视觉资格。该批 C0-17 单条时限为 180 秒，覆盖七页、十四次栅格对照；当前全部 14 页的结果见顶部 `nativeType1FullPageAudit`；全局时限和像素容差保持。原件中的 Calibri 子集含显式空 ToUnicode，继续返回 U+FFFC 与 `textComplete=false`。首次字符映射失败、超时、旧产物探针和完整颜色失败分别保留。临时构建脚本现要求生成新扫描文件，避免 release 失败后复用旧结果；新扫描已核对。

本轮复用像素助手补齐复合矩形、圆角描边和圆头线。矩形重叠只应用一次透明度。普通 PDF 裁剪保留横向小数覆盖和完整设备行。渐变跨越样式、变换指令后仍沿整数裁剪。声明插值的图片使用平台 `medium` 滤波。中性图案可缓存含自身 Alpha 的图片单元。原层数、总像素、重复次数和默认操作预算保持。

同一正常包重新通过十三条既有 PDF 和九条共享流程。共享检查覆盖 60 组渐变裁剪、54 组矩形、16 组线条/裁剪、28 组平铺及 24 组字形预期。另检查图片源裁剪、遮罩、透明叠加和淡入/推入。核心的既有五项图案检查新增图片 Alpha 断言，六十八项 C0 核心保持通过。

第 13 页原件从 5005/3786 降至 0/1。旋转稿从 4961/3457 降至 0/0。第 2 页原件为 1/2，旋转稿为 0/2。第 4 页原件为 0/1，旋转稿为 0/0。第 11 页原件为 6/8，旋转稿为 2/0。第 1、8、14 页及其旋转稿均为 0/0。该历史批次有四页失败，144 dpi、一像素和每通道 96 的阈值保持；当前完整页结果见顶部记录。

逐项撤回验证定位了两项中间回归。横向四分之一像素对齐破坏了 Alpha 遮罩原件，已撤回。渐变的裁剪识别遗漏样式指令，已修复并重新通过既有原件。第 11 页的 Poppler 整页与局部渲染顶边颜色不同。原因尚未确认，整页失败断言保持。当前比较和各次探针归私有 `embeddedType1`，此前结果及包身份归 `type1RasterPrior/rasterPriorPackages`。其他格式继续绑定各自已登记的产物。未重跑整仓全量；固定工具链仍需复核。

`chart_pt_color_bg1.pptx`（`c0-10`）现通过原生环形图显示。缓存保持 April/May 与 95/5，图表自己的 `bg1` 映射产生 `d9d9d9`。系列分离量、内孔、默认边距和圆弧按固定 ONLYOFFICE 10.0.0.170 核对。原件及背景编辑后的 Canvas、SDK PDF 均为 0/0。LibreOffice 的保存重开与其独立改后输入也为 0/0。保持 144 dpi、一像素和每通道 96 的阈值。正常 Worker 检查精确历史、SDK 重开和所有非目标 ZIP 部件。原生外观的数据修改与复制继续保护。

新增三项核心检查覆盖原件、独立坐标/颜色、同类别的多圈显示、类别不一致拒绝、源保留、历史和非法配置。共七十一项 C0 核心及六项既有饼图/环形图/复制检查通过。正常包另通过既有环形图默认 UI，覆盖数据、厚度、类型、历史及 Canvas/PDF。公开的内部 MoonBit 资源和布局接口已重新生成；SDK JSON 与 TS 接口保持。API 文档示例以 `--deny-warn` 通过。参考字体核对和选择目标的测试准备失败保留日志。

此案的 ONLYOFFICE 原稿为黑底，LibreOffice 为白底。两参考原稿仍有 1833624/1831468 个差异像素。首要参考沿仓库顺序预先选定，次要分歧保留。新测试曾在返回数百万坐标时超时。比较器仍检查全部像素并保留完整计数；邻域已有匹配即退出，坐标证据最多 64 项，覆盖全部调用方需求。冻结原件的百万级差异计数和既有 Type1 的 1/2 差异保持。没有提高测试时限或放宽视觉断言。

环形图证据归私有 `nativeCircularChart`。环形图批次的正常包只授予新原件流程及既有环形图 UI 的资格。此前包和扫描归 `nativePiePriorPackages/nativePiePriorScan`，其他格式保留各自身份。该批仍有九项扫描失败及已登记的视觉、公式缺口；未跑整仓全量，固定工具链仍需复核。

`EmbeddedExcelChart.docx`（`c0-40`）现通过核心显示。EMF 按原始物理框、透明度、Unicode 字距及文字裁剪生成既有图元。位图沿原图片 API 提供派生 PNG；原 EMF 与嵌入工作簿原样保留。正常 Worker/PageCanvas 完成背景编辑、精确历史、新会话重开和独立 ONLYOFFICE 保存重开。输入、聚焦和方向键均保持对象保护，整页只读时仍可使用页面设置。

三项新增核心检查覆盖原件、独立 SVG 坐标、PNG 资源、畸形记录、非法字距与图像边界、变更宿主尺寸、缓存恢复及源保留。该 EMF 批次共七十四项 C0 核心通过，51 份原件扫描剩八项失败，46 份正向原件仍均可打开，五个控制项均拒绝。既有 `ImageCrop.docx`、`2col-header.docx` 的正常输入、历史、源保存、Canvas/PDF 及独立对照在同一优化包通过。既有文档保护默认 UI 也通过。

该原件白底的 Canvas 为 12/0，SDK PDF 为 6/0；修改为深色背景后均为 0/0。断言仍报视觉失败，144 dpi、一像素和每通道 96 的容差保持。独立参考使用固定的本机 Arial/Tahoma 字节，与 SDK 一致。预先保存的 ONLYOFFICE 原稿和 SVG 保留；SVG 物理框及基线已独立核对。原稿 PDF 的图像重采样是否导致残差尚未证实，不能据此排除差异。

当前记录归私有 `nativeEmfPreview`。此前包、扫描及核心记录归 `olePriorPackages/olePriorScan/olePriorCore`，其他格式仍绑定各自产物。宿主图片加载及全只读聚焦的中间失败保留日志。新内部 MoonBit 资源及 DOCX Flow 的 `metafile` 类型已同步生成接口和宿主校验。公开接口示例、MoonBit 检查及两套严格 TS 检查通过。整批 C0 尚未通过，未跑整仓全量，固定工具链仍需复核。

`ole-emf_min.pptx`（`c0-07`）通过正常 Worker/PresentationCanvas 的完整 OLE 预览。传统 GDI 路径包含三块扇形、图例和边框；保存的 EMF 与外链原文保持。背景编辑、对象保护、精确历史、全部非目标 ZIP 部件、新 Worker 重开、SDK PDF 及独立保存重开均通过。原件和改后 Canvas、SDK PDF、外部重开四组颜色对照均为 0/0。容差保持 144 dpi、一像素及每通道 96。

预定主参考 ONLYOFFICE 10.0.0.170 漏画全部扇形。固定 core `3250a848ee4ef20c2fb8c38dc86350ec579124b8` 的 `CEmfInterpretatorSvg::HANDLE_EMFPLUS_FILLPIE` 为空，已核对源码。实现前保存了原稿的两套独立 PDF、栅格与 ONLYOFFICE SVG；完整画面由 LibreOffice 核对。引擎差异为 73498/75771，保留在比较记录。SDK 的三个标签基线另与独立 SVG 一致；没有用空白主参考授予完整画面资格。

新增两项核心覆盖原件、路径、标签坐标、字体发现、源历史、对象保护、绘制预算、畸形句柄/曲线/裁剪/变换和 EMF+ Only。既有 DOCX 核心同时核对合法 `GM_ADVANCED` 文字几何，并保留未知模式拒绝。该 PPTX OLE 批次共七十六项 C0 核心通过，51 份扫描剩七项失败；46 份正向原件均可打开，五个控制项均拒绝。公开元文件布局示例、严格 MoonBit 和两套 TS 检查通过。共享 DOCX EMF 的默认 UI 在此包重跑，仍为白底 Canvas 12/0、PDF 6/0，改后背景均 0/0，视觉保持失败。

该批记录归私有 `nativePptxOlePreview`，此前包、扫描与核心归 `pptxOlePriorPackages/pptxOlePriorScan/pptxOlePriorCore`。其余资格仍绑定各自产物。正常包和示例均已重建，共用 Renderer 和 PDF 像素助手字节未变。完整图片只读，不获取外链工作簿；PPTX 元文件内的位图、复杂裁剪、旋转/非等比变换和仅含 EMF+ 的文件仍诊断。未跑整仓全量及固定工具链，整批 C0 继续实施。

页眉页脚的先前组件检查归私有 `nativeRunningPictures`；先前表格检查保留于 `nativeRunningTables`。`Flow` 和节配置使用 `RunningStory {paragraphs,tables}`。表格复用正文排版，字段参与页边有界重排。`Layout.running` 按页保存独立 `PageFrame`，区域文字、图片、底色与边框先于正文绘制，正文缓存保持独立。纯文字写入拒绝复杂区域；正文编辑入口在解析页面节前拒绝页边部件。

图片组件批次的二十三项布局及二十九项 DOCX 定向检查通过，覆盖页码、源顺序、底色/边框、冷热缓存、脚注、连续节、图片水印、浮动图片和命中。新增真实 `c0-35` 图片检查所属关系、尺寸、页面坐标、源图片字节与只读身份；外部/伪造关系及资源键冲突拒绝并保留源。该案和既有表格案计入七十八项 C0 核心。宿主验证共 280 个断言；公开 XML 部件身份、`RunningStory` 和元文件示例通过，严格 MoonBit、两套 TS、定向 lint 与格式检查通过。

新增 Chromium 正常界面使用从 `c0-35` 提取的原生图片组件，保留原绘图、图片和关系，仅排除尚不支持的 VML。图片按所属页眉装载，原生输入、精确历史、源部件保留及保存重开通过。打开及重开后的 Canvas 与独立 PNG 解码逐像素相同；PDF 通过 qpdf，并保留 19×19 RGB 图片资源。最初的夹具关系文件和 Shadow DOM 检查错误已修正，未改产品代码或放宽像素断言。这是图片组件证据，不是整份原件的 Office 版式对照。

普通区域、多节区域和 `2col-header.docx` 的正常界面回归通过。双栏原件及改后 Canvas/PDF 独立颜色对照均为 0/0。前次包、扫描与核心另存 `runningPicturePriorPackages/runningPicturePriorScan/runningPicturePriorCore`；更早的资格及视觉失败保留各自产物身份。

`c0-35` 当前整稿结果归私有 `nativeRunningVml`。原件通过六页核心分页，19×19 源图片由 Chromium 解码，布局诊断为空且未编辑字节不变。正常界面通过正文原生输入、精确历史、非目标部件保留及 SDK 保存重开；选中页重开后的栅格 hash 与编辑后相同。页边 VML、缓存命名字段及正文原生对象保留编辑保护。

独立参考仍使用实现前保存的 ONLYOFFICE 10.0.0.170 六页 A4 原稿；改后文件另由同一工具重开。两次参考均核对四种 Arial 文件。以 144 dpi 和既有颜色容差比较原件及改后文件的第 1、3、6 页：三页 PDF 均为 0/0；Canvas 分别为 597/317、0/0 和 3/12。原件和改后结果相同，整稿视觉保持失败。表格默认兼容模式、自动宽度及 PDF 插值修复前的完整对照已校验归档；更早的分节失败保留紧凑差异和 hash。两处重开测试配置错误另留记录，像素断言与容差保持。

原生 PNG 导出的采样调查另留诊断记录。它确认平滑图片与 PDF 默认采样不同，文字也有独立差异；尚未用作资格参考。现有 PDF 参考保持不变。

该批八十项 C0 核心、二十四项布局及六十三项 DOCX 定向检查通过，其中三项 C0 重叠。新增采样检查覆盖 RGB/Alpha 的显式策略和共享写入器默认值。正文/表格片段、图片、数学内容和精确历史的既有核心检查通过。三个公开示例通过；前批 280 个宿主断言未重复运行。普通页边、多节页边、原生图片、双栏原件、正文混合表格粘贴及行内图片裁剪共六条 Chromium 回归通过。双栏原件及改后 Canvas/PDF 保持 0/0。严格 MoonBit、两套 TS、lint 与格式检查通过。当前验证工具报告 MoonBit 0.1.20261029；此前使用 0.1.20261010，均未授予固定工具链资格。当前批前次资格归 `docxSamplingPriorQualification`，更早结果保留各自产物身份。51 份扫描剩六项失败，46 份正向原件均打开，五个控制项均拒绝。未跑整仓全量，整批 C0 继续实施。

`c0-39` 当前批次归私有 `linkedTextBoxes`。未改动原件使用正常默认界面和 Worker，显式把所有源字体/样式映射为 Noto Sans Regular。两个原生链接框均有文字像素，PAGE/NUMPAGES 按实际页号重算；正文原生输入、精确撤销/重做、非目标部件保留和 SDK 保存重开通过。PDF 通过 qpdf，并包含起始与续框文字。框、框内文字、移动及删除保持只读。完整功能产物按逐文件 hash 校验归档；布局 JSON 使用无损压缩，重复产物保留相同 hash 与实际文件路径。

独立原稿参考在实现前保存。ONLYOFFICE 10.0.0.170 输出单页 Letter，使用 Avenir 替代字体，漏画续框；不能把漏画内容作为正确预期。LibreOffice 输出续文，使用 LinuxLibertineG、FrankRuhlHofshi-Bold 和 LiberationSerif。其 CLI 版本为 26.8.1.1，PDF producer 却报告 LibreOfficeDev 26.8.0.0.alpha0(AARCH64)，该差异照实保留。两套字体均与 SDK 的 Noto Sans 显式替代不同。该批只认定功能通过，同字体原件的整页对照见[当前兼容证据](#当前兼容证据入口)。

链接框批次的八十五项 C0 核心、八十三项 DOCX 及二十四项布局检查通过，其中八项 DOCX 与 C0 重叠。新增五项核心检查覆盖原件、乱序和异宽接续、源映射、非法链拒绝、页边文本框字段及自动段距精确历史。三项宿主检查通过 301 个断言。七条既有 Chromium 流程通过，覆盖普通文本框、文字区域属性、普通/多节页边、原生图片、裁剪与双栏。裁剪和双栏的原件/改后 Canvas 与 PDF 均为 0/0。普通文本框的颜色检查现与 PDF 同为 144 dpi，保持原有像素数量断言，10 pt 源字号及编辑流程保持。C35 在当前产物重跑后，功能及选中页 PDF 通过，Canvas 仍为 597/317、0/0、3/12。

严格 MoonBit、两套 TypeScript、lint、格式及三个公开示例通过。扫描剩五项失败，46 份正向原件均打开，五个控制项均拒绝。未跑整仓全量及固定工具链验收；其他格式资格保留各自产物身份，整批 C0 继续实施。

PPTX 黑白预设色批次归 `nativePresetColors`。85 项 C0 核心通过；已有颜色检查补充黑/白、透明度、明暗变换和非法声明。48 页 `c0-13` 原件逐页读取后，十二处预设色错误已消除，原样保存保持。两条既有 Chromium 外观/线端流程通过；首态 Canvas 严格核对黑/白 RGBA，随后检查普通修改、原生输入、精确历史、保存重开和原有 PDF 轮廓。严格 MoonBit、release、三个公开示例、私有 TS/lint 和格式检查通过。当前扫描仍有五项失败，C13 的阴影、文字效果、几何、列表等尚未补齐；其他格式资格保留各自产物身份。

实现前生成的固定 ONLYOFFICE 10.0.0.170 原稿包含 48 页 720×540 pt 页面。嵌入字体为 Carlito、Carlito-Italic、Arial、Arial-Bold 和 Times New Roman。首页标题在白底上不可见；该参考不授予 C13 完整显示资格。逐页缺口清单、源身份、字体映射和无损压缩产物由私有记录定位。早期 Alpha 遮罩说明误写的文件名已更正：通过的是 `c0-28/nonisolated_blend_smask.pdf`；`c0-27/transparency_group.pdf` 仍扫描失败。原始 ID、hash 和测试结果保持，历史文字误名有单独更正记录。

PPTX 原生大小写批次归 `nativeTextCaps`。三项新核心案检查继承和覆盖、Unicode 字形与源位置、复制到相反设置的目标、清除格式、输入、精确历史、保存重开及拒绝保护。C13 的 48 页无 `cap` 诊断，原件仍原样保存。正常 Worker 将继承大写的 `Straße café ı` 与固定文字 `STRASE CAFÉ I` 比较，Canvas 与 144 dpi PDF 栅格 hash 一致；PDF 文字、原生输入、60 个非目标部件、精确历史及 SDK 重开通过。首轮 PDF 文字仍为小写的失败证据保留；共享 `Line.display_text` 修复后，原断言通过，字段和行内对象替代沿原路径。固定 ONLYOFFICE 原稿第 26 页也把混合大小写源输出为 `TOOLS AND RESOURCES`。

本批 88 项 C0 核心、11 项 PPTX、24 项布局、83 项 DOCX、三个公开示例、严格 MoonBit/release、私有 TS/lint 和格式检查通过；检查集合存在重叠，不累加为独立用例总数。扫描仍有五项失败。新产物只授予上述大小写行为资格，黑白预设色、链接框及其他原件的既有资格保留原产物身份。未重跑全仓、固定工具链验收和此前原件的整页浏览器对照。

PPTX 原生 GIF 批次归 `nativeGifImages`。三项新核心案覆盖原件十四个标志、107×26 与 74×24 独立尺寸、原始字节、普通插入、透明度、平铺、对象复制、跨文稿导入、精确历史、保存重开及非法输入拒绝。48 页清点后，原有十四处图片诊断已消除，阴影、双色调、几何和其他诊断保留。91 项 C0 核心、27 项既有 PPTX 图片/资源、三个公开示例、严格 MoonBit/release、私有 TS/lint 及格式检查通过。当前 MoonBit 为 0.1.20261029，固定工具链尚未验收。

正常 Worker 将两个原始 GIF 按第 26 页的实际组变换放入独立夹具。144 dpi 对照区域为原生 PDF 的 `(965,980,300,48)` 像素条带，并验证参考非空。原件 SDK PDF 为 0/0；半透明修改后的 Canvas/PDF 均为 0/0。62 个非目标部件、精确历史、保存重开及损坏 GIF 的解码失败恢复通过。完整 C13 原件另在正常界面显示同一区域并原样保存，标题的主题阴影诊断保持。独立夹具和原件的 Canvas 均为 2/0，严格零差异断言未改，浏览器用例继续失败；不授予 C13 整页视觉资格。

原生 PDF 把两个 GIF 存成平铺图案中的 JPEG，并带 Alpha 遮罩。它与 Canvas 两像素差异的因果关系尚未证明。首次组坐标与打开 API 合同的测试设置错误、遗漏插值边缘的透明度参考，以及后续颜色失败均保留紧凑证据。临时扫描与产物已按 SHA-256 核对后压缩或去重，清单记录恢复位置。其他格式与前批资格保留原构建身份；本批未重跑全仓和此前原件的整页浏览器对照。

PPTX 外阴影批次归 `nativeOuterShadows`。四项新核心案覆盖固定三角权重、孔洞和曲线、原件 PNG 资源、直接与主题样式、复制、透明度、缩放预览、精确历史、保存重开及拒绝保护。95 项 C0 核心、36 项既有 PPTX 图片/资源/组合/选择回归、三个公开示例、严格 MoonBit/release、正常包与示例构建通过。私有 TS/lint 和受影响格式检查通过；未跑整仓全量及固定工具链验收。

正常 Worker 的 Canvas 原始和半透明采样值与独立三角权重一致。PDF 的 144 dpi 栅格与独立编写的同权重 Alpha 遮罩 PDF 逐像素一致。首次测试把 Canvas 值套到启用图片插值的 PDF；更正为独立 PDF 参考，产品采样策略保持。另一次测试在乘透明度前提前取整；更正数学期望后通过。两次失败的比较、截图和上下文保留。60 个非目标 ZIP 部件、精确撤销/重做及保存重开通过，遮罩没有写入源包。

完整 C13 第 26 页的布局诊断现为空，正常界面可显示、导出当前页 PDF 并原样保存。48 页重新清点后，主题外阴影诊断消除；被它遮盖的几何诊断现单独显露，文字效果、内阴影、双色调、列表和 3D 等仍未补齐。51 份扫描仍有五项失败。此用例只授予上述外阴影行为资格，没有完成原件整页 Office 像素对照；GIF 原件 Canvas 的两像素失败及其他格式资格保留原构建身份。范围归[外阴影合同](formats.md#pptx-外阴影)。

PPTX 原生扇形批次归 `nativePieShapes`。三项新核心案覆盖九个原生扇形、非圆椭圆的射线与曲线控制点、完整圆周、跨零角区、半径描边、旋转命中、连接点、创建/类型转换、填充与阴影资源、复制、精确历史、保存重开和非法导引。原件第 4 页的标题暴露继承 `textNoShape` 误拒绝；共享读取修正后，普通声明、未知元数据与直接/继承优先级通过检查。扇形与字体批次共 100 项 C0 核心、50 项既有 PPTX、七项排版与三个公开示例通过。两项新增核心检查覆盖常规/粗体混排、真实粗体排除、源推进量、普通塑形隔离及 C13 原生文字与历史。绘制校验通过 52 条断言；两个既有 Canvas 案覆盖独立矩形墨迹、小数原点、普通字形、虚线状态恢复、图片和裁剪。严格 MoonBit/release、正常包和示例、两套 TS/lint 与受影响格式检查通过。

正常默认 UI 使用同一 Carlito 常规字体，并核对实际 Wasm/app 字节。完整原件第 4 页无布局诊断，透明度编辑、精确历史、282 个非目标部件、当前页 PDF 和保存重开通过。144 dpi 对照取自改动前的固定 Office PDF，区域为 `(340,240,740,740)`，包含三个扇区及文字标签。共享模拟粗体修复后，原件 Canvas/PDF 均为 0/0；三个 Chromium 用例全部通过。原件、Office 参考、字体、区域、零缺失断言和颜色容差保持。原生内容流给三组 20 pt 标签设置 `0.57167 w` 和 `2 Tr`，字体描述仍为 Carlito、FontWeight 400。核心按相同公式填充加描边，Canvas 保留描边轮廓的小数原点。修复前的 182/144、173/126，以及描边但仍截断原点时的 Canvas 230/0，保留原产物身份。当前资格归 `nativeSyntheticBold`，此前 `nativePieShapes` 的失败记录保持。

首轮文字方向失败、次轮测试漏接正常保存回调所致的下载和未保存提示超时，均保留日志和截图。接回回调后在原 60 秒上限内完成全部功能检查，记录真实颜色失败。下载临时文件曾使合计空间短暂超限；该进程结束并无损压缩四份 C0 字体表后才恢复运行。压缩、去重和源片段保留清单可恢复或定位原证据。51 份扫描剩四项正向失败；C13 的首/中/末页现通过，但 48 页清点仍有缺口，不授予整稿资格。此前阴影、GIF 和其他格式的资格及失败保留原构建身份。未跑全仓和固定工具链验收。

PPTX 圆角标注批次归 `nativeRoundedCallouts`。三项新增核心覆盖原件十一处标注、四向尾部和框外命中、原生圆角与文字区域、五个连接点、旋转、创建/类型修改、渐变/图片/平铺/阴影、复制、精确历史、重开及非法导引保护。八处几何诊断消除，另三处保留文字效果诊断。完整第 36 页无布局诊断。104 项 C0 核心通过，50 项既有 PPTX 回归在该批压缩前通过；严格 MoonBit/release、正常包/示例、两套 TS/lint 和受影响格式检查通过。两个宿主单元用例共 83 个断言通过。

正常默认 UI/Worker 核对实际 Wasm/app 字节，完整原件第 36 页通过框外尾部指针选择、独立半透明采样、282 个非目标部件、精确撤销/重做、当前页 PDF 和保存重开。重开前后的 Canvas/PDF 栅格完全相同。沿固定原件、实现前 Office PDF、Carlito 字节及原颜色容差比较整页，Canvas 为 1686/393，PDF 为 655/271。零缺失断言继续失败，不授予整页视觉资格。

诊断副本仅将 Office PDF 的 JPEG 底图换回原 PPTX 内的 PNG，保持内容、几何、字体、图案矩阵和绘制顺序。PDF 对照降为 0/0，Canvas 为 46/125；副本和正式参考分别记录，正式断言保持。此前流程因未压缩图片流触及 60 秒上限；共享 PDF 写出沿现有依赖压缩 RGB 与 Alpha。新增核心案逐字节检查解码结果、图片复用、插值和源预算。正常界面导出前后的页面栅格 hash 相同，最终流程在原上限内完成。详细大小、计时和失败基线留在私有记录。

标注批次的 51 份扫描有四项正向失败；当批 48 页清点仍有自定义折线、SmartArt 文字、效果、列表和 3D 缺口。标注尾部/圆角调节控件尚未实现。早期扇形、字体、阴影、GIF 及其他格式资格保留各自产物身份。本批未跑全仓或固定工具链验收。

PPTX 自定义路径批次归 `nativeCustomPaths`。三项新增核心覆盖原件十四个路径、公式依赖与单位、原框和非等比尺寸下的曲线/圆弧/文字区域/连接点、非单调曲线与孔洞命中、描边阴影的端帽/连接/面积、预览取消、复制、17 个连接点、精确历史、保存重开及非法/超限源。独立数值由固定 ONLYOFFICE `Geometry.js/Path.js/ArcTo.js` 执行生成，记录源码 hash；普通回归读取冻结数值，不运行参考引擎。107 项 C0 核心、60 项既有形状/图片/组/连接线/笔迹回归及三个公开示例通过。

完整第 6 页已无对象或布局诊断。默认 UI/Worker 核对实际 Wasm/app 字节，指针沿原生组规则选择父组，再经对象列表和对象模式编辑成员。透明度修改、282 个非目标部件、精确撤销/重做、当前页 PDF 和保存重开通过，重开栅格与编辑后完全相同。固定原件、实现前 Office PDF、Carlito 字节、整页 144 dpi 和原颜色容差保持。Canvas/PDF 仍为 36/0、1/0，零缺失断言继续失败，不授予整页视觉资格。

最初的 Worker 查询暴露连接点上限 16 与原件 17 个点不符，核心与宿主现统一为最多 256 个点，越界、非整数和无目标端点继续拒绝。两次指针步骤误将正常组选择当作成员选择，保留比较与上下文；按现有组内操作完成后才记录真正视觉失败。剩余像素位于文字区域；原生 PDF 的 20→12 pt 切换保留前一粗体线宽，但它与全部残差的因果关系尚未证明。没有修改字体、参考、容差或断言来消除残差。

48 页清点的十四处自定义路径几何诊断已消除，其他效果、SmartArt 文字、列表、表格和 3D 缺口保留。51 份扫描仍有四项正向失败。独立扫描、构建和功能/视觉结果分别绑定当前产物；旧圆角标注、扇形及其他格式资格保留原构建。本批未跑全仓或固定工具链验收。

下文 2026-10-29 的 P14 结果是固定构建的历史记录。前次文档核对未找到 `test-lab/.temp/runs/1793305184836/` 和根 `.temp/p14/performance-measured-shape/` 所指原始报告；保留 checkpoint，不把历史结果称为本轮实测。P14 共 12 份上游原件、一份向量派生 PDF 及独立向量，测试项数量不等于真实文件覆盖量。

## P14 素材、环境与当前结果

P14 首轮素材在私有 `cases/p14-xlsx.json`、`cases/p14-office.json`、`cases/p14-pdf.json`，环境依赖在 `cases/p14-environment.json`。交付范围及支持边界归 [P14](../implemented/p14-compatibility-performance.md)，详细源码、产物、测量和历史失败归私有 `cases/p14-current.json`。

2026-11-08，用户确认 `font-scale.pptx` 当前统一采用 ONLYOFFICE 的 27 pt。当前验收使用原生 PDF；27.2 pt 精度参考移入 `historicalPrecision`，不参与当前判定。下文 2026-10-29 的完整运行及性能数字保留其原合同，不作为本轮全仓或性能结果。

2026-11-08，从 `test-lab/` 运行未筛选的 `bun run test`，冻结运行 `1794114128722` 的 3238 项全部通过：2069 核心、155 单元、13 集成、23 安装包消费及 978 Chromium 执行。零失败、阻塞、不确定及重试；源码、产物和资格指针由实际运行器记录。旧失败、超时及中断分别保留。

同一资格产物随后串行执行两轮 `bun run test:performance`，记录为 `1794121125542`、`1794121861213`。每轮完成 20 次新进程冷启动及全部 13 个 Node 负载的正确性检查。每轮统计结果为 10 项通过、4 项校准不确定，标准脚本因此阻断 13 项 Chromium 负载。两轮均未获得标准性能通过结论；保留全部原始计时、冻结预算和延迟负控，不拼接各轮通过项。

冻结的 Chromium 测量入口另作独立诊断，记录为 `1794123391099`。13 个负载均为 `within-budget`，1210 个样本的正确性检查通过，原有延迟负控通过。运行前后核对 8039 份源码与产物身份。临时诊断驱动单独保存，只提供补充测量，不授予标准性能资格，也不合并两轮 Node 结果。

`bun run test:native-performance full` 的运行 `1794122224230` 完成 1024、2048、4096 字符三组测量与保存校验。2048、4096 的两个按键对照均在预算内；1024 的 A/A 噪声不可靠，整套运行未通过。其 Backspace 基线约 24.6 ms，噪声约 17.4 ms，超过约 12.3 ms 的可靠性上限。执行前后的源码、产物及独立宿主身份检查通过。

本轮性能通道均为相同 SDK 产物的 A/B 对照，产品性能预算仍未批准。Node RSS 仅在每次样本验证后观察；峰值内存、图片编码及其他格式的性能未测。标准脚本的 Chromium 阶段未执行，其测量另有上述独立诊断。测量输出无损归档，原始计时、校准与判定记录保留；可重建的功能通过样本按哈希清单清理，原始输入与完整失败证据保留。

2026-10-29，正确性修复后重跑未筛选的 `bun run test`，冻结运行 `1793305184836` 的 2749 项全部通过：1766 核心、150 单元、13 集成、23 安装包消费及 797 浏览器执行。零失败、阻塞、不确定及重试。完整运行绑定源码 `0a797757fd49035bba356a7e6ddfa599a7fa0600500be34ad8486b5d1f78d897`；`.temp/latest-full.json` 由运行器真实生成，原始报告和源码快照保留。先前失败和中断分别保留，不合并成通过结果。

该完整运行覆盖选定 XLSX、DOCX、PPTX、PDF 原件的编辑、精确历史、独立结构、保存重开与输出。五份 Office 原件及指定编辑状态比较实际 Canvas 和独立 PDF：ONLYOFFICE 10.0.0-169、冻结 Arimo 四种字形、Poppler 144 dpi，沿用冻结容差。27.2 pt 按用户选择保留；引擎原生 27 pt PDF 及十倍原生单位的独立精度参考分别记录。PDF 文字固定 PDFium Tinos/Arimo、Poppler 25.03.0 和隔离 Fontconfig；图像缩图严格为 `[0,204,51,128]`。

随后优化只改变布局核心的即时塑形结果复用及其生成接口。A 使用上述完整资格产物；B 使用独立发布 Wasm，双方共用冻结 JS 桥接。固定 CPU 4，Node 24.21.0 使用 `--expose-gc --no-liftoff --no-wasm-lazy-compilation`，在计时前完成优化编译，回收和独立验证在计时区间外。每侧 5 次预热、20 对 A/A 校准、冻结预算后交替采集 20 对 A/B。五项校准可靠，450 个样本的完整布局、保存字节、历史与重开检查通过。4096 字符、17 页首次布局中位数从 56.91 ms 降至 40.07 ms，下降 29.6%，超过 8.43 ms 噪声；重复布局、PDF 导出和首尾编辑均为 `within-budget`。重复布局和 PDF 导出分别增加 1.23 ms、7.29 ms，未超既定预算。仅认定已就绪 Node 核心调用提升；浏览器反馈、启动耗时和三类内存峰值未测量。

优化后产物已通过 132 项布局核心检查和公开 `api`、`build`、`check`，另通过 13 条 Chromium 定向流程（Office 原件、字体切换/回退、双向文字及预算拒绝后恢复）。完整 2749 项资格属于 A，B 的定向与性能结果单独记录，随后文档更新不改变原始运行身份。未提速的字体映射候选、噪声不可靠的测量和计时前退出均保留，未调整噪声算法或预算。量化改进入口为 `tests/performance/p14-layout.ts`，冻结启动脚本、环境和原始结果由当前 checkpoint 定位；既有 `test:performance` 的同产物对照不替代该优化证据。

环境固定 MoonBit 0.1.20261023、moonc 0.10.17+d971670cd、Bun 1.4.2、Node 24.21.0、Playwright 1.63.0/Chromium 153.0.8010.12、qpdf 12.4.1、HarfBuzz 14.4.0 与 Poppler 25.03.0。浏览器串行执行，保留原生剪贴板与完整断言。定向运行显式使用 list/JSON reporter，不授予完整资格。Linux 原生打印的五条流程在完整运行中使用虚拟显示服务通过。

从 `test-lab/` 运行 `bun run test:p14-preparation` 校验离线素材及独立预期，`bun run test:p14-environment` 核对工具、字体、Chromium 及现有 13 个性能输入，`bun run test:p14-recovery` 在隔离副本验证缺失恢复、派生重建和篡改拒绝。`bun run prepare:p14` 需要固定上游源码来恢复原件；已有完整素材的日常检查不依赖 checkout。准备结果只证明素材和依赖。

`bun run test:p14-baseline` 复核环境、构建 SDK，再按 `p14.config.ts` 运行首四 XLSX 案例。该命令保持其有限范围，失败以非零退出并保留实际错误；当前全格式交付由上述完整及定向运行证明。完整性能工具继续要求真实通过的完整资格，不拼接旧失败和定向通过，也不手写资格指针。

## R1 领域拆包与共享加载

2026-10-28 定向检查：公开 Moon check/build/info、严格 TS、lint、格式、冻结锁文件、私有 TS/lint/格式通过。18 项单元检查通过；3 项七包消费检查通过，共 4006 个断言。消费检查沿用已有用例，另检查 XLSX/PDF 独立 bundle、core/web 无 React、唯一 Wasm 和公共 Loader 外部引用。

六条相关 Chromium 流程通过：`engine-loader.spec.ts` 的并发 XLSX/PDF Module 克隆、关闭重开与独立保存；`web-sdk-ui.spec.ts` 的 DOCX 保存确认/替换/双实例和 PDF 编辑保存；`xlsx.spec.ts` 的工作簿编辑/历史/保存重开；`pptx.spec.ts` 的文字/对象编辑与输出；`dev-preview.spec.ts` 的全屏、切换、热更新及 DEV setup/清理。共享流程实际观察到一次获取、一次编译、三次 Module 初始化。生产 Vite 构建通过，产物无 devtools。结果归 `.temp/r1/` 的 `unit-final.log`、`installed-final.log`、`current-browser.log`、`docx-final.log`、`check-final.log` 和 `vite-final.log`。

`current-browser.log` 中 DOCX 首次失败暴露旧异步成功回调清除较新错误的问题；共用控制器修复后，`docx-final.log` 记录该流程通过。旧 UI/旧栈对照的失败日志保留为定位证据，不表示当前用例仍失败。交付边界归 [R1](../implemented/r1-domain-packages-shared-wasm.md)。

补充修复：XLSX 后台重绘继续串行执行并计入队列预算，但不再通过 `busy` 禁用正在点击或输入的控件。`xlsx-repaint.spec.ts` 在按下历史按钮后挂起一次真实 Worker 重绘请求，检查历史按钮和范围框仍可用，并确认松开后撤销执行。原 P9 XLSX 完整流程也通过，保留自动适配、精确历史、公式栏、原生输入及保存输出断言。

PPTX 原对象或组合已有的文字/表格溢出继续作为副本的布局诊断；复制仍执行字体测量、资源和事务校验。新增核心回归覆盖溢出组合的矩阵、文字、历史和保存重开，11 项对象复制相关核心检查通过。原 P9 PPTX 完整流程通过，覆盖组合复制、幻灯片管理、预设形状、历史及输出。另修正面板 key 冲突、原生 ESM 测试的 import map/Loader 配对，以及范围框和对象坐标的重名定位。

补充结果归 `.temp/r1/copy-core.log`、`failures-fixed2.log`、`pptx-fixed-final.log` 和 `fix-check-final.log`。两条累计多个功能的集成用例使用 120 秒总预算及 10 秒动作上限，断言和零重试保持。未跑全量语料、性能或浏览器矩阵。

## 历史定向检查

P10 多节普通表格通过 20 项定向核心检查。新增 Chromium 流程通过，复用本轮已通过的两条尺寸/精确行高流程。覆盖目标节及不等宽起始栏、创建与网格编辑、属性和片段、节归属、精确历史、重开输入、实际 Canvas 和独立 XML/PDF。公开 api/check/build 与私有定向静态检查通过，证据归 `sectionTablesCheckpoint`。沿用 20 秒及零重试；未跑全量或安装包矩阵，连续分节及其余 P10–P12 功能继续实施。

P10 分节创建通过 7 项定向核心检查，包含两项新建分节、三项拆表与两项多节输入检查。新增 Chromium 流程通过，复用本轮已通过的多节输入和拆表流程。覆盖三种分节类型、选择文字保留、表格行拆分及首行插入、继承编号与页眉、精确历史、重开和继续输入。实际 Canvas 空白页、独立 qpdf/PDF 文字及空白页栅格通过。公开 api/check/build、89 项单元断言与私有定向静态检查通过，证据归 `sectionCreationCheckpoint`。连续分节与其余 P10–P12 功能继续实施。

P10 多节原生输入通过 9 项定向核心检查，包含两项新增事务检查及七项组合输入、字段结构和分节布局回归。新增 Chromium 流程通过，复用本轮已通过的两条多节页面/注释流程。覆盖节末输入与格式、Enter/多行拆段、Backspace/Delete 跨节合段、页边引用传递、隐式末节、单元格输入、组合预览/取消、八步核心与六步浏览器精确历史、失败后重做、重开和继续输入；实际 Canvas 墨迹及独立 qpdf/PDF 文字通过。公开 api/check/build 与私有定向静态检查通过，证据归 `sectionNativeInputCheckpoint`。未跑全量或安装包矩阵；新增/连续分节、其余多节结构与 P10–P12 功能继续实施。

P10 指定节文字/图片水印通过 8 项定向核心检查、76 个接口断言及三条 Chromium 流程。覆盖继承与独立别名、各节纸型/居中/变体、空补白页、全文图片资源准备、目标草稿重置、其他部件和正文保留、精确历史、失败后重做与重开；实际 Canvas 像素和独立 qpdf/PDF 文字、透明度及栅格结果通过。公开 api/check/build 和私有定向静态检查通过，证据归 `sectionWatermarkCheckpoint`。未跑全量或安装包矩阵；连续分节、多节正文输入及其余 P10–P12 功能继续实施。

P10 指定节页眉页脚通过 11 项定向核心检查、4 项接口检查共 352 个断言及六条 Chromium 流程。覆盖继承读取、独立副本、恢复前节链接、目标节字段缓存、节内首页与全文奇偶开关、空继承区域、其他部件保留、失败后重做、精确历史、重开、实际 Canvas 墨迹及独立 PDF 文字和链接。公开 api/check/build 和私有定向静态检查通过，证据归 `sectionRunningCheckpoint`。未跑全量或安装包矩阵；连续分节、多节正文输入及其余 P10–P12 需求继续实施。

P10 指定节页边框通过 6 项定向核心检查及三条 Chromium 流程。覆盖节内首页/后续页、前后层次、各节纸型几何、独立移除、同修订切节草稿、跨页目标绑定、其他节和资源保留、交叉/保护/预算失败、四步精确历史及重开。默认控件检查五页实际 Canvas 三种颜色，并用独立 qpdf/PDF 栅格核对红蓝像素；单节背景/边框/原生输入及多节页面/页码回归通过。公开 api/check/build 与定向私有静态检查通过，证据归 `sectionBordersCheckpoint`；复用前轮未变校验器的 337 个断言。未跑全量或安装包矩阵；连续分节及其余多节编辑继续实施。

P10 指定节分栏通过 8 项定向核心检查、3 项接口检查共 337 个断言。新增 Chromium 流程通过，并复用本轮三条已通过的单节等宽/不等宽与多节页面/页码回归。覆盖目标节物理宽度、末栏显示、百分比表格位置和宽度、全文字段、独立设置与重置、失败后重做、四步精确历史、重开、实际 Canvas 色块及独立 qpdf/PDF 坐标。公开 api/check/build 与定向私有静态检查通过，证据归 `sectionColumnsCheckpoint`。未跑全量或安装包矩阵；连续分节、多节正文输入及其他节属性继续实施。

P10 指定节页码设置通过 5 项定向核心检查、3 项接口检查共 328 个断言及两条 Chromium 流程。覆盖起号/续号与独立格式、逐节重置、跨节 PAGE/PAGEREF、继承页眉、源部件保留、五步精确历史、失败后保留重做、隐式末节创建及保存重开。默认控件和独立 PDF 文字/链接沿现有多节流程检查，单节字段、缓存与原生输入回归通过。公开 api/check/build 和定向私有静态检查通过，证据归 `sectionNumberingCheckpoint`。未跑全量或安装包矩阵；其他多节属性与 P10–P12 继续实施。

P10 指定节页面设置通过 11 项定向核心检查、3 项接口检查共 306 个断言。扩展 Chromium 多节流程通过，覆盖显式选节后跨页导航、独立宽高/方向、XML、两步精确历史、重开与草稿重置；复用本轮已通过的跨节注释、背景和两条不等宽分栏流程。公开 api/check/build 与定向私有静态检查通过，证据归 `sectionPageCheckpoint`。未跑全量或安装包矩阵；连续分节及其他多节属性编辑继续实施。

P10 跨节注释通过 8 项定向核心检查、2 项接口检查共 275 个断言及三条 Chromium 流程。覆盖原生逐节编号、文末/节末尾注、脚注跨纸型续排与空末节、正文共享预留空间、跨节 NOTEREF、字段逻辑偏移与光标、内容修改、精确历史和重开。新增默认控件流程检查两页实际 Canvas 墨迹、独立 qpdf/PDF 全文及资源字节；既有多节纸型与单节注释回归通过。公开 api/check/build 和私有定向静态检查通过，证据归 `sectionNotesCheckpoint`。未跑全量、安装包矩阵或外部 Office；多栏共享、每页重启、连续分节与多节编辑继续实施。

P10 多节导入通过 6 项定向核心检查、2 项接口检查共 269 个断言及一条 Chromium 流程。覆盖逐节纸型、分栏与表格边界、页边框、变体继承和独立身份、页码续号/重启/奇偶、全文字段、空页眉几何、编辑保护、源字节和重开。浏览器检查三页 Canvas 墨迹与比例、默认保护提示、独立 qpdf 链接、PDF 文字和 pdfinfo 纸型。公开 api/check/build 与私有定向静态检查通过，证据归 `sectionsCheckpoint`。未跑全量、安装包矩阵或外部 Office；连续分节及多节编辑继续实施，跨节注释见上条记录。

P12 表格单元格方向通过 13 项定向核心检查，覆盖混合方向、逐段矩阵、行界、光标命中、选择、方向键、合并拆分、失败原子性、复制、组变换、精确历史及重开。1 项接口检查通过 143 个断言，新 Chromium 流程检查默认控件、实际点击和原生输入、三步精确历史、重开、独立 XML/PDF 坐标、链接及 PNG/PDF 像素。另复用四条已通过的相关 Chromium 回归结果；其中旧文字框用例补齐已交付的两个查询字段后通过严格断言。公开 api/check/build 和私有定向静态检查通过，证据归 `pptxTableDirectionCheckpoint`。未跑全量、安装包矩阵或外部 Office 验收；单元格任意角度及保持直立、其余 P10–P12 功能继续实施。

P12 文字保持直立通过 8 项定向核心检查、3 项接口检查共 102 个断言及两条 Chromium 流程。覆盖原生角度分界、翻转内边距、文字方向叠加、组变换、光标命中、裁剪、自动适配、复制、精确历史及重开。默认复选框、原生输入、六步精确历史、独立 XML/PDF 坐标、实际 Canvas 及 PNG/PDF 像素通过。公开 api/check/build 和私有定向静态检查通过，证据归 `pptxUprightCheckpoint`。组内自动适配由核心检查覆盖；浏览器覆盖默认静态编辑流程，并在桥接解析按职责拆分后再次通过。未跑全量、安装包或外部 Office 验收；单元格独立角度及保持直立、其余 P10–P12 功能继续实施。

P12 独立文字角度通过 7 项定向核心检查和 3 项接口检查，共 93 个接口断言。覆盖三种锚定的内容中心、两种旋转方向、光标逆变换、源角度舍入、复制、精确历史、资源保留及重开。1 条 Chromium 流程检查默认角度控件、原生输入、三步精确历史、重开、独立 XML、实际 Canvas/PDF 像素及独立链接矩形。公开 api/check/build 和私有定向静态检查通过，证据归 `pptxTextRotationCheckpoint`。未跑全量、安装包或外部 Office 验收；单元格独立角度及其余 P10–P12 功能继续实施。

P10 NOTEREF 注释编号引用通过 25 项定向核心检查，覆盖脚注/尾注标签、上标与相对位置、书签创建及改名、跨段首个注释、复制后重算、注释插入后续号、精确历史、资源保留及重开；普通 REF 的注释目标继续诊断。4 项接口检查通过 395 个断言，1 条 Chromium 流程检查默认控件、原生输入、五步精确历史、重开、绘制字号比例及独立 PDF 文字和两处不同的内部目标。公开 api/check/build 与私有定向静态检查通过，证据归 `noteReferenceCheckpoint`。未跑全量、安装包或外部 Office 验收；复杂域范围、跨段富文本及其余 P10–P12 功能继续实施。

P11 分析资源整列平移通过 10 项定向核心检查和 1 条扩展 Chromium 流程。覆盖分表源/报表、共享及独立日期缓存、三份来源及记录保留、结果和三种控件锚点平移、精确历史、移动后结果保护、预算失败、保存重开、协调刷新与核心打印布局。默认列插删按钮、五处独立 XML 引用、三份缓存记录和两步精确撤销重做通过；保留原行操作及时间线流程。公开 api/check/build、私有定向静态检查通过，证据归 `analysisColumnsCheckpoint`。未跑全量、安装包或新增独立 PDF/PNG 验收；改变源字段数量的列操作、局部单元格结构和完整报表删除继续实施。

P12 三向箭头通过 12 项定向核心检查，覆盖独立 17 顶点轮廓、文字矩形、四个连接点、三项联动上下限、源常量、拖动预览/取消/提交、复制、类型修改、精确历史和重开，并保留四向箭头等回归。3 项接口检查通过 80 个断言，两条 Chromium 流程通过；新流程检查默认控件、原生输入、独立 XML、四步精确历史、重开及 Canvas/独立 PDF 六处轮廓像素和文字。公开 api/check/build 与私有定向静态检查通过，证据归 `threeWayArrowCheckpoint`。未跑全量、安装包或外部 Office 验收；其他预设、自定义几何及 P10–P12 剩余功能继续实施。

P11 分析资源整行插删通过 9 项定向核心检查和 1 条扩展 Chromium 流程。覆盖分表源与报表、同表默认行按钮、三类缓存来源和记录保留、透视结果整体移动、三种锚点、精确历史、预算及保护失败原子性、保存重开和协调刷新。核心打印布局、公开 api/check/build 与私有定向静态检查通过，证据归 `analysisRowsCheckpoint`。未跑全量、安装包或新增独立 PDF/PNG 验收；列及局部单元格结构、完整报表删除继续实施。

P10 REF 完整编号分隔符通过 24 项定向核心检查、4 项接口检查共 374 个断言和 1 条扩展 Chromium 流程。原生引号与空格、逐级连接、其他模式保留元数据、改名、剪贴板、单独清除、缓存、精确历史及重开通过。默认输入/修改、六项字段属性共用传输、独立 XML、实际多级显示、PDF 分隔符文字及内部链接已检查；公开 api/check/build 与私有定向静态检查通过，证据归 `numberReferenceSeparatorCheckpoint`。未跑全量或安装包矩阵，更广 REF 及 P10–P12 继续实施。

P10 REF 相对及完整编号通过 24 项定向核心检查、4 项接口检查共 350 个断言和 1 条扩展 Chromium 流程。同实例上级省略、不同实例、空编号、完整层级、普通/项目符号目标、缺失上级保护、改名、列表修改与粘贴后重算、缓存、精确历史和重开通过。三种模式默认选择器、严格元数据、独立原生 XML、Canvas、PDF 文字及内部链接已检查；公开 api/check/build 与私有定向静态检查通过，证据归 `contextualNumberReferenceCheckpoint`。未跑全量或安装包矩阵，更广 REF 继续实施，P10–P12 保持实施中。

P10 REF 上下位置引用通过 23 项定向核心检查、4 项接口检查共 320 个断言和 1 条扩展 Chromium 流程。跨页、RTL、同段前后、跨段书签、普通格、编号组合、普通/项目符号目标、改名与粘贴后位置重算、缓存、精确历史和重开通过。默认开关、独立原生 XML、实际 Canvas、PDF 文字及内部链接已检查；公开 api/check/build 与定向私有静态检查通过，证据归 `relativeTextReferenceCheckpoint`。未跑全量或安装包矩阵，更广 REF 继续实施，P10–P12 保持实施中。

P11 含透视表、切片器和时间线的工作表改名通过 5 项定向核心检查和 1 条扩展 Chromium 流程。源表与报表分离、共享/独立缓存、两套日期系统、控件与选择身份、待刷新数值、缓存记录保留、精确历史及保存重开后的协调刷新通过。未知扩展与输出失败保持原源，既有普通改名和来源列映射回归通过。默认面板、独立 XML、实际时间线操作及核心打印布局已检查；公开 api/check/build 与定向私有静态检查通过，证据归 `analysisSheetRenameCheckpoint`。未跑全量或安装包矩阵；含分析资源的结构插删与整表复制/删除继续实施，P10–P12 保持实施中。

P12 文字和对象剪贴板的悬停链接通过 12 项定向核心检查和 1 条扩展 Chromium 流程。独立点击/悬停目标、提示/窗口元数据、目标关系复用、原生复制/剪切/重复粘贴、输入后的独立修改、精确历史及保存重开通过。独立 XML、实际 Canvas 和 PDF 点击链接已检查，悬停地址不进入 PDF 注释且不请求外链。公开 api/check/build 与定向私有静态检查通过，证据归 `hoverLinkClipboardCheckpoint`；未跑全量或安装包矩阵，具体幻灯片目标转移及更广富文本继续实施，P10–P12 保持实施中。

P10 REF 段落编号引用通过 23 项定向核心检查、4 项接口检查共 310 个断言和 1 条 Chromium 流程。多级编号、前后缀、跨段书签、普通/项目符号目标、列表修改后重算、默认开关、真实输入、缓存保留与刷新、剪贴板、精确历史和重开通过。独立原生 XML、实际 Canvas、PDF 文字和内部链接已检查。公开 api/check/build 和定向私有静态检查通过，证据归 `numberReferenceCheckpoint`；未跑全量或安装包矩阵，更广 REF 继续实施，P10–P12 保持实施中。

P10 独立公式段落通过 17 项定向核心检查、9 个接口断言和 1 条 Chromium 流程。原生包装、四种对齐、设置默认值、正文/普通格拆段、公式目录、周边输入、结构修改/删除、原生片段、精确历史和重开通过。实际 Canvas 笔画、独立 XML、PDF 分数上下位置及居中通过。公开 api/check/build 和私有 typecheck/lint 通过，证据归 `docxDisplayMathCheckpoint`；未跑全量或安装包矩阵，逐行块数学和更广模式继续实施，P10–P12 保持实施中。

P11 相对日期条件格式通过 14 项定向核心检查、5 项接口测试共 155 个断言和 1 条 Chromium 流程。十种期间、公历边界、1900/1904、数值前缀、当前公式、互操作缓存、范围与复制锚点、精确历史及失败原子性通过。成功日期上下文保留、同规则跨日重绘、无源修改及原日期筛选回归通过。默认面板、重开输入、独立 XML 和实际 Canvas/PDF 颜色通过，公开 api/check/build、私有 typecheck/lint 通过，证据归 `xlsxConditionalDateCheckpoint`；未跑全量或安装包矩阵，P10–P12 保持实施中。

P11 文字条件格式通过 8 项定向核心检查、4 项接口测试共 131 个断言和 1 条 Chromium 流程。包含、不包含、开头和结尾规则的原生文字、类型区别、大小写、空值/错误、文字转义、范围与复制锚点、精确历史及原子拒绝通过。默认面板、输入后的公式结果、保存重开、独立 XML 和实际 Canvas/PDF 颜色通过。公开 api/check/build、私有 typecheck/lint 通过，证据归 `xlsxConditionalTextCheckpoint`；未跑全量或安装包矩阵，P10–P12 保持实施中。

P11 空白/错误条件格式通过 8 项定向核心检查、32 个接口断言和 1 条 Chromium 流程。空格字符、空字符串、未存储格、真实错误及错误文字、原生互操作公式、范围/复制锚点、精确历史及原子拒绝通过。默认四种类型、输入重算、保存重开、独立 XML 与实际 Canvas/PDF 颜色通过，覆盖短视口中首尾格的可见部分。公开 api/check/build、私有 typecheck/lint 通过，证据归 `xlsxConditionalPredicateCheckpoint`；未跑全量或安装包矩阵，P10–P12 保持实施中。

P11 重复/唯一值条件格式通过 8 项定向核心检查、16 个接口断言及 1 条扩展 Chromium 流程。未格式化值、大小写、跨类型逻辑文字、空白、错误、隐藏行、交叠稀疏范围和有界缓存通过；独立复制范围、当前公式重算、精确历史及重开通过。默认面板切换清除旧参数，独立 XML 和实际 Canvas/PDF 颜色检查通过。公开 api/check/build、私有 typecheck/lint 通过，证据归 `xlsxConditionalDuplicatesCheckpoint`；未跑全量或新增浏览器矩阵，P10–P12 保持实施中。

P11 排名及平均值条件格式通过 15 项定向核心检查、19 个接口断言和 1 条 Chromium 流程。稀疏交叠范围、隐藏行、类型区别、并列值、百分比取整、平均值/总体标准差、停止规则、当前公式重算、独立复制范围及精确历史通过。默认面板、原生 XML、重开输入和实际 Canvas/独立 PDF 颜色检查通过。公开 api/check/build、私有 typecheck/lint 通过，证据归 `xlsxConditionalStatisticsCheckpoint`；未跑全量或安装包矩阵，P10–P12 保持实施中。

P12 公式编辑通过 19 项定向核心检查、18 个接口断言和 1 条扩展 Chromium 流程。原生插入、首尾追加、混排/显示/表格公式修改与删除、统一外观、纯文字后备同步、精确历史、锁保护及重开继续编辑通过。实际 PNG 与独立 PDF 栅格双向无缺失笔画，原生 XML 和 PDF 文字检查通过。公开 api/check/build 与私有 typecheck/lint 通过，证据归 `pptxMathEditCheckpoint`。未跑全量或安装包矩阵，复杂数学格式与其他缺口继续实施，P10–P12 保持实施中。

P12 原生公式读取与显示通过 17 项定向核心检查及 1 条 Chromium 流程。形状混排、显示公式、普通表格、DrawingML 属性、对象/页面复制、精确历史及重开通过；与 DOCX 共用的读取器保留七类数学结构与原保护。实际 Canvas/PNG 和独立 PDF 检查通过，两方向栅格对照无缺失笔画。公开 api/check/build 与私有 typecheck/lint 通过，证据归 `pptxMathReadCheckpoint`。本段保留读取阶段证据；未跑全量或安装包矩阵，P10–P12 保持实施中。

P10 HTML 表格题注通过 8 项定向核心检查及 1 条扩展 Chromium 流程。顶端/底端、继承和显式位置、富文本链接、三种粘贴方式、精确混合历史及重开输入通过；独立 XML 核对原生段落和分页保留，PDF 中题注只出现一次。公开 check/build 与私有 typecheck/lint 通过，证据归 `htmlTableCaptionsCheckpoint`；未跑全量或新增浏览器矩阵，P10–P12 保持实施中。

P10 HTML 表格重复表头通过 7 项定向核心检查及 1 条扩展 Chromium 流程。原生 XML 保留两行表头，重开后输入同步到七页 PDF，正文唯一值各出现一次；隐藏行、行组顺序、合并跨度、三种粘贴方式及精确混合历史通过。公开 check/build 与私有 typecheck/lint 通过，证据归 `htmlTableHeadersCheckpoint`；未跑全量或新增浏览器矩阵，P10–P12 保持实施中。

P10 图表定位与几何通过 12 项定向核心检查及 174 个接口断言。既有 Chromium 图表流程扩展尺寸、环绕、Canvas 选择、取消、键盘变换及四步精确历史后通过。核心另覆盖五种定位、跨页锚定、浮动复制、独立锁和重开；环绕的可访问文字遗漏已修复。证据归 `docxChartPositionCheckpoint`；未跑全量或附加浏览器矩阵，P10–P12 保持实施中。

P10 图表富文本复制/剪切及跨文档粘贴通过 14 项定向核心检查，包含两项新图表传递用例及图表、图片、形状和数学片段回归。1 条新增 Chromium 流程通过实际系统剪贴板、独立工作簿数值、Canvas/PNG/PDF、四步精确混合历史和重开编辑检查。公开 api/check/build 与私有 typecheck/lint 通过，证据归 `docxChartClipboardCheckpoint`。复用既有传输检查，未跑全量或重复浏览器矩阵；复杂样式仍待实施，P10–P12 保持实施中。

P10 普通图表通过 34 项定向核心检查与 160 个接口断言，覆盖正文/普通格、嵌入数据、尺寸和图例、独立权限、输入、精确历史及重开。新增 1 条 DOCX Chromium 流程通过，检查默认面板、同步 API、实际 Canvas/PNG/PDF 和独立嵌入 XLSX 数值；提取后的既有 PPTX 图例流程也通过。公开 api/check/build 与私有 typecheck/lint 通过，证据归 `docxChartsCheckpoint`。数据范围绑定及复杂样式仍待实施；未跑全量或重复既有浏览器矩阵，P10–P12 保持实施中。

P12 图例显示与位置通过 26 项定向核心检查，包含两项新图例用例及 24 项图表、占位符、复制和 PDF 链接回归。覆盖五种位置、类别/系列顺序、最小框、长/空标签、条目溢出、未知原生配置保护、工作簿身份/字节保持、精确历史及重开。1 项接口用例通过 132 个断言。1 条新 Chromium 流程通过，覆盖默认面板、实际 Canvas/PNG 颜色、独立 PDF 位置、无操作、独立副本、类型切换、七步精确历史和重开编辑。根 api/check/build 与私有 typecheck/lint 通过，证据归 `chartLegendCheckpoint`。未跑全量、重复既有浏览器矩阵、安装包或外部 Office 验收；图例自定义外观、覆盖及手动布局仍待实施。

P10–P12 浏览器打印通过 5 条定向 Chromium 流程。DOCX、XLSX、PPTX 和 PDF 均实际打开并取消原生打印预览；独立 qpdf/Poppler 检查当前文字、页数、可见表与隐藏幻灯片范围。原生 XLSX 草稿先提交，重复请求只生成一个预览。未保存状态、历史、原格式字节及 `onSave` 保持既有语义。原生调用/加载失败、重试、保留与在途 frame/Blob 清理已有检查。公开 TypeScript、lint、UI/示例构建与私有 typecheck/lint 通过，证据归 `printCheckpoint`。复用既有核心 PDF 检查，未跑全量、实体打印机、其他浏览器或安装包矩阵；P10–P12 仍在实施。

P10 基础行内矩阵通过 34 项定向核心检查，新增两项矩阵用例并保留 32 项数学回归。覆盖正文/普通格、三种列对齐和基线、空单元格、原生列分组及不齐行补足、七种 LaTeX 环境、嵌套、预算/未知源、字体失败、输入、复制、精确历史和重开；全空矩阵通过完整控制属性保留 20.5 pt/Portable Math/0055aa，控制格式的继承范围也已检查。10 项接口用例通过 384 个断言。1 条新 Chromium 流程通过，覆盖默认面板原生读取/创建/修改/删除、实际字形像素、独立 PDF 行列位置、未改源部件、无操作、四项混合历史及重开嵌套修改。根 api/check/build 与私有 typecheck/lint 通过，证据归 `mathMatrixCheckpoint`。未跑全量或重复既有浏览器验收；独立数学段落、内部光标、隐藏占位、自定义间距和局部数学格式仍待实施。

P10 行内求和、乘积和积分通过 32 项定向核心检查，包含两项新 n-ary 用例和 30 项数学回归。覆盖 13 种实际运算符、正文/普通格、右侧上下限、嵌套、默认位置设置、显隐、源保护、复制、输入、精确历史和重开；非法属性/语法、结构预算、无操作及 0.5 pt 已检查。9 项接口用例通过 368 个断言。1 条新 Chromium 流程通过，覆盖默认面板读取/创建/修改/删除、原生属性、实际积分字形像素、独立 HarfBuzz 墨迹度量与 Poppler 参数位置、四项混合历史、窄页对象间换行及重开编辑。根 api/check/build 与私有 typecheck/lint 通过，证据归 `mathNaryCheckpoint`。未跑全量或重复既有浏览器验收；独立数学段落、上下堆叠、增长、矩阵及局部数学格式继续实施。

P10 居中可伸展括号通过 30 项定向核心检查，包含三项新括号/字体表用例和 27 项数学回归。覆盖正文/普通格、字体变体及高括号拼接、多参数分隔、单侧括号、嵌套、原生输入、复制、缓存、LaTeX 编辑、精确历史和重开；未知源属性、语法/参数预算、截断字体表、连接区及伸展上限已有检查。8 项接口用例通过 342 个断言。1 条新 Chromium 流程通过，检查默认面板读取/创建/修改/删除、原生 XML、实际曲线和蓝色像素、独立 PDF 参数坐标、无操作、四项精确历史及重开修改。根 api/check/build 与私有 typecheck/lint 通过，证据归 `mathDelimiterCheckpoint`。未跑全量或重复既有浏览器验收；固定大小/非居中括号、求和/积分、矩阵及局部格式仍待实施。

P10 平方根和带次数根式通过 27 项定向核心检查，新增两项根式用例并保留 25 项数学回归。覆盖正文/普通格、实际字体度量、向量根号、长被开方项伸展、次数定位、嵌套分数/脚标、缓存、原生输入、跨文档复制、LaTeX 编辑、精确历史及重开；非法语法、次数显示属性、隐藏非空次数、混合外观和 0.5 pt 下限已有检查。7 项接口用例通过 329 个断言。既有 9 条数学 Chromium 流程通过；新增根式流程定向通过，检查横线位置的实际 Canvas 像素、独立 PDF 次数/分子/分母位置、原生属性、无操作、再插入、四项混合历史及重开修改。根 api/check/build 与私有 typecheck/lint 通过，证据归 `mathRootCheckpoint`。未跑全量、安装包矩阵、外部 Office 或 OS 输入法验收；括号结构、求和/积分、矩阵及局部格式仍待实施。

P10 有界 LaTeX 创作通过 25 项定向核心检查，新增三项解析/创作/拒绝用例并保留 22 项数学回归。覆盖参数和结构切换、规范化往返、最大深度及文字转义、正文/普通格替换、继承/显式外观、无操作、删除、精确历史和重开目录；非法/宏语法、文本/结构/源预算、缺字体及不透明源保持文档。6 项接口用例通过 320 个断言。既有 8 条数学 Chromium 流程通过；新增 LaTeX 流程定向通过，覆盖失败后的恢复、默认面板嵌套创建/改参/格式/删除、原生 XML、实际 Canvas 与独立 PDF、目录失效、五项混合历史和重开编辑。根 api/check/build 与私有 typecheck/lint 通过，证据归 `mathLatexCheckpoint`。未跑全量、安装包矩阵、外部 Office 或 OS 输入法验收；其他数学结构、局部格式及更多语法仍待实施。

P10 嵌套分数、脚标和横向组合通过 22 项定向核心检查，包含两项新嵌套用例和 20 项数学回归。覆盖正文/普通格、实际基线、缓存绘图一致、原生输入、整式删除、跨文档复制、统一外观、精确历史、重开及平面编辑保护；深度、节点、文字预算、混合源和缓存序列化前拒绝也已检查。5 项接口用例通过 293 个断言。既有 7 条 Chromium 数学流程通过；新增嵌套流程定向复跑通过，覆盖 Canvas、独立 PDF 位置、原生 XML、跨文档粘贴、历史和重开继续输入。首次 PDF 断言把 Poppler 的 `A X` 合并词当作独立 `X`，按实际分组读取坐标后保留位置断言。根 api/check/build 与私有 typecheck/lint 通过，证据归 `mathNestingCheckpoint`。未跑全量、安装包矩阵、外部 Office 或 OS 输入法验收；嵌套参数创作及其他数学结构仍待实施。

P10 脚标创建及参数修改通过 20 项定向核心检查，包含两项新创作用例及 18 项数学回归。覆盖正文/普通格范围替换、14 pt/336699 与自定义数学字体继承、原生三种形式切换、完整 20.5 pt/0055aa 外观、无操作、参数修改保留外观、删除、四项精确历史、重开及未改部件；非法/超限参数、错误结构身份、缺字体、源注释与过期修订原子拒绝。两项接口用例通过 69 个断言。7 条 Chromium 流程通过，新增默认面板创建/切换/格式/删除、插入后焦点、原生 XML、实际 Canvas 与独立 PDF 脚标位置、目录失效、五项精确历史和重开属性，保留脚标显示/输入/剪贴板及分数创作/输入/剪贴板回归。根 api/check/build、私有 typecheck/lint 通过，证据归 `scriptAuthoringCheckpoint`。未跑全量、安装包矩阵、外部 Office 或 OS 输入法验收；嵌套数学、局部格式与复杂结构仍待实施。

P10 脚标周边编辑和原生剪贴板通过 18 项定向核心检查，包含三项新输入/转移用例及 15 项数学回归。覆盖三种脚标的正文/普通格原生输入、Tab/软换行、Enter/合段、组合取消/提交、文字格式、反向整式删除、线性选中文字、缺字体原子拒绝、跨文档外观、矩形格 TSV/扩表/清空、精确历史及重开。6 条 Chromium 流程通过，新增原生输入、拆合段、实际复制/键盘剪切、跨文档默认粘贴、原生外观和独立 PDF 脚标坐标、四项及两项精确历史、重开输入，保留分数创作/输入/剪贴板和脚标显示流程。根 api/check/build 与私有 typecheck/lint 通过，证据归 `scriptsInputCheckpoint`。未跑全量、安装包矩阵、外部 Office 或 OS 输入法验收；脚标创作和内部参数编辑仍待实施。

P10 普通数学上下标读取与显示通过 15 项定向核心检查，包含两项新脚标用例及 13 项分数回归。覆盖正文/普通格、上标/下标/双脚标、实际字形与基线、缓存绘图一致、字体缺失、未知/嵌套/混合源保护、原生部件、无关段落输入、精确历史和重开；分数 0.5 pt 下限也已补齐核心与接口检查。3 项接口用例通过 215 个断言。3 条 Chromium 流程通过，新增实际 Canvas 颜色及独立 PDF 基底/脚标位置、双脚标间隙和水平对齐、原生输入、精确历史及重开显示，保留分数创作/输入回归。根 api/check/build 与私有 typecheck/lint 通过，证据归 `mathScriptsCheckpoint`。未跑全量、安装包矩阵、外部 Office 或 OS 输入法验收；脚标创作及复杂数学仍待实施。

P10 分数整体字体、字号和颜色通过 13 项定向核心检查，包含两项新外观用例及已有分数读取、创作、原生输入、剪贴板和周边格式流程。覆盖正文/普通格、实际继承外观、显式插入/修改、相同直接格式无历史、参数修改保留外观、精确历史、重开及非法参数/缺字体原子拒绝。接口检查通过 40 个断言。已有创作 Chromium 流程扩展独立字体、20.5 pt、颜色、原生 XML、实际 Canvas、独立 PDF 字形大小/基线及重开属性；其余四条流程通过后复用结果。根 api/check/build 与私有 typecheck/lint 通过，补充 UI/示例构建通过，证据归 `mathStyleCheckpoint`。未跑全量、安装包矩阵、外部 Office 或 OS 输入法验收；局部数学格式与复杂结构仍待实施。

P10 公式段落普通文字格式通过 18 项定向核心检查，包含两项新用例、九项原格式用例、四项分数创作/输入和三项分数剪贴板回归。覆盖正文/普通格、反向文字范围、字符格式、段落对齐/缩进/间距、光标待输入格式、组合取消/提交、连续输入、精确历史及重开；公式原生源和外观保持，公式范围、未知源及非法格式原子拒绝。5 条 Chromium 流程通过，新增默认面板格式流程，保留分数创作/输入及两个原生剪贴板流程。实际 Canvas 蓝色文字、独立 PDF 居中与分子分母坐标、原生属性、五步精确历史和重开输入已检查。根 api/check/build、私有 typecheck/lint 通过，证据归 `mathFormatCheckpoint`。未跑全量、安装包矩阵、外部 Office 或 OS 输入法验收；公式自身格式命令及复杂数学仍待实施。

P10 分数富文本剪贴板通过 13 项定向核心检查，包含三项新片段用例、六项分数读取/创作/输入及四项字段剪贴板回归。覆盖反向正文范围、独立数学外观、缺少字体原子拒绝、跨文档修改、矩形格 TSV/OMML、覆盖目标公式、扩表、整格剪切、精确历史及重开；错位、未知、混合外观、源注释与 256 项总量限制也已检查。5 条 Chromium 流程通过，新增正文及矩形格两条流程，保留原富文本资源和分数编辑/输入流程。检查真实剪贴板、键盘剪切、指针矩形选择、默认粘贴、原生字号、未改部件、重开输入与独立 PDF 分子分母坐标。根 api/check/build 与私有 typecheck/lint 通过，证据归 `mathClipboardCheckpoint`。未跑全量、安装包矩阵、外部 Office 或 OS 输入法验收；公式段落格式及复杂数学仍待实施。

P10 分数段落原生输入通过 10 项定向核心检查，包含两项新输入用例、四项分数读取/编辑、两项 PAGE 字段结构回归及两项文档保护。覆盖正文/普通格、独立/相邻文字、两侧光标亲和性、软换行/Tab、Enter/合段、组合输入取消/提交、整式删除/反向替换、相邻分数创建、搜索位置、未知源原子拒绝及精确历史。4 条 Chromium 流程通过，新增插入后焦点、公式两侧输入、换段、Delete、五步精确历史、重开输入及独立 PDF 文字；保留原分数显示/编辑和文档保护流程。根 api/check/build、私有 typecheck/lint 通过，证据归 `mathInputCheckpoint`。未跑全量、安装包矩阵、外部 Office 或 OS 输入法验收；公式段落格式与富文本交换仍受保护。

P10 单层分数编辑通过 4 项定向核心检查，覆盖插入替换、原生 OMML、修改/删除、四步精确历史、重开、PAGE 字段插入回归和失败原子性。1 项接口检查通过 21 个断言；2 条 Chromium 流程通过，覆盖默认属性栏、原生输入、目录失效、源部件保留、精确历史及独立 Poppler PDF 的分子分母坐标和居中，保留既有显示/保护流程。根 api/check/build、私有 typecheck/lint 通过，证据归 `mathEditingCheckpoint`。未跑全量、安装包矩阵、外部 Office 或 OS 输入法验收；公式段落内的普通文字编辑和复杂公式仍待实施。

P12 雷达图通过 8 项定向核心检查，包含两项新雷达图用例及六项折线、复制和占位符回归；原复制用例扩展到雷达图，检查 12 种当前类型的独立资源。覆盖正负径向坐标、首末连接、空值断线、孤立/零值、单类别、有限大数、原生缓存与工作簿、类型切换、精确历史、重开及未知配置保护。接口检查通过 91 个断言。两条 Chromium 流程验证雷达图与散点图；新流程检查五处实际 Canvas/PNG/独立 PDF 像素、PDF 文字、原生轴/样式、嵌入数据、类型/数据编辑和四步精确历史。根 api/check/build、私有 typecheck/lint 通过，证据归 `radarChartCheckpoint`。未跑全量、安装包矩阵、外部 Office 或 OS 输入法验收；填充雷达及更多配置继续实施。

P11 文字旋转通过 22 项定向核心检查，包含两项新功能用例及 20 项格式/自动尺寸/缩小字体/缩进/对齐/条件格式回归。覆盖正负角度投影、跨 run 字素竖排、裁剪、自动行列尺寸、完整格式复制、非法参数、派生文字预算、公式保留、精确历史及重开；同时检查超大选中行列的起始边缘定位。2 项接口检查通过 101 个断言，3 条 Chromium 流程通过。新流程检查实际 Canvas 方向及竖排、独立 Poppler PDF 的旋转尺寸和竖排坐标、原生 XML、未改部件、后续输入及四步精确历史。根 api/check/build、私有 typecheck/lint 通过，详细证据归 `textRotationCheckpoint`。未跑全量、安装包矩阵、外部 Office 或 OS 输入法验收；东亚竖向字形替换仍待扩展。

P10 常用符号面板通过 1 条 Chromium 功能流程：选择符号替换原范围、保持粗体与颜色、继续原生输入、连续插入、组合期间禁用及取消恢复、三步精确撤销/重做、未改部件、保存重开、实际 Canvas 绘制和独立 Poppler PDF 文字。公开 check、UI/示例构建和私有 typecheck/lint 通过，证据归 `symbolsCheckpoint`。本次只接入默认控件，核心、桥与输入协议保持，复用已有核心结果；未加镜像接口测试或全量验收。数学排版、安装包、外部 Office 和 OS 输入法验收未执行。

P11 填充对齐通过 26 项定向表格核心检查，新增两项覆盖完整候选塑形、混合格式、换行/零宽内容、格式化数字、连续空单元格与局部裁剪、独立命中、原生 XF/DXF、自然自动列宽、复制、精确历史、重开和超限原子拒绝。2 项接口检查通过 84 个断言；3 条 Chromium 流程通过，跨列居中流程扩展填充控件、原生 XML、实际 Canvas 重复范围、独立 Poppler PDF 完整重复值与新增宽度、三步精确历史及重开，保留原对齐/分散/缩小字体回归。根 api/check/build 与私有静态检查通过，证据归 `fillAlignmentCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；剩余阶段要求继续实施。

P11 水平分散对齐通过 24 项定向表格核心检查，覆盖末行词间扩展、连续空格、单词居中、混合字号/装饰、隐式换行、RTL、双侧缩进、自动行列尺寸、原生 XF/DXF、格式复制、公式、精确历史及重开。2 项接口检查通过 82 个断言；3 条 Chromium 流程通过，扩展现有对齐流程检查默认控件、实际 Canvas 双侧边界和独立 Poppler PDF 的分散末行宽度，保留原生输入、三步精确历史、重开及跨列居中/缩小字体回归。根 api/check/build 和私有静态检查通过，证据归 `horizontalDistributionCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；其余阶段要求继续实施。

P11 跨列居中通过 22 项表格核心检查，新增两项覆盖范围宽度、独立命中、片段裁剪、复制、换行行高、RTL、公式/合并边界、资源拒绝与精确历史。2 项接口检查通过 80 个断言；3 条 Chromium 流程通过，新增默认控件、实际 Canvas 居中、单格原生输入、两步精确历史与重开，保留原对齐/缩小字体及独立 PDF 回归。根 api/check/build 和私有静态检查通过，证据归 `centerSelectionCheckpoint`。未跑全量、安装包、外部 Office、OS 输入法或跨列居中的冻结窗格/PDF 坐标专项；剩余阶段要求继续实施。

P12 百分比堆积柱形/条形图通过 10 项定向核心检查，覆盖绝对值总和归一化、同号累计、独立段坐标、百分比轴、原值缓存/工作簿、极大/极小值、空值/零值及未知源保护，并保留普通堆积与 11 种类型复制、历史和重开回归。1 项接口检查通过 87 个断言；原堆积 Chromium 流程扩展两种百分比类型，新增三步精确历史及重开，两种方向的 Canvas/PNG/独立 PDF 各九处像素、百分比文字和原值资源通过。根 api/check/build 与私有静态检查通过，证据归 `percentStackedChartsCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；其他配置和剩余阶段要求继续实施。

P12 堆积柱形/条形图通过 9 项定向核心检查，覆盖独立堆积段坐标、同号累计、总和轴、空值/零值、原生分组与工作簿、独立复制、精确历史、重开、未知源保护和累计溢出原子性，并回归簇状、折线及占位图表。1 项接口检查通过 79 个断言；1 条 Chromium 流程检查默认控件、值修改后的实际颜色、两种方向、类型切换、五步精确历史及重开。Canvas/PNG/独立 PDF 各检查两组九处像素，原生分组、轴、关系及当前嵌入工作簿值也通过；历史资源保留。根 api/check/build 与私有静态检查通过，证据归 `stackedChartsCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；其他图表配置和剩余阶段要求继续实施。

P12 四向实心箭头通过 9 项定向核心检查，覆盖独立 24 点轮廓、文字内框、三个联动手柄、源值与有效上限区分、精确边界、指针取消/提交、复制、六步精确历史、重开及未知公式保护，并回归原预设、调节和旋转/翻转输入流程。1 项接口检查通过 17 个断言；2 条 Chromium 流程检查默认控件和联动上限、实际指针、独立 XML、原生输入、精确历史和重开，Canvas/独立 PDF 八处轮廓像素及 PDF 文字通过。根 api/check/build 与私有静态检查通过，证据归 `quadArrowCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；更多预设和剩余阶段要求继续实施。

P11 垂直两端/分散对齐通过 20 项表格核心检查，覆盖等行间距、空行、自动换行、混合字号、单行、裁剪、绘制与链接边界同步，以及原生 XF/DXF、复制、自然自动列宽、值/公式、精确历史和重开。2 项接口检查通过 78 个断言；2 条 Chromium 流程检查默认控件、原生 XML、实际 Canvas 行位置、独立 Poppler PDF 坐标、单行分散居中、原生输入、三步精确历史及重开，并保留缩小字体适应回归。根 api/check/build 和私有静态检查通过，证据归 `verticalAlignmentCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；其余阶段要求继续实施。

P10 SEQ 按标题重启通过 21 项字段核心检查和 3 项共享排版回归，覆盖继承/直接/格内大纲、两个重启级别、混合计数、样式修改、片段、缓存、四步精确历史、重开及长前缀有界求值。6 项接口检查通过 329 个断言，包含级别、必需大纲映射和带标题后缀的起点上限。2 条 Chromium 流程检查标题重启控件、作用域清除后的实际编号、五步精确历史、原生输入、独立 XML、Canvas/PDF 及既有 REF 链接。根 api/check/build 与私有静态检查通过，证据归 `sequenceHeadingCheckpoint`。其余 Flow 夹具只同步必需空映射，未扩大运行范围。未跑全量、安装包、外部 Office 或 OS 输入法验收；目录、题注及剩余阶段功能继续实施。

P12 左右/上下双向箭头通过 8 项定向核心检查，覆盖独立轮廓、文字内框、手柄依赖和限值、旋转/翻转命中、预览取消、复制隔离、六步精确历史、重开及未知源保护，并回归既有预设和调节事务。1 项接口检查通过 13 个断言；2 条 Chromium 流程检查新默认控件与既有调节拖动，独立 XML、实际指针取消/提交、原生输入、历史重开、Canvas/PDF 八处轮廓像素及 PDF 文字通过。根 api/check/build 与私有静态检查通过，证据归 `doubleArrowCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；更多箭头及剩余阶段功能继续实施。

P11 水平两端对齐通过 19 项表格核心检查和 3 项共享排版回归，覆盖等词间隙、混合字号/装饰、末行/无间隙/换行/裁剪、RTL 边界、缩进组合、自然自动列宽、复制、差异格式、四步精确历史及重开，并保留既有 CJK/bidi 排版规则。2 项接口检查通过 71 个断言；2 条 Chromium 流程检查新默认控件与既有缩小字体适应，独立 XML、原生输入、Canvas 首行/末行位置和 Poppler PDF 边界通过。根 api/check/build 与私有静态检查通过，证据归 `justifiedCellsCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；其余对齐及剩余阶段功能继续实施。

P10 SEQ 重新起算和重复编号通过 19 项定向核心检查，覆盖原生开关、当前/后续编号、零及最大起始值、复杂域显示、剪贴板、显式缓存、四步精确历史、重开及无效操作原子性，并回归正文域、PAGEREF 和 REF。6 项接口检查通过 304 个断言；2 条 Chromium 流程检查 SEQ 默认计数控件、输入清空/恢复、原生 XML、Canvas、PDF 文字与既有 REF 及内部链接。根 api/check/build 与私有静态检查通过，证据归 `sequenceControlCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；隐藏、标题重置及剩余阶段功能继续实施。

P10 段内 REF 文字引用通过 18 项定向核心检查，覆盖书签范围、嵌套域当前值、表格目标、改名与输入、剪贴板、显式缓存、精确历史、重开及循环/换行/跨段源保护，并回归 SEQ、正文域、代码修改、PAGEREF 和片段。5 项接口检查通过 254 个断言；2 条 Chromium 流程检查 REF 默认控件及既有 PAGEREF，覆盖真实输入、独立 XML、四步精确历史、Canvas、PDF 文字和 qpdf 内部链接。根 api/check/build 与私有静态检查通过，证据归 `textReferenceCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；跨段富文本、其他 REF 格式与开关及剩余阶段功能继续实施。

P12 圆环图通过 8 项定向核心检查，覆盖同心环路径、独立系列权重、空心比例、正负/极值/空数据、独立资源、类型切换、五步精确历史及重开，并复用饼图、七种图表对象复制和占位符填图。1 项接口检查通过 71 个断言；1 条 Chromium 流程检查默认控件、独立 XML/嵌入数据、空心变化、四步精确历史、重开及一致的 Canvas/PNG/PDF 三点像素。根 api/check/build 与私有静态检查通过，证据归 `doughnutChartCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；其他原生图表配置及剩余阶段功能继续实施。

P11 缩小字体适应通过 17 项定向核心检查：新增两项覆盖普通/混合字号、半磅步长、最小字号、换行优先、自动尺寸、复制、差异格式、精确历史及重开，复用缩进、格式/格式刷/清除、自动尺寸和条件格式。2 项接口检查通过 70 个断言；1 条 Chromium 流程检查默认控件、原生 XML/字号、实际 Canvas 字形缩小、完整 PDF 文字、原生输入、三步精确历史和重开。根 api/check/build 与私有静态检查通过，证据归 `shrinkToFitCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；旋转、其他对齐及其余阶段功能继续实施。

P10 SEQ 序列域通过 16 项定向核心检查，覆盖正文/表格顺序、独立名称和格式、复杂域读取、缓存刷新、输入、剪贴板、精确历史与重开，并回归正文域、代码修改、PAGEREF 和字段片段。3 项接口检查通过 100 个断言；2 条 Chromium 流程检查序列域默认控件及既有 PAGEREF，覆盖独立 XML、实际 Canvas、原生输入、历史和 PDF 文字。根 api/check/build 与私有静态检查通过，证据归 `sequenceFieldCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；SEQ 扩展开关、完整题注及其余阶段功能继续实施。

P11 单元格缩进通过 15 项定向核心检查：新增两项覆盖 Normal 字体距离、左右位置、复制、混合查询、自动尺寸、差异格式、源保护、精确历史及重开，并回归格式/清除/格式刷、自动尺寸及条件格式。1 项接口检查通过 36 个断言；1 条 Chromium 流程检查默认控件、独立 XML、原生输入、三步精确历史、重开及实际 Canvas/PDF 左右各 18 pt 的位置变化。根 api/check/build 与私有静态检查通过，证据归 `cellIndentCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；相对缩进、旋转、其他对齐及其余阶段功能继续实施。

P12 原生双段曲线连接线通过 11 项定向核心检查，既有折线用例同时覆盖曲线几何、切线、极值、命中、转折预览、目标联动、组合复制、原子保护、精确历史及重开。1 项接口检查通过 51 个断言；两条 Chromium 默认控件流程检查折线和曲线的独立 XML、四步精确历史、重开及相同 Canvas/PDF 路径像素。根 api/check/build 与私有静态检查通过，公开原生接口不变；证据归 `curvedConnectorCheckpoint`。前序折线范围见 `elbowConnectorCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；框外转折、其他预设、避障与跨父容器连接继续实施，完整阶段保持未完成。

P11 百分比 `%` 与乘方 `^` 通过 12 项定向核心检查，新增两项覆盖优先级、类型与有限值错误、百分比隐式取值、深度预算、共享公式、填充后缀、符号表名与五步精确历史，复用数值函数、文本连接及 SUMPRODUCT 回归。1 条 Chromium 流程检查真实输入、依赖重算、已有百分比格式、独立 XML、四步精确历史、保存重开后继续编辑及同一 PDF 数值。根 api/check/build 与私有静态检查通过，公开 XLSX 接口不变；证据归 `percentPowerCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；自动格式推断、通用数组及其余阶段功能继续实施。

P11 文本连接 `&` 通过 14 项定向核心检查：新增两项覆盖优先级、类型/错误、Unicode、单行/单列取值、共享公式、填充、带符号表名、精确历史、重开及工作量原子回滚，复用文字函数、HYPERLINK、逻辑及 SUMPRODUCT 回归。既有 HYPERLINK Chromium 流程改用拼接的外部地址和跨表目标，独立 XML、实际导航、四步精确历史、重开及 qpdf URI/XYZ 注释通过。根 api/check/build、私有静态检查和接口不变检查通过，证据归 `concatOperatorCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；通用数组及其余阶段功能继续实施。

P11 HYPERLINK 通过 16 项定向核心检查，新增三项覆盖类型与错误、已选结果地址、依赖与缓存、普通链接优先级、合并主格、PDF 及资源上限，复用逻辑、查找、普通链接和打印回归。1 条 Chromium 流程检查公式栏真实输入、结果不变时地址重算、显式安全打开、未选分支、原生源与四步精确历史、保存重开及独立 qpdf URI/跨表跳转注释。根 api/check/build 与私有静态检查通过；证据归 `formulaHyperlinkCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；数组和动态引用继续实施，P10/P11/P12 保持部分完成。

P10 可编辑标题封面通过 8 项定向核心检查，包含新增的两项封面生命周期及原子保护检查，以及既有书签和页面设置回归。1 项边界检查和 1 条 Chromium 流程覆盖默认控件、真实输入、未改部件、独立 XML、四步精确历史、重开继续编辑及 PDF 分页。公开构建、生成接口、根和私有静态检查通过，证据归私有 `coverPageCheckpoint`。未跑全量、安装包、外部 Office 或 OS 输入法验收；模板库、多节和分栏封面继续实施，P10/P11/P12 保持部分完成。

PPTX 原生三段折线连接线通过 15 项定向核心检查、1 项接口检查（48 个断言）及两条既有 Chromium 流程。覆盖转折、箭头实际方向、目标联动、组合复制、未知几何保护、精确历史与重开，独立 XML 和 Canvas/PDF 三段像素一致。根 api/check/build 与私有静态检查通过，详细范围归 `elbowConnectorCheckpoint`。框外转折、曲线、其他折线及跨父容器连接继续实施；未跑全量、安装包、外部 Office 或 OS 输入法验收。P10/P11/P12 仍为部分完成。

DOCX 图片指针重锚通过 25 项定向核心检查。新增三项覆盖跨段/同段跨页、方形环绕、候选选区、参考原点、锚点锁、失败保留及取消/末次坐标的精确历史；复用原定位、尺寸、重锚与布局回归。传输通过两项、59 个断言。Chromium 新跨页拖动和原移动流程通过，检查缩放后的边缘滚动/翻页、取消、松手/保存末次坐标、独立原生 XML/资源、Canvas、精确历史及重开。原移动流程保留 PDF 与原生输入检查，跨页 PDF 复用前序 SDK 结果。根 api/check/build、私有静态检查和源码上限已检查；证据归 `docxPicturePointerCheckpoint`。未跑全量、安装包或外部 Office；更多浮动对象及其余 P10/P11/P12 继续实施。

DOCX 图片源锚点迁移通过 22 项定向核心检查，包含新增的跨段命名空间/运行格式/身份与资源保留、同段偏移和空段、锚点锁/字符边界/未知源的原子拒绝，以及既有移动、缩放、定位和布局回归。定位传输通过 2 项、54 个断言。新增一条 Chromium SDK 流程通过跨页迁移、源 XML/非目标部件、Canvas/PDF、单项历史、保存重开及后续原生输入。根 api/check/build 与私有静态检查通过；详情归 `docxPictureReanchorCheckpoint`。默认指针跨段重锚、边缘翻页及其余 P10/P11/P12 继续实施；未跑全量、安装包或外部 Office。

DOCX 浮动图片移动通过 19 项定向核心检查，覆盖原始位移派生、对齐参考系、候选/取消、最终坐标、空操作、独立移动/缩放保护锁、失败保留预览、精确混合历史、资源及重开，并复用图片选择、尺寸、定位和环绕回归。传输及 Flow 通过 5 项、191 个断言。Chromium 的新移动流程与原选择/缩放、定位、方形环绕共四条通过；检查缩放后的真实拖动、Canvas/PDF 像素、键盘移动、取消、保存末次位置、混合历史、重开删除和原生输入。根 api/check/build、私有 typecheck/lint/format、源码上限、入口/导出及新旧手势名称已检查。证据归 `docxPictureMoveCheckpoint`。未跑全量、安装包或外部 Office；跨段重锚、边缘翻页及其余 P10/P11/P12 继续实施。

DOCX 方形环绕通过 33 项定向核心检查，包括共享断行/自动行距的 5 项原回归及与下段/表格同页的 6 项原回归。覆盖同一行两侧文字和基线、连续光标/选区、RTL、四种侧向、编号、后置图片命中、整页图片续页、缓存及原生 XML 的四边间距覆盖、资源和精确历史。传输及 Flow 通过 4 项、176 个断言；Chromium 的图片定位及方形环绕两个流程通过，检查两侧 Canvas/PDF 文字像素、侧向切换、无变化、精确混合历史和重开输入。根 api/check/build 与私有 typecheck/lint/format 已检查；证据归 `docxSquareWrappingCheckpoint`。未跑全量、安装包或外部 Office；拖动移动及其余 P10/P11/P12 继续实施。

DOCX 图片上下型环绕通过 18 项定向核心检查，包含普通/合并表格续页的 6 项原回归。覆盖前文避让、四边间距与源覆盖、整页图片锚点、段落保留/孤行、长表表头、缓存、命中/选区、精确历史，以及缺字体/解码资源时的原子拒绝。传输及 Flow 通过 4 项、168 个断言；扩展既有 Chromium 默认流程，检查原生环绕 XML、文字避让的实际 Canvas/PDF 像素、整页图片后的文字续页、尺寸/环绕混合历史与重开。根 api/check/build、私有 typecheck/lint/format 和源码上限已检查。证据归 `docxTopBottomWrappingCheckpoint`。未跑全量、安装包或外部 Office；方形环绕、拖动移动及其余 P10/P11/P12 继续实施。

DOCX 图片定位通过 9 项定向核心检查，覆盖行内/前置/后置切换、两轴参考系、页眉避让后的源边距、缓存、命中/选区、裁剪、精确历史、重开和失败原子性。传输及 Flow 检查通过 4 项、163 个断言。Chromium 默认流程覆盖创建后定位、原生参数、无变化、层次、独立 ZIP/XML/资源、精确历史、重开点击/输入及 Canvas/PDF 像素；证据归 `docxPicturePositionCheckpoint`。未跑全量、安装包或外部 Office；方形/上下型环绕、拖动移动和其余 P10/P11/P12 继续实施。

工作表基础图形的默认面板和通用画布控件通过 17 项定向核心检查；参数、选择及层次传输通过 3 项、58 个断言。新增 Chromium 默认流程通过 1/1，覆盖四种对象创建、属性与统一文字设置、自由缩放候选/取消、移动和键盘、零轴直线命中、图片/图形分别删除与恢复、混合图层、无变化、完整混合历史、独立原生源、重开输入和 PDF。原图片手势与图形 SDK 分别通过 1/1，复查通用 `objects` 目录及新绘图入口。根 api/check/build 通过，私有 typecheck/lint/format 和源码上限、链接、阶段状态已检查。证据归 `xlsxWorksheetShapeControlsCheckpoint`。未跑全量或外部 Office；复杂图形、更多文字变体和边缘自动滚动继续实施，P10/P11/P12 保持 planned。

工作表基础图形的核心与 SDK 通过 17 项定向核心检查和 22 个传输断言。覆盖四种基本对象、混合图片身份/顺序、文字和字体、椭圆文字边界、零轴直线、自由缩放候选、精确历史、行列锚点、工作表复制、重开及失败保护。新增 Chromium SDK 流程通过 1/1，覆盖真实 Worker 与同步 Wasm API、独立 XML/PNG、Canvas 颜色、原生粗体文字、无变化、删除恢复、重开输入及 PDF 文字/颜色。原图片裁剪流程也通过 1/1，复查拆分后的图片传输。证据归 `xlsxWorksheetShapeSdkCheckpoint`。此记录对应核心与 SDK 切片；默认界面与画布交互的后续证据见 `xlsxWorksheetShapeControlsCheckpoint`。未跑全量或外部 Office，P10/P11/P12 保持 planned。

工作表图片裁剪通过 14 项定向核心检查及 27 个传输断言，覆盖原生精度、无变化、重置、图片字节、手势与复制保留、精确混合历史及重开输入。无效值、舍入后为空、锁定、未知裁剪元数据及绘制超限原子拒绝。新增 Chromium 流程通过 1/1，覆盖默认百分比面板、无效组合禁用、实际四色裁剪/重置、对象键盘、只重置裁剪、独立 XML/PNG、混合历史、重开及 PDF 文字/像素。根 api/check/build 和私有 typecheck/lint 通过；证据归 `xlsxWorksheetPictureCropCheckpoint`。未跑全量或外部 Office；负裁剪扩边、复杂绘图和其余图片交互继续实施，P10/P11/P12 保持 planned。

普通图片表的复制、改名及删除通过 17 项定向核心检查，覆盖独立绘图与关系、不可变图片字节、表格/便笺共存、自身公式、混合输入、精确历史和重开。未知对象/链接/身份、共享绘图、结构保护及输出超限原子拒绝。新增 Chromium 流程通过 1/1，覆盖首次打开和重开后的可用按钮、副本独立图片编辑、删除源表与副本、实际 Canvas、独立 OPC/XML/PNG、原生输入及 PDF 文字/像素。首次状态刷新沿现有队列串行执行；根 api/check/build 和私有 typecheck/lint 通过。证据归 `xlsxWorksheetPictureSheetsCheckpoint`。未跑全量或外部 Office；复杂绘图和局部单元格迁移继续实施，P10/P11/P12 保持 planned。

工作表图片行列结构通过 19 项定向核心检查，覆盖三种锚点、插入/截断、偏移与最小跨度、自动行高后的姿态、未受影响的原源、精确历史和重开。未知/共享绘图、保护、局部移位、越界及预算失败保留源与历史。新增 Chromium 流程通过 1/1，覆盖默认行列按钮、实际 Canvas、独立锚点/姿态 XML、PNG 字节、混合输入、精确撤销/重做、重开及 PDF 文字/像素。根 api/check/build 和私有 typecheck/lint 通过；证据归 `xlsxWorksheetPictureAxisCheckpoint`。未跑全量或外部 Office；局部单元格移位及其余绘图继续实施，P10/P11/P12 保持 planned。

工作表图片图层通过 6 项定向核心检查，覆盖四种顺序、边界无变化、原始锚点/资源/注释空白、精确混合历史、重开与失败保护。新图层及原手势流程分别通过 1/1 Chromium；独立 XML/PNG 字节、真实重叠颜色、ShadowRoot 点击目标、默认按钮、原生输入、重开及 PDF 顶层像素通过。传输通过 1 项、13 个断言；根 api/check/build 和私有 typecheck/lint 通过。证据归 `xlsxWorksheetPictureLayerCheckpoint`。未跑全量或外部 Office；混合绘图、组和边缘自动滚动继续实施，P10/P11/P12 保持 planned。

工作表图片手势通过 23 项定向核心检查，新增候选只读、绘制身份、单项原生历史、图片选择恢复、四角比例、冻结/RTL 和过期几何保护。新 Chromium 手势流程通过 1/1，原图片面板回归也通过 1/1；覆盖实际预览/取消、保存取消、拖动/缩放、对象键盘、原生输入、精确历史、独立 XML/PNG、重开及 PDF 文字/像素。传输检查通过 1 项、19 个断言；根 api/check/build 及私有 typecheck/lint 通过。证据归 `xlsxWorksheetPicturePointerCheckpoint`。未跑全量或外部 Office；边缘自动滚动继续实施，P10/P11/P12 保持 planned。

工作表图片通过 22 项定向核心检查，覆盖三种锚点、行列尺寸、冻结/RTL、分页裁剪、不随表打印、资源事务、精确混合历史、重开及失败原子性，并复用便笺和打印回归。新增 Chromium 流程通过 1/1，覆盖默认面板、PNG/JPEG 原生字节、位置/尺寸/文字、删除、原生输入、精确历史、重开、实际 Canvas/PDF 像素及损坏图片拒绝。根 api/check/build、私有 typecheck/lint 通过；证据归 `xlsxWorksheetPictureCheckpoint`。未跑全量或外部 Office；复杂绘图和更多锚点变体继续实施，P10/P11/P12 保持 planned。

正文完整跨表格范围通过 39 项定向核心检查，覆盖共享编号/书签、合并网格、链接/图片/简单域、复制/剪切/替换、输入法取消、范围格式、精确历史及失败原子性。新流程和既有正文剪贴板回归先通过 2/2 Chromium，补齐整表属性后只复跑新流程，通过 1/1；覆盖实际鼠标选择、默认 Copy、快捷键剪切、跨文档原生粘贴、独立 XML/PNG 字节、格内输入、重开及 PDF 文字/四色像素。根 api/check/build 与私有 typecheck/lint 通过；详细失败定位及证据归 `docxMixedBodyTableClipboardCheckpoint`。未跑全量、外部 Office 或安装包矩阵；部分跨入单元格、跨不同表格端点和嵌套结构继续实施，P10/P11/P12 保持 planned。

HTML 普通表格通过 16 项定向核心检查，覆盖合并网格、列组宽度、格内格式/列表/链接/图片、三种方式、段落边界与段前分页、精确混合历史、重开及失败原子性。新 Chromium 流程与原 HTML 流程先通过 2/2，补齐列组与边界后只复跑新流程，通过 1/1；独立 XML、PNG 字节、原生格内输入、重开、实际 PDF 文字及黄色底色/图片三色像素通过。根 api/check/build 与私有 typecheck/lint 通过，证据归 `docxHtmlTableInputCheckpoint`。未跑全量、外部 Office 或安装包全功能矩阵；嵌套表格、caption、重复表头及更广 CSS 继续实施，P10/P11/P12 保持 planned。

PPTX 调节手柄通过 13 项定向核心检查，覆盖现有 12 种可调预设的局部轴、旋转/翻转、候选只读、上下限、取消、精确混合历史、重开和失败原子性。既有连接线回归发现重复变换写入，修改前代码也能复现；修正源姿态比较后，两项端点流程通过。新增指针流程与原辅助线流程共 2/2 Chromium，通过独立 XML、原生输入、保存重开及 Canvas/PDF 像素；传输 1 项、11 个断言通过。根 api/check/build 与私有 typecheck/lint 通过，证据归 `pptxAdjustmentGestureCheckpoint`。未跑全量、外部 Office 或安装包全功能矩阵；P10/P11/P12 保持 planned。

XLSX 多打印区域通过 9 项定向核心检查，覆盖顺序、独立分页、重复标题、共用缩放、连续页码、跨表总页数、联合引用维护、精确混合历史、保存重开与累计上限。既有 Chromium 流程扩展到两个区域，通过独立 XML、8 页实际 PDF、全部正文/标题文字、原生草稿和重开输入；传输检查 1 项、22 个断言通过。根 api/check/build 与私有 typecheck/lint 通过，证据归 `xlsxMultiplePrintAreasCheckpoint`。未跑全量、外部 Office 或安装包全功能矩阵；P10/P11/P12 保持 planned。

HTML/Markdown 内嵌 PNG/JPEG 通过 17 项定向核心检查，含新增两项及三种方式、两类输入、正文片段、旧图片插入和单元格图片回归。覆盖资源预检只读、MIME/尺寸/预算、alt/title、同源去重、原生身份/部件、三种方式、精确混合历史、重开及失败原子性。新 Chromium 流程通过默认面板、本地实际解码、PNG/JPEG 独立字节/XML、继续输入、历史、重开和 PNG/PDF 真像素；外链零请求，损坏压缩数据在提交前拒绝，纯文本仅提取 alt 且不增部件。根 api/check/build、私有 typecheck/lint 和新安装包严格宿主编译通过；证据归 `docxMarkupImageInputCheckpoint`。未跑全量或外部 Office；表格、水平线、外链/复杂图片和更广输入继续实施。

HTML/Markdown 三种粘贴方式通过 9 项定向核心检查，含新增两项及既有两类输入和正文片段回归。覆盖源格式、插入点格式合并、纯文本、反向范围、强调/链接/列表/标题、单格待输入格式、源字体消除、精确混合历史及失败原子性。纯文本不创建编号或关系部件，并在提交前预检目标字体/布局。该缺字体回归先失败，再通过原子拒绝检查；最后只重跑受影响 HTML 流程，通过 1/1，沿用已通过的 Markdown 回归。既有 HTML 浏览器流程扩展到默认方式选择、独立 XML/部件、继续输入、历史、重开及实际 PDF，与 Markdown 回归共 2/2。根 api/check/build、私有 typecheck/lint 和新安装包严格宿主编译通过；证据归 `docxMarkupPasteModeCheckpoint`。未跑全量或外部 Office；图片、表格、水平线及更广交换结构继续实施。

首批 HTML 粘贴通过 14 项定向核心检查，含新增两项和 Markdown、正文片段、列表/链接转移、DOCX 保护回归。覆盖 HTML5 容错、普通/保留空白、NBSP、常用样式、标题/引用/列表/代码/外链、活动内容清理，以及正文/单格、原生输入、精确混合历史、重开和失败原子性。新 HTML Chromium 流程与既有 Markdown 回归共 2/2，通过默认格式选择、实际系统 text/html、独立 XML/部件、三步历史、重开、实际 PDF 和零外链请求。根 api/check/build、私有 typecheck/lint 及新安装包严格宿主编译通过；证据归 `docxHtmlInputCheckpoint`。未跑全量或外部 Office；图片、表格、水平线及更广输入继续实施；三种粘贴方式进度见上文。

首批 CommonMark 粘贴通过 12 项定向核心检查，含新增两项及原有正文片段、列表/链接转移和 DOCX 保护回归。覆盖标题、强调、实体/转义、软硬换行、引用、嵌套列表、代码 Tab/换行和外链，以及正文/单格替换、精确混合历史、重开和失败原子性。新 Chromium 流程通过默认粘贴模式、原生输入、独立 XML/部件、历史、重开、实际 PDF 和错误恢复。根 api/check/build、私有 typecheck/lint 与新安装包严格宿主编译通过；证据归 `docxMarkdownInputCheckpoint`。未跑全量或外部 Office；HTML 与三种方式进度见上文；图片、水平线、扩展及更广输入继续实施，P10/P11/P12 保持 planned。

DOCX 只读编辑保护通过 29 项定向核心检查，包含新增两项及原有输入、格式、表格、修订、组合输入和 XLSX 两类保护回归。覆盖首次设置部件、原生凭据、统一写入及候选拒绝、密码/无密码、错误恢复、源保留、五步精确历史、重开及预算。新 Chromium 流程检查默认面板、密码确认/清空、只读输入和格式控件、直接接口拒绝、独立 Node SHA-512、错误密码、解除后输入、三步历史、重开和实际 PDF；既有 XLSX 工作簿保护流程也通过。传输检查 29 项断言、新安装包严格宿主编译及根 api/check/build 通过；详细证据归 `docxReadOnlyProtectionCheckpoint`。未跑全量或外部 Office；旧式保护参数、细分权限及加密仍待实现。

简单页码域指令编辑通过 18 项定向核心检查，含新增两项及既有域、片段、段落拆合和组合输入回归。覆盖完整/反向域选择、光标亲和、正文及普通格、原生指令与 MERGEFORMAT 保留、当前缓存、格式与空 run、其他域只读、无操作、精确历史、重开和失败原子性。既有正文页码 Chromium 流程扩展到默认面板读改、独立 XML、实际 PDF、旧选择拒绝、原生输入、三步历史和重开。传输检查通过两项用例及 40 项断言，新安装包同步/Worker/编辑器入口通过严格宿主编译；根 api/check/build 与私有静态检查通过。记录归 `bodyPageFieldCodeCheckpoint`。未跑全量或外部 Office；复杂域范围及其他指令仍待实现，P10/P11/P12 保持 planned。

简单页码域整格剪贴板通过 36 项定向核心检查，含新增两项及既有正文/表格片段、图片、链接、输入和查找回归。覆盖反向矩形的当前值 TSV、原生域与格式、目标缓存且旧域保持、扩表、完整合并格、组合取消/提交、整格清空、精确历史、重开及无效布局/片段保护。既有单元格图片 Chromium 流程扩展到混合域，检查实际系统剪贴板、写入失败与延迟、原生删除、跨文档覆盖、独立 XML、查找后输入、重开、Canvas 和 PDF 文字/像素。根 api/check/build 与私有静态检查通过，证据归 `cellPageFieldClipboardCheckpoint`。TS 协议未变，沿用安装包宿主编译；MoonBit `table_clipboard` 新增可选当前布局参数。未跑全量或外部 Office；复杂域及其他指令继续实施。

正文简单页码域剪贴板通过 23 项定向核心检查，包含新增两项和既有域、正文/表格片段、链接、图片及纯文本剪贴板回归。覆盖实际页码与总数、原代码和格式、原缓存只读、目标重算且保留旧域缓存、重复粘贴、精确历史、重开、空结果及布局/指令保护。既有正文富文本 Chromium 流程扩展到系统剪贴板的默认复制/粘贴、原生剪切、独立 XML、历史、重开、Canvas/PNG/PDF，以及空结果域跨文档粘贴。根 api/check/build 与私有静态检查通过，记录归 `bodyPageFieldClipboardCheckpoint`。TS 接口形状未变，沿用前批严格宿主编译；MoonBit 两个查询新增可选当前布局参数。整格/跨格域片段进度见上文；复杂域继续实施；未跑全量或外部 Office。

正文简单页码域段落拆合通过 26 项定向核心检查，包含新增两项和既有域、输入、删除、书签、批注、图片及组合输入回归。覆盖域两侧的两种光标亲和、独立域与混合文字、正文与同格段落、整域范围删除、继承格式及局部命名空间、跨段锚点恢复、组合预览与提交、预算和精确历史。既有 Chromium 流程扩展到真实 Enter/Backspace、拆合后的逐行文字、四步精确历史、重开及 Canvas/PNG/PDF 字形。根 api/check/build 与私有静态检查通过，记录归 `bodyPageFieldStructureCheckpoint`。公开接口未变，复用前批严格宿主证据；未跑全量或外部 Office。

正文简单页码域格式通过 25 项定向核心检查，包含新增两项和既有域、格式、字符间距、跨格格式及组合输入回归。覆盖首个实际结果 run、混合文字范围、完整域、代码/缓存/空 run 保留、格式捕获、待输入格式、精确历史和重开，以及未知/锁定/复杂源保护。既有 Chromium 流程扩展到默认字号、颜色、下划线和段落对齐，检查独立 XML、四步精确历史、重开及实际 Canvas/PNG/PDF 蓝色字形。根 api/check/build 与私有静态检查通过，记录归 `bodyPageFieldFormattingCheckpoint`。公开接口未变，沿用前批严格宿主编译；未跑全量或外部 Office。

正文简单页码域插入及原生输入通过 20 项定向核心检查，包含新增两项和既有字段、图片、组合输入、删除、查找与书签回归。覆盖反向范围替换、相邻域、完整缓存与格式、逻辑光标、整域删除、组合取消/提交、五步精确历史、空段落、单元格、重开和保护。既有 Chromium 流程扩展到两个默认插入按钮、实际键盘选择/输入/删除、独立 XML、四步精确历史、重开与 PDF 当前文字。传输检查通过 23 项断言；新公开类型及同步、Worker、宿主入口通过安装包严格编译。根 api/check/build 与私有静态检查通过，记录归 `bodyPageFieldInsertionCheckpoint`，后续格式、拆合及范围剪贴板进度见上文。复杂域范围仍未完成；未跑全量或外部 Office。

正文页码整体排版通过 16 项定向核心检查，复用字段、分页、命中与选区用例。覆盖固定逻辑位置、完整数字换行、空结果、真实字形簇、RTL、格式装饰、Tab 和缓存。既有 Chromium 流程检查位数变化后的逻辑范围，以及刷新、原生分页输入、精确历史、重开和 Canvas/PNG/PDF。检查发现并修复 RTL 字段前后光标方向。根 api/check/build 与私有静态检查通过；公开接口未变，复用前批严格宿主编译。记录归 `bodyPageFieldAtomsCheckpoint`，后续插入与输入进度见上段。未跑全量或外部 Office。

P10 正文页码字段通过 11 项定向核心检查，包含新增四项和既有页边字段、分页及节编号回归。覆盖实际页号/总数、罗马格式、分栏物理页、单元格续排、缓存复用、显式刷新与无操作、三步精确历史和重开，以及未知/锁定/嵌套/注释源、旧 revision、字体、数量与重复表头保护。新增一条 Chromium 流程检查默认刷新按钮、重复刷新后的原生分页输入、独立 XML、原部件保留、混合历史、重开及 Canvas/PNG/PDF。流程发现并修复了共用页面桥在无变化命令后清除当前布局的问题。安装后的同步、Worker 和宿主刷新入口通过严格编译，根 api/check/build 与私有静态检查通过，记录归 `bodyPageFieldsCheckpoint`，后续插入与输入进度见上文。未跑全量或外部 Office，P10/P11/P12 保持 `planned`。

P12 散点图通过 10 项定向核心检查，包含新增两项和既有柱/条/折线/面积及独立复制回归。覆盖共享数值 X、重复及无序坐标、缺失配对、双数值轴、原生缓存/工作簿、类型切换、四步精确历史和重开，以及非法/溢出 X、未知配置和字体保护。新增一条 Chromium 流程检查默认面板、独立 XML、真实数据点与空白位置、四步历史、重开及相同位置的 Canvas/PNG/PDF。传输用例通过 34 项断言，安装后的 Wasm/Web 类型与插入/数据命令通过严格宿主编译。根 api/check/build、私有静态检查及受影响链接通过，记录归 `scatterChartsCheckpoint`。未跑全量或外部 Office；P10/P11/P12 保持 `planned`。

P12 面积图通过 8 项定向核心检查，包含新增两项、既有柱/条/折线及独立图表复制回归。覆盖零轴闭合、正负段、空值间隙、系列覆盖、首末类别位置、原生缓存/工作簿、类型切换、四步精确历史、重开及未知配置/数值/字体保护。新增一条 Chromium 流程检查默认类型与数据面板、独立 XML、实际填充/空白像素、四步历史、重开及相同位置的 Canvas/PNG/PDF。现有传输用例扩展后通过 31 项断言，安装后的 Wasm/Web 公共类型及两种面积图命令通过严格宿主编译。根 api/check/build、私有静态检查和受影响链接通过，记录归 `areaChartsCheckpoint`。未跑全量或外部 Office；P10/P11/P12 保持 `planned`。

P11 迷你图区域剪切通过 15 项定向核心检查，包含新增两项及既有行列、单元格移动、便笺、规则和链接复制/移动回归。覆盖图形/数据分别或共同移动、重叠覆盖、跨表及第三张表依赖、端点扩缩/交叉、部分来源、七步精确历史、重开，以及数量/保护/输出预算失败。既有跨表便笺剪切 Chromium 流程扩展到原生图形、真实系统剪贴板、目标覆盖、原生输入、独立 XML、三步混合历史、重开及 Canvas/PDF。组合流程发现并修复了新建关系部件再追加超链接时的创建快照覆盖，精确撤销断言保留。根 api/check/build、私有静态检查及文档链接通过，本轮归 `sparklineMovesCheckpoint`。公开 API 和包清单未变，沿用前批剪贴板安装包和严格宿主证据。普通图表、绘图锚点及 P10/P11/P12 其余范围继续实施；未跑全量或外部 Office。

P12 含图表的页面复制通过 6 项定向核心检查，包含新增两项，覆盖独立资源、双向改数据、备注/批注、隐藏状态、删页、五步精确历史及重开。已删图表留下的关系完整复制，未知配置、复制锁、工作簿不一致及预算失败保留源和计数器。新增一条 Chromium 流程检查默认复制页按钮、备注、新对象身份、原始工作簿字节、独立数据修改、页间导航、三步混合历史、重开及两页 PDF 的文字和不同饼图像素。根 api/check/build 与私有静态检查通过，公开接口未变，沿用前批安装包清单和宿主编译证据。记录归 `chartSlideCopiesCheckpoint`。未跑全量或外部 Office；P10/P11/P12 其余范围继续实施。

P12 图表对象复制通过 11 项定向核心检查，包含新增两项，覆盖四种图表、独立资源、双向改数据、混合多选、精确历史、重开、复制锁、缓存/工作簿不一致及未知资源保护。普通对象、表格和原有页面复制检查保持通过。新增一条 Chromium 流程检查默认复制按钮、副本移动和数据编辑、原图 XML/工作簿原字节、四步混合历史、重开及 Canvas/PDF 像素。根 api/check/build 通过。公开接口未变，复用前批安装包清单和严格宿主编译结果。证据归 `chartObjectCopiesCheckpoint`。未跑全量或外部 Office；含图表的页面复制与 P10/P11/P12 其余范围继续实施。

P12 饼图通过 6 项定向核心检查，包含新增两项，覆盖独立扇区与控制点、负值和完整源系列、空图/完整圆、极大数值、图例容量、精确历史、重开及未知原生配置保护。既有 Chromium 图表流程扩展至饼图，检查默认面板、原生系列/颜色/缓存、无数轴、四象限和图例像素、五步混合历史、重开与 PDF。28 项接口断言、3327 项安装包断言与严格宿主编译、根 api/check/build 均通过。证据归 `pieChartsCheckpoint`。未跑全量或外部 Office；其他类型及完整 P10/P11/P12 继续实施。

P12 折线图通过 4 项定向核心检查，包含新增两项，覆盖独立坐标、空值断线、孤立/零值标记、嵌入工作簿、类型切换、精确历史、重开及未知曲线/标记保护。原有 Chromium 图表流程扩展为柱形→条形→折线，检查默认控件、原生缓存、线段与标记像素、空白间隙、历史、重开和 PDF。25 项接口断言、3327 项安装包断言与严格宿主编译、根 api/check/build 均通过。证据归 `lineChartsCheckpoint`。未跑全量或外部 Office；其他图表类型及完整 P10/P11/P12 继续实施。

P12 基础簇状柱形图和条形图通过 9 项定向核心检查、22 项接口断言、1 条 Chromium 流程及 3327 项安装包断言与严格宿主编译。检查正负/空/零值、独立柱体坐标、原生缓存和嵌入 XLSX、数据修改、移动、删除、精确历史、重开与 Canvas/PDF 像素和文字。PDF 检查发现并修复文字编辑保护误入输出诊断，核心增加对应回归。根 api/check/build 通过，证据归 `clusteredChartsCheckpoint`。未跑全量或外部 Office；其他图表类型及完整 P10/P11/P12 继续实施。

P12 新增五种常用形状通过 10 项定向核心检查，包含新增两项。独立坐标覆盖轮廓、文字区域、命中、旋转、调节值、复制、精确历史及重开；未知公式、归一化参数、越界和零宽框有保护检查。新增 Chromium 流程通过默认插入和调节面板、逐字输入、字节历史、重开及 Canvas/PDF 像素，旧调节流程也已通过。安装包通过 3327 项断言与严格宿主编译，根 api/check/build 通过。证据归 `polygonPresetsCheckpoint`。未跑全量或外部 Office；自定义几何及 P10/P11/P12 其余范围继续实施。

P11 数值自动边界通过 22 项定向核心检查，包含新增两项。检查分别自动的起止边界、完整源极值、筛选后原始值聚合、空白/常量、原生标志和实际边界、刷新扩张、固定切换、重开、删除及精确历史。源类型、超限及原生边界不一致失败保留源和历史。传输检查通过 96 项断言；既有 Chromium 流程增加自动开关、预览/网格 13.5、原生缓存、目录和字节历史，单条通过。安装包通过 3327 项断言及严格宿主编译，根 api/check/build 通过。证据归 `pivotAutomaticNumericCheckpoint`。未跑全量或外部 Office，P10/P11/P12 仍为部分交付。

P11 多级日期分组通过 20 项定向核心检查，包含新增两项。覆盖两套日期系统、年/月及年/季度/月、跨年月份分隔、派生字段及原始记录、行列小计、标题冲突、刷新、层级缩减、删除、重开和精确历史。非法单位顺序、派生关系、轴深度及矩阵超限保持源与历史。传输检查通过 87 项断言；既有 Chromium 流程增加年/月多选、2024 小计 17.5、目录、保存及字节历史，单条通过。安装包通过 3327 项断言和严格宿主编译；根 api/check/build 通过。证据归 `pivotMultilevelCalendarCheckpoint`。未跑全量或外部 Office；其他透视及 P10/P11/P12 范围继续实施。

P11 单组件日期分组通过 18 项定向核心检查，包含新增两项。独立数值覆盖两套日期系统、跨年月、季度、366 日/闰日、原始日期求和、时间小数、原生日期与单位/自动边界、源变化/刷新、单位切换、小计、移除、删除、精确历史和重开空操作。历史日期边界、坏类型/越界、分组冲突及未知原生设置保持源和历史。传输检查通过 76 项断言；既有 Chromium 流程增加月分组预览/网格 16、年分组 17.5、目录、修改/移除和字节历史，单条通过。安装包通过 3327 项断言及严格宿主编译；根 api/check/build 通过。证据归 `pivotCalendarGroupingCheckpoint`。未跑全量或外部 Office；多级日期派生字段、其他透视及 P10/P11/P12 范围继续实施。

P11 固定数值分组通过 16 项定向核心检查，包含新增两项。检查原始缓存、分组字段兼作值字段的求和、交叉均值、整数/小数端点、空白与越界、原生分组及成员索引、分组后小计、刷新、移除后的区域清理、删除与精确混合历史；坏边界、混合源类型、自动/日期/重命名导入分组保持源与历史。传输检查通过 66 项断言；既有 Chromium 流程增加区间设置、预览/网格 17.5、原生目录、撤销重做和移除，单条通过。安装包通过 3327 项断言及严格宿主编译；根 api/check/build 通过。证据归 `pivotNumericGroupingCheckpoint`。未跑全量或外部 Office；日期分组、其他透视及 P10/P11/P12 范围继续实施。

P11 自动小计通过 14 项定向核心检查，包含新增两项。独立数值覆盖两层行列、多个值字段、源记录均值、行列小计交叉格与总计、格式化数字标题、原生深度/Values 索引、源变化/刷新、关闭后的区域清理、删除、精确混合历史和重开空操作。非法小计字段、展开后矩阵超限、上方/自定义导入小计保持源和历史。传输检查通过 54 项断言；既有 Chromium 流程增加小计设置、预览/网格 13.5、原生目录及字节历史，单条通过。安装包通过 3327 项断言和严格宿主编译；根 api/check/build 通过。证据归 `pivotSubtotalsCheckpoint`。未跑全量或外部 Office；分组、其他透视及 P10/P11/P12 范围继续实施。

提交前透视表定向检查通过：12 项核心检查、46 项传输断言及一条 Chromium 完整流程。新增报表筛选检查覆盖单选/多选、完整缓存、缺失成员选择、零匹配、原生分页范围、删除与精确历史；非法轴/空选择、扩张覆盖及跨越新旧结果区的链接原子拒绝。界面检查覆盖加载全部候选、选择 A、预览总计 12、原生设置及字节历史；既有列轴、刷新、PDF 和保存重开流程保留。根 api/check/build 通过。详细证据归 `pivotSubmissionCheckpoint`；未跑全量或外部 Office，P10/P11/P12 保持部分交付。

P11 普通列轴通过 10 项定向核心检查，包含新 3 项：类型化行列组合、均值的加权边际、多层列字段、Values 索引、空交叉格、原生首数据行/范围、刷新、行列字段变换、删除、精确历史与保存重开。稀疏源也须遵守完整输出矩阵的 32768 格上限；重复轴字段和未知 Values 位置原子拒绝。既有 Chromium 透视流程扩展到列字段、类型预览、网格与 PDF 交叉表头/总计、历史和删除，单条流程通过。传输检查通过 37 项断言；安装包通过 3327 项断言与严格宿主编译，根 api/check/build 与私有静态检查通过。证据归 `pivotColumnsCheckpoint`。未跑全量或外部 Office；报表筛选、小计、分组及 P10/P11/P12 其余范围继续实施。

P11 已有透视字段编辑与删除通过 7 项定向核心检查，包含新 3 项：字段/源与标题显式映射、聚合与值字段次序、Values 标题避让、扩大拒绝覆盖、缩小清理、原生身份、空操作、精确历史、独占资源删除、样式/便笺/链接清除、依赖公式、其他透视表与结构化表保留、未知关联与共享入口原子拒绝。既有 Chromium 创建/刷新流程扩展到字段加载、预览后应用、值字段移除、删除、字节历史、保存重开与后续输入，单条流程通过。传输检查通过 28 项断言；安装包通过 3327 项断言与严格宿主编译，根 api/check/build 和私有静态检查通过。证据归 `pivotFieldEditingCheckpoint`。未跑全量或外部 Office；列轴、报表筛选、小计、分组及其他 P10/P11/P12 范围继续实施。

P11 透视表的 Wasm/Worker、宿主和默认面板已接通。新增 Chromium 流程通过，覆盖只读多值预览、创建、原生缓存/记录/定义、依赖公式变化后的失效、显式刷新、完整字节历史、保存重开、后续原生输入及 PDF 文字；既有结构化表创建回归保留通过证据。4 项核心检查在目录可选字段序列化修复后通过，新增传输检查通过 21 项断言。安装包通过 3327 项断言和严格宿主编译，根 api/check/build 与私有静态检查通过。证据归 `pivotWebCheckpoint`。未跑全量或外部 Office；已有字段修改/删除、列轴、筛选/小计及 P10/P11/P12 其余范围继续实施。

P11 透视表核心有 13 项定向检查的通过证据，包含新建、类型缓存与索引记录、11 种聚合、多层行分组、当前公式、缓存失效、结果格保护、刷新扩张/缩小、精确混合历史、原生部件与保存重开。缓存身份、独立缓存、未知定义、源与输出冲突及资源预算失败保持候选；共用的表格创建、样式定义和便笺回归同时通过。根 api/check/build 与私有静态检查通过，证据归 `pivotCoreCheckpoint`。本轮只验证 MoonBit 核心，未跑浏览器、外部 Office 或全量；Wasm/Worker、宿主和默认面板及其他透视能力继续实施。

P10 标题/副标题及对应字符预设有 18 项定向核心检查的通过证据，覆盖四字体槽、字号/字间距、主题色、声明与实际段距、继承开关、原生样式身份、表格行内边界、相邻段落缓存失效、直接覆盖、源保留及精确历史。四条 Chromium 流程通过，包含默认重置面板、标题墨迹、相邻行间距、原生 XML、完整历史、保存重开、后续输入及 PDF 文字，并保留既有样式/字间距回归。根 api/check/build 与私有静态检查通过；没有新增公开接口，安装包沿前序结果的原范围复用。证据归 `titlePresetsCheckpoint`。未跑全量或外部 Office；完整强引用边框、其他预设及 P10/P11/P12 其余范围继续实施。

P10 字间距有 28 项定向核心检查的通过证据，覆盖继承、混合范围、后续输入、非法参数原子拒绝、样式、片段、HTML/Markdown、精确历史、双向与组合簇、负间距、光标、换行和分页缓存。三条 Chromium 流程通过，包含字间距控件、独立 Canvas 墨迹宽度、格式复制、样式编辑、后续输入、原生 XML、未改部件、保存重开及 PDF 文字，并保留两条内置样式回归。安装包通过 3327 项断言及严格宿主编译，根 api/check/build 和私有静态检查通过。证据归 `docxCharacterSpacingCheckpoint`。未跑全量或外部 Office；标题/副标题预设和 P10/P11/P12 其余范围继续实施。

P12 跨边翻转有 26 项定向核心检查的通过证据，覆盖四角/双轴、旋转/已有翻转、中心/比例叠加、拖回、同尺寸吸附、直线退化轴、表格原子保护、多选/整组/成员及仅方向变化的精确历史；既有组合/取消组合和方向写回回归同时通过。两条 Chromium 流程通过两种缩放下的真实指针、图片像素反转、固定锚点、拖回恢复、原生方向/尺寸、精确历史、保存重开和后续翻转编辑，保留比例/中心回归。安装包通过 3317 项断言及严格宿主编译；根 api/check/build 与私有静态检查通过。证据归 `crossResizeCheckpoint`，前序结果保留原范围。未跑全量或外部 Office；更广尺寸匹配、扩展辅助线及 P10/P11/P12 其余范围继续实施。

P12 中心缩放通过 15 项定向核心检查，覆盖四角、旋转/翻转、中心锚点、比例叠加、同尺寸容差换算、多选/整组/嵌套成员、越界拒绝和精确历史。两条 Chromium 流程通过两种缩放下的 Alt/Option 切换、最终释放、独立原生中心与尺寸、取消、精确历史、保存重开及原生输入，并保留同尺寸吸附回归。安装包通过 3317 项断言及严格宿主编译；根 api/check/build 和私有静态检查通过。证据归 `centerResizeCheckpoint`，前序结果保留原范围。未跑全量、外部 Office 或 Windows 专项；自动跨边翻转、更广尺寸匹配和 P10/P11/P12 其余范围继续实施。

P12 比例缩放通过 13 项定向核心检查，包含旋转/翻转、四角固定点、图片默认比例、同父多选、整组/嵌套成员、最小尺寸、候选取消及精确历史。两条 Chromium 流程有通过证据，检查两种缩放下的 Shift/Alt 切换、吸附优先级、最终释放修饰键、独立原生尺寸、图片指针、精确历史、保存重开及原生输入，并保留同尺寸吸附回归。安装包通过 3317 项断言及严格宿主编译；根 api/check/build 和最终私有静态检查通过。证据归 `aspectResizeCheckpoint`，前序结果保留原范围。未跑全量或外部 Office；中心缩放、自动跨边翻转、更广尺寸匹配和 P10/P11/P12 其余范围继续实施。

P12 同尺寸缩放有 18 项定向核心检查的通过证据，包含四角、翻转、对边固定、零位移轴、尺寸优先、整组、实际几何、源隔离和精确历史，并保留既有吸附回归。三条 Chromium 流程通过两种缩放下的真实指针、目标高亮像素、Alt、取消、原生 XML、键盘历史和重开输入。新安装包通过 3317 项断言及严格宿主编译；根 api/check/build 与私有静态检查通过。证据归 `sizeSnapCheckpoint`，前序结果保留原范围。未跑全量或外部 Office；比例锁定手势、更广尺寸匹配、扩展辅助线及 P10/P11/P12 其余范围继续实施。

P12 等间距吸附有 15 项定向核心检查的通过证据，覆盖居中/延续、双轴、稳定等距、同带邻居、多选/整组/组内成员、对象优先与网格回退、实际几何、候选源隔离、取消/提交及精确历史。三条 Chromium 流程有通过证据，检查两种缩放下的成对箭头像素、Alt、取消、原生 XML、未改部件、键盘历史及重开输入，并保留对象/辅助线回归。新公开几何通过 3304 项安装包断言和严格宿主编译，根 api/check/build 与私有静态检查通过。证据归 `spacingSnapCheckpoint`，前序结果保留原范围。未跑全量或外部 Office；缩放同尺寸提示、扩展辅助线及 P10/P11/P12 其余范围继续实施。

P11 相对日期筛选通过 19 项定向核心检查，覆盖 16 种期间、星期日起始、1900/1904、保存窗口、原生隐藏来源、当前公式、跨日重新应用、普通区域/原生表、结构及精确历史。四条 Chromium 流程有通过证据，检查宿主时钟经 Worker 传入、日期窗口 XML、原生输入、重新应用、重开及普通区域 PDF，并保留跨年筛选回归。新安装包通过 3293 项断言及严格宿主编译，根 api/check/build 和私有静态检查通过。证据归 `relativeFilterCheckpoint`；此前结果保留各自范围。未跑全量或外部 Office；高级/图标筛选及 P10/P11/P12 其余范围继续实施。

P11 跨年日期筛选有 11 项定向核心检查的通过证据，覆盖月份/季度边界、1900/1904、数值类型、当前公式、普通区域/原生表、手动隐藏、SUBTOTAL、重新应用、结构维护和精确历史。三条 Chromium 流程有通过证据，检查默认控件、跨年值、独立原生 XML、未改部件、原生输入、撤销重做、重开和普通区域 PDF，并保留日期组回归。新公开类型通过 3231 项安装包断言与严格宿主编译，根 api/check/build 及静态检查通过。证据归 `calendarFilterCheckpoint`；前序结果保留各自范围。未跑全量或外部 Office；P10/P11/P12 其余范围继续实施。

P12 动态对齐标记的 14 项定向核心检查有通过证据，覆盖角点/中心、多个同位移目标、零轴、Alt/明确数值定位、最小尺寸后的实际几何核对、预览源保持、取消/提交、精确历史及重开，并保留多选/旋转组、嵌套、网格、选择和连接线回归。三条 Chromium 流程有通过证据，检查实际标记像素、Alt 中途隐藏/恢复、取消和提交清理、角点缩放、纯辅助线不重复标记，并保留网格显示、PNG 隔离、原生 XML、精确历史和输入。新公开几何通过 3201 项安装包断言及严格宿主编译，根 api/check/build 和私有静态检查通过。前序辅助线拖动、PDF、尺寸等证据保留原范围。当前证据归 snapLinesCheckpoint，前序归 gridDisplayCheckpoint、snappingCheckpoint、objectSnapCheckpoint、guideSnapCheckpoint、guideDragCheckpoint 与 guidesCheckpoint。未跑全量或外部 Office；扩展辅助线及 P10/P11/P12 其余范围继续实施。

P11 工作表与工作簿结构保护通过 19 项定向核心检查，覆盖保护启用/解除、密码、无密码和旧式摘要、结构拒绝与内容编辑、单元格保护格式、精确历史、重开及失败保持。节点内文字、注释和处理指令的保留回归通过。最新两条 Chromium 流程检查默认保护控件、结构禁用及恢复、独立 SHA-512 与原生 XML、原生输入、精确历史、保存重开和 PDF；前序格式刷与验证列表流程沿原定向证据复用。新安装包通过 3149 项断言和严格公开宿主编译，根 api/check/build 与静态检查通过。当前证据归 `workbookProtectionCheckpoint`，前序证据保留于 `worksheetProtectionCheckpoint`、`protectionFormatCheckpoint` 和 `unlockedInputCheckpoint`。未跑全量或外部 Office；细分授权、窗口/修订保护及其他密码算法继续实施，P11 保持 planned。

P10 正文 HTML/Markdown 导出及结构列表通过 6 项定向核心检查，覆盖正文资源、原生嵌套、非 1 起点、续号/重启、软换行缩进、空项、跨表格计数、特殊标签、RTL 和失败保持；既有编号规则回归同时通过。两条 Chromium 流程有通过证据，检查默认菜单/回调/下载、独立 HTML 渲染、图片字节/裁剪像素、列表层级和实际值、标记颜色/像素、正文格式隔离及 RTL 方向，保留原生文件和失败后的编辑。根 api/check/build 和私有静态检查通过；公开接口未变，复用此前 3125 项安装包断言及严格宿主编译。证据归 `markupListsCheckpoint`，先前交换输出归 `markupOutputCheckpoint`。未跑全量或外部 Office；复杂列表仍需读取器支持内嵌 HTML/CSS，页边区域/审阅/字段和 HTML/Markdown 导入继续实施，P10/P11/P12 保持 planned。

P10 正文富文本片段通过 17 项定向核心检查，覆盖部分字符、跨段落、列表、链接、完整书签、行内图片、目标格式保持、精确历史，以及无效源、缺字体、旧 revision 和预算失败；既有单元格片段回归同时通过。新 Chromium 流程检查默认跨文档源格式粘贴、Ctrl/Cmd+V/X、独立 ZIP/XML 与图片字节、继续输入格式、精确混合历史、重开及独立 PDF 文字和像素，原有单元格图片流程也通过。新安装包通过 3125 项断言、严格宿主编译和打包；根 api/check/build 通过，详细证据归 `bodyFragmentCheckpoint`。未跑全量或外部 Office；HTML/Markdown、跨表结构及部分书签转移仍未完成，P10/P11/P12 保持 planned。

P11 链接填充通过 11 项定向核心检查，覆盖四向完整范围复制、目标裁剪、部分源/尾块、原目标和提示保持、关系复用、精确历史、重开导航与输入、缩减保留及不安全/重叠/未知/预算失败，并回归普通规则、缩减及链接剪贴板。六条 Chromium 流程有通过证据：扩展默认四向流程检查独立 ZIP/XML、外链地址、条件色、验证、精确历史、重开内部跳转及 PDF；既有填充柄流程检查取消、未知链接失败和恢复、Ctrl、缩减及冻结/RTL。未知链接元数据和未知工作表扩展均阻止完整 PDF。根 api/check/build 及私有静态检查通过，详细证据归 `fillLinksCheckpoint`。公开 API 未变，未重跑安装包、全量或外部 Office；部分源链接与不足尾块按完整范围规则跳过，完整 P10/P11/P12 继续实施。

P11 填充规则通过 17 项定向核心检查，覆盖四向规则扩展、原公式锚点、共享数据条统计、验证尾块、相同值的规则转移、精确历史、重开、向内清除保持规则及非法元数据/验证/预算失败，并回归序列、规则剪贴板和规则移位。六条 Chromium 流程通过默认四向按钮、原生草稿、独立 ZIP/XML、实际条件色、重开验证及 PDF；既有填充柄的自动、Ctrl、缩减、冻结/RTL、取消和恢复同时通过。根 api/check/build、私有静态检查、源码行数、登记、受影响链接和两仓库差异检查通过，详细证据归 `fillRulesCheckpoint`。公开 API 未变，未重跑安装包、全量或外部 Office；相交链接等资源仍保护，完整 P10/P11/P12 继续实施。

P12 基础艺术字通过 12 项定向核心检查，覆盖五种纯色预设、实际字体自动尺寸、原生全选输入、精确混合历史、复制重开、输出及非法参数/字体/预算保护，并回归文字框、尺寸、格式和普通对象。不换行文字改为按实际框宽对齐，另检查居中、右对齐、RTL 及换行缓存隔离。一条 Chromium 流程通过默认插入、原生替换、独立 ZIP/XML、三步精确历史、重开输入、PNG 彩色文字及独立 PDF 文字/像素检查。最终安装包通过 3117 项断言和严格宿主编译，根 api/check/build 及私有静态检查通过；详细证据归 `wordArtCheckpoint`。未跑全量或外部 Office；描边、渐变、阴影和变形艺术字继续实施，完整 P10/P11/P12 仍未完成。

P12 保存墨迹通过 10 项定向核心检查，覆盖跨页原生折线、圆点、命中、复制缩放、描边重开、整次精确历史和未知路径/候选/输出保护，并回归临时画笔、放映、复制及组合。两条 Chromium 流程检查默认保存入口、实际指针输入、独立 ZIP/XML、源和选择保持、精确撤销重做、重开编辑及 Canvas/PNG 和独立 PDF 像素；原有临时笔迹隔离流程通过。新安装包通过 3100 项断言和严格宿主编译，根 api/check/build 通过；详细证据归 `inkSaveCheckpoint`。未跑全量或外部 Office；当前保存开放采样折线，曲线、平滑及压感墨迹继续实施，完整 P10/P11/P12 仍未完成。

XLSX DEVSQ 通过 14 项定向核心检查，覆盖参数类型、稀疏引用、大偏移数值、名称/共享/跨表重算、结构操作、精确历史、重开、显式 TSV 公式转换及未知函数和预算失败保护；共用累计的方差、标准差和 SUBTOTAL 回归同时通过。一条 Chromium 流程检查导入陈旧缓存、原生公式输入、独立 ZIP/XML、完整历史恢复、未知函数草稿保留、重开与完整 PDF。根 api/check/build、私有静态检查、源码行数、登记、受影响链接及两仓库差异检查通过，细节归 `deviationSquaresCheckpoint`。本次未重跑安装包、全量或外部 Office；未知函数和动态引用仍使导入工作簿只读，完整 P10/P11/P12 继续实施。

DOCX 修订正文显示与定位通过 19 项定向核心检查，覆盖下划线/删除线、同布局文字、跨页、裁剪单元格、空修订、组合字符边界、原编辑选区/源/历史保持，以及旧布局、活动候选和不完整段落保护；既有修订、批注覆盖层、书签和组合输入回归同时通过。Chromium 新定位流程检查三页正文/单元格/属性修订跳转、实际高亮像素、可访问页面文字、待处理修订 PDF、源和 PDF 精确保持、旧目录拒绝、定位失败后的原生输入与未知字段源保留；两条原有修订流程也通过。安装包通过 3096 项断言与严格宿主编译，根 api/check/build 通过，细节归 `revisionNavigationCheckpoint`。未跑全量或外部 Office；导出页面保留待处理修订标记，记录新修改、结构修订和更广显示模式继续实施。

DOCX 字符/段落属性修订通过 15 项定向核心检查，包含文字修订、批注、书签和组合输入回归。新用例检查接受当前属性、拒绝恢复旧属性、空旧属性恢复继承、正文/单元格、局部命名空间及中文字体、段落标记格式保持、文字与属性混合批次、精确历史、重开输入，以及未知/重复/嵌套/结构属性的原子保护。两条 Chromium 流程通过作者/类型组合筛选、四种属性处理结果、独立 ZIP/XML、段落标记保持、同布局颜色、精确历史、重开输入与 PDF；原有文字修订流程同时通过。安装包通过 3086 项断言与严格宿主编译，根 api/check/build 通过，细节归 `revisionPropertiesCheckpoint`。未跑全量或外部 Office；记录新修改、结构修订及正文标记/定位继续实施，完整 P10/P11/P12 仍未完成。

DOCX 导入文字修订通过 13 项定向核心检查，覆盖原生插入/删除、混合样式与命名空间、整批原子校验、字段/嵌套/图片保护、文档保护、精确历史和后续输入，并回归批注、书签和组合输入。Chromium 修订流程检查作者筛选、四种接受/拒绝结果、独立 ZIP/XML、旧目录拒绝、精确历史、重开输入及 PDF；既有批注流程也通过。安装包通过 3084 项断言与严格宿主编译，根 api/check/build 通过。修订作者控件标签及按钮禁用条件已修正；浏览器样例使用宿主已有字体组合。边界归[文字修订审阅](formats.md#docx-修订审阅)，私有证据归 `docxRevisionsCheckpoint`。未跑全量或外部 Office；记录新修改、属性/结构修订及正文标记/定位仍未实现，完整 P10/P11/P12 继续实施。

P12 媒体播放属性通过 16 项定向核心检查，覆盖循环/音量/静音原生读写、独立来源、动画列表保持、对象及页面复制、删除回收、精确混合历史、重开、非法值/目标与未知属性保护，并检查未知媒体不阻止无关普通对象复制和删除。三条 Chromium 流程检查默认属性控件、独立 ZIP/XML、复制后分别修改、历史与重开、实际 PCM WAV 至少两次循环回卷、音量/静音属性及停止释放；既有媒体动画、视频、笔迹、故障和输出隔离回归同时通过。安装包通过 3068 项断言及严格宿主编译，根 api/check/build 和私有静态检查通过，细节归 `mediaPlaybackCheckpoint`。未跑全量或外部 Office，未验收实际扬声器音量；更广媒体计时及完整 P10/P11/P12 继续实施。

P12 原生媒体动画通过 17 项定向核心检查，覆盖点击/同时/之后命令、延迟与暂停、手动完成组、一次执行、重播身份与旧反馈、布局跨时点、页复制目标、精确历史、重开、无效目标/参数、未知起点保护及超限对象隔离；原有媒体、动画、放映、链接和自动换页回归同时通过。两条 Chromium 流程检查默认动画面板、独立 ZIP 源、精确历史、实际视频帧、点击不换页及保存重开后的延迟自动播放，同时复查既有媒体播放与释放。安装包通过 3058 项断言与严格宿主编译，根 api/check/build 和私有静态检查通过，细节归 `mediaCuesCheckpoint`。未跑全量或外部 Office；循环、音量/静音及更广媒体计时继续实施，P10/P11/P12 仍未全部完成。

P12 手动放映媒体通过 13 项定向核心检查，覆盖点击/暂停/停止、独立复制实例、动画透明层中的图片命令绑定、画笔帧保留、过期反馈、换页/重启、播放器预算及源/历史隔离；媒体输入、既有放映、画笔和链接回归同时通过。三条 Chromium 流程检查实际视频帧与复制封面分离、暂停/全局恢复、停止、播放拒绝后重试、视频上层笔迹、结束反馈、损坏媒体与健康音频并存、过期事件、原包/PDF 字节保持及换页/换文件/dispose 释放。安装包通过 3043 项断言和严格宿主编译，根 api/check/build 通过，细节归私有 `showMediaCheckpoint`。未跑全量或外部 Office；自动播放、循环、更多编码及完整 P10/P11/P12 继续实施。

P12 内嵌音视频通过 15 项定向核心检查，覆盖双关系、封面及原字节、对象/页面复制、变换和删除、精确混合历史、重开，以及容器、图片、几何、输出、单资源/累计媒体预算和外链保护；原有图片编辑和页面操作回归同时通过。一条 Chromium 默认流程检查 PCM WAV 和 VP8 WebM 的实际解码、封面像素、独立 ZIP/XML/资源字节、两步精确历史、解码失败后的刷新恢复、重开复制和 PDF 封面像素。安装包通过 3004 项断言和严格宿主编译，根 api/check/build 通过，细节归私有 `mediaInputCheckpoint`。未跑全量或外部 Office；媒体播放、其他编码及完整 P10/P11/P12 继续实施。

P12 放映临时画笔通过 11 项定向核心检查，覆盖页内坐标、圆端点/圆连接路径和单点、按页恢复、草稿取消、清空、源/选择/历史和静态输出隔离，以及失效帧、非法笔、点批次、单笔预算和时钟倒退；既有放映、链接、自动换页和切换回归同时通过。两条 Chromium 流程通过淡入期间指针绘制、原生颜色键盘、缩放、跨页恢复、清空、Escape 取消、释放、原包/PDF 字节保持及既有放映/原生输入流程。最终安装包通过 2972 项断言和严格宿主编译，根 api/check/build 通过，细节归私有 `showInkCheckpoint`。未跑全量或外部 Office；持久墨迹、媒体和完整 P10/P11/P12 继续实施。

P10 图片单元格的显式剪切、范围删除和输入通过 15 项定向核心检查，覆盖完整格清空、首格文字/Enter/组合候选、取消、精确历史、重开、复制/删除锁及后续格失败和输出失败的原子性。图片段落、普通格输入及剪贴板回归同时通过。扩展既有 Chromium 流程，检查剪贴板写入延迟和失败恢复、默认剪切、原生 Delete、两步精确历史，以及原有跨文档资源、重开输入和 Canvas/PDF。最终安装包通过 2946 项断言、严格宿主编译及打包，根 api/check/build 通过，细节归私有 `pictureCellsCheckpoint`。未跑全量或外部 Office；浮动图片、表格结构操作和完整 P10/P11/P12 继续实施。

P10 单元格图片片段通过 14 项定向核心检查，覆盖资源共享、独立绘图身份、元数据、文字顺序、裁剪、混合历史、重开及锁定/外链/预算保护，并回归既有链接、书签、列表及图片插入。Chromium 默认跨文档复制 PNG/JPEG、解码拒绝后恢复、独立 XML/压缩字节、精确历史、重开原生输入及 Canvas/PDF 像素检查通过。根 api/check/build 通过，细节归私有 `tableRichImagesCheckpoint`。本次未重跑安装包、全量或外部 Office；此前图示安装包结果保留原范围，完整 P10/P11/P12 继续实施。

P12 流程、层级和循环图示通过 11 项定向核心检查，覆盖三种模板的几何和原生引用、复制、旋转、取消组合、精确历史、重开输入及文字/字体/身份/预算失败。普通对象、连接线和组合回归同时通过。Chromium 默认三模板插入、独立 XML、三步精确历史、重开列表进入文字、原生输入及 PDF 文字/连接线像素检查通过。最终安装包通过 2928 项断言和严格宿主编译，根 api/check/build 与私有静态检查通过，细节归私有 `diagramCheckpoint`。未跑全量或外部 Office；原生 SmartArt 及完整 P10/P11/P12 继续实施。

P11 相对及混合名称剪切移动通过 5 项定向核心检查，覆盖保存坐标变换、重叠/跨表移动、移动中的调用格、作用域与嵌套定义、精确历史、重开输入及不透明/无表名源和预算失败保护。Chromium 默认与原生剪切、默认粘贴流程通过，独立 XML 检查名称、缓存及未改部件，并检查两步精确历史、重开后的原生输入与 PDF。根 api/check/build 和私有静态检查通过，细节归私有 `relativeNameMoveCheckpoint`。公开合同未变，未重跑安装包、全量或外部 Office；完整 P10/P11/P12 继续实施。

P12 同父容器闭合连接图形通过 11 项定向核心检查，覆盖组合、非等比缩放候选、成员旋转、端点修改、嵌套、复制引用重映射、取消/再次组合、精确历史和保护失败。补充组内端点取消及吸附无操作后，新增两项再次通过。Chromium 默认控件流程通过组合、缩放、成员旋转、复制、取消/再次组合、组内连接线入口、六步精确历史、重开输入、独立原生引用及 PDF 文字/像素检查。根 api/check/build 与私有静态检查通过，细节归私有 `connectorGroupCheckpoint`。公开合同未变，本次未重跑安装包；前次 2910 项断言保留原构建范围。未跑全量或外部 Office，跨父容器及折线/曲线继续保护，完整阶段保持未完成。

P12 连接线画布端点拖动通过 8 项定向核心检查，覆盖上层目标/原生点顺序、吸附与断开、另一端保持、候选取消/原位无操作、精确历史、重开及失效输入/锁定/预算保护。补充越过另一端和零长度退化检查后，新增两项再次通过。Chromium 真实鼠标流程检查 50%/100% 缩放的固定屏幕吸附距离、Escape、拖出断开、独立 XML、三步精确历史、Canvas 线条及重开后的普通目标拖动联动。最终安装包通过 2910 项断言及新候选类型/容差参数的严格宿主编译，根 api/check/build 及私有静态检查通过。细节归私有 `connectorPointerCheckpoint`。未跑全量、额外 PDF 或外部 Office；前次 PDF 保留原范围，完整阶段继续实施。

P12 原生直线连接线通过 13 项定向核心检查，覆盖端点、目标变换候选与取消、精确历史、重开和母版/版式源事务。新增两项在补充缺失几何和受保护目标检查后再跑，结果归私有 `connectorCheckpoint`。Chromium 默认创建、连接/断开、目标移动、独立 XML、四步精确历史、重开和 Canvas/PDF 线条检查通过。最终安装包通过 2910 项断言及严格宿主编译，根 api/check/build 和私有静态检查通过。该次未跑全量或外部 Office；组内连接的后续结果见上文，完整阶段保持未完成。

P10 列表复制已解除标记下划线混合继承保护。三项定向核心检查通过：新增用例在目标默认下划线开启时保留源混合状态，核对共享计数、起始覆盖只应用一次、原生输入、精确历史、重开及改级别；原资源正反用例同时通过。既有 Chromium 复制流程在最终构建通过，保留独立编号 XML、链接/书签、历史和 PDF 检查；其输入为统一继承，混合状态由核心用例证明。根 api/check/build 通过，细节归私有 `tableRichListInheritanceCheckpoint`。未跑全量、安装包或外部 Office，前次检查保留原范围，完整阶段继续实施。

P10 表格富文本列表通过 17 项定向核心检查；补齐主题字体/颜色、输出失败及显式级别属性处理后，新增两项再次通过。覆盖多级编号、重启、项目符号、独立身份、已有定义保留、链接与首个编号部件共存、精确历史、重开输入和改级别。未知或失去资源的片段及预算失败保留包和状态。既有 Chromium 链接/书签流程扩展后通过真实默认复制粘贴、独立原生定义与引用、历史、重开及 PDF 标记。根 api/check/build 通过，细节归私有 `tableRichNumberingCheckpoint`。公开合同未变，安装包沿前次 2876 项断言的原构建范围；未跑全量或外部 Office，完整阶段继续实施。

P11 普通单元格的单下划线、删除线和上下标通过 21 项定向核心检查，覆盖样式读写、共同度量、格式刷、跨工作簿复制、清除、条件/表格样式及精确历史。补齐差异格式查询后，最终代码的对应核心用例再次通过。Chromium 默认面板流程通过独立 XML、装饰绘制、原生输入、四步精确历史、重开和 PDF。最终安装包通过 2876 项断言及严格宿主编译，根 api/check/build 和私有静态检查通过。细节归私有 `cellDecorationsCheckpoint`；双线/会计下划线和未知源继续保护。未跑全量及外部 Office，完整阶段继续实施。

P11 富文本单下划线、删除线和上下标通过 12 项定向核心检查、1 项共同装饰检查及现有 XLSX Chromium 流程。既有 PDF 表单流程检查共同文字块改动后的外观、保存和重开。页眉页脚沿实际坐标保留缩放和边距断言；未知装饰继续诊断并保护输出。根 api/check/build 通过，证据归私有 `richDecorationsCheckpoint`。未跑全量或外部 Office，完整阶段继续实施。

P11 普通富文本字体色筛选与排序新增两项核心通过。第一轮颜色检查共十七项通过；加入共同文字段排版后，二十二项既有排序、筛选、自动尺寸和公式视图回归通过，新增两项在补齐重开字体上下文及空段测量检查后再次通过。覆盖任一段匹配、共享源的逐格条件色继承、RGB/索引/主题/自动色、普通区域及原生表、行列排序、隐藏来源、SUBTOTAL、基本文字段测量及空文字大字号、精确历史与重开输入。未知源和输出失败保持包、选择及历史。Chromium 默认筛选/排序流程通过可见行、Canvas 蓝绿文字、相邻格原生输入、独立原生源、四步精确历史、重开及 PDF。根 api/check/build、私有静态检查通过；Web/Worker 合同未变，安装包沿既有证据的原构建范围。详细证据归私有 `richColorsCheckpoint`。未跑全量或外部 Office，复杂富文本、图标及其余完整阶段继续实施。

P10 表格富文本书签新增两项核心通过；前次定向运行的十四项富文本片段、链接和书签回归通过。检查链接内、跨格、跨段落和空段落点锚点、独立身份、同名目标保留、源快照、内部跳转、输入维护范围、两步精确历史及重开改名。遗漏端点/中间格、非法名称、重复或断裂配对、扩展属性、未知目标、目录/标记上限、目标书签和输出失败保持状态。既有 Chromium 链接复制流程扩展后通过，独立 XML 检查书签配对及新 ID，默认链接跳转进入刚粘贴的书签，并保留精确历史、重开输入及 PDF。根 api/check/build、私有静态检查通过；公开合同未变，沿用既有安装包证据的原构建范围。详细证据归私有 `tableRichBookmarksCheckpoint`。未跑全量或外部 Office，复杂范围和其他资源转移、完整 P10/P11/P12 继续实施。

P10 表格富文本链接新增两项核心，连同富文本片段及链接编辑回归共十一项通过；补充 4096 条上限的原子拒绝检查后，新增两项再次通过。检查跨文档目标快照、混合格式和元数据、多关系批量分配与复用、已有关系冲突、目标覆盖、内部书签、空操作、精确历史及重开；不安全目标、源身份、未知属性、缺少目标书签、异常结构和输出失败保持状态。新增 Chromium 默认复制/粘贴流程通过自定义剪贴板、独立原生链接/关系、未改部件、原生输入、两步精确历史、保存重开及 PDF，未触发外部请求。当前构建及私有静态检查通过，根 api/check 复用同一产品代码的提交检查；公开合同未变，安装包沿前批证据的原构建范围。详细证据归私有 `tableRichLinksCheckpoint`。未跑全量或外部 Office，书签身份及其他资源转移、完整 P10/P11/P12 继续实施。

P12 表格占位符的版式切换/重置新增两项核心通过；前次定向运行的十一项占位图片、表格填入、表格变换及版式回归保持适用。检查 `tbl/obj` 跨母版匹配、不等宽列比例、窄列换行增高、行最小高度、格与身份源、文字选择、移动后重置、三步精确历史及重开输入。目标冲突、锁定、异常几何、过窄列、缺少字体/探针、目标母版不支持的下划线及输出失败保留包、查询和身份分配。既有 Chromium 表格填入流程扩展到默认版式控件、列网格/关系/格源检查、行增高、重置与空操作、精确历史、重开输入和 PDF，并在最终保护补齐后通过。根 api/check/build 与私有静态检查通过。公开合同未变，复用前批 2871 项安装包断言及严格宿主编译，其引擎构建早于本轮内部版式修改。详细证据归私有 `placeholderTableLayoutCheckpoint`。未跑全量或外部 Office，完整 P10/P11/P12 继续实施。

P12 空表格/内容槽填表新增两项核心，连同占位图片、新建表格、表格及版式回归共十三项通过；末次调整源扩展遍历后只复跑新增两项并通过。检查双类型原生表格、身份和非可视源、版式提示、位置/宽度、行高、精确混合历史、格输入及重开；非空文字、旋转、其他槽位、源视图、非法行列、旧修订、扩展内容和输出失败保持状态。新增 Chromium 流程通过默认按钮、独立 XML、非目标部件、两步精确历史、重开输入及 PDF。根 api/check/build、私有静态检查、2871 项新安装包断言和严格宿主编译通过。既有表格创建用例的边框预期在提交基线同样失败；按独立 2×3 网格的 8 条纵边与 9 条横边修正为 17 段，公共边只绘制一次。详细证据归私有 `placeholderTableCheckpoint`。未跑全量或外部 Office；后续表格版式结果归私有 `placeholderTableLayoutCheckpoint`；完整 P10/P11/P12 继续实施。

P11 跨日期系统复制新增两项核心，连同单元格/规则复制、日期及验证编辑共十二项通过。覆盖双向换算、日内小数、纯时间与普通数字、公式重算和值粘贴、日期验证边界、格式/公式模式、转置、空操作、精确历史与重开；不可表示日期及输出超限保留状态。详细证据归私有 `copyCalendarCheckpoint`。新增 Chromium 流程通过默认系统剪贴板的双向换算、值粘贴、独立原生值/公式/日期标志、精确历史、重开原生输入及 PDF；复制时核对片段日期标志，防止反向步骤读到旧片段。此前链接、便笺及占位图片的浏览器结果沿各自记录。未跑全量或外部 Office，完整 P10/P11/P12 继续实施。

P11 便笺复制新增两项核心，连同便笺、剪切、单元格及链接复制共十一项通过。覆盖所选作者/富文本/VML、独立身份、源快照、目标覆盖、转置、选择性模式、空目标建资源、仅文字源补框、精确混合历史及重开；异常 XML、地址/身份、框不匹配及输出失败保留状态。补上命名空间展开的逐条预算检查后，仅复跑新增两项并通过。最终 Chromium 流程检查默认系统剪贴板跨工作簿、便笺面板、可访问描述、原生格输入、独立 XML/框、精确历史及重开编辑，PDF 排除便笺。根 api/check/build 与私有静态检查通过。安装包 2860 项断言和严格宿主编译来自内部预算补强前的构建；公开合同保持，最终核心和浏览器验证补强后的引擎。详细结果归私有 `copyNotesCheckpoint`。未跑全量或外部 Office，完整 P10/P11/P12 继续实施。

P11 链接复制新增两项核心，连同结构化剪贴板、规则、链接编辑和剪切回归共十二项通过。覆盖源交集、元数据、目标裁剪、选择性模式、转置、关系复用、同值、单独清除链接及精确跨表/工作簿历史和重开；非法目标、重叠、范围/元数据、未知源及输出失败保留状态。补强同格式输出失败用例后仅复跑新增两项，验证候选关系不污染会话。新增 Chromium 流程通过默认系统剪贴板跨工作簿转移、原生输入、独立 XML、三步精确历史、重开导航和 PDF；复制/粘贴不请求外链。新安装包通过 2850 项断言和严格宿主编译，根 api/check/build 与私有静态检查通过。详细结果归私有 `copyHyperlinksCheckpoint`。未跑全量或外部 Office；便笺等其他复制资源及完整 P10/P11/P12 继续实施。

P12 空图片/内容占位框填图新增两项核心，连同图片、占位符定义及版式回归共十一项通过。检查原生图片、槽位身份、源提示保留、小图片尺寸、后续裁剪/替换、精确混合历史与重开；文字、锁定、扩展属性、目标变化、坏图片及输出预算失败保持原子性。新增一条 Chromium 流程通过默认面板填入大图，检查等比居中、独立 XML/资源、非目标部件、精确撤销重做、重开图片像素和 PDF。根 api/check/build 与私有静态检查通过。公开入口及类型未变，复用前批安装包检查结果，构建范围保持前批。详细结果归私有 `placeholderImageCheckpoint`。未跑全量或外部 Office；图表、媒体等槽位填入及完整 P10/P11/P12 继续实施。

P12 母版修改现按母版、所属版式、实际页面顺序重排。新增两项核心，连同默认字符/段落、源视图/背景和母版重绑定共十二项通过。覆盖未使用版式的提示文字、自增高/缩小框、缩放组、直接覆盖、非目标源、精确历史及重开输入；缺字体、尺寸锁、扩展适配、继承几何丢失和输出预算失败保留状态。当前构建复跑既有 Chromium 母版流程通过，保持 20 秒与零重试；未使用版式新增行为由核心检查覆盖。根 api/check/build 与私有静态检查通过。公开合同未变，复用前批安装包 2836 项断言及严格宿主编译结果，其构建范围保持前批。详情归私有 `layoutReflowCheckpoint`。未跑全量或外部 Office；资源槽位填入及完整 P10/P11/P12 继续实施。

P12 母版默认段落/列表新增两项核心，连同默认字符、普通段落、列表、标记样式和制表位共十四项定向检查通过。覆盖三类九级继承、对齐/方向、行段距、缩进、编号、标记样式、制表位、本地覆盖、自动框、保留字符定义、精确历史和重开；扩展源、缺标记字体及输出预算失败保留状态。按 ONLYOFFICE 修正编号继承粗斜体和普通项目符号使用常规字形的共享解析。扩展既有 Chromium 流程通过，耗时 11.699 秒，保持 20 秒与零重试；默认控件检查对齐、间距、项目符号、缩进、恢复段落继承、精确撤销、字符保留、页面像素、独立 XML、重开输入及三页 PDF。最终安装包通过 2836 项断言及严格宿主编译，根 api/check/build 与私有静态检查通过。详情归私有 `masterParagraphStyleCheckpoint`。未跑全量或外部 Office；未使用版式独占自动框重排、资源槽位填入及完整 P10/P11/P12 继续实施。

P12 母版默认字符样式新增两项核心，连同源视图、主题字体和母版重绑定共九项定向检查通过。覆盖三类九级继承、直接覆盖、已有定义连续修改、原生容器创建/顺序、当前母版及实际页自动框、精确混合历史和重开；非法输入、扩展标记、缺字体及输出预算失败保留原状态。默认面板 Chromium 流程通过，耗时 9.421 秒，保持 20 秒与零重试；检查字号/颜色/粗体、切换级别、恢复继承、精确撤销重做、页面实际颜色像素、独立 XML、非目标部件、重开原生输入及三页 PDF。安装包 API 与严格宿主编译通过 2816 项断言；该结果属于内部适配补齐前的构建，公开合同随后保持，最终核心及浏览器验证最终行为。根 api/check/build 与私有静态检查通过。详情归私有 `masterTextStyleCheckpoint`；未跑全量或外部 Office。该批尚未实现默认段落/列表编辑，后续结果归下述母版段落记录；未使用版式独占自动框的重排继续实施，完整 P10/P11/P12 继续实施。

P12 占位符插入和定义编辑通过十一项定向核心检查，包含两项新用例及版式应用、源视图和母版重绑定回归。覆盖 16 种类型、uint32 索引、类型/索引冲突、移除定义时保留内容和继承几何、精确历史、应用空框、重开，以及锁定/未知元数据/引用几何/输出预算失败的原子保护。新安装包通过 2782 项断言和严格宿主编译；根 api/check/build 与私有静态检查通过。此前现有母版创建 Chromium 流程通过，耗时 8.389 秒。新增占位符默认控件流程也已通过，耗时 7.237 秒，保持 20 秒与零重试。检查插入、类型/索引修改、移除定义后保留文字、精确撤销重做、应用空框、独立 XML、源提示隔离、非目标部件、重开原生输入及三页 PDF；修正类型下拉框的可访问名称。UI 重建、根与私有静态检查通过；安装包结果保留此前构建范围，本轮不重复。详情归私有 `placeholderCheckpoint`。未跑全量或外部 Office；资源槽位填入和默认文字样式仍待实现。

P12 母版新增/复制新增两项核心，连同母版删除、版式管理和应用共十一项定向检查通过。覆盖全部所属版式、独立主题、共享图片/链接、身份分配、七步混合历史、重开、零版式源，以及目录/对象/资源归属/身份/输出预算的原子保护。新增 Chromium 默认按钮流程检查创建、复制像素、原生文字、独立关系与主题字节、复制撤销/重做、应用副本版式、删除原源、未改部件、重开输入和三页 PDF；最终构建 7.633 秒，保持 20 秒与零重试。新安装包通过 2672 项断言和严格宿主编译，根 api/check/build 与私有静态检查通过。详情归私有 `masterCreationCheckpoint`；未跑全量、外部 Office 或无关格式运行，完整 P10/P11/P12 继续实施。

P12 使用中母版删除通过十一项定向核心检查与一条新增 Chromium 流程。两项新核心覆盖类型/名称/顺序匹配、隐藏页、本地覆盖、孤立占位符、自动适配、仅关系变更的继承刷新、精确历史、重开和失败原子性。默认按钮流程检查两页重绑定、母版颜色像素、本地尺寸、独立原生关系/几何、完整包历史、重开原生输入及两页 PDF；当前构建 4.621 秒，保持 20 秒与零重试。根 api/check/build 与私有静态检查通过。本轮复用现有命令及查询，未新增公开类型或包入口；此前 2666 项安装包断言保留原构建范围。详情归私有 `masterRebindCheckpoint`；未跑全量、外部 Office 或无关格式运行，完整 P10/P11/P12 继续实施。

P12 未使用母版删除新增两项核心，连同版式管理、目录/应用及页结构共十五项通过。检查所属原始/新建版式回收、空版式目录、共享主题/图片保留、选择、精确历史、重开及引用/保护/历史预算失败。新增一条 Chromium 流程同时覆盖版式新增/复制/删除/改名/应用和母版删除，检查复制后相同像素、九步完整保存历史、独立 XML、非目标部件、重开原生输入和两页 PDF；当前构建 18.509 秒，保持 20 秒与零重试。新安装包通过 2666 项断言和严格宿主编译，根 api/check/build 与私有静态检查通过。该批覆盖未使用母版删除，使用中重绑定归后续记录。详情归私有 `masterDeletionCheckpoint`；未跑全量、外部 Office 或无关格式运行。

P12 版式新增/复制/删除和源改名的两项核心，连同目录/应用、源视图、页结构和复制回归共十七项通过。覆盖共享图片/链接、对象身份、引用保护、九步精确历史、删除原始/新建部件、重开及失败原子性。当前构建复跑既有 Chromium 源视图/背景流程通过，保持 20 秒和零重试；新增版式管理控件尚未单独跑浏览器流程。重新安装的公开包通过 2662 项断言和严格宿主编译；根 api/check/build 与私有静态检查通过。记录归私有 `layoutManagementCheckpoint`。未跑全量或外部 Office，完整 P10/P11/P12 仍在实施。

P12 母版/版式背景新增两项核心，连同源视图、普通背景/图片背景、内缩和图片插入共十五项定向检查通过。覆盖源继承、页面局部覆盖、未使用版式、图片归属、裁剪/不透明度/平铺/内缩、精确历史及重开；非法输入、未知背景、文稿保护和输出预算失败保留状态。扩展既有 Chromium 源视图流程，检查背景控件、继承色值、原始图片和关系、独立 XML、六步精确混合历史、重开输入及两页 PDF，保持 20 秒和零重试。公开 API/构建、根及私有静态检查通过。本批未新增公开类型或包入口，安装包结果保留前批构建范围；未重跑安装包、全量或外部 Office。详情归私有 `sourceBackgroundCheckpoint`。

P12 母版/版式源视图新增两项核心，与版式、主题字体和组边界共十二项定向检查通过。覆盖源身份、未使用版式、对象文字/填充/图片关系、页面覆盖保留、依赖占位符适配、组边界、精确历史及重开；缺字体、无效源目录和删除继承几何的失败保持原子性。一条 Chromium 流程检查默认选择器、原生输入、版式填充、独立 XML、继承色值、精确撤销重做、重开输入及两页 PDF。当前安装包 2643 项断言和严格宿主、公开 API/构建与根/私有静态检查通过。保持 20 秒和零重试；详情归私有 `sourceViewCheckpoint`。源创建/复制/删除及默认样式、占位符定义和背景等专用设置仍待实现；未跑全量或外部 Office。

P10 水平标尺通过 13 项定向核心检查、两条不同 Chromium 流程及 2305 项当前安装包断言。覆盖缩进、继承制表位、RTL/表格/分栏原点、小数页边距、取消与单次提交、键盘焦点、精确历史、重开输入和 PDF 坐标。检查另发现并修正属性制表位导致的查找偏移，沿用现有查找回归。记录归私有 `rulerCheckpoint`，保留首次构建、交互、参数、查找和包清单失败；宽栏流程保留较早 hash，最终标尺流程及核心/安装包验证后续修正。未跑全量或无关 XLSX/PPTX；多节、纵向标尺和表列边界交互仍待实现。

P11 SUMSQ 通过 14 项定向核心检查及两条 Chromium 流程。覆盖直接参数与引用转换、错误差异、溢出、参数上限、稀疏整列、共享/名称/跨表重算、旧缓存、结构与精确历史。默认公式栏、独立 XML、保存重开及 PDF 已检查。未知链用已核实依赖的 DEVSQ 保留安全编辑和打印保护。记录归私有 `sumSquaresCheckpoint`，保留首次语法、错误码预期及隐藏表依赖检查的失败证据。API 和 TS 边界未变，复用此前安装包边界检查；当前引擎由核心及 Worker/浏览器验证。未跑全量或无关 DOCX/PPTX 流程，三个阶段仍为部分交付。

P12 自定义放映通过 23 项定向核心检查，覆盖重复条目计时、隐藏页与显式跳页、下一页预览缓存、标准关系源、页移动/复制/删除、引用保护和精确历史。新增 Chromium 流程检查定义创建/改名/复制/删除、条目调整、重复页及预览像素、保存重开和选区恢复；原有静态放映、飞行和自动换页三条回归也通过。最终安装包通过 2295 项断言和严格宿主，补齐 Web 入口的 PptxQuery 类型导出。记录归私有 `customShowCheckpoint`，保留夹具、静态检查和首次宿主编译的失败记录及旧 hash。未跑全量、外部 Office 或无关 DOCX/XLSX；默认放映选择编辑已由下述设置增量接通；动作链接、媒体和临时画笔继续实施。

P11 颜色筛选通过 12 项定向核心检查、普通区域与原生表两条 Chromium 流程，以及 2149 项最终安装包断言和严格宿主编译。覆盖有效填充/字体色、无填充、多列交集、手动隐藏、SUBTOTAL、原生输入、精确历史、标准 DXF 源、结构同步、重开和 PDF。保留测试输入/预期错误及缺少明确可访问名称的失败证据；修正后沿原超时、零重试复查。详细记录归私有 `colorFilterCheckpoint`；复用此前 DOCX/PPTX 结果，未跑全量及性能矩阵。

P12 多选独立宽高缩放通过 10 项定向核心检查，覆盖旋转成员、共线直线、候选取消、精确历史、组预览和图片平铺边界。已有缩放组取消组合的 Chromium 流程通过；新角点流程首次因角点在视口外未触发拖动，改用默认缩放控件后只复查该流程，并通过原生输入、独立源、重开及 PNG/PDF 像素检查。最终 2135 项安装包断言与严格宿主通过。记录归私有 `selectionAxesCheckpoint`，保留首次失败及旧构建 hash。未跑全量、无关 DOCX/XLSX 或性能矩阵；各阶段仍未全部完成。

P10 不等宽分栏通过 27 项分栏/页面/表格/缓存/页边核心检查；补齐目标栏的段落保留预估后，复查 18 项分栏与保留规则用例，共 39 项不同用例。两条 Chromium 流程检查等宽回归和不等宽控件、原生输入、精确历史、独立源、重开及 PNG/PDF 几何；改用核心物理页宽显示末栏后，只复查新流程，并检查 500 pt 源纸型的 406.9 pt 剩余宽度。三项 TS 用例、135 项断言与最终 2135 项安装包断言通过。详细构建边界和记录归私有 `unequalColumnsCheckpoint`；浏览器之后的保留规则修改以核心和最终安装包覆盖，未重跑浏览器。未跑全量或无关 XLSX/PPTX 运行；此段保留当时的验证范围，后续表格栏宽结果见下段。

P10 表格实际起始栏宽度通过 31 项定向核心检查。两条 Chromium 流程覆盖宽栏创建、面板上限、调宽、百分比适配、原生输入、精确历史、独立源、重开与 PDF 坐标，以及已有自动适配回归。三项 TS 用例的 139 项断言和最终 2135 项安装包断言通过。详细记录归私有 `tableColumnPlacementCheckpoint`；旧构建 hash 已归档。未跑全量或无关 XLSX/PPTX 运行。固定网格超出后续窄栏仍拒绝，更广跨宽度兼容和各阶段其余范围继续实施。

P11 自定义表样式定义已有三项新增核心检查，连同已有表/样式/条件格式/自动适配共 23 项通过。三条 Chromium 流程检查内置、导入及新建定义，覆盖默认控件、原生输入、五步精确历史、独立源、保存重开及 Canvas/PDF。新流程发现 24 pt 字号未触发行高重排；现按旧、候选各自的表定义比较，并共用计算预算。扩展原核心用例验证应用及改名后的行高。补齐大小写名称冲突保护后，仅复查三项定义用例并通过；最终重新打包通过 2125 项断言与严格宿主。早期标签与行高失败留在私有 `tableStyleDefinitionCheckpoint`；保持 20 秒和零重试。未跑全量或无关 DOCX/PPTX 运行；各阶段仍未全部完成。

P11 已有自定义表样式新增三项核心，连同表、内置样式、条件格式和自动适配共二十项定向检查通过。补齐普通区域的合法 size 元数据及非空文字保护后，只复查三项新例并通过。检查 13 类区域优先级、条纹尺寸、差异格式、直接覆盖、公式、精确历史和重开。内置样式与自定义样式两条 Chromium 功能链跨定向运行通过；新例检查默认目录/控件、原生输入、独立 XML 与其他部件、实际 Canvas 固定 RGB、PDF 颜色和计算文字。保留 option 断言与重算标记预期的初次失败，按原生属性及既有精确重算标记修正，维持 20 秒与零重试。最终 2101 项安装包断言、严格宿主、接口/构建及静态检查通过，证据归私有 `customTableStyleCheckpoint`。本记录未覆盖自定义定义创作；后续证据见上一段。未跑全量、无关 DOCX/PPTX 流程或外部 Office。

P12 渐变色标不透明度新增一项主题/系统颜色检查，并扩展已有色标、保护和预算用例；共十四项定向核心检查通过。三条 Chromium 流程检查 RGBA 背景、带有色背景的形状及 XLSX 数据条。随后独立 qpdf 检查发现已有 writer 仍声明 PDF 1.0，修正为软遮罩要求的 PDF 1.4 后，仅补跑两条 PPTX 流程并通过。覆盖色标不透明度控件、alpha XML、精确历史、重开、轮廓外和后续内容，以及 Canvas/Poppler PDF 的固定位置合成颜色。最终 2085 项安装包断言、严格宿主、接口/构建及静态检查通过，证据归私有 `gradientOpacityCheckpoint`。保持 20 秒与零重试；未跑全量、无关 DOCX 流程或外部 Office。径向渐变、效果及其余阶段范围继续实施。

P12 多色标渐变新增两项核心，连同背景、形状、图片及 XLSX 数据条共十三项定向检查通过。首轮十一项通过；两项旧保护夹具改用未知属性后单独通过，保留首轮失败。覆盖 2–32 色标、内部端点、重复位置突变、规范化、几何、精确历史及参数/源/预算原子拒绝。三条 Chromium 流程检查背景控件、独立 XML、重开及 Canvas/PDF 固定位置颜色，并回归形状渐变和 XLSX 数据条。2079 项安装包断言、严格宿主、公开接口/构建与静态检查通过，证据归私有 `gradientStopsCheckpoint`。未跑全量、无关 DOCX 运行流程或外部 Office；透明/径向渐变继续实施，各阶段仍为部分交付。

P10 分栏符新增两项源事务用例，并扩展已有分栏布局用例。与软换行/分页符、表格控制、段落保留及孤行回归共二十项定向核心检查通过。覆盖单栏/末栏换纸、连续分栏、末尾光标、缓存、格式、查找替换、组合候选、精确历史和保护/预算原子拒绝。两条 Chromium 流程检查默认按钮与 Ctrl+Shift+Enter、原生输入、独立源节点、混合历史、重开删除、正文 PDF 文字位置，以及格内分栏符不打断 `Neighbor` 的提取结果。2059 项安装包断言、公开常量与宿主编译、构建和静态检查通过；详细证据归私有 `columnBreakCheckpoint`。首轮浏览器检查等待未保存文档的离开确认，补齐保存步骤后通过，保持 20 秒和零重试。未跑全量、无关 XLSX/PPTX 运行流程或外部 Office；多节、不等宽栏及其余阶段范围继续实施。

P10 等宽分栏新增两项源事务与三项布局用例，连同页面、自动适配、普通/合并续行、分页缓存及页边字段共二十三项定向检查通过。覆盖末页平衡、分页符换纸、整页页边区域、当前栏表格几何、重复表头、命中、精确历史、重开，以及保护和预算原子拒绝。一条 Chromium 流程检查默认面板、跨栏原生输入、三项混合历史、独立 XML、保存重开、Canvas/PNG/PDF 分隔线和文字位置。三项受影响的 TS 用例、2057 项安装包断言、严格宿主编译、公开构建及静态检查通过；详细证据归私有 `columnsCheckpoint`。未跑全量、无关 XLSX/PPTX 运行流程或外部 Office；不等宽栏、多节继续实施，各阶段仍为部分交付。

P12 图片目标内缩新增两项核心，连同图片替换、形状图片/平铺、背景及带裁剪平铺共十七项定向检查通过。覆盖目标与源裁剪组合、正负内缩、透明度、继承背景、本地源保持、同值、模式转换、边界失败、精确历史及重开。两条 Chromium 流程覆盖默认内缩/重置、图片与形状多选、旋转椭圆、背景、独立 XML、保存重开及同一份 PDF 与 Canvas 的固定位置像素，并回归已有形状图片和原生文字流程。2041 项安装包断言、严格宿主、接口/构建及静态检查通过，详情归私有 `imageInsetsCheckpoint`。未跑全量、无关 DOCX/XLSX 流程或外部 Office；P10、P11、P12 仍为部分交付。

P11 原生表去重新增三项核心，连同普通去重、原生排序/范围及筛选排序回归，共十四项定向检查通过。覆盖整表预览、标题/总计排除、根/嵌套排序裁剪、模板/例外、总计迁移、无标题/无筛选、单行结果、表外依赖与多筛选来源、便笺/链接、精确历史和重开。两条 Chromium 流程覆盖默认去重控件、原生输入、独立 XML、重开与 PDF，并回归普通排序/筛选去重；详细运行与修正记录归私有 `tableDuplicatesCheckpoint`。2006 项安装包断言及严格宿主编译通过，预览边界显式校验 `totalRow`。未跑全量或无关 P10/P12 运行检查；各阶段仍为部分交付。

P11 原生表 Dark1–11 全系列新增一项核心，连同表、样式、条件格式及自动适配共十八项定向检查通过。初轮十七项回归通过；修复新夹具的保留字及 XML 编辑坐标后，仅补跑 Dark 项并通过。覆盖全部十一种固定 RGB、字体/总计线、强调列、正常格式继承、粗体需求、直接覆盖、四步精确历史、重开及无关 OPC 部件保持。两条 Chromium 流程覆盖默认控件切换、三步历史、独立 XML、重开和同一份 PDF 的标题/条纹/线条 RGB，并回归排序/范围操作。1998 项安装包断言、严格宿主、接口/构建及静态检查通过，详情归私有 `darkTableStyleCheckpoint`。三类共 60 种内置表样式已接通；自定义差异样式仍待实现。未跑全量或无关 P10/P12 流程。

P11 原生表 Light1–21 全系列新增一项核心，连同表、样式、条件格式及自动适配共十七项定向检查通过。覆盖三组灰阶/颜色/末项变体的有色文字、条纹、可选内部网格、完整网格、标题/总计线，三步精确历史、重开及所有无关 OPC 部件保持。两条 Chromium 流程在同一产品构建跨定向运行通过，包含 Light 默认控件切换、独立 XML、保存重开和同一份 PDF 的底色/网格线 RGB，并回归排序/范围操作。新增 XML 断言因命令尾换行失败，复用已有输出处理后只重跑该流程并通过；原名称和颜色预期保持。1988 项安装包断言、严格宿主、接口/构建及静态检查通过，详情归私有 `lightTableStyleCheckpoint`。未跑全量或无关 P10/P12 流程；Dark 及自定义表样式继续实施。

P11 原生表 Medium1–28 全系列新增一项核心，连同原生表、样式、条件格式和自动适配共十六项定向检查通过。独立固定值覆盖新增三组的灰阶/颜色及末项变体、网格与总计线、强调列优先、直接格式保留、重开，以及无标题普通总计的字体需求。两条 Chromium 流程覆盖默认控件跨组切换、三步精确历史、重开、同一份 PDF 的独立底色/条纹 RGB，并回归排序/范围操作。1978 项安装包断言、严格宿主、接口/构建及静态检查通过，详情归私有 `mediumTableStyleCheckpoint`。未跑全量或无关 P10/P12 流程；Light/Dark 及自定义表样式继续实施。

P11 原生表样式编辑新增两项核心，连同表、格式、条件格式及自动适配共二十项定向检查通过。覆盖 Medium1–7 独立固定色值、首末列与条纹、直接格式优先、清除、源部件保持、十一项精确历史、重开及选择器/别名/预算保护。两条 Chromium 流程在同一产品构建跨定向运行通过，覆盖新默认控件及原生排序/范围回归；新流程检查独立 XML、原生输入、两步历史、重开和同一份 PDF 的独立 RGB。初轮把填充草稿输入值误作当前颜色，确认已有 placeholder 语义后仅重跑新流程并通过，保留固定颜色预期和失败记录。1970 项安装包断言、严格宿主、接口/构建与静态检查通过，详情归私有 `tableStyleCheckpoint`。未跑全量或无关 P10/P12 流程；其余内置样式及自定义差异样式继续实施。

P11 已有排序状态的原生表范围调整新增一项核心，连同表范围、筛选结构及原生排序共十五项定向检查通过。覆盖根/嵌套排序、扩大保留历史源、纵横缩小及键移除、组合筛选和手动隐藏、模板/例外、稳定列身份、五步精确历史、重开和未知样式保护。补充无筛选节点的颜色排序扩表后，仅重跑对应项并通过。两条 Chromium 流程覆盖排序后扩表及已有筛选结构回归，检查默认控件、独立 XML/无关部件、总计、撤销重做、重开输入及最终同一份 PDF。1960 项安装包断言、严格宿主、接口/构建与静态检查通过，详情归私有 `tableSortResizeCheckpoint`。未跑全量或无关 P10/P12 流程；扩表不自动重排新增数据，原生表横向排序和跨边界排序仍保护。

P11 含原生表工作表的普通区域排序新增一项核心，连同原生/普通排序、筛选排序及去重共十三项定向检查通过。覆盖表外行/列排序、原生计算列依赖、组合筛选与手动隐藏、9/109 总计、独立排序状态、精确历史、重开和未知元数据保护。扩展已有原生表面板流程，并回归普通排序，共两条 Chromium 流程通过；独立 XML 检查确认表外排序保留原生表部件。1960 项安装包断言、严格宿主、接口/构建及静态检查通过，详情归私有 `outsideTableSortCheckpoint`。未跑全量或无关 P10/P12 流程；跨表边界、原生表横向排序和有排序状态的表范围调整仍保护。

P11 原生表排序新增四项核心，连同普通排序、筛选排序、颜色、列表及状态共十五项定向检查通过。覆盖整表数据扩展、模板与例外、便笺/链接、隐藏记录、多筛选重算、原生排序状态、复制/整轴引用和原子保护。两条 Chromium 流程覆盖默认原生表面板与普通排序回归，检查独立 XML、无关部件、原生输入、精确历史、重开及同一份 PDF。1960 项安装包断言、严格宿主、接口/构建和静态检查通过；详情归私有 `tableSortCheckpoint`。未跑全量或无关 P10/P12 流程；横向表排序和有排序状态的范围调整仍保护。

P11 原生表筛选的范围及整轴同步新增四项核心，与原生筛选、表轴/范围、普通筛选轴、筛选排序及分组共二十四项定向用例通过。覆盖条件/按钮/排序键移动、插在总计前的新行、多筛选隐藏交集、整表资源删除与恢复、移出行可见性、手动隐藏保留、最终生成值验证和预算原子保护。初轮二十三项通过；修复导入部件删除后只重跑对应项，最终四项新用例通过并复用二十项回归结果。四条 Chromium 流程在最终构建通过，覆盖新结构流程、已有原生筛选及两条普通轴回归，包含独立 XML/无关部件、五步精确历史、重开和同一份 PDF。接口/构建及静态检查通过；公开类型与 TS 入口未变，沿用前批 1960 项安装包断言。详情归私有 `tableFilterStructureCheckpoint`。未跑全量或无关 P10/P12 流程；表内排序继续实施。

P11 原生表筛选新增三项核心，连同值/自定义/排名/平均值/日期筛选、SUBTOTAL、分组及导入表共二十八项定向检查通过。覆盖原生条件与总计边界、多表和普通筛选的隐藏交集、手动隐藏/分组恢复、重新应用、七步精确历史、重开及源/预算保护；补充含筛选工作表复制后，仅重跑对应一项并通过。三条 Chromium 流程覆盖新面板、普通筛选及计算列/总计回归，检查独立 XML、无关部件、原生输入、四步精确历史、重开及同一份 PDF。1960 项安装包断言、严格宿主、接口/构建和静态检查通过，详情归私有 `tableFilterCheckpoint`。未跑全量或无关 P10/P12 流程；筛选中的表范围结构同步仍保护。

P11 含原生表工作簿的名称编辑新增三项核心，连同名称编辑/计算、原生表工作表资源及内部链接共十六项定向检查通过。覆盖结构化范围名称、计算列/总计的全局及局部作用域改名、同名列标题保留、限定引用、删除后的计算、表名冲突、循环、数组源及预算原子保护。两条 Chromium 流程检查默认名称面板、冲突恢复、原生输入、独立 XML/无关部件、四步精确历史、重开及同一份 PDF，并回归普通名称计算/显示。1949 项安装包断言、严格宿主、接口/构建及静态检查通过；详情归私有 `tableNameCheckpoint`。未跑全量或无关 P10/P12 流程。

P11 含原生表的工作表改名、复制和删除新增四项核心，连同工作表结构/复制/删除、原生表及表轴共二十六项定向检查通过。覆盖原生计算列/总计公式改名、多表独立资源与同名避让、副本间引用、导入局部名称重定向、全局名称保持、源与副本独立输入、删除后的依赖错误、资源归属和精确混合历史。补充全局名称的精确源断言后，仅重跑对应复制用例并通过。两条 Chromium 流程检查默认按钮、原生输入、独立 XML/无关部件、四步精确历史、保存重开及同一份 PDF，并回归便笺资源生命周期。1949 项安装包断言、严格宿主、接口/构建及静态检查通过；详情归私有 `tableSheetCheckpoint`。未跑全量或无关 P10/P12 流程。

P11 原生表整行/列插删新增四项核心，连同普通轴、整轴公式、筛选/便笺结构、已有表、计算列、总计和工作表删除共二十九项定向检查通过。覆盖范围和列身份、首数据行模板重定位、新行计算、永久列引用错误、总计删除、整表及本会话新建资源清理、其他表保留和精确混合历史。补充的新增计算格验证失败检查仅重跑对应一项用例，通过且保持原包、revision 和历史。四条 Chromium 流程覆盖原生表插删及两条普通轴回归、计算列/总计回归，包含独立 XML、无关部件、资源删除、精确历史、重开和同一份 PDF。1949 项安装包断言、严格宿主、接口/构建及静态检查通过；详情归私有 `tableAxisCheckpoint`。未跑全量或无关 P10/P12 流程。

P11 计算列与总计创作新增六项核心，连同范围、创建及导入表共十九项定向检查通过。覆盖整列重填、相对/绝对/当前行引用、保留公式的模板移除、八种原生总计、导入页脚内容、显式无、隐藏恢复、精确混合历史和验证/源/预算保护。新增 Chromium 流程通过原生输入、失败恢复、独立 XML/无关部件、两组精确历史、重开及同一份 PDF；三条表格回归沿相同引擎复用，界面构建资格归私有 `tableColumnCheckpoint`。1949 项安装包断言和严格宿主编译通过。未跑全量或重跑无关 P10/P12 流程；行列结构同步、表筛选及其余阶段能力继续实施。

P11 结构化表范围调整新增五项核心，连同创建及导入表共十三项定向检查通过。覆盖行列扩缩、列身份、移出数据保留、永久引用错误、局部引用归属、总计迁移、计算列空白补齐/例外、名称/跨表依赖、条件范围、精确历史及源/预算保护，并修复其他表计算列的引用更新被误拒绝。范围调整、创建和改名三条 Chromium 流程在同一构建上通过；新流程检查原生输入、总计目标冲突、三步精确历史、独立 XML/全部无关部件、重开和同一份 PDF。1922 项安装包断言、严格宿主、接口/构建及静态检查通过，详情归私有 `tableResizeCheckpoint`。未跑全量；行列结构同步、计算列创作、总计设置和表筛选继续实施。

P11 从选区创建结构化表新增三项核心，连同导入表、便笺资源及空白工作簿共十二项定向检查通过。覆盖标题补名/去重、公式标题转换、结构化依赖、资源关系和内容类型、已有表保持、精确混合历史与重开，以及重叠/名称/预算失败恢复。新建和已有表两条 Chromium 流程通过，检查原生公式输入、创建后改名、全部无关部件的独立比较、XML、三步精确撤销重做、重开及同一份 PDF。1916 项安装包断言、严格宿主、公开接口/构建和静态检查通过，详情归私有 `tableCreateCheckpoint`；未跑全量。扩表、总计及表筛选继续实施。

P12 当前页及全页 JPEG 接通公开 API 和默认菜单，复用既有 PNG 流程。四条 Chromium 检查覆盖 JPEG 格式/尺寸/实际颜色、PNG 无损像素、原生输入、源与选择保持、同修订页序、隐藏页、总预算、编码格式回退拒绝、逐页保存失败/重试、重开及 PDF，并回归 DOCX 共用 PNG 编码和进度。1909 项安装包断言、含 JPEG 调用的严格公开宿主、构建及静态检查通过。详情归私有 `jpegCheckpoint`；核心未变，未新增核心用例或跑全量。打印界面和阶段其余项继续实施。

P11 导入结构化表新增五项核心，连同名称、结构插删、规则移动、自动适配、条件格式、合并边框和格式共二十八项定向检查通过。覆盖结构化引用、数据重算、表/列改名、特殊标题转义、原子保护、Medium2 样式、直接/条件格式优先级、双线和精确历史。一条 Chromium 流程检查原生输入、默认面板改名、独立 XML、保存重开及同一份 PDF。最终安装包 1909 项断言、严格宿主、公开接口/构建和静态检查通过。详情归私有 `tableCheckpoint`；创建、扩表、行列结构同步、总计设置、表筛选及其他表样式仍待实现。未跑全量或外部 Office。

P11 合并格格式刷新增两项核心，连同格式、合并及边框共十一项定向检查通过。覆盖相对合并快照、二维平铺/末块裁短、跨表、底层值与共享公式保留、仅取消合并、精确历史、重开，以及部分范围、非法/重叠合并、数量和输出预算的原子拒绝。一条 Chromium 流程检查原生草稿、默认格式刷与范围框、独立 XML、Canvas/命中几何、重开及同一份 PDF，并确认取消最后一个合并后无空容器。最终安装包 1830 项断言和严格宿主通过，详情归私有 `mergedPainterCheckpoint`；未跑全量或外部 Office。

P12 批量 PNG 新增一项核心和一条 Chromium 流程。九项定向核心检查覆盖打印页序、隐藏页筛选、编辑布局保留及失败保护；浏览器检查非当前页图片、总字节预算、原生输入、精确历史、逐页宿主失败/重试、重开、PDF 和关闭时的输出顺序。既有单页 PNG 与 DOCX 多页流程按适用构建范围复用。最终安装包 1820 项断言、严格宿主编译和三个包的精确文件清单通过，详情归私有 `slideImagesCheckpoint`。JPEG、打印界面及阶段其余项继续实施，未跑全量或外部 Office。

P10 单节页码起点与六种常用格式新增三项核心/布局用例，连同区域字段、页面设置和分页缓存，共十一项核心、八项布局检查通过。Flow 边界三项、130 项断言通过。两条 Chromium 流程检查编号和显式字段格式、奇偶变体、原生输入、源缓存、精确历史、重开、Canvas 与同一份 PDF；同时修复了重开后空白首页聚焦会停止编辑的问题。当前安装包 1814 项断言及严格公开宿主编译通过。详情归私有 `pageNumberingCheckpoint`；多节、章节前缀及更广格式仍待实现，未跑全量或外部 Office。

P11 的 SQRT、POWER、PRODUCT 和 MEDIAN 已接通真实求值。三项新增核心连同数值、SUBTOTAL 和未知公式隔离共十一项定向检查通过，覆盖类型、引用顺序、错误、稀疏区域、共享公式、跨表缓存、隐藏行、精确历史及工作量/输出回滚。两条 Chromium 流程检查原生公式输入、独立 XML、源缓存、精确撤销重做、重开和同一份 PDF。首轮发现的 General 二进制尾数已在显示层修正为十五位有效数字；原值和源缓存保持，去重预览及撤销也已检查。详情归私有 `extendedNumericCheckpoint`。本批接口及平台代码未变，安装包结果保留此前构建范围；未跑全量、外部 Office 或性能矩阵。

P12 自动日期创作新增两项核心，连同导入日期、页脚、版式、编号、页面及复制共二十五项定向检查通过。覆盖格式/语言、固定/自动切换、字段身份、当前时间与缓存、精确混合历史、重开，以及缺时间、混合字段和后续页缺字体的整批回滚。三条 Chromium 流程通过，包含自动日期面板、原生草稿、源 XML、重开及两页 PDF，并回归导入日期与固定页脚。当前安装包 1792 项断言、严格宿主、公开 API/构建及静态检查通过。详情归私有 `automaticDateCheckpoint`；更多语言及独立缓存写回仍待实现，未跑全量或外部 Office。

P12 导入动态日期新增三项核心，连同页脚、版式、编号、页面及复制共二十三项定向检查通过。覆盖三种语言、十三种格式、统一时间、字体选择、母版继承、精确历史及刷新失败回滚。Chromium 流程验证日期刷新、Canvas 墨迹、原生输入、重开、同一份 PDF 和 PNG；安装包 1781 项断言及严格宿主通过。详情归私有 `dateFieldsCheckpoint`。动态日期创作及更多语言尚待实现，未跑全量或外部 Office。

P12 固定日期、页脚和编号编辑新增三项核心，连同版式/页边、编号、页面及复制共二十项定向检查通过。覆盖空白创建、模板几何、已有格式/多行文字、当前页/全部页、编号身份、移除后的多选、精确混合历史、重开，以及后续页保护、非法文字、旧修订和输出预算的整批回滚。扩展既有 Chromium 流程检查专用面板、正文草稿、全部页应用、当前页移除、撤销重做、重开和同一份 PDF 的两页日期/页脚/实际编号；保持 20 秒和零重试。当前安装包 1765 项断言、严格宿主、公开 API/构建及根/私有静态检查通过。实现中修正临时对象身份、可选文字的 JSON 序列化和混合类型校验，并补齐打包入口与精确文件清单；首轮失败记录保留，不计通过。详情归私有 `footerCheckpoint`。动态日期创作尚待实现，未跑全量、外部 Office 或性能矩阵。

P12 版式页边内容新增两项核心，连同版式/重置、编号、页面和复制共十七项定向检查通过。覆盖开关缺省/继承/覆盖、固定日期/页脚保留、编号计算、新字段身份、精确历史、重开，以及动态日期、跨部件关系、未知设置和输出预算的原子拒绝。新增 Chromium 流程检查默认版式面板、原生草稿、编号 7→8 的红色 Canvas 墨迹变化、源缓存/版式/母版保持、精确混合历史、重开和同一份 PDF；既有对象保护流程也通过，保持 20 秒和零重试。首轮浏览器用例补齐撤销后的编辑队列屏障，旧分组矩阵断言改按现有归一化合同检查，并独立保留 20×20 实际尺寸。公开 API、构建和根/私有静态检查通过；接口和平台代码未变，复用前批安装包与严格宿主结果的原构建范围。详情归私有 `layoutFieldsCheckpoint`；未跑全量、外部 Office 或性能矩阵。

P12 幻灯片编号字段新增两项核心，连同页增删/重排、复制及备注共十三项定向检查通过。覆盖起始编号、实际页序、隐藏页、复制/删除、精确混合历史、重开、源缓存保留、文字编辑保护及定位输出；未知类型和字段段落属性继续保留缓存并诊断。本批未新增浏览器、PDF 编码或安装包检查；此前结果保留各自构建范围，不作为本批编号显示的证据。详情归私有 `slideNumberCheckpoint`，P12 仍在实施。

P12 起始编号编辑新增两项核心，连同编号字段、页脚及主题字体共十项通过。覆盖零值、最大起点及后续页、隐藏页、页重排、无变化、精确历史和源缓存保留，以及自动大小/缩小、继承字段、共享尺寸冲突、缺字体、活动候选、未知域和输出预算原子拒绝。扩展既有 Chromium 页脚流程，检查原生草稿后修改起点、红色编号墨迹、独立 XML、两步精确历史、重开和 PDF 的 0/1 编号。1850 项安装包断言、严格宿主、公开 API/构建及根/私有静态检查通过；保持 20 秒、零重试。详细证据归私有 `firstSlideNumberCheckpoint`。未跑全量、外部 Office 或性能矩阵。

P11 行列分组新增四项核心，连同自动适配、结构插删、筛选及两项尺寸回归共十六项通过。覆盖七级嵌套、内外组折叠/展开、汇总位置、取消/清除、原尺寸和单元格、筛选来源、两类 SUBTOTAL、精确历史和重开。结构用例检查插入项继承、折叠组中新行列隐藏、汇总项删除后迁移及边界原子拒绝。Chromium 流程检查原生文字后分组、默认面板、行列及嵌套可见性、独立 XML、混合撤销、清除、重开及 PDF 隐藏结果。1883 项安装包断言和严格宿主通过，六项新增文件的三包精确清单、生成接口、公开构建与静态检查通过。保持 20 秒、零重试；详情归私有 `outlineCheckpoint`。未跑全量、外部 Office 或性能矩阵。

P11 EXACT/REPT 接入真实求值后，文本、逻辑、数值及局部计算共十一项定向核心检查通过。扩展既有文本结果表和参数个数检查，新增边界/依赖/缓存/历史用例，覆盖大小写、Unicode、类型/空白/错误、原始小数次数、32767 单元输出、保存类型及低预算失败恢复；原有两项未计算样例改为检查实际 TRUE/99，另四项未支持函数继续保护。既有 Chromium 文本公式栏流程增加两函数，保留原生输入、独立源/缓存、精确撤销、重开和同一份 PDF 的实际文字，20 秒与零重试保持。公开接口未变，复用前批 1747 项安装包断言和严格宿主；本批 API、构建、根/私有静态及源/链接/diff 检查通过。详情归私有 `exactReptCheckpoint`，未跑全量、外部 Office 或性能矩阵。

P10 页边文字与 PAGE/NUMPAGES 混合编辑新增四项核心，连同导入、页边编辑/开关、独立部件和页面共十四项定向检查通过。覆盖字段增改删、规范化无操作、显式缓存刷新、首页/偶数页/默认的缓存值、代码/样式/未改段落保持、精确历史、重开，以及字段/文字/输出上限与旧修订失败恢复；缓存单独扩展后超出一字节输出预算也保持原状态。扩展既有 Chromium 流程检查原生分页、只读保存、显式缓存写回、光标处插入两类字段、种类修改/移除、五步精确混合历史、独立 XML、重开及同一份 PDF 每页结果；另三条既有页边流程已通过并复用。当前安装包 1747 项断言、严格宿主、公开 API/构建及根/私有静态检查通过；布局算法未变，复用前批十八项布局结果。保持 20 秒与零重试；详情归私有 `runningContentCheckpoint`。未跑全量、外部 Office 或性能矩阵。

P10 导入页边 PAGE/NUMPAGES 新增五项核心，连同页眉页脚/独立部件、页面、分页缓存、间距和跨页表格共二十八项定向检查通过。覆盖简单/成对域、拆分指令/缓存、首个结果样式、当前页号/总页数、9→10 的换行、总页数反馈重排、正文与普通/合并表格避让、冷/热缓存、源与缓存保持、精确历史及重开；未知/锁定/嵌套/不完整/超长指令原子拒绝。新 Chromium 流程检查逐页文字、Canvas 红色页码、字段区域纯文字保护、原生 Ctrl+Enter 将总数从 2 更新为 3、精确撤销重做、部件字节、重开及同一份 PDF 每页文字；保持 20 秒和零重试。定向测试发现重排首页仍采用旧正文空间，修正构造入口后重跑核心、构建和浏览器，并补普通/合并表格边界。公开 Span 增加字段元数据，当前安装包 1728 项断言、严格宿主、边界单元及根/私有静态检查通过；字段创作/缓存更新未交付，详情归私有 `runningFieldsCheckpoint`。未跑全量、外部 Office 或性能矩阵。

P12 独立图片平铺新增三项核心，与图片插入/替换/裁剪/透明度、形状平铺及背景共十九项定向检查通过。覆盖独立重复尺寸、共享资源隔离、旋转翻转、裁剪保留/激活、隐式拉伸、导入对齐/镜像、预设框裁剪、精确历史及重开；密集平铺、激活后的尺寸、未知源和输出预算失败保持原子拒绝。既有图片 Chromium 流程增加默认模式按钮、裁剪和平铺切换、五步精确混合历史，保留损坏文件恢复与读取期间选择变化；同一份 PDF 同时检查替换后的洋红色和椭圆图片框内外的平铺像素，导出不改源。保持 20 秒与零重试。初次矩形流程通过后，修正非矩形图片框沿矩形裁剪的问题，并重跑该流程及定向核心/构建。当前安装包 1728 项断言、严格宿主、公开 API/构建和根/私有静态检查通过；详情归私有 `pictureTileCheckpoint`。未跑全量、外部 Office 或性能矩阵。

P12 带裁剪源的平铺新增三项核心，连同背景/渐变、形状图片、平铺和透明度共二十二项定向检查通过。按 ONLYOFFICE 保留 `srcRect`，平铺使用完整源尺寸，拉伸重新应用裁剪。覆盖四种来源、独立平铺/拉伸尺寸、已有对齐/翻转、替换和透明度、资源/源保持、精确历史及重开；未生效裁剪不触发拉伸尺寸保护，激活后超限和密集平铺仍原子拒绝。现有背景 Chromium 流程保留非零裁剪切换平铺，核对四象限、五步精确历史、重开切回拉伸、原生文字及同一份 PDF；保持 20 秒与零重试。独立原生 Canvas 对照确认当前后端的半透明像素，最终保持精确比较。当前安装包 1721 项断言、严格宿主、公开 API/构建和根/私有静态检查通过；详情归私有 `tileCropCheckpoint`。未跑全量、外部 Office 或性能矩阵。

P12 图片背景格式新增两项核心，与背景/渐变、普通图片裁剪/透明度、形状透明度和平铺共二十项定向检查通过。覆盖四种来源、规范化、源属性/资源保持、零透明与裁剪重置、无操作、精确历史和重开，以及非法输入、源保护、旧修订和预算原子拒绝。既有 Chromium 背景流程加入裁剪加半透明、独立 XML、色块内部 Canvas、重置平铺、五步精确历史、重开原生文字及同一份 PDF 的精确色值/文字；保持 20 秒与零重试。初次取样跨过放大图片的颜色交界，改在色块内部；PPM 核对固定 Poppler 的半透明量化为 127，PDF 保留精确断言。当前安装包 1721 项断言、严格宿主、公开构建/接口和根/私有静态检查通过；更新较窄的模式命令及调用方，保留同一事务。详情归私有 `backgroundFormatCheckpoint`；未跑全量、外部 Office 或性能矩阵。

P11 整行/整列公式新增三项核心，连同查找、条件聚合、填充、名称及结构/规则共二十四项定向检查通过。覆盖边缘稀疏值、全表逻辑面积、空白计数、查找正反向和未命中、复制标记、跨表名称、变为有界引用后的调用偏移、缓存、精确历史与重开；语法、循环、输出和工作预算失败保持原子拒绝。既有查找 Chromium 流程改用整行/整列，检查原生公式、独立 XML、重算、撤销、重开及同一份 PDF，保持 20 秒与零重试。最终保留小范围直接读取，避免扫描无关已用格，定向核心与构建通过；浏览器复用前一构建未变的大范围路径，私有记录保留对应 hash。公开接口、桥和 TS 未变，复用前批 1701 项安装包断言及严格宿主；接口生成、根/私有静态和源/链接/diff 检查通过。详情归私有 `axisFormulaCheckpoint`；未跑全量、外部 Office 或性能矩阵。

P11 相对名称结构编辑新增两项核心，连同已有名称、行列/单元格结构及规则共十六项定向检查通过。覆盖保存坐标、同表/跨表调用位置、相对/混合标记、局部作用域、嵌套名称、范围裁短、删除目标、验证规则重算、精确历史和重开；未限定工作表、不透明源与预算失败保持原子拒绝。一条新增 Chromium 流程首轮通过，沿既有行列按钮检查原生草稿、独立名称/单元格 XML、隐藏表缓存、三步精确历史、重开输入和同一份 PDF。公开 API、桥和 TS 未变，复用前批 1701 项安装包断言及严格宿主；本批重新生成 API、构建并通过私有静态与源/链接/diff 检查。详情归私有 `relativeNameCheckpoint`，未跑全量或外部 Office。

P12 图片背景新增三项核心，连同已有背景/渐变、图片事务和平铺共十二项定向检查通过。覆盖四种来源、裁剪/透明度读取、局部源属性保留、模式/资源复用、复制、精确历史、重开，以及外链/未知源、输入/输出和背景加形状的总平铺上限。新增 Chromium 流程检查透明图片拉伸、不同图片替换、资源及源 XML、前景层次、平铺像素、恢复继承、四步精确历史、重开原生输入和同一份 PDF 的结构/像素/文字；复用已通过的形状图片流程，20 秒和零重试保持。初次定位器包含选项文字，改用既有角色/名称方式；测试框过窄造成正常换行，扩大输入框并保留精确文字断言。当前包 1701 项断言及严格宿主通过；源码属性保留修正后重新构建、运行定向核心和背景浏览器链。类型扩展后的渐变调用方采用明确分支，不使用类型绕过。详情归私有 `backgroundImageCheckpoint`，未跑全量、外部 Office 或性能矩阵。

P10 首页/奇偶页新增一项源事务与两项布局检查，连同默认页边内容、页面、正文导航、缓存、普通/合并格跨页、重复表头、保留链和孤行共 31 项定向核心通过。覆盖六种区域、两个开关、非活动源、缺节/设置部件创建、共享部件保护、精确历史及启用未知内容的原子拒绝；独立行框推导各页计数与上下边界，检查页序偏移后的冷/热布局一致及换色复用。两条短 Chromium 流程首轮通过，检查默认面板、不同正文起点、独立 XML、关闭后保留、原生输入、精确历史、重开和同一份三页 PDF，20 秒与零重试保持。当前安装包 1680 项断言、严格宿主、71 项 Flow 边界断言、构建/接口及根/私有静态检查通过；证据归私有 `runningVariantsCheckpoint`。未跑全量或 Office/性能矩阵。该批未覆盖的共享部件独立操作见下段；多节/继承、页码/字段和页边原生光标仍待实现，合并组重复表头保留既有整组预留边界。

P10 默认页眉页脚新增两项核心，连同页面设置/背景、正文导航、段落/分页缓存及既有空页眉间距共十二项定向检查通过。覆盖部件创建与源顺序、实际避让/底部锚定、两页语义与命中保护、段落/首 run 格式、距离修改保留源、精确历史和重开，以及旧修订、非法值、复杂源/首页/奇偶引用和输出预算原子保护。现有 Flow 边界检查 71 项断言通过。一条 Chromium 流程检查默认面板、Canvas 墨迹、原生正文与过期草稿、独立 XML、精确历史、重开及同一份两页 PDF；20 秒和零重试保持。当前安装包 1671 项断言、严格宿主、公开构建、接口生成及根/私有静态检查通过，详细证据归私有 `runningAreaCheckpoint`。最后的未改段落保真修复及超长源查询保护已重跑核心与构建，复用未变短文字路径的浏览器和 TS 安装包结果。首轮 PDF 文本工具路径遗漏已按既有配置修正并保留失败，不计通过；未扩大全量、外部 Office 或性能矩阵。当时未覆盖的首页/奇偶页结果见前段；页码/字段、复杂对象与页边原生光标仍待实现。

P11 日期组新增三项核心，连同值/自定义/排名/平均值筛选、筛选内结构与排序、SUBTOTAL 共二十项定向检查通过。覆盖年到秒的独立区间边界、1900/1904 日历、最大日期与有界区间合并、条件日期格式、普通文字/数值/纯时间分流、当前公式、多列交集、手动隐藏、结构/复制/改名、精确历史和未知源/预算原子保护。新增一条短 Chromium 日期样例，连同原值筛选共两条通过；检查默认面板、原生公式输入与重新应用、独立 XML/隐藏来源/小计、四步精确历史、重开和同一份 PDF 的可见记录，20 秒与零重试不变。当前安装包的明确文件清单、1659 项断言、严格宿主、公开构建、接口生成及根/私有静态检查通过。新增模块与前批语言模块的清单漏项已补齐，未改变严格清单核对；详细证据归私有 `dateFilterCheckpoint`。未跑全量、外部 Office 或性能矩阵，相对当前日期的动态筛选仍保护。

P12 图片平铺新增两项核心，连同既有图片填充/导入/编辑/透明度/外观/渐变共十五项定向检查通过。覆盖 96 DPI、缩放/偏移/九种对齐、负索引交替翻转、模式切换/共享资源/透明度/精确历史和重开，以及未知源、过密图片编辑和单选/多选变换候选的原子保护。既有图片填充 Chromium 流程扩展为平铺上传、双向模式切换、独立 XML 和重复颜色、五步精确历史、重开原生输入与旋转及同一份 PDF 的像素和文字；20 秒、零重试不变。原外观流程已通过并复用结果，修正控件可访问名称后仅重跑受影响流程；原生输入前等待既有输入焦点，不削弱文字断言。安装包 1640 项断言和严格宿主、构建、接口生成、根/私有静态检查通过；当时复用未改 API 的安装包结果，语言拆分后的明确文件清单由后续日期组批次补齐并重验。详细证据归私有 `shapeTileCheckpoint`。未扩大全量或外部 Office，裁剪后的平铺及其他未知效果继续保护。

P12 形状图片填充新增三项核心，连同已有图片、透明度、外观和渐变共十三项定向检查通过。覆盖共享资源、轮廓裁剪、源裁剪与透明度保留、主题关系归属、本地覆盖、精确混合历史、重开及选择改变、未知源和预算失败原子保护。新 Chromium 流程检查默认图片填充/透明度/清除、原生文字、独立 XML 与资源、Canvas 轮廓内外像素、精确历史、重开旋转及同一份 PDF 的像素和文字；连同既有外观、渐变共三条通过，保持 20 秒、零重试。新安装包 1626 项断言、严格宿主、构建、接口生成及根/私有静态检查通过，详细证据归私有 `shapeImageCheckpoint`。复用未改 DOCX PNG 结果，不扩大全量或外部 Office；平铺及其他受保护图片填充仍属 P12 待实现范围。

P10 全页 PNG 新增一条 Chromium 流程，检查页序/尺寸与独立边框像素、同修订集合、后续输入屏障、总字节预算及失败不交付前缀、当前页/选择/源与精确历史，以及默认逐页命名、宿主部分失败/进度/重试、回调期间编辑、实际多文件下载、保存基线和销毁。连同既有页面背景/边框/单页 PNG/PDF 及 P9 原格式保存回执/替换/双实例共三条定向流程通过，保持 20 秒、零重试；页索引迭代收敛后只重跑新流程，复用未改路径的两条结果。当前安装包 1613 项断言、只读集合 API 的严格宿主编译、构建及根/私有静态检查通过，详细证据归私有 `pageImagesCheckpoint`。核心绘制和 PNG 编码未变，不新增核心测试，不扩大全量、外部 Office 或性能矩阵。

P10 当前页 PNG 扩展既有页面背景/边框 Chromium 流程，覆盖两页、DPR 2 与预览缩放无关的尺寸和全图像素、后续输入不改变输出 revision、原生及组合屏障、默认菜单/保存回调、原格式修改状态、精确历史与保存字节，以及参数/字节/像素预算、未知布局和销毁保护。保持 20 秒、零重试；当前安装包 1613 项断言和新增 PNG 调用的严格宿主编译、公开构建与根/私有静态检查通过。核心绘制及 PNG 编码复用原实现，未新增核心逻辑或扩大核心测试；私有 `docxPngCheckpoint` 记录当前证据及既有 PPTX PNG 结果的复用范围。未跑全量或外部 Office；全页集合的后续结果见上段。

P10 页面边框的双线扩展复用原有两项源事务和一项布局检查，共 3 项定向核心通过。独立 16 个矩形预期覆盖四边内外线、纸张/正文基准、原生每条线宽与三倍总宽、单线混用、缓存复用后正文不变、源顺序/未改部件、选区/待输入格式、精确历史和重开，以及未知源、节、几何和预算保护。既有页面设置单元检查扩展后 3 项、116 个断言通过。既有 Chromium 背景/PNG 流程增加双线控件、原生 val/sz、外线/间隙/内线的 Canvas 与独立两页 PDF 像素、重开控件，保留三步完整字节历史及全部输入、导出、组合、释放和预算检查。旧 PNG 保护夹具改用仍未支持的点线，拒绝与源字节断言保持。公开 api/check/build、定向私有 TS/lint/格式、行数、源码身份、登记、链接及生成接口检查通过。`PageBorder` 新增必填 style 字段，严格宿主示例同步；原单线证据归 `pageBorderCheckpoint`，本次归 `doublePageBorderCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余线型、主题和效果继续保护，P10–P12 继续实施。

P12 直线端点新增两项核心，连同线帽/连接、虚线、外观及对象事务共十一项定向检查通过。覆盖五种轮廓与三档尺寸、水平/垂直及旋转命中、多选/复制、继承覆盖与恢复、精确混合历史和重开，以及未知源、端点锁和输出预算原子保护。既有外观 Chromium 流程保留，并在同文件新增一条短端点流程，检查默认控件、独立 XML、三步精确撤销重做、重开及同一份 Canvas/PDF 的轮廓内外像素。原流程到新增操作前已约十五秒，因此分开运行；每条继续保持 20 秒和零重试。当前安装包 1591 项断言、严格宿主编译、公开构建、接口生成及根/私有静态检查通过；详细证据归私有 `lineEndCheckpoint`。未扩大全量或外部 Office，连接线吸附及目标联动继续实施。

P11 平均值筛选新增两项核心，连同排名/值/自定义筛选、行列变换、自动适配、筛选排序及 SUBTOTAL 共二十四项定向检查通过。覆盖隐藏及重复数值、严格边界、当前公式、多列交集、手动隐藏与缓存、重新应用、结构/复制/改名、精确混合历史和重开，以及空样本、导入阈值、未知源、非有限结果及输出预算的原子保护。既有 Chromium 流程新增两个平均值按钮、原生输入后的重新应用、独立 XML/小计、四步精确撤销重做及重开，保留原有排名、结构与 PDF 检查；20 秒与零重试不变。新安装包 1571 项断言、严格宿主编译、公开构建、生成接口及根/私有静态检查通过。未跑全量或外部 Office，日期类动态筛选继续保护；详细证据归私有 `averageFilterCheckpoint`。

P11 筛选内整行/整列插删新增两项核心，连同行列与局部移位、排名/自定义/值筛选、筛选排序、去重及 SUBTOTAL 共二十六项定向检查通过。覆盖范围与条件列、按钮/嵌套排序、隐藏来源、标题与全部数据删除、公式及小计缓存、选择和精确混合历史，以及预算和工作表边缘的原子保护。既有 Chromium 筛选流程扩展默认插删按钮、独立 XML、四步精确撤销重做、重开及一份结构变更后的 PDF，保持 20 秒与零重试。公开构建和当前静态检查通过；TS 合同未变，复用排名批次的 1560 项安装包断言与严格宿主编译。未跑全量或外部 Office，局部单元格移位及未知筛选仍保护。详细证据归私有 `filterAxisCheckpoint`。

P11 数值排名筛选新增两项核心，连同值/自定义筛选、筛选排序及 SUBTOTAL 共十三项定向检查通过。检查数字记录/并列/百分比/空列、公式及手动隐藏、多列交集、缓存、导入阈值、工作表复制/改名、结构保护、精确混合历史、重开及非法源/预算原子拒绝。既有 Chromium 流程扩展排名面板、项数/百分比切换、原生输入后的重新应用、独立 XML/可见行与小计、精确撤销重做和重开；原有两份值/自定义筛选 PDF 保留，不为未改的打印隐藏路径追加输出。新安装包 1560 项断言及排名类型的严格宿主编译、公开构建、生成接口和根/私有静态检查通过。保持 20 秒与零重试，不扩大全量或外部 Office；详细证据归私有 `rankFilterCheckpoint`。

P10 页面背景新增一项核心，连同页面几何及分页缓存共五项定向检查通过；受影响 Flow 边界的三项 TS 用例通过。检查源顺序、正文/显式格式与单元格底色保留、自动文字对比、待输入格式、精确历史、重开、参数/不透明源/预算原子保护，以及跨页缓存换色和恢复白页。单条 Chromium 流程检查默认面板、原生文字、过期草稿、独立 XML/未改部件、三项混合历史、重开及同一份两页 PDF 的背景像素和文字。当前安装包、严格宿主、公开构建、生成接口和根/私有静态检查通过；私有 `docxBackgroundCheckpoint` 保留详细证据。保持 20 秒与零重试，不扩大全量或外部 Office。

P12 五种常用多边形新增一项核心，连同预设几何、数值调节及对象事务共八项定向检查通过。覆盖独立轮廓与文字矩形、导入/插入、参数边界及未知公式保护、旋转命中、复制、精确历史和重开。既有 Chromium 数值调节流程扩展到五种多边形及三种参数，检查默认面板插入、原生文字、独立 XML、整段混合撤销重做、重开及同一份 Canvas/PDF 的轮廓内外像素。新安装包 1525 项断言、包含五种类型的严格宿主编译、公开构建、生成接口与根/私有静态检查通过。保持 20 秒、零重试，不扩大全量或外部 Office；详细证据归私有 `polygonCheckpoint`。

测试服务于功能开发。当前用真实 DOCX/XLSX/PPTX/PDF 完成打开、编辑、保存和重开，以可操作入口和输出证明交付。

用例围绕用户功能链组织：打开 → 选择/编辑 → 撤销/重做 → 保存/重开 → 导出。断言检查用户可观察的结果，并覆盖文档完整性、安全、恢复和无障碍风险。局部回归优先补入已有功能用例。

文案、标签、界面配色、纯样式、文档和机械重命名直接审阅，按需查看页面。仅当它们改变行为、文档保真或无障碍时增加自动化检查。新增断言须能发现具体功能退化；不为每次修改建立独立用例或快照，也不把措辞、文件清单和内部结构锁成产品合同。

## 选择检查

P12 同组再次组合与显式取消组合通过 14 项定向核心。两项新用例检查已知组尺寸、逆序选择与源顺序、成员身份/文字/外观、反射及非等比祖先下三级提升、共享资源、精确历史和重开输入；组合锁、链接、计时引用、跨父组与输出/身份预算保持原子保护。既有组合/缩放组、成员结构、边界和组内文字覆盖共享坐标提升及权限变更。三条 Chromium 流程通过，新流程六次组合/取消组合及撤销重做逐次保持 Canvas 像素，检查原生尺寸、组间注释、部件清单、保存重开/PDF 和继续输入；原多选缩放与缩放组取消组合保留。2629 项安装包断言、严格宿主、公开 api/check/build 和私有静态检查通过；20 秒，零重试。证据归私有 `memberRegroupCheckpoint`。未跑全量或外部 Office；母版/版式直接编辑及完整阶段继续实施。

P12 成员复制/删除/层次/对齐/分布通过 21 项定向核心。四项新增检查覆盖页面增量、子组复制、身份和共享资源、零/单/多成员删除、嵌套提升后的页面姿态、原生已知尺寸、注释、四种层次、页面/活动对象对齐、四分之一 EMU 下零位移精确无操作、等间隔分布及精确源历史；组进入/几何/复制/删除/取消组合锁、被折叠组链接和计时引用、混合父组与输出预算保持原子保护。既有顶层对象/复制/层次/对齐/组合、缩放组、边界和组内文字用例覆盖共享事务风险。两条 Chromium 流程通过，新流程检查同组全选、快捷键/按钮、XML、五步历史、Canvas 恢复、PDF 和保存重开后继续复制；原成员几何流程保留。2629 项安装包断言、严格宿主、公开 api/check/build 和私有静态检查通过；20 秒，零重试。证据归私有 `memberStructureCheckpoint`。未跑全量或外部 Office；组内重新组合/显式取消组合、母版/版式直接编辑和完整阶段继续实施。

P12 组成员外观通过 24 项定向核心，覆盖嵌套反射/缩放组、多选填充/渐变/描边/不透明度、调节值、图片填充及成员图片属性。成员与父组原生框、文字、共享资源、精确历史和重开保持；组进入锁、未知源、继承对象与预算继续保护。五条不同 Chromium 流程通过，新流程检查层次列表/Shift 选择、默认面板、独立 XML、新增一个图片部件、共享旧资源、七步源历史、Canvas 像素、PDF 及重开后输入。旧部件清单辅助函数不适用于图片替换，新流程改查精确新增资源后单独重跑，复用其余四条通过结果。2629 项安装包断言、严格宿主、公开 api/check/build 和私有静态检查通过；20 秒，零重试。证据归私有 `memberAppearanceCheckpoint`；未跑全量或外部 Office。成员结构、母版/版式直接编辑和完整阶段继续实施。

P12 本地父组边界重算通过 26 项定向核心、五条 Chromium 流程和 2629 项安装包断言。覆盖已知数值的旋转/反射/缩放组、嵌套边界、自动文字适配、其他成员页面姿态、非变换源、预览取消、精确历史、重开、缺省 `chOff` 顺序及母版对象部件隔离。组文字、成员几何、顶层多选、缩放组取消组合和主题字体的浏览器流程检查 XML、Canvas、保存重开和 PDF。公开 api/check/build、严格宿主及私有静态检查通过。保留原 20 秒，零重试；证据归私有 `groupBoundsCheckpoint`，替代上一记录中的父组边界限制。提交前只补文档、用例登记和静态审阅，复用通过结果。未跑全量或外部 Office；母版/版式组编辑、成员外观/结构和完整阶段继续实施。

P12 组成员几何新增三项核心，连同组内文字、组合/缩放组、选择、方向、对齐、框适配和表格变换共 21 项定向检查通过。覆盖嵌套反射/缩放、页面增量、局部整数 EMU、重复候选与取消、固定角点、中心保持、同组多选、子组预览/写回、精确历史、重开输入及锁定/预算失败。共享坐标写回变更由上述顶层、取消组合和文字框用例覆盖。四条 Chromium 流程通过，新流程检查键盘/默认控件、真实主体和角点拖动、旋转/翻转、Shift 成员多选、独立 XML、九步源历史、Canvas 初始/重做像素、重开和 PDF；原组内文字/组合输入、顶层多选与缩放组取消组合保持。2629 项新安装包断言、严格宿主、公开 api/check/build 和私有静态检查通过，均保持 20 秒、零重试。证据归私有 `memberGeometryCheckpoint`；未跑全量或外部 Office。父组边界重算、成员外观/结构与完整阶段继续实施。

P12 组内文字新增三项核心，与既有组合、缩放组、框/字符格式、新增页和表格样式共 20 项定向检查通过。两条 Chromium 流程覆盖双击及层次列表入口、原生输入、粗体/自动适配、局部坐标与父组源、精确历史、重开像素与 PDF、原生组合取消及 Shift 切换成员；既有创建/组合/页操作流程保留。新增页回归发现表格样式读取提前枚举候选全包关系，现只读所属关系并在提交时保留全包校验；独立既有核心先复现失败，再通过修复与资源大小写检查。旧页序测试按已交付放映范围合同补查原生属性保持和精确历史，原保护/预算断言保留。公开 api/check/build、2629 项新安装包断言、严格宿主及私有静态检查通过。沿用原 20 秒和既有 60 秒流程，零重试；证据归私有 `groupTextCheckpoint`。未跑全量或外部 Office；成员变换与完整阶段继续实施。

P11 填充色、无填充和字体色排序新增两项核心。相关排序、筛选、结构、表操作及条件样式共覆盖五十三项定向检查；修正颜色样例并完成同轴条件与样式引用检查后，最终直接相关十一项通过，其余四十二项结果复用。覆盖条件颜色冻结、后续规则重新求色、空内容格样式、隐藏位置、多颜色/值层次、差异样式批量去重、引用完整性、首次部件创建、便笺/链接/公式缓存、精确历史和重开，以及非法参数、富文本文字色及预算的原子保护。同一条 Chromium 流程检查默认填充色置顶和字体色置底、独立样式/排序 XML 与两步精确撤销；原有自定义列表、原生输入、筛选、去重、分列、重开及 PDF 检查保留，20 秒、零重试不变。公开构建、接口生成、根/私有静态检查及安装包的 1520 项断言和严格宿主编译通过，新增十三项颜色输入边界。详细证据归私有 `sortColorCheckpoint`，旧排序批次保留归档。未跑全量或外部 Office 验收，富文本文字色、图标及表格内排序继续实施，P10/P11/P12 保持部分完成。

P11 分列的列类型新增两项核心，与已有分列、CSV/TSV 和输入验证共十二项定向检查通过。覆盖文字/常规、三种日期顺序、1900/1904 日历、公式显式选择、跳过列、转换预览、日期样式及首次样式部件、验证与输出预算的原子保护和精确历史。同一条 Chromium 流程检查默认面板转换、覆盖确认、独立数值/公式缓存 XML、撤销重做、保存重开及宽列日期 PDF；保持 20 秒、零重试。公开构建、接口生成、私有静态检查及安装包的 1491 项断言和严格宿主编译通过。根静态检查由提交钩子执行。详细证据归私有 `textColumnTypesCheckpoint`；未跑全量或外部 Office 验收，地区化转换及其余阶段范围继续实施，P10/P11/P12 保持部分完成。

P11 固定宽度分列新增一项核心，与已有分隔符、CSV/TSV 及输入验证共十项定向检查通过。覆盖 Unicode 列宽、代理对、组合字素、emoji/变体/ZWJ、忽略字符、尾部空格与外层引号、短行空字段、非法位置/输出预算、覆盖确认、格式/便笺/隐藏行、精确历史及重开。同一条排序 Chromium 流程新增方式切换、无效位置禁用、位置改变后预览失效、覆盖勾选、独立 XML、撤销重做及固定分列重开；复用最后一份 PDF 检查两种分列文字结果，20 秒、零重试不变。公开构建、接口生成、根/私有静态检查和安装包的 1480 项断言及严格宿主编译通过，新增十八项固定模式边界。详细证据归私有 `textColumnsFixedCheckpoint`；未跑全量或外部 Office 验收，列转换及其余阶段范围继续实施，P10/P11/P12 保持部分完成。

P11 文本分列新增两项核心，与已有 CSV/TSV 及输入验证共九项定向检查通过。覆盖四种分隔符、引号/转义、换行和空字段、最大列数补空、隐藏行、前导零与文字公式、目标覆盖确认、格式/链接/便笺保持、依赖缓存、无操作、精确历史、重开及旧预览/边界/保护/验证失败。延伸同一条排序 Chromium 流程，检查原生输入、只读预览、覆盖勾选、独立 XML、两步精确历史、重开和文字结果 PDF；保留既有排序/筛选/去重与搜索检查，20 秒、零重试不变。公开构建、接口生成、根/私有静态检查及安装包的 1462 项断言和严格宿主编译通过，新增三十项输入/预览边界。详细证据归私有 `textColumnsCheckpoint`；未跑全量或外部 Office 验收，固定宽度、列转换及其余阶段范围继续实施，P10/P11/P12 保持部分完成。

P12 四种页导航动作新增两项核心，与已有对象及文字链接共八项定向检查通过。覆盖当前页序、隐藏页、首尾停留、页重排/复制/删除、关系不新增、提示和输入继承、精确历史、重开，以及混合/旧修订/活动候选和未知动作保护。同一条链接 Chromium 流程覆盖默认面板设置四种动作、显式导航不改源、一次精确撤销重做、文字动作与重开，并检查移动到既有搜索模块的查找/定位/替换及撤销；保留原有原生输入、链接源和 PDF 检查，20 秒、零重试不变。公开构建、接口生成、根/私有静态检查及安装包的 1432 项断言和严格宿主编译通过。详细证据归私有 `navigationLinksCheckpoint`；未跑全量、放映或外部 Office 验收，P10/P11/P12 保持部分完成。

P11 筛选区域去重新增一项核心，与已有去重、排序、便笺、值/自定义筛选和 SUBTOTAL 共十九项定向检查通过。覆盖筛选隐藏记录参与、搬移后的公式条件、手动隐藏来源、SUBTOTAL 两组缓存、单步精确历史、重开清除条件，以及未知筛选和普通排序的原子保护。同一条 Chromium 排序流程新增默认筛选后预览/去重、独立 XML、行可见性、撤销重做、重开清除和筛选后 PDF 检查；保持 20 秒、零重试。公开构建、接口生成、根/私有静态检查通过；TS 合同未变，复用上一批安装包边界结果。详细证据归私有 `duplicatesFilterCheckpoint`。未跑全量或外部 Office 验收，表格等去重组合继续实施，P10/P11/P12 保持部分完成。

P11 删除重复行新增两项核心，与既有行/列排序及便笺操作共九项定向检查通过。覆盖标题/比较列、格式化值、数字与文字、大小写/空格、隐藏行、富文本/格式、相对公式及依赖缓存、链接/便笺、空尾部无操作、精确历史、重开、旧预览及资源保护。延伸同一条排序 Chromium 流程，检查原生输入、默认预览不改源、明确提交、独立 XML、两步精确历史、重开查找替换和去重后的 PDF；保持 20 秒、零重试。公开构建、接口生成、静态检查、安装包的 1422 项断言及严格宿主编译通过，新增 31 项预览/命令边界。详细证据归私有 `duplicatesCheckpoint`；未跑全量或外部 Office 验收，P10/P11/P12 保持部分完成。

P10 现代批注新增两项核心，连同既有批注、线程、单词导航及覆盖层共十二项定向检查通过。覆盖大小写身份映射、UTC 优先显示及原日期保留、已知作者扩展、follow-up 标志、新条目及首次线程、选择性/级联删除、六步精确历史与重开输入，以及异常映射、外部/共享关系和输出预算的原子保护。同一条 Chromium 流程导入独立构造的现代元数据，检查默认面板修改、UTC 时间、回复、新身份、删除及三步精确撤销重做，保持 20 秒、零重试。公开构建、接口生成和静态检查通过；公开 TS 合同未变，复用上一批安装包边界检查。详细证据归私有 `docxModernCheckpoint`；未跑全量或外部 Office 验收，P10/P11/P12 保持部分完成。

P10 单词批注和顺序导航新增两项核心，连同既有批注、线程及组合共十二项定向检查通过。覆盖跨格式/链接取词、UTF-16 字素边界、空白点锚点、光标精确历史，以及正文/单元格顺序、跳过回复/解决/保护条目、循环和无可用项时不变。同一条 Chromium 流程检查原生光标创建、上一条/下一条、源和历史不变及撤销恢复光标；保持 20 秒、零重试。公开构建、接口生成、根/私有静态检查、安装包的 1426 项断言及严格宿主编译通过。详细证据归私有 `docxSelectionCheckpoint`；未跑全量或外部 Office 验收，P10/P11/P12 保持部分完成。

P10 批注覆盖层新增两项核心，与已有批注/线程及组合共十二项定向检查通过。覆盖跨页范围、点锚点、回复去重、解决状态、普通精确行高单元格裁剪、组合候选、未知/缺失批注正文、旧布局和源/选择/历史不变；正文 R0 图元与加入批注前独立基线相同。延伸同一条 Chromium 流程，检查真实覆盖层像素、150% 缩放下点击与面板定位、原生焦点、拖动和 Shift 扩选、解决隐藏/重开恢复，保留十一项精确历史、重开与静态 PDF。20 秒、零重试不变。公开构建、接口生成及静态检查通过；三个既有 Flow/R0/布局边界单元检查通过，安装公开包的 1417 项断言及严格宿主编译通过，包含新几何的页面/行索引、有限数、页面裁剪与数量边界。详细证据归私有 `docxOverlayCheckpoint`；未跑全量或外部 Office 验收，P10/P11/P12 保持部分完成。

P10 批注线程新增两项核心，连同已有批注及书签共九项定向检查通过。覆盖首次回复/解决的段落身份、commentsExtended 及元数据事务、作者/日期、正文修改后父关系、原生范围维护、单条/级联删除、八项精确历史、重开，以及导入的大小写身份、末段映射、继承命名空间、源注释、异常父关系和输出保护。延伸同一条 Chromium 流程，独立检查父关系和解决标志，增加回复增改删、解决/重开、十一项精确历史及含回复重开；保持 20 秒、零重试。公开构建、接口生成、静态检查、安装公开包的 1405 项断言及严格宿主编译通过；新边界覆盖回复命令、必需 parent/done、悬空/嵌套/循环父关系和状态一致性。详细证据归私有 `docxThreadsCheckpoint`。未跑全量；现代批注兼容和画布标记继续实施。

P10 传统批注新增四项核心，与书签、导入/目标链接、组合、查找和表格输入共二十五项定向检查通过；随后扩展导入用例的链接包裹/移除，以及扩展线程保护，仅重跑四项新用例。覆盖首次部件/关系/类型、范围与点锚点、导入富文本/空正文、作者/日期/源属性、正文输入/拆段/跨段删除、书签共存、精确混合历史和旧修订/输出保护。单条 Chromium 流程检查显式宿主作者、原生与批注草稿、独立 XML、五步精确历史、重开继续输入及静态 PDF 排除批注，保持 20 秒、零重试。安装公开包的 1391 项断言及严格宿主编译通过，新增命令和列表边界。详细证据归私有 `docxCommentsCheckpoint`；回复/解决及扩展线程继续实施，P10/P11/P12 保持部分完成。

P11 便笺网格新增三项核心，连同便笺/合并、冻结、视图/公式视图及打印设置，共十八项定向检查通过。覆盖空格与远端便笺、滚动范围、隐藏行列、四窗格合并片段、RTL 角标镜像、未知 VML 的既有诊断和源不变；打印不包含角标，也不因远端便笺扩大默认区域。延伸已有单条 Chromium 流程，独立检查橙色像素、悬停与选中提示、Escape 隐藏、网格/原生输入的便笺描述、悬停不改变选择或保存字节，保留全部既有历史、重开与静态 PDF。20 秒、零重试不变。公开构建、接口生成、根/私有静态检查，以及重新安装公开包的 1361 项断言和严格宿主编译通过；新增可见便笺的地址/文字/几何和数量/总文字预算边界，维护新增内部模块的构建与包清单。详细证据归私有 `noteGridCheckpoint`；线程批注、便笺外观及其余操作继续实施，P10/P11/P12 保持部分完成。

P11 便笺合并新增三项核心，连同便笺、结构/数据操作、合并边框和合并填充，共二十项定向检查通过。覆盖单条便笺移到左上角、源顺序选择、额外便笺的显式丢弃确认、保留正文/作者/shape 身份/框外观及范围外源、合并内编辑、取消合并、精确历史与重开，以及未知 VML、坐标注释、旧修订和输出预算的原子保护。延伸已有单条 Chromium 流程，在非锚点值全空而有两条便笺时检查默认确认、XML/VML、合并/取消合并、两步精确历史、保存重开及静态 PDF。20 秒、零重试不变。公开构建、接口生成、根/私有静态检查，以及重新安装公开包的 1354 项断言和严格宿主编译通过，包含新增 `discardedNotes` 的宿主类型读取。详细证据归私有 `noteMergeCheckpoint`；便笺网格标记/弹框、外观和线程批注继续实施，P10/P11/P12 保持部分完成。

P11 便笺数据操作新增四项核心，连同便笺、结构引用、排序、四向填充、自动序列、收缩和格式清除，共二十六项定向检查通过。覆盖行/列排序中的空格便笺、标题/隐藏轴及范围外源、填充保留原便笺、三种清除与空格便笺删除、精确历史、重开和未知 VML 的原子保护。延伸已有单条 Chromium 流程，新增排序、填充、内容清除与全部清除，独立检查 XML/VML、四步精确历史、重开及静态 PDF；保持 20 秒、零重试。公开构建、接口生成和根/私有静态检查通过。API/TS 未改，重打当前公开包，复用既有 1354 项边界断言和严格宿主结果。详细证据归私有 `noteOperationsCheckpoint`；合并归属、网格标记和线程批注继续实施，P10/P11/P12 保持部分完成。

P11 便笺结构引用新增三项核心，连同既有便笺、行列/单元格移位、规则和超链接，共十七项定向检查通过。覆盖八种插删/移位、范围外便笺保持、空格便笺越界保护、删除全部所属格、正文/作者/guid/shapeId/Anchor/外观和未变轴原始数值保持、精确混合历史与重开，以及不可改的 VML 文字和输出预算原子拒绝。延伸已有单条 Chromium 流程，保留原六步历史，重开后再检查插行、单元格下移/删除、独立 XML/VML、范围外副本、三步精确历史及静态 PDF。保持 20 秒、零重试；不扩大全量。API/TS 未改，重打当前公开包，复用前次 1354 项边界断言及严格宿主结果。详细证据归私有 `noteAxesCheckpoint`；排序/填充/合并等其余便笺变换继续实施。

P11 传统便笺新增三项核心，连同超链接、表复制/删除和打印设置，共十三项定向检查通过；后续源保护及缺失 VML 兼容补充仅重跑三项新用例。覆盖首次 comments/VML/关系创建、作者复用、字面 SpreadsheetML 转义、首个 run 格式/命名空间、源外围注释与 VML 保持、comments-only 补框及未解析 shapeId 保护、副本独立编辑、独占删除、稳定 ZIP 部件顺序、精确混合历史与重开，以及未知文字/VML/控件、不匹配锚点、共享部件、旧修订和输出预算原子拒绝。单条 Chromium 流程通过，检查宿主作者、同格便笺/原生草稿、独立 XML/VML 和其他部件、复制后编辑与删除、六步精确历史、重开及静态 PDF 排除便笺。1354 项安装包断言、严格宿主、公开构建、接口生成及根/私有静态检查通过。保持 20 秒、零重试，不扩大全量或外部 Office 验收。详细证据归私有 `xlsxNotesCheckpoint`；线程批注、网格标记和引用变换继续实施，P10/P11/P12 保持部分完成。

P12 本地批注新增三项核心，连同普通备注和页复制/删除回归，共十四项通过；修复回复父标识的 JSON 序列化后，仅重跑三项新用例。覆盖首次部件/作者/关系创建、多作者回复、源日期/位置/presence 扩展保持、滞后 lastIdx 分配、回复复制重映射、删除独占部件、精确混合历史与重开，以及非法文字/作者/日期、未知源、悬空回复、共享部件、旧修订和输出预算原子保护。单条 Chromium 流程通过，检查未提供作者时的创建保护、宿主作者、原生输入及批注草稿、默认面板增改删/回复、独立 XML/其他部件、六步精确历史、副本独立编辑、重开及静态 PDF 排除批注。1322 项安装包断言及严格宿主编译通过。保持 20 秒、零重试；不扩大全量或外部 Office 验收。详细证据归私有 `commentsCheckpoint`；P10/P11/P12 保持部分完成。

P11 普通链接新增三项核心，连同行列/单元格移位、表复制/删除、名称和打印设置回归，共十九项通过。最后仅重跑三项新用例，检查局部矩形拆分、提示/display/命名空间/源值公式保持、共享及首次关系部件、合并区域边界、内部矩形和作用域名称、改名/插行/复制/删除后的目标、名称删除及别名链、外部 location 保持、精确历史与重开，以及协议、重叠/未知源、锁、旧修订/选区、输出预算和未知链接打印保护。单条 Chromium 流程检查原生草稿和地址草稿、独立 XML/关系/其他部件、零次自动请求与显式无 opener 窗口、混合移除、内部改名/定位、六步精确历史及重开/PDF 文字。1283 项安装包断言及严格宿主、公开构建、生成接口、根/私有静态与本地链接检查通过。保持 20 秒、零重试，不扩大全量、外部 Office 或 PDF 链接注释。详细证据归私有 `xlsxHyperlinkCheckpoint`；P10/P11/P12 继续保持部分完成。

P10 普通书签新增三项核心，连同导入/目标链接、概览、组合、查找替换及表格编辑，共二十四项通过。最后仅重跑三项新用例，检查范围/空光标、正文/单元格/链接内标记、跨段和交叠范围、删除内容时收缩、标记顺序、行删除保护、大小写名称查找、anchor 改名/删除同步、内外链互换、局部命名空间/直接格式、精确历史与重开，以及重复/未知标记、字段、候选、旧修订及输出预算的原子失败。书签和既有外链两条 Chromium 流程通过；最终只重跑书签流程，检查默认面板、重复创建后继续编辑、原生输入、核心定位、独立 XML/其他部件、五步精确历史及重开/PDF 文字。1241 项安装包断言、严格宿主、公开构建、接口生成及根/私有静态检查通过。保持 20 秒和零重试，不扩大全量、外部 Office 或 PDF 交互注释。详细证据归私有 `bookmarkCheckpoint`；复杂引用仍保护，P10/P11/P12 保持部分完成。

P10 外链目标新增三项核心，连同导入链接文字、字符/段落格式及导航回归，共十六项通过。最后仅重跑三项新用例，检查跨样式/段落的部分范围、光标完整链接与显示文字、关系复用及首次创建、连续输入、混合移除、原字符格式/提示/注释/局部命名空间、前缀冲突、精确历史和重开，以及协议、未知源、旧修订、候选与预算原子失败。目标编辑及既有导入输入两条 Chromium 流程有通过结果；最终只重跑目标流程，检查默认面板地址草稿、非法协议后继续编辑和精确保存、独立 XML/其他部件、零次自动请求、显式新窗口无 opener、五步精确历史、空光标显示文字、重开输入及静态 PDF 文字。1221 项安装包断言、严格宿主、公开构建、生成接口和根/私有静态检查通过。保持 20 秒、零重试，不扩大全量、外部 Office 或 PDF 交互注释。详细证据归私有 `hyperlinkTargetCheckpoint`。

P10 导入链接文字新增三项核心，连同范围输入、内联控制、格式、组合、查找替换、图片插入及导航回归，共三十二项有通过结果。最终只重跑三项新用例与导航一项。检查源顺序、直接格式、外链/anchor 元数据、关系和未改部件、范围复制/替换、三/四步精确历史、空 run、单元格、组合取消/提交、拆段/合段命名空间与继承，以及未知源、链接内插图和重复链接帧预算原子保护。单条 Chromium 流程检查真实输入、默认格式按钮、拆段合段、四步精确历史、独立 XML/其他部件、重开输入及 PDF 文字，确认外链零请求；并修复非空选区按右箭头多走一字。公开构建、接口生成、根/私有静态检查通过；API 与 TS 未改，当前产物重打包，复用前次 1192 项安装包断言及严格宿主结果。保持 20 秒和零重试，不扩大全量、外部 Office 或 PDF 注释。详细证据归私有 `hyperlinkInputCheckpoint`。

P12 文字点击链接新增三项核心，连同对象链接、字符/段落格式及复制回归，共十二项有通过结果。最终只重跑三项新用例，检查跨样式/软换行/段落、组合字符、混合查询、光标完整链接及空格式 run、空段落和后续输入、段落末尾清除、提示/悬停/直接格式与对象链接保留、五步精确历史及重开，以及未知源、协议、候选和源/输出预算原子失败。文字和原对象链接两条 Chromium 流程通过，检查默认面板草稿、独立 XML/关系/未改部件、混合移除、内部跳页、精确历史、重开输入及静态 PDF 文字。1192 项安装包断言及新增文字查询的严格宿主编译、公开构建、生成接口和静态检查通过。保持 20 秒和零重试，不扩大全量、外部 Office 或 PDF 链接注释。详细证据归私有 `textHyperlinkCheckpoint`。

P12 对象点击链接新增三项核心，复用对象增删/复制、页操作/复制及组合的十五项回归，共十八项有通过结果。检查外部/内部目标、共用关系、提示/悬停/注释/文字/几何、精确混合历史、保存重开、页面移动/复制/删除、图片资源、组链接及取消组合保护，以及协议/未知动作/锁/活动候选和输出预算的原子失败。最后只重跑三项新用例，既有结果复用。单条 Chromium 流程检查默认面板、原生输入期间保留链接草稿、独立 XML/其他部件、精确历史、零次自动请求、显式打开且新窗口无 opener、内部跳页、移除/撤销、重开输入及静态 PDF 文字。1192 项安装包断言、严格宿主、公开构建、生成接口及静态检查通过。保持 20 秒和零重试，不扩大全量、外部 Office 或 PDF 链接注释。详细证据归私有 `objectHyperlinkCheckpoint`。

P11 未支持公式的局部编辑新增三项核心，连同逻辑、数值、名称、SUBTOTAL、CSV、统计、条件格式、验证和筛选回归，共三十项通过。检查六种已核实函数、跨表下游/共享源及缓存保持、无关值/格式/尺寸/表顺序、精确历史与重开，以及参数/源码/名称/结构、稀疏新增输入、动态嵌套、可见性、规则读取和预算原子保护。单条 Chromium 流程检查默认原因提示、原生草稿、无关重算、拒绝后草稿恢复、独立 XML/其他部件、精确历史、重开输入及整表 PDF 拒绝和独立区域输出。公开构建、1169 项安装包断言及严格宿主通过。保持 20 秒和零重试，不扩大全量或外部 Office。详细证据归私有 `partialCalculationCheckpoint`。

P10 内置样式新增两项核心，连同原样式重置/修改和主题颜色回归共十四项通过。覆盖七个预设、普通/复杂文字格式、文档默认基础、名称/别名/链接/正文直接覆盖、未改部件、无主题 RGB、有主题关联及后续主题更新、选择与后续输入格式、无操作、精确历史和重开，以及未知属性/主题色和输出预算原子失败。Chromium 单条流程检查无间距、题注和引用字符样式的默认重置按钮、原生草稿、独立源 XML、两项精确历史、重开输入/9 pt 查询及 PDF。公开构建、生成接口及根/私有静态检查通过；公开 API 与 TS 未改，当前产物重新打包，复用此前 1167 项安装包断言及严格宿主结果。保持 20 秒和零重试，不扩大全量或外部 Office。详细证据归私有 `builtinPresetCheckpoint`。

P12 编号标点新增一项核心，连同原列表、标记样式和段落回归共七项通过。检查十六种完整类型、数字/字母重复/罗马数字的独立标记预期、源与非目标部件、公共标记布局、无操作、精确撤销及保存重开后的原生续号。既有 Chromium 列表流程改用左右括号编号，检查原生文字、局部项目符号/级别、独立 XML、混合精确历史、重开 Enter 续号及 PDF 的 `(z)/(aa)/(bb)/(cc)`。当前安装包新增十一种格式及非法别名/边界检查，共 1167 项断言和严格宿主通过；公开构建、生成接口、根静态与私有 TS/格式检查通过。仅跑该列表浏览器流程，复用其他格式既有结果，不扩大全量。详细证据归私有 `numberSchemeCheckpoint`。

P11 合并填充新增三项核心，连同四向、数字/日期序列、向内清除、相邻延伸和本地化循环共二十二项通过。覆盖四向平铺、尾块裁短、各格格式和相对公式、依赖重算、仅几何事务、混合精确历史、重开、单合并锚点预览、日期跨度，以及切开/尺寸冲突、未知元数据、合并计数和输出预算原子失败。单条 Chromium 流程检查原生草稿、独立合并/公式/格式/依赖 XML、两项精确历史、键盘 Ctrl、双击相邻延伸、重开编辑及 PDF。实际定位并修正合并锚点的填充柄隐藏问题；PDF 使用可完整容纳合并格的页面，跨页保护保持。公开构建、生成接口、根静态检查、私有 TS/格式检查、1154 项新安装包断言及严格宿主通过。保持 20 秒和零重试，不扩大全量或外部 Office。详细证据归私有 `mergedFillCheckpoint`。

P11 本地化循环新增三项核心，连同自动/文本/自动日期及 Ctrl 回归共十五项通过。覆盖中英文星期/月名、全称/缩写、跨周期步长、四向反推、大小写和 `May` 消歧、空白/混合分组、公式缓存与依赖、格式循环、精确混合历史、重开编辑，以及显式文本/复制保持和预算/后组溢出原子失败。Chromium 单条流程检查原生草稿后自动填充、独立文字/公式/格式 XML、两项精确历史、保存重开、填充柄方向键与 Ctrl 复制及中文 PDF。公开 API 与 TS 边界未改，复用此前 1154 项安装包断言及严格宿主结果；重新构建并打包当前产物，不重复安装包检查。生成接口、根静态检查与私有 TS/格式检查通过。保持 20 秒、零重试，不扩大全量或外部 Office。详细证据归私有 `cycleSeriesCheckpoint`。

P10 主题字体新增三项核心，连同主题颜色、样式修改、字符样式和首次样式部件共十六项通过。最终仅重跑三项新用例，覆盖标题/正文同时修改、普通单元格与编号继承、直接字体与源元数据、真实字体宽度、四字体槽与东亚/复杂文字提示、独立复杂文字粗体/字号、空段落、字素及混合查询/光标、原生输入与精确历史、首次主题元数据，以及缺字体、源保护、活动组合和预算原子失败。字体与既有颜色两条 Chromium 流程有通过结果；最终字体流程单独重跑，检查草稿、两字体源 XML、实际宽度及软换行、精确混合历史、缺字体恢复、重开输入和 PDF 逐行一致。1154 项安装包断言、严格宿主、构建、生成接口及静态检查通过。保持 20 秒、零重试，复用既有相关结果，不扩大全量、外部 Office 或 PDF 栅格。详细证据归私有 `docxThemeFontCheckpoint`。

P10 六槽主题字体新增两项核心，连同既有字体、颜色和页眉页脚共十一项通过。检查 Latin/EA/CS 批量修改、正文及页边中阿字体排版、直接覆盖、空槽回退、未改部件、精确历史、重开，以及重复/非法槽、局部源保护和仅页边受影响的缺字体原子拒绝。Chromium 新流程通过，覆盖六槽默认面板、原生草稿、独立源 XML、混合历史、空槽回退、保护槽禁用后继续修改其他槽、重开和中文 PDF；同轮既有 Latin 字体流程也通过。1838 项安装包断言和严格宿主通过，生成接口、公开构建和静态检查通过。保持 20 秒和零重试，不扩大全量、外部 Office 或语言矩阵。详细证据归私有 `docxThemeSlotsCheckpoint`。

P10 主题颜色新增三项核心，连同样式修改、字符样式及首次样式部件十项回归共十三项通过。最终仅重跑三项新用例，覆盖正文/单元格样式继承、编号标记、缓存颜色与 HSL 明暗、颜色映射、直接覆盖清除主题属性、系统颜色无操作、首次主题元数据、精确混合历史、重开输入，以及源扩展、非法映射、主题锁、活动组合和预算原子失败。Chromium 单条流程通过，检查面板草稿、实际 Canvas 颜色、独立主题/关系/内容类型 XML、文字与主题两项精确历史、无操作后继续编辑、重开及 PDF。1132 项安装包断言和严格宿主编译通过，公开构建、生成接口及静态检查通过。保持 20 秒和零重试，不扩大全量、外部 Office 或 PDF 栅格验收。详细证据归私有 `docxThemeColorCheckpoint`。

P12 主题字体新增三项核心，连同主题颜色、文本框和适配回归共九项通过。检查跨主题混合值、粗斜体字体预检、本地/继承/组内/零高度框适配、直接字体与未改部件、两步精确历史及重开输入、EA/CS/补充脚本回退、真实中阿字体排版、元数据及扩展顺序、缺字体/候选/旧修订/输出预算和源保护。补充父组缩放及扩展顺序后仅重跑三项新用例，六项既有结果复用。Chromium 字体与颜色两条流程通过；字体检查面板草稿、自动尺寸与独立源 XML、未使用主题保持、混合历史、动态类别新增/撤销后继续操作、缺字体恢复、重开及 PDF。最终字体流程单独重跑通过。1104 项安装包断言及严格宿主通过，保持 20 秒、零重试，不扩大全量和 PDF 栅格验收。

P12 主题颜色用两项新增核心与十项背景/版式/尺寸回归检查跨主题同步、直接覆盖、源字节/身份/几何、文字与主题的两步精确历史、撤销后的派生颜色、重开输入、链接色、候选/旧修订/输出预算及未知色项原子保护。补充系统颜色和带符号的伪 RGB 后只重跑两项新用例。Chromium 单条流程检查原生草稿期间保留面板颜色、应用后 Canvas 颜色、独立主题/直接对象 XML、混合精确历史、无操作、另一页直接背景、重开继续输入与 PDF。1072 项安装包断言及严格宿主通过，新模块进入现有构建与精确包清单。保持 20 秒、零重试，不扩大全量或外部 Office 检查。

P11 Ctrl 填充新增两项核心，连同预览、自动数字/文本/日期共十四项通过；检查四向循环值/格式/公式、精确历史、保存重开、日期与字面文本及预算原子失败。四条填充柄 Chromium 流程通过，包括拖动中切换 Ctrl、释放状态、重开及 Ctrl+方向键。重新打包后 1034 项断言及严格宿主编译通过；不扩大全量检查。

P11 填充柄双击新增三项核心，连同原预览和 Ctrl 回归共七项通过。覆盖左右/对角连续区域、断行、部分目标与目标阻挡、筛选边界、隐藏行、样式空格、合并保护、工作表边缘、4096 格原子拒绝、公式/格式/精确历史及重开编辑。单条 Chromium 流程检查原生草稿后双击、立即保存、独立 XML 值/样式与向导内容、两项精确历史、Enter 实际延伸、Enter/Space 无操作、重开输入及 PDF。重新打包的 1041 项断言和严格宿主通过。既有四条拖动/缩减/Ctrl 流程的路径未改，复用上一轮结果；不扩大全量测试。

P11 填充柄向内缩减新增三项核心，连同预览、原四向填充及自动序列共十项通过。检查纵横尾带/整块内容清空、格式和尺寸保持、共享公式/跨表依赖、精确混合历史、重开、空范围仅改选区、非法/受保护/预算/旧修订原子失败，以及 LTR/RTL/冻结区域的半格吸附与预览无写入。清除循环改为最多 4096 格后仅重跑三项新用例，其余结果复用。Chromium 新流程检查原生草稿、清除区域预览、取消、纵横缩减、清空整块、独立源/格式/依赖缓存、两项精确历史、重开后输入及 PDF 保留/删除文字；已有两条填充柄流程保留向外、键盘、RTL/冻结、边缘滚动及失败恢复检查。保持 20 秒及零重试；公开包边界、严格宿主、构建、生成接口及静态检查同步更新，不扩大全量、外部 Office 或 PDF 栅格。

P11 自动日期新增三项核心，连同自动/文本/显式日期共十三项通过。检查 1900/1904、四向天/月/年、日期时间差、单时间逐小时、普通数字与日期分组、规则/不规则空白、格式循环、依赖重算、无操作、精确历史和重开。补充日期/日期时间混合、午夜反向及后组越界回滚后只重跑三项新用例通过，其余十项复用。三条 Chromium 流程检查自动日期、普通自动及显式日期；新流程检查原生草稿、独立值/公式/样式/依赖缓存与其他部件、两步精确历史、填充柄延伸、重开输入和 PDF，保持 20 秒和零重试。构建、生成接口及根/私有静态检查通过。未改公开 API，复用既有安装包边界和严格宿主结果；未重复打包、跑全量或外部 Office。详细证据归私有 calendarSeriesCheckpoint，合同归[数字序列](formats.md#数字序列)。

P10 单元格内分页符用 `docx-cell-page-break.spec.ts` 检查导入标记、原生输入、Ctrl+Enter 与默认按钮、独立源 XML、非目标部件、三项精确历史、保存重开后删除/继续输入、稳定行续页与 PDF 的完整文字及页数；同一流程再确认正文分页仍换页。核心沿已有六项行内控制检查补单元格编辑/查找替换/重开；两项新布局检查零宽光标、连贯文字度量、正文/格内缓存隔离、自动宽度、连续空标记及纵向合并续页的完整几何，复用十二项行拆分/合并/缓存/自动宽度/双向回归，并运行两项已有双向控制与独立原生导航向量。零宽字符经替换失去 Unicode 信息时按原始 cluster 识别；PDF 同时排除不显示的字形映射和 ActualText 控制。复用已有行续页 Chromium 流程；无公开 API 变化，沿用 988 项包边界与严格宿主结果，不重复打包、全量或 PDF 栅格验收。

P10 纵向合并续排新增三项布局，连同普通行、合并几何、表头和标题/表格联动共十三项通过。检查长合并格与相邻行、完整文字/源归属、逐页边框/底色/选择、冷暖缓存与增删文字后的重排、表头、首个文字片段对齐、精确结束行及超高文字裁剪、不可放行与页数预算。补强页边框闭合断言后仅重跑三项新用例通过，其余十项复用。三条 Chromium 流程检查原生输入、拆分开关、两步精确历史、独立合并 XML/其他部件、重开后续页点击和输入、PDF 文字不重不漏及重复表头；另覆盖普通行及标题/表格回归，保持 20 秒和零重试。构建、根/私有静态检查、生成接口及受影响链接通过。未改公开 API，复用此前安装包边界与严格宿主结果；未重复打包、跑全量或外部 Office。详细证据归私有 tableMergeContinuationCheckpoint，合同归[表格行跨页](formats.md#表格行跨页)。

P12 段落方向新增两项核心及一项基础方向缓存检查，连同原段落/清除/两端对齐和缓存回归共十项通过。检查继承、显式 LTR/RTL、阿拉伯文/数字/拉丁文混排、左右对齐镜像、物理对齐、缩进、局部/多框混合查询、无操作、精确混合历史、清除恢复和重开，非法源诊断与字体/修订失败保持文档。新 Chromium 流程检查草稿、默认复选框、独立 XML/非目标部件、实际字形位置、混合状态、历史、重开输入和 PDF；同构建的两条文字格式流程通过，修正新用例的按钮名称和异步复选操作后仅重跑新流程。保持 20 秒和零重试。976 项安装包断言、严格宿主编译、构建及根/私有静态检查通过。未跑全量或外部 Office；详细证据归私有 paragraphDirectionCheckpoint，范围归[PPTX](formats.md#pptx)。

P11 填充柄新增两项核心，连同自动序列及冻结回归共七项通过。两条 Chromium 流程检查草稿后恢复源范围、预览不写源、释放后保存顺序、无移动、精确混合历史、取消与拒绝后恢复、重开输入，以及缩放/冻结/RTL、方向键、边缘滚动和暂停取消；含超链接的夹具检查 PDF 拒绝保护，另复用本轮自动序列流程的可导出 PDF 检查。三条流程保持 20 秒和零重试。971 项安装包断言与严格宿主编译通过，覆盖预览参数与返回值边界。保存提示引起界面重排时，释放坐标在入队前固定。未跑全量或外部 Office；详细证据归私有 fillHandleCheckpoint，范围归[填充柄](formats.md#填充柄)。

P11 自动填充新增三项核心，连同文本、数字、日期和四向填充共 17 项通过。检查单格数字复制、小数/有符号趋势、数字/文字分组及空白槽位、四向相对公式/绝对引用/越界引用、对应源格格式、依赖重算、无操作、精确混合历史和重开，溢出整次回滚。补充公式分隔数字/文字组后，只重跑三项自动用例通过，其余 14 项复用。自动与原文本两条共三条 Chromium 流程通过；新流程检查原生草稿、独立数字/公式/缓存/样式与非目标部件、两步历史、重开输入和 PDF，保持 20 秒和零重试。946 项安装包断言、严格宿主编译、公开构建和根/私有静态检查通过。该轮尚未接通填充柄，后续结果见上段。未跑全量或外部 Office；详细证据归私有 autoSeriesCheckpoint，合同归[数字序列](formats.md#数字序列)。

P11 文本序列四项核心，连同数字、日期和四向填充共 14 项通过。检查混合前缀独立分组、重复前缀分隔、规则空白槽位、不规则间隔续填、四向多轮推导、最长补零、跨零绝对值、精确大编号、文本类型、源格式、依赖、无操作、精确历史和重开；后组溢出时整次回滚，非法种子和预算保护保持原检查。两条文本 Chromium 流程检查原生草稿、独立文本/格式/依赖缓存及其他部件、精确两步历史、重开输入和 PDF；混合/稀疏样例独立计数为 32。保持 20 秒和零重试。公开构建、根/私有静态检查通过。API/TS 未变，复用此前 931 项安装包边界断言、严格宿主编译及数字/日期浏览器结果，未重复打包。未跑全量或外部 Office；详细证据归私有 textSeriesCheckpoint，范围归[数字序列](formats.md#数字序列)。

P10 孤行控制新增两项源事务、三项布局，连同保留链/表格、段中不分页、缓存及格式/编辑/剪贴板/样式共 35 项通过。检查默认开启、样式显式关闭与继承、开关/清除、非法源及预算、精确混合历史和重开；正文两端至少两行、三行整段、短页回退、显式分页、自动行距、保留链联动及缓存一致。强化继承关闭后只重跑两项源用例，其余结果复用。四条 Chromium 流程检查新默认、原生草稿、独立分页/XML/其他部件、两步历史、重开输入、恢复继承及 PDF，保持 20 秒和零重试；原单属性分页夹具显式关闭孤行控制，标题/表格流程沿新默认。三个单元用例共 111 项断言、916 项安装包断言与严格宿主编译，以及构建和静态检查通过。旧负向夹具改用真正未支持的标记，保留保护断言；旧跨格输入补齐实际列网格。未跑全量或外部 Office。详细证据归私有 widowCheckpoint，合同归[当前格式编辑](formats.md#p10-当前格式编辑)。

P10 与下段同页延伸至紧随表格的首片段。新增三项布局，连同段落链、续行、表头、纵向合并和分页缓存共 15 项通过。检查首行高度变化向前失效、最小/精确行高、拆行/禁止拆行、纵向合并首组、超长行保留全部文字、无空页及显式分页优先。新增标题/表格 Chromium 流程，连同原段落链和拆行共三条通过，检查原生草稿、独立分页/表格源/其他部件、两步精确历史、重开后格内输入、关闭属性恢复分页及 PDF 文字。保持 20 秒和零重试。公开构建和根/私有静态检查通过。未改公开 API/TS，复用前次安装包边界检查，未重复打包；未跑全量或外部 Office。详细证据归私有 keepNextTableCheckpoint，合同归[当前格式编辑](formats.md#p10-当前格式编辑)。

P10 与下段同页新增两项源事务、三项布局，连同段中不分页、格式、表格行和分页缓存共 24 项通过。检查继承/设置/清除、格式历史、重开、非法源和预算保护，以及正文链、末段首行、段中不分页组合、前段缓存失效、段距模式、超长链、显式分页和同格续排。新增 Chromium 流程，连同原段中不分页共两条通过，检查原生草稿、独立分页与 XML、两步精确历史、无操作、保存重开及 PDF 文字，保持 20 秒和零重试。三个定向单元用例共 107 项断言、911 项安装包断言和严格宿主编译通过，公开构建和根/私有静态检查通过。该轮未覆盖正文段落与紧随表格首行联动；未跑全量或外部 Office。详细证据归私有 keepNextCheckpoint，合同归[当前格式编辑](formats.md#p10-当前格式编辑)。

P12 形状双色线性渐变新增两项核心，连同形状纯色外观和背景渐变共七项通过。检查轮廓裁剪、命中、源/选择/几何保持、无操作、纯色/边框/无填充替换、精确混合历史、旋转/复制及重开；非法参数、未知源和输出预算保持原文档。新增形状渐变 Chromium 流程，连同原纯色外观共两条通过，检查原生输入、独立 XML、精确历史、重开输入、Canvas 颜色、独立 PDF 渲染的椭圆轮廓与后续图元颜色及文字。保持 20 秒和零重试。911 项安装包断言、严格宿主编译、公开构建和根/私有静态检查通过。未跑全量或外部 Office；详细证据归私有 shapeGradientCheckpoint，合同归[PPTX](formats.md#pptx)。

P12 线性渐变背景新增三项核心，连同纯色背景、版式和页复制共 12 项通过。检查四向/斜向与页面比例角度、端点色标和源属性、有效继承、无操作、精确混合历史、重开/复制及非目标部件；非法颜色/角度、透明度/多色标/效果/歧义源和输出预算原子保护。新增渐变 Chromium 流程，连同原纯色背景共两条通过，检查背景草稿跨原生文字编辑保留、两步历史、独立 XML、重开输入、Canvas 像素、斜向渐变的独立 PDF 渲染颜色及文字。保持 20 秒和零重试。901 项安装包断言及严格宿主编译通过，当前背景值统一为类型联合，旧字符串/查询字段已移除。未跑全量或外部 Office；详细证据归私有 gradientCheckpoint，合同归[PPTX](formats.md#pptx)。

P12 两端对齐新增一项核心，连同原文字格式/段落回归共五项通过。检查自动换行中间行铺满、末行自然宽度、局部及多框、混合查询、清除恢复、源保真、无操作、精确混合历史和保存重开。现有 `pptx-text-format.spec.ts` 增加两端对齐流程，两条 Chromium 链通过，检查实际字形坐标展开、原生草稿、独立 OOXML/其他部件、两步历史、重开输入及 PDF，保持 20 秒和零重试。890 项安装包断言及严格宿主编译通过，参数校验接受新值并保留未知值拒绝。未跑全量或外部 Office；详细证据归私有 justifyCheckpoint，合同归[PPTX 文字格式](formats.md#pptx)。

P10 段中不分页新增两项源事务、三项布局，连同格式、表格行、表头和分页缓存回归共 22 项通过。覆盖样式继承、开关/清除、拆段复制、精确混合历史与重开、非法源及输出预算保护；正文整段换页、超长/显式分页/页首留白、格内整段及超长回退、属性变化与冷排版一致。新增一条 Chromium 流程，连同原表格跨页共两条通过，检查原生草稿、独立分页/OOXML/非目标部件、两步历史、重开输入、关闭属性后的分页与 PDF 文字完整性，保持 20 秒和零重试。三个定向单元用例、889 项安装包断言及严格宿主编译通过。未跑全量或外部 Office；详细范围归私有 keepLinesCheckpoint，合同归[当前格式编辑](formats.md#p10-当前格式编辑)。

P11 日期序列新增三项核心，连同数字序列和填充/查找/格式回归共 18 项通过。检查两种日期系统、1900 虚构闰日、月末恢复、年闰日进位、时间小数、工作日/大步长、四向及反向、多列格式和跨表缓存、无操作、精确混合历史与重开；非法种子、单位/步长、源形状及日期越界原子拒绝。新增一条日期 Chromium 流程，连同原数字序列/填充共三条通过，覆盖面板单位和步长、原生草稿、独立日期值/样式/缓存、两步历史、重开输入和 PDF，保持 20 秒和零重试。889 项安装包断言与严格宿主编译通过。详细证据归私有 dateSeriesCheckpoint，合同归[数字序列](formats.md#数字序列)。未跑全量或外部 Office。

P11 数字序列扩展增长模式，统一为 `series` 加必需的 `linear/growth` 模式。新增两项核心，连同线性、原填充、查找与格式回归共 15 项通过；检查增长/衰减的四向外推、稀疏/非等差及极端正数、单值/恒定值精确保留、下溢、跨表重算、格式、无操作与混合历史，以及零/负数/溢出/未知模式原子拒绝。`xlsx-series.spec.ts` 同一流程增加模式选择、原生草稿后增长填充、独立缓存/格式、两步精确历史、重开输入和 PDF，连同原填充共两条 Chromium 流程通过，保持 20 秒和零重试。873 项安装包断言及严格宿主编译覆盖两个模式和模式校验；产品代码及当前调用方已移除旧序列 API，历史证据由私有 numericSeriesCheckpoint 关联。未跑全量或外部 Office，合同归[数字序列](formats.md#数字序列)。

P11 线性数字序列新增三项核心，连同原填充、查找与格式回归，共 13 项通过。覆盖多列/行、四向、单值/空白位置/非等差样本及极端有限值、源片段和有效格式、跨表缓存、精确混合历史、重开，以及几何/类型/合并/规则/筛选/预算失败。`xlsx-series.spec.ts` 与原填充流程两条 Chromium 链通过，检查源选区捕获、原生草稿后填充、四向结果、独立 XML/缓存/样式/其他部件、精确历史、无操作、重开后输入及 PDF，保持 20 秒和零重试。安装包 866 项断言及严格宿主编译通过；新命令检查源范围和多余参数，未跑全量或外部 Office。详细证据归私有 linearSeriesCheckpoint，合同归[数字序列](formats.md#数字序列)。

P12 当前版式重置扩展原版式核心和 Chromium 流程。新增两项核心，连同版式切换、页复制与背景回归共九项通过；检查恢复几何、直接格式/身份/普通对象、关系及其他部件保持、缺失空框补齐、无操作、精确混合历史和重开，以及锁定、未知变换、无法继承几何及输出预算的原子拒绝。`pptx-layout.spec.ts` 同一流程增加占位符移动、原生草稿后重置、独立 XML、两步精确撤销/重做、重开后输入和 PDF，保持 20 秒和零重试。安装包 856 项断言与严格宿主编译通过，包含无参数重置命令和多余参数拒绝；未跑全量或外部 Office。详细证据归私有 layoutResetCheckpoint，合同归[幻灯片版式](formats.md#幻灯片版式)。

P10 普通行跨页新增两项源事务和三项布局用例，连同行高、表头、合并与分页缓存回归，共 18 项通过。覆盖逐格文字完整性、续页行距、独立格区域/底色/边框、空白格命中、跨页选择、禁止拆分与超高行、重复表头空间及预算、增删重排与冷排版一致；属性检查样式继承、无操作、结构复制、精确混合历史、重开和原子保护。`docx-table-row.spec.ts` 和原表头流程共两条 Chromium 链通过，检查默认开关、原生文字、独立 XML/其他部件、精确历史、重开、长行增长、续页空白输入与 PDF 文字完整性，保持 20 秒和零重试。公开包 852 项断言及严格宿主编译、三个定向单元用例通过。最终仅 MoonBit 的禁止拆分/表头空间保护另经布局回归和公开构建；TS 包检查与浏览器结果适用于此前相同 TS 和其余分页路径。详细范围归私有 rowContinuationCheckpoint；未跑全量或外部 Office，合同归[表格行跨页](formats.md#表格行跨页)。

P12 版式切换新增三项核心，连同页复制与背景回归，共七项通过。覆盖占位符数值索引/标题匹配、用户文字与直接格式、普通对象和非目标部件、空占位符补齐/移除、跨母版字体/背景继承、精确混合历史及重开/复制。未匹配内容、计时/连接引用、空框中的用户动作、目录和字体预算失败均保持原源。`pptx-layout.spec.ts` 一条 Chromium 流程检查原生草稿后面板切换、对象身份与核心几何、独立 XML、真实背景像素、两步撤销重做、重开后新增框继续输入及 PDF。安装包 846 项断言和严格宿主编译通过；未跑全量或外部 Office。接口及边界归[幻灯片版式](formats.md#幻灯片版式)。

P11 名称管理新增三项核心，连同名称计算、验证和条件格式回归，共 13 项通过。覆盖名称目录、全局/局部新增、定义修改、按作用域改名、共享公式及规则/其他名称同步、删除重算、精确历史与重开，以及相对定位、隐藏目标、重名/循环/未知函数/源标记失败。长部件身份计入目录预算，超限候选在提交前拒绝。现有 `xlsx-names.spec.ts` 同一 Chromium 流程增加面板增改删、所选范围、原生草稿后定位、不写源或历史的范围跳转、独立 XML、混合历史、重开及 PDF；保持 20 秒和零重试。当前重建安装包通过 829 项断言与严格宿主编译；未跑全量或外部 Office。接口及边界归[名称引用](formats.md#名称引用)。

P11 已有名称计算新增三项核心，连同逻辑、SUBTOTAL、轴结构及验证回归，共 14 项通过。覆盖作用域、Unicode、常量/范围/表达式、相对引用、未定义名称、增量依赖、嵌套汇总、规则、绝对定义的插行/改名/复制/删除、精确历史及循环/预算失败；未计算命名公式保留导入缓存并拒绝打印。`xlsx-names.spec.ts` 一条 Chromium 流程检查已有名称文件继续原生编辑、条件格式像素、独立公式/缓存及计算元数据、精确混合历史、重开和 PDF。公共 TS/API 未变，复用此前 812 项参数断言和严格宿主编译结果；当前核心与 Worker 构建另经本轮流程验证，未重跑安装包或全量。管理与定位仍待实现，边界归[名称引用](formats.md#名称引用)。

P11 公式显示新增两项核心，连同原视图/冻结及四项自动适配，共 11 项通过。覆盖共享公式与错误/文字结果、编辑显示、双倍默认/显式宽度、隐藏列、RTL 命中、原共享源/缓存及其他部件、统计不变、精确历史/重开、适配反算，以及本地/继承隐藏保护和失败原子性。原 `xlsx-view.spec.ts` 增加默认开关前的原生输入、可访问文字、独立源/缓存、CSV 和统计值、撤销重做、重开、适配后点击输入与公式 PDF。812 项安装包断言及严格宿主编译通过。保持 20 秒与零重试，未跑全量或外部 Office。显示语义归[工作表网格线与标题](formats.md#工作表网格线与标题)。

P11 RTL 扩展现有视图用例，共 5 项核心通过。新增检查右侧冻结列、反向列坐标、左边缘命中、合并选区四块裁剪、精确历史/重开，以及非对称边距和 50% 打印缩放。原 Chromium 流程增加 RTL 开关、方向键与 Tab 区别、原生输入、实际双向滚动、冻结命中、独立源属性及重开/PDF，保持 20 秒和零重试。808 项重新安装包断言及严格宿主编译通过。接口归[工作表网格线与标题](formats.md#工作表网格线与标题)；普通分割窗格和其余 P10/P11/P12 功能仍待实现，未跑全量或外部 Office。

P11 网格线和行列标题用两项新增核心及两项冻结回归检查源属性、其他窗口、无主窗口创建、计算缓存、打印不变、精确历史/重开和保护/预算失败。无标题网格另检查冻结命中、选区、滚动、过期布局与显式边框。`xlsx-view.spec.ts` 一条 Chromium 流程覆盖原生草稿后切换、输入定位、冻结滚动、独立 XML、混合历史、保存重开与 PDF。802 项安装包断言及严格宿主编译通过。浏览器暴露的旧标题偏移校验和覆盖层裁剪已修正；保持 20 秒与零重试，未跑全量或外部 Office。接口和边界归[工作表网格线与标题](formats.md#工作表网格线与标题)。

P10 九级标题格式重置扩展现有 `style_reset_wbtest.mbt`，检查全部级别的目录能力、初始/重复空操作、字号/粗体/大纲及继承、名称与 next/link/别名保持、正文直接格式、精确历史和重开，以及导入英文名、自定义同名、属性注释和默认角色歧义。连同原样式重置和两项后续样式回归，共七项通过。原 `docx-overview.spec.ts` 增加标题修改后面板重置、源字节恢复、单步撤销重做及空操作检查，原导航/输入/组合/重开/PDF 链仍通过。公共 TS 接口未改，复用此前 793 项安装包与严格宿主结果；本轮只重建和运行相关核心、Chromium 及静态检查，未跑全量或外部 Office。

P12 当前页 PNG 用 `pptx-png.spec.ts` 的一条 Chromium 流程检查原生输入、DPR=2 与不同预览缩放、独立 PNG 头/尺寸/解码、与同分辨率预览的完整像素相等、旋转裁剪图片及源颜色、选择/文档源/历史/未保存状态、默认菜单回调、不能确认原格式保存、参数/字节/像素预算与失败恢复、隐藏页和释放后拒绝。为覆盖 DOM 初始化拆分及共享输出队列，另跑既有 P9 PPTX 输入/历史/PDF/保存重开与新建流程，通过原有时限。793 项重新安装包断言与严格宿主编译通过；无 MoonBit 行为修改，未新增或重跑核心用例。新 PNG 流程保持 20 秒与零重试，未跑全量或外部 Office。

P11 选区统计新增三项核心检查当前类型/公式结果、查询源/选区/历史保持、筛选/手动行隐藏与隐藏列、精确历史/重开、稀疏整表、数值抵消及求和溢出；复用三项筛选和三项 SUBTOTAL，共九项通过。`xlsx-statistics.spec.ts` 一条 Chromium 流程检查状态栏、原生草稿与提交、公式依赖、筛选和隐藏、三步精确混合历史、独立缓存 XML/非目标部件、查询不写源、重开及 PDF。重新安装包的 786 项断言及严格宿主编译通过，包含统计返回值边界与新类型。保留 20 秒超时、零重试；未跑全量或外部 Office。

P10 标题导航与正文统计检查十七项核心用例：原九项，加两项段末后续样式及六项列表回归。`docx-overview.spec.ts` 一条 Chromium 流程检查空白创建、原生输入、九级预设中的样式应用、跨页标题定位、光标焦点、统计更新、组合候选期间的导航禁用及取消、旧修订/文档拒绝、精确历史、独立 XML/非目标部件、保存重开、标题 Enter 恢复正文及两步精确历史和 PDF。安装包增加返回值边界检查，合计 767 项断言通过，严格宿主编译包含新 API。测试宿主显式补齐标题粗体字体映射，组合候选使用当前输入路径的 CompositionEvent；保留 20 秒超时和零重试。未跑全量或外部 Office。

P12 普通演讲备注新增三项核心，检查首个部件/双向关系、读取/修改/清空、换行与源转义、非目标部件/选择、外围占位符和格式、独立复制/删除资源、原子拒绝、精确混合历史及重开；复用页复制与页操作，共 11 项通过。核心历史修复独立新增部件的 XML 身份分配恢复，原字节断言保持。Chromium 一条流程覆盖原生输入、备注面板、独立 XML、跨页与副本、清空/撤销、重开及不泄露备注的静态 PDF。747 项安装包断言、严格宿主编译和静态检查通过。合同归[演讲备注](formats.md#演讲备注)，详细证据归私有 notesCheckpoint；未跑全量或外部 Office。

P11 自定义筛选新增三项核心，检查六种比较、当前数值/公式与格式标签、通配符/转义、双条件 AND/OR、跨列交集、导入默认值与按钮标记、手动隐藏、原子拒绝、混合历史和重开；复用值筛选、SUBTOTAL 与自动尺寸，共 13 项通过。原 Chromium 筛选流程扩展到数值双条件、文字通配符、交集与 OR、独立 XML/SUBTOTAL、原生输入/重新应用、精确历史及重开/PDF；通过原超时和零重试。738 项安装包断言与严格宿主编译通过。合同归[筛选](formats.md#值筛选)，详细定位保留在私有 customFilterCheckpoint；未跑全量或外部 Office。

P10 行内图片拖动缩放新增两项核心，检查原始尺寸派生的候选、裁剪与资源、四角与边界、最终坐标、空操作、精确混合历史/重开，以及身份/位移/忙碌状态保护；复用尺寸编辑、选择与四项组合输入回归，共 9 项通过。原图片选择 Chromium 流程扩展到缩放后的真实拖动、核心预览、Escape、独立尺寸 XML/非目标图片、单项历史、方向键及重开；保留原生编辑与 PDF。另复用恢复和迟到回复销毁两条流程，三条均有通过证据。712 项安装包断言与严格宿主编译通过。源范围与生命周期归[图片拖动缩放合同](formats.md#绘图对象移动与缩放手势)；详细失败定位保留在私有 pictureResizeCheckpoint。该安装包记录对应旧缩放接口；新手势接口的检查范围见 `docxPictureMoveCheckpoint`。未增加超时/重试，未跑全量或外部 Office。

P11 SUBTOTAL 新增三项核心检查全部 22 个编号、类型/错误/空值、手动隐藏与隐藏列、嵌套/包装汇总、标量/跨表/多区域、整列稀疏与大数方差、可见性及增量依赖、源缓存、精确混合历史/重开和参数/环/预算失败；复用三项值筛选及三项条件聚合，共 9 项通过。原 `xlsx-filter.spec.ts` 扩展比较筛选后 18/14、原生编辑重新应用后 21/17、清除后 27/23；独立 XML、语义网格、混合历史、重开及 PDF 均通过。无 SUBTOTAL 时保留原缓存/calcChain，相关非目标部件断言保持。PDF 抽取预期包含原 E1 的 18；清除后通过正常区域定位显示被虚拟化的汇总行，再恢复选择。保留 20 秒超时和零重试。公开 TS 未改，复用此前 687 项安装包参数与严格宿主编译结果，未重跑全量或外部 Office；导入隐藏来源限制归[SUBTOTAL 合同](formats.md#subtotal-汇总)。

P11 普通值筛选用三项新增核心检查多列/空白/大小写/当前公式及条件格式显示值、手动与筛选隐藏重叠、行高隐藏意图、原生编辑后的重新应用、导入标记、复制改名、非目标部件、精确混合历史与重开，以及未知源/锁定/预算/过期输入拒绝；复用四项自动尺寸和一项稀疏行高列宽回归，共 8 项通过。`xlsx-filter.spec.ts` 一条 Chromium 流程检查原生输入、默认值面板、语义网格、独立筛选/隐藏来源/行高/缓存 XML、非目标部件、重新应用和混合历史、保存重开、清除/移除及 PDF 隐藏结果。687 项安装包参数断言及严格宿主编译通过。浏览器发现原生输入被旧自动适配保护阻止，已接通已知筛选并保留未知筛选拒绝；原负向夹具改为未支持的自定义筛选，新用例覆盖带字体的筛选编辑。未修改 20 秒超时或零重试，未跑全量及外部 Office；外部文件缺少隐藏来源扩展时的重叠歧义归[值筛选合同](formats.md#值筛选)。

P11 普通区域排序新增三项核心检查多键行/列、标题、大小写、稳定同键、类型键/空值、隐藏位置、富文本源/命名空间/有效格式、共享/相对/绝对公式及跨表依赖、链接/验证范围、精确历史/重开，以及非法键/预算/过期输入和未知源保护；复用两项填充与五项格式/清除/格式刷回归，共 10 项通过。`xlsx-sort.spec.ts` 一条 Chromium 流程检查原生公式栏输入、双键面板、独立记录顺序/同键/格式/公式/XML/非目标部件、两步混合历史、重开和 PDF 文字顺序。660 项公开安装包断言和严格宿主编译通过。独立文字预期发现默认 String.compare 按长度优先，现改为逐字符比较；预期未改。空串公式夹具改用正确的 t=str 缓存类型。未增加浏览器超时/重试，未跑全量或外部 Office；语言区域顺序、筛选/表格及更广资源排序仍待实现。

P12 一次移除所有章节新增一项核心检查空操作、含空章/重名章的清空、页面/对象/选择保留、单项历史、非目标部件、外层属性/注释/处理指令及未知无关扩展、过期输入、精确撤销重做与重开；已有损坏章节检查同时覆盖拒绝清空。复用十三项章节/页操作/复制回归，共 14 项通过。原 Chromium 折叠流程扩展检查全部移除、平面页导航、空入口禁用、独立 XML、精确非目标部件、单步撤销重做和清空后重开；通过原 20 秒超时及零重试，保留原折叠/PDF 检查。646 项重新安装包断言及严格宿主编译通过。未跑全量、外部 Office 或其他浏览器。

P12 章节折叠在 `pptx-sections.spec.ts` 增加一条 Chromium 流程，检查平面页列表、章节分组、Space/Enter 与焦点、aria-expanded/controls、隐藏页入口、核心查询和源字节不变、全部折叠/展开、改名与撤销后的状态保持、前后页导航自动展开、折叠时的完整 PDF 页序，以及文档重开重置。原两条章节/连页删除流程在相同产品构建通过，共三条流程有通过结果。首次在程序化保存后直接按 Enter，保存的忙碌状态已移动焦点；现先聚焦原章节标题，再按键，保留 Space 后的焦点断言。只重跑失败的新流程，保留原 20 秒超时和零重试。645 项重新安装包断言及严格宿主编译通过；未改核心，复用前次 13 项核心结果，未重跑全量或外部 Office。

P12 章节及页面删除用两项新增核心检查多页/独占资源/链接清理、单项历史、原选择、混合编辑、精确撤销重做和重开，以及空章、末页、过期输入、后续页面的未知引用和累计历史预算拒绝；复用十一项章节/页操作/复制回归，共 13 项通过。`pptx-sections.spec.ts` 新增一条 Chromium 流程，检查原生草稿后整章删除、独立页/关系/备注清单、非目标部件、两步输入/删除历史、重开与单页 PDF；连同原章节流程共两条通过。645 项公开安装包断言和严格宿主编译通过。首次读取新增页状态过早，现等待既有保存队列；随后通用夹具的两页共享备注触发既有保护，新正向输入为第二页补齐独立备注和回链，并断言其删除；共享备注拒绝仍由原核心用例覆盖。超时、零重试和源/历史断言保留。章节折叠检查见本节对应记录；未跑全量、外部 Office 或其他浏览器。

P12 普通章节用三项新增核心检查创建/改名/移除/整章重排、稳定身份、页操作归属、空章、源保留、精确混合历史与重开，以及非法输入和未知章节保护；复用八项页操作/复制回归，共 11 项通过。`pptx-sections.spec.ts` 一条 Chromium 流程检查原生输入、默认章节面板、独立 XML 的 GUID/数值成员及页序、非目标部件、六步精确历史、保存重开和 PDF 文字页序。643 项公开安装包断言及严格宿主编译通过。初次按钮定位误用了 Add slide，现使用已有 Add blank slide 名称；断言、20 秒超时和零重试保留。未跑全量、外部 Office 或其他浏览器；章节折叠及连页删除检查见本节对应记录。

P10 图片点击选择新增两项核心检查段内对象身份、字面占位字符、源选择元数据、删除/调整后的精确历史与重开，以及相同资源的两张图片、LTR/RTL 左右边缘、准确框和裁剪、保护原因。复用十项图片与六项命中/选择/裁剪回归，共 18 项通过。`docx-picture-selection.spec.ts` 一条 Chromium 流程检查缩放后的真实点击、面板自动切换、Shift 扩选、独立 XML 和非目标部件、原生删除/替换、精确历史、重开和 PDF 文字。620 项公开安装包断言及严格宿主编译通过，包含 picture 范围和 selected 查询的信任边界。初次 XPath 按各 run 的子项定位第二张图片，现用全局括号定位；后一次断言读取了 xmllint 的结尾换行，现只清理命令输出边界。原有源/历史断言、20 秒超时和零重试保留。未跑全量、外部 Office 或其他浏览器；拖动缩放、浮动环绕和富资源剪切仍待实现。

P11 普通数据条用三项新增核心检查稀疏数值/当前公式、阈值缓存、条长和渐变、值显示、优先级停止、负值/均匀值、公式错误、主题色保留、整列描述、精确历史/重开及非法设置/未知源的原子保护；复用十项颜色刻度及条件格式回归，共 13 项通过。`xlsx-data-bar.spec.ts` 一条 Chromium 流程检查原生输入、阈值/条长/颜色/显示面板、依赖变化、独立 XML、精确历史、重开及 Canvas/Poppler PDF 渐变与文字。610 项公开安装包断言及严格宿主编译通过。初次 PDF 固定取样框超出列宽，后一次固定纵坐标未考虑原生输入触发的自动行高；现按实际单元格几何和打印边距取样，保持颜色误差上限与原有超时/零重试。未跑全量、外部 Office 或其他浏览器；x14 数据条、图标和其他规则仍待实现。

P11 颜色刻度用三项新增核心检查两/三节点插值、稀疏数值范围、当前公式结果、百分位/百分比、公式阈值、均匀/空范围、主题/索引色保留、依赖重算、整列描述、精确历史与重开，以及未知源和统计预算恢复；复用三项管理与四项普通呈现回归，共 10 项通过。`xlsx-color-scale.spec.ts` 一条 Chromium 流程检查原生输入、节点面板、绝对公式阈值及依赖变化、独立 XML、基础格式保留、混合历史和重开后的 Canvas/Poppler PDF 像素与文字。585 项公开安装包断言及严格宿主编译通过。扩展数据条和其他规则仍待实现；未跑全量或外部 Office。

P11 普通数据验证当前用七项核心检查创建/修改/清除、范围外规则及相对公式、整列描述、混合/no-op 查询、列表值类型和等号文字安全、提示开关、过期选项、精确历史、保护和预算失败；包含三项原输入校验及一项局部规则清除回归。前次填充/查找回归保留独立记录。`xlsx-validation.spec.ts` 继续使用同一条 Chromium 流程，检查非法草稿、警告授权、整块粘贴、默认规则表单和下拉、原生输入与规则独立撤销、局部源 XML、非目标部件、重开和 PDF 文字。532 项公开安装包断言及严格宿主编译通过。初次新增面板定位缺少明确的 select 无障碍名称，现沿既有控件方式提供；未提高超时或增加重试。未跑全量或外部 Office，命名/扩展公式仍待兼容。

P12 预设形状调节用三项新增核心检查圆角与四向箭头、独立调节项、旋转/复制、精确混合历史、保存重开、多选原子失败、锁和未知源，以及字体缩小/形状自动尺寸的同项历史；复用已有预设路径和命中用例，共四项通过。`pptx-adjustment.spec.ts` 一条 Chromium 流程检查原生输入、数值面板/恢复预设、独立 XML、非目标部件、精确历史、重开和 Canvas/Poppler PDF 像素。新操作与查询接入公开安装包，497 项断言及严格宿主编译通过。指针调节手柄、自定义几何、全量测试和外部 Office 未验证。

P10 行内图片用 10 项定向核心检查插入、尺寸/裁剪/重置、替换、删除、共享资源隔离、原生文字/组合输入、格式与查找、段落拆合、精确混合历史、保存重开及保护/预算失败；复用 4 项普通文字格式、组合输入和换行回归。图片按一个 UTF-16 占位计数，单独检查字面 U+FFFC 不会变成图片、锁和数值引用不会被范围删除绕过，以及含图片单元格仍保护表格结构命令。纯文字剪切含图片时，在写剪贴板前拒绝。裁剪布局、命中及缓存沿用已有定向结果；紧凑的基线失败和修复记录留在私有 checkpoint。

现有 `docx-picture.spec.ts` 一条 Chromium 流程检查默认面板插入/替换/裁剪/删除、独立 XML 与资源、Canvas/Poppler PDF 像素、真实键盘跨图片输入、Enter 拆段和 Backspace 合段/删除图片、精确历史、保存重开，以及剪切保护、零次剪贴板写入和恢复。公开包参数与严格宿主共 478 项断言通过。未知图片源/效果、鼠标图片对象选择、浮动环绕和富资源剪贴板仍待实现。未跑全量或外部 Office。

P12 缩放组用一例新增核心检查非等比与嵌套、独立框坐标、字号/边距/线宽、预览与提交一致、取消、逐层取消组合、精确历史及重开；既有组合例改查缩放后可取消，并复用选择、对齐、方向、整稿尺寸及外观用例，共 16 例通过。`pptx-scaled-group.spec.ts` 检查默认按钮、前后 Canvas 画面一致、独立同字号文本的 PDF 边界、源 XML、非目标部件、精确历史、保存重开及原生输入。已有整稿尺寸 Chromium 流程在同一构建通过。初次 PDF 断言估算字高，现用独立文本对照，未放宽数值误差或超时。公开接口和 TS 运行时代码未改，复用前次 450 项公开安装包断言；未跑全量或外部 Office。

P11 四向填充用 `xlsx-fill.spec.ts` 的一条 Chromium 流程检查相邻来源、四向按钮、原生草稿和填充分项撤销、相对/绝对公式、有效样式、独立 XML/跨表缓存/非目标部件、保存重开后输入和 PDF。核心两例检查类型值、共享公式、精确混合历史、边界/no-op、合并与资源保护及预算；复用八例查找/格式检查。新命令加入公开安装包参数与严格宿主检查，累计 450 项断言通过。初次浏览器读取早于命令完成，现等待现有编辑队列；文字输入使用现有前缀标记，正文另行检查。未增加全量、外部 Office 或像素验收。

P11 打印设置用 `xlsx-print-setup.spec.ts` 检查原生草稿后设置纸张/边距/比例、预览返回编辑、设置关闭旧预览、精确混合历史、适合页数、独立 XML/缓存/非目标部件、PDF 页数/尺寸/首尾文字、保存重开与临时纸张覆盖。`xlsx-print-range.spec.ts` 补一条区域/标题操作链，检查独立名称 XML、混合历史、6 页 PDF 的每页标题和完整正文、清除、保存重开及继续原生输入。核心沿冻结/设置回归补两项范围用例，检查分页/适合页数的标题占位、不重复正文、名称随表操作更新、属性/非目标源/选区保持及非法源/预算/保护失败。浏览器输入等待原生控件可编辑并取得焦点；固定行高的 PDF 夹具明确隔离自动行高。非连续多区域及完整兼容矩阵未运行。

P11 纯文字页眉页脚用 `xlsx-header-footer.spec.ts` 的一条 Chromium 链检查待提交原生输入、六段与标志、精确混合历史、独立 XML/距离/非目标部件、三页 PDF 的首页/偶数页/奇数页字段及完整正文、保存重开后清除/撤销和继续输入。文本框有明确无障碍名称，重挂载后的初始内容不影响标签定位。核心两项用例检查页码起点、对齐位置、随表/独立缩放、根注释/空节点创建、选区、无操作及未知源/旧 revision/预算/纸张越界；同时运行六项已有范围/设置/冻结回归。字体、图片、日期/文件代码、PDF 像素对照及外部 Office 未验证。

P11 多表用 `xlsx-print-workbook.spec.ts` 的一条 Chromium 链检查原生草稿后全部可见表预览、跨表翻页、两种默认 PDF 出口、独立 PDF 混合纸张尺寸/顺序/标题/页码、隐藏表排除及 XLSX 未保存状态。导出当前表后，原多表预览仍保留页数与当前位置；错误选表后继续使用已有 PDF 缓存并返回原生输入。核心两项用例检查重排后的工作簿顺序、各表页面设置/打印区域/重复标题、切表重置页码与全局总页数、查询/源/历史保持、末表失败以及整次 1024 页/32768 格预算；同时运行八项已受影响的打印回归。只验证当前支持的绘制内容，图形与完整兼容矩阵仍待后续功能。

P12 查找替换沿 `pptx-search.spec.ts` 检查原生输入后搜索、当前页/全稿、隐藏页定位、单个/全部替换、过期提示、独立 XML/字符格式、非目标部件、精确混合历史、换文档后的宿主拒绝、保存重开后输入及包含隐藏页的 PDF。另运行既有原生输入/键盘/候选/剪贴板链，检查键盘模块拆分的调用边界。核心三项搜索用例覆盖跨 run、大小写/全词/重音/UTF-16/字素边界、跨页/框目标、1000 次普通替换合并源事务、结构换段、no-op、历史、截断和保护/缺字体/字形/候选/旧 revision/预算原子失败；同时运行三项已有字符/上/下标回归及四项 DOCX 搜索文件回归。公开包检查严格宿主与搜索输入/结果校验，三个包使用更新后的精确文件清单。本次未跑全量或 PDF 栅格。

P12 文字/段落格式和列表使用两条 Chromium 链：`pptx-text-format.spec.ts` 保留原生草稿、局部格式、装饰、上/下标、混合查询、独立 XML、精确历史、清除格式、保存重开后输入和 PDF；`pptx-lists.spec.ts` 检查默认列表控件、字母编号起始值、局部符号、级别、移除和混合值、精确历史，以及重开后原生换段续号和独立 PDF 文字。列表的核心九例覆盖列表、段落、字符、清除与上/下标，包含多框独立计数、空段/层级/继承、换行标记、无操作、源和部件保持，以及缺字体/未知定义/预算的原子失败；两例已有 DOCX 编号检查保护公共序号函数迁移。此前公共装饰、脚本布局和文本框检查保留原范围。公开包检查动作、查询、严格宿主编译和边界输入。本次未重跑全量或 PDF 栅格；其余格式功能继续实施。

P12 标记样式沿 `pptx-lists.spec.ts` 新增一条 Chromium 流程，检查待提交原生输入、字体、百分比/点值大小、RGB、恢复正文样式、继承邻段保持、混合查询、精确历史、独立 XML、实际 Canvas 标记颜色及重开后换段续号/PDF。两项新核心用例检查继承覆盖与清除区别、选中字源保持、换行标记、多框、字体元信息、无列表预设样式，以及重复调用、未知源、缺字体、旧 revision、非法大小/颜色/字体与预算原子失败；复用六项列表/段落/清除回归。公开包检查新字段边界及严格宿主调用。不增加全量、外部 Office 或 PDF 栅格验收。

P12 文本框沿 `pptx-text-frame.spec.ts` 的一条 Chromium 链检查原生草稿后修改边距、混合多选、垂直对齐、换行和三种适配模式、独立 XML 与缩放比例、随文字变化的尺寸、精确历史、非目标部件、保存重开后输入与 PDF 文字。核心检查双轴字体适配、自动调整形状的固定宽度/双轴尺寸、字号与段落变化、查找替换、旋转中心、预设内框、空框最小尺寸及变换候选；同时保留独立锚定坐标、缺失/空属性的有序创建、非目标属性/注释、选择、无操作历史、缺字体/候选/旧 revision/锁定/未知适配/预算原子失败。面板按所选框属性重置草稿；单纯文字 revision 不重建输入控件。

P12 端点与连接样式继续扩展 `pptx-paint.spec.ts`，检查多选设置/恢复、独立 `cap/miter` 源、精确混合历史、保存重开与原生输入，以及实际 Canvas 和独立 PDF 栅格中的方头、斜接与未选平头。两例新核心检查继承、局部缺省斜接、显式覆盖、平头/圆头/方头命中、斜线端点、定位描边及复位、精确历史与未知源/非法值保护；复用四例外观与虚线检查。公开包检查合法/非法参数及严格宿主调用；只运行相关功能，不扩大到全量或外部 Office。

P12 预设虚线扩展同一 `pptx-paint.spec.ts` 流程，检查多选写回、混合格式与精确历史、恢复继承、重开后继续原生输入、独立 `prstDash`、实际 Canvas 的划线/间隔及未选实线、独立 PDF 栅格的划线/间隔。核心两例检查 dash 随线宽缩放、定位路径与样式复原、主题颜色/宽度/线型继承、局部缺省属性、精确撤销、其他部件、同值无操作、未知源/预算原子失败及非法路径 dash；复用两例已有外观检查。公开包验证全部预设及清除值、拒绝非法值，并编译严格宿主调用；未扩大到全量、外部 Office 或性能矩阵。

P12 形状外观沿 `pptx-paint.spec.ts` 的一条 Chromium 链检查混合多选、纯色及无填充、边框宽度、原生草稿顺序、独立源 XML、非目标部件、Canvas 实际颜色、精确历史、重开后输入及 PDF 文字。核心补空/缺失属性的有序创建、线条属性和注释保留、`useBgFill`、无操作历史、保护/候选/旧 revision/预算原子失败，并检查静态打印路径的颜色与宽度。PDF 颜色栅格未单独检查。

P11 文件交换用 `xlsx-delimited.spec.ts` 的单条默认 UI 链检查 CSV/TSV 文件、默认文字、转换选项重置/取消、数字/日期/公式类型与缓存、原生公式草稿后的值导出、选区范围、安全前缀、未保存状态、独立 XML、保存重开、坏文件及公式失败恢复。日期列先自动适配，再检查 PDF 格式。核心补三个独立开关、日期序列/非法日期/公式错误、无初始历史、精确编辑历史、引号/CRLF/Unicode/不等宽行、编码和资源失败。公式栏失焦不再抢回文件菜单焦点；复用既有数值函数公式栏流程检查输入、历史与重开，不扩大到其他格式矩阵。

P12 图片不透明度用 `pptx-opacity.spec.ts` 检查导入 75%、50%/0%/100%、原像素半透明的乘积、共享图及后续图元不受影响、独立 amt 与未改图片字节、几何/选择、精确历史、重开后 25% 及 Poppler PDF 颜色。核心两例检查裁剪/复制/替换混合历史、零值与复原、有效值查询、原像素不变、绘图 alpha 恢复、未知效果/保留标记、非法值和预算保护；复用四例图片事务回归。公共图片图元和 PDF 写入扩展后，保留原有两条图片 Chromium 流程，未扩大到全量或外部 Office 验收。公开包检查比例边界和严格宿主调用。

P12 图片替换和裁剪扩展同一 `pptx-image.spec.ts`，用两个共用资源的导入对象检查独立关系、原图不变、四边比例、实际裁剪颜色、替换字节、身份/几何、精确混合历史、坏图失败、重开后重置及 PDF 颜色。核心两例覆盖同字节/同裁剪无操作、旋转翻转保持、其他副本不变、撤销重开、裁剪锁/未知源/多选保护和输出/绘图边界；复用两例插入回归。公开包沿现有检查增加替换、比例及舍入边界，默认 UI 状态以文档和有效图片属性重置；不扩大全量或外部 Office 验收。

P12 图片插入用 `pptx-image.spec.ts` 的一条 Chromium 链检查 PNG/JPEG、原生草稿、独立资源字节/关系/内容类型、非目标部件、实际 Canvas 颜色、精确分项历史、坏图失败、保存重开后复制及 PDF 栅格颜色。核心两例检查图片身份/几何、对象/页复制和删除混合历史、源字节与选择恢复、重开后旋转、无效头/尺寸、旧 revision 与输出预算原子失败。二进制资源进入共用历史后，复用八例已有页面增删/复制/重排检查备注与批注等 XML 资源恢复。公开包检查新动作与严格宿主调用；不扩展全量或外部 Office 验收。

P11 单元格移位插删沿用 `xlsx-cell-shift.spec.ts` 的原生草稿、四向操作、行列带以外保持、跨表引用、固定尺寸/冻结视图、精确混合撤销和重开输入流程。用例已加入条件格式/验证，独立检查规则范围、公式和条数，以及未渲染 PDF 的原子保护。两例新增核心检查覆盖相对/绝对与跨表公式分组、优先顺序、公式型阈值、规则删除、整列绝对规则、身份扩展和工作预算，另跑六例已有移位/整轴结构检查。前一批普通工作簿的 PDF 与 392 项公开包断言保留为历史证据；本次没有公开 API 或 TS 改动，未重复打包或全量测试。

P11 整行/整列插删用 `xlsx-axis.spec.ts` 的一条 Chromium 链检查原生草稿后的插入、绝对引用与结果、行列删除、独立 XML、非目标部件、精确混合历史、保存重开后输入及 PDF 数值。核心三例检查字符串/跨表/反向区域/全行列名称、共享公式展开、隐式稀疏身份、格式与尺寸继承、合并/冻结/多范围选择/规则锚点/链接/打印范围、缓存和历史；参数、边界、源保护、旧 revision 与输出预算失败保持已提交状态。公开包检查四个动作、参数边界与严格宿主调用；不新增全量或外部 Office 验收。

P10 表格自动适配用 `docx-table-autofit.spec.ts` 检查内容随逐字原生输入扩宽、保存重开、页面宽度、冻结、独立 OOXML、未改部件、精确历史和 PDF 文字；复用两条已有表格尺寸流程。核心两例检查合并格、模式/偏好、稳定身份、保存网格、混合历史、导入缺省模式及百分比、窄空格冻结后单列修改、缺字体、源保护和预算失败。布局一例检查中英阿混排、列表/制表符、图片、合并约束和缓存与新排版一致，复用六例合并/表头/精确高度及四例上下文换行。公开包检查模式边界和严格宿主调用；未跑全量或外部 Office 验收。

P10 精确行高沿同一 `docx-table-size.spec.ts` 新增一条 Chromium 链，检查模式切换、固定边界、实际裁剪指令、独立 trHeight、精确历史、保存重开后在隐藏文字中原生输入、恢复自动显示及 PDF 文字；原尺寸链保留。核心检查合并格完整文字、源高度/模式、同值切换、无操作、自动源属性、其他部件、精确混合历史与无效/未知/预算保护。布局检查独立行距和合并边界、部分及完全隐藏行的光标/选区/命中/垂直移动、重复表头裁剪，以及缓存和新排版一致。公开包检查必须提供的模式和严格宿主调用。未扩大全量或外部 Office 验收。

P10 单列宽度扩展既有 `docx-table-size.spec.ts`，保留整表尺寸、底色、边距、对齐、空白命中和 PDF 坐标预期；再检查合并格内第二逻辑列、其余列宽不变、独立 gridCol/tcW、精确历史、保存重开后输入，以及新 PDF 的横向距离。核心一例检查整数 twip、跨度/身份/非目标部件、原生输入和混合历史，并保留五例已有尺寸/边框回归；无效索引/尺寸、超页宽、旧 revision 与输出预算失败保持源。公开包检查合法/非法参数和严格宿主调用，不扩大全量或外部 Office 验收。

P10 边框用 `docx-table-borders.spec.ts` 检查原生输入后整表/当前格设置、线宽/RGB、移除与恢复继承、独立 XML、实际绘制指令、精确混合历史、其他部件、保存重开后输入及 PDF 文字。核心两例覆盖默认/直接边、同宽颜色及不同宽度冲突、合并外框/内部抑制、无变化、源历史和参数/无文字宽度/输出失败；同时运行四例已有表格属性及合并回归。八例已有分页/合并/表头布局保留原坐标、命中及新旧缓存一致预期；矩形边框数据改为线段后，原格矩形预期由独立 cellAreas 保留。公开包检查部分属性集、严格宿主和三份精确文件清单；已有 flow 单测检查新网格结构。不新增全量、外部 Office 或 PDF 栅格验收。

P10 重复表头用 `docx-table-header.spec.ts` 的一条默认 UI 链核对开关、分页、独立源 XML、其他部件保留、精确历史、副本实际像素/命中、源行输入、保存重开和 PDF 中的重复文字。核心补连续前缀、纵向合并边界、注释保护、过期 revision 与输出失败；排版检查独立坐标、导航/选区不重复、空间不足省略、行预算及增量缓存与新排版一致。

P12 页面尺寸用 `pptx-size.spec.ts` 的单条默认 UI 链检查预设/自定义、独立 XML 几何和字体、混合精确历史、保存重开后输入及 Poppler 的 PDF 文字与页面尺寸。核心沿页面/背景用例补多页继承与组坐标、身份、候选、未知几何、参考线和预算原子拒绝；不扩大到无关格式矩阵。

| 变更 | 默认检查 |
| --- | --- |
| 文档、注释、无行为变化的元数据 | `git diff --check`，核对受影响链接与声明 |
| 文案、标签、界面配色、纯样式 | 直接审阅，必要时查看页面；行为不变时不新增自动化用例 |
| 局部行为 | 最近的成功与失败用例 |
| 保存、撤销、恢复、关闭 | 对应行为，加文档保留和恢复/释放用例 |
| 同一改动影响多条功能链，局部检查无法覆盖 | 说明会破坏哪些操作及局部检查的缺口，再运行完整入口 |

按变更风险选择检查，通过后交付。有新变更、失败或未解决疑点时再扩大或重复验证。完整运行针对同一改动影响多条功能链、局部检查无法覆盖的具体风险。相同代码和输入已有适用结果时复用。

浏览器只覆盖 Chrome/Chromium，另保留独立 Node 和文件检查。普通系统输入使用现有输入法。其他浏览器引擎、Windows/Word 和 VoiceOver 验收在当前范围之外。

P9 的默认 UI 检查使用 `web-sdk-ui.spec.ts` 四条现有能力流程，复用 XLSX/PPTX/PDF 宿主回归及 DOCX 键盘/输出屏障。保存回调、候选失败/取消、草稿、释放和多实例检查放在这些流程中。安装包检查由 `ui-package.test.ts` 验证无 DOM 导入、严格类型和普通 JS 构建；包清单沿用现有 qualification。输入、视觉与原始失败/复验边界见 [P9](../implemented/p9-web-sdk-ui.md)及私有 `cases/p9-ui.json`，不授予完整 loop 通过。

P11 的数值、文本、日期、条件聚合、查找函数和单元格查找替换流程位于 `xlsx-functions.spec.ts`，与 P9 共用 `ui-mount.ts` 的准备和释放逻辑。按改动选择用例；用例标题与私有清单保持一致，移动文件不扩大验证范围。查找替换覆盖隐藏表、公式结果保护、单次历史、保存重开、草稿和 IME 屏障；对应核心检查资源失败与原子恢复。DOCX 查找沿已有 Unicode 用例检查表情之后的 UTF-16 位置。

P10 指定行列拆格使用 `docx-cell-split.spec.ts` 检查原生草稿后拆格、共享网格与邻格跨度的独立源、段落身份、Tab 新格输入、精确混合历史、保存重开及 PDF 全部文字。两例新增核心检查普通格和纵向合并格、列边界并集、原内容/格式/身份、dxa/pct/自动适配偏好、同值无操作、非法合并行分组和源/输出预算原子保护；复用四例合并和自动适配检查。公开包验证参数边界及严格宿主调用；未跑全量或外部 Office。

P10 合并行编辑扩展同一 `docx-cell-split.spec.ts`，检查合并内部插行、原生输入与删行、独立 XML、精确混合历史、末格 Tab、保存重开和 PDF。新增两例核心检查合并边界、起始行及延续行删除、整行延续时选择、行属性、内容身份和预算原子失败；复用六例已有结构与拆格检查。公开 API 未变，沿用上一批 423 项公开包断言；未重复打包、全量或外部 Office 验收。

P10 合并列插入继续扩展 `docx-cell-split.spec.ts`，检查原生草稿后的左右插列、各行不同位置、独立公共网格/跨度/文字、精确三步混合历史、保存重开输入及 PDF 全部文字。两例新增核心检查合并内部边界、整表纵横合并、复制的纵向归属、稳定身份、固定总宽、auto/nil 偏好及未知网格/输出保护；复用六例普通结构及合并检查。公开接口未变，沿用此前 423 项包断言；未重复打包或全量测试。

P10 合并列删除继续扩展同一浏览器流程，核对原生草稿后删除、完整相交格的内容删除、独立 gridAfter/行格数、精确混合历史、保存重开后输入和 PDF 中保留/删除文字。两例新增核心检查不同实际行宽、边框及实际格几何、存活身份、后续拆格/插列/插行、空行/整表移除、原纵向归属、未知元数据/锚点和非法行尾保护。与十二例现有结构用例一起通过；因公共网格检查和边框路径受影响，另复用四例合并/垂直对齐/表头布局检查。公开接口未变，沿用此前包断言；未跑全量或外部 Office。

P10 拆表使用 `docx-table-split.spec.ts` 的一条默认 UI 流程，覆盖纵向合并跨分界线、源 XML、其他部件保留、精确历史和重开后输入及 PDF。核心沿现有表格创建/结构/合并用例，补普通拆分的节点身份与命名空间、合并分界和原子失败；不扩展到无关格式矩阵。

表格尺寸沿上述核心表格与既有格式查询用例，补比例取整、合并格宽度、最小行高/自动高度、缺失属性顺序及原子失败。底色沿同一流程补合并格同步、清除、自动文字/编号对比色、待输入格式和原子失败。`docx-table-size.spec.ts` 的单条默认 UI 流程核对 XML、混合历史、重开后的输入和 PDF 中的列距/行距，并核对底色/清除的实际像素及换格后的草稿重置。垂直对齐复用该流程核对三种模式、合并格 XML、精确历史、重开后格内空白点击/输入及 PDF 文字位移。核心补样式继承和清除；排版沿既有表格、分页缓存、命中与选区用例核对独立坐标、缓存与新排版一致。公开包检查同步覆盖数字/颜色/对齐/边距边界和属性查询类型。四边边距继续扩展同一 UI 流程，核对合并格 XML、恢复继承、精确历史、重开输入和独立 PDF 列距/文字位移；核心核对逐边继承、同行顶部最大值、缓存重排，以及边距与插列/缩表组合的原子拒绝。受影响的既有预览边界用例单独执行，核对非法边距和逻辑网格的明确错误。整表对齐与默认边距继续扩展同一流程，核对左/中/右的独立位置、默认值与单格覆盖、继承恢复、源属性顺序、混合历史和重开后 PDF；核心补缺失表格属性创建与原子失败。

P10 共享页边区域独立操作用两例新增核心及三例现有页边检查，共五例通过。覆盖共享别名、非活动引用、原始 XML 与关系保留、内部目标重新定位、外链不变、精确历史、重开及预算原子失败。Chromium 检查读取保护、显式独立、编辑保存与重开；复用同次构建的首页/奇偶页链。初次浏览器输入缺少主文档关系部件，修正独立输入后通过，未修改产品或放宽断言。详细检查归私有 `runningUnlinkCheckpoint`；分页算法沿用上一批定向证据，未跑全量。

## 环境与入口

使用仓库固定的 Bun、MoonBit、Node 和私有依赖版本，安装说明见[开发文档](development.md)。`test-lab/` 是项目的私有测试资源目录，由[根 AGENTS.md](../../AGENTS.md)统一管理；目录内保留测试源码、输入、预期与执行工具。

| 入口 | 用途 |
| --- | --- |
| 根 `bun run check` / `build` / `api` | 静态检查、构建、API 输出；按变更需要选择 |
| 根 `bun run test` | 完整私有 loop；缺少私有 checkout 或任何阶段失败时，命令应失败 |
| 私有 `bun run test:unit` | 单元检查；局部修复可用 Bun runner 选择具体文件/用例 |
| 私有 `bun run test:corpus` | 输入与独立预期的完整性，不代表 SDK 支持 |
| 私有 `bun run test:browser` | Playwright Chromium；按受影响用例选择，需可用的目标产物 |
| 私有 `bun run browsers` | 仅安装锁定 Chromium；已有可用环境不重复安装 |

测试还需 `unzip`、`xmllint`、Poppler 工具、HarfBuzz 14.4.0 和 qpdf 12.4.1。字体与 PDF 诊断基线依赖这两个固定版本。`unzip -l` 支持月日年与 ISO 日期输出。ZIP 全语料检查使用 30 秒预算，保留逐成员和 CRC 校验。

完整 loop 冻结源码、输入与预期，构建一次；MoonBit、安装后的 Node 包和生产 Worker 消费同次产物。`cases/suites.json` 管理必选用例与包内容。局部运行是对应范围的证据，不冒充完整运行。

局部 Chromium 检查使用 `bun run test:browser -- <spec-file> --grep '<case-name>' --reporter=list`，按需增加 JSON 报告器。默认完整报告器核对全部必选清单，会拒绝局部选择；它用于完整 loop，规则保持。局部结果只报告实际执行的用例和环境。

测试过程自动化使用 `.mbtx`，TypeScript 用例使用 Bun/Playwright。私有 `cases/` 清单登记来源、许可、固定输入 hash、操作、独立预期、支持范围与验证状态。路径从私有仓库根目录解析：

- `cases/suites.json` 管理必选执行与归档内容；修改 MoonBit 用例时同步登记 overlay 和测试名称。
- `cases/compatibility.json` 索引兼容输入。
- `cases/catalog.json` 索引自建资产。

输入来源与许可要求见[语料管理](corpus.md)。准备好资产只证明输入可用，验证状态以实际执行结果为准。

## 证据与正确性

参考实现、兼容行为、测试设计与基准均优先使用 ONLYOFFICE core/sdkjs，其次使用 LibreOffice；Collabora 仅补充浏览器交互案例。参考冲突时，在声明的格式范围内优先采用 ONLYOFFICE，用户明确指定的行为除外。适配案例时保留许可、来源和独立预期；参考通过不代表完整 Microsoft Office 兼容。

已有 LibreOffice 基准保留真实来源，随对应功能变更按上述顺序补充或修正；不批量重采历史资产，也不把它们改标为 ONLYOFFICE 结果。

分别检查核心行为、真实浏览器 WasmGC 和文件输出。保存变更用独立 ZIP/XML 工具检查正文及非目标内容；布局/PDF 变更用固定字体、参考几何和 qpdf/Poppler。真实浏览器结论使用目标浏览器中的证据。

产品代码实现输入和格式驱动的通用规则，具体样本与预期放在测试中。保留断言强度；golden 和阈值变更依据独立证据。参考冲突先查真实文件、固定版本和上游规则，沿用用户已确定的选择。

记录输入、源码/工具版本、环境、命令和结果。成功退出且执行了目标用例才算通过；缺工具、零用例、超时和未执行都不是通过。旧失败保留原判断，不因后续修复改写。

P6 的定向功能、共享输出回归及参考应用重开见 [P6 检查依据](../implemented/p6-pptx-editing.md#足够检查与依据)和私有 `cases/p6-pptx.json`。它复用本节的文件与 Chromium 检查，不重做 P4/P5 全量验收，也不扩大历史系统输入法证据。

P7/P8 的五条 PDF 功能链与固定输入归私有 `cases/p7-p8-pdf.json`。执行 `tests/browser/pdf.spec.ts`、`pdf-interaction.spec.ts`，使用上述局部报告器；qpdf 检查结构、源压缩流、页树和字段/批注字典，Poppler 检查文字与 CropBox 裁剪后的选定像素。正向输入含 ONLYOFFICE 模板、LibreOffice 导出和独立构造的 PDF，产品 writer 不作为唯一预期。共享字体、绘制和 PDF 对象编码只重跑对应 DOCX 图片、XLSX 打印及 PPTX 图文/输入链；完整 loop 和性能专项仍不作为该阶段交付条件。

截至 2026-10-14，私有 `cases/p4-input-transport.json` 登记完整功能运行 `1791943643486` 的 405/405，并保留此前两次失败；详细记录位于 `fixtures/derived/input-transport/qualification.tar.gz`。该运行只证明绑定产物。P4 已按限定范围归档；历史完整运行与后续 R0 定向检查的区别见 [P4 验证依据](../implemented/p4-docx-editing.md#验证依据与边界)，不声明当前工作树全量通过。该记录中的原生性能控制仍有噪声失败；性能专项延后，不要求继续校准。

## 修复步骤

1. 读取私有 `.temp/runs/<id>/summary.md`、首个失败日志和对应 `failures/*.json`。
2. 确定输入、操作、预期和实际差异，区分产品、参考、数据和环境问题。
3. 使用记录的参数和安全环境配置，在新 attempt 复现，保留原有结果。
4. 修复共享规则，运行直接受影响的检查；两次尝试无新证据时重新判断路径。
5. 保留简短复现与首个失败，按本文件的范围规则选择后续检查。

重放使用新 attempt，保留旧结果。临时输出统一放在 `.temp/`；昂贵运行前检查根/私有合计容量，达到 2 GiB 停止新增。保留一个当前运行和一个必要基线，按已有授权清理任务自己的缓存。

## 负向验收

修改 runner、判定器或报告器时，选择对应错误预期、缺输入、超时或构建失败探针，确认失败可见且报告可读。普通产品修复验证对应产品行为；私有 `test:negative` 按判定器变更需要选择。

P12 形状不透明度用两例新增核心检查多选、颜色与宽度修改后 alpha 保留、主题 phClr/alphaMod/alphaOff、主题关联本地化、精确历史、保存重开、绘制状态复原及参数/源标记保护；复用八例外观、虚线、端点连接和图片不透明度回归。`pptx-shape-opacity.spec.ts` 检查默认 UI、独立 alpha XML 与其他部件、三步混合历史、保存重开后原生输入，并用独立预期核对实际 Canvas 与 Poppler PDF 颜色；同时运行已有外观链。像素只允许 8 位 alpha 舍入的 1 级误差。初次将两条流程串在一起触及 20 秒上限，现拆为独立用例，未放宽超时或断言。新公开命令与查询经过重新打包的严格宿主及 441 项断言；未跑全量或外部 Office。

P12 放映设置用 18 项定向核心检查覆盖标准属性部件首次创建、数字范围与删页收窄、自定义序列、循环与零时长边界、关闭计时/动画、源保护、精确历史及重开。五条 Chromium 用例通过，包含新增设置流程、已有自定义放映及三条计时回归；新流程检查默认面板、实际动画关闭像素、源 XML、保存重开和退出后原生输入。重新安装的公开包通过 2323 项断言和严格宿主编译。记录归私有 `showSettingsCheckpoint`；保持 20 秒、零重试，未扩展全量或外部 Office 验证。P10/P11/P12 仍为部分交付。

P11 VAR/VAR.S/VARP/VAR.P 通过 11 项定向核心检查及两条 Chromium 流程。新增用例检查直接参数与引用的类型差异、样本/总体除数、较大偏移、错误与空样本、稀疏整列、现代前缀、旧缓存、共享/名称/跨表重算、精确混合历史及重开；复用既有 SUBTOTAL 与未计算链保护断言。默认公式栏、独立 XML、原生输入和 PDF 已检查，20 秒、零重试保持。记录归私有 `varianceCheckpoint`；API、TS 与包清单未变，复用此前安装包边界结果并保留其旧引擎范围。未跑全量、外部 Office 或无关 DOCX/PPTX，各阶段仍为部分交付。

P12 放映链接通过 18 项定向核心检查、四条 Chromium 流程及 2349 项新安装包断言和严格宿主编译。新增检查覆盖文字/对象/组优先级、实际动画变换和隐藏、前景遮挡、当前/上一帧及旧交互拒绝、四类动作、重复自定义序列、隐藏/跨序列页跳转、外部意图和未知动作保护。Chromium 验证 Canvas 和键盘、无自动请求及新窗口无 opener、原格式字节与选择保持、重开输入；原有静态放映和动画/PDF 回归保留。外部目标由本地路由响应。记录归私有 `showLinksCheckpoint`；保留组测试选择错误的失败证据。保持 20 秒、零重试，未扩展全量、外部 Office 或无关格式执行。

P10 Hyperlink/FollowedHyperlink 默认定义与显式重置通过 15 项定向核心检查及两条 Chromium 流程。覆盖真实默认样式继承、别名与直接覆盖、主题绑定、新建无变化重置、精确混合历史、保存重开和链接内原生输入。独立 XML、三种文字颜色像素及 PDF 已检查；20 秒、零重试保持。记录归私有 `linkStyleCheckpoint`。公开签名、TS 与包清单未变，复用此前 2349 项安装包边界断言并保留其旧引擎范围；当前引擎由核心及 Worker/浏览器验证。未跑全量、外部 Office 或无关 XLSX/PPTX；各阶段仍为部分交付。

P11 STDEV/STDEV.S/STDEVP/STDEV.P 通过 13 项定向核心检查及两条 Chromium 流程。覆盖样本/总体的类型、错误和空样本差异，稀疏整列、数值边界、现代前缀、名称/共享/跨表重算及精确结构历史。扩展已有方差流程，保留原断言并加入标准差缓存、原生输入、独立 XML、保存重开和 PDF；未计算链保护回归保持。20 秒、零重试不变。记录归私有 `standardDeviationCheckpoint`，公开签名、TS 与包清单未变，复用此前安装包边界证据并保留旧引擎范围。未跑全量、外部 Office 或无关 DOCX/PPTX；各阶段仍为部分交付。

P12 上次查看页/结束放映动作通过 20 项定向核心检查、四条不同 Chromium 流程及 2351 项最终安装包断言和严格宿主编译。覆盖对象/文字面板、标准动作源、重复条目/自定义顺序恢复、隐藏跳转、自动换页及精确历史。新流程发现 Chromium 退出模态后只发键盘事件、不发 beforeinput；现有恢复回调重新取得原生焦点后，直接输入、保存与重开通过。四条浏览器证据由最终新用例和修复后的三条原有回归组成，保留 20 秒、零重试。记录归私有 `showActionsCheckpoint`，保留源断言、调用顺序及输入失败的紧凑证据；未跑全量、外部 Office 或无关 DOCX/XLSX。各阶段仍为部分交付。

P10 跨单元格属性选择通过 10 项定向核心检查和三条 Chromium 流程。覆盖相交合并格与延续节点、混合值、底色/对齐/边距/边框、混合行跨页状态、整格几何、输入法预览、预算失败及精确历史。浏览器检查真实拖选、整格覆盖像素、四格源属性及实际颜色、未改部件、重开后的原生输入和 PDF，保留原边框和标尺流程。标尺查询曾提前结束拖动，现改为拖动后刷新；旧边框输入步骤按完整文字定位，原预期保持。20 秒、零重试不变。最终安装包的精确清单、严格宿主及新增查询边界检查通过 2369 项断言。记录归私有 `tableRangeCheckpoint`，保留失败与基线证据。未跑全量、外部 Office 或无关 XLSX/PPTX；各阶段仍为部分交付。

P10 跨格文字格式通过 23 项定向核心检查及两条 Chromium 流程。覆盖所选整格全部文字与空段落、混合查询、组合格式、样式、格式复制、列表、合并归属、精确五步历史、未改源与预算/未知内容保护。浏览器扩展已有跨格流程，检查默认 Ribbon 的粗体/居中、独立四格 XML、四步混合历史、重开原生输入与 PDF；原边框回归保留。普通带格式换行的候选校验回归已修复，全部原断言通过。20 秒、零重试保持。记录归私有 `tableTextCheckpoint`。公开签名、TS 和包清单未变，复用上一批 2369 项安装包边界结果并保留旧引擎范围；本轮引擎由核心和当前 Worker/浏览器验证。未跑全量、外部 Office 或无关 XLSX/PPTX；各阶段仍为部分交付。

P10 跨格内容操作通过 17 项定向核心检查及三条不同 Chromium 流程。覆盖首格输入、全部所选格清空、合并归属、换行/Enter、组合取消/提交、空操作、书签留在原格、精确历史及源/输出预算保护。最终新浏览器流程检查真实键盘与 CDP 输入法、所选格数的无障碍说明、独立 XML/未改部件、重开 Tab 输入和 PDF；原格式/边框两条回归保留同引擎及说明文字修改前的应用范围。历史条数明确包含 redo，预览保留一项重做及原字节数。20 秒、零重试保持。记录归私有 `tableContentsCheckpoint`。公开签名及包边界未变，复用上一批安装包断言并保留旧引擎范围。未跑全量、性能矩阵或外部 Office；各阶段仍为部分交付。

P10 跨格纯文本剪贴板通过 12 项定向核心检查及三条不同 Chromium 流程。覆盖整格/反选、空段、合并归属、Tab/LF、65536 单元精确上限、未知内容保护和单项精确历史。新流程检查默认 Copy、真实拖选与原生 Cut、写入延迟期间状态不变、独立 XML/未改部件、撤销后的原生复制和重开继续输入。普通 Unicode 剪贴板回归通过；权限拒绝回归改用当前停止快照、只读输入框及无障碍说明，原内容/选择/恢复断言保持。20 秒、零重试不变。记录归私有 `tableClipboardCheckpoint`，保留节点身份及旧状态栏定位失败证据。公开签名及包边界未变，沿用既有安装包断言的原引擎范围。未跑全量、性能矩阵或外部 Office；富文本片段、矩阵粘贴及完整阶段继续实施。

P10 跨格行列与矩形合并通过 16 项定向核心检查及四条 Chromium 流程。覆盖六种行列操作、反选、独立宽度/文字矩阵、合并格存活归属、各复制列的纵向延续、整表移除、部分跨度/混合容器/未知内容及预算保护。新流程通过默认控件插入两行/两列、删除所选行列及按选区合并，检查真实拖选、插入后原生输入、精确混合历史、未改部件、重开编辑和 PDF；原边框、跨格格式及剪贴板回归均通过同一最终构建。保留 20 秒、零重试。记录归私有 `tableRangeStructureCheckpoint`。公开签名及包边界未变，既有包断言保留原引擎范围。未跑全量、外部 Office 或性能矩阵；完整阶段继续实施。

P11 MODE/MODE.SNGL 与 LARGE/SMALL 通过 13 项定向核心检查及两条 Chromium 流程。覆盖并列众数、直接/引用类型差异、k 与错误顺序、稀疏整列、工作预算、现代前缀、旧缓存、共享/名称/跨表重算、精确混合历史和 calcChain 清理。新流程检查原生公式输入、独立 XML、未改部件、重开与 PDF；既有 PRODUCT/MEDIAN 和未计算链保护断言保留。20 秒、零重试保持。记录归私有 `orderStatisticsCheckpoint`，保留测试编译及 calcChain 元数据预期失败证据。公开签名、TS 与包边界未变，既有安装包结果保留原引擎范围。未跑全量、外部 Office 或无关 DOCX/PPTX；各阶段仍为部分交付。

P12 普通表格通过 9 项定向核心检查和两条 Chromium 流程。新用例覆盖单元格几何、裁剪、填充及边框、真实指针与原生输入、换段及行高增长、组合输入取消、源部件、精确历史、重开和 PDF；原有文本框流程保持通过。跨格写入、不支持样式、跨度和输出失败检查原子保护。20 秒、零重试保持。记录归私有 `nativeTableCheckpoint`，保留离屏指针及测试类型错误证据。该轮公开签名、TS 产品代码和包边界未变，未跑全量、外部 Office 或新安装包检查；其范围限导入与单格输入。

P12 表格创建和整表删除通过 7 项定向核心检查与两条 Chromium 流程。新用例检查等分网格的 EMU 余数、空行增长、单元格属性顺序、源转义、未改部件、身份不复用和精确混合历史，以及无效尺寸、活动草稿、输出预算、删除锁和对象引用的原子拒绝。默认 UI 流程检查真实指针及原生输入、独立 XML、整表删除、撤销重做、重开输入和 PDF；既有导入表格流程保留。新安装包检查和严格宿主编译通过。20 秒、零重试保持，未跑全量或外部 Office。该轮证据归私有 `tableCreationCheckpoint`，范围为创建和整表删除。

P12 当前单格的行列插删通过 6 项定向核心检查及两条 Chromium 流程。覆盖六种操作的文字矩阵、格式继承、旧格及部件原源、网格与外框、光标、精确混合历史，以及当时的跨格选择、模板扩展、锁定、尺寸和输出失败保护；最后一行或列的删除及历史也已检查。新默认 UI 流程验证真实指针、按钮后继续原生输入、独立 XML、撤销重做、重开与 PDF；原创建流程保留。新安装包与严格宿主编译通过，20 秒、零重试保持。该轮证据归私有 `tableStructureCheckpoint`，范围为单格行列操作。

P12 矩形多格选择通过 8 项定向核心检查及两条 Chromium 流程。覆盖反向范围、单元格空白命中、高亮几何、制表符复制、范围输入/删除、组合候选与取消、六种批量行列操作、边界格式、原子预算失败及精确历史；原单格、创建和导入核心断言保留。真实指针流程检查复制剪切、原生输入与组合取消、范围插删、独立 XML、原格及部件、重开和 PDF，既有单格流程通过。新安装包及严格宿主编译通过。20 秒、零重试保持，未跑全量或外部 Office。证据归私有 `tableRangeCheckpoint`；合并拆分和更广样式仍待实现，各阶段保持部分交付。

P12 合并及取消合并通过 10 项定向核心检查及两条 Chromium 流程。独立合并 XML 检查跨度归属、命中、布局、文字格式、后续输入及精确历史；新增合并检查范围闭包、段落移动、延续格清空、完整跨度行列操作和失败原子性。默认 UI 流程检查原生跨度 XML、粗体保留、取消合并、未改格及部件、精确混合历史、保存重开和 PDF，原矩形选区流程通过。新安装包与严格宿主编译通过 2425 项断言；根构建和严格检查、私有类型/静态/格式检查通过。20 秒、零重试保持，保留 XML 补丁锚点修复的失败证据。记录归私有 `tableMergeCheckpoint`。未跑全量或外部 Office；任意拆分、对象变换和更广表格样式仍待实现，各阶段保持部分交付。

P12 表格对象移动、缩放和复制通过 12 项定向核心检查及两条 Chromium 流程。覆盖网格预览与取消、原格源保留、行高适配、合并格和混合多选、对齐/层次、复制独立编辑、锁/预算保护及精确混合历史。真实拖动和默认控件流程检查原生列宽/行高/外框、实际底色、未改部件、自动输入焦点、保存重开和 PDF；原合并流程通过当前构建。用例按公开拖动/忙碌状态等待指针结束后再输入和保存，保留最初的时序与标签定位失败记录。新安装包与严格宿主编译通过 2425 项断言，公开签名及清单未变。20 秒、零重试保持，未跑全量、外部 Office 或无关格式运行。证据归私有 `tableTransformCheckpoint`；各阶段仍为部分交付。

P12 单元格四类格式通过 14 项定向核心检查及两条 Chromium 流程。覆盖底色/移除、四边实线/移除、边距、垂直对齐、混合查询、整表和范围、共享边同步、合并格部分边保护、取消合并宽度预检、缺省属性创建、未知源及预算保护、无操作和精确历史。真实反向拖选使用默认控件，检查独立属性/共享边 XML、未改段落及部件、实际底色/边框像素、行高增长、原生输入、混合撤销重做、重开和 PDF；原表格对象操作流程通过当前构建。修复选择框的可访问名称，保留最初的定位失败和夹具定位失败记录。新安装包与严格宿主编译通过 2440 项断言，新增混合值及非法格式查询边界检查；根和私有严格检查通过。20 秒、零重试保持，未跑全量、外部 Office 或无关格式运行。证据归私有 `tableCellFormatCheckpoint`；各阶段仍为部分交付。

P12 表格文字格式通过 10 项定向核心检查及两条 Chromium 流程。覆盖单格局部 run、光标后续输入与清除、空格默认格式、矩形范围排除中间未选格、段落/列表及清除、合并主格编号延续、形状/表格混合事务、行高适配、缺字体/文字锁/预算保护及精确历史；共用的形状字符/段落/清除六项用例和原单元格样式两项用例通过。旧清除用例在修改前代码上也有相同下划线失败，现按保留超链接的既有行为修正显示预期，并明确断言直接 `u` 属性已移除。真实反选通过已有默认控件修改粗体、字号、对齐和段距，检查独立 XML、非目标格及部件、行高、原生输入、精确混合历史、重开和 PDF；原单元格样式流程通过当前构建。新安装包及严格宿主编译通过 2440 项断言，公开接口和包清单未变。20 秒、零重试保持，未跑全量、外部 Office 或无关格式运行。证据归私有 `tableTextFormatCheckpoint`；各阶段仍为部分交付。

P12 单格按行列拆分通过 10 项定向核心检查及两条 Chromium 流程。覆盖普通格新增行、跨行格约数限制、非对齐整数网格、相邻跨度、原文及样式、源间隙和链接保留、原生输入、行高、精确混合历史及原子失败；共用的行列模板、合并、框格式和文字格式用例通过。表格链接编辑和替换继续受保护，避免共用格式权限误放开跨格写入。默认 UI 流程检查反向选区、2×3 拆分、独立 XML、新空格格式、输入、撤销重做、重开和 PDF；既有单元格格式流程通过。新安装包及严格宿主编译通过 2455 项断言，修正新增 UI 模块清单路径并保留初次失败证据。根和私有严格检查通过，20 秒、零重试保持。未跑全量或外部 Office。证据归私有 `tableSplitCheckpoint`；各阶段仍为部分交付。

P12 单格文字链接通过 9 项定向核心检查，覆盖局部反向范围、字符/段落边界、光标整段链接、空格与合并格、原生输入、精确混合历史、重开、放映实际命中及原子保护；共用的三个文本框链接用例、两个拆格和两个表格文字格式用例通过。新 Chromium 流程以真实反向拖选使用现有链接面板，检查独立 XML、相邻格/格式/部件、关系复用、输入、页导航、移除、跨格禁用、精确撤销重做、重开和 PDF；原文本框链接流程在同一构建通过。新增流程的双击选字及撤销接口误用已按既有输入和按钮方式修正，保留失败证据，产品代码未因此修改。20 秒、零重试保持。根 api/check/build 与私有类型/静态/格式检查通过。公开接口、TS 产品代码及包边界未变，未重跑安装包、全量或外部 Office。证据归私有 `tableHyperlinkCheckpoint`；各阶段仍为部分交付。

P12 表格查找替换通过 9 项定向核心检查及两条 Chromium 流程。新增检查逐格 UTF-16 范围与片段、不跨格串接、普通/合并格跨 run/段落替换、格式/链接/邻格源保留、混合对象行高适配、精确历史、重开及锁/整页/字体/输出原子保护；既有搜索、表格链接和拆格用例通过。默认面板检查当前/全部页、隐藏页结果、单个/全部替换、过期结果、独立 XML、原生输入、撤销重做、重开及 PDF。浏览器发现选区右箭头多走一字，已修正共用核心导航，并检查文本框/表格正反向收起及 Shift 扩展，保持原浏览器文字断言。根与私有严格检查通过，20 秒、零重试保持。公开接口及包边界未变，未重跑安装包、全量或外部 Office。证据归私有 `tableSearchCheckpoint`；各阶段仍为部分交付。

P10 跨格取消合并通过 10 项定向核心检查及两条 Chromium 流程。覆盖多个横纵跨度、相交主格、范围外合并格、逐行样式与原段落保留、普通格无操作、Tab/输入、精确混合历史、反选恢复和源/边距/字体/输出失败；既有合并、跨格结构及属性用例通过。默认按钮流程检查真实反选、独立 4×4 网格/宽度/底色/格式 XML、未改格及部件、新空格原生输入、撤销重做、重开及 PDF；原行列/合并流程保持。旧跨格取消合并拒绝断言已替换为成功后的格式与精确撤销检查，拆格/拆表保护保留。根与私有严格检查通过，20 秒、零重试保持。公开接口及包边界未变，未重跑安装包、全量或外部 Office。证据归私有 `tableRangeUnmergeCheckpoint`；各阶段仍为部分交付。

P10 批量拆格通过 8 项定向核心检查及两条 Chromium 流程。覆盖逐格行列拆分、公共列切点、共享新增行、相邻增行下的纵向合并组、原文/格式/宽度偏好、精确历史、原生输入、重开及整除/总行列/字体/输出保护；既有单格拆分、范围属性和删除后拆格用例通过。默认表单流程检查真实反选、2×3 拆分、独立 twip 网格/行高/底色/跨度 XML、原段落及部件、新空格输入、精确撤销重做、重开和 PDF；原批量取消合并流程通过。旧范围拆格拒绝已替换为成功后的宽度/底色及精确撤销检查，拆表保护保留。根与私有严格检查通过，20 秒、零重试保持。公开接口及包边界未变，未重跑安装包、全量或外部 Office。证据归私有 `tableRangeSplitCheckpoint`；各阶段仍为部分交付。

P10 普通格矩阵粘贴通过 9 项定向核心检查及两条 Chromium 流程。覆盖反向范围、带引号的 Tab/LF/双引号字段、空格与无操作、自动增行扩列、整数宽度、目标格式、非目标段落与部件、原生 Tab/输入、精确混合历史、重开及合并/非法输入/总量/字体/输出保护。既有表格内容、插列和 XLSX 数据验证用例通过，共用 TSV 解析器保留原行为。新默认按钮流程检查独立 XML、格式、重开和 PDF；延期读取后的目标变化、读取拒绝及重试均保留文档。既有纯文本复制剪切流程保持。初次核心失败来自选择受保护内容，初次浏览器保存早于读取提交；检查已按既有保护与可观察状态修正，保留失败证据。读取后新增等待已接受输入，覆盖同轮焦点队列变化。新安装包及严格宿主编译通过 2463 项断言；根 api/check/build 和私有类型/静态/格式检查通过。20 秒、零重试保持，未跑全量或外部 Office。证据归私有 `tablePasteCheckpoint`；各阶段仍为部分交付。

P10 跨格边距面板通过 4 项定向核心检查和两条 Chromium 流程。扩展既有边距及跨格属性用例，覆盖各边的统一／混合查询、样式与表格继承、直接覆盖、查询无修改、批量设置/清除、合并格、精确历史及非法/受保护/输出失败。扩展既有指针属性流程，检查混合边占位、空值禁止提交、四格独立 twip XML、范围外完整源、继承重置、六步混合撤销重做、重开输入及 PDF；共用表单的既有单格/整表/合并流程通过。新安装包通过 2470 项断言及严格宿主编译，检查新增逐边属性、非法返回值及 UI 源/声明清单。根 api/check/build 与私有严格检查通过。核心和浏览器均首次通过，未加专用快照、超时或重试，未跑全量或外部 Office。证据归私有 `tableRangeMarginsCheckpoint`；各阶段仍为部分交付。

P10 跨格行跨页面板通过 4 项定向核心检查和五条 Chromium 流程。扩展既有跨格用例，检查混合值、统一禁止、无操作和精确撤销后的选择/混合值恢复；原单行继承、源顺序、后续输入及保护检查保持。默认面板以半选显示混合行，点击后统一开关；独立 XML 检查两行 `cantSplit`、范围外整行源、八步混合历史、重开后的有效值、输入及 PDF。原长行流程暴露自动刷新查询挤占队列：一次诊断记录 48 个文字事件、另八次换行及队列峰值 64。标尺、目录和批注现通过既有 `whenIdle` 等待已接受输入，过期刷新直接退出。保留原长行输入速度、正文/PDF 断言及 64 项队列上限；三个面板的既有完整流程通过。首次复选框检查已改为点击后等待核心状态，保留初次及队列诊断失败记录，未削弱内容断言或增加超时/重试。新安装包通过 2477 项断言及严格宿主编译，根 api/check/build 与私有严格检查通过。未跑全量、外部 Office 或性能矩阵。证据归私有 `tableRangeRowSplitCheckpoint`；各阶段仍为部分交付。

P10 跨格边框面板通过 4 项定向核心检查、两条 Chromium 流程及 2483 项安装包断言。扩展既有边框和跨格用例，覆盖各侧共同／混合值、零宽共同值、合并格某侧分段差异、继承恢复、查询不改源，以及原边框冲突、保护和历史检查。默认面板检查混合侧、四格 16 条原生边框、nil 移除与继承删除、五个范围外格完整源、十一项混合历史、重开有效边框、输入和 PDF；共用单格/整表流程保持原 XML 与实际描边断言。核心和浏览器首次通过，根 api/check/build、私有严格检查及严格安装宿主编译通过。公用边框文案改为适用于单格和多格的名称，PPTX 用例只机械同步定位名称，未为文案增加运行检查。20 秒、零重试保持，未跑全量或外部 Office。证据归私有 `tableRangeBordersCheckpoint`；各阶段仍为部分交付。

P10 显式单元格矩阵复制/剪切通过 6 项定向核心检查、两条 Chromium 流程及 2491 项安装包断言。核心覆盖反选、完整单格、空段、格内 Tab/换行/引号、合并占位与未选主格保护、精确转义上限、旧 revision 和字段保护；既有纯文本复制与矩阵粘贴用例保持。新默认按钮流程检查真实剪贴板往返、目标增行扩列及格式、延迟写入前不清空、单格光标剪切完整内容、范围外源与部件、精确混合历史、重开输入和 PDF。首次核心失败为测试遗漏既有结束边界 affinity，另一次编译使用保留字；只修正测试，保留 affinity 失败记录。浏览器首次通过，根 api/check/build、私有严格检查及严格安装宿主编译通过。20 秒、零重试保持，未跑全量或外部 Office。证据归私有 `tableMatrixClipboardCheckpoint`；富文本、合并结构往返和完整阶段继续实施。

P12 表格行高与列宽编辑通过 6 项定向核心检查、两条 Chromium 流程及 2519 项安装包断言。新核心覆盖反向范围、单列、共同/混合值、整数 EMU、原单元格源、精确混合历史、合并跨度与内容适配、非法尺寸、总量和活动候选保护；原表格输入和整表变换用例保持。默认面板流程核对真实反向拖选、原生行列和外框尺寸、源间隙/未知网格属性、全部格源与其他部件、原生输入格式、三项精确历史、重开和 PDF。浏览器首次通过。初始核心检查只修正测试的选择比较、整数舍入预期和变换前的对象模式，保留失败记录。根 api/check/build、私有严格检查及严格安装宿主编译通过；20 秒、零重试保持。证据归私有 `tableSizeCheckpoint`，未跑全量或外部 Office；各阶段继续实施。

P11 结构化单元格剪贴板的两项新核心用例通过，四项既有填充/合并格式刷结果沿用各自通过记录。覆盖类型快照、源编辑后保持、跨表公式/格式/缓存、四种模式、转置公式/整行列/边框、合并、精确历史、重开及非法/旧 revision/未知扩展保护。新 Chromium 默认控件流程通过真实系统剪贴板、原生草稿、独立 XML、四项混合历史、重开输入及 PDF；既有原生输入/剪贴板/恢复流程也通过，分别保留报告。新安装包通过 2545 项断言及严格宿主编译。首次新浏览器输入含既有未知扩展，核心按原保护拒绝；改用独立普通工作表输入，另补未知扩展拒绝断言。随后发现可选公式被序列化为单元素数组，已在核心显式输出字符串或 null，并补序列化断言，未放宽 TS 校验。初期测试的比较、边框下标、错误码预期和构建入口遗漏均已修正，失败记录保留。根 api/check/build、私有严格检查通过；20 秒、零重试不变。证据归私有 `cellClipboardCheckpoint`，完整阶段、剪切移动及规则资源复制继续实施；未跑全量或外部 Office。

P11 普通矩形剪切移动通过两项新核心用例、两项既有结构化剪贴板用例、两条 Chromium 流程及 2551 项安装包断言。新核心覆盖重叠、跨表公式和局部名称语义、绝对及部分相交引用、内部链接、共享公式展开、合并便笺、原源保留、精确历史和重开重算；非法范围、旧 revision、相对名称及未知规则资源整体拒绝。默认按钮和原生剪切/粘贴检查真实剪贴板延迟写入、源格保留、消费与重开后过期、禁止选择性剪切、独立 XML、撤销/重做、重开输入和 PDF。核心初期只修正测试语法及 XML 转义预期，新增浏览器保护检查只修正步骤顺序，保留失败证据。根 api/check/build、私有严格检查与安装宿主编译通过。未跑全量或外部 Office；规则资源及跨表便笺/相对名称等移动组合继续实施。证据归私有 `cellMoveCheckpoint`，阶段仍未全部完成。

P11 带链接剪切移动的两项新核心用例通过，五项既有移动/链接用例复用各自通过结果；三条 Chromium 流程及 2551 项安装包断言通过。新检查覆盖重叠内链只变换一次、跨表关系新建/复用与身份冲突、目标裁剪、提示/显示文字、命名空间与注释、精确新增部件历史、重开导航/输入及 PDF。部分源链接、未知属性、锁定与输出预算失败保持文档、部件和历史。首次新核心预期遗漏既有计算链输出清理，已补独立的精确声明差异预期，失败记录保留；未修改保存代码或放宽资源保护。根 api/check/build、私有严格检查及安装宿主编译通过。证据归私有 `cellMoveLinksCheckpoint`；未跑全量或外部 Office，完整阶段及其他资源组合继续实施。

P11 跨表便笺移动的两项新核心用例通过，七项既有移动/链接/便笺用例复用通过记录。覆盖富文本与作者、guid、VML 本地身份/形状类型/外观、空格便笺、缺失资源和仅文字导入、范围外源、精确混合历史、重开及身份/未知源/输出失败回滚。初次核心发现 VML 子节点修改未换算为外框偏移，已修正调用并保留失败记录。新旧两条 Chromium 流程在最终产物通过真实剪切、独立 XML、角标提示和无障碍描述、三项精确历史、重开编辑及 PDF 便笺排除。既有流程首次出现面板未应用文字丢失，诊断只确认时序敏感，未直接捕获清空顺序；面板改为布局阶段同步后，撤去诊断并保留全部原断言通过。2551 项安装包断言及严格宿主/私有检查通过，包结果复用于最后的局部 React 同步调整，分别保留包和最终产物哈希；核心与 Worker 未变化。根 api/check/build、UI/example 构建及最终严格检查通过。证据归私有 `cellMoveNotesCheckpoint`；未跑全量或外部 Office，完整阶段继续实施。

P12 原生表格样式的四项新核心用例通过，六项既有表格/格式/合并用例复用通过记录。覆盖全表、条纹、首末行列、角格、直接文字覆盖、空区域、目录默认值、主题引用、单次背景及共享线、原生资源创建、其他表格保持、重复应用、精确混合历史、合并及字体/身份/源/输出失败。14 个常用预设、完整设置命令、查询和默认表单已接通。新 Chromium 流程在最终产物通过原生样式目录、独立 XML、三种底色和 3 点共享边像素、原生输入、两项精确撤销重做、重开及 PDF；原单元格格式流程保留通过记录。初次浏览器定位缺少显式标签，已沿现有控件补齐；初始 1 点边线像素受抗锯齿影响，改用另一预设的 3 点边线，保留精确白色断言及失败报告。新安装包通过 2563 项断言和严格宿主编译，根 api/check/build、私有严格检查通过。证据归私有 `pptxTableStyleCheckpoint`；未跑全量或外部 Office，更多样式及完整阶段继续实施。

P10 跨格行高通过九项定向核心检查，包含两项新增跨格用例及七项既有行高/尺寸/范围用例。检查共同／混合高度及模式、固定/最小/自动、无操作、完整单元格与范围外行源、反向选择、精确混合历史、原生输入、重开和布局；合并行组同时计算所改多行，600 点边距案例保留 48 点共同上限，超限与输出失败整体回滚。新 Chromium 流程通过真实反选、混合占位、两行 843 twip 固定值、自动恢复、未改格/行/注释/属性/部件、三步精确历史、重开输入及 PDF。原有最小/固定高度的两条默认面板流程通过，单格与跨格共用表单。首次新流程只因 XML 前缀预期失败，已改为按 Word 命名空间逐行核对数值，保留原模式和源断言及失败报告。2573 项安装包断言、严格宿主编译、根 api/check/build 及私有严格检查通过。证据归私有 `docxSelectedRowHeightCheckpoint`；20 秒、零重试保持，未跑全量或外部 Office，三个完整阶段继续实施。

P11 规则剪切移动通过十三项定向核心检查及新旧两条 Chromium 流程。覆盖同表重叠、跨表规则交集与目标裁剪、逐格及其他表引用、原生提示与目录计数、共享统计、独立 XML、规则底色、校验草稿拦截、精确混合历史、重开输入和 PDF。共享变换同时修正逐格拆分整条规则阈值及复制无关兄弟规则的问题，以实际阈值和完整统计样本核对。未知身份/公式、覆盖格工作量、受保护依赖与输出失败整体回滚。根 api/check/build 和私有严格检查通过，公开 API 与包清单未变，未重跑安装包、全量或外部 Office。证据归私有 `cellMoveRulesCheckpoint`，完整阶段继续实施。

P12 段落制表位通过十二项定向核心检查、新旧三条 Chromium 流程及 2605 项安装包断言。检查原生位置、左/中/右/小数点对齐的实际光标、72 点默认间隔、继承覆盖与恢复、混合查询、零间隔、源属性/注释/字符/范围外内容、精确历史和预算失败；默认面板保留原生草稿，接受 Tab 文本粘贴，并通过独立 XML、重开输入及 PDF。九项既有段落/列表/清除/表格文字用例及两条既有文字格式浏览器流程通过。根 api/check/build、严格宿主编译及私有检查通过。证据归私有 `pptxTabsCheckpoint`；未跑全量或外部 Office，完整阶段及样式级制表位改写继续实施。

P10 单元格富文本片段通过七项定向核心检查、两条 Chromium 流程及 2618 项安装包断言。新增三项核心用例检查源样式解析、混合字符/空段落、跨文档、完整合并覆盖与取消、扩展网格、无操作、精确历史和重开；原矩阵文字/粘贴用例保留独立预期。默认按钮检查自定义剪贴板、延迟写入后剪切、源变化后跨文档粘贴、独立原生属性、未改格/部件、原生输入、精确历史及 PDF。未知引用/断裂合并、未选矩形成员、部分目标合并、缺字体和输出预算保持原包；根 api/check/build、严格宿主编译与私有检查通过。首次跨文档测试补齐未保存文档切换和样式部件关系后通过，失败报告保留。证据归私有 `tableRichClipboardCheckpoint`；未跑全量或外部 Office，三个完整阶段与资源片段继续实施。

P11 单元格规则复制通过十三项定向核心检查、两条 Chromium 流程及 2629 项安装包断言。新增三项核心用例覆盖部分源规则的锚点、跨工作簿差异样式、缺失样式部件的联合创建、目标规则裁剪、选择性/转置语义、数据条共同阈值、精确历史和重开；复制后的新值沿新验证，格式粘贴保留导入无效值，后续输入仍受保护。新默认流程保留源快照，独立核对原生公式/差异样式/提示/容器与实际底色，验证原生错误草稿、精确撤销、重开和 PDF；原单元格剪贴板流程也通过。未知引用/元数据、无效几何、空白公式、缺字体和输出预算失败保留源。根 api/check/build、严格宿主编译和私有检查通过。首次新流程补齐既有 `calcPr` 重算标记的完整预期后通过，失败记录保留。证据归私有 `cellCopyRulesCheckpoint`；未跑全量或外部 Office，完整 P10/P11/P12 仍在实施。

## 独立执行档

现有 `test:performance`、`test:native-performance`、`test:cpu-profile` 延后，只有功能被卡死或资源问题阻断时才选择最小诊断。保持已有输入、历史、队列、布局和 Canvas 安全上限及释放检查。

`test:explore`、`test:isolation`、`test:office-candidates` 和 `test:replay` 分别用于扩展探索、本地 Docker 隔离、参考输入准备和干净检出诊断。需要对应任务时再用，不作为日常功能开发的固定步骤。Docker 不挂载凭据、HOME 或 socket，不上传私有文件。未启用的 CI 模板不算运行证据。

## 干净检出复现

复现安装或打包问题时使用新 checkout 与固定私有 gitlink，按开发文档安装依赖。如实记录已有系统工具和本地 URL 覆盖。文档修改使用现有环境完成 diff 和一致性检查。

P10 行内 OMML 横线分数通过 10 项定向核心测试，包含两项新分数用例及八项既有图形/图片回归。协议边界通过 3 项单元测试、203 个断言。两条 Chromium 流程检查分数与符号；分数检查实际横线像素、独立 Poppler PDF 的上下位置和居中、受保护点击后的停止/恢复、原 OMML、其他段落输入、精确历史及重开。根 api/check/build 和私有类型/静态检查通过；字体来源和完整许可登记在私有字体清单。未跑全量、安装包矩阵、外部 Office 或系统输入法验收；公式创建/编辑及完整数学排版仍待实现。

## 隐私与独立验收

所有第一方测试、输入、预期和详细报告保留在私有仓库；公开构建不依赖它们。本地可读 checkout 不属于盲测隔离。未经用户授权不上传、发布、提交或推送测试资产。

P10/P12 较大运算符与堆叠极限通过 23 项定向核心检查及两条 Chromium 流程。核心覆盖独立、行内、混排、缩小参数与缺数学字体时的原子失败；保留既有 DOCX/PPTX 公式回归。浏览器检查默认面板修改求和/积分的右侧与堆叠位置、实际 Canvas 轮廓像素、独立 HarfBuzz 普通字形高度、Poppler 参数坐标与 PDF 栅格、无操作、精确历史和重开编辑。协议沿用提交时已通过的 16 项单元测试、554 条断言；共享 display 布尔字段严格校验。公开 api/check/build 复用 `419c821c` 的通过结果，随后只改产品注释；私有严格检查、注册和文档链接检查通过。证据归私有 `naryDisplayCheckpoint`。未跑全量、安装包或外部 Office；三个阶段继续实施。

P11 MINIFS/MAXIFS 通过 8 项定向核心检查和 1 条 Chromium 流程。核心覆盖 22 项独立公式结果、条件交集、空条件与零、类型/错误、隐藏行、稀疏整列、范围形状、资源失败、名称/跨表依赖、前缀和填充、精确历史及重开，保留六项既有条件聚合和整轴回归。浏览器检查导入缓存重算、默认原生输入、值及条件变化、跨表缓存、精确混合历史、重开、独立 XML 公式与实际 PDF。根 api/check/build、私有严格检查及受影响格式检查通过，公开 API 未变。证据归私有 `conditionalExtremaCheckpoint`；未跑全量、安装包或外部 Office，三个阶段继续实施。

P12 更改形状类型通过 10 项定向核心检查、3 项 TS 测试（99 条断言）及 1 条 Chromium 流程。核心覆盖多选、组内修改、连接点重映射、默认调节值、无操作、精确历史、缺省几何覆盖、锁定/保留源/预算失败和重开，保留预设、文字适配及连接线回归。默认按钮检查身份/几何/外观/文字保持、原生输入、实际 Canvas/PNG 与独立 PDF 栅格、原生 XML、精确混合历史和重开继续修改。根 api/check/build、私有严格检查、注册及文档检查通过；证据归私有 `shapeTypeCheckpoint`。未跑全量、安装包或外部 Office；三阶段继续实施。

P12 闭合预设连接点扩展通过 11 项定向核心检查、3 项 TS 测试（110 条断言）及 1 条 Chromium 流程。独立坐标覆盖 20 种预设的原生顺序及越界保护，核心保留连接线、组合与端点手势回归。默认控件验证六点选择、调节值联动、类型修改的索引重映射、精确历史、重开和继续旋转。根 api/check/build 及私有严格检查通过；详细证据归私有 `connectionSitesCheckpoint`，取代此前仅三种形状连接点的范围限制。未跑全量或外部 Office；三阶段继续实施。

P10 SEQ 隐藏结果通过 7 项定向核心检查、4 项 TS 测试（288 条断言）及 1 条 Chromium 流程。核心覆盖隐藏后的计数、通用格式例外、空结果缓存与复制、无操作、精确历史、重开及既有序列回归。默认控件检查已有域隐藏、插入隐藏起点、后续编号、原生空缓存、其他部件保持、精确历史、重开输入、无残留字形及独立 PDF 文字。公开 api/check/build 与私有严格检查通过；详细证据归私有 `hiddenSequenceCheckpoint`。未跑全量、安装包或外部 Office；P10–P12 仍在实施。

P11 更换工作表图片通过 8 项定向核心检查及 1 条 Chromium 流程。共享资源隔离、三种锚点、裁剪/身份/文字保持、PNG/JPEG 原字节和 MIME、同字节无操作、精确历史、缺解码/锁定/预算失败与重开均有检查。默认文件控件验证原生草稿先提交、真实 Canvas 像素、独立 XML、保存重开和裁剪后的 PDF 栅格。公开 api/check/build 及私有严格检查通过；证据归私有 `xlsxPictureReplaceCheckpoint`。未跑全量、安装包或外部 Office；P10–P12 继续实施。

P12 字符间距通过 4 项定向核心、1 项 TS 测试（30 条断言）及 2 条 Chromium 流程。检查原生单位与舍入、继承恢复、局部/光标格式、混合查询、原子失败、精确历史、保存重开、母版默认间距和后续输入。实际 Canvas 墨迹及独立 PDF 坐标符合四字母间距差，XML 保留非目标源。母版流程发现并修复完整字符属性字段数漏改，补齐严格查询回归。公开构建、受影响严格检查、注册与文档检查通过；证据归私有 `pptxCharacterSpacingCheckpoint`。未跑全量、安装包或外部 Office；P10–P12 继续实施。

P11 导入自动行高首次测量通过 10 项定向核心及 1 条 Chromium 流程。核心覆盖字体高度、固定/隐藏/缓存/多行合并、命中、打印、只读源保持、预算失败、精确历史与重开，并保留八项适配和图片回归。默认宿主验证三行实际 Canvas 墨迹、共同查询与行位置、全部源部件保持、独立 PDF 行间位置、底部命中、原生输入和精确撤销。公开检查、API、构建及私有严格检查通过；证据归私有 `initialRowHeightCheckpoint`。首次测量沿用 4096 行、4096 格及文本工作上限。未跑全量、安装包或外部 Office；P10–P12 继续实施。

P11 普通工作表图表通过 2 项定向核心、1 项 TS 测试（27 条断言）及 2 条 Chromium 流程，含既有图片更换回归。检查当前公式与缓存、原生引用、注释保护、精确混合历史、实际 Canvas 数据联动、默认外观/尺寸/删除、重开输入及独立 PDF。浏览器发现并修复 Worker 请求编号与图表身份冲突；图片回归发现并修复候选资源缺少新媒体。公开检查、API、构建及私有严格检查通过；证据归私有 `worksheetChartCheckpoint`。结构引用维护、隐藏来源及复杂导入继续实施。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P11 工作表图表改名通过 3 项定向核心（含两项既有图表回归）和 2 条扩展 Chromium 流程。检查本表/跨表来源、中文及单引号转义、字面标题、源注释保留、引用内注释保护、精确历史、保存重开与后续输入/PDF。默认改名、复制和删除分别读取对应保护原因，既有图片工作表管理流程保持通过。公开检查、API、构建与受影响严格检查通过；详细证据归私有 `worksheetChartRenameCheckpoint`。未跑全量、安装包或外部 Office；P10–P12 继续实施。

P11 工作表图表复制通过 5 项定向核心（两项新增及三项图表/改名回归）和 2 条扩展 Chromium 流程。检查图表与图片共存、独立部件、本表引用重绑定、外表来源保持、锚点/文字、注释、重名避让、原子失败和精确混合历史。默认复制、独立公式缓存及标题、实际 Canvas、原图隔离、重开输入和独立 PDF 通过；既有图片工作表管理流程保持通过。公开检查、API、构建与受影响严格检查通过；证据归私有 `worksheetChartCopyCheckpoint`。未跑全量、安装包或外部 Office；删除表与行列图表引用维护等继续实施，P10–P12 保持实施中。

P11 工作表图表删除通过 7 项定向核心（两项新增及五项图表/改名/复制回归）、1 项接口测试（28 条断言）和 2 条 Chromium 流程。检查所属资源清理、跨表失效引用、缓存与有效系列联动、注释保护、未知入站引用、重新绑定、精确混合历史和重开。默认删除保留独立原生草稿历史，实际 Canvas、失效提示、标题编辑、引用重绑定、后续公式及独立 PDF 通过；既有图片表管理流程保持通过。公开检查、API、构建与受影响严格检查通过；证据归私有 `worksheetChartDeleteCheckpoint`。未跑全量、安装包或外部 Office；行列图表引用维护等继续实施，P10–P12 保持实施中。

P11 工作表图表整行整列插删通过 9 项定向核心（两项新增及七项图表/表管理回归）和 2 条 Chromium 流程。检查本表/跨表来源平移、扩大、缩小及完整删除后的失效缓存，三种锚点、当前公式、注释保护、范围预算、精确历史及重开。散点图回归修复提交重排误读旧单元格；默认行列按钮、独立输入草稿历史、实际 Canvas、原生缓存/锚点、重开输入与独立 PDF 通过，既有图片行列流程保持通过。公开检查、API、构建与受影响严格检查通过；证据归私有 `worksheetChartAxisCheckpoint`。未跑全量、安装包或外部 Office；含绘图目标的局部单元格插删等继续实施，P10–P12 保持实施中。

P11 普通工作表图表隐藏来源通过 12 项定向核心（两项新增、九项工作表图表及一项共用图例回归）和 2 条 Chromium 流程。检查类别/系列独立可见性、原始配色、空图、隐藏格公式、筛选与手动隐藏重叠、完整缓存、精确历史及重开。默认行高/列宽、原生输入草稿、实际 Canvas、原生引用与未知源、恢复显示后的输入以及独立 PDF 通过；既有图表行列流程保持通过。完整删除隐藏来源保持原子保护，等待可见缓存冻结。公开检查、API、构建与受影响严格检查通过；证据归私有 `worksheetChartVisibilityCheckpoint`。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P11 隐藏图表来源删除通过 14 项定向核心（两项新增及十二项扩展/既有回归）和 2 条 Chromium 流程。删除表及完整来源行后，独立可见缓存、零点系列、饼图原配色、空图、外观修改、重新绑定及精确历史通过。较长的有效系列继续重算，冻结值保持；普通矩阵校验及注释保护保留。默认删除与外观面板、实际 Canvas、保存重开、独立 PDF、原生零点缓存及既有普通删除/重新绑定通过。公开检查、API、构建与受影响严格检查通过；证据归私有 `worksheetChartFrozenCheckpoint`。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P11 带绘图工作表的局部单元格插删通过 19 项定向核心（15 项图表/共用绘制及 4 项图片轴检查）和 2 条 Chromium 流程。四向移位保留三种锚点、绘图源注释、资源字节和身份，同步本表/跨表引用、独立长度及失效缓存。混合精确历史、重开输入、超限原子拒绝和显式散点 X 空项通过；原生草稿、默认四向按钮、实际 Canvas 图表/PNG、原生绘图源不变与独立 PDF 通过，既有整轴图片流程保持。公开检查、API、构建与受影响严格检查通过；证据归私有 `drawingCellShiftCheckpoint`。未跑全量、安装包或外部 Office；复杂资源与后续能力继续实施，P10–P12 保持实施中。

P11 同表绘图复制通过 2 项定向核心、1 项扩展接口检查（20 条断言）和 1 条 Chromium 流程。检查三种锚点、零轴直线、源注释、图片共享字节、图表独立部件与外观、实时公式、精确混合历史、重开和原子拒绝。默认图片/图形/图表面板均选择副本，实际 Canvas、原生资源保留与独立 qpdf/Poppler PDF 通过。公开检查、API、构建与受影响严格检查通过；证据归私有 `drawingDuplicateCheckpoint`。未跑全量、安装包或外部 Office；系统剪贴板、跨表/跨工作簿转移和剪切继续实施，P10–P12 保持实施中。

P11 同工作簿绘图剪切通过 6 项定向核心（两项新增及四项绘图/整表复制回归）、1 项扩展接口检查（27 条断言）和 3 条 Chromium 流程。检查同表/跨表身份与资源归属、三种锚点、零轴直线、原来源图表引用、图片字节、源注释、精确混合历史、重开输入和原子拒绝。默认剪切/粘贴、对象与网格原生快捷键、剪贴板写入失败、旧标记拒绝、成功操作后的错误恢复、实际 Canvas 及独立 qpdf/Poppler PDF 通过；两条既有单元格剪切流程保持通过。公开检查、API、构建与受影响严格检查通过；证据归私有 `drawingCutCheckpoint`。未跑全量、安装包或外部 Office；系统剪贴板复制和跨工作簿绘图转移继续实施，P10–P12 保持实施中。

P11 可移植绘图剪贴板通过 6 项定向核心（两项新增及四项复制/剪切回归）、1 项扩展接口检查（35 条断言）和 2 条 Chromium 流程。检查三种锚点、零轴直线、源裁剪/注释、主题字体与颜色、源关闭后的快照、目标独立身份、精确历史、重开及原子拒绝。默认与原生复制/粘贴、跨工作簿资源、源图片更换后的原快照、源实例释放、重复粘贴、目标字体保留、实际 Canvas、目标未知源与独立 qpdf/Poppler PDF 通过；既有绘图剪切保持通过。公开检查、API、构建及受影响严格检查通过；证据归私有 `drawingFragmentCheckpoint`。未跑全量、安装包或外部 Office；图表系统复制与跨工作簿剪切继续实施，P10–P12 保持实施中。

P11 绘图边缘自动滚动通过 6 项定向核心（两项新增及四项图片回归）、1 项扩展接口检查（27 条断言）和 2 条 Chromium 流程。核心检查冻结区域内及跨区域、LTR/RTL 坐标、只读候选、无效滚动原子拒绝、单项精确历史及重开。浏览器使用冻结窗格中的真实鼠标拖动，检查双轴滚动、指针停留、Escape/手动滚轮取消、松手停止、图片候选 Canvas 像素、移动与图形缩放、精确撤销/重做及重开；既有图片指针、保存屏障、原生输入与独立 PDF 流程通过。公开检查、API、构建及受影响严格检查通过；证据归私有 `drawingScrollCheckpoint`。未跑全量、安装包或外部 Office，RTL 滚动换算的证据限于核心。P10–P12 保持实施中。

P10 普通题注通过 7 项定向核心（两项新增及五项序列字段回归）、2 项接口检查（94 条断言）和 2 条 Chromium 流程。核心检查缺少/已有题注样式、首次资源创建、正文与表格前后插入、独立计数/罗马编号、转义说明、原生输入、显式缓存、五步精确历史、重开及原子失败。默认面板和既有序列域流程检查所选内容保留、原生输入、插入后的重编号、表格外题注、独立 XML、四步精确撤销/重做、重开、实际 Canvas 题注颜色与独立 qpdf/Poppler PDF。题注使用实际斜体字体资源，缺字体继续拒绝。公开构建、检查、API 及受影响严格检查通过；证据归私有 `captionCheckpoint`。未跑全量、安装包或外部 Office，章节前缀和浮动题注框继续实施；P10–P12 保持实施中。

P10 已有脚注/尾注内容通过 2 项定向核心、1 项接口检查（17 条断言）和 1 条 Chromium 流程。检查同种身份、引用数量、缺失内容、普通/空内容、首尾空白、原标记/样式/分隔符、正文及其他 ZIP 部件、四步核心与两步浏览器精确历史、重开，以及结构/跟踪属性、身份/关系、过期状态和聚合预算失败。默认面板、过期目录、并发同源拒绝后继续编辑，以及受保护目录查询后继续读取批注和原格式保存通过。公开构建、检查、API 及受影响严格检查通过；证据归私有 `nativeNotesCheckpoint`。本次未验证脚注页底/尾注分页或其 Canvas/PDF，创建、引用输入与分页仍待接入。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P10 普通注释布局通过 4 项定向核心（两项新增及两项内容回归）、3 项接口检查（234 条断言）和 2 条 Chromium 流程。检查引用页底预留、页边界搬移、长脚注完整续排、文末尾注、原生默认及罗马/字母编号、普通表格、动态页脚与最终页数、只读独立身份、缓存前后几何、内容缩短后的重排和缺字体原子拒绝。浏览器检查全部注释文字、正文边界、蓝色 Canvas 像素、独立 qpdf/Poppler 页数与完整文字、默认面板修改、精确撤销/重做、其他 ZIP 部件及重开；既有受保护目录和失败恢复流程保持通过。公开检查、API、构建及受影响严格检查通过，证据归私有 `notesLayoutCheckpoint`。多栏、超高含脚注表格分片、复杂注释和完整分隔符保真仍待接入。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P10 普通注释创建/删除通过 4 项定向核心（两项新增及两项布局回归）、1 项接口检查（29 条断言）和 2 条 Chromium 流程。检查所选文字保留、同段重复插入、普通表格、原生身份/关系/内容类型/分隔符、六步核心与四步浏览器精确历史、重开，以及缺字体、无效位置、文档保护和其他 Word 区域引用的原子拒绝。默认入口、过期目录拒绝后继续操作、其他 ZIP 部件、删除最后引用后原生输入和独立 qpdf/Poppler PDF 文字通过；既有受保护目录与失败恢复流程保持通过。公开检查、API、构建及受影响严格检查通过，证据归私有 `noteCreateCheckpoint`。含引用段落的范围输入、删除键、剪贴板及注释区域光标仍待接入。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P10 普通注释引用输入通过 4 项定向核心（两项新增及两项创建/删除回归）和 2 条 Chromium 流程。检查两类引用旁的基线输入、同段 PAGE 共存、拆段合并、反向范围替换及同步内容清理。组合输入预览不提交资源，取消恢复原源，最终提交纳入一项精确历史；结构化内容删除保持原子拒绝。浏览器覆盖原生键盘、组合事件、五步精确撤销/重做、原生 ZIP 内容、重开和独立 qpdf/Poppler PDF 文字；既有创建/删除流程保持通过。公开检查、API、构建及受影响严格检查通过，证据归私有 `noteInputCheckpoint`。富文本剪贴板、跨单元格删除、注释区域光标及复杂排版继续实施。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P10 普通注释引用格式通过 12 项定向核心（一项新增、两项引用输入回归及九项既有格式检查）和 2 条 Chromium 流程。检查两类引用的字符属性、反向范围、段落/列表格式、混合查询、基线待输入格式、混合 run 边界拆分、单格格式、内容部件保留、精确历史及重开。默认控件、蓝色 Canvas 像素、独立原生 XML、五步精确撤销/重做、重开和独立 qpdf/Poppler PDF 文字通过；既有引用输入/组合流程保持通过。公开检查、API、构建及受影响严格检查通过，证据归私有 `noteFormatCheckpoint`。跨格注释格式、注释剪贴板转移、注释区域光标和复杂排版继续实施。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P10 普通注释引用剪贴板通过 9 项定向核心（两项新增、两项创建/删除、两项既有正文片段及三项引用输入/格式/组合回归）和 2 条 Chromium 流程。检查两类注释、显示编号、混合颜色/字号、只读资源预检、首次同时创建资源、重复粘贴独立身份、覆盖引用时清理原内容、三步精确资源历史、源剪切及重开。无内容引用、错误种类/标记、缺字体及其他 Word 区域共享的剪切原子拒绝。系统复制/剪切、保留源格式粘贴、原生重复粘贴、独立 XML、未改 ZIP 部件、重开和独立 qpdf/Poppler 完整注释文字通过；既有正文图片、链接、书签及 Canvas/PDF 像素流程保持通过。公开检查、API、构建及受影响严格检查通过，证据归私有 `noteClipboardCheckpoint`。注释列表、跨格注释片段、注释区域光标及复杂排版继续实施。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P10 注释跨格操作通过 7 项定向核心（两项新增、三项既有内容输入及两项单元格富文本检查）和 2 条 Chromium 流程。检查反向端点整格选择、格式/底色、首格输入与组合、整组选区删除、范围外源和注释内容保留、结构化内容原子拒绝、双种类片段、覆盖原引用、扩展网格、TSV 显示同值文字化及精确资源历史。浏览器覆盖指针与无障碍数量、格式控件、系统复制/剪切、原生粘贴、组合取消、四步精确混合历史、独立 XML/ZIP、重开及独立 qpdf/Poppler 注释文字。既有 PNG/JPEG 表格资源、写失败恢复和 Canvas/PDF 像素回归通过；其剪贴板等待改为检查本次实际图片载荷，保留原断言。公开检查、API、构建及受影响严格检查通过，证据归私有 `noteTableCheckpoint`。含引用格的结构命令、注释区域光标及复杂排版继续实施。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P10 注释表格结构操作通过 5 项定向核心（两项新增及三项既有合并/列宽回归）和 2 条 Chromium 流程。行列增删、合并/取消合并、拆格、尺寸、自动适配和拆表保留原注释归属，新空格保持基线格式；删除列及最后一行清理普通内容，结构化内容与缺字体原子拒绝。九步核心与六步浏览器混合历史精确恢复源和资源。默认控件、独立 XML/ZIP、重开和独立 qpdf/Poppler 剩余及已删内容检查通过；既有跨格输入、组合、无障碍选择和剪贴板流程保持通过。公开检查、API、构建及受影响严格检查通过，证据归私有 `noteStructureCheckpoint`。搜索选择、含引用正文中新建表格、注释区域光标和复杂排版继续实施。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P10 注释正文命令通过 10 项定向核心（两项新增、两项既有表格创建、三项搜索及三项注释输入/格式/组合回归）和 2 条 Chromium 流程。含引用正文新建表格保留两侧归属或同步清理所选内容，新空格与折叠查询保留基线和显式待输入格式。正文/普通格搜索保留引用后的逻辑偏移，不跨过引用匹配；普通、跨段和批量替换保留内容与精确资源历史，结构化删除和缺字体原子拒绝。默认搜索/替换、新建表格、原生格内输入、五步精确历史、独立 XML/ZIP、重开和独立 qpdf/Poppler 文字通过；既有表格结构流程保持通过。公开检查、API、构建及受影响严格检查通过，证据归私有 `noteBodyCheckpoint`。注释区域光标、富内容及复杂排版继续实施。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P10 普通多段注释通过 17 项定向核心（两项新增及受影响的目录、创建、输入、剪贴板、表格与正文归属回归）、1 项接口检查（31 条断言）和 3 条 Chromium 流程。检查 LF 和首尾空段、仅有标记及自闭合空段、空白、原样式/源注释、追加/收缩、独立副本与后续修改、普通内容删除、精确资源历史，以及字段/不透明内容、无效字符、预算和缺字体的原子拒绝。默认多行控件、系统剪贴板、四步浏览器精确历史、独立 XML/ZIP、重开语义和独立 qpdf/Poppler 文字通过。最后补充实际剪贴板载荷等待后，仅重跑该流程并通过。公开检查、API、构建及受影响严格检查通过，证据归私有 `noteParagraphCheckpoint`。注释区域光标、富文本范围编辑和复杂排版继续实施。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P11 普通图表系统复制通过 7 项定向核心（三项新增、两项既有绘图片段及两项工作表图表复制回归）和 2 条 Chromium 流程。检查公式当前值快照、不同来源长度与可见性、三种锚点、散点数值轴、饼图配色、全隐藏数据、独立重复粘贴与后续数据修改、精确历史和重开。损坏载荷、资源混用、复制锁、缺字体、结构保护及输出预算原子拒绝。默认复制/粘贴、源修改与关闭、原生粘贴和输入、数据表显示、四步精确混合历史、独立 XML/ZIP、重开 Canvas 像素及独立 qpdf/Poppler 可见文字通过；既有图片/图形快照流程保持通过。公开检查、API、构建及受影响严格检查通过，证据归私有 `chartFragmentCheckpoint`。跨工作簿剪切、附加图表资源及更广原生变体继续实施。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P12 文字富文本剪贴板通过 6 项定向核心（两项新增及四项既有矩形/合并表格回归）、1 项接口检查（18 条断言）和 2 条 Chromium 流程。检查混合字符/段落/列表格式、制表位、反向选区、边界源、单主格、独立重复粘贴、精确历史及重开。损坏载荷、缺字体、旧 revision、活动候选、跨格及冲突继承制表位原子拒绝。默认 Copy/Cut、写失败保护、源修改/关闭、跨主题源格式、原生粘贴/输入、三步精确历史、独立 XML/ZIP、重开语义、Canvas 像素和独立 qpdf/Poppler 文字通过；既有表格文字格式流程保持通过。最后补充继承制表位保护后，仅重跑新浏览器流程并通过。公开检查、API、构建及受影响严格检查通过，证据归私有 `textFragmentCheckpoint`。对象资源、跨格及字段/公式、具体幻灯片目标和悬停链接转移继续实施。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P12 文字链接剪贴板通过 10 项定向核心（四项富文本及六项既有文字/对象链接回归）和 1 条扩展 Chromium 流程。多地址分配、同地址复用、导航动作、引号转义、提示/窗口/标记、源关闭、独立链接修改、精确资源历史及重开/再次复制通过。无效地址/动作/元数据、外来关系、缺字体和输出预算原子拒绝；具体幻灯片目标继续保护。默认系统复制/剪切、原生粘贴/输入、跨主题源格式、四步精确混合历史、独立 XML/ZIP、重开语义、Canvas 像素和独立 qpdf 链接/Poppler 文字通过，复制和粘贴没有请求外链。公开检查、API、构建及受影响严格检查通过，证据归私有 `textLinkFragmentCheckpoint`。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P12 对象剪贴板通过 6 项定向核心（两项新增及四项既有文字富文本回归）、1 项接口检查（32 条断言）及对象和文字两条 Chromium 流程。组合、主题外观、原生图片字节、裁剪/旋转、点击链接、独立重复粘贴、原生输入、源修改/关闭、三步精确资源历史和重开通过。复制锁、损坏/多余资源、不安全引用、缺字体、旧 revision、活动手势和输出预算原子拒绝；浏览器坏图片在提交前拒绝。独立 XML/ZIP 保留原有部件，只增加两份预期图片，重开 Canvas 像素和 qpdf/Poppler 通过，没有请求外链。首次对象浏览器用例误用了要求部件清单不变的检查；补入明确数量和字节的预期图片后，仅重跑对象流程并通过，文字回归复用已通过结果。公开检查、API、构建及受影响严格检查通过，证据归私有 `objectFragmentCheckpoint`。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P12 整表剪贴板通过 8 项定向核心（两项新增、两项既有对象剪贴板及四项表样式回归）和 1 条 Chromium 流程。合并网格、边距/锚定、主题字体/颜色、区域与直接边框优先级、点击链接、首次样式目录和多表样式/图片混合资源、独立重复粘贴、三步精确混合历史、重开后输入和插行通过。外来样式引用、损坏样式/网格和缺字体原子拒绝；既有保护与预算用例保持通过。默认 Copy/Cut、源修改/关闭、跨主题源格式粘贴、原生重复粘贴与输入、独立 XML/ZIP、重开 Canvas 和 qpdf/Poppler 通过，未请求外链。公开检查、API、构建及受影响严格检查通过，证据归私有 `tableFragmentCheckpoint`。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P12 图表剪贴板通过 6 项定向核心（两项新增、两项既有图表复制及两项整表剪贴板回归）和 1 条 Chromium 流程。柱图、圆环和散点快照保留数值/空点、字面标签、图例及孔径，多图独立资源、已有框链接、源关闭、分别修改、三步精确混合历史及重开通过；既有复制用例覆盖十二种图表。源工作簿含私有活动表时仍读取首个数据表，输出只含快照数据。损坏缓存/引用、注释、不一致工作簿、缺字体及输出预算原子拒绝。最后补充多字节标签容量检查后，只重跑新增两项核心并通过。默认 Copy/Cut、源修改/关闭、原生重复粘贴、图表面板修改、独立 ZIP/XML 与工作簿检查、重开 Canvas 和 Poppler 文字通过。公开检查、API、构建及受影响严格检查通过，证据归私有 `pptxChartFragmentCheckpoint`。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P11 三种条件格式图标集通过 7 项定向核心（1 项新增及数据条/色阶各 3 项回归）、6 项传输检查（170 条断言）和 1 条 Chromium 流程。检查数字/公式样本、阈值等值、反向、停止优先级、非法设置保护、精确历史、原生保存和重开。默认控件、仅显示图标时的无障碍数值、实际 Canvas 与独立 Poppler 图标及文字通过。API、公开检查、构建及受影响严格检查通过，证据归私有 `conditionalIconsCheckpoint`。未专项复验复制/结构/RTL 流程，未跑全量、安装包或外部 Office；其他图标与扩展规则继续实施，P10–P12 保持实施中。

P12 普通图表组合通过 5 项定向核心（1 项新增及组合/图表复制各 2 项回归）和 1 条 Chromium 流程。检查组缩放/旋转/翻转、原生独立资源、完整组快照、成员边界、取消组合矩阵、缺字体保护、精确混合历史与重开。默认组合/复制/粘贴/取消组合/图表数据面板、独立 ZIP/XML 与工作簿数量、取消组合前后双向 Canvas 像素、重开像素及独立 Poppler 文字通过。原生组复制曾共享子图表资源，现按全部复制身份分配与检查；旧未知形状用例换为实际未支持的标注形状，保留保护断言。API、公开检查、构建与受影响严格检查通过，证据归私有 `chartGroupCheckpoint`。未跑全量、安装包或外部 Office；组内表格、直接图表旋转控件和组内数据编辑继续实施，P10–P12 保持实施中。

P12 普通表格组合通过 6 项定向核心（1 项新增、2 项表格变换、1 项图表组合及 2 项整表复制回归）和 1 条 Chromium 流程。检查缩放预览/源重读网格、组内输入增高、本地行高与外框之和、祖先边界、样式、取消组合姿态、后续输入/插行、精确混合历史与重开。极小导入组保持诊断、复制保护和原包字节；补入该保护后仅重跑新增核心。默认组合/系统复制/粘贴/取消组合及原生输入、独立原生表/样式/行数、取消组合前后双向 Canvas 像素、重开像素和独立 Poppler 文字通过。API、公开检查、构建与受影响严格检查通过，证据归私有 `tableGroupCheckpoint`。未跑全量、安装包或外部 Office；组内表结构/格外观控件等继续实施，P10–P12 保持实施中。

P12 组内表格外观与表样式通过 9 项定向核心（扩展既有组合用例、2 项格外观、4 项表样式及 2 项文字格式回归）和 1 条扩展 Chromium 流程。新增字符/段落编辑后，仅重跑组合与文字格式共 3 项，复用其他通过结果。检查格外观、字体、原生段落间距、组内样式、行高/组边界、原生快照、精确历史、重开及组文字锁原子保护。默认样式和填充控件已启用，结构插行保持禁用；原生 XML、实际填充像素、取消组合像素及重开/PDF 保持通过。API、公开检查、构建和受影响严格检查通过，证据归私有 `tableGroupFormatCheckpoint`。未跑全量、安装包或外部 Office；组内结构与行列尺寸控件仍待接通，P10–P12 保持实施中。

P12 组内行高/列宽通过 5 项定向核心（扩展组合用例及尺寸/变换各 2 项回归）、1 项传输检查（140 条断言）和 1 条扩展 Chromium 流程。非等比缩放换算、放大组的小本地列宽、行高适配、锁定拒绝、精确历史和重开通过。小数组缩放下重用显示值曾错误新增一次历史；修复后仅重跑扩展核心，确认源字节及 revision 不变。默认行列尺寸控件启用、结构插行保持禁用，原生 XML/像素、精确撤销、重开和独立 PDF 保持通过。API、公开检查、构建及受影响严格检查通过，证据归私有 `tableGroupSizeCheckpoint`。未跑全量、安装包或外部 Office；组内结构控件继续实施，P10–P12 保持实施中。

P12 组内表格结构通过 8 项定向核心（新增结构组合、既有组合及插删/合并/拆格各 2 项）和 2 条 Chromium 流程。检查非等比缩放及旋转/翻转、插删、合并/取消合并、拆格、整表删除、兄弟成员页面姿态、有效网格、原包精确撤销/重做、继续输入、重开、空操作、预算与组锁定保护。新流程使用默认结构控件，检查八步精确历史、独立 XML 网格数、重开 Canvas 与 Poppler 全文；既有组合复制/样式/尺寸流程首轮通过后复用结果。新增测试设置曾保留创建前的旧编辑器并写错列按钮标签，现已修正；拆格换行的 PDF 按完整去空白文字检查。API、公开检查、构建与受影响严格检查通过，证据归私有 `tableGroupStructureCheckpoint`。未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P12 组内图表数据通过 5 项定向核心（扩展组用例及基础图表/复制各 2 项）和 1 条扩展 Chromium 流程。检查非等比缩放与旋转/翻转后的数据编辑、原生组源和兄弟姿态不变、独立工作簿、同值无历史、非法数据原子拒绝、组选择/文字锁、仅缩放锁允许数据编辑、共享图表拒绝、后续取消组合及精确混合历史。默认数据面板、chartDataReason 传输保护、五步精确撤销/重做、独立 ZIP/XML/工作簿数、取消组合像素、重开 Canvas 和独立 PDF 通过。API、公开检查、构建及受影响严格检查通过，证据归私有 `chartGroupDataCheckpoint`。复用既有用例，未跑全量、安装包或外部 Office；P10–P12 保持实施中。

P11 箭头图标级数扩展通过 2 项定向核心（既有三种图标及新增五种箭头集）、6 项传输检查（191 条断言）和 1 条扩展 Chromium 流程。检查三/四/五级数量、原生方向、灰色/彩色路径、阈值等值、反向及未命中索引零、跨工作簿值/规则复制、精确历史和重开。默认面板切换级数会重置百分比草稿，同级彩色/灰色保留自定义阈值；五行实际 Canvas、无障碍数值、独立五节点 XML、两步精确撤销/重做、重开像素及 Poppler 灰色图标/隐藏值通过。API、公开检查、构建与受影响严格检查通过，证据归私有 `conditionalArrowLevelsCheckpoint`。未跑全量、安装包、专门结构/RTL 流程或外部 Office；其他图标与扩展规则继续实施，P10–P12 保持实施中。

P11 基础标准图标集补齐通过 3 项定向核心（覆盖全部 17 种）、6 项传输检查（218 条断言）和 2 条 Chromium 流程。新增九种符号/交通灯/评级/四分圆沿原阈值、原生保存及剪贴板事务；检查级别、符号笔画、评级填充根数、四分圆弧数、反向、跨工作簿重开及精确历史。实际 Canvas 显示全部新增类型，评级与四分圆逐级增加墨迹，默认四分圆反转保留其他列；原生 XML/ZIP、无障碍数值、精确撤销/重做、重开像素及独立 Poppler 图标/隐藏值通过。API、公开检查、构建及受影响严格检查通过，证据归私有 `conditionalStandardIconsCheckpoint`。未跑全量、安装包、专门结构/RTL 流程或外部 Office；x14 自定义图标及扩展规则继续实施，P10–P12 保持实施中。

P10 公式范围字体通过 5 项定向核心（新增嵌套范围及周边格式/显式公式外观各 2 项）和 2 条 Chromium 流程。检查正文与普通格的继承/显式公式、混合与反向选区、字体/字号/RGB 色、同值无历史、其他格式保护、缺少字体上下文或映射的原子失败、继续输入、完整布局、精确混合历史及重开。默认控件分别使用 fontReason 与原通用原因，传输拒绝缺失/非字符串字段；四步精确历史、独立 OMML/ZIP、重开 Canvas 和独立 PDF 通过。补入字体预检后重跑五项核心及两条浏览器；最后修正已有 m:rPr 后插入 w:rPr 的顺序，只重跑新增继承/显式核心用例，复用其余结果。API、公开检查、构建及受影响严格检查通过，证据归私有 `mathRangeFontCheckpoint`。未跑全量、安装包或外部 Office；局部/混合数学格式及其余 P10–P12 能力继续实施。

P10 含公式选区段落格式通过 3 项定向核心（扩展范围用例及周边格式 2 项）和 2 条既有 Chromium 流程。检查完整/反向选区、实际段落值、对齐与缩进、公式内部源不变、同值无历史，以及光标位于含公式段落时缺少字体映射的原子拒绝。默认段落控件与 paragraphReason 传输保护、六步精确撤销/重做、独立原生 XML/ZIP、重开 Canvas 和独立 PDF 通过。API、公开检查、构建及受影响严格检查通过，证据归私有 `mathRangeParagraphCheckpoint`。复用其余已通过结果，未跑全量、安装包或外部 Office；局部/混合数学格式及其余 P10–P12 能力继续实施。

三种 Office 格式的堆积/百分比堆积面积图通过 11 项定向核心（新增三种格式用例，回归普通面积、堆积柱条及基础图表）与 3 项传输检查（218 条断言）。检查正负值的代数累计、前后色带、空值零带、极大有限值的百分比、数值/字体原子拒绝、正文/普通格、XLSX 公式缓存、原生工作簿、精确历史和重开。2 条 Chromium 流程检查普通面积回归与新增默认控件、独立 XML 分组/原值/系列名、未改 ZIP 部件、两步精确历史、重开 Canvas、PNG 和独立 Poppler 百分比轴/像素。新增流程先修正图例标签，再把隐藏图例的 PDF 文字检查改为实际可见标题/轴/类别，系列名独立核对原生 XML。公开 API、检查、构建及受影响严格检查通过，证据归私有 `stackedAreaCheckpoint`。未跑全量、安装包或外部 Office；其他图表样式与 P10–P12 能力继续实施。

P11 图标排序通过 6 项定向核心（新增 2 项，复用颜色及排序元数据各 2 项回归）、1 项传输检查（73 条断言）和 1 条 Chromium 流程。检查显示图案身份、反转、优先级/停止规则、同轴多图标、无图标、行/列与原生表排序、公式/依赖、隐藏记录、便笺/链接、原样式、原生条件、无效元数据保护、行插入后的引用、同值无历史及精确撤销/重做。默认控件、原生输入、独立 XML、未改 ZIP 部件、实际绿色图案、三步精确历史、重开后输入及独立 Poppler 文字顺序通过。浏览器用例改为显式查询完整选区，修正控件标签，并按 option.value 选择与显示编号不同的图案索引。API、公开检查、构建及受影响严格检查通过，证据归私有 `iconSortCheckpoint`。未跑全量、安装包或外部 Office；图标筛选及其余 P10–P12 能力继续实施。

P11 图标筛选通过 6 项定向核心、2 项传输检查（158 条断言）和普通区域/原生表两条 Chromium 流程。覆盖实际图案、反转和停止规则、无图标、多列交集、手动隐藏、SUBTOTAL、原生输入后重新应用、结构维护、原样式、独立 XML、精确历史、重开及独立 Poppler PDF。复查共用图案匹配的图标排序与颜色筛选。API、公开检查、构建及受影响严格检查通过，证据归私有 `iconFilterCheckpoint`。未跑全量、安装包或外部 Office；复杂筛选及其余 P10–P12 能力继续实施。

P12 媒体对象剪贴板通过 4 项定向核心（新增 2 项，复用普通对象剪贴板 2 项回归）、1 项传输检查（46 条断言）及 1 条 Chromium 流程。覆盖音视频原字节/封面、独立重复粘贴、标准双关系、循环/音量/静音、超过旧上限的媒体、无效输入/输出预算、剪切失败保留、精确历史、源关闭后粘贴、重开播放和独立 Poppler PDF 封面。首轮浏览器发现默认工具栏仍排除媒体；修正共同 Copy/Cut 条件后，在原超时和零重试下通过。API、公开检查、构建及受影响严格检查通过，证据归私有 `mediaClipboardCheckpoint`。未跑全量、安装包或外部 Office；源动画时序转移及 P10–P12 其余能力继续实施。

P10 文字水印通过 8 项定向核心（新增 2 项，复用页眉页脚及链接 6 项回归）、1 项传输检查（43 条断言）及 1 条 Chromium 流程。覆盖三个页眉变体、原生独立身份、普通文字与 PAGE 字段编辑、正文几何保持、背景颜色合成、保护及预算失败、精确混合历史、重开输入和过期表单。实际 Canvas、三页独立 Poppler 文字及像素检查通过。核心用例发现仅有水印的页眉错误预留距离；修正为空间只由普通页眉内容决定。补齐新 Wasm 文件的构建入口后，API、公开检查、构建和受影响严格检查通过，证据归私有 `textWatermarkCheckpoint`。未跑全量、安装包或外部 Office；图片水印、导入 VML/扩展水印及 P10–P12 其余能力继续实施。

P12 媒体占位符填充通过 4 项定向核心（新增 2 项，复用占位图片 2 项回归）、1 项传输检查（24 条断言）及 1 条 Chromium 流程。覆盖空媒体/内容槽的音视频填入、身份与版式源保留、封面适配、原生双关系、播放设置、版式重置、精确混合历史、重开播放和 PNG/独立 Poppler PDF 像素。文字、锁、类型、动作/扩展、候选、过期 revision、损坏资源和预算失败保留源及选择。浏览器首次把当前页 PDF 当作全稿使用页号；修正为实际第 1 页后，在原超时和零重试下通过。API、公开检查、构建及受影响严格检查通过，证据归私有 `mediaPlaceholderCheckpoint`。未跑全量、安装包或外部 Office；其余资源槽填入及 P10–P12 能力继续实施。

P11 透视表值显示方式通过 7 项定向核心（新增 2 项，复用列轴及自动小计 5 项回归）、1 项传输检查（107 条断言）及 1 条 Chromium 流程。覆盖总计/行/列百分比、指数、原始记录均值边际、多值混合模式、筛选、小计、零/空白/缺失交叉/错误、原生模式与格式、缓存保持、精确历史、重开输入和刷新。默认控件、实际网格百分比及指数、独立 ZIP/XML/格式代码和 Poppler 百分比文字通过。浏览器发现默认设置的字段顺序不匹配核心预览，导致创建禁用；统一构造顺序后通过。API、公开检查、构建及受影响严格检查通过，证据归私有 `pivotValueModesCheckpoint`。未跑全量、安装包或外部 Excel；父项/相对显示模式及 P10–P12 其余能力继续实施。

P11 父行/父列百分比通过 6 项定向核心（新增 2 项，复用基础显示方式与多级日期各 2 项）、1 项传输检查（109 条断言）及 1 条 Chromium 流程。覆盖直接父级原始记录、均值与求和混合、多值和两轴层级、隐藏小计、两套日期系统、原生 x14 声明、缓存保持、五步精确历史、删除恢复及重开刷新。未知/冲突扩展、保留注释、输出失败和重做保持已检查；普通模式可处理的千条深层记录在额外父级工作超限时拒绝。默认控件、实际百分比、独立 XML/ZIP、原生输入后刷新及 Poppler PDF 文字通过。API、公开检查、构建和受影响严格检查通过，证据归私有 `pivotParentValuesCheckpoint`。未跑全量、安装包或外部 Excel；其他相对显示模式及 P10–P12 其余能力继续实施。

P12 本地现代批注通过 7 项定向核心（新增 2 项，复用传统批注 3 项及页复制 2 项）、1 项传输检查（31 条断言）和 2 条 Chromium 流程（现代及传统各 1 条）。覆盖原生作者/GUID/嵌套回复、新格式创建、传统格式保持、文字/日期/状态/作者元数据、独立页复制、删除回收、六步精确历史及重开编辑。未知源、混合文字、缺失作者、共享归属和输出失败保留源及重做。默认面板、独立 ZIP/XML/内容类型、重开正文输入及 Poppler 静态 PDF 已检查。API、公开检查、构建及受影响严格检查通过，证据归私有 `modernCommentsCheckpoint`。未跑全量、安装包或外部 PowerPoint；更广现代文字、锚点、提及/解决状态操作及 P10–P12 其余能力继续实施。

P12 现代批注状态及原生入口通过 8 项定向核心（新增 1 项，复用现代批注 2 项、传统批注 3 项和页复制 2 项）、1 项传输检查（54 条断言）及现代/传统各 1 条 Chromium 流程。覆盖解决、重开、关闭及单独回复状态、四步精确历史、同值无历史、日期/文字/作者保持、复制状态与锚点重绑定、未知状态/入口/锚点和输出失败恢复。独立 XML 检查入口关系、作者必需字段、页面锚点及状态属性；正文输入后修改状态仍保留输入，Poppler 输出保持正文。API、公开检查、构建及受影响严格检查通过，证据归私有 `commentStatusCheckpoint`。首轮现代浏览器缺少输入焦点等待，补为现有输入法的焦点断言后，在原 20 秒超时和零重试下通过。未跑全量、安装包或外部 PowerPoint；对象/文字锚点、提及及 P10–P12 其余能力继续实施。

P10 图片水印通过 4 项定向核心（新增 2 项，复用文字水印 2 项）、1 项传输检查（67 条断言）及文字/图片各 1 条 Chromium 流程。覆盖三个页眉变体共享图片、原字节与独立身份、尺寸/透明度、正文几何保持、资源复用、文字互换/移除、精确混合历史、重开输入及过期表单。实际 Canvas 透明色、独立 ZIP/XML 和三页 Poppler PDF 像素及正文通过。浏览器发现位置图元缺少图片元数据，以及页眉缓存回收遗漏水印；修正共同布局和缓存路径后，在原超时和零重试下通过。API、公开检查、构建及受影响严格检查通过，证据归私有 `pictureWatermarkCheckpoint`。未跑全量、安装包或外部 Word；VML、多节和扩展水印及 P10–P12 其余能力继续实施。

P11 透视表累计值通过 8 项定向核心（新增 2 项，复用父级百分比、普通显示模式及多级日期各 2 项）、1 项传输检查（121 条断言）和 1 条 Chromium 流程。覆盖行/列及内外层基准、固定其他成员、小计/总计、累计均值、多值混合、缺失交叉、筛选、错误/溢出、两套日期系统、原生声明、缓存保持、精确历史和重开刷新。默认控件、实际网格数字、独立 ZIP/XML/格式、原生输入及 Poppler PDF 文字通过。修正桥接字段数量及派生 JSON 省略空基准的问题；重开后的虚拟网格先定位再检查。在原 20 秒超时和零重试下通过，API、公开检查、构建和受影响严格检查通过，证据归私有 `pivotRunningTotalCheckpoint`。未跑全量、安装包或外部 Excel；累计百分比、其他相对显示模式及 P10–P12 其余能力继续实施。

P11 累计百分比及升降序排名通过 6 项定向核心（新增 2 项，复用累计值和父级百分比各 2 项）、1 项传输检查（127 条断言）和 1 条扩展 Chromium 流程。覆盖父级原始聚合、固定其他成员、加权均值超过 100%、连续并列名次、空白/错误、零分母、原生 x14/基准/格式、缓存保持、精确历史和重开刷新。默认控件、七步精确历史、独立 XML、原生输入及 Poppler 百分比通过；浏览器首轮在原 20 秒超时和零重试下通过。API、公开检查、构建及受影响严格检查通过，证据归私有 `pivotAxisValuesCheckpoint`。未跑全量、安装包或外部 Excel；差值、指定基项方式及 P10–P12 其余能力继续实施。

P11 基项比较与指定父项百分比通过 6 项定向核心（新增 2 项，复用累计/排名及累计值各 2 项）、1 项传输检查（157 条断言）和 1 条 Chromium 流程。覆盖前后项/类型化成员、差值/比例/百分比差异、指定父级原始聚合、空白/错误/零、日期、基项消失后的索引重映射、原生声明、精确历史及重开刷新。默认控件、五步精确历史、独立 ZIP/XML/格式、原生输入和 Poppler 百分比通过；浏览器两轮均在原 20 秒超时和零重试下通过，末轮包含新增指定父项。分组标签消失时保留待刷新源并拒绝改指其他成员。API、公开检查、构建和受影响严格检查通过，证据归私有 `pivotBaseItemsCheckpoint`。未跑全量、安装包或外部 Excel；其余分析及 P10–P12 能力继续实施。

P12 水平文本框分栏通过 3 项定向核心（新增 1 项，复用文本框 2 项）、3 项传输检查（64 条断言）和 2 条 Chromium 流程（新增分栏及原有文本框各 1 条）。覆盖左右栏顺序、等宽和间距、逐栏流动、命中和跨栏导航、换行与不换行自动尺寸、缩小字体、复制属性、同值无历史、精确撤销、重开输入及输出失败保护。默认控件、独立原生 XML/ZIP 和 Poppler 栏坐标通过；原有流程继续覆盖混合边距、锚定、适配和 PDF。API、公开检查、构建及私有严格检查通过，证据归私有 `textColumnsCheckpoint`。未跑全量、安装包或外部 PowerPoint；竖排、文字变形及 P10–P12 其余能力继续实施。

P12 文字整体旋转通过 4 项定向核心（新增 1 项，复用文本框及分栏 3 项）、3 项传输检查（74 条断言）和 3 条 Chromium 流程（新增方向及已有文本框/分栏各 1 条）。覆盖原生两种方向、宽高与内边距交换、实际命中、水平光标、方向键、链接、换行与不换行适配、自动宽度增长、复制属性、精确历史及重开输入。独立 Poppler 字形坐标与横排参考框的旋转结果一致，qpdf 链接矩形覆盖旋转文字；原有流程继续检查分栏、缩小与形状适配。字符直排、独立角度及输出失败保持原保护。API、公开检查、构建及私有严格检查通过，证据归私有 `textDirectionCheckpoint`。未跑全量、安装包或外部 PowerPoint；东亚字符直排、保持直立和文字变形及 P10–P12 其余能力继续实施。

P11 行列成员筛选通过 6 项定向核心（新增 2 项，复用报表筛选和基项比较各 2 项）、1 项传输检查（159 条断言）和 1 条 Chromium 流程。覆盖行/列/报表交集、加权均值、原生隐藏项及页字段、全部可见时清除条件、空结果、缺失成员重映射、数值与多级日期分组、两套日期系统、派生层级和退役分组项保护、精确历史及重开刷新。默认控件、独立 XML/ZIP、原生输入及仅含结果区的 Poppler PDF 通过。浏览器首轮使用只读公式镜像导致等待，改用既有点击/键盘输入后在原 20 秒及零重试下通过。API、公开检查、构建及受影响严格检查通过，证据归私有 `pivotAxisFiltersCheckpoint`。未跑全量、安装包或外部 Excel；切片器/时间线自身连接与控件及 P10–P12 其余能力继续实施。

P11 原生切片器只读目录通过 6 项定向核心（新增 2 项，复用轴筛选和基项比较各 2 项）及 1 项传输检查。覆盖缓存、工作表和透视表身份解析，类型化成员与默认标志，外部、重复及不一致连接保护，未引用缓存原样保留，预算与源/历史不变。API、公开检查、构建和受影响私有严格检查通过，证据归私有 `slicerCatalogCheckpoint`。未新增浏览器或安装包验收，未跑全量；创建、筛选联动、绘制、时间线及 P10–P12 其余能力继续实施。

P11 切片器成员筛选通过 6 项定向核心（新增 2 项，复用目录和轴筛选各 2 项）、2 项传输检查（189 条断言）及 1 条 Chromium 流程。覆盖共享缓存的两张透视表、交叉成员状态、多控件同步、全选、待刷新源保留、数字和两套日期系统的分组缓存重建、后一个目标扩大失败、关联刷新/删除保护及精确历史/重做。默认控件、原生输入、保存重开、独立 XML/缓存字节、结果区 Poppler PDF 和未知扩展保护通过。首轮暴露自动行高与打印对关系元数据的整包拦截，修复后在原 20 秒超时和零重试下通过；实际绘图仍独立检查。API、公开检查、构建及受影响私有严格检查通过，证据归私有 `slicerFilterCheckpoint`。未跑全量、安装包或外部 Excel；创建、布局外字段、画布控件、协调刷新/删除、时间线及 P10–P12 其余能力继续实施。

P11 布局外切片字段通过 7 项定向核心（新增 1 项，复用切片联动、行列和报表筛选各 2 项）、2 项传输检查（192 条断言）及 2 条 Chromium 流程。筛选模型增加必需的 `report`，区分报表和成员条件；所有调用方直接更新。检查布局外字段的隐藏项、无 `axisPage/pageFields`、完整缓存与待刷新源保留、全选清除、精确历史、保存重开和断开连接保护。扩展既有切片流程到四个控件、三个缓存及三步历史，结果区 PDF 不含报表标题；原行列/报表默认流程继续通过。API、公开检查、构建、私有严格类型检查及受影响静态检查通过，证据归私有 `slicerUnusedFieldCheckpoint`。未跑全量、安装包或外部 Excel；创建、画布控件、协调刷新/删除、时间线及 P10–P12 其余能力继续实施。

P11 原生切片器绘制通过 7 项定向核心（新增 2 项，复用切片筛选 2 项及普通图表 3 项）、1 项传输检查（32 条断言）及扩展既有 Chromium 切片流程。14 种内置样式与独立解码的原生差异格式事实一致；三类锚点、兼容分支及 fallback 保留、原生标题/列数/行高/首项、渐变、筛选后重绘、精确历史、保存重开与打印通过。未知样式、兼容分支和失联控件保护打印；框编辑与未协调 fallback 的修改保护源和历史。浏览器检查实际 Canvas 颜色、共享缓存结果、原生切片器 PDF、绘图原字节及继续输入；首轮按钮被短视口裁剪，滚动到可见行后在原 20 秒及零重试下通过。原行列/报表流程仍通过。API、构建、公开/私有严格类型及受影响静态检查通过，证据归私有 `slicerDrawingCheckpoint`。未跑全量、安装包或外部 Excel；画布交互、标题按钮、滚动/悬停、自定义样式、创建、协调刷新/删除、时间线及 P10–P12 其余能力继续实施。

P11 切片器画布交互通过 7 项定向核心（新增 1 项，复用原生绘图、缓存筛选及普通绘图滚动各 2 项）、1 项传输检查（55 条断言）及扩展既有 Chromium 流程。覆盖可见成员与旧布局、单选/多选/清除、至少一项、精确历史、会话滚动、重做保留、保存重开、冻结/RTL 与被裁掉的滚动条。实际按钮、标题多选、Enter 清除、箭头/滚轮、Home/PageUp/PageDown 和成员焦点通过；滚动前后字节及 revision 不变。原共享缓存、待刷新源、输入、独立 XML、重开和 Canvas/PDF 检查继续通过。浏览器暴露负滚动量被桥接层拦截，以及默认 Shadow DOM 的焦点读取问题，修复后在原 20 秒超时和零重试下通过。API、公开检查/构建、严格类型和受影响静态检查通过，证据归私有 `slicerPointerCheckpoint`。未跑全量、安装包或外部 Excel；悬停、拖动选择/滑块、创建、协调刷新/删除、时间线及 P10–P12 其余能力继续实施。

P11 原生切片器创建通过 7 项定向核心（新增 2 项，复用画布交互 1 项、绘制及缓存筛选各 2 项）、1 项传输检查（69 条断言）及 2 条 Chromium 流程。默认面板创建、字段缓存复用、独立视图部件、名称转义、UID、无数据状态、精确混合历史和重开通过。源单元格继续输入及自动行高同步原生与平面后备变换，保留其余源；未知后备仍保护修改。重复名称、越界字段、无效尺寸和缺字体保留源及重做。独立 XML 与结果区 Poppler PDF 使用缓存值，保留待刷新源；既有画布筛选流程继续通过。API、公开检查/构建、私有严格类型及受影响静态检查通过，证据归私有 `slicerCreationCheckpoint`。未跑全量、安装包或外部 Excel；自定义样式、悬停/拖动选择、滑块拖动、框编辑、协调刷新/删除、时间线及 P10–P12 其余能力继续实施。

P11 原生切片器删除通过 6 项定向核心（新增 2 项，复用创建与绘制各 2 项）、1 项传输检查（75 条断言）及扩展既有 Chromium 创建流程。独立部件与共用部件中的控件删除、绘图兼容后备、工作表入口/关系/内容类型清理通过。最后一个可见控件删除后，布局外筛选、共享缓存、透视结果和待刷新源保持；重开后可创建控件复用该状态。旧 revision、失联名称及共享视图关系原子拒绝，精确历史和重做保持。默认删除按钮、独立 ZIP/XML、画布控件消失、撤销重做、重开与结果区 Poppler PDF 通过，沿原 20 秒超时和零重试。API、公开检查/构建、私有严格类型及受影响静态检查通过，证据归私有 `slicerDeletionCheckpoint`。未跑全量、安装包或外部 Excel；关联透视表刷新/删除、缓存回收、框编辑、时间线及 P10–P12 其余能力继续实施。

P11 透视表与切片缓存协调刷新通过 10 项定向核心（新增 4 项，复用缓存筛选、控件删除及普通报表筛选各 2 项）和扩展既有 Chromium 创建/删除流程。共享两表的源值、记录、结果、原生成员索引、缺失普通成员和各表独立条件一起更新；全选接纳新成员，后一张表扩张冲突保持整组源、历史和重做。多级日期、两套日期系统、原生日期值、最后一个控件删除后的刷新、无变化刷新、越界滚动偏移恢复及精确混合历史通过。默认刷新按钮将待刷新值 400 写入缓存与结果，独立 XML、视图部件字节、撤销重做、后续控件删除、重开及 Poppler PDF 通过。原生共享目录可读，沿原 20 秒超时和零重试。API、公开检查、最终构建、私有严格类型及受影响静态检查通过，证据归私有 `slicerRefreshCheckpoint`。未跑全量、安装包或外部 Excel；字段重映射、协调修改/删除、缓存回收、框编辑、时间线及 P10–P12 其余能力继续实施。

P11 关联透视表删除通过 10 项定向核心（新增 3 项，复用控件删除 2 项、普通透视编辑/删除/归属 3 项及缓存筛选 2 项）和扩展既有 Chromium 流程。删除共享表时保留另一张表、缓存/记录及待刷新源，剩余连接可继续筛选；最后一张表删除时清理相关控件和独占缓存。跨表控件与绘图一起移除，其他绘图、缓存和透视定义保持。后一个关联表隐藏时，整次操作保留全部源、选择、历史和重做。导入与会话创建的部件、单项精确历史和重开通过。默认“删除透视表及结果”、独立 ZIP/XML、空目录、撤销重做与重开通过；此前创建、原生输入、筛选、显式刷新及 PDF 继续通过，沿原 20 秒超时和零重试。修复了清理对切片关系元数据的误拦截，以及候选包级联删除时移除列表与内容类型不同步的问题。API、公开检查、最终构建、私有严格类型及受影响静态检查通过，证据归私有 `pivotLinkedDeletionCheckpoint`。未跑全量、安装包或外部 Excel；关联字段修改、框编辑、时间线及 P10–P12 其余能力继续实施。

P11 关联透视字段编辑通过 10 项定向核心（新增 2 项，复用普通透视编辑/删除/归属 3 项、协调刷新 3 项及缓存筛选 2 项）和扩展既有 Chromium 流程。第二张共享表调整行列及有序计数/求和值字段时，第一张表保留自身设置；待刷新值 200 经显式应用进入两表结果，部件身份和切片连接保持。移动到布局外的成员条件继续校验连接，重开可再次筛选，无变化应用不新增历史。后一个结果扩张冲突、旧修订、源范围变化及未连接条件保持全部源、历史和重做；第二张表的值标题大小写冲突也保留原字节与修订。默认面板添加计数字段、预览/应用、独立 XML 结果 1、原生控件字节、精确撤销重做及后续控件/透视表删除、重开与 PDF 通过，沿原 20 秒超时和零重试。API、公开检查/构建、私有严格类型及受影响静态检查通过，证据归私有 `pivotLinkedFieldsCheckpoint`。未跑全量、安装包或外部 Excel；关联源结构与分组映射、框编辑、时间线及 P10–P12 其余能力继续实施。

P11 关联源范围更新通过 10 项定向核心（新增 3 项，复用关联字段 2 项、普通透视编辑/删除/归属 3 项及缓存筛选 2 项）和扩展既有 Chromium 流程。扩大、缩小与跨表/列位置迁移一起更新原生来源、共享结果和切片成员；部件身份、各表条件及未使用的原源数据保持。被移出范围的已选成员保留并标记无数据，重新扩大后恢复结果。后一个结果区扩张冲突及标题变化保留整组源、选择、历史和重做。精确混合历史、重开后筛选与继续应用通过。默认面板应用 A1:D7，独立 XML 校验求和 430、计数 2 和原生来源范围；控件字节、撤销重做、后续删除、重开及 Poppler PDF 通过，沿原 20 秒超时和零重试。API、公开检查/构建、私有严格类型及受影响静态检查通过，证据归私有 `pivotLinkedSourceCheckpoint`。未跑全量、安装包或外部 Excel；关联列结构/分组映射、框编辑、时间线及 P10–P12 其余能力继续实施。

P11 切片器框属性编辑通过 7 项定向核心（新增 2 项，复用创建与绘制各 2 项及画布交互 1 项）、1 项传输检查（90 条断言）和扩展既有 Chromium 流程。三种锚定、位置和尺寸同步原生与已知兼容后备，保留控件/缓存/记录/透视定义、待刷新源和结果。相同属性、精确混合历史、重开后筛选与打印布局通过。旧修订、失联身份、无效尺寸、缺字体、原生控件/绘图锁、锚点注释和未知后备保留源、历史与重做。默认数值面板、独立 XML 坐标、其他 ZIP 条目不变、移动后的实际成员点击、精确撤销重做、重开及原结果 PDF 通过，沿原 20 秒超时和零重试。浏览器暴露的选择控件标签和通信 id 冲突已修复。API、公开检查/构建、私有严格类型及受影响静态检查通过，证据归私有 `slicerFrameCheckpoint`。未跑全量、安装包或外部 Excel；画布框拖动、时间线及 P10–P12 其余能力继续实施。

P11 切片器画布框手势通过 7 项定向核心（新增 2 项，复用框属性 2 项、成员交互 1 项及普通绘图滚动 2 项）、1 项传输检查（92 条断言）和扩展既有 Chromium 流程。冻结/RTL 的独立位移、只读候选、取消后的旧布局、自由/比例锁缩放、原生与兼容变换、全部非绘图部件不变及精确历史通过。隐藏标题的顶边、原生锁及未知后备保留源与重做。默认标题实际拖动、Escape 取消、抬笔提交、Shift 方向键、四角自由缩放、Delete 协调删除与完整撤销通过；成员点击、混合历史、保存重开和原结果 PDF 继续通过。原 20 秒超时和零重试保持。API、公开检查/构建、私有受影响严格类型、静态检查及源码行数通过，证据归私有 `slicerGestureCheckpoint`。未跑全量、安装包或外部 Excel，浏览器边缘滚动与 RTL 未重复验收；这些共用坐标路径由定向核心覆盖。时间线及 P10–P12 其余能力继续实施。

P11 原生时间线目录通过 4 项定向核心（新增 2 项，复用切片器目录 2 项）、1 项传输检查（18 条断言）和 1 条 Chromium 流程。独立日期/结果缓存、原生扩展 GUID、共享视图、源字段、粒度、显示开关、带小数的日期选区、连接和原生绘图保留通过。失联/外部关系、重复名称、错误角色/来源/内容类型、非法闰日和范围、旧 revision 与数量预算保持原子拒绝。默认只读详情、准确选区和连接、无新历史、完整保存字节、重开及切换普通工作簿为空目录通过，沿原 20 秒超时和零重试。输入由明确原生 XML 夹具生成，浏览器使用私有派生输入；不作为外部 Excel 兼容验收。API、公开检查/构建、严格类型、受影响静态检查、构建入口和 800 行限制通过，证据归私有 `timelineCatalogCheckpoint`。未跑全量、安装包或新增 PDF 验收；时间线绘制/创建/范围编辑及 P10–P12 其余能力继续实施。

P11 原生时间线基础绘制通过 6 项定向核心（新增 2 项，复用目录与切片器绘图各 2 项）、2 项传输检查（118 条断言）和 1 条 Chromium 流程。三类锚点、a15 兼容后备、年/季/月/日刻度、闰月与跨月、原生显示开关、滚动位置和连续选区通过。工作簿普通/粗体字体、只读视口、准确保存/重开、未知样式/视图/扩展、非连续状态和缺失字体保护通过。浏览器复用原目录流程，增加实际 Canvas 像素、只读图像说明、无移动手柄和 PDF 文本，保留原 20 秒超时与零重试。类型调整中的滚动时间数组及空选区字段缺失已修复，分别由浏览器边界和定向核心发现；滚动时间保持字符串/null，空选区显式返回 null。API、公开检查/构建和受影响静态检查通过；证据归私有 `timelineDrawingCheckpoint`。未跑全量、安装包或外部 Excel；精确预设外观、创建和范围编辑及 P10–P12 其余能力继续实施。

P11 时间线范围筛选通过 8 项定向核心（新增 2 项，复用时间线绘图、透视报表筛选及切片筛选各 2 项）、2 项传输检查（196 条断言）和扩展既有 Chromium 流程。两套日期系统、独立日期/结果缓存、多张关联表、共享视图、空范围与清除、缓存及待刷新源保留、无变化、精确历史和重开通过。后一张表扩张失败、旧 revision、范围越界/倒置、非法闰日及普通资源操作保持原包与重做。默认日期表单、原生源输入、独立 ZIP/XML 的 sum 20/count 1 与清除后 sum 60/count 3、Canvas 及 PDF 文本通过，原 20 秒超时与零重试保持。空成员数组现明确表示零选择，原核心及 TS 用例已改为正向检查；null 仍表示全部。API、公开检查/构建、受影响私有严格类型与静态检查通过；证据归私有 `timelineFilterCheckpoint`。未跑全量、安装包、外部 Excel 或扩展浏览器矩阵；分组映射、创建、精确样式及 P10–P12 其余能力继续实施。

P11 原生时间线创建通过 8 项定向核心（新增 2 项，复用时间线筛选、绘图及切片器创建各 2 项）、2 项传输检查（137 条断言）和扩展既有 Chromium 流程。两套日期系统、独立日期缓存、成员索引及记录保留、共享结果表、连接复用、连续条件继承、源日期清空待刷新、精确历史和重开通过。名称、日期字段、字体、数量预算及非连续条件保持原包与重做。默认创建表单、SDK 第二视图、保存重开、原生源 200 与缓存结果 20、Canvas 及创建后 PDF 通过，原 20 秒超时和零重试保持。筛选触发行高变化时，原生框和已知兼容后备同步移动；定向核心同时检查变换和精确撤销。API、公开检查/构建、受影响私有严格类型和静态检查通过，证据归私有 `timelineCreateCheckpoint`。未跑全量、安装包或外部 Excel；早期 1900 数字日期、分组映射、手动资源编辑及 P10–P12 其余能力继续实施。

P11 原生时间线删除通过 7 项定向核心（新增 2 项，复用切片器删除 2 项及关联透视表删除 3 项）、2 项传输检查（144 条断言）和扩展既有 Chromium 流程。独立/共享视图、原生及兼容框、同部件兄弟项、关系与内容类型清理、其他部件不变通过。最后一项删除后保留日期条件、独立日期缓存、共享结果表及待刷新源，精确历史、重开和同字段重建复用通过。旧 revision、目标缺失、共享关系、绘图锁、工作表保护及引用注释原子拒绝。默认删除按钮、画布说明移除、缓存结果 20 与原生源 200、完整撤销/重做及空目录重开通过，原 20 秒超时和零重试保持。API、公开检查/构建和受影响私有严格类型、静态检查通过，证据归私有 `timelineDeleteCheckpoint`。未跑全量、安装包、外部 Excel 或扩展浏览器矩阵；分组映射、协调刷新、关联透视表删除及 P10–P12 其余能力继续实施。

P11 时间线关联透视表删除通过 10 项定向核心（新增 3 项，复用时间线筛选 2 项、切片关联透视表删除 3 项及时间线创建 2 项）和扩展既有 Chromium 流程。剩余连接继续筛选、最后连接跨表清理、普通/扩展日期目录、独占资源回收、共享日期定义与记录保留、未连接共享结果表的重开/刷新、待刷新源及精确历史通过。隐藏的后续远端视图与最后日期引用中的注释保留原包、选择和重做。原生日期共享项继续校验 ISO 值，读取不再依赖尚存时间线连接；原负向删除断言由正向事务覆盖替代。默认“删除透视表及结果”、两条时间线画布说明移除、原结果清空、源值 200 保留、完整撤销/重做及保存重开通过，原 20 秒超时和零重试保持。API、公开检查/构建、受影响私有严格类型和静态检查通过，证据归私有 `timelinePivotDeleteCheckpoint`。未新增接口断言，未跑全量、安装包、外部 Excel 或扩展浏览器矩阵；时间线协调刷新、分组映射及 P10–P12 其余能力继续实施。

P11 时间线协调刷新通过 10 项定向核心（新增 4 项，复用时间线筛选 2 项、共享切片器刷新 3 项及日历切片器刷新 1 项）和扩展既有 Chromium 流程。两套日期系统、不同结果缓存、共享视图、跨时间线缓存的共享日期定义、当前源及新日期更新、原生日期记录和 bounds、绝对选区保留、选区外空结果与清除、其他字段条件及切片缺失成员通过。过期标记清除、无变化、精确历史和重开通过。后一张表扩张、非日期/全空源、未知日期元数据及不支持公式的只读状态保持原包与历史。默认刷新使缓存结果 20 更新为当前源 200，保留日期选区，撤销/重做和 PDF 的 200 通过，原 20 秒超时和零重试保持。API、公开检查/构建、受影响私有严格类型和静态检查通过，证据归私有 `timelineRefreshCheckpoint`。未新增接口断言，未跑全量、安装包、外部 Excel 或扩展浏览器矩阵；记录别名、全空日期、早期 1900 数字日期、分组及字段/源修改协调继续实施，P10–P12 保持未完成。

P11 时间线关联字段与源修改通过 11 项定向核心（新增 2 项，复用时间线刷新 4 项、切片关联字段编辑 2 项及源修改 3 项）和扩展既有 Chromium 流程。目标字段、值聚合/标题、其他表设置保留、源增减/跨表迁移、日期缓存身份和绝对选区、源格保留、无变化、重开及精确历史通过。编辑预览包含新日期且保持只读，创建预览保持原合同。日期成员相同集合换序不产生历史；改写日期条件、标题身份、分组、未连接条件、后表扩张、旧 revision、失联预览及只读公式状态保持原子拒绝。默认字段面板将源改为 A1:B5、标题改为 Updated total，预览包含 2 / 4 条，独立 ZIP/XML 总计 240、源值 200、撤销/重做与重开通过，原 20 秒超时和零重试保持。API、公开检查/构建、受影响私有严格类型和静态检查通过，证据归私有 `timelineUpdateCheckpoint`。未新增接口断言，未跑全量、安装包、外部 Excel 或扩展浏览器矩阵；分组、列结构、空日期及手动框编辑继续实施，P10–P12 保持未完成。

P11 时间线数值框编辑通过 8 项定向核心（新增 2 项，复用切片框、切片手势与时间线绘制各 2 项）、2 项传输检查（149 条断言）和扩展既有 Chromium 流程。三类锚点、原生及已知兼容后备、clientData、只改绘图、日期状态与待刷新源保留、无变化、精确历史和重开通过。非法框、旧 revision、失联身份、绘图锁、未知后备、注释和缺失字体保持原包、选择与重做。默认框表单应用 120/160/260/130 磅及随单元格缩放，实际视口、撤销/重做和原生命周期流程通过，保持 20 秒超时与零重试。浏览器发现的 Worker 对象 id 与请求编号冲突已按既有 objectId 字段修复；撤销重做后先重读目录。API、公开检查/构建、受影响私有严格类型和静态检查通过，证据归私有 `timelineFrameCheckpoint`。未跑全量、安装包、外部 Excel 或扩展浏览器矩阵；画布拖动、日期拖选、分组及 P10–P12 其余能力继续实施。

P11 时间线画布框手势通过 8 项定向核心（新增 2 项，复用时间线框、切片手势与时间线绘制各 2 项）、2 项传输检查（152 条断言）和 2 条 Chromium 流程。标题/隐藏标题命中区、冻结/RTL/滚动换算、重复候选、取消及旧布局、自由与锁比例缩放、只改绘图、精确历史和重开通过。锁、未知后备及变换注释保留源与重做。新增浏览器流程检查实际拖动/Escape、Shift 方向键、角点、协调 Delete、独立 ZIP/XML 几何及其他部件不变、混合撤销/重做和重开后继续编辑；原时间线生命周期流程同步复验。两条流程沿原 20 秒超时和零重试。既有 Wasm/Worker 协议复用，API、公开检查/构建及受影响私有严格类型与静态检查通过，证据归私有 `timelineGestureCheckpoint`。未跑全量、安装包、外部 Excel 或扩展浏览器矩阵；日期拖选、粒度、滚动条及 P10–P12 其余能力继续实施。

P11 时间线日期条交互通过 8 项定向核心（新增 2 项，复用范围筛选、框手势与绘制各 2 项）、2 项传输检查（167 条断言）及新增 Chromium 日期流程。四种粒度、两套日期系统、冻结/RTL、闰日末端的小数秒与下一周期零点、共享 Sum/Count 表和视图、候选隔离、释放回起点、反向区间、空日期、选取粒度及精确历史/重开通过。后一张表扩张、旧 revision/布局、不可见段、非法点/粒度、选择锁和缺失字体保留源、选择及重做。浏览器检查点击、Enter/Space、连续拖选/Escape、缓存原文不变、独立 ZIP/XML 的总计 30/计数 2/待刷新源 200、混合历史、重开空月份与焦点返回。原生命周期及框手势两条流程已在本轮通过并复用结果；日期流程初次仅焦点名称查找失败，按实际 Cell A1 input 修正，补齐原生 selectionLevel 后再次通过。三条流程保持原 20 秒超时和零重试。API、公开检查/构建、受影响私有严格类型及静态检查通过，证据归私有 `timelinePointerCheckpoint`。未跑全量、安装包、外部 Excel 或扩展浏览器矩阵；时间轴自动滚动、端点手柄、粒度/滚动条及 P10–P12 其余能力继续实施。

P11 时间线显示粒度与滚动通过 6 项定向核心（新增 2 项，复用日期手势与绘制各 2 项）、2 项传输检查（183 条断言）和两条既有 Chromium 流程。四种粒度、绝对滚动位置保留、日/月/年定位、无变化、显示开关、目标视图独立修改、其余 ZIP 原文不变、缓存及原筛选保留、精确混合历史、重开后 Sum/Count 筛选及打印刻度通过。旧 revision、非法粒度/位置、过期粒度、保护/隐藏工作表及只读公式状态保持原包与重做。浏览器扩展原日期流程，检查默认面板及画布菜单、滑块 Home/End 和实际拖动、释放前无 revision/释放后一项历史、可读日期说明、仅视图部件改变、原筛选保持、撤销/重做、视图重开及继续日期选择。框手势流程复验新控件未遮挡移动、缩放与删除。原 20 秒超时与零重试保持。API、公开检查/构建及受影响私有严格类型、静态检查通过，证据归私有 `timelineViewCheckpoint`。未新增浏览器用例，未跑全量、安装包、外部 Excel 或扩展浏览器矩阵；滚轮、日期拖选自动滚动、端点手柄及 P10–P12 其余能力继续实施。

P11 时间线端点调整通过 6 项定向核心（新增 2 项，复用日期手势及视图各 2 项）、2 项传输检查（199 条断言）和扩展既有 Chromium 日期流程。两套日期系统、原周期无变化、独立候选、另一端的小数秒及 Z 时间串保留、跨端点限制、共享 Sum/Count、待刷新源、缓存定义/记录原文、精确混合历史和重开通过。跨窗口键盘定位与筛选合为一项历史；刷新缩小 bounds 后可保留未改变的另一端时间，普通范围入口仍拒绝越界。后表扩张、旧 revision、非法端点/粒度/周期及无变化保留源与重做。浏览器检查实际端点拖动/Escape、候选不增加 revision、释放一项历史、Home/End/ArrowLeft、重建控件后焦点、滚动及筛选的精确撤销重做，以及独立 ZIP/XML 的总计 30、计数 2、源 200 和缓存原文不变；沿原 20 秒超时与零重试。生产源码和生成 API 未改，复用 4f5fe253 的公开检查/构建及框手势浏览器结果；受影响私有严格类型、静态检查、原生格式、登记和链接检查通过。证据归私有 `timelineEndpointCheckpoint`。未新增浏览器用例，未跑全量、安装包、外部 Excel 或扩展浏览器矩阵；指针自动滚动、分组映射及 P10–P12 其余能力继续实施。

P11 时间线拖选自动滚动通过 5 项定向核心（新增 1 项，复用端点与日期手势各 2 项）、2 项传输检查（202 条断言）及两条既有 Chromium 流程。日期条和两端点在候选窗口移动后保留按下时的原起点；两套日期系统、冻结/RTL、前后滚动候选、源/revision/选择/历史/重做不变、周期边界、另一端精确时间、共享 Sum/Count、待刷新源、其他视图位置、一次筛选与滚动历史、精确撤销重做及重开通过。原端点周期不变时，仅滚动并保留清除状态。浏览器用实际鼠标与受控时钟检查边缘停留、范围滚动取消、端点释放一项变化及精确历史，框手势流程通过。初次日期流程未等待输入屏障即推进虚拟时钟，计时未触发；补齐屏障后通过，保留失败记录；原 20 秒超时及零重试保持。API、公开检查/构建、受影响私有严格类型/静态检查、登记和链接检查通过；证据归私有 `timelineScrollCheckpoint`。未新增浏览器用例，未跑全量、安装包、外部 Excel 或扩展浏览器矩阵；滚轮、分组映射及 P10–P12 其余能力继续实施。

P11 时间线滚轮导航通过两条既有 Chromium 流程。日期流程新增纵向滚轮、连续横向输入、队列逐次累加、按钮移出窗口后的焦点、日期条件保持、除时间线视图外全部 ZIP 原文不变、精确混合撤销及边界无变化保留重做。切片器既有成员筛选、清除、滚动、待刷新源、历史、重开及 PDF 流程通过，确认共享队列未退化。两条沿原 20 秒超时与零重试，未新增用例。复用已有核心滚动边界、保护和历史检查，未新增核心或传输逻辑；API、公开检查/构建、受影响私有严格类型/静态检查、登记、源码上限及链接检查通过。证据归私有 `timelineWheelCheckpoint`。未跑全量、安装包、外部 Excel 或扩展浏览器矩阵；分组映射、列结构及 P10–P12 其余能力继续实施。

P11 原生日历分组时间线通过 10 项定向核心（新增 2 项，复用创建 2 项、协调刷新 4 项、字段/源修改 2 项）、新增一条 Chromium 分组流程及两条既有回归。两套日期系统、月份行及年/季度/月列、同组内单日/部分时间、跨年同名月份、独立 Sum/Count 缓存与共享视图、空白/空范围/清除、缓存原文和待刷新源、关联切片器无数据状态、精确历史/重开通过。预览和刷新读取源 200；新增同日另一个时间后，原时间条件仍只选一条，改为整日得到 205/计数 2。原始字段及分组字段两种独立日期缓存形态保留。连续分组条件继承，分散日期创建及后表扩张冲突保持原子拒绝。核心新增源修改发现中途读取新旧缓存来源不一致，已改为写入前解析各表条件；未分组源修改回归通过。浏览器用默认表单选某日得到 4/1，实际月份按钮得到 6/2，重开后默认刷新得到 202/2，独立 ZIP/XML、缓存及精确历史通过。初轮三条流程通过，顺序修复后补跑受影响分组流程并复用两条未分组回归；原 20 秒超时和零重试保持。API、公开检查/构建、受影响私有严格类型/静态检查、登记、源码上限、链接及派生输入检查通过，证据归私有 `timelineGroupCheckpoint`。未新增公开接口或传输断言，未跑全量、外部 Excel、安装包及扩展浏览器矩阵；分组定义变更、列结构及 P10–P12 其余能力继续实施。

P11 时间线关联日期分组修改通过 10 项定向核心（新增 2 项，复用既有分组 2 项、协调刷新 4 项、字段/源修改 2 项）和三条既有 Chromium 流程。两套日期系统、共享/独立结果缓存、年/取消/日/年季度月切换、原始部分时间区间、共享表同步与独立布局、Sum/Count、待刷新源、同字段切片器成员重映射及排除自身条件的无数据状态、视图原文、无变化、精确混合历史及重开后继续筛选通过。独立日期缓存先校验旧分组，再统一写回原始源字段，保留身份。后表标题扩张触发既有空格保护，未关联日期/数字分组和自定义日期缓存标签保留原包与重做。旧一律拒绝日期分组的负例改为数字分组保护，新增正例覆盖新能力。浏览器扩展分组流程，用默认日历单位、预览、应用和移除入口，独立 ZIP/XML 核对新结果位置的 202/2/源 200、日期状态、精确历史、重开及后续二月选择 6/1；日期手势/滚轮和切片器既有流程复验，原 20 秒超时及零重试保持。API、公开检查/构建、受影响私有严格类型/静态检查、登记、源码上限及链接检查通过，证据归私有 `timelineRegroupCheckpoint`。未新增浏览器用例、公开接口或传输断言，未跑全量、外部 Excel、安装包及扩展浏览器矩阵；未关联字段分组、列结构及 P10–P12 其余能力继续实施。

P11 时间线关联源列映射通过 9 项定向核心（新增 2 项，复用分组及字段/源修改各 2 项、普通透视编辑 3 项）和扩展既有 Chromium 分组流程。两套日期系统、共享/独立结果缓存、日期/分类/值列重排、新增未用列及随后删除、原始部分时间区间、各表独立分类条件、Sum 200/Count 1、控件字段与成员、待刷新原源、视图原文、无变化、精确混合历史、重开和继续刷新 202/2 通过。被引用列删除、歧义标题、旧 revision 和后一张表扩张冲突保留原包、选择及重做。浏览器通过默认源范围和字段编号、只读预览及应用，独立 ZIP/XML 核对结果 6/1、原源 200 与全部日期缓存中第三字段 Date；撤销/重做、重开及一月选择 202/2 通过。原 20 秒超时及零重试保持。API、公开检查/构建、受影响私有严格类型/静态检查、源码上限、链接、登记及派生输入检查通过，证据归私有 `timelineColumnsCheckpoint`。未新增公开模型、传输断言或浏览器用例，未跑全量、外部 Excel、安装包及扩展浏览器矩阵；工作表直接插删列、仅含切片器的源列映射、未关联字段分组及 P10–P12 其余能力继续实施。

P11 共享透视/切片器源列映射通过 8 项定向核心（原源修改文件新增 2 项并复用 3 项、扩展既有日历分组 1 项、关联字段修改 2 项）和一条既有 Chromium 流程。列重排、增列及未用列删除保留各表行列、小计、成员/报表条件、累计计数基准字段、缓存身份及精确历史。重开后筛选仍取缓存总计 200，新源待刷新值 300 保留，刷新后得到 300，原源 200 保持。两套日期系统的年/月分组在新日期字段 2 与衍生字段 4 保留一月总计 2034，精确历史、重开及继续筛选通过。未用但仍有切片器连接的列删除、歧义标题、新列名与另一表值标题冲突、只读计算及后一表扩张冲突保留原包、选择和重做。浏览器扩展原切片器流程，默认字段/源面板完成编号修改、只读预览及应用，独立 ZIP/XML 核对两表结果 400、原源 400 与第五缓存字段 Region，精确历史和重开后继续筛选通过；原画布、无数据状态、键盘滚动和 PDF 检查保留。原 20 秒超时及零重试保持。API、公开检查/构建及受影响私有严格类型/静态检查通过；末次新增拒绝校验后补跑核心与 Moon 检查/构建，复用已通过的浏览器正例。源码上限、链接、登记和派生输入检查通过，证据归私有 `slicerColumnsCheckpoint`。未新增公开接口、输入文件、传输断言或浏览器用例，未跑全量、外部 Excel、安装包及扩展浏览器矩阵；工作表直接插删列、关联分组定义修改及 P10–P12 其余能力继续实施。

P10 文档常用样式重置通过 6 项定向核心（新增 2 项，复用既有内置预设及标题/段间距各 2 项）和一条 Chromium 流程。11 种列表段落、页眉页脚及字符样式、脚注尾注文字及字符样式和引用预设覆盖固定 Tab、默认角色继承、普通/复杂文字 10 pt、上标、直接覆盖、稳定元数据、待输入格式、无变化、11 步精确历史及重开；自定义、类型不符和属性注释保留原包与重做。默认面板重置后，独立 XML 核对缩进、两个 Tab 和复杂文字字号；其余 ZIP 原文、四步精确历史、保存重开、10 pt 查询和后续输入通过。独立 Poppler PDF 核对整行右端 520.45 pt，以及注释、上标和较大直接字号的实际高度。初次检查误将一个 ActualText 行块当作三个词，改为原生 Tab 与整行坐标，并分段测量字号；保留失败记录，产品代码未针对提取器改变。原 20 秒超时及零重试保持。API、公开检查/构建、受影响私有严格类型/静态检查、源码上限、链接和登记检查通过；证据归私有 `documentPresetsCheckpoint`。未新增公开接口或固定输入文件，未跑全量、安装包、外部 Word 及扩展浏览器矩阵；其余内置预设、多节及 P10–P12 其余能力继续实施。

P12 居中圆形径向渐变通过 10 项定向核心（新增 2 项，既有线性背景和形状 8 项）、两项接口检查共 51 个断言，以及两条 Chromium 流程（新增径向、既有线性形状）。覆盖多选、三项 RGBA 色标、原生路径、复制、纯色/线性替换、无变化、精确历史、保存重开及非法值/未知源原子拒绝。默认背景和形状控件、独立 XML、其他 ZIP 原文、继续原生输入通过；七处独立圆形/透明度计算核对 Canvas、PNG 与 Poppler PDF，包含非正方形圆形半径、变化透明度、椭圆裁剪和背景端点。qpdf 验证 PDF 1.4、径向 shading 与软遮罩，PDF 保留文字。首轮背景下拉查询改用已有 combobox 访问方式后通过，产品和超时未改变。公开 API/check/build、私有严格类型/静态检查、源码上限、链接和登记通过；证据归 `radialGradientCheckpoint`。未跑全量、安装包矩阵或外部 Office；非中心焦点、其他路径类型、复杂效果及 P10–P12 其余能力继续实施。

P10 九级目录及目录标题样式重置通过 6 项定向核心（新增 2 项，既有文档和标题预设各 2 项）与一条 Chromium 流程。核心覆盖全部原生缩进、段后距、默认继承、名称与元数据、待输入格式、直接覆盖、10 步精确历史、无变化、保存重开及未知/自定义/类型不符源保护。默认面板检查 1/5/9 级及目录标题，独立 XML、其他 ZIP 原文、四步精确历史、重开后 11 pt 查询与继续原生输入通过；独立 Poppler PDF 核对实际水平坐标及较大直接字号。接口生成、公开检查/构建、受影响私有静态检查、源码上限、链接和登记通过，证据归 `tocPresetsCheckpoint`。保持 20 秒与零重试；未跑全量或外部 Office。仅重置已有目录样式，目录字段生成/更新、图表目录样式和其余阶段能力继续实施。

P10 跨段 TOC 读取与保护通过 6 项定向核心（新增 2 项，既有目录样式和页码引用各 2 项）及两条 Chromium 流程（新增目录读取、既有页码引用）。覆盖目录连续缓存、无标记中间段落保护、链接内复杂 PAGEREF 与简单引用的真实 VIII/IX、原源保持、目录外输入、精确历史、重开及既有显式页码缓存刷新。未知/重复开关、短引号、锁定、不完整、注释和共享边界源原子保护；未知及超长跨段字段也保护中间结果。独立 XML、其余 ZIP 原文、Poppler PDF 文字及 qpdf 链接目标通过。链接按三个相邻 run 注释输出，检查其连续覆盖和共同目标，不要求 writer 合并注释。公开 API/check/build、私有定向静态检查、源码上限、链接与登记通过，证据归 `tocReadCheckpoint`。未跑全量、安装包或外部 Office；目录生成、整体更新、插入/删除及默认控件仍待实现，原生 SDT 等导入变体继续保护。

P10 目录创建、整体更新和删除通过 6 项定向核心（新增 2 项，读取与题注回归各 2 项）、1 项传输检查共 25 个断言，以及两条 Chromium 流程（新增编辑、既有读取）。覆盖空目录、原生标题输入、样式和书签复用、实际 VIII/IX、PAGE 标题在插入后重排、待输入格式、无变化、四步精确历史、重开及过期目录拒绝后继续输入。独立 ZIP/XML 保留其他部件，Poppler 核对目录页码及 280 pt 右端，qpdf 核对四个链接与目标页。目录边界检查区分属性制表位和正文 Tab；过期状态复用可恢复错误处理。公开 API/check/build、私有定向静态检查、源码上限、链接、登记和包文件清单通过，证据归 `tocEditCheckpoint`。保持 20 秒与零重试；未跑全量、安装包或外部 Office，自动更新、复杂导入目录及 P10–P12 其余能力继续实施。

P10 标准 TOC 内容控件通过 6 项定向核心（新增 2 项，既有目录编辑与读取各 2 项）和三条 Chromium 流程（新增包装目录，既有普通读取与创建）。覆盖原生图库、可选标题、包装元数据与末尾格式原文、当前页码、整体更新、整控件删除、空结果及唯一正文控件删除后继续输入、无变化、精确历史和重开。锁定、绑定、重复、嵌套、其他图库、额外内容及带锚点标题原子保护。默认面板、独立 ZIP/XML、其他部件原文、Poppler 标题/页码/继续输入及 qpdf 两个链接的实际目标页通过。公开 API/check/build、私有定向静态检查、源码上限、链接与登记通过，证据归 `tocControlCheckpoint`。未新增公开模型或传输测试，保持 20 秒和零重试；未跑全量、安装包或外部 Office，通用内容控件、复杂导入及 P10–P12 其余能力继续实施。

P11 切片器滚动条通过 5 项定向核心（扩展既有指针 1 项，绘制和框手势各 2 项）、既有传输检查的 96 个断言，以及扩展的切片器 Chromium 流程和既有时间线回归。核心验证绝对行、两列布局与成员索引区分、轨道区域、边界无变化、旧布局保护、冻结/RTL、文档/选择/历史及重做保持。真实垂直拖动、Home、滑块焦点、具名无障碍入口及 Escape 返回 J8 输入通过；随后原生筛选、多选、清除、精确历史、重开、源映射及独立 XML/PDF 保留。首轮轨道被短工作区裁剪，改用原生大行高并收起工具栏；后续定位断言改用实际动态输入名称。原 20 秒和零重试保持，最后仅重跑受影响切片器流程，复用已通过的时间线结果。公开 API/check/build、私有静态检查、源码上限、链接及登记通过，证据归 `slicerScrollCheckpoint`。未新增用例、依赖或安装包检查，未跑全量和外部 Office；悬停/成员拖选及 P10–P12 其余能力继续实施。

P11 切片器成员拖选通过 5 项定向核心（新增范围 2 项，既有指针 1 项及协调筛选 2 项）、两个既有传输检查共 216 个断言，以及扩展的切片器筛选、既有创建/框手势和时间线范围三条 Chromium 流程。核心覆盖显示顺序、正反区间、原状态反选、空选择保持、候选源/视图/历史/重做不变、缺字体与旧/隐藏目标保护、缓存结果 20 与待处理源 200、精确历史和重开。浏览器实际按住边缘滚动，原生画布显示候选，取消后恢复原字节与行位置，松开只增加一次 revision 并选中两项；Ctrl 按下/释放实时改变候选，随后取消保持原包。后续单项/多选、源映射、框手势、时间线及独立 XML/PDF 保留。修饰键补齐后只重跑受影响筛选流程，复用另两条结果，保持 20 秒和零重试。API/check/build、最终 Web 类型与构建、私有静态检查、源码上限、链接、登记及包文件清单通过，证据归 `slicerRangeCheckpoint`。未新增浏览器/单元用例或依赖，未跑全量、安装包或外部 Office；悬停样式及 P10–P12 其余能力继续实施。

P10 绘图对象外链通过 7 项定向核心（新增 2 项，图片编辑 2 项及文字链接 3 项）、三个既有传输检查共 166 个断言，以及新增对象链接和既有图片/形状两条 Chromium 回归。覆盖图片、浮动矩形和零轴线形、原生 docPr 链接、提示及关系复用、当前选择、无变化、精确历史和重开；未知动作、无效目标、缺失关系、锁和过期修改原子保护。默认面板的应用/移除/显式打开、其他 ZIP 部件原文、独立 XML、qpdf 两个 URI 与 80×40/60×30 点击范围、重开后原生输入通过。最后补齐零轴线形容差并复用不受影响的浏览器结果。API/check/build、私有定向静态检查、源码上限、链接、登记及包文件清单通过，证据归 `drawingLinkCheckpoint`。保持 20 秒与零重试；未跑全量、安装包或外部 Office，对象书签关系、链接对象片段转移及 P10–P12 其余能力继续实施。

P10 绘图对象书签链接通过 7 项定向核心（新增 2 项，既有对象外链 2 项及书签 3 项）、三个既有传输检查共 168 个断言，以及扩展对象链接、既有形状属性和书签三条 Chromium 流程。图片与浮动图形共用原生内部关系，普通文字 anchor、对象链接和书签改名/删除合为精确历史；当前选择、无变化、媒体、对象原文、重开和跳转保持。未知共享引用、其他部件引用、锁和缺失目标原子保护，未使用的 XML 部件关系不参与修改。默认面板的内部目标、显式跳转、四步撤销/重做及重开后目标处输入通过；独立 XML 核对单一共享关系，qpdf 核对两个实际第二页目标及 20/180 坐标。公开 API/check/build、最终 UI 构建、私有定向静态检查、源码上限、链接、登记及包文件清单通过，证据归 `drawingBookmarkCheckpoint`。测试辅助函数改用稳定 XML ID 查表，保留精简失败证据。未新增浏览器或单元用例，保持 20 秒和零重试；未跑全量、安装包或外部 Office，链接对象片段转移及 P10–P12 其余能力继续实施。

P10 链接对象的富文本转移通过 11 项定向核心（新增 2 项，既有对象链接 2 项、形状片段 3 项及图片单元格片段 4 项）。覆盖外链、内部书签、关系冲突及复用、原元数据、媒体字节、独立对象身份、重复书签策略、正文剪切、单元格粘贴、精确历史、继续输入和重开；文本框整体/内部文字链接及合并格中的零轴链接形状也已检查。伪造原生关系、非法地址、缺失书签、错误所有者、复制锁及悬停源原子保护，链接对象标记语言输出继续明确拒绝。两条扩展 Chromium 流程通过，复用已通过形状属性回归；真实 Copy、原生 Cut/Paste、跨文档图片/形状/书签粘贴、关系部件登记、源间隙、重开和精确历史通过，qpdf 分别核对外链 URI 和两个实际第二页目标。原超时 20 秒与零重试保持。首轮修正 XML 父节点锚定；浏览器改用已有 Shift+方向键/Home 选择，核对新增内容类型及原 XML 前后缀，等待图片粘贴 revision 后再保存。公开 API/check/build、私有定向静态检查、源码上限、链接及登记通过，证据归 `drawingLinkClipboardCheckpoint`。未新增公开 API、浏览器/单元用例或依赖，未跑全量、安装包或外部 Office；链接对象 HTML/Markdown 输出及 P10–P12 其余能力继续实施。

P10 链接图片的 HTML/Markdown 输出通过 6 项定向核心（扩展既有输出 2 项，复用对象片段 2 项及对象链接 2 项）和一条扩展 Chromium 流程。正文及普通合并格图片保留外链、书签、提示、目标窗口、裁剪和原始嵌入字节；内部地址按忽略大小写查找后使用实际书签名，文字链接沿同一规则。非法地址、缺失书签、未知动作、悬停及嵌套链接拒绝并保留源、选择和历史；图形继续明确保护。默认菜单输出、独立 Chromium 解析、裁剪像素、零外链请求、预算失败后继续输入、精确撤销、重开和下载字节一致通过。首轮补齐已有编号测试辅助函数并改用显式索引元组，保留编译诊断。公开 API/check/build 和私有定向静态检查通过，证据归 `drawingMarkupCheckpoint`。保持 20 秒与零重试，未新增 API、依赖或测试用例；未跑全量、安装包及外部 Office，图形标记语言输出和 P10–P12 其余能力继续实施。

P10 基础图形 HTML/Markdown 输出通过 6 项定向核心（扩展既有输出 2 项，复用对象片段 2 项及对象链接 2 项）和一条扩展 Chromium 流程。矩形、椭圆和零高度线形复用 Canvas/PDF 轮廓，SVG 保留填充、描边、几何与无障碍名称；正文浮动矩形及合并格椭圆保留外链/书签和提示。独立解析核对实际轮廓、描边余量及目标，真实 PNG 像素核对红色填充、蓝色边线与零轴线；既有图片裁剪/字节、菜单、失败恢复、原生输入、精确撤销、重开和下载一致保留。首轮表格后浮动锚点触发现有八次收敛保护，保留 JSON 和 trace，该布局问题未修复；输出流程改用首段页内锚点。随后像素检查改为采样实际两行 PNG，颜色容差及数量阈值保持，附完整线形 PNG。公开 API/check/build 与私有定向静态检查通过，证据归 `shapeMarkupCheckpoint`。保持 20 秒和零重试，未新增 API、依赖或测试用例；未跑全量、安装包及外部 Office，文本框标记语言输出和 P10–P12 其余能力继续实施。

P10 方形环绕的边界接触修复通过 8 项定向核心（新增边界 1 项及既有浮动/环绕 7 项）、原始失败文件的独立核心复现，以及恢复原始锚点的一条 Chromium 流程。只接触正文左/右边界时，表格位置和页数与无环绕一致；正间距仍排除表格，上下型环绕保留原边界规则，缓存几何一致。修复前新用例把表格从 33.65 推到 50，原始文件的锚点在第 2/3 页间振荡八次；修复后两轮收敛为两页。浏览器已恢复原始表格后 180/72 锚点，加载、原生输入、HTML/Markdown 菜单、图片/SVG 像素、精确撤销、重开及下载一致通过。公开 API/check/build、私有定向静态检查、源码上限、链接及登记通过，证据归 `wrappingEdgeCheckpoint`。初始私有暂存的辅助定义和 import 问题已单独修正并保留诊断；产品仅调整方形环绕交集，八轮上限、20 秒和零重试保持。未跑全量、安装包及外部 Office；其他真实循环依赖继续原子拒绝，P10–P12 其余能力继续实施。

P10 普通文本框 HTML/Markdown 输出通过 10 项定向核心（扩展输出 2 项，既有链接片段 2 项、文本框片段 3 项及图形片段 3 项）和一条扩展 Chromium 流程。富文本标题、空段落、框内距、底部对齐、不换行及裁剪保留；整体链接覆盖背景和普通文字，内部书签链接保持独立，源、选择和精确历史不变。列表中的文本框使用 HTML 块，既有 cmark 解析确认 `Literal *[kept]*` 保持字面内容。浏览器独立核对语义、字号/颜色、实际文本区底边和三类点击位置，指针实际选择合并格框内文字，既有图片/SVG 像素、零外链请求、输入、预算恢复、撤销、重开和下载一致保留。首轮补齐测试辅助函数与 SVG 序列化错误声明；浏览器补齐装载器真实斜体字体，并以实际底边对齐替代无依据的固定空余阈值，保留诊断和失败 JSON。公开 API/check/build、私有定向静态检查、源码上限、链接及登记通过，证据归 `textBoxMarkupCheckpoint`。只导出既有核心文本区几何方法，未新增 SDK 命令、依赖或测试用例；保持 20 秒和零重试，未跑全量、安装包及外部 Office，P10–P12 其余能力继续实施。

P11 切片器原生成员悬停通过 7 项定向核心和一条扩展 Chromium 筛选流程。14 套内置样式的普通及悬停状态与独立 ONLYOFFICE DXF 数据一致，源、选择、历史、重做及静态打印保持。浏览器核对悬停像素、移出恢复和待输入文字，既有筛选、连续拖选、精确历史、重开及独立 PDF 检查通过。宿主只重绘画布，悬停入队不发布忙碌状态，避免丢失随后按钮点击。证据归私有 `slicerHoverCheckpoint`；保持 20 秒和零重试，未新增依赖或用例，未跑全量、安装包和外部 Office。P10–P12 其余能力继续实施。

P12 燕尾形与五边形箭头通过 12 项定向核心、3 项接口检查共 78 个断言和一条扩展 Chromium 流程。独立顶点、文字区域、连接点、调节手柄、原生常量与凹口命中保持；旋转/翻转候选、取消、类型修改、复制、精确历史及重开沿已有用例检查。默认控件插入与数值调整、燕尾形内输入、独立 XML、Canvas/PDF 各 14 个采样和 PDF 文字通过。公开 API/check/build 与私有定向静态检查通过，证据归 `chevronCheckpoint`。保持 20 秒和零重试；未新增用例、依赖或绘制路径，未跑全量、安装包和外部 Office。P10–P12 其余能力继续实施。

P12 跨文稿页面导入通过 12 项定向核心、1 项接口检查（27 个断言）和 1 条 Chromium 流程。覆盖所选页顺序、设计/备注/媒体/表格/图表、尺寸适配、链接重映射、失败保护与保留重做、一次精确历史、保存重开、Canvas 像素和独立 PDF。公开 API/check/build 与定向私有静态检查通过，证据归 `slideImportCheckpoint`。修正构建入口遗漏和测试调用类型，保留原有 20 秒与零重试；未跑全量、安装包矩阵和外部 Office，批注导入及 P10–P12 其余能力继续实施。

P12 页面导入的传统与现代批注通过 11 项定向核心和一条扩展 Chromium 流程。覆盖作者/GUID 冲突、重复导入、两种作者表共存、传统父索引和现代页面锚点、位置比例、状态/元数据、继续回复及页复制/删除、缺作者保护、悬空作者引用与重做保留、一次精确历史和保存重开。浏览器沿默认导入与批注面板检查回复、原生 XML、Canvas 和独立 PDF，批注文字继续排除在静态 PDF 之外。首轮修正 XML 锚点替换范围、创建作者部件时的候选快照和待提交媒体传递；保留核心诊断与浏览器失败记录。公开 api/check/build、私有定向静态检查通过；接口结构未变，复用前次 27 个接口断言。证据归 `slideImportCommentsCheckpoint`，保持 20 秒和零重试，未跑全量、安装包矩阵和外部 Office；未知批注元数据及 P10–P12 其余能力继续实施。

P11 标准边框线型通过 8 项定向核心（新增 2 项、既有合并边框 2 项及条件格式 4 项）、一项接口检查共 95 个断言和一条 Chromium 流程。覆盖 14 种标准状态/线型、独立 ONLYOFFICE 线宽/节奏、原生源与格式复制、条件/表格差异样式、精确历史和未知线型保护。浏览器检查默认目录、导入细点线、创建横向虚线与纵向中等点划线、独立 XML、原样撤销/重做、重开、原生输入后的依赖重算，以及实际 Canvas 与独立 PDF 栅格的线段和间隙。像素检查发现邻格网格线盖住显式边框，调整为网格线先绘制，保留颜色和线段断言；控件定位按运行时原生字段组修正，保留首轮 JSON 和像素基线。公开 api/check/build 与定向私有静态检查通过，证据归 `borderStylesCheckpoint`。保持 20 秒和零重试，未跑全量、安装包矩阵和外部 Office；未知线型及 P10–P12 其余能力继续实施。

P10 原生多行公式通过 8 项定向核心（新增 2 项、既有独立段落 2 项、矩阵 2 项及公式编辑 2 项）、2 项接口检查共 28 个断言和一条 Chromium 流程。覆盖原生对齐组与三种基线、实际 JSON、嵌套、空段及全空外观、复制、精确历史、重开和失败保留重做；浏览器沿默认面板检查插入拆段、修改、周边原生输入、实际 Canvas 字形和独立 XML/PDF 行对齐。公开 api/check/build、私有定向 TS/lint 通过，证据归 `equationArrayCheckpoint`。保持 20 秒和零重试；未跑全量、安装包矩阵和外部 Office。局部格式、强制换行及 P10–P12 其余能力继续实施。

P10 原生索引通过 7 项定向核心（新增条目、生成和保护 3 项，既有 TOC 读取及编辑 4 项）、2 项接口共 35 个断言及一条 Chromium 流程。检查隐藏 XE 的零文字位置、原源修改、复制/粘贴及同段剪切、跨段替换、三级词典序、物理页去重、原生页码缓存、空索引、精确历史、重开及失败保留重做；默认控件检查标记、修改、更新、删除、过期目录恢复、原生输入及独立 XML/PDF。公开 api/check/build、定向私有 TS/lint 通过，证据归 `indexCheckpoint`。复用多行公式已通过结果；保持 20 秒和零重试，未跑全量或外部 Office。复杂导入与 P10–P12 其余能力继续实施。

P10 章节题注通过 10 项定向核心（新增章节题注 2 项、既有题注 2 项、序列字段 5 项及注释引用 1 项），并在简化章节号查询分支后复查新增 2 项；接口检查扩展既有用例至 99 个断言。Chromium 沿默认面板创建跨章节的三条题注，检查不同分隔符、原生 STYLEREF/SEQ 代码与缓存、范围外部件、精确历史、重开后标题换段及原生题注输入、显式缓存刷新和独立 XML/PDF。公开 api/check/build、定向私有 TS/lint 通过，证据归 `chapterCaptionCheckpoint`。保持 20 秒和零重试，未跑全量、安装包、独立 Canvas 快照或外部 Office。按名称查找样式、浮动题注框及 P10–P12 其余能力继续实施。

P10 原生题注目录通过 12 项定向核心（新增题注目录 2 项、既有 TOC 读取 2 项、TOC 编辑 2 项、索引 3 项及书签 3 项），既有接口用例扩展至 46 个断言。Chromium 使用默认面板收集简单/复杂正文域和普通格题注，检查不同页的真实编号、六个内部链接、显式更新、精确历史、旧 SEQ 缓存与范围外部件保持、重开原生输入及独立 XML/PDF。段首点书签可定位已验证的复杂域，同段完整范围和普通输入仍受保护。公开 api/check/build、定向私有 TS/lint 通过，证据归 `tocCaptionCheckpoint`。复用章节题注结果；保持 20 秒和零重试，未跑全量、安装包、独立 Canvas 快照或外部 Office。浮动题注目录及 P10–P12 其余能力继续实施。

P10 资料来源管理通过 4 项定向核心、1 项接口检查共 57 个断言及一条 Chromium 流程。覆盖原生资源与身份冲突、七字段修改、2006/2004 命名空间、机构及多作者保留、未知作者数据保护、跨区域 CITATION 引用删除保护、精确混合历史、预算失败保留重做和保存重开。默认表单检查新增、修改、删除、重复标签恢复、独立 ZIP/XML、旧目录恢复及随后原生输入。公开 api/check/build、私有定向 TS/lint 通过，证据归 `sourceManagerCheckpoint`。保持 20 秒和零重试；本次仅修改来源元数据，未新增 Canvas/PDF 验收，未跑全量、安装包或外部 Office。引文、书目及 P10–P12 其余能力继续实施。

P10 原生引文通过 13 项定向核心（新增引文 3 项、来源管理 4 项、既有正文域 6 项），并在改用公开剪贴板流程后复查新增 3 项；既有接口检查扩展至 86 个断言。Chromium 沿默认来源面板检查正文范围替换、普通格中文标题回退、导入多 run 缓存、来源修改后的显式更新/无变化操作、引用删除保护、精确历史、重开和旧目录恢复、随后原生输入及独立 XML/PDF。公开 api/check/build、定向私有 TS/lint 通过，证据归 `citationCheckpoint`。复用来源管理已有浏览器结果；保持 20 秒与零重试，未跑全量、安装包、独立截图或外部 Office。完整引用样式、富文本来源转移、书目及 P10–P12 其余能力继续实施。

P10 原生书目通过 14 项定向核心（新增书目 3 项、既有 TOC 读取/编辑/控件各 2 项、索引 3 项、题注目录 2 项），既有接口检查扩展至 111 个断言。Chromium 沿默认面板生成含未引用及中文来源的书目，检查标题、来源修改后的显式更新、空操作、旧目录恢复、精确混合历史、删除保留来源、重开原生输入、源注释及样式保持、独立 XML/PDF，并确认原有引文缓存不被改写。公开 api/check/build、定向私有 TS/lint 通过，证据归 `bibliographyCheckpoint`。复用来源及引文已有证据；保持 20 秒与零重试，未跑全量、安装包、独立截图或外部 Office。完整引用样式、来源转移及 P10–P12 其余能力继续实施。

P10 引文富文本来源转移通过 10 项定向核心（新增 3 项、既有引文 3 项、共享字段剪贴板 4 项）及 Chromium。默认复制、工具栏和原生快捷键粘贴检查跨文档来源冲突、重复来源复用、完整作者/编辑者/卷期保持、精确混合历史、保存重开、原生输入和独立 XML/PDF。核心另查标准/旧版来源部件创建、撤销资源及不可信片段拒绝。公开 api/check/build 和定向私有 TS/lint 通过，已有 111 个接口断言继续通过，证据归 `citationClipboardCheckpoint`。保持 20 秒与零重试，复用来源、引文和书目已有检查；未跑全量或外部 Office。混合来源命名空间、复杂域片段、未知资源扩展和冲突版本保持保护，P10–P12 仍未完成。

P11 普通透视工作表复制通过 9 项定向核心（新增复制 3 项、既有工作表复制 2 项、透视 4 项）和 Chromium。默认复制、原生输入、共享缓存/原数据源、独立报表定义及字段、协调刷新、精确混合历史和保存重开已检查；独立 XML 检查缓存与来源身份及两张报表结果，独立 PDF 检查副本汇总。核心另查多报表/独立缓存图、删除保留共享资源、未知属性/关系及报表数量超限保留重做。公开 api/check/build、定向私有 TS/lint 通过；未新增协议或接口，复用现有接口检查。证据归 `pivotSheetCopyCheckpoint`，保留 20 秒与零重试，未跑全量或外部 Office。带切片器/时间线连接图的复制及 P10–P12 其他功能继续实施。

P11 普通透视工作表删除与缺失来源恢复通过 12 项定向核心（新增删除/恢复 3 项、既有透视表复制 3 项、透视编辑/删除 3 项、工作表删除 3 项），既有接口检查扩展至 167 个断言。原 Chromium 工作表复制流程增加源表删除、原因与刷新保护、范围外输入、精确撤销/重做、保存重开、缓存 PDF 及默认字段面板显式改源。独立 XML 检查删除部件、缓存保留/失效及重新绑定来源，PDF 分别检查缓存总计 40 与改源后 124。核心另查多缓存最后拥有者回收、共享记录、字段布局保持、异常关系及失败保留重做。公开 api/check/build、定向私有 TS/lint 通过，证据归 `pivotSheetDeleteCheckpoint`。复用此前复制及共享刷新证据，保持 20 秒与零重试，未跑全量或外部 Office。连接控件的整表复制/删除检查见下文，P10–P12 其他能力继续实施。

P11 连接控件的工作表删除通过 16 项定向核心：新增 3 项，复用普通整表删除 3 项、关联透视删除 3 项、时间线透视删除 3 项及两类缓存筛选各 2 项。检查共享连接/最后拥有者、远端资源清理、源表与本表控件删除、缓存记录和待刷新源保持、缺失来源筛选及协调改源、独立字段、精确混合历史和重开。带远端注释的失败用例保留先前候选清理前的全部字节、选择、revision 和重做。新增 Chromium 通过默认删除、成员/日期筛选、缺失来源清除、保存重开和显式改源；独立 XML 检查剩余连接和缓存失效，PDF 检查冻结总计 20。公开 api/check/build、定向 TS/lint 通过；原复制/删除 Chromium 在当前构建复核，167 个接口断言沿用有效结果。证据归 `analysisSheetDeleteCheckpoint`，保持 20 秒与零重试，未跑全量或外部 Office。连接图整表复制检查见下文，其余 P10–P12 功能继续实施。

P11 重叠时间线缓存通过 2 项新增核心和 11 项既有定向回归；既有回归在修正夹具前通过，产品代码随后未变，新增用例按当前夹具单独通过。三缓存连接链覆盖两张表的四张报表，检查 1900 原始日期及 1904 年分组、待刷新源和记录保留、30/220/270 独立汇总、原连接、无变化操作、精确混合历史及重开。失败检查覆盖后表扩张的完整回滚、重做保留和冲突区间刷新保护。Chromium 的默认跨表筛选、刷新、清除、精确历史及保存重开通过，独立 XML 检查三个缓存选区及 Sum/Count 结果，PDF 检查 220。公开 api/check/build、定向私有 TS/lint 通过，证据归 `timelineOverlapCheckpoint`。复用既有接口协议，保持 20 秒与零重试，未跑全量或外部 Office。连接图整表复制检查见下文，其余 P10–P12 能力继续实施。

P11 连接控件的工作表复制通过 16 项定向核心，包含 4 项新增复制、3 项普通透视复制、3 项连接整表删除、2 项重叠时间线及两类控件创建各 2 项；随后 OPC 去重校验通过 2 项既有检查。覆盖独立控件/缓存定义、名称及可选 UID、本地/远端连接、原数据源、日历/成员筛选、缺失来源显式恢复、创建复用、失败原子性及精确混合历史。新增 Chromium 沿同一编辑器和历史分三项连续检查默认复制/筛选、完整撤销重做与独立 XML/PDF、重开后筛选和删除；保留全部断言、20 秒单项上限及零重试。既有连接整表删除 Chromium 已在当前构建通过。独立 XML 检查连接及 15 个唯一 UID，PDF 检查总计 270，导出保留文档。公开 api/check/build、私有 TS/lint 与源格式/链接检查通过，证据归 `analysisSheetCopyCheckpoint`。沿用既有接口协议；时间线列用例仅直接审阅 CopyReason 期望调整，未重跑整文件。未跑全量或外部 Office，P10–P12 保持部分交付。

P11 分析工作簿的新增、重排与可见性通过 3 项新增核心和 10 项既有工作表/结构保护回归。既有回归在修正新夹具前通过，产品代码随后未变；新增用例按最终夹具单独通过。检查稳定表身份/连接、原缓存与待刷新源、跨表公式索引、hidden/veryHidden、隐藏报表的缓存筛选与显式刷新、独立隐藏报表 API 的选区保持、完整精确历史及重开。结构保护、未知扩展及受保护隐藏报表检查失败字节、revision、选择和重做。2 项连续 Chromium 复用同一编辑器，检查默认新增/移动/隐藏/显示、原生输入、筛选刷新、保存重开及独立 XML/PDF；XML 检查两张隐藏表、四条连接及两个总计 220，PDF 检查 220，导出保留文档。公开 api/check/build、私有 TS/lint 与源格式/链接检查通过，证据归 `analysisSheetOrderCheckpoint`。复用既有夹具和接口协议；复制用例仅直接审阅管理原因的期望调整，未重跑完整流程。保持 20 秒与零重试，未跑全量或外部 Office，P10–P12 继续实施。

P11 直接删除未用源列通过 6 项定向核心，包含 2 项新增、1 项既有整列分析结构及 3 项时间线源字段/改名回归。加强共享记录拥有者及实时刷新保护后，新增 2 项再次通过。检查 1900 普通与 1904 年/月分组、四张共享报表、独立日期缓存、成员与记录列投影、派生 base/par、原控件视图、待刷新值、跨表公式、精确历史及重开。匹配共享记录拥有者只投影一次；字段仍被引用、记录扩展、映射不一致及跨独立缓存的实时刷新检查整项字节、revision、选区和重做保持。2 项连续 Chromium 通过原生输入、默认删列、撤销重做、缓存筛选/刷新和重开；独立 XML 检查三个缓存定义、三列记录及所有报表行/值索引，PDF 检查 220，重开清除得到 270，导出保留文档。公开 api/check/build、私有 TS/lint 与源格式/链接检查通过，证据归 `analysisColumnDeleteCheckpoint`。保持 20 秒与零重试，未跑全量或外部 Office；源内插列、删除被使用字段和其余 P10–P12 继续实施。

P11 源内整列插入的 3 项新增核心最终通过。初次定向执行共 10 项，7 项既有和 2 项新增通过；剩余预算用例补齐字体测量前置后，3 项新增全部通过，产品代码未变。检查多列空字段/记录插入、占位名冲突、1900/1904 年/月分组、独立/共享/连接刷新、控件独占字段身份、新字段创建切片器、待刷新值、精确历史及重开。源宽度和部件输出预算失败均检查 limit-exceeded、原字节、revision 与重做保留。此前行列用例中的插列拒绝断言已移入新增成功流程。证据归 analysisColumnInsertCheckpoint。新增 1 项 Chromium 通过默认插列、原生标题输入和 80/26/20/30/220/270 结果，独立 XML 检查三个四字段缓存、两个已更新标题、一个未用缓存占位标题、记录列宽和报表字段索引；完整撤销重做及保存重开通过。私有 TS/lint 通过，公开构建复用前次同源结果。保持 20 秒与零重试，未重复 PDF、全量或外部 Office，P10–P12 保持部分交付。

P12 缺口右箭头通过 1 项新增核心和 8 项既有调节值/变换手柄/类型修改回归。初次执行的新用例只因坐标浮点尾差失败，改用既有 1e-9 容差后单独通过，产品代码未变。独立几何基线检查八点轮廓、文字内框、四个连接点、两个手柄、竖长比例及缺口命中排除；复制、类型修改、精确历史、其他部件不变、重开与越界后重做保持通过。接口检查 3 项、103 个断言通过。1 条 Chromium 检查默认插入、两项调节、原生输入、独立 XML、精确混合历史、保存重开和五个 Canvas/PDF 内外像素，PDF 文字及导出源保持通过。公开 api/check/build、私有 TS/lint/格式通过，证据归 `notchedArrowCheckpoint`。保持 20 秒与零重试，未跑全量或外部 Office，P10–P12 继续实施。

P10 连续分节通过 8 项定向核心，含 3 项新增布局/表格用例及 5 项既有分节创建、保护与原生输入用例。检查同页栏平衡、不同横向边距、共享页旧纵向边距和页眉、后续页新几何、实际页号/全文字段、纸型变化、脚注换页、段前分页、空尾节、表格几何与源顺序。创建矩阵加入 continuous，连续两次表格分节覆盖相同类型属性无修改时的恢复。接口 3 项、89 个断言通过。1 条 Chromium 检查默认连续分节、正文/拆表、原生输入、单物理页页眉页码、完整精确历史及重开；独立 XML 检查三个节、两个连续类型、两张表和其余部件保持，qpdf 与 PDF 文字检查通过。公开 api/check/build、私有 TS/lint/格式通过，证据归 `continuousSectionsCheckpoint`。保持 20 秒与零重试，未跑全量或外部 Office，P10–P12 继续实施。

P10 文档墨迹通过 2 项新增核心和 6 项既有图形回归。检查原生折线、单点、圆端/连接、透明度、锚点、选择与文字保持、只读预览、缩放/改色、轮廓命中、整笔擦除、富文本复制、精确历史、重开及未知源/锁/字体/预算失败。接口 3 项、143 个断言通过。1 条 Chromium 通过默认工具、颜色/线宽、绘制中保存、Escape 取消、空框与实际笔画擦除、原生输入、完整精确历史及保存重开。独立 XML 检查两条原生路径、段落锚点、圆连接及 45000 透明度；三个 Canvas/PDF 像素检查红线、空白与透明黄线，qpdf、PDF 文字和源字节保持通过。公开 api/check/build、私有 TS/lint/格式通过，证据归 `docxInkCheckpoint`。保持 20 秒和零重试，未跑全量、外部 Office 或安装包矩阵，P10–P12 继续实施。

P10 文字修订记录通过 4 项新增核心和 8 项既有审阅/目录回归。检查混合运行格式、原生身份与作者/时间、连续输入、组合取消/提交、删除已有修订的顺序、关闭记录后的编辑、单元格、精确历史及非法输入/未知源/预算失败。接口 2 项、33 个断言通过。1 条 Chromium 检查默认作者/开关、原生输入和删除、关闭后编辑、完整精确历史、保存重开、批量接受/拒绝；独立 XML 检查原生插入/删除和元数据，qpdf、独立 PDF 文字及其他部件保持通过。公开 api/check/build 和私有 TS/lint/格式通过。字段回归发现未解决修订内的字段标记污染后续段落，修复后 8 项回归通过。证据归 `docxTrackingCheckpoint`。保持 Chromium 20 秒、零重试；未跑全量、外部 Office 或安装包矩阵，P10–P12 仍未完成。

P10 字符/段落格式记录通过 3 项新增核心和 19 项既有回归，覆盖部分运行、连续快照、元数据、段落标记保持、正文多段/普通单元格、与文字插删混合、内层属性和外层文字的批量处理、精确历史、无变化和受保护源/旧修订/输出失败。既有 9 项格式检查覆盖常规输入、格式刷、制表位、继承及失败恢复；另外 10 项文字记录与审阅检查通过。扩展原有 1 条 Chromium 流程，检查默认粗体/斜体/居中、完整撤销重做、重开后在已有属性修订内原生输入；独立 XML 检查两个原生字符快照、一个段落快照、作者及当前/旧属性，接受保留粗斜体和居中，拒绝恢复继承。qpdf 和独立 PDF 文字通过。公开 api/check/build 和定向私有 TS/lint/格式通过，证据归 `docxFormatTrackingCheckpoint`。首次浏览器检查对运行数量的假设与前序审阅生成的 A/lpha 两个原生运行不符，按实际源结构改正数量并保留全部属性断言后通过。保持 Chromium 20 秒、零重试；未跑全量或外部 Office，P10–P12 继续实施。

P10 跨格/整表格式修订通过 27 项定向核心，含 3 项新增和 24 项已有文字记录、审阅、常规格式及跨格格式回归。检查反向矩形、空段落标记、源身份与连续快照、合并拥有者及续接格排除、跨完整表格的正文范围、范围外源、精确历史、部分审阅后的选区恢复、空段落继承输入和段末定位。追加未知段落属性/重复 pPr 保护后，7 项相关核心再次通过，验证记录中的文字重建也原子拒绝，保留重做。1 条 Chromium 通过默认记录/下划线/居中/斜体控件、矩形无障碍状态、完整历史、重开后重新选择与输入、连续输入单次撤销。独立 XML 检查 5 个字符快照、5 个段落快照、空段落标记独立源、作者、范围外单元格/部件及接受/拒绝属性；qpdf 和独立 PDF 文字通过。公开 api/check/build 和定向私有 TS/lint/格式通过，证据归 `docxCellFormatTrackingCheckpoint`。保持 Chromium 20 秒、零重试；未跑全量或外部 Office，结构修订及其余 P10–P12 继续实施。

P11 原生线程批注通过 3 项新增核心、3 项既有便笺回归和 2 项接口检查（25 个断言）。检查多部件创建、回复、正文更新、解决/重开、删除、无变化、精确历史及保存重开；独立导入源覆盖作者 provider 元数据、回复先于主批注、旧占位文字、原生提示和源保持。非法源、缺失身份、未知扩展、占位冲突、旧 revision、输出失败及未接入的结构操作保留源与历史。1 条 Chromium 通过默认作者/批注控件、完整字节历史、原生单元格输入及重开；独立 XML/VML 检查身份、作者、正文、父关系、状态和删除，qpdf 与独立 PDF 提取确认批注不进入默认输出。公开 api/check/build 和定向私有 TS/lint/格式通过。接口检查发现初始化循环，网格校验已移回所属模块，保留全部校验。浏览器首次超时后合并历史读取，保留全部字节断言和默认撤销/重做按钮；PDF 检查复用现有 OPEN_DOCUMENT_PDFTOTEXT。保持 20 秒、零重试，未跑全量或外部 Office。证据归 `xlsxThreadsCheckpoint`，线程引用变换及其余 P10–P12 继续实施。

P11 线程批注的行列及区域插删通过 3 项新增核心和 6 项既有线程/便笺回归。检查主批注和回复的完整归属、缺少 ref 的回复、导入 xr:uid、作者/时间/解决状态、VML Anchor 保持、范围外源、跨表公式、非活动选区、精确混合历史及重开；溢出、未知源、旧 revision 和输出失败保留字节、选择与重做。空工作表的多行格式插入暴露重复展开 sheetData 的 XML 重叠，改为合并新增行后一次展开，原空白输入与全部断言保留。1 条 Chromium 检查默认插行/插列/删行、右移插格/左移删格、原生批注与 VML、删除全部回复、精确撤销重做、重开后的原生 Tail! 输入和无障碍提示。独立 XML、qpdf 和 PDF 文字检查通过，批注不进入默认静态 PDF。公开 api/check/build、私有定向 TS/lint/格式及两个 diff 检查通过。证据归 `xlsxThreadAxisCheckpoint`。保持 20 秒、零重试，未跑全量或外部 Office；排序/填充、整表变换及其余 P10–P12 继续实施。

P11 原生线程的数据操作通过 5 项新增核心和 4 项既有便笺回归。覆盖行/列排序的标题、隐藏轴和空格、身份/回复/作者/时间/解决状态、范围外源、重复排序无变化、普通区域及原生表去重的保留/删除归属、表范围缩小、四向/自动序列/收缩填充的资源字节保持、三种清除、空格/完整合并格、精确历史及重开。未知原生正文、不匹配 VML 和输出失败保留原文、选择、revision 与重做。1 条 Chromium 通过默认排序、填充、去重预览/删除、空格全部清除、清内容保留线程、精确撤销重做和重开后的原生 Retained! 输入。独立 XML/VML 检查记录归属、填充保持、完整线程删除及资源数量；qpdf 和独立 PDF 文字检查通过，批注不进入默认输出。公开 api/check/build 和定向私有 TS/lint/格式通过。证据归 `xlsxThreadDataCheckpoint`。保持 Chromium 20 秒、零重试；未跑全量或外部 Office，线程整表/结构化区域转移及其余 P10–P12 继续实施。

P11 原生线程的整表事务通过 2 项新增核心和 6 项既有线程/便笺回归。检查独立原生 XML、回复先于主批注且省略 ref、解决状态、消息/父身份/占位符/已知 xr:uid 重映射、共享作者字节、普通便笺共存、独占资源删除、分别编辑、改名/移动/显隐、精确混合历史及重开后继续回复。未知正文和出站关系、旧 revision、最后可见表及输出失败保留文档与重做。公开 API 和构建通过；此前 3 条线程 Chromium 结果仍适用，本次未增加浏览器用例或全量检查。证据归 `xlsxThreadSheetCheckpoint`。结构化区域转移、合并及其余 P10–P12 继续实施。

P11 线程合并通过 3 项新增核心与 6 项既有线程/便笺回归。检查单线程无损移动、缺少 ref 的回复、原生身份/正文/日期/解决状态/已知 xr:uid、VML Anchor 与范围外源保持；普通便笺和线程混合的源顺序保留、完整线程与全部回复删除、显式丢弃确认、无变化、取消合并、精确混合历史及重开后回复。已有独立导入源增加未知正文、重复身份、缺失作者、非法父关系和占位冲突的合并原子拒绝；旧 revision 和输出预算保留源、选择与历史。1 条 Chromium 通过默认确认/合并/取消合并、精确撤销重做、重开后修改批注和原生 Merged! 输入。独立 XML/VML 检查身份、回复归属和完整删除，qpdf 和 PDF 文字检查通过，批注不进入默认静态输出。公开 api/check/build、私有定向 TS/lint/格式及 diff 检查通过。证据归 `xlsxThreadMergeCheckpoint`。既有便笺浏览器仅更新确认文案并直接审阅；未增加专项快照或重跑该完整流程。保持 20 秒、零重试；未跑全量或外部 Office，线程结构化区域复制/剪切及其余 P10–P12 继续实施。

P11 原生线程剪切通过 3 项新增核心与 2 项既有便笺迁移回归。检查四向同表重叠、完整目标线程覆盖、源身份/父关系/作者/时间/解决状态保持、空格线程和普通便笺、两种工作表处理顺序及缺少/已有目标资源、继承 ref、导入 provider 元数据和 xr:uid、原生正文与 VML Anchor/外观、分别编辑与移回、精确混合历史和重开回复/公式输入。未知原生内容、错误 VML、目标保留身份冲突、旧 revision 和输出失败保留字节、选择、重做及资源状态。1 条 Chromium 通过默认剪切标记不改文档、跨表原生粘贴、完整线程/回复覆盖、精确撤销重做、重开后默认批注修改和原生输入，独立 XML/VML/公式缓存及无障碍描述通过；qpdf 与 PDF 文字确认结果 12/36，批注不进入输出。公开 api/check/build、私有定向 TS/lint/格式及 diff 检查通过，证据归 `xlsxThreadMoveCheckpoint`。保持 20 秒、零重试；未跑全量或外部 Office，线程结构化区域复制及其余 P10–P12 继续实施。

P11 原生线程结构化复制通过 3 项新增核心及 7 项既有线程/整表复制/便笺片段回归。检查仅捕获所选消息和必要作者、源后续修改不改变快照、独立身份/父关系/占位符/修订身份、导入 provider 信息与同名异账号、跨工作簿和重复/转置粘贴、作者复用、继承 ref、目标完整线程覆盖、三种选择性模式保留与空片段清除、精确混合历史和重开编辑。非法配对、原生图、无关作者、范围、旧 revision 和输出失败保留源、选择与重做。补充 1.1 Mi 命名空间输入，验证捕获及作者导入在展开时原子拒绝；3 项新增核心再次通过。3 项接口检查共 117 个断言，复用已有剪贴板验证 helper，并更新其原生字段合同；未跑安装矩阵。1 条 Chromium 通过默认跨文档复制/粘贴、作者元数据冲突、重复转置、完整字节历史、重开批注修改与原生 13 输入；独立 XML/VML 检查新身份、父关系、时间、作者及缓存 39，qpdf 和 PDF 文字通过。浏览器早于仅限制大命名空间的最后保护，普通输入证据继续适用。最终公开 api/check/build、定向私有 TS/lint/格式与 diff 检查通过；证据归 `xlsxThreadClipboardCheckpoint`。保持 20 秒、零重试；未跑全量或外部 Office，P10–P12 继续实施。

P10 HTML/Markdown 水平线通过 3 项新增核心及 6 项既有输入/图片回归。三种方式、目标正文缩进、不等宽第二栏、现有格和导入合并格、引用列表、图片身份共存、独立原生线形/颜色/线宽、精确混合历史及重开编辑通过；非法源、尺寸、绘图上限、旧 revision、缺字体和输出失败保留文档、选择与重做。追加实际合并格和 16 px 厚边框断言后，3 项新增核心再次通过；原生边框换算复用，文字宽度扣除半边框与默认边距的较大值。浏览器输入不含表格，最后这项格内宽度修正不改变其路径，既有结果继续适用。1 条 Chromium 检查默认 HTML/Markdown 粘贴、原生输入、完整字节历史、重开后默认形状编辑及真实 Canvas/PDF 线条；独立 XML、qpdf、PDF 文字和无图片 XObject 证明矢量输出。首轮细灰线像素断言未计抗锯齿，保留失败 JSON/截图后改查超过 250 px 的连续灰线，未修改产品或放宽运行预算。公开 api/check/build 和私有定向 TS/lint/格式通过，公共 API 未变；证据归 `markupRulesCheckpoint`。保持 20 秒、零重试；未跑全量或外部 Office，平面实线以外效果及其余 P10–P12 继续实施。

P12 表格预设虚线通过 3 项新增核心和 8 项既有单元格格式/原生样式/可移植整表复制回归。11 种线型、有效线宽节奏、共享边和区域优先级、继承恢复、颜色/线宽保持、关闭源后的跨文稿独立重复粘贴、原生文字、精确历史及重开通过。未知/重复/自定义线型、部分相邻合并格、旧 revision、缺字体和输出失败保留源、选择与重做。1 项接口检查复用原有表格包 helper，共 146 个断言；新增 nullable `borderDash` 为必需字段。2 条 Chromium 通过新默认线型流程和既有反选格格式流程，独立 XML/ZIP 保留 16 条源边及复制身份；Canvas/PNG 与 Poppler PDF 采样确认 2 pt 长划线的 16 pt 线段与 6 pt 白色间隙，qpdf 和独立 PDF 文字通过。精确混合历史、重开后的原生输入、系统复制及独立重复粘贴已检查。公开 api/check/build、定向私有 TS/lint/格式及两仓 diff 通过；证据归 `tableDashCheckpoint`。私有组/结构用例只随内部边框三元组机械补 `solid` 并审阅，未重跑这些未改流程；未跑全量、安装矩阵或外部 Office。保持 20 秒、零重试；自定义/透明边框及其余 P10–P12 继续实施。


P10 段落修订通过 4 项新增核心及 14 项既有文字/格式/跨格/审阅回归。检查导入的连续插入/删除标记、段末定位、拆段后输入和格式混合处理、正文及同格跨段替换、双向删除、取消本作者新增边界、精确字节与选择历史、保存重开及后续输入。格式和文字结果使用独立预期；非法或末段标记、输入段数和输出预算失败保留源与重做。1 条 Chromium 检查原生 Enter/Backspace/Delete、系统多行粘贴、默认定位与逐项接受/拒绝、完整混合历史和重开输入；独立 XML 检查原生标记位置及作者，qpdf 和 PDF 文字通过。公开 api/check/build、私有 TS/lint/格式和两仓 diff 已检查，公共 API 未变；证据归 `trackedParagraphCheckpoint`。保持 20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。


P12 表格边框不透明度通过 3 项新增核心及 11 项既有虚线、单元格格式、样式和整表复制回归。检查导入透明度、0/25/50/100%、透明胜出边、共享边单次绘制、颜色/线宽/虚线保持、主题色变换、混合查询、关闭源后的独立重复粘贴、原生文字、精确历史及重开。参数、旧 revision、缺字体、部分相邻合并格、无填充及输出预算失败保持源、选择与重做；含注释的颜色源继续拒绝。既有接口 helper 扩展为必需 nullable `borderOpacity`，1 项检查共 155 个断言通过。扩展既有 Chromium 虚线流程，并按编辑/输出和剪贴板拆为 2 条用例，保留全部原断言及 20 秒时限；独立 XML 检查 16 条透明边及两个副本的分别编辑，PNG 和 Poppler PDF 同时采样顶边与共享边的半透明红色，验证没有重复混色。qpdf、PDF 文字、完整混合历史和重开输入通过。公开 api/check/build、定向私有 TS/lint/格式及两仓 diff 通过；证据归 `tableOpacityCheckpoint`。组/结构用例仅机械补充不透明值 1，未重跑这些未改流程；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P11 静态未计算链隔离通过 3 项新增及 7 项既有核心检查。覆盖完整上下游、无关联输入及重算、纯格式和行显隐、名称/共享/跨表、缓存保留、精确历史、重开，以及关联输入、新公式、结构、SUBTOTAL 可见性和输出失败的原子保护。1 条 Chromium 检查默认原生输入、未计算格加粗、混合字节历史、重开及后续输入；独立 XML 验证公式及 777/778 导入缓存，qpdf 和 PDF 文字验证独立选区输出，完整打印拒绝后仍可输入。公开 api/check/build、定向私有 TS/lint/格式及两仓 diff 通过；证据归 `isolatedCalculationCheckpoint`。保持 20 秒、零重试；未跑全量、安装矩阵或外部 Office。当前仅开放 16 项静态数学函数的隔离，动态和未核实函数、结构变化及需要已计算来源的关联资源继续保护，其余 P10–P12 继续实施。

P11 未计算图表通过 2 项新增及 7 项既有核心检查。覆盖导入图表 20 与公式格 777 的独立缓存、实际图元与状态、无关联输入和格式、完整字节历史、重开及独立区域打印；关联分类/标题/数值、公式、显隐和剪贴板转换拒绝后保留源、选择和重做。缓存长度不符安全拒绝，显式改绑后恢复实时 50 及图表打印。3 条 Chromium 检查新图表流程及既有来源删除/公式隔离；补充关联原生输入失败、Escape 和完整字节恢复后，只重跑新增流程并通过。独立 XML 保留缓存并验证改绑后的 50，qpdf 与 PDF 文字验证实际图表，无 777。公开 api/check/build、私有定向 TS/lint/格式、行数、登记、链接及两仓 diff 通过；证据归 `uncalculatedChartCheckpoint`。保持 20 秒、零重试；未跑全量、安装矩阵或外部 Office。动态/不透明源、未计算来源的外观修改及更多关联资源继续保护，P10–P12 继续实施。

P12 表格底色不透明度通过 2 项新增及 14 项既有核心检查。覆盖单格/整表的 0/25/50/75/100%、无填充格保持、混合查询、颜色替换保持透明度、主题占位与 tint 及区域优先级、关闭源后的独立重复复制、原生输入、精确历史和重开；非法值、旧 revision、缺字体、无填充及输出失败保留源、选择和重做。既有接口 helper 扩展为必需 nullable `fillOpacity`，共 164 个断言通过。3 条 Chromium 包括新默认底色流程及既有边框/剪贴板流程；独立 XML 检查一格 25% 蓝色、三格 50% 红色及其他部件保持，PNG 和 Poppler PDF 采样验证实际混色，qpdf 与 PDF 文字通过。公开 api/check/build、私有定向 TS/lint/格式、行数、登记、链接及两仓 diff 通过；证据归 `tableFillOpacityCheckpoint`。保持 20 秒、零重试；未跑全量、安装矩阵或外部 Office。其余 P10–P12 继续实施。

P10 默认批量审阅通过 1 条新增和 2 条既有 Chromium 流程。检查作者筛选的两项插入一次接受、类型筛选的两项删除一次拒绝及单元格格式处理，每批只增加一个 revision；三步完整字节撤销/重做、空结果和不支持条目禁用、保存重开及后续原生输入通过。独立 XML 验证处理范围、保留格式、不透明修订原文和其他部件保持；既有逐项流程及 PDF 回归同时通过。公开 check/build、私有定向 TS/lint/格式、行数、登记、链接及两仓 diff 通过；证据归 `revisionBatchUiCheckpoint`。本次仅接通已有批量核心事务的默认 UI，复用既有核心证据，未重跑核心测试。保持 20 秒、零重试；未跑全量、安装矩阵或外部 Office，P10–P12 继续实施。

P11 三角函数、PI 及角度换算通过 2 项新增及 11 项既有核心检查。独立数值覆盖弧度、负角、极点附近有限正切、微小正弦、类型转换、错误与参数数目；名称/共享/跨表重算、陈旧缓存更新、结构引用维护、完整字节历史及重开后输入通过。原未计算链夹具改用仍未求值的 ASINH/COSH，保留全部原断言并重跑。3 条 Chromium 包含新原生混合公式、45/0 输入重算、独立 XML/PDF 和完整历史，以及既有未计算公式/图表保护、改绑和恢复；旧缓存 777/888 不进入实际输出。公开 api/check/build、私有定向 TS/lint/格式、源码行数、身份、登记、链接及两仓 diff 通过；证据归 `trigonometryCheckpoint`。保持 20 秒、零重试；未跑全量、安装矩阵或外部 Office，数组及其余数学函数继续实施，P10–P12 保持部分交付。

P12 RTL 表格通过 2 项新增与 7 项既有核心检查，覆盖不等列宽、合并主格、格内文字方向保持、镜像坐标与命中、范围、水平格边界及上下导航、物理共享边及透明度、原生区域边框、方向无变化和旧 revision/缺字体原子保护、结构/样式修改、独立重复粘贴、精确字节历史与重开。既有接口 helper 扩展为必需布尔 `table.rtl` 和严格 `tableDirection`，174 个断言通过。新增 Chromium 流程检查默认开关、原生双击入格、左键跨格、输入、保存重开及完整历史；qpdf、独立 PDF 字坐标、PNG 与 Poppler PDF 像素比较及原单元格属性/其他部件保持通过。既有单元格旋转、文字矩阵、链接、输入及 PDF 流程通过。公开 api/check/build、私有定向 TS/lint/格式、源码行数、登记、链接及两仓 diff 检查通过，证据归 `tableRtlCheckpoint`。复用同次既有流程结果，仅重跑修正后的新增流程；20 秒、零重试。未跑全量、安装矩阵或外部 Office，P10–P12 继续实施。

P10 公式交换输出通过 2 项新增及 4 项既有核心检查，覆盖现有九类表达式、嵌套、行内/独立上下限、矩阵列及多行对齐、空格、字面 Markdown 和恶意标记转义。独立 XML 与 CommonMark 检查 MathML 命名空间及段落/列表 HTML 块；未知数学、有效缓存字段、待处理修订及输出预算失败保留源、选择和重做。新增 Chromium 流程验证默认 HTML/Markdown 菜单、原生输入、真实分数/脚标/上下限/矩阵/多行坐标、精确历史和重开；既有普通交换输出流程的同次通过结果复用。标准对齐值后补 Chromium 使用的 CSS 对齐值，修复实际矩阵和多行右对齐。公开 api/check/build、私有定向 TS/lint/格式、行数、测试源身份、登记、链接及两仓 diff 通过，DOCX 公共接口未变；证据归 `mathMarkupCheckpoint`。保持 20 秒、零重试；未跑全量、安装矩阵或外部 Office。字体不嵌入，阅读器度量可能不同；MathML 粘贴导入及其余 P10–P12 继续实施。

P10 简单域交换输出通过 2 项新增及 2 项既有 MathML 核心检查。实际两页分页、节罗马页号、总页数、隐藏序列计数、文字及页号引用、首结果格式、空缓存、合并格、书签大小写、转义、原生输入、精确历史和重开通过。缺失/旧布局、布局诊断、不可用位置、输出预算、复杂/未知字段及待处理审阅均保持源和重做。1 条 Chromium 检查默认 HTML/Markdown 菜单、实际值与样式、可点击书签、独立 ZIP 保留七组 777/stale 源缓存、零外链请求、完整历史、预算失败恢复和重开相同 HTML。公开 api/check/build、私有定向 TS/lint/格式、源码身份、行数、登记、链接及两仓 diff 通过；证据归 `fieldMarkupCheckpoint`。核心只新增可选布局参数，沿既有字段结果及 PDF 引用规则，无新 SDK 命令或依赖。保持 20 秒、零重试；复用既有普通输出浏览器结果，未跑全量、安装矩阵或外部 Office。页码按原 DOCX 布局输出静态值；更广区域和其余 P10–P12 继续实施。

P10 图表交换输出通过 2 项新增及 4 项既有字段/MathML 核心检查。原生更新覆盖现有 14 种配置，独立 XML 检查 SVG 命名空间及本地字形引用，CommonMark 检查 HTML 块；字面标签、变换/裁剪、缺失/旧布局、缺少字形或位置、不平衡状态、输出预算、精确历史及重开通过。1 条 Chromium 验证默认 HTML/Markdown 菜单、正文柱图和合并格饼图、独立字形/裁剪身份、尺寸、标签、两份嵌入工作簿及零外链请求。独立 SVG 与原生 Canvas 的 280×180 区域双方零缺失像素，蓝/橙/文字像素计数均一致；原生输入、预算失败后的重做、精确字节和重开相同 HTML 通过。公开 api/check/build、私有定向 TS/lint/格式、源码身份、行数、登记、链接及两仓 diff 通过；证据归 `chartMarkupCheckpoint`。复用既有可选布局和桥接上下文，无新接口或依赖；20 秒、零重试。未跑全量、安装矩阵或外部 Office。SVG 是带完整数据标签的静态插图，其余 P10–P12 继续实施。

P10 绘图与字段/公式的同段插入通过 2 项新增及 4 项既有图片插入/图表输出核心检查。图片、基础图形和图表分别在完整对象两侧插入，检查普通单元格、样式、逻辑光标、后续文字与对象修改、精确混合历史及重开；未改字段注释原文保留，实际缓存重写继续拒绝。未知/锁定字段、未支持数学、审阅及多部件预算失败保持源、选择和资源。1 条 Chromium 通过默认 Home/插入图表、原生输入、图表更新、字段/公式原文和顺序、当前嵌入关系与 30/40 缓存、HTML/Markdown、qpdf 及独立 PDF 文字、三步完整字节历史、相同 HTML 重开和后续输入。公开 api/check/build、私有定向 TS/lint/格式、源码身份、行数、登记、链接及两仓 diff 通过；证据归 `drawingInlineCheckpoint`。共用源事务只补字段/数学范围与完整对象边界，无新增接口或依赖；20 秒、零重试。未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P10 注释交换输出通过 2 项新增与 4 项既有简单域输出/注释创建核心检查，既有 MathML 同次结果复用。两节 V/1/C 编号、按节重启、合并格引用、不同注释身份、格式、多段与空段、字面 Markdown、独立 XML 锚点及 CommonMark HTML 块通过。注释位置校验补齐已有分节参数，分节段落原生输入、精确历史和未改注释源保持；缺失/重复注释、未知结构、注释字段/列表、无效布局、后续节页眉和预算失败保留原包与重做。1 条 Chromium 通过默认 HTML/Markdown 菜单、实际 PAGE VII、全部往返链接、蓝色粗体、空段、两步精确历史、独立 ZIP 缓存/其他部件保持、零外链请求及正常保存重开相同 HTML。公开 api/check/build、私有定向 TS/lint/格式、行数、源码身份、登记、链接及两仓 diff 通过，证据归 `noteMarkupCheckpoint`。复用既有接口与布局，无新增依赖；20 秒、零重试。注释统一降级为文末分组，多节页面几何不转移。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P10 分节段落查找替换通过 2 项新增与 4 项既有核心检查。三节正文的可编辑结果、注释引用、普通批量、LF 拆段、跨节合并、节内容/注释/缓存保持、精确三步历史及重开输入通过；未知/重复属性、旧修订、Unicode、重叠、截断和保护原子拒绝。1 条 Chromium 通过默认查找定位、原生输入、单项及全部替换、SDK LF 替换、独立 XML 节归属与 ZIP 部件保持、实际分页文字、四步精确历史及保存重开后查找输入。公开 api/check/build、私有定向 TS/lint/格式、行数、源码身份、登记、链接及两仓 diff 通过，证据归 `sectionSearchCheckpoint`。两处校验补齐已有分节参数，无新接口或排版算法；20 秒、零重试。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P11 反三角函数通过 2 项新增及 5 项既有三角/未计算链核心检查。ACOS/ASIN/ATAN 的弧度、ATAN2 的四象限及坐标顺序、坐标轴、大数与次正规数、数值转换、越界/原点/错误传播、严格参数数目、名称/共享/跨表依赖、原生缓存、插行、精确历史和预算失败保持通过。1 条 Chromium 通过默认公式栏、旧导入公式解除保护、原生输入、全部函数重算、独立 ZIP/XML 缓存及错误类型、其他部件保持、两步精确历史、重开输入、qpdf 与独立 PDF 文字。历史按钮后等待已确认 revision，保留完整字节比较、20 秒和零重试。公开 api/check/build、私有定向 TS/lint/格式、行数、源码身份、登记、链接、生成接口及两仓 diff 通过；证据归 `inverseTrigonometryCheckpoint`。无新接口、依赖或 TS 计算，剩余十项静态函数仍沿未计算链保护。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P12 双段直角连接线通过 2 项新增及 4 项既有折线/端点手势核心检查，传输检查 65 个断言通过。1 条 Chromium 检查默认面板、目标联动、类型切换与断开、独立 XML、四步精确历史、重开及 Canvas/PDF 像素。核心另覆盖箭头方向、翻转/零尺寸轴、预览取消、组合复制引用、未知导引及预算失败。公开 api/check/build、私有定向 TS/lint/格式、行数、源码身份、登记、链接、生成接口及两仓 diff 通过；证据归 `rightAngleConnectorCheckpoint`。复用既有折线路径和连接事务；固定单转折无调节导引或自动避障。20 秒、零重试；未跑全量、安装矩阵或外部 Office，P10–P12 继续实施。

P11 指数与对数通过 2 项新增和 5 项既有反三角/未计算链核心检查。39 个标量预期覆盖类型、默认/显式底数、定义域、参数错误、溢出与下溢；共享/名称/跨表依赖、原生缓存、插行、精确历史、重开及预算失败通过。1 条 Chromium 检查默认公式栏、旧导入公式重算、独立 ZIP/XML 值与错误类型、无关部件保持、两步精确历史、重开负数输入及独立 PDF 文字。公开 api/check/build、定向私有 TS/lint/格式、行数、源码身份、登记、链接、生成接口及两仓 diff 通过，证据归 `logarithmsCheckpoint`。复用既有计算路径，无新接口或依赖；20 秒、零重试。未跑全量、安装矩阵或外部 Office；其余六项双曲函数继续保留未计算链保护，P10–P12 继续实施。

P11 双曲函数通过 2 项新增与 5 项既有对数/未计算链核心检查。30 个标量预期覆盖符号、对称性、极小值、溢出/饱和、数值转换及错误；导入共享/名称/跨表公式、原生缓存、插行、两步精确历史、重开和预算失败通过。1 条 Chromium 检查默认公式栏、全部函数重算、独立 ZIP/XML、无关部件保持、精确历史、重开负数输入及独立 PDF 数值和错误。公开 api/check/build、定向私有 TS/lint/格式、行数、源码身份、登记、链接、生成接口及两仓 diff 通过，证据归 `hyperbolicCheckpoint`。既有隔离夹具改用仍未求值的 ACOSH，保护和历史断言不变。无新接口或依赖；20 秒、零重试。未跑全量、安装矩阵或外部 Office；三项逆双曲函数继续沿未计算链保护，P10–P12 继续实施。

P10 被引来源书目通过 2 项新增及 6 项既有书目/引文核心检查。简单域、跨 run 复杂域和表格引用、标签去重、存储顺序、未引用未知来源保留、新来源引用后的显式更新、删除末次引用后的空缓存、精确混合历史、重开及字体/归属/资源预算保护通过。扩展既有 Chromium 流程检查默认面板、来源修改和缓存更新、旧目录恢复、完整字节历史、独立原生控件/样式/三条来源及未知元数据、无关 ZIP 部件、重开输入与 PDF 纳入/排除。公开 api/check/build、定向私有 TS/lint/格式、行数、源码身份、登记、链接、生成接口及两仓 diff 通过，证据归 `citedBibliographyCheckpoint`。复用既有引用扫描，无新接口、配置或依赖；20 秒、零重试。未跑全量、安装矩阵或外部 Office；完整引用样式和自动更新仍未完成，P10–P12 继续实施。

P12 六角星扩展既有多边形、调节手势、连接点及类型修改共 9 项核心检查，未新增核心用例。独立顶点/文字区域、最大内半径的框外轮廓命中、六点顺序和吸附、标准/未知导引、旋转/翻转候选与取消、复制、类型修改、精确历史及重开通过。传输检查 3 项、104 个断言通过。1 条 Chromium 检查默认插入、填充、内半径及最大值的框外实际点击、原生输入、完整字节历史、重开、独立 XML、五处 Canvas/独立 PDF 轮廓像素及 PDF 文字。公开 api/check/build、定向私有 TS/lint/格式、行数、源码身份、登记、链接、生成接口及两仓 diff 通过，证据归 `sixPointStarCheckpoint`。无新增命令、依赖或渲染路径；20 秒、零重试。未跑全量、安装矩阵或外部 Office，其他预设及其余 P10–P12 继续实施。

P12 四角星和八角星扩展既有预设用例，9 项多边形/调节/连接/类型检查及 4 项共享文字框检查通过，未新增核心用例。独立顶点、文本区域、4/8 点顺序、吸附、旋转/翻转候选、导引保护、复制、精确历史与重开通过。空四角星创建、真实输入保留 X、实际溢出诊断及撤销通过。传输检查 3 项、106 个断言通过。1 条 Chromium 检查默认四角星、内半径、一次原生文本输入、改为八角星、默认值重置、六步完整字节历史、重开及最终八角星的独立 XML、五处 Canvas/PDF 轮廓和 PDF 文字。公开 api/check/build、定向私有 TS/lint/格式、行数、源码身份、登记、链接、生成接口及两仓 diff 通过，证据归 `pointStarsCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其他预设和 P10–P12 继续实施。

P11 ACOSH/ASINH 扩展既有双曲函数检查，未新增用例。9 项定向核心通过，包含 30 个新增标量预期、共享/名称/跨表重算、插行、原生缓存、精确历史、重开及预算失败；未计算链和图表回归改用 ATANH，保留全部保护断言。4 条既有 Chromium 流程通过；初次图表撤销比对未等待 UI 修订确认，补上等待后仅重跑该失败流程，保留完整字节、XML/PDF 与恢复断言。公开 api/check/build、定向 TS/lint/格式、行数、源码身份、登记、链接、生成接口及两仓 diff 通过，证据归 `inverseHyperbolicCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，ATANH 与其余 P10–P12 继续实施。

P12 十角星和十二角星扩展既有用例，未新增用例。9 项定向核心检查独立轮廓、文字矩形、导引/边界、10/12 点原生顺序、末点连接保存重开、旋转/翻转预览取消、复制、类型修改及精确历史。4 项传输检查、175 个断言通过，覆盖索引 11/数量 12 的接受及索引 12/数量 13 的拒绝。1 条 Chromium 保留四角星/八角星与原生输入，再切换十角星/十二角星、连接末点，检查原生 XML、十步完整字节历史、重开及最终十二角星的五处 Canvas/PDF 轮廓和 PDF 文字。首个浏览器失败发现旧 8 点查询上限，核心与传输边界同步修正后通过。公开 api/check/build、定向 TS/lint/格式、行数、源码身份、登记、链接、生成接口及两仓 diff 通过，证据归 `tenTwelvePointStarsCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余预设和 P10–P12 继续实施。

P10 HTML 百分比列宽通过 1 项新增和 9 项既有核心检查。独立预期覆盖百分比/点数/未指定列、实际双栏、绝对表宽、跨列和 twip 余数；网格与布局单元格宽度一致，三种粘贴方式、两步精确历史、重开及非法百分比保护通过。扩展 1 条既有 Chromium 流程，检查默认粘贴、原生网格/合并/重复表头/资源、文字与题注输入、完整字节历史、重开、多页 PDF 文字和图片/底色像素及纯文本粘贴。公开 api/check/build、定向 TS/lint/格式、行数、源码身份、登记、链接、生成接口及两仓 diff 通过，证据归 `htmlPercentColumnsCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，内容自动宽度与嵌套表格仍待实现，P10–P12 继续实施。

P11 TEXT 与数字格式共用的 14 项定向核心检查通过，包含 1 项新增数字格式用例、19 个独立格式预期、既有 TEXT 的 26 个标量预期，以及样式/清除/格式刷、未计算链和资源保护回归。31 种格式中的美元/人民币与小数位、十进制/百分比舍入、类型、日期系统、公式显示下的数值/货币/百分比与隐藏源、共享/名称/跨表及格式参数重算、缓存、结构、精确历史和重开通过。既有传输检查扩展到 78 个断言；扩展 1 条 Chromium 检查默认货币控件、TEXT、独立原生样式和字符串缓存、三步完整历史、重开负数输入、实际 PDF 文字及输出源不变。公开 api/check/build、定向 TS/lint/格式、行数、源码身份、登记、链接、生成接口及两仓 diff 通过，证据归 `textFormatCheckpoint` 和 `numberFormatsCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office。更广自定义、会计和多段格式继续保护，P10–P12 继续实施。

P12 四段/五段折线扩展既有连接线用例，4 项定向核心与 73 个传输断言通过。独立五点/六点路径、两个/三个 XY 手柄、默认值、箭头、旋转/翻转拖动与边界、候选取消、端点/目标联动、类型切换、组合复制、精确历史、重开及未知/重复导引、锁和预算保护通过。既有浏览器参数流程增加两条对应 Chromium，检查默认插入和全部转折数值控件、真实垂直手柄拖动及取消、独立原生 XML、未改源部件、七步/八步完整字节历史、重开和 Canvas/独立 PDF 线段。公开 api/check/build、定向私有 TS/lint/格式、行数、测试源码身份、登记、链接、生成接口及两仓 diff 通过，证据归 `fourSegmentConnectorCheckpoint` 和 `fiveSegmentConnectorCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，框外转折与其余 P10–P12 继续实施。

P11 现代倍数取整和 SIGN 扩展既有数值用例，未新增用例。5 项定向核心通过，55 个新增标量值覆盖负数 mode、倍数符号、默认/空白、类型/错误、有限边界和标准前缀；共享/名称/跨表、旧缓存、插行后前缀、两步完整字节历史和重开通过，原有 ATANH 保护与预算检查保持。1 条既有 Chromium 通过实际公式栏、依赖修改、独立标准 _xlfn/XML 缓存、未改 ZIP 部件、精确撤销重做、重开继续输入及独立 PDF 的 31.01。旧范围选择器按当前导航表单收窄，保留原生导航和全部预期；前缀写回补齐后重跑相关核心、公开构建和同一浏览器流程。公开 api/check/build、定向 TS/lint/格式、行数、源码身份、登记、链接和两仓 diff 通过，XLSX 公开接口不变，证据归 `modernRoundingCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其他函数和 P10–P12 继续实施。

P12 单段/三段/四段曲线通过 2 项新增与 4 项既有核心检查。独立默认/修改后贝塞尔控制点、XY 手柄、路径命中/离线点、箭头、旋转/翻转拖动预览取消与精确历史、目标联动、类型切换、组合引用复制、重开、零尺寸轴及未知/重复/框外导引和预算原子保护通过。82 个传输断言通过。既有连接线参数流程增加 1 条四段曲线 Chromium，检查三个数值控件、实际手柄拖动取消、原生 XML/导引/连接、未改 ZIP 部件、八步完整字节历史、重开及四段独立采样点的 Canvas/Poppler PDF 颜色。公开 api/check/build、定向私有 TS/lint/格式、行数、源码身份、登记、链接及生成接口检查通过，证据归 `curvePresetsCheckpoint`。保护夹具已限定到实际连接线节点，保留全部拒绝和源断言。20 秒、零重试；未跑全量、重复曲线浏览器矩阵、安装包或外部 Office，框外导引及其余 P10–P12 继续实施。

P10 页边框主题色通过 8 项定向核心，覆盖映射和明暗变换、保留原生属性、首次主题部件与关系/类型的原子创建、绑定/解除、固定色、六步完整历史、无操作、重开、预算及多节/布局回归。既有 3 项页设置传输检查共 142 个断言通过，新增必填可空 `themeColor` 的接受/拒绝及显式 null 序列化检查。扩展 1 条既有主题 Chromium，检查默认控件、固定色与重新绑定、原生属性、三步完整历史、重开及双线/间隙/明暗色的 Canvas/独立 PDF 采样。公开 api/check/build 与定向私有 TS/lint/格式通过，证据归 `themedPageBorderCheckpoint` 和后续 `themedPageBorderEditingCheckpoint`。失败发现空字段被自动省略，现显式写 null；重开时同级面板重复 key 也已修复，现有流程检查无重复 key 错误。沿用 20 秒、零重试；未跑全量、安装矩阵或外部 Office，主题明暗值的创作控件及其余 P10–P12 继续实施。

P11 星期与周序号扩展既有两项日期核心用例，63 个新增独立值覆盖所有 returnType、跨年 ISO 周、1900/1904 边界、参数转换和错误；跨表重算、插行后的标准前缀/缓存、四步完整字节历史、重开及工作/输出预算通过。扩展 1 条既有 America/Los_Angeles Chromium，保留原生公式和 Enter 定位，检查独立 XML、依赖修改、精确撤销、重开继续输入、日期格式及 PDF 的 `6|24|24`。初次格式修改后定位未推进，现等待队列空闲并检查焦点/启用后执行原有 Enter，未降低断言或修改超时。公开 api/check/build、定向私有 TS/lint/格式、源码/登记/链接和 XLSX 生成接口检查通过，证据归 `weekFunctionsCheckpoint`。未跑全量或外部 Office；其他函数与其余 P10–P12 继续实施。

P12 七角星、十六角星、二十四角星和三十二角星扩展既有核心与星形浏览器用例。9 项核心检查独立轮廓、文字内框、标准归一化、调节预览/取消、复制、类型修改、原生连接点顺序与实际目标边界、精确历史及保存重开。4 项传输用例含 196 个断言，检查端点 15/数量 16 及越界拒绝。1 条 Chromium 检查默认控件、原生输入、十四步完整字节撤销重做、末点连接写回和最终十六角星的五处严格 Canvas/PDF 颜色及 PDF 文字。初次 PDF 失败的旧取样点位于更细星尖的描边边缘，按独立光栅结果移至内部后通过。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过；证据归 `nativeStarFamilyCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P11 旧版 CEILING/FLOOR/TRUNC 扩展两项既有数值核心用例，未新增用例。60 个独立预期与 6 个参数数量拒绝检查覆盖符号、零、容差、位数舍入/上限、浮点缩放、类型和错误；共享、名称及跨表引用、陈旧缓存、插行、精确历史、保存重开和预算原子性同时通过。1 条既有 Chromium 检查默认公式栏、原生输入、标准源/缓存、完整字节撤销重做、重开输入与 PDF。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口和两仓 diff 通过，证据归 `legacyRoundingCheckpoint`。20 秒、零重试；沿固定 ONLYOFFICE 的旧版边界，未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P10 页面虚线/点线边框扩展既有用例。4 项核心检查独立分段坐标、末段裁剪、最小线宽、8192 段上限、缓存派生、混合原生线型、主题保持及精确历史；3 项传输用例含 144 个断言。1 条 Chromium 检查默认样式控件、原生输入/XML、四步完整字节边框撤销重做、保存重开、两页 Canvas/PDF 的线段/间隙颜色及文字，并保留原有双线和 PNG 输出保护流程。首次失败来自旧 PNG 保护样本把现已支持的点线当作不支持，改用波浪线并保留拒绝和源不变断言后通过。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口和两仓 diff 通过，证据归 `patternedPageBordersCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P12 七边形、十边形和十二边形扩展既有用例。9 项核心检查 29 个独立轮廓点、文字区域、固定归一化保护、无调整柄、变换/复制、7/10/12 个原生连接点及末点保存重开、类型修改和精确历史。3 项传输用例含 115 个断言。1 条 Chromium 保留原有椭圆输出比较，增加三种默认类型切换及十二边形的实际 PNG/独立 PDF 比较，再检查原生输入、六步完整字节撤销重做、源与其他部件、保存重开。几何测试超过行数上限后，将既有导引保护用例移到 `pptx_polygon_guards_wbtest.mbt`，保留用例身份与全部断言，使用独立登记目标；拆分后的同 9 项核心通过。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口与两仓 diff 通过，证据归 `fixedPolygonPresetsCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P11 ATANH 扩展既有 7 项核心与 3 条 Chromium 流程。22 个独立值及 2 个参数数量拒绝检查覆盖定义域、极小值、类型与错误；共享/名称/跨表重算、插行、精确历史、重开及输出预算通过。六项尚未求值的 FACT/FACTDOUBLE/COMBIN/COMBINA/GCD/LCM 检查完整依赖保护、无关联编辑和缓存保留，包含原生 COMBINA 前缀；动态及自定义函数仍整本保护。浏览器检查默认输入、XML/PDF、格式、未计算链及图表重绑定。两处测试误判已修正：旧缓存按完整数值排除，历史等待修订后仍比较完整字节。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `atanhCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P10 现有节起始方式扩展既有页面用例。3 项受影响核心检查四种起始方式、实际页数/页码、原生纸型保持、混合方向事务、精确历史、重开、目标源保护和输出预算；既有 3 项传输用例含 164 个断言。1 条 Chromium 保留原分节/表格/原生输入/一页 PDF 检查，并验证默认修改四种类型、无操作、四步完整字节历史、重开输入及三页独立 PDF 的页眉编号。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口与两仓 diff 通过，证据归 `sectionStartCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P11 表名透视表源通过 6 项定向核心、186 个传输断言和 1 条默认 Chromium 流程。检查原生名称绑定、总计排除、范围与列映射、共享切片器/时间线刷新、源删除后的缓存恢复、精确历史和保存重开；浏览器验证默认创建、范围修改、显式刷新、原生输入及独立 XML/PDF。公开 api/check/build 与定向 TS/lint/格式通过，证据归 `tablePivotSourceCheckpoint`。沿用 20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P12 三种剪角矩形通过 7 项定向核心、3 项传输用例共 121 个断言及 1 条默认 Chromium 流程。检查独立轮廓/文字内框、原生连接顺序、两个独立导引及手柄、候选取消、类型修改/复制、保护、精确历史及重开；浏览器验证默认控件、八步完整字节撤销重做、原生输入、原生 XML/未改部件和 12 处 Canvas/独立 PDF 颜色。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `snipRectanglesCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P10 表格虚线/点线通过 7 项受影响核心检查、3 项传输用例共 307 个断言及 2 条既有 Chromium 流程。检查线型读写/无操作、继承与冲突、合并续排、跨文档富文本片段、精确历史、重开输入和分段预算；扩展默认边框流程验证原生 XML、两步新增完整字节历史及五处 Canvas/独立 PDF 线段和间隙颜色。公开 api/check/build 与定向 TS/lint/格式通过，证据归 `patternedTableBordersCheckpoint`。新控件补齐可访问名称；复制测试读取重开后的真实段落身份，旧文本框夹具补齐既有必填字段。20 秒、零重试；未跑全量、安装矩阵或外部 Office，复合边框和其余 P10–P12 继续实施。

P10 表格双线通过 9 项定向核心、37 个传输断言和 1 条新增 Chromium 流程。核心检查三倍总占宽、半宽留白、冲突/合并、源与精确历史、重开输入、输出和成对描边预算；分页检查单页 7 条实线/14 条双线、分两页各 8 条描边及精确边界，合并续排检查完整文字和新鲜布局一致。新增的两项布局断言分别定向复跑通过，其余结果复用。浏览器验证默认双线控件、原生 XML/未改部件、三步完整字节历史、重开输入及横竖两线/间隙的六处严格 Canvas/独立 PDF 颜色。公开 api/check/build 与定向 TS/lint/格式通过，证据归 `doubleTableBordersCheckpoint`。共用行边已按来源与同页边界去重，未知复合线保护用例保留。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P11 GCD/LCM 通过 5 项定向核心与 1 条 Chromium 流程。46 个独立数值/错误预期覆盖截断、直接/单格/范围转换、空白、布尔、稀疏整列、整数边界、原生 LCM 零值/累计规则及 255 个参数；零参数和第 256 个参数保留不同拒绝原因，欧几里得迭代花费工作预算。导入共享/名称/跨表、原生缓存、插行、完整字节历史、重开输入及原子输出失败通过；原隔离用例改为仍未求值的 FACT/FACTDOUBLE 范围，保留全部保护断言。默认公式栏流程检查实际输入、XML/未改部件、两步精确历史、重开和独立 PDF。公开 api/check/build 与定向 TS/lint/格式通过，证据归 `gcdLcmCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，通用数组及其余 P10–P12 继续实施。

P12 四种不对称圆角矩形通过 8 项定向核心、3 项传输用例共 129 个断言和 1 条 Chromium 流程。检查独立逐角三次曲线/文字留白、原生默认值/连接顺序、填充及描边命中、独立导引、旋转翻转候选/取消、恢复、类型修改、复制、源保护、完整字节历史和重开输入；旧圆角矩形复用相同路径并通过回归。默认控件流程验证六处原生导引、范围外部件、十一步精确历史、重开输入及 13 处严格 Canvas/独立 PDF 颜色。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `roundedRectanglesCheckpoint`。新命中夹具改用模型规定的空字符串表示无填充，原断言保留并定向复跑。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P10 表格小间隔虚线、点划线和双点划线通过 10 项定向核心、52 个传输断言及 1 条 Chromium 流程。独立线段坐标覆盖横竖节奏、末段裁剪、尾隙和分段预算原子失败；三组整表/单格样式检查原生查询、无操作、富文本复制、继承/移除、完整字节历史和重开输入。合并续排检查三种线型的完整文字、跨页边界和新鲜布局一致。默认面板验证三种原生线型/八处宽度、范围外部件、四步精确历史、重开输入和 15 处严格 Canvas/独立 PDF 线段/间隙颜色。首次执行定位并补齐共用网格校验目录后，仅复跑两项失败用例；八项已有 PASS 复用。最终公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口和两仓 diff 通过，证据归 `mixedTableDashesCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P11 FACT/FACTDOUBLE 通过 7 项定向核心和 3 条 Chromium 流程。47 个独立值/错误预期覆盖截断、170/300 上限、奇偶乘积、微小输入终止、类型/错误和嵌套函数；14 个范围预期覆盖隐式取值与越界。严格参数数量和乘法工作预算保留原子失败；共享/名称/跨表范围、结构平移、完整字节历史、缓存、重开输入和输出预算通过。未计算链和图表夹具改用仍未求值的 COMBIN/COMBINA，完整源/缓存/依赖保护断言保留。默认公式栏及两条既有保护流程检查原生输入、独立 XML/PDF、精确历史、重开及图表改绑，三条首次运行均通过。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `factorialsCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P11 COMBIN/COMBINA 通过 9 项定向核心与 3 条 Chromium 流程。独立数值/错误基线覆盖主参考的原始定义域、阶乘商、小数差单独截断、溢出/相等回退、科学记法整数转换、类型/错误顺序、范围取值、严格参数数量和工作预算。共用乘法代码的两项阶乘回归通过；共享/名称/跨表、原生前缀与导入源写法、结构变化、完整字节历史、重开输入及原子输出失败通过。八项已有 PASS 复用，仅复跑修正导入源前缀预期的一项。未计算链与图表用例改用已审阅的 MROUND/QUOTIENT，保留完整保护断言。默认公式栏及两条既有保护流程检查原生输入、缓存、精确历史、重开、图表改绑和独立 XML/PDF，三条首次运行通过。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `combinationsCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P12 左上双向和折弯向上箭头通过 8 项定向核心、3 项传输用例共 133 个断言及 1 条 Chromium 流程。独立横/竖框基线检查原生顶点、文字区域、六/八连接点、三处手柄和不同调节上限；源常量、填充/描边及框外命中、候选取消、复制/类型修改、精确历史、未知导引保护、重开输入和打印布局通过。七项已有 PASS 复用，仅复跑应用既有缩小适配后的新用例。默认控件流程检查六处原生导引、范围外部件、九步完整字节历史、重开原生输入及 15 处严格 Canvas/独立 PDF 像素，包含框外箭身；修正初始窄框文字夹具后通过。最终公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `elbowArrowsCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P10 表格主题色边框通过 9 项定向核心与 1 条 Chromium 流程。新用例覆盖样式/整表/单格颜色、槽映射、独立 shade/tint 基线、原生缓存与声明、同色 RGB 解除绑定、再次应用无操作、主题修改、精确历史、重开输入、跨文档片段固定颜色及非法/缺失主题保护；原主题颜色和边框用例同时通过。八项已有 PASS 复用，仅复跑修正误指向段落的非法边框夹具的新用例。默认面板按既有加载步骤选择色项，检查四步完整字节历史、原生 XML/未改部件、重开输入及七处实际 Canvas/独立 PDF 颜色和双线间隙。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `tableThemeBordersCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P10 表格边框主题绑定创作通过 11 项定向核心、77 个传输断言及 1 条 Chromium 流程。新增两项核心检查首次主题/关系/内容类型与边框的一次事务、原生缓存、同一绑定无操作、批量绑定、导入变换保留、改绑/解除、精确历史、重开输入及参数/主题锁/预算失败恢复；九项既有主题与边框流程通过。五个受影响原生调用文件已迁移并编译，额外的三个跨格/列宽用例未执行。默认控件首次运行通过，独立 XML 检查六边绑定、单格覆盖、唯一关系和内容类型，六步完整字节历史、重开输入及七处严格 Canvas/独立 PDF 颜色通过。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、预期生成 API 和两仓 diff 通过，证据归 `tableBorderBindingsCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P11 MROUND 通过 9 项定向核心与 3 条 Chromium 流程。新增两项核心检查主参考的 15 位修正、半值/符号、32 位回绕、极大/微小数、类型/错误、范围隐式取值、参数数量、工作预算，以及共享/名称/跨表、真实缓存、结构变化、精确历史、重开输入和输出失败恢复。修正一项源算术预期后仅重跑该用例，复用首轮其余八项 PASS。组合函数和未计算链/图表保护保持通过，隔离库存仅移除已求值的 MROUND。默认公式栏与两条既有保护流程首次通过，检查原生输入、独立 XML、两步完整字节历史、重开和独立 PDF。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `mroundCheckpoint`。20 秒、零重试；未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P10 表格主题底色通过 11 项定向核心、两项接口共 105 个断言及 1 条 Chromium 流程。覆盖首次主题与底色的一项事务、跨格绑定、实际缓存、样式/槽映射/明暗变换、同绑定无操作、同色固定解除、恢复继承、片段、精确历史、重开输入及非法源/主题锁/预算保护；普通底色、跨格、主题文字和主题边框回归通过。四个原生调用文件已迁移并编译，额外四项对齐/多节表格用例未执行。浏览器修正超宽夹具并补齐新下拉框的显式辅助名称后，六步完整字节历史、原生关系/缓存 XML 和三处严格实际 Canvas/独立 PDF 颜色通过，20 秒、零重试。公开 api/check/build、最终辅助名称后的 build/check、定向 TS/lint/格式、源码身份、登记、链接、行数、预期生成 API 和两仓 diff 通过，证据归 `tableThemeFillsCheckpoint`。未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P10/P12 全角及圆圈数字列表合计通过 12 项定向核心、两项接口共 29 个断言及两条 Chromium 流程。DOCX 覆盖原生创建、级别修改、重启、目录、21 后回退、精确历史、重开续号和输出失败；PPTX 覆盖三种原生方案、标点、实际字形标记、源格式/几何保留、无操作、精确历史和重开。既有编号、级别及标记样式检查保持通过。默认控件检查两端原生输入、独立 XML、DOCX 五步/PPTX 四步完整字节历史及实际独立 PDF。修正范围选择、输入队列等待及重启定义副本预期后，仅复跑 DOCX，复用 PPTX PASS，保持 20 秒和零重试。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `wideNumberingCheckpoint`。未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P11 QUOTIENT 通过 11 项定向核心和 3 条 Chromium 流程。新增两项核心检查符号、整数截断及科学计数法边界、类型/错误、严格参数数量、隐式取值、工作预算、共享/名称/跨表、原生缓存、结构修改、精确历史、重开输入和输出失败恢复；MROUND 与组合函数回归通过。剩余未计算链按主参考核对 MULTINOMIAL 的显式依赖，迁移既有标量/范围、共享/名称、动态嵌套及图表夹具，全部保护预期保留。默认公式栏、两步完整字节历史、独立 XML/PDF 及两条既有保护流程首次通过，20 秒、零重试。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `quotientCheckpoint`。未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P10 上下文全选通过 7 项定向核心和 3 条 Chromium 流程。新增三项覆盖空段落/Unicode、正文与文本框边界、整表起点、无源与历史写入、保留重做、完整替换、精确历史、重开及旧修订/候选/关闭/受保护端点失败；既有导航与文本框输入/几何/锁保护保持通过。默认 Ctrl/Cmd+A、宿主 API、跨页原生替换、组合保护、独立 XML/PDF 和 PPTX 嵌套文字回归通过。正文发现不滚动时仍跳末页后修正显示逻辑，仅复跑该流程，复用另外两项 PASS；20 秒、零重试。公开 api/check/build、最终显示修正后的 check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、预期生成 API 及两仓 diff 通过，证据归 `selectAllCheckpoint`。未跑全量、安装矩阵、系统 IME 或外部 Office，其余 P10–P12 继续实施。

P12 圆环通过 9 项定向核心、3 项接口检查共 135 个断言及 1 条 Chromium 流程。独立常量检查内外曲线、反向孔洞、文字内框、连接点、厚度和手柄；填充/描边命中、上下限、无操作、复制/重置/类型修改、精确历史、未知源与输出保护、重开输入及打印布局通过。八项 PASS 复用，仅复跑按现有解析规则区分非法数字拒绝与未知表达式只读的用例。默认控件检查孔洞穿透、真实拖动与取消、原生 XML、六步完整字节历史、重开输入和七处严格 Canvas/独立 PDF 像素，首次运行通过，20 秒、零重试。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、预期接口差异和两仓 diff 通过，证据归 `donutCheckpoint`。未跑全量、安装矩阵或外部 Office，其余 P10–P12 继续实施。

P10 表格行修订通过 7 项定向核心、3 项接口检查共 45 个断言及 1 条 Chromium 流程。新增三项核心检查跨格插删行、原生编号、文字混合审阅、行标记与合并区域定位、合并续接、未受影响选区、末格 Tab、本作者新增行直接删除、末行清表/光标/分页、精确历史、重开及元数据/输出失败；四项既有行和合并行回归通过。默认界面检查原生输入、独立 XML、三步完整字节历史、保存重开、定位、批量接受/拒绝及其撤销重做，独立 PDF 按物理行提取并核对文字。修正超宽夹具及 PDF 默认按列提取的检查命令后通过，保持 20 秒和零重试。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口与两仓 diff 通过，证据归 `rowTrackingCheckpoint`。未跑全量、安装矩阵或外部 Office；其余 P10–P12 继续实施。

P10 行格式修订通过 8 项定向核心、3 项接口检查共 51 个断言及 1 条 Chromium 流程。新增三项检查行高/跨页/表头的首次快照、连续作者更新、无操作、仅变化行记录、合并格式复制、本作者新增行直接更新、同一行删除与格式拒绝、混合审阅、未受影响选区、精确历史、重开及未知源/网格/输出保护；五项既有行修订和跨页属性回归通过。首轮七项 PASS 复用，仅复跑修正原生标记顺序预期的一项。默认控件、真实点击与输入、类型筛选/定位、五步完整字节历史、批量接受/拒绝、重开和原生 XML 通过；Canvas 与独立 PDF 边界框同时核对 60 pt 行间距。测试改用实际画布选中待审阅行，并等待异步复选框状态，保持 20 秒和零重试。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口和两仓 diff 通过，证据归 `rowFormatTrackingCheckpoint`。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P11 MULTINOMIAL 通过 9 项定向核心与 3 条 Chromium 流程。新增两项核心检查独立阶乘截断、原始总和、类型/错误顺序、稀疏范围、严格参数数量、工作预算、共享/名称/跨表、缓存、结构变化、精确历史、重开和输出失败。七项既有组合函数、未计算链及图表 PASS 复用；修正参数上限和非原生前缀预期，并补齐负数溢出文字转换后，两项新增检查通过。默认公式输入、独立 XML/PDF、两步完整字节历史、重开及两条 SERIESSUM 隔离流程首次通过，20 秒、零重试。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口和两仓 diff 通过，证据归 `multinomialCheckpoint`。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P10 表格格式修订通过 11 项定向核心、3 项接口检查共 57 个断言和 1 条 Chromium 流程。新增三项核心覆盖首次快照、稳定编号、连续修改、无操作、全表定位、表/行/文字混合审阅、八步精确历史、重开、导入元数据、未知源和输出/恢复布局失败；八项既有行格式及行修订回归同时通过。默认对齐、边距和边框控件、原生输入、独立 XML、五步完整字节历史、类型筛选/定位、接受/拒绝与重开输入通过。Canvas 检查 40 pt 对齐位移和 42.6 pt 最终文字位移；独立 PDF 检查 120 pt 列间距。修正测试使用的实际边距标签后通过，保持 20 秒和零重试。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `tableFormatTrackingCheckpoint`。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P10 单元格格式修订通过 14 项定向核心、3 项接口检查共 63 个断言和 1 条 Chromium 流程。新增三项核心覆盖首次格/表快照、稳定编号、混合审阅、合并源格、新行当前格式复制、八步精确历史、重开、导入元数据、未知源、网格保护及输出/恢复失败。十一项既有 PASS 复用，修正复制路径后复跑新增用例；扩展旧边距检查仅复跑所属用例。默认四类控件、原生输入、独立 XML/PDF、六步完整字节历史、筛选/定位、接受/拒绝及重开输入通过。按既有合同和主参考修正精确行高另加边距的预期后，Canvas 检查 2.6 pt 水平及 2 pt 垂直位移，独立 PDF 检查 117.4 pt 列间距；保持 20 秒和零重试。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `cellFormatTrackingCheckpoint`。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P11 SERIESSUM 通过 9 项定向核心与 3 条 Chromium 流程。新增两项核心覆盖标量/范围系数、缺格指数位置、类型/错误顺序、无效幂、严格参数数量、工作预算、共享/名称/跨表、缓存、结构变化、精确历史、重开及输出失败。MULTINOMIAL 和迁移为 SUMX2MY2 的既有隔离/图表用例保留全部断言。默认公式栏、两步完整字节历史、独立 XML/PDF、重开输入及两条保护流程首次通过，保持 20 秒和零重试。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `seriesSumCheckpoint`。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P12 基础心形通过 9 项定向核心、3 项传输检查共 136 个断言及 1 条 Chromium 流程。独立常量检查双曲线、凹口/描边/框外曲线命中、文字区域和连接点；复制、类型修改、四步完整字节历史、重开输入、未知源与输出失败保护通过。默认创建、凹口穿透、独立 XML、七处 Canvas/独立 PDF 像素及 PDF 文字通过，保持 20 秒、零重试。公开 api/check/build 与定向静态检查通过，证据归 `heartCheckpoint`。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P11 成对平方和函数通过 12 项定向核心与 3 条 Chromium 流程。新增两项检查三种运算、矩阵行列匹配、数字类型、缺格/错误、限定引用、工作预算、共享/名称/跨表、缓存、结构、精确历史、重开和输出失败。名称解析保留原引用形式，既有名称、规则、小计和隔离/图表用例保留全部断言；十项 PASS 复用，仅复跑修正为独立稀疏工作簿预算探针的两项新增用例。默认公式栏、独立 XML/PDF、两步完整字节历史、重开输入与 MDETERM 保护流程首次通过，保持 20 秒、零重试。公开 api/check/build 和定向静态检查通过，证据归 `pairedSquaresCheckpoint`。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P10 多栏脚注通过 5 项定向核心与 3 条 Chromium 流程。两项新增核心检查等宽/不等宽栏位、物理栏底、正文避让、动态页脚、表格锚点、跨栏/页/节续排、文字完整、精确历史、重开及输出失败；三项既有单栏/尾注/跨节 PASS 复用。默认分栏/注释控件、原生正文输入、四步完整字节历史、独立 XML、实际 Canvas 颜色、独立 PDF 栏底坐标及重开编辑通过。新增流程发现并修正表单末栏显示/提交宽度不一致；旧不等宽流程在修正后保持通过。保持 20 秒、零重试，最后注释编辑经正常保存屏障后核对完整跨行文字。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `notesColumnsCheckpoint`。未跑全量、安装矩阵或外部 Office；其他 P10–P12 能力继续实施。

P10 多栏尾注通过 7 项定向核心与 3 条 Chromium 流程。两项新增核心以独立常量检查平衡后的精确行坐标、仅含注释栏的分隔线、完整多段文字、等宽/不等宽、文末/节末、脚注避让、跨节编号和总页数、精确历史及重开；五项既有脚注/尾注/跨节用例保持通过。默认分栏与注释控件、原生正文输入、四步完整字节历史、原生 XML、两栏实际 Canvas 颜色及独立 PDF 坐标首次通过，旧多栏脚注和单栏注释流程保留全部断言。保持 20 秒、零重试。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `endnotesColumnsCheckpoint`。未跑全量、安装矩阵或外部 Office；其他 P10–P12 能力继续实施。

P11 MDETERM 通过 14 项定向核心与 3 条 Chromium 流程。两项新增核心检查独立方阵结果、最大主元行交换、奇异矩阵、类型/错误、参数数量、稀疏缺格及分配/消元预算、共享/名称/跨表、缓存、结构、精确历史、重开和输出失败；既有成对平方和、级数、名称/规则/小计、隔离链和图表保留断言。默认公式栏、两步完整字节历史、独立 XML/PDF、保存重开输入及 MINVERSE 保护流程首次通过，保持 20 秒、零重试。公开 api/check/build、定向 TS/lint/格式、源码身份、登记、链接、行数、生成接口及两仓 diff 通过，证据归 `determinantCheckpoint`。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P12 闪电形通过 11 项定向核心、3 项传输检查共 138 个断言及 1 条 Chromium 流程。独立常量检查十一顶点、凹口/描边命中、文字区域和七个连接点；复制、类型修改、四步完整字节历史、重开输入、未知源与输出失败保护通过。默认创建、真实凹口点击、默认字号调整后的原生输入、独立 XML、九处 Canvas/独立 PDF 像素及 PDF 文字通过。点击探针按既有描边容差使用 2 倍缩放，并在编辑器内滚动使目标可见；像素检查恢复半倍缩放。保持 20 秒、零重试。公开 api/check/build 与定向静态检查通过，证据归 `lightningCheckpoint`。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P10 脚注紧随正文位置通过 9 项定向核心、2 项接口检查共 284 个断言及 3 条 Chromium 流程。两项新增核心检查独立位置与分隔线、原生别名、表格底部、不等宽栏、文档继承/节覆盖、跨节续排、完整文字、精确历史、重开和输出失败。查询比较前预读懒解码 OPC 内容，保留完整状态断言；七项既有注释回归结果复用。传输层检查根与节位置的必需字段和枚举；12 个原生夹具文件仅补默认页底字段。默认注释编辑、原生正文输入、两步完整字节历史、原生 XML、实际 Canvas 文字区域及独立 PDF 坐标首次通过，旧多栏及单栏流程保留全部断言。保持 20 秒、零重试。公开 api/check/build、定向静态检查和两仓 diff 通过，生成接口仅增加两个位置字段。证据归 `beneathTextCheckpoint`。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P10 脚注位置修改通过 8 项定向核心、3 项接口检查共 182 个断言及 3 条 Chromium 流程。两项新增核心检查独立位置、编号/源/选择保留、缺失属性创建、逐节隔离、无变化/省略、精确历史、重开输入、过期/不透明/预算失败；既有页面与注释回归保留断言。扩展已有浏览器流程，通过默认页面表单切换页底与紧随正文，检查另一节保持、四步完整字节历史、独立 XML、保存重开、Canvas 和独立 PDF。跨会话的内部段落身份按首次出现顺序对应，保留段落分组和所有其他语义字段；两个既有流程 PASS 复用，仅复跑扩展用例。保持 20 秒、零重试。公开 api/check/build 和定向静态检查通过，生成接口只扩展既有设置参数。证据归 `notePositionEditingCheckpoint`。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P10 全局尾注位置修改通过 7 项定向核心、1 项接口检查共 49 个断言及 3 条 Chromium 流程。两项新增核心检查文末/节末跨页坐标、节内元数据保留、编号/原源/选区、缺失设置资源及完整字节历史、重开输入、保护/未知/过期/字体/输出失败；五项既有多栏/多节/注释布局回归保留断言。新默认面板流程检查跨节迁移、过期目录恢复、四步完整字节历史、独立 XML、完整重开语义、实际 Canvas 与独立 PDF 页归属；两个既有流程 PASS 复用。新位置控件提供明确无障碍标签，保持 20 秒、零重试。公开 api/check/build 与定向静态检查通过，生成接口仅新增位置事务。证据归 `endnotePositionEditingCheckpoint`。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P10–P12 共用堆积折线图通过 9 项定向核心、3 项接口检查共 234 个断言及 2 条 Chromium 流程。两项新增核心检查独立累计坐标、空白零贡献、百分比与极大值、原始工作簿、独立复制、精确历史、重开输入及源/字体/预算失败；既有普通折线、面积和 DOCX 正文/格、XLSX 实时来源检查保留原断言并扩展类型。默认图表控件、四步完整字节历史、原生 XML、工作簿原值/原字节、重开及七处实际 Canvas/PNG/独立 PDF 颜色首次通过，既有堆积面积图流程保持通过。保持 20 秒、零重试。公开 api/check/build、定向静态检查通过；生成接口新增共用折线类型判断。证据归 `stackedLineCheckpoint`。三格式原生构建缓存达到上限后已清理，后续只复跑新增用例并复用既有 PASS；资源详情归私有记录。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P10 注释编号修改通过 7 项定向核心、1 项接口检查共 140 个断言及 2 条 Chromium 流程。两项新增核心检查独立跨节标签、连续/每节重启、编号原值与位置/选区/源保留、缺失属性创建、完整字节历史、重开编辑及保护/字体/预算失败；五项既有位置/节布局回归保留断言。现有默认尾注流程扩展所选节的格式、起始值及重启控制，覆盖过期目录恢复、两步新增完整字节历史、独立 XML、重开及 PDF 标签；既有脚注位置流程保持通过。保持 20 秒、零重试。公开 api/check/build 与定向静态检查通过。证据归 `noteNumberingEditingCheckpoint`。未跑全量、安装矩阵或外部 Office；P10–P12 继续实施。

P10 每页脚注编号通过 5 项定向核心、3 项接口/布局传输检查共 471 个断言及 1 条 Chromium 流程。两项新增核心检查物理页重启、同页跨栏、正文/故事/NOTEREF 标签、跨节续排、冷暖布局、完整字节历史、重开、字体失败及最大起始值之后的递增；三项既有编号和分节结果复用。扩展现有脚注位置流程，保留原生输入和 Canvas/PDF 断言，新增默认编号表单、禁用起点、两步完整字节历史、独立 XML、部件保留、重开语义及 PDF 标签。按既有可见语义文本合同修正新断言后通过，保持 20 秒、零重试。公开 api/check/build 与定向静态检查通过。证据归 `pageNoteNumberingCheckpoint`；未跑全量、安装矩阵或外部 Office，P10–P12 继续实施。

P11 合并计算通过 2 项定向核心、1 项接口检查共 49 个断言及 2 条不同 Chromium 流程。核心检查五种聚合、不同大小来源、字面标签/首次顺序、预览、覆盖确认、实时来源、改名/插行、完整字节历史、重开及范围/保护/预算失败。新增默认面板流程检查两种归并、原生来源输入、六步完整字节历史、独立 XML/缓存、目标外部件和既有重算元数据、重开输入、实际 Canvas 墨迹及独立 PDF；既有排序、分列和去重首次通过并复用。补齐新查询统一路由，并按既有保存政策核对精确 workbook 元数据后，新增流程通过。保持 20 秒、零重试。公开 api/check/build 与定向静态检查通过。证据归 `consolidationCheckpoint`；未跑全量、安装矩阵或外部 Office，P10–P12 继续实施。

P11 分类汇总通过 4 项定向核心（2 项新增、2 项既有合并计算/结构引用回归）、1 项接口检查共 25 个断言及 1 条 Chromium 流程。覆盖相邻/空标签、尾部空行、三种聚合、总计不重复内部汇总、公式与便笺移动、源格式、汇总加粗、大纲、一次完整字节历史及失败原子性。默认控件检查预览不修改源、实际输入更新、折叠、三步撤销重做、保存重开继续输入、独立 XML 和 PDF。未知工作表扩展被正确保护；正向夹具改为普通工作表后通过。公开 api/check/build 与定向静态检查通过，保持 20 秒、零重试。证据归 `subtotalCreationCheckpoint`，未跑全量或外部 Office，P10–P12 继续实施。

P10–P12 按原操作表的六/五/五批最低范围完成收尾，结果已移至 `docs/implemented/`。本次复用未改变路径的定向证据，当前生产改动通过公开 api/check/build；没有执行全量验收。最新分类汇总的核心、接口、Chromium 和文档检查归 `subtotalCreationCheckpoint`，阶段范围对照归 `officeCoreClosureCheckpoint`。原始 SUBTOTAL 公式三项用例保持不变。复杂兼容及外围差距继续由 G3 和路线图维护。

字体替代通过 1 项定向核心、1 项接口检查共 8 个断言及 1 条 Chromium 实际示例流程。浏览器不手选字体、不填写映射，依次打开缺少字体的 DOCX/XLSX/PPTX，核对非阻塞警告、实际 Canvas 墨迹、完整字节保存和关闭；DOCX PDF 通过独立结构检查与中英文提取。原始严格模式和精确映射优先保持。公开 api/check/build 与定向静态检查通过；没有全量或外部 Office 验收。证据归 `fontFallbackCheckpoint`，用户原始文件未提供，不宣称全部本地文件已验证。

字体替代的静态预览补充通过实际 `127.0.0.1:4173` 的 Chromium 检查：仓库 `explicit-page.docx` 在空映射及未手选字体时打开，警告、无错误及可保存状态正常；入口 JS、Wasm/Worker 的请求标识与重新加载更新已检查。先前字体结果来自新会话，未覆盖用户旧页面缓存，本次修正示例资源加载；原文件字节未提供，不宣称与同名夹具相同。示例构建、lint/格式及定向测试静态检查通过，未重跑原生或全量；证据归 `fontFallbackCacheCheckpoint`。

## P13 PDF 核心功能收尾

P13 的公开 API/check/build 通过。六批最低范围的证据归私有 `cases/p7-p8-pdf.json` 的 `p13Checkpoint`。定向 Chromium 流程覆盖创建/阅读、页面与源对象、批注/多笔画签名、字段/多widget、真实脱敏、三种原生Office转换及结构化/图片输出；原生核心检查覆盖字形墨迹、实际裁剪和边界精度、独立资源、字体许可及载荷清理。共享单元、同步/Worker引擎和直接受影响的Office→PDF writer路径另有回归。PDF沿qpdf/Poppler核对结构、文字和像素，Office结果经目标SDK再编辑并核对XML与保存重开。

阶段结果归 [P13](../implemented/p13-pdf-core.md)，当前API与保护边界归[格式合同](formats.md#pdf-输入与文档操作)。本次复用未改变路径的已通过结果，没有执行全量套件、其他浏览器、外部参考应用GUI或新的系统输入法验收。私有记录区分各次适用构建和复用范围，不把定向通过扩张为任意PDF兼容。
