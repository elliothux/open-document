# P6 PPTX 预览、编辑与保真保存

状态：`implemented`，2026-10-14。首版通过真实 PPTX 完成打开、切页、文字与已有对象编辑、撤销、保存重开和静态 PDF。仅覆盖 Chrome/Chromium，不声明完整 PowerPoint 兼容。

## 交付结果

| 用户操作 | 当前结果 |
| --- | --- |
| 打开与导航 | Transitional `.pptx`；声明页序、原始尺寸、隐藏状态、当前页预览和缩放 |
| 主题与继承 | 主题、母版、版式和当前对象按属性解析；占位符按类型/索引匹配，读取字体、颜色、背景、样式引用和几何 |
| 基础图文 | 矩形、椭圆、直线、文本框；无填充/纯色填充和实线边框；普通段落、跨 run 样式、软换行、字符项目符号；PNG/JPEG、矩形裁剪、旋转/翻转及有界组合变换 |
| 文字编辑 | 单框字素选区、输入/删除、Enter 拆段、Shift+Enter 软换行、段落合并、纯文本剪贴板、组合候选与取消 |
| 对象编辑 | 点击/Tab 选择、双击/Enter 进入文本、Esc 退出；方向键移动，拖动与四角尺寸手柄；手势提交一项历史 |
| 保存与恢复 | 目标页局部源补丁、撤销/重做、revision 冲突拒绝、输出屏障、关闭等待；呈现失败保留已提交内容，可刷新或显式撤销 |
| PDF | 当前页/整稿，保留原页尺寸、图元顺序、变换、裁剪及可提取文字；整稿默认跳过隐藏页，可明确包含 |

编辑继承位置时，仅向当前对象写入必要覆盖。文字修改保留范围外 run/段落属性。关系、共享主题/母版/版式、其他页、媒体、备注、批注和未知部件保持源字节。无编辑保存与全部撤销恢复原解压部件；不要求整个 ZIP 字节一致。

固定文本框超出范围时诊断并裁剪。`normAutofit` 在核心有界缩小，保存必要的 `fontScale`，保留基准字号与框尺寸。字段、继承对象和组合成员只读。未知对象占位并阻止点穿；未知范围使该页画布只读，其他页仍可操作。

## 共享实现

`PositionedPage.primitives` 是三种格式共用的有序图元序列。文字保留 Unicode/glyph/字体，图片独立；路径、矩阵和裁剪由核心生成。DOCX/XLSX 保持原绘制顺序，Canvas/PDF 消费同一序列。旧的页面填充/边框/文字分组和 `restoreClip` 已删除。

PPTX 复用 Worker、`CanvasSurface`、`CanvasRenderer`、图片校验/解码、字体塑形和 PDF writer。DOCX/PPTX 共用 `NativeTextInput` 的平台事件与组合处理。TS 分发事件、绘制与准备当前页资源，不解析主题或重新排版。

同步入口为 `loadEngine(wasm).openPptx()`。Web 入口为 `PptxClient.open()` 与 `PresentationEditor.create()`。类型化命令、嵌入示例、预算和支持边界归[开发说明](../references/development.md#pptx-入口)及[格式合同](../references/formats.md#pptx)。

## 足够检查与依据

私有 `cases/p6-pptx.json` 登记固定 ONLYOFFICE 原件、许可及本次证据。`new/en-US/new.pptx` 验证基础占位符；`sample/sample.pptx` 验证复杂内容诊断与无编辑源保留，不将它算作整稿正向渲染输入。

四条 Chromium 功能链覆盖双页共用母版、跨 run/段落编辑、源保留/撤销、真实鼠标移动/尺寸、原生输入事件、组合提交/取消、剪贴板、切页、关闭、保护与失败恢复。独立 ZIP/XML 检查非目标部件，新的 SDK 会话重开保存结果。

Canvas 与 Poppler 的独立像素检查覆盖图文叠放、旋转、裁剪和透明区域。qpdf/Poppler 核对 PDF 页数、原始尺寸和文字；隐藏页及当前页导出分别检查。LibreOffice 26.8.1.1 独立重开保存后的图文 PPTX，再导出两页 PDF，并核对文字。

受共享改动影响的七条 DOCX/XLSX Chromium 用例通过，范围包括图文 PDF、组合输入、取消/关闭、停止后恢复和多页表格打印。绘制边界的三个既有单元用例通过。根静态检查、构建及生成接口检查通过；未运行全量 loop、性能专项、其他浏览器或新的系统输入法验收。

机制与预期优先来自固定 ONLYOFFICE：[占位符继承](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L1694)、[占位符匹配](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/slide/Editor/Format/Slide.js#L390)、[对象变换](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/common/Drawings/Format/Shape.js#L3268)。LibreOffice 仅补充独立重开检查；未复制上游实现或引入生产依赖。

## 边界

不新增/删除幻灯片或对象，不替换图片，不编辑主题/母版/版式，不提供多选、组合编辑或旋转控件。表格、图表、SmartArt、音视频/OLE、自定义几何、复杂连接线、渐变/图案/效果、艺术字、纵排、多栏、自动编号和 `spAutoFit` 保留源并诊断或保护。

动画和切换只保留在 PPTX 中。静态 PDF 不表达播放效果；遇到可见未支持内容或未解决文字适配时拒绝完整导出。PPT、PPTM、Strict OOXML、加密和签名输入不支持。

当前字号、颜色、常见脚本字体及段落能力有明确范围，详见格式合同。逐字符输入独立成历史，组合和一次拖动各成一项；未建设连续输入分组、场景图、全预设形状库、缩略图流水线或性能缓存系统。
