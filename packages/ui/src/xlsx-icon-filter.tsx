import { useState } from "react";
import {
  conditionalIconSets,
  type XlsxFilterColumn,
  type XlsxIconFilter,
  type XlsxIconSet,
} from "@open-document/web/xlsx";
import type { UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { conditionalIconLabels } from "./conditional-icons.js";

export function XlsxIconFilterForm({
  criterion,
  column,
  apply,
  disabled,
  state,
}: {
  criterion: XlsxFilterColumn | undefined;
  column: number;
  apply: (rule: XlsxIconFilter) => void;
  disabled: boolean;
  state: UiSnapshot;
}) {
  const t = messages(state.locale),
    initial = criterion?.kind === "icon" ? criterion : undefined;
  const [iconSet, setIconSet] = useState<XlsxIconSet["kind"]>(
    initial?.iconSet ?? "3Arrows",
  );
  const [iconId, setIconId] = useState<number | null>(
    initial ? initial.iconId : 2,
  );
  const labels = conditionalIconLabels(t);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        apply({ kind: "icon", column, iconSet, iconId });
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.filterIcons}</legend>
        <label>
          {t.filterIconSet}
          <select
            aria-label={t.filterIconSet}
            value={iconSet}
            onChange={(event) => {
              const set = conditionalIconSets.find(
                (set) => set === event.currentTarget.value,
              );
              if (set) {
                setIconSet(set);
                setIconId((id) =>
                  id === null ? null : Math.min(id, Number(set[0]) - 1),
                );
              }
            }}
          >
            {conditionalIconSets.map((set, index) => (
              <option key={set} value={set}>
                {labels[index]}
              </option>
            ))}
          </select>
        </label>
        <label>
          {t.filterIconIndex}
          <select
            aria-label={t.filterIconIndex}
            value={iconId ?? 0}
            disabled={iconId === null}
            onChange={(event) => setIconId(Number(event.currentTarget.value))}
          >
            {Array.from({ length: Number(iconSet[0]) }, (_, index) => (
              <option key={index} value={index}>
                {index + 1}
              </option>
            ))}
          </select>
        </label>
        <label>
          <input
            type="checkbox"
            checked={iconId === null}
            onChange={(event) =>
              setIconId(event.currentTarget.checked ? null : 2)
            }
          />
          {t.sortNoIcon}
        </label>
        <p>{t.sortIconHelp}</p>
        <button type="submit">{t.filterIconApply}</button>
      </fieldset>
    </form>
  );
}
