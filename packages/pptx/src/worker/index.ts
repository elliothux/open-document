import { serveDocument } from "@open-document/web-core/worker";
import type { OfficeCommand } from "@open-document/web-core/protocol";
import type { PptxCommand } from "../core/pptx-command.js";
import { instantiatePptx } from "../core/engine.js";
serveDocument(
  instantiatePptx,
  (session, command: OfficeCommand<PptxCommand>) =>
    command.operation === "budget"
      ? session.defaultBudget()
      : session.execute(command),
);
