# P5 XLSX 网格、计算与编辑

状态：`implemented`，2026-10-14。基于 [P2 文件底座](p2-format-foundation.md)、[P4 DOCX 编辑](p4-docx-editing.md)和 [R0 通用渲染](r0-renderer-foundation.md)，交付有限 XLSX 编辑器。只覆盖 Chrome/Chromium，不表示完整 Excel 兼容。

## 用户结果

开发者可以挂载 XLSX 编辑器，打开工作簿，切表、滚动、缩放及定位单元格。修改数量后，同表乘积、SUM 合计和跨表引用更新。用户可以撤销/重做、输入组合草稿、复制/粘贴纯文本、保存重开，并预览及导出当前表矩形的分页 PDF。

嵌入代码归[开发说明](../references/development.md#xlsx-嵌入入口)，API、输入语义、保真及预算归[格式合同](../references/formats.md#p5-xlsx-合同)。

## 已实现范围

| 能力 | 交付 |
| --- | --- |
| 文件 | Transitional XLSX；稀疏单元格、可见/隐藏表、共享/内联字符串、数值、布尔值、错误、公式与缓存 |
| 网格 | 核心可见行列、命中与选区几何；行高/列宽、隐藏行列、合并锚点、基础字体/填充/实线边框/对齐/换行 |
| 显示 | 基础数值、百分比、日期与时间格式；1900/1904 系统及 1900 闰日兼容；其他显示诊断并保留源声明 |
| 计算 | 常量、算术/比较、A1/矩形/绝对/混合/跨表引用，六个函数；共享公式派生与受影响依赖重算 |
| 编辑 | 点击、键盘与 Shift 选区；单格草稿、提交/取消、原生组合输入、矩形清空与 TSV；原子事务与有界历史 |
| 保存 | 源片段修改、缺行/缺格插入、公式类型与缓存同步、共享字符串计数、calcChain 删除与重算属性 |
| 打印 | 显式纸张/方向/边距、100% 比例、按行列边界分页；独立预览、Unicode/字体子集 PDF |

工作簿 XML 与派生单元格、依赖、结果和历史在同一候选中提交。导入缓存与计算值分开返回；打开不改写原文件。首次有效编辑同步已计算但陈旧的缓存，撤销全部事务恢复原部件字节。

未支持公式、依赖或原有循环使整个工作簿只读；仍可查看导入缓存及无编辑保存。新公式错误、越界、循环、保护和预算失败不留下部分写入。组合结束只更新平台草稿；保存/打印先提交有效草稿并等待队列，未结束组合明确拒绝。

## 共享实现

- XLSX 会话、计算、显示、网格和打印在 `modules/formats/src/xlsx`；Bridge/WASM 校验与 Worker 传输沿现有模块接入。
- `DrawingBatch.regions` / `CanvasRenderer.drawRegion` 统一区域命名，已同步 DOCX 调用方与检查；旧 API 已移除。
- `CanvasSurface` 共用 Canvas/DPR、覆盖层、绘制身份和资源释放；DOCX `PageCanvas` 继续准备图片，XLSX 提供独立网格语义。
- `PositionedDocument` 保存实际定位文字、glyph、Unicode、填充、边框及页面；两个格式共用 PDF writer。表格不转换成 DOCX 段落，也不从视口截图生成 PDF。
- 文件删除能力只补在既有 ZIP/OPC writer，供失效 calcChain 及关系清理使用。公开构建不依赖私有测试资源。

## 足够检查与依据

根 `bun run check`、release 构建与 API 生成通过，私有 TS、lint 与变更文件格式检查通过。私有全目录格式检查仍提示未改动的 `editor-composition.spec.ts`，未扩大修改范围。三项现有绘制/布局校验通过。

Chromium 的六项 XLSX 功能用例通过，覆盖真实 ONLYOFFICE 新工作簿、真实未支持公式工作簿、独立手算公式链、共享公式、类型化错误缓存、编辑/历史、源保留、拒绝/恢复、原生 CDP 组合输入、TSV 数值及公式文字、外部 revision 冲突、队列屏障、网格和五页打印。收尾回归另确认延迟导航后的输入绑定新单元格、可见草稿尺寸及未知值引用保护。独立 ZIP/XML 检查非目标部件；qpdf/Poppler 检查 PDF 结构、中文、数值及非当前视口文字。

共享修改直接保留四项 DOCX Chromium 回归：CJK/字体子集 PDF、RGBA 图片与预览生命周期、键盘定位与输出失败恢复、组合候选提交。未运行完整 loop，不把局部通过记为全量资格通过。

LibreOffice 26.8.1.1 分别重开保存的值工作簿和公式工作簿。CSV 输出确认数值/布尔/前导零/中文，及同表/跨表合计、共享引用与 `#DIV/0!`。它是独立重开检查，不代表 Excel 或视觉等价。运行产物与初始失败保留在本地 `.temp/p5-xlsx/`、`.temp/p5-reference/`，来源和摘要登记在私有 `cases/p5-xlsx.json`。

固定 ONLYOFFICE document-templates `71430c9f183489e8912f54f9dc859e369cf0dfb4` 的 `new/en-US/new.xlsx` 与 `sample/sample.xlsx` 按原字节入库，保留 Apache-2.0 LICENSE 与 AUTHORS。公式类型转换与 IF 分支规则参考 sdkjs [统计函数](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/statisticalFunctions.js)、[SUM](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/mathematicFunctions.js)与 [IF](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/cell/model/FormulaObjects/logicalFunctions.js)。参考源码未作为新增生产依赖。

## 保留限制

不包含新建向导、工作表/行列增删、样式编辑、自动填充、排序筛选、冻结窗格交互、条件格式、图表、透视表、图片编辑和协作。不支持六个函数以外的公式库，以及名称/结构化/外部/三维/整行整列/数组/动态数组/易变/迭代计算。

打印只针对当前表一个矩形，使用明确参数，不自动套用复杂文件打印设置。跨边界合并、超页单行列、未计算公式及未呈现显示/对象拒绝输出。字体需要调用方提供，保真不等于整个 ZIP 字节一致。

未做性能专项、海量压测、发布验收、其他浏览器、Windows/Excel、VoiceOver 或新增系统候选窗验收。现有文件、计算、历史、队列、字体、Canvas 和输出预算保持；实际阻断使用时再诊断性能。
