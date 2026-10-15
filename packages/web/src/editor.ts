import { downloadBytes } from "./download.js";
import { createDocumentElements } from "./document-elements.js";
import type { FoundationClient } from "./foundation.js";
import { PageCanvas } from "./page-canvas.js";
import {
  PointerSelection,
  revealInput,
  type PointerPoint,
} from "./pointer-selection.js";
import { TextInput } from "./text-input.js";
import { DocumentError, DOCX_SOFT_BREAK } from "@open-document/wasm/foundation";
import { bindClipboard } from "./clipboard-input.js";
import {
  EditorState,
  type EditorOutput,
  type EditorSnapshot,
} from "./editor-state.js";
import type { PageLayout } from "@open-document/wasm/preview";
import {
  docxSelectionDescription,
  sameDocxSelection,
  searchSelections,
  type DocumentSearchResult,
} from "./document-selection.js";
export type { DocumentSearchResult } from "./document-selection.js";
import type {
  DocxSelection,
  EditState,
  CharacterFormatPatch,
  ParagraphFormatPatch,
  DocxFindOptions,
} from "@open-document/wasm/foundation";

/** Owns browser input order. The caller owns fonts, the opened DOCX and client lifetime. */
export class DocumentEditor {
  private readonly container: HTMLDivElement;
  private readonly viewport: HTMLDivElement;
  private readonly input: HTMLTextAreaElement;
  private readonly text: HTMLPreElement;
  private readonly observable: EditorState<EditState>;
  private paused = false;
  private readonly listeners = new AbortController();
  private tail: Promise<void> = Promise.resolve();
  private pending = 0;
  private generation = 0;
  private blocked: Error | undefined;
  private closed = false;
  private resuming = false;
  private page = 0;
  private zoom = 1;
  private cssScale = 96 / 72;
  private readonly inputEvents: TextInput;
  private cleanup: Promise<void> | undefined;
  private readonly pointerSelection: PointerSelection;
  private pointerPageTime = 0;
  private selectionDescription = "Focus document text input to start editing";

  private constructor(
    private readonly root: HTMLElement,
    private readonly client: FoundationClient,
    private readonly profile: Record<string, string>,
    private readonly surface: PageCanvas,
    private currentLayout: PageLayout,
    private state: EditState,
  ) {
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
    this.pointerSelection = new PointerSelection(
      this.surface.canvas,
      this.viewport,
      this.listeners.signal,
      (point, initial, extend, elapsed) =>
        this.selectPointer(point, initial, extend, elapsed),
      () =>
        !this.closed &&
        !this.paused &&
        !this.blocked &&
        !this.resuming &&
        !this.inputEvents.active,
      () => this.enqueue(() => this.presentSelection(), true),
    );
    bindClipboard(
      this.input,
      this.listeners.signal,
      (cut) => this.handle(() => this.copySelection(cut)),
      (text) => {
        void this.paste(text).catch(() => {});
      },
      (error) => this.stop(error),
      () => this.inputEvents.active,
    );

    this.input.addEventListener(
      "blur",
      () => {
        this.inputEvents.endGroup();
        this.pointerSelection.finish();
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
          const line = this.currentLayout.semantics[this.page]?.lines.find(
            (line) => !line.readOnlyReason,
          );
          if (!line) throw new Error("This page has no editable text position");
          const position = {
            paragraph: line.paragraph,
            offset: line.start,
            affinity: "after" as const,
          };
          this.state = await this.client.selectDocx(this.state.revision, {
            anchor: position,
            focus: position,
          });
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
        changed: (state, relayout) => this.changed(state, relayout),
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
      const layout = await client.layout(profile);
      const state = await client.editState();
      if (state.selection)
        await client.selectDocx(state.revision, state.selection);
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
  async setPaused(paused: boolean): Promise<void> {
    this.assertOpen();
    this.paused = paused;
    this.container.inert = paused;
    if (paused) this.pointerSelection.finish();
    this.input.readOnly = paused || !!this.blocked || this.resuming;
    this.publish();
    if (paused) await this.tail;
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
  copy(cut = false): Promise<void> {
    return this.enqueue(() => this.copySelection(cut));
  }
  private assertOpen(): void {
    if (this.closed) throw new Error("Editor is disposed");
  }
  private stop(error: Error, cancelQueued = false): void {
    if (this.closed) return;
    this.pointerSelection.cancel();
    this.blocked = error;
    this.inputEvents.endGroup();
    if (cancelQueued) this.generation++;
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
    output = false,
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
      if (this.pending >= 64) {
        this.stop(new Error("Input queue is full"));
        throw this.blocked;
      }
    } catch (error) {
      return Promise.reject(error);
    }
    const generation = this.generation;
    this.pending++;
    this.publish();
    const result = this.tail.then(async () => {
      this.assertOpen();
      if (generation !== this.generation)
        throw new Error("Queued input was cancelled");
      try {
        const value = await operation();
        this.assertOpen();
        if (generation !== this.generation)
          throw new Error("Input was interrupted; reload the current document");
        return value;
      } catch (error) {
        if (
          error instanceof DocumentError &&
          ["busy", "stale-search"].includes(error.code)
        ) {
          this.observable.update({ error: error.message });
        } else if (generation === this.generation)
          this.stop(
            error instanceof Error ? error : new Error(String(error)),
            true,
          );
        throw error;
      }
    });
    this.tail = result
      .then(
        () => {},
        () => {},
      )
      .finally(() => {
        this.pending--;
        this.publish();
      });
    return result;
  }

  private handle(operation: () => Promise<void>): void {
    this.inputEvents.endGroup();
    void this.enqueue(operation).catch(() => {});
  }

  private history(redo: boolean): Promise<void> {
    this.inputEvents.endGroup();
    if (this.blocked && !redo) return this.recover(true);
    return this.enqueue(async () =>
      this.changed(
        await (redo
          ? this.client.redoDocx(this.state.revision)
          : this.client.undoDocx(this.state.revision)),
      ),
    );
  }

  /** Waits for all input accepted before this call, and reports a stopped editor. */
  async whenIdle(): Promise<void> {
    this.pointerSelection.flush();
    await this.tail;
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
    const result = this.tail.then(async () => {
      try {
        this.assertOpen();
        await this.inputEvents.cancel();
        this.assertOpen();
        const state = await this.client.editState();
        this.assertOpen();
        if (undo && state.revision !== this.state.revision)
          throw new Error(
            "Document changed outside the editor; resume before undo",
          );
        if (undo && !state.canUndo) throw new Error("There is no edit to undo");
        this.state = undo ? await this.client.undoDocx(state.revision) : state;
        this.assertOpen();
        this.currentLayout = await this.client.layout(this.profile);
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
        this.input.readOnly = this.closed || !!this.blocked;
        this.publish();
      }
    });
    this.tail = result.then(
      () => {},
      () => {},
    );
    return result;
  }

  private selection(): DocxSelection {
    const selection = this.state.selection;
    if (!selection) throw new Error("Click a document position first");
    return selection;
  }
  find(
    text: string,
    options: DocxFindOptions = {},
  ): Promise<DocumentSearchResult> {
    this.inputEvents.endGroup();
    return this.enqueue(async () => ({
      ...(await this.client.findDocx(this.state.revision, text, options)),
      documentId: this.getSnapshot().documentId,
    }));
  }
  selectMatch(result: DocumentSearchResult, index: number): Promise<void> {
    return this.format(() =>
      this.client.selectDocx(
        result.revision,
        searchSelections(result, this.getSnapshot(), index)[0]!,
      ),
    );
  }
  replaceMatches(
    result: DocumentSearchResult,
    text: string,
    index?: number,
  ): Promise<void> {
    return this.format(() =>
      this.client.replaceDocxMatches(
        result.revision,
        searchSelections(result, this.getSnapshot(), index),
        text,
      ),
    );
  }
  setCharacterFormat(format: CharacterFormatPatch): Promise<void> {
    return this.format(() =>
      this.client.setCharacterFormat(
        this.state.revision,
        this.selection(),
        format,
      ),
    );
  }
  setParagraphFormat(format: ParagraphFormatPatch): Promise<void> {
    return this.format(() =>
      this.client.setParagraphFormat(
        this.state.revision,
        this.selection(),
        format,
      ),
    );
  }
  private format(operation: () => Promise<EditState>): Promise<void> {
    this.inputEvents.endGroup();
    return this.enqueue(async () => {
      await this.changed(await operation());
      this.focus();
    });
  }

  private selectPointer(
    point: PointerPoint,
    initial: boolean,
    extend: boolean,
    elapsed: number,
  ): Promise<void> {
    const rect = this.surface.canvas.getBoundingClientRect();
    const x = (point.x - rect.left) / this.cssScale;
    const y = (point.y - rect.top) / this.cssScale;
    const layoutId = this.currentLayout.id;
    const page = this.page;
    if (initial) {
      this.inputEvents.endGroup();
      this.pointerPageTime = performance.now();
      this.input.focus({ preventScroll: true });
    }
    return this.enqueue(async () => {
      if (!initial) this.scrollPointer(point, elapsed);
      const frame = this.currentLayout.regions[this.page];
      if (!frame) throw new Error("Unknown page");
      if (
        !initial &&
        this.currentLayout.semantics[this.page]?.lines.length === 0
      )
        return;
      const current = this.surface.canvas.getBoundingClientRect();
      const hit = await this.client.hitTest(
        initial ? layoutId : this.currentLayout.id,
        initial ? page : this.page,
        initial
          ? x
          : Math.max(
              0,
              Math.min(frame.width, (point.x - current.left) / this.cssScale),
            ),
        initial
          ? y
          : Math.max(
              0,
              Math.min(frame.height, (point.y - current.top) / this.cssScale),
            ),
      );
      this.assertOpen();
      if (!hit.position) throw new Error(hit.reason);
      this.state = await this.client.selectDocx(this.state.revision, {
        anchor:
          extend && this.state.selection
            ? this.state.selection.anchor
            : hit.position,
        focus: hit.position,
      });
      await this.presentSelection(false);
    }, true);
  }

  private scrollPointer(point: PointerPoint, elapsed: number): void {
    if (elapsed === 0) return;
    const view = this.viewport;
    const rect = view.getBoundingClientRect();
    const velocity = (position: number, start: number, length: number) =>
      Math.max(-1, Math.min(0, (position - start - 32) / 32)) +
      Math.max(0, Math.min(1, (position - start - length + 32) / 32));
    const dx = velocity(point.x, rect.left + view.clientLeft, view.clientWidth);
    const dy = velocity(point.y, rect.top + view.clientTop, view.clientHeight);
    view.scrollLeft += dx * elapsed * 0.6;
    view.scrollTop += dy * elapsed * 0.6;
    if (
      dy === 0 ||
      (dy < 0
        ? view.scrollTop > 0
        : view.scrollTop < view.scrollHeight - view.clientHeight) ||
      performance.now() - this.pointerPageTime < 250
    )
      return;
    const next = this.page + Math.sign(dy);
    if (next < 0 || next >= this.currentLayout.regions.length) return;
    this.page = next;
    this.paint();
    view.scrollTop = dy < 0 ? view.scrollHeight - view.clientHeight : 0;
    this.pointerPageTime = performance.now();
  }

  private async changed(state: EditState, relayout = false): Promise<void> {
    this.assertOpen();
    const revision = this.state.revision;
    this.state = state;
    this.publish();
    if (relayout || state.revision !== revision)
      this.currentLayout = await this.client.layout(this.profile);
    this.assertOpen();
    await this.presentSelection();
  }

  private async copySelection(cut: boolean): Promise<void> {
    const revision = this.state.revision;
    const selection = this.selection();
    const text = await this.client.selectedText(revision, selection);
    this.assertOpen();
    if (text.length === 0) return;
    if (!navigator.clipboard) throw new Error("Clipboard API is unavailable");
    await navigator.clipboard.writeText(text);
    this.assertOpen();
    if (cut) {
      const current = await this.client.editState();
      this.assertOpen();
      if (
        current.revision !== revision ||
        !sameDocxSelection(current.selection, selection)
      )
        throw new Error("Document or selection changed during clipboard write");
      await this.changed(
        await this.client.replaceRange(revision, selection, ""),
      );
    }
  }

  paste(text: string): Promise<void> {
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
        await this.client.replaceRange(
          this.state.revision,
          this.selection(),
          normalized,
        ),
      );
    });
  }
  insertSoftBreak(): Promise<void> {
    return this.paste(DOCX_SOFT_BREAK);
  }

  private async presentSelection(reveal = true): Promise<void> {
    this.assertOpen();
    const selection = this.state.selection;
    const layoutId = this.currentLayout.id;
    const revision = this.currentLayout.revision;
    const caret = selection
      ? await this.client.caret(layoutId, selection.focus)
      : undefined;
    this.assertOpen();
    const geometry = selection
      ? await this.client.selectionGeometry(layoutId, selection)
      : undefined;
    this.assertOpen();
    if (
      this.currentLayout.id !== layoutId ||
      (caret && (caret.layoutId !== layoutId || caret.revision !== revision)) ||
      (geometry &&
        (geometry.layoutId !== layoutId || geometry.revision !== revision))
    )
      throw new Error("Selection geometry belongs to a stale layout");
    if (caret) this.page = caret.page;
    await this.describeSelection();
    this.paint();
    this.surface.drawSelection(this.page, this.cssScale, geometry, caret);
    if (caret) {
      this.input.style.left = `${caret.x * this.cssScale}px`;
      this.input.style.top = `${caret.y * this.cssScale}px`;
      this.input.style.height = `${caret.height * this.cssScale}px`;
      if (reveal) revealInput(this.input, this.viewport);
    }
  }
  private async describeSelection(): Promise<void> {
    const description = await docxSelectionDescription(
      this.client,
      this.state,
      this.page,
      !!this.blocked,
    );
    this.assertOpen();
    this.selectionDescription = description;
    this.input.setAttribute("aria-description", description);
  }
  private paint(): void {
    this.page = Math.min(this.page, this.currentLayout.regions.length - 1);
    this.cssScale = this.surface.draw(this.currentLayout, this.page, this.zoom);
    // Focus and pointer selection run before text intents in the same queue.
    this.input.readOnly = this.paused || !!this.blocked || this.resuming;
    this.text.textContent =
      this.currentLayout.semantics[this.page]?.lines
        .map((line) => line.text.replaceAll("\ufffc", "[image]"))
        .join("\n") ?? "";
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
      busy: this.pending,
      paused: this.paused,
      stopped: !!this.blocked || this.resuming,
      closed: this.closed,
      error: this.blocked?.message ?? "",
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

  /** A barrier: later input cannot change the returned revision or bytes. */
  saveDocx(): Promise<EditorOutput> {
    this.inputEvents.endGroup();
    return this.enqueue(
      async () => {
        const revision = await this.checkRevision();
        const bytes = await this.client.saveDocx();
        this.publish();
        return this.observable.output(revision, "docx", bytes);
      },
      false,
      false,
      true,
    );
  }

  private async checkRevision(): Promise<number> {
    const current = await this.client.editState();
    this.assertOpen();
    if (current.revision !== this.state.revision)
      throw new Error("Document changed outside this editor");
    return current.revision;
  }

  /** Exports the completed layout at this input barrier. */
  exportPdf(outputBytes = 67108864): Promise<EditorOutput> {
    this.inputEvents.endGroup();
    return this.enqueue(
      async () => {
        const revision = await this.checkRevision();
        const bytes = await this.client.exportPdf(
          outputBytes,
          this.currentLayout.id,
        );
        this.publish();
        return this.observable.output(revision, "pdf", bytes);
      },
      false,
      false,
      true,
    );
  }

  async downloadPdf(
    filename = "document.pdf",
    outputBytes = 67108864,
  ): Promise<void> {
    const output = await this.exportPdf(outputBytes);
    this.downloadBytes(output.bytes, "application/pdf", filename);
    this.observable.markDownloaded(output);
  }

  async downloadDocx(filename = "document.docx"): Promise<void> {
    const output = await this.saveDocx();
    this.downloadBytes(
      output.bytes,
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      filename,
    );
    this.observable.markDownloaded(output);
  }

  private downloadBytes(
    bytes: Uint8Array,
    type: string,
    filename: string,
  ): void {
    this.assertOpen();
    try {
      downloadBytes(bytes, type, filename);
    } catch (error) {
      if (!this.blocked)
        this.observable.update({
          error: "Download failed. The document can be saved again.",
        });
      throw error;
    }
  }

  /** Stop input; await accepted work and cancellation before closing the caller's client. */
  dispose(): Promise<void> {
    if (this.cleanup) return this.cleanup;
    this.closed = true;
    this.generation++;
    this.listeners.abort();
    this.selectionDescription = "";
    this.input.removeAttribute("aria-description");
    this.observable.close();
    this.container.remove();
    this.cleanup = this.tail
      .then(() => this.inputEvents.cancel())
      .finally(() => {
        this.surface.dispose();
      });
    return this.cleanup;
  }
}
