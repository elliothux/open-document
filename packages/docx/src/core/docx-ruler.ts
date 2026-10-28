import { record } from "@open-document/wasm/abi/validation";
import { isDocxSelection } from "./docx-search.js";
import type { DocxSelection } from "./docx-hit.js";

export type DocxRulerKind =
  "first" | "hanging" | "left" | "right" | "marginLeft" | "marginRight";
export type DocxRulerTabAlign = "left" | "right" | "center" | "decimal" | "bar";
export type DocxRulerEdit =
  | { kind: DocxRulerKind; position: number; snap: boolean }
  | {
      kind: "tab";
      position: number;
      snap: boolean;
      index: number;
      align: DocxRulerTabAlign;
      remove: boolean;
    };
export interface DocxRuler {
  revision: number;
  layoutId: number;
  selection: DocxSelection;
  page: number;
  width: number;
  origin: number;
  extent: number;
  rtl: boolean;
  markers: {
    kind: DocxRulerKind | "tab";
    position: number;
    index: number;
    align: string;
    leader: string;
  }[];
  reason: string;
}
const kinds = [
  "first",
  "hanging",
  "left",
  "right",
  "marginLeft",
  "marginRight",
];
const aligns = ["left", "right", "center", "decimal", "bar"];

export function checkDocxRulerEdit(
  value: unknown,
): asserts value is DocxRulerEdit {
  const edit = record(value);
  const fields =
    edit.kind === "tab"
      ? ["kind", "position", "snap", "index", "align", "remove"]
      : ["kind", "position", "snap"];
  if (
    Object.keys(edit).length !== fields.length ||
    Object.keys(edit).some((key) => !fields.includes(key)) ||
    typeof edit.position !== "number" ||
    !Number.isFinite(edit.position) ||
    Math.abs(edit.position) > 14400 ||
    typeof edit.snap !== "boolean" ||
    (edit.kind === "tab"
      ? typeof edit.index !== "number" ||
        !Number.isInteger(edit.index) ||
        edit.index < -1 ||
        edit.index > 63 ||
        typeof edit.align !== "string" ||
        !aligns.includes(edit.align) ||
        typeof edit.remove !== "boolean" ||
        (edit.remove && edit.index < 0)
      : typeof edit.kind !== "string" || !kinds.includes(edit.kind))
  )
    throw new Error("Invalid DOCX ruler change");
}

export function docxRuler(value: unknown): DocxRuler {
  const result = record(value);
  const integer = (value: unknown) =>
    typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
  if (
    !integer(result.revision) ||
    !integer(result.layoutId) ||
    !integer(result.page) ||
    !isDocxSelection(result.selection) ||
    typeof result.rtl !== "boolean" ||
    typeof result.reason !== "string" ||
    typeof result.width !== "number" ||
    !(result.width >= 36 && result.width <= 14400) ||
    typeof result.origin !== "number" ||
    !Number.isFinite(result.origin) ||
    typeof result.extent !== "number" ||
    !(result.extent > 0 && result.extent <= 14400) ||
    !Array.isArray(result.markers) ||
    result.markers.length > 70
  )
    throw new Error("Invalid DOCX ruler result");
  for (const entry of result.markers) {
    const marker = record(entry);
    if (
      typeof marker.kind !== "string" ||
      ![...kinds, "tab"].includes(marker.kind) ||
      typeof marker.position !== "number" ||
      !Number.isFinite(marker.position) ||
      typeof marker.index !== "number" ||
      !Number.isInteger(marker.index) ||
      (marker.kind === "tab"
        ? marker.index < 0 ||
          marker.index > 63 ||
          typeof marker.align !== "string" ||
          !aligns.includes(marker.align) ||
          typeof marker.leader !== "string" ||
          ![
            "none",
            "dot",
            "hyphen",
            "underscore",
            "heavy",
            "middleDot",
          ].includes(marker.leader)
        : marker.index !== -1 || marker.align !== "" || marker.leader !== "")
    )
      throw new Error("Invalid DOCX ruler marker");
  }
  return value as DocxRuler;
}
