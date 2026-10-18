import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { XlsxDuplicates } from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { selectedXlsxTable } from "./xlsx-tables.js";

export function XlsxDuplicates({
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
    snapshot = editor.getSnapshot(),
    native = selectedXlsxTable(query),
    range = native?.range ?? query.selection.range,
    address = native?.table.range ?? query.selection.address;
  const bounded =
    (range.bottom - range.top + 1) * (range.right - range.left + 1) <= 4096;
  const [header, setHeader] = useState(native?.table.headerRow ?? false);
  const [columns, setColumns] = useState(() =>
    bounded
      ? Array.from(
          { length: range.right - range.left + 1 },
          (_, i) => range.left + i,
        )
      : [],
  );
  const [preview, setPreview] = useState<XlsxDuplicates>();
  const blocked =
    disabled ||
    snapshot.composition ||
    snapshot.dragging ||
    snapshot.paused ||
    snapshot.stopped ||
    !!query.readOnlyReason ||
    !!native?.table.readOnlyReason ||
    !!query.sheets.find((s) => s.id === query.sheet)?.protected;
  const ready =
    preview &&
    preview.revision === query.revision &&
    preview.sheet === query.sheet &&
    preview.range === address &&
    preview.header === header &&
    preview.columns.length === columns.length &&
    preview.columns.every((column, i) => column === columns[i]);
  return (
    <fieldset disabled={blocked}>
      <legend>{t.removeDuplicates}</legend>
      <p>{address}</p>
      <p>{t.duplicateNotice}</p>
      {!bounded && <p>{t.duplicateLimit}</p>}
      <label>
        <input
          type="checkbox"
          checked={header}
          disabled={!!native}
          onChange={(event) => {
            setHeader(event.currentTarget.checked);
            setPreview(undefined);
          }}
        />
        {t.duplicateHeader}
      </label>
      {bounded &&
        Array.from(
          { length: range.right - range.left + 1 },
          (_, i) => range.left + i,
        ).map((column) => (
          <label key={column}>
            <input
              type="checkbox"
              checked={columns.includes(column)}
              onChange={(event) => {
                const checked = event.currentTarget.checked;
                setColumns((values) =>
                  checked
                    ? [...values, column].sort((a, b) => a - b)
                    : values.filter((value) => value !== column),
                );
                setPreview(undefined);
              }}
            />
            {t.duplicateColumn} {column}
          </label>
        ))}
      <button
        type="button"
        disabled={!bounded || !columns.length}
        onClick={() =>
          controller.run(async () =>
            setPreview(
              await editor.duplicates({
                range: address,
                header,
                columns,
              }),
            ),
          )
        }
      >
        {t.previewDuplicates}
      </button>
      {preview && (
        <>
          <p>
            {t.duplicateKept}: {preview.keptRows.length} ({preview.resultRange})
          </p>
          <p>
            {t.duplicateRemoved}: {preview.removedRows.length} (
            {preview.removedRows.slice(0, 20).join(", ")}
            {preview.removedRows.length > 20 ? "…" : ""})
          </p>
          <div style={{ overflow: "auto", maxHeight: "16rem" }}>
            <table aria-label={t.previewDuplicates}>
              <tbody>
                {preview.preview.map((row, index) => (
                  <tr key={index}>
                    <th scope="row">{preview.keptRows[index]}</th>
                    {row.map((value, column) => (
                      <td key={column} style={{ whiteSpace: "pre-wrap" }}>
                        {value}
                      </td>
                    ))}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <button
            type="button"
            disabled={!ready || !preview.removedRows.length}
            onClick={() =>
              controller.run(() =>
                editor.editSheet(
                  {
                    action: "removeDuplicates",
                    settings: {
                      range: preview.range,
                      header: preview.header,
                      columns: preview.columns,
                    },
                    sourceRevision: preview.revision,
                  },
                  preview.sheet,
                ),
              )
            }
          >
            {t.removeDuplicates}
          </button>
        </>
      )}
    </fieldset>
  );
}
