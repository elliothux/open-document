export type { PanelProps } from "./context.js";
import type { PanelProps } from "./context.js";
import { Command, Group, NativeSlot } from "@open-document/ui/controls";
import { messages } from "@open-document/ui/messages";
import { useLayoutEffect, useState } from "react";
import { downloadBytes } from "@open-document/web-core/download";
import type { PdfNavigation, PdfDestination } from "../core/pdf.js";
import { Thumbnail } from "./thumbnail.js";
import { ObjectCommands, ImageInput, usePdfObjects } from "./objects.js";
import { PageArrangeControls } from "./page-arrange.js";
import { ConversionCommands } from "./conversion.js";
import { RedactionPanel } from "./redaction.js";
import { AnnotationCommands } from "./annotation-commands.js";
export function FormatCommands(props: PanelProps & { tab: string }) {
  const { controller, state, file, disabled, tab } = props;
  const t = messages(state.locale);
  if (file.format === "pdf") {
    const editor = file.editor;
    const data = editor.getSnapshot().data;
    if (tab === "edit") return <ObjectCommands {...props} />;
    if (tab === "view")
      return (
        <>
          <Group label={t.pages}>
            <p role="note">
              {state.locale === "zh-CN"
                ? "导出可识别的段落、列表、表格、图片和链接；逐页损失说明显示在文档诊断中。"
                : "Exports recognized paragraphs, lists, tables, images and links; per-page losses appear in document diagnostics."}
            </p>
            {(["html", "markdown"] as const).map((format) => (
              <Command
                key={format}
                label={`${state.locale === "zh-CN" ? "结构化" : "Structured"} ${format === "html" ? "HTML" : "Markdown"}`}
                disabled={disabled || !!state.document?.draft}
                action={() =>
                  controller.run(() => controller.exportMarkup(format))
                }
              />
            ))}
            {(["single", "continuous", "double"] as const).map(
              (mode, index) => (
                <button
                  type="button"
                  key={mode}
                  disabled={disabled || !!state.document?.draft}
                  aria-pressed={data.readingMode === mode}
                  onClick={() =>
                    controller.run(() => editor.setReadingMode(mode))
                  }
                >
                  {
                    (state.locale === "zh-CN"
                      ? ["单页", "连续", "双页"]
                      : ["Single page", "Continuous", "Two pages"])[index]
                  }
                </button>
              ),
            )}
          </Group>
          <ConversionCommands {...props} />
        </>
      );
    if (tab === "pages")
      return (
        <>
          <Group label={t.pages}>
            <Command
              label={
                state.locale === "zh-CN" ? "插入空白页" : "Insert blank page"
              }
              disabled={disabled || !!data.query.pageOrderReason}
              action={() => controller.run(() => editor.insertBlankPage())}
            />
            {[false, true].map((replace) => (
              <label key={String(replace)} className="od-command">
                {state.locale === "zh-CN"
                  ? replace
                    ? "替换当前页"
                    : "插入 PDF"
                  : replace
                    ? "Replace current page"
                    : "Insert PDF"}
                <input
                  type="file"
                  accept=".pdf"
                  disabled={disabled || !!data.query.pageOrderReason}
                  onChange={(event) => {
                    const input = event.currentTarget;
                    const source = input.files?.[0];
                    input.value = "";
                    if (source)
                      controller.run(async () => {
                        if (source.size > 67108864)
                          throw new Error("PDF import exceeds budget");
                        const bytes = new Uint8Array(
                          await source.arrayBuffer(),
                        );
                        if (replace) await editor.replacePage(bytes);
                        else await editor.insertPages(bytes);
                      });
                  }}
                />
              </label>
            ))}
            <Command
              label={
                state.locale === "zh-CN" ? "提取当前页" : "Extract current page"
              }
              disabled={disabled}
              action={() =>
                controller.run(async () => {
                  const output = await editor.extractPages();
                  downloadBytes(output.bytes, "application/pdf", "page.pdf");
                })
              }
            />
            <Command
              label={
                state.locale === "zh-CN"
                  ? "逐页拆分文件"
                  : "Split into page files"
              }
              disabled={disabled || !!state.document?.draft}
              action={() =>
                controller.run(async () => {
                  const files = await editor.splitFiles();
                  for (const file of files) {
                    downloadBytes(
                      file.output.bytes,
                      "application/pdf",
                      file.name,
                    );
                    editor.markDownloaded(file.output);
                  }
                })
              }
            />
            <Command
              label={t.earlier}
              disabled={
                disabled ||
                state.document?.page === 0 ||
                !!data.query.pageOrderReason
              }
              action={() => controller.run(() => editor.movePage(-1))}
            />
            {(["crop", "resize", "scale"] as const).map((action, index) => (
              <Command
                key={action}
                label={
                  (state.locale === "zh-CN"
                    ? ["裁剪页面", "调整纸张尺寸", "缩放页面内容"]
                    : ["Crop page", "Resize paper", "Scale page content"])[
                    index
                  ]!
                }
                disabled={disabled || !!state.document?.draft}
                action={() =>
                  controller.run(() => editor.beginPageGeometry(action))
                }
              />
            ))}
            <Command
              label={t.later}
              disabled={
                disabled ||
                state.document!.page + 1 >= state.document!.pageCount ||
                !!data.query.pageOrderReason
              }
              action={() => controller.run(() => editor.movePage(1))}
            />
            <Command
              label={t.rotate}
              disabled={disabled}
              action={() => controller.run(() => editor.rotate(90))}
            />
            <button
              type="button"
              className="od-command"
              title={t.deleteHint}
              disabled={
                disabled ||
                data.query.pages.length <= 1 ||
                !!data.query.pageOrderReason
              }
              onClick={() => controller.run(() => editor.deletePage())}
            >
              {t.deletePage}
            </button>
          </Group>
          <PageArrangeControls {...props} />
        </>
      );
    if (tab === "annotations")
      return (
        <>
          <Group label={t.annotations}>
            <Command
              label={t.note}
              disabled={disabled}
              action={() => controller.run(() => editor.beginNote())}
            />
            <Command
              label={t.highlight}
              disabled={
                disabled || !state.document?.selection || state.document.draft
              }
              action={() => controller.run(() => editor.highlight())}
            />
            {(["Underline", "StrikeOut"] as const).map((kind, index) => (
              <Command
                key={kind}
                label={
                  (state.locale === "zh-CN"
                    ? ["下划线", "删除线"]
                    : ["Underline", "Strike out"])[index]!
                }
                disabled={
                  disabled || !state.document?.selection || state.document.draft
                }
                action={() => controller.run(() => editor.highlight(kind))}
              />
            ))}
            {(["Square", "Circle", "Line"] as const).map((kind, index) => (
              <Command
                key={kind}
                label={
                  (state.locale === "zh-CN"
                    ? ["矩形", "椭圆", "线条", "墨迹"]
                    : ["Rectangle", "Ellipse", "Line", "Ink"])[index]!
                }
                disabled={disabled || !!state.document?.draft}
                action={() => controller.run(() => editor.beginDrawing(kind))}
              />
            ))}
            <Command
              label={state.locale === "zh-CN" ? "箭头" : "Arrow"}
              disabled={disabled || !!state.document?.draft}
              action={() =>
                controller.run(() => editor.beginDrawing("Line", true))
              }
            />
            {(["text", "checkbox", "radio", "choice", "list"] as const).map(
              (kind, index) => (
                <Command
                  key={kind}
                  label={
                    (state.locale === "zh-CN"
                      ? [
                          "文本字段",
                          "复选字段",
                          "单选组",
                          "下拉字段",
                          "列表字段",
                        ]
                      : [
                          "Text field",
                          "Checkbox field",
                          "Radio group",
                          "Dropdown field",
                          "List field",
                        ])[index]!
                  }
                  disabled={disabled || !!state.document?.draft}
                  action={() => controller.run(() => editor.beginField(kind))}
                />
              ),
            )}
          </Group>
          <AnnotationCommands {...props} />
          <RedactionPanel {...props} />
        </>
      );
  }
  return null;
}
export function Properties({ controller, state, file, disabled }: PanelProps) {
  const [search, setSearch] = useState("");
  const objectState = usePdfObjects(
    file.editor,
    state.document?.revision ?? 0,
    file.editor.snapshot.page,
  );
  useLayoutEffect(() => {
    if (file.format !== "pdf") return;
    const t = messages(state.locale);
    file.editor.setPropertyLocale(state.locale);
    for (const [key, text] of [
      ["text", t.propertyText],
      ["checked", t.checked],
      [
        "ink-strokes",
        state.locale === "zh-CN"
          ? "墨迹笔画（每行一条 x,y 坐标路径）"
          : "Ink strokes: one x,y path per line",
      ],
      [
        "ink-signature",
        state.locale === "zh-CN" ? "签名外观" : "Visual signature appearance",
      ],
      [
        "ink-pad",
        state.locale === "zh-CN"
          ? "墨迹和签名画板（可用笔画文本作为键盘替代）"
          : "Ink and signature pad (stroke text provides a keyboard alternative)",
      ],
      ["choice", state.locale === "zh-CN" ? "PDF 选项值" : "PDF choice value"],
      [
        "x",
        file.editor.getSnapshot().data.property.startsWith("fieldCopy:")
          ? state.locale === "zh-CN"
            ? "字段横向偏移"
            : "Field horizontal offset"
          : t.noteX,
      ],
      [
        "y",
        file.editor.getSnapshot().data.property.startsWith("fieldCopy:")
          ? state.locale === "zh-CN"
            ? "字段纵向偏移"
            : "Field vertical offset"
          : t.noteY,
      ],
      ...Object.entries(
        state.locale === "zh-CN"
          ? {
              "object-x": "对象横向位置",
              "object-y": "对象纵向位置",
              "object-width": "对象宽度",
              "object-height": "对象高度",
              "object-rotation": "旋转角度",
              "object-font": "字体",
              "object-size": "字号",
              "object-color": "文字颜色",
              "object-foreground": "置于页面内容前方",
              "object-opacity": "批注透明度",
              "object-border": "批注边框宽度",
              "object-author": "批注作者",
              "object-points": "笔迹坐标（x,y 成对）",
              "field-name": "字段名称",
              "field-tooltip": "字段提示",
              "field-options": "选项（每行一个，导出值与显示名用制表符分隔）",
              "field-defaultText": "默认值（列表每行一个）",
              "field-defaultChecked": "默认选中",
              "field-readOnly": "只读字段",
              "field-required": "必填字段",
              "field-multiline": "多行字段",
              "field-multiSelect": "允许多选",
              "field-maxLength": "最大文字长度",
              "field-border": "字段边框宽度",
              "field-background": "字段背景色",
            }
          : {
              "object-x": "Object horizontal position",
              "object-y": "Object vertical position",
              "object-width": "Object width",
              "object-height": "Object height",
              "object-rotation": "Object rotation",
              "object-font": "Font",
              "object-size": "Font size",
              "object-color": "Text color",
              "object-foreground": "In front of page content",
              "object-opacity": "Annotation opacity",
              "object-border": "Annotation border width",
              "object-author": "Annotation author",
              "object-points": "Stroke points (x,y pairs)",
              "field-name": "Field name",
              "field-tooltip": "Field tooltip",
              "field-options":
                "Options: export value and label separated by a tab, one per line",
              "field-defaultText":
                "Default value; list values use separate lines",
              "field-defaultChecked": "Default checked",
              "field-readOnly": "Read-only field",
              "field-required": "Required field",
              "field-multiline": "Multiline field",
              "field-multiSelect": "Multiple selection",
              "field-maxLength": "Maximum text length",
              "field-border": "Field border width",
              "field-background": "Field background",
            },
      ),
    ]) {
      const label = file.editor.propertyInput.querySelector(
        `[data-pdf-control="${key}"]`,
      );
      const caption = label?.querySelector("span"),
        input = label?.querySelector("input,textarea,select,canvas");
      if (caption && text) caption.textContent = text;
      if (input && text) input.setAttribute("aria-label", text);
    }
  }, [file, state.locale, file.editor.getSnapshot().data.property]);
  if (file.format !== "pdf") return null;
  const editor = file.editor,
    data = editor.getSnapshot().data,
    t = messages(state.locale);
  return (
    <aside className="od-properties" aria-label={`${t.find} / ${t.property}`}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() => editor.search(search));
        }}
      >
        <label>
          {t.search}
          <input
            type="search"
            value={search}
            onChange={(event) => setSearch(event.currentTarget.value)}
            disabled={disabled}
          />
        </label>
        <button type="submit" disabled={disabled || !search}>
          {t.find}
        </button>
        {data.searching && (
          <button type="button" onClick={() => editor.cancelSearch()}>
            {t.cancelSearch}
          </button>
        )}
        <div role="status">
          {t.matches}: {data.matches.length}
          {data.searching ? ` (${data.searchPage})` : ""}
        </div>
        <button
          type="button"
          disabled={disabled || !data.matches.length}
          onClick={() => controller.run(() => editor.nextMatch(-1))}
        >
          {t.previousMatch}
        </button>
        <button
          type="button"
          disabled={disabled || !data.matches.length}
          onClick={() => controller.run(() => editor.nextMatch())}
        >
          {t.nextMatch}
        </button>
      </form>
      <label>
        {t.property}
        <select
          aria-label={t.property}
          value={data.property === "note" ? "" : data.property}
          disabled={disabled || state.document?.draft}
          onChange={(event) =>
            controller.run(() =>
              editor.chooseProperty(event.currentTarget.value),
            )
          }
        >
          <option value="">{t.choose}</option>
          {objectState.objects.map((object, index) => (
            <option key={object.id} value={`object:${object.id}`}>
              {object.kind === "text"
                ? object.text.slice(0, 32)
                : `${state.locale === "zh-CN" ? "图片" : "Image"} ${index + 1}`}
            </option>
          ))}
          {Object.entries(
            state.locale === "zh-CN"
              ? {
                  Title: "标题",
                  Author: "作者",
                  Subject: "主题",
                  Keywords: "关键词",
                }
              : {
                  Title: "Title",
                  Author: "Author",
                  Subject: "Subject",
                  Keywords: "Keywords",
                },
          ).map(([key, label]) => (
            <option key={key} value={`metadata:${key}`}>
              {label}
            </option>
          ))}
          {data.query.fields.map((field) => (
            <option key={field.id} value={`field:${field.id}`}>
              {field.name || field.id}
            </option>
          ))}
          {data.query.annotations.map((annotation) => (
            <option key={annotation.id} value={`annotation:${annotation.id}`}>
              {annotation.kind}: {annotation.text || annotation.id}
            </option>
          ))}
        </select>
      </label>
      <NativeSlot node={editor.propertyInput} />
      {objectState.error && <p role="status">{objectState.error}</p>}
      <p>{data.propertyReason}</p>
      <div className="flex gap-1">
        <button
          type="button"
          disabled={
            disabled ||
            !data.property ||
            !!data.propertyReason ||
            data.applying ||
            state.document?.composition
          }
          onClick={() => controller.run(() => editor.applyDraft())}
        >
          {t.applyProperty}
        </button>
        <button
          type="button"
          disabled={
            disabled ||
            !data.property ||
            data.applying ||
            state.document?.composition
          }
          onClick={() => controller.run(() => editor.cancelDraft())}
        >
          {t.cancelProperty}
        </button>
      </div>
      {data.property.startsWith("field:") && (
        <div className="flex gap-1">
          <Command
            label={
              state.locale === "zh-CN"
                ? "字段位置与设计"
                : "Field position and design"
            }
            disabled={disabled || !!state.document?.draft}
            action={() => controller.run(() => editor.beginFieldDesign())}
          />
          <Command
            label={state.locale === "zh-CN" ? "复制字段" : "Copy field"}
            disabled={
              disabled ||
              !!state.document?.draft ||
              (!!data.propertyReason &&
                data.propertyReason !== "Read-only PDF field")
            }
            action={() => controller.run(() => editor.beginFieldCopy())}
          />
          <Command
            label={state.locale === "zh-CN" ? "重命名字段" : "Rename field"}
            disabled={
              disabled ||
              !!state.document?.draft ||
              (!!data.propertyReason &&
                data.propertyReason !== "Read-only PDF field")
            }
            action={() => controller.run(() => editor.beginFieldRename())}
          />
          <Command
            label={state.locale === "zh-CN" ? "删除字段" : "Delete field"}
            disabled={
              disabled ||
              !!state.document?.draft ||
              (!!data.propertyReason &&
                data.propertyReason !== "Read-only PDF field")
            }
            action={() => controller.run(() => editor.deleteField())}
          />
        </div>
      )}
      {data.property.startsWith("annotation:") && (
        <button
          type="button"
          disabled={disabled || state.document?.draft || !!data.propertyReason}
          onClick={() => controller.run(() => editor.deleteAnnotation())}
        >
          {t.deleteAnnotation}
        </button>
      )}
      {data.property.startsWith("object:") && (
        <>
          <button
            type="button"
            disabled={
              disabled || !!state.document?.draft || !!data.propertyReason
            }
            onClick={() => controller.run(() => editor.deleteObject())}
          >
            {state.locale === "zh-CN" ? "删除对象" : "Delete object"}
          </button>
          {objectState.objects.find(
            (object) => `object:${object.id}` === data.property,
          )?.kind === "image" && (
            <>
              <Command
                label={
                  state.locale === "zh-CN"
                    ? "裁剪图片外观"
                    : "Crop image appearance"
                }
                disabled={
                  disabled || !!state.document?.draft || !!data.propertyReason
                }
                action={() => controller.run(() => editor.beginImageCrop())}
              />
              <ImageInput
                controller={controller}
                state={state}
                file={file}
                disabled={
                  disabled || !!state.document?.draft || !!data.propertyReason
                }
                replace
              />
            </>
          )}
        </>
      )}
    </aside>
  );
}

export function PageList({ controller, state, file, disabled }: PanelProps) {
  const t = messages(state.locale);
  const [navigation, setNavigation] = useState<PdfNavigation>();
  const [navigationError, setNavigationError] = useState("");
  useLayoutEffect(() => {
    if (file.format !== "pdf") return;
    let active = true;
    void file.editor.navigation().then(
      (result) => {
        if (active) {
          setNavigation(result);
          setNavigationError("");
        }
      },
      (error: unknown) => {
        if (active) {
          setNavigation(undefined);
          setNavigationError(
            error instanceof Error
              ? error.message
              : "PDF navigation is unavailable",
          );
        }
      },
    );
    return () => {
      active = false;
    };
  }, [file, state.document?.revision]);
  if (file.format !== "pdf") return null;
  const pages = file.editor.snapshot.pages.map((page, index) => ({
    id: page.id,
    title: `${t.pages} ${index + 1}`,
  }));
  return (
    <nav className="od-sidebar" aria-label={t.pages}>
      {navigationError && <p role="status">{navigationError}</p>}
      {navigation?.outlines.map((outline) => (
        <div
          key={outline.id}
          style={{ marginInlineStart: `${outline.level * 12}px` }}
        >
          <Destination
            target={outline.target}
            label={outline.title}
            disabled={disabled}
            navigate={(page) =>
              controller.run(() => file.editor.goToPage(page))
            }
          />
        </div>
      ))}
      {pages.map((page, index) => (
        <button
          type="button"
          key={page.id}
          disabled={disabled}
          aria-current={state.document?.page === index ? "page" : undefined}
          onClick={() => controller.run(() => file.editor.goToPage(page.id))}
        >
          {page.title}
          {Math.abs(index - (state.document?.page ?? 0)) <= 2 && (
            <Thumbnail
              editor={file.editor}
              page={page.id}
              revision={state.document?.revision ?? 0}
            />
          )}
        </button>
      ))}
      {navigation?.links
        .filter((link) => link.page === file.editor.snapshot.page)
        .map((link) => (
          <Destination
            key={link.id}
            target={link.target}
            label={
              link.target.uri ||
              (state.locale === "zh-CN" ? "页面链接" : "Page link")
            }
            disabled={disabled}
            navigate={(page) =>
              controller.run(() => file.editor.goToPage(page))
            }
          />
        ))}
    </nav>
  );
}

function Destination({
  target,
  label,
  disabled,
  navigate,
}: {
  target: PdfDestination;
  label: string;
  disabled: boolean;
  navigate(page: string): unknown;
}) {
  if (target.kind === "uri" && !disabled)
    return (
      <a href={target.uri} target="_blank" rel="noopener noreferrer">
        {label}
      </a>
    );
  return (
    <button
      type="button"
      disabled={disabled || target.kind === "blocked"}
      title={target.reason}
      onClick={() => navigate(target.page)}
    >
      {label}
    </button>
  );
}
