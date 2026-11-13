import { useCallback, useLayoutEffect, useState } from "react";
import { Command, Group } from "@open-document/ui/controls";
import { messages } from "@open-document/ui/messages";
import { downloadBytes } from "@open-document/web-core/download";
import type { PdfNavigation, PdfDestination } from "../core/pdf.js";
import { CachedThumbnail, useThumbnails } from "@open-document/ui/thumbnails";
import { PageArrangeControls } from "./page-arrange.js";
import type { PanelProps } from "./context.js";
import { Icon } from "@open-document/ui/icons";

export function PageTools(props: PanelProps) {
  const { controller, state, file, disabled } = props;
  const t = messages(state.locale);
  const zh = state.locale === "zh-CN";
  const editor = file.editor;
  const { query, property } = editor.getSnapshot().data;
  const [selected, setSelected] = useState<Set<string>>(() => new Set());
  useLayoutEffect(() => {
    const present = new Set(query.pages.map((page) => page.id));
    setSelected((before) => {
      const remaining = new Set([...before].filter((id) => present.has(id)));
      return remaining.size === before.size ? before : remaining;
    });
  }, [query.pages]);
  if (property.startsWith("pageGeometry:")) return null;
  const pages = query.pages
    .filter((page) => selected.has(page.id))
    .map((page) => page.id);
  const targets = pages.length ? pages : [query.page];
  const blocked = disabled || !!state.document?.draft;
  const orderBlocked = blocked || !!query.pageOrderReason;
  return (
    <>
      {query.pageOrderReason && <p role="status">{query.pageOrderReason}</p>}
      <fieldset className="od-pdf-pages">
        <legend>
          <Icon name="file-stack" />
          {zh ? "选择页面" : "Select pages"}
        </legend>
        <div className="od-pdf-page-options">
          {query.pages.map((page, index) => (
            <label key={page.id}>
              <input
                type="checkbox"
                checked={selected.has(page.id)}
                disabled={blocked}
                onChange={(event) => {
                  const checked = event.currentTarget.checked;
                  setSelected((before) => {
                    const next = new Set(before);
                    if (checked) next.add(page.id);
                    else next.delete(page.id);
                    return next;
                  });
                }}
              />
              {zh ? `第 ${index + 1} 页` : `Page ${index + 1}`}
            </label>
          ))}
        </div>
        <p role="status">
          {pages.length
            ? zh
              ? `已选 ${pages.length} 页`
              : `${pages.length} selected`
            : zh
              ? "操作当前页"
              : "Actions use the current page"}
        </p>
        {pages.length > 0 && (
          <button
            type="button"
            disabled={blocked}
            onClick={() => setSelected(new Set())}
          >
            {zh ? "清除页选区" : "Clear page selection"}
          </button>
        )}
      </fieldset>
      <Group label={t.pdfManagePages}>
        <Command
          label={t.earlier}
          disabled={orderBlocked || targets.includes(query.pages[0]!.id)}
          action={() =>
            controller.run(() => editor.operations.movePage(-1, targets))
          }
        />
        <Command
          label={t.later}
          disabled={orderBlocked || targets.includes(query.pages.at(-1)!.id)}
          action={() =>
            controller.run(() => editor.operations.movePage(1, targets))
          }
        />
        <Command
          label={t.rotate}
          disabled={blocked}
          action={() =>
            controller.run(() => editor.operations.rotate(90, targets))
          }
        />
        <Command
          label={zh ? "提取页面" : "Extract pages"}
          icon="download"
          disabled={blocked}
          action={() =>
            controller.run(async () => {
              const output = await editor.operations.extractPages(targets);
              downloadBytes(output.bytes, "application/pdf", "pages.pdf");
            })
          }
        />
        <button
          type="button"
          className="od-command"
          title={t.deleteHint}
          disabled={orderBlocked || targets.length >= query.pages.length}
          onClick={() =>
            controller.run(() => editor.operations.deletePage(targets))
          }
        >
          {zh ? "删除页面" : "Delete pages"}
        </button>
      </Group>
      <details>
        <summary>
          {zh ? "插入、替换和拆分" : "Insert, replace and split"}
        </summary>
        <Group label={zh ? "插入、替换和拆分" : "Insert, replace and split"}>
          <Command
            label={
              state.locale === "zh-CN" ? "插入空白页" : "Insert blank page"
            }
            icon="plus"
            disabled={orderBlocked}
            action={() =>
              controller.run(() => editor.operations.insertBlankPage())
            }
          />
          {[false, true].map((replace) => (
            <label key={String(replace)} className="od-command">
              <Icon name="upload" />
              {state.locale === "zh-CN"
                ? replace
                  ? "替换当前页"
                  : "插入 PDF"
                : replace
                  ? "Replace current page"
                  : "Insert PDF"}
              <input
                type="file"
                accept=".pdf"
                disabled={orderBlocked}
                onChange={(event) => {
                  const input = event.currentTarget;
                  const source = input.files?.[0];
                  input.value = "";
                  if (source)
                    controller.run(async () => {
                      if (source.size > editor.inputLimits.importBytes)
                        throw new Error("PDF import exceeds budget");
                      const bytes = new Uint8Array(await source.arrayBuffer());
                      if (replace) await editor.operations.replacePage(bytes);
                      else await editor.operations.insertPages(bytes);
                    });
                }}
              />
            </label>
          ))}
          <Command
            label={
              state.locale === "zh-CN"
                ? "逐页拆分文件"
                : "Split into page files"
            }
            icon="columns-2"
            disabled={disabled || !!state.document?.draft}
            action={() =>
              controller.run(async () => {
                const files = await editor.operations.splitFiles();
                for (const file of files) {
                  downloadBytes(
                    file.output.bytes,
                    "application/pdf",
                    file.name,
                  );
                  editor.markDownloaded(file.output);
                }
              })
            }
          />
        </Group>
      </details>
      <details>
        <summary>
          {zh ? "当前页尺寸和拼拆" : "Current page size and arrangement"}
        </summary>
        <Group label={zh ? "当前页尺寸" : "Current page size"}>
          {(["crop", "resize", "scale"] as const).map((action, index) => (
            <Command
              key={action}
              label={
                (state.locale === "zh-CN"
                  ? ["裁剪页面", "调整纸张尺寸", "缩放页面内容"]
                  : ["Crop page", "Resize paper", "Scale page content"])[index]!
              }
              icon="crop"
              disabled={disabled || !!state.document?.draft}
              action={() =>
                controller.run(() => editor.beginPageGeometry(action))
              }
            />
          ))}
        </Group>
        <PageArrangeControls {...props} />
      </details>
    </>
  );
}

export function PageList({ controller, state, file, disabled }: PanelProps) {
  const t = messages(state.locale);
  const { editor } = file;
  const { pages, page: activePage, revision } = editor.snapshot;
  const loadThumbnail = useCallback(
    (page: string, revision: number, signal: AbortSignal) =>
      editor.thumbnail(page, revision, signal),
    [editor],
  );
  const thumbnails = useThumbnails(
    loadThumbnail,
    pages.map(({ id }) => id),
    activePage,
    revision,
    {
      paused: disabled || !!state.document?.draft || !!state.document?.stopped,
      version: editor.thumbnailVersion,
    },
  );
  const [navigation, setNavigation] = useState<PdfNavigation>();
  const [navigationError, setNavigationError] = useState("");
  useLayoutEffect(() => {
    if (file.format !== "pdf") return;
    let active = true;
    void file.editor.navigation(file.editor.snapshot.page).then(
      (result) => {
        if (active) {
          setNavigation(result);
          setNavigationError("");
        }
      },
      (error: unknown) => {
        if (active) {
          setNavigation(undefined);
          setNavigationError(
            error instanceof Error
              ? error.message
              : "PDF navigation is unavailable",
          );
        }
      },
    );
    return () => {
      active = false;
    };
  }, [file, state.document?.revision, state.document?.page]);
  if (file.format !== "pdf") return null;
  return (
    <nav className="od-sidebar od-pdf-sidebar" aria-label={t.pages}>
      {navigationError && <p role="status">{navigationError}</p>}
      {navigation?.outlines.map((outline) => (
        <div
          key={outline.id}
          style={{ marginInlineStart: `${outline.level * 12}px` }}
        >
          <Destination
            target={outline.target}
            label={outline.title}
            disabled={disabled}
            navigate={(page) =>
              controller.run(() => file.editor.goToPage(page))
            }
          />
        </div>
      ))}
      {pages.map((page, index) => (
        <button
          type="button"
          key={page.id}
          disabled={disabled}
          aria-current={state.document?.page === index ? "page" : undefined}
          className="od-page-thumb"
          onClick={() => controller.run(() => file.editor.goToPage(page.id))}
        >
          <CachedThumbnail
            cache={thumbnails}
            id={page.id}
            className="od-page-thumb-image"
          />
          <span className="od-page-thumb-label">
            {t.pages} {index + 1}
          </span>
        </button>
      ))}
      {navigation?.links
        .filter((link) => link.page === file.editor.snapshot.page)
        .map((link) => (
          <Destination
            key={link.id}
            target={link.target}
            label={
              link.target.uri ||
              (state.locale === "zh-CN" ? "页面链接" : "Page link")
            }
            disabled={disabled}
            navigate={(page) =>
              controller.run(() => file.editor.goToPage(page))
            }
          />
        ))}
    </nav>
  );
}

function Destination({
  target,
  label,
  disabled,
  navigate,
}: {
  target: PdfDestination;
  label: string;
  disabled: boolean;
  navigate(page: string): unknown;
}) {
  if (target.kind === "uri" && !disabled)
    return (
      <a href={target.uri} target="_blank" rel="noopener noreferrer">
        {label}
      </a>
    );
  return (
    <button
      type="button"
      disabled={disabled || target.kind === "blocked"}
      title={target.reason}
      onClick={() => navigate(target.page)}
    >
      {label}
    </button>
  );
}
