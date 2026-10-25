import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import {
  checkXlsxPivotSettings,
  xlsxPivotAggregates,
  xlsxPivotValueModes,
  xlsxPivotBaseModes,
  xlsxPivotCompareModes,
  type XlsxPivotSettings,
  type XlsxPivotValue,
  type XlsxPivotPreview,
  type XlsxPivots,
  type XlsxPivotFilter,
  type XlsxPivotNumberGroup,
  type XlsxPivotDateGroup,
} from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { PivotFilters } from "./xlsx-pivot-filters.js";
import { PivotNumberGroups } from "./xlsx-pivot-number-groups.js";
import { PivotDateGroups } from "./xlsx-pivot-date-groups.js";
import { PivotBaseItemSelect } from "./xlsx-pivot-base-item.js";
import { XlsxSlicersPanel } from "./xlsx-slicers.js";
import { XlsxTimelinesPanel } from "./xlsx-timelines.js";

export function XlsxPivotsPanel({
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
    snapshot = editor.getSnapshot();
  const [sourceSheet, setSourceSheet] = useState(query.sheet),
    [source, setSource] = useState(query.selection.address),
    [rows, setRows] = useState("1"),
    [columns, setColumns] = useState(""),
    [filters, setFilters] = useState<XlsxPivotFilter[]>([]),
    [subtotals, setSubtotals] = useState(""),
    [numberGroups, setNumberGroups] = useState<XlsxPivotNumberGroup[]>([]),
    [dateGroups, setDateGroups] = useState<XlsxPivotDateGroup[]>([]),
    [values, setValues] = useState<XlsxPivotValue[]>([
      {
        field: 1,
        aggregate: "sum",
        baseItem: null,
        baseField: null,
        showDataAs: "normal",
        name: t.pivotDefaultCaption,
      },
    ]),
    [name, setName] = useState("Pivot1"),
    [destination, setDestination] = useState("E1"),
    [preview, setPreview] = useState<XlsxPivotPreview>(),
    [catalog, setCatalog] = useState<XlsxPivots>(),
    [editing, setEditing] = useState<string>();
  const settings: XlsxPivotSettings = {
    sourceSheet,
    source,
    rows: rows.split(",").map((field) => Number(field.trim()) - 1),
    columns: columns.trim()
      ? columns.split(",").map((field) => Number(field.trim()) - 1)
      : [],
    filters,
    subtotals: subtotals.trim()
      ? subtotals.split(",").map((field) => Number(field.trim()) - 1)
      : [],
    numberGroups,
    dateGroups,
    values,
  };
  const editingSource = catalog?.items.find(
    (pivot) => pivot.part === editing,
  )?.settings;
  let valid = true;
  try {
    checkXlsxPivotSettings(settings);
  } catch {
    valid = false;
  }
  const ready =
      preview?.revision === query.revision &&
      JSON.stringify(preview.settings) === JSON.stringify(settings),
    current = catalog?.revision === query.revision,
    blocked =
      disabled ||
      snapshot.composition ||
      snapshot.dragging ||
      snapshot.paused ||
      snapshot.stopped ||
      !!query.readOnlyReason ||
      !!query.sheets.find((sheet) => sheet.id === query.sheet)?.protected;
  const updateValue = (index: number, patch: Partial<XlsxPivotValue>) =>
    setValues(
      values.map((value, i) => (i === index ? { ...value, ...patch } : value)),
    );
  const basePreview =
    preview?.revision === query.revision &&
    preview.settings.source === source &&
    preview.settings.sourceSheet === sourceSheet &&
    JSON.stringify(preview.settings.numberGroups) ===
      JSON.stringify(numberGroups) &&
    JSON.stringify(preview.settings.dateGroups) === JSON.stringify(dateGroups)
      ? preview
      : undefined;
  const filterChoices =
    basePreview &&
    basePreview.settings.filters.length === filters.length &&
    basePreview.settings.filters.every(
      (filter, i) =>
        filter.field === filters[i]?.field &&
        filter.report === filters[i]?.report,
    )
      ? basePreview.filterItems
      : undefined;
  // shortcut: Preview uses raw values; add formatted labels in MoonBit when needed.
  const display = (cell: XlsxPivotPreview["total"][number]) =>
    cell.kind === "blank" ? t.pivotBlank : String(cell.value);
  return [
    <XlsxTimelinesPanel
      key="timelines"
      editor={editor}
      controller={controller}
      state={state}
      disabled={
        disabled ||
        snapshot.composition ||
        snapshot.dragging ||
        snapshot.paused ||
        snapshot.stopped
      }
    />,
    <fieldset key="pivots" disabled={blocked}>
      <legend>{t.pivots}</legend>
      <XlsxSlicersPanel
        editor={editor}
        controller={controller}
        state={state}
        disabled={blocked}
      />
      <p>{t.pivotHelp}</p>
      <label>
        {t.pivotSourceSheet}
        <select
          aria-label={t.pivotSourceSheet}
          value={sourceSheet}
          onChange={(event) => setSourceSheet(event.currentTarget.value)}
        >
          <option value="">{t.choose}</option>
          {query.sheets.map((sheet) => (
            <option key={sheet.id} value={sheet.id}>
              {sheet.name}
            </option>
          ))}
        </select>
      </label>
      <label>
        {t.pivotSource}
        <input
          value={source}
          maxLength={257}
          placeholder={t.pivotSourceExample}
          onChange={(event) =>
            setSource(event.currentTarget.value.toUpperCase())
          }
        />
      </label>
      <button
        type="button"
        onClick={() => {
          setSourceSheet(query.sheet);
          setSource(query.selection.address);
        }}
      >
        {t.pivotUseSelection}
      </button>
      <label>
        {t.pivotRows}
        <input
          value={rows}
          maxLength={32}
          onChange={(event) => setRows(event.currentTarget.value)}
        />
      </label>
      <label>
        {t.pivotColumns}
        <input
          value={columns}
          maxLength={32}
          onChange={(event) => setColumns(event.currentTarget.value)}
        />
      </label>
      <PivotFilters
        filters={filters}
        setFilters={setFilters}
        choices={filterChoices}
        sourceChanged={
          !!editingSource &&
          (editingSource.source !== source ||
            editingSource.sourceSheet !== sourceSheet)
        }
        axes={[...settings.rows, ...settings.columns]}
        state={state}
      />
      <PivotDateGroups
        groups={dateGroups}
        setGroups={setDateGroups}
        axes={[...settings.rows, ...settings.columns].filter(
          (field) => !numberGroups.some((group) => group.field === field),
        )}
        state={state}
      />
      <label>
        {t.pivotSubtotals}
        <input
          value={subtotals}
          maxLength={64}
          onChange={(event) => setSubtotals(event.currentTarget.value)}
        />
      </label>
      <p>{t.pivotSubtotalsHelp}</p>
      <PivotNumberGroups
        groups={numberGroups}
        setGroups={setNumberGroups}
        axes={[...settings.rows, ...settings.columns].filter(
          (field) => !dateGroups.some((group) => group.field === field),
        )}
        state={state}
      />
      {values.map((value, index) => (
        <fieldset key={index}>
          <legend>
            {t.pivotValue} {index + 1}
          </legend>
          <label>
            {t.pivotColumn}
            <input
              type="number"
              min={1}
              max={64}
              step={1}
              value={value.field + 1}
              onChange={(event) =>
                updateValue(index, {
                  field: event.currentTarget.valueAsNumber - 1,
                })
              }
            />
          </label>
          <label>
            {t.pivotAggregate}
            <select
              aria-label={t.pivotAggregate}
              value={value.aggregate}
              onChange={(event) => {
                const aggregate = xlsxPivotAggregates.find(
                  (kind) => kind === event.currentTarget.value,
                );
                if (aggregate) updateValue(index, { aggregate });
              }}
            >
              {xlsxPivotAggregates.map((kind) => (
                <option key={kind} value={kind}>
                  {t[`pivot_${kind}`]}
                </option>
              ))}
            </select>
          </label>
          <label>
            {t.pivotShowDataAs}
            <select
              aria-label={t.pivotShowDataAs}
              value={value.showDataAs}
              onChange={(event) => {
                const showDataAs = xlsxPivotValueModes.find(
                  (mode) => mode === event.currentTarget.value,
                );
                if (showDataAs)
                  updateValue(index, {
                    showDataAs,
                    baseItem: xlsxPivotCompareModes.includes(showDataAs)
                      ? (value.baseItem ?? "previous")
                      : null,
                    baseField: xlsxPivotBaseModes.includes(showDataAs)
                      ? (value.baseField ?? settings.rows[0] ?? 0)
                      : null,
                  });
              }}
            >
              {xlsxPivotValueModes.map((mode) => (
                <option key={mode} value={mode}>
                  {t[`pivotMode_${mode}`]}
                </option>
              ))}
            </select>
          </label>
          {xlsxPivotBaseModes.includes(value.showDataAs) && (
            <label>
              {t.pivotBaseField}
              <input
                aria-label={t.pivotBaseField}
                type="number"
                min={1}
                max={64}
                step={1}
                required
                value={(value.baseField ?? 0) + 1}
                onChange={(event) =>
                  updateValue(index, {
                    baseField: event.currentTarget.valueAsNumber - 1,
                    baseItem: xlsxPivotCompareModes.includes(value.showDataAs)
                      ? "previous"
                      : null,
                  })
                }
              />
            </label>
          )}
          <label>
            {t.pivotCaption}
            <input
              value={value.name}
              maxLength={255}
              onChange={(event) =>
                updateValue(index, { name: event.currentTarget.value })
              }
            />
          </label>
          {xlsxPivotCompareModes.includes(value.showDataAs) && (
            <PivotBaseItemSelect
              value={value.baseItem}
              items={
                basePreview?.settings.values[index]?.baseField ===
                value.baseField
                  ? basePreview.baseItems[index]
                  : undefined
              }
              update={(baseItem) => updateValue(index, { baseItem })}
              state={state}
            />
          )}
          <button
            type="button"
            disabled={values.length === 1}
            onClick={() => setValues(values.filter((_, i) => i !== index))}
          >
            {t.pivotRemoveValue}
          </button>
        </fieldset>
      ))}
      <button
        type="button"
        disabled={values.length === 8}
        onClick={() =>
          setValues([
            ...values,
            {
              field: 1,
              aggregate: "sum",
              baseItem: null,
              baseField: null,
              showDataAs: "normal",
              name: `${t.pivotDefaultCaption} ${values.length + 1}`,
            },
          ])
        }
      >
        {t.pivotAddValue}
      </button>
      <button
        type="button"
        disabled={!valid}
        onClick={() =>
          controller.run(async () =>
            setPreview(await editor.pivotPreview(settings, editing)),
          )
        }
      >
        {t.pivotPreview}
      </button>
      {preview && (
        <>
          <p>
            {t.pivotFilteredRecords}: {preview.filteredCount} /{" "}
            {preview.recordCount}
          </p>
          {!ready && <p role="status">{t.pivotPreviewStale}</p>}
          {preview.truncated && <p>{t.pivotTruncated}</p>}
          <div style={{ overflow: "auto", maxHeight: "16rem" }}>
            <table aria-label={t.pivotPreview}>
              <thead>
                {preview.columnFields.length > 0 ? (
                  <>
                    {preview.columnFields.map((_, level) => (
                      <tr key={level}>
                        {level === 0 &&
                          preview.rowFields.map((field) => (
                            <th
                              key={field}
                              scope="col"
                              rowSpan={
                                preview.columnFields.length +
                                (preview.settings.values.length > 1 ? 1 : 0)
                              }
                            >
                              {preview.fields[field]}
                            </th>
                          ))}
                        {preview.columnMembers.map((column, i) => (
                          <th
                            key={i}
                            scope="colgroup"
                            colSpan={preview.settings.values.length}
                          >
                            {column.members[level] &&
                              display(column.members[level])}
                            {column.subtotal &&
                              level === column.members.length - 1 &&
                              ` ${t.pivotSubtotal}`}
                          </th>
                        ))}
                        {level === 0 && (
                          <th
                            scope="colgroup"
                            colSpan={preview.settings.values.length}
                            rowSpan={preview.columnFields.length}
                          >
                            {t.pivotTotal}
                          </th>
                        )}
                      </tr>
                    ))}
                    {preview.settings.values.length > 1 && (
                      <tr>
                        {[...preview.columnMembers, null].flatMap((_, i) =>
                          preview.settings.values.map((value, j) => (
                            <th key={`${i}:${j}`} scope="col">
                              {value.name}
                            </th>
                          )),
                        )}
                      </tr>
                    )}
                  </>
                ) : (
                  <tr>
                    {preview.rowFields.map((field) => (
                      <th key={field} scope="col">
                        {preview.fields[field]}
                      </th>
                    ))}
                    {preview.settings.values.map((value, i) => (
                      <th key={i} scope="col">
                        {value.name}
                      </th>
                    ))}
                  </tr>
                )}
              </thead>
              <tbody>
                {preview.rows.map((row, i) => (
                  <tr key={i}>
                    {preview.rowFields.map((_, j) => (
                      <th key={j} scope="row">
                        {row.members[j] && display(row.members[j])}
                        {row.subtotal &&
                          j === row.members.length - 1 &&
                          ` ${t.pivotSubtotal}`}
                      </th>
                    ))}
                    {row.values.map((cell, j) => (
                      <td key={j}>{display(cell)}</td>
                    ))}
                    {preview.columnFields.length > 0 &&
                      row.total.map((cell, j) => (
                        <td key={`total:${j}`}>{display(cell)}</td>
                      ))}
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr>
                  <th scope="row" colSpan={preview.rowFields.length}>
                    {t.pivotTotal}
                  </th>
                  {(preview.columnFields.length > 0
                    ? [...preview.columnTotals.flat(), ...preview.total]
                    : preview.total
                  ).map((cell, i) => (
                    <td key={i}>{display(cell)}</td>
                  ))}
                </tr>
              </tfoot>
            </table>
          </div>
        </>
      )}
      <label>
        {t.pivotName}
        <input
          disabled={!!editing}
          value={name}
          maxLength={255}
          onChange={(event) => setName(event.currentTarget.value)}
        />
      </label>
      <label>
        {t.pivotDestination}
        <input
          disabled={!!editing}
          value={destination}
          maxLength={16}
          onChange={(event) =>
            setDestination(event.currentTarget.value.toUpperCase())
          }
        />
      </label>
      <button
        type="button"
        disabled={
          !valid || !ready || (!editing && (!name.trim() || !destination))
        }
        onClick={() =>
          controller.run(async () => {
            if (!preview) return;
            await editor.editSheet(
              editing
                ? {
                    action: "updatePivot",
                    part: editing,
                    settings: preview.settings,
                    sourceRevision: preview.revision,
                  }
                : {
                    action: "createPivot",
                    settings: preview.settings,
                    sourceRevision: preview.revision,
                    name,
                    destination,
                  },
            );
            setCatalog(await editor.pivots());
          })
        }
      >
        {editing ? t.pivotApply : t.pivotCreate}
      </button>
      {editing && (
        <button
          type="button"
          onClick={() => {
            setEditing(undefined);
            setPreview(undefined);
          }}
        >
          {t.pivotNew}
        </button>
      )}
      <button
        type="button"
        onClick={() =>
          controller.run(async () => setCatalog(await editor.pivots()))
        }
      >
        {t.pivotList}
      </button>
      {catalog && (
        <>
          {!current && <p role="status">{t.pivotReload}</p>}
          {!catalog.items.length && <p>{t.pivotEmpty}</p>}
          {catalog.items.map((pivot) => (
            <fieldset key={pivot.part}>
              <legend>
                {pivot.name} ({pivot.range})
              </legend>
              <p>
                {
                  query.sheets.find((sheet) => sheet.id === pivot.sourceSheet)
                    ?.name
                }{" "}
                {pivot.source}
              </p>
              <p>{pivot.stale ? t.pivotStale : t.pivotCurrent}</p>
              {pivot.reason && <p>{pivot.reason}</p>}
              <button
                type="button"
                disabled={!current || (!pivot.settings && !pivot.recovery)}
                onClick={() => {
                  const settings =
                    pivot.settings ??
                    (pivot.recovery
                      ? {
                          ...pivot.recovery,
                          sourceSheet: "",
                        }
                      : undefined);
                  if (!settings) return;
                  setEditing(pivot.part);
                  setName(pivot.name);
                  setDestination(pivot.range.split(":")[0]!);
                  setSourceSheet(settings.sourceSheet);
                  setSource(settings.source);
                  setRows(settings.rows.map((field) => field + 1).join(","));
                  setColumns(
                    settings.columns.map((field) => field + 1).join(","),
                  );
                  setFilters(settings.filters);
                  setNumberGroups(settings.numberGroups);
                  setDateGroups(settings.dateGroups);
                  setSubtotals(
                    settings.subtotals.map((field) => field + 1).join(","),
                  );
                  setValues(settings.values);
                  setPreview(undefined);
                }}
              >
                {t.pivotEdit}
              </button>
              <button
                type="button"
                disabled={!current || !!pivot.reason}
                onClick={() =>
                  controller.run(async () => {
                    await editor.editSheet({
                      action: "refreshPivot",
                      part: pivot.part,
                    });
                    setCatalog(await editor.pivots());
                  })
                }
              >
                {t.pivotRefresh}
              </button>
              <button
                type="button"
                disabled={!current || (!pivot.settings && !pivot.recovery)}
                onClick={() =>
                  controller.run(async () => {
                    await editor.editSheet({
                      action: "deletePivot",
                      part: pivot.part,
                    });
                    if (editing === pivot.part) {
                      setEditing(undefined);
                      setPreview(undefined);
                    }
                    setCatalog(await editor.pivots());
                  })
                }
              >
                {t.pivotDelete}
              </button>
            </fieldset>
          ))}
        </>
      )}
    </fieldset>,
  ];
}
