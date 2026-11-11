import { record } from "@open-document/wasm/abi/validation";

export interface PptxTableStyle {
  id: string;
  firstRow: boolean;
  lastRow: boolean;
  firstColumn: boolean;
  lastColumn: boolean;
  bandRows: boolean;
  bandColumns: boolean;
}

export interface PptxTableStyleQuery {
  settings: PptxTableStyle;
  choices: { id: string; name: string }[];
  reason: string;
}

export function checkPptxTableStyle(value: unknown): void {
  const style = record(value);
  const flags = [
    "firstRow",
    "lastRow",
    "firstColumn",
    "lastColumn",
    "bandRows",
    "bandColumns",
  ];
  if (
    Object.keys(style).length !== 7 ||
    Object.keys(style).some((key) => key !== "id" && !flags.includes(key)) ||
    flags.some((key) => typeof style[key] !== "boolean") ||
    typeof style.id !== "string" ||
    !style.id.isWellFormed() ||
    style.id.length > 80 ||
    !style.id
  )
    throw new Error("Invalid PPTX table style");
}
