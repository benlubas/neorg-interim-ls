# neorg-interim-ls

Rename files and headers in your norg files without breaking links in the rest of the workspace.

---

This module is labeled "interim" because it is meant to be temporary. Ideally, this module will be
superseded in a month or two by a "real" language server. But for the time being, the real LS is
blocked, so I've written this.

This module provides a way to move files and rename headings without breaking existing links to or
from the file/heading. Works on all files in the workspace, if a file is open, it will use the
buffer contents instead of the file contents so unsaved changes are accounted for.

Relative file links like `{/ ./path/to/file.txt}` are also changed when a file is moved.

Moving a file to a location that already exists will fail with an error. Moving a file to a folder
that doesn't exist will create the folder.

## Limitations

- Links that include a file path to their own file (ie. `{:path/to/blah:}` while in `blah.norg`)
  are not supported. But like, just don't do that.

## Commands

- `Neorg ls rename file` - open a popup to rename the current file
- `Neorg ls rename header` - open a popup to rename the current header (must be used on a heading
line)

## Install

Install this plugin the way you would any other, and load it by adding this to your neorg config:

```lua
["external.interim-ls"] = {},
```

There is no config. Keybinds should be setup by you in an autocommand on the `LspAttach` event.
Please note the only action you will need for this LS is the rename action, but this autocommand is
used for _all_ of your configured language servers.

```lua
vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
        local bufnr = args.buf
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if not client then return end

        if client.server_capabilities.completionProvider then
            vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"
        end

        local opts = { noremap = true, silent = true, buffer = bufnr }
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)

        -- ... other lsp mappings
    end
})
```

## Usage

- rename a heading: done with `:h vim.lsp.buf.rename()`
- rename/move a file: handled by `willRename` which is supported by some file manager plugins such
as [Oil.nvim](https://github.com/steavearc/oil.nvim)
