import {
  WasmSession,
  checkByteInput,
  type InputLimits,
} from "@open-document/wasm/abi/session";

import type {
  PdfBudget,
  PdfCommand,
  PdfLayout,
  PdfQuery,
  PdfResult,
} from "./pdf-types.js";
export type * from "./pdf-types.js";

export interface PdfInputLimits extends InputLimits {
  readonly exportBytes: number;
  readonly rgbaBytes: number;
  readonly importBytes: number;
  readonly inkStrokeCount: number;
  readonly inkCoordinates: number;
  readonly textUnits: number;
}

export function checkPdfByteInput(
  command: PdfCommand,
  limits: PdfInputLimits,
): void {
  if (!("bytes" in command)) return;
  checkByteInput(
    command.bytes,
    command.operation === "openPdf"
      ? command.budget.fileBytes
      : command.operation === "insertPdfPages" ||
          command.operation === "replacePdfPages"
        ? limits.importBytes
        : limits.rgbaBytes,
  );
}

const operations: ReadonlySet<string> = new Set([
  "rasterHeaderPdf",
  "defaultPdfBudget",
  "defaultPdfOfficeBudget",
  "convertPdfOffice",
  "previewPdfRedaction",
  "exportPdfRedaction",
  "openPdf",
  "createPdf",
  "queryPdf",
  "pdfObjects",
  "addPdfText",
  "setPdfPageNumbers",
  "createPdfField",
  "pdfFieldDesign",
  "updatePdfFieldDesign",
  "renamePdfField",
  "deletePdfField",
  "duplicatePdfField",
  "replacePdfText",
  "addPdfImage",
  "movePdfObject",
  "cropPdfImage",
  "deletePdfObject",
  "selectPdfRange",
  "selectedPdfRange",
  "cropPdfPage",
  "resizePdfPage",
  "pdfNavigation",
  "insertPdfPages",
  "replacePdfPages",
  "insertBlankPdfPage",
  "extractPdfPages",
  "splitPdfFiles",
  "splitPdfPage",
  "splitPdfPageGrid",
  "nupPdfPages",
  "exportPdfText",
  "pdfMetadata",
  "setPdfMetadata",
  "renderPdfPage",
  "releasePdfView",
  "extractPdfText",
  "searchPdfPage",
  "hitTestPdf",
  "selectPdf",
  "selectedPdfText",
  "imagePdf",
  "decodedImagePdf",
  "reorderPdfPages",
  "rotatePdfPages",
  "deletePdfPages",
  "addPdfNote",
  "highlightPdfText",
  "markPdfText",
  "addPdfDrawingAnnotation",
  "pdfAnnotation",
  "pdfAnnotationThread",
  "editPdfAnnotation",
  "replyPdfAnnotation",
  "deletePdfAnnotationThread",
  "addPdfInkAnnotation",
  "addPdfStampAnnotation",
  "updatePdfAnnotation",
  "deletePdfAnnotation",
  "setPdfFieldValue",
  "undoPdf",
  "redoPdf",
  "savePdf",
]);
export function isPdfCommand(value: {
  operation: string;
}): value is PdfCommand {
  return operations.has(value.operation);
}
/** Decode compact display and byte payloads at the Wasm boundary. */
function decodePdfOutput<C extends PdfCommand>(
  command: C,
  value: unknown,
  decode: (slot: number) => Uint8Array,
): PdfResult<C> {
  if (command.operation === "renderPdfPage") {
    const { spans, ...layout } = value as Omit<PdfLayout, "spans"> & {
      spans: [
        start: number,
        end: number,
        text: string,
        quad:
          | [number, number, number, number]
          | [number, number, number, number, number, number, number, number],
        source: string,
        mapped: boolean,
        invisible: boolean,
      ][];
    };
    value = {
      ...layout,
      spans: spans.map(
        ([start, end, text, quad, source, mapped, invisible]) => {
          const [x0, y0, x2, y2] = quad;
          return {
            start,
            end,
            text,
            quad: quad.length === 4 ? [x0, y0, x0, y2, x2, y2, x2, y0] : quad,
            source,
            mapped,
            invisible,
          };
        },
      ),
    } satisfies PdfLayout;
  } else if (
    command.operation === "rasterHeaderPdf" &&
    value !== null &&
    typeof value === "object" &&
    "bytes" in value &&
    typeof value.bytes === "number"
  ) {
    value = { ...value, bytes: decode(value.bytes) };
  } else if (command.operation === "splitPdfFiles") {
    const output = value as { files: { name: string; bytes: number }[] };
    value = {
      ...output,
      files: output.files.map((file) => ({
        ...file,
        bytes: decode(file.bytes),
      })),
    };
  } else if (
    command.operation === "convertPdfOffice" ||
    command.operation === "exportPdfRedaction" ||
    command.operation === "exportPdfText" ||
    command.operation === "savePdf" ||
    command.operation === "extractPdfPages" ||
    command.operation === "imagePdf" ||
    command.operation === "decodedImagePdf"
  ) {
    const output = value as { bytes: number | null };
    value = {
      ...output,
      bytes: output.bytes === null ? null : decode(output.bytes),
    };
  }
  return value as PdfResult<C>;
}
/** PDF input and edits share one source object graph and one bounded history. */
export class PdfSession extends WasmSession<PdfInputLimits> {
  constructor(exports: WebAssembly.Exports, handle: unknown) {
    super(exports, handle, "pdf");
  }

  defaultPdfBudget(): PdfBudget {
    return this.execute({ operation: "defaultPdfBudget" });
  }
  /** @internal Used by the file-owning Worker. */
  defaultFileBudget(): PdfBudget {
    return this.call({ operation: "pdfFileBudget" });
  }
  /** @internal Used by the file-owning Worker. */
  startReader(size: number, budget: PdfBudget): void {
    this.call({ operation: "startPdfReader", size, budget });
  }
  /** @internal Used by the file-owning Worker. */
  openReader(): PdfQuery {
    return this.call({ operation: "openPdfReader" });
  }
  /** @internal Used by the file-owning Worker. */
  supplyRange(bytes: Uint8Array): void {
    this.call({ operation: "supplyPdfRange", bytes });
  }
  /** @internal Used by the file-owning Worker. */
  cancelRange(): void {
    this.call({ operation: "cancelPdfRange" });
  }
  execute<C extends PdfCommand>(command: C): PdfResult<C> {
    if (
      command.operation === "openPdf" ||
      command.operation === "rasterHeaderPdf" ||
      command.operation === "insertPdfPages" ||
      command.operation === "replacePdfPages" ||
      command.operation === "addPdfImage" ||
      command.operation === "addPdfStampAnnotation" ||
      command.operation === "decodedImagePdf"
    )
      checkPdfByteInput(command, this.inputLimits());
    return decodePdfOutput(command, this.call(command), (slot) =>
      this.outputBytes(slot),
    );
  }
}
