import type {
  XlsxPivotSettings,
  XlsxSlicerSettings,
  XlsxSlicerFrame,
  XlsxTimelineSettings,
} from "@open-document/wasm/xlsx";

export type XlsxAnalysisRequest =
  | {
      operation: "frameXlsxSlicer";
      revision: number;
      sheet: string;
      slicerId: string;
      frame: XlsxSlicerFrame;
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
