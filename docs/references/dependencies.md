# Foundation 依赖与本地缺口

生产依赖用 `moon.mod` 固定精确版本，不使用根 `references/` 研究副本构建。MoonBit 标准库随工具链固定；下表列直接依赖，传递依赖由 Moon 固定版本解析。

MoonBit 0.1.20261010 要求新配置格式。[依赖准备工具](../../tools/prepare-dependencies.mbtx)先用官方 `moonfmt` 转换固定 HarfBuzz 发布包的 JSON 配置，再核对并应用补丁。源码内容不参与配置转换。颜色结构中与新关键字冲突的 `extend` 改为 `extendMode`，调用方一并修改；两份源码补丁保留原始与结果 hash。依赖版本和许可证保持原值。

| 固定 module | 用到的能力 / 许可 | 必要本地工作 |
| --- | --- | --- |
| [moonbit-community/flate](https://github.com/moonbit-community/flate) 0.8.5 | limited raw DEFLATE、CRC32；Apache-2.0 | 现成 ZIP `read` 急切读取且不承担本项目 CRC/源记录/预算合同；archive 只补 checked ZIP32 索引、缓存与保真封装，不复制压缩器 |
| [Milky2018/xml](https://github.com/moonbit-community/xml-mbt) 0.5.0 | namespace-aware pull reader、source spans、escape；Apache-2.0 | xml 层拥有严格字节解码、禁 DTD、深度预算和文本源片段修改。该版将短 ASCII 的 UTF-16 声明按解码后字符串启发式拒绝；独立解析声明 pseudo-attributes，再以等长空白保留 offset，复用原 parser 验证正文。另补 NS1.0 的 PI target 冒号规则 |
| [moonbit-community/harfbuzz](https://github.com/moonbit-community/harfbuzz.mbt) 0.1.0 | OpenType shaping、glyf DrawFuncs；MoonBit 代码 Apache-2.0，上游附 Old MIT 等完整 notices | 该版 Face metrics getter 在目录准备后仍返回未加载值；直接复用 HeadTable::parse 取 upem。RTL buffer 输出逻辑顺序，核心按 BiDi run 输出视觉顺序。draw 不支持 CFF，入口明确拒绝而不回退成空白字形 |
| [moonbit-community/bidi](https://github.com/moonbit-community/tonyfettes-unicode) 0.5.2 | UAX #9，目标 Unicode 16.0.0；Apache-2.0 与 Unicode 数据许可 | 复用顺序/镜像 API；不重写 Unicode 表，不扩展到完整字素导航 |
| Milky2018/moon_cosmic 0.3.7 | 仅 unicode_linebreak 的断行与字素分段；Apache-2.0 与 Unicode 数据许可 | 复用换行位置和 Unicode 13.0.0 扩展字素，不使用其 editor、排版或字体 owner；断行的 Unicode 15 向量沿用上游 tailoring；字素单独检查完整 Unicode 13 的 602 条标准向量，不声明较新版本 |
| moonbitlang/x 0.5.5 | SHA-256；Apache-2.0 | 字体字节身份与构建补丁核验，不增加全局资源服务 |
| moonbitlang/pdflite 0.3.8 | PDF 对象、序列化、字体子集；Apache-2.0，Typst subsetter 0.2.6 为 MIT OR Apache-2.0 | 当前复用 writer 与 subsetter，将共同 PositionedDocument 编码成 PDF，不创建第二套布局 |

公开 Wasm 包分发项目 Apache LICENSE、完整 HarfBuzz NOTICE 与 UNICODE-LICENSE。固定 Noto 字体、W3C XML 和 POI 测试材料仅保存在私有语料库，保留各自许可和来源；公开 SDK 不打包字体或 fixtures。

P1 使用 harfbuzz/bidi；P3 才因断行需要引入 moon_cosmic 的 unicode_linebreak。传递依赖为 moon_swash 0.1.13、moon_skrifa 0.1.11、moon_yazi 0.1.3、moon_zeno 0.1.4（Apache-2.0；swash Unicode 表为 13.0.0）、async 0.22.4，以及已固定的 harfbuzz/x/flate。解析到 module 不代表全部子包进入浏览器产物；最终 imports 由实际 Wasm 检查。

P4 复用已安装的字素分段，没有新增生产依赖。formats module 显式引用已有 flate 0.8.5，只有 DOCX 私有 wbtest overlay 使用其 ZIP writer 构造独立输入，不进入生产 docx 包的 imports。输入生成不使用 SDK 的 archive/XML writer。

固定 HarfBuzz 的 GDEF API 只暴露 header/class/mark-set，没有 LigCaretList 读取方法。P4 的 [局部 reader](../../modules/layout/src/ligature.mbt) 仅补 coverage 和 caret 格式的预算内读取；轮廓点仍复用 `glyph_contour_point_for_origin`，不维护另一套字体解析或 shaping。格式规则与回退依据见 [DOCX 光标合同](formats.md#p4-当前编辑-api-切片)；上游提供相同能力后替换该 reader 并保留回归。

共享布局的选区区域由 SDK 构造。现有字体和 BiDi 依赖不提供 Writer 的段落 frame 区域，故复用已有区段和字形边界计算。跨页规则依据 [LibreOffice 首尾 frame](https://github.com/LibreOffice/core/blob/d401f2107ccab8f924a8e2df40f573aab7605b6f/sw/source/core/layout/trvlfrm.cxx#L2565-L2651)，原生采集方式参考其[选区句柄回归](https://github.com/LibreOffice/core/blob/d401f2107ccab8f924a8e2df40f573aab7605b6f/desktop/qa/desktop_lib/test_desktop_lib.cxx#L3270-L3305)。与 [ONLYOFFICE 视觉区段选区](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/word/Editor/Paragraph/draw-selection.js#L155-L197)交叉核对；通过范围限已登记同段输入，跨段和跨来源样式另验。此处未移植上游可执行代码或增加依赖；上游依赖提供相同区域合同后替换本地计算并保留回归。

P1 的私有 pdflite content/path 探针继续保留；P3 产品 writer 复用同一固定版本，不依赖探针产物或私有 checkout。授权 notices 随公开 Wasm 包分发，字体和 DOCX/参考 PDF 留在私有库，不捆绑进 SDK。没有 PDF/A 或任意 PDF 编辑承诺。

固定 pdflite 另含严格读取、页树、内容操作符和文字映射；SDK 尚未接入。[P7](../p7-pdf-input.md) 计划复用这些能力并补读取/解码预算，[P8](../p8-pdf-operations.md) 计划复用对象 writer。现有默认解码限制不能当作 SDK 的输入安全合同；本次方案未新增依赖或应用补丁。

## HarfBuzz GDEF 补丁

固定 0.1.0 的 `mark_glyph_set_contains` 把 MarkGlyphSets.coverageOffsets 按 16 位读取，合法组合附加符号输入因而报 `Layout(InvalidFormat)`。[OpenType GDEF](https://learn.microsoft.com/en-us/typography/opentype/spec/gdef#mark-glyph-sets-table) 要求 Offset32。公开 `tools/prepare-dependencies.mbtx` 的 GDEF 补丁只改数组边界/步长和读取函数两条语句，保留原版权头及 Apache 许可；不修改字体、不关闭 mark 特性、不复制整套引擎。

当前原始/修改后 SHA-256 与固定行编辑统一记录在[公开补丁清单](../../tools/harfbuzz-patches/index.json)及其逐文件记录中；记录同时包含下述修复和工作量限制。未知源文件拒绝构建。私有回归覆盖大于 65535 的 coverage offset、截断数组，以及固定 Noto 字体的实际 WasmGC 塑形/PDF 提取。上游固定版本修复此规则后，删除构建补丁，保留回归测试；不保留双路径。

## OpenType 查询读取精简

一次 `LayoutWork` 内最多复用 128 项成功的 Coverage/ClassDef 查询。键包含种类、offset 和 glyph；正引用提示必须指向同一不可变 `BytesView`，其他情况重算。命中仍扣除原查询工作量，错误不登记，不跨塑形调用。私有回归覆盖多源、截断、冷/暖预算、容量和释放；不新增公开 API 或依赖。上游提供等效能力后移除补丁。性能专项按[测试说明](testing.md#独立执行档)延后。

固定 0.1.0 的 [Coverage 循环](https://github.com/moonbit-community/harfbuzz.mbt/blob/143eb274d414145dd9ee4d402ad25b2085f220a1/src/ot/tables/coverage.mbt)和 [ClassDef 格式 2](https://github.com/moonbit-community/harfbuzz.mbt/blob/143eb274d414145dd9ee4d402ad25b2085f220a1/src/ot/tables/gpos.mbt)已检查完整数组，补丁复用这一边界检查，避免逐字段重复验证。

同一准备脚本在完整数组检查之后复用固定 MoonBit 标准库的 `BytesView::unsafe_read_uint16_be`，仅命中时读取 index/class value；目标字形小于范围起点时不读取终点。标准函数本身不查边界，安全前提由原有整表验证和 SDK 32 MiB 字体上限承担；保留线性顺序、无符号值、首次匹配、默认值与截断错误。不新增缓存、依赖、二分查找或另一套塑形。版权头和 notices 保留；未将原始 lookup 代码复制为 SDK 模块。该精简在上游固定版本覆盖后删除，私有回归保留。

当前身份见 [Coverage 补丁](../../tools/harfbuzz-patches/ot--tables--coverage.mbt.json)和 [GPOS 合并补丁](../../tools/harfbuzz-patches/ot--tables--gpos.mbt.json)。

这三个已校验扫描先以剩余预算限制记录数，再在命中或扫描结束前扣除相同数量。保留原工作上限、首次匹配、截断优先级和 sticky 耗尽；私有回归核对逐预算消耗。

准备脚本统一核对原始/修改后身份、有序非重叠行范围及修改后 hash；全部文件验证成功后才写入。已准备文件只验证身份，未知源码或不符预期的修改拒绝构建。补丁来自固定发布包；公开构建不依赖研究 checkout、私有测试库或生成器。详细历史测量留在私有记录，不构成当前功能门槛。

P4 实际原件发现固定 HarfBuzz 0.1.0 默认把 `frac/numr/dnom` 全局启用，使普通数字变成分母字形。[上游 HarfBuzz 14.4.0](https://github.com/harfbuzz/harfbuzz/blob/14.4.0/src/hb-ot-shape.cc#L322-L326) 为分数选择非全局 feature，按上下文掩码应用。SDK 暂用公开 Buffer feature setter 过滤这三个全局项，不修改依赖源码或增加另一套 shaper；自动分数排版未实现，未来固定上游正确实现上下文后应移除此限制。四字体 12 组独立 hb-shape 输出和原 52 行数字原件保留修复前后证据；现有 GDEF/查询成本补丁不变。

## 阿拉伯塑形与附着修复

显式 LTR 排版暴露了固定依赖的反向塑形缺口。现有 Arabic 补丁按原生方向塑形并恢复输出，保留字素内部顺序、行外上下文及原 sticky 工作上限；数字串不做方向反转。依据 [HarfBuzz 原生方向处理](https://github.com/harfbuzz/harfbuzz/blob/11.5.1/src/hb-ot-shape.cc#L549-L603)，主引擎入口另对照 [ONLYOFFICE core](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/DesktopEditor/fontengine/TextShaper.cpp#L727-L744)。GPOS 原有后向查找不再越过未覆盖的最近基字，mark-to-base/ligature 跳过附加符号后停止；依据[最近基字与 coverage 检查](https://github.com/harfbuzz/harfbuzz/blob/11.5.1/src/OT/Layout/GPOS/MarkBasePosFormat1.hh#L108-L152)。五组独立原生向量包含附加符号、连字、混合数字和纯数字；原 44 组及直接/上下文附着回归保持。补丁沿用原许可证头和分发 NOTICE；固定上游覆盖这些缺口后移除本地修改。阶段验证范围见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)，核心通过不代替安装包和浏览器证据。

行外连接上下文补丁复用原 Arabic 状态表，也更新 USE 分支的同一调用者。Buffer 只借用当前段落字符 view 和范围；非法范围先拒绝，clear 清除引用。按 [LibreOffice 的完整字符串与范围调用](https://github.com/LibreOffice/core/blob/1746b16a564f59fcaf8c5670bb292748408da54e/vcl/source/gdi/CommonSalLayout.cxx#L574-L606)保留行外信息，按 [HarfBuzz 五字符上下文上限](https://github.com/harfbuzz/harfbuzz/blob/14.4.0/src/hb-buffer.hh#L98-L103)与 [joining 状态更新](https://github.com/harfbuzz/harfbuzz/blob/14.4.0/src/hb-ot-shaper-arabic.cc#L276-L346)处理前后文。每个被检查字符扣除现有 sticky 工作预算，不把行外字符加入当前 glyph 或公开 SDK 数据。补丁不新增依赖或 SDK API；原版权头与 notices 保留。固定上游具备同等上下文输入和预算约束后删除对应补丁，保留独立原生及 HarfBuzz 回归。历史完整运行 `1791829124994` 为 344/344，17 组独立 HarfBuzz 向量及四组重复 LibreOffice 行几何通过；跨版本实际按键 3/3，4K 删除/恢复约减少 89%，原布局和保存保持。该结果不授予完整 P4、产品延迟预算或可靠峰值通过，详见[测试证据](testing.md)。

固定版本的阿拉伯分支只执行连接形态，没有执行已启用的 `ccmp/locl` 和后续 `rlig/calt/liga/clig`。准备补丁沿用原 GSUB 查表函数，在连接形态前后加入相应阶段；替换后的掩码继续传入下一阶段。GSUB 原有 cluster 传递规则先携带源索引，结束后恢复外部 cluster 与 Unicode，避免一对多替换清空整段 Unicode 属性。Hangul 仍使用的共享形态掩码函数保留。[上游阶段顺序](https://github.com/harfbuzz/harfbuzz/blob/14.4.0/src/hb-ot-shaper-arabic.cc#L251-L320)与固定 LibreOffice 的 HarfBuzz 调用是参考，不增加另一塑形器或按字体特判。

GPOS 在查表期间记录 mark-to-base、mark-to-ligature、mark-to-mark 的相对锚点和父索引，重复附着替换旧相对位置。全部查表后按前向父关系解析，使父字形稍后收到的位置和 advance 调整也生效；RTL 使用视觉原点间距。直接及上下文调用共用此路径。默认可忽略字符在末尾使用字体空格字形并归零 advance；字体没有空格映射时移除相应字形，原 Unicode 文本仍保留。行为参考[上游隐藏默认可忽略字符](https://github.com/harfbuzz/harfbuzz/blob/14.4.0/src/hb-ot-shape.cc#L768-L789)；ZWJ 的现有 `unsupported-emoji` 诊断没有取消。

当前身份见 [Arabic 补丁](../../tools/harfbuzz-patches/buffer--arabic.mbt.json)和 [Buffer 合并补丁](../../tools/harfbuzz-patches/buffer--buffer.mbt.json)。

GPOS 的合并补丁身份见上表；原版权头、Apache-2.0 及公开包 notices 保留。上游固定发布覆盖这些缺口后删除对应补丁并保留回归。两份原字体的 44 项独立向量、混排坐标、直接/上下文双向附着与截断检查见[测试记录](testing.md)。这些有限输入不证明任意字体的替换扩张资源上限或完整阿拉伯文字支持；现有资源上限归[格式合同](formats.md)，未覆盖的扩张与工作量边界不算已验证。

### GSUB 字形分配边界

固定依赖没有限制多重替换的中间数组。共享入口及直接/上下文扩张现检查 65536 项的绝对上限；未匹配的尾部也计入上限。检查在增加目标数组长度前执行，不截断输出。依赖返回 `LimitExceeded`，SDK 映射为既有 `limit-exceeded`；其他字体错误仍按原路径返回。所有 script 的现有 GSUB 调用共用该入口，不在每个特性阶段增加新的额度。

上限取 [HarfBuzz 的最小缓冲区限额](https://github.com/harfbuzz/harfbuzz/blob/14.4.0/src/hb-limits.hh#L29-L45)，本 SDK 不采用随输入增长的系数。极端字体的合法扩张也可能被明确拒绝。上游固定版本提供等效分配边界后删除补丁，保留边界与恢复回归；这项限制不等于查表工作量预算或任意字体的完整资源安全。

当前身份见 [Layout 合并补丁](../../tools/harfbuzz-patches/ot--tables--layout.mbt.json)和 [GSUB 合并补丁](../../tools/harfbuzz-patches/ot--tables--gsub.mbt.json)。

`layout.mbt` 的当前身份还包含两个特性选择入口的索引去重优化。原 `push_unique_int` 每次线性扫描已收集数组；现在按 FeatureList/LookupList 的数量分配局部布尔标记，结果数组继续保留首次出现顺序。无效索引仍忽略，两个不同索引即使指向相同 offset 也继续分别保留。标记长度各不超过 UInt16 表头数量，去重成本按表头数量与已遍历索引数线性增长；没有跨调用缓存、新依赖或 SDK API。固定上游尚无此优化；升级后须重新核对并删除等效补丁。16384 项、required feature、allowlist、指定特性、空表和截断回归的阶段范围见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)。这一优化不限制所有特性表累计解析或 GSUB/GPOS 总工作量。

### 累计查表工作量

一次 `shape_paragraph` 调用的所有字体/script run 共用 67108864 单位的递减计数器。特性选择、GSUB/GPOS、Coverage/ClassDef、GDEF 过滤及嵌套查表的 Result 函数入口和循环迭代计一单位；批量数组初始化、辅助线性扫描及数组移位按处理长度预扣。耗尽状态保持失败，Indic/USE 等试探路径即使忽略中间错误，公共塑形出口仍返回 `WorkLimitExceeded`；SDK 转为 `limit-exceeded` 并回收本次新增轮廓。

字体表初次解析另用同限额。此计数器约束指定查表路径，不是整个文档操作的时间上限，也不覆盖全部字体解析、轮廓分配或进程峰值内存。极端但合法的字体也可能超限；SDK 不截断布局或增加可关闭该限制的公开选项。私有回归覆盖边界、跨阶段/跨 run 共享、完整派生字体和独立恢复字形；当前实际通过情况归[测试记录](testing.md)。固定上游具备等效约束后移除补丁。
