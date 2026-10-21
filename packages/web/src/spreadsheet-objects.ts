import type { XlsxClient, XlsxPictureSettings } from "./xlsx.js";
import type { XlsxQuery, XlsxSheetEdit } from "@open-document/wasm/xlsx";
import type { SpreadsheetCanvas } from "./spreadsheet-canvas.js";

/** Sheet structure and pictures use the host's draft barrier and ordered queue. */
export abstract class SpreadsheetObjects {
  protected abstract readonly client: XlsxClient;
  protected abstract readonly profile: Record<string, string>;
  protected abstract readonly surface: SpreadsheetCanvas;
  protected abstract read<T>(action: () => Promise<T>): Promise<T>;
  protected abstract change(action: () => Promise<XlsxQuery>): Promise<void>;
  abstract get currentState(): XlsxQuery;

  editSheet(change: XlsxSheetEdit, sheet?: string): Promise<void> {
    return this.change(() =>
      this.client.editSheet(
        this.currentState.revision,
        sheet ?? this.currentState.sheet,
        change,
      ),
    );
  }
  pictures() {
    return this.read(() =>
      this.client.pictures(
        this.currentState.revision,
        this.currentState.sheet,
        this.profile,
      ),
    );
  }
  insertPicture(
    bytes: Uint8Array,
    width: number,
    height: number,
    name = "Picture",
    description = "",
  ): Promise<void> {
    return this.change(async () => {
      const state = this.currentState;
      await this.surface.addPicture(this.client, state.revision, bytes);
      return this.client.insertPicture(
        state.revision,
        state.sheet,
        width,
        height,
        bytes,
        this.profile,
        name,
        description,
      );
    });
  }
  setPicture(id: string, settings: XlsxPictureSettings): Promise<void> {
    return this.change(() =>
      this.client.setPicture(
        this.currentState.revision,
        this.currentState.sheet,
        id,
        settings,
        this.profile,
      ),
    );
  }
  deletePicture(id: string): Promise<void> {
    return this.change(() =>
      this.client.deletePicture(
        this.currentState.revision,
        this.currentState.sheet,
        id,
        this.profile,
      ),
    );
  }
}
