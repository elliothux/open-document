# 开发与模块边界

当前实现工程/文本 POC、字体塑形与轮廓 probe、有界 ZIP/XML/OPC、Transitional DOCX 的正文文本节点查询/替换/保存，以及限定 DOCX 分页预览和 PDF 输出。`xlsx`、`pptx` 仍为占位包；PDF reader 尚未实现。当前支持面见[格式合同](formats.md)，固定第三方依赖见[依赖记录](dependencies.md)。

## Workspace

| 位置 | 所有权 | 允许依赖 |
| --- | --- | --- |
| `modules/core` | text、failure、archive、XML 源片段与 OPC 图 | 标准库、固定 flate/xml；不依赖宿主 |
| `modules/layout` | 字体塑形、几何、分页与绘制结果 | core；不通过 DOM 决定布局 |
| `modules/formats` | docx/xlsx/pptx/pdf 的独立语义与读写 | core；需要输出布局时依赖 layout |
| `modules/bridge` | Wasm 导出、核心到宿主的批量 ABI | core、layout、formats/docx、formats/pdf |
| `packages/wasm` | 实例化与 ABI 校验 | WasmGC 产物；不拥有第二份文档模型 |
| `packages/web` | Worker 请求与生命周期 | wasm 包；不实现文本替换、撤销或排版 |

根 `moon.work` 明确列举四个 module，各 module 内以 package 划分真实 concern。暂不为每种格式创建独立发布 module，也不创建 CLI 空壳。根 Bun workspace 只包含 `packages/*`，一个公开 `bun.lock`；私有工具是独立仓库和独立依赖域，不加入公开 workspace。

文本 POC 使用 UTF-16 范围，不允许切断 surrogate pair；它不是字素导航或富文本编辑器。核心保留最多 100 条文本快照用于 POC 撤销，正式编辑阶段再基于测量改为编辑记录。当前 ABI 使用 JS string builtins，尚不承诺其他 WasmGC runtime 等价运行。

## 当前 Foundation API

公开源码入口为 `packages/wasm/src/foundation.ts` 和 `packages/web/src/foundation.ts`，与既有文本 POC 分属真实职责。底层 `(await loadEngine(wasm)).openFoundation()` 适用于受控同步调用；浏览器使用 `FoundationClient.open(wasm, workerUrl)`。宿主提供实际 release Wasm 字节和 bundle 后 Worker 的 URL，不依赖测试服务器。

客户端提供 `defaultBudget()`、`addFont(bytes, identity)`、`shape(text, size, language)`、`openDocx(bytes, budget)`、`query()`、`replaceNode(id, revision, text)`、`saveDocx()`、`flow()`、`imageBytes(key)`、`addImage(key,width,height,rgba)`、`layout(profile)`、`exportPdf(outputBytes,layoutId?)` 与 `dispose()`。DOCX 打开要求显式预算，可从核心默认值复制并收紧。`ShapeBatch` 包含字体身份、font units 度量、CSS px 位置和 UTF-16 clusters；布局使用 point。一个 `OutlineCanvas` 持有同会话派生 Path2D 并在结束时 `dispose()`。

`@open-document/web/preview` 的 `DocumentPreview` 复用 caller 的 `FoundationClient`，创建和关闭边界见[格式合同](formats.md)。宿主先加载所需授权字体；预览准备包内图片、请求核心布局、执行绘制及下载。TS 不持有可编辑文档树，不再塑形。

`tools/prepare-dependencies.mbtx` 是公开构建准备步骤，不依赖私有测试库。它让 Moon 下载精确固定依赖，校验 HarfBuzz 0.1.0 原文件 SHA-256，再修复 GDEF MarkGlyphSets 的 Offset32 读取；重复运行核对已补丁 hash。未知源码直接失败。`check`、`build`、`api` 调用此步骤；直接运行 Moon 命令前也需先运行它。补丁依据、移除条件和许可归[依赖记录](dependencies.md)。

连接代码只拥有一个 in-flight 请求和 Worker 生命周期；不包含通用 RPC 或可独立编辑的文档树。用户字节经 structured clone/JSON/base64 批量穿过边界，已作为当前切片的可测成本；后续只有实测证明它阻碍文档使用时才更换 ABI。

公开主线程入口保留 ESM 模块导入，`engine`、Wasm `foundation` 与 Web client 使用同一份 `DocumentError` 构造函数。应用构建器需要解析 `@open-document/wasm` 的公开子路径；直接加载浏览器 ESM 时，需要 import map 将 `foundation`、`preview`、`engine` 子路径映射到对应产物。内部运行时导入使用 `.js` 扩展名。Worker 单独打包，因此不依赖主页面的 import map。公开 tarball 包含这些模块及其内部依赖，测试服务器只提供资源路由。

## 工具与命令

固定 Bun 1.4.2；Moon 工具链 0.1.20260920（moonc v0.10.14+7d59c7ec9）。使用官方工具链并将 `~/.moon/bin` 加入 PATH；`moon-toolchain` 是本项目的版本约定，不声称 Moon 会自动安装该版本。

```sh
bun install --frozen-lockfile
bun run hooks:install
bun run check
bun run build
bun run api
```

- `check:moon`：WasmGC 类型检查，启用的编译器 warnings 全部视作错误。不增加一个与编译器重复的 MoonBit linter。
- `typecheck`：严格 TS，包括 unchecked index 与 exact optional property；不使用 `any`、忽略指令或类型双重断言。
- `lint`：固定版 Oxlint，警告阻止通过。
- `format` / `format:check`：Moon 原生 formatter + Prettier。前者修改格式，后者只检查。
- `api`：Moon 自动生成 `.mbti`，应审阅并跟随源码提交，禁止手改。
- `build`：正常 release WasmGC + 浏览器 JS，输出到各包 `dist/`。目前包为 private，未发布。

### Git hook

使用与 open-compute 相同的 `simple-git-hooks`，`pre-commit` 执行 `bun run check`。它检查整个当前工作树，不自动 format、不自动 stage、不自动运行私有测试，也不声称检查的是独立 index 快照。部分暂存时维护者仍须核对暂存差异；完整私有验收不由这个 hook 代替。

安装 hook 是显式命令，不在依赖安装中静默覆盖已有 hook。GUI Git 客户端也需要能找到 Bun/Moon；不要通过忽略错误来绕过环境问题。当前环境没有原有 pre-commit hook，已安装本项目配置。

## 开源与私有边界

所有一方测试代码、数据、具体预期结果、原始报告和执行 loop 属于私有 `open-document-test`。产品、架构与测试文档统一在父仓库 `docs/`，不在子仓库重复维护。公开构建完全不依赖私有仓库。`test-lab/` 作为 Git submodule 固定到私有仓库的一个 commit；主仓库只保存 `.gitmodules` 和 gitlink，不包含私有文件。

完成私有仓库的依赖与浏览器安装后，在根目录运行 `bun run test` 即可直接执行 `test-lab` 的完整测试入口。该命令必须依赖私有 checkout，缺失目录或任一步骤失败都会返回失败，不静默跳过。使用 `bun run test`，而不是调用 Bun 内置 runner 的 `bun test`；根 `check` / `build` 和 pre-commit 不依赖此测试入口。

空的、尚未初始化的 submodule 目录也会在入口失败。VS Code/Cursor 共用 `.vscode/settings.json`，显式扫描 `test-lab` 并启用 submodule 检测；没有私有权限的公开使用者仍可正常 check/build。

维护者获取私有仓库权限后，在根目录执行 `git submodule update --init --recursive`，按[测试说明](testing.md)安装测试依赖。不自动跟踪远端分支；更新测试时先提交私有仓库，再提交主仓库的 gitlink。普通公开使用者不需要初始化私有 submodule。

当前仅完成本地提交，尚未推送。其他机器能从远端初始化的前提是：先推送被引用的私有 commit，再推送主仓库提交；不要发布远端尚不可获取的 submodule 引用。

参考：[Moon workspace](https://docs.moonbitlang.com/en/latest/toolchain/moon/workspace.html)、[MoonBit FFI](https://docs.moonbitlang.com/en/stable/language/ffi.html)、[Bun workspaces](https://bun.sh/docs/pm/workspaces)。
