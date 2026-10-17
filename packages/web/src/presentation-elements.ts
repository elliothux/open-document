/** Keep native input and canvas ownership stable across rendering and output. */
export function createPresentationElements(
  canvas: HTMLCanvasElement,
  overlay: HTMLCanvasElement,
) {
  const container = document.createElement("div"),
    viewport = document.createElement("div"),
    holder = document.createElement("div"),
    input = document.createElement("textarea"),
    objectList = document.createElement("ol");
  Object.assign(container.style, {
    display: "flex",
    flexDirection: "column",
    flex: "1",
    minHeight: "0",
  });
  container.setAttribute("role", "region");
  container.setAttribute("aria-label", "Presentation editor");
  objectList.setAttribute("aria-label", "Slide objects");
  Object.assign(viewport.style, {
    overflow: "auto",
    flex: "1",
    minHeight: "0",
  });
  Object.assign(holder.style, { position: "relative", width: "max-content" });
  Object.assign(input.style, {
    position: "absolute",
    opacity: "0",
    width: "1px",
    padding: "0",
    border: "0",
    resize: "none",
    pointerEvents: "none",
  });
  input.setAttribute("aria-label", "Slide input");
  input.autocomplete = "off";
  input.spellcheck = false;
  input.setAttribute("autocapitalize", "off");
  input.tabIndex = -1;
  holder.append(canvas, overlay, input);
  viewport.append(holder);
  return { container, viewport, holder, input, objectList };
}
