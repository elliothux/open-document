///|
pub(all) struct FindOptions {
  matchCase : Bool
  wholeWord : Bool
  all : Bool
}

///|
pub fn FindOptions::new(
  matchCase~ : Bool = false,
  wholeWord~ : Bool = false,
  all~ : Bool = true,
) -> FindOptions {
  { matchCase, wholeWord, all, }
}

///|
priv struct TextMatch {
  slide : Int32
  object : String
  anchor : Int32
  focus : Int32
  snippet : String
  reason : String
}

///|
fn Object::search_texts(self : Object) -> Array[(String, Int32)] {
  guard self.table is Some(table) else { return [(self.text(), 0)] }
  let texts : Array[(String, Int32)] = []
  let mut offset = 0
  for row in table.rows {
    for cell in row.cells {
      if cell.owner() {
        let value = self.table_cell(cell).text()
        texts.push((value, offset))
        offset += value.length() + 1
      }
    }
  }
  texts
}

///|
fn Session::find_text(
  self : Session,
  slide : String,
  text : String,
  options : FindOptions,
) -> (Array[TextMatch], Bool) raise @failure.Failure {
  guard text.length() <= TextFrameUnits && @xml.valid_text(text) else {
    @failure.reject("invalid-operation", "Search text is invalid or excessive")
  }
  let selected = self.index(slide)
  let pattern = @layout.LiteralPattern::new(
    text,
    match_case=options.matchCase,
    whole_word=options.wholeWord,
  )
  let matches : Array[TextMatch] = []
  let mut scanned = 0
  for index, current in self.slides {
    if !options.all && index != selected {
      continue
    }
    for object in current.objects {
      if object.source.tree.part != current.tree.part ||
        object.paragraphs.is_empty() {
        continue
      }
      let value = object.text()
      scanned += value.length()
      guard scanned <= 1048576 else {
        @failure.reject("limit-exceeded", "Search text budget exceeded")
      }
      let reason = self.formatting_reason(object)
      for (value, offset) in object.search_texts() {
        let ranges = pattern.matches(value)
        if ranges.is_empty() {
          continue
        }
        let boundaries = @layout.grapheme_boundaries(value)
        for (anchor, focus) in ranges {
          if matches.length() == SearchMatchLimit {
            return (matches, true)
          }
          let a = match boundaries.binary_search((anchor - 16).max(0)) {
            Ok(i) | Err(i) => i
          }
          let b = match
            boundaries.binary_search((boundaries[a] + 80).min(value.length())) {
            Ok(i) => i
            Err(i) => i - 1
          }
          matches.push({
            slide: index,
            object: object.id,
            anchor: offset + anchor,
            focus: offset + focus,
            snippet: value[boundaries[a]:boundaries[b]].to_owned(),
            reason,
          })
        }
      }
    }
  }
  (matches, false)
}

///|
priv struct SearchMatch {
  slide : String
  object : String
  anchor : Int32
  focus : Int32
  hidden : Bool
  snippet : String
  reason : String
} derive(ToJson)

///|
priv struct SearchResult {
  revision : Int32
  truncated : Bool
  matches : Array[SearchMatch]
} derive(ToJson)

///|
/// Find literal text in slide/source-object order without changing document state.
pub fn Session::find(
  self : Session,
  revision : Int32,
  slide : String,
  text : String,
  options : FindOptions,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  self.check_idle()
  let (matches, truncated) = self.find_text(slide, text, options)
  let result : SearchResult = {
    revision,
    truncated,
    matches: matches.map(item => {
      slide: self.slides[item.slide].tree.part,
      object: item.object,
      anchor: item.anchor,
      focus: item.focus,
      hidden: self.slides[item.slide].hidden,
      snippet: item.snippet,
      reason: item.reason,
    }),
  }
  ToJson::to_json(result)
}

///|
pub const SearchMatchLimit : Int32 = 1000
