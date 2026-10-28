import type { XlsxAnalysisRequest } from "./protocol-xlsx-analysis.js";
import type { XlsxCommentsRequest } from "./protocol-xlsx-comments.js";
import type { XlsxDataRequest } from "./protocol-xlsx-data.js";
import type { Budget } from "@open-document/wasm/abi/validation";
import type {
  GridViewport,
  PrintOptions,
  XlsxSheetEdit,
  XlsxCellFormat,
  CopiedCellFormat,
  XlsxClearMode,
  CopiedCells,
  XlsxPasteMode,
  XlsxFindOptions,
  XlsxDelimitedOptions,
  XlsxFillTarget,
  XlsxPictureSettings,
  XlsxShapeKind,
  XlsxShapeSettings,
  XlsxChartSettings,
  XlsxChartFrame,
} from "../core/index.js";
export type Operation =
  | { operation: "initialize"; module: WebAssembly.Module }
  | XlsxAnalysisRequest
  | XlsxDataRequest
  | XlsxCommentsRequest
  | {
      operation: "insertXlsxChart";
      revision: number;
      sheet: string;
      settings: XlsxChartSettings;
      width: number;
      height: number;
      profile: Record<string, string>;
    }
  | {
      operation: "insertRangeXlsxChart";
      revision: number;
      sheet: string;
      range: string;
      kind: XlsxChartSettings["kind"];
      title: string;
      width: number;
      height: number;
      profile: Record<string, string>;
    }
  | {
      operation: "setXlsxChart";
      revision: number;
      sheet: string;
      chartId: string;
      settings: XlsxChartSettings;
      profile: Record<string, string>;
    }
  | {
      operation: "frameXlsxChart";
      revision: number;
      sheet: string;
      chartId: string;
      settings: XlsxChartFrame;
      profile: Record<string, string>;
    }
  | {
      operation: "deleteXlsxChart";
      revision: number;
      sheet: string;
      chartId: string;
      profile: Record<string, string>;
    }
  | {
      operation: "shapesXlsx";
      revision: number;
      sheet: string;
      profile: Record<string, string>;
    }
  | {
      operation: "insertShapeXlsx";
      revision: number;
      sheet: string;
      kind: XlsxShapeKind;
      width: number;
      height: number;
      text: string;
      profile: Record<string, string>;
    }
  | {
      operation: "setShapeXlsx";
      revision: number;
      sheet: string;
      objectId: string;
      settings: XlsxShapeSettings;
      profile: Record<string, string>;
    }
  | {
      operation: "deleteShapeXlsx";
      revision: number;
      sheet: string;
      objectId: string;
      profile: Record<string, string>;
    }
  | { operation: "openXlsx"; bytes: Uint8Array; budget: Budget; date: string }
  | { operation: "createXlsx"; budget: Budget; date: string }
  | {
      operation: "importXlsxDelimited";
      date: string;
      bytes: Uint8Array;
      delimiter: "," | "\t";
      budget: Budget;
      options: Required<XlsxDelimitedOptions>;
    }
  | {
      operation: "picturesXlsx";
      revision: number;
      sheet: string;
      profile: Record<string, string>;
    }
  | { operation: "pictureResourceXlsx"; revision: number; bytes: Uint8Array }
  | {
      operation: "captureDrawingXlsx";
      revision: number;
      sheet: string;
      objectId: string;
      profile: Record<string, string>;
    }
  | {
      operation: "drawingFragmentImageXlsx";
      revision: number;
      fragment: string;
    }
  | {
      operation: "pasteDrawingXlsx";
      revision: number;
      sheet: string;
      fragment: string;
      profile: Record<string, string>;
    }
  | {
      operation: "selectDrawingXlsx";
      revision: number;
      layout: number;
      objectId: string | null;
    }
  | {
      operation: "drawingGestureXlsx";
      revision: number;
      layout: number;
      handle: number;
      dx: number;
      dy: number;
      commit: boolean;
      viewport?: {
        originX: number;
        originY: number;
        scrollX: number;
        scrollY: number;
      };
      profile: Record<string, string>;
    }
  | { operation: "imageBytesXlsx"; revision: number; key: string }
  | {
      operation: "imageXlsx";
      revision: number;
      key: string;
      width: number;
      height: number;
      bytes: Uint8Array;
    }
  | {
      operation: "insertPictureXlsx";
      revision: number;
      sheet: string;
      width: number;
      height: number;
      bytes: Uint8Array;
      profile: Record<string, string>;
      name: string;
      description: string;
    }
  | {
      operation: "setPictureXlsx";
      revision: number;
      sheet: string;
      pictureId: string;
      settings: XlsxPictureSettings;
      profile: Record<string, string>;
    }
  | {
      operation: "replacePictureXlsx";
      revision: number;
      sheet: string;
      pictureId: string;
      bytes: Uint8Array;
      profile: Record<string, string>;
    }
  | {
      operation: "deletePictureXlsx";
      revision: number;
      sheet: string;
      pictureId: string;
      profile: Record<string, string>;
    }
  | { operation: "exportXlsxCsv"; revision: number; selection: boolean }
  | {
      operation: "findXlsx";
      revision: number;
      sheet: string;
      text: string;
      options: XlsxFindOptions;
    }
  | {
      operation: "replaceXlsxMatches";
      revision: number;
      sheet: string;
      text: string;
      options: XlsxFindOptions;
      replacement: string;
      index?: number | undefined;
    }
  | {
      operation: "autoFitXlsx";
      revision: number;
      sheet: string;
      first: number;
      last: number;
      axis: "rows" | "columns";
      profile: Record<string, string>;
    }
  | { operation: "formatXlsxCells"; revision: number; patch: XlsxCellFormat }
  | { operation: "captureXlsxFormat"; revision: number }
  | {
      operation: "applyXlsxFormat";
      revision: number;
      format: CopiedCellFormat;
    }
  | {
      operation: "editXlsxSheet";
      date: string;
      revision: number;
      sheet: string;
      change: XlsxSheetEdit;
    }
  | {
      operation: "queryXlsx";
      sheet?: string | undefined;
      range?: string | undefined;
    }
  | { operation: "selectXlsx"; revision: number; sheet: string; range: string }
  | {
      operation: "replaceXlsx";
      revision: number;
      sheet: string;
      range: string;
      values: string[][];
      literal: boolean;
      acceptWarnings: boolean;
    }
  | { operation: "undoXlsx" | "redoXlsx"; revision: number }
  | { operation: "saveXlsx" }
  | ({ operation: "viewportXlsx" } & GridViewport)
  | { operation: "hitXlsx"; layoutId: number; x: number; y: number }
  | { operation: "selectionXlsx"; layoutId: number }
  | { operation: "fillPreviewXlsx"; layoutId: number; target: XlsxFillTarget }
  | {
      operation: "navigateXlsx";
      revision: number;
      direction: "left" | "right" | "up" | "down" | "home";
      extend: boolean;
    }
  | { operation: "copyXlsx" | "captureXlsxCells"; revision: number }
  | {
      operation: "pasteXlsxCells";
      revision: number;
      copied: CopiedCells;
      mode: XlsxPasteMode;
      transpose: boolean;
      acceptWarnings: boolean;
    }
  | { operation: "clearXlsx"; revision: number; mode: XlsxClearMode }
  | {
      operation: "pasteXlsx";
      revision: number;
      text: string;
      acceptWarnings: boolean;
    }
  | {
      operation: "printXlsx";
      revision: number;
      sheet: string;
      profile: Record<string, string>;
      options: PrintOptions | null;
    }
  | { operation: "exportXlsxPdf"; layoutId: number; outputBytes: number }
  | { operation: "font"; bytes: Uint8Array; identity: string }
  | { operation: "budget" };
export type Request = Operation & { id: number };
