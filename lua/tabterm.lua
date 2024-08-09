local M = {}

function M.file_exists(name)
    local f = io.open(name,"r")
    if f ~= nil then
        io.close(f)
        return true
    end
    return false
end

-- Find tabterm buffer matching tab_id
function M.find_term_buffer(tab_id)
    local lst = vim.api.nvim_list_bufs()
    for _, b in pairs(lst) do
        local name = vim.api.nvim_buf_get_name(b)
        local match = string.match(name, "^term://.*//.*#tabterm" .. tab_id .. "#")
        if match then
            return b
        end
    end
    return nil
end

-- Find window that is connected to buffer with buf_id
function M.find_buffer_window(buf_id)
    local lst = vim.api.nvim_list_wins()
    for _, w in pairs(lst) do
        if vim.api.nvim_win_get_buf(w) == buf_id then
            return w
        end
    end
    return nil
end

function M.get_first_free_tab_id()
    local used = {}
    local num_tabs = vim.fn.tabpagenr("$")
    for i = 1, num_tabs do
        local d = vim.fn.gettabvar(i, "tabterm_data", nil)
        if d ~= vim.NIL then
            used[d.id] = true
        end
    end

    for i = 1, num_tabs do
        if not used[i] then
            return i
        end
    end

    -- This should never happen
    print("ERROR: tabterm, logic is broken")
    return nil
end

-- Find window that is connected to buffer with buf_id
function M.get_tab_data(tab_id)
    local data = vim.fn.gettabvar(tab_id, "tabterm_data", nil)
    if data == vim.NIL then
        data = M.data_defs
        data['id'] = M.get_first_free_tab_id()
        vim.fn.settabvar(tab_id, "tabterm_data", data)
    end

    return data
end

function M.get_term_window(tab_id)
    local b = M.find_term_buffer(tab_id)
    if b then
        local w = M.find_buffer_window(b)
        return w
    end
    return nil
end

function M.toggle_tab_term()
    -- Get unique tab_id
    tab_id = vim.fn.tabpagenr()
    local tab_data = M.get_tab_data(tab_id)

    -- Find any existing tab-buffer
    local b = M.find_term_buffer(tab_data.id)
    if b then
        -- Look for window
        local w = M.find_buffer_window(b)
        if w then
            -- We have an open window, just close it.
            -- but first store it's width.
            tab_data.width = vim.api.nvim_win_get_width(w)
            vim.fn.settabvar(tab_id, "tabterm_data", tab_data)
            vim.api.nvim_win_close(w, true)

            M.store_session_data()
            return
        end

        -- We have a buffer, reopen it in a new window
        vim.cmd("vertical botright sbuffer " .. b)
        w = M.get_term_window(tab_data.id)
        vim.api.nvim_win_set_width(w, tab_data.width)
        vim.cmd("startinsert")

        M.store_session_data()
        return
    end

    -- We need to start a new terminal
    local cwd = vim.fn.getcwd()
    vim.cmd("vertical botright vnew term://" .. cwd ..
            "//1:bash;\\#tabterm" .. tab_data.id .. "\\#")

    local init = cwd .. '/init.sh'
    if M.file_exists(init) then
        local b = M.find_term_buffer(tab_data.id)
        local id = vim.fn.getbufvar(b, "terminal_job_id")
        vim.api.nvim_chan_send(id, "source ./init.sh\n")
    end

    vim.cmd("startinsert")

    M.store_session_data()
    return
end

function M.on_win_enter()
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)
    local match = string.match(name, "^term://.*//.*#tabterm[0-9]+#")

    if match then
        vim.api.nvim_win_set_option(win, "winhighlight", "Normal:Terminal")
        vim.cmd("startinsert")
    else
        -- Don't reset all highlights
        local option = vim.api.nvim_win_get_option(win, "winhighlight")
        if string.match(option, "Normal:Terminal") then
            vim.api.nvim_win_set_option(win, "winhighlight", "")
        end
    end
end

function M.store_session_data()
    local data = {}
    for i = 1, vim.fn.tabpagenr("$") do
        local d = vim.fn.gettabvar(i, "tabterm_data", nil)
        if d ~= vim.NIL then
            data["" .. i] = d
        end
    end
    vim.g.Tabterm_session_data = vim.fn.json_encode(data)
end

function M.on_session_load_post()
    if vim.g.Tabterm_session_data == nil then
        return
    end
    local data = vim.fn.json_decode(vim.g.Tabterm_session_data)
    for v, k in pairs(data) do
        vim.fn.settabvar(v, "tabterm_data", k)
    end
end

function M.setup(opts)
    M.data_defs = {
        id = nil,
        width = 80
    }

    if opts and opts.width then
        M.data_defs = opts.width
    end

    vim.cmd([[
        autocmd SessionLoadPost * lua require'tabterm'.on_session_load_post()

        autocmd WinEnter,BufEnter * lua require'tabterm'.on_win_enter()

        command! TabTermToggle lua require'tabterm'.toggle_tab_term()
    ]])

    nesqi.keymap {"n", "<C-t><C-t>", ":TabTermToggle<CR>"}
    nesqi.keymap {"t", "<C-t><C-t>", "<C-\\><C-n>:TabTermToggle<CR>"}

end

return M
