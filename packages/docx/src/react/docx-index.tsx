import { useEffect, useState } from "react";
import type { DocumentEditor, DocumentIndexes } from "../web/editor.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";
import { docxIndexLabelUnits } from "@open-document/wasm/engine-source";
import { Icon } from "@open-document/ui/icons";

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
      const value = await editor.pages.indexes();
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
      <h3>
        <Icon name="book" />
        {t.indexes}
      </h3>
      <p>{t.indexHelp}</p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() => editor.pages.markIndexEntry(label));
        }}
      >
        <fieldset disabled={disabled || blocked}>
          <label>
            {t.indexTerm}
            <input
              required
              maxLength={docxIndexLabelUnits}
              value={label}
              onChange={(event) => setLabel(event.currentTarget.value)}
            />
          </label>
          <button type="submit">
            <Icon name="plus" />
            {t.markIndexEntry}
          </button>
          <button
            type="button"
            onClick={() => controller.run(() => editor.pages.insertIndex())}
          >
            <Icon name="plus" />
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
                editor.pages.editIndex(source, {
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
                maxLength={docxIndexLabelUnits}
                defaultValue={entry.label}
              />
            </label>
            <button type="submit">
              <Icon name="refresh" />
              {t.updateIndexEntry}
            </button>
            <button
              type="button"
              onClick={() =>
                controller.run(() =>
                  editor.pages.editIndex(source, {
                    action: "deleteEntry",
                    id: entry.id,
                  }),
                )
              }
            >
              <Icon name="trash" />
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
                editor.pages.editIndex(source, {
                  action: "update",
                  paragraph: index.paragraph,
                }),
              )
            }
          >
            <Icon name="refresh" />
            {t.updateIndex}
          </button>
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.pages.editIndex(source, {
                  action: "delete",
                  paragraph: index.paragraph,
                }),
              )
            }
          >
            <Icon name="trash" />
            {t.deleteIndex}
          </button>
          {index.reason && <p>{index.reason}</p>}
        </fieldset>
      ))}
    </section>
  );
}
