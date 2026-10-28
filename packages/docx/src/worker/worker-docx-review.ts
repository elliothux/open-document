import type { FoundationSession } from "../core/foundation.js";
import type { Operation } from "./protocol.js";

type ReviewOperation = Extract<
  Operation,
  {
    operation:
      | "docxTracking"
      | "setDocxTracking"
      | "docxRevisions"
      | "docxRevisionGeometry"
      | "resolveDocxRevisions";
  }
>;

export function reviewOperation(
  foundation: FoundationSession,
  request: ReviewOperation,
): unknown {
  switch (request.operation) {
    case "docxTracking":
      return foundation.tracking(request.revision);
    case "setDocxTracking":
      return foundation.setTracking(request.revision, request.author);
    case "docxRevisions":
      return foundation.revisions(request.revision);
    case "docxRevisionGeometry":
      return foundation.revisionGeometry(
        request.revision,
        request.layoutId,
        request.revisionId,
      );
    case "resolveDocxRevisions":
      return foundation.resolveRevisions(request.revision, request.change);
  }
}
