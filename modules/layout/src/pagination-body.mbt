///|
fn Pagination::body(
  self : Pagination,
  probe : TextProbe,
  flow : Flow,
  cache : ParagraphCache,
  profile : Map[String, String],
  images : Images,
) -> (Int, Int, PaginationCache?) raise @failure.Failure {
  let blocks = flow.body_blocks(probe, profile)
  let keys = pagination_keys(blocks)
  let context = Json::array([
    self.page.to_json(),
    Json::array(self.setups.map(page => page.to_json())),
    Json(flow.additiveSpacing),
    Json(cache.profile),
  ]).stringify()
  let previous = match probe.pagination {
    Some(old) if old.context == context && keys is Some(_) => Some(old)
    _ => None
  }
  let mut prefix = 0
  let mut suffix = 0
  let positions : Array[PagePosition] = []
  if previous is Some(old) && keys is Some(current) {
    while prefix < old.keys.length().min(current.length()) &&
          old.keys[prefix] == current[prefix] {
      prefix += 1
    }
    if prefix == old.keys.length() && prefix == current.length() {
      self.restore(old, old.positions.last().unwrap(), images)
      for block in blocks {
        block.retain(cache, self.page)
      }
      return (0, self.pages.length(), Some(old))
    }
    while suffix < old.keys.length().min(current.length()) - prefix &&
          old.keys[old.keys.length() - suffix - 1] ==
          current[current.length() - suffix - 1] {
      suffix += 1
    }
    self.restore(old, old.positions[prefix], images)
    positions.append(old.positions[0:prefix + 1].to_owned())
    for index in 0..<prefix {
      blocks[index].retain(cache, self.page)
    }
  } else if keys is Some(_) {
    positions.push(self.position())
  }
  let prefix_pages = self.pages.length() - 1
  let mut reused = prefix_pages
  let mut reflowed = 1
  let mut index = prefix
  while index < blocks.length() {
    if previous is Some(old) &&
      keys is Some(current) &&
      index > prefix &&
      index >= current.length() - suffix {
      let old_index = old.keys.length() - (current.length() - index)
      let before = old.positions[old_index]
      let now = self.position()
      if now.stable(before) &&
        self.page_at(now.page).to_json() == self.page_at(before.page).to_json() &&
        (
          (now.page - before.page) % 2 == 0 ||
          self.setups.is_empty() ||
          self.setups[1].to_json() == self.setups[2].to_json()
        ) {
        reflowed = now.page - prefix_pages + 1
        reused += old.pages.length() - before.page - 1
        self.append_tail(old, before, images)
        for next in (old_index + 1)..<old.positions.length() {
          positions.push(translated_position(old.positions[next], before, now))
        }
        for next in index..<blocks.length() {
          blocks[next].retain(cache, self.page)
        }
        index = blocks.length()
        break
      }
    }
    blocks[index].place(
      self,
      cache,
      probe,
      profile,
      images,
      flow.additiveSpacing,
    )
    index += 1
    if keys is Some(_) {
      positions.push(self.position())
    }
    reflowed = self.pages.length() - prefix_pages
  }
  let next = if keys is Some(keys) &&
    PaginationCache::bounded(context, keys, positions, self.pages) {
    Some({
      context,
      keys,
      positions,
      pages: self.pages.map(page => page.copy_geometry()),
    })
  } else {
    None
  }
  (reflowed, reused, next)
}
