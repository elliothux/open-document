import { WasmSession, encodeBytes } from "./session.js";
import {
  xlsxShapes,
  checkXlsxShapeInsert,
  checkXlsxShapeSettings,
  type XlsxShapeKind,
  type XlsxShapeSettings,
} from "./xlsx-shapes.js";
import { record } from "./validation.js";
import { xlsxQuery, type XlsxQuery } from "./xlsx-query.js";
import {
  xlsxPictures,
  xlsxPictureResource,
  checkXlsxPictureSettings,
  type XlsxPictureSettings,
} from "./xlsx-pictures.js";

export class XlsxDrawingSession extends WasmSession {
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
