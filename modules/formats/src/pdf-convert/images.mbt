///|
fn image_box(
  image : @pdf.PdfExtractedImage,
) -> (Double, Double, Double, Double, Double) raise @failure.Failure {
  let transform = image.transform
  let width = (transform.a * transform.a + transform.b * transform.b).sqrt()
  let height = (transform.c * transform.c + transform.d * transform.d).sqrt()
  guard width > 0 &&
    height > 0 &&
    transform.a * transform.d - transform.b * transform.c > 0 &&
    (transform.a * transform.c + transform.b * transform.d).abs() <=
    width * height * 0.001 else {
    @failure.reject(
      "conversion-unavailable", "Skewed or mirrored images require explicit reconstruction",
    )
  }
  let (cx, cy) = transform.point(0.5, 0.5)
  (
    cx - width / 2,
    cy - height / 2,
    width,
    height,
    @math.atan2(transform.b, transform.a) * 180 / 3.141592653589793,
  )
}

///|
fn image_bytes(image : @pdf.PdfExtractedImage) -> Bytes raise @failure.Failure {
  if image.rgba.length() > 0 {
    let pixels = if image.opacity == 1 {
      image.rgba
    } else {
      Bytes::makei(image.rgba.length(), index => {
        if index % 4 == 3 {
          (image.rgba[index].to_int().to_double() * image.opacity)
          .round()
          .to_int()
          .to_byte()
        } else {
          image.rgba[index]
        }
      })
    }
    @image.encode_png(image.pixelWidth, image.pixelHeight, pixels)
  } else if image.jpeg is Some(bytes) && image.opacity == 1 {
    bytes
  } else {
    @failure.reject(
      "conversion-unavailable", "Source image requires platform decoding before conversion",
    )
  }
}
