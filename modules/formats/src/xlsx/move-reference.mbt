///|
priv struct CellMove {
  source_sheet : String
  target_sheet : String
  source : Range
  target : Range
}

///|
fn CellMove::address(self : CellMove, address : Address) -> Address {
  {
    row: address.row + self.target.top - self.source.top,
    column: address.column + self.target.left - self.source.left,
  }
}

///|
fn CellMove::range(self : CellMove, range : Range) -> Range {
  let first = self.address({ row: range.top, column: range.left, })
  let last = self.address({ row: range.bottom, column: range.right, })
  { top: first.row, left: first.column, bottom: last.row, right: last.column, }
}

///|
fn Expression::moved(
  self : Expression,
  relocation : CellMove,
  before : String?,
  after : String?,
  independent~ : Bool = false,
  depth~ : Int = 0,
) -> Expression raise @failure.Failure {
  guard depth <= 64 else {
    @failure.reject("limit-exceeded", "Formula expression depth exceeded")
  }
  let next = fn(expression : Expression) raise @failure.Failure {
    expression.moved(relocation, before, after, independent~, depth=depth + 1)
  }
  match self {
    Reference(sheet, first, last) => {
      let context = if sheet is Some(_) { sheet } else { before }
      guard !independent || context is Some(_) else {
        @failure.reject(
          "protected-content", "Defined name cell references require a worksheet",
        )
      }
      // Move the stored name coordinates once; evaluation still offsets relative axes from each caller.
      let range = first.range(last.unwrap_or(first))
      let follows = context
        .map(name => name.to_upper() == relocation.source_sheet.to_upper())
        .unwrap_or(false) &&
        relocation.source.covers(range)
      if follows {
        let qualifier = if sheet is None &&
          after == Some(relocation.target_sheet) {
          None
        } else {
          Some(relocation.target_sheet)
        }
        Reference(
          qualifier,
          { ..first, address: relocation.address(first.address), },
          last.map(a => { ..a, address: relocation.address(a.address), }),
        )
      } else if sheet is None && before != after {
        Reference(before, first, last)
      } else {
        self
      }
    }
    Named(None, name) if before != after => Named(before, name)
    Structured(None, _) if before != after =>
      @failure.reject(
        "protected-content", "Implicit table references require cross-sheet move support",
      )
    Unary(operator, value) => Unary(operator, next(value))
    Binary(operator, a, b) => Binary(operator, next(a), next(b))
    Function(name, args) => Function(name, args.map(next))
    expression => expression
  }
}

///|
fn move_formula(
  text : String,
  relocation : CellMove,
  before : String?,
  after : String?,
  independent~ : Bool = false,
) -> String raise @failure.Failure {
  guard text.length() <= 8192 else {
    @failure.reject("limit-exceeded", "Moved formula exceeds budget")
  }
  let source = text.strip_prefix("=").unwrap_or(text[:]).to_owned()
  let expression = parse_formula(source)
  let next = expression.moved(relocation, before, after, independent~)
  if next == expression {
    text
  } else {
    (if text.has_prefix("=") { "=" } else { "" }) + next.source()
  }
}

///|
fn Session::move_names(
  self : Session,
  relocation : CellMove,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  let tree = Tree::new(self.workbook)
  let changes : Array[@xml.SourceChange] = []
  for node in tree.document.nodes() {
    if node.name != "definedName" || node.uri != spreadsheet_uri {
      continue
    }
    let print = ["_xlnm.Print_Area", "_xlnm.Print_Titles"].contains(
      node.attribute("name").unwrap_or(""),
    )
    let current = if print {
      node
      .attribute("localSheetId")
      .map(scope => self.sheets[natural(scope, self.sheets.length() - 1)].name)
    } else {
      None
    }
    let text = if print {
      let spans : Array[(Int, Int)] = []
      let tokens = formula_tokens(node.text, spans~)
      let pieces : Array[String] = []
      let mut start = 0
      for index, token in tokens {
        if token is Operator(",") || token is End {
          let part = node.text[start:spans[index].0].to_owned()
          let next = move_formula(
            part,
            relocation,
            current,
            current,
            independent=true,
          )
          guard relocation.source_sheet == relocation.target_sheet ||
            part == next else {
            @failure.reject(
              "protected-content", "Cross-sheet print ranges require ownership transfer",
            )
          }
          pieces.push(next)
          start = spans[index].1
        }
      }
      pieces.join(",")
    } else {
      move_formula(node.text, relocation, None, None, independent=true)
    }
    changes.append(axis_text_change(tree, node, text))
  }
  changes
}
