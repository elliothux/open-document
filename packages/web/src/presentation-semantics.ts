import type { PptxQuery } from "@open-document/wasm/pptx";
import { focusedElement } from "./editor-state.js";

export function updatePresentationObjects(
  list: HTMLOListElement,
  input: HTMLTextAreaElement,
  state: PptxQuery,
  signal: AbortSignal,
  select: (object: string, mode?: "text", extend?: boolean) => void,
): void {
  input.setAttribute(
    "aria-label",
    `${state.selection.mode === "text" ? "Text" : "Object"} input: ${state.objects.find((object) => object.id === state.selection.object)?.name || "slide"}`,
  );
  const focused = focusedElement(list);
  const active =
    focused instanceof HTMLElement ? focused.dataset.object : undefined;
  list.replaceChildren(
    ...state.objects
      .filter((object) => !object.parent)
      .map((object) => {
        const item = document.createElement("li"),
          button = document.createElement("button");
        button.type = "button";
        button.dataset.object = object.id;
        button.textContent = `${object.name || object.kind}: ${object.text || object.kind}${object.readOnlyReason || object.textReadOnlyReason ? ` (${object.readOnlyReason || object.textReadOnlyReason})` : ""}`;
        button.setAttribute(
          "aria-pressed",
          String(state.selection.objects.includes(object.id)),
        );
        button.addEventListener(
          "click",
          (event) => select(object.id, undefined, event.shiftKey),
          {
            signal: signal,
          },
        );
        button.addEventListener(
          "keydown",
          (event) => {
            if (event.key === "Enter" && !object.textReadOnlyReason) {
              event.preventDefault();
              select(object.id, "text");
            }
          },
          { signal: signal },
        );
        item.append(button);
        return item;
      }),
  );
  if (active)
    for (const button of list.querySelectorAll("button"))
      if (button.dataset.object === active)
        button.focus({ preventScroll: true });
}
