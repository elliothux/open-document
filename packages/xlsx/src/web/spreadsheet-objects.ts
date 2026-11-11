import type { SpreadsheetHost } from "./spreadsheet-host.js";
import type { XlsxPivotSettings } from "../core/xlsx.js";
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
import type { XlsxSheetEdit } from "../core/xlsx.js";
import type { SpreadsheetCanvas } from "./spreadsheet-canvas.js";

/** Sheet structure and drawings use the host's draft barrier and ordered queue. */
export function createSpreadsheetObjects(
  client: XlsxClient,
  profile: Record<string, string>,
  surface: SpreadsheetCanvas,
  host: SpreadsheetHost,
) {
  return {
    pivots() {
      return host.read(() => {
        const { revision, sheet } = host.state();
        return client.execute({ operation: "pivotsXlsx", revision, sheet });
      });
    },
    slicers() {
      return host.read(() => {
        const { revision, sheet } = host.state();
        return client.execute({ operation: "slicersXlsx", revision, sheet });
      });
    },
    pivotPreview(settings: XlsxPivotSettings, part?: string) {
      return host.read(() =>
        client.execute({
          operation: "pivotPreviewXlsx",
          revision: host.state().revision,
          settings: settings,
          part: part,
        }),
      );
    },
    threads(cell?: string) {
      return host.read(() =>
        client.execute({
          operation: "threadsXlsx",
          revision: host.state().revision,
          sheet: host.state().sheet,
          cell: cell ?? host.state().selection.address.split(":")[0]!,
        }),
      );
    },
    editThread(change: XlsxThreadEdit): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "editThreadXlsx",
          revision: host.state().revision,
          sheet: host.state().sheet,
          change: change,
        }),
      );
    },
    timelines() {
      return host.read(() =>
        client.execute({
          operation: "timelinesXlsx",
          revision: host.state().revision,
          sheet: host.state().sheet,
        }),
      );
    },
    insertTimeline(settings: XlsxTimelineSettings): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "insertXlsxTimeline",
          revision: host.state().revision,
          sheet: host.state().sheet,
          settings: settings,
          profile: profile,
        }),
      );
    },
    insertSlicer(settings: XlsxSlicerSettings): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "insertXlsxSlicer",
          revision: host.state().revision,
          sheet: host.state().sheet,
          settings: settings,
          profile: profile,
        }),
      );
    },
    setSlicerFrame(id: string, frame: XlsxDrawingFrame): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "frameXlsxSlicer",
          revision: host.state().revision,
          sheet: host.state().sheet,
          id: id,
          frame: frame,
          profile: profile,
        }),
      );
    },
    setTimelineFrame(id: string, frame: XlsxDrawingFrame): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "frameXlsxTimeline",
          revision: host.state().revision,
          sheet: host.state().sheet,
          id: id,
          frame: frame,
          profile: profile,
        }),
      );
    },
    charts() {
      return host.read(() =>
        client.execute({
          operation: "getXlsxChart",
          revision: host.state().revision,
          sheet: host.state().sheet,
          profile: profile,
        }),
      );
    },
    insertChart(
      settings: XlsxChartSettings,
      width: number,
      height: number,
    ): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "insertXlsxChart",
          revision: host.state().revision,
          sheet: host.state().sheet,
          settings: settings,
          width: width,
          height: height,
          profile: profile,
        }),
      );
    },
    insertChartRange(
      range: string,
      kind: XlsxChartSettings["kind"],
      title: string,
      width: number,
      height: number,
    ): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "insertRangeXlsxChart",
          revision: host.state().revision,
          sheet: host.state().sheet,
          range: range,
          kind: kind,
          title: title,
          width: width,
          height: height,
          profile: profile,
        }),
      );
    },
    setChart(id: string, settings: XlsxChartSettings): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "setXlsxChart",
          revision: host.state().revision,
          sheet: host.state().sheet,
          id: id,
          settings: settings,
          profile: profile,
        }),
      );
    },
    setChartFrame(id: string, settings: XlsxChartFrame): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "frameXlsxChart",
          revision: host.state().revision,
          sheet: host.state().sheet,
          id: id,
          settings: settings,
          profile: profile,
        }),
      );
    },
    deleteChart(id: string): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "deleteXlsxChart",
          revision: host.state().revision,
          sheet: host.state().sheet,
          id: id,
          profile: profile,
        }),
      );
    },
    shapes() {
      return host.read(() =>
        client.execute({
          operation: "shapesXlsx",
          revision: host.state().revision,
          sheet: host.state().sheet,
          profile: profile,
        }),
      );
    },
    insertShape(
      kind: XlsxShapeKind,
      width: number,
      height: number,
      text: string,
    ): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "insertShapeXlsx",
          revision: host.state().revision,
          sheet: host.state().sheet,
          kind: kind,
          width: width,
          height: height,
          text: text,
          profile: profile,
        }),
      );
    },
    setShape(id: string, settings: XlsxShapeSettings): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "setShapeXlsx",
          revision: host.state().revision,
          sheet: host.state().sheet,
          id: id,
          settings: settings,
          profile: profile,
        }),
      );
    },
    deleteShape(id: string): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "deleteShapeXlsx",
          revision: host.state().revision,
          sheet: host.state().sheet,
          id: id,
          profile: profile,
        }),
      );
    },
    select(range: string, sheet = host.state().sheet): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "selectXlsx",
          revision: host.state().revision,
          sheet: sheet,
          range: range,
        }),
      );
    },

    editSheet(change: XlsxSheetEdit, sheet?: string): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "editXlsxSheet",
          revision: host.state().revision,
          sheet: sheet ?? host.state().sheet,
          change: change,
        }),
      );
    },
    pictures() {
      return host.read(() =>
        client.execute({
          operation: "picturesXlsx",
          revision: host.state().revision,
          sheet: host.state().sheet,
          profile: profile,
        }),
      );
    },
    insertPicture(
      bytes: Uint8Array,
      width: number,
      height: number,
      name = "Picture",
      description = "",
    ): Promise<void> {
      return host.change(async () => {
        const state = host.state();
        await surface.addPicture(client, state.revision, bytes);
        return client.execute({
          operation: "insertPictureXlsx",
          revision: state.revision,
          sheet: state.sheet,
          width: width,
          height: height,
          bytes: bytes,
          profile: profile,
          name: name,
          description: description,
        });
      });
    },
    replacePicture(id: string, bytes: Uint8Array): Promise<void> {
      return host.change(async () => {
        const state = host.state();
        await surface.addPicture(client, state.revision, bytes);
        return client.execute({
          operation: "replacePictureXlsx",
          revision: state.revision,
          sheet: state.sheet,
          id: id,
          bytes: bytes,
          profile: profile,
        });
      });
    },
    setPicture(id: string, settings: XlsxPictureSettings): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "setPictureXlsx",
          revision: host.state().revision,
          sheet: host.state().sheet,
          id: id,
          settings: settings,
          profile: profile,
        }),
      );
    },
    deletePicture(id: string): Promise<void> {
      return host.change(() =>
        client.execute({
          operation: "deletePictureXlsx",
          revision: host.state().revision,
          sheet: host.state().sheet,
          id: id,
          profile: profile,
        }),
      );
    },
  };
}
