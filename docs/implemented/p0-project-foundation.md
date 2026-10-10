# P0 — 工程与 SDK 运行底座

状态：`implemented`，2026-10-07 获得本地 `verified` 证据。完成的是开发者工程底座与纯文本 POC，不是 Office 预览或编辑器。后续依次为 [P1](p1-sdk-foundation.md)、[P2](p2-format-foundation.md)、[P3](p3-docx-preview.md)。2026-10-08 按用户要求由原 P1 改编号为 P0；历史报告不改写。

## 开发者已经能做什么

在浏览器中加载 release WasmGC，经 TypeScript API 创建独立文本会话、读取文本、替换范围、撤销、关闭会话。文档状态和编辑语义在 MoonBit；Web 只处理实例化、参数边界、Worker 通信与生命周期。公开 SDK 可独立检查和构建，私有测试不是使用 SDK 的前置依赖。

这是后续文件会话的工程验证，不承诺纯文本 POC 的 ABI 就是最终 DOCX API。不存在 DOCX/XLSX/PPTX/PDF importer、分页、富文本或格式转换实现。

## 已交付的实现边界

| 子目标 | 产品与工程结果 | 实现归属 | 验收方式 |
| --- | --- | --- | --- |
| P0.1 工程 | 固定工具链、可独立构建的 Moon/Bun monorepo | 根 workspace；core/layout/formats/bridge；wasm/web | 无私有依赖的独立副本安装、检查、构建及真实包清单检查 |
| P0.2 文本核心 | 会话状态、UTF-16 范围替换、撤销、关闭 | `modules/core/src/text` | MoonBit 正反例，错误不改变状态 |
| P0.3 Wasm 接入 | 浏览器实例化与参数转换，单 Worker 拥有一个会话 | bridge、wasm、web | 正式 API 调用真实 WasmGC，文本与生命周期分别验证 |
| P0.4 反馈基础 | 失败可定位，漏跑和不完整结果不能报告成功 | 私有判定器与执行器 | 错误预期、缺案例、包泄漏负向探针 |
| P0.5 格式准备 | 首批 DOCX/PDF/XML 输入及独立结构基线 | 私有 corpus | 来源、许可、hash、外部工具检查；不算格式支持 |
| P0.6 开发体验 | 根目录一键检查/测试，hook，submodule 与编辑器发现 | 根 scripts 与配置 | 新检出复现；hook 拒绝错误并接受正常代码 |

当前模块依赖和命令由[开发说明](../references/development.md)维护，测试流程由[执行规则](../references/testing.md)维护；本结果不复制机器清单或建立第二套 roadmap。

## 稳定合同与已知限制

- offset 是 UTF-16 code unit，不是字素索引；不能切断 surrogate pair，组合字符可能被分开。宿主拒绝非整数、负数与超 i32 范围，核心负责文本范围与 surrogate 检查。
- 核心状态码：0 成功；1 非法范围；2 已关闭；3 撤销历史预算超限；4 无可撤销记录。失败不改文本或历史。
- 撤销使用最多 100 条整串快照；这是有界 POC，不承诺大文档增量编辑性能。P4 再以实际编辑负载确定记录和重排策略。
- Web 同时只允许一个操作在途；重叠请求失败，不自动排队重试。dispose 销毁 Worker 并拒绝未完成请求。
- 使用 JS string builtins；目前只验证固定 Chromium，不代表任意 WasmGC runtime、Safari/Firefox 或 CLI 可用。
- layout 与格式包明确占位，不暴露伪能力。缺少私有 submodule 时根测试失败，公开 check/build 仍可运行。

## 验证证据与交接

证据路径均相对私有 `test-lab/`，不要求公开读者能够打开。原始报告、输入和失败材料没有迁入父仓库。

| 证据 | 实际结果与范围 |
| --- | --- |
| `.temp/runs/1791388155610/` | 13 项 Bun unit、6 项 integration、4 项 MoonBit、20 项真实 Chromium 通过；公开构建与真实 tarball 清单检查通过 |
| `.temp/failures/1791387023473/` | 错误预期选 20 项、19 项通过，完整验收失败；只选 1 项且该项通过，完整验收仍失败 |
| `.temp/replay/1791388189786/` | 主仓库 `ce57913` / 子仓库 `90af73a` 的新本地 clone，通过 frozen install、完整 loop 和新安装 hook 正反验证；复用系统工具与缓存，不是裸机或远端验证 |

三轮复核分别覆盖目标完整性、判定器失败能力、新检出复现；实际修复过空 submodule 递归、旧产物混入快照、打包清单未强制校验、执行数硬编码和研究链接依赖本机目录。PDFium 异常输入的 Resources 警告保留为诊断案例，没有放宽成合法 writer 输出。

这些是对应版本的历史证据，不代表后续变更自动通过。P1 先验证字体塑形与字形输出；P2 完成受限 ZIP/XML/OPC 到一次文本写回；P3 再推进 DOCX 预览和 PDF。P0 不能抵扣这些阶段的格式、视觉或性能验收。
