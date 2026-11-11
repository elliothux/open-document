import { integer, record } from "@open-document/wasm/abi/validation";
import { docxIndexLabelUnits } from "@open-document/wasm/engine-source";

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
    value.length <= docxIndexLabelUnits &&
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
