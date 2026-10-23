///|
priv struct TimelineCache {
  part : String
  name : String
  source : String
  pivot_cache : String
  field : Int
  connections : Array[(PivotLocation, Int)]
  state : Json
}

///|
fn timeline_origin(
  document : @xml.Document,
) -> Array[String] raise @failure.Failure {
  let tree = Tree::new(document)
  let root = tree.root("pivotCacheDefinition")
  let source = tree
    .one(root.id, "cacheSource")
    .unwrap_or_else(() => {
      @failure.reject("protected-content", "Timeline source is missing")
    })
  guard source.attribute("type") == Some("worksheet") &&
    tree.children.get(source.id).unwrap_or([]) is [node] &&
    node.uri == spreadsheet_uri &&
    node.name == "worksheetSource" &&
    node.attributes.all(a => {
      a.uri.is_empty() && ["sheet", "ref", "name"].contains(a.name)
    }) else {
    @failure.reject(
      "protected-content", "External or unsupported timeline source",
    )
  }
  ["sheet", "ref", "name"].map(key => {
    decode_text(node.attribute(key).unwrap_or("")).to_upper()
  })
}

///|
fn timeline_source_field(
  document : @xml.Document,
  name : String,
  timeline : Bool,
) -> Int raise @failure.Failure {
  let tree = Tree::new(document)
  let root = tree.root("pivotCacheDefinition")
  let markers = document
    .nodes()
    .filter(node => {
      node.uri == timeline_uri && node.name == "timelinePivotCacheDefinition"
    })
  guard markers.length() <= 1 &&
    (!timeline || !markers.is_empty()) &&
    markers.all(node => {
      let parent = tree.nodes[node.parent]
      flag(node, "timelineData") == timeline &&
      node.attributes.all(a => a.uri.is_empty() && a.name == "timelineData") &&
      tree.children.get(node.id).unwrap_or([]).is_empty() &&
      parent.uri == spreadsheet_uri &&
      parent.name == "ext" &&
      parent
      .attribute("uri")
      .map(uri => uri.to_upper() == "{5DA0FC9A-693D-419C-AD59-312A39285967}")
      .unwrap_or(false) &&
      tree.nodes[parent.parent].name == "extLst" &&
      tree.nodes[tree.nodes[parent.parent].parent].id == root.id
    }) else {
    @failure.reject(
      "protected-content", "Timeline data and result cache roles disagree",
    )
  }
  let source = tree
    .one(root.id, "cacheSource")
    .unwrap_or_else(() => {
      @failure.reject("protected-content", "Timeline pivot source is missing")
    })
  guard source.attribute("type") == Some("worksheet") else {
    @failure.reject(
      "protected-content", "OLAP timeline sources require support",
    )
  }
  let fields = tree
    .one(root.id, "cacheFields")
    .map(list => tree.all(list.id, "cacheField"))
    .unwrap_or([])
  guard fields.length() > 0 && fields.length() <= 80 else {
    @failure.reject("limit-exceeded", "Timeline source fields exceed budget")
  }
  let matches = fields
    .mapi((at, field) => {
      (at, decode_text(field.attribute("name").unwrap_or("")))
    })
    .filter(field => field.1 == name)
  guard matches is [(field, _)] else {
    @failure.reject(
      "protected-content", "Timeline source field is ambiguous or unavailable",
    )
  }
  field
}

///|
fn Session::read_timeline_cache(
  self : Session,
  part : String,
  pivots : Array[PivotLocation],
) -> TimelineCache raise @failure.Failure {
  let document = self.part_xml(part)
  pivot_plain_source(document)
  let tree = Tree::new(document)
  let root = document.nodes()[0]
  guard root.name == "timelineCacheDefinition" else {
    @failure.reject("protected-content", "Expected native timeline cache")
  }
  timeline_profile(tree, root, ["name", "sourceName"], [
    "pivotTables", "state", "timelinePivotFilter",
  ])
  let name = slicer_text(root, "name")
  let source = slicer_text(root, "sourceName")
  let node = tree.timeline_node(root.id, "state")
  timeline_profile(
    tree,
    node,
    [
      "singleRangeFilterState", "minimalRefreshVersion", "lastRefreshVersion", "pivotCacheId",
      "filterType",
    ],
    ["selection", "bounds"],
  )
  let pivot_cache = self.timeline_pivot_cache(
    node.attribute("pivotCacheId").unwrap_or(""),
  )
  let field = timeline_source_field(self.part_xml(pivot_cache), source, true)
  let selection = tree.timeline_children(node.id, "selection")
  guard selection.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate timeline selection")
  }
  let state : Json = {
    "bounds": timeline_range(tree, tree.timeline_node(node.id, "bounds")),
    "selection": selection
    .get(0)
    .map(item => timeline_range(tree, item))
    .unwrap_or(Json::null()),
    "singleRange": flag(node, "singleRangeFilterState", fallback=true),
    "filterType": slicer_text(node, "filterType"),
    "minimumRefreshVersion": natural(
      node.attribute("minimalRefreshVersion").unwrap_or(""),
      2147483647,
    ),
    "lastRefreshVersion": natural(
      node.attribute("lastRefreshVersion").unwrap_or(""),
      2147483647,
    ),
  }
  let lists = tree.timeline_children(root.id, "pivotTables")
  guard lists.length() <= 1 else {
    @failure.reject("protected-content", "Duplicate timeline connections")
  }
  let connections : Array[(PivotLocation, Int)] = []
  let seen : Map[String, Bool] = Map([])
  for list in lists {
    timeline_profile(tree, list, [], ["pivotTable"])
    let entries = tree.timeline_children(list.id, "pivotTable")
    guard !entries.is_empty() && entries.length() <= 16 else {
      @failure.reject("limit-exceeded", "Timeline connections exceed budget")
    }
    for entry in entries {
      timeline_profile(tree, entry, ["tabId", "name"], [])
      let sheet = self.slicer_pivot_sheet(
        entry.attribute("tabId").unwrap_or(""),
      )
      let name = slicer_text(entry, "name")
      guard pivots.filter(pivot => pivot.sheet == sheet && pivot.name == name)
        is [pivot] &&
        !seen.contains(pivot.part) else {
        @failure.reject(
          "protected-content", "Timeline pivot connection is unavailable or duplicated",
        )
      }
      let field = timeline_source_field(
        self.part_xml(pivot.cache),
        source,
        false,
      )
      seen[pivot.part] = true
      guard timeline_origin(self.part_xml(pivot.cache)) ==
        timeline_origin(self.part_xml(pivot_cache)) else {
        @failure.reject(
          "protected-content", "Timeline and connected pivot sources disagree",
        )
      }
      connections.push((pivot, field))
    }
  }
  { part, name, source, pivot_cache, field, connections, state, }
}

///|
fn Session::read_timelines(
  self : Session,
  sheet : String,
) -> Array[Json] raise @failure.Failure {
  let current = self.sheets[self.sheet_index(sheet)]
  let views = self.timeline_parts(
    sheet,
    current.document,
    timeline_view_extension,
    "timelineRefs",
    "timelineRef",
    "Timeline",
  )
  if views.is_empty() {
    return []
  }
  let caches : Map[String, TimelineCache] = Map([])
  let pivots = self.pivot_locations()
  let mut units = 0
  for
    part in self.timeline_parts(
      self.main,
      self.workbook,
      timeline_cache_extension,
      "timelineCacheRefs",
      "timelineCacheRef",
      "TimelineCache",
    ) {
    units += self.part_xml(part).source().length()
    guard units <= 1048576 else {
      @failure.reject("limit-exceeded", "Timeline source exceeds budget")
    }
    let cache = self.read_timeline_cache(part, pivots)
    guard !caches.contains(cache.name.to_lower()) else {
      @failure.reject(
        "protected-content", "Timeline cache names are duplicated",
      )
    }
    caches[cache.name.to_lower()] = cache
  }
  let result : Array[Json] = []
  let names : Map[String, Bool] = Map([])
  for part in views {
    let document = self.part_xml(part)
    units += document.source().length()
    guard units <= 1048576 else {
      @failure.reject("limit-exceeded", "Timeline source exceeds budget")
    }
    pivot_plain_source(document)
    let tree = Tree::new(document)
    let root = document.nodes()[0]
    guard root.name == "timelines" else {
      @failure.reject("protected-content", "Expected native timeline views")
    }
    timeline_profile(tree, root, [], ["timeline"])
    let items = tree.timeline_children(root.id, "timeline")
    guard !items.is_empty() && result.length() + items.length() <= 64 else {
      @failure.reject("limit-exceeded", "Timeline views exceed budget")
    }
    for node in items {
      timeline_profile(
        tree,
        node,
        [
          "name", "cache", "caption", "showHeader", "showSelectionLabel", "showTimeLevel",
          "showHorizontalScrollbar", "level", "selectionLevel", "scrollPosition",
          "style",
        ],
        [],
      )
      let name = slicer_text(node, "name")
      let cache_name = slicer_text(node, "cache")
      guard !names.contains(name.to_lower()) &&
        caches.get(cache_name.to_lower()) is Some(cache) else {
        @failure.reject(
          "protected-content", "Timeline view identity or cache is unavailable",
        )
      }
      names[name.to_lower()] = true
      let scroll = node.attribute("scrollPosition")
      let style = decode_text(node.attribute("style").unwrap_or(""))
      guard style.length() <= 255 && @xml.valid_text(style) else {
        @failure.reject("protected-content", "Invalid timeline style name")
      }
      if scroll is Some(value) {
        ignore(pivot_date_parse(value, false))
      }
      let value : Json = {
        "part": part,
        "name": name,
        "caption": slicer_text(node, "caption", fallback=name),
        "cache": cache.part,
        "cacheName": cache.name,
        "sourceName": cache.source,
        "pivotCache": cache.pivot_cache,
        "field": cache.field,
        "state": cache.state,
        "connections": cache.connections.map(pair => {
          let connection : Json = {
            "sheet": pair.0.sheet,
            "part": pair.0.part,
            "name": pair.0.name,
            "field": pair.1,
          }
          connection
        }),
        "level": natural(node.attribute("level").unwrap_or(""), 3),
        "selectionLevel": natural(
          node.attribute("selectionLevel").unwrap_or(""),
          3,
        ),
        "scrollPosition": scroll
        .map(value => Json(value))
        .unwrap_or(Json::null()),
        "showHeader": flag(node, "showHeader", fallback=true),
        "showSelectionLabel": flag(node, "showSelectionLabel", fallback=true),
        "showTimeLevel": flag(node, "showTimeLevel", fallback=true),
        "showHorizontalScrollbar": flag(
          node,
          "showHorizontalScrollbar",
          fallback=true,
        ),
        "style": style,
      }
      result.push(value)
    }
  }
  result
}

///|
/// Reads native timeline views, date state and pivot connections without refreshing or editing.
pub fn Session::timelines(
  self : Session,
  revision : Int,
  sheet : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  ignore(self.sheet_index(sheet))
  let mut reason = ""
  let items = self.read_timelines(sheet) catch {
    @failure.Failure(code="limit-exceeded", ..) as error => raise error
    @failure.Failure(message~, ..) => {
      reason = message
      []
    }
  }
  let result : Json = {
    "revision": revision,
    "sheet": sheet,
    "reason": reason,
    "items": items,
  }
  guard result.stringify().length() <= 1048576 else {
    @failure.reject("limit-exceeded", "Timeline catalog exceeds budget")
  }
  result
}
