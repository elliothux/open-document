# P12 PPTX 核心功能

状态：`planned`，第 1、2、3、5 批实施中。基于 [P6 PPTX](implemented/p6-pptx-editing.md)和已完成的 [P9](implemented/p9-web-sdk-ui.md)。复用 [P10](p10-docx-core.md) 已交付的包写入，并按实际需要复用 P10 / [P11](p11-xlsx-core.md) 的文字、图形和图表能力。属于功能优先级 P0。空白创建已接通，其余能力仍按下面的范围实施。顺序归[路线图](references/roadmap.md)，当前 API 归[格式合同](references/formats.md#pptx)，功能依据归 [G3](g3-genoffice-sdk-gap.md#演示pptx)。

当前进度：核心创建 960×540 pt 的单页空白文稿，包含版式、母版、主题和完整部件关系。同步 Wasm、Worker 和默认 UI 接通创建、首次保存、另存、保存重开与静态 PDF。支持插入文本框、矩形、圆角矩形、椭圆、三角形、直角三角形、菱形、平行四边形、梯形、直线和四向实心箭头；支持本地顶层形状/图片/组的多选复制、删除、旋转、水平/垂直翻转及层次调整，保留源格式、关系及撤销重做。已接通空白页新增、页复制/删除/重排与隐藏/显示，保持剩余页/对象身份，历史按稳定部件路径恢复。新增页沿用目标页的版式、母版和主题；复制更新对象、计时目标和自身链接，独立复制普通备注与传统批注；删除页同步页引用、自定义放映与已知内部链接，保留共享和未知资源。部件新增/删除与对象编辑共同撤销。保存失败与替换取消保留当前会话。对象多选、成组移动/等比例缩放、删除及对齐/分布已接通；组合及含非等比缩放/嵌套组的取消组合已接通；普通章节新增、改名、移除并保留页面、整章重排和连同页面删除已接通；默认页列表已有逐章及全部折叠/展开，并可一次移除所有章节且保留页面；组内编辑、更多几何和后续批次尚未完成，不标记第 1 批或整个 P12 完成。

## 1. 用户结果与范围

对象外观已接通纯色/无填充、双色线性渐变（角度与比例）、纯色/无边框、宽度、预设虚线、平头/圆头/方头端点及圆角/斜角/斜接连接。核心、Wasm、Worker 和默认 UI 共用多选事务，保留身份、几何、文字及精确历史。已检查独立 XML、Canvas 实际颜色、保存重开和继续原生输入；形状填充和边框的不透明度已接通，保留主题色关联与文字不透明度；渐变复用背景颜色和角度解析，按预设轮廓裁剪，并随对象变换输出到 Canvas/PDF。支持多选、精确历史及保存重开；多色标、透明/径向渐变及效果仍待实现。接口与边界归[格式合同](references/formats.md#pptx)，实现归 [`object-paint.mbt`](../modules/formats/src/pptx/object-paint.mbt)、[`line-dash.mbt`](../modules/formats/src/pptx/line-dash.mbt)、[`line-pen.mbt`](../modules/formats/src/pptx/line-pen.mbt)及 [`shape-opacity.mbt`](../modules/formats/src/pptx/shape-opacity.mbt)。

形状图片填充已接通本地 PNG/JPEG 拉伸/平铺、多选共享资源和默认面板。平铺按 96 DPI 生成尺寸，支持已有源的缩放、偏移、九种对齐和交替翻转；默认面板可切换已有图片的模式，保留资源、透明度、文字和精确历史。单页重复数量在提交和变换候选更新前检查。导入支持本地、版式/母版及主题来源，保留源裁剪和不透明度。文字、轮廓、描边和几何保持，Canvas/PDF 使用相同裁剪路径，支持精确历史及保存重开。文件读取前绑定目标对象，选择改变后拒绝提交；带裁剪源的平铺已接通，保留裁剪值并在拉伸时应用；目标内缩、固定页面方向及未知效果继续保护，仍属本阶段待实现范围。接口和边界归[形状图片填充](references/formats.md#形状图片填充)，实现归 [`shape-image.mbt`](../modules/formats/src/pptx/shape-image.mbt)。

第 2 批已接通本页纯色及双色线性渐变背景、恢复继承、整稿尺寸调整、已有版式切换与当前版式重置，支持默认 UI、Wasm 与 Worker API，保留选择和精确历史。渐变支持任意角度及按页面比例缩放，沿既有图元输出 Canvas/PDF，原生文字编辑保留背景面板草稿。尺寸调整同步缩放页面、版式、母版及组内几何，保持字号和方向。版式切换按类型/索引保留占位符内容，并补齐空占位符，关系、字体/背景继承及对象一起恢复；模板提示不成为用户文字。多色/透明/路径渐变、图表/表格对象与非空参考线仍保护源内容；主题颜色及字体已接通全稿使用中主题的同步修改；版式与母版直接编辑尚待实现。实现归 [`background-fill.mbt`](../modules/formats/src/pptx/background-fill.mbt)、[`slide-background.mbt`](../modules/formats/src/pptx/slide-background.mbt)、[`slide-size.mbt`](../modules/formats/src/pptx/slide-size.mbt)及 [`slide-layout.mbt`](../modules/formats/src/pptx/slide-layout.mbt)，合同及检查归[格式说明](references/formats.md#pptx)。

本页 PNG/JPEG 图片背景已接通核心、API 和默认面板，支持拉伸/平铺、四边裁剪、不透明度、恢复继承、精确历史及保存重开；模式、裁剪和不透明度合为一次格式事务。图片沿实际幻灯片/版式/母版/主题来源读取，保留导入裁剪与透明度；模式修改复用资源，前景对象和正文输入保持。Canvas/PDF 共用整页裁剪与图片清单，背景和形状平铺共用数量上限。裁剪重置与 0–100% 不透明度已有默认面板，沿相同源矩形和源像素 alpha 输出 Canvas/PDF。带裁剪元数据的平铺沿 ONLYOFFICE 绘制整图，切回拉伸后恢复裁剪，源、资源与历史一起保持。其他填充和母版直接编辑继续实施。合同归[图片背景](references/formats.md#图片背景)。

PNG/JPEG 图片插入已接通核心、Wasm、Worker、宿主和默认 UI。新对象在最上层，图片原字节、关系、内容类型与选择共同提交和精确撤销；原生文字草稿仍独立提交。对象与页面复制复用同一图片，保存重开后可继续变换，Canvas 与静态 PDF 复用现有解码和图元。替换与四边源矩形裁剪/重置已接通，保持对象身份、几何、方向和其他副本；图片常量不透明度已接通，保留源像素 alpha 并同步 Canvas/PDF。独立图片的拉伸/平铺读取、模式切换和默认面板也已接通，复用 96 DPI 平铺、源裁剪保留、透明度、资源与精确历史。已支持预设的图片框沿实际轮廓裁剪，检查覆盖椭圆框内外 Canvas/PDF；未知几何继续保护。实现归 [`object-image.mbt`](../modules/formats/src/pptx/object-image.mbt)及 [`image-opacity.mbt`](../modules/formats/src/pptx/image-opacity.mbt)，合同归[格式说明](references/formats.md#pptx)。

普通演讲备注已接通核心、API、默认面板、精确历史及保存重开。首个备注页、关系和内容类型一起创建；修改保留幻灯片、其他备注占位符、未知外围源与资源，清空保留备注页。页面复制独立复制备注，删除回收独占备注。备注文字不进入幻灯片画布和静态 PDF；备注母版编辑、富文本控件及演讲者界面仍待实现。合同归[演讲备注](references/formats.md#演讲备注)，实现归 [`slide-notes.mbt`](../modules/formats/src/pptx/slide-notes.mbt)、[`notes-read.mbt`](../modules/formats/src/pptx/notes-read.mbt)及 [`notes-create.mbt`](../modules/formats/src/pptx/notes-create.mbt)。

传统本地批注及单层回复已接通读取、创建、修改、删除、API 和默认面板。宿主显式提供作者，平台传入创建日期；核心维护独立部件、作者与回复索引，复制页重映射回复目标，删除页回收独占批注。文字和其他源保持、精确历史及重开共用现有事务；现代云批注与未知扩展继续保护。合同归[本地批注与回复](references/formats.md#本地批注与回复)。

当前页 PNG Web 导出已接通 `PresentationEditor.exportPng`、文件菜单和保存回调。核心仍生成布局与 R0 图元，Web 在独立 Canvas 重放并编码，复用已准备的图片和轮廓，不改变选择、原格式保存状态或历史。导出尺寸按源页面 pt 与明确比例生成，不随预览缩放或 DPR 改变；选择框、光标和备注不进入图片。像素及字节预算失败后可继续编辑；输入/变换候选仍须先结束。浏览器编解码依赖、边界和检查归[当前页 PNG 输出](references/formats.md#当前页-png-输出)。批量图片、其他格式及打印继续实施。

用户能从空白文稿制作演示，管理页面、主题/母版/版式，创建并编辑文字、图形、图片、表格和图表，添加媒体与基本动画，放映并输出。程序化 API 提供与 UI 相同的文档操作。GenOffice 源码用于功能与交互，核心语义和算法优先参考 ONLYOFFICE，其次 LibreOffice。

| 批次 | 用户操作及最低交付范围 | G3 对应 |
| --- | --- | --- |
| 1. 文稿与对象创作 | 空白文稿；页增删/复制/重排/隐藏/章节；对象插入/删除/复制、多选、移动/缩放/旋转/翻转、对齐/分布、组合/取消组合与层次 | T01、T04–T06 |
| 2. 文字与页面设计 | 字符/段落/项目符号格式、查找替换、框内边距/垂直锚定/自动适配；页面尺寸、背景、主题、版式/母版及占位符编辑；形状样式和图片插入/替换/裁剪/透明度 | T02、T03、T07–T10 |
| 3. 复合内容 | 表格及行列/合并/样式；图表及嵌入数据；简化 SmartArt 形状组、数学公式和基础艺术字；链接/动作、备注、批注、日期/页码/页脚 | T11–T14、T16、T17 |
| 4. 放映与媒体 | 放映/演讲者界面、页导航、临时画笔；音视频插入和播放；基本切换、对象动画、顺序/触发/计时编辑 | T15、T18、T19 |
| 5. 文件与输出 | 插入其他 PPTX 的受支持页面；补齐本阶段对象的原格式保存、图片、静态 PDF 和打印 | T01、T21 |

第一批即交付保存重开与已有静态 PDF，后续新增对象同步补输出。图表使用前阶段已实现的常用二维类型；SmartArt 首批交付流程、层级与循环等可编辑形状组，不声称是原生 diagram 编辑器。

复杂几何/效果、原生 SmartArt、动画效果全覆盖、多栏/竖排与长尾适配、编码和导入变体归 P14。3D、AI、协作、Diff 与跨窗口演讲者扩展归 P15/P16。基础放映和媒体不依赖 Electron 或远程服务，也不把“动画 XML 已保留”记作可播放。

## 2. 当前基础与改动位置

| 位置 | 当前能力与本阶段改动 |
| --- | --- |
| [`pptx/session.mbt`](../modules/formats/src/pptx/session.mbt)、[`tree.mbt`](../modules/formats/src/pptx/tree.mbt) | 解析 slide/layout/master/theme，缓存源树并派生对象；补文稿结构、新建和跨部件事务 |
| [`model.mbt`](../modules/formats/src/pptx/model.mbt)、[`editing.mbt`](../modules/formats/src/pptx/editing.mbt)、[`slide-add.mbt`](../modules/formats/src/pptx/slide-add.mbt)、[`slide-copy.mbt`](../modules/formats/src/pptx/slide-copy.mbt)、[`slide-copy-comments.mbt`](../modules/formats/src/pptx/slide-copy-comments.mbt)、[`slide-order.mbt`](../modules/formats/src/pptx/slide-order.mbt) | 有序对象集合/文本选择、新增部件与 XML 历史、页新增/复制/删除/重排/隐藏及文字或变换候选；扩展资源所有权、多选其余操作、组内/母版编辑 |
| [`geometry.mbt`](../modules/formats/src/pptx/geometry.mbt)、[`layout.mbt`](../modules/formats/src/pptx/layout.mbt)、[`hit.mbt`](../modules/formats/src/pptx/hit.mbt) | 已有基本形状、图片、矩阵、层次命中；补对象类型、组内选择和播放时显示状态 |
| [`object-arrange.mbt`](../modules/formats/src/pptx/object-arrange.mbt) | 多选方向和层次事务；保留源片段与有序选择 |
| [`object-copy.mbt`](../modules/formats/src/pptx/object-copy.mbt) | 多选与嵌套组复制；复用页复制的身份与内部引用重映射 |
| [`object-selection.mbt`](../modules/formats/src/pptx/object-selection.mbt)、[`object-alignment.mbt`](../modules/formats/src/pptx/object-alignment.mbt) | 多选包围盒、成组移动/等比例缩放、对齐及分布；保留活动对象、源几何与原子历史 |
| [`object-group.mbt`](../modules/formats/src/pptx/object-group.mbt)、[`group-geometry.mbt`](../modules/formats/src/pptx/group-geometry.mbt) | 组合、含缩放与嵌套组的取消组合、父组身份、归一尺寸及命名空间保留 |
| [`theme.mbt`](../modules/formats/src/pptx/theme.mbt)、[`text-edit.mbt`](../modules/formats/src/pptx/text-edit.mbt)、[`autofit.mbt`](../modules/formats/src/pptx/autofit.mbt) | 有限主题继承、纯文本和有界字体缩放；补格式/占位符修改和相关失效 |
| [`bridge/pptx.mbt`](../modules/bridge/src/pptx.mbt)、[`wasm/pptx.ts`](../packages/wasm/src/pptx.ts)、[`web/pptx.ts`](../packages/web/src/pptx.ts) | 延续 `PptxCommand` 与 `execute`；增量加入类型明确的操作与结果 |
| [`presentation-editor.ts`](../packages/web/src/presentation-editor.ts)、[`presentation-pointer.ts`](../packages/web/src/presentation-pointer.ts)、[`ui/panels.tsx`](../packages/ui/src/panels.tsx) | 保留候选、输入、列表/焦点与 P9 状态；增加创作面板和独立放映视图 |

当前组成员、继承对象和未知对象存在只读保护。扩展时逐类补齐语义与写回，不通过删除保护开放任意对象。保持未知可见对象阻止点穿的规则。

## 3. 第一批：文稿、对象与事务

### 3.1 新建和页面结构

核心创建最小文稿：presentation、一个空白 slide、关联 layout/master/theme、关系与内容类型。资源与页面尺寸使用明确的核心默认值，不复制桌面应用模板依赖。接通 P10 扩展后的 P9 空白挂载/新建入口与首次保存状态。

当前 slide ID 为源部件路径，对象 ID 为所属部件与 `cNvPr.id`。延续稳定身份：页重排不改变 ID，复制生成新 ID；页索引只作为展示顺序。新增/删除/重排同时维护 `sldIdLst`、关系、章节、页间链接和活动选择。首批保留至少一页；删除最后一页时明确拒绝，不留下不可布局的会话。

当前 `editPptxSlides` 与 `PresentationEditor.editSlides` 已支持指定目标索引重排及隐藏/显示。重排只移动 presentation 中的页引用，隐藏只改 slide 的 `show`；关系、对象、图片、备注及自定义放映保持原样，活动页和对象选择不变。默认 UI 提供前移/后移、隐藏/显示及页列表状态。候选期间、旧 revision、无效目标和预算失败不修改源或历史。损坏章节、位置型放映范围与未知扩展仍保护重排；空参考线列表和已知图片/图表设置扩展可原样保留，完整边界归[格式合同](references/formats.md#pptx)。

同一入口的 `{ action: "add" }` 在目标页后新增空白本地内容，切到新页并清空对象选择。它沿用目标页的版式、母版和主题，继承版式/母版中的装饰与背景；不复制原页对象、备注、动画或版式占位符。核心分配新页身份、路径和关系，保留原页、资源及自定义放映。新增部件、内容类型和页面引用合为一项历史，可与后续文字/对象、重排、隐藏混合撤销。已通过保存重开与同布局 PDF；结构保护或预算失败不留下半页。

同一入口的 `{ action: "delete" }` 删除目标页，至少保留一页。同步移除页引用、自定义放映条目和指向该页的已知点击/悬停链接，保留链接所在对象。删除活动页时切到相邻页并清空对象选择；其他页的活动选择不变。页面、关系及独占的备注/传统批注 XML 和内容类型共同进入一项有界历史。共享图片、版式、作者和未知资源保留；未知引用、共享备注/批注或预算失败原子拒绝。具体边界归[格式合同](references/formats.md#pptx)。

`{ action: "copy" }` 复制到目标页之后，激活副本并清空对象选择。核心分配新页和本地对象身份，重映射计时目标、连接引用和自身页链接。保留隐藏状态、对象内容、几何和格式，复用图片及版式/母版/主题；普通备注和传统批注复制为独立部件，备注回链指向新页，批注索引及作者 lastIdx 同步更新。已知 creationId 与 DrawingML 字段生成新身份；未知身份扩展及未接入所有权的可变资源仍受保护，含图表数据的页面暂不复制。源页、自定义放映和其他页链接不变。复制部件与后续编辑、隐藏、删除可精确混合撤销；具体边界归[格式合同](references/formats.md#pptx)。对象、备注和计时复制规则参考 [ONLYOFFICE Slide.createDuplicate](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L268-L332)。保留计时 XML 不代表已支持动画播放。

普通章节已接通核心、API 与默认面板。`sectionAdd` 在目标页前分章，`sectionRename` 保留身份，`sectionRemove` 保留页面并合并到相邻章，`sectionMove` 同步重排整章页面，`sectionDelete` 在一项事务中删除章节和所属页面。页新增/复制/删除/移动同步章节归属，空章节保留。章节、页序及原生文字共用精确历史；保存重开和静态 PDF 按实际页序输出。标准 p14 存储、上限与未知源保护归[格式合同](references/formats.md#pptx)，实现归 [`sections.mbt`](../modules/formats/src/pptx/sections.mbt)、[`section-edit.mbt`](../modules/formats/src/pptx/section-edit.mbt)及 [`section-source.mbt`](../modules/formats/src/pptx/section-source.mbt)。章节删除复用页面删除的链接同步、独占备注/批注回收及累计历史预算；失败整项拒绝，至少保留一页，空章只删除元数据。默认页列表按章节分组，支持键盘折叠/展开、全部折叠/展开，保留全稿页码和隐藏页标记。折叠只改变 React 视图状态，保留画布当前页，不修改源文件、选择或历史。外部页导航自动展开目标章；改名和重排按稳定章节身份保持状态，移除章节清理状态，更换文档重置。实现归 [`pptx-slides.tsx`](../packages/ui/src/pptx-slides.tsx)，完整边界归格式合同。`sectionRemoveAll` 一次移除全部章节并保留所有页面、选择和其他部件，只新增一项历史。没有章节时不新增历史；未知章节仍保护，章节外的未知扩展和外层标记保留。

删除仅回收确定由该操作拥有且无引用的部件；不对整个源包做清理优化。

### 3.2 对象选择与几何

选择类型明确区分页集合、对象集合、文字范围和表格单元格。对象集合同时记录活动对象与稳定顺序；进入文字编辑时必须有唯一文字目标。核心产生每种选择的命中、轮廓和手柄，Web 不根据 Canvas 像素猜对象。

对象集合现已接通核心、同步 Wasm、Worker 和默认 UI。`selection.objects` 保存最多 256 个稳定身份及选择顺序，`selection.object` 保存集合中的活动对象。Shift 点击画布或对象列表切换成员，普通点击已选成员保留集合并切换活动对象，Ctrl/Cmd+A 选择当前页对象。进入文字模式时收敛到唯一活动目标。核心返回各成员轮廓、整组包围盒与手柄；含只读成员时隐藏变换手柄并保护整组编辑。

已支持成组移动、角点等比例缩放及多选删除。缩放保留各成员的旋转、局部翻转和零尺寸线段，整组非等比例变换仍拒绝。变换按手势开始时的几何计算，预览不写源；完成或删除提交一项历史，取消不改变源，撤销恢复原选择集合及活动对象。任一成员锁定、几何越界或预算失败时整项拒绝。核心已检查旋转线段、候选重算、精确历史与保护；Chromium 已检查 Shift 多选、真实拖动、取消、删除、独立 XML、保存重开和宿主调用。组合与受支持的取消组合见下文，组内编辑仍待实现。

移动采用 [ONLYOFFICE MoveShapeImageTrack](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/MoveTracks.js#L103-L145) 的原始位置加增量规则，复用核心旋转/翻转矩阵；属性面板与指针使用相同候选路径。

对齐和分布已接通核心、Wasm、Worker、宿主及默认属性面板。六种对齐支持相对页面、选区包围盒或活动对象。水平/垂直分布支持页面和选区，按旋转后矩形的中心排序，计算相等边缘间距；中心相同时保留选择顺序。页面分布平衡两端留白，内容总尺寸超过页面时允许负间距。规则参考 [ONLYOFFICE CommonController](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L9307-L9587)。各成员保留尺寸、旋转、翻转、文字和身份；一次提交一项历史，无变化不新增历史。保护或预算失败整项拒绝。核心已检查旋转/线段、各参考范围、负间距、精确历史及失败；Chromium 已检查默认按钮、参考范围保持、独立 XML、保存重开和继续编辑。接口和最少对象数归[格式合同](references/formats.md#pptx)。

组合与取消组合已接通核心、Wasm、Worker、宿主及默认 UI。组合保留成员身份和源顺序，将局部坐标写入新组；新组位于所选最上层对象的位置。顶层组可整体移动、缩放、旋转、翻转、对齐、调整层次和删除。取消组合支持非等比缩放和嵌套，核心将累计组缩放换算为成员框的位置和尺寸，再恢复世界旋转/翻转与子坐标原点。字号、边距和线宽保持原值，文字按新框排版；候选与源重读使用相同规则。成员身份、命名空间、注释和其他资源保留，组内直接编辑仍受保护。核心已检查嵌套、零尺寸线段、预览/提交一致、精确历史、锁定、引用和预算失败；Chromium 已检查缩放组取消组合前后 Canvas 画面和 PDF 文字坐标不变、独立同字号文本、XML、保存重开与继续输入。详细规则与上游依据归[格式合同](references/formats.md#pptx)。直线两端的三角、凹尾、菱形、椭圆和开放箭头样式及宽/长尺寸已接通核心、API 和默认面板，支持继承恢复、多选、轮廓命中、精确历史和保存重开；Canvas/PDF 使用相同路径，合同归[直线端点样式](references/formats.md#直线端点样式)。连接线端点坐标编辑及目标联动仍待实现。

已支持矩形、圆角矩形、椭圆、五种常用多边形、线、四向实心箭头和文本框插入；墨迹路径仍待实现。圆角矩形和箭头的路径、命中与文字内框按 [ONLYOFFICE 预设几何](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L6950-L6987)计算，导入的数值调节点参与形状和文字布局，旋转/翻转沿现有矩阵。默认 UI 插入、轮廓外命中、复制、混合精确历史、保存重开及 PDF 已检查。圆角半径、箭身宽度及箭头长度的数值修改与恢复预设已接通核心、API 和默认属性面板，支持同类调节项多选、精确历史、保存重开及文字适配同步；指针调节手柄、更多箭头和任意自定义几何仍待扩展；未知公式保留源并诊断，不能改成默认几何覆盖源对象。

当前已接通 `editPptxObjects` 与 `PresentationEditor.editObjects`，具体合同归[格式说明](references/formats.md#pptx)。新对象在最上层；复制已支持有序多选及嵌套组。副本按原层次放到最上层，为顶层对象、组成员及域分配会话内未使用的新身份，重映射副本内部引用。保留旋转、翻转、组缩放、格式、命名空间与图片关系，选择顺序和活动对象对应副本；默认 UI 平移 18 pt。复制按 [ONLYOFFICE GroupShape.copy2](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L310-L339)保留成员顺序与源格式，并复用已有页复制的身份重映射。核心已检查嵌套组矩阵、精确混合历史、锁定、缺字体及预算失败；Chromium 已检查多选按钮、组复制快捷键、独立 XML、撤销、保存重开及副本继续移动。删除清空对象选择，撤销恢复原身份与选择。锁定、继承、组成员、未知扩展复制及带连接/计时引用的删除仍受保护；待对应事务实现后开放。上述形状插入及复制/删除仅修改所属 slide XML，保留其他部件及资源；图片插入同时创建资源事务，见格式合同。

多选角度输入为共同的绝对角度，每个对象保持自身中心；翻转分别反转各成员原有局部轴状态。沿用 [ONLYOFFICE 的逐对象方向属性处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L4367-L4411)。组的内部源坐标保持，缩放组成员经完整矩阵显示。保留选择顺序和活动对象；一项操作合为一项历史，任一成员或预算失败整项拒绝。默认面板显示混合角度与翻转状态，非活动成员的旋转锁也参与禁用。核心已检查独立中心、零尺寸线段、缩放组矩阵、精确历史和失败；Chromium 已检查选择集合变化后的角度刷新、混合控件、独立 XML、撤销重做、保存重开与继续编辑。置顶/置底及前移/后移一层已支持顶层对象集合，包含受支持的组。置顶/置底按原源顺序移动所选对象；前移从高层向低层处理，后移反向处理，每个所选对象越过一个相邻未选对象，连续选择保持相对顺序。规则依据 [ONLYOFFICE CommonController](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L9589-L9695)。保留对象身份、几何、资源、选择顺序、活动对象、注释和未选源片段，一次操作一项历史。核心已检查相邻/分散选择、边界、最上层命中、组及未知对象保留、精确历史与失败；Chromium 已检查四个按钮、独立 XML、混合撤销及组保存重开后继续调整。相同角度、已到达层次边界时不新增历史。旋转遵守 `noRot`，翻转和层次操作继续使用各自保护；组内/母版编辑尚未接通。

三角形、直角三角形、菱形、平行四边形和梯形已接通核心、类型化 API 和默认插入面板。三角形顶点及两个斜四边形偏移可数值修改和恢复预设，按实际宽高限制；导入、轮廓命中、文字矩形、旋转复制、精确历史、保存重开及原生文字共用已有流程。Canvas 与静态 PDF 的轮廓内外像素已检查。接口及上游依据归[多边形与调节值合同](references/formats.md#pptx)，实现归 [`polygon-shapes.mbt`](../modules/formats/src/pptx/polygon-shapes.mbt)。

### 3.3 原子保存和资源

当前 PPTX 历史按稳定部件路径记录 XML 变化集合，已包含新增 slide、其版式关系、presentation 元数据、删除页的部件快照和图片新增/替换的原字节资源。页序、对象编辑与部件增删共同使用预算、revision 与前后选择，可混合精确撤销和重做。后续继续扩展 layout/master/theme 编辑与新资源；复用核心包新增/删除能力，各格式保留自己的事务规则。

创建、复制和母版修改先在候选中解析并校验引用和预算，再提交一次 revision/历史。复制大量对象或媒体必须在分配前检查数量、字节和历史持有量；二进制资源复用不可变字节但仍计入预算。失败不留下半页、空关系或已提交的一半对象。

## 4. 页面设计、文本与复合内容

### 4.1 主题、版式与母版

核心保留“源属性”和“继承后的有效属性”的区别。普通视图修改页内对象写局部覆盖；母版视图明确定位对应部件并影响引用它的页面。重置版式清除支持的覆盖，不能通过把有效属性全部写死来实现主题编辑。

已有版式切换已接通核心、API 和默认面板。按占位符类型/数值索引匹配，保留用户内容、身份与直接格式，重新派生几何和继承样式；缺少的普通占位符生成空文字对象。没有匹配位置或存在歧义时，已有用户内容明确报冲突；仅可安全丢弃的空占位符移除。核心检查跨母版继承、页面复制、精确历史、源引用及预算失败，Chromium 检查原生草稿、面板、独立 XML、背景像素、重开和继续输入/PDF。合同归[幻灯片版式](references/formats.md#幻灯片版式)。

当前版式重置已接通核心、API 和默认按钮。恢复占位符几何并补齐缺失空框，保留用户文字及直接格式，复用版式事务、精确历史、重开与 PDF；重复调用无变化。核心覆盖锁定、未知标记、继承及预算失败，现有 Chromium 版式流程增加移动后原生草稿、面板重置、独立源和两步精确历史。行为及边界归[幻灯片版式](references/formats.md#幻灯片版式)。

主题颜色已接通核心、API 和默认面板，可修改深浅色、六个强调色及链接颜色。按普通视图规则同步修改文稿实际使用的主题，重新派生页面背景、形状、描边和文字；对象直接颜色、颜色映射、字体、几何及其他源片段保留。混合主题返回混合值，原生草稿独立提交，主题修改和全部依赖页合为一次精确历史；无变化及保护/预算失败不提交。两项新增核心与十项背景/版式/尺寸回归、一条 Chromium 流程及安装包检查通过；合同归[主题颜色](references/formats.md#主题颜色)。主题字体也已接通标题/正文、Latin/EA/CS 和补充文字类别的查询、修改、新增与非 Latin 回退清除。一次修改同步使用中主题，并在提交前检查受影响字体及粗斜体 profile；普通、继承及组内自动适配框与主题一起更新和精确撤销，直接字体保持。默认面板支持新增类别，撤销新增后仍可继续编辑。三项新核心、六项主题颜色/文本框/适配回归、两条 Chromium 流程及安装包检查通过；合同归[主题字体](references/formats.md#主题字体)。母版/版式直接编辑继续实施。复制/删除母版或版式须检查所有引用；图表按复合内容批次接入主题重排。尺寸修改已采用各轴缩放内容的策略，同步写回所有页面、相关版式和母版；尺寸边界归[格式合同](references/formats.md#pptx)。

背景、形状填充/描边与基础阴影写回 DrawingML。首批支持无/纯色/线性渐变/图片填充、常用线宽/虚线和基础透明度；不支持的效果仍可保留，但相关输出或修改需要说明范围。图片替换保持对象身份，裁剪使用源矩形，压缩源与资源关系一起事务更新。

### 4.2 文本和表格

文本框四边内边距、上/中/下垂直对齐、换行、缩小字体及形状随文字调整大小已接通核心、API 和默认 UI。支持本地顶层形状的混合多选，保留文字及对象选择。缩小模式同时约束宽高并写回比例；形状调整模式保留字号，按换行设置调整高度或宽高，输入、格式及查找替换与几何共用精确历史。实现归 [`text-frame.mbt`](../modules/formats/src/pptx/text-frame.mbt)和 [`text-resize.mbt`](../modules/formats/src/pptx/text-resize.mbt)，边界归[格式合同](references/formats.md#pptx)。

基础文字格式已接通字体、字号、粗体、斜体、RGB 颜色、单下划线、单删除线、纯色高亮及清除高亮、上/下标及恢复基线，以及段落左/中/右/两端对齐。文字范围只修改选中字，对象模式作用于所选框；光标和空段落的格式用于后续原生输入。核心按需拆分 run，保留范围外内容和属性，格式与文字共用精确历史。装饰及两端对齐沿公共行绘制输出到 Canvas 和 PDF，保留形状的框内裁剪。默认面板显示混合值，各字段保留普通命令期间的草稿。两端对齐的五项定向核心和两条 Chromium 流程已检查中间/末行、字形位置、原生草稿、源片段、精确历史、无操作、重开输入及 PDF。实现归 [`text-format.mbt`](../modules/formats/src/pptx/text-format.mbt)和 [`text-format-properties.mbt`](../modules/formats/src/pptx/text-format-properties.mbt)，接口和剩余边界归[格式合同](references/formats.md#pptx)。

段前/段后间距、行距、左/右/首行缩进和 LTR/RTL 段落方向已接通核心、API 与默认面板。段距支持点值或百分比，行距支持固定点值或百分比；所涉段落和多框共用一次源事务。方向沿继承读取，切换时镜像左右对齐，清除直接格式恢复继承。双向文字、缩进、光标、适配、Canvas 和 PDF 使用同一核心排版，缓存区分显式基础方向。查询区分混合值与保护原因，保留非目标段落及字符内容。实现归 [`paragraph-format.mbt`](../modules/formats/src/pptx/paragraph-format.mbt)和 [`paragraph-properties.mbt`](../modules/formats/src/pptx/paragraph-properties.mbt)，单位与边界归[格式合同](references/formats.md#pptx)。

清除字符和段落直接格式已接通核心、API 与默认面板。字符清除恢复父级字体属性，保留高亮、语言和链接；段落清除恢复对齐、行段距、缩进及项目符号定义的继承，保留级别与默认字符属性。局部范围、光标后续输入、空框和多框共用精确历史。实现归 [`text-clear.mbt`](../modules/formats/src/pptx/text-clear.mbt)，具体属性及保护归[格式合同](references/formats.md#pptx)。

字符项目符号和十六种常用编号（数字、大小写字母/罗马数字的句点、括号变体及无标点数字）已接通核心、API 与默认面板，支持移除列表、起始值、级别、混合范围和多框事务。标记参与公共段落布局、换行、适配和 PDF，原生换段后按级别续号。源属性、继承与精确历史共用既有事务；实现归 [`list-properties.mbt`](../modules/formats/src/pptx/list-properties.mbt)。标记字体、点值/百分比大小、RGB 颜色及恢复正文样式已接通核心、API 和默认面板，沿同一源事务、字体预检、适配及 Canvas/PDF 输出。继承定义、未选段落和字符保持；源扩展及失败原子保护。实现归 [`list-style.mbt`](../modules/formats/src/pptx/list-style.mbt)，接口与边界归[格式合同](references/formats.md#pptx)。更多装饰、其他地区编号类型及图片符号继续实施。字体键与授权字体 profile 继续由核心解析和宿主供应，不引入 DOM 度量。

内边距、垂直锚定、溢出和自动适配是框属性。现有三种适配模式共用核心排版、源几何和保存属性；更广方向和多栏继续扩展。字面查找替换已接通跨页/框的有界结果、当前页/全部页及大小写/全词选项，支持隐藏页定位、单个/全部替换、格式保留及一项跨页精确历史。默认面板与宿主绑定文档和 revision；核心重查目标，保护或失败保留全部页面。实现归 [`search.mbt`](../modules/formats/src/pptx/search.mbt)和 [`search-replace.mbt`](../modules/formats/src/pptx/search-replace.mbt)，范围和预算归[格式合同](references/formats.md#pptx)。

表格保留行列网格、跨度、单元格文本和样式；行列增删/合并/拆分使用自身的 DrawingML 序列化。可以复用文字/边框布局计算，但不照搬 DOCX 分页表格模型。表格在一页内布局，溢出给出明确结果，不自动创建新页。表格选区及文本光标继续由核心返回。

### 4.3 图表、SmartArt、公式与审阅

图表复用已交付的系列/轴/绘制和 XLSX 数据读写，PPTX 负责对象、关系与嵌入工作簿。修改数据同步系列缓存和显示；复制页不得让两个原本独立编辑的数据表误共享可变状态。

SmartArt 模板在核心展开为可编辑形状组、文本和连接线；明确保存为这些对象。原生 diagram 导入编辑留到 P14，不删除原文件中的 diagram 部件来冒充完成。公式复用 P10 数学结构/布局并写回适用的 DrawingML/OMML；艺术字先使用已支持的文本和填充效果，复杂变形单列兼容差距。

本地顶层形状、图片、组及可编辑文字范围的点击链接已接通核心、API 和默认面板。支持创建、修改、移除外部 HTTP/HTTPS/mailto 地址、内部页目标及首页/末页/上一页/下一页动作；文字支持跨样式/段落选区、混合链接统一修改、光标修改完整链接及后续输入继承。保留文字、格式、几何、提示及悬停信息，并复用精确多部件历史。页移动、复制和删除沿既有引用事务保持目标；四种动作由核心按当前编辑页序解析，包含隐藏页，在首尾停留。默认面板显式打开外链或调用 `followHyperlink()` 定位，导航不改源或历史，不自动请求外链。带组链接时保护取消组合，移除后可继续。放映相关动作与输出链接仍待实现，当前合同归[对象超链接](references/formats.md#对象超链接)。备注、批注/回复、作者与日期/页码/页脚分别维护部件和继承；本地批注不依赖协作服务，作者信息由宿主显式提供。

## 5. 放映、动画与媒体

### 5.1 核心与宿主边界

放映是基于已提交文稿 revision 的临时会话，包含当前页、触发步骤、逻辑时间和播放状态。开始前结束/取消文字或变换候选。播放本身不修改文档、历史或保存基线；修改动画属性才是文档事务。

| 核心拥有 | Web 宿主拥有 |
| --- | --- |
| 页序、隐藏页、链接动作、动画目标、触发/时长/延迟/重复、当前显示状态 | 键盘/指针、时钟与帧调度、全屏、媒体设备、焦点和释放 |
| 输入时间与事件后生成确定的图元/变换/透明度/裁剪和媒体动作 | 使用 R0 执行图元，按动作控制音视频并回报结束/失败 |
| 动画 XML 读写、支持范围和未知效果诊断 | 展示诊断与恢复入口，不解释 OOXML 动画树 |

一个帧请求携带当前逻辑时间和待处理事件，返回本帧有变化的显示状态；不能逐对象发 Worker 请求。渲染忙时 Web 合并后续时间，保留必要触发事件，不累积所有过期帧。时钟不能进入排版算法，核心在同一输入下给出同一结果。

### 5.2 首批播放范围

页面切换先交付直接切换、淡入淡出和推入；对象动画先交付出现/消失、淡入淡出、飞入/飞出、缩放/旋转及线性路径。触发覆盖点击、与上一项同时、上一项之后，支持延迟/时长和有界重复。编辑面板保存顺序和目标 ID，属性由核心校验，不映射成一组任意 CSS 类名。

切换目标页只准备当前和必要的相邻页面资源，退出时释放。跳页/后退按规则重置步骤；暂停恢复基于逻辑时间，避免恢复后突然播放完全部动画。隐藏页默认跳过，内部跳转可明确到达隐藏页；行为按参考规则声明。

R0 已支持的矩阵/路径/裁剪继续复用。确实缺少组合透明度等显示原语时，在通用绘制类型、执行器与必要输出方一起补齐；不能在 React 中重建对象来做动画。复杂效果和 PowerPoint 动画兼容留到 P14，未支持效果显示诊断，不冒充精确还原。

### 5.3 媒体与演讲者界面

音视频插入保存媒体类型、源字节/关系、poster、位置与播放属性。核心管理对象和播放动作；Web 通过浏览器媒体能力解码与播放。媒体默认使用显式提供的字节，不自动下载文件中的外链。实现时按实际支持的编码声明范围，不能把“扩展名可选”当成可播放。

浏览器拒绝自动播放时保留可点击播放入口；未支持编码或解码失败显示对象级错误，其他页面仍可操作。媒体结束、暂停和停止事件绑定放映会话与对象身份，过期事件不能推进新文稿。退出放映、切换文件和释放均停止媒体、撤销对象 URL 并停止时钟。媒体有独立的输入/累计资源预算，不能借图片预算无限接收视频。

演讲者视图首批在当前浏览器页面提供当前页、下一页、备注和计时。放映临时画笔属于播放状态；需要保留到文件时通过明确的“保存为墨迹”文档操作处理。退出恢复编辑选区和焦点。跨窗口控制与桌面多屏能力不作为本阶段前置条件。

## 6. SDK、UI、导入与输出

沿 `PptxCommand` / `execute` 增加操作族，Web 编辑宿主提供类型明确的方法。下表是计划合同，不是已发布 API。

| 操作族 | 最小内容 |
| --- | --- |
| 创建与页结构 | budget、页/版式身份、位置及名称；返回页序和有效选择 |
| 对象与几何 | revision、对象集合、操作/属性及坐标空间；复用已有候选 ID 和一次历史 |
| 主题/母版/内容 | 明确编辑范围与部件身份；返回受影响页面和所需资源/字体 |
| 动画编辑 | revision、页/对象身份、受支持的效果、触发与参数；不接受任意脚本 |
| 放映控制 | 开始/结束、导航/触发、逻辑时间与媒体反馈；绑定文稿 revision，返回显示状态与动作 |

P9 shell 增加页标签菜单、插入、文本/形状/图片、母版、动画和放映控件，按格式职责拆分面板。对象列表、原生输入和无障碍节点保持稳定；面板与 Canvas 使用同一个核心选择，组合期间不切换编辑目标。纯 UI 状态仍在 React，文档参数经现有队列提交。

放映从编辑宿主串行切入，期间停止普通编辑，避免在同一 client 并发请求。自定义 UI 通过相同控制方法使用放映，无需导入 React。退出后复用编辑表面和 P9 订阅，不重新打开源文件。

插入其他 PPTX 页面使用两个有界源会话，核心复制明确的部件闭包并重映射身份、关系和内部链接，保留需要的主题/母版。无法解释的跨文稿引用拒绝导入并保留目标文件；不通过只复制 slide XML 产生缺图或缺母版的文件。

静态 PDF/图片/打印基于已提交的编辑布局，忽略播放时的暂态变换，不推进动画。媒体用明确的 poster/占位与静态输出说明；动态内容不能声称已嵌入静态 PDF。原格式保留已支持的动画/媒体与未知源内容，PDF 导出不确认 PPTX 已保存。各输出继续受页/对象/图元/资源与字节预算限制。

## 7. 参考依据与足够检查

| 参考 | 用途 |
| --- | --- |
| [GenOffice 页面操作][gen-slides]、[播放实现][gen-animation] | 核对页面、动画、触发和媒体的用户能力；其中效果近似不作为 Office 算法标准 |
| [ONLYOFFICE Presentation][oo-presentation]、[Slide][oo-slide] | 页面复制/移动、版式/母版与对象的首要实现入口；已核对页重排中的历史及身份处理 |
| [ONLYOFFICE CommonController][oo-controller] | 核对层次按对象序列移动、相邻操作到达边界即停止的规则 |
| [LibreOffice PPTX 输出用例][lo-pptx] | 次要参考；已阅读占位符身份在输出中保留的检查，不用“形状看起来一样”代替继承验证 |

每批选择能证明新操作的输入，复用既有 PPTX/P9 功能流程和资源上限；不预设全效果、全编码或全动画矩阵。

| 改动风险 | 足够检查 |
| --- | --- |
| 页/对象增删复制 | 核对新旧身份、链接/关系、选择与撤销；保存重开后仍可编辑，失败不留下半个部件 |
| 多选、组合与继承 | 一组含旋转/翻转的对象验证组合前后几何；母版/版式修改影响正确页面，局部覆盖仍保留 |
| 文本与复合对象 | 本批格式/表格/图表/公式的内容、布局和输出；嵌入数据修改后系列缓存一致 |
| 播放状态 | 对实际交付效果检查触发顺序、暂停/恢复、跳页与重复；文稿 revision 和保存内容不被播放改变 |
| 媒体/生命周期 | 自动播放被拒、解码失败或旧事件晚到时仍可退出；停止后无遗留媒体、帧任务或失焦 |
| 新 UI/输出 | Chromium 中完成该操作与相关输入法/焦点路径；静态输出与播放暂态分开，导入失败保留目标文件 |

实现时运行受影响核心与 TS 检查、公开构建和定向保存重开。模型语义优先用 ONLYOFFICE 的规则与独立输出核对，LibreOffice 为补充。颜色、菜单布局和控件样式直接审阅；不新增逐控件截图、Windows/PowerPoint、多浏览器或性能专项验收。

各批分别更新 G3 和格式合同。P0 范围均有可用的核心/API/UI/保存与必要检查后才完成 P12；第一批完成、仅有动画 XML 或能导出静态 PDF 都不足以代表整阶段交付。完成后精简并移入 `implemented/`，同步索引与链接。

[gen-slides]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/pptx-ops/src/ops/slide-ops.ts
[gen-animation]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/renderer/animation-play.ts
[oo-presentation]: https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js
[oo-slide]: https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js
[oo-controller]: https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js
[lo-pptx]: https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sd/qa/unit/export-tests-ooxml1.cxx
