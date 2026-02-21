import gleam/option.{type Option}
import gleam/string
import gleam/int
import gleam/result.{try}
import gleam/time/timestamp as ts
import gleam/time/duration as dur
import gleam/time/calendar as cal
import birl/duration
import gleam/order
import birl.{type Day}
import gleam/yielder.{type Yielder}

pub fn to_timestamp(
  time time: birl.Time,
) -> ts.Timestamp {
  let birl.TimeOfDay(
    hour: hours,
    minute: minutes,
    second: seconds,
    milli_second:,
  ) = birl.get_time_of_day(time)
  let birl.Day(year:, month:, date:) = birl.get_day(time)

  let month =
    month
    |> cal.month_from_int
    |> result.lazy_unwrap(fn() {
      panic as {
        "`common.birl_to_timestamp` got an invalid month int: " <>
          { month |> int.to_string } <> "\n" <>
          "from `birl.Time`: " <> { time |> string.inspect } <> "\n"
      }
    })

  // let microseconds = milli_second * 1000
  let nanoseconds = milli_second * 1000 * 1000

  let date = cal.Date(year:, month:, day: date)
  let time = cal.TimeOfDay(hours:, minutes:, seconds:, nanoseconds:)

  ts.from_calendar(date, time, dur.seconds(0))
}

pub fn from_timestamp(
  time time: ts.Timestamp,
) -> birl.Time {
  let #(date, time) = ts.to_calendar(time, dur.seconds(0))

  let cal.Date(year:, month:, day:) = date
  let cal.TimeOfDay(hours:, minutes:, seconds:, ..) = time
  // TODO `microseconds`?
  let month = month |> cal.month_to_int

  birl.from_erlang_universal_datetime(
    #(#(year, month, day), #(hours, minutes, seconds)),
  )
}

pub fn day_str(
  day day: Day,
) -> String {
  [
    day.year |> int.to_string |> string.pad_start(4, "0"),
    day.month |> int.to_string |> string.pad_start(2, "0"),
    day.date |> int.to_string |> string.pad_start(2, "0"),
  ]
  |> string.join("-")
}

pub fn date_range(
  from from: Day,
  through through: Day,
) -> List(Day) {
  let start = birl.unix_epoch |> birl.set_day(from)
  let end = birl.unix_epoch |> birl.set_day(through)

  case start |> birl.compare(end) {
    order.Gt ->
      []

    order.Eq | order.Lt -> {
      let next = start |> birl.add(duration.days(1)) |> birl.get_day

      [from, ..date_range(from: next, through:)]
    }
  }
}

pub fn day_from_calendar_date(
  date date: cal.Date,
) -> Day {
    let cal.Date(year:, month:, day: date) = date
    let month = cal.month_to_int(month)
    birl.Day(year:, month:, date:)
}

pub fn day_to_calendar_date(
  day day: Day,
) -> Result(cal.Date, Nil) {
    let birl.Day(year:, month:, date: day) = day
    use month <- try(cal.month_from_int(month))
    Ok(cal.Date(year:, month:, day:))
}

pub fn day_utc_now() -> Day {
  birl.utc_now()
  |> birl.get_day
}

pub fn day_adjust(
  day day: Day,
  days days: Int,
) -> Day {
  day
  |> birl.set_day(birl.unix_epoch, _)
  |> birl.add(duration.days(days))
  |> birl.get_day
}

pub fn zero_day() -> Day {
  birl.unix_epoch
  |> birl.get_day
}

// pub fn day_range(
//   start start: Day,
//   end end: Option(Day),
// ) -> Yielder(Day) {
//   let zero = birl.unix_epoch

//   let start = birl.set_day(zero, start)
//   let end = end |> option.map(fn(end) { birl.set_day(zero, end) })

//   let step = duration.days(1)

//   birl.range(from: start, to: end, step:)
//   |> yielder.map(fn(time) { birl.get_day(time) })
// }
