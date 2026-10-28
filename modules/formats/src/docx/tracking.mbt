///|
fn WordTree::has_review_markup(self : WordTree, paragraph : Int32) -> Bool {
  if !self.nodes.contains(paragraph) {
    return false
  }
  self
  .descendants(paragraph)
  .any(id => {
    self.nodes[id].uri == word_uri &&
    ["ins", "del", "rPrChange", "pPrChange"].contains(self.nodes[id].name)
  })
}

///|
/// Returns this session's recording mode; author identity is supplied by the host.
pub fn Session::tracking(
  self : Session,
  revision : Int32,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  {
    "revision": revision,
    "enabled": self.tracking_context is Some(_),
    "author": self.tracking_context.map(context => context.0).unwrap_or(""),
    "reason": try {
      self.check_document_protection()
      ""
    } catch {
      @failure.Failure(message~, ..) => message
    },
  }
}

///|
/// Enables or disables text revision recording without changing the document or history.
pub fn Session::track_changes(
  self : Session,
  revision : Int32,
  author : String?,
  date : String,
) -> Json raise @failure.Failure {
  self.check_revision(revision)
  if author is Some(author) {
    revision_author(author, date)
    self.check_document_protection()
  }
  self.tracking_context = author.map(author => (author, date))
  self.input_group = None
  self.typing_text = None
  self.tracking(revision)
}

///|
/// Refreshes host time for the next recorded transaction; source remains unchanged.
pub fn Session::tracking_clock(
  self : Session,
  date : String,
) -> Unit raise @failure.Failure {
  ignore(self.document())
  if self.tracking_context is Some((author, _)) {
    check_comment_date(date)
    self.tracking_context = Some((author, date))
  }
}
