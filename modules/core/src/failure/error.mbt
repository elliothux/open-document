///|
pub(all) suberror Failure {
  Failure(code~ : String, part~ : String, offset~ : Int, message~ : String)
}

///|
pub fn[T] reject(
  code : String,
  message : String,
  part? : String = "",
  offset? : Int = -1,
) -> T raise Failure {
  raise Failure(code~, part~, offset~, message~)
}
