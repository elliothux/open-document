import { record } from "@open-document/wasm/abi/validation";
import {
  checkXlsxPictureSettings,
  type XlsxPictureSettings,
} from "./xlsx-pictures.js";

export type XlsxDrawingFrame = Pick<
  XlsxPictureSettings,
  "anchor" | "x" | "y" | "width" | "height"
>;

export function checkXlsxDrawingFrame(value: unknown): void {
  const frame = record(value),
    keys = ["anchor", "x", "y", "width", "height"];
  if (
    Object.keys(frame).length !== keys.length ||
    !Object.keys(frame).every((key) => keys.includes(key))
  )
    throw new Error("Invalid drawing frame");
  checkXlsxPictureSettings({
    ...frame,
    name: "Drawing",
    description: "",
    crop: [0, 0, 0, 0],
  });
}

export function checkDrawingFrameView(value: unknown): void {
  const frame = record(value);
  if (
    Object.keys(frame).length !== 5 ||
    typeof frame.anchor !== "string" ||
    !["fixed", "move", "size"].includes(frame.anchor) ||
    !["x", "y", "width", "height"].every(
      (key) =>
        typeof frame[key] === "number" &&
        Number.isFinite(frame[key]) &&
        frame[key] >= 0 &&
        frame[key] <= (key === "x" || key === "y" ? 1e9 : 14400),
    )
  )
    throw new Error("Invalid drawing frame view");
}
