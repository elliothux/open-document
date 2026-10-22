import type { Connection } from "./connection.js";
import {
  drawingClipboard,
  checkDrawingFragment,
} from "@open-document/wasm/xlsx";
import {
  xlsxCharts,
  checkXlsxChartSettings,
  checkXlsxChartFrame,
  type XlsxChartSettings,
  type XlsxChartFrame,
} from "@open-document/wasm/xlsx";
import {
  xlsxShapes,
  checkXlsxShapeInsert,
  checkXlsxShapeSettings,
  type XlsxShapeKind,
  type XlsxShapeSettings,
} from "@open-document/wasm/xlsx";
import {
  xlsxQuery,
  xlsxPictures,
  xlsxPictureResource,
  checkXlsxPictureSettings,
  type XlsxPictureSettings,
  type XlsxQuery,
} from "@open-document/wasm/xlsx";

export class XlsxDrawingClient {
  constructor(protected readonly connection: Connection) {}
  async captureDrawing(
    revision: number,
    sheet: string,
    objectId: string,
    profile: Record<string, string>,
  ) {
    return drawingClipboard(
      await this.connection.request({
        operation: "captureDrawingXlsx",
        revision,
        sheet,
        objectId,
        profile,
      }),
    );
  }
  async drawingFragmentImage(
    revision: number,
    fragment: string,
  ): Promise<Uint8Array | null> {
    checkDrawingFragment(fragment);
    const image = await this.connection.request({
      operation: "drawingFragmentImageXlsx",
      revision,
      fragment,
    });
    if (
      image !== null &&
      (!(image instanceof Uint8Array) || image.length > 2097152)
    )
      throw new Error("Invalid drawing clipboard image");
    return image;
  }
  async pasteDrawing(
    revision: number,
    sheet: string,
    fragment: string,
    profile: Record<string, string>,
  ): Promise<XlsxQuery> {
    checkDrawingFragment(fragment);
    return xlsxQuery(
      await this.connection.request({
        operation: "pasteDrawingXlsx",
        revision,
        sheet,
        fragment,
        profile,
      }),
    );
  }
  async charts(
    revision: number,
    sheet: string,
    profile: Record<string, string>,
  ) {
    return xlsxCharts(
      await this.connection.request({
        operation: "getXlsxChart",
        revision,
        sheet,
        profile,
      }),
    );
  }
  async insertChart(
    revision: number,
    sheet: string,
    settings: XlsxChartSettings,
    width: number,
    height: number,
    profile: Record<string, string>,
  ): Promise<XlsxQuery> {
    checkXlsxChartSettings(settings);
    return xlsxQuery(
      await this.connection.request({
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
  async insertChartRange(
    revision: number,
    sheet: string,
    range: string,
    kind: XlsxChartSettings["kind"],
    title: string,
    width: number,
    height: number,
    profile: Record<string, string>,
  ): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({
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
  async setChart(
    revision: number,
    sheet: string,
    id: string,
    settings: XlsxChartSettings,
    profile: Record<string, string>,
  ): Promise<XlsxQuery> {
    checkXlsxChartSettings(settings);
    return xlsxQuery(
      await this.connection.request({
        operation: "setXlsxChart",
        revision,
        sheet,
        chartId: id,
        settings,
        profile,
      }),
    );
  }
  async setChartFrame(
    revision: number,
    sheet: string,
    id: string,
    settings: XlsxChartFrame,
    profile: Record<string, string>,
  ): Promise<XlsxQuery> {
    checkXlsxChartFrame(settings);
    return xlsxQuery(
      await this.connection.request({
        operation: "frameXlsxChart",
        revision,
        sheet,
        chartId: id,
        settings,
        profile,
      }),
    );
  }
  async deleteChart(
    revision: number,
    sheet: string,
    id: string,
    profile: Record<string, string>,
  ): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({
        operation: "deleteXlsxChart",
        revision,
        sheet,
        chartId: id,
        profile,
      }),
    );
  }
  async shapes(
    revision: number,
    sheet: string,
    profile: Record<string, string>,
  ) {
    return xlsxShapes(
      await this.connection.request({
        operation: "shapesXlsx",
        revision,
        sheet,
        profile,
      }),
    );
  }
  async insertShape(
    revision: number,
    sheet: string,
    kind: XlsxShapeKind,
    width: number,
    height: number,
    text: string,
    profile: Record<string, string>,
  ): Promise<XlsxQuery> {
    checkXlsxShapeInsert(kind, width, height, text);
    return xlsxQuery(
      await this.connection.request({
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
  async setShape(
    revision: number,
    sheet: string,
    id: string,
    settings: XlsxShapeSettings,
    profile: Record<string, string>,
  ): Promise<XlsxQuery> {
    checkXlsxShapeSettings(settings);
    return xlsxQuery(
      await this.connection.request({
        operation: "setShapeXlsx",
        revision,
        sheet,
        objectId: id,
        settings,
        profile,
      }),
    );
  }
  async deleteShape(
    revision: number,
    sheet: string,
    id: string,
    profile: Record<string, string>,
  ): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({
        operation: "deleteShapeXlsx",
        revision,
        sheet,
        objectId: id,
        profile,
      }),
    );
  }
  async pictures(
    revision: number,
    sheet: string,
    profile: Record<string, string>,
  ) {
    return xlsxPictures(
      await this.connection.request({
        operation: "picturesXlsx",
        revision,
        sheet,
        profile,
      }),
    );
  }
  async pictureResource(revision: number, bytes: Uint8Array) {
    if (bytes.length > 2097152) throw new Error("Picture input exceeds2MiB");
    return xlsxPictureResource(
      await this.connection.request({
        operation: "pictureResourceXlsx",
        revision,
        bytes,
      }),
    );
  }
  async imageBytes(revision: number, key: string): Promise<Uint8Array> {
    const result = await this.connection.request({
      operation: "imageBytesXlsx",
      revision,
      key,
    });
    if (!(result instanceof Uint8Array))
      throw new Error("Invalid worksheet image bytes");
    return result;
  }
  async addImage(
    revision: number,
    key: string,
    width: number,
    height: number,
    bytes: Uint8Array,
  ): Promise<string> {
    const result = await this.connection.request({
      operation: "imageXlsx",
      revision,
      key,
      width,
      height,
      bytes,
    });
    if (typeof result !== "string" || !result)
      throw new Error("Invalid worksheet image identity");
    return result;
  }
  async insertPicture(
    revision: number,
    sheet: string,
    width: number,
    height: number,
    bytes: Uint8Array,
    profile: Record<string, string>,
    name = "Picture",
    description = "",
  ): Promise<XlsxQuery> {
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
    return xlsxQuery(
      await this.connection.request({
        operation: "insertPictureXlsx",
        revision,
        sheet,
        width,
        height,
        bytes,
        profile,
        name,
        description,
      }),
    );
  }
  async replacePicture(
    revision: number,
    sheet: string,
    id: string,
    bytes: Uint8Array,
    profile: Record<string, string>,
  ): Promise<XlsxQuery> {
    if (bytes.length > 2097152) throw new Error("Picture input exceeds2MiB");
    return xlsxQuery(
      await this.connection.request({
        operation: "replacePictureXlsx",
        revision,
        sheet,
        pictureId: id,
        bytes,
        profile,
      }),
    );
  }
  async setPicture(
    revision: number,
    sheet: string,
    id: string,
    settings: XlsxPictureSettings,
    profile: Record<string, string>,
  ): Promise<XlsxQuery> {
    checkXlsxPictureSettings(settings);
    return xlsxQuery(
      await this.connection.request({
        operation: "setPictureXlsx",
        revision,
        sheet,
        pictureId: id,
        settings,
        profile,
      }),
    );
  }
  async deletePicture(
    revision: number,
    sheet: string,
    id: string,
    profile: Record<string, string>,
  ): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({
        operation: "deletePictureXlsx",
        revision,
        sheet,
        pictureId: id,
        profile,
      }),
    );
  }
}
