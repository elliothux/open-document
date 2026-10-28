# R1 领域拆包与共享 Wasm 加载

状态：`implemented`。交付日期：2026-10-28。格式功能与限制归[格式合同](../references/formats.md)，接入方式与构建命令归[开发说明](../references/development.md)。

## 交付结果

DOCX、XLSX、PPTX、PDF 各有独立 package，提供 `core`、`web`、`react`、`worker` 子路径。宿主可以单独接入一种格式，或按文件类型动态导入。React 入口确定格式，options 不再传 `format`。

| 所属位置 | 当前职责 |
| --- | --- |
| `packages/docx`、`xlsx`、`pptx`、`pdf` | 本格式绑定、校验、协议、Worker、编辑宿主、文件准备、面板及输出动作 |
| `packages/wasm` | 唯一 `engine.wasm`、SHA-256 构建身份、共享 Loader、基础 ABI 与错误 |
| `packages/web-core` | 通用连接、输入、剪贴板、Renderer、Canvas 表面、资源与快照合同 |
| `packages/ui` | 共用外壳、控件、本地化、样式与文件生命周期 |
| `packages/devtools` | 只读订阅公共快照，由 DEV 宿主动态加载并清理 |
| `modules/bridge/src/common` | 有界字段与字节解析、字体输入和错误响应 |
| `modules/bridge/src/docx`、`xlsx`、`pptx`、`pdf` | 各格式独立上下文、命令、字体/图片资源及关闭 |
| `modules/bridge/src/all` | 聚合四类 ABI，链接唯一发布用 Wasm |
| `modules/bridge/src/probe` | 独立文本 POC，仅用于工程测试 |

公共前端层不导入领域包。`core`、`web` 不导入 React。领域 ESM 保留对公共包的外部引用，公共依赖使用精确版本和同一锁文件。旧 `packages/web`、全格式工厂、统一 Worker 与混合协议已删除，相关调用方和生成接口已迁移。

MoonBit 继续拥有文档状态、编辑、计算、排版和序列化。DOCX/PPTX 的嵌入工作簿复用 XLSX 核心，Office 输出复用 PDF writer；这些依赖不引入其他格式的前端编辑器。通用绘制继续遵循 [R0](r0-renderer-foundation.md)。

## 共享加载与隔离

`loadEngine({ url, build }, signal?)` 返回不透明的 `EngineHandle`。绝对 URL 和构建身份相同的调用共享在途获取与编译 Promise。HTTP、读取、编译或基础 ABI 检查失败后移除对应条目，下一次显式调用可重试。缓存只保留当前资源条目；旧请求晚到不会覆盖新构建。

取消只结束该调用方的等待。句柄持有编译后的 Module，不持有文档、可变 Instance 或字体集合。各领域 Worker 接收结构化克隆的 `WebAssembly.Module`，不加入 Transferable 列表，不重新获取或编译 Wasm。每个文档创建独立 Instance 和会话；初始化、取消或克隆失败会释放候选 Worker。

编译保留 WasmGC 的 `js-string` builtins 与 imported string constants。Loader 检查基础导出，领域实例化检查 ABI 版本和本格式导出。保存屏障、组合输入、草稿、候选替换、未保存确认及关闭队列继续由原编辑宿主处理。

开发预览与普通 JS 示例均按格式动态导入，共用一个 Loader 和字体资源。预览保持全屏编辑、文件菜单打开和关闭后的中央打开按钮。DEV setup、替换清理和热更新已接通；生产构建排除 devtools。

## 验证与边界

2026-10-28 在固定本地工具链及 Chromium 上完成以下定向检查，详见[测试说明](../references/testing.md#r1-领域拆包与共享加载)。

- Moon check/build/info、严格 TypeScript、lint、格式和锁文件检查通过。
- 18 项定向单元检查通过，覆盖 Loader 并发、取消、失败重试、新旧构建竞争、克隆失败释放及既有边界校验。
- 3 项安装包消费检查通过，共 4006 个断言；覆盖七包资源与 exports、类型、独立 XLSX/PDF 导入、无 React 的 core/web、唯一 Wasm 和外部共享 Loader。
- 六条相关 Chromium 流程通过：共享 XLSX/PDF Module 与会话隔离、DOCX 保存确认/替换/双实例、XLSX 编辑/历史/重开、PPTX 编辑/历史/输出/重开、PDF 编辑保存及开发预览生命周期。
- 生产 Vite 构建通过，产物无 devtools。

后续定位并修复了两条宽泛 P9 用例：XLSX 后台重绘曾短暂禁用控件，导致历史点击或范围框 Enter 丢失；PPTX 复制曾把源对象已有的文字溢出当成失败。同步修正测试模块映射及重名控件的定位范围。两条完整流程、一个新增重绘竞态检查及 11 项对象复制相关核心检查通过，保留原断言。结果归测试说明中的补充修复记录。

本期只分发一个全格式 Wasm。仅使用 PDF 仍加载全格式二进制；Module 复用范围限同一页面显式提供句柄的调用方。未引入动态链接、Component Model、持久缓存或单格式 Wasm。未跑全量格式语料、性能或浏览器矩阵。
