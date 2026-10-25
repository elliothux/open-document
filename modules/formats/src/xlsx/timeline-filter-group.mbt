///|
fn Session::timeline_filter_group(
  self : Session,
  target : TimelineCache,
) -> Array[TimelineCache] raise @failure.Failure {
  let result = [target]
  let seen = Set::from_array([target.part])
  for ;; {
    let connections : Array[(PivotLocation, Int)] = []
    let pivots : Set[String] = Set([])
    for cache in result {
      for pair in cache.connections {
        connections.push(pair)
        pivots.add(pair.0.part)
      }
    }
    guard pivots.length() <= 16 else {
      @failure.reject(
        "limit-exceeded", "Connected timeline filtering exceeds 16 pivots",
      )
    }
    let linked = self.affected_timeline_caches(
      self.pivot_locations().filter(pivot => pivots.contains(pivot.part)),
    )
    let previous = result.length()
    for cache in linked {
      if !seen.contains(cache.part) &&
        cache.connections.any(pair => {
          connections.any(target => {
            target.0.part == pair.0.part && target.1 == pair.1
          })
        }) {
        seen.add(cache.part)
        result.push(cache)
      }
    }
    if result.length() == previous {
      break
    }
  }
  for cache in result {
    guard !cache.connections.is_empty() &&
      cache.state.singleRange &&
      ["unknown", "dateBetween", "dateEqual"].contains(cache.state.filterType) &&
      Tree::new(self.part_xml(cache.part))
      .timeline_children(0, "timelinePivotFilter")
      .is_empty() else {
      @failure.reject(
        "protected-content", "Timeline filter state requires additional support",
      )
    }
  }
  result
}
