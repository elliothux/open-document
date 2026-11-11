# 测试说明

## 当前兼容证据入口

当前支持与缺口见[兼容性矩阵](compatibility.md)。固定构建的执行证据由私有 `cases/c0-current.json`、`cases/p14-current.json` 及所属阶段 case 维护；这些历史结果不代表当前工作树全量通过。

按[变更范围](testing-scope.md)选择足够检查。逐批结果保留在私有 `cases/history/`，不在本文件累加。

## 环境与入口

使用仓库固定的 Bun、MoonBit、Node 和私有依赖版本，安装说明见[开发文档](development.md)。`test-lab/` 是项目的私有测试资源目录，由[根 AGENTS.md](../../AGENTS.md)统一管理；目录内保留测试源码、输入、预期与执行工具。

| 入口 | 用途 |
| --- | --- |
| 根 `bun run check` / `build` / `api` | 静态检查、构建、API 输出；按变更需要选择 |
| 根 `bun run test` | 完整私有 loop；缺少私有 checkout 或任何阶段失败时，命令应失败 |
| 私有 `bun run test:unit` | 单元检查；局部修复可用 Bun runner 选择具体文件/用例 |
| 私有 `bun run test:corpus` | 输入与独立预期的完整性，不代表 SDK 支持 |
| 私有 `bun run test:browser` | Playwright Chromium；按受影响用例选择，需可用的目标产物 |
| 私有 `bun run browsers` | 仅安装锁定 Chromium；已有可用环境不重复安装 |

测试还需 `unzip`、`xmllint`、Poppler 工具、HarfBuzz 14.4.0 和 qpdf 12.4.1。字体与 PDF 诊断基线依赖这两个固定版本。`unzip -l` 支持月日年与 ISO 日期输出。ZIP 全语料检查使用 30 秒预算，保留逐成员和 CRC 校验。

完整 loop 冻结源码、输入与预期，构建一次；MoonBit、安装后的 Node 包和生产 Worker 消费同次产物。`cases/suites.json` 管理必选用例与包内容。局部运行是对应范围的证据，不冒充完整运行。

局部 Chromium 检查使用 `bun run test:browser -- <spec-file> --grep '<case-name>' --reporter=list`，按需增加 JSON 报告器。默认完整报告器核对全部必选清单，会拒绝局部选择；它用于完整 loop，规则保持。局部结果只报告实际执行的用例和环境。

测试过程自动化使用 `.mbtx`，TypeScript 用例使用 Bun/Playwright。私有 `cases/` 清单登记来源、许可、固定输入 hash、操作、独立预期、支持范围与验证状态。路径从私有仓库根目录解析：

- `cases/suites.json` 管理必选执行与归档内容；修改 MoonBit 用例时同步登记 overlay 和测试名称。
- `cases/compatibility.json` 索引兼容输入。
- `cases/catalog.json` 索引自建资产。

输入来源与许可要求见[语料管理](corpus.md)。准备好资产只证明输入可用，验证状态以实际执行结果为准。

## 证据与正确性

参考实现、兼容行为、测试设计与基准均优先使用 ONLYOFFICE core/sdkjs，其次使用 LibreOffice；Collabora 仅补充浏览器交互案例。参考冲突时，在声明的格式范围内优先采用 ONLYOFFICE，用户明确指定的行为除外。适配案例时保留许可、来源和独立预期；参考通过不代表完整 Microsoft Office 兼容。

已有 LibreOffice 基准保留真实来源，随对应功能变更按上述顺序补充或修正；不批量重采历史资产，也不把它们改标为 ONLYOFFICE 结果。

分别检查核心行为、真实浏览器 WasmGC 和文件输出。保存变更用独立 ZIP/XML 工具检查正文及非目标内容；布局/PDF 变更用固定字体、参考几何和 qpdf/Poppler。真实浏览器结论使用目标浏览器中的证据。

产品代码实现输入和格式驱动的通用规则，具体样本与预期放在测试中。保留断言强度；golden 和阈值变更依据独立证据。参考冲突先查真实文件、固定版本和上游规则，沿用用户已确定的选择。

记录输入、源码/工具版本、环境、命令和结果。成功退出且执行了目标用例才算通过；缺工具、零用例、超时和未执行都不是通过。旧失败保留原判断，不因后续修复改写。

P6 的定向功能、共享输出回归及参考应用重开见 [P6 检查依据](../implemented/p6-pptx-editing.md#足够检查与依据)和私有 `cases/p6-pptx.json`。它复用本节的文件与 Chromium 检查，不重做 P4/P5 全量验收，也不扩大历史系统输入法证据。

P7/P8 的五条 PDF 功能链与固定输入归私有 `cases/p7-p8-pdf.json`。执行 `tests/browser/pdf.spec.ts`、`pdf-interaction.spec.ts`，使用上述局部报告器；qpdf 检查结构、源压缩流、页树和字段/批注字典，Poppler 检查文字与 CropBox 裁剪后的选定像素。正向输入含 ONLYOFFICE 模板、LibreOffice 导出和独立构造的 PDF，产品 writer 不作为唯一预期。共享字体、绘制和 PDF 对象编码只重跑对应 DOCX 图片、XLSX 打印及 PPTX 图文/输入链；完整 loop 和性能专项仍不作为该阶段交付条件。

## 修复步骤

1. 读取私有 `.temp/runs/<id>/summary.md`、首个失败日志和对应 `failures/*.json`。
2. 确定输入、操作、预期和实际差异，区分产品、参考、数据和环境问题。
3. 使用记录的参数和安全环境配置，在新 attempt 复现，保留原有结果。
4. 修复共享规则，运行直接受影响的检查；两次尝试无新证据时重新判断路径。
5. 保留简短复现与首个失败，按本文件的范围规则选择后续检查。

重放使用新 attempt，保留旧结果。临时输出统一放在 `.temp/`；昂贵运行前检查根/私有合计容量，达到 2 GiB 停止新增。保留一个当前运行和一个必要基线，按已有授权清理任务自己的缓存。

## 负向验收

修改 runner、判定器或报告器时，选择对应错误预期、缺输入、超时或构建失败探针，确认失败可见且报告可读。普通产品修复验证对应产品行为；私有 `test:negative` 按判定器变更需要选择。

## 独立执行档

现有 `test:performance`、`test:native-performance`、`test:cpu-profile` 延后，只有功能被卡死或资源问题阻断时才选择最小诊断。保持已有输入、历史、队列、布局和 Canvas 安全上限及释放检查。

`test:explore`、`test:isolation`、`test:office-candidates` 和 `test:replay` 分别用于扩展探索、本地 Docker 隔离、参考输入准备和干净检出诊断。需要对应任务时再用，不作为日常功能开发的固定步骤。Docker 不挂载凭据、HOME 或 socket，不上传私有文件。未启用的 CI 模板不算运行证据。

## 干净检出复现

复现安装或打包问题时使用新 checkout 与固定私有 gitlink，按开发文档安装依赖。如实记录已有系统工具和本地 URL 覆盖。文档修改使用现有环境完成 diff 和一致性检查。

## 隐私与独立验收

所有第一方测试、输入、预期和详细报告保留在私有仓库；公开构建不依赖它们。本地可读 checkout 不属于盲测隔离。未经用户授权不上传、发布、提交或推送测试资产。

## 文档与证据索引

格式合同按[目录](formats.md)分为共享规则和四格式专题。测试用例选择归[检查范围](testing-scope.md)，逐批结果与原限制归私有 `cases/history/*.json` 的 `history` 字段，入口为 `cases/history/README.md`。历史记录不授予当前工作树资格。

兼容性文档的证据入口表读取私有 `cases/documentation.json` 和 `cases/ledger.json`。文件账本按 SHA-256 合并来源。C0 打开证据保留构建、环境和扫描指纹，其他历史清单先登记来源。功能与缺口归所属合同。

从 `test-lab/` 运行 `moon run tools/update-documentation.mbtx` 更新证据表。有原始 C0 扫描记录时，可运行 `moon run tools/update-compatibility-ledger.mbtx` 刷新文件账本。两条命令均接受 `--check`，使用[固定工具链](development.md)。生成过程只核对现有记录。
