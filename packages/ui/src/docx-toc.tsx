import { useEffect, useState } from "react";
import type {
  DocumentEditor,
  DocumentTableOfContents,
} from "@open-document/web/editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxToc({
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
  const [levels, setLevels] = useState(3),
    [source, setSource] = useState<DocumentTableOfContents>();
  useEffect(() => {
    if (blocked) return;
    let active = true;
    controller.run(async () => {
      await editor.whenIdle();
      if (!active) return;
      const source = await editor.tableOfContents();
      if (active) setSource(source);
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
    <section aria-label={t.tableOfContents}>
      <h3>{t.tableOfContents}</h3>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() => editor.insertTableOfContents(levels));
        }}
      >
        <fieldset disabled={disabled || blocked}>
          <label>
            {t.tocLevels}
            <input
              type="number"
              required
              min={1}
              max={9}
              value={levels}
              onChange={(event) => setLevels(event.currentTarget.valueAsNumber)}
            />
          </label>
          <button type="submit">{t.insertToc}</button>
        </fieldset>
      </form>
      {source?.items.map((item, index) => (
        <fieldset
          key={item.paragraph}
          disabled={disabled || blocked || stale || !!item.reason}
        >
          <legend>{`${t.tableOfContents} ${index + 1} (${item.firstLevel}–${item.lastLevel})`}</legend>
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editTableOfContents(source, {
                  action: "update",
                  paragraph: item.paragraph,
                }),
              )
            }
          >
            {t.updateToc}
          </button>
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editTableOfContents(source, {
                  action: "delete",
                  paragraph: item.paragraph,
                }),
              )
            }
          >
            {t.deleteToc}
          </button>
          {item.reason && <p>{item.reason}</p>}
        </fieldset>
      ))}
    </section>
  );
}
