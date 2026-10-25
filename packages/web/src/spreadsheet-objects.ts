import type {
  XlsxClient,
  XlsxPictureSettings,
  XlsxShapeKind,
  XlsxShapeSettings,
  XlsxChartSettings,
  XlsxChartFrame,
  XlsxSlicerSettings,
  XlsxDrawingFrame,
  XlsxTimelineSettings,
  XlsxThreadEdit,
} from "./xlsx.js";
import type { XlsxQuery, XlsxSheetEdit } from "@open-document/wasm/xlsx";
import type { SpreadsheetCanvas } from "./spreadsheet-canvas.js";

/** Sheet structure and drawings use the host's draft barrier and ordered queue. */
export abstract class SpreadsheetObjects {
  protected abstract readonly client: XlsxClient;
  protected abstract readonly profile: Record<string, string>;
  protected abstract readonly surface: SpreadsheetCanvas;
  protected abstract read<T>(action: () => Promise<T>): Promise<T>;
  protected abstract change(action: () => Promise<XlsxQuery>): Promise<void>;
  abstract get currentState(): XlsxQuery;
  threads(cell?: string) {
    return this.read(() =>
      this.client.threads(
        this.currentState.revision,
        this.currentState.sheet,
        cell ?? this.currentState.selection.address.split(":")[0]!,
      ),
    );
  }
  editThread(change: XlsxThreadEdit): Promise<void> {
    return this.change(() =>
      this.client.editThread(
        this.currentState.revision,
        this.currentState.sheet,
        change,
      ),
    );
  }
  timelines() {
    return this.read(() =>
      this.client.timelines(
        this.currentState.revision,
        this.currentState.sheet,
      ),
    );
  }
  insertTimeline(settings: XlsxTimelineSettings): Promise<void> {
    return this.change(() =>
      this.client.insertTimeline(
        this.currentState.revision,
        this.currentState.sheet,
        settings,
        this.profile,
      ),
    );
  }
  insertSlicer(settings: XlsxSlicerSettings): Promise<void> {
    return this.change(() =>
      this.client.insertSlicer(
        this.currentState.revision,
        this.currentState.sheet,
        settings,
        this.profile,
      ),
    );
  }
  setSlicerFrame(id: string, frame: XlsxDrawingFrame): Promise<void> {
    return this.change(() =>
      this.client.setSlicerFrame(
        this.currentState.revision,
        this.currentState.sheet,
        id,
        frame,
        this.profile,
      ),
    );
  }
  setTimelineFrame(id: string, frame: XlsxDrawingFrame): Promise<void> {
    return this.change(() =>
      this.client.setTimelineFrame(
        this.currentState.revision,
        this.currentState.sheet,
        id,
        frame,
        this.profile,
      ),
    );
  }
  charts() {
    return this.read(() =>
      this.client.charts(
        this.currentState.revision,
        this.currentState.sheet,
        this.profile,
      ),
    );
  }
  insertChart(
    settings: XlsxChartSettings,
    width: number,
    height: number,
  ): Promise<void> {
    return this.change(() =>
      this.client.insertChart(
        this.currentState.revision,
        this.currentState.sheet,
        settings,
        width,
        height,
        this.profile,
      ),
    );
  }
  insertChartRange(
    range: string,
    kind: XlsxChartSettings["kind"],
    title: string,
    width: number,
    height: number,
  ): Promise<void> {
    return this.change(() =>
      this.client.insertChartRange(
        this.currentState.revision,
        this.currentState.sheet,
        range,
        kind,
        title,
        width,
        height,
        this.profile,
      ),
    );
  }
  setChart(id: string, settings: XlsxChartSettings): Promise<void> {
    return this.change(() =>
      this.client.setChart(
        this.currentState.revision,
        this.currentState.sheet,
        id,
        settings,
        this.profile,
      ),
    );
  }
  setChartFrame(id: string, settings: XlsxChartFrame): Promise<void> {
    return this.change(() =>
      this.client.setChartFrame(
        this.currentState.revision,
        this.currentState.sheet,
        id,
        settings,
        this.profile,
      ),
    );
  }
  deleteChart(id: string): Promise<void> {
    return this.change(() =>
      this.client.deleteChart(
        this.currentState.revision,
        this.currentState.sheet,
        id,
        this.profile,
      ),
    );
  }
  shapes() {
    return this.read(() =>
      this.client.shapes(
        this.currentState.revision,
        this.currentState.sheet,
        this.profile,
      ),
    );
  }
  insertShape(
    kind: XlsxShapeKind,
    width: number,
    height: number,
    text: string,
  ): Promise<void> {
    return this.change(() =>
      this.client.insertShape(
        this.currentState.revision,
        this.currentState.sheet,
        kind,
        width,
        height,
        text,
        this.profile,
      ),
    );
  }
  setShape(id: string, settings: XlsxShapeSettings): Promise<void> {
    return this.change(() =>
      this.client.setShape(
        this.currentState.revision,
        this.currentState.sheet,
        id,
        settings,
        this.profile,
      ),
    );
  }
  deleteShape(id: string): Promise<void> {
    return this.change(() =>
      this.client.deleteShape(
        this.currentState.revision,
        this.currentState.sheet,
        id,
        this.profile,
      ),
    );
  }
  select(range: string, sheet = this.currentState.sheet): Promise<void> {
    return this.change(() =>
      this.client.select(this.currentState.revision, sheet, range),
    );
  }

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
  replacePicture(id: string, bytes: Uint8Array): Promise<void> {
    return this.change(async () => {
      const state = this.currentState;
      await this.surface.addPicture(this.client, state.revision, bytes);
      return this.client.replacePicture(
        state.revision,
        state.sheet,
        id,
        bytes,
        this.profile,
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
