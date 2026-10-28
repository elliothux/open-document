import type { Messages } from "@open-document/ui/messages-en";

export function PptxShapeOptions({ t }: { t: Messages }) {
  return (
    <>
      <option value="text">{t.textBox}</option>
      <option value="rect">{t.rectangle}</option>
      <option value="roundRect">{t.roundRectangle}</option>
      <option value="round1Rect">{t.round1Rect}</option>
      <option value="round2SameRect">{t.round2SameRect}</option>
      <option value="round2DiagRect">{t.round2DiagRect}</option>
      <option value="snipRoundRect">{t.snipRoundRect}</option>
      <option value="ellipse">{t.ellipse}</option>
      <option value="donut">{t.donut}</option>
      <option value="heart">{t.heart}</option>
      <option value="lightningBolt">{t.lightningBolt}</option>
      <option value="triangle">{t.triangle}</option>
      <option value="rtTriangle">{t.rightTriangle}</option>
      <option value="diamond">{t.diamond}</option>
      <option value="parallelogram">{t.parallelogram}</option>
      <option value="trapezoid">{t.trapezoid}</option>
      <option value="pentagon">{t.pentagon}</option>
      <option value="hexagon">{t.hexagon}</option>
      <option value="snip1Rect">{t.snip1Rect}</option>
      <option value="snip2SameRect">{t.snip2SameRect}</option>
      <option value="snip2DiagRect">{t.snip2DiagRect}</option>
      <option value="heptagon">{t.heptagon}</option>
      <option value="octagon">{t.octagon}</option>
      <option value="decagon">{t.decagon}</option>
      <option value="dodecagon">{t.dodecagon}</option>
      <option value="plus">{t.plusShape}</option>
      <option value="star4">{t.star4}</option>
      <option value="star5">{t.star5}</option>
      <option value="star6">{t.star6}</option>
      <option value="star8">{t.star8}</option>
      <option value="star10">{t.star10}</option>
      <option value="star12">{t.star12}</option>
      <option value="star7">{t.star7}</option>
      <option value="star16">{t.star16}</option>
      <option value="star24">{t.star24}</option>
      <option value="star32">{t.star32}</option>
      <option value="chevron">{t.chevron}</option>
      <option value="homePlate">{t.homePlate}</option>
      <option value="line">{t.lineShape}</option>
      <option value="leftArrow">{t.leftArrow}</option>
      <option value="rightArrow">{t.rightArrow}</option>
      <option value="notchedRightArrow">{t.notchedRightArrow}</option>
      <option value="upArrow">{t.upArrow}</option>
      <option value="downArrow">{t.downArrow}</option>
      <option value="leftRightArrow">{t.leftRightArrow}</option>
      <option value="upDownArrow">{t.upDownArrow}</option>
      <option value="quadArrow">{t.quadArrow}</option>
      <option value="leftRightUpArrow">{t.leftRightUpArrow}</option>
      <option value="leftUpArrow">{t.leftUpArrow}</option>
      <option value="bentUpArrow">{t.bentUpArrow}</option>
    </>
  );
}
