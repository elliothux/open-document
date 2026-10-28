///|
priv struct SeriesCycle {
  id : Int32
  index : Int32
  words : Array[String]
}

///|
let series_cycles : ReadOnlyArray[Array[String]] = [
  ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],
  ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
  [
    "January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December",
  ],
  [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
    "Dec",
  ],
  [
    "星期日", "星期一", "星期二", "星期三", "星期四", "星期五",
    "星期六",
  ],
  ["周日", "周一", "周二", "周三", "周四", "周五", "周六"],
  ["週日", "週一", "週二", "週三", "週四", "週五", "週六"],
  [
    "一月", "二月", "三月", "四月", "五月", "六月", "七月", "八月",
    "九月", "十月", "十一月", "十二月",
  ],
  [
    "1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月",
    "11月", "12月",
  ],
]

///|
fn cycle_text(text : String) -> String {
  let text = text.trim().to_owned()
  if text.has_suffix(".") {
    text[:text.length() - 1].to_owned()
  } else {
    text
  }
}

///|
fn cycle_matches(text : String) -> Array[Int32] {
  let text = cycle_text(text).to_lower()
  let result : Array[Int32] = []
  for id, words in series_cycles {
    if words.any(word => word.to_lower() == text) {
      result.push(id)
    }
  }
  result
}

///|
fn series_cycle(
  text : String,
  previous : SeriesCycle?,
  next : String,
) -> SeriesCycle? {
  let candidates = cycle_matches(text)
  guard !candidates.is_empty() else { return None }
  let id = if previous is Some(value) && candidates.contains(value.id) {
    value.id
  } else {
    cycle_matches(next)
    .iter()
    .find_first(id => candidates.contains(id))
    .unwrap_or(candidates[0])
  }
  let text = cycle_text(text)
  let lower = text.to_lower()
  let index = series_cycles[id]
    .map(word => word.to_lower())
    .search(lower)
    .unwrap()
  let first = text[:text.length().min(2)].to_owned()
  let words = series_cycles[id].map(word => {
    if first == first.to_upper() {
      word.to_upper()
    } else if first == first.to_lower() {
      word.to_lower()
    } else if text[:1] == text[:1].to_owned().to_upper() {
      word
    } else {
      word.to_lower()
    }
  })
  Some({ id, index, words, })
}
