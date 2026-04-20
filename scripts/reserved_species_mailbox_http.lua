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

    local function shellSingleQuote(s)
        return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
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
        local resp = nil
        local err = nil
        local gotViaPopen = false
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

    return {
        jsonEscapeForBridge = jsonEscapeForBridge,
        pokegenHttpPostCurl = pokegenHttpPostCurl,
    }
end
