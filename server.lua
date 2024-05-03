#!/usr/bin/env lua
local linenoise
local has_linenoise
has_linenoise, linenoise = pcall(require, 'linenoise')
---@type uv
local uv = require('luv')
local addr = #arg >= 1 and arg[1] or "127.0.0.1"
local port = #arg >= 2 and tonumber(arg[2]) or 8777
local server_addr = addr .. ":" .. tostring(port)
local cmd
local prev_cmd
---@type uv.uv_tcp_t|nil
local client
---@type uv.uv_tcp_t|nil
local server

PROMPT = 'debugger.lua>'
COLOR_RED = string.char(27) .. "[91m"
COLOR_YELLOW = string.char(27) .. "[33m"
COLOR_RESET = string.char(27) .. "[0m"
PROMPT_COLOR = COLOR_RED .. PROMPT .. COLOR_RESET ..' '
INFO_COLOR = COLOR_YELLOW.."debugger.lua: "..COLOR_RESET
HISTORY_PATH = os.getenv('HOME') .. '/.lua_history'
CLIENT_READY = '\r\r\r\r'

local function shutdown(code)
    if client then
        client:read_stop()
        client:close()
    end
    if server then
        server:close()
    end
    os.exit(code)
end

local function read_cmd()
    if has_linenoise and not os.getenv("DBG_NOREADLINE") then
        local str = linenoise.linenoise(PROMPT_COLOR)
        if str and not str:match "^%s*$" then
            linenoise.historyadd(str)
            linenoise.historysave(HISTORY_PATH)
        end
        return str
    else
        io.write(PROMPT_COLOR)
        return io.read('*l')
    end
end

--------------------------------------------------------------------------------

if has_linenoise and not os.getenv("DBG_NOREADLINE") then
    -- Load command history from ~/.lua_history
    linenoise.historyload(HISTORY_PATH)
    linenoise.historysetmaxlen(50)

    print(INFO_COLOR .. "Linenoise support enabled.")
end

server = uv.new_tcp()
assert(server, "socket creation failed")

server:bind(addr, port)
server:listen(1, function (err)
    assert(not err, err)

    client = uv.new_tcp()
    assert(client, "socket creation failed")

    server:accept(client)
    ---@diagnostic disable-next-line: redefined-local
    client:read_start(function (err, chunk)
        if err then
            print(err)
            io.flush()
            shutdown(1)
        end

        if chunk then
            local data, cnt = chunk:gsub(CLIENT_READY, '')
            io.write(data)
            io.flush()
            if cnt ~= 0 then
                -- Start reading once we see the 'CLIENT_READY' string
                cmd = read_cmd()
                if cmd == nil then
                    -- Handle ^D
                    shutdown(0)

                elseif cmd == "" then
                    -- Repeat previous command by default
                    cmd = prev_cmd or 'h'
                end

                client:write(cmd)
                prev_cmd = cmd

                if cmd == 'q' or cmd == 'quit' then
                    shutdown(0)
                end
            end
        else
            -- No more data
            print(INFO_COLOR ..  "Connection closed")
            shutdown(0)
        end
    end)
end)

print(INFO_COLOR .. "Listening on " .. server_addr .. "...")
uv.run('default')
