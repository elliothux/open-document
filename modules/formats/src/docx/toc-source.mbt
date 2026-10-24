///|
priv struct TocEntry {
  level : Int
  text : String
  bookmarks : Array[String]
} derive(Eq)

///|
fn Session::toc_entries(
  self : Session,
  tree : WordTree,
  flow : @layout.Flow,
  layout : @layout.Layout,
  first : Int,
  last : Int,
  sequence~ : String = "",
) -> (Array[TocEntry], Array[@xml.SourceChange]) raise @failure.Failure {
  let paragraphs : Map[Int, @layout.Paragraph] = Map::from_array(
    flow.paragraphs.map(p => (p.id, p)),
  )
  for table in flow.tables {
    for row in table.rows {
      for cell in row {
        for p in cell {
          paragraphs[p.id] = p
        }
      }
    }
  }
  let values : Map[Int, String] = Map([])
  let fields : Set[Int] = Set([])
  for p in paragraphs.values() {
    for span in p.spans {
      if !span.field.is_empty() {
        fields.add(span.node)
      }
    }
  }
  for page in layout.pages {
    for line in page.lines {
      for run in line.runs {
        for source in run.sources {
          if fields.contains(source.node) {
            values[source.node] = run.text
          }
        }
      }
    }
  }
  let bookmarks = tree.bookmarks()
  let keys : Set[String] = Set([])
  let names : Set[String] = Set([])
  for id in tree.order {
    if tree.is_bookmark(id) {
      keys.add(tree.nodes[id].attribute("id", uri=word_uri).unwrap_or(""))
      names.add(
        tree.nodes[id].attribute("name", uri=word_uri).unwrap_or("").to_lower(),
      )
    }
  }
  let result : Array[TocEntry] = []
  let changes : Array[@xml.SourceChange] = []
  let mut next = 0
  let mut units = 0
  for id in tree.order {
    guard !tree.contents.contains(id) && paragraphs.get(id) is Some(p) else {
      continue
    }
    let level = if sequence.is_empty() {
      flow.outlineLevels
      .get(id)
      .filter(level => level + 1 >= first && level + 1 <= last)
      .map(level => level + 1)
    } else if p.spans.any(span => {
        span.field.has_prefix("SEQ:") &&
        @layout.SequenceField::parse(span.field).sequence == sequence
      }) {
      Some(1)
    } else {
      None
    }
    guard level is Some(level) else { continue }
    tree.check_editable_paragraph(
      id,
      part=self.main,
      pictures=true,
      fields=true,
      complexFields=!sequence.is_empty(),
      math=true,
      notes=true,
    )
    let label = StringBuilder()
    if p.marker is Some(marker) {
      label.write_string(marker.text + " ")
    }
    for span in p.spans {
      guard span.drawing is None else {
        @failure.reject(
          "protected-content", "A heading drawing requires table of contents text support",
        )
      }
      label.write_string(
        if span.field.is_empty() {
          span.text
        } else {
          values.get(span.node).unwrap_or("")
        },
      )
    }
    let text = label
      .to_string()
      .replace_all(old="\t", new=" ")
      .replace_all(old="\u2028", new=" ")
      .replace_all(old="\n", new=" ")
      .trim()
      .to_owned()
    if text.is_empty() {
      continue
    }
    units += text.length()
    guard result.length() < 4096 && text.length() <= 4096 && units <= 1048576 else {
      @failure.reject(
        "limit-exceeded", "Table of contents headings exceed text budget",
      )
    }
    let existing = bookmarks
      .iter()
      .find_first(b => {
        b.reason.is_empty() &&
        b.selection is Some(selection) &&
        selection.anchor.paragraph == id &&
        selection.anchor.offset == 0
      })
    let bookmark = if existing is Some(bookmark) {
      bookmark.name
    } else {
      while next < 16384 &&
            (
              keys.contains(next.to_string()) ||
              names.contains("_toc" + next.to_string())
            ) {
        next += 1
      }
      guard next < 16384 else {
        @failure.reject(
          "limit-exceeded", "Table of contents bookmark identities exhausted",
        )
      }
      let key = next.to_string()
      let name = "_Toc" + key
      next += 1
      keys.add(key)
      names.add(name.to_lower())
      let p = tree.nodes[id]
      let start = tree
        .child(id, "pPr")
        .map(id => tree.nodes[id].end)
        .unwrap_or(p.opening_end)
      changes.push({
        node: id,
        offset: start - p.start,
        length: 0,
        xml: "<od:bookmarkStart xmlns:od=\"\{word_uri}\" od:id=\"\{key}\" od:name=\"\{name}\"/>" +
        (if sequence.is_empty() {
          ""
        } else {
          "<od:bookmarkEnd xmlns:od=\"\{word_uri}\" od:id=\"\{key}\"/>"
        }),
      })
      if sequence.is_empty() {
        changes.push({
          node: id,
          offset: p.closing_start - p.start,
          length: 0,
          xml: "<od:bookmarkEnd xmlns:od=\"\{word_uri}\" od:id=\"\{key}\"/>",
        })
      }
      name
    }
    result.push({ level, text, bookmarks: [bookmark], })
  }
  (result, changes)
}

///|
fn toc_markup(
  entries : Array[TocEntry],
  styles : Map[Int, String],
  instruction : String,
  hyperlink : Bool,
  width : Double,
  index~ : Bool = false,
  sequence~ : String = "",
) -> String raise @failure.Failure {
  let begin = "<od:r><od:fldChar od:fldCharType=\"begin\" od:dirty=\"true\"/></od:r><od:r><od:instrText xml:space=\"preserve\">\{property_attribute(instruction)}</od:instrText></od:r><od:r><od:fldChar od:fldCharType=\"separate\"/></od:r>"
  let end = "<od:r><od:fldChar od:fldCharType=\"end\"/></od:r>"
  if entries.is_empty() {
    let text = if index {
      "No index entries found."
    } else if !sequence.is_empty() {
      "No table of figures entries found."
    } else {
      "No table of contents entries found."
    }
    return "<od:p xmlns:od=\"\{word_uri}\">\{begin}<od:r><od:t>\{text}</od:t></od:r>\{end}</od:p>"
  }
  let output = StringBuilder()
  let separator = if !index || index_separator(instruction) == "\t" {
    "<od:r><od:tab/></od:r>"
  } else {
    "<od:r><od:t xml:space=\"preserve\">" +
    @xml.escape_text(index_separator(instruction)) +
    "</od:t></od:r>"
  }
  for index, entry in entries {
    let style = property_attribute(styles[entry.level])
    let name = property_attribute(entry.bookmarks.get(0).unwrap_or(""))
    let text = "<od:r><od:t xml:space=\"preserve\">\{@xml.escape_text(entry.text)}</od:t></od:r>"
    let label = if hyperlink {
      "<od:hyperlink od:anchor=\"\{name}\">\{text}</od:hyperlink>"
    } else {
      text
    }
    let references = entry.bookmarks
      .map(bookmark => {
        let reference = property_attribute(
          " PAGEREF " + bookmark + (if hyperlink { " \\h" } else { "" }) + " ",
        )
        "<od:fldSimple od:instr=\"\{reference}\" od:dirty=\"true\"><od:r><od:t>1</od:t></od:r></od:fldSimple>"
      })
      .join("<od:r><od:t xml:space=\"preserve\">, </od:t></od:r>")
    output.write_string(
      "<od:p xmlns:od=\"\{word_uri}\"><od:pPr><od:pStyle od:val=\"\{style}\"/><od:numPr><od:numId od:val=\"0\"/></od:numPr><od:tabs><od:tab od:val=\"right\" od:leader=\"dot\" od:pos=\"\{(width*20).round().to_int()}\"/></od:tabs><od:outlineLvl od:val=\"9\"/></od:pPr>" +
      (if index == 0 { begin } else { "" }) +
      label +
      (if references.is_empty() { "" } else { separator + references }) +
      (if index == entries.length() - 1 { end } else { "" }) +
      "</od:p>",
    )
  }
  output.to_string()
}
