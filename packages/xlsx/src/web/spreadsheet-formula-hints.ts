import { xlsxFormulaSourceUnits } from "@open-document/wasm/engine-source";
import type { CommandQueue } from "@open-document/web-core/command-queue";
import type {
  XlsxFormulaAssistance,
  XlsxFormulaDraft,
} from "../core/xlsx-formula.js";
import type { XlsxViewport } from "../core/xlsx-grid.js";
import type { XlsxClient } from "./xlsx.js";

interface FormulaHintTarget {
  client: XlsxClient;
  layout: XlsxViewport | undefined;
  scale: number;
}

const colors = [
  "#2563eb",
  "#b45309",
  "#7e22ce",
  "#087e67",
  "#be185d",
  "#475569",
];

export class SpreadsheetFormulaHints {
  private readonly panel = document.createElement("div");
  private readonly list = document.createElement("div");
  private readonly signature = document.createElement("div");
  private readonly references = document.createElement("div");
  private readonly outlines = document.createElement("div");
  private result: XlsxFormulaAssistance | undefined;
  private request: XlsxFormulaDraft | undefined;
  private rendered: XlsxFormulaAssistance | undefined;
  private active = 0;
  private frame = 0;
  private pending = false;
  private dismissed = "";
  private composing = false;
  private draft = false;
  private onBar = false;

  constructor(
    private readonly input: HTMLTextAreaElement,
    private readonly bar: HTMLElement,
    private readonly holder: HTMLElement,
    private readonly current: () => FormulaHintTarget,
    private readonly signal: AbortSignal,
    private readonly queue: CommandQueue,
  ) {
    this.panel.className = "od-xlsx-formula-hints";
    this.outlines.className = "od-xlsx-reference-outlines";
    this.outlines.setAttribute("aria-hidden", "true");
    this.list.id = `od-formula-functions-${crypto.randomUUID()}`;
    this.list.setAttribute("role", "listbox");
    this.signature.setAttribute("role", "status");
    this.references.className = "od-xlsx-reference-labels";
    this.panel.append(this.list, this.signature, this.references);
    this.panel.hidden = true;
    holder.append(this.outlines, this.panel);
    const options = { signal };
    for (const type of [
      "input",
      "select",
      "selectionchange",
      "keyup",
      "focus",
      "blur",
    ]) {
      input.addEventListener(type, () => this.refresh(), options);
    }
    input.addEventListener(
      "compositionstart",
      () => {
        this.composing = true;
        this.refresh();
      },
      options,
    );
    input.addEventListener(
      "compositionend",
      () => {
        this.composing = false;
        this.refresh();
      },
      options,
    );
    input.addEventListener("keydown", (event) => this.key(event), options);
    this.list.addEventListener(
      "mousedown",
      (event) => event.preventDefault(),
      options,
    );
    this.list.addEventListener(
      "click",
      (event) => {
        if (!(event.target instanceof Element)) return;
        const option = event.target.closest<HTMLElement>(
          "[data-formula-option]",
        );
        if (option) this.accept(Number(option.dataset.formulaOption));
      },
      options,
    );
    const attributes = new MutationObserver(() => this.refresh());
    attributes.observe(input, {
      attributes: true,
      attributeFilter: ["readonly"],
    });
    signal.addEventListener(
      "abort",
      () => {
        attributes.disconnect();
        cancelAnimationFrame(this.frame);
        this.panel.remove();
        this.outlines.remove();
        this.input.removeAttribute("aria-activedescendant");
        this.input.removeAttribute("aria-controls");
        this.input.removeAttribute("aria-autocomplete");
      },
      { once: true },
    );
  }

  update(draft: boolean, onBar: boolean): void {
    this.draft = draft;
    if (!draft) this.dismissed = "";
    if (this.onBar !== onBar) {
      this.onBar = onBar;
      (onBar ? this.bar : this.holder).append(this.panel);
    }
    const { layout, scale } = this.current();
    const region = layout?.regions[0];
    const top = this.input.offsetTop + this.input.offsetHeight;
    const above =
      !onBar && top > 190 && region && region.height * scale - top < 190;
    this.panel.style.left = onBar
      ? "0"
      : `${Math.min(this.input.offsetLeft, Math.max(0, (region?.width ?? 0) * scale - 240))}px`;
    this.panel.style.top = onBar
      ? "100%"
      : `${above ? this.input.offsetTop : top}px`;
    this.panel.style.transform = above ? "translateY(-100%)" : "";
    this.refresh();
  }

  private refresh(): void {
    const { layout } = this.current();
    const source = this.input.value;
    const caret = this.input.selectionStart;
    if (
      !layout ||
      !this.draft ||
      this.composing ||
      this.input.readOnly ||
      !this.input.matches(":focus") ||
      !source.startsWith("=") ||
      source.length > xlsxFormulaSourceUnits + 1
    ) {
      this.request = undefined;
      this.result = undefined;
      this.render();
      return;
    }
    if (
      this.request?.layoutId === layout.id &&
      this.request.source === source &&
      this.request.caret === caret
    ) {
      const showList = !!this.completion();
      if (this.list.hidden !== !showList) this.render();
      return;
    }
    this.request = {
      revision: layout.revision,
      sheet: layout.sheet,
      source,
      caret,
      layoutId: layout.id,
    };
    this.result = undefined;
    this.active = 0;
    if (this.dismissed !== this.keyFor(this.request)) this.dismissed = "";
    this.render();
    this.schedule();
  }

  private schedule(): void {
    if (!this.request || this.signal.aborted || this.frame || this.pending)
      return;
    this.frame = requestAnimationFrame(() => {
      this.frame = 0;
      const request = this.request;
      if (!request) return;
      this.pending = true;
      void this.queue
        .enqueue(
          async () => {
            if (this.request !== request || this.signal.aborted)
              return undefined;
            const { client, layout } = this.current();
            if (layout?.id !== request.layoutId) return undefined;
            return client.execute({
              operation: "formulaAssistXlsx",
              ...request,
            });
          },
          () => {},
          () => {},
        )
        .then(
          (result) => {
            if (this.request !== request || this.signal.aborted) return;
            this.result = result;
            this.render();
          },
          () => {},
        )
        .finally(() => {
          this.pending = false;
          if (this.request !== request) this.schedule();
        });
    });
  }

  private keyFor(request: XlsxFormulaDraft): string {
    return `${request.caret}:${request.source}`;
  }

  private completion() {
    return this.request &&
      this.dismissed !== this.keyFor(this.request) &&
      this.input.selectionStart === this.input.selectionEnd
      ? this.result?.completion
      : undefined;
  }

  private key(event: KeyboardEvent): void {
    if (
      event.defaultPrevented ||
      event.isComposing ||
      this.composing ||
      event.altKey ||
      event.ctrlKey ||
      event.metaKey ||
      event.shiftKey
    )
      return;
    const completion = this.completion();
    if (!completion) return;
    const length = completion.functions.length;
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      this.active =
        (this.active + (event.key === "ArrowDown" ? 1 : length - 1)) % length;
      this.markActive();
    } else if (event.key === "Tab" || event.key === "Enter") {
      event.preventDefault();
      this.accept(this.active);
    } else if (event.key === "Escape" && this.request) {
      event.preventDefault();
      this.dismissed = this.keyFor(this.request);
      this.render();
    }
  }

  private accept(index: number): void {
    const completion = this.completion();
    const item = completion?.functions[index];
    if (
      !completion ||
      !item ||
      this.input.readOnly ||
      this.input.value !== this.request?.source
    )
      return;
    const suffix = completion.appendParen
      ? item.parameters.length
        ? "("
        : "()"
      : "";
    this.input.setSelectionRange(completion.start, completion.end);
    // Chrome applies insertText to the native undo stack.
    this.input.ownerDocument.execCommand(
      "insertText",
      false,
      item.name + suffix,
    );
  }

  private markActive(): void {
    for (const [index, option] of Array.from(this.list.children).entries()) {
      option.setAttribute("aria-selected", String(index === this.active));
    }
    const option = this.list.children[this.active];
    if (option) this.input.setAttribute("aria-activedescendant", option.id);
    else this.input.removeAttribute("aria-activedescendant");
  }

  private render(): void {
    if (this.signal.aborted) return;
    const zh = this.bar.lang === "zh-CN";
    const completion = this.completion();
    const call = this.result?.call;
    const references = this.result?.references ?? [];
    this.list.setAttribute("aria-label", zh ? "公式函数" : "Formula functions");
    this.list.hidden = !completion;
    if (completion) {
      this.input.setAttribute("aria-autocomplete", "list");
      this.input.setAttribute("aria-controls", this.list.id);
    } else {
      this.input.removeAttribute("aria-autocomplete");
      this.input.removeAttribute("aria-controls");
    }
    if (!completion) this.list.replaceChildren();
    else if (this.rendered !== this.result || !this.list.children.length) {
      this.list.replaceChildren(
        ...completion.functions.map((item, index) => {
          const row = document.createElement("div");
          row.id = `${this.list.id}-${index}`;
          row.dataset.formulaOption = String(index);
          row.setAttribute("role", "option");
          row.textContent = item.name;
          return row;
        }),
      );
    }
    this.markActive();
    if (this.rendered !== this.result) {
      this.signature.replaceChildren();
      if (call) {
        const { signature } = call;
        this.signature.append(`${signature.name}(`);
        for (const [index, parameter] of signature.parameters.entries()) {
          if (index) this.signature.append(", ");
          const label = document.createElement(
            index === Math.min(call.argument, signature.parameters.length - 1)
              ? "strong"
              : "span",
          );
          label.textContent = parameter;
          this.signature.append(label);
        }
        this.signature.append(")");
      }
      this.references.replaceChildren();
      this.outlines.replaceChildren();
      const { scale } = this.current();
      for (const [index, reference] of references.entries()) {
        const color = colors[index % colors.length]!;
        const label = document.createElement("span");
        label.style.setProperty("--od-xlsx-reference-color", color);
        label.textContent = reference.label;
        this.references.append(label);
        for (const rect of reference.rects) {
          const outline = document.createElement("span");
          Object.assign(outline.style, {
            left: `${rect.x * scale}px`,
            top: `${rect.y * scale}px`,
            width: `${rect.width * scale}px`,
            height: `${rect.height * scale}px`,
            borderColor: color,
          });
          this.outlines.append(outline);
        }
      }
      this.rendered = this.result;
    }
    this.panel.hidden = !completion && !call && references.length === 0;
  }
}
