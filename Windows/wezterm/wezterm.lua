local wezterm = require 'wezterm'
local act = wezterm.action
local config = wezterm.config_builder()

config.default_prog = { 'D:\\ProgramData\\Scoop\\shims\\nu.exe' }
config.launch_menu = {
  {
    label = 'CMD',
    args = { 'C:\\Windows\\System32\\cmd.exe' },
  },
  {
    label = 'PWSH',
    args = { 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe', '-NoLogo' },
  },
  {
    label = 'PWSH7 (CORE)',
    args = { 'D:\\Program Files\\PowerShell\\7\\pwsh.exe', '-NoLogo' },
  },
  {
    label = 'Nushell',
    args = { 'D:\\ProgramData\\Scoop\\shims\\nu.exe' },
  },
  {
    label = 'Git Bash',
    args = { 'D:\\ProgramData\\Scoop\\apps\\git\\current\\bin\\bash.exe', '--login', '-i' },
  },
}
config.wsl_domains = {}
config.set_environment_variables = {
  EDITOR = 'nvim',
  VISUAL = 'nvim',
}

config.front_end = 'OpenGL'
config.max_fps = 60
config.animation_fps = 1
config.check_for_updates = false
config.scrollback_lines = 100000
config.enable_kitty_keyboard = true

config.font = wezterm.font_with_fallback {
  'Cascadia Mono',
  'Symbols Nerd Font Mono',
}
config.font_size = 12
config.line_height = 1.1
config.harfbuzz_features = { 'calt=0', 'clig=0', 'liga=0' }

config.default_cursor_style = 'SteadyBar'
config.cursor_blink_rate = 0
config.audible_bell = 'Disabled'

config.colors = {
  foreground = '#ebfafa',
  background = '#171928',
  cursor_bg = '#37f499',
  cursor_fg = '#f8f8f2',
  cursor_border = '#37f499',
  selection_bg = '#bf4f8e',
  selection_fg = '#ebfafa',
  ansi = {
    '#21222c',
    '#f9515d',
    '#37f499',
    '#e9f941',
    '#9071f4',
    '#f265b5',
    '#04d1f9',
    '#ebfafa',
  },
  brights = {
    '#7081d0',
    '#f16c75',
    '#69f8b3',
    '#f1fc79',
    '#a48cf2',
    '#fd92ce',
    '#66e4fd',
    '#ffffff',
  },
  tab_bar = {
    background = '#0f111d',
    active_tab = {
      bg_color = '#171928',
      fg_color = '#37f499',
      intensity = 'Bold',
    },
    inactive_tab = {
      bg_color = '#0f111d',
      fg_color = '#7081d0',
    },
    inactive_tab_hover = {
      bg_color = '#21222c',
      fg_color = '#ebfafa',
    },
    new_tab = {
      bg_color = '#0f111d',
      fg_color = '#7081d0',
    },
    new_tab_hover = {
      bg_color = '#21222c',
      fg_color = '#37f499',
    },
  },
}

config.window_padding = {
  left = 10,
  right = 10,
  top = 10,
  bottom = 10,
}
config.window_background_opacity = 0.985
config.window_decorations = 'TITLE|RESIZE'
config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = false
config.tab_max_width = 32
config.pane_focus_follows_mouse = true
config.adjust_window_size_when_changing_font_size = false
config.initial_cols = 120
config.initial_rows = 32

config.keys = {
  { key = 'phys:K', mods = 'CTRL|SHIFT', action = act.ScrollByPage(-1) },
  { key = 'phys:J', mods = 'CTRL|SHIFT', action = act.ScrollByPage(1) },
  { key = 'Enter', mods = 'CTRL|SHIFT', action = act.SpawnWindow },
  { key = 'F5', mods = 'NONE', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
  { key = 'F6', mods = 'NONE', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
  { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentTab { confirm = false } },
  { key = 'phys:Q', mods = 'CTRL|SHIFT', action = act.QuitApplication },
  { key = '}', mods = 'CTRL', action = act.ActivatePaneDirection 'Next' },
  { key = '{', mods = 'CTRL', action = act.ActivatePaneDirection 'Prev' },
  { key = 'phys:H', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Left' },
  { key = 'phys:L', mods = 'CTRL|SHIFT', action = act.ActivatePaneDirection 'Right' },
  { key = 'LeftArrow', mods = 'CTRL', action = act.AdjustPaneSize { 'Left', 10 } },
  { key = 'RightArrow', mods = 'CTRL', action = act.AdjustPaneSize { 'Right', 10 } },
  { key = 'UpArrow', mods = 'CTRL', action = act.AdjustPaneSize { 'Up', 10 } },
  { key = 'DownArrow', mods = 'CTRL', action = act.AdjustPaneSize { 'Down', 10 } },
  { key = 'phys:Z', mods = 'CTRL|SHIFT', action = act.TogglePaneZoomState },
  { key = 'phys:T', mods = 'CTRL|SHIFT', action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'RightArrow', mods = 'CTRL|SHIFT', action = act.ActivateTabRelative(1) },
  { key = 'LeftArrow', mods = 'CTRL|SHIFT', action = act.ActivateTabRelative(-1) },
}

wezterm.on('new-tab-button-click', function(window, pane, button)
  if button == 'Right' then
    window:perform_action(act.ShowLauncherArgs { flags = 'LAUNCH_MENU_ITEMS' }, pane)
    return false
  end
end)

return config
