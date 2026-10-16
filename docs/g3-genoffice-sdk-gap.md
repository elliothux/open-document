# G3 GenOffice 功能对照与全功能 SDK 差距

状态：`research`。本文件记录 2026-10-14 的源码对照，不代表运行验收或功能已经实现。目标与职责归 [SDK 合同](references/sdk.md)，实施顺序归[路线图](references/roadmap.md)，当前支持范围归[格式合同](references/formats.md)。

## 结论与对照口径

P0–P8 已提供四类文件的有限读写和编辑底座，P9 已接通这些能力的默认 UI。距离 GenOffice 的功能面，主要缺口仍是文档操作、布局、计算和保存能力。后续需要按操作同时补齐核心、API、UI 和保存，不能只增加面板或继续扩大测试。

本地 `references/genoffice` 用于回答“有哪些功能、如何操作”。本次读取的 revision 为 `5eab98adc8d0ebf6ecea687e42400a791ef58d64`。下面的固定源码链接对应这一快照。Office 实现、布局、算法与兼容行为优先参考 ONLYOFFICE，其次 LibreOffice；GenOffice 的技术栈不作为引擎迁移目标。App 只用于视觉对比验收与交互参考。

| 标记 | 本文含义 |
| --- | --- |
| P0 | 功能优先级：先补核心操作及必要的 SDK/UI、读写和布局 |
| P1 | 功能优先级：扩展文件兼容、复杂特性覆盖和性能 |
| P2 | 功能优先级：次要与外围能力，包括 AI、协作、Diff |
| P0；扩展 P1 | 操作本身在 P0 可用；复杂文件变体和长尾行为在 P1 扩展 |
| 阶段 P9 等 | 路线图的阶段编号，与上面的功能优先级分开 |

“已有”只指本项目当前声明的有限范围。“缺”指未形成对应的完整操作，不否认底层已有可复用类型或解析代码。保存未知 XML、拥有菜单项、存在操作类型或有测试文件，都不能独立证明该功能已可用。下表按功能族整理；实施时继续从操作入口追到执行、保存与参考行为，不把函数名数量当成功能完成率。

## 文档：DOCX

GenOffice 的主要依据是 [DOCX 引擎导出][d-engine]、[Ribbon][d-ribbon]、[插入][d-insert]、[布局][d-layout]、[引用][d-references]和[文件操作][d-file]。当前项目依据 [P3](implemented/p3-docx-preview.md)、[P4](implemented/p4-docx-editing.md)与 [`FoundationClient`](../packages/web/src/foundation.ts)。

| ID / 功能 | GenOffice 源码中的能力与限制 | 本项目已有与缺口 | 优先级 |
| --- | --- | --- | --- |
| D01 新建、打开、保存 | 新建空白 DOCX、打开、保存/另存；有恢复副本流程 | 已有空白 DOCX 创建、打开、保存/另存及 P9 故障恢复；首次保存与下载状态分开。其他创作能力仍按以下缺口实施 | P0 |
| D02 文本编辑与剪贴板 | 富文本输入、撤销重做、查找替换；HTML/Markdown 粘贴与粘贴选项 | 已有普通正文/单元格纯文本、IME、历史、纯文本剪贴板；缺富文本片段、软换行、查找替换与选择性粘贴 | P0 |
| D03 字符格式 | 字体、字号、粗斜体、颜色、高亮等 Ribbon 操作 | 已有字体/字号/颜色/粗斜体、单下划线、删除线、高亮与上下标的混合查询、修改、清除直接属性、格式复制、预览和 PDF；其余装饰变体待兼容扩展 | P0；扩展 P1 |
| D04 段落格式 | 对齐、缩进、行距、段距、制表位等编辑 | 已有左右/居中/两端对齐、缩进、段距、行距、段前分页与软换行/Tab 输入、五类自定义制表位、引导线、继承清除、默认间隔编辑及 RTL 段落/制表定位；缺其余分页约束和标尺联动 | P0；扩展 P1 |
| D05 样式与主题 | 样式应用/修改、默认字体、主题颜色与字体 | 已有有限继承、段落/字符样式目录、应用、清除、修改、派生/无基础新建、首个样式部件创建、自定义样式删除及历史。删除同步替换引用；默认 UI 提供名称、基础样式和全部已支持属性的保留/设置/恢复继承。已有默认及四类基础样式格式重置、链接自定义样式删除与解链；缺其他内置重置规则与主题编辑 | P0；扩展 P1 |
| D06 列表 | 项目符号、编号、自定义多级列表与重新编号 | 已有常用编号读取、创建、应用、移除、层级/重启、自定义级别模板及标记格式、Enter/Backspace/Tab 规则、单项历史、保存重开与预览/PDF；图片项目符号、编号样式绑定及其他地区格式待兼容扩展 | P0；扩展 P1 |
| D07 页面与节 | 纸张、方向、边距、分栏、分节、分页/分栏符、页码设置 | 已有单节页面尺寸/方向/四边距、正文分页符编辑、默认 UI 与原生快捷键、原子节属性创建、历史、保存重开及同布局 PDF；缺表格内分页、多节/多栏、分栏符编辑与页码 | P0；扩展 P1 |
| D08 页眉页脚 | 页眉页脚编辑，首页/奇偶页区别及页码 | 仅有限空页眉空间；缺实际内容编辑、继承关系与分页布局 | P0；扩展 P1 |
| D09 表格结构 | [插入/删除行列、合并拆分、拆表、表格导航][d-table] | 已有正文固定网格创建、范围替换/拆段、行列增删、指定矩形合并与取消合并、格内输入、Tab 导航、历史、保存重开和 PDF；缺任意拆格、鼠标跨格选择、合并格行列编辑、拆表和嵌套处理 | P0；扩展 P1 |
| D10 表格属性 | [自动调整宽度、边框底色、单元格边距、对齐、重复表头与浮动][d-table-props] | 已有少量显示属性；缺属性编辑、跨页行、复杂边框和浮动布局 | P0；扩展 P1 |
| D11 图片 | 插入、替换、大小、位置、环绕、层次等 | 只显示有限内联图片；缺创建/替换/删除、裁剪与浮动环绕 | P0；扩展 P1 |
| D12 图形与文本框 | 形状、线、文本框、WordArt、定位和环绕 | 缺对象模型、编辑几何、图文混排和序列化 | P0；扩展 P1 |
| D13 图表 | 创建/修改图表 XML 与嵌入工作簿，提供插入入口 | 缺图表模型、数据编辑、绘制和嵌入关系维护 | P0；扩展 P1 |
| D14 公式与符号 | LaTeX/OMML 转换、公式编辑与符号插入 | 缺数学公式布局与写回；普通字符输入不等于公式支持 | P0；扩展 P1 |
| D15 目录与字段 | 从标题生成/更新目录；[显示、修改和更新字段][d-fields]；交叉引用 | 字段等常触发只读保护；缺字段求值、锚点随编辑更新及分页后的目录更新 | P0；扩展 P1 |
| D16 链接与书签 | 超链接、书签、交叉引用入口及保存 | 缺创建/修改/导航和引用完整性维护 | P0 |
| D17 脚注、尾注与引用 | 脚注/尾注、题注、索引、引文与书目；另有 Zotero 入口 | 缺内容模型、编号、引用更新和分页；Zotero 接入单列外围能力 | P0；Zotero P2 |
| D18 批注 | [范围/单词/光标锚定批注、回复和删除][d-comments] | 缺批注锚点、线程、面板与写回 | P0 |
| D19 修订 | [跟踪修改、接受/拒绝、作者筛选、定位修订][d-revisions] | 现有未知修订保护不能代替修订编辑；缺语义、显示与接受/拒绝事务 | P0；扩展 P1 |
| D20 文档比较 | [段落序列差异和变化面板][d-compare]，不是生成可合并的 Word 修订文档 | 缺比较 API 与 UI；不作为基础编辑的前置条件 | P2 |
| D21 设计与绘注 | 封面、页面背景、水印、边框、墨迹等入口与序列化 | 缺相关对象/页面属性与交互；优先完成可保存的常用操作 | P0；扩展 P1 |
| D22 导航与校对 | 标题导航、标尺、字数、查找；拼写替换/自动更正有平台依赖 | 已有正文/单元格字面查找、结果定位、单项/全部替换及历史；缺标题导航、标尺与统计查询；校对词库和服务须另定宿主边界 | 导航 P0；校对 P2 |
| D23 保护与加密 | 编辑保护；[Node 中解密 Standard/Agile DOCX，并写出 Agile 加密文件][d-encryption] | 已有保护性拒绝；缺可用的保护编辑和加密文件流程，不能直接移植 Node 路径 | 保护 P0；加密 P1 |
| D24 输出 | DOCX、PDF、图片、HTML、Markdown；PDF/图片含桌面导出路径 | 已有有限同布局 PDF；缺完整页面输出、图片/HTML/Markdown 导出和打印 UI | P0；保真扩展 P1 |

实施归 [P10 技术方案](p10-docx-core.md)；复杂排版与导入变体在阶段 P14 扩展。以 ONLYOFFICE 的布局和编辑规则补全核心，保留已有 LibreOffice 证据的真实来源。不能直接把 Tiptap 文档树或 DOM 测量结果变成本项目权威状态。

## 表格：XLSX

GenOffice 使用 Univer OSS UI/计算能力与自身网关、sidecar 和写回代码。依据 [Ribbon 操作][s-ribbon]、[操作定义][s-dsl]、[操作执行][s-executor]、[表结构操作][s-workbook]、[透视表][s-pivot]和[公式边界用例][s-formulas]。当前项目依据 [P5](implemented/p5-xlsx-editing.md)与 [`XlsxClient`](../packages/web/src/xlsx.ts)。

| ID / 功能 | GenOffice 源码中的能力与限制 | 本项目已有与缺口 | 优先级 |
| --- | --- | --- | --- |
| S01 工作簿与工作表 | 新建；工作表增删、重命名、复制、移动、隐藏 | 已有空白创建、首次保存/另存/重开、切表、新增、复制、删除、重排、改名和隐藏/显示；部件增删与 XML 历史一起恢复，名称作用域和活动页索引同步；复制更新自身引用与局部名称，普通批注独立；改名更新已支持引用，删除生成引用错误并重算，保留字符串常量；缺更广资源及引用更新 | P0 |
| S02 值与范围 | 值/公式/范围编辑、批量操作、清除、复制粘贴与选择性粘贴 | 已有单格和矩形输入、纯文本 TSV、清除与历史；缺格式/公式感知的片段与复制移动语义 | P0 |
| S03 单元格格式 | 字体、颜色、填充、边框、对齐、换行、格式刷、数字格式 | 已接通有限格式编辑、局部样式复用及 UI；核心历史、默认属性栏、原生草稿、独立 XML、保存重开及格式化公式 PDF 已检查；已支持矩形格式刷、单次/连续跨表应用与取消；已接通三种清除操作及精确历史；既有条件/验证规则支持局部清除和引用平移；未知规则、批注和未知资源继续保护；缺合并格格式刷与更广格式 | P0；扩展 P1 |
| S04 行列与单元格结构 | 行列/单元格插入删除、隐藏、宽高和自动适配 | 已有行高、列宽及零值隐藏的核心/API/UI、历史和保存重开；拆分列区间保留相邻样式，网格/命中/打印使用相同尺寸；已有按当前显示值自动适配、字体度量、精确历史和原生草稿后的 UI 流程；已适配行高随内容/列宽更新，bestFit 列随数值、布尔、错误及跨表结果扩宽，并与编辑共享一次历史；默认行已支持带字体编辑时自动行高；未编辑导入行的首次测量、插删及相关引用/图形锚点修正待实现 | P0；扩展 P1 |
| S05 合并与冻结 | 合并拆分、冻结首行/首列/当前位置、取消冻结 | 已有矩形合并/取消合并、丢弃确认、依赖/验证更新、格式、历史及 PDF；外围边框已有归并、源颜色关联保留和内线清除；更广资源与冻结视图待实现 | P0 |
| S06 常用公式 | 公式栏、函数输入和重算，覆盖明显超过六个函数；并非所有 Excel 公式 | 只有 SUM/AVERAGE/MIN/MAX/COUNT/IF；补逻辑、文本、日期、查找、统计等常用函数族与错误值 | P0；扩展 P1 |
| S07 引用与公式兼容 | 名称、跨表、较广引用；外部/区域化公式等存在保留缓存或拒绝路径 | 不支持的公式/依赖或导入环会使整本只读；须细化安全编辑范围，扩展名称、引用和重算语义 | 核心可编辑性 P0；变体 P1 |
| S08 填充 | 四向填充、序列填充与快速填充入口 | 缺序列推导、相对引用平移和填充柄 | 基础填充 P0；快速填充 P2 |
| S09 查找与数据导航 | 查找替换、名称与定位、范围跳转 | 缺跨工作表查询/替换及面板；现有网格键盘导航只覆盖基础移动 | P0 |
| S10 排序与筛选 | 升降序、自定义排序、筛选、重新应用和高级筛选 | 缺排序/筛选模型、隐藏结果和引用/行数据一致性 | P0；扩展 P1 |
| S11 条件格式 | 规则、颜色刻度、数据条等；部分扩展规则受保存保护 | 已能随清除拆分既有范围并平移公式；缺规则模型、计算、显示及创建/修改 | P0；扩展规则 P1 |
| S12 数据验证 | 数值/日期/列表等验证、提示和错误处理；扩展特性有保护 | 既有规则支持随全部清除拆分范围并平移公式；缺输入约束、下拉、粘贴时校验及规则创建/修改 | P0；扩展 P1 |
| S13 结构化表 | 表格创建、样式与部分行列操作；已有表与会话新建表的可操作范围须分开 | 缺表对象、列名/结构化引用、扩展区域、总计行和样式 UI | P0；复杂已有表 P1 |
| S14 透视表 | 创建/刷新、字段布局；有分组、筛选和计算相关实现 | 缺缓存、聚合、布局、字段面板与写回；不以普通值矩阵冒充可刷新透视表 | P0；扩展 P1 |
| S15 切片器与时间线 | 有创建与透视筛选入口、关联数据结构 | 缺控件、关系和筛选状态；与透视表一起形成操作闭环 | P0；扩展 P1 |
| S16 图表与迷你图 | 图表增改、系列/数据编辑、迷你图；支持面依图表类型 | 缺图表对象、数据绑定、绘制和保存；共用绘制能力不能代替 XLSX 图表语义 | P0；类型覆盖 P1 |
| S17 图片与绘图 | 图片、图形、文本框；符号/公式/图标等入口 | 缺对象锚点、插入/删除/变换/层次和序列化 | P0；扩展 P1 |
| S18 数据工具 | [分列、去重等数据操作][s-data]，以及导入入口 | 缺预览、区域变化、撤销和保存；不先建通用数据平台 | P0 |
| S19 批注与链接 | 线程批注、回复/解决、旧便笺、超链接 | 缺批注与链接模型、锚点及 UI | P0 |
| S20 保护与分组 | 工作表/工作簿保护，行列分组与折叠 | 仅已有有限安全拒绝；缺保护设置、授权操作判断与大纲 | P0；兼容 P1 |
| S21 公式辅助与视图 | 公式显示、追踪引用、错误检查、统计、网格/标题/RTL 显示 | 缺辅助查询与展示；常规公式栏/状态栏先交付 | 常规视图 P0；诊断工具 P2 |
| S22 打印与 PDF | 页面设置、缩放分页、页眉页脚、重复标题、视觉对象输出 | 仅当前表矩形、100% 比例基础分页/PDF；缺这些设置、打印区域和完整输出 | P0；兼容 P1 |
| S23 CSV/TSV/XLS | [CSV/TSV 转工作簿；旧 XLS 打开为转换副本；CSV 保存有格式损失提示][s-open] | 只有粘贴 TSV；缺文件导入和 CSV 导出。旧 XLS 转换与原格式编辑须分开声明 | CSV/TSV P0；旧 XLS P1 |
| S24 大表与保存范围 | 稀疏/流式会话、网关操作与原包写回；涉及图形/表/引用时存在操作保护 | 已有稀疏模型与预算；缺真实复杂工作簿的可编辑覆盖和大表交互优化 | 可用性 P0；覆盖/性能 P1 |

实施归 [P11 技术方案](p11-xlsx-core.md)，先解决“常用工作簿能继续编辑”，再扩展数据分析能力。不能通过忽略未知公式、写入猜测值或取消保护来消除整本只读。应记录依赖影响，保留未知内容，仅开放已能证明安全的操作。GenOffice 的旧说明与较新代码存在范围差异，流式会话和结构操作以对应执行路径为准，不照抄旧 README 的限制。

## 演示：PPTX

依据 [幻灯片操作][t-slides]、[对象插入][t-insert]、[对象编辑][t-elements]、[表格][t-tables]、[排列][t-arrange]、[IPC 操作入口][t-ipc]与[放映实现][t-show]。当前项目依据 [P6](implemented/p6-pptx-editing.md)与 [`PptxClient`](../packages/web/src/pptx.ts)。

| ID / 功能 | GenOffice 源码中的能力与限制 | 本项目已有与缺口 | 优先级 |
| --- | --- | --- | --- |
| T01 文稿与幻灯片结构 | 新建、增删复制/移动页、隐藏、章节管理、插入其他 PPTX | 已有空白创建、首次保存/另存/重开、空白页新增、页复制/删除/重排与隐藏/显示的核心/API/UI；部件增删与对象编辑共同恢复，复制更新对象/计时目标并独立复制备注和传统批注，删除同步已知链接和自定义放映，静态 PDF 按页序与隐藏选择输出；缺更广复制资源、章节与跨文稿合并 | P0；合并兼容 P1 |
| T02 页面设计 | 页面尺寸、背景、版式、主题应用 | 能读有限主题/版式/母版；缺设计编辑和引用写回 | P0；扩展 P1 |
| T03 母版 | [母版/版式视图及对象、文本编辑][t-master] | 缺母版编辑模型、占位符继承重算与 UI | P0；扩展 P1 |
| T04 对象创作 | 形状、文本框、线条、连接线、墨迹等插入删除和复制粘贴 | 已有文本框/矩形/圆角矩形/椭圆/线及四向实心箭头插入，本地顶层形状/图片单对象复制删除、稳定身份、源格式和撤销保存；锁定/继承/连接及计时引用保护。缺更多形状、墨迹、剪贴板资源和连接关系编辑 | P0 |
| T05 选择与几何 | 多选、移动、缩放、旋转、翻转、对齐、分布 | 已有本地顶层单对象移动/缩放、旋转和局部水平/垂直翻转，核心/API/UI 与保存/PDF 共用矩阵；缺多选事务、对齐、分布与辅助线交互 | P0 |
| T06 组合与层次 | 组合/取消组合、置顶置底及相对层次调整 | 已有本地顶层对象置顶/置底和前移/后移一层；能读取部分组变换；缺组合编辑及局部/全局坐标转换事务 | P0 |
| T07 文本格式 | 字符格式、段落、项目符号、文本框属性、查找替换 | 只有现有文本框纯文本编辑与有限格式显示；缺格式、列表及跨框查询 | P0；扩展 P1 |
| T08 文本排版 | 垂直锚定、边距、自动适配等；复杂排版依引擎支持 | 缺完整适配、多栏/竖排/编号与边界行为；按 ONLYOFFICE 规则实现 | 基础 P0；复杂排版 P1 |
| T09 形状样式 | 填充、渐变/图片填充、描边、效果、形状调整与自定义几何 | 只有有限基础形状、纯色与实线；缺样式编辑和复杂图元 | 常用编辑 P0；覆盖 P1 |
| T10 图片 | 插入/替换、裁剪、透明度、变换等 | 仅有限图片呈现及对象移动/缩放；缺资源替换、图片编辑与 UI | P0；扩展 P1 |
| T11 表格 | 创建、行列操作、合并拆分、单元格文本和样式 | 表格不在现有编辑/渲染范围；需完整表对象与排版 | P0；扩展 P1 |
| T12 图表 | 图表插入、类型/系列/数据编辑及关联工作簿 | 缺图表数据、布局、编辑与资源写回 | P0；类型覆盖 P1 |
| T13 SmartArt | 以形状组插入简化 SmartArt，随后按组/形状编辑；不是完整原生 diagram 编辑器 | 缺模板布局和组内编辑；复用形状/组合，不前置完整 SmartArt 引擎 | 模板 P0；原文件兼容 P1 |
| T14 公式与艺术字 | [公式操作写入 OMML，当前显示使用线性文本 fallback][t-equation]；艺术字是预设样式文本框，部分变形只读 | 缺插入/修改和相应格式支持；逐步复用 DOCX 数学/文字底层，分别声明存储和显示范围 | 常用对象 P0；显示/效果覆盖 P1 |
| T15 音视频 | 插入媒体、放映中的媒体层与播放动作 | 只有未知资源保留；缺媒体对象/时间状态、宿主播放与序列化 | P0；编码兼容 P1 |
| T16 链接与动作 | 对象/文本超链接与页间跳转 | 缺链接编辑、导航动作与输出链接 | P0 |
| T17 备注、批注、页脚 | 演讲备注、批注、日期/编号/页脚设置 | 缺内容模型、编辑与保存；本地批注不依赖实时协作服务 | P0 |
| T18 放映与演讲者视图 | 放映、页导航、演讲者视图、画笔与媒体播放 | 只有编辑视图和静态 PDF；缺放映会话、导航和演讲者 UI | P0；多窗口宿主 P2 |
| T19 切换与动画 | 切换属性、对象动画、顺序/触发/计时编辑；[播放实现采用效果近似][t-animation] | 动画/切换仅源保留；缺核心时间线语义、播放状态与显示执行 | 基础播放 P0；效果兼容 P1 |
| T20 3D 对象 | `addModel3d` 嵌入模型和 poster，不据此证明完整实时 3D 编辑 | 缺嵌入对象操作；是否需要实时 3D 另列实际差距，不扩大上游承诺 | P2 |
| T21 输出与打印 | PPTX、图片、PDF 与打印；[PDF 使用 Electron printToPDF][t-pdf] | 已有支持页的静态 PDF；缺完整对象覆盖、图片输出与打印界面；继续使用可移植核心 PDF | P0；保真 P1 |
| T22 导入与保护 | [旧 PPT 和加密 OOXML 有明确拒绝路径][t-main]；复杂对象仍有各自限制 | 已有限 Transitional PPTX 保护与保存；扩展时不把“全功能”解释为 GenOffice 已支持所有旧格式 | P1 |

实施归 [P12 技术方案](p12-pptx-core.md)。媒体解码和播放设备在宿主，文档对象、动画触发与时间关系在核心。Renderer 接收确定的显示状态；不在 React 或 Canvas 层建立另一套幻灯片模型。

## PDF

依据 [操作入口][f-ipc]、[编辑操作][f-ops]、[保存与页面操作][f-save]、[文字编辑][f-text]、[图片编辑][f-image]和[阅读界面][f-app]。当前项目依据 [P7](implemented/p7-pdf-input.md)、[P8](implemented/p8-pdf-operations.md)与 [`PdfClient`](../packages/web/src/pdf.ts)。

| ID / 功能 | GenOffice 源码中的能力与限制 | 本项目已有与缺口 | 优先级 |
| --- | --- | --- | --- |
| F01 阅读与导航 | PDF.js 预览、缩略图、目录/大纲、链接、搜索、双页等 | 已有基础默认 UI、有限图文与页内选择/提取/搜索；缺缩略图、大纲、链接、跨页体验和更广绘制覆盖 | 阅读 UI P0；绘制兼容 P1 |
| F02 新建与文件流程 | 新建 PDF、打开、保存/另存、打印和导出 | 已有统一打开/保存状态、有限修改保存和另存；缺新建及完整打印/输出 UI | P0 |
| F03 页面整理 | 重排、旋转、删除、空白页、插入、替换、提取 | 只有重排/旋转/删除；缺跨文档对象导入、页引用修正及其他操作 | P0 |
| F04 合并与拆分 | 合并文档/页面、拆文档、拆页 | 缺文件级操作、输出集合与关系保留 | P0；复杂引用 P1 |
| F05 页面几何 | 页面尺寸、裁剪和拆页 | 缺编辑页面框、内容/批注变换与写回 | P0；边界兼容 P1 |
| F06 文字编辑 | PDFium/内容流文字替换、插入、字体处理；不承诺任意段落自动重排 | 只能查询/选择文字；缺源文字对象修改、字体子集、度量及编辑 UI | P0；字体兼容 P1 |
| F07 图片编辑 | 图片对象编辑、插入等操作及保存 | 只能显示部分原图；缺图像对象定位、资源替换、变换和写回 | P0；编码兼容 P1 |
| F08 文本标记 | 高亮、下划线、删除线等选区标记 | 只有有限高亮；缺其他标记类型、外观和统一编辑 | P0 |
| F09 绘图批注 | 墨迹、矩形、椭圆、直线、箭头、图片等 | 缺类型模型、创建/变换、外观流和保存 | P0 |
| F10 便笺与讨论 | 便笺、已有便笺编辑、回复线程与删除 | 只有有限便笺；缺完整回复/关联、属性与面板 | P0 |
| F11 印章与签名外观 | 印章、自定义图片和手写签名外观 | 缺对象编辑及资产接入；外观不等于密码学数字签名 | P0；资产管理 P2 |
| F12 水印与页眉页脚 | 水印、页码、页眉页脚等批量叠加 | 缺批量对象插入、定位、预览和保存 | P0 |
| F13 表单填写 | 文本、复选/单选、下拉等字段；静态表单有额外填写交互 | 只支持部分已有文本字段与复选框；缺其他字段、外观与行为 | P0；复杂表单 P1 |
| F14 表单设计 | 创建字段、调整 widget、编辑属性 | 缺字段创建/删除、分组/命名与可视设计 | P0 |
| F15 真正遮盖删除 | [PDFium redaction，针对复用图片和 Form 等危险情况拒绝][f-redaction] | 缺安全移除内容与输出检查；页面删除保留未引用对象，不等于脱敏 | P0；安全与完整性同步完成 |
| F16 加密与密码 | PDF.js 可打开加密文件；源码把加密文档编辑设为只读 | 当前不支持加密输入；先实现明确的查看/权限边界，不能把上游只读误记为可编辑 | P1 |
| F17 数字签名 | [证书签署][f-sign]、[签名检查][f-signatures]，依赖 Node/证书接口 | 缺签署与验证；现有签名保护不验证签名。不据此承诺完整 PAdES/LTV | P2；受保护文件保全始终保留 |
| F18 OCR | [调用 macOS Vision/Windows OCR 辅助程序][f-ocr]；无引擎可用时失败 | 缺浏览器 OCR、扫描页识别与文本层；需可用本地组件或明确的宿主接入 | P2 |
| F19 PDF 转 Office | [PDFium 提取→结构分析→DOCX/XLSX/PPTX 重建][f-convert]；输出有告警，扫描件另需 OCR | 缺三个转换方向；依赖对应 Office 创建/序列化，不承诺恢复原始编辑结构 | 文本型 PDF P0；保真 P1；OCR P2 |
| F20 其他输出 | 图片、打印，以及 Markdown/HTML 转换入口 | 缺图片/结构化文本导出和完整打印 UI；不能用截图替代可编辑 Office 输出 | P0；保真 P1 |
| F21 元数据与文档结构 | 保存路径包含元数据修改；阅读侧有大纲/图层等读取 | 部分结构仅保留/保护；补已确认的读取/编辑入口。不推断已有附件管理或任意书签编辑 | 常用元数据 P0；结构兼容 P1 |
| F22 格式、字体与图形覆盖 | PDF.js/PDFium 与 pdf-lib 分担读取/修改；各自限制不同 | 仅有界 PDF 1.0–1.7 子集；缺较广字体、色彩、图像过滤器、透明/图案等 | P1；阻塞核心操作时提前 |

阶段 P13 补核心操作与输出。阶段 P14 扩展 PDF 文件覆盖。OCR、数字证书接入归阶段 P15，仍保留在全功能目标内。GenOffice 的保存代码会汇总部分未应用的编辑；本项目继续遵守自己的原子拒绝与恢复合同，不复制可能让调用者误判成功的行为。

## 共同 SDK、UI 与外围能力

GenOffice 是桌面应用组合，不能把其 IPC 或 AI 操作注册表直接当成可嵌入 SDK。Web 包提供按格式划分的 client 和编辑宿主；独立 UI 包接通现有能力。依据 [`packages/web/package.json`](../packages/web/package.json)、[`packages/ui/package.json`](../packages/ui/package.json)、[共享 UI 依赖][c-ui]和[设计变量][c-tokens]。

| ID / 能力 | 当前差距与交付方式 | 优先级 |
| --- | --- | --- |
| C01 可嵌入 SDK | P9 已提供 JS 挂载、同格式替换、保存回调、状态和释放。新建及新增输出能力随 P10–P13 接入；沿用现有会话 | P0 |
| C02 默认 UI | P9 已接通现有操作的 React/Shadow DOM Ribbon、面板、菜单与状态栏。后续格式操作随核心接入 | P0 |
| C03 状态与扩展 | 已有快照、历史和输出回执通知及自定义 UI 入口。后续格式属性和扩展点按具体需求补齐 | P0 |
| C04 多实例与资源 | 已接通实例内样式/Portal、焦点、输入、资源释放和保存恢复。当前检查边界见 P9，新输入路径随功能验证 | P0 |
| C05 包与接入说明 | 已有 ESM/types/内联 CSS、明确 Worker/Wasm/字体输入和普通 JS 示例；公开构建独立于 `test-lab`，尚未发布 | P0 |
| C06 兼容与性能 | 依据真实输入补四类格式覆盖；复用 R0，改善受影响的布局、重算、视口与资源热点。不给 Renderer 增加格式语义 | P1 |
| C07 AI | GenOffice 存在 AI 操作入口；SDK 后续提供宿主模型/服务与命令接入。密钥、上传、权限由宿主显式控制，不依赖特定服务 | P2 |
| C08 协作与版本 | 本次证据不足以证明 GenOffice 四类编辑器都有完整实时多人协作。本项目将协作列为目标扩展，待定义同步、冲突和持久化职责 | P2 |
| C09 Diff 与辅助工具 | DOCX 段落比较有明确源码依据；其他格式 Diff 及合并语义单独定义。校对、Zotero、公式诊断、OCR、数字证书分别按实际接口接入 | P2 |
| C10 跨宿主 | 复用核心与薄 Renderer 合同；CLI 和一个非浏览器宿主沿阶段 P16 实施。浏览器阶段不建设多语言绑定框架 | P2 |

C01–C05 的现有能力接入已在 [P9](implemented/p9-web-sdk-ui.md)完成；新建、格式修改等新增文档能力仍归 P10–P13。这里的完成不授予完整 GenOffice 功能。

共享底层按实际复用推进：字体/段落、图形、图表、数学、图片资源和 PDF 输出可逐项共用；DOCX 流式排版、XLSX 网格/计算、PPTX 场景与 PDF 源对象图保留各自语义。不要为四类文件建立一个包揽所有对象的抽象文档模型。

## 如何判定差距已补齐

每次选择表内一个操作，补齐必要的模型、命令、布局/绘制、API、UI 和保存。记录具体支持范围及仍留给 P1/P2 的差距。输出 API 应能在不挂载默认 UI 时使用，不能只完成 App 内部按钮。

只检查本次改变的用户路径和真实风险：操作结果、撤销、保存重开；跨部件改写时核对引用和未修改内容，输入/焦点变化时核对相关 IME 与键盘行为。视觉样式直接审阅。兼容与性能有明确输入或瓶颈后再扩展，不增加全组件快照、全格式矩阵或无依据的性能门槛。

本次完成了本地源码审阅，包括关键执行/保存路径和部分上游测试内容；没有运行 GenOffice 全功能流程，也没有重跑本项目产品测试。未发现的入口不等于上游绝对不支持。宏执行、完整旧格式、任意 OLE、完整 PDF/A/UA、XFA/表单脚本及完整实时 3D 未获得本次证据支持，不作为“GenOffice 已实现”的承诺。

## 固定源码依据

以下链接用于复核本地阅读结果，均固定到本次快照；不要求实现时照搬这些引擎。

[d-engine]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/docx-engine/src/index.ts
[d-ribbon]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/components/Ribbon.tsx
[d-insert]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/components/ribbon-insert-tab.tsx
[d-layout]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/components/ribbon-layout-tab.tsx
[d-references]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/components/ribbon-references-tab.tsx
[d-file]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/file-actions.ts
[d-table]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/editor/table-ops.ts
[d-table-props]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/editor/table-properties.ts
[d-fields]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/editor/field-codes.ts
[d-comments]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/editor/comments.ts
[d-revisions]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/editor/revisions.ts
[d-compare]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/renderer/editor/compare.ts
[d-encryption]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/docs/src/main/docx-encryption.ts
[s-ribbon]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/sheets/src/renderer/ribbon-actions.ts
[s-dsl]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/xlsx-gateway/src/domain/workbook-dsl.ts
[s-executor]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/sheets/src/renderer/op-executor.ts
[s-workbook]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/sheets/src/renderer/workbook-ops.ts
[s-pivot]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/sheets/src/renderer/pivot-actions.ts
[s-formulas]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/sheets/tests/formula-closure.test.ts
[s-data]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/sheets/src/renderer/data-tools-actions.ts
[s-open]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/sheets/src/main/sheets-main.ts
[t-slides]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/pptx-ops/src/ops/slide-ops.ts
[t-insert]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/pptx-ops/src/ops/insert-ops.ts
[t-elements]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/pptx-ops/src/ops/element-ops.ts
[t-tables]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/pptx-ops/src/ops/table-ops.ts
[t-arrange]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/pptx-ops/src/ops/arrange-ops.ts
[t-equation]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/pptx-ops/src/ops/equation-ops.ts
[t-ipc]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/shared/ipc.ts
[t-master]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/renderer/MasterView.tsx
[t-show]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/renderer/components/SlideShowView.tsx
[t-animation]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/renderer/animation-play.ts
[t-pdf]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/main/pdf-export.ts
[t-main]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/slides/src/main/slides-main.ts
[f-ipc]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/shared/ipc.ts
[f-ops]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/renderer/edit-ops/ops.ts
[f-save]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/main/save-pdf.ts
[f-text]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/main/text-edit.ts
[f-image]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/main/image-edit.ts
[f-app]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/renderer/App.tsx
[f-redaction]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/main/redaction.ts
[f-sign]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/main/pdf-sign.ts
[f-signatures]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/main/pdf-signatures.ts
[f-ocr]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/apps/pdf/src/main/ocr.ts
[f-convert]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/pdf2docx/src/index.ts
[c-ui]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/ui/package.json
[c-tokens]: https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/ui/src/tokens.css
