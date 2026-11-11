import { createDocumentReview } from "./document-review.js";
import { createDocumentSources } from "./document-sources.js";
import { createDocumentPages } from "./document-page.js";
import { createDocumentObjects } from "./document-objects.js";
import { createDocumentClipboard } from "./document-clipboard.js";
import { createDocumentTables } from "./document-tables.js";
import { createDocumentSearch } from "./document-search.js";
import { createDocumentFormatting } from "./document-formatting.js";
import { bindClipboard } from "@open-document/web-core/clipboard";
import { viewOnlyError } from "@open-document/web-core/view-mode";
import { docxOutputs, downloadDocxOutput } from "./document-output.js";

export type * from "./document-types.js";
import { createDocumentElements, docxPageText } from "./document-elements.js";
import type { FoundationClient } from "./foundation.js";
import { PageCanvas } from "./page-canvas.js";
import {
  recoverDocxState,
  cancelDocxDrawingGesture,
} from "./document-recovery.js";
import { revealInput } from "@open-document/web-core/pointer-selection";
import { DocumentPointer } from "./document-pointer.js";
import { TextInput } from "./text-input.js";
import { DocumentError } from "../core/foundation.js";
import { copyDocxSelection, pasteDocxSelection } from "./clipboard-input.js";
import {
  EditorState,
  type EditorOutput,
  type EditorSnapshot,
} from "@open-document/web-core/editor-state";
import type { PageLayout } from "../core/preview.js";
import type { DocxSelectionView } from "../core/docx-hit.js";
import {
  docxSelectionDescription,
  docxSelectionRequest,
  selectFirstDocxPosition,
  docxInputReadOnly,
} from "./document-selection.js";
import type {
  DocxSelection,
  EditState,
  DocxSelectionGeometry,
} from "../core/foundation.js";
import { CommandQueue } from "@open-document/web-core/command-queue";

export class DocumentEditor {
  readonly review: ReturnType<typeof createDocumentReview>;
  readonly sources: ReturnType<typeof createDocumentSources>;
  readonly pages: ReturnType<typeof createDocumentPages>;
  readonly objects: ReturnType<typeof createDocumentObjects>;
  readonly clipboard: ReturnType<typeof createDocumentClipboard>;
  readonly tables: ReturnType<typeof createDocumentTables>;
  readonly search: ReturnType<typeof createDocumentSearch>;
  readonly formatting: ReturnType<typeof createDocumentFormatting>;
  private readonly container: HTMLDivElement;
  private readonly viewport: HTMLDivElement;
  private readonly input: HTMLTextAreaElement;
  private readonly text: HTMLPreElement;
  private readonly observable: EditorState<EditState>;
  private paused = false;
  private readonly listeners = new AbortController();
  private readonly queue = new CommandQueue(64, () => {
    const error = new Error("Input queue is full");
    this.stop(error);
    return error;
  });
  private blocked: Error | undefined;
  private outputError = "";
  private closed = false;
  private resuming = false;
  private page = 0;
  private zoom = 1;
  private shownRevision: string | undefined;
  private cssScale = 96 / 72;
  private readonly inputEvents: TextInput;
  private cleanup: Promise<void> | undefined;
  private readonly pointerSelection: DocumentPointer;
  private selectionDescription = "Focus document text input to start editing";
  readonly inputLimits: ReturnType<FoundationClient["inputLimits"]>;
  private constructor(
    private readonly root: HTMLElement,
    private readonly client: FoundationClient,
    private readonly profile: Record<string, string>,
    private readonly surface: PageCanvas,
    private currentLayout: PageLayout,
    private state: EditState,
  ) {
    this.inputLimits = client.inputLimits();
    const host = {
      state: () => this.state,
      selection: () => this.selection(),
      endGroup: () => this.inputEvents.endGroup(),
      read: <T>(operation: () => Promise<T>) => this.enqueue(operation),
      edit: (operation: () => Promise<EditState>) => this.format(operation),
      changed: (state: EditState) => this.changed(state),
      snapshot: () => this.getSnapshot(),
      layout: () => this.currentLayout,
      shownRevision: () => this.shownRevision,
      showRevisionGeometry: (id: string, geometry: DocxSelectionGeometry) =>
        this.showRevisionGeometry(id, geometry),
      paste: (text: string) => this.paste(text),
    };
    this.formatting = createDocumentFormatting(client, profile, host);
    this.review = createDocumentReview(client, host);
    this.sources = createDocumentSources(client, profile, host);
    this.pages = createDocumentPages(client, profile, host);
    this.objects = createDocumentObjects(client, profile, host);
    this.clipboard = createDocumentClipboard(client, profile, host);
    this.tables = createDocumentTables(client, profile, host);
    this.search = createDocumentSearch(client, host);
    const elements = createDocumentElements(
      surface.canvas,
      surface.overlay,
      this.selectionDescription,
    );
    this.container = elements.container;
    this.viewport = elements.viewport;
    this.input = elements.input;
    this.text = elements.text;
    this.observable = new EditorState("docx", {
      revision: state.revision,
      canUndo: state.canUndo,
      canRedo: state.canRedo,
      readOnlyReason: state.readOnlyReason ?? "",
      pageCount: currentLayout.regions.length,
      selection: this.selectionDescription,
      diagnostics: currentLayout.diagnostics,
      data: state,
    });
    const options = { signal: this.listeners.signal };
    window.addEventListener(
      "resize",
      () => {
        if (!this.closed && !this.paused && !this.blocked && !this.resuming)
          this.handle(() => this.presentSelection());
      },
      options,
    );
    this.pointerSelection = new DocumentPointer(
      this.surface,
      this.viewport,
      this.client,
      this.listeners.signal,
      {
        assertOpen: () => this.assertOpen(),
        ink: () => ({
          options: this.objects.inkOptions,
          profile: this.profile,
        }),
        available: () =>
          !this.closed &&
          !this.paused &&
          !this.blocked &&
          !this.resuming &&
          !this.inputEvents.active,
        current: () => ({
          state: this.state,
          layout: this.currentLayout,
          page: this.page,
          scale: this.cssScale,
        }),
        run: (operation) => this.enqueue(operation, true),
        input: () => {
          this.inputEvents.endGroup();
          this.input.focus({ preventScroll: true });
        },
        selected: (state) => this.changed(state, false, false),
        paint: (page) => {
          this.page = page;
          this.paint();
        },
        settle: () => this.enqueue(() => this.presentSelection(), true),
        openComment: (id) => this.review.editComment({ action: "goTo", id }),
        gesture: (change) => {
          this.inputEvents.endGroup();
          return this.enqueue(async () => {
            const state = await this.client.execute({
              operation: "drawingGesture",
              revision: this.state.revision,
              change: change(),
              profile: this.profile,
            });
            await this.changed(state, true, false);
          }, true);
        },
      },
    );
    bindClipboard(
      this.input,
      this.listeners.signal,
      (cut) => {
        if (!cut || !client.readOnly) void this.copy(cut).catch(() => {});
      },
      (text) => {
        if (!client.readOnly) void this.paste(text).catch(() => {});
      },
      (error) => this.stop(error),
      () => this.inputEvents.active,
      () => false,
      () =>
        void pasteDocxSelection(this).catch((error: unknown) => {
          this.observable.update({
            error: error instanceof Error ? error.message : String(error),
          });
        }),
    );
    this.input.addEventListener(
      "blur",
      () => {
        this.inputEvents.endGroup();
        this.pointerSelection.finishText();
      },
      options,
    );
    this.input.addEventListener(
      "focus",
      () => {
        if (
          this.state.selection ||
          this.blocked ||
          this.resuming ||
          this.pointerSelection.active
        )
          return;
        this.handle(async () => {
          if (this.state.selection) return;
          this.state = await selectFirstDocxPosition(
            this.client,
            this.state,
            this.currentLayout,
            this.page,
          );
          await this.presentSelection();
        });
      },
      options,
    );
    this.inputEvents = new TextInput(
      this.input,
      this.listeners.signal,
      this.client,
      {
        state: () => this.state,
        layoutId: () => this.currentLayout.id,
        available: () =>
          !this.closed && !this.paused && !this.blocked && !this.resuming,
        enqueue: (operation, composition) =>
          this.enqueue(operation, false, composition),
        changed: this.changed.bind(this),
        history: (redo) => this.history(redo),
        stop: (error) => this.stop(error),
      },
    );
    this.paint();
    root.append(this.container);
  }
  static async create(
    root: HTMLElement,
    client: FoundationClient,
    profile: Record<string, string>,
    signal?: AbortSignal,
  ): Promise<DocumentEditor> {
    const surface = await PageCanvas.create(client, signal);
    let editor: DocumentEditor | undefined;
    try {
      const layout = await surface.layout(profile);
      const state = await client.execute({ operation: "editState" });
      if (state.selection)
        await client.execute({
          operation: "selectDocx",
          revision: state.revision,
          selection: state.selection,
        });
      signal?.throwIfAborted();
      editor = new DocumentEditor(
        root,
        client,
        { ...profile },
        surface,
        layout,
        state,
      );
      if (state.selection) await editor.presentSelection();
      signal?.throwIfAborted();
      return editor;
    } catch (error) {
      if (editor) await editor.dispose();
      else surface.dispose();
      throw error;
    }
  }
  get layout(): PageLayout {
    return this.currentLayout;
  }
  get pictureSelected(): boolean {
    return this.pointerSelection.pictureSelected;
  }
  readonly getSnapshot = (): EditorSnapshot<EditState> =>
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
    this.assertOpen();
    this.input.focus({ preventScroll: true });
  }
  setReadOnly(readOnly: boolean): void {
    if (readOnly === this.client.readOnly) return;
    this.client.readOnly = readOnly;
    this.paint();
  }
  async setPaused(paused: boolean): Promise<void> {
    this.assertOpen();
    if (paused) this.pointerSelection.finish();
    this.paused = paused;
    this.container.inert = paused;
    this.input.readOnly =
      this.client.readOnly ||
      paused ||
      !!this.blocked ||
      this.resuming ||
      docxInputReadOnly(this.state, this.currentLayout);
    this.publish();
    if (paused) await this.queue.whenIdle();
    else await this.enqueue(() => this.presentSelection(false), true);
  }
  undo(): Promise<void> {
    return this.history(false);
  }
  redo(): Promise<void> {
    return this.history(true);
  }
  goToPage(index: number): Promise<void> {
    return this.enqueue(() => this.showPage(index));
  }
  copy(cut = false, mode?: "cells"): Promise<void> {
    if (cut && this.client.readOnly) return Promise.reject(viewOnlyError());
    return this.enqueue(async () => {
      const state = await copyDocxSelection(
        this.client,
        this.state,
        cut,
        () => this.assertOpen(),
        mode,
      );
      if (state) await this.changed(state);
    });
  }
  private assertOpen(): void {
    if (this.closed) throw new Error("Editor is disposed");
  }
  private stop(error: Error, cancelQueued = false): void {
    if (this.closed) return;
    this.pointerSelection.cancel();
    this.blocked = error;
    this.inputEvents.endGroup();
    if (cancelQueued) this.queue.invalidate();
    this.input.value = "";
    this.input.readOnly = true;
    this.selectionDescription =
      "Selection unavailable while editing is stopped";
    this.input.setAttribute("aria-description", this.selectionDescription);
    this.publish();
  }
  private enqueue<T>(
    operation: () => Promise<T>,
    pointer = false,
    composition = false,
    output: false | EditorOutput["format"] | "images" = false,
  ): Promise<T> {
    if (!pointer) this.pointerSelection.finish();
    try {
      this.assertOpen();
      if (this.paused && !output) throw new Error("Editor input is paused");
      if (this.blocked && !output) throw this.blocked;
      if (this.resuming) throw new Error("Wait for editing to resume");
      if (!composition && this.inputEvents.active) {
        throw new DocumentError(
          "busy",
          "Complete or cancel composition before this operation",
          "",
          -1,
        );
      }
    } catch (error) {
      return Promise.reject(error);
    }
    const generation = this.queue.generation;
    return this.queue.enqueue(
      async () => {
        this.assertOpen();
        if (generation !== this.queue.generation)
          throw new Error("Queued input was cancelled");
        try {
          const value = await operation();
          this.assertOpen();
          if (generation !== this.queue.generation)
            throw new Error(
              "Input was interrupted; reload the current document",
            );
          if (!this.blocked) this.outputError = "";
          return value;
        } catch (error) {
          if (
            output &&
            output !== "pdf" &&
            output !== "docx" &&
            !this.blocked
          ) {
            this.outputError =
              error instanceof Error ? error.message : String(error);
            throw error;
          }
          if (
            error instanceof DocumentError &&
            [
              "busy",
              "read-only-view",
              "target-changed",
              "stale-search",
              "stale-overview",
              "stale-toc",
              "stale-index",
              "stale-sources",
            ].includes(error.code)
          ) {
            this.observable.update({ error: error.message });
          } else if (generation === this.queue.generation)
            this.stop(
              error instanceof Error ? error : new Error(String(error)),
              true,
            );
          throw error;
        }
      },
      () => this.publish(),
      () => this.publish(),
    );
  }
  private handle(operation: () => Promise<void>): void {
    this.inputEvents.endGroup();
    void this.enqueue(operation).catch(() => {});
  }
  private history(redo: boolean): Promise<void> {
    if (this.client.readOnly) return Promise.reject(viewOnlyError());
    this.inputEvents.endGroup();
    if (this.blocked && !redo) return this.recover(true);
    return this.enqueue(async () =>
      this.changed(
        await (redo
          ? this.client.execute({
              operation: "redoDocx",
              revision: this.state.revision,
            })
          : this.client.execute({
              operation: "undoDocx",
              revision: this.state.revision,
            })),
      ),
    );
  }

  async whenIdle(): Promise<void> {
    this.pointerSelection.flush();
    await this.queue.whenIdle();
    this.assertOpen();
    if (this.blocked) throw this.blocked;
  }

  /** Cancels old intents and reloads core state after an input error or external conflict. */
  async resume(): Promise<void> {
    return this.recover(false);
  }
  private async recover(undo: boolean): Promise<void> {
    this.assertOpen();
    if (!this.blocked || this.resuming)
      throw new Error("Resume is only available after editing stops");
    this.resuming = true;
    this.publish();
    return this.queue.barrier(async () => {
      try {
        this.assertOpen();
        await this.inputEvents.cancel();
        this.assertOpen();
        this.state = await recoverDocxState(
          this.client,
          this.state.revision,
          undo,
          () => this.assertOpen(),
        );
        this.currentLayout = await this.surface.layout(this.profile);
        this.assertOpen();
        this.blocked = undefined;
        await this.presentSelection();
      } catch (error) {
        this.stop(
          error instanceof Error ? error : new Error(String(error)),
          true,
        );
        throw error;
      } finally {
        this.resuming = false;
        this.input.readOnly =
          this.client.readOnly ||
          this.closed ||
          !!this.blocked ||
          docxInputReadOnly(this.state, this.currentLayout);
        this.publish();
      }
    });
  }
  private selection(): DocxSelection {
    const selection = this.state.selection;
    if (!selection) throw new Error("Click a document position first");
    return selection;
  }
  private format(operation: () => Promise<EditState>): Promise<void> {
    if (this.client.readOnly) return Promise.reject(viewOnlyError());
    this.inputEvents.endGroup();
    return this.enqueue(async () => {
      await this.changed(await operation());
      if (this.state.selection) this.focus();
    });
  }
  private async changed(
    state: EditState & { selectionView?: DocxSelectionView },
    relayout = false,
    reveal = true,
  ): Promise<void> {
    this.assertOpen();
    const revision = this.state.revision;
    const { selectionView, ...next } = state;
    this.state = next;
    this.publish();
    let view = selectionView;
    if (relayout || state.revision !== revision) {
      const { selectionView, ...layout } = await this.surface.layout(
        this.profile,
        docxSelectionRequest(next),
      );
      this.currentLayout = layout;
      view = selectionView;
    }
    this.assertOpen();
    await this.presentSelection(reveal, view);
  }
  paste(text: string): Promise<void> {
    if (this.client.readOnly) return Promise.reject(viewOnlyError());
    this.inputEvents.endGroup();
    if (text.length > this.state.commandLimit) {
      const error = new Error("Paste exceeds command budget");
      this.stop(error);
      return Promise.reject(error);
    }
    const normalized = text.replace(/\r\n?/g, "\n");
    return this.enqueue(async () => {
      if (normalized.length === 0) return;
      await this.changed(
        await this.client.execute({
          operation: "replaceRange",
          revision: this.state.revision,
          selection: this.selection(),
          text: normalized,
        }),
      );
    });
  }
  private async presentSelection(
    reveal = true,
    view?: DocxSelectionView,
  ): Promise<void> {
    this.assertOpen();
    const layoutId = this.currentLayout.id;
    const request = docxSelectionRequest(this.state);
    if (!view && request)
      view = await this.client.execute({
        operation: "docxSelectionView",
        layoutId,
        ...request,
      });
    this.assertOpen();
    if (
      this.currentLayout.id !== layoutId ||
      (view &&
        (view.layoutId !== layoutId ||
          view.revision !== this.currentLayout.revision))
    )
      throw new Error("Selection geometry belongs to a stale layout");
    if (view?.formatting)
      this.state = { ...this.state, formatting: view.formatting };
    const caret = view?.caret,
      geometry = view?.geometry;
    if (caret && reveal) this.page = caret.page;
    const description = docxSelectionDescription(
      this.state,
      this.page,
      !!this.blocked,
      view,
    );
    this.assertOpen();
    this.selectionDescription = description;
    this.input.setAttribute("aria-description", description);
    this.paint();
    this.surface.drawSelection(this.page, this.cssScale, geometry, caret);
    await this.pointerSelection.refresh(geometry);
    if (caret) {
      this.input.style.left = `${caret.x * this.cssScale}px`;
      this.input.style.top = `${caret.y * this.cssScale}px`;
      this.input.style.height = `${caret.height * this.cssScale}px`;
      if (reveal) revealInput(this.input, this.viewport);
    }
  }
  private paint(): void {
    this.shownRevision = undefined;
    this.page = Math.min(this.page, this.currentLayout.regions.length - 1);
    this.cssScale = this.surface.draw(this.currentLayout, this.page, this.zoom);
    this.surface.setComments(
      this.currentLayout.comments,
      this.page,
      this.cssScale,
    );
    // Focus and pointer selection run before text intents in the same queue.
    this.input.readOnly =
      this.client.readOnly ||
      this.paused ||
      !!this.blocked ||
      this.resuming ||
      docxInputReadOnly(this.state, this.currentLayout);
    this.text.textContent = docxPageText(this.currentLayout, this.page);
    this.publish();
  }
  private publish(): void {
    this.observable.update({
      revision: this.state.revision,
      canUndo: this.state.canUndo,
      canRedo: this.state.canRedo,
      page: this.page,
      pageCount: this.currentLayout.regions.length,
      zoom: this.zoom,
      selection: this.selectionDescription,
      composition: this.inputEvents?.active ?? false,
      dragging: this.pointerSelection?.active ?? false,
      busy: this.queue.pending,
      paused: this.paused,
      stopped: !!this.blocked || this.resuming,
      closed: this.closed,
      error: this.blocked?.message ?? this.outputError,
      diagnostics: this.currentLayout.diagnostics,
      data: this.state,
    });
  }
  private async showPage(index: number): Promise<void> {
    this.page = Math.max(
      0,
      Math.min(this.currentLayout.regions.length - 1, index),
    );
    this.paint();
    this.surface.clearOverlay(this.cssScale);
    await this.pointerSelection.refresh(undefined);
  }
  setZoom(zoom: number): Promise<void> {
    return this.enqueue(async () => {
      if (!Number.isFinite(zoom) || zoom < 0.25 || zoom > 4)
        throw new Error("Invalid zoom");
      const previousZoom = this.zoom;
      const previousPage = this.page;
      this.zoom = zoom;
      try {
        await this.presentSelection();
      } catch (error) {
        this.zoom = previousZoom;
        this.page = previousPage;
        throw error;
      }
    });
  }
  async downloadPdf(
    filename = "document.pdf",
    outputBytes?: number,
  ): Promise<void> {
    this.downloadOutput(await this.exportPdf(outputBytes), filename);
  }
  async downloadDocx(filename = "document.docx"): Promise<void> {
    this.downloadOutput(await this.saveDocx(), filename);
  }
  /** A barrier: later input cannot change the returned revision or bytes. */
  async saveDocx(): Promise<EditorOutput> {
    return (await this.outputs("docx"))[0]!;
  }
  async exportPdf(outputBytes?: number): Promise<EditorOutput> {
    return (await this.outputs("pdf", outputBytes))[0]!;
  }
  async exportHtml(outputBytes?: number): Promise<EditorOutput> {
    return (await this.outputs("html", outputBytes))[0]!;
  }
  async exportMarkdown(outputBytes?: number): Promise<EditorOutput> {
    return (await this.outputs("markdown", outputBytes))[0]!;
  }
  /** Exports the current page at pixels per point, independent of preview zoom and DPR. */
  async exportPng(scale = 1, outputBytes?: number): Promise<EditorOutput> {
    return (await this.outputs("png", outputBytes, scale))[0]!;
  }
  /** Exports all pages in order at one revision, with a shared byte budget. */
  exportPageImages(
    scale = 1,
    outputBytes?: number,
  ): Promise<readonly EditorOutput[]> {
    return this.outputs("images", outputBytes, scale);
  }
  private outputs(
    format: "docx" | "pdf" | "png" | "images" | "html" | "markdown",
    outputBytes = this.inputLimits.exportBytes,
    scale = 1,
  ): Promise<readonly EditorOutput[]> {
    this.inputEvents.endGroup();
    return this.enqueue(
      async () => {
        const outputs = await docxOutputs(
          this.client,
          this.state.revision,
          this.currentLayout,
          this.surface,
          this.page,
          format,
          outputBytes,
          scale,
          this.observable,
          () => this.assertOpen(),
        );
        this.publish();
        return outputs;
      },
      false,
      false,
      format,
    );
  }
  private async showRevisionGeometry(
    id: string,
    geometry: DocxSelectionGeometry,
  ): Promise<void> {
    await this.showPage(geometry.rects[0]!.page);
    this.surface.drawRevision(
      geometry,
      this.page,
      this.cssScale,
      this.viewport,
    );
    this.shownRevision = id;
  }
  private downloadOutput(output: EditorOutput, filename: string): void {
    this.assertOpen();
    downloadDocxOutput(output, filename, this.observable, !this.blocked);
  }
  /** Stop input; await accepted work and cancellation before closing the caller's client. */
  dispose(): Promise<void> {
    if (this.cleanup) return this.cleanup;
    this.closed = true;
    this.queue.invalidate();
    this.listeners.abort();
    this.selectionDescription = "";
    this.input.removeAttribute("aria-description");
    this.observable.close();
    this.container.remove();
    this.cleanup = this.queue
      .whenIdle()
      .then(async () => {
        await this.inputEvents.cancel();
        await cancelDocxDrawingGesture(this.client);
      })
      .finally(() => {
        this.surface.dispose();
      });
    return this.cleanup;
  }
}
