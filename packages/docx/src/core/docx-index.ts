import { integer, record } from "@open-document/wasm/abi/validation";

export type DocxIndexEdit =
  | { action: "mark"; label: string }
  | { action: "updateEntry"; id: number; label: string }
  | { action: "deleteEntry"; id: number }
  | { action: "insert" }
  | { action: "update" | "delete"; paragraph: number };

export interface DocxIndexes {
  revision: number;
  entries: { id: number; paragraph: number; label: string; reason: string }[];
  indexes: {
    paragraph: number;
    endParagraph: number;
    instruction: string;
    reason: string;
  }[];
}

function indexLabel(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length > 0 &&
    value.length <= 255 &&
    value.isWellFormed() &&
    Array.from(value).every(
      (char) =>
        char.codePointAt(0)! >= 32 && !'"\\;\u2028\u2029'.includes(char),
    ) &&
    value.split(":").length <= 3 &&
    value.split(":").every((part) => part.trim().length > 0)
  );
}

export function checkDocxIndexEdit(
  value: unknown,
): asserts value is DocxIndexEdit {
  const change = record(value);
  const fields =
    change.action === "insert"
      ? []
      : change.action === "mark"
        ? ["label"]
        : change.action === "updateEntry"
          ? ["id", "label"]
          : change.action === "deleteEntry"
            ? ["id"]
            : ["paragraph"];
  if (
    typeof change.action !== "string" ||
    ![
      "mark",
      "updateEntry",
      "deleteEntry",
      "insert",
      "update",
      "delete",
    ].includes(change.action) ||
    Object.keys(change).length !== fields.length + 1 ||
    Object.keys(change).some(
      (key) => key !== "action" && !fields.includes(key),
    ) ||
    (fields.includes("label") && !indexLabel(change.label)) ||
    fields.some(
      (key) => key !== "label" && !integer(change[key], 0, 2147483647),
    )
  )
    throw new Error("Invalid DOCX index command");
}

export function docxIndexes(value: unknown): DocxIndexes {
  const result = record(value);
  if (
    !integer(result.revision, 0, 2147483647) ||
    !Array.isArray(result.entries) ||
    result.entries.length > 4096 ||
    !Array.isArray(result.indexes) ||
    result.indexes.length > 256
  )
    throw new Error("Invalid DOCX index catalog");
  const entries = new Set<number>(),
    indexes = new Set<number>();
  for (const value of result.entries) {
    const entry = record(value);
    if (
      !integer(entry.id, 0, 2147483647) ||
      entries.has(Number(entry.id)) ||
      !integer(entry.paragraph, 0, 2147483647) ||
      typeof entry.reason !== "string" ||
      entry.reason.length > 8192 ||
      typeof entry.label !== "string" ||
      entry.label.length > 255 ||
      !entry.label.isWellFormed() ||
      (!entry.reason && !indexLabel(entry.label))
    )
      throw new Error("Invalid DOCX index entry");
    entries.add(Number(entry.id));
  }
  for (const value of result.indexes) {
    const index = record(value);
    if (
      !integer(index.paragraph, 0, 2147483647) ||
      indexes.has(Number(index.paragraph)) ||
      !integer(index.endParagraph, 0, 2147483647) ||
      typeof index.instruction !== "string" ||
      index.instruction.length > 257 ||
      !index.instruction.isWellFormed() ||
      typeof index.reason !== "string" ||
      index.reason.length > 8192
    )
      throw new Error("Invalid DOCX index result");
    indexes.add(Number(index.paragraph));
  }
  return value as DocxIndexes;
}
