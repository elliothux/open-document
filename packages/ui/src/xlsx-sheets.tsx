import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

interface SheetProps {
  controller: EditorController;
  state: UiSnapshot;
  editor: SpreadsheetEditor;
  disabled: boolean;
}

export function XlsxSheets({
  controller,
  state,
  editor,
  disabled,
}: SheetProps) {
  const t = messages(state.locale),
    query = editor.currentState;
  const [chosen, setChosen] = useState("");
  const [name, setName] = useState("");
  const [height, setHeight] = useState("");
  const [width, setWidth] = useState("");
  const [series, setSeries] = useState(false);
  const [seriesMode, setSeriesMode] = useState<
    "linear" | "growth" | "date" | "text" | "auto"
  >("linear");
  const [dateUnit, setDateUnit] = useState<
    "day" | "weekday" | "month" | "year"
  >("day");
  const [dateStep, setDateStep] = useState("1");
  const [seed, setSeed] = useState({ sheet: "", range: "" });
  const source = seed.sheet === query.sheet ? seed.range : "";
  const position = query.sheets.findIndex((sheet) => sheet.id === query.sheet);
  const visible = query.sheets.filter((sheet) => sheet.state === "visible");
  const hidden = query.sheets.filter((sheet) => sheet.state === "hidden");
  const target =
    hidden.find((sheet) => sheet.id === chosen)?.id ?? hidden[0]?.id ?? "";
  return (
    <nav
      className="od-sheets"
      aria-label={t.sheet}
      onMouseDown={(event) => {
        // The queued sheet command commits the draft without losing the click to blur.
        if (
          event.button === 0 &&
          event.target instanceof Element &&
          event.target.closest("button")
        )
          event.preventDefault();
      }}
    >
      {visible.map((sheet) => (
        <button
          type="button"
          key={sheet.id}
          aria-current={sheet.id === query.sheet ? "page" : undefined}
          disabled={disabled}
          onClick={() => controller.run(() => editor.select("A1", sheet.id))}
        >
          {sheet.name}
        </button>
      ))}
      <fieldset disabled={disabled}>
        <legend>{t.manageSheets}</legend>
        <button
          type="button"
          disabled={query.sheets.length >= 256 || !!query.sheetEditReason}
          onClick={() =>
            controller.run(() => editor.editSheet({ action: "add" }))
          }
        >
          {t.addSheet}
        </button>
        <button
          type="button"
          disabled={
            query.sheets.length >= 256 ||
            !!query.sheetCopyReason ||
            !!query.sheetEditReason
          }
          onClick={() =>
            controller.run(() => editor.editSheet({ action: "copy" }))
          }
        >
          {t.copySheet}
        </button>
        <button
          type="button"
          disabled={
            visible.length <= 1 ||
            !!query.sheetDeleteReason ||
            !!query.sheetEditReason
          }
          onClick={() =>
            controller.run(() => editor.editSheet({ action: "delete" }))
          }
        >
          {t.deleteSheet}
        </button>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.editSheet({ action: "rename", name });
              setName("");
            });
          }}
        >
          <label>
            {t.sheetName}
            <input
              value={name}
              maxLength={31}
              required
              disabled={!!query.sheetRenameReason}
              onChange={(event) => setName(event.currentTarget.value)}
            />
          </label>
          <button type="submit" disabled={!!query.sheetRenameReason || !name}>
            {t.renameSheet}
          </button>
        </form>
        {query.sheetRenameReason &&
          query.sheetRenameReason !== query.sheetEditReason && (
            <p>{query.sheetRenameReason}</p>
          )}
        <button
          type="button"
          disabled={position <= 0 || !!query.sheetEditReason}
          onClick={() =>
            controller.run(() =>
              editor.editSheet({ action: "move", index: position - 1 }),
            )
          }
        >
          {t.sheetEarlier}
        </button>
        <button
          type="button"
          disabled={
            position >= query.sheets.length - 1 || !!query.sheetEditReason
          }
          onClick={() =>
            controller.run(() =>
              editor.editSheet({ action: "move", index: position + 1 }),
            )
          }
        >
          {t.sheetLater}
        </button>
        <button
          type="button"
          disabled={visible.length <= 1 || !!query.sheetEditReason}
          onClick={() =>
            controller.run(() =>
              editor.editSheet({ action: "visibility", state: "hidden" }),
            )
          }
        >
          {t.hideSheet}
        </button>
        <label>
          {t.hiddenSheet}
          <select
            value={target}
            disabled={!hidden.length || !!query.sheetEditReason}
            onChange={(event) => setChosen(event.currentTarget.value)}
          >
            {!hidden.length && <option value="">{t.choose}</option>}
            {hidden.map((sheet) => (
              <option key={sheet.id} value={sheet.id}>
                {sheet.name}
              </option>
            ))}
          </select>
        </label>
        <button
          type="button"
          disabled={!target || !!query.sheetEditReason}
          onClick={() =>
            controller.run(() =>
              editor.editSheet(
                { action: "visibility", state: "visible" },
                target,
              ),
            )
          }
        >
          {t.showSheet}
        </button>
      </fieldset>
      {query.sheetEditReason && <p>{query.sheetEditReason}</p>}
      <fieldset disabled={disabled || !!query.dimensions.readOnlyReason}>
        <legend>{t.dimensions}</legend>
        <label>
          <input
            type="checkbox"
            checked={series}
            onChange={(event) => setSeries(event.currentTarget.checked)}
          />
          {t.numericSeries}
        </label>
        {series && (
          <>
            <label>
              {t.seriesMode}
              <select
                value={seriesMode}
                onChange={(event) => {
                  const mode = event.currentTarget.value;
                  if (
                    mode === "linear" ||
                    mode === "growth" ||
                    mode === "date" ||
                    mode === "text" ||
                    mode === "auto"
                  )
                    setSeriesMode(mode);
                }}
              >
                <option value="linear">{t.linearTrend}</option>
                <option value="growth">{t.growthTrend}</option>
                <option value="date">{t.dateSeries}</option>
                <option value="text">{t.textSeries}</option>
                <option value="auto">{t.automaticSeries}</option>
              </select>
            </label>
            {seriesMode === "date" && (
              <>
                <label>
                  {t.seriesDateUnit}
                  <select
                    value={dateUnit}
                    onChange={(event) => {
                      const unit = event.currentTarget.value;
                      if (
                        unit === "day" ||
                        unit === "weekday" ||
                        unit === "month" ||
                        unit === "year"
                      )
                        setDateUnit(unit);
                    }}
                  >
                    <option value="day">{t.seriesDay}</option>
                    <option value="weekday">{t.seriesWeekday}</option>
                    <option value="month">{t.seriesMonth}</option>
                    <option value="year">{t.seriesYear}</option>
                  </select>
                </label>
                <label>
                  {t.seriesStep}
                  <input
                    type="number"
                    step={dateUnit === "day" ? "any" : "1"}
                    min={-2958465}
                    max={2958465}
                    value={dateStep}
                    onChange={(event) => setDateStep(event.currentTarget.value)}
                  />
                </label>
              </>
            )}
            <label>
              {t.seriesSource}
              <input
                value={source}
                maxLength={64}
                onChange={(event) =>
                  setSeed({
                    sheet: query.sheet,
                    range: event.currentTarget.value,
                  })
                }
              />
            </label>
            <button
              type="button"
              onClick={() =>
                setSeed({
                  sheet: query.sheet,
                  range: editor.currentState.selection.address,
                })
              }
            >
              {t.seriesUseSelection}
            </button>
          </>
        )}
        {(
          [
            ["down", t.fillDown],
            ["up", t.fillUp],
            ["right", t.fillRight],
            ["left", t.fillLeft],
          ] as const
        ).map(([direction, label]) => (
          <button
            type="button"
            key={direction}
            disabled={
              series &&
              (!source.trim() || (seriesMode === "date" && !dateStep.trim()))
            }
            onClick={() =>
              controller.run(() =>
                editor.editSheet(
                  series
                    ? {
                        action: "series",
                        ...(seriesMode === "date"
                          ? ({
                              mode: "date",
                              unit: dateUnit,
                              step: Number(dateStep),
                            } as const)
                          : { mode: seriesMode }),
                        source,
                        direction,
                        range: editor.currentState.selection.address,
                      }
                    : {
                        action: "fill",
                        direction,
                        range: editor.currentState.selection.address,
                      },
                ),
              )
            }
          >
            {label}
          </button>
        ))}
        {(
          [
            [{ action: "insertCells", direction: "down" }, t.insertCellsDown],
            [{ action: "insertCells", direction: "right" }, t.insertCellsRight],
            [{ action: "deleteCells", direction: "up" }, t.deleteCellsUp],
            [{ action: "deleteCells", direction: "left" }, t.deleteCellsLeft],
          ] as const
        ).map(([change, label]) => (
          <button
            key={label}
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editSheet({
                  ...change,
                  range: editor.currentState.selection.address,
                }),
              )
            }
          >
            {label}
          </button>
        ))}
        {(
          [
            ["insertRows", t.insertRows],
            ["deleteRows", t.deleteRows],
            ["insertColumns", t.insertColumns],
            ["deleteColumns", t.deleteColumns],
          ] as const
        ).map(([action, label]) => (
          <button
            type="button"
            key={action}
            onClick={() =>
              controller.run(() => {
                const range = editor.currentState.selection.range,
                  rows = action.endsWith("Rows");
                return editor.editSheet({
                  action,
                  first: rows ? range.top : range.left,
                  count: rows
                    ? range.bottom - range.top + 1
                    : range.right - range.left + 1,
                });
              })
            }
          >
            {label}
          </button>
        ))}
        <button
          type="button"
          onClick={() => controller.run(() => editor.autoFit("rows"))}
        >
          {t.autoFitRows}
        </button>
        <button
          type="button"
          onClick={() => controller.run(() => editor.autoFit("columns"))}
        >
          {t.autoFitColumns}
        </button>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              const range = editor.currentState.selection.range;
              await editor.editSheet({
                action: "rowHeight",
                first: range.top,
                last: range.bottom,
                size: Number(height),
              });
              setHeight("");
            });
          }}
        >
          <label>
            {t.rowHeight}
            <input
              type="number"
              min={0}
              max={409.5}
              step="any"
              required
              value={height}
              placeholder={
                query.dimensions.rowHeight === null
                  ? t.mixed
                  : String(query.dimensions.rowHeight)
              }
              onChange={(event) => setHeight(event.currentTarget.value)}
            />
          </label>
          <button type="submit" disabled={!height}>
            {t.setRowHeight}
          </button>
        </form>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              const range = editor.currentState.selection.range;
              await editor.editSheet({
                action: "columnWidth",
                first: range.left,
                last: range.right,
                size: Number(width),
              });
              setWidth("");
            });
          }}
        >
          <label>
            {t.columnWidth}
            <input
              type="number"
              min={0}
              max={255}
              step="any"
              required
              value={width}
              placeholder={
                query.dimensions.columnWidth === null
                  ? t.mixed
                  : String(query.dimensions.columnWidth)
              }
              onChange={(event) => setWidth(event.currentTarget.value)}
            />
          </label>
          <button type="submit" disabled={!width}>
            {t.setColumnWidth}
          </button>
        </form>
        {query.dimensions.readOnlyReason && (
          <p>{query.dimensions.readOnlyReason}</p>
        )}
      </fieldset>
    </nav>
  );
}

export function XlsxView({ controller, state, editor, disabled }: SheetProps) {
  const t = messages(state.locale),
    query = editor.currentState;
  return (
    <fieldset disabled={disabled || !!query.view.readOnlyReason}>
      <legend>{t.worksheetView}</legend>
      {(["gridLines", "headings", "rtl", "formulas"] as const).map((key) => (
        <label key={key} onMouseDown={(event) => event.preventDefault()}>
          <input
            type="checkbox"
            checked={query.view[key]}
            onChange={(event) =>
              controller.run(() =>
                editor.editSheet({
                  action: "view",
                  gridLines: query.view.gridLines,
                  headings: query.view.headings,
                  rtl: query.view.rtl,
                  formulas: query.view.formulas,
                  [key]: event.target.checked,
                }),
              )
            }
          />
          {t[key]}
        </label>
      ))}
      {query.view.readOnlyReason && <p>{query.view.readOnlyReason}</p>}
    </fieldset>
  );
}

export function XlsxFrozen({
  controller,
  state,
  editor,
  disabled,
}: SheetProps) {
  const t = messages(state.locale),
    query = editor.currentState;
  return (
    <fieldset disabled={disabled || !!query.frozen.readOnlyReason}>
      <legend>{t.freezePanes}</legend>
      <button
        type="button"
        disabled={
          query.selection.range.top === 1 && query.selection.range.left === 1
        }
        onClick={() =>
          controller.run(() =>
            editor.editSheet({
              action: "freeze",
              rows: query.selection.range.top - 1,
              columns: query.selection.range.left - 1,
            }),
          )
        }
      >
        {t.freezeSelection}
      </button>
      <button
        type="button"
        onClick={() =>
          controller.run(() =>
            editor.editSheet({ action: "freeze", rows: 1, columns: 0 }),
          )
        }
      >
        {t.freezeTopRow}
      </button>
      <button
        type="button"
        onClick={() =>
          controller.run(() =>
            editor.editSheet({ action: "freeze", rows: 0, columns: 1 }),
          )
        }
      >
        {t.freezeFirstColumn}
      </button>
      <button
        type="button"
        disabled={query.frozen.rows === 0 && query.frozen.columns === 0}
        onClick={() =>
          controller.run(() =>
            editor.editSheet({ action: "freeze", rows: 0, columns: 0 }),
          )
        }
      >
        {t.unfreezePanes}
      </button>
      {query.frozen.readOnlyReason && <p>{query.frozen.readOnlyReason}</p>}
    </fieldset>
  );
}
