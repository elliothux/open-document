import type { DrawRect } from "@open-document/wasm/abi/drawing";
import type { CellRange } from "./xlsx.js";

export interface XlsxFormulaDraft {
  revision: number;
  sheet: string;
  source: string;
  caret: number;
  layoutId?: number;
}

export interface XlsxFormulaSignature {
  name: string;
  parameters: string[];
}

export interface XlsxFormulaAssistance {
  completion: {
    start: number;
    end: number;
    appendParen: boolean;
    functions: XlsxFormulaSignature[];
  } | null;
  call: { signature: XlsxFormulaSignature; argument: number } | null;
  references: {
    label: string;
    sheet: string;
    range: CellRange;
    rects: DrawRect[];
  }[];
}
