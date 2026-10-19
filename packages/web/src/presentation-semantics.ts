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
  const table = state.table;
  if (
    table &&
    (table.firstRow !== table.lastRow || table.firstColumn !== table.lastColumn)
  )
    input.setAttribute(
      "aria-description",
      `Selected cells: row ${table.firstRow + 1} column ${table.firstColumn + 1} to row ${table.lastRow + 1} column ${table.lastColumn + 1}.`,
    );
  else input.removeAttribute("aria-description");
  const focused = focusedElement(list);
  const active =
    focused instanceof HTMLElement ? focused.dataset.object : undefined;
  const byId = new Map(state.objects.map((object) => [object.id, object]));
  const expanded = new Set<string>();
  for (const id of state.selection.objects) {
    let object = byId.get(id);
    while (object) {
      expanded.add(object.id);
      object = byId.get(object.parent);
    }
  }
  const items = (parent: string): HTMLLIElement[] =>
    state.objects
      .filter((object) => object.parent === parent)
      .map((object) => {
        const item = document.createElement("li"),
          button = document.createElement("button");
        button.type = "button";
        button.dataset.object = object.id;
        const textMember = !!object.parent && !object.textReadOnlyReason;
        const objectMode =
          state.selection.mode === "object" &&
          byId.get(state.selection.object)?.parent === object.parent;
        const reason = textMember
          ? object.textReadOnlyReason
          : object.readOnlyReason || object.textReadOnlyReason;
        button.textContent = `${object.name || object.kind}: ${object.text || object.kind}${reason ? ` (${reason})` : ""}`;
        button.setAttribute(
          "aria-pressed",
          String(state.selection.objects.includes(object.id)),
        );
        button.addEventListener(
          "click",
          (event) =>
            select(
              object.id,
              textMember && !objectMode ? "text" : undefined,
              (!textMember || objectMode) && event.shiftKey,
            ),
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
        if (object.kind === "group") {
          button.setAttribute("aria-expanded", String(expanded.has(object.id)));
          if (expanded.has(object.id)) {
            const members = document.createElement("ol");
            members.setAttribute("aria-label", object.name || "Group");
            members.append(...items(object.id));
            item.append(members);
          }
        }
        return item;
      });
  list.replaceChildren(...items(""));
  if (active)
    for (const button of list.querySelectorAll("button"))
      if (button.dataset.object === active)
        button.focus({ preventScroll: true });
}
