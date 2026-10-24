///|
fn CellFormat::for_merged_cell(
  self : CellFormat,
  address : Address,
  range : Range,
) -> CellFormat {
  let none : CellBorder = { style: "none", color: "000000", }
  {
    ..self,
    left: self.left.map(edge => {
      if address.column == range.left {
        edge
      } else {
        none
      }
    }),
    right: self.right.map(edge => {
      if address.column == range.right {
        edge
      } else {
        none
      }
    }),
    top: self.top.map(edge => if address.row == range.top { edge } else { none }),
    bottom: self.bottom.map(edge => {
      if address.row == range.bottom {
        edge
      } else {
        none
      }
    }),
  }
}

///|
fn Session::merged_style(
  self : Session,
  sheet : Sheet,
  range : Range,
) -> CellStyle raise @failure.Failure {
  let first = self.styles[sheet.style_at({ row: range.top, column: range.left, })]
  if range.top == range.bottom && range.left == range.right {
    return first
  }
  let last = self.styles[sheet.style_at({
      row: range.bottom,
      column: range.right,
    })]
  let borders = first.borders.copy()
  let border_priority = first.border_priority.copy()
  // End-cell right/bottom borders complete the merged outline without expanding large imported ranges.
  for side in [1, 3] {
    if last.borders[side].style != "none" {
      borders[side] = last.borders[side]
      border_priority[side] = last.border_priority[side]
    }
  }
  {
    ..first,
    borders,
    border_priority,
    diagnostic: if first.diagnostic.is_empty() {
      last.diagnostic
    } else {
      first.diagnostic
    },
  }
}

///|
fn Session::merge_formats(
  self : Session,
  sheet : Sheet,
  range : Range,
) -> StyleEdit? raise @failure.Failure {
  guard self.styles_part(self.parts) is Some(path) else { return None }
  let source = self.part_xml(path)
  guard source.source().length() <= 2097152 else {
    @failure.reject("limit-exceeded", "Cell styles exceed history budget")
  }
  let tree = Tree::new(source)
  let root = tree.root("styleSheet")
  let formats = tree.all(tree.one(root.id, "cellXfs").unwrap().id, "xf")
  let borders = tree.all(tree.one(root.id, "borders").unwrap().id, "border")
  let edges = Array::make(4, CellBorder::{ style: "none", color: "000000", })
  let fragments = Array::make(4, "")
  for side in 0..<4 {
    let first = if side < 2 { range.top } else { range.left }
    let last = if side < 2 { range.bottom } else { range.right }
    let mut common : CellBorder? = None
    let mut key : Json? = None
    let mut fragment = ""
    for position in first..<=last {
      let address : Address = {
        row: if side < 2 {
          position
        } else if side == 2 {
          range.top
        } else {
          range.bottom
        },
        column: if side == 0 {
          range.left
        } else if side == 1 {
          range.right
        } else {
          position
        },
      }
      let style = sheet.style_at(address)
      let edge = self.styles[style].borders[side]
      let border = natural(
        formats[style].attribute("borderId").unwrap_or("0"),
        borders.length() - 1,
      )
      let node = tree.one(
        borders[border].id,
        ["left", "right", "top", "bottom"][side],
      )
      if edge.style == "none" || node is None {
        common = None
        break
      }
      let node = node.unwrap()
      let identity = style_key(tree, node)
      if key is Some(previous) && previous != identity {
        common = None
        break
      }
      if key is None {
        fragment = style_markup(tree, node)
      }
      key = Some(identity)
      common = Some(edge)
    }
    if common is Some(edge) {
      edges[side] = edge
      fragments[side] = fragment
    }
  }
  let border = CellFormat::new(
    left=Some(edges[0]),
    right=Some(edges[1]),
    top=Some(edges[2]),
    bottom=Some(edges[3]),
  )
  let patches : Array[CellFormat] = []
  let pool : Map[CellFormat, Int] = Map([])
  let originals : Map[String, (Int, Int)] = Map([])
  let border_sides : Map[Int, Array[String]] = Map([])
  for row in range.top..<=range.bottom {
    for column in range.left..<=range.right {
      let address : Address = { row, column, }
      let style = sheet.style_at(address)
      let patch = border.for_merged_cell(address, range)
      if patch.applied(self.styles[style]) == self.styles[style] {
        continue
      }
      let index = if pool.get(patch) is Some(index) {
        index
      } else {
        let index = patches.length()
        patches.push(patch)
        pool[patch] = index
        border_sides[index] = [
          if column == range.left && !fragments[0].is_empty() {
            fragments[0]
          } else {
            "<od:left xmlns:od=\"\{spreadsheet_uri}\"/>"
          },
          if column == range.right && !fragments[1].is_empty() {
            fragments[1]
          } else {
            "<od:right xmlns:od=\"\{spreadsheet_uri}\"/>"
          },
          if row == range.top && !fragments[2].is_empty() {
            fragments[2]
          } else {
            "<od:top xmlns:od=\"\{spreadsheet_uri}\"/>"
          },
          if row == range.bottom && !fragments[3].is_empty() {
            fragments[3]
          } else {
            "<od:bottom xmlns:od=\"\{spreadsheet_uri}\"/>"
          },
        ]
        index
      }
      originals[address.name()] = (style, index)
    }
  }
  if originals.is_empty() {
    None
  } else {
    Some(self.derive_formats(originals, patches, border_sides~))
  }
}
