import { useState } from "react";
import type { DocumentEditor, DocumentNotes } from "../web/editor.js";
import type {
  DocxNotes as Notes,
  DocxNoteKind,
  DocxEndnotePosition,
} from "../web/foundation.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function DocxNotes({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const [source, setSource] = useState<DocumentNotes>();
  const [selected, setSelected] = useState<Notes["entries"][number]>();
  const [text, setText] = useState("");
  const [kind, setKind] = useState<DocxNoteKind>("footnote");
  const [newText, setNewText] = useState("");
  const [position, setPosition] = useState<DocxEndnotePosition>("docEnd");
  const load = async (created?: DocxNoteKind) => {
    const value = await editor.notes();
    const selected = created
      ? value.entries.filter((entry) => entry.kind === created).at(-1)
      : undefined;
    setSource(value);
    setPosition(value.endnotes.position ?? "docEnd");
    setSelected(selected);
    setText(selected?.text ?? "");
  };
  const snapshot = editor.getSnapshot();
  const stale =
    source?.documentId !== snapshot.documentId ||
    source.revision !== snapshot.revision;
  return (
    <section aria-label={t.docxNotes}>
      <h4>{t.docxNotes}</h4>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(async () => {
            await editor.insertNote({ kind, text: newText });
            await load(kind);
            setNewText("");
          });
        }}
      >
        <label>
          {t.docxNoteKind}
          <select
            value={kind}
            disabled={disabled}
            onChange={(event) => {
              const value = event.currentTarget.value;
              if (value === "footnote" || value === "endnote") setKind(value);
            }}
          >
            <option value="footnote">{t.docxFootnote}</option>
            <option value="endnote">{t.docxEndnote}</option>
          </select>
        </label>
        <label>
          {t.newDocxNoteText}
          <textarea
            value={newText}
            maxLength={32767}
            disabled={disabled}
            onChange={(event) => setNewText(event.currentTarget.value)}
          />
        </label>
        <button type="submit" disabled={disabled}>
          {t.insertDocxNote}
        </button>
      </form>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(() => load())}
      >
        {t.readDocxNotes}
      </button>
      {source && (
        <>
          <form
            onSubmit={(event) => {
              event.preventDefault();
              controller.run(async () => {
                await editor.setEndnotePosition(source, position);
                await load();
              });
            }}
          >
            <label>
              {t.endnotePosition}
              <select
                aria-label={t.endnotePosition}
                value={position}
                disabled={disabled || stale || !!source.endnotes.reason}
                onChange={(event) => {
                  const value = event.currentTarget.value;
                  if (value === "docEnd" || value === "sectEnd")
                    setPosition(value);
                }}
              >
                <option value="docEnd">{t.endnotesDocumentEnd}</option>
                <option value="sectEnd">{t.endnotesSectionEnd}</option>
              </select>
            </label>
            {source.endnotes.reason && (
              <p role="status">{t.protectedEndnotePosition}</p>
            )}
            <button
              type="submit"
              disabled={disabled || stale || !!source.endnotes.reason}
            >
              {t.applyEndnotePosition}
            </button>
          </form>
          <label>
            {t.docxNoteEntry}
            <select
              value={selected ? `${selected.kind}:${selected.id}` : ""}
              disabled={disabled || stale}
              onChange={(event) => {
                const entry = source.entries.find(
                  (entry) =>
                    `${entry.kind}:${entry.id}` === event.currentTarget.value,
                );
                setSelected(entry);
                setText(entry?.text ?? "");
              }}
            >
              <option value="">—</option>
              {source.entries.map((entry) => (
                <option
                  key={`${entry.kind}:${entry.id}`}
                  value={`${entry.kind}:${entry.id}`}
                >
                  {entry.kind === "footnote" ? t.docxFootnote : t.docxEndnote}:{" "}
                  {entry.text.slice(0, 40) ||
                    (entry.reason ? t.protectedDocxNote : t.emptyDocxNote)}
                </option>
              ))}
            </select>
          </label>
          {selected && (
            <form
              onSubmit={(event) => {
                event.preventDefault();
                controller.run(async () => {
                  await editor.editNote(source, {
                    kind: selected.kind,
                    id: selected.id,
                    text,
                  });
                  await load();
                });
              }}
            >
              {selected.reason ? (
                <>
                  <p role="status">{t.protectedDocxNote}</p>
                  <pre>{selected.text}</pre>
                </>
              ) : (
                <label>
                  {t.docxNoteText}
                  <textarea
                    value={text}
                    maxLength={32767}
                    disabled={disabled || stale}
                    onChange={(event) => setText(event.currentTarget.value)}
                  />
                </label>
              )}
              <button
                type="submit"
                disabled={disabled || stale || !!selected.reason}
              >
                {t.applyDocxNote}
              </button>
              <button
                type="button"
                disabled={disabled || stale || !!selected.reason}
                onClick={() =>
                  controller.run(async () => {
                    await editor.removeNote(source, {
                      kind: selected.kind,
                      id: selected.id,
                    });
                    await load();
                  })
                }
              >
                {t.removeDocxNote}
              </button>
            </form>
          )}
        </>
      )}
    </section>
  );
}
