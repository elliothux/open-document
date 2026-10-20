///|
fn word_art_markup(
  id : String,
  preset : String,
  text : String,
  x : Double,
  y : Double,
  width : Double,
  height : Double,
) -> String raise @failure.Failure {
  let color = match preset {
    "blue" => "4472C4"
    "gold" => "FFC000"
    "red" => "C00000"
    "purple" => "7030A0"
    "green-italic" => "70AD47"
    _ => @failure.reject("invalid-operation", "Unknown solid WordArt preset")
  }
  guard !text.trim().is_empty() else {
    @failure.reject("invalid-operation", "WordArt text must not be empty")
  }
  let markup = object_markup(id, "text", x, y, width, height, text)
  let body = object_text_markup(
      text,
      style="<a:solidFill><a:srgbClr val=\"\{color}\"/></a:solidFill><a:latin typeface=\"Arial\"/>",
      attributes="sz=\"5400\" b=\"1\" i=\"\{if preset == "green-italic" { 1 } else { 0 }}\"",
    )
    .replace_all(old="<a:pPr>", new="<a:pPr algn=\"ctr\">")
    .replace_all(
      old="<a:bodyPr wrap=\"square\" anchor=\"t\"><a:noAutofit/></a:bodyPr>",
      new="<a:bodyPr wrap=\"none\" anchor=\"ctr\"><a:spAutoFit/></a:bodyPr>",
    )
  markup
  .replace_all(
    old="<p:cNvPr id=\"\{id}\" name=\"text \{id}\"/>",
    new="<p:cNvPr id=\"\{id}\" name=\"WordArt \{id}\"/>",
  )
  .replace_all(old=object_text_markup(text), new=body)
}

///|
fn Session::insert_word_art(
  self : Session,
  preset : String,
  text : String,
  probe : @layout.TextProbe,
  profile : Map[String, String],
) -> Json raise @failure.Failure {
  let slide = self.current()
  let id = self.next_object_identity()
  let identity = slide.tree.part + "#" + id
  let initial = word_art_markup(id, preset, text, 0, 0, 354.6, 72.7)
  let (trial, _) = self.prepare(slide, [object_insertion(slide.tree, initial)])
  let geometry = resize_text_frame(trial.object(identity), probe, profile)
  let markup = word_art_markup(
    id,
    preset,
    text,
    (self.width - geometry.width) / 2,
    (self.height - geometry.height) / 2,
    geometry.width,
    geometry.height,
  )
  let (candidate, edit) = self.prepare(slide, [
    object_insertion(slide.tree, markup),
  ])
  self.commit(
    candidate,
    edit,
    {
      ..self.selection,
      object: identity,
      objects: [identity],
      mode: "text",
      anchor: 0,
      focus: text.length(),
    },
    probe~,
    profile~,
  )
  self.object_sequence = number(id, 1, 4294967295).to_int64() + 1
  self.query()
}
