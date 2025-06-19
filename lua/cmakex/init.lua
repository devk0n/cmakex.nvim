local M = {}

local term_bufnr = nil
local term_winid = nil
local term_job_id = nil

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

  return exe_name or project_name or "a.out"
end

local function open_or_create_dedicated_terminal()
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
    vim.cmd("botright split | resize 15")
    term_winid = vim.api.nvim_get_current_win()

    term_bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(term_winid, term_bufnr)

    term_job_id = vim.fn.termopen(os.getenv("SHELL") or "bash", {
      on_exit = function()
        term_job_id = nil
      end,
    })

    vim.api.nvim_buf_set_name(term_bufnr, "DedicatedBuildTerminal")
  end
end

local function run_in_split(cmd)
  open_or_create_dedicated_terminal()
  if term_job_id and vim.fn.jobwait({ term_job_id }, 0)[1] == -1 then
    vim.fn.chansend(term_job_id, cmd .. "\n")
    vim.defer_fn(function()
      if term_winid and vim.api.nvim_win_is_valid(term_winid) then
        vim.api.nvim_win_call(term_winid, function()
          vim.cmd("normal! G")
        end)
      end
    end, 30)
  else
    vim.notify("Dedicated terminal is not running", vim.log.levels.ERROR)
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

function M.rebuild(build_type)
  build_type = build_type or "Debug"
  M.clean()
  vim.defer_fn(function()
    M.generate(build_type)
    vim.defer_fn(function()
      M.build(build_type)
    end, 100)
  end, 100)
end

function M.run()
  local exe = get_build_dir() .. "/bin/" .. get_executable_name()
  if vim.fn.executable(exe) == 1 then
    run_in_split(exe)
  else
    vim.notify("Executable not found or not executable: " .. exe, vim.log.levels.ERROR)
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

  vim.api.nvim_create_user_command("Rebuild", function(opts)
    M.rebuild(opts.args)
  end, { nargs = "?" })
end

return M
