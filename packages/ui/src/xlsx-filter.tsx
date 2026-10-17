import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { XlsxFilterState } from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

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

export function XlsxFilter({
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
    filter = query.filter;
  const [columnIndex, setColumn] = useState(filter.catalog[0]?.column ?? 1);
  const column =
    filter.catalog.find((c) => c.column === columnIndex) ?? filter.catalog[0];
  const blocked = disabled || !!filter.reason;
  return (
    <fieldset disabled={blocked}>
      <legend>{t.filterCells}</legend>
      {filter.reason && <p>{filter.reason}</p>}
      <button
        type="button"
        disabled={query.selection.range.top === query.selection.range.bottom}
        onClick={() =>
          controller.run(() =>
            editor.editSheet({
              action: "filter",
              range: query.selection.address,
              columns: [],
            }),
          )
        }
      >
        {t.filterRange}
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
            <FilterColumn
              key={JSON.stringify(column)}
              column={column}
              disabled={blocked}
              state={state}
              apply={(values, blank, all) =>
                controller.run(() =>
                  editor.editSheet({
                    action: "filter",
                    range: filter.range,
                    columns: [
                      ...filter.columns.filter(
                        (c) => c.column !== column.column,
                      ),
                      ...(all
                        ? []
                        : [{ column: column.column, values, blank }]),
                    ],
                  }),
                )
              }
            />
          )}
          <button
            type="button"
            disabled={!filter.columns.length}
            onClick={() =>
              controller.run(() => editor.editSheet({ action: "filterClear" }))
            }
          >
            {t.filterClear}
          </button>
          <button
            type="button"
            disabled={!filter.columns.length}
            onClick={() =>
              controller.run(() =>
                editor.editSheet({ action: "filterReapply" }),
              )
            }
          >
            {t.filterReapply}
          </button>
          <button
            type="button"
            onClick={() =>
              controller.run(() => editor.editSheet({ action: "filterRemove" }))
            }
          >
            {t.filterRemove}
          </button>
        </>
      )}
    </fieldset>
  );
}
