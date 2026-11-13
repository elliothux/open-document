import type { Budget } from "@open-document/wasm/abi/session";
import {
  blobRangeSource,
  readSourceRanges,
} from "@open-document/wasm/range-source";
import type { PptxSession } from "../core/pptx.js";

export type PptxFileCommand =
  | { operation: "fileBudgetPptx" }
  | {
      operation: "openPptxFile";
      file: Blob;
      budget?: Budget;
      dateTime?: string;
    };

/** Fill each exact range requested by the engine before resuming it. */
export async function readPptxFile<T>(
  session: PptxSession,
  file: Blob,
  run: () => T,
): Promise<T> {
  try {
    return await readSourceRanges(blobRangeSource(file), run, (bytes) =>
      session.supplyRange(bytes),
    );
  } catch (error) {
    session.cancelRange();
    throw error;
  }
}
