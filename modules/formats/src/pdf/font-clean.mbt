///|
/// Canonical redaction font: only necessary flattened glyph geometry, metrics
/// and original licensing survive. Source programs, table slack and identities
/// never enter this builder. Ordinary exports continue to use the subsetter.
fn clean_font(
  subset : FontSubset,
  source : Bytes,
  index : Int32,
  info : @layout.FontInfo,
  probe : @layout.TextProbe,
) -> Bytes raise {
  guard font_table(source, 0x4f532f32U) is Some(policy) &&
    policy.length() >= 78 &&
    (font_short(policy, 8) & 0x0302) == 0 else {
    raise @pdfcore.HardError("Original font does not permit clean embedding")
  }
  let ids = subset.remap.remapped_gids()
  guard ids.length() > 0 && ids.length() <= 65535 else {
    raise @pdfcore.HardError("Clean font glyph budget exceeded")
  }
  let glyf : Array[Byte] = []
  let loca : Array[Byte] = Array::make((ids.length() + 1) * 4, 0)
  let hmtx : Array[Byte] = Array::make(ids.length() * 4, 0)
  let bounds = [0, 0, 0, 0]
  let mut maxPoints = 0
  let mut maxContours = 0
  let mut maxAdvance = 0
  let mut hasInk = false
  for target, gid in ids {
    font_put_word(loca, target * 4, glyf.length().reinterpret_as_uint())
    let needed = gid != 0 ||
      subset.cids.any(cid => cid.glyph == 0 && !cid.text.is_empty())
    let contours = if needed {
      probe.source_glyph_contours(index, gid.reinterpret_as_uint())
    } else {
      []
    }
    let (bytes, box, points, contourCount) = clean_glyph(contours)
    if !bytes.is_empty() {
      if !hasInk {
        for i in 0..<4 {
          bounds[i] = box[i]
        }
        hasInk = true
      } else {
        bounds[0] = bounds[0].min(box[0])
        bounds[1] = bounds[1].min(box[1])
        bounds[2] = bounds[2].max(box[2])
        bounds[3] = bounds[3].max(box[3])
      }
    }
    maxPoints = maxPoints.max(points)
    maxContours = maxContours.max(contourCount)
    glyf.append(bytes.to_array())
    if glyf.length() % 2 != 0 {
      glyf.push(0)
    }
    let advance = (probe.glyph_width(index, gid.reinterpret_as_uint()) *
      info.upem.to_double() /
      1000)
      .round()
      .to_int()
    guard advance >= 0 && advance <= 65535 else {
      raise @pdfcore.HardError("Clean glyph advance exceeds range")
    }
    maxAdvance = maxAdvance.max(advance)
    font_put_short(hmtx, target * 4, advance)
    font_put_short(hmtx, target * 4 + 2, box[0])
    guard glyf.length() <= 8388608 else {
      raise @pdfcore.HardError("Clean font geometry exceeds budget")
    }
  }
  font_put_word(loca, ids.length() * 4, glyf.length().reinterpret_as_uint())
  let head : Array[Byte] = Array::make(54, 0)
  font_put_word(head, 0, 0x00010000U)
  font_put_word(head, 4, 0x00010000U)
  font_put_word(head, 12, 0x5f0f3cf5U)
  font_put_short(head, 18, info.upem)
  for i in 0..<4 {
    font_put_short(head, 36 + i * 2, bounds[i])
  }
  font_put_short(head, 46, 8)
  font_put_short(head, 48, 2)
  font_put_short(head, 50, 1)
  let hhea : Array[Byte] = Array::make(36, 0)
  font_put_word(hhea, 0, 0x00010000U)
  font_put_short(hhea, 4, info.ascent)
  font_put_short(hhea, 6, -info.descent)
  font_put_short(hhea, 10, maxAdvance)
  font_put_short(hhea, 18, 1)
  font_put_short(hhea, 34, ids.length())
  let maxp : Array[Byte] = Array::make(32, 0)
  font_put_word(maxp, 0, 0x00010000U)
  font_put_short(maxp, 4, ids.length())
  font_put_short(maxp, 6, maxPoints)
  font_put_short(maxp, 8, maxContours)
  font_put_short(maxp, 14, 1)
  let post : Array[Byte] = Array::make(32, 0)
  font_put_word(post, 0, 0x00030000U)
  let angle = (info.italicAngle * 65536).round().to_int()
  font_put_word(post, 4, angle.reinterpret_as_uint())
  let os2 : Array[Byte] = Array::make(78, 0)
  let (bold, italic) = probe.font_style(index)
  font_put_short(os2, 4, if bold { 700 } else { 400 })
  font_put_short(os2, 6, 5)
  font_put_short(os2, 8, font_short(policy, 8))
  font_put_short(
    os2,
    62,
    (if italic { 1 } else { 0 }) | (if bold { 32 } else { 64 }),
  )
  font_put_short(os2, 64, 65535)
  font_put_short(os2, 66, 65535)
  font_put_short(os2, 68, info.ascent)
  font_put_short(os2, 70, -info.descent)
  font_put_short(os2, 74, info.ascent.max(0))
  font_put_short(os2, 76, info.descent.max(0))
  font_construct([
    (0x68656164U, Bytes::from_array(head)),
    (0x68686561U, Bytes::from_array(hhea)),
    (0x6d617870U, Bytes::from_array(maxp)),
    (0x686d7478U, Bytes::from_array(hmtx)),
    (0x6c6f6361U, Bytes::from_array(loca)),
    (0x676c7966U, Bytes::from_array(glyf)),
    (0x706f7374U, Bytes::from_array(post)),
    (0x6e616d65U, clean_font_names(source)),
    (0x4f532f32U, Bytes::from_array(os2)),
  ])
}
