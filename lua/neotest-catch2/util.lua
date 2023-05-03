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

M.touch = function(filename)
	with(open(filename, "w"), function(file)
        file:write("")
	end)
end

return M
