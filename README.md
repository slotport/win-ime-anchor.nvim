# win-ime-anchor.nvim

A Windows-only Neovim plugin that keeps IME always OFF in NORMAL mode.
It enforces IME OFF as a fixed baseline when entering NORMAL mode, automatically correcting accidental IME state changes and anchoring the editor to a predictable input state.

# Requirements

* Neovim >= 0.11
* Windows


# Installation

lazy.nvim

```
{
    "slotport/win-ime-anchor.nvi",
    enabled = vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1,
    lazy = false
}
```


