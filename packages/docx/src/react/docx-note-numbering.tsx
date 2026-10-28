import { useState } from "react";
import type { DocumentEditor, DocumentNoteNumbering } from "../web/editor.js";
import {
  noteNumberFormats,
  type DocxNoteKind,
  type DocxNoteNumberingValue,
} from "../web/foundation.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function DocxNoteNumbering({
  controller,
  state,
  editor,
  disabled,
  section,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
  section: number;
}) {
  const t = messages(state.locale);
  const [kind, setKind] = useState<DocxNoteKind>("footnote");
  const [source, setSource] = useState<DocumentNoteNumbering>();
  const [draft, setDraft] = useState<DocxNoteNumberingValue>({
    format: "decimal",
    start: 1,
    restart: "continuous",
  });
  const load = async () => {
    const value = await editor.noteNumbering(kind, section);
    setSource(value);
    if (value.value) setDraft(value.value);
  };
  const current = editor.getSnapshot();
  const stale =
    source?.documentId !== current.documentId ||
    source.revision !== current.revision ||
    source.section !== section ||
    source.kind !== kind;
  return (
    <section aria-label={t.noteNumbering}>
      <h4>{t.noteNumbering}</h4>
      <p>
        {t.noteNumberingSection} {section + 1}
      </p>
      <label>
        {t.noteNumberingKind}
        <select
          aria-label={t.noteNumberingKind}
          value={kind}
          disabled={disabled}
          onChange={(event) => {
            const value = event.currentTarget.value;
            if (value === "footnote" || value === "endnote") {
              setKind(value);
              setSource(undefined);
            }
          }}
        >
          <option value="footnote">{t.docxFootnote}</option>
          <option value="endnote">{t.docxEndnote}</option>
        </select>
      </label>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(load)}
      >
        {t.readNoteNumbering}
      </button>
      {source && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.setNoteNumbering(source, draft);
              await load();
            });
          }}
        >
          <fieldset
            disabled={
              disabled || stale || source.value === null || !!source.reason
            }
          >
            <label>
              {t.noteNumberFormat}
              <select
                aria-label={t.noteNumberFormat}
                value={draft.format}
                onChange={(event) => {
                  const format = noteNumberFormats.find(
                    (format) => format === event.currentTarget.value,
                  );
                  if (format) setDraft({ ...draft, format });
                }}
              >
                {noteNumberFormats.map((format) => (
                  <option key={format} value={format}>
                    {t[`listFormat_${format}`]}
                  </option>
                ))}
              </select>
            </label>
            <label>
              {t.noteNumberRestart}
              <select
                aria-label={t.noteNumberRestart}
                value={draft.restart}
                onChange={(event) => {
                  const value = event.currentTarget.value;
                  if (
                    value === "continuous" ||
                    value === "eachSect" ||
                    (kind === "footnote" && value === "eachPage")
                  )
                    setDraft({ ...draft, restart: value });
                }}
              >
                <option value="continuous">{t.noteNumberContinuous}</option>
                <option value="eachSect">{t.noteNumberEachSection}</option>
                {kind === "footnote" && (
                  <option value="eachPage">{t.noteNumberEachPage}</option>
                )}
              </select>
            </label>
            <label>
              {t.noteNumberStart}
              <input
                type="number"
                min={0}
                max={4294967295}
                step={1}
                value={draft.start}
                disabled={draft.restart !== "continuous"}
                onChange={(event) =>
                  setDraft({
                    ...draft,
                    start: event.currentTarget.valueAsNumber,
                  })
                }
              />
            </label>
            <p>{t.noteNumberStartHint}</p>
            <button
              type="submit"
              disabled={
                !Number.isSafeInteger(draft.start) ||
                draft.start < 0 ||
                draft.start > 4294967295
              }
            >
              {t.applyNoteNumbering}
            </button>
          </fieldset>
          {source.reason && <p role="status">{t.protectedNoteNumbering}</p>}
        </form>
      )}
    </section>
  );
}
