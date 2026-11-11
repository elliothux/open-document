import type {
  DrawCommand,
  DrawRect,
  DrawingRegion,
} from "@open-document/wasm/abi/drawing";
import { chartTileSpans } from "@open-document/wasm/abi/chart-delta";

type Box = { x: number; y: number; width: number; height: number };
export type ChartFrame = (
  index: number,
  commands: DrawCommand[],
  clips: number,
  defaultStyle: boolean,
) => number | undefined;

const pixelLimit = 2_097_152;
const keyLimit = 1_048_576;

function deviceBox(rect: Box, matrix: DOMMatrix): Box {
  return {
    x: rect.x * matrix.a + matrix.e,
    y: rect.y * matrix.d + matrix.f,
    width: rect.width * matrix.a,
    height: rect.height * matrix.d,
  };
}

function contains(outer: Box, inner: Box): boolean {
  return (
    outer.x <= inner.x &&
    outer.y <= inner.y &&
    outer.x + outer.width >= inner.x + inner.width &&
    outer.y + outer.height >= inner.y + inner.height
  );
}

export class ChartBitmaps {
  private readonly tiles = new Map<string, HTMLCanvasElement>();
  private pixels = 0;
  private keys = 0;

  frame(
    context: CanvasRenderingContext2D,
    region: DrawingRegion,
    mode: string,
    backingClip?: DrawRect,
  ): ChartFrame | undefined {
    const spans = chartTileSpans(region);
    if (
      !spans ||
      context.filter !== "none" ||
      context.shadowColor !== "rgba(0, 0, 0, 0)" ||
      context.getContextAttributes().colorSpace !== "srgb"
    )
      return;
    const root = context.getTransform();
    let pending: { end: number; store: () => void } | undefined;
    return (index, commands, clips, defaultStyle) => {
      if (pending?.end === index) {
        if (clips === 4) pending.store();
        pending = undefined;
      }
      const end = spans.get(index);
      if (!end || clips !== 4 || !defaultStyle) return;
      const page = commands[0];
      const pane = commands[index - 3];
      const chart = commands[index - 2];
      const transform = commands[index - 1];
      if (
        page?.op !== "clipRect" ||
        pane?.op !== "clipRect" ||
        chart?.op !== "clipRect" ||
        transform?.op !== "transform" ||
        commands[end]?.op !== "restore" ||
        commands[end + 1]?.op !== "restore" ||
        commands[end + 2]?.op !== "restore" ||
        root.b !== 0 ||
        root.c !== 0 ||
        root.a <= 0 ||
        root.d <= 0
      )
        return;
      const matrix = context.getTransform();
      if (matrix.b !== 0 || matrix.c !== 0 || matrix.a <= 0 || matrix.d <= 0)
        return;
      const box = deviceBox(chart.rect, root);
      const { x, y, width, height } = box;
      if (
        ![x, y, width, height].every(Number.isSafeInteger) ||
        width <= 0 ||
        height <= 0 ||
        width * height > pixelLimit ||
        !contains(
          {
            x: 0,
            y: 0,
            width: context.canvas.width,
            height: context.canvas.height,
          },
          box,
        ) ||
        !contains(deviceBox(backingClip ?? page.rect, root), box) ||
        !contains(deviceBox(pane.rect, root), box)
      )
        return;
      const body = commands.slice(index, end);
      if (
        body.some(
          (command) =>
            command.op === "image" ||
            command.op === "layer" ||
            command.op === "mask" ||
            command.op === "tile",
        )
      )
        return;
      const first = body.find((command) => {
        if (command.op === "integerScreenGlyphs") return false;
        return (
          command.op !== "clipRect" ||
          !contains(deviceBox(command.rect, matrix), box)
        );
      });
      if (
        first?.op !== "fillRect" ||
        !/^[0-9a-f]{6}$/i.test(first.rect.color) ||
        !contains(deviceBox(first.rect, matrix), box)
      )
        return;
      const key = JSON.stringify([
        mode,
        matrix.a,
        matrix.d,
        matrix.e - x,
        matrix.f - y,
        width,
        height,
        body,
      ]);
      if (key.length > keyLimit) return;
      const bitmap = this.tiles.get(key);
      if (bitmap) {
        context.save();
        try {
          context.resetTransform();
          context.globalAlpha = 1;
          context.globalCompositeOperation = "source-over";
          context.imageSmoothingEnabled = false;
          context.drawImage(bitmap, x, y);
        } finally {
          context.restore();
        }
        return end;
      }
      pending = { end, store: () => this.capture(context, key, box) };
    };
  }

  private capture(
    source: CanvasRenderingContext2D,
    key: string,
    { x, y, width, height }: Box,
  ): void {
    const area = width * height;
    while (
      this.pixels + area > pixelLimit ||
      this.keys + key.length > keyLimit
    ) {
      const oldest = this.tiles.keys().next().value;
      if (oldest === undefined) return;
      this.release(oldest);
    }
    const bitmap = document.createElement("canvas");
    bitmap.width = width;
    bitmap.height = height;
    const target = bitmap.getContext("2d");
    if (!target) return;
    target.imageSmoothingEnabled = false;
    try {
      target.drawImage(source.canvas, x, y, width, height, 0, 0, width, height);
    } catch {
      bitmap.width = bitmap.height = 0;
      return;
    }
    this.tiles.set(key, bitmap);
    this.pixels += area;
    this.keys += key.length;
  }

  private release(key: string): void {
    const bitmap = this.tiles.get(key)!;
    this.pixels -= bitmap.width * bitmap.height;
    this.keys -= key.length;
    bitmap.width = bitmap.height = 0;
    this.tiles.delete(key);
  }

  clear(): void {
    for (const key of this.tiles.keys()) this.release(key);
  }
}
