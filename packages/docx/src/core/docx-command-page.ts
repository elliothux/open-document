import {
  encodeDocxWatermark,
  type DocxWatermarkState,
  type DocxWatermark,
} from "./docx-watermark.js";
import {
  docxRuler,
  checkDocxRulerEdit,
  type DocxRuler,
  type DocxRulerEdit,
} from "./docx-ruler.js";

import {
  checkPageSetup,
  checkPageSection,
  checkPageBackground,
  checkPageBorders,
  checkPageNumbering,
  checkDocxColumns,
  type DocxPageSettings,
  type EditState,
  type DocxPageSetup,
  type DocxPageBorders,
  type DocxPageNumbering,
  type DocxColumns,
} from "./docx-format.js";
import {
  type DocxCoverPage,
  checkDocxCoverPage,
  type DocxRunningVariant,
  checkRunningVariant,
  checkRunningOptions,
  type DocxRunningKind,
  type DocxRunningContent,
  type DocxRunningArea,
  checkRunningKind,
  checkRunningArea,
} from "./docx-page.js";
import type { DocxRuntime } from "./docx-session.js";
import type { RasterHeader } from "@open-document/wasm/abi/drawing";
export const docxPageCommands = {
  ruler(session: DocxRuntime, { revision }: { revision: number }): DocxRuler {
    return session.call<DocxRuler>({ operation: "docxRuler", revision });
  },
  editRuler(
    session: DocxRuntime,
    { source, change }: { source: DocxRuler; change: DocxRulerEdit },
  ) {
    docxRuler(source);
    checkDocxRulerEdit(change);
    return session.call<EditState>({
      operation: "editDocxRuler",
      revision: source.revision,
      layoutId: source.layoutId,
      selection: source.selection,
      change,
    });
  },
  setPageNumbering(
    session: DocxRuntime,
    {
      revision,
      section,
      numbering,
      profile,
    }: {
      revision: number;
      section: number;
      numbering: DocxPageNumbering | null;
      profile: Record<string, string>;
    },
  ) {
    checkPageSection(section);
    checkPageNumbering(numbering);
    return session.call<EditState>({
      operation: "setPageNumbering",
      revision,
      section,
      numbering,
      profile,
    });
  },
  updateBodyPageFields(
    session: DocxRuntime,
    {
      revision,
      profile,
    }: { revision: number; profile: Record<string, string> },
  ) {
    return session.call<EditState>({
      operation: "updateBodyPageFields",
      revision,
      profile,
    });
  },
  setRunningLink(
    session: DocxRuntime,
    {
      revision,
      section,
      kind,
      variant,
      linked,
      profile,
    }: {
      revision: number;
      section: number;
      kind: DocxRunningKind;
      variant: DocxRunningVariant;
      linked: boolean;
      profile: Record<string, string>;
    },
  ) {
    checkPageSection(section);
    if (typeof linked !== "boolean")
      throw new Error("Invalid running link state");
    checkRunningKind(kind);
    checkRunningVariant(variant);
    return session.call<EditState>({
      operation: "setRunningLink",
      revision,
      section,
      kind,
      variant,
      linked,
      profile,
    });
  },
  setRunningOptions(
    session: DocxRuntime,
    {
      revision,
      section,
      first,
      even,
      profile,
    }: {
      revision: number;
      section: number;
      first: boolean;
      even: boolean;
      profile: Record<string, string>;
    },
  ) {
    checkPageSection(section);
    checkRunningOptions(first, even);
    return session.call<EditState>({
      operation: "setRunningOptions",
      revision,
      section,
      first,
      even,
      profile,
    });
  },
  pageSetup(
    session: DocxRuntime,
    {
      revision,
      section = 0,
    }: { revision: number; section?: number | undefined },
  ) {
    checkPageSection(section);
    return session.call<DocxPageSettings>({
      operation: "pageSetup",
      revision,
      section,
    });
  },
  setPageColumns(
    session: DocxRuntime,
    {
      revision,
      section,
      columns,
      profile,
    }: {
      revision: number;
      section: number;
      columns: DocxColumns | null;
      profile: Record<string, string>;
    },
  ) {
    checkPageSection(section);
    checkDocxColumns(columns);
    return session.call<EditState>({
      operation: "setPageColumns",
      revision,
      section,
      columns,
      profile,
    });
  },
  setPageSetup(
    session: DocxRuntime,
    { revision, page }: { revision: number; page: DocxPageSetup },
  ) {
    checkPageSetup(page);
    return session.call<EditState>({
      operation: "setPageSetup",
      revision,
      page,
    });
  },
  setPageBackground(
    session: DocxRuntime,
    { revision, color }: { revision: number; color: string | null },
  ) {
    checkPageBackground(color);
    return session.call<EditState>({
      operation: "setPageBackground",
      revision,
      color,
    });
  },
  watermark(
    session: DocxRuntime,
    { revision, section }: { revision: number; section: number },
  ) {
    checkPageSection(section);
    return session.call<DocxWatermarkState>({
      operation: "watermark",
      revision,
      section,
    });
  },
  rasterHeaderDocx(
    session: DocxRuntime,
    { bytes, verify }: { bytes: Uint8Array; verify?: true },
  ) {
    return session.call<RasterHeader>({
      operation: "rasterHeaderDocx",
      bytes,
      ...(verify ? { verify } : {}),
    });
  },
  setWatermark(
    session: DocxRuntime,
    {
      revision,
      section,
      value,
      profile,
    }: {
      revision: number;
      section: number;
      value: DocxWatermark | null;
      profile: Record<string, string>;
    },
  ) {
    checkPageSection(section);
    return session.call<EditState>({
      operation: "setWatermark",
      revision,
      section,
      value: encodeDocxWatermark(value),
      profile,
    });
  },
  setCoverPage(
    session: DocxRuntime,
    {
      revision,
      cover,
      profile,
    }: {
      revision: number;
      cover: DocxCoverPage | null;
      profile: Record<string, string>;
    },
  ) {
    checkDocxCoverPage(cover);
    return session.call<EditState>({
      operation: "setCoverPage",
      revision,
      cover,
      profile,
    });
  },
  setPageBorders(
    session: DocxRuntime,
    {
      revision,
      section,
      borders,
    }: { revision: number; section: number; borders: DocxPageBorders | null },
  ) {
    checkPageSection(section);
    checkPageBorders(borders);
    return session.call<EditState>({
      operation: "setPageBorders",
      revision,
      section,
      borders,
    });
  },
  runningArea(
    session: DocxRuntime,
    {
      revision,
      section,
      kind,
      variant,
    }: {
      revision: number;
      section: number;
      kind: DocxRunningKind;
      variant: DocxRunningVariant;
    },
  ): DocxRunningArea {
    checkPageSection(section);
    checkRunningKind(kind);
    checkRunningVariant(variant);
    return session.call<DocxRunningArea>({
      operation: "runningArea",
      revision,
      section,
      kind,
      variant,
    });
  },
  setRunningArea(
    session: DocxRuntime,
    {
      revision,
      section,
      kind,
      variant,
      content,
      distance,
      profile,
    }: {
      revision: number;
      section: number;
      kind: DocxRunningKind;
      variant: DocxRunningVariant;
      content: DocxRunningContent[];
      distance: number;
      profile: Record<string, string>;
    },
  ) {
    checkPageSection(section);
    checkRunningArea(kind, variant, content, distance);
    return session.call<EditState>({
      operation: "setRunningArea",
      revision,
      section,
      kind,
      variant,
      content,
      distance,
      profile,
    });
  },
};
