import { record } from "./validation.js";

export interface ParagraphNumbering {
  instance: number;
  numeric: boolean;
  values: number[];
  labels: (string | null)[];
}

export function checkParagraphNumbering(value: unknown): void {
  const numbering = record(value);
  if (
    Object.keys(numbering).some(
      (key) => !["instance", "numeric", "values", "labels"].includes(key),
    ) ||
    !Number.isInteger(numbering.instance) ||
    Number(numbering.instance) < 1 ||
    Number(numbering.instance) > 2147483646 ||
    typeof numbering.numeric !== "boolean" ||
    !Array.isArray(numbering.values) ||
    !numbering.values.length ||
    numbering.values.length > 9 ||
    !numbering.values.every(
      (entry: unknown) =>
        typeof entry === "number" &&
        Number.isInteger(entry) &&
        entry >= 0 &&
        entry <= 2147483646,
    ) ||
    !Array.isArray(numbering.labels) ||
    numbering.labels.length !== numbering.values.length ||
    !numbering.labels.every(
      (entry: unknown) =>
        entry === null || (typeof entry === "string" && entry.length <= 256),
    )
  )
    throw new Error("Invalid paragraph reference numbering");
}
