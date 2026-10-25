import type { DocxInkStroke } from "@open-document/wasm/foundation";
import type { FoundationClient } from "./foundation.js";
import type { PageCanvas } from "./page-canvas.js";
import type { DocxPointerHost } from "./document-pointer.js";
import {
  PointerSelection,
  clampPointerPoint,
  type PointerPoint,
} from "./pointer-selection.js";

interface Draft {
  revision: number;
  layoutId: number;
  page: number;
  scale: number;
  stroke: DocxInkStroke;
}

/** Pointer samples and transient overlays only; the core owns saved ink geometry. */
export class DocumentInkGesture {
  private readonly pointer: PointerSelection;
  private draft: Draft | undefined;
  private ending = false;

  constructor(
    private readonly surface: PageCanvas,
    viewport: HTMLElement,
    private readonly client: FoundationClient,
    signal: AbortSignal,
    private readonly host: DocxPointerHost,
  ) {
    this.pointer = new PointerSelection(
      surface.canvas,
      viewport,
      signal,
      (point, initial) => this.sample(point, initial),
      () =>
        host.available() &&
        host.ink().options.tool !== "select" &&
        !this.ending,
      (cancelled) => this.end(cancelled),
      false,
    );
    window.addEventListener(
      "keydown",
      (event) => {
        if (event.key !== "Escape" || !this.pointer.active) return;
        event.preventDefault();
        event.stopImmediatePropagation();
        this.pointer.finish(true);
      },
      { capture: true, signal },
    );
  }

  get active(): boolean {
    return this.pointer.active || this.ending;
  }
  flush(): void {
    this.pointer.flush();
  }
  finish(): void {
    this.pointer.finish();
  }
  cancel(): void {
    this.pointer.cancel();
    this.draft = undefined;
    this.surface.clearOverlay(this.host.current().scale);
  }

  private sample(point: PointerPoint, initial: boolean): Promise<void> {
    const current = this.host.current();
    const options = this.host.ink().options;
    if (initial) {
      this.host.input();
      this.draft =
        options.tool === "eraser"
          ? undefined
          : {
              revision: current.state.revision,
              layoutId: current.layout.id,
              page: current.page,
              scale: current.scale,
              stroke: {
                points: [],
                color: options.color,
                width: options.width,
                highlighter: options.tool === "highlighter",
              },
            };
    }
    const region = current.layout.regions[current.page];
    if (!region) return Promise.resolve();
    const local = clampPointerPoint(
      point,
      this.surface.canvas.getBoundingClientRect(),
      current.scale,
      region,
    );
    if (options.tool === "eraser")
      return this.host.run(async () => {
        const latest = this.host.current();
        const state = await this.client.eraseInk(
          latest.state.revision,
          latest.layout.id,
          latest.page,
          local.x,
          local.y,
        );
        if (state.revision !== latest.state.revision)
          await this.host.selected(state);
      });
    const draft = this.draft;
    if (
      !draft ||
      draft.page !== current.page ||
      draft.layoutId !== current.layout.id
    )
      return Promise.resolve();
    const previous = draft.stroke.points.at(-1);
    if (!previous || previous[0] !== local.x || previous[1] !== local.y) {
      if (draft.stroke.points.length === 4096) {
        this.pointer.finish();
        return Promise.resolve();
      }
      draft.stroke.points.push([local.x, local.y]);
    }
    const stroke = { ...draft.stroke, points: draft.stroke.points.slice() };
    return this.host.run(async () => {
      if (this.draft !== draft) return;
      const batch = await this.client.previewInk(
        draft.revision,
        draft.layoutId,
        draft.page,
        stroke,
      );
      if (this.draft === draft) this.surface.drawOverlay(batch, draft.scale);
    });
  }

  private async end(cancelled: boolean): Promise<void> {
    const draft = this.draft;
    this.draft = undefined;
    this.ending = true;
    try {
      if (!cancelled && draft) {
        await this.host.run(async () => {
          const current = this.host.current();
          if (
            current.page !== draft.page ||
            current.layout.id !== draft.layoutId
          )
            return;
          const state = await this.client.insertInk(
            draft.revision,
            draft.layoutId,
            draft.page,
            draft.stroke,
            this.host.ink().profile,
          );
          await this.host.selected(state);
        });
      }
    } finally {
      this.ending = false;
      this.surface.clearOverlay(this.host.current().scale);
      await this.host.settle();
    }
  }
}
