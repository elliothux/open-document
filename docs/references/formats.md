# 当前字体与 DOCX 合同

本文维护 P1/P2/P3 的当前支持面；产品目标与核心/宿主职责归 [SDK 合同](sdk.md)。公开包仍为 private/WIP，API 尚未发布。当前只有一种实现路径，没有旧模型、双写或兼容适配。

## 会话与宿主

`loadEngine(bytes).openFoundation()` 创建同步 `FoundationSession`；浏览器使用 `FoundationClient.open(wasm, workerUrl)`，每会话独占 Worker，一次只允许一个请求。`dispose()` 终止 Worker，取消等待中的请求；同步 Wasm 调用本身不支持抢占取消。创建失败、非法打开或替换失败后可以继续使用未提交的会话；成功打开的会话只拥有一个 DOCX。

`defaultBudget()` 从 MoonBit 返回默认值；打开时必须显式传 `Budget`，可以收紧。`openDocx`/`query` 返回派生快照，修改快照不会改变文档；`replaceNode(id, revision, text)` 只替换会话已查询的正文 `w:t`，ID 在该会话内稳定，成功增加 revision。`saveDocx()` 返回新字节，不改宿主输入。保存失败可能留下已核验的读取缓存，但不提交编辑或输出。`close()`/`dispose()` 释放核心/宿主引用，后续访问报错。

字节在 Worker 边界使用 structured clone；Worker/核心之间当前使用一次操作一个 JSON/base64 批次。没有逐字符或逐 entry RPC。字节输入至少包含宿主→Worker clone、base64 字符串和核心解码三种表示；输出反向转换。调用耗时含这些转换，原始/编码大小可直接复核；没有声称零拷贝。轮廓通过 ASCII path 批量发送：`shape()` 返回缓存增量，`layout()` 返回可独立绘制的页结果和当前缓存资源；Canvas 按 key 复用 Path2D。一个 `OutlineCanvas` 必须绑定同一个 probe 的完整生命周期；`dispose()` 后不得复用。宿主负责展示诊断及提供可访问的文本/状态，Canvas 探针没有完整文档无障碍导航。

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

## 文件 profile 与保真

ZIP 支持单磁盘非加密 ZIP32、stored/deflate、UTF-8 或未标记的 ASCII 名称、12/16 字节 data descriptor。拒绝 ZIP64、加密、未知 method/flag、截断、重叠、重复名字/目录、错误 CRC 与解压长度。保留源记录用于未改条目；ZIP 包级 comment 和修改条目的压缩方式不保证词法恒等。

XML 支持 XML 1.0/Namespaces 1.0、UTF-8 和带 BOM 的 UTF-16 LE/BE；编码声明与实际字节必须一致。源片段 offset 统一是解码后的 UTF-16，ZIP 错误 offset 是字节，未知位置为 −1。禁止 DTD 和外部实体；没有文件/网络 entity resolver。允许普通转义/数字字符引用、CDATA、注释、PI、空元素；拒绝重复属性、无效 namespace/PI 名称、非法字符与错误语法。未改 XML 保留原字节；编辑 XML 写成 UTF-8，并更新声明，保留 standalone。

OPC 识别 content types、package/part relationships 与相对 target。关系 ID 只在 owner 内唯一，外链只作为数据返回、从不加载；内部路径不能逃出包。part 名称按 ASCII URI 和 UTF-8 percent escapes 校验，拒绝路径分隔符/非规范 unreserved escapes、尾点、大小写身份冲突和悬空关系。

DOCX 依据 officeDocument relationship、main content type 与 Word namespace 识别，支持 Transitional 主部件。查询正文中直接属于 paragraph/run 的 `w:t`，包括表格内正文；其他结构保留，未知直接 body 结构给诊断。不是 OOXML schema validator，不将未读 customXml/资源当作已理解能力。替换只允许无子元素的已知文本节点，自动转义和设置 `xml:space="preserve"`；未知 markup 保留在原位置，重复保存不累积转义。

Strict、Office/ZIP 加密、宏主部件、签名安全改写和旧二进制格式不在支持面。签名关系可在打开阶段拒绝；签名材料仅被识别时允许只读查询，但编辑/保存拒绝，不能把签名图片或未验证的 signature 当作有效签名。

## 失败

MoonBit 共用 `Failure`，浏览器暴露 `DocumentError(code, message, part, offset)`。主要类别为 `malformed-package/xml/opc/docx/font`、`unsupported-package/xml/docx/font`、`limit-exceeded`、`missing-part/font`、`stale-revision`、`invalid-operation/budget` 和 `closed-session`。Worker 关闭或宿主错误仍是普通 Error。失败不能返回空文档或伪造 revision；测试分别检查错误身份与输入/编辑状态。

当前使用固定 Chromium release WasmGC、独立 ZIP/XML 对照、HarfBuzz 塑形及 qpdf/Poppler 输出检查。P3 的 LibreOffice 固定参考与真实 Canvas/PDF 检查不代表全 Word 兼容；跨浏览器、IME、完整 schema、PDF/A 和 PDF/UA 尚未验证。执行入口与证据规则见[测试说明](testing.md)。

## DOCX 布局与 PDF 输出

`flow()` 返回派生的段落、样式、页面设置、表格、内联图片引用和诊断；不能修改它来编辑文档。`layout(profile)` 在核心中生成 `PageLayout`，profile 将 DOCX 字体键（含 `|bold` / `|italic`）映射到已供应字体 identity。缺字体或字形明确失败，宿主不提供 DOM 测量。布局长度单位为 point；字体内部度量仍用 font units，源范围使用节点局部 UTF-16 offset。

支持 docDefaults、段落/字符样式 basedOn、主题 Latin 字体、直接格式、字号/颜色/粗斜体、段前段后、缩进、左/中/右对齐、auto/exact/atLeast 行距、空段落及显式分页。正文、表格和空页眉共用段落间距校验，负间距/最小行距/单元格 padding 明确失败。页面使用单一设置，多节文档给不支持诊断，不承诺各节独立分页。分页的断行使用固定 Unicode 数据与基本 BiDi；同样式跨文本节点一起塑形并保留源映射。`unicode_linebreak` 的 Unicode 15 测试向量按上游规则排除 30.22/999.0 做依赖回归，其字符表源自 Unicode 13；不宣称完整 UAX #14 符合性。当前 fallback 仍按码点选择，复杂 script、彩色字形和任意字体质量不在承诺范围。

基础表格使用固定列宽、完整均匀 0.5pt 黑色网格、RGB 单色填充、对称 cell margin 和最小行高；行整体换页。合并/嵌套单元格、行内分页、超页高行和 exact 行高明确拒绝。不绘制浮动、裁剪、旋转、翻转图片或带内容的页眉；空页眉复用段落度量预留空间。已识别但未实现的正文属性给诊断，原包仍由 P2 保存；不是完整属性/schema 检查器，主题颜色、条件表格样式与复杂页眉页脚不在支持面。图片仅支持包内内联 extent；宿主解码已授权资源为 RGBA，外链图片明确拒绝、不自动下载。

文字 `auto` color 延后到所在单元格背景确定后解析，正文背景为白色，显式 RGB 保持原值。固定参考 profile 采用 sRGB 相对亮度乘 255 小于 88 时白字、否则黑字，与已检查的 LibreOffice [automatic text color](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/source/core/txtnode/fntcache.cxx) / [Color::IsDark](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/tools/source/generic/color.cxx) 规则相符；不承诺任意 Word 主题的颜色结果。

成功的字体添加、图片添加、打开或正文替换令旧布局失效。`layout` 每次生成新的会话内 `id`；profile 改变必须重排。`exportPdf(outputBytes, layoutId?)` 使用当前核心布局，可指定展示时的 ID 防止旧预览下载新内容；没有布局或 ID 过期时失败。`DocumentPreview` 始终传自己的 ID。失败的图片替换不覆盖已加载资源；PDF 失败不提交部分输出。

PDF 使用同一字形坐标、TrueType 子集、字体宽度、CIDToGIDMap、ToUnicode 与行级 ActualText，支持图片及 alpha mask。字体 fsType 禁止嵌入/子集时失败。默认 variation 坐标与 face 0；不支持 CFF、PDF 输入编辑、PDF/A、PDF/UA、签名或浏览器打印。PDF outputBytes 是 1–67,108,864 字节的产物上限；在最终文档序列化前核对已构建对象 payload，再核对最终确切大小。它不是字体子集、临时对象或整个进程的内存上限。

每段最多 4096 UTF-16 单元，最多 1024 页 / 32768 行。图片最多 256 个，每边最多 4096 像素，总 RGBA 16 MiB；一个 Canvas 最多 1600 万像素，zoom 0.25–4。预算分别约束核心资源、产物与宿主 Canvas，不等于进程峰值内存上限。

断行对候选前缀重新塑形以保留上下文正确性，长无空格段落存在二次成本；4096 单元边界诊断曾约 4.7 秒。Worker 隔离主线程，当前没有延迟 SLA；进入更长正文或交互编辑时需以同一文字/几何断言优化，不能用每字符 advance 或 DOM 测量替代。

`DocumentPreview.create(root, client, profile, signal?)` 显示只读页面、文本和诊断，支持滚动、切页、缩放、键盘与 PDF 下载。`dispose()` 释放自己持有的 Canvas、Path2D、ImageBitmap、监听器和 DOM，保留宿主其他子节点并恢复属性；调用方另需 `client.dispose()` 释放 Worker/核心。取消在异步准备步骤之间检查，不能抢占正在执行的同步 Wasm。基础文本语义与可达按钮不是完整文档无障碍认证。
