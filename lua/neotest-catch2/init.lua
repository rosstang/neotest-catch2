local lib = require("neotest.lib")
local async = require("neotest.async")
local Path = require("plenary.path")
local nio = require("nio")
local xml = require("neotest.lib.xml")
local context_manager = require("plenary.context_manager")
local with = context_manager.with
local open = context_manager.open

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
            function: (identifier) @func_name (#match? @func_name "^TEST_CASE$")
            arguments: (argument_list (_) @test.name)
        )) @test.definition 
    ]]

	local tree = lib.treesitter.parse_positions(path, query, {
		nested_tests = true,
		require_namespaces = false,
	})
	return tree
end

function adapter.build_spec(args)
	print("args = ", vim.inspect(args))
	local position = args.tree:data()
	local command = { "build/tests/bin/testing", "-r", "xml", "-#" }
	if position.type == "dir" then
    else
	    local fname = position.path:match(".+/([^/]+)%.%w+$")
	    local spec = "[#" .. fname .. "]"
        if position.type == "file" then
	    elseif position.type == "test" then
		    spec = spec .. position.name
        end
	    table.insert(command, spec)
	end

	return {
		command = table.concat(command, " "),
		cwd = adapter.root(position.path),
	}
end

function adapter.results(spec, result)
	local results = {}

	local data
	with(open(result.output, "r"), function(reader)
		data = reader:read("*a")
	end)

	local root = xml.parse(data)

	local tests
	if #root.Catch.Group.TestCase == 0 then
		tests = { root.Catch.Group.TestCase }
	else
		tests = root.Catch.Group.TestCase
	end
	print("spec = ", vim.inspect(spec))

	for _, testcase in pairs(tests) do
		print("testcase = ", vim.inspect(testcase))
		local name = testcase._attr.filename .. '::"' .. testcase._attr.name .. '"'

		if testcase.OverallResult._attr.success == "true" then
			results[name] = {
				status = "passed",
			}
		else
			results[name] = {
				status = "failed",
				short = "Expression: "
					.. testcase.Expression.Original
					.. ", expanded: "
					.. testcase.Expression.Expanded,
			}
		end

		local output_file = async.fn.tempname() .. ".stdout"
		results[name]["output"] = output_file
		with(open(output_file, "a"), function(writer)
			if testcase.OverallResult.StdOut ~= nil then
				writer:write(testcase.OverallResult.StdOut)
			else
				writer:write("")
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
