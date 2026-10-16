import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function XlsxPrintSetup({
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
    current = editor.currentState.printSetup;
  const [paper, setPaper] = useState(current.paper),
    [orientation, setOrientation] = useState(current.orientation);
  const [values, setValues] = useState({
    left: String(current.left),
    top: String(current.top),
    right: String(current.right),
    bottom: String(current.bottom),
    scale: String(current.scale),
    fitWidth: String(current.fitWidth),
    fitHeight: String(current.fitHeight),
  });
  const draftDisabled =
    state.loading ||
    !!state.document?.paused ||
    !!state.document?.composition ||
    !!state.document?.dragging ||
    !!state.document?.closed;
  return (
    <fieldset disabled={draftDisabled || !!current.readOnlyReason}>
      <legend>{t.sheetPrintSetup}</legend>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(async () => {
            await editor.editSheet({
              action: "pageSetup",
              paper,
              orientation,
              left: Number(values.left),
              top: Number(values.top),
              right: Number(values.right),
              bottom: Number(values.bottom),
              scale: Number(values.scale),
              fitWidth: Number(values.fitWidth),
              fitHeight: Number(values.fitHeight),
            });
          });
        }}
      >
        <label>
          {t.printPaper}
          <select
            aria-label={t.printPaper}
            value={paper}
            onChange={(event) => {
              const value = event.currentTarget.value;
              if (value === "A4" || value === "Letter") setPaper(value);
            }}
          >
            <option value="A4">A4</option>
            <option value="Letter">Letter</option>
          </select>
        </label>
        <label>
          {t.pageOrientation}
          <select
            aria-label={t.pageOrientation}
            value={orientation}
            onChange={(event) => {
              const value = event.currentTarget.value;
              if (value === "portrait" || value === "landscape")
                setOrientation(value);
            }}
          >
            <option value="portrait">{t.portrait}</option>
            <option value="landscape">{t.landscape}</option>
          </select>
        </label>
        {(
          [
            ["left", t.pageLeft],
            ["top", t.pageTop],
            ["right", t.pageRight],
            ["bottom", t.pageBottom],
            ["scale", t.printScale],
            ["fitWidth", t.printFitWidth],
            ["fitHeight", t.printFitHeight],
          ] as const
        ).map(([key, label]) => (
          <label key={key}>
            {label}
            <input
              type="number"
              required
              step={
                key === "scale" || key === "fitWidth" || key === "fitHeight"
                  ? 1
                  : "any"
              }
              min={key === "scale" ? 10 : 0}
              max={
                key === "scale"
                  ? 400
                  : key === "fitWidth" || key === "fitHeight"
                    ? 1024
                    : 14400
              }
              value={values[key]}
              onChange={(event) => {
                const value = event.currentTarget.value;
                setValues((previous) => ({
                  ...previous,
                  [key]: value,
                }));
              }}
            />
          </label>
        ))}
        <p>{t.printFitNotice}</p>
        <button type="submit" disabled={disabled}>
          {t.apply} {t.sheetPrintSetup}
        </button>
      </form>
      {current.readOnlyReason && <p>{current.readOnlyReason}</p>}
    </fieldset>
  );
}
