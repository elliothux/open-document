import { useLayoutEffect } from "react";
import { Command, NativeSlot } from "@open-document/ui/controls";
import { messages } from "@open-document/ui/messages";
import type { PanelProps } from "./context.js";
import { ImageInput, usePdfObjects } from "./objects.js";
import { Icon } from "@open-document/ui/icons";

export type PdfPropertyTask =
  "content" | "annotations" | "forms" | "metadata" | "pages";

export function PdfProperties({
  controller,
  state,
  file,
  disabled,
  task,
}: PanelProps & { task: PdfPropertyTask }) {
  const objectState = usePdfObjects(
    file.editor,
    state.document?.revision ?? 0,
    file.editor.snapshot.page,
    task === "content",
  );
  useLayoutEffect(() => {
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
  const editor = file.editor,
    data = editor.getSnapshot().data,
    t = messages(state.locale);
  const label = {
    content: t.pdfPageObject,
    annotations: t.pdfAnnotation,
    forms: t.pdfFormField,
    metadata: t.pdfMetadataField,
  };
  return (
    <>
      {task !== "pages" && (
        <label>
          {label[task]}
          <select
            aria-label={label[task]}
            value={data.property}
            disabled={disabled || state.document?.draft}
            onChange={(event) =>
              controller.run(() =>
                editor.chooseProperty(event.currentTarget.value),
              )
            }
          >
            <option value="">{t.choose}</option>
            {task === "content" &&
              objectState.objects.map((object, index) => (
                <option key={object.id} value={`object:${object.id}`}>
                  {object.kind === "text"
                    ? object.text.slice(0, 32)
                    : `${state.locale === "zh-CN" ? "图片" : "Image"} ${index + 1}`}
                </option>
              ))}
            {task === "metadata" &&
              Object.entries(
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
            {task === "forms" &&
              data.query.fields.map((field) => (
                <option key={field.id} value={`field:${field.id}`}>
                  {field.name || field.id}
                </option>
              ))}
            {task === "annotations" &&
              data.query.annotations.map((annotation) => (
                <option
                  key={annotation.id}
                  value={`annotation:${annotation.id}`}
                >
                  {annotation.kind}: {annotation.text || annotation.id}
                </option>
              ))}
          </select>
        </label>
      )}
      <NativeSlot node={editor.propertyInput} />
      {objectState.error && <p role="status">{objectState.error}</p>}
      {data.propertyReason && <p role="status">{data.propertyReason}</p>}
      {data.property && (
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
            <Icon name="check" />
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
            <Icon name="close" />
            {t.cancelProperty}
          </button>
        </div>
      )}
      {task === "forms" && data.property.startsWith("field:") && (
        <div className="flex gap-1">
          <Command
            label={
              state.locale === "zh-CN"
                ? "字段位置与设计"
                : "Field position and design"
            }
            icon="adjust"
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
            icon="trash"
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
      {task === "annotations" && data.property.startsWith("annotation:") && (
        <button
          type="button"
          disabled={disabled || state.document?.draft || !!data.propertyReason}
          onClick={() => controller.run(() => editor.deleteAnnotation())}
        >
          <Icon name="trash" />
          {t.deleteAnnotation}
        </button>
      )}
      {task === "content" && data.property.startsWith("object:") && (
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
                icon="crop"
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
    </>
  );
}
