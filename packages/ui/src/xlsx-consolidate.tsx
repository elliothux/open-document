import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import {
  consolidateFunctions,
  type XlsxConsolidateSettings,
  type XlsxConsolidation,
} from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function XlsxConsolidate({
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
    query = editor.currentState;
  const [sourceSheet, setSourceSheet] = useState(query.sheet);
  const [sourceRange, setSourceRange] = useState(query.selection.address);
  const [settings, setSettings] = useState<XlsxConsolidateSettings>({
    sources: [],
    target: query.selection.address.split(":")[0]!,
    operation: "sum",
    leftLabels: false,
  });
  const [preview, setPreview] = useState<XlsxConsolidation>();
  const [overwrite, setOverwrite] = useState(false);
  const snapshot = editor.getSnapshot(),
    blocked =
      disabled ||
      snapshot.composition ||
      snapshot.dragging ||
      snapshot.paused ||
      snapshot.stopped ||
      !!query.readOnlyReason;
  const ready =
    preview &&
    preview.revision === query.revision &&
    preview.sheet === query.sheet &&
    preview.target === settings.target &&
    preview.operation === settings.operation &&
    preview.leftLabels === settings.leftLabels &&
    JSON.stringify(preview.sources) === JSON.stringify(settings.sources);
  const update = (value: XlsxConsolidateSettings) => {
    setSettings(value);
    setPreview(undefined);
    setOverwrite(false);
  };
  return (
    <fieldset disabled={blocked}>
      <legend>{t.consolidate}</legend>
      <p>{t.consolidateNotice}</p>
      <label>
        {t.consolidateSourceSheet}
        <select
          aria-label={t.consolidateSourceSheet}
          value={sourceSheet}
          onChange={(event) => setSourceSheet(event.currentTarget.value)}
        >
          {query.sheets.map((sheet) => (
            <option key={sheet.id} value={sheet.id}>
              {sheet.name}
            </option>
          ))}
        </select>
      </label>
      <label>
        {t.consolidateSourceRange}
        <input
          value={sourceRange}
          maxLength={64}
          onChange={(event) => setSourceRange(event.currentTarget.value)}
        />
      </label>
      <button
        type="button"
        disabled={!sourceRange || settings.sources.length >= 32}
        onClick={() =>
          update({
            ...settings,
            sources: [
              ...settings.sources,
              { sheet: sourceSheet, range: sourceRange },
            ],
          })
        }
      >
        {t.consolidateAddSource}
      </button>
      <ol>
        {settings.sources.map((source, index) => (
          <li key={index}>
            {query.sheets.find((sheet) => sheet.id === source.sheet)?.name}:{" "}
            {source.range}
            <button
              type="button"
              aria-label={`${t.consolidateRemoveSource} ${index + 1}`}
              onClick={() =>
                update({
                  ...settings,
                  sources: settings.sources.filter((_, at) => at !== index),
                })
              }
            >
              {t.consolidateRemoveSource}
            </button>
          </li>
        ))}
      </ol>
      <label>
        {t.consolidateTarget}
        <input
          value={settings.target}
          maxLength={64}
          onChange={(event) =>
            update({ ...settings, target: event.currentTarget.value })
          }
        />
      </label>
      <label>
        {t.consolidateFunction}
        <select
          aria-label={t.consolidateFunction}
          value={settings.operation}
          onChange={(event) => {
            const operation = consolidateFunctions.find(
              (value) => value === event.currentTarget.value,
            );
            if (operation) update({ ...settings, operation });
          }}
        >
          {consolidateFunctions.map((operation) => (
            <option key={operation} value={operation}>
              {t[`consolidate_${operation}`]}
            </option>
          ))}
        </select>
      </label>
      <label>
        <input
          type="checkbox"
          checked={settings.leftLabels}
          onChange={(event) =>
            update({ ...settings, leftLabels: event.currentTarget.checked })
          }
        />
        {t.consolidateLabels}
      </label>
      <button
        type="button"
        disabled={!settings.sources.length}
        onClick={() =>
          controller.run(async () => {
            setPreview(await editor.consolidation(settings));
            setOverwrite(false);
          })
        }
      >
        {t.consolidatePreview}
      </button>
      {preview && (
        <>
          <p>{preview.resultRange}</p>
          <p>
            {t.consolidateOccupied}: {preview.overwrittenCells}
          </p>
          <div style={{ overflow: "auto", maxHeight: "16rem" }}>
            <table aria-label={t.consolidatePreview}>
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
          {preview.overwrittenCells > 0 && (
            <label>
              <input
                type="checkbox"
                checked={overwrite}
                onChange={(event) => setOverwrite(event.currentTarget.checked)}
              />
              {t.consolidateOverwrite}
            </label>
          )}
          <button
            type="button"
            disabled={!ready || (preview.overwrittenCells > 0 && !overwrite)}
            onClick={() =>
              controller.run(() =>
                editor.editSheet(
                  {
                    action: "consolidate",
                    settings,
                    sourceRevision: preview.revision,
                    overwrite,
                  },
                  preview.sheet,
                ),
              )
            }
          >
            {t.consolidate}
          </button>
        </>
      )}
    </fieldset>
  );
}
