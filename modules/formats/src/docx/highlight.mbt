///|
fn highlight_color(name : String) -> String raise @failure.Failure {
  match name {
    "none" => ""
    "black" => "000000"
    "blue" => "0000ff"
    "cyan" => "00ffff"
    "green" => "00ff00"
    "magenta" => "ff00ff"
    "red" => "ff0000"
    "yellow" => "ffff00"
    "white" => "ffffff"
    "darkBlue" => "000080"
    "darkCyan" => "008080"
    "darkGreen" => "008000"
    "darkMagenta" => "800080"
    "darkRed" => "800000"
    "darkYellow" => "808000"
    "darkGray" => "808080"
    "lightGray" => "c0c0c0"
    _ => @failure.reject("invalid-style", "Invalid highlight color")
  }
}
