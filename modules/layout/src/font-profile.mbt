///|
/// Resolves an exact font mapping, then an explicitly supplied style fallback.
pub fn font_profile_identity(
  profile : Map[String, String],
  key : String,
) -> String? {
  if profile.get(key) is Some(identity) {
    return Some(identity)
  }
  let parts = key.split("|").to_array()
  let fallback = "*" +
    (if parts.contains("bold") { "|bold" } else { "" }) +
    (if parts.contains("italic") { "|italic" } else { "" })
  if profile.get(fallback) is Some(identity) {
    Some(identity)
  } else {
    profile.get("*")
  }
}
