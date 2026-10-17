import { record } from "./validation.js";
import { checkPptxBackgroundFill } from "./pptx-slides.js";
import {
  checkPptxTextFormat,
  checkPptxParagraphFormat,
  type PptxTextFormat,
  type PptxParagraphFormat,
} from "./pptx-format.js";
export const pptxDashes = [
  "solid",
  "dash",
  "dashDot",
  "dot",
  "lgDash",
  "lgDashDot",
  "lgDashDotDot",
  "sysDash",
  "sysDashDot",
  "sysDashDotDot",
  "sysDot",
] as const;
export type PptxDash = (typeof pptxDashes)[number];
export const pptxCaps = ["flat", "rnd", "sq"] as const;
export const pptxJoins = ["round", "bevel", "miter"] as const;
export type PptxCap = (typeof pptxCaps)[number];
export type PptxJoin = (typeof pptxJoins)[number];
export type PptxHyperlink = { kind: "external" | "slide"; target: string };

export function pptxHyperlink(value: unknown): PptxHyperlink | null {
  if (value === null) return null;
  const link = record(value);
  if (
    (link.kind !== "external" && link.kind !== "slide") ||
    typeof link.target !== "string" ||
    !link.target.isWellFormed() ||
    !link.target ||
    link.target.length > (link.kind === "slide" ? 1024 : 2048) ||
    Object.keys(link).some((key) => key !== "kind" && key !== "target") ||
    (link.kind === "external" &&
      (!/^(https?:\/\/|mailto:).+/i.test(link.target) ||
        /\s/u.test(link.target) ||
        Array.from(link.target).some(
          (c) => c.charCodeAt(0) <= 32 || c.charCodeAt(0) === 127 || c === "\\",
        )))
  )
    throw new Error("Invalid PPTX hyperlink");
  return value as PptxHyperlink;
}
export type PptxObjectEdit =
  | { action: "hyperlink"; link: PptxHyperlink | null }
  | {
      action: "shapeAdjustment";
      name: "adj" | "adj1" | "adj2";
      value: number | null;
    }
  | { action: "fillOpacity" | "strokeOpacity"; opacity: number }
  | { action: "strokeCap"; cap: PptxCap | null }
  | { action: "strokeJoin"; join: "round" | "bevel" | null }
  | { action: "strokeJoin"; join: "miter"; miterLimit: number }
  | { action: "strokeDash"; dash: PptxDash | null }
  | { action: "imageOpacity"; opacity: number }
  | { action: "replaceImage"; object: string; bytes: Uint8Array }
  | {
      action: "imageCrop";
      left: number;
      top: number;
      right: number;
      bottom: number;
    }
  | {
      action: "insertImage";
      bytes: Uint8Array;
      x: number;
      y: number;
      width: number;
      height: number;
    }
  | {
      action: "insert";
      kind:
        | "text"
        | "rect"
        | "roundRect"
        | "ellipse"
        | "line"
        | "leftArrow"
        | "rightArrow"
        | "upArrow"
        | "downArrow";
      x: number;
      y: number;
      width: number;
      height: number;
      text: string;
    }
  | { action: "delete" }
  | { action: "clearTextFormat" | "clearParagraphFormat" }
  | { action: "textFormat"; format: PptxTextFormat }
  | { action: "textParagraph"; format: PptxParagraphFormat }
  | { action: "textAlign"; alignment: "left" | "center" | "right" | "justify" }
  | { action: "fill"; color: string | null }
  | {
      action: "gradientFill";
      startColor: string;
      endColor: string;
      angle: number;
      scaled: boolean;
    }
  | { action: "stroke"; color: string | null; width: number }
  | {
      action: "textInsets";
      left: number;
      top: number;
      right: number;
      bottom: number;
    }
  | { action: "textAnchor"; anchor: "t" | "ctr" | "b" }
  | { action: "textWrap"; wrap: boolean }
  | { action: "textFit"; fit: "none" | "shrink" | "resize" }
  | { action: "group" | "ungroup" }
  | { action: "duplicate"; dx: number; dy: number }
  | { action: "rotate"; angle: number }
  | { action: "flip"; axis: "horizontal" | "vertical" }
  | { action: "layer"; order: "front" | "back" | "forward" | "backward" }
  | {
      action: "align";
      alignment: "left" | "center" | "right" | "top" | "middle" | "bottom";
      relativeTo: "slide" | "selection" | "active";
    }
  | {
      action: "distribute";
      axis: "horizontal" | "vertical";
      relativeTo: "slide" | "selection";
    };

export function number(value: unknown, low = 0, high = 0x7fffffff): number {
  if (
    typeof value !== "number" ||
    !Number.isFinite(value) ||
    value < low ||
    value > high
  )
    throw new Error("Invalid PPTX number");
  return value;
}
export function checkPptxObjectEdit(value: unknown): void {
  const change = record(value);
  if (change.action === "hyperlink") {
    if (Object.keys(change).some((key) => key !== "action" && key !== "link"))
      throw new Error("Invalid PPTX hyperlink edit");
    pptxHyperlink(change.link);
    return;
  }
  if (change.action === "shapeAdjustment") {
    if (!["adj", "adj1", "adj2"].includes(String(change.name)))
      throw new Error("Invalid PPTX shape adjustment");
    if (change.value !== null) number(change.value, 0, 21474.83647);
    return;
  }
  if (change.action === "strokeCap") {
    if (change.cap !== null && !pptxCaps.some((value) => value === change.cap))
      throw new Error("Invalid PPTX border cap");
    return;
  }
  if (change.action === "strokeJoin") {
    if (
      change.join !== null &&
      !pptxJoins.some((value) => value === change.join)
    )
      throw new Error("Invalid PPTX border join");
    if (change.join === "miter") number(change.miterLimit, 1, 1000);
    return;
  }
  if (change.action === "strokeDash") {
    if (
      change.dash !== null &&
      !pptxDashes.some((value) => value === change.dash)
    )
      throw new Error("Invalid PPTX border dash");
    return;
  }
  if (
    change.action === "imageOpacity" ||
    change.action === "fillOpacity" ||
    change.action === "strokeOpacity"
  ) {
    number(change.opacity, 0, 1);
    return;
  }
  if (change.action === "insertImage" || change.action === "replaceImage") {
    if (
      !(change.bytes instanceof Uint8Array) ||
      !change.bytes.length ||
      change.bytes.length > 4194304
    )
      throw new Error("Invalid PPTX image input");
    if (change.action === "replaceImage") {
      if (
        typeof change.object !== "string" ||
        !change.object ||
        change.object.length > 1024
      )
        throw new Error("Invalid PPTX picture target");
      return;
    }
    number(change.x, -14400, 14400);
    number(change.y, -14400, 14400);
    number(change.width, 0.1, 14400);
    number(change.height, 0.1, 14400);
    return;
  }
  if (change.action === "imageCrop") {
    const l = number(change.left, 0, 0.99999),
      t = number(change.top, 0, 0.99999),
      r = number(change.right, 0, 0.99999),
      b = number(change.bottom, 0, 0.99999);
    if (
      Math.round(l * 100000) + Math.round(r * 100000) >= 100000 ||
      Math.round(t * 100000) + Math.round(b * 100000) >= 100000
    )
      throw new Error("Invalid PPTX picture crop area");
    return;
  }
  if (
    change.action === "clearTextFormat" ||
    change.action === "clearParagraphFormat"
  )
    return;
  if (change.action === "textParagraph") {
    checkPptxParagraphFormat(change.format);
    return;
  }
  if (change.action === "textFormat") {
    checkPptxTextFormat(change.format);
    return;
  }
  if (
    change.action === "textAlign" &&
    typeof change.alignment === "string" &&
    ["left", "center", "right", "justify"].includes(change.alignment)
  )
    return;
  if (change.action === "textInsets") {
    for (const key of ["left", "top", "right", "bottom"])
      number(change[key], 0, 14400);
    return;
  }
  if (
    change.action === "textAnchor" &&
    ["t", "ctr", "b"].includes(String(change.anchor))
  )
    return;
  if (change.action === "textWrap" && typeof change.wrap === "boolean") return;
  if (
    change.action === "textFit" &&
    typeof change.fit === "string" &&
    ["none", "shrink", "resize"].includes(String(change.fit))
  )
    return;
  if (change.action === "gradientFill") {
    if (
      Object.keys(change).some(
        (key) =>
          !["action", "startColor", "endColor", "angle", "scaled"].includes(
            key,
          ),
      )
    )
      throw new Error("Invalid shape gradient fields");
    checkPptxBackgroundFill({
      kind: "linear",
      startColor: change.startColor,
      endColor: change.endColor,
      angle: change.angle,
      scaled: change.scaled,
    });
    return;
  }
  if (change.action === "fill" || change.action === "stroke") {
    if (
      change.color !== null &&
      (typeof change.color !== "string" || !/^[0-9a-f]{6}$/i.test(change.color))
    )
      throw new Error("Invalid shape color");
    if (change.action === "stroke") number(change.width, 0.1, 1000);
    return;
  }
  if (
    change.action === "delete" ||
    change.action === "group" ||
    change.action === "ungroup"
  )
    return;
  if (
    change.action === "align" &&
    ["left", "center", "right", "top", "middle", "bottom"].includes(
      String(change.alignment),
    ) &&
    ["slide", "selection", "active"].includes(String(change.relativeTo))
  )
    return;
  if (
    change.action === "distribute" &&
    ["horizontal", "vertical"].includes(String(change.axis)) &&
    ["slide", "selection"].includes(String(change.relativeTo))
  )
    return;
  if (change.action === "rotate") {
    number(change.angle, -360, 360);
    return;
  }
  if (
    change.action === "flip" &&
    ["horizontal", "vertical"].includes(String(change.axis))
  )
    return;
  if (
    change.action === "layer" &&
    ["front", "back", "forward", "backward"].includes(String(change.order))
  )
    return;
  if (change.action === "duplicate") {
    number(change.dx, -14400, 14400);
    number(change.dy, -14400, 14400);
    return;
  }
  if (
    change.action !== "insert" ||
    ![
      "text",
      "rect",
      "roundRect",
      "ellipse",
      "line",
      "leftArrow",
      "rightArrow",
      "upArrow",
      "downArrow",
    ].includes(String(change.kind))
  )
    throw new Error("Invalid PPTX object edit");
  number(change.x, -14400, 14400);
  number(change.y, -14400, 14400);
  const width = number(change.width, 0, 14400),
    height = number(change.height, 0, 14400);
  if (!(
    (width >= 0.1 && height >= 0.1) ||
    (change.kind === "line" && width + height >= 0.1)
  ))
    throw new Error("Invalid PPTX object size");
  const text = change.text;
  if (
    typeof text !== "string" ||
    !text.isWellFormed() ||
    text.length > 32767 ||
    Array.from(text).some((character) => {
      const code = character.charCodeAt(0);
      return (
        (code < 32 && code !== 9 && code !== 10) ||
        code === 65534 ||
        code === 65535
      );
    }) ||
    text.split("\n").length > 256 ||
    text.split("\n").some((p) => p.length > 4096) ||
    (change.kind === "line" && text !== "")
  )
    throw new Error("Invalid PPTX object text");
}
