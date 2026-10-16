import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { PptxObjectEdit } from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

type Insert = Extract<PptxObjectEdit, { action: "insert" }>;

export function PptxObjects({
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
  const t = messages(state.locale);
  const [draft, setDraft] = useState<Insert>({
    action: "insert",
    kind: "text",
    x: 72,
    y: 72,
    width: 240,
    height: 96,
    text: "",
  });
  const query = editor.query;
  const selected = query.objects.find(
    (object) => object.id === query.selection.object,
  );
  const objectMode = query.selection.mode === "object";
  return (
    <section aria-label={t.insertObject}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({
              ...draft,
              text: draft.kind === "line" ? "" : draft.text,
            }),
          );
        }}
      >
        <fieldset disabled={disabled || !!query.readOnlyReason}>
          <legend>{t.insertObject}</legend>
          <label>
            {t.objectKind}
            <select
              value={draft.kind}
              onChange={(event) => {
                const kind = event.currentTarget.value;
                if (
                  kind === "text" ||
                  kind === "rect" ||
                  kind === "roundRect" ||
                  kind === "leftArrow" ||
                  kind === "rightArrow" ||
                  kind === "upArrow" ||
                  kind === "downArrow" ||
                  kind === "ellipse" ||
                  kind === "line"
                )
                  setDraft({ ...draft, kind });
              }}
            >
              <option value="text">{t.textBox}</option>
              <option value="rect">{t.rectangle}</option>
              <option value="roundRect">{t.roundRectangle}</option>
              <option value="ellipse">{t.ellipse}</option>
              <option value="line">{t.lineShape}</option>
              <option value="leftArrow">{t.leftArrow}</option>
              <option value="rightArrow">{t.rightArrow}</option>
              <option value="upArrow">{t.upArrow}</option>
              <option value="downArrow">{t.downArrow}</option>
            </select>
          </label>
          {(
            [
              ["x", t.objectX],
              ["y", t.objectY],
              ["width", t.objectWidth],
              ["height", t.objectHeight],
            ] as const
          ).map(([key, label]) => (
            <label key={key}>
              {label}
              <input
                type="number"
                step="any"
                required
                value={draft[key]}
                min={
                  key === "x" || key === "y"
                    ? -14400
                    : draft.kind === "line"
                      ? 0
                      : 0.1
                }
                max={14400}
                onChange={(event) =>
                  setDraft({
                    ...draft,
                    [key]: event.currentTarget.valueAsNumber,
                  })
                }
              />
            </label>
          ))}
          <label>
            {t.objectText}
            <textarea
              value={draft.text}
              maxLength={32767}
              disabled={draft.kind === "line"}
              onChange={(event) =>
                setDraft({ ...draft, text: event.currentTarget.value })
              }
            />
          </label>
          <button type="submit">{t.insertObject}</button>
        </fieldset>
      </form>
      <button
        type="button"
        disabled={
          disabled || !objectMode || !selected || !!selected.duplicateReason
        }
        title={selected?.duplicateReason}
        onClick={() =>
          controller.run(() =>
            editor.editObjects({ action: "duplicate", dx: 18, dy: 18 }),
          )
        }
      >
        {t.duplicateObject}
      </button>
      <button
        type="button"
        disabled={
          disabled || !objectMode || !selected || !!selected.deleteReason
        }
        title={selected?.deleteReason}
        onClick={() =>
          controller.run(() => editor.editObjects({ action: "delete" }))
        }
      >
        {t.deleteObject}
      </button>
      {selected?.deleteReason && <p>{selected.deleteReason}</p>}
      {selected?.duplicateReason &&
        selected.duplicateReason !== selected.deleteReason && (
          <p>{selected.duplicateReason}</p>
        )}
    </section>
  );
}
