import type { PathSegment } from "@open-document/wasm/abi/drawing";

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
