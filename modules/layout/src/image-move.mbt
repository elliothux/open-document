///|
fn image_axis_origin(
  axis : DrawingAxis,
  horizontal : Bool,
  setup : PageSetup,
  frame : PageFrame,
  line : Line,
) -> Double {
  let reference = match axis {
    Offset(reference, _) | Aligned(reference, _) => reference
  }
  if reference == "page" {
    return 0
  }
  if reference == "margin" {
    return if horizontal { setup.left } else { setup.top }
  }
  if horizontal {
    return line.areaX
  }
  frame.lines
  .iter()
  .find_first(prior => {
    prior.paragraph == line.paragraph && prior.areaX == line.areaX
  })
  .map(prior => prior.y)
  .unwrap_or(line.y)
}

///|
/// Resolves a floating move from its original frame into a page's nearest text anchor.
/// Deltas use page-local points, so the same total displacement can target another page.
/// The optional hit changes the logical anchor across a paragraph, page or column.
pub fn Layout::move_drawing(
  self : Layout,
  setup : PageSetup,
  paragraph : Int,
  start : Int,
  dx : Double,
  dy : Double,
  page : Int,
) -> (DrawingAnchor, Hit?) raise @failure.Failure {
  setup.validate()
  guard !dx.is_nan() &&
    !dx.is_inf() &&
    !dy.is_nan() &&
    !dy.is_inf() &&
    dx.abs() <= 14400 &&
    dy.abs() <= 14400 else {
    @failure.reject("invalid-position", "Invalid picture movement delta")
  }
  guard self.pages.get(page) is Some(destination) else {
    @failure.reject("invalid-page", "Unknown picture movement page")
  }
  for source_page, frame in self.pages {
    for line in frame.lines {
      if line.paragraph != paragraph {
        continue
      }
      for image in line.drawings {
        guard image.start == start && image.anchor is Some(anchor) else {
          continue
        }
        if source_page == page && dx == 0 && dy == 0 {
          return (anchor, None)
        }
        let x = image.x + dx
        let y = image.y + dy
        let hit = self.hit_test(
          page,
          x.max(0).min(destination.width),
          y.max(0).min(destination.height),
          text_only=true,
        )
        guard hit.reason.is_empty() &&
          hit.page == page &&
          destination.lines.get(hit.line) is Some(target) &&
          target.paragraph == hit.paragraph &&
          target.cellClip is None else {
          @failure.reject(
            "protected-content", "Picture movement requires an editable body text position",
          )
        }
        let same_frame = source_page == page &&
          target.paragraph == paragraph &&
          target.areaX == line.areaX
        fn moved(axis : DrawingAxis, horizontal : Bool) -> DrawingAxis {
          let from = image_axis_origin(axis, horizontal, setup, frame, line)
          let to = image_axis_origin(
            axis, horizontal, setup, destination, target,
          )
          let delta = if horizontal { dx } else { dy }
          if delta == 0 && from == to {
            return axis
          }
          let reference = match axis {
            Offset(reference, _) | Aligned(reference, _) => reference
          }
          Offset(reference, (if horizontal { x } else { y }) - to)
        }
        return (
          {
            ..anchor,
            horizontal: moved(anchor.horizontal, true),
            vertical: moved(anchor.vertical, false),
          },
          if same_frame {
            None
          } else {
            Some(hit)
          },
        )
      }
    }
  }
  @failure.reject("invalid-image", "Floating picture has no placed frame")
}
