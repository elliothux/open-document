import { useEffect, useRef, useState } from "react";
import type { DocumentEditor, DocumentRuler } from "@open-document/web/editor";
import type {
  DocxRulerEdit,
  DocxRulerTabAlign,
} from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";

const en = {
  ruler: "Document ruler (pt)",
  first: "First line indent",
  hanging: "Hanging indent",
  left: "Start indent",
  right: "End indent",
  marginLeft: "Left margin",
  marginRight: "Right margin",
  tab: "Tab stop",
  type: "New tab alignment",
  select: "Select document text to use the ruler",
  tabs: {
    left: "Left",
    right: "Right",
    center: "Center",
    decimal: "Decimal",
    bar: "Bar",
  },
};
const zh: typeof en = {
  ruler: "文档标尺（磅）",
  first: "首行缩进",
  hanging: "悬挂缩进",
  left: "起始缩进",
  right: "末尾缩进",
  marginLeft: "左边距",
  marginRight: "右边距",
  tab: "制表位",
  type: "新增制表位对齐",
  select: "选择文档文字以使用标尺",
  tabs: {
    left: "左对齐",
    right: "右对齐",
    center: "居中",
    decimal: "小数点",
    bar: "竖线",
  },
};
const aligns: DocxRulerTabAlign[] = [
  "left",
  "center",
  "right",
  "decimal",
  "bar",
];
type Marker = DocumentRuler["markers"][number];
interface Drag {
  source: DocumentRuler;
  marker: Marker;
  pointer: number;
  startX: number;
  position: number;
  remove: boolean;
}

/** Only pointer coordinates and a temporary guide live here; the core owns ruler edits. */
export function DocxRuler({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
}) {
  const snapshot = editor.getSnapshot();
  const selection = JSON.stringify(snapshot.data.selection);
  const [source, setSource] = useState<DocumentRuler>();
  const [drag, setDrag] = useState<Drag>();
  const [align, setAlign] = useState<DocxRulerTabAlign>("left");
  const [frame, setFrame] = useState({ left: 0, scale: 96 / 72 });
  const root = useRef<HTMLDivElement>(null);
  const track = useRef<HTMLDivElement>(null);
  const pendingFocus = useRef<
    { kind: Marker["kind"]; position: number } | undefined
  >(undefined);
  const t = state.locale === "zh-CN" ? zh : en;
  useEffect(() => {
    let current = true;
    setDrag(undefined);
    if (
      !snapshot.data.selection ||
      snapshot.composition ||
      snapshot.stopped ||
      snapshot.closed
    ) {
      setSource(undefined);
      return;
    }
    controller.run(async () => {
      const next = await editor.ruler();
      if (current) setSource(next);
    });
    return () => {
      current = false;
    };
  }, [
    controller,
    editor,
    snapshot.revision,
    selection,
    snapshot.composition,
    snapshot.stopped,
    snapshot.closed,
  ]);
  useEffect(() => {
    const element = root.current;
    const canvas = controller.surfaces.querySelector("canvas");
    if (!element || !canvas || !source) return;
    const update = () => {
      const rect = canvas.getBoundingClientRect();
      setFrame({
        left: rect.left - element.getBoundingClientRect().left,
        scale: rect.width / source.width,
      });
    };
    update();
    const observer = new ResizeObserver(update);
    observer.observe(canvas);
    observer.observe(element);
    controller.surfaces.addEventListener("scroll", update, true);
    return () => {
      observer.disconnect();
      controller.surfaces.removeEventListener("scroll", update, true);
    };
  }, [controller, source, snapshot.zoom, snapshot.page]);
  useEffect(() => {
    const requested = pendingFocus.current;
    if (
      disabled ||
      !source ||
      !requested ||
      source.revision !== snapshot.revision
    )
      return;
    pendingFocus.current = undefined;
    const candidates = Array.from(
      track.current?.querySelectorAll<HTMLButtonElement>("[data-ruler-kind]") ??
        [],
    ).filter((element) => element.dataset.rulerKind === requested.kind);
    candidates.sort(
      (a, b) =>
        Math.abs(Number(a.dataset.rulerPosition) - requested.position) -
        Math.abs(Number(b.dataset.rulerPosition) - requested.position),
    );
    (candidates[0] ?? root.current?.querySelector("select"))?.focus({
      preventScroll: true,
    });
  }, [source, snapshot.revision, disabled]);
  const unavailable =
    disabled ||
    !source ||
    source.revision !== snapshot.revision ||
    source.page !== snapshot.page ||
    !!source.reason;
  const apply = (
    original: DocumentRuler,
    change: DocxRulerEdit,
    focus = false,
  ) => {
    if (focus)
      pendingFocus.current = { kind: change.kind, position: change.position };
    controller.run(async () => {
      try {
        await editor.editRuler(original, change);
      } catch (error) {
        pendingFocus.current = undefined;
        throw error;
      }
    });
  };
  const change = (
    marker: Marker,
    position: number,
    snap: boolean,
    remove = false,
  ): DocxRulerEdit =>
    marker.kind === "tab"
      ? {
          kind: "tab",
          position,
          snap,
          remove,
          index: marker.index,
          align: aligns.find((value) => value === marker.align) ?? "left",
        }
      : { kind: marker.kind, position, snap };
  return (
    <div className="od-ruler" ref={root} role="group" aria-label={t.ruler}>
      <label className="od-ruler-type">
        {t.type}
        <select
          aria-label={t.type}
          value={align}
          disabled={unavailable}
          onChange={(event) =>
            setAlign(
              aligns.find((value) => value === event.currentTarget.value) ??
                "left",
            )
          }
        >
          {aligns.map((value) => (
            <option key={value} value={value}>
              {t.tabs[value]}
            </option>
          ))}
        </select>
      </label>
      {!source && <span className="od-ruler-empty">{t.select}</span>}
      {source && (
        <div
          ref={track}
          className="od-ruler-track"
          style={{ width: source.width * frame.scale, left: frame.left }}
          title={source.reason}
          onClick={(event) => {
            if (unavailable || event.target !== event.currentTarget) return;
            apply(source, {
              kind: "tab",
              index: -1,
              position:
                (event.clientX -
                  event.currentTarget.getBoundingClientRect().left) /
                frame.scale,
              align,
              remove: false,
              snap: !event.altKey,
            });
          }}
        >
          {Array.from(
            {
              length:
                Math.floor((source.width - source.origin) / 9) -
                Math.ceil(-source.origin / 9) +
                1,
            },
            (_, index) => {
              const tick = index + Math.ceil(-source.origin / 9);
              const position = source.origin + tick * 9;
              return (
                <span
                  key={index}
                  aria-hidden="true"
                  className={
                    tick % 4 === 0 ? "od-ruler-tick major" : "od-ruler-tick"
                  }
                  style={{ left: position * frame.scale }}
                >
                  {tick % 4 === 0
                    ? String(tick * 9 * (source.rtl ? -1 : 1))
                    : ""}
                </span>
              );
            },
          )}
          {source.markers.map((marker) => {
            const position =
              drag?.marker === marker ? drag.position : marker.position;
            const label =
              marker.kind === "tab"
                ? `${t.tab} ${marker.index + 1}: ${t.tabs[aligns.find((value) => value === marker.align) ?? "left"]}`
                : t[marker.kind];
            return (
              <button
                key={`${marker.kind}:${marker.index}`}
                type="button"
                role="slider"
                aria-label={label}
                aria-valuemin={Math.min(0, marker.position)}
                aria-valuemax={Math.max(source.width, marker.position)}
                aria-valuenow={position}
                aria-valuetext={`${position.toFixed(2)} pt`}
                data-ruler-kind={marker.kind}
                data-ruler-position={marker.position}
                disabled={unavailable}
                className={`od-ruler-marker ${marker.kind}`}
                style={{
                  left: position * frame.scale,
                  opacity: drag?.marker === marker && drag.remove ? 0.35 : 1,
                }}
                onClick={(event) => event.stopPropagation()}
                onKeyDown={(event) => {
                  if (event.key === "Escape") {
                    setDrag(undefined);
                    event.preventDefault();
                    return;
                  }
                  if (
                    ![
                      "ArrowLeft",
                      "ArrowRight",
                      "Home",
                      "End",
                      "Delete",
                      "Backspace",
                    ].includes(event.key)
                  )
                    return;
                  event.preventDefault();
                  event.stopPropagation();
                  if (unavailable) return;
                  const remove =
                    event.key === "Delete" || event.key === "Backspace";
                  if (remove && marker.kind !== "tab") return;
                  const step = event.shiftKey
                    ? 36
                    : marker.kind === "tab"
                      ? 3
                      : 4.5;
                  const target =
                    event.key === "Home"
                      ? 0
                      : event.key === "End"
                        ? source.width
                        : marker.position +
                          (event.key === "ArrowLeft"
                            ? -step
                            : event.key === "ArrowRight"
                              ? step
                              : 0);
                  apply(
                    source,
                    change(
                      marker,
                      Math.min(source.width, Math.max(0, target)),
                      !event.altKey,
                      remove,
                    ),
                    true,
                  );
                }}
                onPointerDown={(event) => {
                  if (unavailable || event.button !== 0) return;
                  event.preventDefault();
                  event.stopPropagation();
                  event.currentTarget.focus();
                  event.currentTarget.setPointerCapture(event.pointerId);
                  setDrag({
                    source,
                    marker,
                    pointer: event.pointerId,
                    startX: event.clientX,
                    position: marker.position,
                    remove: false,
                  });
                }}
                onPointerMove={(event) => {
                  if (!drag || drag.pointer !== event.pointerId) return;
                  const rect = track.current!.getBoundingClientRect();
                  setDrag({
                    ...drag,
                    position: Math.min(
                      source.width,
                      Math.max(
                        0,
                        drag.marker.position +
                          (event.clientX - drag.startX) / frame.scale,
                      ),
                    ),
                    remove:
                      marker.kind === "tab" &&
                      (event.clientY < rect.top - 12 ||
                        event.clientY > rect.bottom + 12),
                  });
                }}
                onPointerUp={(event) => {
                  if (!drag || drag.pointer !== event.pointerId) return;
                  const rect = track.current!.getBoundingClientRect();
                  const target = Math.min(
                    source.width,
                    Math.max(
                      0,
                      drag.marker.position +
                        (event.clientX - drag.startX) / frame.scale,
                    ),
                  );
                  const remove =
                    marker.kind === "tab" &&
                    (event.clientY < rect.top - 12 ||
                      event.clientY > rect.bottom + 12);
                  setDrag(undefined);
                  if (Math.abs(event.clientX - drag.startX) >= 0.5 || remove)
                    apply(
                      drag.source,
                      change(marker, target, !event.altKey, remove),
                      true,
                    );
                }}
                onPointerCancel={() => setDrag(undefined)}
                onLostPointerCapture={() => setDrag(undefined)}
              >
                {marker.kind === "first"
                  ? "▼"
                  : marker.kind === "hanging"
                    ? "▲"
                    : marker.kind === "left"
                      ? "■"
                      : marker.kind === "right"
                        ? "◀"
                        : marker.kind === "tab"
                          ? marker.align === "bar"
                            ? "│"
                            : marker.align === "center"
                              ? "⊥"
                              : marker.align === "right"
                                ? "┘"
                                : marker.align === "decimal"
                                  ? "⊥·"
                                  : "└"
                          : "↔"}
              </button>
            );
          })}
          {drag && (
            <span
              aria-hidden="true"
              className="od-ruler-guide"
              style={{ left: drag.position * frame.scale }}
            />
          )}
        </div>
      )}
    </div>
  );
}
