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

export function checkPptxTableStyle(value: unknown, allowEmpty = false): void {
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
    (!allowEmpty && !style.id)
  )
    throw new Error("Invalid PPTX table style");
}

export function checkPptxTableStyleQuery(value: unknown): void {
  const query = record(value);
  checkPptxTableStyle(query.settings, true);
  if (
    !Array.isArray(query.choices) ||
    query.choices.length > 270 ||
    typeof query.reason !== "string"
  )
    throw new Error("Invalid PPTX table style query");
  const ids = new Set<string>();
  for (const value of query.choices) {
    const choice = record(value);
    if (
      typeof choice.id !== "string" ||
      !choice.id ||
      choice.id.length > 80 ||
      !choice.id.isWellFormed() ||
      ids.has(choice.id.toUpperCase()) ||
      typeof choice.name !== "string" ||
      !choice.name.isWellFormed() ||
      choice.name.length > 1024
    )
      throw new Error("Invalid PPTX table style choice");
    ids.add(choice.id.toUpperCase());
  }
  const settings = record(query.settings);
  if (
    typeof settings.id === "string" &&
    settings.id &&
    !ids.has(settings.id.toUpperCase())
  )
    throw new Error("Missing PPTX table style choice");
}
