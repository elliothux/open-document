import type { XlsxQuery, XlsxViewport } from "../core/xlsx.js";

interface NoteView {
  query: XlsxQuery;
  layout: XlsxViewport | undefined;
  scale: number;
  disabled: boolean;
}
type VisibleNote = XlsxViewport["notes"][number];

/** Passive hints use core-owned visible note rectangles and never select or edit cells. */
export class SpreadsheetNotes {
  private readonly tip = document.createElement("div");
  private hovered: VisibleNote | undefined;
  private dismissed = "";
  private shown = "";
  private selection = "";
  private layout: XlsxViewport | undefined;
  constructor(
    canvas: HTMLCanvasElement,
    holder: HTMLElement,
    private readonly viewport: HTMLElement,
    private readonly input: HTMLTextAreaElement,
    signal: AbortSignal,
    private readonly current: () => NoteView,
  ) {
    this.tip.id = `od-note-${crypto.randomUUID()}`;
    this.tip.hidden = true;
    this.tip.setAttribute("role", "tooltip");
    this.tip.setAttribute("aria-label", "Cell note");
    Object.assign(this.tip.style, {
      position: "absolute",
      zIndex: "4",
      boxSizing: "border-box",
      maxWidth: "280px",
      maxHeight: "200px",
      overflow: "auto",
      whiteSpace: "pre-wrap",
      overflowWrap: "anywhere",
      padding: "8px",
      border: "1px solid #b8a15b",
      borderRadius: "3px",
      background: "#fff9df",
      color: "#171717",
      font: "14px/1.4 sans-serif",
    });
    holder.append(this.tip);
    const options = { signal };
    canvas.addEventListener(
      "pointermove",
      (event) => {
        const now = this.current();
        if (!now.layout || event.buttons) return;
        const bounds = canvas.getBoundingClientRect(),
          x = (event.clientX - bounds.left) / now.scale,
          y = (event.clientY - bounds.top) / now.scale;
        const hovered = now.layout.notes.find(
          ({ rect }) =>
            x >= rect.x &&
            x < rect.x + rect.width &&
            y >= rect.y &&
            y < rect.y + rect.height,
        );
        if (hovered === this.hovered) return;
        this.hovered = hovered;
        this.update();
      },
      options,
    );
    canvas.addEventListener(
      "pointerleave",
      (event) => {
        if (
          event.relatedTarget instanceof Node &&
          this.tip.contains(event.relatedTarget)
        )
          return;
        this.hovered = undefined;
        this.update();
      },
      options,
    );
    this.tip.addEventListener(
      "pointerleave",
      () => {
        this.hovered = undefined;
        this.update();
      },
      options,
    );
    viewport.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Escape" && !this.tip.hidden) {
          this.dismissed = this.shown;
          this.hide();
        }
      },
      { signal, capture: true },
    );
    signal.addEventListener("abort", () => this.hide(), { once: true });
  }
  private hide(): void {
    this.tip.hidden = true;
    if (this.input.getAttribute("aria-describedby") === this.tip.id)
      this.input.removeAttribute("aria-describedby");
  }
  update(): void {
    const now = this.current(),
      layout = now.layout;
    const selection = `${now.query.sheet}:${now.query.revision}:${now.query.selection.address}`;
    if (selection !== this.selection) {
      this.selection = selection;
      this.dismissed = "";
      this.hovered = undefined;
    }
    if (layout !== this.layout) {
      this.hovered = undefined;
      this.layout = layout;
    }
    if (
      !layout ||
      now.disabled ||
      this.viewport.hidden ||
      layout.sheet !== now.query.sheet ||
      layout.revision !== now.query.revision
    ) {
      this.hide();
      return;
    }
    const note =
      this.hovered ??
      (now.query.note.exists
        ? layout.notes.find((note) => note.address === now.query.note.address)
        : undefined);
    if (!note) {
      this.shown = this.dismissed = "";
      this.hide();
      return;
    }
    const key = `${layout.sheet}:${layout.revision}:${note.address}`;
    if (key !== this.shown) this.dismissed = "";
    if (key === this.dismissed) {
      this.hide();
      return;
    }
    this.shown = key;
    this.tip.textContent = `${note.address} — ${note.author}\n${note.text}`;
    const width = layout.regions[0]!.width * now.scale,
      height = layout.regions[0]!.height * now.scale;
    this.tip.style.maxWidth = `${Math.min(280, width)}px`;
    this.tip.style.maxHeight = `${Math.min(200, height)}px`;
    this.tip.style.left = this.tip.style.top = "0px";
    this.tip.hidden = false;
    const x = note.rect.x * now.scale,
      y = note.rect.y * now.scale;
    this.tip.style.left = `${Math.max(0, Math.min(width - this.tip.offsetWidth, x + note.rect.width * now.scale + 4))}px`;
    this.tip.style.top = `${Math.max(0, Math.min(height - this.tip.offsetHeight, y + note.rect.height * now.scale + 4))}px`;
    if (note.address === now.query.note.address && now.query.note.exists)
      this.input.setAttribute("aria-describedby", this.tip.id);
    else if (this.input.getAttribute("aria-describedby") === this.tip.id)
      this.input.removeAttribute("aria-describedby");
  }
}
