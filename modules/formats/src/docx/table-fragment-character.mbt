///|
fn RunStyle::fragment_format(self : RunStyle) -> CharacterFormat {
  CharacterFormat::new(
    style=Clear,
    family=Set(self.family),
    size=Set(self.size),
    color=Set(self.color),
    bold=Set(self.bold),
    italic=Set(self.italic),
    underline=Set(self.underline),
    strike=Set(self.strike),
    highlight=Set(self.highlight),
    vertAlign=Set(self.vertAlign),
  )
}
