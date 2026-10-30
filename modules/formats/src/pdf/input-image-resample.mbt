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
