import type { DocxBorderStyle } from "./docx-table.js";

export interface ParagraphFrame {
  width: number;
  height: number;
  heightRule: string;
  horizontalAnchor: string;
  verticalAnchor: string;
  x?: number;
  y?: number;
  horizontalAlign: string;
  verticalAlign: string;
  horizontalSpace: number;
  verticalSpace: number;
  borders: Record<string, [number, DocxBorderStyle]>;
}
