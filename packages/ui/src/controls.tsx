import { useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { Menu } from "@base-ui/react/menu";
import { Dialog } from "@base-ui/react/dialog";
import type { EditorController, UiSnapshot } from "./controller.js";
import { messages } from "./messages.js";
import type { OwnedFile } from "./types.js";
import { EditorCommandButton, useEditorCommand } from "./commands.js";
import { Icon, type IconName } from "./icons.js";
import type { RibbonAction } from "./ribbon.js";
export function Command({
  label,
  action,
  disabled = false,
  icon,
  iconOnly = false,
  pressed,
  children,
}: {
  label: string;
  action: () => void;
  disabled?: boolean;
  icon?: IconName;
  /** Show only the icon; the label stays as the accessible name and tooltip. */
  iconOnly?: boolean;
  /** Toggle state, for commands that open a panel or switch a mode. */
  pressed?: boolean | undefined;
  children?: ReactNode;
}) {
  return (
    <button
      type="button"
      className={iconOnly ? "od-command od-command-icon" : "od-command"}
      title={iconOnly ? label : undefined}
      aria-pressed={pressed}
      onClick={action}
      disabled={disabled}
    >
      {icon && <Icon name={icon} />}
      {children}
      <span>{label}</span>
    </button>
  );
}
export function Group({
  label,
  icon,
  children,
}: {
  label: string;
  /** Shown beside the label where the label is visible, such as in panels. */
  icon?: IconName;
  children: ReactNode;
}) {
  return (
    <div className="od-group" role="group" aria-label={label}>
      <div className="od-group-items">{children}</div>
      <span className="od-group-label">
        {icon && <Icon name={icon} />}
        {label}
      </span>
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
  actions,
}: {
  controller: EditorController;
  state: UiSnapshot;
  portal: HTMLElement;
  actions?: readonly RibbonAction[] | undefined;
}) {
  const t = messages(state.locale);
  const save = useEditorCommand("save", controller.commands);
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
        <Menu.Trigger className="od-file-trigger">
          {t.file}
          <Icon name="chevron-down" />
        </Menu.Trigger>
        <Menu.Portal container={portal}>
          <Menu.Positioner
            className="od-menu-positioner"
            sideOffset={4}
            align="start"
          >
            <Menu.Popup className="od-menu">
              {controller.product.canCreate && state.mode === "edit" && (
                <Menu.Item
                  className="od-menu-item"
                  disabled={unavailable}
                  onClick={() => {
                    setName(`Untitled.${controller.product.format}`);
                    setAction("new");
                  }}
                >
                  <Icon name="file-plus" />
                  {t.newDocument}
                </Menu.Item>
              )}
              <Menu.Item
                className="od-menu-item"
                disabled={unavailable}
                onClick={() => {
                  if (controller.options.onOpen)
                    controller.run(controller.options.onOpen);
                  else input.current?.click();
                }}
              >
                <Icon name="folder-open" />
                {t.open}
              </Menu.Item>
              <Menu.Separator className="od-menu-separator" />
              <Menu.Item
                className="od-menu-item"
                disabled={!save?.enabled}
                onClick={() =>
                  void controller.commands.execute("save").catch(() => {})
                }
              >
                <Icon name="save" />
                {save?.label ?? t.save}
                <Shortcut keys="S" />
              </Menu.Item>
              <Menu.Item
                className="od-menu-item"
                disabled={unavailable}
                onClick={() => {
                  setName(state.name);
                  setAction("saveAs");
                }}
              >
                <Icon name="file-stack" />
                {t.saveAs}
              </Menu.Item>
              <Menu.Item
                className="od-menu-item"
                disabled={unavailable}
                onClick={() => controller.run(controller.print)}
              >
                <Icon name="printer" />
                {t.printDocument}
              </Menu.Item>
              {controller.product.outputs.length > 0 && (
                <Menu.SubmenuRoot>
                  <Menu.SubmenuTrigger
                    className="od-menu-item od-submenu-trigger"
                    disabled={unavailable}
                  >
                    <Icon name="download" />
                    {t.exportGroup}
                    <Icon name="chevron-right" />
                  </Menu.SubmenuTrigger>
                  <Menu.Portal container={portal}>
                    <Menu.Positioner
                      className="od-menu-positioner"
                      sideOffset={6}
                      alignOffset={-4}
                    >
                      <Menu.Popup className="od-menu">
                        {controller.product.outputs.map((output) => (
                          <Menu.Item
                            key={output.kind}
                            className="od-menu-item"
                            disabled={unavailable}
                            title={output.title ? t[output.title] : undefined}
                            onClick={() =>
                              controller.run(() =>
                                controller.exportOutput(output.kind),
                              )
                            }
                          >
                            <Icon name={outputIcon(output.kind)} />
                            {t[output.label]}
                          </Menu.Item>
                        ))}
                      </Menu.Popup>
                    </Menu.Positioner>
                  </Menu.Portal>
                </Menu.SubmenuRoot>
              )}
              {!!actions?.length && (
                <Menu.Separator className="od-menu-separator" />
              )}
              {actions?.map((action) => (
                <Menu.Item
                  className="od-menu-item"
                  key={action.label}
                  disabled={!!action.disabled}
                  onClick={action.run}
                >
                  <Icon name={action.icon} />
                  {action.label}
                </Menu.Item>
              ))}
              <Menu.Separator className="od-menu-separator" />
              <Menu.Item
                className="od-menu-item"
                disabled={unavailable}
                onClick={() => controller.run(controller.close)}
              >
                <Icon name="close" />
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
        accept={controller.product.accept}
        onChange={(event) => {
          const file = event.currentTarget.files?.[0];
          event.currentTarget.value = "";
          if (!file) return;
          if (controller.product.delimited && /\.(csv|tsv)$/i.test(file.name)) {
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
            {action === "import" && (
              <Dialog.Description>{t.importNotice}</Dialog.Description>
            )}
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

/** Export formats read at a glance: documents, images, and data. */
function outputIcon(kind: string): IconName {
  if (/png|jpe?g|image/i.test(kind)) return "image";
  if (/csv/i.test(kind)) return "file-spreadsheet";
  if (/html|markdown/i.test(kind)) return "text-input";
  return "file-preview";
}

const mac =
  typeof navigator !== "undefined" &&
  /Mac|iP(hone|ad)/.test(navigator.userAgent);

/** Visual shortcut hint; excluded from the accessible name. */
function Shortcut({ keys }: { keys: string }) {
  return (
    <kbd className="od-menu-shortcut" aria-hidden="true">
      {mac ? `⌘${keys}` : `Ctrl+${keys}`}
    </kbd>
  );
}

export function EditorSettings({
  controller,
  state,
  portal,
}: {
  controller: EditorController;
  state: UiSnapshot;
  portal: HTMLElement;
}) {
  const t = messages(state.locale);
  return (
    <Menu.Root modal={false}>
      <Menu.Trigger
        className="od-caption-icon"
        aria-label={t.settings}
        title={t.settings}
      >
        <Icon name="settings" />
      </Menu.Trigger>
      <Menu.Portal container={portal}>
        <Menu.Positioner
          className="od-menu-positioner"
          sideOffset={4}
          align="end"
        >
          <Menu.Popup className="od-menu" aria-label={t.settings}>
            <Menu.RadioGroup
              aria-label={t.theme}
              value={state.theme}
              onValueChange={(value: unknown) => {
                if (value === "light" || value === "dark")
                  controller.setTheme(value);
              }}
            >
              <span className="od-menu-label" aria-hidden="true">
                {t.theme}
              </span>
              <SettingChoice value="light">{t.light}</SettingChoice>
              <SettingChoice value="dark">{t.dark}</SettingChoice>
            </Menu.RadioGroup>
            <Menu.Separator className="od-menu-separator" />
            <Menu.RadioGroup
              aria-label={t.language}
              value={state.locale}
              onValueChange={(value: unknown) => {
                if (value === "en-US" || value === "zh-CN")
                  controller.setLocale(value);
              }}
            >
              <span className="od-menu-label" aria-hidden="true">
                {t.language}
              </span>
              <SettingChoice value="en-US">English</SettingChoice>
              <SettingChoice value="zh-CN">中文</SettingChoice>
            </Menu.RadioGroup>
          </Menu.Popup>
        </Menu.Positioner>
      </Menu.Portal>
    </Menu.Root>
  );
}

function SettingChoice({
  value,
  children,
}: {
  value: string;
  children: string;
}) {
  return (
    <Menu.RadioItem
      value={value}
      className="od-menu-item od-menu-choice"
      closeOnClick
    >
      <span>{children}</span>
      <Menu.RadioItemIndicator>
        <Icon name="check" />
      </Menu.RadioItemIndicator>
    </Menu.RadioItem>
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
  const actions = file.clipboard();
  const textMode = actions.textMode,
    canCopy = actions.canCopy;
  const pasteDisabled =
    disabled ||
    state.mode === "view" ||
    !!state.document?.readOnlyReason ||
    actions.readOnly;
  const writeDisabled = pasteDisabled || !canCopy;
  const [open, setOpen] = useState(false),
    [text, setText] = useState(""),
    [pasteFormat, setPasteFormat] = useState("plain"),
    [pasteMode, setPasteMode] = useState<"source" | "merge" | "text">("source");
  const field = useRef<HTMLTextAreaElement>(null);
  const paste = async () => {
    await actions.paste?.(text, pasteFormat, pasteMode);
    setOpen(false);
    setText("");
    file.editor.focus();
  };
  return (
    <Group label={t.clipboard}>
      <EditorCommandButton id="copy" iconOnly />
      {!!actions.cut && (
        <Command
          label={t.cut}
          iconOnly
          disabled={writeDisabled}
          action={() => controller.run(() => actions.cut?.())}
        >
          <Icon name="cut" />
        </Command>
      )}
      {!!actions.paste && (
        <Dialog.Root open={open} onOpenChange={setOpen}>
          <Dialog.Trigger
            className="od-command od-command-icon"
            title={t.paste}
            disabled={pasteDisabled}
          >
            <Icon name="paste" />
            <span>{t.paste}</span>
          </Dialog.Trigger>
          <Dialog.Portal container={portal}>
            <Dialog.Backdrop className="od-backdrop" />
            <Dialog.Popup className="od-dialog" initialFocus={field}>
              <Dialog.Title className="od-dialog-title">
                {actions.richText && pasteFormat !== "plain"
                  ? pasteFormat === "html"
                    ? t.pasteHtml
                    : t.pasteMarkdown
                  : t.rangePaste}
              </Dialog.Title>
              <Dialog.Description>{t.pasteHint}</Dialog.Description>
              {!!actions.pasteClipboard && (
                <button
                  type="button"
                  disabled={pasteDisabled}
                  onClick={() =>
                    controller.run(async () => {
                      await actions.pasteClipboard?.();
                      setOpen(false);
                      file.editor.focus();
                    })
                  }
                >
                  {t.pasteFormatting}
                </button>
              )}
              <label className="od-paste-label">
                {actions.richText && pasteFormat !== "plain"
                  ? pasteFormat === "html"
                    ? "HTML"
                    : "Markdown"
                  : t.pasteText}
                <textarea
                  ref={field}
                  disabled={!textMode}
                  value={text}
                  onChange={(event) => setText(event.currentTarget.value)}
                />
              </label>
              {actions.richText && (
                <label>
                  {t.pasteFormat}
                  <select
                    value={pasteFormat}
                    onChange={(event) =>
                      setPasteFormat(event.currentTarget.value)
                    }
                  >
                    <option value="plain">{t.pasteText}</option>
                    <option value="markdown">Markdown</option>
                    <option value="html">HTML</option>
                  </select>
                </label>
              )}
              {actions.richText && pasteFormat !== "plain" && (
                <label>
                  {t.pasteMode}
                  <select
                    value={pasteMode}
                    onChange={(event) => {
                      const value = event.currentTarget.value;
                      if (
                        value === "source" ||
                        value === "merge" ||
                        value === "text"
                      )
                        setPasteMode(value);
                    }}
                  >
                    <option value="source">{t.keepSourceFormat}</option>
                    <option value="merge">{t.matchTargetFormat}</option>
                    <option value="text">{t.keepTextOnly}</option>
                  </select>
                </label>
              )}
              <div className="od-dialog-actions">
                <Dialog.Close>{t.cancel}</Dialog.Close>
                <button
                  type="button"
                  className="od-primary"
                  disabled={!textMode}
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
