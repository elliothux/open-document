import type { PdfPlacement } from "../core/pdf.js";

export interface PdfObjectDragView {
  canvas: HTMLCanvasElement;
  page: string;
  scale: number;
}
export interface PdfObjectDragOptions {
  view(): PdfObjectDragView | undefined;
  placement(): PdfPlacement;
  inputs: { root: HTMLElement; x: HTMLInputElement; y: HTMLInputElement };
  /** Validate the draft and switch text objects to geometry editing. */
  beforeStart(): boolean;
  change(): void;
}
interface Gesture {
  pointer: number;
  view: PdfObjectDragView;
  startX: number;
  startY: number;
  x: number;
  y: number;
  rawX: string;
  rawY: string;
}

/** A movable candidate box; source content changes only through Apply. */
export class PdfObjectDrag {
  readonly element = document.createElement("div");
  private readonly events = new AbortController();
  private selected: { page: string; object: string } | undefined;
  private gesture: Gesture | undefined;
  private pending: Pick<Gesture, "rawX" | "rawY"> | undefined;

  constructor(private readonly options: PdfObjectDragOptions) {
    this.element.tabIndex = 0;
    this.element.setAttribute("role", "button");
    this.element.dataset.pdfObjectMove = "";
    this.setLocale("en-US");
    Object.assign(this.element.style, {
      position: "absolute",
      boxSizing: "border-box",
      border: "2px dashed #2563eb",
      background: "rgba(37,99,235,0.04)",
      cursor: "move",
      touchAction: "none",
      transformOrigin: "0 0",
      zIndex: "2",
    });
    const signal = this.events.signal;
    for (const event of ["input", "change"] as const)
      options.inputs.root.addEventListener(event, () => this.render(), {
        signal,
      });
    this.element.addEventListener(
      "pointerdown",
      (event) => {
        if (
          event.button !== 0 ||
          event.isPrimary === false ||
          this.gesture ||
          !this.selected ||
          !options.beforeStart()
        )
          return;
        const view = options.view(),
          placement = options.placement();
        if (
          !view ||
          view.page !== this.selected.page ||
          !view.canvas.isConnected ||
          !this.valid(placement)
        )
          return;
        event.preventDefault();
        event.stopPropagation();
        const bounds = view.canvas.getBoundingClientRect();
        this.gesture = {
          pointer: event.pointerId,
          view,
          startX: (event.clientX - bounds.left) / view.scale,
          startY: (event.clientY - bounds.top) / view.scale,
          x: placement.x,
          y: placement.y,
          rawX: options.inputs.x.value,
          rawY: options.inputs.y.value,
        };
        this.pending = {
          rawX: options.inputs.x.value,
          rawY: options.inputs.y.value,
        };
        this.element.focus({ preventScroll: true });
        this.element.setPointerCapture(event.pointerId);
        options.change();
      },
      { signal },
    );
    this.element.addEventListener("pointermove", (event) => this.move(event), {
      signal,
    });
    this.element.addEventListener(
      "pointerup",
      (event) => {
        if (event.pointerId !== this.gesture?.pointer) return;
        this.move(event);
        this.release();
        options.change();
      },
      { signal },
    );
    for (const event of ["pointercancel", "lostpointercapture"] as const)
      this.element.addEventListener(
        event,
        () => {
          if (this.gesture) this.cancel();
        },
        { signal },
      );
    this.element.addEventListener(
      "keydown",
      (event) => {
        if (
          event.key === "Escape" &&
          !event.isComposing &&
          (this.gesture || this.pending)
        ) {
          event.preventDefault();
          event.stopPropagation();
          this.cancel();
        }
      },
      { signal },
    );
    window.addEventListener(
      "blur",
      () => {
        if (this.gesture) this.cancel();
      },
      { signal },
    );
  }
  setLocale(locale: "zh-CN" | "en-US"): void {
    this.element.setAttribute(
      "aria-label",
      locale === "zh-CN" ? "移动所选 PDF 对象" : "Move selected PDF object",
    );
    this.element.title =
      locale === "zh-CN"
        ? "拖动仅预览位置，确认后应用；Esc 取消本次拖动"
        : "Drag previews position; Apply commits; Escape cancels this gesture";
  }
  get dragging(): boolean {
    return this.gesture !== undefined;
  }
  show(page?: string, object?: string): void {
    if (this.selected?.page !== page || this.selected?.object !== object) {
      this.release();
      this.pending = undefined;
    }
    this.selected = page && object ? { page, object } : undefined;
    this.render();
  }
  private valid(placement: PdfPlacement): boolean {
    return (
      Object.values(placement).every(
        (value) => Number.isFinite(value) && Math.abs(value) <= 14400,
      ) &&
      placement.width > 0 &&
      placement.height > 0
    );
  }
  private move(event: PointerEvent): void {
    const gesture = this.gesture;
    if (!gesture || gesture.pointer !== event.pointerId) return;
    const view = this.options.view();
    if (
      !view ||
      view.canvas !== gesture.view.canvas ||
      view.page !== gesture.view.page ||
      view.scale !== gesture.view.scale ||
      !view.canvas.isConnected
    ) {
      this.cancel();
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    const bounds = view.canvas.getBoundingClientRect();
    this.options.inputs.x.value = String(
      gesture.x + (event.clientX - bounds.left) / view.scale - gesture.startX,
    );
    this.options.inputs.y.value = String(
      gesture.y + (event.clientY - bounds.top) / view.scale - gesture.startY,
    );
    this.render();
    this.options.change();
  }
  private render(): void {
    const view = this.options.view(),
      placement = this.options.placement();
    const host =
      view?.canvas.offsetParent instanceof HTMLElement
        ? view.canvas.offsetParent
        : view?.canvas.parentElement;
    if (
      !this.selected ||
      !view ||
      view.page !== this.selected.page ||
      !host ||
      !this.valid(placement)
    ) {
      this.element.remove();
      return;
    }
    if (this.element.parentElement !== host) host.append(this.element);
    Object.assign(this.element.style, {
      left: `${view.canvas.offsetLeft + placement.x * view.scale}px`,
      top: `${view.canvas.offsetTop + placement.y * view.scale}px`,
      width: `${placement.width * view.scale}px`,
      height: `${placement.height * view.scale}px`,
      transform: `rotate(${placement.rotation}deg)`,
    });
  }
  private release(): void {
    const gesture = this.gesture;
    this.gesture = undefined;
    if (gesture && this.element.hasPointerCapture(gesture.pointer))
      this.element.releasePointerCapture(gesture.pointer);
  }
  cancel(): void {
    const original = this.gesture ?? this.pending;
    this.release();
    this.pending = undefined;
    if (original) {
      this.options.inputs.x.value = original.rawX;
      this.options.inputs.y.value = original.rawY;
      this.render();
      this.options.change();
    }
  }
  dispose(): void {
    this.cancel();
    this.events.abort();
    this.selected = undefined;
    this.element.remove();
  }
}
