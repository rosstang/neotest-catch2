local async = require("neotest.async")
local lib = require("neotest.lib")
local Path = require("plenary.path")

---@type neotest.Adapter
local CatchNeotestAdapter = { name = "neotest-catch2" }

CatchNeotestAdapter.root = lib.files.match_root_pattern("CMakeLists.txt")

-- replace whitespace with underscores and remove surrounding quotes
function transform_test_name(name)
	return name:gsub("[%s]", "_"):gsub('^"(.*)"$', "%1")
end

function CatchNeotestAdapter.is_test_file(file_path)
	if not vim.endswith(file_path, ".cpp") then
		return false
	end
	local elems = vim.split(file_path, Path.path.sep)
	local file_name = elems[#elems]
	return vim.startswith(file_name, "test_") or vim.endswith(file_name, "_test.cpp")
end

function CatchNeotestAdapter.filter_dir(name)
	return name ~= "build"
end

---@async
---@return neotest.Tree
function CatchNeotestAdapter.discover_positions(path)
	local query = [[
        ((call_expression
            function: (identifier) @func_name
            arguments: (argument_list (_) @test.name)
        ) (#match? @func_name "^TEST_CASE$")) @test.definition
    ]]

	return lib.treesitter.parse_positions(path, query, {
		nested_tests = true,
		require_namespaces = false,
		-- position_id = "require('neotest-catch2')._generate_position_id",
	})
end

---@async
---@param args neotest.RunArgs
---@return neotest.RunSpec
function CatchNeotestAdapter.build_spec(args)
	---@type neotest.RunSpec
	return {}
end

---@async
---@param spec neotest.RunSpec
---@param result neotest.StrategyResult
---@return neotest.Result[]
function CatchNeotestAdapter.results(spec, result)
	return {}
end

setmetatable(CatchNeotestAdapter, {
	__call = function()
		print("catch2 testing called")
		return CatchNeotestAdapter
	end,
})

return CatchNeotestAdapter
