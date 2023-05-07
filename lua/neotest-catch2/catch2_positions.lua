local cmake = require("neotest-catch2.cmake")
local util = require("neotest-catch2.util")
local positions = require("neotest.lib.positions")
local position_parser = require("neotest-catch2.position_parser")
local xml = require('neotest-catch2.stream_xml')
local async = require("neotest.async")

local M = {}

function M.discover_positions_v3(config, path)
	local sources = cmake.get_executable_sources()
	if sources == nil then
		return {}
	end
	local executable = sources[path]
	if executable == nil then
		return {}
	end
	local filename = util.get_file_name(path)
	local xml_file = async.fn.tempname() .. ".xml"
	local args = {
		executable,
		"--list-test",
		"-r",
		"xml",
		"-#",
		"-o",
		xml_file,
		'"[#' .. filename .. ']"',
	}
	local ret = vim.fn.systemlist(table.concat(args, " "))
	local tests = {
		{
			name = util.get_file_name_ext(path),
			type = "file",
			id = path,
			path = path,
			range = { 0, 0, util.get_file_lines(path), 0 },
		},
	}
    local parser = position_parser.new()
    vim.tbl_extend("force", tests, xml.parse_xml(xml_file, parser))
    util.dump("pos.log", tests)
	local tree = positions.parse_tree(tests, {
		nested_tests = true,
		require_namespaces = false,
	})
	return tree
end

function M.discover_positions_v2(config, path)
	local parse_state = {
		header = 0,
		test_name = 1,
		test_file = 2,
		tag = 3,
		stop = 4,
	}

	local sources = cmake.get_executable_sources()
	if sources == nil then
		return {}
	end
	local executable = sources[path]
	if executable == nil then
		return {}
	end
	local filename = util.get_file_name(path)
	local ret = vim.fn.systemlist(executable .. ' -l -v high -# "[#' .. filename .. ']"')
	local state = parse_state.header
	local test_name
	local tests = {
		{
			name = util.get_file_name_ext(path),
			type = "file",
			id = path,
			path = path,
			range = { 0, 0, util.get_file_lines(path), 0 },
		},
	}
	local file_lines
	for _, line in ipairs(ret) do
		if state == parse_state.header and line == "Matching test cases:" then
			state = parse_state.test_name
		elseif state == parse_state.test_name then
			file_lines = {}
			if line:match("^  ") then
				test_name = '"' .. util.trim(line) .. '"'
				state = parse_state.test_file
			else
				state = parse_state.stop
			end
		elseif state == parse_state.test_file then
			line = util.trim(line)
			if line == "(NO DESCRIPTION)" then
				local file = table.concat(file_lines)
				local test_file, lineno = file:match("^([^:]+):(%d+)")
				lineno = tonumber(lineno) - 1
				table.insert(tests, {
					name = test_name,
					type = "test",
					id = test_file .. "::" .. test_name,
					path = test_file,
					range = { lineno, 0, lineno, 0 },
				})
				state = parse_state.tag
			else
				table.insert(file_lines, line)
			end
		elseif state == parse_state.tag then
			state = parse_state.test_name
		end
	end
	local tree = positions.parse_tree(tests, {
		nested_tests = true,
		require_namespaces = false,
	})
	return tree
end

return M
