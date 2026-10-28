# P13 PDF 核心功能

状态：`implemented`。六批最低交付范围已接通 PDF 核心、同步 Wasm/Worker SDK、默认 UI、历史及保存或派生输出。基于 [P7](p7-pdf-input.md)、[P8](p8-pdf-operations.md)、[P9](p9-web-sdk-ui.md)及 [R1](r1-domain-packages-shared-wasm.md)。当前 API、字体与预算归[格式合同](../references/formats.md#pdf-输入与文档操作)，功能差距归 [G3](../g3-genoffice-sdk-gap.md#pdf)，后续归[路线图](../references/roadmap.md)。

## 已交付结果

| 批次 | 用户操作 |
| --- | --- |
| 创建与阅读 | 单页空白 PDF；打开、保存/另存、打印；单页/连续/双页阅读、按需缩略图、大纲和安全链接、搜索导航及跨页选择复制；标题、作者、主题和关键词 |
| 页面与文件整理 | 重排/旋转/删除、空白页、跨文件插入与替换、合并、提取/拆文件；页面框裁剪、纸张尺寸与内容缩放、矩形/网格拆页及多页合一 |
| 正文与叠加内容 | 可隔离源文字和图片的插入/替换/删除、位置/尺寸/旋转与文字样式；图片外观裁剪；原生输入草稿和可取消指针移动；批量文字水印、页眉页脚及明确更新的页码 |
| 批注与表单 | 便笺、高亮/下划线/删除线、矩形/椭圆/直线/箭头、多笔画墨迹、图片印章和可视签名；批注样式、回复与线程删除；文本、复选/单选、下拉/列表填写、创建、复制、命名、删除及 widget 设计 |
| 真实脱敏 | 标记区域、预览实际扩大移除范围、确认损失并导出独立清理副本；文字组/路径移除、私有图片像素清理、字体几何重建及危险输入原子拒绝 |
| 输出与转换 | 当前/选定/全部页 PNG/JPEG；结构化 HTML/Markdown 的段落、列表、线框表格、图片与安全链接；文本型 PDF 转原生可编辑 DOCX、XLSX、PPTX，返回逐页映射与损失说明 |

## 实现与完整性

`modules/formats/src/pdf/` 拥有源对象图、内容流定位、字体/图像资源、页面关系、字段/批注、候选事务与序列化。正文修改按源操作符和 Form 调用路径定位，修改一次共享出现时复制并重绑对应路径。未知映射、无法隔离的操作和不能同步的关系明确保护；预览完整不自动授予编辑、转换或脱敏能力。

有界视图各自绑定修订、页身份和字体版本；后台缩略图与输出不切换活动页或选区。Web 使用既有 Canvas、原生控件、输入队列及草稿/组合/拖动屏障；React 不解释 PDF 操作符或计算源坐标。内容、资源与关系一次提交，失败不改源和历史，撤销仍可恢复原保存字节。

普通保存继续保留未知源对象及未引用载荷。裁剪和对象删除也不提供安全擦除。脱敏从允许幸存的字形、像素和路径重建流及可达资源，移除批注/字段、链接、元数据、附件与旧修订；字体清理丢弃源程序和身份，仅保留必要字形几何、度量及授权记录。输出重新读取核对，未知许可、替代字体、无法精确重建的轮廓、危险图片/字段或不完整解释拒绝清理。

`modules/formats/src/pdf-convert/` 复用有界提取及目标格式原生创建/保存。DOCX 支持横排单栏段落、普通图片和明确线框表格；XLSX 支持明确边界的表格、合并及严格文本/数值；PPTX 逐页生成文本框、图片、表格和简单原生形状。扫描页明确需要 OCR，未知 Unicode 不猜字，不能把整页截图计为可编辑转换。损失先返回说明，明确接受后才交付带损失结果。

提取、拆分、转换、图片及 HTML/Markdown 输出及脱敏副本不改变源修改状态。即使派生结果仍为 PDF，`markSaved` 也拒绝；只有源 `save()` 产物可以确认源保存。临时目标会话和资源完成后释放，PDF 前端不依赖其他格式前端或第二个引擎。

## 检查与边界

公开 API/check/build 通过。定向核心、接口及 Chromium 流程覆盖六批操作的原生控件/指针、选择与生命周期、完整字节历史、失败原子性、保存重开及派生输出。PDF 结构、文本和像素沿用 qpdf/Poppler 独立核对；三种 Office 结果经目标 SDK 再编辑、保存重开并核对原生 XML。字体载荷清理、非标准 PDF 字距的整组语义、真实裁剪与边界浮点误差均有定向回归。共享字体/writer 的 Office 输出和同步/Worker 引擎路径另有直接受影响回归。

详细输入、运行记录和适用构建归[测试说明](../references/testing.md)及私有 `cases/p7-p8-pdf.json` 的 `p13Checkpoint`。复用路径未改变的已通过证据；未执行全量套件、其他浏览器、外部参考应用 GUI 或新的系统输入法验收。阶段完成只覆盖以上最低范围，不表示任意 PDF 均可编辑、可转换或可清理。

更广字体、色彩、图像过滤器、透明/图案、加密输入、复杂 Form/页面引用、Tagged PDF 和字段/批注变体归 P14。OCR、证书签署/验证、资产库、AI 与协作归 P15；可视签名不具有证书签署含义。图片裁剪保留原像素与 mask；真正脱敏仍须用户选择其他页面或复用位置的同类信息。完整 PDF/A/UA、PAdES/LTV、任意原 Office 结构恢复均不由此成为承诺。

## 固定源码依据

2026-10-28 核对本地引用。以下为设计依据，不是本项目运行验收，也不授予复制上游实现的许可；沿[依赖记录](../references/dependencies.md)保留许可证与来源。

- ONLYOFFICE [PDF 页面/字段/批注模型](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/pdf/src/document.js)、[可见页与缩略图调度](https://github.com/ONLYOFFICE/sdkjs/blob/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/pdf/src/viewer.js)：参考对象关系、操作及绘制优先级；不照搬 JS 权威模型。
- ONLYOFFICE [PDF 编辑与脱敏入口](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/PdfEditor.cpp)、[脱敏内容输出](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/PdfFile/SrcWriter/RedactOutputDev.h)：参考按源内容处理，不能据此断言本项目已具备安全清理。
- GenOffice [编辑操作](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/renderer/edit-ops/ops.ts)、[页面整理与保存](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/main/save-pdf.ts)：功能和交互覆盖依据；保留本项目原子提交与失败恢复。
- GenOffice [文字编辑](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/main/text-edit.ts)、[图片编辑](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/main/image-edit.ts)、[脱敏保护](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/main/redaction.ts)：核对可见操作与共享图片/Form/widget 风险，不移植 Electron、系统字体扫描或 Node 运行时。
- GenOffice [PDF → Office 入口](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/pdf2docx/src/index.ts)：提取、分析、目标重建和页级告警的功能依据；实际 Office 构建复用 P10–P12 核心。
