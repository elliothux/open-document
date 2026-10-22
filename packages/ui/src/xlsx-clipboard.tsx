import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function XlsxClipboard({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: SpreadsheetEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    [transpose, setTranspose] = useState(false);
  return (
    <fieldset disabled={disabled}>
      <legend>{t.clipboard}</legend>
      <button
        type="button"
        onMouseDown={(event) => event.preventDefault()}
        onClick={() => controller.run(() => editor.pasteDrawing())}
      >
        {t.pasteDrawing}
      </button>
      <button
        type="button"
        onMouseDown={(event) => event.preventDefault()}
        onClick={() => controller.run(() => editor.copyCells())}
      >
        {t.copyCells}
      </button>
      <button
        type="button"
        onMouseDown={(event) => event.preventDefault()}
        onClick={() => controller.run(() => editor.copyCells(true))}
      >
        {t.cutCells}
      </button>
      <label>
        <input
          type="checkbox"
          checked={transpose}
          onChange={(event) => setTranspose(event.currentTarget.checked)}
        />
        {t.transposeCells}
      </label>
      {(
        [
          ["all", t.pasteAllCells],
          ["values", t.pasteCellValues],
          ["formulas", t.pasteCellFormulas],
          ["format", t.pasteCellFormat],
        ] as const
      ).map(([mode, label]) => (
        <button
          type="button"
          key={mode}
          onMouseDown={(event) => event.preventDefault()}
          onClick={() =>
            controller.run(() => editor.pasteCells(mode, transpose))
          }
        >
          {label}
        </button>
      ))}
    </fieldset>
  );
}
