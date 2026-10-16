import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type {
  PptxTextFormat,
  PptxTextSpacing,
  PptxParagraphFormat,
} from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

function TextField({
  property,
  label,
  value,
  mixed,
  apply,
  disabled,
  onApply,
}: {
  property: "font" | "size" | "color" | "highlight";
  label: string;
  value: string | number | null;
  mixed: string;
  apply: string;
  disabled: boolean;
  onApply: (format: PptxTextFormat) => void;
}) {
  const [draft, setDraft] = useState(value === null ? "" : String(value));
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        onApply(
          property === "size" ? { size: Number(draft) } : { [property]: draft },
        );
      }}
    >
      <label>
        {label}
        <input
          aria-label={label}
          required
          value={draft}
          type={property === "size" ? "number" : "text"}
          min={property === "size" ? 1 : undefined}
          max={property === "size" ? 1024 : undefined}
          step={property === "size" ? "0.01" : undefined}
          maxLength={
            property === "font"
              ? 200
              : property === "color" || property === "highlight"
                ? 6
                : undefined
          }
          pattern={
            property === "color" || property === "highlight"
              ? "[0-9a-fA-F]{6}"
              : undefined
          }
          placeholder={value === null ? mixed : ""}
          onChange={(event) => setDraft(event.currentTarget.value)}
        />
      </label>
      <button type="submit" disabled={disabled || !draft}>
        {apply} {label}
      </button>
    </form>
  );
}

function ParagraphField({
  property,
  label,
  value,
  state,
  disabled,
  onApply,
}: {
  property: keyof PptxParagraphFormat;
  label: string;
  value: number | PptxTextSpacing | null;
  state: UiSnapshot;
  disabled: boolean;
  onApply: (format: PptxParagraphFormat) => void;
}) {
  const t = messages(state.locale),
    spacing =
      property === "before" || property === "after" || property === "line";
  const [draft, setDraft] = useState(
    value === null
      ? ""
      : String(typeof value === "number" ? value : value.value),
  );
  const [unit, setUnit] = useState<PptxTextSpacing["unit"]>(
    value !== null && typeof value !== "number"
      ? value.unit
      : property === "line"
        ? "percent"
        : "point",
  );
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        onApply(
          spacing
            ? { [property]: { unit, value: Number(draft) } }
            : { [property]: Number(draft) },
        );
      }}
    >
      <label>
        {label}
        <input
          aria-label={label}
          type="number"
          required
          value={draft}
          placeholder={value === null ? t.mixed : ""}
          min={
            property === "first"
              ? -4032
              : property === "line"
                ? unit === "point"
                  ? 0.01
                  : 0.001
                : 0
          }
          max={spacing ? (unit === "point" ? 1584 : 1000) : 4032}
          step={spacing ? (unit === "point" ? 0.01 : 0.001) : "any"}
          onChange={(event) => setDraft(event.currentTarget.value)}
        />
      </label>
      {spacing && (
        <label>
          {t.spacingUnit}
          <select
            aria-label={`${label} ${t.spacingUnit}`}
            value={unit}
            onChange={(event) => {
              const value = event.currentTarget.value;
              if (value === "point" || value === "percent") setUnit(value);
            }}
          >
            <option value="point">{t.pointUnit}</option>
            <option value="percent">{t.percentUnit}</option>
          </select>
        </label>
      )}
      <button type="submit" disabled={disabled || !draft}>
        {t.apply} {label}
      </button>
    </form>
  );
}

export function PptxParagraph({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    paragraph = editor.query.paragraph;
  return (
    <fieldset
      disabled={
        !!paragraph.reason ||
        state.loading ||
        state.saving ||
        !!state.document?.composition ||
        !!state.document?.paused ||
        !!state.document?.dragging ||
        !!state.document?.closed
      }
    >
      <legend>{t.paragraph}</legend>
      {(
        [
          ["left", t.indentLeft],
          ["right", t.indentRight],
          ["first", t.firstIndent],
          ["before", t.paragraphBefore],
          ["after", t.paragraphAfter],
          ["line", t.lineSpacing],
        ] as const
      ).map(([key, label]) => (
        <ParagraphField
          key={`${key}:${JSON.stringify(paragraph[key])}`}
          property={key}
          label={label}
          value={paragraph[key]}
          state={state}
          disabled={disabled}
          onApply={(format) =>
            controller.run(() =>
              editor.editObjects({ action: "textParagraph", format }),
            )
          }
        />
      ))}
      <button
        type="button"
        disabled={disabled}
        onClick={() =>
          controller.run(() =>
            editor.editObjects({ action: "clearParagraphFormat" }),
          )
        }
      >
        {t.clearParagraph}
      </button>
      {paragraph.reason && <p>{paragraph.reason}</p>}
    </fieldset>
  );
}

export function PptxFormat({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    format = editor.query.formatting;
  const apply = (format: PptxTextFormat) =>
    controller.run(() => editor.editObjects({ action: "textFormat", format }));
  return (
    <fieldset
      disabled={
        !!format.reason ||
        state.loading ||
        state.saving ||
        !!state.document?.composition ||
        !!state.document?.paused ||
        !!state.document?.dragging ||
        !!state.document?.closed
      }
    >
      <legend>{t.textFormat}</legend>
      {(
        [
          ["font", t.fontFamily],
          ["size", t.fontSize],
          ["color", t.textColor],
          ["highlight", t.highlightColor],
        ] as const
      ).map(([key, label]) => (
        <TextField
          key={`${key}:${format[key]}`}
          property={key}
          label={label}
          value={format[key]}
          mixed={t.mixed}
          apply={t.apply}
          disabled={disabled}
          onApply={apply}
        />
      ))}
      {(
        [
          ["bold", t.bold],
          ["italic", t.italic],
          ["underline", t.underline],
          ["strike", t.strike],
        ] as const
      ).map(([key, label]) => (
        <button
          key={key}
          type="button"
          disabled={disabled}
          aria-pressed={format[key] === null ? "mixed" : format[key]}
          onClick={() => apply({ [key]: format[key] !== true })}
        >
          {label}
        </button>
      ))}
      {(
        [
          ["left", t.alignLeft],
          ["center", t.alignCenter],
          ["right", t.alignRight],
        ] as const
      ).map(([alignment, label]) => (
        <button
          key={alignment}
          type="button"
          disabled={disabled}
          aria-pressed={format.alignment === alignment}
          onClick={() =>
            controller.run(() =>
              editor.editObjects({ action: "textAlign", alignment }),
            )
          }
        >
          {label}
        </button>
      ))}
      <button
        type="button"
        disabled={disabled || format.highlight === ""}
        onClick={() => apply({ highlight: "" })}
      >
        {t.highlight_none}
      </button>
      {format.reason && <p>{format.reason}</p>}
      <button
        type="button"
        disabled={disabled}
        onClick={() =>
          controller.run(() =>
            editor.editObjects({ action: "clearTextFormat" }),
          )
        }
      >
        {t.clearFont}
      </button>
    </fieldset>
  );
}
