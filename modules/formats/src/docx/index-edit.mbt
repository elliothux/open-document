///|
pub(all) enum IndexEdit {
  MarkIndexEntry(String)
  UpdateIndexEntry(Int32, String)
  DeleteIndexEntry(Int32)
  InsertIndex
  UpdateIndex(Int32)
  DeleteIndex(Int32)
}

///|
fn index_entry_markup(label : String) -> String raise @failure.Failure {
  check_index_label(label)
  let instruction = property_attribute(" XE \"" + label + "\" ")
  "<od:fldSimple xmlns:od=\"\{word_uri}\" od:instr=\"\{instruction}\"><od:r><od:rPr><od:vanish/></od:rPr><od:t/></od:r></od:fldSimple>"
}

///|
fn WordTree::index_range_changes(
  self : WordTree,
  start : Position,
  end : Position,
) -> Array[@xml.SourceChange] {
  let changes : Array[@xml.SourceChange] = []
  if start.paragraph == end.paragraph && start.offset == end.offset {
    return changes
  }
  let texts = docx_texts(self)
  for entry in self.index_entries.values() {
    if !entry.reason.is_empty() ||
      (entry.paragraph != start.paragraph && entry.paragraph != end.paragraph) {
      continue
    }
    let ids = if self.nodes[entry.id].name == "fldSimple" {
      [entry.id]
    } else {
      entry.runs
    }
    let source_start = self.nodes[ids[0]].start
    let offset = texts
      .iter()
      .filter(item => {
        item.paragraph == entry.paragraph &&
        self.nodes[item.id].end <= source_start
      })
      .fold(init=0, (sum, item) => {
        sum + inline_text(self.nodes[item.id]).length()
      })
    if (entry.paragraph != start.paragraph || offset >= start.offset) &&
      (entry.paragraph != end.paragraph || offset <= end.offset) {
      for id in ids {
        let node = self.nodes[id]
        let parent = self.nodes[self.nodes[entry.paragraph].parent]
        changes.push({
          node: parent.id,
          offset: node.start - parent.start,
          length: node.end - node.start,
          xml: "",
        })
      }
    }
  }
  changes
}

///|
fn WordTree::index_instruction_changes(
  self : WordTree,
  entry : IndexEntry,
  label : String,
) -> Array[@xml.SourceChange] raise @failure.Failure {
  check_index_label(label)
  let instruction = property_attribute(" XE \"" + label + "\" ")
  let node = self.nodes[entry.id]
  if node.name == "fldSimple" {
    let attribute = node.attributes
      .iter()
      .find_first(a => a.uri == word_uri && a.name == "instr")
      .unwrap()
    return [
      {
        node: node.id,
        offset: attribute.start - node.start,
        length: attribute.end - attribute.start,
        xml: instruction,
      },
    ]
  }
  let instructions = entry.runs
    .map(run => self.children[run])
    .flatten()
    .filter(id => self.nodes[id].name == "instrText")
  instructions.mapi((index, id) => {
    let node = self.nodes[id]
    let text = if index == 0 { instruction } else { "" }
    @xml.SourceChange::{
      node: id,
      offset: node.opening_end - node.start - (if node.empty { 2 } else { 0 }),
      length: if node.empty {
        2
      } else {
        node.closing_start - node.opening_end
      },
      xml: if node.empty {
        ">" + text + "</" + node.qualified + ">"
      } else {
        text
      },
    }
  })
}

///|
/// Marks a term or edits/removes complete native XE and INDEX fields.
pub fn Session::edit_index(
  self : Session,
  revision : Int32,
  change : IndexEdit,
  probe~ : @layout.TextProbe,
  profile~ : Map[String, String],
  images~ : @layout.Images,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  match change {
    InsertIndex =>
      return self.edit_generated_index(
        revision,
        Insert(3),
        probe~,
        profile~,
        images~,
        kind=Index,
      )
    UpdateIndex(id) =>
      return self.edit_generated_index(
        revision,
        Update(id),
        probe~,
        profile~,
        images~,
        kind=Index,
      )
    DeleteIndex(id) =>
      return self.edit_generated_index(
        revision,
        Delete(id),
        probe~,
        profile~,
        images~,
        kind=Index,
      )
    _ => ()
  }
  self.check_document_protection()
  let original = self.document()
  let tree = WordTree::new(original)
  let changes : Array[@xml.SourceChange] = []
  let paragraph = match change {
    MarkIndexEntry(label) => {
      guard tree.index_entries.length() < 4096 else {
        @failure.reject("limit-exceeded", "Index entries exceed budget")
      }
      guard self.selection is Some(selection) else {
        @failure.reject(
          "invalid-position", "Select text or a position for the index entry",
        )
      }
      let range = self.paragraph_range(
        tree,
        selection,
        structural=true,
        fields=true,
        math=true,
        notes=true,
      )
      let position = range.end
      changes.push(
        self.paragraph_inline_source(original, position, _ => {
          index_entry_markup(label)
        }),
      )
      position.paragraph
    }
    UpdateIndexEntry(id, _) | DeleteIndexEntry(id) => {
      guard tree.index_entries.get(id) is Some(entry) && entry.reason.is_empty() else {
        @failure.reject(
          "protected-content", "Select a complete supported index entry",
        )
      }
      tree.check_editable_paragraph(
        entry.paragraph,
        part=self.main,
        pictures=true,
        fields=true,
        math=true,
        notes=true,
      )
      if change is UpdateIndexEntry(_, label) && label == entry.label {
        return self.edit_state()
      }
      if change is UpdateIndexEntry(_, label) {
        changes.append(tree.index_instruction_changes(entry, label))
      } else {
        let nodes = if tree.nodes[id].name == "fldSimple" {
          [id]
        } else {
          entry.runs
        }
        for id in nodes {
          let node = tree.nodes[id]
          changes.push({
            node: entry.paragraph,
            offset: node.start - tree.nodes[entry.paragraph].start,
            length: node.end - node.start,
            xml: "",
          })
        }
      }
      entry.paragraph
    }
    _ => abort("Generated indexes were handled above")
  }
  let (candidate, edit) = original.edit_source(changes)
  let view = { ..self, document: Some(candidate), }
  let layout = @layout.paginate(probe, view.flow(), profile, images)
  guard layout.diagnostics.is_empty() else {
    @failure.reject(
      "unsupported-layout", "Index entries require a complete layout",
    )
  }
  ignore(view.page_positioned(layout, probe))
  let bytes = edit_bytes(edit)
  guard bytes <= history_byte_limit else {
    @failure.reject("limit-exceeded", "Index entry exceeds history budget")
  }
  let pending = self.typing_format
  self.commit_edit(
    {
      xml: [edit],
      parts: Map([]),
      created: Map([]),
      created_media: Map([]),
      before: self.selection,
      after: self.selection,
      paragraphs: [paragraph],
      bytes,
    },
    candidate,
  )
  self.typing_format = pending
  self.edit_result([paragraph])
}
