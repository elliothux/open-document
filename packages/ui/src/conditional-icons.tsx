import {
  conditionalIconSets,
  conditionalThresholds,
  type XlsxConditionalFormat,
  type XlsxIconSet,
} from "@open-document/web/xlsx";
import type { UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function initialConditionalIcons(): XlsxIconSet {
  return {
    kind: "3Arrows",
    reverse: false,
    showValue: true,
    percent: true,
    thresholds: [0, 33, 67].map((value) => ({
      kind: "percent",
      value: String(value),
      greaterOrEqual: true,
    })),
  };
}

export function ConditionalIconFields({
  rule,
  update,
  locale,
}: {
  rule: XlsxConditionalFormat;
  update: (rule: XlsxConditionalFormat) => void;
  locale: UiSnapshot["locale"];
}) {
  const t = messages(locale),
    icons = rule.icons ?? initialConditionalIcons();
  const labels = [
    t.conditionalMin,
    t.conditionalMax,
    t.conditionalNumber,
    t.conditionalPercent,
    t.conditionalPercentile,
    t.conditionalFormula,
  ];
  const kinds = [
    t.conditionalArrows,
    t.conditionalTrafficLights,
    t.conditionalFlags,
  ];
  const set = (icons: XlsxIconSet) => update({ ...rule, icons });
  return (
    <fieldset>
      <legend>{t.conditionalIconSet}</legend>
      <label>
        {t.conditionalIconKind}
        <select
          aria-label={t.conditionalIconKind}
          value={icons.kind}
          onChange={(event) => {
            const kind = conditionalIconSets.find(
              (kind) => kind === event.currentTarget.value,
            );
            if (kind) set({ ...icons, kind });
          }}
        >
          {conditionalIconSets.map((kind, index) => (
            <option key={kind} value={kind}>
              {kinds[index]}
            </option>
          ))}
        </select>
      </label>
      <label>
        <input
          type="checkbox"
          checked={icons.reverse}
          onChange={(event) =>
            set({ ...icons, reverse: event.currentTarget.checked })
          }
        />
        {t.conditionalReverseIcons}
      </label>
      <label>
        <input
          type="checkbox"
          checked={icons.showValue}
          onChange={(event) =>
            set({ ...icons, showValue: event.currentTarget.checked })
          }
        />
        {t.conditionalShowValue}
      </label>
      {icons.thresholds.map((threshold, index) => (
        <fieldset key={index}>
          <legend>
            {t.conditionalThreshold} {index + 1}
          </legend>
          <label>
            {t.conditionalThreshold}
            <select
              aria-label={`${t.conditionalThreshold} ${index + 1}`}
              value={threshold.kind}
              onChange={(event) => {
                const kind = conditionalThresholds.find(
                  (kind) => kind === event.currentTarget.value,
                );
                if (kind)
                  set({
                    ...icons,
                    thresholds: icons.thresholds.map((old, at) =>
                      at === index
                        ? {
                            ...old,
                            kind,
                            value:
                              kind === "min" || kind === "max"
                                ? ""
                                : old.value || "0",
                          }
                        : old,
                    ),
                  });
              }}
            >
              {conditionalThresholds.map((kind, index) => (
                <option key={kind} value={kind}>
                  {labels[index]}
                </option>
              ))}
            </select>
          </label>
          {threshold.kind !== "min" && threshold.kind !== "max" && (
            <label>
              {t.conditionalThresholdValue}
              <input
                aria-label={`${t.conditionalThresholdValue} ${index + 1}`}
                value={threshold.value}
                onChange={(event) =>
                  set({
                    ...icons,
                    thresholds: icons.thresholds.map((old, at) =>
                      at === index
                        ? { ...old, value: event.currentTarget.value }
                        : old,
                    ),
                  })
                }
              />
            </label>
          )}
          <label>
            <input
              type="checkbox"
              aria-label={`${t.conditionalInclusive} ${index + 1}`}
              checked={threshold.greaterOrEqual}
              onChange={(event) =>
                set({
                  ...icons,
                  thresholds: icons.thresholds.map((old, at) =>
                    at === index
                      ? { ...old, greaterOrEqual: event.currentTarget.checked }
                      : old,
                  ),
                })
              }
            />
            {t.conditionalInclusive}
          </label>
        </fieldset>
      ))}
    </fieldset>
  );
}
