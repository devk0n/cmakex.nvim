# cmakex.nvim

A simple CMake + Ninja plugin for Neovim.

## Features

- `:Generate [Debug|Release]` — Run `cmake` with Ninja
- `:Build [Debug|Release]` — Compile using `ninja`
- `:Run` — Run the built executable
- `:Clean` — Delete the build directory

## Setup

```lua
{
  "devk0n/cmakex.nvim",
  config = function()
    require("cmakex").setup()
  end,
  cmd = { "Generate", "Build", "Run", "Clean" },
}

## Requirements
- Ninja
- CMake project with project(...) and add_executable(...)
