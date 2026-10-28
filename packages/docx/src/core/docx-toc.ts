import { integer, record } from "@open-document/wasm/abi/validation";

export type DocxTocEdit =
  | { action: "insert"; levels: number }
  | { action: "insertCaptions"; sequence: string }
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
    sequence?: string;
    instruction: string;
    reason: string;
  }[];
}

export function checkDocxTocEdit(value: unknown): asserts value is DocxTocEdit {
  const change = record(value);
  const field =
    change.action === "insert"
      ? "levels"
      : change.action === "insertCaptions"
        ? "sequence"
        : "paragraph";
  if (
    Object.keys(change).length !== 2 ||
    !Object.keys(change).every((key) => key === "action" || key === field) ||
    typeof change.action !== "string" ||
    !["insert", "insertCaptions", "update", "delete"].includes(change.action) ||
    (field === "sequence"
      ? !captionSequence(change[field])
      : !integer(
          change[field],
          field === "levels" ? 1 : 0,
          field === "levels" ? 9 : 2147483647,
        ))
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
      ("sequence" in item &&
        (!captionSequence(item.sequence) ||
          item.firstLevel !== 1 ||
          item.lastLevel !== 1)) ||
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

function captionSequence(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length <= 40 &&
    value.isWellFormed() &&
    /^[_\p{ID_Start}][_\p{ID_Continue}]*$/u.test(value)
  );
}
