# neorg-interim-ls

_Neorg's missing language server._

Rename files and headers, completions without an auto complete plugin, category completions,
jump to references from headings, links, or definitions

---

This module is labeled "interim" because it is meant to be temporary. Ideally, this module will be
superseded in a month or two by a "real" language server. But for the time being, the real LS is
blocked, so I've written this.

## Features

-   Move files and rename headings without breaking existing links to or
    from the file/heading.

    -   Works on all files in the workspace
    -   if a file is open, it will use the buffer contents instead of the file contents so unsaved
        changes are accounted for.
    -   Relative file links like `{/ ./path/to/file.txt}` are also changed when a file is moved.
    -   Moving a file to a location that already exists will fail with an error. Moving a file to a folder
        that doesn't exist will create the folder.

-   Provides a completion engine for Neorg that allows anyone to get Neorg completions (not just
    those using `nvim-cmp` or `coq-nvim`).
-   Complete category names with categories from your workspace (via [neorg-query](https://github.com/benlubas/neorg-query))
-   Show document content when completing file names
-   Complete `{@name}` to `[name]{:$/people:# name}`
    -   `[name]` is just the first name, `people` is configurable, you must accept the completion
        (default is `<c-y>`) to avoid broken syntax.

## Limitations

-   Links that include a file path to their own file (ie. `{:path/to/blah:}` while in `blah.norg`)
    are not supported in **refactoring operations**. But like, just don't do that.
-   The implementation for goto references uses `rg` for references outside of the current file. This
    is in the name of speed. Parsing everything with TS each time you need to find references is not
    really fast enough for my liking.
    -   The regex that we use will work 100% of the time as long as you use `{:$/path/to/file:}`
        syntax for file paths 100% of the time. (this is what autocomplete suggests, so this is not
        hard to do).

## Install

Install this plugin the way you would any other, and load it by adding this to your neorg config:

```lua
["external.interim-ls"] = {
    config = {
        -- default config shown
        completion_provider = {
            -- Enable or disable the completion provider
            enable = true,

            -- Show file contents as documentation when you complete a file name
            documentation = true,

            -- Try to complete categories provided by Neorg Query. Requires `benlubas/neorg-query`
            categories = false,

            -- suggest heading completions from the given file for `{@x|}` where `|` is your cursor
            -- and `x` is an alphanumeric character. `{@name}` expands to `[name]{:$/people:# name}`
            people = {
                enable = false,

                -- path to the file you're like to use with the `{@x` syntax, relative to the
                -- workspace root, without the `.norg` at the end.
                -- ie. `folder/people` results in searching `$/folder/people.norg` for headings.
                -- Note that this will change with your workspace, so it fails silently if the file
                -- doesn't exist
                path = "people",
            }
        }
    }
},
```

## Config

In addition to the Neorg module config above (which can be excluded as usual if you use the
defaults), this module is affected by LSP configuration. Keybinds should be setup by you in an
autocommand on the `LspAttach` event. Please note the only actions you will need for this LS are the
rename, and references actions, but this autocommand is used for _all_ of your configured language
servers.

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
        vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)

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

Refactoring and completion work just like a normal LSP:

-   type for completions, ensure that you enable category and/or people completions if you want them.
-   rename a heading: done with `:h vim.lsp.buf.rename()`
-   rename/move a file: handled by `willRename` which is supported by some file manager plugins such
    as [Oil.nvim](https://github.com/steavearc/oil.nvim)

Additionally, there are Neorg commands for the refactoring operations (though they are less
convenient than using the regular lsp interface):

-   `:Neorg lsp rename file`
-   `:Neorg lsp rename heading`
