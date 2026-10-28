///|
fn section_name(name : String) -> Unit raise @failure.Failure {
  guard !name.trim().is_empty() && name.length() <= 255 && @xml.valid_text(name) else {
    @failure.reject(
      "invalid-operation", "Section name requires 1 to 255 XML text units",
    )
  }
}

///|
fn section_index(
  sections : Array[Section],
  id : String,
) -> Int32 raise @failure.Failure {
  guard section_guid(id) &&
    sections.search_by(s => s.id.to_upper() == id.to_upper()) is Some(index) else {
    @failure.reject("invalid-operation", "Section no longer exists")
  }
  index
}

///|
fn Session::edit_sections(
  self : Session,
  index : Int32,
  change : SlideEdit,
) -> Json raise @failure.Failure {
  let reason = if change is MoveSection(_, _) || change is DeleteSection(_) {
    self.slide_order_reason()
  } else {
    self.slide_visibility_reason()
  }
  guard reason.is_empty() else { @failure.reject("protected-content", reason) }
  let sections = read_sections(self.main)
  let ids = section_slide_ids(self.main)
  if change is DeleteSection(id) {
    let section = sections[section_index(sections, id)]
    let targets : Array[String] = []
    for i, source in ids {
      if section.slides.contains(source) {
        targets.push(self.slides[i].tree.part)
      }
    }
    return self.delete_slides(targets, section=Some(section.id))
  }
  let mut next = self.object_sequence
  fn fresh() -> String raise @failure.Failure {
    while next <= 4294967295L {
      let id = document_guid(next)
      next += 1L
      if !sections.any(s => s.id.to_upper() == id) {
        return id
      }
    }
    @failure.reject("limit-exceeded", "Section identity exhausted")
  }
  match change {
    AddSection(name) => {
      section_name(name)
      guard sections.length() < 256 else {
        @failure.reject("limit-exceeded", "Sections exceed 256")
      }
      if sections.is_empty() {
        if index > 0 {
          sections.push({
            node: -1,
            id: fresh(),
            name: "Default Section",
            slides: ids[:index].to_owned(),
          })
        }
        sections.push({
          node: -1,
          id: fresh(),
          name,
          slides: ids[index:].to_owned(),
        })
      } else if sections.search_by(s => s.slides.contains(ids[index]))
        is Some(position) {
        let original = sections[position]
        let start = original.slides.search(ids[index]).unwrap()
        sections[position] = {
          ..original,
          slides: original.slides[:start].to_owned(),
        }
        sections.insert(position + 1, {
          node: -1,
          id: fresh(),
          name,
          slides: original.slides[start:].to_owned(),
        })
      } else {
        let first = sections
          .iter()
          .find_first(s => !s.slides.is_empty())
          .map(s => ids.search(s.slides[0]).unwrap())
          .unwrap_or(ids.length())
        sections.insert(0, {
          node: -1,
          id: fresh(),
          name,
          slides: ids[index:first].to_owned(),
        })
      }
    }
    RenameSection(id, name) => {
      section_name(name)
      let position = section_index(sections, id)
      if sections[position].name == name {
        return self.query()
      }
      sections[position] = { ..sections[position], name, }
    }
    RemoveSections => {
      if sections.is_empty() {
        return self.query()
      }
      sections.clear()
    }
    RemoveSection(id) => {
      let position = section_index(sections, id)
      let removed = sections.remove(position)
      if !sections.is_empty() {
        let destination = (position - 1).max(0)
        let original = sections[destination]
        sections[destination] = {
          ..original,
          slides: if position == 0 {
            removed.slides + original.slides
          } else {
            original.slides + removed.slides
          },
        }
      }
    }
    MoveSection(id, target) => {
      let position = section_index(sections, id)
      guard target >= 0 && target < sections.length() else {
        @failure.reject("invalid-operation", "Invalid section position")
      }
      if position == target {
        return self.query()
      }
      let section = sections.remove(position)
      sections.insert(target, section)
    }
    _ => abort("Invalid section command")
  }
  let edits : Array[(String, @xml.Edit)] = []
  let mut main = self.main
  if change is MoveSection(_, _) {
    let owned : Map[String, Bool] = Map([])
    for section in sections {
      for id in section.slides {
        owned[id] = true
      }
    }
    let order = ids.filter(id => !owned.contains(id))
    for section in sections {
      order.append(section.slides)
    }
    let (document, edit) = main.document.edit_source([
      reorder_section_slides(main, order),
    ])
    edits.push((main.part, edit))
    main = Tree::new(main.part, document)
  }
  main = write_sections(main, sections, edits)
  if edits.is_empty() {
    return self.query()
  }
  let slides = self.ordered_slides(main, self.slides)
  self.commit_slides(main, slides, edits, self.selection)
  self.object_sequence = next
  self.query()
}

///|
fn sync_slide_sections(
  before : Tree,
  after : Tree,
  edits : Array[(String, @xml.Edit)],
  change : SlideEdit,
  index : Int32,
) -> Tree raise @failure.Failure {
  let sections = read_sections(before)
  if sections.is_empty() {
    return after
  }
  let ids = section_slide_ids(before)
  let updated = section_slide_ids(after)
  match change {
    AddSlide | CopySlide =>
      if sections.search_by(s => s.slides.contains(ids[index]))
        is Some(position) {
        let section = sections[position]
        let members = section.slides.copy()
        members.insert(
          members.search(ids[index]).unwrap() + 1,
          updated[index + 1],
        )
        sections[position] = { ..section, slides: members, }
      }
    MoveSlide(target) => {
      let labels = ids.map(id => {
        sections.iter().find_first(s => s.slides.contains(id)).map(s => s.id)
      })
      ignore(labels.remove(index))
      let adopt = labels
        .get(target)
        .unwrap_or_else(() => labels.last().unwrap_or(None))
      labels.insert(target, adopt)
      for i, section in sections {
        let members : Array[String] = []
        for j, id in updated {
          if labels[j] == Some(section.id) {
            members.push(id)
          }
        }
        sections[i] = { ..section, slides: members, }
      }
    }
    _ => abort("Invalid page section synchronization")
  }
  write_sections(after, sections, edits)
}
