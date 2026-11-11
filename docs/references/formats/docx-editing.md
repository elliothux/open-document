# DOCX 会话与文字编辑

[格式合同目录](../formats.md)

## 会话与宿主

DOCX 的同步 `FoundationSession` 与 Worker `FoundationClient` 统一使用 `execute(command)`。`DocxCommand` 与 `DocxResult<C>` 从无状态处理函数推导，字段与返回类型归 [`docx-command.ts`](../../../packages/docx/src/core/docx-command.ts)。下文未限定宿主的操作名及参数列表表示命令名称与字段。`defaultBudget/addFont/inputLimits` 保留独立入口；输入限额归[共享合同](shared.md#输入字节限额)。同步会话用 `close()`，Client 用 `dispose()` 关闭。

`DocumentEditor` 通过函数模块组合领域操作，共用原队列与输入分组。`review` 提供审阅、批注、脚注和概览；`sources` 提供来源、引文与书目，目录使用 `sources.catalog()`；`pages` 提供页面、页眉页脚、目录、域和文档保护；`objects` 提供图片、图形、图表、公式及画笔；`tables` 提供表格编辑；`clipboard` 提供全选、软换行与富文本粘贴；`search` 提供查找替换；`formatting` 提供文字/段落格式、样式、主题和列表。下文省略前缀的宿主操作按这些分组调用。普通文字粘贴、复制、历史、保存、导出、导航和生命周期入口保留在 Editor 上。

`openDocx(engine)` 创建同步 `FoundationSession`；浏览器使用 `FoundationClient.open(engine, workerUrl)`，每会话独占 Worker，一次只允许一个请求。`dispose()` 终止 Worker，取消等待中的请求；同步 Wasm 调用本身不支持抢占取消。创建失败、非法打开或替换失败后可以继续使用未提交的会话；成功打开的会话只拥有一个 DOCX。

`defaultBudget()` 从 MoonBit 返回默认值；打开时必须显式传 `Budget`，可以收紧。`openDocx`/`query` 返回派生快照，修改快照不会改变文档；`replaceNode(id, revision, text)` 按已查询的文字、内联控制或图片片段写入文字，与逻辑范围命令共用校验、提交与历史，ID 在该会话内稳定。它保留相邻未知结构，并保留合法 XML 文本中的 CR 等字符，不赋予该段落可视编辑能力。成功内容变化增加 revision；无变化不增加。`saveDocx()` 返回新字节，不改宿主输入、不清空历史。保存失败可能留下已核验的读取缓存，但不提交编辑或输出。`close()`/`dispose()` 释放核心/宿主引用，后续访问报错。

## P4 当前编辑 API 切片

只读 DOCX Flow 的段落包含 `nominalSize`（pt，`0 < size <= 1024`），由核心按默认、段落样式及 `pPr/rPr` 的段落标记字号计算。布局用它计算空行、单元格及空页眉末段的间隙。仅含浮动对象或区域分隔符的空行，使用段落标记字号与字体度量，自动及固定行距沿普通空段规则；浮动对象不占行内宽高。主题字体预检包含锚定段落所用字体，缺少资源时保留源与历史。空行语义依据 [ONLYOFFICE 段落标记度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js#L1283-L1343)。缺省自动行距为单倍。历史产物与当前定向验证的范围归[测试记录](../testing.md)。

历史产物已在 macOS/Chromium 使用现有豆包拼音完成中文提交、取消、撤销重做和绑定 revision 的保存；其他归档产物另通过普通 Latin 系统输入、撤销/重做及独立保存。R0 后的定向检查覆盖组合候选与取消，未重做系统中文输入验收。各记录分别绑定自己的产物，不扩大为所有输入法或 OS 候选窗几何支持；证据入口见 [P4](../../implemented/p4-docx-editing.md#验证依据与边界)。沿用现有输入法；Windows/Word 和 VoiceOver/语音输入不在验收范围，保留基本键盘/AX、源保真及失败恢复检查。

`shape()` 另返回字素边界的 `carets: { offset, before, after }[]`，offset 为 UTF-16，坐标沿用 shaping 的 CSS px；`before` 对应前一逻辑内容侧，`after` 对应后一侧，BiDi 交界可不同。连字优先读取 GDEF 默认设计坐标，缺少匹配数据时只分配该 cluster 的 advance；组合符没有额外停靠点，空文本返回 offset 0。

核心内部布局保留最终行的 carets，坐标为页面 point。宿主通过命中和光标查询获取几何。DOCX 连字光标按 LibreOffice MSO1 的每 pt 120 个整数设备单位构造 GDEF 分量宽度，差值累计到同一塑形 run 的后续光标；最终段内位置截断为整数 twip。公开字体探针仍返回原设计坐标，字形 advance、绘制及行宽不因光标取整而改变。`hitTest(layoutId, page, x, y)` 和 `caret(layoutId, position)` 返回绑定 revision/layout 的页面、行、坐标、高度及逻辑位置，不修改选区或历史。软换行前侧定位上一行，后侧定位下一行；验证范围见 [P4](../../implemented/p4-docx-editing.md#验证依据与边界)。过期或已因内容/资源变化失效的布局报 `stale-layout`，未知页面报 `invalid-page`，非有限/页外坐标或无文字页面报 `invalid-position`。不可安全编辑的图片或段落返回 `editable: false`、`position: null` 和原因。未解释属性的只读原因由 DOCX Flow 按段落及默认样式/表格/节上下文派生，随布局保留；局部段落诊断不禁止无关正文。 方向区段独占一行时仍使用其自然光标度量；因下一方向区段换行而保留的前行文字区段也独立计算。其余可复用的单文字区段保持整行高度，不能按 run 数量一律判成整行；自然高度继续按同页段落底部裁剪。

CJK 字体的左到右 DOCX 文字采用固定 ONLYOFFICE 10 的 Word 光标度量。72 pt Noto Sans SC 的原生光标高为 135.504 pt；100 pt 固定行中的光标可超出行框。该路径的选区保留实际文字边界，不为软换行补满行宽。复杂双向文字及方向控制字符继续使用已验收的 Writer 区段路径。原件和两份 Writer 捕获保留；新独立捕获及生成器归私有 `p4-caret-height-onlyoffice.json`、`p4-script-spacing-onlyoffice.json`。公开字体探针和幻灯片度量保持各自合同。

`selectionGeometry(layoutId, selection)` 返回 `{ layoutId, revision, rects }`，矩形携带页面、行及 point 坐标/宽高。普通逻辑范围按字素两侧的塑形坐标映射，只合并实际相邻区间；同段跨页或含高于段落基准方向的区段时，按固定 LibreOffice 的端点所属区段和自然度量构造区域，保留垂直分区及跨行溢出，再裁剪到各页段落框。跨页保留首框剩余区域、中间整框和末框前缀，不人为在最后一行分割整框区域。内部区域用整数 twip；公开塑形边界和整行高度保持既有精度，其余细分区域按原生整数矩形转换。范围继续到下一行、页或段时，按段落基本方向延伸到行可用区边界；同 offset 的软换行前后侧以实际结束行区分。反向结果相同、折叠为空；普通零宽字素保留零宽矩形，原生区段拆分可保留一个 twip 的边界区域。跨段嵌套范围仍用现有逻辑区间，其原生独立几何尚未验收；不显示段落标记，不赋予跨段写回能力。查询验证端点和当前布局，不改变选区、文档或历史。

`navigateDocx(revision, layoutId, direction, extend = false)` 返回 `{ state, caret }`，使用核心当前选区。方向为 `left/right/up/down/home/end`，左右按逻辑字素顺序移动，Right 到达用 before、Left 到达用 after，Home/End 到当前行逻辑首尾；End 的逻辑尾若同时是下一页同段入口，显示下一页并保留基础方向，同页软换行保持前侧；非折叠选区无 Shift 时，Left 收拢到逻辑起点，Right 从逻辑末端继续前进一个逻辑字素步骤，文档末端保持边界。上下保留目标 x、优先同单元格，离开单元格时排除水平区间不重叠的旁列。`extend` 保留 anchor；成功只改变选区，不增加 revision/历史。显式选区、编辑、横向移动及换布局重置垂直目标，非法方向、旧 revision/layout、无选区或受保护目标原子失败。行携带段落方向、正文/单元格身份和可用水平区间，placed run 携带段落起点，导航复用最终 shaping/BiDi 坐标。验证范围见 [P4](../../implemented/p4-docx-editing.md#验证依据与边界)。

`deleteDocx(revision, direction)` 的方向为 `backward` / `forward`。已有范围整体删除；折叠选区按逻辑前/后扩展字素删除，复用范围事务和历史。组合符与 surrogate 不拆开。段首 Backspace/段尾 Delete 可合并同一正文或单元格内的相邻普通段落；文档首尾保持 revision、源和历史不变。折叠光标越过单元格边界、跨表格或受保护内容时报 `protected-content`；已有整格选区的清空归[跨格内容输入与清空](docx-tables.md#跨格内容输入与清空)。

`selectAllDocx(revision)` 返回普通 `EditState`；`DocumentEditor.clipboard.selectAll()` 使用同一核心命令。正文位置（含单元格）全选主文档正文，文本框位置只全选当前文本框；无选区时选择正文。范围保留首尾空段落、逻辑对象占位和 UTF-16 端点，不把嵌套文本框文字并入正文。全选结束连续输入分组，重置待输入格式与纵向导航目标，只改选区，不改源、revision、历史或重做分支。默认文档原生输入区域的 Ctrl/Cmd+A 使用该命令，保留当前显示页；组合期间和不可用状态不发送全选，面板输入框与 PPTX 沿各自路径。旧 revision、活动候选/手势、关闭会话及受保护端点保持原子失败；全选继续使用既有范围复制与修改保护。页眉页脚及注释正文沿各自独立入口。实现归 [selection-all.mbt](../../../modules/formats/src/docx/selection-all.mbt)和 [text-input.ts](../../../packages/web-core/src/text-input.ts)，依据 [ONLYOFFICE 文档全选](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L8099-L8148)、[正文端点](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L21753-L21775)及[文本故事](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/DocumentContent.js#L7003-L7031)，未复制上游执行代码。

`editState()` 返回 revision、选区、撤销/重做可用性、历史容量与受影响段落；`selectDocx(revision, selection)` 仅更新选区。`replaceRange(revision, selection, text, inputGroup?)` 可跨 run，以及同一正文或单元格中连续的普通段落；`undoDocx(revision)` / `redoDocx(revision)` 恢复内容和选区，revision 继续单调增加。`selection` 保留 anchor/focus，每个位置包含稳定 paragraph ID、段落 UTF-16 offset 与 `before` / `after` affinity；范围按 XML 顺序排序，起点 affinity 决定 run 边界的插入格式。所有命令由 MoonBit 验证，TS 负责平台输入、转发和字节转换。

位置还可包含 `bidiLevel`（0–126 的整数）与 `frameStart`（大于 offset 的段内字素边界）。`frameStart` 保存导航保留的续接页框起点；光标查询只接受逻辑位置恰好位于该续接页框前一个字素的偏好，不能指向任意页。它只影响光标几何和导航，复制、输入、删除及选区矩形仍按逻辑 offset 计算。内容修改清除当前页框偏好，undo/redo 恢复完整选区元数据；只读查询、保存及失败不改变它。缺省字段使用原 affinity 和当前方向层级计算，不保留另一套状态或几何缓存。

编辑提交与后续布局是独立操作：提交成功后布局失败不会自动恢复旧源。浏览器停止输入，但用户可以明确 Undo；宿主排空原队列、取消其暂态组合，并核对当前 revision 后撤销一项历史和重排。失败仍保留停止状态，已完成的明确撤销不伪装为未发生；外部 revision 改动须先恢复，不自动撤销他人的编辑。恢复期间重复请求拒绝，销毁等待已接受的恢复，调用者 client 保留。

`selectedText(revision, selection, cut = false)` 返回核心只读纯文本，按 XML 顺序提取正/反向普通范围，跨段以 LF 分隔并保留空段，折叠范围返回空串。同表跨格提取所选整格，分隔规则归[跨格纯文本剪贴板](docx-tables.md#跨格纯文本剪贴板)。它沿用字素、位置、revision、容器及内容保护检查，未知内容整体拒绝；不改变选区、revision、历史或布局。输出最多 65536 UTF-16 单元（包括 Tab 和 LF），超限报错而不截断。复制与结构写回共用范围顺序/保护检查；只有写回额外检查移动结构及格式。宿主不从页面文字重建选区。

段内边界使用 Unicode 13.0.0 扩展字素，跨文本节点的组合符与 ZWJ 不可拆开；修改后重新合并的字素会将光标推进到合法边界。普通空段支持 offset 0 的输入：优先在第一个已有空 run 创建 text，保留其格式；没有 run 时在段末创建普通 run/text，保留段落属性、现有前缀和非目标源片段。空段身份来自正文 `flow().paragraphs` 或 `flow().tables` 的单元格段落，不能从尚无 text 的 `query().texts` 推断。两端都在正文、完整包住普通表格的范围可沿下文[正文富文本片段](docx-tables.md#正文富文本片段)处理。部分跨入单元格、跨不同表格端点、CR、未支持的域/修订/未知内联标记及受保护容器整体拒绝。受支持的行内图片、普通书签及跨格内容操作分别沿下文合同处理，未修改的源保留。普通正文与顶层表格单元格内的事务可用；不表示带布局诊断的文件已经可视编辑。

`replaceRange` 将实际 LF 作为段落分隔，可替换折叠、段内或跨段正反向范围，首尾/连续 LF 产生空段；新段仍在原 body/单元格内，光标到最后插入文字末尾，并对字素拼接推进到合法边界。原段及移到新段的存量节点保留身份；新节点获得单调 ID。新段继承已支持的段落属性和边界 affinity 选中的字符格式，显式关闭直接或继承的段前分页。未知属性、编号、节或不可安全编辑内容整体拒绝。多分隔替换是单条历史，返回原范围与全部新增段的受影响 ID；撤销删除新段并恢复原字节，重做恢复同一组新 ID。连续输入使用核心保留的目标 text ID 继续同一字符格式；显式选择/导航、删除、外部修改、undo/redo 和关闭终止它，保存或失败不终止。字符格式的连续目标与显式输入组分工不同，均不维护第二份文档内容。

候选 XML 与包预算校验成功后才提交状态。XML Document 是正文内容的唯一权威，Session 已删除文本覆盖表；解析顺序与稳定 `Node.id` 分离，结构插入不重编号相邻节点，删除身份不能继续查询。局部源补丁核对前片段、重放原身份并保留精确 XML；撤销全部改动后保存原 OPC 字节。文本节点、段落属性及命名空间仍由当前解析结果派生，不维护可独立修改的第二棵树。

跨段替换保留前段身份和段落属性，删除中间完整段落，将右侧存活 run/text 移入最终插入段并保留身份。其有效 namespace 与字符格式来自现有 XML/样式解析；上下文变化时固定受支持字体、字号、颜色和四种 bold/italic/script toggle，并保留已解释的语言与 script 属性，全局 styles/theme part 不变。无法清除的未指定继承属性、重复/错置属性、编号、节或未知结构整体保护。一条 XML 候选同时包含叶文本和结构补丁，一次提交一项历史；撤销/重做恢复原字节、身份及选区。

历史保存局部前后源片段、相关节点身份和选区，undo/redo 共计最多 100 项、4 MiB UTF-16 源片段 payload，单命令最多 65536 UTF-16 单元。payload 包含转义、属性及结构标记，不包含数组/节点身份与运行时分配开销；因此含转义的输入可能比纯文本计数更早达到上限。过大的单项整体拒绝，容量不足淘汰最旧完整项，可用边界与计数随结果返回。这些是实施期的安全上限，尚未完成实测校准与性能验收。当前每次提交仍重解析全篇候选 XML，没有声称局部编辑耗时或内存已达标。多分隔片段在字符串构造前检查复制放大，并继续按整个命令检查 XML、包与历史预算。连续普通输入已按下述显式输入组归并；纯文本剪贴板、组合核心/API 与 Chromium 事件宿主、段落塑形复用与稳定点分页已接入。系统输入记录的产物与范围见本节开头；当前 R0 产物未重做系统输入验收，候选窗几何及校准性能仍未测。

组合 API 使用当前已确认选区和 revision；`beginComposition` 返回单调正 i32 `compositionId`，后续更新/提交/取消必须同时匹配身份与 revision。暂态只持有原文档和一个当前范围候选，不累计中间历史；query/Flow/几何读取候选，`EditState.selection` 返回候选光标，`compositionId` 非空，但已确认 XML、选区、revision 与 undo/redo 不变。更新为空或等于原选中文字时显示原文档与原选区。最终非空文字重新经同一范围事务提交，最多一项历史；空结束/取消/同内容 no-op 保留源字节、选区与 redo。开始结束普通输入组；更新及结束继续校验 XML、65536 UTF-16 单元、包输出和历史预算，CR/tab/LF 拒绝，失败保留上一个合法候选。成功开始/更新/取消/结束均废弃旧布局身份；组合期间普通选择/编辑/导航/复制、undo/redo、保存和 PDF 返回 `busy`，错误/过期身份返回 `stale-composition`，关闭释放候选。Chromium CDP/受控更新、结束、空取消及在途宿主销毁已验证；核心候选光标定位平台输入元素，成功候选和结束必须重新取得布局，不能只按 revision 判断。组件清理需 await dispose 后再使用/关闭 client；错误恢复先取消自身候选。R0 后的定向检查再次覆盖候选提交、取消与恢复；系统输入和候选窗几何的验证边界见本节开头。

宿主接受 `compositionend` 后，只消费一次最终文字相同、类型为 `insertCompositionText` 且非 composing 的尾随 `input`，不重复提交核心事务。键盘、beforeinput、新组合、失焦、保存、取消或错误清除这一关联；错误文字、类型或重复通知仍按未支持输入处理。Chromium 受控事件回归验证提交和错误边界。该关联最多保留一份命令预算内文字，不代表堆峰值或系统输入法验收。

`inputGroup` 是可选的正 i32 组号；省略时编辑命令独立成项。组号仅用于非空、无 LF 的普通输入，首项可替换支持的段内/跨段范围；核心仅在后续折叠选区等于已确认当前光标、上一项光标连续且组号相同时归并。单命令仍逐次增加 revision，整组 undo/redo 完整回放候选后一次提交、一次增加 revision，恢复首项前/末项后选区及节点身份。显式选择/导航、删除、未分组编辑、LF 输入、undo/redo 和关闭结束旧组；失败保持已确认组，核心保存不清空组/历史。组 payload 超过 4 MiB 时开启新完整项，整个历史仍按总 payload/100 项淘汰最旧完整项，文档文字保持；`historyEntries/historyBytes` 显示新的可撤销边界。宿主另在失焦、输出屏障和恢复时换组，并在接受排队意图时固定组号。当前组保留各次局部补丁，undo/redo 逐补丁重解析 XML；尚无校准延迟或峰值内存通过。

`DocumentEditor` 已提供有限浏览器输入宿主，与只读 `DocumentPreview` 共用页面绘制、图片预算和释放。调用者独占交付已打开的 client，宿主不维护文档树。点击、拖选、基本键盘输入、选区、删除及 DOCX/PDF 输出经最多 64 项意图队列发送；只移动光标不重建文档布局。默认 UI 的标尺、目录和批注在已接受输入排空后刷新最新状态，过期请求退出，避免自动查询挤占输入队列。输出携带确切 revision，PDF 绑定已完成的 layout ID，当前 revision 与最近输出 revision 分开显示。Tab 可首次进入当前页的可编辑位置，光标滚动可见。主指针拖选通过核心命中/选区 API，两轴边缘滚动按原页序跨页；空白页保留真实端点，末次坐标先于输入与输出，取消/失焦/捕获丢失停止滚动。同段内相邻显式分页符合并为一次布局分页，跨 run 也适用，保存仍保留每个原始分页符；正文、普通换行或独立段落分隔的分页不合并。这是维护者选择的固定 LibreOffice 行为，不授予 Microsoft Word 兼容性。失败需显式恢复，销毁保留原宿主 DOM 和调用者 client；不保证取消已在途核心事务。实际支持与暂未接收的输入见[开发说明](../development.md)。

节的 `w:cols` 与 `w:docGrid` 分别见[分栏](docx-pages.md#分栏)和[正文行网格](docx-pages.md#正文行网格)。段落 `w:adjustRightInd` 在无字符网格时不改变右缩进，保留合法开关。节 `w:noEndnote` 在没有尾注引用或显式关闭时保留，实际尾注抑制仍诊断。开关校验值、属性、子节点和重复声明。插入尾注若使抑制生效，现有候选布局检查原子拒绝，保留文档和历史。

`w:proofErr` 的四种拼写/语法范围标记不绘制正文。读取和普通文字修改保留标记，校验其空内容、单个 `w:type` 属性及合法枚举。额外属性、文字和子节点继续保护。没有结果区、按 `begin/end` 完整闭合的 `BIDIOUTLINE` 可原样读取，接受缺省或 `\* MERGEFORMAT`；它不产生可见结果。其他指令、开关及有结果区的变体仍须实现对应字段语义。实现归 [proofing.mbt](../../../modules/formats/src/docx/proofing.mbt)及 [running-fields.mbt](../../../modules/formats/src/docx/running-fields.mbt)。

字节在 Worker 边界使用 structured clone。字体通过内部 `foundation_add_font` 导出，以每字符一个八位值的字符串传入核心。DOCX 和图片继续使用每操作一个 JSON/Base64 批次，输出反向转换。两种输入均需临时字符串和核心字节，不是零拷贝；原预算保持。轮廓通过 ASCII path 批量发送：`shape()` 返回缓存增量，`layout()` 返回可独立绘制的页结果和当前缓存资源；Canvas 按 key 复用 Path2D。一个 `CanvasRenderer` 必须绑定同一个核心会话的完整生命周期；`dispose()` 后不得复用。宿主负责展示诊断及提供可访问的文本/状态，Canvas 探针没有完整文档无障碍导航。

## P10 当前格式编辑

样式、主题、列表与格式刷通过 `DocumentEditor.formatting` 调用，包括 `styles/createStyle/updateStyle/deleteStyle`、`themeColors/themeFonts`、`lists/editList/updateListLevel` 和 `captureFormat/applyFormat`。该控制器沿用宿主的选择、输入分组、队列和历史事务。

`FoundationSession/Client.execute({ operation: "queryFormatting", revision, selection })` 返回字符与段落属性。每项使用 `{ kind: "value", value }`、`{ kind: "mixed" }` 或 `{ kind: "unavailable", reason }`，同时返回 revision 和限制原因。`EditState.formatting` 包含当前选区的同一查询；没有选区或组合进行中为 null。查询只读取目标段落与继承样式，不要求解析无关图片。

`setCharacterFormat(revision, selection, format)` 支持 `family`、`size`、`spacing`、`color`、`bold`、`italic`、`underline`、`strike`、`highlight` 和 `vertAlign`。字号为 0.5–1024 pt 的半点增量；颜色为六位 RGB 或 `"auto"`。`underline/strike` 为布尔值，写单下划线与单删除线；`vertAlign` 为 `"baseline" | "superscript" | "subscript"`。`highlight` 使用 OOXML 的 `none` 和十六种命名颜色，Wasm/Web 的 `HighlightColor` 与 `highlightColors` 提供类型和完整选项；`none` 关闭高亮，null 恢复继承。

导入的 `w:caps` 沿样式和直接字符属性继承。共享 `TextStyle.caps` 控制大写字形度量、绘制和缓存；源文本、UTF-16 位置与选区保持原义。大小写复用已固定的 Unicode 数据；扩张映射按 [ONLYOFFICE TextShaper](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/TextShaper.js#L80-L90)取首个大写字符，例如 `ß` 显示为 `S`。共享布局的语义文字与 PDF `ActualText` 使用显示大小写，保留字段和行内对象的替代文字。现有格式操作保留该属性，尚无独立编辑控件或格式补丁。

`spacing` 是以 pt 表示的字符间距，范围为 −1584–1584，须能表示成整数 twip。正值扩展，负值紧缩，0 使用正常间距，null 清除直接定义并恢复继承。核心读取和写回原生 `w:rPr/w:spacing`，默认值为 0。格式查询、折叠处后续输入、格式复制、正文片段、样式修改和清除直接格式使用同一属性；默认格式和样式面板提供数值控件。每次实际修改沿现有事务提交，撤销、重做和保存重开保留原生定义。HTML 与 Markdown 的带格式片段输出 `letter-spacing`，逻辑文字保持。

共享塑形层在每个塑形簇后增加间距，簇的总前进宽度下限为 0。非零间距关闭可选 Latin 连字，保留阿拉伯文标准连字和连接塑形；簇内光标沿调整后的宽度分配。该宽度参与混合片段、换行、分页缓存、装饰与选区，Canvas 和 PDF 使用同一绘制结果。依据 [ONLYOFFICE 间距度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/TextShaper.js#L194-L247)及[阿拉伯文标准连字](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/TextShaper.js#L112-L119)。实现归 [`shape.mbt`](../../../modules/layout/src/shape.mbt)和 [`format-model.mbt`](../../../modules/formats/src/docx/format-model.mbt)。

`setParagraphFormat` 支持 `align: "left" | "center" | "right" | "both"`、`before/after/left/right/first`、`line`、`pageBreakBefore`、`keepLines`、`keepNext`、`widowControl` 和 `rtl`。`both` 为两端对齐，写回 OOXML `w:jc`；默认 UI 提供同名按钮。距离单位为 pt，须能表示成整数 twip；范围 0–1584 pt，`first` 可为负值以设置悬挂缩进。`line: { rule, value }` 使用 OOXML 整数单位：`auto` 为每行 240，取值 120–2400；`exact/atLeast` 为 twip，取值 1–31680。UI 显示多倍行距或 pt，确认后转换为这些单位；清除段落直接格式也清除行距。

`keepNext: true/false` 设置或关闭“与下段同页”，null 清除直接定义并恢复样式继承。格式查询与 Flow 返回有效布尔值，默认格式和样式编辑面板提供同名字段；格式复制、拆段、样式应用及清除直接格式沿现有路径处理。连续开启的正文段落与后续末段开头行一起换页；末段开启孤行控制时至少保留开头两行，三行末段若整段可放入则保留全段。末段同时启用 `keepLines` 时保留其全部行。段前/后距及行距参与所需空间，空间可容纳链时省略阻碍其放入页首的段前留白。整页放不下的链按剩余可容纳部分逐步拆分，不循环回退或创建空页；显式段前分页及段内分页符终止该链。

段落链成为分页缓存中的一个块，后段变化会使前面的保留段落重新分页。普通可拆表格行内，同一单元格的相邻段落使用相同保留规则；超长链继续拆分，精确行高保持裁剪，跨格/跨行不链接。正文链可延伸到紧随表格的首个可放片段。可拆普通行按实际最小片段保留；禁止拆行、精确行高及首个纵向合并组按完整高度计算。首行显式分页优先；不能与前段合放的超长首行沿既有拆分规则继续，不反复移动前段。首行内容、高度、列宽或边框变化也使前段重新分页。预判与实际分页共用 [`table-measure.mbt`](../../../modules/layout/src/table-measure.mbt) 和首片段计算，联动归 [`table-keep-next.mbt`](../../../modules/layout/src/table-keep-next.mbt)。参考 [ONLYOFFICE KeepNext 回退规则](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/DocumentContentElementBase.js#L293-L340)及[向前失效处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L3058-L3078)，复用既有度量与分页预算，未引入旧版排版模式。实现归 [`keep-next.mbt`](../../../modules/layout/src/keep-next.mbt)。

`widowControl: true/false` 设置或关闭正文孤行控制，null 清除直接定义并恢复样式继承。DOCX 缺省为 true，沿 [ONLYOFFICE 段落默认值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L16577)；Flow 和格式查询返回有效布尔值。默认格式/样式面板、格式复制、样式应用、清除直接格式和拆段共用既有路径，非法/重复/嵌套标记仍保护源内容。

正文自动断页尽量在两端各保留至少两行。三行段落面临单行拆分且整页可容纳时，整体移至新页；四行及以上若只剩一行在末页，且末两行可同页放入，则向末页多移一行。按实际行高和页首行距度量，空间不足两行时保留有界拆分回退；必要时省略空页上阻碍首段放入的段前留白。显式分页符优先，含显式分页的段落沿原规则。超长“段中不分页”段落仍拆分；“与下段同页”预判包含末段的孤行要求，后段变化向前使保留链失效。当前规则应用正文，格内和页眉保留有效属性并沿原排版规则，不额外施加正文孤行约束；对应 [ONLYOFFICE 正文孤行处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js#L1849-L1887)。实现归 [`widow-control.mbt`](../../../modules/layout/src/widow-control.mbt)，复用现有行/页预算与统一绘制输出，不引入回退循环。

`keepLines: true/false` 设置或关闭“段中不分页”，null 清除直接定义并恢复样式继承；查询与 Flow 返回有效布尔值。默认格式面板和样式编辑面板共用现有命令，格式复制、拆段及清除直接格式也包含该属性。正文段落不能放入当前页时先整体换页；超出一页时在新页正常拆分，不重复尝试。页首空间不足时省略使整段无法放入的段前留白；显式分页符优先，含分页符的段落沿原分页规则执行。可拆的普通表格行按单元格段落保留整组行；整页放不下的格内段落继续拆分，精确行高仍裁剪。重复表头的空间检查包含待放段落，属性变化参与分页缓存失效。规则参考 [ONLYOFFICE KeepLines 分页](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js#L2545-L2590)的现代文档路径；不新增旧 Word 分页模式。不等宽栏按下文使用各自区域宽度续排；多节继续实施。

`FoundationSession/Client.execute({ operation: "styles", revision, kind })` 与 `DocumentEditor.formatting.styles(kind)` 返回现有样式目录：`{ revision, truncated, styles: [{ id, name, reason, basedOn, canDelete, canReset, linked }] }`，`kind` 为 `"paragraph" | "character"`，每类最多 1024 项。`basedOn` 为直接基础样式 ID，无继承时为空串；`canDelete` 表示已支持且未标为默认的自定义样式；`linked` 表示存在样式链接，`canReset` 表示有已支持的格式重置规则。不可应用的样式带原因，默认 UI 禁用对应选项。该接口替代原段落专用目录入口。

`rtl` 使用布尔值写回 `w:bidi`，null 清除直接定义并恢复继承。有效方向参与混合查询、格式复制、样式修改、拆段、历史与保存；默认 UI 提供方向开关。派生 `Paragraph.rtl=true` 指定 RTL 段落基准方向，false 保留既有的 Unicode 自动双向文字计算；本次未增加 run 级方向覆盖。制表与边界坐标归下文。格式、样式或设置修改引起重排时，核心清除已失效的双向层级与跨帧提示；撤销保留修改前选择。双向边界的 `before` 光标跟随前一片段，`after` 跟随后一片段，两者可位于不同视觉位置。

`setParagraphFormat({ style: id })` 校验样式及继承链，清除已支持的段落直接属性后应用样式；保留文字直接字符格式。同一补丁中的显式属性继续覆盖样式。应用默认样式时省略直接 `w:pStyle`；`style: null` 只清除样式引用并恢复默认样式继承。行为依据 [ONLYOFFICE 的段落样式应用](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js)。

`setCharacterFormat({ style: id })` 在目标范围写 `w:rStyle`，保留直接字符属性；`style: null` 清除引用，恢复段落继承和原有直接属性。跨 run 范围沿原边界拆分，折叠范围只设置后续输入样式，随实际输入或组合提交一项历史；取消组合保留输入意图。空段落标记的字符样式也参与查询与显示。行为依据 [ONLYOFFICE 的 Run 字符样式设置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js)。新建文档带 `DefaultParagraphFont`、`Emphasis` 和 `Strong`，继承与粗斜体切换沿已有 OOXML 规则；宿主须为最终组合提供字体 profile，不能只准备样式单独使用的字形。

两类查询均包含样式 ID 与混合状态，格式复制只捕获属性值，不复制样式 ID。未知属性、循环继承、跨类型继承及不支持的值拒绝应用，文档与历史保持原状。应用可一次撤销，支持保存重开和相同布局的 PDF。

`FoundationSession/Client.execute({ operation: "updateStyle", revision, key: id, format: update })` 与 `DocumentEditor.formatting.updateStyle(id, update)` 修改现有样式。`DocxStyleUpdate` 使用 `{ character, paragraph, name?, basedOn?, reset? }`。两类格式支持现有字段，不能包含 `style` 引用。字符样式只接受空的段落补丁。省略字段保留直接定义，null 清除定义并恢复继承。粗体、斜体和删除线的布尔值表示样式在文档默认值及 `basedOn` 链上的有效值，核心换算 OOXML toggle，分别处理复杂文字的粗斜体。名称只改变显示名，保留稳定样式 ID；名称须为非空、最多 200 UTF-16 单元的有效 XML 文字。

`basedOn` 指定同类型、已支持的基础样式；null 移除直接继承引用，省略时保留。更换基础样式保留原有直接定义，不固定旧基础样式的有效值。同一补丁的粗斜体、删除线和制表位按新基础样式计算。核心拒绝循环、跨类型、未知及超过 64 层的继承，并检查原本可用的依赖样式和正文组合。继承、名称与格式修改合为一项历史，撤销恢复完整源内容。行为参考 [ONLYOFFICE 样式继承与历史](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js)。默认 UI 的基础样式列表与当前样式类型一致，也可选“无基础样式”。

样式修改保留元数据、注释与未改正文。核心先检查候选、原本可用的依赖样式及正文直接属性的组合，再合并正文和样式 XML 校验包预算，一次提交 revision 和有界历史。失败不改变正文、部件、选择或历史；撤销/重做也先完整回放全部候选。输入、组合和保存使用同一组已提交部件。共享修改最多处理 4096 个样式，继承链沿既有 64 层上限。默认 UI 可修改所选样式的名称、基础样式及全部已支持的字符/段落属性。属性控件区分保持不变、设置值和恢复继承；粗斜体、下划线、删除线、方向与段前分页也可显式关闭。字符样式不显示段落属性。字体来自宿主提供的 profile，颜色接受六位 RGB 或 auto；行距以倍数或 pt 输入，制表位复用段落编辑字段。格式、名称和继承在确认后合为一项历史，不要求正文选区。目录按按钮显式刷新。DOCX 历史目前支持正文、样式及其他 Word XML 的修改，以及样式或设置创建所需的 XML 部件新增、关系和内容类型修改。已有部件的任意删除及二进制资源历史仍待对应操作接入。

`FoundationSession/Client.execute({ operation: "createStyle", revision, style })` 创建自定义样式，返回 `{ id, state }`。`DocxStyleCreation` 使用 `{ name, kind, basedOn? }`；`kind` 为 `"paragraph" | "character"`，可选的基础样式必须同类型且已支持。省略 `basedOn` 创建无直接继承的定义。Web 编辑宿主的 `createStyle(style)` 返回新 ID。核心分配身份，并避开 Word 部件中已有定义和引用；同类型样式不接受重复显示名。创建不改变选区或立即应用到文字，之后可用现有应用和修改方法。默认 UI 读取目录后可新建；有选中项时以它为基础，没有选中项时不设基础样式。样式管理不要求正文选区，应用和清除仍需要有效选区。

导入文件缺少样式部件时，核心在主文档旁创建唯一 XML 部件，原子补齐主文档关系和内容类型。原有同名部件、关系 ID、外链和未知内容保留。新定义和包元数据合为一项有界历史，新增 XML 的源内容计入历史预算；包图、输出或历史预算失败不改变状态。撤销移除本次新增部件并恢复原包，重做保留后续修改所需的节点身份。保存重开后使用同一关系与样式 ID。

`deleteStyle(revision, id, replacement)` 删除自定义样式，替代样式必须已支持且类型相同，也不能依赖被删样式。Web 编辑宿主省略 revision。核心同步移除定义并替换 WordprocessingML 部件中的样式引用，包括正文、页眉和编号；保留直接格式、文字、其他样式及未知内容。折叠处待输入的样式引用也映射到替代项。命令至多替换 65536 个引用，继续受包与历史预算约束。全部候选成功后一次提交，撤销同时恢复各部件与选择。默认 UI 可显式选择同类型替代样式，初始使用基础样式；无基础样式时须先选择替代项。没有有效替代项时不能删除。删除链接自定义样式时保留对端样式，解除指向被删样式的链接，再替换普通引用；未知链接内容明确拒绝。默认及内置样式不能删除。

`updateStyle(id, { character: {}, paragraph: {}, reset: true })` 显式重置格式，不能同时传其他修改。当前支持文档默认段落/字符样式，以及 Normal、DefaultParagraphFont、Strong、Emphasis、Heading1–Heading9，以及 NoSpacing、Quote、Caption、QuoteChar、SubtleEmphasis、IntenseEmphasis、IntenseQuoteChar、Hyperlink、FollowedHyperlink、Title、Subtitle、TitleChar、SubtitleChar、ListParagraph、Header、Footer、HeaderChar、FooterChar、FootnoteText、EndnoteText、FootnoteTextChar、EndnoteTextChar、FootnoteReference、EndnoteReference、TOC1–TOC9 和 TOCHeading。默认样式恢复文档默认属性；Strong/Emphasis 继承当前默认字符样式并恢复粗体/斜体。稳定 ID、名称、默认标志、next/link 和正文直接格式保留；其他内置样式的重置规则尚未实现。默认 UI 提供同一操作。重置沿上述候选校验及单项历史提交，撤销恢复完整源内容。行为参考 [ONLYOFFICE 样式重置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L8854-L8889)。样式修改与删除还会校验正文继承的编号引用、有效级别属性和标记结果，失败保留原包。

新增预设继承当前对应类型的默认样式。NoSpacing 清除字符覆盖，段后距为 0、单倍行距；Quote 设置 8 pt 段前距、居中、斜体及 text1 的 BF tint；Caption 设置 10 pt 段后距、单倍行距、9 pt 普通/复杂文字字号、斜体及 text2 颜色。QuoteChar/SubtleEmphasis 使用引用的字符属性；IntenseEmphasis/IntenseQuoteChar 使用斜体及 accent1 的 BF shade。段前后其他未声明值沿基础样式继承，正文直接覆盖保持。

ListParagraph 恢复 36 pt 左缩进及同样式段间距抑制。Header/Footer 恢复 0 段后距、单倍行距，以及 242.2 pt 居中和 484.45 pt 右对齐的固定 Tab。对应字符样式恢复默认字符继承。FootnoteText/EndnoteText 恢复 10 pt 普通及复杂文字字号、0 段后距和单倍行距；两个 TextChar 预设仅恢复字号。FootnoteReference/EndnoteReference 恢复上标；注释内容和编号继续由现有脚注/尾注入口管理。这 11 种预设复用 [`style-presets.mbt`](../../../modules/formats/src/docx/style-presets.mbt) 与原重置事务；固定属性依据 [ONLYOFFICE ListParagraph](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles/default-styles.js#L659-L672)及[页眉页脚和注释样式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles/default-styles.js#L840-L1030)。

TOC1–TOC9 恢复 ONLYOFFICE 默认 Simple 目录样式。九级左缩进依次为 0、14.15、28.35、42.5、56.7、70.85、85.05、99.2、113.4 pt，右缩进与首行缩进为 0，段后距为 2.85 pt。段前距、行距和文字格式继承当前默认段落样式；TOCHeading 清除本地段落及字符属性并继承默认段落样式。稳定 ID 或不区分大小写的英文原生名称均可识别，类型仍须为段落。正文直接覆盖、名称和元数据沿原重置合同保留。本操作仅重置已有样式；目录创建与显式整体更新归[原生目录字段](docx-pages.md#原生目录字段读取)，自动更新和其他目录主题继续实施。属性依据 [ONLYOFFICE CreateTOC](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L6750-L6790)与 [CreateTOCHeading](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L7016-L7024)，实现复用上述样式预设与原子事务。

Title/TitleChar 恢复四个 Arial 字体槽、28 pt 普通/复杂文字字号和 −0.5 pt 字间距。Title 段落设置 4 pt 段后距、单倍行距与 `contextualSpacing`。Subtitle/SubtitleChar 恢复 14 pt 字号、0.75 pt 字间距及 text1 的 A6 tint；无主题时使用 RGB `595959`。Subtitle 段落保留原生编号级别 1，不新增编号实例。名称、next/link、正文直接覆盖及其他部件沿上述重置合同保留。预设依据 [ONLYOFFICE 标题与副标题](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles/default-styles.js#L536-L623)。

原生 `contextualSpacing` 按文档默认值、样式继承和直接定义解析。本段开启时，与相邻段落的原生样式引用相同，便省略本段对应的段前或段后距；直接关闭只影响本段。正文、普通表格及已支持的页眉页脚在核心 Flow 中使用计算后的距离，格式查询和原始 XML 保留声明值。表格按同一行相邻单元格比较，首行首格还参考表格前的元素；不把上一行末格当作相邻格。段落样式应用清除直接标志。当前通过原生读取及预设重置使用该属性，未增加独立格式补丁或控件。规则归 [ONLYOFFICE 段距计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L10806-L10965)和[单元格相邻元素](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableCell.js#L2445-L2495)，实现归 [`contextual-spacing.mbt`](../../../modules/formats/src/docx/contextual-spacing.mbt)。

按标准 ID 或对应英文内置名识别，名称不区分大小写，自定义标志及类型不符的样式不套用预设。名称、别名、link/next 和源元数据保持，不创建缺失样式。已有主题时保留颜色关联；相关主题色不可解析时保护重置。没有主题时写预设 RGB，不增加主题部件；之后添加主题可再次重置以建立关联。默认目录的 `canReset` 自动开放已有按钮，沿同一候选、预算、单项精确历史和保存重开，无变化不提交。预设参数参考 [ONLYOFFICE 默认样式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles/default-styles.js#L621-L795)与[题注](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles/default-styles.js#L913-L938)，实现归 [`style-presets.mbt`](../../../modules/formats/src/docx/style-presets.mbt)。完整强引用边框及其余未支持预设继续保护，不以删去属性代替重置。

Hyperlink 和 FollowedHyperlink 继承当前默认字符样式，恢复单下划线；无主题时分别使用 RGB `0563C1` 和 `954F72`，已有可解析主题时关联 `hlink/folHlink`，写为标准 `w:themeColor="hyperlink"/"followedHyperlink"`。新建文档同时提供这两个字符样式，创建与重置共用预设；初始重置不增加历史。用户通过现有字符样式面板显式应用或重置，正文直接格式、链接目标、提示和关系保持。链接创建仍保留原格式；打开链接不写访问历史或自动切换样式。参数依据 [ONLYOFFICE 链接样式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles/default-styles.js#L1028-L1056)。

九级标题的创建和重置共用本项目的标题预设：大纲级别 0–8，字号依次为 16、14、13、12、11、11、11、11、11 pt，并设置粗体标记。重置继承当前默认段落样式；没有默认标记时尝试 Normal，均无时继承文档默认属性。字体与颜色沿基础样式继承，正文直接格式保持。按标准 ID `Heading1`–`Heading9`，或非自定义段落样式的英文名 `Heading N` 识别；名称不区分大小写。自定义样式即使同名也不作为内置标题重置。

标题重置保留名称、别名、next/link、元数据和其他样式，恢复支持的标题字符/段落预设。初始预设及重复重置不新增历史；默认角色有歧义、属性源含未知注释或候选校验失败时保持原包。这里使用与本项目空白文档一致的预设，不声明完整 Office 内置样式、主题及所有导入变体的视觉一致性。

两端对齐在塑形后扩展词间空格；无空格中文使用合法断行处的字形簇间隙，接近满行的普通单词可使用字形簇间距。连字与字形不重塑，末尾空格不参与扩展，最后一个 Tab 之前的位置保留。段落末行与显式分页行保留自然宽度，RTL 末行靠右。软换行默认参与对齐；派生 `Paragraph.expandSoftBreak` 读取设置中的 `compat/doNotExpandShiftReturn`。光标、命中、选区、装饰与 PDF 消费相同位置；阿拉伯文使用词间距，未新增 kashida 字形。规则参考 [ONLYOFFICE 的段落对齐计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js)。

字段省略表示不修改，null 清除对应直接属性并恢复继承。MoonBit 使用 `FormatChange::{Keep, Clear, Set}` 和类型化属性结构。字符范围在边界处拆分 run，范围外文字与未知部件保留；段落属性覆盖范围接触的段落。一次修改提交一项有界历史，保存与 PDF 沿现有布局。无效位置、过期 revision、属性和预算失败不提交部分修改。

折叠范围只改变后续输入属性，不增加 revision、历史或空文字。实际输入及格式一起提交；组合预览沿候选处理，取消仍保留输入属性。显式选择/导航结束该输入属性，保存本身不改变它。默认 UI 的字体/段落控件调用同一 Web 队列，数字与颜色确认后提交；字体仍需宿主供应对应 profile 和字节。

`FoundationSession/Client.execute({ operation: "captureFormat", revision, selection })` 返回核心计算的 `CopiedFormat: { character, paragraph }` 属性片段。它只含当前已支持且在选区内一致的有效值；混合属性省略，应用时保留目标对应值。片段包含值，不绑定源位置或 revision，也不包含页面几何、样式或列表身份。`execute({ operation: "applyFormat", revision, selection, format })` 校验目标 revision 与完整片段，字符和段落候选全部成功后一次提交；失败保留文档与历史。折叠处的字符格式仍作为后续输入属性，段落修改立即提交。Web 编辑宿主提供同名方法，默认 UI 使用“复制格式”和“应用已复制格式”；替换文档后清除 UI 中的片段。应用后可一次撤销两类源修改，保存与 PDF 沿现有格式路径。

核心在连续塑形的光标位置上划分装饰，先绘制高亮背景，再绘制文字与下划线/删除线；编辑装饰不改变连字与断行宽度。单线装饰按原生顶边定位，以原字号的 1/18 绘制描边；下划线使用字体原始下降量。上下标沿 ONLYOFFICE 的 0.65 字号比例舍入到半磅，再上移 0.35 / 下移 0.141 个原字号，保持逻辑文字、源 offset 和原字号属性。字号规则依据 [CRunText.SetMetrics](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/RunContent/Text.js#L208-L225)。段落按[原字号度量行高](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L15249-L15305)，上下标移动字形，选区包含实际基线。相同图元用于 Canvas 与 PDF，不由 DOM 或 CSS 计算文字几何。其他下划线类型或颜色变体保留源并诊断、保护编辑，未宣称完整装饰兼容。

派生 `TextStyle` 包含 `underline/strike`、RGB `highlight`（无高亮为空串）和 `script`；MoonBit 的 `TextStyle::new(font, size, color)` 创建普通样式。`TextProbe::text_block/span_block` 共用上下标与装饰布局，DOCX、XLSX 和 PPTX 沿同一文字图元输出。

`FoundationSession/Client.execute({ operation: "findDocx", revision, text, options })` 进行字面查找；`options` 为可选的 `matchCase`、`wholeWord` 布尔值。返回 `{ revision, truncated, matches: [{ selection, snippet, reason }] }`。结果按正文与表格单元格顺序排列，相邻同容器段落以 LF 相连。受保护文字也返回命中与原因，不能替换。查询最多 65536 UTF-16 单元，最多返回 1000 个不重叠命中；超过上限设置 `truncated`。

多节正文中携带节结束属性的段落也可查找、定位和替换，包含同段注释引用及已支持简单域。普通批量替换保留原节属性；LF 替换复用原生范围事务，把节结束移到拆分后的末段；跨节合并只移除被范围消耗的节边界，并保留后续节及页眉页脚继承规则。节内容、未改注释部件、字段缓存和精确历史沿同一路径保存重开。未知/重复节属性及其他保护仍返回原因，整批替换原子拒绝。实现归 [search.mbt](../../../modules/formats/src/docx/search.mbt)与 [search-replace.mbt](../../../modules/formats/src/docx/search-replace.mbt)，节归属复用 [section_range_transition](../../../modules/formats/src/docx/section-input.mbt)；结果定位和逆序批量沿 [ONLYOFFICE 搜索定位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Search/DocumentSearch.js#L126-L140)及[批量替换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Search/DocumentSearch.js#L303-L316)，未复制执行代码。

查找使用 Unicode 简单小写映射，不做规范化、语言定制或正则匹配。全词边界按字母/数字和非 ASCII Unicode 标识符延续字符判断，ASCII 下划线作为分隔符。命中不能切开字素或代理对。范围暂限主文档正文与单元格，页眉、脚注等内容区域待对应编辑能力接入。

`replaceDocxMatches(revision, selections, text)` 一次校验全部范围后提交一项历史；空数组无变化，重叠、空范围、保护、过期 revision 和预算失败不部分提交。替换最多 1000 个范围，文本最多 65536 UTF-16 单元，允许 LF 段落分隔、U+2028 软换行、U+000B 分栏、U+000C 正文分页与 Tab，不接受 CR。插入文字沿用目标起点 run 格式。结构替换另限源 XML UTF-16 长度乘命中数不超过 67108864，避免逐项解析阻断操作。

`DocumentEditor.search.find(text, options?)` 在原队列中查询，并给结果增加 `documentId`。`selectMatch(result, index)` 定位可编辑命中；`replaceMatches(result, text, index?)` 替换指定项，省略 index 时替换全部结果。全部替换拒绝 `truncated` 或含受保护内容的结果。旧文档或旧 revision 的结果拒绝后仍可继续编辑。默认 UI 提供同一组操作，编辑后提示重新查找并禁用旧结果。

`DOCX_SOFT_BREAK` 为 U+2028，由 Wasm/Web foundation 导出。`replaceRange`、组合候选和批量替换用它表示段内换行，保存为 `w:br`；实际 LF 仍创建段落。`DocumentEditor.clipboard.insertSoftBreak()` 与默认 UI 按钮、Shift+Enter 调用同一范围事务。`query().texts` 包含普通文字与内联控制节点；换行逻辑长度为一个 UTF-16 单元，`w:cr` 同样读取为 U+2028。Flow 用 LF 排版，`selectedText` 与剪贴板将软换行转为 LF。普通换行可删除、选中、设置格式及跨段移动；环绕清除和未知内联属性继续保护。

`DOCX_PAGE_BREAK` 为 U+000C，由同一 foundation 入口导出。正文 `replaceRange`、组合候选、查找替换及 `DocumentEditor.paste(DOCX_PAGE_BREAK)` 用它插入 `w:br w:type="page"`，不增加段落。默认 UI 的插入分页符按钮及 Ctrl/Cmd+Enter 使用相同事务，单独形成历史。已有正文分页符支持选择、格式与删除，保存及撤销保留源节点。普通表格单元格内也支持分页符的读取、插入、选择、格式、删除、查找替换和精确历史；按 [ONLYOFFICE 表格内分页符规则](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L4696-L4712)，它不触发换行或换页。核心保留源 `w:br` 和 UTF-16 位置，按零宽控制塑形，表格行继续按既有规则续页。正文与格内的段落缓存区分上下文，列宽、光标、命中、合并续排及 PDF 共用此行为；PDF 的文字映射和 ActualText 排除不显示的分页符。布局保留相邻分页符合并规则；仅供分页符光标定位的空行不占段落高度、不进入页面文字，也不改变空白页拖选端点。

`DOCX_COLUMN_BREAK` 为 U+000B，由 Wasm/Web foundation 导出。`DocumentEditor.paste(DOCX_COLUMN_BREAK)`、默认插入分栏符按钮和 Ctrl/Cmd+Shift+Enter 复用范围事务，不创建段落。正文移到下一栏，末栏及单栏进入下一张纸；连续分栏符逐个推进，不采用相邻分页符的合并规则。分栏符优先于段落保留与孤行约束，末尾保留下一栏的光标位置，不另占段落高度，并参与末页平衡。

已有和新插入的分栏符占一个 UTF-16 单元，支持选择、格式、删除、查找替换、组合候选、精确混合历史及保存重开。核心写 `w:br w:type="column"`，不把 U+000B 写进 XML 文本。普通表格单元格内按零宽控制保留位置，不强制换行或换栏；PDF 的文字映射和 ActualText 排除不可见控制，保留相邻文字连续性。页眉页脚及其他受保护区域仍拒绝插入；未知内联属性、目标注释、过期 revision 和预算失败保持原包。分栏符定义与格内行为参考 [ONLYOFFICE CRunBreak](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/RunContent/Break.js#L318-L337)和 [Run 分页/分栏处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L4690-L4724)。复用 [`inline-input.mbt`](../../../modules/formats/src/docx/inline-input.mbt)、[`paragraph.mbt`](../../../modules/layout/src/paragraph.mbt)及 [`pagination.mbt`](../../../modules/layout/src/pagination.mbt)，未复制上游执行代码。

Tab 输入与粘贴保存为 `w:tab`，不转成空格。`FoundationSession/Client.execute({ operation: "tabDocx", revision, backward })` 在列表正文执行下述列表规则；普通正文插入 Tab，反向时减少正的首行/左缩进；在现有表格中只移动到相邻单元格，不增加 revision 或历史。默认 UI 的插入制表符按钮与 `DocumentEditor.paste("\t")` 总是插入字符，原生 Ctrl+Tab 也在单元格中插入。Tab/Shift+Tab 只由文档原生输入处理；参数控件使用浏览器焦点切换，Escape 将焦点移出文档输入。

`Paragraph.defaultTab` 为 point，来自 `settings/defaultTabStop` 的整数 twip，默认 36 pt，范围 0–1584 pt；0 表示零宽。核心根据当前行位置与缩进计算下一默认制表位，断行、光标、预览与 PDF 消费同一宽度。末格 Tab 保持原位置，自动追加表格行归表格编辑批次。

`FoundationSession/Client.execute({ operation: "setDefaultTabStop", revision, interval })` 与 `DocumentEditor.formatting.setDefaultTabStop(interval)` 修改文档默认间隔，不要求正文选区。`interval` 为 0–1584 pt，须能表示成整数 twip；null 清除显式设置并恢复 36 pt。`EditState.defaultTabStop` 提供当前有效值，默认 UI 可修改或恢复。修改保留自定义制表位、逻辑 Tab、待输入格式与未知设置；现有相同值不产生历史。缺少设置部件时，XML、关系与内容类型一并创建。设置修改或创建合为一项有界历史，失败保留已提交包，撤销和重做恢复各部件及选择。候选先验证设置值和包预算，再提交并使相关布局失效。未知目标标记、重复设置、外部/重复设置关系，以及强制保护的文档设置拒绝修改。行为参考 [ONLYOFFICE 的文档默认制表位历史](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js)。

`setParagraphFormat({ tabs })` 使用 `TabStop[]`：每项为 `{ position, align, leader? }`，位置单位为 pt，须为 0–1584 pt 的整数 twip，按位置递增且不重复，最多 64 个有效位置。`align` 支持 `left/right/center/decimal/bar`。`leader` 省略时为 `none`，也支持 `dot/hyphen/underscore/heavy/middleDot`；`bar` 只接受无引导线。MoonBit `TabStop.leader` 与核心返回值总带明确值。字段省略保留；null 清除段落直接定义并恢复继承；空数组清除全部有效位置，核心为移除的继承位置写 `w:tab w:val="clear"`。格式查询与格式复制包含有效制表位。默认 UI 可添加、修改、移除、应用、清除全部与恢复继承，使用同一历史与保存路径。

派生 `Paragraph.tabs` 提供合并后的有效位置。核心按后续片段宽度放置右/居中制表位，小数点使用文档 `settings/decimalSymbol`（派生 `Paragraph.decimalSymbol`，默认 `.`）；越过可用边缘的自定义位置按右边缘放置，悬挂缩进保留隐式左边界位置。规则参考 [ONLYOFFICE 的制表位合并](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js)与 [Tab 后续文字定位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js)。未知标记仍保留源并保护编辑。`Paragraph.rtl` 为 true 时，制表原点移到正文右边缘，按向左的距离计算默认及自定义位置。左/右缩进分别作用于起始/末尾边缘，首行缩进和对齐沿同一方向；竖线也按右边缘定位。文字字形保留塑形后的顺序和局部坐标，小数点按后续片段的视觉位置锚定。规则参考 [ONLYOFFICE 的 RTL 制表定位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js)。标尺交互见[水平标尺](docx-content.md#水平标尺)。

引导线按 [ONLYOFFICE 的 Tab 字形绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/RunContent/Tab.js)使用当前字体与字号，重复字形居中放入间隔；短划线使用 1.5 倍步长，`heavy` 与 `underscore` 使用下划线字形。逻辑文字、光标与复制内容仍为一个 Tab，PDF 的 ActualText 不加入装饰字符。每个 Tab 最多 4096 个引导字形，每行 16384 个、每段 65536 个；超过预算明确拒绝布局。

`bar` 遵循 [Word 的竖线制表位语义](https://support.microsoft.com/en-us/word/using-the-ruler-in-word)，在每一行的指定位置绘制竖线，不改变文字或 Tab 定位。当前核心绘制 0.5 pt 黑线，沿行高延伸，预览与 PDF 共用图元；未宣称与 Word 的全部显示细节一致。派生 `Line.bars` 随分页定位，缓存与公开行结果各自持有数组副本。

水平标尺已接通，主题颜色与字体见下节。[P10](../../implemented/p10-docx-core.md)已完成声明的核心格式范围；其他内置样式重置及导入变体归 [P14](../roadmap.md#p14-兼容与性能已完成)。

### DOCX 符号插入

默认编辑栏提供 50 项常用 Unicode 标点、数学符号、货币、箭头、形状和圈号选择。选择后点击插入，沿 `DocumentEditor.paste(symbol)` 替换当前范围或在光标插入；对应同步/Worker 核心操作仍为既有 `replaceRange`。字符保存在普通 `w:t`，继承当前位置的字符和段落格式，保留非目标源。字体与缺字处理沿宿主提供的字体 profile 和既有回退。每次插入产生一项精确历史，并把焦点交还原生输入；后续键入保留原生编辑行为。组合输入、暂停、只读或格式保护状态沿现有控件和核心保护禁用。保存、语义文字、Canvas/PDF 和重开使用共同核心文字路径。OMML 读取、编辑和排版归[数学合同](docx-math.md#docx-嵌套行内数学)；专用符号字体与旧式 `w:sym` 编辑归 [P14](../roadmap.md#p14-兼容与性能已完成)。

控件归 [`docx-symbols.tsx`](../../../packages/docx/src/react/docx-symbols.tsx)，接入既有编辑栏和中英文文案。功能目录来自 [GenOffice 常用符号](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/components/ribbon-insert-tab.tsx#L63-L114)，Unicode 插入与字体语义参考 [ONLYOFFICE 符号插入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/apiBase.js#L3718-L3752)。当前操作复用原核心格式与输入事务，未新增符号模型、桥命令、协议或依赖。
