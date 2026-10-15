import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  DocxPageSettings,
  DocxPageSetup,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxPage({
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
  const [settings, setSettings] = useState<DocxPageSettings>();
  const [draft, setDraft] = useState<DocxPageSetup>();
  const [orientation, setOrientation] = useState<"portrait" | "landscape">(
    "portrait",
  );
  const load = async () => {
    const value = await editor.pageSetup();
    setSettings(value);
    setDraft(value.page ?? undefined);
    setOrientation(
      value.page && value.page.width > value.page.height
        ? "landscape"
        : "portrait",
    );
  };
  const stale = settings?.revision !== state.document?.revision;
  return (
    <section aria-label={t.pageSetup}>
      <h3>{t.pageSetup}</h3>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(load)}
      >
        {t.loadPageSetup}
      </button>
      {settings?.reason && <p>{settings.reason}</p>}
      {draft && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.setPageSetup({ ...draft, orientation });
              await load();
            });
          }}
        >
          <fieldset disabled={disabled || stale}>
            <label>
              {t.pageOrientation}
              <select
                aria-label={t.pageOrientation}
                value={orientation}
                onChange={(event) => {
                  setOrientation(
                    event.currentTarget.value === "landscape"
                      ? "landscape"
                      : "portrait",
                  );
                }}
              >
                <option value="portrait">{t.portrait}</option>
                <option value="landscape">{t.landscape}</option>
              </select>
            </label>
            {(
              [
                ["width", t.pageWidth],
                ["height", t.pageHeight],
                ["top", t.pageTop],
                ["right", t.pageRight],
                ["bottom", t.pageBottom],
                ["left", t.pageLeft],
              ] as const
            ).map(([key, label]) => (
              <label key={key}>
                {label}
                <input
                  type="number"
                  min={key === "width" || key === "height" ? 36 : 0}
                  max={14400}
                  step={0.05}
                  required
                  value={Number.isFinite(draft[key]) ? draft[key] : ""}
                  onChange={(event) => {
                    const value = {
                      ...draft,
                      [key]: event.currentTarget.valueAsNumber,
                    };
                    setDraft(value);
                    if (key === "width" || key === "height")
                      setOrientation(
                        value.width > value.height ? "landscape" : "portrait",
                      );
                  }}
                />
              </label>
            ))}
            <button
              type="submit"
              disabled={
                draft.width - draft.left - draft.right < 12 ||
                draft.height - draft.top - draft.bottom < 12
              }
            >
              {t.applyPageSetup}
            </button>
          </fieldset>
          {stale && <p>{t.reloadPageSetup}</p>}
        </form>
      )}
    </section>
  );
}
