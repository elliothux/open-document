import { bindClipboard } from "@open-document/web-core/clipboard";
import type { PdfViewer } from "./pdf-viewer.js";

/** Keyboard and clipboard events retain the viewer's serialized input queue. */
export function bindPdfKeyboard(
  viewer: PdfViewer,
  signal: AbortSignal,
  perform: (action: () => Promise<unknown>) => void,
  error: (message: string) => void,
): void {
  bindClipboard(
    viewer.viewport,
    signal,
    (cut) =>
      perform(async () => {
        if (cut) throw new Error("PDF body text is read-only");
        await viewer.copy();
      }),
    () => error("PDF body text is read-only"),
    (failure) => error(failure.message),
    () => false,
  );
  viewer.viewport.addEventListener(
    "keydown",
    (event) => {
      if (
        event.defaultPrevented ||
        event.isComposing ||
        viewer.getSnapshot().paused
      )
        return;
      if (event.key === "PageDown" || event.key === "PageUp") {
        event.preventDefault();
        perform(() => viewer.navigatePage(event.key === "PageDown" ? 1 : -1));
      } else if (event.key === "F3") {
        event.preventDefault();
        perform(() => viewer.nextMatch(event.shiftKey ? -1 : 1));
      } else if (
        (event.ctrlKey || event.metaKey) &&
        event.key.toLowerCase() === "a" &&
        viewer.displayedPage
      ) {
        event.preventDefault();
        perform(() =>
          viewer.selectText(0, viewer.displayedPage?.text.length ?? 0),
        );
      }
    },
    { signal },
  );
}
