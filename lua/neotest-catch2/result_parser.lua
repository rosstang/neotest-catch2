local util = require("neotest-catch2.util")
local async = require("neotest.async")
local nio = require("nio")
local context_manager = require("plenary.context_manager")
local with = context_manager.with
local open = context_manager.open

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

M.new = function(use_queue)
	local self = {}
	self.handlers = {}
	self.nodes_stack = {}
    local add_result
    if use_queue then
    	self.results = nio.control.queue()
        add_result = function(r)
            print("result = ", vim.inspect(r))
            self.results.put_nowait(r)
        end
    else
        self.results = {}
        add_result = function(r)
            self.results[r.name] = r
        end
    end

	self.handlers.TestCase = {
		on_start = function(attr)
			local test_name = '"' .. attr.name .. '"'
			return {
				test_name = test_name,
				name = attr.filename .. "::" .. test_name,
				filename = attr.filename,
				line = tonumber(attr.line),
			}
		end,
		on_stop = function(node)
			if node.stdout ~= nil or node.stderr ~= nil then
				local output_file = async.fn.tempname() .. ".out"
				node.output = output_file
				with(open(output_file, "a"), function(writer)
					for _, out in pairs({
						{ "STDOUT", node.stdout },
						{ "STDERR", node.stderr },
					}) do
						writer:write(out[1] .. "\n")
						writer:write((out[2] == nil and "" or out[2]) .. "\n")
					end
				end)
			end
			if node.errors ~= nil then
				local errors = {}
				node.errors = vim.tbl_filter(function(e)
					return e.filename == node.filename
				end, node.errors)
				for _, e in ipairs(node.errors) do
					table.insert(errors, e.filename .. ":" .. (e.line + 1))
					table.insert(errors, "    " .. e.message)
					e.filename = nil
				end
				node.short = table.concat(errors, "\n")
			end
			node.text = nil
			node.test_name = nil
			node.filename = nil
			node.line = nil
			node.tag = nil
			node.stdout = nil
			node.stderr = nil
			node.sections = nil
            add_result(node)
		end,
	}

	self.handlers.OverallResult = {
		on_start = function(attr)
			return {
				status = attr.success == "true" and "passed" or "failed",
			}
		end,
		on_stop = function(node)
			local parent = self.nodes_stack[#self.nodes_stack]
			parent.status = node.status
			if node.stdout ~= nil then
				parent.stdout = node.stdout
			end
			if node.stderr ~= nil then
				parent.stderr = node.stderr
			end
		end,
	}

	self.handlers.Section = {
		on_start = function(attr)
			local section_name = '"' .. util.to_string(attr.name) .. '"'
			return {
				section_name = section_name,
				filename = attr.filename,
				line = tonumber(attr.line),
			}
		end,
		on_stop = function(node)
			local parent = self.nodes_stack[#self.nodes_stack]
			if parent.sections == nil then
				parent.sections = {}
			end
			if parent.errors == nil and node.errors ~= nil then
				parent.errors = {}
			end
			if node.errors ~= nil then
				parent.errors = vim.list_extend(parent.errors, node.errors)
			end
			node.text = nil
			table.insert(parent.sections, node)
		end,
	}

	self.handlers.Expression = {
		on_start = function(attr)
			return {
				filename = attr.filename,
				line = tonumber(attr.line),
			}
		end,
		on_stop = function(node)
			local parent = self.nodes_stack[#self.nodes_stack]
			if parent.expressions == nil then
				parent.expressions = {}
			end
			if parent.errors == nil then
				parent.errors = {}
			end
			node.text = ""
			table.insert(parent.expressions, node)
			local message = "FAILED: "
				.. (node.original ~= nil and node.original or "<empty>")
				.. ", with expansion: "
				.. (node.expanded ~= nil and node.expanded or "<empty>")
			table.insert(parent.errors, {
				filename = node.filename,
				line = node.line - 1,
				message = message,
			})
		end,
	}

	self.handlers.StdOut = create_simple_handler(self, "stdout")
	self.handlers.StdErr = create_simple_handler(self, "stderr")
	self.handlers.Original = create_simple_handler(self, "original")
	self.handlers.Expanded = create_simple_handler(self, "expanded")
	self.handlers.Info = create_simple_handler(self, "info")

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
