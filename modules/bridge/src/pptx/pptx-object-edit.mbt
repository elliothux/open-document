///|
#derive(@json.FromJson)
priv struct ObjectFrameRequest {
  x : @common.RequestNumber
  y : @common.RequestNumber
  width : @common.RequestNumber
  height : @common.RequestNumber
}

///|
#derive(@json.FromJson)
priv struct HyperlinkEditRequest {
  link : @common.RequiredNullable[HyperlinkTargetRequest]
}

///|
#derive(@json.FromJson)
priv struct HyperlinkTargetRequest {
  kind : String
  target : String
}

///|
fn pptx_object_edit(change : Json) -> @model.ObjectEdit raise @failure.Failure {
  let command : @common.ActionRequest = @common.request(change)
  let action = command.action
  match action {
    "tableStructure"
    | "tableRowHeight"
    | "tableColumnWidth"
    | "tableStyle"
    | "tableDirection"
    | "splitTableCell"
    | "fillTable"
    | "insertTable" => pptx_table_edit(action, change)
    "imageFill"
    | "imageFillMode"
    | "imageMode"
    | "imageInsets"
    | "imageOpacity"
    | "replaceImage"
    | "imageCrop"
    | "insertImage" => pptx_image_edit(action, change)
    "insertMedia" | "fillMedia" => pptx_insert_media(action, change)
    "mediaPlayback" => pptx_media_playback(change)
    "insertChart" | "chartData" | "fillChart" => pptx_chart_edit(action, change)
    "insert" | "insertPlaceholder" => pptx_insert_object(action, change)
    "placeholder" => pptx_placeholder(change)
    "delete" => @model.Remove
    "clearTextFormat" => @model.ClearTextFormat
    "clearParagraphFormat" => @model.ClearParagraphFormat
    "textFormat" => {
      let request : TextFormatEditRequest[TextFormatInput] = @common.request(
        change,
      )
      @model.TextFormat(request.format.value)
    }
    "textAlign" => {
      let request : TextAlignmentRequest = @common.request(change)
      @model.TextAlign(request.alignment)
    }
    "textParagraph" => {
      let request : TextFormatEditRequest[ParagraphFormatInput] = @common.request(
        change,
      )
      @model.TextParagraph(request.format.value)
    }
    "textInsets"
    | "textAnchor"
    | "textWrap"
    | "textFit"
    | "textUpright"
    | "textRotation"
    | "textDirection"
    | "textColumns" => pptx_text_frame(action, change)
    "lineEnd"
    | "strokeCap"
    | "strokeJoin"
    | "strokeDash"
    | "shapeAdjustment"
    | "shapeType"
    | "fill"
    | "stroke"
    | "fillOpacity"
    | "strokeOpacity" => pptx_shape_style(action, change)
    "insertConnector" | "connectorEndpoints" =>
      pptx_connector_edit(action, change)
    "insertDiagram" => pptx_diagram_edit(change)
    "insertWordArt" => pptx_word_art_edit(change)
    "insertMath" | "appendMath" | "updateMath" | "deleteMath" =>
      pptx_math_edit(action, change)
    "hyperlink" => {
      let request : HyperlinkEditRequest = @common.request(change)
      match request.link.value {
        None => @model.Hyperlink("none", "")
        Some(link) => @model.Hyperlink(link.kind, link.target)
      }
    }
    "gradientFill" | "radialGradientFill" => pptx_gradient_edit(action, change)
    "group" => @model.Group
    "ungroup" => @model.Ungroup
    "duplicate" | "rotate" | "flip" | "layer" | "align" | "distribute" =>
      pptx_arrange(action, change)
    _ => @failure.reject("invalid-operation", "Unknown object edit")
  }
}
