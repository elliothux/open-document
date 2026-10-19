///|
fn Session::reflow_master_layouts(
  self : Session,
  master : String,
  parts : Map[String, @xml.Document],
  edits : Array[(String, @xml.Edit)],
  probe : @layout.TextProbe?,
  profile : Map[String, String],
  media : Map[String, Bytes],
) -> Unit raise @failure.Failure {
  let original = self
    .layout_choices()
    .filter(choice => choice.master.part == master)
    .map(choice => self.source_slide(choice.tree.part))
  for owner in original {
    guard owner.objects.length() <= 4096 else {
      @failure.reject("limit-exceeded", "Source view objects exceed 4096")
    }
  }
  let updated = self.reflow_source(
    original,
    parts,
    edits,
    probe,
    profile,
    original~,
  )
  for owner in updated {
    let (owner, normalized) = self.normalize_groups(
      owner,
      self.main,
      self.source_index(owner.tree.part),
      parts,
    )
    if normalized is Some(edit) {
      parts[owner.tree.part] = owner.tree.document
      edits.push((owner.tree.part, edit))
    }
    let (owner, normalized) = self.normalize_connectors(
      owner,
      self.main,
      self.source_index(owner.tree.part),
      parts,
    )
    if normalized is Some(edit) {
      parts[owner.tree.part] = owner.tree.document
      edits.push((owner.tree.part, edit))
    }
    self.validate_slides(
      self.main,
      [owner],
      parts~,
      media~,
      check_package=false,
    )
  }
}
