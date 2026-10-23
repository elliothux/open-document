import { integer, record } from "./validation.js";

export type DocxNoteKind = "footnote" | "endnote";
export interface DocxNotes {
  revision: number;
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
    value.length <= 32767 &&
    value.isWellFormed() &&
    !Array.from(value).some((c) => {
      const n = c.codePointAt(0)!;
      return (
        n < 32 ||
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
export function docxNotes(value: unknown): DocxNotes {
  const result = record(value);
  if (
    !integer(result.revision, 0, 2147483647) ||
    !Array.isArray(result.entries) ||
    result.entries.length > 8192
  )
    throw new Error("Invalid native note catalog");
  const seen = new Set<string>();
  let units = 0;
  for (const value of result.entries) {
    const note = record(value);
    if (
      !kind(note.kind) ||
      !identity(note.id) ||
      typeof note.text !== "string" ||
      note.text.length > 32767 ||
      !note.text.isWellFormed() ||
      typeof note.reason !== "string" ||
      !integer(note.references, 0, 2147483647)
    )
      throw new Error("Invalid native note entry");
    const key = `${note.kind}:${note.id}`;
    units += note.text.length;
    if (seen.has(key) || units > 2097152)
      throw new Error("Native note catalog exceeds limits");
    seen.add(key);
  }
  return value as DocxNotes;
}
