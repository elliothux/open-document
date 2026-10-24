///|
fn Session::prepare_analysis_sheet_delete(
  self : Session,
  sheet : String,
  edits : Array[(String, @xml.Edit)],
  removed : Map[String, @xml.Document],
) -> Array[String] raise @failure.Failure {
  let current = self.sheets[self.sheet_index(sheet)]
  ignore(self.read_slicers(sheet))
  ignore(self.read_timelines(sheet))
  let owned = self.slicer_parts(
      sheet,
      current.document,
      slicer_list_extension,
      "slicerList",
      "slicer",
      "slicer",
    ) +
    self.timeline_parts(
      sheet,
      current.document,
      timeline_view_extension,
      "timelineRefs",
      "timelineRef",
      "Timeline",
    )
  let links = self.relationships()
  for part in owned {
    guard links.filter(link => !link.external && link.target == part) is [link] &&
      link.owner == sheet &&
      [
        slicer_relationship_uri + "slicer",
        timeline_relationship_uri + "Timeline",
      ].contains(link.kind) &&
      !links.any(link => link.owner == part) else {
      @failure.reject(
        "protected-content", "Shared or extended analysis view ownership requires deletion support",
      )
    }
  }
  for pivot in self.pivot_locations().filter(pivot => pivot.sheet == sheet) {
    let slicers = self.deletion_slicer_caches(pivot)
    let timelines = self.affected_timeline_caches([pivot])
    self.remove_pivot_slicers(
      pivot,
      slicers,
      edits,
      removed,
      deleted_sheet=Some(sheet),
    )
    self.remove_pivot_timelines(
      pivot,
      timelines,
      edits,
      removed,
      deleted_sheet=Some(sheet),
    )
  }
  owned
}
