-- Import required libraries
require 'cairo'
local status, cairo_xlib = pcall(require, 'cairo_xlib')
if not status then
    cairo_xlib = setmetatable({}, {
        __index = function(_, k)
            return _G[k]
        end
    })
end

-- Cache bestanden en scroll instellingen
local cache_file = "/tmp/apt_updates_cache.txt"
local cache_duration = 3600  -- 1 uur
local scroll_speed = 10  -- pixels per seconde
local scroll_start = 30  -- y-startpositie
local line_height = 15
local visible_lines = 10  -- Maximaal aantal zichtbare regels in Conky
local max_line_length = 29  -- Maximale breedte van elke tekstregel (aantal karakters)

-- Interne staat
local scroll_offset = 0
local last_update_time = os.time()
local original_lines = {}
local repeated_lines = {}

-- Cache vernieuwen voor apt-updates
local function update_cache()
    local handle = io.popen("stat -c %Y " .. cache_file .. " 2>/dev/null")
    local last_update = tonumber(handle:read("*a")) or 0
    handle:close()
    if (os.time() - last_update) > cache_duration then
        os.execute("apt list --upgradable > " .. cache_file .. " 2>/dev/null")
        -- Opmerking: Als 'apt' sudo vereist, gebruik dan:
        -- os.execute("sudo apt list --upgradable > " .. cache_file .. " 2>/dev/null")
        -- Zorg ervoor dat sudo zonder wachtwoord werkt of dat de cache-bestanden toegankelijk zijn.
    end
end

-- Laden van pakketregels uit cache
local function load_package_lines()
    original_lines = {}

    -- Voeg apt-updates toe
    local file = io.open(cache_file, "r")
    if file then
        for line in file:lines() do
            -- Sla de eerste regel over ("Listing...") en parse pakketnamen
            if not line:match("^Listing...") then
                local package_name = line:match("^%S+/") -- Pakketnaam voor de eerste slash
                if package_name then
                    package_name = package_name:gsub("/.*", "") -- Verwijder alles na de slash
                    if #package_name > max_line_length then
                        package_name = package_name:sub(1, max_line_length - 3) .. "..."
                    end
                    table.insert(original_lines, package_name)
                end
            end
        end
        file:close()
    end

    -- Herhaal de lijst met twee lege regels als scheiding
    repeated_lines = {}
    for _ = 1, 2 do
        for _, line in ipairs(original_lines) do
            table.insert(repeated_lines, line)
        end
        table.insert(repeated_lines, "")
        table.insert(repeated_lines, "")
    end
end

-- Hoofdfunctie
function conky_draw_text()
    if conky_window == nil then return end
    local cs = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                         conky_window.visual, conky_window.width, conky_window.height)
    local cr = cairo_create(cs)

    -- Update cache en laad regels
    update_cache()
    load_package_lines()

    -- Hoofdtekst: aantal updates
    local update_count = #original_lines
    local info_text = (update_count == 0) and "System is up-to-date" or tostring(update_count) .. " updates available"
    local kleur = (update_count == 0)
        and {{0, 0x00FF00, 1}}
        or { {0, 0xFFA500, 1}, {1, 0xFF0000, 1} }

    local text_settings = {
        {
            text = info_text,
            font_name = "Ubuntu",
            font_size = 20,
            h_align = "c",
            v_align = "t",
            bold = true,
            x = conky_window.width / 2,
            y = 20,
            orientation = "nn",
            colour = kleur
        }
    }

    -- Scroll-positie bijwerken
    local current_time = os.time()
    local elapsed = os.difftime(current_time, last_update_time)
    scroll_offset = (scroll_offset + scroll_speed * elapsed) % (#repeated_lines * line_height)
    last_update_time = current_time

    -- Pakketten tekenen
    for i = 1, math.min(visible_lines, #repeated_lines) do
        local index = (math.floor(scroll_offset / line_height) + i - 1) % #repeated_lines + 1
        local line = repeated_lines[index]
        if line then
            table.insert(text_settings, {
                text = line,
                font_name = "Dejavu Sans Mono",
                font_size = 14,
                h_align = "l",
                v_align = "t",
                bold = false,
                x = 16,
                y = scroll_start + 20 + (i - 1) * line_height - (scroll_offset % line_height),
                orientation = "nn",
                colour = {{0, 0x42E147, 1}}
            })
        end
    end

    -- Tekst tekenen
    for _, t in ipairs(text_settings) do
        display_text(cr, t)
    end

    cairo_destroy(cr)
    cairo_surface_destroy(cs)
end

-- Tekstweergave-functie
function display_text(cr, t)
    if not t.text then return end
    cairo_select_font_face(cr,
        t.font_name or "Sans",
        CAIRO_FONT_SLANT_NORMAL,
        (t.bold and CAIRO_FONT_WEIGHT_BOLD or CAIRO_FONT_WEIGHT_NORMAL)
    )
    cairo_set_font_size(cr, t.font_size or 12)

    local extents = cairo_text_extents_t:create()
    cairo_text_extents(cr, t.text, extents)

    local x = t.x or 0
    local y = t.y or 0
    if t.h_align == "c" then x = x - extents.width / 2
    elseif t.h_align == "r" then x = x - extents.width end
    if t.v_align == "m" then y = y + extents.height / 2
    elseif t.v_align == "b" then y = y + extents.height
    elseif t.v_align == "t" then y = y - extents.y_bearing end

    cairo_move_to(cr, x, y)
    set_pattern(cr, t)
    cairo_show_text(cr, t.text)
    cairo_stroke(cr)
end

-- Kleurpatronen
function set_pattern(cr, t)
    if #t.colour == 1 then
        cairo_set_source_rgba(cr, rgba(t.colour[1]))
    else
        local pat = cairo_pattern_create_linear(linear_orientation(t))
        for _, stop in ipairs(t.colour) do
            cairo_pattern_add_color_stop_rgba(pat, stop[1], rgba(stop))
        end
        cairo_set_source(cr, pat)
        cairo_pattern_destroy(pat)
    end
end

function linear_orientation(t)
    local x1, y1, x2, y2 = 0, 0, 0, 0
    local text_len = string.len(t.text or "")
    local font_size = t.font_size or 12
    local w = text_len * font_size * 0.6
    local ori = t.orientation or "nn"
    if ori == "nn" then x2 = w end
    return x1, y1, x2, y2
end

function rgba(colour)
    local r = ((colour[2] / 0x10000) % 0x100) / 255
    local g = ((colour[2] / 0x100) % 0x100) / 255
    local b = (colour[2] % 0x100) / 255
    local a = colour[3] or 1
    return r, g, b, a
end