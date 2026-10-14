import type { PdfCommand, PdfQuery } from "@open-document/wasm/pdf";
import { PdfViewer, type PdfViewerOptions } from "./pdf-viewer.js";
import { downloadBytes } from "./download.js";
import type { PdfClient } from "./pdf.js";

type EditCommand = Extract<
  PdfCommand,
  {
    operation:
      | "reorderPdfPages"
      | "rotatePdfPages"
      | "deletePdfPages"
      | "addPdfNote"
      | "highlightPdfText"
      | "updatePdfAnnotation"
      | "deletePdfAnnotation"
      | "setPdfFieldValue"
      | "undoPdf"
      | "redoPdf";
  }
>;
type Draft = {
  kind: "field" | "annotation" | "note";
  id: string;
  page: string;
  original: string | boolean;
};

/** Page operations and a native draft panel; PDF body text remains positioned. */
export class PdfEditor extends PdfViewer {
  private readonly panel = document.createElement("fieldset");
  private readonly target = document.createElement("select");
  private readonly text = document.createElement("textarea");
  private readonly checked = document.createElement("input");
  private readonly x = document.createElement("input");
  private readonly y = document.createElement("input");
  private readonly reason = document.createElement("p");
  private readonly applyButton: HTMLButtonElement;
  private readonly saveButton: HTMLButtonElement;
  private readonly editEvents = new AbortController();
  private draft: Draft | undefined;
  private composing = false;
  private applying = false;

  private constructor(
    client: PdfClient,
    state: PdfQuery,
    options: PdfViewerOptions,
  ) {
    super(client, state, options);
    const signal = this.editEvents.signal;
    const legend = document.createElement("legend");
    legend.textContent = "PDF annotations and form fields";
    this.target.setAttribute("aria-label", "PDF annotation or field");
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
    this.text.addEventListener(
      "compositionstart",
      () => {
        this.composing = true;
        this.updateButtons();
      },
      { signal },
    );
    this.text.addEventListener(
      "compositionend",
      () => {
        this.composing = false;
        this.updateButtons();
      },
      { signal },
    );
    this.target.addEventListener(
      "change",
      () =>
        this.perform(async () => {
          try {
            this.checkDraft();
          } catch (error) {
            this.target.value =
              this.draft && this.draft.kind !== "note"
                ? `${this.draft.kind}:${this.draft.id}`
                : "";
            throw error;
          }
          await this.choose(this.target.value);
        }),
      { signal },
    );
    this.applyButton = this.button("Apply PDF property", () =>
      this.applyDraft(),
    );
    this.saveButton = this.button("Save PDF", async () => {
      const bytes = await this.save();
      downloadBytes(bytes, "application/pdf", "document.pdf");
    });
    this.panel.append(
      legend,
      this.target,
      this.reason,
      this.text,
      this.checked,
      this.x,
      this.y,
      this.applyButton,
      this.button("Cancel PDF property", async () => {
        this.cancelDraft();
      }),
      this.button("Delete annotation", () => this.deleteAnnotation()),
    );
    this.toolbar.append(
      this.button("Move page earlier", () => this.movePage(-1)),
      this.button("Move page later", () => this.movePage(1)),
      this.button("Rotate page clockwise", () => this.rotate(90)),
      this.button("Delete page", () => this.deletePage()),
      this.button("Add note", async () => {
        this.checkDraft();
        this.draft = {
          kind: "note",
          id: "",
          page: this.state.page,
          original: "",
        };
        this.text.value = "";
        this.showDraft();
        this.text.focus();
      }),
      this.button("Highlight selected text", () => this.highlight()),
      this.button("Undo PDF edit", () => this.undo()),
      this.button("Redo PDF edit", () => this.redo()),
      this.saveButton,
    );
    this.element.append(this.panel);
  }

  static override async create(options: PdfViewerOptions): Promise<PdfEditor> {
    const { client, state } = await this.connect(options);
    const editor = new PdfEditor(client, state, options);
    try {
      await editor.refresh();
      return editor;
    } catch (error) {
      editor.dispose();
      throw error;
    }
  }
  private dirty(): boolean {
    if (!this.draft) return false;
    const value =
      typeof this.draft.original === "boolean"
        ? this.checked.checked
        : this.text.value;
    return (
      value !== this.draft.original ||
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
    const options = [new Option("Choose a field or annotation", "")];
    for (const field of this.state.fields)
      options.push(
        new Option(
          `${field.name || field.id} (${field.kind})`,
          `field:${field.id}`,
        ),
      );
    for (const annotation of this.state.annotations.filter(
      (item) => item.kind !== "Widget",
    ))
      options.push(
        new Option(
          `${annotation.kind}: ${annotation.text.slice(0, 80)}`,
          `annotation:${annotation.id}`,
        ),
      );
    this.target.replaceChildren(...options);
    this.draft = undefined;
    this.text.value = "";
    this.showDraft();
    this.updateButtons();
  }
  private updateButtons(): void {
    this.applyButton.disabled =
      this.composing ||
      this.applying ||
      !this.draft ||
      !!this.state.readOnlyReason ||
      this.stopped ||
      !!this.reason.textContent;
    this.saveButton.disabled = this.composing || this.applying;
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
    this.reason.textContent =
      this.state.readOnlyReason ||
      field?.readOnlyReason ||
      annotation?.readOnlyReason ||
      "";
    this.text.hidden = !draft || typeof draft.original === "boolean";
    this.checked.hidden = !draft || typeof draft.original !== "boolean";
    this.x.hidden = this.y.hidden = draft?.kind !== "note";
    this.text.rows = field?.multiline ? 4 : 2;
    this.text.maxLength = field?.maxLength ?? 32767;
    this.text.disabled = this.checked.disabled =
      this.applying || !!this.reason.textContent;
    this.updateButtons();
  }
  private async choose(value: string): Promise<void> {
    if (value.startsWith("field:")) {
      const field = this.state.fields.find(
        (field) => `field:${field.id}` === value,
      );
      if (!field) throw new Error("Unknown PDF field");
      const page = field.widgets[0]?.page || this.state.page;
      if (page !== this.state.page) await this.goToPage(page);
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
        await this.goToPage(annotation.page);
      this.draft = {
        kind: "annotation",
        id: annotation.id,
        page: annotation.page,
        original: annotation.text,
      };
      this.text.value = annotation.text;
    } else this.draft = undefined;
    this.target.value = value;
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
    this.target.value = "";
    this.x.value = this.y.value = "20";
    this.showDraft();
  }
  private async commit(
    command: (revision: number) => EditCommand,
  ): Promise<PdfQuery> {
    return this.enqueue(async () => {
      const request = command(this.state.revision);
      if (this.stopped && !["undoPdf", "redoPdf"].includes(request.operation))
        throw new Error("Refresh or undo before further PDF edits");
      const state = await this.client.execute(request);
      this.state = state;
      this.retainSearch();
      this.draft = undefined;
      this.text.value = "";
      this.target.value = "";
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
    this.applying = true;
    this.cancelSearch();
    this.showDraft();
    try {
      await this.commit((revision) =>
        draft.kind === "field"
          ? {
              operation: "setPdfFieldValue",
              revision,
              field: draft.id,
              value,
              profile: this.profile,
            }
          : draft.kind === "annotation"
            ? {
                operation: "updatePdfAnnotation",
                revision,
                page: draft.page,
                annotation: draft.id,
                text: String(value),
              }
            : {
                operation: "addPdfNote",
                revision,
                page: draft.page,
                x,
                y,
                text: String(value),
              },
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
  async save(): Promise<Uint8Array> {
    if (!this.applying) this.checkDraft();
    if (this.composing)
      throw new Error("Finish or cancel composition before saving");
    return this.enqueue(async () => {
      this.checkDraft();
      return (
        await this.client.execute({
          operation: "savePdf",
          revision: this.state.revision,
        })
      ).bytes;
    });
  }
  override async close(): Promise<void> {
    try {
      await super.close();
    } finally {
      if (!this.closed) this.showDraft();
    }
  }
  override dispose(): void {
    this.editEvents.abort();
    super.dispose();
  }
}
