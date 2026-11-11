export interface ShapeBatch {
  text: string;
  carets: { offset: number; before: number; after: number }[];
  glyphs: {
    id: number;
    cluster: number;
    font: number;
    outline: string;
    strokeWidth: number;
    x: number;
    y: number;
    scale: number;
    advance: number;
    yAdvance: number;
    xOffset: number;
    yOffset: number;
  }[];
  outlines: { key: string; path: string }[];
  runs: {
    start: number;
    end: number;
    level: number;
    font: number;
    script: string;
    language: string;
  }[];
  fonts: {
    identity: string;
    sha256: string;
    face: number;
    variation: string;
    upem: number;
    ascent: number;
    descent: number;
    bbox: number[];
    capHeight: number;
    italicAngle: number;
  }[];
  diagnostics: { code: string; cluster: number; codepoint: number }[];
  width: number;
  fontBytes: number;
  outlineBytes: number;
}

export interface TextStyle {
  font: string;
  size: number;
  color: string;
  underline: boolean;
  strike: boolean;
  caps: boolean;
  highlight: string;
  script: "baseline" | "superscript" | "subscript";
  spacing: number;
  kerning: "all" | "words" | "none";
  fontLeading: boolean;
}

export type NavigationDirection =
  "left" | "right" | "up" | "down" | "home" | "end";
