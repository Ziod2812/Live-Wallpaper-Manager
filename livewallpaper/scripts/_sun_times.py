#!/usr/bin/env python3
"""
_sun_times.py <lat> <lng> [YYYY-MM-DD]
-----------------------------------------
Prints "HH:MM HH:MM<TAB>HH:MM HH:MM" -- no wait, keep it simple:
prints two lines: sunrise then sunset, each "HH:MM" in LOCAL time
(24h), for the given latitude/longitude and date (default: today,
local date).

Pure-Python NOAA solar calculation (the same algorithm behind NOAA's
public sunrise/sunset spreadsheet) -- deliberately has NO network
dependency, unlike weather.sh, so scheduler.sh can resolve "sunrise"/
"sunset" rule boundaries even fully offline. Accuracy is within a
minute or two, which is more than enough for "switch the wallpaper
around sunset".

On any error (bad lat/lng, polar day/night where the sun never
rises/sets on that date) prints "--:--" for the affected line(s) and
exits 0 -- callers treat that as "rule inactive today", not a crash.
"""
import sys
import math
import datetime


def _sun_time(lat, lng, date, is_sunrise, zenith=90.833):
    # Classic NOAA / Sunrise Equation algorithm.
    try:
        day_of_year = date.timetuple().tm_yday
        lng_hour = lng / 15.0
        t = day_of_year + ((6 - lng_hour) / 24.0 if is_sunrise else (18 - lng_hour) / 24.0)

        m = (0.9856 * t) - 3.289

        l = m + (1.916 * math.sin(math.radians(m))) + (0.020 * math.sin(math.radians(2 * m))) + 282.634
        l = l % 360

        ra = math.degrees(math.atan(0.91764 * math.tan(math.radians(l))))
        ra = ra % 360
        l_quadrant = (math.floor(l / 90.0)) * 90.0
        ra_quadrant = (math.floor(ra / 90.0)) * 90.0
        ra = ra + (l_quadrant - ra_quadrant)
        ra = ra / 15.0

        sin_dec = 0.39782 * math.sin(math.radians(l))
        cos_dec = math.cos(math.asin(sin_dec))

        cos_h = (math.cos(math.radians(zenith)) - (sin_dec * math.sin(math.radians(lat)))) / (cos_dec * math.cos(math.radians(lat)))
        if cos_h > 1 or cos_h < -1:
            return None  # sun never rises/sets (polar day/night) on this date

        h = math.degrees(math.acos(cos_h))
        if is_sunrise:
            h = 360 - h
        h = h / 15.0

        local_t = h + ra - (0.06571 * t) - 6.622
        utc_t = (local_t - lng_hour) % 24

        return utc_t
    except (ValueError, ZeroDivisionError):
        return None


def _fmt_local(utc_hours, date):
    if utc_hours is None:
        return "--:--"
    dt_utc = datetime.datetime(date.year, date.month, date.day, tzinfo=datetime.timezone.utc) \
        + datetime.timedelta(hours=utc_hours)
    dt_local = dt_utc.astimezone()
    return dt_local.strftime("%H:%M")


def main():
    if len(sys.argv) < 3:
        print("Usage: _sun_times.py <lat> <lng> [YYYY-MM-DD]", file=sys.stderr)
        sys.exit(1)
    try:
        lat = float(sys.argv[1])
        lng = float(sys.argv[2])
    except ValueError:
        print("--:--")
        print("--:--")
        return
    if len(sys.argv) >= 4:
        try:
            date = datetime.datetime.strptime(sys.argv[3], "%Y-%m-%d").date()
        except ValueError:
            date = datetime.date.today()
    else:
        date = datetime.date.today()

    sunrise = _sun_time(lat, lng, date, True)
    sunset = _sun_time(lat, lng, date, False)
    print(_fmt_local(sunrise, date))
    print(_fmt_local(sunset, date))


if __name__ == "__main__":
    main()
