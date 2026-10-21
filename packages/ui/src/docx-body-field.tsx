import { useState } from "react";
import type {
  DocumentEditor,
  DocumentBodyPageField,
} from "@open-document/web/editor";
import { listFormats, type DocxPageField } from "@open-document/web/foundation";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";

export function DocxBodyField({
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
  const [source, setSource] = useState<DocumentBodyPageField>();
  const [draft, setDraft] = useState<DocxPageField>();
  const snapshot = editor.getSnapshot();
  const stale =
    source?.documentId !== snapshot.documentId ||
    source.revision !== snapshot.revision ||
    JSON.stringify(source.selection) !==
      JSON.stringify(snapshot.data.selection);
  const load = async () => {
    const value = await editor.bodyPageField();
    setSource(value);
    setDraft(value.field ?? undefined);
  };
  return (
    <section aria-label={t.bodyPageField}>
      <h4>{t.bodyPageField}</h4>
      <button
        type="button"
        disabled={disabled || !snapshot.data.selection}
        onClick={() => controller.run(load)}
      >
        {t.loadBodyPageField}
      </button>
      {source?.reason && <p>{source.reason}</p>}
      {draft && source && (
        <form
          onSubmit={(event) => {
            event.preventDefault();
            controller.run(async () => {
              await editor.editBodyPageField(source, draft);
              await load();
            });
          }}
        >
          <fieldset disabled={disabled || stale || !!source.reason}>
            <label>
              {t.runningField}
              <select
                value={draft.field}
                onChange={(event) =>
                  setDraft({
                    ...draft,
                    field:
                      event.currentTarget.value === "PAGE"
                        ? "PAGE"
                        : "NUMPAGES",
                  })
                }
              >
                <option value="PAGE">{t.currentPageField}</option>
                <option value="NUMPAGES">{t.totalPagesField}</option>
              </select>
            </label>
            <label>
              {t.fieldNumberFormat}
              <select
                value={draft.format ?? ""}
                onChange={(event) => {
                  const format = event.currentTarget.value;
                  setDraft(
                    format
                      ? {
                          field: draft.field,
                          format: format as NonNullable<
                            DocxPageField["format"]
                          >,
                        }
                      : { field: draft.field },
                  );
                }}
              >
                <option value="">{t.inheritedPageNumberFormat}</option>
                {listFormats
                  .filter(
                    (format) => format !== "bullet" && format !== "decimalZero",
                  )
                  .map((format) => (
                    <option key={format} value={format}>
                      {t[`listFormat_${format}`]}
                    </option>
                  ))}
              </select>
            </label>
            <button type="submit">{t.applyBodyPageField}</button>
          </fieldset>
        </form>
      )}
    </section>
  );
}
