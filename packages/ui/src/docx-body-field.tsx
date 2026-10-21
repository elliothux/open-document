import { useState } from "react";
import type {
  DocumentEditor,
  DocumentBodyPageField,
} from "@open-document/web/editor";
import { listFormats, type DocxBodyField } from "@open-document/web/foundation";
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
  const [draft, setDraft] = useState<DocxBodyField>();
  const [bookmark, setBookmark] = useState("");
  const [hyperlink, setHyperlink] = useState(false);
  const [relative, setRelative] = useState(false);
  const reference =
    source?.field?.field === "PAGEREF" ? source.field : undefined;
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
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.insertBodyPageField({
              field: "PAGEREF",
              bookmark,
              ...(hyperlink ? { hyperlink: true } : {}),
              ...(relative ? { relative: true } : {}),
            }),
          );
        }}
      >
        <fieldset disabled={disabled || !snapshot.data.selection}>
          <label>
            {t.pageReferenceTarget}
            <input
              aria-label={t.pageReferenceTarget}
              required
              pattern="[A-Za-z_][A-Za-z0-9_]{0,39}"
              maxLength={40}
              value={bookmark}
              onChange={(event) => setBookmark(event.currentTarget.value)}
            />
          </label>
          <label>
            <input
              type="checkbox"
              checked={hyperlink}
              onChange={(event) => setHyperlink(event.currentTarget.checked)}
            />
            {t.pageReferenceLink}
          </label>
          <label>
            <input
              type="checkbox"
              checked={relative}
              onChange={(event) => setRelative(event.currentTarget.checked)}
            />
            {t.pageReferenceRelative}
          </label>
          <button type="submit" disabled={!bookmark}>
            {t.insertPageReference}
          </button>
        </fieldset>
      </form>
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
                  setDraft(
                    event.currentTarget.value === "PAGEREF"
                      ? {
                          field: "PAGEREF",
                          bookmark,
                          ...(draft.format ? { format: draft.format } : {}),
                        }
                      : {
                          field:
                            event.currentTarget.value === "PAGE"
                              ? "PAGE"
                              : "NUMPAGES",
                          ...(draft.format ? { format: draft.format } : {}),
                        },
                  )
                }
              >
                <option value="PAGE">{t.currentPageField}</option>
                <option value="NUMPAGES">{t.totalPagesField}</option>
                <option value="PAGEREF">{t.pageReference}</option>
              </select>
            </label>
            {draft.field === "PAGEREF" && (
              <>
                <label>
                  {t.pageReferenceTarget}
                  <input
                    aria-label={t.selectedPageReferenceTarget}
                    required
                    pattern="[A-Za-z_][A-Za-z0-9_]{0,39}"
                    maxLength={40}
                    value={draft.bookmark}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        bookmark: event.currentTarget.value,
                      })
                    }
                  />
                </label>
                <label>
                  <input
                    type="checkbox"
                    checked={draft.hyperlink ?? false}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        hyperlink: event.currentTarget.checked,
                      })
                    }
                  />
                  {t.selectedPageReferenceLink}
                </label>
                <label>
                  <input
                    type="checkbox"
                    checked={draft.relative ?? false}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        relative: event.currentTarget.checked,
                      })
                    }
                  />
                  {t.selectedPageReferenceRelative}
                </label>
              </>
            )}
            <label>
              {t.fieldNumberFormat}
              <select
                value={draft.format ?? ""}
                onChange={(event) => {
                  const format = event.currentTarget.value;
                  const { format: _previous, ...field } = draft;
                  setDraft(
                    format
                      ? {
                          ...field,
                          format: format as NonNullable<
                            DocxBodyField["format"]
                          >,
                        }
                      : field,
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
            {reference?.hyperlink && (
              <button
                type="button"
                disabled={
                  JSON.stringify(draft) !== JSON.stringify(source.field)
                }
                onClick={() =>
                  controller.run(() =>
                    editor.editBookmark({
                      action: "goTo",
                      name: reference.bookmark,
                    }),
                  )
                }
              >
                {t.followPageReference}
              </button>
            )}
          </fieldset>
        </form>
      )}
    </section>
  );
}
