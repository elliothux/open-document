import type { XlsxViewport } from "@open-document/wasm/xlsx";
import type { XlsxClient } from "./xlsx.js";
import type { PointerHost } from "./spreadsheet-pointer.js";
import type { CanvasSurface } from "./canvas-surface.js";

export function stepTimelineEndpoint(
  client: XlsxClient,
  host: PointerHost,
  object: string,
  handle: number,
  key: string,
): Promise<void> {
  const sheet = host.current().query.sheet;
  return host.run(async () => {
    await host.prepare();
    const now = host.current(),
      timeline = now.layout?.objects.find(
        (item) => item.id === object,
      )?.timeline;
    if (now.query.sheet !== sheet || !timeline)
      throw new Error("Timeline endpoint target changed");
    const endpoint = timeline.handles.find((item) => item.handle === handle);
    if (!endpoint) throw new Error("Timeline endpoint is no longer visible");
    const navigation = timeline.navigation;
    const direction = ["ArrowLeft", "ArrowDown", "PageDown"].includes(key)
      ? -1
      : 1;
    const delta =
      direction *
      (key.startsWith("Page") ? Math.max(1, timeline.periods.length) : 1);
    const position = Math.max(
      navigation.minimum,
      Math.min(
        navigation.maximum,
        key === "Home"
          ? navigation.minimum
          : key === "End"
            ? navigation.maximum
            : endpoint.index + delta,
      ),
    );
    host.assign(
      await client.editSheet(now.query.revision, sheet, {
        action: "setTimelineEndpoint",
        name: timeline.name,
        handle,
        level: navigation.level,
        position,
      }),
    );
    await host.render();
  });
}

export function paintTimelineEndpoints(
  surface: CanvasSurface,
  drawing: XlsxViewport,
  object: string,
  scale: number,
): void {
  const context = surface.clearOverlay(scale);
  context.fillStyle = "#2563eb";
  for (const endpoint of drawing.objects.find((item) => item.id === object)
    ?.timeline?.handles ?? [])
    for (const { clip } of endpoint.regions)
      context.fillRect(clip.x, clip.y, clip.width, clip.height);
}
