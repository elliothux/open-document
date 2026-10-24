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
  const [numbering, setNumbering] = useState<ReferenceNumbering>();
  const [separator, setSeparator] = useState("");
  const [relative, setRelative] = useState(false);
  const [superscript, setSuperscript] = useState(false);
  const [sequence, setSequence] = useState("Figure");
  const [sequenceOptions, setSequenceOptions] = useState<SequenceOptions>({});
  const [referenceKind, setReferenceKind] = useState<
    "PAGEREF" | "REF" | "NOTEREF"
  >("PAGEREF");
  const draftFormat = draft && "format" in draft ? draft.format : undefined;
  const labels = referenceLabels(referenceKind, t);
  const selectedLabels = referenceLabels(draft?.field ?? "PAGEREF", t, true);
  const reference =
    source?.field?.field === "PAGEREF" ||
    source?.field?.field === "REF" ||
    source?.field?.field === "NOTEREF"
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
            editor.insertBodyPageField({
              field: "SEQ",
              sequence,
              ...sequenceOptions,
            }),
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
          <SequenceOptionsForm
            value={sequenceOptions}
            onChange={setSequenceOptions}
            t={t}
          />
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
              ...(referenceKind === "REF" && numbering ? { numbering } : {}),
              ...(relative ? { relative: true } : {}),
              ...(referenceKind === "REF" && separator ? { separator } : {}),
              ...(referenceKind === "NOTEREF" && superscript
                ? { superscript: true }
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
                  event.currentTarget.value === "REF"
                    ? "REF"
                    : event.currentTarget.value === "NOTEREF"
                      ? "NOTEREF"
                      : "PAGEREF",
                )
              }
            >
              <option value="PAGEREF">{t.pageReference}</option>
              <option value="REF">{t.textReference}</option>
              <option value="NOTEREF">{t.noteReference}</option>
            </select>
          </label>
          <label>
            {labels.target}
            <input
              aria-label={labels.target}
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
            {labels.link}
          </label>
          {referenceKind === "REF" && (
            <ReferenceNumberingForm
              value={numbering}
              onChange={setNumbering}
              separator={separator}
              onSeparatorChange={setSeparator}
              t={t}
            />
          )}
          {referenceKind === "NOTEREF" && (
            <label>
              <input
                type="checkbox"
                checked={superscript}
                onChange={(event) =>
                  setSuperscript(event.currentTarget.checked)
                }
              />
              {t.noteReferenceSuperscript}
            </label>
          )}
          <label>
            <input
              type="checkbox"
              checked={relative}
              onChange={(event) => setRelative(event.currentTarget.checked)}
            />
            {labels.relative}
          </label>
          <button type="submit" disabled={!bookmark}>
            {labels.insert}
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
                      : event.currentTarget.value === "NOTEREF"
                        ? { field: "NOTEREF", bookmark }
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
                <option value="NOTEREF">{t.noteReference}</option>
                <option value="SEQ">{t.sequenceField}</option>
              </select>
            </label>
            {draft.field === "SEQ" && (
              <>
                <label>
                  {t.sequenceIdentifier}
                  <input
                    aria-label={t.selectedSequenceIdentifier}
                    required
                    maxLength={40}
                    value={draft.sequence}
                    onChange={(event) =>
                      setDraft({
                        ...draft,
                        sequence: event.currentTarget.value,
                      })
                    }
                  />
                </label>
                <SequenceOptionsForm
                  value={draft}
                  onChange={(options) => {
                    const {
                      restart: _restart,
                      repeat: _repeat,
                      headingLevel: _heading,
                      hidden: _hidden,
                      format: _format,
                      ...field
                    } = draft;
                    setDraft({
                      ...field,
                      ...(!options.hidden && _format
                        ? { format: _format }
                        : {}),
                      ...options,
                    });
                  }}
                  t={t}
                  selected
                />
              </>
            )}
            {(draft.field === "PAGEREF" ||
              draft.field === "REF" ||
              draft.field === "NOTEREF") && (
              <>
                <label>
                  {selectedLabels.target}
                  <input
                    aria-label={selectedLabels.target}
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
                  {selectedLabels.link}
                </label>
                {draft.field === "REF" && (
                  <ReferenceNumberingForm
                    value={draft.numbering}
                    separator={draft.separator ?? ""}
                    onSeparatorChange={(value) => {
                      const field = { ...draft };
                      if (value) field.separator = value;
                      else delete field.separator;
                      setDraft(field);
                    }}
                    onChange={(value) => {
                      const field = { ...draft };
                      if (value) field.numbering = value;
                      else delete field.numbering;
                      setDraft(field);
                    }}
                    selected
                    t={t}
                  />
                )}
                {draft.field === "NOTEREF" && (
                  <label>
                    <input
                      type="checkbox"
                      checked={draft.superscript ?? false}
                      onChange={(event) =>
                        setDraft({
                          ...draft,
                          superscript: event.currentTarget.checked,
                        })
                      }
                    />
                    {t.selectedNoteReferenceSuperscript}
                  </label>
                )}
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
                  {selectedLabels.relative}
                </label>
              </>
            )}
            {draft.field !== "REF" && draft.field !== "NOTEREF" && (
              <label>
                {t.fieldNumberFormat}
                <select
                  value={draft.format ?? ""}
                  disabled={draft.field === "SEQ" && draft.hidden === true}
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
                {referenceLabels(reference.field, t).follow}
              </button>
            )}
          </fieldset>
        </form>
      )}
    </section>
  );
}

function referenceLabels(
  kind: DocxBodyField["field"],
  t: ReturnType<typeof messages>,
  selected = false,
) {
  if (kind === "NOTEREF")
    return {
      target: selected ? t.selectedNoteReferenceTarget : t.noteReferenceTarget,
      link: selected ? t.selectedNoteReferenceLink : t.noteReferenceLink,
      relative: selected
        ? t.selectedTextReferenceRelative
        : t.textReferenceRelative,
      insert: t.insertNoteReference,
      follow: t.followNoteReference,
    };
  return kind === "REF"
    ? {
        target: selected
          ? t.selectedTextReferenceTarget
          : t.textReferenceTarget,
        link: selected ? t.selectedTextReferenceLink : t.textReferenceLink,
        relative: selected
          ? t.selectedTextReferenceRelative
          : t.textReferenceRelative,
        insert: t.insertTextReference,
        follow: t.followTextReference,
      }
    : {
        target: selected
          ? t.selectedPageReferenceTarget
          : t.pageReferenceTarget,
        link: selected ? t.selectedPageReferenceLink : t.pageReferenceLink,
        relative: selected
          ? t.selectedPageReferenceRelative
          : t.pageReferenceRelative,
        insert: t.insertPageReference,
        follow: t.followPageReference,
      };
}

type ReferenceNumbering = Extract<DocxBodyField, { field: "REF" }>["numbering"];

function ReferenceNumberingForm({
  value,
  onChange,
  separator,
  onSeparatorChange,
  selected = false,
  t,
}: {
  value: ReferenceNumbering;
  onChange: (value: ReferenceNumbering) => void;
  separator: string;
  onSeparatorChange: (value: string) => void;
  selected?: boolean;
  t: ReturnType<typeof messages>;
}) {
  return (
    <>
      <label>
        {selected ? t.selectedTextReferenceNumbering : t.textReferenceNumbering}
        <select
          value={value ?? ""}
          onChange={(event) => {
            const mode = event.currentTarget.value;
            onChange(
              mode === "noContext" ||
                mode === "relative" ||
                mode === "fullContext"
                ? mode
                : undefined,
            );
          }}
        >
          <option value="">{t.textReferenceText}</option>
          <option value="noContext">{t.textReferenceNoContext}</option>
          <option value="relative">{t.textReferenceRelativeNumber}</option>
          <option value="fullContext">{t.textReferenceFullContext}</option>
        </select>
      </label>
      {value === "fullContext" && (
        <label>
          {selected
            ? t.selectedTextReferenceSeparator
            : t.textReferenceSeparator}
          <input
            maxLength={32}
            value={separator}
            onChange={(event) => onSeparatorChange(event.currentTarget.value)}
          />
        </label>
      )}
    </>
  );
}

type SequenceOptions = Pick<
  Extract<DocxBodyField, { field: "SEQ" }>,
  "restart" | "repeat" | "headingLevel" | "hidden"
>;

function SequenceOptionsForm({
  value,
  onChange,
  selected = false,
  t,
}: {
  value: SequenceOptions;
  onChange: (value: SequenceOptions) => void;
  selected?: boolean;
  t: ReturnType<typeof messages>;
}) {
  return (
    <>
      <label>
        <input
          type="checkbox"
          checked={value.hidden ?? false}
          onChange={(event) =>
            onChange({
              ...(value.restart === undefined
                ? {}
                : { restart: value.restart }),
              ...(value.repeat === undefined ? {} : { repeat: value.repeat }),
              ...(value.headingLevel === undefined
                ? {}
                : { headingLevel: value.headingLevel }),
              hidden: event.currentTarget.checked,
            })
          }
        />
        {selected ? t.selectedSequenceHidden : t.sequenceHidden}
      </label>
      <label>
        {selected ? t.selectedSequenceBehavior : t.sequenceBehavior}
        <select
          value={
            value.repeat
              ? "repeat"
              : value.restart !== undefined
                ? "restart"
                : "next"
          }
          onChange={(event) =>
            onChange({
              ...(value.hidden === undefined ? {} : { hidden: value.hidden }),
              ...(value.headingLevel === undefined
                ? {}
                : { headingLevel: value.headingLevel }),
              ...(event.currentTarget.value === "repeat"
                ? { repeat: true }
                : event.currentTarget.value === "restart"
                  ? { restart: 1 }
                  : {}),
            })
          }
        >
          <option value="next">{t.sequenceNext}</option>
          <option value="repeat">{t.sequenceRepeat}</option>
          <option value="restart">{t.sequenceRestart}</option>
        </select>
      </label>
      {value.restart !== undefined && (
        <label>
          {selected ? t.selectedSequenceStart : t.sequenceStart}
          <input
            type="number"
            required
            min={0}
            max={2147483647}
            step={1}
            value={Number.isNaN(value.restart) ? "" : value.restart}
            onChange={(event) =>
              onChange({
                ...(value.hidden === undefined ? {} : { hidden: value.hidden }),
                restart: event.currentTarget.valueAsNumber,
                ...(value.headingLevel === undefined
                  ? {}
                  : { headingLevel: value.headingLevel }),
              })
            }
          />
        </label>
      )}
      <label>
        {selected ? t.selectedSequenceHeading : t.sequenceHeading}
        <select
          value={value.headingLevel ?? ""}
          onChange={(event) =>
            onChange({
              ...(value.hidden === undefined ? {} : { hidden: value.hidden }),
              ...(value.restart === undefined
                ? {}
                : { restart: value.restart }),
              ...(value.repeat === undefined ? {} : { repeat: value.repeat }),
              ...(event.currentTarget.value === ""
                ? {}
                : { headingLevel: Number(event.currentTarget.value) }),
            })
          }
        >
          <option value="">{t.sequenceHeadingNone}</option>
          {[1, 2, 3, 4, 5, 6, 7, 8, 9].map((level) => (
            <option key={level} value={level}>
              {t.sequenceHeading} {level}
            </option>
          ))}
        </select>
      </label>
    </>
  );
}
