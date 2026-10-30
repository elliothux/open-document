///|
pub(all) struct ParagraphFrame {
  width : Double
  height : Double
  heightRule : String
  horizontalAnchor : String
  verticalAnchor : String
  x : Double?
  y : Double?
  horizontalAlign : String
  verticalAlign : String
  horizontalSpace : Double
  verticalSpace : Double
  borders : Map[String, (Double, BorderStyle)]
} derive(ToJson)

///|
pub extend ParagraphFrame with ToJson::{to_json}

///|
fn ParagraphFrame::group_key(self : ParagraphFrame) -> String {
  let value = self.to_json()
  if value is Object(fields) {
    fields.remove("borders")
  }
  value.stringify()
}

///|
fn BodyBlock::frame(self : BodyBlock) -> ParagraphFrame? {
  match self {
    BodyParagraph(p) => p.frame
    TableStart(table) =>
      table.rows
      .last()
      .bind(row => row.get(0))
      .bind(cell => cell.get(0))
      .bind(p => p.frame)
    _ => None
  }
}

///|
fn framed_blocks(blocks : Array[BodyBlock]) -> Array[BodyBlock] {
  let result : Array[BodyBlock] = []
  let mut index = 0
  while index < blocks.length() {
    guard blocks[index].frame() is Some(frame) else {
      result.push(blocks[index])
      index += 1
      continue
    }
    let group : Array[BodyBlock] = []
    while index < blocks.length() &&
          blocks[index].frame().map(f => f.group_key()) ==
          Some(frame.group_key()) {
      if !group.is_empty() &&
        blocks[index] is BodyParagraph({ pageBreakBefore: true, .. }) {
        break
      }
      let table = blocks[index] is TableStart(_)
      group.push(blocks[index])
      index += 1
      if table {
        while index < blocks.length() {
          let end = blocks[index] is TableEnd(_)
          group.push(blocks[index])
          index += 1
          if end {
            break
          }
        }
      }
    }
    result.push(FramedBlocks(frame, group))
  }
  result
}
