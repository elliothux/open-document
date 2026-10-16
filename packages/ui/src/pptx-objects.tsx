import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { PptxObjectEdit } from "@open-document/web/pptx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { PptxPaint } from "./pptx-paint.js";
import { PptxTextFrame } from "./pptx-text-frame.js";
import { PptxFormat, PptxParagraph } from "./pptx-format.js";

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
  const duplicationReason = query.objects.find(
    (object) =>
      query.selection.objects.includes(object.id) && object.duplicateReason,
  )?.duplicateReason;
  const deletionReason = query.objects.find(
    (object) =>
      query.selection.objects.includes(object.id) && object.deleteReason,
  )?.deleteReason;
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
        disabled={disabled || !objectMode || !selected || !!duplicationReason}
        title={duplicationReason}
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
          disabled ||
          query.selection.mode !== "object" ||
          !selected ||
          !!deletionReason
        }
        title={deletionReason}
        onClick={() =>
          controller.run(() => editor.editObjects({ action: "delete" }))
        }
      >
        {t.deleteObject}
      </button>
      <button
        type="button"
        disabled={disabled || !!query.groupReason}
        title={query.groupReason}
        onClick={() =>
          controller.run(() => editor.editObjects({ action: "group" }))
        }
      >
        {t.groupObjects}
      </button>
      <button
        type="button"
        disabled={disabled || !!query.ungroupReason}
        title={query.ungroupReason}
        onClick={() =>
          controller.run(() => editor.editObjects({ action: "ungroup" }))
        }
      >
        {t.ungroupObjects}
      </button>
      {selected?.deleteReason && <p>{selected.deleteReason}</p>}
      {selected?.duplicateReason &&
        selected.duplicateReason !== selected.deleteReason && (
          <p>{selected.duplicateReason}</p>
        )}
      <PptxPaint
        key={`${state.document?.documentId}:${query.revision}:${query.selection.mode}:${query.selection.objects.join(",")}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <PptxFormat
        key={`${state.document?.documentId}:${query.selection.objects.join(",")}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <PptxParagraph
        key={`paragraph:${state.document?.documentId}:${query.selection.objects.join(",")}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
      <PptxTextFrame
        key={`${state.document?.documentId}:${JSON.stringify(query.objects.filter((object) => query.selection.objects.includes(object.id)).map((object) => [object.id, object.textFrame]))}`}
        controller={controller}
        state={state}
        editor={editor}
        disabled={disabled}
      />
    </section>
  );
}
