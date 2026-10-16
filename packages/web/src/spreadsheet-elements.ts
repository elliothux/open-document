import { prepareGridInput } from "./spreadsheet-input.js";
import type { CanvasSurface } from "./canvas-surface.js";

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
    top: "0",
    height: "0",
    zIndex: "1",
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
