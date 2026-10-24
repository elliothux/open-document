import { FoundationReviewClient } from "./document-review.js";
import {
  checkDocxIndexEdit,
  docxIndexes,
  type DocxIndexEdit,
} from "@open-document/wasm/foundation";
import {
  docxRuler,
  checkDocxRulerEdit,
  type DocxRuler,
  type DocxRulerEdit,
} from "@open-document/wasm/foundation";
import {
  checkPageSetup,
  checkPageSection,
  checkDocxCoverPage,
  checkDocxWatermark,
  docxWatermarkState,
  type DocxWatermark,
  checkDocxCaption,
  checkSectionBreak,
  type DocxSectionBreak,
  type DocxCaption,
  type DocxCoverPage,
  checkPageBackground,
  checkPageBorders,
  checkPageNumbering,
  checkDocxColumns,
  type DocxColumns,
  docxPageSettings,
  editState,
  checkRunningArea,
  checkRunningKind,
  checkRunningVariant,
  checkRunningOptions,
  docxRunningArea,
  type DocxPageSetup,
  type DocxPageBorders,
  type DocxPageNumbering,
  type DocxRunningKind,
  type DocxRunningVariant,
  type DocxRunningContent,
  type DocxBodyField,
  checkBodyField,
  docxBodyPageField,
  docxProtection,
  checkDocxProtection,
} from "@open-document/wasm/foundation";
import type { DocxSelection } from "@open-document/wasm/foundation";
import {
  checkDocxTocEdit,
  docxTableOfContents,
  type DocxTocEdit,
} from "@open-document/wasm/foundation";

/** Page commands retain the existing Worker and validation boundary. */
export class FoundationPageClient extends FoundationReviewClient {
  async insertSectionBreak(
    revision: number,
    kind: DocxSectionBreak,
    profile: Record<string, string>,
  ) {
    checkSectionBreak(kind);
    return editState(
      await this.connection.request({
        operation: "insertSectionBreak",
        revision,
        kind,
        profile,
      }),
    );
  }
  async tableOfContents(revision: number) {
    return docxTableOfContents(
      await this.connection.request({
        operation: "docxTableOfContents",
        revision,
      }),
    );
  }
  async indexes(revision: number) {
    return docxIndexes(
      await this.connection.request({ operation: "docxIndexes", revision }),
    );
  }
  async editIndex(
    revision: number,
    change: DocxIndexEdit,
    profile: Record<string, string>,
  ) {
    checkDocxIndexEdit(change);
    return editState(
      await this.connection.request({
        operation: "editDocxIndex",
        revision,
        change,
        profile,
      }),
    );
  }
  async editTableOfContents(
    revision: number,
    change: DocxTocEdit,
    profile: Record<string, string>,
  ) {
    checkDocxTocEdit(change);
    return editState(
      await this.connection.request({
        operation: "editDocxTableOfContents",
        revision,
        change,
        profile,
      }),
    );
  }
  async documentProtection(revision: number) {
    return docxProtection(
      await this.connection.request({
        operation: "documentProtection",
        revision,
      }),
    );
  }
  async setDocumentProtection(
    revision: number,
    enabled: boolean,
    password: string,
  ) {
    checkDocxProtection(enabled, password);
    return editState(
      await this.connection.request({
        operation: "setDocumentProtection",
        revision,
        enabled,
        password,
      }),
    );
  }
  async bodyPageField(revision: number, selection: DocxSelection) {
    return docxBodyPageField(
      await this.connection.request({
        operation: "bodyPageField",
        revision,
        selection,
      }),
    );
  }
  async editBodyPageField(
    revision: number,
    selection: DocxSelection,
    field: DocxBodyField,
    profile: Record<string, string>,
  ) {
    checkBodyField(field);
    return editState(
      await this.connection.request({
        operation: "editBodyPageField",
        revision,
        selection,
        field,
        profile,
      }),
    );
  }
  async insertBodyPageField(
    revision: number,
    field: DocxBodyField,
    profile: Record<string, string>,
  ) {
    checkBodyField(field);
    return editState(
      await this.connection.request({
        operation: "insertBodyPageField",
        revision,
        field,
        profile,
      }),
    );
  }
  async insertCaption(
    revision: number,
    caption: DocxCaption,
    profile: Record<string, string>,
  ) {
    checkDocxCaption(caption);
    return editState(
      await this.connection.request({
        operation: "insertDocxCaption",
        revision,
        caption,
        profile,
      }),
    );
  }
  async updateBodyPageFields(
    revision: number,
    profile: Record<string, string>,
  ) {
    return editState(
      await this.connection.request({
        operation: "updateBodyPageFields",
        revision,
        profile,
      }),
    );
  }
  async ruler(revision: number): Promise<DocxRuler> {
    return docxRuler(
      await this.connection.request({ operation: "docxRuler", revision }),
    );
  }
  async editRuler(source: DocxRuler, change: DocxRulerEdit) {
    docxRuler(source);
    checkDocxRulerEdit(change);
    return editState(
      await this.connection.request({
        operation: "editDocxRuler",
        source,
        change,
      }),
    );
  }
  async setPageColumns(
    revision: number,
    section: number,
    columns: DocxColumns | null,
    profile: Record<string, string>,
  ) {
    checkPageSection(section);
    checkDocxColumns(columns);
    return editState(
      await this.connection.request({
        operation: "setPageColumns",
        revision,
        section,
        columns,
        profile,
      }),
    );
  }
  async setPageNumbering(
    revision: number,
    section: number,
    numbering: DocxPageNumbering | null,
    profile: Record<string, string>,
  ) {
    checkPageSection(section);
    checkPageNumbering(numbering);
    return editState(
      await this.connection.request({
        operation: "setPageNumbering",
        revision,
        section,
        numbering,
        profile,
      }),
    );
  }
  async setRunningLink(
    revision: number,
    section: number,
    kind: DocxRunningKind,
    variant: DocxRunningVariant,
    linked: boolean,
    profile: Record<string, string>,
  ) {
    checkPageSection(section);
    if (typeof linked !== "boolean")
      throw new Error("Invalid running link state");
    checkRunningKind(kind);
    checkRunningVariant(variant);
    return editState(
      await this.connection.request({
        operation: "setRunningLink",
        revision,
        section,
        kind,
        variant,
        linked,
        profile,
      }),
    );
  }
  async setRunningOptions(
    revision: number,
    section: number,
    first: boolean,
    even: boolean,
    profile: Record<string, string>,
  ) {
    checkPageSection(section);
    checkRunningOptions(first, even);
    return editState(
      await this.connection.request({
        operation: "setRunningOptions",
        revision,
        section,
        first,
        even,
        profile,
      }),
    );
  }
  async pageSetup(revision: number, section = 0) {
    checkPageSection(section);
    return docxPageSettings(
      await this.connection.request({
        operation: "pageSetup",
        revision,
        section,
      }),
    );
  }
  async setPageSetup(revision: number, page: DocxPageSetup) {
    checkPageSetup(page);
    return editState(
      await this.connection.request({
        operation: "setPageSetup",
        revision,
        page,
      }),
    );
  }
  async setPageBackground(revision: number, color: string | null) {
    checkPageBackground(color);
    return editState(
      await this.connection.request({
        operation: "setPageBackground",
        revision,
        color,
      }),
    );
  }
  async watermark(revision: number, section: number) {
    checkPageSection(section);
    return docxWatermarkState(
      await this.connection.request({
        operation: "watermark",
        revision,
        section,
      }),
    );
  }
  async setWatermark(
    revision: number,
    section: number,
    value: DocxWatermark | null,
    profile: Record<string, string>,
  ) {
    checkPageSection(section);
    checkDocxWatermark(value);
    return editState(
      await this.connection.request({
        operation: "setWatermark",
        revision,
        section,
        value,
        profile,
      }),
    );
  }
  async setCoverPage(
    revision: number,
    cover: DocxCoverPage | null,
    profile: Record<string, string>,
  ) {
    checkDocxCoverPage(cover);
    return editState(
      await this.connection.request({
        operation: "setCoverPage",
        revision,
        cover,
        profile,
      }),
    );
  }
  async setPageBorders(
    revision: number,
    section: number,
    borders: DocxPageBorders | null,
  ) {
    checkPageSection(section);
    checkPageBorders(borders);
    return editState(
      await this.connection.request({
        operation: "setPageBorders",
        revision,
        section,
        borders,
      }),
    );
  }
  async runningArea(
    revision: number,
    section: number,
    kind: DocxRunningKind,
    variant: DocxRunningVariant,
  ) {
    checkPageSection(section);
    checkRunningKind(kind);
    checkRunningVariant(variant);
    return docxRunningArea(
      await this.connection.request({
        operation: "runningArea",
        revision,
        section,
        kind,
        variant,
      }),
    );
  }
  async setRunningArea(
    revision: number,
    section: number,
    kind: DocxRunningKind,
    variant: DocxRunningVariant,
    content: DocxRunningContent[],
    distance: number,
    profile: Record<string, string>,
  ) {
    checkPageSection(section);
    checkRunningArea(kind, variant, content, distance);
    return editState(
      await this.connection.request({
        operation: "setRunningArea",
        revision,
        section,
        kind,
        variant,
        content,
        distance,
        profile,
      }),
    );
  }
}
