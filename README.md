# win-ime-anchor.nvim

A Windows-only Neovim plugin that keeps IME always OFF in NORMAL mode.
It enforces IME OFF as a fixed baseline when entering NORMAL mode, automatically correcting accidental IME state changes and anchoring the editor to a predictable input state.

No external depenencies. The plugin controls the IME via Win32 API using LugJIT FFI.

# Requirements

* Neovim >= 0.11
* Windows

Do nothing on non-Windows platforms.

# Installation

lazy.nvim

```
{
    "slotport/win-ime-anchor.nvim",
    lazy = false
}
```


