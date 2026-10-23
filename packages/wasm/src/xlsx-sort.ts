import { record, integer } from "./validation.js";
import { conditionalIconSets, type XlsxIconSet } from "./xlsx-conditional.js";

export interface XlsxSortKey {
  /** One-based worksheet column for rows, or row for columns. */
  index: number;
  descending: boolean;
  /** Text labels in ascending priority order. Empty or omitted uses normal sorting. */
  customList?: string[];
  sortBy?: "value" | "cellColor" | "fontColor" | "icon";
  /** Six RGB hexadecimal digits; empty selects no fill for cellColor. */
  color?: string;
  /** Native icon set and zero-based visible icon index. Omit both to select cells without an icon. */
  iconSet?: XlsxIconSet["kind"];
  iconId?: number;
}
export interface XlsxSortSettings {
  rows: boolean;
  header: boolean;
  caseSensitive: boolean;
  keys: XlsxSortKey[];
}
export function checkXlsxSort(value: unknown): void {
  const change = record(value);
  if (
    typeof change.range !== "string" ||
    !change.range ||
    change.range.length > 64 ||
    typeof change.rows !== "boolean" ||
    typeof change.header !== "boolean" ||
    typeof change.caseSensitive !== "boolean" ||
    !Array.isArray(change.keys) ||
    change.keys.length < 1 ||
    change.keys.length > 16
  )
    throw new Error("Invalid sort settings");
  const seen = new Set<string>();
  for (const value of change.keys) {
    const key = record(value);
    if (
      !integer(key.index, 1, change.rows ? 16384 : 1048576) ||
      typeof key.descending !== "boolean" ||
      Object.keys(key).some(
        (name) =>
          ![
            "index",
            "descending",
            "customList",
            "sortBy",
            "color",
            "iconSet",
            "iconId",
          ].includes(name),
      )
    )
      throw new Error("Invalid sort key");
    const kind = key.sortBy === undefined ? "value" : key.sortBy;
    if (
      typeof kind !== "string" ||
      !["value", "cellColor", "fontColor", "icon"].includes(kind)
    )
      throw new Error("Invalid sort kind");
    if (kind !== "icon" && ("iconSet" in key || "iconId" in key))
      throw new Error("Unexpected sort icon");
    if (kind === "icon") {
      const noIcon = !("iconSet" in key) && !("iconId" in key);
      if (
        (!noIcon &&
          (!conditionalIconSets.some((set) => set === key.iconSet) ||
            !integer(key.iconId, 0, Number(String(key.iconSet)[0]) - 1))) ||
        (key.color !== undefined && key.color !== "") ||
        (key.customList !== undefined &&
          (!Array.isArray(key.customList) || key.customList.length !== 0))
      )
        throw new Error("Invalid icon sort key");
    } else if (kind === "value") {
      if (key.color !== undefined && key.color !== "")
        throw new Error("Unexpected sort color");
    } else if (
      typeof key.color !== "string" ||
      !(
        /^[0-9a-f]{6}$/iu.test(key.color) ||
        (kind === "cellColor" && key.color === "")
      ) ||
      (key.customList !== undefined &&
        (!Array.isArray(key.customList) || key.customList.length !== 0))
    )
      throw new Error("Invalid color sort key");
    const identity = `${key.index}:${kind}:${kind === "icon" ? `${key.iconSet ?? ""}:${key.iconId ?? 0}` : kind === "value" ? "" : String(key.color).toUpperCase()}`;
    if (seen.has(identity)) throw new Error("Duplicate sort condition");
    seen.add(identity);
    if (key.customList !== undefined) {
      if (!Array.isArray(key.customList) || key.customList.length > 4096)
        throw new Error("Invalid custom sort list");
      const labels = new Set<string>();
      let units = Math.max(0, key.customList.length - 1);
      for (const label of key.customList) {
        if (
          typeof label !== "string" ||
          !label ||
          !label.isWellFormed() ||
          /[,\r\n]/u.test(label) ||
          Array.from(label).some((character) => {
            const code = character.charCodeAt(0);
            return (
              (code < 32 && code !== 9) || code === 65534 || code === 65535
            );
          }) ||
          labels.has(label) ||
          (units += label.length) > 32767
        )
          throw new Error("Invalid custom sort label");
        labels.add(label);
      }
    }
  }
}
