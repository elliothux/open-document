import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type {
  XlsxFilterState,
  XlsxFilterColumn,
  XlsxFilterCondition,
  XlsxFilterOperator,
  XlsxTable,
} from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { XlsxRankFilterForm } from "./xlsx-rank-filter.js";
import { XlsxDateFilterForm } from "./xlsx-date-filter.js";
import { XlsxColorFilterForm } from "./xlsx-color-filter.js";
import { XlsxIconFilterForm } from "./xlsx-icon-filter.js";

function FilterColumn({
  column,
  apply,
  disabled,
  state,
}: {
  column: XlsxFilterState["catalog"][number];
  apply: (values: string[], blank: boolean, all: boolean) => void;
  disabled: boolean;
  state: UiSnapshot;
}) {
  const t = messages(state.locale);
  const [values, setValues] = useState(
    column.values.filter((v) => v.selected).map((v) => v.value),
  );
  const [blank, setBlank] = useState(column.blankSelected);
  const all = values.length === column.values.length && blank;
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        apply(values, blank, all);
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.filterValues}</legend>
        <label>
          <input
            type="checkbox"
            checked={all}
            onChange={(event) => {
              const checked = event.currentTarget.checked;
              setValues(checked ? column.values.map((v) => v.value) : []);
              setBlank(checked);
            }}
          />
          {t.filterAll}
        </label>
        <div className="od-filter-values">
          {column.values.map((choice) => (
            <label key={choice.value}>
              <input
                type="checkbox"
                checked={values.includes(choice.value)}
                onChange={(event) => {
                  const checked = event.currentTarget.checked;
                  setValues((values) =>
                    checked
                      ? [...values, choice.value]
                      : values.filter((v) => v !== choice.value),
                  );
                }}
              />
              {`${choice.value} (${choice.count})`}
            </label>
          ))}
          <label>
            <input
              type="checkbox"
              checked={blank}
              onChange={(e) => setBlank(e.currentTarget.checked)}
            />
            {`${t.filterBlank} (${column.blank})`}
          </label>
        </div>
        <button type="submit">{t.filterApply}</button>
      </fieldset>
    </form>
  );
}

function CustomFilter({
  criterion,
  apply,
  disabled,
  state,
}: {
  criterion: XlsxFilterColumn | undefined;
  apply: (conditions: XlsxFilterCondition[], all: boolean) => void;
  disabled: boolean;
  state: UiSnapshot;
}) {
  const t = messages(state.locale);
  const initial = criterion?.kind === "custom" ? criterion : undefined;
  const [conditions, setConditions] = useState<XlsxFilterCondition[]>([
    initial?.conditions[0] ?? { operator: "equal", value: "" },
    initial?.conditions[1] ?? { operator: "equal", value: "" },
  ]);
  const [second, setSecond] = useState(initial?.conditions.length === 2);
  const [all, setAll] = useState(initial?.all ?? true);
  const operators: [XlsxFilterOperator, string][] = [
    ["equal", "="],
    ["notEqual", "≠"],
    ["greaterThan", ">"],
    ["greaterThanOrEqual", "≥"],
    ["lessThan", "<"],
    ["lessThanOrEqual", "≤"],
  ];
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        apply(conditions.slice(0, second ? 2 : 1), all);
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.filterCustom}</legend>
        <p>{t.filterPattern}</p>
        {conditions.slice(0, second ? 2 : 1).map((condition, index) => (
          <div key={index}>
            <label>
              {`${t.filterOperator} ${index + 1}`}
              <select
                aria-label={`${t.filterOperator} ${index + 1}`}
                value={condition.operator}
                onChange={(e) => {
                  const operator = operators.find(
                    ([value]) => value === e.currentTarget.value,
                  )?.[0];
                  if (operator)
                    setConditions(
                      conditions.map((c, i) =>
                        i === index ? { ...c, operator } : c,
                      ),
                    );
                }}
              >
                {operators.map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
            <label>
              {`${t.filterOperand} ${index + 1}`}
              <input
                value={condition.value}
                maxLength={32767}
                onChange={(e) => {
                  const value = e.currentTarget.value;
                  setConditions(
                    conditions.map((c, i) =>
                      i === index ? { ...c, value } : c,
                    ),
                  );
                }}
              />
            </label>
          </div>
        ))}
        <label>
          <input
            type="checkbox"
            checked={second}
            onChange={(e) => setSecond(e.currentTarget.checked)}
          />
          {t.filterSecond}
        </label>
        {second && (
          <label>
            {t.filterJoin}
            <select
              aria-label={t.filterJoin}
              value={all ? "all" : "any"}
              onChange={(e) => setAll(e.currentTarget.value === "all")}
            >
              <option value="all">{t.filterAnd}</option>
              <option value="any">{t.filterOr}</option>
            </select>
          </label>
        )}
        <button type="submit">{t.filterCustomApply}</button>
      </fieldset>
    </form>
  );
}

export function XlsxFilter({
  editor,
  controller,
  state,
  disabled,
  table,
}: {
  editor: SpreadsheetEditor;
  controller: EditorController;
  state: UiSnapshot;
  disabled: boolean;
  table?: XlsxTable;
}) {
  const t = messages(state.locale),
    query = editor.currentState,
    filter = table?.filter ?? query.filter;
  const edit = (
    change:
      | { action: "filter"; range: string; columns: XlsxFilterColumn[] }
      | { action: "filterClear" | "filterRemove" | "filterReapply" },
  ) => {
    if (!table) return editor.editSheet(change);
    return editor.editSheet(
      change.action === "filter"
        ? { action: "tableFilter", id: table.id, columns: change.columns }
        : {
            action:
              change.action === "filterClear"
                ? "tableFilterClear"
                : change.action === "filterRemove"
                  ? "tableFilterRemove"
                  : "tableFilterReapply",
            id: table.id,
          },
    );
  };
  const [columnIndex, setColumn] = useState(filter.catalog[0]?.column ?? 1);
  const column =
    filter.catalog.find((c) => c.column === columnIndex) ?? filter.catalog[0];
  const blocked = disabled || !!filter.reason || !!table?.readOnlyReason;
  return (
    <fieldset disabled={blocked}>
      <legend>{t.filterCells}</legend>
      {filter.reason && <p>{filter.reason}</p>}
      <button
        type="button"
        disabled={
          !table && query.selection.range.top === query.selection.range.bottom
        }
        onClick={() =>
          controller.run(() =>
            edit({
              action: "filter",
              range: query.selection.address,
              columns: [],
            }),
          )
        }
      >
        {table ? t.tableFilter : t.filterRange}
      </button>
      {filter.range && (
        <>
          <p>{filter.range}</p>
          <label>
            {t.filterColumn}
            <select
              aria-label={t.filterColumn}
              value={column?.column ?? columnIndex}
              onChange={(e) => setColumn(Number(e.currentTarget.value))}
            >
              {filter.catalog.map((c) => (
                <option
                  key={c.column}
                  value={c.column}
                >{`${c.column}: ${c.title}`}</option>
              ))}
            </select>
          </label>
          {column && (
            <>
              <FilterColumn
                key={JSON.stringify(column)}
                column={column}
                disabled={blocked}
                state={state}
                apply={(values, blank, all) =>
                  controller.run(() =>
                    edit({
                      action: "filter",
                      range: filter.range,
                      columns: [
                        ...filter.columns.filter(
                          (c) => c.column !== column.column,
                        ),
                        ...(all
                          ? []
                          : [
                              {
                                kind: "values" as const,
                                column: column.column,
                                values,
                                blank,
                              },
                            ]),
                      ],
                    }),
                  )
                }
              />
              <CustomFilter
                key={
                  JSON.stringify(
                    filter.columns.find((c) => c.column === column.column),
                  ) + column.column
                }
                criterion={filter.columns.find(
                  (c) => c.column === column.column,
                )}
                disabled={blocked}
                state={state}
                apply={(conditions, all) =>
                  controller.run(() =>
                    edit({
                      action: "filter",
                      range: filter.range,
                      columns: [
                        ...filter.columns.filter(
                          (c) => c.column !== column.column,
                        ),
                        {
                          kind: "custom",
                          column: column.column,
                          conditions,
                          all,
                        },
                      ],
                    }),
                  )
                }
              />
              <XlsxRankFilterForm
                key={`rank:${column.column}:${JSON.stringify(filter.columns.find((c) => c.column === column.column))}`}
                column={column.column}
                criterion={filter.columns.find(
                  (c) => c.column === column.column,
                )}
                disabled={blocked}
                state={state}
                apply={(rule) =>
                  controller.run(() =>
                    edit({
                      action: "filter",
                      range: filter.range,
                      columns: [
                        ...filter.columns.filter(
                          (c) => c.column !== column.column,
                        ),
                        rule,
                      ],
                    }),
                  )
                }
              />
              <XlsxDateFilterForm
                key={`dates:${column.column}:${JSON.stringify(filter.columns.find((c) => c.column === column.column))}`}
                column={column.column}
                criterion={filter.columns.find(
                  (c) => c.column === column.column,
                )}
                disabled={blocked}
                state={state}
                apply={(rule) =>
                  controller.run(() =>
                    edit({
                      action: "filter",
                      range: filter.range,
                      columns: [
                        ...filter.columns.filter(
                          (c) => c.column !== column.column,
                        ),
                        rule,
                      ],
                    }),
                  )
                }
              />
              <XlsxColorFilterForm
                key={`color:${column.column}:${JSON.stringify(filter.columns.find((c) => c.column === column.column))}`}
                column={column.column}
                criterion={filter.columns.find(
                  (c) => c.column === column.column,
                )}
                disabled={blocked}
                state={state}
                apply={(rule) =>
                  controller.run(() =>
                    edit({
                      action: "filter",
                      range: filter.range,
                      columns: [
                        ...filter.columns.filter(
                          (c) => c.column !== column.column,
                        ),
                        rule,
                      ],
                    }),
                  )
                }
              />
              <XlsxIconFilterForm
                key={`icon:${column.column}:${JSON.stringify(filter.columns.find((c) => c.column === column.column))}`}
                column={column.column}
                criterion={filter.columns.find(
                  (c) => c.column === column.column,
                )}
                disabled={blocked}
                state={state}
                apply={(rule) =>
                  controller.run(() =>
                    edit({
                      action: "filter",
                      range: filter.range,
                      columns: [
                        ...filter.columns.filter(
                          (c) => c.column !== column.column,
                        ),
                        rule,
                      ],
                    }),
                  )
                }
              />
              <fieldset disabled={blocked}>
                <legend>{t.filterAverage}</legend>
                <p>{t.filterAverageHelp}</p>
                {[true, false].map((above) => (
                  <button
                    key={String(above)}
                    type="button"
                    aria-pressed={filter.columns.some(
                      (c) =>
                        c.column === column.column &&
                        c.kind === "average" &&
                        c.above === above,
                    )}
                    onClick={() =>
                      controller.run(() =>
                        edit({
                          action: "filter",
                          range: filter.range,
                          columns: [
                            ...filter.columns.filter(
                              (c) => c.column !== column.column,
                            ),
                            { kind: "average", column: column.column, above },
                          ],
                        }),
                      )
                    }
                  >
                    {above ? t.filterAboveAverage : t.filterBelowAverage}
                  </button>
                ))}
              </fieldset>
            </>
          )}
          <button
            type="button"
            disabled={!filter.columns.length}
            onClick={() =>
              controller.run(() => edit({ action: "filterClear" }))
            }
          >
            {t.filterClear}
          </button>
          <button
            type="button"
            disabled={!filter.columns.length}
            onClick={() =>
              controller.run(() => edit({ action: "filterReapply" }))
            }
          >
            {t.filterReapply}
          </button>
          <button
            type="button"
            onClick={() =>
              controller.run(() => edit({ action: "filterRemove" }))
            }
          >
            {t.filterRemove}
          </button>
        </>
      )}
    </fieldset>
  );
}
