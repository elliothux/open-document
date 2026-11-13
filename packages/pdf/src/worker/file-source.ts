import {
  blobRangeSource,
  type RangeSource,
} from "@open-document/wasm/range-source";
import { DocumentError } from "@open-document/wasm/abi/session";

const blockBytes = 64 * 1024;
const cacheBlocks = 64;

/** Coalesce nearby reads while retaining at most 4 MiB of independent blocks. */
export function pdfFileSource(file: Blob): RangeSource {
  const source = blobRangeSource(file);
  const cache = new Map<number, Uint8Array>();
  async function block(offset: number): Promise<Uint8Array> {
    const cached = cache.get(offset);
    if (cached) {
      cache.delete(offset);
      cache.set(offset, cached);
      return cached;
    }
    const length = Math.min(blockBytes, source.size - offset);
    const bytes = await source.read(offset, length);
    if (bytes.length !== length)
      throw new DocumentError(
        "truncated-source",
        "Incomplete source block",
        "",
        offset,
      );
    if (cache.size >= cacheBlocks) {
      const oldest = cache.keys().next();
      if (!oldest.done) cache.delete(oldest.value);
    }
    cache.set(offset, bytes);
    return bytes;
  }
  return {
    size: source.size,
    async read(offset, length) {
      if (length > blockBytes) return source.read(offset, length);
      const start = offset - (offset % blockBytes);
      const first = await block(start);
      const local = offset - start;
      const left = first.subarray(local, local + length);
      if (left.length === length) return left;
      const right = await block(start + blockBytes);
      const bytes = new Uint8Array(length);
      bytes.set(left);
      bytes.set(right.subarray(0, length - left.length), left.length);
      return bytes;
    },
  };
}
