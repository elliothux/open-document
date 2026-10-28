import { useState } from "react";
import type { SpreadsheetEditor } from "../web/spreadsheet-editor.js";
import {
  subtotalFunctions,
  type XlsxSubtotalSettings,
  type XlsxSubtotals,
} from "../web/xlsx.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function XlsxSubtotal({
  editor,
  controller,
  state,
  disabled,
}: {
  editor: SpreadsheetEditor;
  controller: EditorController;
  state: UiSnapshot;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    query = editor.currentState,
    range = query.selection.range;
  const [settings, setSettings] = useState<XlsxSubtotalSettings>({
    range: query.selection.address,
    groupColumn: range.left,
    valueColumn: Math.min(range.right, range.left + 1),
    operation: "sum",
  });
  const [preview, setPreview] = useState<XlsxSubtotals>();
  const snapshot = editor.getSnapshot(),
    blocked =
      disabled ||
      snapshot.composition ||
      snapshot.dragging ||
      snapshot.paused ||
      snapshot.stopped ||
      !!query.dimensions.readOnlyReason;
  const bounded =
    range.bottom > range.top &&
    range.right > range.left &&
    (range.bottom - range.top + 1) * (range.right - range.left + 1) <= 4096;
  const ready =
    preview &&
    preview.revision === query.revision &&
    preview.sheet === query.sheet &&
    preview.range === settings.range &&
    preview.groupColumn === settings.groupColumn &&
    preview.valueColumn === settings.valueColumn &&
    preview.operation === settings.operation;
  const valid =
    bounded &&
    Number.isSafeInteger(settings.groupColumn) &&
    Number.isSafeInteger(settings.valueColumn) &&
    settings.groupColumn >= range.left &&
    settings.groupColumn <= range.right &&
    settings.valueColumn >= range.left &&
    settings.valueColumn <= range.right &&
    settings.valueColumn !== settings.groupColumn;
  const update = (value: XlsxSubtotalSettings) => {
    setSettings(value);
    setPreview(undefined);
  };
  return (
    <fieldset disabled={blocked}>
      <legend>{t.subtotal}</legend>
      <p>{settings.range}</p>
      <p>{t.subtotalNotice}</p>
      {!bounded && <p>{t.subtotalRangeNotice}</p>}
      <label>
        {t.subtotalGroupColumn}
        <input
          type="number"
          min={range.left}
          max={range.right}
          step={1}
          value={settings.groupColumn}
          onChange={(event) =>
            update({
              ...settings,
              groupColumn: event.currentTarget.valueAsNumber,
            })
          }
        />
      </label>
      <label>
        {t.subtotalValueColumn}
        <input
          type="number"
          min={range.left}
          max={range.right}
          step={1}
          value={settings.valueColumn}
          onChange={(event) =>
            update({
              ...settings,
              valueColumn: event.currentTarget.valueAsNumber,
            })
          }
        />
      </label>
      <label>
        {t.subtotalFunction}
        <select
          aria-label={t.subtotalFunction}
          value={settings.operation}
          onChange={(event) => {
            const operation = subtotalFunctions.find(
              (value) => value === event.currentTarget.value,
            );
            if (operation) update({ ...settings, operation });
          }}
        >
          {subtotalFunctions.map((operation) => (
            <option key={operation} value={operation}>
              {t[`subtotal_${operation}`]}
            </option>
          ))}
        </select>
      </label>
      <button
        type="button"
        disabled={!valid}
        onClick={() =>
          controller.run(async () =>
            setPreview(await editor.subtotals(settings)),
          )
        }
      >
        {t.subtotalPreview}
      </button>
      {preview && (
        <>
          <p>
            {t.subtotalGroups}: {preview.groups.length} ({preview.resultRange})
          </p>
          <div style={{ overflow: "auto", maxHeight: "16rem" }}>
            <table aria-label={t.subtotalPreview}>
              <tbody>
                {preview.preview.map((row, index) => (
                  <tr key={index}>
                    {row.map((text, column) => (
                      <td key={column} style={{ whiteSpace: "pre-wrap" }}>
                        {text}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <button
            type="button"
            disabled={!valid || !ready}
            onClick={() =>
              controller.run(() =>
                editor.editSheet(
                  {
                    action: "createSubtotals",
                    settings,
                    sourceRevision: preview.revision,
                  },
                  preview.sheet,
                ),
              )
            }
          >
            {t.subtotalCreate}
          </button>
        </>
      )}
    </fieldset>
  );
}
