# 语料管理

P7/P8 的 PDF 输入、许可、固定 SHA-256、操作和证据统一登记在私有 `cases/p7-p8-pdf.json`。ONLYOFFICE `document-templates` 固定 `71430c9f183489e8912f54f9dc859e369cf0dfb4` 的 new/sample PDF 保留 LICENSE/AUTHORS；LibreOffice 补充输入复用已归档 P6 输出及其来源。独立 PDF fixture writer 只在私有测试中生成组合输入；qpdf/Poppler 提供结构、文字和像素预期，公开构建不读取这些资源。

复用现有私有输入、字体和独立预期，按内容身份去重。新增样本直接覆盖当前功能缺口。

P9 复用上述 DOCX、P5 网格、P6 ONLYOFFICE 派生 PPTX 和 P7/P8 PDF fixture，以及同一批授权字体；没有新增兼容集或截图金样本。默认 UI 的操作、当前产物与定向检查边界登记在私有 `cases/p9-ui.json`，格式预期继续由原有输入与独立检查提供。

## 当前数据

实际来源、许可、hash、操作、预期和验证状态由 `test-lab/cases/` 清单维护。文档说明用途与边界，详细记录由该清单定位。

| 数据 | 用途与边界 |
| --- | --- |
| 自建文本、XML、DOCX、PDF | 基本操作、未知内容保留、非法输入和预算；预期不由 SDK writer 生成 |
| Apache POI 的四份 DOCX | 正文、表格、分页、图片关系；浮动 anchor 输入保留为拒绝案例 |
| `cases/lo-docx.json` 的 20 份 LibreOffice 原件 | 固定来源的读取/保留回归，不自动授予布局支持 |
| P4 原始与派生 DOCX | 选择/输入、跨 run/段落、表格同格、保护结构和错误恢复 |
| 固定 Noto 字体及 HarfBuzz 向量 | Latin、Arabic、CJK 的 glyph/cluster/advance/offset；OFL 与来源随资产保留 |
| 固定 LibreOffice PDF、布局 XML、LibreOfficeKit 记录 | 页面、行、光标、选区及保存重开；版本、字体和 profile 与预期绑定 |
| W3C DTD-free Namespaces 1.0 子集 | XML 接受/拒绝；不代表全套 XML 符合性 |
| Unicode LineBreakTest 选定向量 | 与所用 Unicode 数据及声明 tailoring 对齐，不代表完整 UAX #14 |
| PDFium PDF 与原始 `.in` | 独立 PDF 输入；有修复警告的文件不作为合法 writer golden |

P4 验证范围与证据入口见 [P4](../implemented/p4-docx-editing.md#验证依据与边界)。只读、拒绝、准备完成、SDK 正向编辑和参考重开分别记录，不能互相抵扣。Windows/Word 验收跳过；Office 候选工具不创建已审核 golden。

普通 Chrome 系统输入、LibreOffice GUI 观察和最新功能运行分别索引在私有 `cases/p4-native-input-current.json`、`cases/p4-office-gui-current.json`、`cases/p4-input-transport.json`。保留已有紧凑证据；不把历史记录作为未来构建的自动 PASS。

## 后续有选择地引入

测试用例与基准优先取自 ONLYOFFICE core/sdkjs，其次使用 LibreOffice，Collabora 补充浏览器交互案例。只引入当前支持范围需要的案例，先检查来源、许可和对应上游断言。已有资产保留实际来源，不因优先级变化批量重建。

每个新输入登记来源 revision/路径、内容 hash、许可、特征、操作及独立预期。派生输入保留原件关联和具体改动，不能算成新的独立来源。生产工具或版本未知时如实记录 unknown。

参考结果另记录引擎、OS、字体、profile 和诊断。SDK 输出是比较对象，不能直接提升为 golden。参考有差异时保留原始差异；只有独立依据支持的行为变更才能修改预期。

## 增长策略

先用最小真实反例，再补必要组合与边界，以覆盖当前功能衡量进度。输入须有明确来源；不自动执行宏、脚本或外链请求。

`bun run test:corpus` 只验证数据完整性及独立基线。日常测试使用已入库资产，不依赖研究 checkout 或网络下载。现有 `tools/import-corpus.mbtx` 和 `tools/prepare-corpus.mbtx` 用于需要时导入/生成，拒绝覆盖已有资产；重建在独立临时位置比较并审阅。

原件、许可、预期和必要失败复现保留。临时日志与缓存放 `.temp/`，遵守根 AGENTS 的容量限制；不保留完整历史构建来证明 fixture 身份。第三方许可随资产保留，字体不因本机可用就获得再分发权。

## P5 XLSX 输入

私有 `cases/p5-xlsx.json` 登记 ONLYOFFICE document-templates 固定 revision 的 `new/en-US/new.xlsx` 与 `sample/sample.xlsx`。原始输入、Apache-2.0 LICENSE 与 AUTHORS 保留在 `fixtures/upstream/onlyoffice-p5/`；前者验证值编辑，后者验证未支持结构化公式的缓存/只读边界。手工构造的公式、样式、日期和网格输入及独立预期在对应功能用例中维护。运行范围见 [P5](../implemented/p5-xlsx-editing.md#足够检查与依据)，准备状态与 SDK 通过分开记录。

## P6 PPTX 输入

私有 `cases/p6-pptx.json` 登记相同固定 ONLYOFFICE revision 的 `new/en-US/new.pptx` 与 `sample/sample.pptx`，原件、Apache-2.0 LICENSE 和 AUTHORS 位于 `fixtures/upstream/onlyoffice-p6/`。基础原件验证占位符、无编辑保存；复杂示例验证诊断与源保留，不能作为整稿正向渲染输入。

双页共用母版、跨 run 编辑、图文覆盖、裁剪/旋转、组合、字段和失败输入在私有功能用例中从原件及独立源属性构造。Canvas/PDF 预期取自固定源几何、手工 RGBA 色块和独立文件工具；不由 SDK writer 生成自身预期。执行范围及 LibreOffice 独立重开依据见 [P6](../implemented/p6-pptx-editing.md#足够检查与依据)。
