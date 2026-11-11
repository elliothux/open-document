# PDF 输入、编辑与输出

[格式合同目录](../formats.md)

## PDF 输入与文档操作

`PdfSession.inputLimits()`、`PdfClient.inputLimits()` 与 `PdfEditor.inputLimits` 提供核心字节限额，字段与累计预算的区别归[共享合同](shared.md#输入字节限额)。页面导入、RGBA 注册、图片与印章输入沿相同限额检查，打开文件保留显式 `PdfBudget`。

独立 TrueType 接收 `0x00010000` 和 Apple `true` 标识，复用同一目录与轮廓校验。普通 TrueType 源字形先按编码对应的 cmap 查找，再回退到字形名；Unicode 提取与显示字形分别保留。此规则修正重编码子集的 `S` 被同名字形错误替换的问题，不改变 CID 显式 GID 或符号字体路径。xref 分流允许指针位置的合法前置空白，仍拒绝非空白错误前缀，不做任意位置重建。

标准 14 字体同样读取 ToUnicode。局部 CMap 后定义覆盖早定义，局部映射优先于 UseCMap 继承；无效 UTF-16 或缺失条目保持未知。显式替代简单字体时，优先按原编码选择显示字形，编码缺项才采用可信 Unicode；CID 替代仍按 Unicode 选择。无嵌入 Type1 仍要求显式替代。`nonembedded_type1_tounicode.pdf` 在 SDK 和 Poppler 使用同一 Arimo 的条件下通过定向视觉、文字、页面旋转及源保存检查。

TrueType CID 字体支持 `Identity-V`。两字节字形使用 `W2` 或 `DW2` 定位和竖向推进，`TJ` 沿竖向调整。缺少可信 Unicode 的字形可显示，提取标为不完整。竖排源正文改写和脱敏仍受保护。[PDF 1.7 §9.7.4.3](https://developer.adobe.com/document-services/docs/assets/35e4369068f86065372c18787171a17e/PDF_ISO_32000-1.pdf)

CFF1 字形读取复用 pdflite 内部解析器，支持 `Type1C`、`CIDFontType0C` 裸流和 `OpenType` 容器中的 CFF 表。简单字体按显式字形名或字体程序的隐式编码选择，CID 按字符集映射。字符集查找限制在声明的字形数量内，避免误读后续数据。执行必须处于 SDK 预算内，指令、路径缓存及绘制分配扣除预算；截断、越界与预算耗尽拒绝。两份 CFF 表单和 `cid_cff.pdf` 原件定向视觉通过；后者也通过文字完整性、页面旋转及源保存检查。CFF2、字体集合及竖排未补齐。CFF 源文字重构、原生转换和脱敏仍受保护。

嵌入 Type1 的 `FontFile` 读取二进制 eexec、lenIV、Subrs、CharStrings、FontMatrix 及 StandardEncoding/字面编码表，复用同一 charstring 引擎。仅读取有界字体数据，不执行通用 PostScript。字体程序最多 32 MiB，单个字符串 1 MiB，字形和子程序各最多 65535 个，字符串和过程嵌套最多 64 层。已知 flex/hint replacement OtherSubr 沿既有求值器处理，未知调用拒绝。十六进制 eexec、PFB 容器、多主字体、描边字体和竖排仍保护。Type1/CFF 轮廓归一到 em 坐标，复用现有 `glyphs` 命令、轮廓缓存和 PDF 设备像素定位；合计轮廓仍限 8 MiB。阅读不开放源文字重构、转换或脱敏。`circlecopyrt` 按固定字形表提取为 ©；显式空 ToUnicode 保持 U+FFFC 与 `textComplete=false`，不猜测重编码字符。

Type3 字形程序复用内容解释器，支持 `d0/d1` 和水平 FontMatrix（`b=e=0`）。缺省资源沿用调用环境；字形内的图形状态与文字提取单独隔离。`d1` 禁止设置颜色，递归和内容执行沿用现有预算。未支持的图像遮罩等仍返回不完整诊断。没有可信 Unicode 时保留 U+FFFC 和 `textComplete=false`，不从字符编号猜正文。阅读支持不开放源字体重构、格式转换或脱敏。

读取支持 DeviceGray/DeviceRGB 的 1 位打包样本，按行忽略填充位并应用 Decode。CCITT/CCF 只用于 1 位 DeviceGray 图像，支持 Group 3 一维/混合编码和 Group 4；Rows 缺省或为零时以图像高度约束解码。尺寸冲突、截断和预算耗尽拒绝。普通软遮罩仍限既有 8 位灰度范围；JPX 灰度按下述解码精度归一，损坏传真行恢复与无压缩传真扩展尚未实现；阅读支持不自动开放源对象重写。

DeviceRGB/DeviceGray 的绘制分量先截为 16.16 定点值，再舍入到 RGB 字节，依据 [ONLYOFFICE 颜色转换](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/xpdf/GfxState.h#L75-L99)。核心读取 ICC v2/v4 的 RGB 色度矩阵和 Gray 曲线，支持 XYZ 矩阵、单调采样曲线和 gamma，并转换到 sRGB。Gray 的相对色度使用 PCS D50 轴，保留并验证源白点。命名 ColorSpace、DefaultRGB 及标准分量范围沿同一路径解析。配置最多 1 MiB、128 个标签、每曲线 4096 个样本，每页最多 256 份。截断、越界、循环别名、查找表配置和未支持的参数曲线拒绝。色彩适配矩阵依据 [W3C CSS Color 4](https://www.w3.org/TR/css-color-4/#color-conversion-code)。受支持 ICC 图像在 Decode、SMask 和 Matte 后由核心转换，JPEG 在平台解码后走同一路径；每张图像缓存最多 256 种颜色，逐像素和新颜色转换均扣预算，alpha 保持。

JBIG2Decode 接受单页、已知尺寸的嵌入段流或顺序文件头。即时通用区域支持 MMR，以及带四个合法自适应像素的算术模板 0；按页默认值或允许覆盖的区域操作合成，处理 OR/AND/XOR/XNOR/REPLACE、非字节对齐和页面外裁剪。结果反转成 PDF 的默认灰度位，沿用 Decode、颜色和源保存路径。实现归 [`input-jbig2.mbt`](../../../modules/formats/src/pdf/input-jbig2.mbt)及[算术解码](../../../modules/formats/src/pdf/input-jbig2-arithmetic.mbt)，算法参照固定 [ONLYOFFICE JBIG2Stream](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/xpdf/JBIG2Stream.cc)和[算术状态](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/xpdf/JArithmeticDecoder.cc)，未复制上游执行代码。

每流最多 256 段，区域至多 4096×4096 且不超过 4,194,304 像素；输出、算术上下文和工作量扣除现有预算。段长度、页/区域尺寸、引用、自适应像素顺序、终止标记及编码标志先校验。符号字典、精化、其他算术模板与行预测、全局/被引用段、条带页和随机段序保持不完整诊断；截断、非法顺序和越界安全拒绝。能力不增加公共 API，也不开放源图片重构。参考范围及插值分歧见[测试说明](../testing.md#当前兼容证据入口)。

JPXDecode 由 MoonBit 有界解码 JP2 容器和裸 J2K，读取 1–16 位有符号/无符号分量并归一到 8 位。支持默认 precinct、LRCP/RLCP、多质量层、瓦片、顺序瓦片分段、5/3 与 9/7 逆小波、RGB 分量变换及 RESET/VSC/SEGSYM；SOP/EPH 按声明读取。MQ 算术状态与 JBIG2 共用。PDF 的 BitsPerComponent 与 Decode 按 JPX 规则忽略；显式色彩空间优先，省略时按容器或分量数推导 Gray/RGB/CMYK，并处理 sYCC。SMaskInData 的直通/预乘 alpha、Matte 与受支持外部软遮罩复用既有像素路径。JPX 灰度软遮罩允许省略 PDF 精度和色彩空间。

图像边长最多 4096、像素最多 4,194,304、分量最多 5、瓦片最多 4096、质量层最多 256、小波层最多 16；块面积最多 4096，每带最多 65536 块。PDF 尺寸在瓦片分配前核对。容器、量化表、标记、包与样本范围先验证；编码流复制、树、系数、工作区及逐点运算扣除原预算。非默认 precinct、其他包顺序、编码旁路/逐段终止、ROI、HT、调色板、通道重排和内嵌 ICC 保持保护。普通 RGB/Gray/CMYK 与现有受支持 ICC 由 PDF 色彩空间进入，不因此扩大 ICC 配置支持。

原始压缩流保持，完整显示的普通源图像沿既有裁剪合同编辑；裁剪保留隐藏像素，不是脱敏。C024 的裁剪、精确历史和保存重开已验证；其他源图像变体不自动授予资格。实现归 [`input-jpx.mbt`](../../../modules/formats/src/pdf/input-jpx.mbt)、[包读取](../../../modules/formats/src/pdf/input-jpx-packets.mbt)、[块解码](../../../modules/formats/src/pdf/input-jpx-codeblock.mbt)、[逆小波](../../../modules/formats/src/pdf/input-jpx-wavelet.mbt)及[图像接入](../../../modules/formats/src/pdf/input-jpx-images.mbt)。算法依据固定 ONLYOFFICE 随附 OpenJPEG 的 [Tier1 上下文表](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/raster/Jp2/openjpeg/openjpeg-2.4.0/src/lib/openjp2/t1_generate_luts.c)和[逆小波](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/raster/Jp2/openjpeg/openjpeg-2.4.0/src/lib/openjp2/dwt.c)独立实现，未复制上游执行代码。固定独立渲染及 Poppler 分量差异归[测试说明](../testing.md#当前兼容证据入口)。

DeviceCMYK 支持 `k/K`、命名资源、DefaultCMYK 和初始黑色。1 位打包与 8 位样本沿既有流读取，baseline 四分量 JPEG 在 MoonBit 解码，保留 Adobe CMYK/YCCK 样本语义；Decode、软遮罩和 Matte 在 CMYK 分量上处理，再转成 RGB。转换使用[依赖记录](../dependencies.md#jpeg-解码)中的固定 PDFium 样本表和插值。JPEG 先验证尺寸、精度、组件与 MCU 数量。符合解码和预算条件的 RGB/Gray JPEG 由核心按需解码，其余使用现有宿主路径。渐进式 CMYK、CMYK ICC、DCT DecodeParms 和真实叠印仍未支持。

`SA` 接受合法布尔值并保留源字典。绘制按固定 ONLYOFFICE 后端使用统一设备像素提示，不因该开关拒绝实际描边；非布尔值仍拒绝。依据 [RendererOutputDev::updateStrokeAdjust](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/SrcReader/RendererOutputDev.cpp#L621-L624)和 [SplashOutputDev](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/xpdf/SplashOutputDev.cc#L938-L951)。

页面与 Form 的 `/Group /S /Transparency` 支持 DeviceRGB 和已支持的 RGB matrix/TRC ICC，限非挖空合成。源颜色仍按 ICC 转换；组在 RGB 输出目标中混合，依据固定 [ONLYOFFICE RGB 输出与混合](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/SrcReader/RendererOutputDev.cpp#L624-L710)及 [Splash 组目标](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/xpdf/SplashOutputDev.cc#L3932-L3955)。DefaultRGB 仍要求等效 sRGB。此范围不授予任意色域中的原生组混合资格。页面组忽略 I 值，批注随后绘制。

绘制样式使用 `DrawBlend` 的 Normal、Multiply 和 Difference，JSON 使用 `normal/multiply/difference`。原 `multiply` 布尔字段已移除。Difference 按分量绝对差进入既有 Canvas 合成，依据 [W3C 混合公式](https://www.w3.org/TR/compositing-1/#blendingdifference)。隔离 Form 重置内部 alpha、混合及软遮罩，结束后应用调用方状态。外层为 alpha=1、Normal、无软遮罩时，非隔离组继续直接使用背景；其他外层合成要求内部全部为 Normal，再整体应用组 alpha、混合和软遮罩。内部其他混合、挖空及未支持空间继续保护。

有界几何检查只有在能证明全部描边与填充落在 Form BBox 内时，才省去重复的边界裁剪，避免贴边描边再乘一次抗锯齿覆盖。检查控制点包围盒、仿射变换、描边半径、平滑闭合曲线、斜接和方帽余量、内部裁剪及作用域。突出边界、尖角、细线、无界渐变或不能证明的命令保留原裁剪；几何遍历扣除工作预算。源对象与重构保护不变。实现归 [`input-groups.mbt`](../../../modules/formats/src/pdf/input-groups.mbt)及 [`input-form-clip.mbt`](../../../modules/formats/src/pdf/input-form-clip.mbt)。

ExtGState `/SMask` 支持 `None` 或 `S=Alpha` 的 Form 透明组。遮罩保存设置时的矩阵和资源，应用自身 Matrix/BBox；RGB 不参与 alpha 计算，空遮罩使内容透明。转移函数仅接受缺省、Identity 或 Default；Luminosity 和其他函数仍保护。遮罩组独立解释，文字不进入页面语义，资源、递归和临时层受共同预算约束。路径、文字、图片、着色及隔离 Form 复用同一遮罩命令；Type3 在字形程序内部应用一次。同一路径的填充与描边分别遮罩，遵循 [ONLYOFFICE 绘制顺序](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/xpdf/Gfx.cc#L1856-L1930)。遮罩文字/图片保持源编辑保护，普通保存与页面旋转保留源对象和压缩流。实现归 [`input-soft-mask.mbt`](../../../modules/formats/src/pdf/input-soft-mask.mbt)，状态依据 [ONLYOFFICE 软遮罩](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/xpdf/Gfx.cc#L1135-L1310)。

可选内容读取默认 View 配置的 BaseState、ON/OFF、Intent 和 ViewState；ViewState 优先级参照 [PDFium](https://github.com/chromium/pdfium/blob/a84323421e94f484faca52dd9d027934eba42ab8/core/fpdfapi/page/cpdf_occontext.cpp#L139-L160)。配置在首次引用时读取，未使用的配置不阻断页面。OCMD 支持四种成员策略及 Not/And/Or 表达式；组最多 256 个，成员和单个表达式最多 256 项，嵌套最多 32 层。隐藏内容不绘制或提取，仍执行颜色、裁剪和文字推进；整个隐藏 XObject 或批注可跳过。未知身份、非法条件和超限拒绝。仅读取默认屏幕状态，其他配置切换和动态缩放等 usage 尚未实现。源保存保留全部图层；页面关系重写、重构、转换和脱敏沿原保护规则。

缺失 normal appearance 的基础 Line 批注复用既有路径生成临时外观，读取 BS 或旧式 Border 宽度，并容纳端点外的描边。零宽边框不绘制；锁定批注可显示，编辑仍受原标记保护。非零引线、标题、复杂线端或边框效果继续诊断。临时外观不写入源对象，普通保存继续保留缺失 AP。

轴向 `sh` 支持 RGB/Gray/已支持 ICC 的 Type 2 指数函数、Type 3 拼接和一维 Type 0 采样，保留反向 Encode 和硬颜色边界。指数函数先验证有限、有效域和颜色分量；在每段四分之一、二分之一、四分之三处检查线性误差，超过 1/4096 时继续细分，最多 24 层及 4096 点。非法幂、超限或有效 Range 截断保持保护。工作和临时样本扣除预算。

Type 0 仍限 order=1、2–4096 个样本、1/2/4/8/12/16 位和一或三分量，解码长度必须匹配。函数流只解码一次，准备对象不修改源流。函数域、BBox、裁剪、Extend、alpha 和受支持混合进入既有图元；变换不改变后续状态。复用固定 pdflite 读取器；函数深度最多 8、函数 32 个、参数数组 64 项。ICC 按分量间隔至多 1/256 采样颜色，最多 8192 点，再压缩为最多 32 个停点，保留采样点的通道误差不超过 1。计算器函数、分量函数数组、其他渐变色彩空间及径向/网格着色继续诊断。普通保存保留源函数和操作符，原生重构保持保护。实现归 [`input-shading.mbt`](../../../modules/formats/src/pdf/input-shading.mbt)与 [`input-shading-colors.mbt`](../../../modules/formats/src/pdf/input-shading-colors.mbt)，裁剪和 Extend 依据固定 [ONLYOFFICE Gfx](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/xpdf/Gfx.cc#L2369-L2445)。

Pattern 色彩空间支持着色与带 Gray/RGB/CMYK/已支持 ICC 基色的无着色 Type 1 平铺填充。选择图案时验证 PaintType、TilingType、资源、BBox、有限非零步长和可逆 Matrix；切换普通颜色或色彩空间清除当前填充图案，q/Q 保留状态。图案跟随页面/Form 的基准矩阵，不随后续 cm 重新锚定。每格按 BBox 裁剪，保留间隔、重叠、外层裁剪、alpha、Multiply 和软遮罩；内部文字不进入页面语义。单次路径最多 4096 格，按路径控制点包围框与页面框保守估算，并沿既有递归、工作及绘制预算。实现归 [`input-pattern.mbt`](../../../modules/formats/src/pdf/input-pattern.mbt)与[`input-path.mbt`](../../../modules/formats/src/pdf/input-path.mbt)，语义依据 [ONLYOFFICE 平铺与基准矩阵](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/xpdf/Gfx.cc#L2046-L2269)。

TilingType 1/3 在 BBox 等于步长且内外样式均为 alpha=1 的 Normal 时生成单格缓存命令。格内图片保留自身 alpha；内部图层、遮罩、嵌套图块及非中性样式继续逐格执行。TilingType 2、间隔和重叠图案使用连续矢量坐标。Renderer 按重复区域取整后的设备尺寸选择单格采样率。PDF 的最终重复格数不超过 4 且重放命令总数不超过 1048576 时，直接逐格绘制；其余继续以最近邻重复纹理绘制。取整后重复格可能增加，不能按源格数提前切换。单格表面、深度和 4096 格预算仍先校验。直接绘制格内的正向轴对齐图片，设备下界取 floor，上界取 floor+1；其他变换沿已有绘制路径。实现归 [`drawing-tile.ts`](../../../packages/web-core/src/drawing-tile.ts)。采样参考 [Poppler 26.05.0](https://poppler.freedesktop.org/poppler-26.05.0.tar.xz) 的 `SplashOutputDev.cc:4193–4415` 与 `Splash.cc:90–120`，未复制上游执行代码。图案描边、普通文字的字形裁剪、着色图案和原生重构保持保护。普通保存保留全部图案流。

多个源字体映射到同一个显式替代字体时，页面只装载一份替代字体；各源字体的 Unicode 和字形映射仍分别保留。默认 ExtGState 的 `BG2/UCR2/TR2/HT /Default`、`SA false`、`OPM 0/1` 及合法 `SM` 平滑度提示不再中断内容解释。非默认转换、半色调、实际调整描边和真实叠印仍受保护。解析错误保留底层原因，资源超限仍返回原预算错误。C0 的 ArabicCIDTrueType 原件通过核心完整性及 Chromium/Poppler 定向笔画覆盖对照；环境和范围见[测试说明](../testing.md#当前兼容证据入口)。

`@open-document/pdf/core/pdf` 的 `PdfSession` 与 `@open-document/pdf/web/pdf` 的 `PdfClient` 共用类型化 `execute(command)`。同步入口由 `openPdf(engine)` 创建，Worker 入口为 `PdfClient.open(engine, workerUrl)`。字体使用 `addFont(bytes, identity)`。一个 UI 独占一个 client；低层调用方逐条 await 请求。公开请求和结果类型归 [`pdf-types.ts`](../../../packages/pdf/src/core/pdf-types.ts)。以下是当前实现合同，不表示所有输入组合均已验收。

### 会话、阅读与源保存

| 命令 | 输入与结果 |
| --- | --- |
| `defaultPdfBudget` / `openPdf` / `createPdf` / `queryPdf` | 默认预算；以 bytes/budget 和可选 password 打开，或以 width/height/budget 创建单页空白文档；查询当前源快照 |
| `renderPdfPage` / `releasePdfView` | revision、page、profile；返回 `PdfLayout`、DrawingBatch、文字 spans 与独立完整性/诊断。`activate: false` 不切换活动页；`reuse: true` 可复用匹配视图，结果 `reused` 表示复用；按 layoutId 显式释放 |
| `extractPdfText` / `searchPdfPage` | revision、page、profile；提取或给出 query 的字面命中与 quads，不切换展示页 |
| `hitTestPdf` / `selectPdf` / `selectedPdfText` | layoutId；point 命中、UTF-16 anchor/focus 选区和复制文字；未知映射明确失败 |
| `selectPdfRange` / `selectedPdfRange` | revision、两端 page/offset、profile；按文档顺序返回跨页文字和逐页 quads |
| `imagePdf` / `decodedImagePdf` | 按 layoutId/key 返回已解码 RGBA 或供宿主解码的原始 JPEG。两条路径由核心应用 Decode、SMask 和 Matte。`imagePdf` 可选 `size: { width, height }`，按 alpha 加权缩小已解码资源，保留原图 |
| `pdfNavigation` / `pdfMetadata` / `setPdfMetadata` | 查询目录、链接和 Title/Author/Subject/Keywords；元数据修改按 revision 提交 |
| `undoPdf` / `redoPdf` / `savePdf` | revision；历史操作返回快照，原格式保存返回 `{ revision, bytes }` |

`PdfClient.defaultBudget()` 包装 `defaultPdfBudget`；同步 session 为 `defaultPdfBudget()`。page/field/annotation 身份绑定对象号和代数，页序单独返回。revision 单调递增，失败不提交。保留视图在同 revision 内可跨页共存；编辑、字体变化、换文档或显式释放使相应 layoutId 失效。`PdfQuery` 返回 pages、annotations、fields、当前 page、历史、modified、diagnostics 及 readOnlyReason/pageOrderReason；对象、字段和批注分别提供保护原因。

核心严格读取未加密 PDF 1.0–1.7，并支持 PDF 2.0 的只读查看。显示支持源坐标 TrueType、上述 CFF1/Type3 范围、基础路径/裁剪、RGB/Gray/DeviceCMYK、常量 alpha/Multiply、限定图片/Form 和 normal appearance。空白、无边框和外观样式的只读文本框或组合框可无 AP；有值、列表内容、选择索引、富文本、样式或非法几何仍保留不完整诊断。ActualText/ToUnicode/可信编码独立生成语义；未知 Unicode 使用 U+FFFC，不匹配未知范围，含未知范围的复制失败。显示与提取完整性分别返回。

当末尾 `startxref` 的数字偏移错误时，核心可从末尾 64 KiB 内的完整经典交叉引用表恢复只读查看。恢复需要同一文件尾的完整 trailer 和 `%%EOF`。核心核对对象编号和偏移，再沿严格路径读取页面。带旧修订链接、混合引用或加密的文件沿既有规则处理。保存返回输入原字节，源改写和提取成新 PDF 受保护。[ISO 32000-1 §7.5.4–7.5.5](https://developer.adobe.com/document-services/docs/assets/35e4369068f86065372c18787171a17e/PDF_ISO_32000-1.pdf)

文件头或目录 `/Version` 声明 2.0 时，核心沿用现有读取和显示范围，并逐字节保存原件。旋转、改写及提取成新 PDF 受保护。无文件头或未知版本会拒绝。2.0 专用的图形、编码及其他扩展仍按各功能范围处理。[ISO 32000-2 §7.5.2、§7.7.2](https://developer.adobe.com/document-services/docs/assets/5b15559b96303194340b99820d3a70fa/PDF_ISO_32000-2.pdf)

当源文字靠字形位移留出词间距时，核心结合前一字形的水平 em 和包围盒推断空格。该规则只改变提取的文字与选区偏移，绘制和源字节保持。

加密 PDF 的只读范围为 Standard Security Handler V4/R4、128 位 RC4 或 AESV2。字符串和流使用 `StdCF`，AESV2 在打开时验证密码。文档须允许复制和打印。可提供 PDFDocEncoding 用户密码。未提供密码时先尝试空密码；`pdf-password-required` 允许重试。默认编辑器保留密码空白并支持取消。保存返回原加密字节，编辑和提取为新 PDF 受保护。其他加密方式和受限权限继续拒绝。[ISO 32000-1 §7.6](https://developer.adobe.com/document-services/docs/assets/35e4369068f86065372c18787171a17e/PDF_ISO_32000-1.pdf)

解压后没有任何内容的透明 Form 不参与合成。包含绘制操作的挖空组仍报告未支持。

源矩形规范化两个对角点，再组合 MediaBox/CropBox、页面旋转及显示变换。源文字提取保留裁剪区外全文；选择、复制、搜索命中及标记过滤完全位于 CropBox 外的字形，跨页复制沿用相同规则。可见性采用实际字形边界，空格采用基线推进段；选区仍保留文字方向并由页画布裁剪。CMap 字节目标与整数 CID 分别解析，范围展开遵守工作预算。基础字体字符串中的 CR/LF/Tab 保留语义，不作为缺失字形绘制。图片支持有界 ASCIIHex、8 位 RGB/Gray 软遮罩及匹配颜色分量的 Matte；撤销预混合后保留独立 alpha，零 alpha 的 Matte 像素清零。显式缩图按覆盖面积累加 alpha 和预乘颜色，再恢复直通 RGBA；非法尺寸或解码/步数预算失败保留会话和历史。

未支持的图形状态、组混合空间、挖空组、可选内容配置、颜色/字体/图片编码明确诊断；已知图片/批注可以局部限制，未知影响使整页预览不完整。输入范围和排除项见 [P7](../../implemented/p7-pdf-input.md#已交付范围)。签名只读且未验证，非零代数保护改写，不执行脚本或外部资源。导航仅返回目标；外部 URI 是否打开由宿主决定。

普通编辑在原对象图上构造局部候选，检查后原子提交。普通保存保留非目标字典及 stream 压缩 payload，重建 xref/trailer 并去掉旧增量/线性化声明。无编辑或全部撤销返回原字节。保存不替换基线、不清空历史；输出失败不改源。未引用对象仍保留，普通删除、裁剪、覆盖和保存不提供安全擦除；真正脱敏使用下述独立清理输出。

### 文字、图片和页面编排

| 命令 | 输入与结果 |
| --- | --- |
| `pdfObjects` | revision、page、profile；返回文字/图片对象、placement、内容和 readOnlyReason |
| `addPdfText` / `replacePdfText` | `PdfTextSpec` 指定 placement、text、font、size、color、role 和 foreground；批量新增到 pages，或替换指定 page/object |
| `addPdfImage` | page、placement、pixelWidth/pixelHeight 和 RGBA bytes；可用 `replace` 指定替换对象 |
| `rasterHeaderPdf` | 压缩图片的字节窗口 `bytes`、起始 `offset` 与源总长 `total`。返回像素尺寸、`nextOffset` 或 `error`。请求附带 `decode: true` 时，完整且在单次传输预算内的受支持 PNG/JPEG 可随尺寸返回 RGBA `bytes` |
| `movePdfObject` / `deletePdfObject` | page/object；修改 placement 或移除可隔离的对象 |
| `cropPdfImage` | revision、page/object、局部 0..1 的 crop 窗口及 profile；按选中的调用路径裁剪图片外观 |
| `setPdfPageNumbers` | pages、`PdfTextSpec`；使用 `page-number` 角色更新页码对象 |
| `reorderPdfPages` / `rotatePdfPages` / `deletePdfPages` | 稳定 pages；完整排列、degrees 或删除列表 |
| `insertPdfPages` / `replacePdfPages` / `insertBlankPdfPage` | 外部 PDF bytes、源 pages 和目标 index；替换另传 replace，空白页传 width/height |
| `extractPdfPages` / `splitPdfFiles` | 输出选定 pages 的新 PDF，或按 groups 返回多个命名文件；不修改源会话 |
| `cropPdfPage` / `resizePdfPage` | 当前显示坐标下的区域或新宽高；resize 明确 scaleContent 和 top-left/center anchor |
| `splitPdfPage` / `splitPdfPageGrid` / `nupPdfPages` | 按 regions 或 rows/columns 拆页；N-up 把指定 pages 排入给定宽高的网格 |

placement 使用页面显示方向的左上角 point 坐标及 rotation。新增文字由宿主供应的字体塑形，作为独立 Form 写入；角色支持正文、水印、页眉、页脚和页码，foreground 控制前景或背景。源正文继续保留原 PDF 字距。对象查询既识别 SDK 对象，也识别可安全隔离的源文字展示操作和图片调用。替换使用明确文字框和字体，不能把任意扫描页当作可编辑段落。不能安全隔离的共享或复杂 Form、未知映射、隐形文字、Tagged PDF、无法分离的源操作、倾斜/镜像及复杂裁剪按对象返回原因或拒绝操作。

Web 上传图片和图章时，使用同一个 Blob 读取图片。压缩源在 16 MiB 的单次传输预算内时，Worker 接收完整图片并尝试核心解码。较大的源按 64 KiB 的窗口读头，JPEG 的下一段起点由核心给出。核心未返回像素时，浏览器解码并核对尺寸。两条路径共用像素上限和编辑事务。

图片裁剪以 `{ x, y, width, height }` 指定图片局部保留窗口，核心只复制并改写选中的调用路径及 Form 外观。原像素和 mask 保留，裁剪不能用于脱敏；需要清除像素时使用清理输出。

源字体可按原 PDF 显示。源字体禁止再次嵌入时，可显式选择宿主供应的可嵌入字体替换正文。保存保留原字体流。

移动可隔离的源图片时，核心保留原压缩流和选中调用的绘制层。默认属性框格式化位置、尺寸及角度，去除重开后矩阵计算留下的末位噪声。

页面导入、替换、拆分和 N-up 同步受支持的页面引用、批注、widget、字段关系、目录及目的地；无法唯一归属或重映射的关系保护。拆页拒绝横跨分区或不落入任何分区的批注。N-up 使用原生 Form 拼页，保留支持的 appearance 和字段；选择的 widget 必须覆盖完整字段组，源 widget 页须无旋转且使用相同比例。回复/弹出、可选内容、Tagged PDF、固定视图批注标记及未知存活页引用继续保护。它们保留源对象语义；裁掉或未显示的内容不等于被清理。全部修改复用 revision、事务、撤销重做和预算；导出选页及分文件只返回派生字节。

### 表单与批注

PDF 核心只为当前开放子路径输出一次闭合。显式 `h`、矩形 `re` 与隐式闭合绘制 `s/b/b*` 共用该语义；空路径不产生绘制指令。重复闭合不会改变路径结构或使矩形外观绕过既有绘制规则。实现归 [`input-content.mbt`](../../../modules/formats/src/pdf/input-content.mbt)，依据 [ONLYOFFICE 子路径闭合](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/lib/xpdf/GfxState.cc#L4901-L4906)。

| 命令 | 输入与结果 |
| --- | --- |
| `createPdfField` / `pdfFieldDesign` / `updatePdfFieldDesign` | `PdfFieldDesign` 与各 widget 的 `PdfFieldWidgetDesign`；创建、查询或原子更新字段设计 |
| `setPdfFieldValue` | field、value、profile；文本/单选用 string，checkbox 用 boolean，list 用 string[]，同步所有 widget |
| `renamePdfField` / `duplicatePdfField` / `deletePdfField` | 修改同组内字段名；按 name/dx/dy 复制独立字段，或移除字段及 widget |
| `addPdfNote` / `markPdfText` | 便笺；对 layoutId 的核心选区写 Highlight/Underline/StrikeOut，`highlightPdfText` 为高亮入口 |
| `addPdfDrawingAnnotation` / `addPdfInkAnnotation` / `addPdfStampAnnotation` | Square/Circle/Line/Ink；分笔画墨迹或 RGBA 印章；可标为可视签名 |
| `pdfAnnotation` / `editPdfAnnotation` / `updatePdfAnnotation` / `deletePdfAnnotation` | 查询并修改支持的 geometry/color/opacity/border/author/text，或仅修改 text、删除批注 |
| `pdfAnnotationThread` / `replyPdfAnnotation` / `deletePdfAnnotationThread` | 查询回复关系、追加文字回复或删除整个线程 |

字段支持 text、checkbox、radio、choice 和 list。设计包含名称、提示、当前/默认值、只读/必填、多行/多选、最大长度、选项及字体/颜色/边框；更新保持字段类型并提交全部现有 widget，不能用设计更新隐式增加或遗漏成员。新字段和更新外观使用明确供应的可嵌入字体；`profile.form` 可指定表单默认字体。选项 export value 与显示 label 分开；不接受未知值或重复选择。

在编辑器中选择字段时，当前页有该字段的 widget 就留在当前页，否则定位到首个 widget 所在页。

多笔画墨迹和可视签名通过 pointer 采集，拖动期间应用与保存受草稿屏障保护；Escape、pointercancel 或失焦恢复本笔开始前的笔画，完成后显式应用为一次事务。

字段树、页面 Annots、widget Parent/Kids、值和 appearance 必须一致。XFA、动作、计算顺序、未知关系、锁定 widget、受保护嵌入字体和无法完整重建的外观拒绝修改；不执行 JavaScript、计算或提交动作。签名绘制仅生成可视墨迹/印章，不创建数字签名或验证证书。批注编辑保留支持的回复/弹出关系；未知关系、富文本、动作、Tagged PDF 和锁定批注继续保护。

读取 AcroForm 后备字段时，列表的空字符串值表示空选区，包括从父字段继承的值。字段查询优先报告整份表单的修改保护原因，再报告单个控件的原因。C31、C32 可查询后备值并显示已有外观，修改请求报告 XFA 保护。实现归 [input-fields.mbt](../../../modules/formats/src/pdf/input-fields.mbt)。

基础线批注使用 `BS/W` 或旧式 `Border` 读取实线宽度。显示和编辑都接受长度为零的引线及关闭的标题。样式编辑保留未移动的端点，写入覆盖完整笔画的普通线外观。非零引线和启用的标题继续受保护。[ISO 32000-1 第 12.5.6.7 节](https://developer.adobe.com/document-services/docs/assets/35e4369068f86065372c18787171a17e/PDF_ISO_32000-1.pdf)

### 真正脱敏与格式转换

`previewPdfRedaction` / `exportPdfRedaction` 接受 revision、regions 和 profile。区域为 `{ page, x, y, width, height }`，必须位于显示页内，最多 4096 个。预览返回 affected、warnings 和 readOnlyReason，显示实际扩大移除的范围；导出返回独立清理 PDF 字节。两者都不修改原文、选区或历史。

清理输出重新写出幸存文字字形、图片像素和受支持路径。相交文字至少移除整个源文字展示或 ActualText 组，使用实际墨迹边界覆盖负 bearing 和斜体；相交路径整项移除。私有图片把相交像素保守清零，透明像素的 RGB 同样清零。相交图片若复用图片/蒙版或处于复杂 Form 中则拒绝清理，相交交互字段也拒绝。所有幸存图片须已解码；幸存文字须有已知映射，全部正文须使用精确源字体。无法安全保留的裁剪/透明/混合状态以及无法解释的页面拒绝清理。单图片简单 Form 在完整解释和边界检查后可处理。

清理副本移除批注、交互字段、链接、元数据、附件及旧修订，自动丢弃隐形文字；不复制原内容流和整份原字体。幸存字形重建为无源提示程序、无自定义字形名和源身份的独立字体，保留必要授权记录；未知嵌入许可拒绝。无法精确重建的字体轮廓也拒绝。输出重新打开核对幸存语义和图片；普通黑框覆盖、删除对象及源保存仍不能代替此入口。

`defaultPdfOfficeBudget` / `convertPdfOffice` 使用目标 Office 包预算。请求指定 revision、pages、docx/xlsx/pptx、profile 和 acceptLoss；返回 status、warnings、reason、源页到目标页映射及可选 bytes。status 为 `success`、`completed-with-loss`、`needs-acceptance` 或 `failed`。默认不接受损失；需接受时不给输出字节，调用方查看逐页警告后显式重试。

DOCX 转为单栏原生段落、明确线框表格及图片，多栏结构拒绝。XLSX 识别具有明确边界的表格，保留合并单元格及严格数值；前导零保留字符串，公式不从 PDF 恢复，表外内容报告损失。PPTX 每源页生成一张幻灯片，使用原生文本框、图片、简单线形/矩形及表格。字体不嵌入目标 Office，边框归一化、混合行样式及绘制顺序变化明确报告损失。转换使用有界源提取，未知 Unicode 和解释失败拒绝；纯扫描页返回需要 OCR 的原因。当前不提供 OCR、原 Office 文件恢复或通用跨格式文档模型。

### PDF 派生输出

`PdfEditor.operations.exportPageImages(format, pages?, scale?, outputBytes?)` 返回逐页 `EditorOutput[]`，format 为 png/jpeg；使用同一 PDF 绘制路径逐页生成。绘制不完整时拒绝。输出页须非空且去重，累积字节受明确预算约束；后台视图按需复用并释放，不切换活动页。PNG/JPEG 是平台栅格结果，文本、字段和批注不再可交互。

`exportPdfText` / `PdfEditor.operations.exportText` 提供结构化 html/markdown，结果包含 bytes 和 warnings。输出按有界字形与路径推断段落、连续且可识别的项目符号/递增编号列表，以及规则线框和合并表格；不猜测标题层级。Markdown 的表格使用 HTML 保留跨度，不猜测表头。受支持图片从已验证 RGBA 重新编码为 PNG data URI；未解码、被裁剪、镜像或斜切的图片省略并给警告。

文字和属性完整转义；链接只允许 http(s)/mailto 及指向选中页的内部锚点，不自动请求外链。HTML 提供限制资源的 CSP。无法关联到完整文字行的链接、非表格矢量、交互行为及精确页面布局不保留，阅读顺序和段落推断也明确警告。未知 Unicode 原子拒绝，文字、图片和输出继续受预算约束。

Office 转换、文字输出、图片输出、选页、分文件及清理输出均不修改源 revision、历史或源保存基线。选页、分文件及清理 PDF 的 `EditorOutput` 只用于派生输出，`markSaved` 明确拒绝；只有原文 `save()` 产物可确认源保存。调用方负责下载或持久化，并查看结果警告。

### Web 嵌入与生命周期

`@open-document/pdf/web/pdf-viewer` 提供 `PdfViewer.create(root, client, profile?, signal?)`；返回值使用 `PdfViewer` 类型。`@open-document/pdf/web/pdf-editor` 提供相同所有权规则的 `PdfEditor.create`。两者共用阅读视图，Editor 以组合方式加入编辑能力。先由调用者打开 client、供应文件和字体：

```ts
import { PdfEditor } from "@open-document/pdf/web/pdf-editor";
import { PdfClient } from "@open-document/pdf/web/pdf";

const client = await PdfClient.open(engine, workerUrl);
await client.execute({ operation: "openPdf", bytes, budget: await client.defaultBudget() });
await client.addFont(fontBytes, "regular");
const editor = await PdfEditor.create(container, client, { form: "regular" });
propertyPanel.append(editor.propertyInput);
const saved = await editor.save();
// Persist saved.bytes, then editor.markSaved(saved) to confirm the output.
await editor.dispose();
client.dispose();
```

viewer 提供 `snapshot`、`displayedPage`、`refresh`、`goToPage`、`navigatePage`、`setZoom`、`setReadingMode`、`selectText`、`selectRange`、`selectedText`、`copy`、`extractText`、`navigation`、`search`、`cancelSearch`、`nextMatch` 和 `showMatch(index)`。`showMatch` 使用从零开始的结果索引，定位并高亮命中，保留结果控件的焦点。editor 另外提供对象、页面编排、字段、批注、脱敏、转换及输出操作。`thumbnail(page)` 生成独立缩略图。`setReadingMode` 接受 single/continuous/double。`chooseProperty`、各 `begin…` 入口、`applyDraft` 和 `cancelDraft` 共用属性草稿。自定义 UI 可挂入稳定的 `propertyInput`。切页、换文档、刷新和输出前应用或取消草稿。组合期间禁止提交。默认 UI 的文件替换使用 `MountedEditor.open`。

默认 React 组件和 `mountEditor` 共用阅读、编辑内容、批注、页面、表单和视图标签。阅读标签提供搜索结果定位。文件菜单的文件属性读取标题、作者、主题和关键词。页面任务可以按稳定页面标识选择多页，批量移动、旋转和移除各提交一项历史。提取所选页面生成派生文件。表单和批注任务沿用原生草稿。脱敏副本在独立任务中标记、预览并确认导出。

文档操作使用 `editor.operations`：页面移动/旋转/增删/替换/拆分/N-up、字段创建/改名/复制/移除/赋值、便笺/印章/文字标记/批注修改、脱敏预览与输出、Office 转换及派生图片/文字/分文件输出。它们共用 Editor 的草稿检查、队列和提交屏障，执行时读取当前状态与页面表面。原格式 `save()`、`undo()`、`redo()`、属性草稿与阅读操作仍直接归 Editor。

`beginPageGeometry("crop" | "resize" | "scale")` 用原生属性草稿设置页面区域或尺寸；`beginImageCrop()` 使用百分比控件设置图片保留窗口。选中的正文/图片可以用 pointer 框拖动：候选只更新 x/y 输入，松开后等待显式应用，取消或 Escape 还原。拖动期间保存与关闭受屏障保护，应用才提交 `movePdfObject`；图片裁剪同样一次应用形成一项历史。

队列最多 128 个已接受意图，保存排在已接受编辑之后。低层 `close()` 校验草稿并等待已接受操作后释放表面；`dispose()` 停止接收新操作和搜索，等待已接受操作后释放表面，两者都保留调用者的 client。呈现失败保留已提交源，停止新编辑，允许保存、刷新或显式撤销。单页、连续及双页阅读共用绘制器；连续/双页仅保留可见页和有限邻页，最多 8 页 Canvas，合计 64 MiB。核心最多保留 9 个视图，其中一个供缩略图或后台输出临时使用，保留视图的解码图像合计仍限 16 MiB。缩略图和输出不改变活动页或选区；取消搜索及关闭后旧回复不能重绘。

### PDF 默认预算

预算必须为正且不大于核心默认值。可从默认值复制并收紧：

| 字段或资源 | 默认上限 |
| --- | --- |
| fileBytes / outputBytes | 各 64 MiB |
| objects / objectNumber / pages | 100000 / 1000000 / 1024 |
| revisions / depth / Form 与绘制栈 | 128 / 64 / 32 |
| streamBytes / decodedBytes / steps | 16 MiB / 64 MiB / 10000000；同次操作共享耗尽状态 |
| 当前页文字 / 查询 / 命中 | 262144 / 1024 UTF-16 单元 / 每页及 viewer 各 10000 |
| 批注 / widget / 字段树深度 | 每文档各 4096 / 64 |
| 字段/便笺 / 高亮 / 候选与历史 | 32767 UTF-16 单元 / 4096 quad / 8 MiB，undo+redo 共 100 项 |

PDF 核心定义查询长度上限，浏览器查看器使用构建生成的同一数值。

字体、RGBA、图元、轮廓与 Canvas 沿用前述共同限制。PDF 源字体只显示时允许合法子集省略 cmap/OS2；需要重新嵌入时仍检查字体权限，未知权限拒绝。预算检查覆盖分配和循环，保存先保守估计编码大小，再核对确切大小；不保证总堆峰值或延迟。同步 Wasm 不可抢占，宿主只能在异步步骤间取消或终止 Worker。
