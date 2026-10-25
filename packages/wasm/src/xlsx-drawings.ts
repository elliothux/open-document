import { encodeBytes } from "./session.js";
import { XlsxCommentsSession } from "./xlsx-comments.js";
import {
  checkDrawingFragment,
  drawingClipboard,
  drawingFragmentImage,
} from "./xlsx-drawing-clipboard.js";
import {
  xlsxCharts,
  checkXlsxChartSettings,
  checkXlsxChartFrame,
  type XlsxChartSettings,
  type XlsxChartFrame,
} from "./xlsx-charts.js";
import {
  xlsxShapes,
  checkXlsxShapeInsert,
  checkXlsxShapeSettings,
  type XlsxShapeKind,
  type XlsxShapeSettings,
} from "./xlsx-shapes.js";
import { record } from "./validation.js";
import {
  checkXlsxDrawingFrame,
  type XlsxDrawingFrame,
} from "./xlsx-drawing-frame.js";
import { xlsxQuery, type XlsxQuery } from "./xlsx-query.js";
import {
  checkXlsxTimelineGesture,
  type XlsxTimelineGesture,
} from "./xlsx-timeline.js";
import { xlsxAnalysisPreview } from "./xlsx-drawing-pointer.js";
import {
  checkXlsxSlicerGesture,
  type XlsxSlicerGesture,
} from "./xlsx-slicer.js";
import {
  xlsxPictures,
  xlsxPictureResource,
  checkXlsxPictureSettings,
  type XlsxPictureSettings,
} from "./xlsx-pictures.js";

export class XlsxDrawingSession extends XlsxCommentsSession {
  slicerGesture(
    revision: number,
    layout: number,
    id: string,
    gesture: XlsxSlicerGesture,
    profile: Record<string, string>,
  ) {
    checkXlsxSlicerGesture(gesture);
    return xlsxAnalysisPreview(
      this.call({
        operation: "slicerGestureXlsx",
        revision,
        layout,
        objectId: id,
        ...gesture,
        profile,
      }),
    );
  }
  timelineGesture(
    revision: number,
    layout: number,
    id: string,
    gesture: XlsxTimelineGesture,
    profile: Record<string, string>,
  ) {
    checkXlsxTimelineGesture(gesture);
    return xlsxAnalysisPreview(
      this.call({
        operation: "timelineGestureXlsx",
        revision,
        layout,
        objectId: id,
        ...gesture,
        profile,
      }),
    );
  }
  setTimelineFrame(
    revision: number,
    sheet: string,
    id: string,
    frame: XlsxDrawingFrame,
    profile: Record<string, string>,
  ): XlsxQuery {
    checkXlsxDrawingFrame(frame);
    return xlsxQuery(
      this.call({
        operation: "frameXlsxTimeline",
        revision,
        sheet,
        objectId: id,
        frame,
        profile,
      }),
    );
  }
  captureDrawing(
    revision: number,
    sheet: string,
    objectId: string,
    profile: Record<string, string>,
  ) {
    return drawingClipboard(
      this.call({
        operation: "captureDrawingXlsx",
        revision,
        sheet,
        objectId,
        profile,
      }),
    );
  }
  drawingFragmentImage(revision: number, fragment: string): Uint8Array | null {
    checkDrawingFragment(fragment);
    return drawingFragmentImage(
      this.call({ operation: "drawingFragmentImageXlsx", revision, fragment }),
    );
  }
  pasteDrawing(
    revision: number,
    sheet: string,
    fragment: string,
    profile: Record<string, string>,
  ): XlsxQuery {
    checkDrawingFragment(fragment);
    return xlsxQuery(
      this.call({
        operation: "pasteDrawingXlsx",
        revision,
        sheet,
        fragment,
        profile,
      }),
    );
  }
  charts(revision: number, sheet: string, profile: Record<string, string>) {
    return xlsxCharts(
      this.call({ operation: "getXlsxChart", revision, sheet, profile }),
    );
  }
  insertChart(
    revision: number,
    sheet: string,
    settings: XlsxChartSettings,
    width: number,
    height: number,
    profile: Record<string, string>,
  ): XlsxQuery {
    checkXlsxChartSettings(settings);
    return xlsxQuery(
      this.call({
        operation: "insertXlsxChart",
        revision,
        sheet,
        settings,
        width,
        height,
        profile,
      }),
    );
  }
  insertChartRange(
    revision: number,
    sheet: string,
    range: string,
    kind: XlsxChartSettings["kind"],
    title: string,
    width: number,
    height: number,
    profile: Record<string, string>,
  ): XlsxQuery {
    return xlsxQuery(
      this.call({
        operation: "insertRangeXlsxChart",
        revision,
        sheet,
        range,
        kind,
        title,
        width,
        height,
        profile,
      }),
    );
  }
  setChart(
    revision: number,
    sheet: string,
    id: string,
    settings: XlsxChartSettings,
    profile: Record<string, string>,
  ): XlsxQuery {
    checkXlsxChartSettings(settings);
    return xlsxQuery(
      this.call({
        operation: "setXlsxChart",
        revision,
        sheet,
        id,
        settings,
        profile,
      }),
    );
  }
  setChartFrame(
    revision: number,
    sheet: string,
    id: string,
    settings: XlsxChartFrame,
    profile: Record<string, string>,
  ): XlsxQuery {
    checkXlsxChartFrame(settings);
    return xlsxQuery(
      this.call({
        operation: "frameXlsxChart",
        revision,
        sheet,
        id,
        settings,
        profile,
      }),
    );
  }
  deleteChart(
    revision: number,
    sheet: string,
    id: string,
    profile: Record<string, string>,
  ): XlsxQuery {
    return xlsxQuery(
      this.call({ operation: "deleteXlsxChart", revision, sheet, id, profile }),
    );
  }
  shapes(revision: number, sheet: string, profile: Record<string, string>) {
    return xlsxShapes(
      this.call({ operation: "shapesXlsx", revision, sheet, profile }),
    );
  }
  insertShape(
    revision: number,
    sheet: string,
    kind: XlsxShapeKind,
    width: number,
    height: number,
    text: string,
    profile: Record<string, string>,
  ): XlsxQuery {
    checkXlsxShapeInsert(kind, width, height, text);
    return xlsxQuery(
      this.call({
        operation: "insertShapeXlsx",
        revision,
        sheet,
        kind,
        width,
        height,
        text,
        profile,
      }),
    );
  }
  setShape(
    revision: number,
    sheet: string,
    id: string,
    settings: XlsxShapeSettings,
    profile: Record<string, string>,
  ): XlsxQuery {
    checkXlsxShapeSettings(settings);
    return xlsxQuery(
      this.call({
        operation: "setShapeXlsx",
        revision,
        sheet,
        id,
        settings,
        profile,
      }),
    );
  }
  deleteShape(
    revision: number,
    sheet: string,
    id: string,
    profile: Record<string, string>,
  ): XlsxQuery {
    return xlsxQuery(
      this.call({ operation: "deleteShapeXlsx", revision, sheet, id, profile }),
    );
  }
  pictures(revision: number, sheet: string, profile: Record<string, string>) {
    return xlsxPictures(
      this.call({ operation: "picturesXlsx", revision, sheet, profile }),
    );
  }
  pictureResource(revision: number, bytes: Uint8Array) {
    if (bytes.length > 2097152) throw new Error("Picture input exceeds2MiB");
    return xlsxPictureResource(
      this.call({
        operation: "pictureResourceXlsx",
        revision,
        bytes: encodeBytes(bytes),
      }),
    );
  }
  imageBytes(revision: number, key: string): Uint8Array {
    return this.bytes({ operation: "imageBytesXlsx", revision, key });
  }
  addImage(
    revision: number,
    key: string,
    width: number,
    height: number,
    bytes: Uint8Array,
  ): string {
    const result = record(
      this.call({
        operation: "imageXlsx",
        revision,
        key,
        width,
        height,
        bytes: encodeBytes(bytes),
      }),
    );
    if (typeof result.key !== "string" || !result.key)
      throw new Error("Invalid worksheet image resource");
    return result.key;
  }
  insertPicture(
    revision: number,
    sheet: string,
    width: number,
    height: number,
    bytes: Uint8Array,
    profile: Record<string, string>,
    name = "Picture",
    description = "",
  ): XlsxQuery {
    checkXlsxPictureSettings({
      anchor: "move",
      crop: [0, 0, 0, 0],
      x: 0,
      y: 0,
      width,
      height,
      name,
      description,
    });
    if (bytes.length > 2097152) throw new Error("Picture input exceeds2MiB");
    return xlsxQuery(
      this.call({
        operation: "insertPictureXlsx",
        revision,
        sheet,
        width,
        height,
        bytes: encodeBytes(bytes),
        profile,
        name,
        description,
      }),
    );
  }
  replacePicture(
    revision: number,
    sheet: string,
    id: string,
    bytes: Uint8Array,
    profile: Record<string, string>,
  ): XlsxQuery {
    if (bytes.length > 2097152) throw new Error("Picture input exceeds2MiB");
    return xlsxQuery(
      this.call({
        operation: "replacePictureXlsx",
        revision,
        sheet,
        id,
        bytes: encodeBytes(bytes),
        profile,
      }),
    );
  }
  setPicture(
    revision: number,
    sheet: string,
    id: string,
    settings: XlsxPictureSettings,
    profile: Record<string, string>,
  ): XlsxQuery {
    checkXlsxPictureSettings(settings);
    return xlsxQuery(
      this.call({
        operation: "setPictureXlsx",
        revision,
        sheet,
        id,
        settings,
        profile,
      }),
    );
  }
  deletePicture(
    revision: number,
    sheet: string,
    id: string,
    profile: Record<string, string>,
  ): XlsxQuery {
    return xlsxQuery(
      this.call({
        operation: "deletePictureXlsx",
        revision,
        sheet,
        id,
        profile,
      }),
    );
  }
}
