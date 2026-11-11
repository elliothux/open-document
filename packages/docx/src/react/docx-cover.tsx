import { useState } from "react";
import {
  docxCoverSubtitleUnits,
  docxCoverTitleUnits,
} from "@open-document/wasm/engine-source";
import type { DocumentEditor } from "../web/editor.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";
import { Icon } from "@open-document/ui/icons";

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
      <h4>
        <Icon name="file-plus" />
        {t.coverPage}
      </h4>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() => editor.pages.setCoverPage({ title, subtitle }));
        }}
      >
        <fieldset disabled={disabled}>
          <label>
            {t.coverTitle}
            <input
              value={title}
              maxLength={docxCoverTitleUnits}
              required
              onChange={(event) => setTitle(event.currentTarget.value)}
            />
          </label>
          <label>
            {t.coverSubtitle}
            <input
              value={subtitle}
              maxLength={docxCoverSubtitleUnits}
              onChange={(event) => setSubtitle(event.currentTarget.value)}
            />
          </label>
          <button type="submit" disabled={!title.trim()}>
            <Icon name="check" />
            {t.applyCover}
          </button>
          <button
            type="button"
            onClick={() =>
              controller.run(() => editor.pages.setCoverPage(null))
            }
          >
            <Icon name="trash" />
            {t.removeCover}
          </button>
        </fieldset>
      </form>
    </section>
  );
}
