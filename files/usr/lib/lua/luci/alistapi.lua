local fs = require "nixio.fs"
local sys = require "luci.sys"
local json = require "luci.jsonc"
local uci = require "luci.model.uci".cursor()

local API_BASE = "http://127.0.0.1:5244"
local TOKEN_FILE = "/tmp/alist_token"
local TOKEN_TTL = 1800  -- 30 minutes

local M = {}

local function get_creds()
    return {
        username = uci:get("alist", "main", "username") or "admin",
        password = uci:get("alist", "main", "password") or ""
    }
end

local function save_token(t)
    fs.writefile(TOKEN_FILE, t)
end

local function load_token()
    local t = fs.readfile(TOKEN_FILE)
    return t and t:gsub("%s+", "") or ""
end

function M.login()
    local c = get_creds()
    if c.password == "" then
        return nil, "password not configured"
    end
    local req = "/tmp/alist_login.json"
    fs.writefile(req, json.stringify({ username = c.username, password = c.password }))
    local cmd = string.format(
        "curl -s --connect-timeout 3 --max-time 8 -X POST '%s/api/auth/login' -H 'Content-Type: application/json' --data-binary @%s",
        API_BASE, req
    )
    local out = sys.exec(cmd) or ""
    local r = json.parse(out)
    if r and r.code == 200 and r.data and r.data.token then
        save_token(r.data.token)
        return r.data.token
    end
    return nil, (r and r.message) or "login failed"
end

function M.token()
    local t = load_token()
    local st = fs.stat(TOKEN_FILE)
    if t ~= "" and st and (os.time() - st.mtime) < TOKEN_TTL then
        return t
    end
    return M.login()
end

function M.call(method, path, body, retry)
    local token, err = M.token()
    if not token then
        return nil, err
    end
    local reqfile = "/tmp/alist_req.json"
    local cmd
    local url = string.format("'%s%s'", API_BASE, path)
    local headers = "-H 'Content-Type: application/json' -H 'Authorization: " .. token .. "'"
    if body then
        fs.writefile(reqfile, json.stringify(body))
        cmd = string.format("curl -s --connect-timeout 3 --max-time 8 -w '\\nHTTP_CODE:%%{http_code}' -X %s %s %s --data-binary @%s",
            method, url, headers, reqfile)
    else
        cmd = string.format("curl -s --connect-timeout 3 --max-time 8 -w '\\nHTTP_CODE:%%{http_code}' -X %s %s %s",
            method, url, headers)
    end
    local out = sys.exec(cmd) or ""
    local data, code = out:match("^(.*)\nHTTP_CODE:(%d+)$")
    if not code then
        return nil, "no http code"
    end
    if code == "401" and not retry then
        fs.remove(TOKEN_FILE)
        return M.call(method, path, body, true)
    end
    local ok, r = pcall(json.parse, data or "{}")
    if not ok then
        return nil, "json parse error"
    end
    if code ~= "200" or not r or r.code ~= 200 then
        return nil, (r and r.message) or ("http " .. code)
    end
    return r
end

return M
