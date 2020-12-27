dofile("table_show.lua")
dofile("urlcode.lua")
local urlparse = require("socket.url")
local http = require("socket.http")
JSON = assert(loadfile "JSON.lua")()

local item_value = os.getenv('item_value')
local item_type = os.getenv('item_type')
local item_dir = os.getenv('item_dir')
local warc_file_base = os.getenv('warc_file_base')

local url_count = 0
local tries = 0
local downloaded = {}
local addedtolist = {}
local abortgrab = false


if urlparse == nil or http == nil then
  io.stdout:write("socket not corrently installed.\n")
  io.stdout:flush()
  abortgrab = true
end

local ids = {}
local pages_covered = {}

for ignore in io.open("ignore-list", "r"):lines() do
  downloaded[ignore] = true
  downloaded[string.gsub(ignore, '^https', 'http', 1)] = true
end

read_file = function(file)
  if file then
    local f = assert(io.open(file))
    local data = f:read("*all")
    f:close()
    return data
  else
    return ""
  end
end

allowed = function(url, parenturl)
  if string.match(url, "^https?://www%.smackjeeves%.com/api/comments/write")
    or string.match(url, "^https?://www%.smackjeeves%.com/api/comments/report")
    or string.match(url, "^https?://www%.smackjeeves%.com/api/comments/delete")
    or string.match(url, "^https?://www%.smackjeeves%.com/api/comments/good")
    or string.match(url, "^https?://www%.smackjeeves%.com/api/comments/articleGood")
    or string.match(url, "^https?://www%.smackjeeves%.com/login")
    or string.match(url, "^https?://www%.smackjeeves%.com/search")
    or string.match(url, "^https?://resources%.smackjeeves%.com/js/")
    or string.match(url, "^https?://www%.smackjeeves%.com/api/favorite/")
    or string.match(url, "^https?://www%.smackjeeves%.com/discover%?type=")
    or string.match(url, "^https?://www%.smackjeeves%.com/bookshelf")
    or string.match(url, "^https?://www%.smackjeeves%.com/comment/report")
    or string.match(url, "^https?://www%.smackjeeves%.com/settings")
    or string.match(url, "^https?://www%.smackjeeves%.com/author/%d+") then
    return false
  end

  -- These ARE downloaded, but it must be a post request, so anything that calls allowed() shouldn't GET it
  if url == 'https://www.smackjeeves.com/api/comments/get' then
    return false
  end

  -- Do not match article lists for comics other than the one in the item
  if (string.match(url, '^https?://www%.smackjeeves%.com/discover/articleList%?titleNo=%d+$')
    or string.match(url, '^https?://www%.smackjeeves%.com/articleList%?titleNo=%d+$'))
    and url ~= "https://www.smackjeeves.com/discover/articleList?titleNo=" .. item_value
    and url ~= "https://www.smackjeeves.com/articleList?titleNo=" .. item_value
    and item_type == "comic" then
    return false
  end

  --[[local tested = {}
  for s in string.gmatch(url, "([^/]+)") do
    if tested[s] == nil then
      tested[s] = 0
    end
    if tested[s] == 6 then
      return false
    end
    tested[s] = tested[s] + 1
  end]]

  if string.match(url, "^https?://www%.smackjeeves%.com/")
    or string.match(url, "^https?://api%.smackjeeves%.com/")
    or string.match(url, "^https?://images%.smackjeeves%.com/") then
    return true
  end
  -- I have taken out resources. - seemed to be entirely statuc, and a lot of bad extraction was happening for that

  return false
end

wget.callbacks.download_child_p = function(urlpos, parent, depth, start_url_parsed, iri, verdict, reason)
  --[[if string.match(url, "^https?://images%.smackjeeves%.com/legacy/title/")
  or (allowed(url) and string.match(parent, item_value)) then
    addedtolist[url] = true
    return true
  end
  ]]
  local url = urlpos["url"]["url"]
  if downloaded[url] == true or addedtolist[url] == true then
    return false
  end
  if allowed(url) then
    addedtolist[url] = true
    return true
  end

  return false
end

wget.callbacks.get_urls = function(file, url, is_css, iri)
  local urls = {}
  local html = nil

  downloaded[url] = true

  local function check(urla, force)
    local origurl = url
    local url = string.match(urla, "^([^#]+)")
    local url_ = string.match(url, "^(.-)%.?$")
    url_ = string.gsub(url_, "&amp;", "&")
    url_ = string.match(url_, "^(.-)%s*$")
    url_ = string.match(url_, "^(.-)%??$")
    url_ = string.match(url_, "^(.-)&?$")
    url_ = string.match(url_, "^(.-)/?$")
    if (downloaded[url_] ~= true and addedtolist[url_] ~= true)
      and (allowed(url_, origurl) or force) then
      table.insert(urls, { url=url_ })
      addedtolist[url_] = true
      addedtolist[url] = true
    end
  end

  local function checknewurl(newurl)
    if string.match(newurl, "\\[uU]002[fF]") then
      return checknewurl(string.gsub(newurl, "\\[uU]002[fF]", "/"))
    end
    if string.match(newurl, "^https?:////") then
      check(string.gsub(newurl, ":////", "://"))
    elseif string.match(newurl, "^https?://") then
      check(newurl)
    elseif string.match(newurl, "^https?:\\/\\?/") then
      check(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^\\/") then
      checknewurl(string.gsub(newurl, "\\", ""))
    elseif string.match(newurl, "^//") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^/") then
      check(urlparse.absolute(url, newurl))
    elseif string.match(newurl, "^%.%./") then
      if string.match(url, "^https?://[^/]+/[^/]+/") then
        check(urlparse.absolute(url, newurl))
      else
        checknewurl(string.match(newurl, "^%.%.(/.+)$"))
      end
    elseif string.match(newurl, "^%./") then
      check(urlparse.absolute(url, newurl))
    end
  end

  local function checknewshorturl(newurl)
    if string.match(newurl, "^%?") then
      check(urlparse.absolute(url, newurl))
    elseif not (string.match(newurl, "^https?:\\?/\\?//?/?")
      or string.match(newurl, "^[/\\]")
      or string.match(newurl, "^%./")
      or string.match(newurl, "^[jJ]ava[sS]cript:")
      or string.match(newurl, "^[mM]ail[tT]o:")
      or string.match(newurl, "^vine:")
      or string.match(newurl, "^android%-app:")
      or string.match(newurl, "^ios%-app:")
      or string.match(newurl, "^%${")) then
      check(urlparse.absolute(url, "/" .. newurl))
    end
  end

  -- Main comic page
  if url == "https://www.smackjeeves.com/discover/articleList?titleNo=" .. item_value
    and item_type == "comic"
    and status_code == 200 then
    html = read_file(file)

    if string.match(html, '<h1 class="maintenance__title">URL not found</h1>[%s%c]+<p class="maintenance__lead">Please, try again later%.</p>') then
      io.stdout:write("No comic exists at this ID; finishing successfully...\n")
      io.stdout:flush()
      return {}
    end

    if string.match(html, '<h1 class="maintenance__title">') then
      io.stdout:write("Encountered some error message on the page; SJ may be overloaded.\n")
      io.stdout:flush()
      abortgrab = true
      return {}
    end

    -- These two actually give you the same thing if you don't use POST, from what I've observed, but that makes them fail in the WebRecorder player
    table.insert(urls, { url="https://www.smackjeeves.com/api/discover/articleList?titleNo=" .. item_value, post_data="titleNo=" .. item_value})
    table.insert(urls, { url="https://www.smackjeeves.com/api/discover/getCampaignInfo?titleNo=" .. item_value, post_data="titleNo=" .. item_value})

    -- Cover image, if it exists
    -- Note this may also get covers of suggestions - this is fine, small size & I am not sure there is only one thumbnail size
    local title = string.match(html, '"(https://images%.smackjeeves%.com/legacy/title/[^"]+)"')
    if title then
      check(title)
    end

    -- Try to capture redirects from old URLs
    check("http://www.smackjeeves.com/comicprofile.php?id=" .. item_value)

    -- Note that not all of the subdomain redirects consist of the lowered, no-space title, but this seems like a good guess for a lot.
    local title = string.match(html, '<h1 class="article%-hero__ttl">([^<]+)</h1>')
    local subdomain = string.lower(string.gsub(title, '%W', ''))
    check("http://" .. subdomain .. ".thewebcomic.com/", true)
    check("http://" .. subdomain .. ".smackjeeves.com/", true)
  end

  local function queue_comment_api_page(pagenum)
    if pages_covered[pagenum] == true then
      return
    end
    table.insert(urls, { url="https://www.smackjeeves.com/api/comments/get", post_data="titleNo=" .. item_value .. "&articleNo=".. pagenum .. "&page=1&order=new" })
    table.insert(urls, { url="https://www.smackjeeves.com/api/comments/get", post_data="titleNo=" .. item_value .. "&articleNo=".. pagenum .. "&page=1&order=good" })
    table.insert(urls, { url="https://www.smackjeeves.com/api/comments/getAll", post_data="titleNo=" .. item_value .. "&articleNo=".. pagenum .. "&page=1&order=new" })
    table.insert(urls, { url="https://www.smackjeeves.com/api/comments/getAll", post_data="titleNo=" .. item_value .. "&articleNo=".. pagenum .. "&page=1&order=good" })
    pages_covered[pagenum] = true
  end

  -- Individual page (in the print sense) of a comic
  if string.match(url, "^https://www.smackjeeves.com/discover/detail%?titleNo=" .. item_value .. "&articleNo=[0-9]+$")
    and item_type == "comic"
    and status_code == 200 then
    html = read_file(file)
    local pagenum = string.match(url, "^https://www.smackjeeves.com/discover/detail%?titleNo=" .. item_value .. "&articleNo=([0-9]+)$")
    if pagenum == nil then
      io.stdout:write("Pagenum is nil.\n")
      io.stdout:flush()
      abortgrab = true
    end

    if string.match(html, '<h1 class="maintenance__title">') then
      io.stdout:write("Encountered some error message on the page; SJ may be overloaded.\n")
      io.stdout:flush()
      abortgrab = true
      return {}
    end

    -- For whatever reason, when you click the forward/next buttons, it goes to one of the pages (without /discover/) that are queued as follows, which just redirects to the /discover/details page
    check("https://www.smackjeeves.com/detail?titleNo=" .. item_value .. "&articleNo=" .. pagenum, true)

    local at_least_one_img_captured = false
    -- https://www.smackjeeves.com/discover/detail?titleNo=179756&articleNo=66 is a page with multiple images
    for image in string.gmatch(html, "'(https?://images%.smackjeeves%.com/[^']+/dims/optimize)'") do
      check(image, true)
      unoptimized_image = string.match(image, "^(https?://images%.smackjeeves%.com/[^']+)/dims/optimize$")
      check(unoptimized_image, true)
      at_least_one_img_captured = true
    end
    if not at_least_one_img_captured then
      io.stdout:write("No images found on this page; please save your logs (if possible) and contact OrIdow6; aborting.\n")
      io.stdout:flush()
      abortgrab = true
    end

    -- Author profile picture & "recommended for you" covers
    for image in string.gmatch(html, 'background%-image:%s*url%(([^)(<>"]+)%)') do
      check(image, true)
    end

    -- Separate comments page
    check("https://www.smackjeeves.com/comment/" .. item_value .. "/" .. pagenum, true)
    -- Comments API requests
    queue_comment_api_page(pagenum)

    -- Just in case the article list isn't comprehensive for whatever reason...
    if pagenum ~= "1" then
      local prevpn = tostring(tonumber(pagenum) - 1)
      check("https://www.smackjeeves.com/discover/detail?titleNo=" .. item_value .. "&articleNo=" .. prevpn, true)
    end
  end

  -- Comment API requests
  if item_type == "comic" and status_code == 200
    and url == "https://www.smackjeeves.com/api/comments/getAll" then
    html = read_file(file)
    local json = JSON:decode(html)
    if json["result"]["currentPageNo"] < json["result"]["totalPageCnt"] then
      next_page = json["result"]["currentPageNo"] + 1
      queue_comment_api_page(next_page)
    end
  end

  -- XHR list of comic pages
  if item_type == "comic"
    and url == "https://www.smackjeeves.com/api/discover/articleList?titleNo=" .. item_value
    and status_code == 200 then
    html = read_file(file)
    local json = JSON:decode(html)
    for i, v in pairs(json["result"]["list"]) do
      check(v["articleUrl"], true)
      check(v["imgUrl"], true)
    end
  end

  -- Comment API pages - save avatars
  if item_type == "comic"
    and url == "https://www.smackjeeves.com/api/comments/getAll"
    and status_code == 200 then
    html = read_file(file)
    local json = JSON:decode(html)
    for i, v in pairs(json["result"]["list"]) do
      check(v["imgUrl"], true)
    end
  end


  if allowed(url, nil) and status_code == 200
    and not string.match(url, '^https?://images%.smackjeeves%.com') then
    html = read_file(file)
    for newurl in string.gmatch(string.gsub(html, "&quot;", '"'), '([^"]+)') do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(string.gsub(html, "&#039;", "'"), "([^']+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, ">%s*([^<%s]+)") do
      checknewurl(newurl)
    end
    for newurl in string.gmatch(html, "[^%-]href='([^']+)'") do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, '[^%-]href="([^"]+)"') do
      checknewshorturl(newurl)
    end
    for newurl in string.gmatch(html, ":%s*url%(([^%)]+)%)") do
      checknewurl(newurl)
    end
  end

  return urls
end

wget.callbacks.httploop_result = function(url, err, http_stat)
  status_code = http_stat["statcode"]

  url_count = url_count + 1
  io.stdout:write(url_count .. "=" .. status_code .. " " .. url["url"] .. "  \n")
  io.stdout:flush()

  if status_code >= 300 and status_code <= 399 then
    local newloc = urlparse.absolute(url["url"], http_stat["newloc"])
    if downloaded[newloc] == true or addedtolist[newloc] == true
      or not allowed(newloc, url["url"]) then
      tries = 0
      return wget.actions.EXIT
    end
  end

  if status_code >= 200 and status_code <= 399 then
    downloaded[url["url"]] = true
  end

  if abortgrab == true then
    io.stdout:write("ABORTING...\n")
    io.stdout:flush()
    return wget.actions.ABORT
  end

  if status_code == 0
    or (status_code > 400 and status_code ~= 404) then
    io.stdout:write("Server returned " .. http_stat.statcode .. " (" .. err .. "). Sleeping.\n")
    io.stdout:flush()
    local maxtries = 12
    if not allowed(url["url"], nil) then
      maxtries = 3
    end
    if tries >= maxtries then
      io.stdout:write("I give up...\n")
      io.stdout:flush()
      tries = 0
      if maxtries == 3 then
        return wget.actions.EXIT
      else
        return wget.actions.ABORT
      end
    else
      os.execute("sleep " .. math.floor(math.pow(2, tries)))
      tries = tries + 1
      return wget.actions.CONTINUE
    end
  end

  tries = 0

  local sleep_time = 0

  if sleep_time > 0.001 then
    os.execute("sleep " .. sleep_time)
  end

  return wget.actions.NOTHING
end


wget.callbacks.before_exit = function(exit_status, exit_status_string)
  if abortgrab == true then
    return wget.exits.IO_FAIL
  end
  return exit_status
end

