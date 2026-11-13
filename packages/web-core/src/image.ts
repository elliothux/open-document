import type {
  ImagePreparation,
  RasterHeader,
} from "@open-document/wasm/abi/drawing";
import { imageBytes, imageDimension } from "@open-document/wasm/engine-source";

/** Decode only raster bytes whose dimensions were validated by the core. */
export async function decodeImage(
  bytes: Uint8Array | Blob,
  header: RasterHeader,
  signal?: AbortSignal,
  size?: { width: number; height: number },
): Promise<{ bitmap: ImageBitmap; rgba: Uint8Array }> {
  const bitmap = await decodeBitmap(bytes, header, signal, size);
  const canvas = document.createElement("canvas");
  try {
    signal?.throwIfAborted();
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

export async function decodeBitmap(
  bytes: Uint8Array | Blob,
  header: RasterHeader,
  signal?: AbortSignal,
  size?: { width: number; height: number },
): Promise<ImageBitmap> {
  signal?.throwIfAborted();
  if ("error" in header) throw new Error(header.error);
  if (
    size &&
    (!Number.isSafeInteger(size.width) ||
      !Number.isSafeInteger(size.height) ||
      size.width < 1 ||
      size.height < 1 ||
      size.width > Math.min(header.width, imageDimension) ||
      size.height > Math.min(header.height, imageDimension) ||
      size.width * size.height * 4 > imageBytes)
  )
    throw new Error("Invalid image preview dimensions");
  const bitmap = await createImageBitmap(
    bytes instanceof Blob ? bytes : new Blob([new Uint8Array(bytes).buffer]),
    {
      imageOrientation: header.allowTranspose ? "from-image" : "none",
      ...(size && {
        resizeWidth: size.width,
        resizeHeight: size.height,
        resizeQuality: "high",
      }),
    },
  );
  try {
    signal?.throwIfAborted();
    const expected = size ?? header;
    const matches =
      bitmap.width === expected.width && bitmap.height === expected.height;
    const transposed =
      !size &&
      header.allowTranspose &&
      bitmap.width === header.height &&
      bitmap.height === header.width;
    if (!matches && !transposed)
      throw new Error("Decoded image dimensions differ from its header");
    return bitmap;
  } catch (error) {
    bitmap.close();
    throw error;
  }
}

/** Check a raster that still needs host decoding without reading back pixels. */
export async function verifyEncodedImage(
  bytes: Uint8Array,
  header: RasterHeader,
  signal?: AbortSignal,
): Promise<void> {
  if ("coreVerified" in header && header.coreVerified) {
    signal?.throwIfAborted();
    return;
  }
  const bitmap = await decodeBitmap(bytes, header, signal);
  bitmap.close();
}

export function imageBitmapFromPixels(
  width: number,
  height: number,
  bytes: Uint8Array,
): Promise<ImageBitmap> {
  return createImageBitmap(
    new ImageData(new Uint8ClampedArray(bytes), width, height),
  );
}

export async function materializeImage(
  image: ImagePreparation,
  signal?: AbortSignal,
): Promise<{ bitmap: ImageBitmap; rgba: Uint8Array }> {
  signal?.throwIfAborted();
  if (image.kind === "encoded") {
    return decodeImage(image.bytes, image.header, signal);
  }
  return {
    bitmap: await imageBitmapFromPixels(image.width, image.height, image.bytes),
    rgba: image.bytes,
  };
}

/** Office PDF colors use white at zero alpha and an independently sampled mask. */
export async function imageColorPlane(
  width: number,
  height: number,
  rgba: Uint8Array,
): Promise<ImageBitmap | undefined> {
  if (
    !Number.isSafeInteger(width) ||
    !Number.isSafeInteger(height) ||
    width < 1 ||
    height < 1 ||
    width > imageDimension ||
    height > imageDimension ||
    rgba.length > imageBytes ||
    rgba.length !== width * height * 4
  )
    throw new Error("Invalid image color plane dimensions or pixels");
  if (rgba.every((byte, at) => at % 4 !== 3 || byte === 255)) return;
  const colors = new Uint8ClampedArray(rgba);
  for (let at = 0; at < colors.length; at += 4) {
    if (colors[at + 3] === 0)
      colors[at] = colors[at + 1] = colors[at + 2] = 255;
    colors[at + 3] = 255;
  }
  return createImageBitmap(new ImageData(colors, width, height));
}
