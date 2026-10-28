///|
priv struct SplitCell {
  source : DrawingCell
  top : Int32
  bottom : Int32
  left : Int32
  right : Int32
  blank : Bool
}

///|
fn table_grid_points(values : Array[Double]) -> Array[Int64] {
  let points = [0L]
  for value in values {
    points.push(points.last().unwrap() + (value * 12700).round().to_int64())
  }
  points
}

///|
fn table_grid_cuts(
  points : Array[Int64],
  first : Int32,
  last : Int32,
  count : Int32,
) -> Array[Int64] raise @failure.Failure {
  let size = points[last] - points[first]
  guard size >= count.to_int64() else {
    @failure.reject(
      "invalid-transform", "Split grid dimensions must remain positive",
    )
  }
  Array::makei(count + 1, i => {
    points[first] + size * i.to_int64() / count.to_int64()
  })
}

///|
fn refined_table_grid(
  points : Array[Int64],
  cuts : Array[Int64],
) -> Array[Int64] {
  let refined = points.copy()
  for cut in cuts {
    if !refined.contains(cut) {
      refined.push(cut)
    }
  }
  refined.sort()
  refined
}

///|
fn split_cell_values(
  rows : Int32,
  columns : Int32,
  horizontal : Bool,
  vertical : Bool,
) -> Map[String, String] {
  {
    "rowSpan": rows.to_string(),
    "gridSpan": columns.to_string(),
    "hMerge": if horizontal {
      "1"
    } else {
      "0"
    },
    "vMerge": if vertical {
      "1"
    } else {
      "0"
    },
  }
}

///|
fn split_existing_cell(
  cell : DrawingCell,
  rows : Int32,
  columns : Int32,
  horizontal : Bool,
  vertical : Bool,
) -> String raise @failure.Failure {
  let source = source_xml(cell.source)
  if cell.row_span == rows &&
    cell.column_span == columns &&
    cell.h_merge == horizontal &&
    cell.v_merge == vertical {
    return source
  }
  frame_opening(
    cell.source,
    split_cell_values(rows, columns, horizontal, vertical),
  ) +
  source[cell.source.node.opening_end - cell.source.node.start:].to_owned()
}

///|
fn split_new_cell(
  region : SplitCell,
  rows : Int32,
  columns : Int32,
  horizontal : Bool,
  vertical : Bool,
  blank : String,
) -> String raise @failure.Failure {
  let attrs = split_cell_values(rows, columns, horizontal, vertical)
    .iter()
    .map(pair => " \{pair.0}=\"\{pair.1}\"")
    .to_array()
    .join("")
  let content = if !horizontal && !vertical {
    blank
  } else {
    let props = region.source.source
      .child("tcPr")
      .map(p => p.tree.standalone_markup(p.tree.document, p.node.id))
      .unwrap_or("")
    "<a:txBody><a:bodyPr/><a:lstStyle/><a:p/></a:txBody>\{props}"
  }
  "<a:tc xmlns:a=\"\{drawing_uri}\"\{attrs}>\{content}</a:tc>"
}

///|
fn split_table_row(
  table : DrawingTable,
  old_row : Int32?,
  row : Int32,
  height : Int64,
  x : Array[Int64],
  old_x : Array[Int64],
  regions : Array[SplitCell],
  owners : Array[Array[Int32]],
  blank : String,
) -> String raise @failure.Failure {
  let out = StringBuilder()
  if old_row is Some(r) {
    let source = table.rows[r].source
    let text = source_xml(source)
    out.write_string(
      if (table.rows[r].height * 12700).round().to_int64() == height {
        text[:source.node.opening_end - source.node.start].to_owned()
      } else {
        frame_opening(source, { "h": height.to_string() })
      },
    )
    out.write_string(
      source.tree.document.source()[source.node.opening_end:table.rows[r].cells[0].source.node.start].to_owned(),
    )
  } else {
    out.write_string("<a:tr xmlns:a=\"\{drawing_uri}\" h=\"\{height}\">")
  }
  let mut units = 0
  for c in 0..<(x.length() - 1) {
    let old_column = old_x.search(x[c])
    if old_row is Some(r) && old_column is Some(c) && c > 0 {
      out.write_string(
        table.rows[r].source.tree.document.source()[table.rows[r].cells[c - 1].source.node.end:table.rows[r].cells[c].source.node.start].to_owned(),
      )
    }
    guard owners[row][c] >= 0 else {
      @failure.reject("invalid-operation", "Incomplete split table grid")
    }
    let region = regions[owners[row][c]]
    let horizontal = c > region.left
    let vertical = row > region.top
    let rows = if !horizontal && !vertical {
      region.bottom - region.top
    } else {
      1
    }
    let columns = if !horizontal { region.right - region.left } else { 1 }
    let markup = if !horizontal && !vertical && !region.blank {
      split_existing_cell(region.source, rows, columns, false, false)
    } else if horizontal || vertical {
      if old_row is Some(r) && old_column is Some(c) {
        split_existing_cell(
          table.rows[r].cells[c],
          rows,
          columns,
          horizontal,
          vertical,
        )
      } else {
        split_new_cell(region, rows, columns, horizontal, vertical, blank)
      }
    } else {
      split_new_cell(region, rows, columns, false, false, blank)
    }
    units += markup.length()
    guard units <= 2096000 else {
      @failure.reject("limit-exceeded", "Split table row exceeds source budget")
    }
    out.write_string(markup)
  }
  if old_row is Some(r) {
    let source = table.rows[r].source
    out.write_string(
      source.tree.document.source()[table.rows[r].cells.last().unwrap().source.node.end:source.node.end].to_owned(),
    )
  } else {
    out.write_string("</a:tr>")
  }
  out.to_string()
}

///|
fn Session::split_table_cell(
  self : Session,
  rows : Int32,
  columns : Int32,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  guard rows >= 1 &&
    rows <= 1000 &&
    columns >= 1 &&
    columns <= 63 &&
    rows.to_int64() * columns.to_int64() <= 4096 else {
    @failure.reject("invalid-operation", "Invalid split cell dimensions")
  }
  guard self.selection.objects.length() == 1 else {
    @failure.reject("invalid-operation", "Select one cell to split")
  }
  let original = self.current()
  let object = original.object(self.selection.object)
  guard object.table is Some(table) else {
    @failure.reject("protected-content", "Select an editable table")
  }
  let reason = self.table_geometry_reason(object, self.selection)
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let range = table.range(self.selection)
  guard range.owners == 1 else {
    @failure.reject("invalid-operation", "Select one cell to split")
  }
  if rows == 1 && columns == 1 {
    return self.query()
  }
  let (original, edits) = self.table_structure_source(object)
  let object = original.object(object.id)
  let table = object.table.unwrap()
  let owner = table.rows[range.top].cells[range.left]
  guard owner.row_span == 1 ||
    (rows <= owner.row_span && owner.row_span % rows == 0) else {
    @failure.reject(
      "invalid-operation", "Split row count must divide the existing vertical merge",
    )
  }
  let old_x = table_grid_points(table.widths)
  let old_y = table_grid_points(table.rows.map(row => row.height))
  let cuts_x = table_grid_cuts(old_x, range.left, range.right + 1, columns)
  let cuts_y = if owner.row_span == 1 {
    table_grid_cuts(old_y, range.top, range.bottom + 1, rows)
  } else {
    Array::makei(rows + 1, i => old_y[range.top + owner.row_span / rows * i])
  }
  for c in 0..<columns {
    guard (cuts_x[c + 1] - cuts_x[c]).to_double() / 12700 >
      owner.body.left + owner.body.right else {
      @failure.reject(
        "invalid-transform", "Split columns leave no cell text width",
      )
    }
  }
  let x = refined_table_grid(old_x, cuts_x)
  let y = refined_table_grid(old_y, cuts_y)
  let nr = y.length() - 1
  let nc = x.length() - 1
  guard nr <= 1000 && nc <= 63 && nr.to_int64() * nc.to_int64() <= 4096 else {
    @failure.reject(
      "limit-exceeded", "Split table exceeds row column or cell budget",
    )
  }
  let blank = blank_table_content(owner)
  let regions : Array[SplitCell] = []
  for r, row in table.rows {
    for c, cell in row.cells {
      if !cell.owner() || (r == range.top && c == range.left) {
        continue
      }
      regions.push({
        source: cell,
        top: y.search(old_y[r]).unwrap(),
        bottom: y.search(old_y[r + cell.row_span]).unwrap(),
        left: x.search(old_x[c]).unwrap(),
        right: x.search(old_x[c + cell.column_span]).unwrap(),
        blank: false,
      })
    }
  }
  for r in 0..<rows {
    for c in 0..<columns {
      regions.push({
        source: owner,
        top: y.search(cuts_y[r]).unwrap(),
        bottom: y.search(cuts_y[r + 1]).unwrap(),
        left: x.search(cuts_x[c]).unwrap(),
        right: x.search(cuts_x[c + 1]).unwrap(),
        blank: r != 0 || c != 0,
      })
    }
  }
  let owners = Array::makei(nr, _ => Array::make(nc, -1))
  for index, region in regions {
    for r in region.top..<region.bottom {
      for c in region.left..<region.right {
        owners[r][c] = index
      }
    }
  }
  let grid = owner.source.tree.nodes[owner.source.node.parent]
  let table_source : Ref = {
    tree: owner.source.tree,
    node: owner.source.tree.nodes[grid.parent],
  }
  let grid = table_source.child("tblGrid").unwrap()
  let grid_columns = grid.tree.all(grid.node.id, "gridCol")
  let changes : Array[@xml.SourceChange] = []
  for c, node in grid_columns {
    let first = x.search(old_x[c]).unwrap()
    let last = x.search(old_x[c + 1]).unwrap()
    if last - first == 1 {
      continue
    }
    let source : Ref = { tree: grid.tree, node, }
    guard node.attributes.all(a => a.uri.is_empty() && a.name == "w") &&
      grid.tree.children.get(node.id).unwrap_or([]).is_empty() &&
      !source_xml(source).contains("<!--") &&
      !source_xml(source).contains("<?") else {
      @failure.reject(
        "protected-content", "Unknown grid column metadata prevents splitting",
      )
    }
    let markup = StringBuilder()
    for index in first..<last {
      markup.write_string(
        "<a:gridCol xmlns:a=\"\{drawing_uri}\" w=\"\{x[index+1]-x[index]}\"/>",
      )
    }
    changes.push(table_source_change(source, markup.to_string()))
  }
  let mut units = 0
  for r, row in table.rows {
    let first = y.search(old_y[r]).unwrap()
    let last = y.search(old_y[r + 1]).unwrap()
    let markup = StringBuilder()
    for index in first..<last {
      let text = split_table_row(
        table,
        if index == first {
          Some(r)
        } else {
          None
        },
        index,
        y[index + 1] - y[index],
        x,
        old_x,
        regions,
        owners,
        blank,
      )
      units += text.length()
      guard units <= 2096000 else {
        @failure.reject("limit-exceeded", "Split table exceeds source budget")
      }
      markup.write_string(text)
    }
    if markup.to_string() != source_xml(row.source) {
      changes.push(table_source_change(row.source, markup.to_string()))
    }
  }
  let (candidate, edit) = self.prepare_table(
    original,
    changes,
    object.id,
    probe,
    profile,
  )
  let offset = candidate.object(object.id).table
    .unwrap()
    .cell_offset(y.search(cuts_y[0]).unwrap(), x.search(cuts_x[0]).unwrap())
  edits.push((original.tree.part, edit))
  self.commit_page(
    candidate,
    edits,
    { ..self.selection, mode: "text", anchor: offset, focus: offset, },
    probe~,
    profile~,
  )
  self.query()
}
