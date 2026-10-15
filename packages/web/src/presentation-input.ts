import { NativeTextInput, type NativeInputHost } from "./text-input.js";
import type { PptxQuery } from "@open-document/wasm/pptx";
import type { PptxClient } from "./pptx.js";

/** Presentation positions and composition candidates stay in the format core. */
export class PresentationInput extends NativeTextInput<PptxQuery> {
  constructor(
    input: HTMLTextAreaElement,
    signal: AbortSignal,
    client: PptxClient,
    host: NativeInputHost<PptxQuery>,
    layoutId: () => number,
    profile: Record<string, string>,
  ) {
    super(
      input,
      signal,
      {
        async begin(revision) {
          const state = await client.execute({
            operation: "beginPptx",
            revision,
            kind: "text",
          });
          if (state.candidateId === null)
            throw new Error("Core did not begin composition");
          return { state, id: state.candidateId };
        },
        update: (revision, candidateId, text) =>
          client.execute({
            operation: "replacePptx",
            revision,
            candidateId,
            text,
            profile,
          }),
        async commit(revision, candidateId, text) {
          if (!text)
            return client.execute({
              operation: "cancelPptx",
              revision,
              candidateId,
            });
          await client.execute({
            operation: "replacePptx",
            revision,
            candidateId,
            text,
            profile,
          });
          return client.execute({
            operation: "finishPptx",
            revision,
            candidateId,
            profile,
          });
        },
        cancel: (revision, candidateId) =>
          client.execute({ operation: "cancelPptx", revision, candidateId }),
        replace: (revision, text) =>
          client.execute({ operation: "replacePptx", revision, text, profile }),
        delete: (revision, direction) =>
          client.execute({
            operation: "deletePptx",
            revision,
            backward: direction === "backward",
            profile,
          }),
        navigate: (revision, direction, extend) =>
          client.execute({
            operation: "navigatePptx",
            revision,
            layoutId: layoutId(),
            direction,
            extend,
          }),
        softBreak: "\u2028",
        nativeEnter: false,
      },
      host,
    );
  }
}
