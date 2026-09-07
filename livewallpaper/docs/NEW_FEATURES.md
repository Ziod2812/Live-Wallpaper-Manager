# New in this build: Collections, Scheduling, Sunrise/Sunset, Weather, Transitions

## 1. Collections / Groups
- **Manage:** new "Collections" page in the sidebar — create/rename/delete/recolor.
- **Assign wallpapers:** hover any wallpaper card → "+" button (bottom-right of the
  thumbnail) → toggle which collections it belongs to (creates new ones inline too).
- **Data:** `data/collections.json`, edited only through `scripts/collections.sh`
  (list/create/delete/rename/set_color/add/remove/toggle/random/for_path).
- Collections are the building block Schedule and Weather rules pick a random
  wallpaper *from* — create these first.

## 2. Scheduling (time-of-day) + Sunrise/Sunset
- **Page:** Schedule → "Time-of-day rules".
- Each rule is a `start`–`end` window (e.g. `06:00`–`12:00`) mapped to a collection
  (or one specific wallpaper). The **first rule whose window contains the current
  time wins** — order matters, top to bottom.
- Use the literal words `sunrise` / `sunset` instead of a fixed time as either
  boundary to follow daylight — e.g. `sunset`–`sunrise` for a "night" rule.
  Requires **Location** (lat/lng) to be set on the same page.
- Sunrise/sunset is computed **fully offline** (`scripts/_sun_times.py`, the
  standard NOAA solar-position formula) — no network call, no API key. Accuracy
  is within a minute or two.
- Evaluated every 60s by `scripts/scheduler_tick.sh`, driven by
  `Services/SchedulerService.qml`. Only re-applies when the *active rule* changes,
  so it won't relaunch the wallpaper every poll. "Shuffle now" on the page forces
  a fresh random pick from the currently active rule's collection.

## 3. Weather-based wallpaper
- **Page:** Schedule → "Weather-based wallpaper".
- Map a condition (Clear day/night, Cloudy, Fog, Rain, Snow, Storm) to a
  collection; leave a condition unmapped to leave the wallpaper alone for it.
- Weather comes from **Open-Meteo** (`scripts/weather.sh`) — free, no signup,
  no API key. Cached for `weather_poll_minutes` (default 20) to keep network
  calls infrequent. Also requires Location.
- Evaluated every 5 minutes by `scripts/weather_tick.sh` /
  `Services/WeatherService.qml`; only re-applies when the condition actually
  changes. "Apply now" forces an immediate check.

## Known gaps / follow-ups
- Scheduling/Weather always apply to "the current/default monitor" the same way
  `apply_wallpaper.sh` does with no monitor arg — no per-monitor schedule yet.
- Schedule rules have no day-of-week scoping (every rule evaluates every day).
