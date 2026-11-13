import type { RasterHeader } from "@open-document/wasm/abi/drawing";
import { imageBytes } from "@open-document/wasm/engine-source";
import { decodeBitmap } from "@open-document/web-core/image";

// Keep the sampling grid aligned with the PDF core's Flate mask decoder.
function sample(position: number, sourceSize: number, size: number) {
  const center = Math.max(0, ((position + 0.5) * sourceSize) / size - 0.5);
  return {
    first: Math.floor(center),
    second: Math.min(Math.ceil(center), sourceSize - 1),
  };
}

export async function sampleJpeg(
  bytes: Uint8Array,
  header: RasterHeader,
  width: number,
  height: number,
): Promise<Uint8Array> {
  if ("error" in header) throw new Error(header.error);
  if (
    !Number.isSafeInteger(width) ||
    !Number.isSafeInteger(height) ||
    width < 1 ||
    height < 1 ||
    width > header.width ||
    height > header.height ||
    width * height * 12 > imageBytes
  )
    throw new Error("Invalid PDF JPEG sample dimensions");
  const bitmap = await decodeBitmap(bytes, header);
  const canvas = document.createElement("canvas");
  try {
    const stripHeight = 32;
    const stride = bitmap.width * 4;
    canvas.width = bitmap.width;
    canvas.height = stripHeight;
    const context = canvas.getContext("2d", { willReadFrequently: true });
    if (!context) throw new Error("Canvas is unavailable");
    let stripTop = -stripHeight;
    let strip = new Uint8ClampedArray(0);
    const readRow = (row: number) => {
      if (row < stripTop || row >= stripTop + stripHeight) {
        stripTop = Math.floor(row / stripHeight) * stripHeight;
        const rows = Math.min(stripHeight, bitmap.height - stripTop);
        context.drawImage(
          bitmap,
          0,
          stripTop,
          bitmap.width,
          rows,
          0,
          0,
          bitmap.width,
          rows,
        );
        strip = context.getImageData(0, 0, bitmap.width, rows).data;
      }
      const at = (row - stripTop) * stride;
      return strip.subarray(at, at + stride);
    };
    const columns = Array.from({ length: width }, (_, x) =>
      sample(x, bitmap.width, width),
    );
    const output = new Uint8Array(width * height * 12);
    let at = 0;
    for (let y = 0; y < height; y++) {
      const { first, second } = sample(y, bitmap.height, height);
      const top = readRow(first);
      const bottom = first === second ? top : readRow(second);
      for (const column of columns) {
        const left = column.first * 4;
        const right = column.second * 4;
        for (let channel = 0; channel < 3; channel++) {
          output[at + channel] = top[left + channel]!;
          output[at + 3 + channel] = top[right + channel]!;
          output[at + 6 + channel] = bottom[left + channel]!;
          output[at + 9 + channel] = bottom[right + channel]!;
        }
        at += 12;
      }
    }
    return output;
  } finally {
    bitmap.close();
    canvas.width = canvas.height = 0;
  }
}
