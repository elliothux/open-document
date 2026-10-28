import type { PdfPlacement } from "../core/pdf.js";

/** Native ink input participates in the editor's existing composition barrier. */
export class PdfInkInputs {
  readonly element = document.createElement("div");
  readonly strokes = document.createElement("textarea");
  readonly signature = document.createElement("input");
  readonly pad = document.createElement("canvas");
  private readonly events = new AbortController();
  private active:
    { pointer: number; previous: string; paths: number[][] } | undefined;
  constructor(
    private readonly change: () => void,
    private readonly placement: () => PdfPlacement = () => ({
      x: 0,
      y: 0,
      width: 200,
      height: 100,
      rotation: 0,
    }),
  ) {
    this.pad.width = 400;
    this.pad.height = 160;
    this.pad.tabIndex = 0;
    this.pad.style.touchAction = "none";
    this.pad.style.maxWidth = "100%";
    this.pad.setAttribute("aria-label", "Draw ink or a visual signature");
    const padLabel = document.createElement("div"),
      padCaption = document.createElement("span");
    padLabel.dataset.pdfControl = "ink-pad";
    padCaption.textContent = this.pad.getAttribute("aria-label");
    padLabel.append(padCaption, this.pad);
    this.element.append(padLabel);
    this.strokes.setAttribute(
      "aria-label",
      "Ink strokes: one x,y path per line",
    );
    this.strokes.rows = 4;
    this.strokes.maxLength = 262144;
    this.signature.type = "checkbox";
    this.signature.setAttribute("aria-label", "Visual signature appearance");
    for (const [key, input] of [
      ["ink-strokes", this.strokes],
      ["ink-signature", this.signature],
    ] as const) {
      const label = document.createElement("label"),
        caption = document.createElement("span");
      label.dataset.pdfControl = key;
      caption.textContent = input.getAttribute("aria-label");
      label.append(caption, input);
      this.element.append(label);
    }
    this.element.addEventListener("input", change);
    this.element.addEventListener("change", change);
    const signal = this.events.signal;
    this.strokes.addEventListener(
      "input",
      () => {
        this.strokes.setCustomValidity("");
        this.draw();
      },
      { signal },
    );
    this.pad.addEventListener(
      "pointerdown",
      (event) => {
        if (this.strokes.disabled || this.active || event.button !== 0) return;
        let paths: number[][];
        try {
          paths = this.parse(true);
        } catch (error) {
          this.strokes.setCustomValidity(
            error instanceof Error ? error.message : "Invalid ink strokes",
          );
          this.strokes.reportValidity();
          return;
        }
        if (
          paths.reduce((total, path) => total + path.length, 0) >= 32764 ||
          paths.length >= 4096
        ) {
          this.strokes.setCustomValidity("Ink exceeds the stroke budget");
          this.strokes.reportValidity();
          return;
        }
        const point = this.point(event);
        if (!point) return;
        this.active = {
          pointer: event.pointerId,
          previous: this.strokes.value,
          paths: [...paths, point],
        };
        this.pad.focus();
        this.pad.setPointerCapture(event.pointerId);
        event.preventDefault();
        this.draw();
        change();
      },
      { signal },
    );
    this.pad.addEventListener(
      "pointermove",
      (event) => {
        const active = this.active;
        if (!active || active.pointer !== event.pointerId) return;
        const point = this.point(event);
        if (!point) return;
        if (
          active.paths.reduce((total, path) => total + path.length, 0) >= 32766
        ) {
          this.cancelStroke();
          this.strokes.setCustomValidity("Ink exceeds the stroke budget");
          this.strokes.reportValidity();
          return;
        }
        active.paths[active.paths.length - 1]!.push(...point);
        event.preventDefault();
        this.draw();
        change();
      },
      { signal },
    );
    this.pad.addEventListener(
      "pointerup",
      (event) => {
        const active = this.active;
        if (!active || active.pointer !== event.pointerId) return;
        const path = active.paths[active.paths.length - 1]!;
        const point = this.point(event);
        if (
          point &&
          active.paths.reduce((total, path) => total + path.length, 0) <=
            32766 &&
          (path[path.length - 2] !== point[0] ||
            path[path.length - 1] !== point[1])
        )
          path.push(...point);
        if (path.length === 2) path.push(...path);
        this.strokes.value = active.paths
          .map((points) => points.join(", "))
          .join("\n");
        this.active = undefined;
        if (this.pad.hasPointerCapture(event.pointerId))
          this.pad.releasePointerCapture(event.pointerId);
        event.preventDefault();
        this.draw();
        change();
      },
      { signal },
    );
    this.pad.addEventListener("pointercancel", () => this.cancelStroke(), {
      signal,
    });
    this.pad.addEventListener("lostpointercapture", () => this.cancelStroke(), {
      signal,
    });
    this.pad.addEventListener("blur", () => this.cancelStroke(), { signal });
    this.pad.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Escape" && this.active) {
          event.preventDefault();
          event.stopPropagation();
          this.cancelStroke();
        }
      },
      { signal },
    );
    this.draw();
  }
  get dragging(): boolean {
    return this.active !== undefined;
  }
  get signatureKey(): string {
    return JSON.stringify([
      this.strokes.value,
      this.signature.checked,
      this.active?.paths[this.active.paths.length - 1]?.length ?? 0,
    ]);
  }
  set(strokes: readonly (readonly number[])[], signature: boolean): void {
    this.cancelStroke();
    this.strokes.setCustomValidity("");
    this.strokes.value = strokes.map((path) => path.join(", ")).join("\n");
    this.signature.checked = signature;
    this.draw();
  }
  read(): { strokes: number[][]; signature: boolean } {
    if (this.active)
      throw new Error(
        "Finish or cancel the current ink stroke before applying",
      );
    if (this.strokes.validationMessage)
      throw new Error(this.strokes.validationMessage);
    return { strokes: this.parse(false), signature: this.signature.checked };
  }
  private parse(empty: boolean): number[][] {
    const strokes = this.strokes.value
      .split(/\r?\n/)
      .filter((line) => line.trim() !== "")
      .map((line) =>
        line
          .trim()
          .split(/[,\s]+/)
          .map(Number),
      );
    if (
      (!empty && !strokes.length) ||
      strokes.length > 4096 ||
      strokes.some(
        (path) =>
          path.length < 4 ||
          path.length % 2 !== 0 ||
          path.some((value) => !Number.isFinite(value)),
      ) ||
      strokes.reduce((count, path) => count + path.length, 0) > 32768
    )
      throw new Error("Ink requires bounded x,y stroke pairs");
    return strokes;
  }
  show(visible: boolean, disabled: boolean): void {
    this.element.hidden = !visible;
    this.strokes.disabled = this.signature.disabled = disabled;
    this.pad.setAttribute("aria-disabled", String(disabled));
    if (!visible || disabled) this.cancelStroke();
  }
  private point(event: PointerEvent): number[] | undefined {
    const bounds = this.pad.getBoundingClientRect(),
      p = this.placement();
    if (!bounds.width || !bounds.height || !(p.width > 0 && p.height > 0))
      return;
    const x =
      p.x +
      Math.max(0, Math.min(1, (event.clientX - bounds.left) / bounds.width)) *
        p.width;
    const y =
      p.y +
      Math.max(0, Math.min(1, (event.clientY - bounds.top) / bounds.height)) *
        p.height;
    return [x, y];
  }
  private draw(): void {
    const context = this.pad.getContext("2d"),
      p = this.placement();
    if (!context) return;
    context.fillStyle = "#fff";
    context.fillRect(0, 0, this.pad.width, this.pad.height);
    context.strokeStyle = "#64748b";
    context.strokeRect(0.5, 0.5, this.pad.width - 1, this.pad.height - 1);
    let paths: number[][];
    try {
      paths = this.active?.paths ?? this.parse(true);
    } catch {
      return;
    }
    if (!(p.width > 0 && p.height > 0)) return;
    context.strokeStyle = "#111827";
    context.lineWidth = 2;
    context.lineCap = "round";
    context.lineJoin = "round";
    for (const path of paths) {
      if (path.length < 2) continue;
      context.beginPath();
      context.moveTo(
        ((path[0]! - p.x) / p.width) * this.pad.width,
        ((path[1]! - p.y) / p.height) * this.pad.height,
      );
      for (let index = 2; index < path.length; index += 2)
        context.lineTo(
          ((path[index]! - p.x) / p.width) * this.pad.width,
          ((path[index + 1]! - p.y) / p.height) * this.pad.height,
        );
      context.stroke();
    }
  }
  private cancelStroke(): void {
    const active = this.active;
    if (!active) return;
    this.active = undefined;
    this.strokes.value = active.previous;
    if (this.pad.hasPointerCapture(active.pointer))
      this.pad.releasePointerCapture(active.pointer);
    this.draw();
    this.change();
  }
  dispose(): void {
    this.cancelStroke();
    this.events.abort();
    this.element.removeEventListener("input", this.change);
    this.element.removeEventListener("change", this.change);
    this.pad.width = this.pad.height = 0;
  }
}
