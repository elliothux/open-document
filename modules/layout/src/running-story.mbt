///|
/// Header and footer content uses the same paragraphs and tables as the body.
/// ```mbt check
/// test "Running story transformations retain empty source order" {
///   let story : @layout.RunningStory = { paragraphs: [], tables: [], }
///   assert_eq(story.all_paragraphs().length(), 0)
///   assert_eq(story.map_paragraphs(p => p).all_paragraphs().length(), 0)
/// }
/// ```
#derive(ToJson)
pub(all) struct RunningStory {
  paragraphs : Array[Paragraph]
  tables : Array[Table]
}

///|
pub extend RunningStory with ToJson::{to_json}

///|
/// Paragraphs in source order, including nested table cells and text boxes.
pub fn RunningStory::all_paragraphs(self : RunningStory) -> Array[Paragraph] {
  let result = []
  let mut index = 0
  for table in self.tables {
    while index < self.paragraphs.length() && index < table.beforeParagraph {
      result.push(self.paragraphs[index])
      index += 1
    }
    result.append(table.paragraphs())
  }
  result.append(self.paragraphs[index:].to_owned())
  let expanded = []
  for paragraph in result {
    expanded.push(paragraph)
    for span in paragraph.spans {
      if span.drawing is Some({ content: TextBox(_, text), .. }) {
        expanded.append(text.paragraphs)
      }
    }
  }
  expanded
}

///|
/// Applies field resolution and source identities to every paragraph in a story.
pub fn RunningStory::map_paragraphs(
  self : RunningStory,
  transform : (Paragraph) -> Paragraph raise @failure.Failure,
) -> RunningStory raise @failure.Failure {
  let map_paragraph = fn(
    paragraph : Paragraph,
  ) -> Paragraph raise @failure.Failure {
    let paragraph = transform(paragraph)
    {
      ..paragraph,
      spans: paragraph.spans.map(span => {
        if span.drawing is Some({ content: TextBox(shape, text), .. } as frame) {
          let paragraphs = text.paragraphs.map(transform)
          let bottomBorders : Map[Int32, (Double, BorderStyle)] = Map([])
          for index, original in text.paragraphs {
            if text.bottomBorders.get(original.id) is Some(border) {
              bottomBorders[paragraphs[index].id] = border
            }
          }
          {
            ..span,
            drawing: Some({
              ..frame,
              content: TextBox(shape, { ..text, paragraphs, bottomBorders, }),
            }),
          }
        } else {
          span
        }
      }),
    }
  }
  {
    paragraphs: self.paragraphs.map(map_paragraph),
    tables: self.tables.map(table => table.map_paragraphs(map_paragraph)),
  }
}
