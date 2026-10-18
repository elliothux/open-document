import { useEffect, useState } from "react";
import type {
  XlsxTable,
  XlsxTableTotal,
  XlsxTableTotalFunction,
} from "@open-document/web/xlsx";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { PanelProps } from "./panels.js";
import { messages } from "./messages.js";
import { XlsxFilter } from "./xlsx-filter.js";
import { XlsxTableStyleForm } from "./xlsx-table-style.js";
import { XlsxTableStyleDefinitions } from "./xlsx-table-style-definition.js";

export function selectedXlsxTable(query: SpreadsheetEditor["currentState"]) {
  return query.tables
    .map((table) => {
      const points = table.range.split(":").map((text) => {
        const match = /^([A-Z]+)([0-9]+)$/.exec(text)!;
        return {
          row: Number(match[2]),
          column: Array.from(match[1]!).reduce(
            (column, letter) => column * 26 + letter.charCodeAt(0) - 64,
            0,
          ),
        };
      });
      const first = points[0]!,
        last = points[1] ?? first;
      return {
        table,
        range: {
          top: first.row,
          bottom: last.row,
          left: first.column,
          right: last.column,
        },
      };
    })
    .find(
      ({ range }) =>
        range.top <= query.selection.range.top &&
        range.bottom >= query.selection.range.bottom &&
        range.left <= query.selection.range.left &&
        range.right >= query.selection.range.right,
    );
}

const totalFunctions: XlsxTableTotalFunction[] = [
  "sum",
  "average",
  "count",
  "countNums",
  "min",
  "max",
  "stdDev",
  "var",
];

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
      <XlsxTableStyleDefinitions
        key={props.state.document?.documentId}
        {...props}
      />
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
          <XlsxTableStyleForm
            key={`style:${table.id}`}
            {...props}
            table={table}
          />
          <XlsxFilter
            key={`filter:${table.id}`}
            editor={editor}
            controller={props.controller}
            state={props.state}
            disabled={props.disabled}
            table={table}
          />
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
  const [heading, setHeading] = useState(item.name),
    [formula, setFormula] = useState(item.formula ?? "");
  const [totalKind, setTotalKind] = useState("none"),
    [totalText, setTotalText] = useState("");
  useEffect(() => {
    setTotalKind(
      item.totalFormula !== null
        ? "formula"
        : item.totalLabel !== null
          ? "label"
          : item.totalFunction === null
            ? "none"
            : item.totalFunction,
    );
    setTotalText(item.totalFormula ?? item.totalLabel ?? "");
  }, [item.id, item.totalFormula, item.totalLabel, item.totalFunction]);
  useEffect(() => setName(table.name), [table.name]);
  useEffect(() => setRange(table.range), [table.range]);
  useEffect(() => setHeading(item.name), [item.name, item.id]);
  useEffect(() => setFormula(item.formula ?? ""), [item.formula, item.id]);
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
      <form
        onSubmit={(event) => {
          event.preventDefault();
          props.controller.run(() =>
            editor.editSheet({
              action: "tableColumnFormula",
              id: table.id,
              column: item.id,
              formula,
            }),
          );
        }}
      >
        <p>{t.tableFormulaHelp}</p>
        <label>
          {t.tableColumnFormula}
          <input
            value={formula}
            required
            maxLength={8192}
            onChange={(event) => setFormula(event.currentTarget.value)}
          />
        </label>
        <button type="submit" disabled={!formula.trim()}>
          {t.applyTableFormula}
        </button>
        <button
          type="button"
          disabled={item.formula === null}
          onClick={() =>
            props.controller.run(() =>
              editor.editSheet({
                action: "tableColumnFormula",
                id: table.id,
                column: item.id,
                formula: null,
              }),
            )
          }
        >
          {t.removeTableFormula}
        </button>
      </form>
      <label>
        <input
          type="checkbox"
          checked={table.totalRow}
          onChange={(event) => {
            const visible = event.currentTarget.checked;
            props.controller.run(() =>
              editor.editSheet({
                action: "tableTotals",
                id: table.id,
                visible,
              }),
            );
          }}
        />
        {t.tableTotalsRow}
      </label>
      <p>{t.tableTotalsHelp}</p>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          const aggregate = totalFunctions.find((kind) => kind === totalKind);
          const total: XlsxTableTotal | null =
            totalKind === "none"
              ? { kind: "none" }
              : totalKind === "label"
                ? { kind: "label", text: totalText }
                : totalKind === "formula"
                  ? { kind: "formula", formula: totalText }
                  : aggregate
                    ? { kind: "aggregate", function: aggregate }
                    : null;
          if (total)
            props.controller.run(() =>
              editor.editSheet({
                action: "tableTotal",
                id: table.id,
                column: item.id,
                total,
              }),
            );
        }}
      >
        <fieldset disabled={!table.totalRow}>
          <legend>{t.tableColumnTotal}</legend>
          <label>
            {t.tableTotalKind}
            <select
              aria-label={t.tableTotalKind}
              value={totalKind}
              onChange={(event) => setTotalKind(event.currentTarget.value)}
            >
              <option value="none">{t.tableTotalNone}</option>
              <option value="label">{t.tableTotalLabel}</option>
              <option value="formula">{t.tableTotalFormula}</option>
              {totalFunctions.map((kind) => (
                <option key={kind} value={kind}>
                  {t[`tableTotal_${kind}`]}
                </option>
              ))}
              {!["none", "label", "formula", ...totalFunctions].includes(
                totalKind,
              ) && (
                <option value={totalKind} disabled>
                  {totalKind} ({t.tableTotalUnsupported})
                </option>
              )}
            </select>
          </label>
          {(totalKind === "label" || totalKind === "formula") && (
            <label>
              {t.tableTotalContent}
              <input
                value={totalText}
                required={totalKind === "formula"}
                maxLength={totalKind === "formula" ? 8192 : 32767}
                onChange={(event) => setTotalText(event.currentTarget.value)}
              />
            </label>
          )}
          <button
            type="submit"
            disabled={
              !["none", "label", "formula", ...totalFunctions].includes(
                totalKind,
              )
            }
          >
            {t.applyTableTotal}
          </button>
        </fieldset>
      </form>
      {table.readOnlyReason && <p>{table.readOnlyReason}</p>}
    </fieldset>
  );
}
