import { useState } from "react";
import type { DocxTextBoxProperties as Properties } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxTextBoxProperties({
  controller,
  state,
  value,
  reason,
  disabled,
  apply,
}: {
  controller: EditorController;
  state: UiSnapshot;
  value: Properties;
  reason: string;
  disabled: boolean;
  apply: (properties: Properties) => Promise<void>;
}) {
  const t = messages(state.locale);
  const [draft, setDraft] = useState(value);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() => apply(draft));
      }}
    >
      <fieldset disabled={disabled || !!reason}>
        <legend>{t.docxTextBoxLayout}</legend>
        {[
          t.docxTextBoxTop,
          t.docxTextBoxRight,
          t.docxTextBoxBottom,
          t.docxTextBoxLeft,
        ].map((label, index) => (
          <label key={label}>
            {label}
            <input
              type="number"
              required
              step="any"
              min={0}
              max={14400}
              value={
                Number.isFinite(draft.insets[index]) ? draft.insets[index] : ""
              }
              onChange={(event) => {
                const insets: Properties["insets"] = [...draft.insets];
                insets[index] = event.currentTarget.valueAsNumber;
                setDraft({ ...draft, insets });
              }}
            />
          </label>
        ))}
        <label>
          {t.docxTextBoxAnchor}
          <select
            aria-label={t.docxTextBoxAnchor}
            value={draft.anchor}
            onChange={(event) => {
              const anchor = event.currentTarget.value;
              if (anchor === "t" || anchor === "ctr" || anchor === "b")
                setDraft({ ...draft, anchor });
            }}
          >
            <option value="t">{t.alignTop}</option>
            <option value="ctr">{t.alignMiddle}</option>
            <option value="b">{t.alignBottom}</option>
          </select>
        </label>
        <label>
          <input
            type="checkbox"
            checked={draft.wrap}
            onChange={(event) =>
              setDraft({ ...draft, wrap: event.currentTarget.checked })
            }
          />
          {t.docxTextBoxWrap}
        </label>
        <label>
          <input
            type="checkbox"
            checked={draft.clip}
            onChange={(event) =>
              setDraft({ ...draft, clip: event.currentTarget.checked })
            }
          />
          {t.docxTextBoxClip}
        </label>
        <button type="submit">{t.applyDocxTextBoxLayout}</button>
      </fieldset>
      {reason && <p>{reason}</p>}
    </form>
  );
}
