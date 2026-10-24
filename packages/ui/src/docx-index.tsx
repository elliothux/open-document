import { useEffect, useState } from "react";
import type {
  DocumentEditor,
  DocumentIndexes,
} from "@open-document/web/editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxIndex({
  controller,
  state,
  editor,
  disabled,
  blocked,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
  blocked: boolean;
}) {
  const t = messages(state.locale),
    snapshot = editor.getSnapshot();
  const [label, setLabel] = useState(""),
    [source, setSource] = useState<DocumentIndexes>();
  useEffect(() => {
    if (blocked) return;
    let active = true;
    controller.run(async () => {
      await editor.whenIdle();
      if (!active) return;
      const value = await editor.indexes();
      if (active) setSource(value);
    });
    return () => {
      active = false;
    };
  }, [controller, editor, snapshot.documentId, snapshot.revision, blocked]);
  const stale =
    !source ||
    source.documentId !== snapshot.documentId ||
    source.revision !== snapshot.revision;
  return (
    <section aria-label={t.indexes}>
      <h3>{t.indexes}</h3>
      <p>{t.indexHelp}</p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() => editor.markIndexEntry(label));
        }}
      >
        <fieldset disabled={disabled || blocked}>
          <label>
            {t.indexTerm}
            <input
              required
              maxLength={255}
              value={label}
              onChange={(event) => setLabel(event.currentTarget.value)}
            />
          </label>
          <button type="submit">{t.markIndexEntry}</button>
          <button
            type="button"
            onClick={() => controller.run(() => editor.insertIndex())}
          >
            {t.insertIndex}
          </button>
        </fieldset>
      </form>
      {source?.entries.map((entry, index) => (
        <form
          key={`${entry.id}:${entry.label}`}
          onSubmit={(event) => {
            event.preventDefault();
            const value = new FormData(event.currentTarget).get("label");
            if (typeof value === "string")
              controller.run(() =>
                editor.editIndex(source, {
                  action: "updateEntry",
                  id: entry.id,
                  label: value,
                }),
              );
          }}
        >
          <fieldset disabled={disabled || blocked || stale || !!entry.reason}>
            <label>
              {`${t.indexTerm} ${index + 1}`}
              <input
                name="label"
                required
                maxLength={255}
                defaultValue={entry.label}
              />
            </label>
            <button type="submit">{t.updateIndexEntry}</button>
            <button
              type="button"
              onClick={() =>
                controller.run(() =>
                  editor.editIndex(source, {
                    action: "deleteEntry",
                    id: entry.id,
                  }),
                )
              }
            >
              {t.deleteIndexEntry}
            </button>
            {entry.reason && <p>{entry.reason}</p>}
          </fieldset>
        </form>
      ))}
      {source?.indexes.map((index, number) => (
        <fieldset
          key={index.paragraph}
          disabled={disabled || blocked || stale || !!index.reason}
        >
          <legend>{`${t.indexes} ${number + 1}`}</legend>
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editIndex(source, {
                  action: "update",
                  paragraph: index.paragraph,
                }),
              )
            }
          >
            {t.updateIndex}
          </button>
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editIndex(source, {
                  action: "delete",
                  paragraph: index.paragraph,
                }),
              )
            }
          >
            {t.deleteIndex}
          </button>
          {index.reason && <p>{index.reason}</p>}
        </fieldset>
      ))}
    </section>
  );
}
