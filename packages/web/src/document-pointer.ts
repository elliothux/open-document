import type { FoundationClient } from "./foundation.js";
import type { PageLayout } from "@open-document/wasm/preview";
import type {
  EditState,
  DocxSelectionGeometry,
  DocxPictureGestureCommand,
} from "@open-document/wasm/foundation";
import {
  PointerSelection,
  clampPointerPoint,
  scrollPointerViewport,
  type PointerPoint,
} from "./pointer-selection.js";
import { pointerDocxSelection } from "./document-selection.js";
import { DocxPictureGesture } from "./document-picture-gesture.js";

export interface DocxPointerHost {
  assertOpen(): void;
  available(): boolean;
  current(): {
    state: EditState;
    layout: PageLayout;
    page: number;
    scale: number;
  };
  run<T>(operation: () => Promise<T>): Promise<T>;
  input(): void;
  selected(state: EditState): Promise<void>;
  paint(page: number): void;
  settle(): Promise<void>;
  openComment(id: string): Promise<void>;
  gesture(change: () => DocxPictureGestureCommand): Promise<void>;
}

/** Owns document pointer gestures; all document candidates and geometry stay in the core. */
export class DocumentPointer {
  private readonly text: PointerSelection;
  private readonly picture: DocxPictureGesture;
  private pageTime = 0;
  private pendingComment: string | undefined;
  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly viewport: HTMLElement,
    client: FoundationClient,
    signal: AbortSignal,
    private readonly host: DocxPointerHost,
  ) {
    this.picture = new DocxPictureGesture(
      canvas,
      viewport,
      client,
      signal,
      host,
    );
    this.text = new PointerSelection(
      canvas,
      viewport,
      signal,
      (point, initial, extend, elapsed) =>
        this.select(client, point, initial, extend, elapsed),
      () => host.available() && !this.picture.active,
      (cancelled) => {
        const id = cancelled ? undefined : this.pendingComment;
        this.pendingComment = undefined;
        return id === undefined ? host.settle() : host.openComment(id);
      },
    );
  }
  get active() {
    return this.text.active || this.picture.active;
  }
  flush() {
    this.text.flush();
    this.picture.flush();
  }
  finish() {
    this.text.finish();
    this.picture.finish();
  }
  finishText() {
    this.text.finish();
  }
  cancel() {
    this.pendingComment = undefined;
    this.text.cancel();
    this.picture.reset();
  }
  refresh(geometry: DocxSelectionGeometry | undefined) {
    return this.picture.refresh(geometry);
  }

  private select(
    client: FoundationClient,
    point: PointerPoint,
    initial: boolean,
    extend: boolean,
    elapsed: number,
  ): Promise<void> {
    const start = this.host.current(),
      rect = this.canvas.getBoundingClientRect();
    const x = (point.x - rect.left) / start.scale,
      y = (point.y - rect.top) / start.scale;
    this.pendingComment =
      initial && !extend
        ? start.layout.comments.items.find((item) =>
            item.rects.some(
              (rect) =>
                rect.page === start.page &&
                x >= rect.x - 1.5 &&
                x <= rect.x + rect.width + 1.5 &&
                y >= rect.y &&
                y <= rect.y + rect.height,
            ),
          )?.id
        : undefined;
    if (initial) {
      this.pageTime = performance.now();
      this.host.input();
    }
    return this.host.run(async () => {
      if (!initial && elapsed) {
        const current = this.host.current();
        const direction = scrollPointerViewport(
            this.viewport,
            point,
            elapsed,
            this.pageTime,
          ),
          next = current.page + direction;
        if (direction && next >= 0 && next < current.layout.regions.length) {
          this.host.paint(next);
          this.viewport.scrollTop =
            direction < 0
              ? this.viewport.scrollHeight - this.viewport.clientHeight
              : 0;
          this.pageTime = performance.now();
        }
      }
      const current = this.host.current(),
        frame = current.layout.regions[current.page];
      if (!frame) throw new Error("Unknown page");
      if (
        !initial &&
        current.layout.semantics[current.page]?.lines.length === 0
      )
        return;
      const clamped = clampPointerPoint(
        point,
        this.canvas.getBoundingClientRect(),
        current.scale,
        frame,
      );
      const hit = await client.hitTest(
        initial ? start.layout.id : current.layout.id,
        initial ? start.page : current.page,
        initial ? x : clamped.x,
        initial ? y : clamped.y,
      );
      this.host.assertOpen();
      const state = await client.selectDocx(
        current.state.revision,
        pointerDocxSelection(hit, current.state, initial, extend),
      );
      await this.host.selected(state);
    });
  }
}
