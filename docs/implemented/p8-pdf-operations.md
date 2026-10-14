# P8 PDF 页面操作、批注与表单保存

状态：`implemented`，2026-10-14。在 [P7](p7-pdf-input.md) 的同一源对象会话中完成页面整理、便笺/高亮、普通文本字段/复选框、撤销和保存重开。实际 API 与嵌入示例归[格式合同](../references/formats.md#pdf-输入与文档操作)，阶段状态归[路线图](../references/roadmap.md)。

## 已交付结果

| 操作 | 当前实现 |
| --- | --- |
| 页面 | 完整排列重排、90° 倍数旋转、删除并至少保留一页；稳定页身份、继承资源和页框保持 |
| 批注 | 添加、修改、删除普通 Text 便笺和 Highlight；核心文字四边形转回源坐标，生成 normal appearance |
| 普通 `Tx` | 单行/多行纯文本、MaxLen、只读保护；修改 `/V`，保留 `/DV`，同步全部 widget 外观 |
| 复选框 | 读取实际导出状态名，同步字段 `/V` 和每个 widget `/AS`，保留 Off/on appearance |
| 历史 | revision 冲突拒绝；局部对象补丁、100 项/8 MiB 有界 undo/redo；失败不增 revision |
| 保存 | 原对象图完整写出；保留非目标对象与压缩 stream；无编辑和全部撤销返回原字节 |

每次操作先构造受影响对象候选，检查引用、能力、几何、资源和预算，再原子提交。历史不保存整个文件或整个文档快照。保存独立绑定 revision，不清空历史，也不替换原始基线。writer 重建 xref/trailer，移除旧增量与线性化声明；不把页面重新渲染成新文档。

页面重挂前物化有效继承属性。旋转只改 `/Rotate`。删除当前页后选原位置的下一页，否则上一页；undo 恢复身份和源关联。搜索结果按新页序保留，删除页的结果移出。

高亮使用 P7 最终 quad，保留旋转和跨行形状；外观按 ONLYOFFICE 的透明度与 Multiply 语义生成。便笺使用简单路径图标。未知类型、锁定、回复链、动作、富文本、结构引用和无法安全重建的批注受保护。

文本外观复用已有塑形、BiDi、文本框布局和字体子集 writer，仅重建目标 widget。支持基础 DA、Q、纯色 MK 与普通实线边框；固定字号溢出拒绝，字号 0 有界缩小。调用方可用 `profile.form` 指定已供应的可嵌入字体。缺少可用字体、权限限制或任何 widget 无法同步时，整次提交失败。

`PdfEditor` 复用 viewer，增加页面按钮、批注/字段列表与原生 textarea/checkbox 草稿面板。应用前不改源。组合期间禁止提交/输出，切页或换目标前要求应用或取消。保存等待已接受操作；关闭等待在途操作。提交后呈现失败保留已提交内容，停止新编辑，允许保存、刷新或显式撤销。

## 保护规则与限制

直接页引用随稳定对象保持。删除会破坏保留页链接、书签或命名目标时拒绝。PageLabels、结构树、文章线程、页号目标和未知扩展关联保护重排/删除。包含 widget 的页不删除，避免引入表单树清理。各操作按影响范围判断，保护原因随查询返回。

已签名/认证文件只读且未验证；加密、损坏或需修复的文件不能进入可写会话。非零对象代数因固定 writer 限制保护编辑。未知对象及未引用对象继续保留；删除不清理附件、历史敏感数据，不能用于涂黑、脱敏或安全擦除。

不新增/复制页面，不跨文件合并，不编辑任意正文/图片，不设计表单、扁平化、OCR、签名或 PDF/A/PDF/UA 转换。文本 rich text、comb、password、file-select、格式/校验/计算动作、签名、列表/下拉、radio/pushbutton、XFA、NeedAppearances 全局修复和虚线/圆角等未支持 widget 属性受保护。现有 Off/on 外观缺失时不猜测复选框符号。

默认每文档批注/widget 各 4096、字段树深度 64、字段/便笺 32767 UTF-16 单元、单高亮 4096 quad、单次候选及历史合计 8 MiB、输出 64 MiB。源 stream 共享，不在历史中重复保存图片。完整读取与资源限制归[格式合同](../references/formats.md#pdf-输入与文档操作)。

## 足够检查与依据

私有 `cases/p7-p8-pdf.json` 的功能链覆盖页面整理/undo/保存重开，便笺/高亮修改删除，以及多 widget 文本与非 `Yes` 复选框填写。qpdf 检查页树、QuadPoints、字段状态、保留的未知字典和未改压缩流；Poppler 独立提取两处新字段外观文字。

原生输入链覆盖拖选复制、缩放、搜索定位、组合屏障、草稿取消、应用后立即保存/关闭，以及受控呈现失败后的保存和撤销。恢复链覆盖签名、保留目标关系、过期 revision、输出超限和全部撤销原字节。根静态检查、release 构建、API 生成及定向共享回归记录在同一私有证据中。

未运行完整 loop、性能专项、其他浏览器、Windows/参考应用 GUI、VoiceOver 或新增系统输入法验收。独立 qpdf/Poppler 检查证明指定文件结构、文字和像素，不扩大为任意 PDF 阅读器保真。

机制参考 ONLYOFFICE [高亮外观](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/SrcWriter/Annotation.cpp#L994)、[实际复选框导出值](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/pdf/src/forms/base/basecheckbox.js#L688)和[字段写出](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/SrcWriter/Field.cpp#L514)。保存复用固定 pdflite [对象 writer](https://github.com/moonbitlang/office.mbt/blob/2f08f3b8041d9098d258969fe3902b34585163cc/pdflite/pdf_writer_classic.mbt)。上游含跳过的示例测试不计入通过证据，不复制 AGPL 实现。
