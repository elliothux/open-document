import { type EditState, checkDefaultTabStop } from "./docx-format.js";
import {
  type DocxShapes,
  checkDocxShapeEdit,
  type DocxShapeEdit,
} from "./docx-shape.js";
import {
  checkDocxPictureEdit,
  type DocxPictures,
  type DocxPictureEdit,
  checkDocxDrawingGesture,
  type DocxDrawingGestureCommand,
} from "./docx-picture.js";

import {
  checkDocxTableSize,
  checkDocxTableEdit,
  type DocxTableEdit,
} from "./docx-table.js";

import {
  checkFindOptions,
  type DocxFindOptions,
  type DocxSearchResult,
} from "./docx-search.js";

import type { DocxSelection } from "./docx-hit.js";

import type { DocxRuntime } from "./docx-session.js";
export const docxEditingCommands = {
  editState(session: DocxRuntime, _command: object): EditState {
    return session.call<EditState>({ operation: "editState" });
  },
  pictures(session: DocxRuntime, { revision }: { revision: number }) {
    return session.call<DocxPictures>({ operation: "docxPictures", revision });
  },
  shapes(session: DocxRuntime, { revision }: { revision: number }) {
    return session.call<DocxShapes>({ operation: "docxShapes", revision });
  },
  editShape(
    session: DocxRuntime,
    {
      revision,
      shape,
      profile = {},
    }: {
      revision: number;
      shape: DocxShapeEdit;
      profile?: Record<string, string> | undefined;
    },
  ): EditState {
    checkDocxShapeEdit(shape);
    return session.call<EditState>({
      operation: "editDocxShape",
      revision,
      shape,
      profile,
    });
  },
  drawingGesture(
    session: DocxRuntime,
    {
      revision,
      change,
      profile = {},
    }: {
      revision: number;
      change: DocxDrawingGestureCommand;
      profile?: Record<string, string> | undefined;
    },
  ) {
    checkDocxDrawingGesture(change);
    return session.call<EditState>({
      operation: "docxDrawingGesture",
      revision,
      change,
      profile,
    });
  },
  editPicture(
    session: DocxRuntime,
    {
      revision,
      picture,
      profile = {},
    }: {
      revision: number;
      picture: DocxPictureEdit;
      profile?: Record<string, string> | undefined;
    },
  ): EditState {
    checkDocxPictureEdit(picture);
    return session.call<EditState>({
      operation: "editDocxPicture",
      revision,
      picture,
      profile,
    });
  },
  insertTable(
    session: DocxRuntime,
    {
      revision,
      selection,
      rows,
      columns,
      profile,
    }: {
      revision: number;
      selection: DocxSelection;
      rows: number;
      columns: number;
      profile: Record<string, string>;
    },
  ): EditState {
    checkDocxTableSize(rows, columns);
    return session.call<EditState>({
      operation: "insertDocxTable",
      revision,
      selection,
      rows,
      columns,
      profile,
    });
  },
  setDefaultTabStop(
    session: DocxRuntime,
    { revision, interval }: { revision: number; interval: number | null },
  ): EditState {
    checkDefaultTabStop(interval);
    return session.call<EditState>({
      operation: "setDefaultTabStop",
      revision,
      interval,
    });
  },
  editTable(
    session: DocxRuntime,
    {
      revision,
      selection,
      change,
      profile = {},
    }: {
      revision: number;
      selection: DocxSelection;
      change: DocxTableEdit;
      profile?: Record<string, string> | undefined;
    },
  ): EditState {
    checkDocxTableEdit(change, session.inputLimits);
    return session.call<EditState>({
      operation: "editDocxTable",
      revision,
      selection,
      change,
      profile,
    });
  },
  tabDocx(
    session: DocxRuntime,
    {
      revision,
      backward = false,
    }: { revision: number; backward?: boolean | undefined },
  ): EditState {
    return session.call<EditState>({
      operation: "tabDocx",
      revision,
      backward,
    });
  },
  enterDocx(
    session: DocxRuntime,
    { revision }: { revision: number },
  ): EditState {
    return session.call<EditState>({ operation: "enterDocx", revision });
  },
  findDocx(
    session: DocxRuntime,
    {
      revision,
      text,
      options = {},
    }: {
      revision: number;
      text: string;
      options?: DocxFindOptions | undefined;
    },
  ): DocxSearchResult {
    checkFindOptions(options);
    return session.call<DocxSearchResult>({
      operation: "findDocx",
      revision,
      text,
      options,
    });
  },
  replaceDocxMatches(
    session: DocxRuntime,
    {
      revision,
      matches,
      text,
    }: { revision: number; matches: DocxSelection[]; text: string },
  ): EditState {
    return session.call<EditState>({
      operation: "replaceDocxMatches",
      revision,
      matches,
      text,
    });
  },
  beginComposition(
    session: DocxRuntime,
    { revision }: { revision: number },
  ): EditState {
    return session.call<EditState>({ operation: "beginComposition", revision });
  },
  updateComposition(
    session: DocxRuntime,
    {
      revision,
      compositionId,
      text,
    }: { revision: number; compositionId: number; text: string },
  ): EditState {
    return session.call<EditState>({
      operation: "updateComposition",
      revision,
      compositionId,
      text,
    });
  },
  commitComposition(
    session: DocxRuntime,
    {
      revision,
      compositionId,
      text,
    }: { revision: number; compositionId: number; text: string },
  ): EditState {
    return session.call<EditState>({
      operation: "commitComposition",
      revision,
      compositionId,
      text,
    });
  },
  cancelComposition(
    session: DocxRuntime,
    { revision, compositionId }: { revision: number; compositionId: number },
  ): EditState {
    return session.call<EditState>({
      operation: "cancelComposition",
      revision,
      compositionId,
    });
  },
  replaceRange(
    session: DocxRuntime,
    {
      revision,
      selection,
      text,
      inputGroup,
    }: {
      revision: number;
      selection: DocxSelection;
      text: string;
      inputGroup?: number | undefined;
    },
  ): EditState {
    return session.call<EditState>({
      operation: "replaceRange",
      revision,
      selection,
      text,
      inputGroup,
    });
  },
  undoDocx(
    session: DocxRuntime,
    { revision }: { revision: number },
  ): EditState {
    return session.call<EditState>({ operation: "undoDocx", revision });
  },
  deleteDocx(
    session: DocxRuntime,
    {
      revision,
      direction,
    }: { revision: number; direction: "backward" | "forward" },
  ): EditState {
    return session.call<EditState>({
      operation: "deleteDocx",
      revision,
      direction,
    });
  },
  redoDocx(
    session: DocxRuntime,
    { revision }: { revision: number },
  ): EditState {
    return session.call<EditState>({ operation: "redoDocx", revision });
  },
  replaceNode(
    session: DocxRuntime,
    { node, revision, text }: { node: number; revision: number; text: string },
  ): number {
    return session.call<{ revision: number }>({
      operation: "replaceNode",
      node,
      revision,
      text,
    }).revision;
  },
  saveDocx(session: DocxRuntime, _command: object): Uint8Array {
    return session.bytes({ operation: "saveDocx" });
  },
};
