///|
/// Returns the same committed pages as PDF without changing the editing layout.
pub fn Session::print_drawing(
  self : Session,
  revision : Int,
  all : Bool,
  hidden : Bool,
  probe : @layout.TextProbe,
  profile : Map[String, String],
  images : @layout.Images,
) -> Json raise @failure.Failure {
  let document = self.print_layout(revision, all, hidden, probe, profile)
  let resources : Array[String] = []
  for key in self.image_keys(all, hidden) {
    let identity = images.get(key).identity
    if !resources.contains(identity) {
      resources.push(identity)
    }
  }
  {
    "revision": self.revision,
    "regions": document.drawing(images),
    "outlines": probe.outline_resources(),
    "images": resources,
  }
}
