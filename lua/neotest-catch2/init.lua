local lib = require("neotest.lib")
local async = require("neotest.async")
local Path = require("plenary.path")
local nio = require("nio")
local xml = require("neotest.lib.xml")
local context_manager = require("plenary.context_manager")
local with = context_manager.with
local open = context_manager.open
local cmake = require("neotest-catch2.cmake")

local adapter = { name = "neotest-catch2" }

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

function adapter.filter_dir(name)
	return name ~= "build"
end

function adapter.discover_positions(path)
	local query = [[
        ((call_expression
            function: (identifier) @func_name (#eq? @func_name "TEST_CASE")
            arguments: (argument_list (_) @test.name)
        )) @test.definition 
    ]]

	local tree = lib.treesitter.parse_positions(path, query, {
		nested_tests = true,
		require_namespaces = false,
	})
	return tree
end

local function get_file_spec(sources, position, build_dir)
	if sources[position.path] == nil then
		return {}
	end
	local command = { sources[position.path], "-r", "xml", "-#" }
	local fname = position.path:match(".+/([^/]+)%.%w+$")
	local spec = "[#" .. fname .. "]"
	if position.type == "file" then
	elseif position.type == "test" then
		spec = spec .. position.name
	end
	table.insert(command, spec)
	return {
		command = command,
		cwd = build_dir,
	}
end

local function get_dap_strategy(spec, args)
	if args.strategy == "dap" then
		local program = table.remove(spec.command, 1)
        table.insert(spec.command, "-b")
		return {
			name = "Launch",
			type = "lldb",
			request = "launch",
			program = program,
			cwd = spec.cwd,
			stopOnEntry = false,
			args = spec.command,
		}
	end
	return {
		command = table.concat(spec.command, " "),
		cwd = spec.cwd,
	}
end

function adapter.build_spec(args)
	local sources = cmake.get_executable_sources()
	local build_dir = cmake.get_build_dir().filename
	if sources == nil then
		return {}
	end
	local position = args.tree:data()
	local specs = {}
	if position.type == "dir" then
		local files = {}
		for source, target in pairs(sources) do
			if adapter.is_test_file(source) then
				files[target] = 1
			end
		end
		for target, _ in pairs(files) do
			table.insert(specs, {
				command = { target, "-r", "xml" },
				cwd = build_dir,
			})
		end
    else
	    table.insert(specs, get_file_spec(sources, position, build_dir))
    end
    local specs1 = {}
    for _, s in ipairs(specs) do
        table.insert(specs1, {
            strategy = get_dap_strategy(s, args)
        })
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
	with(open(result.output, "r"), function(reader)
		data = reader:read("*a")
	end)

	local root = xml.parse(data)
	for _, testcase in xml_pairs(root.Catch.Group.TestCase) do
		local name = testcase._attr.filename .. '::"' .. testcase._attr.name .. '"'

		if testcase.OverallResult._attr.success == "true" then
			results[name] = {
				status = "passed",
			}
		else
			local message = "FAILED: "
				.. testcase.Expression.Original
				.. ", with expansion: "
				.. testcase.Expression.Expanded
			local errors = {}
			for _, error in xml_pairs(testcase.Expression) do
				if error._attr.filename == testcase._attr.filename then
					table.insert(errors, {
						message = message,
						line = tonumber(error._attr.line) - 1,
					})
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
