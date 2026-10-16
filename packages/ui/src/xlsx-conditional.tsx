import { useState } from "react";
import type { SpreadsheetEditor } from "@open-document/web/spreadsheet-editor";
import {
  validationOperators,
  xlsxNumberFormats,
  type XlsxConditionalFormat,
  type XlsxCellFormat,
  conditionalThresholds,
  type XlsxConditionalStop,
} from "@open-document/web/xlsx";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

function scaleStops(): XlsxConditionalStop[] {
  return [
    { kind: "min", value: "", color: "ff0000" },
    { kind: "max", value: "", color: "00ff00" },
  ];
}

function ColorScaleFields({
  rule,
  update,
  locale,
}: {
  rule: XlsxConditionalFormat;
  update: (rule: XlsxConditionalFormat) => void;
  locale: UiSnapshot["locale"];
}) {
  const t = messages(locale),
    stops = rule.stops ?? scaleStops();
  const labels = [
    t.conditionalMin,
    t.conditionalMax,
    t.conditionalNumber,
    t.conditionalPercent,
    t.conditionalPercentile,
    t.conditionalFormula,
  ];
  const set = (index: number, patch: Partial<XlsxConditionalStop>) =>
    update({
      ...rule,
      stops: stops.map((stop, i) =>
        i === index ? { ...stop, ...patch } : stop,
      ),
    });
  return (
    <fieldset>
      <legend>{t.conditionalColorScale}</legend>
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
          <label>
            {t.conditionalStopColor}
            <input
              aria-label={`${t.conditionalStopColor} ${index + 1}`}
              pattern="[0-9A-Fa-f]{6}"
              value={stop.color}
              onChange={(e) => set(index, { color: e.currentTarget.value })}
            />
          </label>
        </fieldset>
      ))}
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
                {r.rule.kind === "colorScale"
                  ? t.conditionalColorScale
                  : r.rule.formula1}
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
              onChange={(e) =>
                setRule(
                  e.currentTarget.value === "colorScale"
                    ? {
                        kind: "colorScale",
                        operator: "",
                        formula1: "",
                        formula2: "",
                        stopIfTrue: false,
                        format: {},
                        stops: scaleStops(),
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
                          rule.kind === "colorScale"
                            ? { fill: "fff2cc" }
                            : rule.format,
                      },
                )
              }
            >
              <option value="cellIs">{t.conditionalValue}</option>
              <option value="expression">{t.conditionalFormula}</option>
              <option value="colorScale">{t.conditionalColorScale}</option>
            </select>
          </label>
          {rule.kind === "colorScale" ? (
            <ColorScaleFields
              rule={rule}
              update={setRule}
              locale={state.locale}
            />
          ) : (
            <>
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
