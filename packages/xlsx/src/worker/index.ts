import { serveDocument } from "@open-document/web-core/worker";
import type { OfficeCommand } from "@open-document/web-core/protocol";
import type { XlsxCommand } from "../core/xlsx-command.js";
import { instantiateXlsx } from "../core/engine.js";
serveDocument(
  instantiateXlsx,
  (session, command: OfficeCommand<XlsxCommand>) =>
    command.operation === "budget"
      ? session.defaultBudget()
      : session.executeWire(command),
);
