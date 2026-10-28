/** Read supported raster headers before calling the browser decoder. */
export function imageDimensions(bytes: Uint8Array): {
  width: number;
  height: number;
} {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let width = 0;
  let height = 0;
  if (
    bytes.length >= 33 &&
    view.getUint32(0) === 0x89504e47 &&
    view.getUint32(4) === 0x0d0a1a0a &&
    view.getUint32(8) === 13 &&
    view.getUint32(12) === 0x49484452
  ) {
    width = view.getUint32(16);
    height = view.getUint32(20);
  } else if (
    bytes.length >= 13 &&
    view.getUint32(0) === 0x47494638 &&
    (view.getUint16(4) === 0x3761 || view.getUint16(4) === 0x3961)
  ) {
    width = view.getUint16(6, true);
    height = view.getUint16(8, true);
  } else if (bytes.length >= 4 && view.getUint16(0) === 0xffd8) {
    let offset = 2;
    while (offset + 4 <= bytes.length) {
      if (bytes[offset++] !== 0xff) break;
      while (bytes[offset] === 0xff) offset++;
      const marker = bytes[offset++];
      if (marker === undefined || marker === 0xda || marker === 0xd9) break;
      if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
      if (offset + 2 > bytes.length) break;
      const length = view.getUint16(offset);
      if (length < 2 || offset + length > bytes.length) break;
      if (
        marker >= 0xc0 &&
        marker <= 0xcf &&
        marker !== 0xc4 &&
        marker !== 0xc8 &&
        marker !== 0xcc &&
        length >= 8
      ) {
        height = view.getUint16(offset + 3);
        width = view.getUint16(offset + 5);
        break;
      }
      offset += length;
    }
  }
  if (!width || !height)
    throw new Error("Unsupported or malformed PNG, JPEG or GIF image header");
  if (width > 4096 || height > 4096 || width * height > 4194304)
    throw new Error("Decoded image exceeds budget");
  return { width, height };
}

/** Decode only validated local raster bytes; retain alpha for the shared core. */
export async function decodeImage(
  bytes: Uint8Array,
  signal?: AbortSignal,
): Promise<{ bitmap: ImageBitmap; rgba: Uint8Array }> {
  signal?.throwIfAborted();
  const declared = imageDimensions(bytes);
  const bitmap = await createImageBitmap(
    new Blob([new Uint8Array(bytes).buffer]),
    { imageOrientation: "none" },
  );
  const canvas = document.createElement("canvas");
  try {
    signal?.throwIfAborted();
    if (bitmap.width !== declared.width || bitmap.height !== declared.height)
      throw new Error("Decoded image dimensions differ from its header");
    canvas.width = bitmap.width;
    canvas.height = bitmap.height;
    const context = canvas.getContext("2d");
    if (!context) throw new Error("Canvas is unavailable");
    context.drawImage(bitmap, 0, 0);
    return {
      bitmap,
      rgba: new Uint8Array(
        context.getImageData(0, 0, bitmap.width, bitmap.height).data,
      ),
    };
  } catch (error) {
    bitmap.close();
    throw error;
  } finally {
    canvas.width = canvas.height = 0;
  }
}
