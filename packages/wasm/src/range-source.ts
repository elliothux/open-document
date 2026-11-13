import { DocumentError } from "./abi/session.js";

/** Keep the bytes and length stable for the lifetime of a reader. */
export interface RangeSource {
  readonly size: number;
  read(offset: number, length: number): Uint8Array | Promise<Uint8Array>;
}

export function blobRangeSource(file: Blob): RangeSource {
  return {
    size: file.size,
    async read(offset, length) {
      return new Uint8Array(
        await file.slice(offset, offset + length).arrayBuffer(),
      );
    },
  };
}

/** Supply exact ranges requested by Wasm before retrying the operation. */
export async function readSourceRanges<T>(
  source: RangeSource,
  run: () => T,
  supply: (bytes: Uint8Array) => void,
): Promise<T> {
  for (;;) {
    try {
      return run();
    } catch (error) {
      if (
        !(error instanceof DocumentError) ||
        error.code !== "source-range-required"
      )
        throw error;
      const { offset } = error;
      const length = Number(error.part);
      if (
        !Number.isSafeInteger(offset) ||
        !Number.isSafeInteger(length) ||
        offset < 0 ||
        length <= 0 ||
        length > 64 * 1024 * 1024 ||
        length > source.size - offset
      )
        throw new DocumentError(
          "invalid-source",
          "Invalid source range",
          "",
          offset,
        );
      const bytes = await source.read(offset, length);
      if (!(bytes instanceof Uint8Array) || bytes.length !== length)
        throw new DocumentError(
          "truncated-source",
          "Incomplete source range",
          "",
          offset,
        );
      supply(bytes);
    }
  }
}
