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
local catch2 = require("neotest-catch2.catch2_positions")
local func = require("plenary.functional")

local adapter = { name = "neotest-catch2" }

adapter.config = {
	extension = ".cpp",
	test_patterns = { "^test_", "_test.cpp$" },
	dir_blacklist_patterns = { "build", "cmake%-build.*", "external" },
    catch2_version = 3,
}

lib.positions.contains = function(parent, child)
	if parent.type == "dir" then
		return parent.path == child.path or vim.startswith(child.path, parent.path .. sep)
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
	if not vim.endswith(file_path, adapter.config.extension) then
		return false
	end
	local elems = vim.split(file_path, Path.path.sep)
	local file_name = elems[#elems]
	for _, p in ipairs(adapter.config.test_patterns) do
		if file_name:match(p) ~= nil then
			return true
		end
	end
	return false
end

local function filter_dir(path, root)
	root = root:gsub("(%W)", "%%%1")
    for _, p in ipairs(adapter.config.dir_blacklist_patterns) do
        if path:match(root .. sep .. p .. sep) ~= nil then
            return false
        end
    end
    return true
end

function adapter.filter_dir(_, rel_path, root)
	local t = filter_dir(root .. sep .. rel_path, root)
	return t
end

function adapter.discover_positions(path)
    if adapter.config.catch2_version == 3 then
        return catch2.discover_positions_v3(adapter.config, path)
    else
        return catch2.discover_positions_v2(adapter.config, path)
    end
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

local function get_dap_strategy(args, spec)
	if args.strategy ~= "dap" then
		spec.command = table.concat(spec.commands, " ")
		util.touch(spec.xml_file)
		local stream_events, stop_stream = stream_xml.stream_xml(spec.xml_file)
		spec.context = {
			stop_stream = stop_stream,
			results = {},
		}
		local parser = result_parser.new(true)
		spec.stream = function()
			nio.run(function()
				for event in stream_events do
					stream_xml.dispatch(event, parser)
					if parser.stop then
						stop_stream()
						return
					end
				end
			end, function(success, err)
				if not success then
					print("stream parsing xml failure: err = " .. err)
				end
			end)
			return function()
				local item = parser.results.get()
				local results = { [item.name] = item }
				spec.context.results[item.name] = item
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
	return spec
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
	return vim.tbl_map(func.partial(get_dap_strategy, args), specs)
end

function adapter.results(spec, _)
	if spec.context ~= nil and spec.context.results ~= nil then
		return spec.context.results
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
		return adapter
	end,
})

return adapter
