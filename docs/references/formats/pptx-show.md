# PPTX 放映、表格与输出

[格式合同目录](../formats.md)

### 嵌入音视频

`PresentationEditor.editObjects({ action: "insertMedia", kind, contentType, bytes, poster, x, y, width, height })` 插入本地音频或视频。`kind` 为 audio/video，`bytes` 是媒体原字节，`poster` 是 PNG/JPEG 原字节，几何使用磅。同步 Wasm 与 Worker 复用 `editPptxObjects`，MoonBit 对应 `InsertMedia`。插入只作用于普通幻灯片；媒体、封面、内容类型、三条关系及对象选择合为一项精确历史。失败保持原包、历史与身份分配。核心检查容器签名，Web 还须成功解码首帧或音频数据，不能仅按扩展名接收。

`editObjects({ action: "fillMedia", kind, contentType, bytes, poster })` 向普通幻灯片中单选的空 `media/obj` 占位符填入本地音视频，MoonBit 对应 `FillMedia`。输入、解码和预算沿上述插入规则，不接受显式几何。核心复用占位图片的 96 dpi、居中和等比适配规则，小封面不放大，保留旋转/翻转。转换为原生 `p:pic` 后保留占位符身份、名称、定义、样式、顺序及选择；版式提示和其他部件保持。封面、原媒体、双媒体关系及内容类型共用一次精确历史。版式重置恢复槽位几何，保留媒体和播放设置；保存重开后可继续修改播放属性，Canvas、PNG/PDF 使用同一封面。

对象查询的 `mediaFillReason` 返回保护原因。默认媒体面板提供“填入所选媒体占位符”，勾选后文件选择作用于当前槽位。仅含 `noGrp` 的形状锁随填充迁移为同值图片锁。文字非空、非目标类型、组成员、其他锁、已有点击动作或扩展应用元数据继续保护；母版/版式视图保留槽位定义。文件读取及异步解码后复查 revision 和选择，目标变化或资源失败不修改文稿。适配和音视频替换依据 [ONLYOFFICE addImages](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L3803-L3864)，实现归 [`placeholder-media.mbt`](../../../modules/formats/src/pptx/placeholder-media.mbt)，复用已有图片、原生媒体和播放事务，未复制上游源码。

对象沿原生 `p:pic` 保留封面几何与 `kind="image"`，另有 `PptxObject.media: PptxMedia | null`，普通对象为 null。媒体描述包含 `{ kind, key, contentType, poster, reason }`，从 Wasm/Web PPTX 模块导出类型。`mediaBytesPptx` 按 key 读取已声明的受支持内嵌资源；外链或冲突关系仅返回对象级原因，不下载或提供本地字节。支持已知 a:audioFile/a:videoFile 和 p14:media；未知扩展继续保护。普通对象/页面复制分配新绘图身份，复用不可变的媒体和封面；变换、删除、撤销重做及保存重开沿现有事务。删除保留资源，未引用但仍保留的媒体关系继续计入累计预算。

默认面板从显式本地文件解码生成视频首帧封面或音频播放符号。`preparePresentationMedia(bytes, limits, signal?)` 从 `web/pptx` 导出，供宿主复用；`limits` 使用 `client.inputLimits()` 或 `editor.inputLimits`，定义归[PPTX 输入限额](pptx-editing.md#pptx)。容器声明为 audio/wav、audio/mpeg、audio/mp4、audio/webm、video/mp4 或 video/webm；浏览器拒绝编码或数据损坏时，插入失败并保留文稿。当前 Chromium 实测覆盖 PCM WAV 和 VP8 WebM，其余编码按实际解码能力处理，未据文件扩展名承诺兼容。解码帧每轴最多 4096、最多 16777216 像素；生成的封面最多 1920×1080，仍遵守图片输入/解码预算。取消、超时、失败和完成均清理临时解码器及对象 URL。

媒体原字节有独立的单资源 16 MiB、累计 64 MiB 和 64 项预算，历史另限 64 MiB。XML 与图片历史仍共用原来的 4 MiB；`historyBytes` 返回两类历史的合计。原包、XML、输出和显式宿主预算同时生效，可能先达到其上限。静态 Canvas、PNG/JPEG 和 PDF 使用封面，原媒体字节保留在 PPTX。手动及已支持的动画命令归[放映媒体](#放映媒体)和[对象动画](#对象动画)；循环、音量及静音归[媒体播放属性](#媒体播放属性)；更广原生媒体计时继续实施。原生结构参考 [ONLYOFFICE Pic::fromPPTY](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Pic.cpp#L1205-L1256)；未复制上游执行代码。

### 放映与演讲者视图

按区间打开的文稿在放映时继续读取设置、备注和画面所需字节。放映画面沿用编辑器的对象占位框。`PptxShowLayout.diagnostics` 返回当前页的绘制提示。资源读取或预算失败仍会返回错误。

`PresentationEditor.slideshow.start("settings" | "first" | "current" | { show: id }, labels?)` 按已保存设置、从头、当前页或指定自定义放映开始。省略参数时使用 settings。默认页列表提供这些入口。`labels` 使用 `PresentationShowLabels`，从 `web/presentation-editor` 导出，默认 UI 随语言提供名称。`navigate(action, slide?)` 接受 `next/previous/first/last/goto/gotoPosition/click/tick/pause/resume/end`，`end()` 退出。goto 使用页身份并定位当前序列的首次出现；gotoPosition 使用从 0 开始的条目序号字符串，可以区分重复页。click 遵守单击换页设置，next 保持显式导航；tick 根据时间推进自动换页。`active` 包含开始中的状态，`state` 返回当前快照，未放映时为 undefined；`paused` 表示切换及自动换页计时暂停。Wasm/Web PPTX 模块导出 `PptxQuery/PptxShowAction/PptxShowState/PptxShowLayout`。

核心保留编辑页及文字/对象选择，以已提交 revision 管理独立播放位置。普通及自定义导航均跳过隐藏页；当前页开始与显式跳页可到达隐藏页。普通 goto 在自定义放映中限于该序列；源链接的跨序列规则归[放映链接](#放映链接)。没有可见页时开始拒绝。切换尚未结束时，next 先完成当前切换；再次前进才换页或退出末页。后退直接显示目标条目，条目改变后重置入场、动画与计时，包括连续重复同一页。首屏从黑底进入。`index/count` 表示源页序和源页总数，包含隐藏页；`order` 为播放条目的页身份数组，`position` 为当前条目序号，`custom` 为自定义放映 ID 或 null。条目与计数保留隐藏页，默认导航跳过它们。`nextSlide` 是序列中的下一可见页或 null。结束状态的 order 为空、position 为 −1、custom 为 null。候选须先完成或取消；放映期间核心拒绝文档、选择和历史修改。保存及静态输出读取已提交的编辑布局，不改变播放位置或源内容。

低层 controlShowPptx 携带 revision、action、slide 和必需的 time；start 可额外提供 custom ID，此时 slide 为空。startSettings 使用文稿默认选择，不接受 slide 或 custom。layoutShowPptx 携带 revision/profile/time，返回一至两个 R0 页面及 animating。time 为 0–1000000000 的有限单调毫秒，倒退请求拒绝且保留状态。核心扣除暂停间隔后计算进度，不调用宿主时钟。Web 每帧先用 tick 更新播放位置，再准备相邻资源和布局；animating 在切换或等待自动换页时为 true。每次最多处理一项帧工作，忙时只保留最新时间。核心缓存包含播放序列与条目位置，重复页也会更新下一页预览；每帧只重组位置及透明度。结束放映清除播放缓存。imageKeysShowPptx 返回当前、切换前及下一页资源；资源池同时保留编辑页，继续受 256 个键和 16 MiB 解码上限约束。

模态视图位于所属编辑器内，容器全屏兼容 Shadow DOM。支持方向键、PageUp/PageDown、Home/End、页面点击、显式条目跳转和 Escape；原生选择及颜色控件保留自身按键。演讲者开关显示下一页与普通备注；演讲已用时间继续累计，pause/resume 冻结/继续切换及自动换页计时。退出恢复原生焦点和选择；文件替换、宿主 setPaused(true) 和释放结束放映，清理画布、帧请求、监听器和计时器。对象与文字点击链接已有核心命中和键盘入口，范围归[放映链接](#放映链接)。临时画笔及手动媒体归下文；独立窗口仍待实现，源元数据保留。

页序规则参考 [ONLYOFFICE 可见页导航](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/Transitions.js#L4641-L4742)和[显式跳页](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/Transitions.js#L4978-L5003)。实现归 [`slideshow.mbt`](../../../modules/formats/src/pptx/slideshow.mbt)、[`show-state.mbt`](../../../modules/formats/src/pptx/show-state.mbt)及 [`presentation-show.ts`](../../../packages/pptx/src/web/presentation-show.ts)。

### 媒体播放属性

`PresentationEditor.editObjects({ action: "mediaPlayback", value: { loop, volume, mute } })` 修改单个本地顶层音视频对象。`loop/mute` 为布尔值；`volume` 为 0–100000 的整数，沿用原生音量单位，100000 表示 100%。默认值为 false/100000/false。Wasm/Web 导出 `PptxMediaPlayback`，MoonBit 使用 `MediaPlaybackSettings`，其中循环字段名为 `cycling`。`query.mediaPlayback` 返回当前对象的 `{ value, reason }`，普通对象的 value 为 null；默认媒体面板提供循环、百分比音量、静音及一次应用。多个字段合为一项精确历史，无变化不提交；原生草稿仍先沿既有屏障提交。

属性保存为原生动画根节点下的 `p:audio/p:video`、`cMediaNode.vol/mute` 及 `cTn.repeatCount="indefinite"`。保留单页封面，等待媒体动作启动，并在页导航时停止。仅有播放属性而没有主动画序列的源也可读取；新建媒体动画同时补齐其原生媒体节点，动画列表修改和清空保留播放属性。对象和页面复制重映射目标及时间身份，复制对象独立修改设置，共享不可变媒体字节。仅有播放属性引用时，删除对象同时回收该节点；其他动画及连接引用继续保护。

`slideshow.state.media[].playback` 返回实际使用的属性。浏览器将循环、音量比例和静音传给已有解码器，保留实例 token、暂停、停止、故障及释放规则。循环不重复分配播放器，也不推进页面；停止恢复封面并释放资源。放映不修改文稿和历史，静态 Canvas/PDF 仍使用封面。Chromium 已检查 PCM WAV 的多次实际回卷、精确音量比例及静音属性；未据此声明实际扬声器音量验收。

当前读取普通单页、保留封面、无限循环或单次播放的媒体节点。有限重复、自动开始的独立媒体节点、跨页延续、全屏、叙述、隐藏封面及未知节点/属性继续保护；自动播放使用已支持的媒体动画命令。无关普通对象的复制/删除保留未知媒体源。原生字段依据 [ONLYOFFICE CMediaNode](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Timing/CMediaNode.cpp#L42-L68)和 [CTn](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Timing/CTn.cpp#L42-L103)；未复制执行代码。实现归 [`media-playback.mbt`](../../../modules/formats/src/pptx/media-playback.mbt)。

### 放映媒体

`PresentationEditor.slideshow.media({ object, token, action })` 接受 play/pause/stop。`object` 是原生对象身份，`token` 取自当前 `slideshow.state.media`。该数组包含 `{ object, label, kind, key, contentType, token, state, reason, visible, playback }`，状态为 stopped/playing/paused/ended/blocked/error。初始 token 为 0；开始新实例、重播和停止分配新标识，暂停续播保留标识。画布点击已知媒体动作也切换播放/暂停。默认界面为每个对象提供播放、暂停、停止及对象级原因，键盘可操作。

核心管理动作、可见性和实例身份；Web 仅从显式资源字节解码。低层 `mediaShowPptx` 携带 revision/time/change；用户动作另带当前 layoutId。ended/paused/blocked/error 是浏览器反馈，不带 layoutId，必须携带有效 token；error 还带非空、最多 1024 UTF-16 的 message。Wasm/Web 导出 `PptxShowMediaChange/PptxShowMediaState`，MoonBit 使用 `ShowMediaChange`。过期实例、其他页面和结束后的反馈拒绝，播放事件不推进页面、不改文稿、选择、历史或静态输出。播放标识与绘制帧标识独立，反馈不会使正在输入的指针帧失效。

`state="playing"` 表示播放意图。全局暂停或对象隐藏时暂停实际播放，恢复后续播；停止释放解码器并恢复封面。播放结束保留末帧，重播从头开始。换页、退出、换文件和 dispose 释放播放器、对象 URL、事件及帧请求。浏览器拒绝播放时保留“播放”重试入口；不支持的编码或损坏数据只报告到该对象，其他对象及页面继续操作。媒体读取沿宿主原有队列串行执行，错误信息保留到后续动作；控件区滚动，不随状态文字改变画布位置。

视频沿核心 `PptxShowLayout.media` 给出的对象/图片命令路径绘制，保留层次、裁剪、不透明度、变换和上层笔迹。共享封面的复制对象使用不同命令实例，不共享播放帧。通用 Canvas 执行器可为指定图片命令接收临时图像源；静态输出继续使用原封面，不写入视频帧。纯视频帧重绘复用当前绘制批次，不逐帧请求核心。放映最多保留 16 个播放器，包括暂停、结束和等待重试的实例；停止可释放名额。压缩输入累计最多 64 MiB，视频帧每轴最多 4096、累计最多 16777216 像素，分辨率变化时重查；图片命令绑定累计最多 65536 条。媒体输入及图片、Canvas、包预算同时生效。

当前 Chromium 实测 PCM WAV 与 VP8 WebM。点击及自动媒体命令归[对象动画](#对象动画)，循环和音量/静音归[媒体播放属性](#媒体播放属性)；跨页延续和更广原生媒体计时仍待实现。动作与平台边界参考 [ONLYOFFICE CCmd::getMediaData/setState](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L8664-L8737)；未复制上游执行代码。

### 放映临时画笔

`PresentationEditor.slideshow.ink(change, layoutId?)` 仅修改当前放映的临时笔迹。省略 `layoutId` 时绑定当前显示帧。`PptxShowInkChange` 从 Wasm/Web PPTX 模块导出：`begin` 接受 RGB `color`、以 pt 为单位的 `width` 及 `{ x, y }[]` 点；`append`、`end` 接受点数组，`end` 可为空；`cancel` 丢弃当前草稿，`clear` 清空当前源页。低层 `inkShowPptx` 携带 revision、layoutId、单调 time 和 change，核心使用 `ShowInkChange` 校验。失效帧、非法笔或超预算拒绝并保留最后有效状态。

核心按源页保留已完成笔画，返回圆端点、圆连接的 R0 路径；单点生成圆点。切换前后页和下一页预览使用同一笔迹图元，笔迹随页面切换合成。导航取消未完成笔画，返回同一源页恢复已完成笔迹。`PptxShowState.ink` 返回本页已完成 `strokes` 数、包含草稿的 `points` 数及 `drawing`。结束放映返回零值并释放全部笔迹；重新开始为空。文稿 revision、编辑选择、历史、保存及静态 PDF/图片不包含临时笔迹。

默认放映提供画笔、颜色和清空本页。笔宽为 2.25 pt；Web 只转换指针坐标、采集与合并样本，每帧最多提交一批 64 点，由核心绘制。拖动捕获指针，页面外位置限制在页面边缘。绘画点击不触发链接或换页。Escape 取消当前笔画并回到普通指针，再按一次退出；丢失捕获和停用画笔同样取消草稿。退出、文件替换和释放停止采样及帧请求。

`PresentationEditor.slideshow.saveInk()` 与默认“保存墨迹并结束”显式提交全部源页上的已完成笔迹，再结束放映。低层使用 `controlShowPptx` 的 `saveInk` 动作，携带当前 revision、单调 time 和空 slide。核心为每笔创建本地 `p:sp/a:custGeom` 开放折线，保留颜色、宽度、圆端点和圆连接；每页放到现有对象上层，全部页面合为一项历史。原编辑选择和未改部件保持。保存后可命中、移动、缩放、旋转、复制、删除及修改描边，重开、Canvas、图片和 PDF 共用该路径。无笔迹时只结束，不新增历史。Web 先提交已抬笔的待发送样本，取消仍在绘制的草稿；同步核心遇到活动草稿则拒绝。任一页面保护、身份或输出/历史预算失败，全部源、序列和已完成笔迹保持，可继续放映或普通结束。

原生路径读取当前只支持单个、无填充、启用描边的 moveTo/lnTo 路径、常量坐标及空引导列表，每个形状最多 4097 点。路径坐标随对象框缩放，命中按各线段距离计算。零高/宽笔迹使用最小 0.1 pt 框保持既有缩放手柄，单点保留 0.01 pt 线段以显示圆点。曲线、关闭路径、多路径、公式引导和压感数据仍诊断并保护源，不以默认矩形覆盖原源。原有对象、XML、历史及 R0 绘制预算继续适用。

每笔最多 4096 点，整次放映最多 256 笔、32768 点。正在输入的草稿计入点数检查。每批最多 64 点，宽度为 0.5–24 pt，坐标须为页内有限值。Web 以核心的单笔上限限制待发送样本。超限时取消当前草稿并显示错误，已完成笔迹保留。橡皮擦、激光笔、曲线平滑及压感继续实施。

实现归 [`show-ink.mbt`](../../../modules/formats/src/pptx/show-ink.mbt)、[`show-ink-save.mbt`](../../../modules/formats/src/pptx/show-ink-save.mbt)、[`polyline.mbt`](../../../modules/formats/src/pptx/polyline.mbt)及 [`presentation-show-ink.ts`](../../../packages/pptx/src/web/presentation-show-ink.ts)。开放无填充路径和边界参考 [ONLYOFFICE PolyLine](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/PolyLine.js#L180-L262)，当前保留采样折线，不引入曲线拟合。临时页级笔迹、取消和显式写入源的分离参考 [ONLYOFFICE SlideShowAnnotations](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/SlideShowAnnotations.js#L53-L193)。未复制上游执行代码。

### 放映链接

`PresentationEditor.slideshow.click(x, y)` 激活当前已显示帧上的位置；坐标为页面 pt，不是 CSS 像素。默认 Canvas 将点击转换为该坐标。核心按当前形状轮廓、组成员和实际文字字符区域命中；文字链接优先于对象链接，成员无链接时使用最近的组链接。无链接的前景对象阻挡后方链接。动画中的平移、缩放、旋转共用绘制矩阵；动画隐藏项不参与命中。未命中链接时保留原单击动画/换页规则。页面切换期间先完成入场，不激活链接。

`slideshow.followLink(id)` 使用当前放映布局返回的链接 ID，供键盘及自定义宿主使用。`PptxShowLayout.links` 为 `{ id, label, reason, external }[]`；id 是核心分配的十进制字符串，只在当前布局有效。label 使用对象名称或文字，reason 非空时显示诊断并禁用执行；external 为已校验的外部地址或 null。默认视图给内部链接提供按钮，给外部地址提供带 `noopener noreferrer` 的新窗口链接，动画隐藏项不显示。列表更新保持仍存在项的键盘焦点。

内部页链接可明确到达隐藏页，在当前序列中定位目标的第一次出现。若目标不在当前范围或自定义序列内，核心转入完整文稿页序并清除 custom，再从目标继续；此规则是当前 SDK 合同，不声称已由上游自定义放映运行结果验证。首页/末页/上一页/下一页按活动放映序列执行，默认跳过隐藏条目；起点后退停留，末尾前进退出或按循环开关返回。导航重置目标入场和计时，保留编辑选择及源历史。

`lastslideviewed` 返回上一个播放条目。核心只保留该条目的序列、位置和自定义组身份，不保留完整访问栈；普通导航、链接跳转和自动换页在进入新场景时更新。返回时恢复重复条目的准确位置，以及跳出自定义/范围序列前的播放顺序；连续激活在最近两个条目间往返。暂停、布局帧和外部链接不改此记录。首次开始没有记录时停留；结束或重新开始清除记录。目标入场、对象动画和计时按普通跳页重新开始。`endshow` 直接结束当前放映，清除播放缓存；默认视图沿现有退出路径关闭并恢复原生焦点、编辑选择和已提交源。这些播放细则是当前 SDK 合同；未声明已独立运行上游放映验证。标准动作序列化依据 [ONLYOFFICE ShapeWriter](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/MsBinaryFile/PptFile/PPTXWriter/ShapeWriter.cpp#L1692-L1728)。

低层 controlShowPptx 的 click 可携带完整的 layoutId/x/y；followLink 携带 layoutId，slide 使用链接 ID。缺字段、旧 revision、其他场景及过期布局拒绝且不改变状态。同场景保留当前和上一帧，用于处理帧刷新与点击的交错；控制操作及换页会失效旧交互。外链不由核心请求：本次显式激活的 `PptxShowState.external` 返回地址，其他状态为 null。Web 通过新窗口执行，浏览器阻止弹窗时仍可使用列表中的显式链接。HTTP/HTTPS/mailto 的地址校验复用编辑链接边界，打开文件、布局和播放帧不会自动请求地址。

每帧最多 4096 个链接，ID 上限 4095；标签最多 1024、诊断最多 8192 个 UTF-16 单元，标签/诊断/外链总量最多 1 Mi 单元。宏、文件地址、未知动作及扩展链接保持源并显示诊断，点击拒绝执行。已知链接在只读对象和文稿中仍可播放。静态 PDF/图片不增加交互链接注释；自定义放映动作、悬停与其他动作继续实施。

命中后优先处理链接、未命中再换页的依据是 [ONLYOFFICE 放映点击路径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/Transitions.js#L5357-L5445)；动作与外部宿主分派参考[链接回调](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/api.js#L7243-L7283)。实现归 [`show-links.mbt`](../../../modules/formats/src/pptx/show-links.mbt)、[`show-animation.mbt`](../../../modules/formats/src/pptx/show-animation.mbt)和 [`presentation-show.ts`](../../../packages/pptx/src/web/presentation-show.ts)。

### 放映设置

`PresentationEditor.editSlides({ action: "showSettings", value })` 修改整份文稿的默认放映。value 类型为 `NonNullable<PptxQuery["showSettings"]["value"]>`，包含 slides、timings、animations 和 loop。slides 接受 `{ kind: "all" }`、`{ kind: "range", first, last }` 或 `{ kind: "custom", id }`。范围是从 1 开始的闭区间，必须满足 first ≤ last ≤ 页数。custom 使用已有自定义放映 ID。查询返回 value/reason；未知选择、重复范围或无法解释的属性保护修改及按设置开始，源内容保持。

缺省为全部页、启用计时和对象动画、关闭循环。timings=false 禁用自动换页，保留每页设置及手动导航；animations=false 直接显示完整对象，不执行对象动画，页面切换仍保留。loop=true 在向前到达末条目后回到首个可见条目，单页也重置场景；后退仍在起点停留。循环沿用暂停、相邻页缓存及隐藏页规则，零时长循环每次 tick 最多推进一个序列长度。显式 first/current/custom 入口覆盖默认范围，仍使用三个全稿开关。

默认 UI 提供全部页、页码范围或自定义放映，以及计时、对象动画和循环开关。应用后合为一次历史；开始读取已提交值。页重排、增加和复制保持范围的数字位置；删页后把超出末页的起止值收窄到剩余页数。自定义组仍使用稳定页身份；被默认选择的组须先取消选择才能删除。

源采用标准 `presProps/p:showPr` 的 `sldAll/sldRg/custShow` 和 useTimings/showAnimation/loop。首次编辑可创建属性部件、关系及内容类型，连同源历史一起撤销和重做；相同设置不改字节或新增历史。只修改变化的属性和选择片段，保留 showNarration、显示模式、画笔颜色和其他未改源内容。叙述、窗口模式、默认画笔颜色及更广媒体计时仍待实现。媒体命令和临时画笔归各自合同；保存与静态输出继续使用完整文稿，不按默认放映范围裁剪。

字段和序列化依据 [ONLYOFFICE ShowPr](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/ShowPr/PresentationPr.cpp#L48-L128)及[页码范围](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/ShowPr/SldRg.cpp#L42-L78)。重排与删页的数字范围规则是当前 SDK 合同，未声称由上游运行结果验证。实现归 [`show-settings.mbt`](../../../modules/formats/src/pptx/show-settings.mbt)、[`show-settings-create.mbt`](../../../modules/formats/src/pptx/show-settings-create.mbt)和 [`pptx-show-settings.tsx`](../../../packages/pptx/src/react/pptx-show-settings.tsx)；沿用现有编辑队列及播放状态。

### 自定义放映

`PresentationEditor.editSlides({ action: "customShows", value })` 替换整份文稿的自定义放映列表，类型可用 `PptxQuery["customShows"]["items"]`。每项为 `{ id, name, slides }`；新建时 id 为空，由核心分配 uint32 的十进制字符串，现有项保留 ID。name 为 1–255 个有效 XML 文本单元，名称忽略大小写后唯一。slides 使用稳定页身份，可重复并保留顺序。每份文稿最多 32 组，每组最多 256 个条目，合计最多 4096 个。空组可以保留，但不能开始；`query.customShows` 返回 items/reason。

默认面板支持创建、命名、复制、删除、添加/移除条目、前后调整条目及显式开始。草稿经“保存自定义放映”提交，开始使用已提交的定义。修改受保护时仍可选择和播放已知定义。每次应用为一项精确历史；相同列表不新增历史。页移动和复制保持已有定义，复制页不会自动加入；删除页会移除其全部重复引用，允许组变为空。已有放映设置引用的组不能删除；存在未支持的自定义放映超链接动作时也保护删除，防止留下失效目标。重命名保持 ID 与引用。

源写入标准 `p:custShowLst/p:custShow[@name,@id]/p:sldLst/p:sld[@r:id]`，复用 presentation 的 slide 关系。未修改的定义保留源片段，读写、历史和预算沿用既有事务。扩展定义、未知属性、注释、失效关系及重复身份保护修改和自定义开始，普通放映仍可运行。默认放映选择已接通读取、编辑和播放，范围归[放映设置](#放映设置)；自定义动作链接继续实施。

已核对 [ONLYOFFICE 的自定义放映模型与序列化](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Presentation/PresentationChildElements.cpp#L411-L531)，该快照的名称/身份和列表输出不完整；标准结构依据 [Open XML SDK 的 CustomShow、SlideList 与 SlideListEntry](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/generated/DocumentFormat.OpenXml/DocumentFormat.OpenXml.Generator/DocumentFormat.OpenXml.Generator.OpenXmlGenerator/schemas_openxmlformats_org_presentationml_2006_main.g.cs#L12165-L12319)。隐藏页规则参考 [LibreOffice 自定义放映](https://books.libreoffice.org/en/IG70/IG7009-SlideShowsPhotoAlbums.html)。实现归 [`custom-shows.mbt`](../../../modules/formats/src/pptx/custom-shows.mbt)与 [`pptx-show.tsx`](../../../packages/pptx/src/react/pptx-show.tsx)。

### 页面切换

`PresentationEditor.editSlides({ action: "transition", value }, slide?)` 设置目标页切换；null 移除本地切换效果，保留换页设置。`PptxTransition` 为 `{ kind, duration, direction }`，从 Wasm/Web PPTX 模块导出。kind 接受 none/fade/push。fade/push 的 duration 为 100–60000 的整数毫秒，none 只接受 0。push 的 direction 接受 left/right/up/down，表示页面移动方向；其他类型固定为 left。默认面板提供种类、时长、方向、应用与移除。`query.transition` 返回 value/advance/reason。

标准 transition 的 cut/fade/push 及 p14:dur 已接通读写；缺少 dur 时，spd 的 fast/med/slow 分别取 500/750/1000 毫秒。读取不改源，相同设置不新增历史。修改保留页、选择、其他 XML 与资源，共用一次精确历史。声音、经黑场淡入和未知效果继续保护。未知源和非法参数不提交部分结果。播放采用整页隔离透明度或两页平移，保存/PDF 保持静态源布局。

`editSlides({ action: "advance", value }, slide?)` 设置换页。Wasm/Web 导出的 `PptxAdvance` 为 `{ click: boolean, after: number | null }`，查询位于 `query.transition.advance`。after 为 0–3600000 的整数毫秒，null 关闭自动换页。默认值为允许单击且不自动换页。默认面板分别应用效果和换页设置，每次应用各为一项历史；改变效果保留换页，改变换页保留效果。源采用 advClick/advTm，只有换页属性的 transition 也支持读取、保存与重开。

自动等待从入场结束后开始；单击提前结束入场时从该时刻开始。暂停保留剩余时间。迟到帧按源页序有界追赶，跳过隐藏页，到末页退出；源、编辑选择和历史保持。presProps 中 showPr/useTimings=false 禁用自动换页，保留页设置和显式导航；整稿开关通过[放映设置](#放映设置)编辑。规则参考 [ONLYOFFICE 入场后计时](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/Transitions.js#L4486-L4504)、[单击设置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/Transitions.js#L5418-L5445)及[整稿计时开关](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L2115-L2134)，实现归 [`slide-advance.mbt`](../../../modules/formats/src/pptx/slide-advance.mbt)。

方向与速度参考 [ONLYOFFICE 源方向映射](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/apiCommon.js#L429-L450)、[速度缺省](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L4440-L4467)和[整页合成](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/Transitions.js#L442-L770)。未复制上游源码。实现归 [`slide-transition.mbt`](../../../modules/formats/src/pptx/slide-transition.mbt)和 [`pptx-transition.tsx`](../../../packages/pptx/src/react/pptx-transition.tsx)。

### 对象动画

媒体命令 `mediaPlay/mediaPause/mediaStop` 仅接受具有可用本地资源及封面的顶层音视频对象，`params=[]`。默认动画面板共用目标、触发、延迟、顺序、修改和删除控件，固定命令时长及次数。源使用 `presetClass="mediacall"` 与 `p:cmd type="call"`；播放写 `playFrom(0.0)`，暂停写 `pause`，停止写 `stop`。播放命令从头建立新实例；手动媒体面板的暂停续播仍保留播放位置。`after` 等待命令本身的 1 毫秒及延迟，不等待媒体解码结束；结束反馈仍只更新播放器。读取按命令字符串解释行为，书签/裁切起点、扩展命令和重复继续保护。

核心按调度时间、同时间的源顺序执行命令，每页场景中的每项只执行一次。首项为 with/after 时，在入场完成及延迟后自动执行；暂停冻结逻辑时间，手动完成组同时执行该组尚未到时的命令。布局跨过触发时间后继续请求 tick，直到动作状态已发布；视频解码及逐帧绘制沿既有媒体宿主。新实例分配独立 token，旧反馈不能终止新播放；回到页面重置步骤和实例，源、选择、历史与静态输出保持。超出 16 个保留播放器时只报告到超限对象，其他实例及页面继续操作；浏览器拒绝自动播放时仍有手动重试入口。命令与平台边界依据 [ONLYOFFICE CCmd](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L8714-L8732)，未复制执行代码；实现归 [`animation-media.mbt`](../../../modules/formats/src/pptx/animation-media.mbt)。

`PresentationEditor.editSlides({ action: "animations", value }, slide?)` 替换目标页的有序动画。value 是最多 128 项的 `PptxAnimation[]`，每项完整提供 `{ object, kind, trigger, delay, duration, repeat, params }`。类型从 Wasm/Web PPTX 模块导出。object 使用稳定对象 ID，目标限于本地顶层形状、文本框与图片。kind 接受 appear/disappear/fadeIn/fadeOut/scale/rotate/move/flyIn/flyOut/mediaPlay/mediaPause/mediaStop；trigger 接受 click/with/after。delay 为 0–60000 的整数毫秒。除出现/消失与媒体命令外，duration 为 100–60000 的整数毫秒，repeat 为 1–100 的整数；出现/消失与媒体命令固定为 duration=1、repeat=1。`query.animations` 返回 items/reason。

params 为数值数组。出现/消失和淡入淡出使用空数组；scale 使用 `[水平百分比, 垂直百分比]`，每轴为 1–1000 的整数；rotate 使用 `[旋转度数]`，为 −3600–3600 的整数；move 使用 `[水平距离, 垂直距离]`，单位为点，每轴为 −14400–14400 的整数。水平向右、垂直向下、顺时针旋转为正。缩放和旋转围绕源对象中心，直线路径在页面坐标中位移。三种变换分别保留各自终态，可以同时作用于同一对象；同一属性的重叠时间段仍受保护。

flyIn/flyOut 使用 `[方向]`，表示飞入的起侧或飞出的终侧：1 上、2 右、3 右上、4 下、6 右下、8 左、9 左上、12 左下。核心按页面边界、源对象中心和几何外接矩形计算位置，保留源旋转与翻转。飞入从页外回到源位置；飞出从已有位移到页外，不变的轴保留已有位置。飞入开始时显示，飞出在每个周期最后一毫秒隐藏。飞行同时占用位移和可见性，与同一对象这两类属性的时间重叠受保护。

默认面板提供目标、效果、触发、延迟、时长、重复及所选效果的缩放、角度、位移或飞行方向，以及新增、修改、前后移动和移除。每次应用为一项精确历史，保留对象源、选择和其他部件；相同列表不新增历史，空列表清空已支持的动画。未知内容和无效参数保持源与历史。

click 开始一组；with 与当前组共享起点，各自保留延迟；after 等待当前组最长的效果（含延迟与重复）结束。首项为 with/after 时，从页面入场完成后自动开始。重复按周期重新执行，末次完成后保持终态。目标的首项可见性效果为进入时初始隐藏，为退出时初始可见；几何动画保留该可见性。未结束的页面切换先消耗一次 next/click；之后可完成运行中的组，或触发下一点击组，全部完成后才换页。禁止单击换页仍允许触发动画。暂停冻结逻辑时间；手动完成组不会使后续组跳到过期时间。`PptxShowState.step/steps` 表示已调度和总效果数，结束时均为 0。

源采用标准主序列、clickEffect/withEffect/afterEffect、stCondLst 和 repeatCount。出现/消失使用 style.visibility 的 set；淡入淡出使用 style.opacity 的线性 anim，按 ONLYOFFICE 的透明度解释读写。缩放使用 emph/6 与 animScale/by，旋转使用 emph/8 与 animRot/by；位移写为 path/0 的 animMotion，origin=layout，路径坐标按页面宽高归一化。读取接受上述几何参数及从 `M 0 0` 到单个 `L x y E` 的直线；同样接受直线预设 35/42/49/56/63/64。读取校验组间延迟、时间 ID、开始条件、目标、完整次数及属性范围，接受独立前缀和时间 ID。常见 animEffect/filter 形式尚未读取，不据此宣称完整淡入淡出兼容。

飞入/飞出使用 entr/exit 的 presetID=2 和上述方向 subtype。两轴各有一个线性数值 anim，tavLst 的时间点为 0 与 100000，属性为 ppt_x/ppt_y。飞入采用 `#ppt_x/#ppt_y` 和 `0-#ppt_w/2`、`1+#ppt_w/2` 等源坐标公式；飞出采用相应不带 `#` 的已有属性公式。可见性 set 在入场 0 毫秒或出场 duration−1 毫秒触发。读取只接受这些固定公式和时点，拒绝任意表达式、额外轴、混合目标和扩展关键帧。

核心缓存完整对象图元，每帧只按逻辑时间合成既有 R0 矩阵和透明层；文字与形状重叠时整体应用一次透明度。页面裁剪保持在变换外，源对象的旋转、翻转、文字和图片裁剪继续保留。可见性与透明度分别保留，已消失对象不会被几何动画或后续退出透明度重新显示。页面切换保留离场时的透明度和变换；回退或跳转至其他页时从目标页初始状态开始。下一页预览保持静态源。自动换页等待所有动画及点击组完成，之后保留下一页自己的计时。保存、PDF 与图片输出使用完整静态源。

当前读取范围为无构建列表的单主序列。缩放/旋转/路径接受不带 attrNameLst 的上述 by 或路径形式，参数精度按上述整数单位限制。分组或段落子目标、同一属性的时间重叠、曲线、交互触发、无限/分数重复及其他未知 timing 继续保护。查询给出原因，修改和开始播放时拒绝，保持源内容；不会把未知动画当作已播放。带 timing 引用的对象仍受原有删除/组合保护，可先移除其已支持的动画。页复制沿用现有目标 ID 重映射。

语义参考 [ONLYOFFICE 点击组](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L9112-L9167)、[可见性行为](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L9931-L9953)及[初始隐藏对象](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L12121-L12155)。未复制上游源码。实现归 [`animation-read.mbt`](../../../modules/formats/src/pptx/animation-read.mbt)、[`animation-edit.mbt`](../../../modules/formats/src/pptx/animation-edit.mbt)、[`show-animation.mbt`](../../../modules/formats/src/pptx/show-animation.mbt)和 [`pptx-animations.tsx`](../../../packages/pptx/src/react/pptx-animations.tsx)。

计时与透明度参考 [ONLYOFFICE 组间延迟](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L9086-L9110)、[属性合成](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L12860-L12940)和[透明度绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L12950-L12970)。XML 定义参考 Microsoft 的[开始条件](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.presentation.condition)与[动画属性名](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.presentation.attributename)。实现归 [`animation-timing.mbt`](../../../modules/formats/src/pptx/animation-timing.mbt)与 [`animation-xml.mbt`](../../../modules/formats/src/pptx/animation-xml.mbt)。

几何语义参考 ONLYOFFICE 的[相对路径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L7735-L7791)、[旋转](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L8209-L8238)、[缩放](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L8380-L8417)和[中心变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L13023-L13071)。实现归 [`animation-geometry.mbt`](../../../modules/formats/src/pptx/animation-geometry.mbt)。

飞行公式参考 ONLYOFFICE 的[源坐标](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L1486-L1509)、[关键帧求值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L4530-L4628)及[进入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L14468-L14478)/[退出预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L14631-L14641)。实现归 [`animation-flight.mbt`](../../../modules/formats/src/pptx/animation-flight.mbt)。

### 当前页 PNG 输出

`PresentationEditor.exportPng(scale = 1, outputBytes = 67108864)` 返回 `EditorOutput`，`format` 为 `png`。它按现有输入队列导出当前已提交页面，包括明确显示的隐藏页。活动输入/变换候选先完成或取消；布局缺失或与当前页/修订不符时拒绝。选择、源文档、历史、预览尺寸和保存基线保持；导出失败保留编辑与原格式保存入口。

`scale` 为每 pt 的像素数，接受 0.25–4；图片宽高分别为 `ceil(width * scale)` 和 `ceil(height * scale)`，默认 960×540 pt 文稿生成 960×540 px PNG。预览 zoom 和屏幕 DPR 不决定导出尺寸。编码前要求临时图片与现有页面/覆盖层 Canvas 合计不超过 16,777,216 像素；`outputBytes` 为 1–67,108,864 的整数，在复制编码字节前检查 Blob 大小。所有路径释放临时 Canvas；复用的图片和字形路径继续由当前表面持有。

默认文件菜单的“当前页 PNG”使用相同 API。`onSave` 收到 `format: "png"` 及 `.png` 名称的派生输出；没有回调时按 `image/png` 下载。PNG 输出不能 `markSaved`，也不清除 PPTX 未保存状态。它通过当前 R0 执行器重放核心图元，保留已有诊断的显示结果；图片、裁剪、旋转与文字沿现有渲染范围，选择框和光标只在编辑覆盖层中。

`PresentationEditor.exportPageImages(scale = 1, outputBytes = 67108864, hidden = false, format = "png")` 返回全部可见页的只读 `EditorOutput[]`，按文稿顺序排列；hidden=true 包含隐藏页。format 接受 `"png" | "jpeg"`，默认 PNG。结果共享文档身份与 revision，所有图片的字节数之和受 outputBytes 限制。没有选中页面时拒绝。当前页、选区、编辑布局身份、预览和历史保持；后续输入沿同一队列等待集合生成。全部页面成功后才登记并返回输出，失败不交付前缀集合，也不覆盖此前输出记录。

核心 `Session.print_drawing` / Wasm 与 Worker `printLayoutPptx` 复用 `print_layout` 的页面选择、诊断、图元预算和 PDF 几何，返回 `PptxPrintLayout { revision, regions, outlines, images }`。请求携带 revision、all、hidden 和 profile，不改变当前编辑页的布局缓存。批量 PNG 沿完整打印范围保护未知可见内容；单页 PNG 继续保留已有诊断的显示结果。Web 在输出期间准备所选页面图片，逐页编码并释放临时 Canvas，最后恢复当前编辑页的图片集合。

默认文件菜单的“全部幻灯片 PNG”导出全部可见页，复用既有逐页保存/下载流程。名称按 `<原文件基名>-01.png`、`-02.png` 顺序补零，序号只计算导出的页面。所有图片生成后才依次调用 `onSave`；中途失败保留已完成的外部保存及进度，停止后续回调，重试按当前修订重新生成。回调期间继续编辑不会改变已生成图片的 revision。没有 `onSave` 时逐页下载并报告生成进度；多个下载仍受 Chrome 站点权限约束。派生输出不清除 PPTX 修改状态。

上述入口依赖浏览器 Canvas 绘制和编码，当前只检查 Chrome/Chromium；不作为无浏览器图片转换能力。普通 Wasm/Worker 文档状态、布局和 PDF 接口保持原职责。打印入口归[浏览器打印](shared.md#浏览器打印)。

#### JPEG 输出

`PresentationEditor.exportJpeg(scale = 1, outputBytes = 67108864)` 导出当前页，`exportPageImages(scale, outputBytes, hidden, "jpeg")` 导出页面集合。返回输出的 `format` 为 `jpeg`。两者复用上述布局、页面选择、尺寸、像素/总字节预算、队列、源与历史保护及失败恢复。单页保留已有诊断的显示结果，集合沿打印范围保护未知可见内容。

JPEG 使用白色底图和固定 `0.92` 编码质量，属于有损输出，不保留透明通道。平台检查编码 Blob 的实际 MIME；编码失败或浏览器回退其他格式时拒绝交付。默认文件菜单提供“当前页 JPEG”和“全部幻灯片 JPEG”；回调收到 `.jpg` 或按页补零的 `-01.jpg` 名称，没有回调时按 `image/jpeg` 下载。逐页保存失败保留已完成进度，重试按当前修订重新生成；JPEG 输出不能确认原格式保存。实现归 [`canvas-surface.ts`](../../../packages/web-core/src/canvas-surface.ts)及 [`presentation-output.ts`](../../../packages/pptx/src/web/presentation-output.ts)。

### 日期与页脚编辑

`PresentationEditor.editSlides({ action: "footer", value, allSlides }, slide?)` 修改当前页或指定页的日期、页脚和编号。`allSlides=true` 时修改全部页面，包含隐藏页，合为一项历史。Wasm/Worker 的 `editPptxSlides` 使用同一命令。`PptxFooterContent` 为 `{ date: string | { format: number; language: "en-US" | "zh-CN" | "zh-TW" } | null, footer: string | null, number: boolean }`。date 的字符串表示固定文字，对象表示自动日期；format 为 1–13 的整数，对应 `datetime1`–`datetime13`。footer 是页脚文字，null 移除对应对象，空串保留空对象，number 控制编号占位符。MoonBit 使用 `FooterDate::Fixed(String)` 或 `FooterDate::Automatic(Int, String)`，沿 `FooterContent.date` 传入。`PptxQuery.footer` 返回这三项及 `reason`，类型为 `PptxFooter`。缺少对象时为 null/false；未知、复杂或受保护的页边内容返回保护原因。

每项文字最多 4096 UTF-16 单元、256 段，CRLF/CR 归一为 LF，软换行使用 U+2028。核心不读取系统时钟。已有日期和页脚保留对象身份、几何、框属性、列表样式及首段/首 run 格式；新文字使用该格式。相同文字、相同自动日期设置及已有真实编号不改源或历史，刷新后重新应用相同设置也不更新缓存。自动日期使用会话时间，核心缺少时间时拒绝创建；初次创建或改变格式/语言时把当前文字写入字段缓存。修改已有自动日期保留字段 ID、对象身份、几何及首段/首 run 格式，只覆盖所选语言；固定/自动切换和移除沿同一事务。开启静态编号占位符时创建真实 `slidenum` 域；已有真实编号保留缓存。关闭时移除对应本地占位符，并同步清除选择中已移除的对象。

创建优先采用当前版式，其次采用母版中的对应占位符，复制样式并继承几何；模板源保持不变。没有模板时创建独立本地占位符：默认 Arial 12 pt、黑色、自动缩小，日期左对齐、页脚居中、编号右对齐。三个框的 x 分别为页面宽度的 4%、36%、68%，宽度为 28%；y 为高度的 90%，高为 6%。字体仍由宿主授权 profile 提供。新对象及字段身份沿页面复制规则分配，不与原源冲突。

全部目标页完成文字布局、字体、适配和包/输出检查后一次提交。单个页边对象生成的 XML 最多 1,048,576 UTF-16 单元，事务仍受 4 MiB 历史预算约束；任何目标失败均保留原源、选择和身份分配状态。原生草稿先独立提交。只有单段、单个受支持日期域的本地日期占位符可查询并修改自动设置；混合文字/字段、重复/分组页边对象、未知或带注释的文本源、无法解析的模板和关系、删除锁/外部对象引用、缺字体、越界及旧 revision 继续保护。当前操作修改本地页面，不改写共享版式或母版，也不为以后新增的空白页建立全稿默认值。

默认面板提供日期、页脚、编号开关及应用到当前页/全部页。日期可切换固定文字和自动更新，自动模式可选择三种语言及十三种格式；选项以固定日期示例显示，不由 TypeScript 格式化文档日期。草稿在正文输入期间保持，切页和文档替换后按当前页重新加载。结构及内容替换参考 [ONLYOFFICE setHFProperties](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L1182-L1318)，实现归 [`footer-read.mbt`](../../../modules/formats/src/pptx/footer-read.mbt)、[`footer-content.mbt`](../../../modules/formats/src/pptx/footer-content.mbt)、[`footer-edit.mbt`](../../../modules/formats/src/pptx/footer-edit.mbt)及 [`pptx-footer.tsx`](../../../packages/pptx/src/react/pptx-footer.tsx)。母版编辑继续实施，导入与刷新见[动态日期域显示与刷新](#动态日期域显示与刷新)。

### 动态日期域显示与刷新

导入的简单 `a:fld type="datetime1"` 至 `datetime13` 及 `datetimeFigureOut` 按会话时间生成派生文字，类型比较忽略大小写。支持 `en-US`、`zh-CN` 和 `zh-TW`，语言沿 run/段落/继承格式解析，缺省为 `en-US`。字段结构边界与简单编号域相同。缺少时间、未知语言/格式或扩展结构保留源缓存并诊断；继承及锁定对象也保留诊断。日期域继续拒绝纯文字编辑；专用日期面板/API 可修改简单日期占位符，范围见[日期与页脚编辑](#日期与页脚编辑)。

Wasm/Worker 的 `openPptx`、`createPptx` 接受可选 `dateTime`。平台缺省传入当地时钟的 `YYYY-MM-DDTHH:MM:SS` 日历分量；宿主可显式传入以固定结果。MoonBit 的 `Session::open/create` 接受 `date_time`，不传时保留日期缓存并诊断。核心校验公历日期、1–9999 年、0–23 时及 0–59 分秒；该输入不含时区尾部，也不进行时区换算。格式化由 MoonBit 完成，平台只提供时间分量。

`PresentationEditor.refreshDateFields(dateTime?)` 或 Wasm/Worker 的 `dateTimePptx` 更新会话时间；底层命令携带 revision、profile 和可选 dateTime。默认面板提供“刷新日期域”。刷新先检查活动候选、旧修订、所有可显示日期域的字体及框内布局，再统一更新派生文字并使旧布局失效。失败保留原时间、源、选择和历史。刷新不改变 revision、modified、撤销栈、字段代码、ID 或缓存。原格式保存保持源；预览、PNG 和 PDF 使用最近一次会话时间，打开和显式刷新之间共用同一快照。

源编辑、页面复制、主题/尺寸/版式变化及撤销重做沿当前时间重新解析日期。历史页面记录其计算时间，恢复旧快照时只重新解析过期页面，防止“撤销复制、刷新日期、重做复制”恢复旧值。可显示的版式/母版普通文字及组内日期域同样参与刷新预检；模板占位符仍沿既有版式实例化规则。

格式与地区映射依据 [ONLYOFFICE PresentationField](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/PresentationField.js#L61-L78)、[类型索引](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/PresentationField.js#L286-L365)及[地区格式表](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/commonDefines.js#L4625-L4656)。中文沿其格式表和 [Word 字段解析](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/NumFormat.js#L991-L1033)保留现有结果：`datetime4/6` 中的 `W` 是字面文字，`datetime5` 使用时分秒，`datetime13` 的后备格式在 AM/PM 前保留冒号。已有缓存的独立显式写回、更多语言及备注字段继续实施。实现归 [`date-fields.mbt`](../../../modules/formats/src/pptx/date-fields.mbt)及 [`pptx-clock.ts`](../../../packages/pptx/src/core/pptx-clock.ts)。

### 幻灯片编号字段

导入的 `a:fld type="slidenum"` 按演示文稿 `firstSlideNum` 加从零开始的实际页序生成十进制文字，类型比较忽略大小写。起始编号缺省为 1，接受 0–4294967295；隐藏页保留编号位置。行为依据 [ONLYOFFICE PresentationField](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/PresentationField.js#L187-L220)。

`PptxQuery.firstSlideNumber` 返回当前起始编号。`PresentationEditor.editSlides({ action: "firstSlideNumber", number })` 及同步 Wasm/Worker 的同名修改作用于整稿；number 必须为 0–4294967295 的整数。默认编号面板提供起点及应用按钮，原生文字草稿先独立提交，编号草稿在此期间保持；撤销/重做按源起点更新控件。相同起点不新增历史。只修改演示文稿属性，保留字段 ID、源代码和旧缓存，重新派生全部页的编号；末页显示值可超过起点属性的上限。

受影响字段共用已有文字测量和自动适配，框大小或缩小比例与起点合为一项历史。预检包含隐藏页和继承对象。固定框溢出、未知编号域、修改保护、缺字体、旧修订、活动候选及预算失败原子拒绝。共享自动框需要不同源尺寸时继续保护，待本地覆盖支持后扩展。其他源、资源和选择保持；Canvas、PDF 与保存重开使用相同编号。起点语义参考 [ONLYOFFICE changeSlideSize/getFirstSlideNumber](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L844-L863)，实现归 [`slide-numbering.mbt`](../../../modules/formats/src/pptx/slide-numbering.mbt)及 [`autofit.mbt`](../../../modules/formats/src/pptx/autofit.mbt)。

当前支持带非空 `id`、可选 `rPr/t` 及单个空 `pPr` 的形式。`pPr` 须无属性、子元素、注释或处理指令，文字只含空白。该空节点也适用于简单日期域，原源和缓存保持。字段结构依据 [ONLYOFFICE Fld 读取](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Runs/Fld.cpp#L59-L84)及[字段段落属性导入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L10628-L10670)。字号、颜色和字体沿现有文字解析；派生数字进入查询及 Canvas/PDF 共用的定位输出。重排、复制、删除与撤销重做同步更新，读取和保存不刷新源缓存，也不新增修订。字段所在框继续拒绝纯文字编辑，其他字段、非空或重复段落属性及未知扩展保留缓存并诊断。创建和移除见[日期与页脚编辑](#日期与页脚编辑)，版式占位符创建沿[幻灯片版式](pptx-editing.md#幻灯片版式)；母版直接编辑继续实施。实现归 [`text-fields.mbt`](../../../modules/formats/src/pptx/text-fields.mbt)。

### PPTX 普通表格

读取标准 `a16:rowId/colId` 行列编号扩展，校验对应扩展 URI、叶节点和无符号 32 位编号。它们不影响绘制，文字修改与源保存保留原 XML。未知扩展、额外属性和非法编号继续保护或拒绝。两份 C0 原件的核心布局、样式、文字编辑及精确历史已检查，视觉资格归[测试说明](../testing.md#当前兼容证据入口)。实现归 [`table-read.mbt`](../../../modules/formats/src/pptx/table-read.mbt)，标识定义见 [MS-ODRAWXML CT_Identifier](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-odrawxml/e3f3b4ed-ab09-4eb8-817e-d89c44535e45)。

直接边框与表样式共用画笔校验。支持显式 `cap="flat"`、`cmpd="sng"`、`algn="ctr"`，以及无箭头的 `headEnd/tailEnd`。合法 `round/bevel/miter` 连接保留源，直线共享边的绘制保持。重复或非法端标、真实箭头、其他端帽、复合线及对齐方式继续保护。文字修改保留完整 `tcPr`。原生导入依据 [ONLYOFFICE 表格边框](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L8706-L8714)和 [fillDocumentBorder](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L8062-L8069)，实现归 [table-style-paint.mbt](../../../modules/formats/src/pptx/table-style-paint.mbt)。

`editObjects({ action: "tableDirection", rtl })` 修改所选普通表格的原生 `tblPr@rtl`，`rtl` 必须为布尔值。`table.rtl` 返回有效值，默认面板提供“从右到左表格”开关，编辑权限沿 `sizeReason`。缺省及 false 按从左到右排列，true 将原生首列放到右侧。列宽、文字、单元格身份、跨度和样式保持原生顺序；不等列宽、合并格、绘制、命中与范围高亮共用镜像后的网格坐标，格内文字方向仍由段落及 `tcPr@vert` 决定。查询的行列索引、结构命令的 before/after、复制和范围输入均按原生顺序解释。方向切换保留直接格式和其他部件，重复值不新增历史，失败保留源、选择及重做。完整表格的独立复制保留方向，粘贴后可以分别切换。

物理左/右边框仍对应 `lnL/lnR`，镜像后按原区域优先级、线宽和物理右侧规则解决共享边，并且只绘制一次；边框编辑同步实际相邻格。水平文字在 RTL 表格的左右边界按视觉相邻格导航，上下键先移动格内行，再进入同列相邻行的主格。原生含义归 [Open XML RightToLeft](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.tableproperties.righttoleft?view=openxml-3.0.1)。已核对的 ONLYOFFICE 导入器[跳过该属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L8747)，布局参照 LibreOffice 的[镜像列](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/svx/source/table/tablelayouter.cxx#L706-L717)和[合并格区域](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/svx/source/table/tablelayouter.cxx#L106-L146)，实现归 [table-direction.mbt](../../../modules/formats/src/pptx/table-direction.mbt)与 [table-spans.mbt](../../../modules/formats/src/pptx/table-spans.mbt)。

`fillOpacity` 沿现有对象命令修改表格所选单元格的纯色底色不透明度，接受 0–1，并按 1/100000 步长写入原生 `alpha`。对象模式作用于整表，文字模式作用于当前格或矩形范围；无填充格保持，范围内没有纯色底色时拒绝。零不透明度保留颜色身份，后续可恢复；改底色保留透明度。局部覆盖保留原生主题色和 tint 等颜色变换，其他格、边框、文字及原始表样式保持。`table.format.fillOpacity` 返回共同值或混合值 `null`，无填充格为 1；默认面板复用百分比控件。原生与样式底色沿现有 Canvas/PDF 透明图元输出，跨文稿复制保留底色及独立修改。实现复用 [table-cell-opacity.mbt](../../../modules/formats/src/pptx/table-cell-opacity.mbt) 的颜色片段及既有单元格格式事务，参考 [ONLYOFFICE 单元格原生填充绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableDraw.js#L437-L453)。

`PresentationEditor.editObjects({ action: "insertTable", rows, columns, x, y, width, height })` 和同步 Wasm/Worker 的 `editPptxObjects` 创建普通空表格。位置与尺寸单位为点，沿用对象的有限值及 14400 点上限；行列数必须为整数。网格按整数 EMU 等分，总宽与外框精确一致；每列须保留默认左右内边距外的正文字宽度。初始文字为 Arial 18 点、黑色，单元格为白底及 1 点黑色实线边框。行高不足时按现有字体排版增长，所有生成内容合为一项历史。默认 UI 共用对象的位置和尺寸输入，单独提供行列数。身份分配避开原对象及会话已使用身份，失败不占用身份。

对象模式的现有 `delete` 命令可删除整张普通表格，清除选择，并支持精确撤销重做。锁定、引用和输出预算继续由原对象事务校验；有动画或连接引用时受保护。结构依据 [ONLYOFFICE 表格创建](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L4122-L4176)，单元格属性顺序沿 [TableCellProperties 序列化](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Table/TableCellProperties.cpp#L145-L171)。实现归 [`table-create.mbt`](../../../modules/formats/src/pptx/table-create.mbt)。

表格复用现有对象移动/缩放候选、`duplicate`、层次及对齐/分布命令，支持与形状混合多选；默认指针和移动/缩放控件使用同一路径。列宽、行高按原比例分配到整数 EMU，合计与新外框精确一致。预览同步派生网格，取消恢复原源；提交按文字需要增长行高及外框，并合为一项精确历史。字号、边距、单元格片段及跨度保持。宽度不能耗尽主格的文字区域，移动/缩放锁继续生效。复制分配新对象身份，保留原表及资源，副本单元格可独立编辑。`rotateReason` 及默认控件继续保护直接旋转和翻转；导入及取消组合产生的原生框姿态保留。行为参考 [ONLYOFFICE GraphicFrame.resize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicFrame.js#L599-L621)和 [Table.Resize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L18121-L18336)，网格写回归 [`table-transform.mbt`](../../../modules/formats/src/pptx/table-transform.mbt)。

`editObjects({ action: "tableStructure", operation })` 修改表格结构。`operation` 接受 `insertRowBefore`、`insertRowAfter`、`deleteRow`、`insertColumnBefore`、`insertColumnAfter`、`deleteColumn`、`merge`、`unmerge`。`PptxQuery.table` 返回 `{ object, rows, columns, row, column, firstRow, lastRow, firstColumn, lastColumn, rowHeight, columnWidth, reason, sizeReason, operations, splitReason, format, style }`，行列下标从零开始，范围两端均包含；没有单选普通表格时返回 `null`。`operations` 为上述八项操作各自的保护原因，空串表示可用。对象模式的结构操作从首格开始；文字模式的选择两端跨格时，核心将两端单元格作为矩形的对角，扩展到包含相交合并格的完整范围。当前光标仍使用既有 UTF-16 位置，反向选择不改变范围。默认面板直接使用核心返回的位置、范围和原因，鼠标点击结构按钮保留原生输入焦点。

`editObjects({ action: "tableRowHeight" | "tableColumnWidth", value })` 修改上述范围覆盖的全部实际行或列。`value` 为 0.1–14400 点的有限数值，四舍五入到整数 EMU；不按合并格总宽平均分配。对象模式只从首格及其跨度开始，整表尺寸仍使用对象缩放。其他列宽保持，所有格的文字、格式、跨度及其他部件保持；总宽高同步外框，左上角不动。行高仍是内容适配前的目标，文字需要时沿既有逐格排版增长相关行及外框，不裁掉完整内容。全表宽高各不超过 14400 点，列宽必须留下主格的正文字区域。

组内行列尺寸沿相同命令编辑，输入为缩放后的有效点值。核心按父组横/纵缩放换回本地整数 EMU，保留未选原生尺寸，再按现有内容适配和祖先边界事务提交；非整数组缩放可产生 EMU 舍入差异，查询返回最终有效值。重新应用当前显示值不改源、不新增历史。单元格边距按显示网格验证，放大组的合法小本地列宽不会被误判。`sizeReason` 是尺寸修改的独立保护原因，空串表示可用；`reason/operations/splitReason` 继续描述结构操作，`format/style` 使用各自原因。默认控件分别使用这些核心原因，保留文字/选择锁、动画子目标和尺寸预算。

`rowHeight`、`columnWidth` 返回选中实际行或列的有效共同点值，混合时为 `null`。默认面板分别显示共同值或空白混合提示，显式提交一个尺寸。选择、一次精确历史、无变化、锁定、活动候选、字体、源及输出预算共用既有保护；失败保留原文档。尺寸行为参考 [ONLYOFFICE SetColumnWidth/SetRowHeight](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L19008-L19058)，当前 SDK 使用完整逻辑网格、原生 EMU 和已有内容适配。实现归 [`table-size.mbt`](../../../modules/formats/src/pptx/table-size.mbt)，查询和默认面板仍归上述表格模块。

插入数量等于选中的行或列数。向前插入使用首行/列，向后插入使用末行/列，复制行高或列宽及各格框属性、首段字符/段落格式，文字置空。旧单元格及其他部件保持原源。网格与外框一起扩展或缩小，提交前按既有排版检查行高；插入后选中新格块，删除后光标定位相邻保留格。删除全部行或列时移除整表，并检查整表删除锁和外部对象引用。每次操作合为一项精确历史。模板中的身份扩展或资源链接、锁定、多对象选择和超限修改受保护；动画引用表格内部范围时，修改需先实现引用重映射，当前受保护。失败保留源和选择。行为依据 [ONLYOFFICE 表格命令](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L6659-L6716)、[行插入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9997-L10146)和[列插入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L10512-L10620)。实现归 [`table-selection.mbt`](../../../modules/formats/src/pptx/table-selection.mbt)和 [`table-structure.mbt`](../../../modules/formats/src/pptx/table-structure.mbt)。

本地普通 DrawingML 表格（含支持的组成员）沿现有对象查询返回 `kind: "table"`，单元格文字使用现有文字选择和编辑接口。核心读取固定列宽和行高、纯色或无填充、普通纯色实线/预设虚线边框及不透明度、四边内边距及上/中/下垂直对齐。每格独立裁剪，文字、光标、命中和 PDF 复用公共文字布局。默认内边距沿 [ONLYOFFICE 表格设置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/ChartSpacePrototype.js#L640-L665)；网格和图形框对应关系参考 [Create_TableGraphicFrame](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L4122-L4176)。

单格输入、换段、组合输入及取消共用现有源事务。水平文字需要更多高度时，核心增长对应行及外框，连同文字写入一项历史。撤销、重做及保存保留其他单元格和未改部件。查询按行连接单元格段落，以 LF 分隔。多格范围的复制返回完整格文本，列间使用 Tab、行间使用 LF，格内段落及软换行保留为 LF。范围输入把文字写入原生起始主格并清空其他选中格；删除或剪切仅清空内容，保留网格和格式。范围高亮、空白区域命中和可访问描述均使用核心返回的矩形。组合输入候选使用预览选择，取消恢复完整原选区；提交合为一项历史。折叠光标在单元格边界的删除仍受保护，避免把相邻格段落合并或误清空范围。实现归 [`table-input.mbt`](../../../modules/formats/src/pptx/table-input.mbt)和 [`table-hit.mbt`](../../../modules/formats/src/pptx/table-hit.mbt)。

单选可编辑表格时，既有 `fill`、`stroke`、`strokeDash`、`strokeOpacity`、`textInsets`、`textAnchor` 和 `textDirection` 命令修改单元格属性。对象模式作用于整表的主格，文字模式作用于当前主格或闭合后的矩形范围；延续格保留原属性。填充接受六位 RGB 或 `null` 无填充，保留已有不透明度。边框接受同样的颜色和 0.1–1000 点宽度，设置所选主格的四条边并保留各边不透明度与有效预设线型；`null` 移除。相邻格的对应共享边同步修改，避免另一侧覆盖显示。若共享边只覆盖相邻合并格的一部分，核心原子拒绝，不改到范围外。内边距以点为单位，四边接受 0–14400，左右合计须留下正文字宽度；垂直锚定接受 `t/ctr/b`。字号、段落、非目标属性和部件保持，变化与行高增长合为一项精确历史；重复应用相同直接格式不新增历史。目标填充或边框中的未知注释及处理指令保持受保护。

`strokeDash` 复用形状的 11 种 `PptxDash` 预设和 `null` 恢复继承，范围与 `stroke` 相同。只改各目标边的 `prstDash`，保留源颜色和线宽；空的局部边继续继承原生样式和来源优先级。`borderDash` 返回有效共同值，混合时为 `null`。默认表格面板复用形状线型控件；共享边与部分相邻合并格保护不变。实线、虚线及点线共用原区域优先级，选中的整条边携带自己的线型，按有效线宽换算为点值数组。跨文稿复制冻结直接边和原生样式中的线型，重复粘贴后的表格可分别修改。规则沿 [ONLYOFFICE DashPatternPresets](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Metafile.js#L1767-L1820)，实现复用 [`line-dash.mbt`](../../../modules/formats/src/pptx/line-dash.mbt)及原生表格边框事务。自定义虚线和复合线继续保护。

`strokeOpacity` 修改同一目标的纯色边框不透明度，接受 0–1，按 1/100000 步长写入原生 `alpha`。零不透明度保留颜色身份，之后仍可恢复；无填充的边保持无填充，整组没有纯色边框时拒绝此操作。覆盖采用修改前的实际胜出边，保留有效颜色、线宽、线型，以及原生主题色和 tint 等颜色变换，颜色/线宽和虚线操作也保留既有不透明度。`borderOpacity` 返回有效共同值或混合值 `null`；无边框时为 1，默认百分比控件禁用。区域与直接边框按原优先级、线宽及右/下侧规则选出完整胜出边，透明度不参与重新排名。单条原生合并边若含不同颜色、线宽或线型的胜出分段，透明度修改保持保护，避免把分段外观压成一条边；每段共享边只绘制一次，避免重复混色。直接格式和样式随跨文稿复制保留透明度。实现归 [table-cell-opacity.mbt](../../../modules/formats/src/pptx/table-cell-opacity.mbt)，复用 [shape-opacity.mbt](../../../modules/formats/src/pptx/shape-opacity.mbt) 的颜色片段；原生描边来源参考 [ONLYOFFICE SetBorder](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TextDrawer.js#L1751-L1758)。

`table.format` 返回 `{ fill, fillOpacity, borderColor, borderWidth, borderDash, borderOpacity, left, top, right, bottom, anchor, direction, reason, borderReason }`。混合值为 `null`，无颜色为 `""`，无边框宽度为 0；其他长度单位为点。`reason` 和 `borderReason` 为空表示相应编辑可用，后者单独说明共享边保护。默认面板显示整表或范围、混合值及保护原因，使用同一命令和既有原生输入。读取及写回归 [`table-cell-format.mbt`](../../../modules/formats/src/pptx/table-cell-format.mbt)，共享边归 [`table-cell-borders.mbt`](../../../modules/formats/src/pptx/table-cell-borders.mbt)。行为参考 [ONLYOFFICE 单元格共享边](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L1641-L1868)、[底色与垂直对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L2028-L2115)。

`editObjects({ action: "textDirection", direction })` 对单格、矩形范围或整表写入原生 `tcPr@vert`。direction 接受 `horz/vert/vert270`；默认单元格面板显示三种方向，`table.format.direction` 返回共同值或混合值 `null`。文字整体旋转，四边物理边距及垂直锚定沿交换后的文字平面求值。切换为旋转方向时，将不足 20 mm 的目标主格所在行提高到该值，并同步原生外框；重新应用相同方向不改源。行高、框高和方向共用一项精确历史。

每个单元格的段落持有自己的矩阵，绘制、光标、选择、命中、方向键及 PDF 文字链接共用它。旋转文字在既有行界内排版和裁剪，水平邻格继续按内容增长；边距必须留下正文字宽度。合并及取消合并保留各源格的方向，完整表格复制及组变换沿相同路径。独立任意角度、保持直立和东亚字符直排继续保护。实现归 [`table-layout.mbt`](../../../modules/formats/src/pptx/table-layout.mbt)和 [`text-geometry.mbt`](../../../modules/formats/src/pptx/text-geometry.mbt)，方向与行高依据 [ONLYOFFICE 单元格方向](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableCell.js#L1643-L1667)，变换依据[文字矩阵](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableCell.js#L1132-L1152)。

表格和其他演示稿文本框共用字形塑形的精确字宽。居中位置、相邻格式段、光标和选区使用同一字宽。正文分页沿用 Writer 的整数 twip 度量。Canvas 与 PDF 共用核心排版坐标。[测试说明](../testing.md#当前兼容证据入口)

表格复用既有 `textFormat`、`textAlign`、`textParagraph`、`clearTextFormat` 和 `clearParagraphFormat`，支持当前已交付的字符、段落及列表属性。单格内的文字范围和折叠光标使用格内位置，保留局部 run 和后续输入格式；矩形跨格范围作用于完整主格，包括空段落的后续输入格式，跳过延续格。对象模式作用于整表，亦可与形状一起选择。`PptxQuery.formatting` 和 `paragraph` 只合并实际目标的值，混合值及保护原因沿原接口返回。字号、缩进或间距变化按各格实际宽度适配行高及外框，不改变列宽、单元格框属性和非目标格。编号在各格独立计算，合并主格内各段连续编号。清除直接格式保留既有语言、高亮和链接规则；保留的超链接仍可显示下划线。缺字体、文字锁及预算失败保持原源、选择和历史。选区转换归 [`table-text-format.mbt`](../../../modules/formats/src/pptx/table-text-format.mbt)，复用现有格式写回和逐格排版。行为依据 [ONLYOFFICE 单元格文字属性与清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L6207-L6263)和[单元格段落格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L7763-L7851)。

合并格使用原生 `rowSpan/gridSpan/hMerge/vMerge`，保留完整物理网格。原生首行首列主格持有文字，延续格必须为空；核心校验跨度、覆盖及延续标记。文字位置、复制、绘制和裁剪只包含主格，命中延续区域时定位主格。单个合并格内仍可选择文字。主格宽高为所跨列行之和，水平文字需要更多高度时增长跨度末行及外框。结构依据 [ONLYOFFICE 表格序列化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/SerializeWriter.js#L5900-L5967)与 [TableCell 原生属性](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Table/TableCell.cpp#L118-L138)。归属校验归 [`table-spans.mbt`](../../../modules/formats/src/pptx/table-spans.mbt)。

`merge` 要求范围内至少两个主格，按原生行列顺序把各格段落及字符/段落属性移入起始主格，清空其他主格，并写回标准跨度。合并后的文字整体选中。所涉单元格的局部列表默认值必须为空，段落合计最多 256；其他属性、未选格及部件保留。`unmerge` 要求选中一个合并格，恢复物理单元格；文字留在原生起始主格，其余格为空并保留原框及文字格式。每个物理格的边距必须留下正文字宽度，否则先调整边距或列宽。两项操作均共用行高适配和一项精确历史。行为依据 [ONLYOFFICE MergeTableCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9466-L9602)，实现归 [`table-merge.mbt`](../../../modules/formats/src/pptx/table-merge.mbt)。行列操作允许在跨度边界插入、整体移动合并格或删除完整跨度，切穿其他跨度时受保护。逐项操作保护归 [`table-operations.mbt`](../../../modules/formats/src/pptx/table-operations.mbt)。

`editObjects({ action: "splitTableCell", rows, columns })` 拆分一个主格；`table.splitReason` 返回选择或结构保护原因。行列数为整数，分别接受 1–1000、1–63，乘积最多 4096；1×1 不改源、选择或历史。普通格可增加行，跨行合并格要求新行数不超过原跨度且整除跨度。列按主格总宽的整数 EMU 等分，保留原有网格边界；全表物理列数可能大于请求的逻辑列数。其他格调整跨度，保留文字、框属性和源间隙。原文字留在左上格，新逻辑格继承原格首段文字/段落及框格式。新延续格不复制其他格的链接内容。拆分与必要的行高增长合为一项历史，随后光标定位左上格。模板身份/资源链接、受影响列节点的未知元数据、宽度及预算失败原子拒绝。行为依据 [ONLYOFFICE SplitTableCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9609-L9989)，实现归 [`table-split.mbt`](../../../modules/formats/src/pptx/table-split.mbt)。默认控件归 [`pptx-cells.tsx`](../../../packages/pptx/src/react/pptx-cells.tsx)。单格文字链接复用[文字链接合同](pptx-objects.md#对象超链接)；表格查找替换复用上述字面匹配及事务合同。

普通表格已接通组合、组整体变换、成员移动及完整组原生/系统复制。读取按本地原生框验证网格，显示和候选预览按父组缩放派生格尺寸，保留合并、文字、字号、边距与边框。组内原生文字输入按实际宽度排版；行高换回本地坐标并逐行取整，外框使用同一原生行高之和，沿一项历史更新祖先边界。取消组合保留页面姿态，把缩放后的网格及继承旋转/翻转写回原生框，随后可继续输入和改表结构。完整组系统复制沿既有独立表样式快照，重复副本可分别改文字；组内可直接改格填充、边框、边距、锚定、字符/段落格式及表样式；排版、行高和祖先边界沿同一事务更新。格外观与表样式查询使用各自保护原因，文字/选择锁及动画子目标保护继续生效；行列尺寸控件使用独立的 sizeReason，可直接编辑组内表格；组内插删行列、合并/取消合并与拆格已沿原结构控件接通。核心先将祖先组与成员网格归一到有效点值，再复用原生网格写回、文字适配和组边界更新；归一化与编辑合为一项精确历史，失败保留原包，1×1 拆格不改源。结构和显式尺寸共用组成员变换保护，组锁定时保留独立样式/格式原因。导入的极小缩放无法容纳边距时保留源并诊断，复制或相关输出继续保护。表格组合由本项目既有组矩阵和网格缩放实现；ONLYOFFICE 的[直接表格入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicFrame.js#L542-L549)不允许组合或直接旋转。

支持网格宽高与外框一致的完整矩形表格，最多 1000 行、63 列、4096 格，文字合计最多 32767 UTF-16 单元，继续受包、布局、输出及历史预算约束。不一致的延续格、无法排版的组缩放及其他未支持配置给出诊断并保留原源；非整数跨度按现有数值规则拒绝。更广样式与复杂表格元数据编辑继续实施。实现归 [`table-read.mbt`](../../../modules/formats/src/pptx/table-read.mbt)和 [`table-layout.mbt`](../../../modules/formats/src/pptx/table-layout.mbt)。

#### 表格样式

核心沿 presentation 的 `tableStyles` 关系读取原生 `tblStyleLst`。表格未显式指定 `tableStyleId` 时，样式 ID 保持为空，缺省边使用一磅黑色格线，直接边框格式优先。目录 `def` 原样保留，不为已有表格或导入页补上目录默认样式。此行为由 POI 原件断言和 ONLYOFFICE 10.0.0.170 输出核对。支持全表、两组行/列条纹、首末行列和四个角格；按全表、行条纹、列条纹、末列、首列、末行、首行、右下/左下/右上/左上角顺序叠加。行条纹避开首行，列条纹在首列存在有效样式时避开首列。合并主格按其起始物理行列选择区域，内部共享线不绘制。直接单元格属性、run 和段落默认字符属性逐项优先；表格文字样式在母版及文稿默认字符属性之前生效。

读取纯色/无填充、主题填充引用、不透明实线/预设虚线及主题线引用、字体引用/普通字体、粗斜体和文字颜色。表格背景在单元格下方只绘制一次，透明格可透出背景，背景不透明度不重复叠加。全表的内部横竖边映射到实际网格；相邻边先取可见线，再取较高来源优先级，同层取较宽线，最后取右/下格。共享边按物理网格只画一次，跳过同一合并主格内部。`table.format` 使用绘制后的有效边，合并格一侧存在分段差异时返回混合值。文字、填充及边线进入同一 Canvas/PDF 路径。

内置 `No Style, No Grid`、`No Style, Table Grid`，以及 `Themed Style 1` 和 `Medium Style 2` 各六种强调色，共 14 项。使用原生 GUID、主题色及 tint；源目录中的同 ID 定义优先。`table.style` 返回 `{ settings, choices, reason }`；choices 为 `{ id, name }[]`。`settings: PptxTableStyle` 包含 `id` 和六个必需布尔项 `firstRow/lastRow/firstColumn/lastColumn/bandRows/bandColumns`。ID 使用目录身份并规范为大写，最多 80 个 UTF-16 单元；没有样式时查询 ID 为空。类型从 `wasm/pptx`、`web/pptx` 导出。

`editObjects({ action: "tableStyle", style })` 为单选表格应用完整设置；对象模式、单格光标和跨格选择均作用于整表。默认表单提供目录、六个选项和显式应用按钮。应用清除全部物理格的直接填充、边框和 `tcPr` 边距，保留垂直锚定、文字/段落格式、内容、跨度、网格及选择；同样式可重新应用以清除覆盖。缺少的内置定义写入原生目录；目录、关系和内容类型缺失时一起创建，并用中性默认定义保持其他无样式表格的外观。未知源内嵌标记保护被清除的格式。资源和必要行高适配共用一次精确历史，无源变化不增加历史，字体、锁定、候选及输出失败不提交。

目录最多 256 个源定义，名称最多 1024 个 UTF-16 单元，当前查询连同内置项最多 270 项。未知样式、渐变/效果、条件区域的内部横竖边、自定义虚线及未解析字体配置继续诊断并保护原源。未使用的未知定义保留，不影响已支持表格。预设和优先级参考 [ONLYOFFICE 原生预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L18011-L18200)、[区域合成](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableCell.js#L300-L443)及[应用后清除直接格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L8673-L8743)。实现归 [`table-style-read.mbt`](../../../modules/formats/src/pptx/table-style-read.mbt)、[`table-style-edit.mbt`](../../../modules/formats/src/pptx/table-style-edit.mbt)和 [`table-edges.mbt`](../../../modules/formats/src/pptx/table-edges.mbt)；更多预设、边线类型及样式定义编辑继续实施。

### 演讲备注

`PresentationEditor.editSlides({ action: "notes", text }, slide?)` 和同步 Wasm/Worker 的 `editPptxSlides` 修改指定页的普通演讲备注。`PptxQuery.notes` 返回当前页的 `{ text, reason }`。`text` 是完整备注正文；空串清空，CRLF/CR 归一为 LF，段落用 LF、软换行用 U+2028。每页最多 32767 UTF-16 单元，每段最多 4096，最多 256 段；生成 XML 另限 2 Mi 单元，并继续受包、输出和 4 MiB 历史预算约束。

未有备注时，非空文字创建标准 notesSlide、备注到 slide 的回链、slide 到备注的关系及内容类型，合为一项历史。正文使用 `p:ph type=body`，自带按 notesSz 比例计算的位置与尺寸；已有 notesMaster 时关联该母版，不另建或修改备注母版。备注正文结构参考 [ONLYOFFICE CreateNotes](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Notes.js#L387-L430)；可选母版关系见 [Open XML SDK 约束](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/generated/DocumentFormat.OpenXml/DocumentFormat.OpenXml.Generator/DocumentFormat.OpenXml.Generator.OpenXmlGenerator/Part_NotesSlidePart.g.cs#L242-L244)。已有备注没有正文占位符时，在其形状树追加独立正文并分配未占用身份。

修改只替换正文段落，复用首段段落属性与首个 run 的字符属性。正文框属性、列表样式、其他占位符（含页码字段）、其他部件/关系、外围注释及未知源保留。清空保留备注页和空正文；没有备注时清空、相同文字修改均不增加 revision 或历史。选择、幻灯片内容与对象身份保持，原生输入先按既有队列独立提交。撤销新增备注时保留该部件的 XML 身份分配状态，支持其后修改/清空的完整重做。

备注归属必须唯一并正确回链。共享/外部备注、多个正文占位符、字段或未知正文节点/属性、被改范围内注释/处理指令、修改保护、旧 revision、活动候选及预算失败原子拒绝。保护性查询返回空 `text` 和明确 `reason`，不把未知正文当作可修改文本。页面复制沿已有部件闭包创建独立备注并重映射回链；删除仅回收独占备注，精确历史与保存重开共用同一事务。

默认面板提供多行输入、应用和清空，正文草稿在应用后进入文档；切页按当前备注更新面板。备注不加入幻灯片文字、字体/图像资源准备、查找或静态 PDF，不改变幻灯片 Canvas。日期/页脚归[对应合同](#日期与页脚编辑)，同页演讲者界面归[放映](#放映与演讲者视图)；备注富文本控件及备注母版/打印布局兼容归 [P14](../roadmap.md#p14-兼容与性能已完成)。批注归下节。实现归 [`slide-notes.mbt`](../../../modules/formats/src/pptx/slide-notes.mbt)、[`notes-read.mbt`](../../../modules/formats/src/pptx/notes-read.mbt)、[`notes-create.mbt`](../../../modules/formats/src/pptx/notes-create.mbt)及 [`pptx-page.tsx`](../../../packages/pptx/src/react/pptx-page.tsx)。

### 本地批注与回复

`PptxQuery.comments` 返回当前页的 `{ items, reason }`。条目包含稳定的 `id`、作者 `author`、`initials`、源 `date`、纯文字 `text`、根批注 `parent` 和 `status`；根的 `parent` 为 `null`。现代 `status` 为 `active/resolved/closed`，缺省按 `active` 读取；传统格式为 `null`。传统格式的身份为规范化 `authorId:idx`，2018 现代格式为大写、带花括号的 GUID；调用方把身份视为不透明字符串。支持传统 `p:cmLst`、PowerPoint 2012 单层回复，以及现代格式的 `cmLst/authorLst`、`replyLst/reply` 和 DrawingML 文字，按各格式的源顺序返回。缺失作者、重复身份、悬空/嵌套回复及未知扩展返回保护原因，不把未知源当作可编辑文本。

页面已有批注时沿用其原生格式；空页优先使用已有现代作者表，否则沿用传统作者表；两者都不存在时新建现代格式。两种作者表可以共存，各页只使用一种格式。同名但元数据不同的作者保持独立；新批注的姓名/缩写匹配有歧义时继续保护，不合并不同作者。现代关系使用 `http://schemas.microsoft.com/office/2018/10/relationships/comments` 与 `/authors`，内容类型分别为 `application/vnd.ms-powerpoint.comments+xml` 与 `application/vnd.ms-powerpoint.authors+xml`，XML 使用 `http://schemas.microsoft.com/office/powerpoint/2018/8/main`。现代文字当前支持空 `bodyPr/lstStyle`、最多 256 段、每段至多一个文字 run，以及 `lang/sz/b/i/dirty` 字符属性；更新按段保留这些字符属性。作者的 `userId/providerId`、位置和创建日期原样保留；新作者以本地 GUID 作为 `userId`，显式写入空 `providerId`，不合成外部账号。更新文字保留状态，状态命令只修改原生 `status` 属性。未知状态继续保护。对象/文字锚点、任务、提及、混合 run 和未知元数据继续保护。

同步 Wasm、Worker 的 `editPptxSlides` 和 `PresentationEditor.editSlides(change, slide?)` 共用以下命令：

| action | 字段与结果 |
| --- | --- |
| `commentAdd` | `text`、`author: { name, initials }`、`date`、`parent: string \| null`；创建根或回复指定根 |
| `commentUpdate` | `id`、`text`；只修改文字，保留作者、日期、位置及已知扩展 |
| `commentRemove` | `id`；删除回复本身，或删除根及全部回复 |
| `commentStatus` | `id`、`status: active \| resolved \| closed`；修改现代根或回复状态，传统格式拒绝 |

作者必须由宿主显式提供。默认 UI 从 `EditorOptions.commentAuthor` 读取新批注/回复作者；未提供时仍可读取、修改和删除已有批注。界面提供当前页的批注列表、文字编辑及回复输入，草稿保留至提交；创建时间由平台以 UTC ISO 字符串传入，核心校验日历与时间。核心不读取系统账号或时钟。修改文字保留原日期，导入的缺失日期和原日期文本原样保留。

新文字必须非空，最多 32767 UTF-16 单元，CRLF/CR 归一为 LF。作者名非空且最多 255 单元，缩写最多 32；新作者字段不接受控制字符。每页最多 4096 项、合计 1 Mi 文字单元，每种格式的作者表最多 4096 项。传统索引分配扫描最多 16384 个保留批注，并同时预留作者 `lastIdx`，避免导入索引滞后造成重复。现代身份分配扫描已有批注和作者部件，最多 65536 个节点，大小写归一后预留 GUID；文字生成受 1 Mi 源文本上限保护。回复只指向同页根批注。传统新根位置为 `(0, 0)`，新回复沿用根位置；现代新根使用 `pc:sldMkLst/docMk/sldMk` 页面锚点，复制时重绑定到新页身份。位置和批注文字不进入幻灯片 Canvas 或静态 PDF；当前面板以页面归属展示。

首次创建把批注、作者、两处关系、幻灯片原生批注入口扩展和内容类型合为一项有界历史。删除最后一项保留空批注部件和作者。已有 XML 的外围注释、局部命名空间、日期、位置，以及已知 `threadingInfo`/`presenceInfo` 保持。页面复制为传统批注分配新索引、同步作者 `lastIdx` 并重映射父索引；现代批注和回复分配新 GUID，保留嵌套关系并复用作者。删除页仅回收独占批注，保留全稿作者。共享/外部部件、同页混合或不一致的格式声明、未知文字节点/属性、未知扩展、旧 revision、活动候选和包/输出/历史预算失败原子拒绝。所有操作复用现有页面编辑队列、部件事务及精确撤销重做。

传统回复格式依据 [ONLYOFFICE core Comments.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Comments.cpp#L659-L722) 的 `p15:threadingInfo/p15:parentCm`，作者及根/回复索引依据 [Presentation.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L11145-L11230)。现代格式依据 [Comments.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Comments.cpp#L763-L819)、[CommentAuthors.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/CommentAuthors.cpp#L42-L96) 和 [FileTypes.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/FileTypes.cpp#L63-L75)。未复制上游源码。更广现代文字、提及、协作服务和画布批注标记继续实施。实现归 [`comments-read.mbt`](../../../modules/formats/src/pptx/comments-read.mbt)、[`comments-create.mbt`](../../../modules/formats/src/pptx/comments-create.mbt)、[`comments-edit.mbt`](../../../modules/formats/src/pptx/comments-edit.mbt)、[`comments-modern-read.mbt`](../../../modules/formats/src/pptx/comments-modern-read.mbt)、[`comments-modern-edit.mbt`](../../../modules/formats/src/pptx/comments-modern-edit.mbt)及 [`pptx-comments.tsx`](../../../packages/pptx/src/react/pptx-comments.tsx)。

默认面板为现代根提供解决/重新打开，并显示已解决或已关闭状态；传统根不显示状态命令。同值不新增历史。页面入口使用 `{6950BFC3-D8DA-4A85-94F7-54DA5524770B}` 扩展中的 `commentRel`，必须与当前页关系一致；缺失、孤立或不一致入口拒绝批注编辑。页面锚点必须指向当前页，未知锚点和锚点内的注释继续保护。依据 [ONLYOFFICE Slide.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Slide.cpp#L224-L230)、[Microsoft 原生批注示例](https://learn.microsoft.com/en-us/office/open-xml/presentation/how-to-add-a-comment-to-a-slide-in-a-presentation)、[状态定义](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/bd806e3a-96cf-43aa-9618-81b317c34c61)和[作者字段定义](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/aaddcddb-47d6-434f-ab9c-9feca81ff776)。实现归 [`comments-modern-source.mbt`](../../../modules/formats/src/pptx/comments-modern-source.mbt)；既有批注事务、队列和恢复规则保持。
