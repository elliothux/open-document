///|
// Cell backgrounds and borders precede all cell text, including overflowing text.
priv struct PagePaint {
  width : Double
  height : Double
  fills : Array[@layout.Fill]
  strokes : Array[(@layout.Border, String, Double)]
  texts : Array[(@layout.PositionedText, @layout.Border)]
}

///|
fn PagePaint::positioned(self : PagePaint) -> @layout.PositionedPage {
  let primitives : Array[@layout.PositionedPrimitive] = []
  for fill in self.fills {
    primitives.push(Rectangle(fill))
  }
  for (rect, color, width) in self.strokes {
    primitives.push(Stroke(rect, color, width))
  }
  for (text, clip) in self.texts {
    primitives.push(Clip(clip))
    primitives.push(Text(text))
    primitives.push(Restore)
  }
  { width: self.width, height: self.height, primitives, }
}
