import { serveDocument } from "@open-document/web-core/worker";
import type { PdfCommand } from "../core/pdf-types.js";
import { instantiatePdf } from "../core/engine.js";
serveDocument(instantiatePdf, (session, command: PdfCommand) =>
  session.execute(command),
);
