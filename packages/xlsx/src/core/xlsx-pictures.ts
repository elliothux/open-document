import { record, integer } from "@open-document/wasm/abi/validation";

function finite(value: unknown, min: number, max: number): boolean {
  return (
    typeof value === "number" &&
    Number.isFinite(value) &&
    value >= min &&
    value <= max
  );
}

export interface XlsxPictureSettings {
  anchor: "fixed" | "move" | "size";
  x: number;
  y: number;
  width: number;
  height: number;
  name: string;
  description: string;
  crop: number[];
}
export interface XlsxPicture extends XlsxPictureSettings {
  id: string;
  key: string;
}
export interface XlsxPictures {
  revision: number;
  sheet: string;
  reason: string;
  items: XlsxPicture[];
}

function pictureSettings(value: unknown, minimum: number): void {
  const p = record(value);
  if (
    typeof p.anchor !== "string" ||
    !["fixed", "move", "size"].includes(p.anchor) ||
    !["x", "y", "width", "height"].every((key) => finite(p[key], 0, 1e9)) ||
    !finite(p.width, minimum, 14400) ||
    !finite(p.height, minimum, 14400) ||
    typeof p.name !== "string" ||
    !p.name.trim() ||
    p.name.length > 255 ||
    typeof p.description !== "string" ||
    p.description.length > 1024 ||
    !Array.isArray(p.crop) ||
    p.crop.length !== 4 ||
    !p.crop.every((value) => finite(value, 0, 0.999999)) ||
    p.crop[0] + p.crop[2] >= 1 ||
    p.crop[1] + p.crop[3] >= 1
  )
    throw new Error("Invalid worksheet picture settings");
}
export function checkXlsxPictureSettings(
  value: unknown,
): asserts value is XlsxPictureSettings {
  pictureSettings(value, 0.1);
}
export function xlsxPictures(value: unknown): XlsxPictures {
  const result = record(value);
  if (
    !integer(result.revision, 0, 2147483647) ||
    typeof result.sheet !== "string" ||
    typeof result.reason !== "string" ||
    !Array.isArray(result.items) ||
    result.items.length > 256
  )
    throw new Error("Invalid worksheet picture list");
  const ids = new Set<string>();
  for (const item of result.items) {
    pictureSettings(item, 0);
    const p = record(item);
    if (
      typeof p.id !== "string" ||
      !/^[1-9][0-9]*$/.test(p.id) ||
      ids.has(p.id) ||
      typeof p.key !== "string" ||
      !p.key ||
      p.key.length > 256
    )
      throw new Error("Invalid worksheet picture identity or crop");
    ids.add(p.id);
  }
  return value as XlsxPictures;
}

export function xlsxPictureResource(value: unknown): {
  revision: number;
  key: string;
} {
  const result = record(value);
  if (
    !integer(result.revision, 0, 2147483647) ||
    typeof result.key !== "string" ||
    !result.key ||
    result.key.length > 256
  )
    throw new Error("Invalid worksheet picture resource");
  return value as { revision: number; key: string };
}
