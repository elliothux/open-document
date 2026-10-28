import type { PageLayout } from "../core/preview.js";

export function docxPageText(layout: PageLayout, page: number): string {
  return (
    layout.semantics[page]?.lines
      .map((line) =>
        ((line.marker ?? "") + line.text).replaceAll("\ufffc", "[drawing]"),
      )
      .join("\n") ?? ""
  );
}

/** Native input and accessible text remain stable for the editor's lifetime. */
export function createDocumentElements(
  canvas: HTMLCanvasElement,
  overlay: HTMLCanvasElement,
  description: string,
) {
  const container = document.createElement("div"),
    viewport = document.createElement("div"),
    input = document.createElement("textarea"),
    text = document.createElement("pre");
  container.setAttribute("role", "region");
  container.tabIndex = -1;
  container.setAttribute("aria-label", "Document editor");
  text.setAttribute("aria-label", "Current page text");
  input.setAttribute("aria-label", "Document text input");
  input.setAttribute(
    "aria-keyshortcuts",
    "Shift+Enter Control+Enter Meta+Enter Tab Escape",
  );
  input.setAttribute("aria-description", description);
  input.autocomplete = "off";
  input.spellcheck = false;
  input.setAttribute("autocapitalize", "off");
  Object.assign(input.style, {
    position: "absolute",
    width: "1px",
    padding: "0",
    border: "0",
    opacity: "0",
    pointerEvents: "none",
    resize: "none",
  });
  Object.assign(viewport.style, {
    position: "relative",
    overflow: "auto",
    flex: "1",
    minHeight: "0",
  });
  viewport.append(canvas, overlay, input);
  Object.assign(container.style, {
    display: "flex",
    flexDirection: "column",
    flex: "1",
    minHeight: "0",
  });
  Object.assign(text.style, {
    position: "absolute",
    width: "1px",
    height: "1px",
    overflow: "hidden",
    clipPath: "inset(50%)",
  });
  container.append(viewport, text);
  return { container, viewport, input, text };
}
