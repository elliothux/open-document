import { record } from "./validation.js";
import { checkChartSettings as checkPptxChart } from "./chart.js";
export {
  checkChartSettings as checkPptxChart,
  type ChartSettings as PptxChart,
} from "./chart.js";

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
    ...("legend" in change ? { legend: change.legend } : {}),
  });
  const insert = change.action === "insertChart";
  const keys = insert
    ? ["action", "kind", "title", "data", "x", "y", "width", "height"]
    : ["action", "kind", "title", "data"];
  if ("holeSize" in change) keys.push("holeSize");
  if ("legend" in change) keys.push("legend");
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
