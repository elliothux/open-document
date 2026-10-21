import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxCover({
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
  const [title, setTitle] = useState("");
  const [subtitle, setSubtitle] = useState("");
  return (
    <section aria-label={t.coverPage}>
      <h4>{t.coverPage}</h4>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() => editor.setCoverPage({ title, subtitle }));
        }}
      >
        <fieldset disabled={disabled}>
          <label>
            {t.coverTitle}
            <input
              value={title}
              maxLength={256}
              required
              onChange={(event) => setTitle(event.currentTarget.value)}
            />
          </label>
          <label>
            {t.coverSubtitle}
            <input
              value={subtitle}
              maxLength={512}
              onChange={(event) => setSubtitle(event.currentTarget.value)}
            />
          </label>
          <button type="submit" disabled={!title.trim()}>
            {t.applyCover}
          </button>
          <button
            type="button"
            onClick={() => controller.run(() => editor.setCoverPage(null))}
          >
            {t.removeCover}
          </button>
        </fieldset>
      </form>
    </section>
  );
}
