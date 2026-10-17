import type {
  XlsxViewport,
  XlsxSelectionGeometry,
} from "@open-document/wasm/xlsx";

export function requireCellCompositionEnd(composing: boolean): void {
  if (composing)
    throw new Error(
      "Cell editing is unfinished: complete or cancel composition first",
    );
}

export function showCellDraft(
  input: HTMLTextAreaElement,
  style: () => void,
  text: string | undefined,
): void {
  if (text !== undefined) input.value = text;
  style();
  if (text !== undefined) {
    input.focus({ preventScroll: true });
    input.setSelectionRange(input.value.length, input.value.length);
  }
}

export function bindCellDraft(
  input: HTMLTextAreaElement,
  signal: AbortSignal,
  host: {
    start(): void;
    composition(active: boolean): void;
    changed(): void;
    blur(): void;
    reject(error: unknown): void;
  },
): void {
  const options = { signal };
  input.addEventListener(
    "beforeinput",
    (event) => {
      if (!event.inputType.startsWith("insert")) return;
      try {
        host.start();
      } catch (error) {
        event.preventDefault();
        host.reject(error);
      }
    },
    options,
  );
  input.addEventListener(
    "compositionstart",
    () => {
      try {
        host.start();
        host.composition(true);
      } catch (error) {
        host.reject(error);
      }
    },
    options,
  );
  input.addEventListener(
    "compositionend",
    () => host.composition(false),
    options,
  );
  input.addEventListener("input", () => host.changed(), options);
  input.addEventListener("blur", () => host.blur(), options);
}

export function prepareGridInput(input: HTMLTextAreaElement): void {
  Object.assign(input.style, {
    position: "absolute",
    padding: "0",
    border: "0",
    resize: "none",
    font: "14px sans-serif",
    zIndex: "2",
    boxSizing: "border-box",
  });
  input.tabIndex = -1;
  input.autocomplete = "off";
  input.spellcheck = false;
  input.setAttribute("autocapitalize", "off");
  input.setAttribute("aria-label", "Cell input");
}

export function paintGridSelection(
  context: CanvasRenderingContext2D,
  rect: XlsxSelectionGeometry,
  layout: XlsxViewport,
): void {
  context.save();
  context.beginPath();
  context.rect(
    layout.rtl ? 0 : layout.headerWidth,
    layout.headerHeight,
    layout.regions[0]!.width - layout.headerWidth,
    layout.regions[0]!.height - layout.headerHeight,
  );
  context.clip();
  context.fillStyle = "rgba(37, 99, 235, 0.10)";
  context.strokeStyle = "#2563eb";
  context.lineWidth = 1.5;
  for (const piece of rect.rects) {
    context.fillRect(piece.x, piece.y, piece.width, piece.height);
    context.strokeRect(piece.x, piece.y, piece.width, piece.height);
  }
  context.restore();
}

export function styleCellDraft(
  input: HTMLTextAreaElement,
  draft: { address: string } | undefined,
  scale: number,
  layout: XlsxViewport | undefined,
  viewportWidth: number,
  selection: XlsxSelectionGeometry | undefined,
  address: string | undefined,
): void {
  const cell = layout?.cells.find(
    (item) => item.cell.address === (draft?.address ?? address),
  );
  const rect = cell?.rect;
  if (selection) {
    input.style.left = `${Math.max(cell?.clip.x ?? (layout?.rtl ? 0 : layout?.headerWidth) ?? 0, selection.x) * scale}px`;
    input.style.top = `${Math.max(cell?.clip.y ?? layout?.headerHeight ?? 0, selection.y) * scale}px`;
  }
  input.style.opacity = draft ? "1" : "0";
  input.style.pointerEvents = draft ? "auto" : "none";
  input.style.border = draft ? "2px solid #2563eb" : "0";
  input.style.width = draft
    ? `${Math.max(1, Math.min(Math.max(120, (rect?.width ?? 90) * scale), (cell ? (cell.clip.x + cell.clip.width) * scale : viewportWidth) - parseFloat(input.style.left)))}px`
    : "1px";
  input.style.height = draft
    ? `${Math.max(1, Math.min(Math.max(24, (rect?.height ?? 18) * scale), cell ? (cell.clip.y + cell.clip.height) * scale - parseFloat(input.style.top) : Infinity))}px`
    : "1px";
}

interface SpreadsheetKeyHost {
  rtl: boolean;
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
    ArrowLeft: host.rtl ? "right" : "left",
    ArrowRight: host.rtl ? "left" : "right",
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
