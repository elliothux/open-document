export type DocxTrackingRequest =
  | { operation: "docxTracking"; revision: number }
  | { operation: "setDocxTracking"; revision: number; author: string | null };
