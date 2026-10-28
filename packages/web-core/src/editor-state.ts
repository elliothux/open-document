export type EditorFormat = "docx" | "xlsx" | "pptx" | "pdf";

export interface EditorOutput {
  readonly documentId: string;
  readonly revision: number;
  readonly format: EditorFormat | "csv" | "png" | "jpeg" | "html" | "markdown";
  readonly bytes: Uint8Array;
}

export interface EditorFields<T> {
  revision: number;
  canUndo: boolean;
  canRedo: boolean;
  page: number;
  pageCount: number;
  zoom: number;
  selection: string;
  composition: boolean;
  dragging: boolean;
  draft: boolean;
  busy: number;
  paused: boolean;
  stopped: boolean;
  closed: boolean;
  error: string;
  readOnlyReason: string;
  diagnostics: readonly string[];
  data: T;
}

export type EditorSnapshot<T = unknown> = Readonly<EditorFields<T>> & {
  readonly documentId: string;
  readonly format: EditorFormat;
  readonly modified: boolean;
  readonly savedRevision: number;
  readonly lastOutput: Readonly<{
    revision: number;
    format: EditorOutput["format"];
    downloaded: boolean;
  }> | null;
};

/** UI metadata only; the editor's existing queue and core remain the state owners. */
export class EditorState<T> {
  private readonly documentId = crypto.randomUUID();
  private readonly listeners = new Set<() => void>();
  private readonly outputs = new WeakSet<EditorOutput>();
  private value: EditorSnapshot<T>;

  constructor(
    private readonly format: EditorFormat,
    fields: Pick<EditorFields<T>, "revision" | "data"> &
      Partial<EditorFields<T>>,
  ) {
    this.value = Object.freeze({
      canUndo: false,
      canRedo: false,
      page: 0,
      pageCount: 1,
      zoom: 1,
      selection: "",
      composition: false,
      dragging: false,
      draft: false,
      busy: 0,
      paused: false,
      stopped: false,
      closed: false,
      error: "",
      readOnlyReason: "",
      diagnostics: [],
      ...fields,
      documentId: this.documentId,
      format,
      modified: fields.revision !== 0,
      savedRevision: 0,
      lastOutput: null,
    });
  }

  readonly getSnapshot = (): EditorSnapshot<T> => this.value;
  readonly subscribe = (listener: () => void): (() => void) => {
    if (this.value.closed) return () => {};
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  update(fields: Partial<EditorFields<T>>): void {
    const next = { ...this.value, ...fields };
    next.modified = next.revision !== next.savedRevision;
    if (
      Object.keys(next).every((key) =>
        Object.is(Reflect.get(next, key), Reflect.get(this.value, key)),
      )
    )
      return;
    this.publish(next);
  }

  output(
    revision: number,
    format: EditorOutput["format"],
    bytes: Uint8Array,
  ): EditorOutput {
    const output = Object.freeze({
      documentId: this.documentId,
      revision,
      format,
      bytes,
    });
    this.outputs.add(output);
    this.publish({
      ...this.value,
      lastOutput: { revision, format, downloaded: false },
    });
    return output;
  }

  markSaved(output: EditorOutput): void {
    this.validateOutput(output);
    if (output.format !== this.format)
      throw new Error("Only original-format output can confirm a save");
    const savedRevision = Math.max(this.value.savedRevision, output.revision);
    this.publish({
      ...this.value,
      savedRevision,
      modified: this.value.revision !== savedRevision,
    });
  }

  markDownloaded(output: EditorOutput): void {
    this.validateOutput(output);
    this.publish({
      ...this.value,
      lastOutput: {
        revision: output.revision,
        format: output.format,
        downloaded: true,
      },
    });
  }

  close(): void {
    this.update({ closed: true, paused: true });
    this.listeners.clear();
  }

  private validateOutput(output: EditorOutput): void {
    if (
      this.value.closed ||
      !this.outputs.has(output) ||
      output.documentId !== this.documentId ||
      output.revision > this.value.revision
    )
      throw new Error("Output does not belong to this open document");
  }

  private publish(value: EditorSnapshot<T>): void {
    this.value = Object.freeze(value);
    for (const listener of this.listeners) {
      try {
        listener();
      } catch {
        /* Host observers cannot change an accepted transaction. */
      }
    }
  }
}

/** Use the actual root for focus checks, including open Shadow DOM. */
export function focusedElement(node: Node): Element | null {
  const root = node.getRootNode();
  return root instanceof ShadowRoot
    ? root.activeElement
    : (node.ownerDocument?.activeElement ?? null);
}
