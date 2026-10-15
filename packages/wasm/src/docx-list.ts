import { record } from "./validation.js";

export const listFormats = [
  "decimal",
  "decimalZero",
  "lowerLetter",
  "upperLetter",
  "lowerRoman",
  "upperRoman",
  "bullet",
] as const;
export type ListFormat = (typeof listFormats)[number];
export interface DocxListReference {
  id: number;
  level: number;
}
export type DocxListEdit =
  | { action: "create"; format: ListFormat }
  | { action: "apply"; id: number; level: number }
  | { action: "remove" }
  | { action: "restart"; start: number };

const integer = (value: unknown, min: number, max: number): boolean =>
  typeof value === "number" &&
  Number.isInteger(value) &&
  value >= min &&
  value <= max;

export function isListReference(value: unknown): value is DocxListReference {
  if (typeof value !== "object" || value === null) return false;
  const fields = record(value);
  return integer(fields.id, 1, 2147483646) && integer(fields.level, 0, 8);
}

export function checkListEdit(value: DocxListEdit): void {
  const fields = record(value);
  const keys = Object.keys(fields);
  const valid =
    value.action === "create"
      ? keys.length === 2 && listFormats.includes(value.format)
      : value.action === "apply"
        ? keys.length === 3 && isListReference(value)
        : value.action === "remove"
          ? keys.length === 1
          : value.action === "restart"
            ? keys.length === 2 && integer(value.start, 0, 2147483646)
            : false;
  if (!valid) throw new Error("Invalid list edit");
}

export interface DocxListCatalog {
  revision: number;
  truncated: boolean;
  lists: {
    id: number;
    preview: string;
    reason: string;
    levels: { level: number; format: ListFormat }[];
  }[];
}

export function docxListCatalog(value: unknown): DocxListCatalog {
  const fields = record(value);
  if (
    !integer(fields.revision, 0, 2147483647) ||
    typeof fields.truncated !== "boolean" ||
    !Array.isArray(fields.lists) ||
    fields.lists.length > 1024 ||
    !fields.lists.every((value) => {
      const list = record(value);
      return (
        integer(list.id, 1, 2147483646) &&
        typeof list.preview === "string" &&
        typeof list.reason === "string" &&
        Array.isArray(list.levels) &&
        list.levels.length <= 9 &&
        list.levels.every((value) => {
          const level = record(value);
          return (
            integer(level.level, 0, 8) &&
            listFormats.some((format) => format === level.format)
          );
        })
      );
    })
  )
    throw new Error("Invalid list catalog");
  return value as DocxListCatalog;
}
