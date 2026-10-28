import type { XlsxConditionalFormat } from "../web/xlsx.js";
import type { UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function ConditionalStatisticsFields({
  rule,
  update,
  locale,
}: {
  rule: XlsxConditionalFormat;
  update: (rule: XlsxConditionalFormat) => void;
  locale: UiSnapshot["locale"];
}) {
  const t = messages(locale);
  if (rule.rank) {
    const rank = rule.rank;
    return (
      <fieldset>
        <legend>{t.conditionalRank}</legend>
        <label>
          {t.conditionalRankCount}
          <input
            type="number"
            min={1}
            max={rank.percent ? 100 : 1000}
            step={1}
            value={Number.isFinite(rank.rank) ? rank.rank : ""}
            onChange={(e) =>
              update({
                ...rule,
                rank: { ...rank, rank: e.currentTarget.valueAsNumber },
              })
            }
          />
        </label>
        <label>
          <input
            type="checkbox"
            checked={rank.percent}
            onChange={(e) =>
              update({
                ...rule,
                rank: { ...rank, percent: e.currentTarget.checked },
              })
            }
          />
          {t.conditionalRankPercent}
        </label>
        <label>
          <input
            type="checkbox"
            checked={rank.bottom}
            onChange={(e) =>
              update({
                ...rule,
                rank: { ...rank, bottom: e.currentTarget.checked },
              })
            }
          />
          {t.conditionalRankBottom}
        </label>
      </fieldset>
    );
  }
  if (rule.average) {
    const average = rule.average;
    return (
      <fieldset>
        <legend>{t.conditionalAverage}</legend>
        <label>
          <input
            type="checkbox"
            checked={average.above}
            onChange={(e) =>
              update({
                ...rule,
                average: { ...average, above: e.currentTarget.checked },
              })
            }
          />
          {t.conditionalAbove}
        </label>
        <label>
          <input
            type="checkbox"
            checked={average.equal}
            onChange={(e) =>
              update({
                ...rule,
                average: { ...average, equal: e.currentTarget.checked },
              })
            }
          />
          {t.conditionalEqualAverage}
        </label>
        <label>
          {t.conditionalStdDev}
          <input
            type="number"
            min={0}
            max={3}
            step={1}
            value={Number.isFinite(average.stdDev) ? average.stdDev : ""}
            onChange={(e) =>
              update({
                ...rule,
                average: { ...average, stdDev: e.currentTarget.valueAsNumber },
              })
            }
          />
        </label>
      </fieldset>
    );
  }
  return null;
}
