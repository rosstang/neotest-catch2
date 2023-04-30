local lib = require("neotest.lib")
local async = require("neotest.async")
local Path = require("plenary.path")
local nio = require("nio")
local xml = require("neotest.lib.xml")
local context_manager = require("plenary.context_manager")
local with = context_manager.with
local open = context_manager.open
local cmake = require("neotest-catch2.cmake")
local sep = lib.files.sep
local positions = require("neotest.lib.positions")

local adapter = { name = "neotest-catch2" }

local function get_file_name(path)
	return path:match(".+/([^/]+)%.%w+$")
end

function adapter.root(dir)
	local patterns = { "CMakeLists.txt" }
	local start_path = dir
	local start_parents = Path:new(start_path):parents()
	local home = os.getenv("HOME")
	local potential_roots = lib.files.is_dir(start_path) and vim.list_extend({ start_path }, start_parents)
		or start_parents

	for index = #potential_roots, 1, -1 do
		local path = potential_roots[index]
		if path ~= home then
			for _, pattern in ipairs(patterns) do
				for _, p in ipairs(nio.fn.glob(Path:new(path, pattern).filename, true, true)) do
					if lib.files.exists(p) then
						return path
					end
				end
			end
		end
	end
end

function adapter.is_test_file(file_path)
	if not vim.endswith(file_path, ".cpp") then
		return false
	end
	local elems = vim.split(file_path, Path.path.sep)
	local file_name = elems[#elems]
	return vim.startswith(file_name, "test_") or vim.endswith(file_name, "_test.cpp")
end

local function filter_dir(path, root)
	root = root:gsub("(%W)", "%%%1")
	local t = path:match(root .. sep .. "build" .. sep) == nil
		and path:match(root .. sep .. "cmake--build.*" .. sep) == nil
		and path:match(root .. sep .. "external" .. sep) == nil
	return t
end

function adapter.filter_dir(name, rel_path, root)
	local t = filter_dir(root .. sep .. rel_path, root)
	return t
end

local parse_state = {
	header = 0,
	test_name = 1,
	test_file = 2,
	description = 3,
	tag = 4,
	stop = 5,
}

local function trim(s)
	return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function get_file_lines(path)
	local count = 0
	for _ in io.lines(path) do
		count = count + 1
	end
	return count
end

local function treesitter_discover_positions(path)
	local query = [[
        ((call_expression
            function: (identifier) @func_name (#eq? @func_name "TEST_CASE")
            arguments: (argument_list (string_literal) @test.name)
        )) @test.definition 
    ]]
	local tree = lib.treesitter.parse_positions(path, query, {
		nested_tests = true,
		require_namespaces = false,
	})
	print("tree = ", vim.inspect(tree))
	return tree
end

function adapter.discover_positions(path)
	local sources = cmake.get_executable_sources()
	if sources == nil then
		return {}
	end
	local executable = sources[path]
	if executable == nil then
		return {}
	end
	local filename = get_file_name(path)
	local ret = vim.fn.systemlist(executable .. ' -l -v high -# "[#' .. filename .. ']"')
	-- print("position = ", vim.inspect(ret))
	local state = parse_state.header
	local test_name
	local tests = {
		{
			name = get_file_name(path),
			type = "file",
			id = path,
			path = path,
			range = { 0, 0, get_file_lines(path), 0 },
		},
	}

	for _, line in ipairs(ret) do
		if state == parse_state.header and line == "Matching test cases:" then
			state = parse_state.test_name
		elseif state == parse_state.test_name then
			if line:match("^  ") then
				test_name = '"' .. trim(line) .. '"'
				state = parse_state.test_file
			else
				state = parse_state.stop
			end
		elseif state == parse_state.test_file then
			line = trim(line)
			local test_file, lineno = line:match("^([^:]+):(%d+)")
			lineno = tonumber(lineno)
			state = parse_state.description
			table.insert(tests, {
				name = test_name,
				type = "test",
				id = test_file .. "::" .. test_name,
				path = test_file,
				range = { lineno, 0, lineno, 5 },
			})
		elseif state == parse_state.description then
			state = parse_state.tag
		elseif state == parse_state.tag then
			state = parse_state.test_name
		end
	end
	-- print("tests = ", vim.inspect(tests))
	local tree = positions.parse_tree(tests, {
		nested_tests = true,
		require_namespaces = false,
	})
	-- treesitter_discover_positions(path)
	-- print("tree = ", vim.inspect(tree))
	return tree
end

local function get_file_spec(sources, position, dir)
	if sources[position.path] == nil then
		return {}
	end
	local xml_file = async.fn.tempname() .. ".xml"
	local commands = { sources[position.path], "-r", "xml", "-#", "-o", xml_file }
	local fname = get_file_name(position.path)
	local spec = "[#" .. fname .. "]"
	if position.type == "test" then
		spec = spec .. position.name
	end
	table.insert(commands, spec)
	return {
		commands = commands,
		cwd = dir,
		xml_file = xml_file,
	}
end

local function get_dap_strategy(spec, args)
	if args.strategy ~= "dap" then
		spec.command = table.concat(spec.commands, " ")
		return spec
	end
	local program = table.remove(spec.commands, 1)
	table.insert(spec.commands, "-b")
	spec.strategy = {
		name = "Launch",
		type = "codelldb",
		request = "launch",
		program = program,
		cwd = spec.cwd,
		stopOnEntry = false,
		args = spec.commands,
	}
	spec.command = nil
	spec.cwd = nil
end

function adapter.build_spec(args)
	local sources = cmake.get_executable_sources()
	local dir = cmake.get_build_dir().filename
	local root = vim.loop.cwd()
	if sources == nil then
		return {}
	end
	local position = args.tree:data()
	local specs = {}
	if position.type == "dir" then
		local files = {}
		for source, target in pairs(sources) do
			if adapter.is_test_file(source) and filter_dir(source, root) then
				files[target] = 1
			end
		end
		for target, _ in pairs(files) do
			local xml_file = async.fn.tempname() .. ".xml"
			table.insert(specs, {
				commands = { target, "-r", "xml", "-o", xml_file },
				cwd = dir,
				xml_file = xml_file,
			})
		end
	else
		table.insert(specs, get_file_spec(sources, position, dir))
	end
	local specs1 = {}
	for _, s in ipairs(specs) do
		table.insert(specs1, get_dap_strategy(s, args))
	end
	print("specs = ", vim.inspect(specs1))
	return specs1
end

local function xml_pairs(xml_node)
	return pairs(#xml_node == 0 and { xml_node } or xml_node)
end

function adapter.results(spec, result)
	local results = {}
	local data

	if not lib.files.exists(spec.xml_file) then
		return results
	end

	with(open(spec.xml_file, "r"), function(reader)
		data = reader:read("*a")
	end)

	local root = xml.parse(data)
	if root.Catch.Group.TestCase == nil then
		return results
	end

	for _, testcase in xml_pairs(root.Catch.Group.TestCase) do
		local name = testcase._attr.filename .. '::"' .. testcase._attr.name .. '"'

		if testcase.OverallResult._attr.success == "true" then
			results[name] = {
				status = "passed",
			}
		else
			local message
			local errors = {}
			if testcase.Expression ~= nil then
				for _, error in xml_pairs(testcase.Expression) do
					message = "FAILED: " .. error.Original .. ", with expansion: " .. error.Expanded
					if error._attr.filename == testcase._attr.filename then
						table.insert(errors, {
							message = message,
							line = tonumber(error._attr.line) - 1,
						})
					end
				end
			elseif testcase.Exception ~= nil or testcase.FatalErrorCondition ~= nil then
				local error_node = testcase.Exception ~= nil and testcase.Exception or testcase.FatalErrorCondition
				local msg
				message = error_node[1]
				if testcase.FatalErrorCondition ~= nil then
					msg = "Fatal error ["
						.. message
						.. "] for test case file="
						.. error_node._attr.filename
						.. ", line="
						.. error_node._attr.filename
					vim.notify(msg, vim.log.levels.ERROR)
				end

				for _, error in xml_pairs(error_node) do
					if error.attr_ ~= nil then
						if error._attr.filename == testcase._attr.filename then
							table.insert(errors, {
								message = message,
								line = tonumber(error._attr.line) - 1,
							})
						end
					end
				end
			end

			results[name] = {
				status = "failed",
				short = message,
				errors = errors,
			}
		end

		local output_file = async.fn.tempname() .. ".out"
		results[name]["output"] = output_file
		with(open(output_file, "a"), function(writer)
			for _, out in pairs({
				{ "STDOUT", testcase.OverallResult.StdOut },
				{ "STDERR", testcase.OverallResult.StdErr },
			}) do
				writer:write(out[1] .. "\n")
				writer:write((out[2] == nil and "" or out[2]) .. "\n")
			end
		end)
	end

	print("results = ", vim.inspect(results))
	return results
end

setmetatable(adapter, {
	__call = function()
		print("catch2 testing called")
		return adapter
	end,
})

return adapter
