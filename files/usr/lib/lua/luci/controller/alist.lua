module("luci.controller.alist", package.seeall)

local fs = require "nixio.fs"
local sys = require "luci.sys"
local http = require "luci.http"
local json = require "luci.jsonc"
local util = require "luci.util"
local api = require "luci.alistapi"

local DATA_DIR = "/overlay/alist/data"
local CFG = DATA_DIR .. "/config.json"
local DB = DATA_DIR .. "/data.db"
local TC_DATA = "/overlay/alist/ip_limits.json"
local TC_SCRIPT = "/overlay/alist/tc_apply.sh"

function index()
    if not nixio.fs.access("/usr/bin/alist") then
        return
    end
    entry({"admin", "nas", "alist"}, cbi("alist"), _("Alist"), 30).dependent = true
    entry({"admin", "nas", "alist_status"}, call("alist_status"))
    entry({"admin", "nas", "alist_apply"}, call("alist_apply"))

    entry({"admin", "nas", "alist_api", "fs", "list"}, call("alist_fs_list"))
    entry({"admin", "nas", "alist_api", "share", "list"}, call("alist_share_list"))
    entry({"admin", "nas", "alist_api", "share", "create"}, call("alist_share_create"))
    entry({"admin", "nas", "alist_api", "share", "delete"}, call("alist_share_delete"))

    entry({"admin", "nas", "alist_dashboard"}, call("alist_dashboard"))
    entry({"admin", "nas", "alist_users"}, call("alist_users"))
    entry({"admin", "nas", "alist_connections"}, call("alist_connections"))
    entry({"admin", "nas", "alist_block_ip"}, call("alist_block_ip"))
    entry({"admin", "nas", "alist_unblock_ip"}, call("alist_unblock_ip"))
    entry({"admin", "nas", "alist_blocked_ips"}, call("alist_blocked_ips"))

    entry({"admin", "nas", "alist_ip_limits"}, call("alist_ip_limits"))
    entry({"admin", "nas", "alist_ip_limit_add"}, call("alist_ip_limit_add"))
    entry({"admin", "nas", "alist_ip_limit_del"}, call("alist_ip_limit_del"))
    entry({"admin", "nas", "alist_ip_limit_apply"}, call("alist_ip_limit_apply"))
end

function json_ok(data)
    http.prepare_content("application/json")
    http.write_json({ code = 200, data = data })
end

function json_err(msg)
    http.prepare_content("application/json")
    http.write_json({ code = 500, message = msg })
end

function shell_trim(cmd)
    local ok, out = pcall(sys.exec, cmd .. " 2>/dev/null")
    if not ok or not out then return "" end
    return util.trim(out)
end

function alist_status()
    local e = {}
    e.running = (sys.call("pidof alist >/dev/null") == 0)
    e.port = 5244
    json_ok(e)
end

function alist_apply()
    local max_conn = tonumber(http.formvalue("max_connections")) or 20
    local down = tonumber(http.formvalue("max_client_download_speed")) or 10240
    local up = tonumber(http.formvalue("max_client_upload_speed")) or 5120
    if max_conn < 0 then max_conn = 0 end
    if down < 0 then down = 0 end
    if up < 0 then up = 0 end

    sys.call(string.format(
        "jq --argjson mc %d '.max_connections = $mc' %s > /tmp/alist_config.json.tmp && mv /tmp/alist_config.json.tmp %s",
        max_conn, CFG, CFG))

    local sql = string.format([[
INSERT OR REPLACE INTO x_setting_items (key,value,type,"group",flag,"index") VALUES
('max_client_download_speed','%d','number',2,0,0),
('max_client_upload_speed','%d','number',2,0,0);
]], down, up)
    local sqlfile = "/tmp/alist_settings.sql"
    fs.writefile(sqlfile, sql)
    sys.call(string.format("sqlite3 %s < %s", DB, sqlfile))
    fs.remove(sqlfile)

    sys.call("/etc/init.d/alist restart >/dev/null 2>&1")
    http.redirect(luci.dispatcher.build_url("admin/nas/alist"))
end

function alist_fs_list()
    local path = http.formvalue("path") or "/THZH百度盘"
    local r, err = api.call("POST", "/api/fs/list", { path = path, page = 1, per_page = 1000 })
    http.prepare_content("application/json")
    if r then
        http.write(json.stringify(r))
    else
        http.write(json.stringify({ code = 500, message = err or "fs list failed" }))
    end
end

function alist_share_list()
    local r, err = api.call("GET", "/api/share/list?page=1&per_page=100")
    http.prepare_content("application/json")
    if r then
        http.write(json.stringify(r))
    else
        http.write(json.stringify({ code = 500, message = err or "share list failed" }))
    end
end

function alist_share_create()
    local path = http.formvalue("path") or ""
    local password = http.formvalue("password") or ""
    local hours = tonumber(http.formvalue("expires_hours")) or 0
    if path == "" then
        return json_err("path required")
    end
    local expires = 0
    if hours > 0 then
        expires = hours * 3600
    end
    local r, err = api.call("POST", "/api/share/create", {
        path = path,
        password = password,
        expires_in = expires
    })
    http.prepare_content("application/json")
    if r then
        http.write(json.stringify(r))
    else
        http.write(json.stringify({ code = 500, message = err or "create failed" }))
    end
end

function alist_share_delete()
    local sid = http.formvalue("share_id") or ""
    if sid == "" then
        return json_err("share_id required")
    end
    local r, err = api.call("POST", "/api/share/delete", { share_id = sid })
    http.prepare_content("application/json")
    if r then
        http.write(json.stringify(r))
    else
        http.write(json.stringify({ code = 500, message = err or "delete failed" }))
    end
end

function get_users()
    local r = api.call("GET", "/api/admin/user/list?page=1&per_page=100")
    if r and r.data and r.data.content then
        return r.data.content
    end
    return {}
end

function get_connections()
    local out = shell_trim("ss -Htn state established '( sport = :5244 or dport = :5244 )' 2>/dev/null")
    if out == "" then
        out = shell_trim("ss -Htn 2>/dev/null | grep ':5244'")
    end
    local counts = {}
    for line in (out or ""):gmatch("[^\r\n]+") do
        local peer = line:match("%s(%d+%.%d+%.%d+%.%d+):%d+%s*$")
        if not peer then
            peer = line:match("%s(%d+%.%d+%.%d+%.%d+):%d+%s+%s*$")
        end
        if peer and peer ~= "127.0.0.1" then
            counts[peer] = (counts[peer] or 0) + 1
        end
    end
    local list = {}
    for ip, c in pairs(counts) do
        table.insert(list, { ip = ip, count = c })
    end
    table.sort(list, function(a, b) return a.ip < b.ip end)
    return list
end

function ipt_list_blocked()
    local out = sys.exec("iptables -S INPUT 2>/dev/null") or ""
    local list = {}
    for line in out:gmatch("[^\r\n]+") do
        local ip = line:match("%-A INPUT %-s (%d+%.%d+%.%d+%.%d+)/32 %-p tcp .*%-%-dport 5244 %-j DROP")
        if ip then
            table.insert(list, { ip = ip })
        end
    end
    return list
end

function alist_dashboard()
    json_ok({
        users = get_users(),
        connections = get_connections(),
        blocked = ipt_list_blocked(),
        ip_limits = read_ip_limits()
    })
end

function alist_users()
    json_ok(get_users())
end

function alist_connections()
    json_ok(get_connections())
end

function alist_block_ip()
    local ip = http.formvalue("ip") or ""
    if not ip:match("^%d+%.%d+%.%d+%.%d+$") then
        return json_err("invalid ip")
    end
    sys.call(string.format("iptables -I INPUT -s %s -p tcp --dport 5244 -j DROP", ip))
    json_ok(ipt_list_blocked())
end

function alist_unblock_ip()
    local ip = http.formvalue("ip") or ""
    if not ip:match("^%d+%.%d+%.%d+%.%d+$") then
        return json_err("invalid ip")
    end
    sys.call(string.format("iptables -D INPUT -s %s -p tcp --dport 5244 -j DROP", ip))
    json_ok(ipt_list_blocked())
end

function alist_blocked_ips()
    json_ok(ipt_list_blocked())
end

function read_ip_limits()
    local raw = fs.readfile(TC_DATA) or "{}"
    local ok, t = pcall(json.parse, raw)
    if not ok or type(t) ~= "table" then
        t = {}
    end
    return t
end

function write_ip_limits(t)
    fs.writefile(TC_DATA, json.stringify(t))
end

function alist_ip_limits()
    json_ok(read_ip_limits())
end

function alist_ip_limit_add()
    local ip = http.formvalue("ip") or ""
    local down = tonumber(http.formvalue("down")) or 0
    local up = tonumber(http.formvalue("up")) or 0
    if not ip:match("^%d+%.%d+%.%d+%.%d+$") then
        return json_err("invalid ip")
    end
    local t = read_ip_limits()
    local old = t[ip]
    t[ip] = { down = down, up = up }
    local changed = not old or old.down ~= down or old.up ~= up
    write_ip_limits(t)
    if changed then
        sys.call(TC_SCRIPT .. " apply")
    end
    json_ok(t)
end

function alist_ip_limit_del()
    local ip = http.formvalue("ip") or ""
    local t = read_ip_limits()
    if t[ip] then
        t[ip] = nil
        write_ip_limits(t)
        sys.call(TC_SCRIPT .. " apply")
    end
    json_ok(t)
end

function alist_ip_limit_apply()
    sys.call(TC_SCRIPT .. " apply")
    json_ok(read_ip_limits())
end
