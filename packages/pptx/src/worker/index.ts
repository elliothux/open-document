import { serveDocument } from "@open-document/web-core/worker";
import type { OfficeCommand } from "@open-document/web-core/protocol";
import type { PptxCommand } from "../core/pptx-command.js";
import { instantiatePptx } from "../core/engine.js";
import type { PptxSession } from "../core/pptx.js";
import { readPptxFile, type PptxFileCommand } from "./file.js";

const files = new WeakMap<PptxSession, Blob>();

serveDocument(
  instantiatePptx,
  async (session, command: OfficeCommand<PptxCommand | PptxFileCommand>) => {
    if (command.operation === "budget") return session.defaultBudget();
    if (command.operation === "fileBudgetPptx") return session.fileBudget();
    if (command.operation === "openPptxFile") {
      const { file, dateTime } = command;
      if (!(file instanceof Blob)) throw new TypeError("Expected a PPTX file");
      const budget = command.budget ?? session.fileBudget();
      session.startReader(file.size, budget, dateTime);
      const result = await readPptxFile(session, file, () =>
        session.openReader(),
      );
      files.set(session, file);
      return result;
    }
    const file = files.get(session);
    if (!file) return session.execute(command);
    if (
      command.operation === "prepareImagePptx" ||
      command.operation === "mediaBytesPptx" ||
      command.operation === "controlShowPptx" ||
      command.operation === "layoutShowPptx" ||
      command.operation === "inkShowPptx" ||
      command.operation === "mediaShowPptx" ||
      command.operation === "savePptx"
    )
      return readPptxFile(session, file, () => session.execute(command));
    try {
      return session.execute(command);
    } catch (error) {
      session.cancelRange();
      throw error;
    }
  },
);
