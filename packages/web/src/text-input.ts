import type { FoundationClient } from "./foundation.js";
import { DOCX_SOFT_BREAK } from "@open-document/wasm/foundation";
import type {
  EditState,
  DocxSelection,
  NavigationDirection,
} from "@open-document/wasm/foundation";

interface InputHost {
  state(): EditState;
  layoutId(): number;
  available(): boolean;
  enqueue(operation: () => Promise<void>, composition?: boolean): Promise<void>;
  changed(state: EditState, relayout?: boolean): Promise<void>;
  history(redo: boolean): Promise<void>;
  stop(error: Error): void;
}

export interface NativeInputHost<State extends { revision: number }> {
  state(): State;
  limit(): number;
  available(): boolean;
  enqueue(operation: () => Promise<void>, composition?: boolean): Promise<void>;
  changed(state: State, relayout?: boolean): Promise<void>;
  history(redo: boolean): Promise<void>;
  stop(error: Error): void;
}

export interface NativeInputCommands<State> {
  begin(revision: number): Promise<{ state: State; id: number }>;
  update(revision: number, id: number, text: string): Promise<State>;
  commit(revision: number, id: number, text: string): Promise<State>;
  cancel(revision: number, id: number): Promise<unknown>;
  replace(revision: number, text: string, group?: number): Promise<State>;
  delete(revision: number, direction: "backward" | "forward"): Promise<State>;
  navigate(
    revision: number,
    direction: NavigationDirection,
    extend: boolean,
  ): Promise<State>;
  softBreak: string;
  nativeEnter: boolean;
  tab?(revision: number, backward: boolean): Promise<State>;
}

interface Composition {
  token?: { revision: number; id: number };
  pending?: string;
  scheduled: boolean;
}

/** Translates native text events into the editor's existing ordered core commands. */
export class NativeTextInput<State extends { revision: number }> {
  private group: number | undefined;
  private groups = 0;
  private gesture: Composition | undefined;
  private owned: Composition["token"];
  private completed: string | undefined;

  constructor(
    private readonly input: HTMLTextAreaElement,
    signal: AbortSignal,
    private readonly commands: NativeInputCommands<State>,
    private readonly host: NativeInputHost<State>,
  ) {
    const options = { signal };
    input.addEventListener("keydown", this.key, options);
    input.addEventListener("beforeinput", this.beforeInput, options);
    input.addEventListener("input", this.nativeInput, options);
    input.addEventListener("compositionstart", this.begin, options);
    input.addEventListener("compositionupdate", this.update, options);
    input.addEventListener("compositionend", this.end, options);
  }

  get active(): boolean {
    return this.gesture !== undefined;
  }

  endGroup(): void {
    this.group = undefined;
    this.completed = undefined;
  }

  /** Called only after the editor queue drains, including late begin/update replies. */
  async cancel(): Promise<void> {
    this.gesture = undefined;
    this.endGroup();
    this.input.value = "";
    if (this.owned) {
      await this.commands.cancel(this.owned.revision, this.owned.id);
      this.owned = undefined;
    }
  }

  private get state(): State {
    return this.host.state();
  }

  private send(operation: () => Promise<void>, ordinaryInput = false): void {
    if (!ordinaryInput) this.endGroup();
    void this.host.enqueue(operation).catch(() => {});
  }

  private readonly begin = (): void => {
    if (!this.host.available()) return;
    if (this.gesture) {
      this.host.stop(new Error("Composition is already active"));
      return;
    }
    this.endGroup();
    const gesture: Composition = { scheduled: false };
    this.gesture = gesture;
    void this.host
      .enqueue(async () => {
        const { state, id } = await this.commands.begin(this.state.revision);
        // Keep the token before presentation so disposal can cancel a late reply.
        this.owned = gesture.token = {
          revision: state.revision,
          id,
        };
        await this.host.changed(state, true);
      }, true)
      .catch(() => {});
  };

  private readonly update = (event: CompositionEvent): void => {
    const gesture = this.gesture;
    if (!gesture || !this.host.available()) return;
    if (event.data.length > this.host.limit()) {
      this.host.stop(new Error("Input exceeds command budget"));
      return;
    }
    gesture.pending = event.data;
    if (gesture.scheduled) return;
    gesture.scheduled = true;
    void this.host
      .enqueue(async () => {
        gesture.scheduled = false;
        const text = gesture.pending;
        delete gesture.pending;
        const token = gesture.token;
        if (text === undefined) return;
        if (!token) throw new Error("Composition has not begun");
        await this.host.changed(
          await this.commands.update(token.revision, token.id, text),
          true,
        );
      }, true)
      .catch(() => {});
  };

  private readonly end = (event: CompositionEvent): void => {
    const gesture = this.gesture;
    if (!gesture) return;
    this.gesture = undefined;
    this.input.value = "";
    if (!this.host.available()) return;
    const text = event.data;
    if (text.length <= this.host.limit()) this.completed = text;
    void this.host
      .enqueue(async () => {
        const token = gesture.token;
        if (!token) throw new Error("Composition has not begun");
        const state = await this.commands.commit(
          token.revision,
          token.id,
          text,
        );
        this.owned = undefined;
        await this.host.changed(state, true);
      }, true)
      .catch(() => {});
  };

  private readonly nativeInput = (event: Event): void => {
    // Some engines deliver the final native notification after compositionend.
    if (
      event instanceof InputEvent &&
      !event.isComposing &&
      event.inputType === "insertCompositionText" &&
      event.data === this.completed
    ) {
      this.completed = undefined;
      this.input.value = "";
      return;
    }
    if (
      this.active &&
      event instanceof InputEvent &&
      event.isComposing &&
      event.inputType === "insertCompositionText"
    )
      return;
    this.input.value = "";
    this.host.stop(
      new Error("Unsupported native input was not applied to the document"),
    );
  };

  private readonly beforeInput = (event: InputEvent): void => {
    this.completed = undefined;
    if (
      this.active &&
      event.isComposing &&
      event.inputType === "insertCompositionText"
    )
      return;
    if (event.cancelable) event.preventDefault();
    if (!this.host.available()) return;
    if (this.active) {
      this.send(async () => {});
      return;
    }
    if (!event.cancelable || event.isComposing) {
      this.host.stop(new Error("This input event is not supported yet"));
      return;
    }
    const text =
      event.inputType === "insertParagraph" ||
      event.inputType === "insertLineBreak"
        ? event.inputType === "insertLineBreak" && !this.commands.nativeEnter
          ? this.commands.softBreak
          : "\n"
        : event.inputType === "insertText"
          ? event.data
          : null;
    if (text !== null) {
      if (text.length > this.host.limit()) {
        this.host.stop(new Error("Input exceeds command budget"));
        return;
      }
      let inputGroup: number | undefined;
      if (
        event.inputType === "insertText" &&
        text.length > 0 &&
        !text.includes("\n") &&
        !text.includes("\u2028") &&
        !text.includes("\t")
      ) {
        if (this.group === undefined) {
          if (this.groups === 2147483647) {
            this.host.stop(new Error("Input group ids exhausted"));
            return;
          }
          this.group = ++this.groups;
        }
        inputGroup = this.group;
      }
      this.send(
        async () =>
          this.host.changed(
            await this.commands.replace(this.state.revision, text, inputGroup),
          ),
        inputGroup !== undefined,
      );
    } else if (
      event.inputType === "deleteContentBackward" ||
      event.inputType === "deleteContentForward"
    ) {
      const direction =
        event.inputType === "deleteContentBackward" ? "backward" : "forward";
      this.send(async () =>
        this.host.changed(
          await this.commands.delete(this.state.revision, direction),
        ),
      );
    } else
      this.host.stop(
        new Error(`Input ${event.inputType} is not available yet`),
      );
  };

  private readonly key = (event: KeyboardEvent): void => {
    this.completed = undefined;
    if (event.defaultPrevented || event.isComposing || this.active) return;
    const command = event.ctrlKey || event.metaKey;
    if (command && event.key.toLowerCase() === "z") {
      event.preventDefault();
      const redo = event.shiftKey;
      this.endGroup();
      void this.host.history(redo).catch(() => {});
      return;
    }
    if (!this.host.available()) return;
    if (
      event.key === "Tab" &&
      !event.altKey &&
      !event.metaKey &&
      this.commands.tab
    ) {
      event.preventDefault();
      const tab = this.commands.tab,
        literal = event.ctrlKey,
        backward = event.shiftKey;
      this.send(async () =>
        this.host.changed(
          await (literal
            ? this.commands.replace(this.state.revision, "\t")
            : tab(this.state.revision, backward)),
        ),
      );
      return;
    }
    if (command || event.altKey) {
      this.endGroup();
      return;
    }
    if (event.key === "Enter" && event.shiftKey) {
      event.preventDefault();
      const text = this.commands.softBreak;
      this.send(async () =>
        this.host.changed(
          await this.commands.replace(this.state.revision, text),
        ),
      );
      return;
    }
    if (event.key === "Enter" && !this.commands.nativeEnter) {
      event.preventDefault();
      this.send(async () =>
        this.host.changed(
          await this.commands.replace(this.state.revision, "\n"),
        ),
      );
      return;
    }
    const directions: Record<string, NavigationDirection> = {
      ArrowLeft: "left",
      ArrowRight: "right",
      ArrowUp: "up",
      ArrowDown: "down",
      Home: "home",
      End: "end",
    };
    const direction = directions[event.key];
    if (direction) {
      event.preventDefault();
      const extend = event.shiftKey;
      this.send(async () => {
        const result = await this.commands.navigate(
          this.state.revision,
          direction,
          extend,
        );
        await this.host.changed(result);
      });
    } else if (event.key === "Backspace" || event.key === "Delete") {
      event.preventDefault();
      const direction = event.key === "Backspace" ? "backward" : "forward";
      this.send(async () =>
        this.host.changed(
          await this.commands.delete(this.state.revision, direction),
        ),
      );
    }
  };
}

/** DOCX positions stay in the DOCX adapter; native event handling is shared. */
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
        nativeEnter: true,
        tab: (revision, backward) => client.tabDocx(revision, backward),
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
