# neotest-catch2
Neotest adapter for c++. Supports catch2 framework, and cmake needs to be used.

Requires nvim-treesitter and the parser for c++, and also Shatur/neovim-tasks for managing cmake project.
```
use {
  "nvim-neotest/neotest",
  requires = {
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "antoinemadec/FixCursorHold.nvim",
		"Shatur/neovim-tasks",
  	"rosstang/neotest-catch2",
  },
  config = function()
    require("neotest").setup({
      adapters = {
        require("neotest-catch2")(),
      }
  })
}
```

You can optionally supply configuration settings:
```
require("neotest-catch2")({
    configs...
})
```
