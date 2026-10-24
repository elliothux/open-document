import type {
  XlsxPivotSettings,
  XlsxSlicerSettings,
  XlsxDrawingFrame,
  XlsxTimelineSettings,
  XlsxTimelineGesture,
} from "@open-document/wasm/xlsx";

export type XlsxAnalysisRequest =
  | ({
      operation: "timelineGestureXlsx";
      revision: number;
      layout: number;
      objectId: string;
      profile: Record<string, string>;
    } & XlsxTimelineGesture)
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
