import { useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { Menu } from "@base-ui/react/menu";
import { Dialog } from "@base-ui/react/dialog";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import type { OwnedFile } from "./types.js";
import { Icon } from "./icons.js";

export function Command({
  label,
  action,
  disabled = false,
  children,
}: {
  label: string;
  action: () => void;
  disabled?: boolean;
  children?: ReactNode;
}) {
  return (
    <button
      type="button"
      className="od-command"
      onClick={action}
      disabled={disabled}
    >
      {children}
      <span>{label}</span>
    </button>
  );
}
export function Group({
  label,
  children,
}: {
  label: string;
  children: ReactNode;
}) {
  return (
    <div className="od-group" role="group" aria-label={label}>
      <div className="od-group-items">{children}</div>
      <span className="od-group-label">{label}</span>
    </div>
  );
}

/** React owns the slot; the editor retains its stable native input/semantic nodes. */
export function NativeSlot({
  node,
  className,
}: {
  node: HTMLElement;
  className?: string;
}) {
  const slot = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    slot.current?.append(node);
    return () => {
      node.remove();
    };
  }, [node]);
  return <div ref={slot} className={className} />;
}

export function FileMenu({
  controller,
  state,
  portal,
}: {
  controller: EditorController;
  state: UiSnapshot;
  portal: HTMLElement;
}) {
  const t = messages(state.locale);
  const input = useRef<HTMLInputElement>(null);
  const [action, setAction] = useState<"new" | "saveAs" | "import">(),
    [name, setName] = useState(state.name),
    [file, setFile] = useState<File>(),
    [conversions, setConversions] = useState({
      numbers: false,
      dates: false,
      formulas: false,
    });
  const unavailable = state.loading || state.saving || !state.file;
  return (
    <>
      <Menu.Root modal={false}>
        <Menu.Trigger>{t.file}</Menu.Trigger>
        <Menu.Portal container={portal}>
          <Menu.Positioner
            className="od-menu-positioner"
            sideOffset={4}
            align="start"
          >
            <Menu.Popup className="od-menu">
              {controller.options.format !== "pdf" && (
                <Menu.Item
                  className="od-menu-item"
                  disabled={unavailable}
                  onClick={() => {
                    setName(`Untitled.${controller.options.format}`);
                    setAction("new");
                  }}
                >
                  {t.newDocument}
                </Menu.Item>
              )}
              <Menu.Item
                className="od-menu-item"
                disabled={unavailable}
                onClick={() => input.current?.click()}
              >
                {t.open}
              </Menu.Item>
              <Menu.Item
                className="od-menu-item"
                disabled={unavailable}
                onClick={() => controller.run(controller.save)}
              >
                {t.save}
              </Menu.Item>
              {state.file?.format !== "pdf" && (
                <>
                  <Menu.Item
                    className="od-menu-item"
                    disabled={unavailable}
                    onClick={() => controller.run(() => controller.exportPdf())}
                  >
                    {state.file?.format === "pptx"
                      ? t.exportAll
                      : state.file?.format === "xlsx"
                        ? t.exportWorkbook
                        : t.exportPdf}
                  </Menu.Item>
                  {(state.file?.format === "pptx" ||
                    state.file?.format === "xlsx") && (
                    <Menu.Item
                      className="od-menu-item"
                      disabled={unavailable}
                      onClick={() =>
                        controller.run(() => controller.exportPdf(false))
                      }
                    >
                      {state.file?.format === "xlsx"
                        ? t.exportCurrentSheet
                        : t.exportCurrent}
                    </Menu.Item>
                  )}
                </>
              )}
              {state.file?.format === "pptx" && (
                <Menu.Item
                  className="od-menu-item"
                  disabled={unavailable}
                  onClick={() => controller.run(() => controller.exportPng())}
                >
                  {t.exportPng}
                </Menu.Item>
              )}
              {state.file?.format === "xlsx" && (
                <>
                  <p>{t.csvNotice}</p>
                  <Menu.Item
                    className="od-menu-item"
                    disabled={unavailable}
                    onClick={() => controller.run(() => controller.exportCsv())}
                  >
                    {t.exportCsv}
                  </Menu.Item>
                  <Menu.Item
                    className="od-menu-item"
                    disabled={unavailable}
                    onClick={() =>
                      controller.run(() => controller.exportCsv(true))
                    }
                  >
                    {t.exportCsvSelection}
                  </Menu.Item>
                </>
              )}
              <Menu.Item
                className="od-menu-item"
                disabled={unavailable}
                onClick={() => {
                  setName(state.name);
                  setAction("saveAs");
                }}
              >
                {t.saveAs}
              </Menu.Item>
              <Menu.Item
                className="od-menu-item"
                disabled={unavailable}
                onClick={() => controller.run(controller.close)}
              >
                {t.close}
              </Menu.Item>
            </Menu.Popup>
          </Menu.Positioner>
        </Menu.Portal>
      </Menu.Root>
      <input
        ref={input}
        type="file"
        hidden
        accept={
          controller.options.format === "xlsx"
            ? ".xlsx,.csv,.tsv"
            : `.${controller.options.format}`
        }
        onChange={(event) => {
          const file = event.currentTarget.files?.[0];
          event.currentTarget.value = "";
          if (!file) return;
          if (
            controller.options.format === "xlsx" &&
            /\.(csv|tsv)$/i.test(file.name)
          ) {
            setFile(file);
            setConversions({ numbers: false, dates: false, formulas: false });
            setAction("import");
            return;
          }
          controller.run(() => controller.openFile(file));
        }}
      />
      <Dialog.Root
        open={!!action}
        onOpenChange={(open) => {
          if (!open) setAction(undefined);
        }}
      >
        <Dialog.Portal container={portal}>
          <Dialog.Backdrop className="od-backdrop" />
          <Dialog.Popup className="od-dialog">
            <Dialog.Title className="od-dialog-title">
              {action === "import"
                ? t.importDelimited
                : action === "new"
                  ? t.newDocument
                  : t.saveAs}
            </Dialog.Title>
            <Dialog.Description>
              {action === "import" ? t.importNotice : t.fileName}
            </Dialog.Description>
            <form
              onSubmit={(event) => {
                event.preventDefault();
                const operation = action;
                setAction(undefined);
                controller.run(() =>
                  operation === "import" && file
                    ? controller.openFile(file, conversions)
                    : operation === "new"
                      ? controller.create({ name })
                      : controller.saveAs(name),
                );
              }}
            >
              {action === "import" ? (
                <>
                  <p>{file?.name}</p>
                  {(["numbers", "dates", "formulas"] as const).map((key) => (
                    <label key={key}>
                      <input
                        type="checkbox"
                        checked={conversions[key]}
                        onChange={(event) =>
                          setConversions({
                            ...conversions,
                            [key]: event.currentTarget.checked,
                          })
                        }
                      />
                      {
                        t[
                          key === "numbers"
                            ? "importNumbers"
                            : key === "dates"
                              ? "importDates"
                              : "importFormulas"
                        ]
                      }
                    </label>
                  ))}
                </>
              ) : (
                <label>
                  {t.fileName}
                  <input
                    autoFocus
                    required
                    value={name}
                    onChange={(event) => setName(event.currentTarget.value)}
                  />
                </label>
              )}
              <div className="od-dialog-actions">
                <Dialog.Close>{t.cancel}</Dialog.Close>
                <button type="submit" disabled={unavailable}>
                  {action === "import"
                    ? t.importDelimited
                    : action === "new"
                      ? t.createDocument
                      : t.saveAs}
                </button>
              </div>
            </form>
          </Dialog.Popup>
        </Dialog.Portal>
      </Dialog.Root>
    </>
  );
}

export function LeaveConfirmation({
  controller,
  state,
  portal,
}: {
  controller: EditorController;
  state: UiSnapshot;
  portal: HTMLElement;
}) {
  const t = messages(state.locale),
    dialog = state.dialog;
  return (
    <Dialog.Root
      open={!!dialog}
      onOpenChange={(open) => {
        if (!open) controller.choose("cancel");
      }}
    >
      <Dialog.Portal container={portal}>
        <Dialog.Backdrop className="od-backdrop" />
        <Dialog.Popup className="od-dialog">
          <Dialog.Title className="od-dialog-title">
            {dialog?.kind === "draft" ? t.draftTitle : t.unsavedTitle}
          </Dialog.Title>
          <Dialog.Description>
            {dialog?.kind === "draft" ? t.draftText : t.unsavedText}
          </Dialog.Description>
          <div className="od-dialog-actions">
            <Dialog.Close onClick={() => controller.choose("cancel")}>
              {t.keepEditing}
            </Dialog.Close>
            <button type="button" onClick={() => controller.choose("discard")}>
              {dialog?.kind === "draft" ? t.discardDraft : t.discard}
            </button>
            {dialog?.canSave && (
              <button
                type="button"
                className="od-primary"
                onClick={() => controller.choose("save")}
              >
                {controller.options.onSave ? t.saveClose : t.downloadClose}
              </button>
            )}
          </div>
        </Dialog.Popup>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

export function ClipboardGroup({
  controller,
  state,
  file,
  portal,
  disabled,
}: {
  controller: EditorController;
  state: UiSnapshot;
  file: OwnedFile;
  portal: HTMLElement;
  disabled: boolean;
}) {
  const t = messages(state.locale);
  const textMode =
    file.format !== "pptx" || file.editor.query.selection.mode === "text";
  const writeDisabled =
    disabled ||
    !textMode ||
    !!state.document?.readOnlyReason ||
    (file.format === "pptx" &&
      !!file.editor.query.objects.find(
        (object) => object.id === file.editor.query.selection.object,
      )?.textReadOnlyReason);
  const [open, setOpen] = useState(false),
    [text, setText] = useState("");
  const field = useRef<HTMLTextAreaElement>(null);
  const paste = async () => {
    if (file.format === "pdf") return;
    await file.editor.paste(text);
    setOpen(false);
    setText("");
    file.editor.focus();
  };
  return (
    <Group label={t.clipboard}>
      <Command
        label={t.copy}
        disabled={disabled || !textMode}
        action={() => controller.run(() => file.editor.copy())}
      >
        <Icon name="copy" />
      </Command>
      {(file.format === "docx" || file.format === "pptx") && (
        <Command
          label={t.cut}
          disabled={writeDisabled}
          action={() => controller.run(() => file.editor.copy(true))}
        >
          <Icon name="cut" />
        </Command>
      )}
      {file.format !== "pdf" && (
        <Dialog.Root open={open} onOpenChange={setOpen}>
          <Dialog.Trigger className="od-command" disabled={writeDisabled}>
            <Icon name="paste" />
            <span>{t.paste}</span>
          </Dialog.Trigger>
          <Dialog.Portal container={portal}>
            <Dialog.Backdrop className="od-backdrop" />
            <Dialog.Popup className="od-dialog" initialFocus={field}>
              <Dialog.Title className="od-dialog-title">
                {t.rangePaste}
              </Dialog.Title>
              <Dialog.Description>{t.pasteHint}</Dialog.Description>
              <label className="od-paste-label">
                {t.pasteText}
                <textarea
                  ref={field}
                  value={text}
                  onChange={(event) => setText(event.currentTarget.value)}
                />
              </label>
              <div className="od-dialog-actions">
                <Dialog.Close>{t.cancel}</Dialog.Close>
                <button
                  type="button"
                  className="od-primary"
                  onClick={() => controller.run(paste)}
                >
                  {t.apply}
                </button>
              </div>
            </Dialog.Popup>
          </Dialog.Portal>
        </Dialog.Root>
      )}
    </Group>
  );
}
