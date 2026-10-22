import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type {
  PptxMasterTextStyle,
  PptxTextFormat,
} from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { TextField } from "./pptx-format.js";
import { PptxMasterParagraph } from "./pptx-master-paragraph.js";

export function PptxMasterText({
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
    styles = editor.query.editView.textStyles;
  const [kind, setKind] = useState<PptxMasterTextStyle["kind"]>("title"),
    [level, setLevel] = useState(0);
  if (editor.query.editView.kind !== "master") return null;
  const selected = styles.items.find(
    (item) => item.kind === kind && item.level === level,
  );
  const apply = (format: PptxTextFormat | null) =>
    controller.run(() =>
      editor.editSlides({ action: "masterTextStyle", kind, level, format }),
    );
  return (
    <fieldset disabled={disabled || !!styles.reason}>
      <legend>{t.pptxMasterText}</legend>
      <label>
        {t.pptxMasterTextKind}
        <select
          aria-label={t.pptxMasterTextKind}
          value={kind}
          onChange={(event) => {
            const value = event.currentTarget.value;
            if (value === "title" || value === "body" || value === "other")
              setKind(value);
          }}
        >
          <option value="title">{t.pptxPlaceholder_title}</option>
          <option value="body">{t.pptxPlaceholder_body}</option>
          <option value="other">{t.pptxMasterTextOther}</option>
        </select>
      </label>
      <label>
        {t.pptxMasterTextLevel}
        <select
          aria-label={t.pptxMasterTextLevel}
          value={level}
          onChange={(event) => setLevel(Number(event.currentTarget.value))}
        >
          {Array.from({ length: 9 }, (_, index) => (
            <option key={index} value={index}>
              {index + 1}
            </option>
          ))}
        </select>
      </label>
      {selected?.format && (
        <>
          {(
            [
              ["font", t.fontFamily],
              ["size", t.fontSize],
              ["spacing", t.characterSpacing],
              ["color", t.textColor],
              ["highlight", t.highlightColor],
            ] as const
          ).map(([property, label]) => (
            <TextField
              key={`${kind}:${level}:${property}:${selected.format?.[property]}`}
              property={property}
              label={label}
              value={selected.format?.[property] ?? null}
              mixed={t.mixed}
              apply={t.apply}
              disabled={disabled || !!selected.reason || !!styles.reason}
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
          ).map(([property, label]) => (
            <button
              key={property}
              type="button"
              aria-pressed={!!selected.format?.[property]}
              disabled={!!selected.reason}
              onClick={() =>
                apply({ [property]: !selected.format?.[property] })
              }
            >
              {label}
            </button>
          ))}
          {(["superscript", "subscript"] as const).map((script) => (
            <button
              key={script}
              type="button"
              aria-pressed={selected.format?.script === script}
              disabled={!!selected.reason}
              onClick={() =>
                apply({
                  script:
                    selected.format?.script === script ? "baseline" : script,
                })
              }
            >
              {t[script]}
            </button>
          ))}
          <button
            type="button"
            disabled={!!selected.reason || !selected.format.highlight}
            onClick={() => apply({ highlight: "" })}
          >
            {t.highlight_none}
          </button>
        </>
      )}
      <button
        type="button"
        disabled={!selected || !!selected.reason}
        onClick={() => apply(null)}
      >
        {t.pptxResetMasterText}
      </button>
      {(styles.reason || selected?.reason) && (
        <p>{styles.reason || selected?.reason}</p>
      )}
      {selected && (
        <PptxMasterParagraph
          key={`${kind}:${level}`}
          state={state}
          paragraph={selected.paragraph}
          disabled={disabled || !!styles.reason}
          apply={(format) =>
            controller.run(() =>
              editor.editSlides({
                action: "masterParagraphStyle",
                kind,
                level,
                format,
              }),
            )
          }
        />
      )}
    </fieldset>
  );
}
