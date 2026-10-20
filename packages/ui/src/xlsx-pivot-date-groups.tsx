import type { Dispatch, SetStateAction } from "react";
import {
  xlsxPivotDateUnits,
  type XlsxPivotDateGroup,
} from "@open-document/web/xlsx";
import type { UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PivotDateGroups({
  groups,
  setGroups,
  axes,
  state,
}: {
  groups: XlsxPivotDateGroup[];
  setGroups: Dispatch<SetStateAction<XlsxPivotDateGroup[]>>;
  axes: number[];
  state: UiSnapshot;
}) {
  const t = messages(state.locale);
  const update = (at: number, patch: Partial<XlsxPivotDateGroup>) =>
    setGroups(
      groups.map((group, i) => (i === at ? { ...group, ...patch } : group)),
    );
  return (
    <>
      <p>{t.pivotDateHelp}</p>
      {groups.map((group, index) => (
        <fieldset key={index}>
          <legend>
            {t.pivotDateGroup} {index + 1}
          </legend>
          <label>
            {t.pivotColumn}
            <input
              type="number"
              min={1}
              max={64}
              step={1}
              value={Number.isFinite(group.field) ? group.field + 1 : ""}
              onChange={(event) =>
                update(index, { field: event.currentTarget.valueAsNumber - 1 })
              }
            />
          </label>
          <label>
            {t.pivotDateUnit}
            <select
              aria-label={t.pivotDateUnit}
              multiple
              size={4}
              value={group.units}
              onChange={(event) => {
                const options = Array.from(event.currentTarget.selectedOptions);
                update(index, {
                  units: xlsxPivotDateUnits.filter((unit) =>
                    options.some((option) => option.value === unit),
                  ),
                });
              }}
            >
              {xlsxPivotDateUnits.map((unit) => (
                <option key={unit} value={unit}>
                  {t[`pivotDate_${unit}`]}
                </option>
              ))}
            </select>
          </label>
          <button
            type="button"
            onClick={() => setGroups(groups.filter((_, i) => i !== index))}
          >
            {t.pivotRemoveDateGroup}
          </button>
        </fieldset>
      ))}
      <button
        type="button"
        disabled={
          groups.length >= 16 ||
          !axes.some((field) => !groups.some((group) => group.field === field))
        }
        onClick={() => {
          const field = axes.find(
            (field) => !groups.some((group) => group.field === field),
          );
          if (field !== undefined)
            setGroups([...groups, { field, units: ["years"] }]);
        }}
      >
        {t.pivotAddDateGroup}
      </button>
    </>
  );
}
