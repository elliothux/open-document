import {
  createContext,
  memo,
  useContext,
  useSyncExternalStore,
  type ReactNode,
} from "react";
import type { EditorController, UiSnapshot } from "./controller.js";
import type { EditorHost } from "./types.js";
import { Icon, type IconName } from "./icons.js";
import { messages } from "./messages.js";
import { DocumentError } from "@open-document/wasm";

export interface CommandState {
  readonly id: string;
  readonly label: string;
  readonly icon?: IconName;
  readonly shortcut?: string;
  readonly available: boolean;
  readonly enabled: boolean;
  readonly pressed?: boolean | "mixed";
  readonly value?: string | number;
  readonly disabledReason?: string;
}

export type CommandDefinition = Omit<CommandState, "available" | "enabled"> & {
  run(verify?: () => void): unknown | Promise<unknown>;
};

export interface CommandTarget {
  readonly documentId: string;
  readonly revision: number;
  readonly selection: string;
}

export interface EditorCommandApi {
  subscribe(listener: () => void): () => void;
  getSnapshot(id: string): CommandState | undefined;
  captureTarget(): CommandTarget | undefined;
  assertTarget(target: CommandTarget): void;
  execute(id: string, target?: CommandTarget): Promise<void>;
}

export class CommandUnavailable extends DocumentError {
  constructor(
    code: "unavailable" | "disabled" | "target-changed",
    message: string,
  ) {
    super(code, message, "", -1);
    this.name = "CommandUnavailable";
  }
}

export class EditorCommands<E extends EditorHost> implements EditorCommandApi {
  private current?: UiSnapshot<E>;
  private entries = new Map<
    string,
    { state: CommandState; run: CommandDefinition["run"] }
  >();

  constructor(private readonly controller: EditorController<E>) {}

  readonly subscribe = (listener: () => void) =>
    this.controller.subscribe(listener);

  private refresh() {
    const state = this.controller.getUiSnapshot();
    if (this.current === state) return;
    this.current = state;
    const previous = this.entries;
    this.entries = new Map();
    const { file, document } = state;
    if (!file || !document || document.closed) return;
    const t = messages(state.locale);
    const blocked =
      state.loading ||
      document.paused ||
      document.composition ||
      document.dragging ||
      document.stopped;
    const disabledReason = blocked
      ? document.error || t.commandUnavailable
      : undefined;
    const viewReason = state.mode === "view" ? t.viewOnly : undefined;
    const historyReason = disabledReason || viewReason;
    const copyReason =
      disabledReason ||
      (file.clipboard().canCopy ? undefined : t.commandUnavailable);
    const definitions: CommandDefinition[] = [
      {
        id: "save",
        label: state.saving ? t.saving : t.save,
        icon: "save",
        shortcut: "S",
        ...(state.loading ||
        state.saving ||
        document.composition ||
        document.dragging
          ? { disabledReason: t.commandUnavailable }
          : {}),
        run: this.controller.save,
      },
      {
        id: "undo",
        label: t.undo,
        icon: "undo",
        shortcut: "Z",
        ...(historyReason || !document.canUndo
          ? { disabledReason: historyReason || t.commandUnavailable }
          : {}),
        run: () => file.editor.undo(),
      },
      {
        id: "redo",
        label: t.redo,
        icon: "redo",
        shortcut: "Shift+Z",
        ...(historyReason || !document.canRedo
          ? { disabledReason: historyReason || t.commandUnavailable }
          : {}),
        run: () => file.editor.redo(),
      },
      {
        id: "copy",
        label: t.copy,
        icon: "copy",
        ...(copyReason ? { disabledReason: copyReason } : {}),
        run: () => file.editor.copy(),
      },
      ...(this.controller.product.commands?.({
        controller: this.controller,
        state,
        file,
        disabled: blocked || state.mode === "view",
      }) ?? []),
    ];
    for (const { run, ...command } of definitions) {
      const next = {
        ...command,
        available: true,
        enabled: !command.disabledReason,
      };
      const before = previous.get(command.id)?.state;
      const stable =
        before &&
        Object.keys(before).length === Object.keys(next).length &&
        Object.keys(next).every((key) =>
          Object.is(Reflect.get(before, key), Reflect.get(next, key)),
        );
      this.entries.set(command.id, {
        run,
        state: stable ? before : Object.freeze(next),
      });
    }
  }

  readonly getSnapshot = (id: string): CommandState | undefined => {
    this.refresh();
    return this.entries.get(id)?.state;
  };

  readonly captureTarget = (): CommandTarget | undefined => {
    const { document: doc, file } = this.controller.getUiSnapshot();
    return (
      doc && {
        documentId: doc.documentId,
        revision: doc.revision,
        selection:
          (file && this.controller.product.selectionKey?.(file.editor)) ??
          doc.selection,
      }
    );
  };

  assertTarget(target: CommandTarget): void {
    const current = this.captureTarget();
    if (
      target.documentId !== current?.documentId ||
      target.revision !== current.revision ||
      target.selection !== current.selection
    )
      throw new CommandUnavailable(
        "target-changed",
        messages(this.controller.getUiSnapshot().locale).targetChanged,
      );
  }

  readonly execute = async (
    id: string,
    target?: CommandTarget,
  ): Promise<void> => {
    this.refresh();
    const state = this.controller.getUiSnapshot();
    const entry = this.entries.get(id);
    try {
      if (target) this.assertTarget(target);
      if (!entry)
        throw new CommandUnavailable(
          "unavailable",
          messages(state.locale).commandUnavailable,
        );
      if (!entry.state.enabled)
        throw new CommandUnavailable(
          "disabled",
          entry.state.disabledReason ?? entry.state.label,
        );
      await entry.run(target && (() => this.assertTarget(target)));
    } catch (error) {
      this.controller.report(error);
      throw error;
    }
  };
}

const CommandContext = createContext<EditorCommandApi | undefined>(undefined);
const idleSubscribe = () => () => {};
const emptySnapshot = () => undefined;

export function EditorCommandProvider({
  commands,
  children,
}: {
  commands: EditorCommandApi;
  children: ReactNode;
}) {
  return (
    <CommandContext.Provider value={commands}>
      {children}
    </CommandContext.Provider>
  );
}

export function useEditorCommand(
  id: string,
  commands?: EditorCommandApi,
): CommandState | undefined {
  const provided = useContext(CommandContext);
  const api = commands ?? provided;
  return useSyncExternalStore(
    api?.subscribe ?? idleSubscribe,
    () => api?.getSnapshot(id),
    emptySnapshot,
  );
}

export const EditorCommandButton = memo(function EditorCommandButton({
  id,
  commands,
  iconOnly = false,
  children,
}: {
  id: string;
  commands?: EditorCommandApi;
  /** Show only the icon; the label stays as the accessible name and tooltip. */
  iconOnly?: boolean;
  children?: ReactNode;
}) {
  const provided = useContext(CommandContext);
  const api = commands ?? provided;
  const state = useEditorCommand(id, api);
  return (
    <button
      type="button"
      className={
        iconOnly && state?.icon ? "od-command od-command-icon" : "od-command"
      }
      title={state?.disabledReason ?? state?.label}
      aria-description={state?.disabledReason}
      aria-pressed={state?.pressed}
      disabled={!state?.enabled}
      onClick={() => void api?.execute(id).catch(() => {})}
    >
      {state?.icon && <Icon name={state.icon} />}
      <span>{children ?? state?.label ?? id}</span>
    </button>
  );
});
