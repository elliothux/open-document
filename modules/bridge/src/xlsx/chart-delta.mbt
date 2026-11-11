///|
fn Context::encode_chart_tiles(
  self : Context,
  value : Json,
  tiles : ArrayView[@model.ViewportChartTile],
) -> Json {
  let previous = self.chart_tiles
  if tiles.is_empty() && previous.is_empty() {
    return value
  }
  guard value is Object(fields) &&
    fields.get("regions") is Some(Array([Object(region)])) &&
    region.get("commands") is Some(Array(commands)) else {
    return value
  }
  let next : Map[String, Json] = Map([])
  let mut encoded : Array[Json]? = None
  for tile in tiles {
    let key = tile.key
    let known = match next.get(key) {
      Some(_) as known => known
      None => previous.get(key)
    }
    next[key] = tile.body
    if known is Some(known) && physical_equal(known, tile.body) {
      let copy = match encoded {
        Some(copy) => copy
        None => {
          let copy = commands.copy()
          encoded = Some(copy)
          copy
        }
      }
      copy[tile.index] = { "op": "chartTile", "key": key }
    }
  }
  self.chart_tiles = next
  let fields = fields.copy()
  if encoded is Some(commands) {
    let region = region.copy()
    region["commands"] = Json::array(commands)
    fields["regions"] = Json::array([Json::object(region)])
  }
  fields["chartTiles"] = Json(true)
  Json::object(fields)
}
