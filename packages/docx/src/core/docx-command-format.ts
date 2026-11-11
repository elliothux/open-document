import {
  type DocxCharts,
  checkDocxChartEdit,
  type DocxChartEdit,
} from "./docx-chart.js";
import {
  checkFormatPatch,
  checkDocxHyperlink,
  type EditState,
  type CreatedDocxStyle,
  type DocxStyleCatalog,
  copiedFormat,
  checkStyleUpdate,
  type CopiedFormat,
  type DocxStyleUpdate,
  type DocxStyleCreation,
  checkStyleCreation,
  type DocxFormatting,
  type CharacterFormatPatch,
  type ParagraphFormatPatch,
} from "./docx-format.js";

import {
  checkListLevelUpdate,
  type DocxListLevelUpdate,
} from "./docx-list-level.js";
import {
  checkListEdit,
  type DocxListEdit,
  type DocxListCatalog,
} from "./docx-list.js";
import { DocumentError } from "@open-document/wasm/abi/session";

import {
  type DocxThemeColors,
  checkDocxThemeColor,
  type DocxThemeSlot,
  type DocxThemeFonts,
  checkDocxThemeFonts,
  type DocxThemeFontEdit,
} from "./docx-theme.js";

import type { Budget } from "@open-document/wasm/abi/validation";
import type { DocxSelection } from "./docx-hit.js";

import { type ShapeBatch } from "@open-document/wasm/abi/shape";
import type { DocxQuery } from "./foundation.js";
import type { DocxRuntime } from "./docx-session.js";
export const docxFormatCommands = {
  charts(session: DocxRuntime, { revision }: { revision: number }) {
    return session.call<DocxCharts>({ operation: "docxCharts", revision });
  },
  editChart(
    session: DocxRuntime,
    {
      revision,
      chart,
      profile = {},
    }: {
      revision: number;
      chart: DocxChartEdit;
      profile?: Record<string, string> | undefined;
    },
  ): EditState {
    checkDocxChartEdit(chart);
    return session.call<EditState>({
      operation: "editDocxChart",
      revision,
      chart,
      profile,
    });
  },
  shape(
    session: DocxRuntime,
    {
      text,
      size = 32,
      language = "und",
    }: {
      text: string;
      size?: number | undefined;
      language?: string | undefined;
    },
  ): ShapeBatch {
    return session.call<ShapeBatch>({
      operation: "shape",
      text,
      size,
      language,
    });
  },
  openDocx(
    session: DocxRuntime,
    {
      bytes,
      budget,
      password,
    }: { bytes: Uint8Array; budget: Budget; password?: string | undefined },
  ): DocxQuery {
    if (bytes.length > budget.fileBytes || bytes.length > budget.retainedBytes)
      throw new DocumentError(
        "limit-exceeded",
        "Byte input exceeds budget",
        "",
        -1,
      );
    return session.call<DocxQuery>({
      operation: "openDocx",
      bytes,
      budget,
      password,
    });
  },
  query(session: DocxRuntime, _command: object): DocxQuery {
    return session.call<DocxQuery>({ operation: "query" });
  },
  createDocx(session: DocxRuntime, { budget }: { budget: Budget }): DocxQuery {
    return session.call<DocxQuery>({ operation: "createDocx", budget });
  },
  queryFormatting(
    session: DocxRuntime,
    { revision, selection }: { revision: number; selection: DocxSelection },
  ): DocxFormatting {
    return session.call<DocxFormatting>({
      operation: "queryFormatting",
      revision,
      selection,
    });
  },
  styles(
    session: DocxRuntime,
    { revision, kind }: { revision: number; kind: "paragraph" | "character" },
  ): DocxStyleCatalog {
    return session.call<DocxStyleCatalog>({
      operation: "styleCatalog",
      revision,
      kind,
    });
  },
  themeColors(session: DocxRuntime, { revision }: { revision: number }) {
    return session.call<DocxThemeColors>({
      operation: "docxThemeColors",
      revision,
    });
  },
  themeFonts(session: DocxRuntime, { revision }: { revision: number }) {
    return session.call<DocxThemeFonts>({
      operation: "docxThemeFonts",
      revision,
    });
  },
  setThemeFonts(
    session: DocxRuntime,
    {
      revision,
      fonts,
      profile,
    }: {
      revision: number;
      fonts: DocxThemeFontEdit[];
      profile: Record<string, string>;
    },
  ): EditState {
    checkDocxThemeFonts(fonts);
    return session.call<EditState>({
      operation: "setDocxThemeFonts",
      revision,
      fonts,
      profile,
    });
  },
  setThemeColor(
    session: DocxRuntime,
    {
      revision,
      slot,
      color,
    }: { revision: number; slot: DocxThemeSlot; color: string },
  ): EditState {
    checkDocxThemeColor(slot, color);
    return session.call<EditState>({
      operation: "setDocxThemeColor",
      revision,
      slot,
      color,
    });
  },
  lists(
    session: DocxRuntime,
    { revision }: { revision: number },
  ): DocxListCatalog {
    return session.call<DocxListCatalog>({
      operation: "listCatalog",
      revision,
    });
  },
  editList(
    session: DocxRuntime,
    {
      revision,
      selection,
      change,
    }: { revision: number; selection: DocxSelection; change: DocxListEdit },
  ): EditState {
    checkListEdit(change);
    return session.call<EditState>({
      operation: "editList",
      revision,
      selection,
      change,
    });
  },
  updateListLevel(
    session: DocxRuntime,
    {
      revision,
      id,
      level,
      definition,
    }: {
      revision: number;
      id: number;
      level: number;
      definition: DocxListLevelUpdate;
    },
  ): EditState {
    checkListLevelUpdate(id, level, definition);
    return session.call<EditState>({
      operation: "updateListLevel",
      revision,
      listId: id,
      level,
      definition,
    });
  },
  createStyle(
    session: DocxRuntime,
    { revision, style }: { revision: number; style: DocxStyleCreation },
  ): CreatedDocxStyle {
    checkStyleCreation(style);
    return session.call<CreatedDocxStyle>({
      operation: "createStyle",
      revision,
      ...style,
    });
  },
  deleteStyle(
    session: DocxRuntime,
    {
      revision,
      key,
      replacement,
    }: { revision: number; key: string; replacement: string },
  ): EditState {
    return session.call<EditState>({
      operation: "deleteStyle",
      revision,
      key,
      replacement,
    });
  },
  updateStyle(
    session: DocxRuntime,
    {
      revision,
      key,
      format,
    }: { revision: number; key: string; format: DocxStyleUpdate },
  ): EditState {
    checkStyleUpdate(format);
    return session.call<EditState>({
      operation: "updateStyle",
      revision,
      key,
      format,
    });
  },
  captureFormat(
    session: DocxRuntime,
    { revision, selection }: { revision: number; selection: DocxSelection },
  ): CopiedFormat {
    return session.call<CopiedFormat>({
      operation: "captureFormat",
      revision,
      selection,
    });
  },
  applyFormat(
    session: DocxRuntime,
    {
      revision,
      selection,
      format,
      profile = {},
    }: {
      revision: number;
      selection: DocxSelection;
      format: CopiedFormat;
      profile?: Record<string, string> | undefined;
    },
  ): EditState {
    copiedFormat(format);
    return session.call<EditState>({
      operation: "applyFormat",
      revision,
      selection,
      format,
      profile,
    });
  },
  setCharacterFormat(
    session: DocxRuntime,
    {
      revision,
      selection,
      format,
      profile = {},
    }: {
      revision: number;
      selection: DocxSelection;
      format: CharacterFormatPatch;
      profile?: Record<string, string> | undefined;
    },
  ): EditState {
    checkFormatPatch(format);
    return session.call<EditState>({
      operation: "setCharacterFormat",
      revision,
      selection,
      format,
      profile,
    });
  },
  setHyperlink(
    session: DocxRuntime,
    {
      revision,
      selection,
      target,
      text,
    }: {
      revision: number;
      selection: DocxSelection;
      target: string | null;
      text?: string | undefined;
    },
  ): EditState {
    checkDocxHyperlink(target, text);
    return session.call<EditState>({
      operation: "setHyperlink",
      revision,
      selection,
      target,
      ...(text === undefined ? {} : { text }),
    });
  },
  setParagraphFormat(
    session: DocxRuntime,
    {
      revision,
      selection,
      format,
      profile = {},
    }: {
      revision: number;
      selection: DocxSelection;
      format: ParagraphFormatPatch;
      profile?: Record<string, string> | undefined;
    },
  ): EditState {
    checkFormatPatch(format, true);
    return session.call<EditState>({
      operation: "setParagraphFormat",
      revision,
      selection,
      format,
      profile,
    });
  },
};
