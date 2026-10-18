import type { PptxQuery } from "@open-document/wasm/pptx";
import type {
  PptxShowAction,
  PptxShowLayout,
  PptxShowState,
} from "@open-document/wasm/pptx";
import type { PptxClient } from "./pptx.js";
import { PresentationCanvas } from "./presentation-canvas.js";

export interface PresentationShowLabels {
  title: string;
  current: string;
  next: string;
  previous: string;
  first: string;
  last: string;
  end: string;
  fullscreen: string;
  presenter: string;
  notes: string;
  elapsed: string;
  jump: string;
  pause: string;
  resume: string;
}
const english: PresentationShowLabels = {
  title: "Slideshow",
  current: "Current slide",
  next: "Next slide",
  previous: "Previous slide",
  first: "First slide",
  last: "Last slide",
  end: "End slideshow",
  fullscreen: "Fullscreen",
  presenter: "Presenter view",
  notes: "Speaker notes",
  elapsed: "Elapsed time",
  jump: "Go to slide",
  pause: "Pause",
  resume: "Resume",
};

/** Core navigation and drawing remain bound to the editor's committed revision. */
export class PresentationShow {
  private current: PptxShowState | undefined;
  private starting = false;
  private busy = false;
  private dialog: HTMLDialogElement | undefined;
  private stage: HTMLDivElement | undefined;
  private surfaces: PresentationCanvas[] = [];
  private drawing: PptxShowLayout | undefined;
  private listeners: AbortController | undefined;
  private timer: number | undefined;
  private count: HTMLElement | undefined;
  private notes: HTMLElement | undefined;
  private text: HTMLElement | undefined;
  private error: HTMLElement | undefined;
  private jump: HTMLSelectElement | undefined;
  private presenter = false;
  private revision = 0;
  private closed = false;
  private frame = 0;
  private framePending = false;
  private started = 0;
  private pause: HTMLButtonElement | undefined;
  private labels: PresentationShowLabels = english;
  constructor(
    private readonly client: PptxClient,
    private readonly profile: Record<string, string>,
    private readonly run: (operation: () => Promise<void>) => Promise<void>,
    private readonly query: () => PptxQuery,
    private readonly restore: () => Promise<void>,
    private readonly canStart: () => boolean,
    private readonly root: HTMLElement,
  ) {}
  get active(): boolean {
    return this.starting || this.current?.active === true;
  }
  get state(): PptxShowState | undefined {
    return structuredClone(this.current);
  }
  start(
    from: "first" | "current" | { show: string } = "first",
    labels: PresentationShowLabels = english,
  ): Promise<void> {
    if (this.closed || this.active || !this.canStart())
      return Promise.reject(
        new Error("Slideshow is already active or disposed"),
      );
    if (
      from !== "first" &&
      from !== "current" &&
      (typeof from !== "object" ||
        from === null ||
        Object.keys(from).length !== 1 ||
        typeof from.show !== "string")
    )
      return Promise.reject(new Error("Invalid slideshow start"));
    this.starting = true;
    return this.run(async () => {
      const query = this.query();
      this.revision = query.revision;
      this.started = performance.now();
      try {
        this.current = await this.client.execute({
          operation: "controlShowPptx",
          time: this.time(),
          revision: this.revision,
          action: "start",
          slide: from === "current" ? query.slide : "",
          ...(typeof from === "object" ? { custom: from.show } : {}),
        });
        this.createDialog(labels, query);
        await this.paint();
      } catch (error) {
        if (this.current?.active)
          await this.client.execute({
            operation: "controlShowPptx",
            time: this.time(),
            revision: this.revision,
            action: "end",
            slide: "",
          });
        this.release();
        await this.restore();
        throw error;
      }
    }).finally(() => {
      this.starting = false;
    });
  }
  navigate(
    action: Exclude<PptxShowAction, "start">,
    slide = "",
  ): Promise<void> {
    if (this.closed || !this.current?.active || this.busy)
      return Promise.reject(new Error("Slideshow is inactive or busy"));
    this.busy = true;
    return this.run(async () => {
      const state = await this.client.execute({
        operation: "controlShowPptx",
        time: this.time(),
        revision: this.revision,
        action,
        slide,
      });
      this.current = state;
      if (state.active) await this.paint();
      else {
        this.release();
        await this.restore();
      }
    }).finally(() => {
      this.busy = false;
    });
  }
  end(): Promise<void> {
    return this.active ? this.navigate("end") : Promise.resolve();
  }
  private handle(action: () => Promise<void>): void {
    if (this.busy) return;
    void action().catch((error) => {
      if (this.error)
        this.error.textContent =
          error instanceof Error ? error.message : String(error);
    });
  }
  private createDialog(labels: PresentationShowLabels, query: PptxQuery): void {
    this.labels = labels;
    const dialog = document.createElement("dialog"),
      stage = document.createElement("div"),
      events = new AbortController();
    this.dialog = dialog;
    this.stage = stage;
    this.listeners = events;
    dialog.setAttribute("aria-label", labels.title);
    Object.assign(dialog.style, {
      width: "96vw",
      maxWidth: "none",
      maxHeight: "96vh",
      padding: "12px",
      background: "#111827",
      color: "#ffffff",
    });
    const heading = document.createElement("h2"),
      count = document.createElement("p"),
      error = document.createElement("p");
    heading.textContent = labels.title;
    count.setAttribute("aria-live", "polite");
    error.setAttribute("role", "alert");
    this.count = count;
    this.error = error;
    dialog.append(heading, count, error);
    const controls = document.createElement("div");
    const button = (label: string, action: () => Promise<void>) => {
      const element = document.createElement("button");
      element.type = "button";
      element.textContent = label;
      element.addEventListener("click", () => this.handle(action), {
        signal: events.signal,
      });
      controls.append(element);
      return element;
    };
    for (const [label, action] of [
      [labels.first, "first"],
      [labels.previous, "previous"],
      [labels.next, "next"],
      [labels.last, "last"],
    ] as const)
      button(label, () => this.navigate(action));
    const jump = document.createElement("select");
    jump.setAttribute("aria-label", labels.jump);
    this.jump = jump;
    for (const [index, id] of this.current!.order.entries()) {
      const slide = query.slides.find((slide) => slide.id === id)!;
      const option = document.createElement("option");
      option.value = String(index);
      option.textContent = `${index + 1}. ${slide.title}`;
      jump.append(option);
    }
    jump.addEventListener(
      "change",
      () => this.handle(() => this.navigate("gotoPosition", jump.value)),
      { signal: events.signal },
    );
    controls.append(jump);
    button(labels.fullscreen, async () => {
      if (stage.matches(":fullscreen")) await document.exitFullscreen();
      else await stage.requestFullscreen();
    });
    const presenter = button(labels.presenter, async () => {
      this.presenter = !this.presenter;
      presenter.setAttribute("aria-pressed", String(this.presenter));
      this.resize();
    });
    presenter.setAttribute("aria-pressed", "false");
    this.pause = button(labels.pause, () =>
      this.navigate(this.current?.paused ? "resume" : "pause"),
    );
    button(labels.end, () => this.end());
    const elapsed = document.createElement("p"),
      started = performance.now();
    const tick = () => {
      const seconds = Math.floor((performance.now() - started) / 1000);
      elapsed.textContent = `${labels.elapsed}: ${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
    };
    tick();
    this.timer = window.setInterval(tick, 1000);
    const pages = document.createElement("div");
    Object.assign(pages.style, {
      display: "flex",
      gap: "12px",
      alignItems: "start",
    });
    for (const label of [labels.current, labels.next]) {
      const surface = new PresentationCanvas(),
        section = document.createElement("section"),
        title = document.createElement("h3");
      section.setAttribute("aria-label", label);
      section.style.minWidth = "0";
      section.style.flex = "1";
      title.textContent = label;
      section.append(title, surface.canvas);
      pages.append(section);
      this.surfaces.push(surface);
    }
    const text = document.createElement("p"),
      notes = document.createElement("pre");
    Object.assign(text.style, {
      position: "absolute",
      width: "1px",
      height: "1px",
      overflow: "hidden",
      clipPath: "inset(50%)",
    });
    text.setAttribute("aria-label", labels.current);
    notes.setAttribute("aria-label", labels.notes);
    notes.style.whiteSpace = "pre-wrap";
    this.text = text;
    this.notes = notes;
    dialog.append(controls, elapsed, pages, text, notes);
    stage.append(dialog);
    this.root.append(stage);
    dialog.addEventListener(
      "cancel",
      (event) => {
        event.preventDefault();
        this.handle(() => this.end());
      },
      { signal: events.signal },
    );
    dialog.addEventListener(
      "keydown",
      (event) => {
        if (
          event.target instanceof HTMLSelectElement ||
          event.altKey ||
          event.ctrlKey ||
          event.metaKey
        )
          return;
        const actions: Partial<
          Record<string, Exclude<PptxShowAction, "start">>
        > = {
          ArrowRight: "next",
          ArrowDown: "next",
          PageDown: "next",
          ArrowLeft: "previous",
          ArrowUp: "previous",
          PageUp: "previous",
          Home: "first",
          End: "last",
        };
        const action = actions[event.key];
        if (action) {
          event.preventDefault();
          this.handle(() => this.navigate(action));
        } else if (
          (event.key === " " || event.key === "Enter") &&
          event.target === dialog
        ) {
          event.preventDefault();
          this.handle(() => this.navigate("next"));
        }
      },
      { signal: events.signal },
    );
    this.surfaces[0]!.canvas.addEventListener(
      "click",
      () => this.handle(() => this.navigate("click")),
      { signal: events.signal },
    );
    window.addEventListener("resize", () => this.resize(), {
      signal: events.signal,
    });
    dialog.showModal();
    dialog.tabIndex = -1;
    dialog.focus();
  }
  private async paint(): Promise<void> {
    for (const surface of this.surfaces)
      surface.canvas.parentElement!.hidden = true;
    for (const surface of this.surfaces) await surface.prepareShow(this.client);
    await this.paintFrame();
    this.scheduleFrame();
  }
  private time(): number {
    return Math.min(1000000000, Math.max(0, performance.now() - this.started));
  }
  private async paintFrame(): Promise<void> {
    const state = await this.client.execute({
      operation: "controlShowPptx",
      time: this.time(),
      revision: this.revision,
      action: "tick",
      slide: "",
    });
    const changed = state.slide !== this.current?.slide;
    this.current = state;
    if (!state.active) {
      this.release();
      await this.restore();
      return;
    }
    if (changed)
      for (const surface of this.surfaces)
        await surface.prepareShow(this.client);
    this.drawing = await this.client.execute({
      operation: "layoutShowPptx",
      time: this.time(),
      revision: this.revision,
      profile: this.profile,
    });
    if (
      this.closed ||
      !this.current?.active ||
      this.drawing.revision !== this.revision
    )
      throw new Error("Slideshow changed before drawing");
    this.count!.textContent = `${this.current.position + 1} / ${this.current.order.length}`;
    this.notes!.textContent =
      this.current.notes.reason || this.current.notes.text;
    this.text!.textContent = this.current.text;
    this.jump!.value = String(this.current.position);
    this.pause!.textContent = this.current.paused
      ? this.labels.resume
      : this.labels.pause;
    this.error!.textContent = "";
    this.resize();
    if (!this.drawing.animating)
      for (const surface of this.surfaces)
        await surface.prepareShow(this.client);
  }
  private scheduleFrame(): void {
    if (
      this.frame ||
      this.closed ||
      !this.current?.active ||
      !this.drawing?.animating
    )
      return;
    this.frame = requestAnimationFrame(() => {
      this.frame = 0;
      if (this.busy || this.framePending) {
        this.scheduleFrame();
        return;
      }
      this.framePending = true;
      void this.run(async () => {
        if (!this.busy && this.current?.active) await this.paintFrame();
      })
        .catch((error) => {
          if (this.error)
            this.error.textContent =
              error instanceof Error ? error.message : String(error);
          this.drawing = undefined;
        })
        .finally(() => {
          this.framePending = false;
          this.scheduleFrame();
        });
    });
  }
  private resize(): void {
    if (!this.drawing || !this.dialog) return;
    for (const [index, surface] of this.surfaces.entries()) {
      const holder = surface.canvas.parentElement!,
        page = this.drawing.regions[index];
      holder.hidden = !page || (index === 1 && !this.presenter);
      if (!page || holder.hidden) continue;
      const zoom = Math.max(
        0.25,
        Math.min(
          2,
          (holder.clientWidth * 72) / (96 * page.width),
          ((window.innerHeight - 240) * 72) / (96 * page.height),
        ),
      );
      surface.draw(this.drawing, index, zoom);
      surface.canvas.style.maxWidth = "100%";
      surface.canvas.style.height = "auto";
    }
    this.notes!.hidden = !this.presenter;
  }
  private release(): void {
    cancelAnimationFrame(this.frame);
    this.frame = 0;
    this.listeners?.abort();
    this.listeners = undefined;
    if (this.timer !== undefined) window.clearInterval(this.timer);
    this.timer = undefined;
    this.dialog?.close();
    this.dialog?.remove();
    this.dialog = undefined;
    this.stage?.remove();
    this.stage = undefined;
    for (const surface of this.surfaces) surface.dispose();
    this.surfaces = [];
    this.drawing = undefined;
    this.current = undefined;
    this.presenter = false;
  }
  async dispose(): Promise<void> {
    this.closed = true;
    try {
      if (this.current?.active)
        await this.client.execute({
          operation: "controlShowPptx",
          time: this.time(),
          revision: this.revision,
          action: "end",
          slide: "",
        });
    } finally {
      this.release();
    }
  }
}
