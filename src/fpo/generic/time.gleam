import birl
import birl/duration
import gleam/list
import gleam/int
import gleam/string
import gleam/time/calendar.{type Date}
import gleam/dynamic/decode.{type Decoder}

pub fn date_utc_now() -> Date {
  birl.utc_now()
  |> birl.get_day
  |> date_from_birl_day
}

pub fn date_from_birl_day(
  day day: birl.Day,
) -> Date {
  let assert Ok(month) = calendar.month_from_int(day.month)

  calendar.Date(year: day.year, month:, day: day.date)
}

pub fn date_to_birl_day(
  date date: Date,
) -> birl.Day {
  birl.Day(
    year: date.year,
    month: calendar.month_to_int(date.month),
    date: date.day,
  )
}

pub fn date_adjust(
  date date: Date,
  days days: Int
) -> Date {
  date
  |> date_to_birl_day
  |> birl.set_day(birl.unix_epoch, _)
  |> birl.add(duration.days(days))
  |> birl.get_day
  |> date_from_birl_day
}

pub fn date_iso8601_str(
  date date: Date,
) -> String {
  [
    date.year |> int.to_string |> zero_left_pad(4),
    date.month |> calendar.month_to_int |> int.to_string |> zero_left_pad(2),
    date.day |> int.to_string |> zero_left_pad(2),
  ]
  |> string.join("-")
}

pub fn decoder_date() -> Decoder(Date) {
  decode.string
  |> decode.then(fn(str) {
    let ints =
      str
      |> string.split("-")
      |> list.map(int.parse)

    case ints {
      [Ok(year), Ok(month), Ok(day)] ->
        case calendar.month_from_int(month) {
          Ok(month) -> decode.success(calendar.Date(year:, month:, day:))
          Error(Nil) -> decode.failure(zero_date, "invalid `calendar.Date`: " <> str)
        }

      _ ->
        decode.failure(zero_date, "invalid `calendar.Date`: " <> str)
    }
  })
}

pub const zero_date: Date = utc_epoch_date

pub const utc_epoch_date: Date =
  calendar.Date(year: 1970, month: calendar.January, day: 1)

fn zero_left_pad(
  str str: String,
  count count: Int,
) -> String {
  string.pad_start(str, to: count, with: "0")
}
