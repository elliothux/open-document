import { OfficeSession } from "@open-document/wasm/abi/session";
import { xlsxQuery } from "./xlsx-query.js";
import { integer, record } from "@open-document/wasm/abi/validation";

export type XlsxThreadEdit =
  | {
      action: "create";
      cell: string;
      text: string;
      author: string;
      date: string;
    }
  | { action: "reply"; id: string; text: string; author: string; date: string }
  | { action: "update"; id: string; text: string }
  | { action: "resolve"; id: string; resolved: boolean }
  | { action: "delete"; id: string };

export interface XlsxThreads {
  revision: number;
  sheet: string;
  cell: string;
  reason: string;
  items: {
    id: string;
    parentId: string | null;
    personId: string;
    author: string;
    date: string;
    text: string;
    resolved: boolean;
  }[];
}

const guid = (value: unknown): value is string =>
  typeof value === "string" &&
  /^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$/.test(
    value,
  );
const cell = (value: unknown): value is string =>
  typeof value === "string" && /^[A-Z]{1,3}[1-9][0-9]{0,6}$/.test(value);
const date = (value: unknown): value is string =>
  typeof value === "string" &&
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{3})?Z$/.test(value);

export function checkXlsxThreadEdit(
  value: unknown,
): asserts value is XlsxThreadEdit {
  const change = record(value);
  if (change.action === "create" ? !cell(change.cell) : !guid(change.id))
    throw new Error("Invalid cell thread target");
  switch (change.action) {
    case "create":
    case "reply":
      if (
        typeof change.author !== "string" ||
        !change.author.trim() ||
        change.author.length > 255 ||
        !date(change.date)
      )
        throw new Error("Explicit thread author and UTC date are required");
      break;
    case "update":
      break;
    case "resolve":
      if (typeof change.resolved !== "boolean")
        throw new Error("Invalid thread resolution");
      return;
    case "delete":
      return;
    default:
      throw new Error("Invalid cell thread operation");
  }
  if (
    typeof change.text !== "string" ||
    !change.text.trim() ||
    change.text.length > 32767
  )
    throw new Error("Cell thread text must contain 1–32767 UTF-16 units");
}

export function xlsxThreads(value: unknown): XlsxThreads {
  const result = record(value);
  if (
    !integer(result.revision, 0, 2147483647) ||
    typeof result.sheet !== "string" ||
    !cell(result.cell) ||
    typeof result.reason !== "string" ||
    !Array.isArray(result.items) ||
    result.items.length > 4096
  )
    throw new Error("Invalid cell thread catalog");
  const ids = new Set<string>();
  const roots = new Set<string>();
  let units = 0;
  for (const raw of result.items) {
    const item = record(raw);
    if (
      !guid(item.id) ||
      ids.has(item.id) ||
      !guid(item.personId) ||
      (item.parentId !== null && !guid(item.parentId)) ||
      typeof item.author !== "string" ||
      item.author.length > 255 ||
      !date(item.date) ||
      typeof item.text !== "string" ||
      item.text.length > 32767 ||
      typeof item.resolved !== "boolean"
    )
      throw new Error("Invalid cell thread message");
    units += item.text.length;
    ids.add(item.id);
    if (item.parentId === null) roots.add(item.id);
  }
  if (
    roots.size > 1 ||
    units > 1048576 ||
    result.items.some((raw: unknown) => {
      const item = record(raw);
      return item.parentId !== null && !roots.has(String(item.parentId));
    })
  )
    throw new Error("Invalid cell thread relationships");
  return value as XlsxThreads;
}

export class XlsxCommentsSession extends OfficeSession {
  constructor(exports: WebAssembly.Exports, handle: unknown) {
    super(exports, handle, "xlsx");
  }

  threads(revision: number, sheet: string, cell: string): XlsxThreads {
    return xlsxThreads(
      this.call({ operation: "threadsXlsx", revision, sheet, cell }),
    );
  }
  editThread(revision: number, sheet: string, change: XlsxThreadEdit) {
    checkXlsxThreadEdit(change);
    return xlsxQuery(
      this.call({ operation: "editThreadXlsx", revision, sheet, change }),
    );
  }
}
