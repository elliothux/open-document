import type {
  PptxHit,
  PptxQuery,
  PptxSelection,
} from "@open-document/wasm/pptx";

export function objectSelection(
  state: PptxQuery,
  object: string,
  extend: boolean,
): PptxSelection {
  const objects = extend
    ? state.selection.objects.includes(object)
      ? state.selection.objects.filter((id) => id !== object)
      : [...state.selection.objects, ...(object ? [object] : [])]
    : object
      ? [object]
      : [];
  return {
    slide: state.slide,
    object: objects.includes(object) ? object : (objects.at(-1) ?? ""),
    objects,
    mode: "object",
    anchor: 0,
    focus: 0,
  };
}

export function pointerSelection(
  state: PptxQuery,
  hit: PptxHit,
  handle: number,
  text: boolean,
  extend: boolean,
): PptxSelection {
  if (handle) return state.selection;
  const mode =
    hit.object &&
    !hit.textReadOnlyReason &&
    (text ||
      (state.selection.mode === "text" &&
        hit.object === state.selection.object))
      ? "text"
      : "object";
  if (mode === "text")
    return {
      ...objectSelection(state, hit.object, false),
      mode,
      anchor: extend ? state.selection.anchor : hit.offset,
      focus: hit.offset,
    };
  if (
    !extend &&
    state.selection.mode === "object" &&
    state.selection.objects.includes(hit.object)
  )
    return { ...state.selection, object: hit.object };
  return objectSelection(state, hit.object, extend);
}
