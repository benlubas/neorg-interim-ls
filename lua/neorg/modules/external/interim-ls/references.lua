local M = {}

---produce the regular expression used to find lints to the given header (path qualified only,
---doesn't work for links within the file, search for those separately)
---@param workspace_path string|PathlibPath "/abs/path/to/workspace"
---@param current_file string|PathlibPath "test.norg"
---@param target {text: string, type: string} "{text: 'heading', type: '**'}"
---@return string
M.build_backlink_regex = function(workspace_path, current_file, target)
    local Path = require("pathlib")

    current_file = Path(vim.api.nvim_buf_get_name(0))
    current_file = current_file:relative_to(Path(workspace_path)):remove_suffix(".norg")

    target.type = target.type:gsub("%^", "\\^")
    target.type = target.type:gsub("%*", "\\*")
    target.type = target.type:gsub("%$", "\\$")
    return ([[\{:\$/%s:(#|%s) %s\}]]):format(current_file, target.type, target.text) -- {:$/workspace_path:(# heading or ** heading)}
end

---Runs a grep command to find references in the workspace, calls the callback with results
---@param regex string
---@param workspace_path PathlibPath
---@param callback fun(a: lsp.Location[])
M.run_grep = function(regex, workspace_path, callback)
    vim.system({ "rg", "--column", "-o", regex }, { cwd = tostring(workspace_path), text = true }, function(exit)
        if exit.code == 0 then
            local grep_results = vim.iter(vim.split(exit.stdout, "\n", { trimempty = true }))
                :map(function(out_line)
                    local path, linenr, colnr, match_start, match_end = out_line:match("^(.-):(%d*):(%d*):().*()$")
                    if not (path and linenr and colnr and match_start and match_end) then
                        return
                    end
                    linenr = tonumber(linenr)
                    colnr = tonumber(colnr)
                    local match_len = match_end - match_start

                    return {
                        uri = (workspace_path / path):as_uri(),
                        range = {
                            start = { line = linenr - 1, character = colnr },
                            ["end"] = { line = linenr - 1, character = colnr + match_len },
                        },
                    }
                end)
                :totable()
            callback(grep_results)
        else
            callback({})
        end
    end)
end

return M
