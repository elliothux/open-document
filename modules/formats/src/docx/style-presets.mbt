///|
fn heading_style_properties(level : Int) -> (String, String) {
  let size = [32, 28, 26, 24, 22, 22, 22, 22, 22][level - 1]
  (
    "<od:pPr xmlns:od=\"\{word_uri}\"><od:outlineLvl od:val=\"\{level - 1}\"/></od:pPr>",
    "<od:rPr xmlns:od=\"\{word_uri}\"><od:b/><od:sz od:val=\"\{size}\"/></od:rPr>",
  )
}

///|
fn builtin_style_properties(
  key : String,
  name : String,
  kind : String,
  themes : Map[String, String],
) -> (String, String)? {
  let name = name.to_lower()
  let preset = [
      ("NoSpacing", "no spacing", "paragraph"),
      ("Quote", "quote", "paragraph"),
      ("QuoteChar", "quote char", "character"),
      ("SubtleEmphasis", "subtle emphasis", "character"),
      ("IntenseEmphasis", "intense emphasis", "character"),
      ("IntenseQuoteChar", "intense quote char", "character"),
      ("Caption", "caption", "paragraph"),
      ("Hyperlink", "hyperlink", "character"),
      ("FollowedHyperlink", "followedhyperlink", "character"),
      ("Title", "title", "paragraph"),
      ("TitleChar", "title char", "character"),
      ("Subtitle", "subtitle", "paragraph"),
      ("SubtitleChar", "subtitle char", "character"),
    ]
    .iter()
    .find_first(p => kind == p.2 && (key == p.0 || name == p.1))
  guard preset is Some((key, _, _)) else { return None }
  let paragraph = match key {
    "Title" =>
      "<od:pPr xmlns:od=\"\{word_uri}\"><od:spacing od:after=\"80\" od:line=\"240\" od:lineRule=\"auto\"/><od:contextualSpacing/></od:pPr>"
    "Subtitle" =>
      "<od:pPr xmlns:od=\"\{word_uri}\"><od:numPr><od:ilvl od:val=\"1\"/></od:numPr></od:pPr>"
    "NoSpacing" =>
      "<od:pPr xmlns:od=\"\{word_uri}\"><od:spacing od:after=\"0\" od:line=\"240\" od:lineRule=\"auto\"/></od:pPr>"
    "Quote" =>
      "<od:pPr xmlns:od=\"\{word_uri}\"><od:spacing od:before=\"160\"/><od:jc od:val=\"center\"/></od:pPr>"
    "Caption" =>
      "<od:pPr xmlns:od=\"\{word_uri}\"><od:spacing od:after=\"200\" od:line=\"240\" od:lineRule=\"auto\"/></od:pPr>"
    _ => ""
  }
  if key == "Title" || key == "TitleChar" {
    return Some(
      (
        paragraph,
        "<od:rPr xmlns:od=\"\{word_uri}\"><od:rFonts od:ascii=\"Arial\" od:hAnsi=\"Arial\" od:eastAsia=\"Arial\" od:cs=\"Arial\"/><od:spacing od:val=\"-10\"/><od:sz od:val=\"56\"/><od:szCs od:val=\"56\"/></od:rPr>",
      ),
    )
  }
  let (color, theme, transform) = match key {
    "Hyperlink" => ("0563C1", "hlink", "")
    "FollowedHyperlink" => ("954F72", "folHlink", "")
    "Caption" => ("0E2841", "text2", "")
    "Subtitle" | "SubtitleChar" => ("595959", "text1", " od:themeTint=\"A6\"")
    "IntenseEmphasis" | "IntenseQuoteChar" =>
      ("0F4761", "accent1", " od:themeShade=\"BF\"")
    _ => ("404040", "text1", " od:themeTint=\"BF\"")
  }
  let character = if key == "NoSpacing" {
    ""
  } else {
    if !themes.is_empty() && !themes.contains(theme) {
      return None
    }
    // shortcut: Missing themes use preset RGB; reset again after adding a theme to bind it.
    let theme = if themes.contains(theme) {
      let name = match theme {
        "hlink" => "hyperlink"
        "folHlink" => "followedHyperlink"
        name => name
      }
      " od:themeColor=\"\{name}\"" + transform
    } else {
      ""
    }
    let size = match key {
      "Caption" => "<od:sz od:val=\"18\"/><od:szCs od:val=\"18\"/>"
      "Subtitle" | "SubtitleChar" =>
        "<od:spacing od:val=\"15\"/><od:sz od:val=\"28\"/><od:szCs od:val=\"28\"/>"
      _ => ""
    }
    let decoration = if key == "Hyperlink" || key == "FollowedHyperlink" {
      "<od:u od:val=\"single\"/>"
    } else if key == "Subtitle" || key == "SubtitleChar" {
      ""
    } else {
      "<od:i/><od:iCs/>"
    }
    "<od:rPr xmlns:od=\"\{word_uri}\">\{decoration}<od:color od:val=\"\{color}\"\{theme}/>\{size}</od:rPr>"
  }
  Some((paragraph, character))
}
