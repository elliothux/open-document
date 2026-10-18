import { createPresentationElements } from "./presentation-elements.js";
import { presentationKey } from "./presentation-keyboard.js";
import {
  checkPresentationSearch,
  findPresentation,
  replacePresentationMatches,
  type PresentationSearchResult,
} from "./presentation-search.js";
import type { PptxFindOptions } from "@open-document/wasm/pptx";
export type { PresentationSearchResult } from "./presentation-search.js";
import { updatePresentationObjects } from "./presentation-semantics.js";
import { objectSelection, pointerSelection } from "./presentation-selection.js";
import { PresentationCanvas } from "./presentation-canvas.js";
import { presentationOutputs } from "./presentation-output.js";
import { PresentationInput } from "./presentation-input.js";
import { PresentationPointer } from "./presentation-pointer.js";
import { bindClipboard, copyPptxSelection } from "./clipboard-input.js";
import {
  EditorState,
  type EditorOutput,
  type EditorSnapshot,
} from "./editor-state.js";
import type { PptxClient } from "./pptx.js";
import type {
  PptxQuery,
  PptxLayout,
  PptxGeometry,
  PptxSelection,
  PptxPoint,
  PptxObjectEdit,
  PptxSlideEdit,
} from "@open-document/wasm/pptx";

export class PresentationEditor {
  private readonly container: HTMLDivElement;
  private readonly viewport: HTMLDivElement;
  private readonly holder: HTMLDivElement;
  private readonly input: HTMLTextAreaElement;
  readonly objectList: HTMLOListElement;
  private readonly surface = new PresentationCanvas();
  private readonly listeners = new AbortController();
  private readonly observable: EditorState<PptxQuery>;
  private paused = false;
  private errorMessage = "";
  private cleanup: Promise<void> | undefined;
  private readonly inputEvents: PresentationInput;
  private readonly pointer: PresentationPointer;
  private state: PptxQuery;
  private drawing: PptxLayout | undefined;
  private geometry: PptxGeometry | undefined;
  private zoomValue = 1;
  private scale = 96 / 72;
  private tail: Promise<void> = Promise.resolve();
  private pending = 0;
  private closed = false;
  private closing = false;
  private blocked = false;
  private frame = 0;
  private gesture:
    | {
        start: PptxPoint;
        text: boolean;
        anchor: number;
        handle: number;
        token?: { revision: number; id: number };
      }
    | undefined;

  private constructor(
    private readonly root: HTMLElement,
    private readonly client: PptxClient,
    private readonly profile: Record<string, string>,
    state: PptxQuery,
  ) {
    const elements = createPresentationElements(
      this.surface.canvas,
      this.surface.overlay,
    );
    this.container = elements.container;
    this.viewport = elements.viewport;
    this.holder = elements.holder;
    this.input = elements.input;
    this.objectList = elements.objectList;
    this.state = state;
    this.observable = new EditorState("pptx", {
      revision: state.revision,
      canUndo: state.canUndo,
      canRedo: state.canRedo,
      page: state.slides.findIndex((slide) => slide.id === state.slide),
      pageCount: state.slides.length,
      selection: state.selection.object,
      readOnlyReason: state.readOnlyReason,
      diagnostics: [],
      data: state,
    });
    this.inputEvents = new PresentationInput(
      this.input,
      this.listeners.signal,
      client,
      {
        state: () => this.state,
        limit: () => 32767,
        available: () =>
          this.available &&
          !this.state.readOnlyReason &&
          this.state.selection.mode === "text",
        enqueue: (operation, composition) =>
          this.enqueue(operation, composition),
        changed: (state, relayout) => this.changed(state, relayout),
        history: (redo) => (redo ? this.redo() : this.undo()),
        stop: (error) => this.fail(error),
      },
      () => this.layout.id,
      profile,
    );
    this.input.addEventListener("keydown", this.key, {
      signal: this.listeners.signal,
    });
    bindClipboard(
      this.input,
      this.listeners.signal,
      (cut) => this.handle(() => this.copy(cut)),
      (text) => this.handle(() => this.paste(text)),
      (error) => this.fail(error),
      () => this.inputEvents.active,
    );
    this.pointer = new PresentationPointer(
      this.surface.canvas,
      this.listeners.signal,
      {
        available: () =>
          this.available &&
          !this.state.readOnlyReason &&
          !this.inputEvents.active,
        point: (event) => this.surface.point(event, this.scale),
        press: (point, text, extend) => this.press(point, text, extend),
        move: (point) => this.move(point),
        finish: (point, cancel) => this.release(point, cancel),
        fail: (error) => this.fail(error),
      },
    );
    window.addEventListener(
      "resize",
      () => {
        if (
          this.frame ||
          !this.available ||
          this.pointer.active ||
          this.inputEvents.active
        )
          return;
        this.frame = requestAnimationFrame(() => {
          this.frame = 0;
          this.handle(() => this.enqueue(() => this.paint()));
        });
      },
      { signal: this.listeners.signal },
    );
    this.container.append(this.viewport, this.objectList);
    root.append(this.container);
  }
  static async create(
    root: HTMLElement,
    client: PptxClient,
    profile: Record<string, string>,
    signal?: AbortSignal,
  ): Promise<PresentationEditor> {
    signal?.throwIfAborted();
    const editor = new PresentationEditor(
      root,
      client,
      { ...profile },
      await client.execute({ operation: "queryPptx" }),
    );
    try {
      await editor.present();
      signal?.throwIfAborted();
      return editor;
    } catch (error) {
      await editor.dispose();
      throw error;
    }
  }
  private get available(): boolean {
    return !this.closed && !this.closing && !this.paused && !this.blocked;
  }
  get layout(): PptxLayout {
    if (!this.drawing) throw new Error("Presentation layout is unavailable");
    return this.drawing;
  }
  get query(): PptxQuery {
    return structuredClone(this.state);
  }
  readonly getSnapshot = (): EditorSnapshot<PptxQuery> =>
    this.observable.getSnapshot();
  readonly subscribe = (listener: () => void): (() => void) =>
    this.observable.subscribe(listener);
  markSaved(output: EditorOutput): void {
    this.observable.markSaved(output);
  }
  markDownloaded(output: EditorOutput): void {
    this.observable.markDownloaded(output);
  }
  focus(): void {
    if (this.closed || this.closing) throw new Error("Editor is disposed");
    this.input.focus({ preventScroll: true });
  }
  async setPaused(paused: boolean): Promise<void> {
    if (this.closed || this.closing) throw new Error("Editor is disposed");
    this.paused = paused;
    this.container.inert = paused;
    this.objectList.inert = paused;
    this.input.readOnly = paused || this.blocked;
    this.publish();
    if (paused) await this.tail;
  }
  private publish(): void {
    this.observable.update({
      revision: this.state.revision,
      canUndo: this.state.canUndo,
      canRedo: this.state.canRedo,
      page: this.state.slides.findIndex(
        (slide) => slide.id === this.state.slide,
      ),
      pageCount: this.state.slides.length,
      zoom: this.zoomValue,
      selection: this.state.selection.object,
      composition: this.inputEvents?.active ?? false,
      dragging: !!this.gesture || (this.pointer?.active ?? false),
      busy: this.pending,
      paused: this.paused,
      stopped: this.blocked,
      closed: this.closed,
      error: this.errorMessage,
      readOnlyReason: this.state.readOnlyReason,
      diagnostics: this.drawing?.diagnostics ?? this.state.diagnostics,
      data: this.state,
    });
  }
  private handle(operation: () => Promise<unknown>): void {
    void operation().catch((error) =>
      this.fail(error instanceof Error ? error : new Error(String(error))),
    );
  }
  private fail(error: Error): void {
    if (this.closed) return;
    this.blocked = true;
    this.errorMessage = `${error.message}. Committed edits remain available. Refresh or undo to recover.`;
    this.publish();
  }
  private enqueue<T>(
    operation: () => Promise<T>,
    gesture = false,
    recovery = false,
    output = false,
  ): Promise<T> {
    if (this.closed || this.closing)
      return Promise.reject(new Error("Editor is disposed"));
    if (this.paused && !output)
      return Promise.reject(new Error("Editor input is paused"));
    if (this.blocked && !recovery && !output)
      return Promise.reject(new Error("Refresh or undo before editing"));
    if (
      !gesture &&
      (this.inputEvents.active || this.pointer.active || this.gesture)
    )
      return Promise.reject(
        new Error("Complete or cancel the active gesture first"),
      );
    if (this.pending >= 64)
      return Promise.reject(new Error("Editor queue exceeds budget"));
    this.pending++;
    this.publish();
    const result = this.tail.then(operation);
    this.tail = result.then(
      () => {
        this.pending--;
        if (output && !this.blocked) this.errorMessage = "";
        this.publish();
      },
      (error) => {
        this.pending--;
        if (output && !this.blocked) {
          this.errorMessage =
            error instanceof Error ? error.message : String(error);
          this.publish();
        } else
          this.fail(error instanceof Error ? error : new Error(String(error)));
      },
    );
    return result;
  }
  private async changed(state: PptxQuery, relayout = false): Promise<void> {
    const content =
      relayout ||
      this.state.revision !== state.revision ||
      this.state.slide !== state.slide;
    this.state = state;
    this.publish();
    if (content) await this.present();
    else {
      this.updateSemantics();
      await this.paintSelection();
    }
  }
  private async present(): Promise<void> {
    await this.surface.prepare(this.client);
    const layout = await this.client.execute({
      operation: "layoutPptx",
      profile: this.profile,
    });
    if (
      layout.revision !== this.state.revision ||
      layout.slide !== this.state.slide
    )
      throw new Error("Slide changed while preparing layout");
    this.drawing = layout;
    this.updateSemantics();
    await this.paint();
  }
  private async paint(): Promise<void> {
    this.scale = this.surface.draw(this.layout, 0, this.zoomValue);
    await this.paintSelection();
  }
  private async paintSelection(): Promise<void> {
    const geometry = await this.client.execute({
      operation: "selectionPptx",
      layoutId: this.layout.id,
    });
    this.geometry = geometry;
    this.surface.drawSelection(geometry, this.scale, this.input);
    this.publish();
  }
  private updateSemantics(): void {
    updatePresentationObjects(
      this.objectList,
      this.input,
      this.state,
      this.listeners.signal,
      (object, mode, extend) =>
        this.handle(() => this.select(object, mode, 0, 0, extend)),
    );
    this.publish();
  }
  select(
    object: string,
    mode: "object" | "text" = "object",
    anchor = 0,
    focus = anchor,
    extend = false,
  ): Promise<void> {
    return this.enqueue(() =>
      this.selectNow({
        ...objectSelection(this.state, object, extend && mode === "object"),
        mode,
        anchor,
        focus,
      }),
    );
  }
  selectObjects(
    objects: string[],
    active = objects.at(-1) ?? "",
  ): Promise<void> {
    return this.enqueue(() =>
      this.selectNow({
        ...objectSelection(this.state, active, false),
        objects: [...objects],
      }),
    );
  }
  private async selectNow(selection: PptxSelection): Promise<void> {
    await this.changed(
      await this.client.execute({
        operation: "selectPptx",
        revision: this.state.revision,
        ...selection,
      }),
    );
    this.input.focus({ preventScroll: true });
  }
  showSlide(slide: string): Promise<void> {
    return this.enqueue(async () => {
      await this.cancelNow();
      await this.selectNow({
        ...objectSelection(this.state, "", false),
        slide,
      });
    }, true);
  }
  followHyperlink(): Promise<void> {
    return this.enqueue(async () => {
      await this.changed(
        await this.client.execute({
          operation: "followPptxHyperlink",
          revision: this.state.revision,
        }),
      );
      this.input.focus({ preventScroll: true });
    });
  }
  setZoom(zoom: number): Promise<void> {
    return this.enqueue(async () => {
      if (!Number.isFinite(zoom) || zoom < 0.25 || zoom > 4)
        throw new Error("Invalid zoom");
      this.zoomValue = zoom;
      await this.paint();
    });
  }
  transform(dx: number, dy: number, handle = 0): Promise<void> {
    return this.enqueue(async () => {
      const state = await this.client.execute({
        operation: "beginPptx",
        revision: this.state.revision,
        kind: "transform",
      });
      if (state.candidateId === null)
        throw new Error("Core did not begin move");
      try {
        await this.client.execute({
          operation: "dragPptx",
          revision: state.revision,
          candidateId: state.candidateId,
          dx,
          dy,
          handle,
        });
        await this.changed(
          await this.client.execute({
            operation: "finishPptx",
            revision: state.revision,
            candidateId: state.candidateId,
            profile: this.profile,
          }),
        );
      } catch (error) {
        await this.cancelNow();
        throw error;
      }
    });
  }
  async save(): Promise<EditorOutput> {
    return (await this.outputs("pptx"))[0]!;
  }
  async exportPdf(
    all = true,
    hidden = false,
    outputBytes = 67108864,
  ): Promise<EditorOutput> {
    return (await this.outputs("pdf", outputBytes, 1, all, hidden))[0]!;
  }
  async exportPng(scale = 1, outputBytes = 67108864): Promise<EditorOutput> {
    return (await this.outputs("png", outputBytes, scale))[0]!;
  }
  /** Exports visible slides in order at one revision, with a shared byte budget. */
  exportPageImages(
    scale = 1,
    outputBytes = 67108864,
    hidden = false,
  ): Promise<readonly EditorOutput[]> {
    return this.outputs("images", outputBytes, scale, true, hidden);
  }
  private outputs(
    format: "pptx" | "pdf" | "png" | "images",
    outputBytes = 67108864,
    scale = 1,
    all = true,
    hidden = false,
  ): Promise<readonly EditorOutput[]> {
    return this.enqueue(
      () =>
        presentationOutputs(
          this.client,
          this.surface,
          this.state,
          this.drawing,
          this.profile,
          format,
          all,
          hidden,
          outputBytes,
          scale,
          this.observable,
          () => {
            if (this.closed || this.closing)
              throw new Error("Editor is disposed");
          },
        ),
      false,
      false,
      true,
    );
  }
  private async cancelNow(): Promise<void> {
    this.pointer.reset();
    this.gesture = undefined;
    await this.inputEvents.cancel();
    const state = await this.client.execute({ operation: "queryPptx" });
    this.state =
      state.candidateId === null
        ? state
        : await this.client.execute({
            operation: "cancelPptx",
            revision: state.revision,
            candidateId: state.candidateId,
          });
  }
  undo(): Promise<void> {
    return this.recover(false);
  }
  redo(): Promise<void> {
    return this.recover(true);
  }
  refresh(): Promise<void> {
    return this.recover();
  }
  refreshDateFields(dateTime?: string): Promise<void> {
    return this.enqueue(async () =>
      this.changed(
        await this.client.execute({
          operation: "dateTimePptx",
          revision: this.state.revision,
          ...(dateTime === undefined ? {} : { dateTime }),
          profile: this.profile,
        }),
        true,
      ),
    );
  }
  private recover(redo?: boolean): Promise<void> {
    return this.enqueue(
      async () => {
        await this.cancelNow();
        if (redo !== undefined)
          this.state = await this.client.execute({
            operation: redo ? "redoPptx" : "undoPptx",
            revision: this.state.revision,
          });
        this.blocked = false;
        this.errorMessage = "";
        await this.present();
      },
      true,
      true,
    );
  }
  copy(cut = false): Promise<void> {
    return this.enqueue(async () => {
      const state = await copyPptxSelection(
        this.client,
        this.state,
        cut,
        this.profile,
      );
      if (state) await this.changed(state);
    });
  }
  find(
    text: string,
    options: PptxFindOptions = {},
  ): Promise<PresentationSearchResult> {
    return this.enqueue(() =>
      findPresentation(
        this.client,
        this.state,
        this.getSnapshot().documentId,
        text,
        options,
      ),
    );
  }
  selectMatch(result: PresentationSearchResult, index: number): Promise<void> {
    return this.enqueue(async () => {
      checkPresentationSearch(result, this.getSnapshot(), index);
      const match = result.matches[index]!;
      await this.selectNow({
        slide: match.slide,
        object: match.object,
        objects: [match.object],
        mode: match.reason ? "object" : "text",
        anchor: match.anchor,
        focus: match.focus,
      });
    });
  }
  replaceMatches(
    result: PresentationSearchResult,
    replacement: string,
    index?: number,
  ): Promise<void> {
    return this.enqueue(async () => {
      await this.changed(
        await replacePresentationMatches(
          this.client,
          result,
          this.getSnapshot(),
          this.profile,
          replacement,
          index,
        ),
      );
    });
  }
  editObjects(change: PptxObjectEdit): Promise<void> {
    return this.enqueue(async () =>
      this.changed(
        await this.client.execute({
          operation: "editPptxObjects",
          revision: this.state.revision,
          change,
          profile: this.profile,
        }),
      ),
    );
  }
  editSlides(change: PptxSlideEdit, slide?: string): Promise<void> {
    return this.enqueue(async () =>
      this.changed(
        await this.client.execute({
          operation: "editPptxSlides",
          revision: this.state.revision,
          slide: slide ?? this.state.slide,
          change,
          profile: this.profile,
        }),
      ),
    );
  }
  paste(text: string): Promise<void> {
    return this.enqueue(async () =>
      this.changed(
        await this.client.execute({
          operation: "replacePptx",
          revision: this.state.revision,
          text: text.replace(/\r\n?/g, "\n"),
          profile: this.profile,
        }),
      ),
    );
  }
  private press(
    point: PptxPoint,
    text: boolean,
    extend: boolean,
  ): Promise<void> {
    return this.enqueue(async () => {
      let handle = 0;
      if (this.state.selection.mode === "object")
        for (const [index, position] of (
          this.geometry?.handles ?? []
        ).entries())
          if (
            Math.hypot(point.x - position.x, point.y - position.y) <=
            6 / this.scale
          )
            handle = index + 1;
      const hit = await this.client.execute({
        operation: "hitPptx",
        layoutId: this.layout.id,
        ...point,
        tolerance: 4 / this.scale,
      });
      const selection = pointerSelection(this.state, hit, handle, text, extend);
      await this.selectNow(selection);
      this.gesture = {
        start: point,
        text: selection.mode === "text",
        anchor: selection.anchor,
        handle,
      };
    }, true);
  }
  private move(point: PptxPoint): Promise<void> {
    return this.enqueue(async () => {
      const gesture = this.gesture;
      if (!gesture || !this.state.selection.object) return;
      if (gesture.text) {
        const hit = await this.client.execute({
          operation: "hitPptx",
          layoutId: this.layout.id,
          ...point,
          tolerance: 4 / this.scale,
        });
        if (hit.object === this.state.selection.object)
          await this.selectNow({
            ...this.state.selection,
            anchor: gesture.anchor,
            focus: hit.offset,
          });
      } else {
        const dx = point.x - gesture.start.x,
          dy = point.y - gesture.start.y;
        if (!gesture.token && Math.hypot(dx, dy) < 2 / this.scale) return;
        if (!gesture.token) {
          const state = await this.client.execute({
            operation: "beginPptx",
            revision: this.state.revision,
            kind: "transform",
          });
          if (state.candidateId === null)
            throw new Error("Core did not begin drag");
          gesture.token = { revision: state.revision, id: state.candidateId };
          this.state = state;
        }
        await this.changed(
          await this.client.execute({
            operation: "dragPptx",
            revision: gesture.token.revision,
            candidateId: gesture.token.id,
            dx,
            dy,
            handle: gesture.handle,
          }),
          true,
        );
      }
    }, true);
  }
  private async release(point: PptxPoint, cancel: boolean): Promise<void> {
    if (!cancel) await this.move(point);
    await this.enqueue(async () => {
      const gesture = this.gesture;
      this.gesture = undefined;
      if (gesture?.token)
        await this.changed(
          await this.client.execute({
            revision: gesture.token.revision,
            candidateId: gesture.token.id,
            ...(cancel
              ? { operation: "cancelPptx" as const }
              : { operation: "finishPptx" as const, profile: this.profile }),
          }),
          true,
        );
    }, true);
  }
  private readonly key = (event: KeyboardEvent): void => {
    const action = presentationKey(
      event,
      this,
      this.available,
      () =>
        this.enqueue(
          async () => {
            const wasText = this.state.selection.mode === "text";
            await this.cancelNow();
            if (wasText)
              this.state = await this.client.execute({
                operation: "selectPptx",
                revision: this.state.revision,
                ...this.state.selection,
                mode: "object",
                anchor: 0,
                focus: 0,
              });
            await this.present();
          },
          true,
          true,
        ),
      (backward) =>
        this.enqueue(async () =>
          this.changed(
            await this.client.execute({
              operation: "navigatePptx",
              revision: this.state.revision,
              layoutId: this.layout.id,
              direction: backward ? "previous" : "next",
              extend: false,
            }),
          ),
        ),
    );
    if (action) this.handle(() => action);
  };
  dispose(): Promise<void> {
    if (this.cleanup) return this.cleanup;
    this.closing = true;
    this.listeners.abort();
    cancelAnimationFrame(this.frame);
    this.pointer.reset();
    this.observable.close();
    this.cleanup = (async () => {
      try {
        await this.tail;
        await this.cancelNow();
      } finally {
        this.closed = true;
        this.surface.dispose();
        this.drawing = undefined;
        this.geometry = undefined;
        this.objectList.remove();
        this.container.remove();
      }
    })();
    return this.cleanup;
  }
}
