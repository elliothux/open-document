import type { DocumentEditor } from "../web/editor.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { EditorSymbolPicker } from "@open-document/ui";
import { messages } from "@open-document/ui/messages";
const symbols = Array.from(
  "—…·§¶†©®™°±×÷≤≥≠≈∞√µ€£¥¢←→↑↓⇐⇒★☆✓✗●○■□◆◇①②③④⑤⑥⑦⑧⑨⑩",
);

export function DocxSymbols({
  controller,
  state,
  editor,
  disabled,
  portal,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: DocumentEditor;
  disabled: boolean;
  portal: HTMLElement;
}) {
  const t = messages(state.locale);
  return (
    <EditorSymbolPicker
      label={t.insertSymbol}
      title={t.symbols}
      gridLabel={t.symbol}
      symbols={symbols}
      disabled={disabled}
      portal={portal}
      insert={(symbol) =>
        controller.run(async () => {
          await editor.paste(symbol);
          editor.focus();
        })
      }
    />
  );
}
