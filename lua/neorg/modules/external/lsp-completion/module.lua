--[[
    file: LSP-Completion
    title: Completions without a completion plugin
    summary: Provide an LSP Completion source for Neorg
    internal: true
    ---
This module works with the [`core.completion`](@core.completion) module to attempt to provide
intelligent completions.

After setting up `core.completion` with the `engine` set to `lsp-completion`. Then you can get
neorg completions the same way you get completions from other language servers.
--]]

local neorg = require("neorg.core")
local modules, utils = neorg.modules, neorg.utils

local module = modules.create("external.lsp-completion")

---@type core.integrations.treesitter
local ts

---@type core.dirman.utils
local dirman_utils

---@type core.dirman
local dirman

local query

module.setup = function()
    return {
        success = true,
        requires = {
            "core.integrations.treesitter",
            "core.dirman.utils",
            "core.dirman",
        },
    }
end

module.load = function()
    ts = module.required["core.integrations.treesitter"]
    dirman_utils = module.required["core.dirman.utils"]
    dirman = module.required["core.dirman"]
end

module.private = {
    ---Query neorg SE for a list of categories, and format them into completion items
    make_category_suggestions = function(cb)
        if not query then
            module.private.load_query()
        end

        query.list_categories(function(categories)
            cb(
                nil,
                vim.iter(categories)
                :map(function(c)
                    return { label = c, kind = 12 }     -- 12 == "Value"
                end)
                :totable()
            )
        end)
    end,

    load_query = function()
        if modules.load_module("external.query") then
            query = modules.get_module("external.query")
        end
    end,

    make_name_suggestions = function(people_path, params, cb)
        local ws_path = dirman.get_current_workspace()[2]
        local file = dirman_utils.expand_pathlib(ws_path / people_path)
        local people_headers = require("neorg.modules.core.completion.module").private.get_linkables(file, "generic")
        local pos = params.position
        local cursor_col = vim.api.nvim_win_get_cursor(0)[2]
        local line = vim.api.nvim_buf_get_lines(0, params.position.line, params.position.line + 1, false)[1]
        local plus1 = line:sub(cursor_col+1, cursor_col+1) == "}" and 1 or 0
        local ate = {
            {
                range = {
                    start = { line = pos.line, character = pos.character - 3 },
                    ["end"] = { line = pos.line, character = pos.character },
                },
                newText = "",
            },
        }

        cb(
            nil,
            vim.iter(people_headers)
            :map(function(x)
                local first_name = x.title:match("^(%w*)")
                return {
                    label = x.title,
                    kind = 18,     -- Reference
                    textEdit = {
                        range = {
                            start = { line = pos.line, character = pos.character },
                            ["end"] = { line = pos.line, character = cursor_col + plus1 },
                        },
                        newText = ("[%s]{:$/%s:# %s}"):format(first_name, people_path, x.title),
                    },
                    additionalTextEdits = ate,
                }
            end)
            :totable()
        )
        return true
    end,
}

---@class external.lsp-completion : neorg.completion_engine
module.public = {
    create_source = function()
        -- these numbers come from: https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#completionItemKind
        module.private.completion_item_mapping = {
            Directive = 14,
            Tag = 14,
            Language = 10,
            TODO = 23,
            Property = 10,
            Format = 10,
            Embed = 10,
            Reference = 18,
            File = 17,
        }

        function module.public.completion_handler(request, callback, _)
            local abstracted_context = module.public.create_abstracted_context(request)

            local completion_cache = module.public.invoke_completion_engine(abstracted_context)

            if completion_cache.options.pre then
                completion_cache.options.pre(abstracted_context)
            end

            local completions = vim.deepcopy(completion_cache.items)

            for index, element in ipairs(completions) do
                local insert_text = nil
                local label = element
                if type(element) == "table" then
                    insert_text = element[1]
                    label = element.label
                end
                completions[index] = {
                    label = label,
                    insertText = insert_text,
                    kind = module.private.completion_item_mapping[completion_cache.options.type],
                }
            end

            callback(nil, completions)
        end
    end,

    ---Generate context string for the completion
    ---@param params lsp.CompletionItem
    resolve_handler = function(params)
        if params.kind == 17 then -- file
            local path = params.label:gsub(":?%}?", "")
            local expanded_path = dirman_utils.expand_pathlib(path)
            local f = io.open(tostring(expanded_path), "r")
            if f then
                params.documentation = {
                    value = ("```norg\n%s\n```"):format(f:read("*a")),
                    kind = "markdown",
                }
            end
        end
        return params
    end,

    ---Provide categories as a completion source,
    category_completion = function(cb)
        local norg_query = utils.ts_parse_query(
            "norg",
            [[
                (document
                  (ranged_verbatim_tag
                    ((tag_name) @tag_name (#eq? @tag_name "document.meta"))
                    (ranged_verbatim_tag_content) @tag_content
                  )
                )
            ]]
        )

        local norg_parser, iter_src = ts.get_ts_parser(0)
        if not norg_parser then
            return false
        end
        local norg_tree = norg_parser:parse()[1]
        if not norg_tree then
            return false
        end

        local meta_node
        for id, node in norg_query:iter_captures(norg_tree:root(), iter_src) do
            if norg_query.captures[id] == "tag_content" then
                meta_node = node
            end
        end

        if not meta_node then
            return false
        end

        local meta_source = ts.get_node_text(meta_node, iter_src)
        local norg_meta_parser = vim.treesitter.get_string_parser(meta_source, "norg_meta")
        local norg_meta_tree = norg_meta_parser:parse()[1]
        if not norg_meta_tree then
            return false
        end

        local meta_query = utils.ts_parse_query(
            "norg_meta",
            [[
                (metadata
                  (pair
                    ((key) @key (#eq? @key "categories"))
                    (value) @value
                  ) @pair
                )
            ]]
        )

        for id, node in meta_query:iter_captures(norg_meta_tree:root(), meta_source) do
            if meta_query.captures[id] == "pair" then
                local range = ts.get_node_range(node)
                local meta_range = ts.get_node_range(meta_node)
                range.row_start = range.row_start + meta_range.row_start
                range.row_end = range.row_end + meta_range.row_start

                local cursor = vim.api.nvim_win_get_cursor(0)
                if cursor[1] - 1 >= range.row_start and cursor[1] - 1 <= range.row_end then
                    module.private.make_category_suggestions(cb)
                    return true
                end
            end
        end
    end,

    people_completion = function(path, params, cb)
        local buf = vim.uri_to_bufnr(params.textDocument.uri)
        local line = vim.api.nvim_buf_get_lines(buf, params.position.line, params.position.line + 1, false)[1]
        local pos = vim.api.nvim_win_get_cursor(0)
        line = line:sub(1, pos[2])
        if line:match("{@%w[^}]*$") then
            module.private.make_name_suggestions(path, params, cb)
            return true
        end
        return false
    end,

    -- {
    --   before_char = "@",
    --   buffer = 12,
    --   char = 4,
    --   column = 5,
    --   full_line = "   @",
    --   line = "   @",
    --   line_number = 32,
    --   previous_context = {
    --     column = 4,
    --     line = "   ",
    --     start_offset = 5
    --   },
    --   start_offset = 5
    -- }
    -- textDocument/completion
    -- {
    --   context = {
    --     triggerCharacter = "@",
    --     triggerKind = 2
    --   },
    --   position = {
    --     character = 4,
    --     line = 32
    --   },
    --   textDocument = {
    --     uri = "file:///home/benlubas/notes/test1.norg"
    --   }
    -- }

    create_abstracted_context = function(request)
        local line_num = request.position.line
        local col_num = request.position.character
        local buf = vim.uri_to_bufnr(request.textDocument.uri)
        local full_line = vim.api.nvim_buf_get_lines(buf, line_num, line_num + 1, false)[1]

        local before_char = (request.context and request.context.triggerCharacter) or full_line:sub(col_num, col_num)

        return {
            start_offset = col_num + 1,
            char = col_num,
            before_char = before_char,
            line_number = request.position.line,
            column = col_num + 1,
            buffer = buf,
            line = full_line:sub(1, col_num),
            -- this is never used anywhere, so it's probably safe to ignore
            -- previous_context = {
            --     line = request.context.prev_context.cursor_before_line,
            --     column = request.context.prev_context.cursor.col,
            --     start_offset = request.offset,
            -- },
            full_line = full_line,
        }
    end,

    invoke_completion_engine = function(context)
        error("`invoke_completion_engine` must be set from outside.")
        assert(context)
        return {}
    end,
}

return module
