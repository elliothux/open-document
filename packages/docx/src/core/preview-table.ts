import type { DocxFlow } from "./preview.js";
import type { DocxBorderStyle, DocxCellMargins } from "./docx-table.js";

export interface DocxFlowTable {
  autoFit: boolean;
  preferredWidth: { value: number; percent: boolean };
  preferredWidths: DocxFlowTable["preferredWidth"][][];
  id: number;
  beforeParagraph: number;
  legacyCellAlignment: boolean;
  nestedTables: { row: number; column: number; table: DocxFlowTable }[];
  rows: DocxFlow["paragraphs"][][];
  widths: number[];
  align: string;
  borders: { horizontal: DocxBorderStyle[][]; vertical: DocxBorderStyle[][] };
  margins: DocxCellMargins[][];
  heights: number[];
  exactHeights: boolean[];
  splitRows: boolean[];
  fills: string[][];
  verticalAligns: ("top" | "center" | "bottom")[][];
  headerRows: number;
}
