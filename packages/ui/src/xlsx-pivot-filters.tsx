import type { Dispatch, SetStateAction } from "react";
import type {
  XlsxPivotFilter,
  XlsxPivotPreview,
} from "@open-document/web/xlsx";
import type { UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PivotFilters({
  filters,
  setFilters,
  axes,
  choices,
  state,
}: {
  filters: XlsxPivotFilter[];
  setFilters: Dispatch<SetStateAction<XlsxPivotFilter[]>>;
  axes: number[];
  choices: XlsxPivotPreview["filterItems"] | undefined;
  state: UiSnapshot;
}) {
  const t = messages(state.locale);
  const membersLabel = (filter: XlsxPivotFilter) =>
    filter.report
      ? t.pivotFilterMembers
      : axes.includes(filter.field)
        ? t.pivotAxisMembers
        : t.pivotMemberMembers;
  const update = (at: number, patch: Partial<XlsxPivotFilter>) =>
    setFilters(
      filters.map((filter, i) => (i === at ? { ...filter, ...patch } : filter)),
    );
  return (
    <>
      {filters.map((filter, index) => (
        <fieldset key={index}>
          <legend>
            {filter.report
              ? t.pivotReportField
              : axes.includes(filter.field)
                ? t.pivotAxisFilter
                : t.pivotMemberFilter}{" "}
            {index + 1}
          </legend>
          <label>
            {t.pivotColumn}
            <input
              type="number"
              min={1}
              max={64}
              step={1}
              value={filter.field + 1}
              onChange={(event) =>
                update(index, {
                  field: event.currentTarget.valueAsNumber - 1,
                  values: null,
                })
              }
            />
          </label>
          <label>
            {t.pivotFilterPlacement}
            <select
              aria-label={t.pivotFilterPlacement}
              value={String(filter.report)}
              onChange={(event) =>
                update(index, { report: event.currentTarget.value === "true" })
              }
            >
              <option value="true" disabled={axes.includes(filter.field)}>
                {t.pivotReportField}
              </option>
              <option value="false">{t.pivotMemberFilter}</option>
            </select>
          </label>
          <label>
            <input
              type="checkbox"
              checked={filter.values === null}
              onChange={(event) =>
                update(index, {
                  values: event.currentTarget.checked ? null : [],
                })
              }
            />
            {t.pivotFilterAll}
          </label>
          {!choices && <p>{t.pivotFilterLoad}</p>}
          <label>
            {membersLabel(filter)}
            <select
              multiple
              size={8}
              aria-label={membersLabel(filter)}
              disabled={!choices || filter.values === null}
              value={
                choices?.[index]?.flatMap((item, i) =>
                  filter.values?.some(
                    (value) =>
                      value.kind === item.value.kind &&
                      value.value === item.value.value,
                  )
                    ? [String(i)]
                    : [],
                ) ?? []
              }
              onChange={(event) => {
                const items = choices?.[index];
                if (items)
                  update(index, {
                    values: Array.from(
                      event.currentTarget.selectedOptions,
                    ).flatMap((option) => {
                      const item = items[Number(option.value)];
                      return item ? [item.value] : [];
                    }),
                  });
              }}
            >
              {choices?.[index]?.map((item, i) => (
                <option key={i} value={i}>
                  {item.label} ({t[`pivotFilterKind_${item.value.kind}`]})
                </option>
              ))}
            </select>
          </label>
          {filter.values?.length === 0 && (
            <p role="status">{t.pivotFilterEmpty}</p>
          )}
          <button
            type="button"
            onClick={() => setFilters(filters.filter((_, i) => i !== index))}
          >
            {filter.report
              ? t.pivotRemoveFilter
              : axes.includes(filter.field)
                ? t.pivotRemoveAxisFilter
                : t.pivotRemoveMemberFilter}
          </button>
        </fieldset>
      ))}
      <button
        type="button"
        disabled={filters.length === 8}
        onClick={() => {
          const field = Array.from({ length: 64 }, (_, i) => i).find(
            (i) =>
              !axes.includes(i) &&
              !filters.some((filter) => filter.field === i),
          );
          if (field !== undefined)
            setFilters([...filters, { field, report: true, values: null }]);
        }}
      >
        {t.pivotAddFilter}
      </button>
      <button
        type="button"
        disabled={
          filters.length === 8 ||
          axes.every((field) =>
            filters.some((filter) => filter.field === field),
          )
        }
        onClick={() => {
          const field = axes.find(
            (field) => !filters.some((filter) => filter.field === field),
          );
          if (field !== undefined)
            setFilters([...filters, { field, report: false, values: null }]);
        }}
      >
        {t.pivotAddAxisFilter}
      </button>
    </>
  );
}
