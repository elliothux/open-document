///|
fn heading_style_properties(level : Int) -> (String, String) {
  let size = [32, 28, 26, 24, 22, 22, 22, 22, 22][level - 1]
  (
    "<od:pPr xmlns:od=\"\{word_uri}\"><od:outlineLvl od:val=\"\{level - 1}\"/></od:pPr>",
    "<od:rPr xmlns:od=\"\{word_uri}\"><od:b/><od:sz od:val=\"\{size}\"/></od:rPr>",
  )
}
