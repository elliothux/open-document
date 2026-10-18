import type {
  DrawingBatch,
  DrawGlyph,
  DrawStyle,
} from "@open-document/wasm/drawing";
import type { ShapeBatch } from "@open-document/wasm/foundation";

/** One renderer per core session. Platform resources never cross sessions. */
export class CanvasRenderer {
  private readonly paths = new Map<string, Path2D>();
  private closed = false;

  drawRegion(
    context: CanvasRenderingContext2D,
    batch: DrawingBatch,
    index: number,
    images: ReadonlyMap<string, ImageBitmap> = new Map(),
  ): void {
    if (this.closed) throw new Error("Renderer is disposed");
    const region = batch.regions[index];
    if (!region) throw new Error("Unknown drawing region");
    const retained = new Set(batch.outlines.map((outline) => outline.key));
    for (const key of this.paths.keys())
      if (!retained.has(key)) this.paths.delete(key);
    this.prepare(batch.outlines);
    let clips = 0;
    let style: DrawStyle = {
      fillAlpha: 1,
      strokeAlpha: 1,
      evenOdd: false,
      cap: 0,
      join: 0,
      miter: 10,
      dash: [],
      dashOffset: 0,
      multiply: false,
      imageSmoothing: true,
    };
    const styles: DrawStyle[] = [];
    context.save();
    try {
      this.applyStyle(context, style);
      for (const command of region.commands) {
        switch (command.op) {
          case "fillRect": {
            context.globalAlpha = style.fillAlpha;
            const rect = command.rect;
            context.fillStyle = `#${rect.color}`;
            context.fillRect(rect.x, rect.y, rect.width, rect.height);
            break;
          }
          case "strokeRect": {
            context.globalAlpha = style.strokeAlpha;
            const rect = command.rect;
            context.strokeStyle = `#${command.color}`;
            context.lineWidth = command.lineWidth;
            context.strokeRect(rect.x, rect.y, rect.width, rect.height);
            break;
          }
          case "gradientRect": {
            const rect = command.rect;
            if (rect.width === 0 || rect.height === 0) break;
            const gradient = context.createLinearGradient(
              rect.x,
              rect.y,
              rect.x + rect.width,
              rect.y,
            );
            for (const stop of command.stops)
              gradient.addColorStop(
                stop.position,
                `rgba(${Number.parseInt(stop.color.slice(0, 2), 16)},${Number.parseInt(stop.color.slice(2, 4), 16)},${Number.parseInt(stop.color.slice(4, 6), 16)},${stop.opacity})`,
              );
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
              this.glyphs(context, command.glyphs);
            } finally {
              context.restore();
            }
            break;
          case "image": {
            context.globalAlpha = style.fillAlpha;
            const image = command.image;
            const bitmap = images.get(image.key);
            if (!bitmap) throw new Error(`Missing image: ${image.key}`);
            context.drawImage(
              bitmap,
              image.x,
              image.y,
              image.width,
              image.height,
            );
            break;
          }
          case "style":
            style = command.style;
            this.applyStyle(context, style);
            break;
          case "clipPath":
          case "path": {
            const path = new Path2D();
            for (const segment of command.path) {
              switch (segment.op) {
                case "move":
                  path.moveTo(segment.x, segment.y);
                  break;
                case "line":
                  path.lineTo(segment.x, segment.y);
                  break;
                case "cubic":
                  path.bezierCurveTo(
                    segment.x1,
                    segment.y1,
                    segment.x2,
                    segment.y2,
                    segment.x,
                    segment.y,
                  );
                  break;
                case "close":
                  path.closePath();
                  break;
              }
            }
            if (command.op === "clipPath") {
              context.save();
              clips++;
              styles.push(style);
              context.clip(path, command.evenOdd ? "evenodd" : "nonzero");
              break;
            }
            if (command.fill) {
              context.globalAlpha = style.fillAlpha;
              context.fillStyle = `#${command.fill}`;
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
              context.stroke(path);
            }
            break;
          }
          case "transform": {
            const m = command.matrix;
            context.save();
            clips++;
            styles.push(style);
            context.transform(m.a, m.b, m.c, m.d, m.e, m.f);
            break;
          }
          case "clipRect": {
            const rect = command.rect;
            context.save();
            clips++;
            styles.push(style);
            context.beginPath();
            context.rect(rect.x, rect.y, rect.width, rect.height);
            context.clip();
            break;
          }
          case "restore":
            if (clips === 0) throw new Error("Invalid drawing clip stack");
            context.restore();
            style = styles.pop() ?? style;
            clips--;
            break;
          default:
            throw new Error("Unknown drawing command");
        }
      }
      if (clips !== 0) throw new Error("Unclosed drawing clip");
    } finally {
      while (clips-- > 0) context.restore();
      context.restore();
    }
  }

  /** Standalone shaping probe, whose positions are already resolved by the core. */
  draw(
    context: CanvasRenderingContext2D,
    batch: ShapeBatch,
    x = 0,
    baseline = 48,
  ): void {
    if (this.closed) throw new Error("Renderer is disposed");
    this.prepare(batch.outlines);
    this.glyphs(
      context,
      batch.glyphs.map((glyph) => ({
        outline: glyph.outline,
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
        this.paths.set(outline.key, new Path2D(outline.path));
  }

  private applyStyle(
    context: CanvasRenderingContext2D,
    style: DrawStyle,
  ): void {
    context.imageSmoothingEnabled = style.imageSmoothing;
    context.lineCap = (["butt", "round", "square"] as const)[style.cap]!;
    context.lineJoin = (["miter", "round", "bevel"] as const)[style.join]!;
    context.miterLimit = style.miter;
    context.setLineDash(style.dash);
    context.lineDashOffset = style.dashOffset;
    context.globalCompositeOperation = style.multiply
      ? "multiply"
      : "source-over";
  }

  private glyphs(context: CanvasRenderingContext2D, glyphs: DrawGlyph[]): void {
    for (const glyph of glyphs) {
      const path = this.paths.get(glyph.outline);
      if (!path) throw new Error(`Missing outline: ${glyph.outline}`);
      context.save();
      try {
        context.translate(glyph.x, glyph.y);
        context.scale(glyph.scaleX, glyph.scaleY);
        context.fill(path);
      } finally {
        context.restore();
      }
    }
  }

  dispose(): void {
    this.paths.clear();
    this.closed = true;
  }
}
