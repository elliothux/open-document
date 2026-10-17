import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import {
  checkXlsxTextColumnSettings,
  type XlsxTextColumnSettings,
  type XlsxTextColumns,
  type XlsxTextColumnType,
} from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function XlsxTextColumns({
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
    range = query.selection.range;
  const choices = [
    [",", t.columnComma],
    [";", t.columnSemicolon],
    [" ", t.columnSpace],
    ["\t", t.columnTab],
  ] as const;
  const [delimiter, setDelimiter] = useState<(typeof choices)[number][0]>(",");
  const [mode, setMode] = useState<"delimited" | "fixed">("delimited");
  const [breakText, setBreakText] = useState("4,8");
  const [preview, setPreview] = useState<XlsxTextColumns>();
  const [overwrite, setOverwrite] = useState(false);
  const [conversions, setConversions] = useState<{
    revision: number;
    sheet: string;
    range: string;
    types: XlsxTextColumnType[];
  }>();
  const [formulas, setFormulas] = useState(false);
  const types =
    conversions?.revision === query.revision &&
    conversions.sheet === query.sheet &&
    conversions.range === query.selection.address
      ? conversions.types
      : [];
  const typeChoices = [
    ["text", t.columnTypeText],
    ["general", t.columnTypeGeneral],
    ["ymd", t.columnTypeYmd],
    ["mdy", t.columnTypeMdy],
    ["dmy", t.columnTypeDmy],
    ["skip", t.columnTypeSkip],
  ] as const;
  const bounded = range.left === range.right && range.bottom - range.top < 4096;
  const positions = breakText.split(",").map((value) => Number(value.trim()));
  const settings: XlsxTextColumnSettings =
    mode === "fixed"
      ? { range: query.selection.address, breaks: positions, types, formulas }
      : { range: query.selection.address, delimiter, types, formulas };
  let valid = bounded;
  try {
    checkXlsxTextColumnSettings(settings);
  } catch {
    valid = false;
  }
  const blocked =
    disabled ||
    snapshot.composition ||
    snapshot.dragging ||
    snapshot.paused ||
    snapshot.stopped ||
    !!query.readOnlyReason ||
    !!query.sheets.find((sheet) => sheet.id === query.sheet)?.protected;
  const ready =
    preview &&
    preview.revision === query.revision &&
    preview.sheet === query.sheet &&
    preview.range === query.selection.address &&
    preview.formulas === formulas &&
    preview.types.length === types.length &&
    preview.types.every((kind, index) => kind === types[index]) &&
    (mode === "delimited"
      ? "delimiter" in preview && preview.delimiter === delimiter
      : "breaks" in preview &&
        preview.breaks.length === positions.length &&
        preview.breaks.every((value, index) => value === positions[index]));
  return (
    <fieldset disabled={blocked}>
      <legend>{t.textToColumns}</legend>
      <p>{query.selection.address}</p>
      <p>{mode === "fixed" ? t.columnFixedNotice : t.columnNotice}</p>
      {!bounded && <p>{t.columnLimit}</p>}
      <label>
        {t.columnSplitMode}
        <select
          aria-label={t.columnSplitMode}
          value={mode}
          onChange={(event) => {
            const value = event.currentTarget.value;
            if (value === "fixed" || value === "delimited") setMode(value);
            setPreview(undefined);
            setOverwrite(false);
            setConversions(undefined);
          }}
        >
          <option value="delimited">{t.columnDelimited}</option>
          <option value="fixed">{t.columnFixed}</option>
        </select>
      </label>
      {mode === "fixed" ? (
        <label>
          {t.columnBreaks}
          <input
            aria-label={t.columnBreaks}
            value={breakText}
            maxLength={24569}
            onChange={(event) => {
              setBreakText(event.currentTarget.value);
              setPreview(undefined);
              setOverwrite(false);
              setConversions(undefined);
            }}
          />
          <span>{t.columnBreakHelp}</span>
        </label>
      ) : (
        <label>
          {t.columnDelimiter}
          <select
            aria-label={t.columnDelimiter}
            value={delimiter}
            onChange={(event) => {
              const choice = choices.find(
                ([value]) => value === event.currentTarget.value,
              );
              if (choice) setDelimiter(choice[0]);
              setPreview(undefined);
              setOverwrite(false);
              setConversions(undefined);
            }}
          >
            {choices.map(([value, label]) => (
              <option key={value} value={value}>
                {label}
              </option>
            ))}
          </select>
        </label>
      )}
      {bounded && !valid && <p>{t.columnBreakInvalid}</p>}
      {types.length > 0 && (
        <fieldset disabled={blocked}>
          <legend>{t.columnTypes}</legend>
          {types.map((kind, index) => (
            <label key={index}>
              {t.columnType} {index + 1}
              <select
                aria-label={`${t.columnType} ${index + 1}`}
                value={kind}
                onChange={(event) => {
                  const choice = typeChoices.find(
                    ([value]) => value === event.currentTarget.value,
                  );
                  if (choice)
                    setConversions({
                      revision: query.revision,
                      sheet: query.sheet,
                      range: query.selection.address,
                      types: types.map((current, at) =>
                        at === index ? choice[0] : current,
                      ),
                    });
                  setPreview(undefined);
                  setOverwrite(false);
                }}
              >
                {typeChoices.map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
          ))}
          <p>{t.columnTypeNotice}</p>
        </fieldset>
      )}
      <label>
        <input
          type="checkbox"
          checked={formulas}
          disabled={!types.includes("general")}
          onChange={(event) => {
            setFormulas(event.currentTarget.checked);
            setPreview(undefined);
            setOverwrite(false);
          }}
        />
        {t.columnFormulas}
      </label>
      <button
        type="button"
        disabled={!valid}
        onClick={() =>
          controller.run(async () => {
            const result = await editor.textColumns(settings);
            setPreview(result);
            setOverwrite(false);
            setConversions({
              revision: result.revision,
              sheet: result.sheet,
              range: result.range,
              types: result.types,
            });
          })
        }
      >
        {t.previewColumns}
      </button>
      {preview && (
        <>
          <p>
            {t.columnResult}: {preview.resultRange}
          </p>
          <p>
            {t.columnOverwritten}: {preview.overwrittenCells}
          </p>
          <div style={{ overflow: "auto", maxHeight: "16rem" }}>
            <table aria-label={t.previewColumns}>
              <tbody>
                {preview.preview.map((row, index) => (
                  <tr key={index}>
                    <th scope="row">{range.top + index}</th>
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
          {preview.overwrittenCells > 0 && (
            <label>
              <input
                type="checkbox"
                checked={overwrite}
                onChange={(event) => setOverwrite(event.currentTarget.checked)}
              />
              {t.columnOverwrite}
            </label>
          )}
          <button
            type="button"
            disabled={!ready || (preview.overwrittenCells > 0 && !overwrite)}
            onClick={() =>
              controller.run(() =>
                editor.editSheet(
                  {
                    action: "textToColumns",
                    settings:
                      "breaks" in preview
                        ? {
                            range: preview.range,
                            breaks: preview.breaks,
                            types: preview.types,
                            formulas: preview.formulas,
                          }
                        : {
                            range: preview.range,
                            delimiter: preview.delimiter,
                            types: preview.types,
                            formulas: preview.formulas,
                          },
                    sourceRevision: preview.revision,
                    overwrite,
                  },
                  preview.sheet,
                ),
              )
            }
          >
            {t.splitColumns}
          </button>
        </>
      )}
    </fieldset>
  );
}
