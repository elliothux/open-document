///|
fn resized_rgba(
  image : @layout.ImageResource,
  width : Int32,
  height : Int32,
) -> Bytes raise {
  guard width >= 1 &&
    width <= image.width &&
    height >= 1 &&
    height <= image.height else {
    @failure.reject(
      "invalid-image", "PDF image downsampling requires bounded smaller dimensions",
    )
  }
  if width == image.width && height == image.height {
    return image.rgba
  }
  @pdfcore.sdk_decoded(width * height * 4)
  let output : Array[Byte] = Array::make(width * height * 4, 0)
  let dx = image.width.to_double() / width.to_double()
  let dy = image.height.to_double() / height.to_double()
  for y in 0..<height {
    let top = y.to_double() * dy
    let bottom = (y + 1).to_double() * dy
    for x in 0..<width {
      let left = x.to_double() * dx
      let right = (x + 1).to_double() * dx
      let sums = [0.0, 0.0, 0.0, 0.0]
      let mut area = 0.0
      for sy in top.floor().to_int()..<bottom.ceil().to_int().min(image.height) {
        let wy = bottom.min((sy + 1).to_double()) - top.max(sy.to_double())
        for sx in left.floor().to_int()..<right.ceil().to_int().min(image.width) {
          @pdfcore.sdk_check(1)
          let weight = wy *
            (right.min((sx + 1).to_double()) - left.max(sx.to_double()))
          let source = (sy * image.width + sx) * 4
          let alpha = image.rgba[source + 3].to_int().to_double() * weight
          for channel in 0..<3 {
            sums[channel] += image.rgba[source + channel].to_int().to_double() *
              alpha
          }
          sums[3] += alpha
          area += weight
        }
      }
      let target = (y * width + x) * 4
      for channel in 0..<3 {
        output[target + channel] = if sums[3] > 0 {
          (sums[channel] / sums[3]).round().to_int().max(0).min(255).to_byte()
        } else {
          0
        }
      }
      output[target + 3] = (sums[3] / area)
        .round()
        .to_int()
        .max(0)
        .min(255)
        .to_byte()
    }
  }
  Bytes::from_array(output)
}

///|
fn fitted_image_size(
  width : Int32,
  height : Int32,
  scale : Double,
) -> (Int32, Int32) {
  let scale = scale
    .min(@layout.ImageDimension.to_double() / width.to_double())
    .min(@layout.ImageDimension.to_double() / height.to_double())
  (
    (width.to_double() * scale).floor().to_int().max(1),
    (height.to_double() * scale).floor().to_int().max(1),
  )
}

///|
fn ContentContext::fit_image_budget(self : ContentContext) -> Int32 raise {
  let mut fixed = 0L
  let mut resizable = 0L
  let mut oversized = false
  let mut flateSamples = 0L
  let limit = (@layout.ImageBytes / 4).to_int64()
  for key in self.imageKeys {
    if self.jpeg.get(key) is Some(image) {
      let pixels = image.width.to_int64() * image.height.to_int64()
      if image.flateMask is Some(_) {
        flateSamples += pixels
      }
      if image.alpha is None {
        resizable += pixels
        oversized = oversized ||
          pixels > limit ||
          image.width > @layout.ImageDimension ||
          image.height > @layout.ImageDimension
      } else {
        fixed += pixels
      }
    } else if self.flateImages.get(key) is Some(image) {
      let pixels = image.width.to_int64() * image.height.to_int64()
      resizable += pixels
      flateSamples += pixels *
        (image.channels + (if image.mask is Some(_) { 1 } else { 0 })).to_int64()
      oversized = oversized ||
        pixels > limit ||
        image.width > @layout.ImageDimension ||
        image.height > @layout.ImageDimension
    } else {
      fixed += (self.images.get(key).rgba.length() / 4).to_int64()
    }
  }
  // These samples are streamed through two rows, so bound inflation by work.
  guard flateSamples <= self.session.budget.steps.to_int64() * 16L else {
    @failure.reject("limit-exceeded", "PDF page Flate samples exceed budget")
  }
  let scale = if !oversized && fixed + resizable <= limit {
    1.0
  } else {
    // Preserve room for a second view when the page uses resized images.
    let available = (limit - fixed).min(limit / 2L)
    guard available > 0L && resizable > 0L else {
      @failure.reject("limit-exceeded", "PDF page decoded images exceed budget")
    }
    (available.to_double() / resizable.to_double()).sqrt().min(1.0)
  }
  let mut pixels = fixed
  for key in self.imageKeys {
    if self.jpeg.get(key) is Some(image) && image.alpha is None {
      let (width, height) = fitted_image_size(image.width, image.height, scale)
      let (width, height) = if image.flateMask is Some(_) &&
        (width, height) != (image.width, image.height) &&
        width.to_int64() * height.to_int64() * 12 >
        @layout.ImageBytes.to_int64() {
        let tap_scale = ((@layout.ImageBytes / 12).to_double() /
        (image.width.to_double() * image.height.to_double())).sqrt()
        fitted_image_size(image.width, image.height, scale.min(tap_scale))
      } else {
        (width, height)
      }
      pixels += width.to_int64() * height.to_int64()
      if (width, height) != (image.width, image.height) {
        self.jpeg[key] = { ..image, preview: Some((width, height)), }
      }
    } else if self.flateImages.get(key) is Some(image) {
      let (width, height) = fitted_image_size(image.width, image.height, scale)
      if (width, height) != (image.width, image.height) {
        self.flateImages[key] = { ..image, preview: Some((width, height)), }
        pixels += width.to_int64() * height.to_int64()
        continue
      }
      self.flateImages.remove(key)
      try image.raster(width, height) catch {
        @failure.Failure(code="invalid-pdf", message~, ..) => {
          self.displayComplete = false
          self.diagnostics.push(message)
          self.images.add(key, 1, 1, b"\x00\x00\x00\x00")
          pixels += 1L
        }
        error => raise error
      } noraise {
        rgba => {
          self.images.add(key, width, height, rgba)
          pixels += width.to_int64() * height.to_int64()
        }
      }
    }
  }
  guard pixels <= limit else {
    @failure.reject("limit-exceeded", "PDF page decoded images exceed budget")
  }
  (pixels * 4L).to_int()
}
