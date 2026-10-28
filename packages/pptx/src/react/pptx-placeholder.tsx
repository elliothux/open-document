import { useState } from "react";
import { pptxPlaceholderTypes, type PptxPlaceholderType } from "../web/pptx.js";
import type { PresentationEditor } from "../web/presentation-editor.js";
import type { EditorController, UiSnapshot } from "./context.js";
import { messages } from "@open-document/ui/messages";

export function PlaceholderType({
  value,
  onChange,
  state,
}: {
  value: PptxPlaceholderType;
  onChange: (value: PptxPlaceholderType) => void;
  state: UiSnapshot;
}) {
  const t = messages(state.locale);
  return (
    <label>
      {t.pptxPlaceholderType}
      <select
        aria-label={t.pptxPlaceholderType}
        value={value}
        onChange={(event) => {
          const next = pptxPlaceholderTypes.find(
            (type) => type === event.currentTarget.value,
          );
          if (next) onChange(next);
        }}
      >
        {pptxPlaceholderTypes.map((type) => (
          <option key={type} value={type}>
            {t[`pptxPlaceholder_${type}`]}
          </option>
        ))}
      </select>
    </label>
  );
}

export function PptxPlaceholder({
  controller,
  state,
  editor,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  editor: PresentationEditor;
  disabled: boolean;
}) {
  const t = messages(state.locale),
    query = editor.query,
    selected = query.objects.find(
      (object) => object.id === query.selection.object,
    ),
    metadata = selected?.placeholder;
  const [type, setType] = useState<PptxPlaceholderType>(
      metadata?.value?.type ?? "body",
    ),
    [index, setIndex] = useState(String(metadata?.value?.index ?? 0));
  if (query.editView.kind === "slide" || !metadata) return null;
  const blocked =
    disabled ||
    !!metadata.reason ||
    query.selection.mode !== "object" ||
    query.selection.objects.length !== 1;
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() =>
          editor.editObjects({
            action: "placeholder",
            value: { type, index: Number(index) },
          }),
        );
      }}
    >
      <fieldset disabled={blocked}>
        <legend>{t.pptxPlaceholder}</legend>
        <PlaceholderType value={type} onChange={setType} state={state} />
        <label>
          {t.pptxPlaceholderIndex}
          <input
            type="number"
            min={0}
            max={4294967295}
            step={1}
            required
            value={index}
            onChange={(event) => setIndex(event.currentTarget.value)}
          />
        </label>
        <button type="submit">{t.pptxApplyPlaceholder}</button>
        <button
          type="button"
          disabled={!metadata.value}
          onClick={() =>
            controller.run(() =>
              editor.editObjects({ action: "placeholder", value: null }),
            )
          }
        >
          {t.pptxRemovePlaceholder}
        </button>
      </fieldset>
      {metadata.reason && <p>{metadata.reason}</p>}
    </form>
  );
}
