import type { XlsxDrawingClipboard } from "./xlsx-drawing-clipboard.js";
import {
  type XlsxCharts,
  checkXlsxChartSettings,
  checkXlsxChartFrame,
  type XlsxChartSettings,
  type XlsxChartFrame,
} from "./xlsx-charts.js";
import {
  type XlsxShapes,
  checkXlsxShapeInsert,
  checkXlsxShapeSettings,
  type XlsxShapeKind,
  type XlsxShapeSettings,
} from "./xlsx-shapes.js";
import {
  checkXlsxDrawingFrame,
  type XlsxDrawingFrame,
} from "./xlsx-drawing-frame.js";
import { type XlsxQuery } from "./xlsx-query.js";
import {
  checkXlsxTimelineGesture,
  type XlsxTimelineGesture,
} from "./xlsx-timeline.js";
import { type XlsxAnalysisPreview } from "./xlsx-drawing-pointer.js";
import {
  checkXlsxSlicerGesture,
  type XlsxSlicerGesture,
} from "./xlsx-slicer.js";
import {
  type XlsxPictures,
  checkXlsxPictureSettings,
  type XlsxPictureSettings,
} from "./xlsx-pictures.js";
import type { XlsxRuntime } from "./xlsx-session.js";
import type { ImagePreparation } from "@open-document/wasm/abi/drawing";
export const xlsxDrawingCommands = {
  slicerGestureXlsx(
    session: XlsxRuntime,
    {
      revision,
      layout,
      id,
      gesture,
      profile,
    }: {
      revision: number;
      layout: number;
      id: string;
      gesture: XlsxSlicerGesture;
      profile: Record<string, string>;
    },
  ) {
    checkXlsxSlicerGesture(gesture);
    return session.call<XlsxAnalysisPreview>({
      operation: "slicerGestureXlsx",
      revision,
      layout,
      objectId: id,
      ...gesture,
      profile,
    });
  },
  timelineGestureXlsx(
    session: XlsxRuntime,
    {
      revision,
      layout,
      id,
      gesture,
      profile,
    }: {
      revision: number;
      layout: number;
      id: string;
      gesture: XlsxTimelineGesture;
      profile: Record<string, string>;
    },
  ) {
    checkXlsxTimelineGesture(gesture);
    return session.call<XlsxAnalysisPreview>({
      operation: "timelineGestureXlsx",
      revision,
      layout,
      objectId: id,
      ...gesture,
      profile,
    });
  },
  frameXlsxTimeline(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      id,
      frame,
      profile,
    }: {
      revision: number;
      sheet: string;
      id: string;
      frame: XlsxDrawingFrame;
      profile: Record<string, string>;
    },
  ): XlsxQuery {
    checkXlsxDrawingFrame(frame);
    return session.call<XlsxQuery>({
      operation: "frameXlsxTimeline",
      revision,
      sheet,
      objectId: id,
      frame,
      profile,
    });
  },
  captureDrawingXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      objectId,
      profile,
    }: {
      revision: number;
      sheet: string;
      objectId: string;
      profile: Record<string, string>;
    },
  ) {
    return session.call<XlsxDrawingClipboard>({
      operation: "captureDrawingXlsx",
      revision,
      sheet,
      objectId,
      profile,
    });
  },
  drawingFragmentImageXlsx(
    session: XlsxRuntime,
    { revision, fragment }: { revision: number; fragment: string },
  ): Uint8Array | null {
    const { bytes } = session.call<{ bytes: number | null }>({
      operation: "drawingFragmentImageXlsx",
      revision,
      fragment,
    });
    return bytes === null ? null : session.outputBytes(bytes);
  },
  pasteDrawingXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      fragment,
      profile,
    }: {
      revision: number;
      sheet: string;
      fragment: string;
      profile: Record<string, string>;
    },
  ): XlsxQuery {
    return session.call<XlsxQuery>({
      operation: "pasteDrawingXlsx",
      revision,
      sheet,
      fragment,
      profile,
    });
  },
  getXlsxChart(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      profile,
    }: { revision: number; sheet: string; profile: Record<string, string> },
  ) {
    return session.call<XlsxCharts>({
      operation: "getXlsxChart",
      revision,
      sheet,
      profile,
    });
  },
  insertXlsxChart(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      settings,
      width,
      height,
      profile,
    }: {
      revision: number;
      sheet: string;
      settings: XlsxChartSettings;
      width: number;
      height: number;
      profile: Record<string, string>;
    },
  ): XlsxQuery {
    checkXlsxChartSettings(settings);
    return session.call<XlsxQuery>({
      operation: "insertXlsxChart",
      revision,
      sheet,
      settings,
      width,
      height,
      profile,
    });
  },
  insertRangeXlsxChart(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      range,
      kind,
      title,
      width,
      height,
      profile,
    }: {
      revision: number;
      sheet: string;
      range: string;
      kind: XlsxChartSettings["kind"];
      title: string;
      width: number;
      height: number;
      profile: Record<string, string>;
    },
  ): XlsxQuery {
    return session.call<XlsxQuery>({
      operation: "insertRangeXlsxChart",
      revision,
      sheet,
      range,
      kind,
      title,
      width,
      height,
      profile,
    });
  },
  setXlsxChart(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      id,
      settings,
      profile,
    }: {
      revision: number;
      sheet: string;
      id: string;
      settings: XlsxChartSettings;
      profile: Record<string, string>;
    },
  ): XlsxQuery {
    checkXlsxChartSettings(settings);
    return session.call<XlsxQuery>({
      operation: "setXlsxChart",
      revision,
      sheet,
      id,
      settings,
      profile,
    });
  },
  frameXlsxChart(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      id,
      settings,
      profile,
    }: {
      revision: number;
      sheet: string;
      id: string;
      settings: XlsxChartFrame;
      profile: Record<string, string>;
    },
  ): XlsxQuery {
    checkXlsxChartFrame(settings);
    return session.call<XlsxQuery>({
      operation: "frameXlsxChart",
      revision,
      sheet,
      id,
      settings,
      profile,
    });
  },
  deleteXlsxChart(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      id,
      profile,
    }: {
      revision: number;
      sheet: string;
      id: string;
      profile: Record<string, string>;
    },
  ): XlsxQuery {
    return session.call<XlsxQuery>({
      operation: "deleteXlsxChart",
      revision,
      sheet,
      id,
      profile,
    });
  },
  shapesXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      profile,
    }: { revision: number; sheet: string; profile: Record<string, string> },
  ) {
    return session.call<XlsxShapes>({
      operation: "shapesXlsx",
      revision,
      sheet,
      profile,
    });
  },
  insertShapeXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      kind,
      width,
      height,
      text,
      profile,
    }: {
      revision: number;
      sheet: string;
      kind: XlsxShapeKind;
      width: number;
      height: number;
      text: string;
      profile: Record<string, string>;
    },
  ): XlsxQuery {
    checkXlsxShapeInsert(kind, width, height, text);
    return session.call<XlsxQuery>({
      operation: "insertShapeXlsx",
      revision,
      sheet,
      kind,
      width,
      height,
      text,
      profile,
    });
  },
  setShapeXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      id,
      settings,
      profile,
    }: {
      revision: number;
      sheet: string;
      id: string;
      settings: XlsxShapeSettings;
      profile: Record<string, string>;
    },
  ): XlsxQuery {
    checkXlsxShapeSettings(settings);
    return session.call<XlsxQuery>({
      operation: "setShapeXlsx",
      revision,
      sheet,
      id,
      settings,
      profile,
    });
  },
  deleteShapeXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      id,
      profile,
    }: {
      revision: number;
      sheet: string;
      id: string;
      profile: Record<string, string>;
    },
  ): XlsxQuery {
    return session.call<XlsxQuery>({
      operation: "deleteShapeXlsx",
      revision,
      sheet,
      id,
      profile,
    });
  },
  picturesXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      profile,
    }: { revision: number; sheet: string; profile: Record<string, string> },
  ) {
    return session.call<XlsxPictures>({
      operation: "picturesXlsx",
      revision,
      sheet,
      profile,
    });
  },
  pictureResourceXlsx(
    session: XlsxRuntime,
    {
      revision,
      bytes,
      preparePixels,
    }: { revision: number; bytes: Uint8Array; preparePixels?: true },
  ) {
    const { bytes: slot, ...resource } = session.call<{
      revision: number;
      key: string;
      width: number;
      height: number;
      allowTranspose?: true;
      bytes?: number;
    }>({
      operation: "pictureResourceXlsx",
      revision,
      bytes,
      ...(preparePixels ? { preparePixels } : {}),
    });
    return {
      ...resource,
      ...(slot === undefined ? {} : { bytes: session.outputBytes(slot) }),
    };
  },
  prepareImageXlsx(
    session: XlsxRuntime,
    { revision, key }: { revision: number; key: string },
  ): ImagePreparation {
    const image = session.call<ImagePreparation<number>>({
      operation: "prepareImageXlsx",
      revision,
      key,
    });
    return { ...image, bytes: session.outputBytes(image.bytes) };
  },
  imageXlsx(
    session: XlsxRuntime,
    {
      revision,
      key,
      width,
      height,
      bytes,
    }: {
      revision: number;
      key: string;
      width: number;
      height: number;
      bytes: Uint8Array;
    },
  ): string {
    return session.call<{ key: string }>({
      operation: "imageXlsx",
      revision,
      key,
      width,
      height,
      bytes,
    }).key;
  },
  insertPictureXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      width,
      height,
      bytes,
      profile,
      name = "Picture",
      description = "",
    }: {
      revision: number;
      sheet: string;
      width: number;
      height: number;
      bytes: Uint8Array;
      profile: Record<string, string>;
      name?: string | undefined;
      description?: string | undefined;
    },
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
    return session.call<XlsxQuery>({
      operation: "insertPictureXlsx",
      revision,
      sheet,
      width,
      height,
      bytes,
      profile,
      name,
      description,
    });
  },
  replacePictureXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      id,
      bytes,
      profile,
    }: {
      revision: number;
      sheet: string;
      id: string;
      bytes: Uint8Array;
      profile: Record<string, string>;
    },
  ): XlsxQuery {
    return session.call<XlsxQuery>({
      operation: "replacePictureXlsx",
      revision,
      sheet,
      id,
      bytes,
      profile,
    });
  },
  setPictureXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      id,
      settings,
      profile,
    }: {
      revision: number;
      sheet: string;
      id: string;
      settings: XlsxPictureSettings;
      profile: Record<string, string>;
    },
  ): XlsxQuery {
    checkXlsxPictureSettings(settings);
    return session.call<XlsxQuery>({
      operation: "setPictureXlsx",
      revision,
      sheet,
      id,
      settings,
      profile,
    });
  },
  deletePictureXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      id,
      profile,
    }: {
      revision: number;
      sheet: string;
      id: string;
      profile: Record<string, string>;
    },
  ): XlsxQuery {
    return session.call<XlsxQuery>({
      operation: "deletePictureXlsx",
      revision,
      sheet,
      id,
      profile,
    });
  },
};
