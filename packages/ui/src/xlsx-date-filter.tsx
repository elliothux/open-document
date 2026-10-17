import { useState } from "react";
import type { XlsxDateFilter, XlsxFilterColumn } from "@open-document/web/xlsx";
import type { UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function XlsxDateFilterForm({
  criterion,
  column,
  apply,
  disabled,
  state,
}: {
  criterion: XlsxFilterColumn | undefined;
  column: number;
  apply: (rule: XlsxDateFilter) => void;
  disabled: boolean;
  state: UiSnapshot;
}) {
  const t = messages(state.locale);
  const initial = criterion?.kind === "dates" ? criterion : undefined;
  const [groups, setGroups] = useState(initial?.groups.join("\n") ?? "");
  const [values, setValues] = useState(initial?.values.join("\n") ?? "");
  const [blank, setBlank] = useState(initial?.blank ?? false);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        apply({
          kind: "dates",
          column,
          groups: groups
            .split("\n")
            .map((value) => value.trim())
            .filter(Boolean),
          values: values.split("\n").filter((value) => value.length > 0),
          blank,
        });
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.filterDates}</legend>
        <p>{t.filterDateHelp}</p>
        <label>
          {t.filterDateGroups}
          <textarea
            aria-label={t.filterDateGroups}
            value={groups}
            maxLength={81920}
            rows={3}
            required
            onChange={(event) => setGroups(event.currentTarget.value)}
          />
        </label>
        <label>
          {t.filterDateLabels}
          <textarea
            aria-label={t.filterDateLabels}
            value={values}
            maxLength={1048576}
            rows={2}
            onChange={(event) => setValues(event.currentTarget.value)}
          />
        </label>
        <label>
          <input
            type="checkbox"
            checked={blank}
            onChange={(event) => setBlank(event.currentTarget.checked)}
          />
          {t.filterBlank}
        </label>
        <button type="submit" disabled={!groups.trim()}>
          {t.filterDateApply}
        </button>
      </fieldset>
    </form>
  );
}
