import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type { DocxTextWatermark } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

const initial: DocxTextWatermark = {
  text: "CONFIDENTIAL",
  font: "Arial",
  size: 54,
  color: "808080",
  opacity: 0.5,
  diagonal: true,
  bold: false,
  italic: false,
};
export function DocxWatermark({
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
  const [source, setSource] =
    useState<Awaited<ReturnType<DocumentEditor["textWatermark"]>>>();
  const [draft, setDraft] = useState(initial);
  const snapshot = editor.getSnapshot();
  const stale =
    source?.documentId !== snapshot.documentId ||
    source.revision !== snapshot.revision;
  const load = async () => {
    const value = await editor.textWatermark();
    setSource(value);
    setDraft(value.value ?? initial);
  };
  return (
    <section aria-label={t.textWatermark}>
      <h4>{t.textWatermark}</h4>
      <button
        type="button"
        disabled={disabled}
        onClick={() => controller.run(load)}
      >
        {t.readTextWatermark}
      </button>
      {source && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.setTextWatermark(draft);
              await load();
            });
          }}
        >
          {source.reason && <p>{source.reason}</p>}
          {source.mixed && <p role="status">{t.mixedTextWatermarks}</p>}
          <fieldset disabled={disabled || stale || !!source.reason}>
            <label>
              {t.watermarkText}
              <input
                aria-label={t.watermarkText}
                maxLength={256}
                required
                value={draft.text}
                onChange={(event) =>
                  setDraft({ ...draft, text: event.currentTarget.value })
                }
              />
            </label>
            <label>
              {t.watermarkFont}
              <input
                aria-label={t.watermarkFont}
                maxLength={256}
                required
                value={draft.font}
                onChange={(event) =>
                  setDraft({ ...draft, font: event.currentTarget.value })
                }
              />
            </label>
            <label>
              {t.watermarkSize}
              <input
                aria-label={t.watermarkSize}
                type="number"
                min={0.5}
                max={1638}
                step={0.5}
                required
                value={draft.size}
                onChange={(event) =>
                  setDraft({
                    ...draft,
                    size: event.currentTarget.valueAsNumber,
                  })
                }
              />
            </label>
            <label>
              {t.watermarkColor}
              <input
                aria-label={t.watermarkColor}
                type="color"
                value={"#" + draft.color}
                onChange={(event) =>
                  setDraft({
                    ...draft,
                    color: event.currentTarget.value.slice(1),
                  })
                }
              />
            </label>
            <label>
              {t.watermarkOpacity}
              <input
                aria-label={t.watermarkOpacity}
                type="number"
                min={0}
                max={100}
                step="any"
                required
                value={draft.opacity * 100}
                onChange={(event) =>
                  setDraft({
                    ...draft,
                    opacity: event.currentTarget.valueAsNumber / 100,
                  })
                }
              />
            </label>
            <label>
              <input
                type="checkbox"
                checked={draft.diagonal}
                onChange={(event) =>
                  setDraft({ ...draft, diagonal: event.currentTarget.checked })
                }
              />
              {t.watermarkDiagonal}
            </label>
            <label>
              <input
                type="checkbox"
                checked={draft.bold}
                onChange={(event) =>
                  setDraft({ ...draft, bold: event.currentTarget.checked })
                }
              />
              {t.bold}
            </label>
            <label>
              <input
                type="checkbox"
                checked={draft.italic}
                onChange={(event) =>
                  setDraft({ ...draft, italic: event.currentTarget.checked })
                }
              />
              {t.italic}
            </label>
            <button type="submit">{t.applyTextWatermark}</button>
            <button
              type="button"
              disabled={!source.value && !source.mixed}
              onClick={() =>
                controller.run(async () => {
                  await editor.setTextWatermark(null);
                  await load();
                })
              }
            >
              {t.removeTextWatermark}
            </button>
          </fieldset>
        </form>
      )}
    </section>
  );
}
