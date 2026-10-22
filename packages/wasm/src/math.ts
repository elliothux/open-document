import type { TextStyle } from "./preview.js";
import { record } from "./validation.js";

export type MathExpression =
  | { kind: "root"; degree: MathExpression | null; radicand: MathExpression }
  | { kind: "text"; text: string }
  | { kind: "row"; children: MathExpression[] }
  | { kind: "fraction"; numerator: MathExpression; denominator: MathExpression }
  | {
      kind: "scripts";
      base: MathExpression;
      subscript: MathExpression | null;
      superscript: MathExpression | null;
    };

export interface MathFormula {
  expression: MathExpression;
  style: TextStyle;
}

export function checkMathContent(value: unknown): void {
  const math = record(value),
    style = record(math.style);
  if (
    typeof style.size !== "number" ||
    !Number.isFinite(style.size) ||
    style.size < 0.5 ||
    style.size > 409 ||
    typeof style.font !== "string" ||
    !style.font.length ||
    style.font.length > 1024 ||
    typeof style.color !== "string" ||
    !/^[a-fA-F0-9]{6}$/.test(style.color) ||
    style.script !== "baseline" ||
    style.spacing !== 0 ||
    style.underline !== false ||
    style.strike !== false ||
    style.highlight !== ""
  )
    throw new Error("Invalid mathematical style");
  let nodes = 0,
    units = 0;
  function visit(value: unknown, depth: number): void {
    if (depth > 16 || ++nodes > 256)
      throw new Error("Mathematical structure exceeds budget");
    const term = record(value);
    switch (term.kind) {
      case "root":
        if (term.degree !== null) visit(term.degree, depth + 1);
        visit(term.radicand, depth + 1);
        break;
      case "text":
        if (typeof term.text !== "string")
          throw new Error("Invalid mathematical text");
        units += term.text.length;
        if (units > 4096) throw new Error("Mathematical text exceeds budget");
        if (
          !term.text.length ||
          !term.text.isWellFormed() ||
          Array.from(term.text).some(
            (char) =>
              char.codePointAt(0)! < 32 ||
              ["\u2028", "\u2029", "\ufffe", "\uffff"].includes(char),
          )
        )
          throw new Error("Invalid mathematical text");
        break;
      case "row":
        if (
          !Array.isArray(term.children) ||
          term.children.length < 2 ||
          term.children.length > 256
        )
          throw new Error("Invalid mathematical row");
        for (const child of term.children) visit(child, depth + 1);
        break;
      case "fraction":
        visit(term.numerator, depth + 1);
        visit(term.denominator, depth + 1);
        break;
      case "scripts":
        if (term.subscript === null && term.superscript === null)
          throw new Error("Mathematical script requires an index");
        visit(term.base, depth + 1);
        if (term.subscript !== null) visit(term.subscript, depth + 1);
        if (term.superscript !== null) visit(term.superscript, depth + 1);
        break;
      default:
        throw new Error("Invalid mathematical expression");
    }
  }
  visit(math.expression, 0);
}
