import { serveDocument } from "@open-document/web-core/worker";
import type { OfficeCommand } from "@open-document/web-core/protocol";
import type { DocxCommand } from "../core/docx-command.js";
import { instantiateDocx } from "../core/engine.js";
serveDocument(
  instantiateDocx,
  (session, command: OfficeCommand<DocxCommand>) =>
    command.operation === "budget"
      ? session.defaultBudget()
      : session.execute(command),
);
