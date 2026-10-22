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
  "ellipse",
  "triangle",
  "rtTriangle",
  "diamond",
  "parallelogram",
  "trapezoid",
  "pentagon",
  "hexagon",
  "octagon",
  "plus",
  "star5",
  "line",
  "leftArrow",
  "rightArrow",
  "upArrow",
  "downArrow",
  "leftRightArrow",
  "upDownArrow",
  "quadArrow",
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
      kind: "straight" | "elbow" | "curved";
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
