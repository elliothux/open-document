import type { PdfQuery, PdfTextSpec } from "../core/pdf.js";
import { PdfViewer } from "./pdf-viewer.js";
import type { PdfClient } from "./pdf.js";
import type { EditorOutput } from "@open-document/web-core/editor-state";
import { pdfThumbnail } from "./pdf-thumbnail.js";
import { PdfObjectInputs } from "./pdf-object-input.js";
import { decodeImage } from "@open-document/web-core/image";

import {
  draftCommand,
  pdfTextRole,
  type Draft,
  type EditCommand,
} from "./pdf-draft.js";

/** Page operations and a native draft panel; PDF body text remains positioned. */
export class PdfEditor extends PdfViewer {
  private thumbnails: Promise<unknown> = Promise.resolve();
  async thumbnail(page: string): Promise<Blob> {
    const task = this.thumbnails.then(async () => {
      await new Promise<void>((resolve) =>
        requestAnimationFrame(() => resolve()),
      );
      return this.enqueue(
        () =>
          pdfThumbnail(this.client, this.state.revision, page, this.profile),
        false,
        true,
      );
    });
    this.thumbnails = task.catch(() => {});
    return task;
  }
  readonly propertyInput = document.createElement("div");
  private propertyReason = "";
  private readonly text = document.createElement("textarea");
  private readonly checked = document.createElement("input");
  private readonly x = document.createElement("input");
  private readonly y = document.createElement("input");
  private readonly objectInputs = new PdfObjectInputs(() => this.publish());
  private readonly editEvents = new AbortController();
  private draft: Draft | undefined;
  private composing = false;
  private applying = false;

  private constructor(
    client: PdfClient,
    state: PdfQuery,
    root: HTMLElement,
    profile: Record<string, string>,
  ) {
    super(client, state, root, profile);
    const signal = this.editEvents.signal;
    this.text.setAttribute("aria-label", "PDF property text");
    this.text.maxLength = 32767;
    this.checked.type = "checkbox";
    this.checked.setAttribute("aria-label", "PDF checkbox value");
    for (const [input, label] of [
      [this.x, "Note horizontal position"],
      [this.y, "Note vertical position"],
    ] as const) {
      input.type = "number";
      input.value = "20";
      input.min = "0";
      input.setAttribute("aria-label", label);
    }
    this.propertyInput.addEventListener(
      "compositionstart",
      () => {
        this.composing = true;
        this.updateButtons();
      },
      { signal },
    );
    this.propertyInput.addEventListener(
      "compositionend",
      () => {
        this.composing = false;
        this.updateButtons();
      },
      { signal },
    );
    for (const [key, input] of [
      ["text", this.text],
      ["checked", this.checked],
      ["x", this.x],
      ["y", this.y],
    ] as const) {
      const label = document.createElement("label"),
        caption = document.createElement("span");
      label.dataset.pdfControl = key;
      caption.textContent = input.getAttribute("aria-label");
      label.append(caption, input);
      this.propertyInput.append(label);
    }
    for (const node of [this.text, this.checked, this.x, this.y]) {
      node.addEventListener("input", () => this.publish(), { signal });
      node.addEventListener("change", () => this.publish(), { signal });
    }
    this.propertyInput.append(this.objectInputs.element);
    this.showDraft();
  }

  static override async create(
    root: HTMLElement,
    client: PdfClient,
    profile: Record<string, string> = {},
    signal?: AbortSignal,
  ): Promise<PdfEditor> {
    signal?.throwIfAborted();
    const editor = new PdfEditor(
      client,
      await client.execute({ operation: "queryPdf" }),
      root,
      profile,
    );
    try {
      await editor.refresh();
      signal?.throwIfAborted();
      return editor;
    } catch (error) {
      await editor.dispose();
      throw error;
    }
  }
  protected override inputState() {
    return {
      draft: this.dirty(),
      composition: this.composing,
      property: this.draft
        ? this.draft.kind === "note"
          ? "note"
          : this.draft.originalSpec !== undefined &&
              this.draft.kind !== "newText"
            ? `object:${this.draft.id}`
            : `${this.draft.kind}:${this.draft.id}`
        : "",
      propertyReason: this.propertyReason,
      applying: this.applying,
    };
  }
  protected override pauseChanged(): void {
    this.propertyInput.inert = this.paused;
    this.showDraft();
  }
  chooseProperty(value: string): Promise<void> {
    this.checkDraft();
    return this.enqueue(() => this.chooseNow(value));
  }
  beginNote(): Promise<void> {
    this.checkDraft();
    return this.enqueue(async () => {
      this.draft = {
        kind: "note",
        id: "",
        page: this.state.page,
        original: "",
      };
      this.text.value = "";
      this.x.value = this.y.value = "20";
      this.showDraft();
      this.text.focus();
    });
  }
  beginText(role: PdfTextSpec["role"] = "text"): Promise<void> {
    this.checkDraft();
    return this.enqueue(async () => {
      const page = this.state.pages.find(
        (item) => item.id === this.state.page,
      )!;
      const font = this.profile["*"]
        ? "Arial"
        : (Object.keys(this.profile).find((name) => !name.includes("|")) ??
          "Arial");
      const bottom = role === "footer" || role === "page-number";
      this.objectInputs.set({
        placement: {
          x: 20,
          y: bottom ? Math.max(0, page.height - 40) : 20,
          width: Math.max(1, Math.min(200, page.width - 40)),
          height: bottom ? 30 : 60,
          rotation: 0,
        },
        text: "",
        font,
        size: 14,
        color: "000000",
        role,
        foreground: role !== "watermark",
      });
      this.draft = {
        kind: "newText",
        id: "",
        page: page.id,
        original: "",
        originalSpec: this.objectInputs.signature,
        role,
        pages:
          role === "text" ? [page.id] : this.state.pages.map((item) => item.id),
      };
      this.text.value = role === "page-number" ? "{page}" : "";
      this.showDraft();
      this.text.focus();
    });
  }
  async objects() {
    return this.enqueue(() =>
      this.client.execute({
        operation: "pdfObjects",
        profile: this.profile,
        revision: this.state.revision,
        page: this.state.page,
      }),
    );
  }
  async deleteObject(): Promise<PdfQuery> {
    this.checkDraft();
    const draft = this.draft;
    if (!draft || !["textObject", "objectGeometry"].includes(draft.kind))
      throw new Error("Choose a PDF object");
    return this.commit((revision) => ({
      operation: "deletePdfObject",
      profile: this.profile,
      revision,
      page: draft.page,
      object: draft.id,
    }));
  }
  async insertImage(bytes: Uint8Array, replace = false): Promise<PdfQuery> {
    this.checkDraft();
    const draft = this.draft;
    if (replace && draft?.kind !== "objectGeometry")
      throw new Error("Choose an image to replace");
    const page = draft && replace ? draft.page : this.state.page;
    const placement = this.objectInputs.read("").placement;
    this.applying = true;
    this.showDraft();
    try {
      return await this.commit(async (revision) => {
        const image = await decodeImage(bytes);
        try {
          return {
            operation: "addPdfImage",
            profile: this.profile,
            revision,
            page,
            placement: replace
              ? placement
              : {
                  x: 20,
                  y: 20,
                  width: Math.min(200, image.bitmap.width),
                  height:
                    (Math.min(200, image.bitmap.width) * image.bitmap.height) /
                    image.bitmap.width,
                  rotation: 0,
                },
            pixelWidth: image.bitmap.width,
            pixelHeight: image.bitmap.height,
            bytes: image.rgba,
            ...(replace ? { replace: draft!.id } : {}),
          };
        } finally {
          image.bitmap.close();
        }
      });
    } finally {
      this.applying = false;
      if (!this.closed && !this.closing) this.showDraft();
    }
  }
  addNote(page: string, x: number, y: number, text: string): Promise<PdfQuery> {
    this.checkDraft();
    return this.commit((revision) => ({
      operation: "addPdfNote",
      revision,
      page,
      x,
      y,
      text,
    }));
  }
  setFieldValue(field: string, value: string | boolean): Promise<PdfQuery> {
    this.checkDraft();
    return this.commit((revision) => ({
      operation: "setPdfFieldValue",
      revision,
      field,
      value,
      profile: this.profile,
    }));
  }
  updateAnnotation(
    page: string,
    annotation: string,
    text: string,
  ): Promise<PdfQuery> {
    this.checkDraft();
    return this.commit((revision) => ({
      operation: "updatePdfAnnotation",
      revision,
      page,
      annotation,
      text,
    }));
  }

  private dirty(): boolean {
    if (!this.draft) return false;
    const value =
      typeof this.draft.original === "boolean"
        ? this.checked.checked
        : this.text.value;
    return (
      value !== this.draft.original ||
      (this.draft.originalSpec !== undefined &&
        this.objectInputs.signature !== this.draft.originalSpec) ||
      (this.draft.kind === "note" &&
        (this.x.value !== "20" || this.y.value !== "20"))
    );
  }
  protected override checkDraft(): void {
    if (this.composing)
      throw new Error(
        "Finish or cancel text composition before this operation",
      );
    if (this.applying)
      throw new Error("Wait for the accepted PDF property edit");
    if (this.dirty())
      throw new Error(
        "Apply or cancel the PDF property draft before this operation",
      );
  }
  protected override checkClose(): void {
    if (!this.applying) this.checkDraft();
    else if (this.composing)
      throw new Error("Finish or cancel composition before closing");
  }
  protected override stateChanged(): void {
    this.draft = undefined;
    this.text.value = "";
    this.showDraft();
    this.updateButtons();
  }
  private updateButtons(): void {
    this.publish();
  }
  private showDraft(): void {
    const draft = this.draft;
    const field =
      draft?.kind === "field"
        ? this.state.fields.find((field) => field.id === draft.id)
        : undefined;
    const annotation =
      draft?.kind === "annotation"
        ? this.state.annotations.find((item) => item.id === draft.id)
        : undefined;
    this.propertyReason =
      this.state.readOnlyReason ||
      field?.readOnlyReason ||
      annotation?.readOnlyReason ||
      draft?.reason ||
      "";
    this.text.hidden =
      !draft ||
      typeof draft.original === "boolean" ||
      draft.kind === "objectGeometry";
    this.checked.hidden = !draft || typeof draft.original !== "boolean";
    this.x.hidden = this.y.hidden = draft?.kind !== "note";
    for (const input of [this.text, this.checked, this.x, this.y])
      if (input.parentElement) input.parentElement.hidden = input.hidden;
    this.text.rows = field?.multiline ? 4 : 2;
    this.text.maxLength = field?.maxLength ?? 32767;
    this.text.disabled = this.checked.disabled =
      this.paused || this.applying || !!this.propertyReason;
    this.x.disabled = this.y.disabled = this.text.disabled;
    this.objectInputs.show(
      draft?.originalSpec !== undefined,
      draft?.kind !== "objectGeometry",
      this.text.disabled,
    );
    this.updateButtons();
  }
  private async chooseNow(value: string): Promise<void> {
    if (value.startsWith("object:")) {
      const objects = await this.client.execute({
        operation: "pdfObjects",
        profile: this.profile,
        revision: this.state.revision,
        page: this.state.page,
      });
      const object = objects.objects.find(
        (item) => `object:${item.id}` === value,
      );
      if (!object) throw new Error("Unknown PDF object");
      this.objectInputs.set({
        placement: object.placement,
        text: object.text,
        font: object.font || "Arial",
        size: object.size || 14,
        color: object.color || "000000",
        role: "text",
        foreground: object.foreground,
      });
      this.draft = {
        kind: object.kind === "text" ? "textObject" : "objectGeometry",
        id: object.id,
        page: this.state.page,
        original: object.text,
        originalSpec: this.objectInputs.signature,
        reason: object.readOnlyReason,
        role: pdfTextRole(object.role),
      };
      this.text.value = object.text;
    } else if (value.startsWith("metadata:")) {
      const key = value.slice("metadata:".length);
      if (!["Title", "Author", "Subject", "Keywords"].includes(key))
        throw new Error("Unknown PDF metadata");
      const metadata = await this.client.execute({ operation: "pdfMetadata" });
      const entry = Object.entries(metadata.fields).find(
        ([name]) => name === key,
      );
      if (!entry) throw new Error("Missing PDF metadata");
      this.draft = {
        kind: "metadata",
        id: key,
        page: this.state.page,
        original: entry[1],
        reason: metadata.readOnlyReason,
      };
      this.text.value = entry[1];
    } else if (value.startsWith("field:")) {
      const field = this.state.fields.find(
        (field) => `field:${field.id}` === value,
      );
      if (!field) throw new Error("Unknown PDF field");
      const page = field.widgets[0]?.page || this.state.page;
      if (page !== this.state.page) await this.paint(page);
      this.draft = {
        kind: "field",
        id: field.id,
        page,
        original:
          typeof field.value === "boolean"
            ? field.value
            : String(field.value ?? ""),
      };
      this.text.value = typeof field.value === "string" ? field.value : "";
      this.checked.checked = field.value === true;
    } else if (value.startsWith("annotation:")) {
      const annotation = this.state.annotations.find(
        (item) => `annotation:${item.id}` === value,
      );
      if (!annotation) throw new Error("Unknown PDF annotation");
      if (annotation.page !== this.state.page)
        await this.paint(annotation.page);
      this.draft = {
        kind: "annotation",
        id: annotation.id,
        page: annotation.page,
        original: annotation.text,
      };
      this.text.value = annotation.text;
    } else this.draft = undefined;
    this.showDraft();
  }
  cancelDraft(): void {
    if (this.composing || this.applying)
      throw new Error(
        "Finish composition or the accepted edit before cancelling",
      );
    this.draft = undefined;
    this.text.value = "";
    this.checked.checked = false;
    this.x.value = this.y.value = "20";
    this.showDraft();
  }
  private async commit(
    command: (revision: number) => EditCommand | Promise<EditCommand>,
  ): Promise<PdfQuery> {
    return this.enqueue(async () => {
      const request = await command(this.state.revision);
      if (this.stopped && !["undoPdf", "redoPdf"].includes(request.operation))
        throw new Error("Refresh or undo before further PDF edits");
      const state = await this.client.execute(request);
      this.state = state;
      this.retainSearch();
      this.draft = undefined;
      this.text.value = "";
      if (!this.closing && !this.closed) await this.paint();
      return state;
    });
  }
  async applyDraft(): Promise<void> {
    if (this.composing || this.applying)
      throw new Error("Finish composition or the accepted edit first");
    const draft = this.draft;
    if (!draft) throw new Error("Choose a PDF property first");
    const value =
      typeof draft.original === "boolean"
        ? this.checked.checked
        : this.text.value;
    const x = Number(this.x.value),
      y = Number(this.y.value);
    const spec = this.objectInputs.read(String(value), draft.role);
    this.applying = true;
    this.cancelSearch();
    this.showDraft();
    try {
      await this.commit((revision) =>
        draftCommand(draft, value, spec, x, y, revision, this.profile),
      );
    } finally {
      this.applying = false;
      if (!this.closed && !this.closing) this.showDraft();
    }
  }
  async movePage(delta: number): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => {
      const pages = this.state.pages.map((page) => page.id),
        index = pages.indexOf(this.state.page),
        next = index + delta;
      if (!Number.isInteger(delta) || next < 0 || next >= pages.length)
        throw new Error("PDF page cannot move further");
      [pages[index], pages[next]] = [pages[next]!, pages[index]!];
      return { operation: "reorderPdfPages", revision, pages };
    });
  }
  async rotate(degrees: number): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "rotatePdfPages",
      revision,
      pages: [this.state.page],
      degrees,
    }));
  }
  async insertPages(
    bytes: Uint8Array,
    index = this.state.pages.length,
    pages: string[] = [],
  ): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "insertPdfPages",
      revision,
      bytes,
      index,
      pages,
    }));
  }
  async insertBlankPage(width = 595, height = 842): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    const index =
      this.state.pages.findIndex((page) => page.id === this.state.page) + 1;
    return this.commit((revision) => ({
      operation: "insertBlankPdfPage",
      revision,
      index,
      width,
      height,
    }));
  }
  async cropPage(
    x: number,
    y: number,
    width: number,
    height: number,
  ): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "cropPdfPage",
      revision,
      page: this.state.page,
      x,
      y,
      width,
      height,
    }));
  }
  async resizePage(
    width: number,
    height: number,
    scaleContent: boolean,
    anchor: "top-left" | "center" = "top-left",
  ): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "resizePdfPage",
      revision,
      page: this.state.page,
      width,
      height,
      scaleContent,
      anchor,
    }));
  }
  async replacePage(bytes: Uint8Array): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "replacePdfPages",
      revision,
      bytes,
      pages: [],
      index: this.state.pages.findIndex((page) => page.id === this.state.page),
      replace: [this.state.page],
    }));
  }
  async extractPages(pages = [this.state.page]): Promise<EditorOutput> {
    this.checkDraft();
    return this.enqueue(async () => {
      const output = await this.client.execute({
        operation: "extractPdfPages",
        revision: this.state.revision,
        pages,
      });
      return this.observable.output(output.revision, "pdf", output.bytes);
    }, true);
  }
  async deletePage(): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({
      operation: "deletePdfPages",
      revision,
      pages: [this.state.page],
    }));
  }
  async highlight(): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => {
      if (!this.layout) throw new Error("PDF page is not displayed");
      return {
        operation: "highlightPdfText",
        revision,
        layoutId: this.layout.id,
      };
    });
  }
  async deleteAnnotation(): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    const draft = this.draft;
    if (!draft || draft.kind !== "annotation")
      throw new Error("Choose an annotation to delete");
    return this.commit((revision) => ({
      operation: "deletePdfAnnotation",
      revision,
      page: draft.page,
      annotation: draft.id,
    }));
  }
  async undo(): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({ operation: "undoPdf", revision }));
  }
  async redo(): Promise<PdfQuery> {
    this.checkDraft();
    this.cancelSearch();
    return this.commit((revision) => ({ operation: "redoPdf", revision }));
  }
  async save(): Promise<EditorOutput> {
    if (!this.applying) this.checkDraft();
    if (this.composing)
      throw new Error("Finish or cancel composition before saving");
    return this.enqueue(async () => {
      this.checkDraft();
      const output = await this.client.execute({
        operation: "savePdf",
        revision: this.state.revision,
      });
      return this.observable.output(output.revision, "pdf", output.bytes);
    }, true);
  }
  override async close(): Promise<void> {
    try {
      await super.close();
    } finally {
      if (!this.closed) this.showDraft();
    }
  }
  override dispose(): Promise<void> {
    this.editEvents.abort();
    return super.dispose().finally(() => this.propertyInput.remove());
  }
}
