import type {
  DrawingBatch,
  DrawingRegion,
  DrawGlyphRun,
  DrawStyle,
  DrawCommand,
  DrawMatrix,
  DrawRect,
  PdfGlyphCommand,
} from "@open-document/wasm/abi/drawing";
import type { ShapeBatch } from "@open-document/wasm/abi/shape";
import { ChartBitmaps, type ChartFrame } from "./drawing-chart.js";
import {
  clipDeviceRectangle,
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
import { pdfHairline } from "./pdf-hairline.js";
import { pdfPathStroke, pdfStroke } from "./pdf-stroke.js";
import {
  applyDrawingClip,
  applyDrawingStyle,
  drawingPath,
  strokeRectangle,
} from "./drawing-path.js";
export type CanvasRasterMode = "integer" | "fractional" | "pdf";

/** One renderer per core session. Platform resources never cross sessions. */
export class CanvasRenderer {
  private readonly paths = new Map<string, GlyphPath>();
  private readonly chartBitmaps = new ChartBitmaps();
  private closed = false;
  private basePixels = 0;
  private layerPixels = 0;
  private imageWork = 0;
  // Preserve image sampling capacity when glyph refinement reaches its limit.
  private glyphWork = 0;
  constructor(
    private glyphRasterMode?: CanvasRasterMode,
    private readonly imagePixels: ReadonlyMap<string, Uint8Array> = new Map(),
    private readonly imageColors: ReadonlyMap<string, ImageBitmap> = new Map(),
  ) {}

  setGlyphRasterMode(mode: CanvasRasterMode): boolean {
    if (this.closed) throw new Error("Renderer is disposed");
    if (!["integer", "fractional", "pdf"].includes(mode))
      throw new Error("Invalid glyph raster mode");
    const changed = this.glyphRasterMode !== mode;
    this.glyphRasterMode = mode;
    return changed;
  }

  private regionGlyphMode(region: DrawingRegion): CanvasRasterMode {
    return (
      this.glyphRasterMode ??
      (region.glyphRaster === "coverage"
        ? "pdf"
        : (region.glyphRaster ?? "integer"))
    );
  }

  drawRegion(
    context: CanvasRenderingContext2D,
    batch: DrawingBatch,
    index: number,
    images: ReadonlyMap<string, ImageBitmap> = new Map(),
    liveImages: ReadonlyMap<DrawCommand, CanvasImageSource> = new Map(),
    cacheChartTiles = false,
  ): void {
    if (this.closed) throw new Error("Renderer is disposed");
    const region = batch.regions[index];
    if (!region) throw new Error("Unknown drawing region");
    const retained = new Set(batch.outlines.map((outline) => outline.key));
    for (const key of this.paths.keys())
      if (!retained.has(key)) {
        this.paths.delete(key);
        this.chartBitmaps.clear();
      }
    this.prepare(batch.outlines);
    this.usedLayers = 0;
    this.basePixels = context.canvas.width * context.canvas.height;
    this.imageWork = 0;
    this.glyphWork = 0;
    const m = context.getTransform();
    const backingClip =
      region.backingClip &&
      m.b === 0 &&
      m.c === 0 &&
      m.e === 0 &&
      m.f === 0 &&
      m.a > 0 &&
      m.d > 0 &&
      context.canvas.width === Math.ceil(region.width * m.a) &&
      context.canvas.height === Math.ceil(region.height * m.d)
        ? {
            x: 0,
            y: 0,
            width: context.canvas.width / m.a,
            height: context.canvas.height / m.d,
          }
        : undefined;
    this.layerPixels = 0;
    for (const canvas of this.layers) {
      if (
        canvas.width !== context.canvas.width ||
        canvas.height !== context.canvas.height
      ) {
        canvas.width = 0;
        canvas.height = 0;
      } else this.layerPixels += canvas.width * canvas.height;
    }
    try {
      const charts =
        cacheChartTiles && !liveImages.size
          ? this.chartBitmaps.frame(
              context,
              region,
              this.regionGlyphMode(region),
              backingClip,
            )
          : undefined;
      this.drawCommands(
        context,
        region.commands,
        images,
        0,
        liveImages,
        region,
        false,
        charts,
        backingClip,
      );
    } finally {
      for (let i = this.usedLayers; i < this.layers.length; i++) {
        const canvas = this.layers[i]!;
        this.layerPixels -= canvas.width * canvas.height;
        canvas.width = 0;
        canvas.height = 0;
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
    raster: DrawingRegion,
    nativePatternCell = false,
    charts?: ChartFrame,
    backingClip?: DrawRect,
  ): void {
    const coverageImages = raster.imageSampling === "coverage";
    const coverageStroke = raster.strokeRaster === "coverage";
    const fractionalStroke = raster.strokeRaster === "fractional";
    let clips = 0;
    let clipBounds: ClipBounds | undefined;
    let paintClipped = false;
    let pixelCenters = false;
    const defaultGlyphMode = this.regionGlyphMode(raster);
    let glyphRasterMode = defaultGlyphMode;
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
    const defaultStyle = style;
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
    context.save();
    try {
      if (coverageImages) context.imageSmoothingQuality = "medium";
      applyDrawingStyle(context, style);
      for (let index = 0; index < commands.length; index++) {
        const next = charts?.(
          index,
          commands,
          clips,
          style === defaultStyle &&
            !pixelCenters &&
            glyphRasterMode === defaultGlyphMode,
        );
        if (next !== undefined) {
          index = next - 1;
          continue;
        }
        const command = commands[index]!;
        if (
          clipBounds &&
          command.op !== "style" &&
          command.op !== "transform" &&
          command.op !== "restore" &&
          command.op !== "pixelCenters" &&
          command.op !== "integerScreenGlyphs" &&
          command.op !== "clipPath" &&
          command.op !== "clipRect"
        ) {
          context.save();
          paintClipped = true;
          clipDeviceRectangle(
            context,
            clipBounds,
            command.op === "pdfGlyphs" ||
              (command.op === "glyphs" &&
                command.runs.every(([, , strokeWidth]) => strokeWidth === 0)),
          );
        }
        switch (command.op) {
          case "tile":
            drawTile(
              context,
              command,
              (width, height, matrix) =>
                this.layerContext(context, depth, width, height, matrix),
              (target, commands, nativeCell) =>
                this.drawCommands(
                  target,
                  commands,
                  images,
                  depth + 1,
                  liveImages,
                  raster,
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
              raster,
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
              raster,
              command.mask,
            );
            break;
          case "fillRect": {
            context.globalAlpha = style.fillAlpha;
            const rect = command.rect;
            context.fillStyle = `#${rect.color}`;
            if (
              pixelCenters ||
              command.screenFractional ||
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
              coverageImages,
              (width, height) =>
                this.imageTarget(context, depth, width, height),
            );
            break;
          case "strokeRect":
          case "strokeBands": {
            context.globalAlpha = style.strokeAlpha;
            context.strokeStyle = `#${command.color}`;
            context.lineWidth = command.lineWidth;
            if (command.op === "strokeRect") {
              strokeRectangle(context, command, pixelCenters, coverageStroke);
            } else {
              const rect = { x: 0, y: 0, width: 0, height: 0 };
              const stroke = {
                op: "strokeRect" as const,
                rect,
                color: command.color,
                lineWidth: command.lineWidth,
              };
              for (const [y, height, spans] of command.bands) {
                rect.y = y;
                rect.height = height;
                for (const [x, width] of spans) {
                  rect.x = x;
                  rect.width = width;
                  strokeRectangle(
                    context,
                    stroke,
                    pixelCenters,
                    coverageStroke,
                  );
                }
              }
            }
            break;
          }
          case "gradientRect":
          case "radialGradientRect": {
            const rect = command.rect;
            if (rect.width === 0 || rect.height === 0) break;
            const gradient =
              command.op === "radialGradientRect"
                ? context.createRadialGradient(...command.circles)
                : context.createLinearGradient(
                    rect.x,
                    rect.y,
                    rect.x + rect.width,
                    rect.y,
                  );
            for (const stop of command.stops) {
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
          case "pdfGlyphs":
            context.save();
            try {
              context.globalAlpha = style.fillAlpha;
              context.fillStyle = `#${command.color}`;
              this.glyphs(
                context,
                command,
                glyphRasterMode,
                false,
                sourceMatrix,
              );
            } finally {
              context.restore();
            }
            break;
          case "glyphs":
            context.globalAlpha = style.fillAlpha;
            context.fillStyle = `#${command.color}`;
            context.save();
            try {
              context.translate(command.x, command.y);
              this.glyphs(
                context,
                command.runs,
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
            const { image, crop } = command;
            const live = liveImages.get(command);
            const poster = images.get(image.key);
            const bitmap = live ?? poster;
            if (!bitmap) throw new Error(`Missing image: ${image.key}`);
            if (crop) context.save();
            try {
              context.globalAlpha = style.fillAlpha;
              if (crop && live) {
                const rect = crop.clip;
                context.beginPath();
                context.rect(rect.x, rect.y, rect.width, rect.height);
                context.clip();
              }
              imageSmoothing(
                context,
                bitmap,
                image.width,
                image.height,
                image.interpolate,
                command.preservePixels === true,
              );
              const target = (width: number, height: number) =>
                this.imageTarget(context, depth, width, height);
              const pixels = this.imagePixels.get(image.key);
              const colors = this.imageColors.get(image.key);
              if (crop && !live && poster)
                drawCroppedImage(
                  context,
                  poster,
                  image,
                  crop.visible,
                  target,
                  pixels,
                  colors,
                );
              else
                drawImage(
                  context,
                  bitmap,
                  image,
                  nativePatternCell,
                  target,
                  pixels,
                  colors,
                );
            } finally {
              if (crop) context.restore();
            }
            break;
          }
          case "style":
            style = command.style;
            applyDrawingStyle(context, style);
            break;
          case "pixelCenters":
            pixelCenters = true;
            break;
          case "integerScreenGlyphs":
            glyphRasterMode = "integer";
            break;
          case "path": {
            let path: Path2D | undefined;
            const curves = command.strokeGeometry === "curve";
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
                path = drawingPath(command.path);
                context.fill(path, style.evenOdd ? "evenodd" : "nonzero");
              }
              if (command.stroke) {
                context.globalAlpha = style.strokeAlpha;
                context.strokeStyle = `#${command.stroke}`;
                const hairline = command.lineWidth === 0;
                const m = command.lineWidth
                  ? undefined
                  : context.getTransform();
                // shortcut: nonuniform hairlines use the largest scale; use device paths if required.
                context.lineWidth = m
                  ? 1 / Math.max(Math.hypot(m.a, m.b), Math.hypot(m.c, m.d))
                  : command.lineWidth;
                if (
                  !(
                    !pixelCenters &&
                    ((hairline &&
                      m &&
                      !curves &&
                      !fractionalStroke &&
                      pdfHairline(context, command.path, m)) ||
                      pixelRectangleStroke(
                        context,
                        command,
                        coverageStroke,
                        false,
                        command.rectangleDashes,
                      ))
                  ) &&
                  !(
                    !pixelCenters &&
                    (!fractionalStroke || command.textRule) &&
                    pdfStroke(context, command, fractionalStroke)
                  ) &&
                  !(
                    !pixelCenters &&
                    !fractionalStroke &&
                    pdfPathStroke(
                      context,
                      command.path,
                      command.strokeGeometry,
                      coverageStroke || (Boolean(command.fill) && !curves),
                      Boolean(command.fill),
                      16777216 - this.basePixels - this.layerPixels,
                      hairline,
                      command.strokeOutline,
                      command.strokeDashes,
                      command.strokeBounds,
                      command.strokeDashesAxisAligned,
                      command.strokeNonRectangular,
                    )
                  )
                )
                  context.stroke(
                    pixelCenters && hairline
                      ? drawingPath(command.path, m)
                      : (path ?? drawingPath(command.path)),
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
          case "clipPath":
          case "clipRect":
            saveScope();
            clipBounds = applyDrawingClip(
              context,
              command,
              raster.deviceClips === true,
              clipBounds,
              index === 0 ? backingClip : undefined,
            );
            break;
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
    raster: DrawingRegion,
    mask: DrawCommand[] | null,
  ): void {
    const nextDepth = depth + (mask === null ? 1 : 2);
    const target = this.layerContext(context, depth);
    this.drawCommands(target, commands, images, nextDepth, liveImages, raster);
    if (mask !== null) {
      const alpha = this.layerContext(context, depth + 1);
      this.drawCommands(alpha, mask, images, nextDepth, liveImages, raster);
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
    this.layerPixels = pixels - this.basePixels;
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
      batch.glyphs.map<DrawGlyphRun>((glyph) => {
        const font = batch.fonts[glyph.font]!;
        return [
          font.upem,
          [font.bbox[0]!, font.bbox[1]!, font.bbox[2]!, font.bbox[3]!],
          glyph.strokeWidth,
          glyph.scale,
          -glyph.scale,
          [[glyph.outline, x + glyph.x, baseline + glyph.y]],
        ];
      }),
    );
  }

  private prepare(outlines: DrawingBatch["outlines"]): void {
    for (const outline of outlines)
      if (!this.paths.has(outline.key))
        this.paths.set(outline.key, compileGlyphPath(outline.path));
  }

  private glyphs(
    context: CanvasRenderingContext2D,
    runs: DrawGlyphRun[] | PdfGlyphCommand,
    mode: CanvasRasterMode = this.glyphRasterMode ?? "integer",
    pixelSize = false,
    sourceMatrix?: DrawMatrix,
  ): void {
    this.glyphWork += drawGlyphs(
      context,
      runs,
      mode,
      pixelSize,
      sourceMatrix,
      this.paths,
      16777216 - this.basePixels - this.layerPixels,
      67108864 - this.glyphWork,
    );
  }

  dispose(): void {
    this.chartBitmaps.clear();
    for (const canvas of this.layers) {
      canvas.width = 0;
      canvas.height = 0;
    }
    this.layers.length = 0;
    this.paths.clear();
    this.closed = true;
  }
}
