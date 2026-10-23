import { useState } from "react";
import type { DocumentEditor, DocumentNotes } from "@open-document/web/editor";
import type {
  DocxNotes as Notes,
  DocxNoteKind,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

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
  const load = async (created?: DocxNoteKind) => {
    const value = await editor.notes();
    const selected = created
      ? value.entries.filter((entry) => entry.kind === created).at(-1)
      : undefined;
    setSource(value);
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
