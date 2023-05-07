local Path = require("plenary.path")
local utils = require("tasks.utils")
local scandir = require("plenary.scandir")
local ProjectConfig = require("tasks.project_config")
local os = require("ffi").os:lower()

-- Mainly a copy and modify from https://github.com/Shatur/neovim-tasks/blob/master/lua/tasks/module/cmake.lua
M = {}

--- Parses build dir expression.
---@param dir string: Path with expressions to replace.
---@param build_type string
---@return table
local function parse_dir(dir, build_type)
	local parsed_dir = dir:gsub("{cwd}", vim.loop.cwd())
	parsed_dir = parsed_dir:gsub("{os}", os)
	parsed_dir = parsed_dir:gsub("{build_type}", build_type:lower())
	return Path:new(parsed_dir)
end

--- Returns reply directory that contains targets information.
---@param build_dir table
---@return unknown
local function get_reply_dir(build_dir)
	return build_dir / ".cmake" / "api" / "v1" / "reply"
end

--- Reads information about target.
---@param codemodel_target table
---@param reply_dir table
---@return table
local function get_target_info(codemodel_target, reply_dir)
	return vim.json.decode((reply_dir / codemodel_target["jsonFile"]):read())
end

--- Creates query files that to acess information about targets after CMake configuration.
---@param build_dir table
---@return boolean: Returns `true` on success.
local function make_query_files(build_dir)
	local query_dir = build_dir / ".cmake" / "api" / "v1" / "query"
	if not query_dir:mkdir({ parents = true }) then
		utils.notify(string.format('Unable to create "%s"', query_dir.filename), vim.log.levels.ERROR)
		return false
	end

	local codemodel_file = query_dir / "codemodel-v2"
	if not codemodel_file:is_file() then
		if not codemodel_file:touch() then
			utils.notify(string.format('Unable to create "%s"', codemodel_file.filename), vim.log.levels.ERROR)
			return false
		end
	end
	return true
end

--- Reads targets information.
---@param reply_dir table
---@return table?
local function get_codemodel_targets(reply_dir)
	local found_files = scandir.scan_dir(reply_dir.filename, { search_pattern = "codemodel*" })
	if #found_files == 0 then
		utils.notify("Unable to find codemodel file", vim.log.levels.ERROR)
		return nil
	end
	local codemodel = Path:new(found_files[1])
	local codemodel_json = vim.json.decode(codemodel:read())
	return codemodel_json["configurations"][1]["targets"]
end

function M.get_build_dir()
	local project_config = ProjectConfig.new()
	return parse_dir(project_config.cmake.build_dir, project_config.cmake.build_type)
end

function M.get_executable_sources()
	local build_dir = M.get_build_dir()
	local source_dir = Path:new(vim.loop.cwd())
	if not build_dir:is_dir() then
		utils.notify(
			string.format('Build directory "%s" does not exist, you need to run "configure" task first', build_dir),
			vim.log.levels.ERROR
		)
		return nil
	end

	local reply_dir = get_reply_dir(build_dir)
	local codemodel_targets = get_codemodel_targets(reply_dir)
	if not codemodel_targets then
		return nil
	end

	local targets = {}
	for _, target in ipairs(codemodel_targets) do
		local target_info = get_target_info(target, reply_dir)
		local target_name = target_info["name"]
		if target_name:find("_autogen") == nil and target_info["type"] == "EXECUTABLE" then
			local target_path = Path:new(target_info["artifacts"][1]["path"])
			if not target_path:is_absolute() then
				target_path = build_dir / target_path
			end
			for _, source in ipairs(target_info["sources"]) do
				local source_path = Path:new(source["path"])
				if not source_path:is_absolute() then
					source_path = source_dir / source_path
				end
				targets[source_path.filename] = target_path.filename
			end
		end
	end
	return targets
end

return M
