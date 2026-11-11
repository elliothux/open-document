import type {
  DrawCommand,
  DrawRect,
  DrawStyle,
  PathSegment,
} from "@open-document/wasm/abi/drawing";
import {
  pixelClipRectangle,
  pixelRectangleStroke,
  type ClipBounds,
} from "./pdf-pixels.js";

export function applyDrawingClip(
  context: CanvasRenderingContext2D,
  command: Extract<DrawCommand, { op: "clipPath" | "clipRect" }>,
  deviceClips: boolean,
  previous: ClipBounds | undefined,
  backingClip?: DrawRect,
): ClipBounds | undefined {
  let rectangle: ClipBounds;
  if (command.op === "clipRect") {
    const { x, y, width, height } = backingClip ?? command.rect;
    if (!deviceClips) {
      context.beginPath();
      context.rect(x, y, width, height);
      context.clip();
      return previous;
    }
    rectangle = [x, y, x + width, y + height];
  } else if ("rectangle" in command) {
    rectangle = command.rectangle;
  } else {
    context.clip(
      drawingPath(command.path),
      command.evenOdd ? "evenodd" : "nonzero",
    );
    return previous;
  }
  const { path, bounds } = pixelClipRectangle(
    context,
    rectangle,
    deviceClips,
    command.shading,
  );
  if (bounds)
    return previous
      ? [
          Math.max(previous[0], bounds[0]),
          Math.max(previous[1], bounds[1]),
          Math.min(previous[2], bounds[2]),
          Math.min(previous[3], bounds[3]),
        ]
      : bounds;
  context.clip(
    path,
    command.op === "clipPath" && command.evenOdd ? "evenodd" : "nonzero",
  );
  return previous;
}

export function drawingPath(segments: PathSegment[], grid?: DOMMatrix): Path2D {
  const inverse = grid?.inverse();
  const point = (x: number, y: number): [number, number] => {
    if (!grid || !inverse || !Number.isFinite(inverse.a)) return [x, y];
    const device = grid.transformPoint({ x, y });
    const snapped = inverse.transformPoint({
      x: Math.trunc(device.x) + 0.5,
      y: Math.trunc(device.y) + 0.5,
    });
    return [snapped.x, snapped.y];
  };
  const path = new Path2D();
  for (const segment of segments) {
    switch (segment.op) {
      case "move":
        path.moveTo(...point(segment.x, segment.y));
        break;
      case "line":
        path.lineTo(...point(segment.x, segment.y));
        break;
      case "cubic":
        path.bezierCurveTo(
          ...point(segment.x1, segment.y1),
          ...point(segment.x2, segment.y2),
          ...point(segment.x, segment.y),
        );
        break;
      case "close":
        path.closePath();
        break;
    }
  }
  return path;
}

export function strokeRectangle(
  context: CanvasRenderingContext2D,
  command: Extract<DrawCommand, { op: "strokeRect" }>,
  pixelCenters: boolean,
  pdf: boolean,
): void {
  const { rect } = command;
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
    (command.screenFractional && !pdf) ||
    !pixelRectangleStroke(context, command, pdf)
  ) {
    context.strokeRect(rect.x, rect.y, rect.width, rect.height);
  }
}

export function applyDrawingStyle(
  context: CanvasRenderingContext2D,
  style: DrawStyle,
): void {
  context.lineCap = (["butt", "round", "square"] as const)[style.cap]!;
  context.lineJoin = (["miter", "round", "bevel"] as const)[style.join]!;
  context.miterLimit = style.miter;
  context.setLineDash(style.dash);
  context.lineDashOffset = style.dashOffset;
  context.globalCompositeOperation =
    style.blend === "normal" ? "source-over" : style.blend;
}
