import gleam/string
import gleam/result
import gleam/list
import gsv

pub fn to_csv_line(
  strs strs: List(String),
) -> String {
  gsv.from_lists([strs], separator: ",", line_ending: gsv.Unix)
}

pub fn from_csv_line(
  csv csv: String,
) -> List(String) {
  csv
  |> gsv.to_lists(separator: ",")
  |> result.map(list.first)
  |> result.replace_error(Nil)
  |> result.flatten
  |> result.unwrap([])
}

pub fn from_csv_lines(
  csv csv: String,
) -> List(List(String)) {
  csv
  |> string.split("\n")
  |> list.map(from_csv_line)
}
