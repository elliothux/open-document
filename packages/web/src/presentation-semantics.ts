import type { PptxQuery } from "@open-document/wasm/pptx";

export function updatePresentationObjects(
  list: HTMLOListElement,
  state: PptxQuery,
  signal: AbortSignal,
  select: (object: string, mode?: "text") => void,
): void {
  const active =
    document.activeElement instanceof HTMLElement
      ? document.activeElement.dataset.object
      : undefined;
  list.replaceChildren(
    ...state.objects.map((object) => {
      const item = document.createElement("li"),
        button = document.createElement("button");
      button.type = "button";
      button.dataset.object = object.id;
      button.textContent = `${object.name || object.kind}: ${object.text || object.kind}${object.readOnlyReason || object.textReadOnlyReason ? ` (${object.readOnlyReason || object.textReadOnlyReason})` : ""}`;
      button.setAttribute(
        "aria-pressed",
        String(object.id === state.selection.object),
      );
      button.addEventListener("click", () => select(object.id), {
        signal: signal,
      });
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
