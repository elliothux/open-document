///|
fn Session::set_first_slide_number(
  self : Session,
  value : Double,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  guard !value.is_nan() &&
    !value.is_inf() &&
    value.floor() == value &&
    value >= 0 &&
    value <= 4294967295 else {
    @failure.reject(
      "invalid-operation", "First slide number must be an unsigned 32-bit integer",
    )
  }
  if value == presentation_first_number(self.main) {
    return self.query()
  }
  let root = self.main.root("presentation")
  let (document, edit) = self.main.document.edit_source([
    attribute_change(
      { tree: self.main, node: root, },
      "firstSlideNum",
      value.to_int64().to_string(),
    ),
  ])
  let main = Tree::new(self.main.part, document)
  let edits = [(main.part, edit)]
  let parts = self.parts.copy()
  let changes : Map[String, (Tree, Array[@xml.SourceChange])] = Map([])
  for index, original in self.slides {
    let slide = numbered_slide(original, presentation_number(main, index))
    for j, object in slide.objects {
      let fields = object.paragraphs
        .map(p => p.runs)
        .flatten()
        .filter(run => {
          run.source
          .map(source => {
            source.node.uri == drawing_uri &&
            source.node.name == "fld" &&
            source.node.attribute("type").unwrap_or("").to_lower() == "slidenum"
          })
          .unwrap_or(false)
        })
      if fields.is_empty() {
        continue
      }
      guard fields.all(run => {
        run.source.map(slide_number_field).unwrap_or(false)
      }) else {
        @failure.reject(
          "protected-content", "Extended slide number fields require numbering support",
        )
      }
      if object.text() == original.objects[j].text() {
        continue
      }
      if object.body.fit == "none" {
        guard object.geometry is Some(geometry) else {
          @failure.reject("layout-overflow", "Missing slide number geometry")
        }
        let (_, _, reason) = fit_text(object, geometry, probe, profile)
        guard reason.is_empty() else {
          @failure.reject("layout-overflow", reason)
        }
      }
      let updates = derived_frame_changes(object, probe, profile)
      if !updates.is_empty() {
        let entry = changes.get_or_init(object.source.tree.part, () => {
          (object.source.tree, [])
        })
        for update in updates {
          let existing = entry.1
            .iter()
            .find_first(change => {
              change.node == update.node &&
              change.offset == update.offset &&
              change.length == update.length
            })
          if existing is Some(existing) {
            // shortcut: Conflicting shared auto frames stay protected until local overrides are supported.
            guard existing.xml == update.xml else {
              @failure.reject(
                "protected-content", "Shared slide number frames require different sizes",
              )
            }
          } else {
            entry.1.push(update)
          }
        }
      }
    }
  }
  let documents : Map[String, @xml.Document] = Map([])
  for part, (tree, updates) in changes {
    let (document, edit) = tree.document.edit_source(updates)
    documents[part] = document
    if !self.slides.any(slide => slide.tree.part == part) {
      parts[part] = document
    }
    edits.push((part, edit))
  }
  let slides = self.slides.mapi((index, slide) => {
    read_slide(
      self.opc,
      main,
      self.cache,
      documents
      .get(slide.tree.part)
      .map(document => Tree::new(slide.tree.part, document))
      .unwrap_or(slide.tree),
      index~,
      parts~,
      date_time=self.date_time,
    )
  })
  self.commit_slides(main, slides, edits, self.selection, parts~)
  self.query()
}
