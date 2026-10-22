import { record, integer } from "./validation.js";
import { checkChartSettings, type ChartSettings } from "./chart.js";
import {
  checkDocxDrawingPosition,
  type DocxDrawingPositionEdit,
} from "./docx-picture.js";
import { checkDrawingAnchor, type DrawingAnchor } from "./preview.js";

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

export function docxCharts(value: unknown): DocxCharts {
  const catalog = record(value);
  if (
    Object.keys(catalog).length !== 2 ||
    !integer(catalog.revision, 0, 2147483647) ||
    !Array.isArray(catalog.items) ||
    catalog.items.length > 256
  )
    throw new Error("Invalid document chart catalog");
  const ids = new Set<number>();
  for (const value of catalog.items) {
    const item = record(value);
    if (
      Object.keys(item).length !== 10 ||
      Object.keys(item).some(
        (key) =>
          ![
            "id",
            "width",
            "height",
            "settings",
            "reason",
            "deleteReason",
            "anchor",
            "selected",
            "sizeReason",
            "positionReason",
          ].includes(key),
      ) ||
      typeof item.id !== "number" ||
      !integer(item.id, 0, 2147483647) ||
      ids.has(item.id) ||
      typeof item.reason !== "string" ||
      typeof item.deleteReason !== "string" ||
      typeof item.positionReason !== "string" ||
      typeof item.sizeReason !== "string" ||
      typeof item.selected !== "boolean"
    )
      throw new Error("Invalid document chart item");
    ids.add(item.id);
    checkDrawingAnchor(item.anchor);
    if (item.settings === null) {
      if (
        !item.reason ||
        !item.sizeReason ||
        !item.positionReason ||
        !item.deleteReason ||
        item.selected ||
        item.width !== 0 ||
        item.height !== 0 ||
        item.anchor !== null
      )
        throw new Error("Invalid protected document chart");
    } else {
      checkDocxChartEdit({
        ...record(item.settings),
        width: item.width,
        height: item.height,
        action: "insert",
      });
    }
  }
  return value as DocxCharts;
}
