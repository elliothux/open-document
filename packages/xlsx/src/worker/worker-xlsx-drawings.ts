import type { XlsxSession } from "../core/xlsx.js";
import type { Operation } from "./protocol.js";
const drawingOperations = [
  "slicerGestureXlsx",
  "timelineGestureXlsx",
  "insertXlsxTimeline",
  "insertXlsxSlicer",
  "frameXlsxSlicer",
  "frameXlsxTimeline",
  "picturesXlsx",
  "captureDrawingXlsx",
  "drawingFragmentImageXlsx",
  "pasteDrawingXlsx",
  "shapesXlsx",
  "insertShapeXlsx",
  "setShapeXlsx",
  "deleteShapeXlsx",
  "pictureResourceXlsx",
  "selectDrawingXlsx",
  "drawingGestureXlsx",
  "imageBytesXlsx",
  "imageXlsx",
  "insertPictureXlsx",
  "replacePictureXlsx",
  "setPictureXlsx",
  "deletePictureXlsx",
  "getXlsxChart",
  "insertXlsxChart",
  "insertRangeXlsxChart",
  "setXlsxChart",
  "frameXlsxChart",
  "deleteXlsxChart",
] as const;
type DrawingOperation = Extract<
  Operation,
  { operation: (typeof drawingOperations)[number] }
>;
export function isXlsxDrawingRequest(
  request: Operation,
): request is DrawingOperation {
  return drawingOperations.some((operation) => operation === request.operation);
}
export function drawingOperation(
  workbook: XlsxSession | undefined,
  request: DrawingOperation,
): unknown {
  if (!workbook) throw new Error("Open an XLSX client first");
  switch (request.operation) {
    case "slicerGestureXlsx":
      return workbook.slicerGesture(
        request.revision,
        request.layout,
        request.objectId,
        {
          first: request.first,
          position: request.position,
          x: request.x,
          y: request.y,
          additive: request.additive,
          commit: request.commit,
        },
        request.profile,
      );
    case "timelineGestureXlsx":
      return workbook.timelineGesture(
        request.revision,
        request.layout,
        request.objectId,
        {
          handle: request.handle,
          first: request.first,
          position: request.position,
          x: request.x,
          y: request.y,
          commit: request.commit,
        },
        request.profile,
      );
    case "insertXlsxTimeline":
      return workbook.insertTimeline(
        request.revision,
        request.sheet,
        request.settings,
        request.profile,
      );
    case "frameXlsxSlicer":
      return workbook.setSlicerFrame(
        request.revision,
        request.sheet,
        request.objectId,
        request.frame,
        request.profile,
      );
    case "frameXlsxTimeline":
      return workbook.setTimelineFrame(
        request.revision,
        request.sheet,
        request.objectId,
        request.frame,
        request.profile,
      );
    case "insertXlsxSlicer":
      return workbook.insertSlicer(
        request.revision,
        request.sheet,
        request.settings,
        request.profile,
      );
    case "captureDrawingXlsx":
      return workbook.captureDrawing(
        request.revision,
        request.sheet,
        request.objectId,
        request.profile,
      );
    case "drawingFragmentImageXlsx":
      return workbook.drawingFragmentImage(request.revision, request.fragment);
    case "pasteDrawingXlsx":
      return workbook.pasteDrawing(
        request.revision,
        request.sheet,
        request.fragment,
        request.profile,
      );
    case "picturesXlsx":
      return workbook.pictures(
        request.revision,
        request.sheet,
        request.profile,
      );
    case "shapesXlsx":
      return workbook.shapes(request.revision, request.sheet, request.profile);
    case "insertShapeXlsx":
      return workbook.insertShape(
        request.revision,
        request.sheet,
        request.kind,
        request.width,
        request.height,
        request.text,
        request.profile,
      );
    case "setShapeXlsx":
      return workbook.setShape(
        request.revision,
        request.sheet,
        request.objectId,
        request.settings,
        request.profile,
      );
    case "deleteShapeXlsx":
      return workbook.deleteShape(
        request.revision,
        request.sheet,
        request.objectId,
        request.profile,
      );
    case "pictureResourceXlsx":
      return workbook.pictureResource(request.revision, request.bytes);
    case "selectDrawingXlsx":
      return workbook.selectDrawing(
        request.revision,
        request.layout,
        request.objectId,
      );
    case "drawingGestureXlsx":
      return workbook.drawingGesture(
        request.revision,
        request.layout,
        request,
        request.profile,
      );
    case "imageBytesXlsx":
      return workbook.imageBytes(request.revision, request.key);
    case "imageXlsx":
      return workbook.addImage(
        request.revision,
        request.key,
        request.width,
        request.height,
        request.bytes,
      );
    case "insertPictureXlsx":
      return workbook.insertPicture(
        request.revision,
        request.sheet,
        request.width,
        request.height,
        request.bytes,
        request.profile,
        request.name,
        request.description,
      );
    case "replacePictureXlsx":
      return workbook.replacePicture(
        request.revision,
        request.sheet,
        request.pictureId,
        request.bytes,
        request.profile,
      );
    case "setPictureXlsx":
      return workbook.setPicture(
        request.revision,
        request.sheet,
        request.pictureId,
        request.settings,
        request.profile,
      );
    case "deletePictureXlsx":
      return workbook.deletePicture(
        request.revision,
        request.sheet,
        request.pictureId,
        request.profile,
      );
    case "getXlsxChart":
      return workbook.charts(request.revision, request.sheet, request.profile);
    case "insertXlsxChart":
      return workbook.insertChart(
        request.revision,
        request.sheet,
        request.settings,
        request.width,
        request.height,
        request.profile,
      );
    case "insertRangeXlsxChart":
      return workbook.insertChartRange(
        request.revision,
        request.sheet,
        request.range,
        request.kind,
        request.title,
        request.width,
        request.height,
        request.profile,
      );
    case "setXlsxChart":
      return workbook.setChart(
        request.revision,
        request.sheet,
        request.chartId,
        request.settings,
        request.profile,
      );
    case "frameXlsxChart":
      return workbook.setChartFrame(
        request.revision,
        request.sheet,
        request.chartId,
        request.settings,
        request.profile,
      );
    case "deleteXlsxChart":
      return workbook.deleteChart(
        request.revision,
        request.sheet,
        request.chartId,
        request.profile,
      );
  }
}
