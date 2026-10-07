# 开发与模块边界

当前只有工程底座和纯文本 POC。`archive`、`xml`、`opc`、`layout` 及四种格式包是明确的占位包，没有解析、排版或转换实现。

## Workspace

| 位置 | 所有权 | 允许依赖 |
| --- | --- | --- |
| `modules/core` | 纯计算基础能力；当前实现 `text.Session` | MoonBit 标准库，后续审核的基础库；不依赖宿主 |
| `modules/layout` | 字体塑形、几何、分页与绘制结果 | core；不通过 DOM 决定布局 |
| `modules/formats` | docx/xlsx/pptx/pdf 的独立语义与读写 | core；需要输出布局时依赖 layout |
| `modules/bridge` | Wasm 导出、核心到宿主的 ABI | 当前只依赖 core/text |
| `packages/wasm` | 实例化与 ABI 校验 | WasmGC 产物；不拥有第二份文档模型 |
| `packages/web` | Worker 请求与生命周期 | wasm 包；不实现文本替换、撤销或排版 |

根 `moon.work` 明确列举四个 module，各 module 内以 package 划分真实 concern。暂不为每种格式创建独立发布 module，也不创建 CLI 空壳。根 Bun workspace 只包含 `packages/*`，一个公开 `bun.lock`；私有工具是独立仓库和独立依赖域，不加入公开 workspace。

文本 POC 使用 UTF-16 范围，不允许切断 surrogate pair；它不是字素导航或富文本编辑器。核心保留最多 100 条文本快照用于 POC 撤销，正式编辑阶段再基于测量改为编辑记录。当前 ABI 使用 JS string builtins，尚不承诺其他 WasmGC runtime 等价运行。

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

所有一方测试、数据、预期结果和执行 loop 属于私有 `open-document-test`。公开构建完全不依赖它。维护者在本地 `test-lab/` 独立 checkout 中工作；当前按用户要求不提交、不推送，因此尚未建立 gitlink/submodule。

完成私有仓库的依赖与浏览器安装后，在根目录运行 `bun run test` 即可直接执行 `test-lab` 的完整测试入口。该命令必须依赖私有 checkout，缺失目录或任一步骤失败都会返回失败，不静默跳过。使用 `bun run test`，而不是调用 Bun 内置 runner 的 `bun test`；根 `check` / `build` 和 pre-commit 不依赖此测试入口。

未来授权提交后，先创建私有 commit，再将此 checkout 注册为固定 commit 的 submodule 并移除根 ignore 项。不创建指向空仓库的假 gitlink，不自动跟踪远端分支。相关命令和细节保存在私有文档。

参考：[Moon workspace](https://docs.moonbitlang.com/en/latest/toolchain/moon/workspace.html)、[MoonBit FFI](https://docs.moonbitlang.com/en/stable/language/ffi.html)、[Bun workspaces](https://bun.sh/docs/pm/workspaces)。
