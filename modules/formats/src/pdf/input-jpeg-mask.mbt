///|
fn JpegImage::masked_pixels(
  self : JpegImage,
  source : @syntax.PdfObject,
  decode : Array[Double],
  samples : Bytes,
) -> Bytes raise {
  let (width, height) = self.display_size()
  let resize = self.needs_source_samples()
  let rows = FlateRows::new(source)
  @pdfcore.sdk_check(width * height)
  @pdfcore.sdk_decoded(2 * self.width + (width + height) * 24)
  @pdfcore.sdk_decoded(width * height * 4)
  let mut top = FixedArray::make(self.width, b'\x00')
  let mut bottom = FixedArray::make(self.width, b'\x00')
  let rgba = FixedArray::make(width * height * 4, b'\x00')
  let xs = Array::makei(width, x => image_sample(x, self.width, width))
  let ys = Array::makei(height, y => image_sample(y, self.height, height))
  let gray = self.decode.length() == 2
  let opacity = (row : FixedArray[Byte], x) => {
    decoded_sample(row[x], decode[0], decode[1])
  }
  let component = (at, channel, alpha) => {
    let c = if gray { 0 } else { channel }
    let value = decoded_sample(
      samples[at + channel],
      self.decode[c * 2],
      self.decode[c * 2 + 1],
    )
    match self.matte {
      Some(matte) => unblend_sample(value, alpha, matte[c])
      None => value
    }
  }
  let mut target_y = 0
  for y in 0..<self.height {
    let previous = top
    top = bottom
    bottom = previous
    rows.row(bottom.mut_view())
    if target_y >= height || ys[target_y].1 != y {
      continue
    }
    let (y0, _, dy) = ys[target_y]
    let upper = if y0 == y { bottom } else { top }
    for x, (x0, x1, dx) in xs {
      let at = (target_y * width + x) * 4
      let a = opacity(upper, x0)
      if !resize {
        for channel in 0..<3 {
          rgba[at + channel] = component(at, channel, a)
        }
        rgba[at + 3] = a
        continue
      }
      let b = opacity(upper, x1)
      let c = opacity(bottom, x0)
      let d = opacity(bottom, x1)
      let wa = (1.0 - dx) * (1.0 - dy) * a.to_int().to_double()
      let wb = dx * (1.0 - dy) * b.to_int().to_double()
      let wc = (1.0 - dx) * dy * c.to_int().to_double()
      let wd = dx * dy * d.to_int().to_double()
      let alpha = wa + wb + wc + wd
      rgba[at + 3] = alpha.round().to_int().min(255).to_byte()
      if alpha > 0 {
        let source_at = at * 3
        for channel in 0..<3 {
          let value = wa * component(source_at, channel, a).to_int().to_double() +
            wb * component(source_at + 3, channel, b).to_int().to_double() +
            wc * component(source_at + 6, channel, c).to_int().to_double() +
            wd * component(source_at + 9, channel, d).to_int().to_double()
          rgba[at + channel] = (value / alpha)
            .round()
            .to_int()
            .min(255)
            .to_byte()
        }
      }
    }
    target_y += 1
  }
  rows.finish()
  icc_rgba(Bytes::from_array(rgba), self.profile)
}
