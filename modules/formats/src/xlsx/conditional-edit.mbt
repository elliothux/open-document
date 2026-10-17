///|
fn conditional_insertion(
  tree : Tree,
  markup : String,
) -> @xml.SourceChange raise @failure.Failure {
  let root = tree.root("worksheet")
  let next = tree.children
    .get(root.id)
    .unwrap_or([])
    .iter()
    .find_first(n => {
      [
        "dataValidations", "hyperlinks", "printOptions", "pageMargins", "pageSetup",
        "headerFooter", "rowBreaks", "colBreaks", "customProperties", "cellWatches",
        "ignoredErrors", "smartTags", "drawing", "legacyDrawing", "legacyDrawingHF",
        "picture", "oleObjects", "controls", "webPublishItems", "tableParts", "extLst",
      ].contains(n.name)
    })
  if next is Some(next) {
    { node: root.id, offset: next.start - root.start, length: 0, xml: markup, }
  } else {
    insertion(root, markup)
  }
}

///|
fn Session::commit_conditional(
  self : Session,
  index : Int,
  changes : Array[@xml.SourceChange],
  plan : ConditionalStyleEdit,
) -> Json raise @failure.Failure {
  if changes.is_empty() {
    return self.query()
  }
  let sheet = self.sheets[index]
  let (document, edit) = sheet.document.edit_source(join_insertions(changes))
  let sheets = self.sheets.copy()
  sheets[index] = Sheet::read(
    sheet.id,
    sheet.name,
    sheet.state,
    document,
    self.strings,
    self.styles.length(),
  )
  if self.font_context is Some((probe, profile)) &&
    self.grid is Some(grid) &&
    grid.sheet == sheet.id &&
    grid.result is { "cells": Array(visible), .. } {
    let work : FormulaWork = {
      remaining: 1048576,
      date1904: self.date1904,
      origin: { row: 1, column: 1, },
      names: self.formula_names(),
    }
    let conditional = self.conditional_rules(
      sheets[index],
      index,
      sheets,
      work,
      parts=plan.parts,
    )
    for item in visible {
      if item is { "cell": { "address": String(name), .. }, .. } {
        let address = Address::parse(name)
        let value = calculated_cell(
          sheets,
          self.calculation.unwrap().values,
          index,
          address,
        )
        if value == Blank || value == Text("") {
          continue
        }
        let style = conditional.applied(
          self.styles[sheets[index].style_at(address)],
          address,
          sheets,
          index,
          self.calculation.unwrap().values,
          work,
        )
        let identity = profile
          .get(style.font)
          .unwrap_or_error(
            @failure.Failure(
              code="missing-font",
              part="",
              offset=-1,
              message="Missing font profile mapping: " + style.font,
            ),
          )
        ignore(probe.font_index(identity))
      }
    }
  }
  plan.edits.push((sheet.id, edit))
  let anchor = self.anchor
  let focus = self.focus
  self.commit(
    sheets,
    self.workbook,
    self.calculation.unwrap(),
    plan.edits,
    self.selection,
    parts=plan.parts,
    created_parts=plan.created_parts,
  )
  self.anchor = anchor
  self.focus = focus
  self.query()
}

///|
fn Session::set_conditional(
  self : Session,
  id : String,
  source : String,
  priority : Int?,
  settings : ConditionalFormat?,
  source_revision : Int,
) -> Json raise @failure.Failure {
  if priority is Some(_) {
    self.check_revision(source_revision)
  }
  let index = self.sheet_index(id)
  let sheet = self.sheets[index]
  let reason = self.dimension_reason(sheet)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: 1, column: 1, },
    names: self.formula_names(),
  }
  let conditional = self.conditional_rules(sheet, index, self.sheets, work)
  guard conditional.reason.is_empty() else {
    @failure.reject("protected-content", conditional.reason)
  }
  let tree = Tree::new(sheet.document)
  let target = priority.map(priority => {
    conditional.rules
    .iter()
    .find_first(rule => rule.priority == priority)
    .unwrap_or_error(
      @failure.Failure(
        code="invalid-operation",
        part=id,
        offset=-1,
        message="Conditional rule no longer exists",
      ),
    )
  })
  let changes = []
  if target is Some(target) {
    let container = tree.nodes[target.container]
    let reason = conditional_edit_reason(tree, container)
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    if tree.all(container.id, "cfRule").length() == 1 {
      changes.push(sheet_node_removal(tree, container))
    } else {
      changes.push(sheet_node_removal(tree, tree.nodes[target.node]))
    }
  }
  let plan = if settings is Some(settings) {
    guard source.length() <= 262144 else {
      @failure.reject(
        "limit-exceeded", "Conditional ranges exceed source budget",
      )
    }
    let ranges = clear_rule_ranges(source)
    settings.check(ranges, self.sheets, index, work)
    if target is Some(target) &&
      target.ranges == ranges &&
      target.settings().json() == settings.json() {
      return self.query()
    }
    let priority = target
      .map(t => t.priority)
      .unwrap_or_else(() => {
        guard conditional.rules.length() < 4096 else {
          @failure.reject("limit-exceeded", "Conditional rules exceed 4096")
        }
        let last = conditional.rules.last().map(r => r.priority).unwrap_or(0)
        guard last < 2147483647 else {
          @failure.reject("limit-exceeded", "Conditional priority exhausted")
        }
        last + 1
      })
    let plan = if target is Some(target) &&
      target.style.patch_json() == settings.format.patch_json() {
      // Keep unchanged theme/indexed colors and shared differential source identities.
      {
        indices: [
          tree.nodes[target.node]
          .attribute("dxfId")
          .map(raw => natural(raw, 4095)),
        ],
        parts: self.parts.copy(),
        edits: [],
        created_parts: Map([]),
      }
    } else {
      self.derive_conditional_styles([settings.format])
    }
    let colors : Array[String?] = if settings.kind == "colorScale" &&
      target is Some(target) &&
      target.kind == "colorScale" {
      let scale = tree.one(target.node, "colorScale").unwrap()
      let palette = tree.all(scale.id, "color")
      settings.stops.mapi((i, stop) => {
        if target.stops.get(i) is Some(before) &&
          before.color.to_lower() == stop.color.to_lower() {
          Some(style_markup(tree, palette[i]))
        } else {
          None
        }
      })
    } else if settings.kind == "dataBar" &&
      target is Some(target) &&
      target.bar is Some(before) &&
      settings.bar is Some(after) &&
      before.color.to_lower() == after.color.to_lower() {
      [
        Some(
          style_markup(
            tree,
            tree
            .one(tree.one(target.node, "dataBar").unwrap().id, "color")
            .unwrap(),
          ),
        ),
      ]
    } else {
      []
    }
    let rule_markup = if target is Some(target) &&
      target.settings().json() == settings.json() {
      style_markup(tree, tree.nodes[target.node])
    } else {
      settings.markup(priority, plan.indices[0], colors~)
    }
    let markup = "<od:conditionalFormatting xmlns:od=\"\{spreadsheet_uri}\" sqref=\"\{ranges.map(Range::name).join(" ")}\">\{rule_markup}</od:conditionalFormatting>"
    changes.push(conditional_insertion(tree, markup))
    plan
  } else {
    if priority is None {
      let cut = Range::parse(source)
      for
        container in tree.all(
          tree.root("worksheet").id,
          "conditionalFormatting",
        ) {
        if !clear_rule_ranges(container.attribute("sqref").unwrap_or("")).any(r => {
            r.intersects(cut)
          }) {
          continue
        }
        let reason = conditional_edit_reason(tree, container)
        guard reason.is_empty() else {
          @failure.reject("protected-content", reason)
        }
        let (remove, edits) = clear_rule_changes(tree, container, cut)
        if remove {
          changes.push(sheet_node_removal(tree, container))
        } else {
          changes.append(edits)
        }
      }
    }
    {
      indices: [],
      parts: self.parts.copy(),
      edits: [],
      created_parts: Map([]),
    }
  }
  self.commit_conditional(index, changes, plan)
}

///|
fn Session::move_conditional(
  self : Session,
  id : String,
  priority : Int,
  position : Int,
  source_revision : Int,
) -> Json raise @failure.Failure {
  self.check_revision(source_revision)
  let index = self.sheet_index(id)
  let sheet = self.sheets[index]
  let reason = self.dimension_reason(sheet)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let work : FormulaWork = {
    remaining: 1048576,
    date1904: self.date1904,
    origin: { row: 1, column: 1, },
    names: self.formula_names(),
  }
  let conditional = self.conditional_rules(sheet, index, self.sheets, work)
  guard conditional.reason.is_empty() else {
    @failure.reject("protected-content", conditional.reason)
  }
  let rules = conditional.rules.copy()
  let mut before = -1
  for ordinal, rule in rules {
    if rule.priority == priority {
      before = ordinal
      break
    }
  }
  guard before >= 0 else {
    @failure.reject(
      "invalid-operation",
      "Conditional rule no longer exists",
      part=id,
    )
  }
  guard position >= 0 && position < rules.length() else {
    @failure.reject(
      "invalid-operation", "Invalid conditional priority position",
    )
  }
  if before == position {
    return self.query()
  }
  let rule = rules.remove(before)
  rules.insert(position, rule)
  let tree = Tree::new(sheet.document)
  let changes = []
  for ordinal, rule in rules {
    changes.append(
      metadata_changes(tree.nodes[rule.node], [
        ("priority", (ordinal + 1).to_string()),
      ]),
    )
  }
  self.commit_conditional(index, changes, {
    indices: [],
    parts: self.parts.copy(),
    edits: [],
    created_parts: Map([]),
  })
}
