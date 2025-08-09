-- lua/cmakex.lua
local M = {}

-- -------- Config --------
local config = {
  build_dir = "build",
  generator = "Ninja",
  preset = nil,              -- e.g. "dev-debug" to use CMakePresets.json
  build_type = "Debug",
  executable = nil,          -- override executable target name (no path), e.g. "DynamicsLab"
  cmake_args = {},           -- extra -D flags (table of strings)
  run_cwd = nil,             -- working dir for running exe; defaults to project root
}

function M.setup(user)
  config = vim.tbl_deep_extend("force", config, user or {})
  -- Commands
  vim.api.nvim_create_user_command("Generate", function(opts) M.generate(opts.args ~= "" and opts.args or nil) end, { nargs = "?" })
  vim.api.nvim_create_user_command("Build",    function(opts) M.build(opts.args ~= "" and opts.args or nil) end,    { nargs = "?" })
  vim.api.nvim_create_user_command("Rebuild",  function(opts) M.rebuild(opts.args ~= "" and opts.args or nil) end,  { nargs = "?" })
  vim.api.nvim_create_user_command("Run",      function() M.run() end, {})
  vim.api.nvim_create_user_command("RunArgs",  function(opts) M.run(opts.args) end, { nargs = "*" })
  vim.api.nvim_create_user_command("Clean",    function() M.clean() end, {})
end

-- -------- Terminal mgmt --------
local term_bufnr, term_winid, term_job_id

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
      on_exit = function() term_job_id = nil end,
      cwd = vim.loop.cwd(),
    })
    vim.api.nvim_buf_set_name(term_bufnr, "DedicatedBuildTerminal")
  end
end

local function run_in_split(cmd, cwd)
  open_or_create_dedicated_terminal()
  if term_job_id and vim.fn.jobwait({ term_job_id }, 0)[1] == -1 then
    if cwd and cwd ~= "" then
      vim.fn.chansend(term_job_id, "cd " .. cwd .. "\n")
    end
    vim.fn.chansend(term_job_id, cmd .. "\n")
    vim.defer_fn(function()
      if term_winid and vim.api.nvim_win_is_valid(term_winid) then
        vim.api.nvim_win_call(term_winid, function() vim.cmd("normal! G") end)
      end
    end, 30)
  else
    vim.notify("Dedicated terminal is not running", vim.log.levels.ERROR)
  end
end

-- -------- Paths & discovery --------
local function get_project_dir()
  local git_root = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })[1]
  if git_root and git_root ~= "" and vim.v.shell_error == 0 then
    return git_root
  end
  return vim.fn.getcwd()
end

local function get_build_dir()
  return get_project_dir() .. "/" .. config.build_dir
end

local function path_join(a, b) return (a:gsub("/+$", "")) .. "/" .. (b:gsub("^/+", "")) end

local function file_exists(p) return vim.fn.filereadable(p) == 1 end
local function is_exec(p)
  if vim.fn.has("unix") == 1 then return vim.fn.executable(p) == 1 end
  return file_exists(p)
end

-- Find all CMakeLists.txt under project
local function all_cmake_lists()
  local root = get_project_dir()
  local out = {}
  -- Use ripgrep if present (fast), else fallback to vim.fn.glob
  if vim.fn.executable("rg") == 1 then
    local lines = vim.fn.systemlist({ "rg", "--no-messages", "-g", "!build", "-g", "!*build*/**", "-n", "--files", "CMakeLists.txt", root })
    for _, p in ipairs(lines) do
      if p ~= "" then table.insert(out, p) end
    end
  else
    local gl = vim.fn.globpath(root, "**/CMakeLists.txt", true, true)
    for _, p in ipairs(gl) do table.insert(out, p) end
  end
  return out
end

-- Parse add_executable() target names from a single CMakeLists
local function parse_execs_from_file(p)
  local names = {}
  local f = io.open(p, "r")
  if not f then return names end
  for line in f:lines() do
    -- capture add_executable(TargetName ...), allow spaces and quotes
    local name = line:match("%f[%w_]add_executable%s*%(%s*([%w_%-%.]+)")
    if name and name ~= "" then table.insert(names, name) end
  end
  f:close()
  return names
end

local function discover_executables()
  local result = {}
  for _, p in ipairs(all_cmake_lists()) do
    local names = parse_execs_from_file(p)
    for _, n in ipairs(names) do
      table.insert(result, { name = n, cmake = p })
    end
  end
  -- Prefer ones under apps/
  table.sort(result, function(a, b)
    local aa = a.cmake:find("/apps/") and 0 or 1
    local bb = b.cmake:find("/apps/") and 0 or 1
    if aa ~= bb then return aa < bb end
    return a.name < b.name
  end)
  return result
end

local function newest_exe_in_bin()
  local bin = path_join(get_build_dir(), "bin")
  if vim.fn.isdirectory(bin) == 0 then return nil end
  local newest, newest_mtime = nil, -1
  for name in vim.fn.readdir(bin) do
    local full = path_join(bin, name)
    local stat = vim.loop.fs_stat(full)
    if stat and stat.type == "file" and stat.mtime.sec > newest_mtime then
      newest, newest_mtime = full, stat.mtime.sec
    end
  end
  return newest
end

local function resolve_executable_path()
  local bin = path_join(get_build_dir(), "bin")
  -- 1) explicit override
  if config.executable then
    local candidate = path_join(bin, config.executable)
    if is_exec(candidate) then return candidate end
  end
  -- 2) discover via CMakeLists (prefer apps/)
  local execs = discover_executables()
  for _, e in ipairs(execs) do
    local candidate = path_join(bin, e.name)
    if is_exec(candidate) then return candidate end
  end
  -- 3) fallback to newest file in bin/
  local newest = newest_exe_in_bin()
  if newest and is_exec(newest) then return newest end
  -- 4) last resort: project name
  local top = path_join(get_project_dir(), "CMakeLists.txt")
  local proj = nil
  for line in io.lines(top) do
    proj = proj or line:match("project%(([%w_%-%.]+)")
    if proj then break end
  end
  if proj then
    local candidate = path_join(bin, proj)
    if is_exec(candidate) then return candidate end
  end
  return nil
end

-- -------- Actions --------
local function cmake_cmd_generate(build_type)
  if config.preset then
    return string.format('cmake --preset "%s"', config.preset), get_project_dir()
  end
  local args = ""
  if config.cmake_args and #config.cmake_args > 0 then
    args = " " .. table.concat(config.cmake_args, " ")
  end
  return string.format(
    'cmake -G %s -DCMAKE_BUILD_TYPE=%s -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -B "%s" -S "%s"%s',
    config.generator,
    build_type or config.build_type,
    get_build_dir(),
    get_project_dir(),
    args
  ), nil
end

function M.generate(build_type)
  if build_type then config.build_type = build_type end
  vim.fn.mkdir(get_build_dir(), "p")
  local cmd, cwd = cmake_cmd_generate(build_type)
  run_in_split(cmd, cwd)
end

function M.build(build_type)
  if build_type then config.build_type = build_type end
  if config.preset then
    run_in_split(string.format('cmake --build --preset "%s"', config.preset), get_project_dir())
    return
  end
  if vim.fn.filereadable(get_build_dir() .. "/build.ninja") == 0 then
    M.generate(build_type)
  end
  run_in_split("cmake --build " .. get_build_dir(), nil)
end

function M.rebuild(build_type)
  if build_type then config.build_type = build_type end
  M.clean()
  vim.defer_fn(function()
    M.generate(build_type)
    vim.defer_fn(function() M.build(build_type) end, 200)
  end, 100)
end

function M.run(args)
  local exe = resolve_executable_path()
  if not exe then
    vim.notify("Executable not found in build/bin. Set `executable` in setup() or build first.", vim.log.levels.ERROR)
    return
  end
  local run_dir = config.run_cwd or get_project_dir()
  local cmd = exe
  if args and args ~= "" then
    cmd = cmd .. " " .. args
  end
  run_in_split(cmd, run_dir)
end

function M.clean()
  run_in_split("rm -rf " .. get_build_dir(), nil)
end

return M

