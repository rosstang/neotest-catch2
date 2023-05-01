local lxp = require("lxp")

local M = {}
M.__index = M

local TestsHandler = {}
TestsHandler.__index = TestsHandler

TestsHandler.new = function()
	local self = {}
	self.handlers = {}
    self.nodes_stack = {}
	self.results = {}

	self.handlers.TestCase = {
		on_start = function(attr)
			local test_name = '"' .. attr.name .. '"'
			return {
				test_name = test_name,
				name = attr.filename .. "::" .. test_name,
				filename = attr.filename,
				line = attr.line,
			}
		end,
		on_stop = function(node)
            self.result[node.name] = node
		end,
	}

	self.handlers.OverallResult = {
		on_start = function(attr)
            return {
                status = attr.success == "true" and "passed" or "failed"
            }
		end,
        on_stop = function(node)
            local test_case = self.nodes_stack[#self.nodes_stack]
            test_case.status = node.status
        end
	}

	self.handlers.Section = {
		on_start = function(attr)
			local section_name = '"' .. attr.name .. '"'
			return {
				section_name = section_name,
				filename = attr.filename,
				line = attr.line,
			}
		end,
		on_stop = function(node)
            local parent = self.nodes_stack[#self.nodes_stack]
            if parent.sections == nil then
                parent.sections = {}
            end
            table.insert(parent.sections, node)
		end,
	}

	setmetatable(self, TestsHandler)
	return self
end

TestsHandler.on_start = function(self, name, attr)
    local handler = self.handlers[name]
	if handler ~= nil then
        local node = handler.on_start(attr)
        node.tag = name
        table.insert(self.nodes_stack, node)
    end
end

TestsHandler.on_stop = function(self, name)
    local handler = self.handlers[name]
    if handler ~= nil then
        local node = table.remove(self.nodes_stack, #self.nodes_stack)
        if handler.on_stop then
            handler.on_stop(node)
        end
    end
end

TestsHandler.on_char = function(self, str)
    local node = self.nodes_stack[#self.nodes_stack]
    if node.text == nil then
        node.text = ""
    end
    node.text = node.text .. str
end

M.new_parser = function()
    print("creating new parser")
	local tests_handler = TestsHandler.new()
	local self = {
		handler = tests_handler,
	}

	local callbacks = {
		StartElement = function(_, name, attr)
            tests_handler:on_start(name, attr)
		end,
		EndElement = function(_, name)
            tests_handler:on_stop(name)
		end,
		CharacterData = function(_, str)
            tests_handler:on_char(str)
		end,
	}
	self.parser = lxp.new(callbacks)
    setmetatable(self, M)
    print("self = ", vim.inspect(self))
	return self
end

M.parse = function(self, lines)
	for l in lines do
		self.parser:parse(l)
	end
	self.parser:parse()
	self.parser:close()
	return self.handler.results
end

return M
