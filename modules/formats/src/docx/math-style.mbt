///|
fn math_fraction_style(
  format : CharacterFormat,
) -> @layout.TextStyle raise @failure.Failure {
  guard format
    is { family: Set(family), size: Set(size), color: Set(color), .. } &&
    format ==
    CharacterFormat::new(family=Set(family), size=Set(size), color=Set(color)) &&
    !family.trim().is_empty() &&
    family.length() <= 255 &&
    @xml.valid_text(family) &&
    family.iter().all(c => c.to_int() >= 32 && c != '\u2028' && c != '\u2029') &&
    size >= 0.5 &&
    size <= 409 &&
    (size * 2).round() == size * 2 &&
    color.length() == 6 &&
    color.iter().all(c => c.is_ascii_hexdigit()) else {
    @failure.reject(
      "invalid-operation", "Fraction format requires a font, half-point size and RGB color",
    )
  }
  @layout.TextStyle::new(family, size, color.to_lower())
}
