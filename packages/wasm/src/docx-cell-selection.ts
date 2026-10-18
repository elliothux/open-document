import { record } from "./validation.js";
import type { FormatValue } from "./docx-format.js";
import {
  checkDocxBorders,
  type DocxCellMargins,
  type DocxCellBorders,
  type DocxBorderStyle,
} from "./docx-table.js";

export interface DocxCellSelection {
  reason: string;
  value: {
    table: number;
    top: number;
    bottom: number;
    left: number;
    right: number;
    count: number;
    fill: FormatValue<string | null>;
    verticalAlign: FormatValue<"top" | "center" | "bottom">;
    margins: Record<keyof DocxCellMargins, FormatValue<number>>;
    rowSplit: FormatValue<boolean>;
    borders: Record<keyof DocxCellBorders, FormatValue<DocxBorderStyle>>;
  } | null;
}

export function checkDocxCellSelection(value: unknown): void {
  const selection = record(value);
  if (typeof selection.reason !== "string")
    throw new Error("Invalid DOCX cell selection reason");
  if (selection.value === null) return;
  const cells = record(selection.value),
    fill = record(cells.fill),
    align = record(cells.verticalAlign);
  if (
    selection.reason !== "" ||
    !["table", "top", "bottom", "left", "right", "count"].every(
      (key) => Number.isSafeInteger(cells[key]) && Number(cells[key]) >= 0,
    ) ||
    Number(cells.table) > 2147483647 ||
    Number(cells.top) >= Number(cells.bottom) ||
    Number(cells.bottom) > 1000 ||
    Number(cells.left) >= Number(cells.right) ||
    Number(cells.right) > 63 ||
    Number(cells.count) < 1 ||
    Number(cells.count) >
      (Number(cells.bottom) - Number(cells.top)) *
        (Number(cells.right) - Number(cells.left)) ||
    !(
      fill.kind === "mixed" ||
      (fill.kind === "value" &&
        (fill.value === null ||
          (typeof fill.value === "string" &&
            /^[0-9a-f]{6}$/iu.test(fill.value))))
    ) ||
    !(
      align.kind === "mixed" ||
      (align.kind === "value" &&
        typeof align.value === "string" &&
        ["top", "center", "bottom"].includes(align.value))
    )
  )
    throw new Error("Invalid DOCX cell selection");
  const margins = record(cells.margins);
  const borders = record(cells.borders);
  const split = record(cells.rowSplit);
  if (
    split.kind !== "mixed" &&
    !(split.kind === "value" && typeof split.value === "boolean")
  )
    throw new Error("Invalid DOCX selected row splitting");
  for (const side of ["top", "right", "bottom", "left"] as const) {
    const border = record(borders[side]);
    if (border.kind === "value" && border.value !== null)
      checkDocxBorders({ [side]: border.value }, false);
    else if (border.kind !== "mixed")
      throw new Error("Invalid DOCX selected cell border");
    const margin = record(margins[side]);
    if (
      margin.kind !== "mixed" &&
      !(
        margin.kind === "value" &&
        typeof margin.value === "number" &&
        Number.isFinite(margin.value) &&
        margin.value >= 0 &&
        margin.value <= 14400 &&
        Number.isInteger(margin.value * 20)
      )
    )
      throw new Error("Invalid DOCX selected cell margin");
  }
}
