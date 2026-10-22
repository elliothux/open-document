import { record, integer } from "./validation.js";

export interface PptxChart {
  kind:
    | "column"
    | "bar"
    | "stackedColumn"
    | "stackedBar"
    | "percentStackedColumn"
    | "percentStackedBar"
    | "line"
    | "pie"
    | "area"
    | "scatter"
    | "radar"
    | "doughnut";
  title: string;
  /** TSV: header row, category column (numeric X for scatter), then 1-8 numeric series. Pie displays the first series by absolute value. */
  data: string;
  /** Doughnut only: integer percentage from 10 to 90, default 75. Each series draws a ring, innermost first. */
  holeSize?: number;
}

export function checkPptxChart(value: unknown): void {
  const chart = record(value);
  if (
    (Object.keys(chart).length !== 3 && Object.keys(chart).length !== 4) ||
    Object.keys(chart).some(
      (key) => !["kind", "title", "data", "holeSize"].includes(key),
    ) ||
    ![
      "column",
      "bar",
      "stackedColumn",
      "stackedBar",
      "percentStackedColumn",
      "percentStackedBar",
      "line",
      "pie",
      "area",
      "scatter",
      "radar",
      "doughnut",
    ].some((kind) => kind === chart.kind) ||
    ("holeSize" in chart &&
      (chart.kind !== "doughnut" || !integer(chart.holeSize, 10, 90))) ||
    typeof chart.title !== "string" ||
    chart.title.length > 256 ||
    /[\r\n]/.test(chart.title) ||
    typeof chart.data !== "string" ||
    !chart.data.length ||
    chart.data.length > 65536 ||
    ![chart.title, chart.data].every(
      (text) =>
        text.isWellFormed() &&
        Array.from(text).every(
          (c) => c.charCodeAt(0) >= 32 || ["\t", "\n", "\r"].includes(c),
        ),
    )
  )
    throw new Error("Invalid presentation chart");
}

export function checkPptxChartEdit(value: unknown): boolean {
  const change = record(value);
  if (
    change.action !== "insertChart" &&
    change.action !== "chartData" &&
    change.action !== "fillChart"
  )
    return false;
  checkPptxChart({
    kind: change.kind,
    title: change.title,
    data: change.data,
    ...("holeSize" in change ? { holeSize: change.holeSize } : {}),
  });
  const insert = change.action === "insertChart";
  const keys = insert
    ? ["action", "kind", "title", "data", "x", "y", "width", "height"]
    : ["action", "kind", "title", "data"];
  if ("holeSize" in change) keys.push("holeSize");
  if (
    Object.keys(change).length !== keys.length ||
    Object.keys(change).some((key) => !keys.includes(key))
  )
    throw new Error("Invalid chart edit fields");
  if (insert)
    for (const [key, low, high] of [
      ["x", -14400, 14400],
      ["y", -14400, 14400],
      ["width", 180, 14400],
      ["height", 150, 14400],
    ] as const) {
      const number = change[key];
      if (
        typeof number !== "number" ||
        !Number.isFinite(number) ||
        number < low ||
        number > high
      )
        throw new Error("Invalid chart frame");
    }
  return true;
}
