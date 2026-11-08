# 产品路线图

**当前目标：复刻 GenOffice 的文档、表格、PPT、PDF 全功能 SDK。** 本地 `references/genoffice` 是功能与 UI 交互参考，App 仅用于视觉对比验收和交互参考。Office 能力、布局、算法与兼容行为仍优先参考 ONLYOFFICE，其次 LibreOffice。完整目标与职责归 [SDK 合同](sdk.md)，源码差距见 [G3](../g3-genoffice-sdk-gap.md)。

项目未发布，当前有 0 个用户。按当前需求从 Day One 设计，可以直接修改最底层架构，只保留一条实现路径。兼容代码仅限文档格式。浏览器只覆盖 Chrome/Chromium，发布和规模化建设按真实需求安排。

2026-10-14 重排后，先补四类编辑器的核心功能，再扩大兼容与性能，接入外围能力，最后完成跨宿主。**功能优先级 P0/P1/P2 与阶段编号分开**：P0–P14 已完成声明范围，后续阶段为 P15、P16。2026-10-30 根据真实文件不可用反馈，先实施 [C0 兼容补齐](../implemented/c0-real-file-compatibility.md)，再进入 P15。证据与未补齐项统一见[兼容性矩阵](compatibility.md)。

| 功能优先级 | 范围 | 对应阶段 |
| --- | --- | --- |
| P0 核心功能 | 可嵌入 SDK、默认 UI、文档操作、必要布局/计算、保存及常用转换；普通文件打开/显示/保存的阻塞修复与分级降级 | P9–P13；C0 核心可用性修复；C1.1 分级降级基线 |
| P1 兼容与性能 | 复杂文件/格式变体、多生产工具与开源测试集覆盖、核心下沉与 ABI/算法性能优化 | P14 选定范围；R2 架构精简与性能重构；C0/C1 兼容扩展 |
| P2 次要与外围能力 | AI、协作、Diff、OCR、校对、证书等接入，以及次要宿主 | P15、P16 |

安全、保真、恢复、资源上限和无障碍随每个功能完成。使核心操作可用的布局、计算和格式支持属于 P0；不能以“兼容放 P1”为由留下不能保存的功能。卡死或无法交互的问题在阻塞的阶段处理。

## 已完成基础阶段

| 阶段 | 用户结果 | 状态 |
| --- | --- | --- |
| [P0 工程与运行底座](../implemented/p0-project-foundation.md) | 构建 SDK、文本会话与 Worker POC | implemented；不是 Office 功能 |
| [P1 字体与字形输出](../implemented/p1-sdk-foundation.md) | 塑形、BiDi、轮廓绘制和 PDF 路径验证 | implemented |
| [P2 文件与格式底座](../implemented/p2-format-foundation.md) | 有界 ZIP/XML/OPC、窄 DOCX 读写与保真保存 | implemented |
| [P3 DOCX 预览与 PDF](../implemented/p3-docx-preview.md) | 嵌入有限分页预览与同布局 PDF | implemented；非完整 Word 排版 |
| [P4 DOCX 编辑](../implemented/p4-docx-editing.md) | 限定正文/单个表格单元格编辑、撤销、剪贴板、保存重开 | implemented；非完整 Word 编辑器 |
| [P5 XLSX](../implemented/p5-xlsx-editing.md) | 网格、值、首批公式依赖、编辑、保存、基础打印 | implemented；限定公式与基础打印，非完整 Excel 兼容 |
| [P6 PPTX](../implemented/p6-pptx-editing.md) | 主题/版式、基础形状/文字/图片、编辑、保存/PDF | implemented；限定图文与静态 PDF，非完整 PowerPoint 兼容 |
| [P7 PDF 输入](../implemented/p7-pdf-input.md) | 有界解析、限定图文预览、页内选择、提取与搜索 | implemented；源坐标与独立文字映射，复用 R0 和固定 pdflite |
| [P8 PDF 文档操作](../implemented/p8-pdf-operations.md) | 页面重排/旋转/删除、便笺/高亮、文本字段/复选框、保存重开 | implemented；源对象图局部事务、保护规则与有界历史 |
| [P9 Web SDK 与默认 UI](../implemented/p9-web-sdk-ui.md) | 四格式现有操作的默认 UI、状态、保存/关闭与普通 JS 接入 | implemented；现有能力接入，不授予完整 GenOffice 功能 |

阶段 P0–P14 完成的是声明范围，不代表 GenOffice 功能已经齐全。PDF 正文编辑已在 P13 的明确范围交付；更广公式、效果与文件变体归 P14，OCR、数字签名等归外围阶段。完整 Microsoft Office/PDF 标准兼容、任意格式互转、宏执行和全语言绑定不由此自动成为承诺。

已有 Office → PDF writer 不依赖 P7 reader。P7 复用通用绘制，按 PDF 原坐标显示；P8 在原对象图上修改和保存，不通过页面重绘替代文档写回。共用同一核心/宿主合同，不按格式新建 Renderer。

## 后续阶段与顺序

| 阶段 | 用户结果 | 功能优先级 | 状态与依赖 |
| --- | --- | --- | --- |
| [P10 DOCX 核心功能](../implemented/p10-docx-core.md) | 创建、格式、页面/表格、图文、引用/审阅、图表/数学及保存输出 | P0 | `implemented`；六批最低范围已交付，复杂兼容归 P14 |
| [P11 XLSX 核心功能](../implemented/p11-xlsx-core.md) | 结构/格式、常用计算、数据规则、透视/绘图、交换与打印 | P0 | `implemented`；五批最低范围已交付，更广公式和复杂资源归 P14 |
| [P12 PPTX 核心功能](../implemented/p12-pptx-core.md) | 页面/对象、母版/文本、复合内容、放映媒体与输出 | P0 | `implemented`；五批最低范围已交付，复杂效果和导入变体归 P14 |
| [P13 PDF 核心功能](../implemented/p13-pdf-core.md) | 创建/阅读、页面/内容、批注/表单、脱敏与转换 | P0 | `implemented`；六批最低范围已交付，复杂 PDF 兼容归 P14 |
| [P14 兼容与性能](../implemented/p14-compatibility-performance.md) | 扩大真实文件覆盖，使复杂/大文件操作可用 | P1 | `implemented`；七个兼容批次、真实文件编辑与输出，以及 DOCX 首次布局优化 |
| [R2 架构精简、核心下沉与性能重构](../r2-architecture-and-performance.md) | 清理重复校验与转发胶水，二进制直通，渲染与图像逻辑下沉 MoonBit，核心算法提速与单格式 Wasm 拆分 | P0 / P1 | `planned`；R2.1–R2.3 优先实施，R2.4–R2.5 与 C1 配合推进 |
| [C0 真实文件可用性与兼容补齐](../implemented/c0-real-file-compatibility.md) | 首批 51 份候选文件能打开、主要内容可见，已支持操作可安全保存 | P0 / P1 | `implemented`；48 份正向与 3 份控制符合预期，128 条登记浏览器流程通过 |
| [C1 兼容矩阵整合、开源语料引入与多生产工具覆盖](../c1-corpus-and-producer-compatibility.md) | 统一兼容账本、局部特性分级降级、接入 IronCalc/Calamine/Open-XML-SDK 等测试集及多生产工具/CJK 样本 | P0 / P1 | `planned`；承接 C0，系统化扩大真实文件与标准向量覆盖 |
| [P15 次要与外围能力](../p15-peripheral-capabilities.md) | 原生 Diff、AI 命令事务、OCR/校对 Provider、PDF 签名与协作原语接入 | P2 | `planned`；在 R2、C0/C1 及 P16.1 核心独立闭环后逐项接入 |
| [P16 跨宿主与非浏览器运行时](../p16-cross-host-runtime.md) | 无浏览器核心闭环、CLI 和一个明确的非浏览器宿主复用同一核心 | P2 | `planned`；P16.1 核心独立性探针前置到 P15 之前，P16.2–P16.3 最后实施 |

**分步推进顺序：**

1. **第一步（架构减负与逻辑下沉）**：执行 [R2.1–R2.3](../r2-architecture-and-performance.md)，移除 TS 对 Wasm 输出的冗余校验，拍平 DOCX/XLSX 伪继承链，打通 `Uint8Array` / `Transferable` 二进制传输与字形轮廓增量下发，并将 `pdf-pixels.ts` 几何特判与图像头部解析收归 MoonBit。
2. **第二步（分级降级基线）**：[C0](../implemented/c0-real-file-compatibility.md) 已完成首批登记范围，继续落地 [C1.1](../c1-corpus-and-producer-compatibility.md) 的局部不支持特性分级降级（Graceful Degradation）与历史测试账本去重归并。
3. **第三步（开源语料扩充与核心性能攻坚）**：并行推进 [C1.2–C1.5](../c1-corpus-and-producer-compatibility.md)（接入 `IronCalc`、`calamine`、`Open-XML-SDK`、`excelize`、`ONLYOFFICE` 剩余样本及多生产工具/CJK 语料）与 [R2.4–R2.5](../r2-architecture-and-performance.md)（DOCX O(1) 段落缓存键与多节分页缓存、XLSX 强类型坐标与空间索引、单格式 Wasm 拆分编译）。
4. **第四步（无浏览器核心闭环探针）**：执行 [P16.1](../p16-cross-host-runtime.md)，在无 DOM/Canvas 的纯 Wasm 环境跑通四格式含图打开、编辑、重算、排版与 PDF/原格式输出，锁死核心与宿主边界。
5. **第五步（外围能力与跨宿主交付）**：按 [P15.1–P15.5](../p15-peripheral-capabilities.md) 接入原生 Diff、AI 批量事务、OCR/校对 Provider、PDF 签名与协作原语，最后完成 [P16.2–P16.3](../p16-cross-host-runtime.md) 的 CLI 与非浏览器宿主绑定。

跨格式工程重构 [R1 领域拆包与共享 Wasm 加载](../implemented/r1-domain-packages-shared-wasm.md)已完成。四格式有独立 package 和前端入口，共用唯一 Wasm 与公共 Loader；[R2](../r2-architecture-and-performance.md) 在此基础上进一步清理内部胶水并支持单格式 Wasm 产物。

### P9 Web SDK 与默认 UI（已完成）

用户结果：宿主加载公开构建产物，用普通 JS 挂载和释放编辑器。用户能通过默认 UI 完成当前已有的打开、编辑、撤销、缩放、保存和输出，明确看到不支持或只读的原因。

交付与足够检查归 [P9](../implemented/p9-web-sdk-ui.md)。UI 使用 React + open Shadow DOM + Tailwind CSS + Base UI（`@base-ui/react`）。R1 后，领域 React 面板与编辑宿主归各格式包，共用外壳归 `packages/ui`，输入和薄 Renderer 归 `packages/web-core`。已完成 G3 C01–C05 的现有能力接入，Office 新建与核心创作已由 P10–P12 交付，PDF 核心扩展已由 P13 交付。

### P10–P12 Office 核心功能（已完成）

[P10](../implemented/p10-docx-core.md)、[P11](../implemented/p11-xlsx-core.md)及 [P12](../implemented/p12-pptx-core.md) 已完成各自操作表的最低交付范围。核心、同步/Worker SDK、默认 UI、历史、保存重开及对应输出已接通。最近补齐脚注逐页编号、尾注位置、共享堆积折线图、合并计算和分类汇总，并通过所改流程的定向检查。

完成范围以三份结果和[格式合同](formats.md)为准。G3 仍保留真实差距：复杂嵌套/浮动、外部或动态引用、原生 diagram、长尾效果/媒体/旧格式及更广真实文件兼容按 P14 扩展；AI、协作、Diff、校对和其他外围能力归 P15。阶段完成不表示完整 Office 兼容，也不表示执行过当前工作树的全量测试。

### P13 PDF 核心功能（已完成）

用户结果：能够新建/整理 PDF，编辑受支持的文字和图片，完成批注、表单与真实脱敏，并进行常用输出和文本型 PDF 转 Office。对应 G3 F01–F22 的 P0 项。

交付结果归 [P13](../implemented/p13-pdf-core.md)。创建/阅读、页面整理、正文/叠加、批注/表单、真实脱敏、输出/转换六批最低范围已交付。基于 R1 的领域包与共享 Wasm，扩展现有源对象事务和多页资源；PDF → Office 在 MoonBit 中复用 P10–P12 的创建与保存。真实脱敏使用独立清理输出，普通删除和裁剪不承担脱敏语义。

当前 API 与保护边界归[格式合同](formats.md#pdf-输入与文档操作)，定向证据归[测试说明](testing.md)。更广文件兼容归 P14；OCR 和证书签名归 P15。已有签名、资源和完整性保护随核心功能保留。

### P14 兼容与性能（已完成）

用户结果：P10–P13 的操作能用于更广的真实文件，复杂和大文件的交互达到可用。对应 G3 各表的 P1 项。

交付结果归 [P14](../implemented/p14-compatibility-performance.md)。四份 XLSX、三份 DOCX、两份 PPTX、四份 PDF 及独立向量已完成声明的编辑、历史、保存重开与输出检查；其中一份 PDF 从上游向量派生，其余 12 份为上游原件。DOCX 4096 字符首次布局在固定的已就绪 Node 环境降低约 29.6%。完整资格基线与优化后定向结果分别绑定源码，详情归[测试说明](testing.md)。[C0](../implemented/c0-real-file-compatibility.md) 已完成首批登记范围，更广真实文件继续按 [C1](../c1-corpus-and-producer-compatibility.md)补齐。

按具体文件缺口推进：DOCX 复杂分节/浮动/表格/字段与字体排版，XLSX 更广函数/引用/格式规则与复杂结构，PPTX 图形/效果/动画/媒体和继承变体，PDF 字体/色彩/图像/透明与受保护输入。旧格式和加密输入逐条声明查看、转换和编辑范围；不自动承诺宏、任意 OLE 或全标准支持。

性能改进以实际瓶颈排序：核心增量布局/重算、可见范围计算、资源缓存与失效、Worker 传输、Canvas 执行和 UI 更新。能由共享核心解决的放入共享核心；Web 专属的调度、传输和表面复用留在 Web。沿 R0 增量修改，不新建另一套 Renderer 或先设计未知平台框架。

足够检查：兼容改动使用触发差距的样本及受影响的已有用例；性能改动记录同输入、同环境的前后结果，并检查文档输出和资源释放。没有实测依据时不设毫秒/体积门槛，不建立全量性能或浏览器矩阵。

### P15 次要与外围能力

用户结果：宿主可按需启用原生文档比较（Diff）、AI 结构化事务、OCR、校对、数字签名与实时协作原语。对应 G3 的 P2 项；详细分批计划归 [P15 方案](../p15-peripheral-capabilities.md)。

按 P15.1（DOCX/XLSX 原生 Diff）→ P15.2（AI 结构化命令与原子批量事务）→ P15.3（OCR 与校对 Host Provider）→ P15.4（PDF 数字签名核验与增量签署）→ P15.5（协作确定性事务与冲突重放）顺序实施。AI 与外部服务不能绕过 MoonBit 核心校验；上传、模型服务、凭据与授权由宿主显式提供。没有外部服务时能继续使用全部本地核心功能。

### P16 跨宿主与非浏览器运行时

复用同一 MoonBit 核心完成无浏览器环境的真实读取、编辑、计算、排版、保存与 PDF 输出。详细分批计划归 [P16 方案](../p16-cross-host-runtime.md)。

`P16.1 无浏览器核心独立性闭环` 前置到 [R2.3](../r2-architecture-and-performance.md) 之后执行，验证在禁用浏览器 DOM/Canvas/Image 全局对象的运行时中完成四格式操作与输出；`P16.2 CLI 工具` 与 `P16.3 非浏览器宿主接入` 在 P15 之后完成。数据操作和视觉输出分别验证；不预建全语言绑定生成器或通用运行时框架。

## 实施与完成口径

以上是阶段范围，不要求一次生成全部详细方案或一次完成整阶段。进入某阶段时，仅细化下一批用户操作及代码归属。G3 维护功能差距，SDK 文档维护职责，格式合同只记录已交付 API 与范围。

每个操作将核心、API、UI、保存和必要检查一起交付。完成 P0 核心功能不表示 P1/P2 已完成，也不把“有菜单”“能保留源文件”计为可编辑功能。文件读写、交互与视觉分别声明范围；执行细节见[测试说明](testing.md)。
