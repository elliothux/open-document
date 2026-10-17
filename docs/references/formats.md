# 当前字体与格式合同

本文维护各格式的当前支持面；产品目标与核心/宿主职责归 [SDK 合同](sdk.md)。公开包仍为 private/WIP，API 尚未发布。内部架构直接按当前需求修改，删除旧模型与旧路径；兼容处理仅限文档格式。

XLSX 的网格、值/公式编辑、保真保存与基础打印见 [P5](../implemented/p5-xlsx-editing.md)。以下分别声明文件读取、计算、显示和编辑边界。

PPTX 已交付限定幻灯片编辑、源保留及静态 PDF，结果与检查依据见 [P6](../implemented/p6-pptx-editing.md)。

PDF 包含 Office 布局输出，以及 [P7](../implemented/p7-pdf-input.md) 的限定输入/查询和 [P8](../implemented/p8-pdf-operations.md) 的页面、批注、普通字段与源对象保存。两种保存入口各自维护源语义。

后续实现与测试基准优先使用 ONLYOFFICE core/sdkjs，其次使用 LibreOffice。下文 LibreOffice profile 记录已有实现和证据；对应功能调整时按当前优先级核对，并保留历史结果的真实来源。

P4 已完成限定 DOCX 编辑，只对声明范围负责。已验证输入不授予全部控制符编辑或布局支持；性能专项延后。交付范围见 [P4](../implemented/p4-docx-editing.md)，运行证据入口见[测试说明](testing.md#证据与正确性)。

U+202A–U+202E 与 U+2066–U+2069 保留在逻辑文字中，不要求可见字体字形，也不输出控制符轮廓。核心保留这些零宽区段的方向、字体和字号。十类输入的全部 234 个 Right/Left 矩形及真实输入框在 Node/Worker 匹配重复 LibreOffice 参考；原 51 处差异已修复。五组反向阿拉伯塑形向量在两个宿主匹配原生字形。内部 `PlacedRun.size` 以 pt 提供区段字号；完整布局留在核心。固定源码见[依赖记录](dependencies.md)，阶段验证范围见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)。

DOCX 文字区段的实际宽度和后续起点按固定 LibreOffice 的整数 twip 放置，初始断行 advance 和公开 `shape()` 保留浮点设计值。具体未支持范围与历史差异由私有 case 记录维护，不用行宽通过代替光标和选区验证。

## 默认 UI 与编辑宿主

`@open-document/ui` 的 `mountEditor(container, options)` 挂载 DOCX、XLSX、PPTX 或 PDF 默认 UI。`container` 由宿主提供可测量的高度。`options.format` 区分格式；`document` 为 `{ name, bytes }`，`resources` 明确提供 `{ wasm, workerUrl, fonts, profile }`，可传对应 `budget`、`theme: "light" | "dark"`、`locale: "zh-CN" | "en-US"`、异步 `onSave`、初始 `signal` 和 `styleNonce`。接入代码与普通 JS 示例归[开发说明](development.md#默认-web-ui)。

DOCX、XLSX、PPTX 也接受 `document: { name, blank: true }`，`OfficeDocument` 类型排除同时传入 `bytes`。包与模板由各自 MoonBit 格式模块生成，继续使用现有输入、包与输出预算；字体仍由宿主显式提供。DOCX 的 `FoundationSession/Client.createDocx(budget)` 使用 Letter 页面、一英寸边距、11 pt Times New Roman 和一个空段落。XLSX/PPTX 的具体入口和默认值归下文各格式合同。PDF 仍要求已有文件字节。

返回的 `MountedEditor` 按 `format` 区分，`editor` 是当前文件的对应 Web 编辑宿主，只读属性在替换成功后指向新宿主。旧宿主释放后拒绝操作。实例提供以下方法：

| 方法 | 行为 |
| --- | --- |
| `open({ name, bytes })` | 只替换同格式文件；处理草稿/未保存修改，暂停新编辑并等待已接受队列；独立候选完成字体和首屏后替换，失败或取消保留旧会话；成功 `true`，用户取消 `false`，失败拒绝 Promise |
| `save()` | 产生原格式输出，等待 `onSave`；重复调用复用同一在途结果，回调期间可以继续编辑 |
| Office `create({ name })` / `open({ name, blank: true })` | DOCX、XLSX、PPTX 复用替换确认与独立候选，成功后成为新文件；PDF 没有新建入口 |
| `saveAs(name)` | 使用新名称产生原格式输出；目标由宿主决定。失败保留旧名称和修改状态；成功后更新名称。不同名称不复用同一个在途输出 |
| `getSnapshot()` / `subscribe(listener)` | 转发当前宿主的稳定快照；外部订阅跨文件替换保持，监听器异常不改变事务 |
| `close()` | 询问草稿和未保存修改；取消 `false`，完成关闭 `true`；等待在途保存回调后重新检查 |
| `dispose()` | 明确放弃内存会话，不弹确认；取消候选、等待已接受核心操作、释放 Worker/Canvas/React/自建 DOM；重复调用等待同一个 Promise，清理失败仍继续其他清理 |
| `setTheme()` / `setLocale()` | 更新 UI；保留文档会话、Canvas 和原生输入节点 |

每个实例追加一个自建容器与 open ShadowRoot，保留调用者原有 DOM。菜单与 Dialog 的 Portal 位于实例内；关闭确认是模态，会暂时限制整个页面交互。主题、关键尺寸与基础样式在实例内定义，宿主无需 Tailwind。当前目标只有 Chrome/Chromium。

框架无关的四类编辑宿主提供 `getSnapshot()`、`subscribe()`、`focus()`、`setPaused()`、`markSaved(output)` 和 `markDownloaded(output)`。快照包含会话身份、revision、导航、缩放、选区摘要、历史、诊断、停止/错误、在途操作及组合/拖动/草稿状态，并附格式当前查询。未变化时保持对象身份；已提交但绘制失败仍发布新 revision，保留保存与恢复入口。低层宿主借用 client，调用者等待宿主释放后另行关闭 client。

编辑宿主的原格式保存、Office PDF、DOCX/PPTX 单页 PNG 和 XLSX CSV 输出统一返回 `EditorOutput = { documentId, revision, format, bytes }`。`format` 包含 `csv` 和 `png`；编辑器输入格式仍为 DOCX/XLSX/PPTX/PDF。默认 UI 另加文件名 `name`。DOCX 全页 PNG 返回按页序排列的只读 `EditorOutput` 数组，具体合同见[DOCX 页面 PNG](#docx-页面-png)。此约定不改变原始 Wasm/client 的保存结果。只有该宿主实际产生的原格式输出可以 `markSaved`；旧会话、其他格式和任意裸 revision 都不能确认保存。确认的是输出 revision，其后新编辑仍显示未保存。导航、缩放和 UI 变化不修改文档。

原格式 `onSave` 成功才确认保存基线；失败保留修改并允许重试。缺省下载只提示“已生成下载”，不确认磁盘持久化，也不清除修改。PDF、PNG 和 CSV 导出不清除 Office 修改。关闭前选择“导出并继续”明确包含放弃内存会话。`dispose` 不等待宿主存储回调，晚到回执不更新已释放实例。

默认 UI 快照增加 `newDocument`。空白创建后即使 revision 为 0，`modified` 仍为 true；首次原格式 `onSave` 成功才清除此标记。下载不清除它，关闭与替换仍需确认。文件名去首尾空白、拒绝空名、路径分隔和控制字符；缺少当前格式扩展名时补齐。

保存回调期间若又有编辑，关闭/替换保留会话并返回 `false`。候选已经切换后，旧宿主清理失败只发布清理提示；新会话保持可用，`open` 返回 `true`。

DOCX/PPTX 的组合或拖动需要结束/取消。XLSX 保存先提交已支持的单格草稿；PDF 属性草稿须显式应用/取消。替换最多准备一个独立候选，加载界面的“取消”释放候选并恢复旧会话。核心保留原有文档校验、只读规则和预算。

## 会话与宿主

`(await loadEngine(bytes)).openFoundation()` 创建同步 `FoundationSession`；浏览器使用 `FoundationClient.open(wasm, workerUrl)`，每会话独占 Worker，一次只允许一个请求。`dispose()` 终止 Worker，取消等待中的请求；同步 Wasm 调用本身不支持抢占取消。创建失败、非法打开或替换失败后可以继续使用未提交的会话；成功打开的会话只拥有一个 DOCX。

`defaultBudget()` 从 MoonBit 返回默认值；打开时必须显式传 `Budget`，可以收紧。`openDocx`/`query` 返回派生快照，修改快照不会改变文档；`replaceNode(id, revision, text)` 按已查询的文字、内联控制或图片片段写入文字，与逻辑范围命令共用校验、提交与历史，ID 在该会话内稳定。它保留相邻未知结构，并保留合法 XML 文本中的 CR 等字符，不赋予该段落可视编辑能力。成功内容变化增加 revision；无变化不增加。`saveDocx()` 返回新字节，不改宿主输入、不清空历史。保存失败可能留下已核验的读取缓存，但不提交编辑或输出。`close()`/`dispose()` 释放核心/宿主引用，后续访问报错。

## P4 当前编辑 API 切片

只读 DOCX Flow 的段落新增 `nominalSize`（pt，`0 < size <= 1024`），由核心按默认及段落样式计算；它不由具体文字 run 或标记直接字号推断，也不是宿主可编辑状态。布局用它计算单元格/空页眉末段的自动行距间隙，段间仍使用文字自然高度。当前补充修复已通过完整运行 `1791779829628` 的 308/308；23 组独立参考在安装 Node 与生产 Worker 的完整结果相同，验收边界见[测试记录](testing.md)。

历史产物已在 macOS/Chromium 使用现有豆包拼音完成中文提交、取消、撤销重做和绑定 revision 的保存；其他归档产物另通过普通 Latin 系统输入、撤销/重做及独立保存。R0 后的定向检查覆盖组合候选与取消，未重做系统中文输入验收。各记录分别绑定自己的产物，不扩大为所有输入法或 OS 候选窗几何支持；证据入口见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)。沿用现有输入法；Windows/Word 和 VoiceOver/语音输入不在验收范围，保留基本键盘/AX、源保真及失败恢复检查。

`shape()` 另返回字素边界的 `carets: { offset, before, after }[]`，offset 为 UTF-16，坐标沿用 shaping 的 CSS px；`before` 对应前一逻辑内容侧，`after` 对应后一侧，BiDi 交界可不同。连字优先读取 GDEF 默认设计坐标，缺少匹配数据时只分配该 cluster 的 advance；组合符没有额外停靠点，空文本返回 offset 0。

核心内部布局保留最终行的 carets，坐标为页面 point。宿主通过命中和光标查询获取几何。DOCX 连字光标按 LibreOffice MSO1 的每 pt 120 个整数设备单位构造 GDEF 分量宽度，差值累计到同一塑形 run 的后续光标；最终段内位置截断为整数 twip。公开字体探针仍返回原设计坐标，字形 advance、绘制及行宽不因光标取整而改变。`hitTest(layoutId, page, x, y)` 和 `caret(layoutId, position)` 返回绑定 revision/layout 的页面、行、坐标、高度及逻辑位置，不修改选区或历史。软换行前侧定位上一行，后侧定位下一行；验证范围见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)。过期或已因内容/资源变化失效的布局报 `stale-layout`，未知页面报 `invalid-page`，非有限/页外坐标或无文字页面报 `invalid-position`。不可安全编辑的图片或段落返回 `editable: false`、`position: null` 和原因。未解释属性的只读原因由 DOCX Flow 按段落及默认样式/表格/节上下文派生，随布局保留；局部段落诊断不禁止无关正文。 方向区段独占一行时仍使用其自然光标度量；因下一方向区段换行而保留的前行文字区段也独立计算。其余可复用的单文字区段保持整行高度，不能按 run 数量一律判成整行；自然高度继续按同页段落底部裁剪。

`selectionGeometry(layoutId, selection)` 返回 `{ layoutId, revision, rects }`，矩形携带页面、行及 point 坐标/宽高。普通逻辑范围按字素两侧的塑形坐标映射，只合并实际相邻区间；同段跨页或含高于段落基准方向的区段时，按固定 LibreOffice 的端点所属区段和自然度量构造区域，保留垂直分区及跨行溢出，再裁剪到各页段落框。跨页保留首框剩余区域、中间整框和末框前缀，不人为在最后一行分割整框区域。内部区域用整数 twip；公开塑形边界和整行高度保持既有精度，其余细分区域按原生整数矩形转换。范围继续到下一行、页或段时，按段落基本方向延伸到行可用区边界；同 offset 的软换行前后侧以实际结束行区分。反向结果相同、折叠为空；普通零宽字素保留零宽矩形，原生区段拆分可保留一个 twip 的边界区域。跨段嵌套范围仍用现有逻辑区间，其原生独立几何尚未验收；不显示段落标记，不赋予跨段写回能力。查询验证端点和当前布局，不改变选区、文档或历史。

`navigateDocx(revision, layoutId, direction, extend = false)` 返回 `{ state, caret }`，使用核心当前选区。方向为 `left/right/up/down/home/end`，左右按逻辑字素顺序移动，Right 到达用 before、Left 到达用 after，Home/End 到当前行逻辑首尾；End 的逻辑尾若同时是下一页同段入口，显示下一页并保留基础方向，同页软换行保持前侧；非折叠选区无 Shift 时，Left 收拢到逻辑起点，Right 从逻辑末端继续前进一个逻辑字素步骤，文档末端保持边界。上下保留目标 x、优先同单元格，离开单元格时排除水平区间不重叠的旁列。`extend` 保留 anchor；成功只改变选区，不增加 revision/历史。显式选区、编辑、横向移动及换布局重置垂直目标，非法方向、旧 revision/layout、无选区或受保护目标原子失败。行携带段落方向、正文/单元格身份和可用水平区间，placed run 携带段落起点，导航复用最终 shaping/BiDi 坐标。验证范围见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)。

`deleteDocx(revision, direction)` 的方向为 `backward` / `forward`。已有范围整体删除；折叠选区按逻辑前/后扩展字素删除，复用范围事务和历史。组合符与 surrogate 不拆开。段首 Backspace/段尾 Delete 可合并同一正文或单元格内的相邻普通段落；文档首尾保持 revision、源和历史不变。单元格边界、表格或受保护内容整体报 `protected-content`。

`editState()` 返回 revision、选区、撤销/重做可用性、历史容量与受影响段落；`selectDocx(revision, selection)` 仅更新选区。`replaceRange(revision, selection, text, inputGroup?)` 可跨 run，以及同一正文或单元格中连续的普通段落；`undoDocx(revision)` / `redoDocx(revision)` 恢复内容和选区，revision 继续单调增加。`selection` 保留 anchor/focus，每个位置包含稳定 paragraph ID、段落 UTF-16 offset 与 `before` / `after` affinity；范围按 XML 顺序排序，起点 affinity 决定 run 边界的插入格式。所有命令由 MoonBit 验证，TS 只转发和校验响应。

位置还可包含 `bidiLevel`（0–126 的整数）与 `frameStart`（大于 offset 的段内字素边界）。`frameStart` 保存导航保留的续接页框起点；光标查询只接受逻辑位置恰好位于该续接页框前一个字素的偏好，不能指向任意页。它只影响光标几何和导航，复制、输入、删除及选区矩形仍按逻辑 offset 计算。内容修改清除当前页框偏好，undo/redo 恢复完整选区元数据；只读查询、保存及失败不改变它。缺省字段使用原 affinity 和当前方向层级计算，不保留另一套状态或几何缓存。

编辑提交与后续布局是独立操作：提交成功后布局失败不会自动恢复旧源。浏览器停止输入，但用户可以明确 Undo；宿主排空原队列、取消其暂态组合，并核对当前 revision 后撤销一项历史和重排。失败仍保留停止状态，已完成的明确撤销不伪装为未发生；外部 revision 改动须先恢复，不自动撤销他人的编辑。恢复期间重复请求拒绝，销毁等待已接受的恢复，调用者 client 保留。

`selectedText(revision, selection, cut = false)` 返回核心只读纯文本，按 XML 顺序提取正/反向普通范围，跨段以 LF 分隔并保留空段，折叠范围返回空串。它沿用字素、位置、revision、容器及内容保护检查，跨单元格或未知内容整体拒绝；不改变选区、revision、历史或布局。输出最多 65536 UTF-16 单元（包括 LF），超限报错而不截断。复制与结构写回共用范围顺序/保护检查；只有写回额外检查移动结构及格式。宿主不从页面文字重建选区。

段内边界使用 Unicode 13.0.0 扩展字素，跨文本节点的组合符与 ZWJ 不可拆开；修改后重新合并的字素会将光标推进到合法边界。普通空段支持 offset 0 的输入：优先在第一个已有空 run 创建 text，保留其格式；没有 run 时在段末创建普通 run/text，保留段落属性、现有前缀和非目标源片段。空段身份来自正文 `flow().paragraphs` 或 `flow().tables` 的单元格段落，不能从尚无 text 的 `query().texts` 推断。跨单元格/表格、CR、内联图片所在段、域/书签/修订/未知内联标记及受保护容器目前整体拒绝，未修改的内容仍保留。普通正文与顶层表格单元格内的事务可用；不表示带布局诊断的文件已经可视编辑。

`replaceRange` 将实际 LF 作为段落分隔，可替换折叠、段内或跨段正反向范围，首尾/连续 LF 产生空段；新段仍在原 body/单元格内，光标到最后插入文字末尾，并对字素拼接推进到合法边界。原段及移到新段的存量节点保留身份；新节点获得单调 ID。新段继承已支持的段落属性和边界 affinity 选中的字符格式，显式关闭直接或继承的段前分页。未知属性、编号、节或不可安全编辑内容整体拒绝。多分隔替换是单条历史，返回原范围与全部新增段的受影响 ID；撤销删除新段并恢复原字节，重做恢复同一组新 ID。连续输入使用核心保留的目标 text ID 继续同一字符格式；显式选择/导航、删除、外部修改、undo/redo 和关闭终止它，保存或失败不终止。字符格式的连续目标与显式输入组分工不同，均不维护第二份文档内容。

候选 XML 与包预算校验成功后才提交状态。XML Document 是正文内容的唯一权威，Session 已删除文本覆盖表；解析顺序与稳定 `Node.id` 分离，结构插入不重编号相邻节点，删除身份不能继续查询。局部源补丁核对前片段、重放原身份并保留精确 XML；撤销全部改动后保存原 OPC 字节。文本节点、段落属性及命名空间仍由当前解析结果派生，不维护可独立修改的第二棵树。

跨段替换保留前段身份和段落属性，删除中间完整段落，将右侧存活 run/text 移入最终插入段并保留身份。其有效 namespace 与字符格式来自现有 XML/样式解析；上下文变化时固定受支持字体、字号、颜色和四种 bold/italic/script toggle，并保留已解释的语言与 script 属性，全局 styles/theme part 不变。无法清除的未指定继承属性、重复/错置属性、编号、节或未知结构整体保护。一条 XML 候选同时包含叶文本和结构补丁，一次提交一项历史；撤销/重做恢复原字节、身份及选区。

历史保存局部前后源片段、相关节点身份和选区，undo/redo 共计最多 100 项、4 MiB UTF-16 源片段 payload，单命令最多 65536 UTF-16 单元。payload 包含转义、属性及结构标记，不包含数组/节点身份与运行时分配开销；因此含转义的输入可能比纯文本计数更早达到上限。过大的单项整体拒绝，容量不足淘汰最旧完整项，可用边界与计数随结果返回。这些是实施期的安全上限，尚未完成实测校准与性能验收。当前每次提交仍重解析全篇候选 XML，没有声称局部编辑耗时或内存已达标。多分隔片段在字符串构造前检查复制放大，并继续按整个命令检查 XML、包与历史预算。连续普通输入已按下述显式输入组归并；纯文本剪贴板、组合核心/API 与 Chromium 事件宿主、段落塑形复用与稳定点分页已接入。系统输入记录的产物与范围见本节开头；当前 R0 产物未重做系统输入验收，候选窗几何及校准性能仍未测。

组合 API 使用当前已确认选区和 revision；`beginComposition` 返回单调正 i32 `compositionId`，后续更新/提交/取消必须同时匹配身份与 revision。暂态只持有原文档和一个当前范围候选，不累计中间历史；query/Flow/几何读取候选，`EditState.selection` 返回候选光标，`compositionId` 非空，但已确认 XML、选区、revision 与 undo/redo 不变。更新为空或等于原选中文字时显示原文档与原选区。最终非空文字重新经同一范围事务提交，最多一项历史；空结束/取消/同内容 no-op 保留源字节、选区与 redo。开始结束普通输入组；更新及结束继续校验 XML、65536 UTF-16 单元、包输出和历史预算，CR/tab/LF 拒绝，失败保留上一个合法候选。成功开始/更新/取消/结束均废弃旧布局身份；组合期间普通选择/编辑/导航/复制、undo/redo、保存和 PDF 返回 `busy`，错误/过期身份返回 `stale-composition`，关闭释放候选。Chromium CDP/受控更新、结束、空取消及在途宿主销毁已验证；核心候选光标定位平台输入元素，成功候选和结束必须重新取得布局，不能只按 revision 判断。组件清理需 await dispose 后再使用/关闭 client；错误恢复先取消自身候选。R0 后的定向检查再次覆盖候选提交、取消与恢复；系统输入和候选窗几何的验证边界见本节开头。

宿主接受 `compositionend` 后，只消费一次最终文字相同、类型为 `insertCompositionText` 且非 composing 的尾随 `input`，不重复提交核心事务。键盘、beforeinput、新组合、失焦、保存、取消或错误清除这一关联；错误文字、类型或重复通知仍按未支持输入处理。Chromium 受控事件回归验证提交和错误边界。该关联最多保留一份命令预算内文字，不代表堆峰值或系统输入法验收。

`inputGroup` 是可选的正 i32 组号；省略时编辑命令独立成项。组号仅用于非空、无 LF 的普通输入，首项可替换支持的段内/跨段范围；核心仅在后续折叠选区等于已确认当前光标、上一项光标连续且组号相同时归并。单命令仍逐次增加 revision，整组 undo/redo 完整回放候选后一次提交、一次增加 revision，恢复首项前/末项后选区及节点身份。显式选择/导航、删除、未分组编辑、LF 输入、undo/redo 和关闭结束旧组；失败保持已确认组，核心保存不清空组/历史。组 payload 超过 4 MiB 时开启新完整项，整个历史仍按总 payload/100 项淘汰最旧完整项，文档文字保持；`historyEntries/historyBytes` 显示新的可撤销边界。宿主另在失焦、输出屏障和恢复时换组，并在接受排队意图时固定组号。当前组保留各次局部补丁，undo/redo 逐补丁重解析 XML；尚无校准延迟或峰值内存通过。

`DocumentEditor` 已提供有限浏览器输入宿主，与只读 `DocumentPreview` 共用页面绘制、图片预算和释放。调用者独占交付已打开的 client，宿主不维护文档树。点击、拖选、基本键盘输入、选区、删除及 DOCX/PDF 输出经最多 64 项意图队列发送；只移动光标不重建文档布局。输出携带确切 revision，PDF 绑定已完成的 layout ID，当前 revision 与最近输出 revision 分开显示。Tab 可首次进入当前页的可编辑位置，光标滚动可见。主指针拖选通过核心命中/选区 API，两轴边缘滚动按原页序跨页；空白页保留真实端点，末次坐标先于输入与输出，取消/失焦/捕获丢失停止滚动。同段内相邻显式分页符合并为一次布局分页，跨 run 也适用，保存仍保留每个原始分页符；正文、普通换行或独立段落分隔的分页不合并。这是维护者选择的固定 LibreOffice 行为，不授予 Microsoft Word 兼容性。失败需显式恢复，销毁保留原宿主 DOM 和调用者 client；不保证取消已在途核心事务。实际支持与暂未接收的输入见[开发说明](development.md)。

节的 `w:cols` 只识别无子列、`num` 缺省/1、`equalWidth` 缺省/true 的单栏声明；`w:docGrid` 只识别无子节点、`type` 缺省/default 的未启用模式。这些声明与单栏无网格布局一致，源内容保留；未知属性/子节点、自定义列和启用网格仍诊断并保护。此改动让原始 POI 普通正文可进入输入宿主，不增加多栏或网格排版引擎，验证范围见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)。

字节在 Worker 边界使用 structured clone。字体通过内部 `foundation_add_font` 导出，以每字符一个八位值的字符串传入核心。DOCX 和图片继续使用每操作一个 JSON/Base64 批次，输出反向转换。两种输入均需临时字符串和核心字节，不是零拷贝；原预算保持。轮廓通过 ASCII path 批量发送：`shape()` 返回缓存增量，`layout()` 返回可独立绘制的页结果和当前缓存资源；Canvas 按 key 复用 Path2D。一个 `CanvasRenderer` 必须绑定同一个核心会话的完整生命周期；`dispose()` 后不得复用。宿主负责展示诊断及提供可访问的文本/状态，Canvas 探针没有完整文档无障碍导航。

## P10 当前格式编辑

`FoundationSession/Client.queryFormatting(revision, selection)` 返回字符与段落属性。每项使用 `{ kind: "value", value }`、`{ kind: "mixed" }` 或 `{ kind: "unavailable", reason }`，同时返回 revision 和限制原因。`EditState.formatting` 包含当前选区的同一查询；没有选区或组合进行中为 null。查询只读取目标段落与继承样式，不要求解析无关图片。

`setCharacterFormat(revision, selection, format)` 支持 `family`、`size`、`color`、`bold`、`italic`、`underline`、`strike`、`highlight` 和 `vertAlign`。字号为 0.5–1024 pt 的半点增量；颜色为六位 RGB 或 `"auto"`。`underline/strike` 为布尔值，写单下划线与单删除线；`vertAlign` 为 `"baseline" | "superscript" | "subscript"`。`highlight` 使用 OOXML 的 `none` 和十六种命名颜色，Wasm/Web 的 `HighlightColor` 与 `highlightColors` 提供类型和完整选项；`none` 关闭高亮，null 恢复继承。

`setParagraphFormat` 支持 `align: "left" | "center" | "right" | "both"`、`before/after/left/right/first`、`line`、`pageBreakBefore`、`keepLines`、`keepNext`、`widowControl` 和 `rtl`。`both` 为两端对齐，写回 OOXML `w:jc`；默认 UI 提供同名按钮。距离单位为 pt，须能表示成整数 twip；范围 0–1584 pt，`first` 可为负值以设置悬挂缩进。`line: { rule, value }` 使用 OOXML 整数单位：`auto` 为每行 240，取值 120–2400；`exact/atLeast` 为 twip，取值 1–31680。UI 显示多倍行距或 pt，确认后转换为这些单位；清除段落直接格式也清除行距。

`keepNext: true/false` 设置或关闭“与下段同页”，null 清除直接定义并恢复样式继承。格式查询与 Flow 返回有效布尔值，默认格式和样式编辑面板提供同名字段；格式复制、拆段、样式应用及清除直接格式沿现有路径处理。连续开启的正文段落与后续末段开头行一起换页；末段开启孤行控制时至少保留开头两行，三行末段若整段可放入则保留全段。末段同时启用 `keepLines` 时保留其全部行。段前/后距及行距参与所需空间，空间可容纳链时省略阻碍其放入页首的段前留白。整页放不下的链按剩余可容纳部分逐步拆分，不循环回退或创建空页；显式段前分页及段内分页符终止该链。

段落链成为分页缓存中的一个块，后段变化会使前面的保留段落重新分页。普通可拆表格行内，同一单元格的相邻段落使用相同保留规则；超长链继续拆分，精确行高保持裁剪，跨格/跨行不链接。正文链可延伸到紧随表格的首个可放片段。可拆普通行按实际最小片段保留；禁止拆行、精确行高及首个纵向合并组按完整高度计算。首行显式分页优先；不能与前段合放的超长首行沿既有拆分规则继续，不反复移动前段。首行内容、高度、列宽或边框变化也使前段重新分页。预判与实际分页共用 [`table-measure.mbt`](../../modules/layout/src/table-measure.mbt) 和首片段计算，联动归 [`table-keep-next.mbt`](../../modules/layout/src/table-keep-next.mbt)。参考 [ONLYOFFICE KeepNext 回退规则](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/DocumentContentElementBase.js#L293-L340)及[向前失效处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L3058-L3078)，复用既有度量与分页预算，未引入旧版排版模式。实现归 [`keep-next.mbt`](../../modules/layout/src/keep-next.mbt)。

`widowControl: true/false` 设置或关闭正文孤行控制，null 清除直接定义并恢复样式继承。DOCX 缺省为 true，沿 [ONLYOFFICE 段落默认值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L16577)；Flow 和格式查询返回有效布尔值。默认格式/样式面板、格式复制、样式应用、清除直接格式和拆段共用既有路径，非法/重复/嵌套标记仍保护源内容。

正文自动断页尽量在两端各保留至少两行。三行段落面临单行拆分且整页可容纳时，整体移至新页；四行及以上若只剩一行在末页，且末两行可同页放入，则向末页多移一行。按实际行高和页首行距度量，空间不足两行时保留有界拆分回退；必要时省略空页上阻碍首段放入的段前留白。显式分页符优先，含显式分页的段落沿原规则。超长“段中不分页”段落仍拆分；“与下段同页”预判包含末段的孤行要求，后段变化向前使保留链失效。当前规则应用正文，格内和页眉保留有效属性并沿原排版规则，不额外施加正文孤行约束；对应 [ONLYOFFICE 正文孤行处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js#L1849-L1887)。实现归 [`widow-control.mbt`](../../modules/layout/src/widow-control.mbt)，复用现有行/页预算与统一绘制输出，不引入回退循环。

`keepLines: true/false` 设置或关闭“段中不分页”，null 清除直接定义并恢复样式继承；查询与 Flow 返回有效布尔值。默认格式面板和样式编辑面板共用现有命令，格式复制、拆段及清除直接格式也包含该属性。正文段落不能放入当前页时先整体换页；超出一页时在新页正常拆分，不重复尝试。页首空间不足时省略使整段无法放入的段前留白；显式分页符优先，含分页符的段落沿原分页规则执行。可拆的普通表格行按单元格段落保留整组行；整页放不下的格内段落继续拆分，精确行高仍裁剪。重复表头的空间检查包含待放段落，属性变化参与分页缓存失效。规则参考 [ONLYOFFICE KeepLines 分页](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js#L2545-L2590)的现代文档路径；不新增旧 Word 分页模式。多栏及跨页纵向合并仍待实现。

`FoundationSession/Client.styles(revision, kind)` 与 `DocumentEditor.styles(kind)` 返回现有样式目录：`{ revision, truncated, styles: [{ id, name, reason, basedOn, canDelete, canReset, linked }] }`，`kind` 为 `"paragraph" | "character"`，每类最多 1024 项。`basedOn` 为直接基础样式 ID，无继承时为空串；`canDelete` 表示已支持且未标为默认的自定义样式；`linked` 表示存在样式链接，`canReset` 表示有已支持的格式重置规则。不可应用的样式带原因，默认 UI 禁用对应选项。该接口替代原段落专用目录入口。

`rtl` 使用布尔值写回 `w:bidi`，null 清除直接定义并恢复继承。有效方向参与混合查询、格式复制、样式修改、拆段、历史与保存；默认 UI 提供方向开关。派生 `Paragraph.rtl=true` 指定 RTL 段落基准方向，false 保留既有的 Unicode 自动双向文字计算；本次未增加 run 级方向覆盖。制表与边界坐标归下文。格式、样式或设置修改引起重排时，核心清除已失效的双向层级与跨帧提示；撤销保留修改前选择。双向边界的 `before` 光标跟随前一片段，`after` 跟随后一片段，两者可位于不同视觉位置。

`setParagraphFormat({ style: id })` 校验样式及继承链，清除已支持的段落直接属性后应用样式；保留文字直接字符格式。同一补丁中的显式属性继续覆盖样式。应用默认样式时省略直接 `w:pStyle`；`style: null` 只清除样式引用并恢复默认样式继承。行为依据 [ONLYOFFICE 的段落样式应用](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js)。

`setCharacterFormat({ style: id })` 在目标范围写 `w:rStyle`，保留直接字符属性；`style: null` 清除引用，恢复段落继承和原有直接属性。跨 run 范围沿原边界拆分，折叠范围只设置后续输入样式，随实际输入或组合提交一项历史；取消组合保留输入意图。空段落标记的字符样式也参与查询与显示。行为依据 [ONLYOFFICE 的 Run 字符样式设置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js)。新建文档带 `DefaultParagraphFont`、`Emphasis` 和 `Strong`，继承与粗斜体切换沿已有 OOXML 规则；宿主须为最终组合提供字体 profile，不能只准备样式单独使用的字形。

两类查询均包含样式 ID 与混合状态，格式复制只捕获属性值，不复制样式 ID。未知属性、循环继承、跨类型继承及不支持的值拒绝应用，文档与历史保持原状。应用可一次撤销，支持保存重开和相同布局的 PDF。

`FoundationSession/Client.updateStyle(revision, id, update)` 与 `DocumentEditor.updateStyle(id, update)` 修改现有样式。`DocxStyleUpdate` 使用 `{ character, paragraph, name?, basedOn?, reset? }`。两类格式支持现有字段，不能包含 `style` 引用。字符样式只接受空的段落补丁。省略字段保留直接定义，null 清除定义并恢复继承。粗体、斜体和删除线的布尔值表示样式在文档默认值及 `basedOn` 链上的有效值，核心换算 OOXML toggle，分别处理复杂文字的粗斜体。名称只改变显示名，保留稳定样式 ID；名称须为非空、最多 200 UTF-16 单元的有效 XML 文字。

`basedOn` 指定同类型、已支持的基础样式；null 移除直接继承引用，省略时保留。更换基础样式保留原有直接定义，不固定旧基础样式的有效值。同一补丁的粗斜体、删除线和制表位按新基础样式计算。核心拒绝循环、跨类型、未知及超过 64 层的继承，并检查原本可用的依赖样式和正文组合。继承、名称与格式修改合为一项历史，撤销恢复完整源内容。行为参考 [ONLYOFFICE 样式继承与历史](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js)。默认 UI 的基础样式列表与当前样式类型一致，也可选“无基础样式”。

样式修改保留元数据、注释与未改正文。核心先检查候选、原本可用的依赖样式及正文直接属性的组合，再合并正文和样式 XML 校验包预算，一次提交 revision 和有界历史。失败不改变正文、部件、选择或历史；撤销/重做也先完整回放全部候选。输入、组合和保存使用同一组已提交部件。共享修改最多处理 4096 个样式，继承链沿既有 64 层上限。默认 UI 可修改所选样式的名称、基础样式及全部已支持的字符/段落属性。属性控件区分保持不变、设置值和恢复继承；粗斜体、下划线、删除线、方向与段前分页也可显式关闭。字符样式不显示段落属性。字体来自宿主提供的 profile，颜色接受六位 RGB 或 auto；行距以倍数或 pt 输入，制表位复用段落编辑字段。格式、名称和继承在确认后合为一项历史，不要求正文选区。目录按按钮显式刷新。DOCX 历史目前支持正文、样式及其他 Word XML 的修改，以及样式或设置创建所需的 XML 部件新增、关系和内容类型修改。已有部件的任意删除及二进制资源历史仍待对应操作接入。

`FoundationSession/Client.createStyle(revision, style)` 创建自定义样式，返回 `{ id, state }`。`DocxStyleCreation` 使用 `{ name, kind, basedOn? }`；`kind` 为 `"paragraph" | "character"`，可选的基础样式必须同类型且已支持。省略 `basedOn` 创建无直接继承的定义。Web 编辑宿主的 `createStyle(style)` 返回新 ID。核心分配身份，并避开 Word 部件中已有定义和引用；同类型样式不接受重复显示名。创建不改变选区或立即应用到文字，之后可用现有应用和修改方法。默认 UI 读取目录后可新建；有选中项时以它为基础，没有选中项时不设基础样式。样式管理不要求正文选区，应用和清除仍需要有效选区。

导入文件缺少样式部件时，核心在主文档旁创建唯一 XML 部件，原子补齐主文档关系和内容类型。原有同名部件、关系 ID、外链和未知内容保留。新定义和包元数据合为一项有界历史，新增 XML 的源内容计入历史预算；包图、输出或历史预算失败不改变状态。撤销移除本次新增部件并恢复原包，重做保留后续修改所需的节点身份。保存重开后使用同一关系与样式 ID。

`deleteStyle(revision, id, replacement)` 删除自定义样式，替代样式必须已支持且类型相同，也不能依赖被删样式。Web 编辑宿主省略 revision。核心同步移除定义并替换 WordprocessingML 部件中的样式引用，包括正文、页眉和编号；保留直接格式、文字、其他样式及未知内容。折叠处待输入的样式引用也映射到替代项。命令至多替换 65536 个引用，继续受包与历史预算约束。全部候选成功后一次提交，撤销同时恢复各部件与选择。默认 UI 可显式选择同类型替代样式，初始使用基础样式；无基础样式时须先选择替代项。没有有效替代项时不能删除。删除链接自定义样式时保留对端样式，解除指向被删样式的链接，再替换普通引用；未知链接内容明确拒绝。默认及内置样式不能删除。

`updateStyle(id, { character: {}, paragraph: {}, reset: true })` 显式重置格式，不能同时传其他修改。当前支持文档默认段落/字符样式，以及 Normal、DefaultParagraphFont、Strong、Emphasis、Heading1–Heading9，以及 NoSpacing、Quote、Caption、QuoteChar、SubtleEmphasis、IntenseEmphasis 和 IntenseQuoteChar。默认样式恢复文档默认属性；Strong/Emphasis 继承当前默认字符样式并恢复粗体/斜体。稳定 ID、名称、默认标志、next/link 和正文直接格式保留；其他内置样式的重置规则尚未实现。默认 UI 提供同一操作。重置沿上述候选校验及单项历史提交，撤销恢复完整源内容。行为参考 [ONLYOFFICE 样式重置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L8854-L8889)。样式修改与删除还会校验正文继承的编号引用、有效级别属性和标记结果，失败保留原包。

新增预设继承当前对应类型的默认样式。NoSpacing 清除字符覆盖，段后距为 0、单倍行距；Quote 设置 8 pt 段前距、居中、斜体及 text1 的 BF tint；Caption 设置 10 pt 段后距、单倍行距、9 pt 普通/复杂文字字号、斜体及 text2 颜色。QuoteChar/SubtleEmphasis 使用引用的字符属性；IntenseEmphasis/IntenseQuoteChar 使用斜体及 accent1 的 BF shade。段前后其他未声明值沿基础样式继承，正文直接覆盖保持。

按标准 ID 或对应英文内置名识别，名称不区分大小写，自定义标志及类型不符的样式不套用预设。名称、别名、link/next 和源元数据保持，不创建缺失样式。已有主题时保留颜色关联；相关主题色不可解析时保护重置。没有主题时写预设 RGB，不增加主题部件；之后添加主题可再次重置以建立关联。默认目录的 `canReset` 自动开放已有按钮，沿同一候选、预算、单项精确历史和保存重开，无变化不提交。预设参数参考 [ONLYOFFICE 默认样式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles/default-styles.js#L621-L795)与[题注](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles/default-styles.js#L913-L938)，实现归 [`style-presets.mbt`](../../modules/formats/src/docx/style-presets.mbt)。标题/副标题的字符间距、完整强引用边框及其余未支持预设继续保护，不以删去属性代替重置。

九级标题的创建和重置共用本项目的标题预设：大纲级别 0–8，字号依次为 16、14、13、12、11、11、11、11、11 pt，并设置粗体标记。重置继承当前默认段落样式；没有默认标记时尝试 Normal，均无时继承文档默认属性。字体与颜色沿基础样式继承，正文直接格式保持。按标准 ID `Heading1`–`Heading9`，或非自定义段落样式的英文名 `Heading N` 识别；名称不区分大小写。自定义样式即使同名也不作为内置标题重置。

标题重置保留名称、别名、next/link、元数据和其他样式，恢复支持的标题字符/段落预设。初始预设及重复重置不新增历史；默认角色有歧义、属性源含未知注释或候选校验失败时保持原包。这里使用与本项目空白文档一致的预设，不声明完整 Office 内置样式、主题及所有导入变体的视觉一致性。

两端对齐在塑形后扩展词间空格；无空格中文使用合法断行处的字形簇间隙，接近满行的普通单词可使用字形簇间距。连字与字形不重塑，末尾空格不参与扩展，最后一个 Tab 之前的位置保留。段落末行与显式分页行保留自然宽度，RTL 末行靠右。软换行默认参与对齐；派生 `Paragraph.expandSoftBreak` 读取设置中的 `compat/doNotExpandShiftReturn`。光标、命中、选区、装饰与 PDF 消费相同位置；阿拉伯文使用词间距，未新增 kashida 字形。规则参考 [ONLYOFFICE 的段落对齐计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js)。

字段省略表示不修改，null 清除对应直接属性并恢复继承。MoonBit 使用 `FormatChange::{Keep, Clear, Set}` 和类型化属性结构。字符范围在边界处拆分 run，范围外文字与未知部件保留；段落属性覆盖范围接触的段落。一次修改提交一项有界历史，保存与 PDF 沿现有布局。无效位置、过期 revision、属性和预算失败不提交部分修改。

折叠范围只改变后续输入属性，不增加 revision、历史或空文字。实际输入及格式一起提交；组合预览沿候选处理，取消仍保留输入属性。显式选择/导航结束该输入属性，保存本身不改变它。默认 UI 的字体/段落控件调用同一 Web 队列，数字与颜色确认后提交；字体仍需宿主供应对应 profile 和字节。

`FoundationSession/Client.captureFormat(revision, selection)` 返回核心计算的 `CopiedFormat: { character, paragraph }` 属性片段。它只含当前已支持且在选区内一致的有效值；混合属性省略，应用时保留目标对应值。片段包含值，不绑定源位置或 revision，也不包含页面几何、样式或列表身份。`applyFormat(revision, selection, format)` 校验目标 revision 与完整片段，字符和段落候选全部成功后一次提交；失败保留文档与历史。折叠处的字符格式仍作为后续输入属性，段落修改立即提交。Web 编辑宿主提供同名方法，默认 UI 使用“复制格式”和“应用已复制格式”；替换文档后清除 UI 中的片段。应用后可一次撤销两类源修改，保存与 PDF 沿现有格式路径。

核心在连续塑形的光标位置上划分装饰，先绘制高亮背景，再绘制文字与下划线/删除线；编辑装饰不改变连字与断行宽度。上下标沿 ONLYOFFICE 的 0.65 字号比例、上移 0.35 / 下移 0.141 个原字号计算，保持逻辑文字、源 offset 和原字号属性。行高与选区包含实际基线。相同图元用于 Canvas 与 PDF，不由 DOM 或 CSS 计算文字几何。其他下划线类型或颜色变体保留源并诊断、保护编辑，未宣称完整装饰兼容。

派生 `TextStyle` 增加 `underline/strike`、RGB `highlight`（无高亮为空串）和 `script`；MoonBit 的 `TextStyle::new(font, size, color)` 创建普通样式。当前 `TextProbe::text_block` 只返回文本块，上下标可排版，装饰明确拒绝；XLSX/PPTX 仍使用普通样式，后续各自编辑功能接入效果图元。

`FoundationSession/Client.findDocx(revision, text, options?)` 进行字面查找；`options` 为可选的 `matchCase`、`wholeWord` 布尔值。返回 `{ revision, truncated, matches: [{ selection, snippet, reason }] }`。结果按正文与表格单元格顺序排列，相邻同容器段落以 LF 相连。受保护文字也返回命中与原因，不能替换。查询最多 65536 UTF-16 单元，最多返回 1000 个不重叠命中；超过上限设置 `truncated`。

查找使用 Unicode 简单小写映射，不做规范化、语言定制或正则匹配。全词边界按字母/数字和非 ASCII Unicode 标识符延续字符判断，ASCII 下划线作为分隔符。命中不能切开字素或代理对。范围暂限主文档正文与单元格，页眉、脚注等内容区域待对应编辑能力接入。

`replaceDocxMatches(revision, selections, text)` 一次校验全部范围后提交一项历史；空数组无变化，重叠、空范围、保护、过期 revision 和预算失败不部分提交。替换最多 1000 个范围，文本最多 65536 UTF-16 单元，允许 LF 段落分隔、U+2028 软换行、U+000C 正文分页与 Tab，不接受 CR。插入文字沿用目标起点 run 格式。结构替换另限源 XML UTF-16 长度乘命中数不超过 67108864，避免逐项解析阻断操作。

`DocumentEditor.find(text, options?)` 在原队列中查询，并给结果增加 `documentId`。`selectMatch(result, index)` 定位可编辑命中；`replaceMatches(result, text, index?)` 替换指定项，省略 index 时替换全部结果。全部替换拒绝 `truncated` 或含受保护内容的结果。旧文档或旧 revision 的结果拒绝后仍可继续编辑。默认 UI 提供同一组操作，编辑后提示重新查找并禁用旧结果。

`DOCX_SOFT_BREAK` 为 U+2028，由 Wasm/Web foundation 导出。`replaceRange`、组合候选和批量替换用它表示段内换行，保存为 `w:br`；实际 LF 仍创建段落。`DocumentEditor.insertSoftBreak()` 与默认 UI 按钮、Shift+Enter 调用同一范围事务。`query().texts` 包含普通文字与内联控制节点；换行逻辑长度为一个 UTF-16 单元，`w:cr` 同样读取为 U+2028。Flow 用 LF 排版，`selectedText` 与剪贴板将软换行转为 LF。普通换行可删除、选中、设置格式及跨段移动；栏换行、环绕清除和未知内联属性继续保护。

`DOCX_PAGE_BREAK` 为 U+000C，由同一 foundation 入口导出。正文 `replaceRange`、组合候选、查找替换及 `DocumentEditor.paste(DOCX_PAGE_BREAK)` 用它插入 `w:br w:type="page"`，不增加段落。默认 UI 的插入分页符按钮及 Ctrl/Cmd+Enter 使用相同事务，单独形成历史。已有正文分页符支持选择、格式与删除，保存及撤销保留源节点。普通表格单元格内也支持分页符的读取、插入、选择、格式、删除、查找替换和精确历史；按 [ONLYOFFICE 表格内分页符规则](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L4696-L4712)，它不触发换行或换页。核心保留源 `w:br` 和 UTF-16 位置，按零宽控制塑形，表格行继续按既有规则续页。正文与格内的段落缓存区分上下文，列宽、光标、命中、合并续排及 PDF 共用此行为；PDF 的文字映射和 ActualText 排除不显示的分页符。布局保留相邻分页符合并规则；仅供分页符光标定位的空行不占段落高度、不进入页面文字，也不改变空白页拖选端点。

Tab 输入与粘贴保存为 `w:tab`，不转成空格。`FoundationSession/Client.tabDocx(revision, backward?)` 在列表正文执行下述列表规则；普通正文插入 Tab，反向时减少正的首行/左缩进；在现有表格中只移动到相邻单元格，不增加 revision 或历史。默认 UI 的插入制表符按钮与 `DocumentEditor.paste("\t")` 总是插入字符，原生 Ctrl+Tab 也在单元格中插入。Tab/Shift+Tab 只由文档原生输入处理；参数控件使用浏览器焦点切换，Escape 将焦点移出文档输入。

`Paragraph.defaultTab` 为 point，来自 `settings/defaultTabStop` 的整数 twip，默认 36 pt，范围 0–1584 pt；0 表示零宽。核心根据当前行位置与缩进计算下一默认制表位，断行、光标、预览与 PDF 消费同一宽度。末格 Tab 保持原位置，自动追加表格行归表格编辑批次。

`FoundationSession/Client.setDefaultTabStop(revision, interval)` 与 `DocumentEditor.setDefaultTabStop(interval)` 修改文档默认间隔，不要求正文选区。`interval` 为 0–1584 pt，须能表示成整数 twip；null 清除显式设置并恢复 36 pt。`EditState.defaultTabStop` 提供当前有效值，默认 UI 可修改或恢复。修改保留自定义制表位、逻辑 Tab、待输入格式与未知设置；现有相同值不产生历史。缺少设置部件时，XML、关系与内容类型一并创建。设置修改或创建合为一项有界历史，失败保留已提交包，撤销和重做恢复各部件及选择。候选先验证设置值和包预算，再提交并使相关布局失效。未知目标标记、重复设置、外部/重复设置关系，以及强制保护的文档设置拒绝修改。行为参考 [ONLYOFFICE 的文档默认制表位历史](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js)。

`setParagraphFormat({ tabs })` 使用 `TabStop[]`：每项为 `{ position, align, leader? }`，位置单位为 pt，须为 0–1584 pt 的整数 twip，按位置递增且不重复，最多 64 个有效位置。`align` 支持 `left/right/center/decimal/bar`。`leader` 省略时为 `none`，也支持 `dot/hyphen/underscore/heavy/middleDot`；`bar` 只接受无引导线。MoonBit `TabStop.leader` 与核心返回值总带明确值。字段省略保留；null 清除段落直接定义并恢复继承；空数组清除全部有效位置，核心为移除的继承位置写 `w:tab w:val="clear"`。格式查询与格式复制包含有效制表位。默认 UI 可添加、修改、移除、应用、清除全部与恢复继承，使用同一历史与保存路径。

派生 `Paragraph.tabs` 提供合并后的有效位置。核心按后续片段宽度放置右/居中制表位，小数点使用文档 `settings/decimalSymbol`（派生 `Paragraph.decimalSymbol`，默认 `.`）；越过可用边缘的自定义位置按右边缘放置，悬挂缩进保留隐式左边界位置。规则参考 [ONLYOFFICE 的制表位合并](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js)与 [Tab 后续文字定位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js)。未知标记仍保留源并保护编辑。`Paragraph.rtl` 为 true 时，制表原点移到正文右边缘，按向左的距离计算默认及自定义位置。左/右缩进分别作用于起始/末尾边缘，首行缩进和对齐沿同一方向；竖线也按右边缘定位。文字字形保留塑形后的顺序和局部坐标，小数点按后续片段的视觉位置锚定。规则参考 [ONLYOFFICE 的 RTL 制表定位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js)。标尺交互仍待实现。

引导线按 [ONLYOFFICE 的 Tab 字形绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/RunContent/Tab.js)使用当前字体与字号，重复字形居中放入间隔；短划线使用 1.5 倍步长，`heavy` 与 `underscore` 使用下划线字形。逻辑文字、光标与复制内容仍为一个 Tab，PDF 的 ActualText 不加入装饰字符。每个 Tab 最多 4096 个引导字形，每行 16384 个、每段 65536 个；超过预算明确拒绝布局。

`bar` 遵循 [Word 的竖线制表位语义](https://support.microsoft.com/en-us/word/using-the-ruler-in-word)，在每一行的指定位置绘制竖线，不改变文字或 Tab 定位。当前核心绘制 0.5 pt 黑线，沿行高延伸，预览与 PDF 共用图元；未宣称与 Word 的全部显示细节一致。派生 `Line.bars` 随分页定位，缓存与公开行结果各自持有数组副本。

当前未接通标尺和其他内置样式重置规则。主题颜色与字体见下节。剩余范围归 [P10](../p10-docx-core.md)，不把本切片记作完整格式编辑。

### 导入超链接文字

正文及普通单元格中的 `w:hyperlink` 已按源顺序读取其直接 run。链接内文字参与布局、命中、选区/复制、字面查找替换、格式查询与修改，以及原生输入/组合、Tab/软换行/分页符和段落拆分/合并。空链接 run 可继续输入。链接的 run 格式沿普通字符和段落样式计算；不强制替换源颜色、下划线或字符样式。Canvas 与静态 PDF 使用同一文字和格式。

文字编辑保留 `r:id`、anchor、docLocation、history、tgtFrame、tooltip、相邻注释和原关系。Enter 在新段落延续相同链接容器；合段保留原容器、局部命名空间和各 run 原段落继承的格式，不合并两个独立链接身份。文字、结构与格式仍沿同一有界历史精确撤销/重做。链接帧计入既有多段输入源预算，失败不提交源、关系或历史。

当前支持单层链接和直接 run；未知属性、目标缺失、非法 history、嵌套容器、字段及修订继续保留源并保护相关编辑。链接内插入图片暂时拒绝，避免创建当前图片编辑器不支持的容器。文字读取不获取或执行链接目标；目标操作见下节。实现归 [`hyperlink-read.mbt`](../../modules/formats/src/docx/hyperlink-read.mbt)，容器读取与拆分参考固定 [ONLYOFFICE 链接读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Serialize2.js#L12003-L12037)及[链接拆分](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Hyperlink.js#L188-L197)。

普通左右箭头将非空文字选区收敛到对应边界，不再向右额外走一字；继续按箭头才移动。该规则与 [ONLYOFFICE MoveCursorRight](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L6051-L6092)一致，位置和保护仍由核心布局确定。

### DOCX 外部超链接

`FoundationSession/Client.setHyperlink(revision, selection, target, text?)` 和 `DocumentEditor.setHyperlink(target, text?)` 创建、修改或移除正文/普通单元格的外链。target 为 HTTP、HTTPS 或 mailto 地址，null 移除链接但保留文字。地址最多 2048 UTF-16 单元，拒绝空目标、空白、控制字符、反斜杠及非法 XML/Unicode。`checkDocxHyperlink` 从两个 foundation 入口提供相同输入检查，核心仍独立校验。

非空选区只修改所选字符，可跨 run 和相邻段落。链接内光标修改当前完整链接容器；原生连续输入的末端按实际输入节点查询和修改。普通光标创建链接时须提供 text。text 为非空、至多 65536 UTF-16 单元的单行普通文字，提供时替换整个目标范围；链接内光标替换完整链接文字。替换可合并相邻段落，之后光标留在新链接末尾并可继续输入。空链接重复移除及相同目标不新增历史。

`DocxFormatting.hyperlink` 返回 `{ target, mixed, reason }`；非共同目标为 null，mixed 为 true 时可统一设置或移除，reason 说明目标保护原因。原字符格式保持，不自动套用 Hyperlink 字符样式；默认面板提供地址、显示文字、应用、移除和显式打开，外链使用新窗口及 `noopener noreferrer`。普通输入和临时组合状态不覆盖未提交地址草稿；非法地址在进入编辑队列前提示，原文档仍可编辑和保存。打开文件、查询、布局及应用链接都不请求外链。

复用字符边界拆分和关系事务。已选链接的提示、history、tgtFrame 与未选两端保留；移除容器时补齐 run 和书签的局部命名空间，保留文字、格式和注释。相同外部目标复用关系，不改写共用关系或清理旧关系。显示文字、链接 XML、新增/修改关系合为一项历史；过期 revision、活动候选、图片、未知源及源/输出预算失败均不提交。内部目标扩展见下节；docLocation、同时具有外链关系和 anchor 的组合目标及未知关系继续保护。链接样式管理与交互 PDF 注释仍待 [P10](../p10-docx-core.md) 后续实现。范围与光标语义参考 [ONLYOFFICE 链接操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L7811-L8180)，实现归 [`hyperlink-edit.mbt`](../../modules/formats/src/docx/hyperlink-edit.mbt)及 [`hyperlink-query.mbt`](../../modules/formats/src/docx/hyperlink-query.mbt)。

### 书签与内部导航

`FoundationSession/Client.overview(revision)` 的 `bookmarks` 返回 `{ name, selection, reason }[]`，最多 4096 项。支持正文、普通单元格及单层链接内的成对书签；空光标、文字范围、跨段和交叠范围均不占逻辑文字宽度。重复名称/身份、缺失或倒置标记、列书签和未知容器保留源，以 reason 说明保护原因，selection 为 null。

`editBookmark(revision, change)` 与宿主 `DocumentEditor.editBookmark(change)` 接受四种命令：`{ action: "create", name, selection }`、`{ action: "rename", name, replacement }`、`{ action: "remove", name }`、`{ action: "goTo", name }`。创建/改名使用 1–40 个 ASCII 字母、数字或下划线，首字符不能为数字。名称查找及去重忽略大小写；重复创建拒绝。goTo 将光标移到当前书签起点，不改 revision 或历史。默认概览面板提供创建、改名、删除及跳转，复用原生输入和编辑队列。

`setHyperlink` 的 target 另接受 `#书签名`，必须对应当前可用书签。内部链接写入 `w:anchor`，不新增 OPC 关系；外部与内部目标可相互修改，保留原提示和直接格式。默认面板的“打开链接”执行核心定位。改名同时更新主文档已知 anchor 引用；删除书签同时移除这些链接容器，保留文字、格式及命名空间。其他 XML 部件中的 anchor 或包含该名称的字段指令会保护改名/删除，避免悬空引用；交叉引用字段更新仍待实现。

普通文字、组合输入、格式、查找替换和拆段/合段保留零宽标记。范围替换删除中间段落时，丢失的已知端点收缩到替换后的光标；同一位置的起点先于结束标记。删除含书签的表格行等其他结构操作若会破坏配对，则整项拒绝。未知标记源保持。每次创建、改名、删除及相关引用更改合为一次有界历史；保存重开保留范围和导航，预算失败不提交。当前 PDF 仅保留文字与格式，不含可点击注释。

名称匹配及书签定位参考固定 [ONLYOFFICE Bookmarks.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Bookmarks.js#L353-L366)，配对插入及移除参考 [Document.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L24423-L24568)。未复制上游代码；实现归 [`bookmark-read.mbt`](../../modules/formats/src/docx/bookmark-read.mbt)和 [`bookmark-edit.mbt`](../../modules/formats/src/docx/bookmark-edit.mbt)。

### DOCX 本地批注

`FoundationSession/Client.comments(revision)` 返回 `{ revision, reason, items }`；宿主 `DocumentEditor.comments()` 另带 `documentId`。每项包含规范非负 `id`、`author`、`initials`、源 `date`、纯文字 `text`、逻辑 `selection`、保护 `reason`、`parent` 和 `done`。根批注的 parent 为 null，单层回复指向根 id，并使用根的范围及解决状态。支持正文、普通单元格及单层链接内的传统批注范围；单个 `commentReference` 可表示点锚点。未解析的条目保留源，selection 为 null 并说明原因；未知批注部件或不支持的扩展返回整体原因，不暴露部分列表。

`editComment(revision, change)` 和 `DocumentEditor.editComment(change)` 接受 `{ action: "add", text, author, initials, date, selection }`、`{ action: "update", id, text }`、`{ action: "remove", id }` 和 `{ action: "goTo", id }`。创建使用显式范围或光标，作者由宿主提供，时间为平台传入的有效 UTC ISO 字符串；核心不读账号或时钟。默认面板复用 `EditorOptions.commentAuthor`，未提供时仍可读取、修改和删除已有批注。跳转选中当前完整范围，不修改修订、源或历史；文字草稿在正文输入和拆段后保留。

`{ action: "addWord", text, author, initials, date, selection }` 要求折叠光标，由核心按 Unicode 单词边界扩展，跨字符格式和普通链接取词。光标正好位于词尾时选择前词，空白或无单词处保留点锚点；不切开代理对和组合字素。分段复用已安装的 UAX #29 实现，不使用浏览器 DOM 或词典分词。创建后选中该范围，撤销恢复原光标。默认面板在折叠光标处使用此命令；显式 `add` 仍按传入的范围或点创建。

`FoundationSession/Client.navigateComment(revision, "previous" | "next")` 返回 `{ comment: string | null, state: EditState }`；`DocumentEditor.navigateComment(direction)` 在现有队列内应用状态，并更新 `getCommentFocus()`。按正文和普通单元格的源顺序循环，跳过回复、已解决和不可定位的根批注。下一条选择起点严格在当前选择前端之后的批注；上一条选择终点不晚于该前端、起点更早的批注，末端循环。当前范围内的光标和点锚点按同一规则离开；没有可用项时返回 null，保留选择、源、修订和历史。默认面板提供上一条/下一条按钮。

光标处取词依据 [ONLYOFFICE AddComment](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L14184-L14227)，顺序导航目标依据 [GenOffice gotoComment](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/review-actions.ts#L284-L305)。未复制上游源码。实现归 [`comments-selection.mbt`](../../modules/formats/src/docx/comments-selection.mbt)及 [`word-range.mbt`](../../modules/layout/src/word-range.mbt)。

`{ action: "reply", id, text, author, initials, date }` 回复指定根批注，沿用相同文字/作者/时间上限，不创建重复正文标记。`{ action: "resolve", id, done }` 从根或回复设置整线程的解决状态，false 重新打开；已经一致时不新增历史。默认面板按根分组显示回复，提供回复编辑/单条删除、解决/重开及整线程删除。删除根同时删除其全部回复和扩展记录；单条回复删除保留根及其他回复。

`PageLayout.comments` 返回只读 `{ reason, items: [{ id, reason, rects }] }`，rect 含 `page/line/x/y/width/height`，单位为 point。仅未解决根批注产生高亮，回复共用根，点锚点显示窄条。几何复用核心塑形选区、跨页与普通单元格裁剪，并裁到物理页面；组合候选沿显示源更新，取消不改变已提交源。一次最多 4096 项、65536 个矩形，根数与页面 caret/行总数的乘积不超过 8 Mi；超限或缺失正文返回原因，不返回不完整的全局结果。单条不可定位时保留其原因和空矩形。

Web 编辑宿主按相同坐标绘制独立覆盖层。点击高亮沿既有指针/命令队列选择完整范围并定位面板，保留原生输入焦点；拖动、Shift 扩选及取消手势不触发批注跳转。重叠批注按返回顺序定位首项，其他条目仍可从面板选择。`DocumentEditor.getCommentFocus()` 返回最近一次成功跳转的只读 UI 身份 `{ id }`；其他批注修改会清除它。该视图状态不进入文档。解决后隐藏高亮，重新打开后恢复；缩放、翻页和选择覆盖层刷新保持核心位置。高亮不进入 R0 正文或默认静态 PDF，也不改变修订、源及历史。

新文字非空且最多 32767 UTF-16 单元，CRLF/CR 归一为 LF；作者非空且最多 255 单元，缩写最多 32，两者不接受控制字符。每文档最多 4096 条，包含回复，合计 1 Mi 文字单元。导入正文接受普通段落、字符属性及 Tab/软换行；文字替换继承首段及首 run 的属性，保留作者、日期、批注身份、外围注释和局部命名空间。可读取和删除空正文，也可显式修改。表格等未知批注正文、资源关系、共享/外部部件，以及不支持的现代扩展保持保护。

单层线程支持 `w15:commentsEx/commentEx`，用 `paraIdParent` 连接批注正文末段的 `w14:paraId`，用 `done` 记录状态。八位十六进制身份忽略大小写匹配，新增身份避开全部已有批注段落；正文修改保留线程使用的末段身份。首次回复或解决创建所需段落身份、commentsExtended 部件、主文档关系和内容类型，合为一项精确历史。空扩展部件继续可用，新根自动取得独立身份；最后删除后保留空部件和关系。缺失属性写入复用当前命名空间，保留源前缀、外围及节点内注释。缺失/重复身份、悬空或嵌套/循环回复、未知属性及共享/外部扩展继续原子保护。

已支持导入 `commentsIds` 和 `commentsExtensible`。`paraId` 连接批注末段，`durableId` 连接 UTC 元数据，两者均按八位十六进制、忽略大小写匹配；公开 id 仍为正文批注身份。修改正文保留映射、原 UTC 时间、已知 Office presenceInfo 和根批注的 follow-up 标志。向已有身份部件新增根或回复时，为新条目分配独立段落及持久 ID；已有 UTC 部件同时写入宿主提供的时间。首次线程为缺少身份的根补齐映射，不升级普通新建文件的格式。允许已有身份列表只覆盖部分批注；已有记录必须唯一且能定位，UTC 部件必须有对应身份部件。列表的 date 优先使用非空 dateUtc，缺少时读取批注正文 date；两处源属性均保持原值。

删除回复或整线程同时删除相应身份与 UTC 记录，其他记录、外围注释和关系保留；所有部件共用原子预算及精确历史。标准 `mc:Ignorable` 根属性可保留，仍逐项校验实际节点及属性，不因此忽略未知内容。重复/悬空映射、回复携带 follow-up 标志、未知 presence 扩展及共享/外部元数据返回保护原因。依据 [ONLYOFFICE 的段落及持久 ID 映射](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Document/BinWriter/BinaryWriterD.cpp#L8738-L8775)、[元数据写回](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Document/BinReader/ReaderClasses.cpp#L749-L780)及 [MS-DOCX CT_CommentExtensible](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-docx/a7b57225-42e5-43e7-8d98-d90eabf3ca25)。未复制上游源码。实现归 [`comments-modern.mbt`](../../modules/formats/src/docx/comments-modern.mbt)；其他现代扩展继续实施。

首次创建把 comments、正文标记、主文档关系和内容类型合为一项有界事务。标记不占正文宽度；输入、格式、链接修改及拆段/合段维护范围，范围替换删除中间段落时丢失的端点收缩到替换后光标。与书签共用已有边界拆分及位置计算。其他结构操作若会破坏锚点，则原子拒绝。删除同时移除正文标记和批注正文，最后一条删除后保留空部件及关系。旧修订、活动候选和包/输出/历史预算失败不提交；保存重开及精确混合撤销重做沿原事务。正文查找、排版和默认静态 PDF 不包含批注文字。

标记与正文属性依据 [ONLYOFFICE Annotations.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Logic/Annotations.cpp#L70-L145)、[RunContent.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Logic/RunContent.cpp#L752-L803)及 [Comments.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Comments.cpp#L281-L291)；跨段端点参考 [Document.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L22584-L22616)。线程格式依据 [Comments.cpp 的扩展属性](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Comments.cpp#L420-L433)、[ReaderClasses.cpp 的末段身份与父关系](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Document/BinReader/ReaderClasses.cpp#L659-L748)及 [BinaryWriterD.cpp 的回复映射](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Document/BinWriter/BinaryWriterD.cpp#L8692-L8738)。高亮与命中参考 [Comments.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Comments.js#L923-L953)及[标记绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Comments.js#L1383-L1421)。未复制上游源码。实现归 [`comments-read.mbt`](../../modules/formats/src/docx/comments-read.mbt)、[`comments-edit.mbt`](../../modules/formats/src/docx/comments-edit.mbt)、[`comments-threads.mbt`](../../modules/formats/src/docx/comments-threads.mbt)、[`comments-range.mbt`](../../modules/formats/src/docx/comments-range.mbt)、[`comments-layout.mbt`](../../modules/formats/src/docx/comments-layout.mbt)及 [`docx-comments.tsx`](../../packages/ui/src/docx-comments.tsx)。现代批注兼容继续按 [P10](../p10-docx-core.md) 实施。

### DOCX 主题颜色

`FoundationSession/Client.themeColors(revision)` 返回 `DocxThemeColors = { revision, colors }`，包含 `dk1/lt1/dk2/lt2`、`accent1`–`accent6`、`hlink/folHlink` 十二项。每项含 `slot/color/reason`；无法读取的色项颜色为 null，限制原因单独返回。`DocxThemeSlot` 与查询类型沿 `wasm/foundation`、`web/foundation` 导出。查询不修改源或历史；没有主题时返回新主题的默认颜色。

`setThemeColor(revision, slot, color)` 接受上述色项和六位 RGB。`DocumentEditor.themeColors()` 与 `setThemeColor(slot, color)` 沿现有意图队列获取 revision；默认属性面板先加载色表，确认后提交，原生文字输入保留颜色草稿。已有主题从主文档的内部关系定位；缺少主题时，按现有 Word 部件事务分配名称和关系身份，同时创建完整主题、关系及内容类型，不覆盖同名孤立部件。默认字体为 Times New Roman，正文直接格式保持。

文字及列表标记按 `w:themeColor` 解析主题，覆盖缓存 `w:val`；段落/字符样式和普通单元格文字共用相同解析。支持 `clrSchemeMapping` 的文字/背景、强调色和链接映射。`themeShade` 后接 `themeTint`，沿 HSL 亮度应用十六进制字节比例；直接颜色保持。显式设置字符颜色会清除该项的主题颜色及明暗属性，恢复继承则移除整个直接定义。源主题引用和缓存颜色在主题修改后保留，预览与 PDF 消费派生颜色。明暗计算参考 [ONLYOFFICE RtfColor](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/RtfFile/Format/RtfProperty.cpp#L496-L514)。

主题修改、首次创建的元数据及选择合为一次有界历史。撤销/重做重新派生颜色；相同有效颜色保留源和布局，不新增 revision。系统颜色读取 `lastClr`，仅在改变颜色时替换为 RGB。目标颜色的未知属性、子节点、注释、处理指令、重复/外部主题关系，文档保护与主题锁保持拒绝；非法参数、旧修订、活动候选及预算失败不提交。整套主题导入，以及表格底色/边框与绘图对象的主题色仍属后续范围。实现归 [`theme.mbt`](../../modules/formats/src/docx/theme.mbt)和 [`theme-edit.mbt`](../../modules/formats/src/docx/theme-edit.mbt)。

### DOCX 主题字体

`FoundationSession/Client.themeFonts(revision)` 返回 `DocxThemeFonts = { revision, fonts }`，包含 `kind: "major" | "minor"` 的两项。每项返回原始 Latin `font` 和限制 `reason`；无法读取时字体为 null，空串表示源定义为空。`DocxThemeFontPair` 为 `{ major, minor }`。`setThemeFonts(revision, fonts, profile)` 一次修改标题/正文的 Latin 字体对，保留现有 EA、CS、补充脚本、扩展和已知字体元数据。两个字体均为非空实际字体族，最多 200 UTF-16 单元；不接受主题占位符、字体键分隔符、非法 XML 文字和换行。

`DocumentEditor.themeFonts()` 与 `setThemeFonts(fonts)` 复用意图队列，宿主自动携带当前字体 profile。默认面板显式加载、修改和应用字体对，加载会恢复源值，原生输入保留面板草稿。没有主题时沿已有 Word 部件事务创建主题、关系及内容类型；未使用的字体定义不要求加载对应字体。

字符样式逐层保留 ASCII、HAnsi、东亚及复杂文字的直接或主题字体绑定。相同槽内的主题引用优先于缓存字体，较高层直接定义覆盖较低层绑定；`major/minor` 的八个 Word 字体别名分别解析到 Latin/EA/CS。空的主题槽回退到正文 Latin，再回退 Arial，遵循 [ONLYOFFICE FontScheme.checkFont](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L10082-L10135)。直接字体保持；EA/CS 和补充脚本的直接编辑、语言匹配及整套主题导入仍待扩展。

字体槽按 [ONLYOFFICE FontClassification](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/Run/FontClassification.js#L48-L266) 的码点范围、东亚提示和中文语言提示选择。`w:cs/rtl` 强制复杂文字槽，东亚提示及私用区保留上游优先级；复杂文字使用独立 `bCs/iCs/szCs`。核心只在字素边界拆分派生 span，保留原文字节点及 UTF-16 逻辑位置；混合格式查询、光标、空段落、普通单元格和列表标记沿相同规则，保存不拆分源 run。

提交前校验字体对、源定义、主题锁及受影响段落的实际字体键，包含粗斜体，并检查 profile 与已注册字体。主题和新元数据合为一次有界历史，保留选择、后续输入格式、源别名和未改 XML；无变化不增加 revision 或清除布局。旧修订、活动候选、缺字体、未知目标定义及预算失败原子拒绝。主题改变后，现有排版缓存按派生字体失效，Canvas/PDF 使用重新排版的相同结果；后续绘制失败仍沿宿主已有保存和恢复路径处理。实现归 [`theme-font.mbt`](../../modules/formats/src/docx/theme-font.mbt)与 [`font-slots.mbt`](../../modules/formats/src/docx/font-slots.mbt)。

### 标题导航与正文统计

`Session.overview(revision)`、`FoundationSession/Client.overview(revision)` 和 `DocumentEditor.overview()` 查询已提交正文。标题采用样式继承和直接段落属性中的有效 `outlineLvl`；0–8 对应一级至九级，9 表示正文。新建文件提供 Heading1–Heading9。查询包含表格单元格内的标题，不按样式名称猜测层级。

段末原生 Enter 使用当前段落样式的有效 `w:next`，新建标题因此切回 Normal。中间拆段和粘贴换行保持原样式；缺失、同名或非段落目标也继续当前样式。新段落沿既有样式应用规则清除段落直接属性，并保留直接段落方向。选择删除、换段和样式切换合为一次历史；目标样式或预算失败保持原包。规则依据 [ONLYOFFICE 的段末新段落处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L19490)。

`DocumentEditor.selectHeading(result, index)` 定位到标题段落起点。结果绑定文档和修订；过期结果报 `stale-overview`，受保护标题带原因并禁止导航。默认属性面板展示标题和统计。

统计只计算支持的正文逻辑文字。字符按 Unicode 标量计数；空白分隔单词，文字区段相连，段落分别计词。制表符计为空白；显式换行和分页符不计字符。图片、自动编号标记及页眉页脚等其他区域不计入；受保护或排除的正文结构提供原因，不能据此声称全文统计完整。

查询最多扫描 1,048,576 个 UTF-16 单元，返回最多 4,096 个标题，每个标题显示最多 256 个 UTF-16 单元，截断会显式标记。17 个核心用例（含后续样式及列表回归）、一条 Chromium 导航/原生输入/组合取消/历史/重开/PDF 流程及 767 项安装包断言通过；严格宿主编译包含标题查询与导航调用。P10 仍为部分交付。

### 行内图片尺寸与裁剪

`editPicture(revision, { action: "insert", width, height, bytes })` 在核心当前文字选区插入正文行内 PNG/JPEG 图片；跨段范围复用既有删除与合段规则，单个普通表格单元格也可作为容器。`width/height` 为 0.1–14400 pt，舍入到整数 EMU；字节与像素预算同下方替换操作。空段、空 run 或段内位置都生成真正的绘图元素，保留周围文字、run 格式和范围外源。核心为新图片分配未用身份，避开主文档及页眉/页脚中的已有绘图；同时创建图片、关系和内容类型，合为一项有界历史。默认面板提供尺寸和文件选择，并读取新图片属性。选区替换与插入行为参考 [ONLYOFFICE controller_AddInlineImage](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Editor/Document.js#L19412-L19451)。

插入后把文字光标放到新图片之后，默认面板仍读取新图片属性，可以立即继续输入。受支持的正文及普通单元格段落中，图片与布局一致占一个 `U+FFFC`、一个 UTF-16 单元；`query().texts` 也包含该绘图片段。文字位置、范围、查找、格式与组合输入共用这个计数。纯文字中的 `U+FFFC` 仍是文字；核心用独立的保留位置区分原图片与输入字符，不把字符自动变成图片。图片两侧可输入、回车拆段及退格合段，保留图片原 XML、尺寸、裁剪及资源。范围替换和 Backspace/Delete 可以删除图片，并复用 `noDelete`、引用与修订保护；删除保留包内共享资源。行内绘图作为内容位置参考 [ONLYOFFICE Run 的绘图边界](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Editor/Run.js#L1448-L1467)。

纯文字复制只携带占位字符，不携带图片资源。`selectedText(revision, selection, cut = false)` 可用 `cut: true` 预检查剪切；核心对含实际图片的范围返回 `protected-content`，宿主在写剪贴板之前执行该检查。普通文字及字面 `U+FFFC` 仍可剪切。图片剪切与富资源粘贴继续归后续剪贴板批次。

撤销/重做精确恢复文字、图片、选区与资源。节点 ID 仅在当前会话有效，保存重开后须重新查询。未知图片源、扩展、效果或不支持的布局仍保护相应段落。含图片单元格的表格结构命令继续保护，避免绕过对象锁；浮动环绕继续归 [P10](../p10-docx-core.md)。

同步 Wasm 和 Worker 的 `pictures(revision)` 返回 `{ revision, images }`。每项包含会话内绘图节点 `id`、`name`、是否被当前单图片范围选中的 `selected`、point 单位的 `width/height`、四项 `crop`、尺寸/裁剪保护原因 `reason`、删除保护原因 `deleteReason` 和替换保护原因 `replaceReason`。`crop` 依次为源图左、上、右、下移除的比例。受尺寸/裁剪保护的项使用零尺寸及零裁剪，原因供 UI 显示；列表最多 256 项。宿主 `DocumentEditor.pictures()` 复用现有队列，默认图片面板从列表选择目标。

点击受支持的行内图片会选择其一个逻辑单元，复用现有文字选择、历史与输入路径，不增加 revision 或历史。相同图片资源仍按各绘图的段内 offset 区分。布局 `PlacedInlineImage.start/level` 保留逻辑起点和双向级别，`Hit.imageStart` 标记图片命中；左右半部返回相应文字边缘，RTL 调换逻辑方向。选择框按图片本身的框计算，并裁剪到行/单元格的可见区域，不按展开后的源裁剪尺寸命中。

`hitTest(layoutId, page, x, y)` 的 `DocxHit.picture` 为图片的 `DocxSelection` 或 null；`position` 仍是最近文字边缘。核心检查图片两端的逻辑位置和原有保护。默认宿主普通点击使用 picture 范围，拖选和 Shift 点击沿 position 扩展文字范围。命中只查询当前布局，旧布局及无效坐标仍拒绝。默认面板在手势结束后读取 selected 项，自动切换尺寸/裁剪/删除目标；过期、组合、暂停和替换沿现有屏障，晚到的面板读取不覆盖新文档。

原生 Backspace/Delete 和输入可删除或替换被选图片，撤销恢复原图片及选区；列表和命中不改变源包。屏幕阅读文本将占位字符描述为 [image]。普通单元格复用同一位置与裁剪，结构操作和图片剪切仍保留前述保护。行为参考 [ONLYOFFICE ParaDrawing.select](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Editor/Paragraph/ParaDrawing.js#L2784-L2795) 与 [GraphicObjects.OnMouseDown](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Editor/GraphicObjects/GraphicObjects.js#L1594-L1606) 的图片选择与文字输入分工。本项目通过已有逻辑范围连接两者；实现归 [picture-selection.mbt](../../modules/formats/src/docx/picture-selection.mbt) 和 [docx-hit.mbt](../../modules/bridge/src/docx-hit.mbt)。

`editPicture(revision, { action: "resize", id, width, height, crop })` 修改已有受支持的正文行内图片。宿主也显式传入图片列表的 revision，防止读取后改动文档而误用节点身份；默认面板过期后须重新读取。尺寸为 0.1–14400 pt，舍入到整数 EMU；裁剪输入为 0–1 的四个比例，按 1/100000 舍入，两侧之和须小于 1。保持目标框，只裁源图再拉伸至框；重置写四边零值。源图原字节、关系、替代文字、身份和范围外 XML 保持；同时更新行内框及图片变换尺寸。一次命令一项精确历史，保持原文字选择，重复有效值不新增 revision 或废弃布局。

`editPicture(revision, { action: "delete", id })` 只删除目标绘图元素，保留 run、段落和周围文字。目标段落可编辑时，光标落在图片原位置后的合法字素边界；若其他对象仍保护该段落，则保留原文字选择。删除保留包内图片和关系，避免误删共享资源；撤销/重做精确恢复源与选择。`noDelete`、外部对象引用及启用修订记录的文档保护删除；尺寸/裁剪锁不单独阻止删除。默认面板按 `deleteReason` 启用按钮。行为参考 [ONLYOFFICE 从 run 移除绘图](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L2899-L2963)。

`editPicture(revision, { action: "replace", id, bytes })` 替换目标图片的压缩源。`bytes` 为 `Uint8Array`，支持 PNG/JPEG，输入不超过 4 MiB，单轴不超过 4096 像素，总像素不超过 4194304；核心复用 PPTX 的文件头与尺寸校验，平台负责实际解码。目标框、裁剪、替代文字、身份和文字选择保持不变。核心创建独立资源、关系和内容类型，避免改变共享原图；这些修改合为一项历史，撤销移除新增资源，重做恢复相同字节。其他部件及原资源保留。相同字节不新增 revision；源保护、输出及 4 MiB 历史预算失败不留下部分资源。替换不受尺寸/裁剪锁单独限制，默认面板按 `replaceReason` 启用文件选择。固定框替换参考 [ONLYOFFICE replacePictureData](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/Drawings/Format/Image.js#L836-L859)；本操作保留已有裁剪。宿主在重新布局前准备新增图片；核心与 Canvas 回收当前流中不再使用的解码资源，撤销/重做时按需重新准备。

核心 `InlineImage.crop` 与 `PlacedInlineImage` 保留框和源裁剪；公共定位路径产生矩形裁剪及展开后的原图坐标，Canvas/PDF 使用同一结果。展开后的源图宽高各不超过 1e9 pt，沿用绘制坐标预算。资源仍按原键准备，不生成修改后的图片副本。缓存复制裁剪数组，调用者不能改写已保留的几何。未知裁剪/扩展、图片效果或锁定、修订容器、浮动/旋转/翻转图片、外部图片及未支持节设置继续保护。现有 noChangeAspect 约束禁止改变宽高比；noCrop/noResize 保护整项编辑。负裁剪扩边及浮动环绕仍按 [P10](../p10-docx-core.md) 实施。源比例对应 [ONLYOFFICE 图片裁剪系数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L946-L960)，实现归 [`picture-editing.mbt`](../../modules/formats/src/docx/picture-editing.mbt)。

### 行内图片拖动缩放

默认宿主在被准确选中的可编辑行内图片四角显示可聚焦手柄，复用核心选择框和原生指针队列。拖动始终保持原宽高比和裁剪，核心按初始尺寸与本次总位移生成候选，更新不累积上次预览。两轴都有位移时采用较大的比例；单轴位移用于键盘及沿轴缩放。四角编号 1–4 依次为左上、右上、右下、左下。尺寸继续限制为 0.1–14400 pt、整数 EMU 和原裁剪展开预算，越过相反角时钳制到最小尺寸，保持行内排版锚点。等比例追踪参考 [ONLYOFFICE ResizeTracks](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L670-L680)。自由比例侧边手柄、反转、移动锚点及浮动对象继续归 [P10](../p10-docx-core.md)。

同步 Wasm 和 Worker 的 `pictureResize(revision, change)` 返回 `EditState`。`change` 分为 `{ action: "begin", picture }`、`{ action: "update" | "commit", id, dx, dy, handle }` 和 `{ action: "cancel", id }`；`picture` 是列表中的绘图节点 ID，`id` 是开始后 `state.pictureResizeId` 的正整数手势身份。`dx/dy` 为 point 单位的有符号总位移，各不超过 ±14400；核心根据手柄方向换算尺寸，平台只换算 CSS 坐标。`DocxPictureResizeCommand` 从 Wasm/Web foundation 导出。对应核心方法为 `begin_picture_resize/update_picture_resize/finish_picture_resize/cancel_picture_resize`。

开始要求当前正好选中该图片，并通过原尺寸编辑保护。`EditState.pictureResizeId` 在普通状态为 null，与 `compositionId` 互斥。候选复用尺寸命令的校验和源补丁；`flow` 与布局展示候选，已提交源、revision 和历史保持。更新失败保留最后有效候选；错误身份、过期 revision、未知图片源及资源上限继续拒绝。候选期间其他编辑、文字组合及直接 DOCX/PDF 持久化返回 busy。提交按最终坐标重新准备源，只新增一项历史；返回原尺寸则不新增历史。取消恢复原显示和选择，不改变源与历史。图片字节、关系、替代文字、原裁剪及非目标部件保留。

松开提交，Escape、指针取消、捕获丢失及窗口失焦取消。手柄方向键沿对应方向移动 1 pt，Shift 为 10 pt，每次按键产生一项有界编辑。普通命令、保存和暂停先处理末次坐标；`whenIdle()` 只等已接收的候选更新。恢复与销毁会取消未提交候选，已提交历史继续保留。缩放使用当前 CSS 比例，DPR 留给原绘制层；缩放手柄不触发文字选择的边缘自动滚动。核心候选布局和正式布局共用 Canvas/PDF，平台不保存另一份文档树。实现归 [`picture-resize.mbt`](../../modules/formats/src/docx/picture-resize.mbt)、[`document-picture-resize.ts`](../../packages/web/src/document-picture-resize.ts)及 [`document-pointer.ts`](../../packages/web/src/document-pointer.ts)。

### 页面设置

`FoundationSession/Client.pageSetup(revision)` 与 `DocumentEditor.pageSetup()` 返回 `{ revision, page, reason, background }`。`background` 归下文页面背景色，独立返回 `{ color, reason }`。`page` 是主文档单节的源尺寸，字段为 `width/height/top/right/bottom/left`，单位为 pt；缺少节属性时使用 612×792 pt、四边 72 pt。不支持的多节、分栏、镜像页边距、装订线或保护返回 `page: null` 与原因，不返回伪造的可编辑参数。查询不要求正文选区。

`setPageSetup(revision, page)` 同时修改尺寸与四边距，Web 编辑宿主省略 revision。`DocxPageSetup` 要求上述六个值，可选 `orientation: "portrait" | "landscape"`。省略方向时使用指定宽高；给出方向且与宽高不一致时，核心交换宽高并旋转四边距。横向时新左/上/右/下依次为原下/左/上/右，纵向反向旋转；正方形不旋转。规则依据 [ONLYOFFICE 的方向修改](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/sections/sect-pr.js#L1148-L1180)。

尺寸为 36–14400 pt，边距非负；所有数值须能表示为整数 twip，并为正文留下至少 12×12 pt。源尺寸原样写回 `pgSz/pgMar`；`Flow.page`、预览和 PDF 继续采用下文既有纸型解释规则，可能与源尺寸不同，例如 500 pt 的显示尺寸为 498.9 pt。再次应用相同源参数不产生历史，不能把显示尺寸自动写回源文档。

缺少节属性时在正文末尾创建，缺少页面属性时按 OOXML 顺序插入。修改保留段落、稳定节点身份、节元数据、其他部件、页眉/页脚距离和零装订线；清除与新尺寸不一致的旧打印机纸型代码。尺寸与边距合为一项有界历史，保留待输入格式，撤销/重做及保存重开恢复相同源参数。非法值、过期 revision、未知目标属性/注释、多节或预算失败保留已提交包。默认 UI 提供相同的读取、修改和方向选项；文档改变后要求重新读取，防止旧参数覆盖新状态。多节、实际分栏及页眉页脚编辑仍属于后续页面批次。

### 页面背景色

`FoundationSession/Client.setPageBackground(revision, color)` 与 `DocumentEditor.setPageBackground(color)` 设置全稿纯色背景；`color` 为不带 `#` 的六位 RGB，`null` 移除背景并恢复默认白页。`pageSetup().background` 返回当前显式颜色或 null，以及修改保护原因。源 `w:background w:color` 位于正文前，修改保留正文、选择、待输入格式和其他部件，使用一项有界历史；相同颜色不增加历史。默认页面面板共用读取/过期草稿保护，并提供颜色和恢复默认按钮。

核心 `Flow` 与 `DocxFlow` 的必需 `background` 字段为有效六位 RGB；无背景为 `ffffff`。正文、透明单元格和列表标记按有效页面背景计算自动文字对比，有底色的单元格仍按自身底色计算，显式文字色保持原样。分页结束后在页面图元最前加入整页颜色，保留分页缓存中的原内容；换色、恢复白色及缓存复用不积累旧底色。Canvas 与静态 PDF 消费同一背景矩形，包含页边距区域。规则参考 [ONLYOFFICE DocumentBackground.draw](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/document/document-background.js#L54-L87)和 [setBackgroundColor 的历史](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L5638-L5645)；实现归 [`page-background.mbt`](../../modules/formats/src/docx/page-background.mbt)。

非法颜色、旧 revision、活动候选、文档/设计保护及输出预算失败保持当前包与历史。重复背景、未知属性、主题色、图片/渐变/VML 及不透明目标源继续保护，布局保留诊断，不能用纯色替换来删除未知源。全稿主题背景和水印继续实施，页边框见下节。

### 页面边框

`FoundationSession/Client.setPageBorders(revision, borders)` 与 `DocumentEditor.setPageBorders(borders)` 修改当前单节文档的页面边框。`borders` 使用导出的 `DocxPageBorders`：`{ offsetFrom, display, zOrder, sides }`。`offsetFrom` 为 `page/text`，分别从纸张边缘或正文边距外侧计算；`display` 为 `allPages/firstPage/notFirstPage`；`zOrder` 为 `front/back`。`sides` 最多四个互异的 `DocxPageBorder { side, color, width, space }`，`side` 为 `top/left/bottom/right`，`color` 为六位 RGB，`width` 为 0.25–12 pt 且须为 1/8 pt 的倍数，`space` 为 0–31 的整数 pt。空 sides 保留设置但不绘制边框；null 移除 `pgBorders`。`pageSetup().borders` 返回当前值和保护原因。

默认页面面板提供四边独立启用、颜色、宽度和距离，以及基准、显示页面和前后层次。读取后按 revision 保护过期草稿，原生输入先沿既有队列提交。核心按 OOXML 顺序写 `sectPr/pgBorders`，缺少节属性时与边框一起创建；保留正文、选区、待输入格式和其他部件。重复设置不新增历史，移除、背景修改与边框共用精确混合历史和保存重开。页面尺寸变化及边框修改先验证边框不交叉，失败不提交。

核心 `Flow.pageBorders` 为必需结构，无边框时使用空 sides。边框不改变正文分页；缓存复用后派生当前边框，不把装饰写进缓存原页。背面边框位于页面背景之后、正文与表格之前，正面边框通过 `PageFrame.pageBorders` 在正文之后绘制。四边先竖后横，横边覆盖交角；纸张基准的距离量到外缘，正文基准向外留空。Canvas 与 PDF 使用相同填充矩形。几何和顺序依据 [ONLYOFFICE DrawPageBorders](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L5519-L5635)，未复制上游源码；实现归 [`page-borders.mbt`](../../modules/formats/src/docx/page-borders.mbt)、[公共边框布局](../../modules/layout/src/page-borders.mbt)及 [`docx-page-borders.tsx`](../../packages/ui/src/docx-page-borders.tsx)。

导入支持实线、显式 none/nil、RGB 及按黑色解释的 auto，保留未改源。未知线型、主题色、艺术边框、阴影/框效果、重复节点、未知属性/子节点及目标注释保持保护和布局诊断。多节、镜像/装订线、文档保护及预算沿页面设置保护；其余边框样式继续实施。

### 页码格式与起点

`DocumentEditor.setPageNumbering(value)` 与 `FoundationSession/Client.setPageNumbering(revision, value, profile)` 修改单节页码。`value` 为 `DocxPageNumbering { start: number; format }`，start 是 0–4294967295 的整数；format 接受 `decimal`、`decimalZero`、`lowerLetter`、`upperLetter`、`lowerRoman`、`upperRoman`。传 null 移除 `w:pgNumType`，恢复从 1 开始的十进制编号。`pageSetup().numbering` 返回 `{ value, reason }`；不支持的节属性返回 null 与原因。默认页面面板提供起点、格式、应用和重置。

核心以 `layout.PageNumbering` 保存 UInt32 范围的 Int64 起点，公开 JSON 传精确数值；必需的 `Flow.pageNumbering` 参与页边文字派生。PAGE 为起点加物理页序，NUMPAGES 为实际总页数。字段显式格式优先于节格式，未指定格式的 NUMPAGES 使用十进制。字母/罗马数字复用既有 [Office 编号格式](../../modules/layout/src/number-label.mbt)，包括零值和循环规则；页码加法使用 Int64，不在 UInt32 起点附近溢出。首个物理页的首页变体优先，其余页面按编号结果的奇偶选择 even/default；缓存中的对应空间随之更新。

操作沿现有单节属性检查和源事务，按 OOXML 顺序插入或替换 `pgNumType`。修改前预检字体及分页，失败保留原源、选择、待输入格式和历史。相同有效设置不新增历史；重置移除原属性。修改编号本身保留正文、页边 XML、字段代码和缓存，显式区域应用才写回当前字段结果。没有节属性时沿原有路径创建。多节、章节前缀、未知格式、重复节点及带注释/处理指令的编号属性继续保护。

语义依据 [ONLYOFFICE 节起点与编号奇偶](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L14679-L14732)、[PAGE 的节格式/显式格式优先级](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L4828-L4845)及[字段格式映射](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFields/instruction-base.js#L133-L179)。实现归 [`page-numbering.mbt`](../../modules/formats/src/docx/page-numbering.mbt)和[公共页码模型](../../modules/layout/src/page-numbering.mbt)。更广页码格式与多节仍继续实施。

### 页眉页脚

`FoundationSession/Client.runningArea(revision, kind, variant)` 返回 `DocxRunningArea { revision, content, distance, reason, differentFirst, differentEven, shared }`。`kind` 使用 `DocxRunningKind` 的 `header/footer`；`variant` 使用 `DocxRunningVariant` 的 `default/first/even`。`DocumentEditor.runningArea(kind, variant)` 沿原生输入屏障查询。`content` 是 `DocxRunningContent[]`，每项为 `{ text: string }` 或 `{ field: "PAGE" | "NUMPAGES"; format?: "decimal" | "lowerLetter" | "upperLetter" | "lowerRoman" | "upperRoman" }`，从 Wasm/Web foundation 模块导出。当前支持单节，文字以 LF 分段，以 U+2028 表示软换行，保留 Tab；`distance` 为距纸张上边或下边的 pt，同类区域的三种变体共用该距离。不支持的源返回保护原因。

`FoundationSession/Client.setRunningArea(revision, kind, variant, content, distance, profile)` 与 `DocumentEditor.setRunningArea(kind, variant, content, distance)` 替换指定区域的文字和页码字段。核心使用 `RunningContent.Text(String)/Field(String)`，显式格式使用 `FormattedField(String, String)`。例如 `[{ text: "Page " }, { field: "PAGE" }, { text: " of " }, { field: "NUMPAGES" }]`。旧的字符串参数和查询 `text` 字段已移除。前者显式提供字体映射，编辑器复用当前映射。列表最多 256 项；文字与字段合计最多 8192 单位，文字按 UTF-16、每个字段按一单位计算。相邻文字会合并，空列表用于清空；段内最多 64 个字段。距离为 0–14400 pt 的整数 twip，并须给正文留出可用区域。缺失的 `hdr/ftr` 部件、关系、内容类型、节引用及距离在同一事务创建，候选排版和输出预算通过后提交。清空保留一个空段落和已创建部件，不清理未知资源。

`FoundationSession/Client.setRunningOptions(revision, first, even, profile)` 与 `DocumentEditor.setRunningOptions(first, even)` 修改首页和奇偶页开关。核心写回单节 `titlePg` 与文档 `evenAndOddHeaders`，按需创建节或设置部件；关闭保留所有区域和引用，重新开启恢复同一内容。开关不隐式创建文字部件。首页启用时优先选择 first；其余按节起点计算的偶数页在奇偶开关启用时选择 even；其他页选择 default。缺失的活动变体显示空白，不回退到 default。选择依据 [ONLYOFFICE 页边区域解析](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Layout/Base.js#L85-L116)，未复制上游源码。

`FoundationSession/Client.unlinkRunningArea(revision, kind, variant, profile)` 与 `DocumentEditor.unlinkRunningArea(kind, variant)` 为指定共享区域创建独立部件。`shared` 按实际引用解析后的部件判断，包含非活动变体和不同关系 ID 的别名；没有共享或没有部件时不增加历史。默认面板先读取区域，再提供独立操作。

核心完整复制区域 XML 及其关系，保留注释、属性和关系 ID；内部目标改为包内绝对路径，外链保持原地址且不请求网络。图片等资源继续复用，旧部件保留。新部件、关系、内容类型及选定引用合为一次有界事务，候选失败保留原文档，支持精确撤销/重做与重开。未知或带注释的源可独立保留，纯文字编辑限制继续适用。复制思路参考 [ONLYOFFICE 断开页边继承](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L11643-L11715)，当前操作只处理单节显式共享引用，节间继承仍待实现。实现归[独立部件事务](../../modules/formats/src/docx/running-unlink.mbt)。

修改保留正文、选区、待输入格式和其他部件。距离单独变化时完整保留区域源；文字替换保留未改段落的原始 XML，修改的段落保留段落属性与首个 run 的字符属性，字段按该段原有字段顺序沿用结果字符属性，并写为标准简单域；新增段落沿用最后一段。重复设置不新增历史；开关、部件创建、文字和距离修改共用精确撤销重做及保存重开。默认页面面板提供区域、所属页面、读取、文字/字段、距离和两个开关，可在文字光标处插入当前页码或总页数，并更换字段种类、显式格式或移除，过期草稿须重新读取；应用开关保留尚未提交的文字草稿。

核心 `Flow.headers/footers` 按 `default/first/even` 保存活动区域的段落，配合 `headerDistance/footerDistance/differentFirst/differentEven` 派生各页正文上下空间。`Layout.running` 按页保存页边行，独立于正文光标行。页眉从上边距离开始，页脚在下边距离以上结束；实际行框、段距与正文边距共同确定避让。文字复用既有塑形、定位图元、Canvas/PDF 和语义文本；命中返回 `protected-content:running-area`，不产生正文编辑位置。活动区域的重复行计入原有总行数预算。几何依据 [ONLYOFFICE HeaderFooter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/HeaderFooter.js#L1735-L1804)。实现归 [`running-read.mbt`](../../modules/formats/src/docx/running-read.mbt)、[`running-edit.mbt`](../../modules/formats/src/docx/running-edit.mbt)、[开关事务](../../modules/formats/src/docx/running-options.mbt)、[页边布局](../../modules/layout/src/running.mbt)及 [`docx-running.tsx`](../../packages/ui/src/docx-running.tsx)。

分页缓存包含三种活动页的正文空间。后缀复用同时检查当前空间和页序奇偶，首段变动不能把另一类页面的旧位置复用到当前页。普通表格行、纵向合并续页、保留段落链和孤行控制按当前页空间放置；纵向合并组的重复表头仍沿既有整组预留规则，按该组经过页面的最小可用高度判断，逐片段取舍继续完善。

已导入的页眉页脚支持 `PAGE` 和 `NUMPAGES` 的格式化计算，包括 `fldSimple` 和同段内的 begin/instrText/separate/result/end 成对域。接受缺省格式、`\* Arabic` 或 `\* MERGEFORMAT`；保留首个结果 run 的有效字符样式。派生 `Span.field` 使用空串、`PAGE` 或 `NUMPAGES`，`Span.text` 保留导入缓存，实际页边行按当前页号和总页数重新塑形。正文分页、历史和重开会重新计算，Canvas、语义文本和 PDF 使用相同结果。参考 [ONLYOFFICE PAGE 与 NUMPAGES](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L918-L928)。

字段结果改变换行时，核心按每页实际页边高度有界重排正文，最多八轮；不收敛时保留最后完整布局并给出诊断，输出沿既有诊断保护。正文空间和分页缓存包含逐页几何，跨页表格也使用该页空间。现有 1024 页和 32768 行预算继续生效，每段最多 64 个字段。未知指令/开关、锁定、嵌套、不完整或跨段域继续保护且不执行；当前不支持多节继承、更广编号格式和正文域。实现归[字段读取](../../modules/formats/src/docx/running-fields.mbt)与[有界重排](../../modules/layout/src/running-pagination.mbt)。

计算、保存和输出不改写域代码或缓存，不增加历史，也不改变原格式未保存状态。显式应用字段内容会把当前结果与内容修改放在同一项历史；内容和距离相同时，应用用于刷新已有缓存，结果相同则不新增历史。只改距离或开关仍保留区域 XML。刷新简单域和成对域时只替换结果文字，保留域代码、属性和字符样式；未知或带注释的源继续保护。缓存的 `PAGE` 使用该变体的首次出现页，加上节起点并应用节格式或字段显式格式。首页取物理首页；偶数变体取编号后首次为偶数且未被首页占用的页面；默认变体取未被活动首页/偶数区域占用的首个页面。起点为 1 时仍分别遵循原有的 1、2 及默认区域 1/2/3 规则。非活动变体采用同一规则；`NUMPAGES` 使用当前文档总页数。屏幕/PDF 仍逐页计算。更新要求完整布局及原有历史/输出预算通过，失败保留原文档、选择和历史。行为参考 [ONLYOFFICE 字段创建与更新](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L23510-L23568)，当前写回归[有序内容及字段缓存](../../modules/formats/src/docx/running-content.mbt)。

节间继承、其他字段、更广页码格式、图片/表格/审阅对象及页边原生光标仍待实现。共享同一部件的变体可显示，内容替换或缓存更新须先显式断开，避免改写其他区域；未知或带注释的目标源也不允许内容替换或缓存更新。非活动区域保持原源，启用前验证候选布局。正文查找和统计仍只覆盖既定正文范围。

### 表格创建

`FoundationSession/Client.insertTable(revision, selection, rows, columns)` 与 `DocumentEditor.insertTable(rows, columns)` 在正文范围插入固定网格，默认 UI 提供行列输入。rows 为 1–1000，columns 为 1–63，总格数最多 4096，并受 XML、历史和输出预算限制。列宽按当前单节布局的可用页宽分配整数 twip，余量逐列分配，每列至少 12 pt。沿用当前纸型解释，不改源页面设置。未知或受保护的正文、嵌套表格、多节及无法解释的页面设置拒绝操作。

核心先删除所选文字；在段中插入时拆分段落，在段首插入时保留原段落作为后续内容。新增表格使用 0.5 pt 黑色完整网格、5.4 pt 水平单元格边距与固定列宽。单元格复制插入起点的有效字符格式及支持的段落属性，并将缩进与段前分页显式归零。若段首已有段前分页，则转移到首格首段，保留表格在该页开始的位置；页首不生成额外空页。其他单元格的段前分页仍受原有布局保护。

范围删除、段落拆分与新增节点共同提交一项历史，选区进入首格。核心失败保留已提交源与历史。保存及混合文字编辑的撤销/重做精确恢复源节点、选择和其他部件。新增格可继续输入、设置已有字符/段落格式及用 Tab 导航。固定及自动适配布局均沿同一表格模型排版。

`FoundationSession/Client.editTable(revision, selection, change, profile?)` 与 `DocumentEditor.editTable(change)` 接收带 `action` 的对象。行列操作为 `{ action: "rowBefore" | "rowAfter" | "deleteRow" | "columnBefore" | "columnAfter" | "deleteColumn" }`。范围须位于一个支持的单元格内，默认 UI 提供同样的六个命令。新增行复制当前行的行/格属性及各格首段格式；新增列复制邻格属性和首段格式，不复制文字，保留格式继承。固定宽表格保持总宽，按原列宽比例缩放为整数 twip；未指定固定宽的网格按插入/删除后的列宽计算。列编辑结果须在可用页宽内，各实际单元格至少 12 pt；重建出的细分网格可更窄。全部命令遵守创建时的行列、格数及资源上限；生成源片段时累计预算，超限即停止。

行操作作用于当前格所在的实际源行。插入位置穿过纵向合并时，新行延续该合并；在合并范围外插入时，新格保持横向跨度并独立。删除起始行会删除该行内容，后续延续格成为新起始格，不转移已删文字；删除延续行保留起始格内容。保留原网格、行属性、宽度偏好及固定/自动适配模式。新增行进入首个非延续格；整行均为延续格时进入覆盖它的起始格。候选源沿现有字体上下文检查可写性、有效宽度和分页，失败保留已提交状态。合并列删除遵循下述整格相交规则。行为依据 [ONLYOFFICE 行插入与删除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9997-L10293)，实现归 [`table-row-edit.mbt`](../../modules/formats/src/docx/table-row-edit.mbt)及[`共享结构事务`](../../modules/formats/src/docx/table-grid-structure.mbt)。

左右插列使用所选整格的有效宽度。每行在指定边界相邻的完整单元格前后插入，不切开已有格；各行插入位置可以不同。核心按插入后的实际格边界重建公共网格和 gridSpan，固定宽表格按比例保持总宽。原文字、段落身份和纵向合并归属保留；新格复制右邻格的格/首段格式，行末复制左邻格。新格可延续同一来源的纵向合并，保持空白；dxa/pct 格偏好按有效宽度写为 dxa，auto/nil 保留，整表适配模式不变。未知源、缺字体、格宽不足、分页或预算失败均不提交。依据 [ONLYOFFICE AddTableColumn 与网格重建](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L10516-L10788)及[公共边界计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L15005-L15155)，实现归 [`table-column-insert.mbt`](../../modules/formats/src/docx/table-column-insert.mbt)。

列删除以当前整格的左右网格边界为范围，删除各行中与范围相交的完整单元格及全部内容。横向合并格不会只缩短跨度。核心按存活格的宽度重建公共网格；固定宽表格保持总宽，auto/nil 偏好保留。空行及修正后全部为纵向延续的行移除；其他纵向延续只能接到同一原始归属和相同边界，不能与无关格合并。删除最后所有格时移除表格并进入正文。依据 [ONLYOFFICE 列选择](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L19140-L19171)与[RemoveTableCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L14338-L14520)，实现归 [`table-column-delete.mbt`](../../modules/formats/src/docx/table-column-delete.mbt)。

删除后各行可有不同的实际宽度，源 `trPr/gridAfter` 记录行尾空缺。解析、行列维护及拆格同步这些边界；空缺不产生单元格、填充或外框。`gridAfter` 须为 0–63 的整数，实际跨度加空缺必须等于公共网格列数。有效细分网格可小于 6 pt，实际单元格仍须留下文字宽度。当前支持从第 0 列开始的行，非零行首空缺及其余行宽属性仍待实现。未知源和保护内容在删除前检查；候选字体/分页、源、历史及输出预算失败保留已提交状态。

新增列将光标移到新列首行。删除操作将光标移到相邻的剩余行或列；删除最后一行或列时移除表格，进入后续正文段落，必要时创建空段落。首格段前分页随结构转移。末格 Tab 在最后一个实际源行之后新增一行并进入首格，即使最后一格的合并起始点位于前行，Shift+Tab 在首格保持原位。每次结构操作与新增身份、列宽及选择合为一次历史，保留未删文字与其他部件，支持保存重开和精确混合撤销/重做。未知结构、锚点、受保护内容或预算失败原子拒绝。行为依据 [ONLYOFFICE 行列操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9997-L10788)和[固定宽网格缩放](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L414-L425)。

`{ action: "merge", rows, columns }` 从当前格的左上网格位置合并指定矩形。范围为 1–1000 行、1–63 列且最多 4096 个网格位置，不能切开已有合并格。内容按行优先顺序进入左上格，保留段落、字符格式和空段落；列网格不变，更新格宽、gridSpan 与 vMerge。`{ action: "unmerge" }` 取消当前格的合并，恢复原网格各列和行，全部内容留在首格，新增格保留相应格式并置空。两者使用同一有界源历史，可与格内输入精确混合撤销，保存后继续编辑。相同合并范围或取消未合并格不新增历史。书签等受保护锚点、未知格属性及输出预算失败原子拒绝。内容顺序参考 [ONLYOFFICE 合并](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9466-L9530)。

`{ action: "splitCell", rows, columns }` 将当前单格拆成指定行列，默认 UI 提供同名操作和数量输入。普通格可新增 1–1000 行、1–63 列；纵向合并格的行数须不超过原合并行数，且能整除原行数。`1×1` 不改变源或历史。它与 `unmerge` 不同：列边界按当前有效宽度等分到整数 twip，合并原有边界后细分公共网格；其他行仅更新跨度，保持原单元格范围。

普通格新增行时复制原行属性，邻格通过纵向合并保持原内容和范围。原段落内容全部留在左上格；新格为空并复制相应格/首段格式。保留原段落身份、非目标内容和其他部件，光标进入左上格。dxa/pct 宽度偏好按列数分配并保持总量，auto/nil 保留；邻格的宽度偏好和整表固定/自动适配模式不变。

结果仍须满足最多 1000 行、63 个公共网格列和 4096 个网格位置，新增源、历史及输出受既有预算约束。核心使用字体 profile 先检查候选格内宽度与分页，边距不足、未知格/行属性、保留的属性注释、缺字体或预算失败时原子拒绝。操作与选择合为一次精确历史，可与文字输入混合撤销、保存重开并沿同一布局输出 PDF。当前合并行组仍须能完整放入一页。算法依据 [ONLYOFFICE SplitTableCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9609-L10001)，实现归 [`table-cell-split.mbt`](../../modules/formats/src/docx/table-cell-split.mbt)。

`{ action: "splitTable" }` 在所选单元格所在行之前拆分正文表格，两表之间插入空正文段落，光标进入下表首格。首行、缺少段落的单元格、嵌套/受保护表格、未知结构及预算失败拒绝操作。两表保留列网格、宽度、边框、样式和单元格内容；原有行和未替换内容的身份保持。纵向合并跨越分界线时，内容留在上表，下表从对应位置创建空的合并起始格，复制原合并格格式并清除段前分页；后续延续格继续归属下表。分界、空格及选择一次提交历史，支持原样撤销、保存重开、继续输入及同布局 PDF。默认 UI 使用同一操作。拆表与跨度清理参考 [LibreOffice SplitTable](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/source/core/docnode/ndtbl.cxx#L3392-L3515)及[纵向跨度清理](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/source/core/table/swnewtable.cxx#L2021-L2110)。

布局读取横向跨度及纵向起始/延续格，文字、背景和边框使用合并后的矩形；Tab 跳过纵向延续格。纵向合并格可跨源行与页面继续，保持起始格的内容归属、底色、边框与逻辑位置。普通行已支持[逐格跨页](#表格行跨页)，重复表头见[当前合同](#重复表头)。包含可见内容的纵向延续格明确拒绝，避免隐藏其文字。含合并格的行增删遵循上述规则；列删除按所选整格的横向范围移除相交格。默认 UI 提供从当前格指定行列数量的合并与取消合并；鼠标矩形选择及其余属性编辑仍归 [P10](../p10-docx-core.md)。

### 表格尺寸

`editTable({ action: "tableWidth", value })` 设置当前格所在表的总宽度，单位为 pt。核心按原列宽比例分配整数 twip，精确保持目标总宽，同步 `tblW`、列网格和全部格的 `tcW`；横向合并按跨度求宽，纵向合并起始/延续关系和文字保持。最多 63 个逻辑列，各列至少 12 pt，格内边距须留出文字宽度，总宽不超过当前页的可用宽度。未修改的样式、边框、对齐、段落和其他部件保留。比例规则参考 [ONLYOFFICE 网格缩放](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L413-L429)。

`editTable({ action: "columnWidth", column, value })` 设置同表内指定逻辑列的宽度，column 从 0 开始，须小于当前列数。value 为 12–14400 pt 的整数 twip，整表仍须位于可用页宽内。其他列宽度保持，表格总宽随目标列增减；横向合并的格宽按所跨列求和，纵向延续节点一起更新。共享整表宽度的网格/属性序列化、保护、边距及半描边宽度预检、源历史和保存。规则参考 [ONLYOFFICE 列宽设置与网格重建](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L19008-L19039)；本 API 用逻辑列索引明确定位合并格覆盖的各列。默认 UI 显示从 1 开始的列号及对应宽度。

`editTable({ action: "rowHeight", value, rule })` 设置当前格所在行的高度。`rule` 必须为 `atLeast` 或 `exact`，写入相应的 `trHeight hRule`。`atLeast` 允许内容撑高，值为 0 时删除行高属性并恢复自动；`exact` 固定行高并裁剪溢出，完整文字及逻辑位置仍保留。精确值另加同行最大上下边距，包含上边框，最小可见行距为一个 twip。纵向合并以末行模式决定是否允许内容撑高；末行为精确高度时裁剪到整个合并格。预览和 PDF 使用同一裁剪，光标及选区限制在格内，垂直移动跳过完全隐藏的行。重复表头保留相同裁剪。规则参考 [ONLYOFFICE 精确行高与边距](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L2660-L2700)、[内容裁剪](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L2775-L2900)及[合并格末行](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L3150-L3162)。尺寸须有限、非负、不超过 14400 pt，且为整数 twip；表宽须大于 0。核心保留合并行组的一页边界，拒绝超出可用页高的尺寸。

`queryFormatting(...).table` 在支持的表格上下文中返回 `{ id, autoFit, row, rows, column, columns, columnWidths, headerRows, width, rowHeight, rowHeightRule, align, tableMargins, tableBorders, cellFill, cellVerticalAlign, cellMargins, cellBorders, maxWidth, maxRowHeight }`，否则为 null。`id` 为当前表节点身份，`row` 从 0 开始，`columns` 为逻辑列数；`column` 为当前格左侧的逻辑列索引，`columnWidths` 为全部逻辑列宽（pt）；`width` 是列网格总宽，`rowHeight` 是源高度值，`rowHeightRule` 为 `atLeast` 或 `exact`；自动高度返回 `0/atLeast`。这些值均非浏览器测量。`DocxFlow.tables[].exactHeights` 按行携带精确模式。`align` 为整表的 `left`、`center` 或 `right`；`tableMargins` 是表格默认单元格边距，尚未叠加单格覆盖。`cellFill` 为当前格的六位 RGB 底色，无底色时为 null；`cellVerticalAlign` 为有效的 `top`、`center` 或 `bottom`；`cellMargins` 为该格有效的 `{ top, right, bottom, left }`。两类边距均以 pt 表示。默认 UI 读取同一查询，提交后反映实际属性；文档、所选段落或 revision 变化会重置未提交的属性输入。

尺寸操作保留逻辑选区和当前光标处的待输入格式，重排后清除旧布局定位提示，沿已有队列、源历史、保存重开和 PDF。无源变化不增加历史；未知行/格映射、网格标记、属性或预算失败原子拒绝。缺少的尺寸属性按 OOXML 顺序创建；恢复自动高度保留其他行属性，并重新显示被裁剪文字。其余格属性仍归 [P10](../p10-docx-core.md)。

### 表格边框

`editTable({ action: "tableBorders" | "cellBorders", value })` 修改整表默认边框或当前逻辑格的直接边框。`value` 为非空部分属性集：四边使用 `top/right/bottom/left`，整表另支持 `insideH/insideV`。每边 `{ width, color }` 设置实线，`width: 0` 显式关闭，null 删除该边直接属性并恢复继承；省略的边保持。非零线宽为 0.25–12 pt，须为 1/8 pt 的整数倍；color 为六位 RGB。默认 UI 提供表格/当前格、各边/全部、线宽、颜色、移除及恢复继承。纵向合并起始与延续节点共同修改，内部合并边不绘制。

核心沿表格样式链与直接属性求有效值。单元格声明优先于表格默认；相邻单元格先取非空边，再取较宽实线，同宽按 RGB 亮度规则求值。规则依据 [ONLYOFFICE 边框冲突](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L15267-L15342)。当前读取 `single/nil/none`、RGB/auto 和左右的 start/end 别名；auto 为黑色。主题边框、虚线、双线、阴影、非零间隔和未知属性继续保护，不覆盖不理解的源内容。

`queryFormatting(...).table.tableBorders` 返回六边的默认值，`cellBorders` 返回当前格四边的实际冲突结果；合并格某边包含不同线段时该边为 null，表示混合。`DocxFlow.tables[].borders` 为核心生成的 horizontal/vertical 网格，替代旧布尔值。边宽参与行高与分页预留，左右边界至少预留半个描边宽度。分页缓存、重复表头、Canvas 和 PDF 消费相同线段及颜色，Web 不重算边框。

属性沿现有单项源历史保存，保留文字、网格、选区、待输入格式和其他部件。无变化保留源片段及 revision；无文字宽度、未知目标、旧 revision、输出或历史预算失败原子拒绝。合并仍沿当前[结构规则](#表格创建)保留每行首格属性，取消合并复制相应格属性；复杂边框和跨格选择仍归 P10/P14。实现归 [`table-borders.mbt`](../../modules/formats/src/docx/table-borders.mbt)、[`table-border-editing.mbt`](../../modules/formats/src/docx/table-border-editing.mbt)及[公共边框绘制](../../modules/layout/src/table-borders.mbt)。

### 表格底色

`editTable({ action: "cellFill", value })` 修改当前单元格的纯色底色。`value` 为不带 `#` 的六位十六进制 RGB，核心统一小写并写入 `shd val="clear" color="auto" fill="…"`；null 删除该格的直接底色。纵向合并格的起始与延续节点一起修改，横向跨度、文字身份、其他属性与部件保留。自动文字与列表编号根据新背景重新求色，清除后按白色背景求色。操作沿现有队列、源历史、待输入格式、保存重开及同布局 PDF；无源变化不增加历史，未知主题/扩展属性、源注释及预算失败原子拒绝。

默认 UI 提供颜色输入、应用和清除。当前仅修改光标所在的逻辑格，矩形多格选择、主题/图案底色及其余属性仍归 [P10](../p10-docx-core.md)。单格底色行为参考 [ONLYOFFICE CellsBackground](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L1989-L2100)。

### 单元格垂直对齐

`editTable({ action: "cellVerticalAlign", value })` 为当前逻辑格设置 `top`、`center` 或 `bottom`，写入直接 `vAlign`；null 删除直接属性，恢复表格样式继承，无继承值时为顶部。基础表格样式沿 `basedOn` 链求值，条件表格样式仍受既有保护。纵向合并起始与延续节点一起修改；底色、网格、文字身份和其他部件保留。修改复用底色的单格事务，保留逻辑选区、待输入格式和精确历史。无源变化不增加历史，未知属性/标记与预算失败原子拒绝。

核心先排完格内内容并计算整组合并行高，再按剩余高度平移全部文字和内联对象：居中取一半，底部取全部。边距、边框、段落间距及多行内容参与内容高度；内容撑满时不产生负位移。跨页普通格仅在首个含文字的片段应用垂直对齐，后续文字从顶部继续。命中先确定所属单元格，再选其文字位置，格内空白也不会落入邻格。位移与单元格区域参与缓存，光标、选区、预览和 PDF 共用同一几何。默认 UI 提供三种对齐按钮。跨页合并延续和更广表格属性仍归 [P10](../p10-docx-core.md)。行为依据 [ONLYOFFICE 垂直对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L3426-L3495)。

### 单元格边距

`editTable({ action: "cellMargins", value })` 为当前逻辑格设置四边独立边距。`value` 使用 `DocxCellMargins` 的 `{ top, right, bottom, left }`，四项均为有限、非负、不超过 14400 pt 的整数 twip 值；null 删除直接 `tcMar`，恢复逐边继承。纵向合并起始与延续格同步修改，属性按 OOXML 顺序插入；底色、垂直对齐、网格、文字身份和其他部件保留。继承先求基础表格样式与当前表的 `tblCellMar`，再叠加样式及当前格的 `tcMar`。未提供的边继续继承，最终默认左右各 5.4 pt、上下为 0。当前从左到右表格中，`start/end` 优先于同层 `left/right`，`nil` 为零；相对宽度、条件表格样式和未知扩展继续保护。

核心 `Table` 与 `DocxFlow.tables` 使用必需的逐格 `margins` 数组。排版从格宽扣除左右边距，采用本行最大的顶部边距与当前格的底部边距计算内容高度，再执行垂直对齐。该规则参考 [ONLYOFFICE 边距继承及同行顶部边距](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableCell.js#L1389-L1425) 和[同行顶部边距求值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableCell.js#L2765-L2784)。改变边距会更新塑形宽度、行组页缓存、光标/选区、预览和 PDF。修改不能挤掉文字宽度，显式行高与边距的合并行组下限须小于一页可用高度；实际文字仍受既有分页约束。插列、缩表及其他事务也核对有效格内宽度，失败时保留原包和历史。

默认 UI 提供四边输入、应用和恢复继承。操作沿已有单格事务保留待输入格式、精确撤销/重做及保存重开；未知源属性、注释和预算失败原子拒绝。矩形多格编辑及其余表格属性仍归 [P10](../p10-docx-core.md)。

### 整表对齐与默认边距

`editTable({ action: "tableAlign", value })` 为当前格所在的正文表格设置 `left`、`center` 或 `right`，写入表格 `jc`。核心按页面可用宽度定位整表，格内段落对齐保持。默认 UI 提供三个整表对齐按钮。行为参考 [ONLYOFFICE TableAlignment](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L1368-L1378)。

`editTable({ action: "tableMargins", value })` 设置表格默认单元格边距，使用相同的 `DocxCellMargins` 四边值和[边距边界](#单元格边距)，写入 `tblCellMar`；null 删除当前表的直接默认值，恢复表格样式和基础默认值。现有单格及单元格样式的覆盖保留，只有继承这些边的格随之改变。默认 UI 分别显示整表默认值和当前格有效值，两组输入复用同一四边表单。行为参考 [ONLYOFFICE TableDefaultMargins](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L1053-L1097)。

两项操作使用表格属性事务，保留文字身份、选区、待输入格式、其他属性与部件；必要的表格属性容器按 OOXML 顺序创建。无源变化不增加历史，未知目标属性/标记、无文字宽度、边距超过页高或预算失败原子拒绝。预览、空白区域命中、光标/选区与 PDF 使用同一位置；保存重开和精确撤销/重做沿已有路径。浮动表格及其他表格属性仍按 [P10](../p10-docx-core.md)范围推进。

### 表格自动适配

`editTable({ action: "autoFit", mode })` 支持 `content`、`page` 和 `fixed`。内容模式写 `tblLayout=autofit`、`tblW=auto/0` 与各格 `tcW=auto/0`，随后每次排版按内容重新求宽；页面模式改为 `tblW=pct/5000`，跟随当前可用页宽。固定模式测量当前有效列宽后写 `tblLayout=fixed`、整数 twip 的网格及表/格 dxa 宽度。每次切换共同提交一次历史，保留合并跨度、段落身份、文字、格式、选择、其他部件与待输入格式；同源无变化不增加历史。

缺省 `tblLayout` 按自动模式读取；表样式和直接 `tblPr` 决定模式及表宽，直接属性优先。dxa 偏好转为点值，pct 的 0–5000 转为可用页宽的比例；auto/nil 表示未指定。公共 `Table` 携带 `autoFit/preferredWidth/preferredWidths`，布局层使用授权字体的相同塑形结果求字素、单词和不换行宽度，再合入边距、半描边、行内图片、缩进、列表和制表位置。单列约束先求，合并格不足部分按源网格比例分配；不足以容纳最小单词时向字素下限收缩，字素或图片仍放不下则拒绝。列宽最终落在整数 twip，受可用页宽及既有资源上限约束。规则参考 [ONLYOFFICE 自动表格宽度](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L448-L648)及[合并格约束](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L864-L1050)。

低层 `FoundationSession/Client.editTable` 的第 4 个参数为字体 profile，测量操作必须提供所需映射；`DocumentEditor` 自动传入宿主 profile，图片沿已提供资源预检。`queryFormatting(...).table.autoFit` 返回当前模式。自动模式中的 `width/columnWidths` 为保存的回退网格，有效宽度来自布局；默认 UI 显示自动状态，并在冻结后开放手动宽度输入。程序化整表/单列宽度修改也会先测量并转为固定模式；目标列至少 12 pt，已有其他窄列保持。Canvas、命中、选择、缓存和 PDF 共用有效网格。未知属性/保留标记、缺字体/字形、无法排版或预算失败不提交。嵌套/浮动表格和更广宽度类型继续按原保护范围处理。

### 表格行跨页

`editTable({ action: "rowSplit", value })` 设置当前格所在行是否允许拆分，`value` 必须为布尔值。核心写入 `cantSplit val="0"/"1"`，有效值相同时保留源及 revision。`queryFormatting(...).table.rowSplit` 和 `DocxFlow.tables[].splitRows` 返回有效设置，包含表格样式链继承，缺省允许拆分。默认 UI 提供当前行复选框。结构操作保留并复制已有行属性；开关、文字、选择和待输入格式沿现有事务及精确历史恢复。

普通自动/最小高度行按每格的实际文字行分页，各格独立继续，保留横向跨度、图片及逻辑位置。每页片段保留边框、底色、边距和单元格命中区域，短格结束后的空白定位到原内容末尾。新页首行重新应用首行行距，跨页间距不重复累积；段末间距在页底截断，不单独生成空白续页。行最小高度仍占位，单行或边距超过可用页高时明确失败，沿现有 1024 页和 32768 行预算终止。

禁止拆分时先将行移到新页；整页仍放不下时继续分页，避免丢字或无限换页。规则来自 [OOXML cantSplit](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.wordprocessing.cantsplit?view=openxml-3.0.1#remarks)；逐格继续及首个文字片段垂直对齐参考 [ONLYOFFICE TableRecalculate.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L2710-L3495)，未复制上游代码。精确高度仍沿[裁剪规则](#表格尺寸)。实现归 [`table-row-continuation.mbt`](../../modules/layout/src/table-row-continuation.mbt)及 [`table-height.mbt`](../../modules/formats/src/docx/table-height.mbt)。

纵向合并组先按源行推进边界，再分配每个逻辑格的页面片段。普通相邻格决定各行的最小结束位置，合并文字可穿过中间行，其结束行仅在自动/最小高度模式扩展。每个片段保留起始格的内容身份和填充，页边界补齐合并格的外边框，内部合并边保持关闭。居中/底部对齐只作用于首个含文字的片段；精确结束行继续裁剪超出格框的文字，不生成额外内容页。

能放进一页的首组合并行仍与前方 `keepNext` 标题整体保留；超长组保留首个可放片段。重复表头、原生输入、源历史、保存重开、空白区域命中、光标/选区和 PDF 沿现有路径工作。布局继续使用相同的 1024 页、32768 行及候选预算。合并内容归属与结束行计算参考 [ONLYOFFICE 合并格续排](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L2710-L2805)及[首个文字片段对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L3400-L3495)，未复制上游代码。实现归 [`table-merge-continuation.mbt`](../../modules/layout/src/table-merge-continuation.mbt)；嵌套/浮动表格继续保护。

### 重复表头

`editTable({ action: "headerRows", value })` 将当前表开头的 `value` 行设为重复表头，并移除后续行的直接表头标志。0 清除全部，值须为 0–1000 且不超过表的行数。`queryFormatting(...).table.rows/headerRows` 返回总行数与有效表头行数，`DocxFlow.tables[].headerRows` 为相同的有效连续前缀。默认 UI 提供行数输入。

导入只读取开头连续开启的 `tblHeader`。纵向合并跨越表头边界时，缩短有效前缀；主动设置这样的边界原子拒绝。规则依据 [ONLYOFFICE private_RecalculateHeader](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L1836-L1891)。源标志、内容、段落身份、其他部件与待输入格式沿已有单项历史保存、撤销和重做。

自动分页在后续页重画表头，复用文字、图片、合并、边距、对齐、底色和边框几何；Canvas 与 PDF 使用同一结果。表头与下一行所需片段放不进一页时，该页省略副本，正文继续排版；最小行高仍参与判断。表头自身跨多页时不重复。副本不增加逻辑文字、查找结果、键盘导航或选区高亮；点击副本定位源表头，编辑源行后各副本同步。布局 `Line.repeated` 标记副本，增量缓存键包含表头依赖，复制行计入行预算。纵向合并组按最大需保留文字片段预留表头空间；放不下时该组的续页省略副本。

### 列表读取与标记排版


核心读取主文档及表格中的 `numPr`，合并默认/段落样式和直接 `numId/ilvl`；`numId=0` 取消继承。编号部件使用独立抽象定义、实例及 0–8 级别。支持 `decimal`、`decimalZero`、大小写字母、大小写罗马数字和 Unicode 项目符号；读取级别的起始值、父级重启、`startOverride`、文字模板、对齐、后缀、段落及字符属性。正文与表格按源顺序计数，同一抽象定义的实例共享计数；首次遇到实例时应用当前级别的起始覆盖。`lvlOverride` 可覆盖已支持的级别属性，外层与内层 `ilvl` 必须一致。模板、文字和几何使用有效级别；计数起点及父级重启仍取抽象定义，缺失抽象级别的默认起点为 0。行为依据 [ONLYOFFICE 的编号计数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L28708-L28931)。

标记字符格式合并段落样式、段落标记直接属性和级别属性；级别定义最后覆盖。段落标记的直接下划线不传给列表标记，级别显式下划线仍可生效。依据 [ONLYOFFICE 的编号文字属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L1877-L1918)。

字母编号使用 `a…z, aa, bb…`，每 780 个值循环；罗马数字每 32767 个值循环。字母/罗马值为 0 时不输出数字字符，模板中的标点保留。依据 [ONLYOFFICE 数字格式化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/editorscommon.js#L8141-L8225)。整数不超过 2147483646；计数溢出明确失败。每份编号部件最多索引 4096 个抽象定义与 4096 个实例，标记最多 256 UTF-16 单元。编号身份一次建索引，重复数字身份、缺失引用、非法级别和未知有效属性拒绝解释，源包仍可原样保存。

派生 `Paragraph.marker` 为可选的 `{ text, style, align, suffix }`，只用于布局。`suffix` 为 tab、space 或 nothing。核心独立塑形标记，按首行位置和级别对齐放置，再计算正文的首行起点；续行使用段落缩进。RTL 按右侧起点定位，保留字形顺序；标记的字号和装饰参与行高及绘制，自动颜色沿正文/单元格背景计算。标记不进入正文 spans、光标 offset、命中区段或文字选区。`Line.marker` 保存其绘制区段，`markerText` 带输出后缀；缓存分别复制标记几何并计入原有预算。段首显式分页保留分页前标记，后续行不重复。

预览和 PDF 消费相同标记图元。PDF 的 ActualText 和默认 UI 的页面文字包含标记；`SemanticLine.marker` 是可选文字前缀，`text/start/end` 仍对应正文。支持的 `numPr` 已接入文字、段落格式与结构编辑；非空段落的 Enter 保留列表引用并重新计数。未知编号属性继续保护。

`FoundationSession/Client.enterDocx(revision)` 与原生 Enter 使用同一核心操作。空项在第一级退出列表并清除直接左/首行缩进，在更深级别降低一级。Enter 先删除已有选区，再判断空项规则；删除和列表变化合为一次历史。粘贴 LF 仍拆分段落，不触发空项退出。段首 Backspace 在更深级别降低一级并清除直接左/首行缩进；第一级退出时保留有效正文左边界 `max(left, left + first)`，首行缩进置零。右缩进和其他段落属性保留。规则依据 [ONLYOFFICE Enter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L19421-L19463) 与 [Backspace](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L4315-L4345)。

列表段首或从段首开始的选择使用 Tab/Shift+Tab 调整层级，范围限制为 0–8，触及边界不增加历史；跨段选择按各自级别调整。混合选择中的普通段落按 12.5 mm 网格调整左缩进，写回整数 twip。折叠在第一级且当前计数不大于 1 时，改为按文档默认制表间隔平移全部已定义级别，并清除当前段落的直接左/首行缩进；反向移动保持非负的标记位置。存在完整级别覆盖时修改该覆盖，否则修改共享抽象定义，相关实例一同重排。该特例要求有效零级定义有左缩进；缺少时保持原样。列表文字中间的 Tab/Shift+Tab 插入字面 Tab；原生 Ctrl+Tab、粘贴和表格导航仍沿原路径。编号部件与段落属性合为一项历史。规则依据 [ONLYOFFICE Tab](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L5146-L5205) 和 [编号缩进](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/Num.js#L461-L474)。修改或删除含未知注释/处理指令的属性时明确拒绝，保留源内容。

`FoundationSession/Client.lists(revision)` 返回 `{ revision, truncated, lists: [{ id, preview, reason, levels: [{ level, format, pattern, start, restart, align, suffix }] }] }`，最多 1024 项。不可编辑定义提供原因。`editList(revision, selection, change)` 支持 `{ action: "create", format }`、`{ action: "apply", id, level }`、`{ action: "remove" }`、`{ action: "restart", start }` 和 `{ action: "level", increase }`。`format` 为上述七种格式，`level` 为 0–8；`start` 为 0–2147483646，重启要求折叠选择且不接受项目符号。

`level` 命令要求选择包含列表，按各段当前级别升降一级并清除直接左/首行缩进；同选的普通段落按上述网格调整，合为一项历史。默认 UI 的级别按钮使用同一命令，支持混合状态。`DocxFormatting.list` 提供列表身份/级别的一致值、混合或不可用状态。

`DocumentEditor.lists()` 与 `editList(change)` 沿现有队列执行，默认 UI 提供目录、创建、应用、移除、级别调整和重启。创建提供九级默认定义；缺少编号部件时同步创建关系与内容类型。移除以 `numId=0` 取消继承并保留直接段落格式。重启复制独立定义，保留当前父级计数，并更新受影响的后续项目；依据 [ONLYOFFICE 重启编号](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L25105-L25218)。每次命令合为一项有界历史，失败保留原包；撤销、重做和保存重开恢复相同结果。自定义级别编辑归下文。

`FoundationSession/Client.updateListLevel(revision, listId, level, definition)` 与 `DocumentEditor.updateListLevel(listId, level, definition)` 修改已有级别，不要求正文选择。`DocxListLevelUpdate` 包含格式、模板、起点、父级重启、标记对齐和后缀；可同时修改左/首行缩进与标记字符属性。默认 UI 从列表目录读取这些参数，并提供同一修改入口。读取后若文档已改变，需重新读取列表再修改定义，防止旧参数覆盖新值。

`definition` 必须提供 `format`、`pattern`、`start`、`restart`、`align` 和 `suffix`。`pattern` 为 1–256 UTF-16 单元，`%1`–`%9` 只引用当前或之前已定义的级别，其他文字原样输出；拒绝控制字符和非法 XML 文字。引用项目符号级别时数字片段为空，模板标点保留，依据 [ONLYOFFICE 数字格式化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/editorscommon.js#L10428-L10439)。`start` 为 0–2147483646；`restart` 为 null（缺省父级规则）、0（永不重启），或 1–当前级别索引（对应从 1 开始的父级）。`align` 为 left/center/right，`suffix` 为 tab/space/nothing。

可选 `left/first` 沿用整数 twip 可表示的 pt 范围，null 清除级别上的直接值。可选 `character` 接受已有字符属性片段，禁止 `style` 引用；省略属性保持，null 清除。定义修改不覆盖正文直接格式，待输入字符格式也保留。已有完整级别覆盖时修改该覆盖，否则修改共享抽象定义；依据 [ONLYOFFICE SetLvl](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/Num.js#L131-L147)。改变级别起点不会删除实例的 `startOverride`；计数仍遵守前述抽象定义和实例覆盖规则。

编号 XML 的所有变化合为一项有界历史，主文档源内容不变。核心在提交前验证级别引用、已有编号结果、相关段落属性、包与历史预算；失败保留文档、选择和历史。修改会使相关编号重排，撤销/重做及保存重开保留相同模板、标记样式与缩进；预览和 PDF 沿已有标记路径输出。

当前不解释图片项目符号、编号样式链接、级别中的样式绑定、法律编号、修订编号及其他地区格式。使用中的定义含这些结构时明确失败，未知源内容照常保留；字体或字形缺失也不静默替换。页眉等内容区域仍受原有范围限制。

## 通用绘制输出

`@open-document/wasm/drawing` 定义 `DrawingBatch`、`DrawingRegion`、`DrawCommand` 和批量校验。`DrawingBatch.regions` 是绘制区域数组；DOCX 中每个区域对应一页，XLSX 屏幕结果对应一个视口，PPTX 对应当前幻灯片。区域只包含 `width`、`height` 和有序 `commands`，不包含段落或表格模型。区域原点在左上，坐标为 point，x 向右、y 向下。Renderer 使用 `drawRegion`，旧的页字段与方法已删除。

当前指令如下：

| `op` | 数据与作用 |
| --- | --- |
| `fillRect` | `rect: { x, y, width, height, color }`；颜色是六位十六进制 RGB |
| `strokeRect` | `rect`、`color`、point 单位的 `lineWidth` |
| `glyphs` | 批次原点 `x/y`、`color` 和 `glyphs`；每个字形给出 `outline`、相对 `x/y`、`scaleX/scaleY`，核心已确定方向与位置 |
| `image` | `image: { key, x, y, width, height }`，消费已解码的图片 |
| `path` | `path` 为 move/line/cubic/close 数值段；`fill`/`stroke` 为 RGB 或空串，`lineWidth` 为 point |
| `transform` | 压入有限、可逆的仿射 `matrix: { a, b, c, d, e, f }`；与当前矩阵合成 |
| `style` | fillAlpha/strokeAlpha、evenOdd、cap/join/miter、dash/dashOffset、multiply、imageSmoothing；设置当前图形状态 |
| `clipPath` | 路径与 evenOdd；压入路径裁剪，空路径产生空裁剪 |
| `clipRect` / `restore` | 压入矩形裁剪 / 恢复最近矩阵、裁剪及样式；批次须平衡 |

核心生成完整区域的绘制顺序和裁剪。`outlines: { key, path }[]` 与 `images: string[]` 独立于区域；批次中每个轮廓仅保留一份，键为字体 SHA-256 与 glyph ID。`addImage(key,width,height,rgba)` 返回由尺寸及 RGBA SHA-256 组成的资源身份；同一源键替换像素后返回新身份。平台位图按此身份缓存。Canvas 按完整批次淘汰上一页轮廓，开始绘制时重设样式；路径 `lineWidth: 0` 表示设备细线，非均匀变换时按最大尺度近似。

`layout(profile)` 返回 `PageLayout`：绘制批次、会话内 `id`、`revision`、复用计数、字体信息、profile、诊断，以及独立的 `semantics`。语义页按阅读顺序保留行文字、源位置、方向、只读原因与文字边界。宿主用它展示文本并初始化焦点；命中、光标和选区仍查询核心。完整 run、carets、图片布局和表格模型留在内部 `Layout`，供编辑几何及 PDF 使用。

宿主校验有限数值、尺寸、颜色、路径、矩阵、嵌套栈和全部资源引用。每批指令/路径段/glyph 累计最多 1048576 项，栈深度最多 32，数值绝对值最多 1e9；轮廓仍最多 8 MiB。未知指令、无效输出及缺资源明确失败。`@open-document/web/drawing` 的 `CanvasRenderer` 只执行这些指令，并保留独立 `shape()` 探针的绘制入口。

`CanvasSurface` 共用尺寸、DPR、透明覆盖层、绘制身份与资源释放。DOCX 的 `PageCanvas` 继续准备文档图片。相同 `id`、区域、zoom 和 DPR 下，只清除并重画覆盖层；仅像素尺寸变化时重设画布尺寸。缩放与窗口 DPR 变化重新呈现，覆盖层几何须匹配当前布局身份与 revision。

预览与编辑共用此路径。宿主在关闭时释放 Canvas、Path2D 和 ImageBitmap；内容与覆盖层共同计入像素预算。JSON/Worker 仍按批次传输。PDF writer 消费 `PositionedDocument.pages[].primitives` 的有序矩形、边框、文字、独立图片、路径、矩阵、裁剪和恢复操作。DOCX 从内部布局转换，XLSX 从独立打印布局生成，PPTX 从幻灯片布局生成；旧分组结构已删除。字体嵌入、Unicode 与裁剪仍由核心处理。

### DOCX 页面 PNG

Web 宿主 `DocumentEditor.exportPng(scale = 1, outputBytes = 67108864)` 返回当前页的 PNG `EditorOutput`。先调用 `goToPage(index)` 可逐页获取，index 从 0 开始。`scale` 是每 point 的像素数，允许 0.25–4；默认 1 对应 72 DPI。图片尺寸为页宽高乘 scale 后向上取整，不跟随预览 zoom 或设备 DPR。默认文件菜单提供“当前页 PNG”，沿既有 `onSave` 或下载路径输出原文件基名的 `.png`，不清除 DOCX 修改状态。

`DocumentEditor.exportPageImages(scale = 1, outputBytes = 67108864)` 一次返回全部页面的只读 `EditorOutput[]`，按页序排列且共享文档身份与 revision。总字节预算计算所有 PNG 的字节数之和，不是每页单独授予预算。页面依次编码并释放临时 Canvas，保留的 PNG 总量受同一预算约束；全部成功后才返回集合和登记输出，编码失败不交付前缀集合。导出不改变当前页、缩放、选择、源或历史。

默认菜单的“全部页面 PNG”先生成完整集合，再按页序等待既有 `onSave`；文件名使用 `<原文件基名>-01.png`、`-02.png`，页号至少两位并随总页数补齐。回调期间可以继续编辑，已生成页面仍绑定原 revision。宿主中途失败时显示已完成页数，保留已完成的外部保存，不继续后续回调，也不清除 DOCX 修改；重试重新导出当前修订的全部页面。无 `onSave` 时逐页发起下载并报告生成进度，不确认磁盘持久化；多文件下载受 [Chrome 站点下载权限](https://support.google.com/chrome/answer/114662?hl=en)约束。

输出进入同一原生输入队列。它包含已接受的编辑，绑定文档身份和 revision，后续排队编辑不改变已产生的图片。当前布局须匹配 revision，并且无未支持布局诊断；活动组合或图片缩放候选须先结束或取消。核心继续拥有分页、正文、表格、页面背景/边框及图片位置；平台只用现有 R0、轮廓和已准备位图绘制到独立 Canvas 后编码。选区、光标、批注高亮等覆盖层不进入 PNG。

输出 Canvas 与保留的预览/覆盖层合计最多 16777216 像素，输出字节预算为 1–67108864；尺寸在分配前检查，编码后检查实际字节数，并在成功或失败后释放临时 Canvas。PNG 失败保留源、选择及历史，不停止编辑；下一项成功操作清除 PNG 错误。销毁期间不交付图片。原格式保存与 PDF 继续沿原有恢复规则。

图片输出目标参考 [GenOffice exportImages](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/file-actions.ts#L1463-L1540)。当前复用已有核心绘制和 [Canvas 编码](../../packages/web/src/canvas-surface.ts)，未移植其 Electron/PDF.js 导出路径；队列与入口归 [`document-page.ts`](../../packages/web/src/document-page.ts)及 [`document-output.ts`](../../packages/web/src/document-output.ts)。这是 Chrome/Chromium 的 Web 输出；其他编码和无浏览器图片输出继续实施。

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

一次段落塑形的全部字体/script run 另共用 67108864 单位的查表预算。指定 OpenType 查表函数的 Result 入口、循环迭代和按长度计费的批量操作递减同一计数器；GSUB/GPOS、Coverage/ClassDef、GDEF 过滤及试探查表超限统一返回 `limit-exceeded`。字体表初次解析另有同限额。该限制可能拒绝工作量过大的合法字体，不能代表整次文档操作的时间上限、所有字体分配或进程峰值内存；具体范围与补丁身份见[依赖说明](dependencies.md#累计查表工作量)。

## 文件 profile 与保真

ZIP 支持单磁盘非加密 ZIP32、stored/deflate、UTF-8 或未标记的 ASCII 名称、12/16 字节 data descriptor。拒绝 ZIP64、加密、未知 method/flag、截断、重叠、重复名字/目录、错误 CRC 与解压长度。保留源记录用于未改条目；ZIP 包级 comment 和修改条目的压缩方式不保证词法恒等。

XML 支持 XML 1.0/Namespaces 1.0、UTF-8 和带 BOM 的 UTF-16 LE/BE；编码声明与实际字节必须一致。源片段 offset 统一是解码后的 UTF-16，ZIP 错误 offset 是字节，未知位置为 −1。禁止 DTD 和外部实体；没有文件/网络 entity resolver。允许普通转义/数字字符引用、CDATA、注释、PI、空元素；拒绝重复属性、无效 namespace/PI 名称、非法字符与错误语法。未改 XML 保留原字节；编辑 XML 写成 UTF-8，并更新声明，保留 standalone。

OPC 识别 content types、package/part relationships 与相对 target。关系 ID 只在 owner 内唯一，外链只作为数据返回、从不加载；内部路径不能逃出包。part 名称按 ASCII URI 和 UTF-8 percent escapes 校验，拒绝路径分隔符/非规范 unreserved escapes、尾点、大小写身份冲突和悬空关系。

DOCX 依据 officeDocument relationship、main content type 与 Word namespace 识别，支持 Transitional 主部件。查询正文中直接属于 paragraph/run 的 `w:t`，包括表格内正文；其他结构保留，未知直接 body 结构给诊断。不是 OOXML schema validator，不将未读 customXml/资源当作已理解能力。替换只允许无子元素的已知文本节点，自动转义和设置 `xml:space="preserve"`；未知 markup 保留在原位置，重复保存不累积转义。

Strict、Office/ZIP 加密、宏主部件、签名安全改写和旧二进制格式不在支持面。签名关系可在打开阶段拒绝；签名材料仅被识别时允许只读查询，但编辑/保存拒绝，不能把签名图片或未验证的 signature 当作有效签名。

## 失败

MoonBit 共用 `Failure`，浏览器暴露 `DocumentError(code, message, part, offset)`。主要类别为 `malformed-package/xml/opc/docx/font`、`unsupported-package/xml/docx/font`、`limit-exceeded`、`missing-part/font`、`stale-revision`、`invalid-operation/budget/position`、`protected-content` 和 `closed-session`。Worker 关闭或宿主错误仍是普通 Error。失败不能返回空文档或伪造 revision；测试分别检查错误身份与输入/编辑状态。

当前使用固定 Chromium release WasmGC、独立 ZIP/XML 对照、HarfBuzz 塑形及 qpdf/Poppler 输出检查。P3 的 LibreOffice 固定参考与真实 Canvas/PDF 检查不代表全 Word 兼容；系统输入法的全面覆盖、完整 schema、PDF/A 和 PDF/UA 尚未验证。执行入口与证据规则见[测试说明](testing.md)。

## DOCX 布局与 PDF 输出

普通数字使用默认字形；共享塑形入口禁止固定依赖将 `frac/numr/dnom` 全局应用到所有数字。四种固定 Noto 字体的独立默认字形/位置已核对。当前没有 OpenType feature 编辑 API，也未实现 U+2044 上下文触发的自动数字分数排版；字符和 DOCX 源照常保留，不冒充完整 HarfBuzz 行为。原有连字、BiDi、字素及测宽/绘制共用路径保持。

DOCX 的显式页面宽、高按固定 LibreOffice 25.8.2.2 的[导入规则](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/sw/source/writerfilter/dmapper/DomainMapper.cxx#L824-L837)转换为整数 1/100 mm，各自按[标准尺寸表顺序](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/i18nutil/source/utility/paper.cxx#L208-L224)选择差值严格小于 44 的首个值并回到整数 twip；不匹配值及缺省页面保持，非法值仍由原页面 validator 拒绝。500 pt 可成为 498.9 pt，1000 pt 可成为 1000.65 pt；这是显示布局尺寸，原 pgSz XML 和包部件不改写。普通换行候选在布局层排除补充码点之前的边界，以匹配 LibreOffice/ICU 的 UTF-16 查询；强制换行、段末、字素紧急回退和标准 Unicode 分段模块保持。十二份同字体控制与原 DPR2 输入已由重复独立参考和实际两宿主核对，不承诺所有 CJK 或 Office 版本的行为。尺寸事实有来源，算法独立实现；未移植上游可执行代码或新增依赖。

共享自然行度量使用固定 LibreOffice 25.8.2.2 的[MSO1 参考设备](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/vcl/source/gdi/virdev.cxx#L405-L406)。每 pt 120 单位，字号和 ascent/descent 先取整为设备单位。再将 ascent 与组合高度分别换算为整数 twip，布局输出仍用 pt。依据[字体度量取整](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/vcl/source/font/fontmetric.cxx#L538-L539)和[组合高度换算](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/vcl/source/outdev/font.cxx#L205-L210)，不是简单将浮点 pt 乘 20 取整；固定 Noto 的 10 pt 为 273 twip。源字号/XML、字体选择、字形 advance、Exact 基线和 API 保持；五字号表格与另组正文重复参考只授予自然高度与已声明垂直步距。

字体自然高度优先使用有效 USE_TYPO_METRICS，随后是有效 hhea，最后回退到已验证的 Win 度量；缺失或截断 hhea 原子拒绝。`FontInfo` 的 ascent/descent 随此选择，CJK 与 Arabic 的预定变化已由固定字体二进制独立核对。光标在单文字区段复用行框，多区段按前侧文字区段取自然高度并裁剪到当前页段落底部；`caret`、`hitTest`、导航共用计算。原 CJK 与六组垂直控制已匹配固定参考。十二组独立原生对照另验证中西文自动间距、不同字号和窄行，以及 Arabic/Asian 进入和退出区段的差别；测宽、字形和光标共用间距，行尾仅在宽度允许时保留。有效 autoSpaceDE/DN 源属性按固定 LibreOffice 25.8.2.2 导入行为保留但不应用，非法或重复声明继续保护。两份 Arabic/Asian 原件已验证折叠 Left/Right 的 after/before 坐标及高度、70 个独立鼠标位置和 36 个默认逻辑按键位置；真实编辑器按键在 Chromium 验证。所有脚本分类、嵌套 BiDi、小字号间距命中及其他导航配置仍未全面验收；证据与范围见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)。

自动行距修复已通过完整运行 `1791779829628`。按固定 LibreOffice 的[导入取整](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/sw/source/writerfilter/dmapper/DomainMapper_Impl.cxx#L5303)，先将 auto 值换成整数百分比；0 按 100%，非零最小为 50%。[首行与后续行](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/sw/source/core/text/itrform2.cxx#L2335-L2422)分别处理正间隙与收缩，[段间间隙](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/sw/source/core/layout/flowfrm.cxx#L1644-L1743)归属前段，换页清除。单元格和空页眉末段按[专用路径](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/sw/source/core/layout/flowfrm.cxx#L1934-L1942)及[名义字号的 1.15 系数](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/sw/source/core/layout/frmtool.cxx#L2674-L2683)留出底部间隙。ONLYOFFICE sdkjs 的[比例间隙](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js#L2988-L2996)另有浮点路径；本阶段采用已冻结 LibreOffice profile 的规则。23 组正文、表格末段和有效段距参考均由安装 Node/生产 Worker 验证，原 15 组完整页面、状态和保存结果保持。磁盘及后续失败记录保留。图片自动行距及原生 caret/选区仍未获得本批几何验收，证据见[测试记录](testing.md)。

行距保留 `{ rule, value }` 的原始 OOXML 数值，先合并默认值、`basedOn` 与直接格式，再解释单位。`auto` 的单位为 1/240 行；`exact` 和 `atLeast` 为 twip。仅覆盖段前或段后距不改变行距；最小值 0 使用自然行高。固定行距采用 LibreOffice 25.8.2.2 参考配置：基线位于行高的 4/5，段尾手动换行的空行保持相同行高。共享布局的 `clip` 指令让 Canvas 和 PDF 在行的垂直范围内裁剪文字与内联图片；最小行距保留自然基线。该配置依据 [LibreOffice 行度量](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/source/core/text/itrform2.cxx)，不声明各 Office 应用采用相同基线。

`flow().additiveSpacing` 指明段距策略。普通同页相邻段落在 `settings.xml` 存在且 `doNotUseHTMLParagraphAutoSpacing` 缺省或为 false/0/off 时，合并为 `max(previous.after, current.before)`；该标志开启时累加。缺少整个 settings 部件时，保留固定 LibreOffice 配置的累加默认值。正文和同一单元格使用相同规则；自然换页舍弃跨页间距，显式段前分页保留当前段前距，单元格首段前距与末段后距计入行高。段内显式分页结束时舍弃该段段后距。固定参考转换分别核对了这几类边界。

上述策略结合 [ONLYOFFICE 普通段距与特殊分支](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L10805-L10860)、[LibreOffice 布局分支](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/source/core/layout/flowfrm.cxx#L1582-L1770) 与固定引擎结果；不是完整 Word 间距规则。`contextualSpacing`、自动段距、按行指定的段距及上述范围外的编号仍不支持，直接格式和实际应用的默认值、样式链都会报告部件与特性，例如 `unsupported-layout:word/styles.xml:w:vanish`。未使用的命名样式不产生诊断。原始内容照常保留，应用不能把带诊断的结果称为保真布局。

自动断行前只解析一次整段 BiDi 层级；选定行执行 UAX #9 L1/L2，塑形沿用该层级与镜像规则。同样式源 run 拆分不会改变阅读顺序；使用独立 FriBidi 1.0.16 的整段层级核对 RTL、数字、括号及拉丁后缀，不以片段重新推断方向生成答案。

浏览器预览只接受 PNG、JPEG 与 GIF。宿主先检查有界编码头的尺寸与像素预算，再调用原生解码器；解码结果仍核对预算与头部尺寸，失败或取消关闭已创建的 ImageBitmap 并保留宿主。GIF 使用原生解码器选取的静态帧，不支持动画播放；其他编码明确失败。该检查不保证浏览器或 WasmGC 的进程峰值内存。

`flow()` 返回派生的段落、样式、页面设置、表格、内联图片引用和诊断；不能修改它来编辑文档。段落与表格数组各自保持源顺序；顶层表格的必需 `beforeParagraph` 是当前源 XML 中先于该表格的正文段落数，同位置连续表格按表格数组顺序插入。稳定 `id` 不表示文档位置，拆段后也不按 ID 排序。`layout(profile)` 在核心中生成 `PageLayout`，profile 将 DOCX 字体键（含 `|bold` / `|italic`）映射到已供应字体 identity。缺字体或字形明确失败，宿主不提供 DOM 测量。布局长度单位为 point；字体内部度量仍用 font units，源范围使用节点局部 UTF-16 offset。

支持 docDefaults、段落/字符样式 basedOn、主题 Latin 字体、直接格式、字号/颜色/粗斜体、段前段后、缩进、左/中/右对齐、auto/exact/atLeast 行距、空段落及显式分页。正文、表格和页眉页脚共用段落间距校验，负间距/最小行距/单元格 padding 明确失败。页面使用单一设置，多节文档给不支持诊断，不承诺各节独立分页。分页的断行使用固定 Unicode 数据与基本 BiDi；同样式跨文本节点一起塑形并保留源映射。`unicode_linebreak` 的 Unicode 15 测试向量按上游规则排除 30.22/999.0 做依赖回归，其字符表源自 Unicode 13；不宣称完整 UAX #14 符合性。当前 fallback 仍按码点选择，复杂 script、彩色字形和任意字体质量不在承诺范围。

基础表格使用固定列宽、当前支持的实线/无边框、RGB 单色填充、四边 cell margin 和最小/精确行高；普通行[逐格跨页](#表格行跨页)，纵向合并行组整体换页。边框编辑与冲突规则归[表格边框](#表格边框)。相邻行共享边框只占一次高度，表尾另留底边，分页判断包含当前页底边空间。自然字高使用上述共享参考设备取整；固定 Noto 原表格的自然行高与垂直步距已匹配固定 LibreOffice，不扩大为所有应用或水平几何一致。嵌套单元格仍明确拒绝；精确行高沿[裁剪规则](#表格尺寸)。不绘制浮动、旋转或翻转图片；页眉页脚已接通[文字、实际避让与逐页输出](#页眉页脚)。已识别但未实现的正文属性给诊断，原包仍由 P2 保存；不是完整属性/schema 检查器，主题颜色、条件表格样式与复杂页眉页脚不在支持面。图片仅支持包内内联 extent；宿主解码已授权资源为 RGBA，外链图片明确拒绝、不自动下载。

表格左/中/右对齐按基础样式、派生样式、直接属性依次覆盖，start/end 沿用 left/right 归一化；未知有效值报 `unsupported-layout`。明确零 dxa 缩进仅在可选符号后全零数字、已知属性且无子节点/文本时视为无位移；非零、非法或未知声明仍诊断/保护。此规则不增加非零缩进、RTL 表格语义或复杂表格支持。Word compatibilityMode 对表格外侧边距和定位的版本差异尚未实现，零缩进声明可读不等于版本布局已经一致；固定网格超过正文可用宽度仍明确拒绝，不通过缩小原件或统一左移获得通过。原 POI 表格的 kern/ligature 诊断仍保留，普通核心源事务可用不等于可视编辑可用。

文字 `auto` color 延后到所在单元格背景确定后解析，正文背景为白色，显式 RGB 保持原值。固定参考 profile 采用 sRGB 相对亮度乘 255 小于 88 时白字、否则黑字，与已检查的 LibreOffice [automatic text color](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/source/core/txtnode/fntcache.cxx) / [Color::IsDark](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/tools/source/generic/color.cxx) 规则相符；不承诺任意 Word 主题的颜色结果。

成功的字体添加、图片添加、打开或正文替换令旧布局失效。`layout` 每次生成新的会话内 `id`；profile 改变必须重排。`exportPdf(outputBytes, layoutId?)` 使用当前核心布局，可指定展示时的 ID 防止旧预览下载新内容；没有布局或 ID 过期时失败。`DocumentPreview` 始终传自己的 ID。失败的图片替换不覆盖已加载资源；PDF 失败不提交部分输出。

`PageLayout.shapedParagraphs` / `reusedParagraphs` 是本次实际塑形/复用的段落几何数量（含表头、单元格及复用页面内的段落）；`reflowedPages` / `reusedPages` 是重新处理分页状态及直接复用的整页数，二者之和等于当前页数。它们不是耗时指标。完整源输入和字体/page/profile/间距依赖匹配时，核心复用局部行及页面前缀，在首个变化边界所在页继续原分页规则；只有未变后缀和纵坐标、段后间距及页内文字/边框有无全部匹配，才接回旧几何。表格按行检查稳定点，显式空白页规则不变；旧后缀仍检查当前图片及行/页预算。仅保留上次成功布局：塑形和分页各自最多 1024 条输入、1048576 个载荷单位，超限仍正常塑形/分页，不缩减文档支持。一个原始字段或字符串 UTF-16 单元计一单位，不代表堆字节或峰值内存；失败不提交候选缓存，成功增加字体后清空，关闭释放，返回的可变数组与缓存隔离。阶段范围与性能边界见 [P4](../implemented/p4-docx-editing.md#保留限制)。

Office PDF 输出使用同一字形坐标、TrueType 子集、字体宽度、CIDToGIDMap、ToUnicode 与行级 ActualText，支持图片及 alpha mask。字体 fsType 禁止嵌入/子集时失败。默认 variation 坐标与 face 0；不支持 CFF、PDF/A、PDF/UA、签名或浏览器打印。PDF outputBytes 是 1–67,108,864 字节的产物上限；在最终文档序列化前核对已构建对象 payload，再核对最终确切大小。它不是字体子集、临时对象或整个进程的内存上限。

一次段落布局内的候选测宽另保留最多 128 个成功宽度，每个精确键最多 4096 UTF-16 单元，键合计不超过 524288 单元，另有 128 个 Double。键绑定文本、字号、主字体和当前 BiDi 上下文；字体集合在该同步调用内不变。超限重新测量，图片和最终绘制不使用此表；返回或失败即释放，不形成跨段落或跨编辑的持久缓存。此载荷计数不代表实际堆峰值。

每段最多 4096 UTF-16 单元，最多 1024 页 / 32768 行。图片最多 256 个，每边最多 4096 像素，总 RGBA 16 MiB；当前页内容与编辑覆盖层合计最多 16777216 像素，zoom 0.25–4。预算分别约束核心资源、产物与宿主 Canvas，不等于进程峰值内存上限。

断行对候选前缀重新塑形以保留上下文，长无空格段落存在二次成本。Worker 隔离主线程，当前没有延迟 SLA。实际交互被阻断时再诊断，不能以每字符 advance 或 DOM 测量替代正确布局。

性能校准和进一步优化延后。已有输入/字形/历史/队列/布局/Canvas 上限、拒绝恢复和释放要求保持。

`DocumentPreview.create(root, client, profile, signal?)` 显示只读页面、文本和诊断，支持滚动、切页、缩放、键盘与 PDF 下载。`dispose()` 释放自己持有的 Canvas、Path2D、ImageBitmap、监听器和 DOM，保留宿主其他子节点并恢复属性；调用方另需 `client.dispose()` 释放 Worker/核心。取消在异步准备步骤之间检查，不能抢占正在执行的同步 Wasm。基础文本语义与可达按钮不是完整文档无障碍认证。

## P5 XLSX 合同

`XlsxSession.create(budget)` 与 `XlsxClient.create(budget)` 创建一张可见的空白 `Sheet1`，选区为 A1，revision 与历史为 0。基础样式为 11 pt Calibri、General 数字格式、黑字、无填充/边框；工作簿使用自动计算。核心创建 workbook、worksheet、styles、关系与内容类型，之后沿相同读取、计算、编辑、历史及保存路径运行。默认 UI 与 `mountEditor`、实例 `create/open` 接通该入口；首次保存规则见上文。工作表和单元格身份由核心生成，不从文件名推导。

`XlsxSession` 和 `XlsxClient` 分别提供同步 WASM 与 Worker Promise API。核心持有 OPC/XML、稀疏单元格、公式依赖、选区、历史及几何；TS 只处理平台输入与呈现。工作表 `id` 来自包内关系目标。查询包含隐藏表，界面只列出可见表。

| API | 结果与约束 |
| --- | --- |
| `open(bytes,budget)` / `openXlsx(bytes,budget)` | 打开 Transitional XLSX；签名、Strict、加密和其他扩展格式拒绝 |
| `query(sheet?,range?)` | 默认当前选区；返回实际存在的稀疏单元格，单格查询包含空格；A1 地址，查询矩形端点有序 |
| `select(revision,sheet,range)` | 更新可见表的核心选区；隐藏表须先显示；单格合并区域定位锚点 |
| `editSheet(revision,sheet,change)` | 工作表新增、复制、删除、重排、改名、可见性、行高/列宽及矩形合并/取消合并事务；返回 `XlsxQuery` |
| `autoFit(revision,sheet,first,last,axis,profile)` | 按当前显示值和字体测量自动适配行高或列宽；返回 `XlsxQuery` |
| `replace(revision,sheet,range,values,literal=false)` | 一项矩形事务；字段为输入字符串，核心识别值与公式；清空保留样式 |
| `find(revision,sheet,text,options={})` | 返回有界单元格结果；支持当前表/工作簿、大小写、整格、公式源/计算值，不改选区 |
| `replaceMatches(revision,sheet,text,options,replacement,index?)` | 重新计算同一查询；有 index 时替换该格全部匹配，否则替换全部结果；一次原子历史 |
| `navigate(revision,direction,extend=false)` | `left/right/up/down/home`；跳过隐藏行列，Shift 扩展选区 |
| `copy(revision)` / `paste(revision,text)` / `clear(revision)` | 核心显示值 TSV、矩形粘贴及清空；核心识别数值/布尔，`=` 不执行 |
| `undo(revision)` / `redo(revision)` | 源片段、选区和计算结果原子恢复；revision 每次成功修改递增 |
| `save()` | 返回完整 XLSX；无编辑及全部撤销后保留原解压部件字节 |
| `viewport(options)` | 逻辑滚动、point 尺寸、sheet、字体 profile、可选 `reveal`；一个绘制区域及可见网格语义 |
| `hit(layoutId,x,y)` / `selectionGeometry(layoutId)` | 核心地址命中与选区矩形；旧布局身份或 revision 拒绝 |
| `printLayout(revision,sheet,options,profile)` | 独立打印区域，返回有身份的页面绘制批次 |
| `exportPdf(layoutId,outputBytes)` | 使用当前打印布局；编辑、字体变更或新打印布局使旧输出身份失效 |

`XlsxQuery` 返回 `sheets`、`sheet`、`selection`、`revision`、历史状态、`date1904`、`fontKeys` 和诊断。每格分别返回 `value`、`formula`、`cached`、`calculated`、`calculation`、`calculationReason`、`display`、`input` 与 `readOnlyReason`。空格、空字符串、零、布尔值与错误独立表示。`input` 是核心生成的可编辑源码，文字带前导单引号，避免重新提交时误作公式或数值。

### 选区统计

`XlsxQuery.statistics` 返回 `{ range, count, countNumbers, sum, average, min, max, reason }`，Wasm/Web 导出 `XlsxStatistics`。`range` 是此次查询的矩形；默认 UI 状态栏使用当前选区。查询及选区变化不改 revision、文档源、历史或保存状态。输入草稿期间显示已提交值；提交后使用当前公式结果，随历史、筛选及行隐藏更新。

`count` 计算非空值，包含文本、布尔值和错误；空白及空串不计。其余五项只计算数值，包括数值公式结果和日期序列值；数字文本与布尔值不转成数值。隐藏行（含筛选隐藏和零高度）不参与，隐藏列仍参与。行为依据 [ONLYOFFICE 的选区统计](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L13248)。当前只处理已有矩形选区，不包含非连续区域。

没有数值时，`sum/average/min/max` 为 null。当前输出原始数值，不应用活动单元格的数字格式；日期、百分比和货币的状态栏格式仍待扩展。核心使用缩放及补偿求和；总和超出有限数值范围时，`sum` 为 null 并在 `reason` 说明，仍返回有效计数、平均与极值。选区含未计算公式时，计数按已知值/缓存类型返回，四项汇总均为 null，`reason` 说明原因。源文件只读原因也进入 `reason`，不把导入缓存标为新计算结果。沿用查询最多 4096 个已有单元格的限制；统计复用此次查询的稀疏列表，不遍历大矩形中的空格。

### 单元格查找替换

`XlsxFindOptions` 包含 `matchCase`、`wholeCell`、`formulas`、`workbook`，默认依次为 false、false、true、false。查找使用非空字面文本，不解释正则或通配符；不区分大小写时使用固定 Unicode 简单大写映射。匹配保留完整 Unicode 字符，位置与长度按 UTF-16 计。公式模式搜索带 `=` 的源码，其余格搜索逻辑值；值模式搜索未应用数字格式的计算值或导入缓存。普通文本不包含编辑输入使用的转义单引号。

`XlsxSearchResult` 返回 `revision`、`truncated` 和 `matches`。每个匹配格只有一项，包含稳定部件路径 `sheet`、表名 `name`、`address`、`hidden`、`snippet` 和替换保护原因 `reason`，按工作表顺序、行、列排列。工作簿范围包含隐藏表；选择隐藏结果前须先显示该表。保护内容和公式计算结果仍可查找；值模式的公式结果不能替换，须切换公式模式修改源码。

`SpreadsheetEditor.find(text,options)` 先提交已接受的原生草稿，返回增加 `documentId`、查询表、文本与选项的 `SpreadsheetSearchResult`。`selectMatch(result,index)` 定位可见结果；`replaceMatches(result,replacement,index?)` 使用同一队列。组合输入未完成时拒绝；文档身份或 revision 变化后须重新查找。默认 UI 提供这三项操作和四个选项。

核心重新查找，不信任调用方给出的结果格。替换当前结果会替换该格全部不重叠匹配；替换全部跨表提交一次历史，保留当前选区，包含隐藏表。已有文本格保持文本类型，替换产生的 `=` 不执行；只有公式模式命中的真实公式会重新解析源码。数值/布尔格沿已有输入转换。任何匹配格受保护、公式无效或预算失败时，整项替换不提交；无变化不增加历史。

查询和替换文本各限 32767 UTF-16 单位；最多返回 4096 格，并在发现后续匹配时设置 `truncated`。截断结果不能全部替换。扫描文本总量限 8 Mi UTF-16 单位；每格输出限 32767、一次替换输入总量限 1 Mi UTF-16 单位，继续受工作簿、计算、历史和输出预算约束。结果片段最多 80 个完整 Unicode 字符。名称定位、格式化显示值搜索及正则/通配符不在当前范围。

### 工作表顺序、名称与可见性

`XlsxSheetEdit` 从 `wasm/xlsx` 和 `web/xlsx` 导出。`{ action: "move", index }` 将指定表移动到从 0 开始的目标索引，索引覆盖可见和隐藏表；`{ action: "visibility", state: "visible" | "hidden" | "veryHidden" }` 修改可见性。同步 Wasm、Worker 使用 `editSheet(revision, sheet, change)`；编辑宿主为 `SpreadsheetEditor.editSheet(change, sheet?)`，省略身份时操作队列执行时的活动表，先沿现有屏障提交单格草稿。无效状态、越界索引、旧 revision、隐藏最后可见表和预算超限不修改文档或历史。同位置/同状态不新增历史。

`{ action: "add" }` 在指定表后新增可见空白表，并激活 A1。核心分配唯一的 `SheetN` 名称、sheetId、部件路径和关系 ID，保留已有或未引用的同名源部件；会话内撤销后重新新增也不复用该身份。新表沿用工作簿基础样式。工作表 XML、关系、内容类型、局部名称索引、视图和选区合为一次有界历史；后续编辑与新增可混合精确撤销/重做。最多 256 张表，结构保护或预算失败不留下新增部件。默认 UI 提供同一新增入口。新增空表保留既有公式缓存、共享字符串计数和 calcChain。

工作表身份是 OPC 部件路径，移动保留 sheetId、关系、名称及公式源。历史中的 XML 编辑也按部件路径定位。核心同步名称的 `localSheetId`、窗口的 `activeTab/firstSheet` 与工作表 `tabSelected`，按新顺序重建计算索引。隐藏活动表时先向右查找可见表，再向左查找；显示表会将其激活并定位 A1。打开时沿首个 workbook view 恢复活动表，隐藏活动页则定位邻近可见表。仅改顺序/视图不清除 calcChain 或改写单元格缓存、共享字符串计数；实际单元格编辑继续沿已有计算元数据规则保存。

`XlsxQuery.sheetEditReason` 是工作表级管理操作的保护原因，空串表示可用。当前继续保护未知单元格公式、锁定结构的 workbookProtection、三维名称引用、无法解释的名称语法、非空工作簿扩展/自定义工作簿视图及未知根内容。源内容保留；不通过放开按钮改变引用语义。默认 UI 提供前移/后移、隐藏与显示普通 hidden 表；veryHidden 仅由显式 API 修改。

`{ action: "rename", name }` 修改表名，保持 OPC 路径、sheetId、关系、顺序、可见性及选区。名称为 1–31 个 UTF-16 单元，须是有效 XML 文本，不能含控制字符或 `[]:*?/\`，不能以单引号开头或结尾，不能与其他表名大小写不敏感地重复。相同名称不新增历史；无效名称、旧 revision 或预算失败不修改文档。

核心复用公式词法分析，仅替换 `!` 前匹配旧名称的标记。新引用使用单引号包围名称，并转义名称内的单引号。更新范围包括单元格公式、定义名称、既有条件格式/数据验证公式和内部超链接 `location`；带关系 ID 的外部链接保留其目标内位置。字符串常量、共享公式组与源格式保持不变；事务重建计算并沿既有计算元数据规则保存，撤销恢复原部件字节。规则呈现与编辑范围分别归[条件格式](#条件格式)和[数据验证](#数据验证)。

`{ action: "delete" }` 删除指定表，至少保留一张可见表。删除活动表时优先选择右侧可见表，再向左查找，定位 A1；删除其他表保留活动表与范围。同步剩余名称的 `localSheetId`、工作簿窗口及工作表视图；移除被删表的局部名称。将指向该表的已支持单元格/区域引用整体替换为 `#REF!`，覆盖单元格公式、保留的定义名称和既有条件格式/数据验证公式；移除指向它的内部超链接，保留外部链接及字符串常量。共享公式组继续保存为共享组，失去目标的错误参与依赖计算和缓存写回。核心现可解析七种标准公式错误常量，保留错误传播和 IF 的按需求值规则。引用错误在网格和 PDF 中使用同一结果。

`{ action: "copy" }` 在目标表后复制，分配新的 sheetId、部件及关系身份。名称从 `原名 (1)` 起避让重名，长度不超过 31 个 UTF-16 单元且不切断代理对。副本保留内容、格式、尺寸和可见性，更新自身显式引用与复制的局部名称；其他表的引用及字符串常量不变。已有普通便笺及对应 VML 复制为独立部件，清除副本的可选 guid/shapeId，源便笺不变；外部链接只保留地址。可见副本激活 A1，隐藏副本保留当前选择。副本部件和元数据使用同一有界历史，失败不修改文档。绘图、表格、非便笺 VML、线程批注及未知身份扩展仍受保护；便笺范围归[单元格便笺](#单元格便笺)。

删除移除工作表 XML、其关系、失效 calcChain 及其关系，以及独占的普通便笺 XML/VML，更新工作簿关系和内容类型。其余源资源保留，不回收共享字符串条目或重排字符串索引；保存更新使用计数并沿现有规则标记重算。删除部件快照、引用、缓存和选择共同提交一项有界历史，可与新增、输入和改名精确混合撤销/重做；损坏回放或预算失败保留已提交文档。选择与错误引用规则参考 [ONLYOFFICE 删除工作表](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L4122-L4188)和[引用转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L10419-L10455)。

`XlsxQuery.sheetRenameReason` 包含结构保护原因，并保护尚未接入引用更新的工作簿/工作表资源关系、未知工作表内容、非空扩展及非普通/共享公式组。复制和删除沿用该引用保护；复制另保护未知身份属性，删除另拒绝未知的部件入站引用。默认 UI 显示原因，提供名称输入、复制、改名与删除入口，并禁用最后可见表的删除。更广资源及引用处理仍归 [P11](../p11-xlsx-core.md)。

`{ action: "rowHeight" | "columnWidth", first, last, size }` 设置包含两端的行或列范围，索引从 1 开始。行高为 0–409.5 磅，一次最多 4096 行；列宽为 0–255 个 OOXML 字符宽度单位，列索引上限为 16384。零值隐藏并保留已有尺寸；正值设置固定尺寸并显示目标行列，列宽同时取消 bestFit。列宽由核心按 Normal 字体和字号的最大数字宽度换算为实际几何。设置行高可创建空行记录，不展开空单元格；拆分列区间保留各段的样式与轮廓属性。目标列包含未知属性或子元素时拒绝修改，保留源内容。

`XlsxQuery.dimensions` 返回查询范围的 `rowHeight`、`columnWidth` 和 `readOnlyReason`。尺寸不一致时返回 `null`，隐藏行列按 0 参与查询。默认 UI 对所选行/列设置尺寸。未知公式仍沿现有只读边界，受保护工作表拒绝尺寸修改；仅锁定工作簿结构不禁止该操作。一次修改进入既有历史，保持表身份和选区；重复设置相同源状态不增加历史。保存保留单元格源、公式缓存、共享字符串计数和 calcChain；实际单元格或公式变化继续触发原有计算元数据更新。自动适配及持续更新见下节；未编辑导入默认行的首次测量仍归 [P11](../p11-xlsx-core.md)。

### 行列插入与删除

`editSheet({ action: "insertRows" | "deleteRows" | "insertColumns" | "deleteColumns", first, count })` 操作整行或整列。first 从 1 开始；插入发生在该索引前，删除覆盖从 first 开始的 count 项。count 为 1–4096，区间须位于 1048576 行或 16384 列内。默认 UI 根据当前矩形选区确定行/列区间，先提交已接受的原生草稿。核心遍历实际单元格和区间，不展开整张空表。

核心沿既有词法位置重写受影响的 A1 引用，保留字符串、非目标表的本地引用和范围外源片段。绝对标记只限制复制平移，行列结构变化仍移动绝对引用。相交区域扩展或缩短，全部失去目标则写入 `#REF!`；共享公式涉及结构变化时有界展开为普通公式。名称、打印区域/标题、合并、行列尺寸、冻结边界、滚动/选择位置、既有条件格式/验证范围及公式、内部链接同步更新。删除规则锚点时，先定位存活格原本使用的相对公式，再应用结构变换。完整删除的打印名称或规则移除，普通失效名称保留引用错误。

插入复制上方行或左侧列的已有尺寸与字符/单元格格式，清空新增格的值和公式，并显示新增行列；新增列取消 bestFit。首行/首列无前项时使用缺省格式。单元格、引用、计算缓存和选区合为一次源历史；撤销恢复精确包，保存重开可继续输入和输出 PDF。自动轴沿原有字体与工作量预算更新。规则依据 [ONLYOFFICE 行插入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L8313-L8369)及[列插入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L8473-L8554)。实现归 [`axis-edit.mbt`](../../modules/formats/src/xlsx/axis-edit.mbt)、[`axis-reference.mbt`](../../modules/formats/src/xlsx/axis-reference.mbt)、[`axis-cells.mbt`](../../modules/formats/src/xlsx/axis-cells.mbt)与 [`axis-metadata.mbt`](../../modules/formats/src/xlsx/axis-metadata.mbt)。

普通值、自定义、数值排名及平均值筛选随整行/整列插删同步。范围前插入移动整个筛选，范围内插入扩展矩形并重新匹配新增空行；删除缩短矩形，删除的条件列和按钮标记一起移除。手动隐藏及筛选隐藏来源随行移动；删除标题后，首个存活行成为标题并清除其筛选隐藏来源。失去全部列或数据行时移除筛选，仅保留存活的手动隐藏。嵌套标准排序范围和键沿既有结构变换维护。候选公式重算后重新应用条件，再更新 SUBTOTAL 缓存，与源和选区合为一次精确历史；范围后的操作保留既有筛选源及隐藏状态。变换后的矩形继续受 4096 格上限约束，插入不得裁掉工作表边缘的筛选端点。规则参考 [ONLYOFFICE 列筛选变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/AutoFilters.js#L2115-L2215)和[行筛选变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/AutoFilters.js#L2326-L2395)，实现归 [`filter-axis.mbt`](../../modules/formats/src/xlsx/filter-axis.mbt)。

插入会推掉实际源行、单元格或便笺时拒绝。[传统便笺](#单元格便笺)的归属已随结构事务维护。工作表保护、未知公式/引用/属性、非空扩展、未知筛选、绘图、表格、线程批注及未知便笺资源继续保护，保留文档与历史；仅锁定工作簿结构不禁止行列插删。筛选表的局部单元格移位仍受保护。四向单元格移位插删见下节；其余引用资源按 [P11](../p11-xlsx-core.md) 继续接入。

### 单元格移位插入与删除

`editSheet({ action: "insertCells", range, direction })` 支持 `down/right`；`deleteCells` 支持 `up/left`。`range` 为当前目标表中的一个 A1 矩形，最多 4096 格；已有 `sheet` 参数可指定表。上下移位只作用于该矩形的列带，左右移位只作用于其行带；数量为所选高度或宽度。默认 UI 使用现有选区并先提交已接受的原生草稿，成功后保持该矩形选择。插入格只复制上侧或左侧的有效格式，不复制内容；到达首行/首列时使用默认格式。

事务移动稀疏单元格源，保留值、公式、富文本和有效格式；移入另一行/列后仍使用原有效单元格样式。新源片段保留命名空间，原行属性与格间注释继续保留。固定行高、列宽、隐藏/轮廓及冻结分割保持坐标；普通自动尺寸继续沿已有内容重排事务更新。实际数据会被推出工作表边缘时原子拒绝，格式、生成源、输出与历史继续受既有预算约束。

普通/共享公式、跨表引用、绝对标记、定义名称、内部链接、已支持合并区域、有效范围和计算缓存共用一次源历史。相交共享公式有界展开。单个引用及完全位于移动带中的区域按插删轴调整；跨越带边界的引用通常保持，删除完全覆盖其轴区间且切到另一轴边缘时裁掉相交边。整轴引用仍覆盖工作表末端。规则依据 [ONLYOFFICE Range.isIntersectForShift/forShift](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L614-L790)和[公式移位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L10152-L10280)，不把移动当成相对复制。

既有条件格式/数据验证的 `sqref` 按移动带拆分或删除；普通公式与公式型 `cfvo` 阈值保持各格的相对、绝对和跨表引用。需要不同公式的区域分组保存，保留规则属性、源注释和命名空间；条件格式保留原优先顺序并分配唯一优先级，验证同步 `count`，与单元格共用一次精确历史。常量或全绝对公式按区间处理，不展开整列空格。相对公式每次操作最多求值 100000 个规则覆盖格、处理 4 Mi 字符，累计最多 4096 个规则片段；克隆源另受单部件与 4 Mi 字符上限约束。未知规则结构、无法解析的公式、克隆身份扩展或预算不足时原子拒绝。范围变换参考 [ONLYOFFICE 条件格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L564-L643)和[数据验证](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/DataValidation.js#L976-L1067)。

范围变换复用源规则与引用事务。普通条件格式的呈现与验证执行/编辑已接通，范围归[条件格式](#条件格式)和[数据验证](#数据验证)；未呈现效果的 PDF 继续原子拒绝。传统便笺按所选行/列带移动归属，删除目标格时同时删除文字和对应 VML 框，范围外便笺保留。移动带切开合并或矩形链接、依赖无法隔离的公式/引用、未接入的筛选/绘图/表格/线程批注资源及工作表保护继续原子拒绝。可用的整行/整列操作保持原有规则支持。保存重开后继续沿同一编辑与 PDF 路径工作；其余 [P11](../p11-xlsx-core.md) 范围仍待实现。

### 四向填充

`editSheet({ action: "fill", range, direction })` 支持 `down/up/right/left`，作用于 A1 矩形；源和目标合计最多 4096 格。向下/上以首行/末行为源，向右/左以首列/末列为源；沿填充轴只有一行/列时，源为方向相反的相邻行/列。相邻源越界时保持文档。数字直接重复，不推导序列。

核心复制类型值及有效格式，文字中的 `=` 保持文字；公式只平移相对引用，保留绝对与跨表引用，越界生成 `#REF!`。受影响共享公式有界展开。值、格式、依赖缓存和选区共用既有事务、自动尺寸及一次精确历史；保存重开后可继续编辑。复制文字和公式源码累计最多 1 Mi 字符，单公式最多 8192 字符，候选、源和历史仍受既有预算约束。

源或目标相交条件格式、验证或链接时拒绝填充；传统便笺保留各格原有文字与框，不随源复制，见[单元格便笺](#单元格便笺)；合并几何见下段；未知扩展、表格/透视和线程批注继续保护。范围外规则与元数据保留。默认按钮使用当前选区，沿既有队列提交原生草稿。核心已检查四向、相邻边界、类型值、有效格式、共享公式、重算、精确历史、重开及原子失败；Chromium 已检查四向按钮、原生草稿、独立公式/样式/缓存源、混合历史、保存重开和 PDF。重新打包的参数检查与严格宿主调用通过。数字序列见[数字序列](#数字序列)，基本拖动与键盘操作见[填充柄](#填充柄)。来源选择参考 [ONLYOFFICE prepareFillHandle](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L27533-L27590)，实现归 [`fill.mbt`](../../modules/formats/src/xlsx/fill.mbt)。

#### 合并格填充

四向按钮以起始行/列为源；若该边穿过合并格，核心沿填充轴扩至完整源块。值、公式和各格有效格式按该源块循环，合并区域一起平铺到目标。尾块不足源尺寸时裁到目标边界；裁成单格时保持普通格，不写单格合并。自动/文本/数字趋势沿现有源槽位和实际格位置推导；仅被合并覆盖而没有锚点的数字序列行/列循环源值和格式。显式日期模式每行/列仍只接收一个数字种子，可由一个完整合并格承载，按合并跨度推进日期。

源和已有目标合并必须完整包含，不能切开；目标几何已等于源平铺结果时可重复填充。需要替换其他目标合并时，源与目标须由同尺寸合并格完整平铺，否则原子拒绝。未知合并元数据继续保护，范围外节点、注释和未改部件保留。填充复制各物理格的值和格式，不执行另一次合并命令的丢弃策略。

单个合并锚点可作为序列和填充柄的完整源。预览的 `source` 保留原选择地址，`range` 使用核心合并边界；宿主沿核心返回的单元格几何放置填充柄。Ctrl、四向方向键、拖动及源内合并的相邻延伸复用同一事务。向内清除仅清完整合并区域的内容，保留合并和格式；切开合并的清除拒绝。相邻区域中源外的合并向导仍待支持。

值、公式缓存、合并几何和选区先在候选中校验，再提交一次精确历史；仅几何变化也可撤销。沿用 4096 个受影响物理格、1024 个工作表合并区域、内容/公式和输出/历史预算，失败保持源、选择和历史。保存重开继续编辑，网格和 PDF 使用同一合并几何；跨打印页边界的合并仍遵守既有 `print-overflow` 保护。

尺寸保护和平铺参考 [ONLYOFFICE 合并填充](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21799-L21920)及[尾块裁短](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22594-L22616)，四向和趋势结果核对其[独立合并用例](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/SerialTests.js#L5006-L5210)。实现归 [`fill-merge.mbt`](../../modules/formats/src/xlsx/fill-merge.mbt)、[`fill.mbt`](../../modules/formats/src/xlsx/fill.mbt)与 [`cell-transaction.mbt`](../../modules/formats/src/xlsx/cell-transaction.mbt)，不新增公开 API。

#### 本地化文本循环

`auto` 在核心识别九组常用文字表：英文星期与月份的全称/缩写、`星期日`–`星期六`、`周日`–`周六`、`週日`–`週六`、`一月`–`十二月` 和 `1月`–`12月`。按源文字识别，不依赖浏览器或界面语言。`May` 同时属于月全称和缩写时，优先采用相邻源格的同类表；单独出现时使用全称。匹配忽略大小写、两端空白和末尾句点，源格原文仍保留。

同类文字转成循环索引后沿既有整数趋势推导，跨周/月/年边界延续，四向填充自然反推。单值按一个位置推进，多值可推导跳项；非整数趋势沿文本模式重复源。常量、规则空白槽位和不同类别的独立分组复用原逻辑。目标仍循环采用对应源格的格式和大小写风格：前两字母全大写时输出大写，首字母大写时输出首字母大写，其余输出小写；中文文字保持不变。

仅字面文字参与识别。公式缓存中的星期/月名继续按公式平移，带数字后缀的其他文字仍按文本编号推导；数字与数值日期沿既有路径处理。显式 `text` 模式不使用这些词表，Ctrl 及 `copy` 继续循环复制。按钮、拖动/方向键和相邻区域延伸共用该推导与一次精确历史，保存重开和 PDF 使用生成的文字。不增加新 API 或语言配置；其他语言、别名和用户自定义循环表尚未接入。

词表、大小写及相邻源消歧参考 [ONLYOFFICE 时间名称自动填充](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22051-L22165)及 [中文文化数据](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/NumFormat.js#L6090-L6120)。循环的展开/反推复用本项目整数趋势；实现归 [`series-cycle.mbt`](../../modules/formats/src/xlsx/series-cycle.mbt)与 [`series-text.mbt`](../../modules/formats/src/xlsx/series-text.mbt)。

### 填充柄

普通网格在选区末格显示填充柄；RTL 使用左下角。拖动向外扩展一条行带或列带，核心按物理距离选择轴。向内拖动选择要清除的末尾行带或列带，只清内容和公式并保留格式；边界按命中格的半格位置吸附，角点附近未越过边界时无操作。拖到源起点可清空整块内容。聚焦填充柄后，方向键延伸一行或一列，左右键遵循 RTL 的物理方向。支持缩放、冻结窗格和边缘滚动。Ctrl 将向外填充切换为循环复制；单个普通数值改为逐格加一。日期/时间、文字及公式按源模式复制，公式仍平移相对引用。拖动中按下或松开 Ctrl 即可切换，释放使用当时的状态；方向键也支持 Ctrl。向内清除规则不变。双击填充柄，或聚焦后按 Enter/Space，按相邻连续区域向下自动填充。下方首行全部有内容时延伸至首个缺格行之前；部分有内容时不操作；全空时从左右及对角相连的区域推导末行，并停在目标列下一处内容之前。样式空格不延长区域，隐藏行仍参与推导；相邻筛选区域不能借作跨区向导。源内的完整合并可沿填充事务复制；源外参与推导的合并向导仍明确拒绝。没有可延伸范围时不增加修订或历史。

`XlsxSession/XlsxClient.fillPreview(layoutId, target)` 接受 `{ kind: "point", x, y }`、`{ kind: "direction", direction }` 或 `{ kind: "adjacent" }`。三种 target 都接受可选布尔字段 `ctrl`，默认 false。核心返回 `source/range/direction/mode/geometry/end`。Ctrl 向外操作返回 `mode=copy` 或单个普通数字的 `mode=linear`，range 与自动向外操作相同。`mode=auto` 的 range 是源与向外目标的并集，`mode=shrink` 的 range 是待清尾带；geometry 显示此操作区域，end 定位提交后的末格。预览不改文档、选区、revision 或历史。过期布局、非法目标和超过 4096 格的范围拒绝。宿主只发送指针与键盘意图，范围和冻结裁剪由核心计算。

原生草稿先独立提交，再恢复拖动前的源范围。预览不写源；释放时按预览的自动、复制、线性或缩减模式执行一次事务，后续保存排在该操作之后。未释放时，Escape、失焦、指针取消、暂停和销毁取消拖动。相交规则、链接及其他资源沿用填充保护，合并源沿下述几何规则处理；失败保持源和历史。含未渲染超链接的工作表仍按既有规则拒绝 PDF 导出。

`editSheet({ action: "series", mode: "shrink", source, range, direction })` 提供同一缩减操作。source 是原选区，range 必须是其中完整的末尾行带（direction=up）或末尾列带（direction=left），原范围限 4096 格。保留左上区域成为选区；全清时仍选择原范围。没有内容可清时仅调整选区，不新增 revision 或历史。共享公式展开和依赖缓存复用已有单元格事务；其他单元格、行列尺寸及源元信息保持。规则依据 [ONLYOFFICE canPromote](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21961-L22003)及[缩减仅清内容](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22296-L22303)，实现归 [`fill-shrink.mbt`](../../modules/formats/src/xlsx/fill-shrink.mbt)。

`editSheet` 的 `series` 支持 `mode=copy`，循环复制源值及格式并平移公式相对引用。Ctrl 规则参考 [ONLYOFFICE 数值切换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22408-L22421)。

双击范围依据 [ONLYOFFICE applyFillHandleDoubleClick](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L15248-L15306)及[连续区域扩展](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L4528-L4783)。实现归 [`fill-adjacent.mbt`](../../modules/formats/src/xlsx/fill-adjacent.mbt)，以非空行列索引查询边界，避免逐格扫描稀疏工作表；最终范围继续受 4096 格限制。

方向选择参考 [ONLYOFFICE changeSelectionFillHandle](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L14754-L14825)，未复制上游代码。实现归 [`fill-preview.mbt`](../../modules/formats/src/xlsx/fill-preview.mbt) 和 [`spreadsheet-pointer.ts`](../../packages/web/src/spreadsheet-pointer.ts)。

### 数字序列

`editSheet({ action: "series", mode, source, range, direction })` 的缩减模式见[填充柄](#填充柄)。生成序列时，从显式源矩形填充序列，`mode` 为 `linear`、`growth`、`date`、`text` 或 `auto`，`direction` 支持四个方向。日期模式另需 `unit` 和 `step`，其他模式拒绝这两个字段。核心使用 `SeriesMode.Linear/Growth/Date(unit, step)/TextSeries/Automatic`。`range` 包含源和全部目标，最多 4096 格；源须占据方向起始边，且完整覆盖垂直方向的列带或水平方向的行带。源与目标相同时为无操作。

各列/行独立使用源数字和实际位置拟合趋势，保留全部种子；空白不参与拟合，也不压缩其位置。每条序列至少有一个字面数字。线性模式按最小二乘拟合，单值种子的步长为 1，向上/左自然反推。增长模式对正数取自然对数后拟合，再还原指数值；单值或恒定种子保持原值。公式、文字、布尔及错误种子明确拒绝，增长模式另拒绝零和负数。两种模式均支持非等差样本及四向外推。

目标沿用该行/列首个数字种子的有效格式，写入数字并同步依赖缓存。增长计算在对数域合成，避免先指数溢出再缩放；非有限结果原子拒绝，极小结果沿 IEEE 754 下溢为零。行为及格式来源参考 [ONLYOFFICE 数字取对数与趋势拟合](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L24917-L25039)，未复制上游代码。

日期模式每条序列使用一个字面数字种子；垂直源为一行，水平源为一列，可同时填充多条。`unit` 为 `day/weekday/month/year`，`step` 为有限数字，绝对值不超过 2958465；仅天允许小数，其余单位使用整数，零复制原值。向下/右按步长前进，向上/左反向，负步长反转。核心使用工作簿的 1900/1904 日期系统，保留时间小数；结果须在序列零点至 9999-12-31 当日内。1900 系统保留序列 60 的虚构闰日。工作日跳过周六、周日，不含节假日；按整周及有界余数计算，避免大步长逐天遍历。月序列按原日号截到目标月末，后续月份恢复原日号；年序列按上游规则把非闰年的 2 月 29 日进位至 3 月 1 日，再沿该日期继续。规则参考 [ONLYOFFICE 日期序列](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L24665-L24757)及 [cDate 年月变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L4063-L4075)；小数时间按本项目日期值模型保留，不采用上游的整数日期截断。

文本模式接受字面文本或空白。按填充方向把相邻同前缀的 ASCII 数字后缀分组；不同前缀或非空普通文字结束当前组。每组独立拟合整数截距和步长，单值向下/右步长为 1，向上/左为 -1。组与普通文字沿源槽位循环。保留前缀，采用该序列最长的前导零宽度；超出宽度时自然增长。向上/左反推，跨零后按上游取绝对值。纯数字文本仍输出文本，各目标循环采用对应源格的有效格式。规则空白间隔且数值等差时，按种子顺序拟合并保留空白槽位；间隔或差值不规则时，按实际位置拟合，整数趋势同时填入组内空白槽位。源中的空白保持原样，生成值保持文本类型及对应源格格式。纯文本和非整数趋势重复原值，本地化星期/月名由自动模式推导。后缀及结果限于精确整数范围 0–9007199254740991，单格最多 32767 UTF-16 单位；单条序列处理的内容和全部生成内容各限 1 Mi 单位，超过预算原子拒绝。大编号先减去首值再拟合，避免均值抹去相邻整数差。后缀、补零和跨零规则参考 [ONLYOFFICE 文本填充](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22360-L22385)、[整数趋势与最长补零](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L23185-L23334)及 [跨零处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L23447-L23453)。未复制上游代码。

自动模式按源槽位同时处理数字、文本和公式。数字与文字前缀分别分组；数字可使用小数趋势，单格数字源复制原值，多格源中的单个数字组按 1 或 -1 延续。文字沿文本分组规则推导，布尔、错误和普通文字按原类型重复。公式分隔相邻组，再按对应源格平移相对引用；绝对引用不动，越界引用写为 `#REF!`。所有目标循环复制对应源格的有效格式，源格保持原样，填充与依赖重算合为一次历史；公式与文本共用 1 Mi 单位预算，单条公式最多 8192 单位。数字的非有限结果原子拒绝。自动模式也按既有数字格式识别日期、日期时间与时间，规则见下段；指定日期单位和步长仍使用显式 `date` 模式。本模式复用已有趋势、文本分组和公式平移；[`series-auto.mbt`](../../modules/formats/src/xlsx/series-auto.mbt) 负责合成，不增加计算服务。

默认面板提供序列开关、线性/增长/日期/文本/自动模式、日期单位和步长、源范围输入及使用当前选区的按钮；随后选择包含源的完整目标，再用四向填充按钮执行。更换工作表后须重新指定源，重开文档恢复普通填充模式。原生草稿先独立提交，填充复用同一共享公式展开、自动适配、重算、保存及精确历史；无值、格式或合并几何变化时不新增 revision。有限数值或日期计算失败、被切开的合并及既有填充资源保护均原子拒绝。手动隐藏行列按实际位置参与；相交的已启用筛选保护，后续再接可见格序列。规则资源复制仍按 P11 实施。文本实现归 [`series-text.mbt`](../../modules/formats/src/xlsx/series-text.mbt)，共用实现归 [`series.mbt`](../../modules/formats/src/xlsx/series.mbt)和 [`series-date.mbt`](../../modules/formats/src/xlsx/series-date.mbt)。

自动日期使用源格的有效数字格式，日期组与普通数字组分开。纯日期按整数天拟合，常量或非整数趋势循环源值；单日期按方向延续一天。同一日号且日历间隔为整数时，推导月序列；月份也相同时可推导年序列。月份截到月末后恢复原日号，年份沿既有闰日进位规则。规则空白保留槽位，不规则空白参与实际位置推导。源日期、时间小数及格式保持原样，各目标循环源格格式。

日期时间保留数值时间差；月/年模式分别推进日历与时间差，避免时刻越过午夜后改变后续月份。混合日期和日期时间使用整数日期趋势及首个日期时间格的固定时间部分。不形成有效日期趋势时重复源模式；同日但不一致的小数时间趋势按上游规则保持起始时刻。单时间按一小时推进，多时间拟合小数天，反向越过午夜时回到当天时刻。日期仍使用工作簿的 1900/1904 系统；非法源或超出日历范围的结果整项拒绝，包括其他组已推导出候选值的情况。工作日仍由显式日期模式指定，不自动猜测节假日或工作日序列。

识别与拟合参考 [ONLYOFFICE 日期/时间自动填充](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L23237-L23346)及[月/年识别](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L23607-L23633)。实现归 [`series-calendar.mbt`](../../modules/formats/src/xlsx/series-calendar.mbt)，复用已有日期步进和填充事务，未复制上游代码。

### 区域排序

`editSheet({ action: "sort", range, rows, header, caseSensitive, keys })` 对最多 4096 格的显式 A1 矩形排序。`rows=true` 按行重排，键 `index` 是工作表从 1 开始的列号；`rows=false` 按列重排，键为行号。`keys` 为 1–16 个互异条件 `{ index, descending, customList?, sortBy?, color? }`，索引必须在范围内，按数组顺序比较。三个布尔字段必须显式提供，`header=true` 保留所选范围的第一行或第一列。默认面板使用当前选区，提供方向、标题、大小写、增删多键、每键自定义列表及颜色依据。`XlsxSortSettings/XlsxSortKey` 从 Wasm/Web XLSX 模块导出。

核心冻结排序前的当前键值，不用导入缓存代替未计算公式。数值及可解析为有限十进制数的文字键按数字比较，保留原单元格类型；布尔和错误按显示文字参与文字比较。空格与空串不同；空单元格和空串结果在升降序中均置后。相同键按原行列顺序稳定排列。`caseSensitive=false` 使用固定 Unicode 16 大写映射，文字按 UTF-16 字符序比较，不使用 MoonBit 默认的长度优先比较；语言区域校对顺序仍待兼容扩展。隐藏行或列的位置、内容与手动隐藏状态保留，不参加对应方向的置换。普通比较、隐藏位置和多键路径参考 [ONLYOFFICE _getSortElems](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21327-L21649)；该上游的 localeCompare 与本期固定字符序不同。

每个值键可选 `customList: string[]`，缺省或空数组使用普通排序。非空列表按给定顺序定义文字优先级，各键可使用不同列表。沿既有归一化，数字及数字文字继续按数值比较，布尔和错误按显示文字参与匹配。列表先精确匹配原文字，未命中时使用固定 Unicode 大写映射查找列表中的第一项；仅大小写不同的标签可以分别列出，精确命中保留各自顺序。此列表匹配规则不受 `caseSensitive` 改变，该选项继续控制未列出文字的普通比较。升序时列出项排在未列出文字之前，未列出项按普通顺序比较；降序反转文字比较结果，空单元格和空串仍排在末尾。相同优先级继续比较后续键，再保持源顺序。

每份列表最多 4096 项，逗号连接后的长度最多 32767 UTF-16 单元。标签必须互不相同且非空，前后空格保持，不能包含逗号、回车或换行。引号、制表符及看似 OOXML 转义的文字通过既有文字编码保存；原始和编码后的列表载荷另受 1 Mi 单元预算约束，失败不提交。默认面板按键提供每行一项的输入，留空恢复普通排序。核心 `SortKey.custom_list` 使用空数组表示普通顺序；TS 的 `customList` 可省略。列表与单元格、排序状态、筛选和缓存合为同一项历史，不另建应用级自定义列表目录。

已检查 ONLYOFFICE 的上述排序路径，其文字分支没有自定义列表比较。因此文字优先级参考下一顺位的 [LibreOffice GetSubIndex/Compare](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/tool/userlist.cxx#L60-L142)与[文字键排序入口](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/data/table3.cxx#L1534-L1585)。实际大小写映射和未列出项排序继续采用本项目的固定规则，不执行地区化校对。每键顺序写入标准 `sortCondition@customList`，导入、无关编辑、工作表复制/改名及既有排序状态引用维护保留它；实现归 [`sort-list.mbt`](../../modules/formats/src/xlsx/sort-list.mbt)。

`sortBy` 缺省或为 `value` 时按值比较；`cellColor` 按填充色，`fontColor` 按单元格字体色。颜色键必须给出 `color`，使用六位 RGB 十六进制文字；填充色的空串表示无填充，与白色不同。颜色键不能同时使用非空自定义列表，值键不能指定非空颜色。同一轴可设置不同颜色或依据，例如先红色、再绿色，最后按该列数值；完全重复的条件仍拒绝。`descending=false` 把命中色放在前面，`true` 放在后面，同组继续比较后续键，再保持原顺序。空内容格也按其有效颜色参加此分组；隐藏行列继续保留位置。

颜色取自排序前的有效样式，包含已支持条件格式及主题/索引颜色的解析。核心冻结颜色匹配结果，再使用原有单元格置换；条件规则仍留原范围，排序后重新求色，依赖位置的规则可能改变最终颜色。默认面板提供依据、RGB 输入、无填充及命中色位置。颜色条件写标准 `sortBy` 与 `dxfId`，一次批量复用或新增差异样式；首次样式部件也与数据、关系和历史一起提交。原有规则和样式身份保持，颜色引用缺失时拒绝重排或引用相关的表操作。富文本文字色和图标排序仍受保护，未知样式效果不猜测颜色。

有效样式冻结及按命中色分组参考 [ONLYOFFICE _getSortElems/colorFillCmp](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21427-L21600)，`dxfId` 存储参考 [CSortCondition](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/XlsxFormat/Table/Autofilter.cpp#L96-L106)。实现归 [`sort-color.mbt`](../../modules/formats/src/xlsx/sort-color.mbt)，差异样式复用 [`conditional-style-edit.mbt`](../../modules/formats/src/xlsx/conditional-style-edit.mbt)，没有新增绘制模型或复制上游源码。

排序移动单元格值、富文本 XML、有效样式及已支持公式，局部补齐命名空间，保留源格式。公式相对引用按实际位移平移，绝对引用保持，越界生成 `#REF!`；受影响共享组有界展开。区域外公式引用继续指向原坐标，并按排序后的内容重算。单格超链接随内容移动，矩形链接保持原坐标，关系和目标不变。条件格式、验证及名称保持原坐标范围，效果和输入约束基于候选值计算；验证失败整项拒绝。行列尺寸保留原位置，已有自动尺寸仍按新内容重排。公式、依赖缓存与值/源/链接使用同一有界历史，精确撤销/重做，保存重开及 PDF 使用已排序内容；原生草稿先独立提交。恒等置换不新增 revision 或历史。重排及公式位移参考 [ONLYOFFICE _sortByArray](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21651-L21770)。

已有普通值/自定义筛选的工作表也使用相同排序入口和显式范围。核心先按排序前的可见性冻结参加坐标；行排序保留手动及筛选隐藏记录的位置，列排序保留隐藏列位置。筛选范围、条件及按钮属性保持原坐标，不随单元格移动。候选值、格式和公式生成后，重新应用筛选，保留原手动隐藏来源，并重算依赖可见性的 SUBTOTAL 缓存；排序后可见行可因当前位置的公式结果而变化。单格链接和便笺沿内容移动，区域外源保持。单元格、筛选掩码、公式缓存与选区共同提交一次精确历史；恒等置换不新增历史。默认排序面板沿相同原生草稿屏障执行，保存重开保留当前顺序和筛选；清除条件只恢复筛选隐藏。

实际发生置换时，核心把范围、键顺序、升降序、行/列方向和大小写选项保存为标准 `sortState`，与内容和筛选共用一次历史。`ref` 排除显式标题；值键写 `sortBy="value"`，颜色键写相应依据与差异样式引用，固定字符序写 `sortMethod="none"`。排序范围位于已有筛选内时写入该筛选，否则写入工作表；另一位置的历史排序设置保持。恒等置换不改排序信息或历史。导入可保留合法空状态及最多 64 个不同排序条件及其自定义文字顺序；同轴颜色条件按依据和差异样式引用区分，`none`/`pinYin`/`stroke` 标志在无关修改和筛选重新应用时保留源内容；这不表示执行地区化排序。新命令仍限 16 键。工作表改名、复制与重开保留设置；工作表级排序信息随整行列及完整覆盖排序区域的单元格移位同步范围和键引用，删除键时移除该键，失去全部键时移除状态。只跨过排序区域一部分的移位保留上次排序记录。清除筛选条件保留其排序信息；新筛选范围不能容纳旧排序范围时移除旧信息，移除筛选也移除其排序信息。其他位置和未知源保持。

上述存储和引用维护参考 [ONLYOFFICE SortState](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L9742-L10000)、[OOXML 排序定义](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/Test/Applications/DocxFormatCodeGen/codegen/Resource/sml.xsd#L148-L182)及[写入代码](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/XlsxFormat/Table/Autofilter.cpp#L320-L352)，没有复制上游源码。

排序键归一化共享 1048576 次公式工作预算，移动片段累计最多 1 Mi UTF-16，继续使用公式、候选、源和 4 MiB 历史上限。合并区域、未知筛选/排序元数据、图标排序状态、绘图、结构化表/透视、线程批注及未知便笺、未知资源或关系、未知单元格/公式标记和工作表保护继续原子拒绝。更广合并/资源支持归 [P11](../p11-xlsx-core.md) 后续范围。实现归 [`sort.mbt`](../../modules/formats/src/xlsx/sort.mbt)、[`sort-state.mbt`](../../modules/formats/src/xlsx/sort-state.mbt)、[`sort-source.mbt`](../../modules/formats/src/xlsx/sort-source.mbt)、[`reorder-cells.mbt`](../../modules/formats/src/xlsx/reorder-cells.mbt)及 [`xlsx-sort.tsx`](../../packages/ui/src/xlsx-sort.tsx)。

### 文本分列

`XlsxSession/Client.textColumns(revision, sheet, settings)` 返回只读预览，宿主入口为 `SpreadsheetEditor.textColumns(settings)`。`XlsxTextColumnSettings` 包含同列 A1 范围 `range`，以及二选一的分隔符 `delimiter` 或固定宽度位置 `breaks`；不能同时提供。分隔符支持逗号、分号、空格及制表符。可选 `types` 指定每列转换，`formulas` 默认关闭。返回 `XlsxTextColumns`，含归一化设置、revision、sheet、`resultRange`、原始字段数 `splitColumns`、实际输出列数 `columns`、将覆盖的非空单元格数 `overwrittenCells` 和转换后的前十行 `preview`。设置、预览及 `XlsxTextColumnType` 从 Wasm/Web XLSX 模块导出。MoonBit 的 `TextColumnSettings.split` 使用 `Delimited(String)` 或 `Fixed(Array[Int])`，`types=[]` 表示全部文字。预览不改源、选择或历史；原生草稿和组合屏障沿既有宿主队列处理。

提交使用 `editSheet({ action: "textToColumns", settings, sourceRevision, overwrite })`。源列的编辑值从选区左上角向右拆分，包含隐藏行；公式使用带 `=` 的编辑文字，普通数值使用原值文字，不使用格式化显示或导入缓存。分隔符模式中，双引号包围字段内的分隔符保持，两个连续引号还原为一个；连续/末尾分隔符产生空字段，短行补空至最大列数。保留单元格内的换行，不把它扩成额外工作表行。默认全部写为文字，前导零和公式样式文字保持。空字段清空对应内容，单元格格式、链接、便笺和行隐藏状态保持原坐标；条件/验证范围也保持。

`types` 非空时必须覆盖全部原始字段。`text` 保留文字，`general` 复用现有数字及布尔解析；只有常规列且明确选择 `formulas=true` 才解析公式，无法计算的公式拒绝整项操作。`ymd`、`mdy`、`dmy` 分别按明确年月日顺序转换，要求四位年及数字日期，接受 `/`、`-`、`.` 和既有时间解析。无效日期保留原文；有效日期使用工作簿 1900/1904 日历，并设置 `yyyy-mm-dd` 或 `yyyy-mm-dd hh:mm:ss`，其余样式保持。`skip` 丢弃该字段，其余字段向左紧排；必须保留至少一列，实际输出矩形之外保持原样。默认面板先预览，再逐列选择类型，公式另有勾选项；候选日期、计算值和格式与提交一致。地区化数字、月份名称及任意日期格式不在当前范围。

固定宽度使用 1–4095 个严格递增的整数位置，范围为 1–65534；`breaks: [3,7]` 依次取宽 3、宽 4 和余下文字，始终输出三列。宽度复用 Unicode 16 的 W/F 两列、其余默认一列及默认可忽略字符零列的顺序；不是字体像素宽度。沿现有字素分段整体推进，宽字符或组合簇跨过指定位置时整体留在当前段，不拆代理对或字素；随后按下一段宽度继续。忽略簇附在前段末尾，短行补空。每段仅裁掉尾部 ASCII 空格，再移除成对外层双引号；内部引号、分隔符及前导空格保持。固定模式不执行分隔符引号解析。默认面板提供方式切换及位置输入；无效位置阻止预览，修改方式或位置会清除旧预览和覆盖确认。

原源列之外的非空目标值或公式计入覆盖数量，仅带格式的空单元格不计入。核心重算方案并复核 sourceRevision；需要覆盖时，只有 `overwrite=true` 才提交。默认面板先显示输出矩形、数量和前十行，再要求勾选覆盖并明确提交。设置、选区、表、文档或修订变化使旧预览失效。目标写入、日期样式及首次样式部件、公式依赖缓存、验证及自动适配共用已有单元格事务和一次精确历史；无实际变化不新增历史。保存重开与静态 PDF 使用同一结果。

源最多 4096 行，原始字段矩形和实际输出矩形均最多 4096 格，实际输出不能越过 XFD 列；输入累计最多 1 Mi UTF-16，每格最多 32767 单元，并受原包、XML、输出和 4 MiB 历史预算约束。分隔符模式的错误引号、非法固定位置、合并格、富文本等既有只读单元格、工作表保护、不透明公式/元数据或验证失败原子拒绝。CSV/TSV 文件导入仍只接受逗号或制表符，原转换选项保持。更广地区化转换和格式组合继续实施。

功能入口参考 GenOffice 单列分列操作，编辑值与文本粘贴事务参考固定 [ONLYOFFICE asc_TextToColumns](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/api.js#L846-L902)及 [getRangeText](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L23563-L23594)。固定宽度参考 [LibreOffice 列宽推进](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/ui/docshell/impex.cxx#L529-L557)、[段落提取](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/ui/docshell/impex.cxx#L1490-L1534)及[分列事务](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/ui/docshell/impex.cxx#L1641-L1689)，补齐字素完整性。本实现默认保留文字，转换需要明确选择，不声称覆盖完整文本导入向导；未复制上游源码。实现归 [`text-columns.mbt`](../../modules/formats/src/xlsx/text-columns.mbt)、[`text-columns-convert.mbt`](../../modules/formats/src/xlsx/text-columns-convert.mbt)、[`text-columns-fixed.mbt`](../../modules/formats/src/xlsx/text-columns-fixed.mbt)、既有 [`delimited.mbt`](../../modules/formats/src/xlsx/delimited.mbt)和 [`xlsx-text-columns.tsx`](../../packages/ui/src/xlsx-text-columns.tsx)。

### 删除重复行

`XlsxSession/Client.duplicates(revision, sheet, settings)` 返回只读预览，宿主入口为 `SpreadsheetEditor.duplicates(settings)`。`XlsxDuplicateSettings` 包含显式 A1 矩形 `range`、`header` 和工作表从 1 开始的比较列 `columns`；至少选一列，各列互异且在范围内。`header=true` 保留首行。返回 `XlsxDuplicates`，包含同一设置、revision、sheet、完整 `keptRows/removedRows`、有效结果 `resultRange` 及前十条保留记录的格式化值 `preview`。两个类型从 Wasm/Web XLSX 模块导出。核心预览不修改源、选择、修订或历史；宿主沿既有队列先处理原生草稿和组合输入。

提交使用 `editSheet({ action: "removeDuplicates", settings, sourceRevision })`。默认面板先选择比较列和标题，再预览删除数量、原行号及保留内容，最后明确提交。设置、选区、表或修订变化后旧预览不能提交；换文档须丢弃旧结果。核心重新计算方案并核对 sourceRevision，不信任传入的删除行列表。无重复或候选源没有实际变化时不新增历史。

比较使用当前已计算结果和格式化文字，区分大小写及空格；显示相同的数字与文字可匹配，不因底层类型不同而保留两份。保留首次出现的记录，包含手动隐藏行。存活单元格按原顺序向区域顶部压紧，移动值、富文本源、有效格式及相对公式；绝对引用和区域外引用坐标保持，依赖缓存同步重算。清空尾部内容及显式单元格格式，行列继承格式仍有效，不删除整张表的物理行，也不移动选区外单元格。手动尺寸和隐藏状态保留原坐标，自动尺寸沿现有路径重排。条件格式、验证及名称保留坐标，候选输入继续校验。

单格链接和便笺随保留记录移动。删除重复记录时，同步移除对应便笺/VML 和完整落在该选区删除行内的链接；跨行链接保持原坐标。其他部件及源片段保留，值、公式、样式、链接、便笺和缓存合为一次精确历史；撤销、重开后输入、查找替换及 PDF 沿相同内容路径。一次最多 4096 格，格式化及条件计算共享 1048576 工作预算，搬移片段累计最多 1 Mi UTF-16，继续遵守输出和 4 MiB 历史上限。合并格、排序状态、表格/透视、绘图、未知便笺及单元格/公式元数据等沿重排保护原子拒绝；这些组合继续实施。

已有普通值/自定义筛选时，去重比较仍包含筛选隐藏行，保留首条记录。筛选范围、条件和已知按钮标记保留；按压紧后的当前公式结果重新应用条件，重写筛选隐藏来源和实际行可见性，手动隐藏继续保留原行号。SUBTOTAL 及依赖缓存随可见性一起重算。整个过程只有一次历史；重开后清除条件仍只恢复筛选隐藏行。未知筛选条件或不透明源原子拒绝，导入隐藏来源的歧义沿[值筛选](#值筛选)处理。

比较和稳定压紧依据 [ONLYOFFICE setRemoveDuplicates](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L25977-L26181)、[清空单元格](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21142-L21166)及前述 `_sortByArray`；未复制上游源码。实现归 [`duplicates.mbt`](../../modules/formats/src/xlsx/duplicates.mbt)、[`reorder-cells.mbt`](../../modules/formats/src/xlsx/reorder-cells.mbt)及 [`xlsx-duplicates.tsx`](../../packages/ui/src/xlsx-duplicates.tsx)。其余数据工具继续按 [P11](../p11-xlsx-core.md) 实施。

### 值筛选

`editSheet({ action: "filter", range, columns })` 设置普通工作表的值、日期组、自定义、数值排名或平均值筛选。`range` 是含标题首行、至少一行数据且最多 4096 格的 A1 矩形。`columns` 最多含 256 个互异的 值条件 `{ kind: "values", column, values, blank }` 、自定义条件 `{ kind: "custom", column, conditions, all }` 、排名条件 `{ kind: "rank", column, value, top, percent }` 、平均值条件 `{ kind: "average", column, above }` 或日期组条件 `{ kind: "dates", column, groups, values, blank }`；`column` 是范围内从 1 开始的工作表列号，`values` 是最多 4096 项互异文字，`blank` 显式决定空白是否通过。各列取交集，同列文字取并集；空条件数组显示全部数据并保留筛选范围。文字按当前已计算值和已支持的有效格式（含条件格式）显示，去除两端空白后使用固定 Unicode 16 小写映射匹配；不改变单元格类型、值、样式、公式或记录位置。未计算公式不使用导入缓存代替。普通文字匹配参考 [ONLYOFFICE Filters.isHideValue](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L10785-L10805)和 [AutoFilter.setRowHidden](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L9585-L9640)。日期组、数值排名与平均值条件见下文；颜色/日期类动态及高级筛选继续保护。

自定义筛选的 `conditions` 含一至两个 `{ operator, value }`，`all` 为 `true` 时取 AND，`false` 时取 OR。`operator` 接受标准 `equal/notEqual/greaterThan/greaterThanOrEqual/lessThan/lessThanOrEqual`，`value` 为最多 32767 单元的文字。有限数字文字按当前数值比较，包含可转换的数值文字单元格，不使用四舍五入后的显示值或导入公式缓存；空白不当作零。其他条件按去除两端空白和相同大小写映射后的标签比较，数值单元格不参与文字匹配；等于/不等于支持 `*`、`?` 和 `~` 转义，`?` 对应一个 UTF-16 单元。空文字等于可匹配空白/公式空串。比较符必须放在 `operator`，条件值内的 `<`/`>` 不被重新解析。自定义日期比较使用数值序号；日历前缀使用下节日期组，本地化解析继续实施。双条件和数值/文字分流参考 [ONLYOFFICE CustomFilters/CustomFilter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L11130-L11456)，文字/通配符复用已有有界条件匹配。

同一列仅有一类条件，值、日期组、自定义、排名和平均值面板相互替换，其他列保留并继续取交集。`query.filter.columns` 返回相同带 `kind` 的联合类型；日期组、自定义、排名和平均值列的值目录不投影条件结果，值选择初始为全部，应用后切换为值条件。默认面板支持比较符、条件值、第二条件及 AND/OR。MoonBit 使用 `FilterColumn { column, rule }` 和 `FilterRule::Values/Dates/Custom/Rank/Average`；Wasm/Web 另导出 `XlsxFilterColumn/XlsxCustomFilter/XlsxFilterCondition/XlsxFilterOperator`。

`filterClear` 清除全部条件并保留范围，`filterRemove` 同时移除范围，`filterReapply` 按当前值重新应用。原生输入先按原队列提交；普通编辑保留现有隐藏结果，由重新应用更新。每项使用已有 revision 和单项源历史，保持选择；相同结果不新增历史。网格、自动尺寸及 PDF 共用核心隐藏行。`query.filter` 提供 `range/columns/reason` 和逐列 `catalog`；每列返回 `column/title/blank/blankSelected` 及 `{ value, count, selected }` 选项，按归一化值合并大小写，保留当前条件中的零计数值。默认面板使用当前选区创建范围，选择列和值、空白，并提供清除、移除和重新应用。Wasm/Web 导出 `XlsxFilterSettings/XlsxFilterValues/XlsxFilterState`。

保存使用标准 `autoFilter/filterColumn/filters/filter` 或 `customFilters/customFilter`（`and` 与 `operator/val`）、`sheetPr.filterMode` 和行 `hidden`。行高、原属性与非目标部件保留。`autoFilter/extLst` 内的 `urn:open-document:xlsx:filter-state` 扩展记录 `manual` 与 `filtered` 行号，可同时包含同一行；清除筛选只恢复筛选隐藏，手动隐藏继续保留。已有行高/隐藏命令同步手动来源，正行高也不能展开仍被筛选隐藏的行。复制、改名、撤销重做和保存重开保留此来源；扩展与实际隐藏行不一致时拒绝编辑。外部文件只有一个 `hidden` 字段，无法判断同一行是否同时被手动和筛选隐藏；无来源扩展时，将不匹配条件的隐藏行视为筛选隐藏，其余视为手动隐藏。外部程序若丢弃扩展，也会恢复此导入限制。

每项匹配/目录共用 1048576 次公式工作预算，条件文字累计最多 1048576 个 UTF-16 单元，目录数据/标题累计最多 1048576 个单元；继续受包、源和 4 MiB 历史预算约束。未知条件、日历声明、扩展、属性、筛选内注释/处理指令、工作表保护或无法计算的显示值拒绝修改，保留源与历史。保留已知 `hiddenButton/showButton` 标记。已支持条件的排序和整行/整列插删复用候选重算与隐藏来源事务，局部单元格移位仍保护；表格筛选、标题下拉箭头和更广组合按 [P11](../p11-xlsx-core.md) 继续接入。实现归 [`filter-model.mbt`](../../modules/formats/src/xlsx/filter-model.mbt)、[`filter-values.mbt`](../../modules/formats/src/xlsx/filter-values.mbt)、[`filter-custom.mbt`](../../modules/formats/src/xlsx/filter-custom.mbt)、[`filter-source.mbt`](../../modules/formats/src/xlsx/filter-source.mbt)、[`filter-edit.mbt`](../../modules/formats/src/xlsx/filter-edit.mbt)及 [`xlsx-filter.tsx`](../../packages/ui/src/xlsx-filter.tsx)。

### 日期组筛选

Wasm/Web 导出 `XlsxDateFilter`，使用 `{ kind: "dates", column, groups, values, blank }`，沿既有 `editSheet({ action: "filter", range, columns })` 替换同列条件。`groups` 是至少一项的日历前缀：`YYYY`、`YYYY-MM`、`YYYY-MM-DD`、`YYYY-MM-DDTHH`、`YYYY-MM-DDTHH:mm` 或 `YYYY-MM-DDTHH:mm:ss`，分别匹配整年、月、日、小时、分钟或秒。年为四位 0001–9999，其他分量须补两位；只接受有效日历、24 小时及 0–59 分秒，不接受时区或地区日期文字。普通数字、文字和布尔值等使用 `values` 的既有格式化标签匹配，空白由 `blank` 单独决定。默认面板按行编辑前缀和其他文字，并提供空白开关。

核心只把当前数值和已计算数值公式、且有效格式为日期或日期时间的单元格交给日期组；有效格式包含条件格式。General 数值、日期样式下的文字、布尔和错误、纯时间格式均沿普通标签匹配，不隐式转换为日期。同列日期组和普通标签分别作用于对应类型，各列仍取交集。每组比较 `[起点, 下一组起点)`，时间小数直接使用工作簿序列值，不经过 JavaScript Date、宿主时钟或时区。1900 系统保留序列 60 的虚构 1900-02-29；1904 系统的序列 0 对应 1904-01-01。日期组固定在明确的日历前缀上，不随“今天”变化。

每列日期组与普通标签合计最多 4096 项，分别拒绝完全重复项；跨粒度重叠合法。派生区间先排序合并，再有界二分匹配，沿既有 1048576 份工作和文字预算，不按记录数与日期组数做全交叉扫描。值改变后保留现有隐藏结果，重新应用更新筛选隐藏及 SUBTOTAL 缓存；手动隐藏、源格式、选择、精确历史、整行/整列结构同步、工作表复制/改名和保存重开沿同一事务。错误日历、未知源及输出预算失败均不提交部分结果。

标准 `filters/dateGroupItem` 使用 `dateTimeGrouping` 与对应的 `year/month/day/hour/minute/second` 前缀字段，可与普通 `filter` 和 `blank` 共存。读取不改写源；修改保留筛选按钮、排序状态和隐藏来源。未知粒度、缺少前置字段、多余细分字段、`calendarType` 声明及未知属性/子节点继续保护。相对当前日期的 `dynamicFilter`、其他日历和本地化解析仍归 P11 后续范围。读取及区间规则参考 [ONLYOFFICE 的日期分组匹配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L10785-L10835)、[日期类型分流](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/AutoFilters.js#L1288-L1304)及[六种区间构造](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L12769-L12834)。未复制上游源码；实现归 [`filter-date.mbt`](../../modules/formats/src/xlsx/filter-date.mbt)和 [`xlsx-date-filter.tsx`](../../packages/ui/src/xlsx-date-filter.tsx)。

### 数值排名筛选

`XlsxRankFilter` 从 Wasm/Web XLSX 模块导出，使用 `{ kind: "rank", column, value, top, percent }`。`value` 为整数：项数模式 1–500，百分比模式 1–100；`top=true` 取最大值，false 取最小值。它与值/自定义条件共用 `editSheet({ action: "filter", range, columns })`，替换同列条件，保留其他列并取交集。默认面板提供方向、项数/百分比、数量和应用按钮，保存重开后恢复当前设置。

排名只采用标题后、明确范围内的当前数值及已计算数值公式结果，包含手动和筛选隐藏记录。文字形式的数字、布尔、错误及空白不参与；其他列条件不改变排名样本。重复值按记录计数，阈值上的并列项全部保留。百分比先按数值记录数向下取整，至少一项；项数超过记录数时保留全部数值记录，无数值时全部数据行不匹配。标题与范围外的数字不参与。原生编辑保留现有可见性，使用重新应用按当前值计算阈值；手动隐藏继续保留，SUBTOTAL 的 9/109 及依赖缓存与筛选共享一次历史。

标准 `top10` 的 `val/top/percent` 已接通读取与写回，缺省 top=true、percent=false；已知有限 `filterVal` 可读取，重新应用按当前数值计算，不信任导入阈值。写回保留设置和实际可见行，不持久化派生阈值缓存。采用 [ONLYOFFICE Top10 的方向、百分比与标准字段](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L12306-L12490)及 [1–500 项交互](https://github.com/ONLYOFFICE/web-apps/blob/9c0ca538c3b211052347df09d2a4d6781f023403/apps/spreadsheeteditor/main/app/view/AutoFilterDialog.js)。已检查的 ONLYOFFICE 分支使用 parseFloat 和去重集合；本实现沿已有类型模型只接受数值，并按 [LibreOffice TopTenQuery 的数值记录和包含边界](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/data/table3.cxx#L2487-L2545)保留重复记录，避免将数字文字或不同值个数当作记录数。百分比沿 ONLYOFFICE 的统一向下取整规则。未复制上游源码；实现归 [`filter-rank.mbt`](../../modules/formats/src/xlsx/filter-rank.mbt)。

排名复用当前最多 4096 格、公式工作、输出及历史预算。未知属性/子节点、非法标准参数或非有限缓存值保留原子拒绝；依赖畸形筛选的 SUBTOTAL 也可能在打开时拒绝。工作表复制和改名保留排名条件；整行/整列变换见[行列插入与删除](#行列插入与删除)，局部单元格移位仍受保护。颜色/图标/日期类动态/高级筛选继续实施。

### 平均值筛选

`XlsxAverageFilter` 从 Wasm/Web XLSX 模块导出，使用 `{ kind: "average", column, above }`。`above=true` 严格高于平均值，false 严格低于；等于平均值不通过。沿同一 `editSheet({ action: "filter", range, columns })` 替换同列条件，其他列仍取交集。默认筛选面板提供两个按钮，并显示当前方向。

样本使用标题后、范围内的当前数值和已计算数值公式结果，包含隐藏记录及重复值；文字数字、布尔、错误和空白不参与，也不通过此条件。其他列条件不改变样本。无数值时全部数据行不匹配。原生输入保留现有可见性，重新应用后更新阈值、筛选隐藏及 SUBTOTAL 缓存；手动隐藏、结构变换、复制/改名、精确历史和保存重开复用既有事务。清除条件后，原先隐藏的错误值重新参与普通公式计算。

标准 `dynamicFilter` 的 `aboveAverage/belowAverage` 已接通读取和写回；已知 `val/maxVal` 必须有限，重新应用按当前值计算并移除派生缓存。规则参考 [ONLYOFFICE 平均值计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L11728-L11745)和[严格比较](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L11865-L11871)。上游样本使用 parseFloat；本实现沿排名筛选的已有类型模型只接受数值记录，避免隐式转换文字。复用 4096 格、公式工作、输出及历史上限，非有限平均值、未知属性/子节点和其他动态类型继续原子拒绝。实现归 [`filter-rank.mbt`](../../modules/formats/src/xlsx/filter-rank.mbt)及既有筛选读写与面板。

### 自动适配尺寸

同步 Wasm 与 Worker 使用 `autoFit(revision, sheet, first, last, axis, profile)`；`axis` 为 `rows/columns`，索引从 1 开始且包含两端。宿主使用 `SpreadsheetEditor.autoFit(axis)`，作用于执行时选区覆盖的完整行或列，先提交单格草稿。默认尺寸面板提供两个按钮。每项命令独立进入既有历史，保持当前表和选区；重复写入相同源状态不增加 revision。

核心遍历所选轴上实际存在的单元格，使用显示数字格式、已计算值、有效字体与当前列宽测量；不按公式源码长度估算。换行及显式换行沿既有文本布局。行高至少为工作表默认值，并包含当前网格文本内边距，上限 409.5 磅；列宽按 Normal 字体最大数字宽度换算，向上取足像素并保留 1/256 单位，上限 255。无可测内容的轴回到默认尺寸。适配后的行高随内容、有效字体/字号、换行、数字格式、合并及列宽变化重算；bestFit 列随数值、布尔、错误及公式结果扩宽，不因值变短缩列，也不因普通文字编辑扩列。显式调用仍可重新缩放到当前内容。

多列合并不参与列宽测量，多行合并不参与行高测量；单行横向合并的换行文本使用单行字体高度。行高适配保留隐藏行；隐藏列仍按其底层声明宽度测量换行文本，保留隐藏状态。列宽适配显示目标列。修改保留列样式、轮廓、折叠属性、相邻尺寸、单元格源、样式部件、公式缓存与 calcChain，只提交目标工作表的尺寸片段。行记录写入 `customHeight="0"`，列记录写入 `bestFit="1"`。核心在同一候选事务内先更新依赖数值列，再重算行高；派生尺寸与值、缓存、样式共用一次 revision 和历史，撤销不重新测量。手动设置正行高或正列宽切回固定尺寸，手动隐藏列不被数值更新显示。未固定高度的普通默认行，也在带字体的编辑中重算并写入 `ht`。`sheetFormatPr.customHeight` 是行的缺省固定设置，显式 `customHeight="0"` 可覆盖它。未绑定字体时，原本不带 `ht` 的行保留自动声明，可继续仅数据编辑和保存；原本缓存 `ht` 的自动行仍须先绑定字体再修改。尚未编辑的导入缺省行，在首次布局中仍使用源默认高度，初次测量待扩展。

一次事务累计最多 4096 次轴适配、4096 次单元格测量及 262144 个文本单元，不展开空单元格矩阵。字体缺失、富文本/未知样式、保护、未计算公式、未支持的条件规则、未知筛选/表格/透视及扩展资源继续拒绝，保留包和历史。显式适配、成功的网格布局或打印布局会在会话内保留调用者的字体探针和 profile 副本。探针由调用者持有并须保持可用；重新打开后，影响自动轴的编辑须先完成一次带字体 profile 的布局或适配。缺映射、未知布局或预算失败会拒绝整个候选编辑，保留原值、缓存、样式、尺寸及撤销/重做。默认宿主打开时已完成字体布局。尺寸片段使用原有历史和输出预算。核心已检查换行、大小字体、数字显示、合并、隐藏行及零高行、原列区间属性、Normal 与第 0 个单元格样式分离、精确历史、重开和失败；Chromium 已检查默认按钮、草稿与尺寸分项撤销、独立 XML、同步 Wasm/Worker 结果、保存重开及 PDF。实现依据 [ONLYOFFICE 列宽适配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L18321-L18500)、[行高适配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L18504-L18576)及[合并格行高规则](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9820-L9880)。

自动模式更新依据 [ONLYOFFICE 数值列扩宽](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9558-L9610)及[行高失效与重算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9915-L9975)。核心已检查数值/布尔/错误和跨表依赖结果扩列、短值不缩列、行高增减、改窄列后的换行高度、手动固定覆盖、稀疏目标间未知列声明保留，以及字体/文本预算失败的原子性和重开恢复。Chromium 已检查原生输入自动扩列、一次撤销恢复输入和尺寸，换行输入及列宽变化重算行高，固定行高继续输入保持；沿同一流程保存、重开和导出 PDF。

默认行的带字体编辑已检查原生输入、换行、字号、列宽及固定覆盖，源行高与输入共同进入精确历史；清除内容和格式后空白 Normal 行回到默认高度。列宽修改只更新与实际变化列相交的实际行；合并变化按受影响行区间更新，不展开空单元格。未触及行的只读内容和原 XML 保留。普通值/表达式条件规则已按有效差异样式测量，并在依赖变化时重算受影响自动轴，见[条件格式](#条件格式)。未支持的效果继续保护。默认行高变化可改变分页；现有原生输入流程已通过独立 XML 核对两条普通行 18 pt、双行文字行 33 pt，以及 120 pt 可打印高度下的 6 页预览。

### 合并与取消合并

`editSheet(revision, sheet, { action: "merge", range, discard })` 合并指定矩形；`{ action: "unmerge", range }` 取消相交的合并。`range` 是 A1 矩形，单格地址自动扩展到已有完整合并范围。两种操作一次最多 4096 格，工作表最多保留 1024 个不重叠合并范围；合并须完整包含相交的旧合并。重复合并同一范围和取消未合并范围不增加历史。活动表操作选择目标范围，非活动表操作保留当前选择。

`XlsxQuery.merging` 返回查询范围的 `range`、是否相交合并的 `merged`、非左上角非空格数 `discarded`、会丢弃的额外便笺数 `discardedNotes`，以及 `mergeReason/unmergeReason`。合并只有收到布尔 `discard: true` 才能丢弃非锚点内容或额外便笺；否则以 `merge-data-loss` 拒绝。默认属性栏使用同一复选框确认值/公式或便笺损失，即使单元格值全空也须确认便笺损失；宿主沿现有队列先提交草稿。核心重新检查当前数据和保护状态，失败保留已提交包与历史。

合并保留左上角值/公式和各格非边框格式，清除其余值/公式；共享公式存活成员转换为普通公式，依赖缓存和保存计算元数据同步更新。非锚点验证范围从规则中移除，锚点验证和条件格式保留。单元格与合并 XML、验证和缓存一起提交一项有界历史，保留原样式记录和不相关资源，新增边框样式按需派生并复用。取消合并只移除相交合并记录，保留各格内容/格式及计算源；被此前合并丢弃的内容通过撤销恢复。合并后格式查询、编辑及清除可从单格锚点作用于完整范围。

文字与填充沿用左上角样式；边框组合读取起止格的声明，补齐右边和下边。合并时只保留整条外围上各格一致的线型及颜色声明，缺失或不一致时移除整边；内部边框清除。新边框保留主题色、索引色等源声明，不按当前 RGB 固定化。单行和单列遵循同一规则；合并后设置某侧边框只作用于外围对应边，不在内部加线。各格的字体、填充和数字格式保持不变，原样式记录保留源字节。格式查询、网格和打印使用同一边框组合，读取起止格不展开巨大导入合并区。派生样式仍受每类记录数、样式源码长度和历史预算限制；候选总长度超限时也不清除内容、不提交历史。工作表保护、部分旧合并、未知合并属性、超出预算、富文本/未知目标样式，以及未知便笺、非锚点超链接、表格/透视表和扩展资源拒绝合并；取消合并沿自身保护检查，不清理未知资源。合并格格式刷仍待矩形快照扩展。核心已检查内容策略、验证、共享公式、依赖、XML 顺序、纯取消合并的部件保真、精确历史和失败；Chromium 已检查键盘范围、确认控件、合并内命中、填充、保存重开和 PDF。操作依据 [ONLYOFFICE 范围合并与验证调整](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L20316-L20706)；边框归并及外围写回遵循同一上游过程。核心已检查四边、内线、单行/单列、不一致边的移除、主题/索引色源声明、精确历史、重复样式复用及预算失败。Chromium 用独立 XML 检查派生边框和原样式记录，网格及打印绘制数据保持颜色、线宽，保存重开及 PDF 沿已有流程。

### 单元格格式编辑

同步 Wasm 与 Worker 使用 `formatCells(revision, patch)`，宿主使用 `SpreadsheetEditor.formatCells(patch)`。命令作用于队列执行时的选区，宿主先提交单格草稿。`XlsxCellFormat` 从 `wasm/xlsx` 和 `web/xlsx` 导出；省略的属性保持原值。字段为 `family`、`size`、`bold`、`italic`、`color`、`fill`、`horizontal`、`vertical`、`wrap`、`numberFormat` 及 `left/right/top/bottom`。颜色为六位十六进制，空 `fill` 清除填充；四边使用 `{ style: "none" | "thin" | "medium" | "thick", color }`。字号为 1–409 磅，水平对齐为 general/left/center/right，垂直对齐为 top/center/bottom；数字格式限下节已有集合。宿主先验证新字体键存在于字体 profile。

`XlsxQuery.formatting` 返回这些属性，不同值返回 `null`，并返回 `readOnlyReason` 和所选字体键 `fontKeys`。一次最多 4096 格；依赖无法隔离的公式、受保护表、富文本/未知样式及只覆盖部分合并格的范围继续保护。单格合并锚点的格式查询和编辑扩展到完整合并范围。空白格继承行样式，其次列样式，再使用基础样式；显式单元格样式优先。派生格式保留原共享记录，不改写其他格。样式和目标格共同提交有界历史，缺失样式部件时关系及内容类型一起创建和撤销。仅改格式保留值、公式源、缓存和 calcChain，后续输入保持格样式；重复设置有效状态不新增历史。格式化的空白格参与使用范围和打印。默认 UI 使用可滚动属性栏，保留网格工作区。Chromium 已检查格式设置、草稿顺序、混合历史、缺失字体恢复、保存重开和格式化公式的 PDF 输出；更多装饰和格式代码仍归 [P11](../p11-xlsx-core.md)。

### 格式刷

同步 Wasm/Worker 的 `captureFormat(revision)` 返回 `CopiedCellFormat`，类型为 `Required<XlsxCellFormat>[][]`；`applyFormat(revision, format)` 将它应用到当前选区。宿主对应 `SpreadsheetEditor.captureFormat()` 和 `applyFormat(format)`，复制与应用前均提交单格草稿。快照保存逐格有效属性，不含样式索引或源工作表身份；复制本身不修改文档和历史。

单格目标按源矩形尺寸扩展；其他目标按源行列顺序重复平铺，边缘截到目标边界。源和目标各最多 4096 格，矩阵须非空、等宽且携带全部属性。工作表边界、未知属性、字体、只读内容和预算失败均保留已提交文档。合并格源或目标继续保护，待合并编辑接通后补齐。应用复用现有格式事务；值、公式、缓存和行列尺寸保留。样式复用按元素/属性的命名空间与名称、值及子结构判断，忽略前缀和属性顺序，原有源记录保持原样。

默认 UI 的格式刷单击后对下一个新选区应用一次；双击或在按钮上按 Shift+Enter 锁定，可连续应用及切换工作表。Esc 或再次点击按钮取消，替换文档时释放状态。复制/平铺参考 [ONLYOFFICE 的目标扩展与格式复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21916-L21960)，单次/锁定/取消参考 [GenOffice 格式刷](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/sheets/src/renderer/format-painter.ts)。

### 清除单元格

同步 Wasm/Worker 使用 `clear(revision, mode = "contents")`，宿主使用 `SpreadsheetEditor.clear(mode = "contents")`。`XlsxClearMode` 从 `wasm/xlsx` 和 `web/xlsx` 导出，取值为 `contents/formats/all`。缺省和原生 Delete/Backspace 保持清除内容；默认 UI 分别提供清除单元格、清除格式和全部清除。宿主先提交单格草稿；输入与清除各占一项历史。

`formats` 将目标格恢复为工作簿内置 Normal 样式，派生或复用 cellXF，保留原共享样式、值、公式、缓存和 calcChain。两种格式清除都会取消完整合并，并从选区清除既有条件格式。`all` 还清除值和公式、选区内验证规则及完整覆盖的超链接；部分覆盖的超链接保持原范围；被清除的共享公式组将存活成员展开为普通公式，并重算受影响依赖。行列尺寸与范围外单元格保持原样，内容变化沿既有保存路径更新计算元数据及共享字符串计数。

一次最多 4096 格，单格合并锚点扩展到完整合并范围。`XlsxQuery.normalFont` 返回 Normal 样式的字体键；宿主在格式清除前检查对应 profile。Normal 不等同于第 0 个 cellXF，也不依赖本地化样式名。未知模式、受保护内容、缺失字体和预算失败不提交清除。部分覆盖的合并、需要平移且无法解析的规则公式，以及未知规则结构继续保护；非空扩展、表格/透视表资源、线程批注及未知便笺也继续保护；传统便笺的清除归[单元格便笺](#单元格便笺)。规则之外的资源不推断所有权。

条件格式和验证的 `sqref` 从各原矩形扣除选区，保留不相交区域，最多留下 4096 个矩形。条件格式按范围外接矩形左上角定位，验证按第一个 `sqref` 区域定位；锚点变化时复用核心公式解析器平移相对引用，保持绝对/混合引用、跨表引用和字符串。条件公式、验证的两个公式及公式阈值一并更新，越界引用变为 `#REF!`。锚点不变时保留公式源；清空全部范围才删除规则，验证容器计数同步更新。规则计算、显示与编辑范围分别归[条件格式](#条件格式)和[数据验证](#数据验证)。范围扣除参考 [ONLYOFFICE 条件规则清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L13347-L13386)与[验证范围清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/DataValidation.js#L1068-L1088)；验证公式源位置参考 [LibreOffice 导入](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/filter/oox/worksheethelper.cxx#L1096-L1119)。核心已检查四块残留、多个原范围、混合引用、字符串、阈值越界、上限拒绝和精确历史；Chromium 通过默认按钮清除并用独立 XML 检查范围与公式，保存重开后可继续输入。

核心已检查 Normal 派生、取消合并、条件格式/验证/链接清除、共享公式、依赖缓存及精确混合历史；Chromium 已检查原生草稿后清除格式、全部清除、独立 XML、保存重开和 PDF。行为参考 [ONLYOFFICE 范围清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21093-L21175)和[清除选项](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L16669-L16695)。

### 条件格式

普通 `cellIs`、`expression`、`colorScale` 和 `dataBar` 规则已在核心计算。值规则支持八项比较；数值、文字和布尔保持类型区别，文字比较忽略大小写，空格按零或空文字比较。表达式沿现有公式语法求值，相对引用以全部 `sqref` 的外接左上角为原点，保留绝对/混合及跨表引用；`ROW/COLUMN` 使用当前格。公式错误不命中，未知函数或引用给出诊断。

`priority` 越小越优先；命中的高优先级属性覆盖低优先级的相同属性，其余属性组合。命中 `stopIfTrue` 后不再使用后续规则，即使该规则没有差异样式。`dxfId` 从工作簿当前样式部件解析，不写回单元格样式。支持字体名、字号、粗斜体、文字色、纯色/无填充、四边 thin/medium/thick/none、现有数字格式及基本对齐/换行。颜色复用主题、索引及 tint 解析；差异填充优先采用 `bgColor`，与 [ONLYOFFICE fixForDxf](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/model/WorkbookElems.js#L3502-L3509)一致。差异字体仍须显式提供 profile 映射。

`XlsxConditionalFormat` 包含 `kind`（`cellIs/expression/colorScale/dataBar`）、`operator`、`formula1`、`formula2`、`stopIfTrue` 和部分属性 `format: XlsxCellFormat`。表达式的 operator 为空；仅 between/notBetween 使用第二个公式。颜色刻度的 stops 和数据条的 bar 见下文。`XlsxQuery.conditionalFormats` 返回当前表按优先级排序的全部普通规则，每项包含 `priority`、空格分隔的 A1 矩形 `ranges`、`rule` 和 `readOnlyReason`，容器也有保护原因。规则原点随完整 ranges 定位，不随当前选区变化。

`SpreadsheetEditor.editSheet`、`XlsxClient.editSheet` 与同步 Wasm 共用以下操作。核心对应 `SheetEdit::ConditionalRule` 和 `ConditionalPriority`。

| action | 字段与行为 |
| --- | --- |
| `conditionalRule` | `ranges, priority, rule, sourceRevision`；priority 为 null 且 rule 非 null 时新增到最低优先级 |
| `conditionalRule` | priority 非 null 且 rule 非 null 时修改该完整规则的范围和属性；其他共享同一范围的规则保留 |
| `conditionalRule` | priority 非 null 且 rule 为 null 时删除该完整规则；ranges 可为空 |
| `conditionalRule` | priority 和 rule 均为 null 时，仅从 ranges 指定的单个矩形扣除条件规则；范围外公式随锚点平移，值及基础格式保留 |
| `conditionalPriority` | `priority, position, sourceRevision`；position 从 0 开始，将该规则移到完整列表中的指定位置，并重编规则优先级 |

修改、删除和排序要求 sourceRevision 等于执行时 revision，避免过期优先级命中另一规则。新增和选区清除使用显式范围，不依赖旧规则身份；仍沿 editSheet 的 revision 与原生草稿屏障执行。普通草稿先提交，新增规则单独进入历史；带过期身份的修改在草稿提交后拒绝，须按新查询重试。重复修改为相同范围/属性或移到原位置不新增历史。

规则、差异样式及派生尺寸共同提交一次事务。只修改条件或范围时保留原 dxfId、主题色及共享差异源。新差异样式复用现有样式池，保留旧的共享 dxf；缺样式部件时关系和内容类型一同创建/撤销。新数字格式沿原样式路径分配身份。当前可见有效字体在提交前检查，未知源、保留的规则注释/处理指令、工作表保护、缺字体或预算失败保留原文档。范围输入最多 4096 个矩形及 262144 UTF-16 单位；规则查询的范围/公式合计最多 1048576 单位，超出时返回管理保护原因。

默认条件格式面板提供新增、选择、修改、删除、上下调整优先级和仅清除选区规则，支持值/公式条件、停止后续规则、文字色/填充、粗斜体、字号、换行和数字格式。API 可使用全部现有 XlsxCellFormat 属性；面板未展示的导入属性保留。实现归 [`conditional-edit.mbt`](../../modules/formats/src/xlsx/conditional-edit.mbt)、[`conditional-style-edit.mbt`](../../modules/formats/src/xlsx/conditional-style-edit.mbt) 和 [`conditional-settings.mbt`](../../modules/formats/src/xlsx/conditional-settings.mbt)。

`kind: "colorScale"` 使用 `stops` 描述两个或三个颜色节点，operator、formula1、formula2 为空，format 为空对象，stopIfTrue 为 false。每个 `XlsxConditionalStop` 包含 `kind`、字符串 `value` 和六位 RGB `color`。节点类型为 min、max、num、percent、percentile 或 formula；min/max 的 value 为空，百分比和百分位范围为 0–100。普通值/公式规则不带 stops；MoonBit 的 ConditionalFormat 对应空数组。

颜色刻度使用完整规则范围内实际数字和已计算公式结果，忽略空格、文字、布尔和错误，不重复统计相交范围。不按可见窗口重新取范围，也不读取旧公式缓存作为当前结果。percent 按最小/最大值计算，percentile 按排序后的 `(n-1)*p` 位置线性插值；公式阈值在规则原点求值一次。阈值按数值排序，颜色保持节点顺序；超过端点时截定，所有值相同时使用末端颜色，无数字或阈值公式出错时不着色。RGB 插值使用 [ONLYOFFICE CGradient](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/model/ConditionalFormatting.js#L2637-L2680)的 256 步及通道向下取整，百分位参考 [getPercentile](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/model/FormulaObjects/statisticalFunctions.js#L356-L375)。

默认面板可在两/三节点间切换并编辑各节点的类型、值/公式和颜色；中间节点默认使用第 50 百分位。阈值与统计按当前计算缓存，编辑后重新计算，网格和 PDF 复用同一最终填充，不改基础单元格样式。只改范围时保留原规则源；修改阈值也保留未变的主题色/索引色节点。颜色刻度不创建 dxf，沿既有规则历史、局部清除与保存重开。统计、排序及阈值文本共同受规则工作预算限制，失败不留下部分缓存或半项编辑。实现归 [`conditional-scale.mbt`](../../modules/formats/src/xlsx/conditional-scale.mbt)。

数据条使用 `kind: "dataBar"` 与 `bar: XlsxDataBar`。operator、formula1、formula2 为空，format 为空对象，stopIfTrue 为 false，不带 stops。bar 包含 minimum、maximum、六位 RGB color、showValue，以及整数 minLength/maxLength；条长范围为 0–100 且 minLength 不大于 maxLength。minimum/maximum 为 `XlsxConditionalThreshold { kind, value }`，沿用颜色刻度的六种阈值及字符串值。MoonBit 对应 DataBar、ConditionalThreshold 和 ConditionalFormat.bar；其他规则的 bar 为 None，JSON 省略。

普通 SpreadsheetML dataBar 默认显示值，最短/最长条长为 10%/90%。核心复用完整稀疏范围的当前数值、公式阈值和有界缓存，按值计算条长，超出阈值时截定。均匀值使用最短条长，无数字或阈值公式出错时不绘制；多条数据条使用首个有效的高优先级规则，并遵守更高优先级的停止规则。沿 [ONLYOFFICE legacy data bar](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/view/WorksheetView.js#L6273-L6385) 的条长、内边距和渐变端色计算，末端向白色混合 82.8%；全部非正数时从右侧绘制。普通规则采用同色、无轴线的旧格式语义，混合正负值仍沿最小/最大值计算。x14 的负值颜色、轴线、方向、实心条及边框设置尚未接入，保留源并保护相关输出与修改。

默认面板提供两个阈值、条色、显示值开关和最短/最长条长；新增、完整修改/删除、优先级及局部清除沿同一规则事务。只改阈值时保留未变的主题/索引色，不分配 dxf 或基础单元格样式。showValue 为 false 只隐藏网格/PDF 文字，值、公式、查询的逻辑 display 和原生输入保留；自动尺寸仍按实际值及有效文字格式计算。实现归 [conditional-bar.mbt](../../modules/formats/src/xlsx/conditional-bar.mbt)。

共享绘制使用 `GradientRectangle(rect, startColor, endColor)` 和 `gradientRect` 命令，均为从左到右的 RGB 渐变；反向条交换颜色和起点。矩形坐标须有限、绝对值不超过 10^9，宽高非负，颜色为六位 RGB。Canvas 使用线性渐变，PDF 使用经矩形裁剪的轴向 shading，复用已有变换/裁剪；PDF 相同颜色对共享资源，最多 4096 对，保留总输出预算。背景先绘制，随后数据条、边框和文字。实现归 [layout/gradient.mbt](../../modules/layout/src/gradient.mbt) 与 [pdf/write-gradient.mbt](../../modules/formats/src/pdf/write-gradient.mbt)。

网格、查询 `display`、自动适配和打印使用同一有效样式。依赖格输入或公式结果改变时，自动行/数值 bestFit 列按条件样式重算，与原编辑共享一次历史；固定尺寸保持原值。规则 XML、`dxf`、基础格式和范围外部件保留，保存重开继续计算。合并格按锚点求值。

规则及差异样式各限 4096 项，公式限 8192 UTF-16 单位；网格、整项打印或编辑适配共享 1048576 次规则/公式工作预算，不展开整列空格。未知规则、属性、装饰或扩展样式保留源并诊断；相关打印或适配拒绝，避免输出缺失效果。查询中的条件格式预算失败转成诊断，避免成功提交后被返回查询误报为失败；实际绘制和输出仍检查预算。扩展数据条、图标集、其他规则、边框仅改颜色及更广差异格式仍待实现。实现归 [`conditional-format.mbt`](../../modules/formats/src/xlsx/conditional-format.mbt) 和 [`conditional-style.mbt`](../../modules/formats/src/xlsx/conditional-style.mbt)，值比较参考 [ONLYOFFICE cellIs](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/model/ConditionalFormatting.js#L835-L913)。

### 单元格超链接

`XlsxQuery.hyperlink` 返回 `{ target, mixed, readOnlyReason, navigationReason }`。target 为共同地址，未链接或混合选区为 null；mixed 区分混合范围。范围查询使用矩形运算，不展开整列空格。支持普通 `hyperlink`、外部关系及内部 location；未知属性/容器、组合外链与 location、未解析关系或相交的重复链接保护相关修改。

`SpreadsheetEditor.editSheet({ action: "hyperlink", range, target })` 复用 `XlsxSession/Client.editSheet(revision, sheet, change)`。HTTP、HTTPS、mailto 或 `#范围/定义名称` 最多 2048 UTF-16 单元；内部目标须解析到现有可见表中的一个矩形，例如 `#'团队''s Data'!$A$1:B2` 或 `#Local`。核心使用现有公式词法、名称作用域与引用解析。null 移除范围内链接，保留单元格值、公式、富文本和直接格式；不自动套用链接颜色或下划线。显示文字继续通过原生输入编辑。

修改局部范围时拆分既有链接，范围外目标、提示、display、局部命名空间及间隙注释保留。单格命中合并区域时作用于整块；其他选区须包含相交的完整合并区域。新增关系复用同目标，不改写共用关系或清理旧关系；首次关系部件与链接 XML 合为一次历史。源、范围片段、历史及输出预算失败不提交。

默认面板提供地址、应用、混合移除及显式打开，原生草稿沿既有队列提交。打开文件、查询、设置链接和打印均不请求外链；外部打开使用新窗口及 `noopener noreferrer`。内部打开调用 `{ action: "openHyperlink", range, sourceRevision }`，核心检查当前选区与修订后定位，不增加历史。无效或隐藏目标返回 navigationReason，保留源并拒绝跳转。

已有改名、复制、删除工作表及行列/单元格结构事务继续更新普通链接范围与内部引用；名称改名同步内部 location，外部文件的 location 保持原值。删除定义名称时移除因此失去矩形目标的已知链接，包括名称别名链；其他已失效引用保留导航原因。保存重开支持继续编辑，链接和关系与原生输入、结构修改可精确混合撤销。静态 PDF 校验普通链接元数据后保留单元格文字与格式，未知链接扩展继续保护输出；可点击 PDF 注释、HYPERLINK 函数及绘图对象链接仍属后续范围。

实现归 [`hyperlink-query.mbt`](../../modules/formats/src/xlsx/hyperlink-query.mbt) 和 [`hyperlink-edit.mbt`](../../modules/formats/src/xlsx/hyperlink-edit.mbt)。范围查找、设置/移除及保留直接格式的语义参考固定 [ONLYOFFICE Range hyperlinks](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L20760-L20849)，复用第一方范围拆分、关系与历史事务，未复制上游代码。

### 单元格便笺

`XlsxQuery.note` 返回查询单元格的 `{ address, exists, text, author, reason }`。单格或一个完整合并区域可编辑，合并区域使用左上角身份；多格返回选择原因。支持传统 comments XML 和普通 VML 便笺框，线程批注继续保护。查询覆盖显式 `sheet/range`，不改变活动选区。

`XlsxSession/Client.editSheet(revision, sheet, { action: "note", cell, text, author? })` 和 `SpreadsheetEditor.editSheet(change, sheet?)` 创建、修改或删除便笺。`cell` 是单个 A1 地址，`text: null` 删除；新文字必须非空，最多 32767 UTF-16 单元，CRLF/CR 归一为 LF。新建须显式提供非空 `author`，最多 255 单元且不含控制字符；修改保留原作者。空文本便笺可读取和删除，显式文字修改继承首个源 run 的字符属性。SpreadsheetML 转义由核心统一编码，字面的 `_x0041_` 不会变成 `A`。

默认面板复用 `EditorOptions.commentAuthor.name` 创建作者，未提供时仍可修改和删除已有便笺。应用前原生单元格草稿沿既有队列提交，值、公式、格式和计算结果保持。便笺输入以当前文档/工作表/单元格绑定；切换单元格更新输入，未应用的面板草稿不写入文档。显示文字与 VML 外观不进入单元格值、查找、CSV 或默认静态 PDF。面板继续提供便笺编辑；网格角标和悬停/选中提示见下段。

网格使用 R0 绘制橙色逻辑右上角标，RTL 镜像到左侧，尺寸随缩放变化；空格和合并锚点也可显示。位置与裁剪由核心沿用行列尺寸、隐藏、冻结和合并几何。`XlsxViewport.notes` 返回可见 `{ address, author, text, rect }`，rect 使用 point 的已裁剪画布坐标；跨冻结窗格的合并格可有多个可见片段，源便笺不重复。一次最多 4096 个片段及 5 Mi 文字/作者单元，含最多四窗格重复。仅便笺的远端单元格扩展网格滚动范围，不扩展默认打印区域。未知便笺继续沿既有保护和诊断处理，不暴露部分记录。

Web 复用核心矩形显示悬停或选中便笺的作者与纯文字提示，不改变选区、修订、历史或保存源。键盘选中格关联便笺描述，网格语义也提供作者和文字；Escape 隐藏提示，切换目标可重新显示。长文字可在有界提示中滚动；悬停提示内仍可读取。布局、工作表或修订变化后更新提示，释放实例时解除监听。角标和提示不进入静态 PDF，也不修改 VML 外观。角标参考 [ONLYOFFICE drawCommentCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L642-L690)，实现归 [`notes-grid.mbt`](../../modules/formats/src/xlsx/notes-grid.mbt)及 [`spreadsheet-notes.ts`](../../packages/web/src/spreadsheet-notes.ts)。

首次创建把 comments、VML、工作表 `legacyDrawing`、关系和内容类型合为一项精确历史。普通备注框使用标准 `ObjectType="Note"` 及从零开始的 Row/Column、八项 Anchor。导入只有 comments 而无 VML 时，新增便笺会补齐全部现有便笺的框；若已有未解析的 `shapeId`，保护该创建。修改只替换文字正文，保留原作者、其他便笺、外围注释、局部命名空间和 VML 位置/外观。删除移除文字与对应框，最后一条删除后保留空部件和作者列表。每表最多 4096 条、合计 1 Mi 文字单元及 4096 个作者，并继续受包、输出与历史预算约束。

复制表创建独立 comments/VML 部件并重映射关系；副本可继续编辑。改名和删除沿已有工作表事务，删除仅回收独占部件和内容类型。新增部件按稳定顺序写入 ZIP，删除/撤销不改变相同状态的保存字节。重复地址、作者缺失、未知/不匹配的 VML、控件/图片、未知文字/扩展、共享/外部部件、保护、旧修订和预算失败原子拒绝。普通合并及取消合并的便笺归属见下段。未知 VML 保留未渲染诊断并拒绝打印；普通便笺输出按默认不打印批注处理，非默认批注打印设置继续保护。

整行/整列插删和四向单元格移位复用既有 `AxisChange`。便笺随所属格移动，范围外不变；删除所属格时移除该便笺及对应 VML shape，保留作者、空部件和关系。插入不得把空格上的便笺推出工作表。核心同步 comment 的 `ref` 和对应 `ClientData` 的 Row 或 Column，仅改动受影响轴的文字；Anchor 矩形、偏移、外观/标志、guid/shapeId、正文与其他源保留。范围插入后选区仍是插入区域，可定位到移后的便笺格；不单独修改既有选区规则。部件、值/公式、规则与选择共用一次精确历史；无法安全替换的 VML 文字或预算失败不提交。归属规则参考 [ONLYOFFICE updateCommentsDependencies](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L709-L838)，实现归 [`notes-transform.mbt`](../../modules/formats/src/xlsx/notes-transform.mbt)。

普通行/列排序复用已有稳定位置映射，便笺与所属格一起移动，空值格也参与；标题、隐藏轴和范围外便笺保留。核心同步 `ref` 与 VML Row/Column，正文、作者和弹框外观保持。四向填充、自动序列与收缩填充保留每格原有便笺，不复制源便笺或覆盖目标便笺。清除内容/格式保留便笺；全部清除删除选区内文字与对应 VML shape，包括只有便笺的空格，保留范围外便笺、空部件与作者。各操作与值/公式/格式共同提交一次有界历史，支持精确撤销与重开；未知资源继续原子保护。语义参考 [ONLYOFFICE sortComments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L840-L863)、[自动填充](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22180-L22690)及[清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L16657-L16703)，实现复用同一便笺源编辑器与已有操作事务。

合并复用 [ONLYOFFICE mergeComments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L1395-L1431) 的源顺序选择：先取范围内首条便笺，后续便笺的行不更大且列更小时替换保留项。保留项移到合并左上角，其余文字与 VML shape 删除；单条便笺移动不产生便笺损失。`discardedNotes` 返回额外便笺数，范围 0–4095，沿现有 `discard` 显式确认；非锚点值/公式仍独立计入 `discarded`。保留项的正文、作者、shape 身份及框外观不变，范围外便笺保持。便笺、合并几何、单元格与派生样式共用一次精确历史；合并后修改便笺使用左上角身份。取消合并保留现有便笺和资源，不恢复已确认丢弃的便笺；撤销可精确恢复它们。未知/共享资源、无法替换的 VML 坐标或预算失败继续原子保护。

部件及锚点格式参考 [ONLYOFFICE VmlDrawing.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/VmlDrawing.cpp#L295-L410)。实现独立使用已有 XML 编辑、单元格地址、关系及历史事务，归 [`notes-read.mbt`](../../modules/formats/src/xlsx/notes-read.mbt)、[`notes-vml.mbt`](../../modules/formats/src/xlsx/notes-vml.mbt)、[`notes-create.mbt`](../../modules/formats/src/xlsx/notes-create.mbt)、[`notes-edit.mbt`](../../modules/formats/src/xlsx/notes-edit.mbt)及 [`xlsx-format.tsx`](../../packages/ui/src/xlsx-format.tsx)。线程回复/解决、便笺外观编辑和其余资源变换仍归 [P11](../p11-xlsx-core.md)。

### 数据验证

普通 `dataValidation` 支持创建、修改、清除及核心输入校验，覆盖整数、小数、日期、时间、文字长度、列表和自定义公式，以及八种比较运算。源的 `showErrorMessage` 为 true 才限制输入，`allowBlank` 允许空值。日期和时间比较已有数值序列或公式结果，沿工作簿的 1900/1904 日期系统；不新增宿主日期字符串猜测。文字长度使用 UTF-16 单元。重叠范围沿源顺序选择首个规则，规则自身的多个范围使用首段锚点平移相对引用。

`SpreadsheetEditor.editSheet({ action: "validation", range, rule })` 复用同步 Wasm、Worker 和 `XlsxClient.editSheet`。`rule` 为 `XlsxDataValidation`，null 清除目标范围的验证。新增和修改不改写已有值；相交旧规则扣除选区，范围外规则及相对公式保持含义。整列仍是范围描述，不展开空格子。一次提交一项精确历史，无变化不新增历史。未知规则属性、保留的注释/处理指令、非默认输入法设置及扩展验证保护修改；预算或公式检查失败不留下半项操作。实现归 [`validation-edit.mbt`](../../modules/formats/src/xlsx/validation-edit.mbt)。

| `XlsxDataValidation` 字段 | 内容 |
| --- | --- |
| `kind` | `none/whole/decimal/date/time/textLength/list/custom`；none 允许任意值并保留提示 |
| `operator` | `between/notBetween/equal/notEqual/lessThan/lessThanOrEqual/greaterThan/greaterThanOrEqual` |
| `formula1/formula2` | 已支持的公式；比较范围需要两项，列表使用带引号的逗号文字或单行/单列引用 |
| `allowBlank/showErrorMessage` | 空值策略及是否检查非法输入 |
| `errorStyle/errorTitle/error` | `stop/warning/information`、错误标题和信息 |
| `showInputMessage/promptTitle/prompt` | 是否显示输入提示、提示标题和正文 |
| `showDropDown` | true 隐藏列表下拉；沿 OOXML 的反向开关保存 |

标题最多 32、提示/错误正文最多 255 UTF-16 单元。核心 `DataValidation::default()` 使用允许空值、启用停止错误的 1–10 整数规则。默认属性面板编辑以上字段，应用及清除只作用于所选范围。原生草稿沿现有队列先独立提交，规则变更可另行撤销。

`XlsxQuery.dataValidation` 返回选区首格的 `rule`、是否混合的 `mixed`、编辑保护原因、列表文字 `options/optionsReason` 及有效 `promptVisible`。规则公式已相对选区首格换算，混合查询和整列覆盖有范围片段及工作量上限。输入提示遵守工作表的 `disablePrompts`。`{ action: "validationValue", index, sourceRevision }` 选择当前单格或合并格的候选值；`sourceRevision` 使用显示选项时的 query revision，过期选择拒绝。核心重新读取列表，保留引用值类型，字面列表保持文字，等号开头的选项不执行为公式；选择与重算共用原值事务和历史。

自定义条件和边界公式复用既有公式解析、引用与计算，读取整次候选写入和受影响计算结果。字面列表按逗号拆分、移除每项开头的空格并按原文比较；单行/单列列表引用保留值类型。未知公式、名称/扩展引用、未知规则属性及扩展验证继续保护相关输入。每表最多检查 4096 条规则，单个列表最多 4096 项或单元格，验证共享 1048576 份工作预算；规则公式各不超过 8192 UTF-16 单元。失败发生在缓存写回、自动尺寸、源提交和历史之前，整块粘贴不会留下部分值。

失败使用 `validation-stop` 或 `validation-warning`，消息包含表名、单元格及源错误标题/文字。同步 Wasm 和 `XlsxClient.replace(revision, sheet, range, values, literal=false, acceptWarnings=false)`、`paste(revision, text, acceptWarnings=false)` 提供显式警告授权。授权后仍重算并检查所有目标，只允许 `warning/information`，不绕过 `stop`、未知规则或预算。查找替换沿共享值事务校验，暂不提供警告授权参数。验证不因依赖值变化重新拒绝未直接修改的格子，也不重验撤销/重做。

`SpreadsheetEditor.acceptValidationWarnings` 默认为 false，作用于该编辑器的原生输入和粘贴。默认公式栏提供对应复选框，启用后允许这些输入触发警告，直至关闭或更换文档。非法原生输入保留草稿和焦点，用户可纠正、取消或启用警告后重试；停止规则始终生效。现有规则 XML、值类型、其他部件及精确历史保持。普通验证元数据不再阻止打印/PDF，输出仍使用原值和样式；未支持的条件格式及其他未呈现内容继续保护输出。命名/扩展公式和更广导入变体仍待兼容扩展。行为参考 [ONLYOFFICE 数据验证](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/model/DataValidation.js#L516-L619)，输入实现归 [`data-validation.mbt`](../../modules/formats/src/xlsx/data-validation.mbt)。

### SUBTOTAL 汇总

`SUBTOTAL(function_num, ref1, ...)` 复用原生公式栏、公式解析和依赖图，支持总计 2–255 个参数。编号 1–11 依次执行 AVERAGE、COUNT、COUNTA、MAX、MIN、PRODUCT、STDEV、STDEVP、SUM、VAR、VARP；101–111 执行同一运算并排除手动隐藏行。两组均排除筛选隐藏，隐藏列不影响结果。引用格的公式只要含 SUBTOTAL，就排除该格，避免嵌套重复计数；不沿普通引用继续追踪嵌套。求值使用当前类型值，支持同表/跨表单格和矩形及多区域参数，重叠引用按出现次数计入。命名、三维、数组与引用返回形式仍按既有公式边界处理。

数值参与统计，引用文字、布尔与空白通常不参与数值统计；COUNTA 包括文字、布尔、空串公式与错误，COUNT 只计引用数值。PRODUCT 沿所选 ONLYOFFICE 行为转换引用中的有限数字文字，其余文字忽略。直接标量复用数值转换，直接错误先传播；COUNT 可忽略引用错误，COUNTA 计入引用错误，其余统计传播已纳入的引用错误。无数值时 SUM、PRODUCT、MIN、MAX 返回 0，平均、方差和标准差返回 `#DIV/0!`；样本统计不足两项也返回 `#DIV/0!`，总体单项统计返回 0。方差按有界在线均值/平方偏差计算，避免直接相减平方和造成的大数误差。非有限结果返回 `#NUM!`；无效或非整数编号返回 `#VALUE!`。所有读取、嵌套解析和汇总共用现有公式工作量、深度及引用上限，整列空域按实际单元格处理，不展开稠密矩阵。

已有[隐藏来源扩展](#值筛选)时，1–11 仅排除 `filtered`，101–111 排除实际零高行；手动与筛选重叠时两组均排除。没有扩展的外部活动值筛选无法确定隐藏来源，此时 SUBTOTAL 将筛选体内全部已隐藏行视为筛选隐藏，筛选外隐藏行仍视为手动隐藏；重新应用后使用保存的来源。此限制也适用于外部程序丢弃扩展的文件。筛选/清除/移除/重新应用和手动行高变更在同一事务重算相关工作簿公式，缓存、跨表依赖和精确历史一起更新。没有 SUBTOTAL 的筛选继续保留原公式源及 calcChain，不为可见性变更重写无关缓存。撤销重做、保存重开、网格和 PDF 使用同一结果。

编号与嵌套排除参考 [ONLYOFFICE cSUBTOTAL](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L5087-L5243)及[引用读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L1195-L1213)。两类隐藏、隐藏列与嵌套结果同时按 [SUBTOTAL 合同](https://support.microsoft.com/en-us/excel/functions/subtotal-function)处理；对本项目记录的手动来源不采用旧上游“存在筛选就跳过全部隐藏行”的捷径。实现归 [`formula-subtotal.mbt`](../../modules/formats/src/xlsx/formula-subtotal.mbt)。

### 显示与计算

读取共享/内联字符串、数值、布尔值、错误、公式及缓存。富文本读出文字，保留原 XML并保护编辑。受保护工作表及含未知编辑语义的单元格只读。图表、未支持的条件格式、绘图等未呈现内容给出诊断，继续保留源部件。

网格读取行高、列宽、隐藏行列与合并区域。核心使用 Normal 字体和字号的最大数字宽度换算列宽；不依赖 DOM 度量。字体键沿用 `family|bold|italic`，宿主明确映射到已添加的字体身份。支持字体大小、粗斜体、基本文字色、纯色填充、实线边框、左中右/上中下对齐与换行。行列尺寸使用声明值，显式自动适配命令更新这些值；自动模式的内容和列宽变化在文档事务内同步尺寸。数字宽度不足时显示 `#`；文字按单元格裁剪。

General 显示按 [ONLYOFFICE 的 15 位有效数字拆分](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/NumFormat.js#L87-L89)及[数值分解](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/NumFormat.js#L125-L153)消除二进制尾数。例如实际 Double 为 `20.009999999999998` 时显示 `20.01`。文字舍入不重新解析 Double，最大有限数和次正规数保持可显示；计算、类型值、公式文字转换及 XLSX 源缓存保留原精度。查询、网格、PDF、纯文字剪贴板、筛选标签和按显示文字去重共用该格式；去重仍先预览并由显式事务提交。当前保持既有小数/科学记法选择，按实际列宽选择 General 精度和更广浮点显示兼容仍待扩展。实现归 [`number-general.mbt`](../../modules/formats/src/xlsx/number-general.mbt)。

数字格式覆盖 General、`@`、整数、两位小数、千分位、百分比、`yyyy-mm-dd`、`hh:mm:ss`，以及内置 1–4、9–10、14–22、49。日期保留数值，核心解释 1900/1904 系统，1900 序号 60 显示虚构的 2 月 29 日，序号 0 显示 1900-01-00。不经过宿主时区。其他格式、颜色 tint、渐变/图案、非实线边框及额外字体装饰保留声明并诊断，不承诺显示等价。

公式支持数值、字符串和布尔常量，括号、一元正负、`+ - * /`、比较、A1 单格/矩形、整行/整列范围、绝对/混合引用、带引号的跨表引用，以及 `SUM/AVERAGE/MIN/MAX/COUNT/IF/AND/OR/NOT/IFERROR/IFNA/ISBLANK/ISNUMBER/ISTEXT/ABS/INT/MOD/ROUND/ROUNDUP/ROUNDDOWN/SQRT/POWER/PRODUCT/MEDIAN/LEN/LEFT/RIGHT/MID/TRIM/UPPER/LOWER/CONCAT/CONCATENATE/TEXTJOIN/FIND/SEARCH/SUBSTITUTE/EXACT/REPT/DATE/YEAR/MONTH/DAY/TIME/HOUR/MINUTE/SECOND/DAYS/COUNTA/COUNTBLANK/COUNTIF/COUNTIFS/SUMIF/SUMIFS/AVERAGEIF/AVERAGEIFS/INDEX/MATCH/VLOOKUP/HLOOKUP/XLOOKUP/ROW/COLUMN/ROWS/COLUMNS/SUBTOTAL`。范围端点可以反向，核心按矩形解释。显式省略的函数参数作为空白处理，仍检查各函数参数数量。

整列 `A:A`、`$A:B` 和整行 `1:1`、`$1:2` 可带工作表限定并使用反向端点。行号只接受十进制整数，范围受 1048576 行、16384 列约束；混合行/列/单格端点拒绝。内部用一个有界矩形表示，未覆盖维度在复制时固定；原公式源码保持，复制及名称展开输出对应行列记法和 `$` 标记。依赖保留区间，聚合及条件函数查询实际单元格，空白计数按逻辑面积扣除非空值。线性查找在大范围内仅检查已有单元格及各空白区间的首个搜索位置，保留正反向、错误与近似候选规则；小范围保持直接读取，二分查找沿原路径。全部沿用工作量及输出限制，保留空项的超大连接仍可能原子拒绝。

结构编辑沿现有 [ONLYOFFICE 范围变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L675-L768)；范围末端贴住工作表上限，起点不固定在第一行/列。例如在 A 列前插列时，名称中的 `Sheet1!$2:$2` 变为 `Sheet1!B$2:XFD$2`，之后按名称调用位置求值，越界产生 `#REF!`。范围记法参考 [ONLYOFFICE getName](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L983-L1019)，稀疏值和空白数量参考 [cArea](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L1195-L1240)及[countCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L1326-L1335)。数组结果仍归 P14。

AND/OR 接受数值和布尔，忽略引用内的文本与空白；没有有效值时返回 `#VALUE!`。文字常量返回 `#VALUE!`，不沿用数学函数的数字转换。稀疏范围只访问已有单元格，不展开整张表；即使已有确定的布尔结果，范围和后续参数中的错误仍参与，范围内按行列顺序保留首个错误。NOT 接受布尔、数值、空白及 TRUE/FALSE 文字，其他文字返回 `#VALUE!`。三项类型判断不转换数字文字，区分空白格与空字符串；当前使用标量参数，多格范围返回 `#VALUE!`。公式结果引用空白格时计算为数值 0。

IF、IFERROR、IFNA 只求值选中的结果分支，依赖仍包含全部声明引用。IFERROR 捕获公式错误值，IFNA 只捕获 `#N/A`；两者不吞未知函数、循环、引用解析失败或资源超限。新输入及生成的 IFNA、CONCAT、TEXTJOIN、DAYS、XLOOKUP 按 OOXML 写入对应 `_xlfn.` 函数前缀，读取也接受这些前缀；只替换函数 token，保留同名工作表和文字常量。查询继续返回实际公式源。

ABS 返回绝对值，INT 向负无穷取整；MOD 按 `n - d * floor(n / d)` 计算，零除数返回 `#DIV/0!`。三类舍入按有限 Double 的十进制表示处理，ROUND 的半值远离零，ROUNDUP 远离零，ROUNDDOWN 朝零；位数的小数部分朝零截断。正负位数、进位及 `ROUND(1.005,2)=1.01` 使用同一路径，不先乘十进制倍率。精度至少 324 时保持原值；截断后的精度小于 -308 时，非零 ROUNDUP 返回 `#NUM!`，其余返回 0。结果非有限也返回 `#NUM!`，不按任意精度分配字符串。

SQRT 计算非负平方根，负数返回 `#NUM!`。POWER 接受两个标量；零的负幂为 `#DIV/0!`，零的零次幂沿所选参考返回 1。负底数的非整数幂沿 [ONLYOFFICE POWER](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L3435-L3462) 计算负候选根，再以反向幂的整数舍入结果核对底数；不成立时为 `#NUM!`。非有限结果为 `#NUM!`，下溢可为 0。标量类型转换沿既有规则。

PRODUCT 按参数顺序及引用内的行列顺序相乘，重复/重叠引用按次数计入。引用中的数字文字可转换，布尔、空白与其他文字忽略，引用错误传播；直接布尔和数字文字转换，直接非法文字返回 `#VALUE!`，空参数忽略。没有数值返回 0；中间溢出立即返回 `#NUM!`，不会被后面的零消除。行为依据 [ONLYOFFICE PRODUCT](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L3574-L3665)。

MEDIAN 对实际数值排序，偶数项取中间两项的平均值。沿 [ONLYOFFICE MEDIAN](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L8541-L8620)，引用中的文字、布尔、空白及错误均忽略；直接布尔参与，直接文字忽略，直接错误及空参数返回 `#VALUE!`。没有数值也返回 `#VALUE!`，平均值的非有限结果为 `#NUM!`。PRODUCT/MEDIAN 支持跨表、名称展开和整行/列的稀疏引用，不展开空矩阵；隐藏及筛选行仍参与。遍历与排序预付现有公式工作预算，资源超限整体回滚，IFERROR 不吞资源失败。四项均参与实际依赖、缓存及精确历史，不再使用未计算保护。实现归 [`formula-numeric.mbt`](../../modules/formats/src/xlsx/formula-numeric.mbt)及 [`formula-product-median.mbt`](../../modules/formats/src/xlsx/formula-product-median.mbt)。

数值函数复用已有数值、数字文字、布尔及空白转换；ROUND/ROUNDDOWN 的文字引用保持 `#VALUE!`，文字常量仍可转换。标量函数的多格范围返回 `#VALUE!`。实现参考 [ONLYOFFICE 数值函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js)及其独立[舍入用例](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/mathematicTests.js#L16439-L16487)。核心已检查负数、半值、进位、类型转换、有限边界、跨表重算、缓存和精确历史；默认公式栏已检查组合数值公式、依赖修改、独立 XML、保存重开及 PDF。更广浮点兼容与地区化数值解析仍归后续扩展。

LEN、LEFT、RIGHT、MID、FIND、SEARCH 使用 UTF-16 单元计数和位置，不使用编辑光标的字素计数。LEFT/RIGHT 默认取 1；MID 起点至少为 1，数量非负，小数参数朝零截断并按实际长度截取。切开代理字符对返回 `#VALUE!`，不保存无效 XML。TRIM 只折叠和移除普通空格，保留 TAB 与不换行空格。UPPER/LOWER 使用固定 Unicode 16 完整大小写映射，包含扩张及希腊词尾 Sigma，暂不提供地区化规则。

FIND 按区分大小写的字面匹配返回从 1 起的位置。SEARCH 不区分大小写，支持 `*`、`?` 与 `~` 转义；通配符沿所选旧版参考行为不跨换行。核心使用计入工作量的动态规划，避免正则回溯。SUBSTITUTE 区分大小写，按非重叠字面匹配替换；指定实例必须为正数，省略则替换全部。

EXACT 把两个标量转换为既有逻辑文字后做区分大小写的精确比较，不折叠空格或规范化 Unicode；空白格按空字符串比较，错误按参数顺序传播。REPT 接受文字和数值次数，使用既有数值转换；按 [ONLYOFFICE REPT](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/textanddataFunctions.js#L1966-L2020) 先检查原始次数在 0–32767、UTF-16 长度乘原始次数不超过 32767，再向零截断次数并重复。因此 `REPT("ab",2.9)` 为 `abab`，`REPT("ab",16383.9)` 为 `#VALUE!`，空文字配超限次数也拒绝。两项复用依赖、重算、缓存、历史及保存，不再使用未计算缓存保护；比较和输出在执行前计入公式工作预算，资源失败不被 IFERROR 吞掉。当前为标量语义，数组和隐式求交继续扩展。实现归[文本求值](../../modules/formats/src/xlsx/formula-text.mbt)，比较依据 [ONLYOFFICE EXACT](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/textanddataFunctions.js#L893-L934)及其[独立用例](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/textAndDataTests.js#L2672-L2710)。

CONCAT 按行列顺序连接范围，CONCATENATE 当前只接受标量。TEXTJOIN 的 ignore_empty 为 false 时保留首尾与中间空项，为 true 时跳过空项；分隔符范围按顺序循环使用。普通连接和忽略空项的连接只访问已有稀疏单元格。保留空项的范围先按面积检查剩余预算，再遍历，不能展开超大空矩形。

生成的文本最多 32767 个 UTF-16 单元，超过时返回 `#VALUE!`。复制、范围遍历及搜索共用既有 1048576 单位公式工作预算；耗尽返回 `limit-exceeded`，IFERROR 不吞此失败，候选源码、缓存和历史整体回滚。文本规则参考固定 [ONLYOFFICE 文本函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/textanddataFunctions.js)。MID 的无效起点与 TEXTJOIN 首部空项沿 [MID 合同](https://support.microsoft.com/en-us/excel/functions/mid-function)及 [TEXTJOIN 合同](https://support.microsoft.com/en-us/excel/functions/textjoin-function)处理，未沿用旧版参考的这两处实现缺口。现代 Excel 字符兼容版本、动态数组与更广地区化规则留待 P14。

DATE、YEAR、MONTH、DAY、DAYS 使用工作簿的 1900/1904 日期系统，返回数值。1900 系统保留序号 0 的 1900-01-00 和序号 60 的虚构闰日；1904 系统序号 0 为 1904-01-01。支持到 9999-12-31，当日的小数时间仍有效；负序号或超出末日返回 `#NUM!`。显示和计算复用核心日历转换，按有界查找确定年份，不按输入年份逐年循环。

DATE 的年参数先截断，0–1899 加 1900；月份和日期按公历归一化，显式 1900-02-29 保留虚构序号。年份必须在 0–9999，月份/日期绝对值最多 2147483647，超出返回 `#NUM!`。DAYS 按两个有效序号各自向下取整后相减。TIME 将三个参数分别朝零截断，合计非负时按 24 小时取余；非有限或负合计返回 `#NUM!`。HOUR/MINUTE 返回时分，SECOND 按参考规则舍入到整秒，不向时分进位。函数不自动改变单元格格式；默认 UI 可沿现有数字格式显示日期或时间。

提取和差值函数接受数字文字，以及明确的 `yyyy-mm-dd`、`yyyy/m/d`、`m/d/yyyy` 日期与 `h:mm[:ss[.ffffff]]` 时间，可用空格或 `T` 连接，时间可附 AM/PM。日期必须实际有效；不解释时区、月份名称或两位年份。沿所选参考的引用转换，HOUR/MINUTE/SECOND 的文本引用返回 `#VALUE!`；DAY 的引用可转换数字文字，其余日期文字引用返回 `#VALUE!`。YEAR/MONTH/DAYS 可解释上述日期文字引用。日期系统和转换都在 MoonBit 内执行，不调用宿主 Date 或当地时区。

日期与时间规则参考固定 [ONLYOFFICE 实现](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/dateandtimeFunctions.js)、[日期序号转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L4007-L4062)及独立[日期时间用例](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/dateTimeTests.js)。地区化日期解析、自动日期格式推断及更广历史兼容仍待扩展。

COUNTA 统计非空白值，包括错误和公式返回的空文字。COUNTBLANK 统计空白格及空文字，单格与矩形保持相同规则；参数必须为引用。计数按范围面积和已有单元格求得，不展开空矩阵，支持最大工作表矩形的精确计数。

COUNTIF/COUNTIFS、SUMIF/SUMIFS、AVERAGEIF/AVERAGEIFS 共用有类型的条件。条件支持 `= <> < <= > >=`；省略运算符表示等于。数值等值比较可转换数字文字，数值大小比较只使用数值。空白条件参数按 0 解释，空文字条件匹配空白及空文字。布尔条件保持类型；文字形式的错误条件可匹配相应错误值。文字比较当前使用简单 Unicode 映射和 UTF-16 顺序，地区化排序留待后续。

文字等值条件覆盖整个单元格，不区分大小写；`*`、`?` 与 `~` 转义按有界动态规划匹配，可包含换行。多条件取交集，范围行列数量必须一致，单元格位置及工作表可以不同。范围或条件数组不做隐式求交；非法形状返回 `#VALUE!`。普通条件聚合包含全部隐藏行；[SUBTOTAL](#subtotal-汇总) 区分筛选与手动隐藏。

SUMIF/AVERAGEIF 的可选结果范围从其左上角取与条件范围相同的形状；越过工作表边界返回 `#REF!`。隐含范围也进入依赖图，修改锚点之外的结果单元格会重算。已匹配结果中的数值参与求和/平均，文字和空白不参与；已匹配错误按行列顺序传播，未匹配错误不影响结果。没有数值时 SUMIF/SUMIFS 返回 0，AVERAGEIF/AVERAGEIFS 返回 `#DIV/0!`。非有限结果返回 `#NUM!`。

条件范围遍历、文字比较和通配符共用现有公式工作预算；超限整体回滚，IFERROR 不吞资源失败。实现参考固定 [ONLYOFFICE 统计函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js)、[条件匹配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L12325-L12512)与[条件求和](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L5310-L5402)。结果范围投影及错误读取同时对照 [LibreOffice 条件聚合](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/tool/interpr1.cxx#L5871-L6094)。单格空文字计数与结果范围形状沿 [COUNTBLANK 合同](https://support.microsoft.com/en-us/excel/functions/countblank-function)及 [SUMIF 合同](https://support.microsoft.com/en-us/excel/functions/sumif-function)，不沿用旧参考中单格/区域及结果矩阵尺寸的不一致。

ROW/COLUMN 返回显式引用的左上角行列，省略参数时返回公式自身位置；ROWS/COLUMNS 返回矩形行列数量，不遍历单元格。四项位置函数只校验引用身份，不依赖引用内的值，`A1=ROW(A1)` 不产生值循环。公式来源位置属于核心求值上下文，不由宿主选区决定。

INDEX 当前返回一个单元格的值，支持二维行列索引、单行/单列简写及标量输入；索引朝零截断，越界返回 `#REF!`，负索引返回 `#VALUE!`，单一区域的 area_num 必须为 1。选中空白格返回 0。零行/列仅在对应维度本来为 1 时返回单格，其余数组结果仍未支持。MATCH 接受一维引用，0 为首个精确匹配，1 为升序的最后一个不大于项，-1 为降序的最后一个不小于项；省略时为 1。精确模式支持整格通配符和转义，不把数字文字与数值等同。

VLOOKUP/HLOOKUP 在首列/首行查找，返回指定列/行的标量值；省略 range_lookup 时沿升序近似规则，false 使用首个精确或通配符匹配。无匹配返回 `#N/A`，结果索引小于 1 返回 `#VALUE!`，超出表格返回 `#REF!`。近似匹配的重复键沿最后一个符合项，精确匹配沿首项。

XLOOKUP 当前使用同形的一维查找和返回引用，默认精确查找，支持 -1/1 的最近较小/较大项及 2 的通配符模式。search_mode 为 1/-1 时正向/反向扫描，为 2/-2 时按升序/降序二分；二分不接受通配符模式。二分和旧式近似模式要求输入已有正确排序，不替用户排序。未命中时才求值 if_not_found；省略或显式空参数返回 `#N/A`，查找值、查找过程和选中结果中的错误保留类型，不被回退值覆盖。

查找共享既有文字比较与工作预算，二分直接读取稀疏地址；线性或通配符工作超限整体回滚，IFERROR 不吞失败。值依赖目前保留声明的范围和回退分支；动态引用、引用形式 INDEX、整行/列返回及其他数组结果仍待扩展。实现参考固定 [ONLYOFFICE 查找引用函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/lookupandreferenceFunctions.js)及独立[位置与查找用例](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/lookupAndReferenceTests.js)。当前范围是标量计算，不授予完整数组或动态引用兼容。

逻辑、类型和扩展函数前缀参考 [ONLYOFFICE 逻辑函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/logicalFunctions.js)、[类型函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/informationFunctions.js)及[公式序列化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L3586-L3587)。范围迭代和错误参与与固定 [LibreOffice ScAnd/ScOr](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/tool/interpr1.cxx#L1234-L1413)交叉核对。独立用例覆盖类型、空白、错误、跨表重算、缓存、精确历史及失败；默认公式栏已检查组合公式、依赖变化、独立 XML、保存重开和 PDF。

首次打开计算支持的公式，编辑只重新求值受影响公式。首次有效事务同步与已计算结果不同的导入缓存，包括未受本次输入影响的陈旧缓存；无编辑打开不写回。语法、越界引用、未支持公式、新建循环和预算超限整体拒绝；除零等是带类型的公式结果。共享公式按锚点派生；编辑命中组时有界展开该组，其他组保留。

结构化/外部/三维引用、数组、动态数组、易变函数及迭代计算未支持。依赖无法确定、函数参数语义未核实或存在原有循环时，整个工作簿只读。公式不访问网络、宏或宿主脚本。

导入的 SUMSQ 尚不求值，但已核实只读取显式参数，沿既有语法和名称展开建立静态依赖。保留其源码和导入缓存，依赖它们的公式也标为未计算。核心只把实际求值的结果放入 `calculated`，缓存不参与新的公式、条件格式、验证或筛选计算。每格新增 `calculationReason`：已计算/普通值为空，未计算时说明未支持函数或上游位置。默认公式栏显示原因；有缓存时显示缓存，缺缓存显示未计算。选区含未计算公式时，计数仍可读，四项汇总均为 null 并给出原因。

所有源提交先比较未计算链的源码、展开表达式、稳定表身份、依赖矩形及参数值。新增的稀疏参数格也参与；嵌套 SUBTOTAL 另检查手动隐藏与筛选来源。相同参数下可编辑无关值、已支持公式、格式和视图，并沿原有重算、源事务、预算与精确历史保存；会改变该链或参数的输入、结构/名称及可见性操作原子拒绝。新增未支持公式及 CSV/TSV 公式转换继续拒绝。其他未核实函数、INDIRECT/OFFSET、CELL 等环境/格式查询、自定义函数及其嵌套继续整本保护。未计算函数的参数行为参考固定 [ONLYOFFICE SUMSQ](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L5732-L5797)；保护实现在 [`calculation-protection.mbt`](../../modules/formats/src/xlsx/calculation-protection.mbt)。

未计算公式即使有缓存也不能作为计算结果打印；只含已计算内容的独立打印区域可输出。XLSX 原格式保存保留未计算公式及缓存，CSV 值导出沿既有有缓存才可导出的合同，不赋予缓存已计算状态。

### 名称引用

已有 `definedNames` 可用于单元格、条件格式和数据验证中的受支持表达式。名称不区分大小写，支持 Unicode 名称、工作簿/工作表作用域、常量、矩形及整行/整列引用和表达式组合。单元格中的未限定名称先查当前表，再查工作簿；`'表名'!名称` 先查指定表，再查工作簿。名称定义内部的未限定名称查工作簿作用域，局部名称须显式指定表；这沿用 ONLYOFFICE 的独立定义解析上下文。`localSheetId` 决定名称的查找范围，不为定义内部的单元格引用绑定工作表。

定义中的单元格引用须包含工作表。绝对行列保持固定，相对行列以 A1 为原点，按使用该名称的单元格偏移。展开后复用现有表达式、依赖图、范围函数、增量计算、规则及缓存事务。未定义名称产生 `#NAME?`，仍可继续编辑；命名循环、未支持表达式与超预算候选原子拒绝，导入后沿既有只读规则保留源和缓存。未使用的复杂定义不参与求值。

最多读取 4096 个定义，名称和定义合计不超过 1,048,576 UTF-16 单元；每条公式仍限 8192 单元，展开受 64 层表达式深度及现有工作预算保护。名称目录另计入重复的作用域身份，总计同样不超过 1,048,576 单元；目录超限返回保护原因，新增候选在提交前拒绝。名称源不会被展开结果替换。绝对、相对及混合定义的显式工作表引用随行列/单元格结构、表改名/复制/删除及局部作用域索引一起更新，精确历史和重开复用原路径。结构操作在定义保存的坐标上变换一次，保留 `$`、公式文字及非目标源；使用名称的单元格仍保存名称，不写入展开后的引用。删除完整目标时定义写为 `#REF!`，依赖与缓存一起重算。局部单元格移位沿既有范围交集规则，保留未覆盖的跨带引用。

相对定义在求值时按实际调用格偏移。同表调用格随结构移动后，使用新位置；跨表调用格保持自己的位置。例如 `Items!$A2` 在 `Items!E2` 调用时读 A3；在第 2 行上方插行后，定义为 `Items!$A3`、调用格为 E3，读取 A5，其他表的 E2 则读取 `Items!A4`。这是定义坐标和调用位置各自变化的结果，不额外补偿调用方。未限定工作表的单元格引用、需改写的不透明源及预算失败仍原子保护。规则中的名称复用同一候选定义与求值上下文。

`XlsxQuery.names` 返回 `entries` 和整体 `readOnlyReason`。每条名称包含 `name`、`scope`、原始 `formula`、`hidden` 及单项 `readOnlyReason`。`scope` 是稳定工作表部件身份，`null` 表示工作簿。默认名称面板与自定义 UI 共用下列 `editSheet` 命令：

| 命令 | 行为 |
| --- | --- |
| `{ action: "name", original, name, scope, formula }` | `original: null` 创建名称；否则按原名称和作用域修改定义或改名。编辑期间保持作用域，定义可带 `=` 前缀 |
| `{ action: "nameDelete", name, scope }` | 删除定义，保留单元格公式中的名称，重新计算为 `#NAME?` 或剩余作用域的值 |
| `{ action: "nameSelect", name, scope }` | 解析为单个矩形后定位到目标表，复用合并格、隐藏表和选区查询边界；不写源、不增加 revision 或历史 |

名称最多 255 UTF-16 单元，允许字母、Unicode 标记及既有名称字符；A1/R1C1 地址、R/C、布尔常量和 `_xlnm.` 系统名称不接受管理修改。新定义先检查语法、支持的函数、作用域及循环，再构造候选。一次增改删同步重算、缓存、尺寸与精确历史，重复设置不产生历史；新定义的可选 `=` 前缀不要求改写相同的导入源。改名按原作用域绑定同步单元格、共享公式锚点、规则、内部链接和其他定义，保留字符串、共享组和元数据。全局改名会被已有局部名称遮蔽时明确拒绝。源文本中的未知标记、资源引用或工作预算不能安全处理时，候选整体拒绝。

名称面板可从当前选区生成带表名的绝对矩形，也可输入常量或表达式。命令先提交原生单元格草稿；定位按当时焦点解析相对定义。常量和计算表达式不能作为矩形定位，隐藏目标表须先显示。导入的未支持语法或系统定义保留并显示保护原因，普通命令不改变隐藏属性。多区域、整行整列、作用域迁移和更广定义兼容另行扩展。

实现归 [`named-definitions.mbt`](../../modules/formats/src/xlsx/named-definitions.mbt)与 [`name-edit.mbt`](../../modules/formats/src/xlsx/name-edit.mbt)。作用域、定义上下文和相对偏移参考 [ONLYOFFICE DefName](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L457-L512)及 [cName](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L2173-L2262)。管理事务和改名绑定参考 [editDefinesNames](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L1086-L1125)及 [changeDefName](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L2261-L2275)。

结构变换参考 [ONLYOFFICE 名称公式通知](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L559-L574)及[按保存引用移动](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L10152-L10281)，实现复用 [`axis-reference.mbt`](../../modules/formats/src/xlsx/axis-reference.mbt)和 [`axis-metadata.mbt`](../../modules/formats/src/xlsx/axis-metadata.mbt)。

### 冻结窗格

`editSheet({ action: "freeze", rows, columns })` 冻结起始的指定数量行列，`0, 0` 取消冻结。`rows` 为 0–1048575，`columns` 为 0–16383 的整数。`XlsxQuery.frozen` 返回数量和 `readOnlyReason`。默认属性栏提供首行、首列、所选范围之前及取消冻结；命令沿队列先提交原生草稿。RTL 视图的起始列位于右侧。

核心修改主窗口 `sheetView` 的 pane 和 selection，保留视图属性、注释及其他窗口的源内容。一次操作进入既有历史，相同数量不增加历史；预算或保护失败保持原状态。操作不改变单元格、样式、公式缓存、calcChain 或打印。工作簿窗口保护和未知视图元数据阻止修改，未知公式继续遵循既有只读边界。

网格读取普通 LTR/RTL 的 `frozen` / `frozenSplit` 视图；普通 split 仍拒绝布局。一个 R0 区域内最多绘制四个裁剪窗格，共享 4096 格和 262144 UTF-16 文字预算；核心负责命中、滚动定位及合并格跨边界。`XlsxViewport.cells[].clip` 给出所属窗格，合并格按地址去重。`XlsxSelectionGeometry` 保留锚点矩形并返回最多四个 `rects`；覆盖层绘制这些矩形，原生输入受所属窗格裁剪。

### 工作表网格线与标题

`editSheet({ action: "view", gridLines, headings, rtl, formulas })` 设置当前表的网格线、行列标题、RTL 方向和公式显示，四项均为布尔值。`XlsxQuery.view` 返回这四项及 `readOnlyReason`。默认属性栏的四个开关调用相同命令，先提交原生草稿。主窗口缺省显示网格线/标题，采用 LTR 和计算结果；读取 `0/1/false/true`。修改只写变化的属性，保留其他窗口、窗格、选区和未知部件。缺少主窗口时创建。相同设置不增加历史，失败不提交部分结果。

核心同时调整绘制、滚动范围、冻结窗格、命中和选区。`XlsxViewport.headerWidth/headerHeight` 在显示标题时为 `36/18` pt，隐藏时为 `0/0`，并返回空的标题行列数组。`rtl` 为真时，行标题和起始列在右侧；所有矩形仍使用画布左上角坐标，`scrollX` 始终是从起始列向后的非负距离。Web 换算 Chromium 的 RTL 滚动值，并沿核心矩形绘制覆盖层和定位原生输入；无标题时仍保留可访问的单元格语义。

RTL 改变列排列，不镜像字形，也不改变单元格值、格式、计算缓存和 calcChain。网格方向键按视觉左右移动；Tab/Shift+Tab 沿逻辑列次序前进/后退，原生草稿的文字方向键保持浏览器行为。程序化 `navigate` 的左右继续表示逻辑列方向。打印使用相同列方向、分页与重复标题，在页边距和缩放内排列单元格；页眉页脚保留各自对齐。网格线和行列标题开关不改变打印，隐藏网格线也不隐藏显式边框。

`formulas=true` 保存主视图的 `showFormulas`，网格、查询 `display`、可访问单元格及 PDF 显示带 `=` 的逻辑公式源。共享公式沿现有展开规则显示，原共享源与缓存保留。物理列宽加倍，隐藏列仍为零，行高和源列宽不变；冻结、RTL、命中、选区及打印使用相同尺寸。数值不再因过窄显示井号；常规对齐及数值采用左对齐，其他显式文字对齐保留。非公式数值显示编辑形式：一般数值不强制补位或分组，百分比保留 `%`，日期/时间使用固定 ISO 日期及 24 小时时间，不使用宿主区域设置。

自动适配测量当前显示文字，并将物理宽度换回源字符宽度；后续原生输入沿既有自动尺寸事务更新。统计、筛选及 CSV/TSV 值输出继续使用实际计算值。公式显示不写公式结果缓存，也不移除 calcChain。受保护表的隐藏公式在公式视图中不显示，公式栏输入为空，查询 `formula` 为 `null`；隐藏标记读取本地及基础样式，显式保护覆盖沿 `applyProtection` 解释。源包保留，支持正常保存和计算。

操作沿冻结窗格的普通视图和保护边界执行。窗口保护、未知视图元数据及既有未知公式只读边界仍会拒绝修改。普通分割窗格及辅助诊断仍待实现。行为参考 [ONLYOFFICE 显示开关与方向事务](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L8020-L8094)、[公式视图文字](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9493-L9674)、[编辑文字与保护](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L16152-L16252)和 [WorksheetView.checkRtl](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L27778-L27812)。

### 输入与保存

CSV 输出拒绝 SpreadsheetML 转义产生的 NUL 等非 XML 控制字符，保留原工作簿。

`XlsxSession.importDelimited(bytes, delimiter, budget, options = {})` 与 `XlsxClient.importDelimited` 创建一张新工作表，分隔符明确为 `","` 或 `"\t"`。只接受 UTF-8，可带 BOM；引号字段、双引号转义及字段内 CR/LF 保留。不等宽行按实际字段写入，导出时补空字段到矩形。`XlsxDelimitedOptions` 的 `numbers`、`dates`、`formulas` 均默认 false，字段默认完整保留文字。默认 XLSX UI 的文件入口接受 `.csv/.tsv`，按后缀选择分隔符，显示每次重置的转换选项，导入后改用 `.xlsx` 文件名并等待首次保存。宿主可在 `EditorDocument.delimited` 指定同一组选项；非 CSV/TSV 输入不接受此属性。取消选项或导入失败保留旧文档。

`numbers` 采用既有核心有限数值解析，前导零会消失；布尔及单引号前缀仍为文字。`dates` 采用核心 1900 日期系统，接受四位年份的数字 ISO/美国日期及可选时间、独立时间；非法日期仍保留文字。日期、时间和日期时间分别持久化 `yyyy-mm-dd`、`hh:mm:ss`、`m/d/yy h:mm` 格式，后者显示到分钟但保留秒与小数。日期列过窄时沿现有规则显示 `######`，可用列宽自动适配。`formulas` 仅把原文首字符为 `=` 的字段交给既有公式解析和计算引擎，写回源公式与结果缓存；不支持的公式、循环或预算失败拒绝整次导入。有效公式错误结果保留为错误值。导入初始 revision 为 0，无撤销历史；后续编辑沿正常历史重算。数字/日期分类与样式参考 [ONLYOFFICE CellFormatController](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Sheets/Reader/CellFormatController/CellFormatController.cpp#L136-L280)，默认文字及显式执行是本 SDK 的策略。

导入最多 4 MiB 文件、1048576 UTF-16 单元、65536 字段与 16384 列，每格最多 32767 UTF-16 单元，并受既有 OPC 预算约束。空字段和行列位置保留；不支持的编码、引号结构、非法 XML 字符或预算失败不产生可用的半份工作簿。

`XlsxSession.exportCsv(revision, selection = false)` 与 `XlsxClient.exportCsv` 输出 UTF-8 CSV 字节；宿主 `SpreadsheetEditor.exportCsv(selection = false)` 先提交原生草稿，返回上述 `EditorOutput`。false 导出当前表从 A1 到已用边界的矩形，true 导出当前选区，均最多 65536 格。输出原始逻辑值、布尔值与已计算/缓存公式结果，空合并延续格输出空字段，不导出公式、样式、其他表或图形。公式没有可信结果时拒绝，不伪造空值。

CSV 采用 CRLF 行尾，含逗号、引号、CR/LF 的字段加引号，内部引号成对转义。文字去前导空白后以 `= + - @` 开头，或原文以 Tab/CR/LF 开头时，加一个单引号防止外部表格执行；负数值保持数值。该单引号在文字模式重导入时保留。输出最多 4194304 UTF-16 单元并受 outputBytes 限制。默认文件菜单明确提示范围、格式损失和文字前缀策略，CSV 输出不确认 XLSX 已保存。引号/分隔符行为参考 [ONLYOFFICE CSVReader](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Sheets/Reader/CSVReader.cpp#L328-L366) 和 [CSVWriter](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Sheets/Writer/CSVWriter.cpp#L907-L925)；安全前缀为本 SDK 的明确策略。

前导 `=` 进入公式，单引号强制文字。未做日期自动识别与地区化输入推断。TSV 粘贴保留以 `=` 或单引号开头的文字，其余字段由核心识别数值、布尔或文字。CRLF/CR 统一为 LF，支持带引号的字段、字段内换行和双引号转义；不等宽行或未闭合引号拒绝。矩形写入、粘贴和清空与任意合并区域相交时拒绝，单格按锚点修改。

候选源片段、依赖、计算缓存和历史一起提交。新文字使用内联字符串；共享字符串顺序不变，同步计数。保存保留非目标源内容，移除失效 `calcChain`、其关系与 content type，并设置 `calcPr` 重算属性。输出重新检查 OPC 完整性；失败保留会话，不返回部分文件。不承诺整个 ZIP 字节相等。

`SpreadsheetEditor` 持有一个原生 textarea 草稿。双击/F2 编辑，Enter/Tab 提交并移动，Shift+Enter 在草稿内换行，Esc 取消。草稿开始与导航进入同一队列，快速输入绑定确认后的单元格，保留原生文字与选择。离格或切表先提交；错误保留草稿与旧值。组合结束只更新草稿，提交产生一项历史。草稿中使用原生文本撤销，退出后使用核心工作簿历史。保存/打印等待命令队列，组合未结束拒绝输出。外部 revision 冲突需取消草稿并刷新，不覆盖外部修改。

屏幕使用固定视口 Canvas 与独立覆盖层。滚动/尺寸/缩放请求按动画帧合并，过期结果丢弃；成功几何、文字和轮廓在预算内复用。选区只更新覆盖层。可见单元格提供有界 grid 语义、地址、值和只读原因，保留焦点和键盘入口。调用者拥有 client 生命周期；关闭 editor 后另行关闭 client。

`SpreadsheetEditor.formulaBar` 是可挂载的稳定 DOM 节点。默认 UI 在网格上方展示公式栏和范围框。公式栏显示核心的 `cell.input`；编辑时与网格使用同一个原生 textarea，另一处显示只读镜像。切换保留草稿、目标、光标和原生撤销；组合期间不移动节点。Enter/Tab、Esc、草稿错误、切格和输出继续遵循上述队列和屏障；关闭编辑器时移除公式栏。自定义宿主可挂载该节点，组合期间保持挂载；未挂载时继续使用网格输入。

`XlsxQuery.selection.address` 返回当前选择的规范 A1 地址或矩形地址。默认范围框将输入交给既有 `select`；选择只改变运行时范围和滚动，不新增文档历史。无效或倒序地址保留原选择，已有草稿先沿队列提交。当前范围框仅定位当前表的单格或矩形，名称和跨表定位仍归 [P11](../p11-xlsx-core.md)。

### 打印与资源边界

`editSheet({ action: "pageSetup", paper, orientation, left, top, right, bottom, scale, fitWidth, fitHeight })` 保存当前工作表的打印设置。`XlsxPrintSetup` 的纸张为 `A4` 或 `Letter`，方向为 `portrait` 或 `landscape`，边距为 point。边距须非负并在每个方向留下至少 12 pt 可打印空间；比例为 10–400 的整数，横/纵页数为 0–1024 的整数。0 表示该方向不限页数；任一页数非零时取代百分比，核心按实际行列分割，在 10%–100% 中求满足页数的最大整数比例。10% 仍不能满足时输出失败，不截断内容。页面与缩放范围参考 [ONLYOFFICE calcPrintScale](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L4580-L4808)。

`XlsxQuery.printSetup` 返回上述设置及 `readOnlyReason`。修改 `pageMargins`、`pageSetup` 和 `sheetPr/pageSetUpPr`，按 XML 顺序创建缺失节点，保留其他部件、单元格、公式缓存及计算链。边距写回 inch，查询和排版统一使用 point；新页边距包含 header/footer 的标准字段。一次设置一项历史，保持选择，重复设置不增加历史。保护、旧 revision、未知打印属性或预算失败保持源和历史。未知设置返回保护原因，其查询字段使用默认值占位，不能视为源文件的实际设置。

`editSheet({ action: "printRange", area, rows, columns })` 保存单个矩形打印区域及重复标题。`area` 使用当前表 A1 矩形，`rows` 使用整行区间（如 `1:2`），`columns` 使用整列区间（如 `A:B`）；各字段留空即清除该设置。接受绝对引用和小写列名，核心返回规范形式。`XlsxQuery.printRange` 返回这三个字段及 `readOnlyReason`，类型为 `XlsxPrintRange` 加保护原因。受保护源的空字段是查询占位，不能当作实际设置。

核心写入 `workbook/definedNames` 中带 `localSheetId` 的 `_xlnm.Print_Area` 和 `_xlnm.Print_Titles`，保留其他名称、已有名称属性、工作表源及计算缓存。改名、复制、重排和删除沿已有名称引用事务同步；名称中的空格、逗号和单引号按工作表引用规则处理。一次设置一项精确历史，重复设置不新增历史；旧 revision、表/工作簿结构保护及源/输出预算失败原子拒绝。重复或无作用域的打印名称、跨表定义、非连续多区域和含未知内部标记的定义暂时保护。

重复标题只补当前页起点之前的行列，和正文重合时绘制一次。标题可在打印区域之外；隐藏行列保持隐藏。分页和适合页数都预留标题尺寸，过大的标题明确失败；不截掉标题来满足页数。该行为参考 [ONLYOFFICE 打印标题分页](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L3286-L3390)及[名称写回](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L23501-L23556)。

`editSheet({ action: "headerFooter", ...settings })` 保存纯文字页眉页脚，查询为 `XlsxQuery.headerFooter`，类型为 `XlsxHeaderFooter` 加 `readOnlyReason`。设置包含六个字符串 `oddHeader/oddFooter/evenHeader/evenFooter/firstHeader/firstFooter`，四个布尔值 `differentFirst/differentOddEven/scaleWithDoc/alignWithMargins`，以及 point 距离 `headerMargin/footerMargin`。默认六段为空，首页/奇偶页不区分，随表缩放并对齐边距，距纸张上/下边缘均为 21.6 pt。距离可设 0–14400 pt，实际文字越出纸张时打印失败。

每段最多 255 UTF-16 单元；留空清除。支持 `&L`、`&C`、`&R` 切换左、中、右部分，`&P` 为页码，`&N` 为本次输出总页数，`&A` 为当前表名，`&&` 为普通 `&`。未指定部分时居中，支持换行，CR/CRLF 规范为 LF。文字使用工作簿 Normal 字体、字号和黑色。字体、装饰、图片、日期/时间及文件字段控制码暂时保护，不能静默丢弃。源 `useFirstPageNumber/firstPageNumber` 可指定正整数页码起点；首页与奇偶模板按实际输出页序选择，不随起始页码改变。字段与模板语义参考 [ONLYOFFICE HeaderFooter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/HeaderFooter.js#L72-L123)及[页眉页脚绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L5301-L5405)。

六段与标志写入工作表 `headerFooter`，距离写入 `pageMargins` 的 inch 字段。缺失节点按源顺序创建，保留其他边距、根注释、单元格、计算缓存和非目标部件；重复设置不增加历史。表保护、未知标记、旧 revision、预算失败均不提交部分结果。未知源查询返回保护原因和默认占位值。页眉页脚沿核心字体与有序图元输出，随表缩放时仍保留物理边距和距离；关闭边距对齐时使用 17.8 mm 左右边距。页眉页脚按保存的位置绘制，不移动正文；距离和正文边距可产生重叠，越出纸张则拒绝输出。默认 UI 和自定义 UI 使用同一事务与输出屏障。

`SpreadsheetEditor.printLayout()` / `exportPdf()` 默认传递 null，打印当前表并使用已保存的纸张、边距和缩放。没有源设置时，核心默认 A4 纵向、四边 36 pt 和 100%。默认范围优先使用各表保存的打印区域，没有定义时使用该表有内容的矩形。`PrintOptions` 可单独给出 `range`、`sheets`，或一起给出六个临时 point 纸张字段 `width/height/left/top/right/bottom`；纸张字段必须全部提供。临时纸张和范围应用到每个目标表，保存的缩放、重复标题及页眉页脚继续适用。`checkPrintOptions` 校验同一边界。

`{ sheets: "visible" }` 打印全部可见表，`{ sheets: [id, ...] }` 打印指定的可见表，按当前工作簿顺序合并；列表顺序不改变工作簿顺序。列表须含 1–256 个不重复的稳定表身份，未知或隐藏表明确拒绝。各表保留自己的页面尺寸、缩放、打印区域、重复标题和页眉页脚；空表仍生成一页。页码起点及首页/奇偶模板在切表时重新开始，`&N` 使用整次输出的总页数。整体分页与字段语义参考 [ONLYOFFICE 工作簿打印](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorkbookView.js#L4144-L4200)及[切表后的页码](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L3978-L4002)。

多表共用 32768 格与 1024 页上限，不按表重新分配预算。任一目标表失败，整次输出失败，源、历史、活动表、选区及已有成功预览保持。`XlsxPrintLayout.sheet` 仍是请求时的当前表身份，不表示所有输出页来自同一表。默认 UI 提供全部可见表预览、跨表翻页、全部可见表 PDF 和当前表 PDF。导出其他范围时保留已显示的预览及其页码；PDF 不确认原 XLSX 已保存。

编辑会关闭旧预览，隐藏网格不再触发布局失败。参数草稿在普通命令繁忙时保持可编辑，提交仍等待队列，组合输入和文档切换继续阻止操作。

各表分页先向下再向右，沿行列边界分割；空表一页，超宽单列、超高单行、跨页/范围/标题边界合并、未计算公式、未支持显示或未呈现内容明确拒绝。网格和打印共享字体与尺寸，缩放在核心有序图元中完成。屏幕滚动、缩放和 DPR 不改变打印布局。各表仍限一个矩形；非连续多区域和更多纸张/布局变体继续实施。标题计入轴和单元格上限，标题与页眉页脚都计入每页文字上限。

继续使用前文文件、字体、输出与 Canvas 上限，另有以下操作上限。载荷计数不代表进程峰值或性能保证。

| 对象 | 上限 |
| --- | --- |
| 工作表 / 实际单元格 / 样式 | 256 / 100000 / 4096 |
| 单格文字 / 全部文字或共享字符串载荷 | 32767 UTF-16 / 4 Mi UTF-16 |
| 单次查询、写入、剪贴板、视口 | 4096 格；编辑/剪贴板 1 Mi UTF-16；可见文字 262144 UTF-16 |
| 合并区域 / 单个共享公式组 | 1024 / 4096 格 |
| 公式 | 单格 8192 UTF-16、4096 token；语法深度 64；依赖链 256；工作簿源码 1 Mi、引用 32768、一次计算工作量 1048576 |
| 历史 / 队列 | undo+redo 共 100 项、4 MiB 源补丁 payload；宿主 64 项 |
| 打印 | 整次输出 32768 格（含重复标题）和 1024 页；每表单轴 4096 项；每页继续受绘制文字/单元格上限约束 |

当前范围不含模板向导、高级筛选、图表/透视表/图片编辑和协作。工作表/行列、格式、填充与普通区域排序的当前支持面见本节对应合同。XLS/XLSB/XLSM、其他浏览器、Windows/Excel、VoiceOver、性能专项与发布验收未进入本期验证。

## PPTX

`PresentationEditor.editSlides({ action: "size", width, height })` 修改全稿尺寸，单位为 pt，每边 1–14400，核心取整到 EMU。默认 UI 提供 16:9、4:3 和自定义宽高。`query.width/height` 返回实际尺寸，`slideSizeReason` 返回保护原因。各轴按新旧尺寸比例缩放全部页面及关联版式、母版的本地位置与尺寸；组的子坐标原点、范围及成员同时缩放。字号、描边宽度、旋转/翻转、对象身份、选择与其他资源保持。该规则依据 [ONLYOFFICE Presentation.changeSlideSizeFunction](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L805-L850)、[Shape.changeSize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L3235-L3266)和 [GroupShape.changeSize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L789-L805)。

尺寸、页面和设计部件合为一次有界历史。相同实际尺寸不新增历史；旧 revision、活动候选、保护、坐标越界和输出/历史预算失败原子拒绝。图表/表格等未知页面对象、未知变换坐标和非空参考线暂时保护尺寸调整。未知部件与原有源片段保留。保存重开及 Canvas/PDF 使用相同的新尺寸和几何；反复改变比例可能产生 EMU 取整，撤销恢复原始源字节。

页面背景使用 `PresentationEditor.editSlides({ action: "background", value }, slide?)`。`value` 是 `PptxBackgroundFill`：纯色为 `{ kind: "solid", color }`，线性渐变为 `{ kind: "linear", startColor, endColor, angle, scaled }`，颜色均为不带 `#` 的六位 RGB。`null` 移除本页背景并恢复版式、母版继承。`query.background` 返回有效 `value`、本页是否设置 `explicit` 与保护原因 `reason`；没有背景时返回白色纯色。`value` 的查询类型为 `PptxBackground`，还包含下节的图片背景；两个类型均由 `wasm/pptx` 和 `web/pptx` 导出。核心使用 `BackgroundFill`。

渐变使用位置 0 和 100000 的两个不透明色标。`angle` 为顺时针 0–360 度，核心舍入到 1/60000 度并把 360 规范为 0；0 从左至右，90 从上至下。`scaled` 必须为布尔值；true 按页面长宽比调整角度，false 保持实际角度。导入可解析主题/系统颜色及已有明暗变换，保留未改源；透明度、多色标、非端点色标、路径渐变、非零平铺矩形和复杂效果继续保护；图片背景见下节。有效背景随版式/母版继承，复制页与尺寸调整沿相同解析；修改背景不改对象身份或几何。角度规则依据 [ONLYOFFICE getGradientPoints](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/editorscommon.js#L15290-L15511)。

操作复用 revision、候选保护、输出预算和精确撤销重做；本页已有相同有效背景时为无操作。默认面板提供背景类型、两色/角度/比例设置和恢复继承；原生文字编辑保留尚未应用的背景草稿。核心复用现有矩阵与水平渐变原语生成任意方向，Canvas/PDF 不解析 DrawingML。12 项定向核心、两条 Chromium 流程检查继承、方向/比例、源保真、历史、重开输入、真实 Canvas 颜色及独立 PDF 渲染颜色。其他背景与母版编辑仍待实现；主题颜色和字体见下节。修改本页背景的语义参考 [ONLYOFFICE Slide.changeBackground](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L825-L829)，实现归 [`background-fill.mbt`](../../modules/formats/src/pptx/background-fill.mbt)和 [`slide-background.mbt`](../../modules/formats/src/pptx/slide-background.mbt)。

### 图片背景

`PresentationEditor.editSlides({ action: "backgroundImage", bytes, mode }, slide?)` 设置或替换本页 PNG/JPEG 背景，`mode` 为 `stretch` 或 `tile`。Wasm/Worker 使用同一 `editPptxSlides` 命令。输入沿图片写入上限：4 MiB、单边 4096 像素及总计 4 Mi 像素。原图片字节、关系、内容类型和背景源合为一次有界事务；保留对象、选择与非目标部件，支持精确撤销/重做、页面复制及保存重开。重复设置相同本地图片及模式不增加历史，旧资源继续保留，不做包清理。

`{ action: "backgroundImageFormat", mode, crop, opacity }` 一次设置已有图片背景的模式、四边裁剪和不透明度，保留资源键及已有平铺参数。`crop: [left, top, right, bottom]` 为移除源图的比例，各项非负且小于 1；核心按 1/100000 舍入，两侧之和须小于 1。`opacity` 为 0–1，使用相同精度并乘上源像素 alpha。四个零移除裁剪，1 移除常量 alpha 覆盖；本地有效同值不增加历史。`tile` 保留非零裁剪，绘制整张源图；切回 `stretch` 后重新应用原裁剪。平铺沿用已有参数或标准默认值，也可在一次命令中重置裁剪并切换模式。继承图片可创建本页覆盖，继续复用原资源；本地替换只修改图片引用，格式编辑只修改变化的 `stretch/tile`、`srcRect` 和 `alphaModFix`；保留 `dpi/cstate/rotWithShape` 等已识别源属性、已有图片关系和其他部件。`{ action: "background", value: null }` 恢复继承，受支持的纯色/渐变命令也可替换图片背景。默认背景面板提供类型、图片、模式、四边百分比、裁剪重置、不透明度及恢复继承，格式一次应用并进入同一历史；文件读取绑定目标页，读完后检查目标是否改变。

`query.background.value` 的图片分支为 `{ kind: "image", key, crop: [left, top, right, bottom], opacity, mode }`，其余分支仍为纯色与线性渐变。`key` 是核心图片资源身份，`crop` 是非负源裁剪比例，`opacity` 为 0–1。按幻灯片、版式、母版顺序选择背景，并按实际来源部件解析内部图片关系；主题 `bgRef` 也按主题部件解析。导入保留 `srcRect` 和常量 `alphaModFix`，替换图片继续保留这些值；格式候选沿用原资源和整页裁剪，不生成图片副本。缺图片、非法模式/数值、舍入后空源区域、未知源及预算失败保留源、选择和历史。拉伸展开后的宽高各不超过 1e9 pt；平铺的未生效裁剪不参与这个展开检查，切回拉伸时重新验证。

背景先铺白底，再裁剪到整页并使用既有图片图元，前景对象随后绘制。拉伸以有效源矩形覆盖页面；平铺复用[形状图片](#形状图片填充)的 96 DPI、缩放/偏移、九种对齐及交替翻转，保留但不应用源裁剪。背景、形状填充和独立图片合计每页最多 65536 格；写入、模式、尺寸及变换候选先验证此上限。背景图片计入全稿 256 项使用中图片及既有字节/历史预算，预览、PNG 和 PDF 使用同一资源清单。外链、非零目标内缩和未知效果继续保护；不抓取外部图片，也不删除未知源来替换背景。

源矩形复用 [ONLYOFFICE 图片裁剪系数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L946-L960)，读取与绘制顺序参考 [ONLYOFFICE 背景继承](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L1260-L1322)、[背景图片资源](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L1134-L1151)及[背景先于对象绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L1416-L1451)，未复制上游源码。实现归[背景图片](../../modules/formats/src/pptx/background-image.mbt)、[图片事务](../../modules/formats/src/pptx/object-image.mbt)和[共用平铺](../../modules/formats/src/pptx/shape-tile.mbt)。

### 主题颜色

`PresentationEditor.editSlides({ action: "themeColor", slot, color })` 与 Wasm/Worker 的 `editPptxSlides` 修改主题颜色。`slot` 为 `PptxThemeSlot`：`dk1/lt1/dk2/lt2`、`accent1`–`accent6`、`hlink/folHlink`；`color` 为不带 `#` 的六位 RGB，核心规范为小写。普通视图按 [ONLYOFFICE changeColorScheme](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9766-L9798) 的范围，同步修改文稿所有页面实际引用的主题，每个部件仅改一次；不修改未使用的主题。默认面板说明此范围，提供颜色项和颜色选择。

`PptxQuery.themeColors` 返回十二个 `PptxThemeColor`，每项含 `slot/color/reason`。全部使用中主题的有效颜色相同时返回 RGB，混合时返回 `null`；不能安全编辑时给出原因。类型从 `wasm/pptx` 和 `web/pptx` 导出。支持普通 `srgbClr` 和 `sysClr.lastClr`；选择新颜色时写为显式 sRGB，相同有效值保持原系统颜色源。含颜色变换、未知属性/子节点、注释或处理指令的目标色项仍保护；一处受保护即拒绝整次修改。其他色项、字体、额外配色、扩展及未改部件原样保留。

核心重新解析所有依赖页，背景、形状、描边、文字和列表的主题引用继续使用原颜色映射及明暗变换；直接 RGB 覆盖、对象身份、几何和文字选择保持。原生文字草稿先独立提交；主题部件和派生页面共用一次有界历史。撤销/重做重新派生依赖颜色，不只恢复 XML。相同颜色无操作，旧 revision、活动候选、输出/历史预算及保护失败原子拒绝。保存重开和 Canvas/PDF 沿相同布局路径。主题字体见下节；主题包应用、母版/版式直接编辑及复合对象仍按 P12 后续批次实施。实现归 [`theme-edit.mbt`](../../modules/formats/src/pptx/theme-edit.mbt)及 [`pptx-theme.tsx`](../../packages/ui/src/pptx-theme.tsx)。

### 主题字体

`PresentationEditor.editSlides({ action: "themeFont", kind, script, font })` 沿主题颜色的全稿使用中主题范围修改字体定义。`kind` 为 `major`（标题）或 `minor`（正文）。`script` 为 `latin/ea/cs`，或区分大小写的四字母脚本代码，如 `Hans/Arab`。`font` 使用实际字体族，最多 200 UTF-16 单元，遵循字符字体的合法性规则；Latin 不能为空，其他类别的空串恢复补充脚本或 Latin 回退。缺少的非空定义按 Latin、EA、CS、补充字体顺序插入，保留扩展和其他文字类别；清除不存在的定义无操作。默认面板可选择已有类别或输入新代码，新增项撤销后面板仍可继续操作。

`PptxQuery.themeFonts` 返回 `PptxThemeFont[]`，每项包含 `kind/script/font/reason`。`font` 为原始定义，跨主题混合时为 `null`；不存在的定义为空串，保护原因独立返回。两种用途合计最多 256 项。新字体和查询类型沿 `wasm/pptx`、`web/pptx` 导出。所有 `editPptxSlides` 请求携带字体 `profile`，Web 编辑宿主自动传入自己的映射。MoonBit 的 `edit_slides` 在字体操作时还须提供 `probe`；其他页面操作不需要字体度量。

提交前按受影响文字的实际字体键预检 profile 和已注册字体，包含粗斜体键；仅修改未使用的类别时不要求加载该字体。核心重新解析依赖页，直接字体覆盖和未受影响内容保持。缩小适配更新比例，形状适配同步本地、继承及组内框的源尺寸；组内尺寸沿父组缩放换回原坐标，零高度框也可重新计算。主题、页面及受影响版式/母版部件合为一次有界历史，撤销/重做同时恢复派生字体和几何，保存重开和 PDF 使用同一结果。

已知字体元数据 `panose/pitchFamily/charset` 保留。目标字体定义的未知属性/子节点、注释、处理指令及重复项仍保护；不能安全适配的源、尺寸锁、缺字体、旧修订、活动候选和预算失败原子拒绝。文字类别划分与语言范围沿现有字体解析，不声明全语言字体一致性。主题字体重排依据 [ONLYOFFICE CTheme.changeFontScheme](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L10662-L10673)，定义顺序参考 [FontCollection](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/FontCollection.cpp#L89-L112)。实现归 [`theme-font.mbt`](../../modules/formats/src/pptx/theme-font.mbt)，适配复用 [`autofit.mbt`](../../modules/formats/src/pptx/autofit.mbt)及 [`text-resize.mbt`](../../modules/formats/src/pptx/text-resize.mbt)。

### 幻灯片版式

`PresentationEditor.editSlides({ action: "layout", id }, slide?)` 应用文稿中已有的版式。`id` 是版式部件路径，须来自 `query.slideLayout.choices`；`current` 返回当前页的版式身份，`reason` 返回目录或修改保护原因。每项选择包含 `id/name/master/masterName`，分别表示版式身份/源名称及所属母版身份/源名称。默认面板按名称和母版展示选项。空名称仅在界面使用序号，不改写源。

目录沿 presentation 的母版列表及各母版的版式列表读取，保留声明顺序。最多 256 个母版、256 项版式；目录文字与重复身份合计不超过 1,048,576 UTF-16 单元，源名称最多 1024 单元。未知、重复或归属错误的引用保护目录；其他编辑与原始源继续保留。

核心按占位符类型及数值索引匹配，中心标题与标题共用匹配类别，并沿用单个正文占位符的回退规则。匹配对象保留身份、文字、直接格式、链接和选择，清除受支持的本地几何覆盖，由新版式及母版重新派生位置、尺寸和继承样式。普通本地对象保留原源。新版式缺少的普通标题、正文、内容及副标题占位符生成空的本地文字对象，使用新身份并继承版式；模板提示文字不会写入幻灯片内容。

缺失的 `dt/ftr/hdr/sldNum` 占位符按版式 `hf` 开关插入；缺少版式设置时使用母版设置，两者均无设置时不插入。有效设置中未声明的开关缺省为启用。固定日期和页脚保留已有文字及样式，简单编号域保留源缓存并计算显示值；字段 ID 复用页面复制的分配规则。内容写为本地对象，位置继续继承版式。普通占位符仍清空提示。规则参考 [ONLYOFFICE 占位符复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L776-L800)及[版式/母版页边设置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9158-L9182)，实现归 [`layout-fields.mbt`](../../modules/formats/src/pptx/layout-fields.mbt)。

没有匹配位置或多个对象争用同一位置时，已有用户内容明确报冲突。仅无文字、可见填充/边框、动作或未知元数据的未匹配占位符可以移除；被计时/连接引用的对象继续保护。缺少时间上下文或未支持的日期域、未知字段、包含关系的页边文字、分组或歧义占位符、未知页边开关/变换，以及导致新增显示诊断或无法解析几何的版式仍保护。新增占位符 XML 合计最多 1,048,576 UTF-16 单元，继续受包、字体、输出及历史预算限制。母版/主题继承可随切换更新，版式和母版本身保持原源。

关系目标、占位符与源变化共用一次精确历史；原生文字草稿先独立提交。选择中失去的继承对象或空占位符会清除，保留对象的文字光标继续有效。相同版式切换是空操作；母版/版式的直接编辑及创建仍待实现。字体总数在候选提交前检查，避免提交后才超出查询的 256 键预算。保存重开、页面复制及 Canvas/PDF 沿相同关系与继承路径。实现归 [`slide-layout.mbt`](../../modules/formats/src/pptx/slide-layout.mbt)，匹配和几何重置参考 [ONLYOFFICE getMatchingShape](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L390-L522)及 [changeLayout](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L695-L800)。

`PresentationEditor.editSlides({ action: "resetLayout" }, slide?)` 重新应用目标页的当前版式，默认面板提供重置按钮。它清除占位符受支持的本地 `xfrm`，恢复版式/母版几何，并沿相同规则补齐缺失的空占位符。保留已有匹配对象身份、用户文字、字符/段落/框属性及形状外观；普通对象和版式关系原字节保持。行为沿 [ONLYOFFICE 当前版式重置入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9519-L9553)，文字格式清除仍使用既有字符/段落命令。

重置仅在有覆盖或占位符变化时新增一项历史，重复调用不改源或 revision。原生草稿先独立提交，随后可精确混合撤销/重做和保存重开。移动/尺寸锁、实际旋转变化的 `noRot`、未知变换标记、无法继承几何及资源预算失败均原子拒绝；版式切换使用相同候选保护。

### 文稿与对象

`PptxSession.execute({ operation: "createPptx", budget })` 与 `PptxClient.execute` 创建 960×540 pt 的空白演示文稿，包含一张无对象页面及其空白版式、母版、主题、关系和内容类型。主题使用 Arial 和显式颜色/无效果样式；当前页为该空白页，revision 与历史为 0。创建后可显示、插入基本对象、保存、重开及输出静态 PDF。默认 UI 与 `mountEditor`、实例 `create/open` 使用同一入口及首次保存规则。主题颜色及字体已支持下述编辑，母版编辑继续实施；创建不生成占位文字或不可编辑的背景图片。

`PptxSession.execute()` 与 `PptxClient.execute()` 使用独立的 `PptxCommand`，不复用 DOCX/XLSX 位置模型。`PptxQuery` 返回 revision、声明页序/尺寸/隐藏状态、当前页对象、有效字体键、图片键、选区、历史状态与诊断。幻灯片 ID 为源部件路径，对象 ID 为所属部件与源 `cNvPr.id`；未知对象使用只读源节点身份。对象包含 `parent`：顶层为空串，组成员为直接父组身份。组自身以 `kind: "group"` 返回，成员按原顺序绘制；默认列表、对象导航和全选只使用顶层对象。未知组效果仍诊断并阻止点穿。

| 命令 | 作用 |
| --- | --- |
| `openPptx` / `queryPptx` | 显式预算打开 Transitional PPTX / 查询当前状态 |
| `selectPptx` / `navigatePptx` | 页/有序对象集合/文字选择、对象顺序及字素/行导航；文字使用对象内 UTF-16 offset |
| `editPptxSlides` | revision、稳定 slide 身份、`PptxSlideEdit` 和字体 `profile`；新增、复制、删除、重排、隐藏/显示、章节、背景、主题颜色/字体、备注或全稿尺寸，返回 `PptxQuery` |
| `editPptxObjects` | revision、字体 profile 和 `PptxObjectEdit`；插入、删除、复制、旋转、翻转、层次、对齐/分布或组合/取消组合，返回 `PptxQuery` |
| `replacePptx` / `deletePptx` / `copyPptx` | 普通文字范围编辑、方向删除及纯文本复制；编辑需要字体 profile |
| `beginPptx` / `finishPptx` / `cancelPptx` | 开始、提交、取消 `text` 或 `transform` 候选；匹配 revision 与 candidateId |
| `transformPptx` / `dragPptx` | 绝对位置/尺寸，或基于手势开始几何的 point 增量与核心手柄编号 |
| `undoPptx` / `redoPptx` / `savePptx` | 原子历史及绑定 revision 的源保存 |
| `layoutPptx` / `hitPptx` / `selectionPptx` | 当前页绘制、最上层命中、对象轮廓/手柄及文字光标/选区；几何绑定 layoutId |
| `imageKeysPptx` / `imageBytesPptx` / `imagePptx` | 准备当前页或导出范围的资源键、读压缩源、接入经过宿主校验的 RGBA |
| `exportPptxPdf` | 绑定 revision、字体 profile、当前页/整稿、隐藏页选择与输出预算的静态 PDF |

`PptxSelection` 包含 `slide`、有序且唯一的 `objects: string[]`、活动 `object`、`mode`、`anchor` 和 `focus`。空集合要求活动身份为空；非空集合要求活动身份属于集合。集合最多 256 个当前页对象，身份长度最多 1024。文字模式要求唯一对象及有效字素边界。`selectPptx` 必须提供全部字段，失败保留原选择；选择不新增历史。宿主 `selectObjects(objects, active?)` 默认激活最后一项；`select(object, mode?, anchor?, focus?, extend?)` 默认替换选择，`extend=true` 在对象模式中切换成员。

默认 UI 支持 Shift 点击画布/列表切换成员、点击已选成员保留集合以及 Ctrl/Cmd+A 全选。进入文字模式收敛到活动对象。`selectionPptx` 返回成员 `outlines` 和包围盒 `outline`；本地可变换成员使用四角手柄。多选 `dragPptx` 的移动及角点等比例缩放沿用开始几何；`transformPptx` 对多选接收整组世界坐标包围盒，非等比例尺寸拒绝。旋转、翻转、相对位置和零尺寸线段保留，每个成员继续受原尺寸/位置限制。任一成员受保护时整组拒绝。属性面板使用同一变换路径；候选完成后仅一项历史，取消保持源和选择。

`PptxSlideEdit` 从 `wasm/pptx` 和 `web/pptx` 导出。`{ action: "move", index }` 将目标页移到从 0 开始的索引，索引包括隐藏页；`{ action: "hidden", hidden }` 修改隐藏状态。编辑宿主为 `PresentationEditor.editSlides(change, slide?)`，省略身份时作用于队列执行时的活动页。重排保持页路径、源页 ID、对象身份、关系及活动选择，仅改 `sldIdLst` 顺序；隐藏只改 slide 的 `show`。自定义放映和页间链接仍按原关系指向同一页面。相同位置/状态不新增历史，错误不提交。

`{ action: "add" }` 在目标页后插入空白本地内容，沿用该页的版式、母版和主题，继承版式/母版中的装饰与背景。新页可继续创建及编辑对象；不复制原页对象、备注、动画或版式占位符。核心分配新页 ID、路径和关系，切到新页并清空对象选择。会话内撤销后再新增不复用该页身份。新 slide 及其版式关系、内容类型和页引用合为一项有界历史，与后续对象/文字、重排和隐藏共同精确撤销/重做。最多 256 页，预算或保护失败不留下新部件。默认 UI 提供新增空白页入口。

`{ action: "copy" }` 在目标页后复制，激活副本并清空对象选择。保留隐藏状态、内容、几何、格式及版式继承，分配新页/对象身份，重映射对象连接与计时目标。自身页链接指向副本，其他页链接及自定义放映保持原目标。图片、版式、母版和主题复用原部件，外部超链接保留地址且不下载。普通备注和传统批注另建部件及关系；备注回链指向副本，批注保留作者和内容，分配新 idx 并更新作者 lastIdx。复制部件、作者索引和页引用进入同一有界历史，支持后续编辑、删除、保存重开和精确撤销/重做。重新复制不复用已撤销的页/对象身份。

复制为已知 PowerPoint 2010 creationId 扩展及 DrawingML 字段生成新身份，保留字段类型和源缓存文字；保护其他未知 XML 身份扩展及 noCopy 锁。未知关系、图表/嵌入数据、媒体、VML 和线程批注需要对应所有权支持后开放。支持页关系为 slideLayout/image/hyperlink/slide/notesSlide/comments；备注关系为 notesMaster/image/hyperlink/slide；传统批注仅允许超链接。外部关系仅允许 hyperlink。标准计时 XML 可保留并重映射对象目标，尚不提供动画编辑或播放。复制继续受 256 页、对象/文字、输入输出和 4 MiB 历史预算约束，失败不修改已提交内容。

`{ action: "delete" }` 删除指定页，至少保留一页。删除活动页时选择原位置的下一页，末页则选前页，并清空对象选择；删除非活动页保留当前选择。同步移除 presentation 页引用、自定义放映中的对应条目，以及其他 XML 中指向该页的已知 DrawingML 点击/悬停链接及关系，保留链接所在对象与文字。空的自定义放映保留身份。仅删除该 slide、其关系和独占的备注/传统批注 XML 及关系，移除对应内容类型；版式、母版、主题、图片、作者与未知资源保留，不扫描清理整个包。共享备注/批注、未知或隐式引用、超出历史/输出预算时原子拒绝。删除部件快照计入有界历史，可与新增、对象及页序编辑精确混合撤销/重做，损坏历史拒绝回放且不改变当前文稿。默认 UI 提供删除页，并禁用最后一页的删除。选择规则参考 [ONLYOFFICE 删除页](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9458-L9485)。

`PptxQuery.sections` 返回 `{ items: PptxSection[], reason }`。每章包含稳定 GUID `id`、`name` 和按页序排列的稳定部件路径 `slides`；类型从 Wasm/Web PPTX 模块导出。核心读取标准 PowerPoint 2010 `p14:sectionLst`，源成员引用 presentation 的数值 `p:sldId`，不使用页索引或关系 ID。存储参考 [ONLYOFFICE SectionList/Section](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Presentation/PresentationChildElements.cpp#L289-L339)。

`PresentationEditor.editSlides` 同步支持 `{ action: "sectionAdd", name }`、`{ action: "sectionRename", id, name }`、`{ action: "sectionRemove", id }`、`{ action: "sectionRemoveAll" }`、`{ action: "sectionMove", id, index }` 和 `{ action: "sectionDelete", id }`。新增在目标页前切分所属章；首次从中间分章时为前页创建 Default Section。移除保留页面，归入前章，首章则归入后章；移除最后一章只清理章节元数据。移动按从零开始的章节索引重排该章及其全部页面，保留活动页/对象身份。新增和复制页继承源章；删除移除成员，跨章移动按落点归属。空章保留，未分章前缀允许存在。每章成员必须连续、有序且互不重复，最后一个非空章覆盖到末页。

最多 256 章，名称最多 255 UTF-16 单元；创建/改名要求非空有效 XML 文字。章节与关联页序合为一项有界历史，可与页操作和原生输入混合精确撤销。重名允许，身份按 GUID 区分。相同名称/位置不新增历史。未知章节属性/子项、非连续/重复/悬空引用和修改保护明确拒绝，不删掉未知源来开放编辑。非目标部件、已有章节外标签及页引用周围源内容保留；未知无关扩展可随章节改名保留，但仍保护页序修改。保存重开及 PDF 使用提交后的页序。默认面板提供新增、选择、改名、保留页面移除、一次移除所有章节、前后移动及删除章节和页面。

默认页列表按 `query.sections` 的稳定身份分组，保留未分章的前缀、全稿页码、空章和隐藏页标记。章节标题显示名称与页数，按钮用 `aria-expanded` 和 `aria-controls` 关联成员页；Enter/Space 切换，另有全部折叠/展开。折叠隐藏该章的页按钮，当前画布及核心选择不变；活动页所在的折叠章由标题标识，外部页导航会自动展开目标章。改名和整章重排保持折叠状态；已移除的章清理状态，新章初始展开。更换/重开文档时初始全部展开。无可用章节时继续显示平面页列表。折叠是默认 UI 的会话视图状态，不写入 PPTX、不增加文档历史，不改变保存/PDF 页序和页数。参考 [GenOffice 章节视图状态](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/renderer/App.tsx#L2247-L2259)，实现归 [`pptx-slides.tsx`](../../packages/ui/src/pptx-slides.tsx)。

`sectionRemoveAll` 一次移除全部章节，保留全部页、页序、对象、选择及其他部件。章节元数据以一项有界历史移除，可精确撤销/重做和保存重开；没有章节时不修改 revision 或历史。UI 无章节时禁用入口。损坏或未知章节继续保护；其他扩展、外层属性、注释和处理指令保留，只在外层扩展列表没有其他内容时一并移除该空容器。操作目标参考 [GenOffice removeAllSections](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/renderer/slide-actions.ts#L182-L189)，沿用已有标准 p14 写回和核心事务。

`sectionDelete` 同时删除该章及全部成员页，至少保留一页；空章只移除章节元数据。剩余页面、章节和对象保留稳定身份。活动页被删时选择其后首个存活页，无后页则选择末个存活页，并清空对象选择；活动页未删除则保留原选择。页引用、自定义放映、已知页链接、独占备注/传统批注与相关类型声明复用页面删除规则，全部变化进入同一项有界历史。未知入站引用、共享备注/批注、保护或整项累计预算失败不提交任何删除。原生草稿先独立提交，随后整章删除独立撤销。UI 禁用删除覆盖全稿的章节。页面集合与独占资源的精确快照直接扩展既有核心历史，撤销/重做及保存重开不依赖逐页宿主命令。操作目标参考 [GenOffice 整章删除](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/main/slides-main.ts#L4266-L4288)，资源和页选择沿用前述 ONLYOFFICE 页删除规则。

`PptxQuery.slideOrderReason/slideVisibilityReason` 返回各自保护原因。修改保护阻止两者；损坏或未支持的章节、未知 presentation/页列表扩展、presProps 中的位置型 `sldRg` 放映范围和未知 presentation properties 扩展阻止新增、删除与重排。空参考线列表及已知图片编辑数据、默认 DPI、图表引用跟踪设置扩展原样保留；非空参考线列表继续保护。默认 UI 使用这些原因，提供新增、删除、页前移/后移和隐藏/显示，页列表保留隐藏页入口。历史按稳定部件路径恢复，混合对象编辑与页序变化不会改错页面。

隐藏页仍可在编辑器中查看和编辑，允许全部页隐藏。全稿静态 PDF 默认跳过隐藏页，显式 `hidden: true` 包含它们；仅导出当前页时可以输出当前隐藏页。没有待输出页时返回 `unsupported-pdf`，不返回空 PDF。保存重开按新页序打开首张页面，保留隐藏状态。更广复制资源仍归 [P12](../p12-pptx-core.md)。

`PptxObjectEdit` 从 `wasm/pptx` 和 `web/pptx` 导出。`PresentationEditor.editObjects(change)` 使用同一队列与命令。插入参数为 `{ action: "insert", kind: "text" | "rect" | "roundRect" | "ellipse" | "triangle" | "rtTriangle" | "diamond" | "parallelogram" | "trapezoid" | "line" | "leftArrow" | "rightArrow" | "upArrow" | "downArrow", x, y, width, height, text }`；坐标和尺寸为 point，绝对值不超过 14400。非线对象宽高至少 0.1；线可有一个零尺寸轴，总尺寸至少 0.1。文本框透明无描边，矩形、圆角矩形、椭圆和箭头白底黑色 1 pt 线，直线黑色 1 pt；文字为 Arial 18 pt 黑色，支持 `\n` 与 `U+2028`，线不接收文字。核心校验文字、字体和固定框容量，失败保留文档和历史。

图片插入为 `{ action: "insertImage", bytes: Uint8Array, x, y, width, height }`，沿相同 `editObjects` 入口。坐标为 point，绝对值不超过 14400，宽高至少 0.1。接收本地 PNG/JPEG 原字节，单图最多 4 MiB，尺寸每轴不超过 4096，像素总数不超过 4194304，文稿最多 256 个不同图片资源；最终包与单项 4 MiB 历史预算仍可拒绝操作。核心检查文件头、声明尺寸和几何；浏览器客户端提交前验证实际解码与声明尺寸一致，坏图保留当前源和历史。同步 Wasm 入口不承担宿主解码，导入图片仍沿原有解码合同。核心分配对象与资源身份，事务新增图片、内部关系和内容类型；撤销移除本次新资源，重做恢复原字节及 ZIP 顺序。对象/页复制共用图片，删除对象/页保留资源，不清理整个包。默认 UI 选择图片文件，并采用插入面板中的 X/Y/宽高。创建矩形图片并 stretch 到给定几何的规则参考 [ONLYOFFICE fillImage](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L114-L142)。高级图片效果继续归 [P12](../p12-pptx-core.md)及后续兼容扩展。

图片替换为 `{ action: "replaceImage", object, bytes: Uint8Array }`，使用相同图片预算和浏览器解码检查。要求对象模式中唯一的本地顶层图片，保持对象身份、选择、几何、旋转/翻转、裁剪及其他源属性；为它新建图片和关系，不覆盖共享资源或改变其他副本。`object` 必须与提交时唯一选中的图片身份一致；文件读取期间改变选择会拒绝替换，防止改错目标。相同原字节不新增历史。对象几何保留参考 [ONLYOFFICE replacePictureData 的 stretch 路径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L839-L869)，当前接口保留原裁剪，不提供 fit/fill/original 模式。

独立图片使用 `editObjects({ action: "imageMode", mode: "stretch" | "tile" })` 切换模式。`picture.mode` 返回当前有效模式，`modeReason` 返回编辑保护原因；默认图片面板提供选择和应用。命令作用于唯一选中的本地顶层图片，只改 `blipFill` 的模式节点，保持身份、外框、旋转/翻转、裁剪、不透明度、图片字节及关系。同值不增加历史。未显式声明模式的已知源按拉伸读取，首次切换插入标准平铺。导入支持已有缩放、偏移、对齐与交替翻转，范围与[形状平铺](#形状图片填充)相同。平铺使用整张源图并保留裁剪；切回拉伸时重新应用裁剪，并在提交前验证展开尺寸。

图片在拉伸和平铺时均按已支持的预设图片框裁剪，矩形沿原矩形路径，椭圆等复用已有形状轮廓；变换后的框和图片使用同一矩阵。绘制入口参考 [ONLYOFFICE CImageShape.draw](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L592-L659)，平铺语义复用其 ShapeDrawer。背景、形状填充和独立图片共用每页 65536 个重复单元；尺寸和变换候选沿同一数量检查。未知模式/填充标记、外链、非零目标内缩、固定页面方向及未知效果继续保护；未知几何不放开。失败保留源、资源、选择和历史。保存重开、复制、替换、裁剪、不透明度及 Canvas/PDF 沿原路径。实现归 [`picture-mode.mbt`](../../modules/formats/src/pptx/picture-mode.mbt)及[共享平铺](../../modules/formats/src/pptx/shape-tile.mbt)。

四边裁剪为 `{ action: "imageCrop", left, top, right, bottom }`，每边为源图的移除比例，范围 0 至 0.99999。核心按 OOXML 的 1/100000 网格舍入，左右及上下之和必须小于 1，派生绘图坐标继续受预算约束；不改对象外框。四个零恢复整图并移除裁剪覆盖，同值不新增历史。`PptxObject.picture` 返回四边有效比例和 `replaceReason/cropReason`，另返回 `mode` 与 `modeReason`。裁剪锁、继承/组内图片、非唯一选择、未知裁剪标记及预算失败保留源；默认 UI 提供替换文件、四边百分比和重置。替换、裁剪和后续对象编辑沿同一历史精确恢复，保存重开与 Canvas/PDF 共用已有源矩形显示路径。

图片不透明度为 `{ action: "imageOpacity", opacity }`，要求对象模式中唯一的本地顶层图片。`opacity` 为 0 至 1，0 完全透明，1 完全不透明；核心按 1/100000 网格写入 `a:alphaModFix amt`，调回 1 时移除覆盖，同值不新增历史。`picture.opacity/opacityReason` 返回当前值及修改保护原因。支持单个常量 alpha 效果，其他效果继续诊断；带未知保留标记的透明度节点保护修改。倍乘关系参考 [ONLYOFFICE CBlipFill 常量 alpha](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L3818-L3840)。操作保持身份、几何、裁剪、图片原字节及共享副本，能与替换/复制混合精确撤销和保存重开。默认 UI 显示不透明度百分比。

定位后的图片图元携带不透明度，DOCX 行内图片显式使用 1。Canvas 沿公共 `DrawStyle.fillAlpha` 执行，图片结束后恢复默认样式；PDF 在单张图片的作用域应用 ExtGState `ca`，与原像素的软蒙版相乘，不把共享原图改成带透明度的新像素。两个输出共用核心值和相同源像素，完全透明的对象仍保留选择及资源。

删除参数为 `{ action: "delete" }`，复制为 `{ action: "duplicate", dx, dy }`。两者要求对象模式；空选区不修改文档。删除作用于整个集合，先校验全部成员，再提交一项历史；任一保护失败不删除其他成员。复制作用于整个集合，包括受支持的嵌套组；副本按原源顺序放到最上层。保留源内容、几何、组缩放、命名空间与图片/超链接关系，为副本及其全部成员分配会话内尚未使用的新 `cNvPr.id`，域身份同样更新。副本内部对象引用重映射；引用集合外对象而需联动的结构明确拒绝。副本选择保留原选择顺序及对应活动对象。一次复制合为一项历史，任一成员、字体、几何或预算失败不创建副本、不消耗身份。原对象、其他部件和资源保持原样。一次复制的 XML 片段及继承命名空间合计最多 2 Mi UTF-16 单元，在拼接前检查；最终包和历史继续受原有预算约束。删除清空选择；撤销/重做精确恢复源 XML 与选择。`PptxObject.deleteReason/duplicateReason` 返回操作保护原因，空串表示可用。继承/组成员/未知对象继续保护；复制占位符及未知扩展、删除锁定或带连接/计时引用的对象仍拒绝，含未支持所属关系的页面也保护删除。资源和关系不做清理。默认 UI 提供插入面板、复制/删除按钮；对象输入支持 Delete/Backspace 与 Ctrl/Cmd+D，默认复制偏移各 18 pt。

圆角矩形使用 `roundRect`，实心箭头使用四个方向的标准 DrawingML 预设；新对象使用默认调节点。读取圆角 `adj`、箭头 `adj1/adj2` 的 `val` 数值公式，按预设上下限和实际宽高计算路径、文字矩形及命中；未知调节点或公式保留源并诊断。文字矩形先于 bodyPr 内边距，新增/复制时继续检查实际容量。Canvas 与 PDF 使用同一路径，旋转和局部翻转使用同一矩阵。

三角形 `triangle`、直角三角形 `rtTriangle`、菱形 `diamond`、平行四边形 `parallelogram` 和梯形 `trapezoid` 已接通导入、插入、文字编辑、轮廓命中及 Canvas/PDF。路径和文字矩形依据 [ONLYOFFICE CreateGeometry](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8500-L8550)，实现归 [`polygon-shapes.mbt`](../../modules/formats/src/pptx/polygon-shapes.mbt)。三角形的 `adj` 是顶点横向比例，默认 0.5，范围 0–1；平行四边形及梯形的 `adj` 是斜边偏移占短边的倍数，默认 0.25，上限分别为宽/短边及宽/(2×短边)。导入数值按几何上限夹取；编辑值越界则拒绝。直角三角形和菱形没有调节项。文字矩形先计算，再加框内边距。数值修改、恢复预设、多选保护、保存和精确历史复用既有命令；单一 `adj` 的面板批量修改要求相同预设。复杂自定义几何和指针调节手柄继续实施。

`editObjects({ action: "shapeAdjustment", name, value })` 修改所选本地顶层预设形状的一个调节值。圆角 `adj` 为短边的 0–0.5 倍；四向实心箭头的 `adj1` 为箭身占横向宽度的 0–1 倍，`adj2` 为箭头长度占短边的倍数，上限是箭头方向边长除以短边。数值按十万分之一保存，沿现有公式整数范围限制在 0–21474.83647。null 只移除该调节值，恢复预设默认值；其他调节值和源内容保留。规则依据 [ONLYOFFICE 预设几何](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/Drawings/Format/CreateGeometry.js#L6947-L6981)，实现归 [`shape-adjustment.mbt`](../../modules/formats/src/pptx/shape-adjustment.mbt)。

对象查询的 `shapeAdjustments` 返回 `preset`、`reason` 和 `values`；各值包含 `name/value/maximum`，使用与命令相同的比例。默认面板显示百分比，支持分别应用、恢复预设值及相同调节项的多选混合查询。任一对象锁定 `noAdjustHandles`、未知调节源、所选形状不支持该项或数值越过几何上限时，整项拒绝。无变化不新增历史。修改与派生的字体缩小或形状自动尺寸合为一项历史，保留文字、身份、选择及非目标部件；保存重开后可继续修改。组内、继承对象、指针拖动调节手柄和任意自定义几何编辑继续实施。

旋转使用 `{ action: "rotate", angle }`，绝对角度为 -360°–360°，核心舍入到 1/60000°。`{ action: "flip", axis: "horizontal" | "vertical" }` 切换局部水平/垂直翻转。`{ action: "layer", order: "front" | "back" | "forward" | "backward" }` 调整本地顶层对象的源顺序。三者均支持本地顶层对象集合，组作为一个对象处理。各操作保留位置、尺寸、对象身份、文字、裁剪和关系；相同角度与层次边界不新增历史。旋转独立保持各对象自身中心点；翻转分别反转各对象的局部轴状态。文字、图形、图片、命中和选区消费同一矩阵。`geometry` 返回源有效 `rotation/flipX/flipY`，`rotateReason/arrangeReason` 返回对应保护原因。`noRot` 仅阻止旋转；继承/组成员与原有变换锁继续保护。默认 UI 提供角度、翻转及四种层次操作。

批量旋转/翻转要求对象模式，保留各成员位置、尺寸、源顺序、关系、选择顺序及活动对象；组成员的局部源几何保持，世界矩阵随组方向更新。一次提交一项历史，任一成员、源或包预算失败不提交部分对象；相同角度无变化时不新增历史。默认角度框在值混合时留空并显示提示，翻转按钮使用 `aria-pressed="mixed"` 表示混合状态；选择集合改变时刷新角度。旋转锁检查全部成员，`noRot` 不阻止翻转。

层次调整要求对象模式；空选择保持文档不变。`front/back` 按原源顺序将所选对象放到最上层/最下层。`forward` 从上到下、`backward` 从下到上处理，每个所选对象仅越过一个相邻未选对象，所选对象之间保持原顺序。组作为单个顶层对象移动，内部层次和完整矩阵保持；未知未选对象原样保留。核心只移除并插入所选源片段，保留注释、其他源内容、关系、选择顺序及活动对象。任一成员受保护或预算失败时整项拒绝，成功只提交一项历史；已到边界或全选而无变化时不新增历史。默认四个按钮支持多选。

文字与变换候选基于原范围重算，不写入已提交 XML，不累积中间历史。暂态查询/布局读取候选；提交一项历史，取消恢复原选择。保存、PDF 和普通编辑在候选期间失败。Enter 是普通段落分隔 `\n`，Shift+Enter 使用对象内软换行 `U+2028`；保存为 DrawingML `p` / `br`。跨 run/段落保留范围外字符与段落属性，不重建整个 `spTree` 或 `txBody`。普通逐字符输入目前各自成项。

对齐使用 `{ action: "align", alignment: "left" | "center" | "right" | "top" | "middle" | "bottom", relativeTo: "slide" | "selection" | "active" }`。相对页面使用页面边缘或中线；相对选区使用所有成员旋转后的矩形包围盒；相对活动对象使用 `selection.object` 的包围盒并保留该对象的位置。`center` 为水平居中，`middle` 为垂直居中。单对象相对自身选区或活动对象时不修改源。

分布使用 `{ action: "distribute", axis: "horizontal" | "vertical", relativeTo: "slide" | "selection" }`。页面分布至少需要两个对象，选区分布至少需要三个；不足时明确拒绝，不切换参考范围。按世界坐标矩形中心排序，中心相同则按选择顺序。选区分布固定排序后的首尾边缘，其余对象保持相等边缘间距。页面有余量时，内部间距与两端留白相等；总尺寸不小于页面时，两端贴页面边缘，内部间距允许为负。旋转矩形边界包含零尺寸线段，不计描边宽度。

对齐与分布要求对象模式，沿用 256 成员、本地顶层对象及现有锁定/继承/未知资源保护。只改成员位置，保留顺序、活动对象、尺寸、旋转、翻转、文字、裁剪和关系；位置舍入为整数 EMU。成员越界、输出或历史预算失败不提交任何成员，成功只新增一项历史，重复操作无变化时不新增。默认面板提供参考范围、六种对齐和两种分布，活动对象参考下禁用分布。接口复用 `editPptxObjects` / `PresentationEditor.editObjects`。

组合使用 `{ action: "group" }`，至少选择两个可编辑本地顶层对象。核心分配新组身份，保留成员身份、相对顺序、格式及关系，转换局部坐标；新组放在所选最上层对象的位置，选择切到新组。原组也可参与嵌套组合。顶层组沿用整体移动、缩放（含非等比例）、旋转、翻转、层次、对齐和删除事务；候选同步派生成员世界矩阵，不写已提交源。多选集合的非等比例缩放仍拒绝。

取消组合使用 `{ action: "ungroup" }`，选择须全部为受支持顶层组。包含非等比缩放及嵌套组，成员回到原组所在层次，选择展开为直接成员，最多 256 项。核心先把累计组缩放换算为成员框的位置与尺寸，再以旋转/翻转矩阵绘制；文字字号、边距及描边宽度保持原值，文字按新框排版。候选预览和源重读使用同一几何规则；取消组合还原世界位置、尺寸、旋转及翻转，保留成员身份、命名空间和组内注释。子组保留自己的子坐标范围，可继续逐层取消组合。组内直接编辑仍保护。

尺寸归一遵循 [ONLYOFFICE 组合缩放系数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L568-L607)及[成员 normalize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L629-L664)，取消组合参考 [unGroupCallback](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L7045-L7108)。核心已检查非等比嵌套、旋转/翻转、预览与提交一致、取消、文字/线宽、精确历史及重开；Chromium 已检查取消组合前后 Canvas 画面、独立同字号文本的 PDF 字形边界、XML、非目标部件、历史和重开后原生输入。

`PptxQuery.groupReason/ungroupReason` 返回当前选择的保护原因，默认 UI 用它禁用按钮。继承占位符、未知组效果/扩展、成员锁定、`noGrp/noUngrp`、组合所涉连接/计时引用和取消组合所移除组的引用继续保护。操作只改所属 slide XML，保留其他部件及资源；一次提交一项有界历史，撤销恢复原源与选择，失败不消耗新身份或提交部分成员。

`editPptxObjects` / `PresentationEditor.editObjects` 支持 `{ action: "fill", color }` 和 `{ action: "stroke", color, width }`。颜色为不带 `#` 的六位 RGB，核心统一小写；null 写显式 `noFill`，表示无填充或无边框。宽度为 0.1–1000 pt，舍入到整数 EMU。操作作用于对象模式下所选的本地顶层形状，包含文本框和基本形状；多选原子提交为一次历史。查询中每个对象带 `appearance: { fill, gradient, imageFill, imageFillMode, imageFillReason, stroke, width, fillOpacity, strokeOpacity, fillOpacityReason, strokeOpacityReason, dash, dashReason, cap, join, miterLimit, penReason, reason }`，颜色为有效 RGB 或 null，宽度为有效 pt，reason 说明保护原因。默认 UI 显示混合状态，分别应用填充和边框，草稿随选择或实际外观值更新。

修改只覆盖目标属性，保留几何、顺序、身份、文字、其他线条属性与部件。缺失的填充/边框按 DrawingML 顺序创建，空边框保留原属性；填充覆盖会关闭 `useBgFill`。直接设置相同值不增加历史；候选、过期 revision、锁定、未知填充属性/注释及预算失败不提交任何成员。组、组内对象、继承装饰和图片仍受保护，多色标/透明/径向渐变及复杂效果编辑待扩展；图片拉伸填充见下节。纯色与受支持线型沿共同 Canvas/静态 PDF 路径绘制。实现参考 [ONLYOFFICE CShape.changeFill/changeLine](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L6421-L6461) 的局部属性覆盖及背景填充处理。

`editObjects({ action: "gradientFill", startColor, endColor, angle, scaled })` 将所选本地顶层形状设为双色线性渐变。颜色为六位 RGB，角度为 0–360° 并按 1/60000° 舍入，360° 归一为 0°；`scaled` 为必需布尔值。角度及比例规则复用[页面背景](#pptx)，保留形状的轮廓、调节点、几何、描边和文字，随对象旋转/翻转。默认外观面板提供类型、两色、角度和按形状比例缩放。查询 `appearance.gradient` 返回 `{ kind: "linear", startColor, endColor, angle, scaled }` 或 null；渐变时 `fill` 为 null、`fillOpacity` 为 1，填充不透明度命令受保护，纯色描边仍可调整。纯色/无填充命令可替换已有受支持渐变。

读取本地、版式/母版继承及主题的两端点不透明渐变；源的 `rotWithShape` 为缺省/真值，固定页面方向、多色标、透明、路径渐变、非零 tileRect 或未知标记保留源并诊断。操作先校验全部成员，复用原子源事务、无操作和精确历史；非法值、保护成员和输出预算失败保持整个文档。新增定位图元 `ClipPath(path, evenOdd)` 复用既有绘制命令，Canvas/PDF 沿相同预设路径裁剪，矩形以外区域及后续图元保持原样。实现归 [`shape-gradient.mbt`](../../modules/formats/src/pptx/shape-gradient.mbt)；参考 [ONLYOFFICE 形状渐变绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1970-L2037)。

### 形状图片填充

`editObjects({ action: "imageFill", objects, bytes, mode })` 将所选本地顶层闭合形状设为 PNG/JPEG 图片填充，`mode` 必须为 `stretch` 或 `tile`。`objects` 是文件读取前捕获的有序选择，提交时须与当前选择完全一致，防止异步读取后修改其他对象。图片沿既有 4 MiB、尺寸、资源数量、输出和历史预算校验，Web 提交前检查实际解码。多选共享一个新资源及关系，保留各自身份、几何、轮廓、描边、文字、已有裁剪和有效填充不透明度。核心沿既有图片事务提交，失败不增加资源或历史；相同本地图片无操作。默认面板选择图片后直接应用，清除和纯色/渐变命令可替换受支持图片填充。

查询 `appearance.imageFill` 返回资源键或 null，`imageFillMode` 返回 `stretch`、`tile` 或 null，`imageFillReason` 返回保护原因。读取本地、版式/母版和主题的内部图片关系，按来源部件解析；支持非负四边源裁剪及常量 `alphaModFix`。图片按预设形状轮廓裁剪，随对象旋转/翻转，Canvas/PDF 共用同一图元。已有本地图片填充可用 `fillOpacity` 修改透明度；继承图片先设置本地图片覆盖。带裁剪元数据的平铺复用 [ONLYOFFICE drawBlipFillTile](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1687-L1777)：使用整张源图的 96 DPI 尺寸、对齐和翻转，保留 `srcRect`；切回拉伸才应用裁剪。模式切换、替换、透明度和精确历史保留这些值；切回拉伸的扩展尺寸及平铺数量超限原子拒绝。非零目标内缩、固定页面方向、外链、背景关联图片填充及未知/重复/不透明源继续保护，仍归 P12 后续实现。实现归 [`shape-image.mbt`](../../modules/formats/src/pptx/shape-image.mbt)和 [`object-image.mbt`](../../modules/formats/src/pptx/object-image.mbt)，语义参考 [ONLYOFFICE 图片拉伸、裁剪和透明度绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1778-L1848)，未复制上游源码。

`editObjects({ action: "imageFillMode", mode })` 在已有本地图片上切换拉伸和平铺，不新增图片或关系；继承填充须先设置本地覆盖。默认面板提供模式选择、应用及按所选模式上传文件。平铺采用 96 DPI，即源像素乘 0.75 pt，不读取嵌入 DPI。导入支持 `sx/sy`（1–100000000，以 100000 为一倍）、`tx/ty`（±182880000 EMU）、九种 `algn` 及 `flip=none/x/y/xy`；偏移和对齐确定原始格点，负索引仍保持交替镜像相位。换图保留已有平铺参数，切换回平铺使用默认顶左对齐、原尺寸和无翻转。非零源裁剪在平铺时保留，切回拉伸后生效；未知源继续保留并诊断。

核心只生成覆盖形状的有限图片图元，沿同一轮廓裁剪供 Canvas/PDF 使用。每页最多 65536 个重复单元；应用、复制、尺寸修改及单选/多选变换预览超过预算时，在资源、历史或候选变化前拒绝。已有超预算源仍可原样保存，输出受预算保护。实现归 [`shape-tile.mbt`](../../modules/formats/src/pptx/shape-tile.mbt)，尺寸、对齐和交替镜像依据 [ONLYOFFICE 平铺绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1685-L1776)及[镜像纹理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/Graphics.js#L870-L949)。未复制上游源码，未增加渲染后端或依赖。

`editObjects({ action: "fillOpacity" | "strokeOpacity", opacity })` 分别设置纯色/本地图片填充和纯色边框的不透明度，值为 0–1，按 1/100000 舍入。默认 UI 使用百分比输入；查询返回两项有效值及各自保护原因，支持混合多选。无填充的一侧须先设置填充，0 保留形状和选择。100% 写入明确的不透明覆盖，不表示恢复继承。

读取已有颜色的 alpha、alphaMod 和 alphaOff，按声明顺序计算并归一到 0–1。修改保留 RGB/系统色/主题色及 tint、shade、lumMod、lumOff 等关联；继承填充写为本地声明，主题 phClr 绑定到原引用颜色，保留主题和父级源。颜色与线宽修改保留已有有效不透明度；明确移除填充后不保留隐藏的 alpha 状态。操作复用同一多选源事务、待输入文字屏障和精确历史。未知颜色标记、保留注释、只读对象及预算失败拒绝全部成员。文字和页面背景的透明度仍受原保护。算法参考 [ONLYOFFICE 颜色 alpha 变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L2089-L2108)，实现归 [`shape-opacity.mbt`](../../modules/formats/src/pptx/shape-opacity.mbt)。

`editObjects({ action: "strokeDash", dash })` 修改所选本地顶层形状的预设线型，适用已有多选、文字框和基础形状。`dash` 接受 `solid`、`dash`、`dashDot`、`dot`、`lgDash`、`lgDashDot`、`lgDashDotDot`、`sysDash`、`sysDashDot`、`sysDashDotDot` 或 `sysDot`；null 移除局部 `prstDash` 并恢复主题/父级，缺省为实线。`appearance.dash` 返回有效线型，`dashReason` 返回本操作的保护原因。默认 UI 提供线型选择、应用和恢复继承，混合选择继续显示混合状态。

修改只写目标 `prstDash`；缺少 `ln` 时按 DrawingML 顺序创建局部边框，保留颜色和宽度继承，明确的 `solid` 可覆盖主题虚线。行宽、颜色、填充、几何、文字、身份及其他部件保持，整组共用一次精确历史。重复同一直接值不新增历史，源注释/处理指令或未知线型属性保护修改；自定义 dash、重复声明及未知预设保留源并诊断。

预设使用 [ONLYOFFICE DashPatternPresets](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Metafile.js#L1767-L1820)的线宽倍数，普通短划线为 4/3，长划线为 8/3，系统短划线为 3/1。有效线宽变化同步缩放 dash。定位后的路径携带点值数组，Canvas 沿已有绘制样式执行并复原，PDF 使用单路径作用域中的 dash 指令，后续图元继续沿自身样式绘制。自定义 dash 继续实施。

`editObjects({ action: "strokeCap", cap })` 设置 `flat/rnd/sq` 平头/圆头/方头，null 恢复继承。`{ action: "strokeJoin", join }` 设置 `round/bevel` 圆角/斜角，null 恢复继承；`{ action: "strokeJoin", join: "miter", miterLimit }` 设置斜接，比例为 1–1000，按 1/100000 舍入。查询返回有效 `cap/join/miterLimit` 及 `penReason`，默认 UI 提供两类样式、斜接上限和各自恢复按钮。

局部值按属性覆盖父级/主题；连接类型相同时继承缺失的斜接上限。基础缺省值为平头、圆角和斜接比例 8，依据 [DrawingML 继承与默认值](https://learn.microsoft.com/ga-ie/openspecs/office_standards/ms-oi29500/c0c046ec-a61d-405d-88fe-74d8487a37d7)。操作沿用本地顶层形状、多选原子事务、精确历史与既有预算，保留颜色、宽度、线型、其他源属性和部件；不修改共享主题或母版。未知/重复连接、保留的连接注释、未知端点或超出支持范围的斜接值保留源并保护修改。

定位路径使用 `PathStyle { fillAlpha, strokeAlpha, dash, cap, join, miter }`，数值端点 0/1/2 对应平头/圆头/方头，连接 0/1/2 对应斜接/圆角/斜角。Canvas 复用既有 `DrawStyle`，每条路径后复原；PDF 在独立图形作用域写相同端点、连接、斜接、dash 及独立填充/描边 alpha。普通及斜线的端点形状参与核心命中。预览与输出不再把导入端点或连接静默画成默认值。

### 直线端点样式

`editObjects({ action: "lineEnd", side, end })` 修改所选本地顶层直线的端点样式。`side` 为 `head/tail`，分别对应路径起点的 `headEnd` 和终点的 `tailEnd`。`end` 为 `{ kind, width, length }`：`kind` 接受 `none/triangle/stealth/diamond/oval/arrow`，分别为无、实心三角、凹尾、菱形、椭圆和开放箭头；宽度与长度各接受 `sm/med/lg`。`end=null` 移除该端的局部声明并恢复继承，`kind="none"` 显式覆盖继承。MoonBit 类型为 `LineEnd`，Wasm/Web 类型为 `PptxLineEnd`；查询返回 `appearance.headEnd/tailEnd/lineEndReason`，默认面板提供两端独立设置、混合状态和恢复按钮。

尺寸使用有效线宽的 2/3/5 倍，细线以 1.875 pt 为最低基准。该值将上游的 2.5 px 最小尺寸固定到源坐标，预览缩放与 DPR 不改变 PDF 几何。三角、凹尾和开放箭头朝外，菱形与椭圆以端点为中心；端点沿直线方向、旋转、翻转和既有组矩阵绘制。轮廓参与核心命中，使用边框颜色和不透明度，保持主体虚线而以实线绘制端点。Canvas/PDF 复用相同路径。零长度线不派生端点轮廓，保留原源。

导入读取局部、版式/母版及主题声明，缺省为无端点和中尺寸。编辑只替换指定节点，保留线宽、颜色、几何、文字、身份及其他部件；多选共享原子事务、精确历史和保存重开。重复直接值不增加历史。`noChangeArrowheads` 锁、只读/继承/组内对象、未知类型/尺寸/属性/子节点、重复声明、端点内注释及预算失败继续保护。连接线吸附和目标联动仍待实现。尺寸参考 [ONLYOFFICE EndArrow](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L7331-L7400)，轮廓参考 [DrawLineEnd](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L51-L500)；未复制上游源码。实现归 [`line-end.mbt`](../../modules/formats/src/pptx/line-end.mbt)、[`line-end-edit.mbt`](../../modules/formats/src/pptx/line-end-edit.mbt)及 [`pptx-line-ends.tsx`](../../packages/ui/src/pptx-line-ends.tsx)。

主题颜色支持 sRGB、带 `lastClr` 的系统色、主题/颜色映射以及 tint、shade、lumMod、lumOff。支持无填充、纯色填充、实线及标准预设虚线、主题填充/边框/背景引用和无效果样式。未知颜色变换、填充或可见效果保留源并诊断，不静默宣称完整。占位符依类型/索引匹配，当前属性按具体声明覆盖继承值；写回不修改共享主题、母版或版式。

字体键为有效 family，按需附加 `|bold` / `|italic`。主/次字体、显式 Latin/EA/CS 字体及当前常见脚本映射参与解析；自动推断覆盖 Latin、简中 Han 缺省、Kana、Hangul、Arabic、Hebrew、Devanagari 和 Thai。语言敏感的 Han 区域字体推断尚未扩展；不声明全语言主题字体一致性。调用者提供授权字体及实际样式映射，缺失时明确失败。

文本框读取基本字号、粗体/斜体、文字色、段落对齐、内边距、缩进、点值/百分比段距及行距、软换行和字符项目符号的字体/大小/颜色。固定框越界诊断并裁剪；无法建立文字几何时保留边界占位和对象文本查询。`normAutofit` 以 10 次有界搜索求解 10%–100% 字号缩放，同时检查可用宽高，保存必要 `fontScale` 并保留基准字号。字段所在框保持文字编辑保护；简单编号字段的显示见下节。其他字段、图片项目符号、多栏、纵排及文字变形继续诊断或保护。

`editPptxObjects` / `PresentationEditor.editObjects` 已支持 `{ action: "textInsets", left, top, right, bottom }`、`{ action: "textAnchor", anchor }`、`{ action: "textWrap", wrap }` 和 `{ action: "textFit", fit }`。四边距离为 0–14400 pt，舍入为整数 EMU，须保留有效文字区域；anchor 为 `t`、`ctr` 或 `b`。布尔 wrap 控制框内换行。fit 为 `none`（固定框）、`shrink`（缩小字体）或 `resize`（形状随文字调整大小），分别保存 `noAutofit`、`normAutofit` 或 `spAutoFit`。它们作用于所选本地顶层文本形状，文字模式和对象模式均可调用，多选合为一次源事务。默认 UI 提供四边输入、垂直对齐、换行开关和适配模式，保留待提交的原生文字输入。

每个 `PptxObject.textFrame` 返回有效 `left/top/right/bottom/anchor/wrap/fit` 及保护原因 `reason`。修改保留文字、字符格式、身份、选择和其他部件；缺失 `bodyPr` 与适配节点按 DrawingML 顺序创建，其他属性和非目标注释原样保留。`shrink` 重新测量并保存比例，10% 字号仍无法容纳时原子拒绝。`none` 保留当前尺寸及固定框越界诊断。

`resize` 保留名义字号。开启换行时保持宽度、调整高度；关闭换行时按显式段落和软换行调整宽高，内容减少时也收缩。复用当前预设形状文字内框及段落测量，计入边距、列表和行段距。未旋转对象按首段水平对齐与框垂直锚定保持对应位置；旋转对象保持中心及方向。原生输入、字符/段落格式、框属性、查找替换和变换完成时，几何与文字合为同一项精确历史。保存重开沿用已写入几何，后续编辑继续重算。行为依据 [ONLYOFFICE 文字内框及位置更新](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L3646-L3870)，实现归 [`text-resize.mbt`](../../modules/formats/src/pptx/text-resize.mbt)。

无变化不增加历史。形状边长沿用 0.1–14400 pt，尺寸向上取整到 EMU；预设内框求逆不重复测字，最多 16 次文字重排。超限、无可用内框、不收敛、变换锁、缺字体、未知适配内容或输出/历史预算失败均原子拒绝。候选和旧 revision 保持既有保护。组内/继承对象及独立保持直立的旋转文字仍待对应编辑支持；普通水平文字沿用已有裁剪、Canvas 与 PDF 路径。

`editPptxObjects` / `PresentationEditor.editObjects` 支持 `{ action: "textFormat", format }`，其中 `PptxTextFormat` 可包含 `font/size/bold/italic/color/underline/strike/highlight/script`。至少提供一项，省略项保持；不接受 null 清除或未知字段。font 为不超过 200 UTF-16 单元的实际字体族，不能包含 `|`、换行或以 `+` 开头；主题字体编辑见[主题字体](#主题字体)。size 为 1–1024 pt，核心舍入到 0.01 pt。color 为六位 RGB 十六进制，查询和保存规范为小写。字体族同时写入 latin/ea/cs，授权字体与样式仍通过宿主 profile 供应。

文字模式修改选中字符，光标处创建用于后续输入的格式；空段落写入 `endParaRPr`。对象模式作用于所选本地顶层文本框，混合多选合为一项事务。`{ action: "textAlign", alignment: "left" | "center" | "right" | "justify" }` 修改所涉段落，对象模式修改框内全部段落。`PptxQuery.formatting` 返回上述九项字符属性及 `alignment` 的共同有效值，混合值为 null；`reason` 返回保护原因。无可编辑选择时为 null 占位，不是源格式。两种类型从 `wasm/pptx` 和 `web/pptx` 导出。

`justify` 写回 DrawingML `algn="just"`，导入和继承使用相同有效值。默认格式面板提供“两端对齐”按钮；自动换行的中间行沿公共段落排版扩展间隔，末行保持自然宽度，原生输入、命中、光标、适配和 Canvas/PDF 使用同一组坐标。无变化时不增加历史；清除段落直接格式恢复继承。行为参考 [ONLYOFFICE 段落两端对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L5255-L5261)，源值参考 [TextAlign](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Limit/TextAlign.cpp#L44-L77)。分散对齐和 `justLow` 等变体仍保护，不将其默认为两端对齐。

underline/strike 为布尔值，保存为 DrawingML 的 `u="sng"/"none"` 和 `strike="sngStrike"/"noStrike"`。highlight 接受六位 RGB 或空串；空串清除高亮，写入含 `alpha=0` 的透明颜色以覆盖继承，并保留继承定义。查询空串表示无高亮，null 表示混合或保护占位。高亮沿既有纯色/主题颜色解析；未知内部标记及其他透明度仍保护。公共 `Line::positioned` 在文字前输出高亮，在文字后输出同文字颜色的下划线与删除线，使用塑形光标确定装饰范围；装饰修改保留 glyph、光标和逻辑文字。Canvas 与 PDF 共用此图元序列，PPTX 继续在框边界裁剪。DrawingML 属性及高亮写回参考 [ONLYOFFICE RunProperties](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/RunProperties.cpp#L233-L238)和[字符属性输出](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/RunProperties.cpp#L425-L452)。双线、波浪/虚线、自定义线色等其他装饰继续实施。

script 接受 `baseline`、`superscript` 或 `subscript`，分别写入 DrawingML `baseline=0/30000/-25000`。恢复基线写 0 覆盖继承，清除直接格式移除本地 baseline 并恢复继承。导入按首个有效 baseline 的正负识别上、下标，保留未改源值；此行为遵循 [ONLYOFFICE 读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L8957-L8966)和[写出](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/SerializeWriter.js#L2202-L2205)。查询字号保留名义值，公共布局按 65% 绘制字号及名义字号的 +35%/-14.1% 基线偏移排版，沿用 [ONLYOFFICE 脚本度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/commonDefines.js#L799-L802)。原生输入、命中、光标、选区、适配、Canvas 与 PDF 共用相同文字布局；任意数值偏移编辑仍待支持。

字符操作按需拆分 run，保留范围外文字、字符和段落属性、命名空间、对象身份、几何及其他部件。后续输入继承光标格式，替换范围继承首个选中字的格式。格式、对齐及原生文字共用精确历史；无变化不增加历史。已有缩小适配继续重新测量和保存比例，固定框继续诊断并裁剪溢出。候选、旧 revision、缺字体、锁定、未知 run/格式扩展或输出预算失败保持源和历史。字段、组内和继承对象继续保护。行为参考 [ONLYOFFICE 当前文本范围操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L1373-L1415)。更多装饰和图片项目符号仍待实现。

`{ action: "clearTextFormat" }` 清除所选 run 的字体、字号、粗斜体、下划线、删除线、文字色和上/下标直接定义，恢复段落、列表、版式及主题继承。保留高亮、语言、链接与源间隙；高亮使用独立的空串操作关闭。文字范围按需拆分 run；光标处建立用于后续输入的继承格式，空段落清除 `endParaRPr` 对应覆盖。对象模式清除所选本地文本框的 run 及段尾字符覆盖，保留段落默认字符定义。源中显式写出的默认值也会移除；再次清除不新增历史。语言与高亮保留规则参考 [ONLYOFFICE 字符清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L16926-L16947)。

`{ action: "clearParagraphFormat" }` 清除所涉段落的直接对齐、左/右/首行缩进、行段距及本地项目符号、编号、符号字体/大小/颜色定义，恢复继承。保留 `lvl`、`defRPr`、字符内容及其元信息；图片项目符号和未支持的编号类型仍保护。段落选择沿用 `textParagraph` 的范围规则，对象模式处理全部所选框。清除沿现有源事务、字体预检、适配与输出预算执行；未知格式标记或失败保持源与历史，撤销精确恢复原属性和选择。默认 UI 提供两个清除按钮，宿主与 Worker 沿 `editObjects` 调用。语义参考 [ONLYOFFICE 段落清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L11606-L11663)。

`{ action: "textParagraph", format }` 修改段距、行距、缩进、方向及列表。`PptxParagraphFormat` 可含 `left/right/first/before/after/line/list/level/rtl/listFont/listSize/listColor`，至少提供一项，省略项保持。仅三个标记样式字段接受 null，含义见下文；拒绝其他 null 和未知字段。left/right 为 0–4032 pt，first 为 -4032–4032 pt，相对段落起始侧缩进指定首行或悬挂缩进，核心舍入为整数 EMU。before/after/line 使用 `PptxTextSpacing`：`{ unit: "point" | "percent", value }`。段前/段后点值为 0–1584 pt，百分比为 0–1000%；行距点值至少 0.01 pt，百分比至少 0.001%，上限相同。点值和百分比分别保存到百分之一点和千分之一百分比；100% 为单倍行距。输出范围与顺序参考 [ONLYOFFICE TextSpacing](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/TextSpacing.cpp#L90-L162)及[段落属性](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/TextParagraphPr.cpp#L196-L218)。

`rtl` 为布尔值，写入 DrawingML 段落方向；读取沿本地、列表、版式/母版和默认属性继承。缺少显式对齐时，RTL 默认右对齐；已有显式对齐仍按物理左右解释。切换方向时镜像当前左右对齐，居中和两端对齐保持，遵循 [ONLYOFFICE SetParagraphBidi](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L16952-L16967)及[非文档段落的默认对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L11257-L11288)。缩进、标记和双向文字使用公共排版器；PPTX 显式提供 LTR/RTL 基础方向，避免阿拉伯文首字符覆盖段落设置。字体、光标、选区、Canvas/PDF 和适配共用同一结果，缓存区分基础方向。`paragraph.rtl` 返回有效布尔值或混合值 null；默认面板显示混合复选状态。清除段落直接格式同时清除方向并恢复继承。局部范围、多框、原生草稿、精确历史与重开沿用已有事务，非法方向源保留并诊断。竖排、多栏和组内直接编辑继续实施。

文字模式修改光标所在或范围所涉段落，终点恰在下一段开头时不修改下一段；对象模式修改所选本地文本框中的全部段落。`PptxQuery.paragraph` 返回各字段的共同有效值和 `reason`，混合项为 null；保护时为 null 占位。类型和动作从 `wasm/pptx`、`web/pptx` 导出，宿主沿 `editObjects` 队列执行。修改只写目标 `pPr`，保留字符、未改属性、源注释、继承定义、非目标段落、部件及选择。未知间距节点内容保护该框的间距/缩进操作；无变化不新增历史，旧 revision、候选、缺字体、无可用行宽和预算失败均不提交。已有适配框重新计算比例；固定框保留溢出诊断。默认面板按各字段的有效值更新草稿，其他格式命令完成时不清掉输入。

list 使用 `PptxListFormat`：`{ kind: "none" }`、`{ kind: "bullet", value }` 或 `{ kind: "number", value, start }`。字符符号限一个字素、最多 16 UTF-16 单元；编号支持十六种格式：`arabicPeriod/arabicParenBoth/arabicParenR/arabicPlain`，以及 `alphaLc/alphaUc/romanLc/romanUc` 分别与 `Period/ParenBoth/ParenR` 组合。`Period` 使用句点，`ParenBoth` 使用左右括号，`ParenR` 使用右括号，`Plain` 不加标点；例如 `alphaUcParenBoth` 输出 `(A)`。start 为 1–32767。level 为 0–8；默认 UI 显示第 1–9 级。列表与级别可分别修改，也可和间距/缩进一起提交。查询返回有效列表定义及级别，混合值为 null。移除列表写 `buNone` 覆盖继承，清除段落直接格式移除本地列表定义并恢复继承，保留级别。

编号在各文本框内计算：向前跳过更深层段落，遇到更浅层、不同类型或不同起始值时重新起算；同级空段落不推进后续数字。规则依据 [ONLYOFFICE GetBulletNum](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L10678-L10717)。字母与罗马数字沿用 DOCX 的公共序号格式化，字母采用 aa、bb 等重复规则。逻辑文字与复制内容保留原段落文字，编号是布局标记。

首次应用列表按首个字符字号建立悬挂缩进，移除列表恢复标记所在左边界；显式 left/first 优先。规则参考 [ONLYOFFICE 列表缩进](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L10616-L10643)。保留已有符号字体、字号、颜色和其他段落元信息。标记进入公共段落布局，参与换行、行高、字体预检、适配及 glyph 预算，使用当前 36 pt 默认制表间隔分开标记与正文；Canvas 和 PDF 共用相同位置。已有字符内容、非目标段落、部件、选择及精确历史保持。格式值沿 [ONLYOFFICE DrawingML 编号枚举](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Limit/TextAutonumberScheme.cpp#L46-L88)，括号与标点沿 [PresentationNumbering](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/PresentationNumbering.js#L188-L298)；源保留完整类型，导入、修改、原生续号和重开使用同一标记规则。默认面板列出各格式的标记示例，Wasm 与 Worker 参数/响应校验共享同一允许列表。图片符号、地区编号和自定义制表设置仍待支持。

`listFont/listColor` 使用与字符格式相同的字体家族及六位 RGB 边界。`listSize` 使用 `{ unit: "point" | "percent", value }`，支持 1–1024 pt 或正文首字符字号的 1–400%，分别舍入到百分之一点和千分之一百分比。查询返回有效字体家族、颜色及继承后的大小单位/值；随文字大小返回 100%，混合字段为 null。显式样式分别写 `buFont/buSzPts/buSzPct/buClr`；传 null 写对应的 `buFontTx/buSzTx/buClrTx`，覆盖继承并跟随正文首字符。默认面板逐项设置，并可一次恢复三项正文样式；`clearParagraphFormat` 则移除本地定义并恢复列表/版式继承。规则依据 [ONLYOFFICE 标记属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L12797-L12876)。只修改所选段落的对应属性，保留字符、列表定义、字体元信息和其他部件；相同直接定义不新增历史。重复或带未知内容的目标属性保护整项事务，缺字体与输出预算失败也不提交。

字面查找由 `findPptx` 命令和 `PresentationEditor.find(text, options?)` 提供。`PptxFindOptions` 可含 `matchCase/wholeWord/all`；前两项默认 false，all 默认 true，并包含隐藏页。all=false 只搜索请求指定的 slide，结果导航后仍保留原搜索范围。扫描按页面顺序及本地对象源顺序进行，跨 run/段落匹配，不跨文本框；母版/版式装饰与备注不参加本次查找。页面/对象顺序参考 [ONLYOFFICE Slide.Search](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L346-L355)。分组内或带字段/扩展的已解析文字可返回结果及保护原因，替换沿现有本地顶层文本框边界开放。

`PptxSearchResult` 返回 revision、truncated 及最多 1000 条 matches；每条含 `slide/object/anchor/focus/hidden/snippet/reason`。anchor/focus 是该对象文字的 UTF-16 范围，并对齐字素边界；跨段落使用 LF，软换行使用 U+2028，编号标记不属于逻辑文字。与 DOCX 共用公共字面搜索：简单 Unicode 小写映射、不忽略重音、全词使用字母/数字边界，结果不重叠；不提供正则、通配符或语言分词。查找不改变选择、源、revision 或历史。

`replacePptxMatches` 携带同一 revision、原 slide/text/options、replacement、可选 index 和字体 profile；不提供 index 时替换全部。核心重查结果后定位各对象，按对象范围提交一项跨页历史。普通段内替换合并源补丁并继承首个选中字的字符属性，保留未选 run、段落属性及其他部件；跨段落或 LF 替换复用结构编辑。有变化时，单个替换定位到新文字末尾，全部替换保留当前页/对象并调整已有文字选区。无变化不新增历史，任一保护、缺字体/字形、适配或输出失败均保留所有页面及历史。

搜索文本与 replacement 各最多 32767 UTF-16 单元；replacement 接受 LF/U+2028，拒绝 CR 和非法 XML 字符。搜索总文字限 1048576 单元，截断结果禁止全部替换；结构批次另受源文字长度乘匹配数累计 64 Mi 单元和 4 MiB 历史预算限制，普通批次不按匹配重复解析整页。公共原生生成文字也在构造 XML 前限制到 2 Mi 单元。宿主的 `find/selectMatch/replaceMatches` 沿既有队列执行，并绑定 documentId/revision；换文档或文字变化后返回 stale-search。默认面板提供当前页/全部页、大小写/全词、结果定位、单个/全部替换、保护原因及过期提示。隐藏页结果可直接定位。

支持矩形、椭圆、直线与文本框的核心路径；PNG/JPEG、矩形源裁剪、旋转/翻转和组合坐标变换。组合成员与继承对象只读；本地顶层对象可通过核心/API/UI 旋转、翻转和调整层次。图片不发起外链请求，源压缩字节与关系不改；只为当前页准备屏幕资源。全稿 PDF 临时准备所选页资源，仍受累计图片/输出预算约束，失败不返回截断文件。

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
| 历史 / 宿主队列 | undo+redo 共 100 项、4 MiB 源补丁 payload；编辑与指针意图队列各 64 项，指针预览只保留待发送末次坐标 |

P6 基础与检查边界归 [P6 结果](../implemented/p6-pptx-editing.md)，增量创作能力与剩余范围归 [P12](../p12-pptx-core.md)。Chromium 受控输入事件已验证；没有追加系统输入源、Windows/PowerPoint、VoiceOver、其他浏览器或性能验收。

### 对象超链接

`PresentationEditor.editObjects({ action: "hyperlink", link })` 修改所选本地顶层对象或其文字的点击链接。对象模式支持单个形状、图片或组；文字模式支持一个可编辑文本框。`link` 为 `{ kind: "external", target }`、`{ kind: "slide", target }`、`{ kind: "action", target }` 或 null；null 移除点击链接。动作 target 只接受 `firstslide`、`lastslide`、`nextslide`、`previousslide`。`PptxHyperlink` 从 `wasm/pptx` 和 `web/pptx` 导出。每个 `PptxObject.hyperlink` 返回对象链接的 `{ value, reason }`；`PptxQuery.textHyperlink` 返回当前文字范围的 `{ value, mixed, reason }`。链接不一致时 value 为 null 且 mixed 为 true，默认面板仍允许统一设置或移除。多对象与继承对象继续保护。

文字选区按 UTF-16 字素边界拆分 run，可跨样式、软换行及段落，只修改选中范围。链接内的光标修改当前段落中相邻且关系及提示等元数据一致的完整链接；不同提示或关系保持独立。普通光标通过空 run 或空段落末尾属性设置后续输入链接。原生输入继承链接，移除时同步对应段落末尾属性，避免清空后再次出现。保留直接字体、大小、粗斜体、颜色和源下划线；存在点击链接时派生单下划线，移除后恢复原直接定义。文字链接写入 `rPr/endParaRPr`，与对象的 `cNvPr` 链接独立；累计生成源限制为 2 Mi UTF-16 单元。

外部地址最多 2048 UTF-16 单元，只允许 HTTP、HTTPS 和 mailto，拒绝空目标、空白、控制字符及反斜杠。内部页目标使用当前文稿的稳定 slide 部件身份，不能使用页序号；允许显式跳转隐藏页。默认面板创建、修改及移除链接，单独的打开入口才导航。外链使用新窗口和 `noopener noreferrer`。`PresentationEditor.followHyperlink()` 及 Wasm/Worker 命令 `{ operation: "followPptxHyperlink", revision }` 从当前单个对象或一致的文字链接解析内部页/动作，再由核心定位；拒绝混合链接、外链、旧修订及活动候选。四种动作按当前编辑页序执行，包含隐藏页；上一页/下一页在边界停留并保留选择。重排、复制及删除页后按新位置解析，不保存过期页序号。导航不改源、revision 或历史；显示、打开文件和布局不自动请求外链或执行动作。脚本、文件地址、相对网址、宏、上次查看页、结束放映及其他放映动作继续保护源。

核心写 `cNvPr/a:hlinkClick`：外链使用 External hyperlink 关系，内链使用 slide 关系及 `ppaction://hlinksldjump`。四种导航动作写 `ppaction://hlinkshowjump?jump=…` 和空 `r:id`，不创建关系；导入时按 action 解析，允许省略、空或原有关系身份。与目标相同的关系可复用；修改不覆盖其他对象共用的关系，也不清理旧关系。保留 tooltip、tgtFrame、history、highlightClick、endSnd、相邻悬停链接、注释、文字和几何；未知属性、声音等子内容或无法解析的关系保护修改。新增关系与对象 XML 共用一项有界历史，旧 revision、活动候选、锁和输出预算失败均不提交。相同链接及重复清除不新增历史。

页面重排保持内部目标，页面复制复用既有自身链接重映射，删页移除相应入链并保留对象。对象复制保留链接；带自身点击或悬停链接的组不能直接取消组合，避免丢失组动作。普通点击链接移除后可取消组合，成员自己的链接保留。静态 Canvas/PDF 保留对象外观及文字，不增加交互链接注释。悬停/一般动作编辑、放映点击行为及输出链接继续按 [P12](../p12-pptx-core.md) 实施。语义参考固定 [ONLYOFFICE 对象链接操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L3503-L3683)、[文字链接拆分与光标操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L7811-L8180)、[PPTX 链接下划线](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L10545-L10565)、[内部页动作解析](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L9259-L9290)及[编辑器显式导航](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/api.js#L7243-L7264)，实现归 [`object-hyperlink.mbt`](../../modules/formats/src/pptx/object-hyperlink.mbt)和 [`text-hyperlink.mbt`](../../modules/formats/src/pptx/text-hyperlink.mbt)。

### 当前页 PNG 输出

`PresentationEditor.exportPng(scale = 1, outputBytes = 67108864)` 返回 `EditorOutput`，`format` 为 `png`。它按现有输入队列导出当前已提交页面，包括明确显示的隐藏页。活动输入/变换候选先完成或取消；布局缺失或与当前页/修订不符时拒绝。选择、源文档、历史、预览尺寸和保存基线保持；导出失败保留编辑与原格式保存入口。

`scale` 为每 pt 的像素数，接受 0.25–4；图片宽高分别为 `ceil(width * scale)` 和 `ceil(height * scale)`，默认 960×540 pt 文稿生成 960×540 px PNG。预览 zoom 和屏幕 DPR 不决定导出尺寸。编码前要求临时图片与现有页面/覆盖层 Canvas 合计不超过 16,777,216 像素；`outputBytes` 为 1–67,108,864 的整数，在复制编码字节前检查 Blob 大小。所有路径释放临时 Canvas；复用的图片和字形路径继续由当前表面持有。

默认文件菜单的“当前页 PNG”使用相同 API。`onSave` 收到 `format: "png"` 及 `.png` 名称的派生输出；没有回调时按 `image/png` 下载。PNG 输出不能 `markSaved`，也不清除 PPTX 未保存状态。它通过当前 R0 执行器重放核心图元，保留已有诊断的显示结果；图片、裁剪、旋转与文字沿现有渲染范围，选择框和光标只在编辑覆盖层中。

此入口依赖浏览器 Canvas 绘制和 PNG 编码，当前只检查 Chrome/Chromium；不作为无浏览器 PNG 转换能力。普通 Wasm/Worker 文档状态、布局和 PDF 接口保持原职责。批量页图片、JPEG 及打印界面仍待实现。

### 日期与页脚编辑

`PresentationEditor.editSlides({ action: "footer", value, allSlides }, slide?)` 修改当前页或指定页的日期、页脚和编号。`allSlides=true` 时修改全部页面，包含隐藏页，合为一项历史。Wasm/Worker 的 `editPptxSlides` 使用同一命令。`PptxFooterContent` 为 `{ date: string | { format: number; language: "en-US" | "zh-CN" | "zh-TW" } | null, footer: string | null, number: boolean }`。date 的字符串表示固定文字，对象表示自动日期；format 为 1–13 的整数，对应 `datetime1`–`datetime13`。footer 是页脚文字，null 移除对应对象，空串保留空对象，number 控制编号占位符。MoonBit 使用 `FooterDate::Fixed(String)` 或 `FooterDate::Automatic(Int, String)`，沿 `FooterContent.date` 传入。`PptxQuery.footer` 返回这三项及 `reason`，类型为 `PptxFooter`。缺少对象时为 null/false；未知、复杂或受保护的页边内容返回保护原因。

每项文字最多 4096 UTF-16 单元、256 段，CRLF/CR 归一为 LF，软换行使用 U+2028。核心不读取系统时钟。已有日期和页脚保留对象身份、几何、框属性、列表样式及首段/首 run 格式；新文字使用该格式。相同文字、相同自动日期设置及已有真实编号不改源或历史，刷新后重新应用相同设置也不更新缓存。自动日期使用会话时间，核心缺少时间时拒绝创建；初次创建或改变格式/语言时把当前文字写入字段缓存。修改已有自动日期保留字段 ID、对象身份、几何及首段/首 run 格式，只覆盖所选语言；固定/自动切换和移除沿同一事务。开启静态编号占位符时创建真实 `slidenum` 域；已有真实编号保留缓存。关闭时移除对应本地占位符，并同步清除选择中已移除的对象。

创建优先采用当前版式，其次采用母版中的对应占位符，复制样式并继承几何；模板源保持不变。没有模板时创建独立本地占位符：默认 Arial 12 pt、黑色、自动缩小，日期左对齐、页脚居中、编号右对齐。三个框的 x 分别为页面宽度的 4%、36%、68%，宽度为 28%；y 为高度的 90%，高为 6%。字体仍由宿主授权 profile 提供。新对象及字段身份沿页面复制规则分配，不与原源冲突。

全部目标页完成文字布局、字体、适配和包/输出检查后一次提交。单个页边对象生成的 XML 最多 1,048,576 UTF-16 单元，事务仍受 4 MiB 历史预算约束；任何目标失败均保留原源、选择和身份分配状态。原生草稿先独立提交。只有单段、单个受支持日期域的本地日期占位符可查询并修改自动设置；混合文字/字段、重复/分组页边对象、未知或带注释的文本源、无法解析的模板和关系、删除锁/外部对象引用、缺字体、越界及旧 revision 继续保护。当前操作修改本地页面，不改写共享版式或母版，也不为以后新增的空白页建立全稿默认值。

默认面板提供日期、页脚、编号开关及应用到当前页/全部页。日期可切换固定文字和自动更新，自动模式可选择三种语言及十三种格式；选项以固定日期示例显示，不由 TypeScript 格式化文档日期。草稿在正文输入期间保持，切页和文档替换后按当前页重新加载。结构及内容替换参考 [ONLYOFFICE setHFProperties](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L1182-L1318)，实现归 [`footer-read.mbt`](../../modules/formats/src/pptx/footer-read.mbt)、[`footer-content.mbt`](../../modules/formats/src/pptx/footer-content.mbt)、[`footer-edit.mbt`](../../modules/formats/src/pptx/footer-edit.mbt)及 [`pptx-footer.tsx`](../../packages/ui/src/pptx-footer.tsx)。母版编辑继续实施，导入与刷新见[动态日期域显示与刷新](#动态日期域显示与刷新)。

### 动态日期域显示与刷新

导入的简单 `a:fld type="datetime1"` 至 `datetime13` 及 `datetimeFigureOut` 按会话时间生成派生文字，类型比较忽略大小写。支持 `en-US`、`zh-CN` 和 `zh-TW`，语言沿 run/段落/继承格式解析，缺省为 `en-US`。字段结构边界与简单编号域相同。缺少时间、未知语言/格式或扩展结构保留源缓存并诊断；继承及锁定对象也保留诊断。日期域继续拒绝纯文字编辑；专用日期面板/API 可修改简单日期占位符，范围见[日期与页脚编辑](#日期与页脚编辑)。

Wasm/Worker 的 `openPptx`、`createPptx` 接受可选 `dateTime`。平台缺省传入当地时钟的 `YYYY-MM-DDTHH:MM:SS` 日历分量；宿主可显式传入以固定结果。MoonBit 的 `Session::open/create` 接受 `date_time`，不传时保留日期缓存并诊断。核心校验公历日期、1–9999 年、0–23 时及 0–59 分秒；该输入不含时区尾部，也不进行时区换算。格式化由 MoonBit 完成，平台只提供时间分量。

`PresentationEditor.refreshDateFields(dateTime?)` 或 Wasm/Worker 的 `dateTimePptx` 更新会话时间；底层命令携带 revision、profile 和可选 dateTime。默认面板提供“刷新日期域”。刷新先检查活动候选、旧修订、所有可显示日期域的字体及框内布局，再统一更新派生文字并使旧布局失效。失败保留原时间、源、选择和历史。刷新不改变 revision、modified、撤销栈、字段代码、ID 或缓存。原格式保存保持源；预览、PNG 和 PDF 使用最近一次会话时间，打开和显式刷新之间共用同一快照。

源编辑、页面复制、主题/尺寸/版式变化及撤销重做沿当前时间重新解析日期。历史页面记录其计算时间，恢复旧快照时只重新解析过期页面，防止“撤销复制、刷新日期、重做复制”恢复旧值。可显示的版式/母版普通文字及组内日期域同样参与刷新预检；模板占位符仍沿既有版式实例化规则。

格式与地区映射依据 [ONLYOFFICE PresentationField](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/PresentationField.js#L61-L78)、[类型索引](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/PresentationField.js#L286-L365)及[地区格式表](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/commonDefines.js#L4625-L4656)。中文沿其格式表和 [Word 字段解析](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/NumFormat.js#L991-L1033)保留现有结果：`datetime4/6` 中的 `W` 是字面文字，`datetime5` 使用时分秒，`datetime13` 的后备格式在 AM/PM 前保留冒号。已有缓存的独立显式写回、更多语言及备注字段继续实施。实现归 [`date-fields.mbt`](../../modules/formats/src/pptx/date-fields.mbt)及 [`pptx-clock.ts`](../../packages/wasm/src/pptx-clock.ts)。

### 幻灯片编号字段

导入的 `a:fld type="slidenum"` 按演示文稿 `firstSlideNum` 加从零开始的实际页序生成十进制文字，类型比较忽略大小写。起始编号缺省为 1，接受 0–4294967295；隐藏页保留编号位置。行为依据 [ONLYOFFICE PresentationField](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/PresentationField.js#L187-L220)。

当前支持带非空 `id`、可选 `rPr/t` 且无其他字段属性或子节点的形式。字号、颜色和字体沿现有文字解析；派生数字进入查询及 Canvas/PDF 共用的定位输出。重排、复制、删除与撤销重做同步更新，读取和保存不刷新源缓存，也不新增修订。字段所在框继续拒绝纯文字编辑，其他字段和带段落属性/未知扩展的字段保留缓存并诊断。创建和移除见[日期与页脚编辑](#日期与页脚编辑)，版式占位符创建沿[幻灯片版式](#幻灯片版式)；母版直接编辑继续实施。实现归 [`text-fields.mbt`](../../modules/formats/src/pptx/text-fields.mbt)。

### 演讲备注

`PresentationEditor.editSlides({ action: "notes", text }, slide?)` 和同步 Wasm/Worker 的 `editPptxSlides` 修改指定页的普通演讲备注。`PptxQuery.notes` 返回当前页的 `{ text, reason }`。`text` 是完整备注正文；空串清空，CRLF/CR 归一为 LF，段落用 LF、软换行用 U+2028。每页最多 32767 UTF-16 单元，每段最多 4096，最多 256 段；生成 XML 另限 2 Mi 单元，并继续受包、输出和 4 MiB 历史预算约束。

未有备注时，非空文字创建标准 notesSlide、备注到 slide 的回链、slide 到备注的关系及内容类型，合为一项历史。正文使用 `p:ph type=body`，自带按 notesSz 比例计算的位置与尺寸；已有 notesMaster 时关联该母版，不另建或修改备注母版。备注正文结构参考 [ONLYOFFICE CreateNotes](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Notes.js#L387-L430)；可选母版关系见 [Open XML SDK 约束](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/generated/DocumentFormat.OpenXml/DocumentFormat.OpenXml.Generator/DocumentFormat.OpenXml.Generator.OpenXmlGenerator/Part_NotesSlidePart.g.cs#L242-L244)。已有备注没有正文占位符时，在其形状树追加独立正文并分配未占用身份。

修改只替换正文段落，复用首段段落属性与首个 run 的字符属性。正文框属性、列表样式、其他占位符（含页码字段）、其他部件/关系、外围注释及未知源保留。清空保留备注页和空正文；没有备注时清空、相同文字修改均不增加 revision 或历史。选择、幻灯片内容与对象身份保持，原生输入先按既有队列独立提交。撤销新增备注时保留该部件的 XML 身份分配状态，支持其后修改/清空的完整重做。

备注归属必须唯一并正确回链。共享/外部备注、多个正文占位符、字段或未知正文节点/属性、被改范围内注释/处理指令、修改保护、旧 revision、活动候选及预算失败原子拒绝。保护性查询返回空 `text` 和明确 `reason`，不把未知正文当作可修改文本。页面复制沿已有部件闭包创建独立备注并重映射回链；删除仅回收独占备注，精确历史与保存重开共用同一事务。

默认面板提供多行输入、应用和清空，正文草稿在应用后进入文档；切页按当前备注更新面板。备注不加入幻灯片文字、字体/图像资源准备、查找或静态 PDF，不改变幻灯片 Canvas。备注富文本控件、母版/打印布局、日期/页脚和演讲者界面仍按 [P12](../p12-pptx-core.md) 后续范围实施。批注归下节。实现归 [`slide-notes.mbt`](../../modules/formats/src/pptx/slide-notes.mbt)、[`notes-read.mbt`](../../modules/formats/src/pptx/notes-read.mbt)、[`notes-create.mbt`](../../modules/formats/src/pptx/notes-create.mbt)及 [`pptx-page.tsx`](../../packages/ui/src/pptx-page.tsx)。

### 本地批注与回复

`PptxQuery.comments` 返回当前页的 `{ items, reason }`。条目包含稳定的 `id`（规范化的 `authorId:idx`）、作者 `author`、`initials`、源 `date`、纯文字 `text` 和根批注 `parent`；根的 `parent` 为 `null`。支持传统 `p:cmLst` 和 PowerPoint 2012 的单层回复，按源顺序返回。缺失作者、重复身份、悬空/嵌套回复、现代云批注及未知扩展返回保护原因，不把未知源当作可编辑文本。

同步 Wasm、Worker 的 `editPptxSlides` 和 `PresentationEditor.editSlides(change, slide?)` 共用以下命令：

| action | 字段与结果 |
| --- | --- |
| `commentAdd` | `text`、`author: { name, initials }`、`date`、`parent: string \| null`；创建根或回复指定根 |
| `commentUpdate` | `id`、`text`；只修改文字，保留作者、日期、位置及已知扩展 |
| `commentRemove` | `id`；删除回复本身，或删除根及全部回复 |

作者必须由宿主显式提供。默认 UI 从 `EditorOptions.commentAuthor` 读取新批注/回复作者；未提供时仍可读取、修改和删除已有批注。界面提供当前页的批注列表、文字编辑及回复输入，草稿保留至提交；创建时间由平台以 UTC ISO 字符串传入，核心校验日历与时间。核心不读取系统账号或时钟。修改文字保留原日期，导入的缺失日期和原日期文本原样保留。

新文字必须非空，最多 32767 UTF-16 单元，CRLF/CR 归一为 LF。作者名非空且最多 255 单元，缩写最多 32；新作者字段不接受控制字符。每页最多 4096 项、合计 1 Mi 文字单元，全稿作者最多 4096 项；新建/复制索引分配扫描最多 16384 个保留批注，并同时预留作者 `lastIdx`，避免导入索引滞后造成重复。回复只指向同页根批注，新根位置为 `(0, 0)`，新回复沿用根位置。位置和批注文字不进入幻灯片 Canvas 或静态 PDF；当前面板以页面归属展示。

首次创建把 comments、commentAuthors、两处关系和内容类型合为一项有界历史。删除最后一项保留空批注部件和作者。已有 XML 的外围注释、局部命名空间、日期、位置，以及已知 `threadingInfo`/`presenceInfo` 保持。页面复制分配新索引、同步作者 `lastIdx` 并重映射每个回复的父索引；删除页仅回收独占批注，保留全稿作者。共享/外部部件、未知文字节点/属性、未知扩展、旧 revision、活动候选和包/输出/历史预算失败原子拒绝。所有操作复用现有页面编辑队列、部件事务及精确撤销重做。

回复格式依据 [ONLYOFFICE core Comments.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Comments.cpp#L659-L722) 的 `p15:threadingInfo/p15:parentCm`，作者及根/回复索引依据 [Presentation.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L11145-L11230)。未复制上游源码。现代批注、提及/解决状态、协作服务和画布批注标记继续实施。实现归 [`comments-read.mbt`](../../modules/formats/src/pptx/comments-read.mbt)、[`comments-create.mbt`](../../modules/formats/src/pptx/comments-create.mbt)、[`comments-edit.mbt`](../../modules/formats/src/pptx/comments-edit.mbt)及 [`pptx-comments.tsx`](../../packages/ui/src/pptx-comments.tsx)。

## PDF 输入与文档操作

`@open-document/wasm/pdf` 的 `PdfSession` 与 `@open-document/web/pdf` 的 `PdfClient` 共用类型化 `execute(command)`。同步入口由 `loadEngine(wasm).openPdf()` 创建，Worker 入口为 `PdfClient.open(wasm, workerUrl)`。字体使用 `addFont(bytes, identity)`。一个 UI 独占一个 client；低层调用方逐条 await 请求。

| 命令 | 输入与结果 |
| --- | --- |
| `defaultPdfBudget` / `openPdf` / `queryPdf` | 默认预算；显式 bytes/budget 打开；查询当前源快照 |
| `renderPdfPage` | revision、page、profile；当前页 `PdfLayout`、DrawingBatch、文字 spans 与独立完整性/诊断 |
| `extractPdfText` / `searchPdfPage` | revision、page、profile；提取或给出 query 的字面命中与 quads，不切换展示页 |
| `hitTestPdf` / `selectPdf` / `selectedPdfText` | layoutId；point 命中、UTF-16 anchor/focus 选区和复制文字；未知映射明确失败 |
| `imagePdf` / `decodedImagePdf` | layoutId/key；RGBA 或经过核心验证的 JPEG；宿主解码后提交匹配尺寸的 RGBA，核心应用 Decode/SMask |
| `reorderPdfPages` / `rotatePdfPages` / `deletePdfPages` | revision、稳定 pages；完整排列、degrees 或删除列表；返回新快照 |
| `addPdfNote` / `highlightPdfText` | revision；page/x/y/text 便笺，或当前 layoutId 的核心选区高亮 |
| `updatePdfAnnotation` / `deletePdfAnnotation` | revision、page、annotation；更新 text 或删除受支持批注 |
| `setPdfFieldValue` | revision、field、value、profile；文本或 boolean，同步所有 widget |
| `undoPdf` / `redoPdf` / `savePdf` | revision；历史操作返回快照，保存返回 `{ revision, bytes }` |

`PdfClient.defaultBudget()` 包装 `defaultPdfBudget`；同步 session 为 `defaultPdfBudget()`。page/field/annotation 身份绑定对象号和代数，页序单独返回。revision 单调递增，失败不提交；layoutId 在换页、编辑、字体变化和换文档后失效。`PdfQuery` 包含 pages、annotations、fields、当前 page、历史状态、modified 和 readOnlyReason/pageOrderReason。字段和批注另给各自的只读原因。

核心严格读取未加密 PDF 1.0–1.7，不修复损坏引用或回退旧修订。显示支持源坐标 TrueType、基础路径/裁剪、RGB/Gray、常量 alpha/Multiply、限定图片/Form 和 normal appearance。ActualText/ToUnicode/可信编码独立生成语义；未知 Unicode 使用 U+FFFC，不匹配未知范围，含未知范围的复制失败。显示与提取完整性分别返回。

未支持的图形状态、透明组、可选内容、颜色/字体/图片编码明确诊断；已知图片/批注可以局部限制，未知影响使整页预览不完整。完整正向范围和排除项见 [P7](../implemented/p7-pdf-input.md#已交付范围)。签名只读且未验证，非零代数保护改写，不执行脚本或外部资源。

编辑在原对象图上构造局部候选，检查后原子提交。页面关联、Tagged PDF 批注、锁定/富文本/动作、复杂字段和无法同步的 widget 受保护，范围见 [P8](../implemented/p8-pdf-operations.md#保护规则与限制)。`profile.form` 可指定已供应的可嵌入字体；新字段外观才进行塑形和文本框布局，PDF 正文保持源字距。

保存保留非目标字典及 stream 压缩 payload，重建 xref/trailer 并去掉旧增量/线性化声明。无编辑或全部撤销返回原字节。保存不替换基线、不清空历史；输出失败不改源。未引用对象仍保留，删除不能用于安全擦除、涂黑或脱敏。

### Web 嵌入与生命周期

`@open-document/web/pdf-viewer` 提供 `PdfViewer.create(root, client, profile?, signal?)`；`@open-document/web/pdf-editor` 提供相同所有权规则的 `PdfEditor.create`。先由调用者打开 client、供应文件和字体：

```ts
import { PdfEditor } from "@open-document/web/pdf-editor";
import { PdfClient } from "@open-document/web/pdf";

const client = await PdfClient.open(wasm, workerUrl);
await client.execute({ operation: "openPdf", bytes, budget: await client.defaultBudget() });
await client.addFont(fontBytes, "regular");
const editor = await PdfEditor.create(container, client, { form: "regular" });
propertyPanel.append(editor.propertyInput);
const saved = await editor.save();
// Persist saved.bytes, then editor.markSaved(saved) to confirm the output.
await editor.dispose();
client.dispose();
```

viewer 提供 `snapshot`、`displayedPage`、`refresh`、`goToPage`、`navigatePage`、`setZoom`、`selectText`、`selectedText`、`copy`、`extractText`、`search`、`cancelSearch` 和 `nextMatch`。editor 增加 `movePage`、`rotate`、`deletePage`、`highlight`、`addNote`、`setFieldValue`、`updateAnnotation`、`deleteAnnotation`、`chooseProperty`、`beginNote`、`applyDraft`、`cancelDraft`、`undo`、`redo` 和 `save`。自定义 UI 可以挂入稳定的 `propertyInput`，不另存一份属性草稿；切页/换文档/刷新/输出前应用或取消，组合期间禁止提交。默认 UI 的文件替换使用前述 `MountedEditor.open`。

队列最多 128 个已接受意图，保存排在已接受编辑之后。低层 `close()` 校验草稿并等待已接受操作后释放表面；`dispose()` 停止接收新操作和搜索，等待已接受操作后释放表面，两者都保留调用者的 client。呈现失败保留已提交源，停止新编辑，允许保存、刷新或显式撤销。Canvas 与派生资源只保留当前页；取消搜索及关闭后旧回复不能重绘。

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

字体、RGBA、图元、轮廓与 Canvas 沿用前述共同限制。PDF 源字体只显示时允许合法子集省略 cmap/OS2；需要重新嵌入时仍检查字体权限，未知权限拒绝。预算检查覆盖分配和循环，保存先保守估计编码大小，再核对确切大小；不保证总堆峰值或延迟。同步 Wasm 不可抢占，宿主只能在异步步骤间取消或终止 Worker。
