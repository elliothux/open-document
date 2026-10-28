///|
priv struct SheetSlicer {
  part : String
  name : String
  caption : String
  cache : SlicerCache
  columns : Int32
  start : Int32
  show_caption : Bool
  row_height : Double
  locked : Bool
  style : String
}

///|
fn Session::read_slicers(
  self : Session,
  sheet : String,
) -> Array[SheetSlicer] raise @failure.Failure {
  let current = self.sheets[self.sheet_index(sheet)]
  let parts = self.slicer_parts(
    sheet,
    current.document,
    slicer_list_extension,
    "slicerList",
    "slicer",
    "slicer",
  )
  if parts.is_empty() {
    return []
  }
  let trees = parts.map(part => (part, Tree::new(self.part_xml(part))))
  let wanted : Array[String] = []
  for (_, tree) in trees {
    for node in tree.slicer_children(tree.document.nodes()[0].id, "slicer") {
      wanted.push(slicer_text(node, "cache"))
      guard wanted.length() <= 64 else {
        @failure.reject("limit-exceeded", "Worksheet slicers exceed budget")
      }
    }
  }
  let caches = self.slicer_caches(wanted)
  let result : Array[SheetSlicer] = []
  let names : Map[String, Bool] = Map([])
  let mut members = 0
  let mut units = 0
  for (part, tree) in trees {
    let document = tree.document
    pivot_plain_source(document)
    let root = document.nodes()[0]
    guard root.name == "slicers" else {
      @failure.reject("protected-content", "Expected worksheet slicers")
    }
    slicer_node_profile(tree, root, [], ["slicer"])
    let entries = tree.slicer_children(root.id, "slicer")
    guard !entries.is_empty() && result.length() + entries.length() <= 64 else {
      @failure.reject("limit-exceeded", "Worksheet slicers exceed budget")
    }
    for node in entries {
      slicer_node_profile(
        tree,
        node,
        [
          "name", "cache", "caption", "columnCount", "startItem", "showCaption",
          "level", "style", "lockedPosition", "rowHeight",
        ],
        [],
      )
      let name = slicer_text(node, "name")
      let caption = decode_text(node.attribute("caption").unwrap_or(name))
      guard caption.length() <= 255 && @xml.valid_text(caption) else {
        @failure.reject("protected-content", "Invalid slicer caption")
      }
      let cache_name = slicer_text(node, "cache")
      guard caches.get(cache_name) is Some(cache) &&
        !names.contains(name) &&
        natural(node.attribute("level").unwrap_or("0"), 2147483647) == 0 else {
        @failure.reject(
          "protected-content", "Slicer cache, name or hierarchy is unavailable",
        )
      }
      let columns = natural(node.attribute("columnCount").unwrap_or("1"), 64)
      let row_height = natural(
          node.attribute("rowHeight").unwrap_or(""),
          182880000,
        ).to_double() /
        12700
      guard columns > 0 && row_height > 0 else {
        @failure.reject(
          "protected-content", "Slicer button dimensions must be positive",
        )
      }
      names[name] = true
      members += cache.members.length()
      units += name.length() + caption.length()
      for item in cache.members {
        units += item.value.display().length() * 2
      }
      guard members <= 16384 && units <= 1048576 else {
        @failure.reject(
          "limit-exceeded", "Slicer catalog text or members exceed budget",
        )
      }
      let style = decode_text(node.attribute("style").unwrap_or(""))
      guard style.length() <= 255 && @xml.valid_text(style) else {
        @failure.reject("protected-content", "Invalid slicer style name")
      }
      result.push({
        part,
        name,
        caption,
        cache,
        columns,
        row_height,
        start: natural(node.attribute("startItem").unwrap_or("0"), 4095),
        show_caption: flag(node, "showCaption", fallback=true),
        locked: flag(node, "lockedPosition"),
        style,
      })
    }
  }
  result
}

///|
/// Reads the native slicer cache graph without changing source or refreshing pivots.
pub fn Session::slicers(
  self : Session,
  revision : Int32,
  sheet : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  ignore(self.sheet_index(sheet))
  let mut reason = ""
  let controls = self.read_slicers(sheet) catch {
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
    "items": controls.map(control => {
      let cache = control.cache
      let value : Json = {
        "part": control.part,
        "name": control.name,
        "caption": control.caption,
        "cache": cache.part,
        "cacheName": cache.name,
        "sourceName": cache.source,
        "pivotCache": cache.pivot_cache,
        "field": cache.field,
        "connections": cache.pivots.map(pivot => {
          let value : Json = {
            "sheet": pivot.sheet,
            "part": pivot.part,
            "name": pivot.name,
          }
          value
        }),
        "columnCount": control.columns,
        "startItem": control.start,
        "showCaption": control.show_caption,
        "rowHeight": control.row_height,
        "lockedPosition": control.locked,
        "style": control.style,
        "sortOrder": cache.sort,
        "crossFilter": cache.cross_filter,
        "customListSort": cache.custom_sort,
        "showMissing": cache.show_missing,
        "members": cache.members.map(item => {
          let value : Json = {
            "index": item.index,
            "value": item.value,
            "label": if item.value == Blank {
              "(blank)"
            } else {
              item.value.display()
            },
            "selected": item.selected,
            "hasData": item.hasData,
          }
          value
        }),
      }
      value
    }),
  }
  guard result.stringify().length() <= 1048576 else {
    @failure.reject("limit-exceeded", "Slicer catalog JSON exceeds budget")
  }
  result
}
