///|
fn Session::range_paragraph_text(
  self : Session,
  tree : WordTree,
  range : ParagraphRange,
  paragraph : Int,
  fields : Map[Int, String],
) -> String raise @failure.Failure {
  let texts = self.editable_texts(paragraph)
  let start = if paragraph == range.start.paragraph {
    range.start.offset
  } else {
    0
  }
  let end = if paragraph == range.end.paragraph {
    range.end.offset
  } else {
    2147483647
  }
  let out = StringBuilder()
  let mut units = 0
  for item in texts; offset = 0 {
    let text = inline_text(tree.nodes[item.id])
    let left = (start - offset).clamp(min=0, max=text.length())
    let right = (end - offset).clamp(min=0, max=text.length())
    if left < right {
      let value = fields
        .get(item.id)
        .unwrap_or_else(() => text[left:right].to_owned())
        .replace_all(old="\u2028", new="\n")
      guard value.length() <= command_limit - units else {
        @failure.reject(
          "limit-exceeded", "Selection text exceeds UTF-16 budget",
        )
      }
      units += value.length()
      out.write_string(value)
    }
    continue offset + text.length()
  }
  out.to_string()
}

///|
fn Session::mixed_range_text(
  self : Session,
  tree : WordTree,
  range : ParagraphRange,
  fields : Map[Int, String],
) -> String raise @failure.Failure {
  let siblings = tree.children[tree.nodes[range.start.paragraph].parent]
  let blocks = siblings[siblings.search(range.start.paragraph).unwrap():siblings
    .search(range.end.paragraph)
    .unwrap() +
    1]
  let tables = self.flow().tables
  let lines : Array[String] = []
  let mut units = 0
  fn append(line : String) -> Unit raise @failure.Failure {
    let size = line.length() + (if lines.is_empty() { 0 } else { 1 })
    guard size <= command_limit - units else {
      @failure.reject("limit-exceeded", "Selection text exceeds UTF-16 budget")
    }
    units += size
    lines.push(line)
  }
  for id in blocks {
    if tree.nodes[id].name == "p" {
      append(self.range_paragraph_text(tree, range, id, fields))
      continue
    }
    let table = tables.iter().find_first(table => table.id == id).unwrap()
    for r, row in table.rows {
      let values : Array[String] = []
      for c, paragraphs in row {
        let text = if table.rowSpans[r][c] == 0 {
          ""
        } else {
          paragraphs
          .map(p => self.range_paragraph_text(tree, range, p.id, fields))
          .join("\n")
        }
        values.push(@delimited.quote_field(text))
        for _ in 1..<table.columnSpans[r][c] {
          values.push("")
        }
      }
      append(values.join("\t"))
    }
  }
  lines.join("\n")
}
