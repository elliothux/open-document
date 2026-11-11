import { record } from "@open-document/wasm/abi/validation";
import { docxRevisionEntries } from "@open-document/wasm/engine-source";

export interface DocxRevisions {
  revision: number;
  reason: string;
  items: {
    id: string;
    sourceId: string;
    kind:
      | "insert"
      | "delete"
      | "rowInsert"
      | "rowDelete"
      | "rowFormat"
      | "tableFormat"
      | "cellFormat"
      | "characterFormat"
      | "paragraphFormat"
      | "unsupported";
    element: string;
    author: string;
    date: string;
    text: string;
    paragraph: number | null;
    reason: string;
  }[];
}
export interface DocxRevisionEdit {
  action: "accept" | "reject";
  ids: readonly string[];
}
function identity(value: unknown): value is string {
  return (
    typeof value === "string" &&
    /^(0|[1-9]\d{0,9})$/.test(value) &&
    Number(value) <= 2147483647
  );
}
export function checkDocxRevisionIdentity(value: unknown): void {
  if (!identity(value)) throw new Error("Invalid revision identity");
}
export function checkDocxRevisionEdit(
  value: unknown,
  maxEntries = docxRevisionEntries,
): void {
  const change = record(value);
  if (
    (change.action !== "accept" && change.action !== "reject") ||
    !Array.isArray(change.ids) ||
    !change.ids.length ||
    change.ids.length > maxEntries ||
    !change.ids.every(identity) ||
    new Set(change.ids).size !== change.ids.length ||
    Object.keys(change).length !== 2 ||
    Object.keys(change).some((key) => key !== "action" && key !== "ids")
  )
    throw new Error("Invalid revision resolution");
}
