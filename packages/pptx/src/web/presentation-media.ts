/** Decode explicit local bytes. No source URL from a document enters this path. */
async function decodeMedia<T>(
  bytes: Uint8Array,
  contentType: string,
  signal: AbortSignal | undefined,
  use: (video: HTMLVideoElement) => T | Promise<T>,
): Promise<T> {
  signal?.throwIfAborted();
  if (!bytes.length || bytes.length > 16777216)
    throw new Error("Media input must contain 1 to 16777216 bytes");
  const video = document.createElement("video");
  if (!video.canPlayType(contentType))
    throw new Error(`This browser cannot decode ${contentType}`);
  const url = URL.createObjectURL(
    new Blob([new Uint8Array(bytes).buffer], { type: contentType }),
  );
  video.preload = "auto";
  video.muted = true;
  video.playsInline = true;
  try {
    await new Promise<void>((resolve, reject) => {
      const done = (error?: Error) => {
        clearTimeout(timer);
        video.removeEventListener("loadeddata", ready);
        video.removeEventListener("error", failed);
        signal?.removeEventListener("abort", aborted);
        if (error) reject(error);
        else resolve();
      };
      const ready = () => done();
      const failed = () =>
        done(new Error(`Media decoding failed (${video.error?.code ?? 0})`));
      const aborted = () => done(new Error("Media decoding cancelled"));
      const timer = setTimeout(
        () => done(new Error("Media decoding timed out")),
        10000,
      );
      video.addEventListener("loadeddata", ready, { once: true });
      video.addEventListener("error", failed, { once: true });
      signal?.addEventListener("abort", aborted, { once: true });
      video.src = url;
      video.load();
    });
    signal?.throwIfAborted();
    if (
      video.videoWidth > 4096 ||
      video.videoHeight > 4096 ||
      video.videoWidth * video.videoHeight > 16777216
    )
      throw new Error("Decoded media frame exceeds budget");
    return await use(video);
  } finally {
    video.pause();
    video.removeAttribute("src");
    video.load();
    URL.revokeObjectURL(url);
  }
}

export function verifyPresentationMedia(
  bytes: Uint8Array,
  kind: "audio" | "video",
  contentType: string,
  signal?: AbortSignal,
): Promise<void> {
  return decodeMedia(bytes, contentType, signal, (video) => {
    if (video.videoWidth > 0 !== (kind === "video"))
      throw new Error("Decoded media kind differs from the declared kind");
  });
}

/** Generate the static poster from the first decoded frame, or an audio play symbol. */
export async function preparePresentationMedia(
  bytes: Uint8Array,
  signal?: AbortSignal,
): Promise<{
  kind: "audio" | "video";
  contentType: string;
  poster: Uint8Array;
}> {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const type =
    bytes.length >= 16 && view.getUint32(4) === 0x66747970
      ? "video/mp4"
      : bytes.length >= 8 && view.getUint32(0) === 0x1a45dfa3
        ? "video/webm"
        : bytes.length >= 44 &&
            view.getUint32(0) === 0x52494646 &&
            view.getUint32(8) === 0x57415645
          ? "audio/wav"
          : bytes.length >= 4 &&
              (view.getUint32(0) >>> 8 === 0x494433 ||
                (view.getUint16(0) & 0xffe0) === 0xffe0)
            ? "audio/mpeg"
            : "";
  if (!type) throw new Error("Unsupported media container");
  return decodeMedia(bytes, type, signal, async (video) => {
    const kind = video.videoWidth ? "video" : "audio";
    const contentType =
      kind === "audio" ? type.replace("video/", "audio/") : type;
    const canvas = document.createElement("canvas");
    try {
      const scale = Math.min(
        1,
        1920 / (video.videoWidth || 240),
        1080 / (video.videoHeight || 96),
      );
      canvas.width = Math.max(1, Math.round((video.videoWidth || 240) * scale));
      canvas.height = Math.max(
        1,
        Math.round((video.videoHeight || 96) * scale),
      );
      const context = canvas.getContext("2d");
      if (!context) throw new Error("Canvas is unavailable");
      if (kind === "video")
        context.drawImage(video, 0, 0, canvas.width, canvas.height);
      else {
        context.fillStyle = "#334155";
        context.fillRect(0, 0, canvas.width, canvas.height);
        context.fillStyle = "#ffffff";
        context.beginPath();
        context.moveTo(106, 24);
        context.lineTo(142, 48);
        context.lineTo(106, 72);
        context.fill();
      }
      const blob = await new Promise<Blob>((resolve, reject) =>
        canvas.toBlob(
          (value) =>
            value
              ? resolve(value)
              : reject(new Error("Media poster encoding failed")),
          "image/png",
        ),
      );
      if (blob.size > 4194304)
        throw new Error("Media poster exceeds byte budget");
      signal?.throwIfAborted();
      return {
        kind,
        contentType,
        poster: new Uint8Array(await blob.arrayBuffer()),
      };
    } finally {
      canvas.width = canvas.height = 0;
    }
  });
}
