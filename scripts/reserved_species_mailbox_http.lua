-- HTTP bridge helpers (loaded by reserved_species_mailbox.lua).

return function(M)
    local function jsonEscapeForBridge(s)
        s = tostring(s or "")
        s = s:gsub("\\", "\\\\")
        s = s:gsub('"', '\\"')
        s = s:gsub("\n", "\\n")
        s = s:gsub("\r", "\\r")
        return s
    end

    local function parsePokegenJsonResponse(s)
        if not s or s == "" then
            return nil, 0
        end
        local st = s:match('"status"%s*:%s*"(%a+)"')
        local rs = s:match('"result_species"%s*:%s*(%d+)')
        return st, tonumber(rs or 0)
    end

    local function jsonUnescapeFromBridge(s)
        if not s then
            return nil
        end
        s = tostring(s)
        s = s:gsub("\\n", "\n")
        s = s:gsub("\\r", "\r")
        s = s:gsub('\\"', '"')
        s = s:gsub("\\\\", "\\")
        return s
    end

    local function shellSingleQuote(s)
        return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
    end

    local function runHostCurlCommand(cmd)
        local maxSec = M.POKEGEN_HTTP_MAX_TIME_SEC or 30
        local resp = nil
        local err = nil
        local gotViaPopen = false
        local tmp = os.tmpname() or "build/pokegen_http_tmp.txt"
        if io and io.popen then
            local okPopen, hOrErr = pcall(io.popen, cmd)
            if okPopen and hOrErr then
                gotViaPopen = true
                local okRead, dataOrErr = pcall(function()
                    local s = hOrErr:read("*a")
                    hOrErr:close()
                    return s
                end)
                if okRead then
                    resp = dataOrErr
                else
                    err = tostring(dataOrErr)
                    gotViaPopen = false
                end
            elseif not okPopen then
                err = tostring(hOrErr)
            end
        end
        if not gotViaPopen and os and os.execute then
            local outPath = tmp .. ".out"
            local redir = cmd .. " > " .. shellSingleQuote(outPath) .. " 2>&1"
            local okEx, codeOrErr = pcall(os.execute, redir)
            if not okEx then
                err = err or tostring(codeOrErr)
            end
            local rf = io.open(outPath, "r")
            if rf then
                resp = rf:read("*a")
                rf:close()
            end
            pcall(os.remove, outPath)
        end
        pcall(os.remove, tmp)
        return resp, err
    end

    -- POST JSON to pokegen-server via host curl (blocking). Requires curl on PATH.
    -- mGBA may define io.popen but throw "'popen' not supported" — use pcall and fall back to os.execute.
    local function pokegenHttpPostCurl(url, jsonBody)
        local maxSec = M.POKEGEN_HTTP_MAX_TIME_SEC or 30
        local tmp = os.tmpname()
        if not tmp then
            tmp = "build/pokegen_http_body.json"
        end
        local wf = io.open(tmp, "w")
        if not wf then
            return false, nil, nil, "cannot write temp JSON body"
        end
        wf:write(jsonBody)
        wf:close()
        -- -d @file avoids shell-escaping the JSON body; quote URL and path for sh.
        local qtmp = shellSingleQuote(tmp)
        local qurl = shellSingleQuote(url)
        local cmd = string.format(
            "curl -sS --max-time %d -X POST -H %s -d @%s %s",
            maxSec,
            shellSingleQuote("Content-Type: application/json"),
            qtmp,
            qurl
        )
        local resp, err = runHostCurlCommand(cmd)
        pcall(os.remove, tmp)
        if not resp or resp == "" then
            return false,
                nil,
                nil,
                err
                    or "empty response (install curl; check POKEGEN_HTTP_URL). If mGBA blocks subprocesses, use a build that allows os.execute."
        end
        local st, rs = parsePokegenJsonResponse(resp)
        return true, st, rs, nil
    end

    local function pokegenHttpGetCurl(url)
        local maxSec = M.POKEGEN_HTTP_MAX_TIME_SEC or 30
        local qurl = shellSingleQuote(url)
        local cmd = string.format("curl -sS --max-time %d %s", maxSec, qurl)
        local resp, err = runHostCurlCommand(cmd)
        if not resp or resp == "" then
            return false, nil, err or "empty HTTP GET response"
        end
        return true, resp, nil
    end

    local function parsePokegenPayloadResponse(s)
        if not s or s == "" then
            return nil
        end
        local out = {}
        out.speciesName = jsonUnescapeFromBridge(s:match('"species_name"%s*:%s*"(.-)"'))
        out.pokedexDescription = jsonUnescapeFromBridge(s:match('"pokedex_description"%s*:%s*"(.-)"'))
        out.frontImageUrl = jsonUnescapeFromBridge(s:match('"front_image"%s*:%s*%b{}.-"url"%s*:%s*"(.-)"'))
        out.backImageUrl = jsonUnescapeFromBridge(s:match('"back_image"%s*:%s*%b{}.-"url"%s*:%s*"(.-)"'))
        out.iconImageUrl = jsonUnescapeFromBridge(s:match('"icon_image"%s*:%s*%b{}.-"url"%s*:%s*"(.-)"'))
        out.footprintImageUrl = jsonUnescapeFromBridge(s:match('"footprint_image"%s*:%s*%b{}.-"url"%s*:%s*"(.-)"'))
        out.cryAudioUrl = jsonUnescapeFromBridge(s:match('"cry_audio"%s*:%s*%b{}.-"url"%s*:%s*"(.-)"'))
        out.moveset = {}
        local movesBlob = s:match('"moveset"%s*:%s*%[(.-)%]')
        if movesBlob and movesBlob ~= "" then
            for chunk in movesBlob:gmatch("%b{}") do
                local lv = tonumber(chunk:match('"level"%s*:%s*(%d+)'))
                local mv = tonumber(chunk:match('"move_id"%s*:%s*(%d+)'))
                if lv and mv then
                    out.moveset[#out.moveset + 1] = { level = lv, move = mv }
                end
            end
        end
        if not out.speciesName and not out.pokedexDescription and not out.frontImageUrl and not out.backImageUrl then
            return nil
        end
        return out
    end

    return {
        jsonEscapeForBridge = jsonEscapeForBridge,
        pokegenHttpPostCurl = pokegenHttpPostCurl,
        pokegenHttpGetCurl = pokegenHttpGetCurl,
        parsePokegenPayloadResponse = parsePokegenPayloadResponse,
    }
end
