export type Request =
  | { id: number; operation: "open"; text: string; wasm: ArrayBuffer }
  | { id: number; operation: "read" | "undo" }
  | {
      id: number;
      operation: "replace";
      start: number;
      end: number;
      text: string;
    };

export type Response =
  | { id: number; ok: true; text: string }
  | { id: number; ok: false; error: string };
