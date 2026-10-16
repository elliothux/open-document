import type { XlsxViewport } from "@open-document/wasm/xlsx";

export function styleCellDraft(
  input: HTMLTextAreaElement,
  draft: { address: string } | undefined,
  scale: number,
  layout: XlsxViewport | undefined,
  viewportWidth: number,
): void {
  const rect = layout?.cells.find(
    (item) => item.cell.address === draft?.address,
  )?.rect;
  input.style.opacity = draft ? "1" : "0";
  input.style.pointerEvents = draft ? "auto" : "none";
  input.style.border = draft ? "2px solid #2563eb" : "0";
  input.style.width = draft
    ? `${Math.max(120, Math.min((rect?.width ?? 90) * scale, viewportWidth - parseFloat(input.style.left)))}px`
    : "1px";
  input.style.height = draft
    ? `${Math.max(24, (rect?.height ?? 18) * scale)}px`
    : "1px";
}

interface SpreadsheetKeyHost {
  paused: boolean;
  composing: boolean;
  draft: boolean;
  cancelDraft(): void;
  handle(action: () => Promise<unknown>): void;
  move(
    direction: "left" | "right" | "up" | "down" | "home",
    extend?: boolean,
  ): Promise<void>;
  undo(): Promise<void>;
  redo(): Promise<void>;
  edit(): Promise<void>;
  clear(): Promise<void>;
}

/** Native cell drafts keep their text shortcuts; grid keys use the editor's queue. */
export function spreadsheetKey(
  event: KeyboardEvent,
  host: SpreadsheetKeyHost,
): void {
  if (
    event.defaultPrevented ||
    host.paused ||
    event.isComposing ||
    host.composing
  )
    return;
  if (event.key === "Escape") {
    event.preventDefault();
    host.cancelDraft();
    return;
  }
  if (host.draft) {
    if ((event.key === "Enter" && !event.shiftKey) || event.key === "Tab") {
      event.preventDefault();
      host.handle(() =>
        host.move(
          event.key === "Tab" ? (event.shiftKey ? "left" : "right") : "down",
        ),
      );
    }
    return;
  }
  if (
    (event.ctrlKey || event.metaKey) &&
    !event.altKey &&
    ["z", "y"].includes(event.key.toLowerCase())
  ) {
    event.preventDefault();
    host.handle(() =>
      event.shiftKey || event.key.toLowerCase() === "y"
        ? host.redo()
        : host.undo(),
    );
    return;
  }
  const directions: Record<
    string,
    "left" | "right" | "up" | "down" | "home" | undefined
  > = {
    ArrowLeft: "left",
    ArrowRight: "right",
    ArrowUp: "up",
    ArrowDown: "down",
    Home: "home",
    Enter: "down",
    Tab: event.shiftKey ? "left" : "right",
  };
  const direction = directions[event.key];
  if (direction) {
    event.preventDefault();
    host.handle(() =>
      host.move(direction, event.shiftKey && event.key !== "Tab"),
    );
  } else if (event.key === "F2") {
    event.preventDefault();
    host.handle(() => host.edit());
  } else if (event.key === "Delete" || event.key === "Backspace") {
    event.preventDefault();
    host.handle(() => host.clear());
  }
}
