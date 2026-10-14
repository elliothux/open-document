# 当前字体与 DOCX 合同

本文维护 P1/P2/P3 及实施中的 P4 的当前支持面；产品目标与核心/宿主职责归 [SDK 合同](sdk.md)。公开包仍为 private/WIP，API 尚未发布。当前只有一种实现路径，没有旧模型、双写或兼容适配。

后续实现与测试基准优先使用 ONLYOFFICE core/sdkjs，其次使用 LibreOffice。下文 LibreOffice profile 记录已有实现和证据；对应功能调整时按当前优先级核对，并保留历史结果的真实来源。

P4 编辑仍在开发，只对声明范围负责。已验证输入不授予全部控制符编辑或布局支持；性能专项延后。当前目标见 [P4](../p4-docx-editing.md)，运行证据入口见[测试说明](testing.md#证据与正确性)。

U+202A–U+202E 与 U+2066–U+2069 保留在逻辑文字中，不要求可见字体字形，也不输出控制符轮廓。核心保留这些零宽区段的方向、字体和字号。十类输入的全部 234 个 Right/Left 矩形及真实输入框在 Node/Worker 匹配重复 LibreOffice 参考；原 51 处差异已修复。五组反向阿拉伯塑形向量在两个宿主匹配原生字形。`PlacedRun.size` 以 pt 提供区段字号；这是只读布局快照，不能作为宿主文档模型。固定源码和证据见 [P4](../p4-docx-editing.md)。

DOCX 文字区段的实际宽度和后续起点按固定 LibreOffice 的整数 twip 放置，初始断行 advance 和公开 `shape()` 保留浮点设计值。具体未支持范围与历史差异由私有 case 记录维护，不用行宽通过代替光标和选区验证。

## 会话与宿主

`(await loadEngine(bytes)).openFoundation()` 创建同步 `FoundationSession`；浏览器使用 `FoundationClient.open(wasm, workerUrl)`，每会话独占 Worker，一次只允许一个请求。`dispose()` 终止 Worker，取消等待中的请求；同步 Wasm 调用本身不支持抢占取消。创建失败、非法打开或替换失败后可以继续使用未提交的会话；成功打开的会话只拥有一个 DOCX。

`defaultBudget()` 从 MoonBit 返回默认值；打开时必须显式传 `Budget`，可以收紧。`openDocx`/`query` 返回派生快照，修改快照不会改变文档；`replaceNode(id, revision, text)` 精确写回已查询的无子元素 `w:t`，与逻辑范围命令共用校验、提交与历史，ID 在该会话内稳定。它保留相邻未知结构，并保留合法 XML 文本中的 CR 等字符，不赋予该段落可视编辑能力。成功内容变化增加 revision；无变化不增加。`saveDocx()` 返回新字节，不改宿主输入、不清空历史。保存失败可能留下已核验的读取缓存，但不提交编辑或输出。`close()`/`dispose()` 释放核心/宿主引用，后续访问报错。

## P4 当前编辑 API 切片

只读 DOCX Flow 的段落新增 `nominalSize`（pt，`0 < size <= 1024`），由核心按默认及段落样式计算；它不由具体文字 run 或标记直接字号推断，也不是宿主可编辑状态。布局用它计算单元格/空页眉末段的自动行距间隙，段间仍使用文字自然高度。当前补充修复已通过完整运行 `1791779829628` 的 308/308；23 组独立参考在安装 Node 与生产 Worker 的完整结果相同，验收边界见[测试记录](testing.md)。

此前固定产物已在 macOS/Chromium 使用现有豆包拼音完成中文提交、取消、撤销重做和绑定 revision 的保存；另一个此前产物通过现有输入模式的普通原生字母输入、撤销/重做及独立保存。这些结果分别绑定各自产物；当前冻结构建另已通过普通 Latin 系统输入、撤销/重做和独立保存复验；不扩大为所有输入法或 OS 候选窗几何支持。按用户 2026-10-11 的要求，Windows/Word 验收和 VoiceOver/语音输入跳过，仍保留基本键盘/AX、源保真及失败恢复检查；当前完整范围归 [P4](../p4-docx-editing.md)。下述系统简体拼音及朗读未测项是证据边界，不再是该阶段必须取得的环境。

`shape()` 另返回字素边界的 `carets: { offset, before, after }[]`，offset 为 UTF-16，坐标沿用 shaping 的 CSS px；`before` 对应前一逻辑内容侧，`after` 对应后一侧，BiDi 交界可不同。连字优先读取 GDEF 默认设计坐标，缺少匹配数据时只分配该 cluster 的 advance；组合符没有额外停靠点，空文本返回 offset 0。

`PageLayout` 的最终行也携带 carets，坐标为页面 point。DOCX 连字光标按 LibreOffice MSO1 的每 pt 120 个整数设备单位构造 GDEF 分量宽度，差值累计到同一塑形 run 的后续光标；最终段内位置截断为整数 twip。公开字体探针仍返回原设计坐标，字形 advance、绘制及行宽不因光标取整而改变。`hitTest(layoutId, page, x, y)` 和 `caret(layoutId, position)` 返回绑定 revision/layout 的页面、行、坐标、高度及逻辑位置，不修改选区或历史。软换行前侧定位上一行，后侧定位下一行；命中规则与参考依据见 [P4](../p4-docx-editing.md#32-位置选区与命中)。过期或已因内容/资源变化失效的布局报 `stale-layout`，未知页面报 `invalid-page`，非有限/页外坐标或无文字页面报 `invalid-position`。图片及不可安全编辑的段落返回 `editable: false`、`position: null` 和原因。未解释属性的只读原因由 DOCX Flow 按段落及默认样式/表格/节上下文派生，随布局保留；局部段落诊断不禁止无关正文。 方向区段独占一行时仍使用其自然光标度量；因下一方向区段换行而保留的前行文字区段也独立计算。其余可复用的单文字区段保持整行高度，不能按 run 数量一律判成整行；自然高度继续按同页段落底部裁剪。

`selectionGeometry(layoutId, selection)` 返回 `{ layoutId, revision, rects }`，矩形携带页面、行及 point 坐标/宽高。普通逻辑范围按字素两侧的塑形坐标映射，只合并实际相邻区间；同段跨页或含高于段落基准方向的区段时，按固定 LibreOffice 的端点所属区段和自然度量构造区域，保留垂直分区及跨行溢出，再裁剪到各页段落框。跨页保留首框剩余区域、中间整框和末框前缀，不人为在最后一行分割整框区域。内部区域用整数 twip；公开塑形边界和整行高度保持既有精度，其余细分区域按原生整数矩形转换。范围继续到下一行、页或段时，按段落基本方向延伸到行可用区边界；同 offset 的软换行前后侧以实际结束行区分。反向结果相同、折叠为空；普通零宽字素保留零宽矩形，原生区段拆分可保留一个 twip 的边界区域。跨段嵌套范围仍用现有逻辑区间，其原生独立几何尚未验收；不显示段落标记，不赋予跨段写回能力。查询验证端点和当前布局，不改变选区、文档或历史。

`navigateDocx(revision, layoutId, direction, extend = false)` 返回 `{ state, caret }`，使用核心当前选区。方向为 `left/right/up/down/home/end`，左右按逻辑字素顺序移动，Right 到达用 before、Left 到达用 after，Home/End 到当前行逻辑首尾；End 的逻辑尾若同时是下一页同段入口，显示下一页并保留基础方向，同页软换行保持前侧；非折叠选区无 Shift 时，Left 收拢到逻辑起点，Right 从逻辑末端继续前进一个逻辑字素步骤，文档末端保持边界。上下保留目标 x、优先同单元格，离开单元格时排除水平区间不重叠的旁列。`extend` 保留 anchor；成功只改变选区，不增加 revision/历史。显式选区、编辑、横向移动及换布局重置垂直目标，非法方向、旧 revision/layout、无选区或受保护目标原子失败。行携带段落方向、正文/单元格身份和可用水平区间，placed run 携带段落起点，导航复用最终 shaping/BiDi 坐标。规则及验证合同见 [P4](../p4-docx-editing.md#32-位置选区与命中)。

`deleteDocx(revision, direction)` 的方向为 `backward` / `forward`。已有范围整体删除；折叠选区按逻辑前/后扩展字素删除，复用范围事务和历史。组合符与 surrogate 不拆开。段首 Backspace/段尾 Delete 可合并同一正文或单元格内的相邻普通段落；文档首尾保持 revision、源和历史不变。单元格边界、表格或受保护内容整体报 `protected-content`。

`editState()` 返回 revision、选区、撤销/重做可用性、历史容量与受影响段落；`selectDocx(revision, selection)` 仅更新选区。`replaceRange(revision, selection, text, inputGroup?)` 可跨 run，以及同一正文或单元格中连续的普通段落；`undoDocx(revision)` / `redoDocx(revision)` 恢复内容和选区，revision 继续单调增加。`selection` 保留 anchor/focus，每个位置包含稳定 paragraph ID、段落 UTF-16 offset 与 `before` / `after` affinity；范围按 XML 顺序排序，起点 affinity 决定 run 边界的插入格式。所有命令由 MoonBit 验证，TS 只转发和校验响应。

位置还可包含 `bidiLevel`（0–126 的整数）与 `frameStart`（大于 offset 的段内字素边界）。`frameStart` 保存导航保留的续接页框起点；光标查询只接受逻辑位置恰好位于该续接页框前一个字素的偏好，不能指向任意页。它只影响光标几何和导航，复制、输入、删除及选区矩形仍按逻辑 offset 计算。内容修改清除当前页框偏好，undo/redo 恢复完整选区元数据；只读查询、保存及失败不改变它。缺省字段使用原 affinity 和当前方向层级计算，不保留另一套状态或几何缓存。

编辑提交与后续布局是独立操作：提交成功后布局失败不会自动恢复旧源。浏览器停止输入，但用户可以明确 Undo；宿主排空原队列、取消其暂态组合，并核对当前 revision 后撤销一项历史和重排。失败仍保留停止状态，已完成的明确撤销不伪装为未发生；外部 revision 改动须先恢复，不自动撤销他人的编辑。恢复期间重复请求拒绝，销毁等待已接受的恢复，调用者 client 保留。

`selectedText(revision, selection)` 返回核心只读纯文本，按 XML 顺序提取正/反向普通范围，跨段以 LF 分隔并保留空段，折叠范围返回空串。它沿用字素、位置、revision、容器及内容保护检查，跨单元格或未知内容整体拒绝；不改变选区、revision、历史或布局。输出最多 65536 UTF-16 单元（包括 LF），超限报错而不截断。复制与结构写回共用范围顺序/保护检查；只有写回额外检查移动结构及格式。宿主不从页面文字重建选区。

段内边界使用 Unicode 13.0.0 扩展字素，跨文本节点的组合符与 ZWJ 不可拆开；修改后重新合并的字素会将光标推进到合法边界。普通空段支持 offset 0 的输入：优先在第一个已有空 run 创建 text，保留其格式；没有 run 时在段末创建普通 run/text，保留段落属性、现有前缀和非目标源片段。空段身份来自正文 `flow().paragraphs` 或 `flow().tables` 的单元格段落，不能从尚无 text 的 `query().texts` 推断。跨单元格/表格、CR/tab、内联图片所在段、域/书签/修订/未知内联标记及受保护容器目前整体拒绝，未修改的内容仍保留。普通正文与顶层表格单元格内的事务可用；不表示带布局诊断的文件已经可视编辑。

`replaceRange` 将实际 LF 作为段落分隔，可替换折叠、段内或跨段正反向范围，首尾/连续 LF 产生空段；新段仍在原 body/单元格内，光标到最后插入文字末尾，并对字素拼接推进到合法边界。原段及移到新段的存量节点保留身份；新节点获得单调 ID。新段继承已支持的段落属性和边界 affinity 选中的字符格式，显式关闭直接或继承的段前分页。未知属性、编号、节或不可安全编辑内容整体拒绝。多分隔替换是单条历史，返回原范围与全部新增段的受影响 ID；撤销删除新段并恢复原字节，重做恢复同一组新 ID。连续输入使用核心保留的目标 text ID 继续同一字符格式；显式选择/导航、删除、外部修改、undo/redo 和关闭终止它，保存或失败不终止。字符格式的连续目标与显式输入组分工不同，均不维护第二份文档内容。

候选 XML 与包预算校验成功后才提交状态。XML Document 是正文内容的唯一权威，Session 已删除文本覆盖表；解析顺序与稳定 `Node.id` 分离，结构插入不重编号相邻节点，删除身份不能继续查询。局部源补丁核对前片段、重放原身份并保留精确 XML；撤销全部改动后保存原 OPC 字节。文本节点、段落属性及命名空间仍由当前解析结果派生，不维护可独立修改的第二棵树。

跨段替换保留前段身份和段落属性，删除中间完整段落，将右侧存活 run/text 移入最终插入段并保留身份。其有效 namespace 与字符格式来自现有 XML/样式解析；上下文变化时固定受支持字体、字号、颜色和四种 bold/italic/script toggle，并保留已解释的语言与 script 属性，全局 styles/theme part 不变。无法清除的未指定继承属性、重复/错置属性、编号、节或未知结构整体保护。一条 XML 候选同时包含叶文本和结构补丁，一次提交一项历史；撤销/重做恢复原字节、身份及选区。

历史保存局部前后源片段、相关节点身份和选区，undo/redo 共计最多 100 项、4 MiB UTF-16 源片段 payload，单命令最多 65536 UTF-16 单元。payload 包含转义、属性及结构标记，不包含数组/节点身份与运行时分配开销；因此含转义的输入可能比纯文本计数更早达到上限。过大的单项整体拒绝，容量不足淘汰最旧完整项，可用边界与计数随结果返回。这些是实施期的安全上限，尚未完成实测校准与性能验收。当前每次提交仍重解析全篇候选 XML，没有声称局部编辑耗时或内存已达标。多分隔片段在字符串构造前检查复制放大，并继续按整个命令检查 XML、包与历史预算。连续普通输入已按下述显式输入组归并；纯文本剪贴板、组合核心/API 与 Chromium 事件宿主、段落塑形复用与稳定点分页已接入。现有中文输入法的历史验收已记录，此前另一产物通过普通原生输入、撤销/重做和独立保存；当前源码的普通系统输入、撤销/重做和独立保存重开已复验；当前 OS 中文 composition、候选窗几何及校准性能仍未测。

组合 API 使用当前已确认选区和 revision；`beginComposition` 返回单调正 i32 `compositionId`，后续更新/提交/取消必须同时匹配身份与 revision。暂态只持有原文档和一个当前范围候选，不累计中间历史；query/Flow/几何读取候选，`EditState.selection` 返回候选光标，`compositionId` 非空，但已确认 XML、选区、revision 与 undo/redo 不变。更新为空或等于原选中文字时显示原文档与原选区。最终非空文字重新经同一范围事务提交，最多一项历史；空结束/取消/同内容 no-op 保留源字节、选区与 redo。开始结束普通输入组；更新及结束继续校验 XML、65536 UTF-16 单元、包输出和历史预算，CR/tab/LF 拒绝，失败保留上一个合法候选。成功开始/更新/取消/结束均废弃旧布局身份；组合期间普通选择/编辑/导航/复制、undo/redo、保存和 PDF 返回 `busy`，错误/过期身份返回 `stale-composition`，关闭释放候选。Chromium CDP/受控更新、结束、空取消及在途宿主销毁已验证；核心候选光标定位平台输入元素，成功候选和结束必须重新取得布局，不能只按 revision 判断。组件清理需 await dispose 后再使用/关闭 client；错误恢复先取消自身候选。此前固定产物的 macOS/Chromium 中文输入已验证；此前另一产物通过普通原生输入，当前源码的普通系统输入已复验，当前 OS 中文 composition 未复验。候选窗几何及更多平台输入仍未测。

宿主接受 `compositionend` 后，只消费一次最终文字相同、类型为 `insertCompositionText` 且非 composing 的尾随 `input`，不重复提交核心事务。键盘、beforeinput、新组合、失焦、保存、取消或错误清除这一关联；错误文字、类型或重复通知仍按未支持输入处理。Chromium 受控事件回归验证提交和错误边界。该关联最多保留一份命令预算内文字，不代表堆峰值或系统输入法验收。

`inputGroup` 是可选的正 i32 组号；省略时编辑命令独立成项。组号仅用于非空、无 LF 的普通输入，首项可替换支持的段内/跨段范围；核心仅在后续折叠选区等于已确认当前光标、上一项光标连续且组号相同时归并。单命令仍逐次增加 revision，整组 undo/redo 完整回放候选后一次提交、一次增加 revision，恢复首项前/末项后选区及节点身份。显式选择/导航、删除、未分组编辑、LF 输入、undo/redo 和关闭结束旧组；失败保持已确认组，核心保存不清空组/历史。组 payload 超过 4 MiB 时开启新完整项，整个历史仍按总 payload/100 项淘汰最旧完整项，文档文字保持；`historyEntries/historyBytes` 显示新的可撤销边界。宿主另在失焦、输出屏障和恢复时换组，并在接受排队意图时固定组号。当前组保留各次局部补丁，undo/redo 逐补丁重解析 XML；尚无校准延迟或峰值内存通过。

`DocumentEditor` 已提供有限浏览器输入宿主，与只读 `DocumentPreview` 共用页面绘制、图片预算和释放。调用者独占交付已打开的 client，宿主不维护文档树。点击、拖选、基本键盘输入、选区、删除及 DOCX/PDF 输出经最多 64 项意图队列发送；只移动光标不重建文档布局。输出携带确切 revision，PDF 绑定已完成的 layout ID，当前 revision 与最近输出 revision 分开显示。Tab 可首次进入当前页的可编辑位置，光标滚动可见。主指针拖选通过核心命中/选区 API，两轴边缘滚动按原页序跨页；空白页保留真实端点，末次坐标先于输入与输出，取消/失焦/捕获丢失停止滚动。同段内相邻显式分页符合并为一次布局分页，跨 run 也适用，保存仍保留每个原始分页符；正文、普通换行或独立段落分隔的分页不合并。这是维护者选择的固定 LibreOffice 行为，不授予 Microsoft Word 兼容性。失败需显式恢复，销毁保留原宿主 DOM 和调用者 client；不保证取消已在途核心事务。实际支持与暂未接收的输入见[开发说明](development.md)。

节的 `w:cols` 只识别无子列、`num` 缺省/1、`equalWidth` 缺省/true 的单栏声明；`w:docGrid` 只识别无子节点、`type` 缺省/default 的未启用模式。这些声明与单栏无网格布局一致，源内容保留；未知属性/子节点、自定义列和启用网格仍诊断并保护。此改动让原始 POI 普通正文可进入输入宿主，不增加多栏或网格排版引擎，依据与验证归 [P4](../p4-docx-editing.md#34-输入异步与保存)。

字节在 Worker 边界使用 structured clone。字体通过内部 `foundation_add_font` 导出，以每字符一个八位值的字符串传入核心。DOCX 和图片继续使用每操作一个 JSON/Base64 批次，输出反向转换。两种输入均需临时字符串和核心字节，不是零拷贝；原预算保持。轮廓通过 ASCII path 批量发送：`shape()` 返回缓存增量，`layout()` 返回可独立绘制的页结果和当前缓存资源；Canvas 按 key 复用 Path2D。一个 `OutlineCanvas` 必须绑定同一个 probe 的完整生命周期；`dispose()` 后不得复用。宿主负责展示诊断及提供可访问的文本/状态，Canvas 探针没有完整文档无障碍导航。

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

当前使用固定 Chromium release WasmGC、独立 ZIP/XML 对照、HarfBuzz 塑形及 qpdf/Poppler 输出检查。P3 的 LibreOffice 固定参考与真实 Canvas/PDF 检查不代表全 Word 兼容；系统组合输入、完整 schema、PDF/A 和 PDF/UA 尚未验证。执行入口与证据规则见[测试说明](testing.md)。

## DOCX 布局与 PDF 输出

普通数字使用默认字形；共享塑形入口禁止固定依赖将 `frac/numr/dnom` 全局应用到所有数字。四种固定 Noto 字体的独立默认字形/位置已核对。当前没有 OpenType feature 编辑 API，也未实现 U+2044 上下文触发的自动数字分数排版；字符和 DOCX 源照常保留，不冒充完整 HarfBuzz 行为。原有连字、BiDi、字素及测宽/绘制共用路径保持。

DOCX 的显式页面宽、高按固定 LibreOffice 25.8.2.2 的[导入规则](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/sw/source/writerfilter/dmapper/DomainMapper.cxx#L824-L837)转换为整数 1/100 mm，各自按[标准尺寸表顺序](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/i18nutil/source/utility/paper.cxx#L208-L224)选择差值严格小于 44 的首个值并回到整数 twip；不匹配值及缺省页面保持，非法值仍由原页面 validator 拒绝。500 pt 可成为 498.9 pt，1000 pt 可成为 1000.65 pt；这是显示布局尺寸，原 pgSz XML 和包部件不改写。普通换行候选在布局层排除补充码点之前的边界，以匹配 LibreOffice/ICU 的 UTF-16 查询；强制换行、段末、字素紧急回退和标准 Unicode 分段模块保持。十二份同字体控制与原 DPR2 输入已由重复独立参考和实际两宿主核对，不承诺所有 CJK 或 Office 版本的行为。尺寸事实有来源，算法独立实现；未移植上游可执行代码或新增依赖。

共享自然行度量使用固定 LibreOffice 25.8.2.2 的[MSO1 参考设备](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/vcl/source/gdi/virdev.cxx#L405-L406)。每 pt 120 单位，字号和 ascent/descent 先取整为设备单位。再将 ascent 与组合高度分别换算为整数 twip，布局输出仍用 pt。依据[字体度量取整](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/vcl/source/font/fontmetric.cxx#L538-L539)和[组合高度换算](https://github.com/LibreOffice/core/blob/libreoffice-25.8.2.2/vcl/source/outdev/font.cxx#L205-L210)，不是简单将浮点 pt 乘 20 取整；固定 Noto 的 10 pt 为 273 twip。源字号/XML、字体选择、字形 advance、Exact 基线和 API 保持；五字号表格与另组正文重复参考只授予自然高度与已声明垂直步距。

字体自然高度优先使用有效 USE_TYPO_METRICS，随后是有效 hhea，最后回退到已验证的 Win 度量；缺失或截断 hhea 原子拒绝。`FontInfo` 的 ascent/descent 随此选择，CJK 与 Arabic 的预定变化已由固定字体二进制独立核对。光标在单文字区段复用行框，多区段按前侧文字区段取自然高度并裁剪到当前页段落底部；`caret`、`hitTest`、导航共用计算。原 CJK 与六组垂直控制已匹配固定参考。十二组独立原生对照另验证中西文自动间距、不同字号和窄行，以及 Arabic/Asian 进入和退出区段的差别；测宽、字形和光标共用间距，行尾仅在宽度允许时保留。有效 autoSpaceDE/DN 源属性按固定 LibreOffice 25.8.2.2 导入行为保留但不应用，非法或重复声明继续保护。两份 Arabic/Asian 原件已验证折叠 Left/Right 的 after/before 坐标及高度、70 个独立鼠标位置和 36 个默认逻辑按键位置；真实编辑器按键在 Chromium 验证。所有脚本分类、嵌套 BiDi、小字号间距命中及其他导航配置仍未全面验收；证据与范围见 [P4](../p4-docx-editing.md#32-位置选区与命中)。

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

`PageLayout.shapedParagraphs` / `reusedParagraphs` 是本次实际塑形/复用的段落几何数量（含表头、单元格及复用页面内的段落）；`reflowedPages` / `reusedPages` 是重新处理分页状态及直接复用的整页数，二者之和等于当前页数。它们不是耗时指标。完整源输入和字体/page/profile/间距依赖匹配时，核心复用局部行及页面前缀，在首个变化边界所在页继续原分页规则；只有未变后缀和纵坐标、段后间距及页内文字/边框有无全部匹配，才接回旧几何。表格按行检查稳定点，显式空白页规则不变；旧后缀仍检查当前图片及行/页预算。仅保留上次成功布局：塑形和分页各自最多 1024 条输入、1048576 个载荷单位，超限仍正常塑形/分页，不缩减文档支持。一个原始字段或字符串 UTF-16 单元计一单位，不代表堆字节或峰值内存；失败不提交候选缓存，成功增加字体后清空，关闭释放，返回的可变数组与缓存隔离。具体校准性能和完整阶段条件见 [P4](../p4-docx-editing.md#35-排版失效与性能路径)。

PDF 使用同一字形坐标、TrueType 子集、字体宽度、CIDToGIDMap、ToUnicode 与行级 ActualText，支持图片及 alpha mask。字体 fsType 禁止嵌入/子集时失败。默认 variation 坐标与 face 0；不支持 CFF、PDF 输入编辑、PDF/A、PDF/UA、签名或浏览器打印。PDF outputBytes 是 1–67,108,864 字节的产物上限；在最终文档序列化前核对已构建对象 payload，再核对最终确切大小。它不是字体子集、临时对象或整个进程的内存上限。

一次段落布局内的候选测宽另保留最多 128 个成功宽度，每个精确键最多 4096 UTF-16 单元，键合计不超过 524288 单元，另有 128 个 Double。键绑定文本、字号、主字体和当前 BiDi 上下文；字体集合在该同步调用内不变。超限重新测量，图片和最终绘制不使用此表；返回或失败即释放，不形成跨段落或跨编辑的持久缓存。此载荷计数不代表实际堆峰值。

每段最多 4096 UTF-16 单元，最多 1024 页 / 32768 行。图片最多 256 个，每边最多 4096 像素，总 RGBA 16 MiB；一个 Canvas 最多 1600 万像素，zoom 0.25–4。预算分别约束核心资源、产物与宿主 Canvas，不等于进程峰值内存上限。

断行对候选前缀重新塑形以保留上下文，长无空格段落存在二次成本。Worker 隔离主线程，当前没有延迟 SLA。实际交互被阻断时再诊断，不能以每字符 advance 或 DOM 测量替代正确布局。

性能校准和进一步优化延后。已有输入/字形/历史/队列/布局/Canvas 上限、拒绝恢复和释放要求保持。

`DocumentPreview.create(root, client, profile, signal?)` 显示只读页面、文本和诊断，支持滚动、切页、缩放、键盘与 PDF 下载。`dispose()` 释放自己持有的 Canvas、Path2D、ImageBitmap、监听器和 DOM，保留宿主其他子节点并恢复属性；调用方另需 `client.dispose()` 释放 Worker/核心。取消在异步准备步骤之间检查，不能抢占正在执行的同步 Wasm。基础文本语义与可达按钮不是完整文档无障碍认证。
