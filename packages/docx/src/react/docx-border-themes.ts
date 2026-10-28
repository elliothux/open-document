import type { DocxPageBorder } from "../web/foundation.js";
import type { Messages } from "@open-document/ui/messages-en";

export function borderThemeOptions(
  t: Messages,
): [DocxPageBorder["themeColor"], string][] {
  return [
    [null, t.pageBorderFixed],
    ["dark1", `${t.darkColor} 1`],
    ["light1", `${t.lightColor} 1`],
    ["dark2", `${t.darkColor} 2`],
    ["light2", `${t.lightColor} 2`],
    ["accent1", `${t.accentColor} 1`],
    ["accent2", `${t.accentColor} 2`],
    ["accent3", `${t.accentColor} 3`],
    ["accent4", `${t.accentColor} 4`],
    ["accent5", `${t.accentColor} 5`],
    ["accent6", `${t.accentColor} 6`],
    ["hyperlink", t.hyperlinkColor],
    ["followedHyperlink", t.followedHyperlinkColor],
    ["text1", `${t.pageBorderThemeText} 1`],
    ["text2", `${t.pageBorderThemeText} 2`],
    ["background1", `${t.pageBorderThemeBackground} 1`],
    ["background2", `${t.pageBorderThemeBackground} 2`],
  ];
}
