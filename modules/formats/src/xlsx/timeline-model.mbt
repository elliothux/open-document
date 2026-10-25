///|
priv struct TimelineRange {
  start : String
  end : String
} derive(ToJson)

///|
priv struct TimelineState {
  bounds : TimelineRange
  selection : TimelineRange?
  singleRange : Bool
  filterType : String
  minimumRefreshVersion : Int
  lastRefreshVersion : Int
}

///|
fn TimelineState::same_filter(
  self : TimelineState,
  other : TimelineState,
) -> Bool raise @failure.Failure {
  match (self.selection, other.selection) {
    (Some(left), Some(right)) =>
      pivot_date_parse(left.start, false) ==
      pivot_date_parse(right.start, false) &&
      pivot_date_parse(left.end, false) == pivot_date_parse(right.end, false)
    (None, None) =>
      (self.filterType == "unknown") == (other.filterType == "unknown")
    _ => false
  }
}

///|
priv struct SheetTimeline {
  part : String
  name : String
  caption : String
  cache : TimelineCache
  level : Int
  selection_level : Int
  scroll : String?
  header : Bool
  selection_label : Bool
  time_level : Bool
  scrollbar : Bool
  style : String
}

///|
fn SheetTimeline::json(self : SheetTimeline) -> Json {
  let cache = self.cache
  {
    "part": self.part,
    "name": self.name,
    "caption": self.caption,
    "cache": cache.part,
    "cacheName": cache.name,
    "sourceName": cache.source,
    "pivotCache": cache.pivot_cache,
    "field": cache.field,
    "state": {
      "bounds": cache.state.bounds,
      "selection": cache.state.selection
      .map(value => Json(value))
      .unwrap_or(Json::null()),
      "singleRange": cache.state.singleRange,
      "filterType": cache.state.filterType,
      "minimumRefreshVersion": cache.state.minimumRefreshVersion,
      "lastRefreshVersion": cache.state.lastRefreshVersion,
    },
    "connections": cache.connections.map(pair => {
      let value : Json = {
        "sheet": pair.0.sheet,
        "part": pair.0.part,
        "name": pair.0.name,
        "field": pair.1,
      }
      value
    }),
    "level": self.level,
    "selectionLevel": self.selection_level,
    "scrollPosition": self.scroll
    .map(value => Json(value))
    .unwrap_or(Json::null()),
    "showHeader": self.header,
    "showSelectionLabel": self.selection_label,
    "showTimeLevel": self.time_level,
    "showHorizontalScrollbar": self.scrollbar,
    "style": self.style,
  }
}
