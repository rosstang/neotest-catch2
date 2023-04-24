# neotest-catch2
Neotest adapter for c++. Supports catch2 framework, and cmake needs to be used.

Requires nvim-treesitter and the parser for c++

require("neotest").setup({
  adapters = {
    require("neotest-catch2")(),
  }
})

You can optionally supply configuration settings:
...
