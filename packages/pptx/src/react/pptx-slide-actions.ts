import { pptxSlideCountLimit } from "@open-document/wasm/engine-source";
import { messages } from "@open-document/ui/messages";
import type { RibbonAction } from "@open-document/ui/ribbon";
import type { PptxSlideEdit } from "../web/pptx.js";
import type { PanelProps } from "./context.js";

export function slideActions(
  {
    controller,
    state,
    file,
    disabled,
  }: Pick<PanelProps, "controller" | "state" | "file" | "disabled">,
  index: number,
): readonly RibbonAction[] {
  const t = messages(state.locale);
  const { editor } = file;
  const { slides, slideOrderReason, slideVisibilityReason, revision } =
    editor.query;
  const target = slides[index];
  if (!target) return [];
  const orderBlocked = disabled || !!slideOrderReason;
  const edit = (change: PptxSlideEdit) => () =>
    controller.run(() => editor.editSlides(change, target.id, revision));
  return [
    {
      label: t.copySlide,
      icon: "copy",
      disabled: orderBlocked || slides.length >= pptxSlideCountLimit,
      run: edit({ action: "copy" }),
    },
    {
      label: t.deleteSlide,
      icon: "trash",
      disabled: orderBlocked || slides.length <= 1,
      run: edit({ action: "delete" }),
    },
    {
      label: target.hidden ? t.showSlide : t.hideSlide,
      icon: target.hidden ? "eye" : "eye-off",
      disabled: disabled || !!slideVisibilityReason,
      run: edit({ action: "hidden", hidden: !target.hidden }),
    },
    {
      label: t.slideEarlier,
      icon: "chevron-up",
      disabled: orderBlocked || index === 0,
      run: edit({ action: "move", index: index - 1 }),
    },
    {
      label: t.slideLater,
      icon: "chevron-down",
      disabled: orderBlocked || index === slides.length - 1,
      run: edit({ action: "move", index: index + 1 }),
    },
  ];
}
