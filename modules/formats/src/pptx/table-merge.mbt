///|
fn table_span_change(
  cell : DrawingCell,
  rows : Int,
  columns : Int,
  horizontal : Bool,
  vertical : Bool,
) -> @xml.SourceChange raise @failure.Failure {
  let source = cell.source
  let parent = source.tree.nodes[source.node.parent]
  {
    node: parent.id,
    offset: source.node.start - parent.start,
    length: source.node.opening_end - source.node.start,
    xml: frame_opening(source, {
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
    }),
  }
}

///|
fn Session::merge_table_cells(
  self : Session,
  object : Object,
  range : TableRange,
  unmerge : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let (original, edits) = self.table_structure_source(object)
  let object = original.object(object.id)
  let table = object.table.unwrap()
  let owner = table.rows[range.top].cells[range.left]
  let changes : Array[@xml.SourceChange] = []
  if !unmerge {
    let paragraphs : Array[String] = []
    let mut units = 0
    for row in range.top..<=range.bottom {
      for column in range.left..<=range.right {
        let cell = table.rows[row].cells[column]
        if !cell.owner() {
          continue
        }
        for p in cell.paragraphs {
          let xml = p.source.tree.standalone_markup(
            p.source.tree.document,
            p.source.node.id,
          )
          units += xml.length()
          guard units <= 2096000 else {
            @failure.reject(
              "limit-exceeded", "Merged table text exceeds history budget",
            )
          }
          paragraphs.push(xml)
        }
        if row != range.top || column != range.left {
          let target = object.table_cell(cell)
          let (clear, _) = text_changes(
            target,
            { ..self.selection, anchor: 0, focus: target.text().length(), },
            "",
          )
          changes.append(clear)
        }
      }
    }
    let first = owner.paragraphs[0].source.node
    let last = owner.paragraphs.last().unwrap().source.node
    let parent = owner.source.tree.nodes[first.parent]
    changes.push({
      node: parent.id,
      offset: first.start - parent.start,
      length: last.end - first.start,
      xml: paragraphs.join(""),
    })
  }
  for row in range.top..<=range.bottom {
    for column in range.left..<=range.right {
      let left = column == range.left
      let top = row == range.top
      changes.push(
        table_span_change(
          table.rows[row].cells[column],
          if !unmerge && left && top {
            range.bottom - range.top + 1
          } else {
            1
          },
          if !unmerge && left {
            range.right - range.left + 1
          } else {
            1
          },
          !unmerge && !left,
          !unmerge && !top,
        ),
      )
    }
  }
  let (candidate, edit) = self.prepare_table(
    original,
    changes,
    object.id,
    probe,
    profile,
  )
  let next = candidate.object(object.id)
  let offset = next.table.unwrap().cell_offset(range.top, range.left)
  let length = if unmerge {
    0
  } else {
    next.table.unwrap().rows[range.top].cells[range.left].paragraphs.fold(
      init=-1,
      (sum, p) => sum + paragraph_length(p) + 1,
    )
  }
  edits.push((original.tree.part, edit))
  self.commit_page(
    candidate,
    edits,
    { ..self.selection, mode: "text", anchor: offset, focus: offset + length, },
    probe~,
    profile~,
  )
  self.query()
}
