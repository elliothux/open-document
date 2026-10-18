import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  DocxTableEdit,
  DocxCellMargins,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { DocxMargins } from "./docx-margins.js";
import { DocxBorders } from "./docx-borders.js";
import { DocxCellSelection } from "./docx-cell-selection.js";

export function DocxTables({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const [rows, setRows] = useState("2");
  const [columns, setColumns] = useState("2");
  const [mergeRows, setMergeRows] = useState("1");
  const [mergeColumns, setMergeColumns] = useState("2");
  const [splitRows, setSplitRows] = useState("2");
  const [splitColumns, setSplitColumns] = useState("2");
  const rowCount = Number(rows),
    columnCount = Number(columns);
  const snapshot = editor.getSnapshot();
  const paragraph = snapshot.data.selection?.focus.paragraph;
  const protectedRange =
    !snapshot.data.formatting || !!snapshot.data.formatting.reason;
  const body =
    !protectedRange &&
    editor.layout.semantics[snapshot.page]?.lines.some(
      (line) => line.paragraph === paragraph && line.container === 0,
    );
  const cell =
    editor.layout.semantics[snapshot.page]?.lines.some(
      (line) => line.paragraph === paragraph && line.container > 0,
    ) &&
    !protectedRange &&
    !snapshot.data.formatting?.cellSelection.value;
  const size = snapshot.data.formatting?.table;
  const selected = snapshot.data.formatting?.cellSelection.value;
  const mergeRowCount = selected
      ? selected.bottom - selected.top
      : Number(mergeRows),
    mergeColumnCount = selected
      ? selected.right - selected.left
      : Number(mergeColumns);
  return (
    <section aria-label={t.insertTable}>
      <h3>{t.insertTable}</h3>
      {selected && (
        <DocxCellSelection
          key={`${snapshot.documentId}:${snapshot.revision}:${JSON.stringify(snapshot.data.selection)}`}
          controller={controller}
          state={state}
          editor={editor}
          selected={selected}
          disabled={disabled}
        />
      )}
      {size && (
        <fieldset disabled={disabled || !!snapshot.data.formatting?.reason}>
          <legend>{t.tableAutoFit}</legend>
          {size.autoFit && <p>{t.tableAutomaticWidths}</p>}
          {(
            [
              ["content", t.tableFitContent],
              ["page", t.tableFitPage],
              ["fixed", t.tableFitFixed],
            ] as const
          ).map(([mode, label]) => (
            <button
              type="button"
              key={mode}
              onClick={() =>
                controller.run(() =>
                  editor.editTable({ action: "autoFit", mode }),
                )
              }
            >
              {label}
            </button>
          ))}
        </fieldset>
      )}
      {size && (
        <DocxBorders
          key={`borders:${snapshot.documentId}:${size.id}:${paragraph}:${snapshot.revision}`}
          controller={controller}
          state={state}
          editor={editor}
          cell={size.cellBorders}
          table={size.tableBorders}
          disabled={disabled || !!snapshot.data.formatting?.reason}
        />
      )}
      {size && (
        <TableProperties
          key={`${snapshot.documentId}:${size.id}:${paragraph}:${snapshot.revision}`}
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled || !!snapshot.data.formatting?.reason}
          width={size.width}
          autoFit={size.autoFit}
          height={size.rowHeight}
          heightRule={size.rowHeightRule}
          columns={size.columns}
          column={size.column}
          columnWidths={size.columnWidths}
          maxWidth={size.maxWidth}
          maxHeight={size.maxRowHeight}
          fill={size.cellFill}
          verticalAlign={size.cellVerticalAlign}
          margins={size.cellMargins}
          tableMargins={size.tableMargins}
          align={size.align}
          rows={size.rows}
          headerRows={size.headerRows}
          rowSplit={size.rowSplit}
        />
      )}
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() => editor.insertTable(rowCount, columnCount));
        }}
      >
        <fieldset disabled={disabled || !body}>
          <label>
            {t.tableRows}
            <input
              type="number"
              min={1}
              max={1000}
              required
              value={rows}
              onChange={(event) => setRows(event.currentTarget.value)}
            />
          </label>
          <label>
            {t.tableColumns}
            <input
              type="number"
              min={1}
              max={63}
              required
              value={columns}
              onChange={(event) => setColumns(event.currentTarget.value)}
            />
          </label>
          <button
            type="submit"
            disabled={
              !Number.isInteger(rowCount) ||
              !Number.isInteger(columnCount) ||
              rowCount * columnCount > 4096
            }
          >
            {t.insertTable}
          </button>
        </fieldset>
      </form>
      <fieldset disabled={disabled || (!cell && !selected)}>
        <legend>
          {t.tableRows} / {t.tableColumns}
        </legend>
        {([false, true] as const).map((cut) => (
          <button
            key={String(cut)}
            type="button"
            onMouseDown={(event) => event.preventDefault()}
            onClick={() => controller.run(() => editor.copy(cut, "cells"))}
          >
            {cut ? t.cutCells : t.copyCells}
          </button>
        ))}
        <button
          type="button"
          onMouseDown={(event) => event.preventDefault()}
          onClick={() =>
            controller.run(async () => {
              const before = editor.getSnapshot();
              const text = await navigator.clipboard.readText();
              await editor.whenIdle();
              const current = editor.getSnapshot();
              if (
                current.busy !== 0 ||
                current.dragging ||
                current.documentId !== before.documentId ||
                current.revision !== before.revision ||
                JSON.stringify(current.data.selection) !==
                  JSON.stringify(before.data.selection)
              )
                throw new Error("Selection changed during clipboard read");
              return editor.editTable({ action: "pasteCells", text });
            })
          }
        >
          {t.pasteCells}
        </button>
        {(
          [
            "rowBefore",
            "rowAfter",
            "deleteRow",
            "columnBefore",
            "columnAfter",
            "deleteColumn",
            "unmerge",
            "splitTable",
          ] satisfies DocxTableEdit["action"][]
        ).map((change) => (
          <button
            key={change}
            type="button"
            disabled={!!selected && change === "splitTable"}
            onMouseDown={(event) => event.preventDefault()}
            onClick={() =>
              controller.run(() => editor.editTable({ action: change }))
            }
          >
            {t[change]}
          </button>
        ))}
      </fieldset>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editTable({
              action: "merge",
              rows: mergeRowCount,
              columns: mergeColumnCount,
            }),
          );
        }}
      >
        <fieldset disabled={disabled || (!cell && !selected)}>
          <legend>{t.mergeCells}</legend>
          <label>
            {t.mergeRows}
            <input
              type="number"
              min={1}
              max={1000}
              required
              value={selected ? mergeRowCount : mergeRows}
              readOnly={!!selected}
              onChange={(event) => setMergeRows(event.currentTarget.value)}
            />
          </label>
          <label>
            {t.mergeColumns}
            <input
              type="number"
              min={1}
              max={63}
              required
              value={selected ? mergeColumnCount : mergeColumns}
              readOnly={!!selected}
              onChange={(event) => setMergeColumns(event.currentTarget.value)}
            />
          </label>
          <button
            type="submit"
            disabled={
              mergeRowCount * mergeColumnCount <= 1 ||
              mergeRowCount * mergeColumnCount > 4096
            }
          >
            {t.mergeCells}
          </button>
        </fieldset>
      </form>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editTable({
              action: "splitCell",
              rows: Number(splitRows),
              columns: Number(splitColumns),
            }),
          );
        }}
      >
        <fieldset disabled={disabled || (!cell && !selected)}>
          <legend>{t.splitCell}</legend>
          <label>
            {t.splitCellRows}
            <input
              type="number"
              min={1}
              max={1000}
              required
              value={splitRows}
              onChange={(event) => setSplitRows(event.currentTarget.value)}
            />
          </label>
          <label>
            {t.splitCellColumns}
            <input
              type="number"
              min={1}
              max={63}
              required
              value={splitColumns}
              onChange={(event) => setSplitColumns(event.currentTarget.value)}
            />
          </label>
          <button
            type="submit"
            disabled={
              Number(splitRows) * Number(splitColumns) <= 1 ||
              Number(splitRows) * Number(splitColumns) > 4096
            }
          >
            {t.splitCell}
          </button>
        </fieldset>
      </form>
    </section>
  );
}

function TableProperties({
  controller,
  state,
  editor,
  disabled,
  autoFit,
  width,
  height,
  heightRule,
  columns,
  column,
  columnWidths,
  maxWidth,
  maxHeight,
  fill,
  verticalAlign,
  margins,
  tableMargins,
  align,
  rows,
  headerRows,
  rowSplit,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
  autoFit: boolean;
  width: number;
  height: number;
  heightRule: "atLeast" | "exact";
  columns: number;
  column: number;
  columnWidths: number[];
  maxWidth: number;
  maxHeight: number;
  fill: string | null;
  verticalAlign: "top" | "center" | "bottom";
  margins: DocxCellMargins;
  tableMargins: DocxCellMargins;
  align: "left" | "center" | "right";
  rows: number;
  headerRows: number;
  rowSplit: boolean;
}) {
  const t = messages(state.locale);
  const [tableWidth, setWidth] = useState(String(width)),
    [headers, setHeaders] = useState(String(headerRows)),
    [rowHeight, setHeight] = useState(String(height)),
    [cellFill, setFill] = useState(`#${fill ?? "ffffff"}`);
  const [rowRule, setRowRule] = useState(heightRule);
  const [columnIndex, setColumnIndex] = useState(column),
    [columnWidth, setColumnWidth] = useState(String(columnWidths[column]));
  const maximumColumnWidth = maxWidth - width + columnWidths[columnIndex]!;
  return (
    <fieldset disabled={disabled}>
      <legend>{t.tableProperties}</legend>
      <label>
        <input
          type="checkbox"
          checked={rowSplit}
          onChange={(event) => {
            const value = event.currentTarget.checked;
            controller.run(() =>
              editor.editTable({ action: "rowSplit", value }),
            );
          }}
        />
        {t.tableRowSplit}
      </label>
      {!autoFit && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(() =>
              editor.editTable({
                action: "columnWidth",
                column: columnIndex,
                value: Number(columnWidth),
              }),
            );
          }}
        >
          <label>
            {t.tableColumn}
            <select
              aria-label={t.tableColumn}
              value={columnIndex}
              onChange={(event) => {
                const index = Number(event.currentTarget.value);
                if (Number.isInteger(index) && index >= 0 && index < columns) {
                  setColumnIndex(index);
                  setColumnWidth(String(columnWidths[index]));
                }
              }}
            >
              {columnWidths.map((_, index) => (
                <option key={index} value={index}>
                  {index + 1}
                </option>
              ))}
            </select>
          </label>
          <label>
            {t.tableColumnWidth}
            <input
              type="number"
              min={12}
              max={maximumColumnWidth}
              step={0.05}
              required
              value={columnWidth}
              onChange={(event) => setColumnWidth(event.currentTarget.value)}
            />
          </label>
          <button type="submit" aria-label={`${t.apply} ${t.tableColumnWidth}`}>
            {t.apply}
          </button>
        </form>
      )}
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editTable({ action: "headerRows", value: Number(headers) }),
          );
        }}
      >
        <label>
          {t.tableHeaderRows}
          <input
            type="number"
            required
            min={0}
            max={Math.min(rows, 1000)}
            step={1}
            value={headers}
            onChange={(event) => setHeaders(event.currentTarget.value)}
          />
        </label>
        <button type="submit" aria-label={`${t.apply} ${t.tableHeaderRows}`}>
          {t.apply}
        </button>
      </form>
      <fieldset>
        <legend>{t.tableAlignment}</legend>
        {(
          [
            ["left", t.alignLeft],
            ["center", t.alignCenter],
            ["right", t.alignRight],
          ] as const
        ).map(([value, label]) => (
          <button
            key={value}
            type="button"
            aria-label={`${t.tableAlignment}: ${label}`}
            aria-pressed={align === value}
            onMouseDown={(event) => event.preventDefault()}
            onClick={() =>
              controller.run(() =>
                editor.editTable({ action: "tableAlign", value }),
              )
            }
          >
            {label}
          </button>
        ))}
      </fieldset>
      {(
        [
          ["tableMargins", tableMargins, t.tableMargins],
          ["cellMargins", margins, t.cellMargins],
        ] as const
      ).map(([action, value, label]) => (
        <DocxMargins
          key={action}
          controller={controller}
          state={state}
          editor={editor}
          action={action}
          value={value}
          label={label}
        />
      ))}
      <fieldset>
        <legend>{t.cellVerticalAlign}</legend>
        {(
          [
            ["top", t.alignTop],
            ["center", t.alignMiddle],
            ["bottom", t.alignBottom],
          ] as const
        ).map(([value, label]) => (
          <button
            key={value}
            type="button"
            aria-pressed={verticalAlign === value}
            onMouseDown={(event) => event.preventDefault()}
            onClick={() =>
              controller.run(() =>
                editor.editTable({ action: "cellVerticalAlign", value }),
              )
            }
          >
            {label}
          </button>
        ))}
      </fieldset>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.editTable({ action: "cellFill", value: cellFill.slice(1) }),
          );
        }}
      >
        <label>
          {t.cellFill}
          <input
            type="color"
            value={cellFill}
            onChange={(event) => setFill(event.currentTarget.value)}
          />
        </label>
        <button type="submit" aria-label={`${t.apply} ${t.cellFill}`}>
          {t.apply}
        </button>
        <button
          type="button"
          onMouseDown={(event) => event.preventDefault()}
          onClick={() =>
            controller.run(() =>
              editor.editTable({ action: "cellFill", value: null }),
            )
          }
        >
          {t.clearCellFill}
        </button>
      </form>
      <label>
        {t.rowHeightRule}
        <select
          aria-label={t.rowHeightRule}
          value={rowRule}
          onChange={(event) => {
            const value = event.currentTarget.value;
            if (value === "atLeast" || value === "exact") setRowRule(value);
          }}
        >
          <option value="atLeast">{t.rowHeightAtLeast}</option>
          <option value="exact">{t.rowHeightExact}</option>
        </select>
      </label>
      {(
        [
          {
            action: "tableWidth",
            label: t.tableWidth,
            value: tableWidth,
            set: setWidth,
            min: columns * 12,
            max: maxWidth,
          },
          {
            action: "rowHeight",
            label:
              rowRule === "exact" ? t.rowHeightExactValue : t.rowHeightMinimum,
            value: rowHeight,
            set: setHeight,
            min: 0,
            max: maxHeight,
          },
        ] as const
      ).map(
        (field) =>
          (!autoFit || field.action !== "tableWidth") && (
            <form
              key={field.action}
              onSubmit={(event) => {
                event.preventDefault();
                if (field.value !== "")
                  controller.run(() =>
                    editor.editTable(
                      field.action === "rowHeight"
                        ? {
                            action: "rowHeight",
                            value: Number(field.value),
                            rule: rowRule,
                          }
                        : { action: "tableWidth", value: Number(field.value) },
                    ),
                  );
              }}
            >
              <label>
                {field.label}
                <input
                  type="number"
                  required
                  step={0.05}
                  min={field.min}
                  max={field.max}
                  value={field.value}
                  onChange={(event) => field.set(event.currentTarget.value)}
                />
              </label>
              <button
                type="submit"
                aria-label={`${t.apply} ${field.label}`}
                disabled={
                  !field.value ||
                  Number(field.value) < field.min ||
                  Number(field.value) > field.max
                }
              >
                {t.apply}
              </button>
            </form>
          ),
      )}
    </fieldset>
  );
}
