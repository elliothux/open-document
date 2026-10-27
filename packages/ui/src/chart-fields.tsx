import type { ChartSettings } from "@open-document/web/foundation";
import type { ReactNode } from "react";
import type { messages } from "./messages.js";
export const initialChart: ChartSettings = {
  kind: "column",
  title: "Chart",
  data: "Category\tSeries 1\tSeries 2\nA\t10\t20\nB\t15\t5",
};
export function ChartFields({
  draft,
  setDraft,
  t,
  children,
}: {
  draft: ChartSettings;
  setDraft(value: ChartSettings): void;
  t: ReturnType<typeof messages>;
  children?: ReactNode;
}) {
  return (
    <>
      <label>
        {t.chartLegend}
        <select
          aria-label={t.chartLegend}
          value={
            draft.legend ??
            (["pie", "doughnut"].includes(draft.kind) ? "right" : "bottom")
          }
          onChange={(event) => {
            const legend = event.currentTarget.value;
            if (
              legend === "none" ||
              legend === "top" ||
              legend === "bottom" ||
              legend === "left" ||
              legend === "right"
            )
              setDraft({ ...draft, legend });
          }}
        >
          <option value="none">{t.chartLegendNone}</option>
          <option value="top">{t.chartLegendTop}</option>
          <option value="bottom">{t.chartLegendBottom}</option>
          <option value="left">{t.chartLegendLeft}</option>
          <option value="right">{t.chartLegendRight}</option>
        </select>
      </label>
      <label>
        {t.chartKind}
        <select
          aria-label={t.chartKind}
          value={draft.kind}
          onChange={(event) => {
            const kind = event.currentTarget.value;
            if (
              kind === "column" ||
              kind === "bar" ||
              kind === "stackedColumn" ||
              kind === "stackedBar" ||
              kind === "percentStackedColumn" ||
              kind === "percentStackedBar" ||
              kind === "line" ||
              kind === "stackedLine" ||
              kind === "percentStackedLine" ||
              kind === "area" ||
              kind === "stackedArea" ||
              kind === "percentStackedArea" ||
              kind === "scatter" ||
              kind === "radar" ||
              kind === "doughnut" ||
              kind === "pie"
            ) {
              const { holeSize: _holeSize, ...settings } = draft;
              setDraft(
                kind === "doughnut"
                  ? { ...settings, kind, holeSize: draft.holeSize ?? 75 }
                  : { ...settings, kind },
              );
            }
          }}
        >
          <option value="column">{t.chartColumn}</option>
          <option value="bar">{t.chartBar}</option>
          <option value="stackedColumn">{t.chartStackedColumn}</option>
          <option value="stackedBar">{t.chartStackedBar}</option>
          <option value="percentStackedColumn">
            {t.chartPercentStackedColumn}
          </option>
          <option value="percentStackedBar">{t.chartPercentStackedBar}</option>
          <option value="line">{t.chartLine}</option>
          <option value="stackedLine">{t.chartStackedLine}</option>
          <option value="percentStackedLine">
            {t.chartPercentStackedLine}
          </option>
          <option value="pie">{t.chartPie}</option>
          <option value="doughnut">{t.chartDoughnut}</option>
          <option value="area">{t.chartArea}</option>
          <option value="stackedArea">{t.chartStackedArea}</option>
          <option value="percentStackedArea">
            {t.chartPercentStackedArea}
          </option>
          <option value="scatter">{t.chartScatter}</option>
          <option value="radar">{t.chartRadar}</option>
        </select>
      </label>
      {draft.kind === "doughnut" && (
        <label>
          {t.chartHoleSize}
          <input
            aria-label={t.chartHoleSize}
            type="number"
            min={10}
            max={90}
            step={1}
            required
            value={draft.holeSize ?? 75}
            onChange={(event) =>
              setDraft({
                ...draft,
                holeSize: event.currentTarget.valueAsNumber,
              })
            }
          />
        </label>
      )}
      <label>
        {t.chartTitle}
        <input
          aria-label={t.chartTitle}
          maxLength={256}
          value={draft.title}
          onChange={(event) =>
            setDraft({ ...draft, title: event.currentTarget.value })
          }
        />
      </label>
      {children ?? (
        <>
          <label>
            {t.chartData}
            <textarea
              aria-label={t.chartData}
              maxLength={65536}
              rows={6}
              value={draft.data}
              onChange={(event) =>
                setDraft({ ...draft, data: event.currentTarget.value })
              }
            />
          </label>
          <p>{t.chartDataHint}</p>
        </>
      )}
      {draft.kind === "pie" && <p>{t.chartPieHint}</p>}
      {draft.kind === "doughnut" && <p>{t.chartDoughnutHint}</p>}
      {draft.kind === "scatter" && <p>{t.chartScatterHint}</p>}
    </>
  );
}
