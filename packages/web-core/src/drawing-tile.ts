import type { DrawCommand } from "@open-document/wasm/abi/drawing";
import { tileReplayWork } from "@open-document/wasm/engine-source";

function resampleBitmapCell(
  source: Uint8ClampedArray,
  width: number,
  height: number,
): ImageData {
  const result = new ImageData(width, height);
  // The PDF image covers the final device coordinate, then the tile clips it.
  const stepX = 8 / (width + 1),
    stepY = 8 / (height + 1);
  for (let y = 0, sy = 0; y < height; y++, sy += stepY) {
    // The inclusive PDF image row wraps to the start of the repeated tile.
    const sampleY = y === 0 ? 7 : sy;
    const top = Math.floor(sampleY),
      bottom = Math.min(7, top + 1),
      fy = sampleY - top;
    for (let x = 0, sx = 0; x < width; x++, sx += stepX) {
      const left = Math.floor(sx),
        right = Math.min(7, left + 1),
        fx = sx - left;
      const out = (y * width + x) * 4;
      for (let channel = 0; channel < 3; channel++) {
        const a = Math.floor(
          source[(top * 8 + left) * 4 + channel]! * (1 - fx) +
            source[(top * 8 + right) * 4 + channel]! * fx,
        );
        const b = Math.floor(
          source[(bottom * 8 + left) * 4 + channel]! * (1 - fx) +
            source[(bottom * 8 + right) * 4 + channel]! * fx,
        );
        result.data[out + channel] = Math.floor(a * (1 - fy) + b * fy);
      }
      result.data[out + 3] = 255;
    }
  }
  return result;
}

export function drawBitmapPattern(
  context: CanvasRenderingContext2D,
  command: Extract<DrawCommand, { op: "patternRect" }>,
  coverage: boolean,
  createTarget: (width: number, height: number) => CanvasRenderingContext2D,
): void {
  const colors = [command.zero, command.one].map((color) => [
    Number.parseInt(color.slice(0, 2), 16),
    Number.parseInt(color.slice(2, 4), 16),
    Number.parseInt(color.slice(4, 6), 16),
    255,
  ]);
  const pixels = new Uint8ClampedArray(256);
  for (let y = 0; y < 8; y++)
    for (let x = 0; x < 8; x++)
      pixels.set(colors[(command.mask[y]! >> (7 - x)) & 1]!, (y * 8 + x) * 4);
  const m = context.getTransform();
  const rect = command.rect;
  const axisAligned = m.b === 0 && m.c === 0;
  // Office chart hatches keep their bitmap pixels and start at the paint bounds.
  const screenTile =
    !coverage && command.screenDevice && axisAligned && m.a > 0 && m.d > 0;
  const width = m.a * command.period,
    height = m.d * command.period;
  // shortcut: fractional source pixels use the native grid for integer-sized axis-aligned tiles; retain existing sampling for other transforms.
  const deviceTile =
    coverage &&
    axisAligned &&
    [width, height].every(
      (size) => Number.isInteger(size) && size >= 8 && size < 31,
    ) &&
    (width % 8 !== 0 || height % 8 !== 0);
  const image = deviceTile
    ? resampleBitmapCell(pixels, width, height)
    : new ImageData(pixels, 8, 8);
  const target = createTarget(image.width, image.height);
  target.putImageData(image, 0, 0);
  const pattern = context.createPattern(target.canvas, "repeat");
  if (!pattern) throw new Error("Bitmap pattern is unavailable");
  pattern.setTransform(
    deviceTile
      ? new DOMMatrix([
          1 / m.a,
          0,
          0,
          1 / m.d,
          (Math.floor(m.e) - m.e) / m.a,
          (Math.floor(m.f) - m.f) / m.d,
        ])
      : screenTile
        ? new DOMMatrix([1 / m.a, 0, 0, 1 / m.d, rect.x, rect.y])
        : new DOMMatrix().scale(command.period / 8),
  );
  context.save();
  try {
    context.imageSmoothingEnabled =
      !deviceTile &&
      (!coverage ||
        command.period * Math.min(Math.hypot(m.a, m.b), Math.hypot(m.c, m.d)) <
          8);
    context.fillStyle = pattern;
    context.fillRect(rect.x, rect.y, rect.width, rect.height);
  } finally {
    context.restore();
  }
}

export function drawTile(
  context: CanvasRenderingContext2D,
  command: Extract<DrawCommand, { op: "tile" }>,
  createTarget: (
    width: number,
    height: number,
    matrix: DOMMatrix,
  ) => CanvasRenderingContext2D,
  draw: (
    target: CanvasRenderingContext2D,
    commands: DrawCommand[],
    nativeCell: boolean,
  ) => void,
): void {
  const parent = context.getTransform(),
    m = command.matrix;
  const device = parent.multiply(new DOMMatrix([m.a, m.b, m.c, m.d, m.e, m.f]));
  const { width, height, columns, rows, resolution } = command;
  const determinant = device.a * device.d - device.b * device.c;
  if (!Number.isFinite(determinant) || !determinant) return;
  const kx = Math.abs(device.b) > Math.abs(device.a) ? -device.b : device.a;
  const ky =
    Math.abs(device.b) > Math.abs(device.a)
      ? device.c - (device.a * device.d) / device.b
      : device.d - (device.b * device.c) / device.a;
  const resultWidth = Math.ceil(Math.abs(kx * width * columns)),
    resultHeight = Math.ceil(Math.abs(ky * height * rows));
  const sampleX = resolution.x * Math.hypot(parent.a, parent.b),
    sampleY = resolution.y * Math.hypot(parent.c, parent.d);
  const nominalWidth = Math.max(1, Math.ceil(sampleX * width)),
    nominalHeight = Math.max(1, Math.ceil(sampleY * height));
  const sx = (sampleX * resultWidth) / (nominalWidth * columns),
    sy = (sampleY * resultHeight) / (nominalHeight * rows);
  const tileWidth = Math.max(1, Math.ceil(sx * width)),
    tileHeight = Math.max(1, Math.ceil(sy * height));
  const repeatX = Math.max(columns, Math.ceil(resultWidth / tileWidth)),
    repeatY = Math.max(rows, Math.ceil(resultHeight / tileHeight));
  if (!Number.isSafeInteger(repeatX * repeatY) || repeatX * repeatY > 4096)
    throw new Error("Drawing tile repetitions exceed budget");
  const target = createTarget(
    tileWidth,
    tileHeight,
    new DOMMatrix([sx, 0, 0, sy, 0, 0]),
  );
  // Keep the existing surface budget check before replaying native cells.
  // shortcut: larger replay programs retain the cache; extend with a measured native case.
  if (
    command.replay &&
    repeatX * repeatY <= 4 &&
    columns * rows * command.commands.length <= tileReplayWork
  ) {
    for (let row = 0; row < rows; row++)
      for (let column = 0; column < columns; column++) {
        context.save();
        try {
          context.transform(
            m.a,
            m.b,
            m.c,
            m.d,
            m.e + m.a * width * column + m.c * height * row,
            m.f + m.b * width * column + m.d * height * row,
          );
          draw(context, command.commands, true);
        } finally {
          context.restore();
        }
      }
    return;
  }
  draw(target, command.commands, false);
  const pattern = context.createPattern(target.canvas, "repeat");
  if (!pattern) throw new Error("Tile pattern is unavailable");
  const scaleX = (tileWidth * repeatX) / (Math.abs(kx * width * repeatX) + 1);
  const scaleY = (tileHeight * repeatY) / (Math.abs(ky * height * repeatY) + 1);
  context.save();
  try {
    context.transform(
      (m.a * scaleX * width) / tileWidth,
      (m.b * scaleX * width) / tileWidth,
      (m.c * scaleY * height) / tileHeight,
      (m.d * scaleY * height) / tileHeight,
      m.e,
      m.f,
    );
    context.globalAlpha = 1;
    context.imageSmoothingEnabled = false;
    context.fillStyle = pattern;
    context.fillRect(0, 0, tileWidth * repeatX, tileHeight * repeatY);
  } finally {
    context.restore();
  }
}

/** Direct native pattern cells use complete device rows and columns for axis images. */
export function drawPatternImage(
  context: CanvasRenderingContext2D,
  bitmap: CanvasImageSource,
  image: Extract<DrawCommand, { op: "image" }>["image"],
): boolean {
  const m = context.getTransform();
  if (m.b !== 0 || m.c !== 0 || m.a <= 0 || m.d <= 0) return false;
  const left = Math.floor(m.a * image.x + m.e),
    top = Math.floor(m.d * image.y + m.f),
    right = Math.floor(m.a * (image.x + image.width) + m.e) + 1,
    bottom = Math.floor(m.d * (image.y + image.height) + m.f) + 1;
  if (
    ![left, top, right, bottom].every(Number.isSafeInteger) ||
    right <= left ||
    bottom <= top
  )
    return false;
  context.save();
  try {
    context.resetTransform();
    context.drawImage(bitmap, left, top, right - left, bottom - top);
  } finally {
    context.restore();
  }
  return true;
}
