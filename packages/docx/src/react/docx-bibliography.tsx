import { useState } from "react";
import { docxBibliographyHeadingUnits } from "@open-document/wasm/engine-source";
import type { DocumentEditor, DocumentSources } from "../web/editor.js";
import type { EditorController } from "./context.js";
import type { messages } from "@open-document/ui/messages";
import { Icon } from "@open-document/ui/icons";

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
      <h4>
        <Icon name="book" />
        {t.bibliography}
      </h4>
      <p>{t.bibliographyHelp}</p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (source)
            controller.run(() =>
              editor.sources.insertBibliography(source, title),
            );
        }}
      >
        <fieldset
          disabled={disabled || !source || !editor.getSnapshot().selection}
        >
          <label>
            {t.bibliographyTitle}
            <input
              required
              maxLength={docxBibliographyHeadingUnits}
              value={title}
              onChange={(event) => setTitle(event.currentTarget.value)}
            />
          </label>
          <button type="submit">
            <Icon name="plus" />
            {t.insertBibliography}
          </button>
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
                editor.sources.editBibliography(source, {
                  action: "update",
                  paragraph: item.paragraph,
                }),
              )
            }
          >
            <Icon name="refresh" />
            {t.updateBibliography}
          </button>
          <button
            type="button"
            disabled={disabled || !!item.reason}
            onClick={() =>
              controller.run(() =>
                editor.sources.editBibliography(source, {
                  action: "delete",
                  paragraph: item.paragraph,
                }),
              )
            }
          >
            <Icon name="trash" />
            {t.deleteBibliography}
          </button>
          {item.reason && <p>{item.reason}</p>}
        </section>
      ))}
    </section>
  );
}
