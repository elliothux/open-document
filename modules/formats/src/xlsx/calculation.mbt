///|
priv struct Dependency {
  sheet : Int
  range : Range
}

///|
priv struct FormulaWork {
  mut remaining : Int
}

///|
fn FormulaWork::spend(
  self : FormulaWork,
  amount~ : Int = 1,
) -> Unit raise @failure.Failure {
  guard amount >= 0 && self.remaining >= amount else {
    @failure.reject(
      "limit-exceeded", "Formula calculation work budget exceeded",
    )
  }
  self.remaining -= amount
}

///|
priv struct Calculation {
  sources : Map[(Int, String), String]
  expressions : Map[(Int, String), Expression]
  dependencies : Map[(Int, String), Array[Dependency]]
  values : Map[(Int, String), Value]
  order : Array[(Int, String)]
}

///|
fn referenced_sheet(
  sheets : Array[Sheet],
  current : Int,
  name : String?,
) -> Int raise @failure.Failure {
  guard name is Some(name) else { return current }
  for index, sheet in sheets {
    if sheet.name.to_lower() == name.to_lower() {
      return index
    }
  }
  @failure.reject("invalid-address", "Unknown worksheet in formula: " + name)
}

///|
fn Expression::dependencies(
  self : Expression,
  sheets : Array[Sheet],
  current : Int,
  work : FormulaWork,
  output : Array[Dependency],
  depth : Int,
) -> Unit raise @failure.Failure {
  work.spend()
  guard depth <= 64 && output.length() < 4096 else {
    @failure.reject(
      "limit-exceeded", "Formula reference or expression depth exceeded",
    )
  }
  match self {
    Constant(_) => ()
    Reference(name, first, last) => {
      let last = last.unwrap_or(first)
      output.push({
        sheet: referenced_sheet(sheets, current, name),
        range: first.range(last),
      })
    }
    Unary(_, value) =>
      value.dependencies(sheets, current, work, output, depth + 1)
    Binary(_, left, right) => {
      left.dependencies(sheets, current, work, output, depth + 1)
      right.dependencies(sheets, current, work, output, depth + 1)
    }
    Function(name, args) => {
      guard [
        "SUM", "AVERAGE", "MIN", "MAX", "COUNT", "IF", "AND", "OR", "NOT", "IFERROR",
        "IFNA", "ISBLANK", "ISNUMBER", "ISTEXT", "ABS", "INT", "MOD", "ROUND", "ROUNDUP",
        "ROUNDDOWN", "LEN", "LEFT", "RIGHT", "MID", "TRIM", "UPPER", "LOWER", "CONCAT",
        "CONCATENATE", "TEXTJOIN", "FIND", "SEARCH", "SUBSTITUTE",
      ].contains(name) else {
        @failure.reject("unsupported-formula", "Unsupported function: " + name)
      }
      for arg in args {
        arg.dependencies(sheets, current, work, output, depth + 1)
      }
    }
  }
}

///|
fn Calculation::visit(
  self : Calculation,
  key : (Int, String),
  formulas : Map[Int, Array[(Int, String)]],
  marks : Map[(Int, String), Int],
  work : FormulaWork,
  depth : Int,
) -> Unit raise @failure.Failure {
  work.spend()
  guard depth <= 256 else {
    @failure.reject("limit-exceeded", "Formula dependency depth exceeded")
  }
  match marks.get(key) {
    Some(2) => return
    Some(1) =>
      @failure.reject(
        "circular-reference", "Workbook contains a circular formula dependency",
      )
    _ => ()
  }
  marks[key] = 1
  for dependency in self.dependencies[key] {
    for candidate in formulas.get(dependency.sheet).unwrap_or([]) {
      work.spend()
      if dependency.range.contains(Address::parse(candidate.1)) {
        self.visit(candidate, formulas, marks, work, depth + 1)
      }
    }
  }
  marks[key] = 2
  self.order.push(key)
}

///|
fn Calculation::build(
  sheets : Array[Sheet],
  previous : Calculation?,
  changed : Array[(Int, Range)],
) -> Calculation raise @failure.Failure {
  let calculation : Calculation = {
    sources: Map([]),
    expressions: Map([]),
    dependencies: Map([]),
    values: Map([]),
    order: [],
  }
  let work = FormulaWork::{ remaining: 1048576, }
  let formulas : Map[Int, Array[(Int, String)]] = Map([])
  let mut references = 0
  let mut tokens = 0
  for index, sheet in sheets {
    for name, cell in sheet.cells {
      work.spend()
      if cell.formula is Some(source) {
        guard !cell.read_only.has_prefix("Unsupported formula") else {
          @failure.reject("unsupported-formula", cell.read_only)
        }
        let key = (index, name)
        let expression = if previous is Some(previous) &&
          previous.sources.get(key) == Some(source) {
          previous.expressions[key]
        } else {
          parse_formula(source)
        }
        tokens += source.length()
        guard tokens <= 1048576 else {
          @failure.reject(
            "limit-exceeded", "Workbook formula source budget exceeded",
          )
        }
        let dependencies : Array[Dependency] = []
        expression.dependencies(sheets, index, work, dependencies, 0)
        references += dependencies.length()
        guard references <= 32768 else {
          @failure.reject(
            "limit-exceeded", "Workbook formula reference budget exceeded",
          )
        }
        calculation.sources[key] = source
        calculation.expressions[key] = expression
        calculation.dependencies[key] = dependencies
        if formulas.get(index) is Some(items) {
          items.push(key)
        } else {
          formulas[index] = [key]
        }
      }
    }
  }
  let marks : Map[(Int, String), Int] = Map([])
  for key in calculation.sources.keys() {
    calculation.visit(key, formulas, marks, work, 0)
  }
  let invalid = changed.copy()
  for key in calculation.order {
    let affected = calculation.dependencies[key].any(dependency => {
        invalid.any(item => {
          work.spend()
          item.0 == dependency.sheet && item.1.intersects(dependency.range)
        })
      }) ||
      invalid.any(item => {
        work.spend()
        item.0 == key.0 && item.1.contains(Address::parse(key.1))
      })
    let value = if previous is Some(previous) &&
      !affected &&
      previous.sources.get(key) == calculation.sources.get(key) &&
      previous.values.get(key) is Some(value) {
      value
    } else {
      calculation.expressions[key].evaluate(
        sheets,
        key.0,
        calculation.values,
        work,
        0,
      )
    }
    calculation.values[key] = formula_result(value)
    if affected {
      let address = Address::parse(key.1)
      invalid.push(
        (
          key.0,
          {
            top: address.row,
            left: address.column,
            bottom: address.row,
            right: address.column,
          },
        ),
      )
    }
  }
  calculation
}
