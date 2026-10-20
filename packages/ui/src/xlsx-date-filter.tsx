import { useState } from "react";
import type {
  XlsxCalendarFilter,
  XlsxDateFilter,
  XlsxFilterColumn,
  XlsxRelativeDateFilter,
} from "@open-document/web/xlsx";
import { xlsxRelativeDatePeriods } from "@open-document/web/xlsx";
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
  apply: (
    rule: XlsxDateFilter | XlsxCalendarFilter | XlsxRelativeDateFilter,
  ) => void;
  disabled: boolean;
  state: UiSnapshot;
}) {
  const t = messages(state.locale);
  const initial = criterion?.kind === "dates" ? criterion : undefined;
  const [groups, setGroups] = useState(initial?.groups.join("\n") ?? "");
  const [values, setValues] = useState(initial?.values.join("\n") ?? "");
  const [blank, setBlank] = useState(initial?.blank ?? false);
  return (
    <>
      <RelativeFilter
        criterion={criterion}
        column={column}
        apply={apply}
        disabled={disabled}
        state={state}
      />
      <CalendarFilter
        criterion={criterion}
        column={column}
        apply={apply}
        disabled={disabled}
        state={state}
      />
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
    </>
  );
}

function RelativeFilter({
  criterion,
  column,
  apply,
  disabled,
  state,
}: {
  criterion: XlsxFilterColumn | undefined;
  column: number;
  apply: (rule: XlsxRelativeDateFilter) => void;
  disabled: boolean;
  state: UiSnapshot;
}) {
  const t = messages(state.locale);
  const labels = {
    yesterday: t.filterRelativeYesterday,
    today: t.filterRelativeToday,
    tomorrow: t.filterRelativeTomorrow,
    lastWeek: t.filterRelativeLastWeek,
    thisWeek: t.filterRelativeThisWeek,
    nextWeek: t.filterRelativeNextWeek,
    lastMonth: t.filterRelativeLastMonth,
    thisMonth: t.filterRelativeThisMonth,
    nextMonth: t.filterRelativeNextMonth,
    lastQuarter: t.filterRelativeLastQuarter,
    thisQuarter: t.filterRelativeThisQuarter,
    nextQuarter: t.filterRelativeNextQuarter,
    lastYear: t.filterRelativeLastYear,
    thisYear: t.filterRelativeThisYear,
    nextYear: t.filterRelativeNextYear,
    yearToDate: t.filterRelativeYearToDate,
  };
  const [period, setPeriod] = useState<XlsxRelativeDateFilter["period"]>(
    criterion?.kind === "relativeDate" ? criterion.period : "today",
  );
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        apply({ kind: "relativeDate", column, period });
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.filterRelative}</legend>
        <p>{t.filterRelativeHelp}</p>
        <label>
          {t.filterRelativePeriod}
          <select
            aria-label={t.filterRelativePeriod}
            value={period}
            onChange={(event) => {
              const period = xlsxRelativeDatePeriods.find(
                (period) => period === event.currentTarget.value,
              );
              if (period) setPeriod(period);
            }}
          >
            {xlsxRelativeDatePeriods.map((period) => (
              <option key={period} value={period}>
                {labels[period]}
              </option>
            ))}
          </select>
        </label>
        <button type="submit">{t.filterRelativeApply}</button>
      </fieldset>
    </form>
  );
}

function CalendarFilter({
  criterion,
  column,
  apply,
  disabled,
  state,
}: {
  criterion: XlsxFilterColumn | undefined;
  column: number;
  apply: (rule: XlsxCalendarFilter) => void;
  disabled: boolean;
  state: UiSnapshot;
}) {
  const t = messages(state.locale);
  const initial = criterion?.kind === "calendar" ? criterion : undefined;
  const [unit, setUnit] = useState<"month" | "quarter">(
    initial?.unit ?? "month",
  );
  const [value, setValue] = useState(initial?.value ?? 1);
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        apply({ kind: "calendar", column, unit, value });
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.filterCalendar}</legend>
        <p>{t.filterCalendarHelp}</p>
        <label>
          {t.filterCalendarUnit}
          <select
            aria-label={t.filterCalendarUnit}
            value={unit}
            onChange={(event) => {
              const unit =
                event.currentTarget.value === "month" ? "month" : "quarter";
              setUnit(unit);
              setValue(Math.min(value, unit === "month" ? 12 : 4));
            }}
          >
            <option value="month">{t.filterCalendarMonth}</option>
            <option value="quarter">{t.filterCalendarQuarter}</option>
          </select>
        </label>
        <label>
          {t.filterCalendarValue}
          <select
            aria-label={t.filterCalendarValue}
            value={value}
            onChange={(event) => setValue(Number(event.currentTarget.value))}
          >
            {Array.from({ length: unit === "month" ? 12 : 4 }, (_, index) => (
              <option key={index + 1} value={index + 1}>
                {index + 1}
              </option>
            ))}
          </select>
        </label>
        <button type="submit">{t.filterCalendarApply}</button>
      </fieldset>
    </form>
  );
}
