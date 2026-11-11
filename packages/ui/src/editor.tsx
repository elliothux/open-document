import { useLayoutEffect, useRef, useState } from "react";
import { createPortal, flushSync } from "react-dom";
import { createRoot } from "react-dom/client";
import css from "../dist/styles.js";
import { EditorController } from "./controller.js";
import { EditorShell } from "./shell.js";
import type {
  EditorHost,
  EditorEvents,
  EditorOptions,
  MountedProduct,
  Product,
} from "./types.js";

type ProductFactory<
  O extends EditorOptions,
  E extends EditorHost,
  F extends Product<E>["format"],
> = (options: O) => Product<E> & { readonly format: F };

type EditorProps<
  O extends EditorOptions,
  E extends EditorHost,
  F extends Product<E>["format"],
> = EditorEvents<MountedProduct<E, F>> & {
  options: O;
  product: ProductFactory<O, E, F>;
  onRelease?: () => void;
};

interface Binding<E extends EditorHost, F extends Product<E>["format"]> {
  controller: EditorController<E>;
  handle: MountedProduct<E, F>;
  target: HTMLElement;
  portal: HTMLElement;
  active: boolean;
  started: boolean;
}

/** The host's React tree owns the shell; a portal retains Shadow DOM isolation. */
export function ProductEditor<
  O extends EditorOptions,
  E extends EditorHost,
  F extends Product<E>["format"],
>(props: EditorProps<O, E, F>) {
  const host = useRef<HTMLDivElement>(null);
  const initial = useRef(props);
  const current = useRef(props);
  const [binding, setBinding] = useState<Binding<E, F>>();
  const [failure, setFailure] = useState<string>();
  useLayoutEffect(() => {
    current.current = props;
  }, [props]);

  useLayoutEffect(() => {
    const element = host.current;
    if (!element) return;
    const { options, product } = initial.current;
    const dom = element.ownerDocument;
    const shadow = element.shadowRoot ?? element.attachShadow({ mode: "open" });
    const style = dom.createElement("style");
    if (options.styleNonce) style.nonce = options.styleNonce;
    style.textContent = css;
    const target = dom.createElement("div");
    target.style.height = "100%";
    const portal = dom.createElement("div");
    portal.dataset.odPortal = "";
    const surfaces = dom.createElement("div");
    surfaces.className = "od-surfaces";
    shadow.append(style, target, portal);
    const definition = product(options);
    const controller = new EditorController(
      options,
      definition,
      element,
      surfaces,
      () => {
        style.remove();
        target.remove();
        portal.remove();
        if (session.active) {
          session.active = false;
          setBinding((old) => (old === session ? undefined : old));
          current.current.onRelease?.();
        }
      },
      (error) => current.current.onError?.(error),
    );
    const session: Binding<E, F> = {
      controller,
      target,
      portal,
      active: true,
      started: false,
      handle: {
        format: definition.format,
        getSnapshot: controller.getSnapshot,
        subscribe: controller.subscribe,
        open: controller.open,
        save: controller.save,
        print: controller.print,
        saveAs: (name) => controller.saveAs(name),
        close: controller.close,
        dispose: controller.dispose,
        create: (document) => controller.create(document),
        setTheme: (theme) => controller.setTheme(theme),
        setLocale: (locale) => controller.setLocale(locale),
        setMode: (mode) => controller.setMode(mode),
        commands: controller.commands,
        get editor() {
          const file = controller.getUiSnapshot().file;
          if (!file) throw new Error("Editor is unavailable");
          return file.editor;
        },
      },
    };
    setBinding(session);
    return () => {
      session.active = false;
      // Detach this mount immediately; an in-flight candidate can only release its own nodes.
      style.remove();
      target.remove();
      portal.remove();
      void controller
        .dispose()
        .catch((error: unknown) => current.current.onError?.(error));
    };
  }, []);

  useLayoutEffect(() => {
    if (!binding?.active) return;
    binding.controller.updatePresentation(props.options);
  }, [binding, props.options]);

  useLayoutEffect(() => {
    if (!binding?.active || binding.started) return;
    binding.started = true;
    const { controller, handle } = binding;
    let previous: ReturnType<typeof handle.getSnapshot> | undefined;
    controller.subscribe(() => {
      const snapshot = controller.getUiSnapshot().document;
      if (binding.active && snapshot && snapshot !== previous) {
        previous = snapshot;
        current.current.onChange?.(snapshot);
      }
    });
    // NativeSlot is attached before candidate layout begins.
    void controller
      .initialize()
      .then(
        () => {
          if (binding.active) current.current.onReady?.(handle);
        },
        async (error: unknown) => {
          if (!binding.active) return;
          setFailure(error instanceof Error ? error.message : String(error));
          try {
            await controller.dispose();
          } catch (cleanup) {
            error = new AggregateError(
              [error, cleanup],
              "Mount and cleanup failed",
            );
          }
          current.current.onError?.(error);
        },
      )
      .catch((error: unknown) => current.current.onError?.(error));
  }, [binding]);

  const shadow = host.current?.shadowRoot;
  return (
    <div
      className="open-document-editor"
      ref={host}
      style={{ height: "100%", minHeight: 0 }}
    >
      {binding &&
        createPortal(
          <EditorShell
            controller={binding.controller}
            portal={binding.portal}
          />,
          binding.target,
        )}
      {failure && shadow && createPortal(<p role="alert">{failure}</p>, shadow)}
    </div>
  );
}

export async function mountProduct<
  O extends EditorOptions,
  E extends EditorHost,
  F extends Product<E>["format"],
>(
  container: HTMLElement,
  options: O,
  product: ProductFactory<O, E, F>,
): Promise<MountedProduct<E, F>> {
  options.signal?.throwIfAborted();
  const target = container.ownerDocument.createElement("div");
  target.style.height = "100%";
  container.append(target);
  const root = createRoot(target);
  const ready = Promise.withResolvers<MountedProduct<E, F>>();
  let mounted = true;
  const release = () => {
    if (!mounted) return;
    mounted = false;
    try {
      root.unmount();
    } finally {
      target.remove();
    }
  };
  try {
    flushSync(() =>
      root.render(
        <ProductEditor
          options={options}
          product={product}
          onReady={ready.resolve}
          onError={ready.reject}
          onRelease={release}
        />,
      ),
    );
    return await ready.promise;
  } catch (error) {
    release();
    throw error;
  }
}
