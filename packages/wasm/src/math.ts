import type { TextStyle } from "./preview.js";
import { record } from "./validation.js";

export interface MathFormat {
  family: string;
  size: number;
  color: string;
}

export type MathExpression =
  | {
      kind: "equationArray";
      baseAlignment: "top" | "center" | "bottom";
      rows: (MathExpression | null)[][];
    }
  | {
      kind: "matrix";
      baseAlignment: "top" | "center" | "bottom";
      columnAlignments: ("left" | "center" | "right")[];
      rows: (MathExpression | null)[][];
    }
  | {
      kind: "nary";
      operator: string;
      limitLocation: "subSup" | "undOvr";
      lower: MathExpression | null;
      upper: MathExpression | null;
      body: MathExpression;
    }
  | {
      kind: "delimited";
      open: string;
      close: string;
      separator: string;
      arguments: MathExpression[];
    }
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
  display: boolean;
}

export function checkMathContent(value: unknown): void {
  const math = record(value),
    style = record(math.style);
  if (
    typeof math.display !== "boolean" ||
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
      case "equationArray":
      case "matrix": {
        if (
          typeof term.baseAlignment !== "string" ||
          !["top", "center", "bottom"].includes(term.baseAlignment) ||
          !Array.isArray(term.rows) ||
          term.rows.length < 1 ||
          term.rows.length > 64 ||
          (term.kind === "matrix" &&
            (!Array.isArray(term.columnAlignments) ||
              term.columnAlignments.length < 1 ||
              term.columnAlignments.length > 64 ||
              !term.columnAlignments.every(
                (value) =>
                  value === "left" || value === "center" || value === "right",
              ) ||
              term.rows.length * term.columnAlignments.length > 256))
        )
          throw new Error("Invalid mathematical rows or alignment");
        for (const row of term.rows) {
          if (
            !Array.isArray(row) ||
            row.length < 1 ||
            row.length > 64 ||
            (term.kind === "matrix" &&
              Array.isArray(term.columnAlignments) &&
              row.length !== term.columnAlignments.length)
          )
            throw new Error("Invalid mathematical row dimensions");
          for (const cell of row) {
            if (cell === null) {
              if (depth >= 16 || ++nodes > 256)
                throw new Error("Mathematical structure exceeds budget");
            } else visit(cell, depth + 1);
          }
        }
        break;
      }
      case "nary":
        if (
          typeof term.operator !== "string" ||
          term.operator.length !== 1 ||
          !"∑∏∐∫∬∭∮∯∰⋃⋂⋁⋀".includes(term.operator) ||
          (term.limitLocation !== "subSup" && term.limitLocation !== "undOvr")
        )
          throw new Error("Invalid n-ary operator or limit location");
        if (term.lower !== null) visit(term.lower, depth + 1);
        if (term.upper !== null) visit(term.upper, depth + 1);
        visit(term.body, depth + 1);
        break;
      case "delimited":
        if (
          ![term.open, term.close, term.separator].every(
            (value) =>
              typeof value === "string" &&
              ["", ..."()[]{}|‖⌈⌉⌊⌋⟨⟩"].includes(value),
          ) ||
          !Array.isArray(term.arguments) ||
          term.arguments.length < 1 ||
          term.arguments.length > 64
        )
          throw new Error("Invalid mathematical delimiter");
        for (const argument of term.arguments) visit(argument, depth + 1);
        break;
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
