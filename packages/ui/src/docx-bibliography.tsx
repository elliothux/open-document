import { useState } from "react";
import type {
  DocumentEditor,
  DocumentSources,
} from "@open-document/web/editor";
import type { EditorController } from "./controller.js";
import type { messages } from "./messages.js";

export function DocxBibliography({
  controller,
  editor,
  source,
  disabled,
  t,
}: {
  controller: EditorController;
  editor: DocumentEditor;
  source: DocumentSources | undefined;
  disabled: boolean;
  t: ReturnType<typeof messages>;
}) {
  const [title, setTitle] = useState(t.bibliography);
  return (
    <section aria-label={t.bibliography}>
      <h4>{t.bibliography}</h4>
      <p>{t.bibliographyHelp}</p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (source)
            controller.run(() => editor.insertBibliography(source, title));
        }}
      >
        <fieldset
          disabled={disabled || !source || !editor.getSnapshot().selection}
        >
          <label>
            {t.bibliographyTitle}
            <input
              required
              maxLength={255}
              value={title}
              onChange={(event) => setTitle(event.currentTarget.value)}
            />
          </label>
          <button type="submit">{t.insertBibliography}</button>
        </fieldset>
      </form>
      {source?.bibliographies.map((item, index) => (
        <section
          key={item.paragraph}
          aria-label={t.bibliography + " " + (index + 1)}
        >
          <button
            type="button"
            disabled={disabled || !!item.reason}
            onClick={() =>
              controller.run(() =>
                editor.editBibliography(source, {
                  action: "update",
                  paragraph: item.paragraph,
                }),
              )
            }
          >
            {t.updateBibliography}
          </button>
          <button
            type="button"
            disabled={disabled || !!item.reason}
            onClick={() =>
              controller.run(() =>
                editor.editBibliography(source, {
                  action: "delete",
                  paragraph: item.paragraph,
                }),
              )
            }
          >
            {t.deleteBibliography}
          </button>
          {item.reason && <p>{item.reason}</p>}
        </section>
      ))}
    </section>
  );
}
