import { integer, record } from "./validation.js";

export type DocxTocEdit =
  | { action: "insert"; levels: number }
  | { action: "update" | "delete"; paragraph: number };

export interface DocxTableOfContents {
  revision: number;
  items: {
    paragraph: number;
    endParagraph: number;
    firstLevel: number;
    lastLevel: number;
    hyperlink: boolean;
    outline: boolean;
    instruction: string;
    reason: string;
  }[];
}

export function checkDocxTocEdit(value: unknown): asserts value is DocxTocEdit {
  const change = record(value);
  const field = change.action === "insert" ? "levels" : "paragraph";
  if (
    Object.keys(change).length !== 2 ||
    !Object.keys(change).every((key) => key === "action" || key === field) ||
    typeof change.action !== "string" ||
    !["insert", "update", "delete"].includes(change.action) ||
    !integer(
      change[field],
      field === "levels" ? 1 : 0,
      field === "levels" ? 9 : 2147483647,
    )
  )
    throw new Error("Invalid DOCX table of contents command");
}

export function docxTableOfContents(value: unknown): DocxTableOfContents {
  const result = record(value);
  if (
    !integer(result.revision, 0, 2147483647) ||
    !Array.isArray(result.items) ||
    result.items.length > 256
  )
    throw new Error("Invalid DOCX table of contents catalog");
  const seen = new Set<number>();
  for (const value of result.items) {
    const item = record(value);
    if (
      !integer(item.paragraph, 0, 2147483647) ||
      seen.has(Number(item.paragraph)) ||
      !integer(item.endParagraph, 0, 2147483647) ||
      !integer(item.firstLevel, 1, 9) ||
      !integer(item.lastLevel, Number(item.firstLevel), 9) ||
      typeof item.hyperlink !== "boolean" ||
      typeof item.outline !== "boolean" ||
      typeof item.instruction !== "string" ||
      item.instruction.length > 257 ||
      !item.instruction.isWellFormed() ||
      typeof item.reason !== "string" ||
      item.reason.length > 8192
    )
      throw new Error("Invalid DOCX table of contents item");
    seen.add(Number(item.paragraph));
  }
  return value as DocxTableOfContents;
}
