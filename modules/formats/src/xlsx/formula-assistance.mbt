///|
#derive(ToJson)
priv struct FormulaCompletion {
  start : Int32
  end : Int32
  appendParen : Bool
  functions : Array[FormulaSignature]
}

///|
#derive(ToJson)
priv struct FormulaCallHint {
  signature : FormulaSignature
  argument : Int32
}

///|
#derive(ToJson)
priv struct FormulaReferenceHint {
  label : String
  sheet : String
  range : Range
  rects : Array[@layout.Border]
}

///|
fn formula_call_hint(
  tokens : Array[Token],
  spans : Array[(Int32, Int32)],
  caret : Int32,
) -> FormulaCallHint? {
  let stack : Array[(String, Int32)] = []
  for index, token in tokens {
    if spans[index].1 > caret {
      break
    }
    match token {
      Operator("(") => {
        let name = match tokens.get(index - 1) {
          Some(Word(word)) => formula_function_name(word)
          _ => ""
        }
        stack.push((name, 0))
      }
      Operator(")") => ignore(stack.pop())
      Operator(",") if stack.last() is Some((name, argument)) =>
        stack[stack.length() - 1] = (name, argument + 1)
      _ => ()
    }
  }
  while stack.pop() is Some((name, argument)) {
    if formula_signatures.iter().find_first(item => item.name == name)
      is Some(signature) {
      return Some({ signature, argument, })
    }
  }
  None
}

///|
fn formula_completion(
  source : String,
  tokens : Array[Token],
  spans : Array[(Int32, Int32)],
  caret : Int32,
) -> FormulaCompletion? {
  for index, token in tokens {
    let (start, end) = spans[index]
    guard token is Word(word) && start < caret && caret <= end else { continue }
    if tokens.get(index - 1) is Some(Operator("!" | ":" | ")" | "%")) ||
      tokens.get(index + 1) is Some(Operator("!" | ":") | Brackets(_)) {
      return None
    }
    if !(tokens.get(index + 1) is Some(Operator("("))) &&
      (Some(formula_address(word)) catch { _ => None }) is Some(_) {
      return None
    }
    let prefix = source[start:caret].to_upper().to_owned()
    let matches = formula_signatures.filter(item => item.name.has_prefix(prefix))
    matches.sort_by((a, b) => {
      let length = a.name.length().compare(b.name.length())
      if length == 0 {
        a.name.compare(b.name)
      } else {
        length
      }
    })
    let functions = matches.iter().take(8).to_array()
    guard !functions.is_empty() else { return None }
    return Some({
      start: start + 1,
      end: end + 1,
      appendParen: !(tokens.get(index + 1) is Some(Operator("("))),
      functions,
    })
  }
  None
}

///|
fn Session::formula_references(
  self : Session,
  current : Int32,
  source : String,
  tokens : Array[Token],
  spans : Array[(Int32, Int32)],
  grid : Grid?,
) -> Array[FormulaReferenceHint] {
  let references : Array[FormulaReferenceHint] = []
  let parser : FormulaParser = { tokens, cursor: 0, }
  let mut index = 0
  while index + 1 < tokens.length() && references.length() < 24 {
    let start = index
    index += 1
    let token = tokens[start]
    let next = tokens[index]
    if tokens.get(start - 1) is Some(Operator("!" | ":")) ||
      next is Operator("(") ||
      next is Brackets(_) {
      continue
    }
    let target = match (token, next) {
      (Word(sheet) | Quoted(sheet, true), Operator("!")) => Some(sheet)
      _ => None
    }
    let start_ref = if target is Some(_) { start + 2 } else { start }
    parser.cursor = start_ref
    let expression = try {
      let text = parser.reference_token()
      if !(tokens[start_ref] is Numeric(_, _)) ||
        tokens[parser.cursor] is Operator(":") {
        Some(parser.reference(target, text))
      } else {
        None
      }
    } catch {
      _ => None
    }
    if expression is Some(Reference(target, first, last)) {
      let range = first.range(last.unwrap_or(first))
      let sheet = Some(referenced_sheet(self.sheets, current, target)) catch {
        _ => None
      }
      if sheet is Some(sheet) {
        let target = self.sheets[sheet]
        let rects = match grid {
          Some(grid) if grid.sheet == target.id =>
            grid.range_geometry(range, target.frozen).rects
          _ => []
        }
        references.push({
          label: source[spans[start].0:spans[parser.cursor - 1].1].to_owned(),
          sheet: target.id,
          range,
          rects,
        })
      }
    }
    index = index.max(parser.cursor)
  }
  references
}

///|
/// Describe an unfinished formula at a UTF-16 caret and optionally project its references onto a live viewport.
pub fn Session::formula_assistance(
  self : Session,
  revision : Int32,
  sheet : String,
  source : String,
  caret : Int32,
  layout? : Int32,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  let current = self.sheet_index(sheet)
  guard caret >= 0 &&
    caret <= source.length() &&
    source.length() <= FormulaSourceUnits + 1 else {
    @failure.reject(
      "invalid-operation", "Formula caret or source exceeds bounds",
    )
  }
  let grid = match layout {
    None => None
    Some(id) => {
      guard self.grid is Some(grid) &&
        grid.id == id &&
        grid.sheet == sheet &&
        grid.revision == revision else {
        @failure.reject(
          "stale-layout", "Formula references require current grid geometry",
        )
      }
      Some(grid)
    }
  }
  let spans : Array[(Int32, Int32)] = []
  let mut complete = true
  let formula = if source.has_prefix("=") && caret > 0 {
    source[1:].to_owned()
  } else {
    ""
  }
  let tokens = formula_tokens(formula, spans~) catch {
    _ => {
      complete = false
      let end = spans.last().map(span => span.1).unwrap_or(0)
      spans.clear()
      formula_tokens(formula[:end].to_owned(), spans~)
    }
  }
  let completion = if complete {
    formula_completion(formula, tokens, spans, caret - 1)
  } else {
    None
  }
  {
    "completion": completion.map(item => Json(item)).unwrap_or(Json::null()),
    "call": formula_call_hint(tokens, spans, caret - 1)
    .map(item => Json(item))
    .unwrap_or(Json::null()),
    "references": Json(
      self.formula_references(current, formula, tokens, spans, grid),
    ),
  }
}
