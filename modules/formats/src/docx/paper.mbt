///|
// Native DOCX page dimensions are exact integer twips. Do not snap them to a
// nearby paper preset: that changes page bounds and can change pagination.
fn page_dimension(twips : Double) -> Double {
  twips / 20
}
