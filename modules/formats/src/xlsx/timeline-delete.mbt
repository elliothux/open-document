///|
/// Removes a native timeline view and its drawing while retaining the cached pivot filter.
pub fn Session::delete_timeline(
  self : Session,
  revision : Int,
  sheet : String,
  name : String,
) -> Json raise @failure.Failure {
  self.delete_analysis_view(revision, sheet, name, timeline=true)
}
