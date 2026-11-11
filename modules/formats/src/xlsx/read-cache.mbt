///|
priv struct ReadCache {
  revision : Int32
  workbook : @xml.Document
  sheets : Array[Sheet]
  parts : Map[String, @xml.Document]
  media : Map[String, Bytes]
  removed : Array[String]
  scrolls : Map[(String, String), Int32]
  mut relationships : ReadOnlyArray[@opc.Relationship]?
  notes : Map[(String, Bool), SheetNotes?]
  threads : Map[String, SheetThreads]
  objects : Map[String, (Dimensions, Array[SheetObject], Array[String])]
  reference_sensitive : Map[String, Bool]
  mut conditional : ConditionalRead?
  mut chart_tiles : ChartTiles?
}

///|
fn Session::read_cache(self : Session) -> ReadCache {
  // Candidate transactions and slicer previews can change parts before revision.
  if self.read_cache is Some(cache) &&
    cache.revision == self.revision &&
    physical_equal(cache.workbook, self.workbook) &&
    cache.sheets.length() == self.sheets.length() &&
    cache.sheets
    .iter2()
    .iter()
    .all(pair => physical_equal(pair.1, self.sheets[pair.0])) &&
    cache.parts.length() == self.parts.length() &&
    cache.parts
    .iter()
    .all(pair => {
      self.parts
      .get(pair.0)
      .map(value => physical_equal(value, pair.1))
      .unwrap_or(false)
    }) &&
    cache.media.length() == self.media.length() &&
    cache.media
    .iter()
    .all(pair => {
      self.media
      .get(pair.0)
      .map(value => physical_equal(value, pair.1))
      .unwrap_or(false)
    }) &&
    cache.removed == self.removed &&
    cache.scrolls == self.slicer_scrolls {
    return cache
  }
  let cache : ReadCache = {
    revision: self.revision,
    workbook: self.workbook,
    sheets: self.sheets.copy(),
    parts: self.parts.copy(),
    media: self.media.copy(),
    removed: self.removed.copy(),
    scrolls: self.slicer_scrolls.copy(),
    relationships: None,
    notes: Map([]),
    threads: Map([]),
    objects: Map([]),
    reference_sensitive: Map([]),
    conditional: None,
    chart_tiles: None,
  }
  self.read_cache = Some(cache)
  cache
}
