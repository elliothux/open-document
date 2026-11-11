///|
priv struct SlideAnimationRequest {
  object : String
  kind : String
  trigger : String
  delay : @common.RequestInt
  duration : @common.RequestInt
  repeat : @common.RequestInt
  params : Array[@common.RequestNumber]
} derive(@json.FromJson)

///|
priv struct SlideAdvanceRequest {
  click : Bool
  after : Json
} derive(@json.FromJson)

///|
priv struct SlideTransitionRequest {
  kind : String
  duration : @common.RequestInt
  direction : String
} derive(@json.FromJson)

///|
priv struct SolidBackgroundRequest {
  color : String
} derive(@json.FromJson)

///|
priv struct BackgroundImageFormatRequest {
  crop : Array[@common.RequestNumber]
  mode : String
  opacity : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct FooterContentRequest {
  date : @common.RequiredNullable[FooterDateRequest]
  footer : @common.RequiredNullable[String]
  number : Bool
} derive(@json.FromJson)

///|
priv struct SlideFooterRequest {
  value : FooterContentRequest
  allSlides : Bool
} derive(@json.FromJson)

///|
priv struct AutomaticFooterDateRequest {
  format : @common.RequestInt
  language : String
} derive(@json.FromJson)

///|
priv struct FooterDateRequest {
  value : @model.FooterDate
}

///|
impl @json.FromJson for FooterDateRequest with fn from_json(input, path) {
  let value = match input {
    String(text) => @model.Fixed(text)
    _ => {
      let date : AutomaticFooterDateRequest = @json.from_json(input, path~)
      @model.Automatic(date.format.value, date.language)
    }
  }
  { value, }
}

///|
priv struct IndexRequest {
  index : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct IdRequest {
  id : String
} derive(@json.FromJson)

///|
priv struct NameRequest {
  name : String
} derive(@json.FromJson)

///|
priv struct RenameSectionRequest {
  id : String
  name : String
} derive(@json.FromJson)

///|
priv struct MoveSectionRequest {
  id : String
  index : @common.RequestInt
} derive(@json.FromJson)

///|
priv struct SlideVisibilityRequest {
  hidden : Bool
} derive(@json.FromJson)

///|
priv struct SlideNotesRequest {
  text : String
} derive(@json.FromJson)

///|
priv struct FirstSlideNumberRequest {
  number : @common.RequestNumber
} derive(@json.FromJson)

///|
priv struct ThemeColorRequest {
  slot : String
  color : String
} derive(@json.FromJson)

///|
priv struct ThemeFontRequest {
  kind : String
  script : String
  font : String
} derive(@json.FromJson)

///|
priv struct SlideSizeRequest {
  width : @common.RequestNumber
  height : @common.RequestNumber
} derive(@json.FromJson)

///|
fn pptx_slide_edit(change : Json) -> @model.SlideEdit raise @failure.Failure {
  let command : @common.ActionRequest = @common.request(change)
  let action = command.action
  match action {
    "guides" => pptx_guide_edit(change)
    "snapping" => pptx_snapping_edit(change)
    "showSettings" => pptx_show_settings(change)
    "customShows" => {
      guard change is { "value": Array(items), .. } &&
        items.length() <= @model.CustomShowCount else {
        @failure.reject("invalid-operation", "Custom show list is required")
      }
      @model.CustomShows(
        items.map(item => {
          guard item is { "slides": Array(slides), .. } &&
            slides.length() <= @model.CustomShowSlides else {
            @failure.reject(
              "invalid-operation", "Custom show slide list is required",
            )
          }
          @common.request(item)
        }),
      )
    }
    "animations" => {
      guard change is { "value": Array(items), .. } &&
        items.length() <= @model.SlideAnimationCount else {
        @failure.reject("invalid-operation", "Animation list is required")
      }
      @model.Animations(
        items.map(item => {
          guard item is { "params": Array(values), .. } && values.length() <= 2 else {
            @failure.reject(
              "invalid-operation", "Animation parameters are required",
            )
          }
          let animation : SlideAnimationRequest = @common.request(item)
          {
            object: animation.object,
            kind: animation.kind,
            trigger: animation.trigger,
            delay: animation.delay.value,
            duration: animation.duration.value,
            repeat: animation.repeat.value,
            params: animation.params.map(value => value.value),
          }
        }),
      )
    }
    "advance" => {
      let value = match change {
        { "value": value, .. } => value
        _ => @failure.reject("invalid-operation", "Slide advance is required")
      }
      let advance : SlideAdvanceRequest = @common.request(value)
      let after = if advance.after is Null {
        None
      } else {
        let time : @common.RequestInt = @common.request(advance.after)
        Some(time.value)
      }
      @model.Advance({ click: advance.click, after, })
    }
    "transition" =>
      @model.Transition(
        match change {
          { "value": Null, .. } => None
          { "value": value, .. } => {
            let transition : SlideTransitionRequest = @common.request(value)
            Some({
              kind: transition.kind,
              duration: transition.duration.value,
              direction: transition.direction,
            })
          }
          _ =>
            @failure.reject("invalid-operation", "Slide transition is required")
        },
      )
    "add" => @model.AddSlide
    "copy" => @model.CopySlide
    "delete" => @model.DeleteSlide
    "move" => {
      let request : IndexRequest = @common.request(change)
      @model.MoveSlide(request.index.value)
    }
    "hidden" => {
      let request : SlideVisibilityRequest = @common.request(change)
      @model.HideSlide(request.hidden)
    }
    "notes" => {
      let request : SlideNotesRequest = @common.request(change)
      @model.Notes(request.text)
    }
    "firstSlideNumber" => {
      let request : FirstSlideNumberRequest = @common.request(change)
      @model.FirstSlideNumber(request.number.value)
    }
    "footer" => {
      let request : SlideFooterRequest = @common.request(change)
      let value = request.value
      @model.Footer(
        {
          date: value.date.value.map(date => date.value),
          footer: value.footer.value,
          number: value.number,
        },
        request.allSlides,
      )
    }
    "commentAdd" | "commentUpdate" | "commentRemove" | "commentStatus" =>
      pptx_comment_change(action, change)
    "themeColor" => {
      let request : ThemeColorRequest = @common.request(change)
      @model.ThemeColor(request.slot, request.color)
    }
    "themeFont" => {
      let request : ThemeFontRequest = @common.request(change)
      @model.ThemeFont(request.kind, request.script, request.font)
    }
    "masterTextStyle" | "masterParagraphStyle" =>
      pptx_master_text_style(action, change)
    "sectionAdd" => {
      let request : NameRequest = @common.request(change)
      @model.AddSection(request.name)
    }
    "sectionRename" => {
      let request : RenameSectionRequest = @common.request(change)
      @model.RenameSection(request.id, request.name)
    }
    "sectionRemove" | "sectionDelete" => {
      let request : IdRequest = @common.request(change)
      if action == "sectionRemove" {
        @model.RemoveSection(request.id)
      } else {
        @model.DeleteSection(request.id)
      }
    }
    "sectionRemoveAll" => @model.RemoveSections
    "sectionMove" => {
      let request : MoveSectionRequest = @common.request(change)
      @model.MoveSection(request.id, request.index.value)
    }
    "size" => {
      let request : SlideSizeRequest = @common.request(change)
      @model.Size(request.width.value, request.height.value)
    }
    "backgroundImage" => {
      let source : @common.BytesRequest = @common.request(change)
      let bytes = @common.byte_input(source.bytes, @model.ImageInputBytes)
      let request : ImageModeRequest = @common.request(change)
      @model.BackgroundImage(bytes, request.mode)
    }
    "backgroundImageInsets" =>
      @model.BackgroundImageInsets(pptx_image_insets(change))
    "backgroundImageFormat" => {
      guard change is { "crop": Array(values), .. } && values.length() == 4 else {
        @failure.reject("invalid-operation", "Four crop values are required")
      }
      let image : BackgroundImageFormatRequest = @common.request(change)
      @model.BackgroundImageFormat(
        image.mode,
        image.crop.map(value => value.value),
        image.opacity.value,
      )
    }
    "background" => {
      let value = match change {
        { "value": Null, .. } => None
        { "value": { "kind": String("solid"), .. } as value, .. } => {
          let fill : SolidBackgroundRequest = @common.request(value)
          Some(@model.Solid(fill.color))
        }
        { "value": { "kind": String("linear"), .. } as value, .. } => {
          let stops = pptx_gradient_stops(value)
          let fill : LinearGradientRequest = @common.request(value)
          Some(@model.Linear(stops, fill.angle.value, fill.scaled))
        }
        { "value": { "kind": String("radial"), .. } as value, .. } =>
          Some(@model.Radial(pptx_gradient_stops(value)))
        _ =>
          @failure.reject(
            "invalid-operation", "Slide background requires a color or null",
          )
      }
      @model.Background(value)
    }
    "layout" => {
      let request : IdRequest = @common.request(change)
      @model.ApplyLayout(request.id)
    }
    "resetLayout" => @model.ResetLayout
    "addLayout"
    | "copyLayout"
    | "deleteLayout"
    | "deleteMaster"
    | "addMaster"
    | "copyMaster"
    | "sourceName" => pptx_source_edit(action, change)
    _ => @failure.reject("invalid-operation", "Unknown slide edit")
  }
}
