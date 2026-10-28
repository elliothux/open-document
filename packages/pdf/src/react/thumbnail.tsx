import { useLayoutEffect, useRef, useState } from "react";
import type { PdfEditor } from "../web/index.js";

/** At most five neighboring thumbnails are mounted by the page list. */
export function Thumbnail({
  editor,
  page,
  revision,
}: {
  editor: PdfEditor;
  page: string;
  revision: number;
}) {
  const host = useRef<HTMLSpanElement>(null);
  const [url, setUrl] = useState("");
  useLayoutEffect(() => {
    setUrl("");
    let active = true;
    let objectUrl = "";
    const observer = new IntersectionObserver((entries) => {
      if (!entries.some((entry) => entry.isIntersecting)) return;
      observer.disconnect();
      void editor
        .thumbnail(page)
        .then((blob) => {
          if (!active) return;
          objectUrl = URL.createObjectURL(blob);
          setUrl(objectUrl);
        })
        .catch(() => {
          if (active) setUrl("");
        });
    });
    if (host.current) observer.observe(host.current);
    return () => {
      active = false;
      observer.disconnect();
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [editor, page, revision]);
  return (
    <span ref={host} style={{ display: "block", minHeight: "24px" }}>
      {url && (
        <img src={url} alt="" style={{ width: "96px", height: "auto" }} />
      )}
    </span>
  );
}
