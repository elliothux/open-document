import type { PresentationEditor } from "./presentation-editor.js";

export function presentationKey(
  event: KeyboardEvent,
  editor: PresentationEditor,
  available: boolean,
  escape: () => Promise<void>,
  tab: (backward: boolean) => Promise<void>,
): Promise<void> | undefined {
  if (event.isComposing) return;
  if (event.key === "Escape") {
    event.preventDefault();
    return escape();
  }
  if (event.defaultPrevented || !available) return;
  const state = editor.query;
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "a") {
    event.preventDefault();
    const object = state.objects.find(
      (object) => object.id === state.selection.object,
    );
    if (state.selection.mode === "object")
      return editor.selectObjects(
        state.objects
          .filter((peer) => peer.parent === (object?.parent ?? ""))
          .map((object) => object.id),
      );
    if (object) return editor.select(object.id, "text", 0, object.text.length);
    return;
  }
  if (state.selection.mode !== "object") return;
  const objects = state.objects.filter((object) =>
    state.selection.objects.includes(object.id),
  );
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "z") {
    event.preventDefault();
    return event.shiftKey ? editor.redo() : editor.undo();
  }
  if (
    (event.ctrlKey || event.metaKey) &&
    !event.altKey &&
    event.key.toLowerCase() === "d"
  ) {
    event.preventDefault();
    if (
      objects.some(
        (object) =>
          object.duplicateReason || object.parent !== objects[0]?.parent,
      )
    )
      return;
    return editor.editObjects({ action: "duplicate", dx: 18, dy: 18 });
  }
  if (event.key === "Tab") {
    event.preventDefault();
    return tab(event.shiftKey);
  }
  if (event.key === "Enter") {
    event.preventDefault();
    if (
      !state.objects.find((object) => object.id === state.selection.object)
        ?.textReadOnlyReason
    )
      return editor.select(state.selection.object, "text");
  } else if (
    ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key)
  ) {
    event.preventDefault();
    if (
      objects.some(
        (object) =>
          object.transformReason || object.parent !== objects[0]?.parent,
      )
    )
      return;
    const step = event.shiftKey ? 10 : 1;
    return editor.transform(
      event.key === "ArrowLeft" ? -step : event.key === "ArrowRight" ? step : 0,
      event.key === "ArrowUp" ? -step : event.key === "ArrowDown" ? step : 0,
    );
  } else if (event.key === "Delete" || event.key === "Backspace") {
    event.preventDefault();
    if (
      objects.some(
        (object) => object.deleteReason || object.parent !== objects[0]?.parent,
      )
    )
      return;
    return editor.editObjects({ action: "delete" });
  }
}
