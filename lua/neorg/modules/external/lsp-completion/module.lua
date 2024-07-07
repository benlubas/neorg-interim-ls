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
local modules = neorg.modules

local module = modules.create("external.lsp-completion")

module.private = {}

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
                    insertText = insert_text,
                    label = label,
                    kind = module.private.completion_item_mapping[completion_cache.options.type],
                }
            end

            callback(nil, completions)
        end
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

        return {
            start_offset = col_num + 1,
            char = col_num,
            before_char = request.context.triggerCharacter,
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
