# P16 跨宿主与非浏览器运行时

状态：`planned`，2026-11-02。本阶段对应[路线图](references/roadmap.md)的跨宿主目标与 [SDK 合同](references/sdk.md#次要平台其他语言--wasm-runtime以及-cli)。通过复用同一份 MoonBit 核心，在无浏览器、无 DOM/Canvas 的环境下完成 DOCX、XLSX、PPTX、PDF 的读取、编辑、计算、排版、保存与转换。

**推进策略调整**：将 `P16.1 无浏览器核心闭环探针` 提前至 [R2.3 核心下沉](r2-architecture-and-performance.md)之后、[P15 外围能力](p15-peripheral-capabilities.md)之前执行，用自动化构建强制保证核心不依赖任何浏览器专属 API。

## 用户结果与范围

1. **纯 Wasm/Native 无 DOM 闭环**：在无 `window`、`document`、`CanvasRenderingContext2D`、`createImageBitmap` 的运行时（`moonrun`、Node/Bun 无 DOM 模式或 Wasmtime）中，直接打开四格式文档、执行查询与编辑命令、完成公式重算与文本排版、保存原格式并导出 PDF。
2. **命令行工具（CLI）**：提供轻量 CLI 入口，支持文件检查（inspect/diagnostics）、批量文本/结构提取、程序化编辑脚本执行以及 Office → PDF / HTML / Markdown / CSV 转换。
3. **非浏览器宿主绑定**：验证一个明确的非浏览器宿主环境（如服务端 Node/Bun Worker 或 Rust/Go Wasmtime 宿主），复用与 Web 相同的命令协议与 DrawingBatch 输出。

## 分批实施计划

| 批次 | 用户与工程结果 | 核心与宿主工作 | 足够检查 |
| --- | --- | --- | --- |
| P16.1 无浏览器核心独立性闭环（前置） | 不依赖浏览器 Image/Canvas API 完成四格式打开、含图排版、编辑、保存与 PDF 导出 | 在 MoonBit 核心完成 PNG/JPEG/GIF 头部解析与必要像素解码；核验 Wasm imports 表零浏览器依赖 | 在纯 Node/Bun（禁用 DOM/Canvas globals）与 `moonrun` 中跑通含图片/图表的 DOCX、XLSX、PPTX、PDF 读写与 PDF 导出 |
| P16.2 CLI 工具与批处理工作流 | 通过命令行完成四格式诊断、内容提取、脚本化修改与格式转换 | 新增 CLI 入口模块，封装文件 I/O、字体目录加载、预算配置与退出码规范 | CLI 打开正常/损坏/受保护文件、执行转换（DOCX/XLSX/PPTX → PDF，PDF → Office/Markdown）及保存重开检查通过 |
| P16.3 非浏览器宿主接入与栅格后端验证 | 在一个明确的非浏览器宿主中嵌入 SDK，验证会话生命周期、内存上限与非 DOM 绘制后端 | 对接目标运行时 WasmGC/线性内存 ABI；将 `DrawingBatch` 接入宿主 2D 绘制后端（如 Skia / TinySkia / CoreGraphics） | 宿主内并发会话隔离、资源释放、预算拒绝及页面栅格输出与 Chromium 基线对照通过 |

---

## 关键技术边界

1. **严格控制 Wasm Imports**：
   - 定期检查 `engine.wasm`（及单格式 Wasm）的 import 表。除标准 WasmGC `js-string` builtins（在支持環境下）或最小字节传输桥接外，禁止引入绑定浏览器全局对象的 import。
   - 若目标非浏览器运行时（如特定版本的 Wasmtime）尚未完整支持 `js-string` builtins，在 `P16.3` 构建目标中提供标准 WasmGC / 传统线性内存编译配置，核心业务源码保持同一套。
2. **字体与图像资源的宿主中立性**：
   - 字体始终以字节切片 + 显式 `profile` 映射注入核心，不依赖操作系统字体注册表或 CSS Font Loading API。
   - 图像尺寸嗅探与 PDF 导出所需的像素数据在 MoonBit 内独立完成，无需回调宿主 Canvas。
3. **不预建多语言万能框架**：
   - 只为已确定的 CLI 和目标宿主编写薄适配层，直接复用 JSON/二进制命令协议，不维护庞大的跨语言对象映射生成器和旧版兼容垫片。
