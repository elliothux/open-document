///|
pub(all) struct CopiedCell {
  value : Value
  formula : String?
  format : CellFormat
}

///|
pub(all) struct CopiedCells {
  top : Int
  left : Int
  date1904 : Bool
  cells : Array[Array[CopiedCell]]
  merges : Array[Range]
  conditional : Array[CopiedConditional]
  validations : Array[CopiedValidation]
  hyperlinks : Array[CopiedHyperlink]
  notes : CopiedNotes?
}

///|
fn CellStyle::copied_format(self : CellStyle) -> CellFormat {
  let parts = self.font.split("|").map(part => part.to_owned()).to_array()
  CellFormat::new(
    family=Some(parts[0]),
    size=Some(self.size),
    bold=Some(parts.contains("bold")),
    italic=Some(parts.contains("italic")),
    underline=Some(self.underline),
    strike=Some(self.strike),
    script=Some(self.script),
    color=Some(self.color),
    fill=Some(self.fill),
    horizontal=Some(self.horizontal),
    vertical=Some(self.vertical),
    wrap=Some(self.wrap),
    numberFormat=Some(self.format),
    left=Some(self.borders[0]),
    right=Some(self.borders[1]),
    top=Some(self.borders[2]),
    bottom=Some(self.borders[3]),
  )
}

///|
pub impl ToJson for CopiedCells with fn to_json(self) {
  {
    "top": self.top,
    "left": self.left,
    "date1904": self.date1904,
    "cells": self.cells.map(row => {
      row.map(cell => {
        "value": Json(cell.value),
        "formula": if cell.formula is Some(formula) {
          Json(formula)
        } else {
          Json::null()
        },
        "format": Json::object(
          cell.format.applied(default_style()).format_values(),
        ),
      })
    }),
    "merges": self.merges,
    "conditional": self.conditional.map(rule => {
      "ranges": Json(rule.ranges),
      "anchor": { "row": rule.anchor.row, "column": rule.anchor.column },
      "settings": rule.settings.json(),
    }),
    "validations": self.validations.map(rule => {
      "ranges": Json(rule.ranges),
      "anchor": { "row": rule.anchor.row, "column": rule.anchor.column },
      "settings": Json(rule.settings),
    }),
    "hyperlinks": self.hyperlinks.map(link => {
      "range": Json(link.range),
      "target": Json(link.target),
      "display": link.display.map(Json::string).unwrap_or(Json::null()),
      "tooltip": link.tooltip.map(Json::string).unwrap_or(Json::null()),
    }),
    "notes": self.notes
    .map(notes => {
      let value : Json = {
        "comments": notes.comments,
        "vml": notes.vml.map(Json::string).unwrap_or(Json::null()),
      }
      value
    })
    .unwrap_or(Json::null()),
  }
}

///|
pub extend CopiedCells with ToJson::{to_json}

///|
fn CopiedCells::validate(self : CopiedCells) -> Unit raise @failure.Failure {
  guard !self.cells.is_empty() &&
    !self.cells[0].is_empty() &&
    self.cells.length().to_int64() * self.cells[0].length().to_int64() <= 4096 &&
    self.cells.all(row => row.length() == self.cells[0].length()) &&
    self.top >= 1 &&
    self.left >= 1 &&
    self.top.to_int64() + self.cells.length().to_int64() - 1 <= 1048576 &&
    self.left.to_int64() + self.cells[0].length().to_int64() - 1 <= 16384 else {
    @failure.reject("invalid-operation", "Expected a bounded cell fragment")
  }
  check_format_merges(self.merges, self.cells.length(), self.cells[0].length())
  self.check_copied_rules()
  self.check_copied_hyperlinks()
  self.check_copied_notes()
  let mut units = 0L
  for row in self.cells {
    for cell in row {
      cell.format.complete()
      let text = cell.value.display()
      guard text.length() <= 32767 && @xml.valid_text(text) else {
        @failure.reject("invalid-operation", "Invalid copied cell value")
      }
      if cell.value is Number(value) {
        guard !value.is_nan() && !value.is_inf() else {
          @failure.reject(
            "invalid-operation", "Copied cell numbers must be finite",
          )
        }
      }
      if cell.value is Error(value) {
        guard [
          "#NULL!", "#DIV/0!", "#VALUE!", "#REF!", "#NAME?", "#NUM!", "#N/A",
        ].contains(value) else {
          @failure.reject("invalid-operation", "Unknown copied cell error")
        }
      }
      if cell.formula is Some(formula) {
        guard !formula.is_empty() && formula.length() <= 8192 else {
          @failure.reject("limit-exceeded", "Copied formula exceeds budget")
        }
        ignore(parse_formula(formula))
      }
      units += text.length().to_int64() +
        cell.formula.map(value => value.length().to_int64()).unwrap_or(0L)
      guard units <= 1048576 else {
        @failure.reject("limit-exceeded", "Copied cell text exceeds budget")
      }
    }
  }
}

///|
/// Captures a bounded logical rectangle, independent of later source edits.
pub fn Session::capture_cells(
  self : Session,
  revision : Int,
) -> CopiedCells raise @failure.Failure {
  self.check_revision(revision)
  let (id, selected) = self.selection
  let index = self.sheet_index(id)
  let sheet = self.sheets[index]
  let range = sheet.merge_target(selected)
  let reason = self.format_reason(sheet, range)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  self.check_fill_resources(sheet, range, hyperlinks=true, rules=true)
  check_merge_markup(Tree::new(sheet.document))
  let calculation = self.calculation.unwrap()
  let rows : Array[Array[CopiedCell]] = []
  for row in range.top..<=range.bottom {
    let cells : Array[CopiedCell] = []
    for column in range.left..<=range.right {
      let address : Address = { row, column, }
      let key = address.name()
      let cell = sheet.cells.get(key)
      cells.push({
        value: calculation.values
        .get((index, key))
        .unwrap_or(cell.map(cell => cell.value).unwrap_or(Blank)),
        formula: cell.bind(cell => cell.formula),
        format: self.styles[sheet.style_at(address)].copied_format(),
      })
    }
    rows.push(cells)
  }
  let (conditional, validations) = self.capture_cell_rules(sheet, index, range)
  let fragment : CopiedCells = {
    top: range.top,
    left: range.left,
    date1904: self.date1904,
    cells: rows,
    conditional,
    validations,
    hyperlinks: self.capture_hyperlinks(sheet, range),
    notes: self.capture_notes(sheet, range),
    merges: sheet.merges
    .filter(merge => range.covers(merge))
    .map(merge => {
      top: merge.top - range.top + 1,
      left: merge.left - range.left + 1,
      bottom: merge.bottom - range.top + 1,
      right: merge.right - range.left + 1,
    }),
  }
  fragment.validate()
  fragment
}

///|
/// Pastes values, formulas and formats as one source/history transaction.
pub fn Session::paste_cells(
  self : Session,
  revision : Int,
  copied : CopiedCells,
  mode : String,
  transpose~ : Bool = false,
  accept_warnings~ : Bool = false,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  guard ["all", "values", "formulas", "format"].contains(mode) else {
    @failure.reject("invalid-operation", "Unknown cell paste mode")
  }
  copied.validate()
  let index = self.sheet_index(self.selection.0)
  let sheet = self.sheets[index]
  let rows = if transpose {
    copied.cells[0].length()
  } else {
    copied.cells.length()
  }
  let columns = if transpose {
    copied.cells.length()
  } else {
    copied.cells[0].length()
  }
  let target : Range = {
    ..self.selection.1,
    bottom: self.selection.1.top + rows - 1,
    right: self.selection.1.left + columns - 1,
  }
  guard target.bottom <= 1048576 && target.right <= 16384 else {
    @failure.reject("invalid-address", "Copied cells leave the worksheet")
  }
  let reason = self.format_reason(sheet, target)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  self.check_fill_resources(sheet, target, hyperlinks=true, rules=true)
  let format = mode == "all" || mode == "format"
  let merges = if format {
    sheet.format_merges(
      target,
      copied.merges.map(merge => {
        if transpose {
          {
            top: merge.left,
            left: merge.top,
            bottom: merge.right,
            right: merge.bottom,
          }
        } else {
          merge
        }
      }),
      rows,
      columns,
    )
  } else {
    guard !sheet.merges.any(merge => merge.intersects(target)) else {
      @failure.reject(
        "protected-content", "Value-only paste requires unmerged targets",
      )
    }
    sheet.merges
  }
  let updates : Map[String, CellContent] = Map([])
  let originals : Map[String, (Int, Int)] = Map([])
  let patches : Array[CellFormat] = []
  let pool : Map[CellFormat, Int] = Map([])
  for r in 0..<rows {
    for c in 0..<columns {
      let cell = copied.cells[if transpose { c } else { r }][if transpose {
          r
        } else {
          c
        }]
      let address : Address = { row: target.top + r, column: target.left + c, }
      let key = address.name()
      let old = sheet.cells.get(key)
      let formula = if mode == "values" {
        None
      } else {
        cell.formula.map(formula => {
          let expression = parse_formula(formula)
          let expression = if transpose {
            expression.transpose(copied.top, copied.left)
          } else {
            expression
          }
          expression.source(
            rows=target.top - copied.top,
            columns=target.left - copied.left,
            invalid_ref=true,
          )
        })
      }
      let value = if mode != "format" && formula is None {
        cell.calendar_value(copied.date1904, self.date1904)
      } else {
        cell.value
      }
      let changed = if mode == "format" {
        { value: Blank, formula: None, keep_shared: true, }
      } else {
        {
          value: if formula is Some(_) {
            Blank
          } else {
            value
          },
          formula,
          keep_shared: false,
        }
      }
      let patch = if transpose { cell.format.transposed() } else { cell.format }
      let mut restyle = false
      if format &&
        patch.applied(self.styles[sheet.style_at(address)]) !=
        self.styles[sheet.style_at(address)] {
        let patch_id = pool
          .get(patch)
          .unwrap_or_else(() => {
            let id = patches.length()
            patches.push(patch)
            pool[patch] = id
            id
          })
        originals[key] = (sheet.style_at(address), patch_id)
        restyle = true
      }
      if restyle ||
        (
          mode != "format" &&
          (
            old.bind(cell => cell.formula) != formula ||
            (
              formula is None &&
              old.map(cell => cell.value).unwrap_or(Blank) != value
            )
          )
        ) {
        updates[key] = changed
      }
    }
  }
  let rules = mode == "all" || mode == "format"
  let (conditional, validations) = if rules {
    {
      ..copied,
      validations: if mode == "all" {
        copied.validations
      } else {
        []
      },
    }.rules_at(target, transpose, self.date1904)
  } else {
    ([], [])
  }
  let change_rules = rules &&
    (
      !conditional.is_empty() ||
      (mode == "all" && !validations.is_empty()) ||
      sheet.has_clipboard_rules(target, mode == "all")
    )
  let change_links = mode == "all" &&
    copied.hyperlinks.map(link => {
      (
        copied.rule_range(link.range, target, transpose),
        link.target,
        link.display,
        link.tooltip,
      )
    }) !=
    self
    .capture_hyperlinks(sheet, target)
    .map(link => (link.range, link.target, link.display, link.tooltip))
  let change_notes = mode == "all" &&
    (copied.notes is Some(_) || self.capture_notes(sheet, target) is Some(_))
  if updates.is_empty() &&
    merges == sheet.merges &&
    !change_rules &&
    !change_links &&
    !change_notes {
    return self.select(revision, sheet.id, target.name())
  }
  let formatting = if originals.is_empty() {
    None
  } else {
    Some(self.derive_formats(originals, patches))
  }
  let (formatting, rule_indices) = if rules {
    self.copied_rule_styles(
      formatting,
      conditional.map(rule => rule.settings.format),
    )
  } else {
    (formatting, [])
  }
  let styles = formatting.map(plan => plan.indices).unwrap_or(Map([]))
  let plan = self.prepare_cells(
    Map([(index, updates)]),
    styles=Map([(index, styles)]),
    merges=Map([(index, merges)]),
    formatting~,
    accept_warnings~,
    preserve_values=mode == "format",
    validate_values=mode == "values" || mode == "formulas",
  )
  if rules {
    self.prepare_copied_rules(
      plan,
      index,
      target,
      conditional,
      if mode == "all" {
        validations
      } else {
        []
      },
      rule_indices,
      mode == "all",
    )
  }
  if mode == "all" {
    if change_links {
      self.prepare_copied_hyperlinks(plan, index, target, copied, transpose)
    }
    if change_notes {
      self.prepare_copied_notes(plan, index, target, copied, transpose)
    }
    let addresses = []
    for row in target.top..<=target.bottom {
      for column in target.left..<=target.right {
        addresses.push(Address::{ row, column, }.name())
      }
    }
    self.validate_inputs(
      plan.sheets,
      plan.calculation,
      Map([(index, addresses)]),
      accept_warnings,
    )
  }
  if plan.edits.is_empty() && plan.created_parts.is_empty() {
    return self.select(revision, sheet.id, target.name())
  }
  self.commit(
    plan.sheets,
    self.workbook,
    plan.calculation,
    plan.edits,
    (sheet.id, target),
    parts=plan.parts,
    created_parts=plan.created_parts,
  )
  self.query()
}
