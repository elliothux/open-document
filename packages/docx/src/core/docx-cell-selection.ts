import type { FormatValue } from "./docx-format.js";
import {
  type DocxCellMargins,
  type DocxCellBorders,
  type DocxBorderStyle,
} from "./docx-table.js";

export interface DocxCellSelection {
  reason: string;
  value: {
    table: number;
    top: number;
    bottom: number;
    left: number;
    right: number;
    count: number;
    fill: FormatValue<string | null>;
    verticalAlign: FormatValue<"top" | "center" | "bottom">;
    margins: Record<keyof DocxCellMargins, FormatValue<number>>;
    rowSplit: FormatValue<boolean>;
    rowHeight: FormatValue<number>;
    rowHeightRule: FormatValue<"atLeast" | "exact">;
    maxRowHeight: number;
    borders: Record<keyof DocxCellBorders, FormatValue<DocxBorderStyle>>;
  } | null;
}
