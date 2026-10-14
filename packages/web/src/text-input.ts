import type { FoundationClient } from "./foundation.js";
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

interface Composition {
  token?: { revision: number; id: number };
  pending?: string;
  scheduled: boolean;
}

/** Translates native text events into the editor's existing ordered core commands. */
export class TextInput {
  private group: number | undefined;
  private groups = 0;
  private gesture: Composition | undefined;
  private owned: Composition["token"];
  private completed: string | undefined;

  constructor(
    private readonly input: HTMLTextAreaElement,
    signal: AbortSignal,
    private readonly client: FoundationClient,
    private readonly host: InputHost,
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
      await this.client.cancelComposition(this.owned.revision, this.owned.id);
      this.owned = undefined;
    }
  }

  private get state(): EditState {
    return this.host.state();
  }

  private selection(): DocxSelection {
    const selection = this.state.selection;
    if (!selection) throw new Error("Click a document position first");
    return selection;
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
        const state = await this.client.beginComposition(this.state.revision);
        if (state.compositionId === null)
          throw new Error("Core did not begin composition");
        // Keep the token before presentation so disposal can cancel a late reply.
        this.owned = gesture.token = {
          revision: state.revision,
          id: state.compositionId,
        };
        await this.host.changed(state, true);
      }, true)
      .catch(() => {});
  };

  private readonly update = (event: CompositionEvent): void => {
    const gesture = this.gesture;
    if (!gesture || !this.host.available()) return;
    if (event.data.length > this.state.commandLimit) {
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
          await this.client.updateComposition(token.revision, token.id, text),
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
    if (text.length <= this.state.commandLimit) this.completed = text;
    void this.host
      .enqueue(async () => {
        const token = gesture.token;
        if (!token) throw new Error("Composition has not begun");
        const state = await this.client.commitComposition(
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
        ? "\n"
        : event.inputType === "insertText"
          ? event.data
          : null;
    if (text !== null) {
      if (text.length > this.state.commandLimit) {
        this.host.stop(new Error("Input exceeds command budget"));
        return;
      }
      let inputGroup: number | undefined;
      if (
        event.inputType === "insertText" &&
        text.length > 0 &&
        !text.includes("\n")
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
            await this.client.replaceRange(
              this.state.revision,
              this.selection(),
              text,
              inputGroup,
            ),
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
          await this.client.deleteDocx(this.state.revision, direction),
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
    if (command || event.altKey) {
      this.endGroup();
      return;
    }
    if (event.key === "Enter" && event.shiftKey) {
      event.preventDefault();
      this.host.stop(new Error("Soft line breaks are not available yet"));
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
        const result = await this.client.navigateDocx(
          this.state.revision,
          this.host.layoutId(),
          direction,
          extend,
        );
        await this.host.changed(result.state);
      });
    } else if (event.key === "Backspace" || event.key === "Delete") {
      event.preventDefault();
      const direction = event.key === "Backspace" ? "backward" : "forward";
      this.send(async () =>
        this.host.changed(
          await this.client.deleteDocx(this.state.revision, direction),
        ),
      );
    }
  };
}
