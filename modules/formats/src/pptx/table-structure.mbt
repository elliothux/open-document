///|
fn validate_table_template(source : Ref) -> Unit raise @failure.Failure {
  guard source.node.uri == drawing_uri &&
    source.node.name != "extLst" &&
    !["hlinkClick", "hlinkMouseOver"].contains(source.node.name) &&
    source.node.attributes.all(a => a.uri.is_empty() && a.name != "id") else {
    @failure.reject(
      "protected-content", "Table insertion template contains identity extensions or links",
    )
  }
  for node in source.tree.children.get(source.node.id).unwrap_or([]) {
    validate_table_template({ tree: source.tree, node, })
  }
}

///|
fn blank_table_content(cell : DrawingCell) -> String raise @failure.Failure {
  let paragraph = cell.paragraphs[0]
  let body = cell.source.child("txBody").unwrap()
  let properties = [
    body.child("bodyPr"),
    body.child("lstStyle"),
    paragraph.source.child("pPr"),
    paragraph.source.child("endParaRPr"),
    cell.source.child("tcPr"),
  ]
  for
    source in [
      ..properties,
      paragraph.runs[0].source.bind(run => run.child("rPr")),
    ] {
    if source is Some(source) {
      validate_table_template(source)
    }
  }
  let fragments = properties.map(source => {
    source
    .map(item => item.tree.standalone_markup(item.tree.document, item.node.id))
    .unwrap_or("")
  })
  let format = replacement_properties(paragraph, 0)
  guard fragments.fold(init=format.length(), (sum, text) => sum + text.length()) <=
    2096000 else {
    @failure.reject(
      "limit-exceeded", "Table cell template exceeds history budget",
    )
  }
  "<a:txBody>\{fragments[0]}\{fragments[1]}<a:p>\{fragments[2]}<a:r>\{format}<a:t/></a:r>\{fragments[3]}</a:p></a:txBody>\{fragments[4]}"
}

///|
fn blank_table_cell(cell : DrawingCell) -> String raise @failure.Failure {
  "<a:tc xmlns:a=\"\{drawing_uri}\">\{blank_table_content(cell)}</a:tc>"
}

///|
fn table_source_change(
  source : Ref,
  xml : String,
  before~ : Bool? = None,
) -> @xml.SourceChange {
  let parent = source.tree.nodes[source.node.parent]
  {
    node: parent.id,
    offset: (if before == Some(false) {
      source.node.end
    } else {
      source.node.start
    }) -
    parent.start,
    length: if before is None {
      source.node.end - source.node.start
    } else {
      0
    },
    xml,
  }
}

///|
fn Session::prepare_table(
  self : Session,
  original : Slide,
  changes : Array[@xml.SourceChange],
  identity : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> (Slide, @xml.Edit) raise @failure.Failure {
  let (candidate, edit) = self.prepare(original, changes)
  let object = candidate.object(identity)
  guard object.table is Some(_) else {
    @failure.reject("protected-content", object.diagnostic)
  }
  let fit = object.table_fit_changes(probe, profile)
  if fit.is_empty() {
    return (candidate, edit)
  }
  let (document, _) = candidate.tree.document.edit_source(fit)
  let tree = Tree::new(original.tree.part, document)
  let markup = source_xml({ tree, node: tree.nodes[object.source.node.id], })
  let source = original.objects
    .iter()
    .find_first(object => object.id == identity)
  self.prepare(original, [
    if source is Some(source) {
      table_source_change(source.source, markup)
    } else {
      object_insertion(original.tree, markup)
    },
  ])
}

///|
fn Session::edit_table_structure(
  self : Session,
  operation : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  guard [
    "insertRowBefore", "insertRowAfter", "deleteRow", "insertColumnBefore", "insertColumnAfter",
    "deleteColumn", "merge", "unmerge",
  ].contains(operation) else {
    @failure.reject("invalid-operation", "Unknown table structure operation")
  }
  guard self.selection.objects.length() == 1 else {
    @failure.reject(
      "invalid-operation", "Select one table before changing its structure",
    )
  }
  let original = self.current()
  let object = original.object(self.selection.object)
  guard object.table is Some(table) else {
    @failure.reject("protected-content", "Select an editable table")
  }
  let (_, _, reason) = self.table_position(object, self.selection)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let range = table.range(self.selection)
  self.check_table_operation(object, range, operation)
  if operation == "merge" || operation == "unmerge" {
    return self.merge_table_cells(
      object,
      range,
      operation == "unmerge",
      probe,
      profile,
    )
  }
  let rows = operation.contains("Row")
  let insert = operation.has_prefix("insert")
  let before = operation.has_suffix("Before")
  let first = if rows { range.top } else { range.left }
  let last = if rows { range.bottom } else { range.right }
  let amount = last - first + 1
  let current_count = if rows {
    table.rows.length()
  } else {
    table.widths.length()
  }
  if !insert && current_count == amount {
    let reason = self.object_edit_reason(object, "delete")
    guard reason.is_empty() else {
      @failure.reject("protected-content", reason)
    }
    let (candidate, edit) = self.prepare(original, [
      table_source_change(object.source, ""),
    ])
    self.commit(
      candidate,
      edit,
      {
        ..self.selection,
        object: "",
        objects: [],
        mode: "object",
        anchor: 0,
        focus: 0,
      },
      probe~,
      profile~,
    )
    return self.query()
  }
  let count = current_count + (if insert { amount } else { -amount })
  let other = if rows { table.widths.length() } else { table.rows.length() }
  guard count <= (if rows { 1000 } else { 63 }) && count * other <= 4096 else {
    @failure.reject("limit-exceeded", "Table dimensions exceed budget")
  }
  let changes : Array[@xml.SourceChange] = []
  let at = if insert && !before { last + 1 } else { first.min(count - 1) }
  let target_row = if rows { at } else { range.top }
  let target_column = if rows { range.left } else { at }
  let mut extent = 0.0
  if rows {
    let donor = table.rows[if before { first } else { last }]
    extent = table.rows.fold(init=0.0, (sum, row) => sum + row.height) +
      (if insert {
        donor.height * amount.to_double()
      } else {
        -table.rows[first:last + 1].fold(init=0.0, (sum, row) => {
          sum + row.height
        })
      })
    let markup = if insert {
      let cells = donor.cells.map(blank_table_cell)
      guard cells.fold(init=0L, (sum, cell) => sum + cell.length().to_int64()) *
        amount.to_int64() <=
        2096000 else {
        @failure.reject(
          "limit-exceeded", "Inserted table row exceeds history budget",
        )
      }
      "<a:tr xmlns:a=\"\{drawing_uri}\" h=\"\{(donor.height * 12700).round().to_int64()}\">\{cells.join("")}</a:tr>"
    } else {
      ""
    }
    if insert {
      changes.push(
        table_source_change(
          donor.source,
          markup.repeat(amount),
          before=Some(before),
        ),
      )
    } else {
      for row in first..<=last {
        changes.push(table_source_change(table.rows[row].source, ""))
      }
    }
  } else {
    let column = if before { first } else { last }
    let width = table.widths[column]
    extent = table.widths.fold(init=0.0, (sum, width) => sum + width) +
      (if insert {
        width * amount.to_double()
      } else {
        -table.widths[first:last + 1].fold(init=0.0, (sum, width) => sum + width)
      })
    let first_row = table.rows[0].source
    let table_source : Ref = {
      tree: first_row.tree,
      node: first_row.tree.nodes[first_row.node.parent],
    }
    let grid = table_source.child("tblGrid").unwrap()
    let nodes = grid.tree.all(grid.node.id, "gridCol")
    if insert {
      let markup = "<a:gridCol xmlns:a=\"\{drawing_uri}\" w=\"\{(width * 12700).round().to_int64()}\"/>"
      changes.push(
        table_source_change(
          { tree: grid.tree, node: nodes[column], },
          markup.repeat(amount),
          before=Some(before),
        ),
      )
    } else {
      for column in first..<=last {
        changes.push(
          table_source_change({ tree: grid.tree, node: nodes[column], }, ""),
        )
      }
    }
    let mut units = 0L
    for row in table.rows {
      let markup = if insert { blank_table_cell(row.cells[column]) } else { "" }
      units += markup.length().to_int64() * amount.to_int64()
      guard units <= 2096000 else {
        @failure.reject(
          "limit-exceeded", "Inserted table column exceeds history budget",
        )
      }
      if insert {
        changes.push(
          table_source_change(
            row.cells[column].source,
            markup.repeat(amount),
            before=Some(before),
          ),
        )
      } else {
        for column in first..<=last {
          changes.push(table_source_change(row.cells[column].source, ""))
        }
      }
    }
  }
  guard extent <= 14400 else {
    @failure.reject("limit-exceeded", "Table extent exceeds budget")
  }
  let transform = object.source.child("xfrm", uri=presentation_uri).unwrap()
  changes.push(
    attribute_change(
      transform.child("ext").unwrap(),
      if rows {
        "cy"
      } else {
        "cx"
      },
      (extent * 12700).round().to_int64().to_string(),
    ),
  )
  let (candidate, edit) = self.prepare_table(
    original,
    changes,
    object.id,
    probe,
    profile,
  )
  let table = candidate.object(object.id).table.unwrap()
  let offset = if self.selection.mode == "text" {
    table.cell_offset(target_row, target_column)
  } else {
    0
  }
  let focus = if self.selection.mode == "text" && insert {
    table.cell_offset(
      if rows {
        target_row + amount - 1
      } else {
        range.bottom
      },
      if rows {
        range.right
      } else {
        target_column + amount - 1
      },
    )
  } else {
    offset
  }
  self.commit(
    candidate,
    edit,
    { ..self.selection, anchor: offset, focus, },
    probe~,
    profile~,
  )
  self.query()
}
