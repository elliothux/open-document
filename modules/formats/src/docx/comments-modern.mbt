///|
let comment_ids_uri = "http://schemas.microsoft.com/office/word/2016/wordml/cid"

///|
let comment_ids_kind = "http://schemas.microsoft.com/office/2016/09/relationships/commentsIds"

///|
let comment_extensible_uri = "http://schemas.microsoft.com/office/word/2018/wordml/cex"

///|
let comment_extensible_kind = "http://schemas.microsoft.com/office/2018/08/relationships/commentsExtensible"

///|
fn comment_root_attribute(attribute : @xml.Attribute) -> Bool {
  attribute.uri == "http://schemas.openxmlformats.org/markup-compatibility/2006" &&
  attribute.name == "Ignorable"
}

///|
fn comment_hex(value : Int) -> String {
  let out = StringBuilder()
  for j in 0..<8 {
    let digit = (value >> ((7 - j) * 4)) & 15
    out.write_string("0123456789ABCDEF"[digit:digit + 1].to_owned())
  }
  out.to_string()
}

///|
fn read_comment_ids(
  entries : Array[DocComment],
  document : @xml.Document,
) -> Map[String, String] raise @failure.Failure {
  let tree = WordTree::new(document)
  let root = tree.nodes[0]
  guard root.uri == comment_ids_uri &&
    root.name == "commentsIds" &&
    root.attributes.all(comment_root_attribute) &&
    root.text.trim().is_empty() else {
    @failure.reject("protected-content", "Unknown comment identity root")
  }
  let by_para = Map::from_array(
    entries.filter(e => !e.para.is_empty()).map(e => (e.para, true)),
  )
  let durable : Map[String, String] = Map([])
  let used : Map[String, Bool] = Map([])
  for id in tree.children[0] {
    let n = tree.nodes[id]
    guard n.uri == comment_ids_uri &&
      n.name == "commentId" &&
      n.text.trim().is_empty() &&
      tree.children[id].is_empty() &&
      n.attributes.all(a => {
        a.uri == comment_ids_uri && ["paraId", "durableId"].contains(a.name)
      }) else {
      @failure.reject("protected-content", "Unknown comment identity record")
    }
    let para = comment_para_id(
      n.attribute("paraId", uri=comment_ids_uri).unwrap_or(""),
    )
    let key = comment_para_id(
      n.attribute("durableId", uri=comment_ids_uri).unwrap_or(""),
    )
    guard by_para.contains(para) &&
      !durable.contains(para) &&
      !used.contains(key) else {
      @failure.reject(
        "protected-content", "Duplicate or detached durable comment identity",
      )
    }
    durable[para] = key
    used[key] = true
  }
  durable
}

///|
fn check_comment_presence(
  tree : WordTree,
  id : Int,
) -> Unit raise @failure.Failure {
  let n = tree.nodes[id]
  let extension_uri = "http://schemas.microsoft.com/office/word/2018/wordml"
  guard [comment_extensible_uri, extension_uri].contains(n.uri) &&
    n.name == "extLst" &&
    n.attributes.is_empty() &&
    n.text.trim().is_empty() &&
    tree.children[id].length() <= 1 else {
    @failure.reject("protected-content", "Unknown comment extensions")
  }
  for ext in tree.children[id] {
    let e = tree.nodes[ext]
    guard e.uri == n.uri &&
      e.name == "ext" &&
      e.text.trim().is_empty() &&
      e.attributes.length() == 1 &&
      e.attribute("uri").map(s => s.to_upper()) ==
      Some("{19B8F6BF-5375-455C-9EA6-DF929625EA0E}") &&
      tree.children[ext].length() == 1 else {
      @failure.reject("protected-content", "Unknown comment presence extension")
    }
    let person = tree.nodes[tree.children[ext][0]]
    guard person.uri ==
      "http://schemas.microsoft.com/office/powerpoint/2012/main" &&
      person.name == "presenceInfo" &&
      person.text.trim().is_empty() &&
      tree.children[person.id].is_empty() &&
      person.attributes.all(a => {
        a.uri.is_empty() &&
        ["userId", "providerId"].contains(a.name) &&
        a.value.length() <= 1024
      }) else {
      @failure.reject("protected-content", "Unknown comment presence data")
    }
  }
}

///|
fn read_comment_extensible(
  entries : Array[DocComment],
  durable : Map[String, String],
  document : @xml.Document,
) -> Array[DocComment] raise @failure.Failure {
  let tree = WordTree::new(document)
  let root = tree.nodes[0]
  guard root.uri == comment_extensible_uri &&
    root.name == "commentsExtensible" &&
    root.attributes.all(comment_root_attribute) &&
    root.text.trim().is_empty() else {
    @failure.reject("protected-content", "Unknown extensible comment root")
  }
  let by_id = Map::from_array(
    entries.filter(e => durable.contains(e.para)).map(e => (durable[e.para], e)),
  )
  let used : Map[String, Bool] = Map([])
  let dates : Map[String, String] = Map([])
  for id in tree.children[0] {
    let n = tree.nodes[id]
    guard n.uri == comment_extensible_uri &&
      n.name == "commentExtensible" &&
      n.text.trim().is_empty() &&
      tree.children[id].length() <= 1 &&
      n.attributes.all(a => {
        a.uri == comment_extensible_uri &&
        ["durableId", "dateUtc", "intelligentPlaceholder"].contains(a.name)
      }) else {
      @failure.reject(
        "protected-content", "Unknown extensible comment metadata",
      )
    }
    let key = comment_para_id(
      n.attribute("durableId", uri=comment_extensible_uri).unwrap_or(""),
    )
    guard by_id.get(key) is Some(entry) &&
      !used.contains(key) &&
      n
      .attribute("dateUtc", uri=comment_extensible_uri)
      .map(v => v.length() <= 128)
      .unwrap_or(true) else {
      @failure.reject(
        "protected-content", "Duplicate detached or excessive comment metadata",
      )
    }
    used[key] = true
    if n.attribute("dateUtc", uri=comment_extensible_uri) is Some(date) &&
      !date.is_empty() {
      dates[key] = date
    }
    if n.attribute("intelligentPlaceholder", uri=comment_extensible_uri)
      is Some(value) {
      guard entry.parent is None &&
        ["0", "1", "false", "true", "off", "on"].contains(value) else {
        @failure.reject("protected-content", "Invalid comment follow-up flag")
      }
    }
    for child in tree.children[id] {
      check_comment_presence(tree, child)
    }
  }
  entries.map(e => {
    ..e,
    date: durable.get(e.para).bind(key => dates.get(key)).unwrap_or(e.date),
  })
}

///|
fn add_comment_identity(
  source : CommentsSource,
  para : String,
  date : String?,
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
) -> Unit raise @failure.Failure {
  guard source.ids is Some((path, original)) else { return }
  let document = parts.get(path).unwrap_or(original)
  let tree = WordTree::new(document)
  let used : Map[String, Bool] = Map([])
  for id in tree.children[0] {
    let n = tree.nodes[id]
    if n.attribute("paraId", uri=comment_ids_uri).map(comment_para_id) ==
      Some(para) {
      return
    }
    used[comment_para_id(
      n.attribute("durableId", uri=comment_ids_uri).unwrap_or(""),
    )] = true
  }
  let key = for i in 1..<=65536 {
    let candidate = comment_hex(i)
    if !used.contains(candidate) {
      break candidate
    }
  } nobreak {
    @failure.reject("limit-exceeded", "Durable comment identities exhausted")
  }
  let (next, edit) = append_part_xml(
    document,
    "<od:commentId xmlns:od=\"\{comment_ids_uri}\" od:paraId=\"\{para}\" od:durableId=\"\{key}\"/>",
  )
  store_comment_edit(path, next, edit, parts, created, edits)
  if source.extensible is Some((path, original)) {
    let timestamp = date
      .map(v => " od:dateUtc=\"\{property_attribute(v)}\"")
      .unwrap_or("")
    let (next, edit) = append_part_xml(
      parts.get(path).unwrap_or(original),
      "<od:commentExtensible xmlns:od=\"\{comment_extensible_uri}\" od:durableId=\"\{key}\"\{timestamp}/>",
    )
    store_comment_edit(path, next, edit, parts, created, edits)
  }
}

///|
fn remove_comment_records(
  path : String,
  document : @xml.Document,
  uri : String,
  attribute : String,
  values : Array[String],
  parts : Map[String, @xml.Document],
  created : Map[String, @xml.Document],
  edits : Map[String, Array[@xml.Edit]],
) -> Unit raise @failure.Failure {
  let tree = WordTree::new(document)
  let targets = Map::from_array(values.map(v => (v, true)))
  let changes : Array[@xml.SourceChange] = []
  for id in tree.children[0] {
    let n = tree.nodes[id]
    if n
      .attribute(attribute, uri~)
      .map(comment_para_id)
      .map(v => targets.contains(v))
      .unwrap_or(false) {
      changes.push({
        node: n.parent,
        offset: n.start - tree.nodes[n.parent].start,
        length: n.end - n.start,
        xml: "",
      })
    }
  }
  if !changes.is_empty() {
    let (next, edit) = document.edit_source(changes)
    store_comment_edit(path, next, edit, parts, created, edits)
  }
}
