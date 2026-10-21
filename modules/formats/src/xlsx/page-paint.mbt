///|
// Cell backgrounds and borders precede all cell text, including overflowing text.
priv struct PagePaint {
  width : Double
  height : Double
  fills : Array[@layout.Fill]
  bars : Array[@layout.PositionedPrimitive]
  strokes : Array[(@layout.Border, String, Double)]
  texts : Array[(Array[@layout.PositionedPrimitive], @layout.Border)]
  cells : Array[(Range, @layout.Border)]
}

///|
fn PagePaint::positioned(self : PagePaint) -> @layout.PositionedPage {
  let primitives : Array[@layout.PositionedPrimitive] = []
  for fill in self.fills {
    primitives.push(Rectangle(fill))
  }
  primitives.append(self.bars)
  for (rect, color, width) in self.strokes {
    primitives.push(Stroke(rect, color, width))
  }
  for (items, clip) in self.texts {
    primitives.push(Clip(clip))
    primitives.append(items)
    primitives.push(Restore)
  }
  { width: self.width, height: self.height, primitives, }
}
