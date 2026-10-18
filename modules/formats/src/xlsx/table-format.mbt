///|
// OOXML font and border records carry whole components when edited directly.
fn CellFormat::for_table(self : CellFormat, base : CellStyle) -> CellFormat {
  let font = self.family is Some(_) ||
    self.size is Some(_) ||
    self.bold is Some(_) ||
    self.italic is Some(_) ||
    self.color is Some(_)
  let borders = [self.left, self.right, self.top, self.bottom].any(side => {
    side is Some(_)
  })
  let pieces = base.font.split("|").map(piece => piece.to_owned()).to_array()
  {
    ..self,
    family: if font {
      Some(self.family.unwrap_or(pieces[0]))
    } else {
      self.family
    },
    size: if font {
      Some(self.size.unwrap_or(base.size))
    } else {
      self.size
    },
    bold: if font {
      Some(self.bold.unwrap_or(pieces.contains("bold")))
    } else {
      self.bold
    },
    italic: if font {
      Some(self.italic.unwrap_or(pieces.contains("italic")))
    } else {
      self.italic
    },
    color: if font {
      Some(self.color.unwrap_or(base.color))
    } else {
      self.color
    },
    left: if borders {
      Some(self.left.unwrap_or(base.borders[0]))
    } else {
      self.left
    },
    right: if borders {
      Some(self.right.unwrap_or(base.borders[1]))
    } else {
      self.right
    },
    top: if borders {
      Some(self.top.unwrap_or(base.borders[2]))
    } else {
      self.top
    },
    bottom: if borders {
      Some(self.bottom.unwrap_or(base.borders[3]))
    } else {
      self.bottom
    },
  }
}
