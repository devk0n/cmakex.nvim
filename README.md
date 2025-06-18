# cmakex.nvim

🛠️ A fast, zero-config CMake + Ninja runner for Neovim.

`cmakex.nvim` provides a simple set of commands to generate, build, run, and clean your C++ projects using CMake and Ninja — directly from Neovim.

---

## ✨ Features

- `:Generate [Debug|Release]` — Configure your project with CMake
- `:Build [Debug|Release]` — Compile your project using Ninja
- `:Run` — Run the built executable in a terminal split
- `:Clean` — Remove the build directory

No setup or config files required — works out of the box for most CMake projects.

---

## 🚀 Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "devk0n/cmakex.nvim",
  cmd = { "Generate", "Build", "Run", "Clean" },
  config = function()
    require("cmakex").setup()
  end,
}
```

## 📂 Requirements
- CMake
- Ninja
- A `CMakeLists.txt` file with `project(...)` and `add_executable(...)`

## 📦 Commands

| Command     | Description                              |
|-------------|------------------------------------------|
| `:Generate` | Configure the project (default: Debug)   |
| `:Build`    | Build the project with Ninja             |
| `:Run`      | Run the generated executable             |
| `:Clean`    | Remove the `build/` directory            |

---

## 🧠 Example `CMakeLists.txt`

```cmake
cmake_minimum_required(VERSION 3.15)
project(MyApp)

add_executable(MyApp main.cpp)
```
