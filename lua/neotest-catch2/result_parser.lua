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
            if node.texts ~= nil then
                local parent = self.nodes_stack[#self.nodes_stack]
                parent[field_name] = table.concat(node.texts, "")
            end
        end,
    }
end

local create_file_handler = function(self, field_name)
    return {
        on_start = function(_)
            local output_file = async.fn.tempname() .. ".out"
            return {
                output = output_file,
                file_handle = io.open(output_file, "w"),
            }
        end,
        on_stop = function(node)
            if node.file_handle ~= nil then
                node.file_handle:close()
            end
            local parent = self.nodes_stack[#self.nodes_stack]
            parent[field_name] = { output = node.output }
        end,
    }
end

local get_text = function(node)
    if node.text ~= nil then
        return node.text
    end
    if node.texts ~= nil then
        return table.concat(node.texts, "")
    end
    return ""
end

local create_error_handler = function(self, error_name)
    return {
        on_start = function(attr)
            return {
                filename = util.normalize(attr.filename),
                line = tonumber(attr.line),
            }
        end,
        on_stop = function(node)
            local parent = self.nodes_stack[#self.nodes_stack]
            if parent.errors == nil then
                parent.errors = {}
            end
            local message = error_name .. ": " .. get_text(node)
            table.insert(parent.errors, {
                filename = node.filename,
                line = node.line - 1,
                message = message,
            })
        end,
    }
end

M.new = function(use_queue)
    local self = {}
    self.handlers = {}
    self.nodes_stack = {}
    self.stop = false

    local add_result
    if use_queue then
        self.results = nio.control.queue()
        add_result = function(r)
            self.results.put(r)
        end
    else
        self.results = {}
        add_result = function(r)
            self.results[r.name] = r
        end
    end

    self.handlers.Catch2TestRun = {
        on_start = function(attr)
            return {}
        end,
        on_stop = function(node)
            self.stop = true
        end,
    }
    self.handlers.TestCase = {
        on_start = function(attr)
            local test_name = attr.name
            local filename = util.normalize(attr.filename)
            return {
                test_name = test_name,
                name = filename .. "::" .. test_name,
                filename = filename,
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
                        if out[2] ~= nil then
                            with(open(out[2].output, 'r'), function(reader)
                                writer:write(reader:read("*all"))
                            end)
                        end
                    end
                end)
            end
            if node.errors ~= nil then
                local errors = {}
                for _, e in ipairs(node.errors) do
                    if e.line ~= nil then
                        table.insert(errors, e.filename .. ":" .. (e.line + 1))
                    end
                    table.insert(errors, "    " .. e.message)
                    if e.filename ~= node.filename then
                        e.line = nil
                    end
                    e.filename = nil
                end
                node.short = table.concat(errors, "\n")
            end
            add_result({
                name = node.name,
                errors = node.errors,
                short = node.short,
                output = node.output,
                status = node.status,
            })
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
                filename = util.normalize(attr.filename),
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
            table.insert(parent.sections, {
                section_name = node.section_name,
                filename = node.filename,
                line = node.line,
                errors = node.errors,
            })
        end,
    }

    self.handlers.Expression = {
        on_start = function(attr)
            return {
                filename = util.normalize(attr.filename),
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
            node.texts = nil
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

    self.handlers.FatalErrorCondition = create_error_handler(self, "FatalErrorCondition")
    self.handlers.Exception = create_error_handler(self, "Exception")
    self.handlers.StdOut = create_file_handler(self, "stdout")
    self.handlers.StdErr = create_file_handler(self, "stderr")
    self.handlers.Original = create_simple_handler(self, "original")
    self.handlers.Expanded = create_simple_handler(self, "expanded")
    self.handlers.Info = {
        on_start = function()
            return {}
        end,
        on_stop = function(node)
            local parent = self.nodes_stack[#self.nodes_stack]
            if parent.errors == nil then
                parent.errors = {}
            end
            table.insert(parent.errors, {
                message = get_text(node),
            })
        end,
    }

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
    if node.file_handle ~= nil then
        node.file_handle:write(str)
        return
    elseif node.texts == nil then
        node.texts = {}
    end
    table.insert(node.texts, str)
end

return M
