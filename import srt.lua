-- Function to convert SRT file to regions in Reaper
local function load_srt_file(file_path)
    local file = io.open(file_path, "r")
    if not file then 
        reaper.ShowMessageBox("Failed to open file: " .. file_path, "Error", 0)
        return nil
    end

    local regions = {}
    while true do
        local line = file:read("*line")
        if not line then break end

        if tonumber(line) then
            local timecode_in = file:read("*line")
            local text = file:read("*line")
            file:read("*line") -- Skip the blank line

            if timecode_in then
                -- Match timecode pattern with spaces around arrow
                local start_hour, start_min, start_sec, start_ms, end_hour, end_min, end_sec, end_ms = 
                    timecode_in:match("(%d+):(%d+):(%d+),(%d+) %-%-> (%d+):(%d+):(%d+),(%d+)")

                if start_hour and start_min and start_sec and start_ms and end_hour and end_min and end_sec and end_ms then
                    local start_pos = (tonumber(start_hour) * 3600 + tonumber(start_min) * 60 + tonumber(start_sec) + tonumber(start_ms) / 1000)
                    local end_pos = (tonumber(end_hour) * 3600 + tonumber(end_min) * 60 + tonumber(end_sec) + tonumber(end_ms) / 1000)
                    regions[#regions + 1] = { start_pos = start_pos, end_pos = end_pos, name = text }
                else
                    reaper.ShowMessageBox("Failed to parse timecode in line: " .. timecode_in, "Error", 0)
                end
            else
                reaper.ShowMessageBox("Unexpected format in SRT file.", "Error", 0)
            end
        end
    end
    file:close()
    return regions
end

local function add_regions(regions)
    for i = 1, #regions do
        reaper.AddProjectMarker2(0, true, regions[i].start_pos, regions[i].end_pos, regions[i].name, -1, 0)
    end
end

-- Main script execution
local retval, file_path = reaper.GetUserFileNameForRead("", "Select SRT file", ".srt")
if retval then
    local regions = load_srt_file(file_path)
    if regions and #regions > 0 then
        add_regions(regions)
        reaper.ShowMessageBox("Regions added successfully.", "Info", 0)
    else
        reaper.ShowMessageBox("No regions to add. Check the SRT file format.", "Error", 0)
    end
end
