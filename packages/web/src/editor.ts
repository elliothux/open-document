import type { FoundationClient } from "./foundation.js";
import { PageCanvas } from "./page-canvas.js";
import { PointerSelection, type PointerPoint } from "./pointer-selection.js";
import { TextInput } from "./text-input.js";
import { DocumentError } from "@open-document/wasm/foundation";
import { bindClipboard } from "./clipboard-input.js";
import type { PageLayout } from "@open-document/wasm/preview";
import type {
  DocxPosition,
  DocxSelection,
  EditState,
} from "@open-document/wasm/foundation";

/** Owns browser input order. The caller owns fonts, the opened DOCX and client lifetime. */
export class DocumentEditor {
  private readonly container = document.createElement("div");
  private readonly viewport = document.createElement("div");
  private readonly input = document.createElement("textarea");
  private readonly status = document.createElement("p");
  private readonly text = document.createElement("pre");
  private readonly diagnostics = document.createElement("ul");
  private readonly undo = document.createElement("button");
  private readonly redo = document.createElement("button");
  private readonly previous = document.createElement("button");
  private readonly next = document.createElement("button");
  private readonly retry = document.createElement("button");
  private readonly download = document.createElement("button");
  private readonly pdf = document.createElement("button");
  private readonly listeners = new AbortController();
  private tail: Promise<void> = Promise.resolve();
  private pending = 0;
  private generation = 0;
  private blocked: Error | undefined;
  private closed = false;
  private resuming = false;
  private outputRevision: number | undefined;
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
    this.container.setAttribute("role", "region");
    this.container.setAttribute("aria-label", "Document editor");
    this.status.setAttribute("role", "status");
    this.text.setAttribute("aria-label", "Current page text");
    this.diagnostics.setAttribute("aria-label", "Document diagnostics");
    this.input.setAttribute("aria-label", "Document text input");
    this.input.setAttribute("aria-description", this.selectionDescription);
    this.input.autocomplete = "off";
    this.input.spellcheck = false;
    this.input.setAttribute("autocapitalize", "off");
    Object.assign(this.input.style, {
      position: "absolute",
      width: "1px",
      padding: "0",
      border: "0",
      opacity: "0",
      pointerEvents: "none",
      resize: "none",
    });
    Object.assign(this.viewport.style, {
      position: "relative",
      overflow: "auto",
      maxHeight: "80vh",
    });
    this.viewport.append(this.surface.canvas, this.surface.overlay, this.input);
    this.container.append(
      this.previous,
      this.next,
      this.undo,
      this.redo,
      this.download,
      this.pdf,
      this.retry,
      this.status,
      this.viewport,
      this.text,
      this.diagnostics,
    );
    const options = { signal: this.listeners.signal };
    window.addEventListener(
      "resize",
      () => {
        if (!this.closed && !this.blocked && !this.resuming)
          this.handle(() => this.presentSelection());
      },
      options,
    );
    const button = (
      element: HTMLButtonElement,
      label: string,
      action: () => void,
    ) => {
      element.type = "button";
      element.textContent = label;
      element.addEventListener("click", action, options);
    };
    button(this.previous, "Previous page", () =>
      this.handle(() => this.showPage(this.page - 1)),
    );
    button(this.next, "Next page", () =>
      this.handle(() => this.showPage(this.page + 1)),
    );
    button(this.undo, "Undo", () => {
      void this.history(false).catch(() => {});
    });
    button(this.redo, "Redo", () => {
      void this.history(true).catch(() => {});
    });
    button(this.download, "Save DOCX", () => {
      void this.downloadDocx().catch(() => {});
    });
    button(this.pdf, "Export PDF", () => {
      void this.downloadPdf().catch(() => {});
    });
    button(this.retry, "Resume editing", () => {
      void this.resume().catch(() => {});
    });
    this.pointerSelection = new PointerSelection(
      this.surface.canvas,
      this.viewport,
      this.listeners.signal,
      (point, initial, extend, elapsed) =>
        this.selectPointer(point, initial, extend, elapsed),
      () =>
        !this.closed &&
        !this.blocked &&
        !this.resuming &&
        !this.inputEvents.active,
      () => this.enqueue(() => this.presentSelection(), true),
    );
    bindClipboard(
      this.input,
      this.listeners.signal,
      (cut) => this.handle(() => this.copySelection(cut)),
      (text) => this.pasteText(text),
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
        available: () => !this.closed && !this.blocked && !this.resuming,
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
    this.retry.hidden = false;
    this.undo.disabled = !this.state.canUndo;
    this.redo.disabled = true;
    this.status.textContent = `${error.message}. Editing stopped; ${cancelQueued ? "queued input was cancelled" : "accepted input will finish; new input was rejected"}. Resume to reload the current document.`;
  }

  private enqueue<T>(
    operation: () => Promise<T>,
    pointer = false,
    composition = false,
  ): Promise<T> {
    if (!pointer) this.pointerSelection.finish();
    try {
      this.assertOpen();
      if (this.blocked) throw this.blocked;
      if (this.resuming) throw new Error("Wait for editing to resume");
      if (!composition && this.inputEvents.active) {
        this.status.textContent =
          "Complete or cancel composition before this operation";
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
        if (error instanceof DocumentError && error.code === "busy") {
          this.status.textContent = error.message;
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
      const frame = this.currentLayout.pages[this.page];
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
    if (next < 0 || next >= this.currentLayout.pages.length) return;
    this.page = next;
    this.paint();
    view.scrollTop = dy < 0 ? view.scrollHeight - view.clientHeight : 0;
    this.pointerPageTime = performance.now();
  }

  private async changed(state: EditState, relayout = false): Promise<void> {
    this.assertOpen();
    const revision = this.state.revision;
    this.state = state;
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
      const same = (a: DocxPosition, b: DocxPosition) =>
        a.paragraph === b.paragraph &&
        a.offset === b.offset &&
        a.affinity === b.affinity &&
        a.bidiLevel === b.bidiLevel &&
        a.frameStart === b.frameStart;
      if (
        current.revision !== revision ||
        !current.selection ||
        !same(current.selection.anchor, selection.anchor) ||
        !same(current.selection.focus, selection.focus)
      )
        throw new Error("Document or selection changed during clipboard write");
      await this.changed(
        await this.client.replaceRange(revision, selection, ""),
      );
    }
  }

  private pasteText(text: string): void {
    this.inputEvents.endGroup();
    if (this.blocked || this.closed) return;
    if (this.inputEvents.active) {
      this.handle(async () => {});
      return;
    }
    if (text.length > this.state.commandLimit || text.includes("\t")) {
      this.stop(new Error("Paste contains tabs or exceeds command budget"));
      return;
    }
    const normalized = text.replace(/\r\n?/g, "\n");
    this.handle(async () => {
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
    const context = this.surface.clearOverlay(this.cssScale);
    context.fillStyle = "rgba(30, 100, 220, 0.25)";
    for (const rect of geometry?.rects ?? []) {
      if (rect.page === this.page)
        context.fillRect(rect.x, rect.y, rect.width, rect.height);
    }
    if (caret) {
      context.fillStyle = "#174ca0";
      context.fillRect(caret.x, caret.y, 1 / this.cssScale, caret.height);
      this.input.style.left = `${caret.x * this.cssScale}px`;
      this.input.style.top = `${caret.y * this.cssScale}px`;
      this.input.style.height = `${caret.height * this.cssScale}px`;
      if (reveal) this.revealInput();
    }
  }

  private async describeSelection(): Promise<void> {
    const selection = this.state.selection;
    let description: string;
    if (this.blocked)
      description = "Selection unavailable while editing is stopped";
    else if (this.state.compositionId !== null)
      description = "Text composition in progress";
    else if (!selection)
      description = "Focus document text input to start editing";
    else if (
      selection.anchor.paragraph === selection.focus.paragraph &&
      selection.anchor.offset === selection.focus.offset
    )
      description = `Insertion point on page ${this.page + 1}`;
    else {
      try {
        description = `Selected text: ${await this.client.selectedText(this.state.revision, selection)}`;
      } catch (error) {
        if (
          !(error instanceof DocumentError) ||
          (error.code !== "protected-content" &&
            error.code !== "limit-exceeded")
        )
          throw error;
        description = `Selected content is unavailable: ${error.message}`;
      }
    }
    this.assertOpen();
    this.selectionDescription = description;
    this.input.setAttribute("aria-description", description);
  }

  private revealInput(): void {
    this.input.scrollIntoView({ block: "nearest", inline: "nearest" });
    const target = this.input.getBoundingClientRect();
    const view = this.viewport;
    const box = view.getBoundingClientRect();
    const top = box.top + view.clientTop;
    const left = box.left + view.clientLeft;
    // Native nearest scrolling rounds fractional caret coordinates to CSS pixels.
    if (target.height <= view.clientHeight) {
      if (target.top < top) view.scrollTop -= Math.ceil(top - target.top);
      else if (target.bottom > top + view.clientHeight)
        view.scrollTop += Math.ceil(target.bottom - top - view.clientHeight);
    }
    if (target.width <= view.clientWidth) {
      if (target.left < left) view.scrollLeft -= Math.ceil(left - target.left);
      else if (target.right > left + view.clientWidth)
        view.scrollLeft += Math.ceil(target.right - left - view.clientWidth);
    }
  }

  private paint(): void {
    this.page = Math.min(this.page, this.currentLayout.pages.length - 1);
    this.cssScale = this.surface.draw(this.currentLayout, this.page, this.zoom);
    // Focus and pointer selection run before text intents in the same queue.
    this.input.readOnly = !!this.blocked || this.resuming;
    this.retry.hidden = !this.blocked;
    this.undo.disabled = !this.state.canUndo;
    this.redo.disabled = !this.state.canRedo;
    this.previous.disabled = this.page === 0;
    this.next.disabled = this.page === this.currentLayout.pages.length - 1;
    this.text.textContent =
      this.currentLayout.semantics[this.page]?.lines
        .map((line) => line.text.replaceAll("\ufffc", "[image]"))
        .join("\n") ?? "";
    this.updateStatus();
    this.diagnostics.replaceChildren(
      ...this.currentLayout.diagnostics.map((message) => {
        const item = document.createElement("li");
        item.textContent = message;
        return item;
      }),
    );
  }

  private updateStatus(): void {
    if (!this.blocked) {
      const text = `Page ${this.page + 1} of ${this.currentLayout.pages.length}; revision ${this.state.revision}; last output ${this.outputRevision ?? "none"}; ${this.selectionDescription}`;
      if (this.status.textContent !== text) this.status.textContent = text;
    }
  }

  private async showPage(index: number): Promise<void> {
    this.page = Math.max(
      0,
      Math.min(this.currentLayout.pages.length - 1, index),
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
  saveDocx(): Promise<{ revision: number; bytes: Uint8Array }> {
    this.inputEvents.endGroup();
    return this.enqueue(async () => {
      const revision = await this.checkRevision();
      const bytes = await this.client.saveDocx();
      this.outputRevision = revision;
      this.updateStatus();
      return { revision, bytes };
    });
  }

  private async checkRevision(): Promise<number> {
    const current = await this.client.editState();
    this.assertOpen();
    if (current.revision !== this.state.revision)
      throw new Error("Document changed outside this editor");
    return current.revision;
  }

  /** Exports the completed layout at this input barrier. */
  exportPdf(
    outputBytes = 67108864,
  ): Promise<{ revision: number; bytes: Uint8Array }> {
    this.inputEvents.endGroup();
    return this.enqueue(async () => {
      const revision = await this.checkRevision();
      const bytes = await this.client.exportPdf(
        outputBytes,
        this.currentLayout.id,
      );
      this.outputRevision = revision;
      this.updateStatus();
      return { revision, bytes };
    });
  }

  async downloadPdf(
    filename = "document.pdf",
    outputBytes = 67108864,
  ): Promise<void> {
    const { bytes } = await this.exportPdf(outputBytes);
    this.downloadBytes(bytes, "application/pdf", filename);
  }

  async downloadDocx(filename = "document.docx"): Promise<void> {
    const { bytes } = await this.saveDocx();
    this.downloadBytes(
      bytes,
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      filename,
    );
  }

  private downloadBytes(
    bytes: Uint8Array,
    type: string,
    filename: string,
  ): void {
    this.assertOpen();
    let url: string | undefined;
    try {
      url = URL.createObjectURL(
        new Blob([new Uint8Array(bytes).buffer], { type }),
      );
      const link = document.createElement("a");
      link.href = url;
      link.download = filename;
      link.click();
    } catch (error) {
      if (!this.blocked)
        this.status.textContent =
          "Download failed. The current document is available to save again.";
      throw error;
    } finally {
      if (url) URL.revokeObjectURL(url);
    }
  }

  /** Removes UI immediately; await cancellation before reusing or closing the caller's client. */
  dispose(): Promise<void> {
    if (this.cleanup) return this.cleanup;
    this.closed = true;
    this.generation++;
    this.listeners.abort();
    this.selectionDescription = "";
    this.input.removeAttribute("aria-description");
    this.surface.dispose();
    this.container.remove();
    this.cleanup = this.tail.then(() => this.inputEvents.cancel());
    return this.cleanup;
  }
}
