import { useState } from "react";
import type { DocumentEditor } from "@open-document/web/editor";
import type {
  DocxTableEdit,
  DocxCellMargins,
} from "@open-document/web/foundation";
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
        <TableProperties
          key={`${snapshot.documentId}:${size.id}:${paragraph}:${snapshot.revision}`}
          controller={controller}
          state={state}
          editor={editor}
          disabled={disabled || !!snapshot.data.formatting?.reason}
          width={size.width}
          height={size.rowHeight}
          columns={size.columns}
          maxWidth={size.maxWidth}
          maxHeight={size.maxRowHeight}
          fill={size.cellFill}
          verticalAlign={size.cellVerticalAlign}
          margins={size.cellMargins}
          tableMargins={size.tableMargins}
          align={size.align}
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

function TableProperties({
  controller,
  state,
  editor,
  disabled,
  width,
  height,
  columns,
  maxWidth,
  maxHeight,
  fill,
  verticalAlign,
  margins,
  tableMargins,
  align,
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
  fill: string | null;
  verticalAlign: "top" | "center" | "bottom";
  margins: DocxCellMargins;
  tableMargins: DocxCellMargins;
  align: "left" | "center" | "right";
}) {
  const t = messages(state.locale);
  const [tableWidth, setWidth] = useState(String(width)),
    [rowHeight, setHeight] = useState(String(height)),
    [cellFill, setFill] = useState(`#${fill ?? "ffffff"}`);
  return (
    <fieldset disabled={disabled}>
      <legend>{t.tableProperties}</legend>
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
        <MarginFields
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

function MarginFields({
  controller,
  state,
  editor,
  action,
  value,
  label,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  action: "cellMargins" | "tableMargins";
  value: DocxCellMargins;
  label: string;
}) {
  const t = messages(state.locale);
  const [draft, setDraft] = useState({
    top: String(value.top),
    right: String(value.right),
    bottom: String(value.bottom),
    left: String(value.left),
  });
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editTable({
            action,
            value: {
              top: Number(draft.top),
              right: Number(draft.right),
              bottom: Number(draft.bottom),
              left: Number(draft.left),
            },
          }),
        );
      }}
    >
      <fieldset>
        <legend>{label}</legend>
        {(
          [
            ["top", t.pageTop],
            ["right", t.pageRight],
            ["bottom", t.pageBottom],
            ["left", t.pageLeft],
          ] as const
        ).map(([side, label]) => (
          <label key={side}>
            {label}
            <input
              type="number"
              min={0}
              max={14400}
              step={0.05}
              required
              value={draft[side]}
              onChange={(event) =>
                setDraft({ ...draft, [side]: event.currentTarget.value })
              }
            />
          </label>
        ))}
        <button type="submit" aria-label={`${t.apply} ${label}`}>
          {t.apply}
        </button>
        <button
          type="button"
          onMouseDown={(event) => event.preventDefault()}
          onClick={() =>
            controller.run(() => editor.editTable({ action, value: null }))
          }
        >
          {action === "cellMargins"
            ? t.resetCellMargins
            : t.inheritStyleProperty}
        </button>
      </fieldset>
    </form>
  );
}
