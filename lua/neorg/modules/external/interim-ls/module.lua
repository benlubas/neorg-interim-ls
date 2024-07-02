--[[
    file: Interim-LS-Module
    title: Some Missing Language Server Features
    summary: A module that provides some missing LS features as a builtin neorg module instead of a true, external language server binary
    internal: false
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
  are not supported

## Commands

- `Neorg ls rename file`
- `Neorg ls rename header`
--]]

local neorg = require("neorg.core")
local modules = neorg.modules
local log = neorg.log

local module = modules.create("external.interim-ls")

module.setup = function()
    return {
        success = true,
        requires = {
            "core.integrations.treesitter",
            "core.dirman",
            "core.dirman.utils",
            "core.neorgcmd",
            "core.ui.text_popup",
            "external.refactor",
        },
    }
end

local dirman, refactor, ts
module.load = function()
    module.required["core.neorgcmd"].add_commands_from_table({
        lsp = {
            min_args = 0,
            max_args = 1,
            name = "lsp",
            condition = "norg",
            subcommands = {
                rename = {
                    args = 1,
                    name = "interim-ls.rename",
                    subcommands = {
                        file = {
                            min_args = 0,
                            max_args = 1,
                            name = "interim-ls.rename.file",
                        },
                        heading = {
                            args = 0,
                            name = "interim-ls.rename.heading",
                        },
                    },
                },
            },
        },
    })
    ---@type core.integrations.treesitter
    ts = module.required["core.integrations.treesitter"]
    dirman = module.required["core.dirman"]
    ---@type external.refactor
    refactor = module.required["external.refactor"]

    vim.api.nvim_create_autocmd("FileType", {
        pattern = "norg",
        callback = module.private.start_lsp,
    })
end

module.private.handlers = {
    ["initialize"] = function(_params, callback, _notify_reply_callback)
        local initializeResult = {
            capabilities = {
                renameProvider = {
                    prepareProvider = true,
                },
                workspace = {
                    fileOperations = {
                        willRename = {
                            filters = {
                                {
                                    pattern = {
                                        matches = "file",
                                        glob = "**/*.norg",
                                    },
                                },
                            },
                        },
                        didRename = true,
                    },
                },
            },
            serverInfo = {
                name = "neorg-refactor-ls",
                version = "0.0.1",
            },
        }
        callback(nil, initializeResult)
    end,

    ["textDocument/prepareRename"] = function(params, callback, _notify_reply_callback)
        local buf = vim.uri_to_bufnr(params.textDocument.uri)
        local node = ts.get_first_node_on_line(buf, params.position.line)
        if not node then
            return
        end

        local type = node:type()
        if type:match("^heading%d") then
            -- let the rename go through
            local range = {
                start = { line = params.position.line, character = 0 },
                ["end"] = { line = params.position.line + 1, character = 0 },
            }
            local heading_line =
                vim.api.nvim_buf_get_lines(buf, params.position.line, params.position.line + 1, true)[1]
            callback(nil, { range = range, placeholder = heading_line })
        end
    end,

    ["textDocument/rename"] = function(params, _callback, _notify_reply_callback)
        refactor.rename_heading(params.position.line + 1, params.newName)
    end,

    ["workspace/willRenameFiles"] = function(params, _callback, _notify_reply_callback)
        for _, files in ipairs(params.files) do
            local old = vim.uri_to_fname(files.oldUri)
            local new = vim.uri_to_fname(files.newUri)
            refactor.rename_file(old, new)
        end
    end,
}

module.private.start_lsp = function()
    -- setup and attach the shell LSP for file renaming
    -- https://github.com/jmbuhr/otter.nvim/pull/137/files
    vim.lsp.start({
        name = "neorg-interim-ls",
        capabilities = vim.lsp.protocol.make_client_capabilities(),
        cmd = function(_dispatchers)
            local members = {
                trace = "messages",
                request = function(method, params, callback, notify_reply_callback)
                    if module.private.handlers[method] then
                        module.private.handlers[method](params, callback, notify_reply_callback)
                    else
                        log.warn("Unexpected LSP method: " .. method)
                    end
                end,
                notify = function(_method, _params) end,
                is_closing = function() end,
                terminate = function() end,
            }
            return members
        end,
        filetypes = { "norg" },
        root_dir = tostring(dirman.get_current_workspace()[2]),
    })
end

module.events.subscribed = {
    ["core.neorgcmd"] = {
        ["interim-ls.rename.file"] = true,
        ["interim-ls.rename.heading"] = true,
    },
}

module.on_event = function(event)
    if module.private[event.split_type[2]] then
        module.private[event.split_type[2]](event)
    end
end

module.private["interim-ls.rename.file"] = function(event)
    local new_path = event.content[1]
    local current = vim.api.nvim_buf_get_name(0)
    if new_path then
        refactor.rename_file(current, new_path)
    else
        vim.schedule(function()
            vim.ui.input({ prompt = "New Path: ", default = current }, function(text)
                refactor.rename_file(current, text)
                vim.cmd.e(text)
            end)
        end)
    end
end

module.private["interim-ls.rename.heading"] = function(event)
    local line_number = event.cursor_position[1]
    local prefix = string.match(event.line_content, "^%s*%*+ ")
    if not prefix then -- this is a very very simple check that we're on a heading line. We use TS in the actual rename_heading function
        return
    end

    vim.schedule(function()
        vim.ui.input({ prompt = "New Heading: ", default = event.line_content }, function(text)
            if not text then
                return
            end

            refactor.rename_heading(line_number, text)
        end)
    end)
end

return module
