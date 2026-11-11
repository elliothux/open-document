import { type EditState } from "./docx-format.js";

import {
  type DocxMathEdit,
  type DocxFractionEdit,
  type DocxScriptEdit,
  checkDocxFractionEdit,
  checkDocxScriptEdit,
  checkDocxMathEdit,
  type DocxMathFractions,
  type DocxMathScripts,
  type DocxMathExpressions,
} from "./docx-math.js";
import type { DocxRuntime } from "./docx-session.js";
export const docxMathCommands = {
  mathExpressions(session: DocxRuntime, { revision }: { revision: number }) {
    return session.call<DocxMathExpressions>({
      operation: "docxMathExpressions",
      revision,
    });
  },
  editMath(
    session: DocxRuntime,
    {
      revision,
      math,
      profile = {},
    }: {
      revision: number;
      math: DocxMathEdit;
      profile?: Record<string, string> | undefined;
    },
  ): EditState {
    checkDocxMathEdit(math);
    return session.call<EditState>({
      operation: "editDocxMath",
      revision,
      math,
      profile,
    });
  },
  mathFractions(session: DocxRuntime, { revision }: { revision: number }) {
    return session.call<DocxMathFractions>({
      operation: "docxMathFractions",
      revision,
    });
  },
  mathScripts(session: DocxRuntime, { revision }: { revision: number }) {
    return session.call<DocxMathScripts>({
      operation: "docxMathScripts",
      revision,
    });
  },
  editMathFraction(
    session: DocxRuntime,
    {
      revision,
      fraction,
      profile = {},
    }: {
      revision: number;
      fraction: DocxFractionEdit;
      profile?: Record<string, string> | undefined;
    },
  ): EditState {
    checkDocxFractionEdit(fraction);
    return session.call<EditState>({
      operation: "editDocxMathFraction",
      revision,
      fraction,
      profile,
    });
  },
  editMathScript(
    session: DocxRuntime,
    {
      revision,
      script,
      profile = {},
    }: {
      revision: number;
      script: DocxScriptEdit;
      profile?: Record<string, string> | undefined;
    },
  ): EditState {
    checkDocxScriptEdit(script);
    return session.call<EditState>({
      operation: "editDocxMathScript",
      revision,
      script,
      profile,
    });
  },
};
