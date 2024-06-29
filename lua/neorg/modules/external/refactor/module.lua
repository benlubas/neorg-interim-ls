--[[
    file: Refactor-Module
    title: Refactoring things for the LSP
    summary: A helper module for all the refactoring operations the LSP can use
    internal: true
    ---

No commands here, just functions that refactor things.
--]]

local neorg = require("neorg.core")
local Path = require("pathlib")
local modules = neorg.modules
local log = neorg.log

local module = modules.create("external.refactor")

module.setup = function()
    return {
        success = true,
        requires = {
            "core.integrations.treesitter",
            "core.dirman",
            "core.dirman.utils",
        },
    }
end

local dirman, dirman_utils, ts
module.load = function()
    -- TODO: how would I get types in here?
    ---@type core.integrations.treesitter
    ts = module.required["core.integrations.treesitter"]
    dirman = module.required["core.dirman"]
    dirman_utils = module.required["core.dirman.utils"]
end

---@class external.refactor
module.public = {
    ---move the current file from one location to another, and update all the links to/from the file
    ---in the current workspace. Deletes the buffer of the original file if it exists
    ---@param current_path string
    ---@param new_path string
    ---@return boolean success
    rename_file = function(current_path, new_path)
        new_path = vim.fs.normalize(new_path)
        current_path = vim.fs.normalize(current_path)

        if new_path == current_path then
            return false
        end

        if Path(new_path):exists() then
            log.error(
                ("Cannot move file `%s` to `%s` becuase `%s` already exists."):format(current_path, new_path, new_path)
            )
            return false
        end

        local buf = vim.uri_to_bufnr(vim.uri_from_fname(current_path))
        local total_changed = { files = 0, links = 0 }

        ---@type lsp.WorkspaceEdit
        local wsEdit = { changes = {} }
        ---@param link Link
        local current_file_changes = module.private.fix_links(current_path, function(link)
            local range = link.file and link.file.range
            local link_str = link.file and link.file.text
            local raw = false
            if link.type and link.type.text == "/ " then
                range = link.text.range -- don't ask me why the parser does this
                link_str = link.text.text
                raw = true
            end
            if not range then
                return
            end
            local link_path, rel = dirman_utils.expand_pathlib(link_str, raw, current_path)
            if link_path and rel then
                -- it's relative to the file location, so we might have to change it
                local lp = Path(tostring(link_path)):relative_to(Path(new_path), true):resolve():remove_suffix(".norg")
                if lp then
                    return tostring(lp), unpack(range)
                end
            end
        end)
        if #current_file_changes > 0 then
            total_changed.files = total_changed.files + 1
            total_changed.links = total_changed.links + #current_file_changes
            local current_path_uri = vim.uri_from_fname(new_path)
            wsEdit.changes[current_path_uri] = current_file_changes
        end

        local ws_name = dirman.get_current_workspace()[1]
        local ws_path = dirman.get_current_workspace()[2]

        local files = dirman.get_norg_files(ws_name)
        local new_ws_path = "$" .. string.gsub(new_path, "^" .. ws_path, "")
        new_ws_path = string.gsub(new_ws_path, "%.norg$", "")
        for _, file in ipairs(files) do
            file = tostring(file)
            if file == current_path then
                goto continue
            end
            ---@param link Link
            local file_changes = module.private.fix_links(file, function(link)
                local range = link.file and link.file.range
                local link_str = link.file and link.file.text
                local raw = false
                if link.type and link.type.text == "/ " then
                    range = link.text.range -- don't ask me why the parser does this
                    link_str = link.text.text
                    raw = true
                end
                if not range then
                    return
                end
                local link_path, rel = dirman_utils.expand_pathlib(link_str, raw, file)
                if not link_path then
                    return
                end
                if link_path and link_path:samefile(Path(current_path)) then
                    ---@type PathlibPath | nil
                    local new_link
                    if rel then
                        new_link = Path(new_path):relative_to(Path(file):parent())
                        if not new_link then
                            return
                        end
                        new_link:resolve():remove_suffix(".norg")
                    else
                        new_link = Path(new_ws_path)
                    end
                    return tostring(new_link), unpack(range)
                end
            end)
            if #file_changes > 0 then
                total_changed.files = total_changed.files + 1
                total_changed.links = total_changed.links + #file_changes
                local file_uri = vim.uri_from_fname(file)
                wsEdit.changes[file_uri] = file_changes
            end

            ::continue::
        end

        if not Path(new_path):parent():exists() then
            Path(new_path):parent():mkdir(750, true)
        end
        vim.api.nvim_buf_delete(buf, {})
        vim.lsp.util.apply_workspace_edit(wsEdit, "utf-8")
        vim.notify(
            ("[Neorg] renamed %s to %s\nChanged %d links across %d files."):format(
                current_path,
                new_path,
                total_changed.links,
                total_changed.files
            ),
            vim.log.levels.INFO
        )
        return true
    end,

    ---rename the heading on the given line. Updating all links in the current workspace that point to
    ---the heading
    ---@param line_number number 1-indexed line number the heading is on
    ---@param new_heading string new heading, including the leading `*`s
    rename_heading = function(line_number, new_heading)
        line_number = line_number - 1
        local buf = vim.api.nvim_get_current_buf()
        local node = ts.get_first_node_on_line(buf, line_number)
        local line = vim.api.nvim_buf_get_lines(buf, line_number, line_number + 1, false)
        local prefix = line[1]:match("^%*+ ")
        local new_prefix = new_heading:match("^%*+ ")
        local new_name = new_heading:sub(#new_prefix + 1)
        if not node then
            return
        end

        local title = node:field("title")[1]
        if not title then
            return
        end

        local title_text = ts.get_node_text(title)
        local total_changed = {
            files = 0,
            links = 0,
        }

        -- headings with checkbox items have this extra white space.
        title_text = string.gsub(title_text, "^ ", "")

        ---@type lsp.WorkspaceEdit
        local wsEdit = { changes = {} }
        ---@param link Link
        local changes = module.private.fix_links(buf, function(link)
            local link_prefix = link.type and link.type.text
            local link_heading = link.text and link.text.text
            -- NOTE: This will not work for {:path/to/current/file:# heading} but who would do that..
            if not link.file and (link_prefix == "# " or link_prefix == prefix) and link_heading == title_text then
                local p = new_prefix
                if link_prefix == "# " then
                    p = "# "
                end
                return ("{%s%s}"):format(p, new_name)
            end
        end)

        local file_uri = vim.uri_from_bufnr(buf)
        wsEdit.changes[file_uri] = changes

        -- change the heading in our file too
        table.insert(wsEdit.changes[file_uri], {
            newText = new_heading .. "\n",
            range = {
                start = {
                    line = line_number,
                    character = 0,
                },
                ["end"] = {
                    line = line_number + 1,
                    character = 0,
                },
            },
        })
        if #changes - 1 > 0 then
            total_changed.files = total_changed.files + 1
            total_changed.links = total_changed.links + #changes - 1
        end

        -- loop through all the files
        local ws_name = dirman.get_current_workspace()[1]
        local files = dirman.get_norg_files(ws_name)

        local current_path = vim.api.nvim_buf_get_name(0)
        for _, file in ipairs(files) do
            if file == current_path then
                goto continue
            end

            ---@param link Link
            changes = module.private.fix_links(file, function(link)
                local link_str = link.file and link.file.text
                if not link_str then
                    return
                end

                local link_path, _ = dirman_utils.expand_pathlib(link_str, false, current_path)
                local link_heading = link.text and link.text.text
                local link_prefix = link.type and link.type.text
                if not link_heading or not link_prefix then
                    return
                end

                if
                    (link_prefix == "# " or link_prefix == prefix)
                    and link_heading == title_text
                    and link_path:samefile(Path(current_path))
                then
                    local p = new_prefix
                    if link_prefix == "# " then
                        p = "# "
                    end
                    return ("%s%s"):format(p, new_name),
                        link.type.range[1],
                        link.type.range[2],
                        link.text.range[3],
                        link.text.range[4]
                end
            end)
            if #changes > 0 then
                wsEdit.changes[vim.uri_from_fname(file)] = changes
                total_changed.files = total_changed.files + 1
                total_changed.links = total_changed.links + #changes
            end

            ::continue::
        end

        vim.lsp.util.apply_workspace_edit(wsEdit, "utf-8")
        vim.notify(
            ("[Neorg] renamed %s to %s\nChanged %d links across %d files."):format(
                title_text,
                new_name,
                total_changed.links,
                total_changed.files
            ),
            vim.log.levels.INFO
        )
    end,
}

---Abstract function to generate TextEdits that alter matching links
---@param source number | string bufnr or filepath
---@param fix_link function takes a string, the current link, returns a string, the new link,
---or nil if this shouldn't be changed
module.private.fix_links = function(source, fix_link)
    local links = nil
    links = module.private.get_links(source)

    local edits = {}
    for _, link in ipairs(links) do
        local new_link, start_line, start_char, end_line, end_char = fix_link(link)
        if new_link then
            ---@type lsp.TextEdit
            local text_edit = {
                newText = new_link,
                range = {
                    start = {
                        line = start_line or link.range[1],
                        character = start_char or link.range[2],
                    },
                    ["end"] = {
                        line = end_line or link.range[3],
                        character = end_char or link.range[4],
                    },
                },
            }
            table.insert(edits, text_edit)
        end
    end

    return edits
end

---@class NodeText
---@field range Range
---@field text string

---@class Link
---@field file? NodeText
---@field type? NodeText
---@field text? NodeText
---@field range Range range of the entire link

---fetch all the links in the given buffer
---@param source number | string bufnr or full path to file
---@return Link[]
module.private.get_links = function(source)
    local link_query_string = [[
        (link
          (link_location
            file: (_)* @file
            type: (_)* @type
            text: (_)* @text) @link_location)
    ]]
    local norg_parser
    local iter_src
    if type(source) ~= "string" and type(source) ~= "number" then
        source = tostring(source)
    end
    if type(source) == "string" then
        -- check if the file is open; use the buffer contents if it is
        ---@diagnostic disable-next-line: param-type-mismatch
        if vim.fn.bufexists(source) == 1 then
            source = vim.uri_to_bufnr(vim.uri_from_fname(source))
        else
            iter_src = io.open(source, "r"):read("*a")
            norg_parser = vim.treesitter.get_string_parser(iter_src, "norg")
        end
    end
    if type(source) == "number" then
        if source == 0 then
            source = vim.api.nvim_get_current_buf()
        end
        norg_parser = vim.treesitter.get_parser(source, "norg")
        iter_src = source
    end
    if not norg_parser then
        return {}
    end
    local norg_tree = norg_parser:parse()[1]
    local query = vim.treesitter.query.parse("norg", link_query_string)
    local links = {}
    for _, match in query:iter_matches(norg_tree:root(), iter_src) do
        local link = {}
        for id, node in pairs(match) do
            local name = query.captures[id]
            link[name] = {
                text = ts.get_node_text(node, iter_src),
                ---@diagnostic disable-next-line: undefined-field
                range = { node:range() },
            }
        end
        link.range = link.link_location.range
        link.link_location = nil
        table.insert(links, link)
    end
    return links
end

return module
