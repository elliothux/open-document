import type {
  DocxRevisionEdit,
  DocxPasteMode,
  Budget,
  DocxRuler,
  DocxRulerEdit,
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
  DocxPageNumbering,
  DocxColumns,
  DocxPageBorders,
  DocxRunningKind,
  DocxRunningVariant,
  DocxRunningContent,
  DocxPageField,
  DocxPictureEdit,
  DocxPictureResizeCommand,
  DocxTableEdit,
  DocxThemeSlot,
  DocxThemeFontEdit,
  DocxBookmarkEdit,
  DocxCommentEdit,
} from "@open-document/wasm/foundation";
import type {
  GridViewport,
  XlsxDuplicateSettings,
  XlsxPivotSettings,
  PrintOptions,
  XlsxSheetEdit,
  XlsxCellFormat,
  CopiedCellFormat,
  XlsxClearMode,
  CopiedCells,
  XlsxPasteMode,
  XlsxFindOptions,
  XlsxDelimitedOptions,
  XlsxTextColumnSettings,
  XlsxFillTarget,
  XlsxPictureSettings,
  XlsxShapeKind,
  XlsxShapeSettings,
} from "@open-document/wasm/xlsx";
import type { PptxCommand } from "@open-document/wasm/pptx";
import type { PdfCommand } from "@open-document/wasm/pdf";

export type Operation =
  | {
      operation: "shapesXlsx";
      revision: number;
      sheet: string;
      profile: Record<string, string>;
    }
  | {
      operation: "insertShapeXlsx";
      revision: number;
      sheet: string;
      kind: XlsxShapeKind;
      width: number;
      height: number;
      text: string;
      profile: Record<string, string>;
    }
  | {
      operation: "setShapeXlsx";
      revision: number;
      sheet: string;
      objectId: string;
      settings: XlsxShapeSettings;
      profile: Record<string, string>;
    }
  | {
      operation: "deleteShapeXlsx";
      revision: number;
      sheet: string;
      objectId: string;
      profile: Record<string, string>;
    }
  | { operation: "pivotsXlsx"; revision: number; sheet: string }
  | {
      operation: "pivotPreviewXlsx";
      revision: number;
      settings: XlsxPivotSettings;
    }
  | { operation: "docxRuler"; revision: number }
  | { operation: "editDocxRuler"; source: DocxRuler; change: DocxRulerEdit }
  | {
      operation: "textColumnsXlsx";
      revision: number;
      sheet: string;
      settings: XlsxTextColumnSettings;
    }
  | {
      operation: "duplicatesXlsx";
      revision: number;
      sheet: string;
      settings: XlsxDuplicateSettings;
    }
  | { operation: "editBookmark"; revision: number; change: DocxBookmarkEdit }
  | { operation: "docxComments"; revision: number }
  | { operation: "docxRevisions"; revision: number }
  | {
      operation: "docxRevisionGeometry";
      revision: number;
      layoutId: number;
      revisionId: string;
    }
  | {
      operation: "resolveDocxRevisions";
      revision: number;
      change: DocxRevisionEdit;
    }
  | {
      operation: "navigateComment";
      revision: number;
      direction: "previous" | "next";
    }
  | { operation: "editDocxComment"; revision: number; change: DocxCommentEdit }
  | {
      operation: "setHyperlink";
      revision: number;
      selection: DocxSelection;
      target: string | null;
      text?: string;
    }
  | { operation: "docxThemeFonts"; revision: number }
  | {
      operation: "setDocxThemeFonts";
      revision: number;
      fonts: DocxThemeFontEdit[];
      profile: Record<string, string>;
    }
  | { operation: "docxThemeColors"; revision: number }
  | {
      operation: "setDocxThemeColor";
      revision: number;
      slot: DocxThemeSlot;
      color: string;
    }
  | { operation: "docxOverview"; revision: number }
  | {
      operation: "docxPictureResize";
      revision: number;
      change: DocxPictureResizeCommand;
      profile: Record<string, string>;
    }
  | { operation: "docxPictures"; revision: number }
  | {
      operation: "editDocxPicture";
      revision: number;
      picture: DocxPictureEdit;
      profile: Record<string, string>;
    }
  | {
      operation: "editDocxTable";
      profile: Record<string, string>;
      revision: number;
      selection: DocxSelection;
      change: DocxTableEdit;
    }
  | {
      operation: "setRunningOptions";
      revision: number;
      first: boolean;
      even: boolean;
      profile: Record<string, string>;
    }
  | { operation: "pageSetup"; revision: number }
  | { operation: "documentProtection"; revision: number }
  | {
      operation: "setDocumentProtection";
      revision: number;
      enabled: boolean;
      password: string;
    }
  | { operation: "bodyPageField"; revision: number; selection: DocxSelection }
  | {
      operation: "editBodyPageField";
      revision: number;
      selection: DocxSelection;
      field: DocxPageField;
      profile: Record<string, string>;
    }
  | {
      operation: "insertBodyPageField";
      revision: number;
      field: DocxPageField;
      profile: Record<string, string>;
    }
  | {
      operation: "updateBodyPageFields";
      revision: number;
      profile: Record<string, string>;
    }
  | {
      operation: "setPageColumns";
      revision: number;
      columns: DocxColumns | null;
      profile: Record<string, string>;
    }
  | {
      operation: "runningArea";
      revision: number;
      kind: DocxRunningKind;
      variant: DocxRunningVariant;
    }
  | {
      operation: "unlinkRunningArea";
      revision: number;
      kind: DocxRunningKind;
      variant: DocxRunningVariant;
      profile: Record<string, string>;
    }
  | {
      operation: "setRunningArea";
      revision: number;
      kind: DocxRunningKind;
      variant: DocxRunningVariant;
      content: DocxRunningContent[];
      distance: number;
      profile: Record<string, string>;
    }
  | { operation: "setPageBackground"; revision: number; color: string | null }
  | {
      operation: "setPageBorders";
      revision: number;
      borders: DocxPageBorders | null;
    }
  | { operation: "setPageSetup"; revision: number; page: DocxPageSetup }
  | {
      operation: "setPageNumbering";
      revision: number;
      numbering: DocxPageNumbering | null;
      profile: Record<string, string>;
    }
  | {
      operation: "insertDocxTable";
      revision: number;
      selection: DocxSelection;
      rows: number;
      columns: number;
      profile: Record<string, string>;
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
  | { operation: "openXlsx"; bytes: Uint8Array; budget: Budget; date: string }
  | { operation: "createXlsx"; budget: Budget; date: string }
  | {
      operation: "importXlsxDelimited";
      date: string;
      bytes: Uint8Array;
      delimiter: "," | "\t";
      budget: Budget;
      options: Required<XlsxDelimitedOptions>;
    }
  | {
      operation: "picturesXlsx";
      revision: number;
      sheet: string;
      profile: Record<string, string>;
    }
  | { operation: "pictureResourceXlsx"; revision: number; bytes: Uint8Array }
  | {
      operation: "selectDrawingXlsx";
      revision: number;
      layout: number;
      objectId: string | null;
    }
  | {
      operation: "drawingGestureXlsx";
      revision: number;
      layout: number;
      handle: number;
      dx: number;
      dy: number;
      commit: boolean;
      profile: Record<string, string>;
    }
  | { operation: "imageBytesXlsx"; revision: number; key: string }
  | {
      operation: "imageXlsx";
      revision: number;
      key: string;
      width: number;
      height: number;
      bytes: Uint8Array;
    }
  | {
      operation: "insertPictureXlsx";
      revision: number;
      sheet: string;
      width: number;
      height: number;
      bytes: Uint8Array;
      profile: Record<string, string>;
      name: string;
      description: string;
    }
  | {
      operation: "setPictureXlsx";
      revision: number;
      sheet: string;
      pictureId: string;
      settings: XlsxPictureSettings;
      profile: Record<string, string>;
    }
  | {
      operation: "deletePictureXlsx";
      revision: number;
      sheet: string;
      pictureId: string;
      profile: Record<string, string>;
    }
  | { operation: "exportXlsxCsv"; revision: number; selection: boolean }
  | {
      operation: "findXlsx";
      revision: number;
      sheet: string;
      text: string;
      options: XlsxFindOptions;
    }
  | {
      operation: "replaceXlsxMatches";
      revision: number;
      sheet: string;
      text: string;
      options: XlsxFindOptions;
      replacement: string;
      index?: number | undefined;
    }
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
      date: string;
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
      acceptWarnings: boolean;
    }
  | { operation: "undoXlsx" | "redoXlsx"; revision: number }
  | { operation: "saveXlsx" }
  | ({ operation: "viewportXlsx" } & GridViewport)
  | { operation: "hitXlsx"; layoutId: number; x: number; y: number }
  | { operation: "selectionXlsx"; layoutId: number }
  | { operation: "fillPreviewXlsx"; layoutId: number; target: XlsxFillTarget }
  | {
      operation: "navigateXlsx";
      revision: number;
      direction: "left" | "right" | "up" | "down" | "home";
      extend: boolean;
    }
  | { operation: "copyXlsx" | "captureXlsxCells"; revision: number }
  | {
      operation: "pasteXlsxCells";
      revision: number;
      copied: CopiedCells;
      mode: XlsxPasteMode;
      transpose: boolean;
      acceptWarnings: boolean;
    }
  | { operation: "clearXlsx"; revision: number; mode: XlsxClearMode }
  | {
      operation: "pasteXlsx";
      revision: number;
      text: string;
      acceptWarnings: boolean;
    }
  | {
      operation: "printXlsx";
      revision: number;
      sheet: string;
      profile: Record<string, string>;
      options: PrintOptions | null;
    }
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
      operation: "exportDocxMarkup";
      revision: number;
      format: "html" | "markdown";
      outputBytes: number;
    }
  | {
      operation: "selectDocx";
      revision: number;
      selection: DocxSelection;
    }
  | {
      operation: "tableClipboard" | "docxClipboard";
      revision: number;
      selection: DocxSelection;
      cut: boolean;
    }
  | {
      operation: "tableFragmentImages" | "bodyFragmentImages";
      revision: number;
      fragment: string;
    }
  | {
      operation: "pasteBodyFragment";
      revision: number;
      selection: DocxSelection;
      fragment: string;
      profile: Record<string, string>;
    }
  | {
      operation: "pasteMarkdown";
      revision: number;
      selection: DocxSelection;
      markdown: string;
      profile: Record<string, string>;
      mode: DocxPasteMode;
    }
  | {
      operation: "pasteHtml";
      revision: number;
      selection: DocxSelection;
      html: string;
      profile: Record<string, string>;
      mode: DocxPasteMode;
    }
  | {
      operation: "markupImages";
      revision: number;
      kind: "html" | "markdown";
      input: string;
      mode: DocxPasteMode;
    }
  | {
      operation: "selectedText";
      revision: number;
      selection: DocxSelection;
      cut: boolean;
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
