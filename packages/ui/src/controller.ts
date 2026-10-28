import { downloadBytes } from "@open-document/web-core/download";
import type { DelimitedOptions, EditorHost, Product } from "./types.js";
import type { EditorOutput } from "@open-document/web-core/editor-state";
import { readFile } from "./file.js";
import { messages } from "./messages.js";
import { PdfPrinter } from "./print.js";
import { mime } from "./types.js";
import type {
  OfficeDocument,
  EditorOptions,
  Locale,
  MountedSnapshot,
  OwnedFile,
  SavedDocument,
  Theme,
} from "./types.js";

export type LeaveChoice = "save" | "discard" | "cancel";
export interface LeaveDialog {
  readonly kind: "draft" | "unsaved";
  readonly canSave: boolean;
}
export interface UiSnapshot<E extends EditorHost = EditorHost> {
  readonly file: OwnedFile<E> | undefined;
  readonly document: MountedSnapshot | undefined;
  readonly name: string;
  readonly saving: boolean;
  readonly loading: boolean;
  readonly theme: Theme;
  readonly locale: Locale;
  readonly message: string;
  readonly error: string;
  readonly dialog: LeaveDialog | undefined;
}

/** Coordinates file ownership; document commands stay in each editor's queue. */
export class EditorController<E extends EditorHost = EditorHost> {
  private value: UiSnapshot<E>;
  private readonly listeners = new Set<() => void>();
  private unsubscribe: (() => void) | undefined;
  private saving:
    { kind: string; name: string; promise: Promise<SavedDocument> } | undefined;
  private changing: Promise<boolean> | undefined;
  private candidate: Promise<OwnedFile<E>> | undefined;
  private candidateAbort: AbortController | undefined;
  private prepared: OwnedFile<E> | undefined;
  private answer: ((choice: LeaveChoice) => void) | undefined;
  private cleanup: Promise<void> | undefined;
  private disposed = false;
  private errorVersion = 0;
  private newDocumentId: string | undefined;
  private readonly printer: PdfPrinter;

  constructor(
    readonly options: EditorOptions,
    readonly product: Product<E>,
    readonly host: HTMLElement,
    readonly surfaces: HTMLElement,
    private readonly releaseUi: () => void,
  ) {
    this.printer = new PdfPrinter(host.ownerDocument);
    this.value = {
      file: undefined,
      document: undefined,
      name: options.document.name,
      saving: false,
      loading: true,
      theme: options.theme ?? "light",
      locale: options.locale ?? "en-US",
      message: "",
      error: "",
      dialog: undefined,
    };
    this.host.dataset.theme = this.value.theme;
  }

  readonly getUiSnapshot = (): UiSnapshot<E> => this.value;
  readonly getSnapshot = (): MountedSnapshot => {
    if (!this.value.document) throw new Error("Editor is not mounted");
    return this.value.document;
  };
  readonly subscribe = (listener: () => void): (() => void) => {
    if (this.disposed) return () => {};
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  private publish(fields: Partial<UiSnapshot<E>> = {}): void {
    const value = { ...this.value, ...fields };
    if (value.file) {
      const snapshot = value.file.editor.getSnapshot();
      const next = {
        ...snapshot,
        newDocument: snapshot.documentId === this.newDocumentId,
        modified:
          snapshot.modified || snapshot.documentId === this.newDocumentId,
        error: value.error || snapshot.error,
        name: value.name,
        saving: value.saving,
        loading: value.loading,
        message: value.message,
      };
      const previous = this.value.document;
      value.document =
        previous &&
        Object.keys(next).every((key) =>
          Object.is(Reflect.get(next, key), Reflect.get(previous, key)),
        )
          ? previous
          : Object.freeze(next);
    }
    this.value = Object.freeze(value);
    for (const listener of this.listeners) {
      try {
        listener();
      } catch {
        /* Observers do not own file transactions. */
      }
    }
  }

  private assertOpen(): void {
    if (this.disposed) throw new Error("Editor is disposed");
  }
  private current(): OwnedFile<E> {
    this.assertOpen();
    if (!this.value.file) throw new Error("Editor is not mounted");
    return this.value.file;
  }

  async initialize(): Promise<void> {
    this.assertOpen();
    this.options.signal?.throwIfAborted();
    const abort = () => this.candidateAbort?.abort(this.options.signal?.reason);
    this.options.signal?.addEventListener("abort", abort, { once: true });
    try {
      const file = await this.prepare(this.options.document);
      this.options.signal?.throwIfAborted();
      this.assertOpen();
      this.install(
        file,
        this.options.document.name,
        !!this.options.document.blank,
      );
    } finally {
      this.options.signal?.removeEventListener("abort", abort);
    }
  }

  private async prepare(document: OfficeDocument): Promise<OwnedFile<E>> {
    if (this.candidate) throw new Error("A file is already opening");
    this.candidateAbort ??= new AbortController();
    this.candidate = this.product.prepare(
      document,
      this.surfaces,
      this.candidateAbort.signal,
    );
    try {
      const file = await this.candidate;
      if (this.disposed || this.candidateAbort.signal.aborted) {
        await file.dispose();
        throw new DOMException("Opening cancelled", "AbortError");
      }
      this.prepared = file;
      return file;
    } finally {
      this.candidate = undefined;
      this.candidateAbort = undefined;
    }
  }
  cancelOpening(): void {
    this.assertOpen();
    this.candidateAbort?.abort(
      new DOMException("Opening cancelled", "AbortError"),
    );
  }

  private install(file: OwnedFile<E>, name: string, isNew = false): void {
    this.printer.cancel();
    name = file.originalName;
    isNew ||= file.imported;
    this.newDocumentId = isNew
      ? file.editor.getSnapshot().documentId
      : undefined;
    this.prepared = undefined;
    this.unsubscribe?.();
    Object.assign(file.surface.style, {
      position: "relative",
      visibility: "visible",
      pointerEvents: "auto",
    });
    this.unsubscribe = file.editor.subscribe(() => this.publish());
    this.publish({ file, name, loading: false, message: "", error: "" });
  }

  readonly save = (): Promise<SavedDocument> => this.output("original");
  saveAs(name: string): Promise<SavedDocument> {
    return this.output("original", false, this.fileName(name));
  }
  private fileName(name: string): string {
    name = name.trim();
    if (
      !name ||
      name.length > 255 ||
      [...name].some(
        (character) =>
          character.charCodeAt(0) < 32 ||
          character === "/" ||
          character === "\\",
      )
    )
      throw new Error("A valid file name is required");
    return name.toLowerCase().endsWith(`.${this.product.format}`)
      ? name
      : `${name}.${this.product.format}`;
  }
  exportPdf(all = true): Promise<SavedDocument> {
    return this.output(all ? "pdf" : "pdf-current");
  }
  readonly print = (): Promise<void> => this.output("print").then(() => {});
  exportCsv(selection = false): Promise<SavedDocument> {
    return this.output(selection ? "csv-selection" : "csv");
  }
  exportPng(): Promise<SavedDocument> {
    return this.output("png");
  }
  exportMarkup(format: "html" | "markdown"): Promise<SavedDocument> {
    return this.output(format);
  }
  exportJpeg(): Promise<SavedDocument> {
    return this.output("jpeg");
  }
  exportImages(format: "png" | "jpeg" = "png"): Promise<void> {
    return this.output(format === "jpeg" ? "jpegs" : "images").then(() => {});
  }
  exportOutput(kind: string): Promise<SavedDocument> {
    return this.output(kind);
  }
  private output(
    kind: string,
    leaving = false,
    targetName = this.value.name,
  ): Promise<SavedDocument> {
    try {
      this.assertOpen();
    } catch (error) {
      return Promise.reject(error);
    }
    if (this.saving)
      return this.saving.kind === kind && this.saving.name === targetName
        ? this.saving.promise
        : Promise.reject(new Error("Another output is in progress"));
    if (this.changing && !leaving)
      return Promise.reject(new Error("A file change is in progress"));
    const file = this.current();
    const name =
      kind === "original"
        ? targetName
        : this.value.name.replace(/\.[^.]*$/, "") +
          (kind === "html"
            ? ".html"
            : kind === "markdown"
              ? ".md"
              : kind === "png"
                ? ".png"
                : kind === "jpeg"
                  ? ".jpg"
                  : kind.startsWith("csv")
                    ? ".csv"
                    : ".pdf");
    const operation = async (): Promise<SavedDocument> => {
      if (kind === "images" || kind === "jpegs") {
        if (!file.pageImages) throw new Error("Page images are unavailable");
        const pages = await file.pageImages(kind === "jpegs" ? "jpeg" : "png");
        const prefix = targetName.replace(/\.[^.]*$/, "");
        const digits = Math.max(2, String(pages.length).length);
        let result: SavedDocument | undefined;
        for (const [index, page] of pages.entries()) {
          result = await this.deliverOutput(
            page,
            `${prefix}-${String(index + 1).padStart(digits, "0")}.${page.format === "jpeg" ? "jpg" : "png"}`,
            kind,
            file,
          );
          this.assertOpen();
          const text = messages(this.value.locale)[
            this.options.onSave
              ? "imageSavedProgress"
              : "imageGeneratedProgress"
          ];
          this.publish({
            message: text
              .replace("{done}", String(index + 1))
              .replace("{total}", String(pages.length))
              .replace("{format}", page.format === "jpeg" ? "JPEG" : "PNG"),
          });
        }
        if (!result) throw new Error("The document has no page images");
        return result;
      }
      const output = await file.output(kind);
      if (kind === "print") {
        this.assertOpen();
        await this.printer.print(output.bytes, name);
        return Object.freeze({ ...output, name });
      }
      return this.deliverOutput(output, name, kind, file);
    };
    // Start after publishing the in-flight promise so observers cannot start a second callback.
    const promise = Promise.resolve()
      .then(operation)
      .catch((error: unknown) => {
        this.report(error);
        throw error;
      })
      .finally(() => {
        this.saving = undefined;
        if (!this.disposed) this.publish({ saving: false });
      });
    this.saving = { kind, name: targetName, promise };
    this.publish({ saving: true, message: "", error: "" });
    return promise;
  }

  private async deliverOutput(
    output: EditorOutput,
    name: string,
    kind: string,
    file: OwnedFile<E>,
  ): Promise<SavedDocument> {
    this.assertOpen();
    const result = Object.freeze({ ...output, name });
    if (this.options.onSave) {
      await this.options.onSave(result);
      if (!this.disposed && this.value.file === file) {
        if (kind === "original") {
          file.editor.markSaved(output);
          this.newDocumentId = undefined;
        }
        this.publish({
          name: kind === "original" ? name : this.value.name,
          message: messages(this.value.locale).outputSaved,
        });
      }
    } else {
      downloadBytes(output.bytes, mime[output.format], name);
      file.editor.markDownloaded(output);
      this.publish({
        name: kind === "original" ? name : this.value.name,
        message: messages(this.value.locale).generated,
      });
    }
    return result;
  }

  private ask(dialog: LeaveDialog): Promise<LeaveChoice> {
    this.assertOpen();
    return new Promise((resolve) => {
      this.answer = resolve;
      this.publish({ dialog });
    });
  }
  choose(choice: LeaveChoice): void {
    const answer = this.answer;
    this.answer = undefined;
    this.publish({ dialog: undefined });
    answer?.(choice);
  }

  private async canLeave(file: OwnedFile<E>): Promise<boolean> {
    let snapshot = file.editor.getSnapshot();
    if (snapshot.composition || snapshot.dragging) {
      this.publish({ message: messages(this.value.locale).compositionText });
      file.editor.focus();
      return false;
    }
    await file.editor.setPaused(true);
    this.assertOpen();
    snapshot = file.editor.getSnapshot();
    if (snapshot.composition || snapshot.dragging) return false;
    let leavingOutput: SavedDocument | undefined;
    if (snapshot.draft) {
      const choice = await this.ask({
        kind: "draft",
        canSave: file.draftCanSave,
      });
      this.assertOpen();
      if (choice === "cancel") return false;
      if (choice === "save") {
        leavingOutput = await this.output("original", true);
      } else if (file.cancelDraft) file.cancelDraft();
      else return false;
    }
    if (
      !leavingOutput &&
      (file.editor.getSnapshot().modified ||
        file.editor.getSnapshot().documentId === this.newDocumentId)
    ) {
      const choice = await this.ask({ kind: "unsaved", canSave: true });
      this.assertOpen();
      if (choice === "cancel") return false;
      if (choice === "save")
        leavingOutput = await this.output("original", true);
    }
    const after = file.editor.getSnapshot();
    if (
      leavingOutput &&
      (after.revision !== leavingOutput.revision ||
        after.draft ||
        after.composition ||
        after.dragging)
    ) {
      this.publish({ message: messages(this.value.locale).modified });
      return false;
    }
    return true;
  }

  readonly open = (document: OfficeDocument): Promise<boolean> =>
    this.change(() => this.replace(document));
  create(document: { readonly name: string }): Promise<boolean> {
    if (!this.product.canCreate)
      return Promise.reject(new Error("Blank creation is unavailable for PDF"));
    return this.open({ name: this.fileName(document.name), blank: true });
  }
  openFile(file: File, delimited?: DelimitedOptions): Promise<boolean> {
    return this.change(() => this.replace(file, delimited));
  }
  private async replace(
    source: OfficeDocument | File,
    delimited?: DelimitedOptions,
  ): Promise<boolean> {
    const previous = this.current();
    const inputLimit =
      this.product.delimited && /\.(csv|tsv)$/i.test(source.name)
        ? Math.min(previous.inputLimit, 4194304)
        : previous.inputLimit;
    if (
      (source instanceof File ? source.size : (source.bytes?.length ?? 0)) >
      inputLimit
    )
      throw new Error("Document input exceeds budget");
    if (!(await this.canLeave(previous))) return false;
    this.publish({ loading: true, error: "", message: "" });
    const abort = new AbortController();
    this.candidateAbort = abort;
    try {
      const document: OfficeDocument =
        source instanceof File
          ? {
              name: source.name,
              bytes: await readFile(source, abort.signal),
              ...(delimited === undefined ? {} : { delimited }),
            }
          : source;
      abort.signal.throwIfAborted();
      this.assertOpen();
      const candidate = await this.prepare(document);
      this.assertOpen();
      this.install(candidate, document.name, !!document.blank);
      try {
        await previous.dispose();
      } catch (error) {
        this.publish({
          message: `${messages(this.value.locale).previousCleanup}: ${error instanceof Error ? error.message : String(error)}`,
        });
      }
      return true;
    } catch (error) {
      if (
        !this.disposed &&
        error instanceof DOMException &&
        error.name === "AbortError"
      ) {
        this.publish({ message: messages(this.value.locale).cancel });
        return false;
      }
      throw error;
    } finally {
      if (this.candidateAbort === abort) this.candidateAbort = undefined;
    }
  }
  readonly close = (): Promise<boolean> =>
    this.change(async () => {
      if (!(await this.canLeave(this.current()))) return false;
      await this.dispose();
      return true;
    });
  private change(operation: () => Promise<boolean>): Promise<boolean> {
    try {
      this.assertOpen();
    } catch (error) {
      return Promise.reject(error);
    }
    if (this.changing)
      return Promise.reject(new Error("A file change is already in progress"));
    const promise = Promise.resolve()
      .then(async () => {
        if (this.saving) await this.saving.promise;
        this.assertOpen();
        return operation();
      })
      .catch((error: unknown) => {
        this.report(error);
        throw error;
      })
      .finally(async () => {
        this.changing = undefined;
        if (!this.disposed) {
          await this.value.file?.editor.setPaused(false);
          this.publish({ loading: false });
        }
      });
    this.changing = promise;
    return promise;
  }

  setTheme(theme: Theme): void {
    this.assertOpen();
    this.host.dataset.theme = theme;
    this.publish({ theme });
  }
  setLocale(locale: Locale): void {
    this.assertOpen();
    this.publish({ locale });
  }
  report(error: unknown): void {
    if (!this.disposed) {
      this.errorVersion++;
      this.publish({
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
  run(operation: () => unknown | Promise<unknown>): void {
    const errorVersion = this.errorVersion;
    try {
      void Promise.resolve(operation()).then(
        () => {
          if (!this.disposed && this.errorVersion === errorVersion)
            this.publish({ error: "" });
        },
        (error: unknown) => this.report(error),
      );
    } catch (error) {
      this.report(error);
    }
  }

  readonly dispose = (): Promise<void> => {
    if (this.cleanup) return this.cleanup;
    this.disposed = true;
    this.printer.cancel();
    this.candidateAbort?.abort();
    this.choose("cancel");
    this.unsubscribe?.();
    this.cleanup = (async () => {
      const failures: unknown[] = [];
      let candidate: OwnedFile<E> | undefined;
      try {
        candidate = await this.candidate;
      } catch {
        /* Preparation owns failed candidates. */
      }
      try {
        await candidate?.dispose();
      } catch (error) {
        failures.push(error);
      }
      try {
        await this.prepared?.dispose();
      } catch (error) {
        failures.push(error);
      }
      try {
        await this.value.file?.dispose();
      } catch (error) {
        failures.push(error);
      }
      this.publish({ loading: false, saving: false });
      this.listeners.clear();
      try {
        this.releaseUi();
      } catch (error) {
        failures.push(error);
      }
      if (failures.length)
        throw new AggregateError(failures, "Editor cleanup failed");
    })();
    return this.cleanup;
  };
}
