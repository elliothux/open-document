import type { XlsxCell } from "../core/xlsx.js";
import { prepareGridInput } from "./spreadsheet-input.js";

/** Both views use one native input, so switching keeps its draft and native undo. */
export class SpreadsheetFormula {
  readonly element = document.createElement("div");
  private readonly mirror = document.createElement("textarea");
  private active = false;
  switching = false;

  constructor(
    private readonly input: HTMLTextAreaElement,
    private readonly holder: HTMLElement,
    signal: AbortSignal,
    edit: () => void,
  ) {
    this.element.append(this.mirror);
    this.mirror.readOnly = true;
    this.element.addEventListener(
      "pointerdown",
      (event) => {
        if (this.active || event.button !== 0 || this.mirror.disabled) return;
        event.preventDefault();
        edit();
      },
      { signal },
    );
    this.mirror.addEventListener("focus", edit, { signal });
  }

  show(active: boolean): void {
    if (active === this.active) return;
    this.switching = true;
    const { selectionStart, selectionEnd, selectionDirection } = this.input;
    const focused = this.input.matches(":focus");
    const gridStyle = (this.active ? this.mirror : this.input).style.cssText;
    try {
      this.active = active;
      this.element.append(active ? this.input : this.mirror);
      this.holder.append(active ? this.mirror : this.input);
      this.input.style.cssText = "";
      this.mirror.style.cssText = "";
      (active ? this.mirror : this.input).style.cssText = gridStyle;
      prepareGridInput(active ? this.mirror : this.input);
      if (active || focused) this.input.focus({ preventScroll: true });
      this.input.setSelectionRange(
        selectionStart,
        selectionEnd,
        selectionDirection,
      );
    } finally {
      this.switching = false;
    }
  }

  prepare(): void {
    if (this.active) this.input.style.cssText = this.mirror.style.cssText;
  }

  update(
    draft: boolean,
    cell: XlsxCell | undefined,
    unavailable: boolean,
  ): void {
    const bar = this.active ? this.input : this.mirror;
    this.input.setAttribute("aria-label", `Cell ${cell?.address ?? ""} input`);
    this.input.setAttribute(
      "aria-description",
      `${cell?.display ?? ""}${cell?.readOnlyReason ? "; " + cell.readOnlyReason : ""}`,
    );
    this.mirror.hidden = this.active && !draft;
    this.mirror.value = draft ? this.input.value : (cell?.input ?? "");
    this.mirror.disabled = !this.active && unavailable;
    this.mirror.tabIndex = this.active ? -1 : 0;
    this.mirror.setAttribute("aria-hidden", String(this.active));
    this.mirror.removeAttribute("aria-label");
    if (this.active) {
      this.mirror.style.cssText = this.input.style.cssText;
      this.mirror.style.pointerEvents = "none";
      if (!draft) this.input.value = cell?.input ?? "";
    }
    bar.setAttribute("aria-label", "Formula input");
    bar.setAttribute("aria-description", cell?.readOnlyReason ?? "");
    Object.assign(bar.style, {
      position: "static",
      left: "auto",
      top: "auto",
      width: "100%",
      height: "28px",
      minHeight: "28px",
      maxHeight: "160px",
      boxSizing: "border-box",
      padding: "3px 5px",
      border: "1px solid #cbd5e1",
      font: "14px sans-serif",
      opacity: "1",
      pointerEvents: "auto",
      resize: "none",
    });
  }
}
