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
              {`${t.sortBy} ${i + 1}`}
              <select
                aria-label={`${t.sortBy} ${i + 1}`}
                value={key.sortBy ?? "value"}
                onChange={(event) => {
                  const sortBy = event.currentTarget.value;
                  if (
                    sortBy === "value" ||
                    sortBy === "cellColor" ||
                    sortBy === "fontColor"
                  )
                    setKeys((keys) =>
                      keys.map((current, at) =>
                        at !== i
                          ? current
                          : sortBy === "value"
                            ? {
                                index: current.index,
                                descending: current.descending,
                                sortBy,
                                customList: [],
                              }
                            : {
                                index: current.index,
                                descending: current.descending,
                                sortBy,
                                color: "ff0000",
                              },
                      ),
                    );
                }}
              >
                <option value="value">{t.sortValues}</option>
                <option value="cellColor">{t.sortFillColor}</option>
                <option value="fontColor">{t.sortFontColor}</option>
              </select>
            </label>
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
                <option value="ascending">
                  {(key.sortBy ?? "value") === "value"
                    ? t.sortAscending
                    : t.sortColorFirst}
                </option>
                <option value="descending">
                  {(key.sortBy ?? "value") === "value"
                    ? t.sortDescending
                    : t.sortColorLast}
                </option>
              </select>
            </label>
            {(key.sortBy ?? "value") === "value" ? (
              <label>
                {`${t.sortCustomList} ${i + 1}`}
                <textarea
                  aria-label={`${t.sortCustomList} ${i + 1}`}
                  maxLength={32767}
                  rows={3}
                  value={key.customList?.join("\n") ?? ""}
                  onChange={(event) =>
                    update(i, {
                      customList:
                        event.currentTarget.value === ""
                          ? []
                          : event.currentTarget.value
                              .replace(/\r\n/g, "\n")
                              .split("\n"),
                    })
                  }
                />
                <span>{t.sortCustomListHelp}</span>
              </label>
            ) : (
              <>
                <label>
                  {`${t.sortColor} ${i + 1}`}
                  <input
                    aria-label={`${t.sortColor} ${i + 1}`}
                    value={key.color ?? "ff0000"}
                    maxLength={6}
                    pattern="[0-9a-fA-F]{6}"
                    required={key.sortBy === "fontColor"}
                    onChange={(event) =>
                      update(i, { color: event.currentTarget.value })
                    }
                  />
                </label>
                {key.sortBy === "cellColor" && (
                  <label>
                    <input
                      type="checkbox"
                      checked={key.color === ""}
                      onChange={(event) =>
                        update(i, {
                          color: event.currentTarget.checked ? "" : "ff0000",
                        })
                      }
                    />
                    {t.sortNoFill}
                  </label>
                )}
              </>
            )}
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
          disabled={keys.length >= 16}
          onClick={() => {
            const index =
              Array.from({ length: high - low + 1 }, (_, i) => low + i).find(
                (index) => !keys.some((key) => key.index === index),
              ) ?? low;
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
