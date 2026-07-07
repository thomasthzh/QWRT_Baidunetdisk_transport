local m = Map("alist", translate("Alist"), translate("Alist 管理面板：状态、分享、限速、在线管理。"))
m:chain("alist")

local s = m:section(SimpleSection, translate("Alist Status"))
s.template = "alist_status"

local sh = m:section(SimpleSection, translate("Share Links"))
sh.template = "alist_shares"

local bw = m:section(SimpleSection, translate("Bandwidth & Concurrency"))
bw.template = "alist_bandwidth"

local adm = m:section(SimpleSection, translate("Admin Console"))
adm.template = "alist_admin"

return m
