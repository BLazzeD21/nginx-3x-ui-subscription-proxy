local http = require "resty.http"

local servers_str = os.getenv("SERVERS")

if not servers_str then
    ngx.log(ngx.ERR, "SERVERS env is empty")
    return ngx.exit(500)
end

local servers = {}
for server in string.gmatch(servers_str, "[^%s]+") do
    table.insert(servers, server)
end

local function parse_userinfo(header)
    if not header then
        return 0, 0, 0, 0
    end

    local upload   = tonumber(header:match("upload=(%d+)")) or 0
    local download = tonumber(header:match("download=(%d+)")) or 0
    local total    = tonumber(header:match("total=(%d+)")) or 0
    local expire   = tonumber(header:match("expire=(%d+)")) or 0

    return upload, download, total, expire
end

local httpc = http.new()
httpc:set_timeout(15000)

local configs = {}

local sum_upload = 0
local sum_download = 0
local sum_total = 0

local infinite = false
local max_expire = 0

local profile_title = nil
local announces_raw = {}

for _, base_url in ipairs(servers) do

    local url = base_url .. ngx.var.sub_id

    local res, err = httpc:request_uri(url, {
        method = "GET",
        ssl_verify = false,
        headers = {
            ["User-Agent"] = "Clash",
            ["Accept"] = "*/*"
        }
    })

    if not res then
        ngx.log(ngx.ERR, "Request failed: ", err)
        goto continue
    end

    if res.status ~= 200 then
        ngx.log(ngx.ERR, "Bad status: ", res.status)
        goto continue
    end

    local decoded = ngx.decode_base64(res.body)
    if decoded and decoded ~= "" then
        table.insert(configs, decoded)
    end

    local upload, download, total, expire =
        parse_userinfo(res.headers["Subscription-Userinfo"])

    sum_upload = sum_upload + upload
    sum_download = sum_download + download

    if total == 0 then
        infinite = true
    elseif not infinite then
        sum_total = sum_total + total
    end

    if expire > max_expire then
        max_expire = expire
    end

    if not profile_title and res.headers["Profile-Title"] then
        profile_title = res.headers["Profile-Title"]
    end

    if res.headers["Announce"] then
        table.insert(announces_raw, res.headers["Announce"])
    end

    ::continue::
end

if infinite then
    sum_total = 0
end

local announces_decoded = {}

for _, v in ipairs(announces_raw) do
    local clean = v:gsub("^base64:", "")
    local decoded = ngx.decode_base64(clean)

    if decoded then
        table.insert(announces_decoded, decoded)
    end
end

local final_announce = ""

if #announces_decoded > 0 then
    local joined = table.concat(announces_decoded, " | ")
    final_announce = "base64:" .. ngx.encode_base64(joined)
end

if #configs == 0 then
    ngx.status = 502
    ngx.say("No configs")
    return
end

local combined = table.concat(configs, "\n")
local encoded = ngx.encode_base64(combined)

ngx.header["Content-Type"] = "text/plain; charset=utf-8"
ngx.header["Profile-Title"] = profile_title or "Subscription"
ngx.header["Profile-Update-Interval"] = "3"

ngx.header["Subscription-Userinfo"] =
    "upload=" .. sum_upload ..
    "; download=" .. sum_download ..
    "; total=" .. sum_total ..
    "; expire=" .. max_expire

ngx.header["Announce"] = final_announce
ngx.header["Content-Length"] = #encoded

ngx.print(encoded)
