local lib = require("neotest.lib")
local async = require("neotest.async")
local Path = require("plenary.path")
local nio = require("nio")
local cmake = require("neotest-catch2.cmake")
local util = require("neotest-catch2.util")
local sep = lib.files.sep
local positions = require("neotest.lib.positions")
local result_parser = require("neotest-catch2.result_parser")
local stream_xml = require("neotest-catch2.stream_xml")

local adapter = { name = "neotest-catch2" }

lib.positions.contains = function(parent, child)
	if parent.type == "dir" then
		return parent.path == child.path or vim.startswith(child.path, parent.path .. require("neotest.lib.file").sep)
	end
	if child.type == "dir" then
		return false
	end
	if parent.type == "file" then
		return parent.path == child.path
	end
	if child.type == "file" then
		return false
	end

	return (parent.range[1] <= child.range[1] and parent.range[3] > child.range[3])
		or (parent.range[1] < child.range[1] and parent.range[3] >= child.range[3])
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

local function get_file_lines(path)
	local count = 0
	for _ in io.lines(path) do
		count = count + 1
	end
	return count
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
	local filename = util.get_file_name(path)
	local ret = vim.fn.systemlist(executable .. ' -l -v high -# "[#' .. filename .. ']"')
	-- print("position = ", vim.inspect(ret))
	local state = parse_state.header
	local test_name
	local tests = {
		{
			name = util.get_file_name_ext(path),
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
				test_name = '"' .. util.trim(line) .. '"'
				state = parse_state.test_file
			else
				state = parse_state.stop
			end
		elseif state == parse_state.test_file then
			line = util.trim(line)
			local test_file, lineno = line:match("^([^:]+):(%d+)")
			lineno = tonumber(lineno) - 1
			state = parse_state.description
			table.insert(tests, {
				name = test_name,
				type = "test",
				id = test_file .. "::" .. test_name,
				path = test_file,
				range = { lineno, 0, lineno, 0 },
			})
		elseif state == parse_state.description then
			state = parse_state.tag
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

local function get_file_spec(sources, position, dir)
	if sources[position.path] == nil then
		return {}
	end
	local xml_file = async.fn.tempname() .. ".xml"
	local commands = { sources[position.path], "-r", "xml", "-#", "-o", xml_file }
	local fname = util.get_file_name(position.path)
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
		util.touch(spec.xml_file)
		local stream_events, stop_stream = stream_xml.stream_xml(spec.xml_file)
		spec.stop_stream = stop_stream
		spec.stream = function()
			local parser = result_parser.new(true)
			nio.run(function()
				for event in stream_events do
					stream_xml.dispatch(event, parser)
				end
			end, function(success, err)
				if not success then
					print("stream parsing xml failure: err = " .. err)
				end
			end)

			return function()
				local results = {}
                while parser.results.size() > 0 do
                    local item = parser.results.get_nowait()
                    results[item.name] = item
                end

                if #results == 0 then
                    local item = parser.results.get()
                    results[item.name] = item
                end
				return results
			end
		end
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
	return specs1
end

function adapter.results(spec, result)
	if spec.stop_stream ~= nil then
		spec.stop_stream()
	end

	local results = {}
	if not lib.files.exists(spec.xml_file) then
		return results
	end

	local parser = result_parser.new(false)
	results = stream_xml.parse_xml(spec.xml_file, parser)
	return results
end

setmetatable(adapter, {
	__call = function()
		print("catch2 testing called")
		return adapter
	end,
})

return adapter
