# 测试规则与修复 loop

本文件拥有测试规则与反馈流程的文档合同；可执行实现、输入和结果保留在私有 `test-lab/`。产品范围与各阶段验收归[路线图](roadmap.md)及对应阶段方案，不能由测试反向扩展。除特别说明外，本文命令及 `tools/`、`cases/`、`.temp/` 路径均相对 `test-lab/`。

## 环境与入口

需要根项目指定的 MoonBit/Bun、可用的 Node（Playwright CLI）、Playwright 固定 Chromium，以及 POSIX 环境的 Git、tar、cp、unzip、xmllint、qpdf 12.4.1、HarfBuzz 14.4.0 的 `hb-shape` 和 Poppler 26.05.0 的 `pdftotext` / `pdftoppm` / `pdfinfo`。生成自建 DOCX 另需 zip。`pdftotext` 不在 PATH 时显式设置 `OPEN_DOCUMENT_PDFTOTEXT` 为可执行文件路径。首次运行需联网获取锁定依赖与浏览器；日常使用固定语料，不临时抓取未知文档。这是当前 macOS 开发执行器，不承诺 Windows shell 等价运行。

在公开根先 `bun install --frozen-lockfile`，并用 `git submodule update --init --recursive` 获取固定版本的私有 `test-lab/`（需要仓库权限及远端已存在对应 commit）。然后在 `test-lab/`：

```sh
bun install --frozen-lockfile
moon update
bun run browsers
bun run test
```

`moon update` 更新工具的包索引，不升级脚本中固定的 async@0.22.4。公开 module 固定 flate/xml/harfbuzz/bidi、cosmic 的 Unicode 断行包及 PDF writer pdflite；版本、许可和固定 GDEF 修补见[依赖记录](dependencies.md)。测试脚本的 async 与独立 PDF probe 不进入 SDK；P3 的 pdflite writer 已进入公开构建。

目前只验收随 Playwright 1.63.0 安装的 Chromium；没有冒充 Firefox/Safari 或任意 runtime 已验证。P1/P3 使用私有固定 Noto 字节，不依赖浏览器系统字体。P3 的 LibreOffice 参考使用相同的四个 Noto Sans 样式文件与固定字体替换 profile。

`tools/loop.mbtx` 单次执行检查、构建、临时 MoonBit 测试组装、判定器/语料检查与浏览器验收，不自动写源码、更新 golden 或无限重试。修复循环由维护者或授权 Agent 调用这个确定性执行器构成。

完整运行还在私有临时目录组装一个仅含公开源码的独立 Git 工作区，排除旧 dist/node_modules，安装锁定依赖并重新检查/构建。两包实际生成 tarball，读取 archive entries，与 `cases/suites.json` 的公开文件清单精确比对：多出私有文件、遗漏 Wasm、重复或越界路径均失败。临时 Git 边界避免父目录 ignore 规则导致 lint 零文件。执行器不创建 commit，也不触及真实仓库 index。

`cases/suites.json` 拥有 Moon 测试 overlay、必选名称、P0–P3 浏览器案例与包文件清单。新增 Moon 包测试在这里登记 source/destination/names；执行器组装后核对 outline 和实际执行数量。浏览器核对所有必选案例的精确集合及一次通过；Bun 产出 JUnit，禁止零用例、skip/failure/error，私有 lint 拒绝 focused/disabled tests。所有维护的 `.mbtx` 都做 deny-warn 检查和格式检查。完整入口不接受筛选参数；P1–P3 是 SDK 行为验收，P7 仍只有语料准备检查。

P1 在真实 Worker 中与独立 `hb-shape` 比较 glyph/UTF-16 cluster/advance/offset，另检查 Canvas 非空像素和几何边界、fallback/RTL/缺字、资源复用与失败恢复；PDF 候选单独构建 release WasmGC，在浏览器消费同批轮廓并检查 imports。记录字体 hash、Wasm 原始/gzip/Brotli 大小、冷/热调用、缓存字节和 JSON 批次大小，尚无 WasmGC 峰值内存测量或性能 SLA。

P2 的快测覆盖源片段、OPC、ZIP 及 W3C NS1.0 的 DTD-free 子集；真实 Worker 使用自建包和四个固定 POI DOCX，执行 no-op、两个 revision 编辑和重复保存。独立 unzip/xmllint 验证输出 CRC、结构、文本与每个非目标 part hash；预算 N−1/N/N+1、压缩炸弹、metadata/编码/关系/签名和原子失败另有案例。保存后的 SDK 自读不替代独立判定；此检查不包含参考 Office 应用重开、完整 schema 或布局。

W3C XML namespace 的部分错误只写 xmllint stderr，退出码仍为零；对应 oracle 同时核对 stderr 的 namespace/parser error，不能将零退出当成有效 XML。SDK 的失败必须按自己的 `DocumentError` 身份判断，不能吞掉未知错误。

P3 分开验证布局、Canvas 和 PDF：三个真实 POI DOCX 对照固定 LibreOffice 参考的页数、逐词文字及行首坐标；基础表格另检查参考区域的背景和文字颜色。PDF 经 qpdf 检查、Poppler 实际提取和栅格化；关闭 ActualText 后仍检查连字、组合字符和 CJK 的 ToUnicode，避免行级替代文字掩盖字体映射缺陷。内联 RGBA 图片检查 Canvas 和 PDF 的实际四象限颜色。DPR 2 下 6/8/11 pt 的页面分别检查实际墨迹；它不是全字号主观阅读质量声明。

Canvas/PDF 在相同 72 DPI 下双向检查实体墨迹的一像素邻域覆盖，缺失计数必须为零。实体墨迹取通道值小于 128，目标覆盖取小于 250，允许 Skia 与 Splash 的边缘抗锯齿差异；颜色、页面、文字和几何仍有独立断言。初始判定器对细线使用同一实体阈值产生误报，失败证据保留；依据独立 PDF 栅格和实图校准后冻结当前规则，不在测试过程中自动调整。此规则不是 SSIM，也不宣称和 Word 逐像素相等。

`cases/p3.json` 固定 LibreOffice 25.8.2.2、输入、字体、profile 和三份参考 PDF。生成校准入口是 `OPEN_DOCUMENT_LIBREOFFICE=<fixed-app>/Contents/MacOS/soffice moon run tools/reference-p3.mbtx`：核对引擎版本、字体和 profile hash，在唯一临时目录转换两次，再与冻结参考的 72 DPI 页面 PNG 比较；不覆盖参考。2026-10-10 校准 `1791633451630` 的六页 PNG 在三次渲染间 hash 完全相同，无重复环境像素噪声。预览仍只对声明的有限特征负责；原 POI GIF 是浮动 anchor，保留并作为明确拒绝案例。

基础输入记录 Worker 创建、解析、首次/暖布局、单页绘制、PDF 输出和布局 JSON 字节数。三个 POI 的 `layoutMs` 包含预览准备与首帧，单独 `drawMs` 是额外 Canvas 重放；二者不能混为纯核心时间。输入、字体和输出 hash 与环境一并保存。没有可靠的 WasmGC 峰值内存测量，报告明确 `measured: false`，不拿 linear memory 冒充；当前也没有延迟 SLA。

`bun run test:unit` 可独立运行，不要求旧运行目录；其中 corpus readiness 仍需独立 XML/PDF 工具。需要当次构建证据的 qualification/entrypoint 测试归 `tests/integration`，由完整入口提供新构建、tarball 和 Moon 日志后执行，并有独立 JUnit。`bun run test:corpus` 只验证样本完整性与独立基线，不能替代 SDK 兼容性测试。

## 证据与正确性

- 私有 `.temp/runs/<id>/` 保存各阶段 log、`status.json`、浏览器 JSON/HTML、失败 trace 和截图；首次失败保留，不以重跑覆盖。
- `evidence.json` 记录真实源码文件 hash、私有测试/输入 hash、Wasm/JS 产物 hash、锁文件、工具链与环境；未提交源码不冒充已提交 HEAD。浏览器实际版本在 Playwright annotations。
- 成功要求 expected/selected/executed 对齐且没有 skip/retry。零案例、缺参考、缺产物、基础设施错误、超时不算 PASS。
- 验证真实 release WasmGC 与正式 TS API/Worker，不用 native/moonrun 替代浏览器。Moon 测试运行在复制的源码 + 私有测试 overlay，不能修改原始源码。
- 浏览器检查的是实际 `dist/`；检查浏览器运行期间公开源码/配置、私有测试/配置/数据、Wasm/JS 产物 hash 未变化。这不是从构建开始的文件锁；不要并行修改正在验收的工作树，完成编辑后重新构建验收。
- UI 文本只是观测值，预期来自固定 case；纯文本相等不证明布局、IME、文件格式或 PDF 输出正确。

## 修复步骤

2026-10-10 当前 P0–P3 完整验收：根 `bun run test` 成功，17 个 MoonBit、16 个 Bun 单元、6 个集成与 55 个浏览器案例全部执行通过。环境为 macOS 27.0.1 (26A434) arm64、Node 24.21.0、Bun 1.4.2、Moon 0.1.20260920、Playwright 1.63.0/Chromium 153.0.8010.12。私有运行定位 `1791634601274`，源码清单摘要 `294bdb005a5da2a51998c58041fc46b6fb64ab066a6dde8556552faffe10489f`；公开检查、release 构建、公开独立 snapshot、实际包 inventory 和 browser sourceUnchanged 均通过。源码与产物未提交，不冒充 HEAD 验收。

负向判定定位 `1791634490093`：错误 oracle 55 选中/54 通过且恰好一个预期失败；缺项探针 1 选中/1 通过仍整体失败。包装命令成功确认了两次底层非零退出，随后重跑上述正常完整 loop。此前真实失败与 trace 均保留，未通过重试或覆盖旧目录取得通过；初始像素判定器的校准及其独立证据见上文。

1. 从一个失败的具体 case 开始，保留输入、操作、expected/actual、运行身份与错误阶段。
2. 区分 SDK 缺陷、参考答案问题、未承诺能力、样本损坏、环境/工具错误。原始失败保留分类，不把其直接移出分母。
3. 在公开契约范围内缩小复现，修复一般规则。禁止 fixture 名称/hash/测试 ID 特判或把核心计算移出被验证路径。
4. 开发时可用 `bun run test:unit` 或 Playwright `--grep` 定位；选测不能作为完整 P0 通过。完整报告器会拒绝缺少必选案例的验收。
5. 修复后跑完整 `bun run test`。公共基础包变更扩大到所有已支持依赖格式；未来按量引入 nightly 分片，当前没有已配置的定时任务。
6. 新的缺陷留下最小回归案例；只有独立证据支持且人工批准时才改 expected、golden 或阈值。`moon test --update` 不是消除失败的捷径。

连续尝试不缩小原因、独立参考冲突、需要新权限/许可/产品范围时停止扩大修改，报告证据。不得自动 commit/push 或发布私有结果。

## 负向验收

P0 应实际执行一次错误预期探针，并确认非零退出、具体差异及 failure artifact：

`bun run test:negative` 自动执行两次独立探针：全选案例但故意改错一个 expected，必须恰好失败一项；只选一个正确案例，该案例通过但完整验收必须失败。每次使用唯一 `.temp/failures/<id>/`，保留底层非零退出和报告，包装命令只有确认这些预期失败后才成功。先运行正常完整 loop 生成当前构建，探针后再跑完整 loop。

```sh
OPEN_DOCUMENT_ORACLE_PROBE=1 OPEN_DOCUMENT_RUN_DIR=.temp/oracle-probe bun run test:browser
```

此开关只在私有测试端改变一个断言的 expected，不改产品实现或冻结的数据。它用于证明判定器会失败，不算产品缺陷，不允许放宽断言后对外声称通过。随后正常完整运行应通过。

根入口另有回归测试：私有目录不存在和空 submodule 目录均须在 2 秒内正常返回非零，而不是向父目录递归查找同名 script。判定器单元测试覆盖空清单、重复项、缺项、额外文件与零执行。

## 干净检出复现

经授权提交两个仓库并固定 gitlink 后，在私有根运行 `bun run test:replay`。它要求两个工作树干净，从本地 Git 历史新 clone 主仓库，再在临时 clone 内将 submodule URL 指向本地私有仓库并初始化固定 commit；不改原仓库配置，不联网 push。随后安装两个 frozen lockfile、显式安装 pre-commit，并从新根运行完整 loop，再验证 hook 拒绝故意类型错误且接受正常代码。日志位于 `.temp/replay/<id>/`。

该检查没有原工作树的 dist/node_modules/references，但复用系统工具链、依赖下载缓存与已安装浏览器；它证明新检出可复现，不等于裸机或远端权限验证。

安装公开 hook 后，可以用 `moon run tools/check-hook.mbtx .temp/runs/<id>` 检查它：工具只在该次运行的临时 SDK 副本加入一个故意的 TS 类型错误，执行实际 hook 并检查 TS2322，再将该临时文件移到运行证据目录。最后检查真实公开工作树。该检查不修改或暂存真实产品源码。

## 隐私与独立验收

产品、研究、测试规则与 loop 设计文档统一在父仓库 `docs/`；全部测试代码、语料、具体预期、原始报告、判定器、执行脚本和测试技能仍私有。`test-lab/` 不维护第二套 docs。公开 hook 只做公开检查。运行未经审查的外部 PR 时不挂载私有 token/语料，不从 privileged workflow checkout 并执行任意 PR。

当前本地 checkout 对同一 Agent 可见，因此没有盲测隔离。以后需要独立 holdout 时，由受限环境持有样本/预期，只返回受控结果；分目录不构成访问控制。公共开源样本仍遵循原许可，私有保存不改变权利。

当前不做自动 Office 服务、不上传原文档或日志、不部署对象存储、不配置跨仓凭据。私有仓库与主仓库 gitlink 已获授权本地提交；尚未推送。推送时必须先让私有 commit 在远端可获取，再推送引用它的主仓库提交。运行证据仍记录内容 hash，以覆盖未提交修改。
