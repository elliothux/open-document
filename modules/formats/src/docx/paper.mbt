///|
// Standard paper dimensions in 1/100 mm, in LibreOffice's first-match order.
// Factual size data: LibreOffice/core libreoffice-25.8.2.2 i18nutil/source/utility/paper.cxx.
// Independently implemented; no upstream executable code is copied.
let paper_dimensions : Array[Int32] = [
  84100, 118900, 59400, 42000, 29700, 21000, 14800, 25000, 35300, 17600, 21590, 27940,
  35560, 43180, 12500, 22900, 32400, 16200, 11400, 11000, 22000, 18000, 27000, 28000,
  55880, 86360, 111760, 18415, 26670, 33020, 9843, 19050, 9208, 16510, 22543, 10478,
  24130, 11430, 26353, 12065, 18400, 26000, 13000, 14000, 20300, 25700, 36400, 18200,
  12800, 13970, 21519, 27517, 25400, 29210, 45800, 23000, 37783, 10000, 22860, 38100,
  22700, 35600, 30500, 48700, 32233, 33000, 20000, 10500, 30480, 7400, 5200, 3700,
  2600, 100000, 141400, 70700, 50000, 8800, 6200, 4400, 3100, 64800, 8100, 5700,
  45720, 60960, 91440, 121920, 15750, 17500, 19500, 19700, 27300, 33866, 14288, 15875,
]

///|
fn page_dimension(twips : Double) -> Double {
  // Leave invalid values to the existing page validator before integer conversion.
  guard twips >= 720 && twips <= 288000 else { return twips / 20 }
  let dimension = (twips * 127 / 72 + 0.5).to_int()
  for standard in paper_dimensions {
    if (dimension - standard).abs() < 44 {
      return (standard.to_double() * 72 / 127 + 0.5).to_int().to_double() / 20
    }
  }
  twips / 20
}
