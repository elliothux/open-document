import type {
  XlsxPivotSettings,
  XlsxSlicerSettings,
} from "@open-document/wasm/xlsx";

export type XlsxAnalysisRequest =
  | { operation: "pivotsXlsx" | "slicersXlsx"; revision: number; sheet: string }
  | {
      operation: "pivotPreviewXlsx";
      revision: number;
      settings: XlsxPivotSettings;
    }
  | {
      operation: "insertXlsxSlicer";
      revision: number;
      sheet: string;
      settings: XlsxSlicerSettings;
      profile: Record<string, string>;
    };
