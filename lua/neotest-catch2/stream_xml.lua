local lib = require("neotest.lib")
local nio = require("nio")
local lxp = require("lxp")
local util = require("neotest-catch2.util")

local EventType = {
	start = "start",
	stop = "stop",
	on_char = "on_char",
}

local M = {}

-- parse the whole xml filename, and use handler to handle
-- the xml elements
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

	local data = file:read("a")
	parser:parse(data)
	parser:parse()
	parser:close()
	file:close()
	return handler.results
end

-- parse the xml filename with streaming, and convert the start element/stop element/
-- character data into events put into an event queue
M.stream_xml = function(filename)
	local stream_data, stop_stream = lib.files.stream(filename)
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
    M.parser = parser

	local parse = function()
		for s in stream_data do
			parser:parse(s)
			parser:parse("\n")
		end
	end

	nio.run(parse, function(success, err)
		if not success then
			print("Error while splitting lines: " .. err)
		end
	end)

	return queue.get, function()
        stop_stream()
        parser:parse()
        parser:close()
    end
end

-- given a handler and a event, call the callback function from handler
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
