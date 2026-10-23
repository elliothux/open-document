import type {
  XlsxPivotSettings,
  XlsxSlicerSettings,
  XlsxDrawingFrame,
  XlsxTimelineSettings,
} from "@open-document/wasm/xlsx";

export type XlsxAnalysisRequest =
  | {
      operation: "frameXlsxSlicer" | "frameXlsxTimeline";
      revision: number;
      sheet: string;
      objectId: string;
      frame: XlsxDrawingFrame;
      profile: Record<string, string>;
    }
  | {
      operation: "pivotsXlsx" | "slicersXlsx" | "timelinesXlsx";
      revision: number;
      sheet: string;
    }
  | {
      operation: "pivotPreviewXlsx";
      revision: number;
      settings: XlsxPivotSettings;
      part?: string;
    }
  | {
      operation: "insertXlsxTimeline";
      revision: number;
      sheet: string;
      settings: XlsxTimelineSettings;
      profile: Record<string, string>;
    }
  | {
      operation: "insertXlsxSlicer";
      revision: number;
      sheet: string;
      settings: XlsxSlicerSettings;
      profile: Record<string, string>;
    };
