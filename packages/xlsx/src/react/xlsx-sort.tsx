import { useState } from "react";
import type { SpreadsheetEditor } from "../web/spreadsheet-editor.js";
import { conditionalIconSets, type XlsxSortKey } from "../web/xlsx.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";
import { selectedXlsxTable } from "./xlsx-tables.js";
import { conditionalIconLabels } from "./conditional-icons.js";

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
    query = editor.currentState;
  const native = selectedXlsxTable(query);
  const range = native?.range ?? query.selection.range;
  const [rows, setRows] = useState(true),
    [header, setHeader] = useState(false),
    [caseSensitive, setCaseSensitive] = useState(false),
    [keys, setKeys] = useState<XlsxSortKey[]>([
      { index: range.left, descending: false },
    ]);
  const rowAxis = !!native || rows,
    low = rowAxis ? range.left : range.top,
    high = rowAxis ? range.right : range.bottom;
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
            rows: rowAxis,
            header: native ? false : header,
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
        <legend>{native ? t.tableSort : t.sortCells}</legend>
        <p>{native ? native.table.range : query.selection.address}</p>
        {native && (
          <p>
            {native.table.name}: {t.tableSortHelp}
          </p>
        )}
        <label>
          {t.sortAxis}
          <select
            aria-label={t.sortAxis}
            value={rowAxis ? "rows" : "columns"}
            disabled={!!native}
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
            checked={native ? native.table.headerRow : header}
            disabled={!!native}
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
                    sortBy === "fontColor" ||
                    sortBy === "icon"
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
                            : sortBy === "icon"
                              ? {
                                  index: current.index,
                                  descending: current.descending,
                                  sortBy,
                                  iconSet: "3Arrows",
                                  iconId: 2,
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
                <option value="icon">{t.sortIcons}</option>
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
                    : key.sortBy === "icon"
                      ? t.sortIconFirst
                      : t.sortColorFirst}
                </option>
                <option value="descending">
                  {(key.sortBy ?? "value") === "value"
                    ? t.sortDescending
                    : key.sortBy === "icon"
                      ? t.sortIconLast
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
            ) : key.sortBy === "icon" ? (
              <>
                <label>
                  {`${t.sortIconSet} ${i + 1}`}
                  <select
                    aria-label={`${t.sortIconSet} ${i + 1}`}
                    value={key.iconSet ?? ""}
                    onChange={(event) => {
                      const set = conditionalIconSets.find(
                        (set) => set === event.currentTarget.value,
                      );
                      setKeys((keys) =>
                        keys.map((current, at) =>
                          at !== i
                            ? current
                            : {
                                index: current.index,
                                descending: current.descending,
                                sortBy: "icon",
                                ...(set
                                  ? {
                                      iconSet: set,
                                      iconId: Math.min(
                                        current.iconId ?? 2,
                                        Number(set[0]) - 1,
                                      ),
                                    }
                                  : {}),
                              },
                        ),
                      );
                    }}
                  >
                    <option value="">{t.sortNoIcon}</option>
                    {conditionalIconSets.map((set, index) => (
                      <option key={set} value={set}>
                        {conditionalIconLabels(t)[index]}
                      </option>
                    ))}
                  </select>
                </label>
                {key.iconSet && (
                  <label>
                    {`${t.sortIconIndex} ${i + 1}`}
                    <select
                      aria-label={`${t.sortIconIndex} ${i + 1}`}
                      value={key.iconId ?? 0}
                      onChange={(event) =>
                        update(i, { iconId: Number(event.currentTarget.value) })
                      }
                    >
                      {Array.from(
                        { length: Number(key.iconSet[0]) },
                        (_, index) => (
                          <option key={index} value={index}>
                            {index + 1}
                          </option>
                        ),
                      )}
                    </select>
                  </label>
                )}
                <p>{t.sortIconHelp}</p>
              </>
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
        <button type="submit">{native ? t.tableSort : t.sortCells}</button>
      </fieldset>
    </form>
  );
}
