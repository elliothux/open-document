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
    [kind, setKind] = useState("headings"),
    [sequence, setSequence] = useState(
      state.locale === "zh-CN" ? "图" : "Figure",
    ),
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
          controller.run(() =>
            kind === "headings"
              ? editor.insertTableOfContents(levels)
              : editor.insertTableOfFigures(sequence),
          );
        }}
      >
        <fieldset disabled={disabled || blocked}>
          <label>
            {t.tocSource}
            <select
              value={kind}
              onChange={(event) => setKind(event.currentTarget.value)}
            >
              <option value="headings">{t.tocHeadings}</option>
              <option value="captions">{t.tableOfFigures}</option>
            </select>
          </label>
          {kind === "headings" ? (
            <label>
              {t.tocLevels}
              <input
                type="number"
                required
                min={1}
                max={9}
                value={levels}
                onChange={(event) =>
                  setLevels(event.currentTarget.valueAsNumber)
                }
              />
            </label>
          ) : (
            <label>
              {t.tocSequence}
              <input
                required
                maxLength={40}
                value={sequence}
                onChange={(event) => setSequence(event.currentTarget.value)}
              />
            </label>
          )}
          <button type="submit">
            {kind === "headings" ? t.insertToc : t.insertTableOfFigures}
          </button>
        </fieldset>
      </form>
      {source?.items.map((item, index) => (
        <fieldset
          key={item.paragraph}
          disabled={disabled || blocked || stale || !!item.reason}
        >
          <legend>
            {item.sequence
              ? `${t.tableOfFigures} ${index + 1} (${item.sequence})`
              : `${t.tableOfContents} ${index + 1} (${item.firstLevel}–${item.lastLevel})`}
          </legend>
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
