import { useEffect, useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type { ParagraphStyleCatalog } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxStyles({
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
  const current = editor.getSnapshot().data.formatting?.paragraph.style;
  const currentId = current?.kind === "value" ? current.value : "";
  const [catalog, setCatalog] = useState<ParagraphStyleCatalog>();
  const [selected, setSelected] = useState(currentId);
  useEffect(() => setCatalog(undefined), [editor]);
  useEffect(() => setSelected(currentId), [currentId]);
  const choice = catalog?.styles.find((style) => style.id === selected);
  return (
    <fieldset disabled={disabled}>
      <legend>{t.paragraphStyle}</legend>
      <button
        type="button"
        onClick={() =>
          controller.run(async () => setCatalog(await editor.paragraphStyles()))
        }
      >
        {t.loadStyles}
      </button>
      <label>
        {t.paragraphStyle}
        <select
          aria-label={t.paragraphStyle}
          value={choice ? selected : ""}
          onChange={(event) => setSelected(event.currentTarget.value)}
        >
          <option value="" disabled>
            {current?.kind === "mixed" ? t.mixed : t.chooseStyle}
          </option>
          {catalog?.styles.map((style) => (
            <option key={style.id} value={style.id} disabled={!!style.reason}>
              {style.name}
              {style.reason ? ` (${style.reason})` : ""}
            </option>
          ))}
        </select>
      </label>
      {catalog?.truncated && <p role="status">{t.styleLimit}</p>}
      <button
        type="button"
        disabled={!choice || !!choice.reason}
        onClick={() =>
          controller.run(() => editor.setParagraphFormat({ style: selected }))
        }
      >
        {t.applyStyle}
      </button>
      <button
        type="button"
        onClick={() =>
          controller.run(() => editor.setParagraphFormat({ style: null }))
        }
      >
        {t.restoreDefaultStyle}
      </button>
    </fieldset>
  );
}
