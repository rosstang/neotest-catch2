local util = require("neotest-catch2.util")

local M = {}
M.__index = M

local create_simple_handler = function(self, field_name)
	return {
		on_start = function(_)
			return {}
		end,
		on_stop = function(node)
			local parent = self.nodes_stack[#self.nodes_stack]
			parent[field_name] = util.trim(node.text)
			node.text = nil
		end,
	}
end

M.new = function()
	local self = {}
	self.handlers = {}
	self.nodes_stack = {}
	self.results = {}

	self.handlers.TestCase = {
		on_start = function(attr)
			return {}
		end,
		on_stop = function(node)
			local id = node.source_info.file .. "::" .. node.name
			local lineno = tonumber(node.source_info.line) - 1
			table.insert(self.results, {
				name = node.name,
				type = "test",
				id = id,
				path = node.source_info.file,
				range = { lineno, 0, lineno, 0 },
			})
			print("position results = " .. vim.inspect(self.results))
		end,
	}

	self.handlers.SourceInfo = {
		on_start = function(attr)
			return {}
		end,
		on_stop = function(node)
			local parent = self.nodes_stack[#self.nodes_stack]
            node.file = util.normalize(node.file)
			parent.source_info = node
		end,
	}
	self.handlers.Name = create_simple_handler(self, "name")
	self.handlers.File = create_simple_handler(self, "file")
	self.handlers.Line = create_simple_handler(self, "line")

	setmetatable(self, M)
	return self
end

M.on_start = function(self, name, attr)
	local handler = self.handlers[name]
	if handler ~= nil then
		local node = handler.on_start(attr)
		node.tag = name
		table.insert(self.nodes_stack, node)
	end
end

M.on_stop = function(self, name)
	local handler = self.handlers[name]
	if handler ~= nil then
		local node = table.remove(self.nodes_stack, #self.nodes_stack)
		if handler.on_stop then
			handler.on_stop(node)
		end
	end
end

M.on_char = function(self, str)
	local node = self.nodes_stack[#self.nodes_stack]
	if node == nil then
		return
	end
	if node.text == nil then
		node.text = ""
	end
	node.text = node.text .. "\n" .. str
end

return M
