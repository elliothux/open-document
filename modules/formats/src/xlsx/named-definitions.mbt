///|
priv struct NamedDefinitions {
  sources : Map[(Int32, String), String]
  tables : Array[StructuredTable]
}

///|
fn NamedDefinitions::empty() -> NamedDefinitions {
  { sources: Map([]), tables: [], }
}

///|
fn NamedDefinitions::same(
  self : NamedDefinitions,
  other : NamedDefinitions,
) -> Bool {
  self.tables == other.tables &&
  self.sources.length() == other.sources.length() &&
  self.sources.iter().all(entry => other.sources.get(entry.0) == Some(entry.1))
}

///|
fn name_identifier(text : String) -> Bool {
  guard !text.is_empty() && text.length() <= 255 else { return false }
  let mut first = true
  for character in text.iter() {
    let letter = match @ucd.general_category(character) {
      Lu | Ll | Lt | Lm | Lo | Nl => true
      _ => false
    }
    let number_or_mark = match @ucd.general_category(character) {
      Nd | Mn | Mc | Me => true
      _ => false
    }
    let allowed = letter ||
      character == '_' ||
      character == '\\' ||
      (!first && (character == '.' || number_or_mark))
    if !allowed {
      return false
    }
    first = false
  }
  true
}

///|
fn read_named_definitions(
  workbook : @xml.Document,
  count : Int32,
) -> NamedDefinitions raise @failure.Failure {
  let tree = Tree::new(workbook)
  let result = NamedDefinitions::empty()
  let mut units = 0
  if tree.one(tree.root("workbook").id, "definedNames") is Some(parent) {
    for node in tree.all(parent.id, "definedName") {
      let name = node.attribute("name").unwrap_or("")
      let scope = node
        .attribute("localSheetId")
        .map(value => natural(value, 255))
        .unwrap_or(-1)
      guard name_identifier(name) &&
        scope < count &&
        !result.sources.contains((scope, name.to_upper())) else {
        @failure.reject("malformed-xlsx", "Invalid or duplicate defined name")
      }
      units += name.length() + node.text.length()
      guard result.sources.length() < 4096 && units <= 1048576 else {
        @failure.reject(
          "limit-exceeded", "Workbook defined names exceed budget",
        )
      }
      result.sources[(scope, name.to_upper())] = node.text
    }
  }
  result
}

///|
fn Session::formula_names(self : Session) -> NamedDefinitions {
  self.calculation
  .map(calculation => calculation.names)
  .unwrap_or(NamedDefinitions::empty())
}

///|
fn Expression::resolve_names(
  self : Expression,
  sheets : Array[Sheet],
  sheet : Int32,
  origin : Address,
  work : FormulaWork,
  active~ : Map[(Int32, String), Bool] = Map([]),
  depth~ : Int32 = 0,
) -> Expression raise @failure.Failure {
  work.spend()
  guard depth <= 64 else {
    @failure.reject("limit-exceeded", "Defined name expression depth exceeded")
  }
  match self {
    Constant(_) => self
    Structured(name, selector) =>
      structured_reference(name, selector, sheets, sheet, origin, work)
    Reference(target, _, _) => {
      guard target is Some(_) || sheet >= 0 else {
        @failure.reject(
          "unsupported-formula", "Defined name cell references require a worksheet",
        )
      }
      self
    }
    Named(target, name) => {
      if target is None &&
        work.names.tables.any(table => table.name.to_upper() == name.to_upper()) {
        return structured_reference(
          Some(name),
          "[#Data]",
          sheets,
          sheet,
          origin,
          work,
        )
      }
      let context = if target is Some(_) {
        referenced_sheet(sheets, 0, target)
      } else {
        sheet
      }
      let scoped = (context, name.to_upper())
      let key = if work.names.sources.contains(scoped) {
        scoped
      } else {
        (-1, name.to_upper())
      }
      guard work.names.sources.get(key) is Some(source) else {
        return Constant(Error("#NAME?"))
      }
      guard !active.contains(key) else {
        @failure.reject("circular-reference", "Circular defined name: " + name)
      }
      work.spend(amount=source.length())
      active[key] = true
      defer ignore(active.remove(key))
      let expression = parse_formula(
        source.strip_prefix("=").unwrap_or(source[:]).to_owned(),
      )
      let shifted = expression.source(
        rows=origin.row - 1,
        columns=origin.column - 1,
        invalid_ref=true,
      )
      // Like DefName's independent worksheet, bodies use global names unless qualified.
      parse_formula(shifted).resolve_names(
        sheets,
        -1,
        origin,
        work,
        active~,
        depth=depth + 1,
      )
    }
    Unary(op, value) =>
      Unary(
        op,
        value.resolve_names(
          sheets,
          sheet,
          origin,
          work,
          active~,
          depth=depth + 1,
        ),
      )
    Binary(op, left, right) =>
      Binary(
        op,
        left.resolve_names(
          sheets,
          sheet,
          origin,
          work,
          active~,
          depth=depth + 1,
        ),
        right.resolve_names(
          sheets,
          sheet,
          origin,
          work,
          active~,
          depth=depth + 1,
        ),
      )
    Function(name, args) =>
      Function(
        name,
        args.map(arg => {
          arg.resolve_names(
            sheets,
            sheet,
            origin,
            work,
            active~,
            depth=depth + 1,
          )
        }),
      )
  }
}
