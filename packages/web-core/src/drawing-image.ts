import type { DrawCommand } from "@open-document/wasm/abi/drawing";
import { drawPatternImage } from "./drawing-tile.js";

export function imageSmoothing(
  context: CanvasRenderingContext2D,
  bitmap: CanvasImageSource,
  width: number,
  height: number,
  interpolate: boolean | null,
  preservePixels: boolean,
): void {
  if (
    interpolate != null ||
    !preservePixels ||
    !(bitmap instanceof ImageBitmap)
  ) {
    context.imageSmoothingEnabled = interpolate ?? true;
    return;
  }
  const m = context.getTransform();
  // Native noninterpolated images keep source pixels when both axes enlarge.
  context.imageSmoothingEnabled = !(
    ((m.b === 0 && m.c === 0) || (m.a === 0 && m.d === 0)) &&
    Math.hypot(m.a, m.b) * width >= bitmap.width &&
    Math.hypot(m.c, m.d) * height >= bitmap.height
  );
}

function drawColorImage(
  context: CanvasRenderingContext2D,
  bitmap: CanvasImageSource,
  image: Extract<DrawCommand, { op: "image" }>["image"],
  createTarget: (width: number, height: number) => CanvasRenderingContext2D,
  sourceColor?: ImageBitmap,
): boolean {
  if (
    !sourceColor ||
    !(bitmap instanceof ImageBitmap) ||
    image.interpolate !== null ||
    !context.imageSmoothingEnabled
  )
    return false;
  const m = context.getTransform();
  // shortcut: actual source crops, rotation and shear keep Canvas sampling; extend on a native failure.
  if (m.b === 0 && m.c === 0 && m.a > 0 && m.d > 0) {
    if (
      sourceColor.width !== bitmap.width ||
      sourceColor.height !== bitmap.height
    )
      throw new Error("Image color plane dimensions differ");
    const x = m.a * image.x + m.e,
      y = m.d * image.y + m.f,
      width = m.a * image.width,
      height = m.d * image.height,
      left = Math.max(0, Math.floor(x)),
      top = Math.max(0, Math.floor(y)),
      right = Math.min(context.canvas.width, Math.ceil(x + width)),
      bottom = Math.min(context.canvas.height, Math.ceil(y + height));
    if (right <= left || bottom <= top) return true;
    const target = createTarget(right - left, bottom - top);
    target.globalAlpha = 1;
    target.globalCompositeOperation = "source-over";
    target.imageSmoothingEnabled = true;
    target.imageSmoothingQuality = context.imageSmoothingQuality;
    target.drawImage(sourceColor, x - left, y - top, width, height);
    // Coverage belongs to the mask; RGB samples carry no alpha of their own.
    const colors = target.getImageData(
      0,
      0,
      target.canvas.width,
      target.canvas.height,
    );
    for (let at = 3; at < colors.data.length; at += 4) colors.data[at] = 255;
    target.putImageData(colors, 0, 0);
    target.globalCompositeOperation = "destination-in";
    target.drawImage(bitmap, x - left, y - top, width, height);
    const masked = target.getImageData(
      0,
      0,
      target.canvas.width,
      target.canvas.height,
    );
    const opacity = context.globalAlpha;
    for (let at = 3; at < masked.data.length; at += 4)
      masked.data[at] = Math.round(masked.data[at]! * opacity);
    target.putImageData(masked, 0, 0);
    context.save();
    try {
      context.resetTransform();
      context.globalAlpha = 1;
      context.imageSmoothingEnabled = false;
      context.drawImage(target.canvas, left, top);
    } finally {
      context.restore();
    }
    return true;
  }
  return false;
}

/** Downscaled images average complete source blocks before clipping. */
// shortcut: mixed-axis reductions and rotations keep Canvas sampling; extend on a failing native case.
function drawReducedImage(
  context: CanvasRenderingContext2D,
  bitmap: CanvasImageSource,
  image: Extract<DrawCommand, { op: "image" }>["image"],
  createTarget: (width: number, height: number) => CanvasRenderingContext2D,
  sourcePixels?: Uint8Array,
): boolean {
  if (
    image.interpolate !== false ||
    !sourcePixels ||
    !(bitmap instanceof ImageBitmap)
  )
    return false;
  const m = context.getTransform();
  if (
    m.b === 0 &&
    m.c === 0 &&
    m.a > 0 &&
    m.d > 0 &&
    m.a * image.width < bitmap.width &&
    m.d * image.height < bitmap.height
  ) {
    const left = Math.floor(m.a * image.x + m.e),
      top = Math.floor(m.d * image.y + m.f),
      width = Math.floor(m.a * (image.x + image.width) + m.e) + 1 - left,
      height = Math.floor(m.d * (image.y + image.height) + m.f) + 1 - top;
    if (
      [left, top, width, height].every(Number.isSafeInteger) &&
      width > 0 &&
      height > 0 &&
      width <= bitmap.width &&
      height <= bitmap.height
    ) {
      if (sourcePixels.length !== bitmap.width * bitmap.height * 4)
        throw new Error("Invalid source image pixels");
      const target = createTarget(width, height);
      target.globalAlpha = 1;
      target.globalCompositeOperation = "source-over";
      const pixels = new ImageData(width, height);
      for (let y = 0; y < height; y++) {
        const firstY = Math.floor((y * bitmap.height) / height),
          lastY = Math.floor(((y + 1) * bitmap.height) / height);
        for (let x = 0; x < width; x++) {
          const firstX = Math.floor((x * bitmap.width) / width),
            lastX = Math.floor(((x + 1) * bitmap.width) / width);
          let red = 0,
            green = 0,
            blue = 0,
            alpha = 0;
          for (let py = firstY; py < lastY; py++)
            for (let px = firstX; px < lastX; px++) {
              const at = (py * bitmap.width + px) * 4,
                a = sourcePixels[at + 3]!;
              red += sourcePixels[at]!;
              green += sourcePixels[at + 1]!;
              blue += sourcePixels[at + 2]!;
              alpha += a;
            }
          const at = (y * width + x) * 4;
          if (alpha) {
            const count = (lastX - firstX) * (lastY - firstY);
            pixels.data[at] = Math.floor(red / count);
            pixels.data[at + 1] = Math.floor(green / count);
            pixels.data[at + 2] = Math.floor(blue / count);
            pixels.data[at + 3] = Math.floor(alpha / count);
          }
        }
      }
      target.canvas.width = width;
      target.canvas.height = height;
      target.putImageData(pixels, 0, 0);
      context.save();
      try {
        context.resetTransform();
        context.imageSmoothingEnabled = false;
        context.drawImage(target.canvas, left, top);
      } finally {
        context.restore();
      }
      return true;
    }
  }
  return false;
}

export function drawImage(
  context: CanvasRenderingContext2D,
  bitmap: CanvasImageSource,
  image: Extract<DrawCommand, { op: "image" }>["image"],
  nativePatternCell: boolean,
  createTarget: (width: number, height: number) => CanvasRenderingContext2D,
  sourcePixels?: Uint8Array,
  sourceColor?: ImageBitmap,
): void {
  if (drawColorImage(context, bitmap, image, createTarget, sourceColor)) return;
  if (drawReducedImage(context, bitmap, image, createTarget, sourcePixels))
    return;
  if (nativePatternCell && drawPatternImage(context, bitmap, image)) return;
  context.drawImage(bitmap, image.x, image.y, image.width, image.height);
}

/** A source crop avoids applying clip-edge coverage twice to the bitmap boundary. */
export function drawCroppedImage(
  context: CanvasRenderingContext2D,
  bitmap: ImageBitmap,
  image: Extract<DrawCommand, { op: "image" }>["image"],
  visible: Extract<DrawCommand, { op: "clipRect" }>["rect"],
  createTarget: (width: number, height: number) => CanvasRenderingContext2D,
  sourcePixels?: Uint8Array,
  sourceColor?: ImageBitmap,
): void {
  const { x: left, y: top, width, height } = visible;
  if (width <= 0 || height <= 0) return;
  if (sourcePixels && image.interpolate === false) {
    context.save();
    try {
      context.beginPath();
      context.rect(left, top, width, height);
      context.clip();
      if (drawReducedImage(context, bitmap, image, createTarget, sourcePixels))
        return;
    } finally {
      context.restore();
    }
  }
  if (
    sourceColor &&
    left === image.x &&
    top === image.y &&
    width === image.width &&
    height === image.height &&
    drawColorImage(context, bitmap, image, createTarget, sourceColor)
  ) {
    return;
  }
  context.drawImage(
    bitmap,
    ((left - image.x) * bitmap.width) / image.width,
    ((top - image.y) * bitmap.height) / image.height,
    (width * bitmap.width) / image.width,
    (height * bitmap.height) / image.height,
    left,
    top,
    width,
    height,
  );
}
