# 当前字体与格式合同

本文维护 P1–P9 的当前支持面；产品目标与核心/宿主职责归 [SDK 合同](sdk.md)。公开包仍为 private/WIP，API 尚未发布。内部架构直接按当前需求修改，删除旧模型与旧路径；兼容处理仅限文档格式。

XLSX 的网格、值/公式编辑、保真保存与基础打印见 [P5](../implemented/p5-xlsx-editing.md)。以下分别声明文件读取、计算、显示和编辑边界。

PPTX 已交付限定幻灯片编辑、源保留及静态 PDF，结果与检查依据见 [P6](../implemented/p6-pptx-editing.md)。

PDF 包含 Office 布局输出，以及 [P7](../implemented/p7-pdf-input.md) 的限定输入/查询和 [P8](../implemented/p8-pdf-operations.md) 的页面、批注、普通字段与源对象保存。两种保存入口各自维护源语义。

后续实现与测试基准优先使用 ONLYOFFICE core/sdkjs，其次使用 LibreOffice。下文 LibreOffice profile 记录已有实现和证据；对应功能调整时按当前优先级核对，并保留历史结果的真实来源。

P4 已完成限定 DOCX 编辑，只对声明范围负责。已验证输入不授予全部控制符编辑或布局支持；性能专项延后。交付范围见 [P4](../implemented/p4-docx-editing.md)，运行证据入口见[测试说明](testing.md#证据与正确性)。

U+202A–U+202E 与 U+2066–U+2069 保留在逻辑文字中，不要求可见字体字形，也不输出控制符轮廓。核心保留这些零宽区段的方向、字体和字号。十类输入的全部 234 个 Right/Left 矩形及真实输入框在 Node/Worker 匹配重复 LibreOffice 参考；原 51 处差异已修复。五组反向阿拉伯塑形向量在两个宿主匹配原生字形。内部 `PlacedRun.size` 以 pt 提供区段字号；完整布局留在核心。固定源码见[依赖记录](dependencies.md)，阶段验证范围见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)。

DOCX 文字区段的实际宽度和后续起点按固定 LibreOffice 的整数 twip 放置，初始断行 advance 和公开 `shape()` 保留浮点设计值。具体未支持范围与历史差异由私有 case 记录维护，不用行宽通过代替光标和选区验证。

## 默认 UI 与编辑宿主

`@open-document/ui` 的 `mountEditor(container, options)` 挂载 DOCX、XLSX、PPTX 或 PDF 默认 UI。`container` 由宿主提供可测量的高度。`options.format` 区分格式；`document` 为 `{ name, bytes }`，`resources` 明确提供 `{ wasm, workerUrl, fonts, profile }`，可传对应 `budget`、`theme: "light" | "dark"`、`locale: "zh-CN" | "en-US"`、异步 `onSave`、初始 `signal` 和 `styleNonce`。接入代码与普通 JS 示例归[开发说明](development.md#默认-web-ui)。

DOCX 也接受 `document: { name, blank: true }`，类型排除同时传入 `bytes`。`FoundationSession/Client.createDocx(budget)` 创建与打开一致的空白会话。包与模板由 MoonBit 生成，默认 Letter 页面、一英寸边距、11 pt Times New Roman 和一个空段落；字体仍由宿主显式提供。当前 XLSX/PPTX/PDF 要求已有文件字节。

返回的 `MountedEditor` 按 `format` 区分，`editor` 是当前文件的对应 Web 编辑宿主，只读属性在替换成功后指向新宿主。旧宿主释放后拒绝操作。实例提供以下方法：

| 方法 | 行为 |
| --- | --- |
| `open({ name, bytes })` | 只替换同格式文件；处理草稿/未保存修改，暂停新编辑并等待已接受队列；独立候选完成字体和首屏后替换，失败或取消保留旧会话；成功 `true`，用户取消 `false`，失败拒绝 Promise |
| `save()` | 产生原格式输出，等待 `onSave`；重复调用复用同一在途结果，回调期间可以继续编辑 |
| DOCX `create({ name })` / `open({ name, blank: true })` | 复用替换确认与独立候选，成功后成为新文件；其他格式没有新建入口 |
| `saveAs(name)` | 使用新名称产生原格式输出；目标由宿主决定。失败保留旧名称和修改状态；成功后更新名称。不同名称不复用同一个在途输出 |
| `getSnapshot()` / `subscribe(listener)` | 转发当前宿主的稳定快照；外部订阅跨文件替换保持，监听器异常不改变事务 |
| `close()` | 询问草稿和未保存修改；取消 `false`，完成关闭 `true`；等待在途保存回调后重新检查 |
| `dispose()` | 明确放弃内存会话，不弹确认；取消候选、等待已接受核心操作、释放 Worker/Canvas/React/自建 DOM；重复调用等待同一个 Promise，清理失败仍继续其他清理 |
| `setTheme()` / `setLocale()` | 更新 UI；保留文档会话、Canvas 和原生输入节点 |

每个实例追加一个自建容器与 open ShadowRoot，保留调用者原有 DOM。菜单与 Dialog 的 Portal 位于实例内；关闭确认是模态，会暂时限制整个页面交互。主题、关键尺寸与基础样式在实例内定义，宿主无需 Tailwind。当前目标只有 Chrome/Chromium。

框架无关的四类编辑宿主提供 `getSnapshot()`、`subscribe()`、`focus()`、`setPaused()`、`markSaved(output)` 和 `markDownloaded(output)`。快照包含会话身份、revision、导航、缩放、选区摘要、历史、诊断、停止/错误、在途操作及组合/拖动/草稿状态，并附格式当前查询。未变化时保持对象身份；已提交但绘制失败仍发布新 revision，保留保存与恢复入口。低层宿主借用 client，调用者等待宿主释放后另行关闭 client。

编辑宿主的原格式保存和 Office PDF 输出统一返回 `EditorOutput = { documentId, revision, format, bytes }`。默认 UI 另加文件名 `name`。此约定不改变原始 Wasm/client 的保存结果。只有该宿主实际产生的原格式输出可以 `markSaved`；旧会话、其他格式和任意裸 revision 都不能确认保存。确认的是输出 revision，其后新编辑仍显示未保存。导航、缩放和 UI 变化不修改文档。

`onSave` 成功才确认保存基线；失败保留修改并允许重试。缺省下载只提示“已生成下载”，不确认磁盘持久化，也不清除修改。PDF 导出不清除 Office 修改。关闭前选择“导出并继续”明确包含放弃内存会话。`dispose` 不等待宿主存储回调，晚到回执不更新已释放实例。

默认 UI 快照增加 `newDocument`。空白创建后即使 revision 为 0，`modified` 仍为 true；首次原格式 `onSave` 成功才清除此标记。下载不清除它，关闭与替换仍需确认。文件名去首尾空白、拒绝空名、路径分隔和控制字符；缺少当前格式扩展名时补齐。

保存回调期间若又有编辑，关闭/替换保留会话并返回 `false`。候选已经切换后，旧宿主清理失败只发布清理提示；新会话保持可用，`open` 返回 `true`。

DOCX/PPTX 的组合或拖动需要结束/取消。XLSX 保存先提交已支持的单格草稿；PDF 属性草稿须显式应用/取消。替换最多准备一个独立候选，加载界面的“取消”释放候选并恢复旧会话。核心保留原有文档校验、只读规则和预算。

## 会话与宿主

`(await loadEngine(bytes)).openFoundation()` 创建同步 `FoundationSession`；浏览器使用 `FoundationClient.open(wasm, workerUrl)`，每会话独占 Worker，一次只允许一个请求。`dispose()` 终止 Worker，取消等待中的请求；同步 Wasm 调用本身不支持抢占取消。创建失败、非法打开或替换失败后可以继续使用未提交的会话；成功打开的会话只拥有一个 DOCX。

`defaultBudget()` 从 MoonBit 返回默认值；打开时必须显式传 `Budget`，可以收紧。`openDocx`/`query` 返回派生快照，修改快照不会改变文档；`replaceNode(id, revision, text)` 精确写回已查询的无子元素 `w:t`，与逻辑范围命令共用校验、提交与历史，ID 在该会话内稳定。它保留相邻未知结构，并保留合法 XML 文本中的 CR 等字符，不赋予该段落可视编辑能力。成功内容变化增加 revision；无变化不增加。`saveDocx()` 返回新字节，不改宿主输入、不清空历史。保存失败可能留下已核验的读取缓存，但不提交编辑或输出。`close()`/`dispose()` 释放核心/宿主引用，后续访问报错。

## P4 当前编辑 API 切片

只读 DOCX Flow 的段落新增 `nominalSize`（pt，`0 < size <= 1024`），由核心按默认及段落样式计算；它不由具体文字 run 或标记直接字号推断，也不是宿主可编辑状态。布局用它计算单元格/空页眉末段的自动行距间隙，段间仍使用文字自然高度。当前补充修复已通过完整运行 `1791779829628` 的 308/308；23 组独立参考在安装 Node 与生产 Worker 的完整结果相同，验收边界见[测试记录](testing.md)。

历史产物已在 macOS/Chromium 使用现有豆包拼音完成中文提交、取消、撤销重做和绑定 revision 的保存；其他归档产物另通过普通 Latin 系统输入、撤销/重做及独立保存。R0 后的定向检查覆盖组合候选与取消，未重做系统中文输入验收。各记录分别绑定自己的产物，不扩大为所有输入法或 OS 候选窗几何支持；证据入口见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)。沿用现有输入法；Windows/Word 和 VoiceOver/语音输入不在验收范围，保留基本键盘/AX、源保真及失败恢复检查。

`shape()` 另返回字素边界的 `carets: { offset, before, after }[]`，offset 为 UTF-16，坐标沿用 shaping 的 CSS px；`before` 对应前一逻辑内容侧，`after` 对应后一侧，BiDi 交界可不同。连字优先读取 GDEF 默认设计坐标，缺少匹配数据时只分配该 cluster 的 advance；组合符没有额外停靠点，空文本返回 offset 0。

核心内部布局保留最终行的 carets，坐标为页面 point。宿主通过命中和光标查询获取几何。DOCX 连字光标按 LibreOffice MSO1 的每 pt 120 个整数设备单位构造 GDEF 分量宽度，差值累计到同一塑形 run 的后续光标；最终段内位置截断为整数 twip。公开字体探针仍返回原设计坐标，字形 advance、绘制及行宽不因光标取整而改变。`hitTest(layoutId, page, x, y)` 和 `caret(layoutId, position)` 返回绑定 revision/layout 的页面、行、坐标、高度及逻辑位置，不修改选区或历史。软换行前侧定位上一行，后侧定位下一行；验证范围见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)。过期或已因内容/资源变化失效的布局报 `stale-layout`，未知页面报 `invalid-page`，非有限/页外坐标或无文字页面报 `invalid-position`。图片及不可安全编辑的段落返回 `editable: false`、`position: null` 和原因。未解释属性的只读原因由 DOCX Flow 按段落及默认样式/表格/节上下文派生，随布局保留；局部段落诊断不禁止无关正文。 方向区段独占一行时仍使用其自然光标度量；因下一方向区段换行而保留的前行文字区段也独立计算。其余可复用的单文字区段保持整行高度，不能按 run 数量一律判成整行；自然高度继续按同页段落底部裁剪。

`selectionGeometry(layoutId, selection)` 返回 `{ layoutId, revision, rects }`，矩形携带页面、行及 point 坐标/宽高。普通逻辑范围按字素两侧的塑形坐标映射，只合并实际相邻区间；同段跨页或含高于段落基准方向的区段时，按固定 LibreOffice 的端点所属区段和自然度量构造区域，保留垂直分区及跨行溢出，再裁剪到各页段落框。跨页保留首框剩余区域、中间整框和末框前缀，不人为在最后一行分割整框区域。内部区域用整数 twip；公开塑形边界和整行高度保持既有精度，其余细分区域按原生整数矩形转换。范围继续到下一行、页或段时，按段落基本方向延伸到行可用区边界；同 offset 的软换行前后侧以实际结束行区分。反向结果相同、折叠为空；普通零宽字素保留零宽矩形，原生区段拆分可保留一个 twip 的边界区域。跨段嵌套范围仍用现有逻辑区间，其原生独立几何尚未验收；不显示段落标记，不赋予跨段写回能力。查询验证端点和当前布局，不改变选区、文档或历史。

`navigateDocx(revision, layoutId, direction, extend = false)` 返回 `{ state, caret }`，使用核心当前选区。方向为 `left/right/up/down/home/end`，左右按逻辑字素顺序移动，Right 到达用 before、Left 到达用 after，Home/End 到当前行逻辑首尾；End 的逻辑尾若同时是下一页同段入口，显示下一页并保留基础方向，同页软换行保持前侧；非折叠选区无 Shift 时，Left 收拢到逻辑起点，Right 从逻辑末端继续前进一个逻辑字素步骤，文档末端保持边界。上下保留目标 x、优先同单元格，离开单元格时排除水平区间不重叠的旁列。`extend` 保留 anchor；成功只改变选区，不增加 revision/历史。显式选区、编辑、横向移动及换布局重置垂直目标，非法方向、旧 revision/layout、无选区或受保护目标原子失败。行携带段落方向、正文/单元格身份和可用水平区间，placed run 携带段落起点，导航复用最终 shaping/BiDi 坐标。验证范围见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)。

`deleteDocx(revision, direction)` 的方向为 `backward` / `forward`。已有范围整体删除；折叠选区按逻辑前/后扩展字素删除，复用范围事务和历史。组合符与 surrogate 不拆开。段首 Backspace/段尾 Delete 可合并同一正文或单元格内的相邻普通段落；文档首尾保持 revision、源和历史不变。单元格边界、表格或受保护内容整体报 `protected-content`。

`editState()` 返回 revision、选区、撤销/重做可用性、历史容量与受影响段落；`selectDocx(revision, selection)` 仅更新选区。`replaceRange(revision, selection, text, inputGroup?)` 可跨 run，以及同一正文或单元格中连续的普通段落；`undoDocx(revision)` / `redoDocx(revision)` 恢复内容和选区，revision 继续单调增加。`selection` 保留 anchor/focus，每个位置包含稳定 paragraph ID、段落 UTF-16 offset 与 `before` / `after` affinity；范围按 XML 顺序排序，起点 affinity 决定 run 边界的插入格式。所有命令由 MoonBit 验证，TS 只转发和校验响应。

位置还可包含 `bidiLevel`（0–126 的整数）与 `frameStart`（大于 offset 的段内字素边界）。`frameStart` 保存导航保留的续接页框起点；光标查询只接受逻辑位置恰好位于该续接页框前一个字素的偏好，不能指向任意页。它只影响光标几何和导航，复制、输入、删除及选区矩形仍按逻辑 offset 计算。内容修改清除当前页框偏好，undo/redo 恢复完整选区元数据；只读查询、保存及失败不改变它。缺省字段使用原 affinity 和当前方向层级计算，不保留另一套状态或几何缓存。

编辑提交与后续布局是独立操作：提交成功后布局失败不会自动恢复旧源。浏览器停止输入，但用户可以明确 Undo；宿主排空原队列、取消其暂态组合，并核对当前 revision 后撤销一项历史和重排。失败仍保留停止状态，已完成的明确撤销不伪装为未发生；外部 revision 改动须先恢复，不自动撤销他人的编辑。恢复期间重复请求拒绝，销毁等待已接受的恢复，调用者 client 保留。

`selectedText(revision, selection)` 返回核心只读纯文本，按 XML 顺序提取正/反向普通范围，跨段以 LF 分隔并保留空段，折叠范围返回空串。它沿用字素、位置、revision、容器及内容保护检查，跨单元格或未知内容整体拒绝；不改变选区、revision、历史或布局。输出最多 65536 UTF-16 单元（包括 LF），超限报错而不截断。复制与结构写回共用范围顺序/保护检查；只有写回额外检查移动结构及格式。宿主不从页面文字重建选区。

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

`setParagraphFormat` 支持 `align: "left" | "center" | "right" | "both"`、`before/after/left/right/first`、`line` 和 `pageBreakBefore`。`both` 为两端对齐，写回 OOXML `w:jc`；默认 UI 提供同名按钮。距离单位为 pt，须能表示成整数 twip；范围 0–1584 pt，`first` 可为负值以设置悬挂缩进。`line: { rule, value }` 使用 OOXML 整数单位：`auto` 为每行 240，取值 120–2400；`exact/atLeast` 为 twip，取值 1–31680。UI 显示多倍行距或 pt，确认后转换为这些单位；清除段落直接格式也清除行距。

`FoundationSession/Client.styles(revision, kind)` 与 `DocumentEditor.styles(kind)` 返回现有样式目录：`{ revision, truncated, styles: [{ id, name, reason, basedOn, canDelete }] }`，`kind` 为 `"paragraph" | "character"`，每类最多 1024 项。`basedOn` 为直接基础样式 ID，无继承时为空串；`canDelete` 表示已支持、未链接且未标为默认的自定义样式。不可应用的样式带原因，默认 UI 禁用对应选项。该接口替代原段落专用目录入口。

`setParagraphFormat({ style: id })` 校验样式及继承链，清除已支持的段落直接属性后应用样式；保留文字直接字符格式。同一补丁中的显式属性继续覆盖样式。应用默认样式时省略直接 `w:pStyle`；`style: null` 只清除样式引用并恢复默认样式继承。行为依据 [ONLYOFFICE 的段落样式应用](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js)。

`setCharacterFormat({ style: id })` 在目标范围写 `w:rStyle`，保留直接字符属性；`style: null` 清除引用，恢复段落继承和原有直接属性。跨 run 范围沿原边界拆分，折叠范围只设置后续输入样式，随实际输入或组合提交一项历史；取消组合保留输入意图。空段落标记的字符样式也参与查询与显示。行为依据 [ONLYOFFICE 的 Run 字符样式设置](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js)。新建文档带 `DefaultParagraphFont`、`Emphasis` 和 `Strong`，继承与粗斜体切换沿已有 OOXML 规则；宿主须为最终组合提供字体 profile，不能只准备样式单独使用的字形。

两类查询均包含样式 ID 与混合状态，格式复制只捕获属性值，不复制样式 ID。未知属性、循环继承、跨类型继承及不支持的值拒绝应用，文档与历史保持原状。应用可一次撤销，支持保存重开和相同布局的 PDF。

`FoundationSession/Client.updateStyle(revision, id, update)` 与 `DocumentEditor.updateStyle(id, update)` 修改现有样式。`DocxStyleUpdate` 使用 `{ character, paragraph, name?, basedOn? }`。两类格式支持现有字段，不能包含 `style` 引用。字符样式只接受空的段落补丁。省略字段保留直接定义，null 清除定义并恢复继承。粗体、斜体和删除线的布尔值表示样式在文档默认值及 `basedOn` 链上的有效值，核心换算 OOXML toggle，分别处理复杂文字的粗斜体。名称只改变显示名，保留稳定样式 ID；名称须为非空、最多 200 UTF-16 单元的有效 XML 文字。

`basedOn` 指定同类型、已支持的基础样式；null 移除直接继承引用，省略时保留。更换基础样式保留原有直接定义，不固定旧基础样式的有效值。同一补丁的粗斜体、删除线和制表位按新基础样式计算。核心拒绝循环、跨类型、未知及超过 64 层的继承，并检查原本可用的依赖样式和正文组合。继承、名称与格式修改合为一项历史，撤销恢复完整源内容。行为参考 [ONLYOFFICE 样式继承与历史](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js)。默认 UI 的基础样式列表与当前样式类型一致，也可选“无基础样式”。

样式修改保留元数据、注释与未改正文。核心先检查候选、原本可用的依赖样式及正文直接属性的组合，再合并正文和样式 XML 校验包预算，一次提交 revision 和有界历史。失败不改变正文、部件、选择或历史；撤销/重做也先完整回放全部候选。输入、组合和保存使用同一组已提交部件。共享修改最多处理 4096 个样式，继承链沿既有 64 层上限。默认 UI 可修改所选样式的名称、基础样式、字号、段落对齐和恢复继承字号；其他已支持格式可通过 API 修改。目录按按钮显式刷新。DOCX 历史目前支持正文、样式及其他 Word XML 的修改，以及样式或设置创建所需的 XML 部件新增、关系和内容类型修改。已有部件的任意删除及二进制资源历史仍待对应操作接入。

`FoundationSession/Client.createStyle(revision, style)` 创建自定义样式，返回 `{ id, state }`。`DocxStyleCreation` 使用 `{ name, kind, basedOn? }`；`kind` 为 `"paragraph" | "character"`，可选的基础样式必须同类型且已支持。省略 `basedOn` 创建无直接继承的定义。Web 编辑宿主的 `createStyle(style)` 返回新 ID。核心分配身份，并避开 Word 部件中已有定义和引用；同类型样式不接受重复显示名。创建不改变选区或立即应用到文字，之后可用现有应用和修改方法。默认 UI 读取目录后可新建；有选中项时以它为基础，没有选中项时不设基础样式。样式管理不要求正文选区，应用和清除仍需要有效选区。

导入文件缺少样式部件时，核心在主文档旁创建唯一 XML 部件，原子补齐主文档关系和内容类型。原有同名部件、关系 ID、外链和未知内容保留。新定义和包元数据合为一项有界历史，新增 XML 的源内容计入历史预算；包图、输出或历史预算失败不改变状态。撤销移除本次新增部件并恢复原包，重做保留后续修改所需的节点身份。保存重开后使用同一关系与样式 ID。

`deleteStyle(revision, id, replacement)` 删除自定义样式，替代样式必须已支持且类型相同，也不能依赖被删样式。Web 编辑宿主省略 revision。核心同步移除定义并替换 WordprocessingML 部件中的样式引用，包括正文、页眉和编号；保留直接格式、文字、其他样式及未知内容。折叠处待输入的样式引用也映射到替代项。命令至多替换 65536 个引用，继续受包与历史预算约束。全部候选成功后一次提交，撤销同时恢复各部件与选择。默认 UI 显示并使用所选样式的基础样式作为替代。默认/内置样式及链接样式保留保护，不按删除命令重置其定义。

两端对齐在塑形后扩展词间空格；无空格中文使用合法断行处的字形簇间隙，接近满行的普通单词可使用字形簇间距。连字与字形不重塑，末尾空格不参与扩展，最后一个 Tab 之前的位置保留。段落末行与显式分页行保留自然宽度，RTL 末行靠右。软换行默认参与对齐；派生 `Paragraph.expandSoftBreak` 读取设置中的 `compat/doNotExpandShiftReturn`。光标、命中、选区、装饰与 PDF 消费相同位置；阿拉伯文使用词间距，未新增 kashida 字形。规则参考 [ONLYOFFICE 的段落对齐计算](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph_Recalculate.js)。

字段省略表示不修改，null 清除对应直接属性并恢复继承。MoonBit 使用 `FormatChange::{Keep, Clear, Set}` 和类型化属性结构。字符范围在边界处拆分 run，范围外文字与未知部件保留；段落属性覆盖范围接触的段落。一次修改提交一项有界历史，保存与 PDF 沿现有布局。无效位置、过期 revision、属性和预算失败不提交部分修改。

折叠范围只改变后续输入属性，不增加 revision、历史或空文字。实际输入及格式一起提交；组合预览沿候选处理，取消仍保留输入属性。显式选择/导航结束该输入属性，保存本身不改变它。默认 UI 的字体/段落控件调用同一 Web 队列，数字与颜色确认后提交；字体仍需宿主供应对应 profile 和字节。

`FoundationSession/Client.captureFormat(revision, selection)` 返回核心计算的 `CopiedFormat: { character, paragraph }` 属性片段。它只含当前已支持且在选区内一致的有效值；混合属性省略，应用时保留目标对应值。片段包含值，不绑定源位置或 revision，也不包含页面几何、样式或列表身份。`applyFormat(revision, selection, format)` 校验目标 revision 与完整片段，字符和段落候选全部成功后一次提交；失败保留文档与历史。折叠处的字符格式仍作为后续输入属性，段落修改立即提交。Web 编辑宿主提供同名方法，默认 UI 使用“复制格式”和“应用已复制格式”；替换文档后清除 UI 中的片段。应用后可一次撤销两类源修改，保存与 PDF 沿现有格式路径。

核心在连续塑形的光标位置上划分装饰，先绘制高亮背景，再绘制文字与下划线/删除线；编辑装饰不改变连字与断行宽度。上下标沿 ONLYOFFICE 的 0.65 字号比例、上移 0.35 / 下移 0.141 个原字号计算，保持逻辑文字、源 offset 和原字号属性。行高与选区包含实际基线。相同图元用于 Canvas 与 PDF，不由 DOM 或 CSS 计算文字几何。其他下划线类型或颜色变体保留源并诊断、保护编辑，未宣称完整装饰兼容。

派生 `TextStyle` 增加 `underline/strike`、RGB `highlight`（无高亮为空串）和 `script`；MoonBit 的 `TextStyle::new(font, size, color)` 创建普通样式。当前 `TextProbe::text_block` 只返回文本块，上下标可排版，装饰明确拒绝；XLSX/PPTX 仍使用普通样式，后续各自编辑功能接入效果图元。

`FoundationSession/Client.findDocx(revision, text, options?)` 进行字面查找；`options` 为可选的 `matchCase`、`wholeWord` 布尔值。返回 `{ revision, truncated, matches: [{ selection, snippet, reason }] }`。结果按正文与表格单元格顺序排列，相邻同容器段落以 LF 相连。受保护文字也返回命中与原因，不能替换。查询最多 65536 UTF-16 单元，最多返回 1000 个不重叠命中；超过上限设置 `truncated`。

查找使用 Unicode 简单小写映射，不做规范化、语言定制或正则匹配。全词边界按字母/数字和非 ASCII Unicode 标识符延续字符判断，ASCII 下划线作为分隔符。命中不能切开字素或代理对。范围暂限主文档正文与单元格，页眉、脚注等内容区域待对应编辑能力接入。

`replaceDocxMatches(revision, selections, text)` 一次校验全部范围后提交一项历史；空数组无变化，重叠、空范围、保护、过期 revision 和预算失败不部分提交。替换最多 1000 个范围，文本最多 65536 UTF-16 单元，允许 LF 段落分隔、U+2028 软换行与 Tab，不接受 CR。插入文字沿用目标起点 run 格式。结构替换另限源 XML UTF-16 长度乘命中数不超过 67108864，避免逐项解析阻断操作。

`DocumentEditor.find(text, options?)` 在原队列中查询，并给结果增加 `documentId`。`selectMatch(result, index)` 定位可编辑命中；`replaceMatches(result, text, index?)` 替换指定项，省略 index 时替换全部结果。全部替换拒绝 `truncated` 或含受保护内容的结果。旧文档或旧 revision 的结果拒绝后仍可继续编辑。默认 UI 提供同一组操作，编辑后提示重新查找并禁用旧结果。

`DOCX_SOFT_BREAK` 为 U+2028，由 Wasm/Web foundation 导出。`replaceRange`、组合候选和批量替换用它表示段内换行，保存为 `w:br`；实际 LF 仍创建段落。`DocumentEditor.insertSoftBreak()` 与默认 UI 按钮、Shift+Enter 调用同一范围事务。`query().texts` 包含普通文字与内联控制节点；换行逻辑长度为一个 UTF-16 单元，`w:cr` 同样读取为 U+2028。Flow 用 LF 排版，`selectedText` 与剪贴板将软换行转为 LF。普通换行可删除、选中、设置格式及跨段移动；页/栏换行、环绕清除和未知内联属性继续保护。

Tab 输入与粘贴保存为 `w:tab`，不转成空格。`FoundationSession/Client.tabDocx(revision, backward?)` 在正文插入 Tab，反向时减少正的首行/左缩进；在现有表格中只移动到相邻单元格，不增加 revision 或历史。默认 UI 的插入制表符按钮与 `DocumentEditor.paste("\t")` 总是插入字符，原生 Ctrl+Tab 也在单元格中插入。Tab/Shift+Tab 只由文档原生输入处理；参数控件使用浏览器焦点切换，Escape 将焦点移出文档输入。

`Paragraph.defaultTab` 为 point，来自 `settings/defaultTabStop` 的整数 twip，默认 36 pt，范围 0–1584 pt；0 表示零宽。核心根据当前行位置与缩进计算下一默认制表位，断行、光标、预览与 PDF 消费同一宽度。末格 Tab 保持原位置，自动追加表格行归表格编辑批次。

`FoundationSession/Client.setDefaultTabStop(revision, interval)` 与 `DocumentEditor.setDefaultTabStop(interval)` 修改文档默认间隔，不要求正文选区。`interval` 为 0–1584 pt，须能表示成整数 twip；null 清除显式设置并恢复 36 pt。`EditState.defaultTabStop` 提供当前有效值，默认 UI 可修改或恢复。修改保留自定义制表位、逻辑 Tab、待输入格式与未知设置；现有相同值不产生历史。缺少设置部件时，XML、关系与内容类型一并创建。设置修改或创建合为一项有界历史，失败保留已提交包，撤销和重做恢复各部件及选择。候选先验证设置值和包预算，再提交并使相关布局失效。未知目标标记、重复设置、外部/重复设置关系，以及强制保护的文档设置拒绝修改。行为参考 [ONLYOFFICE 的文档默认制表位历史](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Document.js)。

`setParagraphFormat({ tabs })` 使用 `TabStop[]`：每项为 `{ position, align, leader? }`，位置单位为 pt，须为 0–1584 pt 的整数 twip，按位置递增且不重复，最多 64 个有效位置。`align` 支持 `left/right/center/decimal/bar`。`leader` 省略时为 `none`，也支持 `dot/hyphen/underscore/heavy/middleDot`；`bar` 只接受无引导线。MoonBit `TabStop.leader` 与核心返回值总带明确值。字段省略保留；null 清除段落直接定义并恢复继承；空数组清除全部有效位置，核心为移除的继承位置写 `w:tab w:val="clear"`。格式查询与格式复制包含有效制表位。默认 UI 可添加、修改、移除、应用、清除全部与恢复继承，使用同一历史与保存路径。

派生 `Paragraph.tabs` 提供合并后的有效位置。核心按后续片段宽度放置右/居中制表位，小数点使用文档 `settings/decimalSymbol`（派生 `Paragraph.decimalSymbol`，默认 `.`）；越过可用边缘的自定义位置按右边缘放置，悬挂缩进保留隐式左边界位置。规则参考 [ONLYOFFICE 的制表位合并](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Styles.js)与 [Tab 后续文字定位](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Run.js)。未知标记仍保留源并保护编辑。当前使用物理左边框作为制表原点，RTL 镜像与标尺交互仍待实现。

引导线按 [ONLYOFFICE 的 Tab 字形绘制](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/RunContent/Tab.js)使用当前字体与字号，重复字形居中放入间隔；短划线使用 1.5 倍步长，`heavy` 与 `underscore` 使用下划线字形。逻辑文字、光标与复制内容仍为一个 Tab，PDF 的 ActualText 不加入装饰字符。每个 Tab 最多 4096 个引导字形，每行 16384 个、每段 65536 个；超过预算明确拒绝布局。

`bar` 遵循 [Word 的竖线制表位语义](https://support.microsoft.com/en-us/word/using-the-ruler-in-word)，在每一行的指定位置绘制竖线，不改变文字或 Tab 定位。当前核心绘制 0.5 pt 黑线，沿行高延伸，预览与 PDF 共用图元；未宣称与 Word 的全部显示细节一致。派生 `Line.bars` 随分页定位，缓存与公开行结果各自持有数组副本。

当前未接通剩余制表位能力、样式 CRUD 与列表。剩余范围归 [P10](../p10-docx-core.md)，不把本切片记作完整格式编辑。

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

上述策略结合 [ONLYOFFICE 普通段距与特殊分支](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph.js#L10805-L10860)、[LibreOffice 布局分支](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/sw/source/core/layout/flowfrm.cxx#L1582-L1770) 与固定引擎结果；不是完整 Word 间距规则。`contextualSpacing`、自动段距、按行指定的段距及编号仍不支持，直接格式和实际应用的默认值、样式链都会报告部件与特性，例如 `unsupported-layout:word/styles.xml:w:vanish`。未使用的命名样式不产生诊断。原始内容照常保留，应用不能把带诊断的结果称为保真布局。

自动断行前只解析一次整段 BiDi 层级；选定行执行 UAX #9 L1/L2，塑形沿用该层级与镜像规则。同样式源 run 拆分不会改变阅读顺序；使用独立 FriBidi 1.0.16 的整段层级核对 RTL、数字、括号及拉丁后缀，不以片段重新推断方向生成答案。

浏览器预览只接受 PNG、JPEG 与 GIF。宿主先检查有界编码头的尺寸与像素预算，再调用原生解码器；解码结果仍核对预算与头部尺寸，失败或取消关闭已创建的 ImageBitmap 并保留宿主。GIF 使用原生解码器选取的静态帧，不支持动画播放；其他编码明确失败。该检查不保证浏览器或 WasmGC 的进程峰值内存。

`flow()` 返回派生的段落、样式、页面设置、表格、内联图片引用和诊断；不能修改它来编辑文档。段落与表格数组各自保持源顺序；顶层表格的必需 `beforeParagraph` 是当前源 XML 中先于该表格的正文段落数，同位置连续表格按表格数组顺序插入。稳定 `id` 不表示文档位置，拆段后也不按 ID 排序。`layout(profile)` 在核心中生成 `PageLayout`，profile 将 DOCX 字体键（含 `|bold` / `|italic`）映射到已供应字体 identity。缺字体或字形明确失败，宿主不提供 DOM 测量。布局长度单位为 point；字体内部度量仍用 font units，源范围使用节点局部 UTF-16 offset。

支持 docDefaults、段落/字符样式 basedOn、主题 Latin 字体、直接格式、字号/颜色/粗斜体、段前段后、缩进、左/中/右对齐、auto/exact/atLeast 行距、空段落及显式分页。正文、表格和空页眉共用段落间距校验，负间距/最小行距/单元格 padding 明确失败。页面使用单一设置，多节文档给不支持诊断，不承诺各节独立分页。分页的断行使用固定 Unicode 数据与基本 BiDi；同样式跨文本节点一起塑形并保留源映射。`unicode_linebreak` 的 Unicode 15 测试向量按上游规则排除 30.22/999.0 做依赖回归，其字符表源自 Unicode 13；不宣称完整 UAX #14 符合性。当前 fallback 仍按码点选择，复杂 script、彩色字形和任意字体质量不在承诺范围。

基础表格使用固定列宽、完整均匀 0.5pt 黑色网格、RGB 单色填充、对称 cell margin 和最小行高；行整体换页。相邻行共享边框只占一次高度，表尾另留底边，分页判断包含当前页底边空间。自然字高使用上述共享参考设备取整；固定 Noto 原表格的自然行高与垂直步距已匹配固定 LibreOffice，不扩大为所有应用或水平几何一致。合并/嵌套单元格、行内分页、超页高行和 exact 行高明确拒绝。不绘制浮动、裁剪、旋转、翻转图片或带内容的页眉；空页眉复用段落度量预留空间。已识别但未实现的正文属性给诊断，原包仍由 P2 保存；不是完整属性/schema 检查器，主题颜色、条件表格样式与复杂页眉页脚不在支持面。图片仅支持包内内联 extent；宿主解码已授权资源为 RGBA，外链图片明确拒绝、不自动下载。

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

`XlsxSession` 和 `XlsxClient` 分别提供同步 WASM 与 Worker Promise API。核心持有 OPC/XML、稀疏单元格、公式依赖、选区、历史及几何；TS 只处理平台输入与呈现。工作表 `id` 来自包内关系目标。查询包含隐藏表，界面只列出可见表。

| API | 结果与约束 |
| --- | --- |
| `open(bytes,budget)` / `openXlsx(bytes,budget)` | 打开 Transitional XLSX；签名、Strict、加密和其他扩展格式拒绝 |
| `query(sheet?,range?)` | 默认当前选区；返回实际存在的稀疏单元格，单格查询包含空格；A1 地址，查询矩形端点有序 |
| `select(revision,sheet,range)` | 更新核心选区；单格合并区域定位锚点 |
| `replace(revision,sheet,range,values,literal=false)` | 一项矩形事务；字段为输入字符串，核心识别值与公式；清空保留样式 |
| `navigate(revision,direction,extend=false)` | `left/right/up/down/home`；跳过隐藏行列，Shift 扩展选区 |
| `copy(revision)` / `paste(revision,text)` / `clear(revision)` | 核心显示值 TSV、矩形粘贴及清空；核心识别数值/布尔，`=` 不执行 |
| `undo(revision)` / `redo(revision)` | 源片段、选区和计算结果原子恢复；revision 每次成功修改递增 |
| `save()` | 返回完整 XLSX；无编辑及全部撤销后保留原解压部件字节 |
| `viewport(options)` | 逻辑滚动、point 尺寸、sheet、字体 profile、可选 `reveal`；一个绘制区域及可见网格语义 |
| `hit(layoutId,x,y)` / `selectionGeometry(layoutId)` | 核心地址命中与选区矩形；旧布局身份或 revision 拒绝 |
| `printLayout(revision,sheet,options,profile)` | 独立打印区域，返回有身份的页面绘制批次 |
| `exportPdf(layoutId,outputBytes)` | 使用当前打印布局；编辑、字体变更或新打印布局使旧输出身份失效 |

`XlsxQuery` 返回 `sheets`、`sheet`、`selection`、`revision`、历史状态、`date1904`、`fontKeys` 和诊断。每格分别返回 `value`、`formula`、`cached`、`calculated`、`calculation`、`display`、`input` 与 `readOnlyReason`。空格、空字符串、零、布尔值与错误独立表示。`input` 是核心生成的可编辑源码，文字带前导单引号，避免重新提交时误作公式或数值。

### 显示与计算

读取共享/内联字符串、数值、布尔值、错误、公式及缓存。富文本读出文字，保留原 XML并保护编辑。受保护工作表及含未知编辑语义的单元格只读。图表、条件格式、绘图等未呈现内容给出诊断，继续保留源部件。

网格读取行高、列宽、隐藏行列与合并区域。核心使用默认字体最大数字宽度换算列宽；不依赖 DOM 度量。字体键沿用 `family|bold|italic`，宿主明确映射到已添加的字体身份。支持字体大小、粗斜体、基本文字色、纯色填充、实线边框、左中右/上中下对齐与换行。行列尺寸使用声明值，不自动调整。数字宽度不足时显示 `#`；文字按单元格裁剪。

数字格式覆盖 General、`@`、整数、两位小数、千分位、百分比、`yyyy-mm-dd`、`hh:mm:ss`，以及内置 1–4、9–10、14–22、49。日期保留数值，核心解释 1900/1904 系统，1900 序号 60 显示虚构的 2 月 29 日，序号 0 显示 1900-01-00。不经过宿主时区。其他格式、颜色 tint、渐变/图案、非实线边框及额外字体装饰保留声明并诊断，不承诺显示等价。

公式支持数值、字符串和布尔常量，括号、一元正负、`+ - * /`、比较、A1 单格/矩形、绝对/混合引用、带引号的跨表引用，以及 `SUM/AVERAGE/MIN/MAX/COUNT/IF`。范围端点可以反向，核心按矩形解释。引用中的文字、布尔、空值和错误按函数规则处理；IF 只求值选中分支，依赖仍包含两侧声明引用。

首次打开计算支持的公式，编辑只重新求值受影响公式。首次有效事务同步与已计算结果不同的导入缓存，包括未受本次输入影响的陈旧缓存；无编辑打开不写回。语法、越界引用、未支持公式、新建循环和预算超限整体拒绝；除零等是带类型的公式结果。共享公式按锚点派生；编辑命中组时有界展开该组，其他组保留。

名称、结构化/外部/三维/整行整列引用、数组、动态数组、易变函数及迭代计算未支持。导入存在未支持公式、无法解析依赖或原有循环时，整个工作簿只读，显示导入缓存；缺缓存显示未计算。公式不访问网络、宏或宿主脚本。

### 输入与保存

前导 `=` 进入公式，单引号强制文字。未做日期自动识别与地区化输入推断。TSV 粘贴保留以 `=` 或单引号开头的文字，其余字段由核心识别数值、布尔或文字。CRLF/CR 统一为 LF，支持带引号的字段、字段内换行和双引号转义；不等宽行或未闭合引号拒绝。矩形写入、粘贴和清空与任意合并区域相交时拒绝，单格按锚点修改。

候选源片段、依赖、计算缓存和历史一起提交。新文字使用内联字符串；共享字符串顺序不变，同步计数。保存保留非目标源内容，移除失效 `calcChain`、其关系与 content type，并设置 `calcPr` 重算属性。输出重新检查 OPC 完整性；失败保留会话，不返回部分文件。不承诺整个 ZIP 字节相等。

`SpreadsheetEditor` 持有一个原生 textarea 草稿。双击/F2 编辑，Enter/Tab 提交并移动，Shift+Enter 在草稿内换行，Esc 取消。草稿开始与导航进入同一队列，快速输入绑定确认后的单元格，保留原生文字与选择。离格或切表先提交；错误保留草稿与旧值。组合结束只更新草稿，提交产生一项历史。草稿中使用原生文本撤销，退出后使用核心工作簿历史。保存/打印等待命令队列，组合未结束拒绝输出。外部 revision 冲突需取消草稿并刷新，不覆盖外部修改。

屏幕使用固定视口 Canvas 与独立覆盖层。滚动/尺寸/缩放请求按动画帧合并，过期结果丢弃；成功几何、文字和轮廓在预算内复用。选区只更新覆盖层。可见单元格提供有界 grid 语义、地址、值和只读原因，保留焦点和键盘入口。调用者拥有 client 生命周期；关闭 editor 后另行关闭 client。

### 打印与资源边界

`PrintOptions` 明确给出 point 纸张宽高与四边距，可给 `range`。方向通过宽高表示，固定 100%；默认范围是当前表有内容的矩形。编辑器默认 A4 纵向、36 point 边距，提供预览切页与 PDF。分页先向下再向右，沿行列边界分割；空表一页，超宽单列、超高单行、跨页/范围合并、未计算公式、未支持显示或未呈现内容明确拒绝。屏幕滚动、缩放、DPR 不改变打印布局。复杂文件打印设置保留，不自动套用。

继续使用前文文件、字体、输出与 Canvas 上限，另有以下操作上限。载荷计数不代表进程峰值或性能保证。

| 对象 | 上限 |
| --- | --- |
| 工作表 / 实际单元格 / 样式 | 256 / 100000 / 4096 |
| 单格文字 / 全部文字或共享字符串载荷 | 32767 UTF-16 / 4 Mi UTF-16 |
| 单次查询、写入、剪贴板、视口 | 4096 格；编辑/剪贴板 1 Mi UTF-16；可见文字 262144 UTF-16 |
| 合并区域 / 单个共享公式组 | 1024 / 4096 格 |
| 公式 | 单格 8192 UTF-16、4096 token；语法深度 64；依赖链 256；工作簿源码 1 Mi、引用 32768、一次计算工作量 1048576 |
| 历史 / 队列 | undo+redo 共 100 项、4 MiB 源补丁 payload；宿主 64 项 |
| 打印 | 32768 可见格、单轴 4096 项、1024 页；每页继续受视口绘制文字/单元格上限约束 |

当前范围不含空白工作簿向导、表/行列增删、样式编辑、填充、排序筛选、冻结窗格交互、图表/透视表/图片编辑、协作和整本工作簿打印。XLS/XLSB/XLSM、其他浏览器、Windows/Excel、VoiceOver、性能专项与发布验收未进入本期验证。

## PPTX

`PptxSession.execute()` 与 `PptxClient.execute()` 使用独立的 `PptxCommand`，不复用 DOCX/XLSX 位置模型。`PptxQuery` 返回 revision、声明页序/尺寸/隐藏状态、当前页对象、有效字体键、图片键、选区、历史状态与诊断。幻灯片 ID 为源部件路径，对象 ID 为所属部件与源 `cNvPr.id`；未知对象使用只读源节点身份。

| 命令 | 作用 |
| --- | --- |
| `openPptx` / `queryPptx` | 显式预算打开 Transitional PPTX / 查询当前状态 |
| `selectPptx` / `navigatePptx` | 页/对象/文字选择、对象顺序及字素/行导航；文字使用对象内 UTF-16 offset |
| `replacePptx` / `deletePptx` / `copyPptx` | 普通文字范围编辑、方向删除及纯文本复制；编辑需要字体 profile |
| `beginPptx` / `finishPptx` / `cancelPptx` | 开始、提交、取消 `text` 或 `transform` 候选；匹配 revision 与 candidateId |
| `transformPptx` / `dragPptx` | 绝对位置/尺寸，或基于手势开始几何的 point 增量与核心手柄编号 |
| `undoPptx` / `redoPptx` / `savePptx` | 原子历史及绑定 revision 的源保存 |
| `layoutPptx` / `hitPptx` / `selectionPptx` | 当前页绘制、最上层命中、对象轮廓/手柄及文字光标/选区；几何绑定 layoutId |
| `imageKeysPptx` / `imageBytesPptx` / `imagePptx` | 准备当前页或导出范围的资源键、读压缩源、接入经过宿主校验的 RGBA |
| `exportPptxPdf` | 绑定 revision、字体 profile、当前页/整稿、隐藏页选择与输出预算的静态 PDF |

文字与变换候选基于原范围重算，不写入已提交 XML，不累积中间历史。暂态查询/布局读取候选；提交一项历史，取消恢复原选择。保存、PDF 和普通编辑在候选期间失败。Enter 是普通段落分隔 `\n`，Shift+Enter 使用对象内软换行 `U+2028`；保存为 DrawingML `p` / `br`。跨 run/段落保留范围外字符与段落属性，不重建整个 `spTree` 或 `txBody`。普通逐字符输入目前各自成项。

主题颜色支持 sRGB、带 `lastClr` 的系统色、主题/颜色映射以及 tint、shade、lumMod、lumOff。支持无填充、纯色填充、实线、主题填充/边框/背景引用和无效果样式。未知颜色变换、填充或可见效果保留源并诊断，不静默宣称完整。占位符依类型/索引匹配，当前属性按具体声明覆盖继承值；写回不修改共享主题、母版或版式。

字体键为有效 family，按需附加 `|bold` / `|italic`。主/次字体、显式 Latin/EA/CS 字体及当前常见脚本映射参与解析；自动推断覆盖 Latin、简中 Han 缺省、Kana、Hangul、Arabic、Hebrew、Devanagari 和 Thai。语言敏感的 Han 区域字体推断尚未扩展；不声明全语言主题字体一致性。调用者提供授权字体及实际样式映射，缺失时明确失败。

文本框支持基本字号、粗体/斜体、文字色、段落对齐、内边距、缩进、点值/百分比段距及行距、软换行和字符项目符号的字体/大小/颜色。固定框越界诊断并裁剪；无法建立文字几何时保留边界占位和对象文本查询。`normAutofit` 以 10 次有界搜索求解 10%–100% 字号缩放，保存必要 `fontScale` 并保留基准字号。字段所在框、自动编号、图片项目符号、多栏、纵排、文字变形和 `spAutoFit` 诊断或保护。

支持矩形、椭圆、直线与文本框的核心路径；PNG/JPEG、矩形源裁剪、旋转/翻转和组合坐标变换。组合成员与继承对象只读；未提供旋转控件。图片不发起外链请求，源压缩字节与关系不改；只为当前页准备屏幕资源。全稿 PDF 临时准备所选页资源，仍受累计图片/输出预算约束，失败不返回截断文件。

未知可见对象阻止点穿；无确定边界时，该页直接画布编辑只读，查询/保存及其他页仍可用。静态 PDF 遇到可见未支持内容、效果或未解决适配时返回页/对象原因。动画/切换只保留源。保存及全部撤销保留原解压部件；输出重新校验 ZIP/XML/OPC，不承诺整个 ZIP 字节一致。

沿用文件、字体、图片、Canvas 和 PDF 预算，另有以下上限。预算不等同于堆峰值或性能保证。

| 对象 | 上限 |
| --- | --- |
| 页数 / 每页对象身份 / 全稿可见对象 | 256 / 4096 / 16384 |
| 依赖树 / 组合层级 | 2048 个源部件 / 16 层 |
| 幻灯片或对象尺寸、位置绝对值 | 14400 point；线可有一个零尺寸轴 |
| 文本框 / 单段 / 全稿文字 | 32767 / 4096 / 1048576 UTF-16；每框最多 256 段 |
| 字体键 / 图片资源 | 各 256；图片最大 4096×4096、单图 4194304 像素、RGBA 累计 16 MiB |
| 布局 / PDF 图元 | 每页 262144 glyph；整稿 PDF 1048576 图元；通用绘制仍受前述批次预算约束 |
| 历史 / 宿主队列 | undo+redo 共 100 项、4 MiB 源补丁 payload；编辑与指针意图队列各 64 项，指针预览只保留待发送末次坐标 |

未支持内容、产品操作和本次检查边界归 [P6 结果](../implemented/p6-pptx-editing.md)。Chromium 受控输入事件已验证；没有追加系统输入源、Windows/PowerPoint、VoiceOver、其他浏览器或性能验收。

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
