import {
  mediaImageCommand,
  type PptxShowLayout,
  type PptxShowState,
  type PptxShowMediaState,
  type PptxShowMediaChange,
} from "@open-document/wasm/pptx";
import type { DrawCommand } from "@open-document/wasm/drawing";
import type { PptxClient } from "./pptx.js";

export interface PresentationMediaLabels {
  mediaTitle: string;
  mediaPlay: string;
  mediaPause: string;
  mediaStop: string;
}
interface Player {
  token: number;
  video: HTMLVideoElement;
  events: AbortController;
  url: string;
  bytes: number;
  pixels: number;
  want: boolean;
  started: boolean;
  failed: boolean;
  closed: boolean;
  timer: number;
  feedbackError: string;
}
interface Row {
  element: HTMLDivElement;
  play: HTMLButtonElement;
  stop: HTMLButtonElement;
  reason: HTMLParagraphElement;
  error: string;
  token: number;
  state: string;
}

/** Browser decoders follow core playback instances; drawing commands retain all geometry. */
export class PresentationShowMedia {
  private readonly players = new Map<string, Player>();
  private readonly rows = new Map<string, Row>();
  private readonly panel = document.createElement("section");
  private state: PptxShowState | undefined;
  private closed = false;
  constructor(
    private readonly client: PptxClient,
    controls: HTMLElement,
    signal: AbortSignal,
    private readonly labels: PresentationMediaLabels,
    private readonly send: (change: PptxShowMediaChange) => Promise<void>,
    private readonly redraw: () => void,
  ) {
    this.panel.setAttribute("aria-label", labels.mediaTitle);
    Object.assign(this.panel.style, {
      height: "min(160px, 22vh)",
      overflow: "auto",
    });
    controls.append(this.panel);
    signal.addEventListener("abort", () => this.dispose(), { once: true });
  }
  get animating(): boolean {
    return Array.from(this.players.values()).some(
      (player) =>
        player.want &&
        !player.closed &&
        !player.failed &&
        player.video.videoWidth > 0 &&
        !player.video.paused &&
        !player.video.ended,
    );
  }
  async update(state: PptxShowState): Promise<void> {
    if (this.closed) return;
    this.state = state;
    const entries = new Map(state.media.map((item) => [item.object, item]));
    for (const [id, player] of this.players) {
      const current = entries.get(id);
      if (
        !current ||
        current.token !== player.token ||
        ["stopped", "error"].includes(current.state)
      )
        this.drop(id, player);
    }
    for (const [id, row] of this.rows)
      if (!entries.has(id)) {
        row.element.remove();
        this.rows.delete(id);
      }
    for (const media of state.media) {
      let row = this.rows.get(media.object);
      if (!row) {
        const element = document.createElement("div"),
          name = document.createElement("span"),
          play = document.createElement("button"),
          stop = document.createElement("button"),
          reason = document.createElement("p");
        element.setAttribute("role", "group");
        element.setAttribute("aria-label", media.label || media.kind);
        name.textContent = media.label || media.kind;
        play.type = stop.type = "button";
        stop.textContent = this.labels.mediaStop;
        play.addEventListener("click", () => this.action(media.object));
        stop.addEventListener("click", () => this.action(media.object, "stop"));
        element.append(name, play, stop, reason);
        this.panel.append(element);
        row = {
          element,
          play,
          stop,
          reason,
          error: "",
          token: media.token,
          state: media.state,
        };
        this.rows.set(media.object, row);
      }
      if (row.token !== media.token || row.state !== media.state)
        row.error = "";
      row.token = media.token;
      row.state = media.state;
      row.play.textContent =
        media.state === "playing"
          ? this.labels.mediaPause
          : this.labels.mediaPlay;
      row.play.disabled =
        state.paused ||
        (media.state !== "playing" && !media.visible) ||
        (media.token === 0 && !!media.reason);
      row.stop.disabled = media.state === "stopped" || media.token === 0;
      row.reason.textContent =
        media.reason ||
        this.players.get(media.object)?.feedbackError ||
        row.error;
      row.reason.setAttribute(
        "role",
        ["error", "blocked"].includes(media.state) ||
          !!row.error ||
          !!this.players.get(media.object)?.feedbackError
          ? "alert"
          : "status",
      );
      if (media.state === "playing" && !this.players.has(media.object))
        await this.create(media);
      const player = this.players.get(media.object);
      if (player) this.apply(media, player);
    }
    this.panel.hidden = !state.media.length;
  }
  private action(object: string, action?: "stop"): void {
    const media = this.state?.media.find((item) => item.object === object);
    if (!media || this.closed) return;
    const row = this.rows.get(object);
    if (row) row.error = "";
    void this.send({
      object,
      token: media.token,
      action: action ?? (media.state === "playing" ? "pause" : "play"),
    }).catch((error) => {
      const row = this.rows.get(object);
      if (row && !this.closed) {
        row.error = error instanceof Error ? error.message : String(error);
        row.reason.textContent = row.error;
        row.reason.setAttribute("role", "alert");
      }
    });
  }
  private alive(id: string, player: Player): boolean {
    return !this.closed && !player.closed && this.players.get(id) === player;
  }
  private async create(media: PptxShowMediaState): Promise<void> {
    const video = document.createElement("video"),
      events = new AbortController();
    const player: Player = {
      token: media.token,
      video,
      events,
      url: "",
      bytes: 0,
      pixels: 0,
      want: false,
      started: false,
      failed: false,
      closed: false,
      timer: 0,
      feedbackError: "",
    };
    this.players.set(media.object, player);
    player.timer = window.setTimeout(
      () =>
        this.fail(media.object, player, "error", "Media decoding timed out"),
      10000,
    );
    video.preload = "auto";
    video.playsInline = true;
    const feedback = (action: "ended" | "paused") => {
      if (!this.alive(media.object, player) || player.failed) return;
      player.want = false;
      void this.send({
        object: media.object,
        token: player.token,
        action,
      }).catch((error) => this.feedbackFailure(media.object, player, error));
    };
    video.addEventListener(
      "playing",
      () => {
        player.started = true;
        this.redraw();
      },
      { signal: events.signal },
    );
    video.addEventListener(
      "pause",
      () => {
        if (player.started && player.want && !video.ended) feedback("paused");
      },
      { signal: events.signal },
    );
    video.addEventListener("ended", () => feedback("ended"), {
      signal: events.signal,
    });
    video.addEventListener(
      "error",
      () =>
        this.fail(
          media.object,
          player,
          "error",
          `Media decoding failed (${video.error?.code ?? 0})`,
        ),
      { signal: events.signal },
    );
    const checkSize = () => {
      if (!this.alive(media.object, player)) return;
      const pixels = video.videoWidth * video.videoHeight;
      if (
        video.videoWidth > 0 !== (media.kind === "video") ||
        video.videoWidth > 4096 ||
        video.videoHeight > 4096 ||
        pixels -
          player.pixels +
          Array.from(this.players.values()).reduce(
            (sum, item) => sum + item.pixels,
            0,
          ) >
          16777216
      )
        this.fail(
          media.object,
          player,
          "error",
          "Decoded media kind or cumulative frame budget is unsupported",
        );
      else player.pixels = pixels;
    };
    for (const event of ["loadedmetadata", "resize"])
      video.addEventListener(event, checkSize, { signal: events.signal });
    video.addEventListener(
      "loadeddata",
      () => {
        clearTimeout(player.timer);
        player.timer = 0;
        const current = this.state?.media.find(
          (item) => item.object === media.object,
        );
        if (current && this.alive(media.object, player)) {
          this.apply(current, player);
          this.redraw();
        }
      },
      { signal: events.signal },
    );
    await this.client
      .execute({ operation: "mediaBytesPptx", key: media.key })
      .then((bytes) => {
        if (!this.alive(media.object, player)) return;
        if (
          this.players.size > 16 ||
          bytes.length +
            Array.from(this.players.values()).reduce(
              (sum, item) => sum + item.bytes,
              0,
            ) >
            67108864
        )
          throw new Error("Slideshow decoded media input exceeds budget");
        if (!video.canPlayType(media.contentType))
          throw new Error(`This browser cannot decode ${media.contentType}`);
        player.bytes = bytes.length;
        player.url = URL.createObjectURL(
          new Blob([new Uint8Array(bytes).buffer], { type: media.contentType }),
        );
        video.src = player.url;
        video.load();
      })
      .catch((error) => this.fail(media.object, player, "error", error));
  }
  private apply(media: PptxShowMediaState, player: Player): void {
    if (player.failed || player.closed || player.video.readyState < 2) return;
    const want =
      media.state === "playing" && !this.state?.paused && media.visible;
    if (want === player.want) return;
    player.want = want;
    if (!want) {
      player.video.pause();
      return;
    }
    void player.video.play().catch((error) => {
      if (!player.want || !this.alive(media.object, player)) return;
      this.fail(
        media.object,
        player,
        error instanceof DOMException && error.name === "NotAllowedError"
          ? "blocked"
          : "error",
        error,
      );
    });
  }
  private fail(
    id: string,
    player: Player,
    action: "blocked" | "error",
    error: unknown,
  ): void {
    if (!this.alive(id, player) || player.failed) return;
    player.failed = true;
    player.want = false;
    player.video.pause();
    if (action === "error") this.unload(player);
    const message =
      Array.from(
        (error instanceof Error ? error.message : String(error)).toWellFormed(),
      )
        .slice(0, 512)
        .join("") || "Media playback failed";
    void this.send({
      object: id,
      token: player.token,
      action,
      ...(action === "error" ? { message } : {}),
    }).catch((error) => this.feedbackFailure(id, player, error));
  }
  private feedbackFailure(id: string, player: Player, error: unknown): void {
    const current = this.state?.media.find((item) => item.object === id);
    if (
      !this.alive(id, player) ||
      current?.token !== player.token ||
      !["playing", "paused", "blocked"].includes(current.state)
    )
      return;
    player.failed = true;
    player.want = false;
    player.feedbackError =
      error instanceof Error ? error.message : String(error);
    this.unload(player);
    const row = this.rows.get(id);
    if (row) {
      row.reason.textContent = player.feedbackError;
      row.reason.setAttribute("role", "alert");
    }
  }
  sources(
    drawing: PptxShowLayout,
  ): ReadonlyMap<DrawCommand, CanvasImageSource> {
    const result = new Map<DrawCommand, CanvasImageSource>();
    for (const binding of drawing.media) {
      const player = this.players.get(binding.object);
      if (
        !player ||
        player.closed ||
        player.video.readyState < 2 ||
        !player.video.videoWidth
      )
        continue;
      for (const path of binding.paths)
        result.set(mediaImageCommand(drawing, path), player.video);
    }
    return result;
  }
  private unload(player: Player): void {
    clearTimeout(player.timer);
    player.timer = 0;
    player.events.abort();
    player.video.pause();
    player.video.removeAttribute("src");
    player.video.load();
    if (player.url) URL.revokeObjectURL(player.url);
    player.url = "";
    player.bytes = player.pixels = 0;
  }
  private drop(id: string, player: Player): void {
    player.closed = true;
    this.unload(player);
    this.players.delete(id);
  }
  dispose(): void {
    if (this.closed) return;
    this.closed = true;
    for (const [id, player] of this.players) this.drop(id, player);
    this.rows.clear();
    this.panel.remove();
    this.state = undefined;
  }
}
