import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type { DocxTableEdit } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

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
  const rowCount = Number(rows),
    columnCount = Number(columns);
  const snapshot = editor.getSnapshot();
  const paragraph = snapshot.data.selection?.focus.paragraph;
  const body = editor.layout.semantics[snapshot.page]?.lines.some(
    (line) => line.paragraph === paragraph && line.container === 0,
  );
  const cell = editor.layout.semantics[snapshot.page]?.lines.some(
    (line) => line.paragraph === paragraph && line.container > 0,
  );
  const size = snapshot.data.formatting?.table;
  return (
    <section aria-label={t.insertTable}>
      <h3>{t.insertTable}</h3>
      {size && (
        <TableSizes
          key={`${snapshot.documentId}:${size.id}:${size.row}:${snapshot.revision}`}
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled || !!snapshot.data.formatting?.reason}
          width={size.width}
          height={size.rowHeight}
          columns={size.columns}
          maxWidth={size.maxWidth}
          maxHeight={size.maxRowHeight}
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
      <fieldset disabled={disabled || !cell}>
        <legend>
          {t.tableRows} / {t.tableColumns}
        </legend>
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
              rows: Number(mergeRows),
              columns: Number(mergeColumns),
            }),
          );
        }}
      >
        <fieldset disabled={disabled || !cell}>
          <legend>{t.mergeCells}</legend>
          <label>
            {t.mergeRows}
            <input
              type="number"
              min={1}
              max={1000}
              required
              value={mergeRows}
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
              value={mergeColumns}
              onChange={(event) => setMergeColumns(event.currentTarget.value)}
            />
          </label>
          <button
            type="submit"
            disabled={
              Number(mergeRows) * Number(mergeColumns) <= 1 ||
              Number(mergeRows) * Number(mergeColumns) > 4096
            }
          >
            {t.mergeCells}
          </button>
        </fieldset>
      </form>
    </section>
  );
}

function TableSizes({
  controller,
  state,
  editor,
  disabled,
  width,
  height,
  columns,
  maxWidth,
  maxHeight,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
  width: number;
  height: number;
  columns: number;
  maxWidth: number;
  maxHeight: number;
}) {
  const t = messages(state.locale);
  const [tableWidth, setWidth] = useState(String(width)),
    [rowHeight, setHeight] = useState(String(height));
  return (
    <fieldset disabled={disabled}>
      <legend>{t.tableSize}</legend>
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
            label: t.rowHeightMinimum,
            value: rowHeight,
            set: setHeight,
            min: 0,
            max: maxHeight,
          },
        ] as const
      ).map((field) => (
        <form
          key={field.action}
          onSubmit={(event) => {
            event.preventDefault();
            if (field.value !== "")
              controller.run(() =>
                editor.editTable({
                  action: field.action,
                  value: Number(field.value),
                }),
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
      ))}
    </fieldset>
  );
}
