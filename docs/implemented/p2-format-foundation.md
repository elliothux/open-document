# P2 — 文件与格式公共底座

状态：`implemented`，2026-10-10 获得本地 `verified` 证据。使用者可以把 Transitional DOCX 字节与显式预算交给 `FoundationClient`，查询有稳定节点定位的正文段落/run/text，凭预期 revision 替换一个已知 `w:t`，无编辑保存或重复保存。文档权威状态在 MoonBit；宿主只调度 Worker 与收集字节。持续维护的支持范围、错误和预算见[格式合同](../references/formats.md)。

`core/archive` 先检查 ZIP 目录与 local/central metadata，再按需执行有界 stored/deflate 读取、CRC 与实际解压长度核对；同一条目重复读取不重复解压或扣预算。`core/xml` 严格解码 UTF-8/BOM UTF-16 LE/BE，保留 namespace-aware 源片段；`core/opc` 拥有 content types 与按 owner 定义的关系身份。`formats/docx` 只维护原文档和已知节点的替换映射，不建立第二棵可编辑 DOM。

无编辑保存保留所有 part 的解压后字节；局部编辑只重写主 XML 的文本片段和必要 `xml:space`，保留未知属性、namespace、节点、注释、PI、customXml 和关系。未修改条目复用原压缩记录，修改条目 stored 写出。事务在 XML、entry、累计解压和输出预算校验成功后才增加 revision；失败不改输入或编辑状态。保存还检查此前未读条目的完整性，不依靠阅读器修复。

2026-10-10 的完整测试使用自建 DOCX/XML、20 个 W3C Namespaces 1.0 的 DTD-free 输入及四个固定 Apache POI DOCX。MoonBit 快测与真实 Chromium release WasmGC 分别执行；输出由独立 unzip/xmllint 检查 CRC、XML、结构与非目标 part SHA-256。覆盖 N−1/N/N+1 预算、惰性/缓存读取、损坏/重复/重叠 ZIP、descriptor、压缩炸弹、编码/实体、OPC 路径与关系、签名限制、过期 revision、原子失败恢复和关闭。输入与许可管理见[语料管理](../references/corpus.md)。

Ponytail Review 修复了短 UTF-16 声明的上游启发式冲突、处理指令 namespace 校验、stored 条目的分配前长度校验，以及关闭后查询的错误身份；叶节点检查使用源树的顺序性质，移除每次替换扫描整棵树的额外工作。具体上游缺口见[依赖记录](../references/dependencies.md)。

本阶段没有分页预览、IME、跨 run 编辑、Word/LibreOffice 应用重开或 OOXML 全 schema 验证。Strict、加密、多磁盘/ZIP64、宏主部件和签名安全改写被明确拒绝；不承诺整个 ZIP 字节一致或任意 OOXML 格式兼容。页面布局与 PDF 输出归 [P3](p3-docx-preview.md)，交互编辑归 P4。
