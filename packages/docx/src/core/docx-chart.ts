import { record, integer } from "@open-document/wasm/abi/validation";
import {
  checkChartSettings,
  type ChartSettings,
} from "@open-document/wasm/abi/chart";
import {
  checkDocxDrawingPosition,
  type DocxDrawingPositionEdit,
} from "./docx-picture.js";
import type { DrawingAnchor } from "./preview.js";

export type DocxChartValue = ChartSettings & { width: number; height: number };
export type DocxChartUpdate =
  | DocxChartValue
  | { action: "resize"; width: number; height: number }
  | Omit<DocxDrawingPositionEdit, "id">;
export type DocxChartEdit =
  | (DocxChartValue & { action: "insert" })
  | (DocxChartValue & { action: "update"; id: number })
  | { action: "delete"; id: number }
  | { action: "resize"; id: number; width: number; height: number }
  | DocxDrawingPositionEdit;
export interface DocxCharts {
  revision: number;
  items: {
    id: number;
    width: number;
    height: number;
    settings: ChartSettings | null;
    reason: string;
    deleteReason: string;
    anchor: DrawingAnchor | null;
    selected: boolean;
    sizeReason: string;
    positionReason: string;
  }[];
}

export function checkDocxChartEdit(value: unknown): void {
  const edit = record(value);
  if (edit.action === "position") {
    const keys = [
      "action",
      "id",
      "anchor",
      ...(Object.hasOwn(edit, "target") ? ["target"] : []),
    ];
    if (
      Object.keys(edit).length !== keys.length ||
      Object.keys(edit).some((key) => !keys.includes(key)) ||
      (Object.hasOwn(edit, "target") && edit.target === undefined)
    )
      throw new Error("Invalid document chart position fields");
    return checkDocxDrawingPosition(edit);
  }
  const insert = edit.action === "insert",
    remove = edit.action === "delete",
    resize = edit.action === "resize";
  if (
    !["insert", "update", "delete", "resize"].some(
      (action) => action === edit.action,
    ) ||
    (!insert && !integer(edit.id, 0, 2147483647))
  )
    throw new Error("Invalid document chart action");
  const keys = ["action", ...(!insert ? ["id"] : [])];
  if (!remove) {
    const { action: _action, id: _id, width, height, ...settings } = edit;
    if (!resize) checkChartSettings(settings);
    for (const [number, low] of [
      [width, 180],
      [height, 150],
    ] as const)
      if (
        typeof number !== "number" ||
        !Number.isFinite(number) ||
        number < low ||
        number > 14400
      )
        throw new Error("Invalid document chart dimensions");
    keys.push("width", "height");
    if (!resize) {
      keys.push("kind", "title", "data");
      for (const key of ["legend", "holeSize"])
        if (Object.hasOwn(edit, key)) keys.push(key);
    }
  }
  if (
    Object.keys(edit).length !== keys.length ||
    Object.keys(edit).some((key) => !keys.includes(key))
  )
    throw new Error("Invalid document chart fields");
}
