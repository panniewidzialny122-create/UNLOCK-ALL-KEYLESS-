repeat task.wait() until game:IsLoaded()
assert(hookmetamethod, "[ascida]: Your executor doesn't support this.")

-- REMOVED: AnalyticsPipelineController hooks that caused freezing

local players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local httpService = game:GetService("HttpService")
local queueteleport = queue_on_teleport or queueteleport or function(...) return ... end
local localPlayer = players.LocalPlayer

local function waitForCharacter()
    if localPlayer.Character then return end
    local success = localPlayer.CharacterAdded:Wait(10)  -- timeout after 10 seconds
    if not success then warn("Character did not load within 10 seconds") end
    task.wait(2)
end
waitForCharacter()

local playerScripts
local attempts = 0
repeat
    task.wait(1)
    playerScripts = localPlayer:FindFirstChild("PlayerScripts")
    attempts = attempts + 1
    if attempts > 20 then return warn("PlayerScripts not found") end
until playerScripts

local controllers
attempts = 0
repeat
    task.wait(1)
    controllers = playerScripts:FindFirstChild("Controllers")
    attempts = attempts + 1
    if attempts > 20 then return warn("Controllers not found") end
until controllers

local modules
attempts = 0
repeat
    task.wait(1)
    modules = replicatedStorage:FindFirstChild("Modules")
    attempts = attempts + 1
    if attempts > 20 then return warn("Modules not found") end
until modules

local function waitForModule(parent, name, timeout)
    local timeElapsed = 0
    while not parent:FindFirstChild(name) and timeElapsed < timeout do
        task.wait(0.5)
        timeElapsed = timeElapsed + 0.5
    end
    return parent:FindFirstChild(name)
end

local cosmeticLib = waitForModule(modules, "CosmeticLibrary", 10)
local itemLib = waitForModule(modules, "ItemLibrary", 10)
local dataCtrl = waitForModule(controllers, "PlayerDataController", 10)
local dataUtility = waitForModule(modules, "PlayerDataUtility", 10)

if not cosmeticLib or not itemLib or not dataCtrl then 
    return warn("Required modules missing")
end

local EnumLibrary, CosmeticLibrary, ItemLibrary, DataController, DataUtility
local loadSuccess = pcall(function()
    CosmeticLibrary = require(cosmeticLib)
    ItemLibrary = require(itemLib)
    DataController = require(dataCtrl)
    DataUtility = require(dataUtility)
    local enumLib = modules:FindFirstChild("EnumLibrary")
    if enumLib then
        EnumLibrary = require(enumLib)
        if EnumLibrary and EnumLibrary.WaitForEnumBuilder then
            task.spawn(function() pcall(function() EnumLibrary:WaitForEnumBuilder() end) end)
        end
    end
end)

local function GetAllWeaponMapsTo(bool)
    local weapons = {}
    if ItemLibrary and ItemLibrary.Items then
        for name, _ in pairs(ItemLibrary.Items) do
            if not name:find("MISSING_") then
                weapons[name] = bool
            end
        end
    end
    return weapons
end

DataController.OwnsAllWeapons = function()
    return true
end
DataController.GetUnlockedWeapons = function()
    return GetAllWeaponMapsTo(true)
end

if not loadSuccess or not CosmeticLibrary or not ItemLibrary or not DataController then 
    return warn("Failed to require modules")
end

local equipped = {}
local favorites = {}
local constructingWeapon, viewingProfile, lastUsedWeapon

local function cloneCosmetic(name, cosmeticType, options)
    if not CosmeticLibrary or not CosmeticLibrary.Cosmetics then return nil end
    local base = CosmeticLibrary.Cosmetics[name]
    if not base then return nil end
    local data = {}
    for key, value in pairs(base) do data[key] = value end
    data.Name = name
    data.Type = data.Type or cosmeticType
    data.Seed = math.random(1, 1000000)
    if EnumLibrary then
        pcall(function()
            local enumId = EnumLibrary:ToEnum(name)
            if enumId then data.Enum, data.ObjectID = enumId, enumId end
        end)
    end
    if options then
        if options.inverted then data.Inverted = true end
        if options.favoritesOnly then data.OnlyUseFavorites = true end
    end
    return data
end

local saveFile = "unlockall/config.json"
local function saveConfig()
    if not writefile then return end
    task.spawn(function()
        pcall(function()
            local config = {equipped = {}, favorites = favorites}
            for weapon, cosmetics in pairs(equipped) do
                config.equipped[weapon] = {}
                for cosmeticType, cosmeticData in pairs(cosmetics) do
                    if cosmeticData and cosmeticData.Name then
                        config.equipped[weapon][cosmeticType] = {name = cosmeticData.Name, seed = cosmeticData.Seed, inverted = cosmeticData.Inverted}
                    end
                end
            end
            if not isfolder("unlockall") then makefolder("unlockall") end
            writefile(saveFile, httpService:JSONEncode(config))
        end)
    end)
end

local function loadConfig()
    if not readfile or not isfile or not isfile(saveFile) then return end
    pcall(function()
        local config = httpService:JSONDecode(readfile(saveFile))
        if config.equipped then
            for weapon, cosmetics in pairs(config.equipped) do
                equipped[weapon] = {}
                for cosmeticType, cosmeticData in pairs(cosmetics) do
                    local cloned = cloneCosmetic(cosmeticData.name, cosmeticType, {inverted = cosmeticData.inverted})
                    if cloned then 
                        cloned.Seed = cosmeticData.seed 
                        equipped[weapon][cosmeticType] = cloned 
                    end
                end
            end
        end
        favorites = config.favorites or {}
    end)
end

CosmeticLibrary.OwnsCosmeticNormally = function() return true end
CosmeticLibrary.OwnsCosmeticUniversally = function() return true end
CosmeticLibrary.OwnsCosmeticForSomething = function() return true end
CosmeticLibrary.OwnsCosmeticForWeapon = function() return true end

local originalOwnsCosmetic = CosmeticLibrary.OwnsCosmetic
CosmeticLibrary.OwnsCosmetic = function(self, inventory, name, weapon)
    if name and name:find("MISSING_") then return originalOwnsCosmetic(self, inventory, name, weapon) end
    return true
end

local originalGet = DataController.Get
DataController.Get = function(self, key)
    local data = originalGet(self, key)
    if key == "CosmeticInventory" then 
        return setmetatable({}, {__index = function() return true end}) 
    end
    if key == "FavoritedCosmetics" then
        local result = {}
        if data then 
            for k, v in pairs(data) do result[k] = v end 
        end
        for weapon, favs in pairs(favorites) do
            result[weapon] = result[weapon] or {}
            for name, isFav in pairs(favs) do result[weapon][name] = isFav end
        end
        return result
    end
    return data
end

local originalGetWeaponData = DataController.GetWeaponData
DataController.GetWeaponData = function(self, weaponName)
    local data = {
        Unlocked = true,
        Level = 100,
        XP = 99999
    }
    local originalData = originalGetWeaponData(self, weaponName)
    if originalData then
        for k, v in pairs(originalData) do
            data[k] = v
        end
    end
    if equipped and equipped[weaponName] then
        for cosmeticType, cosmeticData in pairs(equipped[weaponName]) do
            data[cosmeticType] = cosmeticData
        end
    end
    return data
end

local FighterController
task.spawn(function()
    local fc = controllers:FindFirstChild("FighterController")
    if fc then pcall(function() FighterController = require(fc) end) end
end)

task.spawn(function()
    task.wait(1)
    if not hookmetamethod then return end
    local remotes = replicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end
    local dataRemotes = remotes:FindFirstChild("Data")
    local replicationRemotes = remotes:FindFirstChild("Replication")
    local equipRemote = dataRemotes and dataRemotes:FindFirstChild("EquipCosmetic")
    local favoriteRemote = dataRemotes and dataRemotes:FindFirstChild("FavoriteCosmetic")
    local fighterRemotes = replicationRemotes and replicationRemotes:FindFirstChild("Fighter")
    local useItemRemote = fighterRemotes and fighterRemotes:FindFirstChild("UseItem")
    if not equipRemote then return end

    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() ~= "FireServer" then return oldNamecall(self, ...) end
        local args = {...}
        if useItemRemote and self == useItemRemote and FighterController then
            task.spawn(function()
                pcall(function()
                    local fighter = FighterController:GetFighter(localPlayer)
                    if fighter and fighter.Items then
                        for _, item in pairs(fighter.Items) do
                            if item:Get("ObjectID") == args[1] then
                                lastUsedWeapon = item.Name
                                break
                            end
                        end
                    end
                end)
            end)
        end
        if self == equipRemote then
            local weaponName, cosmeticType, cosmeticName = args[1], args[2], args[3]
            local options = args[4] or {}
            equipped[weaponName] = equipped[weaponName] or {}
            if not cosmeticName or cosmeticName == "None" or cosmeticName == "" then
                equipped[weaponName][cosmeticType] = nil
                if not next(equipped[weaponName]) then equipped[weaponName] = nil end
            else
                local cloned = cloneCosmetic(cosmeticName, cosmeticType, {inverted = options.IsInverted, favoritesOnly = options.OnlyUseFavorites})
                if cloned then equipped[weaponName][cosmeticType] = cloned end
            end
            task.spawn(function()
                task.wait(0.1)
                pcall(function() DataController.CurrentData:Replicate("WeaponInventory") end)
                saveConfig()
            end)
            return
        end
        if favoriteRemote and self == favoriteRemote then
            favorites[args[1]] = favorites[args[1]] or {}
            favorites[args[1]][args[2]] = args[3] or nil
            saveConfig()
            return
        end
        return oldNamecall(self, ...)
    end)
end)

local originalGetViewModelImage = ItemLibrary.GetViewModelImageFromWeaponData
ItemLibrary.GetViewModelImageFromWeaponData = function(self, weaponData, highRes)
    if not weaponData then return originalGetViewModelImage(self, weaponData, highRes) end
    local weaponName = weaponData.Name
    local shouldShowSkin = (weaponData.Skin and equipped[weaponName] and weaponData.Skin == equipped[weaponName].Skin) or (viewingProfile == localPlayer and equipped[weaponName] and equipped[weaponName].Skin)
    if shouldShowSkin and equipped[weaponName] and equipped[weaponName].Skin then
        local skinInfo = self.ViewModels[equipped[weaponName].Skin.Name]
        if skinInfo then return skinInfo[highRes and "ImageHighResolution" or "Image"] or skinInfo.Image end
    end
    return originalGetViewModelImage(self, weaponData, highRes)
end

task.spawn(function()
    task.wait(3)
    pcall(function()
        local clientItemPath = playerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem
        local ClientItem = require(clientItemPath)
        if ClientItem._CreateViewModel then
            local orig = ClientItem._CreateViewModel
            ClientItem._CreateViewModel = function(self, viewmodelRef)
                local weaponName = self.Name
                local weaponPlayer = self.ClientFighter and self.ClientFighter.Player
                constructingWeapon = (weaponPlayer == localPlayer) and weaponName or nil
                if weaponPlayer == localPlayer and equipped[weaponName] and equipped[weaponName].Skin and viewmodelRef then
                    pcall(function()
                        local dataKey, skinKey, nameKey = self:ToEnum("Data"), self:ToEnum("Skin"), self:ToEnum("Name")
                        if viewmodelRef[dataKey] then
                            viewmodelRef[dataKey][skinKey] = equipped[weaponName].Skin
                            viewmodelRef[dataKey][nameKey] = equipped[weaponName].Skin.Name
                        elseif viewmodelRef.Data then
                            viewmodelRef.Data.Skin = equipped[weaponName].Skin
                            viewmodelRef.Data.Name = equipped[weaponName].Skin.Name
                        end
                    end)
                end
                local result = orig(self, viewmodelRef)
                constructingWeapon = nil
                return result
            end
        end
    end)
    pcall(function()
        local viewModelModule = playerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem:FindFirstChild("ClientViewModel")
        if viewModelModule then
            local ClientViewModel = require(viewModelModule)
            if ClientViewModel.GetWrap then
                local orig = ClientViewModel.GetWrap
                ClientViewModel.GetWrap = function(self)
                    local weaponName = self.ClientItem and self.ClientItem.Name
                    local weaponPlayer = self.ClientItem and self.ClientItem.ClientFighter and self.ClientItem.ClientFighter.Player
                    if weaponName and weaponPlayer == localPlayer and equipped[weaponName] and equipped[weaponName].Wrap then
                        return equipped[weaponName].Wrap
                    end
                    return orig(self)
                end
            end
            local origNew = ClientViewModel.new
            ClientViewModel.new = function(replicatedData, clientItem)
                local weaponPlayer = clientItem.ClientFighter and clientItem.ClientFighter.Player
                local weaponName = constructingWeapon or clientItem.Name
                if weaponPlayer == localPlayer and equipped[weaponName] then
                    pcall(function()
                        local ReplicatedClass = require(replicatedStorage.Modules.ReplicatedClass)
                        local dataKey = ReplicatedClass:ToEnum("Data")
                        replicatedData[dataKey] = replicatedData[dataKey] or {}
                        local cosmetics = equipped[weaponName]
                        if cosmetics.Skin then replicatedData[dataKey][ReplicatedClass:ToEnum("Skin")] = cosmetics.Skin end
                        if cosmetics.Wrap then replicatedData[dataKey][ReplicatedClass:ToEnum("Wrap")] = cosmetics.Wrap end
                        if cosmetics.Charm then replicatedData[dataKey][ReplicatedClass:ToEnum("Charm")] = cosmetics.Charm end
                    end)
                end
                local result = origNew(replicatedData, clientItem)
                if weaponPlayer == localPlayer and equipped[weaponName] and equipped[weaponName].Wrap and result._UpdateWrap then
                    task.spawn(function()
                        result:_UpdateWrap()
                        task.wait(0.1)
                        if not result._destroyed then result:_UpdateWrap() end
                    end)
                end
                return result
            end
        end
    end)
    pcall(function()
        local ViewProfile = require(playerScripts.Modules.Pages.ViewProfile)
        if ViewProfile and ViewProfile.Fetch then
            local orig = ViewProfile.Fetch
            ViewProfile.Fetch = function(self, targetPlayer)
                viewingProfile = targetPlayer
                return orig(self, targetPlayer)
            end
        end
    end)
    pcall(function()
        local ClientEntity = require(playerScripts.Modules.ClientReplicatedClasses.ClientEntity)
        if ClientEntity.ReplicateFromServer then
            local orig = ClientEntity.ReplicateFromServer
            ClientEntity.ReplicateFromServer = function(self, action, ...)
                if action == "FinisherEffect" then
                    local args = {...}
                    local killerName = args[3]
                    local decodedKiller = killerName
                    if type(killerName) == "userdata" and EnumLibrary and EnumLibrary.FromEnum then
                        pcall(function() decodedKiller = EnumLibrary:FromEnum(killerName) end)
                    end
                    local isOurKill = tostring(decodedKiller) == localPlayer.Name or tostring(decodedKiller):lower() == localPlayer.Name:lower()
                    if isOurKill and lastUsedWeapon and equipped[lastUsedWeapon] and equipped[lastUsedWeapon].Finisher then
                        local finisherData = equipped[lastUsedWeapon].Finisher
                        local finisherEnum = finisherData.Enum
                        if not finisherEnum and EnumLibrary then
                            pcall(function() finisherEnum = EnumLibrary:ToEnum(finisherData.Name) end)
                        end
                        if finisherEnum then
                            args[1] = finisherEnum
                            return orig(self, action, unpack(args))
                        end
                    end
                end
                return orig(self, action, ...)
            end
        end
    end)
end)

loadConfig()
