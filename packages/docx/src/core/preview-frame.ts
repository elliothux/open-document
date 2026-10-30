import { record } from "@open-document/wasm/abi/validation";
import { checkDocxBorders, type DocxBorderStyle } from "./docx-table.js";

export interface ParagraphFrame {
  width: number;
  height: number;
  heightRule: string;
  horizontalAnchor: string;
  verticalAnchor: string;
  x?: number;
  y?: number;
  horizontalAlign: string;
  verticalAlign: string;
  horizontalSpace: number;
  verticalSpace: number;
  borders: Record<string, [number, DocxBorderStyle]>;
}

export function checkParagraphFrame(value: unknown): void {
  if (value === undefined) return;
  const frame = record(value);
  for (const key of ["width", "height", "horizontalSpace", "verticalSpace"]) {
    const v = frame[key];
    if (typeof v !== "number" || !Number.isFinite(v) || v < 0 || v > 14400)
      throw new Error("Invalid paragraph frame size");
  }
  for (const key of ["x", "y"]) {
    const v = frame[key];
    if (
      v !== undefined &&
      (typeof v !== "number" || !Number.isFinite(v) || Math.abs(v) > 14400)
    )
      throw new Error("Invalid paragraph frame offset");
  }
  for (const key of ["horizontalAnchor", "verticalAnchor"])
    if (!["page", "margin", "text"].some((v) => v === frame[key]))
      throw new Error("Invalid paragraph frame anchor");
  for (const [key, values] of [
    ["heightRule", ["auto", "atLeast", "exact"]],
    ["horizontalAlign", ["", "left", "right", "center", "inside", "outside"]],
    ["verticalAlign", ["", "top", "bottom", "center", "inside", "outside"]],
  ] as const)
    if (!values.some((v) => v === frame[key]))
      throw new Error("Invalid paragraph frame alignment");
  for (const [side, edge] of Object.entries(record(frame.borders))) {
    if (
      !Array.isArray(edge) ||
      edge.length !== 2 ||
      typeof edge[0] !== "number" ||
      !Number.isInteger(edge[0]) ||
      edge[0] < 0 ||
      edge[0] > 31
    )
      throw new Error("Invalid paragraph frame border spacing");
    checkDocxBorders({ [side]: edge[1] }, false);
  }
}
