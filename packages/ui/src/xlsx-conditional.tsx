import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import {
  validationOperators,
  xlsxNumberFormats,
  type XlsxConditionalFormat,
  type XlsxCellFormat,
  conditionalThresholds,
  conditionalDatePeriods,
  type XlsxConditionalStop,
} from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import { ConditionalStatisticsFields } from "./conditional-statistics.js";
import {
  ConditionalIconFields,
  initialConditionalIcons,
} from "./conditional-icons.js";

function scaleStops(): XlsxConditionalStop[] {
  return [
    { kind: "min", value: "", color: "ff0000" },
    { kind: "max", value: "", color: "00ff00" },
  ];
}

function VisualRuleFields({
  rule,
  update,
  locale,
}: {
  rule: XlsxConditionalFormat;
  update: (rule: XlsxConditionalFormat) => void;
  locale: UiSnapshot["locale"];
}) {
  const t = messages(locale),
    bar = rule.bar,
    stops = bar
      ? [
          { ...bar.minimum, color: bar.color },
          { ...bar.maximum, color: bar.color },
        ]
      : (rule.stops ?? scaleStops());
  const labels = [
    t.conditionalMin,
    t.conditionalMax,
    t.conditionalNumber,
    t.conditionalPercent,
    t.conditionalPercentile,
    t.conditionalFormula,
  ];
  const set = (index: number, patch: Partial<XlsxConditionalStop>) =>
    update(
      bar
        ? {
            ...rule,
            bar: {
              ...bar,
              [index === 0 ? "minimum" : "maximum"]: {
                kind: patch.kind ?? stops[index]!.kind,
                value: patch.value ?? stops[index]!.value,
              },
            },
          }
        : {
            ...rule,
            stops: stops.map((stop, i) =>
              i === index ? { ...stop, ...patch } : stop,
            ),
          },
    );
  return (
    <fieldset>
      <legend>{bar ? t.conditionalDataBar : t.conditionalColorScale}</legend>
      {!bar && (
        <label>
          {t.conditionalStopCount}
          <select
            aria-label={t.conditionalStopCount}
            value={stops.length}
            onChange={(e) =>
              update({
                ...rule,
                stops:
                  e.currentTarget.value === "3"
                    ? [
                        stops[0]!,
                        { kind: "percentile", value: "50", color: "ffff00" },
                        stops[stops.length - 1]!,
                      ]
                    : [stops[0]!, stops[stops.length - 1]!],
              })
            }
          >
            <option value="2">2</option>
            <option value="3">3</option>
          </select>
        </label>
      )}
      {stops.map((stop, index) => (
        <fieldset key={index}>
          <legend>
            {t.conditionalThreshold} {index + 1}
          </legend>
          <label>
            {t.conditionalThreshold}
            <select
              aria-label={`${t.conditionalThreshold} ${index + 1}`}
              value={stop.kind}
              onChange={(e) => {
                const kind = conditionalThresholds.find(
                  (k) => k === e.currentTarget.value,
                );
                if (kind)
                  set(index, {
                    kind,
                    value:
                      kind === "min" || kind === "max"
                        ? ""
                        : stop.value || "50",
                  });
              }}
            >
              {conditionalThresholds.map((kind, i) => (
                <option key={kind} value={kind}>
                  {labels[i]}
                </option>
              ))}
            </select>
          </label>
          {stop.kind !== "min" && stop.kind !== "max" && (
            <label>
              {t.conditionalThresholdValue}
              <input
                aria-label={`${t.conditionalThresholdValue} ${index + 1}`}
                value={stop.value}
                onChange={(e) => set(index, { value: e.currentTarget.value })}
              />
            </label>
          )}
          {!bar && (
            <label>
              {t.conditionalStopColor}
              <input
                aria-label={`${t.conditionalStopColor} ${index + 1}`}
                pattern="[0-9A-Fa-f]{6}"
                value={stop.color}
                onChange={(e) => set(index, { color: e.currentTarget.value })}
              />
            </label>
          )}
        </fieldset>
      ))}
      {bar && (
        <>
          <label>
            {t.conditionalBarColor}
            <input
              aria-label={t.conditionalBarColor}
              pattern="[0-9A-Fa-f]{6}"
              value={bar.color}
              onChange={(e) =>
                update({
                  ...rule,
                  bar: { ...bar, color: e.currentTarget.value },
                })
              }
            />
          </label>
          <label>
            <input
              type="checkbox"
              checked={bar.showValue}
              onChange={(e) =>
                update({
                  ...rule,
                  bar: { ...bar, showValue: e.currentTarget.checked },
                })
              }
            />
            {t.conditionalShowValue}
          </label>
          {(
            [
              ["minLength", t.conditionalMinLength],
              ["maxLength", t.conditionalMaxLength],
            ] as const
          ).map(([key, label]) => (
            <label key={key}>
              {label}
              <input
                type="number"
                min="0"
                max="100"
                step="1"
                aria-label={label}
                value={bar[key]}
                onChange={(e) =>
                  update({
                    ...rule,
                    bar: { ...bar, [key]: e.currentTarget.valueAsNumber },
                  })
                }
              />
            </label>
          ))}
        </>
      )}
    </fieldset>
  );
}

export function XlsxConditional({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: SpreadsheetEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    query = editor.currentState,
    current = query.conditionalFormats;
  const [priority, setPriority] = useState<number | null>(null);
  const [ranges, setRanges] = useState(query.selection.address);
  const fresh = (): XlsxConditionalFormat => ({
    kind: "cellIs",
    operator: "greaterThan",
    formula1: "0",
    formula2: "",
    stopIfTrue: false,
    format: { fill: "fff2cc" },
  });
  const [rule, setRule] = useState<XlsxConditionalFormat>(fresh);
  const kinds: Record<XlsxConditionalFormat["kind"], string> = {
    cellIs: t.conditionalValue,
    expression: t.conditionalFormula,
    colorScale: t.conditionalColorScale,
    dataBar: t.conditionalDataBar,
    iconSet: t.conditionalIconSet,
    top10: t.conditionalRank,
    aboveAverage: t.conditionalAverage,
    duplicateValues: t.conditionalDuplicates,
    uniqueValues: t.conditionalUnique,
    containsBlanks: t.conditionalBlanks,
    notContainsBlanks: t.conditionalNonblanks,
    containsErrors: t.conditionalErrors,
    notContainsErrors: t.conditionalNonerrors,
    containsText: t.conditionalContains,
    notContainsText: t.conditionalNotContains,
    beginsWith: t.conditionalBegins,
    endsWith: t.conditionalEnds,
    timePeriod: t.conditionalDate,
  };
  const selected = current.rules.find((r) => r.priority === priority);
  const reason = current.readOnlyReason || selected?.readOnlyReason || "";
  const setFormat = <K extends keyof XlsxCellFormat>(
    key: K,
    value: XlsxCellFormat[K],
  ) =>
    setRule((old) => {
      const format = { ...old.format };
      if (value === undefined) delete format[key];
      else format[key] = value;
      return { ...old, format };
    });
  const operators = [
    t.validationBetween,
    t.validationNotBetween,
    t.validationEqual,
    t.validationNotEqual,
    t.validationLess,
    t.validationLessEqual,
    t.validationGreater,
    t.validationGreaterEqual,
  ];
  const pair =
    rule.kind === "cellIs" && ["between", "notBetween"].includes(rule.operator);
  const choose = (value: string) => {
    const selected = current.rules.find((r) => r.priority === Number(value));
    setPriority(selected?.priority ?? null);
    setRanges(selected?.ranges ?? query.selection.address);
    setRule(selected?.rule ?? fresh());
  };
  const apply = (settings: XlsxConditionalFormat | null, target = priority) =>
    controller.run(() =>
      editor.editSheet({
        action: "conditionalRule",
        ranges:
          target === null && settings === null
            ? query.selection.address
            : ranges,
        priority: target,
        rule: settings,
        sourceRevision: query.revision,
      }),
    );
  return (
    <section aria-label={t.conditionalFormatting}>
      <fieldset disabled={disabled}>
        <legend>{t.conditionalFormatting}</legend>
        <label>
          {t.conditionalRules}
          <select
            aria-label={t.conditionalRules}
            value={priority ?? ""}
            onChange={(e) => choose(e.currentTarget.value)}
          >
            <option value="">{t.conditionalNew}</option>
            {current.rules.map((r) => (
              <option key={r.priority} value={r.priority}>
                {r.priority}: {r.ranges} —{" "}
                {r.rule.kind === "cellIs" || r.rule.kind === "expression"
                  ? r.rule.formula1
                  : kinds[r.rule.kind]}
              </option>
            ))}
          </select>
        </label>
        <button type="button" onClick={() => choose("")}>
          {t.conditionalNew}
        </button>
        {reason && <p role="status">{reason}</p>}
        <fieldset disabled={!!reason}>
          <label>
            {t.conditionalRanges}
            <input
              aria-label={t.conditionalRanges}
              value={ranges}
              onChange={(e) => setRanges(e.currentTarget.value)}
            />
          </label>
          <label>
            {t.conditionalKind}
            <select
              aria-label={t.conditionalKind}
              value={rule.kind}
              onChange={(e) => {
                const kind = e.currentTarget.value;
                if (kind === "iconSet") {
                  setRule({
                    kind,
                    operator: "",
                    formula1: "",
                    formula2: "",
                    stopIfTrue: false,
                    format: {},
                    icons: initialConditionalIcons(),
                  });
                  return;
                }
                if (
                  kind === "top10" ||
                  kind === "aboveAverage" ||
                  kind === "duplicateValues" ||
                  kind === "uniqueValues" ||
                  kind === "containsBlanks" ||
                  kind === "notContainsBlanks" ||
                  kind === "containsErrors" ||
                  kind === "notContainsErrors" ||
                  kind === "containsText" ||
                  kind === "notContainsText" ||
                  kind === "beginsWith" ||
                  kind === "endsWith" ||
                  kind === "timePeriod"
                ) {
                  setRule({
                    kind,
                    operator: "",
                    formula1: "",
                    formula2: "",
                    stopIfTrue: rule.stopIfTrue,
                    format:
                      rule.kind === "colorScale" ||
                      rule.kind === "dataBar" ||
                      rule.kind === "iconSet"
                        ? { fill: "fff2cc" }
                        : rule.format,
                    ...(kind === "top10"
                      ? { rank: { rank: 10, percent: false, bottom: false } }
                      : kind === "aboveAverage"
                        ? { average: { above: true, equal: false, stdDev: 0 } }
                        : kind === "containsText" ||
                            kind === "notContainsText" ||
                            kind === "beginsWith" ||
                            kind === "endsWith"
                          ? { text: rule.text ?? "" }
                          : kind === "timePeriod"
                            ? { timePeriod: "today" }
                            : {}),
                  });
                  return;
                }
                setRule(
                  kind === "colorScale" || kind === "dataBar"
                    ? {
                        kind,
                        operator: "",
                        formula1: "",
                        formula2: "",
                        stopIfTrue: false,
                        format: {},
                        ...(kind === "colorScale"
                          ? { stops: scaleStops() }
                          : {
                              bar: {
                                minimum: { kind: "min", value: "" },
                                maximum: { kind: "max", value: "" },
                                color: "638ec6",
                                showValue: true,
                                minLength: 10,
                                maxLength: 90,
                              },
                            }),
                      }
                    : {
                        kind:
                          e.currentTarget.value === "expression"
                            ? "expression"
                            : "cellIs",
                        operator:
                          e.currentTarget.value === "expression"
                            ? ""
                            : "greaterThan",
                        formula1: rule.formula1 || "0",
                        formula2: "",
                        stopIfTrue: rule.stopIfTrue,
                        format:
                          rule.kind === "colorScale" ||
                          rule.kind === "dataBar" ||
                          rule.kind === "iconSet"
                            ? { fill: "fff2cc" }
                            : rule.format,
                      },
                );
              }}
            >
              {Object.entries(kinds).map(([kind, label]) => (
                <option key={kind} value={kind}>
                  {label}
                </option>
              ))}
            </select>
          </label>
          {rule.kind === "iconSet" ? (
            <ConditionalIconFields
              rule={rule}
              update={setRule}
              locale={state.locale}
            />
          ) : rule.kind === "colorScale" || rule.kind === "dataBar" ? (
            <VisualRuleFields
              rule={rule}
              update={setRule}
              locale={state.locale}
            />
          ) : (
            <>
              {rule.kind === "timePeriod" && (
                <label>
                  {t.conditionalPeriod}
                  <select
                    aria-label={t.conditionalPeriod}
                    value={rule.timePeriod}
                    onChange={(e) => {
                      const period = conditionalDatePeriods.find(
                        (period) => period === e.currentTarget.value,
                      );
                      if (period) setRule({ ...rule, timePeriod: period });
                    }}
                  >
                    {conditionalDatePeriods.map((period, index) => (
                      <option key={period} value={period}>
                        {
                          [
                            t.filterRelativeYesterday,
                            t.filterRelativeToday,
                            t.filterRelativeTomorrow,
                            t.conditionalLast7Days,
                            t.filterRelativeLastWeek,
                            t.filterRelativeThisWeek,
                            t.filterRelativeNextWeek,
                            t.filterRelativeLastMonth,
                            t.filterRelativeThisMonth,
                            t.filterRelativeNextMonth,
                          ][index]
                        }
                      </option>
                    ))}
                  </select>
                </label>
              )}
              {rule.text !== undefined && (
                <label>
                  {t.conditionalText}
                  <input
                    aria-label={t.conditionalText}
                    value={rule.text}
                    onChange={(e) =>
                      setRule({ ...rule, text: e.currentTarget.value })
                    }
                  />
                </label>
              )}
              {(rule.kind === "top10" || rule.kind === "aboveAverage") && (
                <ConditionalStatisticsFields
                  rule={rule}
                  update={setRule}
                  locale={state.locale}
                />
              )}
              {rule.kind === "cellIs" && (
                <label>
                  {t.validationOperator}
                  <select
                    aria-label={t.validationOperator}
                    value={rule.operator}
                    onChange={(e) => {
                      const operator = validationOperators.find(
                        (o) => o === e.currentTarget.value,
                      );
                      if (operator)
                        setRule((old) => ({
                          ...old,
                          operator,
                          formula2: ["between", "notBetween"].includes(operator)
                            ? old.formula2 || "10"
                            : "",
                        }));
                    }}
                  >
                    {validationOperators.map((o, i) => (
                      <option key={o} value={o}>
                        {operators[i]}
                      </option>
                    ))}
                  </select>
                </label>
              )}
              {(rule.kind === "cellIs" || rule.kind === "expression") && (
                <label>
                  {t.validationFormula1}
                  <input
                    aria-label={t.validationFormula1}
                    value={rule.formula1}
                    onChange={(e) =>
                      setRule({ ...rule, formula1: e.currentTarget.value })
                    }
                  />
                </label>
              )}
              {pair && (
                <label>
                  {t.validationFormula2}
                  <input
                    aria-label={t.validationFormula2}
                    value={rule.formula2}
                    onChange={(e) =>
                      setRule({
                        ...rule,
                        formula2: e.currentTarget.value,
                      })
                    }
                  />
                </label>
              )}
              <label>
                <input
                  type="checkbox"
                  checked={rule.stopIfTrue}
                  onChange={(e) =>
                    setRule({
                      ...rule,
                      stopIfTrue: e.currentTarget.checked,
                    })
                  }
                />
                {t.conditionalStop}
              </label>
              {(
                [
                  ["color", t.textColor],
                  ["fill", t.cellFill],
                ] as const
              ).map(([key, label]) => (
                <label key={key}>
                  {label}
                  <input
                    aria-label={t.conditionalFormatting + ": " + label}
                    value={rule.format[key] ?? ""}
                    pattern="[0-9A-Fa-f]{6}"
                    onChange={(e) =>
                      setFormat(key, e.currentTarget.value || undefined)
                    }
                  />
                </label>
              ))}
              <label>
                <input
                  type="checkbox"
                  checked={rule.format.fill === ""}
                  onChange={(e) =>
                    setFormat("fill", e.currentTarget.checked ? "" : undefined)
                  }
                />
                {t.noCellFill}
              </label>
              {(
                [
                  ["bold", t.bold],
                  ["italic", t.italic],
                  ["wrap", t.wrap],
                ] as const
              ).map(([key, label]) => (
                <label key={key}>
                  {label}
                  <select
                    aria-label={t.conditionalFormatting + ": " + label}
                    value={
                      rule.format[key] === undefined
                        ? ""
                        : String(rule.format[key])
                    }
                    onChange={(e) =>
                      setFormat(
                        key,
                        e.currentTarget.value === ""
                          ? undefined
                          : e.currentTarget.value === "true",
                      )
                    }
                  >
                    <option value="">{t.keepStyleProperty}</option>
                    <option value="true">{t.styleOn}</option>
                    <option value="false">{t.styleOff}</option>
                  </select>
                </label>
              ))}
              <label>
                {t.fontSize}
                <input
                  aria-label={t.conditionalFormatting + ": " + t.fontSize}
                  type="number"
                  min="1"
                  max="409"
                  value={rule.format.size ?? ""}
                  onChange={(e) =>
                    setFormat(
                      "size",
                      e.currentTarget.value === ""
                        ? undefined
                        : e.currentTarget.valueAsNumber,
                    )
                  }
                />
              </label>
              <label>
                {t.cellNumberFormat}
                <select
                  aria-label={
                    t.conditionalFormatting + ": " + t.cellNumberFormat
                  }
                  value={rule.format.numberFormat ?? ""}
                  onChange={(e) =>
                    setFormat(
                      "numberFormat",
                      e.currentTarget.value || undefined,
                    )
                  }
                >
                  <option value="">{t.keepStyleProperty}</option>
                  {xlsxNumberFormats.map((f) => (
                    <option key={f} value={f}>
                      {f}
                    </option>
                  ))}
                </select>
              </label>
            </>
          )}
          <button type="button" onClick={() => apply(rule)}>
            {t.conditionalApply}
          </button>
          <button
            type="button"
            disabled={priority === null}
            onClick={() => apply(null)}
          >
            {t.conditionalDelete}
          </button>
        </fieldset>
        <button
          type="button"
          disabled={!!current.readOnlyReason}
          onClick={() => apply(null, null)}
        >
          {t.conditionalClear}
        </button>
        {[
          [-1, t.conditionalUp],
          [1, t.conditionalDown],
        ].map(([step, label]) => {
          const position =
            current.rules.findIndex((r) => r.priority === priority) +
            Number(step);
          return (
            <button
              key={String(step)}
              type="button"
              disabled={
                !!reason ||
                priority === null ||
                position < 0 ||
                position >= current.rules.length
              }
              onClick={() => {
                if (priority !== null)
                  controller.run(() =>
                    editor.editSheet({
                      action: "conditionalPriority",
                      priority,
                      position,
                      sourceRevision: query.revision,
                    }),
                  );
              }}
            >
              {label}
            </button>
          );
        })}
      </fieldset>
    </section>
  );
}
