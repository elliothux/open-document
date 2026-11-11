import type { DrawingBatch } from "./drawing.js";
import { ChartDelta } from "./chart-delta.js";

type Outline = DrawingBatch["outlines"][number];

/** Retain only the last drawing batch at this transport boundary. */
export class OutlineDelta {
  private previous = new Map<string, string>();
  private readonly charts = new ChartDelta();

  clear(): void {
    this.previous.clear();
    this.charts.clear();
  }

  update(value: unknown, encode = false): unknown {
    if (
      !value ||
      typeof value !== "object" ||
      !("regions" in value) ||
      !Array.isArray(value.regions) ||
      !("outlines" in value) ||
      !Array.isArray(value.outlines)
    )
      return value;

    const next = new Map<string, string>();
    const outlines = (value.outlines as (Outline | string)[]).map((entry) => {
      if (typeof entry === "string") {
        const path = this.previous.get(entry);
        if (path === undefined) throw new Error("Missing retained outline");
        next.set(entry, path);
        return { key: entry, path };
      }
      next.set(entry.key, entry.path);
      return encode && this.previous.get(entry.key) === entry.path
        ? entry.key
        : entry;
    });
    this.previous = next;
    return this.charts.update(
      { ...value, regions: value.regions, outlines },
      encode,
    );
  }
}
