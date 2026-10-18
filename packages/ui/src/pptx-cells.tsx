import { useState } from "react";
import type { PresentationEditor } from "@open-document/web/presentation-editor";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PptxTableSize({
  controller,
  state,
  editor,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
}) {
  const t = messages(state.locale),
    table = editor.query.table!;
  const [values, setValues] = useState({
    rowHeight: String(table.rowHeight ?? ""),
    columnWidth: String(table.columnWidth ?? ""),
  });
  return (
    <>
      {(
        [
          ["tableRowHeight", "rowHeight", t.tableRowHeight],
          ["tableColumnWidth", "columnWidth", t.tableColumnWidth],
        ] as const
      ).map(([action, key, label]) => (
        <form
          key={key}
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(() =>
              editor.editObjects({ action, value: Number(values[key]) }),
            );
          }}
        >
          <label>
            {label}
            <input
              type="number"
              min={0.1}
              max={14400}
              step="any"
              required
              value={values[key]}
              placeholder={table[key] === null ? t.mixed : undefined}
              onChange={(event) =>
                setValues({ ...values, [key]: event.currentTarget.value })
              }
            />
          </label>
          <button
            type="submit"
            disabled={
              !Number.isFinite(Number(values[key])) ||
              Number(values[key]) < 0.1 ||
              Number(values[key]) > 14400
            }
          >
            {t.apply} {label}
          </button>
        </form>
      ))}
    </>
  );
}

export function PptxSplitCell({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    table = editor.query.table!;
  const [rows, setRows] = useState("2"),
    [columns, setColumns] = useState("2");
  const valid =
    Number.isInteger(Number(rows)) &&
    Number(rows) >= 1 &&
    Number(rows) <= 1000 &&
    Number.isInteger(Number(columns)) &&
    Number(columns) >= 1 &&
    Number(columns) <= 63 &&
    Number(rows) * Number(columns) <= 4096;
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editObjects({
            action: "splitTableCell",
            rows: Number(rows),
            columns: Number(columns),
          }),
        );
      }}
    >
      <fieldset disabled={disabled || !!table.splitReason}>
        <legend>{t.splitCell}</legend>
        <label>
          {t.splitCellRows}
          <input
            type="number"
            min={1}
            max={1000}
            step={1}
            required
            value={rows}
            onChange={(event) => setRows(event.currentTarget.value)}
          />
        </label>
        <label>
          {t.splitCellColumns}
          <input
            type="number"
            min={1}
            max={63}
            step={1}
            required
            value={columns}
            onChange={(event) => setColumns(event.currentTarget.value)}
          />
        </label>
        <button type="submit" disabled={!valid}>
          {t.splitCell}
        </button>
        {table.splitReason && <p>{table.splitReason}</p>}
      </fieldset>
    </form>
  );
}

export function PptxCells({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    table = editor.query.table!,
    format = table.format;
  const [fill, setFill] = useState(format.fill || "ffffff");
  const [border, setBorder] = useState(format.borderColor || "000000");
  const [width, setWidth] = useState(String(format.borderWidth || 1));
  const [margins, setMargins] = useState({
    left: String(format.left ?? ""),
    top: String(format.top ?? ""),
    right: String(format.right ?? ""),
    bottom: String(format.bottom ?? ""),
  });
  return (
    <fieldset
      disabled={disabled || !!format.reason || !!editor.query.readOnlyReason}
    >
      <legend>{t.cellFormat}</legend>
      <p>
        {editor.query.selection.mode === "object"
          ? t.wholeTable
          : `${t.cellRange}: ${table.firstRow + 1}, ${table.firstColumn + 1} – ${table.lastRow + 1}, ${table.lastColumn + 1}`}
      </p>
      {Object.values(format).some((value) => value === null) && (
        <p>{t.mixed}</p>
      )}
      <label>
        {t.cellFill}
        <input
          type="color"
          value={`#${fill}`}
          onChange={(event) => setFill(event.currentTarget.value.slice(1))}
        />
      </label>
      <button
        type="button"
        onClick={() =>
          controller.run(() =>
            editor.editObjects({ action: "fill", color: fill }),
          )
        }
      >
        {t.apply} {t.cellFill}
      </button>
      <button
        type="button"
        onClick={() =>
          controller.run(() =>
            editor.editObjects({ action: "fill", color: null }),
          )
        }
      >
        {t.noCellFill}
      </button>
      <fieldset disabled={!!format.borderReason}>
        <legend>{t.cellBorders}</legend>
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(() =>
              editor.editObjects({
                action: "stroke",
                color: border,
                width: Number(width),
              }),
            );
          }}
        >
          <label>
            {t.cellBorders}
            <input
              type="color"
              value={`#${border}`}
              onChange={(event) =>
                setBorder(event.currentTarget.value.slice(1))
              }
            />
          </label>
          <label>
            {t.shapeLineWidth}
            <input
              type="number"
              min={0.1}
              max={1000}
              step="any"
              required
              value={width}
              onChange={(event) => setWidth(event.currentTarget.value)}
            />
          </label>
          <button type="submit">
            {t.apply} {t.cellBorders}
          </button>
          <button
            type="button"
            onClick={() =>
              controller.run(() =>
                editor.editObjects({ action: "stroke", color: null, width: 1 }),
              )
            }
          >
            {t.noTableBorder}
          </button>
        </form>
        {format.borderReason && <p>{format.borderReason}</p>}
      </fieldset>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editObjects({
              action: "textInsets",
              left: Number(margins.left),
              top: Number(margins.top),
              right: Number(margins.right),
              bottom: Number(margins.bottom),
            }),
          );
        }}
      >
        <fieldset>
          <legend>{t.cellMargins}</legend>
          {(
            [
              ["left", t.textInsetLeft],
              ["top", t.textInsetTop],
              ["right", t.textInsetRight],
              ["bottom", t.textInsetBottom],
            ] as const
          ).map(([key, label]) => (
            <label key={key}>
              {label}
              <input
                type="number"
                min={0}
                max={14400}
                step="any"
                required
                placeholder={t.mixed}
                value={margins[key]}
                onChange={(event) =>
                  setMargins({ ...margins, [key]: event.currentTarget.value })
                }
              />
            </label>
          ))}
          <button type="submit">
            {t.apply} {t.cellMargins}
          </button>
        </fieldset>
      </form>
      <label>
        {t.cellVerticalAlign}
        <select
          aria-label={t.cellVerticalAlign}
          value={format.anchor ?? ""}
          onChange={(event) => {
            const anchor = event.currentTarget.value;
            if (anchor === "t" || anchor === "ctr" || anchor === "b")
              controller.run(() =>
                editor.editObjects({ action: "textAnchor", anchor }),
              );
          }}
        >
          <option value="" disabled>
            {t.mixed}
          </option>
          <option value="t">{t.alignTop}</option>
          <option value="ctr">{t.alignMiddle}</option>
          <option value="b">{t.alignBottom}</option>
        </select>
      </label>
      {format.reason && <p>{format.reason}</p>}
    </fieldset>
  );
}
