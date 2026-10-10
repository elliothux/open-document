# Foundation 依赖与本地缺口

生产依赖用 `moon.mod` 固定精确版本，不使用根 `references/` 研究副本构建。MoonBit 标准库随工具链固定；下表列直接依赖，传递依赖由 Moon 固定版本解析。

| 固定 module | 用到的能力 / 许可 | 必要本地工作 |
| --- | --- | --- |
| [moonbit-community/flate](https://github.com/moonbit-community/flate) 0.8.5 | limited raw DEFLATE、CRC32；Apache-2.0 | 现成 ZIP `read` 急切读取且不承担本项目 CRC/源记录/预算合同；archive 只补 checked ZIP32 索引、缓存与保真封装，不复制压缩器 |
| [Milky2018/xml](https://github.com/moonbit-community/xml-mbt) 0.5.0 | namespace-aware pull reader、source spans、escape；Apache-2.0 | xml 层拥有严格字节解码、禁 DTD、深度预算和文本源片段修改。该版将短 ASCII 的 UTF-16 声明按解码后字符串启发式拒绝；独立解析声明 pseudo-attributes，再以等长空白保留 offset，复用原 parser 验证正文。另补 NS1.0 的 PI target 冒号规则 |
| [moonbit-community/harfbuzz](https://github.com/moonbit-community/harfbuzz.mbt) 0.1.0 | OpenType shaping、glyf DrawFuncs；MoonBit 代码 Apache-2.0，上游附 Old MIT 等完整 notices | 该版 Face metrics getter 在目录准备后仍返回未加载值；直接复用 HeadTable::parse 取 upem。RTL buffer 输出逻辑顺序，核心按 BiDi run 输出视觉顺序。draw 不支持 CFF，入口明确拒绝而不回退成空白字形 |
| [moonbit-community/bidi](https://github.com/moonbit-community/tonyfettes-unicode) 0.5.2 | UAX #9，目标 Unicode 16.0.0；Apache-2.0 与 Unicode 数据许可 | 复用顺序/镜像 API；不重写 Unicode 表，不扩展到完整字素导航 |
| Milky2018/moon_cosmic 0.3.7 | 仅 unicode_linebreak；Apache-2.0 与 Unicode 数据许可 | 复用换行位置，不使用其 editor、排版或字体 owner；Unicode 15 向量按上游 tailoring 做回归，不声称完整符合性 |
| moonbitlang/x 0.5.5 | SHA-256；Apache-2.0 | 字体字节身份与构建补丁核验，不增加全局资源服务 |
| moonbitlang/pdflite 0.3.8 | PDF 对象、序列化、字体子集；Apache-2.0，Typst subsetter 0.2.6 为 MIT OR Apache-2.0 | 复用 writer 与 subsetter；本地仅将共同 PageFrame/GlyphRun 编码成 PDF，不创建第二套布局 |

公开 Wasm 包分发项目 Apache LICENSE、完整 HarfBuzz NOTICE 与 UNICODE-LICENSE。固定 Noto 字体、W3C XML 和 POI 测试材料仅保存在私有语料库，保留各自许可和来源；公开 SDK 不打包字体或 fixtures。

P1 使用 harfbuzz/bidi；P3 才因断行需要引入 moon_cosmic 的 unicode_linebreak。传递依赖为 moon_swash 0.1.13、moon_skrifa 0.1.11、moon_yazi 0.1.3、moon_zeno 0.1.4（Apache-2.0；swash Unicode 表为 13.0.0）、async 0.22.4，以及已固定的 harfbuzz/x/flate。解析到 module 不代表全部子包进入浏览器产物；最终 imports 由实际 Wasm 检查。

P1 的私有 pdflite content/path 探针继续保留；P3 产品 writer 复用同一固定版本，不依赖探针产物或私有 checkout。授权 notices 随公开 Wasm 包分发，字体和 DOCX/参考 PDF 留在私有库，不捆绑进 SDK。没有 PDF/A 或任意 PDF 编辑承诺。

## HarfBuzz GDEF 补丁

固定 0.1.0 的 `mark_glyph_set_contains` 把 MarkGlyphSets.coverageOffsets 按 16 位读取，合法组合附加符号输入因而报 `Layout(InvalidFormat)`。[OpenType GDEF](https://learn.microsoft.com/en-us/typography/opentype/spec/gdef#mark-glyph-sets-table) 要求 Offset32。公开 `tools/prepare-dependencies.mbtx` 只改数组边界/步长和读取函数两条语句，保留原版权头及 Apache 许可；不修改字体、不关闭 mark 特性、不复制整套引擎。

原文件 SHA-256 为 `ff75d107183fac2fe5498f4f0cdf6237d821f7e1b1d83477856aed4ffa13ec3d`；补丁后为 `2c48f426f0a8f5baf767c1b09746f4b1c1ea9ea1cf9a4725ff29658c575fbfbb`。未知源文件拒绝构建。私有回归覆盖大于 65535 的 coverage offset、截断数组，以及固定 Noto 字体的实际 WasmGC 塑形/PDF 提取。上游固定版本修复此规则后，删除构建补丁，保留回归测试；不保留双路径。
