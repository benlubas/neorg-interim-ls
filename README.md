# neorg-interim-ls

Neorg's missing language server.

-   Rename files and headers in your norg files without breaking links in the rest of the workspace
-   Get neorg completions without needing an auto completion plugin

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

Additionally, this plugin provides a completion engine for Neorg that allows anyone to get Neorg
completions (not just those using `nvim-cmp` or `coq-nvim`).

## Limitations

-   Links that include a file path to their own file (ie. `{:path/to/blah:}` while in `blah.norg`)
    are not supported in refactoring operations. But like, just don't do that.

## Install

Install this plugin the way you would any other, and load it by adding this to your neorg config:

```lua
["external.interim-ls"] = {
    config = {
        completion_provider = {
            -- enable/disable the completion provider. On by default.
            enable = true,

            -- Try to complete categories. Requires benlubas/neorg-se
            categories = false,
        }
    }
},
```

## Config

In addition to the Neorg module config above (which can be excluded as usual if you use the
defaults), this module is affected by LSP configuration. Keybinds should be setup by you in an
autocommand on the `LspAttach` event. Please note the only action you will need for this LS is the
rename action, but this autocommand is used for _all_ of your configured language servers.

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

        -- ... your other lsp mappings
    end
})
```

### Completion

First ensure that you're able to get LSP completions in some way. This will vary by completion
plugin. For nvim-cmp you will need the `nvim-cmp-lsp` source. For mini-completion things should work
out of the box. If you're using nvim's builtin omnifunc, I trust you know what you're doing.

Then, configure Neorg's completion module like this:

```lua
["core.completion"] = {
    config = { engine = { module_name = "external.lsp-completion" } },
},
```

## Usage

Refactoring works just like a normal LSP:

-   rename a heading: done with `:h vim.lsp.buf.rename()`
-   rename/move a file: handled by `willRename` which is supported by some file manager plugins such
    as [Oil.nvim](https://github.com/steavearc/oil.nvim)

Additionally, there are Neorg commands that that can accomplish the same things (though they are less convienient):

-   `:Neorg lsp rename file`
-   `:Neorg lsp rename heading`
