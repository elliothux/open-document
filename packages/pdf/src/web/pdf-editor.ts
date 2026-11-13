import { viewOnlyReason } from "@open-document/web-core/view-mode";
import { propertyDraft, renderPdfPropertyDraft } from "./pdf-property-draft.js";
import {
  textDraft,
  drawingDraft,
  inkDraft,
  fieldDraft,
  pageGeometryDraft,
  imageCropDraft,
} from "./pdf-draft-setup.js";
import type {
  PdfQuery,
  PdfTextSpec,
  PdfDrawingAnnotation,
  PdfFieldDesign,
} from "../core/pdf.js";
import { createPdfOperations } from "./pdf-operations.js";
import { PdfView } from "./pdf-view.js";
import type { PdfViewer } from "./pdf-viewer.js";
import type { PdfClient } from "./pdf.js";
import type { EditorOutput } from "@open-document/web-core/editor-state";
import { ThumbnailRevisions } from "@open-document/web-core/thumbnail-revisions";
import { pdfThumbnail } from "./pdf-thumbnail.js";
import { PdfPropertyInputs } from "./pdf-property-input.js";
import { PdfObjectDrag } from "./pdf-object-drag.js";

import { draftCommand, type Draft, type EditCommand } from "./pdf-draft.js";

/** Page operations and a native draft panel; PDF body text remains positioned. */
export class PdfEditor {
  private readonly view: PdfView;
  get element() {
    return this.view.element;
  }
  get viewport() {
    return this.view.viewport;
  }
  readonly getSnapshot = (...args: Parameters<PdfViewer["getSnapshot"]>) =>
    this.view.getSnapshot(...args);
  readonly subscribe = (...args: Parameters<PdfViewer["subscribe"]>) =>
    this.view.subscribe(...args);
  readonly markSaved = (...args: Parameters<PdfViewer["markSaved"]>) =>
    this.view.markSaved(...args);
  readonly markDownloaded = (
    ...args: Parameters<PdfViewer["markDownloaded"]>
  ) => this.view.markDownloaded(...args);
  readonly focus = (...args: Parameters<PdfViewer["focus"]>) =>
    this.view.focus(...args);
  readonly setPaused = (...args: Parameters<PdfViewer["setPaused"]>) =>
    this.view.setPaused(...args);
  setReadOnly(readOnly: boolean): void {
    if (readOnly === this.client.readOnly) return;
    this.client.readOnly = readOnly;
    this.showDraft();
    this.view.publish();
  }
  get snapshot() {
    return this.view.snapshot;
  }
  get displayedPage() {
    return this.view.displayedPage;
  }
  readonly refresh = (...args: Parameters<PdfViewer["refresh"]>) =>
    this.view.refresh(...args);
  readonly goToPage = (...args: Parameters<PdfViewer["goToPage"]>) =>
    this.view.goToPage(...args);
  readonly navigatePage = (...args: Parameters<PdfViewer["navigatePage"]>) =>
    this.view.navigatePage(...args);
  readonly setZoom = (...args: Parameters<PdfViewer["setZoom"]>) =>
    this.view.setZoom(...args);
  readonly selectText = (...args: Parameters<PdfViewer["selectText"]>) =>
    this.view.selectText(...args);
  readonly selectedText = (...args: Parameters<PdfViewer["selectedText"]>) =>
    this.view.selectedText(...args);
  readonly extractText = (...args: Parameters<PdfViewer["extractText"]>) =>
    this.view.extractText(...args);
  readonly navigation = (...args: Parameters<PdfViewer["navigation"]>) =>
    this.view.navigation(...args);
  readonly setReadingMode = (
    ...args: Parameters<PdfViewer["setReadingMode"]>
  ) => this.view.setReadingMode(...args);
  readonly selectRange = (...args: Parameters<PdfViewer["selectRange"]>) =>
    this.view.selectRange(...args);
  readonly cancelSearch = (...args: Parameters<PdfViewer["cancelSearch"]>) =>
    this.view.cancelSearch(...args);
  readonly search = (...args: Parameters<PdfViewer["search"]>) =>
    this.view.search(...args);
  readonly nextMatch = (...args: Parameters<PdfViewer["nextMatch"]>) =>
    this.view.nextMatch(...args);
  readonly showMatch = (index: number) => this.view.showMatch(index);
  metadata() {
    return this.view.enqueue(() =>
      this.client.execute({ operation: "pdfMetadata" }),
    );
  }
  readonly copy = (...args: Parameters<PdfViewer["copy"]>) =>
    this.view.copy(...args);

  readonly operations: ReturnType<typeof createPdfOperations>;
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

  private thumbnails: Promise<unknown> = Promise.resolve();
  private readonly thumbnailRevisions = new ThumbnailRevisions();
  readonly thumbnailVersion = (page: string): number =>
    this.thumbnailRevisions.version(page, this.view.state.revision);
  async thumbnail(
    page: string,
    revision?: number,
    signal?: AbortSignal,
  ): Promise<Blob> {
    const task = this.thumbnails.then(() => {
      return this.view.enqueue(
        () => {
          signal?.throwIfAborted();
          const current = this.view.state.revision;
          if (revision !== undefined && current !== revision)
            throw new Error("PDF thumbnail is stale");
          return pdfThumbnail(this.client, current, page, this.profile, signal);
        },
        false,
        true,
      );
    });
    this.thumbnails = task.catch(() => {});
    return task;
  }
  private readonly controls: PdfPropertyInputs;
  private readonly objectDrag: PdfObjectDrag;
  readonly propertyInput: HTMLDivElement;
  private propertyReason = "";
  private draft: Draft | undefined;
  private composing = false;
  private applying = false;
  private applicationDone: Promise<void> = Promise.resolve();

  readonly inputLimits: ReturnType<PdfClient["inputLimits"]>;
  private constructor(
    private readonly client: PdfClient,
    state: PdfQuery,
    root: HTMLElement,
    private readonly profile: Record<string, string>,
  ) {
    this.inputLimits = client.inputLimits();
    this.controls = new PdfPropertyInputs(
      () => this.view.publish(),
      (active) => {
        this.composing = active;
        this.updateButtons();
      },
      this.inputLimits,
    );
    this.objectDrag = new PdfObjectDrag({
      view: () =>
        this.view.layout
          ? {
              canvas: this.view.surface.canvas,
              page: this.view.layout.page,
              scale: this.view.scale,
            }
          : undefined,
      placement: () => this.controls.objectInputs.read("").placement,
      inputs: {
        root: this.controls.objectInputs.element,
        x: this.controls.objectInputs.inputs.x,
        y: this.controls.objectInputs.inputs.y,
      },
      beforeStart: () => {
        const draft = this.draft;
        if (
          this.view.paused ||
          this.applying ||
          this.composing ||
          this.getSnapshot().busy ||
          this.propertyReason ||
          !draft ||
          !["textObject", "objectGeometry"].includes(draft.kind)
        )
          return false;
        if (draft.kind === "textObject") {
          if (this.dirty()) return false;
          draft.kind = "objectGeometry";
          this.showDraft();
        }
        return true;
      },
      change: () => this.view.publish(),
    });
    this.propertyInput = this.controls.element;

    this.view = new PdfView(client, state, root, profile, {
      inputState: () => this.inputState(),
      pauseChanged: () => this.pauseChanged(),
      checkDraft: () => this.checkDraft(),
      checkClose: () => this.checkClose(),
      stateChanged: () => this.stateChanged(),
    });
    this.operations = createPdfOperations(this.client, this.profile, {
      state: () => this.view.state,
      view: () => ({
        layout: this.view.layout,
        surface: this.view.surface,
        scale: this.view.scale,
        closed: this.view.closed,
        closing: this.view.closing,
      }),
      checkDraft: () => this.checkDraft(),
      cancelSearch: () => this.cancelSearch(),
      commit: (command) => this.commit(command),
      enqueue: (action, output) => this.view.enqueue(action, output),
      output: (...args) => this.view.observable.output(...args),
      warnings: (warnings) => {
        this.view.pageDiagnostics = [
          ...new Set([...this.view.pageDiagnostics, ...warnings]),
        ];
        this.view.publish();
      },
    });
    this.showDraft();
  }

  static async create(
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
  private inputState() {
    return {
      draft: this.dirty(),
      composition: this.composing,
      dragging: this.controls.inkInputs.dragging || this.objectDrag.dragging,
      property: this.draft
        ? this.draft.kind === "note"
          ? "note"
          : this.draft.kind === "textObject" ||
              this.draft.kind === "objectGeometry"
            ? `object:${this.draft.id}`
            : `${this.draft.kind}:${this.draft.id}`
        : "",
      propertyReason: this.propertyReason,
      applying: this.applying,
    };
  }
  private pauseChanged(): void {
    this.propertyInput.inert = this.view.paused || this.client.readOnly;
    this.showDraft();
  }
  chooseProperty(value: string): Promise<void> {
    this.checkDraft();
    return this.view.enqueue(() => this.chooseNow(value));
  }
  private beginDraft(
    setup: () => Draft | Promise<Draft>,
    focus: HTMLElement = this.controls.text,
  ): Promise<void> {
    this.checkDraft();
    return this.view.enqueue(async () => {
      this.checkDraft();
      this.draft = await setup();
      this.showDraft();
      if (!this.view.closed && !this.view.closing) focus.focus();
    });
  }
  setPropertyLocale(locale: "zh-CN" | "en-US"): void {
    this.controls.widgetInputs.setLocale(locale);
    this.controls.cropInputs.setLocale(locale);
    this.objectDrag.setLocale(locale);
  }
  beginImageCrop(): Promise<void> {
    return this.beginDraft(async () => {
      const draft = this.draft;
      const query = await this.client.execute({
        operation: "pdfObjects",
        revision: this.view.state.revision,
        page: this.view.state.page,
        profile: this.profile,
      });
      const target = query.objects.find((item) => item.id === draft?.id);
      if (!draft || !target || target.kind !== "image" || target.readOnlyReason)
        throw new Error(
          target?.readOnlyReason || "Choose an editable PDF image",
        );
      return imageCropDraft(this.controls, draft.page, draft.id);
    }, this.controls.cropInputs.inputs.x);
  }
  beginFieldDesign(): Promise<void> {
    return this.beginDraft(async () => {
      if (this.draft?.kind !== "field")
        throw new Error("Choose a field to design");
      const details = await this.client.execute({
        operation: "pdfFieldDesign",
        revision: this.view.state.revision,
        field: this.draft.id,
      });
      if (!details.spec)
        throw new Error(details.readOnlyReason || "Field design is protected");
      const spec = details.spec;
      this.controls.fieldInputs.set(spec);
      this.controls.objectInputs.set({
        ...spec,
        text: String(spec.value),
        role: "text",
        foreground: true,
      });
      this.controls.widgetInputs.setPages(this.view.state.pages);
      this.controls.widgetInputs.set(details.widgets, spec.kind);
      const value = Array.isArray(spec.value)
        ? spec.value.join("\n")
        : spec.value;
      this.controls.text.value = typeof value === "boolean" ? "" : value;
      this.controls.checked.checked = value === true;
      return {
        kind: "fieldDesign",
        id: details.field,
        page: this.view.state.page,
        original: value,
        reason: details.readOnlyReason,
        originalSpec:
          this.controls.objectInputs.signature +
          this.controls.fieldInputs.signature +
          this.controls.widgetInputs.signature,
      };
    }, this.controls.fieldInputs.controls.name);
  }
  beginAnnotationEdit(): Promise<void> {
    return this.beginAnnotationDraft("annotationStyle");
  }
  beginAnnotationReply(): Promise<void> {
    return this.beginAnnotationDraft("annotationReply");
  }
  private beginAnnotationDraft(
    kind: "annotationStyle" | "annotationReply",
  ): Promise<void> {
    return this.beginDraft(async () => {
      if (this.draft?.kind !== "annotation")
        throw new Error("Choose an annotation");
      const details = await this.client.execute({
        operation: "pdfAnnotation",
        revision: this.view.state.revision,
        page: this.draft.page,
        annotation: this.draft.id,
      });
      this.controls.objectInputs.setAnnotation({
        ...details.style,
        ...(kind === "annotationReply" ? { author: "", text: "" } : {}),
      });
      this.controls.text.value =
        kind === "annotationReply" ? "" : details.style.text;
      return {
        kind,
        id: details.annotation,
        page: details.page,
        original: this.controls.text.value,
        originalSpec: this.controls.objectInputs.signature,
      };
    });
  }
  deleteAnnotationThread(): Promise<PdfQuery> {
    this.checkDraft();
    if (this.draft?.kind !== "annotation")
      throw new Error("Choose an annotation thread");
    const { page, id } = this.draft;
    return this.commit((revision) => ({
      operation: "deletePdfAnnotationThread",
      revision,
      page,
      annotation: id,
    }));
  }
  beginNote(): Promise<void> {
    this.checkDraft();
    return this.view.enqueue(async () => {
      this.draft = {
        kind: "note",
        id: "",
        page: this.view.state.page,
        original: "",
      };
      this.controls.text.value = "";
      this.controls.x.value = this.controls.y.value = "20";
      this.showDraft();
      this.controls.text.focus();
    });
  }
  beginText(role: PdfTextSpec["role"] = "text"): Promise<void> {
    return this.beginDraft(() =>
      textDraft(this.controls, this.view.state, this.profile, role),
    );
  }
  async objects() {
    return this.view.enqueue(() =>
      this.client.execute({
        operation: "pdfObjects",
        profile: this.profile,
        revision: this.view.state.revision,
        page: this.view.state.page,
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
    const page = draft && replace ? draft.page : this.view.state.page;
    const placement = this.controls.objectInputs.read("").placement;
    const completion = Promise.withResolvers<void>();
    this.applicationDone = completion.promise;
    this.applying = true;
    this.showDraft();
    try {
      return await this.commit(async (revision) => {
        const image = await this.client.decodeRaster(bytes);
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
                width: Math.min(200, image.width),
                height:
                  (Math.min(200, image.width) * image.height) / image.width,
                rotation: 0,
              },
          pixelWidth: image.width,
          pixelHeight: image.height,
          bytes: image.bytes,
          ...(replace ? { replace: draft!.id } : {}),
        };
      });
    } finally {
      this.applying = false;
      completion.resolve();
      if (!this.view.closed && !this.view.closing) this.showDraft();
    }
  }
  beginDrawing(
    kind: PdfDrawingAnnotation["kind"],
    arrow = false,
  ): Promise<void> {
    return this.beginDraft(() =>
      drawingDraft(this.controls, this.view.state, kind, arrow),
    );
  }
  beginInk(signature = false): Promise<void> {
    return this.beginDraft(
      () => inkDraft(this.controls, this.view.state, signature),
      this.controls.inkInputs.pad,
    );
  }
  beginField(kind: PdfFieldDesign["kind"]): Promise<void> {
    return this.beginDraft(
      () => fieldDraft(this.controls, this.view.state, this.profile, kind),
      this.controls.fieldInputs.controls.name,
    );
  }
  beginFieldRename(): Promise<void> {
    return this.beginFieldName("fieldName");
  }
  beginFieldCopy(): Promise<void> {
    return this.beginFieldName("fieldCopy");
  }
  private async beginFieldName(kind: "fieldName" | "fieldCopy"): Promise<void> {
    this.checkDraft();
    await this.view.enqueue(async () => {
      this.checkDraft();
      if (this.draft?.kind !== "field")
        throw new Error("Choose a field to rename");
      const field = this.view.state.fields.find(
        (field) => field.id === this.draft?.id,
      )!;
      this.draft = {
        kind,
        id: field.id,
        page: this.view.state.page,
        original: field.name + (kind === "fieldCopy" ? "_copy" : ""),
      };
      this.controls.text.value = String(this.draft.original);
      this.controls.x.value = this.controls.y.value = "20";
      this.showDraft();
      this.controls.text.focus();
    });
  }
  deleteField(): Promise<PdfQuery> {
    this.checkDraft();
    if (this.draft?.kind !== "field")
      throw new Error("Choose a field to delete");
    return this.operations.removeField(this.draft.id);
  }
  private draftSignature(): string {
    if (this.draft?.kind === "imageCrop")
      return this.controls.cropInputs.signature;
    return (
      this.controls.objectInputs.signature +
      (this.draft?.kind === "newField" || this.draft?.kind === "fieldDesign"
        ? this.controls.fieldInputs.signature
        : "") +
      (this.draft?.kind === "fieldDesign"
        ? this.controls.widgetInputs.signature
        : "") +
      (this.draft?.kind === "newInk"
        ? this.controls.inkInputs.signatureKey
        : "")
    );
  }
  private draftValue(): string | boolean | string[] {
    if (!this.controls.fieldChoice.hidden)
      return this.draft?.kind === "field" &&
        this.view.state.fields.find((field) => field.id === this.draft?.id)
          ?.kind === "list"
        ? Array.from(
            this.controls.fieldChoice.selectedOptions,
            (option) => option.value,
          )
        : this.controls.fieldChoice.value;
    return typeof this.draft?.original === "boolean"
      ? this.controls.checked.checked
      : this.controls.text.value;
  }
  private dirty(): boolean {
    if (!this.draft) return false;
    const value = this.draftValue();
    return (
      JSON.stringify(value) !== JSON.stringify(this.draft.original) ||
      (this.draft.originalSpec !== undefined &&
        this.draftSignature() !== this.draft.originalSpec) ||
      ((this.draft.kind === "note" || this.draft.kind === "fieldCopy") &&
        (this.controls.x.value !== "20" || this.controls.y.value !== "20"))
    );
  }
  private checkDraft(): void {
    if (this.controls.inkInputs.dragging || this.objectDrag.dragging)
      throw new Error(
        "Finish or cancel the current pointer gesture before this operation",
      );
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
  private checkClose(): void {
    if (this.controls.inkInputs.dragging || this.objectDrag.dragging)
      throw new Error("Finish or cancel the pointer gesture before closing");
    if (!this.applying) this.checkDraft();
    else if (this.composing)
      throw new Error("Finish or cancel composition before closing");
  }
  private stateChanged(): void {
    this.draft = undefined;
    this.controls.text.value = "";
    this.showDraft();
    this.updateButtons();
  }
  private updateButtons(): void {
    this.view.publish();
  }
  private showDraft(): void {
    const draft = this.draft;
    const field =
      draft?.kind === "field"
        ? this.view.state.fields.find((field) => field.id === draft.id)
        : undefined;
    const annotation =
      draft?.kind === "annotation"
        ? this.view.state.annotations.find((item) => item.id === draft.id)
        : undefined;
    this.propertyReason =
      (this.client.readOnly ? viewOnlyReason : "") ||
      this.view.state.readOnlyReason ||
      field?.readOnlyReason ||
      annotation?.readOnlyReason ||
      draft?.reason ||
      "";
    renderPdfPropertyDraft(
      this.controls,
      draft,
      field,
      this.view.paused,
      this.applying,
      this.propertyReason,
      this.objectDrag,
    );
    this.updateButtons();
  }
  private async chooseNow(value: string): Promise<void> {
    this.draft = await propertyDraft(
      value,
      this.controls,
      this.view.state,
      this.client,
      this.profile,
      (page) => this.view.paint(page),
    );
    this.showDraft();
  }
  cancelDraft(): void {
    if (this.composing || this.applying)
      throw new Error(
        "Finish composition or the accepted edit before cancelling",
      );
    this.objectDrag.cancel();
    this.draft = undefined;
    this.controls.text.value = "";
    this.controls.checked.checked = false;
    this.controls.x.value = this.controls.y.value = "20";
    this.showDraft();
  }
  private async commit(
    command: (revision: number) => EditCommand | Promise<EditCommand>,
  ): Promise<PdfQuery> {
    return this.view.enqueue(async () => {
      const request = await command(this.view.state.revision);
      if (
        this.view.stopped &&
        !["undoPdf", "redoPdf"].includes(request.operation)
      )
        throw new Error("Refresh or undo before further PDF edits");
      const before = this.view.state;
      const state = await this.client.execute(request);
      if (request.operation === "setPdfFieldValue") {
        const field = state.fields.find(({ id }) => id === request.field);
        if (field)
          this.thumbnailRevisions.update(
            before.revision,
            state.revision,
            field.widgets.map(({ page }) => page),
          );
      } else if (request.operation === "replacePdfText") {
        this.thumbnailRevisions.update(before.revision, state.revision, [
          request.page,
        ]);
      }
      this.view.state = state;
      this.view.retainSearch();
      this.draft = undefined;
      this.controls.text.value = "";
      if (!this.view.closing && !this.view.closed) await this.view.paint();
      return state;
    });
  }
  async applyDraft(): Promise<void> {
    if (
      this.composing ||
      this.applying ||
      this.objectDrag.dragging ||
      this.controls.inkInputs.dragging
    )
      throw new Error("Finish composition or the accepted edit first");
    const draft = this.draft;
    if (!draft) throw new Error("Choose a PDF property first");
    const value = this.draftValue();
    const x = Number(this.controls.x.value),
      y = Number(this.controls.y.value);
    const spec = this.controls.objectInputs.read(String(value), draft.role);
    const completion = Promise.withResolvers<void>();
    this.applicationDone = completion.promise;
    this.applying = true;
    this.cancelSearch();
    this.showDraft();
    try {
      await this.commit((revision) =>
        draftCommand(draft, value, spec, x, y, revision, this.profile, {
          crop:
            draft.kind === "imageCrop"
              ? this.controls.cropInputs.read()
              : undefined,
          drawing:
            draft.kind === "newDrawing" && draft.drawingKind
              ? this.controls.objectInputs.drawing(
                  draft.drawingKind,
                  String(value),
                  draft.arrow,
                )
              : undefined,
          field:
            draft.kind === "newField" || draft.kind === "fieldDesign"
              ? this.controls.fieldInputs.read(spec, value)
              : undefined,
          widgets:
            draft.kind === "fieldDesign"
              ? this.controls.widgetInputs.read()
              : undefined,
          style:
            draft.kind === "newInk" ||
            draft.kind === "annotationStyle" ||
            draft.kind === "annotationReply"
              ? this.controls.objectInputs.annotation(String(value))
              : undefined,
          ink:
            draft.kind === "newInk"
              ? this.controls.inkInputs.read()
              : undefined,
        }),
      );
    } finally {
      this.applying = false;
      completion.resolve();
      if (!this.view.closed && !this.view.closing) this.showDraft();
    }
  }
  beginPageGeometry(action: "crop" | "resize" | "scale"): Promise<void> {
    return this.beginDraft(
      () => pageGeometryDraft(this.controls, this.view.state, action),
      this.controls.objectInputs.inputs.width,
    );
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
  async save(): Promise<EditorOutput> {
    if (!this.applying) this.checkDraft();
    if (this.composing)
      throw new Error("Finish or cancel composition before saving");
    const applicationDone = this.applicationDone;
    return this.view.enqueue(async () => {
      await applicationDone;
      this.checkDraft();
      const output = await this.client.execute({
        operation: "savePdf",
        revision: this.view.state.revision,
      });
      return this.view.observable.output(output.revision, "pdf", output.bytes);
    }, true);
  }
  async close(): Promise<void> {
    try {
      await this.view.close();
      await this.dispose();
    } finally {
      if (!this.view.closed) this.showDraft();
    }
  }
  async dispose(): Promise<void> {
    if (!this.view.closed) this.checkClose();
    await this.view.dispose();
    this.objectDrag.dispose();
    this.controls.dispose();
    this.propertyInput.remove();
  }
}
