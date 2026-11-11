///|
struct ParagraphVersion {
  paragraph : Paragraph
  content : String
  number : Int32
  mut checked : Bool
}

///|
priv struct ParagraphVersions {
  probe : TextProbe
  current : Map[Int32, ParagraphVersion]
  mut units : Int32
}

///|
fn ParagraphCache::version(
  self : ParagraphCache,
  paragraph : Paragraph,
) -> ParagraphVersion? {
  guard self.versions is Some(versions) else { return None }
  if versions.current.get(paragraph.id) is Some(current) {
    // Field reflow and running stories can have more than one form of a node.
    return if physical_equal(current.paragraph, paragraph) {
      Some(current)
    } else {
      None
    }
  }
  guard versions.current.length() < 4096 && versions.units < 1048576 else {
    return None
  }
  let previous = versions.probe.paragraph_versions.get(paragraph.id)
  let version = if previous is Some(previous) &&
    physical_equal(previous.paragraph, paragraph) {
    previous
  } else {
    guard paragraph.finite_geometry() else { return None }
    let content = paragraph.to_json().stringify()
    if previous is Some(previous) && previous.content == content {
      { ..previous, paragraph, checked: false, }
    } else {
      let number = versions.probe.next_paragraph_version
      guard number < 2147483647 else { return None }
      versions.probe.next_paragraph_version += 1
      { paragraph, content, number, checked: false, }
    }
  }
  let units = version.content.length() + 1
  guard units <= 1048576 - versions.units else { return None }
  versions.current[paragraph.id] = version
  versions.units += units
  Some(version)
}

///|
fn ParagraphCache::commit(self : ParagraphCache, probe : TextProbe) -> Unit {
  probe.paragraphs = self.current
  probe.text_units = self.current
    .values()
    .fold(init=0, (sum, entry) => sum + entry.units)
  if self.versions is Some(versions) {
    probe.paragraph_versions = versions.current
  }
}
