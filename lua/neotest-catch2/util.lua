local context_manager = require("plenary.context_manager")
local with = context_manager.with
local open = context_manager.open

local M = {}

M.trim = function(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

M.to_string = function(x)
	return x == nil and "" or x
end

M.get_file_name = function(path)
	return path:match(".+/([^/]+)%.%w+$")
end

M.get_file_name_ext = function(path)
	return path:match(".+/([^/]+)$")
end

M.dump = function(filename, x)
	with(open(filename, "w"), function(file)
		file:write(vim.inspect(x))
	end)
end

M.write = function(filename, str)
	with(open(filename, "a"), function(file)
		file:write(str)
	end)
end

M.touch = function(filename)
	with(open(filename, "w"), function(file)
		file:write("")
	end)
end

M.get_file_lines = function(path)
	local count = 0
	for _ in io.lines(path) do
		count = count + 1
	end
	return count
end

return M
