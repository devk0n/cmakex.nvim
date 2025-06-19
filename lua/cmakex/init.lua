-- lua/cmake_runner/init.lua
local M = {}

local term_bufnr = nil
local term_winid = nil

local function get_project_dir()
  return vim.fn.getcwd()
end

local function get_build_dir()
  return get_project_dir() .. "/build"
end

local function get_executable_name()
  local cmake_file = get_project_dir() .. "/CMakeLists.txt"
  local project_name = nil
  local exe_name = nil

  for line in io.lines(cmake_file) do
    if not project_name then
      project_name = line:match("project%(([%w_%-]+)")
    end
    if not exe_name then
      exe_name = line:match("add_executable%(([%w_%-]+)")
    end
  end

  if exe_name == "${PROJECT_NAME}" or exe_name == nil then
    return project_name or "a.out"
  end

  return exe_name
end

local function open_or_reuse_terminal()
  -- If terminal buffer exists and is valid, reuse it
  if term_bufnr and vim.api.nvim_buf_is_valid(term_bufnr) then
    local wins = vim.fn.win_findbuf(term_bufnr)
    if #wins == 0 then
      vim.cmd("botright split | resize 15")
      term_winid = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(term_winid, term_bufnr)
    else
      term_winid = wins[1]
    end
  else
    -- Create a new terminal buffer
    vim.cmd("botright split | resize 15")
    term_winid = vim.api.nvim_get_current_win()
    vim.cmd("term")
    term_bufnr = vim.api.nvim_get_current_buf()
  end
end

local function run_in_split(cmd)
  open_or_reuse_terminal()
  if vim.b.terminal_job_id then
    vim.fn.chansend(vim.b.terminal_job_id, cmd .. "\n")

    -- Scroll to the bottom
    vim.defer_fn(function()
      if term_winid and vim.api.nvim_win_is_valid(term_winid) then
        vim.api.nvim_win_call(term_winid, function()
          vim.cmd("normal! G")
        end)
      end
    end, 30) -- small delay to allow output to flush
  else
    vim.notify("Failed to send command to terminal", vim.log.levels.ERROR)
  end
end


function M.generate(build_type)
  build_type = build_type or "Debug"
  local cmd = string.format(
    'cmake -G Ninja -DCMAKE_BUILD_TYPE=%s -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -B "%s" -S "%s"',
    build_type,
    get_build_dir(),
    get_project_dir()
  )
  vim.fn.mkdir(get_build_dir(), "p")
  run_in_split(cmd)
end

function M.build(build_type)
  build_type = build_type or "Debug"
  if vim.fn.filereadable(get_build_dir() .. "/build.ninja") == 0 then
    M.generate(build_type)
  end
  run_in_split("ninja -C " .. get_build_dir())
end

function M.run()
  local exe = get_build_dir() .. "/" .. get_executable_name()
  if vim.fn.filereadable(exe) == 1 then
    run_in_split(exe)
  else
    vim.notify("Executable not found: " .. exe, vim.log.levels.ERROR)
  end
end

function M.clean()
  run_in_split("rm -rf " .. get_build_dir())
end

function M.setup()
  vim.api.nvim_create_user_command("Generate", function(opts)
    M.generate(opts.args)
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("Build", function(opts)
    M.build(opts.args)
  end, { nargs = "?" })

  vim.api.nvim_create_user_command("Run", function()
    M.run()
  end, {})

  vim.api.nvim_create_user_command("Clean", function()
    M.clean()
  end, {})
end

return M

