import { useState } from "react";
import type { DocumentEditor } from "../web/editor.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { Group } from "@open-document/ui/controls";
import { messages } from "@open-document/ui/messages";

const symbols = Array.from(
  "—…·§¶†©®™°±×÷≤≥≠≈∞√µ€£¥¢←→↑↓⇐⇒★☆✓✗●○■□◆◇①②③④⑤⑥⑦⑧⑨⑩",
);

export function DocxSymbols({
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
  const t = messages(state.locale);
  const [symbol, setSymbol] = useState(symbols[0]!);
  return (
    <Group label={t.symbols}>
      <label>
        {t.symbol}
        <select
          value={symbol}
          disabled={disabled}
          onChange={(event) => setSymbol(event.currentTarget.value)}
        >
          {symbols.map((value) => (
            <option key={value} value={value}>
              {value}
            </option>
          ))}
        </select>
      </label>
      <button
        type="button"
        disabled={disabled}
        onClick={() =>
          controller.run(async () => {
            await editor.paste(symbol);
            editor.focus();
          })
        }
      >
        {t.insertSymbol}
      </button>
    </Group>
  );
}
