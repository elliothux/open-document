# 文件兼容性矩阵

2026-11-07 更新。本文维护输入覆盖、证据强度和未补齐项。[格式合同](formats.md)维护已交付 API；[C0](../implemented/c0-real-file-compatibility.md)维护首批 51 份候选原件修复；[C1](../c1-corpus-and-producer-compatibility.md)维护历史账本去重、开源测试集批量引入与多生产工具覆盖；[语料管理](corpus.md)维护来源与预期规则。

C0 首批 51 份候选已完成登记范围。48 份正向输入通过，3 份控制按预期拒绝。核心 251/251、四格式登记浏览器流程 128/128 通过。C43 原始工作表 30/30、重算后完整可见页 32/32 均为 0/0；原数据和属性保持。构建身份与复用范围归[测试说明](testing.md#当前兼容证据入口)。更广语料仍归 C1。

## 历史修复批次

以下保留各批当时的结果，当前资格以上方最终记录为准。

前批固定构建的全部 28 项登记 PPTX 兼容测试通过，覆盖 16 份固定原件的登记操作和补充控制。C13 的 130 组严格比较保持 0/0，整稿 48 份 SDK PDF 与获批正式批次相同。证据与构建、操作范围归[测试说明](testing.md#当前兼容证据入口)。

同一构建的 28 条登记 PDF 浏览器用例全部通过。C17 的 14 页及旋转共 28 组均为 0/0，保存、精确历史和 997 个源对象检查通过。私有 Poppler 参考工具已固定通用缓存范围修复，SDK 输出、原件与阈值保持。旧工具和失败证据保留，C43 仍未完成。[测试说明](testing.md#当前兼容证据入口)

C43 的两张复合饼图已按选定 ONLYOFFICE 外观显示为普通饼图，原始数据和属性保留。该批 69 项核心检查及两条正式组件流程通过，完整 Canvas/PDF 四组均为 0/0。组件参考统一固定 Arimo，并按原生工作区和打印路线分别比较。该批整表从 10/30 提高到 12/30。[测试说明](testing.md#当前兼容证据入口)

C43 散点图现匹配主引擎的逐点配色显示与稀疏缓存画笔。70 项相关核心和原始隔离图的完整 Canvas/PDF 对照通过，源保存及新 Worker 的 PDF 一致。整表第 5 页新增两组 0/0，严格结果提高到 14/30；其他 28 张 SDK 栅格和全部参考保持。完整 C43 仍失败。[测试说明](testing.md#当前兼容证据入口)

前批圆形图通过 34 项相关核心和两条正式隔离流程，完整 Canvas/PDF 四组均为 0/0。打印沿主引擎省略扇区底纹，保留轮廓、矩形底纹与源属性；工作区保持。整表第 4 页新增两组 0/0，该批严格结果提高到 16/30；其他 28 张 SDK 栅格及全部参考保持。[测试说明](testing.md#当前兼容证据入口)

前批使自动深度轴标题沿主引擎保持不可见，保留源属性、显式位置及布局留量。70 项相关核心通过。三张曲面图及堆积条图的完整 Canvas/PDF 均为 0/0，透视柱图 PDF 为 0/0，Canvas 仍为 0/5。该批整表第 1 页新增两组 0/0，结果提高到 18/30；第 14 页差异减少，其余 26 张 SDK 栅格及全部冻结参考保持。[测试说明](testing.md#当前兼容证据入口)

前批三维堆积面积批次通过 70 项相关核心检查。原件和独立真实零值控制的完整 Canvas/PDF 四组均为 0/0，源数据、原样保存及新 Worker 的相同 PDF 检查通过。范围累计和首点选面沿选定主引擎。整表第 8 页新增两组 0/0，结果提高到 20/30；其余 28 张 SDK 栅格及全部 30 张冻结参考保持。第 10–14 页仍失败。[测试说明](testing.md#当前兼容证据入口)

最新气泡图与曲面网格批次通过 73 项相关核心及八条正式流程。两张气泡图跟随主引擎显示为散点，保留原始尺寸和属性；曲面分类网格按边界绘制。原始工作表 15 页 Canvas/PDF 全部为 0/0，共 30/30。冻结参考及此前通过的 20 张 SDK 栅格保持。气泡图的完整工作区、重开和 62%/65% 整页打印对照通过。完整 C43 验收仍开放。[测试说明](testing.md#当前兼容证据入口)

共享填充直线描边修复后，透视柱图工作区 Canvas 从 0/5 降为 0/0，整页 PDF 保持 0/0。两张三维柱图正式流程及六项渲染回归通过。源保存、新 Worker 重开、参考与阈值保持。完整登记 XLSX 和跨格式验收仍在执行。[测试说明](testing.md#当前兼容证据入口)

C34 双页表单的原件、两页独立输入、精确历史、源对象保留和新 Worker 重开现已通过。核心重复闭合修复后，四组整页对照均为 0/0；按钮动作继续保护。该原件只有独立字段，具体范围与原生外观放置的证据限制归[测试说明](testing.md#当前兼容证据入口)。

C13 已采用用户批准的完整独立参考。48 页原稿的 96 组、三页修改后的六组和组件 28 组正式严格比较均为 0/0。七条 Chromium 用例通过，包含六条 C13 流程和一条共享 WMF 回归。SDK 输出、阈值、源保存及历史保持。旧参考的 78/96 与 5/6 失败证据保留。[测试说明](testing.md#当前兼容证据入口)

C13 第 28 页的居中表头和粗体后正文采用精确字宽，两处原点与原生绘图指令相差小于 0.001 pt。采用获批矢量与原生字形位置参考后，原件及去双色控制的四组整页比较均为 0/0。[测试说明](testing.md#当前兼容证据入口)

C43 两种面积图的数据目录现区分已知源错误和真实零值。55 项相关核心及默认编辑器、原样保存和新 Worker 检查通过。15 张打印预览和整份 PDF 与前批相同，整表仍沿用 10/30。[测试说明](testing.md#当前兼容证据入口)

C43 自动标题的行高现与等价显式标题一致。独立 PDF 的字形轮廓及基线坐标已核对。55 项相关核心通过；两张隔离图和整表的正式视觉复跑仍失败，整表保持 10/30。源保存、重开与完整拆分绘制保持。[测试说明](testing.md#当前兼容证据入口)

**当前不能认定真实 Office/PDF 文件已普遍可用。** P10–P14 完成了声明范围，但原始文件、生产工具和复杂特征组合的覆盖仍不足。用户报告多份 PPT/PDF 打不开或明显缺内容，作为系统性可用性问题处理。尚未确定每类失败的占比和根因；不要求用户提供特定文件才开始修复。

## 读取矩阵的方式

每份输入分别记录以下结果。成功解析、出现画布或输出了文件，都不能替代其他列。

| 操作 | 正向结果 | 不能计为正向通过 |
| --- | --- | --- |
| 打开 | 识别容器，建立会话，返回页/幻灯片/工作表及诊断 | 拒绝符合声明范围的文件；只保存原字节 |
| 显示 | 指定页面的文字、对象、位置、裁剪和层次与独立参考相符 | 空白页、缺对象、局部降级；只检查非空像素 |
| 读取语义 | 文字、顺序、数值、公式/缓存及选择位置正确 | 有字形却无法复制；缓存被当成重算结果 |
| 编辑 | 指定操作产生正确结果，失败不改源，可撤销/重做 | 仅新建内容可编辑；原对象只读 |
| 保存重开 | SDK 与独立工具能读取输出；目标变化正确，非目标内容保留 | 只检查 ZIP/XML 合法；只由 SDK 自己重开 |
| 输出 | 选定 PDF/图片/转换保留声明内容，损失有明确范围 | 出口返回 bytes，但漏页、缺图或语义不全 |

状态分别使用“已记录通过”“本轮实测通过”“失败”“未执行”“不支持”“部分/只读”。准备完成另记，不能当执行结果。“不支持”的拒绝可以通过保护检查，仍是兼容性缺口。引擎差异、参考缺失和环境阻塞单列，不归入通过。

覆盖按**内容 hash、操作、构建与环境**统计。同文件的多个操作不是多个独立样本。未经生产工具和特征分层，不报告笼统的“兼容率”。上游仓库文件数量也不是我们的覆盖率分母。

## 当前证据账本

C47 的 Strict XLSX 可只读打开。默认界面显示三张工作表、样式和公式结果，并逐字节保存原件。横向滚出原格后仍显示长文本尾部。两张有内容的工作表共四组独立同字体的整页预览和 PDF 对照均为 0/0。LibreOffice 另存及新 Worker 重开通过。[测试说明](testing.md#当前兼容证据入口)

C18 原件可在默认编辑器显式换用可嵌入字体替换正文。保存保留受限的源字体和原内容流。改后整页笔画覆盖为 0/0，独立提取文字、精确历史及新 Worker 重开通过。[测试说明](testing.md#当前兼容证据入口)

C23 原件的 CMYK 图片已通过默认编辑器移动、精确历史、源保留及保存重开。改后 Canvas 和独立重开的保存 PDF 均为 0/0。[测试说明](testing.md#当前兼容证据入口)

C39 两个链接文本框的原件及改后文件共四组 Canvas/PDF 整页对照为 0/0。源保留、精确历史及 SDK 和 LibreOffice 重开通过。[测试说明](testing.md#当前兼容证据入口)

C01 原件的 11 个版式按源顺序可用。继承标题输入、精确历史、源保留和 SDK/ONLYOFFICE 重开通过。原件与改后文件的四组整页 Canvas/PDF 均为 0/0。[测试说明](testing.md#当前兼容证据入口)

C13 第 28 页的原生表格与 WMF 图标已恢复正常显示及 PDF 导出。普通标题沿演示稿默认样式读取 Arial Bold，表格显式 Calibri 保持。原件与去除双色效果的整页控制均通过输入、精确历史、新 Worker 重开、完整单元格属性和 282 个非目标部件保留。获批参考下的两条正式用例及原色、双色 WMF 组件均为 0/0。参考范围见[测试说明](testing.md#当前兼容证据入口)。

| 证据入口（私有 `test-lab/`） | 已记录范围 | 本次审计结论 |
| --- | --- | --- |
| `cases/compatibility.json` | P2/P3 六案：三份有限 DOCX 正向、一份浮动图片拒绝、两份 PDF 准备记录 | 历史清单，不能继续充当四格式当前总矩阵 |
| `cases/lo-docx.json` | 20 份 LibreOffice DOCX 的读取/保留 | 不授予完整分页、编辑或视觉通过 |
| `cases/p5-xlsx.json`、`p6-pptx.json` | ONLYOFFICE new/sample 原件与功能派生输入 | 基础编辑、保护和源保留；复杂 sample 不等于整文件渲染通过 |
| `cases/p7-p8-pdf.json` | P7/P8 功能链及 P13 checkpoint | 支持范围内的功能证据；P13 多轮定向结果不能合并成当前全量资格 |
| `cases/p14-xlsx.json` | 四份 XLSX，共享公式和删行引用 | 准备记录与 `p14-current.json` 的执行记录分开读取 |
| `cases/p14-office.json` | 三份 DOCX：分栏、嵌套表、框架；两份 PPTX：文字自动适配 | 不能推导任意文档、演示稿的布局覆盖 |
| `cases/p14-pdf.json` | 三份 PDFium 原件；一份从 PDF.js 向量派生的 `smask-matte.pdf`；CMap/RGBA 向量 | 不是四份独立上游 PDF 原件，也没有覆盖广泛字体、色彩与图片编码 |
| `cases/p14-current.json` | A 构建 2749 项完整运行；B 优化后 132 项布局和 13 条 Chromium 定向结果 | 均为已记录结果。本次未重跑；本机未找到所指原始运行目录，不能称本轮复核通过 |
| `cases/c0-upstream-candidates.json` | 固定上游 revision、原件 hash、测试入口及候选范围 | 保留候选准备时的状态；后续执行另记 |
| `cases/c0-current.json` | 51 份固定候选；251 项登记核心与四格式 128 条浏览器流程 | `finalCompatibilityQualification` 记录当前构建及适用的共享 Renderer 复查。48 份正向通过、3 份控制按预期拒绝；C13 130 组、C17 28 组、C43 原始 30 组及重算后 32 组严格比较全部为 0/0。历史失败、参考身份与未支持边界分别保留 |

P14 的 13 份文件实际为 **12 份上游原件 + 1 份派生 PDF**。2749 项是多层测试执行数，既不等于 2749 份真实文件，也不覆盖下列所有组合。A/B 和原始记录边界详见[测试说明](testing.md#p14-素材环境与当前结果)。

## 按格式维护的能力矩阵

下表“有限实现”指代码与合同已有支持，不表示本轮用新语料验证过。证据列只列直接相关的已有范围；缺证据按未知处理，不臆测通过或失败。

| 格式 / 输入族 | 打开、显示与语义 | 编辑、保存与输出 | 证据及主要缺口 | 后续 |
| --- | --- | --- | --- | --- |
| 共同：Transitional OOXML / 合法 PDF | 有界解析、Worker、Canvas 已接通 | 原子事务、历史和源保留已实现 | 缺整份复杂文档的系统抽样；解析、字体和首屏失败未分层统计 | C0.1 |
| 共同：字体与脚本 | TrueType、显式回退、BiDi/塑形有限实现 | 输出受嵌入许可与子集能力约束 | CFF/TTC、完整字形回退、彩色 emoji 等不足；CJK/RTL 组合缺广泛原件证据 | C0.2 |
| DOCX：正文、样式、节、页眉页脚、字段 | P10 有限分页和语义 | 支持已列编辑及同布局 PDF | C0 裁剪/双栏原件通过；引用控件和校对标记已读取，字段原件 Canvas/PDF 及改后重开均通过；复杂节、字段和页眉页脚仍缺完整资格 | C0.4 |
| DOCX：浮动、嵌套表、文本框、绕排 | 已扩展部分锚点、框架、嵌套布局 | 按已识别结构编辑，未知源保留/保护 | `LinkedTextBoxes` 已通过核心及双框接续、正文输入、精确历史和保存重开；框保持只读，原件及改后整页 Canvas/PDF 均为 0/0；其他组合继续检查 | C0.4 |
| DOCX：图表、数学、审阅与嵌入对象 | 已列原生能力和受限预览 | 不是任意 OLE、公式对象或修订结构编辑 | 新建/小型用例不能证明外部文件的混合对象布局 | C0.4 |
| XLSX：数值、样式、公式、引用 | 常用函数、依赖和已列规则 | P11 编辑/计算；P14 共享公式、删行更新 | C41 上游八次赋值、二十个依赖值、默认输入、精确历史、源保留和新 Worker 重开通过。缓存自动行已按五份独立原生对照重测；原件与修改后全部六页 Canvas/PDF 均为 0/0，固定 Noto 替代、页序、源保存及新 Worker 重开通过。函数族、外部引用及其他格式组合继续补齐 | C0.4 |
| XLSX：图表、透视、规则、绘图与打印 | C43 十九张图表均已接通读取与缓存数据更新。显示沿选定 ONLYOFFICE 外观，复合饼图显示为普通饼图，保留拆分数据及属性。自动深度轴标题不可见，保留源文字、显式位置和布局留量。C44 原生条件格式与单元格度量已读取 | 跨表输入、精确历史、源保留与新 Worker 重开通过。已计算绑定数据可更新缓存；原生图表配置改写与未知扩展继续保护。C43 原件手工缓存、默认输入、显式重算及三轮缓存历史通过，104 个非随机结果匹配独立原生输出 | C43 按 100% 预览及导出 15 页。完整工作表 15 页 Canvas/PDF 均为 0/0，共 30/30，冻结参考保持。主折线、双轴折线、百分比及三维堆积面积、两张雷达、散点、圆形及普通饼图外观的复合饼图已有完整独立对照。三张曲面图与堆积条图的完整 Canvas/PDF 均为 0/0；透视柱图 Canvas/PDF 均为 0/0。气泡组件的完整工作区、原样重开及 62%/65% 整页打印对照通过。混合图修改控制、原生保存及独立重开通过，重算后全部可见页的 32 组完整 Canvas/PDF 均为 0/0。C44 原件/改后双表 PDF、四处 Canvas 单元格内部和独立重开共十组均为 0/0；整视口及其他文件未授予资格。[证据与边界](testing.md#当前兼容证据入口) | C0.4 |
| XLSX：原生大纲透视表 | C45 的报表和字段可读取，网格显示灰底、粗体和边线 | 单行字段和单值刷新保留紧凑行标题、样式和已识别的扩展 | 汇总值独立核对。工作簿 100% 比例下，原件和刷新版各三页，12 组整页为 0/0。转换器自动适页参考单列 | C0.4 |
| XLSX：重合绘图锚点 | C46 的五个对象已读取，重合锚点图片保持隐藏 | 单元格输入与首列前插列通过。打印区域和五个锚点同步移动，Mac 元数据、精确历史及新 Worker 重开通过 | 相同字体及源 80% 缩放下，原件、单元格改后和插列后各两页，12 组整页 Canvas/PDF 对照均为 0/0 | C0.4 |
| PPTX：母版、版式、主题、占位符 | 有限继承、图文布局；C12 显示版式共享文字和源页脚，隐藏母版占位提示 | C12 副标题输入、精确历史及 SDK、LibreOffice 重开通过 | C12 两页原件和改后 Canvas/PDF 共八组整页均为 0/0，覆盖继承样式和上标；多母版/多版式整稿仍缺证据 | C0.2 |
| PPTX：文字、RTL、自动适配 | P14 适配、行距、字偶距已记录。C08 支持符号字体与 RTL 悬挂列表的正文和标记对齐 | C08 原生输入、精确历史、保存及 SDK、LibreOffice 重开通过。C11 首屏副标题编辑、精确历史和源保留通过 | C08 原件和改后 Canvas/PDF 四组整页均为 0/0。C11 两页原件和改后 Canvas、PDF 和外部重开十组均为 0/0。主题字体、嵌入字体、竖排、混合脚本与长文本组合待测 | C0.2 / C0.3 |
| PPTX：组、裁剪、自定义几何、填充/效果 | 已列形状、变换、渐变及有限 WMF 多边形/双色实现 | 已识别对象可编辑、静态输出。C13 的矩形 WMF 裁剪保留媒体及双色效果，精确历史和重开通过 | 独立 WMF 裁剪控制的 Canvas/PDF 均为 0/0。长尾记录和原色边缘，以及复杂组、图片填充、EMF、阴影等需按原件对照 | C0.2 / C0.3 |
| PPTX：表格、图表、SmartArt、OLE | 有限原生表格/图表；原生 SmartArt 可读独立文字框的 DrawingML 缓存与默认只读层级布局，简化图示另用形状组 | 原生 diagram 不是完整可编辑对象；未知对象保护 | 两份表格文字编辑流程通过；SmartArt 缓存的原件及背景编辑结果、Canvas/PDF 和保存重开已匹配独立参考；空缓存组织图的默认两层结构及背景编辑已通过独立对照；C13 第 7–14 页的九个缓存图已恢复，`hierarchy4` 已接通同组字号重算；显示、PDF、背景编辑、历史和新 Worker 重开通过，获批参考下的整页视觉通过；原生编辑和其他布局仍有缺口 | C0.2 / C0.3 |
| PPTX：动画、媒体、放映 | 已列时间线/媒体和 Chromium 编码范围；C09 读取版式的空媒体槽 | C09 填充 VP8 WebM 并保留占位符和分组限制；精确历史、新 Worker 重开及播放通过 | C09 原件和 ONLYOFFICE 重开改后文件共四组 Canvas/PDF 整页为 0/0；LibreOffice 26.8.1.1 另存会丢失占位符身份。完整动画和其他编码组合待测 | C0.3 / C0.5 |
| PDF：结构与页面 | 未加密 1.0–1.7；xref/object stream、增量、页框与旋转。2.0 和已支持的密码加密可只读查看 | 未加密 1.0–1.7 有限页面操作和保留源对象保存。只读 PDF 可原样保存 | ONLYOFFICE 两页 PDF 2.0 及 C50 加密原件通过整页笔画对照与保存重开。损坏结构仍拒绝 | C0.1 / C0.5 |
| PDF：TrueType、编码、提取 | 有限嵌入 glyf、Identity-H、Identity-V、CMap/ActualText | 显示和 Unicode 完整性分开，竖排源正文改写和脱敏受保护 | PDF.js 竖排原件三页 Canvas 对 Poppler 均为 0/0。未知映射复制受保护 | C0.2 |
| PDF：Type3 字形程序 | 水平 FontMatrix 的 `d0/d1`，复用内容解释器 | 源重构、转换和脱敏仍保护 | 原件六个图形及旋转页视觉通过；缺可信 Unicode 仍标为不完整，图像遮罩等未支持 | C0.2 |
| PDF：Type1/CFF、竖排字体 | 无嵌入标准 Type1 可显式替代；二进制嵌入 Type1、CFF1 裸流/OpenType、SID 名称和 CID 字符集可读取 | CFF 源重构、原生转换和脱敏仍保护 | 两份 CFF 表单原件视觉通过；CID CFF 原件整页及旋转页已通过定向对照。Type1 的 14 页原件与旋转完成完整对照，正式 28/28 组通过；固定参考工具包含通用缓存范围守卫，旧 0/8 失败证据保留；十六进制 eexec、PFB、多主字体、CFF2、字体集合与竖排仍待补齐 | C0.2 |
| PDF：色彩、编码、图案与透明 | RGB/Gray/DeviceCMYK、有限 Flate/JPEG、1 位图像、CCITT Group 3/4、JBIG2 MMR/算术模板 0、有界 JPX/JPEG2000、SMask/Matte、已支持 RGB/Gray ICC 图像；Normal/Multiply/Difference、RGB/受支持 RGB ICC 页面及限定 Form 组、Alpha 软遮罩、指数/一维采样轴向渐变、默认可见图层及有界平铺填充 | 已有受支持对象可输出；新增解码不自动授予源对象重写 | CCITT 原件定向视觉通过；渐进式 CMYK、CMYK ICC、其他 ICC/目标空间、JPX 非默认 precinct/其他包顺序/调色板、JBIG2 字典/精化/其他算术模式、非隔离组的非 Normal 内部与复杂外层组合、挖空、Luminosity 遮罩、更多混合、径向/网格渐变、着色图案、图案描边/普通文字仍有明确缺口 | C0.2 |
| PDF：表单、批注与外观 | normal appearance、基础无外观 Line 和已列字段/批注；空白无样式只读文本框/组合框可无 AP | C33 支持改线宽、颜色和批注文字，保留端点、源对象及精确历史。C34 双页独立字段通过输入、历史、源保留及重开；补充原件 `issue14023.pdf` 通过三页共享文本、复选状态和单选状态检查 | C33 原件与旋转页通过既有 Poppler 对照，改后通过 qpdf 和新 Worker 重开。C34 原件/改后四组整页对照通过；补充原件验证跨页同步和保存结构；有值、列表内容、选择索引或样式的缺 AP 控件仍不完整；复杂外观、XFA/动作等保护 | C0.3 |
| PDF：源正文编辑、脱敏、转换 | 可识别/可隔离的文字与图片 | Tagged/未知关系/复杂 Form 等保护；脱敏为独立清理输出 | 阅读通过不授予编辑、脱敏或转换通过；扫描页阅读与 OCR 分开 | C0.3 |
| 扩展格式：`.doc/.xls/.ppt`、Strict、加密、宏 | Strict XLSX 基础工作表、指定 Standard/Agile 配置的加密 DOCX 和已支持的密码加密 PDF 可只读显示及原样保存 | 混合关系命名空间拒绝；签名按现有合同拒绝或只读 | C47、C49、C50 及 Word 2010、2013 Agile 原件可只读查看。旧版 PPT 和损坏 PDF 仍拒绝。换文件失败后保留原文档 | C0.5 |
| 大文档、密集图片、超长表格 | 有预算与有限缓存 | 失败需保留会话和可恢复操作 | Node 局部提速不能证明浏览器启动、滚动或内存可用 | 随阻塞修复 / C0.5 |

PDF 尾部的错误 `startxref` 偏移可用同一文件尾的完整经典交叉引用表恢复。C22 派生对照通过只读显示、原样保存与新 Worker 重开。C51 的文件头和 trailer 损坏，按预期拒绝。[测试说明](testing.md#当前兼容证据入口)

C43 圆环图的扇区路径、绘制顺序和标签顺序已与原生核对。独立同倍率工作区对照中，圆环图 93% 和 75%、普通饼图 93% 均为 0/0。圆环图的隔离 PDF 对正式参考为 0/0，普通饼图 PDF 对恢复原生底纹的候选为 0/0。获批独立工作区对照及原始工作表 30 组、重算后完整可见页 32 组均为 0/0。[测试说明](testing.md#当前兼容证据入口)

C43 的 LibreOffice 另存件可在首张工作表显示和打印条形复合饼图。第二张工作表可预览两张复合饼图、普通饼图、圆环图、两张雷达图、百分比面积图和两张气泡图，并报告其余 9 张图表的部件路径。源文件可原样保存。第二张工作表的绘图编辑与打印继续受保护。[测试说明](testing.md#当前兼容证据入口)

PDF V4/R4 的 AESV2 与 RC4 均可用密码只读打开。C50 原件及 AESV2 对照的整页笔画覆盖均为 0/0。原样保存、权限拒绝和新 Worker 重开通过。[测试说明](testing.md#当前兼容证据入口)

PPTX/PDF 的候选替换现区分容器、解析、字体和绘制失败。Chromium 用真实旧版 PPT 和损坏 PDF 核对容器和解析阶段，另模拟字体和画布失败。各次都清理候选并保留旧编辑器。[测试说明](testing.md#当前兼容证据入口)

C13 SmartArt 第 14 页的字号与空格混排行高已修正。整稿的 48 次导出及原样保存通过。获批完整独立参考下，原稿、改后及组件的 130 组严格比较均为 0/0；旧 78/96 与候选证据保留。[测试说明](testing.md#当前兼容证据入口)

## 上游矩阵与可用语料

准备阶段读取固定 Git 对象。以下是指定目录下的**文件路径数量**，没有按内容去重，不是上游或 SDK 测试结果。后续 SDK 扫描只覆盖候选原件，结果另记。完整 revision 和本地目录在私有候选清单中。仅有 `.git` 的副本通过 `git show <revision>:<path>` 读取，不要求重新下载或切换参考工作树。

| 项目及固定测试入口 | 目录与可用文件 | 应复用的检查方式 |
| --- | --- | --- |
| [ONLYOFFICE core x2tTester](https://github.com/ONLYOFFICE/core/blob/3250a848ee4ef20c2fb8c38dc86350ec579124b8/Test/Applications/x2tTester/README.md) | `Test/`、`OOXML/`、`PdfFile/`：DOCX 1、XLSX 34、XLS 1；本次范围无 PPTX/PDF 文件 | 格式转出矩阵、逐文件报告、固定字体和超时；转出成功后仍需内容检查 |
| [ONLYOFFICE sdkjs PDF demo](https://github.com/ONLYOFFICE/sdkjs/tree/72b0421c0bbf9d01eed9cf14834ae47eb2df1b50/pdf/test) | 该快照没有顶层 `tests/`、`test/` 语料；`pdf/test/` 为页面与脚本入口 | 仍是实现/交互参考；这些入口不足以证明存在可直接搬用的完整四格式矩阵 |
| [ONLYOFFICE-QA x2t-testing](https://github.com/ONLYOFFICE-QA/x2t-testing/blob/540e4308ce1fd4d7ea41220cc66b85fd03a74ae7/README.md) | 全树 DOCX 1、XLSX 2、PPTX 1，其中含错误扩展名输入；大语料走 S3 | 旧仓库已归档；后继 [wrapper](https://github.com/ONLYOFFICE-QA/x2ttester_wrapper/blob/master/readme.md)支持选择文件和格式，但字体库是私有的，不能宣称完整语料已可复现 |
| [LibreOffice Writer 测试说明](https://github.com/LibreOffice/core/blob/2821d29a87b28785d74fa64d975465e4c99d4416/sw/qa/extras/README) | `sw/qa`、`sd/qa`、`sc/qa`、`vcl/qa`、`filter/qa`：DOCX 2159、XLSX 396、PPTX 441、PDF 59；另 DOC 351、XLS 344、PPT 72 | 导入模型、布局 XML、导出 OOXML XPath、保存后重载；不能只搬文件、不搬对应断言 |
| [Apache POI slideshow 测试](https://github.com/apache/poi/tree/ae62bb5116b9aee19ebd5834e3a82066132c9f7f/poi-ooxml/src/test/java/org/apache/poi/xslf) | `test-data/`：DOCX 181、XLSX 371、PPTX 103、PDF 1；另 DOC 175、XLS 420、PPT 146 | 完整示例、文本/对象读取、关系和写回；结构断言不代替 Office 布局参考 |
| [PDFium pixel runner](https://github.com/chromium/pdfium/blob/a84323421e94f484faca52dd9d027934eba42ab8/testing/tools/run_pixel_tests.py) | `testing/resources/`：PDF 301、`.in` 模板 508 | embedder API、像素参考与资源限制；`.in` 用上游生成器，不能算现成 PDF；[DEPS](https://github.com/chromium/pdfium/blob/a84323421e94f484faca52dd9d027934eba42ab8/DEPS)还指向独立 `pdfium_tests` corpus，本轮未导入 |
| [PDF.js manifest](https://github.com/mozilla/pdf.js/blob/24de17e81b3357b30ffd710ec080be00d65ac98d/test/test_manifest.json) / [runner](https://github.com/mozilla/pdf.js/blob/24de17e81b3357b30ffd710ec080be00d65ac98d/test/test.mjs) | `test/pdfs/`：PDF 989、`.link` 460；manifest 1403 条：eq 1240、text 80、load 57、other 20、fbf 2、highlight 2、extract 2 | `eq` 比较参考图；`text` 检查文字层的栅格结果；`load` 不授予像素一致；同文件可多条，523 个 link 条目不等于 523 个已下载文件 |
| [Collabora Cypress](https://github.com/CollaboraOnline/online.mirror/blob/033854ea356ba65dae6618297257366cddb05bdf/cypress_test/README) | `cypress_test/`、`test/`：DOCX 8、XLSX 5、PPTX 2、PDF 4，另有旧格式与大量 ODF | 文件打开后的输入、选择、剪贴板、保存与浏览器状态；本项目只取 Chromium 桌面所需流程 |
| [GenOffice PPTX fixtures](https://github.com/genspark-ai/genoffice/blob/5eab98adc8d0ebf6ecea687e42400a791ef58d64/packages/pptx-engine/tests/fixtures/README.md) | 全树 DOCX 39、XLSX 1、PPTX 3、PDF 3；PPTX 包中的两个示例由 python-pptx 生成，PDF 文件集中于 shell 错误/密码场景 | 功能与交互参考；不能把生成的小例子、测试名称或计划中的 golden 当成成熟跨格式兼容矩阵 |
| `references/IronCalc`（MIT / Apache-2.0） | `xlsx/tests/calc_tests/`（8 大函数目录 + 综合表）与 `xlsx/tests/*.xlsx` 共 50+ 份；`base/src/test/` 156 份测试 | 表格公式求值、错误传播、动态数组、定义名称与条件格式；可直接提取 `<v>` 缓存作为公式黄金预期（[C1.2](../c1-corpus-and-producer-compatibility.md#c12-xlsx-公式数字格式与引用黄金集)） |
| `references/calamine`（MIT） | `tests/` 下 70+ 份真实 issue 样本（含 XLSX、XLSM、XLSB、XLS、ODS） | 怪异 OOXML 容器、内联字符串/CDATA、非标命名空间前缀、绝对路径关系、多轴共享公式与 OOM 边界（[C1.3](../c1-corpus-and-producer-compatibility.md#c13-ooxml-怪异容器与复杂特性集)） |
| `references/Open-XML-SDK`（MIT） | `test/DocumentFormat.OpenXml.Tests.Assets/assets/TestFiles/` 下 70+ 份官方测试资产 | Office 2010–2016 复杂特性、Markup Compatibility（`mcdoc`/`mcppt`）、缺失 `calcChain`、SVG 与 1.5 MB 性能基准（[C1.3](../c1-corpus-and-producer-compatibility.md#c13-ooxml-怪异容器与复杂特性集)） |
| `references/excelize`（BSD-3-Clause） | `numfmt_test.go`（443 KB）、`calc_test.go`（348 KB）、`adjust_test.go` 与 `test/*.xlsx` | 数字格式掩码表驱动向量、公式计算与行列增删引用平移断言（[C1.2](../c1-corpus-and-producer-compatibility.md#c12-xlsx-公式数字格式与引用黄金集)） |
| `references/office_oxide` & `references/anydoc`（MIT / Apache-2.0） | `office_oxide/tests/`（31 份集成/保真/预算测试）与 `anydoc/tests/` | 包完整性、分配预算拒绝、往返幂等性（Idempotence）与畸形输入恢复（[C1.3](../c1-corpus-and-producer-compatibility.md#c13-ooxml-怪异容器与复杂特性集)） |
| `references/apache-tika`（Apache-2.0） | 本地 `.git` 对象库中的 `test-documents` 多生产工具样本 | 按生产工具（WPS、Google、Apple、POI 等）抽样验证容器与结构兼容（[C1.5](../c1-corpus-and-producer-compatibility.md#c15-多生产工具与-cjk-真实排版集)） |

本地 Univer 的两个 XLSX 位于剪贴板测试资产目录，主要服务粘贴行为，不是 Office 解析/导出的完整文件语料。BetterOffice 的文档所列本地目录在本次环境中不存在，未将其记为已审计输入来源；现有语料已足够启动修复。

### 首批可直接复用的原件

私有 `cases/c0-upstream-candidates.json` 选定 **51 个候选**：16 PPTX、20 PDF、7 DOCX、7 XLSX、1 PPT。当前登记 47 个正向候选和四个旧格式、加密或损坏控制项。C47 的 Strict XLSX 原件已从拒绝控制转为正向用例。原件共 4,357,619 字节，现已从本地固定 Git 对象复制到私有 `fixtures/upstream/c0/`，核对 SHA-256 并保留来源声明。准备阶段曾补取浅克隆缺少的 blob；未改动参考工作树。文件名不自动证明特征或合法性；清单保留选取主题和源测试位置，当前扫描结果另记。

48 个候选已定位到上游测试代码或 manifest。`nonembedded_type1_tounicode.pdf`、`shading_extend.pdf`、`form_two_pages.pdf` 尚未定位到直接上游测试条目。前两份已用固定 Poppler 建立独立预期并通过定向视觉；`form_two_pages.pdf` 的独立预期仍待准备。已有条目也需审阅具体断言，不直接导入上游 PASS。

| 候选组 | 代表原件 | 要回答的问题 |
| --- | --- | --- |
| 整份演示稿/继承 | POI `SampleShow.pptx`、`WithMaster.pptx`；LO `master-and-eleven-layouts.pptx` | 多页、母版、版式和文本是否同时可见，是否漏页漏对象 |
| 演示对象 | LO `group-rot.pptx`、`crop-to-shape.pptx`、`smartart-background-drawingml-fallback.pptx`、`ole-emf_min.pptx`；POI `customGeo.pptx`、两份 table-with-* | 变换、裁剪、主题表格与 fallback 是否正确；未知原对象是否保留 |
| 完整 PDF 与字体 | PDF.js `tracemonkey.pdf`、`pdfkit_compressed.pdf`、`ArabicCIDTrueType.pdf`、`cid_cff.pdf`、`simpletype3font.pdf` | 文件是否能打开，首/中/末页是否完整，显示和文字提取分别缺什么 |
| PDF 图像/颜色/合成 | PDF.js `cmykjpeg.pdf`、`jpx_smaskindata.pdf`、`jbig2_file_header.pdf`、`ccitt_EndOfBlock_false.pdf`、`transparency_group.pdf`、`tiling_patterns_variations.pdf` | 缺图、错色、透明组与图案造成的空白来自哪里 |
| PDF 外观/关系 | PDF.js `annotation-text-widget.pdf`、`annotation-choice-widget.pdf`、`annotation-line-without-appearance.pdf`、`form_two_pages.pdf`、`issue14023.pdf` | 阅读外观与编辑权限分开；共享字段保存后是否一致 |
| 文档与工作簿 | LO `090716_Studentische_Arbeit_VWS.docx`、`LinkedTextBoxes.docx`、`EmbeddedExcelChart.docx`；ONLYOFFICE `Formula_complex_dependencies.xlsx`、`NumberFormat.xlsx`、`chart_7_full_1.xlsx`；LO 规则/透视/锚点文件 | 完整文档、嵌入对象、计算与缓存、打印和保存是否一致 |
| 控制项 | POI `SampleSS.strict.xlsx`、`SampleShow.ppt`；LO `Encrypted_LO_Standard_abc.docx`；GenOffice 密码/损坏 PDF | 区分格式缺口、密码需求与非法输入；拒绝不能冲掉原会话 |

断言必须对应输入。例如 LO `testCropToShape` 检查形状类型及位图填充，`testBackgroundDrawingmlFallback` 检查背景覆盖范围和颜色，`testGroupsRotatedPosition` 检查保存后的坐标。它们可以作为结构依据，但不是当前 SDK 的整页像素 golden。Office 像素参考仍优先由固定 ONLYOFFICE 生成，LibreOffice 补充；PDF 采用固定 PDFium/Poppler，并保留 PDF.js 已有断言与差异。

### 公开补充来源

本轮已检查以下公开入口；尚未下载或赋予 SDK 通过状态。先用本地原件，出现明确缺口再引入。

| 来源 | 可补范围 | 使用边界 |
| --- | --- | --- |
| [Open Preservation format-corpus](https://github.com/openpreserve/format-corpus) | `office`、`office-examples`、`fully-featured-pdf` 等，补生产工具与格式版本 | README 声明除另有说明外 CC0；逐文件查元数据和例外；不是像素参考库 |
| [PDF Association pdf-corpora](https://github.com/pdf-association/pdf-corpora) | 查找 PDFium、PDF.js、其他公开 PDF 集 | 这是索引；链接公开不等于允许再分发，也不等于本机已有文件 |
| [veraPDF corpus](https://github.com/veraPDF/veraPDF-corpus) | PDF/A、PDF/UA 与部分 ISO 32000 条款的原子 pass/fail 输入 | CC BY 4.0；用于声明对应标准范围时，不能替代视觉或编辑兼容检查 |

不批量抓取 `.link`、不先镜像海量 corpus，也不扩建多浏览器验收。完整文件与定向回归原件搭配，按下一批缺口增加。
