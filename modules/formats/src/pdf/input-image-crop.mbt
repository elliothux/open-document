///|
pub(all) struct PdfImageCrop {
  x : Double
  y : Double
  width : Double
  height : Double
}

///|
fn check_image_crop(crop : PdfImageCrop) -> Unit raise @failure.Failure {
  guard crop.x >= 0 &&
    crop.y >= 0 &&
    crop.width > 0 &&
    crop.height > 0 &&
    crop.x + crop.width <= 1 &&
    crop.y + crop.height <= 1 else {
    @failure.reject(
      "invalid-position", "Image crop must be a nonempty window inside the image",
    )
  }
}

///|
fn cropped_image_placement(
  placement : PdfPlacement,
  crop : PdfImageCrop,
) -> PdfPlacement raise @failure.Failure {
  let (x, y) = source_placement_matrix(placement).point(
    crop.x * placement.width,
    crop.y * placement.height,
  )
  let result : PdfPlacement = {
    x,
    y,
    width: placement.width * crop.width,
    height: placement.height * crop.height,
    rotation: placement.rotation,
  }
  check_pdf_placement(result)
  result
}

///|
fn PdfTransaction::cropped_image_form(
  self : PdfTransaction,
  form : @syntax.PdfObject,
  placement : PdfPlacement,
  crop : PdfImageCrop,
) -> @syntax.PdfObject raise {
  let object = match form {
    PdfIndirect(number) => self.object(number)
    _ => form
  }
  let (x, y, r, t) = source_logical_box(self.session.document, object)
  let sx = placement.width / (r - x)
  let sy = placement.height / (t - y)
  let transform : @layout.Matrix = {
    a: sx,
    b: 0,
    c: 0,
    d: sy,
    e: -x * sx - placement.width * crop.x,
    f: -y * sy - placement.height * (1 - crop.y - crop.height),
  }
  let transform = transform.then(
    pdf_object_matrix(get(self.session.document, object, "Matrix")).inverse(),
  )
  let reference = self.add(
    appearance_stream(
      @pdflite.pdf_content_bytes_of_ops([
        @content.Op_q,
        @content.Op_cm(geometry_matrix(transform)),
        @content.Op_Do(pdf_name("Image")),
        @content.Op_Q,
      ]),
      placement.width * crop.width,
      placement.height * crop.height,
      dict([("XObject", dict([("Image", form)]))]),
    ),
  )
  guard reference is PdfIndirect(number) &&
    self.object(number) is PdfStreamObject(stream) else {
    abort("Expected cropped image Form")
  }
  self.objects[number] = @syntax.pdf_stream(
    stream.dictionary.with_entry(pdf_name("ODKind"), tag("Image")),
    stream.data,
  )
  reference
}

///|
/// Trim an image appearance without deleting its hidden pixels or encoded data.
/// Only the selected occurrence is rebound; this operation is not redaction.
pub fn PdfSession::crop_image(
  self : PdfSession,
  revision : Int32,
  pageId : String,
  id : String,
  crop : PdfImageCrop,
  supplied : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let tx = self.transaction(revision)
  check_image_crop(crop)
  let page = self.page(pageId)
  pdf_bound(self.budget, () => {
    if id.contains("/source/") {
      let display = self.build_display(
        page.id,
        supplied,
        profile,
        @layout.Images::new(),
      )
      defer display.probe.close()
      let target = source_checked_target(self, display, id)
      guard target.kind.has_prefix("image") else {
        @failure.reject("invalid-operation", "Choose an editable PDF image")
      }
      if crop.x == 0 && crop.y == 0 && crop.width == 1 && crop.height == 1 {
        return self.query()
      }
      let placement = source_placement(self, target)
      let original = tx.original_source_form(display, target)
      let cropped = tx.cropped_image_form(original, placement, crop)
      let (ops, resources) = tx.source_form_ops(
        target,
        cropped,
        cropped_image_placement(placement, crop),
      )
      tx.write_source_object(page, target, ops, resources)
    } else {
      let target = self.owned_object(page, id)
      guard target.kind == "image" else {
        @failure.reject("invalid-operation", "Choose an editable PDF image")
      }
      if crop.x == 0 && crop.y == 0 && crop.width == 1 && crop.height == 1 {
        return self.query()
      }
      let cropped = tx.cropped_image_form(target.form, target.placement, crop)
      tx.replace_owned(
        page,
        target,
        cropped,
        cropped_image_placement(target.placement, crop),
      )
    }
    tx.commit(self.current)
  })
}
