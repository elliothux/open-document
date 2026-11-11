import type { DrawCommand, DrawingBatch, DrawingRegion } from "./drawing.js";

type ChartTile = {
  op: "chartTile";
  key: string;
  commands?: DrawCommand[];
};
type WireRegion = Omit<DrawingRegion, "commands"> & {
  commands: (DrawCommand | ChartTile)[];
};

// Worker encoding uses the original tile bodies, while callers get flat commands.
const wireRegions = new WeakMap<DrawingRegion[], WireRegion[]>();
const chartSpans = new WeakMap<DrawingRegion, ReadonlyMap<number, number>>();

export function chartTileSpans(
  region: DrawingRegion,
): ReadonlyMap<number, number> | undefined {
  return chartSpans.get(region);
}

export class ChartDelta {
  private previous = new Map<string, DrawCommand[]>();

  clear(): void {
    this.previous.clear();
  }

  update<T extends Pick<DrawingBatch, "regions">>(
    value: T,
    encode: boolean,
  ): unknown {
    const regions = encode
      ? wireRegions.get(value.regions)
      : "chartTiles" in value && value.chartTiles === true
        ? (value.regions as WireRegion[])
        : undefined;
    if (!regions) return value;

    const next = new Map<string, DrawCommand[]>();
    const wire: WireRegion[] = regions.map((region) => {
      const commands = region.commands.map((command) => {
        if (command.op !== "chartTile") return command;
        const cached = next.get(command.key) ?? this.previous.get(command.key);
        const body = command.commands ?? cached;
        if (!body) throw new Error("Missing retained chart tile");
        next.set(command.key, body);
        return encode && cached === body
          ? { op: command.op, key: command.key }
          : { ...command, commands: body };
      });
      return { ...region, commands };
    });
    this.previous = next;
    if (encode) return { ...value, regions: wire, chartTiles: true };

    const expanded = wire.map((region) => {
      const spans = new Map<number, number>();
      const commands: DrawCommand[] = [];
      for (const command of region.commands) {
        if (command.op !== "chartTile") {
          commands.push(command);
          continue;
        }
        const body = structuredClone(command.commands ?? []);
        const start = commands.length;
        for (const item of body) commands.push(item);
        if (body.length) spans.set(start, commands.length);
      }
      const result = { ...region, commands };
      if (spans.size) chartSpans.set(result, spans);
      return result;
    });
    wireRegions.set(expanded, wire);
    const { chartTiles: _marker, ...result } = value as typeof value & {
      chartTiles: true;
    };
    return { ...result, regions: expanded };
  }
}
