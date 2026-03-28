-- win-ime-anchor/init.lua
local M = {}

local function is_windows()
	return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

-- WinAPI constants
local WM_IME_CONTROL = 0x0283
local IMC_GETOPENSTATUS = 0x0005
local IMC_SETOPENSTATUS = 0x0006

local ffi, user32, imm32
local ok_ffi = false

local function ensure_ffi()
	if ok_ffi then
		return true
	end
	if not is_windows() then
		return false
	end

	local ok
	ok, ffi = pcall(require, "ffi")
	if not ok then
		return false
	end

	ffi.cdef([[
    typedef void* HWND;
    typedef unsigned long long WPARAM;
    typedef long long LPARAM;
    typedef long long LRESULT;

    HWND GetForegroundWindow(void);
    LRESULT SendMessageW(HWND hWnd, unsigned int Msg, WPARAM wParam, LPARAM lParam);

    HWND ImmGetDefaultIMEWnd(HWND hWnd);
  ]])

	user32 = ffi.load("user32")
	imm32 = ffi.load("imm32")
	ok_ffi = true
	return true
end

---@return ffi.cdata*|nil
local function get_ime_hwnd()
	if not ensure_ffi() then
		return nil
	end
	local fg = user32.GetForegroundWindow()
	if fg == nil then
		return nil
	end
	local ime_hwnd = imm32.ImmGetDefaultIMEWnd(fg)
	return ime_hwnd
end

---@return boolean|nil
local function ime_get_open()
	local h = get_ime_hwnd()
	if not h then
		return nil
	end
	local ret = user32.SendMessageW(h, WM_IME_CONTROL, IMC_GETOPENSTATUS, 0)
	return ret ~= 0
end

---@param on boolean
local function ime_set_open(on)
	local h = get_ime_hwnd()
	if not h then
		return
	end
	user32.SendMessageW(h, WM_IME_CONTROL, IMC_SETOPENSTATUS, on and 1 or 0)
end

---@param mode string|nil
local function might_ime_on(mode)
	if mode == nil then
		return false
	end
	-- insert-like modes: i (insert), R (replace), c (command-line), t (terminal)
	return mode:match("^[iRct]") ~= nil
end

------------------------------------------------------------
-- plugun body
------------------------------------------------------------

---@class WinImeAnchorConfig
---@field enable_polling boolean|nil         -- enable polling for IME status (default: false)
---@field polling_interval integer|nil       -- polling interval in milliseconds (default: 200)

---@type boolean
local did_setup = false

---@type boolean
local has_focus = true -- Assume nvim has focus at start up

---@type table<string, boolean|nil>
local saved_ime_state = {
	-- for insert-like modes, replace mode
	-- nil = unknown state, true = IME active, false = IME inactive
	---@type boolean|nil
	insert = nil,

	-- for command-line mode
	---@type boolean|nil
	command = nil,

	-- for terminal mode
	---@type boolean|nil
	terminal = nil,
}

---@type uv.uv_timer_t|nil
local poll_timer = nil

----@param prev_mode string
local function anchor_ime_off(prev_mode)
	local current_ime_state = ime_get_open()
	if current_ime_state ~= nil then
		-- save_ime_state(current_ime_state, prev_mode)
		if prev_mode:match("^i") then
			saved_ime_state.insert = current_ime_state
		elseif prev_mode:match("^R") then
			saved_ime_state.insert = current_ime_state
		elseif prev_mode:match("^c") then
			saved_ime_state.insert = current_ime_state
		elseif prev_mode:match("^t") then
			saved_ime_state.insert = current_ime_state
		end
	end
	if current_ime_state then
		ime_set_open(false)
	end
end

---@param mode string|nil
local function restore_anchored_ime(mode)
	if not mode then
		return
	end
	local s = nil
	if mode:match("^i") then
		s = saved_ime_state.insert
	elseif mode:match("^R") then
		s = saved_ime_state.insert
	elseif mode:match("^c") then
		s = saved_ime_state.command
	elseif mode:match("^t") then
		s = saved_ime_state.terminal
	end

	if s == nil then
		-- DO nothing if no stored status
		return
	elseif ime_get_open() == s then
		-- Do nothing if the status is already the same
		return
	else
		-- Restore the IME status when entering insert mode
		ime_set_open(s)
	end
end

local function poll_ime_state()
	if has_focus == false then
		return
	end

	local mode = vim.api.nvim_get_mode().mode

	if might_ime_on(mode) then
		-- Do nothing.
		-- User might changed IME state intentionally.
	else
		-- non-insert-like modes must keep IME off
		local current_ime_state = ime_get_open()
		if current_ime_state == true then
			ime_set_open(false)
		end
	end
end

---@param opts WinImeAnchorConfig|nil
function M.setup(opts)
	if did_setup then
		return
	end
	did_setup = true

	-- Do nothing if not windows or ffi is not available
	if not is_windows() or not ensure_ffi() then
		return
	end

	opts = opts or {}

	local group = vim.api.nvim_create_augroup("WinImeAnchor", { clear = true })
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = group,
		callback = function(ev)
			-- split `match` into old_mode and new_mode
			local old_mode, new_mode = ev.match:match("([^:]+):([^:]+)")
			if might_ime_on(new_mode) then
				restore_anchored_ime(new_mode)
			else
				anchor_ime_off(old_mode)
			end
		end,
	})
	vim.api.nvim_create_autocmd("FocusGained", {
		group = group,
		callback = function()
			has_focus = true
		end,
	})

	vim.api.nvim_create_autocmd("FocusLost", {
		group = group,
		callback = function()
			has_focus = false
		end,
	})
	if opts.enable_polling then
		-- Start polling timer to check IME status every `polling_interval` milliseconds
		local interval = opts.polling_interval or 200

		poll_timer = vim.loop.new_timer()
		if poll_timer ~= nil then
			poll_timer:start(interval, interval, vim.schedule_wrap(poll_ime_state))

			-- Stop the timer when exiting Neovim
			vim.api.nvim_create_autocmd("VimLeavePre", {
				group = group,
				callback = function()
					if poll_timer then
						poll_timer:stop()
						poll_timer:close()
						poll_timer = nil
					end
				end,
			})
		end
	end
end

return M
