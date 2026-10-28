import { integer, record } from "@open-document/wasm/abi/validation";
import {
  noteNumberFormats,
  type DocxNoteKind,
  type DocxNoteNumberingValue,
} from "./docx-notes.js";
import type { DocxFlow } from "./preview.js";

export interface DocxFlowNote {
  kind: DocxNoteKind;
  key: string;
  paragraph: number;
  node: number;
  numbering: {
    format: DocxNoteNumberingValue["format"];
    value: number;
    restart: DocxNoteNumberingValue["restart"];
    marker: number;
  };
  content: DocxFlow["paragraphs"];
}

export function checkDocxNotes(
  value: unknown,
  checkParagraph: (value: unknown) => void,
): void {
  if (!Array.isArray(value)) throw new Error("Invalid preview array");
  if (value.length > 8192) throw new Error("Note count exceeds limits");
  const identities = new Set<string>();
  const anchors = new Set<string>();
  for (const entry of value) {
    const note = record(entry);
    const key = note.key;
    const identity = `${String(note.kind)}:${String(key)}`;
    const anchor = `${String(note.paragraph)}:${String(note.node)}`;
    if (
      (note.kind !== "footnote" && note.kind !== "endnote") ||
      typeof key !== "string" ||
      key !== String(Number(key)) ||
      !/^[0-9]+$/u.test(key) ||
      Number(key) > 2147483647 ||
      !integer(note.paragraph, 0, Number.MAX_SAFE_INTEGER) ||
      !integer(note.node, 0, Number.MAX_SAFE_INTEGER) ||
      identities.has(identity) ||
      anchors.has(anchor)
    )
      throw new Error("Invalid note identity");
    identities.add(identity);
    anchors.add(anchor);
    const numbering = record(note.numbering);
    if (
      !noteNumberFormats.some((format) => format === numbering.format) ||
      !integer(numbering.value, 0, 4294975486) ||
      !integer(numbering.marker, -2147483648, 2147483647) ||
      (numbering.restart !== "continuous" &&
        numbering.restart !== "eachSect" &&
        !(note.kind === "footnote" && numbering.restart === "eachPage"))
    )
      throw new Error("Invalid note numbering");
    if (!Array.isArray(note.content) || !note.content.length)
      throw new Error("Missing note story");
    for (const paragraph of note.content) checkParagraph(paragraph);
  }
}
