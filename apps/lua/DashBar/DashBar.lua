-- Dash Bar  -  compact driver dash for Assetto Corsa (Custom Shaders Patch Lua app)
--
--   * Gear inside a ring that fills with RPM (green -> amber -> red near the limiter)
--   * 15 shift lights: green, red, blue; all flash blue at the shift point
--   * Speed, RPM, race position
--   * Strip underneath: track temp, air temp, current lap time (shows the last lap for a few seconds after the line)

local settings = ac.storage({
  speedUnit = 'KPH',   -- 'KPH' or 'MPH'
  lightsStart = 0.80,  -- fraction of max RPM where the first light comes on
  shiftAt = 0.965,     -- fraction of max RPM where all lights flash
  maxRpmOverride = 0,  -- 0 = use the car's limiter
  showLastLap = 5,     -- seconds to show the last lap time after crossing the line
})

local view = { gear = 0, rpm = 0, maxRpm = 8000, speed = 0, pos = 0, road = nil, air = nil, lapMs = 0 }
local lastLap = { count = nil, shownUntil = 0, ms = 0 }
local clock = 0
local peakRpm = 0

local function field(obj, ...)
  if not obj then return nil end
  for _, k in ipairs({ ... }) do
    local ok, v = pcall(function() return obj[k] end)
    if ok and v ~= nil then return v end
  end
end
local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end

local function fmtLap(ms)
  if not ms or ms <= 0 then return '--:--.---' end
  ms = math.floor(ms + 0.5)
  local m = math.floor(ms / 60000)
  return string.format('%02d:%06.3f', m, (ms - m * 60000) / 1000)
end

function script.update(dt)
  clock = clock + dt
  local car = ac.getCar(0)
  if not car then return end
  local sim = ac.getSim()

  view.gear = car.gear or 0
  view.rpm = car.rpm or 0
  view.speed = car.speedKmh or 0
  view.pos = field(car, 'racePosition') or 0

  -- max rpm: setting, else the car's limiter, else the highest rpm we've seen
  if view.rpm > peakRpm then peakRpm = view.rpm end
  local lim = field(car, 'rpmLimiter')
  if settings.maxRpmOverride > 0 then view.maxRpm = settings.maxRpmOverride
  elseif lim and lim > 1000 then view.maxRpm = lim
  else view.maxRpm = math.max(6000, peakRpm) end

  view.road = field(sim, 'roadTemperature', 'trackTemperature')
  view.air = field(sim, 'ambientTemperature', 'airTemperature')

  local lc = car.lapCount or 0
  if lastLap.count and lc == lastLap.count + 1 and (car.previousLapTimeMs or 0) > 0 then
    lastLap.ms = car.previousLapTimeMs
    lastLap.shownUntil = clock + settings.showLastLap
  end
  lastLap.count = lc
  view.lapMs = car.lapTimeMs or 0
end

-- ---------------------------------------------------------------- drawing
local C = {
  body   = rgbm(0.015, 0.015, 0.018, 0.95),
  edge   = rgbm(1, 1, 1, 0.07),
  hub    = rgbm(0.17, 0.17, 0.18, 1),
  hubIn  = rgbm(0.20, 0.20, 0.21, 1),
  ring   = rgbm(0.38, 0.38, 0.40, 1),
  green  = rgbm(0.25, 0.85, 0.25, 1),
  amber  = rgbm(1.00, 0.68, 0.10, 1),
  red    = rgbm(1.00, 0.18, 0.15, 1),
  blue   = rgbm(0.20, 0.55, 1.00, 1),
  off    = rgbm(0.55, 0.55, 0.57, 1),
  orange = rgbm(1.00, 0.55, 0.10, 1),
  white  = rgbm(0.97, 0.97, 0.97, 1),
  label  = rgbm(0.80, 0.80, 0.82, 1),
  strip  = rgbm(0.17, 0.17, 0.18, 0.98),
  strip2 = rgbm(0.40, 0.40, 0.42, 1),
  purple = rgbm(0.75, 0.40, 1.00, 1),
}

local function text(str, size, x, y, col, align)
  local w = ui.measureDWriteText(str, size).x
  if align == 'right' then x = x - w elseif align == 'center' then x = x - w / 2 end
  ui.dwriteDrawText(str, size, vec2(x, y), col)
end

local function arc(cx, cy, r, a1, a2, col, thick)
  if a2 - a1 < 0.001 then return end
  ui.pathClear()
  ui.pathArcTo(vec2(cx, cy), r, a1, a2, math.max(6, math.floor((a2 - a1) * 18)))
  ui.pathStroke(col, false, thick)
end

-- small original icons
local function iconRoad(x, y, s)
  local h, w1, w2 = 18 * s, 6 * s, 16 * s
  ui.pathClear()
  ui.pathLineTo(vec2(x - w1 / 2, y - h / 2)); ui.pathLineTo(vec2(x + w1 / 2, y - h / 2))
  ui.pathLineTo(vec2(x + w2 / 2, y + h / 2)); ui.pathLineTo(vec2(x - w2 / 2, y + h / 2))
  ui.pathFillConvex(C.label)
  for i = 0, 2 do
    local yy = y - h / 2 + (i * 0.33 + 0.08) * h
    ui.drawLine(vec2(x, yy), vec2(x, yy + h * 0.18), C.strip, 1.6 * s)
  end
end
local function iconWind(x, y, s)
  for i, dy in ipairs({ -5, 0, 5 }) do
    local len = (i == 2 and 16 or 11) * s
    local x0 = x - 8 * s + (i == 3 and 3 * s or 0)
    ui.drawLine(vec2(x0, y + dy * s), vec2(x0 + len, y + dy * s), C.label, 1.8 * s)
  end
  arc(x + 6 * s, y - 8 * s, 3 * s, -math.pi * 0.9, math.pi * 0.5, C.label, 1.8 * s)
  arc(x + 7 * s, y + 3 * s, 2.5 * s, -math.pi * 0.5, math.pi * 0.9, C.label, 1.8 * s)
end
local function iconWatch(x, y, s)
  local r = 8 * s
  ui.drawCircle(vec2(x, y + 1 * s), r, C.label, 24, 2 * s)
  ui.drawLine(vec2(x, y - r), vec2(x, y - r - 3 * s), C.label, 2 * s)
  ui.drawLine(vec2(x - 3 * s, y - r - 3.5 * s), vec2(x + 3 * s, y - r - 3.5 * s), C.label, 2 * s)
  ui.drawLine(vec2(x, y + 1 * s), vec2(x + 4 * s, y - 3 * s), C.label, 2 * s)
end

local BASE_W, BASE_H = 720, 230

function script.windowMain(dt)
  local size = ui.windowSize()
  local s = math.min(size.x / BASE_W, size.y / BASE_H)
  local function S(v) return v * s end

  ui.pushDWriteFont('Segoe UI;Weight=Bold')

  -- body: one long rounded pill
  ui.drawRectFilled(vec2(S(4), S(4)), vec2(S(716), S(186)), C.edge, S(91))
  ui.drawRectFilled(vec2(S(6), S(6)), vec2(S(714), S(184)), C.body, S(89))

  -- gear hub with rpm ring
  local cx, cy, R = S(95), S(95), S(84)
  ui.drawCircleFilled(vec2(cx, cy), R, C.hub, 64)
  ui.drawCircleFilled(vec2(cx, cy), R - S(16), C.hubIn, 64)
  local a0, sweep = math.pi * 0.62, math.pi * 1.62        -- ring starts bottom-left, runs clockwise
  local frac = clamp(view.rpm / math.max(1, view.maxRpm), 0, 1)
  arc(cx, cy, R - S(7), a0, a0 + sweep, C.ring, S(5))
  local rcol = C.green
  if frac >= settings.shiftAt then rcol = C.red elseif frac >= settings.lightsStart then rcol = C.amber end
  arc(cx, cy, R - S(7), a0, a0 + sweep * frac, rcol, S(9))

  local g = view.gear
  local gs = g < 0 and 'R' or (g == 0 and 'N' or tostring(g))
  text(gs, S(64), cx, cy - S(44), C.white, 'center')

  -- shift lights
  local n = 15
  local lx0, ly, step, lr = S(215), S(42), S(23), S(8.5)
  local span = settings.shiftAt - settings.lightsStart
  local lit = span > 0 and clamp(math.floor((frac - settings.lightsStart) / span * n + 0.5), 0, n) or 0
  local flash = frac >= settings.shiftAt
  local flashOn = math.floor(clock * 10) % 2 == 0
  for i = 1, n do
    local col = C.off
    if flash then
      col = flashOn and C.blue or C.off
    elseif i <= lit then
      if i <= 5 then col = C.green elseif i <= 10 then col = C.red else col = C.blue end
    end
    ui.drawCircleFilled(vec2(lx0 + (i - 1) * step, ly), lr, col, 20)
  end

  -- speed and rpm
  local unit = settings.speedUnit
  local spd = unit == 'MPH' and view.speed * 0.621371 or view.speed
  text(unit, S(19), S(210), S(78), C.label)
  text(string.format('%.0f', spd), S(40), S(207), S(98), C.white)
  text('RPM', S(19), S(320), S(78), C.label)
  text(string.format('%.0f', view.rpm), S(40), S(317), S(98), C.white)

  -- position
  local pos = view.pos and view.pos > 0 and ('P' .. tostring(view.pos)) or 'P-'
  text(pos, S(52), S(676), S(62), C.orange, 'right')

  -- bottom strip
  local x1, x2, y1, y2 = S(78), S(500), S(166), S(214)
  ui.drawRectFilled(vec2(x1, y1), vec2(x2, y2), C.strip2, S(12))
  ui.drawRectFilled(vec2(x1 + S(2), y1 + S(2)), vec2(x2 - S(2), y2 - S(2)), C.strip, S(10))
  local ty, ts = S(176), S(23)
  local function tempStr(v) return v and string.format('%.0f °C', v) or '-- °C' end
  iconRoad(S(106), S(190), s)
  text(tempStr(view.road), ts, S(124), ty, C.white)
  iconWind(S(238), S(190), s)
  text(tempStr(view.air), ts, S(256), ty, C.white)
  iconWatch(S(366), S(189), s)
  local showingLast = clock < lastLap.shownUntil
  text(fmtLap(showingLast and lastLap.ms or view.lapMs), ts, S(384), ty, showingLast and C.purple or C.white)

  ui.popDWriteFont()
end

-- ---------------------------------------------------------------- settings
function script.windowSettings(dt)
  if ui.button('Speed unit: ' .. settings.speedUnit) then
    settings.speedUnit = settings.speedUnit == 'KPH' and 'MPH' or 'KPH'
  end
  local v, c
  v, c = ui.slider('##start', settings.lightsStart * 100, 50, 95, 'First shift light at %.0f%% of max RPM')
  if c then settings.lightsStart = v / 100 end
  v, c = ui.slider('##shift', settings.shiftAt * 100, 80, 100, 'Shift flash at %.1f%% of max RPM')
  if c then settings.shiftAt = v / 100 end
  v, c = ui.slider('##max', settings.maxRpmOverride, 0, 20000, settings.maxRpmOverride > 0 and 'Max RPM: %.0f' or 'Max RPM: from car')
  if c then settings.maxRpmOverride = math.floor(v / 50 + 0.5) * 50 end
  v, c = ui.slider('##last', settings.showLastLap, 0, 15, 'Show last lap for %.0f s')
  if c then settings.showLastLap = v end
end

-- exposed for testing only
script._debug = function() return view end
