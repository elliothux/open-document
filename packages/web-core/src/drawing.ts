import type {
  DrawingBatch,
  DrawGlyph,
  DrawStyle,
  DrawCommand,
  DrawMatrix,
  PathSegment,
} from "@open-document/wasm/abi/drawing";
import type { ShapeBatch } from "@open-document/wasm/abi/shape";
import {
  fillStrokeDiamond,
  clipDeviceRectangle,
  fractionalClipBounds,
  pdfClipPath,
  pixelRectangleFill,
  pixelRectangleStroke,
  type ClipBounds,
} from "./pdf-pixels.js";
import {
  compileGlyphPath,
  drawGlyphs,
  type GlyphPath,
} from "./drawing-glyphs.js";
import { drawBitmapPattern, drawTile } from "./drawing-tile.js";
import {
  drawImage,
  drawCroppedImage,
  imageSmoothing,
} from "./drawing-image.js";
import { pdfHairline, pdfPathStroke, pdfStroke } from "./pdf-stroke.js";
import { drawingPath } from "./drawing-path.js";
export type CanvasRasterMode = "integer" | "fractional" | "pdf";

/** One renderer per core session. Platform resources never cross sessions. */
export class CanvasRenderer {
  private readonly paths = new Map<string, GlyphPath>();
  private closed = false;
  private basePixels = 0;
  private imageWork = 0;
  // Preserve image sampling capacity when glyph refinement reaches its limit.
  private glyphWork = 0;
  private glyphRasterMode: CanvasRasterMode;

  constructor(
    private readonly rasterMode: CanvasRasterMode = "integer",
    private readonly imagePixels: ReadonlyMap<string, Uint8Array> = new Map(),
    private readonly imageColors: ReadonlyMap<string, ImageBitmap> = new Map(),
  ) {
    this.glyphRasterMode = rasterMode;
  }

  setGlyphRasterMode(mode: CanvasRasterMode): boolean {
    if (this.closed) throw new Error("Renderer is disposed");
    if (!["integer", "fractional", "pdf"].includes(mode))
      throw new Error("Invalid glyph raster mode");
    const changed = this.glyphRasterMode !== mode;
    this.glyphRasterMode = mode;
    return changed;
  }

  drawRegion(
    context: CanvasRenderingContext2D,
    batch: DrawingBatch,
    index: number,
    images: ReadonlyMap<string, ImageBitmap> = new Map(),
    liveImages: ReadonlyMap<DrawCommand, CanvasImageSource> = new Map(),
  ): void {
    if (this.closed) throw new Error("Renderer is disposed");
    const region = batch.regions[index];
    if (!region) throw new Error("Unknown drawing region");
    const retained = new Set(batch.outlines.map((outline) => outline.key));
    for (const key of this.paths.keys())
      if (!retained.has(key)) this.paths.delete(key);
    this.prepare(batch.outlines);
    this.usedLayers = 0;
    this.basePixels = context.canvas.width * context.canvas.height;
    this.imageWork = 0;
    this.glyphWork = 0;
    const m = context.getTransform(),
      first = region.commands[0];
    const commands =
      first?.op === "clipRect" &&
      first.rect.x === 0 &&
      first.rect.y === 0 &&
      first.rect.width === region.width &&
      first.rect.height === region.height &&
      m.b === 0 &&
      m.c === 0 &&
      m.e === 0 &&
      m.f === 0 &&
      m.a > 0 &&
      m.d > 0 &&
      context.canvas.width === Math.ceil(region.width * m.a) &&
      context.canvas.height === Math.ceil(region.height * m.d)
        ? // Align the page clip to its backing pixels while retaining its save/restore scope.
          [
            {
              ...first,
              rect: {
                ...first.rect,
                width: context.canvas.width / m.a,
                height: context.canvas.height / m.d,
              },
            },
            ...region.commands.slice(1),
          ]
        : region.commands;
    for (const canvas of this.layers)
      if (
        canvas.width !== context.canvas.width ||
        canvas.height !== context.canvas.height
      ) {
        canvas.width = 0;
        canvas.height = 0;
      }
    try {
      this.drawCommands(context, commands, images, 0, liveImages);
    } finally {
      for (let i = this.usedLayers; i < this.layers.length; i++) {
        this.layers[i]!.width = 0;
        this.layers[i]!.height = 0;
      }
    }
  }

  private readonly layers: HTMLCanvasElement[] = [];
  private usedLayers = 0;
  private drawCommands(
    context: CanvasRenderingContext2D,
    commands: DrawCommand[],
    images: ReadonlyMap<string, ImageBitmap>,
    depth: number,
    liveImages: ReadonlyMap<DrawCommand, CanvasImageSource>,
    nativePatternCell = false,
  ): void {
    let clips = 0;
    let clipBounds: ClipBounds | undefined;
    let paintClipped = false;
    let pixelCenters = false;
    let glyphRasterMode = this.glyphRasterMode;
    let sourceMatrix: DrawMatrix = context.getTransform();
    let style: DrawStyle = {
      fillAlpha: 1,
      strokeAlpha: 1,
      evenOdd: false,
      cap: 0,
      join: 0,
      miter: 10,
      dash: [],
      dashOffset: 0,
      blend: "normal",
    };
    const styles: {
      style: DrawStyle;
      pixelCenters: boolean;
      glyphRasterMode: CanvasRasterMode;
      sourceMatrix: DrawMatrix;
      clipBounds: ClipBounds | undefined;
    }[] = [];
    const saveScope = () => {
      context.save();
      clips++;
      styles.push({
        style,
        pixelCenters,
        glyphRasterMode,
        sourceMatrix,
        clipBounds,
      });
    };
    const clipPath = (path: PathSegment[], evenOdd: boolean) => {
      const bounds =
        this.rasterMode === "pdf"
          ? fractionalClipBounds(context, path)
          : undefined;
      if (bounds) {
        clipBounds = clipBounds
          ? [
              Math.max(clipBounds[0], bounds[0]),
              Math.max(clipBounds[1], bounds[1]),
              Math.min(clipBounds[2], bounds[2]),
              Math.min(clipBounds[3], bounds[3]),
            ]
          : bounds;
      } else context.clip(drawingPath(path), evenOdd ? "evenodd" : "nonzero");
    };
    context.save();
    try {
      this.applyStyle(context, style);
      for (let index = 0; index < commands.length; index++) {
        const command = commands[index]!;
        const next = commands[index + 1];
        const cropped =
          command.op === "clipRect" &&
          next?.op === "image" &&
          commands[index + 2]?.op === "restore" &&
          !liveImages.has(next)
            ? images.get(next.image.key)
            : undefined;
        if (
          clipBounds &&
          command.op !== "style" &&
          command.op !== "transform" &&
          command.op !== "restore" &&
          command.op !== "pixelCenters" &&
          command.op !== "integerScreenGlyphs" &&
          command.op !== "clipPath" &&
          (command.op !== "clipRect" || cropped)
        ) {
          context.save();
          paintClipped = true;
          clipDeviceRectangle(
            context,
            clipBounds,
            command.op === "glyphs" &&
              command.glyphs.every((glyph) => glyph.strokeWidth === 0),
          );
        }
        switch (command.op) {
          case "tile":
            drawTile(
              context,
              command,
              this.rasterMode === "pdf",
              (width, height, matrix) =>
                this.layerContext(context, depth, width, height, matrix),
              (target, commands, nativeCell) =>
                this.drawCommands(
                  target,
                  commands,
                  images,
                  depth + 1,
                  liveImages,
                  nativeCell,
                ),
            );
            break;
          case "layer":
            this.layer(
              context,
              command.commands,
              command.opacity,
              images,
              depth,
              liveImages,
              null,
            );
            break;
          case "mask":
            this.layer(
              context,
              command.commands,
              1,
              images,
              depth,
              liveImages,
              command.mask,
            );
            break;
          case "fillRect": {
            context.globalAlpha = style.fillAlpha;
            const rect = command.rect;
            context.fillStyle = `#${rect.color}`;
            if (
              pixelCenters ||
              this.rasterMode === "fractional" ||
              !pixelRectangleFill(context, rect)
            )
              context.fillRect(rect.x, rect.y, rect.width, rect.height);
            break;
          }
          case "patternRect":
            context.globalAlpha = style.fillAlpha;
            drawBitmapPattern(
              context,
              command,
              this.rasterMode === "pdf",
              (width, height) =>
                this.imageTarget(context, depth, width, height),
            );
            break;
          case "strokeRect": {
            context.globalAlpha = style.strokeAlpha;
            const rect = command.rect;
            context.strokeStyle = `#${command.color}`;
            context.lineWidth = command.lineWidth;
            if (pixelCenters) {
              const m = context.getTransform();
              context.save();
              try {
                context.setTransform(m.a, m.b, m.c, m.d, m.e + 0.5, m.f + 0.5);
                context.strokeRect(rect.x, rect.y, rect.width, rect.height);
              } finally {
                context.restore();
              }
            } else if (
              (command.screenFractional && this.rasterMode !== "pdf") ||
              !pixelRectangleStroke(context, command, this.rasterMode === "pdf")
            )
              context.strokeRect(rect.x, rect.y, rect.width, rect.height);
            break;
          }
          case "gradientRect":
          case "radialGradientRect": {
            const rect = command.rect;
            if (rect.width === 0 || rect.height === 0) break;
            const gradient =
              command.op === "radialGradientRect"
                ? context.createRadialGradient(
                    rect.x + rect.width / 2,
                    rect.y + rect.height / 2,
                    72 / 25.4,
                    rect.x + rect.width / 2,
                    rect.y + rect.height / 2,
                    Math.max(rect.width, rect.height) / 2,
                  )
                : context.createLinearGradient(
                    rect.x,
                    rect.y,
                    rect.x + rect.width,
                    rect.y,
                  );
            for (const [index, stop] of command.stops.entries()) {
              // Match PDF interval extension at duplicate endpoint stops.
              if (
                (stop.position === 0 &&
                  command.stops[index + 1]?.position === 0) ||
                (stop.position === 1 &&
                  command.stops[index - 1]?.position === 1)
              )
                continue;
              gradient.addColorStop(
                stop.position,
                `rgba(${Number.parseInt(stop.color.slice(0, 2), 16)},${Number.parseInt(stop.color.slice(2, 4), 16)},${Number.parseInt(stop.color.slice(4, 6), 16)},${stop.opacity})`,
              );
            }
            context.globalAlpha = style.fillAlpha;
            context.fillStyle = gradient;
            context.fillRect(rect.x, rect.y, rect.width, rect.height);
            break;
          }
          case "glyphs":
            context.globalAlpha = style.fillAlpha;
            context.fillStyle = `#${command.color}`;
            context.save();
            try {
              context.translate(command.x, command.y);
              this.glyphs(
                context,
                command.glyphs,
                pixelCenters ? "fractional" : glyphRasterMode,
                pixelCenters,
                {
                  a: sourceMatrix.a,
                  b: sourceMatrix.b,
                  c: sourceMatrix.c,
                  d: sourceMatrix.d,
                  e:
                    sourceMatrix.a * command.x +
                    sourceMatrix.c * command.y +
                    sourceMatrix.e,
                  f:
                    sourceMatrix.b * command.x +
                    sourceMatrix.d * command.y +
                    sourceMatrix.f,
                },
              );
            } finally {
              context.restore();
            }
            break;
          case "image": {
            context.globalAlpha = style.fillAlpha;
            const image = command.image;
            const bitmap = liveImages.get(command) ?? images.get(image.key);
            if (!bitmap) throw new Error(`Missing image: ${image.key}`);
            imageSmoothing(
              context,
              bitmap,
              image.width,
              image.height,
              image.interpolate,
              this.rasterMode === "fractional",
            );
            drawImage(
              context,
              bitmap,
              image,
              nativePatternCell,
              (width, height) =>
                this.imageTarget(context, depth, width, height),
              this.imagePixels.get(image.key),
              this.imageColors.get(image.key),
            );
            break;
          }
          case "style":
            style = command.style;
            this.applyStyle(context, style);
            break;
          case "pixelCenters":
            pixelCenters = this.rasterMode !== "pdf";
            break;
          case "integerScreenGlyphs":
            if (this.rasterMode !== "pdf") glyphRasterMode = "integer";
            break;
          case "clipPath":
          case "path": {
            if (command.op === "clipPath") {
              saveScope();
              clipPath(
                pdfClipPath(
                  context,
                  command.path,
                  this.rasterMode,
                  commands,
                  index,
                ),
                command.evenOdd,
              );
              break;
            }
            const path = drawingPath(command.path);
            const curves = command.path.some(
              (segment) => segment.op === "cubic",
            );
            if (pixelCenters) {
              const m = context.getTransform();
              context.save();
              // VCL centers antialiased vector paths on device pixels at every zoom.
              context.setTransform(m.a, m.b, m.c, m.d, m.e + 0.5, m.f + 0.5);
            }
            try {
              if (command.fill) {
                context.globalAlpha = style.fillAlpha;
                context.fillStyle = `#${command.fill}`;
                if (
                  style.strokeAlpha === 1 &&
                  fillStrokeDiamond(context, command)
                )
                  break;
                context.fill(path, style.evenOdd ? "evenodd" : "nonzero");
              }
              if (command.stroke) {
                context.globalAlpha = style.strokeAlpha;
                context.strokeStyle = `#${command.stroke}`;
                const m = context.getTransform();
                // shortcut: nonuniform hairlines use the largest scale; use device paths if required.
                context.lineWidth =
                  command.lineWidth ||
                  1 / Math.max(Math.hypot(m.a, m.b), Math.hypot(m.c, m.d));
                if (
                  !(
                    !pixelCenters &&
                    ((command.lineWidth === 0 &&
                      this.rasterMode !== "fractional" &&
                      pdfHairline(context, command.path, m)) ||
                      pixelRectangleStroke(
                        context,
                        command,
                        this.rasterMode === "pdf",
                      ))
                  ) &&
                  !(
                    !pixelCenters &&
                    (this.rasterMode !== "fractional" ||
                      (command.textRule && m.b === 0 && m.c === 0)) &&
                    pdfStroke(context, command)
                  ) &&
                  !(
                    !pixelCenters &&
                    this.rasterMode !== "fractional" &&
                    pdfPathStroke(
                      context,
                      command.path,
                      this.rasterMode === "pdf" ||
                        (Boolean(command.fill) && !curves),
                      Boolean(command.fill),
                      16777216 -
                        this.layers.reduce(
                          (sum, canvas) => sum + canvas.width * canvas.height,
                          this.basePixels,
                        ),
                      command.lineWidth === 0,
                    )
                  )
                )
                  context.stroke(
                    pixelCenters && command.lineWidth === 0
                      ? drawingPath(command.path, m)
                      : path,
                  );
              }
            } finally {
              if (pixelCenters) context.restore();
            }
            break;
          }
          case "transform": {
            const m = command.matrix;
            saveScope();
            sourceMatrix = {
              a: sourceMatrix.a * m.a + sourceMatrix.c * m.b,
              b: sourceMatrix.b * m.a + sourceMatrix.d * m.b,
              c: sourceMatrix.a * m.c + sourceMatrix.c * m.d,
              d: sourceMatrix.b * m.c + sourceMatrix.d * m.d,
              e: sourceMatrix.a * m.e + sourceMatrix.c * m.f + sourceMatrix.e,
              f: sourceMatrix.b * m.e + sourceMatrix.d * m.f + sourceMatrix.f,
            };
            context.transform(m.a, m.b, m.c, m.d, m.e, m.f);
            break;
          }
          case "clipRect": {
            const rect = command.rect;
            if (next?.op === "image" && cropped) {
              const image = next.image;
              context.save();
              try {
                context.globalAlpha = style.fillAlpha;
                imageSmoothing(
                  context,
                  cropped,
                  image.width,
                  image.height,
                  image.interpolate,
                  this.rasterMode === "fractional",
                );
                drawCroppedImage(
                  context,
                  cropped,
                  image,
                  rect,
                  (width, height) =>
                    this.imageTarget(context, depth, width, height),
                  this.imagePixels.get(image.key),
                  this.imageColors.get(image.key),
                );
              } finally {
                context.restore();
              }
              index += 2;
              break;
            }
            saveScope();
            if (this.rasterMode === "pdf")
              clipPath(
                pdfClipPath(
                  context,
                  [
                    { op: "move", x: rect.x, y: rect.y },
                    { op: "line", x: rect.x + rect.width, y: rect.y },
                    {
                      op: "line",
                      x: rect.x + rect.width,
                      y: rect.y + rect.height,
                    },
                    { op: "line", x: rect.x, y: rect.y + rect.height },
                    { op: "close" },
                  ],
                  "pdf",
                  commands,
                  index,
                ),
                false,
              );
            else {
              context.beginPath();
              context.rect(rect.x, rect.y, rect.width, rect.height);
              context.clip();
            }
            break;
          }
          case "restore":
            if (clips === 0) throw new Error("Invalid drawing clip stack");
            context.restore();
            ({
              style,
              pixelCenters,
              glyphRasterMode,
              sourceMatrix,
              clipBounds,
            } = styles.pop()!);
            clips--;
            break;
          default:
            throw new Error("Unknown drawing command");
        }
        if (paintClipped) {
          context.restore();
          paintClipped = false;
        }
      }
      if (clips !== 0) throw new Error("Unclosed drawing clip");
    } finally {
      if (paintClipped) context.restore();
      while (clips-- > 0) context.restore();
      context.restore();
    }
  }

  private layer(
    context: CanvasRenderingContext2D,
    commands: DrawCommand[],
    opacity: number,
    images: ReadonlyMap<string, ImageBitmap>,
    depth: number,
    liveImages: ReadonlyMap<DrawCommand, CanvasImageSource>,
    mask: DrawCommand[] | null,
  ): void {
    const nextDepth = depth + (mask === null ? 1 : 2);
    const target = this.layerContext(context, depth);
    this.drawCommands(target, commands, images, nextDepth, liveImages);
    if (mask !== null) {
      const alpha = this.layerContext(context, depth + 1);
      this.drawCommands(alpha, mask, images, nextDepth, liveImages);
      target.save();
      try {
        target.resetTransform();
        target.globalAlpha = 1;
        target.globalCompositeOperation = "destination-in";
        target.drawImage(alpha.canvas, 0, 0);
      } finally {
        target.restore();
      }
    }
    context.save();
    try {
      context.resetTransform();
      context.globalAlpha = opacity;
      context.drawImage(target.canvas, 0, 0);
    } finally {
      context.restore();
    }
  }

  private imageTarget(
    context: CanvasRenderingContext2D,
    depth: number,
    width: number,
    height: number,
  ): CanvasRenderingContext2D {
    this.imageWork += width * height * 2;
    if (this.imageWork > 67108864)
      throw new Error("Image sampling exceeds pixel work budget");
    return this.layerContext(context, depth, width, height, new DOMMatrix());
  }

  private layerContext(
    context: CanvasRenderingContext2D,
    depth: number,
    width = context.canvas.width,
    height = context.canvas.height,
    matrix = context.getTransform(),
  ): CanvasRenderingContext2D {
    let pixels = this.basePixels + width * height;
    for (let i = 0; i < depth; i++)
      pixels += (this.layers[i]?.width ?? 0) * (this.layers[i]?.height ?? 0);
    if (
      depth >= 4 ||
      !Number.isSafeInteger(width) ||
      !Number.isSafeInteger(height) ||
      width < 1 ||
      height < 1 ||
      pixels > 16777216
    )
      throw new Error("Drawing layers exceed pixel budget");
    for (let i = depth + 1; i < this.layers.length; i++) {
      this.layers[i]!.width = 0;
      this.layers[i]!.height = 0;
    }
    const canvas = this.layers[depth] ?? document.createElement("canvas");
    this.layers[depth] = canvas;
    this.usedLayers = Math.max(this.usedLayers, depth + 1);
    if (canvas.width !== width) canvas.width = width;
    if (canvas.height !== height) canvas.height = height;
    const target = canvas.getContext("2d");
    if (!target) throw new Error("Layer canvas is unavailable");
    target.resetTransform();
    target.clearRect(0, 0, width, height);
    target.setTransform(matrix);
    return target;
  }

  /** Standalone shaping probe, whose positions are already resolved by the core. */
  draw(
    context: CanvasRenderingContext2D,
    batch: ShapeBatch,
    x = 0,
    baseline = 48,
  ): void {
    if (this.closed) throw new Error("Renderer is disposed");
    this.basePixels = context.canvas.width * context.canvas.height;
    this.imageWork = 0;
    this.glyphWork = 0;
    this.prepare(batch.outlines);
    this.glyphs(
      context,
      batch.glyphs.map<DrawGlyph>((glyph) => ({
        outline: glyph.outline,
        upem: batch.fonts[glyph.font]!.upem,
        fontBounds: [
          batch.fonts[glyph.font]!.bbox[0]!,
          batch.fonts[glyph.font]!.bbox[1]!,
          batch.fonts[glyph.font]!.bbox[2]!,
          batch.fonts[glyph.font]!.bbox[3]!,
        ],
        strokeWidth: glyph.strokeWidth,
        x: x + glyph.x,
        y: baseline + glyph.y,
        scaleX: glyph.scale,
        scaleY: -glyph.scale,
      })),
    );
  }

  private prepare(outlines: DrawingBatch["outlines"]): void {
    for (const outline of outlines)
      if (!this.paths.has(outline.key))
        this.paths.set(outline.key, compileGlyphPath(outline.path));
  }

  private applyStyle(
    context: CanvasRenderingContext2D,
    style: DrawStyle,
  ): void {
    if (this.rasterMode === "pdf") context.imageSmoothingQuality = "medium";
    context.lineCap = (["butt", "round", "square"] as const)[style.cap]!;
    context.lineJoin = (["miter", "round", "bevel"] as const)[style.join]!;
    context.miterLimit = style.miter;
    context.setLineDash(style.dash);
    context.lineDashOffset = style.dashOffset;
    context.globalCompositeOperation =
      style.blend === "normal" ? "source-over" : style.blend;
  }

  private glyphs(
    context: CanvasRenderingContext2D,
    glyphs: DrawGlyph[],
    mode: CanvasRasterMode = this.glyphRasterMode,
    pixelSize = false,
    sourceMatrix?: DrawMatrix,
  ): void {
    this.glyphWork += drawGlyphs(
      context,
      glyphs,
      mode,
      pixelSize,
      sourceMatrix,
      this.paths,
      16777216 -
        this.layers.reduce(
          (sum, canvas) => sum + canvas.width * canvas.height,
          this.basePixels,
        ),
      67108864 - this.glyphWork,
    );
  }

  dispose(): void {
    for (const canvas of this.layers) {
      canvas.width = 0;
      canvas.height = 0;
    }
    this.layers.length = 0;
    this.paths.clear();
    this.closed = true;
  }
}
