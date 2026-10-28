///|
fn Session::index_rows(
  self : Session,
  tree : WordTree,
  layout : @layout.Layout,
) -> (Array[TocEntry], Array[@xml.SourceChange]) raise @failure.Failure {
  guard tree.index_entries.length() <= 4096 else {
    @failure.reject("limit-exceeded", "Index entries exceed budget")
  }
  let texts = docx_texts(tree)
  let bookmarks = tree.bookmarks()
  let names : Set[String] = Set([])
  let keys : Set[String] = Set([])
  for id in tree.order {
    if tree.is_bookmark(id) {
      keys.add(tree.nodes[id].attribute("id", uri=word_uri).unwrap_or(""))
      names.add(
        tree.nodes[id].attribute("name", uri=word_uri).unwrap_or("").to_lower(),
      )
    }
  }
  let anchors : Map[(Int32, Int32), String] = Map([])
  let labels : Map[String, Array[String]] = Map([])
  let references : Map[String, Array[(Int32, String)]] = Map([])
  let changes : Array[@xml.SourceChange] = []
  let mut next = 0
  let mut work = 0
  for id in tree.order {
    guard tree.index_entries.get(id) is Some(entry) else { continue }
    guard entry.reason.is_empty() else {
      @failure.reject("protected-content", entry.reason)
    }
    tree.check_editable_paragraph(
      entry.paragraph,
      part=self.main,
      pictures=true,
      fields=true,
      math=true,
      notes=true,
    )
    let start = if tree.nodes[id].name == "fldSimple" {
      tree.nodes[id].start
    } else {
      tree.nodes[entry.runs[0]].start
    }
    let offset = texts
      .iter()
      .filter(item => {
        item.paragraph == entry.paragraph && tree.nodes[item.id].end <= start
      })
      .fold(init=0, (sum, item) => {
        sum + inline_text(tree.nodes[item.id]).length()
      })
    let page = for page, frame in layout.pages {
      work += frame.lines.length()
      guard work <= 1048576 else {
        @failure.reject("limit-exceeded", "Index page lookup exceeds budget")
      }
      if frame.lines.any(line => {
          line.paragraph == entry.paragraph &&
          !line.repeated &&
          line.container >= 0 &&
          line.start <= offset &&
          offset <= line.end
        }) {
        break Some(page)
      }
    } nobreak {
      None
    }
    guard page is Some(page) else {
      @failure.reject("unsupported-layout", "Index entry has no laid out page")
    }
    let bookmark = if anchors.get((entry.paragraph, offset)) is Some(name) {
      name
    } else {
      let existing = bookmarks
        .iter()
        .find_first(value => {
          value.reason.is_empty() &&
          value.selection is Some(selection) &&
          selection.anchor.paragraph == entry.paragraph &&
          selection.anchor.offset == offset
        })
      let name = if existing is Some(value) {
        value.name
      } else {
        while next < 16384 &&
              (
                keys.contains(next.to_string()) ||
                names.contains("_idx" + next.to_string())
              ) {
          next += 1
        }
        guard next < 16384 else {
          @failure.reject(
            "limit-exceeded", "Index bookmark identities exhausted",
          )
        }
        let key = next.to_string()
        let name = "_Idx" + key
        next += 1
        keys.add(key)
        names.add(name.to_lower())
        changes.push({
          node: entry.paragraph,
          offset: start - tree.nodes[entry.paragraph].start,
          length: 0,
          xml: "<od:bookmarkStart xmlns:od=\"\{word_uri}\" od:id=\"\{key}\" od:name=\"\{name}\"/><od:bookmarkEnd xmlns:od=\"\{word_uri}\" od:id=\"\{key}\"/>",
        })
        name
      }
      anchors[(entry.paragraph, offset)] = name
      name
    }
    let levels = entry.label
      .split(":")
      .map(value => value.trim().to_owned())
      .to_array()
    for level in 1..<=levels.length() {
      let terms = levels[:level].to_owned()
      let key = terms.map(value => value.to_lower()).join(":")
      if !labels.contains(key) {
        guard labels.length() < 4096 else {
          @failure.reject(
            "limit-exceeded", "Index result exceeds paragraph budget",
          )
        }
        labels[key] = terms
        references[key] = []
      }
      if level == levels.length() &&
        !references[key].any(value => value.0 == page) {
        references[key].push((page, bookmark))
      }
    }
  }
  let keys = labels.keys().to_array()
  keys.sort_by((a, b) => {
    let left = labels[a]
    let right = labels[b]
    for i in 0..<left.length().min(right.length()) {
      let order = left[i].to_lower().lexical_compare(right[i].to_lower())
      if order != 0 {
        break order
      }
    } nobreak {
      left.length().compare(right.length())
    }
  })
  let entries = keys.map(key => {
    let terms = labels[key]
    references[key].sort_by((a, b) => a.0.compare(b.0))
    TocEntry::{
      level: terms.length(),
      text: terms.last().unwrap(),
      bookmarks: references[key].map(value => value.1),
    }
  })
  (entries, changes)
}
