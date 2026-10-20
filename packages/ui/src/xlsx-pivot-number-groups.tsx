import type { Dispatch, SetStateAction } from "react";
import type { XlsxPivotNumberGroup } from "@open-document/web/xlsx";
import type { UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function PivotNumberGroups({
  groups,
  setGroups,
  axes,
  state,
}: {
  groups: XlsxPivotNumberGroup[];
  setGroups: Dispatch<SetStateAction<XlsxPivotNumberGroup[]>>;
  axes: number[];
  state: UiSnapshot;
}) {
  const t = messages(state.locale);
  const update = (at: number, patch: Partial<XlsxPivotNumberGroup>) =>
    setGroups(
      groups.map((group, i) => (i === at ? { ...group, ...patch } : group)),
    );
  return (
    <>
      {groups.map((group, index) => (
        <fieldset key={index}>
          <legend>
            {t.pivotNumberGroup} {index + 1}
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
          {(["start", "end", "interval"] as const).map((key) => (
            <label key={key}>
              {t[`pivotGroup_${key}`]}
              <input
                type="number"
                step="any"
                value={Number.isFinite(group[key]) ? group[key] : ""}
                onChange={(event) =>
                  update(index, { [key]: event.currentTarget.valueAsNumber })
                }
              />
            </label>
          ))}
          <button
            type="button"
            onClick={() => setGroups(groups.filter((_, i) => i !== index))}
          >
            {t.pivotRemoveNumberGroup}
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
            setGroups([...groups, { field, start: 0, end: 100, interval: 10 }]);
        }}
      >
        {t.pivotAddNumberGroup}
      </button>
    </>
  );
}
