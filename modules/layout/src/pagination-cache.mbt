///|
priv struct PagePosition {
  page : Int
  lines : Int
  borders : Int
  fills : Int
  cellAreas : Int
  count : Int
  y : Double
  after : Double
  gap : Double
  table : Int?
  tableWidths : Array[Double]
}

///|
struct PaginationCache {
  context : String
  keys : Array[String]
  positions : Array[PagePosition]
  pages : Array[PageFrame]
}

///|
fn Pagination::position(self : Pagination) -> PagePosition {
  let page = self.pages.last().unwrap()
  {
    page: self.pages.length() - 1,
    lines: page.lines.length(),
    borders: page.borders.length(),
    fills: page.fills.length(),
    cellAreas: page.cellAreas.length(),
    count: self.count,
    y: self.y,
    after: self.after,
    gap: self.gap,
    table: self.active_table,
    tableWidths: self.active_table
    .bind(id => self.tables.get(id))
    .map(table => table.widths)
    .unwrap_or([]),
  }
}

///|
fn PagePosition::stable(self : PagePosition, other : PagePosition) -> Bool {
  self.table == other.table &&
  self.tableWidths == other.tableWidths &&
  self.y == other.y &&
  self.after == other.after &&
  self.gap == other.gap &&
  (self.lines == 0) == (other.lines == 0) &&
  (self.borders == 0) == (other.borders == 0) &&
  (self.cellAreas == 0) == (other.cellAreas == 0)
}

///|
fn Pagination::restore(
  self : Pagination,
  old : PaginationCache,
  position : PagePosition,
  images : Images,
) -> Unit raise @failure.Failure {
  self.pages.clear()
  for index in 0..<position.page {
    let page = old.pages[index].copy_geometry()
    page.validate_images(images)
    self.pages.push(page)
  }
  let page = old.pages[position.page]
  let prefix : PageFrame = {
    ..page,
    lines: page.lines[0:position.lines]
    .to_owned()
    .map(line => line.copy_geometry()),
    borders: page.borders[0:position.borders].to_owned(),
    fills: page.fills[0:position.fills].to_owned(),
    cellAreas: page.cellAreas[0:position.cellAreas]
    .to_owned()
    .map(area => area.copy_geometry()),
  }
  prefix.validate_images(images)
  self.pages.push(prefix)
  self.placedWrapping.clear()
  for frame in self.pages {
    for line in frame.lines {
      for image in line.images {
        if image.anchor is Some(anchor) && anchor.wrapping != "none" {
          self.placedWrapping[(line.paragraph, image.start)] = ()
        }
      }
    }
  }
  self.page = self.page_at(position.page)
  self.y = position.y
  self.after = position.after
  self.gap = position.gap
  self.count = position.count
  self.active_table = position.table
}

///|
fn Pagination::append_tail(
  self : Pagination,
  old : PaginationCache,
  position : PagePosition,
  images : Images,
) -> Unit raise @failure.Failure {
  let end = old.positions.last().unwrap()
  let count = self.count + end.count - position.count
  guard count <= 32768 &&
    self.pages.length() + old.pages.length() - position.page - 1 <=
    1024 * self.columns.count else {
    @failure.reject(
      "limit-exceeded", "Reused layout exceeds page or line budget",
    )
  }
  let page = old.pages[position.page]
  let tail : PageFrame = {
    ..page,
    lines: page.lines[position.lines:]
    .to_owned()
    .map(line => line.copy_geometry()),
    borders: page.borders[position.borders:].to_owned(),
    fills: page.fills[position.fills:].to_owned(),
    cellAreas: page.cellAreas[position.cellAreas:]
    .to_owned()
    .map(area => area.copy_geometry()),
  }
  tail.validate_images(images)
  let current = self.pages.last().unwrap()
  current.lines.append(tail.lines)
  current.borders.append(tail.borders)
  current.fills.append(tail.fills)
  current.cellAreas.append(tail.cellAreas)
  for index in (position.page + 1)..<old.pages.length() {
    let page = old.pages[index].copy_geometry()
    page.validate_images(images)
    self.pages.push(page)
  }
  self.page = self.page_at(self.pages.length() - 1)
  self.y = end.y
  self.after = end.after
  self.gap = end.gap
  self.count = count
  self.active_table = end.table
}

///|
fn PaginationCache::bounded(
  context : String,
  keys : Array[String],
  positions : Array[PagePosition],
  pages : Array[PageFrame],
) -> Bool {
  let mut units = context.length() +
    positions.length() * 11 +
    pages.length() * 2
  for position in positions {
    units += position.tableWidths.length()
  }
  for key in keys {
    units += key.length()
  }
  if units > 1048576 {
    return false
  }
  for page in pages {
    units += paragraph_cache_units("", page.lines) + page.borders.length() * 6
    for fill in page.fills {
      units += 4 + fill.color.length()
    }
    for area in page.cellAreas {
      units += 4 + area.paragraphs.length()
    }
    if units > 1048576 {
      return false
    }
  }
  true
}

///|
fn translated_position(
  position : PagePosition,
  old : PagePosition,
  current : PagePosition,
) -> PagePosition {
  let same_page = position.page == old.page
  {
    ..position,
    page: position.page + current.page - old.page,
    count: position.count + current.count - old.count,
    lines: position.lines +
    (if same_page { current.lines - old.lines } else { 0 }),
    borders: position.borders +
    (if same_page { current.borders - old.borders } else { 0 }),
    fills: position.fills +
    (if same_page { current.fills - old.fills } else { 0 }),
    cellAreas: position.cellAreas +
    (if same_page { current.cellAreas - old.cellAreas } else { 0 }),
  }
}
