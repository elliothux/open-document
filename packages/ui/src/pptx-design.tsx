import { useState } from "react";
import type { PanelProps } from "./panels.js";
import { messages } from "./messages.js";

export function PptxDesign({ controller, state, file, disabled }: PanelProps) {
  const query = file.format === "pptx" ? file.editor.query : undefined,
    t = messages(state.locale),
    choice = query?.editView.choices.find(
      (choice) => choice.id === query.slide,
    );
  const [name, setName] = useState(choice?.name ?? "");
  if (file.format !== "pptx" || !query || !choice) return null;
  const editor = file.editor,
    operations = query.editView.operations;
  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        controller.run(() => editor.editSlides({ action: "sourceName", name }));
      }}
    >
      <fieldset disabled={disabled}>
        <legend>{t.pptxSourceManagement}</legend>
        <label>
          {t.pptxSourceName}
          <input
            type="text"
            maxLength={1024}
            value={name}
            disabled={!!operations.rename}
            onChange={(event) => setName(event.currentTarget.value)}
          />
        </label>
        <button
          type="submit"
          disabled={!!operations.rename}
          title={operations.rename}
        >
          {t.pptxRenameSource}
        </button>
        {(
          [
            ["addLayout", t.pptxAddLayout],
            ["copyLayout", t.pptxCopyLayout],
            ["deleteLayout", t.pptxDeleteLayout],
            ["addMaster", t.pptxAddMaster],
            ["copyMaster", t.pptxCopyMaster],
          ] as const
        ).map(([action, label]) => (
          <button
            key={action}
            type="button"
            disabled={!!operations[action]}
            title={operations[action]}
            onClick={() => controller.run(() => editor.editSlides({ action }))}
          >
            {label}
          </button>
        ))}
        {operations.deleteLayout && choice.kind === "layout" && (
          <p>{operations.deleteLayout}</p>
        )}
        {operations.copyLayout && choice.kind === "layout" && (
          <p>{operations.copyLayout}</p>
        )}
        {operations.copyMaster && choice.kind === "master" && (
          <p>{operations.copyMaster}</p>
        )}
        {choice.kind === "master" && (
          <>
            <button
              type="button"
              disabled={!!operations.deleteMaster}
              title={operations.deleteMaster}
              onClick={() =>
                controller.run(() =>
                  editor.editSlides({ action: "deleteMaster" }),
                )
              }
            >
              {t.pptxDeleteMaster}
            </button>
            {operations.deleteMaster && <p>{operations.deleteMaster}</p>}
          </>
        )}
      </fieldset>
    </form>
  );
}
