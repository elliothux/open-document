import { useEffect, useState } from "react";
import type { XlsxTable } from "@open-document/web/xlsx";
import type { PanelProps } from "./panels.js";
import { messages } from "./messages.js";

export function XlsxTablesPanel(props: PanelProps) {
  const [choice, setChoice] = useState(0),
    [newName, setNewName] = useState("");
  if (props.file.format !== "xlsx") return null;
  const tables = props.file.editor.currentState.tables;
  const t = messages(props.state.locale),
    table = tables.find((table) => table.id === choice) ?? tables[0];
  const editor = props.file.editor;
  return (
    <fieldset disabled={props.disabled}>
      <legend>{t.structuredTables}</legend>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          props.controller.run(() =>
            editor.editSheet({
              action: "createTable",
              range: editor.currentState.selection.address,
              name: newName,
            }),
          );
        }}
      >
        <p>{t.tableCreateHelp}</p>
        <p>{editor.currentState.selection.address}</p>
        <label>
          {t.tableCreateName}
          <input
            value={newName}
            required
            maxLength={255}
            onChange={(event) => setNewName(event.currentTarget.value)}
          />
        </label>
        <button type="submit" disabled={!newName}>
          {t.createStructuredTable}
        </button>
      </form>
      {table && (
        <>
          <label>
            {t.tableChoice}
            <select
              aria-label={t.tableChoice}
              value={table.id}
              onChange={(event) => setChoice(Number(event.currentTarget.value))}
            >
              {tables.map((table) => (
                <option key={table.id} value={table.id}>
                  {table.name} ({table.range})
                </option>
              ))}
            </select>
          </label>
          <p>{t.tableNamesHelp}</p>
          <TableNames key={table.id} {...props} table={table} />
        </>
      )}
    </fieldset>
  );
}

function TableNames({ table, ...props }: PanelProps & { table: XlsxTable }) {
  const [name, setName] = useState(table.name),
    [column, setColumn] = useState(table.columns[0]!.id),
    [range, setRange] = useState(table.range);
  const item =
    table.columns.find((item) => item.id === column) ?? table.columns[0]!;
  const [heading, setHeading] = useState(item.name);
  useEffect(() => setName(table.name), [table.name]);
  useEffect(() => setRange(table.range), [table.range]);
  useEffect(() => setHeading(item.name), [item.name, item.id]);
  if (props.file.format !== "xlsx") return null;
  const editor = props.file.editor,
    t = messages(props.state.locale);
  return (
    <fieldset disabled={!!table.readOnlyReason}>
      <legend>{table.name}</legend>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          props.controller.run(() =>
            editor.editSheet({ action: "resizeTable", id: table.id, range }),
          );
        }}
      >
        <p>{t.tableResizeHelp}</p>
        <label>
          {t.tableRange}
          <input
            value={range}
            required
            maxLength={32}
            onChange={(event) => setRange(event.currentTarget.value)}
          />
        </label>
        <button type="submit" disabled={range === table.range}>
          {t.resizeStructuredTable}
        </button>
      </form>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          props.controller.run(() =>
            editor.editSheet({ action: "renameTable", id: table.id, name }),
          );
        }}
      >
        <label>
          {t.tableName}
          <input
            value={name}
            maxLength={255}
            required
            onChange={(event) => setName(event.currentTarget.value)}
          />
        </label>
        <button type="submit" disabled={name === table.name}>
          {t.renameTable}
        </button>
      </form>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          props.controller.run(() =>
            editor.editSheet({
              action: "renameTableColumn",
              id: table.id,
              column: item.id,
              name: heading,
            }),
          );
        }}
      >
        <label>
          {t.structuredTableColumn}
          <select
            aria-label={t.structuredTableColumn}
            value={item.id}
            onChange={(event) => setColumn(Number(event.currentTarget.value))}
          >
            {table.columns.map((column) => (
              <option key={column.id} value={column.id}>
                {column.name}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t.tableColumnName}
          <input
            value={heading}
            maxLength={255}
            required
            disabled={!table.headerRow}
            onChange={(event) => setHeading(event.currentTarget.value)}
          />
        </label>
        <button
          type="submit"
          disabled={!table.headerRow || heading === item.name}
        >
          {t.renameTableColumn}
        </button>
      </form>
      {table.readOnlyReason && <p>{table.readOnlyReason}</p>}
    </fieldset>
  );
}
