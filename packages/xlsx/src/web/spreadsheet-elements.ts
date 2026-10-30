import { prepareGridInput } from "./spreadsheet-input.js";
import type { CanvasSurface } from "@open-document/web-core/canvas-surface";
import type { XlsxViewport } from "../core/xlsx.js";

export function observeGridViewport(
  viewport: HTMLElement,
  input: HTMLElement,
  signal: AbortSignal,
  current: () => {
    layout: XlsxViewport | undefined;
    scale: number;
    drawingScroll: boolean;
  },
  render: () => void,
): ResizeObserver {
  const options = { signal };
  viewport.addEventListener(
    "focus",
    () => input.focus({ preventScroll: true }),
    options,
  );
  viewport.addEventListener(
    "scroll",
    () => {
      const { layout, scale, drawingScroll } = current();
      if (!drawingScroll && gridScrollChanged(viewport, layout, scale))
        render();
    },
    options,
  );
  const resize = new ResizeObserver(render);
  resize.observe(viewport);
  window.addEventListener("resize", render, options);
  return resize;
}

function gridScrollX(viewport: HTMLElement, scale: number): number {
  return ((viewport.dir === "rtl" ? -1 : 1) * viewport.scrollLeft) / scale;
}

export function gridScrollChanged(
  viewport: HTMLElement,
  layout: Pick<XlsxViewport, "scrollX" | "scrollY"> | undefined,
  scale: number,
): boolean {
  return (
    !layout ||
    Math.abs(gridScrollX(viewport, scale) - layout.scrollX) > 0.1 ||
    Math.abs(viewport.scrollTop / scale - layout.scrollY) > 0.1
  );
}

export function prepareGridViewport(
  viewport: HTMLElement,
  rtl: boolean,
  scrollX: number,
  scale: number,
) {
  const direction = rtl ? "rtl" : "ltr";
  if (viewport.dir !== direction) {
    viewport.dir = direction;
    viewport.scrollLeft = (rtl ? -1 : 1) * scrollX * scale;
  }
  return {
    scrollX: gridScrollX(viewport, scale),
    scrollY: viewport.scrollTop / scale,
    width: Math.max(120, viewport.clientWidth / scale),
    height: Math.max(60, viewport.clientHeight / scale),
  };
}

export function updateGridScroll(
  viewport: HTMLElement,
  spacer: HTMLElement,
  layout: XlsxViewport,
  scale: number,
): void {
  spacer.style.width = `${(layout.extentWidth + layout.headerWidth) * scale}px`;
  spacer.style.height = `${(layout.extentHeight + layout.headerHeight) * scale}px`;
  viewport.scrollLeft = (layout.rtl ? -1 : 1) * layout.scrollX * scale;
  viewport.scrollTop = layout.scrollY * scale;
}

export function createGridElements(
  root: HTMLElement,
  surface: CanvasSurface,
  printView: { element: HTMLElement },
) {
  const container = document.createElement("div");
  const viewport = document.createElement("div");
  const holder = document.createElement("div");
  const spacer = document.createElement("div");
  const input = document.createElement("textarea");
  const semantics = document.createElement("div");
  Object.assign(container.style, {
    display: "flex",
    flexDirection: "column",
    flex: "1",
    minHeight: "0",
  });
  container.setAttribute("role", "region");
  container.setAttribute("aria-label", "Spreadsheet editor");
  viewport.setAttribute("role", "grid");
  viewport.setAttribute("aria-label", "Worksheet cells");
  viewport.tabIndex = 0;
  Object.assign(viewport.style, {
    position: "relative",
    overflow: "auto",
    flex: "1",
    minHeight: "0",
    width: "100%",
  });
  Object.assign(holder.style, {
    position: "sticky",
    left: "0",
    right: "0",
    top: "0",
    height: "0",
    zIndex: "1",
    direction: "ltr",
  });
  Object.assign(surface.canvas.style, {
    position: "absolute",
    left: "0",
    top: "0",
  });
  prepareGridInput(input);
  Object.assign(semantics.style, {
    position: "absolute",
    top: "0",
    left: "0",
    width: "1px",
    height: "1px",
    overflow: "hidden",
    clipPath: "inset(50%)",
  });
  semantics.setAttribute("role", "rowgroup");
  holder.append(surface.canvas, surface.overlay, input);
  viewport.append(holder, spacer, semantics);
  container.append(viewport, printView.element);
  root.append(container);
  return { container, viewport, holder, spacer, input, semantics };
}
