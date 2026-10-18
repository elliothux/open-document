import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type { DocxFormatting } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxCellSelection({
  controller,
  state,
  editor,
  selected,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  selected: NonNullable<DocxFormatting["cellSelection"]["value"]>;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const [fill, setFill] = useState(
    `#${selected.fill.kind === "value" ? (selected.fill.value ?? "ffffff") : "ffffff"}`,
  );
  return (
    <section aria-label={t.selectedCells}>
      <h3>
        {t.selectedCells}: {selected.count}
      </h3>
      <p>{t.cellSelectionText}</p>
      <fieldset disabled={disabled}>
        <legend>{t.cellFill}</legend>
        {selected.fill.kind === "mixed" && <p>{t.mixed}</p>}
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(() =>
              editor.editTable({ action: "cellFill", value: fill.slice(1) }),
            );
          }}
        >
          <label>
            {t.cellFill}
            <input
              type="color"
              value={fill}
              onChange={(event) => setFill(event.currentTarget.value)}
            />
          </label>
          <button type="submit" aria-label={`${t.apply} ${t.cellFill}`}>
            {t.apply}
          </button>
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editTable({ action: "cellFill", value: null }),
              )
            }
          >
            {t.clearCellFill}
          </button>
        </form>
      </fieldset>
      <fieldset disabled={disabled}>
        <legend>{t.cellVerticalAlign}</legend>
        {selected.verticalAlign.kind === "mixed" && <p>{t.mixed}</p>}
        {(
          [
            ["top", t.alignTop],
            ["center", t.alignMiddle],
            ["bottom", t.alignBottom],
          ] as const
        ).map(([value, label]) => (
          <button
            type="button"
            key={value}
            aria-pressed={
              selected.verticalAlign.kind === "value" &&
              selected.verticalAlign.value === value
            }
            onClick={() =>
              controller.run(() =>
                editor.editTable({ action: "cellVerticalAlign", value }),
              )
            }
          >
            {label}
          </button>
        ))}
        <button
          type="button"
          onClick={() =>
            controller.run(() =>
              editor.editTable({ action: "cellVerticalAlign", value: null }),
            )
          }
        >
          {t.inheritStyleProperty}
        </button>
      </fieldset>
    </section>
  );
}
