import { useState } from "react";
import type { XlsxFilterColumn, XlsxRankFilter } from "@open-document/web/xlsx";
import type { UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function XlsxRankFilterForm({
  criterion,
  column,
  apply,
  disabled,
  state,
}: {
  criterion: XlsxFilterColumn | undefined;
  column: number;
  apply: (rule: XlsxRankFilter) => void;
  disabled: boolean;
  state: UiSnapshot;
}) {
  const t = messages(state.locale);
  const [draft, setDraft] = useState<XlsxRankFilter>(
    criterion?.kind === "rank"
      ? criterion
      : { kind: "rank", column, value: 10, top: true, percent: false },
  );
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        apply(draft);
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.filterRank}</legend>
        <p>{t.filterRankHelp}</p>
        <label>
          {t.filterRankDirection}
          <select
            value={draft.top ? "top" : "bottom"}
            onChange={(event) =>
              setDraft({ ...draft, top: event.currentTarget.value === "top" })
            }
          >
            <option value="top">{t.filterRankTop}</option>
            <option value="bottom">{t.filterRankBottom}</option>
          </select>
        </label>
        <label>
          {t.filterRankMode}
          <select
            value={draft.percent ? "percent" : "items"}
            onChange={(event) =>
              setDraft({
                ...draft,
                percent: event.currentTarget.value === "percent",
                value: Math.min(
                  draft.value,
                  event.currentTarget.value === "percent" ? 100 : 500,
                ),
              })
            }
          >
            <option value="items">{t.filterRankItems}</option>
            <option value="percent">{t.filterRankPercent}</option>
          </select>
        </label>
        <label>
          {t.filterRankAmount}
          <input
            type="number"
            min={1}
            max={draft.percent ? 100 : 500}
            step={1}
            required
            value={draft.value}
            onChange={(event) =>
              setDraft({ ...draft, value: event.currentTarget.valueAsNumber })
            }
          />
        </label>
        <button type="submit">{t.filterRankApply}</button>
      </fieldset>
    </form>
  );
}
