import { serveDocument } from "@open-document/web-core/worker";
import {
  readSourceRanges,
  type RangeSource,
} from "@open-document/wasm/range-source";
import type { PdfCommand } from "../core/pdf-types.js";
import type { PdfSession } from "../core/pdf.js";
import { instantiatePdf } from "../core/engine.js";
import type { PdfFileCommand } from "../headless.js";
import { pdfFileSource } from "./file-source.js";

const files = new WeakMap<PdfSession, RangeSource>();

async function readFile<T>(
  session: PdfSession,
  file: RangeSource,
  run: () => T,
): Promise<T> {
  try {
    return await readSourceRanges(file, run, (bytes) =>
      session.supplyRange(bytes),
    );
  } catch (error) {
    session.cancelRange();
    throw error;
  }
}

serveDocument(
  instantiatePdf,
  async (session, command: PdfCommand | PdfFileCommand) => {
    if (command.operation === "pdfFileBudget")
      return session.defaultFileBudget();
    if (command.operation === "openPdfFile") {
      const { file } = command;
      if (!(file instanceof Blob)) throw new TypeError("Expected a PDF file");
      session.startReader(
        file.size,
        command.budget ?? session.defaultFileBudget(),
      );
      const source = pdfFileSource(file);
      const result = await readFile(session, source, () =>
        session.openReader(),
      );
      files.set(session, source);
      return result;
    }
    if (command.operation === "openPdf" || command.operation === "createPdf") {
      const result = session.execute(command);
      files.delete(session);
      return result;
    }
    const file = files.get(session);
    return file
      ? readFile(session, file, () => session.execute(command))
      : session.execute(command);
  },
);
