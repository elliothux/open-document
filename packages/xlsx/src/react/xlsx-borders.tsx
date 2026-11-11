import { useRef } from "react";
import type { CommandTarget } from "@open-document/ui/commands";
import { Icon } from "@open-document/ui/icons";
import { messages } from "@open-document/ui/messages";
import { RibbonMenu } from "@open-document/ui/ribbon";
import type { XlsxCellBorder, XlsxCellFormat } from "../core/xlsx.js";
import type { PanelProps } from "./context.js";

const sides = ["top", "bottom", "left", "right"] as const;
const thin: XlsxCellBorder = { style: "thin", color: "000000" };
const none: XlsxCellBorder = { style: "none", color: "000000" };

export function XlsxBorders({
  controller,
  state,
  file,
  disabled,
  workspace,
}: PanelProps) {
  const target = useRef<CommandTarget | undefined>(undefined);
  if (!workspace) return null;
  const t = messages(state.locale);
  const zh = state.locale === "zh-CN";
  const unavailable =
    disabled || !!file.editor.currentState.formatting.readOnlyReason;
  const apply = (patch: XlsxCellFormat) =>
    controller.run(() => {
      const captured = target.current;
      if (!captured) throw new Error(t.targetChanged);
      return file.editor.formatCells(patch, () =>
        controller.commands.assertTarget(captured),
      );
    });
  return (
    <RibbonMenu
      label={zh ? "边框" : "Borders"}
      portal={workspace.portal}
      className="od-icon-command"
      disabled={unavailable}
      onOpenChange={(open) => {
        if (open) target.current = controller.commands.captureTarget();
      }}
      actions={[
        {
          label: zh ? "所有边框" : "All borders",
          icon: "border-all",
          run: () =>
            apply({ top: thin, bottom: thin, left: thin, right: thin }),
        },
        {
          label: zh ? "无边框" : "No borders",
          icon: "border-none",
          run: () =>
            apply({ top: none, bottom: none, left: none, right: none }),
        },
        ...sides.map((side) => ({
          label: zh
            ? `每格${t[`${side}CellBorder`]}`
            : `${t[`${side}CellBorder`]} on each cell`,
          icon: `border-${side}` as const,
          run: () => apply({ [side]: thin }),
        })),
      ]}
    >
      <Icon name="border-all" />
    </RibbonMenu>
  );
}
