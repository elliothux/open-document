import type { DrawRect, DrawMatrix } from "@open-document/wasm/abi/drawing";
import type {
  PptxHyperlink,
  PptxCap,
  PptxJoin,
  PptxLineEnd,
  PptxDash,
} from "./pptx-objects.js";
import type { PptxBackgroundFill } from "./pptx-slides.js";
import type { PptxPlaceholder } from "./pptx-placeholder.js";

import type { PptxConnector } from "./pptx-connectors.js";
import type { PptxMedia } from "./pptx-media.js";
import type { PptxChart } from "./pptx-chart.js";
import type { PptxMathItem } from "./pptx-math.js";
export interface PptxObject {
  equations: PptxMathItem[];
  media: PptxMedia | null;
  connector: PptxConnector | null;
  connectionSiteCount: number;
  id: string;
  parent: string;
  name: string;
  kind: string;
  chart: PptxChart | null;
  text: string;
  readOnlyReason: string;
  textReadOnlyReason: string;
  deleteReason: string;
  duplicateReason: string;
  rotateReason: string;
  arrangeReason: string;
  transformReason: string;
  tableFillReason: string;
  chartFillReason: string;
  mediaFillReason: string;
  chartDataReason: string;
  shapeTypeReason: string;
  placeholder: { value: PptxPlaceholder | null; reason: string };
  hyperlink: { value: PptxHyperlink | null; reason: string };
  shapeAdjustments: {
    preset: string;
    reason: string;
    values: {
      name: "adj" | "adj1" | "adj2" | "adj3";
      value: number;
      maximum: number;
    }[];
  };
  imageInsets: [number, number, number, number];
  imageInsetsReason: string;
  picture: {
    mode: "stretch" | "tile";
    modeReason: string;
    opacity: number;
    opacityReason: string;
    left: number;
    top: number;
    right: number;
    bottom: number;
    replaceReason: string;
    cropReason: string;
  };
  appearance: {
    imageFill: string | null;
    imageFillMode: "stretch" | "tile" | null;
    imageFillReason: string;
    gradient: Extract<PptxBackgroundFill, { kind: "linear" | "radial" }> | null;
    fillOpacity: number;
    strokeOpacity: number;
    fillOpacityReason: string;
    strokeOpacityReason: string;
    cap: PptxCap;
    join: PptxJoin;
    miterLimit: number;
    penReason: string;
    headEnd: PptxLineEnd;
    tailEnd: PptxLineEnd;
    lineEndReason: string;
    dash: PptxDash;
    dashReason: string;
    fill: string | null;
    stroke: string | null;
    width: number;
    reason: string;
  };
  textFrame: {
    left: number;
    top: number;
    right: number;
    bottom: number;
    anchor: string;
    wrap: boolean;
    fit: "none" | "shrink" | "resize";
    columns: number;
    columnGap: number;
    rtlColumns: boolean;
    direction: string;
    rotation: number;
    upright: boolean;
    reason: string;
  };
  geometry:
    | (DrawRect & {
        matrix: DrawMatrix;
        rotation: number;
        flipX: boolean;
        flipY: boolean;
      })
    | null;
}
