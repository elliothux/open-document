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

function captionSequence(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length <= 40 &&
    value.isWellFormed() &&
    /^[_\p{ID_Start}][_\p{ID_Continue}]*$/u.test(value)
  );
}
