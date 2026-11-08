// Copyright 2019 The PDFium Authors
// Original code copyright 2014 Foxit Software Inc.
// Adapted from core/fxge/dib/cfx_cmyk_to_srgb.cpp, BSD-3-Clause; full terms in packages/wasm/NOTICE.

///|
fn cmyk_rgb(values : Array[Double]) -> Array[Double] {
  let fixed = values.map(value => {
    (value.max(0).min(1) * 255).round().to_int() << 8
  })
  let indices = fixed.map(value => (value + 4096) >> 13)
  let strides = [729, 81, 9, 1]
  let origin = indices
    .mapi((index, value) => value * strides[index])
    .fold(init=0, (sum, value) => sum + value) *
    3
  let result = Array::makei(3, channel => {
    cmyk_samples[origin + channel].to_int() << 8
  })
  for component in 0..<4 {
    let lower = fixed[component] >> 13
    let neighbor = if lower != indices[component] {
      lower
    } else if lower == 8 {
      7
    } else {
      lower + 1
    }
    let offset = origin +
      (neighbor - indices[component]) * strides[component] * 3
    let rate = (fixed[component] - (indices[component] << 13)) *
      (indices[component] - neighbor)
    for channel in 0..<3 {
      result[channel] += (
          cmyk_samples[origin + channel].to_int() -
          cmyk_samples[offset + channel].to_int()
        ) *
        rate /
        32
    }
  }
  result.map(value => (value.max(0) >> 8).min(255).to_double() / 255)
}

///|
fn cmyk_pixels(
  context : ContentContext,
  key : String,
  bytes : Bytes,
  width : Int32,
  height : Int32,
  transform : Int32?,
  blocks : Int32,
  decode : Array[Double],
  alpha : Bytes?,
  matte : Array[Double]?,
) -> Unit raise {
  guard transform is (None | Some(0 | 2)) else {
    @failure.reject(
      "unsupported-pdf", "Unsupported four-component JPEG transform",
    )
  }
  // Charge bounded marker, Huffman, IDCT, plane and output work before entering the codec.
  let work = bytes.length().to_int64() * 2 +
    blocks.to_int64() * 2048 +
    width.to_int64() * height.to_int64() * 4
  guard work <= 2147483647L else {
    @failure.reject("limit-exceeded", "JPEG work exceeds budget")
  }
  @pdfcore.sdk_check(work.to_int())
  @pdfcore.sdk_decoded(bytes.length() * 2 + blocks * 64 + width * height * 12)
  let (decoded_width, decoded_height, samples) = @jpeg.decode_cmyk_jpeg(bytes) catch {
    Failure::Failure(message) => @failure.reject("invalid-image", message)
  }
  guard (decoded_width, decoded_height) == (width, height) &&
    samples.length() == width * height * 4 else {
    @failure.reject("invalid-image", "JPEG samples do not match PDF dimensions")
  }
  context.images.add(
    key,
    width,
    height,
    cmyk_rgba(samples, width * height, transform, decode, alpha, matte),
  )
}

///|
fn cmyk_rgba(
  samples : Bytes,
  pixels : Int32,
  transform : Int32?,
  decode : Array[Double],
  alpha : Bytes?,
  matte : Array[Double]?,
) -> Bytes {
  let rgba : Array[Byte] = Array::make(pixels * 4, 0)
  for pixel in 0..<pixels {
    let at = pixel * 4
    let components = Array::makei(4, channel => {
      samples[at + channel].to_int().to_double()
    })
    if transform == Some(2) {
      let y = components[0]
      let cb = components[1]
      let cr = components[2]
      components[0] = (434.456 - y - 1.402 * cr).round().max(0).min(255)
      components[1] = (119.541 - y + 0.344 * cb + 0.714 * cr)
        .round()
        .max(0)
        .min(255)
      components[2] = (481.816 - y - 1.772 * cb).round().max(0).min(255)
    }
    let opacity = alpha.map(mask => mask[pixel]).unwrap_or(255)
    let decoded = components.mapi((channel, value) => {
      let value = decoded_sample(
        value.to_int().to_byte(),
        decode[channel * 2],
        decode[channel * 2 + 1],
      )
      if matte is Some(matte) && alpha is Some(_) {
        unblend_sample(value, opacity, matte[channel]).to_int().to_double() /
        255
      } else {
        value.to_int().to_double() / 255
      }
    })
    let color = cmyk_rgb(decoded)
    for channel in 0..<3 {
      rgba[at + channel] = (color[channel] * 255).round().to_int().to_byte()
    }
    rgba[at + 3] = opacity
  }
  Bytes::from_array(rgba)
}
