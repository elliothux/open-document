# P3 — DOCX 预览与可移植 PDF 输出

状态：`implemented`，2026-10-10 获得限定范围的本地 `verified` 证据。开发者可提供 Transitional DOCX 和授权字体，将只读分页预览嵌入 Web 应用，并下载由同一布局生成、可提取文字的 PDF。SDK 仍为 WIP，尚未发布；交互编辑归 P4。

## 结果与职责

复用 [P1](p1-sdk-foundation.md) 的字体/塑形链和 [P2](p2-format-foundation.md) 的包/源片段权威。DOCX 负责 Word 样式、页面与对象语义；MoonBit layout 负责断行、字形位置、源范围和分页；TypeScript 负责 Worker、资源解码、Canvas 重放与宿主生命周期。PDF writer 消费同一页和字形结果，不重新排版。

实现基础段落、样式继承、主题 Latin 字体、粗斜体/字号/RGB、行距/缩进/对齐、空段落、显式分页、中英混排与基本双向文本。固定列宽表格支持均匀网格、填充、对称 padding、最小行高和整行换页；内联图片支持 extent 与 RGBA。页几何与分页不受视口缩放或 DPR 改变。

`DocumentPreview` 提供滚动、切页、缩放、键盘、文本与诊断、PDF 下载。取消与销毁释放自己拥有的 ImageBitmap、Canvas、监听器和 DOM，保留宿主节点；调用方释放 client/Worker。基础语义输出不是完整文档无障碍支持。

`layout(profile)` 返回带 revision、字体/profile 身份和会话内 ID 的派生结果；资源或正文变更使布局失效。预览下载始终带自己的 ID，旧视图不能悄悄导出新布局。PDF 使用 TrueType 子集、字体宽度、CIDToGIDMap、ToUnicode、ActualText 和图片 alpha mask；输出超预算明确失败，不交付部分文件。当前接口、预算和具体支持面统一见[格式合同](../references/formats.md)。

Ponytail Review 沿 DOCX → Worker → layout → Canvas/PDF 的实际调用检查了正确性、失败恢复、资源释放、成本与抽象必要性。复用已有字体链、Path2D、浏览器解码和 pdflite；没有引入第二个编辑模型、renderer、布局引擎或插件平台。上游 HarfBuzz GDEF Offset32 的缺口以固定源码 hash 的两处修补解决，真实塑形和独立 regression 均执行，移除条件见[依赖记录](../references/dependencies.md)。

## 验证证据

2026-10-10 修复审查发现的七项 P3 问题：原始行距规则与数值共同继承；自动断行保留段落级 BiDi；固定行距与段尾空行共享基线和裁剪；公开构建入口共享错误类；实际应用的样式给部件/特性诊断；PNG/JPEG/GIF 在原生解码前核对尺寸；段距明确区分 settings 与分页/单元格边界。当前具体规则归[格式合同](../references/formats.md)。没有新增兼容层、可编辑模型或渲染引擎。

最终完整 loop `1791647542205` 执行 19 个 MoonBit、17 个 Bun 单元、6 个集成和 65 个 Chromium 案例，全部通过，无 skip/retry。公开源码摘要为 `b5a50879c87c12bcde44675558082faebbd3e50c0affe5b445b51f57a50c39b8`，浏览器期间源码和产物不变；根 check/build、公开源码独立安装构建及 tarball 清单检查同时通过，`bun run api` 另成功生成接口。负向探针 `1791647465991` 全选 65 项恰好失败 1 项，单选 1 项即使通过也被完整判定拒绝，随后完成上述正常重跑。

固定 LibreOffice 25.8.2.2 的参考扩大至 20 页，校准 `1791646799003` 的两次转换和冻结参考栅格 hash 一致。整段 BiDi 使用 FriBidi 1.0.16 的独立层级。原始 `testN778140` 和 `testTdf145716_nonHTMLspacing` 文档保留全部部件；自动间距给诊断、带内容页眉拒绝布局，未将参考引擎的完整布局算成 SDK 支持。Ponytail Review 核对生产者、消费者、公开入口和测试，未发现当前范围内的剩余修复项。

以下为初次 P3 验证记录，保留其输入与环境口径，不代表后续代码自动通过：

根 `bun run api` 与 `bun run test` 成功；完整 loop 同时执行根 `bun run check`、`bun run build`、仅公开源码的独立安装/检查/构建、真实 tarball 清单和浏览器期间源码/产物不变检查。17 个 MoonBit、16 个 Bun 单元、6 个集成与 55 个 Chromium 案例全部执行，无 skip/retry。私有运行 `1791634601274`，公开源码清单摘要 `294bdb005a5da2a51998c58041fc46b6fb64ab066a6dde8556552faffe10489f`；未提交工作树以文件 hash 记录，不冒充 HEAD。

环境为 macOS 27.0.1 (26A434) arm64、Bun 1.4.2、Node 24.21.0、Moon 0.1.20260920 / moonc 0.10.14+7d59c7ec9、Playwright 1.63.0 / Chromium 153.0.8010.12、qpdf 12.4.1、HarfBuzz 14.4.0 与 Poppler 26.05.0。

- 三个真实 POI DOCX 对照固定 LibreOffice 25.8.2.2 的六页参考，检查文字、页数、行几何及表格颜色；参考校准 `1791633451630` 两次转换和冻结参考的 72 DPI PNG hash 相同，Codex 检查了六页实际图像。
- 实际 Canvas 与 PDF 分别检查墨迹、边界、RGBA 颜色、键盘/下载/DPR；qpdf 和 Poppler 独立打开、提取、栅格化。关闭 ActualText 后仍检查连字、组合字符和 CJK 映射，组合字形另与 HarfBuzz 比较 ID、cluster、advance/offset。
- 空文档、连续分页、4096/4097 单元、字体嵌入限制、超高表格、缺资源、过期布局、精确输出预算、准备中取消和宿主保留都有失败/恢复案例。Unicode 断行执行 6,424 个声明 tailoring 内的向量。
- 负向判定 `1791634490093` 确认 55 个案例中的错误 oracle 恰好失败一项，以及单项通过仍因缺必选案例非零退出；随后重跑正常完整 loop。首个真实失败、输入和 trace 均保留，没有重试掩盖失败。

基础输入当次 Worker 创建约 40.8 ms、解析 4.6 ms、首次布局 9.6 ms、暖布局 1.8 ms、绘制 0.2 ms、PDF 6.3 ms，布局 JSON 9,093 字节。Wasm 为 1,675,049 字节，gzip 518,603 / Brotli 374,828 字节，SDK 与独立 PDF probe 的外部 imports 均为空；这些是单次观测，不是性能承诺。详细口径、判定规则和参考复现入口见[测试说明](../references/testing.md)；测试/fixtures/原始报告只在私有仓库。

## 当前边界

不包含浮动/裁剪/旋转/翻转图片、合并/嵌套/行内分页表格、带内容页眉页脚、复杂域/修订、主题颜色、条件表格样式、完整 Word 布局或彩色字体。原 POI GIF 为浮动 anchor，仍作为保留内容与明确拒绝的负向输入；没有改造成内联来冒充兼容。

没有 Microsoft Word golden、Firefox/Safari、PDF/A、PDF/UA、签名或 PDF 输入编辑验证。字体 fallback 仍按码点；断行字符表和向量版本不同，不能宣称完整 UAX #14 符合性。长无空格段落重新塑形存在二次成本，4096 单元诊断曾约 4.7 秒，进入更长文档或交互编辑时需要优化。WasmGC 峰值内存未可靠测量，资源/输出预算不等于进程峰值上限。
