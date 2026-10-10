# P1 — 字体、塑形与字形输出

状态：`implemented`，2026-10-10 获得本地 `verified` 证据。MoonBit 的 `layout.TextProbe` 接收固定字体与文本，在真实浏览器 Worker/WasmGC 中生成 glyph、UTF-16 cluster、advance/offset、BiDi run 和轮廓批次。TS 的 `OutlineCanvas` 只执行核心给出的位置，不调用 `fillText` 或另一套塑形引擎。产品和职责合同已移至 [SDK 合同](../references/sdk.md)。

采用固定的 harfbuzz@0.1.0 和 bidi@0.5.2，直接使用当前切片需要的字体、塑形和 Unicode BiDi 模块；没有引入包含编辑/换行职责的 moon_cosmic。资源由会话拥有，按输入顺序逐码点 fallback，使用 face 0 和默认 variation 坐标；缺字保留 `.notdef` 和定位诊断，彩色 emoji 明确诊断。支持 standalone TrueType/glyf，包括固定 CJK variable TTF 的默认实例；CFF、TTC 和轴选择不在本阶段支持面内。

独立 HarfBuzz 14.4.0 核对连字、组合字符、中文、阿拉伯 RTL 与多字体 run 的 glyph/cluster/度量；真实 Canvas 检查非空像素和几何边界。固定 Noto 资产保留来源、SHA-256 和 SIL OFL，见[语料管理](../references/corpus.md)。重复塑形复用轮廓；失败回滚新增缓存，销毁 Worker 和 renderer 后拒绝继续访问。

2026-10-10 在 Bun 1.4.2、Moon 0.1.20260920、Playwright 1.63.0 的 Chromium 中验证。完整 loop 的源码、产物、字体身份、独立参考、画面、冷/热调用耗时、缓存字节和 JSON 批次大小均保留在私有运行证据中；当前验收入口见[测试说明](../references/testing.md)。这些观测不是性能 SLA，也没有测得 WasmGC 峰值内存。

运行 `1791627205722` 的 release SDK 为 925,541 字节，gzip 296,345、Brotli 216,211 字节。固定 Noto Sans 的 `office`/48px/en 样本：Worker 打开 24ms，字体获取/装载 43ms，首次 shape 6.7ms，重复 shape 1.7ms；原字体 569,208 字节，base64 758,944 字节，首/重复 JSON 批次为 2,567/822 字节，核心轮廓缓存保持 1,644 字节。Canvas/readback 单独计时，重复 shape 不混入绘制成本。它们只是此次本地环境的单次观测。

私有 pdflite@0.3.8 探针在同一浏览器 WasmGC 中消费真实核心轮廓（quadratic 精确转换成 cubic），核对命令数量与非法输入；SDK 与候选在启用 JS string builtins 后的外部 imports 均为空。P1 当时仅作为测试依赖；[P3](p3-docx-preview.md) 已将 writer/字体子集/ToUnicode 纳入公开 SDK。P1 证据本身不证明这些后续能力或无浏览器输出。

Ponytail Review 按每会话一个 Worker、受限文本/字体资源的负载审查了核心、bridge、Worker、renderer 与测试。已删除 TS 预算副本，复用一个 Worker 连接，补齐失败缓存回滚与 renderer 生命周期；没有建立资源服务、通用 RPC、兼容层或第二个 renderer。
