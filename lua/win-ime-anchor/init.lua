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

local function ime_get_open()
	local h = get_ime_hwnd()
	if not h then
		return nil
	end
	local ret = user32.SendMessageW(h, WM_IME_CONTROL, IMC_GETOPENSTATUS, 0)
	return ret ~= 0
end

local function ime_set_open(on)
	local h = get_ime_hwnd()
	if not h then
		return
	end
	user32.SendMessageW(h, WM_IME_CONTROL, IMC_SETOPENSTATUS, on and 1 or 0)
end

local function might_ime_on(mode)
	if mode == nil then
		return false
	end
	return mode:match("^[iRct]") ~= nil
end

------------------------------------------------------------
-- plugun body
------------------------------------------------------------

---@class WinImeAnchorConfig
---@field enable_polling boolean|nil         -- enable polling for IME status (default: false)
---@field polling_interval integer|nil       -- polling interval in milliseconds (default: 200)

local did_setup = false
local ime_state = nil -- nil = unknown state
local poll_timer = nil

local function save_ime_state(open)
	ime_state = open
end

local anchor_ime_off = function()
	local open = ime_get_open()
	if open ~= nil then
		-- save the IME status before anchoring IME OFF
		save_ime_state(open)
	end
	if open then
		ime_set_open(false)
	end
end

local restore_anchored_ime = function()
	if ime_state == nil then
		-- DO nothing if no stored status
		return
	end
	if ime_get_open() == ime_state then
		-- Do nothing if the status is already the same
		return
	end
	-- Restore the IME status when entering insert mode
	ime_set_open(ime_state)
end

local function poll_ime_state()
	local mode = vim.api.nvim_get_mode().mode

	if might_ime_on(mode) then
		-- Do nothing.
		-- User might changed IME state intentionally.
	else
		-- non-insert-like modes must keep IME off
		local open = ime_get_open()
		if open == true then
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

	opts = opts or {}

	-- Do nothing if not windows or ffi is not available
	if not is_windows() or not ensure_ffi() then
		return
	end

	local group = vim.api.nvim_create_augroup("WinImeAnchor", { clear = true })
	vim.api.nvim_create_autocmd("ModeChanged", {
		group = group,
		callback = function(ev)
            -- split `match` into old_mode and new_mode
			local old_mode, new_mode = ev.match:match("([^:]+):([^:]+)")
			if might_ime_on(new_mode) then
				restore_anchored_ime()
			else
				anchor_ime_off()
			end
		end,
	})
	if opts.enable_polling then
		local interval = opts.polling_interval or 200

		poll_timer = vim.loop.new_timer()
		poll_timer:start(interval, interval, vim.schedule_wrap(poll_ime_state))

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

return M
