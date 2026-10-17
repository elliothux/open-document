import type { FoundationClient } from "./foundation.js";
import type {
  DocxPictures,
  DocxSelectionGeometry,
} from "@open-document/wasm/foundation";
import type { DocxPointerHost } from "./document-pointer.js";
import { PointerSelection, type PointerPoint } from "./pointer-selection.js";

/** Four aspect-preserving corners preview in the core and commit only on release. */
export class DocxPictureResize {
  private image: DocxPictures["images"][number] | undefined;
  private revision = -1;
  private readonly buttons: HTMLButtonElement[] = [];
  private readonly pointers: PointerSelection[] = [];
  private origin: PointerPoint = { x: 0, y: 0 };
  private point = this.origin;
  private scale = 1;
  private ending = false;
  constructor(
    viewport: HTMLElement,
    private readonly client: FoundationClient,
    signal: AbortSignal,
    private readonly host: DocxPointerHost,
  ) {
    for (const [i, corner] of [
      "top left",
      "top right",
      "bottom right",
      "bottom left",
    ].entries()) {
      const button = document.createElement("button");
      button.type = "button";
      button.hidden = true;
      button.setAttribute("aria-label", `Resize picture ${corner}`);
      button.setAttribute(
        "aria-keyshortcuts",
        "ArrowLeft ArrowRight ArrowUp ArrowDown Escape",
      );
      Object.assign(button.style, {
        position: "absolute",
        width: "12px",
        height: "12px",
        padding: "0",
        border: "2px solid white",
        background: "#174ca0",
        cursor: i % 2 ? "nesw-resize" : "nwse-resize",
        transform: "translate(-50%, -50%)",
        zIndex: "2",
      });
      viewport.append(button);
      this.buttons.push(button);
      const handle = (i + 1) as 1 | 2 | 3 | 4;
      const pointer = new PointerSelection(
        button,
        viewport,
        signal,
        async (point, initial) => {
          this.point = point;
          if (initial) {
            this.origin = point;
            this.scale = host.current().scale;
            const picture = this.image?.id;
            if (picture === undefined)
              throw new Error("Select a picture before resizing");
            return host.resize(() => ({ action: "begin", picture }));
          }
          const delta = this.delta(point);
          return host.resize(() => ({
            action: "update",
            id: this.identity(),
            handle,
            ...delta,
          }));
        },
        () =>
          host.available() &&
          !this.active &&
          !!this.image &&
          this.revision === host.current().state.revision,
        (cancelled) => {
          this.ending = true;
          const delta = this.delta(this.point);
          return host
            .resize(() =>
              cancelled
                ? { action: "cancel", id: this.identity() }
                : { action: "commit", id: this.identity(), handle, ...delta },
            )
            .finally(() => {
              this.ending = false;
              void host.settle().catch(() => {});
            });
        },
        false,
      );
      this.pointers.push(pointer);
      button.addEventListener(
        "keydown",
        (event) => {
          if (
            !["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(
              event.key,
            ) ||
            !host.available() ||
            this.active ||
            !this.image ||
            this.revision !== host.current().state.revision
          )
            return;
          event.preventDefault();
          const picture = this.image.id,
            step = event.shiftKey ? 10 : 1;
          const dx =
            event.key === "ArrowLeft"
              ? -step
              : event.key === "ArrowRight"
                ? step
                : 0;
          const dy =
            event.key === "ArrowUp"
              ? -step
              : event.key === "ArrowDown"
                ? step
                : 0;
          this.ending = true;
          void host
            .resize(() => ({ action: "begin", picture }))
            .catch(() => {});
          void host
            .resize(() => ({
              action: "commit",
              id: this.identity(),
              handle,
              dx,
              dy,
            }))
            .finally(() => {
              this.ending = false;
              void host.settle().catch(() => {});
            })
            .catch(() => {});
        },
        { signal },
      );
    }
    window.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Escape" && this.pointers.some((p) => p.active)) {
          event.preventDefault();
          this.pointers.forEach((p) => p.finish(true));
        }
      },
      { signal },
    );
    signal.addEventListener(
      "abort",
      () => {
        this.reset();
        this.buttons.forEach((b) => b.remove());
      },
      { once: true },
    );
  }
  get active() {
    return this.ending || this.pointers.some((p) => p.active);
  }
  flush() {
    this.pointers.forEach((p) => p.flush());
  }
  finish() {
    this.pointers.forEach((p) => p.finish());
  }
  reset() {
    this.ending = false;
    this.pointers.forEach((p) => p.cancel());
    this.buttons.forEach((b) => (b.hidden = true));
  }
  private identity(): number {
    const id = this.host.current().state.pictureResizeId;
    if (id === null) throw new Error("Picture resize is no longer active");
    return id;
  }
  private delta(point: PointerPoint) {
    return {
      dx: Math.max(
        -14400,
        Math.min(14400, (point.x - this.origin.x) / this.scale),
      ),
      dy: Math.max(
        -14400,
        Math.min(14400, (point.y - this.origin.y) / this.scale),
      ),
    };
  }
  async refresh(geometry: DocxSelectionGeometry | undefined): Promise<void> {
    const current = this.host.current(),
      selection = current.state.selection;
    if (current.state.pictureResizeId === null && !this.ending) {
      this.image = undefined;
      if (
        selection &&
        selection.anchor.paragraph === selection.focus.paragraph &&
        Math.abs(selection.anchor.offset - selection.focus.offset) === 1 &&
        this.host.available()
      ) {
        const catalog = await this.client.pictures(current.state.revision);
        this.host.assertOpen();
        this.revision = catalog.revision;
        this.image = catalog.images.find(
          (image) => image.selected && !image.reason,
        );
      }
    }
    const rect =
      this.image && geometry?.rects.find((r) => r.page === current.page);
    for (const [i, button] of this.buttons.entries()) {
      button.hidden = !rect || !this.host.available();
      if (rect) {
        button.style.left = `${(rect.x + (i === 1 || i === 2 ? rect.width : 0)) * current.scale}px`;
        button.style.top = `${(rect.y + (i >= 2 ? rect.height : 0)) * current.scale}px`;
      }
    }
  }
}
