import { integer, record } from "@open-document/wasm/abi/validation";
import {
  docxNoteTextUnits,
  docxNumberingStartMax,
} from "@open-document/wasm/engine-source";

export type DocxNoteKind = "footnote" | "endnote";
export type DocxEndnotePosition = "docEnd" | "sectEnd";
export const noteNumberFormats = [
  "decimal",
  "decimalZero",
  "lowerLetter",
  "upperLetter",
  "lowerRoman",
  "upperRoman",
] as const;
export interface DocxNoteNumberingValue {
  format: (typeof noteNumberFormats)[number];
  start: number;
  restart: "continuous" | "eachSect" | "eachPage";
}
export interface DocxNoteNumbering {
  revision: number;
  kind: DocxNoteKind;
  section: number;
  value: DocxNoteNumberingValue | null;
  reason: string;
}
export function checkNoteNumbering(
  value: unknown,
): asserts value is DocxNoteNumberingValue {
  const fields = record(value);
  if (
    Object.keys(fields).length !== 3 ||
    Object.keys(fields).some(
      (key) => !["format", "start", "restart"].includes(key),
    ) ||
    !noteNumberFormats.some((format) => format === fields.format) ||
    !integer(fields.start, 0, docxNumberingStartMax) ||
    (fields.restart !== "continuous" &&
      fields.restart !== "eachSect" &&
      fields.restart !== "eachPage")
  )
    throw new Error("Invalid note numbering");
}
export function docxNoteNumbering(value: unknown): DocxNoteNumbering {
  const fields = record(value);
  if (
    !integer(fields.revision, 0, 2147483647) ||
    !kind(fields.kind) ||
    !integer(fields.section, 0, 1023) ||
    typeof fields.reason !== "string" ||
    (fields.value === null ? !fields.reason : !!fields.reason)
  )
    throw new Error("Invalid note numbering settings");
  if (fields.value !== null) {
    checkNoteNumbering(fields.value);
    if (fields.kind === "endnote" && fields.value.restart === "eachPage")
      throw new Error("Invalid endnote numbering restart");
  }
  return value as DocxNoteNumbering;
}
export function checkEndnotePosition(
  value: unknown,
): asserts value is DocxEndnotePosition {
  if (value !== "docEnd" && value !== "sectEnd")
    throw new Error("Invalid endnote placement");
}
export interface DocxNotes {
  revision: number;
  endnotes: { position: DocxEndnotePosition | null; reason: string };
  entries: {
    kind: DocxNoteKind;
    id: string;
    text: string;
    reason: string;
    references: number;
  }[];
}
export interface DocxNoteIdentity {
  kind: DocxNoteKind;
  id: string;
}
export interface DocxNoteCreate {
  kind: DocxNoteKind;
  text: string;
}
export interface DocxNoteEdit extends DocxNoteIdentity {
  text: string;
}

function identity(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^(0|[1-9]\d{0,9})$/u.test(value) &&
    value === String(Number(value)) &&
    Number(value) <= 2147483647
  );
}
function kind(value: unknown): value is DocxNoteKind {
  return value === "footnote" || value === "endnote";
}
function text(value: unknown): value is string {
  return (
    typeof value === "string" &&
    value.length <= docxNoteTextUnits &&
    value.isWellFormed() &&
    !Array.from(value).some((c) => {
      const n = c.codePointAt(0)!;
      return (
        (n < 32 && n !== 10) ||
        n === 127 ||
        n === 8232 ||
        n === 8233 ||
        n === 65534 ||
        n === 65535
      );
    })
  );
}
export function checkDocxNoteCreate(
  value: unknown,
): asserts value is DocxNoteCreate {
  const note = record(value);
  if (
    Object.keys(note).length !== 2 ||
    Object.keys(note).some((key) => !["kind", "text"].includes(key)) ||
    !kind(note.kind) ||
    !text(note.text)
  )
    throw new Error("Invalid native note creation");
}
export function checkDocxNoteIdentity(
  value: unknown,
): asserts value is DocxNoteIdentity {
  const note = record(value);
  if (
    Object.keys(note).length !== 2 ||
    Object.keys(note).some((key) => !["kind", "id"].includes(key)) ||
    !kind(note.kind) ||
    !identity(note.id)
  )
    throw new Error("Invalid native note identity");
}
export function checkDocxNoteEdit(
  value: unknown,
): asserts value is DocxNoteEdit {
  const note = record(value);
  if (
    Object.keys(note).length !== 3 ||
    Object.keys(note).some((key) => !["kind", "id", "text"].includes(key)) ||
    !kind(note.kind) ||
    !identity(note.id) ||
    !text(note.text)
  )
    throw new Error("Invalid native note text or identity");
}
