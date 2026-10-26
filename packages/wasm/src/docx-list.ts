import { record } from "./validation.js";

export const listFormats = [
  "decimal",
  "decimalZero",
  "decimalFullWidth",
  "decimalEnclosedCircle",
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
  | { action: "restart"; start: number }
  | { action: "level"; increase: boolean };

const integer = (value: unknown, min: number, max: number): value is number =>
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
            : value.action === "level"
              ? keys.length === 2 && typeof value.increase === "boolean"
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
    levels: DocxListLevel[];
  }[];
}

export interface ListLevelSettings {
  format: ListFormat;
  pattern: string;
  start: number;
  restart: number | null;
  align: "left" | "center" | "right";
  suffix: "tab" | "space" | "nothing";
}
export interface DocxListLevel extends ListLevelSettings {
  level: number;
}

export function validListLevelSettings(
  value: Record<string, unknown>,
  level: number,
): boolean {
  return (
    integer(level, 0, 8) &&
    listFormats.some((format) => format === value.format) &&
    typeof value.pattern === "string" &&
    value.pattern.length > 0 &&
    value.pattern.length <= 256 &&
    value.pattern.isWellFormed() &&
    !Array.from(value.pattern).some((character) => {
      const code = character.charCodeAt(0);
      return (
        code < 32 ||
        code === 127 ||
        code === 8232 ||
        code === 8233 ||
        code === 65534 ||
        code === 65535
      );
    }) &&
    integer(value.start, 0, 2147483646) &&
    (value.restart === null || integer(value.restart, 0, level)) &&
    ["left", "center", "right"].some((align) => align === value.align) &&
    ["tab", "space", "nothing"].some((suffix) => suffix === value.suffix)
  );
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
            validListLevelSettings(level, level.level)
          );
        })
      );
    })
  )
    throw new Error("Invalid list catalog");
  return value as DocxListCatalog;
}
