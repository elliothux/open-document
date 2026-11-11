import { record } from "@open-document/wasm/abi/validation";
import { xlsxThreadTextUnits } from "@open-document/wasm/engine-source";

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
    change.text.length > xlsxThreadTextUnits
  )
    throw new Error(
      `Cell thread text must contain 1–${xlsxThreadTextUnits} UTF-16 units`,
    );
}
