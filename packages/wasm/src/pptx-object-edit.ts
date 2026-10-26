import type {
  PptxPlaceholder,
  PptxPlaceholderType,
} from "./pptx-placeholder.js";
import type { PptxTableStyle } from "./pptx-table-style.js";
import type { PptxTextFormat, PptxParagraphFormat } from "./pptx-format.js";
import type { PptxBackgroundFill } from "./pptx-slides.js";
import type {
  PptxHyperlink,
  PptxCap,
  PptxDash,
  PptxLineEnd,
  PptxTable,
} from "./pptx-objects.js";
import type { PptxConnectorEnd } from "./pptx-connectors.js";
import type { PptxMediaPlayback } from "./pptx-media.js";
import type { PptxChart } from "./pptx-chart.js";
import type { PptxMathEdit } from "./pptx-math.js";
export const pptxInsertKinds = [
  "text",
  "rect",
  "roundRect",
  "round1Rect",
  "round2SameRect",
  "round2DiagRect",
  "snipRoundRect",
  "snip1Rect",
  "snip2SameRect",
  "snip2DiagRect",
  "ellipse",
  "donut",
  "heart",
  "triangle",
  "rtTriangle",
  "diamond",
  "parallelogram",
  "trapezoid",
  "pentagon",
  "hexagon",
  "heptagon",
  "octagon",
  "decagon",
  "dodecagon",
  "plus",
  "star4",
  "star5",
  "star6",
  "star8",
  "star10",
  "star12",
  "star7",
  "star16",
  "star24",
  "star32",
  "chevron",
  "homePlate",
  "line",
  "leftArrow",
  "rightArrow",
  "notchedRightArrow",
  "upArrow",
  "downArrow",
  "leftRightArrow",
  "upDownArrow",
  "quadArrow",
  "leftRightUpArrow",
  "leftUpArrow",
  "bentUpArrow",
] as const;

export function checkPptxShapeEdit(change: Record<string, unknown>): void {
  if (change.action === "shapeType") {
    if (
      Object.keys(change).length !== 2 ||
      Object.keys(change).some((key) => !["action", "preset"].includes(key)) ||
      !pptxInsertKinds.some(
        (kind) => kind !== "text" && kind !== "line" && kind === change.preset,
      )
    )
      throw new Error("Invalid PPTX shape type");
  } else if (change.action === "textInsets") {
    for (const key of ["left", "top", "right", "bottom"]) {
      const value = change[key];
      if (
        typeof value !== "number" ||
        !Number.isFinite(value) ||
        value < 0 ||
        value > 14400
      )
        throw new Error("Invalid PPTX text inset");
    }
  } else if (change.action === "textAnchor") {
    if (
      typeof change.anchor !== "string" ||
      !["t", "ctr", "b"].includes(change.anchor)
    )
      throw new Error("Invalid PPTX text anchor");
  } else if (change.action === "textWrap") {
    if (typeof change.wrap !== "boolean")
      throw new Error("Invalid PPTX text wrapping");
  } else if (change.action === "textFit") {
    if (
      typeof change.fit !== "string" ||
      !["none", "shrink", "resize"].includes(change.fit)
    )
      throw new Error("Invalid PPTX text fitting");
  } else if (change.action === "textColumns") {
    if (
      Object.keys(change).length !== 4 ||
      Object.keys(change).some(
        (key) => !["action", "columns", "gap", "rtl"].includes(key),
      ) ||
      typeof change.columns !== "number" ||
      !Number.isInteger(change.columns) ||
      change.columns < 1 ||
      change.columns > 16 ||
      typeof change.gap !== "number" ||
      !Number.isFinite(change.gap) ||
      change.gap < 0 ||
      change.gap > 14400 ||
      typeof change.rtl !== "boolean"
    )
      throw new Error("Invalid PPTX text columns");
  } else if (change.action === "textUpright") {
    if (
      Object.keys(change).length !== 2 ||
      Object.keys(change).some((key) => !["action", "upright"].includes(key)) ||
      typeof change.upright !== "boolean"
    )
      throw new Error("Invalid PPTX upright text");
  } else if (change.action === "textRotation") {
    if (
      Object.keys(change).length !== 2 ||
      Object.keys(change).some((key) => !["action", "angle"].includes(key)) ||
      typeof change.angle !== "number" ||
      !Number.isFinite(change.angle) ||
      Math.abs(change.angle) > 360
    )
      throw new Error("Invalid PPTX text rotation");
  } else if (change.action === "textDirection") {
    if (
      Object.keys(change).length !== 2 ||
      Object.keys(change).some(
        (key) => !["action", "direction"].includes(key),
      ) ||
      typeof change.direction !== "string" ||
      !["horz", "vert", "vert270"].includes(change.direction)
    )
      throw new Error("Invalid PPTX text direction");
  } else {
    if (
      !["adj", "adj1", "adj2", "adj3"].some((name) => name === change.name) ||
      (change.value !== null &&
        (typeof change.value !== "number" ||
          !Number.isFinite(change.value) ||
          change.value < 0 ||
          change.value > 21474.83647))
    )
      throw new Error("Invalid PPTX shape adjustment");
  }
}

export type PptxObjectEdit =
  | PptxMathEdit
  | ({
      action: "insertChart";
      x: number;
      y: number;
      width: number;
      height: number;
    } & PptxChart)
  | ({ action: "chartData" | "fillChart" } & PptxChart)
  | {
      action: "insertWordArt";
      preset: "blue" | "gold" | "red" | "purple" | "green-italic";
      text: string;
    }
  | { action: "mediaPlayback"; value: PptxMediaPlayback }
  | {
      action: "fillMedia";
      kind: "audio" | "video";
      contentType: string;
      bytes: Uint8Array;
      poster: Uint8Array;
    }
  | {
      action: "insertMedia";
      kind: "audio" | "video";
      contentType: string;
      bytes: Uint8Array;
      poster: Uint8Array;
      x: number;
      y: number;
      width: number;
      height: number;
    }
  | {
      action: "insertDiagram";
      template: "process" | "hierarchy" | "cycle";
      items: string[];
      x: number;
      y: number;
      width: number;
      height: number;
    }
  | {
      action: "insertConnector" | "connectorEndpoints";
      kind:
        | "straight"
        | "rightAngle"
        | "elbow"
        | "elbow4"
        | "elbow5"
        | "curved"
        | "curved2"
        | "curved4"
        | "curved5";
      start: PptxConnectorEnd;
      end: PptxConnectorEnd;
    }
  | {
      action: "placeholder";
      value: PptxPlaceholder | null;
    }
  | {
      action: "insertPlaceholder";
      type: PptxPlaceholderType;
      x: number;
      y: number;
      width: number;
      height: number;
      text: string;
    }
  | { action: "tableStyle"; style: PptxTableStyle }
  | { action: "tableDirection"; rtl: boolean }
  | { action: "tableRowHeight" | "tableColumnWidth"; value: number }
  | { action: "splitTableCell"; rows: number; columns: number }
  | { action: "fillTable"; rows: number; columns: number }
  | { action: "tableStructure"; operation: keyof PptxTable["operations"] }
  | {
      action: "insertTable";
      rows: number;
      columns: number;
      x: number;
      y: number;
      width: number;
      height: number;
    }
  | {
      action: "imageFill";
      objects: readonly string[];
      bytes: Uint8Array;
      mode: "stretch" | "tile";
    }
  | { action: "imageFillMode"; mode: "stretch" | "tile" }
  | { action: "imageMode"; mode: "stretch" | "tile" }
  | { action: "imageInsets"; insets: [number, number, number, number] }
  | { action: "lineEnd"; side: "head" | "tail"; end: PptxLineEnd | null }
  | { action: "hyperlink"; link: PptxHyperlink | null }
  | {
      action: "shapeType";
      preset: Exclude<(typeof pptxInsertKinds)[number], "text" | "line">;
    }
  | {
      action: "shapeAdjustment";
      name: "adj" | "adj1" | "adj2" | "adj3";
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
      kind: (typeof pptxInsertKinds)[number];
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
      stops: Extract<PptxBackgroundFill, { kind: "linear" }>["stops"];
      angle: number;
      scaled: boolean;
    }
  | { action: "stroke"; color: string | null; width: number }
  | {
      action: "radialGradientFill";
      stops: Extract<PptxBackgroundFill, { kind: "radial" }>["stops"];
    }
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
  | { action: "textColumns"; columns: number; gap: number; rtl: boolean }
  | { action: "textDirection"; direction: "horz" | "vert" | "vert270" }
  | { action: "textRotation"; angle: number }
  | { action: "textUpright"; upright: boolean }
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

export function objectText(text: unknown): string {
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
    text.split("\n").some((p) => p.length > 4096)
  )
    throw new Error("Invalid PPTX object text");
  return text;
}
