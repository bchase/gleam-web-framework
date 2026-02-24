import gtz
import tempo.{type DateTime, type Offset, type Date}
import tempo/datetime
import tempo/duration
import tempo/offset
import tempo/time

pub type TimeZoneProvider = tempo.TimeZoneProvider

pub fn utc_timezone() -> TimeZoneProvider {
  let assert Ok(tz) = gtz.timezone("Etc/UTC")
  tz
}

pub fn utc_offset() -> Offset {
  let assert Ok(offset) = offset(minutes: 0)
  offset
}

pub fn offset(
  minutes minutes: Int,
) -> Result(Offset, Nil) {
  minutes
  |> duration.minutes
  |> offset.from_duration
}

pub fn start_of_day(
  datetime dt: DateTime,
) -> DateTime {
  datetime.new(
    date: datetime.get_date(dt),
    time: time.start_of_day,
    offset: datetime.get_offset(dt),
  )
}

/// `"23:59:59.999999"`
pub fn end_of_day(
  datetime dt: DateTime,
) -> DateTime {
  dt
  |> end_of_day_instant_24
  |> datetime.subtract(duration.microseconds(1))
}

/// `"24:00:00.000000"`
pub fn end_of_day_instant_24(
  datetime dt: DateTime,
) -> DateTime {
  datetime.new(
    date: datetime.get_date(dt),
    time: time.end_of_day,
    offset: datetime.get_offset(dt),
  )
}
