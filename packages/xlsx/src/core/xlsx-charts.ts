import type { ChartSettings } from "@open-document/wasm/abi/chart";
import { integer, record } from "@open-document/wasm/abi/validation";
import {
  xlsxChartReferenceUnits,
  xlsxChartSeriesCount,
} from "@open-document/wasm/engine-source";
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
export interface XlsxChart
  extends Omit<XlsxChartSettings, "kind">, XlsxChartFrame {
  /** Imported bubble and surface charts retain native sources and are read-only. */
  kind: XlsxChartSettings["kind"] | "bubble" | "surface";
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

function checkChartFields(value: unknown, requireBindings: boolean): void {
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
    (!xlsxChartKinds.some((kind) => kind === c.kind) &&
      (requireBindings || (c.kind !== "bubble" && c.kind !== "surface"))) ||
    !noteText(c.title, 256) ||
    !noteText(c.label, 256) ||
    /[\r\n]/.test(String(c.title) + String(c.label)) ||
    !["none", "top", "bottom", "left", "right"].some(
      (legend) => legend === c.legend,
    ) ||
    (c.kind === "doughnut"
      ? !integer(c.holeSize, 10, 90)
      : c.holeSize !== null) ||
    !noteText(c.categories, xlsxChartReferenceUnits) ||
    (requireBindings && !c.categories) ||
    !Array.isArray(c.names) ||
    c.names.length < 1 ||
    c.names.length > xlsxChartSeriesCount ||
    !Array.isArray(c.values) ||
    c.values.length !== c.names.length ||
    ![...c.names, ...c.values].every(
      (value) =>
        noteText(value, xlsxChartReferenceUnits) &&
        (!requireBindings || value.length > 0),
    )
  )
    throw new Error("Invalid worksheet chart settings");
}
export function checkXlsxChartSettings(
  value: unknown,
): asserts value is XlsxChartSettings {
  checkChartFields(value, true);
}
export function checkXlsxChartFrame(
  value: unknown,
): asserts value is XlsxChartFrame {
  checkXlsxPictureSettings({ ...record(value), crop: [0, 0, 0, 0] });
}
