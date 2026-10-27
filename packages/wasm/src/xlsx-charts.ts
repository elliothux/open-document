import type { ChartSettings } from "./chart.js";
import { integer, record } from "./validation.js";
import { noteText } from "./xlsx-sheet.js";
import {
  checkXlsxPictureSettings,
  type XlsxPictureSettings,
} from "./xlsx-pictures.js";

export const xlsxChartKinds = [
  "column",
  "bar",
  "stackedColumn",
  "stackedBar",
  "percentStackedColumn",
  "percentStackedBar",
  "line",
  "stackedLine",
  "percentStackedLine",
  "pie",
  "area",
  "stackedArea",
  "percentStackedArea",
  "scatter",
  "radar",
  "doughnut",
] as const satisfies readonly ChartSettings["kind"][];
export interface XlsxChartSettings {
  kind: ChartSettings["kind"];
  title: string;
  label: string;
  legend: "none" | "top" | "bottom" | "left" | "right";
  holeSize: number | null;
  categories: string;
  names: string[];
  values: string[];
}
export type XlsxChartFrame = Omit<XlsxPictureSettings, "crop">;
export interface XlsxChart extends XlsxChartSettings, XlsxChartFrame {
  id: string;
  data: string;
  bindingReason: string;
}
export interface XlsxCharts {
  revision: number;
  sheet: string;
  reason: string;
  items: XlsxChart[];
}

export function checkXlsxChartSettings(
  value: unknown,
): asserts value is XlsxChartSettings {
  const c = record(value);
  if (
    Object.keys(c).length !== 8 ||
    Object.keys(c).some(
      (key) =>
        ![
          "kind",
          "title",
          "label",
          "legend",
          "holeSize",
          "categories",
          "names",
          "values",
        ].includes(key),
    ) ||
    !xlsxChartKinds.some((kind) => kind === c.kind) ||
    !noteText(c.title, 256) ||
    !noteText(c.label, 256) ||
    /[\r\n]/.test(String(c.title) + String(c.label)) ||
    !["none", "top", "bottom", "left", "right"].some(
      (legend) => legend === c.legend,
    ) ||
    (c.kind === "doughnut"
      ? !integer(c.holeSize, 10, 90)
      : c.holeSize !== null) ||
    !noteText(c.categories, 1024) ||
    !c.categories ||
    !Array.isArray(c.names) ||
    c.names.length < 1 ||
    c.names.length > 8 ||
    !Array.isArray(c.values) ||
    c.values.length !== c.names.length ||
    ![...c.names, ...c.values].every(
      (value) => noteText(value, 1024) && value.length > 0,
    )
  )
    throw new Error("Invalid worksheet chart settings");
}
export function checkXlsxChartFrame(
  value: unknown,
): asserts value is XlsxChartFrame {
  checkXlsxPictureSettings({ ...record(value), crop: [0, 0, 0, 0] });
}
export function xlsxCharts(value: unknown): XlsxCharts {
  const catalog = record(value);
  if (
    !integer(catalog.revision, 0, 2147483647) ||
    typeof catalog.sheet !== "string" ||
    typeof catalog.reason !== "string" ||
    !Array.isArray(catalog.items) ||
    catalog.items.length > 256
  )
    throw new Error("Invalid worksheet chart catalog");
  const ids = new Set<string>();
  for (const value of catalog.items) {
    const c = record(value);
    const id = c.id,
      data = c.data,
      bindingReason = c.bindingReason;
    checkXlsxChartSettings({
      kind: c.kind,
      title: c.title,
      label: c.label,
      legend: c.legend,
      holeSize: c.holeSize,
      categories: c.categories,
      names: c.names,
      values: c.values,
    });
    checkXlsxChartFrame(c);
    if (
      typeof id !== "string" ||
      !/^[1-9][0-9]*$/.test(id) ||
      ids.has(id) ||
      !noteText(data, 65536) ||
      !noteText(bindingReason, 1024)
    )
      throw new Error("Invalid worksheet chart identity or data");
    ids.add(id);
  }
  return value as XlsxCharts;
}
