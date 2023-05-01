local xml = require("lua.neotest-catch2.results")

local parser = xml.new_parser()
local file = io.open("output.xml", "r")
print(vim.inspect(parser:parse(file:lines())))

