import { useState } from "react";
import type {
  DocumentEditor,
  DocumentBodyPageField,
} from "@open-document/web/editor";
import {
  listFormats,
  type DocxBodyField,
  type DocxPageField,
} from "@open-document/web/foundation";
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
  const [sequence, setSequence] = useState("Figure");
  const [referenceKind, setReferenceKind] = useState<"PAGEREF" | "REF">(
    "PAGEREF",
  );
  const draftFormat = draft?.field === "REF" ? undefined : draft?.format;
  const reference =
    source?.field?.field === "PAGEREF" || source?.field?.field === "REF"
      ? source.field
      : undefined;
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
            editor.insertBodyPageField({ field: "SEQ", sequence }),
          );
        }}
      >
        <fieldset disabled={disabled || !snapshot.data.selection}>
          <label>
            {t.sequenceIdentifier}
            <input
              required
              maxLength={40}
              value={sequence}
              onChange={(event) => setSequence(event.currentTarget.value)}
            />
          </label>
          <button type="submit">{t.insertSequenceField}</button>
        </fieldset>
      </form>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          controller.run(() =>
            editor.insertBodyPageField({
              field: referenceKind,
              bookmark,
              ...(hyperlink ? { hyperlink: true } : {}),
              ...(referenceKind === "PAGEREF" && relative
                ? { relative: true }
                : {}),
            }),
          );
        }}
      >
        <fieldset disabled={disabled || !snapshot.data.selection}>
          <label>
            {t.referenceType}
            <select
              value={referenceKind}
              onChange={(event) =>
                setReferenceKind(
                  event.currentTarget.value === "REF" ? "REF" : "PAGEREF",
                )
              }
            >
              <option value="PAGEREF">{t.pageReference}</option>
              <option value="REF">{t.textReference}</option>
            </select>
          </label>
          <label>
            {referenceKind === "REF"
              ? t.textReferenceTarget
              : t.pageReferenceTarget}
            <input
              aria-label={
                referenceKind === "REF"
                  ? t.textReferenceTarget
                  : t.pageReferenceTarget
              }
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
            {referenceKind === "REF"
              ? t.textReferenceLink
              : t.pageReferenceLink}
          </label>
          {referenceKind === "PAGEREF" && (
            <label>
              <input
                type="checkbox"
                checked={relative}
                onChange={(event) => setRelative(event.currentTarget.checked)}
              />
              {t.pageReferenceRelative}
            </label>
          )}
          <button type="submit" disabled={!bookmark}>
            {referenceKind === "REF"
              ? t.insertTextReference
              : t.insertPageReference}
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
                    event.currentTarget.value === "REF"
                      ? { field: "REF", bookmark }
                      : event.currentTarget.value === "SEQ"
                        ? {
                            field: "SEQ",
                            sequence,
                            ...(draftFormat ? { format: draftFormat } : {}),
                          }
                        : event.currentTarget.value === "PAGEREF"
                          ? {
                              field: "PAGEREF",
                              bookmark,
                              ...(draftFormat ? { format: draftFormat } : {}),
                            }
                          : {
                              field:
                                event.currentTarget.value === "PAGE"
                                  ? "PAGE"
                                  : "NUMPAGES",
                              ...(draftFormat ? { format: draftFormat } : {}),
                            },
                  )
                }
              >
                <option value="PAGE">{t.currentPageField}</option>
                <option value="NUMPAGES">{t.totalPagesField}</option>
                <option value="PAGEREF">{t.pageReference}</option>
                <option value="REF">{t.textReference}</option>
                <option value="SEQ">{t.sequenceField}</option>
              </select>
            </label>
            {draft.field === "SEQ" && (
              <label>
                {t.sequenceIdentifier}
                <input
                  aria-label={t.selectedSequenceIdentifier}
                  required
                  maxLength={40}
                  value={draft.sequence}
                  onChange={(event) =>
                    setDraft({ ...draft, sequence: event.currentTarget.value })
                  }
                />
              </label>
            )}
            {(draft.field === "PAGEREF" || draft.field === "REF") && (
              <>
                <label>
                  {draft.field === "REF"
                    ? t.textReferenceTarget
                    : t.pageReferenceTarget}
                  <input
                    aria-label={
                      draft.field === "REF"
                        ? t.selectedTextReferenceTarget
                        : t.selectedPageReferenceTarget
                    }
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
                  {draft.field === "REF"
                    ? t.selectedTextReferenceLink
                    : t.selectedPageReferenceLink}
                </label>
                {draft.field === "PAGEREF" && (
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
                )}
              </>
            )}
            {draft.field !== "REF" && (
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
                              DocxPageField["format"]
                            >,
                          }
                        : field,
                    );
                  }}
                >
                  <option value="">
                    {draft.field === "SEQ"
                      ? t.defaultSequenceFormat
                      : t.inheritedPageNumberFormat}
                  </option>
                  {listFormats
                    .filter(
                      (format) =>
                        format !== "bullet" && format !== "decimalZero",
                    )
                    .map((format) => (
                      <option key={format} value={format}>
                        {t[`listFormat_${format}`]}
                      </option>
                    ))}
                </select>
              </label>
            )}
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
                {reference.field === "REF"
                  ? t.followTextReference
                  : t.followPageReference}
              </button>
            )}
          </fieldset>
        </form>
      )}
    </section>
  );
}
