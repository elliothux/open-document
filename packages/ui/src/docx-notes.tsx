import { useState } from "react";
import type { DocumentEditor, DocumentNotes } from "@open-document/web/editor";
import type { DocxNotes as Notes } from "@open-document/web/foundation";
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
  const load = async () => {
    const value = await editor.notes();
    setSource(value);
    setSelected(undefined);
    setText("");
  };
  const snapshot = editor.getSnapshot();
  const stale =
    source?.documentId !== snapshot.documentId ||
    source.revision !== snapshot.revision;
  return (
    <section aria-label={t.docxNotes}>
      <h4>{t.docxNotes}</h4>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(load)}
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
                  <input
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
            </form>
          )}
        </>
      )}
    </section>
  );
}
