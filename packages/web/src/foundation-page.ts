import { FoundationReviewClient } from "./document-review.js";
import {
  checkPageSetup,
  checkPageBackground,
  checkPageBorders,
  docxPageSettings,
  editState,
  checkRunningArea,
  checkRunningKind,
  checkRunningVariant,
  checkRunningOptions,
  docxRunningArea,
  type DocxPageSetup,
  type DocxPageBorders,
  type DocxRunningKind,
  type DocxRunningVariant,
  type DocxRunningContent,
} from "@open-document/wasm/foundation";

/** Page commands retain the existing Worker and validation boundary. */
export class FoundationPageClient extends FoundationReviewClient {
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
