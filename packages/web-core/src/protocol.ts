export type WorkerInitialization = {
  operation: "initialize";
  module?: WebAssembly.Module;
};

export type WorkerControl =
  | WorkerInitialization
  | { operation: "font"; bytes: Uint8Array; identity: string };

export type WorkerOperation<Command> = WorkerControl | Command;
export type OfficeCommand<Command> = Command | { operation: "budget" };

export interface Request<Operation> {
  id: number;
  command: Operation;
}

export type Response =
  | { id: number; ok: true; value: unknown; reusable?: true }
  | {
      id: number;
      ok: false;
      error: string;
      code?: string;
      part?: string;
      offset?: number;
    };

export function errorResponse(id: number, error: unknown): Response {
  return {
    id,
    ok: false,
    error: error instanceof Error ? error.message : String(error),
    ...(error instanceof Error &&
    error.name === "DocumentError" &&
    "code" in error &&
    typeof error.code === "string" &&
    "part" in error &&
    typeof error.part === "string" &&
    "offset" in error &&
    typeof error.offset === "number"
      ? { code: error.code, part: error.part, offset: error.offset }
      : {}),
  };
}
