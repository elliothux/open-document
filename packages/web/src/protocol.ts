import type {
  Budget,
  DocxSelection,
  DocxPosition,
  NavigationDirection,
  CharacterFormatPatch,
  ParagraphFormatPatch,
  DocxFindOptions,
  CopiedFormat,
  DocxStyleUpdate,
  DocxStyleCreation,
  DocxListEdit,
  DocxListLevelUpdate,
  DocxPageSetup,
  DocxTableEdit,
} from "@open-document/wasm/foundation";
import type {
  GridViewport,
  PrintOptions,
  XlsxSheetEdit,
  XlsxCellFormat,
  CopiedCellFormat,
  XlsxClearMode,
} from "@open-document/wasm/xlsx";
import type { PptxCommand } from "@open-document/wasm/pptx";
import type { PdfCommand } from "@open-document/wasm/pdf";

export type Operation =
  | {
      operation: "editDocxTable";
      revision: number;
      selection: DocxSelection;
      change: DocxTableEdit;
    }
  | { operation: "pageSetup"; revision: number }
  | { operation: "setPageSetup"; revision: number; page: DocxPageSetup }
  | {
      operation: "insertDocxTable";
      revision: number;
      selection: DocxSelection;
      rows: number;
      columns: number;
    }
  | {
      operation: "updateListLevel";
      revision: number;
      listId: number;
      level: number;
      definition: DocxListLevelUpdate;
    }
  | { operation: "listCatalog"; revision: number }
  | {
      operation: "editList";
      revision: number;
      selection: DocxSelection;
      change: DocxListEdit;
    }
  | {
      operation: "setDefaultTabStop";
      revision: number;
      interval: number | null;
    }
  | PptxCommand
  | PdfCommand
  | { operation: "openPdfWorker"; wasm: ArrayBuffer }
  | { operation: "openPresentation"; wasm: ArrayBuffer }
  | { operation: "open"; text: string; wasm: ArrayBuffer }
  | { operation: "read" | "undo" }
  | {
      operation: "replace";
      start: number;
      end: number;
      text: string;
    }
  | { operation: "openFoundation"; wasm: ArrayBuffer }
  | { operation: "openSpreadsheet"; wasm: ArrayBuffer }
  | { operation: "openXlsx"; bytes: Uint8Array; budget: Budget }
  | { operation: "createXlsx"; budget: Budget }
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
    }
  | { operation: "undoXlsx" | "redoXlsx"; revision: number }
  | { operation: "saveXlsx" }
  | ({ operation: "viewportXlsx" } & GridViewport)
  | { operation: "hitXlsx"; layoutId: number; x: number; y: number }
  | { operation: "selectionXlsx"; layoutId: number }
  | {
      operation: "navigateXlsx";
      revision: number;
      direction: "left" | "right" | "up" | "down" | "home";
      extend: boolean;
    }
  | { operation: "copyXlsx"; revision: number }
  | { operation: "clearXlsx"; revision: number; mode: XlsxClearMode }
  | { operation: "pasteXlsx"; revision: number; text: string }
  | ({
      operation: "printXlsx";
      revision: number;
      sheet: string;
      profile: Record<string, string>;
    } & PrintOptions)
  | { operation: "exportXlsxPdf"; layoutId: number; outputBytes: number }
  | { operation: "font"; bytes: Uint8Array; identity: string }
  | { operation: "shape"; text: string; size: number; language: string }
  | { operation: "openDocx"; bytes: Uint8Array; budget: Budget }
  | { operation: "createDocx"; budget: Budget }
  | { operation: "tabDocx"; revision: number; backward: boolean }
  | { operation: "enterDocx"; revision: number }
  | {
      operation: "styleCatalog";
      revision: number;
      kind: "paragraph" | "character";
    }
  | {
      operation: "findDocx";
      revision: number;
      text: string;
      options: DocxFindOptions;
    }
  | {
      operation: "replaceDocxMatches";
      revision: number;
      matches: DocxSelection[];
      text: string;
    }
  | {
      operation: "queryFormatting" | "captureFormat";
      revision: number;
      selection: DocxSelection;
    }
  | {
      operation: "applyFormat";
      revision: number;
      selection: DocxSelection;
      format: CopiedFormat;
    }
  | {
      operation: "updateStyle";
      revision: number;
      key: string;
      format: DocxStyleUpdate;
    }
  | {
      operation: "createStyle";
      revision: number;
      style: DocxStyleCreation;
    }
  | {
      operation: "deleteStyle";
      revision: number;
      key: string;
      replacement: string;
    }
  | {
      operation: "setCharacterFormat";
      revision: number;
      selection: DocxSelection;
      format: CharacterFormatPatch;
    }
  | {
      operation: "setParagraphFormat";
      revision: number;
      selection: DocxSelection;
      format: ParagraphFormatPatch;
    }
  | { operation: "budget" | "query" | "saveDocx" | "flow" | "editState" }
  | {
      operation: "selectDocx" | "selectedText";
      revision: number;
      selection: DocxSelection;
    }
  | {
      operation: "replaceRange";
      revision: number;
      selection: DocxSelection;
      text: string;
      inputGroup?: number | undefined;
    }
  | { operation: "undoDocx" | "redoDocx"; revision: number }
  | { operation: "beginComposition"; revision: number }
  | {
      operation: "updateComposition" | "commitComposition";
      revision: number;
      compositionId: number;
      text: string;
    }
  | { operation: "cancelComposition"; revision: number; compositionId: number }
  | {
      operation: "deleteDocx";
      revision: number;
      direction: "backward" | "forward";
    }
  | { operation: "layout"; profile: Record<string, string> }
  | {
      operation: "hitTest";
      layoutId: number;
      page: number;
      x: number;
      y: number;
    }
  | { operation: "caret"; layoutId: number; position: DocxPosition }
  | {
      operation: "navigateDocx";
      revision: number;
      layoutId: number;
      direction: NavigationDirection;
      extend: boolean;
    }
  | {
      operation: "selectionGeometry";
      layoutId: number;
      selection: DocxSelection;
    }
  | {
      operation: "exportPdf";
      outputBytes: number;
      layoutId?: number | undefined;
    }
  | { operation: "imageBytes"; key: string }
  | {
      operation: "image";
      key: string;
      width: number;
      height: number;
      bytes: Uint8Array;
    }
  | { operation: "replaceNode"; node: number; revision: number; text: string };

export type Request = Operation & { id: number };

export type Response =
  | { id: number; ok: true; value: unknown }
  | {
      id: number;
      ok: false;
      error: string;
      code?: string;
      part?: string;
      offset?: number;
    };
