import type { FoundationClient } from "./foundation.js";
import {
  DOCX_SOFT_BREAK,
  DOCX_PAGE_BREAK,
  DOCX_COLUMN_BREAK,
} from "../core/foundation.js";
import type { EditState, DocxSelection } from "../core/foundation.js";

import { NativeTextInput } from "@open-document/web-core/text-input";
interface InputHost {
  state(): EditState;
  layoutId(): number;
  available(): boolean;
  enqueue(operation: () => Promise<void>, composition?: boolean): Promise<void>;
  changed(
    state: EditState,
    relayout?: boolean,
    reveal?: boolean,
  ): Promise<void>;
  history(redo: boolean): Promise<void>;
  stop(error: Error): void;
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
          const state = await client.beginComposition(revision);
          if (state.compositionId === null)
            throw new Error("Core did not begin composition");
          return { state, id: state.compositionId };
        },
        update: (revision, id, text) =>
          client.updateComposition(revision, id, text),
        commit: (revision, id, text) =>
          client.commitComposition(revision, id, text),
        cancel: (revision, id) => client.cancelComposition(revision, id),
        replace: (revision, text, group) =>
          client.replaceRange(revision, selection(), text, group),
        delete: (revision, direction) => client.deleteDocx(revision, direction),
        navigate: async (revision, direction, extend) =>
          (
            await client.navigateDocx(
              revision,
              host.layoutId(),
              direction,
              extend,
            )
          ).state,
        softBreak: DOCX_SOFT_BREAK,
        pageBreak: DOCX_PAGE_BREAK,
        columnBreak: DOCX_COLUMN_BREAK,
        nativeEnter: true,
        enter: (revision) => client.enterDocx(revision),
        tab: (revision, backward) => client.tabDocx(revision, backward),
        selectAll: (revision) => client.selectAllDocx(revision),
      },
      { ...host, limit: () => host.state().commandLimit },
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
