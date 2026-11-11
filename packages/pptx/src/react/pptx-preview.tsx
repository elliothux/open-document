import { useEffect, useRef, useState } from "react";
import type { PresentationEditor } from "../web/presentation-editor.js";

export function PptxPreview({
  editor,
  slide,
  revision,
  width,
  height,
}: {
  editor: PresentationEditor;
  slide: string;
  revision: number;
  width: number;
  height: number;
}) {
  const box = useRef<HTMLSpanElement>(null);
  const [visible, setVisible] = useState(false);
  const [url, setUrl] = useState("");

  useEffect(() => {
    const target = box.current;
    if (!target) return;
    const observer = new IntersectionObserver(
      ([entry]) => setVisible(!!entry?.isIntersecting),
      { rootMargin: "96px 0px" },
    );
    observer.observe(target);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    setUrl("");
    if (!visible) return;
    const abort = new AbortController();
    let image = "";
    const frame = requestAnimationFrame(() => {
      void editor.preview({ slide, revision, signal: abort.signal }).then(
        (blob) => {
          if (abort.signal.aborted) return;
          image = URL.createObjectURL(blob);
          setUrl(image);
        },
        () => {},
      );
    });
    return () => {
      abort.abort();
      cancelAnimationFrame(frame);
      if (image) URL.revokeObjectURL(image);
    };
  }, [editor, slide, revision, visible]);

  return (
    <span
      ref={box}
      className="od-slide-preview"
      style={{ aspectRatio: width / height }}
      aria-hidden="true"
    >
      {url && <img src={url} alt="" draggable={false} />}
    </span>
  );
}
