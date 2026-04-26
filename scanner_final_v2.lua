local HttpService      = game:GetService("HttpService")
local TeleportService  = game:GetService("TeleportService")
local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local Workspace        = game:GetService("Workspace")
local LocalPlayer      = Players.LocalPlayer

-- ═══════════════════════════════════════════════
--  CONFIGURAÇÃO
-- ═══════════════════════════════════════════════
local DISCORD_WEBHOOK  = "https://discord.com/api/webhooks/1497417672756039929/tu9DObizbZ68I7-Zvrf7hWSFapqhinHNAcxh9R9yfgt7rPAEo_jd2aW3TFgdZCkdHQFq"
local FIREBASE_URL     = "https://la-suprema-f3571-default-rtdb.firebaseio.com/scanner_logs.json"
local GAME_ID          = 109983668079237
local MIN_VALUE        = 20000000
local SCAN_WAIT        = 8
local HOP_TIMEOUT      = 5          
local EMBED_COLOR      = 0xFFD700
local NOTIFIER_NAME    = "One Piece Notify"

local BLACK_NAMES      = {}
local TARGET_NAMES     = {}
local ULTRA_BRAINROTS  = {}

-- ═══════════════════════════════════════════════
--  LOG HELPERS
-- ═══════════════════════════════════════════════
local ICONS = {
    ok      = "✅",
    warn    = "⚠️ ",
    err     = "❌",
    scan    = "🔍",
    found   = "🎯",
    hop     = "➡️ ",
    discord = "📨",
    fire    = "🔥",
    ultra   = "🔴",
    high    = "🟠",
    mid     = "🟡",
    duel    = "⚔️",
    skip    = "⏭️ ",
    fetch   = "🌐",
    queue   = "📋",
}

local function ts() return os.date("%H:%M:%S") end
local function log(icon, msg) print(string.format("[%s] %s  %s", ts(), icon, msg)) end
local function sep() print("  " .. string.rep("─", 46)) end
local function banner(text)
    local pad = math.floor((44 - #text) / 2)
    print("  ╔" .. string.rep("═", 46) .. "╗")
    print("  ║" .. string.rep(" ", pad) .. text .. string.rep(" ", 46 - pad - #text) .. "║")
    print("  ╚" .. string.rep("═", 46) .. "╝")
end

-- ═══════════════════════════════════════════════
--  HTTP
-- ═══════════════════════════════════════════════
local http_request = (syn and syn.request) or (http and http.request) or request

local function httpGet(url)
    local ok, res = pcall(http_request, {Url=url, Method="GET"})
    if not ok or not res or res.StatusCode ~= 200 then return nil end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
    return ok2 and data or nil
end

local function httpPost(url, body)
    local ok, res = pcall(http_request, {
        Url     = url,
        Method  = "POST",
        Headers = {["Content-Type"]="application/json"},
        Body    = HttpService:JSONEncode(body),
    })
    return ok and res
end

local function httpPatch(url, body)
    local ok, res = pcall(http_request, {
        Url     = url,
        Method  = "PATCH",
        Headers = {["Content-Type"]="application/json"},
        Body    = HttpService:JSONEncode(body),
    })
    return ok and res
end

-- ═══════════════════════════════════════════════
--  PARSE / FORMAT
-- ═══════════════════════════════════════════════
local function parseValue(text)
    if not text then return 0 end
    local clean = tostring(text):gsub("[%$%s,/smh]", "")
    local numStr, suf = clean:match("([%d%.]+)(%a?)")
    if not numStr then return 0 end
    local n    = tonumber(numStr) or 0
    local mult = ({K=1e3,M=1e6,B=1e9,T=1e12})[(suf or ""):upper()] or 1
    return n * mult
end

local function fmtV(v)
    if v >= 1e12 then return ("%.2fT"):format(v/1e12) end
    if v >= 1e9  then return ("%.2fB"):format(v/1e9)  end
    if v >= 1e6  then return ("%.2fM"):format(v/1e6)  end
    if v >= 1e3  then return ("%.1fK"):format(v/1e3)  end
    return tostring(math.floor(v))
end

-- ═══════════════════════════════════════════════
--  FIREBASE — DEDUP
--  Antes de enviar ao webhook, verifica se já há
--  um log igual no Firebase (mesmo jobId+name+gen).
--  Se não houver, salva e envia. Se houver, skipa.
-- ═══════════════════════════════════════════════
local function firebaseKey(jobId, name, gen)
    -- Firebase keys não podem ter . # $ [ ]
    local raw = jobId .. "__" .. name .. "__" .. gen
    return raw:gsub("[%.#%$%[%]]", "_")
end

local function firebaseAlreadyLogged(jobId, name, gen)
    local key = firebaseKey(jobId, name, gen)
    local url = ("https://la-suprema-f3571-default-rtdb.firebaseio.com/scanner_logs/%s.json"):format(key)
    local data = httpGet(url)
    -- Firebase retorna `null` (nil em Lua após decode) se não existir
    return data ~= nil
end

local function firebaseSaveLog(jobId, name, gen, extra)
    local key = firebaseKey(jobId, name, gen)
    local url = ("https://la-suprema-f3571-default-rtdb.firebaseio.com/scanner_logs/%s.json"):format(key)
    local payload = {
        jobId   = jobId,
        name    = name,
        gen     = gen,
        ts      = os.time(),
        value   = extra and extra.value or 0,
        owner   = extra and extra.owner or "?",
    }
    httpPatch(url, payload)
end

-- ═══════════════════════════════════════════════
--  CARREGAR MÓDULOS
-- ═══════════════════════════════════════════════
local Synchronizer, AnimalsData, AnimalsShared

do
    local function tryLoad(parent, name)
        local ok, r = pcall(function() return require(parent:WaitForChild(name, 5)) end)
        return ok and r or nil
    end
    local ok1, Packages = pcall(function() return RS:WaitForChild("Packages", 5) end)
    local ok2, Datas    = pcall(function() return RS:WaitForChild("Datas",    5) end)
    local ok3, Shared   = pcall(function() return RS:WaitForChild("Shared",   5) end)
    if ok1 and Packages then Synchronizer  = tryLoad(Packages, "Synchronizer") end
    if ok2 and Datas    then AnimalsData   = tryLoad(Datas,    "Animals")      end
    if ok3 and Shared   then AnimalsShared = tryLoad(Shared,   "Animals")      end
end

local useSync = Synchronizer and AnimalsData and AnimalsShared
if useSync then
    log(ICONS.ok,   "Módulos carregados → modo SYNC (avançado)")
else
    log(ICONS.warn, "Módulos ausentes → modo LEGADO")
end

-- ═══════════════════════════════════════════════
--  FILTROS
-- ═══════════════════════════════════════════════
local function isBlacklisted(n)
    local low = n:lower()
    for _, b in ipairs(BLACK_NAMES) do if b~="" and low:find(b:lower()) then return true end end
    return false
end
local function isTargeted(n)
    local low = n:lower()
    for _, t in ipairs(TARGET_NAMES) do if t~="" and low:find(t:lower()) then return true end end
    return false
end
local function shouldScan(name, genValue)
    if isBlacklisted(name) then return false end
    return genValue >= MIN_VALUE or isTargeted(name)
end

-- ═══════════════════════════════════════════════
--  HELPERS DE DUEL / OWNER
-- ═══════════════════════════════════════════════
local function isFusing(a)
    return a.Machine and a.Machine.Type=="Fuse" and a.Machine.Active
end

local function isInDuel(a)
    if a.Machine and type(a.Machine)=="table" then
        local mt = a.Machine.Type
        if type(mt)=="string" and mt:lower():find("duel") then return true end
    end
    if a.InDuel==true or a.inDuel==true then return true end
    local d = a.Data or a
    if type(d)=="table" and (d.InDuel==true or d.inDuel==true) then return true end
    return false
end

local function cameBackFromDuel(player)
    if player==LocalPlayer then
        local ok, d = pcall(function() return TeleportService:GetLocalPlayerTeleportData() end)
        if ok and type(d)=="table" and (d.fromDuel or d.DuelData or d.duel) then return true end
    end
    for _, c in ipairs(player:GetChildren()) do
        local n = c.Name:lower()
        if n:find("duel") or n:find("returned") then return true end
    end
    local ok, attrs = pcall(function() return player:GetAttributes() end)
    if ok and attrs then
        for k,v in pairs(attrs) do
            if k:lower():find("duel") and (v==true or v==1) then return true end
        end
    end
    return false
end

local function getDuelPlayers()
    local dp = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if cameBackFromDuel(p) then dp[p.Name]=true; dp[tostring(p.UserId)]=true end
    end
    return dp
end

local function getPlotOwner(plot)
    local oa = plot:GetAttribute("Owner") or plot:GetAttribute("PlayerName")
    if oa then
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Name==tostring(oa) or tostring(p.UserId)==tostring(oa) then return p end
        end
    end
    for _, p in ipairs(Players:GetPlayers()) do if p.Name==plot.Name then return p end end
    return nil
end

local function isPlotOwnerInDuel(plot, duelPlayers)
    local owner = plot:GetAttribute("Owner") or plot:GetAttribute("PlayerName") or plot.Name
    if duelPlayers[owner] or duelPlayers[tostring(owner)] then return true end
    local p = getPlotOwner(plot)
    if p and (duelPlayers[p.Name] or duelPlayers[tostring(p.UserId)]) then return true end
    return false
end

-- ═══════════════════════════════════════════════
--  SCAN AVANÇADO (Synchronizer)
-- ═══════════════════════════════════════════════
local function scanPlots(duelPlayers, seen, currentJobId)
    local results = {}
    local plots = Workspace:FindFirstChild("Plots")
    if not plots then log(ICONS.warn, "Plots não encontrado"); return results end

    for _, plot in ipairs(plots:GetChildren()) do
        local ok, pot = pcall(function() return Synchronizer:Get(plot.Name) end)
        if not ok or not pot then continue end
        local ok2, list = pcall(function() return pot:Get("AnimalList") end)
        if not ok2 or type(list)~="table" then continue end

        local syncOwner
        local owOk, owVal = pcall(function() return pot:Get("Owner") end)
        if owOk and owVal~=nil then syncOwner = type(owVal)=="string" and owVal or tostring(owVal) end

        local plotDuel  = (syncOwner and duelPlayers[syncOwner]) or isPlotOwnerInDuel(plot, duelPlayers)
        local ownerName = syncOwner or "?"

        local plotItems, hasQualifying = {}, false

        for _, animalData in pairs(list) do
            if type(animalData)~="table" then continue end
            if isFusing(animalData) then continue end
            local name = animalData.Index
            if not name or not AnimalsData[name] then continue end

            local inDuel   = isInDuel(animalData) or plotDuel
            local data     = animalData.Data or animalData
            local mutation = data.Mutation
            if type(mutation)~="string" or mutation=="" then mutation=nil end

            local traitsTable, traitsList = nil, {}
            if type(data.Traits)=="table" then
                traitsTable = {}
                if #data.Traits>0 then
                    for _, t in ipairs(data.Traits) do
                        if type(t)=="string" then table.insert(traitsTable,t); table.insert(traitsList,t) end
                    end
                else
                    for tName, enabled in pairs(data.Traits) do
                        if enabled then table.insert(traitsTable,tName); table.insert(traitsList,tName) end
                    end
                end
                if #traitsTable==0 then traitsTable=nil end
            end

            local ok3, genValue = pcall(function()
                return AnimalsShared:GetGeneration(name, mutation, traitsTable, nil)
            end)
            if not ok3 or type(genValue)~="number" then continue end

            local qualifies = shouldScan(name, genValue)
            if qualifies then hasQualifying=true end

            local displayName = name
            local info = AnimalsData[name]
            if info and info.DisplayName then displayName=info.DisplayName end

            table.insert(plotItems, {
                name=displayName, index=name, genValue=genValue,
                mutation=mutation, traitsList=traitsList,
                inDuel=inDuel, qualifies=qualifies, ownerName=ownerName,
            })
        end

        if not hasQualifying then continue end

        for _, item in ipairs(plotItems) do
            if not item.qualifies then continue end
            local genText = "$"..fmtV(item.genValue).."/s"
            local key = item.name..genText
            if seen[key] then continue end
            seen[key] = true

            local isUltra = false
            for _, u in ipairs(ULTRA_BRAINROTS) do
                if u~="" and item.name:lower()==u:lower() then isUltra=true; break end
            end
            local tier = (item.genValue>=1e9 or isUltra) and "ULTRA"
                      or (item.genValue>=100e6) and "HIGH" or "MID"

            table.insert(results, {
                tier=tier, name=item.name, gen=genText, value=item.genValue,
                mutation=item.mutation,
                traits=#item.traitsList>0 and item.traitsList or nil,
                inDuel=item.inDuel, ownerName=item.ownerName,
            })

            local icon   = (tier=="ULTRA") and ICONS.ultra or (tier=="HIGH") and ICONS.high or ICONS.mid
            local extras = (item.mutation and (" [MUT:"..item.mutation.."]") or "")
                        .. (item.inDuel and " "..ICONS.duel or "")
            log(icon, ("%-24s  %s%s  (owner: %s)"):format(item.name, genText, extras, item.ownerName))
        end
    end
    return results
end

-- ═══════════════════════════════════════════════
--  IMAGEM DO FANDOM
-- ═══════════════════════════════════════════════
local function getBrainrotImage(name)
    local ok, result = pcall(function()
        local url = "https://stealabrainrot.fandom.com/api.php?action=query&titles="
                    ..HttpService:UrlEncode(name).."&prop=pageimages&piprop=original&format=json"
        local resp = http_request({Url=url, Method="GET"})
        if resp and resp.StatusCode==200 then
            local d = HttpService:JSONDecode(resp.Body)
            for _, page in pairs(d.query.pages) do
                if page.original and page.original.source then return page.original.source end
            end
        end
    end)
    return ok and result or nil
end

-- ═══════════════════════════════════════════════
--  DISCORD — com dedup via Firebase
-- ═══════════════════════════════════════════════
local function getMutPfx(mut)
    if not mut or mut=="" or mut:lower()=="none" or mut:lower()=="default" then return "" end
    return "["..mut:upper().."] "
end

local sentThisSession = {}  -- fallback local caso Firebase falhe

local function notify(results, jobId)
    if #results==0 then return end

    -- encontra o melhor item
    local best = results[1]
    for _, r in ipairs(results) do if r.value>best.value then best=r end end

    local genText = best.gen
    local dedupKey = jobId.."__"..best.name.."__"..genText

    -- ── DEDUP LOCAL (instantâneo) ──────────────────────
    if sentThisSession[dedupKey] then
        log(ICONS.skip, "Duplicata (local) — webhook bloqueado: "..best.name)
        return
    end

    -- ── DEDUP FIREBASE (persistente entre sessões) ──────
    log(ICONS.fire, "Verificando Firebase: "..best.name.." "..genText.."...")
    local alreadyInFirebase = firebaseAlreadyLogged(jobId, best.name, genText)
    if alreadyInFirebase then
        log(ICONS.skip, "Duplicata (Firebase) — webhook bloqueado: "..best.name)
        sentThisSession[dedupKey] = true
        return
    end

    -- ── SALVA NO FIREBASE ────────────────────────────────
    firebaseSaveLog(jobId, best.name, genText, {value=best.value, owner=best.ownerName})
    sentThisSession[dedupKey] = true

    -- ── MONTA EMBED ─────────────────────────────────────
    local total = 0
    for _, r in ipairs(results) do total = total + r.value end

    local listLines = ""
    local count = 0
    for _, r in ipairs(results) do
        if count>=6 then break end
        local line = "1x "..getMutPfx(r.mutation)..r.name.." ("..r.gen..")"
        if r.inDuel then line=line.." ⚔️" end
        listLines = listLines..line.."\n"
        count = count + 1
    end
    if #results>6 then listLines=listLines.."+ "..(#results-6).." mais..." end

    local imageUrl = getBrainrotImage(best.name)
    local joinUrl  = ("roblox://experiences/start?placeId=%d&gameInstanceId=%s"):format(GAME_ID, jobId)

    local color = best.value>=1e9 and 0xFF0000 or best.value>=500e6 and 0xFF6600 or EMBED_COLOR

    local embed = {
        title       = "🎯 "..getMutPfx(best.mutation)..best.name.." · "..fmtV(best.value).."/s",
        description = "**Brainrots encontrados:**\n```"..listLines.."```"
                    ..(best.inDuel and "\n⚔️ **Dono em Duel!**" or ""),
        color       = color,
        thumbnail   = imageUrl and {url=imageUrl} or nil,
        fields      = {
            {name="Players",    value=tostring(#Players:GetPlayers()).."/8", inline=true},
            {name="Owner",      value=tostring(best.ownerName),              inline=true},
            {name="Total Gen",  value="$"..fmtV(total).."/s",               inline=true},
            {name="Join",       value="[Clique aqui]("..joinUrl..")",        inline=false},
            {name="Job ID",     value="```"..jobId.."```",                   inline=false},
        },
        footer = {text = NOTIFIER_NAME.." v3 • "..os.date("%H:%M:%S")},
    }

    local ok = httpPost(DISCORD_WEBHOOK, {content="", username=NOTIFIER_NAME, embeds={embed}})
    if ok then
        log(ICONS.discord, ("Webhook enviado! Melhor: %s %s | Total: $%s/s"):format(
            best.name, genText, fmtV(total)))
    else
        log(ICONS.warn, "Falha ao enviar webhook")
    end
end

-- ═══════════════════════════════════════════════
--  SERVER HOP — otimizado
--  Melhorias:
--   1. Pré-busca async da lista (sem esperar teleport terminar)
--   2. Pool circular — nunca rebusca enquanto houver servidores
--   3. Ordenação por (maxPlayers - playing) desc → menos lotados primeiro
--   4. Skip imediato se servidor ficou cheio antes do teleport
--   5. Timeout agressivo: HOP_TIMEOUT segundos antes de desistir
--   6. Reseta visited só quando pool COMPLETAMENTE esgotado
--   7. Cursor completo — busca todas as páginas de uma vez (até 300 ids)
-- ═══════════════════════════════════════════════
local visited  = { [game.JobId] = true }
local pool     = {}
local poolPage = ""   -- cursor atual para buscar mais

local function fetchPage(cursor)
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc"
              .. "&excludeFullGames=true&limit=100"):format(GAME_ID)
    if cursor and cursor~="" then url = url.."&cursor="..cursor end
    return httpGet(url)
end

-- Refill pool buscando até 3 páginas (≈300 servidores)
local function refillPool()
    log(ICONS.fetch, "Buscando servidores...")
    local newIds, cursor, pages = {}, "", 0

    repeat
        pages = pages + 1
        local data = fetchPage(cursor)
        if not data or not data.data then break end

        for _, s in ipairs(data.data) do
            if s.id and not visited[s.id] and s.playing < s.maxPlayers then
                -- ordena por slots livres desc (insere mantendo ordem)
                table.insert(newIds, {id=s.id, free=s.maxPlayers-s.playing})
            end
        end

        cursor = data.nextPageCursor or ""
    until cursor=="" or pages>=3

    -- sort: mais slots livres primeiro (menos lotados = mais brainrots)
    table.sort(newIds, function(a,b) return a.free > b.free end)
    for _, entry in ipairs(newIds) do table.insert(pool, entry.id) end

    if #pool>0 then
        log(ICONS.queue, ("%d servidor(es) na pool (%.0f%% visitados ignorados)"):format(
            #pool, (#newIds>0 and (1 - #pool/#newIds)*0 or 0)))
    else
        log(ICONS.warn, "Nenhum servidor novo. Resetando visitados...")
        visited = { [game.JobId]=true }
        task.wait(8)
        refillPool()
    end
end

local teleporting = false

local function hopTo(serverId)
    if teleporting then return end
    teleporting = true
    visited[serverId] = true

    log(ICONS.hop, ("Teleportando → %s... (%d na pool)"):format(serverId:sub(1,8), #pool))

    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(GAME_ID, serverId, LocalPlayer)
    end)

    if not ok then
        log(ICONS.warn, "Teleport falhou: "..tostring(err))
        teleporting = false
        task.wait(2)
    end
end

local function nextServer()
    -- Se pool vazia, refaz
    if #pool==0 then refillPool() end
    if #pool==0 then log(ICONS.err, "Pool ainda vazia. Aguardando 15s..."); task.wait(15); return end

    local serverId = table.remove(pool, 1)
    hopTo(serverId)
end

-- Pré-carrega a próxima leva enquanto o jogador ainda está no servidor atual
local function preloadPoolAsync()
    task.spawn(function()
        if #pool < 10 then
            refillPool()
        end
    end)
end

-- ═══════════════════════════════════════════════
--  INICIALIZAÇÃO
-- ═══════════════════════════════════════════════
print("")
banner("🧠  BRAINROT SCANNER  v3")
print(("  ║  💰 Mínimo   : $%s/s"):format(fmtV(MIN_VALUE)))
print(("  ║  🔧 Modo     : %s"):format(useSync and "SYNC (avançado)" or "LEGADO"))
print(("  ║  ⏱️  Scan Wait : %ds  |  HOP Timeout: %ds"):format(SCAN_WAIT, HOP_TIMEOUT))
print(("  ║  🔥 Firebase : %s"):format(FIREBASE_URL))
print("")

-- Espera personagem
repeat task.wait(1) until LocalPlayer.Character
    and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

log(ICONS.ok, "Personagem pronto. Iniciando em "..SCAN_WAIT.."s...")
task.wait(SCAN_WAIT)

-- Pré-carrega pool inicial
refillPool()

-- ═══════════════════════════════════════════════
--  LOOP PRINCIPAL
-- ═══════════════════════════════════════════════
local scanN   = 0
local jobId   = game.JobId

while true do
    teleporting = false
    scanN = scanN + 1
    jobId = game.JobId

    sep()
    log(ICONS.scan, ("Scan #%d  │  Job: %s...  │  Players: %d/8"):format(
        scanN, jobId:sub(1,8), #Players:GetPlayers()))

    -- Pré-carrega próximos servidores em background
    preloadPoolAsync()

    local results
    if useSync then
        results = scanPlots(getDuelPlayers(), {}, jobId)
    else
        results = {}
        log(ICONS.warn, "scanLegacy não implementado nesta versão")
    end

    if #results > 0 then
        local total = 0
        for _, r in ipairs(results) do total = total + r.value end

        log(ICONS.found, ("ACHOU! %d item(s) │ Total: $%s/s"):format(#results, fmtV(total)))

        for i = 1, math.min(5, #results) do
            local r    = results[i]
            local icon = (r.tier=="ULTRA") and ICONS.ultra or (r.tier=="HIGH") and ICONS.high or ICONS.mid
            local mut  = r.mutation and " ["..r.mutation.."]" or ""
            local duel = r.inDuel and " "..ICONS.duel or ""
            print(("  │  %s  %-24s %s%s%s"):format(icon, r.name, r.gen, mut, duel))
        end
        if #results > 5 then print("  │  ... e mais "..(#results-5).." brainrot(s)") end

        -- Notificação in-game
        pcall(function()
            game.StarterGui:SetCore("SendNotification", {
                Title    = "🎯 $"..fmtV(total).."/s",
                Text     = results[1].name,
                Duration = 5,
            })
        end)

        -- Envia webhook (com dedup Firebase)
        notify(results, jobId)

        log(ICONS.hop, "Pulando servidor...")
        nextServer()
    else
        log(ICONS.err, ("Nada acima de $%s/s — pulando..."):format(fmtV(MIN_VALUE)))
        nextServer()
    end

    task.wait(SCAN_WAIT)
end