/** Owns at most one browser PDF frame per editor. */
export class PdfPrinter {
  private release: ((reason?: Error) => void) | undefined;

  constructor(private readonly document: Document) {}

  print(bytes: Uint8Array, name: string): Promise<void> {
    this.cancel();
    return new Promise((resolve, reject) => {
      const frame = this.document.createElement("iframe");
      const url = URL.createObjectURL(
        new Blob([new Uint8Array(bytes).buffer], { type: "application/pdf" }),
      );
      frame.title = name;
      frame.dataset.odPrint = "";
      frame.tabIndex = -1;
      frame.setAttribute("aria-hidden", "true");
      Object.assign(frame.style, {
        position: "fixed",
        width: "1px",
        height: "1px",
        left: "-10000px",
        border: "0",
        pointerEvents: "none",
      });
      const release = (reason?: Error) => {
        clearTimeout(timer);
        frame.onload = null;
        frame.onerror = null;
        frame.remove();
        URL.revokeObjectURL(url);
        if (this.release === release) this.release = undefined;
        if (reason) reject(reason);
      };
      const timer = setTimeout(
        () => release(new Error("Print PDF did not load")),
        30_000,
      );
      this.release = release;
      frame.onload = () => {
        clearTimeout(timer);
        try {
          const target = frame.contentWindow;
          if (!target) throw new Error("Print window is unavailable");
          target.addEventListener("afterprint", () => release(), {
            once: true,
          });
          // shortcut: PDF viewers may omit afterprint; retain one PDF until the next print, file change or dispose.
          target.focus();
          target.print();
          resolve();
        } catch (error) {
          release(error instanceof Error ? error : new Error(String(error)));
        }
      };
      frame.onerror = () => release(new Error("Print PDF failed to load"));
      frame.src = url;
      this.document.body.append(frame);
    });
  }

  cancel(): void {
    this.release?.(new DOMException("Printing cancelled", "AbortError"));
  }
}
