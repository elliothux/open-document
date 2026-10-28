import type { FoundationSession } from "../core/foundation.js";
import type { Operation } from "./protocol.js";

export function selectionOperation(
  session: FoundationSession,
  request: Extract<
    Operation,
    { operation: "selectDocx" | "selectAllDocx" | "selectedText" }
  >,
): unknown {
  switch (request.operation) {
    case "selectDocx":
      return session.selectDocx(request.revision, request.selection);
    case "selectAllDocx":
      return session.selectAllDocx(request.revision);
    case "selectedText":
      return session.selectedText(
        request.revision,
        request.selection,
        request.cut,
      );
  }
}
