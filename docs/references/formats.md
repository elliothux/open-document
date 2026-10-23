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
| `print()` | 使用当前核心 PDF 请求 Chrome 打印对话框，返回 `Promise<void>`；范围与平台条件见[浏览器打印](#浏览器打印) |
| `getSnapshot()` / `subscribe(listener)` | 转发当前宿主的稳定快照；外部订阅跨文件替换保持，监听器异常不改变事务 |
| `close()` | 询问草稿和未保存修改；取消 `false`，完成关闭 `true`；等待在途保存回调后重新检查 |
| `dispose()` | 明确放弃内存会话，不弹确认；取消候选、等待已接受核心操作、释放 Worker/Canvas/React/自建 DOM；重复调用等待同一个 Promise，清理失败仍继续其他清理 |
| `setTheme()` / `setLocale()` | 更新 UI；保留文档会话、Canvas 和原生输入节点 |

每个实例追加一个自建容器与 open ShadowRoot，保留调用者原有 DOM。菜单与 Dialog 的 Portal 位于实例内；关闭确认是模态，会暂时限制整个页面交互。主题、关键尺寸与基础样式在实例内定义，宿主无需 Tailwind。当前目标只有 Chrome/Chromium。

框架无关的四类编辑宿主提供 `getSnapshot()`、`subscribe()`、`focus()`、`setPaused()`、`markSaved(output)` 和 `markDownloaded(output)`。快照包含会话身份、revision、导航、缩放、选区摘要、历史、诊断、停止/错误、在途操作及组合/拖动/草稿状态，并附格式当前查询。未变化时保持对象身份；已提交但绘制失败仍发布新 revision，保留保存与恢复入口。低层宿主借用 client，调用者等待宿主释放后另行关闭 client。

编辑宿主的原格式保存、Office PDF、DOCX/PPTX PNG、PPTX JPEG、XLSX CSV 和 DOCX HTML/Markdown 输出统一返回 `EditorOutput = { documentId, revision, format, bytes }`。`format` 另包含 `csv`、`png`、`jpeg`、`html` 和 `markdown`；编辑器输入格式仍为 DOCX/XLSX/PPTX/PDF。默认 UI 另加文件名 `name`。全页图片返回按页序排列的只读 `EditorOutput` 数组，具体合同见[DOCX 页面 PNG](#docx-页面-png)及[PPTX 图片输出](#当前页-png-输出)。此约定不改变原始 Wasm/client 的保存结果。只有该宿主实际产生的原格式输出可以 `markSaved`；旧会话、其他格式和任意裸 revision 都不能确认保存。确认的是输出 revision，其后新编辑仍显示未保存。导航、缩放和 UI 变化不修改文档。

原格式 `onSave` 成功才确认保存基线；失败保留修改并允许重试。缺省下载只提示“已生成下载”，不确认磁盘持久化，也不清除修改。PDF、PNG 和 CSV 导出不清除 Office 修改。关闭前选择“导出并继续”明确包含放弃内存会话。`dispose` 不等待宿主存储回调，晚到回执不更新已释放实例。

默认 UI 快照增加 `newDocument`。空白创建后即使 revision 为 0，`modified` 仍为 true；首次原格式 `onSave` 成功才清除此标记。下载不清除它，关闭与替换仍需确认。文件名去首尾空白、拒绝空名、路径分隔和控制字符；缺少当前格式扩展名时补齐。

保存回调期间若又有编辑，关闭/替换保留会话并返回 `false`。候选已经切换后，旧宿主清理失败只发布清理提示；新会话保持可用，`open` 返回 `true`。

DOCX/PPTX 的组合或拖动需要结束/取消。XLSX 保存先提交已支持的单格草稿；PDF 属性草稿须显式应用/取消。替换最多准备一个独立候选，加载界面的“取消”释放候选并恢复旧会话。核心保留原有文档校验、只读规则和预算。

### 浏览器打印

`MountedEditor.print()` 与文件菜单“打印…”共用既有输出队列。DOCX 打印全部页面，XLSX 按工作簿顺序打印全部可见表，PPTX 打印全部可见幻灯片；沿各自核心 PDF 路径保留页面设置、分页、字体、图形、诊断和输出预算。PDF 编辑器使用当前原格式输出。原生输入先经过现有屏障：XLSX 提交支持的单格草稿，其他格式的组合、拖动或属性草稿仍须结束或取消。重复打印请求复用在途输出，不再生成第二个预览。

平台将本地 PDF Blob 放入一个临时 iframe，加载后调用该窗口的 `print()`；Chrome 负责原生预览、页范围和打印机选择。实现参考 [MDN 打印示例](https://developer.mozilla.org/en-US/docs/Web/CSS/Guides/Media_queries/Printing#print_an_external_page_without_opening_it)，不使用 HTML 重新分页或截图代替矢量 PDF。宿主需允许 `blob:` iframe、内置 PDF 查看器及浏览器打印；受限容器仍遵循 Chrome 权限。Promise 完成只表示已发出打印请求，不表示用户已打印或保存。取消预览不作为文档错误，也不触发 `onSave`、下载或清除未保存状态。

每个实例最多保留一个打印 frame 与 Blob。`afterprint`、下一次打印、文件替换及释放实例会清理资源；部分 PDF 查看器不发送 `afterprint` 时保留到后三种操作。加载失败、30 秒未加载或原生调用抛错时拒绝并清理，文档与历史保持可用；释放实例会取消仍在等待加载的请求。当前验收只包含 Chromium 原生预览与生成的 PDF，不包含实体打印机或其他浏览器。

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

`deleteDocx(revision, direction)` 的方向为 `backward` / `forward`。已有范围整体删除；折叠选区按逻辑前/后扩展字素删除，复用范围事务和历史。组合符与 surrogate 不拆开。段首 Backspace/段尾 Delete 可合并同一正文或单元格内的相邻普通段落；文档首尾保持 revision、源和历史不变。折叠光标越过单元格边界、跨表格或受保护内容时报 `protected-content`；已有整格选区的清空归[跨格内容输入与清空](#跨格内容输入与清空)。

`editState()` 返回 revision、选区、撤销/重做可用性、历史容量与受影响段落；`selectDocx(revision, selection)` 仅更新选区。`replaceRange(revision, selection, text, inputGroup?)` 可跨 run，以及同一正文或单元格中连续的普通段落；`undoDocx(revision)` / `redoDocx(revision)` 恢复内容和选区，revision 继续单调增加。`selection` 保留 anchor/focus，每个位置包含稳定 paragraph ID、段落 UTF-16 offset 与 `before` / `after` affinity；范围按 XML 顺序排序，起点 affinity 决定 run 边界的插入格式。所有命令由 MoonBit 验证，TS 只转发和校验响应。

位置还可包含 `bidiLevel`（0–126 的整数）与 `frameStart`（大于 offset 的段内字素边界）。`frameStart` 保存导航保留的续接页框起点；光标查询只接受逻辑位置恰好位于该续接页框前一个字素的偏好，不能指向任意页。它只影响光标几何和导航，复制、输入、删除及选区矩形仍按逻辑 offset 计算。内容修改清除当前页框偏好，undo/redo 恢复完整选区元数据；只读查询、保存及失败不改变它。缺省字段使用原 affinity 和当前方向层级计算，不保留另一套状态或几何缓存。

编辑提交与后续布局是独立操作：提交成功后布局失败不会自动恢复旧源。浏览器停止输入，但用户可以明确 Undo；宿主排空原队列、取消其暂态组合，并核对当前 revision 后撤销一项历史和重排。失败仍保留停止状态，已完成的明确撤销不伪装为未发生；外部 revision 改动须先恢复，不自动撤销他人的编辑。恢复期间重复请求拒绝，销毁等待已接受的恢复，调用者 client 保留。

`selectedText(revision, selection, cut = false)` 返回核心只读纯文本，按 XML 顺序提取正/反向普通范围，跨段以 LF 分隔并保留空段，折叠范围返回空串。同表跨格提取所选整格，分隔规则归[跨格纯文本剪贴板](#跨格纯文本剪贴板)。它沿用字素、位置、revision、容器及内容保护检查，未知内容整体拒绝；不改变选区、revision、历史或布局。输出最多 65536 UTF-16 单元（包括 Tab 和 LF），超限报错而不截断。复制与结构写回共用范围顺序/保护检查；只有写回额外检查移动结构及格式。宿主不从页面文字重建选区。

段内边界使用 Unicode 13.0.0 扩展字素，跨文本节点的组合符与 ZWJ 不可拆开；修改后重新合并的字素会将光标推进到合法边界。普通空段支持 offset 0 的输入：优先在第一个已有空 run 创建 text，保留其格式；没有 run 时在段末创建普通 run/text，保留段落属性、现有前缀和非目标源片段。空段身份来自正文 `flow().paragraphs` 或 `flow().tables` 的单元格段落，不能从尚无 text 的 `query().texts` 推断。两端都在正文、完整包住普通表格的范围可沿下文[正文富文本片段](#正文富文本片段)处理。部分跨入单元格、跨不同表格端点、CR、未支持的域/修订/未知内联标记及受保护容器整体拒绝。受支持的行内图片、普通书签及跨格内容操作分别沿下文合同处理，未修改的源保留。普通正文与顶层表格单元格内的事务可用；不表示带布局诊断的文件已经可视编辑。

`replaceRange` 将实际 LF 作为段落分隔，可替换折叠、段内或跨段正反向范围，首尾/连续 LF 产生空段；新段仍在原 body/单元格内，光标到最后插入文字末尾，并对字素拼接推进到合法边界。原段及移到新段的存量节点保留身份；新节点获得单调 ID。新段继承已支持的段落属性和边界 affinity 选中的字符格式，显式关闭直接或继承的段前分页。未知属性、编号、节或不可安全编辑内容整体拒绝。多分隔替换是单条历史，返回原范围与全部新增段的受影响 ID；撤销删除新段并恢复原字节，重做恢复同一组新 ID。连续输入使用核心保留的目标 text ID 继续同一字符格式；显式选择/导航、删除、外部修改、undo/redo 和关闭终止它，保存或失败不终止。字符格式的连续目标与显式输入组分工不同，均不维护第二份文档内容。

候选 XML 与包预算校验成功后才提交状态。XML Document 是正文内容的唯一权威，Session 已删除文本覆盖表；解析顺序与稳定 `Node.id` 分离，结构插入不重编号相邻节点，删除身份不能继续查询。局部源补丁核对前片段、重放原身份并保留精确 XML；撤销全部改动后保存原 OPC 字节。文本节点、段落属性及命名空间仍由当前解析结果派生，不维护可独立修改的第二棵树。

跨段替换保留前段身份和段落属性，删除中间完整段落，将右侧存活 run/text 移入最终插入段并保留身份。其有效 namespace 与字符格式来自现有 XML/样式解析；上下文变化时固定受支持字体、字号、颜色和四种 bold/italic/script toggle，并保留已解释的语言与 script 属性，全局 styles/theme part 不变。无法清除的未指定继承属性、重复/错置属性、编号、节或未知结构整体保护。一条 XML 候选同时包含叶文本和结构补丁，一次提交一项历史；撤销/重做恢复原字节、身份及选区。

历史保存局部前后源片段、相关节点身份和选区，undo/redo 共计最多 100 项、4 MiB UTF-16 源片段 payload，单命令最多 65536 UTF-16 单元。payload 包含转义、属性及结构标记，不包含数组/节点身份与运行时分配开销；因此含转义的输入可能比纯文本计数更早达到上限。过大的单项整体拒绝，容量不足淘汰最旧完整项，可用边界与计数随结果返回。这些是实施期的安全上限，尚未完成实测校准与性能验收。当前每次提交仍重解析全篇候选 XML，没有声称局部编辑耗时或内存已达标。多分隔片段在字符串构造前检查复制放大，并继续按整个命令检查 XML、包与历史预算。连续普通输入已按下述显式输入组归并；纯文本剪贴板、组合核心/API 与 Chromium 事件宿主、段落塑形复用与稳定点分页已接入。系统输入记录的产物与范围见本节开头；当前 R0 产物未重做系统输入验收，候选窗几何及校准性能仍未测。

组合 API 使用当前已确认选区和 revision；`beginComposition` 返回单调正 i32 `compositionId`，后续更新/提交/取消必须同时匹配身份与 revision。暂态只持有原文档和一个当前范围候选，不累计中间历史；query/Flow/几何读取候选，`EditState.selection` 返回候选光标，`compositionId` 非空，但已确认 XML、选区、revision 与 undo/redo 不变。更新为空或等于原选中文字时显示原文档与原选区。最终非空文字重新经同一范围事务提交，最多一项历史；空结束/取消/同内容 no-op 保留源字节、选区与 redo。开始结束普通输入组；更新及结束继续校验 XML、65536 UTF-16 单元、包输出和历史预算，CR/tab/LF 拒绝，失败保留上一个合法候选。成功开始/更新/取消/结束均废弃旧布局身份；组合期间普通选择/编辑/导航/复制、undo/redo、保存和 PDF 返回 `busy`，错误/过期身份返回 `stale-composition`，关闭释放候选。Chromium CDP/受控更新、结束、空取消及在途宿主销毁已验证；核心候选光标定位平台输入元素，成功候选和结束必须重新取得布局，不能只按 revision 判断。组件清理需 await dispose 后再使用/关闭 client；错误恢复先取消自身候选。R0 后的定向检查再次覆盖候选提交、取消与恢复；系统输入和候选窗几何的验证边界见本节开头。

宿主接受 `compositionend` 后，只消费一次最终文字相同、类型为 `insertCompositionText` 且非 composing 的尾随 `input`，不重复提交核心事务。键盘、beforeinput、新组合、失焦、保存、取消或错误清除这一关联；错误文字、类型或重复通知仍按未支持输入处理。Chromium 受控事件回归验证提交和错误边界。该关联最多保留一份命令预算内文字，不代表堆峰值或系统输入法验收。

`inputGroup` 是可选的正 i32 组号；省略时编辑命令独立成项。组号仅用于非空、无 LF 的普通输入，首项可替换支持的段内/跨段范围；核心仅在后续折叠选区等于已确认当前光标、上一项光标连续且组号相同时归并。单命令仍逐次增加 revision，整组 undo/redo 完整回放候选后一次提交、一次增加 revision，恢复首项前/末项后选区及节点身份。显式选择/导航、删除、未分组编辑、LF 输入、undo/redo 和关闭结束旧组；失败保持已确认组，核心保存不清空组/历史。组 payload 超过 4 MiB 时开启新完整项，整个历史仍按总 payload/100 项淘汰最旧完整项，文档文字保持；`historyEntries/historyBytes` 显示新的可撤销边界。宿主另在失焦、输出屏障和恢复时换组，并在接受排队意图时固定组号。当前组保留各次局部补丁，undo/redo 逐补丁重解析 XML；尚无校准延迟或峰值内存通过。

`DocumentEditor` 已提供有限浏览器输入宿主，与只读 `DocumentPreview` 共用页面绘制、图片预算和释放。调用者独占交付已打开的 client，宿主不维护文档树。点击、拖选、基本键盘输入、选区、删除及 DOCX/PDF 输出经最多 64 项意图队列发送；只移动光标不重建文档布局。默认 UI 的标尺、目录和批注在已接受输入排空后刷新最新状态，过期请求退出，避免自动查询挤占输入队列。输出携带确切 revision，PDF 绑定已完成的 layout ID，当前 revision 与最近输出 revision 分开显示。Tab 可首次进入当前页的可编辑位置，光标滚动可见。主指针拖选通过核心命中/选区 API，两轴边缘滚动按原页序跨页；空白页保留真实端点，末次坐标先于输入与输出，取消/失焦/捕获丢失停止滚动。同段内相邻显式分页符合并为一次布局分页，跨 run 也适用，保存仍保留每个原始分页符；正文、普通换行或独立段落分隔的分页不合并。这是维护者选择的固定 LibreOffice 行为，不授予 Microsoft Word 兼容性。失败需显式恢复，销毁保留原宿主 DOM 和调用者 client；不保证取消已在途核心事务。实际支持与暂未接收的输入见[开发说明](development.md)。

节的 `w:cols` 只识别无子列、`num` 缺省/1、`equalWidth` 缺省/true 的单栏声明；`w:docGrid` 只识别无子节点、`type` 缺省/default 的未启用模式。这些声明与单栏无网格布局一致，源内容保留；未知属性/子节点、自定义列和启用网格仍诊断并保护。此改动让原始 POI 普通正文可进入输入宿主，不增加多栏或网格排版引擎，验证范围见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)。

字节在 Worker 边界使用 structured clone。字体通过内部 `foundation_add_font` 导出，以每字符一个八位值的字符串传入核心。DOCX 和图片继续使用每操作一个 JSON/Base64 批次，输出反向转换。两种输入均需临时字符串和核心字节，不是零拷贝；原预算保持。轮廓通过 ASCII path 批量发送：`shape()` 返回缓存增量，`layout()` 返回可独立绘制的页结果和当前缓存资源；Canvas 按 key 复用 Path2D。一个 `CanvasRenderer` 必须绑定同一个核心会话的完整生命周期；`dispose()` 后不得复用。宿主负责展示诊断及提供可访问的文本/状态，Canvas 探针没有完整文档无障碍导航。

## P10 当前格式编辑

`FoundationSession/Client.queryFormatting(revision, selection)` 返回字符与段落属性。每项使用 `{ kind: "value", value }`、`{ kind: "mixed" }` 或 `{ kind: "unavailable", reason }`，同时返回 revision 和限制原因。`EditState.formatting` 包含当前选区的同一查询；没有选区或组合进行中为 null。查询只读取目标段落与继承样式，不要求解析无关图片。

`setCharacterFormat(revision, selection, format)` 支持 `family`、`size`、`spacing`、`color`、`bold`、`italic`、`underline`、`strike`、`highlight` 和 `vertAlign`。字号为 0.5–1024 pt 的半点增量；颜色为六位 RGB 或 `"auto"`。`underline/strike` 为布尔值，写单下划线与单删除线；`vertAlign` 为 `"baseline" | "superscript" | "subscript"`。`highlight` 使用 OOXML 的 `none` 和十六种命名颜色，Wasm/Web 的 `HighlightColor` 与 `highlightColors` 提供类型和完整选项；`none` 关闭高亮，null 恢复继承。

`spacing` 是以 pt 表示的字符间距，范围为 −1584–1584，须能表示成整数 twip。正值扩展，负值紧缩，0 使用正常间距，null 清除直接定义并恢复继承。核心读取和写回原生 `w:rPr/w:spacing`，默认值为 0。格式查询、折叠处后续输入、格式复制、正文片段、样式修改和清除直接格式使用同一属性；默认格式和样式面板提供数值控件。每次实际修改沿现有事务提交，撤销、重做和保存重开保留原生定义。HTML 与 Markdown 的带格式片段输出 `letter-spacing`，逻辑文字保持。

共享塑形层在每个塑形簇后增加间距，簇的总前进宽度下限为 0。非零间距关闭可选 Latin 连字，保留阿拉伯文标准连字和连接塑形；簇内光标沿调整后的宽度分配。该宽度参与混合片段、换行、分页缓存、装饰与选区，Canvas 和 PDF 使用同一绘制结果。依据 [ONLYOFFICE 间距度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/TextShaper.js#L194-L247)及[阿拉伯文标准连字](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/TextShaper.js#L112-L119)。实现归 [`shape.mbt`](../../modules/layout/src/shape.mbt)和 [`format-model.mbt`](../../modules/formats/src/docx/format-model.mbt)。

`setParagraphFormat` 支持 `align: "left" | "center" | "right" | "both"`、`before/after/left/right/first`、`line`、`pageBreakBefore`、`keepLines`、`keepNext`、`widowControl` 和 `rtl`。`both` 为两端对齐，写回 OOXML `w:jc`；默认 UI 提供同名按钮。距离单位为 pt，须能表示成整数 twip；范围 0–1584 pt，`first` 可为负值以设置悬挂缩进。`line: { rule, value }` 使用 OOXML 整数单位：`auto` 为每行 240，取值 120–2400；`exact/atLeast` 为 twip，取值 1–31680。UI 显示多倍行距或 pt，确认后转换为这些单位；清除段落直接格式也清除行距。

`keepNext: true/false` 设置或关闭“与下段同页”，null 清除直接定义并恢复样式继承。格式查询与 Flow 返回有效布尔值，默认格式和样式编辑面板提供同名字段；格式复制、拆段、样式应用及清除直接格式沿现有路径处理。连续开启的正文段落与后续末段开头行一起换页；末段开启孤行控制时至少保留开头两行，三行末段若整段可放入则保留全段。末段同时启用 `keepLines` 时保留其全部行。段前/后距及行距参与所需空间，空间可容纳链时省略阻碍其放入页首的段前留白。整页放不下的链按剩余可容纳部分逐步拆分，不循环回退或创建空页；显式段前分页及段内分页符终止该链。

段落链成为分页缓存中的一个块，后段变化会使前面的保留段落重新分页。普通可拆表格行内，同一单元格的相邻段落使用相同保留规则；超长链继续拆分，精确行高保持裁剪，跨格/跨行不链接。正文链可延伸到紧随表格的首个可放片段。可拆普通行按实际最小片段保留；禁止拆行、精确行高及首个纵向合并组按完整高度计算。首行显式分页优先；不能与前段合放的超长首行沿既有拆分规则继续，不反复移动前段。首行内容、高度、列宽或边框变化也使前段重新分页。预判与实际分页共用 [`table-measure.mbt`](../../modules/layout/src/table-measure.mbt) 和首片段计算，联动归 [`table-keep-next.mbt`](../../modules/layout/src/table-keep-next.mbt)。参考 [ONLYOFFICE KeepNext 回退规则](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/DocumentContentElementBase.js#L293-L340)及[向前失效处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L3058-L3078)，复用既有度量与分页预算，未引入旧版排版模式。实现归 [`keep-next.mbt`](../../modules/layout/src/keep-next.mbt)。

`widowControl: true/false` 设置或关闭正文孤行控制，null 清除直接定义并恢复样式继承。DOCX 缺省为 true，沿 [ONLYOFFICE 段落默认值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L16577)；Flow 和格式查询返回有效布尔值。默认格式/样式面板、格式复制、样式应用、清除直接格式和拆段共用既有路径，非法/重复/嵌套标记仍保护源内容。

正文自动断页尽量在两端各保留至少两行。三行段落面临单行拆分且整页可容纳时，整体移至新页；四行及以上若只剩一行在末页，且末两行可同页放入，则向末页多移一行。按实际行高和页首行距度量，空间不足两行时保留有界拆分回退；必要时省略空页上阻碍首段放入的段前留白。显式分页符优先，含显式分页的段落沿原规则。超长“段中不分页”段落仍拆分；“与下段同页”预判包含末段的孤行要求，后段变化向前使保留链失效。当前规则应用正文，格内和页眉保留有效属性并沿原排版规则，不额外施加正文孤行约束；对应 [ONLYOFFICE 正文孤行处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js#L1849-L1887)。实现归 [`widow-control.mbt`](../../modules/layout/src/widow-control.mbt)，复用现有行/页预算与统一绘制输出，不引入回退循环。

`keepLines: true/false` 设置或关闭“段中不分页”，null 清除直接定义并恢复样式继承；查询与 Flow 返回有效布尔值。默认格式面板和样式编辑面板共用现有命令，格式复制、拆段及清除直接格式也包含该属性。正文段落不能放入当前页时先整体换页；超出一页时在新页正常拆分，不重复尝试。页首空间不足时省略使整段无法放入的段前留白；显式分页符优先，含分页符的段落沿原分页规则执行。可拆的普通表格行按单元格段落保留整组行；整页放不下的格内段落继续拆分，精确行高仍裁剪。重复表头的空间检查包含待放段落，属性变化参与分页缓存失效。规则参考 [ONLYOFFICE KeepLines 分页](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js#L2545-L2590)的现代文档路径；不新增旧 Word 分页模式。不等宽栏按下文使用各自区域宽度续排；多节继续实施。

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

`updateStyle(id, { character: {}, paragraph: {}, reset: true })` 显式重置格式，不能同时传其他修改。当前支持文档默认段落/字符样式，以及 Normal、DefaultParagraphFont、Strong、Emphasis、Heading1–Heading9，以及 NoSpacing、Quote、Caption、QuoteChar、SubtleEmphasis、IntenseEmphasis、IntenseQuoteChar、Hyperlink、FollowedHyperlink、Title、Subtitle、TitleChar 和 SubtitleChar。默认样式恢复文档默认属性；Strong/Emphasis 继承当前默认字符样式并恢复粗体/斜体。稳定 ID、名称、默认标志、next/link 和正文直接格式保留；其他内置样式的重置规则尚未实现。默认 UI 提供同一操作。重置沿上述候选校验及单项历史提交，撤销恢复完整源内容。行为参考 [ONLYOFFICE 样式重置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L8854-L8889)。样式修改与删除还会校验正文继承的编号引用、有效级别属性和标记结果，失败保留原包。

新增预设继承当前对应类型的默认样式。NoSpacing 清除字符覆盖，段后距为 0、单倍行距；Quote 设置 8 pt 段前距、居中、斜体及 text1 的 BF tint；Caption 设置 10 pt 段后距、单倍行距、9 pt 普通/复杂文字字号、斜体及 text2 颜色。QuoteChar/SubtleEmphasis 使用引用的字符属性；IntenseEmphasis/IntenseQuoteChar 使用斜体及 accent1 的 BF shade。段前后其他未声明值沿基础样式继承，正文直接覆盖保持。

Title/TitleChar 恢复四个 Arial 字体槽、28 pt 普通/复杂文字字号和 −0.5 pt 字间距。Title 段落设置 4 pt 段后距、单倍行距与 `contextualSpacing`。Subtitle/SubtitleChar 恢复 14 pt 字号、0.75 pt 字间距及 text1 的 A6 tint；无主题时使用 RGB `595959`。Subtitle 段落保留原生编号级别 1，不新增编号实例。名称、next/link、正文直接覆盖及其他部件沿上述重置合同保留。预设依据 [ONLYOFFICE 标题与副标题](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles/default-styles.js#L536-L623)。

原生 `contextualSpacing` 按文档默认值、样式继承和直接定义解析。本段开启时，与相邻段落的原生样式引用相同，便省略本段对应的段前或段后距；直接关闭只影响本段。正文、普通表格及已支持的页眉页脚在核心 Flow 中使用计算后的距离，格式查询和原始 XML 保留声明值。表格按同一行相邻单元格比较，首行首格还参考表格前的元素；不把上一行末格当作相邻格。段落样式应用清除直接标志。当前通过原生读取及预设重置使用该属性，未增加独立格式补丁或控件。规则归 [ONLYOFFICE 段距计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L10806-L10965)和[单元格相邻元素](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableCell.js#L2445-L2495)，实现归 [`contextual-spacing.mbt`](../../modules/formats/src/docx/contextual-spacing.mbt)。

按标准 ID 或对应英文内置名识别，名称不区分大小写，自定义标志及类型不符的样式不套用预设。名称、别名、link/next 和源元数据保持，不创建缺失样式。已有主题时保留颜色关联；相关主题色不可解析时保护重置。没有主题时写预设 RGB，不增加主题部件；之后添加主题可再次重置以建立关联。默认目录的 `canReset` 自动开放已有按钮，沿同一候选、预算、单项精确历史和保存重开，无变化不提交。预设参数参考 [ONLYOFFICE 默认样式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles/default-styles.js#L621-L795)与[题注](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles/default-styles.js#L913-L938)，实现归 [`style-presets.mbt`](../../modules/formats/src/docx/style-presets.mbt)。完整强引用边框及其余未支持预设继续保护，不以删去属性代替重置。

Hyperlink 和 FollowedHyperlink 继承当前默认字符样式，恢复单下划线；无主题时分别使用 RGB `0563C1` 和 `954F72`，已有可解析主题时关联 `hlink/folHlink`，写为标准 `w:themeColor="hyperlink"/"followedHyperlink"`。新建文档同时提供这两个字符样式，创建与重置共用预设；初始重置不增加历史。用户通过现有字符样式面板显式应用或重置，正文直接格式、链接目标、提示和关系保持。链接创建仍保留原格式；打开链接不写访问历史或自动切换样式。参数依据 [ONLYOFFICE 链接样式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles/default-styles.js#L1028-L1056)。

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

`replaceDocxMatches(revision, selections, text)` 一次校验全部范围后提交一项历史；空数组无变化，重叠、空范围、保护、过期 revision 和预算失败不部分提交。替换最多 1000 个范围，文本最多 65536 UTF-16 单元，允许 LF 段落分隔、U+2028 软换行、U+000B 分栏、U+000C 正文分页与 Tab，不接受 CR。插入文字沿用目标起点 run 格式。结构替换另限源 XML UTF-16 长度乘命中数不超过 67108864，避免逐项解析阻断操作。

`DocumentEditor.find(text, options?)` 在原队列中查询，并给结果增加 `documentId`。`selectMatch(result, index)` 定位可编辑命中；`replaceMatches(result, text, index?)` 替换指定项，省略 index 时替换全部结果。全部替换拒绝 `truncated` 或含受保护内容的结果。旧文档或旧 revision 的结果拒绝后仍可继续编辑。默认 UI 提供同一组操作，编辑后提示重新查找并禁用旧结果。

`DOCX_SOFT_BREAK` 为 U+2028，由 Wasm/Web foundation 导出。`replaceRange`、组合候选和批量替换用它表示段内换行，保存为 `w:br`；实际 LF 仍创建段落。`DocumentEditor.insertSoftBreak()` 与默认 UI 按钮、Shift+Enter 调用同一范围事务。`query().texts` 包含普通文字与内联控制节点；换行逻辑长度为一个 UTF-16 单元，`w:cr` 同样读取为 U+2028。Flow 用 LF 排版，`selectedText` 与剪贴板将软换行转为 LF。普通换行可删除、选中、设置格式及跨段移动；环绕清除和未知内联属性继续保护。

`DOCX_PAGE_BREAK` 为 U+000C，由同一 foundation 入口导出。正文 `replaceRange`、组合候选、查找替换及 `DocumentEditor.paste(DOCX_PAGE_BREAK)` 用它插入 `w:br w:type="page"`，不增加段落。默认 UI 的插入分页符按钮及 Ctrl/Cmd+Enter 使用相同事务，单独形成历史。已有正文分页符支持选择、格式与删除，保存及撤销保留源节点。普通表格单元格内也支持分页符的读取、插入、选择、格式、删除、查找替换和精确历史；按 [ONLYOFFICE 表格内分页符规则](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L4696-L4712)，它不触发换行或换页。核心保留源 `w:br` 和 UTF-16 位置，按零宽控制塑形，表格行继续按既有规则续页。正文与格内的段落缓存区分上下文，列宽、光标、命中、合并续排及 PDF 共用此行为；PDF 的文字映射和 ActualText 排除不显示的分页符。布局保留相邻分页符合并规则；仅供分页符光标定位的空行不占段落高度、不进入页面文字，也不改变空白页拖选端点。

`DOCX_COLUMN_BREAK` 为 U+000B，由 Wasm/Web foundation 导出。`DocumentEditor.paste(DOCX_COLUMN_BREAK)`、默认插入分栏符按钮和 Ctrl/Cmd+Shift+Enter 复用范围事务，不创建段落。正文移到下一栏，末栏及单栏进入下一张纸；连续分栏符逐个推进，不采用相邻分页符的合并规则。分栏符优先于段落保留与孤行约束，末尾保留下一栏的光标位置，不另占段落高度，并参与末页平衡。

已有和新插入的分栏符占一个 UTF-16 单元，支持选择、格式、删除、查找替换、组合候选、精确混合历史及保存重开。核心写 `w:br w:type="column"`，不把 U+000B 写进 XML 文本。普通表格单元格内按零宽控制保留位置，不强制换行或换栏；PDF 的文字映射和 ActualText 排除不可见控制，保留相邻文字连续性。页眉页脚及其他受保护区域仍拒绝插入；未知内联属性、目标注释、过期 revision 和预算失败保持原包。分栏符定义与格内行为参考 [ONLYOFFICE CRunBreak](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/RunContent/Break.js#L318-L337)和 [Run 分页/分栏处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L4690-L4724)。复用 [`inline-input.mbt`](../../modules/formats/src/docx/inline-input.mbt)、[`paragraph.mbt`](../../modules/layout/src/paragraph.mbt)及 [`pagination.mbt`](../../modules/layout/src/pagination.mbt)，未复制上游执行代码。

Tab 输入与粘贴保存为 `w:tab`，不转成空格。`FoundationSession/Client.tabDocx(revision, backward?)` 在列表正文执行下述列表规则；普通正文插入 Tab，反向时减少正的首行/左缩进；在现有表格中只移动到相邻单元格，不增加 revision 或历史。默认 UI 的插入制表符按钮与 `DocumentEditor.paste("\t")` 总是插入字符，原生 Ctrl+Tab 也在单元格中插入。Tab/Shift+Tab 只由文档原生输入处理；参数控件使用浏览器焦点切换，Escape 将焦点移出文档输入。

`Paragraph.defaultTab` 为 point，来自 `settings/defaultTabStop` 的整数 twip，默认 36 pt，范围 0–1584 pt；0 表示零宽。核心根据当前行位置与缩进计算下一默认制表位，断行、光标、预览与 PDF 消费同一宽度。末格 Tab 保持原位置，自动追加表格行归表格编辑批次。

`FoundationSession/Client.setDefaultTabStop(revision, interval)` 与 `DocumentEditor.setDefaultTabStop(interval)` 修改文档默认间隔，不要求正文选区。`interval` 为 0–1584 pt，须能表示成整数 twip；null 清除显式设置并恢复 36 pt。`EditState.defaultTabStop` 提供当前有效值，默认 UI 可修改或恢复。修改保留自定义制表位、逻辑 Tab、待输入格式与未知设置；现有相同值不产生历史。缺少设置部件时，XML、关系与内容类型一并创建。设置修改或创建合为一项有界历史，失败保留已提交包，撤销和重做恢复各部件及选择。候选先验证设置值和包预算，再提交并使相关布局失效。未知目标标记、重复设置、外部/重复设置关系，以及强制保护的文档设置拒绝修改。行为参考 [ONLYOFFICE 的文档默认制表位历史](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js)。

`setParagraphFormat({ tabs })` 使用 `TabStop[]`：每项为 `{ position, align, leader? }`，位置单位为 pt，须为 0–1584 pt 的整数 twip，按位置递增且不重复，最多 64 个有效位置。`align` 支持 `left/right/center/decimal/bar`。`leader` 省略时为 `none`，也支持 `dot/hyphen/underscore/heavy/middleDot`；`bar` 只接受无引导线。MoonBit `TabStop.leader` 与核心返回值总带明确值。字段省略保留；null 清除段落直接定义并恢复继承；空数组清除全部有效位置，核心为移除的继承位置写 `w:tab w:val="clear"`。格式查询与格式复制包含有效制表位。默认 UI 可添加、修改、移除、应用、清除全部与恢复继承，使用同一历史与保存路径。

派生 `Paragraph.tabs` 提供合并后的有效位置。核心按后续片段宽度放置右/居中制表位，小数点使用文档 `settings/decimalSymbol`（派生 `Paragraph.decimalSymbol`，默认 `.`）；越过可用边缘的自定义位置按右边缘放置，悬挂缩进保留隐式左边界位置。规则参考 [ONLYOFFICE 的制表位合并](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js)与 [Tab 后续文字定位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js)。未知标记仍保留源并保护编辑。`Paragraph.rtl` 为 true 时，制表原点移到正文右边缘，按向左的距离计算默认及自定义位置。左/右缩进分别作用于起始/末尾边缘，首行缩进和对齐沿同一方向；竖线也按右边缘定位。文字字形保留塑形后的顺序和局部坐标，小数点按后续片段的视觉位置锚定。规则参考 [ONLYOFFICE 的 RTL 制表定位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js)。标尺交互见[水平标尺](#水平标尺)。

引导线按 [ONLYOFFICE 的 Tab 字形绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/RunContent/Tab.js)使用当前字体与字号，重复字形居中放入间隔；短划线使用 1.5 倍步长，`heavy` 与 `underscore` 使用下划线字形。逻辑文字、光标与复制内容仍为一个 Tab，PDF 的 ActualText 不加入装饰字符。每个 Tab 最多 4096 个引导字形，每行 16384 个、每段 65536 个；超过预算明确拒绝布局。

`bar` 遵循 [Word 的竖线制表位语义](https://support.microsoft.com/en-us/word/using-the-ruler-in-word)，在每一行的指定位置绘制竖线，不改变文字或 Tab 定位。当前核心绘制 0.5 pt 黑线，沿行高延伸，预览与 PDF 共用图元；未宣称与 Word 的全部显示细节一致。派生 `Line.bars` 随分页定位，缓存与公开行结果各自持有数组副本。

水平标尺已接通；其他内置样式重置规则仍待实现。主题颜色与字体见下节。剩余范围归 [P10](../p10-docx-core.md)，不把本切片记作完整格式编辑。

### DOCX 符号插入

默认编辑栏提供 50 项常用 Unicode 标点、数学符号、货币、箭头、形状和圈号选择。选择后点击插入，沿 `DocumentEditor.paste(symbol)` 替换当前范围或在光标插入；对应同步/Worker 核心操作仍为既有 `replaceRange`。字符保存在普通 `w:t`，继承当前位置的字符和段落格式，保留非目标源。字体与缺字处理沿宿主提供的字体 profile 和既有回退。每次插入产生一项精确历史，并把焦点交还原生输入；后续键入保留原生编辑行为。组合输入、暂停、只读或格式保护状态沿现有控件和核心保护禁用。保存、语义文字、Canvas/PDF 和重开使用共同核心文字路径。专用符号字体、旧式 `w:sym` 编辑及 OMML 数学排版继续按 [P10](../p10-docx-core.md)和 P14 范围实施。

控件归 [`docx-symbols.tsx`](../../packages/ui/src/docx-symbols.tsx)，接入既有编辑栏和中英文文案。功能目录来自 [GenOffice 常用符号](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/components/ribbon-insert-tab.tsx#L63-L114)，Unicode 插入与字体语义参考 [ONLYOFFICE 符号插入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/apiBase.js#L3718-L3752)。当前操作复用原核心格式与输入事务，未新增符号模型、桥命令、协议或依赖。

### DOCX 行内分数

普通正文及普通单元格段落可读取直接嵌入的 `m:oMath/m:f` 横线分数。平面参数面板处理单层分数，分子和分母为普通 `m:r/m:t`；默认接受数字及简单运算标点，字母须显式声明 `m:sty m:val="p"` 正体。数学 run 可携带完整的 `w:rPr` 字体、字号和颜色；两项参数及各 run 要求同一外观。其他属性、混合数学样式和未知公式保留源并报告诊断。分数与脚标的组合读取归[嵌套行内数学](#docx-嵌套行内数学)。分子和分母均非空，合计最多 4096 个 UTF-16 单元。

宿主在现有字体 profile 中提供数学 run 显式指定的字体；没有完整的 run 外观时，使用设置部件 `m:mathFont`，默认 `Cambria Math`。核心需要实际字体的行度量及 U+2217 字形计算数学轴；缺少字体或字形明确拒绝布局。行内参数采用 0.76 字号系数，分子分母居中，横线宽度取两者较大值。公式参与逐行基线、行高和现有段落缓存预算，使用已有文字、矩形及变换图元输出 Canvas/PDF；语义文字为 `(分子)/(分母)`。

属性栏可插入、加载、修改和删除当前范围内的分数。`DocumentEditor.insertMathFraction({numerator, denominator})` 在普通文字选区插入，替换所选文字并保留两侧文字和格式。核心复用段内原生对象插入路径，写入正体 `m:oMath/m:f`。两个参数要求非空单行文字，合计最多 4096 个 UTF-16 单元；目录最多 256 项。

`mathFractions()` 返回绑定 `documentId` 和 `revision` 的目录，项含原生 XML 身份 `id`、分子、分母及保护原因。可编辑项的 `format` 返回实际字体 `family`、字号 `size` 和颜色 `color`；受保护项为 `null`。`editMathFraction(source, id, value)` 修改指定分数，`value=null` 删除。插入和修改可携带完整的 `format`，统一设置分子分母外观；省略时，插入沿当前继承，修改保留原外观。字号为 0.5–409 pt 的半点值，颜色为六位 RGB，字体须提供实际资源。属性栏加载分数后显示对应控件。过期目录、受保护容器、修订和未知公式源明确拒绝；字体及完整布局预检失败时保留源和历史。相同参数及相同直接格式不创建历史，每项实际编辑可精确撤销/重做并保存重开。

公式在正文及普通格中占一个逻辑位置。插入后光标位于公式之后，默认面板恢复原生输入焦点；可在公式两侧键入、插入制表符/软换行、Enter 换段及边界合段。Delete/Backspace 和范围替换整体删除公式；保留的公式不改内部源。组合输入沿既有候选、取消及单项提交处理。搜索将公式计为一个对象位置，避免后续文字查找/替换错位；纯文字选择查询使用 `(分子)/(分母)`。点击受支持公式可选择其整体，不停止编辑。

原生富文本剪贴板已接通分数复制、剪切、正文范围粘贴及普通矩形单元格粘贴。纯文字和 TSV 使用线性表达式；原生片段保存可编辑 OMML，并写入实际数学字体、字号和颜色，避免单独复制公式时丢失外观。接收文档须供应该字体。粘贴复用现有段落/表格事务、资源和完整布局预检；支持目标公式覆盖、表格扩张、继续原生输入、一项精确历史和重开。分子/分母修改保留显式外观。未知、错位、混合外观及不完整源拒绝，文档分数总数限 256 项。

`queryFormatting()` 分别返回输入的 `inputReason`、通用格式的 `reason`，字体/字号/RGB 文字色的独立 `fontReason`，以及段落属性的 `paragraphReason`。宿主按核心输入状态设置原生输入框只读；格式不可用不再阻止已支持的输入。正文及普通格中的公式两侧文字可使用既有字符格式、格式查询及格式复制；光标可设置待输入格式，并修改所在段落的对齐、缩进和间距。组合输入、原生源及精确历史沿原路径处理。

非折叠选区包含完整、已支持的公式时，可通过既有字体、字号和文字颜色控件一起修改公式与周围普通文字。`fontReason` 为空表示这三项可用；`character.family/size/color` 返回实际共同或混合值，通用 `reason` 保留其他操作的保护原因。核心只接受这三项的 Set/Keep，保留每个未改属性；数学字号接受 0.5–409 点的半点值，文字色为六位 RGB。含公式选区可修改既有段落对齐、缩进、间距、制表位及分页属性；`paragraphReason` 为空表示可用，查询返回实际段落值，公式内部源保持不变。Clear 字符属性、自动色、粗体等其他字符属性、列表及格式刷继续保护。

公式原结构、文字和版式参数保持，只更新数学 run 及已有控制属性中的完整统一字体属性；新增 `w:rPr` 放在已有 `m:rPr` 之后。已有相同显式值不新增历史，首次设置可固化继承值。MoonBit `apply_format/set_character_format/set_paragraph_format` 在修改公式范围或含公式段落属性时使用 probe、profile 和 images 做完整布局预检，失败保留原包、选择和历史。Wasm/Worker 的 `applyFormat/setCharacterFormat/setParagraphFormat` 在 format 后接受可选字体 profile；默认编辑宿主传入已有资源 profile，普通文字命令不新增字体上下文要求。公式范围缺少上下文或字体映射时在提交前拒绝。

实现归 [math-range-format.mbt](../../modules/formats/src/docx/math-range-format.mbt)，沿 [ONLYOFFICE 数学文字属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/base.js#L1016-L1071)的整体及控制属性语义；复用现有 OMML 属性写回。分数面板仍可显式修改平面分数的整体数学外观。未知公式、源注释/处理指令、修订、文档保护和未支持容器继续保护，失败保留源与历史。HTML/Markdown 明确拒绝公式输出，避免静默丢失。局部/混合数学格式、更多 LaTeX 语法和完整数学排版仍待实现。

片段校验归 [`math-clipboard.mbt`](../../modules/formats/src/docx/math-clipboard.mbt)，统一外观读取归 [`math-style.mbt`](../../modules/formats/src/docx/math-style.mbt)。完整公式复制参考 [ONLYOFFICE ParaMath.Copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L594-L612)；数学 run 中的 Word 属性位置按 [Open XML SDK schema](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/data/schemas/schemas_openxmlformats_org_officeDocument_2006_math.json#L45-L59)核对。

整体数学格式参考 [ONLYOFFICE ParaMath.Apply_TextPr](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L1161-L1204)，沿现有分数候选、字体预检及原生属性写回，不增加独立格式状态。

段内文字及换段复用 [`body-field-input.mbt`](../../modules/formats/src/docx/body-field-input.mbt)，源结构参照 [ONLYOFFICE Paragraph.Split](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L13838-L13881)及 [ParaMath.Split](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L3001-L3034)。当前仅开放公式两侧及整体操作，公式内部通过分数面板编辑。

编辑归 [`math-edit.mbt`](../../modules/formats/src/docx/math-edit.mbt)，接口校验归 [`docx-math.ts`](../../packages/wasm/src/docx-math.ts)，默认面板归 [`docx-math.tsx`](../../packages/ui/src/docx-math.tsx)。

读取归 [`math-read.mbt`](../../modules/formats/src/docx/math-read.mbt)及 [`math-run.mbt`](../../modules/formats/src/docx/math-run.mbt)，布局归 [`layout/math-fraction.mbt`](../../modules/layout/src/math-fraction.mbt)。数学轴参考 [ONLYOFFICE Math.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L2520-L2525)，参数缩放、间距及横线规则参考 [fraction.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/fraction.js#L352-L459)和[分子分母间距](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/fraction.js#L821-L909)。私有测试使用带完整许可的 DejaVu Math 字体，公开构建不依赖私有资源。

### DOCX 嵌套行内数学

正文和普通单元格可读取 `m:oMath` 内的横线分数、上下标及横向组合。各参数可递归包含同类结构，保留原生 OMML。所有数学 run 要求统一字体、字号和颜色，文字与正体声明沿上述合同；未知结构、混合外观、修订和扩展继续保护。

核心使用 `MathExpression` 的 `Text`、`Row`、`Fraction`、`Scripts`、`Root`、`Delimited`、`Nary`、`Matrix`，统一由 `MathFormula` 承载。`Row` 和 `Delimited` 使用不可变子项数组。解析与布局在递归及缓存序列化前检查：根深度为 0，最大深度 16，最多 256 项结构/run 节点（横向组合计一项），文字合计 4096 个 UTF-16 单元。原生数学对象目录仍最多 256 项；超限原子拒绝。Web flow 使用 `kind="math"` 和 `{expression, style}`，沿同一预算校验。

子参数递归按 0.76 缩放，横向组合按基线对齐；分数及结构化基底的单/双脚标使用实际字体度量。Canvas/PDF 继续消费核心已定位图元。线性文字用括号表达嵌套关系，供语义层、选择、纯文字和 TSV 使用。

公式占一个逻辑位置，支持两侧原生输入、整式删除/替换、富文本复制/剪切、跨文档粘贴、精确历史及重开。周边编辑保留原公式源；富文本写回实际统一外观及递归结构。已有分数/脚标参数 API 和面板只修改平面参数，遇到嵌套内容返回保护原因，避免扁平化覆盖。嵌套参数可通过下述 LaTeX 表单或 SDK 替换；单式独立段落归[独立公式合同](#docx-独立公式段落)；内部光标、逐行块数学、局部格式与更多结构/语法仍待实现。

结构及边界归 [`math-expression.mbt`](../../modules/layout/src/math-expression.mbt)，递归测量归 [`math-layout.mbt`](../../modules/layout/src/math-layout.mbt)，读取归 [`math-read.mbt`](../../modules/formats/src/docx/math-read.mbt)，写回归 [`math-markup.mbt`](../../modules/formats/src/docx/math-markup.mbt)。脚标的文字/结构化基底分支沿上述 ONLYOFFICE 定位规则。

### DOCX 独立公式段落

正文和普通单元格支持 `m:oMathPara` 包装的单个 `m:oMath`，复用上述数学结构、统一外观和预算。包装整体占一个逻辑位置，目录不会把内层表达式重复列出。独立段落按 `m:oMathParaPr/m:jc` 对齐，接受 left、center、centerGroup 和 right；缺省沿设置中的 `m:defJc`，再回退居中。centerGroup 在单式范围内按居中处理。公式旁有普通文字或段落带编号时使用段落对齐；周边原生输入保留原包装。语义依据 [ONLYOFFICE 行内模式判断及数学对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L2269-L2332)。

默认数学面板提供“插入独立公式”。`DocumentEditor.insertMath(value, true)` 和 Wasm/Worker 的 `{ action: "insert", latex, display: true, format? }` 走同一事务；MoonBit 为 `edit_math(..., display=true)`。省略或 false 保留行内插入。替换当前范围后，非空段落按插入点拆为前文、公式和后文；空段落直接承载公式。统一外观、结构修改和删除复用已有公式目录与命令，更新保留包装和对齐源，删除移除整个包装。独立插入、段落拆分和范围替换共用一项精确历史。

正文和普通格的原生富文本片段保留包装、有效对齐及统一数学外观，跨文档粘贴后可继续修改。保存重开保留原生内容；Canvas、语义与 PDF 使用同一数学基线和段落位置。未知包装/属性、多表达式、混合外观、源注释及既有未支持结构继续保护。软换行及页/栏控制符与独立包装混排仍需逐行块布局，导入给出诊断，普通输入原子拒绝；Enter 拆成相邻段落仍走既有路径。较大显示运算符和上下堆叠极限归下述[求和与积分](#docx-行内求和与积分)；局部格式继续实施。实现归 [math-display.mbt](../../modules/formats/src/docx/math-display.mbt)、[math-read.mbt](../../modules/formats/src/docx/math-read.mbt)、[math-edit.mbt](../../modules/formats/src/docx/math-edit.mbt)和[原生输入](../../modules/formats/src/docx/body-field-input.mbt)。

### DOCX LaTeX 公式编辑

默认“数学公式”面板和 `DocumentEditor.insertMath({latex, format?})` 可在正文/普通格中创建嵌套公式，替换当前文字范围并恢复原生输入焦点。支持横线 `\frac{分子}{分母}`、`_{下标}`、`^{上标}`、根式 `\sqrt{被开方项}` 与 `\sqrt[次数]{被开方项}`、花括号分组、横向组合、`\text{原文}`、[可伸展括号](#docx-可伸展括号)、[行内求和与积分](#docx-行内求和与积分)和[矩阵](#docx-行内矩阵)。单字符脚标可省略花括号，两个脚标可交换输入顺序；重复同类脚标和缺失参数拒绝。当前字母与文本均使用正体数学 run。

公式中的普通空格忽略，`\text{...}` 中的空格保留。文字内的 `{ } _ % $ # &` 使用反斜线转义；反斜线、尖号和波浪线可用 `\textbackslash{}`、`\textasciicircum{}`、`\textasciitilde{}` 表示。数学序列也接受 `\backslash` 与支持的单字符转义。宏、外部输入、注释、未映射的环境/排版命令和其他语法明确拒绝，不执行 TeX。

`mathExpressions()` 返回绑定文档身份和修订的原生目录，项含 `id`、规范化 `latex`、实际统一 `format` 和保护原因。规范化文字使用 `\text`，脚标按下标、上标顺序输出；无脚标作用的嵌套行分组展开，保留有脚标基底的结构。`editMath(source, id, value)` 替换指定公式的完整结构，`value=null` 删除。支持修改嵌套参数、切换根结构，以及统一字体/字号/颜色；省略格式沿插入继承或保留原外观。未知源、修订、源注释、受保护容器与过期目录继续拒绝。

LaTeX 源最多 131072 个 UTF-16 单元，语法嵌套最多 64 层；解析结果继续遵守上述深度 16、256 节点、4096 个文字单元和实际字体要求。源上限容纳规范化的文字转义。候选原生 OMML 在字体与完整布局预检后提交，沿已有事务保存精确历史；无操作不新增历史。非法输入保留源、选择及历史，默认面板沿既有“恢复编辑”流程继续。保存重开后可加载规范化参数和实际外观再修改。

解析和规范化归 [`math-latex.mbt`](../../modules/formats/src/docx/math-latex.mbt)，复用既有数学源编辑和排版。语法映射参考 ONLYOFFICE 的 [横线分数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/LaTeXParser.js#L286-L323)、[脚标及顺序](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/LaTeXParser.js#L1097-L1168)和[原文参数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/LaTeXParser.js#L821-L853)。输入范围比上游完整语法小，仅接受当前数学结构。

### DOCX 行内上下标

普通正文及普通单元格可读取直接嵌入的 `m:oMath/m:sSup`、`m:sSub` 和 `m:sSubSup`。平面基底和脚标为非空普通数学 run，合计最多 4096 个 UTF-16 单元。数字与简单运算符可省略正体声明；字母须声明 `m:sty m:val="p"`。各参数使用统一字体、字号和颜色，完整的 Word run 外观沿分数读取路径处理。当前接受空的结构属性；脚标对齐选项及其他扩展保留源并报告诊断。嵌套基底与参数归[嵌套行内数学](#docx-嵌套行内数学)。

核心用实际数学字体塑形基底，并按 0.76 比例塑形脚标。偏移使用 U+2B1A 的度量，下标偏移同时使用 U+2217；缺少字体或度量字形明确拒绝布局。上下标参与行基线、行高、段落缓存及资源预算，沿已有图元输出 Canvas/PDF。线性替代文字使用 `X_(下标)^(上标)`，省略不存在的一项。分数与上下标共用字体、文字边界、缓存计数和基线处理；支持的数学字号下限统一为 0.5 pt。

属性栏“上下标公式”可插入、加载、修改和删除。`DocumentEditor.insertMathScript({base, subscript, superscript, format?})` 替换普通文字选区；基底非空，下标或上标可用空字符串省略，至少保留一项。核心按参数写为 `m:sSub`、`m:sSup` 或 `m:sSubSup`，修改可在三种形式之间切换，不留下旧参数。

`mathScripts()` 返回绑定 `documentId` 和 `revision` 的目录，项含原生 `id`、三个参数、保护原因及实际 `format`。`editMathScript(source, id, value)` 修改指定公式，`value=null` 删除。分数和脚标目录各返回所属的已知结构，未知源仍报告保护原因；总目录预算沿 256 项数学对象检查。过期目录、其他结构身份、修订、源注释及不支持容器明确拒绝。

`MathFormat` 为 DOCX 与 PPTX 数学共用的完整 `family`、`size` 和 `color`。插入省略格式时沿段落与数学字体设置继承，修改省略时保留原外观；显式格式写为统一 Word run 属性。相同参数及相同已有直接格式不创建历史。候选源先完成字体与完整布局预检，再提交一项精确历史；失败保持源、选择和历史。

脚标公式在正文及普通格中占一个逻辑位置。插入后光标位于公式之后，并恢复原生输入焦点。可在两侧原生输入、插入 Tab/软换行、Enter 换段及边界合段，并进行组合输入、周边文字格式和整式删除/替换。保留的公式不改内部源。包含完整数学对象的非折叠选区可统一设置字体、字号和 RGB 文字色，其余格式继续保护；基底和脚标通过属性栏或 SDK 显式编辑。

原生富文本复制/剪切、跨文档正文和普通矩形格粘贴已接通。纯文字/TSV 使用线性表达式，片段保存可编辑 OMML 及实际字体、字号和颜色；目标须供应该字体。目标脚标覆盖、表格扩张、整格清空、继续输入、精确历史及重开沿已有事务处理。片段与目标文档沿现有 256 项数学对象预算检查，未知源和字体/布局失败保留源与历史。HTML/Markdown 明确拒绝，避免丢失结构。局部/混合数学格式、斜体数学字形及更广脚标属性继续实施。

读取归 [`docx/math-read.mbt`](../../modules/formats/src/docx/math-read.mbt)，布局归 [`layout/math-scripts.mbt`](../../modules/layout/src/math-scripts.mbt)，共用度量与边界归 [`math-common.mbt`](../../modules/layout/src/math-common.mbt)。偏移参考 [ONLYOFFICE 单脚标](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/degree.js#L182-L348)及[双脚标](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/degree.js#L817-L933)，度量字形归 [Math.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L2520-L2533)。

输入与源保护复用分数的对象路径。原生片段写回归 [`math-markup.mbt`](../../modules/formats/src/docx/math-markup.mbt)，复制仍参考 [ParaMath.Copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L594-L612)，不在宿主重建数学源。

创建和参数修改复用 [`math-edit.mbt`](../../modules/formats/src/docx/math-edit.mbt) 的候选与历史，分数和脚标共用 [`DocxMath`](../../packages/ui/src/docx-math.tsx) 表单。结构参数及先后顺序按 [Open XML SDK schema](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/data/schemas/schemas_openxmlformats_org_officeDocument_2006_math.json#L1055-L1190)核对。

### DOCX 根式

正文及普通格支持 `m:rad` 平方根和带次数根式，可与分数、上下标及根式递归组合。平方根使用 `degHide=true` 和空 `m:deg`；次数可见时，次数和被开方项均非空。次数可包含受支持的数学结构。接受基本次数显示属性，未知属性、重复/缺失参数、隐藏但非空的次数及混合外观保留源并报告保护原因。

`MathExpression.Root` 保存可空次数和被开方项；flow 使用 `{kind:"root", degree, radicand}`，次数为空时明确传 `null`。参数共用实际统一字体、字号和颜色，次数按 0.6498 比例缩小。核心按字体 `5`、`g` 的实际字形度量选择根号高度，长被开方项使用伸长分支；根号横线覆盖被开方项。根号用既有向量路径输出 Canvas/PDF，字体仍须提供实际资源。小字号的根号末端按比例收敛，保持 0.5 pt 下限；路径节点计入段落缓存预算。

已有“数学公式”面板及 `insertMath` / `editMath` 支持 `\sqrt{...}` 和 `\sqrt[次数]{...}`。读取后的平方根、带次数根式及嵌套结构可修改参数、切换结构、统一外观和删除；目录提供规范化 LaTeX 和实际外观。分数/脚标专用目录跳过根式。公式仍占一个逻辑位置，沿现有原生输入、整式删除/替换、富文本复制、精确历史和重开路径处理。线性替代文字为 `sqrt(被开方项)` 或 `root[次数](被开方项)`。其他数学结构、局部/混合格式和更广根式源变体继续实施。

结构读取归 [`math-read.mbt`](../../modules/formats/src/docx/math-read.mbt)，布局归 [`math-root.mbt`](../../modules/layout/src/math-root.mbt)。尺寸和绘图参考 ONLYOFFICE [根号路径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/radical.js#L59-L201)、[字体度量与伸展](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/radical.js#L204-L330)及[次数/基底定位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/radical.js#L564-L681)，字号系数归 [Math.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Math.js#L47-L48)。LaTeX 语法参考 [LaTeXParser.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/LaTeXParser.js#L1267-L1298)，原生参数顺序按 [Open XML SDK](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/data/schemas/schemas_openxmlformats_org_officeDocument_2006_math.json#L961-L1001)核对。

### DOCX 可伸展括号

正文及普通格支持 `m:d` 居中伸展括号，参数可嵌套分数、脚标、根式及括号。支持 `()`、`[]`、`{}`、`|`、`‖`、`⌈⌉`、`⌊⌋`、`⟨⟩`，任一侧可隐藏，左右字符可不同。每组有 1–64 个非空 `m:e` 参数，多个参数使用统一分隔符；默认是圆括号和竖线。接受省略属性、`grow=true` 与 `shp=centered`；固定大小、`match`、控制格式及其他源扩展继续保护。

核心模型为 `Delimited(open, close, separator, arguments)`，flow 使用 `{kind:"delimited", open, close, separator, arguments}`。隐藏字符为空字符串。单参数没有可见分隔符，读取时规范化为默认值，使加载后应用相同 LaTeX 保持原生源且不增加历史。公式语义、选择和纯文字按实际括号及分隔符输出，仍占一个逻辑位置。

“数学公式”面板及 `insertMath` / `editMath` 支持 `\left...\right`，用 `\middle` 分隔参数，用 `.` 隐藏一侧。字符命令包括 `\lbrace` / `\rbrace`、`\langle` / `\rangle`、`\lfloor` / `\rfloor`、`\lceil` / `\rceil`、`\vert` 和 `\Vert`；接受转义花括号及 `\|`。例如 `\left\{\frac{x_1}{2}\middle|\sqrt{q}\right.`。嵌套、统一外观、原生周边输入、整式删除、富文本复制、精确历史及重开沿既有公式路径处理。多个 `\middle` 必须使用同一字符；空参数、未配对命令与未知语法拒绝。

排版围绕数学轴确定括号高度，读取实际字体的 OpenType `MATH` 垂直变体；高度不足时按连接区拼接部件并均匀重复伸展部件。核心把实际字形轮廓转换为既有向量路径，Canvas/PDF 共用。字体须提供对应字形和足够的变体或拼接数据；缺失时原子拒绝。只读取所选字形的数据，不展开完整数学字体表。每字形最多 128 个变体、64 个部件定义，单括号最多拼接 256 个字形且轮廓少于 8192 段，单公式最多 65536 段；路径仍计入段落缓存。当前 PDF 括号以向量绘制，文字提取使用参数文字；完整线性替代文字由语义层提供。

读取与 LaTeX 分隔归 [`docx/math-delimiter.mbt`](../../modules/formats/src/docx/math-delimiter.mbt)，定位归 [`layout/math-delimiter.mbt`](../../modules/layout/src/math-delimiter.mbt)，字体读取及轮廓归 [`math-font-variants.mbt`](../../modules/layout/src/math-font-variants.mbt) 和 [`math-font-outline.mbt`](../../modules/layout/src/math-font-outline.mbt)。数学轴和参数尺寸参考 [ONLYOFFICE operators.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/operators.js#L3546-L3671)，原生结构按 [Open XML SDK](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/data/schemas/schemas_openxmlformats_org_officeDocument_2006_math.json#L551-L587)核对，字体变体及连接区按 [OpenType MATH](https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathvariants-table)处理。固定大小、其他定位方式、局部数学格式及更多运算结构继续实施。

### DOCX 行内求和与积分

正文及普通格支持 `m:nary` 的求和、乘积、余积、单/双/三重积分、三种闭合积分，以及大并集、交集、逻辑或和逻辑与。参数可递归包含已有数学结构。上下限分别可见或隐藏；隐藏参数须为空，可见参数和主体须非空。接受省略 `chr` 的默认积分、`limLoc`、`grow=false` 和基本显隐属性；增长、空白可见占位、控制格式及其他扩展继续保护。

核心模型为 `Nary(operator, limitLocation, lower, upper, body)`，flow 使用 `{kind:"nary", operator, limitLocation, lower, upper, body}`，隐藏的上下限明确传 `null`。`limitLocation` 保留原生 `subSup` / `undOvr`。省略时读取对应文档设置 `intLim` / `naryLim`；默认分别为 `subSup` 和 `undOvr`。显式属性覆盖默认设置，未使用的错误设置不会影响其他数学结构。

行内公式按 ONLYOFFICE 的行内分支使用普通字号运算符和右侧上下限，保留原生位置属性供写回。核心按实际字形的墨迹宽度、上下边界和边距定位运算符；上下限按 0.76 缩小，复用单/双脚标度量，主体按数学基线对齐。符号与主体之间的间距随字号变化。Canvas/PDF 复用已有文字图元，行内 PDF 保留运算符及参数的文字映射；线性语义为 `∑_(下限)^(上限)(主体)` 等形式。

独立公式中的运算符使用字体 MATH 表的 `displayOperatorMinHeight` 及真实变体/拼装轮廓；`undOvr` 将上下限居中堆叠，`subSup` 保留右侧位置。单个或两个可见上下限沿同一布局处理。共享 `MathFormula` 的 `display` 布尔字段由段落上下文生成；DOCX 混排或编号段落、分子/分母及缩小脚标中的运算符仍用普通字号和右侧上下限。PPTX 独立数学段落沿同一实现。较大运算符在 Canvas/PDF 中以字体轮廓绘制，PDF 参数仍可提取文字，运算符本身不提供字形文字映射；完整线性语义保留。缺少 MATH 常量、变体或字体时明确失败，编辑事务保留源和历史。字号缩放继续复用路径及图元预算。

既有“数学公式”面板及 `insertMath` / `editMath` 接受 `\sum`、`\prod`、`\coprod`、`\int`、`\iint`、`\iiint`、`\oint`、`\oiint`、`\oiiint`、`\bigcup`、`\bigcap`、`\bigvee` 和 `\bigwedge`。使用 `_` / `^` 输入上下限，主体可为一个带脚标的原子或花括号分组，例如 `\sum_{i=0}^{n}{x_i}`、`\int_0^1{\frac{x}{2}}`。`\limits` 和 `\nolimits` 保留对应原生位置属性，当前行内显示均使用右侧上下限。目录提供带显式位置修饰的规范化 LaTeX。重复脚标、缺失主体、空参数及未知语法拒绝，沿现有输入与结构预算处理。

运算符沿现有公式路径完成统一外观、周边原生输入、整式删除/替换、富文本复制、精确历史及重开。分数/脚标专用目录跳过独立的 `m:nary`。相同参数与直接外观不增加历史，字体/布局失败保持文档。增长属性及局部格式继续实施；矩阵归[行内矩阵](#docx-行内矩阵)。较大运算符沿 [OpenType MATH 常量](https://learn.microsoft.com/en-us/typography/opentype/spec/math#mathconstants-table)和字体变体，上下限间距及居中参考 [ONLYOFFICE 上下堆叠布局](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/nary.js#L1140-L1196)，未复制上游执行代码。

读取、默认设置和 LaTeX 归 [`docx/math-nary.mbt`](../../modules/formats/src/docx/math-nary.mbt)，布局归 [`layout/math-nary.mbt`](../../modules/layout/src/math-nary.mbt)。参考 ONLYOFFICE 的[行内分支](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/nary.js#L305-L356)、[行内符号与测量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/nary.js#L1220-L1262)、[墨迹宽度](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/mathText.js#L708-L829)及[默认位置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/math-settings.js#L308-L311)。原生结构按 [Open XML SDK](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/data/schemas/schemas_openxmlformats_org_officeDocument_2006_math.json#L875-L935)核对。

### DOCX 行内矩阵

正文及普通格支持 `m:m` 矩阵，可嵌套已有分数、脚标、根式、括号和行内运算符。每列可左对齐、居中或右对齐，整体基线可顶端、居中或底端对齐。读取原生列分组及重复列数；缺少的列描述按居中补足，较短行补为空单元格。空单元格保留为原生 `m:e`，按实际数学字体显示占位字形 `⬚`，不写成普通文字。

模型为 `Matrix(baseAlignment, columnAlignments, rows)`，flow 使用 `{kind:"matrix", baseAlignment, columnAlignments, rows}`。行、列均为不可变数组，单元格为数学表达式或明确的 `null`。最多 64 行、64 列且总格数不超过 256，空单元格也计入共用的 256 项结构预算，因此单独矩阵最多容纳 255 个空单元格。深度和文字仍沿整个公式检查。语义、选择和纯文字使用 `matrix(a,b;c,d)`；空单元格保留分隔位置。

核心按每行最大上升/下降距离和每列最大宽度排版。默认列距为一 em，行距按字号、相邻基线和最小间距计算。各格按所在行基线对齐，居中矩阵围绕数学轴定位；顶端和底端基线分别取首行和末行。Canvas/PDF 共用既有文字和矢量图元。完整的字体、字号和颜色可由矩阵 `ctrlPr` 的 Word run 属性承载，作用范围限于该矩阵参数；这使全空矩阵仍能保存外观、跨文档复制并重开。局部或混合控制格式继续保护。

“数学公式”面板及 `insertMath` / `editMath` 接受 `\begin{matrix}a&b\\c&d\end{matrix}`。`pmatrix`、`bmatrix`、`Bmatrix`、`vmatrix` 和 `Vmatrix` 复用已有可伸展分隔符。`array` 的列描述接受 `l` / `c` / `r`，可用 `[t]`、`[c]`、`[b]` 指定基线，例如 `\begin{array}[t]{lr}a&b\\c&d\end{array}`。矩阵环境中的 `&` 分列，`\\` 换行；空单元格和较短行的缺失项均保留为占位格，末尾换行不额外增加一行。文字中的保留字符沿 `\text{...}` 或转义规则处理。目录统一输出含显式对齐的 `array`，带括号矩阵输出 `\left...\right` 与该数组的组合。

矩阵沿统一公式路径完成结构/尺寸修改、整体外观、周边原生输入、整式删除/替换、富文本复制、精确历史和重开；分数/脚标专用目录跳过独立矩阵。字体、布局、语法、行列或结构预算失败保持文档。接受基本对齐、可见占位、默认间距及完整统一控制外观；隐藏占位、自定义间距、局部格式、未知源属性和其他环境明确保护或拒绝。

原生读取及 LaTeX 归 [`docx/math-matrix.mbt`](../../modules/formats/src/docx/math-matrix.mbt)，布局归 [`layout/math-matrix.mbt`](../../modules/layout/src/math-matrix.mbt)，控制外观和递归写回归 [`math-markup.mbt`](../../modules/formats/src/docx/math-markup.mbt)。定位参考 [ONLYOFFICE matrix.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/matrix.js#L361-L518)及[行列度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/matrix.js#L660-L715)，环境参考 [LaTeXParser.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Math/LaTeXParser.js#L1396-L1510)，原生结构按 [Open XML SDK](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/data/schemas/schemas_openxmlformats_org_officeDocument_2006_math.json#L10012-L10165)核对。

### 水平标尺

`DocumentEditor.ruler()` 返回绑定当前文档、revision、layoutId 和完整选择的 `DocumentRuler`。核心按焦点位置所在行提供页宽、物理原点、可用宽度和手柄位置；正文、普通单元格边距、实际分栏和 RTL 使用同一布局，不在 DOM 中推算文档结构。刻度以该原点为零，单位为磅，并跟随 Canvas 缩放和水平滚动。标尺值描述焦点段落，所改属性沿现有格式命令应用于选中段落。

`editRuler(source, change)` 使用既有输入队列及格式/页面源事务。每次修改合为一项历史；旧 revision、布局、选择及其他文档结果拒绝。未知源、编辑保护、格式和输出预算沿原路径校验。查询、拖动导线和取消均不修改源或历史。

| `change.kind` | 参数和结果 |
| --- | --- |
| `first` | `{ position, snap }`；只改首行相对起始缩进 |
| `hanging` | 同上；改起始缩进，并保持焦点段落首行的物理位置 |
| `left` / `right` | 同上；分别移动起始缩进（携带首行）和末尾缩进，RTL 按实际方向换算 |
| `marginLeft` / `marginRight` | 同上；修改单节左右页边距，保留尺寸、方向和其他边距；受保护节不提供手柄 |
| `tab` | `{ position, snap, index, align, remove }`；`index: -1` 新增，其余为查询中的当前索引；`align` 为 `left/right/center/decimal/bar`，`remove` 删除已有项 |

`position` 是纸张左边缘起算的物理点坐标。缩进/页边距默认按 4.5 pt 对齐，制表位按 3 pt 对齐；`snap: false` 使用 0.05 pt 精度。首行、起始缩进和制表位从实际段落原点吸附，末尾缩进从文字区域末端吸附；结果按 twip 归一化，保留小数页边距。手柄有界限制在纸张及当前文字边界内；参数还须满足现有格式上限。移动制表位保留引导线，重复位置拒绝；继承项移动/删除写入已有显式清除标记，保存重开不会复活。制表位仍最多 64 项。

默认标尺支持鼠标拖动、松开提交，Escape/指针取消保持原文档。方向键按上述步长移动，Shift 使用 36 pt，Home/End 移向纸张两端；Alt 关闭吸附。制表位可选择五类对齐后点击空白处新增，Delete/Backspace 或拖离标尺删除。制表位排序后键盘焦点跟随被移动项。UI 只保存指针导线，正文重排和源值由核心提交决定。

实现归 [`ruler.mbt`](../../modules/formats/src/docx/ruler.mbt)，入口归 [`document-page.ts`](../../packages/web/src/document-page.ts)和[默认标尺](../../packages/ui/src/docx-ruler.tsx)。参数与事务参考固定 [ONLYOFFICE Rulers.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/Rulers.js#L2245-L2310)；缩进、制表位及页边距仍使用各自已实现的 OOXML 序列化。当前为水平标尺和磅单位；多节页面设置、纵向标尺及通过标尺调整表格列边界未实现。

### 导入超链接文字

正文及普通单元格中的 `w:hyperlink` 已按源顺序读取其直接 run。链接内文字参与布局、命中、选区/复制、字面查找替换、格式查询与修改，以及原生输入/组合、Tab/软换行/分页符和段落拆分/合并。空链接 run 可继续输入。链接的 run 格式沿普通字符和段落样式计算；不强制替换源颜色、下划线或字符样式。Canvas 与静态 PDF 使用同一文字和格式。

文字编辑保留 `r:id`、anchor、docLocation、history、tgtFrame、tooltip、相邻注释和原关系。Enter 在新段落延续相同链接容器；合段保留原容器、局部命名空间和各 run 原段落继承的格式，不合并两个独立链接身份。文字、结构与格式仍沿同一有界历史精确撤销/重做。链接帧计入既有多段输入源预算，失败不提交源、关系或历史。

当前支持单层链接和直接 run；未知属性、目标缺失、非法 history、嵌套容器、字段及修订继续保留源并保护相关编辑。链接内插入图片暂时拒绝，避免创建当前图片编辑器不支持的容器。文字读取不获取或执行链接目标；目标操作见下节。实现归 [`hyperlink-read.mbt`](../../modules/formats/src/docx/hyperlink-read.mbt)，容器读取与拆分参考固定 [ONLYOFFICE 链接读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Serialize2.js#L12003-L12037)及[链接拆分](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Hyperlink.js#L188-L197)。

普通左右箭头将非空文字选区收敛到对应边界，不再向右额外走一字；继续按箭头才移动。该规则与 [ONLYOFFICE MoveCursorRight](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L6051-L6092)一致，位置和保护仍由核心布局确定。

### DOCX 外部超链接

`FoundationSession/Client.setHyperlink(revision, selection, target, text?)` 和 `DocumentEditor.setHyperlink(target, text?)` 创建、修改或移除正文/普通单元格的外链。target 为 HTTP、HTTPS 或 mailto 地址，null 移除链接但保留文字。地址最多 2048 UTF-16 单元，拒绝空目标、空白、控制字符、反斜杠及非法 XML/Unicode。`checkDocxHyperlink` 从两个 foundation 入口提供相同输入检查，核心仍独立校验。

非空选区只修改所选字符，可跨 run 和相邻段落。链接内光标修改当前完整链接容器；原生连续输入的末端按实际输入节点查询和修改。普通光标创建链接时须提供 text。text 为非空、至多 65536 UTF-16 单元的单行普通文字，提供时替换整个目标范围；链接内光标替换完整链接文字。替换可合并相邻段落，之后光标留在新链接末尾并可继续输入。空链接重复移除及相同目标不新增历史。

`DocxFormatting.hyperlink` 返回 `{ target, mixed, reason }`；非共同目标为 null，mixed 为 true 时可统一设置或移除，reason 说明目标保护原因。原字符格式保持，不自动套用 Hyperlink 字符样式；默认面板提供地址、显示文字、应用、移除和显式打开，外链使用新窗口及 `noopener noreferrer`。普通输入和临时组合状态不覆盖未提交地址草稿；非法地址在进入编辑队列前提示，原文档仍可编辑和保存。打开文件、查询、布局及应用链接都不请求外链。

复用字符边界拆分和关系事务。已选链接的提示、history、tgtFrame 与未选两端保留；移除容器时补齐 run 和书签的局部命名空间，保留文字、格式和注释。相同外部目标复用关系，不改写共用关系或清理旧关系。显示文字、链接 XML、新增/修改关系合为一项历史；过期 revision、活动候选、图片、未知源及源/输出预算失败均不提交。内部目标扩展见下节；docLocation、同时具有外链关系和 anchor 的组合目标及未知关系继续保护。链接样式管理归[当前格式合同](#p10-当前格式编辑)，输出归[PDF 文字链接](#docx-pdf-文字链接)。范围与光标语义参考 [ONLYOFFICE 链接操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L7811-L8180)，实现归 [`hyperlink-edit.mbt`](../../modules/formats/src/docx/hyperlink-edit.mbt)及 [`hyperlink-query.mbt`](../../modules/formats/src/docx/hyperlink-query.mbt)。

### 书签与内部导航

`FoundationSession/Client.overview(revision)` 的 `bookmarks` 返回 `{ name, selection, reason }[]`，最多 4096 项。支持正文、普通单元格及单层链接内的成对书签；空光标、文字范围、跨段和交叠范围均不占逻辑文字宽度。重复名称/身份、缺失或倒置标记、列书签和未知容器保留源，以 reason 说明保护原因，selection 为 null。

`editBookmark(revision, change)` 与宿主 `DocumentEditor.editBookmark(change)` 接受四种命令：`{ action: "create", name, selection }`、`{ action: "rename", name, replacement }`、`{ action: "remove", name }`、`{ action: "goTo", name }`。创建/改名使用 1–40 个 ASCII 字母、数字或下划线，首字符不能为数字。名称查找及去重忽略大小写；重复创建拒绝。goTo 将光标移到当前书签起点，不改 revision 或历史。默认概览面板提供创建、改名、删除及跳转，复用原生输入和编辑队列。

`setHyperlink` 的 target 另接受 `#书签名`，必须对应当前可用书签。内部链接写入 `w:anchor`，不新增 OPC 关系；外部与内部目标可相互修改，保留原提示和直接格式。默认面板的“打开链接”执行核心定位。改名同时更新主文档及已知页眉页脚部件的 anchor 引用，包含共享和未启用变体；删除书签同时移除这些链接容器，保留文字、格式及命名空间。主文档已知简单 `PAGEREF` 随书签改名同步目标，删除目标后显示明确的缺失引用结果，缓存由显式字段刷新更新。其他 XML 部件、未关联页眉页脚中的 anchor，以及复杂或未知引用字段继续保护改名/删除；范围归[书签页码引用](#书签页码引用)。

普通文字、组合输入、格式、查找替换和拆段/合段保留零宽标记。范围替换删除中间段落时，丢失的已知端点收缩到替换后的光标；同一位置的起点先于结束标记。删除含书签的表格行等其他结构操作若会破坏配对，则整项拒绝。未知标记源保持。每次创建、改名、删除及相关引用更改合为一次有界历史；保存重开保留范围和导航，预算失败不提交。当前 PDF 的可点击文字注释归[PDF 文字链接](#docx-pdf-文字链接)。

名称匹配及书签定位参考固定 [ONLYOFFICE Bookmarks.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Bookmarks.js#L353-L366)，配对插入及移除参考 [Document.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L24423-L24568)。未复制上游代码；实现归 [`bookmark-read.mbt`](../../modules/formats/src/docx/bookmark-read.mbt)和 [`bookmark-edit.mbt`](../../modules/formats/src/docx/bookmark-edit.mbt)。

### DOCX PDF 文字链接

既有 `FoundationSession/Client.exportPdf`、`DocumentEditor.exportPdf` 和默认导出入口自动保留正文、普通单元格、[文本框](#docx-文本框)及[页眉页脚](#页眉页脚)中的已知文字链接。外链输出原始 HTTP、HTTPS 或 mailto 地址；内部链接及带 `\h` 的 `PAGEREF` 输出当前书签起点的实际页和坐标。未设置链接开关的字段只输出文字；缺少目标的 `PAGEREF` 保留缺失引用结果，不生成悬空动作。未知关系、组合目标及非法地址拒绝导出，保留原文档。

链接矩形复用已完成布局的逐行光标边界，支持换行、混合格式及单元格裁剪，不扩大到行尾空白。文本框复用核心最终行坐标，按实际溢出设置、行内父格及纸张裁剪；浮动框沿页面位置输出。PDF 写入无边框 `Link` 注释；外链使用 `URI` 动作，内部使用 `GoTo` 和真实页对象的 `XYZ` 目标，统一转换为 PDF 左下角坐标。导出不改源、选择、历史及未保存状态，不请求链接目标。

一次导出最多 65536 个矩形，目标定位与矩形查询共用 8388608 项行/光标工作预算。收集注释时预检字节，整体仍受现有 PDF 输出上限约束。绘图对象整体链接及更广导入兼容继续实施。MoonBit 入口归 [`links-layout.mbt`](../../modules/formats/src/docx/links-layout.mbt)，几何归 [`links.mbt`](../../modules/layout/src/links.mbt)，序列化归 [`write-links.mbt`](../../modules/formats/src/pdf/write-links.mbt)。依据 [ONLYOFFICE 外链](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/PdfWriter.cpp#L1198-L1221)及[内部页目标](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/PdfWriter.cpp#L4123-L4138)，未复制上游执行代码。

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

### DOCX 修订审阅

`DocumentEditor.revisions()` 返回绑定 `documentId/revision` 的 `DocumentRevisions`。目录按正文源顺序列出 `id/sourceId/kind/element/author/date/text/paragraph/reason`；`kind` 为 `insert`、`delete`、`characterFormat`、`paragraphFormat` 或 `unsupported`。`id` 是当前 XML 节点身份，`sourceId` 保留原生修订编号，不能互换。查询不改变源、选择或历史。默认面板显示文字预览、作者和日期，提供作者与类型组合筛选及逐项接受/拒绝。

`DocumentEditor.resolveRevisions(catalog, { action: "accept" | "reject", ids })` 显式处理目录内的一项或一批修订。Wasm/Worker 使用 `docxRevisions` 和 `resolveDocxRevisions`，携带 revision；同步会话提供对应方法。旧目录或其他文档的目录被拒绝。核心预检整批后提交一次源历史：接受插入或拒绝删除保留普通 run，接受删除或拒绝插入移除包装及内容。拒绝删除把 `delText` 恢复为 `t`，保留样式、命名空间、空白、Tab 和软换行；其他源内容及部件保持。撤销/重做恢复精确源，处理后的普通段落可继续输入。

受支持的待处理文字修订参与正文和普通单元格的同一份布局。插入文字加下划线，删除文字加删除线，保留原字体、颜色及其他字符属性；属性修订显示当前格式。语义文本、Canvas、页面图片和 PDF 共用这些标记，处理修订后恢复普通输出。默认面板明确说明导出页面也会包含待处理标记。包含修订的段落继续拒绝普通光标编辑，查找与统计保留既有保护说明，不把已显示的修订文字伪装为可编辑位置。

`DocumentEditor.showRevision(catalog, id)` 定位目录中的普通文字或属性修订。它复用现有队列，请求当前布局的核心区域，显示首个区域所在页并滚动、高亮；跨页范围返回各页区域，定位时高亮首段所在页。定位不改变正文编辑选区、revision、历史、源或修改状态。高亮是临时覆盖层，其他编辑或页面操作会清除，也不进入导出。同步会话和 `FoundationClient` 提供 `revisionGeometry(revision, layoutId, id)`，返回既有 `{ layoutId, revision, rects }` 结构；底层 `docxRevisionGeometry` 命令使用 `revisionId` 字段，避免与 Worker 消息序号混用。

核心从可显示的源节点计算范围，再沿塑形后的字符边界向外对齐，处理跨页、单元格裁剪和空修订的 1.5 pt 定位线。单次最多 65536 个区域，继续受布局预算限制。旧文档目录、旧 revision/layout、未知目标、活动候选、无可见范围或不完整段落布局拒绝定位；只读定位失败保留后续编辑入口。Web 在绘制前校验布局身份和页面边界，不自行解释 OOXML 位置。

当前处理正文直属段落及普通正文表格单元格内、直接包裹普通 run 的 `w:ins/w:del`，以及普通 run 的 `rPr/rPrChange` 和段落的 `pPr/pPrChange`。属性修订必须含一份匹配的旧属性，当前与旧属性均沿已有结构属性校验；字符属性预览该 run 的文字，段落属性预览该段文字。接受移除修订记录并保留当前属性，拒绝恢复旧属性及其命名空间；拒绝段落属性保留当前段落标记的 `rPr`，不把标记格式当作旧段落属性覆盖。空旧属性恢复继承。属性和文字修订可在一个显式批次内处理，共用历史与预算。

字段、图片、嵌套修订、移动、段落结构修订、未知内容或元数据保持保护并给出条目原因。当前或旧属性中的未知项、重复属性、旧段落属性包含标记格式或节结构、属性源中的注释/处理指令，以及段落标记自身的修订继续保护。启用的文档保护由核心拒绝接受/拒绝事务，保留保护标记；只读定位不移除保护。未支持内容继续给出布局诊断，不声明完整显示。记录新修改、作者颜色、更广结构及显示模式兼容继续实施。

目录最多 4096 项，每项预览最多 32767 UTF-16 单元，总预览最多 1 Mi 单元；作者最多 255，日期及源编号最多 128。提交接受现有 XML、包输出和历史预算，空批次、重复或缺失身份、活动候选及任意受保护项使整批失败。保留选区位于未受影响段落时的原位置；受影响时移至首个可编辑的处理段落，否则清除选区。

行为依据 [ONLYOFFICE 接受修订](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L11139-L11226)及[拒绝修订](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L11232-L11340)，属性恢复依据 [Run.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L8755-L8771)及 [Paragraph.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L15855-L15865)。旧段落属性排除标记格式依据 [ParagraphProperty.cpp](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Logic/ParagraphProperty.cpp#L568-L571)。未复制上游执行代码。实现归 [`revisions.mbt`](../../modules/formats/src/docx/revisions.mbt)、[`revision-properties.mbt`](../../modules/formats/src/docx/revision-properties.mbt)、[`document-review.ts`](../../packages/web/src/document-review.ts)及 [`docx-revisions.tsx`](../../packages/ui/src/docx-revisions.tsx)。

插入下划线和删除线依据 [ONLYOFFICE line-draw-state.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/draw/line-draw-state.js#L665-L695)；范围定位参考 [Document.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L18105-L18134)。当前定位保留编辑选区，使用独立审阅高亮。实现归 [`revision-layout.mbt`](../../modules/formats/src/docx/revision-layout.mbt)、[`flow.mbt`](../../modules/formats/src/docx/flow.mbt)及 [`page-canvas.ts`](../../packages/web/src/page-canvas.ts)。

### DOCX 只读编辑保护

`FoundationSession/Client.documentProtection(revision)` 返回 `DocxProtection = { revision, protected, passwordRequired, reason }`，不返回密码、盐或摘要。`setDocumentProtection(revision, enabled, password)` 启用 `readOnly` 保护或验证密码后解除。`DocumentEditor.documentProtection()` 返回附有 `documentId` 的 `DocumentProtection`；`setDocumentProtection(source, enabled, password = "")` 核对文档和 revision 后提交。默认页面面板提供读取、密码确认、启用及解除，提交后清空密码输入。

保护写入原生 `w:documentProtection`，可不设密码。新密码使用平台生成的 16 字节随机盐、SHA-512 和 100000 轮散列；密码最多 255 个有效 UTF-16 单元。接受 `algorithmName="SHA-512"`、`hashValue`、`saltValue`、`spinCount` 的完整凭据，导入盐限 1–64 字节、轮数限 1000000；比较摘要时累计全部字节差异。文件内容仍可读取，保存、查询、选择、复制及现有输出保持可用。

核心统一提交入口拒绝受保护文档的正文、格式、表格、资源及其他部件修改；组合输入和图片缩放也在开始候选前检查。格式查询返回限制原因，默认格式控件和原生文字输入进入只读状态。缺少设置部件时，设置、关系及内容类型一并创建；解除只删除已知保护节点，保留其他设置和原部件。保护开关沿现有精确历史撤销/重做，重新打开不创建历史。错误密码、旧 revision、未知源、活动候选及预算失败保留文档和历史。

当前支持只读模式及上述完整 SHA-512 凭据。其他限制类型、格式保护、`cryptAlgorithmSid` 等旧式参数、未知/混合算法、重复节点及节点内注释继续保护，查询给出原因。细分授权和文件加密仍待实现。设置及算法依据 [ONLYOFFICE 设置序列化](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Settings/Settings.cpp#L872-L903)与[密码验证事务](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/api.js#L14372-L14483)。实现归[保护源及事务](../../modules/formats/src/docx/protection.mbt)、[共享散列](../../modules/formats/src/internal/protection/password.mbt)和[默认面板](../../packages/ui/src/docx-protection.tsx)，未复制上游执行代码。

### DOCX 主题颜色

`FoundationSession/Client.themeColors(revision)` 返回 `DocxThemeColors = { revision, colors }`，包含 `dk1/lt1/dk2/lt2`、`accent1`–`accent6`、`hlink/folHlink` 十二项。每项含 `slot/color/reason`；无法读取的色项颜色为 null，限制原因单独返回。`DocxThemeSlot` 与查询类型沿 `wasm/foundation`、`web/foundation` 导出。查询不修改源或历史；没有主题时返回新主题的默认颜色。

`setThemeColor(revision, slot, color)` 接受上述色项和六位 RGB。`DocumentEditor.themeColors()` 与 `setThemeColor(slot, color)` 沿现有意图队列获取 revision；默认属性面板先加载色表，确认后提交，原生文字输入保留颜色草稿。已有主题从主文档的内部关系定位；缺少主题时，按现有 Word 部件事务分配名称和关系身份，同时创建完整主题、关系及内容类型，不覆盖同名孤立部件。默认字体为 Times New Roman，正文直接格式保持。

文字及列表标记按 `w:themeColor` 解析主题，覆盖缓存 `w:val`；段落/字符样式和普通单元格文字共用相同解析。支持 `clrSchemeMapping` 的文字/背景、强调色和链接映射。`themeShade` 后接 `themeTint`，沿 HSL 亮度应用十六进制字节比例；直接颜色保持。显式设置字符颜色会清除该项的主题颜色及明暗属性，恢复继承则移除整个直接定义。源主题引用和缓存颜色在主题修改后保留，预览与 PDF 消费派生颜色。明暗计算参考 [ONLYOFFICE RtfColor](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/RtfFile/Format/RtfProperty.cpp#L496-L514)。

主题修改、首次创建的元数据及选择合为一次有界历史。撤销/重做重新派生颜色；相同有效颜色保留源和布局，不新增 revision。系统颜色读取 `lastClr`，仅在改变颜色时替换为 RGB。目标颜色的未知属性、子节点、注释、处理指令、重复/外部主题关系，文档保护与主题锁保持拒绝；非法参数、旧修订、活动候选及预算失败不提交。整套主题导入，以及表格底色/边框与绘图对象的主题色仍属后续范围。实现归 [`theme.mbt`](../../modules/formats/src/docx/theme.mbt)和 [`theme-edit.mbt`](../../modules/formats/src/docx/theme-edit.mbt)。

### DOCX 主题字体

`FoundationSession/Client.themeFonts(revision)` 返回 `DocxThemeFonts = { revision, fonts }`，按标题、正文的顺序各返回 Latin、EA、CS 三槽，共六项。每项包含 `kind: "major" | "minor"`、`script: "latin" | "ea" | "cs"`、原始 `font` 和限制 `reason`；无法读取时字体为 null，空串表示源定义为空。`DocxThemeFontEdit` 为 `{ kind, script, font }`。`setThemeFonts(revision, fonts, profile)` 接受 1–6 项互不重复的修改，一次提交指定槽，保留其他槽、补充脚本、扩展和已知字体元数据。Latin 必须为非空实际字体族；EA/CS 可设空串恢复现有回退。非空字体最多 200 UTF-16 单元；不接受主题占位符、字体键分隔符、非法 XML 文字和换行。

`DocumentEditor.themeFonts()` 与 `setThemeFonts(fonts)` 复用意图队列，宿主自动携带当前字体 profile。默认面板显式加载、修改和批量应用六槽；受保护槽禁用并显示原因，其余槽可继续修改。加载恢复源值，原生输入保留面板草稿。没有主题时沿已有 Word 部件事务创建主题、关系及内容类型；未使用的字体定义不要求加载对应字体。

字符样式逐层保留 ASCII、HAnsi、东亚及复杂文字的直接或主题字体绑定。相同槽内的主题引用优先于缓存字体，较高层直接定义覆盖较低层绑定；`major/minor` 的八个 Word 字体别名分别解析到 Latin/EA/CS。空的主题槽回退到正文 Latin，再回退 Arial，遵循 [ONLYOFFICE FontScheme.checkFont](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L10082-L10135)。直接字体保持；补充脚本编辑、语言匹配及整套主题导入仍待扩展。

字体槽按 [ONLYOFFICE FontClassification](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/Run/FontClassification.js#L48-L266) 的码点范围、东亚提示和中文语言提示选择。`w:cs/rtl` 强制复杂文字槽，东亚提示及私用区保留上游优先级；复杂文字使用独立 `bCs/iCs/szCs`。核心只在字素边界拆分派生 span，保留原文字节点及 UTF-16 逻辑位置；混合格式查询、光标、空段落、普通单元格和列表标记沿相同规则，保存不拆分源 run。

提交前校验修改列表、源定义、主题锁及受影响段落的实际字体键，包含粗斜体，并检查 profile 与已注册字体。预检覆盖正文、表格及所有已存页眉页脚变体，区域内段落身份分别比较。主题和新元数据合为一次有界历史，保留选择、后续输入格式、源别名和未改 XML；无变化不增加 revision 或清除布局。旧修订、活动候选、缺字体、未知目标定义及预算失败原子拒绝。主题改变后，现有排版缓存按派生字体失效，Canvas/PDF 使用重新排版的相同结果；后续绘制失败仍沿宿主已有保存和恢复路径处理。实现归 [`theme-font.mbt`](../../modules/formats/src/docx/theme-font.mbt)与 [`font-slots.mbt`](../../modules/formats/src/docx/font-slots.mbt)。

### 标题导航与正文统计

`Session.overview(revision)`、`FoundationSession/Client.overview(revision)` 和 `DocumentEditor.overview()` 查询已提交正文。标题采用样式继承和直接段落属性中的有效 `outlineLvl`；0–8 对应一级至九级，9 表示正文。新建文件提供 Heading1–Heading9。查询包含表格单元格内的标题，不按样式名称猜测层级。

段末原生 Enter 使用当前段落样式的有效 `w:next`，新建标题因此切回 Normal。中间拆段和粘贴换行保持原样式；缺失、同名或非段落目标也继续当前样式。新段落沿既有样式应用规则清除段落直接属性，并保留直接段落方向。选择删除、换段和样式切换合为一次历史；目标样式或预算失败保持原包。规则依据 [ONLYOFFICE 的段末新段落处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L19490)。

`DocumentEditor.selectHeading(result, index)` 定位到标题段落起点。结果绑定文档和修订；过期结果报 `stale-overview`，受保护标题带原因并禁止导航。默认属性面板展示标题和统计。

统计只计算支持的正文逻辑文字。字符按 Unicode 标量计数；空白分隔单词，文字区段相连，段落分别计词。制表符计为空白；显式换行和分页符不计字符。图片、自动编号标记及页眉页脚等其他区域不计入；受保护或排除的正文结构提供原因，不能据此声称全文统计完整。

查询最多扫描 1,048,576 个 UTF-16 单元，返回最多 4,096 个标题，每个标题显示最多 256 个 UTF-16 单元，截断会显式标记。17 个核心用例（含后续样式及列表回归）、一条 Chromium 导航/原生输入/组合取消/历史/重开/PDF 流程及 767 项安装包断言通过；严格宿主编译包含标题查询与导航调用。P10 仍为部分交付。

### DOCX 绘图框与基础图形

正文 DrawingML 矩形、椭圆和线已接通读取与矢量 Canvas/PDF。支持无文字的 `wps:wsp`，普通文本内容见下方[文本框](#docx-文本框)。画笔支持显式 RGB/无填充、实线及匹配框尺寸的未旋转几何。行内框参与行宽和行高；正文浮动框复用既有定位、图层、上下型/方形环绕及缓存。线可有一个零尺寸轴。图形不生成位图资源。

Flow 使用 `spans[].drawing: DrawingFrame | null`。框为 `{ width, height, anchor, content }`；图片内容为 `{ kind: "picture", key, crop }`，基础图形内容为 `{ kind: "shape", preset, fill, stroke, lineWidth }`。`preset` 为 `rect/ellipse/line`，颜色为六位 RGB 或空字符串，尺寸和线宽使用 point。空颜色表示不绘制该项。共享锚点类型为 `DrawingAnchor/DrawingAxis`；原生定位结果为 `Line.drawings: PlacedDrawingFrame[]`，命中使用 `Hit.drawingStart`。图片源编辑命令、裁剪值和资源键继续表达图片本身。正文可访问文字把对象单元标为 `[drawing]`。

`DocumentEditor.shapes()` 返回 `{ revision, items }`，每项包含 `{ id, name, selected, preset, width, height, fill, stroke, lineWidth, anchor, reason, sizeReason, deleteReason, positionReason, textBox, textReason }`。文本框的 `textBox` 返回下述文字区域属性，普通无文字图形返回 `null`；`textReason` 说明文字区域编辑的保护原因。同步 `FoundationSession` 与 Worker `FoundationClient` 使用 `shapes(revision)`。目录最多 256 项，节点身份仅在当前会话有效；重开后重新查询。

`editShape(revision, { action: "properties", id, width, height, fill, stroke, lineWidth })` 修改完整尺寸和画笔；`{ action: "delete", id }` 显式删除。尺寸范围为 0–14400 pt，矩形/椭圆的两轴必须正值，线允许一轴为零；线宽为 0–1584 pt，有线条颜色时必须正值。核心舍入到整数 EMU，颜色使用六位 RGB 或空字符串。同步和 Worker 客户端可传字体 profile，默认宿主沿原输入屏障与队列提交。默认图形面板提供目录选择、尺寸、填充/线条、线宽及删除；旧修订的控件需要重新读取目录。

`editShape(revision, { action: "insert", preset, width, height, fill, stroke, lineWidth })` 在当前文字选择处创建行内图形。`preset` 使用 `DocxShapePreset` 的 `rect/ellipse/line`。正文、空段和普通单元格复用图片插入的源事务；受支持的跨段范围先删除并合段，再插入图形。一次实际创建只记一项历史，光标落在图形之后，继承原运行格式。图形与图片共用主文档、页眉和页脚中的未用身份，不新增媒体或关系。失败保留源、选择和历史。默认面板提供类型和尺寸，创建后选中新图形属性；初始填充为 `4472C4`，线条为黑色、1 pt，可在属性面板修改。

属性事务保留对象身份、锚点、环绕、周围运行格式和非目标部件；删除只移除目标 `w:drawing`，保留共享资源和关系。每次实际修改记一项精确历史，无变化保持修订。`noResize` 只阻止尺寸变化，`noChangeAspect` 要求保持原比例，`noDelete` 和外部对象引用阻止删除；移动锁不阻止画笔修改。文档保护、修订容器、未知锁及将被覆盖的注释/处理指令保持保护。环绕重排沿原布局预检，失败保留源、选择和历史。

普通无文字图形已随正文富文本片段复制、剪切及跨文档粘贴，支持行内与已支持的浮动锚点。行内图形还可随完整普通/合并单元格转移。默认按钮和原生快捷键沿既有片段协议执行。复制保留原生几何、画笔、名称、描述、标题及图形内的源间隙；粘贴为 `wp:docPr` 和可选 `wps:cNvPr` 分配目标中的未用身份。重复粘贴生成独立对象，源图形和目标已有身份保持。`bodyFragmentImages`、`tableFragmentImages` 的纯图形预检返回空 `images`；混合片段只解码图片，图形不创建媒体或关系。一次实际粘贴或剪切合为一项精确历史。

`noCopy` 阻止图形富文本复制和剪切，`noDelete` 只阻止剪切及删除。未知绘图元数据、引用属性及外部关系继续保护复制；图形只携带已支持的独立属性。正文及整格粘贴在最终候选上检查图片与图形合计不超过 256 项，先扣除被替换对象，满额时仍可等量替换。格式、布局、输出或数量预算失败保留原包、选择和历史。片段校验、身份重映射及源保留归 [fragment-drawings.mbt](../../modules/formats/src/docx/fragment-drawings.mbt)，复制依据 [ONLYOFFICE Shape.copy/fillObject](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2772-L2833)。

受支持图形段落已接通前后原生/组合输入、字符格式、查找、拆段合段和范围删除。图形占一个逻辑 `U+FFFC`，输入同名字符仍是文字。保留图形源、资源和精确混合历史，删除继续检查独立锁与外部引用。普通文字光标可命中图形边界；绘图命中和句柄同时支持图片与基础图形。图片目录只返回图片。框内文字编辑见下方文本框，纯色艺术字见 [DOCX 基础艺术字](#docx-基础艺术字)；文字描边、主题画笔、渐变、旋转/翻转、箭头、复杂图形和未知扩展继续拒绝输出，保留原始源与历史。HTML/Markdown 的图形转换尚未接通。

实现归 [drawing-frame.mbt](../../modules/layout/src/drawing-frame.mbt)、[drawing.mbt](../../modules/formats/src/docx/drawing.mbt)、[shape-read.mbt](../../modules/formats/src/docx/shape-read.mbt)、[shape-editing.mbt](../../modules/formats/src/docx/shape-editing.mbt)、[shape-insert.mbt](../../modules/formats/src/docx/shape-insert.mbt)、[共享插入事务](../../modules/formats/src/docx/drawing-insert.mbt)、[文字事务](../../modules/formats/src/docx/drawing-text.mbt)及[默认面板](../../packages/ui/src/docx-shapes.tsx)。轮廓复用 [basic-shape.mbt](../../modules/layout/src/basic-shape.mbt)。源结构参考 [ONLYOFFICE Shape 读取](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Shape.cpp#L89-L168)与 [DOCX 写出](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Shape.cpp#L238-L332)，独立锁参考 [CNvSpPr](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/CNvSpPr.cpp#L87-L122)。当前范围归 [P10](../p10-docx-core.md)。

`editShape(revision, { action: "position", id, anchor, target? })` 修改图形定位。图形与图片共用 `DocxDrawingPositionEdit`、核心 `set_drawing_anchor` 和默认定位面板。`anchor` 为 `null` 时恢复行内；浮动框支持前置/后置、两轴基准与偏移/对齐、层次、方形/上下型环绕和四边间距，参数归[图片定位](#图片定位)。图形目录返回当前 `anchor` 及 `positionReason`。

`target` 显式把浮动图形重锚到正文段落，可跨页；偏移按移除前文档计算。事务保留原运行格式、命名空间、身份、矢量源和非目标部件，选择新逻辑范围，修改合为一项精确历史。`noMove`、`noChangeWrap` 阻止定位，`noResize`、`noCopy`、`noDelete` 不阻止定位。跨段迁移遵循 `wp:anchor locked`。浮动图形要求正文容器；源不明、位置无效、布局或预算失败保持原文档与历史。默认宿主已接通指针选择、四角及键盘缩放、浮动拖动、跨段/跨页重锚和边缘翻页。图形目录的 `selected` 标记当前单对象范围，默认面板自动跟随；`noSelect` 阻止图形手势。图形允许独立调整宽高，`noChangeAspect` 存在时保持比例，`noResize` 保护缩放；图片继续保持原比例与裁剪。矩形/椭圆的最小尺寸为一个 EMU；线允许零轴，交互命中与选择框将零轴扩展为 6 pt，源尺寸和绘制不变。候选、取消、最终坐标、原生删除、历史与持久化屏障复用[绘图对象手势](#绘图对象移动与缩放手势)。

### DOCX 普通图表

正文和普通单元格支持原生行内图表的读取、插入、类型/标题/TSV 数据/尺寸/图例修改与整图删除。类型、固定外观和五种图例位置复用 [PPTX 基础图表](#pptx-基础图表)。MoonBit 共用图表模型、排版和原生 XML；XLSX 模块读取矩形数据，生成实际嵌入工作簿。Canvas、PNG 和 PDF 重放同一组图元，语义文字包含标题与数据。

同步 `FoundationSession` 与 Worker `FoundationClient` 提供 `charts(revision)` 和 `editChart(revision, chart, profile)`。查询返回 `{ revision, items: [{ id, width, height, settings, anchor, selected, reason, deleteReason, sizeReason, positionReason }] }`；`settings` 是共用 `ChartSettings`，原生配置不受支持时为 `null`。已知图表即使内容锁定，仍返回数据与几何。`id` 是当前原生绘图节点身份。编辑使用 `{ action: "insert", ...settings, width, height }`、`{ action: "update", id, ...settings, width, height }`、`{ action: "resize", id, width, height }`、`{ action: "position", id, anchor, target? }` 或 `{ action: "delete", id }`。内容、删除、尺寸和位置分别检查对应的原因字段。

Web `DocumentEditor.charts()` 增加 `documentId`，`insertChart(value)` 消费当前选择，`editChart(catalog, id, value | null)` 验证文档、修订与目录身份。默认图表面板调用相同接口，提供读取/选择、类型、标题、TSV、宽高、图例、圆环空心比例及创建/修改/删除。默认框为 360×240 pt。输入和持久化沿既有队列，图表占一个逻辑位置；相邻文字输入与整图范围删除保留原生源。

宽高分别为 180–14400 pt 与 150–14400 pt，插入前必须能完整排版。单次目录最多 256 项，输入及规范化 TSV 均最多 65536 个 UTF-16 单元；类别、系列与标签上限沿共用图表合同。插入、图表部件、XLSX、关系和内容类型合为一项历史；字体、布局、缓存、权限及预算失败保持源和历史。标题、类型、图例或尺寸变化保留未改数据的工作簿路径和字节；数据变化创建独立工作簿。删除保留未引用资源，沿现有包资源策略恢复精确历史。

当前编辑要求单独拥有图表部件、已支持的原生配置，以及一致的系列缓存和嵌入数据。未知配置、不透明图表源、共享图表和未支持的文档区域保持保护。`noTextEdit` 与 `noDelete` 分别限制内容修改和删除，缩放服从 `noResize/noChangeAspect`；定位服从 `noMove/noChangeWrap`，指针选择服从 `noSelect`。数据范围绑定及复杂样式继续实施。

正文图表复用 [绘图定位](#图片定位) 和既有几何手势，支持行内、前方、后方、四周与上下环绕，保留引用轴、偏移、距离及层序。`target` 可移到另一正文段落。默认面板提供独立尺寸与位置操作；Canvas 提供四角缩放、浮动移动、键盘方向键与 Escape 取消。候选不写历史，最终操作只记一项；尺寸和位置保持原图表 XML 与工作簿字节。环绕后的可访问文字保留图表标题和数据。单元格、页眉及页脚中的浮动图表仍受保护。

正文和普通格的范围复制/剪切、跨文档粘贴及完整单元格片段已支持行内图表，复用现有剪贴板 API、MIME 与默认按钮。副本保留原生图表 XML、嵌入 XLSX 字节、名称/描述和尺寸，分配独立绘图身份、部件、工作簿及关系；只更新复制后关系的目标，后续改数据互不影响。纯文本使用图表标题和数据。图表不会进入位图解码，资源预检仍只向平台返回实际图片。

复制检查 `noCopy`，剪切另检查 `noDelete`；`noTextEdit` 保留复制、粘贴和相邻文字输入，仍保护图表内容修改。片段最多 2097152 个 UTF-16 单元，图片与图表合计最多 2 MiB 解码资源。未知命名空间/元数据、不透明源、外部图表关系、缓存不一致、字体及预算失败保持文档和历史。资源与片段合为一项事务，源和副本支持精确混合历史与重开。正文浮动图表传递保留已支持的锚点和环绕；浮动图表粘贴到单元格及未知源继续保护。实现归 [图表片段](../../modules/formats/src/docx/chart-fragment.mbt)，独立数据参考 [ONLYOFFICE 图表复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L4959-L4983)。

实现归 [DOCX 图表事务](../../modules/formats/src/docx/chart-edit.mbt)、[共享原生图表](../../modules/formats/src/internal/chart/read.mbt)、[图表排版](../../modules/layout/src/chart-legend.mbt)、[XLSX 数据读取](../../modules/formats/src/xlsx/chart-data.mbt)及[默认面板](../../packages/ui/src/docx-charts.tsx)。源关系和工作簿编辑参考 [ONLYOFFICE Word 图表编辑](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/GraphicObjects/GraphicObjects.js#L1346-L1375)。阶段范围归 [P10](../p10-docx-core.md)。

### DOCX 基础艺术字

`editShape(revision, { action: "insertWordArt", preset, text })` 在当前正文文字选择处创建原生艺术字文本框。五种纯色预设为 `blue/gold/red/purple/green-italic`，RGB 分别为 `4472C4/FFC000/C00000/7030A0/70AD47`。文字沿文档默认字体，使用 36 pt、粗体，绿色另带斜体；段落居中、单倍行距且段前后距为零。字符属性同时写入运行和段末属性，后续原生输入保留格式。

初始框为 2700000 × 720000 EMU（约 212.6 × 56.7 pt），透明、无边框。默认浮于正文前方，两轴分别以分栏和锚点段落为基准，偏移为零，不排斥周围文字。框内垂直居中，不自动换行，使用原生 `noAutofit`；长文字可溢出，用户通过现有尺寸、文字区域及字符控件继续调整。这里提供固定初始框，内容驱动的自动尺寸仍待实现。

创建复用图形范围替换、身份分配和浮动定位候选，全部源修改合为一项精确历史，失败保留原包、选择和历史。创建后全选框内文字，默认表单聚焦既有输入控件，用户可直接替换。文字排版、查找、剪贴板、手势、删除、Canvas/PDF 和重开输入沿普通文本框路径；不新增媒体、关系或私有艺术字状态。默认 DOCX 与 PPTX 表单共用 [word-art.tsx](../../packages/ui/src/word-art.tsx)。

`text` 必须含非空白内容，沿文本框的 XML 字符、LF 段落、Tab、软换行及 32767/256/4096 上限。默认浮动创建要求普通正文位置；单元格、嵌套文本框及其他保护容器明确拒绝。字体 probe 可用时预检普通及粗体/粗斜体字体；缺字体、过期修订、活动候选、源或历史预算失败不提交。文字描边、渐变、阴影、变形和三维效果继续实施。

实现归 [word-art.mbt](../../modules/formats/src/docx/word-art.mbt)。36 pt、透明无边框、居中和原生 Word 段落沿 [ONLYOFFICE createTextArt](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L8794-L8912)；字体大小的格式区分另见 [private_createWordArt](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/apiBuilder.js#L33296-L33365)。五种纯色配方与固定初始框取自 GenOffice 功能目标；未复制上游执行代码。

### DOCX 文本框

普通 `wps:txbx/w:txbxContent` 已接通核心读取、富文本排版与 Canvas/PDF。内容使用原生 Word 段落、样式和字体整形，保留字符装饰、对齐、缩进、段距及行距。矩形与椭圆复用绘图框；椭圆先取内接文字区域，再应用四边边距。文字不转成图片。可访问页面文字包含框内各行。正文逻辑位置仍只计一个对象，框内文字使用自身的段落身份和偏移。

Flow 的文本框内容为 `{ kind: "textBox", shape, text }`。`shape` 包含原图形的 `preset/fill/stroke/lineWidth`，`text` 为 `{ paragraphs, insets, anchor, wrap, clip }`。`paragraphs` 使用原段落结构；`insets` 按上、右、下、左排列，单位为 pt，默认分别为 3.6、7.2、3.6、7.2。`anchor` 支持 `t/ctr/b`，`wrap` 对应 `square/none`。默认文字可溢出；两轴都声明 `clip` 时裁剪到框边界。核心缓存包含文字、样式和框尺寸，缩放后重新断行。

`editShape(revision, { action: "insert", preset, text, width, height, fill, stroke, lineWidth })` 创建原生文本框。提供 `text`（包括空字符串）时，`preset` 支持 `rect/ellipse`；省略 `text` 时仍创建上述无文字图形。初始文字以 LF 分段，支持 Tab 和 `U+2028` 软换行，拒绝 CR、无效 XML 字符及分页/分栏控制。正文、空段、普通单元格和受支持范围替换复用同一插入事务，不新增媒体或关系。创建只记一项历史，光标进入末段文字末尾；保存重开后仍可继续输入。

默认图形面板提供文本框类型与初始文字，创建矩形框后聚焦原输入控件。初始填充为白色，线条为黑色、1 pt；SDK 也可创建椭圆文本框。空框保留一个原生空段落。

普通文本框已随正文富文本片段复制、剪切及跨文档粘贴；行内文本框还可随完整普通/合并单元格转移。复制保留原生框、画笔、边距、垂直对齐、换行、溢出和锚点。框内段落复用原片段序列化，把源样式和主题转成明确格式；粘贴不依赖源文档的样式身份。文字、空段、Tab 和软换行保留，文字不转成图片。`docPr`、`cNvPr` 及可选 `txbx` 身份使用目标中的未用值，重复粘贴后可独立编辑。纯文本框预检不返回图片，也不创建媒体。框内外链通过既有片段协议携带目标并在接收文档重建关系；内部链接要求接收文档已有可用书签。

选择边框后，默认复制按钮和原生剪切/粘贴快捷键沿既有协议执行。框内文字范围也可复制为普通富文本片段，再粘贴到已有文字区域。一次剪切或粘贴只记一项精确历史，保存重开后仍可编辑。`noCopy` 阻止复制和剪切，`noDelete` 只阻止剪切；`noTextEdit` 保留在对象上，继续保护框内输入。未知文字元数据、未解析的样式/主题引用、嵌套绘图和不支持的内容继续保护。浮动文本框要求正文目标；最终布局、数量或历史预算失败保留源、选择及历史。行为参考 [ONLYOFFICE 文本框内容与 bodyPr 复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2772-L2833)，实现归 [fragment-drawings.mbt](../../modules/formats/src/docx/fragment-drawings.mbt)。

已有文本框可通过 `shapes()`、`editShape` 和默认图形面板修改尺寸、画笔及定位，也可使用原绘图手势。事务保留 `txbxContent` 原文、样式与非目标部件，复用独立锁、单项历史和保存重开。创建与读取共用预设文字区域及边距校验，无可用区域时直接拒绝。提供字体 probe 时，框创建或修改同时预检内部文字排版；字体、尺寸或布局失败保留源与历史。

`editShape(revision, { action: "textBox", id, properties: { insets, anchor, wrap, clip } })` 修改已有文本框的文字区域。`DocxTextBoxProperties.insets` 为上、右、下、左四边距，单位为 pt，各值范围 0–14400，核心舍入到整数 EMU；预设文字区域扣除边距后必须仍有可用宽高。`anchor` 支持 `t/ctr/b`，`wrap` 控制框内换行，`clip` 同时控制两轴是否裁剪到框边界。默认面板提供对应控件与“应用文本框排版”。

命令只更新原生 `bodyPr` 对应属性，保留其他声明、子节点、注释、框内文字、绘图身份、框尺寸、锚点和选择。缺失 `bodyPr` 时创建普通无自动适配的声明；有效属性相同时不写源、不增加修订或历史。一次实际修改只记一项精确历史，保存重开后保留属性和框内输入能力。`noTextEdit`、`noSelect` 及文档保护阻止该命令；尺寸、移动和删除锁继续各自作用于框操作。提供字体 probe 时沿原布局预检；无效属性、无可用文字区域、缺字体或布局预算失败保留源、选择与历史。实现归 [text-box-properties.mbt](../../modules/formats/src/docx/text-box-properties.mbt)及[默认控件](../../packages/ui/src/docx-text-box-properties.tsx)，语义参考 [ONLYOFFICE 垂直对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L1942-L1968)与[边距修改](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2037-L2083)。自动适配、多栏、竖排及独立两轴溢出继续实施。

单击文本框内侧进入文字选择，边框仍用于选择整个对象。框内命中、光标、扩选、方向键与 Home/End 使用最终行几何；标尺使用框内可用文字区域。现有原生输入、组合候选/取消/最终提交、字符/段落格式及拆段合段复用同一源事务和精确历史。保存重开后仍可继续输入。查询中的文本节点带独立段落身份；正文与文本框、不同文本框之间的文字范围保持保护，不能把框内偏移当成正文偏移。查找按内容区域分组，框内段落不打断相邻正文段落。

框内普通文字超链接复用[已有文字链接](#docx-外部超链接)的读取、设置、移除、混合查询及显式打开。支持 HTTP、HTTPS、mailto 和指向可用正文/单元格书签的内部目标。原生输入、拆合段、格式和精确历史保留链接；整框及框内范围的富文本复制使用同一目标转移协议，避免携带失效关系身份。PDF 复用[文字链接输出](#docx-pdf-文字链接)，保留实际文字边界和源文件。行为参考 [ONLYOFFICE 文字链接与父框坐标](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L2886-L3000)。

当前每框限 256 段、32767 个 UTF-16 单元，单段沿既有 4096 单元上限。普通运行文字、Tab 和软换行可编辑。`noTextEdit` 和 `noSelect` 阻止框内文字编辑，沿既有文档保护检查；帧属性仍遵循各自的锁。候选和提交前校验段落结构及内容上限，失败保留最后有效候选或原文档。表格、列表、字段、嵌套绘图、链接文本框、多栏、竖排、旋转、自动适配及独立两轴溢出设置继续拒绝输出，保留源与历史。更多兼容继续实施；不支持的剪切仍受保护，避免把对象降成占位字符后删除原内容。

实现归 [shape-text.mbt](../../modules/formats/src/docx/shape-text.mbt)、[drawing-text-box.mbt](../../modules/layout/src/drawing-text-box.mbt)、[文字区域交互](../../modules/layout/src/text-box-interaction.mbt)及[框内编辑保护](../../modules/formats/src/docx/text-box-editing.mbt)。原生内容与 `bodyPr` 参考 [ONLYOFFICE Shape 读取](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Shape.cpp#L111-L168)，默认边距与文字区域参考 [Shape.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L1571-L1625)，默认 bodyPr 参考 [Format.js](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L11945-L11964)，文字命中与选区坐标转换参考 [selectionSetStart/End](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L5372-L5415)。当前范围归 [P10](../p10-docx-core.md)。

### 行内图片尺寸与裁剪

`editPicture(revision, { action: "insert", width, height, bytes })` 在核心当前文字选区插入正文行内 PNG/JPEG 图片；跨段范围复用既有删除与合段规则，单个普通表格单元格也可作为容器。`width/height` 为 0.1–14400 pt，舍入到整数 EMU；字节与像素预算同下方替换操作。空段、空 run 或段内位置都生成真正的绘图元素，保留周围文字、run 格式和范围外源。核心为新图片分配未用身份，避开主文档及页眉/页脚中的已有绘图；同时创建图片、关系和内容类型，合为一项有界历史。默认面板提供尺寸和文件选择，并读取新图片属性。选区替换与插入行为参考 [ONLYOFFICE controller_AddInlineImage](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Editor/Document.js#L19412-L19451)。

插入后把文字光标放到新图片之后，默认面板仍读取新图片属性，可以立即继续输入。受支持的正文及普通单元格段落中，图片与布局一致占一个 `U+FFFC`、一个 UTF-16 单元；`query().texts` 也包含该绘图片段。文字位置、范围、查找、格式与组合输入共用这个计数。纯文字中的 `U+FFFC` 仍是文字；核心用独立的保留位置区分原图片与输入字符，不把字符自动变成图片。图片两侧可输入、回车拆段及退格合段，保留图片原 XML、尺寸、裁剪及资源。范围替换和 Backspace/Delete 可以删除图片，并复用 `noDelete`、引用与修订保护；删除保留包内共享资源。行内绘图作为内容位置参考 [ONLYOFFICE Run 的绘图边界](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Editor/Run.js#L1448-L1467)。

纯文字复制只携带占位字符，不携带图片资源。`selectedText(revision, selection, cut = false)` 可用 `cut: true` 预检查剪切；核心对含实际图片的范围返回 `protected-content`，宿主在写剪贴板之前执行该检查。普通文字及字面 `U+FFFC` 仍可剪切。默认富文本复制、剪切与粘贴已携带行内/浮动图片及资源，按[正文富文本片段](#正文富文本片段)校验和重分配身份。

撤销/重做精确恢复文字、图片、选区与资源。节点 ID 仅在当前会话有效，保存重开后须重新查询。未知图片源、扩展、效果或不支持的布局仍保护相应段落。含图片单元格的表格结构命令继续保护，避免绕过对象锁；浮动环绕继续归 [P10](../p10-docx-core.md)。

同步 Wasm 和 Worker 的 `pictures(revision)` 返回 `{ revision, images }`。每项包含会话内绘图节点 `id`、`name`、是否被当前单图片范围选中的 `selected`、point 单位的 `width/height`、四项 `crop`、尺寸/裁剪保护原因 `reason`、删除保护原因 `deleteReason`、替换保护原因 `replaceReason`，以及下方定位使用的 `anchor` 和 `positionReason`。`crop` 依次为源图左、上、右、下移除的比例。受尺寸/裁剪保护的项使用零尺寸及零裁剪，原因供 UI 显示；列表最多 256 项。宿主 `DocumentEditor.pictures()` 复用现有队列，默认图片面板从列表选择目标。

点击受支持的行内图片会选择其一个逻辑单元，复用现有文字选择、历史与输入路径，不增加 revision 或历史。相同图片资源仍按各绘图的段内 offset 区分。布局 `PlacedDrawingFrame.start/level` 保留逻辑起点和双向级别，`Hit.drawingStart` 标记图片命中；左右半部返回相应文字边缘，RTL 调换逻辑方向。选择框按图片本身的框计算，并裁剪到行/单元格的可见区域，不按展开后的源裁剪尺寸命中。

`hitTest(layoutId, page, x, y)` 的 `DocxHit.drawing` 为图片或基础图形的 `DocxSelection` 或 null；`position` 仍是最近文字边缘。核心检查图片两端的逻辑位置和原有保护。默认宿主普通点击使用 drawing 范围，拖选和 Shift 点击沿 position 扩展文字范围。命中只查询当前布局，旧布局及无效坐标仍拒绝。默认面板在手势结束后读取 selected 项，自动切换尺寸/裁剪/删除目标；过期、组合、暂停和替换沿现有屏障，晚到的面板读取不覆盖新文档。

原生 Backspace/Delete 和输入可删除或替换被选图片，撤销恢复原图片及选区；列表和命中不改变源包。屏幕阅读文本将占位字符描述为 [image]。普通单元格复用同一位置与裁剪，结构操作和图片剪切仍保留前述保护。行为参考 [ONLYOFFICE ParaDrawing.select](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Editor/Paragraph/ParaDrawing.js#L2784-L2795) 与 [GraphicObjects.OnMouseDown](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/word/Editor/GraphicObjects/GraphicObjects.js#L1594-L1606) 的图片选择与文字输入分工。本项目通过已有逻辑范围连接两者；实现归 [drawing-selection.mbt](../../modules/formats/src/docx/drawing-selection.mbt) 和 [docx-hit.mbt](../../modules/bridge/src/docx-hit.mbt)。

`editPicture(revision, { action: "resize", id, width, height, crop })` 修改已有受支持的正文图片。宿主也显式传入图片列表的 revision，防止读取后改动文档而误用节点身份；默认面板过期后须重新读取。尺寸为 0.1–14400 pt，舍入到整数 EMU；裁剪输入为 0–1 的四个比例，按 1/100000 舍入，两侧之和须小于 1。保持目标框，只裁源图再拉伸至框；重置写四边零值。源图原字节、关系、替代文字、身份和范围外 XML 保持；同时更新行内框及图片变换尺寸。一次命令一项精确历史，保持原文字选择，重复有效值不新增 revision 或废弃布局。

`editPicture(revision, { action: "delete", id })` 只删除目标绘图元素，保留 run、段落和周围文字。目标段落可编辑时，光标落在图片原位置后的合法字素边界；若其他对象仍保护该段落，则保留原文字选择。删除保留包内图片和关系，避免误删共享资源；撤销/重做精确恢复源与选择。`noDelete`、外部对象引用及启用修订记录的文档保护删除；尺寸/裁剪锁不单独阻止删除。默认面板按 `deleteReason` 启用按钮。行为参考 [ONLYOFFICE 从 run 移除绘图](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L2899-L2963)。

`editPicture(revision, { action: "replace", id, bytes })` 替换目标图片的压缩源。`bytes` 为 `Uint8Array`，支持 PNG/JPEG，输入不超过 4 MiB，单轴不超过 4096 像素，总像素不超过 4194304；核心复用 PPTX 的文件头与尺寸校验，平台负责实际解码。目标框、裁剪、替代文字、身份和文字选择保持不变。核心创建独立资源、关系和内容类型，避免改变共享原图；这些修改合为一项历史，撤销移除新增资源，重做恢复相同字节。其他部件及原资源保留。相同字节不新增 revision；源保护、输出及 4 MiB 历史预算失败不留下部分资源。替换不受尺寸/裁剪锁单独限制，默认面板按 `replaceReason` 启用文件选择。固定框替换参考 [ONLYOFFICE replacePictureData](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/Drawings/Format/Image.js#L836-L859)；本操作保留已有裁剪。宿主在重新布局前准备新增图片；核心与 Canvas 回收当前流中不再使用的解码资源，撤销/重做时按需重新准备。

核心 `DrawingFrame.content` 的图片分支与 `PlacedDrawingFrame` 保留框和源裁剪；公共定位路径产生矩形裁剪及展开后的原图坐标，Canvas/PDF 使用同一结果。展开后的源图宽高各不超过 1e9 pt，沿用绘制坐标预算。资源仍按原键准备，不生成修改后的图片副本。缓存复制裁剪数组，调用者不能改写已保留的几何。未知裁剪/扩展、图片效果或锁定、修订容器、未知浮动锚点及旋转/翻转图片、外部图片及未支持节设置继续保护。现有 noChangeAspect 约束禁止改变宽高比；noCrop/noResize 保护整项编辑。负裁剪扩边及浮动环绕仍按 [P10](../p10-docx-core.md) 实施。源比例对应 [ONLYOFFICE 图片裁剪系数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L946-L960)，实现归 [`picture-editing.mbt`](../../modules/formats/src/docx/picture-editing.mbt)。

### 绘图对象移动与缩放手势

默认宿主在被准确选中的可编辑图片四角显示可聚焦手柄，复用核心选择框和原生指针队列。缩放始终保持原宽高比和裁剪，核心按初始尺寸与本次总位移生成候选，更新不累积上次预览。两轴都有位移时采用较大的比例；单轴位移用于键盘及沿轴缩放。四角编号 1–4 依次为左上、右上、右下、左下。尺寸继续限制为 0.1–14400 pt、整数 EMU 和原裁剪展开预算，越过相反角时钳制到最小尺寸，保留原逻辑位置。等比例追踪参考 [ONLYOFFICE ResizeTracks](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L670-L680)。自由比例侧边手柄、反转及更多浮动对象继续归 [P10](../p10-docx-core.md)。

同步 Wasm 和 Worker 的 `drawingGesture(revision, change)` 返回 `EditState`。`change` 分为 `{ action: "begin", drawing, handle }`、`{ action: "update" | "commit", id, dx, dy }` 和 `{ action: "cancel", id }`。`handle: 0` 移动正文浮动图片，1–4 缩放对应角；操作和句柄在开始时固定。`drawing` 是图片或图形列表中的绘图节点 ID，`id` 是开始后 `state.drawingGestureId` 的正整数手势身份。`dx/dy` 为 point 单位的有符号总位移，各不超过 ±14400；核心根据手柄方向换算尺寸，平台只换算 CSS 坐标。`DocxDrawingGestureCommand` 从 Wasm/Web foundation 导出。对应核心方法为 `begin_drawing_gesture/update_drawing_gesture/finish_drawing_gesture/cancel_drawing_gesture`。

可移动的选中浮动图片提供覆盖原框的移动目标，也可聚焦后使用方向键移动。移动保留尺寸、裁剪、层次和环绕。未传 `page` 的位移命令保留源段落锚点，偏移从初始位置计算。原轴为对齐时，核心按当前纸张、源边距、栏或段首布局解析偏移，只转换实际移动或参考原点改变的轴；零位移保持原对齐及源字节。数值继续按整数 EMU 舍入，移动后的偏移仍须在 ±14400 pt 内。指针点击移动目标仍聚焦正文，保持原生删除和文字替换。直接 MoonBit 移动对齐图片须提供 `probe/profile/images`；纯源偏移编辑继续可用。依据为 [ONLYOFFICE 移动追踪](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/GraphicObjects/DrawingStates.js#L2111-L2180)及[保留参考系的偏移换算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ParaDrawing.js#L1754-L1822)。指针跨段重锚和边缘翻页已接通同一手势。

指针更新和提交附带从 0 开始的 `page`。此时 `dx/dy` 是当前页内指针坐标相对起点页内坐标的总差，视口滚动计入页内坐标。核心从开始时的布局计算图片框，并在忽略图片覆盖层的最近文字位置确定锚点。同段、同页、同栏内移动保留原逻辑位置；跨段、跨页或跨栏迁移共用定位源事务。位置仍按原纸张、源页边距、栏或段落参考系写回。传入 `page` 的直接 MoonBit 调用须在开始时提供 `probe/profile/images`；未知页和受保护落点保留最后有效候选。

开始要求当前正好选中该绘图对象。缩放通过原尺寸编辑保护；移动通过独立的 `positionReason`、`noMove/noChangeWrap` 和文档保护，`noResize` 单独锁定时仍可移动。`EditState.drawingGestureId` 在普通状态为 null，与 `compositionId` 互斥。候选复用尺寸或定位命令的校验和源补丁；`flow`、布局和返回的 `selection` 展示候选；会话已提交源、选择、revision 和历史保持。更新失败保留最后有效候选；错误身份、过期 revision、未知图片源及资源上限继续拒绝。候选期间其他编辑、文字组合及直接 DOCX/PDF 持久化返回 busy。提交按最终坐标重新准备源，只新增一项历史；有效值未改变则不新增历史。取消恢复原显示和选择，不改变源与历史。图片字节、关系、替代文字、原裁剪及非目标部件保留。

松开提交，Escape、指针取消、捕获丢失及窗口失焦取消。移动目标和缩放手柄的方向键沿对应方向移动 1 pt，Shift 为 10 pt，每次按键产生一项有界编辑。普通命令、保存和暂停先处理末次坐标；`whenIdle()` 只等已接收的候选更新。恢复与销毁会取消未提交候选，已提交历史继续保留。手势使用当前 CSS 比例，DPR 留给原绘制层；图片移动复用视口边缘滚动和翻页；四角缩放仍在当前页进行。核心候选布局和正式布局共用 Canvas/PDF，平台不保存另一份文档树。实现归 [`drawing-gesture.mbt`](../../modules/formats/src/docx/drawing-gesture.mbt)、[`document-drawing-gesture.ts`](../../packages/web/src/document-drawing-gesture.ts)及 [`document-pointer.ts`](../../packages/web/src/document-pointer.ts)。

### 图片定位

`editPicture(revision, { action: "position", id, anchor })` 在正文行内图片、前置/后置的无环绕浮动图片、上下型及方形环绕之间切换，也可修改既有锚点。默认图片面板提供相同操作。`anchor: null` 表示行内；浮动值为 `{ horizontal, vertical, behind, order, wrapping, wrapSide, distance }`。两轴使用 `{ relativeTo, offset, align }`：偏移为 point 数值并令 `align: null`；对齐则令 `offset: null`。水平基准支持 `page/margin/column`，对齐支持 `left/center/right`；垂直基准支持 `page/margin/paragraph`，对齐支持 `top/center/bottom`。段落对齐沿 ONLYOFFICE 规则落在段首，数值偏移相对段首计算。

定位命令可带 `target: DocxPosition`，把既有浮动图片迁移到普通正文段落的指定字符边界。目标偏移按迁移前文档计算；同段迁移时核心扣除被移走的图片字符。`anchor` 同时给出相对目标参考系的位置。源锚点、定位和新图片选区共用一项历史。图片保留原生身份、运行格式、资源和关系。命名空间随源运行保留，目标文字的格式保持。绘图节点 ID 可能变化，下一项命令重新查询图片列表。移到自身前后边界只修改定位，相同有效值不新增历史。

跨段迁移遵循 `wp:anchor locked`；独立的 `noDelete` 不阻止移动。未知运行元数据、字段/超链接内部、表格或受保护目标、非字符边界和超限输出原子拒绝。该能力已接通核心 `set_drawing_anchor(..., target?)`、同步 Wasm、Worker 和宿主定位命令。默认指针跨段迁移也使用同一源事务。依据为 [ONLYOFFICE 跨段移动及原运行格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/GraphicObjects/DrawingStates.js#L1845-L1895)。

偏移为有限的 ±14400 pt，按整数 EMU 舍入。`behind` 为布尔值；`order` 为 0–4294967295 的整数，传输为 JSON 数字。图片目录的 `anchor` 与 Flow 的 `DrawingFrame.anchor` 显式返回浮动值或 null。`positionReason` 独立于尺寸/裁剪锁，`noMove/noChangeWrap` 和文档保护继续拒绝定位。未知位置元数据或被覆盖的位置节点中的注释/处理指令保留源并拒绝覆盖；把含扩展身份的锚点改为行内也继续保护。表格、页眉页脚、简单定位、禁止重叠、效果和其他参考系仍不支持浮动编辑。

核心先按纸张、源页边距、当前栏或锚点段落放置图片；页眉页脚让出的正文空间不改变源页边距基准。浮动图片不增加文字行宽与行高，仍占一个逻辑单元。后置图片先于文字绘制，前置图片后于文字绘制；同层按顺序及源位置排列。前置图片优先命中；后置图片在文字区域外可选，方形环绕的空隙也可选择图片。浮动选区按完整图片框计算，沿同一 Canvas/PDF 输出。

`wrapping` 为 `none`、`topBottom` 或 `square`。`wrapSide` 为 `bothSides/left/right/largest`，非方形模式使用 `bothSides`。方形环绕按图片及间距切出可用文字区域，两侧文字按段落方向连续排入同一行，共用基线、行距、光标、选区和分页。段落测量结果在各片段间复用，保留 Unicode 连接上下文和原制表位基准；段落保留、孤行及与下段/表格同页使用实际环绕行。小于 18 pt 的页边空隙沿 ONLYOFFICE 并入排除区。当前表格整体或续页片段在相交图片下方排放。

`distance` 为 `{ top, right, bottom, left }`，各值为 0–14400 pt，按整数 EMU 舍入。上下型环绕在水平相交的栏中排除图片及间距覆盖的纵向区域；文字行、表格和续页避让同一区域。源锚点与文字行分离，整页图片留在原页，后续文字进入下一页。排除区域变化会使相关分页失效，稳定输入可复用缓存。核心锚点布局及方形行高度各最多迭代八次；循环依赖或超限明确失败。

读取时支持 `wp:wrapTopAndBottom` 的 `distT/distB` 及 `wp:wrapSquare` 的四边间距覆盖锚点间距，方形侧向写为 `wrapText`；零效果范围保留支持。未设置的左右间距沿 ONLYOFFICE 使用 3.2 mm，显式零值保持。环绕属性写回原生 XML，保留图片字节、关系及未改源。依据为 [ONLYOFFICE 方形侧向与上下型排除区](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/GraphicObjects/WrapManager.js#L228-L305)、[页边空隙](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/GraphicObjects/WrapManager.js#L408-L421)及[图片间距默认值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ParaDrawing.js#L1712-L1716)。

同步 Wasm 和 Worker 的 `editPicture`、`pictureGesture` 接受第三个字体 `profile` 参数，默认 `{}`；宿主自动传入当前映射。涉及环绕的定位、尺寸、移动和缩放候选在提交前预检完整布局，缺字体、缺解码图片或排版失败保持文档、选择和历史；候选更新失败保留最后有效候选。直接 MoonBit 会话可显式传入 `probe/profile/images` 启用相同预检，纯源编辑继续使用既有有界事务。

未传 `target` 时定位保持原文字选择。资源、名称/替代文字及未改 XML 保留；一次命令一项精确历史，相同有效值不新增历史。旧修订、无效值、未知源和输出超限原子拒绝。实现归 [drawing-position.mbt](../../modules/formats/src/docx/drawing-position.mbt)、[drawing-reanchor.mbt](../../modules/formats/src/docx/drawing-reanchor.mbt)、[floating-image.mbt](../../modules/layout/src/floating-image.mbt)、[image-wrapping.mbt](../../modules/layout/src/image-wrapping.mbt)及[square-wrapping.mbt](../../modules/layout/src/square-wrapping.mbt)，依据为 [ONLYOFFICE 图片放置属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ParaDrawing.js#L986-L1057)。更广浮动对象继续归 [P10](../p10-docx-core.md)。

### 页面设置

`FoundationSession/Client.pageSetup(revision)` 与 `DocumentEditor.pageSetup()` 返回 `{ revision, page, reason, background, borders, numbering, columns }`。各属性的合同见下文。`page` 是主文档单节的源尺寸，字段为 `width/height/top/right/bottom/left`，单位为 pt；缺少节属性时使用 612×792 pt、四边 72 pt。不支持的多节、未知分栏元数据、镜像页边距、装订线或保护返回 `page: null` 与原因，不返回伪造的可编辑参数。查询不要求正文选区。

`setPageSetup(revision, page)` 同时修改尺寸与四边距，Web 编辑宿主省略 revision。`DocxPageSetup` 要求上述六个值，可选 `orientation: "portrait" | "landscape"`。省略方向时使用指定宽高；给出方向且与宽高不一致时，核心交换宽高并旋转四边距。横向时新左/上/右/下依次为原下/左/上/右，纵向反向旋转；正方形不旋转。规则依据 [ONLYOFFICE 的方向修改](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/sections/sect-pr.js#L1148-L1180)。

尺寸为 36–14400 pt，边距非负；所有数值须能表示为整数 twip，并为正文留下至少 12×12 pt。源尺寸原样写回 `pgSz/pgMar`；`Flow.page`、预览和 PDF 继续采用下文既有纸型解释规则，可能与源尺寸不同，例如 500 pt 的显示尺寸为 498.9 pt。再次应用相同源参数不产生历史，不能把显示尺寸自动写回源文档。

缺少节属性时在正文末尾创建，缺少页面属性时按 OOXML 顺序插入。修改保留段落、稳定节点身份、节元数据、其他部件、页眉/页脚距离和零装订线；清除与新尺寸不一致的旧打印机纸型代码。尺寸与边距合为一项有界历史，保留待输入格式，撤销/重做及保存重开恢复相同源参数。非法值、过期 revision、未知目标属性/注释、多节或预算失败保留已提交包。默认 UI 提供相同的读取、修改和方向选项；文档改变后要求重新读取，防止旧参数覆盖新状态。已有分栏时，修改尺寸也须为每栏保留至少 12 pt 宽度。多节及页眉页脚节间继承继续实施。

### 分栏

`FoundationSession/Client.setPageColumns(revision, columns, profile)` 与 `DocumentEditor.setPageColumns(columns)` 设置主文档单节的分栏。`DocxColumns` 必须包含 `{ count, gap, separator, custom }`：栏数为 1–12 的整数，栏间距为 0–14400 pt 且须表示为整数 twip，分隔线为布尔值。`custom: []` 表示等宽；不等宽时提供恰好 `count` 项 `{ width, gap }`，分别为栏宽和栏后间距。宽度为 12–14400 pt，间距为 0–14400 pt，均须有限且为整数 twip。`null` 移除显式 `w:cols`，恢复单栏、36 pt 间距、无分隔线及空 `custom`。缺少节属性时原子创建；`pageSetup().columns` 返回 `{ value, reason }`，不支持的源返回 null 和原因。

等宽时从可用页宽扣除全部间距再等分。不等宽时读取 `w:equalWidth="0"` 及逐项 `w:col w:w/w:space`，栏数取子节点数。前面的栏使用各自宽度和间距，末栏延伸到正文右边界；末项源宽度/间距保留，几何不使用它们。全部实际栏宽至少 12 pt。默认面板可切换模式，编辑前面各栏的宽度和间距；末栏显示核心物理页面宽度对应的剩余量，保留原元数据。Wasm/Web 沿既有 foundation 模块导出类型和命令，面板沿原有读取、重置和过期草稿保护。

正文按栏顺序续排，末页在整数 twip 上有界求解平衡高度；显式分页符及段前分页进入下一张纸。进入不同宽度时，核心按原逻辑偏移重新断开剩余文字，保留整段双向分析、字体来源、光标和终止控制符；续段不重复首行缩进或列表标记。孤行和“与下段同页”按实际下一栏宽度预估，段落缓存包含续排偏移。页眉页脚保持整页宽度，页码和总页数按实际纸张计算。Canvas、PNG 和 PDF 消费同一物理页结果；分页缓存键包含全部栏参数及平衡高度。

不等宽栏中的表格改为按实际起始栏解析百分比与适配宽度，续栏保持同一列网格。创建、尺寸命令及布局后的属性查询已接入实际位置；未提供布局的原生查询仍返回最窄栏上限。默认编辑器在布局后刷新表格查询，使尺寸面板使用实际栏的上限。分页缓存记录表格起始栏拟合后的列宽，复用时保持同一网格；自动表格的内容变化会使相关宽度失效。创建、调宽、适配、插删列、拆格、历史、保存重开及 PDF 已做定向检查。普通行、合并格与重复表头按目标栏重新取横坐标，文字、边框、底色、命中、光标和选区共用几何。固定网格超出目的栏时拒绝候选，不自动改写网格。更广跨宽度表格兼容继续实施。

修改保留正文、选择、待输入格式、页码/页边属性及其他 OPC 部件，使用一项有界源历史。同值不新增历史，撤销/重做和保存重开恢复源与布局。非法参数、旧 revision、保护、未知属性/子节点、不透明目标源、布局或输出预算失败原子拒绝。分栏符沿上文范围编辑；多节继续实施，不能把保留源记为已支持。

实现归 [`page-columns.mbt`](../../modules/formats/src/docx/page-columns.mbt) 和 [`columns.mbt`](../../modules/layout/src/columns.mbt)。等宽计算参考 [ONLYOFFICE SectionColumns](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/sections/section-columns.js#L200-L216)，栏位置和平衡参考 [DocumentPageSection](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/document/document-page-section.js#L78-L100)，分隔线参考 [Document.draw](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L5384-L5390)。未复制上游执行代码。

### 可编辑标题封面

`FoundationSession/Client.setCoverPage(revision, cover, profile)` 与 `DocumentEditor.setCoverPage(cover)` 在正文前插入或替换标题封面。`DocxCoverPage` 为 `{ title: string, subtitle: string }`；`null` 移除本 SDK 标记的封面，无封面时不增加历史。标题须有非空白内容，最多 256 个 UTF-16 单位；副标题最多 512 个单位，可为空。两者须为有效 XML 文字，不含换行、Tab、控制符或段落分隔符。默认页面面板提供相同操作，插入后光标位于标题末尾，可继续输入及修改原生格式。

核心创建居中的普通段落：标题 32 pt 粗体、段前 144 pt，副标题 16 pt；每段段后 24 pt。字体继承文档默认值。末尾空段落带段前分页，将原正文移至后页。封面使用原生书签 `_OpenDocumentCoverPage` 标记范围；重开后仍可替换或移除。普通书签命令可定位该标记，改名、创建及删除由封面命令管理。书签身份分配复用已有实现，保留正文、其他书签及 OPC 部件。书签端点和单项历史参考 [ONLYOFFICE AddBookmark](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L24423-L24501)，段前分页参考 [SetParagraphPageBreakBefore](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L20916-L20944)。标题样式是本 SDK 的基础模板规则，未复制上游执行代码；实现归 [`cover-page.mbt`](../../modules/formats/src/docx/cover-page.mbt)。

插入、替换及移除各使用一项有界源历史，撤销/重做恢复原字节和选择。候选先用现有字体、图片与完整分页校验，标题和副标题必须能放入一页；保存、预览及 PDF 沿用普通段落路径。替换/移除要求完整标记位于文档起始，范围内为受支持的普通段落，不含其他书签或不透明注释。封面外的内容保留；已有指向封面的链接或 PAGEREF 时，先移除引用再移除封面。旧修订、活动候选、保护、缺字体、布局或输出预算失败保持原文档与历史。当前仅支持单节单栏，保留已有页眉页脚及首页选项；更多封面模板、多节与分栏封面继续实施。

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

`FoundationSession/Client.runningArea(revision, kind, variant)` 返回 `DocxRunningArea { revision, content, distance, reason, differentFirst, differentEven, shared }`。`kind` 使用 `DocxRunningKind` 的 `header/footer`；`variant` 使用 `DocxRunningVariant` 的 `default/first/even`。`DocumentEditor.runningArea(kind, variant)` 沿原生输入屏障查询。`content` 是 `DocxRunningContent[]`，每项为 `{ text: string; target?: string }` 或 `{ field: "PAGE" | "NUMPAGES"; format?: "decimal" | "lowerLetter" | "upperLetter" | "lowerRoman" | "upperRoman" }`，从 Wasm/Web foundation 模块导出。当前支持单节，文字以 LF 分段，以 U+2028 表示软换行，保留 Tab；`distance` 为距纸张上边或下边的 pt，同类区域的三种变体共用该距离。不支持的源返回保护原因。

`FoundationSession/Client.setRunningArea(revision, kind, variant, content, distance, profile)` 与 `DocumentEditor.setRunningArea(kind, variant, content, distance)` 替换指定区域的文字和页码字段。核心使用 `RunningContent.Text(String)/Link(String, String)/Field(String)`，显式格式使用 `FormattedField(String, String)`。例如 `[{ text: "Page " }, { field: "PAGE" }, { text: " of " }, { field: "NUMPAGES" }]`。旧的字符串参数和查询 `text` 字段已移除。前者显式提供字体映射，编辑器复用当前映射。列表最多 256 项；文字与字段合计最多 8192 单位，文字按 UTF-16、每个字段按一单位计算。相邻文字会合并，空列表用于清空；段内最多 64 个字段。距离为 0–14400 pt 的整数 twip，并须给正文留出可用区域。缺失的 `hdr/ftr` 部件、关系、内容类型、节引用及距离在同一事务创建，候选排版和输出预算通过后提交。清空保留一个空段落和已创建部件，不清理未知资源。

文字项带 `target` 时生成普通原生超链接，移除该属性恢复普通文字。目标最多 2048 个 UTF-16 单元，接受 HTTP、HTTPS、mailto 或指向可用正文/单元格书签的 `#name`；空显示文字、非法地址及缺失目标拒绝整项修改。默认面板在每个文字项下提供链接地址，清空后移除链接。带链接的 LF 仍分段，软换行和 Tab 保留；相邻且目标相同的文字合并。查询保留链接目标，未改段落和仅改距离时保留原始 XML。目标书签改名或删除时，已知页眉页脚引用与正文合为一次事务，失败保留整包；共享和未启用变体也同步更新。未知跨部件引用继续保护。

外链关系归所属页眉/页脚部件，允许不同区域使用相同关系身份。首次关系部件及必要内容类型声明与文字共用一项精确历史；解除共享时沿既有路径复制。显示、编辑和输出不请求目标。PDF 按实际活动变体逐页生成[文字链接注释](#docx-pdf-文字链接)，复用实际文字边界与正文书签坐标，重复行计入原有预算。实现归 [running-links.mbt](../../modules/formats/src/docx/running-links.mbt)、[有序内容](../../modules/formats/src/docx/running-content.mbt)及[注释收集](../../modules/formats/src/docx/links-layout.mbt)，PDF 语义参考 [ONLYOFFICE 文字链接](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L2886-L3000)。

`FoundationSession/Client.setRunningOptions(revision, first, even, profile)` 与 `DocumentEditor.setRunningOptions(first, even)` 修改首页和奇偶页开关。核心写回单节 `titlePg` 与文档 `evenAndOddHeaders`，按需创建节或设置部件；关闭保留所有区域和引用，重新开启恢复同一内容。开关不隐式创建文字部件。首页启用时优先选择 first；其余按节起点计算的偶数页在奇偶开关启用时选择 even；其他页选择 default。缺失的活动变体显示空白，不回退到 default。选择依据 [ONLYOFFICE 页边区域解析](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Layout/Base.js#L85-L116)，未复制上游源码。

`FoundationSession/Client.unlinkRunningArea(revision, kind, variant, profile)` 与 `DocumentEditor.unlinkRunningArea(kind, variant)` 为指定共享区域创建独立部件。`shared` 按实际引用解析后的部件判断，包含非活动变体和不同关系 ID 的别名；没有共享或没有部件时不增加历史。默认面板先读取区域，再提供独立操作。

核心完整复制区域 XML 及其关系，保留注释、属性和关系 ID；内部目标改为包内绝对路径，外链保持原地址且不请求网络。图片等资源继续复用，旧部件保留。新部件、关系、内容类型及选定引用合为一次有界事务，候选失败保留原文档，支持精确撤销/重做与重开。未知或带注释的源可独立保留，纯文字编辑限制继续适用。复制思路参考 [ONLYOFFICE 断开页边继承](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L11643-L11715)，当前操作只处理单节显式共享引用，节间继承仍待实现。实现归[独立部件事务](../../modules/formats/src/docx/running-unlink.mbt)。

修改保留正文、选区、待输入格式和其他部件。距离单独变化时完整保留区域源；文字替换保留未改段落的原始 XML，修改的段落保留段落属性与首个 run 的字符属性，字段按该段原有字段顺序沿用结果字符属性，并写为标准简单域；新增段落沿用最后一段。重复设置不新增历史；开关、部件创建、文字和距离修改共用精确撤销重做及保存重开。默认页面面板提供区域、所属页面、读取、文字/字段、距离和两个开关，可在文字光标处插入当前页码或总页数，并更换字段种类、显式格式或移除，过期草稿须重新读取；应用开关保留尚未提交的文字草稿。

核心 `Flow.headers/footers` 按 `default/first/even` 保存活动区域的段落，配合 `headerDistance/footerDistance/differentFirst/differentEven` 派生各页正文上下空间。`Layout.running` 按页保存页边行，独立于正文光标行。页眉从上边距离开始，页脚在下边距离以上结束；实际行框、段距与正文边距共同确定避让。文字复用既有塑形、定位图元、Canvas/PDF 和语义文本；命中返回 `protected-content:running-area`，不产生正文编辑位置。活动区域的重复行计入原有总行数预算。几何依据 [ONLYOFFICE HeaderFooter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/HeaderFooter.js#L1735-L1804)。实现归 [`running-read.mbt`](../../modules/formats/src/docx/running-read.mbt)、[`running-edit.mbt`](../../modules/formats/src/docx/running-edit.mbt)、[开关事务](../../modules/formats/src/docx/running-options.mbt)、[页边布局](../../modules/layout/src/running.mbt)及 [`docx-running.tsx`](../../packages/ui/src/docx-running.tsx)。

分页缓存包含三种活动页的正文空间。后缀复用同时检查当前空间和页序奇偶，首段变动不能把另一类页面的旧位置复用到当前页。普通表格行、纵向合并续页、保留段落链和孤行控制按当前页空间放置；纵向合并组的重复表头仍沿既有整组预留规则，按该组经过页面的最小可用高度判断，逐片段取舍继续完善。

已导入的页眉页脚支持 `PAGE` 和 `NUMPAGES` 的格式化计算，包括 `fldSimple` 和同段内的 begin/instrText/separate/result/end 成对域。接受缺省格式、十进制、大小写字母及罗马数字的显式格式开关，以及可组合的 `MERGEFORMAT`；保留首个结果 run 的有效字符样式。派生 `Span.field` 使用空串、字段名或带冒号格式后缀的字段名，格式归[页码格式与起点](#页码格式与起点)。`Span.text` 保留导入缓存，实际页边行按节编号、显式格式和物理总页数重新塑形。正文分页、历史和重开会重新计算，Canvas、语义文本和 PDF 使用相同结果。参考 [ONLYOFFICE PAGE 与 NUMPAGES](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L918-L928)。

字段结果改变换行时，核心按每页实际页边高度有界重排正文，最多八轮；不收敛时保留最后完整布局并给出诊断，输出沿既有诊断保护。正文空间和分页缓存包含逐页几何，跨页表格也使用该页空间。现有 1024 页和 32768 行预算继续生效，每段最多 64 个字段。未知指令/开关、锁定、嵌套、不完整或跨段域继续保护且不执行；多节继承及更广编号格式继续实施，正文范围归[正文页码字段](#正文页码字段)。实现归[字段读取](../../modules/formats/src/docx/running-fields.mbt)与[有界重排](../../modules/layout/src/running-pagination.mbt)。

计算、保存和输出不改写域代码或缓存，不增加历史，也不改变原格式未保存状态。显式应用字段内容会把当前结果与内容修改放在同一项历史；内容和距离相同时，应用用于刷新已有缓存，结果相同则不新增历史。只改距离或开关仍保留区域 XML。刷新简单域和成对域时只替换结果文字，保留域代码、属性和字符样式；未知或带注释的源继续保护。缓存的 `PAGE` 使用该变体的首次出现页，加上节起点并应用节格式或字段显式格式。首页取物理首页；偶数变体取编号后首次为偶数且未被首页占用的页面；默认变体取未被活动首页/偶数区域占用的首个页面。起点为 1 时仍分别遵循原有的 1、2 及默认区域 1/2/3 规则。非活动变体采用同一规则；`NUMPAGES` 使用当前文档总页数。屏幕/PDF 仍逐页计算。更新要求完整布局及原有历史/输出预算通过，失败保留原文档、选择和历史。行为参考 [ONLYOFFICE 字段创建与更新](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L23510-L23568)，当前写回归[有序内容及字段缓存](../../modules/formats/src/docx/running-content.mbt)。

节间继承、其他字段、更广页码格式、图片/表格/审阅对象及页边原生光标仍待实现。共享同一部件的变体可显示，内容替换或缓存更新须先显式断开，避免改写其他区域；未知或带注释的目标源也不允许内容替换或缓存更新。非活动区域保持原源，启用前验证候选布局。正文查找和统计仍只覆盖既定正文范围。

### 正文页码字段

正文中的每个字段占一个逻辑对象位置，完整结果作为整体排版。位数改变或结果为空时保留该位置，光标和选区只落在字段前后。实际字形簇和完整显示文字用于语义文本、PNG 与 PDF，数字内部不拆行。页眉页脚保留原有排版方式。依据 [ONLYOFFICE 页码整体测量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/RunContent/PageNum.js#L154-L176)，实现归[字段行内排版](../../modules/layout/src/field-run.mbt)。

导入的正文和普通单元格支持 `PAGE`、`NUMPAGES` 的简单域及同段成对域，沿用上述格式开关和首个结果 run 的有效样式。`PAGE` 使用字段所在行的物理页及当前节编号；`NUMPAGES` 使用实际纸张总数，分栏不增加页号。核心先用有界初始值分页，再按字段位置与总页数重排，和页眉页脚共用最多八轮的收敛限制。原段落、单元格及分页缓存参与同一路径，Canvas、语义文本、PNG 与 PDF 共用结果；布局与保存不改缓存或历史。

`FoundationSession/Client.updateBodyPageFields(revision, profile)` 和 `DocumentEditor.updateBodyPageFields()` 显式刷新正文缓存，默认页面面板提供同名按钮。核心只改结果文字，清空多余缓存 run 的文字，保留域代码、属性、字符样式、其他部件和原选择，一次更新合为一项精确历史。结果相同不改 revision，保留当前显示布局和后续原生导航。缺字体、未知/锁定/嵌套指令、结果内注释或处理指令、保护及原有输出/历史预算失败时整体拒绝。

`FoundationSession/Client.insertBodyPageField(revision, field, profile)` 和 `DocumentEditor.insertBodyPageField(field)` 将当前范围替换为一个原生简单域。`DocxBodyField` 接受 `DocxPageField` 的 `{ field: "PAGE" | "NUMPAGES", format? }`，以及下述[书签页码引用](#书签页码引用)、[序列编号字段](#序列编号字段)和[书签文字引用](#书签文字引用)，可选格式沿用上述五种显式格式。默认页面面板提供“插入正文页码”和“插入正文总页数”。核心保留附近字符格式，写入实际布局值，将光标放到域后，插入与范围删除合为一项精确历史。正文、空段落和普通单元格共用事务。未知源、超限、缺字体及不完整布局整体拒绝，不改其他域的旧缓存。依据 [ONLYOFFICE 插入字段及直接格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L23510-L23565)，实现归[正文域插入](../../modules/formats/src/docx/body-field-insert.mbt)。

仅含受支持简单域和普通内容的段落，已有原生光标、相邻文字输入、同段范围替换、整域 Delete/Backspace 和组合输入。一个域保持一个源位置，删除整个源元素，不把结果拆成可编辑数字。查找中的后续文字也沿用逻辑位置。域的正文范围及整格剪贴板分别沿用[正文富文本片段](#正文富文本片段)与[单元格富文本片段](#单元格富文本片段)；复杂域范围及其他指令继续保护。其他普通段落可继续输入并触发实时重算。实现归[正文域输入](../../modules/formats/src/docx/body-field-input.mbt)。

正文及同一普通单元格内，Enter 可在简单域两侧拆段，段落边界 Delete/Backspace 可合并。跨段范围替换和组合输入将所选域完整移除，保留范围外的域、代码和缓存。合并时补齐移动元素的命名空间，将原段落继承的字符格式保留为直接属性。书签和批注锚点随拆合移动，被删段落中的锚点恢复到正确逻辑位置；源、选择及其他部件沿同一精确历史保存重开。跨容器、复杂/未知/锁定域和原有预算失败仍整体拒绝。依据 [ONLYOFFICE 域不可拆分](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Field.js#L169-L177)与[段落拆分及属性继承](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L13838-L13869)，实现归[正文域输入](../../modules/formats/src/docx/body-field-input.mbt)和[跨段源事务](../../modules/formats/src/docx/range.mbt)。

简单域整体参与已有字符格式查询和修改，也支持所在段落的对齐、间距等段落格式。默认格式面板、格式捕获和光标处的待输入格式共用原有命令。核心查询并修改首个实际结果 run，保留域代码、缓存文字、前置空 run 和其他缓存样式。域与邻接普通文字混合选择时，普通 run 按边界拆分，域保持完整；格式修改与后续输入各自沿精确历史保存重开。复杂域、未知字段或结果属性继续拒绝格式修改。依据 [ONLYOFFICE 字段结果格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1774-L1812)，实现归[格式查询](../../modules/formats/src/docx/format-query.mbt)与[字符格式事务](../../modules/formats/src/docx/format-character.mbt)。

`FoundationSession/Client.bodyPageField(revision, selection)` 返回 `DocxBodyPageField`：`{ revision, selection, field, reason }`。完整选择一个简单域，或把光标放在其前后的对应亲和侧时，`field` 为 `DocxBodyField`；没有可编辑域时返回 `null` 及原因。普通文字、多个域、跨段及复杂域不能作为一个域修改。查询保持原源、选择和历史。

`editBodyPageField(revision, selection, field, profile)` 修改该域的类型、书签目标、序列名称与显式编号格式。省略 `format` 时，PAGE/PAGEREF 沿用节格式，NUMPAGES/SEQ 使用十进制。核心只改指令属性和当前域的实际结果，保留 `MERGEFORMAT`、其他源属性、结果格式、空 run、选择及其他域缓存；多余结果文字清空。修改合为一项精确历史，相同语义指令不刷新缓存或增加历史。未知指令、锁定、缺字体、布局或预算失败保持原文档。显式结果刷新仍使用 `updateBodyPageFields`。

`DocumentEditor.bodyPageField()` 返回附有 `documentId` 的 `DocumentBodyPageField`；`editBodyPageField(source, field)` 核对文档、revision 和选择后提交。默认页面面板提供读取、类型、编号格式和应用控件；切换选择后须重新读取。代码修改依据 [ONLYOFFICE ChangeInstruction](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L2074-L2095)，原生简单域结构沿用已有序列化。实现归[正文域代码事务](../../modules/formats/src/docx/body-field-edit.mbt)，未移植上游执行代码。

每段最多 64 个字段，正文布局最多 4096 个字段位置。重复表头中的 `PAGE`、不可定位的结果及未收敛结果给出布局诊断，阻止不确定的刷新或输出。其他域及完整字段创作继续实施。依据 [ONLYOFFICE 字段行所在页](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L918-L928)与[实际页总数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1312-L1315)。实现归[正文字段布局](../../modules/layout/src/body-fields.mbt)和[缓存刷新事务](../../modules/formats/src/docx/body-field-edit.mbt)。

### 书签页码引用

`DocxBodyField` 增加 `{ field: "PAGEREF", bookmark: string, format?, hyperlink?: boolean, relative?: boolean }`，从 Wasm/Web foundation 导出，沿现有 `insertBodyPageField`、`bodyPageField` 和 `editBodyPageField` 使用。默认正文域面板提供目标书签输入、插入、读取及修改。名称沿当前书签创建规则，最多 40 个 ASCII 字母、数字或下划线，首字符不是数字；创建和修改目标时必须存在可用书签。

正文及普通单元格中，核心按书签起点所在的实际纸张计算页号，采用当前单节编号或显式格式。简单域可插入、查询、修改、原生输入及整域替换；已知同段复杂域可显示和刷新，范围编辑保持保护。书签改名只修改已知简单域的目标 token，保留空白、格式开关及 `MERGEFORMAT`。删除或缺少目标时，显示 `Error! Bookmark not defined.`；原缓存仍由 `updateBodyPageFields` 显式刷新。源、选择和缓存共用既有精确历史，计算、保存和输出不隐式改写原缓存。原生格式依据 [ONLYOFFICE PAGEREF](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1259-L1312)。

`relative: true` 保留原生 `\p` 开关。同页按实际光标位置显示 `above` 或 `below`；跨页显示 `on page N`，其中 N 是从 1 开始的物理页号，不使用节编号格式。`hyperlink: true` 保留原生 `\h` 标记，默认面板通过“跳转到引用目标”显式定位已提交的目标。修改目标后须先应用，再跳转。PDF 输出保留此目标，范围归[PDF 文字链接](#docx-pdf-文字链接)。

`Flow.bookmarks` 保存忽略大小写的名称到 `[startParagraph, startOffset, endParagraph, endOffset]` 的范围绑定；页码与链接定位使用前两项，TypeScript 只验证传输。最多 4096 个目标与字段位置；一次分页轮次最多访问 1048576 个候选行和光标位置，沿用最多八轮重排。普通字段片段保留原生目标名，在目标文档中重新绑定；不会复制范围外的书签，缺失时显示上述错误。重复表头中的相对引用、未知或重复开关保持诊断和编辑保护。页眉页脚、未知/受保护目标、其他引用变体和目录继续实施。实现归 [`body-page-reference.mbt`](../../modules/formats/src/docx/body-page-reference.mbt)及[字段布局](../../modules/layout/src/body-fields.mbt)，未复制上游执行代码。

### 书签文字引用

`DocxBodyField` 接受 `{ field: "REF", bookmark: string, hyperlink?: boolean }`，沿现有正文域插入、查询与修改 API 使用。名称沿书签规则，创建和修改时须存在可用目标。默认正文域面板提供文字/页码引用选择、目标、插入、读取、修改及显式跳转。REF 不接受页码格式或相对位置属性。

当前支持正文或普通单元格内、同一段落中的书签文字范围。原生指令为 `REF name [\h] \* MERGEFORMAT`，保留结果 run 的字符格式。普通文字按逻辑边界截取，目标内的 PAGE、NUMPAGES、PAGEREF、SEQ 使用当前计算值，嵌套 REF 按依赖计算；一个域仍占一个逻辑位置。缺少目标时显示 `Error! Reference source not found.`。已知简单域随书签改名更新目标 token；原生输入、格式和富文本片段沿既有事务维护。布局、保存及 PDF 不改写缓存，显式刷新合为一项精确历史。`hyperlink: true` 保留原生 `\h`，默认控件显式跳转，PDF 输出内部目标。

每项结果最多 4096 个 UTF-16 单元，依赖深度最多 64，单轮查询工作量最多 1048576。循环、无效依赖、跨段目标、绘图或换行/控制字符保留各域原缓存并给出布局诊断，阻止不确定的刷新和输出。仍沿用正文域数量、八轮分页、字体、历史及输出预算。跨段及多行内容、未带 MERGEFORMAT 的目标格式复制、编号/相对位置等开关和完整 REF 创作继续实施；未知指令保留源并保护。实现归 [`text-reference.mbt`](../../modules/layout/src/text-reference.mbt)、[书签源事务](../../modules/formats/src/docx/body-page-reference.mbt)与[字段指令](../../modules/formats/src/docx/running-fields.mbt)。行为依据 [ONLYOFFICE REF 与结果格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1417-L1495)及[目标内容和错误](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexField.js#L1496-L1595)，未复制上游执行代码。

### 序列编号字段

`DocxBodyField` 接受 `{ field: "SEQ", sequence: string, format?, restart?: number, repeat?: boolean, headingLevel?: number, hidden?: boolean }`，沿现有正文域插入、查询和修改 API 使用。默认正文域面板提供序列名称、计数方式、起始值、隐藏、插入、读取和修改控件。名称区分大小写，最多 40 个 UTF-16 单元；首字符为下划线或 Unicode 标识符起始字符，后续允许标识符续字符。每个名称独立从 1 计数，按正文与普通表格单元格的源顺序递增，不依赖 XML 节点编号或节页码。缺省格式为十进制，显式格式支持 `decimal/lowerLetter/upperLetter/lowerRoman/upperRoman`。

`restart` 为 0–2147483647 的整数，将当前域设为该值，后续同名域继续递增。`repeat: true` 显示最近的同名编号，不推进计数；前面没有同名编号时显示初始值 1。两项不能同时启用，`repeat: false` 等同默认递增。查询返回实际启用的属性；修改为普通递增时省略两项。核心使用 64 位计数，最大起始值之后仍可继续递增。开关读写依据 [ONLYOFFICE SEQ 解析](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L1941-L1993)，重新起算后的递增及最近编号语义依据 [Microsoft SEQ 定义](https://support.microsoft.com/en-us/word/field-codes-seq-sequence-field)。

`headingLevel` 为 1–9 的整数。当前域从最近的同级或更高层标题后重新计数，未出现对应标题时沿普通编号链计算。可与重复或显式起点组合；重复保持该标题范围的前值，显式起点优先。默认面板可设置或清除标题级别，切换计数方式或修改起点保留该设置。原生指令使用 `\\s n`，无效或重复级别保持源保护。标题来自有效大纲级别，复用文档默认值、样式继承及段落覆盖；普通表格内标题也按源顺序参与。`Flow.outlineLevels` 为必需的段落身份到 0–8 级别映射，省略正文段落并在无标题时返回空对象；数字键来自段落身份。核心按有界前缀计算混合编号，不使用递归，最多 1048576 个求值步骤及 40960 项缓存。样式修改更新显示，显式缓存和精确历史沿原事务。标题范围规则依据 [ONLYOFFICE 标题边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L819-L862)，常量指令语义归上述 Microsoft 定义，实现复用[有效大纲级别](../../modules/formats/src/docx/outline-level.mbt)及[正文流](../../modules/formats/src/docx/flow.mbt)。

原生指令为 `SEQ name`，接受上述编号格式开关、`MERGEFORMAT`、重新起算 `\r n`、重复 `\c` 、显式递增 `\n` 及标题重启 `\s n`。递增/重复/起点开关互斥，可与格式开关交换顺序；无效起始值、重复及冲突开关保持诊断和源保护。已知简单域和同段复杂域参与计算；简单域复用原生输入、格式修改、完整域剪贴板及一个逻辑位置。复杂域范围仍保护。新增、修改或粘贴只写当前域的实际缓存，其他域实时重算显示；`updateBodyPageFields` 显式刷新全部结果缓存，合为一项精确历史。布局、保存和 PDF 不隐式改写缓存。同名书签的改名不改变已知简单 SEQ 的序列名称。

`hidden: true` 写原生 `\h`，保留计数、重启和重复规则，结果显示为空。字段仍占一个逻辑位置，保留格式及完整富文本复制；缓存刷新写空结果，Canvas/PDF 不绘制编号。查询只返回有效的隐藏状态。沿 [ONLYOFFICE 隐藏规则](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L791-L816)，导入的 `\h` 遇到通用格式开关（包括 `MERGEFORMAT`）时仍显示，读取和保存保留原指令。API 中有效隐藏不能与显式 `format` 同时设置；默认面板勾选隐藏时清除待提交格式并禁用格式选择，修改已有域时也不保留会抵消隐藏的 `MERGEFORMAT`。取消隐藏后恢复默认十进制，再可选择显式格式。创建、修改、原生相邻输入、空结果复制、精确历史、重开及静态输出沿既有事务。

沿用每段 64 个字段、正文 4096 个字段位置及原有分页、字体、XML、历史和输出预算。当前范围为正文及普通单元格；页眉页脚及书签形式引用继续实施；题注创作归下文[DOCX 题注](#docx-题注)。未知指令和开关保留源、给出诊断并保护编辑。实现归[序列计算](../../modules/layout/src/sequence-field.mbt)、[正文顺序](../../modules/layout/src/body-fields.mbt)、[指令读取](../../modules/formats/src/docx/running-fields.mbt)及[缓存和代码事务](../../modules/formats/src/docx/body-field-edit.mbt)。依据 [ONLYOFFICE SEQ 指令](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L707-L756)、[正文计数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L789-L875)及[名称比较](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ComplexFieldInstruction.js#L906-L913)，未复制上游执行代码。

### DOCX 脚注与尾注内容

`DocumentEditor.notes()` 返回 `DocumentNotes = { documentId, revision, entries }`。每项包含 `{ kind: "footnote" | "endnote", id, text, reason, references }`；id 是所属种类内的原生十进制身份，返回为 0–2147483647 的规范字符串。references 是正文中同类、同身份引用的数量，保留原 XML 中的身份写法。分隔符不进入普通目录；孤立内容仍可读取，缺失内容的引用返回受保护占位项。默认页面面板提供目录读取、内容选择与文字修改，复杂内容显示保护说明。

`DocumentEditor.editNote(source, { kind, id, text })` 绑定目录的文档身份和 revision，替换普通注释的多段文字，LF 表示段落边界，保留首尾空段。允许空文字，含 LF 最多 32767 个 UTF-16 单元；CR、Tab 和其他控制字符继续拒绝。默认创建和修改控件使用多行输入。同步 `FoundationSession` 和 Worker `FoundationClient` 提供 `notes(revision)`、`editNote(revision, note, profile)`；宿主沿用当前布局的字体映射。`DocxNotes`、`DocxNoteKind`、`DocxNoteEdit` 从 Wasm/Web foundation 导出，结果解码和编辑校验从 Wasm foundation 导出。可排版注释在提交前检查候选布局，缺字体、布局或资源预算失败保留原源和历史。过期目录、队列内的同源竞争及受保护目录查询保持当前会话可继续使用。

`DocumentEditor.insertNote({ kind, text })` 在当前选区按文档顺序的末尾插入引用，保留所选文字。`text` 采用上述多段文字限制，可为空。正文和普通表格使用同一源插入入口，引用保留附近 run 属性并设为上标。已有 FootnoteText/EndnoteText 样式继续使用；没有时新增内容采用 10 pt 文字与普通段落。缺少内容部件时创建原生关系、内容类型、正文标记及默认分隔符，已有部件只追加新内容。身份避开已有内容、特殊注释及正文引用。资源和正文共用一项精确历史，光标留在正文引用之后，面板自动选中新内容。

`DocumentEditor.removeNote(source, { kind, id })` 删除目录中的普通内容及其至多一个正文引用，保留其他内容、源格式、分隔符和部件关系。重复引用、其他 Word 内容区域中的引用、结构化或不透明内容继续保护。命令后选区回到原引用位置；撤销恢复内容、资源和原选区。最后一个引用删除后，该段落可继续普通输入。空部件继续保留，避免清理其他源数据。孤立普通内容允许从目录删除。

同步和 Worker 客户端分别提供 `insertNote(revision, note, profile)`、`removeNote(revision, note, profile)`，返回现有编辑状态。`DocxNoteCreate`、`DocxNoteIdentity` 从 Wasm/Web foundation 导出；`checkDocxNoteCreate`、`checkDocxNoteIdentity` 从 Wasm foundation 导出。创建/删除执行完整候选布局、文档保护、资源及历史预算检查，拒绝后会话可继续使用。正文中的普通引用占一个逻辑位置。原生文字输入、同一容器内的范围替换、拆段/合并和删除键保留引用源；新文字使用基线格式。删除唯一引用时，普通注释内容沿同一事务和精确历史删除。组合输入预览同步隐藏已删除引用的内容，取消恢复原源，提交只记录最终文字。复杂内容、重复引用及其他 Word 区域共享的引用保持删除保护。普通正文和所选单元格的字符、段落及列表格式已接通既有命令和默认控件。引用参与有效格式及混合查询，所选范围沿原 run 边界拆分，保留注释身份和内容部件。折叠处的待输入格式随实际文字提交，邻接引用的新文字保持基线。含引用的整格选择沿用矩形高亮、混合查询和底色等共用属性事务。原生输入及组合提交只替换首格，删除清空全部所选格；注释内容清理、预览取消及精确历史采用同一归属检查，范围外内容保持。含引用格的行列增删、合并/取消合并、拆格、尺寸、自动适配和拆表已接通既有命令与默认控件。移动保留原引用和内容，新空格清除仅属引用的样式与上标。删除格或最后一行时，普通内容随同一事务清理，结构化内容仍原子拒绝；撤销/重做精确恢复正文、资源和选择。含引用的正文位置已支持新建表格，拆段保留两侧引用，覆盖范围同步清理普通内容。新空格继承当前位置的基线与待输入格式。搜索在正文和普通格中将引用计为一个逻辑对象，保留后续文字偏移，不跨过引用匹配相邻文字；匹配选择及普通、跨段、批量替换复用同一源与资源历史。正文搜索不包含注释内容区域。引用旁的折叠光标查询与实际输入均清除仅属引用的样式和上标，显式待输入格式继续生效。注释区域光标继续实施。

普通单段或多段文字注释已随正文、单格范围及单元格矩形的富文本片段复制、剪切和粘贴。纯文本输出当前显示编号；原生片段携带注释内容、原生标记及解析后的字符/段落格式，保留混合文字样式。目标文档分配独立身份，创建或复用内容部件、关系、内容类型和默认分隔符；重复粘贴不共享内容。覆盖目标引用时同步删除其原内容，正文与资源合为一项精确历史。复制和资源预检不修改源，剪切先检查内容归属，并沿既有系统剪贴板写入成功后的删除入口。无内容的裸引用、错误标记、未知种类和缺字体拒绝粘贴；列表、结构化或不透明注释继续保护。默认 Copy/Cut、保留源格式粘贴及原生快捷键复用[正文富文本片段](#正文富文本片段)，实现归 [`notes-clipboard.mbt`](../../modules/formats/src/docx/notes-clipboard.mbt)。单元格片段也支持覆盖原引用和扩展目标网格。TSV 写入普通文字时，即使显示值与原编号相同，也会移除被覆盖的引用及其普通内容；原生片段则分配独立身份。含注释的表格布局预检保留整个文档及其注释区域。注释内容独立复制参考 [ONLYOFFICE FootnoteReference.Copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/RunContent/FootnoteReference.js#L108-L126)。

核心按原生关系查找内容部件，修改目标文字节点，保留正文引用、注释标记、段落/run 属性、源注释、分隔符和其他部件；新文字首尾空白显式保存。空段落在原位置新增普通文字 run。按 LF 保留或增删段落；新增段落继承最后文字 run 和段落属性，不复制段落源身份。仅有编号标记时，新文字清除标记专属样式与上标。原生标记必须唯一并位于首段。一次实际修改只记一项精确历史，无变化保持源和 revision；撤销/重做恢复原部件与选择。字段、其他结构、正文内未知标记、文字节点内不透明源及跟踪属性继续保护；外部/共享部件、重复身份及无效 XML 身份拒绝操作。每类最多 4096 项内容和 1048576 个文字单元，合并目录最多 8192 项，沿用 XML、历史及输出预算。

已有普通文字注释已接入单节、单栏核心布局。正文和普通表格中的引用占一个逻辑位置，按原生连续编号的格式和起始号显示；编号设置的修改命令仍待接入。脚注按引用行预留页底空间，空间不足时移动引用，长文字续排后页；尾注文字进入文末并参与分页。正文与页眉页脚的 PAGE、NUMPAGES 使用包含注释页的最终页数。注释复用字体、段落测量及输出管线，保留原文字和外观，进入实际 Canvas、语义内容及 PDF。编号和分页为派生结果，保存不改写原 XML。

`DocxFlow.notes` 是必需数组，每项为 `{ kind, key, paragraph, node, content }`。paragraph、node 定位正文引用，content 使用独立的负段落身份和只读区域，避免与正文和页眉页脚源节点混淆。内容面板继续按种类和身份修改文字，画布中的注释区域暂不提供原生光标输入。含注释的页面重排暂不复用整页缓存，段落测量继续复用。最多 8192 项注释，沿用 1024 页、32768 行与字体/XML/输出预算。

当前支持普通文字段落及可整体放置的含脚注表格行组。多栏共享脚注、超高含脚注行组的分片预留、注释内部的表格/对象/域、链接/审阅锚点、自定义引用标记和分隔符、非连续编号均待接入，不能解释时保留诊断或拒绝布局。复杂段落保持规则和完整分隔符保真仍待实现。注释区域光标及内容的富文本编辑继续按 P10 实施，不标记脚注功能或阶段完成。实现归 [`notes-read.mbt`](../../modules/formats/src/docx/notes-read.mbt)、[`notes-edit.mbt`](../../modules/formats/src/docx/notes-edit.mbt)、[`notes-create.mbt`](../../modules/formats/src/docx/notes-create.mbt)、[`notes-remove.mbt`](../../modules/formats/src/docx/notes-remove.mbt)、[`notes-layout.mbt`](../../modules/formats/src/docx/notes-layout.mbt)、[`布局预留与续排`](../../modules/layout/src/notes.mbt)和 [`docx-notes.tsx`](../../packages/ui/src/docx-notes.tsx)。原生内容区域参考 [ONLYOFFICE FootEndnote](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/FootEndnote.js#L49-L69)，跨页续排参考 [ONLYOFFICE Footnotes](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Footnotes.js#L272-L351)，保留所选文字的插入行为参考 [ONLYOFFICE AddFootnote](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L18859-L18904)。

### DOCX 题注

`DocumentEditor.insertCaption(caption)` 与同步 `FoundationSession`、Worker `FoundationClient.insertCaption(revision, caption, profile)` 接受 `DocxCaption = { label, text, position: "before" | "after", format? }`。`DocxCaption` 从 Wasm/Web foundation 导出，`checkDocxCaption` 从 Wasm foundation 导出。标签采用现有 SEQ 的标识符规则，最多 40 个 UTF-16 单元；说明是最多 1024 单元的有效单行文字，可为空。编号支持十进制、大小写字母及大小写罗马数字，缺省十进制。默认页面面板提供标签、说明、位置与格式控件。

核心在焦点所在正文段落或其所属普通表格前后插入一个题注段落，保留所选正文及表格内容。段落由标签、原生 SEQ 简单域和说明组成；同名编号按正文顺序重算显示，其他名称独立计数。只缓存新域，其他域的源缓存由现有显式刷新命令维护。既有 Caption 身份或英文名称对应的段落样式保持原源；没有时使用现有题注预设创建样式，缺少样式部件时一同创建关系和内容类型。上方题注带保持下段属性。新段落、缓存及样式资源合为一项精确历史，撤销恢复原选区；光标进入题注末尾，可继续原生输入和现有字段编辑。

文档保护、单节、字体、完整布局、XML、字段数量、资源及历史预算沿现有核心规则。斜体题注预设要求宿主提供对应字体映射；失败保留原包及历史。章节前缀、自动定位的浮动题注框及题注目录继续实施。实现归 [`caption.mbt`](../../modules/formats/src/docx/caption.mbt)和 [`docx-caption.tsx`](../../packages/ui/src/docx-caption.tsx)。段落/表格旁插入及 Caption 样式依据 [ONLYOFFICE AddCaption](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L25688-L25828)，交互范围参考 GenOffice 的标签、SEQ 与说明入口。

### 表格创建

`FoundationSession/Client.insertTable(revision, selection, rows, columns, profile)` 与 `DocumentEditor.insertTable(rows, columns)` 在正文范围插入固定网格，默认 UI 提供行列输入。rows 为 1–1000，columns 为 1–63，总格数最多 4096，并受 XML、历史和输出预算限制。列宽按当前单节布局的可用栏宽分配整数 twip，余量逐列分配，每列至少 12 pt。沿用当前纸型解释，不改源页面设置。未知或受保护的正文、嵌套表格、多节及无法解释的页面设置拒绝操作。

核心先删除所选文字；在段中插入时拆分段落，在段首插入时保留原段落作为后续内容。新增表格使用 0.5 pt 黑色完整网格、5.4 pt 水平单元格边距与固定列宽。单元格复制插入起点的有效字符格式及支持的段落属性，并将缩进与段前分页显式归零。若段首已有段前分页，则转移到首格首段，保留表格在该页开始的位置；页首不生成额外空页。其他单元格的段前分页仍受原有布局保护。

范围删除、段落拆分与新增节点共同提交一项历史，选区进入首格。核心失败保留已提交源与历史。保存及混合文字编辑的撤销/重做精确恢复源节点、选择和其他部件。新增格可继续输入、设置已有字符/段落格式及用 Tab 导航。固定及自动适配布局均沿同一表格模型排版。

`FoundationSession/Client.editTable(revision, selection, change, profile?)` 与 `DocumentEditor.editTable(change)` 接收带 `action` 的对象。行列操作为 `{ action: "rowBefore" | "rowAfter" | "deleteRow" | "columnBefore" | "columnAfter" | "deleteColumn" }`。范围支持单格及下述[同表跨格选择](#跨格行列与矩形合并)，默认 UI 提供同样的六个命令。新增行复制当前行的行/格属性及各格首段格式；新增列复制邻格属性和首段格式，不复制文字，保留格式继承。固定宽表格保持总宽，按原列宽比例缩放为整数 twip；未指定固定宽的网格按插入/删除后的列宽计算。列编辑结果须在可用页宽内，各实际单元格至少 12 pt；重建出的细分网格可更窄。全部命令遵守创建时的行列、格数及资源上限；生成源片段时累计预算，超限即停止。

单格选择时，行操作作用于当前格所在的实际源行。插入位置穿过纵向合并时，新行延续该合并；在合并范围外插入时，新格保持横向跨度并独立。删除起始行会删除该行内容，后续延续格成为新起始格，不转移已删文字；删除延续行保留起始格内容。保留原网格、行属性、宽度偏好及固定/自动适配模式。新增行进入首个非延续格；整行均为延续格时进入覆盖它的起始格。候选源沿现有字体上下文检查可写性、有效宽度和分页，失败保留已提交状态。合并列删除遵循下述整格相交规则。行为依据 [ONLYOFFICE 行插入与删除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9997-L10293)，实现归 [`table-row-edit.mbt`](../../modules/formats/src/docx/table-row-edit.mbt)及[`共享结构事务`](../../modules/formats/src/docx/table-grid-structure.mbt)。

左右插列使用所选整格的有效宽度。每行在指定边界相邻的完整单元格前后插入，不切开已有格；各行插入位置可以不同。核心按插入后的实际格边界重建公共网格和 gridSpan，固定宽表格按比例保持总宽。原文字、段落身份和纵向合并归属保留；新格复制右邻格的格/首段格式，行末复制左邻格。新格可延续同一来源的纵向合并，保持空白；dxa/pct 格偏好按有效宽度写为 dxa，auto/nil 保留，整表适配模式不变。未知源、缺字体、格宽不足、分页或预算失败均不提交。依据 [ONLYOFFICE AddTableColumn 与网格重建](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L10516-L10788)及[公共边界计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L15005-L15155)，实现归 [`table-column-insert.mbt`](../../modules/formats/src/docx/table-column-insert.mbt)。

列删除以当前整格的左右网格边界为范围，删除各行中与范围相交的完整单元格及全部内容。横向合并格不会只缩短跨度。核心按存活格的宽度重建公共网格；固定宽表格保持总宽，auto/nil 偏好保留。空行及修正后全部为纵向延续的行移除；其他纵向延续只能接到同一原始归属和相同边界，不能与无关格合并。删除最后所有格时移除表格并进入正文。依据 [ONLYOFFICE 列选择](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L19140-L19171)与[RemoveTableCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L14338-L14520)，实现归 [`table-column-delete.mbt`](../../modules/formats/src/docx/table-column-delete.mbt)。

删除后各行可有不同的实际宽度，源 `trPr/gridAfter` 记录行尾空缺。解析、行列维护及拆格同步这些边界；空缺不产生单元格、填充或外框。`gridAfter` 须为 0–63 的整数，实际跨度加空缺必须等于公共网格列数。有效细分网格可小于 6 pt，实际单元格仍须留下文字宽度。当前支持从第 0 列开始的行，非零行首空缺及其余行宽属性仍待实现。未知源和保护内容在删除前检查；候选字体/分页、源、历史及输出预算失败保留已提交状态。

新增列将光标移到新列首行。删除操作将光标移到相邻的剩余行或列；删除最后一行或列时移除表格，进入后续正文段落，必要时创建空段落。首格段前分页随结构转移。末格 Tab 在最后一个实际源行之后新增一行并进入首格，即使最后一格的合并起始点位于前行，Shift+Tab 在首格保持原位。每次结构操作与新增身份、列宽及选择合为一次历史，保留未删文字与其他部件，支持保存重开和精确混合撤销/重做。未知结构、锚点、受保护内容或预算失败原子拒绝。行为依据 [ONLYOFFICE 行列操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9997-L10788)和[固定宽网格缩放](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L414-L425)。

`{ action: "merge", rows, columns }` 从当前格的左上网格位置合并指定矩形。范围为 1–1000 行、1–63 列且最多 4096 个网格位置，不能切开已有合并格。内容按行优先顺序进入左上格，保留段落、字符格式和空段落；列网格不变，更新格宽、gridSpan 与 vMerge。`{ action: "unmerge" }` 取消当前格的合并，恢复原网格各列和行，全部内容留在首格，新增格保留相应格式并置空。两者使用同一有界源历史，可与格内输入精确混合撤销，保存后继续编辑。相同合并范围或取消未合并格不新增历史。书签等受保护锚点、未知格属性及输出预算失败原子拒绝。内容顺序参考 [ONLYOFFICE 合并](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9466-L9530)。

`{ action: "splitCell", rows, columns }` 将当前单格或所选各主格分别拆成指定行列，默认 UI 提供同名操作和数量输入。普通格可新增 1–1000 行、1–63 列；纵向合并格的行数须不超过原合并行数，且能整除原行数。`1×1` 不改变源或历史。它与 `unmerge` 不同：列边界按当前有效宽度等分到整数 twip，合并原有边界后细分公共网格；未选格按新增边界更新跨度，保留原内容和横向范围。

跨格操作把各主格的列切点合为一个公共网格，保留全部旧边界。同一源行中的普通格共享新增行，不按目标格重复追加。纵向合并仍按原源行组分区；相邻普通格增行时，在对应组中加入延续格，保持请求的逻辑拆分行数。所有目标合为一项源事务，光标进入首个主格；1×1 保留整个原范围及 revision。

普通格新增行时复制原行属性，邻格通过纵向合并保持原内容和范围。原段落内容全部留在左上格；新格为空并复制相应格/首段格式。保留原段落身份、非目标内容和其他部件，光标进入左上格。dxa/pct 宽度偏好按列数分配并保持总量，auto/nil 保留；邻格的宽度偏好和整表固定/自动适配模式不变。

结果仍须满足最多 1000 行、63 个公共网格列和 4096 个网格位置，新增源、历史及输出受既有预算约束。核心使用字体 profile 先检查候选格内宽度与分页，边距不足、未知格/行属性、保留的属性注释、缺字体或预算失败时原子拒绝。操作与选择合为一次精确历史，可与文字输入混合撤销、保存重开并沿同一布局输出 PDF。当前合并行组仍须能完整放入一页。算法依据 [ONLYOFFICE SplitTableCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9609-L10001)，实现归 [`table-cell-split.mbt`](../../modules/formats/src/docx/table-cell-split.mbt)。

`{ action: "splitTable" }` 在所选单元格所在行之前拆分正文表格，两表之间插入空正文段落，光标进入下表首格。首行、缺少段落的单元格、嵌套/受保护表格、未知结构及预算失败拒绝操作。两表保留列网格、宽度、边框、样式和单元格内容；原有行和未替换内容的身份保持。纵向合并跨越分界线时，内容留在上表，下表从对应位置创建空的合并起始格，复制原合并格格式并清除段前分页；后续延续格继续归属下表。分界、空格及选择一次提交历史，支持原样撤销、保存重开、继续输入及同布局 PDF。默认 UI 使用同一操作。拆表与跨度清理参考 [LibreOffice SplitTable](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/source/core/docnode/ndtbl.cxx#L3392-L3515)及[纵向跨度清理](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/source/core/table/swnewtable.cxx#L2021-L2110)。

布局读取横向跨度及纵向起始/延续格，文字、背景和边框使用合并后的矩形；Tab 跳过纵向延续格。纵向合并格可跨源行与页面继续，保持起始格的内容归属、底色、边框与逻辑位置。普通行已支持[逐格跨页](#表格行跨页)，重复表头见[当前合同](#重复表头)。包含可见内容的纵向延续格明确拒绝，避免隐藏其文字。含合并格的行增删遵循上述规则；列删除按所选整格的横向范围移除相交格。默认 UI 提供从当前格指定行列数量的合并，以及单格或跨格取消合并；鼠标属性选择归[跨单元格属性选择](#跨单元格属性选择)，其余范围编辑仍归 [P10](../p10-docx-core.md)。

### 跨单元格属性选择

鼠标拖动或 Shift 扩选的两个端点位于同一受支持表格的不同格时，核心按端点的逻辑网格范围选择相交整格。横向跨度与纵向合并属于同一格；修改同步全部纵向延续节点。`EditState.formatting.cellSelection` 返回表身份、半开行列边界、实际格数、底色和垂直对齐的共同值或混合值。`value.margins` 的 `top/right/bottom/left` 分别返回有效边距的 `{ kind: "value", value }` 或 `{ kind: "mixed" }`，数值单位为 point，包含样式、整表及单格覆盖。无跨格范围时 `value` 为 null，保护失败另给 `reason`。同格内仍使用普通文字选区。

默认表格面板显示所选格数，提供批量底色、清除、顶部/居中/底部对齐与恢复继承。四边边距复用单格及整表的表单，各边分别显示共同数值或留空并提示混合；填齐四边后使用既有 `cellMargins` 命令设置全部所选格。“使用继承边距”移除各目标格的直接覆盖，再按各自样式和整表默认值求有效边距。表单随文档、revision 和原选择重新加载，保留数值校验及选择。混合查询和批量重置依据 [ONLYOFFICE Get_Props](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L472-L494)及[所选格边距修改](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L1094-L1155)。

`value.borders` 按 `top/right/bottom/left` 返回所选主格同名边的共同 `{ kind: "value", value: { width, color } }` 或 `{ kind: "mixed" }`。宽度为零仍是共同值；任一合并主格的同一边含不同线段时，该边保持混合。查询沿已有共享边冲突结果，保留单格查询的格式。默认面板复用 [`docx-borders.tsx`](../../packages/ui/src/docx-borders.tsx)，提供单边或各格四边的线宽、RGB、显式移除与恢复继承；范围面板只调用既有 `cellBorders`，整表入口保持独立。每个所选主格的同名边一起修改，不将“各格四边”解释为选区最外框。清除写入无边框覆盖，继承移除指定侧的直接定义；相邻格和表样式仍按[边框冲突规则](#表格边框)求最终线段。源属性和段落不变的范围外格保持。共同/混合比较参考 [ONLYOFFICE 所选格边框查询](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L397-L465)。

[行跨页开关](#表格行跨页)作用于端点覆盖的实际源行，逐行判断无变化。`value.rowSplit` 返回这些行有效设置的共同布尔值或混合状态，默认面板使用半选复选框显示混合值，点击后统一允许拆分，再次点击统一禁止。同一源行的其他格共享此开关，范围外行保持。属性共用候选布局检查、单项历史及输出预算，保留文字、网格、选区和其他部件；支持精确撤销、重做及保存重开。边距面板归 [`docx-margins.tsx`](../../packages/ui/src/docx-margins.tsx)。

核心 `Session.selection_rects(layout, selection)` 从已有 `cellAreas` 返回完整所选格在各页的覆盖框，Wasm 和 Canvas 沿既有选择几何查询显示，不进入 PDF 或原格式。标尺在文字拖动期间保留当前显示，结束后再查询，避免中断鼠标捕获。参考 [ONLYOFFICE 相交格选择及合并归属](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L15872-L15976)，实现归 [`table-range.mbt`](../../modules/formats/src/docx/table-range.mbt)。

`value.rowHeight` 与 `value.rowHeightRule` 分别返回所选实际源行的共同高度、共同 `atLeast/exact` 模式或混合值。自动高度为 `0/atLeast`。`value.maxRowHeight` 是这些行可统一设置的最小高度上限，单位为 point；核心按纵向合并行组扣除边框、未选行的最小高度和各行边距，不按旧高度逐行独立计算。候选仍须通过整组页面及边距校验。查询不改源或历史。

跨格选择调用既有 `editTable({ action: "rowHeight", value, rule })`，一次修改端点覆盖的实际行及其中未选列的格。单格与跨格共用默认行高表单，混合高度留空、混合模式显示占位，显式填齐后提交。固定值保留完整文字并沿既有规则裁剪；`0/atLeast` 恢复自动。修改保留所有格源内容、跨度、其他行属性、范围外行及原逻辑选择，合为一项精确历史；重复同值不增加历史，任一保护或预算失败整体拒绝。行范围依据 [ONLYOFFICE SetRowHeight](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L19045-L19059)，实现复用 [`table-size.mbt`](../../modules/formats/src/docx/table-size.mbt)；表单归 [`docx-cell-selection.tsx`](../../packages/ui/src/docx-cell-selection.tsx)。

字符与段落格式、样式应用、格式复制/应用和列表操作使用所选整格内的全部段落，包括空段落；手势端点位于文字中间时也不截断首尾格。有效格式查询沿相同范围返回共同值或混合值。字符与段落格式可合为一项历史，保留原选择端点、非目标格的源片段和其他部件；恢复后可在空段落继续原生输入。普通段落拆分候选继续按候选文档校验，不查询旧源中的新段落。规则参考 [ONLYOFFICE 所选格文字属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L6207-L6263)及[段落对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L7763-L7783)，写回复用既有格式事务。

#### 跨格内容输入与清空

所选整格的非空 `replaceRange` 输入只替换按源顺序的首个所选格，其余格保持原样。LF 在首格内拆段；Enter 先替换首格内容，再沿原有段落/列表规则处理。Delete/Backspace 或空文字替换清空全部所选格，每格留下一个空段落，光标落在首格。行列、合并归属、格属性和非目标格保持；清空后仍可 Tab 导航及原生输入。

每次操作沿现有源补丁合为一项有界历史，撤销恢复全部格和原始选择；单段内容相同或已空单段格清空时只收起选择，不增加 revision 或历史。成对书签随各自格内范围收缩，保留原格归属。组合预览每次从已提交网格和选择重建，取消保留源、选择和重做；提交只替换首格。输入框的无障碍说明报告所选格数。依据 [ONLYOFFICE 所选格删除与输入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L6288-L6335)，实现归 [`table-contents.mbt`](../../modules/formats/src/docx/table-contents.mbt)。

#### 跨格纯文本剪贴板

`selectedText` 按源顺序读取所选整格的全部文字。格内段落以 LF 分隔并保留空段，同一源行的所选格之间用 Tab，每个所选行末尾保留 LF。合并格的内容只提取一次，纵向延续不重复，也不生成占位字段；段内 Tab 和软换行沿已有纯文本合同保留。正反选结果相同，分隔符全部计入 65536 UTF-16 单元上限。规则参考 [ONLYOFFICE 所选格提取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L7450-L7482)、[所选行末格判断](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableCell.js#L2281-L2304)及[段末分隔](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js#L3201-L3223)，换行统一为 SDK 已有的 LF。

默认 Copy/Cut 和原生快捷键复用同一入口。核心先完成提取与保护检查；宿主写入成功后核对 revision 和原选择，再沿现有整格清空事务剪切。复制不写历史，剪切合为一项历史，保留表格结构、属性、其他部件和精确撤销。写入拒绝时保留源和选择，沿现有显式恢复入口继续。当前复制仍输出纯文本，格式和表格片段继续实施；含图片或未知内容的跨格范围继续保护。

#### 单元格矩阵粘贴

`editTable({ action: "pasteCells", text })` 和默认“粘贴单元格”按钮显式读取矩形 TSV。Tab 分列，LF 分行，CRLF/CR 统一为 LF；带引号字段支持格内 Tab、换行和双写引号。空字段清空目标格，末尾行分隔不新增一行。各行字段数必须相同。普通原生粘贴继续沿已有文字输入规则处理。

矩阵从当前格或所选范围按源顺序的首个主格写入。矩阵决定写入尺寸，不重复填满或清空选区余下部分。缺少的底部行和右侧列一次补足，保留目标格格式；新格沿现有源模板继承文字和框格式，新行沿表尾行模板。新增列按整数 twip 比例分配当前有效总宽，保留余数；新列和修改后的实际格宽至少 12pt。未改文字、段落身份、表属性和其他部件保持。整个操作只提交一项历史，精确撤销恢复原选择；无变化保留源、选择和 revision。

目标必须是支持的普通格，覆盖任一合并格或缺失源格时整体拒绝。扩列要求源行完整。全表最多 1000 行、63 列、4096 个逻辑格，输入最多 65536 UTF-16 单元。逐格候选重解析累计最多 64 Mi UTF-16 单元，并沿既有源、历史、字体、布局和输出预算原子检查。默认按钮在读取后等待已接受输入，并核对文档、revision、选择和拖动状态；读取拒绝或目标变化保留文档，可重试。

普通纯文本 Copy/Cut 不携带矩形与合并信息，也不转义格内分隔符；含这些内容的结果不能视作可往返的 TSV。需要矩形往返时使用下述显式复制模式。覆盖和自动补足行列的操作依据 [ONLYOFFICE InsertTableContent](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L18018-L18118)。纯文本入口继续保护合并目标；富文本入口见下文。实现归 [`table-paste.mbt`](../../modules/formats/src/docx/table-paste.mbt)；DOCX/XLSX 共用内部 [`TSV 解析器`](../../modules/formats/src/internal/delimited/clipboard.mbt)。

#### 单元格矩阵复制与剪切

`DocumentEditor.copy(cut = false, mode?: "cells")` 的显式 `"cells"` 模式对应默认“复制单元格”和“剪切单元格”按钮。核心 `tableClipboard(revision, selection)` 返回 `{ text, selection, fragment, reason }`，查询不改源、选择或历史。`text` 为矩形 TSV，每行以 LF 结束。含 Tab、LF、CR 或双引号的字段用双引号包围，内部引号双写；格内段落和软换行统一为 LF。普通 Copy/Cut 和原生快捷键保持原合同。

矩形覆盖所选主格的完整跨度，TSV 文字只写在各主格左上角。合并覆盖位置、源空缺和边界扩展后未选择的格填空字段；不递归扩大文字选择，也不读取或清空未选择的主格。单格光标或同格文字选择均复制该格全部段落。TSV 不恢复源合并、样式或资源；`fragment` 另携带支持的富文本矩阵。

返回的 `selection` 是剪切清空范围：跨格保留原整格范围，单格扩展至该格全部段落。宿主写入剪贴板成功后，核对编辑器生命周期、原 revision 和选择，再沿既有 `replaceRange` 清空。写入失败或目标变化保留源；清空保留格属性、表结构和精确历史。含图片、字段或其他不支持内容时，在写入前保护拒绝。

矩形最多 4096 个位置，转义与分隔符计入 65536 UTF-16 单元上限。实现归 [`table-clipboard.mbt`](../../modules/formats/src/docx/table-clipboard.mbt)，字段转义复用既有 XLSX 逻辑。整格内容依据 [ONLYOFFICE 所选格提取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L7450-L7483)，矩形分隔和引号依据 [ONLYOFFICE 工作表文字剪贴板](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/clipboard.js#L1828-L1850)。

#### 单元格富文本片段

支持的普通段落和完整矩形合并生成非空 `fragment`，`reason` 为空。片段由核心生成和解析，宿主将其视作不透明字符串。字符及段落样式解析为直接属性，保留混合字符、空段落、Tab/软换行、自定义制表位、底色、边距、垂直对齐及横纵合并。片段不引用源样式身份，复制后修改或关闭源文档不改变内容。

普通文字链接也随片段复制。核心保留目标、混合字符、提示文字及已支持的链接元数据，不携带源关系 ID。粘贴时在目标文档分配或复用外部链接关系，多条链接一次写入同一部件；相同目标共享关系。内部 `#书签名` 保持名称，须引用目标文档已有书签或同片段内完整复制的书签。链接遵循既有目标和 XML 校验，未知属性、源关系身份及失效书签整体拒绝。完整普通链接可被目标片段覆盖，未覆盖链接和已有关系保持。正文、关系创建及选择共用一次精确历史，失败保留源包及历史。

普通成对书签随完整范围复制，支持点锚点、跨段落/单元格，以及链接中的标记。范围内各段均须被选中；遗漏端点或中间格时只提供 TSV 和原因。片段使用局部身份，粘贴时为新名称分配目标中未占用的 ID；目标已有同名书签时保留原书签，跳过复制的标记，不重命名或覆盖原目标。名称按既有规则忽略大小写比较。书签、文字及资源沿同一历史提交；保存重开后可继续改名、跳转及输入。已有目标格中的书签仍保护覆盖，包括重复粘贴到刚创建书签的格。

普通编号与项目符号携带实际引用的原生定义、级别和重启值。目标重新分配编号及抽象定义身份，共享的源定义仍共享；不接入目标已有列表。标记从所带定义的起点计算，正文不包含伪造的编号文字。主题字体和颜色在复制时解析，段落标记字体保留来源外观。编号部件、关系、内容类型和正文合为一项历史；布局及制表位验证读取候选部件，保存重开后可继续输入和改级别。段落样式产生的不同标记下划线使用独立编号实例和原生级别覆盖，共享同一抽象定义以保持连续计数。起始覆盖只放在每个源实例的第一个样式变体中，避免遇到新样式时再次重启。已有显式级别下划线保持；未知编号资源继续保护。实现归 [`table-fragment-list-instance.mbt`](../../modules/formats/src/docx/table-fragment-list-instance.mbt)，计数与首遇覆盖依据 [ONLYOFFICE NumberingInfoEngine](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js#L28785-L28924)。

行内 PNG/JPEG 图片随普通单元格片段复制，保留文字顺序、尺寸、四边裁剪、名称和描述。相同压缩资源共享目标关系，绘图身份分别分配，已有图片身份保留。压缩字节、正文、关系及内容类型合为一次历史，保存时移除片段中的私有载荷。锁定复制、外链图片、未知绘图扩展及浮动图片继续保护。实现归 [`table-fragment-images.mbt`](../../modules/formats/src/docx/table-fragment-images.mbt)，元数据复制参考 [ONLYOFFICE Image.Copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L162-L200)，未复制上游执行代码。

`FoundationSession.tableFragmentImages(revision, fragment)` 和异步 `FoundationClient.tableFragmentImages` 返回 `{ revision, images: [{ key, bytes }] }`，其中 `bytes` 为 `Uint8Array`。查询在副本上校验片段及资源，不改源包、选择和历史。同步宿主须先解码并用 `addImage` 注册 RGBA；Web `editTable` 自动完成解码和注册，再提交核心事务。解码失败保留原文档，沿编辑器既有 `resume()` 路径恢复。

`editTable({ action: "pasteFragment", fragment })` 从当前主格写入片段矩形。它可替换完全覆盖的目标合并，并补足底部行和右侧列；部分覆盖合并整体拒绝。列宽、行高和表属性沿目标网格，格宽按目标跨度更新。未改格、格间注释和其他部件保留，写入、扩展、选择与精确撤销合为一项历史；不含资源身份时，相同源片段无操作；列表、图片和基础图形片段每次分配独立身份。

简单 `PAGE`、`NUMPAGES` 域可随整格、跨格矩形及完整合并格转移。TSV 使用当前布局的实际值，富文本保留原生指令、显式编号格式和解析后的字符格式。布局要求及缓存规则复用[正文域片段](#正文富文本片段)；MoonBit `table_clipboard` 也接受可选 `layout`，同步及 Worker 桥传入当前布局。粘贴可覆盖目标简单域并扩展网格，只更新新域缓存；已有域缓存保持。域、图片、文字及扩表共用一项精确历史。原生输入、Enter 和组合输入沿所选主格处理，整格删除清空域并保留网格。含简单域段落的普通文字可查找替换；图片和域均占一个逻辑位置。

默认复制及显式“剪切单元格”同时写 `text/plain` 和 Chromium 自定义类型 `web application/x-open-document-docx-cells`。`tableClipboard(revision, selection, cut = false)` 在 `cut=true` 时检查图片和域的完整富文本及原生删除权限，查询保持只读。剪贴板写入成功后，Web 再核对文档、revision、选择和生命周期，沿既有范围删除事务清空所选完整单元格。写入失败不修改源；切出的图片资源仍留在源包，支持精确撤销。底层纯文本 selectedText(cut=true) 继续保护图片和域；默认正文富文本剪切归下节。

默认“粘贴单元格”及 Web foundation 导出的 `pasteDocxCells(editor)` 优先读取片段；只有缺少此类型时读取 TSV。无效片段不回退成文字。读取后核对文档、revision、选择和生命周期，再沿既有编辑队列提交。

富文本范围须包含完整所选矩形，合并边各段须有共同宽度和颜色。复杂列表、不完整或复杂书签、批注身份、复杂域和未知结构的资源转移继续实施；可提取文字但不能生成富文本时返回 `fragment: null` 及具体 `reason`，系统剪贴板保留原 TSV。图片格已有富文本复制和显式剪切。跨格 Delete/Backspace 清空全部所选主格；文字、Enter 和组合输入只替换首个主格，保留其余格图片和域。图片删除锁、引用保护和候选失败沿既有原子事务执行。结构操作仍沿原保护。文档默认 Tab 间隔、小数点符号及其他全局设置采用目标文档；源行高及表属性不转移。覆盖已有图片须通过原生删除保护，其他身份或未知源仍拒绝。整格输入与清空依据 [ONLYOFFICE Table.Remove](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L6288-L6335)。

每片段最多 256 张图片，逐图 base64 源最多 2 Mi 单元，解码后的压缩字节合计最多 2 MiB；共享资源的每次引用均计入检查。原生绘图身份分配最多扫描 16384 项，图片字节计入既有历史及输出预算。

片段最多 2 Mi UTF-16 单元、4096 条链接和 4096 个书签，目标书签目录最多 4096 项。编号和抽象定义各最多 4096 项，编号部件仍受片段的源码预算限制。既有 XML 深度、源字节、65536 文字单元、1000 行、63 列、4096 逻辑格及历史/字体/布局/输出预算继续执行。Web 在读 Blob 前另限 4 MiB；TS 不解析 WordML。未知引用、断裂合并、超预算和缺字体均保留原文档及历史。实现归 [`table-fragment-copy.mbt`](../../modules/formats/src/docx/table-fragment-copy.mbt)、[`table-fragment-read.mbt`](../../modules/formats/src/docx/table-fragment-read.mbt)、[`table-fragment-links.mbt`](../../modules/formats/src/docx/table-fragment-links.mbt)、[`table-fragment-bookmarks.mbt`](../../modules/formats/src/docx/table-fragment-bookmarks.mbt)、[`table-fragment-numbering.mbt`](../../modules/formats/src/docx/table-fragment-numbering.mbt)及 [`table-fragment-paste.mbt`](../../modules/formats/src/docx/table-fragment-paste.mbt)。编号资源依据 [ONLYOFFICE 所用编号定义与实例复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Serialize2.js#L4967-L5080)。结构依据 [ONLYOFFICE 所选内容](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L7524-L7748)与上述 `InsertTableContent`；链接复制参考 [ParaHyperlink.Copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Hyperlink.js#L80-L87)，同名书签处理参考 [addBookmarkStart/End](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Serialize2.js#L17511-L17533)，未移植上游可执行代码。

#### 跨格行列与矩形合并

同表跨格选择可使用既有六种行列命令，默认面板与 API 采用相同范围。插入行数等于所选格所属的不同源行数；向上插入复制首个所选行，向下插入复制末个所选行。删除这些源行及其全部内容，包括选区列外的格。纵向延续不重复计数；删除合并起始行后，存活的首个延续格成为新起始格，已删文字不转移。仅含延续的中间行可存活，仍保持正确归属。依据 [ONLYOFFICE 所选行增删](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9997-L10254)。

插入列数等于首个所选源行中的实际所选格数，横向跨度不重复计数。左插使用首个所选格的有效宽度，右插使用末个所选格的有效宽度；边界取全部实际所选格的最左/最右网格边界。新列复制每行相邻格的属性，分别维护纵向归属。删除列按同样的左右边界移除各行相交整格；沿既有公共网格重建、固定总宽、行尾空缺及空行清理规则。依据 [ONLYOFFICE 所选列删除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L10329-L10426)及[插列数量、宽度与边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L10512-L10658)。

跨格 `merge` 的 rows/columns 必须等于选区的逻辑矩形尺寸；默认面板自动填入并锁定这两个数量。已有合并格须完整位于矩形内，切开已有跨度时原子拒绝；内容按源顺序进入左上格。六种行列命令及合并均沿现有源补丁一次提交历史，撤销恢复原字节和正/反向选择，保留未删内容及其他部件。删除最后全部行或列时移除表格并进入正文。源、字体、布局及输出预算继续检查，失败不提交。

跨格 `unmerge` 按实际所选主格取消合并，保持原公共网格；相交的合并格整体处理，范围外合并格及普通格保持原源。每个主格的全部文字留在原格，新格为空并继承对应源行格的框与首段格式。所有修改及布局预检合为一项历史，光标定位首个所选主格；没有合并格时保留原源、范围和 revision。未知格源、无可用文字宽度、字体及预算失败整体拒绝。指定行列拆格支持同一范围，规则归上述 `splitCell` 合同。拆表仍须选择单格，默认面板在跨格时禁用。链接、书签及批注创建沿普通文字范围规则；跨格时链接查询给出原因，默认面板禁用对应创建。部分跨入单元格、跨不同表格端点及未知格内容沿既有保护规则；两端在正文的完整表格范围归[正文富文本片段](#正文富文本片段)；跨格边框/边距的默认面板、嵌套表格和其余结构范围操作继续实施。

### HTML/Markdown 内嵌图片

HTML 的 img/src 和 Markdown 的直接/引用式图片接受 `data:image/png;base64,...` 或 `data:image/jpeg;base64,...`。核心校验 MIME、文件头、像素和尺寸预算，复用原生行内 DrawingML、关系、内容类型及图片部件。保留 alt/title；同片段重复字节共用源部件，绘图身份分别分配。源数据按原压缩字节保存，不重新编码。

默认图片框按 96 dpi 把原始像素换算为点。HTML 的 width/height 属性按像素处理，内联 width/height 支持数值、px、pt，覆盖相同属性；只设一边时保持原始比例，两边都设时使用明确尺寸。百分比、auto、裁剪、变换、浮动和链接内图片尚不在本入口范围；HTTP/file/cid 等来源不请求且明确拒绝。原有行内图片编辑、资源完整性和历史规则继续适用。

`FoundationSession.markupImages(revision, kind, input, mode = "source")` 和异步 `FoundationClient.markupImages` 返回原有 `DocxFragmentImages`：`{ revision, images: [{ key, bytes }] }`。kind 为 html/markdown。查询保留原源、选择、revision 和历史。同步宿主先解码返回的压缩字节，并用原有 `addImage(key, width, height, rgba)` 登记，再调用相同输入/方式的粘贴命令。Web 客户端在需要绘图的方式下自动执行清单、浏览器本地解码、登记及最终粘贴；损坏像素在提交前拒绝，bitmap 总会释放。

源格式和匹配目标格式都保留图片框及资源；纯文本方式保留 alt，省略无 alt 的图片，不创建图片部件。所有方式仍验证图片源及尺寸。每片段最多 256 张，压缩字节累计最多 2 MiB，元数据各最多 1024 个 UTF-16 单元；总输入仍限 65536 单元。单图最多 4096×4096、4194304 像素，解码缓存继续限 16 MiB/256 项。图片框沿原 0.1–14400 pt 范围。实现归[图片输入与预检](../../modules/formats/src/docx/markup-images.mbt)及[共享原生图片构造](../../modules/formats/src/docx/picture-markup.mbt)。尺寸换算参考 [ONLYOFFICE 图片尺寸处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L13583-L13625)，未移植上游可执行代码。

### HTML/Markdown 粘贴方式

两种输入均接受可选 `mode: DocxPasteMode = "source"`，类型从 Wasm/Web 的 `foundation` 导出。默认对话框在 HTML 或 Markdown 输入下显示三种方式：

| mode | 行为 |
| --- | --- |
| `source` | 保留已支持的源字符和段落格式；沿原生正文片段事务写入 |
| `merge` | 使用插入点的有效字体、字号、颜色、字符间距、突出显示及段落格式；保留源强调、上下标、链接、列表编号和标题级别 |
| `text` | 提取文字、图片 alt、Tab、换行及列表标记，表格转为 TSV；清除源格式和链接，沿普通文字替换事务，继承目标和待输入格式 |

匹配格式按范围文档顺序的起点取值，保留光标亲和；反向选择使用同一插入点。目标段落的对齐、方向、间距、缩进、Tab 和分页属性作用于导入段落，源编号/标题结构保留。不要求加载被替换的源字体，但保留的强调仍需目标字体对应资源。

纯文本方式先解释受支持的语法，不把 HTML 标签或 Markdown 标记作为文字。列表标记写为普通文字，段落和硬换行沿普通输入拆段；编号、链接和其他临时候选不写入文档。输入格式直接选“纯文本”时，仍按原输入文字粘贴。三种方式都执行原输入、资源、保护、范围及预算检查，不绕过未知结构限制。

每次粘贴最多一项历史，后续输入独立撤销；错误不改变源、选择或历史。普通系统剪贴板和私有原生片段仍默认保留源格式，方式选择作用于显式 HTML/Markdown 输入。实现归[粘贴方式](../../modules/formats/src/docx/markup-mode.mbt)，原生属性合并参考 [ONLYOFFICE 段落与文字转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L3624-L3710)。

### HTML 粘贴

`FoundationSession`、`FoundationClient` 提供 `pasteHtml(revision, selection, html, profile, mode = "source")`；`DocumentEditor.pasteHtml(html, mode = "source")` 沿现有队列使用当前选择，方式归上节。默认粘贴对话框选择 HTML 后解释输入。普通 Ctrl/Cmd+V 或源格式粘贴先读私有原生片段，再读系统 `text/html`，最后读纯文本；显式单元格矩阵粘贴沿原规则。异步读取期间文档或选择变化时拒绝提交。

核心用固定 html 0.2.1 解析 HTML5，再写入与 Markdown 相同的[正文富文本片段](#正文富文本片段)。支持正文/单格范围替换、div/p、h1–h6、blockquote、pre/code、十进制 ol 起始值/ul、普通 li、span、b/strong、i/em、u、s/strike/del、sup/sub、br、受支持的内嵌 img 和 HTTP/HTTPS/mailto 链接。HTML5 容错由解析库完成；普通 ASCII 空白折叠，NBSP 保留，pre 和指定保留模式写原生 Tab/换行。

仅使用 style、dir、hidden，以及 a 的 href/title、ol 的 start 和 img 的 src/alt/title/width/height。字符格式支持 font-family、pt/px 字号、粗斜体、RGB 颜色、下划线/删除线和上下标；段落支持对齐、方向、标题 outlineLvl、引用及列表缩进。字号换算到原生半点。white-space 支持 normal/nowrap/pre/pre-wrap/break-spaces。display:none、visibility:hidden/collapse 和 hidden 属性移除对应子树。其他属性及未声明 CSS 丢弃，不把 CSS 写入 DOCX。

script/style/head 元数据和 iframe/object/embed/template/noscript 子树全部移除，事件属性不参与转换。核心不执行脚本，也不请求图片、样式、框架或链接。未知元素、未支持图片来源、水平线、SVG/MathML、本地锚点、逆序/逐项改号及不支持的已声明格式明确拒绝；不会回退成纯文本掩盖失败。普通表格归下节，更广 HTML 结构和图片引用形式仍待实施。

源最多 65536 个 UTF-16 单元及 2048 个 `<`；树最多 4096 个节点。转换沿共同的 32 层、512 段落、256 列表、9 级编号和片段/字体/历史/输出预算。格式、关系及编号共用一项事务，失败保留原源、选区和历史；保存重开后继续原生输入。实现归 [HTML 输入](../../modules/formats/src/docx/html-input.mbt)及[内联格式](../../modules/formats/src/docx/html-style.mbt)，参考 [ONLYOFFICE HTML 粘贴入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L12167-L12230)，未移植上游可执行代码。

### HTML 表格

HTML 输入支持 `table`、`caption`、`thead/tbody/tfoot` 行组、`tr`、`td/th` 及 `colgroup/col`。核心将网格写为原生 Word 表格，`rowspan/colspan` 生成纵向延续与列跨度；`rowspan=0` 延续到当前行组末尾，超过行组的跨度截到该边界。缺少的普通格补为空格。`th` 默认粗体和居中，显式字符/段落样式继续覆盖。格内段落、列表、链接及内嵌 PNG/JPEG 沿现有转换与资源事务，禁止嵌套表格。

可见 `thead` 行写为连续的原生 `tblHeader`，复用[重复表头](#重复表头)的跨页布局、合并格、原生编辑及输出。表头排在正文行组之前，`tfoot` 排在正文行组之后，各类行组内部保留源顺序。隐藏行不占表头行数，普通 `th` 不会自动成为重复表头。纯文本按相同可见顺序生成 TSV，不重复输出表头。标志写回参考 [ONLYOFFICE HTML 表头转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L10581-L10607)，多行和跨页沿本项目的原生表格合同。

题注转换为表格前后的普通 Word 段落，保留受支持的富文本、链接、多段内容及原生输入。默认置顶并沿普通段落宽度居中，CSS `text-align` 可覆盖。`caption-side: top/bottom` 支持题注自身设置及表格继承，旧 `align="bottom"` 作为无 CSS 时的底端位置。隐藏题注不输出。源格式的顶端题注通过 `keepNext` 与表格保留分页关系；匹配格式沿目标段落属性，纯文本按可见位置输出一次。默认位置、居中及段落转换参考 [LibreOffice HTML 题注](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/source/filter/html/htmltab.cxx#L4552-L4592)。自动编号与交叉引用仍按[序列编号字段](#序列编号字段)和 P10 引用功能继续实施。

表格 `width` 属性或 CSS 支持数字/px、pt 和大于 0、不超过 100% 的宽度，默认 100% 的可用栏宽。`colgroup/col` 的 `span` 和数字/px/pt 宽度生成原生列宽与合并格宽度，缺省列为 72 pt；列组宽度按子列继承，未声明的余列等宽。表格百分比在实际接收栏位解析，绝对列宽保留比例。单格 `bgcolor/background-color`、`valign/vertical-align` 与 table 的 0–16 px `border` 已接通原生底色、垂直对齐及黑色实线边框。其他 CSS 沿上述白名单处理；百分比列宽、按内容自动估算列宽及更广边框/尺寸继续实施。

源格式和匹配格式保留表格结构，匹配格式将插入点的字符/段落格式应用到各格，保留源强调、编号、链接和表格属性。纯文本按表格位置插入带引号的 TSV，跨列和纵向延续格留空，主格文字仅出现一次。正文可一次粘贴段落与表格；首尾段落与目标文字合并，表格两侧文字各自保留。段首插表不新增前置空段，段前分页随第一格转移。目标在单元格内时，含表格的源/匹配方式拒绝嵌套；纯文本方式仍沿普通输入。

既有正文片段读取和粘贴复用同一路径，允许最多 32 个普通表格、合计 4096 个网格单元，每表最多 1000 行和 63 列；HTML 的 512 段落上限包含各格及纵向延续。图片预检只读，实际像素解码后才提交，正文、编号、链接和媒体合为一项精确历史。未知/重叠网格、字体、布局、保护及预算失败整体拒绝。实现归[HTML 表格](../../modules/formats/src/docx/html-table.mbt)和[正文片段事务](../../modules/formats/src/docx/fragment-paste.mbt)，网格跨度及延续参考 [ONLYOFFICE 表格行转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L11763-L11901)；未移植上游可执行代码。

### Markdown 粘贴

`FoundationSession`、`FoundationClient` 提供 `pasteMarkdown(revision, selection, markdown, profile, mode = "source")`。`DocumentEditor.pasteMarkdown(markdown, mode = "source")` 在现有编辑队列中使用当前选择，沿上述三种粘贴方式。默认粘贴对话框选择 Markdown 后解释输入；原生普通文字粘贴不自动猜测语法。

核心用固定 cmark 0.4.12 解析 CommonMark，转换为[正文富文本片段](#正文富文本片段)，复用格式、编号、链接及源事务。支持普通正文或单个普通格的范围替换、ATX/Setext 标题、粗体/斜体、实体/转义、软换行和硬换行、引用缩进、行内/块代码、有序/无序嵌套列表、续行段落，以及 HTTP/HTTPS/mailto 的直接、引用式和自动链接。标题写原生 outlineLvl 与粗体；代码写 Courier New 和原生 Tab/换行，字体仍由宿主 profile 显式提供。

一次导入合为一项精确历史，保留目标前后文字及其他源部件，保存重开后继续编辑。编号定义、实例、外链和内嵌图片关系沿原片段事务分配身份；不访问链接。图片范围归上述[内嵌图片](#htmlmarkdown-内嵌图片)。Markdown 内嵌 HTML、外链图片、本地锚点及水平线明确拒绝，不静默丢弃。扩展语法按普通 CommonMark 文字解释，不声明 GFM 表格、删除线、任务框、数学或脚注导入。独立 HTML 入口归[HTML 粘贴](#html-粘贴)；Markdown 内嵌 HTML 及更广交换结构仍待实施。

源文本最多 65536 个 UTF-16 单元；解析前限制 `[]()*_>` 及反引号共 1024 个。转换树最多 4096 个节点、32 层、512 个段落、256 个列表及 9 级编号；生成片段仍受原 XML、资源、字体、历史和输出预算限制。未知内容、缺字体、旧 revision、保护及预算失败均不提交源变化。实现归[Markdown 输入](../../modules/formats/src/docx/markdown-input.mbt)。格式转换参考 [ONLYOFFICE 粘贴段落与文本](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L12167-L12230)，未移植上游可执行代码。

### 正文富文本片段

正文浮动图片和基础图形随原生锚点转移。复制保留两轴基准、偏移/对齐、层次、环绕侧向与四边间距；粘贴把逻辑锚点放入目标段落，按目标页面与段落布局解析。图形保留原生矢量，图片沿原压缩字节预检、解码和资源事务执行。

每次粘贴分别分配绘图身份。已携带的 `wp14:anchorId/editId` 须为八位十六进制值，核心为副本重分配未用值，避开主文档及声明的页眉/页脚身份。源与目标已有元数据、注释和非目标部件保持。未知元数据、引用及复制锁继续拒绝；删除锁阻止剪切和删除。浮动片段要求正文目标，粘入单元格原子拒绝。范围替换、资源与新锚点合为一项精确历史，重复粘贴生成独立对象。行为参考 [ONLYOFFICE ParaDrawing.Copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/ParaDrawing.js#L1361-L1407)。

`FoundationSession.clipboard(revision, selection, cut = false)` 和异步 `FoundationClient.clipboard` 返回 `DocxClipboard`：`{ kind: "body" | "cells", text, fragment, reason, selection }`。普通正文和同一单元格中的文字范围可截取部分字符及跨段落内容；跨格整格范围沿既有矩形片段。查询保持源、选择和历史。不能转移的已知内容返回纯文本及原因，图片和域的剪切须成功生成富文本并通过原生删除保护。

两端都在普通正文段落时，范围可以完整包住中间的普通表格。复制按正文块顺序生成原生片段；正文和格内内容共用编号及书签身份，保留合并网格、原生表宽/对齐/边框/默认边距、行高/重复表头/跨页策略、字符格式、链接、简单域和行内图片。纯文本使用 LF 分隔正文块，表格按带引号 TSV 输出，合并续格留空。剪切、普通替换、输入法候选和范围格式复用同一结构校验与事务，首尾未选文字保留；取消和撤销恢复原字节。默认选择、Copy/Cut、源格式粘贴、格内继续输入、重开及 PDF 已检查。依据 [ONLYOFFICE 所选正文块遍历](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/DocumentContent.js#L4810-L4835)。部分跨入格内、嵌套表格及未知结构继续拒绝。表样式资源尚未随整表转移；带这些引用的富文本捕获给出原因，不丢弃引用后生成片段。

正文片段携带解析后的字符/段落格式、完整普通书签、链接、编号、行内/浮动 PNG/JPEG 及基础图形。资源校验和目标身份分配复用[单元格富文本片段](#单元格富文本片段)。`bodyFragmentImages(revision, fragment)` 只读预检图片；同步宿主先解码并注册 RGBA。`pasteBodyFragment(revision, selection, fragment, profile)` 原子替换范围；Web 自动解码，`DocumentEditor.pasteFragment(fragment)` 沿既有编辑队列提交。字体、布局、资源、历史或输出失败保留原文档。

简单 `PAGE`、`NUMPAGES` 域也随正文片段转移，保留指令、显式编号格式及已解析的字符格式。纯文本输出取当前完整布局的实际结果，长度变化不改变用于剪切的逻辑范围；缺少、过时或不完整布局时拒绝读取所选域，不退回旧缓存。同步和 Worker 桥使用当前布局，调用方先完成相同 revision 的排版；MoonBit `selected_text`、`clipboard` 可显式传入 `layout`。粘贴按目标位置重算新域缓存，保留已有域的旧缓存，并与文字及资源合为一项历史。空结果域仍携带富文本片段，不视为空选择。整格/跨格及完整合并格中的简单域复用相同规则，范围归[单元格富文本片段](#单元格富文本片段)。依据 [ONLYOFFICE 原生简单域序列化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Serialize2.js#L5513-L5528)，实现归[域剪贴板值与格式](../../modules/formats/src/docx/field-clipboard.mbt)。

单段粘贴保留目标段落属性，源字符格式随文字插入。多段粘贴使用源段落属性，保留目标前后文字的字符格式；最后一个部分段落当前也使用源段落属性。光标停在插入末尾，继续输入继承源字符格式。文字、资源、选择和所有段落合为一项精确历史。

默认 Copy/Cut 与原生快捷键携带 `text/plain` 及 Chromium 自定义类型 `web application/x-open-document-docx-body`。写入成功且文档、revision、选择仍一致时才剪切。默认粘贴面板的“保留源格式粘贴”、Ctrl/Cmd+V 和导出的 `pasteDocxSelection(editor)` 优先读取正文片段，其次读取单元格片段，缺少原生类型时粘贴纯文本。无效原生片段拒绝，读取期间目标变化保留文档。`paste(text)` 及原生普通 paste 事件继续采用纯文本路径。

最多 1024 个正文块、65536 文字单元；表格读取和粘贴另沿用[HTML 表格](#html-表格)的数量与网格预算。片段、图片、链接、书签及编号采用上述共享预算，Web 读取 Blob 前限 4 MiB。域另沿用每段 64 个及正文布局 4096 个位置的上限。跨不同表格端点、部分跨入格内、批注/修订/复杂域及部分书签转移继续实施；HTML/Markdown 输入范围归各自章节。实现归 [`fragment-copy.mbt`](../../modules/formats/src/docx/fragment-copy.mbt)、[`fragment-import.mbt`](../../modules/formats/src/docx/fragment-import.mbt) 和 [`fragment-paste.mbt`](../../modules/formats/src/docx/fragment-paste.mbt)。段落拆分和首尾合并参考 [ONLYOFFICE SelectedContent](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/SelectedContent.js#L1021-L1198)，未复制上游执行代码。

### 表格尺寸

`editTable({ action: "tableWidth", value })` 设置当前格所在表的总宽度，单位为 pt。核心按原列宽比例分配整数 twip，精确保持目标总宽，同步 `tblW`、列网格和全部格的 `tcW`；横向合并按跨度求宽，纵向合并起始/延续关系和文字保持。最多 63 个逻辑列，各列至少 12 pt，格内边距须留出文字宽度，总宽不超过当前页的可用宽度。未修改的样式、边框、对齐、段落和其他部件保留。比例规则参考 [ONLYOFFICE 网格缩放](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L413-L429)。

`editTable({ action: "columnWidth", column, value })` 设置同表内指定逻辑列的宽度，column 从 0 开始，须小于当前列数。value 为 12–14400 pt 的整数 twip，整表仍须位于可用页宽内。其他列宽度保持，表格总宽随目标列增减；横向合并的格宽按所跨列求和，纵向延续节点一起更新。共享整表宽度的网格/属性序列化、保护、边距及半描边宽度预检、源历史和保存。规则参考 [ONLYOFFICE 列宽设置与网格重建](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L19008-L19039)；本 API 用逻辑列索引明确定位合并格覆盖的各列。默认 UI 显示从 1 开始的列号及对应宽度。

`editTable({ action: "rowHeight", value, rule })` 设置当前行或跨格选择覆盖的实际源行高度。`rule` 必须为 `atLeast` 或 `exact`，写入相应的 `trHeight hRule`。`atLeast` 允许内容撑高，值为 0 时删除行高属性并恢复自动；`exact` 固定行高并裁剪溢出，完整文字及逻辑位置仍保留。精确值另加同行最大上下边距，包含上边框，最小可见行距为一个 twip。纵向合并以末行模式决定是否允许内容撑高；末行为精确高度时裁剪到整个合并格。预览和 PDF 使用同一裁剪，光标及选区限制在格内，垂直移动跳过完全隐藏的行。重复表头保留相同裁剪。规则参考 [ONLYOFFICE 精确行高与边距](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L2660-L2700)、[内容裁剪](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L2775-L2900)及[合并格末行](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L3150-L3162)。尺寸须有限、非负、不超过 14400 pt，且为整数 twip；表宽须大于 0。核心保留合并行组的一页边界，拒绝超出可用页高的尺寸。

`queryFormatting(...).table` 在支持的表格上下文中返回 `{ id, autoFit, row, rows, column, columns, columnWidths, headerRows, width, rowHeight, rowHeightRule, align, tableMargins, tableBorders, cellFill, cellVerticalAlign, cellMargins, cellBorders, maxWidth, maxRowHeight }`，否则为 null。`id` 为当前表节点身份，`row` 从 0 开始，`columns` 为逻辑列数；`column` 为当前格左侧的逻辑列索引，`columnWidths` 为全部逻辑列宽（pt）；`width` 是列网格总宽，`rowHeight` 是源高度值，`rowHeightRule` 为 `atLeast` 或 `exact`；自动高度返回 `0/atLeast`。这些值均非浏览器测量。`DocxFlow.tables[].exactHeights` 按行携带精确模式。`align` 为整表的 `left`、`center` 或 `right`；`tableMargins` 是表格默认单元格边距，尚未叠加单格覆盖。`cellFill` 为当前格的六位 RGB 底色，无底色时为 null；`cellVerticalAlign` 为有效的 `top`、`center` 或 `bottom`；`cellMargins` 为该格有效的 `{ top, right, bottom, left }`。两类边距均以 pt 表示。默认 UI 读取同一查询，提交后反映实际属性；文档、所选段落或 revision 变化会重置未提交的属性输入。

尺寸操作保留逻辑选区和当前光标处的待输入格式，重排后清除旧布局定位提示，沿已有队列、源历史、保存重开和 PDF。无源变化不增加历史；未知行/格映射、网格标记、属性或预算失败原子拒绝。缺少的尺寸属性按 OOXML 顺序创建；恢复自动高度保留其他行属性，并重新显示被裁剪文字。其余格属性仍归 [P10](../p10-docx-core.md)。

### 表格边框

`editTable({ action: "tableBorders" | "cellBorders", value })` 修改整表默认边框或当前逻辑格的直接边框。`value` 为非空部分属性集：四边使用 `top/right/bottom/left`，整表另支持 `insideH/insideV`。每边 `{ width, color }` 设置实线，`width: 0` 显式关闭，null 删除该边直接属性并恢复继承；省略的边保持。非零线宽为 0.25–12 pt，须为 1/8 pt 的整数倍；color 为六位 RGB。默认 UI 提供表格/当前格、各边/全部、线宽、颜色、移除及恢复继承。纵向合并起始与延续节点共同修改，内部合并边不绘制。

核心沿表格样式链与直接属性求有效值。单元格声明优先于表格默认；相邻单元格先取非空边，再取较宽实线，同宽按 RGB 亮度规则求值。规则依据 [ONLYOFFICE 边框冲突](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L15267-L15342)。当前读取 `single/nil/none`、RGB/auto 和左右的 start/end 别名；auto 为黑色。主题边框、虚线、双线、阴影、非零间隔和未知属性继续保护，不覆盖不理解的源内容。

`queryFormatting(...).table.tableBorders` 返回六边的默认值，`cellBorders` 返回当前格四边的实际冲突结果；合并格某边包含不同线段时该边为 null，表示混合。`DocxFlow.tables[].borders` 为核心生成的 horizontal/vertical 网格，替代旧布尔值。边宽参与行高与分页预留，左右边界至少预留半个描边宽度。分页缓存、重复表头、Canvas 和 PDF 消费相同线段及颜色，Web 不重算边框。

属性沿现有单项源历史保存，保留文字、网格、选区、待输入格式和其他部件。无变化保留源片段及 revision；无文字宽度、未知目标、旧 revision、输出或历史预算失败原子拒绝。合并仍沿当前[结构规则](#表格创建)保留每行首格属性，取消合并复制相应格属性；跨格属性修改归[跨单元格属性选择](#跨单元格属性选择)，复杂边框仍归 P10/P14。实现归 [`table-borders.mbt`](../../modules/formats/src/docx/table-borders.mbt)、[`table-border-editing.mbt`](../../modules/formats/src/docx/table-border-editing.mbt)及[公共边框绘制](../../modules/layout/src/table-borders.mbt)。

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

缺省 `tblLayout` 按自动模式读取；表样式和直接 `tblPr` 决定模式及表宽，直接属性优先。偏好宽度使用 `{ value, percent }`：dxa 转为点值并设 `percent: false`，pct 的 0–5000 转为 0–1 并设 `percent: true`，在表格实际落栏时解析；auto/nil 使用零点值表示未指定。公共 `Table` 携带 `autoFit/preferredWidth/preferredWidths`，布局层使用授权字体的相同塑形结果求字素、单词和不换行宽度，再合入边距、半描边、行内图片、缩进、列表和制表位置。单列约束先求，合并格不足部分按源网格比例分配；不足以容纳最小单词时向字素下限收缩，字素或图片仍放不下则拒绝。列宽最终落在整数 twip，受可用页宽及既有资源上限约束。规则参考 [ONLYOFFICE 自动表格宽度](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L448-L648)及[合并格约束](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableRecalculate.js#L864-L1050)。

低层 `FoundationSession/Client.editTable` 的第 4 个参数为字体 profile，测量操作必须提供所需映射；`DocumentEditor` 自动传入宿主 profile，图片沿已提供资源预检。`queryFormatting(...).table.autoFit` 返回当前模式。自动模式中的 `width/columnWidths` 为保存的回退网格，有效宽度来自布局；默认 UI 显示自动状态，并在冻结后开放手动宽度输入。程序化整表/单列宽度修改也会先测量并转为固定模式；目标列至少 12 pt，已有其他窄列保持。Canvas、命中、选择、缓存和 PDF 共用有效网格。未知属性/保留标记、缺字体/字形、无法排版或预算失败不提交。嵌套/浮动表格和更广宽度类型继续按原保护范围处理。

### 表格行跨页

`editTable({ action: "rowSplit", value })` 设置当前格所在行或跨格选区端点覆盖的实际源行是否允许拆分，`value` 必须为布尔值。核心写入 `cantSplit val="0"/"1"`，有效值相同时保留源及 revision。`queryFormatting(...).table.rowSplit` 和 `DocxFlow.tables[].splitRows` 返回有效设置，包含表格样式链继承，缺省允许拆分。跨格选择通过 `cellSelection.value.rowSplit` 返回 `{ kind: "value", value: boolean }` 或 `{ kind: "mixed" }`。默认 UI 提供单行及跨格复选框，混合时半选；所有目标合为一项历史，保留原选择和范围外行。结构操作保留并复制已有行属性；开关、文字、选择和待输入格式沿现有事务及精确历史恢复。

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
| `layer` | opacity 为 0–1，commands 在独立透明表面绘制后整体合成；子内容重叠不重复应用整层透明度 |

隔离层最多嵌套四级，共享原指令/资源预算；子裁剪在层内平衡。单次绘制的目标与活动临时层合计最多 16777216 像素。Web 复用同尺寸临时表面，在不再使用、尺寸变化或释放时清理；图层不包含格式规则。

核心 `PositionedDocument.drawing(images)` 默认填充白底。`clear=false` 为透明对象层生成图元，仍保留页面裁剪；它不改变布局或源文档。

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

### DOCX HTML 与 Markdown

核心 `Session.export_markup(revision, format, output_bytes)` 与同步/异步 `FoundationSession/Client.exportMarkup(revision, format, outputBytes = 67108864)` 返回 UTF-8 字节。`format` 为 `html` 或 `markdown`。Web `DocumentEditor.exportHtml/exportMarkdown(outputBytes = 67108864)` 沿既有输出屏障返回 `EditorOutput`，绑定文档身份与修订。默认文件菜单输出原基名的 `.html`/`.md`，复用 `onSave` 或浏览器下载；导出不改变源、选择、历史和 DOCX 保存基线。

正文与普通表格按源顺序输出，保留逻辑文字、空段落、Tab/换行、前六级标题、粗斜体、下划线、删除线、上下标、内外链接、提示及书签锚点。HTML 使用解析后的字体、字号、颜色、高亮、背景、段距、缩进、方向与对齐；表格携带网格列宽、合并跨度、表头、底色、边距和共同边线。列表使用原生 `ol/ul/li`、`start/value` 和 `aria-level`，保留多级嵌套、实际起点、续号与重启。计数复用核心编号规则；正文和各单元格分别关闭列表容器，跨区域的计数仍连续。空项保留行高，标记与正文各自使用有效格式；RTL 列表使用逻辑起始边缩进。简单标签使用原生 HTML 计数器；复杂标签、装饰、超过 z 的 Word 字母序列及超出浏览器罗马计数范围的标签，使用已计算样式文字保留外观，同时保留列表结构与实际数值。

行内 PNG/JPEG 内嵌原始压缩字节，保留替代文字、显示尺寸及裁剪；复制锁、外链或未知图片沿原保护。Markdown 使用原生标题、转义文字、硬换行及普通十进制/圆点列表。子项和续行按父项标记宽度缩进，保留非 1 起点、空项和中断后的续号。编号实例切换、特殊标签、超过九位的序号、跳级或 RTL 无法直接表达时，使用嵌套 HTML 列表；字符装饰、链接、图片及表格也使用内嵌 HTML，读取器须允许这些 HTML。HTML 列表片段及表格保留源背景，避免自动白色文字落在默认白底。普通 Markdown 段落不携带字体、颜色和页面几何；导出后的自动换行由读取器决定。分页/分栏断点转为换行；页面边框、分页约束及制表对齐不转移。

含页眉页脚、批注、待处理修订、字段或布局不支持内容时明确拒绝。合并格边线不统一时也拒绝。未知资源、非法链接、活动候选、旧 revision 及超限保留原包。文字、属性和 CSS 字符串分别转义；链接沿既有 HTTP/HTTPS/mailto/书签白名单，不输出脚本、事件、外链图片或外部样式。默认上限 64 MiB，并取原会话输出预算的较小值；UTF-16 中间结果和最终 UTF-8 字节分别检查，图片编码前预检剩余预算。Web 输出失败后可继续原生编辑。

实现归 [`markup-output.mbt`](../../modules/formats/src/docx/markup-output.mbt)及 [`markup-lists.mbt`](../../modules/formats/src/docx/markup-lists.mbt)。列表嵌套与续号参考 [ONLYOFFICE 列表栈](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L858-L951)，实际数值沿本项目共享的 `NumberCounter.advance`。标题和普通段落转换参考 [ONLYOFFICE CopyParagraph](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L728-L858)，合并格参考 [CopyCell](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/wordcopypaste.js#L1035-L1066)。未复制上游执行代码。更广区域和 HTML/Markdown 导入继续实施。

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

上述策略结合 [ONLYOFFICE 普通段距与特殊分支](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L10805-L10860)、[LibreOffice 布局分支](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/source/core/layout/flowfrm.cxx#L1582-L1770) 与固定引擎结果；不是完整 Word 间距规则。`contextualSpacing` 的支持范围归 [P10 当前格式编辑](#p10-当前格式编辑)。自动段距、按行指定的段距及上述范围外的编号仍不支持，直接格式和实际应用的默认值、样式链都会报告部件与特性，例如 `unsupported-layout:word/styles.xml:w:vanish`。未使用的命名样式不产生诊断。原始内容照常保留，应用不能把带诊断的结果称为保真布局。

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

### 工作表保护

`editSheet({ action: "protection", enabled, password? })` 启用或解除当前工作表保护。同步 Wasm、Worker 和编辑宿主复用同一入口；宿主先提交已接受的原生草稿。`password` 省略或为空串时创建无密码保护，否则使用原字符串，不裁剪或归一化。密码最多 255 个 UTF-16 单元，须为有效 XML 文字。已保护表须先解除，才能更改密码；解除未保护表不增加历史。

新密码使用标准 `SHA-512`、16 字节安全随机盐及 100000 次迭代。平台通过 Web Crypto 提供盐，MoonBit 计算散列，写入 `algorithmName/hashValue/saltValue/spinCount`，不把明文密码写入源、历史或查询。解除支持 SHA-512 与旧式 `password` 摘要；旧式摘要只用于导入验证，不用于新建密码。SHA-512 输入盐限 1–64 字节，摘要为 64 字节，迭代接受 0–1000000；编码属性先检查长度。未知算法、混合或残缺凭据、超限与未知保护元数据明确拒绝。

`XlsxQuery.protection` 返回 `{ protected, passwordRequired, reason }`，Wasm/Web 导出 `XlsxProtection`。`reason` 说明当前保护改写限制，不包含密码或散列。默认 UI 显示状态，提供密码输入和新密码确认；操作结束后清空输入。工作表保护限制编辑，不加密文件内容。新保护使用标准默认操作权限，保留选择锁定和未锁定格；细分操作授权及选择限制创作仍待实现。

保护节点按工作表标准顺序插入或移除，沿既有有界源事务与精确历史。错误密码、无效输入、旧 revision 和输出失败保留文档、选择及历史；锁定格、未锁定格、隐藏公式与重算规则见下文。节点内注释、处理指令或未知文字阻止保护改写，保留原内容。默认无密码保护、错误密码恢复、保存重开、混合历史与 PDF 已检查。[工作簿结构保护](#工作簿结构保护)见下节，授权区域及其他密码算法继续实施。

实现归 [`protection-edit.mbt`](../../modules/formats/src/xlsx/protection-edit.mbt)和 [`protection-password.mbt`](../../modules/formats/src/xlsx/protection-password.mbt)。复用固定版本 `moonbitlang/x` 的 SHA-512，无新增依赖。标准凭据及旧式摘要参考 [ONLYOFFICE 保护入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookProtection.js#L521-L531)、[默认盐与迭代](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/editorscommon.js#L14917-L14919)、[写保护散列](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OfficeCryptReader/source/CryptTransform.cpp#L905-L928)及[旧式密码摘要](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookProtection.js#L132-L147)。未复制上游执行代码。

### 工作簿结构保护

`editSheet({ action: "workbookProtection", enabled, password? })` 启用或解除整本工作簿的结构保护。入口沿现有 `editSheet` 传递表身份；操作作用于工作簿，保留活动表、选区、表身份及原有资源。保护期间，新增、复制、删除、移动、改名、隐藏和显示工作表由核心拒绝，默认管理控件按 `sheetEditReason/sheetRenameReason` 禁用。单元格内容、格式、行列和工作表保护继续遵守各自规则，不把结构保护当作整本只读。

`XlsxQuery.workbookProtection` 使用同一 `XlsxProtection` 类型，返回 `{ protected, passwordRequired, reason }`。`protected` 表示 `lockStructure`，与 `sheets[].protected` 的工作表保护分开；`reason` 是保护设置改写限制。默认 UI 提供独立状态、密码和确认表单，操作后清空输入。错误密码及预算失败不提交修改；解除未保护的工作簿不新增历史。关闭状态的标准保护节点可重新启用。

新密码复用上述长度、随机盐、SHA-512 与迭代预算，保存为原生 `workbookAlgorithmName/workbookHashValue/workbookSaltValue/workbookSpinCount`。旧式 `workbookPassword` 摘要可用于解除导入保护；无密码保护可直接解除。保护节点按工作簿标准顺序插入或移除，单次保护改写只修改 workbook 部件；内容编辑、保护与结构操作可精确混合撤销，保存重开后权限仍有效。

未知保护属性、节点文字/注释/处理指令、活动窗口/修订保护及修订凭据继续保护原源；当前只改工作簿结构保护。其他密码算法与细分工作表授权仍待实现。核心、默认 UI、独立散列/原生 XML、失败保持、保存重开及 PDF 已检查。保护限制编辑，不加密文件内容。

实现归 [`workbook-protection.mbt`](../../modules/formats/src/xlsx/workbook-protection.mbt)，密码算法复用 [`protection-password.mbt`](../../modules/formats/src/xlsx/protection-password.mbt)。字段和行为参考 [ONLYOFFICE 工作簿保护模型](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookProtection.js#L588-L610)、[凭据字段](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookProtection.js#L687-L696)及[结构保护入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookProtection.js#L826-L839)。未复制上游执行代码。

### 受保护工作表的单元格输入

导入的 `sheetProtection sheet="1"` 工作表按有效 `locked` 格式判断输入权限。默认格锁定；显式单元格样式优先于行样式和列样式，基础 `cellStyleXfs` 及 `applyProtection` 沿既有样式继承解析。条件格式只改变显示，不授予编辑权限。查询和视口的每格 `readOnlyReason` 使用同一判断，默认原生输入随活动格更新。

`formatCells({ locked?, formulaHidden? })` 设置普通矩形单元格的锁定和公式隐藏格式。两项均为布尔值，省略时保留有效值；修改其中一项时保留另一项的基础样式继承结果，不激活原本被 `applyProtection="0"` 忽略的局部值。核心派生 `cellXfs`，写入标准 `protection` 和 `applyProtection="1"`；保留值、公式、其他样式及无关部件。`formatting.locked/formulaHidden` 返回共同布尔值或混合态 null；默认格式面板提供保留/开/关及生效提示。设置仅在工作表启用保护时生效，当前受保护表仍拒绝格式修改。未知保护元数据和输出预算失败保留原源。

格式刷和结构化复制/粘贴的完整格式携带这两项属性，沿既有矩形、合并及精确历史规则转移。完整复制格式必须包含两项；普通格式补丁仍可省略。条件格式和自定义表样式不接受保护属性，不把显示规则当作权限。行为参考 [ONLYOFFICE 单元格保护入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/api.js#L6506-L6514)及[范围格式写入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L19768-L19809)，实现复用 [`style-derive.mbt`](../../modules/formats/src/xlsx/style-derive.mbt)和既有格式事务。

未锁定格可输入、清除内容、粘贴 TSV、选择验证列表和替换查找结果。混合范围含锁定格时整项拒绝，不提交部分内容或历史；数据验证、富文本和未知单元格结构继续沿原保护。输入引起的锁定公式缓存重算仍允许，公式源及原有保护设置保持。每项成功编辑共用既有精确历史、保存、重开与 PDF 路径。隐藏公式不出现在输入源码或公式查找结果中，无论该格是否锁定。

工作簿只读原因优先；未知工作表保护属性、子节点、根扩展、授权区域 `protectedRanges` 或选择限制继续阻止受保护表的输入。内容输入保留原密码凭据；启用、解除和凭据校验归[工作表保护](#工作表保护)。格式、结构及其他尚未接通的授权操作仍受工作表保护限制。内容输入复用 `replace`、`paste`、`clear`、`replaceMatches` 和验证选择入口。

权限判断归 [`sheet-protection.mbt`](../../modules/formats/src/xlsx/sheet-protection.mbt)，所有内容事务在 [`cell-transaction.mbt`](../../modules/formats/src/xlsx/cell-transaction.mbt)复查原始目标。行为参考 [ONLYOFFICE 受保护范围编辑](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L27030-L27104)和[范围锁定判断](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L13956-L14052)。未复制上游执行代码。

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

`sheetRenameReason`、`sheetCopyReason` 和 `sheetDeleteReason` 分别说明改名、复制和删除的资源保护原因。默认按钮使用对应字段；最后一张可见表、名称合法性和容量等条件仍由各命令检查。普通图表已有工作表改名、复制和删除时的引用维护。

`{ action: "rename", name }` 修改表名，保持 OPC 路径、sheetId、关系、顺序、可见性及选区。名称为 1–31 个 UTF-16 单元，须是有效 XML 文本，不能含控制字符或 `[]:*?/\`，不能以单引号开头或结尾，不能与其他表名大小写不敏感地重复。相同名称不新增历史；无效名称、旧 revision 或预算失败不修改文档。

核心复用公式词法分析，仅替换 `!` 前匹配旧名称的标记。新引用使用单引号包围名称，并转义名称内的单引号。更新范围包括单元格公式、定义名称、既有条件格式/数据验证公式和内部超链接 `location`；带关系 ID 的外部链接保留其目标内位置。字符串常量、共享公式组与源格式保持不变；事务重建计算并沿既有计算元数据规则保存，撤销恢复原部件字节。规则呈现与编辑范围分别归[条件格式](#条件格式)和[数据验证](#数据验证)。

`{ action: "delete" }` 删除指定表，至少保留一张可见表。删除活动表时优先选择右侧可见表，再向左查找，定位 A1；删除其他表保留活动表与范围。同步剩余名称的 `localSheetId`、工作簿窗口及工作表视图；移除被删表的局部名称。将指向该表的已支持单元格/区域引用整体替换为 `#REF!`，覆盖单元格公式、保留的定义名称和既有条件格式/数据验证公式；移除指向它的内部超链接，保留外部链接及字符串常量。共享公式组继续保存为共享组，失去目标的错误参与依赖计算和缓存写回。核心现可解析七种标准公式错误常量，保留错误传播和 IF 的按需求值规则。引用错误在网格和 PDF 中使用同一结果。

`{ action: "copy" }` 在目标表后复制，分配新的 sheetId、部件及关系身份。名称从 `原名 (1)` 起避让重名，长度不超过 31 个 UTF-16 单元且不切断代理对。副本保留内容、格式、尺寸和可见性，更新自身显式引用与复制的局部名称；其他表的引用及字符串常量不变。已有普通便笺及对应 VML 复制为独立部件，清除副本的可选 guid/shapeId，源便笺不变；外部链接只保留地址。可见副本激活 A1，隐藏副本保留当前选择。副本部件和元数据使用同一有界历史，失败不修改文档。[结构化表](#结构化表与引用)和[普通图片](#工作表图片)同时建立各自独立部件；复杂绘图、非便笺 VML、线程批注及未知身份扩展仍受保护。便笺范围归[单元格便笺](#单元格便笺)。

删除移除工作表 XML、其关系、失效 calcChain 及其关系，以及独占的普通便笺 XML/VML、结构化表和普通图片绘图 XML/关系，更新工作簿关系和内容类型。其余源资源及可能共享的图片字节保留，不回收共享字符串条目或重排字符串索引；保存更新使用计数并沿现有规则标记重算。删除部件快照、引用、缓存和选择共同提交一项有界历史，可与新增、输入和改名精确混合撤销/重做；损坏回放或预算失败保留已提交文档。选择与错误引用规则参考 [ONLYOFFICE 删除工作表](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L4122-L4188)和[引用转换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L10419-L10455)。

`XlsxQuery.sheetRenameReason` 包含结构保护原因，并保护尚未接入引用更新的工作簿/工作表资源关系、未知工作表内容、非空扩展及非普通/共享公式组。复制和删除通过各自查询字段返回引用保护；复制另保护未知身份属性，删除另拒绝未知的部件入站引用。默认 UI 显示原因，提供名称输入、复制、改名与删除入口，并禁用最后可见表的删除。更广资源及引用处理仍归 [P11](../p11-xlsx-core.md)。

`{ action: "rowHeight" | "columnWidth", first, last, size }` 设置包含两端的行或列范围，索引从 1 开始。行高为 0–409.5 磅，一次最多 4096 行；列宽为 0–255 个 OOXML 字符宽度单位，列索引上限为 16384。零值隐藏并保留已有尺寸；正值设置固定尺寸并显示目标行列，列宽同时取消 bestFit。列宽由核心按 Normal 字体和字号的最大数字宽度换算为实际几何。设置行高可创建空行记录，不展开空单元格；拆分列区间保留各段的样式与轮廓属性。目标列包含未知属性或子元素时拒绝修改，保留源内容。

`XlsxQuery.dimensions` 返回查询范围的 `rowHeight`、`columnWidth` 和 `readOnlyReason`。尺寸不一致时返回 `null`，隐藏行列按 0 参与查询。默认 UI 对所选行/列设置尺寸。未知公式仍沿现有只读边界，受保护工作表拒绝尺寸修改；仅锁定工作簿结构不禁止该操作。一次修改进入既有历史，保持表身份和选区；重复设置相同源状态不增加历史。保存保留单元格源、公式缓存、共享字符串计数和 calcChain；实际单元格或公式变化继续触发原有计算元数据更新。自动适配及持续更新见下节；未编辑导入默认行的首次测量仍归 [P11](../p11-xlsx-core.md)。

### 行列插入与删除

`editSheet({ action: "insertRows" | "deleteRows" | "insertColumns" | "deleteColumns", first, count })` 操作整行或整列。first 从 1 开始；插入发生在该索引前，删除覆盖从 first 开始的 count 项。count 为 1–4096，区间须位于 1048576 行或 16384 列内。默认 UI 根据当前矩形选区确定行/列区间，先提交已接受的原生草稿。核心遍历实际单元格和区间，不展开整张空表。

核心沿既有词法位置重写受影响的 A1 引用，保留字符串、非目标表的本地引用和范围外源片段。绝对标记只限制复制平移，行列结构变化仍移动绝对引用。相交区域扩展或缩短，全部失去目标则写入 `#REF!`；共享公式涉及结构变化时有界展开为普通公式。名称、打印区域/标题、合并、行列尺寸、冻结边界、滚动/选择位置、既有条件格式/验证范围及公式、内部链接同步更新。删除规则锚点时，先定位存活格原本使用的相对公式，再应用结构变换。完整删除的打印名称或规则移除，普通失效名称保留引用错误。

插入复制上方行或左侧列的已有尺寸与字符/单元格格式，清空新增格的值和公式，并显示新增行列；新增列取消 bestFit。首行/首列无前项时使用缺省格式。单元格、引用、计算缓存和选区合为一次源历史；撤销恢复精确包，保存重开可继续输入和输出 PDF。自动轴沿原有字体与工作量预算更新。规则依据 [ONLYOFFICE 行插入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L8313-L8369)及[列插入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L8473-L8554)。实现归 [`axis-edit.mbt`](../../modules/formats/src/xlsx/axis-edit.mbt)、[`axis-reference.mbt`](../../modules/formats/src/xlsx/axis-reference.mbt)、[`axis-cells.mbt`](../../modules/formats/src/xlsx/axis-cells.mbt)与 [`axis-metadata.mbt`](../../modules/formats/src/xlsx/axis-metadata.mbt)。

普通值、自定义、数值排名及平均值筛选随整行/整列插删同步。范围前插入移动整个筛选，范围内插入扩展矩形并重新匹配新增空行；删除缩短矩形，删除的条件列和按钮标记一起移除。手动隐藏及筛选隐藏来源随行移动；删除标题后，首个存活行成为标题并清除其筛选隐藏来源。失去全部列或数据行时移除筛选，仅保留存活的手动隐藏。嵌套标准排序范围和键沿既有结构变换维护。候选公式重算后重新应用条件，再更新 SUBTOTAL 缓存，与源和选区合为一次精确历史；范围后的操作保留既有筛选源及隐藏状态。变换后的矩形继续受 4096 格上限约束，插入不得裁掉工作表边缘的筛选端点。规则参考 [ONLYOFFICE 列筛选变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/AutoFilters.js#L2115-L2215)和[行筛选变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/AutoFilters.js#L2326-L2395)，实现归 [`filter-axis.mbt`](../../modules/formats/src/xlsx/filter-axis.mbt)。

插入会推掉实际源行、单元格或便笺时拒绝。[传统便笺](#单元格便笺)、[结构化表](#结构化表与引用)和[普通图片](#工作表图片)沿各自合同维护归属。工作表保护、未知公式/引用/属性、非空扩展、未知筛选、未知绘图、线程批注及未知便笺资源继续保护，保留文档与历史；仅锁定工作簿结构不禁止行列插删。筛选表的局部单元格移位仍受保护。四向单元格移位插删见下节；其余引用资源按 [P11](../p11-xlsx-core.md) 继续接入。

### 单元格移位插入与删除

`editSheet({ action: "insertCells", range, direction })` 支持 `down/right`；`deleteCells` 支持 `up/left`。`range` 为当前目标表中的一个 A1 矩形，最多 4096 格；已有 `sheet` 参数可指定表。上下移位只作用于该矩形的列带，左右移位只作用于其行带；数量为所选高度或宽度。默认 UI 使用现有选区并先提交已接受的原生草稿，成功后保持该矩形选择。插入格只复制上侧或左侧的有效格式，不复制内容；到达首行/首列时使用默认格式。

事务移动稀疏单元格源，保留值、公式、富文本和有效格式；移入另一行/列后仍使用原有效单元格样式。新源片段保留命名空间，原行属性与格间注释继续保留。固定行高、列宽、隐藏/轮廓及冻结分割保持坐标；普通自动尺寸继续沿已有内容重排事务更新。实际数据会被推出工作表边缘时原子拒绝，格式、生成源、输出与历史继续受既有预算约束。

普通/共享公式、跨表引用、绝对标记、定义名称、内部链接、已支持合并区域、有效范围和计算缓存共用一次源历史。相交共享公式有界展开。单个引用及完全位于移动带中的区域按插删轴调整；跨越带边界的引用通常保持，删除完全覆盖其轴区间且切到另一轴边缘时裁掉相交边。整轴引用仍覆盖工作表末端。规则依据 [ONLYOFFICE Range.isIntersectForShift/forShift](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L614-L790)和[公式移位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L10152-L10280)，不把移动当成相对复制。

带普通图片或已支持图表的工作表也可执行四向移位。局部操作保留固定、随格移动和随区域缩放三种锚点的标记；固定行列尺寸时，绘图 XML、位置、尺寸、文字和媒体字节保持。有自动行高变化时，需跟随尺寸的对象继续按候选尺寸重排。本表及跨表图表引用沿相同移动带变换，分类、系列标题、独立数值长度和失效缓存归[工作表图表](#工作表图表)。单元格、公式、引用和缓存共用一次精确历史；未知资源、无法表示的矩形及预算失败继续原子拒绝。实现归 [`axis-edit.mbt`](../../modules/formats/src/xlsx/axis-edit.mbt)、[`picture-axis.mbt`](../../modules/formats/src/xlsx/picture-axis.mbt)和 [`chart-axis.mbt`](../../modules/formats/src/xlsx/chart-axis.mbt)。锚点规则依据 [ONLYOFFICE 局部移位与整轴绘图更新](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/DrawingObjects.js#L3232-L3558)，沿用本项目的引用和绘图实现。

既有条件格式/数据验证的 `sqref` 按移动带拆分或删除；普通公式保持各格的相对、绝对和跨表引用。公式型 `cfvo` 阈值按整条规则更新引用，不随覆盖格偏移。需要不同公式的区域按各条 `cfRule` 分组保存，避免其他色阶或数据条随之拆分统计样本；保留规则属性、源注释和命名空间。条件格式保留原优先顺序并分配唯一优先级，验证同步 `count`，与单元格共用一次精确历史。常量、全绝对公式及整条规则阈值按区间处理，不展开整列空格。逐格相对公式每次操作最多求值 100000 个规则覆盖格、处理 4 Mi 字符，累计最多 4096 个规则片段；克隆源另受单部件与 4 Mi 字符上限约束。未知规则结构、无法解析的公式、克隆身份扩展或预算不足时原子拒绝。范围变换参考 [ONLYOFFICE 条件格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L564-L643)和[数据验证](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/DataValidation.js#L976-L1067)，整条规则阈值沿[统一求值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L1029-L1086)。

范围变换复用源规则与引用事务。普通条件格式的呈现与验证执行/编辑已接通，范围归[条件格式](#条件格式)和[数据验证](#数据验证)；未呈现效果的 PDF 继续原子拒绝。传统便笺按所选行/列带移动归属，删除目标格时同时删除文字和对应 VML 框，范围外便笺保留。移动带切开合并或矩形链接、依赖无法隔离的公式/引用、未接入的筛选/绘图/表格/线程批注资源及工作表保护继续原子拒绝。可用的整行/整列操作保持原有规则支持。保存重开后继续沿同一编辑与 PDF 路径工作；其余 [P11](../p11-xlsx-core.md) 范围仍待实现。

### 四向填充

`editSheet({ action: "fill", range, direction })` 支持 `down/up/right/left`，作用于 A1 矩形；源和目标合计最多 4096 格。向下/上以首行/末行为源，向右/左以首列/末列为源；沿填充轴只有一行/列时，源为方向相反的相邻行/列。相邻源越界时保持文档。数字直接重复，不推导序列。

核心复制类型值及有效格式，文字中的 `=` 保持文字；公式只平移相对引用，保留绝对与跨表引用，越界生成 `#REF!`。受影响共享公式有界展开。值、格式、依赖缓存和选区共用既有事务、自动尺寸及一次精确历史；保存重开后可继续编辑。复制文字和公式源码累计最多 1 Mi 字符，单公式最多 8192 字符，候选、源和历史仍受既有预算约束。

四向填充、序列和向外填充柄已支持普通条件格式与数据验证，细节见下段。普通链接已接通完整源范围复制及目标裁剪；传统便笺保留各格原有文字与框，不随源复制，见[单元格便笺](#单元格便笺)；已识别迷你图随源模式复制并平移数据源，见[单元格迷你图](#单元格迷你图)；合并几何见下段；未知扩展、表格/透视和线程批注继续保护。范围外规则与元数据保留。默认按钮使用当前选区，沿既有队列提交原生草稿。核心已检查四向、相邻边界、类型值、有效格式、共享公式、重算、精确历史、重开及原子失败；Chromium 已检查四向按钮、原生草稿、独立公式/样式/缓存源、混合历史、保存重开和 PDF。重新打包的参数检查与严格宿主调用通过。数字序列见[数字序列](#数字序列)，基本拖动与键盘操作见[填充柄](#填充柄)。来源选择参考 [ONLYOFFICE prepareFillHandle](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L27533-L27590)，实现归 [`fill.mbt`](../../modules/formats/src/xlsx/fill.mbt)。

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

#### 条件格式与验证

条件格式和数据验证随源范围按原周期扩展，覆盖目标内旧规则并保留范围外部分。复制、自动、线性、增长、日期及文本序列共用此事务。核心保留原生规则与差异样式引用、优先级相对顺序、验证提示和容器元数据；色阶、数据条的最小/最大值仍按源和新范围共同计算。向上/左填充重新绑定相对公式锚点，绝对引用及全局阈值沿既有规则变换。条件格式裁短最后一块；数据验证仅复制目标能完整容纳的源规则片段，部分尾块不保留旧验证。生成值按最终规则校验，失败保留原包、选区、修订和历史。向内缩减只清内容，保留规则与格式。

规则、值、公式缓存及合并几何合为一次精确历史。相同值仍可转移不同规则，重复同一结果不新增历史。沿已有 4096 格、4096 规则/范围和 1 Mi 单元格源限制；相对规则变换沿既有 100000 格、4 Mi 公式工作及历史/输出预算，超限原子拒绝。未知规则元数据、表/透视资源和线程批注继续保护。普通链接沿下段合同复制，不自动打开外链。实现归 [`fill-rules.mbt`](../../modules/formats/src/xlsx/fill-rules.mbt)，语义参考 [ONLYOFFICE promote 的验证与条件规则扩展](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22638-L22755)；未复制上游执行代码。

#### 链接填充

四向、复制、自动和其他序列只复制完整落在源范围内的普通链接，并按源周期放到能完整容纳链接的目标片段。部分源链接及不足的尾块不复制。外部 HTTP/HTTPS/mailto 目标与内部 `#` 目标保持原字符串，不按公式相对引用平移；提示与显示标签保留，格内值仍沿所选填充模式生成。核心不请求链接，默认界面继续由用户显式打开或导航。

目标旧链接按本 SDK 既有矩形粘贴规则裁剪，保留范围外片段；新范围没有源链接时清除旧链接。链接、值、公式缓存、格式和普通规则合为一次精确历史；同值也能更新链接，重复结果不新增历史。关系复用现有目标身份，重开后可继续输入和内部跳转；向内缩减只清内容，保留链接及其元数据。未知/组合元数据、重叠链接、不安全地址、未解析关系及超限原子拒绝。沿 4096 格/链接、1 Mi 复制链接文字、单项标签/提示 32767 单元和 2 Mi 目标链接源码上限，以及已有历史/输出预算。

完整范围与尾块规则参考 [ONLYOFFICE promote 的链接复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22619-L22636)，缩减参考 [cleanText](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21114-L21129)。目标裁剪复用本项目的链接粘贴事务；实现归 [`fill-hyperlinks.mbt`](../../modules/formats/src/xlsx/fill-hyperlinks.mbt)和 [`clipboard-hyperlinks.mbt`](../../modules/formats/src/xlsx/clipboard-hyperlinks.mbt)，不新增公开 API。

### 填充柄

普通网格在选区末格显示填充柄；RTL 使用左下角。拖动向外扩展一条行带或列带，核心按物理距离选择轴。向内拖动选择要清除的末尾行带或列带，只清内容和公式并保留格式；边界按命中格的半格位置吸附，角点附近未越过边界时无操作。拖到源起点可清空整块内容。聚焦填充柄后，方向键延伸一行或一列，左右键遵循 RTL 的物理方向。支持缩放、冻结窗格和边缘滚动。Ctrl 将向外填充切换为循环复制；单个普通数值改为逐格加一。日期/时间、文字及公式按源模式复制，公式仍平移相对引用。拖动中按下或松开 Ctrl 即可切换，释放使用当时的状态；方向键也支持 Ctrl。向内清除规则不变。双击填充柄，或聚焦后按 Enter/Space，按相邻连续区域向下自动填充。下方首行全部有内容时延伸至首个缺格行之前；部分有内容时不操作；全空时从左右及对角相连的区域推导末行，并停在目标列下一处内容之前。样式空格不延长区域，隐藏行仍参与推导；相邻筛选区域不能借作跨区向导。源内的完整合并可沿填充事务复制；源外参与推导的合并向导仍明确拒绝。没有可延伸范围时不增加修订或历史。

`XlsxSession/XlsxClient.fillPreview(layoutId, target)` 接受 `{ kind: "point", x, y }`、`{ kind: "direction", direction }` 或 `{ kind: "adjacent" }`。三种 target 都接受可选布尔字段 `ctrl`，默认 false。核心返回 `source/range/direction/mode/geometry/end`。Ctrl 向外操作返回 `mode=copy` 或单个普通数字的 `mode=linear`，range 与自动向外操作相同。`mode=auto` 的 range 是源与向外目标的并集，`mode=shrink` 的 range 是待清尾带；geometry 显示此操作区域，end 定位提交后的末格。预览不改文档、选区、revision 或历史。过期布局、非法目标和超过 4096 格的范围拒绝。宿主只发送指针与键盘意图，范围和冻结裁剪由核心计算。

原生草稿先独立提交，再恢复拖动前的源范围。预览不写源；释放时按预览的自动、复制、线性或缩减模式执行一次事务，后续保存排在该操作之后。未释放时，Escape、失焦、指针取消、暂停和销毁取消拖动。普通规则沿下述填充合同扩展；向内清除内容保留原规则和格式。普通链接随同一次填充复制，向内缩减保留链接；其他未知资源继续保护，合并源沿下述几何规则处理；失败保持源和历史。普通支持的链接不阻止静态 PDF；未知工作表扩展仍明确拒绝完整输出。

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

已识别迷你图的普通行列排序和原生表行排序沿同一事务执行。目标地址、源范围及原生扩展字节保持，图形从排序后的当前格值重绘。图形位置与便笺归属分别处理，便笺仍随单元格移动。详细边界归[单元格迷你图](#单元格迷你图)。

同一工作表含受支持原生表时，表外普通矩形仍可按行或列排序。核心检查表资源归属，保留表范围、列身份、计算列模板和原生排序状态。按当前全部筛选来源冻结可见位置，候选计算后重新应用相关条件；手动隐藏和各筛选来源分别保留，最终隐藏取并集。普通筛选内的排序状态仍写入所属筛选，其他普通排序写入工作表；原生表的排序状态独立保存。选区与表相交时沿[原生表行排序](#结构化表与引用)规则，跨表边界仍保护。范围归属参考 [ONLYOFFICE searchRangeInTableParts](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L1479-L1500)。

`editSheet({ action: "sort", range, rows, header, caseSensitive, keys })` 对最多 4096 格的显式 A1 矩形排序。`rows=true` 按行重排，键 `index` 是工作表从 1 开始的列号；`rows=false` 按列重排，键为行号。`keys` 为 1–16 个互异条件 `{ index, descending, customList?, sortBy?, color?, iconSet?, iconId? }`，索引必须在范围内，按数组顺序比较。三个布尔字段必须显式提供，`header=true` 保留所选范围的第一行或第一列。默认面板使用当前选区，提供方向、标题、大小写、增删多键、每键自定义列表、颜色及图标依据。`XlsxSortSettings/XlsxSortKey` 从 Wasm/Web XLSX 模块导出。

核心冻结排序前的当前键值，不用导入缓存代替未计算公式。数值及可解析为有限十进制数的文字键按数字比较，保留原单元格类型；布尔和错误按显示文字参与文字比较。空格与空串不同；空单元格和空串结果在升降序中均置后。相同键按原行列顺序稳定排列。`caseSensitive=false` 使用固定 Unicode 16 大写映射，文字按 UTF-16 字符序比较，不使用 MoonBit 默认的长度优先比较；语言区域校对顺序仍待兼容扩展。隐藏行或列的位置、内容与手动隐藏状态保留，不参加对应方向的置换。普通比较、隐藏位置和多键路径参考 [ONLYOFFICE _getSortElems](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21327-L21649)；该上游的 localeCompare 与本期固定字符序不同。

每个值键可选 `customList: string[]`，缺省或空数组使用普通排序。非空列表按给定顺序定义文字优先级，各键可使用不同列表。沿既有归一化，数字及数字文字继续按数值比较，布尔和错误按显示文字参与匹配。列表先精确匹配原文字，未命中时使用固定 Unicode 大写映射查找列表中的第一项；仅大小写不同的标签可以分别列出，精确命中保留各自顺序。此列表匹配规则不受 `caseSensitive` 改变，该选项继续控制未列出文字的普通比较。升序时列出项排在未列出文字之前，未列出项按普通顺序比较；降序反转文字比较结果，空单元格和空串仍排在末尾。相同优先级继续比较后续键，再保持源顺序。

每份列表最多 4096 项，逗号连接后的长度最多 32767 UTF-16 单元。标签必须互不相同且非空，前后空格保持，不能包含逗号、回车或换行。引号、制表符及看似 OOXML 转义的文字通过既有文字编码保存；原始和编码后的列表载荷另受 1 Mi 单元预算约束，失败不提交。默认面板按键提供每行一项的输入，留空恢复普通排序。核心 `SortKey.custom_list` 使用空数组表示普通顺序；TS 的 `customList` 可省略。列表与单元格、排序状态、筛选和缓存合为同一项历史，不另建应用级自定义列表目录。

已检查 ONLYOFFICE 的上述排序路径，其文字分支没有自定义列表比较。因此文字优先级参考下一顺位的 [LibreOffice GetSubIndex/Compare](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/tool/userlist.cxx#L60-L142)与[文字键排序入口](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/data/table3.cxx#L1534-L1585)。实际大小写映射和未列出项排序继续采用本项目的固定规则，不执行地区化校对。每键顺序写入标准 `sortCondition@customList`，导入、无关编辑、工作表复制/改名及既有排序状态引用维护保留它；实现归 [`sort-list.mbt`](../../modules/formats/src/xlsx/sort-list.mbt)。

`sortBy` 缺省或为 `value` 时按值比较；`cellColor` 按填充色，`fontColor` 按单元格字体色。颜色键必须给出 `color`，使用六位 RGB 十六进制文字；填充色的空串表示无填充，与白色不同。颜色键不能同时使用非空自定义列表，值键不能指定非空颜色。同一轴可设置不同颜色或依据，例如先红色、再绿色，最后按该列数值；完全重复的条件仍拒绝。`descending=false` 把命中色放在前面，`true` 放在后面，同组继续比较后续键，再保持原顺序。空内容格也按其有效颜色参加此分组；隐藏行列继续保留位置。

颜色取自排序前的有效样式，包含已支持条件格式及主题/索引颜色的解析。核心冻结颜色匹配结果，再使用原有单元格置换；条件规则仍留原范围，排序后重新求色，依赖位置的规则可能改变最终颜色。默认面板提供依据、RGB 输入、无填充及命中色位置。颜色条件写标准 `sortBy` 与 `dxfId`，一次批量复用或新增差异样式；首次样式部件也与数据、关系和历史一起提交。原有规则和样式身份保持，颜色引用缺失时拒绝重排或引用相关的表操作。普通富文本文字色沿[颜色筛选](#颜色筛选)的文字段规则匹配；未知源继续保护。

`sortBy: "icon"` 按当前条件格式实际显示的图标匹配。`iconSet` 使用已支持的 17 种标准名称，`iconId` 是从零开始的图案索引；两项同时省略时匹配无图标的格。其他依据不能指定图标，图标键不能携带非空颜色或自定义列表。默认控件按一开始编号，切换级数时裁到有效图案范围；规则反转不改变图案身份。`descending=false/true` 分别将匹配项置前/置后，同组沿后续键及原顺序比较；同轴可指定多个不同图标。核心在置换前冻结有效图标，保留规则优先级、停止规则、当前公式和空值语义；规则仍留原坐标，排序后按新内容重绘。普通行/列和原生表行排序复用相同事务、隐藏位置及精确历史。标准 `sortCondition` 写 `sortBy="icon"` 和明确的 `iconSet/iconId`，无图标条件省略两项，不新增差异样式。读取校验分组及索引，既有复制/结构引用维护保留这些属性。MoonBit `SortKey` 增加 `icon_set/icon_id`，非图标键使用空串及零。图标身份和方向按 [OOXML SortCondition](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.sortcondition?view=openxml-3.0.1)核对，既有 ONLYOFFICE 顺位的稳定重排与多键事务保持；实现归 [`sort-icon.mbt`](../../modules/formats/src/xlsx/sort-icon.mbt)。

有效样式冻结及按命中色分组参考 [ONLYOFFICE _getSortElems/colorFillCmp](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21427-L21600)，`dxfId` 存储参考 [CSortCondition](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/XlsxFormat/Table/Autofilter.cpp#L96-L106)。实现归 [`sort-color.mbt`](../../modules/formats/src/xlsx/sort-color.mbt)，差异样式复用 [`conditional-style-edit.mbt`](../../modules/formats/src/xlsx/conditional-style-edit.mbt)，没有新增绘制模型或复制上游源码。

排序移动单元格值、富文本 XML、有效样式及已支持公式，局部补齐命名空间，保留源格式。公式相对引用按实际位移平移，绝对引用保持，越界生成 `#REF!`；受影响共享组有界展开。区域外公式引用继续指向原坐标，并按排序后的内容重算。单格超链接随内容移动，矩形链接保持原坐标，关系和目标不变。条件格式、验证及名称保持原坐标范围，效果和输入约束基于候选值计算；验证失败整项拒绝。行列尺寸保留原位置，已有自动尺寸仍按新内容重排。公式、依赖缓存与值/源/链接使用同一有界历史，精确撤销/重做，保存重开及 PDF 使用已排序内容；原生草稿先独立提交。恒等置换不新增 revision 或历史。重排及公式位移参考 [ONLYOFFICE _sortByArray](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21651-L21770)。

已有普通值/自定义筛选的工作表也使用相同排序入口和显式范围。核心先按排序前的可见性冻结参加坐标；行排序保留手动及筛选隐藏记录的位置，列排序保留隐藏列位置。筛选范围、条件及按钮属性保持原坐标，不随单元格移动。候选值、格式和公式生成后，重新应用筛选，保留原手动隐藏来源，并重算依赖可见性的 SUBTOTAL 缓存；排序后可见行可因当前位置的公式结果而变化。单格链接和便笺沿内容移动，区域外源保持。单元格、筛选掩码、公式缓存与选区共同提交一次精确历史；恒等置换不新增历史。默认排序面板沿相同原生草稿屏障执行，保存重开保留当前顺序和筛选；清除条件只恢复筛选隐藏。

实际发生置换时，核心把范围、键顺序、升降序、行/列方向和大小写选项保存为标准 `sortState`，与内容和筛选共用一次历史。`ref` 排除显式标题；值键写 `sortBy="value"`，颜色键写相应依据与差异样式引用，图标键写相应集合和图案索引，固定字符序写 `sortMethod="none"`。排序范围位于已有筛选内时写入该筛选，否则写入工作表；另一位置的历史排序设置保持。恒等置换不改排序信息或历史。导入可保留合法空状态及最多 64 个不同排序条件及其自定义文字顺序；同轴颜色条件按依据和差异样式引用区分，`none`/`pinYin`/`stroke` 标志在无关修改和筛选重新应用时保留源内容；这不表示执行地区化排序。新命令仍限 16 键。工作表改名、复制与重开保留设置；工作表级排序信息随整行列及完整覆盖排序区域的单元格移位同步范围和键引用，删除键时移除该键，失去全部键时移除状态。只跨过排序区域一部分的移位保留上次排序记录。清除筛选条件保留其排序信息；新筛选范围不能容纳旧排序范围时移除旧信息，移除筛选也移除其排序信息。其他位置和未知源保持。

上述存储和引用维护参考 [ONLYOFFICE SortState](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L9742-L10000)、[OOXML 排序定义](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/Test/Applications/DocxFormatCodeGen/codegen/Resource/sml.xsd#L148-L182)及[写入代码](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/XlsxFormat/Table/Autofilter.cpp#L320-L352)，没有复制上游源码。

排序键归一化共享 1048576 次公式工作预算，移动片段累计最多 1 Mi UTF-16，继续使用公式、候选、源和 4 MiB 历史上限。合并区域、未知筛选/排序元数据、绘图、未支持的结构化表操作/透视、线程批注及未知便笺、未知资源或关系、未知单元格/公式标记和工作表保护继续原子拒绝。更广合并/资源支持归 [P11](../p11-xlsx-core.md) 后续范围。实现归 [`sort.mbt`](../../modules/formats/src/xlsx/sort.mbt)、[`sort-state.mbt`](../../modules/formats/src/xlsx/sort-state.mbt)、[`sort-source.mbt`](../../modules/formats/src/xlsx/sort-source.mbt)、[`reorder-cells.mbt`](../../modules/formats/src/xlsx/reorder-cells.mbt)及 [`xlsx-sort.tsx`](../../packages/ui/src/xlsx-sort.tsx)。

### 文本分列

`XlsxSession/Client.textColumns(revision, sheet, settings)` 返回只读预览，宿主入口为 `SpreadsheetEditor.textColumns(settings)`。`XlsxTextColumnSettings` 包含同列 A1 范围 `range`，以及二选一的分隔符 `delimiter` 或固定宽度位置 `breaks`；不能同时提供。分隔符支持逗号、分号、空格及制表符。可选 `types` 指定每列转换，`formulas` 默认关闭。返回 `XlsxTextColumns`，含归一化设置、revision、sheet、`resultRange`、原始字段数 `splitColumns`、实际输出列数 `columns`、将覆盖的非空单元格数 `overwrittenCells` 和转换后的前十行 `preview`。设置、预览及 `XlsxTextColumnType` 从 Wasm/Web XLSX 模块导出。MoonBit 的 `TextColumnSettings.split` 使用 `Delimited(String)` 或 `Fixed(Array[Int])`，`types=[]` 表示全部文字。预览不改源、选择或历史；原生草稿和组合屏障沿既有宿主队列处理。

提交使用 `editSheet({ action: "textToColumns", settings, sourceRevision, overwrite })`。源列的编辑值从选区左上角向右拆分，包含隐藏行；公式使用带 `=` 的编辑文字，普通数值使用原值文字，不使用格式化显示或导入缓存。分隔符模式中，双引号包围字段内的分隔符保持，两个连续引号还原为一个；连续/末尾分隔符产生空字段，短行补空至最大列数。保留单元格内的换行，不把它扩成额外工作表行。默认全部写为文字，前导零和公式样式文字保持。空字段清空对应内容，单元格格式、链接、便笺和行隐藏状态保持原坐标；条件/验证范围也保持。

`types` 非空时必须覆盖全部原始字段。`text` 保留文字，`general` 复用现有数字及布尔解析；只有常规列且明确选择 `formulas=true` 才解析公式，无法计算的公式拒绝整项操作。`ymd`、`mdy`、`dmy` 分别按明确年月日顺序转换，要求四位年及数字日期，接受 `/`、`-`、`.` 和既有时间解析。无效日期保留原文；有效日期使用工作簿 1900/1904 日历，并设置 `yyyy-mm-dd` 或 `yyyy-mm-dd hh:mm:ss`，其余样式保持。`skip` 丢弃该字段，其余字段向左紧排；必须保留至少一列，实际输出矩形之外保持原样。默认面板先预览，再逐列选择类型，公式另有勾选项；候选日期、计算值和格式与提交一致。地区化数字、月份名称及任意日期格式不在当前范围。

固定宽度使用 1–4095 个严格递增的整数位置，范围为 1–65534；`breaks: [3,7]` 依次取宽 3、宽 4 和余下文字，始终输出三列。宽度复用 Unicode 16 的 W/F 两列、其余默认一列及默认可忽略字符零列的顺序；不是字体像素宽度。沿现有字素分段整体推进，宽字符或组合簇跨过指定位置时整体留在当前段，不拆代理对或字素；随后按下一段宽度继续。忽略簇附在前段末尾，短行补空。每段仅裁掉尾部 ASCII 空格，再移除成对外层双引号；内部引号、分隔符及前导空格保持。固定模式不执行分隔符引号解析。默认面板提供方式切换及位置输入；无效位置阻止预览，修改方式或位置会清除旧预览和覆盖确认。

原源列之外的非空目标值或公式计入覆盖数量，仅带格式的空单元格不计入。核心重算方案并复核 sourceRevision；需要覆盖时，只有 `overwrite=true` 才提交。默认面板先显示输出矩形、数量和前十行，再要求勾选覆盖并明确提交。设置、选区、表、文档或修订变化使旧预览失效。目标写入、日期样式及首次样式部件、公式依赖缓存、验证及自动适配共用已有单元格事务和一次精确历史；无实际变化不新增历史。保存重开与静态 PDF 使用同一结果。

源最多 4096 行，原始字段矩形和实际输出矩形均最多 4096 格，实际输出不能越过 XFD 列；输入累计最多 1 Mi UTF-16，每格最多 32767 单元，并受原包、XML、输出和 4 MiB 历史预算约束。分隔符模式的错误引号、非法固定位置、合并格、富文本等既有只读单元格、工作表保护、不透明公式/元数据或验证失败原子拒绝。CSV/TSV 文件导入仍只接受逗号或制表符，原转换选项保持。更广地区化转换和格式组合继续实施。

功能入口参考 GenOffice 单列分列操作，编辑值与文本粘贴事务参考固定 [ONLYOFFICE asc_TextToColumns](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/api.js#L846-L902)及 [getRangeText](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L23563-L23594)。固定宽度参考 [LibreOffice 列宽推进](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/ui/docshell/impex.cxx#L529-L557)、[段落提取](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/ui/docshell/impex.cxx#L1490-L1534)及[分列事务](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/ui/docshell/impex.cxx#L1641-L1689)，补齐字素完整性。本实现默认保留文字，转换需要明确选择，不声称覆盖完整文本导入向导；未复制上游源码。实现归 [`text-columns.mbt`](../../modules/formats/src/xlsx/text-columns.mbt)、[`text-columns-convert.mbt`](../../modules/formats/src/xlsx/text-columns-convert.mbt)、[`text-columns-fixed.mbt`](../../modules/formats/src/xlsx/text-columns-fixed.mbt)、既有 [`delimited.mbt`](../../modules/formats/src/xlsx/delimited.mbt)和 [`xlsx-text-columns.tsx`](../../packages/ui/src/xlsx-text-columns.tsx)。

### 删除重复行

已识别迷你图的普通区域与原生表去重沿同一预览和事务执行。移除原始重复行内的图形，幸存图形保留坐标和数据源；具体归属见[单元格迷你图](#单元格迷你图)。

`XlsxSession/Client.duplicates(revision, sheet, settings)` 返回只读预览，宿主入口为 `SpreadsheetEditor.duplicates(settings)`。`XlsxDuplicateSettings` 包含显式 A1 矩形 `range`、`header` 和工作表从 1 开始的比较列 `columns`；至少选一列，各列互异且在有效范围内。普通区域的 `header=true` 保留首行。返回 `XlsxDuplicates`，包含有效设置、`totalRow`、revision、sheet、完整 `keptRows/removedRows`、有效结果 `resultRange` 及前十条保留记录的格式化值 `preview`。`totalRow` 表示不参加比较的原生总计行，普通区域为 false。两个类型从 Wasm/Web XLSX 模块导出。核心预览不修改源、选择、修订或历史；宿主沿既有队列先处理原生草稿和组合输入。

提交使用 `editSheet({ action: "removeDuplicates", settings, sourceRevision })`。默认面板先选择比较列和标题，再预览删除数量、原行号及保留内容，最后明确提交。设置、选区、表或修订变化后旧预览不能提交；换文档须丢弃旧结果。核心重新计算方案并核对 sourceRevision，不信任传入的删除行列表。无重复或候选源没有实际变化时不新增历史。

比较使用当前已计算结果和格式化文字，区分大小写及空格；显示相同的数字与文字可匹配，不因底层类型不同而保留两份。保留首次出现的记录，包含手动隐藏行。存活单元格按原顺序向区域顶部压紧，移动值、富文本源、有效格式及相对公式；绝对引用和区域外引用坐标保持，依赖缓存同步重算。清空尾部内容及显式单元格格式，行列继承格式仍有效，不删除整张表的物理行，也不移动选区外单元格。手动尺寸和隐藏状态保留原坐标，自动尺寸沿现有路径重排。条件格式、验证及名称保留坐标，候选输入继续校验。

单格链接和便笺随保留记录移动。删除重复记录时，同步移除对应便笺/VML 和完整落在该选区删除行内的链接；跨行链接保持原坐标。其他部件及源片段保留，值、公式、样式、链接、便笺和缓存合为一次精确历史；撤销、重开后输入、查找替换及 PDF 沿相同内容路径。有效范围一次最多 4096 格，格式化及条件计算共享 1048576 工作预算，搬移片段累计最多 1 Mi UTF-16，继续遵守输出和 4 MiB 历史上限。合并格、跨表边界、透视、绘图、未知排序/便笺及单元格/公式元数据等沿重排保护原子拒绝；这些组合继续实施。

已有普通值/自定义筛选时，去重比较仍包含筛选隐藏行，保留首条记录。筛选范围、条件和已知按钮标记保留；按压紧后的当前公式结果重新应用条件，重写筛选隐藏来源和实际行可见性，手动隐藏继续保留原行号。SUBTOTAL 及依赖缓存随可见性一起重算。整个过程只有一次历史；重开后清除条件仍只恢复筛选隐藏行。未知筛选条件或不透明源原子拒绝，导入隐藏来源的歧义沿[值筛选](#值筛选)处理。

选区完整位于一张原生表时，核心将有效范围扩展为整表。`header` 取原生设置，比较列可选整表中的任意列。标题和总计不参加比较，预览的 `range` 和 `resultRange` 包含它们。默认面板显示整表范围并锁定标题开关。删除后保留表/列身份、计算列模板、存活例外和样式，范围按删除数缩小；总计文字、公式和格式迁至新末行，公式沿范围调整规则保持原文。根及筛选内的已知排序范围同步裁剪，保留历史设置，不重新排序。表外普通区域也可去重，保留原生表范围，并重新计算依赖该区域的原生与普通筛选。多来源可见性、手动隐藏、依赖缓存及源变化共用一次历史；没有标题或筛选的表沿相同路径处理。

比较和稳定压紧依据 [ONLYOFFICE setRemoveDuplicates](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L25977-L26181)、[清空单元格](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21142-L21166)及前述 `_sortByArray`；未复制上游源码。实现归 [`duplicates.mbt`](../../modules/formats/src/xlsx/duplicates.mbt)、[`reorder-cells.mbt`](../../modules/formats/src/xlsx/reorder-cells.mbt)及 [`xlsx-duplicates.tsx`](../../packages/ui/src/xlsx-duplicates.tsx)。其余数据工具继续按 [P11](../p11-xlsx-core.md) 实施。

### 值筛选

`editSheet({ action: "filter", range, columns })` 设置普通工作表的值、日期组、跨年日期、相对日期、自定义、数值排名、平均值、颜色或图标筛选。`range` 是含标题首行、至少一行数据且最多 4096 格的 A1 矩形。`columns` 最多含 256 个互异的 值条件 `{ kind: "values", column, values, blank }` 、自定义条件 `{ kind: "custom", column, conditions, all }` 、排名条件 `{ kind: "rank", column, value, top, percent }` 、平均值条件 `{ kind: "average", column, above }` 、日期组条件 `{ kind: "dates", column, groups, values, blank }` 、跨年日期条件 `{ kind: "calendar", column, unit, value }` 、相对日期条件 `{ kind: "relativeDate", column, period }` 、颜色条件 `{ kind: "color", column, cellColor, color }` 或图标条件 `{ kind: "icon", column, iconSet, iconId }`；`column` 是范围内从 1 开始的工作表列号，`values` 是最多 4096 项互异文字，`blank` 显式决定空白是否通过。各列取交集，同列文字取并集；空条件数组显示全部数据并保留筛选范围。文字按当前已计算值和已支持的有效格式（含条件格式）显示，去除两端空白后使用固定 Unicode 16 小写映射匹配；不改变单元格类型、值、样式、公式或记录位置。未计算公式不使用导入缓存代替。普通文字匹配参考 [ONLYOFFICE Filters.isHideValue](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L10785-L10805)和 [AutoFilter.setRowHidden](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L9585-L9640)。日期组、跨年日期、颜色、数值排名与平均值条件见下文；高级筛选继续保护。

自定义筛选的 `conditions` 含一至两个 `{ operator, value }`，`all` 为 `true` 时取 AND，`false` 时取 OR。`operator` 接受标准 `equal/notEqual/greaterThan/greaterThanOrEqual/lessThan/lessThanOrEqual`，`value` 为最多 32767 单元的文字。有限数字文字按当前数值比较，包含可转换的数值文字单元格，不使用四舍五入后的显示值或导入公式缓存；空白不当作零。其他条件按去除两端空白和相同大小写映射后的标签比较，数值单元格不参与文字匹配；等于/不等于支持 `*`、`?` 和 `~` 转义，`?` 对应一个 UTF-16 单元。空文字等于可匹配空白/公式空串。比较符必须放在 `operator`，条件值内的 `<`/`>` 不被重新解析。自定义日期比较使用数值序号；日历前缀使用下节日期组，本地化解析继续实施。双条件和数值/文字分流参考 [ONLYOFFICE CustomFilters/CustomFilter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L11130-L11456)，文字/通配符复用已有有界条件匹配。

GenOffice 的“高级筛选”入口使用上述同列最多两个自定义条件和 AND/OR，当前 API 与默认自定义面板已覆盖这一入口。条件区域式高级筛选仍按 P11 计划实施；二者不另建相同的条件模型。

同一列仅有一类条件，值、日期组、跨年日期、相对日期、自定义、排名、平均值和颜色面板相互替换，其他列保留并继续取交集。`query.filter.columns` 返回相同带 `kind` 的联合类型；日期组、跨年日期、相对日期、自定义、排名、平均值和颜色列的值目录不投影条件结果，值选择初始为全部，应用后切换为值条件。默认面板支持比较符、条件值、第二条件及 AND/OR。MoonBit 使用 `FilterColumn { column, rule }` 和 `FilterRule::Values/Dates/Calendar/Relative/Custom/Rank/Average/Color/ColorStyle`；Wasm/Web 另导出 `XlsxFilterColumn/XlsxCustomFilter/XlsxFilterCondition/XlsxFilterOperator`。

`filterClear` 清除全部条件并保留范围，`filterRemove` 同时移除范围，`filterReapply` 按当前值重新应用。原生输入先按原队列提交；普通编辑保留现有隐藏结果，由重新应用更新。每项使用已有 revision 和单项源历史，保持选择；相同结果不新增历史。网格、自动尺寸及 PDF 共用核心隐藏行。`query.filter` 提供 `range/columns/reason` 和逐列 `catalog`；每列返回 `column/title/blank/blankSelected` 及 `{ value, count, selected }` 选项，按归一化值合并大小写，保留当前条件中的零计数值。默认面板使用当前选区创建范围，选择列和值、空白，并提供清除、移除和重新应用。Wasm/Web 导出 `XlsxFilterSettings/XlsxFilterValues/XlsxFilterState`。

保存使用标准 `autoFilter/filterColumn/filters/filter` 或 `customFilters/customFilter`（`and` 与 `operator/val`）、`sheetPr.filterMode` 和行 `hidden`。行高、原属性与非目标部件保留。`autoFilter/extLst` 内的 `urn:open-document:xlsx:filter-state` 扩展记录 `manual` 与 `filtered` 行号，可同时包含同一行；清除筛选只恢复筛选隐藏，手动隐藏继续保留。已有行高/隐藏命令同步手动来源，正行高也不能展开仍被筛选隐藏的行。复制、改名、撤销重做和保存重开保留此来源；扩展与实际隐藏行不一致时拒绝编辑。外部文件只有一个 `hidden` 字段，无法判断同一行是否同时被手动和筛选隐藏；无来源扩展时，将不匹配条件的隐藏行视为筛选隐藏，其余视为手动隐藏。外部程序若丢弃扩展，也会恢复此导入限制。

每项匹配/目录共用 1048576 次公式工作预算，条件文字累计最多 1048576 个 UTF-16 单元，目录数据/标题累计最多 1048576 个单元；继续受包、源和 4 MiB 历史预算约束。未知条件、日历声明、扩展、属性、筛选内注释/处理指令、工作表保护或无法计算的显示值拒绝修改，保留源与历史。保留已知 `hiddenButton/showButton` 标记。已支持条件的排序和整行/整列插删复用候选重算与隐藏来源事务，局部单元格移位仍保护；原生表筛选归[结构化表](#结构化表与引用)；标题下拉箭头和更广组合按 [P11](../p11-xlsx-core.md) 继续接入。实现归 [`filter-model.mbt`](../../modules/formats/src/xlsx/filter-model.mbt)、[`filter-values.mbt`](../../modules/formats/src/xlsx/filter-values.mbt)、[`filter-custom.mbt`](../../modules/formats/src/xlsx/filter-custom.mbt)、[`filter-source.mbt`](../../modules/formats/src/xlsx/filter-source.mbt)、[`filter-edit.mbt`](../../modules/formats/src/xlsx/filter-edit.mbt)及 [`xlsx-filter.tsx`](../../packages/ui/src/xlsx-filter.tsx)。

### 跨年日期筛选

Wasm/Web 导出 `XlsxCalendarFilter`，使用 `{ kind: "calendar", column, unit, value }`。`unit` 接受 `month` 或 `quarter`，`value` 分别为 1–12 月或 1–4 季度，匹配所有年份。普通区域与原生表共用条件、默认控件、同列替换和其他列交集。

核心按当前数值的日期序号匹配月份，使用工作簿的 1900/1904 系统，保留 1900 年虚构闰日。显示格式不影响结果；普通数值和时间小数也按日期序号解释，文字、布尔、错误、空白及日历范围外数值不匹配。公式使用当前计算值，不读取过期缓存。输入后沿原筛选规则保留隐藏结果，显式重新应用再更新。手动隐藏、SUBTOTAL、整行/列结构维护、精确历史及保存重开复用已有事务和工作预算。

源写为标准 `dynamicFilter type="M1"… "M12"` 或 `"Q1"… "Q4"`。导入查询保留原源和按钮标记；有限 `val/maxVal` 缓存只作源校验，重新应用按当前值计算。未知类型、属性和子节点继续保护。依赖当前日期的条件归[相对日期筛选](#相对日期筛选)。月份与季度边界参考 [ONLYOFFICE DynamicFilter.isHideValue](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L11896-L11990)，原生类型名归同文件的 `ToXml_ST_DynamicFilterType`。实现归 [`filter-calendar.mbt`](../../modules/formats/src/xlsx/filter-calendar.mbt)和 [`xlsx-date-filter.tsx`](../../packages/ui/src/xlsx-date-filter.tsx)。

### 相对日期筛选

Wasm/Web 导出 `XlsxRelativeDateFilter`，条件为 `{ kind: "relativeDate", column, period }`。`period` 接受 `yesterday/today/tomorrow`、`lastWeek/thisWeek/nextWeek`、`lastMonth/thisMonth/nextMonth`、`lastQuarter/thisQuarter/nextQuarter`、`lastYear/thisYear/nextYear` 和 `yearToDate`，可从 `xlsxRelativeDatePeriods` 读取目录。默认面板提供对应的中英文期间。

宿主只提供本地公历日期 `YYYY-MM-DD`，核心沿工作簿 1900/1904 系统计算起止序号。周从星期日开始；日、周、月、季度和年使用完整日历边界，年初至今包含今天。起点包含，终点不包含，数值按日期序号匹配，类型规则与[跨年日期](#跨年日期筛选)一致。普通区域与原生表共用多列交集、手动隐藏、SUBTOTAL、重新应用和源历史。

同步 `XlsxSession.create/open/editSheet` 和 Worker `XlsxClient.create/openXlsx/editSheet` 的最后一项可显式传入日期文字，默认由 `spreadsheetDate()` 取得本地今天；无时区转换或计时器。Worker 协议随创建、打开和工作表命令发送 `date`。MoonBit 对应方法接受可省略的 `date=Some("2024-02-29")`，相对条件使用 `Relative(period, cache)`；新条件传 `None`，缓存为可选的序号起止二元组。成功的命令日期留在会话中，供后续相对日期条件格式和计算使用；失败恢复原日期，并保留原源和历史。日期变化使网格缓存失效，自身不改变源、revision 或文档历史。核心不自动读取系统日期或启动计时器。范围与原生表的筛选仍按下面的显式重新应用规则更新。实现归 [sheet-date.mbt](../../modules/formats/src/xlsx/sheet-date.mbt)。

保存使用标准 `dynamicFilter type/val/maxVal`。查询和重开保留原窗口、隐藏行和源；跨日、普通输入或撤销重做不自动重新筛选。显式应用或重新应用按当日计算窗口，并与隐藏来源及缓存合为一次精确历史。原生导入按保存的窗口推断未记录的隐藏来源，随后重新应用才采用新日期，避免将昨日筛选隐藏误作手动隐藏。两个缓存都缺省时，计算使用显式会话日期；缺少日期时拒绝需要计算的操作。单边、非有限或倒置缓存及未知期间、属性和子节点继续保护。

区间名称、星期日起始和边界参考 [ONLYOFFICE DynamicFilter.init 的 referenceValues](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L11673-L11700)，匹配沿该文件的 `DynamicFilter.isHideValue`。完整期间按其参考边界构造，不沿用 `_calcDateInterval` 中额外加一的日/月/年终点。实现归 [`filter-relative.mbt`](../../modules/formats/src/xlsx/filter-relative.mbt)、[`xlsx-filter.ts`](../../packages/wasm/src/xlsx-filter.ts)及[默认日期控件](../../packages/ui/src/xlsx-date-filter.tsx)。

### 颜色筛选

Wasm/Web 导出 `XlsxColorFilter`，使用 `{ kind: "color", column, cellColor, color }`。`cellColor=true` 比较填充，false 比较字体色；`color` 接受六位 RGB（不带 `#`，忽略大小写）或 null。null 分别表示无填充或自动黑色字体；查询将黑色字体归一化为 `000000`。无填充与白色填充不同。普通区域与原生表使用同一条件和默认面板，替换同列条件并保留其他列交集。

核心比较直接、表样式及条件格式叠加后的当前有效颜色，包含有格式的空白格。手动隐藏、SUBTOTAL、重新应用、结构变换、源历史与输出预算复用既有筛选事务；修改颜色后须显式重新应用。标准 `colorFilter` 保存 `dxfId/cellColor`；比较色沿共享差异样式池写入填充字段，字体模式也如此。导入的字体字段可读取；相同颜色重新设置保留已有样式引用和主题关联。未知样式和超限输入原子拒绝。图标与高级条件仍待实现。

普通行内及共享富文本按任一文字段的颜色匹配，字体色排序使用同一规则。显式 RGB、主题/索引色、明暗变换及自动黑色沿既有解析；缺省颜色继承当前单元格的有效字体色，包含条件格式。共享字符串的比较色集合按身份复用，继承色仍逐格求值，不能固化为第一个引用格的颜色。排序保留文字段及共享字符串源，富文本的文字修改继续只读；相邻普通格仍可原生输入。

基本文字段的字体、字号、粗斜体、颜色、单下划线、删除线和上下标已进入共同排版，预览、静态 PDF、自动行高及列宽使用相同文字段。空文字段的大字号也参与行高；同文异字号的格重排后，自动尺寸随文字段源重新测量。字体资源由原有 `probe/profile` 提供，重开后沿既有规则重新绑定。文字块保留完整绘制指令，页眉页脚和 PDF 表单沿相同坐标变换消费。双线及会计下划线、未知文字段或注音保留源并给出诊断，受影响的自动测量及输出继续保护。颜色归 [`rich-colors.mbt`](../../modules/formats/src/xlsx/rich-colors.mbt)，文字段归 [`rich-layout.mbt`](../../modules/formats/src/xlsx/rich-layout.mbt)，共同块排版归 [`positioned.mbt`](../../modules/layout/src/positioned.mbt)。任一文字段匹配参考 [ONLYOFFICE ColorFilter.isHideValue](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L12110-L12185)与 [colorFillCmp](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21522-L21538)；未复制上游可执行代码。

比较及存储参考 [ONLYOFFICE ColorFilter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L12110-L12260)，未复制上游源码。实现归 [`filter-color.mbt`](../../modules/formats/src/xlsx/filter-color.mbt)、已有颜色排序的 [`sort-color.mbt`](../../modules/formats/src/xlsx/sort-color.mbt)及 [`xlsx-color-filter.tsx`](../../packages/ui/src/xlsx-color-filter.tsx)。

### 图标筛选

Wasm/Web 导出 `XlsxIconFilter`，使用 `{ kind: "icon", column, iconSet, iconId }`，沿普通区域与原生表的现有筛选命令替换同列条件。`iconSet` 使用已支持的 17 种标准名称，`iconId` 是从零开始的实际图案索引；`null` 匹配没有图标的格。默认面板按一开始显示编号，切换级数时裁到有效范围，并提供无图标开关。边界拒绝未知名称、越界索引、缺少字段及混合条件。

核心与[图标排序](#区域排序)共用实际显示图案的匹配，保留反转、规则优先级、停止规则、当前公式及文字/空白语义。各列取交集，手动隐藏和其他筛选来源分别保留；SUBTOTAL、整行插删、精确历史与重开沿既有事务。输入后保留现有隐藏结果，显式重新应用再按当前图案筛选。规则、原样式和数据坐标不变，不新增差异样式。

标准 `iconFilter` 写 `iconSet` 和有值的 `iconId`；无图标条件省略 `iconId`。该语义依据 [OOXML IconFilter](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.iconfilter?view=openxml-3.0.1)；已检查的 ONLYOFFICE `WorkbookElems.js` 图标筛选字段仍标为待实现，因此复用本项目现有图案求值与筛选事务。未知属性、子节点和自定义 x14 图标继续保护，未复制上游源码。实现归 [`conditional-icon.mbt`](../../modules/formats/src/xlsx/conditional-icon.mbt)、[`filter-values.mbt`](../../modules/formats/src/xlsx/filter-values.mbt)及 [`xlsx-icon-filter.tsx`](../../packages/ui/src/xlsx-icon-filter.tsx)。

### 日期组筛选

Wasm/Web 导出 `XlsxDateFilter`，使用 `{ kind: "dates", column, groups, values, blank }`，沿既有 `editSheet({ action: "filter", range, columns })` 替换同列条件。`groups` 是至少一项的日历前缀：`YYYY`、`YYYY-MM`、`YYYY-MM-DD`、`YYYY-MM-DDTHH`、`YYYY-MM-DDTHH:mm` 或 `YYYY-MM-DDTHH:mm:ss`，分别匹配整年、月、日、小时、分钟或秒。年为四位 0001–9999，其他分量须补两位；只接受有效日历、24 小时及 0–59 分秒，不接受时区或地区日期文字。普通数字、文字和布尔值等使用 `values` 的既有格式化标签匹配，空白由 `blank` 单独决定。默认面板按行编辑前缀和其他文字，并提供空白开关。

核心只把当前数值和已计算数值公式、且有效格式为日期或日期时间的单元格交给日期组；有效格式包含条件格式。General 数值、日期样式下的文字、布尔和错误、纯时间格式均沿普通标签匹配，不隐式转换为日期。同列日期组和普通标签分别作用于对应类型，各列仍取交集。每组比较 `[起点, 下一组起点)`，时间小数直接使用工作簿序列值，不经过 JavaScript Date、宿主时钟或时区。1900 系统保留序列 60 的虚构 1900-02-29；1904 系统的序列 0 对应 1904-01-01。日期组固定在明确的日历前缀上，不随“今天”变化。

每列日期组与普通标签合计最多 4096 项，分别拒绝完全重复项；跨粒度重叠合法。派生区间先排序合并，再有界二分匹配，沿既有 1048576 个求值步骤和文字预算，不按记录数与日期组数做全交叉扫描。值改变后保留现有隐藏结果，重新应用更新筛选隐藏及 SUBTOTAL 缓存；手动隐藏、源格式、选择、精确历史、整行/整列结构同步、工作表复制/改名和保存重开沿同一事务。错误日历、未知源及输出预算失败均不提交部分结果。

标准 `filters/dateGroupItem` 使用 `dateTimeGrouping` 与对应的 `year/month/day/hour/minute/second` 前缀字段，可与普通 `filter` 和 `blank` 共存。读取不改写源；修改保留筛选按钮、排序状态和隐藏来源。未知粒度、缺少前置字段、多余细分字段、`calendarType` 声明及未知属性/子节点继续保护。相对当前日期的 `dynamicFilter` 归[相对日期筛选](#相对日期筛选)；其他日历和本地化解析仍归 P11 后续范围。读取及区间规则参考 [ONLYOFFICE 的日期分组匹配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L10785-L10835)、[日期类型分流](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/AutoFilters.js#L1288-L1304)及[六种区间构造](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L12769-L12834)。未复制上游源码；实现归 [`filter-date.mbt`](../../modules/formats/src/xlsx/filter-date.mbt)和 [`xlsx-date-filter.tsx`](../../packages/ui/src/xlsx-date-filter.tsx)。

### 数值排名筛选

`XlsxRankFilter` 从 Wasm/Web XLSX 模块导出，使用 `{ kind: "rank", column, value, top, percent }`。`value` 为整数：项数模式 1–500，百分比模式 1–100；`top=true` 取最大值，false 取最小值。它与值/自定义条件共用 `editSheet({ action: "filter", range, columns })`，替换同列条件，保留其他列并取交集。默认面板提供方向、项数/百分比、数量和应用按钮，保存重开后恢复当前设置。

排名只采用标题后、明确范围内的当前数值及已计算数值公式结果，包含手动和筛选隐藏记录。文字形式的数字、布尔、错误及空白不参与；其他列条件不改变排名样本。重复值按记录计数，阈值上的并列项全部保留。百分比先按数值记录数向下取整，至少一项；项数超过记录数时保留全部数值记录，无数值时全部数据行不匹配。标题与范围外的数字不参与。原生编辑保留现有可见性，使用重新应用按当前值计算阈值；手动隐藏继续保留，SUBTOTAL 的 9/109 及依赖缓存与筛选共享一次历史。

标准 `top10` 的 `val/top/percent` 已接通读取与写回，缺省 top=true、percent=false；已知有限 `filterVal` 可读取，重新应用按当前数值计算，不信任导入阈值。写回保留设置和实际可见行，不持久化派生阈值缓存。采用 [ONLYOFFICE Top10 的方向、百分比与标准字段](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L12306-L12490)及 [1–500 项交互](https://github.com/ONLYOFFICE/web-apps/blob/9c0ca538c3b211052347df09d2a4d6781f023403/apps/spreadsheeteditor/main/app/view/AutoFilterDialog.js)。已检查的 ONLYOFFICE 分支使用 parseFloat 和去重集合；本实现沿已有类型模型只接受数值，并按 [LibreOffice TopTenQuery 的数值记录和包含边界](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/data/table3.cxx#L2487-L2545)保留重复记录，避免将数字文字或不同值个数当作记录数。百分比沿 ONLYOFFICE 的统一向下取整规则。未复制上游源码；实现归 [`filter-rank.mbt`](../../modules/formats/src/xlsx/filter-rank.mbt)。

排名复用当前最多 4096 格、公式工作、输出及历史预算。未知属性/子节点、非法标准参数或非有限缓存值保留原子拒绝；依赖畸形筛选的 SUBTOTAL 也可能在打开时拒绝。工作表复制和改名保留排名条件；整行/整列变换见[行列插入与删除](#行列插入与删除)，局部单元格移位仍受保护。图标与高级筛选继续实施。

### 平均值筛选

`XlsxAverageFilter` 从 Wasm/Web XLSX 模块导出，使用 `{ kind: "average", column, above }`。`above=true` 严格高于平均值，false 严格低于；等于平均值不通过。沿同一 `editSheet({ action: "filter", range, columns })` 替换同列条件，其他列仍取交集。默认筛选面板提供两个按钮，并显示当前方向。

样本使用标题后、范围内的当前数值和已计算数值公式结果，包含隐藏记录及重复值；文字数字、布尔、错误和空白不参与，也不通过此条件。其他列条件不改变样本。无数值时全部数据行不匹配。原生输入保留现有可见性，重新应用后更新阈值、筛选隐藏及 SUBTOTAL 缓存；手动隐藏、结构变换、复制/改名、精确历史和保存重开复用既有事务。清除条件后，原先隐藏的错误值重新参与普通公式计算。

标准 `dynamicFilter` 的 `aboveAverage/belowAverage` 已接通读取和写回；已知 `val/maxVal` 必须有限，重新应用按当前值计算并移除派生缓存。规则参考 [ONLYOFFICE 平均值计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L11728-L11745)和[严格比较](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L11865-L11871)。上游样本使用 parseFloat；本实现沿排名筛选的已有类型模型只接受数值记录，避免隐式转换文字。复用 4096 格、公式工作、输出及历史上限，非有限平均值、未知属性/子节点和其他动态类型继续原子拒绝。实现归 [`filter-rank.mbt`](../../modules/formats/src/xlsx/filter-rank.mbt)及既有筛选读写与面板。

### 自动适配尺寸

同步 Wasm 与 Worker 使用 `autoFit(revision, sheet, first, last, axis, profile)`；`axis` 为 `rows/columns`，索引从 1 开始且包含两端。宿主使用 `SpreadsheetEditor.autoFit(axis)`，作用于执行时选区覆盖的完整行或列，先提交单格草稿。默认尺寸面板提供两个按钮。每项命令独立进入既有历史，保持当前表和选区；重复写入相同源状态不增加 revision。

核心遍历所选轴上实际存在的单元格，使用显示数字格式、已计算值、有效字体与当前列宽测量；不按公式源码长度估算。换行及显式换行沿既有文本布局。行高至少为工作表默认值，并包含当前网格文本内边距，上限 409.5 磅；列宽按 Normal 字体最大数字宽度换算，向上取足像素并保留 1/256 单位，上限 255。无可测内容的轴回到默认尺寸。适配后的行高随内容、有效字体/字号、换行、数字格式、合并及列宽变化重算；bestFit 列随数值、布尔、错误及公式结果扩宽，不因值变短缩列，也不因普通文字编辑扩列。显式调用仍可重新缩放到当前内容。

多列合并不参与列宽测量，多行合并不参与行高测量；单行横向合并的换行文本使用单行字体高度。行高适配保留隐藏行；隐藏列仍按其底层声明宽度测量换行文本，保留隐藏状态。列宽适配显示目标列。修改保留列样式、轮廓、折叠属性、相邻尺寸、单元格源、样式部件、公式缓存与 calcChain，只提交目标工作表的尺寸片段。行记录写入 `customHeight="0"`，列记录写入 `bestFit="1"`。核心在同一候选事务内先更新依赖数值列，再重算行高；派生尺寸与值、缓存、样式共用一次 revision 和历史，撤销不重新测量。手动设置正行高或正列宽切回固定尺寸，手动隐藏列不被数值更新显示。未固定高度的普通默认行，也在带字体的编辑中重算并写入 `ht`。`sheetFormatPr.customHeight` 是行的缺省固定设置，显式 `customHeight="0"` 可覆盖它。未绑定字体时，原本不带 `ht` 的行保留自动声明，可继续仅数据编辑和保存；原本缓存 `ht` 的自动行仍须先绑定字体再修改。尚未编辑的导入普通自动行，缺少缓存 `ht` 时已在首次带字体布局中测量；网格、命中、图片锚点和打印共用派生高度。此过程不写入 XML、revision 或历史，保存保留原行声明；后续编辑继续沿既有适配事务更新源。

首次行高只测量实际含格、可见、未固定且未缓存高度的行，不展开隐式空行。显式 `ht` 的自动行继续使用其缓存，`sheetFormatPr.customHeight` 及单行覆盖沿源读取；多行合并不扩展行高。只读布局复用文字测量，省去仅为写回所需的筛选和扩展资源编辑限制；工作表保护、非文字扩展及其他部件保持。无法测量的未知字符或条件样式保留源高度及既有诊断，缺字体和资源超限明确失败。首次布局沿用 4096 行、4096 次文字格测量、262144 个文本单元和公式工作上限；超过此范围的未缓存工作表仍需更大表的增量测量能力。已有缓存或固定行不占该首次测量预算。查询在存在同 revision、同表的有效网格时报告实际行高，未布局时报告源高度。实现归 [`initial-row-height.mbt`](../../modules/formats/src/xlsx/initial-row-height.mbt)及既有适配器；默认/缓存/隐藏行行为依据 [ONLYOFFICE 行高读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L2932-L2966)和[测量后更新非固定行](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9860-L9900)。

一次事务累计最多 4096 次轴适配、4096 次单元格测量及 262144 个文本单元，不展开空单元格矩阵。字体缺失、富文本/未知样式、保护、未计算公式、未支持的条件规则、未知筛选/表格/透视及扩展资源继续拒绝，保留包和历史。显式适配、成功的网格布局或打印布局会在会话内保留调用者的字体探针和 profile 副本。探针由调用者持有并须保持可用；重新打开后，影响自动轴的编辑须先完成一次带字体 profile 的布局或适配。缺映射、未知布局或预算失败会拒绝整个候选编辑，保留原值、缓存、样式、尺寸及撤销/重做。默认宿主打开时已完成字体布局。尺寸片段使用原有历史和输出预算。核心已检查换行、大小字体、数字显示、合并、隐藏行及零高行、原列区间属性、Normal 与第 0 个单元格样式分离、精确历史、重开和失败；Chromium 已检查默认按钮、草稿与尺寸分项撤销、独立 XML、同步 Wasm/Worker 结果、保存重开及 PDF。实现依据 [ONLYOFFICE 列宽适配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L18321-L18500)、[行高适配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L18504-L18576)及[合并格行高规则](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9820-L9880)。

自动模式更新依据 [ONLYOFFICE 数值列扩宽](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9558-L9610)及[行高失效与重算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9915-L9975)。核心已检查数值/布尔/错误和跨表依赖结果扩列、短值不缩列、行高增减、改窄列后的换行高度、手动固定覆盖、稀疏目标间未知列声明保留，以及字体/文本预算失败的原子性和重开恢复。Chromium 已检查原生输入自动扩列、一次撤销恢复输入和尺寸，换行输入及列宽变化重算行高，固定行高继续输入保持；沿同一流程保存、重开和导出 PDF。

默认行的带字体编辑已检查原生输入、换行、字号、列宽及固定覆盖，源行高与输入共同进入精确历史；清除内容和格式后空白 Normal 行回到默认高度。列宽修改只更新与实际变化列相交的实际行；合并变化按受影响行区间更新，不展开空单元格。未触及行的只读内容和原 XML 保留。普通值/表达式条件规则已按有效差异样式测量，并在依赖变化时重算受影响自动轴，见[条件格式](#条件格式)。未支持的效果继续保护。默认行高变化可改变分页；现有原生输入流程已通过独立 XML 核对两条普通行 18 pt、双行文字行 33 pt，以及 120 pt 可打印高度下的 6 页预览。

### 合并与取消合并

`editSheet(revision, sheet, { action: "merge", range, discard })` 合并指定矩形；`{ action: "unmerge", range }` 取消相交的合并。`range` 是 A1 矩形，单格地址自动扩展到已有完整合并范围。两种操作一次最多 4096 格，工作表最多保留 1024 个不重叠合并范围；合并须完整包含相交的旧合并。重复合并同一范围和取消未合并范围不增加历史。活动表操作选择目标范围，非活动表操作保留当前选择。

`XlsxQuery.merging` 返回查询范围的 `range`、是否相交合并的 `merged`、非左上角非空格数 `discarded`、会丢弃的额外便笺数 `discardedNotes`，以及 `mergeReason/unmergeReason`。合并只有收到布尔 `discard: true` 才能丢弃非锚点内容或额外便笺；否则以 `merge-data-loss` 拒绝。默认属性栏使用同一复选框确认值/公式或便笺损失，即使单元格值全空也须确认便笺损失；宿主沿现有队列先提交草稿。核心重新检查当前数据和保护状态，失败保留已提交包与历史。

合并保留左上角值/公式和各格非边框格式，清除其余值/公式；共享公式存活成员转换为普通公式，依赖缓存和保存计算元数据同步更新。非锚点验证范围从规则中移除，锚点验证和条件格式保留。单元格与合并 XML、验证和缓存一起提交一项有界历史，保留原样式记录和不相关资源，新增边框样式按需派生并复用。取消合并只移除相交合并记录，保留各格内容/格式及计算源；被此前合并丢弃的内容通过撤销恢复。合并后格式查询、编辑及清除可从单格锚点作用于完整范围。

文字与填充沿用左上角样式；边框组合读取起止格的声明，补齐右边和下边。合并时只保留整条外围上各格一致的线型及颜色声明，缺失或不一致时移除整边；内部边框清除。新边框保留主题色、索引色等源声明，不按当前 RGB 固定化。单行和单列遵循同一规则；合并后设置某侧边框只作用于外围对应边，不在内部加线。各格的字体、填充和数字格式保持不变，原样式记录保留源字节。格式查询、网格和打印使用同一边框组合，读取起止格不展开巨大导入合并区。派生样式仍受每类记录数、样式源码长度和历史预算限制；候选总长度超限时也不清除内容、不提交历史。工作表保护、部分旧合并、未知合并属性、超出预算、富文本/未知目标样式，以及未知便笺、非锚点超链接、表格/透视表和扩展资源拒绝合并；取消合并沿自身保护检查，不清理未知资源。合并格格式刷归[格式刷](#格式刷)。核心已检查内容策略、验证、共享公式、依赖、XML 顺序、纯取消合并的部件保真、精确历史和失败；Chromium 已检查键盘范围、确认控件、合并内命中、填充、保存重开和 PDF。操作依据 [ONLYOFFICE 范围合并与验证调整](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L20316-L20706)；边框归并及外围写回遵循同一上游过程。核心已检查四边、内线、单行/单列、不一致边的移除、主题/索引色源声明、精确历史、重复样式复用及预算失败。Chromium 用独立 XML 检查派生边框和原样式记录，网格及打印绘制数据保持颜色、线宽，保存重开及 PDF 沿已有流程。

### 单元格格式编辑

同步 Wasm 与 Worker 使用 `formatCells(revision, patch)`，宿主使用 `SpreadsheetEditor.formatCells(patch)`。命令作用于队列执行时的选区，宿主先提交单格草稿。`XlsxCellFormat` 从 `wasm/xlsx` 和 `web/xlsx` 导出；省略的属性保持原值。字段为 `family`、`size`、`bold`、`italic`、`underline`、`strike`、`script`、`color`、`fill`、`horizontal`、`vertical`、`wrap`、`shrinkToFit`、`indent`、`textRotation`、`numberFormat` 及 `left/right/top/bottom`。`underline` 为单下划线，`strike` 为删除线，均使用布尔值；`script` 为 `baseline | superscript | subscript`。颜色为六位十六进制，空 `fill` 清除填充；四边使用 `{ style: "none" | "thin" | "medium" | "thick" | "double", color }`。字号为 1–409 磅，水平对齐为 general/left/center/right/justify/centerContinuous/distributed/fill，垂直对齐为 top/center/bottom/justify/distributed；数字格式限下节已有集合。宿主先验证新字体键存在于字体 profile。

`XlsxQuery.formatting` 返回这些属性，不同值返回 `null`，并返回 `readOnlyReason` 和所选字体键 `fontKeys`。一次最多 4096 格；依赖无法隔离的公式、受保护表、富文本/未知样式及只覆盖部分合并格的范围继续保护。单格合并锚点的格式查询和编辑扩展到完整合并范围。空白格继承行样式，其次列样式，再使用基础样式；显式单元格样式优先。派生格式保留原共享记录，不改写其他格。样式和目标格共同提交有界历史，缺失样式部件时关系及内容类型一起创建和撤销。仅改格式保留值、公式源、缓存和 calcChain，后续输入保持格样式；重复设置有效状态不新增历史。格式化的空白格参与使用范围和打印。默认 UI 使用可滚动属性栏，保留网格工作区。单下划线、删除线和上下标沿共同字体度量进入网格、自动适配及 PDF；格式刷、单元格片段和三种清除沿相同样式事务保留或移除。条件格式与自定义表格样式支持这些差异属性，直接字体组件的覆盖规则保持。未知、重复、双线及会计下划线继续诊断并保护编辑和输出。共同读取归 [`font-decorations.mbt`](../../modules/formats/src/xlsx/font-decorations.mbt)，原生属性依据 [ONLYOFFICE Font 读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L988-L1030)。Chromium 已检查格式设置、草稿顺序、格式刷、装饰绘制、混合历史、缺失字体恢复、保存重开和格式化公式的 PDF 输出；更多装饰和格式代码仍归 [P11](../p11-xlsx-core.md)。

`horizontal: "centerContinuous"` 从非空单元格向右扩展到同一原生样式索引、相同有效对齐的连续显式空单元格，忽略缩进并在整个范围居中。空文字值视为空格，公式保留独立文字源；非空内容、不同样式、缺失格、合并格或行末中断范围。原单元格内容、矩形、命中、选择及合并记录保持。自动行高按整个范围测量换行，自动列宽保留自然文字宽度。滚动与冻结窗格沿既有裁剪绘制；源格在可见片段之外时补绘其文字，隐藏源列不补绘。打印片段使用相同文字坐标，链接边界按片段裁剪。补绘文字源计入 4096 格与文字预算；范围文字宽度不超过 14400 pt。原生 XF/DXF、API、默认控件、格式复制及精确历史沿既有路径维护。实现归 [`alignment-ranges.mbt`](../../modules/formats/src/xlsx/alignment-ranges.mbt)、[`grid-cells.mbt`](../../modules/formats/src/xlsx/grid-cells.mbt)和 [`autofit.mbt`](../../modules/formats/src/xlsx/autofit.mbt)。同一原生样式要求依据 [Apache POI CENTER_SELECTION](https://poi.apache.org/apidocs/3.17/org/apache/poi/ss/usermodel/HorizontalAlignment.html#CENTER_SELECTION)；ONLYOFFICE 和 LibreOffice 的基础读取仅映射普通居中，未作为跨列绘制基线。

`vertical: "justify" | "distributed"` 将自然排版后的剩余高度平均分到各行之间，首末行贴近已有上下内边距。显式空行参与行数，混合字号保留各行自然高度。只有一行时，`justify` 靠上，`distributed` 居中；高度不足时不增加间距，沿原单元格矩形裁剪。两者不改变换行设置、源文字、字号、公式或自动尺寸。绘制和链接边界使用同一逐行偏移，边界不包含额外行间空白。原生 XF/DXF、格式查询、格式刷、单元格片段、默认控件及精确历史共用既有入口。原生值归 [Microsoft 垂直对齐定义](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.verticalalignmentvalues?view=openxml-3.0.1)，多行间距参考 [LibreOffice 垂直行距](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/editeng/source/editeng/impedit3.cxx#L4425-L4475)及 [Excel 行距说明](https://support.microsoft.com/en-us/excel/change-line-spacing)。实现归 [`cell-text.mbt`](../../modules/formats/src/xlsx/cell-text.mbt)，未复制上游执行代码。

`horizontal: "fill"` 将格式化后的显示值作为整体重复，保留混合字体、装饰及上下文塑形；只添加完整值，首个值超宽时沿原范围裁剪。连续显式空单元格在原生样式索引与有效对齐相同时延续范围，非空内容、公式、缺失格、其他样式及合并格中断延续。跨列范围和范围外源文字补绘复用跨列居中的预算及裁剪，单元格值、公式、选择、命中和合并保持独立。填充忽略缩进并优先于缩小字体适应，保留源字号；开启换行时改用普通类型对齐和换行，不重复。显式多行不重复。自动列宽测量原显示值，自动行高及格式提交检查扩展文字预算，不按重复值撑宽列。扩展沿每块 32767 个 UTF-16 单位/文字片段及现有 262144 单位总预算，文字范围宽度不超过 14400 pt；达到预算而未确定完整边界时拒绝，失败不留下格式或资源变化。原生 XF/DXF、查询、复制、默认控件和精确历史使用原入口；Canvas/PDF 及链接边界使用同一文字坐标。实现归 [`fill-text.mbt`](../../modules/formats/src/xlsx/fill-text.mbt)、[`alignment-ranges.mbt`](../../modules/formats/src/xlsx/alignment-ranges.mbt)及 [`grid-cells.mbt`](../../modules/formats/src/xlsx/grid-cells.mbt)。规则归 [Apache POI FILL](https://poi.apache.org/apidocs/3.17/org/apache/poi/ss/usermodel/HorizontalAlignment.html#FILL)及 [Microsoft 填充对齐](https://learn.microsoft.com/en-us/troubleshoot/microsoft-365-apps/excel/format-cells-settings#alignment-tab)。ONLYOFFICE 的基础读取映射普通两端对齐，重复度量参考 [LibreOffice 完整值重复](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/ui/view/output2.cxx#L1933-L1972)；当前按完整候选实际塑形确定最后一个可放值，未复制上游执行代码。

`horizontal: "distributed"` 对每行的词间空白分配剩余宽度，包括末行和未换行的单行；连续空格合为一个间隙，不拉开词内字母或组合字素。没有可扩展间隙时保留塑形结果并居中，超宽内容沿格裁剪。左右均保留 `indent`，文字区减去两侧缩进。此对齐隐式换行，优先于缩小字体适应；源 `wrapText`、字号、文字、值和公式不变。自动行高按实际换行测量，显式自动列宽测量未扩展的自然宽度并计入两侧缩进。XF/DXF、查询、复制、默认控件及精确历史沿既有路径；Canvas/PDF 与链接边界使用同一逐行坐标。原生词与双侧缩进定义归 [Apache POI DISTRIBUTED](https://poi.apache.org/apidocs/3.17/org/apache/poi/ss/usermodel/HorizontalAlignment.html#DISTRIBUTED)，隐式换行参考 [ONLYOFFICE 分散对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9527-L9530)，末行扩展参考 [LibreOffice 分散末行](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/editeng/source/editeng/impedit3.cxx#L1693-L1700)。实现复用 [`cell-text.mbt`](../../modules/formats/src/xlsx/cell-text.mbt)、[`positioned.mbt`](../../modules/layout/src/positioned.mbt)及既有词间距算法，未复制上游执行代码。

`horizontal: "justify"` 按词间空白扩展非末行，连续空格合为一个间隙；不拉开没有空白的字母。末行保持自然宽度，LTR 靠左，RTL 靠右。普通文字、混合字号、装饰、显式换行与自动换行共用核心图元，换行开关仍独立保存；两端对齐忽略缩进。计算不改变源文字、字号、公式或缓存。自动行高保留文字高度，自动列宽使用未扩展词间距的度量。原生 XF/DXF、混合查询、格式刷及单元格片段复用既有事务，Canvas/PDF 使用同一位置，RTL 的打印与链接边界计入行偏移。旋转等仍待实现。实现归 [`cell-text.mbt`](../../modules/formats/src/xlsx/cell-text.mbt)、[`positioned.mbt`](../../modules/layout/src/positioned.mbt)和 [`justification.mbt`](../../modules/layout/src/justification.mbt)，词间距及末行规则依据 [ONLYOFFICE 词间扩展](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/StringRender.js#L1209-L1242)和[末行方向](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/StringRender.js#L1318-L1325)，未复制上游执行代码。

`indent` 为 0–250 的整数，缺省为 0，省略补丁保留原值，显式 0 清除缩进。每级使用 Normal 字体的三个空格；空格宽先按固定 96 dpi 舍入，再换算为磅，不随当前格字号或缩放改变。按有效左/右对齐向格内缩进，General 依类型选择方向，居中不平移。换行按缩进减少可用宽度，数值溢出检查、自动行高、自动列宽及 PDF 复用同一度量。缩进不自动改变水平对齐。原生 `alignment.indent`、混合查询、格式刷、完整格式快照、片段、条件格式与自定义表格样式沿现有事务维护，保留原值、公式和精确历史。相对缩进继续诊断并保护。实现归 [`cell-text.mbt`](../../modules/formats/src/xlsx/cell-text.mbt)、[`cell-format.mbt`](../../modules/formats/src/xlsx/cell-format.mbt)和 [`autofit.mbt`](../../modules/formats/src/xlsx/autofit.mbt)。距离依据 [ONLYOFFICE Normal 空格](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L619-L622)、[文字位置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L6709-L6725)及[换行和度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9642-L9668)，未复制上游执行代码。

`shrinkToFit` 为布尔值，缺省 false；省略保留，显式 false 关闭。换行优先于缩小。核心按实际格宽与缩进测量普通或混合字号文字，以半磅步长缩小各 run，最低 2.5 pt；源字号低于该值时保持，不放大。达到下限仍超宽时沿格边裁剪，数值保留格式化文字，不替换为井号。网格、自动行高及 PDF 复用同一结果；显式自动列宽测量未缩小文字，后续缩小格不自动撑宽 bestFit 列。显示计算不写回字号、值或源，格式补丁、混合查询、格式刷、完整快照、片段及条件/自定义表格样式沿既有精确历史维护。每次缩小最多 16 轮，沿用字体与文字预算；文字旋转见下节。实现归 [`cell-text.mbt`](../../modules/formats/src/xlsx/cell-text.mbt)及 [`autofit.mbt`](../../modules/formats/src/xlsx/autofit.mbt)。行为依据 [ONLYOFFICE 字体缩小](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/StringRender.js#L1162-L1185)、[换行优先](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L10161)及[列宽和文字度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9568-L9674)，未复制上游执行代码。

### 单元格文字旋转

`XlsxCellFormat.textRotation` 直接使用 OOXML 整数：0 为水平，1–90 为逆时针角度，91–180 按 `90 − value` 转成顺时针角度，255 为逐字素竖排。省略保留，显式 0 恢复水平。查询返回共同值或 `null`；格式刷、完整格式快照、单元格片段、条件格式和自定义表格样式沿既有源事务保留。默认控件提供水平、正负 45/90 度及竖排预设，API 可写全部有效角度。

核心先用原字体、装饰、混合字号及换行规则测量，再变换整个文字块并按旋转外框对齐。数值沿原格式显示，旋转不改写源字号、内容或公式。缩小字体按投影宽度测量，自动行高/列宽采用旋转后的尺寸；竖排按已有扩展字素边界分行，保留跨 run 的组合字符，General 水平对齐居中。实际文字、裁剪和 PDF 链接使用共同图元与边界，格选择和命中保留原矩形。选中行列超过可用视口时，定位起始边缘，避免顶部文字藏在标题后方。竖排派生文字仍受每块 32767 个 UTF-16 单元预算限制，失败保持源和历史。

实现归 [`text-rotation.mbt`](../../modules/formats/src/xlsx/text-rotation.mbt)、[`cell-text.mbt`](../../modules/formats/src/xlsx/cell-text.mbt)及 [`autofit.mbt`](../../modules/formats/src/xlsx/autofit.mbt)。编码参考 [ONLYOFFICE Align.getAngle](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L5277-L5286)，旋转投影与竖排参考 [WorksheetView](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L9556-L9640)及 [StringRender](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/StringRender.js#L974-L1030)。未复制上游执行代码；竖排不等同于东亚竖向字形替换。

### 格式刷

同步 Wasm/Worker 的 `captureFormat(revision)` 返回 `CopiedCellFormat { cells: Required<XlsxCellFormat>[][]; merges: CellRange[] }`；`applyFormat(revision, format)` 将它应用到当前选区。merges 使用相对 cells 左上角的 1 起始行列，包含 top/left/bottom/right；范围须在矩阵内、互不重叠且至少覆盖两格。宿主对应 `SpreadsheetEditor.captureFormat()` 和 `applyFormat(format)`，复制与应用前均提交单格草稿。快照保存逐格有效属性及完整合并范围，不含样式索引或源工作表身份；复制本身不修改文档和历史。MoonBit 的 `apply_format(revision, cells, merges)` 接收同一矩阵和范围。

普通单格目标按源矩形尺寸扩展；选中已有合并格的单格锚点时，源和目标均取完整合并范围。其他目标按源行列顺序重复平铺，格式及合并范围的末块截到目标边界，退化成单格的合并不写入。目标内部的旧合并由快照替换；不含合并的快照会取消目标内部合并。只覆盖部分旧合并时拒绝。格式刷保留包括被合并格遮住的全部值、公式、缓存和共享组；取消合并后仍能读取它们。这与明确丢弃内容的合并命令分别处理。

源和目标各最多 4096 格，矩阵须非空、等宽且携带全部属性；快照及最终工作表各最多 1024 个合并范围。工作表边界、未知属性、字体、只读内容和预算失败均保留已提交文档。格式、合并元数据及已有自动适配合为一次有界历史，重复应用不新增历史；移除最后一个合并时删除空容器。样式复用按元素/属性的命名空间与名称、值及子结构判断，忽略前缀和属性顺序，原有源记录保持原样。实现归[格式快照](../../modules/formats/src/xlsx/format-painter.mbt)、[合并平铺](../../modules/formats/src/xlsx/format-merge.mbt)和[格式事务](../../modules/formats/src/xlsx/format-edit.mbt)。

默认 UI 的格式刷单击后对下一个新选区应用一次；双击或在按钮上按 Shift+Enter 锁定，可连续应用及切换工作表。Esc 或再次点击按钮取消，替换文档时释放状态。复制/平铺参考 [ONLYOFFICE 的目标扩展与格式复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21916-L21960)，合并替换、底层内容保留和末块裁短沿其[格式及合并复制路径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22578-L22616)。单次/锁定/取消参考 [GenOffice 格式刷](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/sheets/src/renderer/format-painter.ts)。

### 清除单元格

同步 Wasm/Worker 使用 `clear(revision, mode = "contents")`，宿主使用 `SpreadsheetEditor.clear(mode = "contents")`。`XlsxClearMode` 从 `wasm/xlsx` 和 `web/xlsx` 导出，取值为 `contents/formats/all`。缺省和原生 Delete/Backspace 保持清除内容；默认 UI 分别提供清除单元格、清除格式和全部清除。宿主先提交单格草稿；输入与清除各占一项历史。

`formats` 将目标格恢复为工作簿内置 Normal 样式，派生或复用 cellXF，保留原共享样式、值、公式、缓存和 calcChain。两种格式清除都会取消完整合并，并从选区清除既有条件格式。`all` 还清除值和公式、选区内验证规则及完整覆盖的超链接；部分覆盖的超链接保持原范围；被清除的共享公式组将存活成员展开为普通公式，并重算受影响依赖。行列尺寸与范围外单元格保持原样，内容变化沿既有保存路径更新计算元数据及共享字符串计数。

一次最多 4096 格，单格合并锚点扩展到完整合并范围。`XlsxQuery.normalFont` 返回 Normal 样式的字体键；宿主在格式清除前检查对应 profile。Normal 不等同于第 0 个 cellXF，也不依赖本地化样式名。未知模式、受保护内容、缺失字体和预算失败不提交清除。部分覆盖的合并、需要平移且无法解析的规则公式，以及未知规则结构继续保护；未支持的非空扩展、表格/透视表资源、线程批注及未知便笺也继续保护；传统便笺的清除归[单元格便笺](#单元格便笺)，已识别迷你图的清除归[单元格迷你图](#单元格迷你图)。规则之外的资源不推断所有权。

条件格式和验证的 `sqref` 从各原矩形扣除选区，保留不相交区域，最多留下 4096 个矩形。条件格式按范围外接矩形左上角定位，验证按第一个 `sqref` 区域定位；锚点变化时复用核心公式解析器平移相对引用，保持绝对/混合引用、跨表引用和字符串。条件公式、验证的两个公式及公式阈值一并更新，越界引用变为 `#REF!`。锚点不变时保留公式源；清空全部范围才删除规则，验证容器计数同步更新。规则计算、显示与编辑范围分别归[条件格式](#条件格式)和[数据验证](#数据验证)。范围扣除参考 [ONLYOFFICE 条件规则清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L13347-L13386)与[验证范围清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/DataValidation.js#L1068-L1088)；验证公式源位置参考 [LibreOffice 导入](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/filter/oox/worksheethelper.cxx#L1096-L1119)。核心已检查四块残留、多个原范围、混合引用、字符串、阈值越界、上限拒绝和精确历史；Chromium 通过默认按钮清除并用独立 XML 检查范围与公式，保存重开后可继续输入。

核心已检查 Normal 派生、取消合并、条件格式/验证/链接清除、共享公式、依赖缓存及精确混合历史；Chromium 已检查原生草稿后清除格式、全部清除、独立 XML、保存重开和 PDF。行为参考 [ONLYOFFICE 范围清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21093-L21175)和[清除选项](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L16669-L16695)。

### 条件格式

普通 `cellIs`、`expression`、`colorScale`、`dataBar`、`top10`、`aboveAverage`、`duplicateValues`、`uniqueValues`、`containsBlanks`、`notContainsBlanks`、`containsErrors`、`notContainsErrors`、`containsText`、`notContainsText`、`beginsWith`、`endsWith` 和 `timePeriod` 规则已在核心计算。值规则支持八项比较；数值、文字和布尔保持类型区别，文字比较忽略大小写，空格按零或空文字比较。表达式沿现有公式语法求值，相对引用以全部 `sqref` 的外接左上角为原点，保留绝对/混合及跨表引用；`ROW/COLUMN` 使用当前格。表达式的错误结果不命中，未知函数或引用给出诊断。

`priority` 越小越优先；命中的高优先级属性覆盖低优先级的相同属性，其余属性组合。命中 `stopIfTrue` 后不再使用后续规则，即使该规则没有差异样式。`dxfId` 从工作簿当前样式部件解析，不写回单元格样式。支持字体名、字号、粗斜体、文字色、纯色/无填充、四边 thin/medium/thick/double/none、现有数字格式及基本对齐/换行。颜色复用主题、索引及 tint 解析；差异填充优先采用 `bgColor`，与 [ONLYOFFICE fixForDxf](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/model/WorkbookElems.js#L3502-L3509)一致。差异字体仍须显式提供 profile 映射。

`XlsxConditionalFormat` 包含 `kind`（上述十七类）、`operator`、`formula1`、`formula2`、`stopIfTrue` 和部分属性 `format: XlsxCellFormat`。表达式的 operator 为空；仅 between/notBetween 使用第二个公式。颜色刻度的 stops、数据条的 bar、排名的 rank、平均值的 average、文字的 text 和相对日期的 timePeriod 见下文。`XlsxQuery.conditionalFormats` 返回当前表按优先级排序的全部普通规则，每项包含 `priority`、空格分隔的 A1 矩形 `ranges`、`rule` 和 `readOnlyReason`，容器也有保护原因。规则原点随完整 ranges 定位，不随当前选区变化。

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

排名使用 `kind: "top10"` 和 `rank: { rank, percent, bottom }`。`rank` 为 1–1000 的整数；percent 为 true 时限 1–100，取数字数量乘百分比后向下取整，至少保留一个数字。bottom 选择最小值，否则选择最大值；边界并列全部命中。平均值使用 `kind: "aboveAverage"` 和 `average: { above, equal, stdDev }`。above 选择高于或低于平均值，equal 包含等于最终阈值；stdDev 为 0–3 的整数，按总体标准差把阈值向相应方向移动。语义依据 [ONLYOFFICE 排名和均值计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7636-L7707)及[阈值比较](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L917-L931)。

两类统计规则的 operator、formula1、formula2 为空，不带 stops/bar，分别只带 rank 或 average；其他规则省略这两项，MoonBit 使用 None。统计取完整规则范围内的当前数字和公式结果，包含隐藏行，不重复统计交叠范围；空白、文字、布尔和错误不参与且不命中。阈值沿有界稀疏缓存计算，输入后重算，网格、颜色操作、自动尺寸和 PDF 共用有效样式。默认面板提供全部统计参数及既有差异外观，保留停止规则、原生 SpreadsheetML 属性、复制后的独立规则范围、精确历史和重开。实现归 [conditional-statistics.mbt](../../modules/formats/src/xlsx/conditional-statistics.mbt)。

重复值和唯一值分别使用 `kind: "duplicateValues"` 与 `kind: "uniqueValues"`。operator、formula1、formula2 为空，不带 stops、bar、rank 或 average；format 和 stopIfTrue 沿既有差异样式规则。完整范围内按当前未格式化逻辑文字判断重复，包含隐藏行及公式结果，相交范围只统计实际格一次。文字区分大小写；数字与相同逻辑文字可同组，布尔、错误使用其逻辑文字，空白与空字符串不参与也不命中。数值的显示格式不改变重复性。行为依据 [ONLYOFFICE 重复键](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L3165-L3170)、[规则匹配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7734-L7746)及[未格式化值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L16253-L16267)。默认面板可创建和切换这两类规则；缓存按当前规则与计算上下文重建，计数文字消耗公式工作预算。复制保留独立规则范围、外观和精确历史，保存重开仍可编辑。实现归 [conditional-duplicates.mbt](../../modules/formats/src/xlsx/conditional-duplicates.mbt)。

空白/非空白使用 `containsBlanks/notContainsBlanks`，错误/无错误使用 `containsErrors/notContainsErrors`。它们的 operator、formula1、formula2 为空，不带 stops、bar、rank 或 average。空白包含未存储格、空字符串及全部由 ASCII 空格组成的逻辑文字；制表符、不换行空格和全角空格均为非空白。错误按当前逻辑类型判断，错误文字字符串属于无错误；无错误规则也匹配空白。实际输入和公式结果变化后，网格、自动尺寸和打印沿现有差异样式重新计算。语义依据 [ONLYOFFICE 空白与错误判断](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7804-L7850)。

这四类原生规则可含一份互操作公式；核心按规则类型判断，API 查询保留空的 formula1/formula2。未修改规则保留原源，写回或复制时按当前范围锚点生成 `LEN(TRIM(A1))=0`、`ISERROR(A1)` 等公式；范围修改同步更新锚点，复制使用目标范围。生成形式依据 [ONLYOFFICE 规则公式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L1381-L1392)。这是规则的写回形式，单元格函数范围仍归[显示与计算](#显示与计算)。默认面板提供四种类型和既有外观，不要求输入这些公式。创建、修改、复制、精确历史和重开归 [conditional-predicate.mbt](../../modules/formats/src/xlsx/conditional-predicate.mbt)及既有规则事务。

`kind: "colorScale"` 使用 `stops` 描述两个或三个颜色节点，operator、formula1、formula2 为空，format 为空对象，stopIfTrue 为 false。每个 `XlsxConditionalStop` 包含 `kind`、字符串 `value` 和六位 RGB `color`。节点类型为 min、max、num、percent、percentile 或 formula；min/max 的 value 为空，百分比和百分位范围为 0–100。普通值/公式规则不带 stops；MoonBit 的 ConditionalFormat 对应空数组。

颜色刻度使用完整规则范围内实际数字和已计算公式结果，忽略空格、文字、布尔和错误，不重复统计相交范围。不按可见窗口重新取范围，也不读取旧公式缓存作为当前结果。percent 按最小/最大值计算，percentile 按排序后的 `(n-1)*p` 位置线性插值；公式阈值在规则原点求值一次。阈值按数值排序，颜色保持节点顺序；超过端点时截定，所有值相同时使用末端颜色，无数字或阈值公式出错时不着色。RGB 插值使用 [ONLYOFFICE CGradient](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/model/ConditionalFormatting.js#L2637-L2680)的 256 步及通道向下取整，百分位参考 [getPercentile](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/model/FormulaObjects/statisticalFunctions.js#L356-L375)。

默认面板可在两/三节点间切换并编辑各节点的类型、值/公式和颜色；中间节点默认使用第 50 百分位。阈值与统计按当前计算缓存，编辑后重新计算，网格和 PDF 复用同一最终填充，不改基础单元格样式。只改范围时保留原规则源；修改阈值也保留未变的主题色/索引色节点。颜色刻度不创建 dxf，沿既有规则历史、局部清除与保存重开。统计、排序及阈值文本共同受规则工作预算限制，失败不留下部分缓存或半项编辑。实现归 [`conditional-scale.mbt`](../../modules/formats/src/xlsx/conditional-scale.mbt)。

数据条使用 `kind: "dataBar"` 与 `bar: XlsxDataBar`。operator、formula1、formula2 为空，format 为空对象，stopIfTrue 为 false，不带 stops。bar 包含 minimum、maximum、六位 RGB color、showValue，以及整数 minLength/maxLength；条长范围为 0–100 且 minLength 不大于 maxLength。minimum/maximum 为 `XlsxConditionalThreshold { kind, value }`，沿用颜色刻度的六种阈值及字符串值。MoonBit 对应 DataBar、ConditionalThreshold 和 ConditionalFormat.bar；其他规则的 bar 为 None，JSON 省略。

普通 SpreadsheetML dataBar 默认显示值，最短/最长条长为 10%/90%。核心复用完整稀疏范围的当前数值、公式阈值和有界缓存，按值计算条长，超出阈值时截定。均匀值使用最短条长，无数字或阈值公式出错时不绘制；多条数据条使用首个有效的高优先级规则，并遵守更高优先级的停止规则。沿 [ONLYOFFICE legacy data bar](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/view/WorksheetView.js#L6273-L6385) 的条长、内边距和渐变端色计算，末端向白色混合 82.8%；全部非正数时从右侧绘制。普通规则采用同色、无轴线的旧格式语义，混合正负值仍沿最小/最大值计算。x14 的负值颜色、轴线、方向、实心条及边框设置尚未接入，保留源并保护相关输出与修改。

默认面板提供两个阈值、条色、显示值开关和最短/最长条长；新增、完整修改/删除、优先级及局部清除沿同一规则事务。只改阈值时保留未变的主题/索引色，不分配 dxf 或基础单元格样式。showValue 为 false 只隐藏网格/PDF 文字，值、公式、查询的逻辑 display 和原生输入保留；自动尺寸仍按实际值及有效文字格式计算。实现归 [conditional-bar.mbt](../../modules/formats/src/xlsx/conditional-bar.mbt)。

共享绘制使用 `GradientRectangle(rect, stops)` 和 `gradientRect` 命令，均为从左到右的 RGBA 渐变。`stops` 含 2–32 项 `{ position, color, opacity }`；位置须有限、位于 0–1 并按非递减顺序排列，颜色为六位 RGB，`opacity` 须有限并位于 0–1。同位置色标形成突变，首尾外侧延续端点颜色。数据条仍使用两个不透明端点，反向条交换颜色和起点。矩形坐标须有限、绝对值不超过 10^9，宽高非负。Canvas 按顺序添加色标，PDF 使用经矩形裁剪的轴向 shading，以 Type 3 函数拼接 Type 2 插值；非全不透明色标使用同位置灰度 shading 与 Luminosity 软遮罩，复用已有变换/裁剪并在局部作用域恢复状态。输出声明 PDF 1.4；PDF 相同色标序列共享资源，最多 4096 组，保留总输出预算。背景先绘制，随后数据条、边框和文字。实现归 [layout/gradient.mbt](../../modules/layout/src/gradient.mbt) 与 [pdf/write-gradient.mbt](../../modules/formats/src/pdf/write-gradient.mbt)。

网格、查询 `display`、自动适配和打印使用同一有效样式。依赖格输入或公式结果改变时，自动行/数值 bestFit 列按条件样式重算，与原编辑共享一次历史；固定尺寸保持原值。规则 XML、`dxf`、基础格式和范围外部件保留，保存重开继续计算。合并格按锚点求值。

图标集使用 `kind: "iconSet"` 与 `icons: XlsxIconSet`。支持全部 [17 种基础标准集](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.iconsetvalues?view=openxml-3.0.1)：`3Arrows`、`3ArrowsGray`、`3Flags`、`3Signs`、`3Symbols`、`3Symbols2`、`3TrafficLights1`、`3TrafficLights2`、`4Arrows`、`4ArrowsGray`、`4Rating`、`4RedToBlack`、`4TrafficLights`、`5Arrows`、`5ArrowsGray`、`5Rating`、`5Quarters`，包含 reverse、showValue、percent 和与图标级数一致的三至五个 thresholds；每个阈值使用 `{ kind, value, greaterOrEqual }`，类型和值沿既有六种阈值。operator、formula1、formula2 为空，format 为空对象，stopIfTrue 为 false，不带其他规则元数据。MoonBit 对应 IconSet 与 ConditionalIconThreshold。完整稀疏范围只统计当前数字和公式数字结果，按原生节点逆序比较，等值由 greaterOrEqual 控制；reverse 反转命中的图标，均未命中时使用索引零。percent 保留原生属性，各节点的 kind 决定计算方式。比较依据 [ONLYOFFICE getIndexRule](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L999-L1011)。

默认面板提供图标类型、阈值、等值、反向及显示值开关。切换级数时将草稿阈值重置为均匀百分比，级数不变时保留已编辑阈值。箭头的四级顺序为下、右下、右上、上，五级在中间增加向右；灰色使用中性填充，颜色沿既有红/黄/绿。方向顺序依据 [ONLYOFFICE 图标映射](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L3047-L3061)。原生读取、命令和跨工作簿规则剪贴板均校验级数与阈值数量，不能用五级名称配三个阈值。Canvas/PDF 复用有界矢量路径，文字为图标预留空间，自动尺寸包含图标。仅显示图标时，逻辑值和输入保留；可见格的 accessibleText 保留格式化值供无障碍网格使用。原生保存、精确历史和重开沿既有条件规则事务。符号提供带圆框和独立笔画两种外观，评级按原生级别增加四根蓝色柱，四分圆按顺时针从空心递增到实心；四色圆点和交通灯按各自顺序绘制。级别依据 [ONLYOFFICE 标准映射](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L3047-L3063)，新增几何归 [conditional-icon-symbols.mbt](../../modules/formats/src/xlsx/conditional-icon-symbols.mbt)。x14 自定义图标及扩展属性保持诊断与保护。实现归 [conditional-icon.mbt](../../modules/formats/src/xlsx/conditional-icon.mbt) 和 [conditional-icon-paint.mbt](../../modules/formats/src/xlsx/conditional-icon-paint.mbt)。

规则及差异样式各限 4096 项，公式限 8192 UTF-16 单位；网格、整项打印或编辑适配共享 1048576 次规则/公式工作预算，不展开整列空格。未知规则、属性、装饰或扩展样式保留源并诊断；相关打印或适配拒绝，避免输出缺失效果。查询中的条件格式预算失败转成诊断，避免成功提交后被返回查询误报为失败；实际绘制和输出仍检查预算。扩展数据条、自定义图标与其他规则、边框仅改颜色及更广差异格式仍待实现。实现归 [`conditional-format.mbt`](../../modules/formats/src/xlsx/conditional-format.mbt) 和 [`conditional-style.mbt`](../../modules/formats/src/xlsx/conditional-style.mbt)，值比较参考 [ONLYOFFICE cellIs](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/cell/model/ConditionalFormatting.js#L835-L913)。

四种文字规则使用 `containsText/notContainsText/beginsWith/endsWith` 和 `text: string`，MoonBit 对应 `text: Some(value)`。operator、formula1、formula2 为空，不带 stops、bar、rank 或 average；其他类型不带 text。按当前未格式化逻辑值忽略大小写比较，`*`、`?` 和 `~` 为普通文字。包含支持数字及布尔的逻辑文字，开头/结尾的非空文字只匹配文字值。包含不匹配空值和错误；不包含取反，因此可以匹配错误及空值。空文字的开头/结尾匹配所有非错误值。按 [ONLYOFFICE text operand](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L758-L830) 的规则，匹配文字恰为 TRUE/FALSE 时直接使用其布尔值，优先于上述文字比较。

原生 text 属性定义文字规则；缺失此属性的公式变体继续诊断和保护源。导入接受省略或与类型对应的 operator，API 统一为空。原生公式作为有界互操作缓存，保存未修改源；创建、复制或改变范围时生成当前锚点的 SEARCH/LEFT/RIGHT 公式，转义文字引号和 SEARCH 通配符。text 最多 8192 UTF-16 单位，生成公式仍须满足既有 8192 单位上限。默认面板可创建和修改四种规则与文字，复用差异样式、停止规则、当前输入重算、精确历史和保存重开。网格、自动适配和 PDF 沿同一有效样式。实现归 [conditional-text.mbt](../../modules/formats/src/xlsx/conditional-text.mbt)，原生公式依据 [ONLYOFFICE 生成入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L1361-L1380)。

相对日期高亮使用 `kind: "timePeriod"` 与 `timePeriod`。`conditionalDatePeriods` 提供 `yesterday/today/tomorrow/last7Days/lastWeek/thisWeek/nextWeek/lastMonth/thisMonth/nextMonth`，MoonBit 为 `timePeriod: Some(period)`。operator、formula1、formula2 为空，不带 text、stops、bar、rank 或 average；其他类型不带 timePeriod。日、周和月使用完整公历区间，周从星期日开始，最近七天包含今天和之前六个公历日。区间含起点、不含终点，时间小数保留；沿工作簿 1900/1904 系统换算。按 [ONLYOFFICE 当前值匹配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7854-L7865)，数值及文字开头的十进制数字可参与，包含指数和后续文字；空值、布尔、错误及没有数字前缀的文字不命中。

原生 timePeriod 定义规则，零个或一个公式为互操作缓存。创建、范围修改和复制写回当前锚点的 TODAY/FLOOR/WEEKDAY/MONTH/YEAR 公式，普通单元格中的未知函数仍受保护。默认面板提供十种期间，复用差异样式、停止规则、当前公式结果、精确历史、保存重开和同一 Canvas/PDF 样式。日期沿[宿主日历上下文](#相对日期筛选)提供；缺少日期时保留源并保护需要计算的显示、编辑和输出。区间依据 [ONLYOFFICE getTimePeriod](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L693-L756)，原生公式依据[同文件生成入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/ConditionalFormatting.js#L1301-L1338)。实现归 [conditional-date.mbt](../../modules/formats/src/xlsx/conditional-date.mbt)。

### 单元格超链接

`XlsxQuery.hyperlink` 返回 `{ target, mixed, readOnlyReason, navigationReason }`。target 为共同地址，未链接或混合选区为 null；mixed 区分混合范围。范围查询使用矩形运算，不展开整列空格。支持普通 `hyperlink`、外部关系及内部 location；未知属性/容器、组合外链与 location、未解析关系或相交的重复链接保护相关修改。

`HYPERLINK(link_location[, friendly_name])` 已进入普通公式求值、依赖重算及缓存。省略显示值时返回地址文字；给出显示值时保留文字、数值、布尔和错误类型，空白变为 0。两个参数均支持单格或按公式位置交叉取值的一行/一列引用；不能取唯一值的矩形返回 `#VALUE!`。参数错误先取地址错误，错误结果不生成公式链接。IF、IFERROR、IFNA 的已选结果、INDEX 标量和 XLOOKUP 未命中结果保留其公式链接；算术、普通文本函数及引用结果单元格只取得值，不继承地址。规则依据 [ONLYOFFICE HYPERLINK](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/lookupandreferenceFunctions.js#L1443-L1493)、[引用取值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L3424-L3442)及[范围交叉](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L18912-L18919)。

同格已有普通链接时，普通链接优先，沿 [ONLYOFFICE 命中顺序](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L12482-L12579)保留其独立来源。缺少普通链接时，查询、显式打开及 PDF 使用当前公式结果地址；未选分支和错误结果不激活公式链接。合并区域由主格拥有链接，其他源格不重复激活。直接链接面板对公式拥有的格显示修改原因，继续允许显式导航；地址和显示值通过原有公式栏修改。普通链接的设置/移除保留公式，移除显式普通链接后重新显示公式目标。公式不创建或清理普通链接节点、关系与字体样式，原文和精确历史沿既有事务保存。

公式地址仍执行既有 HTTP、HTTPS、mailto 与内部范围校验；不安全或过长地址保留公式显示值，在链接查询中给出原因并保护打印，不发出请求。未解析的内部目标保留导航原因，未打印的目标沿现有规则不生成注释。每次计算与缓存复用后的全部公式地址合计最多 1048576 个 UTF-16 单位；地址求值及本次打印的链接合并分别共享既有公式工作预算，超限不提交。实现归 [`formula-hyperlink.mbt`](../../modules/formats/src/xlsx/formula-hyperlink.mbt)、[`formula-evaluate.mbt`](../../modules/formats/src/xlsx/formula-evaluate.mbt)和 [`calculation.mbt`](../../modules/formats/src/xlsx/calculation.mbt)。数组公式、动态引用及更多函数继续实施，未复制上游执行代码。

`SpreadsheetEditor.editSheet({ action: "hyperlink", range, target })` 复用 `XlsxSession/Client.editSheet(revision, sheet, change)`。HTTP、HTTPS、mailto 或 `#范围/定义名称` 最多 2048 UTF-16 单元；内部目标须解析到现有可见表中的一个矩形，例如 `#'团队''s Data'!$A$1:B2` 或 `#Local`。核心使用现有公式词法、名称作用域与引用解析。null 移除范围内链接，保留单元格值、公式、富文本和直接格式；不自动套用链接颜色或下划线。显示文字继续通过原生输入编辑。

修改局部范围时拆分既有链接，范围外目标、提示、display、局部命名空间及间隙注释保留。单格命中合并区域时作用于整块；其他选区须包含相交的完整合并区域。新增关系复用同目标，不改写共用关系或清理旧关系；首次关系部件与链接 XML 合为一次历史。源、范围片段、历史及输出预算失败不提交。

默认面板提供地址、应用、混合移除及显式打开，原生草稿沿既有队列提交。打开文件、查询、设置链接和打印均不请求外链；外部打开使用新窗口及 `noopener noreferrer`。内部打开调用 `{ action: "openHyperlink", range, sourceRevision }`，核心检查当前选区与修订后定位，不增加历史。无效或隐藏目标返回 navigationReason，保留源并拒绝跳转。

已有改名、复制、删除工作表及行列/单元格结构事务继续更新普通链接范围与内部引用；名称改名同步内部 location，外部文件的 location 保持原值。删除定义名称时移除因此失去矩形目标的已知链接，包括名称别名链；其他已失效引用保留导航原因。保存重开支持继续编辑，链接和关系与原生输入、结构修改可精确混合撤销。PDF 已保留普通单元格的外链及内部目标注释，范围见下段。HYPERLINK 复用下文相同的打印注释路径，绘图对象链接继续实施。

既有 PDF 导出自动将本次实际打印的 HTTP、HTTPS、mailto 文字链接写为无边框注释。矩形来自核心文字块的实际位置，按单元格和纸张裁剪，保留对齐、换行、RTL、缩放、重复标题、多区域及多表页序。隐藏行列和空白文字不生成注释，不扩张打印范围。重叠链接或只覆盖部分合并格的链接保护打印；原有未知元数据和地址校验保持。内部 location 复用当前表、跨表及作用域名称解析，目标矩形的左上角映射到本次输出的实际格位置；合并格使用所属主格，空白目标也可定位。重复标题和多个区域中的同格使用首次打印位置。未输出、隐藏、缺失或不能解析为单一矩形的目标只保留文字。ONLYOFFICE [表格打印](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L6734-L6744)省略内部链接；本 SDK 扩展沿既有 [PDF 页目标语义](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/PdfWriter.cpp#L1207-L1227)输出 `GoTo/XYZ`。导出不改工作簿、选区、历史或未保存状态，也不请求链接地址。

核心打印结果的 `PositionedDocument.links` 随页面一起缓存，PDF 复用[现有链接注释](#docx-pdf-文字链接)序列化。每次最多 65536 个注释矩形、8388608 次链接与文字片段比较；目标解析共用本次打印的 1048576 项公式工作预算，继续执行既有打印及 PDF 字节预算。实现归 [`print-links.mbt`](../../modules/formats/src/xlsx/print-links.mbt)与 [`print.mbt`](../../modules/formats/src/xlsx/print.mbt)，未复制上游执行代码。

实现归 [`hyperlink-query.mbt`](../../modules/formats/src/xlsx/hyperlink-query.mbt) 和 [`hyperlink-edit.mbt`](../../modules/formats/src/xlsx/hyperlink-edit.mbt)。范围查找、设置/移除及保留直接格式的语义参考固定 [ONLYOFFICE Range hyperlinks](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L20760-L20849)，复用第一方范围拆分、关系与历史事务，未复制上游代码。

### 单元格便笺

`XlsxQuery.note` 返回查询单元格的 `{ address, exists, text, author, reason }`。单格或一个完整合并区域可编辑，合并区域使用左上角身份；多格返回选择原因。支持传统 comments XML 和普通 VML 便笺框，线程批注继续保护。查询覆盖显式 `sheet/range`，不改变活动选区。

`XlsxSession/Client.editSheet(revision, sheet, { action: "note", cell, text, author? })` 和 `SpreadsheetEditor.editSheet(change, sheet?)` 创建、修改或删除便笺。`cell` 是单个 A1 地址，`text: null` 删除；新文字必须非空，最多 32767 UTF-16 单元，CRLF/CR 归一为 LF。新建须显式提供非空 `author`，最多 255 单元且不含控制字符；修改保留原作者。空文本便笺可读取和删除，显式文字修改继承首个源 run 的字符属性。SpreadsheetML 转义由核心统一编码，字面的 `_x0041_` 不会变成 `A`。

默认面板复用 `EditorOptions.commentAuthor.name` 创建作者，未提供时仍可修改和删除已有便笺。应用前原生单元格草稿沿既有队列提交，值、公式、格式和计算结果保持。便笺输入以当前文档/工作表/单元格绑定；切换单元格更新输入，未应用的面板草稿不写入文档。同格单元格输入与保存保留尚未应用的便笺文字；绑定文字在布局阶段同步，避免挂载后的同步覆盖输入。显示文字与 VML 外观不进入单元格值、查找、CSV 或默认静态 PDF。面板继续提供便笺编辑；网格角标和悬停/选中提示见下段。

网格使用 R0 绘制橙色逻辑右上角标，RTL 镜像到左侧，尺寸随缩放变化；空格和合并锚点也可显示。位置与裁剪由核心沿用行列尺寸、隐藏、冻结和合并几何。`XlsxViewport.notes` 返回可见 `{ address, author, text, rect }`，rect 使用 point 的已裁剪画布坐标；跨冻结窗格的合并格可有多个可见片段，源便笺不重复。一次最多 4096 个片段及 5 Mi 文字/作者单元，含最多四窗格重复。仅便笺的远端单元格扩展网格滚动范围，不扩展默认打印区域。未知便笺继续沿既有保护和诊断处理，不暴露部分记录。

Web 复用核心矩形显示悬停或选中便笺的作者与纯文字提示，不改变选区、修订、历史或保存源。键盘选中格关联便笺描述，网格语义也提供作者和文字；Escape 隐藏提示，切换目标可重新显示。长文字可在有界提示中滚动；悬停提示内仍可读取。布局、工作表或修订变化后更新提示，释放实例时解除监听。角标和提示不进入静态 PDF，也不修改 VML 外观。角标参考 [ONLYOFFICE drawCommentCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L642-L690)，实现归 [`notes-grid.mbt`](../../modules/formats/src/xlsx/notes-grid.mbt)及 [`spreadsheet-notes.ts`](../../packages/web/src/spreadsheet-notes.ts)。

首次创建把 comments、VML、工作表 `legacyDrawing`、关系和内容类型合为一项精确历史。普通备注框使用标准 `ObjectType="Note"` 及从零开始的 Row/Column、八项 Anchor。导入只有 comments 而无 VML 时，新增便笺会补齐全部现有便笺的框；若已有未解析的 `shapeId`，保护该创建。修改只替换文字正文，保留原作者、其他便笺、外围注释、局部命名空间和 VML 位置/外观。删除移除文字与对应框，最后一条删除后保留空部件和作者列表。每表最多 4096 条、合计 1 Mi 文字单元及 4096 个作者，并继续受包、输出与历史预算约束。

复制表创建独立 comments/VML 部件并重映射关系；副本可继续编辑。改名和删除沿已有工作表事务，删除仅回收独占部件和内容类型。新增部件按稳定顺序写入 ZIP，删除/撤销不改变相同状态的保存字节。重复地址、作者缺失、未知/不匹配的 VML、控件/图片、未知文字/扩展、共享/外部部件、保护、旧修订和预算失败原子拒绝。普通合并及取消合并的便笺归属见下段。未知 VML 保留未渲染诊断并拒绝打印；普通便笺输出按默认不打印批注处理，非默认批注打印设置继续保护。

整行/整列插删和四向单元格移位复用既有 `AxisChange`。便笺随所属格移动，范围外不变；删除所属格时移除该便笺及对应 VML shape，保留作者、空部件和关系。插入不得把空格上的便笺推出工作表。核心同步 comment 的 `ref` 和对应 `ClientData` 的 Row 或 Column，仅改动受影响轴的文字；Anchor 矩形、偏移、外观/标志、guid/shapeId、正文与其他源保留。范围插入后选区仍是插入区域，可定位到移后的便笺格；不单独修改既有选区规则。部件、值/公式、规则与选择共用一次精确历史；无法安全替换的 VML 文字或预算失败不提交。归属规则参考 [ONLYOFFICE updateCommentsDependencies](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L709-L838)，实现归 [`notes-transform.mbt`](../../modules/formats/src/xlsx/notes-transform.mbt)。

普通行/列排序复用已有稳定位置映射，便笺与所属格一起移动，空值格也参与；标题、隐藏轴和范围外便笺保留。核心同步 `ref` 与 VML Row/Column，正文、作者和弹框外观保持。四向填充、自动序列与收缩填充保留每格原有便笺，不复制源便笺或覆盖目标便笺。清除内容/格式保留便笺；全部清除删除选区内文字与对应 VML shape，包括只有便笺的空格，保留范围外便笺、空部件与作者。各操作与值/公式/格式共同提交一次有界历史，支持精确撤销与重开；未知资源继续原子保护。语义参考 [ONLYOFFICE sortComments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L840-L863)、[自动填充](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22180-L22690)及[清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L16657-L16703)，实现复用同一便笺源编辑器与已有操作事务。

合并复用 [ONLYOFFICE mergeComments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L1395-L1431) 的源顺序选择：先取范围内首条便笺，后续便笺的行不更大且列更小时替换保留项。保留项移到合并左上角，其余文字与 VML shape 删除；单条便笺移动不产生便笺损失。`discardedNotes` 返回额外便笺数，范围 0–4095，沿现有 `discard` 显式确认；非锚点值/公式仍独立计入 `discarded`。保留项的正文、作者、shape 身份及框外观不变，范围外便笺保持。便笺、合并几何、单元格与派生样式共用一次精确历史；合并后修改便笺使用左上角身份。取消合并保留现有便笺和资源，不恢复已确认丢弃的便笺；撤销可精确恢复它们。未知/共享资源、无法替换的 VML 坐标或预算失败继续原子保护。

矩形剪切移动复用[单元格剪切移动](#单元格剪切移动)事务。同表便笺沿原地址映射，跨表保留完整富文本、作者及已有 guid，并在目标作者表中匹配或追加作者。VML 框及所用形状类型带原外观和命名空间迁入，分配目标内未占用的身份，同步 `shapeId`、`ref` 与 Row/Column；原 Anchor、偏移和外观保持。目标缺少 comments/VML 时创建独立部件与关系，只有文字资源的导入便笺按已有创建规则补齐框。目标范围内的旧便笺被覆盖，范围外原节点保持；源端保留空部件、作者与关系。已移入的便笺可继续修改、删除或移回。身份冲突、无法匹配的原 `shapeId`、未知/共享资源及预算失败整体拒绝，文字和框源的迁移合计最多 2 Mi UTF-16 单元，其他便笺及事务预算继续生效。归属依据 [ONLYOFFICE moveRangeComments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L562-L586)，实现归 [`move-notes.mbt`](../../modules/formats/src/xlsx/move-notes.mbt)及共用的 [`notes-import.mbt`](../../modules/formats/src/xlsx/notes-import.mbt)。

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

自定义条件和边界公式复用既有公式解析、引用与计算，读取整次候选写入和受影响计算结果。字面列表按逗号拆分、移除每项开头的空格并按原文比较；单行/单列列表引用保留值类型。未知公式、名称/扩展引用、未知规则属性及扩展验证继续保护相关输入。每表最多检查 4096 条规则，单个列表最多 4096 项或单元格，验证共享 1048576 个求值步骤预算；规则公式各不超过 8192 UTF-16 单元。失败发生在缓存写回、自动尺寸、源提交和历史之前，整块粘贴不会留下部分值。

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

公式支持数值、字符串和布尔常量，括号、一元正负、`+ - * / ^`、后缀百分比 `%`、文本连接 `&`、比较、A1 单格/矩形、整行/整列范围、绝对/混合引用、带引号的跨表引用，以及 `SUM/AVERAGE/MIN/MAX/COUNT/IF/AND/OR/NOT/IFERROR/IFNA/ISBLANK/ISNUMBER/ISTEXT/ABS/INT/MOD/ROUND/ROUNDUP/ROUNDDOWN/SQRT/POWER/PRODUCT/MEDIAN/MODE/MODE.SNGL/LARGE/SMALL/SUMSQ/SUMPRODUCT/DEVSQ/VAR/VAR.S/VARP/VAR.P/STDEV/STDEV.S/STDEVP/STDEV.P/LEN/LEFT/RIGHT/MID/TRIM/UPPER/LOWER/CONCAT/CONCATENATE/TEXTJOIN/FIND/SEARCH/SUBSTITUTE/EXACT/REPT/DATE/YEAR/MONTH/DAY/TIME/HOUR/MINUTE/SECOND/DAYS/COUNTA/COUNTBLANK/COUNTIF/COUNTIFS/SUMIF/SUMIFS/AVERAGEIF/AVERAGEIFS/MINIFS/MAXIFS/INDEX/MATCH/VLOOKUP/HLOOKUP/XLOOKUP/ROW/COLUMN/ROWS/COLUMNS/SUBTOTAL/HYPERLINK`。范围端点可以反向，核心按矩形解释。显式省略的函数参数作为空白处理，仍检查各函数参数数量。

`&` 将两个值按普通公式文字规则连接，布尔使用 TRUE/FALSE，空白使用空文字，公式错误按左侧优先传播。它低于加减、高于比较，同级从左到右；括号保留明确的计算顺序。一行/一列引用按公式位置取唯一值，其余非单值矩形返回 `#VALUE!`。它与 HYPERLINK 复用 [`formula-range.mbt`](../../modules/formats/src/xlsx/formula-range.mbt) 中的标量取值，与文本函数共用 32767 个 UTF-16 单位及 1048576 单位工作预算；超长结果为 `#VALUE!`，工作量超限拒绝整次编辑。共享公式、填充、工作表改名与重开沿普通 token/引用路径，字符串常量内的表名或 `&` 保持文字。规则参考 [ONLYOFFICE cConcatSTROperator](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L4793-L4832)。例如 `HYPERLINK(A1&"#details","查看")` 使用拼接后的地址，保留既有安全导航及 PDF 规则；实现复用 [`formula-parser.mbt`](../../modules/formats/src/xlsx/formula-parser.mbt) 和 [`formula-evaluate.mbt`](../../modules/formats/src/xlsx/formula-evaluate.mbt)，未复制上游执行代码。

后缀 `%` 将数值除以 100，可重复使用，例如 `50%%` 为 0.005；单行/单列引用沿相同的标量取值规则。`^` 直接复用 POWER 的当前标量求值器和有限值、负数实根及错误规则；按所选 ONLYOFFICE 基线，`0^0` 为 1。优先级由高到低为前缀正负、`%`、`^`、乘除、加减、`&` 和比较；同级二元运算从左到右，`2^3^2` 为 64，`2^(3^2)` 为 512，`-2^2` 为 4。共享公式和填充将 `%` 保存到其已平移操作数之后，例如 `((A2)%^2)`，保留精确历史及重开计算。运算符保留原格数字格式：已有百分比格式可将 0.5 显示为 50%，General 继续显示 0.5；自动格式推断继续实施。规则参考 [ONLYOFFICE 百分比与乘方](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L4663-L4718)及[正负号优先级](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L4503-L4506)，实现沿 [`formula-parser.mbt`](../../modules/formats/src/xlsx/formula-parser.mbt)、[`formula-evaluate.mbt`](../../modules/formats/src/xlsx/formula-evaluate.mbt)和 [`formula-shift.mbt`](../../modules/formats/src/xlsx/formula-shift.mbt)，未复制上游执行代码。

`SUMPRODUCT` 接受静态范围及其中的一元、算术、比较和文本连接表达式。名称、共享与跨表引用沿普通依赖重算；稀疏整列按已有单元格和逻辑空白区域求值，沿用工作量预算。标量函数子表达式仍使用原有求值规则，通用数组常量和数组函数形式继续实施。参数规则参考 [ONLYOFFICE SUMPRODUCT](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L5645-L5743)：数字文字转换，布尔和非数字文字计为零；单格空白引用返回 `#VALUE!`，空白范围元素计为零。顶层参数尺寸按依次增长的最大行列检查：后续较小参数返回 `#NUM!`，较早的小参数在后续坐标补空白。错误按行列及参数顺序传播。范围表达式内部的两个范围必须同尺寸；标量可参与逐元素运算。空白区域批量累计不承诺与 Excel 的浮点逐项累加位级一致。实现归 [`formula-sum-product.mbt`](../../modules/formats/src/xlsx/formula-sum-product.mbt)。

整列 `A:A`、`$A:B` 和整行 `1:1`、`$1:2` 可带工作表限定并使用反向端点。行号只接受十进制整数，范围受 1048576 行、16384 列约束；混合行/列/单格端点拒绝。内部用一个有界矩形表示，未覆盖维度在复制时固定；原公式源码保持，复制及名称展开输出对应行列记法和 `$` 标记。依赖保留区间，聚合及条件函数查询实际单元格，空白计数按逻辑面积扣除非空值。线性查找在大范围内仅检查已有单元格及各空白区间的首个搜索位置，保留正反向、错误与近似候选规则；小范围保持直接读取，二分查找沿原路径。全部沿用工作量及输出限制，保留空项的超大连接仍可能原子拒绝。

结构编辑沿现有 [ONLYOFFICE 范围变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L675-L768)；范围末端贴住工作表上限，起点不固定在第一行/列。例如在 A 列前插列时，名称中的 `Sheet1!$2:$2` 变为 `Sheet1!B$2:XFD$2`，之后按名称调用位置求值，越界产生 `#REF!`。范围记法参考 [ONLYOFFICE getName](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L983-L1019)，稀疏值和空白数量参考 [cArea](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L1195-L1240)及[countCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L1326-L1335)。数组结果仍归 P14。

AND/OR 接受数值和布尔，忽略引用内的文本与空白；没有有效值时返回 `#VALUE!`。文字常量返回 `#VALUE!`，不沿用数学函数的数字转换。稀疏范围只访问已有单元格，不展开整张表；即使已有确定的布尔结果，范围和后续参数中的错误仍参与，范围内按行列顺序保留首个错误。NOT 接受布尔、数值、空白及 TRUE/FALSE 文字，其他文字返回 `#VALUE!`。三项类型判断不转换数字文字，区分空白格与空字符串；当前使用标量参数，多格范围返回 `#VALUE!`。公式结果引用空白格时计算为数值 0。

IF、IFERROR、IFNA 只求值选中的结果分支，依赖仍包含全部声明引用。IFERROR 捕获公式错误值，IFNA 只捕获 `#N/A`；两者不吞未知函数、循环、引用解析失败或资源超限。新输入及生成的 IFNA、CONCAT、TEXTJOIN、DAYS、XLOOKUP、VAR.S、VAR.P、STDEV.S、STDEV.P、MODE.SNGL、MINIFS、MAXIFS 按 OOXML 写入对应 `_xlfn.` 函数前缀，读取也接受这些前缀；只替换函数 token，保留同名工作表和文字常量。查询继续返回实际公式源。

ABS 返回绝对值，INT 向负无穷取整；MOD 按 `n - d * floor(n / d)` 计算，零除数返回 `#DIV/0!`。三类舍入按有限 Double 的十进制表示处理，ROUND 的半值远离零，ROUNDUP 远离零，ROUNDDOWN 朝零；位数的小数部分朝零截断。正负位数、进位及 `ROUND(1.005,2)=1.01` 使用同一路径，不先乘十进制倍率。精度至少 324 时保持原值；截断后的精度小于 -308 时，非零 ROUNDUP 返回 `#NUM!`，其余返回 0。结果非有限也返回 `#NUM!`，不按任意精度分配字符串。

SQRT 计算非负平方根，负数返回 `#NUM!`。POWER 接受两个标量；零的负幂为 `#DIV/0!`，零的零次幂沿所选参考返回 1。负底数的非整数幂沿 [ONLYOFFICE POWER](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L3435-L3462) 计算负候选根，再以反向幂的整数舍入结果核对底数；不成立时为 `#NUM!`。非有限结果为 `#NUM!`，下溢可为 0。标量类型转换沿既有规则。

PRODUCT 按参数顺序及引用内的行列顺序相乘，重复/重叠引用按次数计入。引用中的数字文字可转换，布尔、空白与其他文字忽略，引用错误传播；直接布尔和数字文字转换，直接非法文字返回 `#VALUE!`，空参数忽略。没有数值返回 0；中间溢出立即返回 `#NUM!`，不会被后面的零消除。行为依据 [ONLYOFFICE PRODUCT](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L3574-L3665)。

MEDIAN 对实际数值排序，偶数项取中间两项的平均值。沿 [ONLYOFFICE MEDIAN](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L8541-L8620)，引用中的文字、布尔、空白及错误均忽略；直接布尔参与，直接文字忽略，直接错误及空参数返回 `#VALUE!`。没有数值也返回 `#VALUE!`，平均值的非有限结果为 `#NUM!`。PRODUCT/MEDIAN 支持跨表、名称展开和整行/列的稀疏引用，不展开空矩阵；隐藏及筛选行仍参与。遍历与排序预付现有公式工作预算，资源超限整体回滚，IFERROR 不吞资源失败。四项均参与实际依赖、缓存及精确历史，不再使用未计算保护。实现归 [`formula-numeric.mbt`](../../modules/formats/src/xlsx/formula-numeric.mbt)及 [`formula-product-median.mbt`](../../modules/formats/src/xlsx/formula-product-median.mbt)。

MODE/MODE.SNGL 返回出现次数最多的数，并列时取较小值；只有互不重复的数时返回 `#N/A`，没有数值返回 `#VALUE!`。两者复用已有有界数值收集与排序；引用中的文字、布尔、空白和错误均忽略，直接文字也忽略，直接布尔、错误和省略参数返回 `#VALUE!`。现代名称按标准 `_xlfn.MODE.SNGL` 读写。规则依据 [ONLYOFFICE MODE](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L8785-L8880)及[现代别名](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L8956-L8966)。

LARGE/SMALL 接受数据与标量 k，分别返回第 k 大/小值，重复值分别占位。引用文字与空白忽略，引用错误传播；LARGE 将引用布尔转为 1/0，SMALL 忽略它们。k 沿现有数值转换；沿所选 ONLYOFFICE 规则，LARGE 将正小数 k 向上取整，非正 k 先返回 `#N/A`，超过样本数为 `#NUM!`。SMALL 的范围形式只接受有效整数 k，否则返回 `#NUM!`，范围错误先传播。LARGE 要求显式区域数据，直接标量或单格引用返回 `#NUM!`；SMALL 的标量/单格形式可转换数值，且 k 必须为 1。规则依据 [ONLYOFFICE LARGE](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L7710-L7790)及 [SMALL](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L10540-L10632)，实现归 [`formula-order-statistics.mbt`](../../modules/formats/src/xlsx/formula-order-statistics.mbt)。

四种名称均参与普通静态依赖、名称/共享/跨表重算、原生公式栏、缓存与精确历史。隐藏和筛选行仍参与，整行/列按已有单元格稀疏读取。遍历及排序消耗现有工作预算，超限不被 IFERROR 吞掉；未修改的导入公式源保留。数组与动态引用继续沿既有保护边界。

SUMSQ 按参数及引用内行列顺序累计平方和，重复引用按次数计入。直接布尔和数字文字转换，非法文字为 `#VALUE!`；引用中的文字、布尔和空白忽略。沿固定 [ONLYOFFICE SUMSQ](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L5732-L5797)，单格引用中的错误忽略，显式范围（含 `A1:A1`）及直接错误传播。没有数值返回 0，平方或累计非有限返回 `#NUM!`。跨表、名称、共享公式及整行/列稀疏引用复用已有依赖、工作预算、缓存和精确历史；不再使用未计算保护。实现归 [`formula-sum-squares.mbt`](../../modules/formats/src/xlsx/formula-sum-squares.mbt)。

DEVSQ 返回离均差平方和，接受 1–255 个参数。引用仅统计数值，忽略文字、布尔、空白及错误；直接布尔转 1/0，直接文字（含数字文字）忽略，直接错误或空参数返回 `#VALUE!`。无数值返回 0，非有限累计返回 `#NUM!`。参数规则依据固定 [ONLYOFFICE DEVSQ](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L5743-L5822)，核心采用下述稳定累计替代上游直接均值算法。普通 DEVSQ 包含隐藏和筛选行；数组和动态引用仍未支持。实现归 [`formula-deviation-squares.mbt`](../../modules/formats/src/xlsx/formula-deviation-squares.mbt)。

VAR/VAR.S 返回样本方差，VARP/VAR.P 返回总体方差。普通引用、名称、跨表、共享公式及稀疏整行/列沿现有依赖和缓存事务；引用中的文字、布尔及空白忽略，错误传播。直接布尔转为 1/0；按固定 ONLYOFFICE 规则，VAR 忽略直接文字和空白，VAR.S/VARP/VAR.P 将它们作为 0，数字文字也不按数值转换。样本少于两个数、总体没有数值时返回 `#DIV/0!`；非有限结果返回 `#NUM!`。普通方差包含隐藏和筛选行及嵌套 SUBTOTAL；可见行汇总仍使用 SUBTOTAL。

STDEV/STDEV.S 返回样本标准差，STDEVP/STDEV.P 返回总体标准差，共用方差累计并对结果开平方。按固定 ONLYOFFICE 规则，样本形式只统计引用中的数值，忽略引用和直接参数中的错误；直接数值文字、布尔和省略参数按现有数值转换，无法转换的文字忽略。样本没有数值成员时返回 0，仅有一个时返回 `#DIV/0!`。总体形式沿 VARP 的转换和错误规则：引用非数值忽略、错误传播，直接布尔转 1/0、文字和省略参数为 0；没有数值时返回 `#DIV/0!`。普通标准差包含隐藏和筛选行；现代名称读写标准 `_xlfn.` 前缀，保留未改的导入源。非有限累计返回 `#NUM!`，继续遵守现有工作预算。依据 [ONLYOFFICE STDEV/STDEV.S](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L10693-L10773)及 [STDEVP/STDEV.P](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L10841-L10938)。数字文字使用当前核心的数值转换；地区格式文字及数组仍待兼容扩展。

方差、标准差、DEVSQ 和 SUBTOTAL 共用平方偏差累计。先减去首个值，再逐项更新均值和平方偏差，避免大偏移下丢失相邻值的差，也避免直接作两个大平方和之差。规则依据 [ONLYOFFICE VAR/VARP/VAR.P/VAR.S](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L11619-L12008)。读取接受 `_xlfn.VAR.S`/`_xlfn.VAR.P`，新输入和生成的这两个现代名称带标准前缀；导入未改的源片段保留。独立结果、类型、空样本、错误、较大偏移、溢出、前缀、工作预算、重算和精确历史由定向用例检查；数组、动态引用及更广统计函数继续扩展。实现归 [`formula-variance.mbt`](../../modules/formats/src/xlsx/formula-variance.mbt)和 [`formula-subtotal.mbt`](../../modules/formats/src/xlsx/formula-subtotal.mbt)。

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

MINIFS/MAXIFS 在结果范围中返回满足全部条件的最小值/最大值，复用现有条件、稀疏范围及依赖图。结果范围和每个条件范围必须具有相同行列数。两项沿 ONLYOFFICE 先将条件转换为文字；空文字或空白条件也接受数值 0，显式 `"="` 仍只匹配空白及空文字。错误条件参数返回 `#VALUE!`，字面的错误文字仍可匹配相应错误值。只选择结果范围中的数值，忽略其文字、布尔、空白和错误；没有数值时返回 0。包含隐藏行，整列只遍历已有单元格。名称、跨表依赖、填充平移、精确历史和缓存沿同一事务。读取普通及 `_xlfn.` 名称，新输入和生成公式写回标准前缀。实现归 [`formula-conditional.mbt`](../../modules/formats/src/xlsx/formula-conditional.mbt)，依据 [ONLYOFFICE MAXIFS/MINIFS](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js#L8313-L8542)。

条件范围遍历、文字比较和通配符共用现有公式工作预算；超限整体回滚，IFERROR 不吞资源失败。实现参考固定 [ONLYOFFICE 统计函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js)、[条件匹配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L12325-L12512)与[条件求和](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js#L5310-L5402)。结果范围投影及错误读取同时对照 [LibreOffice 条件聚合](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/tool/interpr1.cxx#L5871-L6094)。单格空文字计数与结果范围形状沿 [COUNTBLANK 合同](https://support.microsoft.com/en-us/excel/functions/countblank-function)及 [SUMIF 合同](https://support.microsoft.com/en-us/excel/functions/sumif-function)，不沿用旧参考中单格/区域及结果矩阵尺寸的不一致。

ROW/COLUMN 返回显式引用的左上角行列，省略参数时返回公式自身位置；ROWS/COLUMNS 返回矩形行列数量，不遍历单元格。四项位置函数只校验引用身份，不依赖引用内的值，`A1=ROW(A1)` 不产生值循环。公式来源位置属于核心求值上下文，不由宿主选区决定。

INDEX 当前返回一个单元格的值，支持二维行列索引、单行/单列简写及标量输入；索引朝零截断，越界返回 `#REF!`，负索引返回 `#VALUE!`，单一区域的 area_num 必须为 1。选中空白格返回 0。零行/列仅在对应维度本来为 1 时返回单格，其余数组结果仍未支持。MATCH 接受一维引用，0 为首个精确匹配，1 为升序的最后一个不大于项，-1 为降序的最后一个不小于项；省略时为 1。精确模式支持整格通配符和转义，不把数字文字与数值等同。

VLOOKUP/HLOOKUP 在首列/首行查找，返回指定列/行的标量值；省略 range_lookup 时沿升序近似规则，false 使用首个精确或通配符匹配。无匹配返回 `#N/A`，结果索引小于 1 返回 `#VALUE!`，超出表格返回 `#REF!`。近似匹配的重复键沿最后一个符合项，精确匹配沿首项。

XLOOKUP 当前使用同形的一维查找和返回引用，默认精确查找，支持 -1/1 的最近较小/较大项及 2 的通配符模式。search_mode 为 1/-1 时正向/反向扫描，为 2/-2 时按升序/降序二分；二分不接受通配符模式。二分和旧式近似模式要求输入已有正确排序，不替用户排序。未命中时才求值 if_not_found；省略或显式空参数返回 `#N/A`，查找值、查找过程和选中结果中的错误保留类型，不被回退值覆盖。

查找共享既有文字比较与工作预算，二分直接读取稀疏地址；线性或通配符工作超限整体回滚，IFERROR 不吞失败。值依赖目前保留声明的范围和回退分支；动态引用、引用形式 INDEX、整行/列返回及其他数组结果仍待扩展。实现参考固定 [ONLYOFFICE 查找引用函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/lookupandreferenceFunctions.js)及独立[位置与查找用例](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/tests/cell/spreadsheet-calculation/formula-tests/lookupAndReferenceTests.js)。当前范围是标量计算，不授予完整数组或动态引用兼容。

逻辑、类型和扩展函数前缀参考 [ONLYOFFICE 逻辑函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/logicalFunctions.js)、[类型函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/informationFunctions.js)及[公式序列化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L3586-L3587)。范围迭代和错误参与与固定 [LibreOffice ScAnd/ScOr](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sc/source/core/tool/interpr1.cxx#L1234-L1413)交叉核对。独立用例覆盖类型、空白、错误、跨表重算、缓存、精确历史及失败；默认公式栏已检查组合公式、依赖变化、独立 XML、保存重开和 PDF。

首次打开计算支持的公式，编辑只重新求值受影响公式。首次有效事务同步与已计算结果不同的导入缓存，包括未受本次输入影响的陈旧缓存；无编辑打开不写回。语法、越界引用、未支持公式、新建循环和预算超限整体拒绝；除零等是带类型的公式结果。共享公式按锚点派生；编辑命中组时有界展开该组，其他组保留。

结构化/外部/三维引用、数组、动态数组、易变函数及迭代计算未支持。依赖无法确定、函数参数语义未核实或存在原有循环时，整个工作簿只读。公式不访问网络、宏或宿主脚本。

DEVSQ 已真实求值，接入名称、共享公式、跨表、稀疏引用及普通重算、缓存和历史事务。原 DEVSQ 专用未计算链及其隔离检查已移除。核心只把实际求值结果放入 `calculated`，缓存不参与新的公式、条件格式、验证或筛选计算。每格 `calculationReason` 在已计算/普通值时为空，未知公式只读时说明工作簿保护原因。默认公式栏显示原因；有缓存时显示缓存，缺缓存显示未计算。选区含未计算公式时，计数仍可读，四项汇总均为 null 并给出原因。

新增未支持公式及 CSV/TSV 中的未支持公式转换在提交前拒绝。导入含未知函数、INDIRECT/OFFSET、CELL 等环境/格式查询、自定义函数及其嵌套时继续整本只读，保留原始源码和缓存。

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

含受支持原生表的工作簿使用同一名称面板及命令，可新增、修改、改名、删除和定位名称。名称定义可引用 `Sales[Total]` 等已支持的结构化范围；候选验证、依赖计算和内部链接检查使用同一表上下文。改名同时更新原生 `calculatedColumnFormula/totalsRowFormula`，按所属工作表判断局部优先和显式限定，不改写列标题、结构化选择器或字符串常量。名称与现有表名冲突时拒绝，列标题不占用名称空间。删除保留表内公式源，再按剩余作用域计算。表定义、单元格、名称、缓存及选择共用一次精确历史；未知表资源、数组公式源、循环和预算失败保持原状态。

名称面板可从当前选区生成带表名的绝对矩形，也可输入常量或表达式。命令先提交原生单元格草稿；定位按当时焦点解析相对定义。常量和计算表达式不能作为矩形定位，隐藏目标表须先显示。导入的未支持语法或系统定义保留并显示保护原因，普通命令不改变隐藏属性。多区域、整行整列、作用域迁移和更广定义兼容另行扩展。

实现归 [`named-definitions.mbt`](../../modules/formats/src/xlsx/named-definitions.mbt)与 [`name-edit.mbt`](../../modules/formats/src/xlsx/name-edit.mbt)。作用域、定义上下文和相对偏移参考 [ONLYOFFICE DefName](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L457-L512)及 [cName](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L2173-L2262)。管理事务和改名绑定参考 [editDefinesNames](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L1086-L1125)及 [changeDefName](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L2261-L2275)。

结构变换参考 [ONLYOFFICE 名称公式通知](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L559-L574)及[按保存引用移动](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L10152-L10281)，实现复用 [`axis-reference.mbt`](../../modules/formats/src/xlsx/axis-reference.mbt)和 [`axis-metadata.mbt`](../../modules/formats/src/xlsx/axis-metadata.mbt)。

### 结构化表与引用

原生表行排序复用 `editSheet({ action: "sort", range, ... })`。选区完全位于一张表内时，核心扩展为整张表的数据行和全部列，固定标题与总计。默认排序面板同步这些边界；多键、文字自定义列表和颜色沿[区域排序](#区域排序)规则。排序前冻结当前公式键和可见位置，手动或筛选隐藏记录留在原位；保留计算列模板、值/公式例外、富文本、便笺、链接和直接格式。候选计算后重新应用相关原生表及普通筛选，同步 SUBTOTAL 和最终值校验。

排序状态写入所属表根节点 `sortState`，移除竞争的嵌套筛选排序状态，保留无关源。已支持的排序范围、键及颜色差异样式随整轴和工作表复制维护；源、值、缓存与可见性合为精确历史，支持保存重开和打印。原生表保持整行排序；跨越表边界的选区及未知元数据继续保护。方向规则沿 [ONLYOFFICE 原生表排序设置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L25584-L25608)的锁定方向。已有排序的范围调整见下文。实现归 [`table-sort.mbt`](../../modules/formats/src/xlsx/table-sort.mbt)，参考 [ONLYOFFICE 表数据排序范围](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L2574-L2659)。

`XlsxQuery.tables` 返回当前工作表的原生表定义，包括 `id`、`name`、A1 `range`、`headerRow/totalRow`、`columns`、`style`、`filter` 和 `readOnlyReason`。每列返回稳定的 `id`、`name` 及可空的 `formula/totalFunction/totalLabel/totalFormula` 原生设置；表和列身份来自所属 XML，不从位置或显示文字重新生成。`filter` 沿用 `XlsxFilterState` 的范围、条件、值目录和保护原因。核心校验表关系、名称、列数、重复身份、重叠范围和合并区域，单元格仍由原有稀疏工作表持有。

公式支持 `Sales[Amount]`、表内 `[Amount]`、`[@Amount]`、`[[First]:[Last]]`，以及 `#Data/#Headers/#Totals/#All/#This Row`。裸表名表示数据区域，标题和总计按定义排除；连续行段可组合。列名中的结构字符使用单引号转义。引用解析为现有单元格依赖和有界范围，保留原公式文字；跨表公式、名称引用，以及计算列和总计格中已有的单元格公式随普通数据重算。普通数据修改不自动补齐既有区域中缺失的计算列公式；扩展新行的补齐见下文。缺表返回 `#NAME?`，缺列或不存在的行段返回 `#REF!`，数据区域外的当前行引用返回 `#VALUE!`。不连续行列组合继续保护。

`editSheet({ action: "renameTable", id, name })` 修改表名称。`editSheet({ action: "renameTableColumn", id, column, name })` 修改列标题；`column` 是稳定列身份。表名遵循已有名称规则，表名和列名最多 255 个 UTF-16 单元。核心同时更新所属表部件、表头、工作簿名称及各表公式，按词法标记替换，保留字符串常量、列身份、表关系、样式定义和无关源。默认结构化表面板调用相同命令，先提交原生草稿。源、缓存和选区进入一项精确历史，相同名称不新增历史。

`editSheet({ action: "createTable", range, name })` 将当前工作表的矩形区域转为原生结构化表。区域至少包含标题和一行数据；首行作为标题，不插入新行。核心按已支持的单元格数字格式取得标题文字，空白使用 `Column1` 等唯一名称，重复标题追加从 2 开始的数字，并避开现有标题。标题公式转换为当前结果文字；共享公式标题继续保护。非标题单元格的值、公式和直接格式保持，已有结构化引用随新定义重算。

创建使用 `TableStyleMedium2` 行条纹，分配独立表/列身份、部件路径及关系，并添加内容类型和工作表引用。标题修改、源、缓存、资源及选区合为一项精确历史；已有表及无关部件保持。创建后可沿既有路径编辑数据、输入结构化公式及改名。默认面板使用当前选区，原生草稿先提交。重叠表、合并区域、普通筛选、名称冲突、受保护源或资源预算失败整体拒绝。标题超过 255 或总名称预算时拒绝，不静默截断。实现归 [`table-create.mbt`](../../modules/formats/src/xlsx/table-create.mbt)及与便笺共用的 [`sheet-resource.mbt`](../../modules/formats/src/xlsx/sheet-resource.mbt)。空白和重复标题规则参考 [ONLYOFFICE 标题生成](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L5545-L5627)。

`editSheet({ action: "resizeTable", id, range })` 调整行数及左右列边界。新范围保留首行、部分原有列和至少一行数据。保留列按原单元格位置保留身份与元数据；新列分配身份，并从原位置的逻辑值生成唯一标题。空白或重复标题使用空闲 `ColumnN`。有标题的表同步写入新列标题，无标题表保持首行数据。移出表的普通数据与直接格式留在原坐标；指向移除列的已绑定公式写为 `#REF!`，重新扩入同名列也不恢复旧引用。移出范围的普通局部结构化引用补上表名，保持归属；当前行引用在数据区外返回 `#VALUE!`。

已有总计行随末行移动：核心清除原总计行，在保留列的新位置恢复原文字/公式，目标已有内容时整体拒绝。原生 `calculatedColumnFormula` 为新增数据行中的空白格补公式，相对 A1 引用按首个数据行偏移，结构化引用保留；既有值或公式例外不覆盖。一次补齐最多涉及 4096 格，沿既有公式、输出及历史预算。此入口不新增计算列定义或总计设置，也不向整张工作表插入行列。

核心同步表范围、排除总计行的筛选范围、工作簿名称和各表依赖缓存。新范围完全包含原范围时，恰好覆盖整表或单列的条件格式按新末行延长，保留原锚点；缩小时不裁剪原规则。样式、自动适配和打印沿现有表定义派生。默认面板提供范围框与同一命令，先提交原生草稿；相同范围不增加历史。表排序或未知列/筛选元数据、跨边界的共享局部公式、未绑定的规则引用及超限候选继续保护。实现归 [`table-resize.mbt`](../../modules/formats/src/xlsx/table-resize.mbt)及 [`table-resize-references.mbt`](../../modules/formats/src/xlsx/table-resize-references.mbt)，范围与列身份依据 [ONLYOFFICE changeRefOnRange](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L8579-L8641)，条件格式范围依据 [af_changeTableRange](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L22631-L22708)。

`editSheet({ action: "tableColumnFormula", id, column, formula })` 创建或重填计算列。字符串公式可带开头的 `=`，相对 A1 引用从首个数据行偏移，结构化引用保留。命令改写所选列的全部数据格，包括已有值和公式例外；标题、总计及直接格式保持。`formula: null` 只移除原生模板，保留现有单元格公式，随后可按普通数据格编辑。相同模板且各格公式等价时不新增历史。每次最多 4096 个数据格、公式最多 8192 个 UTF-16 单元，沿现有 1048576 公式工作预算。实现归 [`table-column.mbt`](../../modules/formats/src/xlsx/table-column.mbt)。

`editSheet({ action: "tableTotals", id, visible })` 显示或隐藏总计行。显示在表下方增加一行，不插入整张工作表的行；目标须为空且不与合并、表或普通筛选重叠。首次没有总计设置时，多列表的首列使用 `Summary`，末列按数据选择求和或非空计数；单列表仅生成聚合。隐藏缩小表范围、清除原总计格，保留设置和直接格式；缺失或不同于设置的导入总计内容先保存为标签或自定义公式。再次显示恢复这些设置，显式“无”不会恢复默认聚合。表筛选范围始终排除总计行。

`editSheet({ action: "tableTotal", id, column, total })` 修改可见总计行的所选列。`XlsxTableTotal` 支持 `{ kind: "none" }`、`{ kind: "label", text }`、`{ kind: "formula", formula }` 和 `{ kind: "aggregate", function }`。聚合为 `sum/average/count/countNums/min/max/stdDev/var`，分别使用已有 `SUBTOTAL` 的 109/101/103/102/105/104/107/110；标准差与方差使用样本口径。自定义公式最多 8192 个单元，标签最多 32767 个单元。修改总计保留计算列模板。全部公式及总计元数据累计最多 1048576 个单元；多次总计元数据写入受同量级源处理预算限制，超限整体拒绝。

计算列与总计命令沿同一事务更新原生定义、单元格、依赖和缓存，支持精确历史、保存重开及现有打印。默认面板调用相同命令并先提交原生草稿。共享/数组公式源、未知表/筛选元数据、非法结果、验证失败和输出预算失败均保留原状态。总计实现归 [`table-total.mbt`](../../modules/formats/src/xlsx/table-total.mbt)及 [`table-totals.mbt`](../../modules/formats/src/xlsx/table-totals.mbt)。默认设置及聚合映射参考 [ONLYOFFICE 总计行](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L10063-L10140)；其中数值计数沿现有 `SUBTOTAL(102)` 补齐。原生计算列和总计设置分别保留。

`editSheet({ action: "tableFilter", id, columns })` 设置原生表筛选。`id` 是表身份；范围由核心取标题和数据区域，排除总计行，不能由调用方另传。`columns` 沿用[普通筛选](#值筛选)的值、自定义、排名、平均值、日期组、跨年日期、相对日期和颜色条件；列号仍是从 1 开始的工作表列号。多列取交集，空条件保留筛选范围并显示全部数据。`tableFilterClear/tableFilterRemove/tableFilterReapply` 同样携带 `id`，分别清除条件、移除原生筛选节点和按当前值重新应用。查询不重写导入源，普通数据输入也不自动重新筛选。

条件和隐藏来源写入所属表部件的原生 `autoFilter`，行隐藏和 `sheetPr/filterMode` 写入工作表。同一工作表上的多个原生表及普通筛选分别保留条件和筛选隐藏记录；实际隐藏取各筛选与手动隐藏的并集。清除或移除一个筛选保留其他来源。行高和分组折叠/展开同步手动来源，`SUBTOTAL` 的 1–11 与 101–111 继续区分筛选隐藏和手动隐藏。源、可见性、缓存和依赖合为一次精确历史，保存重开、工作表复制、网格和 PDF 复用同一结果。导入文件无法辨别重叠隐藏原因时，沿用普通筛选的来源限制。

默认结构化表面板复用现有条件控件，原生草稿先提交。筛选需要标题和至少一行数据，范围最多 4096 格、条件最多 256 列；文本、公式工作、输出及历史沿普通筛选预算。当前表目录共享 1048576 次工作预算，超限目录返回原因。未知条件、扩展、注释/处理指令、保护或预算失败保留原源、选区和历史。原生表筛选已随范围调整和整行/整列插删同步，具体规则见下文；表内行排序见下文。实现归 [`filter-visibility.mbt`](../../modules/formats/src/xlsx/filter-visibility.mbt)及既有筛选读写，参考 [ONLYOFFICE 表/区域的共同筛选入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L1054-L1135)和[按表身份重新应用](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L1405-L1445)。没有复制上游代码。

筛选中的 `resizeTable` 保留仍在范围内的条件列和按钮标记，列号继续绑定原工作表列；移出列的条件随列移除。扩大后按当前值检查新增数据行，缩小后释放移出行的筛选隐藏，保留手动隐藏及其他表/普通筛选的来源。总计行仍不参加筛选，迁移目标须为空，已有值/公式例外沿范围调整规则保留。已有排序状态也可调整范围。扩大时保留仍有效的历史排序范围及源，不自动重排新增数据。缩小时把表根节点排序限制在新数据区，把筛选内排序限制在新筛选范围；裁剪各键范围，移除已离开的键，全部键移出时删除状态。键顺序、大小写、方法、自定义列表及颜色样式引用保持。颜色引用先按既有差异样式池校验，未知元数据或缺失样式仍原子拒绝。源、条件、生成格、总计和缓存共用一次精确历史。实现复用 [`sort-state.mbt`](../../modules/formats/src/xlsx/sort-state.mbt) 与现有表范围事务；扩大时保留历史设置参考 [ONLYOFFICE changeRefOnRange](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L8579-L8642)，裁剪额外保证保存状态仍属于本表。

已有 `insertRows/deleteRows/insertColumns/deleteColumns` 同步维护原生表。表之前的插入移动范围，表内部的插入扩展范围；保留原列身份，新列使用空闲身份和唯一 `ColumnN` 标题。计算列模板的相对引用按新的首个数据行重定位，绝对引用沿工作表结构变化。插入的数据行按模板生成公式，原有值/公式例外不改写；每次最多生成 4096 格。总计和筛选范围一起移动，删除总计所在行时关闭总计并保留设置。

活动筛选随整轴操作移动条件列、按钮和手动/筛选隐藏记录。删去条件列时移除相应条件，仍保留其他列；插在总计之前的数据行也进入筛选。已支持的嵌套排序范围及键沿同一变换同步。候选公式先计算，再重新应用受影响的条件，最后重算 SUBTOTAL；生成格按最终结果执行数据验证。多表与普通筛选的行隐藏继续取并集，逐条合并记录，避免对手动隐藏数组反复扫描。原有排序/删除重复流程也复用同一重新应用路径。实现归 [`filter-axis.mbt`](../../modules/formats/src/xlsx/filter-axis.mbt)和 [`filter-structure.mbt`](../../modules/formats/src/xlsx/filter-structure.mbt)。

删列将所有已绑定的目标列引用写为永久 `#REF!`，包含单元格、名称及其他表的公式。删除覆盖整张表的行或列时，删除所属表部件、关系、内容类型和工作表引用，裸表名及行段引用也改为 `#REF!`。同时移除该表的筛选隐藏来源，保留其他筛选及手动隐藏。候选计算使用待删除部件列表，避免读取已删的导入表。同一工作表中的其他原生表及其资源继续保留。源、生成格、依赖、缓存和资源删除合为一次精确历史；撤销能恢复导入部件，也能恢复本会话新建的部件。

部分删除表首行、删除后没有数据行、插入导致表越界、未知表排序、未知表资源和超限候选继续拒绝。穿过表的局部单元格移位仍保护；无交集的移位保留表并同步已支持的引用。生成格沿数据验证检查。默认行列按钮使用原有命令，原生草稿先提交。实现归 [`table-axis.mbt`](../../modules/formats/src/xlsx/table-axis.mbt)、[`table-axis-resources.mbt`](../../modules/formats/src/xlsx/table-axis-resources.mbt)及 [`axis-edit.mbt`](../../modules/formats/src/xlsx/axis-edit.mbt)，参考 [ONLYOFFICE 行范围变化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L2326-L2421)、[列身份维护](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L2117-L2170)及[首行删除保护](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/autofilters.js#L1468-L1478)。

普通数据格沿现有输入路径编辑。直接覆盖表头、总计格或已有计算列时，核心要求相应表命令；缓存重算不受此限制。连接、资源关系、扩展、未知规则引用、受保护工作表和超限候选原子拒绝。工作簿最多 256 张结构化表、4096 列定义；每表列名累计最多 65536 个单元，改名共享 1048576 公式工作预算和原有 4 MiB 历史上限。

`editSheet({ action: "tableStyle", id, style })` 修改所属表的原生样式。`style` 为 `XlsxTableStyle`，包含 `name: string | null` 和显式布尔字段 `firstColumn/lastColumn/rowStripes/columnStripes`。名称支持 `TableStyleLight1`–`TableStyleLight21`、`TableStyleMedium1`–`TableStyleMedium28` 和 `TableStyleDark1`–`TableStyleDark11`，共 60 种，以及工作簿中已有的受支持自定义样式。名称查找由核心执行，自定义名称按目录中的大小写保存。null 清除样式，保留数据、模板、筛选和直接格式。查询的 `style` 返回名称或 null，四个布尔字段另行返回。

缺失的原生节点按需创建，相同设置不增加修订或历史。未知元数据、保护及预算失败整体拒绝。自定义定义与内置名称相同时，以已有自定义定义为准；未知定义仍保护。默认面板、同步 Wasm 和 Worker 使用同一命令。样式源与自动尺寸变化合为精确历史，公式缓存、calcChain 和无关部件保持。实现归 [`table-style-edit.mbt`](../../modules/formats/src/xlsx/table-style-edit.mbt)和 [`xlsx-table-style.tsx`](../../packages/ui/src/xlsx-table-style.tsx)。

自定义样式沿标准 `tableStyles/tableStyle/tableStyleElement` 与 `dxfs/dxf` 读取。`query.tableStyles: XlsxTableStyleChoice[]` 返回 `{ name, readOnlyReason, elements }` 目录，默认面板列出可用项并禁用未知项；最多 256 个定义，每个名称最多 255 个 UTF-16 单元，首尾空白和控制字符拒绝。每个定义最多 13 类非重复区域：全表、两组行/列条纹、首末列、标题/总计行及四个角格。条纹尺寸为 1–1048576；按全表、列条纹、行条纹、末列、首列、标题、总计和角格顺序叠加。字体族/大小/粗斜体/颜色、纯色填充、数字格式、对齐/换行及已支持边框复用差异格式解析，内部横竖边按区域几何映射。直接属性逐项优先，条件格式随后覆盖；字体变体沿现有 4096 字体键和 1048576 工作预算收集。未知区域、缺失 dxf、复杂图案和对角线保持诊断与保护，不替换成内置外观。应用只改所属表的样式引用和标记，原样式定义、dxf 和其他部件保持。实现归 [`table-custom-style.mbt`](../../modules/formats/src/xlsx/table-custom-style.mbt)，区域优先级依据 [ONLYOFFICE CTableStyle.initStyle](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Serialize.js#L14218-L14290)。

`editSheet({ action: "tableStyleDefinition", original, name, elements })` 新建或完整替换定义。`original: null` 表示新建，字符串表示已有名称；`name` 可同时改名。新名称按大小写不敏感规则避开已有定义及 60 种内置名称；同名导入定义仍可修改。`elements: XlsxTableStyleElement[]` 中每项必须包含 `{ kind, size, format, vertical, horizontal }`。`kind` 来自 Wasm/Web 导出的 `xlsxTableStyleRegions`；`format` 沿用 `XlsxCellFormat`，未提供的属性不再属于该区域。`vertical/horizontal` 为内部边框的 `XlsxCellBorder | null`。非条纹区域的合法 `size` 规范为 1；空数组保留一个无格式定义。查询按原生优先级返回区域，未知定义返回保护原因和空数组。

`editSheet({ action: "deleteTableStyle", name, replacement })` 删除定义。`replacement: string | null` 显式选择已有可用自定义/内置样式，或清除引用。定义修改影响使用它的全部表；改名和删除同步各工作表的引用及默认表样式，保留表标记、数据、公式和其他部件。任一受影响表受保护时整项拒绝。仍被默认透视样式使用的定义不能删除，透视样式编辑继续实施。

核心复用差异样式池，仅为变更区域派生 dxf，未变区域保留原身份及主题/索引色关联。删除不回收共享 dxf 或数字格式。缺少样式部件时创建原生部件、关系和内容类型；源、资源与自动尺寸合为一次精确历史。相同有效定义不新增历史，名称冲突、过期、未知源标记及输出预算失败原子拒绝。单个样式部件的编辑候选最多 2097152 个 UTF-16 单元，另受原有 XML 字节及 4 MiB 历史预算约束。默认面板提供新建、区域格式、条纹尺寸、改名和显式替代删除，先提交原生草稿。字体或引用变化使用旧、候选各自的表定义比较并重排行高；两次比较共用计算预算。实现归 [`table-style-definition.mbt`](../../modules/formats/src/xlsx/table-style-definition.mbt)、[`autofit-reflow.mbt`](../../modules/formats/src/xlsx/autofit-reflow.mbt)和 [`xlsx-table-style-definition.tsx`](../../packages/ui/src/xlsx-table-style-definition.tsx)。

内置样式复用已有主题及 tint 解析。各组保留原生定义的差异：

| 名称范围 | 字体和底色 | 条纹、边框和总计 |
| --- | --- | --- |
| Medium1–7 | 深色标题，正文使用主题深色字 | 浅条纹，双线总计 |
| Medium8–14 | 深色标题、总计及强调列 | 较深条纹，主题浅色内部网格与粗分隔线 |
| Medium15–21 | 深色标题及强调列，普通总计不额外加粗 | 灰条纹，黑色双线总计；灰阶项保留完整网格 |
| Medium22–28 | 浅底色和主题深色字 | 较深条纹、完整网格与中等总计线 |
| Light1–7 | 有色文字，不新增标题底色 | 浅条纹，少量标题、总计及外侧横线 |
| Light8–14 | 深色标题，正文保留普通底色 | 行/列条纹开关分别控制内部横线/竖线，总计使用双线 |
| Light15–21 | 正文保留普通底色 | 浅条纹、完整网格、中等标题线和双线总计 |
| Dark1–7 | 深底浅字，强调列使用更深底色 | 标题、总计及强调列保留中等浅色分隔线 |
| Dark8–11 | 标题与正文使用配对主题色，未强调的标题不加粗 | 浅条纹，不新增内部网格，总计使用深色双线 |

Dark8–11 未声明的正文文字色和边框沿用正常单元格格式。字体请求只包含实际需要的粗体字形。直接格式按属性覆盖表样式，条件格式随后覆盖；网格、自动适配与打印使用同一结果。格式面板查询包含表样式；`none` 清除直接边框覆盖，恢复表样式。共享边只绘制一次，双线保留两条细线及间隙。宿主仍须提供字体和 profile。

原生属性依据 ONLYOFFICE 的 [Medium 定义](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Sheets/XlsxDefaults/presetTableStyles.xml#L3-L2668)、[Light 定义](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Sheets/XlsxDefaults/presetTableStyles.xml#L2668-L4536)和 [Dark 定义](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/Binary/Sheets/XlsxDefaults/presetTableStyles.xml#L4537-L5598)。实现归 [`table-style.mbt`](../../modules/formats/src/xlsx/table-style.mbt)，复用原有绘制模型。

含受支持原生表的工作表可沿现有 `rename/copy/delete` 命令和默认按钮操作。工作表改名同步各表的 `calculatedColumnFormula/totalsRowFormula`，保留表名、表/列身份及部件路径。复制为每张表分配独立身份、空闲 `TableN` 名称和部件，并复制工作表关系与内容类型；列身份和其他原生设置保留。副本的显式表引用、工作表自引用及导入的局部名称指向相应副本，字符串常量和全局名称保持原归属。表名分配避开已有表和名称，不重命名源表。实现归 [`table-sheet-copy.mbt`](../../modules/formats/src/xlsx/table-sheet-copy.mbt)，参考 [ONLYOFFICE 工作表表副本及映射](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7096-L7120)及[表名分配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L1286-L1300)。

删除工作表清理其所属表部件、关系和内容类型，更新其他表的普通工作表引用及结构化依赖；失去目标的引用写为 `#REF!`。候选计算使用待删部件列表，保留仍存在的表。创建/删除部件、引用、缓存、视图和选择合为精确历史，支持保存重开和现有打印。已支持的原生筛选随副本保留独立的条件和隐藏来源；未知表资源归属、未知排序元数据、公式扩展和预算失败保持原子拒绝。复制仍受每工作簿 256 张表、4096 列定义及原有历史/输出上限。实现归 [`table-sheet.mbt`](../../modules/formats/src/xlsx/table-sheet.mbt)、[`sheet-copy.mbt`](../../modules/formats/src/xlsx/sheet-copy.mbt)及 [`sheet-delete.mbt`](../../modules/formats/src/xlsx/sheet-delete.mbt)。

当前接通区域创建、范围调整、导入、查询、普通数据编辑、表/列改名、计算列创作/重填、总计设置、整行/列插删同步、工作表资源操作、含表工作簿的名称创作及原生表筛选。筛选中的范围及整轴结构同步已接通；表内行排序已接通；原生表保持整行排序，自定义样式定义创作沿上述命令；其余格式覆盖继续实施。未修改的样式定义保留；只有已支持的表定义和样式才解除 `tableParts` 未呈现诊断，其余仍保护打印。未知表筛选继续保护计算修改并保留源。

结构化引用依据 [ONLYOFFICE cStrucTable](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L2352-L2628)的行段、列身份、当前行及转义行为。实现归 [`table.mbt`](../../modules/formats/src/xlsx/table.mbt)、[`structured-reference.mbt`](../../modules/formats/src/xlsx/structured-reference.mbt)、[`table-rename.mbt`](../../modules/formats/src/xlsx/table-rename.mbt)及 [`xlsx-tables.tsx`](../../packages/ui/src/xlsx-tables.tsx)，复用既有事务和绘制模型。

### 冻结窗格

`editSheet({ action: "freeze", rows, columns })` 冻结起始的指定数量行列，`0, 0` 取消冻结。`rows` 为 0–1048575，`columns` 为 0–16383 的整数。`XlsxQuery.frozen` 返回数量和 `readOnlyReason`。默认属性栏提供首行、首列、所选范围之前及取消冻结；命令沿队列先提交原生草稿。RTL 视图的起始列位于右侧。

核心修改主窗口 `sheetView` 的 pane 和 selection，保留视图属性、注释及其他窗口的源内容。一次操作进入既有历史，相同数量不增加历史；预算或保护失败保持原状态。操作不改变单元格、样式、公式缓存、calcChain 或打印。工作簿窗口保护和未知视图元数据阻止修改，未知公式继续遵循既有只读边界。

网格读取普通 LTR/RTL 的 `frozen` / `frozenSplit` 视图；普通 split 仍拒绝布局。一个 R0 区域内最多绘制四个裁剪窗格，共享 4096 格和 262144 UTF-16 文字预算；核心负责命中、滚动定位及合并格跨边界。`XlsxViewport.cells[].clip` 给出所属窗格，合并格按地址去重。`XlsxSelectionGeometry` 保留锚点矩形并返回最多四个 `rects`；覆盖层绘制这些矩形，原生输入受所属窗格裁剪。

### 行列分组与折叠

`XlsxQuery.outline` 返回 `{ rows, columns, reason }`。两个轴各含 `summaryAfter` 及 `groups`；每组包含从 1 开始的 `first/last`、1–7 的 `level`、汇总项 `summary` 和 `collapsed`。缺省汇总位于明细之后。组由标准 `outlineLevel` 的连续区间派生；共用汇总项的组使用外层按钮，没有可用汇总项时禁用折叠。未知属性、自动应用样式或超限结构返回原因，保留原源。

`editSheet` 接通以下修改，`axis` 为 `"rows" | "columns"`：

| action | 其他字段 | 结果 |
| --- | --- | --- |
| `group` / `ungroup` | `first, last` | 所选行列增加/减少一级，级别下限为 0 |
| `collapseGroup` | `first, last, level, collapsed` | 匹配当前组并折叠/展开 |
| `clearOutline` | 无 | 清除该轴的分组并显示明细 |
| `outlineSummary` | `after` | 设置汇总在明细之前/之后，并迁移折叠标记 |

一次范围操作最多修改 4095 项明细，另预留一个汇总项；一次元数据修改最多 4096 项，每轴最多 1024 组、七级。沿现有源补丁保留行高、列宽、样式、自动适配标记、文字、公式和其他部件；级别缓存及汇总标记一同更新。默认分组面板提供所选范围分组/取消、折叠/展开、清除及汇总位置，原生草稿先提交。修改沿现有 revision、保护及有界历史，重复状态不新增历史；非法范围、层级溢出、未知源和输出预算失败原子拒绝。

折叠隐藏全部明细；展开显示组内手动隐藏项，保留仍折叠的内组及筛选隐藏。清除分组同样显示明细并保留筛选结果，遵循 [ONLYOFFICE 分组展开](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L24846-L24938)与[清除大纲](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L25323-L25415)。行隐藏复用[筛选来源记录](#值筛选)，`SUBTOTAL` 缓存随可见性重算并与折叠合为一项历史。网格、命中、语义单元格及 PDF 复用相同尺寸，隐藏内容仍保存在源单元格中。

整行/整列插删同步分组级别和汇总位置，插入项继承前项的分组级别，并在所在组折叠时保持隐藏；筛选来源和缓存共同提交。删除后仍存在的组保留折叠状态；没有合法汇总位置时原子拒绝。取消分组只减少级别，不自行显示原隐藏项。复制、改名、保存重开与精确混合历史保留分组；保护设置与更广导入变体继续实施。实现归 [`outline.mbt`](../../modules/formats/src/xlsx/outline.mbt)、[`outline-edit.mbt`](../../modules/formats/src/xlsx/outline-edit.mbt)、[`outline-axis.mbt`](../../modules/formats/src/xlsx/outline-axis.mbt)及 [`xlsx-outline.tsx`](../../packages/ui/src/xlsx-outline.tsx)。

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

### 结构化单元格剪贴板

`XlsxSession/Client.captureCells(revision)` 返回核心生成的 `CopiedCells`：源 `top/left`、`date1904`、矩形 `cells`、相对合并范围 `merges`、`conditional`、`validations`、`hyperlinks`、`notes` 和 `sparklines`。每格包含类型化 `value`、公式字符串或 `null` 和全部已支持格式属性。值是复制时的已计算结果；公式保留源表达式和位置。片段独立于之后的源编辑，不持有源会话句柄。

`pasteCells(revision, copied, mode = "all", transpose = false, acceptWarnings = false)` 从当前选择的左上角写入一次片段大小的矩形，不平铺到更大的选择。`all` 写入值、相对平移公式、支持的格式/合并、两类规则、链接、便笺及迷你图；`values` 只写复制时的类型值与公式结果；`formulas` 写入平移公式及非公式常量；`format` 保留目标值、公式和数据验证，只写格式、合并及条件格式。`values/formulas` 保留目标格式和两类规则，目标须未合并。文字 `=literal` 仍是文字，不经输入解析变成公式。

`transpose` 交换行列、合并范围和四边边框。公式先绕复制矩形原点交换引用坐标，再执行粘贴位移；绝对标记沿原引用保留，整行/列引用交换轴。引用越界按既有规则写为 `#REF!`。行为依据 [ONLYOFFICE 选择性粘贴模式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/clipboard.js#L186-L247)、[转置后应用位移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L29818-L29881)和[引用坐标翻转](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L11010-L11034)。

格式与新样式部件、内容、合并、依赖、缓存、验证、自动尺寸和选择共用一次候选事务。已有共享公式按必要范围展开；只贴格式保留目标文字源。失败保留文档与历史。支持完整包含的普通合并格；相交但不完整的目标合并拒绝。源与目标继续复用既有填充资源保护，富文本、原生表/透视和未知工作表扩展保持显式保护。便笺和迷你图随全部粘贴传递，其余模式保持目标便笺及迷你图。更广资源转移继续实施。不含规则/便笺，且单元格、链接与迷你图均相同的片段只更新选择；携带规则或便笺的粘贴可重建原生范围、优先级及身份。

源与目标的 `date1904` 不同时，核心按源格式识别已支持的日期及日期时间数值，换算 1462 天并保留日内小数。纯时间、普通数字、文字及其他类型保持原值；`format` 不转换数值。`all/formulas` 保留公式，在目标日期系统重算；`values` 转换已计算的日期结果。公式内部的普通数字常量不改写。日期验证的数字字面边界同步换算，`DATE`、引用及其他表达式沿目标公式语义处理。源或目标日历无法表示的日期整项拒绝，保留文档与历史；两本工作簿的日期系统不变。

换算复用核心日期序列与格式分类，实现归 [`clipboard-date.mbt`](../../modules/formats/src/xlsx/clipboard-date.mbt)。工作簿日期标志参考 [ONLYOFFICE setDate1904](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L5813-L5825)；跨日期系统粘贴及 1462 天差值依据 [Microsoft 日期系统说明](https://support.microsoft.com/en-us/excel/date-systems-in-excel)。定向核心和默认系统剪贴板浏览器流程已检查，覆盖双向日期换算、值粘贴、精确历史、重开输入及 PDF。

每项 `conditional` / `validations` 包含 `ranges`、`anchor` 和 `settings`，类型分别为 `CopiedConditional` / `CopiedValidation`。`ranges` 是复制矩形内的源绝对地址交集；`anchor` 保留原规则的公式原点。条件设置沿已有 `XlsxConditionalFormat`，验证设置沿 `XlsxDataValidation`。条件样式与主题颜色解析为支持的直接格式，目标重新分配差异样式，保留源规则次序；不沿用源工作簿的 `dxfId`。

全部粘贴裁去目标两类规则的覆盖区，再写入复制交集；格式粘贴只处理条件格式。范围外规则及目标容器的显示设置保留。格内公式按原锚点和复制位移转换；转置复用同一引用坐标交换规则。公式型色阶/数据条阈值按整条规则处理，新覆盖区共同计算统计。复制不移动源引用或其他表的依赖；源和目标使用各自的名称定义，定义及关联资源不随片段转移。规则引用语法和支持范围沿既有合同。

全部粘贴在规则替换后检查新值；值/公式粘贴沿目标原验证检查。只贴格式不重新验证已有值，可保留导入文件中的无效值；后续输入仍受原验证限制。差异样式和普通格样式可同时创建同一个样式部件，关系、内容类型及全部源一起撤销。候选字体、规则、输入、工作量或输出失败保留原文档、选择和历史。

两类规则各最多 4096 项，范围合计最多 4096 个矩形，设置文字合计最多 1048576 UTF-16 单元；原单格、公式、XML、样式和事务预算继续生效。非默认验证 IME 设置、未知身份与扩展继续保护。源全局提示设置留在源文档，目标全局提示设置留在目标文档。实现归 [`clipboard-rules.mbt`](../../modules/formats/src/xlsx/clipboard-rules.mbt)和 [`clipboard-rule-paste.mbt`](../../modules/formats/src/xlsx/clipboard-rule-paste.mbt)。交集复制及转置规则依据 [ONLYOFFICE 条件规则复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L13432-L13505)和[验证复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L13233-L13262)；未移植可执行代码。

每项 `hyperlinks` 使用 `CopiedHyperlink`，含复制矩形内的源绝对 `range`、`target` 和可空的 `display/tooltip`。捕获范围与普通原生链接取交集，保留目标及元数据；未知或重叠链接保护复制。只有 `all` 替换目标覆盖区的链接，范围外片段和属性保持；值、公式及格式模式均保留目标链接。无源链接时清除目标覆盖区，单独链接变化也进入同一历史。转置交换链接所属格，内部目标文字保持原值，不执行公式位移；跨表或工作簿后仍按目标文档解析。外链按目标表分配或复用安全关系，保留旧共享资源，不自动发起请求。链接、单元格、样式与全部关系共用候选、验证和精确历史；同值、迷你图相同且不含规则/便笺的片段保持空操作。

链接目录最多 4096 项，范围须在片段内且互不重叠；目标及元数据合计最多 1048576 UTF-16 单元，`display/tooltip` 各最多 32767 单元。目标沿已有 HTTP/HTTPS/mailto 和内部引用校验。候选链接输出仍限制为 4096 项及 2 Mi UTF-16 单元，全部输出和历史预算继续执行。实现归 [`clipboard-hyperlinks.mbt`](../../modules/formats/src/xlsx/clipboard-hyperlinks.mbt)，关系及原生范围裁剪复用 [`hyperlink-edit.mbt`](../../modules/formats/src/xlsx/hyperlink-edit.mbt)。目标复制与所属范围位移参考 [ONLYOFFICE 范围链接复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22619-L22631)；本 SDK 同时裁剪源交集和目标覆盖，未复制上游源码。

`notes` 为 `CopiedNotes | null`。非空项含原生便笺 XML 的 `comments` 字符串及可空的 `vml` 字符串，只包含所选便笺、实际作者及相关框类型。MoonBit 沿既有严格读取器验证原生结构、富文本、所属地址、VML 类型及框匹配；Web 只校验载荷形状和长度。源 `guid` 不进入副本，目标重新分配部件/框身份及作者索引，保留富文本、外观、原 Anchor 与偏移；`ref` 和 VML Row/Column 随目标或转置更新。仅 `all` 替换目标覆盖区的便笺；`notes: null` 清除该区便笺，值/公式/格式粘贴保持原便笺。范围外原节点、原作者和空资源保留，源文档不变。

目标缺少 comments/VML 时沿既有资源事务创建；只有文字的导入便笺补齐默认框。源、作者、资源、关系、内容类型与值/公式共用一次精确历史及预算检查，失败保留文档。两个 XML 字符串合计最多 2 Mi UTF-16 单元，捕获时逐条检查实际展开长度，包含命名空间、作者和框类型；沿原有 4096 项及 1048576 单元便笺文字限制。未知/共享/外链 VML、线程批注、源身份注入、范围外地址和异常 XML 继续保护。默认便笺面板、角标和可访问描述读取同一结果，静态 PDF 继续排除便笺。实现归 [`clipboard-notes.mbt`](../../modules/formats/src/xlsx/clipboard-notes.mbt)与 [`notes-import.mbt`](../../modules/formats/src/xlsx/notes-import.mbt)，复制范围、目标覆盖与独立身份依据 [ONLYOFFICE moveRangeComments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/CellComment.js#L550-L586)；未复制上游源码。

`SpreadsheetEditor.copyCells()` 先提交原生草稿，再将片段及普通 TSV 写入系统剪贴板。`pasteCells(mode = "all", transpose = false)` 读取相同载荷，沿队列检查字体、revision 和生命周期后提交；默认面板提供四种模式和转置开关。载荷类型为 Chromium 的 `web application/x-open-document-cells`。普通原生粘贴及 `paste(text)` 保持上述 TSV 语义；普通 `copy()` 也先提交已接受草稿。读取/写入权限失败保留源，晚到读取不能修改已关闭的编辑器。

片段最多 4096 格、1024 个合并范围、1048576 UTF-16 单元的值/公式文字；每格文字最多 32767 单元，公式最多 8192 单元。Web 写入的 JSON 最多 4194304 UTF-16 单元，读取最多 8 MiB。Wasm、Worker 和核心分别校验载荷，现有样式、历史、源、字体及输出预算继续生效。实现归 [`cell-fragment.mbt`](../../modules/formats/src/xlsx/cell-fragment.mbt)、[`clipboard-transpose.mbt`](../../modules/formats/src/xlsx/clipboard-transpose.mbt)及 [`spreadsheet-clipboard.ts`](../../packages/web/src/spreadsheet-clipboard.ts)。

### 单元格剪切移动

`editSheet(revision, targetSheet, { action: "moveCells", sourceSheet, source, destination })` 在同一工作簿内移动普通矩形。目标从 `destination` 左上角开始，大小取源范围。完整单个合并格按实际跨度移动；部分合并相交拒绝。源与目标可重叠，目标覆盖和源清除读取同一个原始快照。内容、直接格式、完整合并、链接及便笺一起移动；行列尺寸及行列格式保留。便笺的作者、富文本、VML 及跨表归属归[单元格便笺](#单元格便笺)。多表公式、名称、内部链接的目标、计算缓存、自动尺寸与选择共用一次精确历史。未变化的公式保留原表达式。

完整落在源范围内的引用随格移动，包含绝对引用；部分相交的范围保持。相对及混合名称在定义保存的坐标上移动一次，保留 `$`、作用域、属性及调用公式中的名称。跨表移动把定义中的目标表改为目标表，求值仍按实际调用格偏移；调用格自身移动时使用新位置，不额外补偿。此规则与上述结构操作一致，依据 [ONLYOFFICE 名称定义事务](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L561-L580)及[调用格偏移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L2249-L2256)。移动到另一工作表时，原来指向源范围外的无表名引用和名称保留原表语义，不按复制规则偏移。依据 [ONLYOFFICE 移动事务与跨表公式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L9800-L9858)和[完整包含引用的移动规则](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/parserFormula.js#L10155-L10227)。

完整包含的普通外链与内链随所属格移动，保留提示文字、显示文字和命名空间；源选择须包含完整链接范围。目标链接只裁掉被覆盖的范围，范围外源与容器注释保留。跨表外链在目标表复用相同目标的已有关系，或分配未占用的关系身份；旧源关系保留。内链目标沿同一次引用变换，重叠移动也只变换一次。链接归属参考 [ONLYOFFICE 合并与链接移动](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L9543-L9609)。未知链接属性、混合内外目标、失效关系及不安全协议继续保护；打开外链仍须用户明确操作。

普通条件格式和数据验证按实际交集随格移动，目标规则只裁掉覆盖区。重叠移动按原始归属计算，跨表复制原生规则片段并补齐命名空间；范围外规则、容器显示设置和提示保持。逐格公式保留原位置的引用语义，完整落在源区的引用随格移动；跨表未移动的本地引用保留原表。其他表内的依赖规则同步更新，公式型色阶/数据条阈值按整条规则处理。不同公式分组、优先级和验证 `count` 复用上述规则变换；同表保留的色阶/数据条覆盖区共用统计样本。规则归属沿 [ONLYOFFICE 条件格式迁移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L13432-L13507)和[数据验证迁移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L13233-L13257)，引用处理复用本节的移动合同。

`SpreadsheetEditor.copyCells(true)` 和默认“剪切单元格”按钮先写系统剪贴板，源格在粘贴成功前保留。剪切只携带显示值 TSV 和 `web application/x-open-document-cut` 的工作簿身份、源范围与 revision；核心在 `pasteCells("all", false)` 时校验并移动实际源内容，不要求先生成复制片段。网格原生剪切/粘贴复用该入口，草稿文字仍沿原生文字输入。消费后、源文档编辑后或重开工作簿后的旧载荷拒绝；跨工作簿、选择性粘贴及转置剪切也拒绝。普通 TSV 和复制片段沿原合同。

移动最多 4096 格和 1024 个合并范围；工作簿源、公式、链接及迷你图组节点源合计最多 1 Mi UTF-16 单元，搬移与改写的单元格源合计最多 1 Mi 单元。每表最多 4096 个链接，单表生成的链接源最多 2 Mi 单元。规则沿既有 100000 格、4 Mi 字符和 4096 片段工作上限；每表至多 4096 条条件规则和 4096 条验证。全部变动仍受 4 MiB 历史及包输出预算约束。被保护的源、目标或受影响公式/链接/规则/迷你图拒绝。未知资源、原生表、透视及带筛选/排序的工作簿保持保护，未限定工作表的名称引用及需改写的不透明名称源继续保护；跨表打印范围的归属转移继续实施。实现归 [`move-cells.mbt`](../../modules/formats/src/xlsx/move-cells.mbt)、[`move-reference.mbt`](../../modules/formats/src/xlsx/move-reference.mbt)、[`move-hyperlinks.mbt`](../../modules/formats/src/xlsx/move-hyperlinks.mbt)、[`move-rules.mbt`](../../modules/formats/src/xlsx/move-rules.mbt)、[`rule-fragments.mbt`](../../modules/formats/src/xlsx/rule-fragments.mbt)和 [`move-resources.mbt`](../../modules/formats/src/xlsx/move-resources.mbt)。

### 工作表绘图复制

`SpreadsheetEditor.editSheet({ action: "duplicateDrawing", objectId })` 在当前表复制一个普通图片、图形、文本框或图表。同步 `XlsxSession` 和异步 `XlsxClient` 使用显式 revision、sheet 的 `editSheet`。默认属性面板提供“复制对象”，复制后选择副本并加载其属性。副本分配新的本地身份，放在最上层，向右、向下各偏移 12 pt；保留原名称、替代文字、三种锚点、尺寸、零轴直线、裁剪、文字、可见及打印策略。

核心在原生片段中补丁修改身份和坐标，保留未改源、注释及命名空间。图片共享不可变媒体字节，后续更换沿既有资源隔离规则。图表获得独立部件和关系，保留数据引用、缓存及配色；修改副本外观不改原图，两者仍读取同一单元格来源。新增部件、关系、内容类型和选择合为一次精确历史，支持撤销、重做、保存重开及后续输入。Canvas/PDF 继续使用共用绘制管线。

每表最多 256 个对象，全部变更沿既有包、输出及 4 MiB 历史预算。越界、旧 revision、复制/选择锁、工作表保护、未知身份扩展和未支持的关系原子拒绝；需改写的锚点数字内部有注释时也拒绝。图表附加资源仍受保护。此命令完成同表独立复制；同工作簿转移归[绘图剪切](#工作表绘图剪切)，图片、基础图形和普通图表系统复制归[绘图剪贴板复制](#工作表绘图剪贴板复制)；跨工作簿剪切继续实施。实现归 [`drawing-copy.mbt`](../../modules/formats/src/xlsx/drawing-copy.mbt)。原生对象、图像填充及图表独立复制参考 [ONLYOFFICE Image.copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L162-L187)和 [ChartSpace.copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L4959-L4999)；未复制上游执行代码。

### 工作表绘图剪贴板复制

`SpreadsheetEditor.copyDrawing(id)` 复制一个普通 PNG/JPEG 图片、矩形、椭圆、直线、文本框或工作表图表。默认图片、图形和图表面板提供“复制绘图”，对象和已选择绘图的网格支持 Ctrl/Meta+C。`pasteDrawing()` 与“粘贴绘图”支持同表、跨表和跨工作簿；本页面的网格原生粘贴也识别复制片段。新对象放在选区左上格和最上层，分配独立本地身份。保留三种锚点、尺寸、零轴直线、裁剪、名称、替代文字、可见和打印策略。

剪贴板格式为 `web application/x-open-document-drawing`。核心快照携带选中对象的原生片段、所需图片或图表数据及字体名/主题色。图表只携带当前标签、系列值和独立可见性，不复制来源公式或无关单元格。源文稿后续修改、关闭或替换不改变快照，允许重复粘贴。图片使用快照内的压缩字节；每次粘贴创建目标媒体、关系及内容类型。字体和主题会改变图形解释时，核心在目标对象中写明源字体与 RGB，保留原外观；宿主仍须提供该字体。未改源、命名空间和图片注释保留，需要重建的样式源若带注释则保护，避免丢失内容。

普通图表的快照保留完整系列长度、空值、散点数值轴、原配色及各来源的可见性。每次粘贴创建独立隐藏数据表和原生图表，绑定新表中的普通值，目标格不被覆盖。数据表可沿既有表管理显示并编辑；副本之间独立，后续输入自动更新所属图表。来源公式保存为当前计算值。图表和数据表、关系及内容类型共用一项精确历史；工作簿结构保护会拒绝该粘贴。删除图表保留数据表，避免删除后续输入；用户可显式删除数据表。实现归 [`chart-fragment.mbt`](../../modules/formats/src/xlsx/chart-fragment.mbt)，从缓存重建数据表参考 [ONLYOFFICE getWorksheetsFromCache](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L2169-L2264)。

同步 `XlsxSession` 和异步 `XlsxClient` 提供 `captureDrawing(revision, sheet, id, profile)`，返回 `{ fragment, text }`；`pasteDrawing(revision, sheet, fragment, profile)` 导入片段。`drawingFragmentImage(revision, fragment)` 返回核心校验后的压缩图片或 `null`，供宿主沿现有图片入口预解码。默认编辑宿主自动完成预检、解码和提交。核心验证解码尺寸后，才把绘图、资源、关系和选择合为一次精确历史。失败保留文稿，撤销、重做、重开输入及 Canvas/PDF 继续共用既有管线。

片段最多 4 Mi UTF-16 单元，原生框源最多 1 Mi 单元，单图最多 2 MiB；平台读取 Blob 最多 8 MiB。JSON 使用标准库有界解析，XML 深度、像素、累计图片、256 对象、历史及包输出沿既有预算。字段、资源、复制/选择锁、工作表保护、宏/绑定、外链、不支持的原生结构或越界失败原子拒绝。图表含附加关系、源注释或内容内处理指令时继续保护；同表独立复制和同工作簿剪切沿相邻合同。实现归 [`drawing-fragment.mbt`](../../modules/formats/src/xlsx/drawing-fragment.mbt)、[`drawing-paste.mbt`](../../modules/formats/src/xlsx/drawing-paste.mbt)及 [`spreadsheet-clipboard-host.ts`](../../packages/web/src/spreadsheet-clipboard-host.ts)。图形复制和源外观保留参考 [ONLYOFFICE Shape.copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2829-L2858)及 [saveSourceFormatting](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L7639-L7659)；未复制执行代码。

### 工作表绘图剪切

`SpreadsheetEditor.cutDrawing(id)` 先写系统剪贴板，保留源对象和文稿历史。默认图片、图形和图表属性面板提供“剪切绘图”，对象键盘支持 Ctrl/Meta+X；网格已选择的绘图也沿同一入口。`pasteDrawing()` 和默认“粘贴绘图”把对象搬到当前选区左上格，网格原生粘贴识别同一标记。剪切载荷 `web application/x-open-document-drawing-cut` 只包含工作簿身份、源表、对象 ID 和 revision，最多 4096 字节。写剪贴板失败不删源；编辑、重开或已经成功搬移后的旧标记拒绝。跨工作簿剪切仍拒绝。

核心命令为 `editSheet(revision, targetSheet, { action: "moveDrawing", sourceSheet, objectId })`。普通图片、图形、文本框和图表可在同表或同一工作簿的不同表之间搬移。保留三种锚点、尺寸、零轴直线、裁剪、文字、可见及打印策略；对象放在目标绘图最上层。同表保留 ID，跨表只在本地 ID 冲突时重映射。坐标与身份沿源补丁修改，保留未改注释和命名空间。相同位置的同表搬移不新增历史。

图片沿用原媒体字节，目标绘图复用已有关系或新建独立关系，不重复同一内容类型声明。图表沿用原部件，目标获得关系并移除旧绘图的关系。跨表搬移把无表名引用限定到原来源表，显式外表引用保持；不会改读目标表的同坐标。移动后的来源输入仍同步缓存和绘制，后续整表复制继续使用独立图表规则。源移除、目标插入、新建绘图、关系、引用和选择合为一项精确历史；失败不留下部分资源。

源/目标工作表保护、选择/移动锁、未知身份和关系扩展、越界、256 对象或历史/包预算失败均原子拒绝。需要改写的不透明锚点文字、图表引用或关系源继续保护；复制锁不阻止搬移。图片、基础图形和普通图表系统复制归[绘图剪贴板复制](#工作表绘图剪贴板复制)；跨工作簿剪切及更广原生变体继续实施。实现归 [`drawing-move.mbt`](../../modules/formats/src/xlsx/drawing-move.mbt)、[`drawing-transfer-source.mbt`](../../modules/formats/src/xlsx/drawing-transfer-source.mbt)及 [`spreadsheet-clipboard.ts`](../../packages/web/src/spreadsheet-clipboard.ts)。延后删除及同文档剪切归属参考 [ONLYOFFICE Clipboard.copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/clipboard.js#L434-L441)和 [_checkCutBefore](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/clipboard.js#L2119-L2153)；未复制执行代码。

### 工作表图片

`SpreadsheetEditor.pictures()` 返回当前表的 `{ revision, sheet, reason, items }`。每项包含稳定的原生 `id`、名称、替代文字、锚点、point 几何、源裁剪及图片资源键。`insertPicture(bytes, width, height, name?, description?)` 在选定单元格插入普通 PNG/JPEG；`setPicture(id, settings)` 修改锚点、位置、尺寸及文字，`deletePicture(id)` 删除目标锚点。`replacePicture(id, bytes)` 更换目标的 PNG/JPEG 压缩资源，保留身份、名称、替代文字、三种锚点、几何及源裁剪。默认面板提供独立文件选择，不提交其他未应用的属性草稿。默认图片面板复用这些入口，调整尺寸保留当前比例。同步 `XlsxSession` 和异步 `XlsxClient` 提供对应显式 revision/sheet/profile 接口；Web 在提交前完成图片预检和像素解码。

`anchor` 接受 `fixed`、`move`、`size`，分别保存 `absoluteAnchor`、`oneCellAnchor` 和普通 `twoCellAnchor`。核心按原生行高/列宽解释几何，尺寸编辑在同一历史中同步图片姿态。网格按冻结窗格裁剪图片，RTL 只移动对象位置；打印沿现有分页、区域和缩放裁剪，保留隐藏和 `fPrintsWithSheet` 策略。源裁剪参与同一 Canvas/PDF 绘制。资源、关系、源补丁和原生输入共用精确历史，撤销与重做恢复相同字节，失败保留文档。删除保留可能共享的关系和媒体，解码缓存只保留实际引用的图片。

更换图片时，核心分配新媒体路径及关系，只修改所选图片的 `a:blip/@r:embed`。旧关系与媒体保留，共用原资源的其他对象不改变；新 MIME 与内容类型跟随实际字节，不依赖文件扩展名。同字节替换不新增历史。新资源、关系和源补丁合为一项事务，撤销移除本次新增资源，重做恢复同一字节。单图上限为 2 MiB，解码与累计资源沿现有图片上限；Web 先提交原生单元格草稿，再预检和解码，失败保留源。文件读取期间文稿版本或工作表变化时，默认面板拒绝提交并要求重新加载图片。实现归 [`picture-replace.mbt`](../../modules/formats/src/xlsx/picture-replace.mbt)，图片源修改参考 [ONLYOFFICE 图像属性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L4191-L4203)，锚点、源裁剪和元数据继续沿本 SDK 的保留规则。

`XlsxPictureSettings.crop` 必填，按左、上、右、下保存四个源裁剪比例；每项为 0–1 之间的有限数，不含 1。核心按原生 1/100000 精度舍入，再检查对边之和小于 1。裁剪保留框的位置与尺寸，不改压缩图片字节；全零移除原生 `srcRect`。拖动、缩放和整表复制保留裁剪。默认图片面板提供四边百分比，步长为 0.001%，沿原属性按钮提交；“重置裁剪”只恢复完整图片，不提交其他未应用草稿。

`noCrop` 锁阻止改变裁剪，原有对象选择/尺寸锁继续生效。未知裁剪属性、子内容、注释和处理指令保护源；裁剪展开后的每轴尺寸最多 1e9 pt。无效值、舍入后为空或预算失败整体拒绝；相同裁剪、位置、尺寸及文字不新增历史。实现归 [`picture-crop.mbt`](../../modules/formats/src/xlsx/picture-crop.mbt)，复用 DOCX 裁剪精度与现有图片事务。比例解释参考 [ONLYOFFICE 图片裁剪系数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L947-L959)，原生顺序沿 [BlipFill 序列化](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Fills/BlipFill.cpp#L159-L173)。

每表图片和基础图形合计最多 256 项，压缩图片源合计最多 16 MiB；新输入最多 2 MiB，尺寸为 0.1–14400 pt。字体、RGBA、历史及包输出继续沿用共享预算。工作表保护、对象锁、未知锚点及复杂图形、旋转/翻转、外链及不支持的绘图样式保持保护并返回原因。`twoCellAnchor` 的其他 `editAs` 变体和复杂图形继续实施；其余资源迁移沿现有保护。实现归 [`picture-read.mbt`](../../modules/formats/src/xlsx/picture-read.mbt)、[`picture-edit.mbt`](../../modules/formats/src/xlsx/picture-edit.mbt)、[`picture-reflow.mbt`](../../modules/formats/src/xlsx/picture-reflow.mbt)及 [`spreadsheet-canvas.ts`](../../packages/web/src/spreadsheet-canvas.ts)。

普通图片随整表复制、改名及删除，沿现有 `editSheet` 命令和默认表管理按钮操作。复制创建独立绘图 XML 与关系，保留三种锚点、图层、文字、裁剪及部件内图片身份；不可变 PNG/JPEG 字节共用。副本图片可单独修改，源图片保持；同表便笺和结构化表继续各自建立副本。改名沿原有引用事务保留绘图归属。删除移除该表的绘图 XML、关系及内容类型，保留可能共享的图片字节。源与副本的编辑、删除及输入共用精确历史；保存重开后可继续编辑。

表管理先验证普通图片及独立绘图归属；未知对象、共享绘图、图片链接/扩展身份和非图片绘图关系继续保护。原始客户端先提供字体 profile，默认宿主在首次资源测量后沿现有队列刷新可用状态。工作簿结构保护、资源和历史预算继续生效。实现归 [`picture-sheets.mbt`](../../modules/formats/src/xlsx/picture-sheets.mbt)，锚点及对象独立复制参考 [ONLYOFFICE copyObjects](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7391-L7421)。

整行、整列插入或删除复用原有 `editSheet` 命令和默认按钮。固定图片保持位置与尺寸；单格锚点只随起点之前的行列移动；双格锚点同时维护起止标记，在图片内部插入或删除时改变尺寸。删除覆盖单格锚点时保留原索引与偏移；覆盖双格起点时截到删除起点，至少保留一格跨度。截断只清零受影响轴的偏移，另一轴保留。图片身份、替代文字、裁剪、锁和资源保持，自动行高重排后同步最终原生姿态；几何未变的姿态片段保留原源。图片、单元格、引用和选择共用一次精确历史，重开后可继续输入及输出 PDF。

结构编辑先验证工作簿中的全部支持绘图。原始客户端须先以相同 revision 的 `pictures` 或 `viewport` 提供字体 profile，默认宿主自动准备。未知绘图、共享绘图部件、工作表保护、锚点越界及候选预算失败整体拒绝。局部单元格移位保留三种锚点标记，需要跟随尺寸的对象仍响应自动行高重排。依赖行列变化沿锚点策略调整，直接对象修改仍遵守对象锁。实现归 [`picture-axis.mbt`](../../modules/formats/src/xlsx/picture-axis.mbt)，移动和缩放策略依据 [ONLYOFFICE 行列绘图更新](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/DrawingObjects.js#L3232-L3511)。

画布图片可以选择、拖动及四角等比缩放。图片覆盖范围和可见手柄由核心按冻结窗格裁剪，重叠图片沿源顺序命中；方向键以 1 pt 操作，Shift 改为 10 pt，Delete 删除对象。核心保留图片选择，普通单元格选择结束图片选择；原生事务及撤销/重做同步恢复它。候选完整网格沿同一 Canvas 绘制，抬笔只提交一项历史。Escape、失焦、捕获丢失、滚动及过期几何取消候选。保存及常规修改入口先取消候选；其他命令改变几何后也会取消过期候选。只读查询保留候选。

`XlsxSession/XlsxClient.selectDrawing(revision, layout, objectId)` 绑定当前网格选择图片或基础图形，null 清除选择。`drawingGesture(revision, layout, { handle, dx, dy, commit }, profile)` 返回 `{ query, drawing, selection }`。handle 为移动 0，或屏幕左上/右上/右下/左下 1–4；增量为屏幕方向的 point，核心处理 RTL。commit=false 返回候选网格及 null query，保留源、revision 和历史；commit=true 沿已有原生位置事务写入，返回 query 及 null drawing。候选只分配新的绘制身份，不能据此确认保存。手势增量每轴限 ±14400 pt，沿用原生尺寸、位置、锁定、资源及历史预算。缩放固定对角；图片保留当前比例，图形自由调整宽高，noChangeAspect 锁要求等比。翻转继续实施。实现归 [`drawing-pointer.mbt`](../../modules/formats/src/xlsx/drawing-pointer.mbt)及 [`spreadsheet-drawing-pointer.ts`](../../packages/web/src/spreadsheet-drawing-pointer.ts)，参考 [ONLYOFFICE 缩放候选及比例保护](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L634-L678)。

绘图拖动及四角缩放复用现有指针调度器，在视口边缘持续滚动。可选 `gesture.viewport = { originX, originY, scrollX, scrollY }` 使用 point：origin 是开始时相对原网格画布的屏幕坐标，scroll 是当前绝对滚动量，两轴均非负，RTL 水平量也为正。核心从原布局换算冻结/滚动区域及 RTL 位移，候选网格和对象选框使用当前滚动位置。候选保留源、revision 和历史，抬笔只提交一项位置事务；Escape、手动滚动、保存和释放实例沿已有取消屏障恢复原对象。起点必须位于原视口内，滚动量每轴最多 10⁹ pt，换算后的总增量继续受 ±14400 pt 限制。宿主按候选网格更新滚动范围，保留原手势布局身份；外部视口变化仍取消手势。坐标依据参考 [ONLYOFFICE 绘图区域偏移换算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/DrawingObjects.js#L4172-L4193)。

`editSheet(revision, sheet, { action: "drawingOrder", objectId, direction })` 调整图片与基础图形层次。direction 接受 `front`、`back`、`forward`、`backward`，对应置顶、置底及移动一层。默认图片和图形面板使用四个图层按钮。核心移动原始锚点片段，保留身份、位置、尺寸、文字、裁剪、资源和片段间的注释/空白；网格显示、命中及 PDF 采用同一原生顺序。一次实际调整只记一项历史，并选择目标图片；已经位于边界时保持源、revision、选择和历史。普通单元格输入可以继续，撤销/重做和重开保持原生内容。同步核心或原始客户端先用相同 revision 的 `pictures` 或 `viewport` 提供字体 profile，默认宿主自动准备。锁定、工作表保护、失效身份、未知绘图或预算失败整体拒绝。基础图形共用原生顺序；组内层次继续实施。实现归 [`drawing-order.mbt`](../../modules/formats/src/xlsx/drawing-order.mbt)，参考 [ONLYOFFICE 图层顺序操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L9589-L9688)。

### 工作表基础图形

`SpreadsheetEditor.shapes()` 返回当前表的 `{ revision, sheet, reason, items }`。`insertShape(kind, width, height, text)` 在所选单元格插入矩形、椭圆、直线或文本框，kind 分别为 `rect`、`ellipse`、`line`、`textBox`。`setShape(id, settings)` 修改完整属性，`deleteShape(id)` 删除目标。同步 `XlsxSession` 和 Worker `XlsxClient` 使用对应的显式 revision/sheet/profile 参数。宿主复用现有草稿屏障和串行队列。默认图形面板提供创建、完整属性修改和删除；原生文字输入与属性提交沿用同一文档历史。

属性包含锚点、point 位置/尺寸、名称和替代文字、六位 RGB 填充/描边、线宽及普通文字。`fill`、`stroke` 为 null 时不绘制。文字支持统一字体、字号、粗体、斜体、颜色、换行、水平/垂直对齐，以及 `insets: { left, top, right, bottom }`。字号为 1–400 pt，线宽为 0–1000 pt，每项内边距为 0–14400 pt；文字最多 32767 个 UTF-16 单位。矩形、椭圆及文本框的宽高至少 0.1 pt；直线允许一个轴为零，另一个轴至少 0.1 pt。对象每轴尺寸不超过 14400 pt，位置沿工作表边界校验。

基础图形与图片共用原生绘图顺序、身份、三种锚点、行列重排及工作表资源事务，每表合计最多 256 项。图形保存 `xdr:sp`、预设几何及 DrawingML 文字，不另建 TS 文档模型。轮廓复用 PPTX 的基础路径，文字复用共享塑形与换行；椭圆先采用原生内接文字矩形，再加文字内边距。字体键随绘图加入 `fontKeys`。网格、Canvas 和 PDF 使用同一 R0 图元。 `XlsxViewport.objects` 按原生顺序返回 `{ id, kind, name, selected, regions }`；kind 为 picture、chart 或四种基础图形。可见区域与手柄归核心计算，零轴直线的命中矩形每轴至少 6 pt，再按窗格裁剪。

相同属性不新增历史；修改、层次、行列插入、复制、删除与普通输入共用精确历史，保存后可继续编辑。核心手势区分图形自由缩放与图片等比缩放，候选保留源及历史；默认画布控件支持选择、拖动、四角缩放、方向键、Shift 大步移动及 Delete 删除；图片和图形按各自原生事务处理。选择、移动、尺寸、比例、文字和形状类型锁分别保护对应修改。未知属性、扩展、注释、处理指令、复杂文字、旋转/翻转及复杂几何受保护，候选资源或输出超限整体拒绝。这里只覆盖普通统一文字图形，尚不代表完整 DrawingML 支持。

实现归 [`shape-read.mbt`](../../modules/formats/src/xlsx/shape-read.mbt)、[`shape-edit.mbt`](../../modules/formats/src/xlsx/shape-edit.mbt)、[`shape-preserve.mbt`](../../modules/formats/src/xlsx/shape-preserve.mbt)、[`shape-paint.mbt`](../../modules/formats/src/xlsx/shape-paint.mbt)及 [`xlsx-shapes.ts`](../../packages/wasm/src/xlsx-shapes.ts)。椭圆文字矩形参考 [ONLYOFFICE CreateGeometry](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L3100-L3117)，锁定分类参考 [GraphicObjectBase](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L166-L183)。

### 工作表图表

`SpreadsheetEditor.charts()` 返回当前表的 `{ revision, sheet, reason, items }`。每项包含原生 `id`、名称、替代文字、三种锚点、point 位置/尺寸、图表外观、数据源引用和当前值 TSV。同步 `XlsxSession` 与异步 `XlsxClient` 提供对应显式 revision/sheet/profile 接口。`XlsxViewport.objects.kind` 增加 `chart`；选择、移动、自由缩放和删除沿既有画布入口。

`insertChartRange(range, kind, title, width, height)` 使用当前表的普通矩形：第一行为系列标题，第一列为类别，其余为数值系列。核心生成带表名的绝对引用，在当前选择处插入 `oneCellAnchor`。`insertChart(settings, width, height)` 使用显式 `XlsxChartSettings`：`kind/title/label/legend/holeSize/categories/names/values`。`categories` 为一行或一列的本工作簿来源，`names` 的每项引用一个标题格，`values` 的对应项引用各自的一行或一列，分类与系列允许独立长度。允许本表或跨表普通引用；不接受表达式、外部或三维来源。空标题显示默认系列名，非数值点留空，公式读取当前计算值。

支持簇状、堆积、百分比堆积柱形图/条形图、折线、饼、圆环、普通及堆积/百分比堆积面积图、散点和雷达图。类型、图例、空心比例及实际绘制沿[PPTX 基础图表](#pptx-基础图表)的共用模型。`setChart(id, settings)` 修改外观和引用；`setChartFrame(id, frame)` 修改锚点、位置、尺寸及文字；`deleteChart(id)` 删除锚点并保留旧资源。默认面板提供区域插入、引用修改、当前值预览和独立尺寸编辑。宿主先提交原生输入草稿，再执行图表命令。

MoonBit 维护原生 `graphicFrame`、图表 XML、关系、内容类型及系列缓存。普通编辑后，依赖公式、图表缓存、源补丁和布局共用一次候选事务与精确历史，不生成嵌入工作簿。打开时按当前单元格值派生图表，首次查看保留源。修改、保存重开、Canvas 和静态 PDF 使用同一数据及图元。相同设置不新增历史；失败保留文档与历史。

工作表改名同步本表及其他表中普通图表的分类、系列标题和数值引用。核心沿已有词法标记只替换匹配旧表名的片段，保留地址、绝对标记、固定标题、缓存、绘图身份和其他源。名称匹配不区分大小写，中文及名称内单引号使用原生转义；注释和处理指令保留。需要替换的引用文字内部若带这些内容，整项改名保持保护。工作簿名称、普通单元格公式、图表引用和计算共用一次精确历史，重开后可继续改名与输入。实现归 [`chart-rename.mbt`](../../modules/formats/src/xlsx/chart-rename.mbt)，依据 [ONLYOFFICE 跨表绘图引用改名](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L5550-L5582)。

复制工作表时，已引用的普通图表和所属绘图分别获得独立部件与关系。图表对原表的显式引用改指副本，未限定表名的引用继续按新所属表解释；其他工作表的来源保持。对象在新绘图中保留本地 ID、名称、替代文字、三种锚点和几何，图片沿既有规则共享不可变媒体。源图表、固定标题和非目标字节保留，副本后续改值、改类型或标题不影响原图表。

新表、绘图、图表、关系、内容类型和引用进入既有复制事务，支持混合输入/图表编辑的精确撤销、重做与保存重开。部件路径避让当前包、会话和未引用的同名资源；全部新增源仍受 4 MiB 历史和输出预算约束。源注释保留；需要重写的引用内部若带注释或处理指令，整项复制拒绝。共享图表部件、图表的附加资源及未知绘图身份扩展保持保护。实现归 [`chart-copy.mbt`](../../modules/formats/src/xlsx/chart-copy.mbt)，依据 [ONLYOFFICE 复制绘图与重绑定本表来源](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7391-L7440)。

删除工作表时，所属绘图、图表、关系和内容类型沿既有部件快照一起移除。共享图片等媒体保留，未知的部件入站引用拒绝整项删除。其他表的图表将被删来源的完整引用写为 `#REF!`，对象及最后有效缓存保留；尚有效的系列继续读取当前单元格值。支持原生带地址尾部的失效引用，例如 `#REF!$A$2:$A$4`。工作表删除、引用、计算及资源共用一次精确历史；打开已保存的失效图表不改源。

`XlsxChart.bindingReason` 在来源失效时返回原因，正常时为空串。默认图表属性面板显示缓存提示，保留标题、类型和引用编辑入口。修改已有失效图表的外观时保留其缓存；重新绑定后恢复实时更新并清除提示。新建图表不能使用缺少缓存的失效来源。缓存只是最后有效值，不表示已删除来源仍在更新。原生输入、撤销、重开和 Canvas/PDF 共用这一状态。实现复用 [`chart-rename.mbt`](../../modules/formats/src/xlsx/chart-rename.mbt)、[`chart-bindings.mbt`](../../modules/formats/src/xlsx/chart-bindings.mbt)及 [`sheet-delete.mbt`](../../modules/formats/src/xlsx/sheet-delete.mbt)。依据 [ONLYOFFICE 删除表时处理图表来源](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L5498-L5541)、[失效引用写回](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L12116-L12128)和[无法解析来源时的缓存保留](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L12551-L12568)。

整行、整列插删已同步本表及跨表的分类、系列标题和数值引用。来源内部插入扩大范围，删除缩小范围；完整删除来源后写为 `#REF!` 并保留最后有效缓存与提示。绝对地址也随结构变化，已失效引用保持。固定、随单元格移动和随区域缩放三种锚点复用已有图片规则；引用、原生缓存、公式计算和几何共用一次精确历史。几何预检与提交重排读取插删后的候选数据，散点图不会误读旧位置。

纯引用平移只补丁修改原生引用文字，保留其他注释及处理指令。引用内部有注释，或数据变化需要改写带注释的缓存时，整项操作保持保护。来源扩大超过 256 格、对象越界或其他预算失败也原子拒绝。默认行列按钮先提交原生输入草稿，再提交结构历史；重开后输入及 Canvas/PDF 沿同一数据。实现归 [`chart-axis.mbt`](../../modules/formats/src/xlsx/chart-axis.mbt)、[`picture-axis.mbt`](../../modules/formats/src/xlsx/picture-axis.mbt)及 [`transaction.mbt`](../../modules/formats/src/xlsx/transaction.mbt)。依据 [ONLYOFFICE 行列操作维护图表来源](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L5583-L5634)和[引用移动及范围调整](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L12107-L12115)。复用已有结构引用算法，未复制上游执行代码。

普通图表按原生 `plotVisOnly=1` 排除来源表的隐藏行列。类别和各系列分别按各自来源压紧可见点；没有可见来源的系列不绘制，也不进入图例。保留原始系列及扇区配色，隐藏第一系列不会使第二系列变蓝。手动隐藏、筛选和分组共同沿有效尺寸计算；目标表相同坐标的隐藏状态不影响跨表来源。全部来源隐藏时保留标题和图框，恢复显示后继续绘制。

有效来源的原生引用、完整当前值缓存及 `charts().data` 保留全部来源值，可见性只派生到 Canvas/PDF。单独隐藏不改图表 XML；隐藏格的公式仍重算并更新完整缓存。保存重开保留来源尺寸和可见结果，查看与输出保持只读。已有失效引用继续采用缓存。

删除来源表或整行整列删除使分类、数值引用失效时，将对应引用最后可见的点冻结到原生缓存。分类和各数值引用独立保存长度，支持 `ptCount=0`，全部隐藏的系列不重新出现。饼图和圆环图将保留的类别颜色写入标准 `dPt`，其他系列保留原生 RGB 配色。引用、缓存、资源清理及源补丁共用一项精确历史，状态写回标准图表部件。

尚有效的来源继续计算，长度可以与其他有效来源或冻结缓存不同。核心按可见点顺序派生共同绘制矩阵，普通分类缺少的标签用序号，显式散点 X 缺项及缺少的数值留空；TSV 查询使用相同补齐规则，原生缓存保留独立长度。已有失效图表仍可修改外观、保存重开及继续输入；重新绑定后恢复当前来源及可见性。默认删除、外观面板、精确混合历史、实际 Canvas 和独立 PDF 已检查。需要改写缓存时，带源注释或处理指令的图表仍原子拒绝。实现归 [`chart-cache.mbt`](../../modules/formats/src/xlsx/chart-cache.mbt)、[`worksheet.mbt`](../../modules/formats/src/internal/chart/worksheet.mbt)及 [`worksheet-palette.mbt`](../../modules/formats/src/internal/chart/worksheet-palette.mbt)。缓存规则参考 [ONLYOFFICE 失效来源保留及零点缓存](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L12551-L12568)与[按可见来源保存点数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L12586-L12685)。共用绘制模型的普通矩阵校验保持等长、非空；独立来源缓存另受相同字符、系列、点数和数值预算约束。

可见性与配色实现归 [`xlsx/chart-visibility.mbt`](../../modules/formats/src/xlsx/chart-visibility.mbt)、[`layout/chart-visibility.mbt`](../../modules/layout/src/chart-visibility.mbt)及共用图表绘制。依据 [ONLYOFFICE 数值来源可见性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L12551-L12612)和[类别来源可见性](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L14111-L14208)。本项目保留完整缓存并单独派生可见数据，未复制上游执行代码。

每个数据区域最多 256 格，每图 1–8 个系列，每表绘图合计最多 256 项；框至少 180×150 pt，每轴不超过 14400 pt，位置沿工作表边界校验。引用最多 1024 个字符；文字、字体、计算工作和历史沿共用预算。当前只编辑共用模型能完整识别的普通图表。`plotVisOnly=0`、其他缓存结构、共享图表部件、复杂样式、旋转/翻转和未知原生变体保持保护。带源注释或处理指令的图表不进行整图及缓存改写，带这些内容的姿态或锚点不重写；源仍保留。普通图片及图表已有局部单元格插删，跨工作簿图表复制沿[绘图剪贴板合同](#工作表绘图剪贴板复制)保存独立数据；跨工作簿剪切继续实施。

实现归 [`chart-bindings.mbt`](../../modules/formats/src/xlsx/chart-bindings.mbt)、[`chart-edit.mbt`](../../modules/formats/src/xlsx/chart-edit.mbt)、[`chart-range.mbt`](../../modules/formats/src/xlsx/chart-range.mbt)、[`worksheet.mbt`](../../modules/formats/src/internal/chart/worksheet.mbt)及 [`xlsx-charts.ts`](../../packages/wasm/src/xlsx-charts.ts)。引用和缓存检查参考 [ONLYOFFICE 系列来源](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L2390-L2435)及[工作表与缓存比较](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L2495-L2540)。未复制上游执行代码。

### 单元格迷你图

`editSheet(revision, sheet, { action: "sparkline", cell, source, kind })` 在未合并的目标格创建或修改迷你图。`kind` 为 `line`、`column` 或 `winLoss`；`source` 为同一工作簿中一行或一列的区域，缺省使用本表，也可加工作表名称，例如 `'Source data'!A1:D1`。名称匹配忽略大小写，名称中的单引号写成两个单引号。`source: null` 删除该目标格的迷你图。每表最多 256 个目标，每个数据源最多 256 格。查询 `sparklines` 返回 `items: { cell, source, kind }[]` 及 `readOnlyReason`；本表源返回规范化区域，跨表源返回带引号的表名及区域。原有目标格内容保留，文字按原有规则显示。

核心单独保存来源表归属，从该表当前计算结果及行列可见性取数。来源改值或公式结果变化后，目标 Canvas/PDF 读取新数据；来源格隐藏时排除该格，目标表同坐标的值和尺寸不参与取数。目标表与来源表的整轴和局部单元格插删分别更新目标位置与实际源范围，沿现有范围、端点和 256 格上限。来源表缺失的新命令拒绝；导入的缺失来源保留原始定义，并在查询和诊断中说明原因，静态输出拒绝遗漏内容。外部工作簿及三维来源仍保护。数据绑定参考 [ONLYOFFICE sparkline.setF](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L8430-L8442)，绘制仍归共同迷你图图元。

清除内容和清除格式保留迷你图的原生定义及便笺。全部清除移除目标格在选区内的迷你图，包括空白目标；同次提交清除值、样式、规则及所属便笺。移除最后一个目标后删除本功能的空扩展。仅清除数据源时，选区外迷你图继续绑定原地址，图形随空值留空；重新输入数据后恢复 Canvas/PDF，无需重新绑定。已有 `#REF!` 保持失效。相关操作沿同一历史和输出预算，未知迷你图配置及未知扩展继续保护。默认三种清除按钮沿既有接口接入。行为参考 [ONLYOFFICE 清除选项](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L16669-L16704)，实现复用 [`clear.mbt`](../../modules/formats/src/xlsx/clear.mbt)及 [`clear-rules.mbt`](../../modules/formats/src/xlsx/clear-rules.mbt)。

四向填充及向外序列按源矩形循环复制迷你图的类型和位置。数据源按每个副本的行列位移平移，已有绝对地址也沿迷你图规则移动；每个端点裁到工作表边界，`#REF!` 保持失效。尾块只复制落入目标的格。目标原有迷你图先移除，因此源模式中的空白图形位置也会清除对应目标；范围外迷你图和各格便笺保留。只有图形变化时同样生成一项历史，重复填充有效状态不新增历史。向内缩减保留图形、绑定、格式和便笺，仅清除内容。新目标仍须未合并；合并源覆盖旧目标图形时先移除旧图形，保留新合并。每表 256 个目标及已有包/历史预算继续生效，失败不提交。默认四向按钮、原生改值、保存重开和 Canvas/PDF 沿同一核心结果。复制依据 [ONLYOFFICE 目标替换与平铺](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L22677-L22691)、[迷你图数据源位移](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L8070-L8091)及[端点边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L930-L972)。实现归 [`sparkline-fill.mbt`](../../modules/formats/src/xlsx/sparkline-fill.mbt)，复用现有填充事务。

整行、整列插入或删除时，核心用现有范围算法同步目标格和数据源。区域内部插入扩大源，删除缩小源；删除整个源后保留目标，原生公式与查询 `source` 为 `#REF!`，图形留空。用户重新填写区域可恢复显示；重新提交 `#REF!` 可保留失效绑定。目标格被删除时移除对应迷你图，最后一个目标删除后移除本功能的空扩展。源、单元格、公式缓存和选择共用一项精确历史。插入会丢失目标、丢失源端点或使数据源超过 256 格时，整项拒绝。结构位移与目标删除依据 [ONLYOFFICE updateSparklineGroupOffset](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L10369-L10418)。

局部 `insertCells` 的 down/right 与 `deleteCells` 的 up/left 沿同一事务更新迷你图。目标格在移动带内时移动或删除，源完整落在移动带内时按区域规则移动、扩缩或变为 `#REF!`。跨带源复用普通公式的引用规则：例如源为 `A1:D1` 时，在 `B1` 向下插入仍引用 `A1:D1`；删除 `A1:B1` 并向上移动后引用 `C1:D1`。插入只对完整落入移动带的源检查端点越界，不相交的源保持原样。目标格的便笺沿既有位移规则同步。依据 [ONLYOFFICE Range.isIntersectForShift](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L614-L637)；普通合并、筛选、原生表及未知资源的保护继续生效。

工作表 `rename` 更新所有已识别迷你图数据公式中的表名，保留绝对地址、命名空间前缀和失效绑定。`copy` 把表内迷你图复制到新表，本表数据引用改到副本，跨表数据引用保留原来源表；原表数据与图形保持独立。隐表副本沿用隐藏状态与原有活动选择。`delete` 通过既有事务删除表内迷你图及独占资源；其他表引用该来源的迷你图变为可重新绑定的 `#REF!`，其他来源保持可编辑。既有便笺复制、公式/名称和依赖更新规则继续生效。改名及其撤销/重做按工作簿中的实际表名刷新迷你图模型。复制与数据归属参考 [ONLYOFFICE 工作表复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L7439-L7444)及 [sparkline.updateWorksheet](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L8434-L8442)。

MoonBit 写入原生 x14 `sparklineGroups` 扩展、xm 数据公式与目标引用。每个目标单独保存类型，修改与删除只替换本功能拥有的扩展。其他部件和未知扩展保留。没有变化时不新增历史；源、选择及已有文档预算沿用同一事务。保存重开后仍可修改。类型与原生结构参考 [ONLYOFFICE sparklineGroup](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/WorkbookElems.js#L7804-L7842)，数据绑定与共用图表绘制参考 [CSparklineView](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/DrawingObjects.js#L682-L755)。未复制上游实现源码。

Canvas 和静态 PDF 复用单元格绘制。核心从当前计算结果取数，直接改值与公式结果变化会更新图形。源格隐藏时从序列中排除，空白、文字、布尔与错误值留空。折线在空值处断开，孤立点保留小标记；柱形与盈亏用蓝色表示正值、橙色表示负值，零值不画柱。盈亏只显示正负方向。线宽固定 0.75pt，图形在格内留 2pt 边距。自动行高只测量文字，迷你图跟随目标格尺寸。默认可访问网格通过描述暴露类型和源区域。

普通行列排序和原生表行排序保留迷你图目标地址、类型、数据源公式与原生扩展字节。即使目标格在排序范围内，图形仍读取原地址中的当前值；例如目标 `F2` 的源为 `B2:C2` 时，行排序后继续显示新 `B2:C2` 的值。标题、手动隐藏及筛选后的可见位置沿现有排序规则处理，便笺随所属单元格移动。原生表排序仍扩至完整数据行，保留筛选来源、计算模板及例外。再次改值继续更新图形，撤销/重做与保存重开保留同一绑定。未知配置、资源和预算失败保持原子拒绝。此行为沿 [ONLYOFFICE 单元格排序](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L21651-L21777)及[排序后的便笺和绘制更新](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L20693-L20700)。实现只为 [`sort-source.mbt`](../../modules/formats/src/xlsx/sort-source.mbt)、[`sort.mbt`](../../modules/formats/src/xlsx/sort.mbt)及原生表排序入口放行已验证扩展，复用既有排序与重绘。

普通区域和原生表去重移除原始重复行中、且目标格在有效选区内的迷你图；最后一个目标移除后删除本功能的空扩展。幸存图形保留原坐标与数据源，读取压紧后的当前格值；尾部格清空后，仍在该处的图形继续保留并显示空数据。范围外目标和 `#REF!` 绑定沿同一归属规则处理。便笺、链接及单元格按既有去重规则移动或删除；原生表继续缩小范围、迁移总计并保留模板、例外与筛选来源。预览保持只读，数据、图形和资源清理共用一项精确历史及输出预算，重复提交无变化时不新增历史。默认预览和删除入口沿核心资源校验；再次输入、撤销/重做、重开及 Canvas/PDF 共用当前模型。依据 [ONLYOFFICE 删除原始重复行资源后压紧](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L26112-L26136)。实现复用 [`duplicates.mbt`](../../modules/formats/src/xlsx/duplicates.mbt)、[`reorder-cells.mbt`](../../modules/formats/src/xlsx/reorder-cells.mbt)及既有迷你图删除。

区域复制通过结构化单元格剪贴板传递三种迷你图及失效绑定。`CopiedCells.sparklines` 为最多 256 项 `CopiedSparkline[]`，每项含源绝对目标格 `cell: { row, column }`、数据坐标 `source: CellRange | null` 和 `kind`；`null` 表示 `#REF!`。仅捕获选区内目标，快照不随之后的源图形编辑变化。源格须在矩形内、不重复且未合并；数据坐标须为有效的一行/列且至多 256 格。

仅 `all` 替换目标覆盖区的迷你图，源空白位置清除原目标，范围外图形保持。复制到同表、其他表或其他工作簿时，数据坐标随粘贴起点位移，并绑定目标表；原外表来源也按此规则转为目标本表来源。绝对标记不阻止迷你图位移，越界端点截定到表边界。转置交换目标格位置，数据区域保留原方向并应用同一粘贴位移。`values/formulas/format` 保留目标图形；若格式粘贴会合并目标图形格，整项拒绝。目标容量、未知配置及包输出失败保留源、选择和历史。图形、单元格、规则、链接及便笺使用同一事务，后续输入、精确撤销/重做、重开及 Canvas/PDF 读取当前目标数据。实现归 [`clipboard-sparklines.mbt`](../../modules/formats/src/xlsx/clipboard-sparklines.mbt)；数据归属与位移依据 [ONLYOFFICE 迷你图粘贴入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L28529-L28539)及 [moveSparklineGroup](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L10420-L10558)。

区域剪切复用同一工作簿内的 `moveCells` 事务。目标格随所选图形移动，目标覆盖区的旧图形移除；重叠区域先按源身份映射，空白源位置也清除旧目标。仅移动图形时，数据坐标和来源表保持：例如把 Sheet1 中读取 `A1:D1` 的图形搬到 Sheet2，仍读取 `'Sheet1'!A1:D1`。移动完整数据区域时，全工作簿中引用该区域的迷你图同步新坐标和来源表，保留其他表的目标位置；图形和数据一起移动时，共同归到新表。绝对地址不阻止内容移动，`#REF!` 绑定继续保留。

同表沿一行/列的数据轴移动部分端点时，范围按新端点扩缩；端点越过另一端时规范为升序范围。移动中间格、跨轴搬动端点及跨表移动部分来源时，原数据区域保持，继续读取原位置中的剩余值。单区域模型不生成多区域或跨表联合来源。变换后的来源和目标各受 256 格/项上限约束，受影响图形在受保护表中时整项拒绝。图形、便笺、超链接、原生部件和计算缓存共用一项精确历史与原有输出预算，创建资源后继续添加关系的组合也可完整撤销。默认剪切/原生粘贴、后续输入、重开及 Canvas/PDF 沿同一模型；跨工作簿、转置和选择性剪切继续按剪切合同拒绝。实现归 [`move-sparklines.mbt`](../../modules/formats/src/xlsx/move-sparklines.mbt)，范围移动与端点规则依据 [ONLYOFFICE moveSparklineGroup](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L10420-L10558)。

当前支持固定颜色、独立数轴、同一工作簿内的本表或跨表单区域及普通未合并目标。日期轴、组合轴、自定义颜色/标记、外部/三维来源和其他原生配置继续实施；未知配置保留并给出只读原因，静态 PDF 拒绝遗漏内容。其他表编辑沿各操作的资源保护。普通绘图锚点及图表当前范围归[工作表图表](#工作表图表)。实现归 [`sparkline.mbt`](../../modules/formats/src/xlsx/sparkline.mbt)、[`sparkline-edit.mbt`](../../modules/formats/src/xlsx/sparkline-edit.mbt)、[`sparkline-axis.mbt`](../../modules/formats/src/xlsx/sparkline-axis.mbt)及 [`sparkline-paint.mbt`](../../modules/formats/src/xlsx/sparkline-paint.mbt)。工作表操作复用 [`sheet-rename.mbt`](../../modules/formats/src/xlsx/sheet-rename.mbt)、[`sheet-copy.mbt`](../../modules/formats/src/xlsx/sheet-copy.mbt)和 [`sheet-order.mbt`](../../modules/formats/src/xlsx/sheet-order.mbt)。

### 透视表核心

普通区域行列轴透视表已接通 MoonBit、Wasm、Worker、编辑宿主和默认面板。`Session::pivot_preview(revision, settings)` 返回字段、记录数、类型化分组结果及总计，查询不写源或历史。预览最多返回前 20 个行分组，groups 和 truncated 说明完整输出行数（含小计、不含总计）及截断状态；总计与实际创建仍处理全部筛选后记录，JSON 继续受 1 Mi UTF-16 上限约束。`PivotSettings` 为 `{ sourceSheet, source, rows, columns, filters, subtotals, numberGroups, dateGroups, values }`；sourceSheet 是稳定工作表部件身份，source 包含标题行。rows 和 columns 使用相对源区域、从 0 开始的列索引；两轴不能重复字段，columns 空数组表示只有行轴；每项 values 为 `{ field, aggregate, name }`，name 是显示标题。标题按当前格式读取且不能为空，重复标题在缓存中分配唯一名称，不改源格；值标题不能与源字段名称重复。

filters 为 0–8 项 `{ field, values }`，field 使用源列索引且与行列轴及其他筛选字段互斥。values 为 null 时选择全部成员，自动包含后续新增成员；非空类型化 Value 数组表示固定选择，单字段内取并集，字段之间取交集。文字匹配合并大小写，数字、文字数字、布尔、错误与空白保持类型；每字段最多 4096 个成员。核心保留完整缓存记录与已选但暂时缺失的成员，刷新不静默重置选择。预览 recordCount 是源记录数，filteredCount 是筛选后记录数，filterItems 是各字段的 `{ value, label }` 候选项，label 由核心按源格式生成。零匹配允许，返回空分组及空白总计。

报表筛选格按字段顺序纵向排列，其后留一空行。目录 range、覆盖保护、更新原点和删除范围包含筛选格；原生 location.ref 仅含表头及聚合结果。选择保存为原生 pageFields、axisPage、item 与隐藏成员标记。默认面板提供全部/类型化多选，改动后预览再应用。横向、换行或未知原生分页布局保持保护。布局和成员筛选依据 [ONLYOFFICE 报表位置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L4323-L4342)、[成员筛选](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L5103-L5139)与[报表值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L5237-L5267)。

预览的 columnMembers 按列组合返回 `{ members, formats, subtotal }`，columnTotals 为每个列组合的值字段总计。每项 rows.values 按“列组合、值字段”展平，rows.total 是该行全部记录的总计；根 total 是筛选后源记录的总计。没有列轴时 columnMembers 为空、columnTotals 只含根总计，rows.values 仍按值字段排列。缺少记录的交叉格为空。行列边际直接累积源记录，平均值和样本统计不会对显示聚合值二次聚合。预览只截断行，全部有界列组仍受结果格数及 JSON 文字预算约束。

numberGroups 为最多 16 项 `{ field, start, end, interval }`。field 是行或列字段的源列索引，不能重复；start/end 分别接受有限数或 null；null 随完整源数值的最小值/最大值更新，不受报表筛选影响。全空源使用 0–1，常量源的自动终点使用该值加 1。解析后的 start < end，interval 必须为可推进边界的有限正数。每字段最多 4094 个区间，另含下界外/空白与上界外两项；未出现的区间不写输出行列。分组字段保留原始数值和空白共享项及缓存记录，另存原生 fieldGroup/base、rangePr 的自动标志和实际边界及 groupItems；作为值字段时仍聚合原始数值。区间按原生分组索引排序；小数边界复用既有 15 位 General 精度，end 包含在最后区间。整数成员与整数边界采用 0-4、5-10 等原生标题；空白并入下界外项，自动起点时该项标题为 (blank)。改变边界或移除分组沿现有字段更新、覆盖保护、清理与精确历史；刷新保留各边界的自动/固定设置；自动边界重新读取源值，扩张和超限仍先校验再提交。源新增文字/布尔/错误时拒绝刷新并保留原结果，用户可修正源或显式移除分组。默认面板提供字段、起点、终点、各边界的自动开关、间隔和移除入口，预览后应用。离散分组、人工成员标题和更广原生分组仍保持保护；原生自动边界与缓存源不一致时保留源并拒绝修改。数值分组项及原始共享项共用 1 Mi 文字预算，输出和聚合继续受既有限制。实现归 [`pivot-group.mbt`](../../modules/formats/src/xlsx/pivot-group.mbt)，依据 [ONLYOFFICE 分组结构](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L19402-L19430)、[边界映射](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L20523-L20545)、[标题](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L20581-L20612)、[源极值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L19263-L19282)、[刷新自动边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L15386-L15397)及[常量边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L20696-L20708)。

dateGroups 使用 `{ field, units }`。units 从 years、quarters、months、days 中按此顺序选择 1–4 个不同单位。同一源行/列字段不能同时数值和日期分组；数值字段数与日期单位数合计最多 16 项。年按年份分组，季度/月/日按原生日历部分分组；选择 years、months 可分开不同年份的月份，单选 months 则跨年合并。日使用含闰日的 366 项，Jan/Feb、Qtr1、1-Jan 等标题由核心生成。边界随源日期自动更新，空白独立显示。默认面板可多选、修改及移除单位，预览后应用。

最细单位使用原字段，其余单位追加原生派生缓存字段，设置 databaseField=0、fieldGroup/base 和原字段的 par。派生标题避开源字段及值标题，记录仍只包含源列。有效行列轴按由粗到细展开，每轴最多 8 层。预览 fields 包含源字段和派生标题，rowFields、columnFields 是有效缓存字段索引；settings 中的轴和分组仍使用源列索引。subtotals 选择多单位源字段时，为其展开后的外层单位启用小计。原生读取校验派生字段归属、顺序、标题、父关系及完整轴链；未知或不完整布局保持保护。实现归 [`pivot-group-read.mbt`](../../modules/formats/src/xlsx/pivot-group-read.mbt)，依据 [ONLYOFFICE 派生缓存字段](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L1884-L1907)与[分组轴展开](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L8028-L8060)。

核心以工作簿的 1900/1904 日期系统处理数值时间，不依赖浏览器时区。原始值用于聚合，源单元格及时间小数保留；缓存保存原生 d 日期共享项、自动边界 rangePr、单位、groupItems 与原始记录索引。ISO 日期时间包含时间小数，UTC 日期纪元及 1900 历史边界沿主参考规则。刷新、单位切换、小计、移除、删除和精确历史复用同一事务；日期缓存重开后可空操作刷新。坏日期、非法类型、过宽年份、未知单位、固定日期边界、非单位日间隔和手动标题保持保护。每字段最多 4094 年或 366 日，日期文本及分组成员共同遵守共享项文字预算。实现归 [`pivot-date-group.mbt`](../../modules/formats/src/xlsx/pivot-date-group.mbt)与 [`pivot-group.mbt`](../../modules/formats/src/xlsx/pivot-group.mbt)。依据 [ONLYOFFICE 日期缓存](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L12951-L13001)、[日历索引](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L20543-L20577)、[日历成员](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L20625-L20688)及[日期纪元与历史取值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/utils/utils.js#L3950-L4123)。

同步 `XlsxSession` 和 Worker `XlsxClient` 提供 `pivotPreview(revision, settings)` 与 `pivots(revision, sheet)`，返回 `XlsxPivotPreview` 和 `XlsxPivots`。目录的 sourceSheet、source、settings 使用对象/字符串或 null；不使用单元素数组表示可选字段。创建复用 `editSheet(revision, sheet, { action: "createPivot", settings, sourceRevision, name, destination })`；sourceRevision 必须等于当前 revision，拒绝沿用过期预览。刷新复用 `{ action: "refreshPivot", part }`。两种编辑返回普通 `XlsxQuery`，仍沿同一布局、恢复与保存路径。

已有行列轴透视表支持 `{ action: "updatePivot", part, settings, sourceRevision }`，对应 `Session::update_pivot(revision, sheet, part, settings)`。修改源表/范围、有序行列字段、值字段顺序、聚合与标题，保持透视表、缓存和记录部件身份及左上位置。源标题改变时，普通刷新仍拒绝推断映射；用户可按新源列号明确设置并预览后应用。至少保留一个行字段和一个值字段。更新复用刷新事务、扩张保护、缩小清理、格式保留和精确历史；相同定义与数据不新增历史。Values 轴标题与新字段冲突时分配唯一名称。字段行为依据 [ONLYOFFICE 行字段](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L6142-L6177)、[字段移除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L6285-L6315)和[值聚合](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L18305-L18308)。

`{ action: "deletePivot", part }` 对应 `Session::delete_pivot(revision, sheet, part)`。删除支持的独占透视表及结果，清除结果区的直接格式、受支持规则、便笺和完整包含的链接，重算依赖公式；其他透视表、普通数据和不相交结构化表保持。核心移除独占缓存、记录、定义及其关系部件、工作簿缓存入口和对应内容类型；最后一项同时移除 pivotCaches 容器。其他对象指向这些资源、共享缓存、未知定义/资源、合并或结构化范围重叠时拒绝；普通历史可精确恢复全部源与资源。删除语义依据 [ONLYOFFICE 对象移除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L11773-L11791)与[结果清理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L10766-L10777)。

`SpreadsheetEditor.pivotPreview(settings)`、`pivots()` 与既有 `editSheet(change, sheet?)` 使用同一队列，读取前提交已接受的原生草稿。默认面板选择源工作表、含标题的范围、有序行/列字段及最多八项值字段；UI 列号从 1 开始，API 从 0 开始。预览展示真实字段、类型化结果和总计，字段或 revision 改变后须重新预览；创建到当前工作表的指定空白格。目录显式读取当前工作表，显示源、结果范围、缓存状态和保护原因；工作簿改变后重新读取再刷新。预览与目录状态仅供显示，核心继续验证当前源、revision、覆盖冲突和资源预算。

目录中的“编辑透视字段”加载原生设置，预览后一次应用。行/列字段按输入次序排列，值字段可添加、删除并选择聚合；编辑时名称和目的位置保持。“创建另一张透视表”退出编辑模式。“删除透视表及结果”沿同一队列提交，完成后显示剩余目录；撤销和重做复用普通历史。

`Session::create_pivot(revision, sheet, name, destination, settings)` 在可见、未保护工作表的空白位置创建透视表。destination 是左上格。核心保存标准 `pivotTableDefinition`、`pivotCacheDefinition`、共享项及索引记录，使用工作簿缓存入口与部件关系链接；实际结果写入类型化单元格。行列字段组合按成员首次出现的顺序分层排列，文字比较合并大小写并保留首个拼写；数字、文字数字和布尔值各自分组。内部空白记录保留，末尾连续全空记录合为一条空白记录。只有行轴时保留单行标题和底部总计；有列轴时生成原生字段标题区、多级成员行、值标题行及底部/右侧总计。多值使用最后一项 Values 列轴，原生项保留值字段索引。位置、首数据行和列宽依据 [ONLYOFFICE 定位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L5657-L5723)与[表头写入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L10838-L10920)。

subtotals 是需要自动小计的外层行/列字段索引集合，空数组关闭小计；展开后的末层字段、重复项及非轴字段拒绝。小计位于所属组之后，采用值字段各自的聚合，直接读取筛选后的原始记录；行列小计交叉格与总计不再次累加显示结果。原生字段保存 defaultSubtotal、subtotalTop=0 及默认小计项，rowItems/colItems 保存 default 类型、字段深度及值字段索引。已有设置可加载、预览、修改和关闭，沿同一扩大保护、缩小清理与精确历史；重开刷新仍可用。上方小计、自定义小计聚合及其他未知布局保持保护。预览行与列成员新增 subtotal 布尔值，小计的 members/formats 只含所属字段前缀；UI 为剩余行字段补空表头格。原生标题沿源格式生成，预览继续保留原始类型。输出矩阵及分组预算包含小计，聚合工作量在累积前检查。实现依据 [ONLYOFFICE 小计项生成](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L5569-L5600)、[字段小计项](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L17035-L17065)和[格式化标题](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/Workbook.js#L11195-L11215)。

`Session::pivots(revision, sheet)` 返回 `{ revision, items }`。每项包含 part、name、range、sourceSheet、source、stale、settings 和 reason；不支持的原生定义返回 null settings 和保护原因。`Session::refresh_pivot(revision, sheet, part)` 重新读取当前计算值，整体替换缓存、记录、定义和输出。源值或依赖公式变化在普通事务中写入缓存失效标志；普通输入不自动刷新结果。结果格拒绝普通值/公式写入。刷新扩张必须有空白空间，缩小清空移出的结果格，保持区域外内容；旧位置内的直接格式保留。相同源与结果的刷新不新增历史。创建、源数据失效和刷新各用现有 revision、有界部件历史和包校验，保存重开后仍可刷新。

aggregate 接受 `sum`、`count`、`countNums`、`average`、`min`、`max`、`product`、`stdDev`、`stdDevp`、`var` 和 `varp`。count 统计非空记录，countNums 只统计数值。文字与布尔值不加入数值聚合，错误值沿数值结果传播；平均值和样本/总体统计按有效数值数目处理。规则依据 [ONLYOFFICE 聚合状态](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/databaseFunctions.js#L51-L220)、[类型与大小写缓存](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L3075-L3184)和[原生行列项](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/PivotTables.js#L5289-L5620)。

源最多 64 列、65536 个数据格，共享项及输出文字各最多 1 Mi UTF-16；行/值字段各为 1–8 项，列字段为 0–8 项，两轴各最多 4096 个明细/小计项，输出最多 32768 格。新建总数最多 16 项；导入目录读取最多 64 项。聚合及普通事务检查各受 1048576 项工作量、4 MiB 历史及包预算约束。输出与源、合并或结构化区域相交时拒绝，扩张时也保护便笺和链接。支持的刷新范围是原生普通区域行列轴、固定或自动数值边界分组、单级或多级日期分组及纵向报表筛选定义；共享缓存、横向或换行分页字段、手动成员顺序、扩展头部、未知源标记及属性继续保护。源标题变更需要字段映射，当前拒绝刷新；不能解析的源范围保护单元格编辑。样式、共享缓存及更广兼容继续实施。布局归 [`pivot-layout.mbt`](../../modules/formats/src/xlsx/pivot-layout.mbt)，其余实现归 [`pivot-cache.mbt`](../../modules/formats/src/xlsx/pivot-cache.mbt)、[`pivot.mbt`](../../modules/formats/src/xlsx/pivot.mbt)、[`pivot-refresh.mbt`](../../modules/formats/src/xlsx/pivot-refresh.mbt)、[`pivot-protection.mbt`](../../modules/formats/src/xlsx/pivot-protection.mbt)、[传输校验](../../packages/wasm/src/xlsx-pivot.ts)和[默认面板](../../packages/ui/src/xlsx-pivot.tsx)。

### 打印与资源边界

`editSheet({ action: "pageSetup", paper, orientation, left, top, right, bottom, scale, fitWidth, fitHeight })` 保存当前工作表的打印设置。`XlsxPrintSetup` 的纸张为 `A4` 或 `Letter`，方向为 `portrait` 或 `landscape`，边距为 point。边距须非负并在每个方向留下至少 12 pt 可打印空间；比例为 10–400 的整数，横/纵页数为 0–1024 的整数。0 表示该方向不限页数；任一页数非零时取代百分比，核心按实际行列分割，在 10%–100% 中求满足页数的最大整数比例。10% 仍不能满足时输出失败，不截断内容。页面与缩放范围参考 [ONLYOFFICE calcPrintScale](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L4580-L4808)。

`XlsxQuery.printSetup` 返回上述设置及 `readOnlyReason`。修改 `pageMargins`、`pageSetup` 和 `sheetPr/pageSetUpPr`，按 XML 顺序创建缺失节点，保留其他部件、单元格、公式缓存及计算链。边距写回 inch，查询和排版统一使用 point；新页边距包含 header/footer 的标准字段。一次设置一项历史，保持选择，重复设置不增加历史。保护、旧 revision、未知打印属性或预算失败保持源和历史。未知设置返回保护原因，其查询字段使用默认值占位，不能视为源文件的实际设置。

`editSheet({ action: "printRange", area, rows, columns })` 保存打印区域及重复标题。`area` 使用当前表 A1 矩形，多个矩形以逗号分隔（如 `A1:D20,F1:H20`），最多 32 项和 2048 UTF-16 单元；`rows` 使用整行区间（如 `1:2`），`columns` 使用整列区间（如 `A:B`），各最多 32 UTF-16 单元。各字段留空即清除该设置。接受绝对引用和小写列名，核心返回规范形式并保留区域顺序。`XlsxQuery.printRange` 返回这三个字段及 `readOnlyReason`，类型为 `XlsxPrintRange` 加保护原因。受保护源的空字段是查询占位，不能当作实际设置。

核心写入 `workbook/definedNames` 中带 `localSheetId` 的 `_xlnm.Print_Area` 和 `_xlnm.Print_Titles`，保留其他名称、已有名称属性、工作表源及计算缓存。每个区域分别写入带表名的绝对引用；导入的同表多区域定义使用同一路径。改名、复制、重排、删除及行列结构变化沿已有名称引用事务同步；名称中的空格、逗号和单引号按工作表引用规则处理。一次设置一项精确历史，重复设置不新增历史；旧 revision、表/工作簿结构保护及源/输出预算失败原子拒绝。重复或无作用域的打印名称、跨表定义和含未知内部标记的定义继续保护。

多个区域按定义顺序分别起页，不按地址排序、合并或去重；相交格会随各区域分别打印。各区域复用标题，每表共用满足全部区域页数设置的最大缩放比例；百分比模式保持指定比例。页码和首页/奇偶模板在同表区域之间连续，切表才重新开始。该规则参考 [ONLYOFFICE 多区域分页](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L3795-L3914)及[共用缩放](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L4698-L4735)。

重复标题只补当前页起点之前的行列，和正文重合时绘制一次。标题可在打印区域之外；隐藏行列保持隐藏。分页和适合页数都预留标题尺寸，过大的标题明确失败；不截掉标题来满足页数。该行为参考 [ONLYOFFICE 打印标题分页](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L3286-L3390)及[名称写回](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L23501-L23556)。

`editSheet({ action: "headerFooter", ...settings })` 保存纯文字页眉页脚，查询为 `XlsxQuery.headerFooter`，类型为 `XlsxHeaderFooter` 加 `readOnlyReason`。设置包含六个字符串 `oddHeader/oddFooter/evenHeader/evenFooter/firstHeader/firstFooter`，四个布尔值 `differentFirst/differentOddEven/scaleWithDoc/alignWithMargins`，以及 point 距离 `headerMargin/footerMargin`。默认六段为空，首页/奇偶页不区分，随表缩放并对齐边距，距纸张上/下边缘均为 21.6 pt。距离可设 0–14400 pt，实际文字越出纸张时打印失败。

每段最多 255 UTF-16 单元；留空清除。支持 `&L`、`&C`、`&R` 切换左、中、右部分，`&P` 为页码，`&N` 为本次输出总页数，`&A` 为当前表名，`&&` 为普通 `&`。未指定部分时居中，支持换行，CR/CRLF 规范为 LF。文字使用工作簿 Normal 字体、字号和黑色。字体、装饰、图片、日期/时间及文件字段控制码暂时保护，不能静默丢弃。源 `useFirstPageNumber/firstPageNumber` 可指定正整数页码起点；首页与奇偶模板按实际输出页序选择，不随起始页码改变。字段与模板语义参考 [ONLYOFFICE HeaderFooter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/HeaderFooter.js#L72-L123)及[页眉页脚绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L5301-L5405)。

六段与标志写入工作表 `headerFooter`，距离写入 `pageMargins` 的 inch 字段。缺失节点按源顺序创建，保留其他边距、根注释、单元格、计算缓存和非目标部件；重复设置不增加历史。表保护、未知标记、旧 revision、预算失败均不提交部分结果。未知源查询返回保护原因和默认占位值。页眉页脚沿核心字体与有序图元输出，随表缩放时仍保留物理边距和距离；关闭边距对齐时使用 17.8 mm 左右边距。页眉页脚按保存的位置绘制，不移动正文；距离和正文边距可产生重叠，越出纸张则拒绝输出。默认 UI 和自定义 UI 使用同一事务与输出屏障。

`SpreadsheetEditor.printLayout()` / `exportPdf()` 默认传递 null，打印当前表并使用已保存的纸张、边距和缩放。没有源设置时，核心默认 A4 纵向、四边 36 pt 和 100%。默认范围优先使用各表保存的打印区域，没有定义时使用该表有内容的矩形。`PrintOptions` 可单独给出 `range`、`sheets`，或一起给出六个临时 point 纸张字段 `width/height/left/top/right/bottom`；纸张字段必须全部提供。`range` 支持相同上限的逗号分隔矩形，非空时替代保存的全部区域。临时纸张和范围应用到每个目标表，保存的缩放、重复标题及页眉页脚继续适用。`checkPrintOptions` 校验同一边界。

`{ sheets: "visible" }` 打印全部可见表，`{ sheets: [id, ...] }` 打印指定的可见表，按当前工作簿顺序合并；列表顺序不改变工作簿顺序。列表须含 1–256 个不重复的稳定表身份，未知或隐藏表明确拒绝。各表保留自己的页面尺寸、缩放、打印区域、重复标题和页眉页脚；空表仍生成一页。页码起点及首页/奇偶模板在切表时重新开始，`&N` 使用整次输出的总页数。整体分页与字段语义参考 [ONLYOFFICE 工作簿打印](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorkbookView.js#L4144-L4200)及[切表后的页码](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/view/WorksheetView.js#L3978-L4002)。

多表共用 32768 格与 1024 页上限，不按表重新分配预算。任一目标表失败，整次输出失败，源、历史、活动表、选区及已有成功预览保持。`XlsxPrintLayout.sheet` 仍是请求时的当前表身份，不表示所有输出页来自同一表。默认 UI 提供全部可见表预览、跨表翻页、全部可见表 PDF 和当前表 PDF。导出其他范围时保留已显示的预览及其页码；PDF 不确认原 XLSX 已保存。

编辑会关闭旧预览，隐藏网格不再触发布局失败。参数草稿在普通命令繁忙时保持可编辑，提交仍等待队列，组合输入和文档切换继续阻止操作。

各区域分页先向下再向右，沿行列边界分割；无可见格的区域仍生成一页，超宽单列、超高单行、跨页/范围/标题边界合并、未计算公式、未支持显示或未呈现内容明确拒绝。网格和打印共享字体与尺寸，缩放在核心有序图元中完成。屏幕滚动、缩放和 DPR 不改变打印布局。区域与工作表共用整次输出预算，不为每个区域重置。更多纸张/布局变体继续实施。标题计入轴和单元格上限，标题与页眉页脚都计入每页文字上限。

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

当前 Web 范围不含模板向导、高级筛选、图表/图片编辑和协作。透视表的当前范围归[透视表核心](#透视表核心)。工作表/行列、格式、填充与普通区域排序的当前支持面见本节对应合同。XLS/XLSB/XLSM、其他浏览器、Windows/Excel、VoiceOver、性能专项与发布验收未进入本期验证。

## PPTX

`PresentationEditor.editSlides({ action: "size", width, height })` 修改全稿尺寸，单位为 pt，每边 1–14400，核心取整到 EMU。默认 UI 提供 16:9、4:3 和自定义宽高。`query.width/height` 返回实际尺寸，`slideSizeReason` 返回保护原因。各轴按新旧尺寸比例缩放全部页面及关联版式、母版的本地位置与尺寸；组的子坐标原点、范围及成员同时缩放。字号、描边宽度、旋转/翻转、对象身份、选择与其他资源保持。该规则依据 [ONLYOFFICE Presentation.changeSlideSizeFunction](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L805-L850)、[Shape.changeSize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L3235-L3266)和 [GroupShape.changeSize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L789-L805)。

尺寸、页面和设计部件合为一次有界历史。相同实际尺寸不新增历史；旧 revision、活动候选、保护、坐标越界和输出/历史预算失败原子拒绝。图表/表格等未知页面对象、未知变换坐标和未支持的扩展辅助线保护尺寸调整。原生视图辅助线同步按轴缩放，组不再次重算边界，保留缩放后的子坐标原点。未知部件与原有源片段保留。保存重开及 Canvas/PDF 使用相同的新尺寸和几何；反复改变比例可能产生 EMU 或辅助线坐标取整，撤销恢复原始源字节。

### 幻灯片辅助线

`PresentationEditor.editSlides({ action: "guides", visible, items })` 修改文稿的原生视图辅助线。同步 Wasm/Worker 使用相同的 `editPptxSlides` 命令；核心使用 `SlideEdit::Guides`。`PptxQuery.guides` 返回 `{ visible, items, reason }`。`PptxGuide` 为 `{ orientation: "horz" | "vert", position: number }`，`position` 从页面顶部或左侧起算，单位为磅。`PptxGuide` 和 `PptxGuides` 从 `wasm/pptx` 与 `web/pptx` 导出。

一次命令提交完整列表与显示设置，最多 64 条。核心将有限位置取整到 1/8 磅，原生 `pos` 保持有符号 32 位整数，允许页面外的位置。默认面板可新增水平或垂直线、修改位置、移除单线或清空；新增从页面中点开始，同向后续线向后偏移 12.5 磅并限制在页面边界。面板草稿须显式应用。编辑 Canvas 以虚线显示，隐藏保留列表；放映及静态 PNG/JPEG/PDF 使用内容布局，不包含辅助线。

写回只改 `viewProps` 中的 `slideViewPr/cSldViewPr` 显示属性与 `guideLst`。缺少视图部件时创建标准部件、关系和内容类型，合为一项精确历史。其他视图设置、吸附属性、外围注释、页面内容、选择和对象身份保留。页面改尺寸时，水平位置按高度比例、垂直位置按宽度比例一起缩放。相同实际值无操作；旧 revision、活动候选/放映、修改保护、歧义或外部视图关系、未知辅助线结构或范围内注释及资源失败整体拒绝并保留原包。

编辑 Canvas 已支持拖动。已选对象及其尺寸手柄优先，其他位置按 4 个屏幕像素的容差查找辅助线；交叉或重叠时选择源顺序最后的一条。`beginGuidePptx` 接收 `{ revision, x, y, tolerance }`，核心未命中或辅助线隐藏时返回无候选的当前查询；命中则返回既有 `candidateId`。后续使用 `dragPptx` 的相对指针位移和 `handle: 0`，只改变水平线的纵坐标或垂直线的横坐标，在页面边缘按原生精度取整。横向移动水平线、纵向移动垂直线以及零位移均不改位置。

拖动预览只更新候选及 `guides.items`，保持 revision、原生源和历史。`cancelPptx` 或默认输入的 Escape/指针取消恢复原值；`finishPptx` 复用既有提交、预算和精确历史，成功移动只新增一项。活动候选期间，保存、结构修改及其他编辑继续沿既有保护。普通数值面板仍提供键盘可操作入口。移动与边界规则参考 [ONLYOFFICE CGuideTrack](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/MoveTracks.js#L954-L1025)。候选实现归 [`guide-gesture.mbt`](../../modules/formats/src/pptx/guide-gesture.mbt)，平台指针队列归 [`presentation-pointer.ts`](../../packages/web/src/presentation-pointer.ts)。

对象移动和角点缩放已支持吸附辅助线及其他对象。移动按各叶对象的四个变换后角点与中心计算，整组使用成员点，多选使用全部所选点。缩放使用所拖角点；组内对象和多选框沿同一世界坐标计算，再回到原有父坐标变换。目标取当前源部件的未选叶对象，同样使用变换后四角与中心；所选组的全部成员排除，普通视图不使用继承的母版/版式对象。旋转、翻转、嵌套组和无宽/高直线沿已有几何。两个轴各取容差内绝对距离最小的修正，等距保留先遇到的移动点，再按目标源顺序保留；对象目标先于等距辅助线。目标排序并二分查找，避免多选逐点全配对。某轴位移为零时保持该轴，最小尺寸、文字适配和资源限制继续生效。

对象间吸附缺省开启；导入视图 `cSldViewPr.snapToObjects="0"` 时关闭，未知属性值不用于对象吸附。辅助线继续独立参与计算。对象拖动不改写视图设置、目标对象或其资源，Alt 仍提供自由定位。网格与永久设置、动态对齐标记见下文。

`dragPptx.tolerance` 沿用页面磅值，缺省为 0，不吸附。默认指针使用 6 个屏幕像素换算的容差，按住 Alt 或在释放时保留 Alt 则传 0；预览队列和最终指针位置保留修饰键。键盘移动、数值变换仍按明确坐标定位。隐藏只控制辅助线显示，已有位置仍可吸附；清空列表移除这些目标。未知辅助线保留原源，不参与吸附，其原因继续显示于 `guides.reason`。取消、一次提交、精确历史和保存重开共用原有对象事务，辅助线部件不因对象吸附而改写。

取点与最近距离依据 [ONLYOFFICE calculateSnapArrays](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L733-L746)、[最近点](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L10510-L10557)及[移动轴修正](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/States.js#L1633-L1736)。实现归 [`object-snap.mbt`](../../modules/formats/src/pptx/object-snap.mbt)。默认辅助线列表有高度上限并可滚动，避免大量条目占满编辑区。

位置换算及新增规则参考 [ONLYOFFICE ViewPr](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/ViewPr.js#L441-L452)、[新增](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/ViewPr.js#L576-L618)及[缩放](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/ViewPr.js#L774-L781)；原生部件结构参考 [ONLYOFFICE CSldViewPr](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/ViewProps/CSldViewPr.cpp)。实现归 [`guides.mbt`](../../modules/formats/src/pptx/guides.mbt)与 [`pptx-guides.tsx`](../../packages/ui/src/pptx-guides.tsx)。母版/版式的扩展辅助线及备注辅助线继续实施。

### 动态对齐标记

对象移动或角点缩放命中其他对象时，`PptxGeometry.snapLines` 返回临时对齐线。每项复用 `PptxGuide` 的 `{ orientation, position }`，位置为页面磅值；未命中、Alt/`tolerance: 0` 或非对象变换时返回空数组。默认 Canvas 用独立颜色的虚线绘制，复用辅助线绘制路径。标记仅属于当前候选，不写入视图部件、文稿历史或内容布局。

核心沿已选叶对象的四角/中心及活动缩放角点取目标，保留与最终吸附修正在原生 EMU 精度内一致的对象位置；等距目标仍按原有规则选择。每个方向去重并最多保留 64 条，顺序沿移动源点采样。返回前核对实际候选的世界坐标，最小尺寸或其他预览约束使对象未到达目标时隐藏该线。来源为已有辅助线或网格的吸附不额外生成对象标记，零位移轴保持无标记。多选、整组、旋转及嵌套成员沿同一规则。

后续拖动样本重新计算标记；明确数值变换、取消、提交、撤销重做及重开不保留它们。布局身份与现有选择几何共用，Web 只执行核心返回的位置，不重算吸附。源及历史继续使用原有候选事务，放映和静态输出沿内容布局。取点、同位移目标及辅助线排除依据 [ONLYOFFICE MoveState](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/States.js#L1633-L1774)，显示入口依据 [DrawVerAnchor/DrawHorAnchor](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/DrawingDocument.js#L2793-L2832)。实现归 [object-snap.mbt](../../modules/formats/src/pptx/object-snap.mbt)、[hit.mbt](../../modules/formats/src/pptx/hit.mbt)及 [presentation-canvas.ts](../../packages/web/src/presentation-canvas.ts)。

### 等间距吸附与提示

对象移动支持在两侧邻居之间居中，或延续同侧已有的对象间距。核心使用选区整体的世界外框，在另一轴投影有正重叠的同父本地对象中找最近邻居；整组按外框参与，选中对象及其成员、继承对象不作为邻居。多选共同平移，组内成员沿原有父坐标转换。候选使用既有屏幕像素容差：对象边缘/中心和辅助线优先，未命中的轴再尝试等间距，最后回退到网格。等距离时保留居中、左/上延续、右/下延续的稳定顺序。

`PptxGeometry.snapSpacing` 返回零至四项 `PptxSpacing`：`{ axis: "x" | "y", from, to, at }`。横向箭头从 `(from, at)` 到 `(to, at)`，纵向从 `(at, from)` 到 `(at, to)`；坐标为页面磅值，每轴成对显示。返回前用实际候选外框重查相等间距，量化、约束或页面外位置不符合时隐藏箭头。默认 Canvas 只在选择覆盖层绘制双向箭头，源、内容布局、放映和静态输出沿原路径。

等间距沿 `snapToObjects` 开关。角点缩放、零位移轴、Alt/`tolerance: 0` 和明确数值变换不使用该吸附；取消、提交、历史操作和重开清理提示。没有新增命令或保存设置。外框和间隔沿已有分布几何，参考 [ONLYOFFICE distributeHor/distributeVer](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L9484-L9585)。交互依据本地 GenOffice 的 `snap.ts` 与 `SlideCanvas.tsx`；核心独立实现有界邻居扫描，不复制其引擎。实现归 [spacing-snap.mbt](../../modules/formats/src/pptx/spacing-snap.mbt)、[object-snap.mbt](../../modules/formats/src/pptx/object-snap.mbt)及 [presentation-canvas.ts](../../packages/web/src/presentation-canvas.ts)。同尺寸提示归[缩放同尺寸吸附与提示](#缩放同尺寸吸附与提示)，扩展辅助线仍按 P12 实施。

### 比例缩放手势

按住 Shift 拖动对象角点时，核心保持初始框的宽高比。单张图片或仅含图片的多选默认保持比例；普通形状、整组及混合多选在未按 Shift 时沿独立宽高缩放。组内成员使用原有父坐标转换，未启用中心缩放时，旋转和翻转保持相对角点。多选以原选择框的统一比例缩放成员，最小尺寸沿原有约束。零宽或零高的选择框保留既有退化轴规则。

低层 `dragPptx` 增加可选布尔值 `shift`，缺省为 `false`；MoonBit 使用 `Session.drag(..., shift=true)`。指针合并预览和最终释放各自传递当前修饰键。比例约束优先于全部吸附，清理临时对齐线、间距箭头和同尺寸标记；Alt 关闭吸附并启用[从中心缩放](#从中心缩放)，不取消比例约束。移动、连接线端点和明确数值变换继续使用既有操作规则。没有新增文稿设置，取消、单次提交、精确历史与重开沿原候选事务。

缩放系数取两个尺寸绝对值系数中的较大值，依据 [ONLYOFFICE ResizeTrackShapeImage.resize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L634-L689)。图片默认比例和比例优先于吸附的交互对照本地 GenOffice `SlideCanvas.tsx` 的 `ratioLocked` 与 `boundBoxFunc`。实现归 [object-snap.mbt](../../modules/formats/src/pptx/object-snap.mbt)、[object-selection.mbt](../../modules/formats/src/pptx/object-selection.mbt)及 [presentation-pointer.ts](../../packages/web/src/presentation-pointer.ts)。中心手势归[从中心缩放](#从中心缩放)，跨边方向归[跨边缩放与翻转](#跨边缩放与翻转)。

### 从中心缩放

角点缩放时按住 Alt/Option，保持初始框的中心；非 Mac 的 Ctrl 也启用同一约束。移动时 Alt 继续自由定位。低层 `dragPptx.center` 为可选布尔值，缺省 `false`；MoonBit 使用 `Session.drag(..., center=true)`。指针合并预览和最终释放分别传递当前状态，松开后回到原相对角点规则。Alt/Option 继续同时关闭吸附，不关闭 Shift 或图片默认比例。

核心将活动角点在框坐标中的位移乘二，再沿现有旋转/翻转和父坐标计算中心锚点。普通形状、图片、整组及同父多选/成员共用既有候选与源事务；多选以原选择框中心统一变换。可与比例、最小尺寸、组边界、连接对象更新、取消、单次提交及精确历史共同使用。单条直线沿 ONLYOFFICE 的既有端点规则忽略中心约束；移动、连接线端点和明确数值变换保留原行为。文字和表格最终尺寸继续受既有自动适配约束。

独立使用 `center=true` 且保留容差时，对象尺寸匹配按活动边的屏幕位移判断；完整宽高改变量为边位移的两倍。匹配后继续固定中心，其他轴复用原有网格/边缘/辅助线规则。实际几何仍由核心复核；比例约束优先于全部吸附。没有新增文稿设置或保存状态。

位移系数与中心位置依据 [ONLYOFFICE resizeRelativeCenter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L1019-L1120)。默认修饰键对照本地 GenOffice `SlideCanvas.tsx` 的 `centeredScaling` 与 Alt/Option 交互。实现归 [object-snap.mbt](../../modules/formats/src/pptx/object-snap.mbt)、[object-selection.mbt](../../modules/formats/src/pptx/object-selection.mbt)、[size-snap.mbt](../../modules/formats/src/pptx/size-snap.mbt)及 [presentation-pointer.ts](../../packages/web/src/presentation-pointer.ts)。跨边方向归[跨边缩放与翻转](#跨边缩放与翻转)。

### 跨边缩放与翻转

角点越过固定对边时，核心保留有向宽高；负值转为正尺寸，并切换对应的原生翻转位。普通缩放保持原相对角点，中心缩放保持原中心。预览始终基于手势起点，拖回原侧时恢复原方向，不累计翻转。Shift 与图片默认比例按尺寸绝对值取统一系数；接近零时沿既有最小框约束，直线保留允许的零宽或零高轴。

普通形状、图片、整组及同父多选/成员沿同一候选。多选反射各成员中心；奇数次轴反射同时反向成员旋转角，继续使用既有非等比缩放规则，不生成剪切。原生表格继续限制翻转；缩到单元格边距以内时按原规则原子拒绝。连接线端点仍使用原端点手势。

同尺寸吸附匹配跨边后尺寸的绝对值，再换回带方向的角点位移，保留原有容差、优先级与实际几何复核。数值变换继续接受正尺寸并从原源重算。源写回共用原生 `rot/flipH/flipV` 变更，位置和尺寸不变而仅方向变化时，也提交一次精确历史；取消、撤销重做、图片字节和其他部件沿原事务保留。

尺寸符号、翻转与固定点依据 [ONLYOFFICE ResizeTrackShapeImage.resize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L690-L760)及 [resizeRelativeCenter](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L1045-L1120)。实现归 [object-snap.mbt](../../modules/formats/src/pptx/object-snap.mbt)、[object-selection.mbt](../../modules/formats/src/pptx/object-selection.mbt)、[editing.mbt](../../modules/formats/src/pptx/editing.mbt)、[geometry.mbt](../../modules/formats/src/pptx/geometry.mbt)及 [object-arrange.mbt](../../modules/formats/src/pptx/object-arrange.mbt)。没有新增命令、文稿设置或宿主数学。

### 缩放同尺寸吸附与提示

单个未旋转的本地顶层对象在角点缩放时，可匹配其他本地顶层对象的原生框宽或高。普通形状和整组沿现有变换；图片、连接线、组内成员、多选及带旋转/倾斜的活动框继续使用既有缩放规则，不参与尺寸匹配。匹配按现有屏幕容差换算到框坐标，各维度取最近值，等距保留目标源顺序。只处理有位移的轴，保持对边和相对角点。已匹配尺寸的轴优先于网格与边缘/辅助线，其他轴沿原规则处理。

`PptxGeometry.snapSize` 返回零至 64 项 `PptxSizeMatch`：`{ object, width, height, outline }`。`object` 为目标身份；两个布尔值说明哪些原生尺寸与实际候选相等，至少一项为真；`outline` 是目标四角的页面坐标。相同目标合并成一项，按源顺序保留。核心在返回前重新检查实际尺寸，量化或预览约束不再匹配时隐藏提示。Canvas 仅在选择覆盖层描绘目标的虚线外框，不重算匹配和几何。

尺寸匹配沿 `snapToObjects` 开关；Alt/`tolerance: 0`、明确数值变换及候选结束清理标记，取消、提交、历史和重开保留原有源事务。没有新增命令或保存设置；提示不进入文稿内容、放映或静态输出。比例手势归[比例缩放手势](#比例缩放手势)，更广旋转/组内尺寸匹配继续实施。坐标转换和固定点沿 [ONLYOFFICE getResizeCoefficients](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L2212-L2312)及既有核心变换；交互对照本地 GenOffice `SlideCanvas.tsx` 的同尺寸边框提示。实现归 [size-snap.mbt](../../modules/formats/src/pptx/size-snap.mbt)、[object-snap.mbt](../../modules/formats/src/pptx/object-snap.mbt)、[pptx-view.ts](../../packages/wasm/src/pptx-view.ts)及 [presentation-canvas.ts](../../packages/web/src/presentation-canvas.ts)。

### 网格与吸附设置

`PresentationEditor.editSlides({ action: "snapping", grid, objects, spacing })` 同时修改网格开关、对象间吸附开关和统一间距。同步 Wasm/Worker 使用既有 `editPptxSlides`，核心使用 `SlideEdit::Snapping(SnapSettings)`。`query.snapping` 返回 `{ grid, objects, spacing, reason }`；对象开关同时控制等间距和同尺寸吸附。类型 `PptxSnapSettings` 和含原因的 `PptxSnapping` 从 `wasm/pptx` 与 `web/pptx` 导出。默认面板提供这三项设置和显式应用，普通对象或文字编辑保留未应用草稿。辅助线吸附独立于两个开关。

`spacing` 单位为磅，接受 1 EMU（1/12700 磅）至 144 磅，并按整数 EMU 保存。网格缺省关闭，对象间吸附缺省开启，默认间距为 360000 EMU。沿 ONLYOFFICE 使用原生 `gridSpacing.cx` 作为两轴间距；导入超大单位按其 1000 倍修正规则读取。只改开关时保留原 `cx/cy`，明确修改间距才将两者设为同值。写回保留未知属性、辅助线内容、其他视图源和全部页面；缺少视图部件时创建关系及内容类型，设置与必要源变更只提交一次精确历史。旧 revision、活动候选/放映、保护、无效参数及资源失败保留原包。

网格以页面中心为基准，使用原生 EMU 换算和就近取点。移动按活动对象的世界外框左上角定位；多选共同平移，组内对象沿原有父坐标转换。每个方向先找容差内的对象或辅助线，再尝试[等间距](#等间距吸附与提示)，仍未命中时落到最近网格。自由比例的角点缩放先匹配[原生尺寸](#缩放同尺寸吸附与提示)，未匹配的轴将活动角点落到网格，再进行对象/辅助线吸附，最小尺寸及文字适配继续生效。位移为零的轴保持；`tolerance: 0`、Alt、键盘及明确数值变换继续自由定位。修改页面尺寸后按新页面中心计算，网格间距保持原生绝对值。编辑网格已有独立显示开关；动态对齐标记见上文。

`PresentationEditor.setGridVisible(visible)` 切换编辑网格，`gridVisible` 返回当前显示值，默认面板提供对应复选框。开关属于当前编辑宿主的临时视图，缺省隐藏；关闭文件后释放，重开重新隐藏。它独立于网格吸附开关，不写入 PPTX，不改变 revision、历史、选择、修改标记或原格式字节。沿现有队列、活动输入及保护条件使用；控件即时显示选择并与外部 API 结果同步，失败恢复实际状态。

低层 `selectionPptx` 可传 `gridScale`，单位为每磅的 CSS 像素数，有限且位于 0.1–16。MoonBit 使用 `Session.selection_geometry(layoutId, grid_scale=Some(scale))` 生成网格；`PptxGeometry.grid` 返回 `{ points, cross }`，未请求时为 `null`。几何绑定已有布局，旧布局拒绝。核心共用原生中心及间距，按上游最小内间隔和主线间隔生成点阵；缩放后使用点或十字。每次最多 16384 点，极细间距或大页面只降低显示密度，保留实际吸附间距和源设置。Web 只绘制这些点，网格、辅助线和选择保持独立绘制状态。放映及静态 PNG/JPEG/PDF 使用内容布局，不包含编辑网格。显示密度依据 [ONLYOFFICE CStrideData.drawGrid](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L1565-L1683)，开关与输出边界依据 [drawViewPrMarks](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L1685-L1713)。

依据为 [ONLYOFFICE 网格间距](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/ViewPr.js#L241-L263)、[CStrideData](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L1512-L1564)、[移动回退](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/States.js#L1738-L1774)与[缩放指针](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/States.js#L1468-L1481)。实现归 [`snapping.mbt`](../../modules/formats/src/pptx/snapping.mbt)、[`object-snap.mbt`](../../modules/formats/src/pptx/object-snap.mbt)及共用的 [`view-properties.mbt`](../../modules/formats/src/pptx/view-properties.mbt)。

页面背景使用 `PresentationEditor.editSlides({ action: "background", value }, slide?)`。`value` 是 `PptxBackgroundFill`：纯色为 `{ kind: "solid", color }`，线性渐变为 `{ kind: "linear", stops, angle, scaled }`。`stops` 含 2–32 项 `{ position, color, opacity }`，颜色均为不带 `#` 的六位 RGB。`null` 移除本页背景并恢复版式、母版继承。`query.background` 返回有效 `value`、本页是否设置 `explicit` 与保护原因 `reason`；没有背景时返回白色纯色。`value` 的查询类型为 `PptxBackground`，还包含下节的图片背景；两个类型均由 `wasm/pptx` 和 `web/pptx` 导出。核心使用 `BackgroundFill`。

色标 `opacity` 须有限并位于 0–1，核心舍入到 1/100000；1 为不透明，0 为全透明。背景以白色页面为底，形状与既有内容合成。位置须有限、位于 0–1 并按非递减顺序排列。核心将位置舍入到 1/100000，写入原生整数位置，不自动排序。同位置色标形成突变，首尾可以位于内部，外侧延续对应端点颜色。`angle` 为顺时针 0–360 度，核心舍入到 1/60000 度并把 360 规范为 0；0 从左至右，90 从上至下。`scaled` 必须为布尔值；true 按页面长宽比调整角度，false 保持实际角度。导入可解析主题/系统颜色、已有明暗及按源顺序计算的 alpha/alphaMod/alphaOff 变换，保留未改源；路径渐变、非零平铺矩形和复杂效果继续保护；图片背景见下节。有效背景随版式/母版继承，复制页与尺寸调整沿相同解析；修改背景不改对象身份或几何。角度规则依据 [ONLYOFFICE getGradientPoints](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/editorscommon.js#L15290-L15511)。

操作复用 revision、候选保护、输出预算和精确撤销重做；本页已有相同有效背景时为无操作。默认面板提供背景类型、色标增删、位置/颜色/不透明度、角度/比例设置和恢复继承；原生文字编辑保留尚未应用的背景草稿。核心复用现有矩阵与水平渐变原语生成任意方向，Canvas/PDF 不解析 DrawingML。定向检查覆盖继承、方向/比例、色标与突变、源保真、历史、重开输入、真实 Canvas 颜色及独立 PDF 渲染颜色，证据归[测试说明](testing.md)。其他背景与母版编辑仍待实现；主题颜色和字体见下节。修改本页背景的语义参考 [ONLYOFFICE Slide.changeBackground](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L825-L829)，实现归 [`background-fill.mbt`](../../modules/formats/src/pptx/background-fill.mbt)和 [`slide-background.mbt`](../../modules/formats/src/pptx/slide-background.mbt)。

### 图片背景

`PresentationEditor.editSlides({ action: "backgroundImage", bytes, mode }, slide?)` 设置或替换本页 PNG/JPEG 背景，`mode` 为 `stretch` 或 `tile`。Wasm/Worker 使用同一 `editPptxSlides` 命令。输入沿图片写入上限：4 MiB、单边 4096 像素及总计 4 Mi 像素。原图片字节、关系、内容类型和背景源合为一次有界事务；保留对象、选择与非目标部件，支持精确撤销/重做、页面复制及保存重开。重复设置相同本地图片及模式不增加历史，旧资源继续保留，不做包清理。

`{ action: "backgroundImageFormat", mode, crop, opacity }` 一次设置已有图片背景的模式、四边裁剪和不透明度，保留资源键及已有平铺参数。`crop: [left, top, right, bottom]` 为移除源图的比例，各项非负且小于 1；核心按 1/100000 舍入，两侧之和须小于 1。`opacity` 为 0–1，使用相同精度并乘上源像素 alpha。四个零移除裁剪，1 移除常量 alpha 覆盖；本地有效同值不增加历史。`tile` 保留非零裁剪，绘制整张源图；切回 `stretch` 后重新应用原裁剪。平铺沿用已有参数或标准默认值，也可在一次命令中重置裁剪并切换模式。继承图片可创建本页覆盖，继续复用原资源；本地替换只修改图片引用，格式编辑只修改变化的 `stretch/tile`、`srcRect` 和 `alphaModFix`；保留 `dpi/cstate/rotWithShape` 等已识别源属性、已有图片关系和其他部件。`{ action: "background", value: null }` 恢复继承，受支持的纯色/渐变命令也可替换图片背景。默认背景面板提供类型、图片、模式、四边百分比、裁剪重置、不透明度及恢复继承，格式一次应用并进入同一历史；文件读取绑定目标页，读完后检查目标是否改变。

`query.background.value` 的图片分支为 `{ kind: "image", key, crop: [left, top, right, bottom], opacity, mode }`，其余分支仍为纯色与线性渐变。`key` 是核心图片资源身份，`crop` 是非负源裁剪比例，`opacity` 为 0–1。按幻灯片、版式、母版顺序选择背景，并按实际来源部件解析内部图片关系；主题 `bgRef` 也按主题部件解析。导入保留 `srcRect` 和常量 `alphaModFix`，替换图片继续保留这些值；格式候选沿用原资源和整页裁剪，不生成图片副本。缺图片、非法模式/数值、舍入后空源区域、未知源及预算失败保留源、选择和历史。拉伸展开后的宽高各不超过 1e9 pt；平铺的未生效裁剪不参与这个展开检查，切回拉伸时重新验证。

背景先铺白底，再裁剪到整页并使用既有图片图元，前景对象随后绘制。拉伸以有效源矩形覆盖页面；平铺复用[形状图片](#形状图片填充)的 96 DPI、缩放/偏移、九种对齐及交替翻转，保留但不应用源裁剪。背景、形状填充和独立图片合计每页最多 65536 格；写入、模式、尺寸及变换候选先验证此上限。背景图片计入全稿 256 项使用中图片及既有字节/历史预算，预览、PNG 和 PDF 使用同一资源清单。目标内缩归[图片目标内缩](#图片目标内缩)；外链和未知效果继续保护；不抓取外部图片，也不删除未知源来替换背景。

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

### 母版与版式编辑视图

`PptxQuery.editView` 返回 `kind: "slide" | "master" | "layout"`、返回普通视图的 `slide`、`choices`、`reason` 和 `operations`。`operations` 的 `rename/addLayout/copyLayout/deleteLayout/deleteMaster/addMaster/copyMaster` 分别返回保护原因，空串表示允许。每项源选择包含 `id/name/kind/master`。目录沿文稿声明的母版及版式读取，包含未被页面使用的源；最多 256 个母版和 256 个版式，目录合计最多 1 Mi UTF-16 单元。未知、重复或归属错误的引用保护整个源目录。

`PresentationEditor.showSlide(part)` 和 `selectPptx.slide` 接受目录中的源部件路径。`query.slide` 指向当前源，`query.slides` 始终只列真实幻灯片。默认页栏的“编辑视图”选择器切换母版、版式与普通页面。当前源的本地对象沿既有文字、外观、几何、组合及图片资源事务编辑；普通视图中的继承对象继续只读，版式视图中的母版装饰也只读。

修改写回源部件并重读引用页面，保留页面直接覆盖。需要重新适配的依赖文字框复用字体度量和原有尺寸锁，源、依赖框、资源和前后选择合为一次有界历史。共享框需要不同尺寸、缺字体或预算失败时整项拒绝。未使用的当前源也检查字体、对象、图片和输出预算。当前源最多 4096 个可见对象，并与实际页面共同遵守现有总预算。

保存和整稿输出始终使用真实幻灯片，当前画布输出可使用所选源。切回页面、精确撤销/重做和重开继续保留源身份与关系。模板提示文字不写入页面用户文字。源视图暂不显示普通页的页序、备注、动画、主题及查找面板。

`editSlides({ action: "masterTextStyle", kind, level, format }, masterPart?)` 编辑目标母版的默认字符格式。`kind` 为 `title/body/other`，`level` 为 0–8；默认面板显示为第 1–9 级。`format` 复用 `PptxTextFormat` 的字体、字号、字符间距、粗斜体、颜色、下划线、删除线、高亮和上下标，按指定属性合并。`format: null` 移除该级 `defRPr`，恢复字符继承，保留段落及列表定义。缺失的 `txStyles`、类别和级别按原生顺序创建，已知元数据在普通修改时保留；扩展属性、注释、未知字体或填充标记保护目标格式。

`editView.textStyles` 返回 `{ items, reason }`。母版视图含三类共 27 项 `{ kind, level, format, reason, paragraph }`，`format` 返回完整有效字符值，字体显示 Latin 槽的解析结果；受保护项返回空格式和原因。`paragraph` 沿 `PptxParagraphFormatting` 返回有效段落、列表和制表位，并增加 `alignment`；其保护原因与字符格式分开。普通页和版式视图返回空目录及切换提示。本地字符、段落、占位符列表样式继续优先于母版默认格式。母版修改按当前母版、所属全部版式、实际页面的顺序重排，包含未使用版式的本地自动框；页面沿更新后的版式尺寸适配。源组边界沿已有归一化更新，保留页面姿态及本地覆盖，源提示文字保持在源部件。字体预检、尺寸锁、几何/资源及输出预算检查共用提交，选择、源和必要框尺寸共用一次精确历史。版式重排实现归 [`layout-reflow.mbt`](../../modules/formats/src/pptx/layout-reflow.mbt)。实现归 [`master-text-style.mbt`](../../modules/formats/src/pptx/master-text-style.mbt)，继承顺序依据 [ONLYOFFICE Shape 文本样式合成](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2925-L3000)，未复制上游源码。

`editSlides({ action: "masterParagraphStyle", kind, level, format }, masterPart?)` 编辑相同类别及级别的默认段落。`PptxMasterParagraphFormat` 复用段落的缩进、行段距、方向、普通项目符号/编号、标记字体/大小/颜色及制表位，并增加 `alignment: "left" | "center" | "right" | "justify"`。内层 `format.level` 拒绝，级别由外层选择。`format: null` 清除本级已支持的段落直接设置，保留字符定义、级别及其他源片段。标记属性传空值使用正文样式；制表位沿现有继承合并，移除本级定义后恢复上级。

默认面板复用普通段落、列表及制表位控件，修改和清除共用母版事务及精确历史。未知间距、标记、制表位及扩展源保护修改；字符定义中的未知属性在段落修改和清除时保留。新标记字体同样在提交前预检。编号标记继承正文粗斜体，普通项目符号使用常规字形，依据 [ONLYOFFICE MergeTextPr](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/PresentationNumbering.js#L389-L456)。实现归 [`master-paragraph-style.mbt`](../../modules/formats/src/pptx/master-paragraph-style.mbt)，段落解析与写入复用 [`paragraph-read.mbt`](../../modules/formats/src/pptx/paragraph-read.mbt)和 [`paragraph-properties.mbt`](../../modules/formats/src/pptx/paragraph-properties.mbt)。未复制上游源码。

`editObjects({ action: "insertPlaceholder", type, x, y, width, height, text })` 在当前母版或版式插入顶层占位文本框。`type` 使用原生 `title/body/ctrTitle/subTitle/dt/ftr/sldNum/hdr/obj/chart/tbl/clipArt/dgm/media/sldImg/pic`；核心按当前源最大索引加一分配 `idx`，从 1 开始，耗尽 uint32 时拒绝。位置、尺寸和提示文字沿用文本框限制。图表、图片、媒体等类型目前定义槽位标记，资源填入仍受各功能支持范围约束。

`editObjects({ action: "replaceImage", object, bytes })` 也可向单选的空 `pic/obj` 占位框填入 PNG/JPEG。默认图片面板显示“填入占位图片”。核心转换为原生 `p:pic`，保留对象身份、名称/链接、占位符定义、样式及版式关系；提示文字留在版式。图片按 96 dpi 换算点值，居中并等比适配；小图片不放大，源像素尺寸至少按 1 mm，缩放结果各轴至少 5 mm，沿 [ONLYOFFICE addImages](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L3803-L3852) 的规则。旋转/翻转保持，必要继承几何写为局部框。填入后继续使用普通图片替换、裁剪和透明度。非空文字、其他占位类型、组成员、锁定或扩展非可视属性、未知外围源继续保护。源图片字节、关系、内容类型和对象转换合为一次精确历史，目标身份变化、输入和预算失败保留文档。实现归 [`placeholder-image.mbt`](../../modules/formats/src/pptx/placeholder-image.mbt)，复用 [`object-image.mbt`](../../modules/formats/src/pptx/object-image.mbt) 的资源事务；未复制上游源码。

`editObjects({ action: "fillTable", rows, columns })` 在普通幻灯片的单选空 `tbl/obj` 占位框中创建原生表格。默认表格面板提供“填入占位表格”，对象查询的 `tableFillReason` 返回保护原因。表格沿现有新建格式，继承槽位的有效位置和宽度，行高由字体及单元格内容撑开；不将槽位高度强制分配到各行。保留 `cNvPr` 身份、名称/链接、`nvPr` 占位定义、对象顺序与选择，版式提示和其他部件保持原字节。填入后继续使用原生格输入、表格结构和格式命令。

行数为 1–1000，列数为 1–63，总格数最多 4096；现有列宽、字体、候选、历史和包预算继续执行。文字非空、非目标槽位、组成员、锁定、旋转/翻转、未知外围或扩展内容继续保护；母版/版式视图保留槽位定义入口。表格转换、网格和必要行高共用一次精确历史，失败保留源、选择及身份分配。表格占位符的版式切换与重置沿[幻灯片版式](#幻灯片版式)处理。实现归 [`placeholder-table.mbt`](../../modules/formats/src/pptx/placeholder-table.mbt)，复用 [`table-create.mbt`](../../modules/formats/src/pptx/table-create.mbt)与 [`table-structure.mbt`](../../modules/formats/src/pptx/table-structure.mbt) 的候选及排版；位置/宽度和替换行为参考 [ONLYOFFICE Add_FlowTable](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L4079-L4120)，未复制上游源码。

`editObjects({ action: "fillChart", kind, title, data })` 在普通幻灯片的单选空 `chart/obj` 槽位中填入原生图表。参数复用[基础图表](#pptx-基础图表)的六种类型、标题及 TSV 数据规则。默认图表面板显示“填充图表占位符”；对象查询的 `chartFillReason` 返回保护原因。核心复用图表 XML、嵌入 XLSX、关系及内容类型事务，保留对象身份、名称、占位定义、顺序和选择，版式提示及其他部件保持。填入后沿普通数据修改、移动缩放、历史、保存重开和 Canvas/PDF 路径。

槽位须为本地顶层、无文字、无旋转/翻转且至少 180×150 pt。未知/扩展内容、锁、错误槽位及母版/版式视图继续保护。核心采用槽位的有效位置及完整宽高，参考 [ONLYOFFICE finalizeAddChart](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L3935-L3982)。图表资源和替换共用一项精确历史，失败保留文稿、选择及身份分配；整对象复制沿既有占位身份保护。实现归 [`placeholder-chart.mbt`](../../modules/formats/src/pptx/placeholder-chart.mbt)及 [`chart-edit.mbt`](../../modules/formats/src/pptx/chart-edit.mbt)，未复制上游源码。

单选本地顶层形状或图片后，`editObjects({ action: "placeholder", value: { type, index } })` 修改定义；`value: null` 移除定义并保留对象、内容与资源。`index` 是 0 至 4294967295 的整数；同源相同类型/索引不得重复，比较时居中标题归为标题。每个查询对象的 `placeholder` 返回 `{ value, reason }`，普通页面可读取定义，修改需进入源视图。已知 `sz/orient/hasCustomPrompt` 保留，未知元数据和形状类型锁保护修改。需要时先固化当前源对象的继承几何；会导致引用页面丢失继承几何的修改仍整项拒绝。源、依赖页、选择与历史沿既有事务提交；默认面板提供插入和定义控件。实现归 [`placeholder-edit.mbt`](../../modules/formats/src/pptx/placeholder-edit.mbt)，索引分配参考 [ONLYOFFICE NewShapeTracks](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/NewShapeTracks.js#L869-L894)。

`editSlides({ action: "addMaster" }, source?)` 在所选母版后新增空白母版、一个空白版式和独立默认主题；选择版式时使用其所属母版的位置。空白内容复用核心新建文稿的构造。`copyMaster` 接受母版源，保留名称、源设置及全部声明版式的顺序，并独立复制主题；零版式的母版也可复制。对象、字段、creationId、母版和版式身份重新分配，所属关系重映射到副本；图片字节和普通链接继续共享。图表等尚未接通复制归属的可变资源、未声明的版式关系和未知身份扩展保护复制。两项操作选择新母版并清空对象选择，保留真实页面；主目录、关系、主题及所有新源合为一次历史。目录、每个新源的对象/字体/图片、累计历史和包预算在提交前检查，失败保留源、选择和身份分配。默认源管理面板提供相同操作。实现归 [`master-create.mbt`](../../modules/formats/src/pptx/master-create.mbt)及 [`master-source.mbt`](../../modules/formats/src/pptx/master-source.mbt)。复制归属与插入位置参考 [ONLYOFFICE MasterSlide.createDuplicate](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/SlideMaster.js#L702-L741)和 [DublicateMaster](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9214-L9253)，未复制上游源码。

`editSlides` 的 `addLayout` 在所选母版下新增空白版式；选择版式时新增到其后。`copyLayout` 在同一母版下复制版式，保留源名称，重映射对象身份并共享图片及链接；图表等尚无复制所有权支持的资源保护复制。`deleteLayout` 仅删除没有页面或其他部件引用的版式，同时移除目录、关系及内容类型，保留共享资源；删除当前版式后选择其母版。`sourceName` 的 `name` 修改母版或版式名称，最多 1024 UTF-16 单元，允许空串，相同名称不产生历史。这些操作复用现有命令、默认源管理面板和部件历史；新增身份在撤销后也不复用，失败保留原状态。实现归 [`source-edit.mbt`](../../modules/formats/src/pptx/source-edit.mbt)、[`layout-create.mbt`](../../modules/formats/src/pptx/layout-create.mbt)及 [`layout-delete.mbt`](../../modules/formats/src/pptx/layout-delete.mbt)。复制与目录操作参考 [ONLYOFFICE Layout.createDuplicate](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Layout.js#L282-L328) 和 [SlideMaster 目录操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/SlideMaster.js#L543-L560)，未复制上游源码。

`editSlides({ action: "deleteMaster" }, masterPart?)` 删除母版及其声明的全部版式，至少保留一个母版。引用页面自动转到声明顺序中的第一个剩余母版，包含隐藏页。版式先匹配显式类型，再按 `matchingName` 或源名称匹配，最后选择首个非标题版式或第一项。需要重绑定而目标母版没有版式时整项拒绝。页面本地对象、文字、身份和直接尺寸保留；失去版式及母版匹配的占位符先写入原有几何，自动框沿新继承重新适配。新字体使用现有 probe/profile 预检。页面关系、必要几何、母版、版式、主目录和内容类型合为一次历史，主题、图片及其他资源保留。当前源属于被删母版时返回原来的真实页面，其他选择保持。默认母版面板提供相同操作和保护原因；没有版式的未使用母版也可删除。未知部件入站关系、页面或主目录中的未知关系引用、对象保护和预算失败原子拒绝。实现归 [`master-delete.mbt`](../../modules/formats/src/pptx/master-delete.mbt)及 [`master-rebind.mbt`](../../modules/formats/src/pptx/master-rebind.mbt)。重绑定、匹配和孤立框依据 [ONLYOFFICE ChangeSlideSlideMaster](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9754-L9765)、[getMatchingLayout](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/SlideMaster.js#L324-L400)及 [checkNoTransformPlaceholder](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L2009-L2040)。未复制上游源码。

源视图沿用背景面板。`editSlides` 的 `background/backgroundImage/backgroundImageFormat/backgroundImageInsets` 同样接受母版或版式部件路径，包含未使用的版式。纯色、线性渐变、PNG/JPEG、裁剪、不透明度、拉伸/平铺和目标内缩复用[既有背景合同](#图片背景)，不新增命令或资源模型。修改只写目标源及必要图片关系/内容类型，重读引用页面；页面和版式的局部覆盖保持。清除版式背景恢复母版，清除母版背景使用白底。格式编辑复用目标源已解析的图片，即使该源不在当前画面中；公开图片读取仍按当前画面及真实页的使用范围保护。背景、资源与选择共同精确撤销，未知源、文稿保护和预算失败原子拒绝。语义依据 [ONLYOFFICE 母版背景事务](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/SlideMaster.js#L530-L534)及[版式背景事务](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Layout.js#L348-L353)，未复制上游源码。

源视图采用 [ONLYOFFICE 的母版模式与依赖对象区分](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L2679-L2703)。实现归 [`page-view.mbt`](../../modules/formats/src/pptx/page-view.mbt)、[`page-read.mbt`](../../modules/formats/src/pptx/page-read.mbt)及 [`page-reflow.mbt`](../../modules/formats/src/pptx/page-reflow.mbt)。

### 幻灯片版式

`PresentationEditor.editSlides({ action: "layout", id }, slide?)` 应用文稿中已有的版式。`id` 是版式部件路径，须来自 `query.slideLayout.choices`；`current` 返回当前页的版式身份，`reason` 返回目录或修改保护原因。每项选择包含 `id/name/master/masterName`，分别表示版式身份/源名称及所属母版身份/源名称。默认面板按名称和母版展示选项。空名称仅在界面使用序号，不改写源。

目录沿 presentation 的母版列表及各母版的版式列表读取，保留声明顺序。最多 256 个母版、256 项版式；目录文字与重复身份合计不超过 1,048,576 UTF-16 单元，源名称最多 1024 单元。未知、重复或归属错误的引用保护目录；其他编辑与原始源继续保留。

核心按占位符类型及数值索引匹配，中心标题与标题共用匹配类别，并沿用单个正文占位符的回退规则。匹配对象保留身份、文字、直接格式、链接和选择，清除受支持的本地几何覆盖，由新版式及母版重新派生位置、尺寸和继承样式。普通本地对象保留原源。新版式缺少的普通标题、正文、内容及副标题占位符生成空的本地文字对象，使用新身份并继承版式；模板提示文字不会写入幻灯片内容。

缺失的 `dt/ftr/hdr/sldNum` 占位符按版式 `hf` 开关插入；缺少版式设置时使用母版设置，两者均无设置时不插入。有效设置中未声明的开关缺省为启用。固定日期和页脚保留已有文字及样式，简单编号域保留源缓存并计算显示值；字段 ID 复用页面复制的分配规则。内容写为本地对象，位置继续继承版式。普通占位符仍清空提示。规则参考 [ONLYOFFICE 占位符复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L776-L800)及[版式/母版页边设置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9158-L9182)，实现归 [`layout-fields.mbt`](../../modules/formats/src/pptx/layout-fields.mbt)。

没有匹配位置或多个对象争用同一位置时，已有用户内容明确报冲突。仅无文字、可见填充/边框、动作或未知元数据的未匹配占位符可以移除；被计时/连接引用的对象继续保护。缺少时间上下文或未支持的日期域、未知字段、包含关系的页边文字、分组或歧义占位符、未知页边开关/变换，以及导致新增显示诊断或无法解析几何的版式仍保护。新增占位符 XML 合计最多 1,048,576 UTF-16 单元，继续受包、字体、输出及历史预算限制。母版/主题继承可随切换更新，版式和母版本身保持原源。

关系目标、占位符与源变化共用一次精确历史；原生文字草稿先独立提交。选择中失去的继承对象或空占位符会清除，保留对象的文字光标继续有效。相同版式切换是空操作；母版/版式对象编辑归[源视图](#母版与版式编辑视图)，母版和版式的新增/复制/删除及源改名归同一合同。字体总数在候选提交前检查，避免提交后才超出查询的 256 键预算。保存重开、页面复制及 Canvas/PDF 沿相同关系与继承路径。实现归 [`slide-layout.mbt`](../../modules/formats/src/pptx/slide-layout.mbt)，匹配和几何重置参考 [ONLYOFFICE getMatchingShape](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L390-L522)及 [changeLayout](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L695-L800)。

`PresentationEditor.editSlides({ action: "resetLayout" }, slide?)` 重新应用目标页的当前版式，默认面板提供重置按钮。它清除占位符受支持的本地 `xfrm`，恢复版式/母版几何，并沿相同规则补齐缺失的空占位符。保留已有匹配对象身份、用户文字、字符/段落/框属性及形状外观；普通对象和版式关系原字节保持。行为沿 [ONLYOFFICE 当前版式重置入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9519-L9553)，文字格式清除仍使用既有字符/段落命令。

重置仅在有覆盖或占位符变化时新增一项历史，重复调用不改源或 revision。原生草稿先独立提交，随后可精确混合撤销/重做和保存重开。移动/尺寸锁、实际旋转变化的 `noRot`、未知变换标记、无法继承几何及资源预算失败均原子拒绝；版式切换使用相同候选保护。

匹配的图表占位符支持版式切换与重置，完整采用目标槽位的位置和宽高。现有图表数据、对象身份、占位定义及资源保持；未知/旋转/翻转或小于 180×150 pt 的目标原子拒绝。重复重置不新增历史。

匹配的表格占位符也支持版式切换与重置。核心使用目标槽位的有效位置和宽度，按整数 EMU 比例调整现有列网格；保留行最小高度，并按新宽度重新排版，必要时增高行及原生表格框。槽位高度不压缩已有内容。表格身份、占位定义、格内文字和直接格式保持，源版式及未修改部件保留原字节；关系、列宽、行高和选择共用一次精确历史。重置恢复位置及列宽，重复重置不新增历史。

底层 `Session::edit_slides` 在表格重排时需要已有字体 `probe/profile`；Wasm、Worker 和默认面板沿现有命令传递。目标缺少匹配槽位、含旋转/翻转或未知几何，原表格锁定，列宽无法容纳边距，字体缺失，目标母版引入不支持的表格格式，或预算失败时整项拒绝。已有表格即使文字为空，也不作为可丢弃的空提示框删除。实现归 [`layout-table.mbt`](../../modules/formats/src/pptx/layout-table.mbt)，列宽及行高复用 [`table-transform.mbt`](../../modules/formats/src/pptx/table-transform.mbt)和 [`table-layout.mbt`](../../modules/formats/src/pptx/table-layout.mbt)。框重置与按宽度重排参考 [ONLYOFFICE changeLayout](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L728-L753)及 [GraphicFrame 表格重排](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicFrame.js#L413-L477)，未复制上游源码。

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
| `copyPptx` / `pastePptxFragment` | 读取文字及原生富文本快照，或以字体 profile 粘贴快照；范围归[文字富文本片段](#pptx-文字富文本片段) |
| `pastePptxObjects` / `objectFragmentImagesPptx` | 以字体 profile 粘贴独立对象快照，或只读校验并提取待解码图片；范围归[对象剪贴板](#pptx-对象剪贴板) |
| `beginPptx` / `finishPptx` / `cancelPptx` | 开始、提交、取消 `text` 或 `transform` 候选；匹配 revision 与 candidateId |
| `transformPptx` / `dragPptx` | 绝对位置/尺寸，或基于手势开始几何的 point 增量与核心手柄编号 |
| `undoPptx` / `redoPptx` / `savePptx` | 原子历史及绑定 revision 的源保存 |
| `layoutPptx` / `hitPptx` / `selectionPptx` | 当前页绘制、最上层命中、对象轮廓/手柄及文字光标/选区；几何绑定 layoutId |
| `imageKeysPptx` / `imageBytesPptx` / `imagePptx` | 准备当前页或导出范围的资源键、读压缩源、接入经过宿主校验的 RGBA |
| `mediaBytesPptx` | 读取当前文稿已声明且受支持的内嵌音视频原字节；外部媒体拒绝 |
| `exportPptxPdf` | 绑定 revision、字体 profile、当前页/整稿、隐藏页选择与输出预算的静态 PDF |

`PptxSelection` 包含 `slide`、有序且唯一的 `objects: string[]`、活动 `object`、`mode`、`anchor` 和 `focus`。空集合要求活动身份为空；非空集合要求活动身份属于集合。集合最多 256 个当前页对象，身份长度最多 1024。文字模式要求唯一对象及有效字素边界。`selectPptx` 必须提供全部字段，失败保留原选择；选择不新增历史。宿主 `selectObjects(objects, active?)` 默认激活最后一项；`select(object, mode?, anchor?, focus?, extend?)` 默认替换选择，`extend=true` 在对象模式中切换成员。

默认 UI 支持 Shift 点击画布/列表切换成员、点击已选成员保留集合以及 Ctrl/Cmd+A 全选。进入文字模式收敛到活动对象。`selectionPptx` 返回成员 `outlines` 和包围盒 `outline`；本地可变换成员使用四角手柄。多选 `dragPptx` 的移动及角点独立宽高缩放沿用开始几何；`transformPptx` 对多选接收整组世界坐标包围盒，宽高倍率分别计算。成员中心按世界轴缩放，旋转和翻转保持；角度规范到 0–360° 后，45–135° 及 225–315° 区间（含起点、不含终点）交换本地宽高倍率，其余角度直接使用两轴倍率。斜角成员采用这一预设规则，不生成剪切变换；结果包围盒由成员几何重新求出。零宽度或零高度的共线集合保留零跨度，不能请求扩展该方向。拖动越过相反角时按各成员的最小尺寸钳制，每个成员继续受原尺寸/位置限制。任一成员受保护时整组拒绝。属性面板使用同一变换路径；候选完成后仅一项历史，取消保持源和选择。 缩放尺寸与中心参考 [ONLYOFFICE ShapeForResizeInGroup](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L2392-L2430)，角度区间参考 [checkNormalRotate](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L185-L188)；未复制上游执行代码。

`PptxSlideEdit` 从 `wasm/pptx` 和 `web/pptx` 导出。`{ action: "move", index }` 将目标页移到从 0 开始的索引，索引包括隐藏页；`{ action: "hidden", hidden }` 修改隐藏状态。编辑宿主为 `PresentationEditor.editSlides(change, slide?)`，省略身份时作用于队列执行时的活动页。重排保持页路径、源页 ID、对象身份、关系及活动选择，仅改 `sldIdLst` 顺序；隐藏只改 slide 的 `show`。自定义放映和页间链接仍按原关系指向同一页面。相同位置/状态不新增历史，错误不提交。

`{ action: "add" }` 在目标页后插入空白本地内容，沿用该页的版式、母版和主题，继承版式/母版中的装饰与背景。新页可继续创建及编辑对象；不复制原页对象、备注、动画或版式占位符。核心分配新页 ID、路径和关系，切到新页并清空对象选择。会话内撤销后再新增不复用该页身份。新 slide 及其版式关系、内容类型和页引用合为一项有界历史，与后续对象/文字、重排和隐藏共同精确撤销/重做。最多 256 页，预算或保护失败不留下新部件。默认 UI 提供新增空白页入口。

`{ action: "copy" }` 在目标页后复制，激活副本并清空对象选择。保留隐藏状态、内容、几何、格式及版式继承，分配新页/对象身份，重映射对象连接与计时目标。自身页链接指向副本，其他页链接及自定义放映保持原目标。图片、版式、母版和主题复用原部件，外部超链接保留地址且不下载。普通备注和传统批注另建部件及关系；备注回链指向副本，批注保留作者和内容，分配新 idx 并更新作者 lastIdx。复制部件、作者索引和页引用进入同一有界历史，支持后续编辑、删除、保存重开和精确撤销/重做。重新复制不复用已撤销的页/对象身份。

复制为已知 PowerPoint 2010 creationId 扩展及 DrawingML 字段生成新身份，保留字段类型和源缓存文字；保护其他未知 XML 身份扩展及 noCopy 锁。已知 p14:media 扩展及内嵌音视频关系复用原媒体和封面。未知关系、图表/嵌入数据、VML 和线程批注需要对应所有权支持后开放。支持页关系为 slideLayout/image/hyperlink/slide/notesSlide/comments/audio/video，以及 Microsoft media；备注关系为 notesMaster/image/hyperlink/slide；传统批注仅允许超链接。外部关系仅允许 hyperlink。标准计时 XML 保留并重映射对象目标；动画编辑与执行范围归[对象动画](#对象动画)。复制继续受 256 页、对象/文字、输入输出和历史预算约束，失败不修改已提交内容。

`{ action: "delete" }` 删除指定页，至少保留一页。删除活动页时选择原位置的下一页，末页则选前页，并清空对象选择；删除非活动页保留当前选择。同步移除 presentation 页引用、自定义放映中的对应条目，以及其他 XML 中指向该页的已知 DrawingML 点击/悬停链接及关系，保留链接所在对象与文字。空的自定义放映保留身份。仅删除该 slide、其关系和独占的备注/传统批注 XML 及关系，移除对应内容类型；版式、母版、主题、图片、作者与未知资源保留，不扫描清理整个包。共享备注/批注、未知或隐式引用、超出历史/输出预算时原子拒绝。删除部件快照计入有界历史，可与新增、对象及页序编辑精确混合撤销/重做，损坏历史拒绝回放且不改变当前文稿。默认 UI 提供删除页，并禁用最后一页的删除。选择规则参考 [ONLYOFFICE 删除页](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L9458-L9485)。

`PptxQuery.sections` 返回 `{ items: PptxSection[], reason }`。每章包含稳定 GUID `id`、`name` 和按页序排列的稳定部件路径 `slides`；类型从 Wasm/Web PPTX 模块导出。核心读取标准 PowerPoint 2010 `p14:sectionLst`，源成员引用 presentation 的数值 `p:sldId`，不使用页索引或关系 ID。存储参考 [ONLYOFFICE SectionList/Section](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Presentation/PresentationChildElements.cpp#L289-L339)。

`PresentationEditor.editSlides` 同步支持 `{ action: "sectionAdd", name }`、`{ action: "sectionRename", id, name }`、`{ action: "sectionRemove", id }`、`{ action: "sectionRemoveAll" }`、`{ action: "sectionMove", id, index }` 和 `{ action: "sectionDelete", id }`。新增在目标页前切分所属章；首次从中间分章时为前页创建 Default Section。移除保留页面，归入前章，首章则归入后章；移除最后一章只清理章节元数据。移动按从零开始的章节索引重排该章及其全部页面，保留活动页/对象身份。新增和复制页继承源章；删除移除成员，跨章移动按落点归属。空章保留，未分章前缀允许存在。每章成员必须连续、有序且互不重复，最后一个非空章覆盖到末页。

最多 256 章，名称最多 255 UTF-16 单元；创建/改名要求非空有效 XML 文字。章节与关联页序合为一项有界历史，可与页操作和原生输入混合精确撤销。重名允许，身份按 GUID 区分。相同名称/位置不新增历史。未知章节属性/子项、非连续/重复/悬空引用和修改保护明确拒绝，不删掉未知源来开放编辑。非目标部件、已有章节外标签及页引用周围源内容保留；未知无关扩展可随章节改名保留，但仍保护页序修改。保存重开及 PDF 使用提交后的页序。默认面板提供新增、选择、改名、保留页面移除、一次移除所有章节、前后移动及删除章节和页面。

默认页列表按 `query.sections` 的稳定身份分组，保留未分章的前缀、全稿页码、空章和隐藏页标记。章节标题显示名称与页数，按钮用 `aria-expanded` 和 `aria-controls` 关联成员页；Enter/Space 切换，另有全部折叠/展开。折叠隐藏该章的页按钮，当前画布及核心选择不变；活动页所在的折叠章由标题标识，外部页导航会自动展开目标章。改名和整章重排保持折叠状态；已移除的章清理状态，新章初始展开。更换/重开文档时初始全部展开。无可用章节时继续显示平面页列表。折叠是默认 UI 的会话视图状态，不写入 PPTX、不增加文档历史，不改变保存/PDF 页序和页数。参考 [GenOffice 章节视图状态](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/renderer/App.tsx#L2247-L2259)，实现归 [`pptx-slides.tsx`](../../packages/ui/src/pptx-slides.tsx)。

`sectionRemoveAll` 一次移除全部章节，保留全部页、页序、对象、选择及其他部件。章节元数据以一项有界历史移除，可精确撤销/重做和保存重开；没有章节时不修改 revision 或历史。UI 无章节时禁用入口。损坏或未知章节继续保护；其他扩展、外层属性、注释和处理指令保留，只在外层扩展列表没有其他内容时一并移除该空容器。操作目标参考 [GenOffice removeAllSections](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/renderer/slide-actions.ts#L182-L189)，沿用已有标准 p14 写回和核心事务。

`sectionDelete` 同时删除该章及全部成员页，至少保留一页；空章只移除章节元数据。剩余页面、章节和对象保留稳定身份。活动页被删时选择其后首个存活页，无后页则选择末个存活页，并清空对象选择；活动页未删除则保留原选择。页引用、自定义放映、已知页链接、独占备注/传统批注与相关类型声明复用页面删除规则，全部变化进入同一项有界历史。未知入站引用、共享备注/批注、保护或整项累计预算失败不提交任何删除。原生草稿先独立提交，随后整章删除独立撤销。UI 禁用删除覆盖全稿的章节。页面集合与独占资源的精确快照直接扩展既有核心历史，撤销/重做及保存重开不依赖逐页宿主命令。操作目标参考 [GenOffice 整章删除](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/main/slides-main.ts#L4266-L4288)，资源和页选择沿用前述 ONLYOFFICE 页删除规则。

`PptxQuery.slideOrderReason/slideVisibilityReason` 返回各自保护原因。修改保护阻止两者；损坏或未支持的章节、未知 presentation/页列表扩展、presProps 中的位置型 `sldRg` 放映范围和未知 presentation properties 扩展阻止新增、删除与重排。空参考线列表及已知图片编辑数据、默认 DPI、图表引用跟踪设置扩展原样保留；非空参考线列表继续保护。默认 UI 使用这些原因，提供新增、删除、页前移/后移和隐藏/显示，页列表保留隐藏页入口。历史按稳定部件路径恢复，混合对象编辑与页序变化不会改错页面。

隐藏页仍可在编辑器中查看和编辑，允许全部页隐藏。全稿静态 PDF 默认跳过隐藏页，显式 `hidden: true` 包含它们；仅导出当前页时可以输出当前隐藏页。没有待输出页时返回 `unsupported-pdf`，不返回空 PDF。保存重开按新页序打开首张页面，保留隐藏状态。更广复制资源仍归 [P12](../p12-pptx-core.md)。

`PptxObjectEdit` 从 `wasm/pptx` 和 `web/pptx` 导出。`PresentationEditor.editObjects(change)` 使用同一队列与命令。插入参数为 `{ action: "insert", kind: "text" | "rect" | "roundRect" | "ellipse" | "triangle" | "rtTriangle" | "diamond" | "parallelogram" | "trapezoid" | "pentagon" | "hexagon" | "octagon" | "plus" | "star5" | "line" | "leftArrow" | "rightArrow" | "upArrow" | "downArrow" | "leftRightArrow" | "upDownArrow" | "quadArrow", x, y, width, height, text }`；坐标和尺寸为 point，绝对值不超过 14400。非线对象宽高至少 0.1；线可有一个零尺寸轴，总尺寸至少 0.1。文本框透明无描边，矩形、圆角矩形、椭圆和箭头白底黑色 1 pt 线，直线黑色 1 pt；文字为 Arial 18 pt 黑色，支持 `\n` 与 `U+2028`，线不接收文字。核心校验文字、字体和固定框容量，失败保留文档和历史。

图片插入为 `{ action: "insertImage", bytes: Uint8Array, x, y, width, height }`，沿相同 `editObjects` 入口。坐标为 point，绝对值不超过 14400，宽高至少 0.1。接收本地 PNG/JPEG 原字节，单图最多 4 MiB，尺寸每轴不超过 4096，像素总数不超过 4194304，文稿最多 256 个不同图片资源；最终包与单项 4 MiB 历史预算仍可拒绝操作。核心检查文件头、声明尺寸和几何；浏览器客户端提交前验证实际解码与声明尺寸一致，坏图保留当前源和历史。同步 Wasm 入口不承担宿主解码，导入图片仍沿原有解码合同。核心分配对象与资源身份，事务新增图片、内部关系和内容类型；撤销移除本次新资源，重做恢复原字节及 ZIP 顺序。对象/页复制共用图片，删除对象/页保留资源，不清理整个包。默认 UI 选择图片文件，并采用插入面板中的 X/Y/宽高。创建矩形图片并 stretch 到给定几何的规则参考 [ONLYOFFICE fillImage](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L114-L142)。高级图片效果继续归 [P12](../p12-pptx-core.md)及后续兼容扩展。

图片替换为 `{ action: "replaceImage", object, bytes: Uint8Array }`，使用相同图片预算和浏览器解码检查。替换已有图片时要求对象模式中唯一的本地图片（含组成员），保持对象身份、选择、几何、旋转/翻转、裁剪及其他源属性；为它新建图片和关系，不覆盖共享资源或改变其他副本。空 `pic/obj` 槽位也可通过同一命令填入图片，尺寸适配归[占位框填图](#母版与版式编辑视图)。`object` 必须与提交时唯一选中的对象身份一致；文件读取期间改变选择会拒绝替换，防止改错目标。相同原字节不新增历史。已有图片的几何保留参考 [ONLYOFFICE replacePictureData 的 stretch 路径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L839-L869)，当前接口保留原裁剪，不提供 fit/fill/original 模式。

独立图片使用 `editObjects({ action: "imageMode", mode: "stretch" | "tile" })` 切换模式。`picture.mode` 返回当前有效模式，`modeReason` 返回编辑保护原因；默认图片面板提供选择和应用。命令作用于唯一选中的本地图片（含组成员），只改 `blipFill` 的模式节点，保持身份、外框、旋转/翻转、裁剪、不透明度、图片字节及关系。同值不增加历史。未显式声明模式的已知源按拉伸读取，首次切换插入标准平铺。导入支持已有缩放、偏移、对齐与交替翻转，范围与[形状平铺](#形状图片填充)相同。平铺使用整张源图并保留裁剪；切回拉伸时重新应用裁剪，并在提交前验证展开尺寸。

图片在拉伸和平铺时均按已支持的预设图片框裁剪，矩形沿原矩形路径，椭圆等复用已有形状轮廓；变换后的框和图片使用同一矩阵。绘制入口参考 [ONLYOFFICE CImageShape.draw](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Image.js#L592-L659)，平铺语义复用其 ShapeDrawer。背景、形状填充和独立图片共用每页 65536 个重复单元；尺寸和变换候选沿同一数量检查。未知模式/填充标记、外链、固定页面方向及未知效果继续保护；目标内缩归[图片目标内缩](#图片目标内缩)；未知几何不放开。失败保留源、资源、选择和历史。保存重开、复制、替换、裁剪、不透明度及 Canvas/PDF 沿原路径。实现归 [`picture-mode.mbt`](../../modules/formats/src/pptx/picture-mode.mbt)及[共享平铺](../../modules/formats/src/pptx/shape-tile.mbt)。

四边裁剪为 `{ action: "imageCrop", left, top, right, bottom }`，每边为源图的移除比例，范围 0 至 0.99999。核心按 OOXML 的 1/100000 网格舍入，左右及上下之和必须小于 1，派生绘图坐标继续受预算约束；不改对象外框。四个零恢复整图并移除裁剪覆盖，同值不新增历史。`PptxObject.picture` 返回四边有效比例和 `replaceReason/cropReason`，另返回 `mode` 与 `modeReason`。裁剪锁、继承图片、非唯一选择、未知裁剪标记及预算失败保留源；默认 UI 提供替换文件、四边百分比和重置。替换、裁剪和后续对象编辑沿同一历史精确恢复，保存重开与 Canvas/PDF 共用已有源矩形显示路径。

图片不透明度为 `{ action: "imageOpacity", opacity }`，要求对象模式中唯一的本地图片（含组成员）。`opacity` 为 0 至 1，0 完全透明，1 完全不透明；核心按 1/100000 网格写入 `a:alphaModFix amt`，调回 1 时移除覆盖，同值不新增历史。`picture.opacity/opacityReason` 返回当前值及修改保护原因。支持单个常量 alpha 效果，其他效果继续诊断；带未知保留标记的透明度节点保护修改。倍乘关系参考 [ONLYOFFICE CBlipFill 常量 alpha](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L3818-L3840)。操作保持身份、几何、裁剪、图片原字节及共享副本，能与替换/复制混合精确撤销和保存重开。默认 UI 显示不透明度百分比。

定位后的图片图元携带不透明度，DOCX 行内图片显式使用 1。Canvas 沿公共 `DrawStyle.fillAlpha` 执行，图片结束后恢复默认样式；PDF 在单张图片的作用域应用 ExtGState `ca`，与原像素的软蒙版相乘，不把共享原图改成带透明度的新像素。两个输出共用核心值和相同源像素，完全透明的对象仍保留选择及资源。

删除参数为 `{ action: "delete" }`，复制为 `{ action: "duplicate", dx, dy }`。两者要求对象模式；空选区不修改文档。删除作用于整个集合，先校验全部成员，再提交一项历史；任一保护失败不删除其他成员。复制作用于整个集合，包括受支持的嵌套组；副本按原源顺序放到所属父容器的最上层。保留非变换源内容、页面几何、命名空间与图片/超链接关系，为副本及其全部成员分配会话内尚未使用的新 `cNvPr.id`，域身份同样更新。副本内部对象引用重映射；引用集合外对象而需联动的结构明确拒绝。副本选择保留原选择顺序及对应活动对象。一次复制合为一项历史，任一成员、字体、几何或预算失败不创建副本、不消耗身份。原对象的页面姿态、非变换内容、其他部件及资源保持；组内原生坐标可随边界重算归一化。一次复制的 XML 片段及继承命名空间合计最多 2 Mi UTF-16 单元，在拼接前检查；最终包和历史继续受原有预算约束。删除清空选择；撤销/重做精确恢复源 XML 与选择。`PptxObject.deleteReason/duplicateReason` 返回操作保护原因，空串表示可用。继承/跨父组选择/未知对象继续保护；复制占位符及未知扩展、删除锁定或带连接/计时引用的对象仍拒绝，含未支持所属关系的页面也保护删除。资源和关系不做清理。默认 UI 提供插入面板、复制/删除按钮；对象输入支持 Delete/Backspace 与 Ctrl/Cmd+D，默认复制偏移各 18 pt。

### PPTX 对象剪贴板

对象模式的 `copyPptx` 返回 `{ text, fragment, reason }`。本地顶层形状、PNG/JPEG 图片、普通表格、普通图表及完整组合可生成独立原生快照。复制保留源位置、层次、几何、旋转/翻转、图片裁剪、填充、描边、文字及点击外链/导航动作；主题字体、颜色和线性渐变写为明确源外观。继承占位符沿用既有复制保护；未选对象和其他源资源不进入快照。源文稿修改或关闭后仍可重复粘贴。

整表快照保留网格宽度、行高、合并归属、格内文字/段落、边距、锚定、底色和边框。源表样式的区域、字体和颜色冻结后随片段转移，目标分配独立样式身份；同名源样式不覆盖目标，未选样式不进入快照。直接边框与区域边框分别保存，保留原生共享边的优先级。样式目录不存在时原子创建中性默认目录，已有无样式表格不被附加新外观。一批多个表样式、图片和链接沿同一资源历史提交；重复粘贴保持独立，保存重开后仍可输入及修改表结构。源格式解析参考 [ONLYOFFICE 表格源格式复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicFrame.js#L1040-L1095)，实现归 [`object-clipboard-table.mbt`](../../modules/formats/src/pptx/object-clipboard-table.mbt)及[既有表样式资源事务](../../modules/formats/src/pptx/table-style-resource.mbt)；未复制上游执行代码。

普通图表快照保留当前支持类型的标题、标签、系列数值/空值、图例、圆环孔径和原生外观。复制先核对图表缓存与嵌入数据，片段只携带所用数据；粘贴时创建独立图表、关系及一个仅含普通值的 XLSX。文字标签保留前导零和字面等号，不转为公式；源工作簿的其他工作表和未选对象不进入快照。嵌入数据固定读取首个数据表，不受保存时的活动表影响。源数据不一致、公式、附加图表资源和未知外观继续保护。重复粘贴后可分别通过原图表数据面板修改，源修改/关闭不改变已有快照。实现归 [`object-clipboard-chart.mbt`](../../modules/formats/src/pptx/object-clipboard-chart.mbt)、[严格原生缓存读取](../../modules/formats/src/internal/chart/read.mbt)及 [XLSX 数据写入](../../modules/formats/src/xlsx/chart-data.mbt)；源格式复制参考 [ONLYOFFICE 图表源格式复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L8855-L8870)，未复制上游执行代码。

`pastePptxObjects` 接受 `revision`、`fragment` 和字体 `profile`，向当前可写页插入快照并返回 `PptxQuery`。每次粘贴分配新对象身份和独立资源，重映射组内引用及目标关系。源位置保留，对象放到当前页顶层。对象、图片、图表及嵌入数据、关系、内容类型和选择合为一项精确历史。缺字体、损坏资源、引用不完整、冲突继承制表位、活动候选或预算失败均不提交。Web 宿主先通过 `objectFragmentImagesPptx` 只读提取图片，再用浏览器解码；坏图片在修改文稿前拒绝。

默认 Copy/Cut 写入 `text/plain` 和 Chromium 自定义类型 `web application/x-open-document-pptx-objects`。默认源格式粘贴、`PresentationEditor.pasteClipboard()` 和对象输入的 Ctrl/Meta+V 走同一路径；剪切在系统写入成功并复核会话、revision 和选择后删除源。对象快照最多含 256 个顶层对象和 256 项资源，原生 XML 及每项图表 XML 最多 1 Mi UTF-16，完整 JSON 最多 4 Mi UTF-16。图片压缩字节合计最多 2 MiB，图片编码、表样式、图表 XML 和链接的资源值合计最多 2796204 UTF-16，输入及目标页解码图片各最多 16 MiB；表格、图表数据、样式目录、包和历史继续受既有预算约束。

组内局部选择、跨格富文本片段、媒体、字段/公式、具体幻灯片目标、悬停链接及未知对象源继续保护；带注释/处理指令的待重写表属性、样式和图表同样保护。对象复制失败不丢弃对象后降为纯文本。实现归 [`object-clipboard.mbt`](../../modules/formats/src/pptx/object-clipboard.mbt)、[`object-clipboard-style.mbt`](../../modules/formats/src/pptx/object-clipboard-style.mbt)、[`object-clipboard-read.mbt`](../../modules/formats/src/pptx/object-clipboard-read.mbt)和 [`object-clipboard-paste.mbt`](../../modules/formats/src/pptx/object-clipboard-paste.mbt)。复用既有原生对象复制、源格式解析、图片资源及多部件历史。

### PPTX 文字富文本片段

`copyPptx` 返回 `{ text, fragment, reason }`。普通形状或一个表格主格的文字范围可生成独立原生片段，保留混合字体、字号、字符间距、粗斜体、颜色、下划线、删除线、高亮和上下标，以及段落对齐、方向、缩进、行段距、列表级别/起点/标记样式和制表位。核心把继承的字体和主题色写为明确字体名与 RGB。源文稿后续编辑、关闭或主题变化不改变快照。范围按 UTF-16 字素边界处理，保留软换行及空段落。

文字点击外链和导航动作也随片段转移，保留 HTTP/HTTPS/mailto 地址、提示、目标窗口和已知点击标记。目标文稿创建或复用自己的关系，不沿用源关系 ID；一批多个地址与重复粘贴保留独立目标，同地址可以共用关系，修改一个副本时不改变其他副本。链接和文字合为一项精确源/资源历史，缺字体、无效地址或预算失败均不留下关系。复制、粘贴及排版不请求外链。原格式保存和 PDF 链接复用既有合同。实现归 [`text-clipboard-links.mbt`](../../modules/formats/src/pptx/text-clipboard-links.mbt)，链接值和提示随原生段落复制参考 [ONLYOFFICE ParaHyperlink.Copy](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Hyperlink.js#L80-L88)。

`pastePptxFragment` 接受 `revision`、`fragment` 和字体 `profile`，在当前文字选区内提交一次历史，返回 `PptxQuery`。目标限于一个形状或一个主格；跨格富文本粘贴仍受保护。范围外 run 保留原生源，保留前缀或尾部的边界段落沿用目标段落属性，完整替换的段落采用源属性。目标继承制表位若会额外混入来源段落，核心原子拒绝。缺字体、损坏 XML、关系/未知节点、无效范围、旧 revision、活动候选或预算失败不改变源、选择和历史。

默认 Copy/Cut 同时写 `text/plain` 和 Chromium 自定义类型 `web application/x-open-document-pptx-text`。`PresentationEditor.pasteClipboard()`、文字输入的 Ctrl/Meta+V 和默认“按源格式粘贴”读取原生片段；外部普通文字沿既有范围输入。异步读写后核对会话、revision 和选择。剪切仅在系统写入成功后删除源。显式 `paste(text)` 和原生纯文本粘贴事件继续接受普通文字。

片段最多 1 Mi UTF-16、256 段及 256 个不同链接目标；链接地址和单项元数据各不超过 2048 UTF-16。粘贴后的整个对象文字最多 32767 UTF-16。跨格复制保留既有 TSV；字段、公式、具体幻灯片目标、悬停链接、文字透明度和不支持的文字源返回 `fragment: null` 及原因，保留普通文字复制。具体幻灯片链接须先具备目标页转移，避免误指向另一文稿的同名路径。跨格富文本和更广文字格式继续实施。实现归 [`text-clipboard.mbt`](../../modules/formats/src/pptx/text-clipboard.mbt)、[`text-fragment-paste.mbt`](../../modules/formats/src/pptx/text-fragment-paste.mbt)及 [`clipboard-input.ts`](../../packages/web/src/clipboard-input.ts)。解析后冻结源字体/主题色参考 [ONLYOFFICE 源格式捕获](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L7837-L7846)；未复制上游执行代码。

### 更改形状类型

`editObjects({ action: "shapeType", preset })` 修改对象模式中所选本地闭合形状的原生 `prstGeom`，支持单选、多选及同组成员。目标采用已有插入目录的闭合预设，排除 `text` 和 `line`；两者分别是插入文本框的命令名称和开放路径。文本框的矩形源也可改为闭合形状，保留既有非可视属性。`PptxObject.shapeTypeReason` 返回修改保护原因。默认面板复用“对象类型”选择器，并提供“更改所选形状”按钮；Wasm/Web 的 `pptxInsertKinds` 共用同一目录。

修改保留对象身份、源变换、文字/格式、填充/描边、资源与关系。改变类型时移除旧调节值，采用目标预设默认值；选择当前类型不新增历史，也不重置已有调节值。缺少本地几何时按 XML 顺序添加覆盖。新文字内框沿既有布局与自动适配，在同一事务提交尺寸或缩小值。旋转/翻转、组边界、字体、包和历史预算继续适用；任一目标失败整体回滚。未知几何、保留标记、锁定及继承对象继续保护，组内未知几何同样保护。

已有连接引用随受支持闭合预设之间的类型修改重映射到最近的有效连接点，保留目标身份，并沿既有矩阵和连接线归一化更新源端点。目标预设尚无连接点支持时原子拒绝，保留原连接。连接点范围归[连接线](#连接线)。Canvas、PNG、PDF 和命中复用当前几何路径。类型修改、周边原生文字输入、无操作、精确混合历史及保存重开已检查。实现归 [`shape-type.mbt`](../../modules/formats/src/pptx/shape-type.mbt)及[既有连接线事务](../../modules/formats/src/pptx/connector-edit.mbt)，几何替换和重新适配参考 [ONLYOFFICE changePresetGeom](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L6380-L6405)，未复制上游执行代码。

圆角矩形使用 `roundRect`，实心箭头使用四个单向、左右/上下双向及四向的标准 DrawingML 预设；新对象使用默认调节点。读取圆角 `adj`、单向/双向箭头 `adj1/adj2` 的 `val` 数值公式，按预设上下限和实际宽高计算路径、文字矩形及命中；未知调节点或公式保留源并诊断。文字矩形先于 bodyPr 内边距，新增/复制时继续检查实际容量。Canvas 与 PDF 使用同一路径，旋转和局部翻转使用同一矩阵。

三角形 `triangle`、直角三角形 `rtTriangle`、菱形 `diamond`、平行四边形 `parallelogram` 和梯形 `trapezoid` 已接通导入、插入、文字编辑、轮廓命中及 Canvas/PDF。路径和文字矩形依据 [ONLYOFFICE CreateGeometry](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8500-L8550)，实现归 [`polygon-shapes.mbt`](../../modules/formats/src/pptx/polygon-shapes.mbt)。三角形的 `adj` 是顶点横向比例，默认 0.5，范围 0–1；平行四边形及梯形的 `adj` 是斜边偏移占短边的倍数，默认 0.25，上限分别为宽/短边及宽/(2×短边)。导入数值按几何上限夹取；编辑值越界则拒绝。直角三角形和菱形没有调节项。文字矩形先计算，再加框内边距。数值修改、恢复预设、多选保护、保存和精确历史复用既有命令；单一 `adj` 的面板批量修改要求相同预设。复杂自定义几何和指针调节手柄继续实施。

五边形 `pentagon`、六边形 `hexagon`、八边形 `octagon`、十字 `plus` 和五角星 `star5` 已接通同一导入、插入、文字区域、命中、外观、变换、复制、历史和 Canvas/PDF。六边形的 `adj` 是短边偏移，默认 0.25，上限宽/(2×短边)；八边形切角默认 0.29289，十字内缩默认 0.25，五角星内半径默认 0.19098，三者上限均为 0.5。五边形没有可编辑调节项。默认面板提供类型及对应调节值、恢复预设。读取并保留默认 hf/vf 归一化参数，自定义比例及未知公式保持保护；零宽导入框不产生非有限坐标。依据 [ONLYOFFICE 六边形](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L4635-L4674)、[八边形与五边形](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L6348-L6451)、[十字](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L6570-L6607)及[五角星](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8052-L8111)，实现复用上述多边形模块。

左右双向箭头使用 `leftRightArrow`，上下双向箭头使用 `upDownArrow`。两者沿原插入、查询、复制、变换与原生文字编辑命令使用，默认面板提供对应类型。核心生成十顶点的闭合轮廓，两端箭头及中间箭身共用命中、文字内框和 Canvas/PDF。`adj1` 控制箭身比例，`adj2` 控制每端箭头长度，默认均为 0.5；每端最多占方向长度的一半。文字内框在两端同时内缩，先于原有四边文字边距；细箭身仍检查固定框容量，可使用既有缩小或自动尺寸设置。两个 XY 手柄分别调整箭身及箭头，箭身手柄随当前箭头长度移动。预览不改源，取消保持原包，提交与文字适配合为一项精确历史；副本的调节值独立保存。导入超范围常量按预设钳制显示并保留源，未知公式继续保护。实现归 [`preset-shapes.mbt`](../../modules/formats/src/pptx/preset-shapes.mbt)、[`shape-adjustment.mbt`](../../modules/formats/src/pptx/shape-adjustment.mbt)和 [`adjustment-gesture.mbt`](../../modules/formats/src/pptx/adjustment-gesture.mbt)，依据 [ONLYOFFICE 左右双向箭头](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L5280-L5317)和[上下双向箭头](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8594-L8634)，未复制上游执行代码。

四向箭头使用 `quadArrow`，默认 `adj1/adj2/adj3` 均为 0.225。核心按原生 24 顶点闭合轮廓绘制和命中，文字矩形先于四边文字边距。三个调节值均以短边为基准：`adj2` 是箭头半宽，范围 0–0.5；`adj1` 是箭身宽度，范围 0–2×有效 `adj2`；`adj3` 是箭头长度，范围 0–(0.5−有效 `adj2`)。默认控件和三个 XY 手柄使用同一联动上限，箭身手柄随有效箭头长度移动。范围以原生十万分之一表示，精确边界可写回。修改一个值可改变其他值的有效显示，源常量仍保留；指针提交只写实际改变的原生调节值，随后恢复上限仍可读取原值。预览取消、文字适配、旋转/翻转、复制、精确历史及重开沿现有事务。小固定框继续检查文字容量，可显式选择已有缩小或自动尺寸设置。未知公式保持源保护。依据 [ONLYOFFICE 四向箭头](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L6603-L6664)，实现归上述预设及调节模块，未复制上游执行代码。

`editObjects({ action: "shapeAdjustment", name, value })` 修改所选本地预设形状的一个调节值，包含组成员。圆角 `adj` 为短边的 0–0.5 倍；单向/双向实心箭头的 `adj1` 为箭身占横向宽度的 0–1 倍，`adj2` 为箭头长度占短边的倍数，单向箭头的上限是方向边长除以短边，双向箭头再除以 2。数值按十万分之一保存，沿现有公式整数范围限制在 0–21474.83647。null 只移除该调节值，恢复预设默认值；其他调节值和源内容保留。规则依据 [ONLYOFFICE 预设几何](https://github.com/ONLYOFFICE/sdkjs/blob/b2f0aa1d5ca8c82e827ff3af6577d8edf913a2e7/common/Drawings/Format/CreateGeometry.js#L6947-L6981)，实现归 [`shape-adjustment.mbt`](../../modules/formats/src/pptx/shape-adjustment.mbt)。

对象查询的 `shapeAdjustments` 返回 `preset`、`reason` 和 `values`；各值包含 `name/value/maximum`，使用与命令相同的比例。默认面板显示百分比，支持分别应用、恢复预设值及相同调节项的多选混合查询。任一对象锁定 `noAdjustHandles`、未知调节源、所选形状不支持该项或数值越过几何上限时，整项拒绝。无变化不新增历史。修改与派生的字体缩小或形状自动尺寸合为一项历史，保留文字、身份、选择及非目标部件；保存重开后可继续修改。继承对象和任意自定义几何编辑继续实施。

单选可调本地形状时，`selectionPptx` 的 `adjustmentHandles` 返回最多两个 `{ name, x, y }` 页面坐标，顺序与 `shapeAdjustments.values` 一致。圆角矩形、单向/双向实心箭头、三角形、平行四边形、梯形、六边形、八边形、十字和五角星使用标准 XY 调节位置；旋转、翻转及父容器缩放沿对象矩阵。受保护、多选、文字选择及无调节项时返回空数组。既有 `handles` 继续表示尺寸或连接线端点。

默认 Canvas 用黄色菱形绘制调节手柄，命中优先于尺寸手柄；参数面板继续提供键盘入口。`beginPptx` 使用 `kind="adjustment"`，后续 `dragPptx` 的 `handle=1/2` 对应该项顺序，`dx/dy` 是相对手势起始指针的页面位移。核心逆变换到局部轴，忽略垂直于该轴的位移，并限制在当前几何上限。候选显示预览，revision、已提交源及历史保持；回到起点无历史，松开将最终调节和必要文字适配合为一项历史，Escape、指针取消及丢失捕获使用现有取消路径。旧身份、锁定、无效手柄、字体/布局及资源失败保持最后有效候选和已提交源。位置与拖动规则参考 [ONLYOFFICE 预设 XY 调节](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L6950-L6982)及[逆变换与上下限](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/AdjustmentTracks.js#L195-L252)，实现归 [`adjustment-gesture.mbt`](../../modules/formats/src/pptx/adjustment-gesture.mbt)。

旋转使用 `{ action: "rotate", angle }`，绝对角度为 -360°–360°，核心舍入到 1/60000°。`{ action: "flip", axis: "horizontal" | "vertical" }` 切换局部水平/垂直翻转。`{ action: "layer", order: "front" | "back" | "forward" | "backward" }` 调整本地顶层对象或同组成员的源顺序。三者均支持同一父容器中的本地对象集合，组作为一个对象处理。各操作保留位置、尺寸、对象身份、文字、裁剪和关系；相同角度与层次边界不新增历史。旋转独立保持各对象自身中心点；翻转分别反转各对象的局部轴状态。文字、图形、图片、命中和选区消费同一矩阵。`geometry` 返回源有效 `rotation/flipX/flipY`，`rotateReason/arrangeReason` 返回对应保护原因。`noRot` 仅阻止旋转；继承、跨父组选择与原有变换锁继续保护。默认 UI 提供角度、翻转及四种层次操作。

批量旋转/翻转要求对象模式，保留各成员位置、尺寸、源顺序、关系、选择顺序及活动对象；组成员的局部源几何保持，世界矩阵随组方向更新。一次提交一项历史，任一成员、源或包预算失败不提交部分对象；相同角度无变化时不新增历史。默认角度框在值混合时留空并显示提示，翻转按钮使用 `aria-pressed="mixed"` 表示混合状态；选择集合改变时刷新角度。旋转锁检查全部成员，`noRot` 不阻止翻转。

层次调整要求对象模式；空选择保持文档不变。`front/back` 按原源顺序将所选对象放到最上层/最下层。`forward` 从上到下、`backward` 从下到上处理，每个所选对象仅越过一个相邻未选对象，所选对象之间保持原顺序。组作为父容器中的单个对象移动，内部层次和完整矩阵保持；未知未选对象原样保留。核心只移除并插入所选源片段，保留注释、其他源内容、关系、选择顺序及活动对象。任一成员受保护或预算失败时整项拒绝，成功只提交一项历史；已到边界或全选而无变化时不新增历史。默认四个按钮支持多选。

文字与变换候选基于原范围重算，不写入已提交 XML，不累积中间历史。暂态查询/布局读取候选；提交一项历史，取消恢复原选择。保存、PDF 和普通编辑在候选期间失败。Enter 是普通段落分隔 `\n`，Shift+Enter 使用对象内软换行 `U+2028`；保存为 DrawingML `p` / `br`。跨 run/段落保留范围外字符与段落属性，不重建整个 `spTree` 或 `txBody`。普通逐字符输入目前各自成项。

对齐使用 `{ action: "align", alignment: "left" | "center" | "right" | "top" | "middle" | "bottom", relativeTo: "slide" | "selection" | "active" }`。相对页面使用页面边缘或中线；相对选区使用所有成员旋转后的矩形包围盒；相对活动对象使用 `selection.object` 的包围盒并保留该对象的位置。`center` 为水平居中，`middle` 为垂直居中。单对象相对自身选区或活动对象时不修改源。

分布使用 `{ action: "distribute", axis: "horizontal" | "vertical", relativeTo: "slide" | "selection" }`。页面分布至少需要两个对象，选区分布至少需要三个；不足时明确拒绝，不切换参考范围。按世界坐标矩形中心排序，中心相同则按选择顺序。选区分布固定排序后的首尾边缘，其余对象保持相等边缘间距。页面有余量时，内部间距与两端留白相等；总尺寸不小于页面时，两端贴页面边缘，内部间距允许为负。旋转矩形边界包含零尺寸线段，不计描边宽度。

对齐与分布要求对象模式，沿用 256 成员、同一父容器中的本地对象及现有锁定/继承/未知资源保护。只改成员位置，保留顺序、活动对象、尺寸、旋转、翻转、文字、裁剪和关系；位置舍入为整数 EMU。成员越界、输出或历史预算失败不提交任何成员，成功只新增一项历史，重复操作或对齐到自身的零位移不写源、不新增历史。默认面板提供参考范围、六种对齐和两种分布，活动对象参考下禁用分布。接口复用 `editPptxObjects` / `PresentationEditor.editObjects`。

组合使用 `{ action: "group" }`，至少选择两个同一父容器中的可编辑本地对象。核心分配新组身份，保留成员身份、相对顺序、格式及关系，转换局部坐标；新组在原父容器中放到所选最上层对象的位置，选择切到新组。原组也可参与嵌套组合。顶层组沿用整体移动、缩放（含非等比例）、旋转、翻转、层次、对齐和删除事务；候选同步派生成员世界矩阵，不写已提交源。多选集合的独立宽高缩放沿上文同一候选路径执行。

取消组合使用 `{ action: "ungroup" }`，选择须全部为同一父容器中的受支持组。包含非等比缩放及嵌套组，成员回到原组所在层次，选择展开为直接成员，最多 256 项。核心先把累计组缩放换算为成员框的位置与尺寸，再以旋转/翻转矩阵绘制；文字字号、边距及描边宽度保持原值，文字按新框排版。候选预览和源重读使用同一几何规则；取消组合还原世界位置、尺寸、旋转及翻转，保留成员身份、命名空间和组内注释。子组保留成员和页面姿态，可继续逐层取消组合。组内组合与显式取消组合沿相同事务，坐标与保护规则见下文。

组内组合先在父组方向计算包围盒，再按累计父组缩放写入原生 `off/ext` 和成员局部框；新组的 `chOff=0`、`chExt=ext`。父组保持身份、元数据及关系。取消组合把直接成员提升一级，转换到被移除组原父容器的坐标，不把嵌套成员直接提升到页面。两者保持成员页面位置、尺寸和方向，误差限于整数 EMU；组内成员集合变化与现有祖先边界重算合为一项历史。支持形状、图片和子组，混合父组及继承内容继续保护。

祖先进入/几何锁、`noGrp/noUngrp`、成员锁、未知扩展、拆散连接关系的分组、计时引用及取消组合所移除组的链接或引用继续整项拒绝。展开选择最多 256 个直接成员；几何、字体、源/输出及历史预算失败不提交任何源，也不消耗新组身份。默认按钮使用现有 `groupReason/ungroupReason`。共享坐标提升归 [`group-geometry.mbt`](../../modules/formats/src/pptx/group-geometry.mbt)，保留原矩阵正交校验；删除的单成员提升共用它。分组框和局部坐标参考 [ONLYOFFICE getBoundsForGroup/getGroup](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L6945-L7006)，取消组合参考下文。

尺寸归一遵循 [ONLYOFFICE 组合缩放系数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L568-L607)及[成员 normalize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L629-L664)，取消组合参考 [unGroupCallback](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L7045-L7108)。核心已检查非等比嵌套、旋转/翻转、预览与提交一致、取消、文字/线宽、精确历史及重开；Chromium 已检查取消组合前后 Canvas 画面、独立同字号文本的 PDF 字形边界、XML、非目标部件、历史和重开后原生输入。

`PptxQuery.groupReason/ungroupReason` 返回当前选择的保护原因，默认 UI 用它禁用按钮。继承占位符、未知组效果/扩展、成员锁定、`noGrp/noUngrp`、拆散连接关系的组合、计时引用和取消组合所移除组的引用继续保护。操作只改所属 slide XML，保留其他部件及资源；一次提交一项有界历史，撤销恢复原源与选择，失败不消耗新身份或提交部分成员。

组内形状文字沿现有 `selectPptx`、`replacePptx`、格式、链接和查找替换命令编辑。`parent` 保留直接父组，`textReadOnlyReason` 独立于成员对象的 `readOnlyReason`；成员移动、缩放、旋转和翻转沿下文几何入口；复制、删除、层次及对齐复用下文同组事务，成员外观沿原属性命令编辑。`hitPptx` 的可选 `text: true` 返回最上层可编辑的文字成员及核心光标位置；普通命中仍返回顶层组，前方图片、形状或未知对象继续遮挡后方文字。核心使用累计组矩阵计算光标及选区，不在 Web 中反算文字坐标。

默认指针双击进入文字，文字拖选使用同一成员命中。对象列表按父子层次展开所选组及成员祖先；成员按钮进入文字，Escape 返回直接父组。文字输入、组合候选取消、字符/段落格式、框边距/垂直对齐/换行和三种适配共用原事务及默认面板。自动尺寸按累计组缩放还原局部整数 EMU，保留成员旋转/翻转和其他成员的页面姿态；本地父组外框与子坐标在同一事务中更新。缩放不改变字号、边距和线宽。

普通视图中的母版/版式成员、未知组效果、`noDrilldown/noSelect/noTextEdit` 及原文字保护继续拒绝编辑。祖先 `noMove/noResize` 不阻止固定框内输入，但阻止自动尺寸变更。缺字体、溢出及原有资源/输出预算失败整体拒绝，源与历史保持。行为参考 [ONLYOFFICE 组内文字选择与变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L196-L216)及[组内文字输入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L715-L730)，实现复用 [`group-geometry.mbt`](../../modules/formats/src/pptx/group-geometry.mbt)、[`text-resize.mbt`](../../modules/formats/src/pptx/text-resize.mbt)和[`文字命中`](../../modules/formats/src/pptx/hit.mbt)。

组成员几何复用 `beginPptx`、`dragPptx`、`finishPptx` / `cancelPptx` 以及 `rotate` / `flip` 对象命令，`PresentationEditor.transform` 的增量仍为页面点值。对象的 `transformReason` 返回移动/缩放保护原因，`rotateReason` 返回旋转保护原因；`arrangeReason` 返回层次和对齐保护原因。最多 256 个所选对象须来自同一父组，父子或跨父组选择整项拒绝。绝对 `transformPptx` 使用归一化父组坐标及尺寸，与当前 `PptxObject.geometry` 的 x/y/width/height 一致；`dragPptx` 使用页面坐标增量。

核心逆变换页面增量和固定角点，再按累计组缩放还原成员局部坐标。预览舍入为原生整数 EMU，提交读取同一几何；旋转和翻转保持中心，子组变化同步其成员世界矩阵。同组多选使用父组方向的包围盒及手柄，沿原成员缩放轴交换规则调整中心和尺寸。文字、字号、边距、描边和成员身份保留；文字框自动适配共用同一局部写回，取消、撤销重做、保存重开沿原源事务。本地父组边界随成员变换及自动适配重算，坐标归一化规则见下文。

默认对象列表在成员对象模式中支持普通及 Shift 同组选择；Enter 进入文字，Escape 返回直接父组。已进入组后，普通画布命中返回当前父组的直接成员，双击继续使用文字命中。移动/缩放及旋转/翻转控件复用已有面板；受保护的删除、复制和混合范围方向键不修改源，也不停止编辑器。祖先组的 `noDrilldown/noSelect/noMove/noResize`、对应旋转锁、成员锁、未知组和继承内容继续保护；原生坐标、字体、布局、源/历史及输出上限失败整项拒绝。同组成员组合及逐级取消组合沿原命令和按钮开放。

同一父组中的形状、图片及子组复用 `duplicate/delete/layer/align/distribute`。复制的 `dx/dy` 为页面点值，核心逆变换到父组坐标，再写整数 EMU；副本留在原父组，按原源顺序置于该组最上层，选择顺序与活动对象对应副本。对象身份、域身份与副本内引用沿已有复制事务重映射，图片资源共享。层次调整只改直接父容器中的源顺序，不改成员或组的原生框。对齐/分布仍使用页面包围盒、页面/选区/活动对象参考，再将页面增量写回父组；非目标成员的页面姿态保持。默认按钮复用原保护原因，父子或跨父组混选整项拒绝。对象模式下 Ctrl/Cmd+A 选择当前直接父容器中的对象，Ctrl/Cmd+D 与 Delete/Backspace 使用原复制/删除入口。

删除后，从内到外移除空组，并将单个存活成员提升到组原来的层次。核心保留成员页面姿态、尺寸、文字、身份与资源，组间注释和命名空间随存活内容保留；原生坐标按 EMU 舍入。改变的成员集合和重建边界与删除合为同一历史。删除清空对象选择，撤销恢复原源和完整选择。待折叠组的点击/悬停链接、`noUngrp/noDelete` 或连接/计时引用，以及原对象/祖先保护，会整项拒绝；查询 `deleteReason` 也显示当前选择引发的组折叠保护。资源及关系继续保留，不做包清理。规则参考 [ONLYOFFICE removeInGroup](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L5275-L5358)，实现归 [`object-delete.mbt`](../../modules/formats/src/pptx/object-delete.mbt)。

本地成员原生变换或已有组的成员集合改变时，核心按内层到外层重算祖先边界。范围采用 [ONLYOFFICE GroupShape](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L1246-L1384) 的旋转象限轴交换规则。受影响顶层组的子树归一化为 `chOff=0`、`chExt=ext`；按已舍入的父坐标写回子成员，保留页面中心、大小与方向，误差限于整数 EMU。成员文字、字体、边距、描边、身份、元数据和关系保留。未移动成员的局部 `x/y` 可以改变，宿主须读取当前查询，页面姿态保持。缺省 `chOff` 写入 `chExt` 之前。实现归 [`group-bounds.mbt`](../../modules/formats/src/pptx/group-bounds.mbt)。

预览只更新派生几何；提交从候选原生源重读坐标，并与原操作共用一项修订和历史，撤销/重做精确恢复源。顶层组整体变换、顶层复制与顶层新建组合不强制归一化；组内成员集合变化更新现有祖先组边界。只有当前编辑的源部件被改写，其继承对象保持；母版/版式源视图使用同一边界事务。未知同组成员、原生坐标及输出/历史预算失败原子拒绝。主题字体与页码自动适配沿同一坐标写回，避免重复除以组缩放。

页面增量与组内原生坐标换算参考 [ONLYOFFICE MoveShapeImageTrack](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/MoveTracks.js#L95-L145)及[组缩放写回](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/MoveTracks.js#L301-L315)。独立父组权限及受支持的本地组边界为 SDK 实施范围；母版、版式组编辑仍待实现。实现归 [`member-geometry.mbt`](../../modules/formats/src/pptx/member-geometry.mbt)、[`object-selection.mbt`](../../modules/formats/src/pptx/object-selection.mbt)和[`变换面板`](../../packages/ui/src/pptx-arrange.tsx)。

组成员外观复用下列原命令和默认面板。支持形状纯色/无填充、线性渐变、图片填充、描边/端点/线型及不透明度，支持预设调节值；独立图片成员支持替换、裁剪、拉伸/平铺、不透明度与拉伸目标内缩。形状批量外观仍原子提交，图片属性要求唯一对象选择。纯外观修改保留所有成员与父组原生变换，不触发组边界归一化；调节值引起的自动适配沿已有框事务更新边界。图片替换新建资源及关系，其他共用旧资源的对象保持。

祖先组的 `noDrilldown/noSelect`、未知组源、继承内容、原对象保护及属性专用锁继续拒绝。祖先移动/缩放锁允许不改框的外观操作；调节值引起的框变化仍遵守自动适配保护。既有未知属性、图片解码、源/资源/输出和历史预算原样执行，失败不提交部分成员。权限归 [`object-paint.mbt`](../../modules/formats/src/pptx/object-paint.mbt)，图片沿 [`image-edit.mbt`](../../modules/formats/src/pptx/image-edit.mbt)。局部填充/描边覆盖参考下文 ONLYOFFICE `changeFill/changeLine`，调节锁参考 [canChangeAdjustments](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicObjectBase.js#L1065-L1070)。

`editPptxObjects` / `PresentationEditor.editObjects` 支持 `{ action: "fill", color }` 和 `{ action: "stroke", color, width }`。颜色为不带 `#` 的六位 RGB，核心统一小写；null 写显式 `noFill`，表示无填充或无边框。宽度为 0.1–1000 pt，舍入到整数 EMU。操作作用于对象模式下所选的本地形状（含组成员），包含文本框和基本形状；多选原子提交为一次历史。查询中每个对象带 `appearance: { fill, gradient, imageFill, imageFillMode, imageFillReason, stroke, width, fillOpacity, strokeOpacity, fillOpacityReason, strokeOpacityReason, dash, dashReason, cap, join, miterLimit, penReason, reason }`，颜色为有效 RGB 或 null，宽度为有效 pt，reason 说明保护原因。默认 UI 显示混合状态，分别应用填充和边框，草稿随选择或实际外观值更新。

修改只覆盖目标属性，保留几何、顺序、身份、文字、其他线条属性与部件。缺失的填充/边框按 DrawingML 顺序创建，空边框保留原属性；填充覆盖会关闭 `useBgFill`。直接设置相同值不增加历史；候选、过期 revision、锁定、未知填充属性/注释及预算失败不提交任何成员。组本身、继承装饰和独立图片的形状填充/描边仍受保护，径向渐变及复杂效果编辑待扩展；图片拉伸填充见下节。纯色与受支持线型沿共同 Canvas/静态 PDF 路径绘制。实现参考 [ONLYOFFICE CShape.changeFill/changeLine](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L6421-L6461) 的局部属性覆盖及背景填充处理。

`editObjects({ action: "gradientFill", stops, angle, scaled })` 将所选本地形状（含组成员）设为多色标线性渐变。色标使用[页面背景](#pptx)的 2–32 项颜色、位置与不透明度规则。角度为 0–360° 并按 1/60000° 舍入，360° 归一为 0°；`scaled` 为必需布尔值。角度及比例规则复用页面背景，保留形状的轮廓、调节点、几何、描边和文字，随对象旋转/翻转。默认外观面板与背景共用色标增删、位置/颜色/不透明度控件，另有类型、角度和按形状比例缩放。查询 `appearance.gradient` 返回 `{ kind: "linear", stops, angle, scaled }` 或 null；渐变时 `fill` 为 null、`fillOpacity` 为 1；整体填充不透明度命令受保护，各色标不透明度沿 `gradientFill` 编辑，纯色描边仍可调整。纯色/无填充命令可替换已有受支持渐变。

读取本地、版式/母版继承及主题的 2–32 项 RGBA 渐变色标；源的 `rotWithShape` 为缺省/真值，固定页面方向、路径渐变、非零 tileRect 或未知标记保留源并诊断。操作先校验全部成员，复用原子源事务、无操作和精确历史；非法值、保护成员和输出预算失败保持整个文档。定位图元 `ClipPath(path, evenOdd)` 复用既有绘制命令，Canvas/PDF 沿相同预设路径裁剪，矩形以外区域及后续图元保持原样。实现归 [`shape-gradient.mbt`](../../modules/formats/src/pptx/shape-gradient.mbt)；参考 [ONLYOFFICE 形状渐变绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1970-L2037)的逐色标位置绘制。

### 图片目标内缩

`editObjects({ action: "imageInsets", insets })` 设置所选本地图片及图片填充形状（含组成员）的目标矩形。`editSlides({ action: "backgroundImageInsets", insets }, slide?)` 设置图片背景，继承背景可创建本页覆盖并复用原资源。两者沿同步 Wasm、Worker、宿主和默认面板使用相同事务。对象查询返回 `imageInsets` 与 `imageInsetsReason`；图片背景的 `value.insets` 返回有效值。

`insets: [left, top, right, bottom]` 是对象或页面宽高的比例。正数向内，负数向外；四个零恢复完整目标。每项须在 DrawingML 有符号百分比范围 −21474.83648–21474.83647 内，按 1/100000 舍入后，左右与上下之和分别小于 1。默认控件使用百分比，支持四边设置、重置及一次应用。当前仅拉伸支持目标内缩；切为平铺会移除拉伸矩形，再切回拉伸使用零内缩，源裁剪继续保留。

核心先把有效源裁剪映射到目标矩形，再同时裁剪到该矩形与形状轮廓或页面。内缩留白不会露出被裁掉的源像素。目标随对象旋转/翻转，透明度乘源像素 alpha；Canvas、PNG/JPEG 和 PDF 复用同一图元。读取支持本地、版式、母版与主题来源；对象内缩编辑要求本地图片或填充。替换图片、透明度及同模式格式编辑保留目标矩形；不改变对象外框、文字、图片字节或现有关系。非目标源保持，同值不增加历史，混合输入和设置可精确撤销并保存重开。

目标展开后的图片宽高与位置绝对值不超过 1e9 pt，并继续遵守图片、输出和历史预算。空矩形、未知源、保护及预算失败整体拒绝。实现归 [`image-insets.mbt`](../../modules/formats/src/pptx/image-insets.mbt)，目标与源矩形的组合依据 [ONLYOFFICE drawBlipFillStretch](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1778-L1834)，未复制上游源码。

### 形状图片填充

`editObjects({ action: "imageFill", objects, bytes, mode })` 将所选本地闭合形状（含组成员）设为 PNG/JPEG 图片填充，`mode` 必须为 `stretch` 或 `tile`。`objects` 是文件读取前捕获的有序选择，提交时须与当前选择完全一致，防止异步读取后修改其他对象。图片沿既有 4 MiB、尺寸、资源数量、输出和历史预算校验，Web 提交前检查实际解码。多选共享一个新资源及关系，保留各自身份、几何、轮廓、描边、文字、已有裁剪和有效填充不透明度。核心沿既有图片事务提交，失败不增加资源或历史；相同本地图片无操作。默认面板选择图片后直接应用，清除和纯色/渐变命令可替换受支持图片填充。

查询 `appearance.imageFill` 返回资源键或 null，`imageFillMode` 返回 `stretch`、`tile` 或 null，`imageFillReason` 返回保护原因。读取本地、版式/母版和主题的内部图片关系，按来源部件解析；支持非负四边源裁剪及常量 `alphaModFix`。图片按预设形状轮廓裁剪，随对象旋转/翻转，Canvas/PDF 共用同一图元。已有本地图片填充可用 `fillOpacity` 修改透明度；继承图片先设置本地图片覆盖。带裁剪元数据的平铺复用 [ONLYOFFICE drawBlipFillTile](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1687-L1777)：使用整张源图的 96 DPI 尺寸、对齐和翻转，保留 `srcRect`；切回拉伸才应用裁剪。模式切换、替换、透明度和精确历史保留这些值；切回拉伸的扩展尺寸及平铺数量超限原子拒绝。目标内缩归[图片目标内缩](#图片目标内缩)；固定页面方向、外链、背景关联图片填充及未知/重复/不透明源继续保护，仍归 P12 后续实现。实现归 [`shape-image.mbt`](../../modules/formats/src/pptx/shape-image.mbt)和 [`object-image.mbt`](../../modules/formats/src/pptx/object-image.mbt)，语义参考 [ONLYOFFICE 图片拉伸、裁剪和透明度绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1778-L1848)，未复制上游源码。

`editObjects({ action: "imageFillMode", mode })` 在已有本地图片上切换拉伸和平铺，不新增图片或关系；继承填充须先设置本地覆盖。默认面板提供模式选择、应用及按所选模式上传文件。平铺采用 96 DPI，即源像素乘 0.75 pt，不读取嵌入 DPI。导入支持 `sx/sy`（1–100000000，以 100000 为一倍）、`tx/ty`（±182880000 EMU）、九种 `algn` 及 `flip=none/x/y/xy`；偏移和对齐确定原始格点，负索引仍保持交替镜像相位。换图保留已有平铺参数，切换回平铺使用默认顶左对齐、原尺寸和无翻转。非零源裁剪在平铺时保留，切回拉伸后生效；未知源继续保留并诊断。

核心只生成覆盖形状的有限图片图元，沿同一轮廓裁剪供 Canvas/PDF 使用。每页最多 65536 个重复单元；应用、复制、尺寸修改及单选/多选变换预览超过预算时，在资源、历史或候选变化前拒绝。已有超预算源仍可原样保存，输出受预算保护。实现归 [`shape-tile.mbt`](../../modules/formats/src/pptx/shape-tile.mbt)，尺寸、对齐和交替镜像依据 [ONLYOFFICE 平铺绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L1685-L1776)及[镜像纹理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/Graphics.js#L870-L949)。未复制上游源码，未增加渲染后端或依赖。

`editObjects({ action: "fillOpacity" | "strokeOpacity", opacity })` 分别设置纯色/本地图片填充和纯色边框的不透明度，值为 0–1，按 1/100000 舍入。默认 UI 使用百分比输入；查询返回两项有效值及各自保护原因，支持混合多选。无填充的一侧须先设置填充，0 保留形状和选择。100% 写入明确的不透明覆盖，不表示恢复继承。

读取已有颜色的 alpha、alphaMod 和 alphaOff，按声明顺序计算并归一到 0–1。修改保留 RGB/系统色/主题色及 tint、shade、lumMod、lumOff 等关联；继承填充写为本地声明，主题 phClr 绑定到原引用颜色，保留主题和父级源。颜色与线宽修改保留已有有效不透明度；明确移除填充后不保留隐藏的 alpha 状态。操作复用同一多选源事务、待输入文字屏障和精确历史。未知颜色标记、保留注释、只读对象及预算失败拒绝全部成员。文字和页面背景的透明度仍受原保护。算法参考 [ONLYOFFICE 颜色 alpha 变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L2089-L2108)，实现归 [`shape-opacity.mbt`](../../modules/formats/src/pptx/shape-opacity.mbt)。

`editObjects({ action: "strokeDash", dash })` 修改所选本地形状（含组成员）的预设线型，适用已有多选、文字框和基础形状。`dash` 接受 `solid`、`dash`、`dashDot`、`dot`、`lgDash`、`lgDashDot`、`lgDashDotDot`、`sysDash`、`sysDashDot`、`sysDashDotDot` 或 `sysDot`；null 移除局部 `prstDash` 并恢复主题/父级，缺省为实线。`appearance.dash` 返回有效线型，`dashReason` 返回本操作的保护原因。默认 UI 提供线型选择、应用和恢复继承，混合选择继续显示混合状态。

修改只写目标 `prstDash`；缺少 `ln` 时按 DrawingML 顺序创建局部边框，保留颜色和宽度继承，明确的 `solid` 可覆盖主题虚线。行宽、颜色、填充、几何、文字、身份及其他部件保持，整组共用一次精确历史。重复同一直接值不新增历史，源注释/处理指令或未知线型属性保护修改；自定义 dash、重复声明及未知预设保留源并诊断。

预设使用 [ONLYOFFICE DashPatternPresets](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Metafile.js#L1767-L1820)的线宽倍数，普通短划线为 4/3，长划线为 8/3，系统短划线为 3/1。有效线宽变化同步缩放 dash。定位后的路径携带点值数组，Canvas 沿已有绘制样式执行并复原，PDF 使用单路径作用域中的 dash 指令，后续图元继续沿自身样式绘制。自定义 dash 继续实施。

`editObjects({ action: "strokeCap", cap })` 设置 `flat/rnd/sq` 平头/圆头/方头，null 恢复继承。`{ action: "strokeJoin", join }` 设置 `round/bevel` 圆角/斜角，null 恢复继承；`{ action: "strokeJoin", join: "miter", miterLimit }` 设置斜接，比例为 1–1000，按 1/100000 舍入。查询返回有效 `cap/join/miterLimit` 及 `penReason`，默认 UI 提供两类样式、斜接上限和各自恢复按钮。

局部值按属性覆盖父级/主题；连接类型相同时继承缺失的斜接上限。基础缺省值为平头、圆角和斜接比例 8，依据 [DrawingML 继承与默认值](https://learn.microsoft.com/ga-ie/openspecs/office_standards/ms-oi29500/c0c046ec-a61d-405d-88fe-74d8487a37d7)。操作沿用本地形状（含组成员）、多选原子事务、精确历史与既有预算，保留颜色、宽度、线型、其他源属性和部件；不修改共享主题或母版。未知/重复连接、保留的连接注释、未知端点或超出支持范围的斜接值保留源并保护修改。

定位路径使用 `PathStyle { fillAlpha, strokeAlpha, dash, cap, join, miter }`，数值端点 0/1/2 对应平头/圆头/方头，连接 0/1/2 对应斜接/圆角/斜角。Canvas 复用既有 `DrawStyle`，每条路径后复原；PDF 在独立图形作用域写相同端点、连接、斜接、dash 及独立填充/描边 alpha。普通及斜线的端点形状参与核心命中。预览与输出不再把导入端点或连接静默画成默认值。

### 直线端点样式

`editObjects({ action: "lineEnd", side, end })` 修改所选本地顶层直线或已知折线/曲线连接线的端点样式。`side` 为 `head/tail`，分别对应路径起点的 `headEnd` 和终点的 `tailEnd`。`end` 为 `{ kind, width, length }`：`kind` 接受 `none/triangle/stealth/diamond/oval/arrow`，分别为无、实心三角、凹尾、菱形、椭圆和开放箭头；宽度与长度各接受 `sm/med/lg`。`end=null` 移除该端的局部声明并恢复继承，`kind="none"` 显式覆盖继承。MoonBit 类型为 `LineEnd`，Wasm/Web 类型为 `PptxLineEnd`；查询返回 `appearance.headEnd/tailEnd/lineEndReason`，默认面板提供两端独立设置、混合状态和恢复按钮。

尺寸使用有效线宽的 2/3/5 倍，细线以 1.875 pt 为最低基准。该值将上游的 2.5 px 最小尺寸固定到源坐标，预览缩放与 DPR 不改变 PDF 几何。三角、凹尾和开放箭头朝外，菱形与椭圆以端点为中心；端点沿实际首末非零线段或曲线切线方向、旋转、翻转和既有组矩阵绘制；支持普通直线及已知折线/曲线连接线。轮廓参与核心命中，使用边框颜色和不透明度，保持主体虚线而以实线绘制端点。Canvas/PDF 复用相同路径。零长度线不派生端点轮廓，保留原源。

导入读取局部、版式/母版及主题声明，缺省为无端点和中尺寸。编辑只替换指定节点，保留线宽、颜色、几何、文字、身份及其他部件；多选共享原子事务、精确历史和保存重开。重复直接值不增加历史。`noChangeArrowheads` 锁、只读/继承/组内对象、未知类型/尺寸/属性/子节点、重复声明、端点内注释及预算失败继续保护。连接线端点拖动及目标联动见[连接线](#连接线)。尺寸参考 [ONLYOFFICE EndArrow](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L7331-L7400)，轮廓参考 [DrawLineEnd](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Drawing/ShapeDrawer.js#L51-L500)；未复制上游源码。实现归 [`line-end.mbt`](../../modules/formats/src/pptx/line-end.mbt)、[`line-end-edit.mbt`](../../modules/formats/src/pptx/line-end-edit.mbt)及 [`pptx-line-ends.tsx`](../../packages/ui/src/pptx-line-ends.tsx)。

主题颜色支持 sRGB、带 `lastClr` 的系统色、主题/颜色映射以及 tint、shade、lumMod、lumOff。支持无填充、纯色填充、实线及标准预设虚线、主题填充/边框/背景引用和无效果样式。未知颜色变换、填充或可见效果保留源并诊断，不静默宣称完整。占位符依类型/索引匹配，当前属性按具体声明覆盖继承值；写回不修改共享主题、母版或版式。

字体键为有效 family，按需附加 `|bold` / `|italic`。主/次字体、显式 Latin/EA/CS 字体及当前常见脚本映射参与解析；自动推断覆盖 Latin、简中 Han 缺省、Kana、Hangul、Arabic、Hebrew、Devanagari 和 Thai。语言敏感的 Han 区域字体推断尚未扩展；不声明全语言主题字体一致性。调用者提供授权字体及实际样式映射，缺失时明确失败。

文本框读取基本字号、粗体/斜体、文字色、段落对齐、内边距、缩进、点值/百分比段距及行距、软换行和字符项目符号的字体/大小/颜色。固定框越界诊断并裁剪；无法建立文字几何时保留边界占位和对象文本查询。`normAutofit` 以 10 次有界搜索求解 10%–100% 字号缩放，同时检查可用宽高，保存必要 `fontScale` 并保留基准字号。字段所在框保持文字编辑保护；简单编号字段的显示见下节。其他字段、图片项目符号、多栏、纵排及文字变形继续诊断或保护。

`editPptxObjects` / `PresentationEditor.editObjects` 已支持 `{ action: "textInsets", left, top, right, bottom }`、`{ action: "textAnchor", anchor }`、`{ action: "textWrap", wrap }` 和 `{ action: "textFit", fit }`。四边距离为 0–14400 pt，舍入为整数 EMU，须保留有效文字区域；anchor 为 `t`、`ctr` 或 `b`。布尔 wrap 控制框内换行。fit 为 `none`（固定框）、`shrink`（缩小字体）或 `resize`（形状随文字调整大小），分别保存 `noAutofit`、`normAutofit` 或 `spAutoFit`。它们作用于所选本地顶层文本形状，文字模式和对象模式均可调用，多选合为一次源事务。默认 UI 提供四边输入、垂直对齐、换行开关和适配模式，保留待提交的原生文字输入。

每个 `PptxObject.textFrame` 返回有效 `left/top/right/bottom/anchor/wrap/fit` 及保护原因 `reason`。修改保留文字、字符格式、身份、选择和其他部件；缺失 `bodyPr` 与适配节点按 DrawingML 顺序创建，其他属性和非目标注释原样保留。`shrink` 重新测量并保存比例，10% 字号仍无法容纳时原子拒绝。`none` 保留当前尺寸及固定框越界诊断。

`resize` 保留名义字号。开启换行时保持宽度、调整高度；关闭换行时按显式段落和软换行调整宽高，内容减少时也收缩。复用当前预设形状文字内框及段落测量，计入边距、列表和行段距。未旋转对象按首段水平对齐与框垂直锚定保持对应位置；旋转对象保持中心及方向。原生输入、字符/段落格式、框属性、查找替换和变换完成时，几何与文字合为同一项精确历史。保存重开沿用已写入几何，后续编辑继续重算。行为依据 [ONLYOFFICE 文字内框及位置更新](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L3646-L3870)，实现归 [`text-resize.mbt`](../../modules/formats/src/pptx/text-resize.mbt)。

无变化不增加历史。形状边长沿用 0.1–14400 pt，尺寸向上取整到 EMU；预设内框求逆不重复测字，最多 16 次文字重排。超限、无可用内框、不收敛、变换锁、缺字体、未知适配内容或输出/历史预算失败均原子拒绝。候选和旧 revision 保持既有保护。组内/继承对象及独立保持直立的旋转文字仍待对应编辑支持；普通水平文字沿用已有裁剪、Canvas 与 PDF 路径。

`editPptxObjects` / `PresentationEditor.editObjects` 支持 `{ action: "textFormat", format }`，其中 `PptxTextFormat` 可包含 `font/size/spacing/bold/italic/color/underline/strike/highlight/script`。至少提供一项，省略项保持；不接受 null 清除或未知字段。font 为不超过 200 UTF-16 单元的实际字体族，不能包含 `|`、换行或以 `+` 开头；主题字体编辑见[主题字体](#主题字体)。size 为 1–1024 pt，核心舍入到 0.01 pt。color 为六位 RGB 十六进制，查询和保存规范为小写。字体族同时写入 latin/ea/cs，授权字体与样式仍通过宿主 profile 供应。

`spacing` 为以 pt 表示的字符间距，正值扩展、负值紧缩、0 恢复正常间距。编辑范围为 −1584–1584 pt，核心舍入到 0.01 pt，读写 DrawingML `spc` 的整数百分之一点；无本地定义时沿段落、列表、版式和母版继承。普通范围、折叠光标后续输入、空段尾、多框、母版分级默认格式及字符清除共用现有事务、适配与公共塑形，Canvas/PDF 使用同一组位置。默认文本与母版面板提供同名控件。单位依据 [ONLYOFFICE 字符间距读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L9051-L9052)；本 SDK 使用共享塑形的 ±1584 pt 资源上限，未覆盖原生格式更大的完整数值范围，越界源保留并诊断。实现归 [`text-read.mbt`](../../modules/formats/src/pptx/text-read.mbt)及 [`text-format-properties.mbt`](../../modules/formats/src/pptx/text-format-properties.mbt)。

文字模式修改选中字符，光标处创建用于后续输入的格式；空段落写入 `endParaRPr`。对象模式作用于所选本地顶层文本框，混合多选合为一项事务。`{ action: "textAlign", alignment: "left" | "center" | "right" | "justify" }` 修改所涉段落，对象模式修改框内全部段落。`PptxQuery.formatting` 返回上述十项字符属性及 `alignment` 的共同有效值，混合值为 null；`reason` 返回保护原因。无可编辑选择时为 null 占位，不是源格式。两种类型从 `wasm/pptx` 和 `web/pptx` 导出。

`justify` 写回 DrawingML `algn="just"`，导入和继承使用相同有效值。默认格式面板提供“两端对齐”按钮；自动换行的中间行沿公共段落排版扩展间隔，末行保持自然宽度，原生输入、命中、光标、适配和 Canvas/PDF 使用同一组坐标。无变化时不增加历史；清除段落直接格式恢复继承。行为参考 [ONLYOFFICE 段落两端对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L5255-L5261)，源值参考 [TextAlign](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Limit/TextAlign.cpp#L44-L77)。分散对齐和 `justLow` 等变体仍保护，不将其默认为两端对齐。

underline/strike 为布尔值，保存为 DrawingML 的 `u="sng"/"none"` 和 `strike="sngStrike"/"noStrike"`。highlight 接受六位 RGB 或空串；空串清除高亮，写入含 `alpha=0` 的透明颜色以覆盖继承，并保留继承定义。查询空串表示无高亮，null 表示混合或保护占位。高亮沿既有纯色/主题颜色解析；未知内部标记及其他透明度仍保护。公共 `Line::positioned` 在文字前输出高亮，在文字后输出同文字颜色的下划线与删除线，使用塑形光标确定装饰范围；装饰修改保留 glyph、光标和逻辑文字。Canvas 与 PDF 共用此图元序列，PPTX 继续在框边界裁剪。DrawingML 属性及高亮写回参考 [ONLYOFFICE RunProperties](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/RunProperties.cpp#L233-L238)和[字符属性输出](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/RunProperties.cpp#L425-L452)。双线、波浪/虚线、自定义线色等其他装饰继续实施。

script 接受 `baseline`、`superscript` 或 `subscript`，分别写入 DrawingML `baseline=0/30000/-25000`。恢复基线写 0 覆盖继承，清除直接格式移除本地 baseline 并恢复继承。导入按首个有效 baseline 的正负识别上、下标，保留未改源值；此行为遵循 [ONLYOFFICE 读取](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L8957-L8966)和[写出](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/SerializeWriter.js#L2202-L2205)。查询字号保留名义值，公共布局按 65% 绘制字号及名义字号的 +35%/-14.1% 基线偏移排版，沿用 [ONLYOFFICE 脚本度量](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/commonDefines.js#L799-L802)。原生输入、命中、光标、选区、适配、Canvas 与 PDF 共用相同文字布局；任意数值偏移编辑仍待支持。

字符操作按需拆分 run，保留范围外文字、字符和段落属性、命名空间、对象身份、几何及其他部件。后续输入继承光标格式，替换范围继承首个选中字的格式。格式、对齐及原生文字共用精确历史；无变化不增加历史。已有缩小适配继续重新测量和保存比例，固定框继续诊断并裁剪溢出。候选、旧 revision、缺字体、锁定、未知 run/格式扩展或输出预算失败保持源和历史。字段、组内和继承对象继续保护。行为参考 [ONLYOFFICE 当前文本范围操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L1373-L1415)。更多装饰和图片项目符号仍待实现。

`{ action: "clearTextFormat" }` 清除所选 run 的字体、字号、字符间距、粗斜体、下划线、删除线、文字色和上/下标直接定义，恢复段落、列表、版式及主题继承。保留高亮、语言、链接与源间隙；高亮使用独立的空串操作关闭。文字范围按需拆分 run；光标处建立用于后续输入的继承格式，空段落清除 `endParaRPr` 对应覆盖。对象模式清除所选本地文本框的 run 及段尾字符覆盖，保留段落默认字符定义。源中显式写出的默认值也会移除；再次清除不新增历史。语言与高亮保留规则参考 [ONLYOFFICE 字符清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L16926-L16947)。

`{ action: "clearParagraphFormat" }` 清除所涉段落的直接对齐、左/右/首行缩进、行段距、制表位/默认间隔及本地项目符号、编号、符号字体/大小/颜色定义，恢复继承。保留 `lvl`、`defRPr`、字符内容及其元信息；图片项目符号和未支持的编号类型仍保护。段落选择沿用 `textParagraph` 的范围规则，对象模式处理全部所选框。清除沿现有源事务、字体预检、适配与输出预算执行；未知格式标记或失败保持源与历史，撤销精确恢复原属性和选择。默认 UI 提供两个清除按钮，宿主与 Worker 沿 `editObjects` 调用。语义参考 [ONLYOFFICE 段落清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L11606-L11663)。

`{ action: "textParagraph", format }` 修改段距、行距、缩进、方向及列表。`PptxParagraphFormat` 可含 `left/right/first/before/after/line/list/level/rtl/listFont/listSize/listColor/tabs/defaultTab`，至少提供一项，省略项保持。三个标记样式字段和两个制表位字段接受 null，含义见下文；拒绝其他 null 和未知字段。left/right 为 0–4032 pt，first 为 -4032–4032 pt，相对段落起始侧缩进指定首行或悬挂缩进，核心舍入为整数 EMU。before/after/line 使用 `PptxTextSpacing`：`{ unit: "point" | "percent", value }`。段前/段后点值为 0–1584 pt，百分比为 0–1000%；行距点值至少 0.01 pt，百分比至少 0.001%，上限相同。点值和百分比分别保存到百分之一点和千分之一百分比；100% 为单倍行距。输出范围与顺序参考 [ONLYOFFICE TextSpacing](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/TextSpacing.cpp#L90-L162)及[段落属性](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/TextParagraphPr.cpp#L196-L218)。

`tabs` 使用最多 32 项的 `PptxParagraphTab { position, align }`；position 为 0–1584 pt 内的整数 twip，严格递增且不重复，align 为 `left/center/right/decimal`。写入原生 `tabLst/tab`，对齐分别为 `l/ctr/r/dec`，不生成引导符或竖线。`defaultTab` 为 0–1584 pt，舍入到整数 EMU 后写 `defTabSz`；零关闭后续默认间隔。缺省沿 [ONLYOFFICE 演示文稿的 25.4 mm／72 pt](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L2889-L2899)。查询返回共同有效值，混合项为 null。DrawingML 的位置和对齐定义见[原生制表位](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.tabstop?view=openxml-3.0.1)。

原生制表位沿段落、列表、版式/母版和默认样式读取，同位置由近层覆盖；合并依据 [ONLYOFFICE 段落继承](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L16450-L16456)及[同位置覆盖](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js#L15464-L15504)。无继承制表位时，数组替换本地定义，空数组清空；tabs=null 移除本地定义并恢复继承，defaultTab=null 单独恢复默认间隔。改写有效的继承制表位仍须样式级编辑，当前原子保护；恢复本地覆盖可执行。低于 twip 精度、超限或未知原生内容保留源并诊断，带内部注释的列表替换/清除保护。

公共制表位排版同时提供对齐后的字形、光标、选择、适配和 Canvas/PDF。字符、其他段落、属性、对象及部件保持。默认面板提供位置、对齐、间隔、清空及恢复；原生 Tab 文本沿既有粘贴入口，全部与源修改共用精确历史。实现归 [`paragraph-tabs.mbt`](../../modules/formats/src/pptx/paragraph-tabs.mbt)。

`rtl` 为布尔值，写入 DrawingML 段落方向；读取沿本地、列表、版式/母版和默认属性继承。缺少显式对齐时，RTL 默认右对齐；已有显式对齐仍按物理左右解释。切换方向时镜像当前左右对齐，居中和两端对齐保持，遵循 [ONLYOFFICE SetParagraphBidi](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L16952-L16967)及[非文档段落的默认对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L11257-L11288)。缩进、标记和双向文字使用公共排版器；PPTX 显式提供 LTR/RTL 基础方向，避免阿拉伯文首字符覆盖段落设置。字体、光标、选区、Canvas/PDF 和适配共用同一结果，缓存区分基础方向。`paragraph.rtl` 返回有效布尔值或混合值 null；默认面板显示混合复选状态。清除段落直接格式同时清除方向并恢复继承。局部范围、多框、原生草稿、精确历史与重开沿用已有事务，非法方向源保留并诊断。竖排、多栏继续实施。

文字模式修改光标所在或范围所涉段落，终点恰在下一段开头时不修改下一段；对象模式修改所选本地文本框中的全部段落。`PptxQuery.paragraph` 返回各字段的共同有效值和 `reason`，混合项为 null；保护时为 null 占位。类型和动作从 `wasm/pptx`、`web/pptx` 导出，宿主沿 `editObjects` 队列执行。修改只写目标 `pPr`，保留字符、未改属性、源注释、继承定义、非目标段落、部件及选择。未知间距节点内容保护该框的间距/缩进操作；无变化不新增历史，旧 revision、候选、缺字体、无可用行宽和预算失败均不提交。已有适配框重新计算比例；固定框保留溢出诊断。默认面板按各字段的有效值更新草稿，其他格式命令完成时不清掉输入。

list 使用 `PptxListFormat`：`{ kind: "none" }`、`{ kind: "bullet", value }` 或 `{ kind: "number", value, start }`。字符符号限一个字素、最多 16 UTF-16 单元；编号支持十六种格式：`arabicPeriod/arabicParenBoth/arabicParenR/arabicPlain`，以及 `alphaLc/alphaUc/romanLc/romanUc` 分别与 `Period/ParenBoth/ParenR` 组合。`Period` 使用句点，`ParenBoth` 使用左右括号，`ParenR` 使用右括号，`Plain` 不加标点；例如 `alphaUcParenBoth` 输出 `(A)`。start 为 1–32767。level 为 0–8；默认 UI 显示第 1–9 级。列表与级别可分别修改，也可和间距/缩进一起提交。查询返回有效列表定义及级别，混合值为 null。移除列表写 `buNone` 覆盖继承，清除段落直接格式移除本地列表定义并恢复继承，保留级别。

编号在各文本框内计算：向前跳过更深层段落，遇到更浅层、不同类型或不同起始值时重新起算；同级空段落不推进后续数字。规则依据 [ONLYOFFICE GetBulletNum](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L10678-L10717)。字母与罗马数字沿用 DOCX 的公共序号格式化，字母采用 aa、bb 等重复规则。逻辑文字与复制内容保留原段落文字，编号是布局标记。

首次应用列表按首个字符字号建立悬挂缩进，移除列表恢复标记所在左边界；显式 left/first 优先。规则参考 [ONLYOFFICE 列表缩进](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L10616-L10643)。保留已有符号字体、字号、颜色和其他段落元信息。标记进入公共段落布局，参与换行、行高、字体预检、适配及 glyph 预算，使用当前 36 pt 默认制表间隔分开标记与正文；Canvas 和 PDF 共用相同位置。已有字符内容、非目标段落、部件、选择及精确历史保持。格式值沿 [ONLYOFFICE DrawingML 编号枚举](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Limit/TextAutonumberScheme.cpp#L46-L88)，括号与标点沿 [PresentationNumbering](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Numbering/PresentationNumbering.js#L188-L298)；源保留完整类型，导入、修改、原生续号和重开使用同一标记规则。默认面板列出各格式的标记示例，Wasm 与 Worker 参数/响应校验共享同一允许列表。图片符号、地区编号和自定义制表设置仍待支持。

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

P6 基础与检查边界归 [P6 结果](../implemented/p6-pptx-editing.md)，增量创作能力与剩余范围归 [P12](../p12-pptx-core.md)。Chromium 受控输入事件已验证；没有追加系统输入源、Windows/PowerPoint、VoiceOver、其他浏览器或性能验收。

### 连接线

`PresentationEditor.editObjects({ action: "insertConnector", kind, start, end })` 创建原生 `p:cxnSp`。必填 `kind` 为 `straight`、`elbow` 或 `curved`，分别写 `straightConnector1`、三段折线 `bentConnector3` 或双段曲线 `curvedConnector3`。`connectorEndpoints` 用相同的类型和两端参数修改唯一选中的连接线；显式切换类型与端点修改合为一项历史，新类型恢复默认调节点。MoonBit 使用 `InsertConnector(kind, start, end)` / `ConnectorEndpoints(kind, start, end)` 及 `ConnectorEnd`，Wasm/Web 导出 `PptxConnectorEnd`：`{ x, y, target, site }`。坐标使用磅；`target=""` 表示自由端点，`site` 必须为 0。创建时连接线及目标位于顶层。编辑时 `target` 须属于同一源部件、同一直接父容器；坐标由目标的原生连接点计算，输入坐标仍须有限且有界。自由端点与查询端点始终使用页面坐标。

矩形、圆角矩形及矩形图片支持 0 上、1 左、2 下、3 右。椭圆支持 0 上、1 左上、2 左、3 左下、4 下、5 右下、6 右、7 右上。其余已支持的闭合预设也使用原生连接点：三角形、直角三角形、平行四边形、五边形、六边形及左右双向箭头各 6 个，八边形及上下双向箭头各 8 个，五角星 5 个，梯形、菱形、十字及其他实心箭头各 4 个。索引遵循 `CreateGeometry.AddCnx` 顺序；除上述命名点外，默认面板按原生序号显示。`PptxObject.connectionSiteCount` 返回实际数量，不能连接的对象为 0。连接点经过目标的旋转和翻转矩阵，再量化为整数 EMU。目标调节值修改、移动、独立宽高缩放、旋转、翻转和框适配时，同一事务更新连接线的 `xfrm`，保留 `stCxn/endCxn` 引用。变换候选使用相同规则，取消不写源。母版和版式沿源视图编辑，普通页继续保护继承对象。

`PptxObject.connector` 对连接线返回 `{ kind, start, end, reason }`，其他对象为 `null`。无法解析端点时，类型和两端均为 `null`，并返回保护原因。默认面板可创建或切换连接线类型，选择两端的对象和命名连接点，修改自由坐标或断开连接。线宽、颜色、虚线、装饰及 Canvas/PDF 路径复用既有直线实现。端点写入和目标联动各随本次编辑形成一项历史，保存重开后保留原生连接关系。

三段折线的原生 `adj1` 指定转折横坐标，缺省为框宽的 50%；当前支持框内 0–100%，原生导入、现有形状调节面板及拖动手柄使用同一值，恢复时移除局部声明。主体沿起点、转折上端、转折下端、终点绘制；箭头取实际首末非零段方向，水平或垂直退化仍保持。命中、Canvas 与 PDF 共用该路径。目标联动、端点拖动及组合复制保留类型与调节点；显式切换类型受 `noChangeShapeType` 锁保护。框外调节点、未知或含注释的几何替换继续保护源，不自动规划避障路径。依据 [ONLYOFFICE 折线预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L1222-L1232)。

双段曲线沿相同的 `adj1`、默认值及框内范围编辑。设框宽高为 `w/h`，转折横坐标为 `x=w*adj1`；起点为 `(0,0)`，第一段的控制点为 `(x/2,0)`、`(x,h/4)`，终点为 `(x,h/2)`，第二段的控制点为 `(x,3h/4)`、`((w+x)/2,h)`，终点为 `(w,h)`。Canvas/PDF 保留两段原生三次贝塞尔命令。箭头取首末非零控制方向，包含调节点极值和零尺寸轴。核心命中按相同控制点细分，平直误差阈值为 0.01 pt、最多 12 层；绘制不使用采样折线。类型切换、目标联动、组合复制和历史沿上述连接线事务。几何依据 [ONLYOFFICE 曲线预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L2414-L2426)，细分参考 [partition_bezier4](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Path.js#L3779-L3812)；有界命中实现归 [`connector-path.mbt`](../../modules/formats/src/pptx/connector-path.mbt)，未复制上游执行代码。

单选受支持连接线时，`selectionPptx.handles` 按起点、终点返回两个实际页面坐标。默认画布可直接拖动这两个手柄；`beginPptx` 使用 `kind="connector"`，`dragPptx` 的 `handle=1/2` 对应起点/终点，`dx/dy` 始终相对手势起始端点，另一端保持。可选 `tolerance` 为 0–64 pt，缺省 0 表示不吸附；默认宿主按当前预览比例换算 6 CSS px，不乘 DPR。核心按上层对象优先、原生连接点索引顺序寻找半径内的同一直接父容器中的本地受支持目标，沿用上述旋转/翻转和 EMU 量化。离开连接点范围后，该端变为自由端点。候选只更新临时页，释放时写回端点及连接关系并提交一项历史，返回起始状态不增加历史；Escape、指针取消及丢失捕获沿原候选取消路径恢复。旧 revision/候选、错误手柄、越界、退化为零长度、锁定和输出预算失败保持最后有效候选与已提交源。

有连接的线通过画布端点或面板修改，直接变换继续保护。连接线与全部引用目标同时选择时可组合或复制；整个组可复制，副本的原生引用映射到副本目标。同一直接父容器中的闭合图形支持组内端点编辑/吸附、成员移动/旋转、组缩放/旋转/翻转、嵌套及取消/再次组合。核心逆变换页面端点并写整数 EMU，复用既有组边界归一化，候选与提交保持一致。重复原生端点及连接关系不增加历史。默认列表选择连接线时进入对象模式。拆散引用的组合/复制、仍被外部引用的目标删除、跨父容器连接、其他曲线/折线预设、自定义或未知预设连接点继续保护。未知连接元数据、非整数或越界索引、失去目标、锁定和输出预算失败保留源与历史；受保护连接线也阻止其目标发生无法写回的几何变化。沿用对象数量、坐标、XML、历史和输出预算。

连接点计算归 [`connection-sites.mbt`](../../modules/formats/src/pptx/connection-sites.mbt)。三角形及箭头等点坐标依据 [ONLYOFFICE CreateGeometry](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8525-L8620) 的原生导引。实现归 [`connector.mbt`](../../modules/formats/src/pptx/connector.mbt)、[`connector-edit.mbt`](../../modules/formats/src/pptx/connector-edit.mbt)、[`connector-gesture.mbt`](../../modules/formats/src/pptx/connector-gesture.mbt)及 [`pptx-connectors.tsx`](../../packages/ui/src/pptx-connectors.tsx)。吸附规则参考 [ONLYOFFICE ResizeTrackShapeImage](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/ResizeTracks.js#L370-L450)及 [Geometry.findConnector](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Geometry.js#L1174-L1187)。组内连接重算及父组逆变换参考 [ONLYOFFICE CnxShape](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CnxShape.js#L624-L684)。原生点顺序参考 ONLYOFFICE `CreateGeometry` 的[矩形](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L6741)、[椭圆](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L3100)、[圆角矩形](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L7195)和[直线连接线](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/CreateGeometry.js#L8272)，未复制上游执行代码。

### 基础艺术字

`editObjects({ action: "insertWordArt", preset, text })` 在当前页面或源视图创建标准 DrawingML 文字框。`preset` 支持 `blue`、`gold`、`red`、`purple`、`green-italic` 五种纯色预设；颜色分别为 4472C4、FFC000、C00000、7030A0、70AD47。文字为 Arial、54 pt、粗体，绿色另带斜体。预设写入普通 run 和段末字符属性，不添加私有样式状态；后续文字、格式、查找、复制、变换和删除沿已有对象操作。宿主须提供对应粗体及粗斜体字体，缺字体不提交。

核心按实际字体度量生成不换行、水平/垂直居中、随文字调整大小的框，再置于页面中央。全部文字成为活动选择，默认面板把焦点交还原生输入，首次键入可直接替换。输入、字号或框设置变化复用既有自动适配；首次插入和后续输入各自进入一项精确历史。保存重开、Canvas、PNG/JPEG 和静态 PDF 使用同一排版。其他对象、关系及未改部件保留。

`text` 必须含非空白内容，沿现有对象文字规则接受有效 XML 字符、LF 段落、软换行和 Tab；最多 32767 个 UTF-16 单元、256 段，每段最多 4096 单元。旧 revision、活动候选、放映、保护、字体及尺寸/输出/历史预算失败原子拒绝。框尺寸沿既有 14400 pt 上限。文字描边、渐变、阴影、弯曲及三维艺术字继续实施，已有变形节点继续诊断并保护源。

不换行只关闭自动断行；对齐、RTL、制表位和命中继续使用实际框宽。核心不再用极大虚拟宽度对齐，并在段落缓存中区分是否换行。实现归 [`word-art.mbt`](../../modules/formats/src/pptx/word-art.mbt)、[`text-frame.mbt`](../../modules/layout/src/text-frame.mbt)和默认 [`word-art.tsx`](../../packages/ui/src/word-art.tsx)。文字框、无底色/边框、54 pt、居中与自动适配参考 [ONLYOFFICE createTextArt](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L8794-L8912)，插入历史和整段选择参考 [AddTextArt](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L11071-L11103)。五种纯色配方按 GenOffice 功能清单选择；未复制上游执行代码。

### PPTX 数学公式

形状文字和普通表格中的 `a14:m/m:oMath` 已接通原生读取、数学排版及 Canvas、PNG 和 PDF。单个 `m:oMathPara` 支持左/中/右对齐，`centerGroup` 按居中处理；显示公式独占段落，行内公式可与普通文字混排。已知 `mc:AlternateContent/Choice` 选择 DrawingML 2010 数学内容，保留原兼容后备源。包装形式依据 [ONLYOFFICE MathParaWrapper](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Runs/MathParaWrapper.cpp#L111-L130)。

公式与 DOCX 共用[有界数学结构](#docx-行内分数)、字体度量和图元。分数、上下标、根式、定界符、求和/积分及矩阵的读取归 [共享 OMML 读取器](../../modules/formats/src/internal/omml/math-read.mbt)。普通正体或数字沿既有规则读取，统一字体/字号/RGB 支持原生 Word 属性和基本 DrawingML `a:rPr`；DrawingML 可使用显式字号、纯 RGB 与相同的文字字体槽。主题字体、主题色、透明度和其他数学字符效果仍受保护。源未声明字体时使用 `Cambria Math`，由宿主提供实际字体及 profile。

独立公式使用较大的真实字体运算符，原生 `undOvr` / `subSup` 分别显示上下堆叠 / 右侧上下限，缩小参数仍用普通符号和右侧位置。模型、字体要求及 PDF 文字映射边界归[共享求和与积分布局](#docx-行内求和与积分)。文字框字号适配保留显示上下文，更新、无操作、精确历史及重开沿既有公式事务。

`editObjects({ action: "insertMath", latex, format, x, y, width, height })` 创建原生公式文字框。选中单个本地文字框后，`{ action: "appendMath", latex, format, position: "start" | "end" }` 在首尾插入独立公式段落。`latex` 复用 [DOCX 有界语法](#docx-latex-公式编辑)。共用的 `MathFormat` 为 `{ family, size, color }`；字体名最多 255 个单行单元，字号为 0.5–409 pt、精度 0.01 pt，颜色为六位 RGB。默认面板提供相同的插入和外观操作。

对象查询的 `equations` 返回 `{ node, latex, format, reason }[]`，其中 LaTeX 为共享打印器的规范化表达。选中所属对象后，`{ action: "updateMath", target, latex, format }` 修改整式，`{ action: "deleteMath", target }` 删除整式；`target` 为 `{ object, revision, node }`，必须来自当前查询。过期版本或错误对象拒绝执行。形状混排、显示公式和普通表格中的已有公式均可修改，保留周边文字与段落属性。无变化的修改不新增历史。

公式通过既有段落图形框参与基线、断行、框内边距、垂直锚定与表格单元格位移，不转换为图片。对象查询的 `text` 返回可读线性表达，普通文字输入仍通过 `textReadOnlyReason` 保护公式结构。空后备和已验证的单个纯文字后备可随对象或整页复制；修改表达时同步纯文字后备。未知后备、批注式 XML 内容、编辑锁和其他未知扩展保护相应操作。字体、布局和预算失败保留源与历史。创建、修改、删除、精确混合历史及保存重开沿核心事务，实现归[公式编辑](../../modules/formats/src/pptx/math-edit.mbt)。局部数学格式和更多结构继续实施。

单式沿 16 层、256 个结构节点和 4096 个文字单元的上限，PPTX 单式 XML 另限 2048 节点。文字框、页面字形、图元、资源和历史预算沿既有路径；未支持的数学源给出对象诊断并保护源，缺数学字体时输出明确失败。实现归 [PPTX 数学读取](../../modules/formats/src/pptx/math-read.mbt)和[段落绘制](../../modules/formats/src/pptx/layout.mbt)。DrawingML 数学字符属性依据 [ONLYOFFICE 数学内容](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/DocxFormat/Math/oMathContent.cpp#L2393-L2406)。

### PPTX 基础图表

`editObjects({ action: "insertChart", kind, title, data, x, y, width, height })` 插入簇状柱形图 `column`、条形图 `bar`、堆积柱形图 `stackedColumn`、堆积条形图 `stackedBar`、百分比堆积柱形图 `percentStackedColumn`、百分比堆积条形图 `percentStackedBar`、带圆形数据点的折线图 `line`、饼图 `pie`、面积图 `area`、堆积面积图 `stackedArea`、百分比堆积面积图 `percentStackedArea`、散点图 `scatter`、雷达图 `radar` 或圆环图 `doughnut`。选中单个本地图表后，`{ action: "chartData", kind, title, data }` 修改类型、标题和数据。对象查询的 `chart` 返回 `{ kind, title, data, legend }`，其他对象为 `null`。`chartDataReason` 返回当前对象数据修改的独立保护原因，空串表示可用；核心写入与默认面板使用相同原因。非图表对象返回具体原因，传输层拒绝缺失或非字符串字段。

`data` 为 TSV，首行给出类别轴标题和系列名，首列为类别，其余为有限数值或空值。支持 1–8 个系列、1–256 个类别，输入和规范化 TSV 均最多 65536 个 UTF-16 单元；标题及各标签最多 256 个单行单元。核心复用 XLSX 分隔文本导入，公式作为文字处理并在数值列拒绝。空值保留间隙，零值没有柱高；数轴包含零并采用 1/2/5/10 刻度间隔。参考 [ONLYOFFICE 数轴计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L2678-L2736)。

MoonBit 生成原生 `graphicFrame`、`barChart`、`lineChart`、`pieChart`、`doughnutChart`、`areaChart`、`scatterChart` 或 `radarChart`、系列公式/缓存、关系和实际嵌入 XLSX，使用固定配色、Arial 及图例。公共图元输出 Canvas 与静态 PDF。框最小为 180×150 点，移动、缩放、对齐、层级、删除复用对象事务。直接旋转和翻转保持保护。普通本地图表可与受支持对象组合；图表文字通过数据面板编辑，支持单选组内图表。

普通视图中的本地顶层图表支持 `editObjects({ action: "duplicate", dx, dy })` 和默认“复制对象”按钮。可与同父的普通对象一起多选复制，保留选择顺序、活动对象、内容、名称及非目标源。副本分配新对象身份、独立图表 XML、嵌入工作簿及关系；初始工作簿保留原始字节，后续改数据互不影响。复制、资源及内容类型合为一项精确历史。缓存与工作簿不一致、未知图表资源关系、复制锁、字体、布局或预算失败时整项拒绝。完整组合及组成员中的普通图表沿同一路径分配独立资源；复制前检查全部新成员的字体和布局。母版/版式图表复制继续保护。规则参考 [ONLYOFFICE 图表复制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L4959-L5028)，实现归 [`chart-copy.mbt`](../../modules/formats/src/pptx/chart-copy.mbt)和 [`object-copy.mbt`](../../modules/formats/src/pptx/object-copy.mbt)。

系统复制、剪切及跨文稿重复粘贴归[对象剪贴板](#pptx-对象剪贴板)。该路径按已核对的缓存重建独立普通值工作簿，排除原嵌入文件中的其他工作表；同稿“复制对象”继续保留原工作簿字节。

普通图表可参与组合与逐级取消组合，成员顺序和原生资源归属保持。组整体移动、缩放、旋转和翻转使用既有组矩阵；成员移动后沿图表框重算祖先边界，其他成员的页面姿态保持。取消组合把继承旋转/翻转写到 `p:xfrm`，重开后 Canvas/PDF 继续使用同一姿态。原生组复制为每个子图表创建独立图表和完整工作簿；系统复制完整组时，子图表沿上述快照路径重建独立普通值工作簿。组内及取消组合后均可分别改数据。数据编辑仅更新图表 XML 和工作簿，保留原生组、成员框、继承姿态及其他成员源；资源写回沿一项精确历史，无变化时不改源。组选择/文字锁和共享图表资源保持保护，仅限制组缩放时允许改数据。工作簿与缓存一致性仍在写入前核对。该成员编辑沿 [ONLYOFFICE 图表设置入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L3847-L3870)的组内选择语义，复用 [chart-edit.mbt](../../modules/formats/src/pptx/chart-edit.mbt)。直接图表旋转/翻转控件继续实施。表格组合归[普通表格](#pptx-普通表格)。实现复用 [group-bounds.mbt](../../modules/formats/src/pptx/group-bounds.mbt)、[object-group.mbt](../../modules/formats/src/pptx/object-group.mbt) 和 [object-copy.mbt](../../modules/formats/src/pptx/object-copy.mbt)，成员复制依据 [ONLYOFFICE GroupShape.copy2](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GroupShape.js#L310-L339)。

#### 图例显示与位置

`PptxChart.legend` 接受 `"none" | "top" | "bottom" | "left" | "right"`，插入、占位符填入及 `chartData` 共用此设置。省略时饼图/圆环图默认右侧，其他类型默认底部；查询总是返回实际 `legend`。默认数据面板提供相同选项。隐藏时不写 `c:legend`，四边位置写标准 `legendPos=t/b/l/r` 和 `overlay=0`。类型切换、独立对象/页面复制、精确历史及保存重开保留设置；数据未变时复用原工作簿路径和字节，不因修改图例、标题或类型而增加嵌入工作簿。

核心按真实字体度量安排顶部/底部图例的行列，并为绘图区预留空间；左右图例竖排。饼图/圆环图使用类别名称和扇区颜色，其他类型使用系列名称与相同颜色、线条或标记；堆积图的竖排图例按原生逆系列顺序排列。条目过多时显示剩余数量，单项文字裁剪在自身边界内。Canvas、PNG 和 PDF 共用核心布局。原生自定义字体/外观、覆盖图例、手动布局、条目删改和右上角位置继续保护源。位置与顺序参考 [ONLYOFFICE 图例布局](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L7725-L7855)，实现归 [`chart-legend.mbt`](../../modules/layout/src/chart-legend.mbt)。

`editSlides({ action: "copy" })` 和默认“复制页”按钮也支持含图表的页面。每个本地图表部件及嵌入工作簿克隆到新路径，页面关系指向副本，原页和新页可分别改数据。原本不同的图表保持独立；源页内部共用同一图表部件的关系结构在新页中保留，数据编辑仍遵守共享资源保护。已删除图表留下的关系也按相同原生配置和数据一致性规则克隆，未知资源保持保护。图表与工作簿、备注、批注、对象引用、隐藏状态和页面引用沿现有整页事务共同进入精确历史。删除页面继续保留未回收的图表资源。实现复用上述图表资源模块及 [`slide-copy.mbt`](../../modules/formats/src/pptx/slide-copy.mbt)、[`slide-add.mbt`](../../modules/formats/src/pptx/slide-add.mbt)。

`stackedColumn` 和 `stackedBar` 按类别把正值与负值分别沿零轴累计，系列按源顺序相接；空值不推进累计，零值没有可见段。数轴根据每类正、负总和取界，沿相同 1/2/5/10 刻度规则生成。所有系列共用一个类别位置，`gapWidth=150`、`overlap=100`；条形图保留原类别方向。原生 `barChart` 按方向保存 `barDir=col/bar` 和 `grouping=stacked`，缓存、公式及嵌入工作簿保留原数值。插入、数据修改、占位符填入、复制及类型切换复用原事务、独立资源和精确历史，默认面板提供两种类型。总和超出数值范围时原子拒绝；其他重叠/样式及组合继续保护。算法依据 [ONLYOFFICE 堆积轴取界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L1520-L1606)及[同号序列累计](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L3554-L3570)，实现归下述图表数据及布局模块，未复制上游执行代码。

`percentStackedColumn` 和 `percentStackedBar` 把每类原数值除以该类的绝对值总和，再分别累计正负比例。归一化先按最大绝对值缩放再求和，极大值不会因分母求和溢出；空值不参与，零值不产生可见段。数轴按比例总和取界、包含零、沿已有刻度规则并限制在 −100%–100%，显示整数百分比；全空或全零使用 0–100%。原生分组为 `percentStacked`，数轴使用小数范围及 `numFmt=0%`，系列缓存、TSV 和嵌入工作簿继续保存原数值。类型切换、原生查询、默认控件、独立复制及精确历史共用原入口。归一化和同号累计依据上述 [ONLYOFFICE 堆积计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L1520-L1606)，轴边界参考[百分比轴取界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L2693-L2726)。核心数据和绘制共享归一化结果计算，未知数轴格式仍保留源保护。

折线图按类别中心连接相邻非空数据点，空值断线，孤立点及零值仍显示圆形标记。线宽固定为 1.5 点，标记直径为 5 点；图例采用相同线段与标记。原生配置为 `standard`、`smooth=0`、`dispBlanksAs=gap`，与布局共用数据。曲线、堆积、其他标记及跨空值连接继续保护。行为参考 [ONLYOFFICE 折线与空值处理](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L9042-L9185)和[圆形标记](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L3158-L3205)。

饼图显示首个系列，按绝对值计算扇区。零值和空值不占面积，全零或全空时绘图区留空。全部系列保留在查询、原生缓存及嵌入工作簿中，切回其他类型仍可使用。核心先按最大绝对值缩放再求和，避免有限数值的总和溢出。第一片从十二点方向顺时针开始，类别颜色循环使用八色。TSV 首格作为副标题，和主标题写入原生富文本标题的两个段落。饼图不生成数轴，默认右侧图例按框高显示，放不下时显示剩余项数量；完整数据仍可编辑。当前不提供角度、分离扇区、数据标签或配色设置。语义参考 [ONLYOFFICE 饼图与首个系列](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L12238-L12346)，实现归 [`chart-pie.mbt`](../../modules/layout/src/chart-pie.mbt)。

圆环图使用 `kind: "doughnut"`，插入、数据修改及占位符填入接受可选 `holeSize`。它是 10–90 的整数百分比，省略时使用 75；其他图表类型拒绝此属性。圆环查询始终返回实际 `holeSize`，默认面板提供该数值控件。MoonBit 的 `InsertChart/ChartData/FillChart` 构造器末尾使用 `Int?` 传入同一设置，其他类型显式传 `None`。

每个系列按绝对值独立归一化，由内向外形成同心环，沿用饼图的类别颜色、标题和图例。径向可用宽度按系列数均分；没有任何数值点的空缓存不推进绘制环序号，零点仍保留所属环的位置。外弧与反向内弧构成闭合路径，Canvas、PNG 和 PDF 保留真实空心。原生 `doughnutChart` 保存每个系列的类别颜色及 `holeSize`，不生成数轴。空心比例、类型与数据修改沿一项精确历史；独立复制、缓存/工作簿核对和重开保留设置。范围沿用上述系列、类别、字号及资源预算；角度、分离扇区、数据标签、其他配色和更广原生配置继续保护。算法归 [`chart-pie.mbt`](../../modules/layout/src/chart-pie.mbt)，依据 [ONLYOFFICE 默认空心比例](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L6183-L6192)、[系列半径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L14106-L14215)、[相反方向的内外弧](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L14270-L14316)及 [OpenXML 空心比例范围](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.drawing.charts.holesize?view=openxml-3.0.1)，未复制上游执行代码。

面积图使用 `kind: "area"`。类别轴按 `crossBetween=midCat` 把首末类别点放在绘图区边缘，单类别居中。每个连续非空数据段沿零轴闭合，空值断开，孤立点和全零段不产生可见面积；正负部分保留原符号。系列按原顺序用固定不透明颜色绘制，后系列可覆盖前系列，不累计数据；图例沿相同系列顺序。当前无外轮廓和数据点标记，配置为 `standard`、`varyColors=0`、`dispBlanksAs=gap`。未知分组、透明度、标记及其他轴配置保持诊断和源保护。数据修改、切换类型、独立对象复制及精确历史复用原路径；Canvas、PNG 和 PDF 使用同一封闭图元。位置和空值规则依据 [ONLYOFFICE 面积图默认轴](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L6582-L6591)、[零轴闭合与断段](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L9735-L9840)及[系列绘制顺序与空值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L10796-L10884)。

堆积面积图使用 `stackedArea`，百分比堆积使用 `percentStackedArea`。两者按系列顺序累计带符号值，每条色带连接前后累计边界；空值按零参与累计，原生缓存保留空值。百分比分母为该类别各系列绝对值之和，先归一化再求和以避免有限大值溢出；零总量绘制零带。轴包含全部中间累计值，原生 `areaChart/grouping` 分别保存 `stacked/percentStacked`，百分比轴使用 `0%`。DOCX、XLSX、PPTX 共用以上类型、原生读写和默认控件；工作簿保留原值，类型切换不改数据源，XLSX 继续按当前公式值重算。累计与空值依据 [ONLYOFFICE 面积累计](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L10840-L10888)，色带依据[前后系列边界](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L9735-L9810)。

散点图使用 `kind: "scatter"`，TSV 首列为共享的有限数值 X 或空值，后续各列为 Y 系列。首格为 X 轴标题。X/Y 都存在时绘制直径 5 点的圆形标记；零值保留，缺失任一坐标时不画点。数值 X 按实际比例定位，重复、无序 X 和正负坐标保持；点之间不连线。两条数值轴分别沿相同零包含和 1/2/5/10 刻度规则取界，空数据轴使用 0–1；边界包含未成对的有限源数值。原生结构为 `scatterChart`、`scatterStyle=marker`、`varyColors=0`、两条 `valAx` 和各系列 `xVal/yVal` 数值引用/缓存，所有 X 引用同一工作簿首列。切换类型、独立复制、精确历史及重开沿既有事务。每系列独立 X、连线/平滑、气泡、其他标记和自定义轴继续保护。行为依据 [ONLYOFFICE 默认散点类型](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L6251-L6267)、[双数值轴](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartSpace.js#L13462-L13494)及[数值定位与空值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L14843-L14934)。实现归 [`chart-scatter.mbt`](../../modules/layout/src/chart-scatter.mbt)。

读取仅接受当前原生结构，未知图表类型、样式、轴配置或公式保持诊断与源保护。数据编辑前核对缓存与嵌入工作簿，拒绝共享图表资源。修改数据保留对象/图表身份，并新建嵌入工作簿以支持精确撤销。旧工作簿及删除后未引用的图表资源继续保留，受现有包和历史预算限制。更广导入、样式与资源回收继续实施。实现归 [`chart-data.mbt`](../../modules/layout/src/chart-data.mbt)、[`chart-read.mbt`](../../modules/formats/src/internal/chart/read.mbt)、[`chart-edit.mbt`](../../modules/formats/src/pptx/chart-edit.mbt)及 [`chart-layout.mbt`](../../modules/layout/src/chart-layout.mbt)。

### 简化 SmartArt 图示

`PresentationEditor.editObjects({ action: "insertDiagram", template, items, x, y, width, height })` 插入一个可编辑形状组。`template` 为 `process`、`hierarchy` 或 `cycle`，分别按水平流程、首项为根的单层层级、顺时针循环排列。普通模板接受 2–16 项，循环接受 3–16 项。每项最多 4096 UTF-16 单元，总计最多 32767；文字沿原形状校验与转义规则。坐标及外框使用页面磅，沿既有对象边界校验。

MoonBit 使用 `InsertDiagram(DiagramSettings)` 计算布局，生成矩形、文字和带箭头的原生 `p:cxnSp` 直线连接线。连接线位于节点下方，端点引用原生连接点。形状、组及引用复用既有创建和子树复制的身份分配，保存为普通 `p:grpSp`，不创建原生 diagram 部件或模板元数据。插入后沿普通组/成员事务修改文字、格式、几何、复制及取消组合；连接点跟随目标变换，副本引用映射到副本节点。

默认面板提供三种模板及逐行标签，位置和大小使用现有对象输入，并说明保存为可编辑形状和连接线。一次插入一项历史，成功后选中新组。文字放不进节点、缺字体、身份耗尽、资源或输出预算失败时整项拒绝，保留源和选择，不消耗身份。画布、重开及 PDF 共用已有图元。原生 SmartArt 导入及更广模板兼容归 P14。

实现归 [`diagram.mbt`](../../modules/formats/src/pptx/diagram.mbt)、[`object-markup.mbt`](../../modules/formats/src/pptx/object-markup.mbt)及 [`pptx-diagram.tsx`](../../packages/ui/src/pptx-diagram.tsx)。模板布局是 SDK 的简化规则；底层对象参考 [ONLYOFFICE SmartArt 形状生成](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/SmartArts/SmartArtTree.js#L1838-L1864)，未复制其执行代码。连接点规则归[连接线](#连接线)。

### 对象超链接

`PresentationEditor.editObjects({ action: "hyperlink", link })` 修改所选本地顶层对象或其文字的点击链接。对象模式支持单个形状、图片或组；文字模式支持一个可编辑文本框或普通表格中的单个主格。`link` 为 `{ kind: "external", target }`、`{ kind: "slide", target }`、`{ kind: "action", target }` 或 null；null 移除点击链接。动作 target 接受 `firstslide`、`lastslide`、`nextslide`、`previousslide`、`lastslideviewed`、`endshow`；后两类仅在放映中执行。`PptxHyperlink` 从 `wasm/pptx` 和 `web/pptx` 导出。每个 `PptxObject.hyperlink` 返回对象链接的 `{ value, reason }`；`PptxQuery.textHyperlink` 返回当前文字范围的 `{ value, mixed, reason }`。链接不一致时 value 为 null 且 mixed 为 true，默认面板仍允许统一设置或移除。多对象与继承对象继续保护。

文字选区按 UTF-16 字素边界拆分 run，可跨样式、软换行及段落，只修改选中范围。链接内的光标修改当前段落中相邻且关系及提示等元数据一致的完整链接；不同提示或关系保持独立。普通光标通过空 run 或空段落末尾属性设置后续输入链接。原生输入继承链接，移除时同步对应段落末尾属性，避免清空后再次出现。保留直接字体、大小、粗斜体、颜色和源下划线；存在点击链接时派生单下划线，移除后恢复原直接定义。文字链接写入 `rPr/endParaRPr`，与对象的 `cNvPr` 链接独立；累计生成源限制为 2 Mi UTF-16 单元。

外部地址最多 2048 UTF-16 单元，只允许 HTTP、HTTPS 和 mailto，拒绝空目标、空白、控制字符及反斜杠。内部页目标使用当前文稿的稳定 slide 部件身份，不能使用页序号；允许显式跳转隐藏页。默认面板创建、修改及移除链接，单独的打开入口才导航。外链使用新窗口和 `noopener noreferrer`。`PresentationEditor.followHyperlink()` 及 Wasm/Worker 命令 `{ operation: "followPptxHyperlink", revision }` 从当前单个对象或一致的文字链接解析内部页/动作，再由核心定位；拒绝混合链接、外链、旧修订及活动候选。四种动作按当前编辑页序执行，包含隐藏页；上一页/下一页在边界停留并保留选择。重排、复制及删除页后按新位置解析，不保存过期页序号。导航不改源、revision 或历史；显示、打开文件和布局不自动请求外链或执行动作。`lastslideviewed/endshow` 可创建、修改和移除，编辑器中的 `followHyperlink()` 明确拒绝执行；默认面板提示在放映中使用。脚本、文件地址、相对网址、宏及其他未支持动作继续保护源。

核心写 `cNvPr/a:hlinkClick`：外链使用 External hyperlink 关系，内链使用 slide 关系及 `ppaction://hlinksldjump`。六种导航动作写 `ppaction://hlinkshowjump?jump=…` 和空 `r:id`，不创建关系；导入时按 action 解析，允许省略、空或原有关系身份。与目标相同的关系可复用；修改不覆盖其他对象共用的关系，也不清理旧关系。保留 tooltip、tgtFrame、history、highlightClick、endSnd、相邻悬停链接、注释、文字和几何；未知属性、声音等子内容或无法解析的关系保护修改。新增关系与对象 XML 共用一项有界历史，旧 revision、活动候选、锁和输出预算失败均不提交。相同链接及重复清除不新增历史。

页面重排保持内部目标，页面复制复用既有自身链接重映射，删页移除相应入链并保留对象。对象复制保留链接；带自身点击或悬停链接的组不能直接取消组合，避免丢失组动作。普通点击链接移除后可取消组合，成员自己的链接保留。静态 Canvas 保留对象外观及文字，PDF 链接归[下段](#pptx-pdf-链接)。放映点击归[放映链接](#放映链接)；悬停及其他一般动作编辑继续按 [P12](../p12-pptx-core.md) 实施。语义参考固定 [ONLYOFFICE 对象链接操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/CommonController.js#L3503-L3683)、[文字链接拆分与光标操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L7811-L8180)、[PPTX 链接下划线](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L10545-L10565)、[内部页动作解析](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L9259-L9290)及[编辑器显式导航](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/api.js#L7243-L7264)，实现归 [`object-hyperlink.mbt`](../../modules/formats/src/pptx/object-hyperlink.mbt)和 [`text-hyperlink.mbt`](../../modules/formats/src/pptx/text-hyperlink.mbt)。

表格文字链接在单个主格内使用相同的局部范围及光标规则，包含跨行列合并格和空格；范围先转换为格内位置，不改其他格及延续格。跨主格选择返回保护原因，统一设置和移除均不写入，默认面板同步禁用。新关系与单元格源仍合为一项历史；已有格式、几何及其他部件保持。放映使用表格原有逐格文字几何命中。规则依据 [ONLYOFFICE 表格链接操作](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L4601-L4630)。整表对象链接编辑仍受保护。

### PPTX 雷达图

`PptxChart.kind: "radar"` 使用现有插入、修改数据、占位符填入和查询入口。首列仍为类别，各数据列为系列；1–256 个类别、1–8 个系列及文字预算沿基础图表合同。原生配置为 `radarChart`、`radarStyle=marker`、`varyColors=0`、类别轴与数值轴、5 点圆形标记及 1.5 点系列线。原生缓存、引用、实际嵌入 XLSX、对象身份、独立复制和精确历史复用原图表路径。

类别从顶部开始顺时针等角排列。数值轴包含零并沿已有 1/2/5/10 刻度规则取界；半径为 `(值 − 下界) / (上界 − 下界)` 的投影。负值保持原数值；下界映射到中心，零按共同刻度定位。全零/全空使用 0–1。相邻非空点连接，首末点也视为相邻；空值在两侧断线，孤立点和零值保留标记。单类别只画标记，两类别只保留一条连接。核心先绘制系列线再绘制标记，类别、刻度和系列图例沿相同字体路径输出。径向比例先归一化再乘显示半径，避免有限大数产生无穷坐标。

当前框使用内接圆和有界标签区域；默认面板可改类型、标题及数据，Canvas、PNG 和静态 PDF 共用位置。只读取当前原生配置；填充雷达、其他标记、轴配置和组合继续诊断并保留源。实现归 [`chart-radar.mbt`](../../modules/layout/src/chart-radar.mbt)及既有图表读写模块。算法参考 [ONLYOFFICE 类别角度、径向坐标、空值及闭合](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L14406-L14563)、[半径和绘制层次](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Charts/ChartsDrawer.js#L14793-L14812)及[原生样式与数轴](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/ChartFormat.js#L6094-L6116)。未复制上游执行代码。

### PPTX PDF 链接

既有 PDF 导出保留对象和文字的 HTTP、HTTPS、mailto 外链，以及本次输出中可用的内部页目标。首页、末页、上一页、下一页动作按原生页序解析，再映射到实际输出页序；当前页、全部页及隐藏页选项保持原有规则。目标未输出时不生成注释。上次查看页、结束放映和媒体播放动作在静态 PDF 中不执行。

对象链接使用实际几何边界，零宽或零高直线补入线宽。文字和表格文字复用核心布局的可见字形区间，按文本框、单元格及纸张裁剪。旋转、翻转和组变换作用于矩形四角，再取轴对齐包围框；不声明多边形或遮挡命中。导出不改源、选区、历史和未保存状态，也不请求链接地址。未知或非法动作保护输出。

核心通过 `PositionedDocument.links` 复用[共享注释输出](#docx-pdf-文字链接)。每次最多 65536 个矩形、8388608 个文字几何工作单元，并继续执行现有打印和 PDF 字节预算。实现归 [`print-links.mbt`](../../modules/formats/src/pptx/print-links.mbt)，几何及动作语义参考 [ONLYOFFICE PDF 文字链接](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L2886-L2968)，未复制上游执行代码。

### 嵌入音视频

`PresentationEditor.editObjects({ action: "insertMedia", kind, contentType, bytes, poster, x, y, width, height })` 插入本地音频或视频。`kind` 为 audio/video，`bytes` 是媒体原字节，`poster` 是 PNG/JPEG 原字节，几何使用磅。同步 Wasm 与 Worker 复用 `editPptxObjects`，MoonBit 对应 `InsertMedia`。插入只作用于普通幻灯片；媒体、封面、内容类型、三条关系及对象选择合为一项精确历史。失败保持原包、历史与身份分配。核心检查容器签名，Web 还须成功解码首帧或音频数据，不能仅按扩展名接收。

对象沿原生 `p:pic` 保留封面几何与 `kind="image"`，另有 `PptxObject.media: PptxMedia | null`，普通对象为 null。媒体描述包含 `{ kind, key, contentType, poster, reason }`，从 Wasm/Web PPTX 模块导出类型。`mediaBytesPptx` 按 key 读取已声明的受支持内嵌资源；外链或冲突关系仅返回对象级原因，不下载或提供本地字节。支持已知 a:audioFile/a:videoFile 和 p14:media；未知扩展继续保护。普通对象/页面复制分配新绘图身份，复用不可变的媒体和封面；变换、删除、撤销重做及保存重开沿现有事务。删除保留资源，未引用但仍保留的媒体关系继续计入累计预算。

默认面板从显式本地文件解码生成视频首帧封面或音频播放符号。`preparePresentationMedia(bytes, signal?)` 从 `web/pptx` 导出，供宿主复用。容器声明为 audio/wav、audio/mpeg、audio/mp4、audio/webm、video/mp4 或 video/webm；浏览器拒绝编码或数据损坏时，插入失败并保留文稿。当前 Chromium 实测覆盖 PCM WAV 和 VP8 WebM，其余编码按实际解码能力处理，未据文件扩展名承诺兼容。解码帧每轴最多 4096、最多 16777216 像素；生成的封面最多 1920×1080，仍遵守图片输入/解码预算。取消、超时、失败和完成均清理临时解码器及对象 URL。

媒体原字节有独立的单资源 16 MiB、累计 64 MiB 和 64 项预算，历史另限 64 MiB。XML 与图片历史仍共用原来的 4 MiB；`historyBytes` 返回两类历史的合计。原包、XML、输出和显式宿主预算同时生效，可能先达到其上限。静态 Canvas、PNG/JPEG 和 PDF 使用封面，原媒体字节保留在 PPTX。手动及已支持的动画命令归[放映媒体](#放映媒体)和[对象动画](#对象动画)；循环、音量及静音归[媒体播放属性](#媒体播放属性)；更广原生媒体计时继续实施。原生结构参考 [ONLYOFFICE Pic::fromPPTY](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Pic.cpp#L1205-L1256)；未复制上游执行代码。

### 放映与演讲者视图

`PresentationEditor.slideshow.start("settings" | "first" | "current" | { show: id }, labels?)` 按已保存设置、从头、当前页或指定自定义放映开始。省略参数时使用 settings。默认页列表提供这些入口。`labels` 使用 `PresentationShowLabels`，从 `web/presentation-editor` 导出，默认 UI 随语言提供名称。`navigate(action, slide?)` 接受 `next/previous/first/last/goto/gotoPosition/click/tick/pause/resume/end`，`end()` 退出。goto 使用页身份并定位当前序列的首次出现；gotoPosition 使用从 0 开始的条目序号字符串，可以区分重复页。click 遵守单击换页设置，next 保持显式导航；tick 根据时间推进自动换页。`active` 包含开始中的状态，`state` 返回当前快照，未放映时为 undefined；`paused` 表示切换及自动换页计时暂停。Wasm/Web PPTX 模块导出 `PptxQuery/PptxShowAction/PptxShowState/PptxShowLayout`。

核心保留编辑页及文字/对象选择，以已提交 revision 管理独立播放位置。普通及自定义导航均跳过隐藏页；当前页开始与显式跳页可到达隐藏页。普通 goto 在自定义放映中限于该序列；源链接的跨序列规则归[放映链接](#放映链接)。没有可见页时开始拒绝。切换尚未结束时，next 先完成当前切换；再次前进才换页或退出末页。后退直接显示目标条目，条目改变后重置入场、动画与计时，包括连续重复同一页。首屏从黑底进入。`index/count` 表示源页序和源页总数，包含隐藏页；`order` 为播放条目的页身份数组，`position` 为当前条目序号，`custom` 为自定义放映 ID 或 null。条目与计数保留隐藏页，默认导航跳过它们。`nextSlide` 是序列中的下一可见页或 null。结束状态的 order 为空、position 为 −1、custom 为 null。候选须先完成或取消；放映期间核心拒绝文档、选择和历史修改。保存及静态输出读取已提交的编辑布局，不改变播放位置或源内容。

低层 controlShowPptx 携带 revision、action、slide 和必需的 time；start 可额外提供 custom ID，此时 slide 为空。startSettings 使用文稿默认选择，不接受 slide 或 custom。layoutShowPptx 携带 revision/profile/time，返回一至两个 R0 页面及 animating。time 为 0–1000000000 的有限单调毫秒，倒退请求拒绝且保留状态。核心扣除暂停间隔后计算进度，不调用宿主时钟。Web 每帧先用 tick 更新播放位置，再准备相邻资源和布局；animating 在切换或等待自动换页时为 true。每次最多处理一项帧工作，忙时只保留最新时间。核心缓存包含播放序列与条目位置，重复页也会更新下一页预览；每帧只重组位置及透明度。结束放映清除播放缓存。imageKeysShowPptx 返回当前、切换前及下一页资源；资源池同时保留编辑页，继续受 256 个键和 16 MiB 解码上限约束。

模态视图位于所属编辑器内，容器全屏兼容 Shadow DOM。支持方向键、PageUp/PageDown、Home/End、页面点击、显式条目跳转和 Escape；原生选择及颜色控件保留自身按键。演讲者开关显示下一页与普通备注；演讲已用时间继续累计，pause/resume 冻结/继续切换及自动换页计时。退出恢复原生焦点和选择；文件替换、宿主 setPaused(true) 和释放结束放映，清理画布、帧请求、监听器和计时器。对象与文字点击链接已有核心命中和键盘入口，范围归[放映链接](#放映链接)。临时画笔及手动媒体归下文；独立窗口仍待实现，源元数据保留。

页序规则参考 [ONLYOFFICE 可见页导航](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/Transitions.js#L4641-L4742)和[显式跳页](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/Transitions.js#L4978-L5003)。实现归 [`slideshow.mbt`](../../modules/formats/src/pptx/slideshow.mbt)、[`show-state.mbt`](../../modules/formats/src/pptx/show-state.mbt)及 [`presentation-show.ts`](../../packages/web/src/presentation-show.ts)。

### 媒体播放属性

`PresentationEditor.editObjects({ action: "mediaPlayback", value: { loop, volume, mute } })` 修改单个本地顶层音视频对象。`loop/mute` 为布尔值；`volume` 为 0–100000 的整数，沿用原生音量单位，100000 表示 100%。默认值为 false/100000/false。Wasm/Web 导出 `PptxMediaPlayback`，MoonBit 使用 `MediaPlaybackSettings`，其中循环字段名为 `cycling`。`query.mediaPlayback` 返回当前对象的 `{ value, reason }`，普通对象的 value 为 null；默认媒体面板提供循环、百分比音量、静音及一次应用。多个字段合为一项精确历史，无变化不提交；原生草稿仍先沿既有屏障提交。

属性保存为原生动画根节点下的 `p:audio/p:video`、`cMediaNode.vol/mute` 及 `cTn.repeatCount="indefinite"`。保留单页封面，等待媒体动作启动，并在页导航时停止。仅有播放属性而没有主动画序列的源也可读取；新建媒体动画同时补齐其原生媒体节点，动画列表修改和清空保留播放属性。对象和页面复制重映射目标及时间身份，复制对象独立修改设置，共享不可变媒体字节。仅有播放属性引用时，删除对象同时回收该节点；其他动画及连接引用继续保护。

`slideshow.state.media[].playback` 返回实际使用的属性。浏览器将循环、音量比例和静音传给已有解码器，保留实例 token、暂停、停止、故障及释放规则。循环不重复分配播放器，也不推进页面；停止恢复封面并释放资源。放映不修改文稿和历史，静态 Canvas/PDF 仍使用封面。Chromium 已检查 PCM WAV 的多次实际回卷、精确音量比例及静音属性；未据此声明实际扬声器音量验收。

当前读取普通单页、保留封面、无限循环或单次播放的媒体节点。有限重复、自动开始的独立媒体节点、跨页延续、全屏、叙述、隐藏封面及未知节点/属性继续保护；自动播放使用已支持的媒体动画命令。无关普通对象的复制/删除保留未知媒体源。原生字段依据 [ONLYOFFICE CMediaNode](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Timing/CMediaNode.cpp#L42-L68)和 [CTn](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Timing/CTn.cpp#L42-L103)；未复制执行代码。实现归 [`media-playback.mbt`](../../modules/formats/src/pptx/media-playback.mbt)。

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

每笔最多 4096 点，整次放映最多 256 笔、32768 点；正在输入的草稿计入点数检查。每批最多 64 点，宽度为 0.5–24 pt，坐标须为页内有限值。Web 待发送样本最多 4096 点，超限取消当前草稿并显示错误，已完成笔迹保留。橡皮擦、激光笔、曲线平滑及压感继续实施。

实现归 [`show-ink.mbt`](../../modules/formats/src/pptx/show-ink.mbt)、[`show-ink-save.mbt`](../../modules/formats/src/pptx/show-ink-save.mbt)、[`polyline.mbt`](../../modules/formats/src/pptx/polyline.mbt)及 [`presentation-show-ink.ts`](../../packages/web/src/presentation-show-ink.ts)。开放无填充路径和边界参考 [ONLYOFFICE PolyLine](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/TrackObjects/PolyLine.js#L180-L262)，当前保留采样折线，不引入曲线拟合。临时页级笔迹、取消和显式写入源的分离参考 [ONLYOFFICE SlideShowAnnotations](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/SlideShowAnnotations.js#L53-L193)。未复制上游执行代码。

### 放映链接

`PresentationEditor.slideshow.click(x, y)` 激活当前已显示帧上的位置；坐标为页面 pt，不是 CSS 像素。默认 Canvas 将点击转换为该坐标。核心按当前形状轮廓、组成员和实际文字字符区域命中；文字链接优先于对象链接，成员无链接时使用最近的组链接。无链接的前景对象阻挡后方链接。动画中的平移、缩放、旋转共用绘制矩阵；动画隐藏项不参与命中。未命中链接时保留原单击动画/换页规则。页面切换期间先完成入场，不激活链接。

`slideshow.followLink(id)` 使用当前放映布局返回的链接 ID，供键盘及自定义宿主使用。`PptxShowLayout.links` 为 `{ id, label, reason, external }[]`；id 是核心分配的十进制字符串，只在当前布局有效。label 使用对象名称或文字，reason 非空时显示诊断并禁用执行；external 为已校验的外部地址或 null。默认视图给内部链接提供按钮，给外部地址提供带 `noopener noreferrer` 的新窗口链接，动画隐藏项不显示。列表更新保持仍存在项的键盘焦点。

内部页链接可明确到达隐藏页，在当前序列中定位目标的第一次出现。若目标不在当前范围或自定义序列内，核心转入完整文稿页序并清除 custom，再从目标继续；此规则是当前 SDK 合同，不声称已由上游自定义放映运行结果验证。首页/末页/上一页/下一页按活动放映序列执行，默认跳过隐藏条目；起点后退停留，末尾前进退出或按循环开关返回。导航重置目标入场和计时，保留编辑选择及源历史。

`lastslideviewed` 返回上一个播放条目。核心只保留该条目的序列、位置和自定义组身份，不保留完整访问栈；普通导航、链接跳转和自动换页在进入新场景时更新。返回时恢复重复条目的准确位置，以及跳出自定义/范围序列前的播放顺序；连续激活在最近两个条目间往返。暂停、布局帧和外部链接不改此记录。首次开始没有记录时停留；结束或重新开始清除记录。目标入场、对象动画和计时按普通跳页重新开始。`endshow` 直接结束当前放映，清除播放缓存；默认视图沿现有退出路径关闭并恢复原生焦点、编辑选择和已提交源。这些播放细则是当前 SDK 合同；未声明已独立运行上游放映验证。标准动作序列化依据 [ONLYOFFICE ShapeWriter](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/MsBinaryFile/PptFile/PPTXWriter/ShapeWriter.cpp#L1692-L1728)。

低层 controlShowPptx 的 click 可携带完整的 layoutId/x/y；followLink 携带 layoutId，slide 使用链接 ID。缺字段、旧 revision、其他场景及过期布局拒绝且不改变状态。同场景保留当前和上一帧，用于处理帧刷新与点击的交错；控制操作及换页会失效旧交互。外链不由核心请求：本次显式激活的 `PptxShowState.external` 返回地址，其他状态为 null。Web 通过新窗口执行，浏览器阻止弹窗时仍可使用列表中的显式链接。HTTP/HTTPS/mailto 的地址校验复用编辑链接边界，打开文件、布局和播放帧不会自动请求地址。

每帧最多 4096 个链接，ID 上限 4095；标签最多 1024、诊断最多 8192 个 UTF-16 单元，标签/诊断/外链总量最多 1 Mi 单元。宏、文件地址、未知动作及扩展链接保持源并显示诊断，点击拒绝执行。已知链接在只读对象和文稿中仍可播放。静态 PDF/图片不增加交互链接注释；自定义放映动作、悬停与其他动作继续实施。

命中后优先处理链接、未命中再换页的依据是 [ONLYOFFICE 放映点击路径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/Transitions.js#L5357-L5445)；动作与外部宿主分派参考[链接回调](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/api.js#L7243-L7283)。实现归 [`show-links.mbt`](../../modules/formats/src/pptx/show-links.mbt)、[`show-animation.mbt`](../../modules/formats/src/pptx/show-animation.mbt)和 [`presentation-show.ts`](../../packages/web/src/presentation-show.ts)。

### 放映设置

`PresentationEditor.editSlides({ action: "showSettings", value })` 修改整份文稿的默认放映。value 类型为 `NonNullable<PptxQuery["showSettings"]["value"]>`，包含 slides、timings、animations 和 loop。slides 接受 `{ kind: "all" }`、`{ kind: "range", first, last }` 或 `{ kind: "custom", id }`。范围是从 1 开始的闭区间，必须满足 first ≤ last ≤ 页数。custom 使用已有自定义放映 ID。查询返回 value/reason；未知选择、重复范围或无法解释的属性保护修改及按设置开始，源内容保持。

缺省为全部页、启用计时和对象动画、关闭循环。timings=false 禁用自动换页，保留每页设置及手动导航；animations=false 直接显示完整对象，不执行对象动画，页面切换仍保留。loop=true 在向前到达末条目后回到首个可见条目，单页也重置场景；后退仍在起点停留。循环沿用暂停、相邻页缓存及隐藏页规则，零时长循环每次 tick 最多推进一个序列长度。显式 first/current/custom 入口覆盖默认范围，仍使用三个全稿开关。

默认 UI 提供全部页、页码范围或自定义放映，以及计时、对象动画和循环开关。应用后合为一次历史；开始读取已提交值。页重排、增加和复制保持范围的数字位置；删页后把超出末页的起止值收窄到剩余页数。自定义组仍使用稳定页身份；被默认选择的组须先取消选择才能删除。

源采用标准 `presProps/p:showPr` 的 `sldAll/sldRg/custShow` 和 useTimings/showAnimation/loop。首次编辑可创建属性部件、关系及内容类型，连同源历史一起撤销和重做；相同设置不改字节或新增历史。只修改变化的属性和选择片段，保留 showNarration、显示模式、画笔颜色和其他未改源内容。叙述、窗口模式、默认画笔颜色及更广媒体计时仍待实现。媒体命令和临时画笔归各自合同；保存与静态输出继续使用完整文稿，不按默认放映范围裁剪。

字段和序列化依据 [ONLYOFFICE ShowPr](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/ShowPr/PresentationPr.cpp#L48-L128)及[页码范围](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/ShowPr/SldRg.cpp#L42-L78)。重排与删页的数字范围规则是当前 SDK 合同，未声称由上游运行结果验证。实现归 [`show-settings.mbt`](../../modules/formats/src/pptx/show-settings.mbt)、[`show-settings-create.mbt`](../../modules/formats/src/pptx/show-settings-create.mbt)和 [`pptx-show-settings.tsx`](../../packages/ui/src/pptx-show-settings.tsx)；沿用现有编辑队列及播放状态。

### 自定义放映

`PresentationEditor.editSlides({ action: "customShows", value })` 替换整份文稿的自定义放映列表，类型可用 `PptxQuery["customShows"]["items"]`。每项为 `{ id, name, slides }`；新建时 id 为空，由核心分配 uint32 的十进制字符串，现有项保留 ID。name 为 1–255 个有效 XML 文本单元，名称忽略大小写后唯一。slides 使用稳定页身份，可重复并保留顺序。每份文稿最多 32 组，每组最多 256 个条目，合计最多 4096 个。空组可以保留，但不能开始；`query.customShows` 返回 items/reason。

默认面板支持创建、命名、复制、删除、添加/移除条目、前后调整条目及显式开始。草稿经“保存自定义放映”提交，开始使用已提交的定义。修改受保护时仍可选择和播放已知定义。每次应用为一项精确历史；相同列表不新增历史。页移动和复制保持已有定义，复制页不会自动加入；删除页会移除其全部重复引用，允许组变为空。已有放映设置引用的组不能删除；存在未支持的自定义放映超链接动作时也保护删除，防止留下失效目标。重命名保持 ID 与引用。

源写入标准 `p:custShowLst/p:custShow[@name,@id]/p:sldLst/p:sld[@r:id]`，复用 presentation 的 slide 关系。未修改的定义保留源片段，读写、历史和预算沿用既有事务。扩展定义、未知属性、注释、失效关系及重复身份保护修改和自定义开始，普通放映仍可运行。默认放映选择已接通读取、编辑和播放，范围归[放映设置](#放映设置)；自定义动作链接继续实施。

已核对 [ONLYOFFICE 的自定义放映模型与序列化](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Presentation/PresentationChildElements.cpp#L411-L531)，该快照的名称/身份和列表输出不完整；标准结构依据 [Open XML SDK 的 CustomShow、SlideList 与 SlideListEntry](https://github.com/dotnet/Open-XML-SDK/blob/431ab05cf160248cc3885a4a766026d4f8243792/generated/DocumentFormat.OpenXml/DocumentFormat.OpenXml.Generator/DocumentFormat.OpenXml.Generator.OpenXmlGenerator/schemas_openxmlformats_org_presentationml_2006_main.g.cs#L12165-L12319)。隐藏页规则参考 [LibreOffice 自定义放映](https://books.libreoffice.org/en/IG70/IG7009-SlideShowsPhotoAlbums.html)。实现归 [`custom-shows.mbt`](../../modules/formats/src/pptx/custom-shows.mbt)与 [`pptx-show.tsx`](../../packages/ui/src/pptx-show.tsx)。

### 页面切换

`PresentationEditor.editSlides({ action: "transition", value }, slide?)` 设置目标页切换；null 移除本地切换效果，保留换页设置。`PptxTransition` 为 `{ kind, duration, direction }`，从 Wasm/Web PPTX 模块导出。kind 接受 none/fade/push。fade/push 的 duration 为 100–60000 的整数毫秒，none 只接受 0。push 的 direction 接受 left/right/up/down，表示页面移动方向；其他类型固定为 left。默认面板提供种类、时长、方向、应用与移除。`query.transition` 返回 value/advance/reason。

标准 transition 的 cut/fade/push 及 p14:dur 已接通读写；缺少 dur 时，spd 的 fast/med/slow 分别取 500/750/1000 毫秒。读取不改源，相同设置不新增历史。修改保留页、选择、其他 XML 与资源，共用一次精确历史。声音、经黑场淡入和未知效果继续保护。未知源和非法参数不提交部分结果。播放采用整页隔离透明度或两页平移，保存/PDF 保持静态源布局。

`editSlides({ action: "advance", value }, slide?)` 设置换页。Wasm/Web 导出的 `PptxAdvance` 为 `{ click: boolean, after: number | null }`，查询位于 `query.transition.advance`。after 为 0–3600000 的整数毫秒，null 关闭自动换页。默认值为允许单击且不自动换页。默认面板分别应用效果和换页设置，每次应用各为一项历史；改变效果保留换页，改变换页保留效果。源采用 advClick/advTm，只有换页属性的 transition 也支持读取、保存与重开。

自动等待从入场结束后开始；单击提前结束入场时从该时刻开始。暂停保留剩余时间。迟到帧按源页序有界追赶，跳过隐藏页，到末页退出；源、编辑选择和历史保持。presProps 中 showPr/useTimings=false 禁用自动换页，保留页设置和显式导航；整稿开关通过[放映设置](#放映设置)编辑。规则参考 [ONLYOFFICE 入场后计时](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/Transitions.js#L4486-L4504)、[单击设置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/Transitions.js#L5418-L5445)及[整稿计时开关](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L2115-L2134)，实现归 [`slide-advance.mbt`](../../modules/formats/src/pptx/slide-advance.mbt)。

方向与速度参考 [ONLYOFFICE 源方向映射](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/apiCommon.js#L429-L450)、[速度缺省](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/Serialize.js#L4440-L4467)和[整页合成](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Drawing/Transitions.js#L442-L770)。未复制上游源码。实现归 [`slide-transition.mbt`](../../modules/formats/src/pptx/slide-transition.mbt)和 [`pptx-transition.tsx`](../../packages/ui/src/pptx-transition.tsx)。

### 对象动画

媒体命令 `mediaPlay/mediaPause/mediaStop` 仅接受具有可用本地资源及封面的顶层音视频对象，`params=[]`。默认动画面板共用目标、触发、延迟、顺序、修改和删除控件，固定命令时长及次数。源使用 `presetClass="mediacall"` 与 `p:cmd type="call"`；播放写 `playFrom(0.0)`，暂停写 `pause`，停止写 `stop`。播放命令从头建立新实例；手动媒体面板的暂停续播仍保留播放位置。`after` 等待命令本身的 1 毫秒及延迟，不等待媒体解码结束；结束反馈仍只更新播放器。读取按命令字符串解释行为，书签/裁切起点、扩展命令和重复继续保护。

核心按调度时间、同时间的源顺序执行命令，每页场景中的每项只执行一次。首项为 with/after 时，在入场完成及延迟后自动执行；暂停冻结逻辑时间，手动完成组同时执行该组尚未到时的命令。布局跨过触发时间后继续请求 tick，直到动作状态已发布；视频解码及逐帧绘制沿既有媒体宿主。新实例分配独立 token，旧反馈不能终止新播放；回到页面重置步骤和实例，源、选择、历史与静态输出保持。超出 16 个保留播放器时只报告到超限对象，其他实例及页面继续操作；浏览器拒绝自动播放时仍有手动重试入口。命令与平台边界依据 [ONLYOFFICE CCmd](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L8714-L8732)，未复制执行代码；实现归 [`animation-media.mbt`](../../modules/formats/src/pptx/animation-media.mbt)。

`PresentationEditor.editSlides({ action: "animations", value }, slide?)` 替换目标页的有序动画。value 是最多 128 项的 `PptxAnimation[]`，每项完整提供 `{ object, kind, trigger, delay, duration, repeat, params }`。类型从 Wasm/Web PPTX 模块导出。object 使用稳定对象 ID，目标限于本地顶层形状、文本框与图片。kind 接受 appear/disappear/fadeIn/fadeOut/scale/rotate/move/flyIn/flyOut/mediaPlay/mediaPause/mediaStop；trigger 接受 click/with/after。delay 为 0–60000 的整数毫秒。除出现/消失与媒体命令外，duration 为 100–60000 的整数毫秒，repeat 为 1–100 的整数；出现/消失与媒体命令固定为 duration=1、repeat=1。`query.animations` 返回 items/reason。

params 为数值数组。出现/消失和淡入淡出使用空数组；scale 使用 `[水平百分比, 垂直百分比]`，每轴为 1–1000 的整数；rotate 使用 `[旋转度数]`，为 −3600–3600 的整数；move 使用 `[水平距离, 垂直距离]`，单位为点，每轴为 −14400–14400 的整数。水平向右、垂直向下、顺时针旋转为正。缩放和旋转围绕源对象中心，直线路径在页面坐标中位移。三种变换分别保留各自终态，可以同时作用于同一对象；同一属性的重叠时间段仍受保护。

flyIn/flyOut 使用 `[方向]`，表示飞入的起侧或飞出的终侧：1 上、2 右、3 右上、4 下、6 右下、8 左、9 左上、12 左下。核心按页面边界、源对象中心和几何外接矩形计算位置，保留源旋转与翻转。飞入从页外回到源位置；飞出从已有位移到页外，不变的轴保留已有位置。飞入开始时显示，飞出在每个周期最后一毫秒隐藏。飞行同时占用位移和可见性，与同一对象这两类属性的时间重叠受保护。

默认面板提供目标、效果、触发、延迟、时长、重复及所选效果的缩放、角度、位移或飞行方向，以及新增、修改、前后移动和移除。每次应用为一项精确历史，保留对象源、选择和其他部件；相同列表不新增历史，空列表清空已支持的动画。未知内容和无效参数保持源与历史。

click 开始一组；with 与当前组共享起点，各自保留延迟；after 等待当前组最长的效果（含延迟与重复）结束。首项为 with/after 时，从页面入场完成后自动开始。重复按周期重新执行，末次完成后保持终态。目标的首项可见性效果为进入时初始隐藏，为退出时初始可见；几何动画保留该可见性。未结束的页面切换先消耗一次 next/click；之后可完成运行中的组，或触发下一点击组，全部完成后才换页。禁止单击换页仍允许触发动画。暂停冻结逻辑时间；手动完成组不会使后续组跳到过期时间。`PptxShowState.step/steps` 表示已调度和总效果数，结束时均为 0。

源采用标准主序列、clickEffect/withEffect/afterEffect、stCondLst 和 repeatCount。出现/消失使用 style.visibility 的 set；淡入淡出使用 style.opacity 的线性 anim，按 ONLYOFFICE 的透明度解释读写。缩放使用 emph/6 与 animScale/by，旋转使用 emph/8 与 animRot/by；位移写为 path/0 的 animMotion，origin=layout，路径坐标按页面宽高归一化。读取接受上述几何参数及从 `M 0 0` 到单个 `L x y E` 的直线；同样接受直线预设 35/42/49/56/63/64。读取校验组间延迟、时间 ID、开始条件、目标、完整次数及属性范围，接受独立前缀和时间 ID。常见 animEffect/filter 形式尚未读取，不据此宣称完整淡入淡出兼容。

飞入/飞出使用 entr/exit 的 presetID=2 和上述方向 subtype。两轴各有一个线性数值 anim，tavLst 的时间点为 0 与 100000，属性为 ppt_x/ppt_y。飞入采用 `#ppt_x/#ppt_y` 和 `0-#ppt_w/2`、`1+#ppt_w/2` 等源坐标公式；飞出采用相应不带 `#` 的已有属性公式。可见性 set 在入场 0 毫秒或出场 duration−1 毫秒触发。读取只接受这些固定公式和时点，拒绝任意表达式、额外轴、混合目标和扩展关键帧。

核心缓存完整对象图元，每帧只按逻辑时间合成既有 R0 矩阵和透明层；文字与形状重叠时整体应用一次透明度。页面裁剪保持在变换外，源对象的旋转、翻转、文字和图片裁剪继续保留。可见性与透明度分别保留，已消失对象不会被几何动画或后续退出透明度重新显示。页面切换保留离场时的透明度和变换；回退或跳转至其他页时从目标页初始状态开始。下一页预览保持静态源。自动换页等待所有动画及点击组完成，之后保留下一页自己的计时。保存、PDF 与图片输出使用完整静态源。

当前读取范围为无构建列表的单主序列。缩放/旋转/路径接受不带 attrNameLst 的上述 by 或路径形式，参数精度按上述整数单位限制。分组或段落子目标、同一属性的时间重叠、曲线、交互触发、无限/分数重复及其他未知 timing 继续保护。查询给出原因，修改和开始播放时拒绝，保持源内容；不会把未知动画当作已播放。带 timing 引用的对象仍受原有删除/组合保护，可先移除其已支持的动画。页复制沿用现有目标 ID 重映射。

语义参考 [ONLYOFFICE 点击组](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L9112-L9167)、[可见性行为](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L9931-L9953)及[初始隐藏对象](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L12121-L12155)。未复制上游源码。实现归 [`animation-read.mbt`](../../modules/formats/src/pptx/animation-read.mbt)、[`animation-edit.mbt`](../../modules/formats/src/pptx/animation-edit.mbt)、[`show-animation.mbt`](../../modules/formats/src/pptx/show-animation.mbt)和 [`pptx-animations.tsx`](../../packages/ui/src/pptx-animations.tsx)。

计时与透明度参考 [ONLYOFFICE 组间延迟](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L9086-L9110)、[属性合成](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L12860-L12940)和[透明度绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L12950-L12970)。XML 定义参考 Microsoft 的[开始条件](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.presentation.condition)与[动画属性名](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.presentation.attributename)。实现归 [`animation-timing.mbt`](../../modules/formats/src/pptx/animation-timing.mbt)与 [`animation-xml.mbt`](../../modules/formats/src/pptx/animation-xml.mbt)。

几何语义参考 ONLYOFFICE 的[相对路径](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L7735-L7791)、[旋转](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L8209-L8238)、[缩放](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L8380-L8417)和[中心变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L13023-L13071)。实现归 [`animation-geometry.mbt`](../../modules/formats/src/pptx/animation-geometry.mbt)。

飞行公式参考 ONLYOFFICE 的[源坐标](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L1486-L1509)、[关键帧求值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L4530-L4628)及[进入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L14468-L14478)/[退出预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Timing.js#L14631-L14641)。实现归 [`animation-flight.mbt`](../../modules/formats/src/pptx/animation-flight.mbt)。

### 当前页 PNG 输出

`PresentationEditor.exportPng(scale = 1, outputBytes = 67108864)` 返回 `EditorOutput`，`format` 为 `png`。它按现有输入队列导出当前已提交页面，包括明确显示的隐藏页。活动输入/变换候选先完成或取消；布局缺失或与当前页/修订不符时拒绝。选择、源文档、历史、预览尺寸和保存基线保持；导出失败保留编辑与原格式保存入口。

`scale` 为每 pt 的像素数，接受 0.25–4；图片宽高分别为 `ceil(width * scale)` 和 `ceil(height * scale)`，默认 960×540 pt 文稿生成 960×540 px PNG。预览 zoom 和屏幕 DPR 不决定导出尺寸。编码前要求临时图片与现有页面/覆盖层 Canvas 合计不超过 16,777,216 像素；`outputBytes` 为 1–67,108,864 的整数，在复制编码字节前检查 Blob 大小。所有路径释放临时 Canvas；复用的图片和字形路径继续由当前表面持有。

默认文件菜单的“当前页 PNG”使用相同 API。`onSave` 收到 `format: "png"` 及 `.png` 名称的派生输出；没有回调时按 `image/png` 下载。PNG 输出不能 `markSaved`，也不清除 PPTX 未保存状态。它通过当前 R0 执行器重放核心图元，保留已有诊断的显示结果；图片、裁剪、旋转与文字沿现有渲染范围，选择框和光标只在编辑覆盖层中。

`PresentationEditor.exportPageImages(scale = 1, outputBytes = 67108864, hidden = false, format = "png")` 返回全部可见页的只读 `EditorOutput[]`，按文稿顺序排列；hidden=true 包含隐藏页。format 接受 `"png" | "jpeg"`，默认 PNG。结果共享文档身份与 revision，所有图片的字节数之和受 outputBytes 限制。没有选中页面时拒绝。当前页、选区、编辑布局身份、预览和历史保持；后续输入沿同一队列等待集合生成。全部页面成功后才登记并返回输出，失败不交付前缀集合，也不覆盖此前输出记录。

核心 `Session.print_drawing` / Wasm 与 Worker `printLayoutPptx` 复用 `print_layout` 的页面选择、诊断、图元预算和 PDF 几何，返回 `PptxPrintLayout { revision, regions, outlines, images }`。请求携带 revision、all、hidden 和 profile，不改变当前编辑页的布局缓存。批量 PNG 沿完整打印范围保护未知可见内容；单页 PNG 继续保留已有诊断的显示结果。Web 在输出期间准备所选页面图片，逐页编码并释放临时 Canvas，最后恢复当前编辑页的图片集合。

默认文件菜单的“全部幻灯片 PNG”导出全部可见页，复用既有逐页保存/下载流程。名称按 `<原文件基名>-01.png`、`-02.png` 顺序补零，序号只计算导出的页面。所有图片生成后才依次调用 `onSave`；中途失败保留已完成的外部保存及进度，停止后续回调，重试按当前修订重新生成。回调期间继续编辑不会改变已生成图片的 revision。没有 `onSave` 时逐页下载并报告生成进度；多个下载仍受 Chrome 站点权限约束。派生输出不清除 PPTX 修改状态。

上述入口依赖浏览器 Canvas 绘制和编码，当前只检查 Chrome/Chromium；不作为无浏览器图片转换能力。普通 Wasm/Worker 文档状态、布局和 PDF 接口保持原职责。打印入口归[浏览器打印](#浏览器打印)。

#### JPEG 输出

`PresentationEditor.exportJpeg(scale = 1, outputBytes = 67108864)` 导出当前页，`exportPageImages(scale, outputBytes, hidden, "jpeg")` 导出页面集合。返回输出的 `format` 为 `jpeg`。两者复用上述布局、页面选择、尺寸、像素/总字节预算、队列、源与历史保护及失败恢复。单页保留已有诊断的显示结果，集合沿打印范围保护未知可见内容。

JPEG 使用白色底图和固定 `0.92` 编码质量，属于有损输出，不保留透明通道。平台检查编码 Blob 的实际 MIME；编码失败或浏览器回退其他格式时拒绝交付。默认文件菜单提供“当前页 JPEG”和“全部幻灯片 JPEG”；回调收到 `.jpg` 或按页补零的 `-01.jpg` 名称，没有回调时按 `image/jpeg` 下载。逐页保存失败保留已完成进度，重试按当前修订重新生成；JPEG 输出不能确认原格式保存。实现归 [`canvas-surface.ts`](../../packages/web/src/canvas-surface.ts)及 [`presentation-output.ts`](../../packages/web/src/presentation-output.ts)。

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

`PptxQuery.firstSlideNumber` 返回当前起始编号。`PresentationEditor.editSlides({ action: "firstSlideNumber", number })` 及同步 Wasm/Worker 的同名修改作用于整稿；number 必须为 0–4294967295 的整数。默认编号面板提供起点及应用按钮，原生文字草稿先独立提交，编号草稿在此期间保持；撤销/重做按源起点更新控件。相同起点不新增历史。只修改演示文稿属性，保留字段 ID、源代码和旧缓存，重新派生全部页的编号；末页显示值可超过起点属性的上限。

受影响字段共用已有文字测量和自动适配，框大小或缩小比例与起点合为一项历史。预检包含隐藏页和继承对象。固定框溢出、未知编号域、修改保护、缺字体、旧修订、活动候选及预算失败原子拒绝。共享自动框需要不同源尺寸时继续保护，待本地覆盖支持后扩展。其他源、资源和选择保持；Canvas、PDF 与保存重开使用相同编号。起点语义参考 [ONLYOFFICE changeSlideSize/getFirstSlideNumber](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L844-L863)，实现归 [`slide-numbering.mbt`](../../modules/formats/src/pptx/slide-numbering.mbt)及 [`autofit.mbt`](../../modules/formats/src/pptx/autofit.mbt)。

当前支持带非空 `id`、可选 `rPr/t` 且无其他字段属性或子节点的形式。字号、颜色和字体沿现有文字解析；派生数字进入查询及 Canvas/PDF 共用的定位输出。重排、复制、删除与撤销重做同步更新，读取和保存不刷新源缓存，也不新增修订。字段所在框继续拒绝纯文字编辑，其他字段和带段落属性/未知扩展的字段保留缓存并诊断。创建和移除见[日期与页脚编辑](#日期与页脚编辑)，版式占位符创建沿[幻灯片版式](#幻灯片版式)；母版直接编辑继续实施。实现归 [`text-fields.mbt`](../../modules/formats/src/pptx/text-fields.mbt)。

### PPTX 普通表格

`PresentationEditor.editObjects({ action: "insertTable", rows, columns, x, y, width, height })` 和同步 Wasm/Worker 的 `editPptxObjects` 创建普通空表格。位置与尺寸单位为点，沿用对象的有限值及 14400 点上限；行列数必须为整数。网格按整数 EMU 等分，总宽与外框精确一致；每列须保留默认左右内边距外的正文字宽度。初始文字为 Arial 18 点、黑色，单元格为白底及 1 点黑色实线边框。行高不足时按现有字体排版增长，所有生成内容合为一项历史。默认 UI 共用对象的位置和尺寸输入，单独提供行列数。身份分配避开原对象及会话已使用身份，失败不占用身份。

对象模式的现有 `delete` 命令可删除整张普通表格，清除选择，并支持精确撤销重做。锁定、引用和输出预算继续由原对象事务校验；有动画或连接引用时受保护。结构依据 [ONLYOFFICE 表格创建](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L4122-L4176)，单元格属性顺序沿 [TableCellProperties 序列化](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Table/TableCellProperties.cpp#L145-L171)。实现归 [`table-create.mbt`](../../modules/formats/src/pptx/table-create.mbt)。

表格复用现有对象移动/缩放候选、`duplicate`、层次及对齐/分布命令，支持与形状混合多选；默认指针和移动/缩放控件使用同一路径。列宽、行高按原比例分配到整数 EMU，合计与新外框精确一致。预览同步派生网格，取消恢复原源；提交按文字需要增长行高及外框，并合为一项精确历史。字号、边距、单元格片段及跨度保持。宽度不能耗尽主格的文字区域，移动/缩放锁继续生效。复制分配新对象身份，保留原表及资源，副本单元格可独立编辑。`rotateReason` 及默认控件继续保护直接旋转和翻转；导入及取消组合产生的原生框姿态保留。行为参考 [ONLYOFFICE GraphicFrame.resize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicFrame.js#L599-L621)和 [Table.Resize](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L18121-L18336)，网格写回归 [`table-transform.mbt`](../../modules/formats/src/pptx/table-transform.mbt)。

`editObjects({ action: "tableStructure", operation })` 修改表格结构。`operation` 接受 `insertRowBefore`、`insertRowAfter`、`deleteRow`、`insertColumnBefore`、`insertColumnAfter`、`deleteColumn`、`merge`、`unmerge`。`PptxQuery.table` 返回 `{ object, rows, columns, row, column, firstRow, lastRow, firstColumn, lastColumn, rowHeight, columnWidth, reason, sizeReason, operations, splitReason, format, style }`，行列下标从零开始，范围两端均包含；没有单选普通表格时返回 `null`。`operations` 为上述八项操作各自的保护原因，空串表示可用。对象模式的结构操作从首格开始；文字模式的选择两端跨格时，核心将两端单元格作为矩形的对角，扩展到包含相交合并格的完整范围。当前光标仍使用既有 UTF-16 位置，反向选择不改变范围。默认面板直接使用核心返回的位置、范围和原因，鼠标点击结构按钮保留原生输入焦点。

`editObjects({ action: "tableRowHeight" | "tableColumnWidth", value })` 修改上述范围覆盖的全部实际行或列。`value` 为 0.1–14400 点的有限数值，四舍五入到整数 EMU；不按合并格总宽平均分配。对象模式只从首格及其跨度开始，整表尺寸仍使用对象缩放。其他列宽保持，所有格的文字、格式、跨度及其他部件保持；总宽高同步外框，左上角不动。行高仍是内容适配前的目标，文字需要时沿既有逐格排版增长相关行及外框，不裁掉完整内容。全表宽高各不超过 14400 点，列宽必须留下主格的正文字区域。

组内行列尺寸沿相同命令编辑，输入为缩放后的有效点值。核心按父组横/纵缩放换回本地整数 EMU，保留未选原生尺寸，再按现有内容适配和祖先边界事务提交；非整数组缩放可产生 EMU 舍入差异，查询返回最终有效值。重新应用当前显示值不改源、不新增历史。单元格边距按显示网格验证，放大组的合法小本地列宽不会被误判。`sizeReason` 是尺寸修改的独立保护原因，空串表示可用；`reason/operations/splitReason` 继续描述结构操作，`format/style` 使用各自原因。默认控件分别使用这些核心原因，保留文字/选择锁、动画子目标和尺寸预算。

`rowHeight`、`columnWidth` 返回选中实际行或列的有效共同点值，混合时为 `null`。默认面板分别显示共同值或空白混合提示，显式提交一个尺寸。选择、一次精确历史、无变化、锁定、活动候选、字体、源及输出预算共用既有保护；失败保留原文档。尺寸行为参考 [ONLYOFFICE SetColumnWidth/SetRowHeight](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L19008-L19058)，当前 SDK 使用完整逻辑网格、原生 EMU 和已有内容适配。实现归 [`table-size.mbt`](../../modules/formats/src/pptx/table-size.mbt)，查询和默认面板仍归上述表格模块。

插入数量等于选中的行或列数。向前插入使用首行/列，向后插入使用末行/列，复制行高或列宽及各格框属性、首段字符/段落格式，文字置空。旧单元格及其他部件保持原源。网格与外框一起扩展或缩小，提交前按既有排版检查行高；插入后选中新格块，删除后光标定位相邻保留格。删除全部行或列时移除整表，并检查整表删除锁和外部对象引用。每次操作合为一项精确历史。模板中的身份扩展或资源链接、锁定、多对象选择和超限修改受保护；动画引用表格内部范围时，修改需先实现引用重映射，当前受保护。失败保留源和选择。行为依据 [ONLYOFFICE 表格命令](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L6659-L6716)、[行插入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9997-L10146)和[列插入](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L10512-L10620)。实现归 [`table-selection.mbt`](../../modules/formats/src/pptx/table-selection.mbt)和 [`table-structure.mbt`](../../modules/formats/src/pptx/table-structure.mbt)。

本地普通 DrawingML 表格（含支持的组成员）沿现有对象查询返回 `kind: "table"`，单元格文字使用现有文字选择和编辑接口。核心读取固定列宽和行高、纯色或无填充、普通不透明实线边框、四边内边距及上/中/下垂直对齐。每格独立裁剪，文字、光标、命中和 PDF 复用公共文字布局。默认内边距沿 [ONLYOFFICE 表格设置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/ChartSpacePrototype.js#L640-L665)；网格和图形框对应关系参考 [Create_TableGraphicFrame](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Presentation.js#L4122-L4176)。

单格输入、换段、组合输入及取消共用现有源事务。文字需要更多高度时，核心增长对应行及外框，连同文字写入一项历史。撤销、重做及保存保留其他单元格和未改部件。查询按行连接单元格段落，以 LF 分隔。多格范围的复制返回完整格文本，列间使用 Tab、行间使用 LF，格内段落及软换行保留为 LF。范围输入把文字写入左上格并清空其他选中格；删除或剪切仅清空内容，保留网格和格式。范围高亮、空白区域命中和可访问描述均使用核心返回的矩形。组合输入候选使用预览选择，取消恢复完整原选区；提交合为一项历史。折叠光标在单元格边界的删除仍受保护，避免把相邻格段落合并或误清空范围。实现归 [`table-input.mbt`](../../modules/formats/src/pptx/table-input.mbt)和 [`table-hit.mbt`](../../modules/formats/src/pptx/table-hit.mbt)。

单选可编辑表格时，既有 `fill`、`stroke`、`textInsets` 和 `textAnchor` 命令修改单元格属性。对象模式作用于整表的主格，文字模式作用于当前主格或闭合后的矩形范围；延续格保留原属性。填充接受六位 RGB 或 `null` 无填充，保留已有不透明度。边框接受同样的颜色和 0.1–1000 点宽度，设置所选主格的四条不透明实线边；`null` 移除。相邻格的对应共享边同步修改，避免另一侧覆盖显示。若共享边只覆盖相邻合并格的一部分，核心原子拒绝，不改到范围外。内边距以点为单位，四边接受 0–14400，左右合计须留下正文字宽度；垂直锚定接受 `t/ctr/b`。字号、段落、非目标属性和部件保持，变化与行高增长合为一项精确历史；重复应用相同直接格式不新增历史。目标填充或边框中的未知注释及处理指令保持受保护。

`table.format` 返回 `{ fill, borderColor, borderWidth, left, top, right, bottom, anchor, reason, borderReason }`。混合值为 `null`，无颜色为 `""`，无边框宽度为 0；其他长度单位为点。`reason` 和 `borderReason` 为空表示相应编辑可用，后者单独说明共享边保护。默认面板显示整表或范围、混合值及保护原因，使用同一命令和既有原生输入。读取及写回归 [`table-cell-format.mbt`](../../modules/formats/src/pptx/table-cell-format.mbt)，共享边归 [`table-cell-borders.mbt`](../../modules/formats/src/pptx/table-cell-borders.mbt)。行为参考 [ONLYOFFICE 单元格共享边](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L1641-L1868)、[底色与垂直对齐](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L2028-L2115)。

表格复用既有 `textFormat`、`textAlign`、`textParagraph`、`clearTextFormat` 和 `clearParagraphFormat`，支持当前已交付的字符、段落及列表属性。单格内的文字范围和折叠光标使用格内位置，保留局部 run 和后续输入格式；矩形跨格范围作用于完整主格，包括空段落的后续输入格式，跳过延续格。对象模式作用于整表，亦可与形状一起选择。`PptxQuery.formatting` 和 `paragraph` 只合并实际目标的值，混合值及保护原因沿原接口返回。字号、缩进或间距变化按各格实际宽度适配行高及外框，不改变列宽、单元格框属性和非目标格。编号在各格独立计算，合并主格内各段连续编号。清除直接格式保留既有语言、高亮和链接规则；保留的超链接仍可显示下划线。缺字体、文字锁及预算失败保持原源、选择和历史。选区转换归 [`table-text-format.mbt`](../../modules/formats/src/pptx/table-text-format.mbt)，复用现有格式写回和逐格排版。行为依据 [ONLYOFFICE 单元格文字属性与清除](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L6207-L6263)和[单元格段落格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L7763-L7851)。

合并格使用原生 `rowSpan/gridSpan/hMerge/vMerge`，保留完整物理网格。左上主格持有文字，延续格必须为空；核心校验跨度、覆盖及延续标记。文字位置、复制、绘制和裁剪只包含主格，命中延续区域时定位主格。单个合并格内仍可选择文字。主格宽高为所跨列行之和，文字需要更多高度时增长跨度末行及外框。结构依据 [ONLYOFFICE 表格序列化](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Shapes/SerializeWriter.js#L5900-L5967)与 [TableCell 原生属性](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/OOXML/PPTXFormat/Logic/Table/TableCell.cpp#L118-L138)。归属校验归 [`table-spans.mbt`](../../modules/formats/src/pptx/table-spans.mbt)。

`merge` 要求范围内至少两个主格，按行顺序把各格段落及字符/段落属性移入左上格，清空其他主格，并写回标准跨度。合并后的文字整体选中。所涉单元格的局部列表默认值必须为空，段落合计最多 256；其他属性、未选格及部件保留。`unmerge` 要求选中一个合并格，恢复物理单元格；文字留在左上格，其余格为空并保留原框及文字格式。每个物理格的边距必须留下正文字宽度，否则先调整边距或列宽。两项操作均共用行高适配和一项精确历史。行为依据 [ONLYOFFICE MergeTableCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9466-L9602)，实现归 [`table-merge.mbt`](../../modules/formats/src/pptx/table-merge.mbt)。行列操作允许在跨度边界插入、整体移动合并格或删除完整跨度，切穿其他跨度时受保护。逐项操作保护归 [`table-operations.mbt`](../../modules/formats/src/pptx/table-operations.mbt)。

`editObjects({ action: "splitTableCell", rows, columns })` 拆分一个主格；`table.splitReason` 返回选择或结构保护原因。行列数为整数，分别接受 1–1000、1–63，乘积最多 4096；1×1 不改源、选择或历史。普通格可增加行，跨行合并格要求新行数不超过原跨度且整除跨度。列按主格总宽的整数 EMU 等分，保留原有网格边界；全表物理列数可能大于请求的逻辑列数。其他格调整跨度，保留文字、框属性和源间隙。原文字留在左上格，新逻辑格继承原格首段文字/段落及框格式。新延续格不复制其他格的链接内容。拆分与必要的行高增长合为一项历史，随后光标定位左上格。模板身份/资源链接、受影响列节点的未知元数据、宽度及预算失败原子拒绝。行为依据 [ONLYOFFICE SplitTableCells](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L9609-L9989)，实现归 [`table-split.mbt`](../../modules/formats/src/pptx/table-split.mbt)。默认控件归 [`pptx-cells.tsx`](../../packages/ui/src/pptx-cells.tsx)。单格文字链接复用[文字链接合同](#对象超链接)；表格查找替换复用上述字面匹配及事务合同。

普通表格已接通组合、组整体变换、成员移动及完整组原生/系统复制。读取按本地原生框验证网格，显示和候选预览按父组缩放派生格尺寸，保留合并、文字、字号、边距与边框。组内原生文字输入按实际宽度排版；行高换回本地坐标并逐行取整，外框使用同一原生行高之和，沿一项历史更新祖先边界。取消组合保留页面姿态，把缩放后的网格及继承旋转/翻转写回原生框，随后可继续输入和改表结构。完整组系统复制沿既有独立表样式快照，重复副本可分别改文字；组内可直接改格填充、边框、边距、锚定、字符/段落格式及表样式；排版、行高和祖先边界沿同一事务更新。格外观与表样式查询使用各自保护原因，文字/选择锁及动画子目标保护继续生效；行列尺寸控件使用独立的 sizeReason，可直接编辑组内表格；组内插删行列、合并/取消合并与拆格已沿原结构控件接通。核心先将祖先组与成员网格归一到有效点值，再复用原生网格写回、文字适配和组边界更新；归一化与编辑合为一项精确历史，失败保留原包，1×1 拆格不改源。结构和显式尺寸共用组成员变换保护，组锁定时保留独立样式/格式原因。导入的极小缩放无法容纳边距时保留源并诊断，复制或相关输出继续保护。表格组合由本项目既有组矩阵和网格缩放实现；ONLYOFFICE 的[直接表格入口](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/GraphicFrame.js#L542-L549)不允许组合或直接旋转。

支持网格宽高与外框一致的完整矩形表格，最多 1000 行、63 列、4096 格，文字合计最多 32767 UTF-16 单元，继续受包、布局、输出及历史预算约束。不一致的延续格、无法排版的组缩放及其他未支持配置给出诊断并保留原源；非整数跨度按现有数值规则拒绝。更广样式与复杂表格元数据编辑继续实施。实现归 [`table-read.mbt`](../../modules/formats/src/pptx/table-read.mbt)和 [`table-layout.mbt`](../../modules/formats/src/pptx/table-layout.mbt)。

#### 表格样式

核心沿 presentation 的 `tableStyles` 关系读取原生 `tblStyleLst`。表格未显式指定 `tableStyleId` 时使用目录的 `def`。支持全表、两组行/列条纹、首末行列和四个角格；按全表、行条纹、列条纹、末列、首列、末行、首行、右下/左下/右上/左上角顺序叠加。行条纹避开首行，列条纹在首列存在有效样式时避开首列。合并主格按其起始物理行列选择区域，内部共享线不绘制。直接单元格属性、run 和段落默认字符属性逐项优先；表格文字样式在母版及文稿默认字符属性之前生效。

读取纯色/无填充、主题填充引用、不透明实线及主题线引用、字体引用/普通字体、粗斜体和文字颜色。表格背景在单元格下方只绘制一次，透明格可透出背景，背景不透明度不重复叠加。全表的内部横竖边映射到实际网格；相邻边先取可见线，再取较高来源优先级，同层取较宽线，最后取右/下格。共享边按物理网格只画一次，跳过同一合并主格内部。`table.format` 使用绘制后的有效边，合并格一侧存在分段差异时返回混合值。文字、填充及边线进入同一 Canvas/PDF 路径。

内置 `No Style, No Grid`、`No Style, Table Grid`，以及 `Themed Style 1` 和 `Medium Style 2` 各六种强调色，共 14 项。使用原生 GUID、主题色及 tint；源目录中的同 ID 定义优先。`table.style` 返回 `{ settings, choices, reason }`；choices 为 `{ id, name }[]`。`settings: PptxTableStyle` 包含 `id` 和六个必需布尔项 `firstRow/lastRow/firstColumn/lastColumn/bandRows/bandColumns`。ID 使用目录身份并规范为大写，最多 80 个 UTF-16 单元；没有样式时查询 ID 为空。类型从 `wasm/pptx`、`web/pptx` 导出。

`editObjects({ action: "tableStyle", style })` 为单选表格应用完整设置；对象模式、单格光标和跨格选择均作用于整表。默认表单提供目录、六个选项和显式应用按钮。应用清除全部物理格的直接填充、边框和 `tcPr` 边距，保留垂直锚定、文字/段落格式、内容、跨度、网格及选择；同样式可重新应用以清除覆盖。缺少的内置定义写入原生目录；目录、关系和内容类型缺失时一起创建，并用中性默认定义保持其他无样式表格的外观。未知源内嵌标记保护被清除的格式。资源和必要行高适配共用一次精确历史，无源变化不增加历史，字体、锁定、候选及输出失败不提交。

目录最多 256 个源定义，名称最多 1024 个 UTF-16 单元，当前查询连同内置项最多 270 项。未知样式、渐变/效果、条件区域的内部横竖边、虚线、透明边框及未解析字体配置继续诊断并保护原源。未使用的未知定义保留，不影响已支持表格。预设和优先级参考 [ONLYOFFICE 原生预设](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Format.js#L18011-L18200)、[区域合成](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table/TableCell.js#L300-L443)及[应用后清除直接格式](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Table.js#L8673-L8743)。实现归 [`table-style-read.mbt`](../../modules/formats/src/pptx/table-style-read.mbt)、[`table-style-edit.mbt`](../../modules/formats/src/pptx/table-style-edit.mbt)和 [`table-edges.mbt`](../../modules/formats/src/pptx/table-edges.mbt)；更多预设、边线类型及样式定义编辑继续实施。

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
