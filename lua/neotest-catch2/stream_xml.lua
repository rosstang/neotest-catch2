local lib = require("neotest.lib")
local nio = require("nio")
local lxp = require("lxp")

local EventType = {
	start = "start",
	stop = "stop",
	on_char = "on_char",
}

local M = {}

M.parse_xml = function(filename, handler)
	local file = io.open(filename)
    if file == nil then
        return {}
    end
	local parser = lxp.new({
		StartElement = function(_, name, attr)
            handler:on_start(name, attr)
		end,
		EndElement = function(_, name)
            handler:on_stop(name)
		end,
		CharacterData = function(_, str)
            handler:on_char(str)
		end,
	})

    for l in file:lines() do
        parser:parse(l)
    end
    parser:parse()
    parser:close()
    file:close()
    return handler.results
end

M.stream_xml = function(filename)
	local stream_data, stop_stream = lib.files.stream_lines(filename)
	local queue = nio.control.queue()

	local parser = lxp.new({
		StartElement = function(_, name, attr)
			queue.put_nowait({
				event_type = EventType.start,
				name = name,
				attr = attr,
			})
		end,
		EndElement = function(_, name)
			queue.put_nowait({
				event_type = EventType.stop,
				name = name,
			})
		end,
		CharacterData = function(_, str)
			queue.put_nowait({
				event_type = EventType.on_char,
				char_data = str,
			})
		end,
	})

	local parse = function()
		for lines in stream_data do
			for _, l in ipairs(lines) do
				parser:parse(l)
			end
		end
		parser:parse()
		parser:close()
	end

	nio.run(parse, function(success, err)
		if not success then
			print("Error while splitting lines: " .. err)
		end
	end)

	return queue.get, stop_stream
end

M.dispatch = function(event, handler)
	if event.event_type == EventType.start then
		handler:on_start(event.name, event.attr)
	elseif event.event_type == EventType.stop then
		handler:on_stop(event.name)
	elseif event.event_type == EventType.on_char then
		handler:on_char(event.char_data)
	end
end

return M

