import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import type { XlsxSortKey } from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function XlsxSort({
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
    range = query.selection.range;
  const [rows, setRows] = useState(true),
    [header, setHeader] = useState(false),
    [caseSensitive, setCaseSensitive] = useState(false),
    [keys, setKeys] = useState<XlsxSortKey[]>([
      { index: range.left, descending: false },
    ]);
  const low = rows ? range.left : range.top,
    high = rows ? range.right : range.bottom;
  const update = (position: number, patch: Partial<XlsxSortKey>) =>
    setKeys((keys) =>
      keys.map((key, i) => (i === position ? { ...key, ...patch } : key)),
    );
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editSheet({
            action: "sort",
            range: query.selection.address,
            rows,
            header,
            caseSensitive,
            keys,
          }),
        );
      }}
    >
      <fieldset
        disabled={
          disabled ||
          !!query.readOnlyReason ||
          !!query.sheets.find((s) => s.id === query.sheet)?.protected
        }
      >
        <legend>{t.sortCells}</legend>
        <p>{query.selection.address}</p>
        <label>
          {t.sortAxis}
          <select
            aria-label={t.sortAxis}
            value={rows ? "rows" : "columns"}
            onChange={(event) => {
              const rows = event.currentTarget.value === "rows";
              setRows(rows);
              setKeys([
                { index: rows ? range.left : range.top, descending: false },
              ]);
            }}
          >
            <option value="rows">{t.sortRows}</option>
            <option value="columns">{t.sortColumns}</option>
          </select>
        </label>
        <label>
          <input
            type="checkbox"
            checked={header}
            onChange={(e) => setHeader(e.currentTarget.checked)}
          />
          {t.sortHeader}
        </label>
        <label>
          <input
            type="checkbox"
            checked={caseSensitive}
            onChange={(e) => setCaseSensitive(e.currentTarget.checked)}
          />
          {t.matchCase}
        </label>
        {keys.map((key, i) => (
          <div key={i}>
            <label>
              {`${t.sortKey} ${i + 1}`}
              <input
                aria-label={`${t.sortKey} ${i + 1}`}
                type="number"
                min={low}
                max={high}
                required
                value={key.index}
                onChange={(e) =>
                  update(i, { index: Number(e.currentTarget.value) })
                }
              />
            </label>
            <label>
              {`${t.sortDirection} ${i + 1}`}
              <select
                aria-label={`${t.sortDirection} ${i + 1}`}
                value={key.descending ? "descending" : "ascending"}
                onChange={(e) =>
                  update(i, {
                    descending: e.currentTarget.value === "descending",
                  })
                }
              >
                <option value="ascending">{t.sortAscending}</option>
                <option value="descending">{t.sortDescending}</option>
              </select>
            </label>
            <button
              type="button"
              aria-label={`${t.removeSortKey} ${i + 1}`}
              disabled={keys.length === 1}
              onClick={() =>
                setKeys((keys) => keys.filter((_, position) => position !== i))
              }
            >
              {t.removeSortKey}
            </button>
          </div>
        ))}
        <button
          type="button"
          disabled={keys.length >= Math.min(16, high - low + 1)}
          onClick={() => {
            const index = Array.from(
              { length: high - low + 1 },
              (_, i) => low + i,
            ).find((index) => !keys.some((key) => key.index === index));
            if (index !== undefined)
              setKeys((keys) => [...keys, { index, descending: false }]);
          }}
        >
          {t.addSortKey}
        </button>
        <button type="submit">{t.sortCells}</button>
      </fieldset>
    </form>
  );
}
