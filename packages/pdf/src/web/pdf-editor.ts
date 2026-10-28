import { propertyDraft } from "./pdf-property-draft.js";
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
import { PdfOperations } from "./pdf-operations.js";
import type { PdfClient } from "./pdf.js";
import type { EditorOutput } from "@open-document/web-core/editor-state";
import { pdfThumbnail } from "./pdf-thumbnail.js";
import { PdfPropertyInputs } from "./pdf-property-input.js";
import { PdfObjectDrag } from "./pdf-object-drag.js";
import { decodeImage } from "@open-document/web-core/image";

import { draftCommand, type Draft, type EditCommand } from "./pdf-draft.js";

/** Page operations and a native draft panel; PDF body text remains positioned. */
export class PdfEditor extends PdfOperations {
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
  private readonly controls = new PdfPropertyInputs(
    () => this.publish(),
    (active) => {
      this.composing = active;
      this.updateButtons();
    },
  );
  private readonly objectDrag = new PdfObjectDrag({
    view: () =>
      this.layout
        ? {
            canvas: this.surface.canvas,
            page: this.layout.page,
            scale: this.scale,
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
        this.paused ||
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
    change: () => this.publish(),
  });
  readonly propertyInput = this.controls.element;
  private propertyReason = "";
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
  protected override pauseChanged(): void {
    this.propertyInput.inert = this.paused;
    this.showDraft();
  }
  chooseProperty(value: string): Promise<void> {
    this.checkDraft();
    return this.enqueue(() => this.chooseNow(value));
  }
  private beginDraft(
    setup: () => Draft | Promise<Draft>,
    focus: HTMLElement = this.controls.text,
  ): Promise<void> {
    this.checkDraft();
    return this.enqueue(async () => {
      this.checkDraft();
      this.draft = await setup();
      this.showDraft();
      if (!this.closed && !this.closing) focus.focus();
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
        revision: this.state.revision,
        page: this.state.page,
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
        revision: this.state.revision,
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
      this.controls.widgetInputs.setPages(this.state.pages);
      this.controls.widgetInputs.set(details.widgets, spec.kind);
      const value = Array.isArray(spec.value)
        ? spec.value.join("\n")
        : spec.value;
      this.controls.text.value = typeof value === "boolean" ? "" : value;
      this.controls.checked.checked = value === true;
      return {
        kind: "fieldDesign",
        id: details.field,
        page: this.state.page,
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
        revision: this.state.revision,
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
    return this.enqueue(async () => {
      this.draft = {
        kind: "note",
        id: "",
        page: this.state.page,
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
      textDraft(this.controls, this.state, this.profile, role),
    );
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
    const placement = this.controls.objectInputs.read("").placement;
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
  beginDrawing(
    kind: PdfDrawingAnnotation["kind"],
    arrow = false,
  ): Promise<void> {
    return this.beginDraft(() =>
      drawingDraft(this.controls, this.state, kind, arrow),
    );
  }
  beginInk(signature = false): Promise<void> {
    return this.beginDraft(
      () => inkDraft(this.controls, this.state, signature),
      this.controls.inkInputs.pad,
    );
  }
  beginField(kind: PdfFieldDesign["kind"]): Promise<void> {
    return this.beginDraft(
      () => fieldDraft(this.controls, this.state, this.profile, kind),
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
    await this.enqueue(async () => {
      this.checkDraft();
      if (this.draft?.kind !== "field")
        throw new Error("Choose a field to rename");
      const field = this.state.fields.find(
        (field) => field.id === this.draft?.id,
      )!;
      this.draft = {
        kind,
        id: field.id,
        page: this.state.page,
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
    return this.removeField(this.draft.id);
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
        this.state.fields.find((field) => field.id === this.draft?.id)?.kind ===
          "list"
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
  protected override checkDraft(): void {
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
  protected override checkClose(): void {
    if (this.controls.inkInputs.dragging || this.objectDrag.dragging)
      throw new Error("Finish or cancel the pointer gesture before closing");
    if (!this.applying) this.checkDraft();
    else if (this.composing)
      throw new Error("Finish or cancel composition before closing");
  }
  protected override stateChanged(): void {
    this.draft = undefined;
    this.controls.text.value = "";
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
    this.controls.text.hidden =
      !draft ||
      typeof draft.original === "boolean" ||
      draft.kind === "objectGeometry" ||
      draft.kind === "pageGeometry" ||
      draft.kind === "imageCrop" ||
      (!!field && ["radio", "choice", "list"].includes(field.kind));
    this.controls.fieldChoice.hidden =
      !field || !["radio", "choice", "list"].includes(field.kind);
    this.controls.checked.hidden =
      !draft || typeof draft.original !== "boolean";
    this.controls.x.hidden = this.controls.y.hidden =
      draft?.kind !== "note" && draft?.kind !== "fieldCopy";
    for (const [input, axis] of [
      [this.controls.x, "horizontal"],
      [this.controls.y, "vertical"],
    ] as const) {
      input.min = draft?.kind === "fieldCopy" ? "-14400" : "0";
      const label =
        draft?.kind === "fieldCopy"
          ? `Field ${axis} offset`
          : `Note ${axis} position`;
      input.setAttribute("aria-label", label);
      const caption = input.parentElement?.querySelector("span");
      if (caption) caption.textContent = label;
    }
    for (const input of [
      this.controls.text,
      this.controls.checked,
      this.controls.fieldChoice,
      this.controls.x,
      this.controls.y,
    ])
      if (input.parentElement) input.parentElement.hidden = input.hidden;
    this.controls.text.rows = field?.multiline ? 4 : 2;
    this.controls.text.maxLength = field?.maxLength ?? 32767;
    this.controls.text.disabled = this.controls.checked.disabled =
      this.paused || this.applying || !!this.propertyReason;
    this.controls.x.disabled = this.controls.y.disabled =
      this.controls.text.disabled;
    this.controls.fieldChoice.disabled = this.controls.text.disabled;
    this.controls.fieldInputs.show(
      draft?.kind === "newField" || draft?.kind === "fieldDesign",
      this.controls.text.disabled,
      draft?.kind === "fieldDesign",
    );
    this.controls.widgetInputs.show(
      draft?.kind === "fieldDesign",
      this.controls.text.disabled,
    );
    this.controls.inkInputs.show(
      draft?.kind === "newInk",
      this.controls.text.disabled,
    );
    this.controls.cropInputs.show(
      draft?.kind === "imageCrop",
      this.controls.text.disabled,
    );
    this.controls.objectInputs.show(
      draft?.originalSpec !== undefined && draft.kind !== "imageCrop",
      draft?.kind !== "objectGeometry",
      this.controls.text.disabled,
      !draft?.id.includes("/source/"),
      draft?.kind === "newDrawing" ||
        draft?.kind === "newInk" ||
        draft?.kind === "annotationStyle" ||
        draft?.kind === "annotationReply",
      draft?.kind === "pageGeometry" ? draft.pageAction : undefined,
    );
    if (draft?.kind === "newField")
      for (const key of ["rotation", "foreground"] as const) {
        const label = this.controls.objectInputs.inputs[key].parentElement;
        if (label) label.hidden = true;
      }
    if (draft?.kind === "fieldDesign")
      for (const key of [
        "x",
        "y",
        "width",
        "height",
        "rotation",
        "foreground",
      ] as const) {
        const label = this.controls.objectInputs.inputs[key].parentElement;
        if (label) label.hidden = true;
      }
    if (
      draft?.kind === "newDrawing" ||
      draft?.kind === "newInk" ||
      draft?.kind === "annotationStyle"
    )
      for (const key of ["rotation", "points"] as const) {
        const label = this.controls.objectInputs.inputs[key].parentElement;
        if (label && (key !== "points" || draft.kind !== "newDrawing"))
          label.hidden = true;
      }
    if (draft?.kind === "annotationReply")
      for (const [key, control] of Object.entries(
        this.controls.objectInputs.inputs,
      )) {
        if (control.parentElement)
          control.parentElement.hidden = key !== "author";
      }
    const movable =
      !this.paused &&
      !this.applying &&
      !this.propertyReason &&
      (draft?.kind === "textObject" || draft?.kind === "objectGeometry");
    this.objectDrag.show(
      movable ? draft.page : undefined,
      movable ? draft.id : undefined,
    );
    this.updateButtons();
  }
  private async chooseNow(value: string): Promise<void> {
    this.draft = await propertyDraft(
      value,
      this.controls,
      this.state,
      this.client,
      this.profile,
      (page) => this.paint(page),
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
  protected override async commit(
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
      this.controls.text.value = "";
      if (!this.closing && !this.closed) await this.paint();
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
      if (!this.closed && !this.closing) this.showDraft();
    }
  }
  beginPageGeometry(action: "crop" | "resize" | "scale"): Promise<void> {
    return this.beginDraft(
      () => pageGeometryDraft(this.controls, this.state, action),
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
  override async dispose(): Promise<void> {
    if (!this.closed) this.checkClose();
    await super.dispose();
    this.objectDrag.dispose();
    this.controls.dispose();
    this.propertyInput.remove();
  }
}
