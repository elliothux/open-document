import { Command, Group } from "@open-document/ui/controls";
import { messages } from "@open-document/ui/messages";
import type { PanelProps } from "./context.js";
import { AnnotationCommands } from "./annotation-commands.js";
import { ConversionCommands } from "./conversion.js";

export function ReadingTools(props: PanelProps) {
  const { controller, state, file, disabled } = props;
  const t = messages(state.locale);
  const editor = file.editor;
  const data = editor.getSnapshot().data;
  return (
    <>
      <Group label={t.pdfReadingTools} icon="book">
        <p role="note">
          {state.locale === "zh-CN"
            ? "导出可识别的段落、列表、表格、图片和链接；逐页损失说明显示在文档诊断中。"
            : "Exports recognized paragraphs, lists, tables, images and links; per-page losses appear in document diagnostics."}
        </p>
        {(["html", "markdown"] as const).map((format) => (
          <Command
            key={format}
            label={`${state.locale === "zh-CN" ? "结构化" : "Structured"} ${format === "html" ? "HTML" : "Markdown"}`}
            icon="download"
            disabled={disabled || !!state.document?.draft}
            action={() => controller.run(() => controller.exportMarkup(format))}
          />
        ))}
        {(["single", "continuous", "double"] as const).map((mode, index) => (
          <button
            type="button"
            key={mode}
            disabled={disabled || !!state.document?.draft}
            aria-pressed={data.readingMode === mode}
            onClick={() => controller.run(() => editor.setReadingMode(mode))}
          >
            {
              (state.locale === "zh-CN"
                ? ["单页", "连续", "双页"]
                : ["Single page", "Continuous", "Two pages"])[index]
            }
          </button>
        ))}
      </Group>
      <ConversionCommands {...props} />
    </>
  );
}
export function AnnotationActions(props: PanelProps) {
  const { controller, state, file, disabled } = props;
  const t = messages(state.locale);
  const editor = file.editor;
  return (
    <>
      <Group label={t.annotations} icon="comment-count">
        <Command
          label={t.note}
          icon="note"
          disabled={disabled || !!state.document?.draft}
          action={() => controller.run(() => editor.beginNote())}
        />
        <Command
          label={t.highlight}
          icon="highlighter"
          disabled={
            disabled || !state.document?.selection || state.document.draft
          }
          action={() => controller.run(() => editor.operations.highlight())}
        />
        {(["Underline", "StrikeOut"] as const).map((kind, index) => (
          <Command
            key={kind}
            label={
              (state.locale === "zh-CN"
                ? ["下划线", "删除线"]
                : ["Underline", "Strike out"])[index]!
            }
            icon={kind === "Underline" ? "underline" : "strikethrough"}
            disabled={
              disabled || !state.document?.selection || state.document.draft
            }
            action={() =>
              controller.run(() => editor.operations.highlight(kind))
            }
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
            icon={
              kind === "Square"
                ? "square"
                : kind === "Circle"
                  ? "circle"
                  : "minus"
            }
            disabled={disabled || !!state.document?.draft}
            action={() => controller.run(() => editor.beginDrawing(kind))}
          />
        ))}
        <Command
          label={state.locale === "zh-CN" ? "箭头" : "Arrow"}
          icon="arrow-right"
          disabled={disabled || !!state.document?.draft}
          action={() => controller.run(() => editor.beginDrawing("Line", true))}
        />
      </Group>
      <AnnotationCommands {...props} />
    </>
  );
}
export function FormActions({ controller, state, file, disabled }: PanelProps) {
  const t = messages(state.locale);
  const editor = file.editor;
  return (
    <Group label={t.pdfForms} icon="text-input">
      {(["text", "checkbox", "radio", "choice", "list"] as const).map(
        (kind, index) => (
          <Command
            key={kind}
            label={
              (state.locale === "zh-CN"
                ? ["文本字段", "复选字段", "单选组", "下拉字段", "列表字段"]
                : [
                    "Text field",
                    "Checkbox field",
                    "Radio group",
                    "Dropdown field",
                    "List field",
                  ])[index]!
            }
            icon={
              kind === "text"
                ? "text-input"
                : kind === "checkbox"
                  ? "checkbox"
                  : kind === "radio"
                    ? "circle"
                    : "list-checks"
            }
            disabled={disabled || !!state.document?.draft}
            action={() => controller.run(() => editor.beginField(kind))}
          />
        ),
      )}
    </Group>
  );
}
