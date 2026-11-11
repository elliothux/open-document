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
