///|
priv struct Dependency {
  sheet : Int
  range : Range
}

///|
priv struct FormulaWork {
  mut remaining : Int
  date1904 : Bool
  mut origin : Address
  names : NamedDefinitions
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
  names : NamedDefinitions
  sources : Map[(Int, String), String]
  expressions : Map[(Int, String), Expression]
  dependencies : Map[(Int, String), Array[Dependency]]
  values : Map[(Int, String), Value]
  hyperlinks : Map[(Int, String), String?]
  order : Array[(Int, String)]
  uncomputed : Map[(Int, String), String]
  guarded_ranges : Map[Int, Array[Range]]
  mut protected_visibility : Bool
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
  hyperlink~ : Ref[Bool]? = None,
  uncomputed~ : Ref[String?]? = None,
) -> Unit raise @failure.Failure {
  work.spend()
  guard depth <= 64 && output.length() < 4096 else {
    @failure.reject(
      "limit-exceeded", "Formula reference or expression depth exceeded",
    )
  }
  match self {
    Named(_, _) | Structured(_, _) =>
      self
      .resolve_names(sheets, current, work.origin, work)
      .dependencies(
        sheets,
        current,
        work,
        output,
        depth + 1,
        hyperlink~,
        uncomputed~,
      )
    Constant(_) => ()
    Reference(name, first, last) => {
      let last = last.unwrap_or(first)
      output.push({
        sheet: referenced_sheet(sheets, current, name),
        range: first.range(last),
      })
    }
    Unary(_, value) =>
      value.dependencies(
        sheets,
        current,
        work,
        output,
        depth + 1,
        hyperlink~,
        uncomputed~,
      )
    Binary(_, left, right) => {
      left.dependencies(
        sheets,
        current,
        work,
        output,
        depth + 1,
        hyperlink~,
        uncomputed~,
      )
      right.dependencies(
        sheets,
        current,
        work,
        output,
        depth + 1,
        hyperlink~,
        uncomputed~,
      )
    }
    Function(name, args) => {
      if name == "HYPERLINK" && hyperlink is Some(hyperlink) {
        hyperlink.val = true
      }
      if ![
          "SUM", "AVERAGE", "MIN", "MAX", "COUNT", "IF", "AND", "OR", "NOT", "IFERROR",
          "IFNA", "ISBLANK", "ISNUMBER", "ISTEXT", "ABS", "INT", "MOD", "ROUND",
          "ROUNDUP", "ROUNDDOWN", "LEN", "LEFT", "RIGHT", "MID", "TRIM", "UPPER",
          "LOWER", "CONCAT", "CONCATENATE", "TEXTJOIN", "FIND", "SEARCH", "SUBSTITUTE",
          "EXACT", "REPT", "TEXT", "DATE", "YEAR", "MONTH", "DAY", "TIME", "HOUR",
          "MINUTE", "SECOND", "DAYS", "COUNTA", "COUNTBLANK", "COUNTIF", "COUNTIFS",
          "SUMIF", "SUMIFS", "AVERAGEIF", "AVERAGEIFS", "MINIFS", "MAXIFS", "INDEX",
          "MATCH", "VLOOKUP", "HLOOKUP", "XLOOKUP", "ROW", "COLUMN", "ROWS", "COLUMNS",
          "SUBTOTAL", "SQRT", "POWER", "PRODUCT", "MEDIAN", "SUMSQ", "DEVSQ", "VAR",
          "VAR.S", "PI", "SIN", "COS", "TAN", "RADIANS", "DEGREES", "VARP", "VAR.P",
          "STDEV", "STDEV.S", "STDEVP", "STDEV.P", "MODE", "MODE.SNGL", "LARGE",
          "SMALL", "SUMPRODUCT", "HYPERLINK", "ACOS", "ASIN", "ATAN", "ATAN2", "EXP",
          "LN", "LOG", "LOG10", "SINH", "COSH", "TANH", "ACOSH", "ASINH",
        ].contains(name) {
        guard uncomputed is Some(reason) && isolated_math_function(name) else {
          @failure.reject(
            "unsupported-formula",
            "Unsupported function: " + name,
          )
        }
        reason.val = Some("Unsupported function: " + name)
      }
      for index, arg in args {
        if ["ROW", "COLUMN", "ROWS", "COLUMNS"].contains(name) &&
          arg is Reference(_, _, _) {
          ignore(arg.aggregate_range(sheets, current))
          continue
        }
        if index == 2 &&
          (name == "SUMIF" || name == "AVERAGEIF") &&
          args[0].aggregate_range(sheets, current) is Some(base) &&
          arg.aggregate_range(sheets, current) is Some(target) &&
          target.fit(base.bounds) is Some(target) {
          guard output.length() < 4096 else {
            @failure.reject(
              "limit-exceeded", "Formula reference budget exceeded",
            )
          }
          work.spend()
          output.push({ sheet: target.sheet, range: target.bounds, })
          continue
        }
        arg.dependencies(
          sheets,
          current,
          work,
          output,
          depth + 1,
          hyperlink~,
          uncomputed~,
        )
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
        if self.uncomputed.contains(candidate) && !self.uncomputed.contains(key) {
          self.uncomputed[key] = "Uncalculated dependency: " + candidate.1
        }
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
  date1904 : Bool,
  workbook : @xml.Document,
  tables~ : Array[StructuredTable],
) -> Calculation raise @failure.Failure {
  let definitions = read_named_definitions(workbook, sheets.length())
  for table in tables {
    guard !table.filtering || table.filter is Some(_) else {
      @failure.reject(
        "unsupported-formula", "Table filtering requires calculation support",
      )
    }
    guard !definitions.sources.contains((-1, table.name.to_upper())) else {
      @failure.reject(
        "malformed-xlsx", "Table name conflicts with a workbook defined name",
      )
    }
  }
  let names = { ..definitions, tables, }
  let previous = if previous is Some(previous) && previous.names.same(names) {
    Some(previous)
  } else {
    None
  }
  let calculation : Calculation = {
    names,
    sources: Map([]),
    expressions: Map([]),
    dependencies: Map([]),
    values: Map([]),
    hyperlinks: Map([]),
    order: [],
    uncomputed: Map([]),
    guarded_ranges: Map([]),
    protected_visibility: false,
  }
  let work = FormulaWork::{
    remaining: 1048576,
    date1904,
    names,
    origin: { row: 1, column: 1, },
  }
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
          parse_formula(source).resolve_names(sheets, index, cell.address, work)
        }
        tokens += source.length()
        guard tokens <= 1048576 else {
          @failure.reject(
            "limit-exceeded", "Workbook formula source budget exceeded",
          )
        }
        let dependencies : Array[Dependency] = []
        let hyperlink = Ref(false)
        let uncomputed : Ref[String?] = Ref(None)
        expression.dependencies(
          sheets,
          index,
          work,
          dependencies,
          0,
          hyperlink=Some(hyperlink),
          uncomputed=Some(uncomputed),
        )
        if uncomputed.val is Some(reason) {
          calculation.uncomputed[key] = reason
        }
        if hyperlink.val {
          calculation.hyperlinks[key] = None
        }
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
  calculation.protect_dependencies(formulas, work)
  let invalid = changed.copy()
  let mut link_units = 0
  for key in calculation.order {
    work.origin = Address::parse(key.1)
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
    let hyperlink : Ref[String?] = Ref(None)
    if calculation.uncomputed.get(key) is Some(reason) {
      guard !affected &&
        (
          previous is None ||
          previous.bind(p => p.sources.get(key)) == calculation.sources.get(key)
        ) else {
        @failure.reject("unsupported-formula", reason)
      }
      continue
    }
    let value = if previous is Some(previous) &&
      !affected &&
      previous.sources.get(key) == calculation.sources.get(key) &&
      previous.values.get(key) is Some(value) {
      hyperlink.val = previous.hyperlinks.get(key).bind(value => value)
      value
    } else {
      calculation.expressions[key].evaluate(
        sheets,
        key.0,
        calculation.values,
        work,
        0,
        hyperlink=Some(hyperlink),
      )
    }
    calculation.values[key] = formula_result(value)
    if calculation.hyperlinks.contains(key) {
      let target = if value is Error(_) { None } else { hyperlink.val }
      link_units += target.map(t => t.length()).unwrap_or(0)
      guard link_units <= 1048576 else {
        @failure.reject(
          "limit-exceeded", "Formula hyperlink targets exceed the text budget",
        )
      }
      calculation.hyperlinks[key] = target
    }
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
