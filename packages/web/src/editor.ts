import { docxOutputs, downloadDocxOutput } from "./document-output.js";
import { DocumentTables } from "./document-tables.js";
export type * from "./document-types.js";
import { createDocumentElements, docxPageText } from "./document-elements.js";
import type { FoundationClient } from "./foundation.js";
import { PageCanvas } from "./page-canvas.js";
import {
  recoverDocxState,
  cancelDocxDrawingGesture,
} from "./document-recovery.js";
import { revealInput } from "./pointer-selection.js";
import { DocumentPointer } from "./document-pointer.js";
import { TextInput } from "./text-input.js";
import { DocumentError } from "@open-document/wasm/foundation";
import {
  bindClipboard,
  copyDocxSelection,
  pasteDocxSelection,
} from "./clipboard-input.js";
import {
  EditorState,
  type EditorOutput,
  type EditorSnapshot,
} from "./editor-state.js";
import type { PageLayout } from "@open-document/wasm/preview";
import {
  docxSelectionDescription,
  queryDocxSelectionGeometry,
  searchSelections,
  selectFirstDocxPosition,
  type DocumentSearchResult,
} from "./document-selection.js";
import type {
  DocxSelection,
  EditState,
  CharacterFormatPatch,
  ParagraphFormatPatch,
  CopiedFormat,
  DocxStyleUpdate,
  DocxStyleCreation,
  DocxFindOptions,
  DocxListEdit,
  DocxListLevelUpdate,
  DocxPictureEdit,
  DocxThemeSlot,
  DocxThemeFontEdit,
  DocxSelectionGeometry,
} from "@open-document/wasm/foundation";
export class DocumentEditor extends DocumentTables {
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
  private outputError = "";
  private closed = false;
  private resuming = false;
  private page = 0;
  private zoom = 1;
  private cssScale = 96 / 72;
  private readonly inputEvents: TextInput;
  private cleanup: Promise<void> | undefined;
  private readonly pointerSelection: DocumentPointer;
  private selectionDescription = "Focus document text input to start editing";
  private constructor(
    private readonly root: HTMLElement,
    private readonly client: FoundationClient,
    protected readonly profile: Record<string, string>,
    private readonly surface: PageCanvas,
    private currentLayout: PageLayout,
    private state: EditState,
  ) {
    super({
      client,
      read: (operation) => this.enqueue(operation),
      edit: (operation) => this.format(operation),
      snapshot: () => this.getSnapshot(),
      layout: () => this.currentLayout,
    });
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
    this.pointerSelection = new DocumentPointer(
      this.surface,
      this.viewport,
      this.client,
      this.listeners.signal,
      {
        assertOpen: () => this.assertOpen(),
        ink: () => ({ options: this.inkOptions, profile: this.profile }),
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
        settle: () => this.enqueue(() => this.presentSelection(false), true),
        openComment: (id) => this.editComment({ action: "goTo", id }),
        gesture: (change) => {
          this.inputEvents.endGroup();
          return this.enqueue(async () => {
            const state = await this.client.drawingGesture(
              this.state.revision,
              change(),
              this.profile,
            );
            await this.changed(state, true, false);
          }, true);
        },
      },
    );
    bindClipboard(
      this.input,
      this.listeners.signal,
      (cut) => void this.copy(cut).catch(() => {}),
      (text) => void this.paste(text).catch(() => {}),
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
    if (paused) this.pointerSelection.finish();
    this.paused = paused;
    this.container.inert = paused;
    this.input.readOnly =
      paused ||
      !!this.blocked ||
      this.resuming ||
      !!this.state.formatting?.inputReason;
    this.publish();
    if (paused) await this.tail;
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
        if (!this.blocked) this.outputError = "";
        return value;
      } catch (error) {
        if (output && output !== "pdf" && output !== "docx" && !this.blocked) {
          this.outputError =
            error instanceof Error ? error.message : String(error);
          throw error;
        }
        if (
          error instanceof DocumentError &&
          [
            "busy",
            "stale-search",
            "stale-overview",
            "stale-toc",
            "stale-index",
            "stale-sources",
          ].includes(error.code)
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
          this.closed || !!this.blocked || !!this.state.formatting?.inputReason;
        this.publish();
      }
    });
    this.tail = result.then(
      () => {},
      () => {},
    );
    return result;
  }
  protected selection(): DocxSelection {
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
    return this.applyFormat({ character: format, paragraph: {} });
  }
  setHyperlink(target: string | null, text?: string): Promise<void> {
    return this.format(() =>
      this.client.setHyperlink(
        this.state.revision,
        this.selection(),
        target,
        text,
      ),
    );
  }
  lists() {
    return this.enqueue(() => this.client.lists(this.state.revision));
  }
  updateListLevel(
    id: number,
    level: number,
    definition: DocxListLevelUpdate,
  ): Promise<void> {
    return this.format(() =>
      this.client.updateListLevel(this.state.revision, id, level, definition),
    );
  }
  editList(change: DocxListEdit): Promise<void> {
    return this.format(() =>
      this.client.editList(this.state.revision, this.selection(), change),
    );
  }
  setParagraphFormat(format: ParagraphFormatPatch): Promise<void> {
    return this.applyFormat({ character: {}, paragraph: format });
  }
  themeColors() {
    return this.enqueue(() => this.client.themeColors(this.state.revision));
  }
  themeFonts() {
    return this.enqueue(() => this.client.themeFonts(this.state.revision));
  }
  setThemeFonts(fonts: DocxThemeFontEdit[]): Promise<void> {
    return this.format(() =>
      this.client.setThemeFonts(this.state.revision, fonts, this.profile),
    );
  }
  setThemeColor(slot: DocxThemeSlot, color: string): Promise<void> {
    return this.format(() =>
      this.client.setThemeColor(this.state.revision, slot, color),
    );
  }
  pictures() {
    return this.enqueue(() => this.client.pictures(this.state.revision));
  }
  editPicture(revision: number, picture: DocxPictureEdit): Promise<void> {
    return this.format(() =>
      this.client.editPicture(revision, picture, this.profile),
    );
  }
  setDefaultTabStop(interval: number | null): Promise<void> {
    return this.format(() =>
      this.client.setDefaultTabStop(this.state.revision, interval),
    );
  }
  styles(kind: "paragraph" | "character") {
    return this.enqueue(() => this.client.styles(this.state.revision, kind));
  }
  updateStyle(key: string, format: DocxStyleUpdate): Promise<void> {
    return this.format(() =>
      this.client.updateStyle(this.state.revision, key, format),
    );
  }
  createStyle(style: DocxStyleCreation): Promise<string> {
    this.inputEvents.endGroup();
    return this.enqueue(async () => {
      const result = await this.client.createStyle(this.state.revision, style);
      await this.changed(result.state);
      return result.id;
    });
  }
  deleteStyle(key: string, replacement: string): Promise<void> {
    return this.format(() =>
      this.client.deleteStyle(this.state.revision, key, replacement),
    );
  }
  captureFormat(): Promise<CopiedFormat> {
    this.inputEvents.endGroup();
    return this.enqueue(() =>
      this.client.captureFormat(this.state.revision, this.selection()),
    );
  }
  applyFormat(format: CopiedFormat): Promise<void> {
    return this.format(() =>
      this.client.applyFormat(
        this.state.revision,
        this.selection(),
        format,
        this.profile,
      ),
    );
  }
  private format(operation: () => Promise<EditState>): Promise<void> {
    this.inputEvents.endGroup();
    return this.enqueue(async () => {
      await this.changed(await operation());
      if (this.state.selection) this.focus();
    });
  }
  private async changed(
    state: EditState,
    relayout = false,
    reveal = true,
  ): Promise<void> {
    this.assertOpen();
    const revision = this.state.revision;
    this.state = state;
    this.publish();
    if (relayout || state.revision !== revision)
      this.currentLayout = await this.surface.layout(this.profile);
    this.assertOpen();
    await this.presentSelection(reveal);
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
  private async presentSelection(reveal = true): Promise<void> {
    this.assertOpen();
    const layoutId = this.currentLayout.id;
    const { caret, geometry, formatting } = await queryDocxSelectionGeometry(
      this.client,
      this.state,
      this.currentLayout,
      () => this.assertOpen(),
    );
    this.assertOpen();
    if (this.currentLayout.id !== layoutId)
      throw new Error("Selection geometry belongs to a stale layout");
    this.state = { ...this.state, formatting };
    if (caret) this.page = caret.page;
    const description = await docxSelectionDescription(
      this.client,
      this.state,
      this.page,
      !!this.blocked,
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
    this.page = Math.min(this.page, this.currentLayout.regions.length - 1);
    this.cssScale = this.surface.draw(this.currentLayout, this.page, this.zoom);
    this.surface.setComments(
      this.currentLayout.comments,
      this.page,
      this.cssScale,
    );
    // Focus and pointer selection run before text intents in the same queue.
    this.input.readOnly =
      this.paused ||
      !!this.blocked ||
      this.resuming ||
      !!this.state.formatting?.inputReason;
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
      busy: this.pending,
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
  protected outputs(
    format: "docx" | "pdf" | "png" | "images" | "html" | "markdown",
    outputBytes = 67108864,
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
  protected async showRevisionGeometry(
    geometry: DocxSelectionGeometry,
  ): Promise<void> {
    await this.showPage(geometry.rects[0]!.page);
    this.surface.drawRevision(
      geometry,
      this.page,
      this.cssScale,
      this.viewport,
    );
  }
  protected downloadOutput(output: EditorOutput, filename: string): void {
    this.assertOpen();
    downloadDocxOutput(output, filename, this.observable, !this.blocked);
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
