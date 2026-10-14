# P9 Web SDK 与默认 UI

状态：`implemented`。已接通 DOCX、XLSX、PPTX、PDF 的现有能力。浏览器范围为 Chrome/Chromium，包仍为 private/WIP。本阶段不授予完整 GenOffice 功能；新增文档能力与后续顺序归[路线图](../references/roadmap.md)，差距归 [G3](../g3-genoffice-sdk-gap.md)。

## 已交付结果

宿主使用普通 JavaScript 调用 `@open-document/ui` 的 `mountEditor`，显式供应文件、Wasm、Worker、授权字体与 profile。默认 UI 提供文件菜单、分组功能区、格式面板、状态、诊断及恢复入口，支持 light/dark 与 zh-CN/en-US。

| 格式 | 已接通的操作 |
| --- | --- |
| DOCX | 现有正文/单格文本输入、选区与纯文本剪贴板、历史、翻页/缩放、原格式保存、PDF 与停止后恢复 |
| XLSX | 可见工作表、单格原生草稿、范围粘贴/清除、历史、缩放、原格式保存、基础打印预览与 PDF |
| PPTX | 真实幻灯片/对象列表、对象与文本模式、现有移动/缩放/文字编辑、历史、保存、当前页/整稿 PDF |
| PDF | 页导航、选择/复制、搜索、缩放、重排/旋转/删除、便笺/高亮、原生字段/批注草稿、历史和保存 |

只读原因与格式诊断沿原合同展示。尚未实现的操作不显示为空按钮；列表使用核心页码、标题与对象信息。新建、格式编辑、对象创作、放映、PDF 正文编辑继续归 P10–P13。

## API 与生命周期

实际签名、草稿规则和资源所有权归[格式合同](../references/formats.md#默认-ui-与编辑宿主)，可运行普通 JS 示例与构建命令归[开发说明](../references/development.md#默认-web-ui)。

- 返回值按 `format` 区分当前只读 `editor` 属性，提供同格式 `open`、`save`、`close`、`dispose` 和跨替换保持的状态订阅。
- 输出携带 `documentId/revision/format/bytes`。宿主保存回调成功才确认原格式基线，后续编辑仍未保存；下载只记录生成，PDF 不清除 Office 修改。
- 替换先处理草稿/修改并暂停旧会话，在独立候选完成字体与首屏后切换。损坏、资源失败和加载取消保留旧会话；最多一个候选。
- 正常关闭提供保存/放弃/取消。明确释放不弹确认，等待已接受操作后取消未提交候选，继续完成各项清理；重复释放等待同一结果。

## 实现与参考

[`packages/ui`](../../packages/ui/package.json) 使用 React、open ShadowRoot、构建期 Tailwind 与 Base UI。样式、Portal 与 ARIA 引用在实例内；关键尺寸采用本地 px，省略 Preflight。菜单非模态，关闭确认使用 Base UI 模态 Dialog。主题不改变文档页面颜色或核心布局。

四类 Web 编辑宿主保持框架无关，拥有既有队列、Canvas、原生输入与语义节点。旧编辑工具栏已移出；React 更新不重建输入或会话。XLSX 草稿与 PDF 属性草稿各保留一份；PPTX 对象焦点按实际 root 恢复。MoonBit 的编辑、布局和序列化边界保持。

功能区、设计变量及选定 SVG 参考 GenOffice `5eab98adc8d0ebf6ecea687e42400a791ef58d64`。来源与许可保留在 [NOTICE](../../packages/ui/NOTICE)，依赖版本归[依赖记录](../references/dependencies.md#默认-web-ui-依赖)。未引入 GenOffice 的应用或编辑引擎依赖。

## 足够检查与边界

定向检查复用各格式的输入、独立预期和保存检查，未扩大兼容集：

| 风险 | 已检查的结果 |
| --- | --- |
| UI 改接与输出 | 四类默认 UI 的编辑、撤销/重做、保存重开；既有 XLSX/PPTX/PDF 宿主回归及 DOCX 键盘/下载屏障 |
| 保存误报 | 重复保存共享回调；回调失败、新编辑、晚到回执及 PDF 输出保留正确修改状态；关闭前保存再次编辑保留会话 |
| 替换与释放 | 损坏输入、字体失败、加载取消、草稿取消关闭、初始挂载取消、清理失败、已接受表格草稿释放与另一实例继续工作 |
| ShadowRoot 与输入 | 宿主冲突 CSS/根字号、实例 Portal/焦点、原生输入节点稳定；默认 UI 中的 Chromium 中文组合与当前 Chrome 普通系统输入 |
| 包接入 | tarball 本地安装、无 DOM 导入、严格类型与普通 JS 构建；示例只依赖公开产物 |

`bun run check`、公开构建及相关私有静态检查通过。九条不同的 Chromium 功能流程已有适用通过结果；表格释放失败修复后只复验该流程，原始失败保留。详细范围与产物归私有 `cases/p9-ui.json`，不声明完整 loop 或全部兼容回归通过。

GenOffice App 0.11.727 用于直接审阅功能区、页面工作区和状态栏；没有新增截图金样本。普通 Chrome 使用现有输入源键入并操作菜单/关闭，未切换输入源；中文组合由 CDP 检查。历史系统中文输入证据仍保留原边界。

未运行性能专项、其他浏览器、Windows/Word 或 VoiceOver 验收。基础格式保真和资源上限继续以[格式合同](../references/formats.md)为准。
