# PPTX 视图、设计与页面导入

[格式合同目录](../formats.md)

## PPTX

`PptxSession.inputLimits()` 与 `PptxClient.inputLimits()` 返回同一核心限额；`PresentationEditor.inputLimits` 提供当前会话的只读值。`PptxInputLimits` 包含单次字体 `fontBytes`、导入文件 `importBytes`、图片与海报 `imageBytes`、媒体 `mediaBytes` 及 RGBA 注册 `rgbaBytes`。它们表示上限，不表示剩余额度。默认 UI 在读取文件前检查，Client 在解码或克隆前检查，Session 在编码前检查；核心继续执行累计、历史与格式保护。`checkPptxInput(command, limits)` 共用命令结构与字节检查；领域 `checkPptxObjectEdit/checkPptxSlideEdit/checkPptxImportInput` 保留结构、类型与属性值检查，字节上限由完整命令检查处理。

DrawingML 对象编号接受无符号 32 位范围，包括 `0`。重复编号、非整数及越界仍拒绝；幻灯片编号继续受其独立下限约束。C0 的 OLE 原件已通过打开与未编辑源保存，未授予 OLE 外观或原生编辑通过。

文字读取将 `u="heavy"` 与 `sng` 映射为单下划线。纯色 `uFill` 校验后保留原 XML，绘制使用文字色；独立粗细及下划线填色尚未绘制。此行为遵循 [ONLYOFFICE 下划线导入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L9084-L9087)及[未消费填色记录的分支](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L9098-L9195)。未知样式、非纯色填充、扩展描边和非法标记继续保护。实现归 [text-read.mbt](../../../modules/formats/src/pptx/text-read.mbt)。

`PresentationEditor.editSlides({ action: "size", width, height })` 修改全稿尺寸，单位为 pt，每边 1–14400，核心取整到 EMU。默认 UI 提供 16:9、4:3 和自定义宽高。`query.width/height` 返回实际尺寸，`slideSizeReason` 返回保护原因。各轴按新旧尺寸比例缩放全部页面及关联版式、母版的本地位置与尺寸；组的子坐标原点、范围及成员同时缩放。字号、描边宽度、旋转/翻转、对象身份、选择与其他资源保持。该规则依据 [ONLYOFFICE Presentation.changeSlideSizeFunction](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L805-L850)、[Shape.changeSize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L3235-L3266)和 [GroupShape.changeSize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L789-L805)。

尺寸、页面和设计部件合为一次有界历史。相同实际尺寸不新增历史；旧 revision、活动候选、保护、坐标越界和输出/历史预算失败原子拒绝。已知表格和图表框随页面缩放，表格列宽与行高按轴缩放；未知页面对象、变换坐标和未支持的扩展辅助线保护尺寸调整。原生视图辅助线同步按轴缩放，组不再次重算边界，保留缩放后的子坐标原点。未知部件与原有源片段保留。保存重开及 Canvas/PDF 使用相同的新尺寸和几何；反复改变比例可能产生 EMU 或辅助线坐标取整，撤销恢复原始源字节。

不可见的文字轮廓 `a:ln` 保留原 XML，正文可读取并沿现有格式编辑。节点须无属性、注释或处理指令，文字只含空白；接受空节点或唯一的空 `a:noFill` 子节点。ONLYOFFICE 的 [CLn 初始状态](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L7608-L7621)没有填充，[isVisible](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L7773-L7775)据填充判断轮廓可见性；[noFill 不可见](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L6693-L6695)。C13 第 45 页的独立原生移除控制确认空标签不改变整页绘制。可见轮廓、下划线轮廓及扩展结构仍受保护。

文字 `effectLst` 接受空列表或现有解析器支持的单个 `outerShdw`。核心验证阴影数值、颜色和结构，保留原效果。绘制遵循 [ONLYOFFICE 跳过文字效果记录](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L9112-L9116)，不绘制该文字阴影。记录身份由 [RunProperties 写入](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/RunProperties.cpp#L539-L541)确认。独立原生控制只移除 C13 第 41、42 页十处文字效果，整页 PNG 字节不变。光晕、效果图、扩展标记、缩放或倾斜阴影仍保护。形状阴影继续沿[外阴影合同](pptx-objects.md#pptx-外阴影)绘制。实现归 [text-decoration.mbt](../../../modules/formats/src/pptx/text-decoration.mbt)及上述读取入口。

对象的 `a:fontRef` 按字符格式链选择主题字体，覆盖较低优先级的母版或文稿字体。直接声明的对应文字脚本字体保持优先。主字体和次字体分别解析拉丁、东亚及复杂文字。行为依据 [ONLYOFFICE shapeTextStyle](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L3010-L3015)及[样式合并](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L3068-L3080)。实现复用上述文字读取入口。

### 幻灯片辅助线

`PresentationEditor.editSlides({ action: "guides", visible, items })` 修改文稿的原生视图辅助线。同步 Wasm/Worker 使用相同的 `editPptxSlides` 命令；核心使用 `SlideEdit::Guides`。`PptxQuery.guides` 返回 `{ visible, items, reason }`。`PptxGuide` 为 `{ orientation: "horz" | "vert", position: number }`，`position` 从页面顶部或左侧起算，单位为磅。`PptxGuide` 和 `PptxGuides` 从 `wasm/pptx` 与 `web/pptx` 导出。

一次命令提交完整列表与显示设置，最多 64 条。核心将有限位置取整到 1/8 磅，原生 `pos` 保持有符号 32 位整数，允许页面外的位置。默认面板可新增水平或垂直线、修改位置、移除单线或清空；新增从页面中点开始，同向后续线向后偏移 12.5 磅并限制在页面边界。面板草稿须显式应用。编辑 Canvas 以虚线显示，隐藏保留列表；放映及静态 PNG/JPEG/PDF 使用内容布局，不包含辅助线。

写回只改 `viewProps` 中的 `slideViewPr/cSldViewPr` 显示属性与 `guideLst`。缺少视图部件时创建标准部件、关系和内容类型，合为一项精确历史。其他视图设置、吸附属性、外围注释、页面内容、选择和对象身份保留。页面改尺寸时，水平位置按高度比例、垂直位置按宽度比例一起缩放。相同实际值无操作；旧 revision、活动候选/放映、修改保护、歧义或外部视图关系、未知辅助线结构或范围内注释及资源失败整体拒绝并保留原包。

编辑 Canvas 已支持拖动。已选对象及其尺寸手柄优先，其他位置按 4 个屏幕像素的容差查找辅助线；交叉或重叠时选择源顺序最后的一条。`beginGuidePptx` 接收 `{ revision, x, y, tolerance }`，核心未命中或辅助线隐藏时返回无候选的当前查询；命中则返回既有 `candidateId`。后续使用 `dragPptx` 的相对指针位移和 `handle: 0`，只改变水平线的纵坐标或垂直线的横坐标，在页面边缘按原生精度取整。横向移动水平线、纵向移动垂直线以及零位移均不改位置。

拖动预览只更新候选及 `guides.items`，保持 revision、原生源和历史。`cancelPptx` 或默认输入的 Escape/指针取消恢复原值；`finishPptx` 复用既有提交、预算和精确历史，成功移动只新增一项。活动候选期间，保存、结构修改及其他编辑继续沿既有保护。普通数值面板仍提供键盘可操作入口。移动与边界规则参考 [ONLYOFFICE CGuideTrack](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/MoveTracks.js#L954-L1025)。候选实现归 [`guide-gesture.mbt`](../../../modules/formats/src/pptx/guide-gesture.mbt)，平台指针队列归 [`presentation-pointer.ts`](../../../packages/pptx/src/web/presentation-pointer.ts)。

对象移动和角点缩放已支持吸附辅助线及其他对象。移动按各叶对象的四个变换后角点与中心计算，整组使用成员点，多选使用全部所选点。缩放使用所拖角点；组内对象和多选框沿同一世界坐标计算，再回到原有父坐标变换。目标取当前源部件的未选叶对象，同样使用变换后四角与中心；所选组的全部成员排除，普通视图不使用继承的母版/版式对象。旋转、翻转、嵌套组和无宽/高直线沿已有几何。两个轴各取容差内绝对距离最小的修正，等距保留先遇到的移动点，再按目标源顺序保留；对象目标先于等距辅助线。目标排序并二分查找，避免多选逐点全配对。某轴位移为零时保持该轴，最小尺寸、文字适配和资源限制继续生效。

对象间吸附缺省开启；导入视图 `cSldViewPr.snapToObjects="0"` 时关闭，未知属性值不用于对象吸附。辅助线继续独立参与计算。对象拖动不改写视图设置、目标对象或其资源，Alt 仍提供自由定位。网格与永久设置、动态对齐标记见下文。

`dragPptx.tolerance` 沿用页面磅值，缺省为 0，不吸附。默认指针使用 6 个屏幕像素换算的容差，按住 Alt 或在释放时保留 Alt 则传 0；预览队列和最终指针位置保留修饰键。键盘移动、数值变换仍按明确坐标定位。隐藏只控制辅助线显示，已有位置仍可吸附；清空列表移除这些目标。未知辅助线保留原源，不参与吸附，其原因继续显示于 `guides.reason`。取消、一次提交、精确历史和保存重开共用原有对象事务，辅助线部件不因对象吸附而改写。

取点与最近距离依据 [ONLYOFFICE calculateSnapArrays](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L733-L746)、[最近点](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L10510-L10557)及[移动轴修正](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/States.js#L1633-L1736)。实现归 [`object-snap.mbt`](../../../modules/formats/src/pptx/object-snap.mbt)。默认辅助线列表有高度上限并可滚动，避免大量条目占满编辑区。

位置换算及新增规则参考 [ONLYOFFICE ViewPr](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/ViewPr.js#L441-L452)、[新增](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/ViewPr.js#L576-L618)及[缩放](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/ViewPr.js#L774-L781)；原生部件结构参考 [ONLYOFFICE CSldViewPr](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/ViewProps/CSldViewPr.cpp)。实现归 [`guides.mbt`](../../../modules/formats/src/pptx/guides.mbt)与 [`pptx-guides.tsx`](../../../packages/pptx/src/react/pptx-guides.tsx)。母版/版式的扩展辅助线及备注辅助线继续实施。

### 动态对齐标记

对象移动或角点缩放命中其他对象时，`PptxGeometry.snapLines` 返回临时对齐线。每项复用 `PptxGuide` 的 `{ orientation, position }`，位置为页面磅值；未命中、Alt/`tolerance: 0` 或非对象变换时返回空数组。默认 Canvas 用独立颜色的虚线绘制，复用辅助线绘制路径。标记仅属于当前候选，不写入视图部件、文稿历史或内容布局。

核心沿已选叶对象的四角/中心及活动缩放角点取目标，保留与最终吸附修正在原生 EMU 精度内一致的对象位置；等距目标仍按原有规则选择。每个方向去重并最多保留 64 条，顺序沿移动源点采样。返回前核对实际候选的世界坐标，最小尺寸或其他预览约束使对象未到达目标时隐藏该线。来源为已有辅助线或网格的吸附不额外生成对象标记，零位移轴保持无标记。多选、整组、旋转及嵌套成员沿同一规则。

后续拖动样本重新计算标记；明确数值变换、取消、提交、撤销重做及重开不保留它们。布局身份与现有选择几何共用，Web 只执行核心返回的位置，不重算吸附。源及历史继续使用原有候选事务，放映和静态输出沿内容布局。取点、同位移目标及辅助线排除依据 [ONLYOFFICE MoveState](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/States.js#L1633-L1774)，显示入口依据 [DrawVerAnchor/DrawHorAnchor](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/DrawingDocument.js#L2793-L2832)。实现归 [object-snap.mbt](../../../modules/formats/src/pptx/object-snap.mbt)、[hit.mbt](../../../modules/formats/src/pptx/hit.mbt)及 [presentation-canvas.ts](../../../packages/pptx/src/web/presentation-canvas.ts)。

### 等间距吸附与提示

对象移动支持在两侧邻居之间居中，或延续同侧已有的对象间距。核心使用选区整体的世界外框，在另一轴投影有正重叠的同父本地对象中找最近邻居；整组按外框参与，选中对象及其成员、继承对象不作为邻居。多选共同平移，组内成员沿原有父坐标转换。候选使用既有屏幕像素容差：对象边缘/中心和辅助线优先，未命中的轴再尝试等间距，最后回退到网格。等距离时保留居中、左/上延续、右/下延续的稳定顺序。

`PptxGeometry.snapSpacing` 返回零至四项 `PptxSpacing`：`{ axis: "x" | "y", from, to, at }`。横向箭头从 `(from, at)` 到 `(to, at)`，纵向从 `(at, from)` 到 `(at, to)`；坐标为页面磅值，每轴成对显示。返回前用实际候选外框重查相等间距，量化、约束或页面外位置不符合时隐藏箭头。默认 Canvas 只在选择覆盖层绘制双向箭头，源、内容布局、放映和静态输出沿原路径。

等间距沿 `snapToObjects` 开关。角点缩放、零位移轴、Alt/`tolerance: 0` 和明确数值变换不使用该吸附；取消、提交、历史操作和重开清理提示。没有新增命令或保存设置。外框和间隔沿已有分布几何，参考 [ONLYOFFICE distributeHor/distributeVer](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L9484-L9585)。交互依据本地 GenOffice 的 `snap.ts` 与 `SlideCanvas.tsx`；核心独立实现有界邻居扫描，不复制其引擎。实现归 [spacing-snap.mbt](../../../modules/formats/src/pptx/spacing-snap.mbt)、[object-snap.mbt](../../../modules/formats/src/pptx/object-snap.mbt)及 [presentation-canvas.ts](../../../packages/pptx/src/web/presentation-canvas.ts)。同尺寸提示归[缩放同尺寸吸附与提示](#缩放同尺寸吸附与提示)，扩展辅助线仍按 P12 实施。

### 比例缩放手势

按住 Shift 拖动对象角点时，核心保持初始框的宽高比。单张图片或仅含图片的多选默认保持比例；普通形状、整组及混合多选在未按 Shift 时沿独立宽高缩放。组内成员使用原有父坐标转换，未启用中心缩放时，旋转和翻转保持相对角点。多选以原选择框的统一比例缩放成员，最小尺寸沿原有约束。零宽或零高的选择框保留既有退化轴规则。

低层 `dragPptx` 增加可选布尔值 `shift`，缺省为 `false`；MoonBit 使用 `Session.drag(..., shift=true)`。指针合并预览和最终释放各自传递当前修饰键。比例约束优先于全部吸附，清理临时对齐线、间距箭头和同尺寸标记；Alt 关闭吸附并启用[从中心缩放](#从中心缩放)，不取消比例约束。移动、连接线端点和明确数值变换继续使用既有操作规则。没有新增文稿设置，取消、单次提交、精确历史与重开沿原候选事务。

缩放系数取两个尺寸绝对值系数中的较大值，依据 [ONLYOFFICE ResizeTrackShapeImage.resize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L634-L689)。图片默认比例和比例优先于吸附的交互对照本地 GenOffice `SlideCanvas.tsx` 的 `ratioLocked` 与 `boundBoxFunc`。实现归 [object-snap.mbt](../../../modules/formats/src/pptx/object-snap.mbt)、[object-selection.mbt](../../../modules/formats/src/pptx/object-selection.mbt)及 [presentation-pointer.ts](../../../packages/pptx/src/web/presentation-pointer.ts)。中心手势归[从中心缩放](#从中心缩放)，跨边方向归[跨边缩放与翻转](#跨边缩放与翻转)。

### 从中心缩放

角点缩放时按住 Alt/Option，保持初始框的中心；非 Mac 的 Ctrl 也启用同一约束。移动时 Alt 继续自由定位。低层 `dragPptx.center` 为可选布尔值，缺省 `false`；MoonBit 使用 `Session.drag(..., center=true)`。指针合并预览和最终释放分别传递当前状态，松开后回到原相对角点规则。Alt/Option 继续同时关闭吸附，不关闭 Shift 或图片默认比例。

核心将活动角点在框坐标中的位移乘二，再沿现有旋转/翻转和父坐标计算中心锚点。普通形状、图片、整组及同父多选/成员共用既有候选与源事务；多选以原选择框中心统一变换。可与比例、最小尺寸、组边界、连接对象更新、取消、单次提交及精确历史共同使用。单条直线沿 ONLYOFFICE 的既有端点规则忽略中心约束；移动、连接线端点和明确数值变换保留原行为。文字和表格最终尺寸继续受既有自动适配约束。

独立使用 `center=true` 且保留容差时，对象尺寸匹配按活动边的屏幕位移判断；完整宽高改变量为边位移的两倍。匹配后继续固定中心，其他轴复用原有网格/边缘/辅助线规则。实际几何仍由核心复核；比例约束优先于全部吸附。没有新增文稿设置或保存状态。

位移系数与中心位置依据 [ONLYOFFICE resizeRelativeCenter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L1019-L1120)。默认修饰键对照本地 GenOffice `SlideCanvas.tsx` 的 `centeredScaling` 与 Alt/Option 交互。实现归 [object-snap.mbt](../../../modules/formats/src/pptx/object-snap.mbt)、[object-selection.mbt](../../../modules/formats/src/pptx/object-selection.mbt)、[size-snap.mbt](../../../modules/formats/src/pptx/size-snap.mbt)及 [presentation-pointer.ts](../../../packages/pptx/src/web/presentation-pointer.ts)。跨边方向归[跨边缩放与翻转](#跨边缩放与翻转)。

### 跨边缩放与翻转

角点越过固定对边时，核心保留有向宽高；负值转为正尺寸，并切换对应的原生翻转位。普通缩放保持原相对角点，中心缩放保持原中心。预览始终基于手势起点，拖回原侧时恢复原方向，不累计翻转。Shift 与图片默认比例按尺寸绝对值取统一系数；接近零时沿既有最小框约束，直线保留允许的零宽或零高轴。

普通形状、图片、整组及同父多选/成员沿同一候选。多选反射各成员中心；奇数次轴反射同时反向成员旋转角，继续使用既有非等比缩放规则，不生成剪切。原生表格继续限制翻转；缩到单元格边距以内时按原规则原子拒绝。连接线端点仍使用原端点手势。

同尺寸吸附匹配跨边后尺寸的绝对值，再换回带方向的角点位移，保留原有容差、优先级与实际几何复核。数值变换继续接受正尺寸并从原源重算。源写回共用原生 `rot/flipH/flipV` 变更，位置和尺寸不变而仅方向变化时，也提交一次精确历史；取消、撤销重做、图片字节和其他部件沿原事务保留。

尺寸符号、翻转与固定点依据 [ONLYOFFICE ResizeTrackShapeImage.resize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L690-L760)及 [resizeRelativeCenter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L1045-L1120)。实现归 [object-snap.mbt](../../../modules/formats/src/pptx/object-snap.mbt)、[object-selection.mbt](../../../modules/formats/src/pptx/object-selection.mbt)、[editing.mbt](../../../modules/formats/src/pptx/editing.mbt)、[geometry.mbt](../../../modules/formats/src/pptx/geometry.mbt)及 [object-arrange.mbt](../../../modules/formats/src/pptx/object-arrange.mbt)。没有新增命令、文稿设置或宿主数学。

### 缩放同尺寸吸附与提示

单个未旋转的本地顶层对象在角点缩放时，可匹配其他本地顶层对象的原生框宽或高。普通形状和整组沿现有变换；图片、连接线、组内成员、多选及带旋转/倾斜的活动框继续使用既有缩放规则，不参与尺寸匹配。匹配按现有屏幕容差换算到框坐标，各维度取最近值，等距保留目标源顺序。只处理有位移的轴，保持对边和相对角点。已匹配尺寸的轴优先于网格与边缘/辅助线，其他轴沿原规则处理。

`PptxGeometry.snapSize` 返回零至 64 项 `PptxSizeMatch`：`{ object, width, height, outline }`。`object` 为目标身份；两个布尔值说明哪些原生尺寸与实际候选相等，至少一项为真；`outline` 是目标四角的页面坐标。相同目标合并成一项，按源顺序保留。核心在返回前重新检查实际尺寸，量化或预览约束不再匹配时隐藏提示。Canvas 仅在选择覆盖层描绘目标的虚线外框，不重算匹配和几何。

尺寸匹配沿 `snapToObjects` 开关；Alt/`tolerance: 0`、明确数值变换及候选结束清理标记，取消、提交、历史和重开保留原有源事务。没有新增命令或保存设置；提示不进入文稿内容、放映或静态输出。比例手势归[比例缩放手势](#比例缩放手势)，更广旋转/组内尺寸匹配继续实施。坐标转换和固定点沿 [ONLYOFFICE getResizeCoefficients](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L2212-L2312)及既有核心变换；交互对照本地 GenOffice `SlideCanvas.tsx` 的同尺寸边框提示。实现归 [size-snap.mbt](../../../modules/formats/src/pptx/size-snap.mbt)、[object-snap.mbt](../../../modules/formats/src/pptx/object-snap.mbt)、[pptx-view.ts](../../../packages/pptx/src/core/pptx-view.ts)及 [presentation-canvas.ts](../../../packages/pptx/src/web/presentation-canvas.ts)。

### 网格与吸附设置

`PresentationEditor.editSlides({ action: "snapping", grid, objects, spacing })` 同时修改网格开关、对象间吸附开关和统一间距。同步 Wasm/Worker 使用既有 `editPptxSlides`，核心使用 `SlideEdit::Snapping(SnapSettings)`。`query.snapping` 返回 `{ grid, objects, spacing, reason }`；对象开关同时控制等间距和同尺寸吸附。类型 `PptxSnapSettings` 和含原因的 `PptxSnapping` 从 `wasm/pptx` 与 `web/pptx` 导出。默认面板提供这三项设置和显式应用，普通对象或文字编辑保留未应用草稿。辅助线吸附独立于两个开关。

`spacing` 单位为磅，接受 1 EMU（1/12700 磅）至 144 磅，并按整数 EMU 保存。网格缺省关闭，对象间吸附缺省开启，默认间距为 360000 EMU。沿 ONLYOFFICE 使用原生 `gridSpacing.cx` 作为两轴间距；导入超大单位按其 1000 倍修正规则读取。只改开关时保留原 `cx/cy`，明确修改间距才将两者设为同值。写回保留未知属性、辅助线内容、其他视图源和全部页面；缺少视图部件时创建关系及内容类型，设置与必要源变更只提交一次精确历史。旧 revision、活动候选/放映、保护、无效参数及资源失败保留原包。

网格以页面中心为基准，使用原生 EMU 换算和就近取点。移动按活动对象的世界外框左上角定位；多选共同平移，组内对象沿原有父坐标转换。每个方向先找容差内的对象或辅助线，再尝试[等间距](#等间距吸附与提示)，仍未命中时落到最近网格。自由比例的角点缩放先匹配[原生尺寸](#缩放同尺寸吸附与提示)，未匹配的轴将活动角点落到网格，再进行对象/辅助线吸附，最小尺寸及文字适配继续生效。位移为零的轴保持；`tolerance: 0`、Alt、键盘及明确数值变换继续自由定位。修改页面尺寸后按新页面中心计算，网格间距保持原生绝对值。编辑网格已有独立显示开关；动态对齐标记见上文。

`PresentationEditor.setGridVisible(visible)` 切换编辑网格，`gridVisible` 返回当前显示值，默认面板提供对应复选框。开关属于当前编辑宿主的临时视图，缺省隐藏；关闭文件后释放，重开重新隐藏。它独立于网格吸附开关，不写入 PPTX，不改变 revision、历史、选择、修改标记或原格式字节。沿现有队列、活动输入及保护条件使用；控件即时显示选择并与外部 API 结果同步，失败恢复实际状态。

低层 `selectionPptx` 可传 `gridScale`，单位为每磅的 CSS 像素数，有限且位于 0.1–16。MoonBit 使用 `Session.selection_geometry(layoutId, grid_scale=Some(scale))` 生成网格；`PptxGeometry.grid` 返回 `{ points, cross }`，未请求时为 `null`。几何绑定已有布局，旧布局拒绝。核心共用原生中心及间距，按上游最小内间隔和主线间隔生成点阵；缩放后使用点或十字。每次最多 16384 点，极细间距或大页面只降低显示密度，保留实际吸附间距和源设置。Web 只绘制这些点，网格、辅助线和选择保持独立绘制状态。放映及静态 PNG/JPEG/PDF 使用内容布局，不包含编辑网格。显示密度依据 [ONLYOFFICE CStrideData.drawGrid](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L1565-L1683)，开关与输出边界依据 [drawViewPrMarks](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L1685-L1713)。

依据为 [ONLYOFFICE 网格间距](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/ViewPr.js#L241-L263)、[CStrideData](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L1512-L1564)、[移动回退](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/States.js#L1738-L1774)与[缩放指针](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/States.js#L1468-L1481)。实现归 [`snapping.mbt`](../../../modules/formats/src/pptx/snapping.mbt)、[`object-snap.mbt`](../../../modules/formats/src/pptx/object-snap.mbt)及共用的 [`view-properties.mbt`](../../../modules/formats/src/pptx/view-properties.mbt)。

页面背景使用 `PresentationEditor.editSlides({ action: "background", value }, slide?)`。`value` 是 `PptxBackgroundFill`：纯色为 `{ kind: "solid", color }`，线性渐变为 `{ kind: "linear", stops, angle, scaled }`，居中圆形径向渐变为 `{ kind: "radial", stops }`。`stops` 含 2–32 项 `{ position, color, opacity }`，颜色均为不带 `#` 的六位 RGB。`null` 移除本页背景并恢复版式、母版继承。`query.background` 返回有效 `value`、本页是否设置 `explicit` 与保护原因 `reason`；没有背景时返回白色纯色。`value` 的查询类型为 `PptxBackground`，还包含下节的图片背景；两个类型均由 `wasm/pptx` 和 `web/pptx` 导出。核心使用 `BackgroundFill`。

色标 `opacity` 须有限并位于 0–1，核心舍入到 1/100000；1 为不透明，0 为全透明。背景以白色页面为底，形状与既有内容合成。位置须有限、位于 0–1 并按非递减顺序排列。核心将位置舍入到 1/100000，写入原生整数位置，不自动排序。同位置色标形成突变，首尾可以位于内部，外侧延续对应端点颜色。`angle` 为顺时针 0–360 度，核心舍入到 1/60000 度并把 360 规范为 0；0 从左至右，90 从上至下。`scaled` 必须为布尔值；true 按页面长宽比调整角度，false 保持实际角度。导入可解析主题/系统颜色、已有明暗及按源顺序计算的 alpha/alphaMod/alphaOff 变换，保留未改源；圆形路径的点与平铺元数据沿下述 ONLYOFFICE 几何读取，其他路径及复杂效果继续保护；图片背景见下节。有效背景随版式/母版继承，复制页与尺寸调整沿相同解析；修改背景不改对象身份或几何。角度规则依据 [ONLYOFFICE getGradientPoints](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/editorscommon.js#L15290-L15511)。

操作复用 revision、候选保护、输出预算和精确撤销重做；本页已有相同有效背景时为无操作。默认面板提供背景类型、色标增删、位置/颜色/不透明度、角度/比例设置和恢复继承；原生文字编辑保留尚未应用的背景草稿。核心复用现有矩阵与水平渐变原语生成任意方向，Canvas/PDF 不解析 DrawingML。定向检查覆盖继承、方向/比例、色标与突变、源保真、历史、重开输入、真实 Canvas 颜色及独立 PDF 渲染颜色，证据归[测试说明](../testing.md)。其他背景与母版编辑仍待实现；主题颜色和字体见下节。修改本页背景的语义参考 [ONLYOFFICE Slide.changeBackground](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L825-L829)，实现归 [`background-fill.mbt`](../../../modules/formats/src/pptx/background-fill.mbt)和 [`slide-background.mbt`](../../../modules/formats/src/pptx/slide-background.mbt)。

### 图片背景

`PresentationEditor.editSlides({ action: "backgroundImage", bytes, mode }, slide?)` 设置或替换本页 PNG/JPEG/GIF 背景，`mode` 为 `stretch` 或 `tile`。Wasm/Worker 使用同一 `editPptxSlides` 命令。输入沿图片写入上限：4 MiB、单边 4096 像素及总计 4 Mi 像素。原图片字节、关系、内容类型和背景源合为一次有界事务；保留对象、选择与非目标部件，支持精确撤销/重做、页面复制及保存重开。重复设置相同本地图片及模式不增加历史，旧资源继续保留，不做包清理。

`{ action: "backgroundImageFormat", mode, crop, opacity }` 一次设置已有图片背景的模式、四边裁剪和不透明度，保留资源键及已有平铺参数。`crop: [left, top, right, bottom]` 为移除源图的比例，各项非负且小于 1；核心按 1/100000 舍入，两侧之和须小于 1。`opacity` 为 0–1，使用相同精度并乘上源像素 alpha。四个零移除裁剪，1 移除常量 alpha 覆盖；本地有效同值不增加历史。`tile` 保留非零裁剪，绘制整张源图；切回 `stretch` 后重新应用原裁剪。平铺沿用已有参数或标准默认值，也可在一次命令中重置裁剪并切换模式。继承图片可创建本页覆盖，继续复用原资源；本地替换只修改图片引用，格式编辑只修改变化的 `stretch/tile`、`srcRect` 和 `alphaModFix`；保留 `dpi/cstate/rotWithShape` 等已识别源属性、已有图片关系和其他部件。`{ action: "background", value: null }` 恢复继承，受支持的纯色/渐变命令也可替换图片背景。默认背景面板提供类型、图片、模式、四边百分比、裁剪重置、不透明度及恢复继承，格式一次应用并进入同一历史；文件读取绑定目标页，读完后检查目标是否改变。

`query.background.value` 的图片分支为 `{ kind: "image", key, crop: [left, top, right, bottom], opacity, mode }`，其余分支为纯色、线性及居中圆形径向渐变。`key` 是核心图片资源身份，`crop` 是非负源裁剪比例，`opacity` 为 0–1。按幻灯片、版式、母版顺序选择背景，并按实际来源部件解析内部图片关系；主题 `bgRef` 也按主题部件解析。导入保留 `srcRect` 和常量 `alphaModFix`，替换图片继续保留这些值；格式候选沿用原资源和整页裁剪，不生成图片副本。缺图片、非法模式/数值、舍入后空源区域、未知源及预算失败保留源、选择和历史。拉伸展开后的宽高各不超过 1e9 pt；平铺的未生效裁剪不参与这个展开检查，切回拉伸时重新验证。

背景先铺白底，再裁剪到整页并使用既有图片图元，前景对象随后绘制。拉伸以有效源矩形覆盖页面；平铺复用[形状图片](pptx-objects.md#形状图片填充)的 96 DPI、缩放/偏移、九种对齐及交替翻转，保留但不应用源裁剪。背景、形状填充和独立图片合计每页最多 65536 格；写入、模式、尺寸及变换候选先验证此上限。背景图片计入全稿 256 项使用中图片及既有字节/历史预算，预览、PNG 和 PDF 使用同一资源清单。目标内缩归[图片目标内缩](pptx-objects.md#图片目标内缩)；外链和未知效果继续保护；不抓取外部图片，也不删除未知源来替换背景。

源矩形复用 [ONLYOFFICE 图片裁剪系数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L946-L960)，读取与绘制顺序参考 [ONLYOFFICE 背景继承](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L1260-L1322)、[背景图片资源](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L1134-L1151)及[背景先于对象绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L1416-L1451)，未复制上游源码。实现归[背景图片](../../../modules/formats/src/pptx/background-image.mbt)、[图片事务](../../../modules/formats/src/pptx/object-image.mbt)和[共用平铺](../../../modules/formats/src/pptx/shape-tile.mbt)。

### 主题颜色

DrawingML `prstClr` 现读取 `black/white`，分别解释为 `000000/ffffff`。背景、渐变、形状、边线、文字及表格复用既有颜色变换和透明度。普通外观修改沿原事务写回，源保存、精确历史及重开保留。未知预设名、大小写错误、额外属性和非空文字仍诊断；其他预设色尚未开放。实现归 [theme.mbt](../../../modules/formats/src/pptx/theme.mbt)，取值依据 [ONLYOFFICE 预设色](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Common/SimpleTypes_Drawing.cpp#L1800-L2005)。

DrawingML 颜色读取支持原生有符号 `hueOff`，单位为 1/60000 度；色相环绕后保持饱和度与亮度。`satMod` 和 `satOff` 修改 HSL 饱和度，结果钳制到有效范围；灰色偏移沿 ONLYOFFICE 的规则。背景、渐变色标、形状、边线、文字和高亮共用颜色解释器，保留源变换和透明度。依据 [ONLYOFFICE CColorModifiers](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L2068-L2249)。未知变换及扩展标记继续保护。

`PresentationEditor.editSlides({ action: "themeColor", slot, color })` 与 Wasm/Worker 的 `editPptxSlides` 修改主题颜色。`slot` 为 `PptxThemeSlot`：`dk1/lt1/dk2/lt2`、`accent1`–`accent6`、`hlink/folHlink`；`color` 为不带 `#` 的六位 RGB，核心规范为小写。普通视图按 [ONLYOFFICE changeColorScheme](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9766-L9798) 的范围，同步修改文稿所有页面实际引用的主题，每个部件仅改一次；不修改未使用的主题。默认面板说明此范围，提供颜色项和颜色选择。

`PptxQuery.themeColors` 返回十二个 `PptxThemeColor`，每项含 `slot/color/reason`。全部使用中主题的有效颜色相同时返回 RGB，混合时返回 `null`；不能安全编辑时给出原因。类型从 `wasm/pptx` 和 `web/pptx` 导出。支持普通 `srgbClr` 和 `sysClr.lastClr`；选择新颜色时写为显式 sRGB，相同有效值保持原系统颜色源。含颜色变换、未知属性/子节点、注释或处理指令的目标色项仍保护；一处受保护即拒绝整次修改。其他色项、字体、额外配色、扩展及未改部件原样保留。

核心重新解析所有依赖页，背景、形状、描边、文字和列表的主题引用继续使用原颜色映射及明暗变换；直接 RGB 覆盖、对象身份、几何和文字选择保持。原生文字草稿先独立提交；主题部件和派生页面共用一次有界历史。撤销/重做重新派生依赖颜色，不只恢复 XML。相同颜色无操作，旧 revision、活动候选、输出/历史预算及保护失败原子拒绝。保存重开和 Canvas/PDF 沿相同布局路径。主题字体见下节；主题包应用、母版/版式直接编辑及复合对象仍按 P12 后续批次实施。实现归 [`theme-edit.mbt`](../../../modules/formats/src/pptx/theme-edit.mbt)及 [`pptx-theme.tsx`](../../../packages/pptx/src/react/pptx-theme.tsx)。

### 主题字体

`PresentationEditor.editSlides({ action: "themeFont", kind, script, font })` 沿主题颜色的全稿使用中主题范围修改字体定义。`kind` 为 `major`（标题）或 `minor`（正文）。`script` 为 `latin/ea/cs`，或区分大小写的四字母脚本代码，如 `Hans/Arab`。`font` 使用实际字体族，最多 200 UTF-16 单元，遵循字符字体的合法性规则；Latin 不能为空，其他类别的空串恢复补充脚本或 Latin 回退。缺少的非空定义按 Latin、EA、CS、补充字体顺序插入，保留扩展和其他文字类别；清除不存在的定义无操作。默认面板可选择已有类别或输入新代码，新增项撤销后面板仍可继续操作。

`PptxQuery.themeFonts` 返回 `PptxThemeFont[]`，每项包含 `kind/script/font/reason`。`font` 为原始定义，跨主题混合时为 `null`；不存在的定义为空串，保护原因独立返回。两种用途合计最多 256 项。新字体和查询类型沿 `wasm/pptx`、`web/pptx` 导出。所有 `editPptxSlides` 请求携带字体 `profile`，Web 编辑宿主自动传入自己的映射。MoonBit 的 `edit_slides` 在字体操作时还须提供 `probe`；其他页面操作不需要字体度量。

提交前按受影响文字的实际字体键预检 profile 和已注册字体，包含粗斜体键；仅修改未使用的类别时不要求加载该字体。核心重新解析依赖页，直接字体覆盖和未受影响内容保持。缩小适配更新比例，形状适配同步本地、继承及组内框的源尺寸；组内尺寸沿父组缩放换回原坐标，零高度框也可重新计算。主题、页面及受影响版式/母版部件合为一次有界历史，撤销/重做同时恢复派生字体和几何，保存重开和 PDF 使用同一结果。

已知字体元数据 `panose/pitchFamily/charset` 保留。目标字体定义的未知属性/子节点、注释、处理指令及重复项仍保护；不能安全适配的源、尺寸锁、缺字体、旧修订、活动候选和预算失败原子拒绝。文字类别划分与语言范围沿现有字体解析，不声明全语言字体一致性。主题字体重排依据 [ONLYOFFICE CTheme.changeFontScheme](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L10662-L10673)，定义顺序参考 [FontCollection](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/FontCollection.cpp#L89-L112)。实现归 [`theme-font.mbt`](../../../modules/formats/src/pptx/theme-font.mbt)，适配复用 [`autofit.mbt`](../../../modules/formats/src/pptx/autofit.mbt)及 [`text-resize.mbt`](../../../modules/formats/src/pptx/text-resize.mbt)。

### 母版与版式编辑视图

`PptxQuery.editView` 返回 `kind: "slide" | "master" | "layout"`、返回普通视图的 `slide`、`choices`、`reason` 和 `operations`。`operations` 的 `rename/addLayout/copyLayout/deleteLayout/deleteMaster/addMaster/copyMaster` 分别返回保护原因，空串表示允许。每项源选择包含 `id/name/kind/master`。目录沿文稿声明的母版及版式读取，包含未被页面使用的源；最多 256 个母版和 256 个版式，目录合计最多 1 Mi UTF-16 单元。未知、重复或归属错误的引用保护整个源目录。

`PresentationEditor.showSlide(part)` 和 `selectPptx.slide` 接受目录中的源部件路径。`query.slide` 指向当前源，`query.slides` 始终只列真实幻灯片。默认页栏的“编辑视图”选择器切换母版、版式与普通页面。当前源的本地对象沿既有文字、外观、几何、组合及图片资源事务编辑；普通视图中的继承对象继续只读，版式视图中的母版装饰也只读。

修改写回源部件并重读引用页面，保留页面直接覆盖。需要重新适配的依赖文字框复用字体度量和原有尺寸锁，源、依赖框、资源和前后选择合为一次有界历史。共享框需要不同尺寸、缺字体或预算失败时整项拒绝。未使用的当前源也检查字体、对象、图片和输出预算。当前源最多 4096 个可见对象，并与实际页面共同遵守现有总预算。

保存和整稿输出始终使用真实幻灯片，当前画布输出可使用所选源。切回页面、精确撤销/重做和重开继续保留源身份与关系。模板提示文字不写入页面用户文字。源视图暂不显示普通页的页序、备注、动画、主题及查找面板。

`editSlides({ action: "masterTextStyle", kind, level, format }, masterPart?)` 编辑目标母版的默认字符格式。`kind` 为 `title/body/other`，`level` 为 0–8；默认面板显示为第 1–9 级。`format` 复用 `PptxTextFormat` 的字体、字号、字符间距、粗斜体、颜色、下划线、删除线、高亮和上下标，按指定属性合并。`format: null` 移除该级 `defRPr`，恢复字符继承，保留段落及列表定义。缺失的 `txStyles`、类别和级别按原生顺序创建，已知元数据在普通修改时保留；扩展属性、注释、未知字体或填充标记保护目标格式。

`editView.textStyles` 返回 `{ items, reason }`。母版视图含三类共 27 项 `{ kind, level, format, reason, paragraph }`，`format` 返回完整有效字符值，字体显示 Latin 槽的解析结果；受保护项返回空格式和原因。`paragraph` 沿 `PptxParagraphFormatting` 返回有效段落、列表和制表位，并增加 `alignment`；其保护原因与字符格式分开。普通页和版式视图返回空目录及切换提示。本地字符、段落、占位符列表样式继续优先于母版默认格式。母版修改按当前母版、所属全部版式、实际页面的顺序重排，包含未使用版式的本地自动框；页面沿更新后的版式尺寸适配。源组边界沿已有归一化更新，保留页面姿态及本地覆盖，源提示文字保持在源部件。字体预检、尺寸锁、几何/资源及输出预算检查共用提交，选择、源和必要框尺寸共用一次精确历史。版式重排实现归 [`layout-reflow.mbt`](../../../modules/formats/src/pptx/layout-reflow.mbt)。实现归 [`master-text-style.mbt`](../../../modules/formats/src/pptx/master-text-style.mbt)，继承顺序依据 [ONLYOFFICE Shape 文本样式合成](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2925-L3000)，未复制上游源码。

普通非占位符文字框按演示稿 `defaultTextStyle` 优先于母版 `otherStyle` 合成字符与段落属性；缺失属性再沿母版回退。占位符与表格保持母版优先，本地字符、段落及列表覆盖继续优先。此顺序依据 [ONLYOFFICE 普通形状与占位符的样式顺序](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L3028-L3076)，实现归 [text-read.mbt](../../../modules/formats/src/pptx/text-read.mbt)。

`editSlides({ action: "masterParagraphStyle", kind, level, format }, masterPart?)` 编辑相同类别及级别的默认段落。`PptxMasterParagraphFormat` 复用段落的缩进、行段距、方向、普通项目符号/编号、标记字体/大小/颜色及制表位，并增加 `alignment: "left" | "center" | "right" | "justify"`。内层 `format.level` 拒绝，级别由外层选择。`format: null` 清除本级已支持的段落直接设置，保留字符定义、级别及其他源片段。标记属性传空值使用正文样式；制表位沿现有继承合并，移除本级定义后恢复上级。

默认面板复用普通段落、列表及制表位控件，修改和清除共用母版事务及精确历史。未知间距、标记、制表位及扩展源保护修改；字符定义中的未知属性在段落修改和清除时保留。新标记字体同样在提交前预检。编号标记继承正文粗斜体，普通项目符号使用常规字形，依据 [ONLYOFFICE MergeTextPr](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/PresentationNumbering.js#L389-L456)。实现归 [`master-paragraph-style.mbt`](../../../modules/formats/src/pptx/master-paragraph-style.mbt)，段落解析与写入复用 [`paragraph-read.mbt`](../../../modules/formats/src/pptx/paragraph-read.mbt)和 [`paragraph-properties.mbt`](../../../modules/formats/src/pptx/paragraph-properties.mbt)。未复制上游源码。

`editObjects({ action: "insertPlaceholder", type, x, y, width, height, text })` 在当前母版或版式插入顶层占位文本框。`type` 使用原生 `title/body/ctrTitle/subTitle/dt/ftr/sldNum/hdr/obj/chart/tbl/clipArt/dgm/media/sldImg/pic`；核心按当前源最大索引加一分配 `idx`，从 1 开始，耗尽 uint32 时拒绝。位置、尺寸和提示文字沿用文本框限制。图表、图片、媒体等类型目前定义槽位标记，资源填入仍受各功能支持范围约束。

`editObjects({ action: "replaceImage", object, bytes })` 也可向单选的空 `pic/obj` 占位框填入 PNG/JPEG/GIF。默认图片面板显示“填入占位图片”。核心转换为原生 `p:pic`，保留对象身份、名称/链接、占位符定义、样式及版式关系；提示文字留在版式。图片按 96 dpi 换算点值，居中并等比适配；小图片不放大，源像素尺寸至少按 1 mm，缩放结果各轴至少 5 mm，沿 [ONLYOFFICE addImages](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L3803-L3852) 的规则。旋转/翻转保持，必要继承几何写为局部框。填入后继续使用普通图片替换、裁剪和透明度。仅含 `noGrp` 的形状锁随填充迁移为同值图片锁。非空文字、其他占位类型、组成员、其他锁或扩展非可视属性、未知外围源继续保护。源图片字节、关系、内容类型和对象转换合为一次精确历史，目标身份变化、输入和预算失败保留文档。实现归 [`placeholder-image.mbt`](../../../modules/formats/src/pptx/placeholder-image.mbt)，复用 [`object-image.mbt`](../../../modules/formats/src/pptx/object-image.mbt) 的资源事务；未复制上游源码。

`editObjects({ action: "fillTable", rows, columns })` 在普通幻灯片的单选空 `tbl/obj` 占位框中创建原生表格。默认表格面板提供“填入占位表格”，对象查询的 `tableFillReason` 返回保护原因。表格沿现有新建格式，继承槽位的有效位置和宽度，行高由字体及单元格内容撑开；不将槽位高度强制分配到各行。保留 `cNvPr` 身份、名称/链接、`nvPr` 占位定义、对象顺序与选择，版式提示和其他部件保持原字节。填入后继续使用原生格输入、表格结构和格式命令。

行数为 1–1000，列数为 1–63，总格数最多 4096；现有列宽、字体、候选、历史和包预算继续执行。文字非空、非目标槽位、组成员、锁定、旋转/翻转、未知外围或扩展内容继续保护；母版/版式视图保留槽位定义入口。表格转换、网格和必要行高共用一次精确历史，失败保留源、选择及身份分配。表格占位符的版式切换与重置沿[幻灯片版式](#幻灯片版式)处理。实现归 [`placeholder-table.mbt`](../../../modules/formats/src/pptx/placeholder-table.mbt)，复用 [`table-create.mbt`](../../../modules/formats/src/pptx/table-create.mbt)与 [`table-structure.mbt`](../../../modules/formats/src/pptx/table-structure.mbt) 的候选及排版；位置/宽度和替换行为参考 [ONLYOFFICE Add_FlowTable](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L4079-L4120)，未复制上游源码。

`editObjects({ action: "fillChart", kind, title, data })` 在普通幻灯片的单选空 `chart/obj` 槽位中填入原生图表。参数复用[基础图表](pptx-objects.md#pptx-基础图表)的六种类型、标题及 TSV 数据规则。默认图表面板显示“填充图表占位符”；对象查询的 `chartFillReason` 返回保护原因。核心复用图表 XML、嵌入 XLSX、关系及内容类型事务，保留对象身份、名称、占位定义、顺序和选择，版式提示及其他部件保持。填入后沿普通数据修改、移动缩放、历史、保存重开和 Canvas/PDF 路径。

槽位须为本地顶层、无文字、无旋转/翻转且至少 180×150 pt。未知/扩展内容、锁、错误槽位及母版/版式视图继续保护。核心采用槽位的有效位置及完整宽高，参考 [ONLYOFFICE finalizeAddChart](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L3935-L3982)。图表资源和替换共用一项精确历史，失败保留文稿、选择及身份分配；整对象复制沿既有占位身份保护。实现归 [`placeholder-chart.mbt`](../../../modules/formats/src/pptx/placeholder-chart.mbt)及 [`chart-edit.mbt`](../../../modules/formats/src/pptx/chart-edit.mbt)，未复制上游源码。

单选本地顶层形状或图片后，`editObjects({ action: "placeholder", value: { type, index } })` 修改定义；`value: null` 移除定义并保留对象、内容与资源。`index` 是 0 至 4294967295 的整数；同源相同类型/索引不得重复，比较时居中标题归为标题。每个查询对象的 `placeholder` 返回 `{ value, reason }`，普通页面可读取定义，修改需进入源视图。已知 `sz/orient/hasCustomPrompt` 保留，未知元数据和形状类型锁保护修改。需要时先固化当前源对象的继承几何；会导致引用页面丢失继承几何的修改仍整项拒绝。源、依赖页、选择与历史沿既有事务提交；默认面板提供插入和定义控件。实现归 [`placeholder-edit.mbt`](../../../modules/formats/src/pptx/placeholder-edit.mbt)，索引分配参考 [ONLYOFFICE NewShapeTracks](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/NewShapeTracks.js#L869-L894)。

`editSlides({ action: "addMaster" }, source?)` 在所选母版后新增空白母版、一个空白版式和独立默认主题；选择版式时使用其所属母版的位置。空白内容复用核心新建文稿的构造。`copyMaster` 接受母版源，保留名称、源设置及全部声明版式的顺序，并独立复制主题；零版式的母版也可复制。对象、字段、creationId、母版和版式身份重新分配，所属关系重映射到副本；图片字节和普通链接继续共享。图表等尚未接通复制归属的可变资源、未声明的版式关系和未知身份扩展保护复制。两项操作选择新母版并清空对象选择，保留真实页面；主目录、关系、主题及所有新源合为一次历史。目录、每个新源的对象/字体/图片、累计历史和包预算在提交前检查，失败保留源、选择和身份分配。默认源管理面板提供相同操作。实现归 [`master-create.mbt`](../../../modules/formats/src/pptx/master-create.mbt)及 [`master-source.mbt`](../../../modules/formats/src/pptx/master-source.mbt)。复制归属与插入位置参考 [ONLYOFFICE MasterSlide.createDuplicate](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/SlideMaster.js#L702-L741)和 [DublicateMaster](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9214-L9253)，未复制上游源码。

`editSlides` 的 `addLayout` 在所选母版下新增空白版式；选择版式时新增到其后。`copyLayout` 在同一母版下复制版式，保留源名称，重映射对象身份并共享图片及链接；图表等尚无复制所有权支持的资源保护复制。`deleteLayout` 仅删除没有页面或其他部件引用的版式，同时移除目录、关系及内容类型，保留共享资源；删除当前版式后选择其母版。`sourceName` 的 `name` 修改母版或版式名称，最多 1024 UTF-16 单元，允许空串，相同名称不产生历史。这些操作复用现有命令、默认源管理面板和部件历史；新增身份在撤销后也不复用，失败保留原状态。实现归 [`source-edit.mbt`](../../../modules/formats/src/pptx/source-edit.mbt)、[`layout-create.mbt`](../../../modules/formats/src/pptx/layout-create.mbt)及 [`layout-delete.mbt`](../../../modules/formats/src/pptx/layout-delete.mbt)。复制与目录操作参考 [ONLYOFFICE Layout.createDuplicate](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Layout.js#L282-L328) 和 [SlideMaster 目录操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/SlideMaster.js#L543-L560)，未复制上游源码。

`editSlides({ action: "deleteMaster" }, masterPart?)` 删除母版及其声明的全部版式，至少保留一个母版。引用页面自动转到声明顺序中的第一个剩余母版，包含隐藏页。版式先匹配显式类型，再按 `matchingName` 或源名称匹配，最后选择首个非标题版式或第一项。需要重绑定而目标母版没有版式时整项拒绝。页面本地对象、文字、身份和直接尺寸保留；失去版式及母版匹配的占位符先写入原有几何，自动框沿新继承重新适配。新字体使用现有 probe/profile 预检。页面关系、必要几何、母版、版式、主目录和内容类型合为一次历史，主题、图片及其他资源保留。当前源属于被删母版时返回原来的真实页面，其他选择保持。默认母版面板提供相同操作和保护原因；没有版式的未使用母版也可删除。未知部件入站关系、页面或主目录中的未知关系引用、对象保护和预算失败原子拒绝。实现归 [`master-delete.mbt`](../../../modules/formats/src/pptx/master-delete.mbt)及 [`master-rebind.mbt`](../../../modules/formats/src/pptx/master-rebind.mbt)。重绑定、匹配和孤立框依据 [ONLYOFFICE ChangeSlideSlideMaster](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9754-L9765)、[getMatchingLayout](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/SlideMaster.js#L324-L400)及 [checkNoTransformPlaceholder](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L2009-L2040)。未复制上游源码。

源视图沿用背景面板。`editSlides` 的 `background/backgroundImage/backgroundImageFormat/backgroundImageInsets` 同样接受母版或版式部件路径，包含未使用的版式。纯色、线性渐变、PNG/JPEG/GIF、裁剪、不透明度、拉伸/平铺和目标内缩复用[既有背景合同](#图片背景)，不新增命令或资源模型。修改只写目标源及必要图片关系/内容类型，重读引用页面；页面和版式的局部覆盖保持。清除版式背景恢复母版，清除母版背景使用白底。格式编辑复用目标源已解析的图片，即使该源不在当前画面中；公开图片读取仍按当前画面及真实页的使用范围保护。背景、资源与选择共同精确撤销，未知源、文稿保护和预算失败原子拒绝。语义依据 [ONLYOFFICE 母版背景事务](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/SlideMaster.js#L530-L534)及[版式背景事务](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Layout.js#L348-L353)，未复制上游源码。

源视图采用 [ONLYOFFICE 的母版模式与依赖对象区分](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L2679-L2703)。实现归 [`page-view.mbt`](../../../modules/formats/src/pptx/page-view.mbt)、[`page-read.mbt`](../../../modules/formats/src/pptx/page-read.mbt)及 [`page-reflow.mbt`](../../../modules/formats/src/pptx/page-reflow.mbt)。

### 幻灯片版式

`PresentationEditor.editSlides({ action: "layout", id }, slide?)` 应用文稿中已有的版式。`id` 是版式部件路径，须来自 `query.slideLayout.choices`；`current` 返回当前页的版式身份，`reason` 返回目录或修改保护原因。每项选择包含 `id/name/master/masterName`，分别表示版式身份/源名称及所属母版身份/源名称。默认面板按名称和母版展示选项。空名称仅在界面使用序号，不改写源。

目录沿 presentation 的母版列表及各母版的版式列表读取，保留声明顺序。最多 256 个母版、256 项版式；目录文字与重复身份合计不超过 1,048,576 UTF-16 单元，源名称最多 1024 单元。未知、重复或归属错误的引用保护目录；其他编辑与原始源继续保留。

核心按占位符类型及数值索引匹配，中心标题与标题共用匹配类别，并沿用单个正文占位符的回退规则。匹配对象保留身份、文字、直接格式、链接和选择，清除受支持的本地几何覆盖，由新版式及母版重新派生位置、尺寸和继承样式。普通本地对象保留原源。新版式缺少的普通标题、正文、内容及副标题占位符生成空的本地文字对象，使用新身份并继承版式；模板提示文字不会写入幻灯片内容。

缺失的 `dt/ftr/hdr/sldNum` 占位符按版式 `hf` 开关插入；缺少版式设置时使用母版设置，两者均无设置时不插入。有效设置中未声明的开关缺省为启用。固定日期和页脚保留已有文字及样式，简单编号域保留源缓存并计算显示值；字段 ID 复用页面复制的分配规则。内容写为本地对象，位置继续继承版式。普通占位符仍清空提示。规则参考 [ONLYOFFICE 占位符复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L776-L800)及[版式/母版页边设置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9158-L9182)，实现归 [`layout-fields.mbt`](../../../modules/formats/src/pptx/layout-fields.mbt)。

没有匹配位置或多个对象争用同一位置时，已有用户内容明确报冲突。仅无文字、可见填充/边框、动作或未知元数据的未匹配占位符可以移除；被计时/连接引用的对象继续保护。缺少时间上下文或未支持的日期域、未知字段、包含关系的页边文字、分组或歧义占位符、未知页边开关/变换，以及导致新增显示诊断或无法解析几何的版式仍保护。新增占位符 XML 合计最多 1,048,576 UTF-16 单元，继续受包、字体、输出及历史预算限制。母版/主题继承可随切换更新，版式和母版本身保持原源。

关系目标、占位符与源变化共用一次精确历史；原生文字草稿先独立提交。选择中失去的继承对象或空占位符会清除，保留对象的文字光标继续有效。相同版式切换是空操作；母版/版式对象编辑归[源视图](#母版与版式编辑视图)，母版和版式的新增/复制/删除及源改名归同一合同。字体总数在候选提交前检查，避免提交后才超出查询的 256 键预算。保存重开、页面复制及 Canvas/PDF 沿相同关系与继承路径。实现归 [`slide-layout.mbt`](../../../modules/formats/src/pptx/slide-layout.mbt)，匹配和几何重置参考 [ONLYOFFICE getMatchingShape](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L390-L522)及 [changeLayout](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L695-L800)。

`PresentationEditor.editSlides({ action: "resetLayout" }, slide?)` 重新应用目标页的当前版式，默认面板提供重置按钮。它清除占位符受支持的本地 `xfrm`，恢复版式/母版几何，并沿相同规则补齐缺失的空占位符。保留已有匹配对象身份、用户文字、字符/段落/框属性及形状外观；普通对象和版式关系原字节保持。行为沿 [ONLYOFFICE 当前版式重置入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9519-L9553)，文字格式清除仍使用既有字符/段落命令。

重置仅在有覆盖或占位符变化时新增一项历史，重复调用不改源或 revision。原生草稿先独立提交，随后可精确混合撤销/重做和保存重开。移动/尺寸锁、实际旋转变化的 `noRot`、未知变换标记、无法继承几何及资源预算失败均原子拒绝；版式切换使用相同候选保护。

匹配的图表占位符支持版式切换与重置，完整采用目标槽位的位置和宽高。现有图表数据、对象身份、占位定义及资源保持；未知/旋转/翻转或小于 180×150 pt 的目标原子拒绝。重复重置不新增历史。

匹配的表格占位符也支持版式切换与重置。核心使用目标槽位的有效位置和宽度，按整数 EMU 比例调整现有列网格；保留行最小高度，并按新宽度重新排版，必要时增高行及原生表格框。槽位高度不压缩已有内容。表格身份、占位定义、格内文字和直接格式保持，源版式及未修改部件保留原字节；关系、列宽、行高和选择共用一次精确历史。重置恢复位置及列宽，重复重置不新增历史。

底层 `Session::edit_slides` 在表格重排时需要已有字体 `probe/profile`；Wasm、Worker 和默认面板沿现有命令传递。目标缺少匹配槽位、含旋转/翻转或未知几何，原表格锁定，列宽无法容纳边距，字体缺失，目标母版引入不支持的表格格式，或预算失败时整项拒绝。已有表格即使文字为空，也不作为可丢弃的空提示框删除。实现归 [`layout-table.mbt`](../../../modules/formats/src/pptx/layout-table.mbt)，列宽及行高复用 [`table-transform.mbt`](../../../modules/formats/src/pptx/table-transform.mbt)和 [`table-layout.mbt`](../../../modules/formats/src/pptx/table-layout.mbt)。框重置与按宽度重排参考 [ONLYOFFICE changeLayout](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L728-L753)及 [GraphicFrame 表格重排](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicFrame.js#L413-L477)，未复制上游源码。

### 跨文稿页面导入

`PresentationEditor.inspectSlides(bytes)` 只读返回源页的 `index/title/hidden` 目录。`importSlides(bytes, indices)` 在调用时绑定当前 revision 和页面，按给定的零基索引顺序插入到该页之后，选择首个导入页。默认页栏可读取本地 PPTX、勾选页面并一次插入。底层命令为 `inspectPptxSlides { revision, bytes, indices }` 与 `importPptxSlides { revision, bytes, indices, after, profile }`。前者在索引为空时只读目录，指定索引时还返回字体、图片和媒体预检资源。Web 导入在预检中请求 `prepareResources: true` 和 `verifyImages: true`，由核心验证支持的 PNG/JPEG。浏览器验证其余图片和媒体，再复核目标选择。核心维护全部原生部件与历史。

导入复制所选页、版式、母版、主题、普通备注、图片、内嵌音视频、表格样式、图表及其嵌入数据。部件路径、页/对象和已知创建身份独立分配，关系、连接与计时目标一起重映射。页间链接必须指向同次选择的源页，遗漏目标则整次拒绝。页面按目标文稿宽高分别缩放几何、表格列宽和行高，保留字号、方向、隐藏状态及源设计；目标章节按插入位置归属。全部导入只有一项精确撤销/重做历史，可保存重开、继续编辑和输出 Canvas/PDF。设计继承与尺寸处理参考 [ONLYOFFICE InsertContent2](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L8190-L8310)，未复制上游执行代码。

所选页的传统批注、单层回复及 2018 现代批注也随页面导入，保留原生格式、作者元数据、文字、日期和状态。作者元数据完全相同时复用目标作者，否则分配独立身份；传统索引预留目标实际索引及 `lastIdx`，现代 GUID 同时避开源和目标身份。两种分配也预留目标的悬空作者引用，保留原有缺作者诊断。传统父索引和现代页面锚点重映射，位置按页面比例缩放。两种作者表可以共存，查询、继续回复、复制和删除按页面格式处理；源批注部件独立复制，整次导入仍只有一项历史。格式和边界归[本地批注与回复](pptx-show.md#本地批注与回复)，实现归 [`slide-import-comments.mbt`](../../../modules/formats/src/pptx/slide-import-comments.mbt)。

源输入最多 32 MiB，沿用目标输入/输出、256 页和对象/文字预算。历史非音视频资源最多 4 MiB、音视频最多 64 MiB；导入图片单个压缩源最多 2 MiB，累计解码最多 16 MiB。所选批注合计最多 16384 项，并受各格式的作者、文字和身份扫描上限约束。缺字体、损坏或未知所有权、共享批注、缺失作者、未知批注元数据或作者资源、外部媒体和其他未支持关系整次拒绝，保留目标源、选择及重做。默认 UI 沿用“恢复编辑”后继续操作。源全局放映设置和章节不合并，复杂跨文稿兼容仍属 P12。

### 文稿与对象

`PptxSession.execute({ operation: "createPptx", budget })` 与 `PptxClient.execute` 创建 960×540 pt 的空白演示文稿，包含一张无对象页面及其空白版式、母版、主题、关系和内容类型。主题使用 Arial 和显式颜色/无效果样式；当前页为该空白页，revision 与历史为 0。创建后可显示、插入基本对象、保存、重开及输出静态 PDF。默认 UI 与 `mountEditor`、实例 `create/open` 使用同一入口及首次保存规则。主题颜色及字体已支持下述编辑，母版编辑继续实施；创建不生成占位文字或不可编辑的背景图片。

`PptxSession.execute()` 与 `PptxClient.execute()` 使用独立的 `PptxCommand`，不复用 DOCX/XLSX 位置模型。`PptxQuery` 返回 revision、声明页序/尺寸/隐藏状态、当前页对象、有效字体键、图片键、选区、历史状态与诊断。幻灯片 ID 为源部件路径，对象 ID 为所属部件与源 `cNvPr.id`；未知对象使用只读源节点身份。对象包含 `parent`：顶层为空串，组成员为直接父组身份。组自身以 `kind: "group"` 返回，成员按原顺序绘制；默认列表、对象导航和全选只使用顶层对象。未知组效果仍诊断并阻止点穿。

| 命令 | 作用 |
| --- | --- |
| `openPptx` / `queryPptx` | 显式预算打开 Transitional PPTX / 查询当前状态 |
| `selectPptx` / `navigatePptx` | 页/有序对象集合/文字选择、对象顺序及字素/行导航；文字使用对象内 UTF-16 offset |
| `editPptxSlides` | revision、稳定 slide 身份、`PptxSlideEdit` 和字体 `profile`；新增、复制、删除、重排、隐藏/显示、章节、背景、主题颜色/字体、备注或全稿尺寸，返回 `PptxQuery` |
| `editPptxObjects` | revision、字体 profile 和 `PptxObjectEdit`；插入、删除、复制、旋转、翻转、层次、对齐/分布或组合/取消组合，返回 `PptxQuery` |
| `replacePptx` / `deletePptx` | 普通文字范围编辑及方向删除；编辑需要字体 profile |
| `copyPptx` / `pastePptxFragment` | 读取文字及原生富文本快照，或以字体 profile 粘贴快照；范围归[文字富文本片段](pptx-objects.md#pptx-文字富文本片段) |
| `pastePptxObjects` / `objectFragmentImagesPptx` | 以字体 profile 粘贴独立对象快照，或只读校验并提取待解码图片；范围归[对象剪贴板](pptx-objects.md#pptx-对象剪贴板) |
| `beginPptx` / `finishPptx` / `cancelPptx` | 开始、提交、取消 `text` 或 `transform` 候选；匹配 revision 与 candidateId |
| `transformPptx` / `dragPptx` | 绝对位置/尺寸，或基于手势开始几何的 point 增量与核心手柄编号 |
| `undoPptx` / `redoPptx` / `savePptx` | 原子历史及绑定 revision 的源保存 |
| `layoutPptx` / `hitPptx` / `selectionPptx` | 当前页绘制、最上层命中、对象轮廓/手柄及文字光标/选区；几何绑定 layoutId |
| `imageKeysPptx` / `prepareImagePptx` / `imagePptx` | 列出当前页或导出范围的图片。核心返回已注册的 RGBA，或返回压缩源，由宿主解码后注册 |
| `mediaBytesPptx` | 读取当前文稿已声明且受支持的内嵌音视频原字节；外部媒体拒绝 |
| `exportPptxPdf` | 绑定 revision、字体 profile、当前页/整稿、隐藏页选择与输出预算的静态 PDF |

`PptxSelection` 包含 `slide`、有序且唯一的 `objects: string[]`、活动 `object`、`mode`、`anchor` 和 `focus`。空集合要求活动身份为空；非空集合要求活动身份属于集合。集合最多 256 个当前页对象，身份长度最多 1024。文字模式要求唯一对象及有效字素边界。`selectPptx` 必须提供全部字段，失败保留原选择；选择不新增历史。宿主 `selectObjects(objects, active?)` 默认激活最后一项；`select(object, mode?, anchor?, focus?, extend?)` 默认替换选择，`extend=true` 在对象模式中切换成员。

默认 UI 支持 Shift 点击画布/列表切换成员、点击已选成员保留集合以及 Ctrl/Cmd+A 全选。进入文字模式收敛到活动对象。`selectionPptx` 返回成员 `outlines` 和包围盒 `outline`；本地可变换成员使用四角手柄。多选 `dragPptx` 的移动及角点独立宽高缩放沿用开始几何；`transformPptx` 对多选接收整组世界坐标包围盒，宽高倍率分别计算。成员中心按世界轴缩放，旋转和翻转保持；角度规范到 0–360° 后，45–135° 及 225–315° 区间（含起点、不含终点）交换本地宽高倍率，其余角度直接使用两轴倍率。斜角成员采用这一预设规则，不生成剪切变换；结果包围盒由成员几何重新求出。零宽度或零高度的共线集合保留零跨度，不能请求扩展该方向。拖动越过相反角时按各成员的最小尺寸钳制，每个成员继续受原尺寸/位置限制。任一成员受保护时整组拒绝。属性面板使用同一变换路径；候选完成后仅一项历史，取消保持源和选择。 缩放尺寸与中心参考 [ONLYOFFICE ShapeForResizeInGroup](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L2392-L2430)，角度区间参考 [checkNormalRotate](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L185-L188)；未复制上游执行代码。

`PptxSlideEdit` 从 `wasm/pptx` 和 `web/pptx` 导出。`{ action: "move", index }` 将目标页移到从 0 开始的索引，索引包括隐藏页；`{ action: "hidden", hidden }` 修改隐藏状态。编辑宿主为 `PresentationEditor.editSlides(change, slide?)`，省略身份时作用于队列执行时的活动页。重排保持页路径、源页 ID、对象身份、关系及活动选择，仅改 `sldIdLst` 顺序；隐藏只改 slide 的 `show`。自定义放映和页间链接仍按原关系指向同一页面。相同位置/状态不新增历史，错误不提交。

`{ action: "add" }` 在目标页后插入空白本地内容，沿用该页的版式、母版和主题，继承版式/母版中的装饰与背景。新页可继续创建及编辑对象；不复制原页对象、备注、动画或版式占位符。核心分配新页 ID、路径和关系，切到新页并清空对象选择。会话内撤销后再新增不复用该页身份。新 slide 及其版式关系、内容类型和页引用合为一项有界历史，与后续对象/文字、重排和隐藏共同精确撤销/重做。最多 256 页，预算或保护失败不留下新部件。默认 UI 提供新增空白页入口。

`{ action: "copy" }` 在目标页后复制，激活副本并清空对象选择。保留隐藏状态、内容、几何、格式及版式继承，分配新页/对象身份，重映射对象连接与计时目标。自身页链接指向副本，其他页链接及自定义放映保持原目标。图片、版式、母版和主题复用原部件，外部超链接保留地址且不下载。普通备注和传统批注另建部件及关系；备注回链指向副本，批注保留作者和内容，分配新 idx 并更新作者 lastIdx。复制部件、作者索引和页引用进入同一有界历史，支持后续编辑、删除、保存重开和精确撤销/重做。重新复制不复用已撤销的页/对象身份。

复制为已知 PowerPoint 2010 creationId 扩展及 DrawingML 字段生成新身份，保留字段类型和源缓存文字；保护其他未知 XML 身份扩展及 noCopy 锁。已知 p14:media 扩展及内嵌音视频关系复用原媒体和封面。未知关系、图表/嵌入数据、VML 和线程批注需要对应所有权支持后开放。支持页关系为 slideLayout/image/hyperlink/slide/notesSlide/comments/audio/video，以及 Microsoft media；备注关系为 notesMaster/image/hyperlink/slide；传统批注仅允许超链接。外部关系仅允许 hyperlink。标准计时 XML 保留并重映射对象目标；动画编辑与执行范围归[对象动画](pptx-show.md#对象动画)。复制继续受 256 页、对象/文字、输入输出和历史预算约束，失败不修改已提交内容。

`{ action: "delete" }` 删除指定页，至少保留一页。删除活动页时选择原位置的下一页，末页则选前页，并清空对象选择；删除非活动页保留当前选择。同步移除 presentation 页引用、自定义放映中的对应条目，以及其他 XML 中指向该页的已知 DrawingML 点击/悬停链接及关系，保留链接所在对象与文字。空的自定义放映保留身份。仅删除该 slide、其关系和独占的备注/传统批注 XML 及关系，移除对应内容类型；版式、母版、主题、图片、作者与未知资源保留，不扫描清理整个包。共享备注/批注、未知或隐式引用、超出历史/输出预算时原子拒绝。删除部件快照计入有界历史，可与新增、对象及页序编辑精确混合撤销/重做，损坏历史拒绝回放且不改变当前文稿。默认 UI 提供删除页，并禁用最后一页的删除。选择规则参考 [ONLYOFFICE 删除页](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9458-L9485)。

`PptxQuery.sections` 返回 `{ items: PptxSection[], reason }`。每章包含稳定 GUID `id`、`name` 和按页序排列的稳定部件路径 `slides`；类型从 Wasm/Web PPTX 模块导出。核心读取标准 PowerPoint 2010 `p14:sectionLst`，源成员引用 presentation 的数值 `p:sldId`，不使用页索引或关系 ID。存储参考 [ONLYOFFICE SectionList/Section](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Presentation/PresentationChildElements.cpp#L289-L339)。

`PresentationEditor.editSlides` 同步支持 `{ action: "sectionAdd", name }`、`{ action: "sectionRename", id, name }`、`{ action: "sectionRemove", id }`、`{ action: "sectionRemoveAll" }`、`{ action: "sectionMove", id, index }` 和 `{ action: "sectionDelete", id }`。新增在目标页前切分所属章；首次从中间分章时为前页创建 Default Section。移除保留页面，归入前章，首章则归入后章；移除最后一章只清理章节元数据。移动按从零开始的章节索引重排该章及其全部页面，保留活动页/对象身份。新增和复制页继承源章；删除移除成员，跨章移动按落点归属。空章保留，未分章前缀允许存在。每章成员必须连续、有序且互不重复，最后一个非空章覆盖到末页。

最多 256 章，名称最多 255 UTF-16 单元；创建/改名要求非空有效 XML 文字。章节与关联页序合为一项有界历史，可与页操作和原生输入混合精确撤销。重名允许，身份按 GUID 区分。相同名称/位置不新增历史。未知章节属性/子项、非连续/重复/悬空引用和修改保护明确拒绝，不删掉未知源来开放编辑。非目标部件、已有章节外标签及页引用周围源内容保留；未知无关扩展可随章节改名保留，但仍保护页序修改。保存重开及 PDF 使用提交后的页序。默认面板提供新增、选择、改名、保留页面移除、一次移除所有章节、前后移动及删除章节和页面。

默认页列表按 `query.sections` 的稳定身份分组，保留未分章的前缀、全稿页码、空章和隐藏页标记。章节标题显示名称与页数，按钮用 `aria-expanded` 和 `aria-controls` 关联成员页；Enter/Space 切换，另有全部折叠/展开。折叠隐藏该章的页按钮，当前画布及核心选择不变；活动页所在的折叠章由标题标识，外部页导航会自动展开目标章。改名和整章重排保持折叠状态；已移除的章清理状态，新章初始展开。更换/重开文档时初始全部展开。无可用章节时继续显示平面页列表。折叠是默认 UI 的会话视图状态，不写入 PPTX、不增加文档历史，不改变保存/PDF 页序和页数。参考 [GenOffice 章节视图状态](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/renderer/App.tsx#L2247-L2259)，实现归 [`pptx-slides.tsx`](../../../packages/pptx/src/react/pptx-slides.tsx)。

`sectionRemoveAll` 一次移除全部章节，保留全部页、页序、对象、选择及其他部件。章节元数据以一项有界历史移除，可精确撤销/重做和保存重开；没有章节时不修改 revision 或历史。UI 无章节时禁用入口。损坏或未知章节继续保护；其他扩展、外层属性、注释和处理指令保留，只在外层扩展列表没有其他内容时一并移除该空容器。操作目标参考 [GenOffice removeAllSections](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/renderer/slide-actions.ts#L182-L189)，沿用已有标准 p14 写回和核心事务。

`sectionDelete` 同时删除该章及全部成员页，至少保留一页；空章只移除章节元数据。剩余页面、章节和对象保留稳定身份。活动页被删时选择其后首个存活页，无后页则选择末个存活页，并清空对象选择；活动页未删除则保留原选择。页引用、自定义放映、已知页链接、独占备注/传统批注与相关类型声明复用页面删除规则，全部变化进入同一项有界历史。未知入站引用、共享备注/批注、保护或整项累计预算失败不提交任何删除。原生草稿先独立提交，随后整章删除独立撤销。UI 禁用删除覆盖全稿的章节。页面集合与独占资源的精确快照直接扩展既有核心历史，撤销/重做及保存重开不依赖逐页宿主命令。操作目标参考 [GenOffice 整章删除](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/main/slides-main.ts#L4266-L4288)，资源和页选择沿用前述 ONLYOFFICE 页删除规则。

`PptxQuery.slideOrderReason/slideVisibilityReason` 返回各自保护原因。修改保护阻止两者；损坏或未支持的章节、未知 presentation/页列表扩展、presProps 中的位置型 `sldRg` 放映范围和未知 presentation properties 扩展阻止新增、删除与重排。空参考线列表及已知图片编辑数据、默认 DPI、图表引用跟踪设置扩展原样保留；非空参考线列表继续保护。默认 UI 使用这些原因，提供新增、删除、页前移/后移和隐藏/显示，页列表保留隐藏页入口。历史按稳定部件路径恢复，混合对象编辑与页序变化不会改错页面。

隐藏页仍可在编辑器中查看和编辑，允许全部页隐藏。全稿静态 PDF 默认跳过隐藏页，显式 `hidden: true` 包含它们；仅导出当前页时可以输出当前隐藏页。没有待输出页时返回 `unsupported-pdf`，不返回空 PDF。保存重开按新页序打开首张页面，保留隐藏状态。更广复制资源兼容归 [P14](../roadmap.md#p14-兼容与性能已完成)。

`PptxObjectEdit` 从 `wasm/pptx` 和 `web/pptx` 导出。`PresentationEditor.editObjects(change)` 使用同一队列与命令。插入参数为 `{ action: "insert", kind: "text" | "rect" | "roundRect" | "round1Rect" | "round2SameRect" | "round2DiagRect" | "snipRoundRect" | "snip1Rect" | "snip2SameRect" | "snip2DiagRect" | "ellipse" | "pie" | "wedgeRoundRectCallout" | "donut" | "heart" | "lightningBolt" | "triangle" | "rtTriangle" | "diamond" | "parallelogram" | "trapezoid" | "pentagon" | "hexagon" | "heptagon" | "octagon" | "decagon" | "dodecagon" | "plus" | "star4" | "star5" | "star6" | "star7" | "star8" | "star10" | "star12" | "star16" | "star24" | "star32" | "chevron" | "homePlate" | "line" | "leftArrow" | "rightArrow" | "notchedRightArrow" | "upArrow" | "downArrow" | "leftRightArrow" | "upDownArrow" | "quadArrow" | "leftRightUpArrow" | "leftUpArrow" | "bentUpArrow", x, y, width, height, text }`；坐标和尺寸为 point，绝对值不超过 14400。非线对象宽高至少 0.1；线可有一个零尺寸轴，总尺寸至少 0.1。文本框透明无描边，矩形、圆角矩形、椭圆和箭头白底黑色 1 pt 线，直线黑色 1 pt；文字为 Arial 18 pt 黑色，支持 `\n` 与 `U+2028`，线不接收文字。核心校验文字、字体和固定框容量，失败保留文档和历史。

图片插入为 `{ action: "insertImage", bytes: Uint8Array, x, y, width, height }`，沿相同 `editObjects` 入口。坐标为 point，绝对值不超过 14400，宽高至少 0.1。接收本地 PNG/JPEG/GIF 原字节，单图最多 4 MiB，尺寸每轴不超过 4096，像素总数不超过 4194304，文稿最多 256 个不同图片资源；最终包与单项 4 MiB 历史预算仍可拒绝操作。核心检查文件头、声明尺寸和几何；浏览器客户端提交前验证实际解码与声明尺寸一致，坏图保留当前源和历史。同步 Wasm 入口不承担宿主解码，导入图片仍沿原有解码合同。核心分配对象与资源身份，事务新增图片、内部关系和内容类型；撤销移除本次新资源，重做恢复原字节及 ZIP 顺序。对象/页复制共用图片，删除对象/页保留资源，不清理整个包。默认 UI 选择图片文件，并采用插入面板中的 X/Y/宽高。创建矩形图片并 stretch 到给定几何的规则参考 [ONLYOFFICE fillImage](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L114-L142)。高级图片效果归 [P14](../roadmap.md#p14-兼容与性能已完成)。

图片替换为 `{ action: "replaceImage", object, bytes: Uint8Array }`，使用相同图片预算和浏览器解码检查。替换已有图片时要求对象模式中唯一的本地图片（含组成员），保持对象身份、选择、几何、旋转/翻转、裁剪及其他源属性；为它新建图片和关系，不覆盖共享资源或改变其他副本。空 `pic/obj` 槽位也可通过同一命令填入图片，尺寸适配归[占位框填图](#母版与版式编辑视图)。`object` 必须与提交时唯一选中的对象身份一致；文件读取期间改变选择会拒绝替换，防止改错目标。相同原字节不新增历史。已有图片的几何保留参考 [ONLYOFFICE replacePictureData 的 stretch 路径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L839-L869)，当前接口保留原裁剪，不提供 fit/fill/original 模式。

独立图片使用 `editObjects({ action: "imageMode", mode: "stretch" | "tile" })` 切换模式。`picture.mode` 返回当前有效模式，`modeReason` 返回编辑保护原因；默认图片面板提供选择和应用。命令作用于唯一选中的本地图片（含组成员），只改 `blipFill` 的模式节点，保持身份、外框、旋转/翻转、裁剪、不透明度、图片字节及关系。同值不增加历史。未显式声明模式的已知源按拉伸读取，首次切换插入标准平铺。导入支持已有缩放、偏移、对齐与交替翻转，范围与[形状平铺](pptx-objects.md#形状图片填充)相同。平铺使用整张源图并保留裁剪；切回拉伸时重新应用裁剪，并在提交前验证展开尺寸。

图片在拉伸和平铺时均按已支持的预设图片框裁剪，矩形沿原矩形路径，椭圆等复用已有形状轮廓；变换后的框和图片使用同一矩阵。绘制入口参考 [ONLYOFFICE CImageShape.draw](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L592-L659)，平铺语义复用其 ShapeDrawer。背景、形状填充和独立图片共用每页 65536 个重复单元；尺寸和变换候选沿同一数量检查。未知模式/填充标记、外链、固定页面方向及未知效果继续保护；目标内缩归[图片目标内缩](pptx-objects.md#图片目标内缩)；未知几何不放开。失败保留源、资源、选择和历史。保存重开、复制、替换、裁剪、不透明度及 Canvas/PDF 沿原路径。实现归 [`picture-mode.mbt`](../../../modules/formats/src/pptx/picture-mode.mbt)及[共享平铺](../../../modules/formats/src/pptx/shape-tile.mbt)。

四边裁剪为 `{ action: "imageCrop", left, top, right, bottom }`，每边为源图的移除比例，范围 0 至 0.99999。核心按 OOXML 的 1/100000 网格舍入，左右及上下之和必须小于 1，派生绘图坐标继续受预算约束；不改对象外框。四个零恢复整图并移除裁剪覆盖，同值不新增历史。`PptxObject.picture` 返回四边有效比例和 `replaceReason/cropReason`，另返回 `mode` 与 `modeReason`。裁剪锁、继承图片、非唯一选择、未知裁剪标记及预算失败保留源；默认 UI 提供替换文件、四边百分比和重置。替换、裁剪和后续对象编辑沿同一历史精确恢复，保存重开与 Canvas/PDF 共用已有源矩形显示路径。

图片不透明度为 `{ action: "imageOpacity", opacity }`，要求对象模式中唯一的本地图片（含组成员）。`opacity` 为 0 至 1，0 完全透明，1 完全不透明；核心按 1/100000 网格写入 `a:alphaModFix amt`，调回 1 时移除覆盖，同值不新增历史。`picture.opacity/opacityReason` 返回当前值及修改保护原因。支持单个常量 alpha 效果，其他效果继续诊断；带未知保留标记的透明度节点保护修改。倍乘关系参考 [ONLYOFFICE CBlipFill 常量 alpha](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L3818-L3840)。操作保持身份、几何、裁剪、图片原字节及共享副本，能与替换/复制混合精确撤销和保存重开。默认 UI 显示不透明度百分比。

定位后的图片图元携带不透明度，DOCX 行内图片显式使用 1。Canvas 沿公共 `DrawStyle.fillAlpha` 执行，图片结束后恢复默认样式；PDF 在单张图片的作用域应用 ExtGState `ca`，与原像素的软蒙版相乘，不把共享原图改成带透明度的新像素。两个输出共用核心值和相同源像素，完全透明的对象仍保留选择及资源。

删除参数为 `{ action: "delete" }`，复制为 `{ action: "duplicate", dx, dy }`。两者要求对象模式；空选区不修改文档。删除作用于整个集合，先校验全部成员，再提交一项历史；任一保护失败不删除其他成员。复制作用于整个集合，包括受支持的嵌套组；副本按原源顺序放到所属父容器的最上层。保留非变换源内容、页面几何、命名空间与图片/超链接关系，为副本及其全部成员分配会话内尚未使用的新 `cNvPr.id`，域身份同样更新。副本内部对象引用重映射；引用集合外对象而需联动的结构明确拒绝。副本选择保留原选择顺序及对应活动对象。一次复制合为一项历史，任一成员、字体、几何或预算失败不创建副本、不消耗身份。原对象的页面姿态、非变换内容、其他部件及资源保持；组内原生坐标可随边界重算归一化。一次复制的 XML 片段及继承命名空间合计最多 2 Mi UTF-16 单元，在拼接前检查；最终包和历史继续受原有预算约束。删除清空选择；撤销/重做精确恢复源 XML 与选择。`PptxObject.deleteReason/duplicateReason` 返回操作保护原因，空串表示可用。继承/跨父组选择/未知对象继续保护；复制占位符及未知扩展、删除锁定或带连接/计时引用的对象仍拒绝，含未支持所属关系的页面也保护删除。资源和关系不做清理。默认 UI 提供插入面板、复制/删除按钮；对象输入支持 Delete/Backspace 与 Ctrl/Cmd+D，默认复制偏移各 18 pt。

原对象或组合成员已有的文字/表格溢出随副本保留为布局诊断，不阻止保持原框的复制。字体测量、资源、几何及事务预算继续校验；新增文字和修改文字框沿各自原有容量保护。实现归 [`object-copy.mbt`](../../../modules/formats/src/pptx/object-copy.mbt)。

GIF87a/GIF89a 图片复用既有 Chromium 解码器和核心 RGBA 资源。当前显示解码器选取的静态帧；动画仍未实现。插入、替换、背景、形状填充、平铺、对象复制与跨文稿导入共用 [image-info.mbt](../../../modules/formats/src/pptx/image-info.mbt) 的有界头尾和尺寸检查。实际码流由浏览器解码，失败的候选保留当前文档。保存继续保留原 GIF 字节、关系、裁剪和透明度。签名依据 [ONLYOFFICE GIF 检查](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/raster/ImageFileFormatChecker.cpp#L104-L125)，当前像素与功能证据归[测试说明](../testing.md#当前兼容证据入口)。
