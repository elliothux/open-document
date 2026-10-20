///|
pub(all) struct Caret {
  offset : Int
  before : Double
  after : Double
} derive(ToJson)

///|
pub extend Caret with ToJson::{to_json}

///|
fn TextProbe::shape_carets(
  self : TextProbe,
  text : String,
  glyphs : Array[Glyph],
  runs : Array[GlyphRun],
  controls : Array[Caret],
  tracking : Map[Int, Double],
  caret_units? : Double,
) -> Array[Caret] raise @failure.Failure {
  let boundaries = grapheme_boundaries(text)
  let groups : Map[Int, Array[Glyph]] = Map([])
  for glyph in glyphs {
    if groups.get(glyph.cluster) is Some(group) {
      group.push(glyph)
    } else {
      groups[glyph.cluster] = [glyph]
    }
  }
  for caret in controls {
    if !groups.contains(caret.offset) {
      groups[caret.offset] = []
    }
  }
  let offsets = groups.keys().collect()
  offsets.sort()
  let before : Map[Int, Double] = Map([])
  let after : Map[Int, Double] = Map([])
  for caret in controls {
    before[caret.offset] = caret.before
    after[caret.offset] = caret.after
  }
  for run in runs {
    let clusters = offsets.filter(offset => {
      offset >= run.start && offset < run.end
    })
    let mut correction = 0.0
    for index, start in clusters {
      let end = clusters.get(index + 1).unwrap_or(run.end)
      let cluster = groups[start]
      if cluster.is_empty() {
        continue
      }
      let first = cluster[0]
      let mut left = first.x - first.xOffset.to_double() * first.scale
      let mut right = left
      let mut base = first
      for glyph in cluster {
        let origin = glyph.x - glyph.xOffset.to_double() * glyph.scale
        left = left.min(origin)
        right = right.max(origin + glyph.advance.to_double() * glyph.scale)
        if glyph.advance > base.advance {
          base = glyph
        }
      }
      let edges = [
        start,
        ..boundaries.filter(offset => offset > start && offset < end),
        end,
      ]
      let count = edges.length() - 1
      right += tracking.get(start).unwrap_or(0)
      let carets = if count > 1 { self.ligature_carets(base) } else { [] }
      let width = right - left
      let ordered = for i in 1..<carets.length() {
        if carets[i] < carets[i - 1] {
          break false
        }
      } nobreak {
        true
      }
      let valid = tracking.get(start).unwrap_or(0) == 0 &&
        carets.length() == count - 1 &&
        carets.iter().all(x => x >= 0 && x <= width) &&
        ordered
      let units = if valid && count > 1 { caret_units } else { None }
      let adjusted_width = match units {
        Some(units) => (width * units).floor() / units
        None => width
      }
      // Writer accumulates integer reference-device GDEF component widths.
      let loss = width - adjusted_width
      if run.level % 2 == 0 {
        left -= correction
        right -= correction + loss
      } else {
        left += correction + loss
        right += correction
      }
      for i, offset in edges {
        let distance = if i == 0 {
          0.0
        } else if i == count {
          adjusted_width
        } else if valid {
          let distance = carets[if run.level % 2 == 0 {
              i - 1
            } else {
              count - i - 1
            }]
          match units {
            Some(units) => (distance * units).floor() / units
            None => distance
          }
        } else {
          // shortcut: fonts without matching ligature carets divide this cluster's advance; upgrade with a richer font caret contract.
          width * i.to_double() / count.to_double()
        }
        let x = if run.level % 2 == 0 {
          left + distance
        } else if valid && i > 0 && i < count {
          left + distance
        } else {
          right - distance
        }
        if boundaries.contains(offset) {
          if i < count {
            after[offset] = x
          }
          if i > 0 {
            before[offset] = x
          }
        }
      }
      correction += loss
    }
  }
  boundaries.map(offset => {
    let a = after.get(offset).unwrap_or(before.get(offset).unwrap_or(0))
    let b = before.get(offset).unwrap_or(a)
    { offset, before: b, after: a, }
  })
}
