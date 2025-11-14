--!SERVER_SCRIPT
-- HudEvolution CSP server HUD

-- In CSP server scripts, `ac` and `ui` are provided as globals.
-- Do NOT require 'ac' or 'ui' here.

local STORAGE_SIZE = ac.storage({ group = 'ACEvoHUD', name = 'Size', value = 1 })
local Size = STORAGE_SIZE.value

local colors = {
    SPEEDOMETER_GRAY = rgbm(0x2d/255, 0x2d/255, 0x2d/255, 1),
    SPEEDOMETER_DARK = rgbm(0x66/255, 0x65/255, 0x65/255, 1),
    SPEEDOMETER_WHITE = rgbm(1, 1, 1, 1),
    RPM_NORMAL = rgbm(1, 1, 254/255, 1),
    RPM_WARNING = rgbm(1, 1, 0, 1),
    RPM_DANGER = rgbm(1, 0, 0, 1),
}

local current_rpm_fill = 0
local target_rpm_fill = 0
local rpm_animation_speed = 3.0
local frame_counter = 0
local last_displayed_rpm = 0
local blink_time = 0

local STORAGE_UNIT = ac.storage({ group = 'ACEvoHUD', name = 'Unit', value = true })
local isKmh = STORAGE_UNIT.value
local lastClickTime = 0
local doubleClickThreshold = 0.3

-- HUD drawing -------------------------------------------------------------

local function drawSpeedometer(car, center, radius, dt)
    if not car then return end
    local my_car = car

    local max_rpm = my_car.rpmLimiter
    if max_rpm == 0 then
        max_rpm = 8000
    end

    max_rpm = max_rpm * 1.05

    target_rpm_fill = math.clamp(my_car.rpm / max_rpm, 0, 1)

    -- smooth RPM animation using dt from drawUI context
    dt = dt or 0.016
    if current_rpm_fill < target_rpm_fill then
        current_rpm_fill = math.min(current_rpm_fill + rpm_animation_speed * dt, target_rpm_fill)
    elseif current_rpm_fill > target_rpm_fill then
        current_rpm_fill = math.max(current_rpm_fill - rpm_animation_speed * dt, target_rpm_fill)
    end

    -- RPM background
    ui.pathClear()
    ui.pathArcTo(center, radius, math.rad(-210), math.rad(30), 32)
    ui.pathStroke(colors.SPEEDOMETER_GRAY, false, 18)

    -- RPM fill
    if my_car.rpm >= 20 then
        ui.pathClear()
        local start_angle = math.rad(-210)
        local end_angle = math.lerp(start_angle, math.rad(40), current_rpm_fill)

        local fill_color = colors.RPM_NORMAL

        if current_rpm_fill > 0.87 then
            fill_color = colors.RPM_WARNING
        end
        if current_rpm_fill > 0.92 then
            local blink_factor = (math.sin(blink_time) + 1) / 2

            fill_color = rgbm(
                math.lerp(1, 0xd3/255, blink_factor),
                math.lerp(0, 0x15/255, blink_factor),
                math.lerp(0, 0x14/255, blink_factor),
                1
            )
        end

        ui.pathArcTo(center, radius, start_angle, end_angle, 32)
        ui.pathStroke(fill_color, false, 18)
    end

    -- Steering indicator
    ui.pathClear()
    ui.pathArcTo(center, radius * 0.88, math.rad(-127), math.rad(-53), 32)
    ui.pathStroke(colors.SPEEDOMETER_DARK, false, 5)

    local steer_value = ac.getControllerSteerValue()
    local circle_angle = math.lerp(math.rad(-127), math.rad(-53), (steer_value + 1) / 2)
    local circle_center = vec2(
        center.x + math.cos(circle_angle) * radius * 0.88,
        center.y + math.sin(circle_angle) * radius * 0.88
    )
    ui.drawCircleFilled(circle_center, 5, colors.SPEEDOMETER_WHITE)

    -- Clutch arc
    ui.pathClear()
    ui.pathArcTo(center, radius * 0.88, math.rad(-210), math.rad(-152), 16)
    ui.pathStroke(colors.SPEEDOMETER_DARK, false, 5.5)
    if my_car.clutch < 1 then
        ui.pathClear()
        local end_angle = math.lerp(math.rad(-210), math.rad(-152), 1 - my_car.clutch)
        ui.pathArcTo(center, radius * 0.88, math.rad(-210), end_angle, 16)
        ui.pathStroke(rgbm(0x18/255, 0xfa/255, 0xfa/255, 1), false, 5.5)
    end

    -- Brake arc
    ui.pathClear()
    ui.pathArcTo(center, radius * 0.82, math.rad(-210), math.rad(-152), 16)
    ui.pathStroke(colors.SPEEDOMETER_DARK, false, 5.5)
    if my_car.brake > 0 then
        ui.pathClear()
        local end_angle = math.lerp(math.rad(-210), math.rad(-152), my_car.brake)
        ui.pathArcTo(center, radius * 0.82, math.rad(-210), end_angle, 16)
        ui.pathStroke(rgbm(1, 0, 0, 1), false, 5.5)
    end

    -- Gas arc
    ui.pathClear()
    ui.pathArcTo(center, radius * 0.88, math.rad(-28), math.rad(30), 16)
    ui.pathStroke(colors.SPEEDOMETER_DARK, false, 5.5)
    if my_car.gas > 0 then
        ui.pathClear()
        local end_angle = math.lerp(math.rad(30), math.rad(-28), my_car.gas)
        ui.pathArcTo(center, radius * 0.88, math.rad(30), end_angle, 16)
        ui.pathStroke(rgbm(0x39/255, 0xb5/255, 0x4a/255, 1), false, 5.5)
    end

    -- Fuel bar
    local fuelBarWidth = radius * 0.91
    local fuelBarHeight = radius * 0.09
    local fuelBarPos = vec2(
        center.x - fuelBarWidth / 2.1,
        center.y + radius * 0.95
    )

    ui.drawRectFilled(
        fuelBarPos,
        vec2(fuelBarPos.x + fuelBarWidth, fuelBarPos.y + fuelBarHeight),
        rgbm(0x3d/255, 0x3c/255, 0x45/255, 1)
    )

    local max_fuel = my_car.maxFuel > 0 and my_car.maxFuel or 1
    local fuel_percentage = math.clamp(my_car.fuel / max_fuel, 0, 1)

    ui.drawRectFilled(
        fuelBarPos,
        vec2(fuelBarPos.x + fuelBarWidth * fuel_percentage, fuelBarPos.y + fuelBarHeight),
        rgbm(1, 1, 254/255, 1)
    )

    local fuel_text = string.format("%.0fL", my_car.fuel)
    local fuel_text_size = radius * 0.11
    local fuel_text_offset = radius * 0.20
    if my_car.fuel >= 100 then
        fuel_text_offset = radius * 0.24
    end

    ui.pushDWriteFont('rajdhani:\\Fonts')
    ui.dwriteDrawText(
        fuel_text,
        fuel_text_size,
        vec2(fuelBarPos.x - fuel_text_offset, fuelBarPos.y - radius * 0.02),
        colors.SPEEDOMETER_WHITE
    )
    ui.popDWriteFont()

    -- Center image
    local image_size = radius * 1
    local image_pos = vec2(
        center.x - image_size / 2.05,
        center.y - radius * -0.595 - image_size / 2
    )
    ui.setCursor(image_pos)
    ui.image('materials/001.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.6), ui.ImageFit.Fit)

    -- TC block
    image_size = radius * 1
    image_pos = vec2(
        center.x - image_size / 0.85,
        center.y - radius * -0.795 - image_size / 2
    )

    if my_car.tractionControlModes > 0 then
        ui.setCursor(image_pos)
        ui.image('materials/012.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.6), ui.ImageFit.Fit)

        local tc_label_size = radius * 0.095
        local tc_value_size = radius * 0.11

        local tc_label_pos = vec2(
            image_pos.x + image_size * 0.41,
            image_pos.y + image_size * 0.44
        )
        local tc_value_pos = vec2(
            image_pos.x + image_size * 0.545,
            image_pos.y + image_size * 0.43
        )

        ui.pushDWriteFont('roboto:\\Fonts')
        ui.dwriteDrawText("TC ", tc_label_size, tc_label_pos, colors.SPEEDOMETER_WHITE)
        ui.popDWriteFont()

        ui.pushDWriteFont('rajdhani:\\Fonts')
        ui.dwriteDrawText(string.format("%d", my_car.tractionControlMode), tc_value_size, tc_value_pos, colors.SPEEDOMETER_WHITE)
        ui.popDWriteFont()
    end

    -- ABS block
    image_size = radius * 1
    image_pos = vec2(
        center.x - image_size / 3.80,
        center.y - radius * -0.795 - image_size / 2
    )

    if my_car.absModes > 0 then
        ui.setCursor(image_pos)
        ui.image('materials/012.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.6), ui.ImageFit.Fit)

        local abs_label_size = radius * 0.095
        local abs_value_size = radius * 0.11

        local abs_label_pos = vec2(
            image_pos.x + image_size * 0.37,
            image_pos.y + image_size * 0.44
        )
        local abs_value_pos = vec2(
            image_pos.x + image_size * 0.57,
            image_pos.y + image_size * 0.43
        )

        ui.pushDWriteFont('roboto:\\Fonts')
        ui.dwriteDrawText("ABS ", abs_label_size, abs_label_pos, colors.SPEEDOMETER_WHITE)
        ui.popDWriteFont()

        ui.pushDWriteFont('rajdhani:\\Fonts')
        ui.dwriteDrawText(string.format("%d", my_car.absMode), abs_value_size, abs_value_pos, colors.SPEEDOMETER_WHITE)
        ui.popDWriteFont()
    end

    -- Brake bias block
    image_size = radius * 1
    image_pos = vec2(
        center.x - image_size / -5,
        center.y - radius * -0.795 - image_size / 2
    )
    ui.setCursor(image_pos)
    ui.image('materials/012.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.6), ui.ImageFit.Fit)

    local bias_value = math.floor(my_car.brakeBias * 100)
    local bb_text_size = radius * 0.095
    local value_text_size = radius * 0.11

    local bb_text_pos = vec2(
        image_pos.x + image_size * 0.33,
        image_pos.y + image_size * 0.44
    )
    local value_text_pos = vec2(
        image_pos.x + image_size * 0.47,
        image_pos.y + image_size * 0.43
    )

    ui.pushDWriteFont('roboto:\\Fonts')
    ui.dwriteDrawText("BB ", bb_text_size, bb_text_pos, colors.SPEEDOMETER_WHITE)
    ui.popDWriteFont()

    ui.pushDWriteFont('rajdhani:\\Fonts')
    ui.dwriteDrawText(string.format("%d%%", bias_value), value_text_size, value_text_pos, colors.SPEEDOMETER_WHITE)
    ui.popDWriteFont()

    -- Indicator / lights / warning icons --------------------

    image_size = radius * 0.27
    image_pos = vec2(center.x - image_size / 0.42, center.y - radius * 0.52 - image_size / 2)
    ui.setCursor(image_pos)
    ui.image('materials/002.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.8), ui.ImageFit.Fit)
    if my_car.turningLightsActivePhase and (my_car.turningLeftLights or my_car.hazardLights) then
        ui.setCursor(image_pos)
        ui.image('materials/002b.png', vec2(image_size, image_size), rgbm(1, 1, 1, 1), ui.ImageFit.Fit)
    end

    image_size = radius * 0.27
    image_pos = vec2(center.x - image_size / -0.68, center.y - radius * 0.515 - image_size / 2)
    ui.setCursor(image_pos)
    ui.image('materials/003.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.8), ui.ImageFit.Fit)
    if my_car.turningLightsActivePhase and (my_car.turningRightLights or my_car.hazardLights) then
        ui.setCursor(image_pos)
        ui.image('materials/003b.png', vec2(image_size, image_size), rgbm(1, 1, 1, 1), ui.ImageFit.Fit)
    end

    image_size = radius * 0.27
    image_pos = vec2(center.x - image_size / 0.45, center.y - radius * 0.27 - image_size / 2)
    ui.setCursor(image_pos)
    ui.image('materials/004.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.8), ui.ImageFit.Fit)
    if my_car.headlightsActive and my_car.lowBeams then
        ui.setCursor(image_pos)
        ui.image('materials/004b.png', vec2(image_size, image_size), rgbm(1, 1, 1, 1), ui.ImageFit.Fit)
    end
    if my_car.headlightsActive and not my_car.lowBeams then
        ui.setCursor(image_pos)
        ui.image('materials/004c.png', vec2(image_size, image_size), rgbm(1, 1, 1, 1), ui.ImageFit.Fit)
    end

    image_size = radius * 0.27
    image_pos = vec2(center.x - image_size / -0.77, center.y - radius * 0.25 - image_size / 2)
    ui.setCursor(image_pos)
    ui.image('materials/005.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.8), ui.ImageFit.Fit)

    image_size = radius * 0.27
    image_pos = vec2(center.x - image_size / 0.45, center.y - radius * 0.06 - image_size / 2)
    ui.setCursor(image_pos)
    ui.image('materials/006.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.8), ui.ImageFit.Fit)
    if my_car.absInAction then
        ui.setCursor(image_pos)
        ui.image('materials/006b.png', vec2(image_size, image_size), rgbm(1, 1, 1, 1), ui.ImageFit.Fit)
    end

    image_size = radius * 0.27
    image_pos = vec2(center.x - image_size / 0.45, center.y - radius * -0.17 - image_size / 2)
    ui.setCursor(image_pos)
    ui.image('materials/007.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.8), ui.ImageFit.Fit)
    if my_car.tractionControlInAction then
        ui.setCursor(image_pos)
        ui.image('materials/007b.png', vec2(image_size, image_size), rgbm(1, 1, 1, 1), ui.ImageFit.Fit)
    end

    image_size = radius * 0.27
    image_pos = vec2(center.x - image_size / 0.45, center.y - radius * -0.39 - image_size / 2)
    ui.setCursor(image_pos)
    ui.image('materials/008.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.8), ui.ImageFit.Fit)
    if my_car.handbrake > 0 then
        ui.setCursor(image_pos)
        ui.image('materials/008b.png', vec2(image_size, image_size), rgbm(1, 1, 1, 1), ui.ImageFit.Fit)
    end

    image_size = radius * 0.27
    image_pos = vec2(center.x - image_size / -1.04, center.y - radius * -0.35 - image_size / 2)
    ui.setCursor(image_pos)
    if my_car.engineLifeLeft < 500 then
        ui.image('materials/009b.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.8), ui.ImageFit.Fit)
    else
        ui.image('materials/009.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.8), ui.ImageFit.Fit)
    end

    image_size = radius * 0.27
    image_pos = vec2(center.x - image_size / -0.54, center.y - radius * -0.275 - image_size / 2)
    ui.setCursor(image_pos)
    if my_car.engineLifeLeft <= 0 then
        ui.image('materials/010b.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.8), ui.ImageFit.Fit)
    else
        ui.image('materials/010.png', vec2(image_size, image_size), rgbm(1, 1, 1, 0.8), ui.ImageFit.Fit)
    end

    image_size = radius * 0.27
    image_pos = vec2(center.x - image_size / 0.30, center.y - radius * -0.99 - image_size / 2)
    ui.setCursor(image_pos)
    ui.image('materials/011.png', vec2(image_size, image_size), rgbm(1, 1, 1, 1), ui.ImageFit.Fit)

    -- Gear text
    local gear_positions = {
        N   = vec2(center.x - radius * 0.31, center.y - radius * 0.67),
        ["1"]   = vec2(center.x - radius * 0.20, center.y - radius * 0.68),
        ["2-3"] = vec2(center.x - radius * 0.25, center.y - radius * 0.68),
        ["4-6"] = vec2(center.x - radius * 0.30, center.y - radius * 0.68),
        ["7"]   = vec2(center.x - radius * 0.20, center.y - radius * 0.68),
        ["8-9"] = vec2(center.x - radius * 0.30, center.y - radius * 0.68),
        R   = vec2(center.x - radius * 0.31, center.y - radius * 0.69)
    }

    ui.pushDWriteFont('rajdhani:\\Fonts')

    local gear_text, gear_pos
    if my_car.gear == 0 then
        gear_text = "N"
        gear_pos = gear_positions.N
    elseif my_car.gear == -1 then
        gear_text = "R"
        gear_pos = gear_positions.R
    elseif my_car.gear == 1 then
        gear_text = "1"
        gear_pos = gear_positions["1"]
    elseif my_car.gear >= 2 and my_car.gear <= 3 then
        gear_text = tostring(my_car.gear)
        gear_pos = gear_positions["2-3"]
    elseif my_car.gear >= 4 and my_car.gear <= 6 then
        gear_text = tostring(my_car.gear)
        gear_pos = gear_positions["4-6"]
    elseif my_car.gear == 7 then
        gear_text = "7"
        gear_pos = gear_positions["7"]
    else
        gear_text = tostring(my_car.gear)
        gear_pos = gear_positions["8-9"]
    end

    local text_size = radius * 1.07
    local gear_color = colors.SPEEDOMETER_WHITE
    if current_rpm_fill > 0.87 then
        gear_color = colors.RPM_WARNING
    end
    if current_rpm_fill > 0.92 then
        blink_time = blink_time + dt * 18
        local blink_factor = (math.sin(blink_time) + 1) / 2
        gear_color = rgbm(
            math.lerp(1, 1, blink_factor),
            math.lerp(0, 1, blink_factor),
            math.lerp(0, 1, blink_factor),
            1
        )
    else
        blink_time = 0
    end

    ui.dwriteDrawText(gear_text, text_size, gear_pos, gear_color)
    ui.popDWriteFont()

    -- Distance (odometer)
    local distance_value = my_car.distanceDrivenTotalKm
    if not isKmh then
        distance_value = distance_value * 0.621371
    end
    local distance_text = string.format("%d %s", math.floor(distance_value), isKmh and "km" or "mi")
    local distance_size = radius * 0.10
    ui.dwriteDrawText(distance_text, distance_size, vec2(center.x - radius * 0.12, center.y - radius * -0.53), colors.SPEEDOMETER_WHITE)

    -- Speed
    local speed_value = math.floor(my_car.speedKmh)
    if not isKmh then
        speed_value = math.floor(speed_value * 0.621371)
    end

    local speed_text
    local speed_pos_y = center.y - radius * 0.93
    local speed_pos_x = center.x - radius * 0.255

    if speed_value < 10 then
        speed_text = string.format("  %d", speed_value)
        speed_pos_x = center.x - radius * 0.255
    elseif speed_value < 100 then
        speed_text = string.format(" %d", speed_value)
        speed_pos_x = center.x - radius * 0.225
    else
        speed_text = string.format("%d", speed_value)
        speed_pos_y = speed_pos_y + radius * 0.07
        speed_pos_x = center.x - radius * 0.240
    end

    local speed_text_size = radius * 0.33
    local speed_pos = vec2(speed_pos_x, speed_pos_y)

    ui.pushDWriteFont('Untitled1:\\Fonts')
    ui.dwriteDrawText(speed_text, speed_text_size, speed_pos, colors.SPEEDOMETER_WHITE)
    ui.popDWriteFont()

    local kmh_label_size = radius * 0.09
    local kmh_label_pos = vec2(center.x - radius * 0.105, center.y - radius * 0.53)
    ui.pushDWriteFont('roboto:\\Fonts')
    ui.dwriteDrawText(isKmh and "km/h" or "mp/h", kmh_label_size, kmh_label_pos, colors.SPEEDOMETER_WHITE)
    ui.popDWriteFont()

    -- RPM numeric
    local actual_rpm = math.floor(my_car.rpm)
    local main_digits = math.floor(actual_rpm / 100) * 100
    local actual_last_two = actual_rpm % 100

    frame_counter = frame_counter + 1
    if frame_counter >= 5 then
        frame_counter = 0
        last_displayed_rpm = actual_last_two
    end

    local rpm_value = main_digits + (last_displayed_rpm or 0)
    local rpm_text
    local rpm_pos_y = center.y - radius * 0.142

    if rpm_value < 1000 then
        rpm_text = string.format("   %d", rpm_value)
    elseif rpm_value < 10000 then
        rpm_text = string.format("  %d", rpm_value)
    else
        rpm_text = string.format(" %d", rpm_value)
    end

    local rpm_text_size = radius * 0.17
    local rpm_pos = vec2(center.x + radius * 0.345, rpm_pos_y)

    ui.pushDWriteFont('rajdhani:\\Fonts')
    ui.dwriteDrawText(rpm_text, rpm_text_size, rpm_pos, colors.SPEEDOMETER_WHITE)
    ui.popDWriteFont()

    local rpm_label_size = radius * 0.12
    local rpm_label_pos = vec2(rpm_pos.x + radius * 0.12, rpm_pos.y + radius * 0.15)

    ui.pushDWriteFont('roboto:\\Fonts')
    ui.dwriteDrawText("rpm", rpm_label_size, rpm_label_pos, colors.SPEEDOMETER_WHITE)
    ui.popDWriteFont()
end

-- Window + input ----------------------------------------------------------

local function windowMain(dt, screenSize)
    local sim = ac.getSim()
    if not sim then return end

    local car = ac.getCar(sim.focusedCar)
    if not car then return end

    -- Double-click anywhere on the HUD window to toggle kmh/mi
    if ui.mouseClicked(0) and ui.windowHovered() then
        local currentTime = ui.time()
        if currentTime - lastClickTime < doubleClickThreshold then
            isKmh = not isKmh
            STORAGE_UNIT.value = isKmh
            lastClickTime = 0
        else
            lastClickTime = currentTime
        end
    end

    local speedometer_center = vec2(screenSize.x / 2, screenSize.y / 2)
    local speedometer_radius = math.min(screenSize.x, screenSize.y) * 0.4 * Size

    drawSpeedometer(car, speedometer_center, speedometer_radius, dt)
end

-- Logic-only update: NO ui.* here
function script.update(dt)
    -- keep empty for now (or put non-UI logic here)
end

-- UI drawing context: CSP calls this for server script UI
function script.drawUI(dt)
    dt = dt or (ac.getDeltaT and ac.getDeltaT() or 0.016)

    -- full-screen transparent window, no setNextWindow* needed
    local ws = ui.windowSize()
    ui.beginTransparentWindow('ACEvoHUD_Main', vec2(0, 0), ws)
    windowMain(dt, ws)
    ui.endWindow()
end

