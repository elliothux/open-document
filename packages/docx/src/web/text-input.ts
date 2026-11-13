import type { FoundationClient } from "./foundation.js";
import {
  DOCX_SOFT_BREAK,
  DOCX_PAGE_BREAK,
  DOCX_COLUMN_BREAK,
} from "../core/foundation.js";
import type { EditState, DocxSelection } from "../core/foundation.js";

import {
  NativeTextInput,
  type NativeInputHost,
} from "@open-document/web-core/text-input";

interface InputHost extends Omit<NativeInputHost<EditState>, "limit"> {
  layoutId(): number;
}

export class TextInput extends NativeTextInput<EditState> {
  constructor(
    input: HTMLTextAreaElement,
    signal: AbortSignal,
    client: FoundationClient,
    host: InputHost,
  ) {
    const selection = (): DocxSelection => {
      const value = host.state().selection;
      if (!value) throw new Error("Click a document position first");
      return value;
    };
    super(
      input,
      signal,
      {
        async begin(revision) {
          const state = await client.execute({
            operation: "beginComposition",
            revision: revision,
          });
          if (state.compositionId === null)
            throw new Error("Core did not begin composition");
          return { state, id: state.compositionId };
        },
        update: (revision, id, text) =>
          client.execute({
            operation: "updateComposition",
            revision: revision,
            compositionId: id,
            text: text,
          }),
        commit: (revision, id, text) =>
          client.execute({
            operation: "commitComposition",
            revision: revision,
            compositionId: id,
            text: text,
          }),
        cancel: (revision, id) =>
          client.execute({
            operation: "cancelComposition",
            revision: revision,
            compositionId: id,
          }),
        replace: (revision, text, group) =>
          client.execute({
            operation: "replaceRange",
            revision: revision,
            selection: selection(),
            text: text,
            inputGroup: group,
          }),
        delete: (revision, direction) =>
          client.execute({
            operation: "deleteDocx",
            revision: revision,
            direction: direction,
          }),
        navigate: async (revision, direction, extend) =>
          (
            await client.execute({
              operation: "navigateDocx",
              revision: revision,
              layoutId: host.layoutId(),
              direction: direction,
              extend: extend,
              selectionView: true,
            })
          ).state,
        softBreak: DOCX_SOFT_BREAK,
        pageBreak: DOCX_PAGE_BREAK,
        columnBreak: DOCX_COLUMN_BREAK,
        nativeEnter: true,
        enter: (revision) =>
          client.execute({ operation: "enterDocx", revision: revision }),
        tab: (revision, backward) =>
          client.execute({
            operation: "tabDocx",
            revision: revision,
            backward: backward,
          }),
        selectAll: (revision) =>
          client.execute({ operation: "selectAllDocx", revision: revision }),
      },
      {
        ...host,
        available: () =>
          host.available() && (!input.readOnly || !!host.state().selection),
        limit: () => host.state().commandLimit,
      },
    );
    input.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Escape" && !event.isComposing && !this.active) {
          input.closest<HTMLElement>('[role="region"]')?.focus();
        }
      },
      { signal },
    );
  }
}
