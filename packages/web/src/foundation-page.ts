import { FoundationReviewClient } from "./document-review.js";
import {
  docxRuler,
  checkDocxRulerEdit,
  type DocxRuler,
  type DocxRulerEdit,
} from "@open-document/wasm/foundation";
import {
  checkPageSetup,
  checkDocxCoverPage,
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

/** Page commands retain the existing Worker and validation boundary. */
export class FoundationPageClient extends FoundationReviewClient {
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
    columns: DocxColumns | null,
    profile: Record<string, string>,
  ) {
    checkDocxColumns(columns);
    return editState(
      await this.connection.request({
        operation: "setPageColumns",
        revision,
        columns,
        profile,
      }),
    );
  }
  async setPageNumbering(
    revision: number,
    numbering: DocxPageNumbering | null,
    profile: Record<string, string>,
  ) {
    checkPageNumbering(numbering);
    return editState(
      await this.connection.request({
        operation: "setPageNumbering",
        revision,
        numbering,
        profile,
      }),
    );
  }
  async unlinkRunningArea(
    revision: number,
    kind: DocxRunningKind,
    variant: DocxRunningVariant,
    profile: Record<string, string>,
  ) {
    checkRunningKind(kind);
    checkRunningVariant(variant);
    return editState(
      await this.connection.request({
        operation: "unlinkRunningArea",
        revision,
        kind,
        variant,
        profile,
      }),
    );
  }
  async setRunningOptions(
    revision: number,
    first: boolean,
    even: boolean,
    profile: Record<string, string>,
  ) {
    checkRunningOptions(first, even);
    return editState(
      await this.connection.request({
        operation: "setRunningOptions",
        revision,
        first,
        even,
        profile,
      }),
    );
  }
  async pageSetup(revision: number) {
    return docxPageSettings(
      await this.connection.request({ operation: "pageSetup", revision }),
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
  async setPageBorders(revision: number, borders: DocxPageBorders | null) {
    checkPageBorders(borders);
    return editState(
      await this.connection.request({
        operation: "setPageBorders",
        revision,
        borders,
      }),
    );
  }
  async runningArea(
    revision: number,
    kind: DocxRunningKind,
    variant: DocxRunningVariant,
  ) {
    checkRunningKind(kind);
    checkRunningVariant(variant);
    return docxRunningArea(
      await this.connection.request({
        operation: "runningArea",
        revision,
        kind,
        variant,
      }),
    );
  }
  async setRunningArea(
    revision: number,
    kind: DocxRunningKind,
    variant: DocxRunningVariant,
    content: DocxRunningContent[],
    distance: number,
    profile: Record<string, string>,
  ) {
    checkRunningArea(kind, variant, content, distance);
    return editState(
      await this.connection.request({
        operation: "setRunningArea",
        revision,
        kind,
        variant,
        content,
        distance,
        profile,
      }),
    );
  }
}
