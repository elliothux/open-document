///|
pub(all) enum BibliographyFieldEdit {
  InsertBibliography(String)
  UpdateBibliography(Int)
  DeleteBibliography(Int)
}

///|
fn Session::bibliography_fields(
  self : Session,
) -> Array[Json] raise @failure.Failure {
  let tree = WordTree::new(self.document())
  let items : Array[Json] = []
  for id in tree.order {
    if tree.contents.get(id) is Some(field) &&
      field.paragraphs[0] == id &&
      field.instruction.trim().to_upper().has_prefix("BIBLIOGRAPHY") {
      guard items.length() < 256 else {
        @failure.reject("limit-exceeded", "Too many bibliography fields")
      }
      items.push({
        "paragraph": id,
        "endParagraph": field.paragraphs.last().unwrap(),
        "instruction": field.instruction,
        "reason": field.reason,
      })
    }
  }
  items
}

///|
fn Session::bibliography_rows(
  self : Session,
) -> (Array[TocEntry], Array[@xml.SourceChange]) raise @failure.Failure {
  let records = self
    .bibliography_part()
    .map(pair => read_bibliography_sources(WordTree::new(pair.1)))
    .unwrap_or([])
  let references = self.source_references()
  guard !references.contains("") &&
    references.iter().all(tag => records.any(record => record.value.tag == tag)) else {
    @failure.reject(
      "protected-content", "Bibliography requires complete citation source references",
    )
  }
  let entries : Array[TocEntry] = []
  let mut units = 0
  for record in records {
    if !references.contains(record.value.tag) {
      continue
    }
    guard record.reason.is_empty() && record.author_reason.is_empty() else {
      @failure.reject(
        "protected-content", "Bibliography requires supported source and author data",
      )
    }
    let value = record.value
    let text = [
        if value.author.is_empty() {
          ""
        } else {
          value.author + "."
        },
        if value.year.is_empty() {
          ""
        } else {
          "(" + value.year + ")."
        },
        if value.title.is_empty() {
          ""
        } else {
          value.title + "."
        },
        if value.publisher.is_empty() {
          ""
        } else {
          value.publisher + "."
        },
        value.url,
      ]
      .filter(part => !part.is_empty())
      .join(" ")
    guard !text.is_empty() else {
      @failure.reject(
        "protected-content", "Bibliography source has no display text",
      )
    }
    units += text.length()
    guard units <= 1048576 else {
      @failure.reject("limit-exceeded", "Bibliography text exceeds budget")
    }
    entries.push({ level: 1, text, bookmarks: [], })
  }
  (entries, [])
}

///|
/// Generates, explicitly updates or removes one native bibliography in one history item.
pub fn Session::edit_bibliography(
  self : Session,
  revision : Int,
  change : BibliographyFieldEdit,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  if change is InsertBibliography(_) {
    guard self.bibliography_fields().length() < 256 else {
      @failure.reject("limit-exceeded", "Too many bibliography fields")
    }
  }
  self.edit_generated_index(
    revision,
    match change {
      InsertBibliography(title) => {
        guard source_text(title, 255) && !title.trim().is_empty() else {
          @failure.reject(
            "invalid-operation", "Bibliography heading requires 1-255 plain characters",
          )
        }
        InsertBibliography(title)
      }
      UpdateBibliography(id) => Update(id)
      DeleteBibliography(id) => Delete(id)
    },
    kind=Bibliography,
    probe~,
    profile~,
    images~,
  )
}
