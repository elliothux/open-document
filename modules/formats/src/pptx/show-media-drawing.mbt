///|
fn media_image_key(id : String) -> String {
  "show-media:" + id
}

///|
fn media_fragment(
  object : Object?,
  commands : Array[@layout.DrawCommand],
) -> Array[@layout.DrawCommand] {
  guard object is Some(object) && object.media is Some(_) else {
    return commands
  }
  commands.map(command => {
    match command {
      Image(image) => Image({ ..image, key: media_image_key(object.id), })
      Layer(alpha, children) =>
        Layer(alpha, media_fragment(Some(object), children))
      _ => command
    }
  })
}

///|
fn media_draw_commands(
  commands : Array[@layout.DrawCommand],
  aliases : Map[String, (String, String)],
  paths : Map[String, Array[Array[Int]]],
  prefix : Array[Int],
) -> Array[@layout.DrawCommand] {
  commands.mapi((index, command) => {
    match command {
      Image(image) => {
        guard aliases.get(image.key) is Some((object, poster)) else {
          return command
        }
        if !paths.contains(object) {
          paths[object] = []
        }
        paths[object].push(prefix + [index])
        Image({ ..image, key: poster, })
      }
      Layer(alpha, children) =>
        Layer(
          alpha,
          media_draw_commands(children, aliases, paths, prefix + [index]),
        )
      _ => command
    }
  })
}

///|
fn Session::media_drawing(
  self : Session,
  show : ShowState,
  regions : Array[@layout.DrawingRegion],
  images : @layout.Images,
) -> (Array[@layout.DrawingRegion], Array[Json]) raise @failure.Failure {
  let aliases : Map[String, (String, String)] = Map([])
  for index in [Some(show.index), show.from] {
    if index is Some(index) {
      for object in self.slides[index].objects {
        if object.media is Some(_) && object.image is Some(poster) {
          aliases[media_image_key(object.id)] = (
            object.id,
            images.get(poster).identity,
          )
        }
      }
    }
  }
  let paths : Map[String, Array[Array[Int]]] = Map([])
  let regions = regions.mapi((index, region) => {
    ..region,
    commands: media_draw_commands(region.commands, aliases, paths, [index]),
  })
  guard paths.values().fold(init=0, (sum, refs) => sum + refs.length()) <= 65536 else {
    @failure.reject(
      "limit-exceeded", "Slideshow media image references exceed budget",
    )
  }
  let refs = paths
    .iter()
    .map(pair => {
      let item : Json = { "object": pair.0, "paths": pair.1 }
      item
    })
    .to_array()
  (regions, refs)
}
