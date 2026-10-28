///|
priv struct SourcePatch {
  node : Int32
  offset : Int32
  after_offset : Int32
  position : Int32
  before : String
  after : String
  before_ids : Array[Int32]
  after_ids : Array[Int32]
}

///|
/// Local source fragments and node identities needed for exact undo and redo.
pub struct Edit {
  priv patches : Array[SourcePatch]
}

///|
priv struct AbsolutePatch {
  start : Int32
  end : Int32
  text : String
  index : Int32
}

///|
pub(all) struct SourceChange {
  node : Int32
  offset : Int32
  length : Int32
  xml : String
}

///|
/// Returns decoded source; Node source offsets refer to this string.
pub fn Document::source(self : Document) -> String {
  self.source
}

///|
/// Escapes XML 1.0 character data without normalizing carriage returns.
pub fn escape_text(text : String) -> String raise @failure.Failure {
  guard valid_text(text) else {
    @failure.reject("invalid-operation", "Invalid XML text")
  }
  @parser.escape(text).replace(old="\r", new="&#13;")
}

///|
fn Document::node_index(
  self : Document,
  id : Int32,
) -> Int32 raise @failure.Failure {
  for index, node in self.nodes {
    if node.id == id {
      return index
    }
  }
  @failure.reject(
    "invalid-operation",
    "Unknown XML node",
    part=self.part,
    offset=id,
  )
}

///|
pub fn Document::node(
  self : Document,
  id : Int32,
) -> Node raise @failure.Failure {
  self.nodes[self.node_index(id)]
}

///|
pub fn Document::bytes(self : Document) -> Bytes {
  @utf8.encode(self.canonical_source())
}

///|
pub fn Document::is_original(self : Document) -> Bool {
  self.canonical_source() == self.origin
}

///|
fn Document::canonical_source(self : Document) -> String {
  if self.declaration_end > 0 &&
    self.source[:self.declaration_end] != self.declaration {
    self.declaration + self.source[self.declaration_end:].to_owned()
  } else {
    self.source
  }
}

///|
/// Counts every retained UTF-16 source fragment, including escapes and markup.
pub fn Edit::payload_bytes(self : Edit) -> Int64 {
  self.patches
  .iter()
  .fold(init=0L, (bytes, patch) => {
    bytes +
    (patch.before.length().to_int64() + patch.after.length().to_int64()) * 2
  })
}

///|
fn Document::source_patch(
  self : Document,
  id : Int32,
  start : Int32,
  end : Int32,
  text : String,
) -> SourcePatch raise @failure.Failure {
  let node = self.node(id)
  guard start > node.start &&
    start < node.end &&
    end >= start &&
    end <= node.end &&
    self.source.get_view(start~, end~) is Some(_) else {
    @failure.reject(
      "invalid-operation",
      "XML patch leaves its node",
      part=self.part,
    )
  }
  {
    node: id,
    offset: start - node.start,
    after_offset: 0,
    position: start,
    before: self.source[start:end].to_owned(),
    after: text,
    before_ids: [],
    after_ids: [],
  }
}

///|
fn Document::source_patches(
  self : Document,
  changes : Array[SourceChange],
) -> Array[SourcePatch] raise @failure.Failure {
  changes.map(change => {
    let node = self.node(change.node)
    guard change.offset >= 0 &&
      change.length >= 0 &&
      valid_text(change.xml) &&
      change.offset <= node.end - node.start &&
      change.length <= node.end - node.start - change.offset else {
      @failure.reject(
        "invalid-operation",
        "Invalid XML source range",
        part=self.part,
      )
    }
    let start = node.start + change.offset
    self.source_patch(change.node, start, start + change.length, change.xml)
  })
}

///|
/// Edits node-local source ranges atomically, validating the complete resulting XML.
pub fn Document::edit_source(
  self : Document,
  changes : Array[SourceChange],
) -> (Document, Edit) raise @failure.Failure {
  self.prepare_edit(self.source_patches(changes), forward=true, record=true)
}

///|
pub fn Document::apply(
  self : Document,
  edit : Edit,
  forward~ : Bool,
) -> Document raise @failure.Failure {
  self.prepare_edit(edit.patches, forward~, record=false).0
}

///|
fn Document::prepare_edit(
  self : Document,
  patches : Array[SourcePatch],
  forward~ : Bool,
  record~ : Bool,
) -> (Document, Edit) raise @failure.Failure {
  let absolute : Array[AbsolutePatch] = []
  for index, patch in patches {
    let node = self.node(patch.node)
    let before = if forward { patch.before } else { patch.after }
    let after = if forward { patch.after } else { patch.before }
    let offset = if forward { patch.offset } else { patch.after_offset }
    guard offset > 0 &&
      offset < node.end - node.start &&
      before.length() <= node.end - node.start - offset else {
      @failure.reject(
        "invalid-operation",
        "XML patch leaves its current node",
        part=self.part,
      )
    }
    let start = node.start + offset
    let end = start + before.length()
    guard self.source[start:end] == before else {
      @failure.reject(
        "invalid-operation",
        "XML source patch is stale",
        part=self.part,
        offset=start,
      )
    }
    absolute.push({ start, end, text: after, index, })
  }
  if self.declaration_end > 0 &&
    self.source[:self.declaration_end] != self.declaration {
    absolute.push({
      start: 0,
      end: self.declaration_end,
      text: self.declaration,
      index: -1,
    })
  }
  absolute.sort_by((a, b) => {
    if a.start == b.start {
      if a.end != b.end {
        a.end.compare(b.end)
      } else if !forward && a.index >= 0 && b.index >= 0 {
        // Adjacent deletions collapse to one offset; undo restores source order.
        patches[a.index].position.compare(patches[b.index].position)
      } else {
        a.index.compare(b.index)
      }
    } else {
      a.start.compare(b.start)
    }
  })
  let units = absolute
    .iter()
    .fold(init=self.source.length().to_int64(), (units, patch) => {
      units +
      patch.text.length().to_int64() -
      (patch.end - patch.start).to_int64()
    })
  guard units >= 0 && units <= self.byte_limit.to_int64() else {
    @failure.reject(
      "limit-exceeded",
      "XML source patch budget exceeded",
      part=self.part,
    )
  }
  let output = StringBuilder()
  let inserted : Array[(Int32, Int32, Int32)] = []
  let mut cursor = 0
  let mut shift = 0
  for patch in absolute {
    guard patch.start >= cursor else {
      @failure.reject(
        "invalid-operation",
        "Overlapping XML replacements",
        part=self.part,
      )
    }
    output.write_view(self.source[cursor:patch.start])
    output.write_string(patch.text)
    inserted.push(
      (
        patch.start + shift,
        patch.start + shift + patch.text.length(),
        patch.index,
      ),
    )
    shift += patch.text.length() - (patch.end - patch.start)
    cursor = patch.end
  }
  output.write_view(self.source[cursor:])
  let candidate = Document::parse(
    @utf8.encode(output.to_string()),
    self.part,
    self.depth_limit,
    self.byte_limit,
  )
  let survivors : Map[Int32, Int32] = Map([])
  let before_ids = Array::makei(patches.length(), _ => [])
  for node in self.nodes {
    let mut shift = 0
    let mut removed = false
    for patch in absolute {
      if node.start >= patch.start && node.start < patch.end {
        removed = true
        if patch.index >= 0 {
          before_ids[patch.index].push(node.id)
        }
        break
      }
      if node.start >= patch.end {
        shift += patch.text.length() - (patch.end - patch.start)
      }
    }
    if !removed {
      survivors[node.start + shift] = node.id
    }
  }
  let after_ids = Array::makei(patches.length(), _ => [])
  let ids : Array[Int32] = []
  let used : Map[Int32, Bool] = Map([])
  let mut next_id = self.next_id
  for node in candidate.nodes {
    let insertion = inserted
      .iter()
      .find_first(range => {
        node.start >= range.0 && node.start < range.1 && range.2 >= 0
      })
    let id = if survivors.get(node.start) is Some(id) {
      id
    } else if insertion is Some((_, _, index)) && !record {
      let expected = if forward {
        patches[index].after_ids
      } else {
        patches[index].before_ids
      }
      guard expected.get(after_ids[index].length()) is Some(id) else {
        @failure.reject(
          "invalid-operation",
          "XML patch node identities changed",
          part=self.part,
        )
      }
      id
    } else {
      guard next_id < 0x7fffffff else {
        @failure.reject(
          "limit-exceeded",
          "XML node identities exhausted",
          part=self.part,
        )
      }
      let id = next_id
      next_id += 1
      id
    }
    ids.push(id)
    guard id >= 0 && id < next_id && !used.contains(id) else {
      @failure.reject(
        "invalid-operation",
        "XML patch reuses an unrelated node identity",
        part=self.part,
      )
    }
    used[id] = true
    if insertion is Some((_, _, index)) {
      after_ids[index].push(id)
    }
  }
  if !record {
    for index, patch in patches {
      let expected_before = if forward {
        patch.before_ids
      } else {
        patch.after_ids
      }
      let expected_after = if forward {
        patch.after_ids
      } else {
        patch.before_ids
      }
      guard before_ids[index] == expected_before &&
        after_ids[index] == expected_after else {
        @failure.reject(
          "invalid-operation",
          "XML patch node identities changed",
          part=self.part,
        )
      }
    }
  }
  for index, node in candidate.nodes {
    candidate.nodes[index] = {
      ..node,
      id: ids[index],
      parent: if node.parent < 0 {
        -1
      } else {
        ids[node.parent]
      },
    }
  }
  let edit = if record {
    {
      patches: patches.mapi((index, patch) => {
        let range = inserted
          .iter()
          .find_first(range => range.2 == index)
          .unwrap()
        let node = candidate.node(patch.node)
        {
          ..patch,
          after_offset: range.0 - node.start,
          before_ids: before_ids[index],
          after_ids: after_ids[index],
        }
      }),
    }
  } else {
    { patches, }
  }
  ({ ..candidate, origin: self.origin, next_id, }, edit)
}
