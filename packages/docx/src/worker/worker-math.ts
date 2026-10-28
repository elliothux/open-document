import type { FoundationSession } from "../core/foundation.js";
import type { Operation } from "./protocol.js";

export type MathOperation = Extract<
  Operation,
  {
    operation:
      | "docxMathFractions"
      | "docxMathScripts"
      | "docxMathExpressions"
      | "editDocxMathFraction"
      | "editDocxMathScript"
      | "editDocxMath";
  }
>;

export function mathOperation(
  session: FoundationSession,
  request: MathOperation,
) {
  switch (request.operation) {
    case "docxMathFractions":
      return session.mathFractions(request.revision);
    case "docxMathScripts":
      return session.mathScripts(request.revision);
    case "docxMathExpressions":
      return session.mathExpressions(request.revision);
    case "editDocxMathFraction":
      return session.editMathFraction(
        request.revision,
        request.fraction,
        request.profile,
      );
    case "editDocxMathScript":
      return session.editMathScript(
        request.revision,
        request.script,
        request.profile,
      );
    case "editDocxMath":
      return session.editMath(request.revision, request.math, request.profile);
  }
}
