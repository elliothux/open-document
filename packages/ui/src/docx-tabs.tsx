import { useEffect, useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type { TabStop } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

import { DocxTabFields } from "./docx-tab-fields.js";

interface Props {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
}

export function DocxTabs({ controller, state, editor, disabled }: Props) {
  const t = messages(state.locale);
  const current = editor.getSnapshot().data.formatting?.paragraph.tabs;
  const value = current?.kind === "value" ? current.value : undefined;
  const [draft, setDraft] = useState<TabStop[]>(value ?? []);
  useEffect(() => setDraft(value ?? []), [value]);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.setParagraphFormat({
            tabs: [...draft].sort((a, b) => a.position - b.position),
          }),
        );
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.tabStops}</legend>
        {current?.kind === "mixed" && <p>{t.mixed}</p>}
        <DocxTabFields
          draft={draft}
          setDraft={setDraft}
          locale={state.locale}
        />
        <button type="submit">{t.applyTabStops}</button>
        <button
          type="button"
          onClick={() =>
            controller.run(() => editor.setParagraphFormat({ tabs: [] }))
          }
        >
          {t.clearTabStops}
        </button>
        <button
          type="button"
          onClick={() =>
            controller.run(() => editor.setParagraphFormat({ tabs: null }))
          }
        >
          {t.restoreTabStops}
        </button>
      </fieldset>
    </form>
  );
}

export function DocxDefaultTab({ controller, state, editor, disabled }: Props) {
  const t = messages(state.locale);
  const current = editor.getSnapshot().data.defaultTabStop;
  const [draft, setDraft] = useState(String(current));
  useEffect(() => setDraft(String(current)), [current, editor]);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() => editor.setDefaultTabStop(Number(draft)));
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.defaultTabStop}</legend>
        <label>
          {t.defaultTabInterval}
          <input
            aria-label={t.defaultTabInterval}
            type="number"
            required
            min={0}
            max={1584}
            step={0.05}
            value={draft}
            onChange={(event) => setDraft(event.currentTarget.value)}
          />
        </label>
        <button type="submit">{t.applyDefaultTab}</button>
        <button
          type="button"
          onClick={() => controller.run(() => editor.setDefaultTabStop(null))}
        >
          {t.restoreDefaultTab}
        </button>
      </fieldset>
    </form>
  );
}
