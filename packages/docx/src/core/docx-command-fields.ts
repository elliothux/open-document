import {
  checkDocxBibliographyEdit,
  type DocxBibliographyEdit,
  checkDocxCitationEdit,
  type DocxCitationEdit,
  checkDocxSourceEdit,
  type DocxSources,
  type DocxSourceEdit,
} from "./docx-sources.js";
import {
  checkDocxIndexEdit,
  type DocxIndexes,
  type DocxIndexEdit,
} from "./docx-index.js";
import {
  checkDocxTocEdit,
  type DocxTableOfContents,
  type DocxTocEdit,
} from "./docx-toc.js";
import { checkSectionBreak } from "./docx-sections.js";

import { checkDocxProtection, type DocxProtection } from "./docx-protection.js";
import { protectionSalt } from "@open-document/wasm/abi/protection-password";

import type { DocxSelection } from "./docx-hit.js";
import { type EditState } from "./docx-format.js";
import {
  type DocxSectionBreak,
  type DocxCaption,
  checkDocxCaption,
  type DocxBodyField,
  type DocxBodyPageField,
  checkBodyField,
} from "./docx-page.js";
import type { DocxRuntime } from "./docx-session.js";
export const docxFieldsCommands = {
  documentProtection(session: DocxRuntime, { revision }: { revision: number }) {
    return session.call<DocxProtection>({
      operation: "documentProtection",
      revision,
    });
  },
  setDocumentProtection(
    session: DocxRuntime,
    {
      revision,
      enabled,
      password,
    }: { revision: number; enabled: boolean; password: string },
  ) {
    checkDocxProtection(enabled, password);
    return session.call<EditState>({
      operation: "setDocumentProtection",
      revision,
      enabled,
      password,
      passwordSalt: protectionSalt(enabled, password),
    });
  },
  bodyPageField(
    session: DocxRuntime,
    { revision, selection }: { revision: number; selection: DocxSelection },
  ): DocxBodyPageField {
    return session.call<DocxBodyPageField>({
      operation: "bodyPageField",
      revision,
      selection,
    });
  },
  editBodyPageField(
    session: DocxRuntime,
    {
      revision,
      selection,
      field,
      profile,
    }: {
      revision: number;
      selection: DocxSelection;
      field: DocxBodyField;
      profile: Record<string, string>;
    },
  ) {
    checkBodyField(field);
    return session.call<EditState>({
      operation: "editBodyPageField",
      revision,
      selection,
      field,
      profile,
    });
  },
  insertBodyPageField(
    session: DocxRuntime,
    {
      revision,
      field,
      profile,
    }: {
      revision: number;
      field: DocxBodyField;
      profile: Record<string, string>;
    },
  ) {
    checkBodyField(field);
    return session.call<EditState>({
      operation: "insertBodyPageField",
      revision,
      field,
      profile,
    });
  },
  insertSectionBreak(
    session: DocxRuntime,
    {
      revision,
      kind,
      profile,
    }: {
      revision: number;
      kind: DocxSectionBreak;
      profile: Record<string, string>;
    },
  ) {
    checkSectionBreak(kind);
    return session.call<EditState>({
      operation: "insertSectionBreak",
      revision,
      kind,
      profile,
    });
  },
  insertCaption(
    session: DocxRuntime,
    {
      revision,
      caption,
      profile,
    }: {
      revision: number;
      caption: DocxCaption;
      profile: Record<string, string>;
    },
  ) {
    checkDocxCaption(caption);
    return session.call<EditState>({
      operation: "insertDocxCaption",
      revision,
      caption,
      profile,
    });
  },
  tableOfContents(session: DocxRuntime, { revision }: { revision: number }) {
    return session.call<DocxTableOfContents>({
      operation: "docxTableOfContents",
      revision,
    });
  },
  sources(session: DocxRuntime, { revision }: { revision: number }) {
    return session.call<DocxSources>({ operation: "docxSources", revision });
  },
  editBibliography(
    session: DocxRuntime,
    {
      revision,
      change,
      profile,
    }: {
      revision: number;
      change: DocxBibliographyEdit;
      profile: Record<string, string>;
    },
  ) {
    checkDocxBibliographyEdit(change);
    return session.call<EditState>({
      operation: "editDocxBibliography",
      revision,
      change,
      profile,
    });
  },
  editCitation(
    session: DocxRuntime,
    {
      revision,
      change,
      profile,
    }: {
      revision: number;
      change: DocxCitationEdit;
      profile: Record<string, string>;
    },
  ) {
    checkDocxCitationEdit(change);
    return session.call<EditState>({
      operation: "editDocxCitation",
      revision,
      change,
      profile,
    });
  },
  editSource(
    session: DocxRuntime,
    { revision, change }: { revision: number; change: DocxSourceEdit },
  ) {
    checkDocxSourceEdit(change);
    return session.call<EditState>({
      operation: "editDocxSource",
      revision,
      change,
    });
  },
  indexes(session: DocxRuntime, { revision }: { revision: number }) {
    return session.call<DocxIndexes>({ operation: "docxIndexes", revision });
  },
  editIndex(
    session: DocxRuntime,
    {
      revision,
      change,
      profile,
    }: {
      revision: number;
      change: DocxIndexEdit;
      profile: Record<string, string>;
    },
  ) {
    checkDocxIndexEdit(change);
    return session.call<EditState>({
      operation: "editDocxIndex",
      revision,
      change,
      profile,
    });
  },
  editTableOfContents(
    session: DocxRuntime,
    {
      revision,
      change,
      profile,
    }: {
      revision: number;
      change: DocxTocEdit;
      profile: Record<string, string>;
    },
  ) {
    checkDocxTocEdit(change);
    return session.call<EditState>({
      operation: "editDocxTableOfContents",
      revision,
      change,
      profile,
    });
  },
};
