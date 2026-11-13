///|
fn JpegImage::pixels(self : JpegImage, rgba : Bytes) -> Bytes raise {
  if self.flateMask is Some((source, decode)) {
    return self.masked_pixels(source, decode, rgba)
  }
  if self.alpha is None &&
    self.decode
    .mapi((index, value) => value == (index % 2).to_double())
    .all(value => value) {
    return icc_rgba(rgba, self.profile)
  }
  let channels = self.decode.length() / 2
  let output = Bytes::makei(rgba.length(), i => {
    let channel = i % 4
    if channel == 3 {
      self.alpha.map(mask => mask[i / 4]).unwrap_or(rgba[i])
    } else {
      let c = if channels == 1 { 0 } else { channel }
      let value = decoded_sample(
        rgba[i],
        self.decode[c * 2],
        self.decode[c * 2 + 1],
      )
      if self.matte is Some(matte) && self.alpha is Some(alpha) {
        unblend_sample(value, alpha[i / 4], matte[c])
      } else {
        value
      }
    }
  })
  icc_rgba(output, self.profile)
}

///|
fn JpegImage::core_pixels(
  self : JpegImage,
  budget : PdfBudget,
) -> Bytes? raise @failure.Failure {
  guard self.preview is None else { return None }
  let pixels = self.width.to_int64() * self.height.to_int64()
  let compressed = self.bytes.length().to_int64()
  let blocks = self.blocks.to_int64()
  let work = compressed * 2 + blocks * 2048 + pixels * 4
  let allocation = compressed * 2 + blocks * 256 + pixels * 12
  // Leave the source available to the host when the PDF budget cannot admit the codec.
  guard !@pdfcore.sdk_active() &&
    work <= budget.steps.to_int64() &&
    allocation <= budget.streamBytes.min(budget.decodedBytes).to_int64() else {
    return None
  }
  pdf_bound(budget, () => {
    @pdfcore.sdk_check(work.to_int())
    @pdfcore.sdk_decoded(allocation.to_int())
    guard @image.decode_plain_raster(self.bytes) is Some((width, height, rgba)) &&
      width == self.width &&
      height == self.height else {
      return None
    }
    Some(self.pixels(rgba))
  }) catch {
    @failure.Failure(code="limit-exceeded", ..) => None
    error => raise error
  }
}

///|
fn JpegImage::display_size(self : JpegImage) -> (Int32, Int32) {
  self.preview.unwrap_or((self.width, self.height))
}

///|
fn JpegImage::needs_source_samples(self : JpegImage) -> Bool {
  self.flateMask is Some(_) && self.preview is Some(_)
}
