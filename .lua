local shared = odh_shared_plugins
task.spawn(function()
    shared.load_from_github_url("/aux0on/CrashHandler/refs/heads/main/Prevention.lua")
end)

if shared.game_name ~= "Murder Mystery 2" then return end
local afp = shared.CreateTab("Autofarm+", "/aux0on/AFPIcon/refs/heads/main/Untitled163_20260919023714")
local combat_section = afp:AddSection("Autofarm+")

-- 🚨 OPTIMIZED WHITELIST (Dictionary for O(1) lookups) 🚨
local whitelist = {}

local Players = game:GetService("Players")
while not Players.LocalPlayer do task.wait() end
local player = Players.LocalPlayer

local trueAntiVoidConnection
local originalDestroyHeight = workspace.FallenPartsDestroyHeight

local function setupAntiVoid()
    if not player then return end
    if trueAntiVoidConnection then
        trueAntiVoidConnection:Disconnect()
        trueAntiVoidConnection = nil
    end
    workspace.FallenPartsDestroyHeight = 0/0
    trueAntiVoidConnection = player.CharacterAdded:Connect(function(char)
        task.wait(0.1)
        workspace.FallenPartsDestroyHeight = 0/0
    end)
end

local vU = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- 🚨 MAID CLASS FOR CLEANUP 🚨
local Maid = {}
Maid.__index = Maid

function Maid.new()
    return setmetatable({_tasks = {}, _destroyed = false}, Maid)
end

function Maid:GiveTask(task)
    if self._destroyed then self:_cleanupTask(task) return end
    table.insert(self._tasks, task)
    return task
end

function Maid:_cleanupTask(task)
    local t = typeof(task)
    if t == "RBXScriptConnection" then task:Disconnect()
    elseif t == "Instance" then task:Destroy()
    elseif t == "function" then task()
    elseif t == "table" and type(task.Destroy) == "function" then task:Destroy()
    end
end

function Maid:DoCleaning()
    if self._destroyed then return end
    self._destroyed = true
    for _, task in ipairs(self._tasks) do self:_cleanupTask(task) end
    self._tasks = {}
end

function Maid:Destroy() self:DoCleaning() end

local RootMaid = Maid.new()

local noclipEnabled = false

local function applyNoclipNow()
    local character = player.Character
    if character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = false end
        end
    end
end

local function restoreCollision()
    local character = player.Character
    if character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then part.CanCollide = true end
        end
    end
end

local function setNoclip(state)
    noclipEnabled = state
    if not state then restoreCollision() else applyNoclipNow() end
end

RootMaid:GiveTask(RunService.Stepped:Connect(function()
    if not noclipEnabled then return end
    local character = player.Character
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.CanCollide then
            part.CanCollide = false
        end
    end
end))

local roleCache = { data = nil, timestamp = 0, TTL = 0.8 }

local function getCachedRoleData()
    local now = tick()
    if roleCache.data and (now - roleCache.timestamp) < roleCache.TTL then
        return roleCache.data
    end
    local ok, result = pcall(function()
        local remote = ReplicatedStorage:FindFirstChild("GetPlayerData", true)
        if remote and remote:IsA("RemoteFunction") then return remote:InvokeServer() end
    end)
    if ok and result then
        roleCache.data = result
        roleCache.timestamp = now
        return result
    end
    roleCache.timestamp = now
    return roleCache.data
end

local function getMyRole()
    local roleData = getCachedRoleData()
    if not roleData then return nil end
    local data = roleData[player.Name]
    if data then return data.Role end
    return nil
end

local autoKillAllEnabled = false
local autoShootMurdEnabled = false
local autoResetMurdEnabled = false
local autoResetSheriffEnabled = false
local resetAllEnabled = false
local noRenderEnabled = false
local autoGGEnabled = false

local afkConnection
local isResetting = false

local sheriffFlingMaid = nil
local resetAllMaid = nil
local autoGGMaid = Maid.new()
RootMaid:GiveTask(autoGGMaid)

local resetAllState = "waiting"
local hasFlingedMurdererThisLife = false
local hasExecutedThisLife = false

local blackScreenGui = nil
local blackScreenFrame = nil
local shootLoopThread = nil

local function CreateBlackScreen()
    if blackScreenGui then return end
    blackScreenGui = Instance.new("ScreenGui")
    blackScreenGui.Name = "NoRenderBackground"
    blackScreenGui.DisplayOrder = -99999
    blackScreenGui.IgnoreGuiInset = true
    blackScreenGui.ResetOnSpawn = false
    blackScreenFrame = Instance.new("Frame")
    blackScreenFrame.Size = UDim2.new(1, 0, 1, 0)
    blackScreenFrame.BackgroundColor3 = Color3.fromRGB(0,0,0)
    blackScreenFrame.BorderSizePixel = 0
    blackScreenFrame.Parent = blackScreenGui
    blackScreenGui.Parent = player:WaitForChild("PlayerGui")
end

local function RemoveBlackScreen()
    if blackScreenGui then
        blackScreenGui:Destroy()
        blackScreenGui = nil
        blackScreenFrame = nil
    end
end

local function ToggleNoRender()
    noRenderEnabled = not noRenderEnabled
    RunService:Set3dRenderingEnabled(not noRenderEnabled)
    if noRenderEnabled then CreateBlackScreen() else RemoveBlackScreen() end
end

local function SetNoRenderState(state)
    if state == noRenderEnabled then return end
    ToggleNoRender()
end

local function CleanupNoRender()
    if noRenderEnabled then
        RunService:Set3dRenderingEnabled(true)
        RemoveBlackScreen()
        noRenderEnabled = false
    end
end

local function getRole()
    local bp = player:FindFirstChild("Backpack")
    local char = player.Character
    if bp and (bp:FindFirstChild("Knife") or (char and char:FindFirstChild("Knife"))) then
        return "Murderer"
    elseif bp and (bp:FindFirstChild("Gun") or (char and char:FindFirstChild("Gun"))) then
        return "Sheriff"
    end
    return "Innocent"
end

local function isWhitelisted(p)
    return whitelist[p.UserId] == true
end

local function getMurd()
    local roleData = getCachedRoleData()
    if roleData then
        for playerName, data in pairs(roleData) do
            if data.Role == "Murderer" and not data.Killed and not data.Dead then
                local p = Players:FindFirstChild(playerName)
                if p and p ~= player and not isWhitelisted(p) then return p end
            end
        end
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and not isWhitelisted(plr) then
            local bp = plr:FindFirstChild("Backpack")
            local char = plr.Character
            if (bp and bp:FindFirstChild("Knife")) or (char and char:FindFirstChild("Knife")) then
                return plr
            end
        end
    end
    return nil
end

local function getSheriff()
    local roleData = getCachedRoleData()
    if roleData then
        for playerName, data in pairs(roleData) do
            if data.Role == "Sheriff" and not data.Killed and not data.Dead then
                local p = Players:FindFirstChild(playerName)
                if p and p ~= player and not isWhitelisted(p) then return p end
            end
        end
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= player and not isWhitelisted(plr) then
            local bp = plr:FindFirstChild("Backpack")
            local char = plr.Character
            if (bp and bp:FindFirstChild("Gun")) or (char and char:FindFirstChild("Gun")) then
                return plr
            end
        end
    end
    return nil
end

local function getGun()
    local char = player.Character
    if char and char:FindFirstChild("Gun") then return char.Gun end
    local bp = player:FindFirstChild("Backpack")
    if bp and bp:FindFirstChild("Gun") then return bp.Gun end
end

local function hasGun()
    local char = player.Character
    local bp = player:FindFirstChild("Backpack")
    return (char and char:FindFirstChild("Gun")) or (bp and bp:FindFirstChild("Gun"))
end

local function getKnife()
    local char = player.Character
    if char and char:FindFirstChild("Knife") then return char.Knife end
    local bp = player:FindFirstChild("Backpack")
    if bp and bp:FindFirstChild("Knife") then return bp.Knife end
end

local function hasKnife()
    return getKnife() ~= nil
end

local function touch(a, b)
    pcall(function()
        firetouchinterest(a, b, 0)
        firetouchinterest(a, b, 1)
    end)
end

local function fullyRestoreCharacter(character, savedData)
    if not character or not savedData then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then return end
    humanoid.PlatformStand = false
    for _, track in ipairs(humanoid:GetPlayingAnimationTracks()) do track:Stop() end
    rootPart.AssemblyLinearVelocity = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero
    rootPart.CFrame = savedData.cframe
    pcall(function()
        sethiddenproperty(rootPart, "PhysicsRepRootRef", nil)
        sethiddenproperty(rootPart, "PhysicsRepRootPart", nil)
    end)
    humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then part.CanCollide = true end
    end
end

local function resetPlayer(TargetPlayer, attempts)
    if not TargetPlayer or not TargetPlayer.Parent then return end
    local maxAttempts = attempts or 3
    for currentAttempt = 1, maxAttempts do
        if not TargetPlayer.Parent then break end
        local tChar = TargetPlayer.Character
        local tHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
        if tHum and tHum.Health <= 0 then break end

        local Character = player.Character
        if not Character then break end
        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        local RootPart = Humanoid and Humanoid.RootPart
        if not (Character and Humanoid and RootPart and tChar) then break end

        local TRootPart = tChar:FindFirstChild("HumanoidRootPart")
        local THead = tChar:FindFirstChild("Head")
        if not TRootPart then break end

        isResetting = true
        local savedData = { cframe = RootPart.CFrame }
        Humanoid.PlatformStand = true

        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.Velocity = Vector3.new(0, -50000, 0)
        bv.Parent = RootPart

        local bg = Instance.new("BodyGyro")
        bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        bg.P = 1000000
        bg.Parent = RootPart

        Workspace.FallenPartsDestroyHeight = 0/0
        local startTime = tick()
        local completed = false
        local conn
        conn = RunService.Heartbeat:Connect(function()
            if tick() - startTime > 1.0 or not TargetPlayer.Character or not TRootPart.Parent then
                Workspace.FallenPartsDestroyHeight = originalDestroyHeight
                bv:Destroy()
                bg:Destroy()
                pcall(function()
                    sethiddenproperty(RootPart, "PhysicsRepRootRef", nil)
                    sethiddenproperty(RootPart, "PhysicsRepRootPart", nil)
                end)
                fullyRestoreCharacter(Character, savedData)
                if conn then conn:Disconnect() end
                completed = true
                return
            end
            if TRootPart and TRootPart.Parent and Character and Character.Parent then
                local headPos = THead and THead.Position or (TRootPart.Position + Vector3.new(0, 2.5, 0))
                RootPart.CFrame = CFrame.new(headPos) * CFrame.Angles(math.pi / 2, 0, 0)
                RootPart.AssemblyLinearVelocity = Vector3.new(0, -50000, 0)
                RootPart.AssemblyAngularVelocity = Vector3.new(7500, 7500, 7500)
                for i = 1, 5 do
                    touch(RootPart, TRootPart)
                    if THead then touch(RootPart, THead) end
                end
                pcall(function()
                    sethiddenproperty(RootPart, "PhysicsRepRootRef", InstanceHandle.new(TRootPart))
                    sethiddenproperty(RootPart, "PhysicsRepRootPart", TRootPart)
                end)
            end
        end)

        while not completed and TargetPlayer.Parent do task.wait(0.05) end
        if not completed then
            Workspace.FallenPartsDestroyHeight = originalDestroyHeight
            if bv.Parent then bv:Destroy() end
            if bg.Parent then bg:Destroy() end
            pcall(function()
                sethiddenproperty(RootPart, "PhysicsRepRootRef", nil)
                sethiddenproperty(RootPart, "PhysicsRepRootPart", nil)
            end)
            fullyRestoreCharacter(Character, savedData)
            if conn then conn:Disconnect() end
        end
        isResetting = false
        task.wait(0.15)
        local postHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
        if not postHum or postHum.Health <= 0 then break end
    end
end

local function killAll()
    local knife = getKnife()
    if not knife then return end
    local events = knife:FindFirstChild("Events")
    if not events then return end
    local handleTouched = events:FindFirstChild("HandleTouched")
    if not handleTouched then return end

    local targets = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character and not isWhitelisted(p) then
            local upperTorso = p.Character:FindFirstChild("UpperTorso")
            if upperTorso then table.insert(targets, upperTorso) end
        end
    end
    for _, upperTorso in ipairs(targets) do
        handleTouched:FireServer(upperTorso)
    end
end

local function killAllExceptOne()
    local knife = getKnife()
    if not knife then return false end
    local events = knife:FindFirstChild("Events")
    if not events then return false end
    local handleTouched = events:FindFirstChild("HandleTouched")
    if not handleTouched then return false end

    local allPlayers = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= player and p.Character and not isWhitelisted(p) then
            local upperTorso = p.Character:FindFirstChild("UpperTorso")
            if upperTorso then table.insert(allPlayers, upperTorso) end
        end
    end
    if #allPlayers < 1 then return false end

    local survivor = allPlayers[math.random(1, #allPlayers)]
    for _, upperTorso in ipairs(allPlayers) do
        if upperTorso ~= survivor then
            handleTouched:FireServer(upperTorso)
            task.wait(0.05)
        end
    end
    return true
end

local function equipGun()
    local gun = getGun()
    if not gun then return false end
    if gun.Parent == player.Character then return true end
    if gun.Parent == player.Backpack then
        local char = player.Character
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:EquipTool(gun)
            for _ = 1, 10 do
                task.wait(0.1)
                if gun.Parent == char then return true end
            end
        end
    end
    return false
end

local function unequipGun()
    local char = player.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    local gun = getGun()
    if gun and gun.Parent == char then
        local backpack = player:FindFirstChild("Backpack")
        if backpack then gun.Parent = backpack end
    end
end

-- 🚨 NEW INSTANT SHOOT LOGIC 🚨
local function shootMurd()
    if not equipGun() then return end
    task.wait(0.1)
    
    local gun = getGun()
    if not gun then return end
    
    local handle = gun:FindFirstChild("Handle")
    local shootRemote = gun:FindFirstChild("Shoot") or gun:FindFirstChild("FireGun") or gun:FindFirstChild("Events") and gun.Events:FindFirstChild("Shoot")
    
    if handle and shootRemote then
        local startCF = handle.CFrame
        local endCF = CFrame.new(handle.Position + handle.CFrame.LookVector * 100)
        pcall(function()
            shootRemote:FireServer(startCF, endCF)
        end)
    end
end

local function startShootingMurderer()
    if shootLoopThread then
        task.cancel(shootLoopThread)
        shootLoopThread = nil
    end
    shootLoopThread = task.spawn(function()
        while true do
            if not hasGun() then break end
            local murd = getMurd()
            if not murd or not murd.Character then break end
            local humanoid = murd.Character:FindFirstChildOfClass("Humanoid")
            if not humanoid or humanoid.Health <= 0 then break end
            shootMurd()
            task.wait(0.5)
        end
        unequipGun()
        shootLoopThread = nil
    end)
end

local function executeResetAll()
    local role = getMyRole() or getRole()
    if role == "Murderer" or hasKnife() then
        if not hasExecutedThisLife then
            hasExecutedThisLife = true
            task.wait(1.0)
            killAllExceptOne()
        end
    else
        local murderer = getMurd()
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= player and p ~= murderer and not isWhitelisted(p) then
                local tChar = p.Character
                local tHum = tChar and tChar:FindFirstChildOfClass("Humanoid")
                if tHum and tHum.Health > 0 then
                    resetPlayer(p, 1)
                    task.wait(0.2)
                end
            end
        end
    end
end

local function startResetAllMonitor()
    if resetAllMaid then resetAllMaid:Destroy() end
    resetAllMaid = Maid.new()
    resetAllState = "waiting"
    resetAllMaid:GiveTask(task.spawn(function()
        while resetAllEnabled do
            setNoclip(true)
            roleCache.timestamp = 0
            local role = getMyRole() or getRole()
            if resetAllState == "waiting" then
                local shouldRun = false
                if role == "Murderer" or hasKnife() then
                    if not hasExecutedThisLife then shouldRun = true end
                else
                    if getMurd() then shouldRun = true end
                end
                if shouldRun then
                    executeResetAll()
                    resetAllState = "done"
                end
            elseif resetAllState == "done" then
                if role == "Murderer" or hasKnife() then
                    if not hasKnife() then resetAllState = "waiting" end
                else
                    if not getMurd() then resetAllState = "waiting" end
                end
            end
            task.wait(0.1)
        end
    end))
end

local function stopResetAllMonitor()
    if resetAllMaid then resetAllMaid:Destroy() resetAllMaid = nil end
    resetAllState = "waiting"
end

local function updateNoclip()
    setNoclip(autoResetSheriffEnabled or autoResetMurdEnabled or resetAllEnabled)
end

local function toggleResetAll(enabled)
    resetAllEnabled = enabled
    if enabled then startResetAllMonitor() else stopResetAllMonitor() end
    updateNoclip()
end

local function startSheriffFling()
    if sheriffFlingMaid then sheriffFlingMaid:Destroy() end
    sheriffFlingMaid = Maid.new()
    sheriffFlingMaid:GiveTask(task.spawn(function()
        while autoResetSheriffEnabled do
            setNoclip(true)
            local role = getMyRole() or getRole()
            if role ~= "Murderer" then
                local target = getSheriff()
                if target and target ~= player then
                    resetPlayer(target, 3)
                    while getSheriff() and autoResetSheriffEnabled and ((getMyRole() or getRole()) ~= "Murderer") do task.wait(0.5) end
                end
            end
            task.wait(0.3)
        end
        updateNoclip()
    end))
end

local function stopSheriffFling()
    if sheriffFlingMaid then sheriffFlingMaid:Destroy() sheriffFlingMaid = nil end
    updateNoclip()
end

-- 🚨 FIXED AUTO RESET MURDERER (Waits for murderer) 🚨
local function flingMurdererOnRespawn()
    if not autoResetMurdEnabled or hasFlingedMurdererThisLife then return end
    local role = getMyRole() or getRole()
    if role == "Murderer" then return end
    if autoShootMurdEnabled and hasGun() then return end

    -- Poll for up to 10 seconds to wait for server data to register the murderer
    local timeout = tick() + 10
    while tick() < timeout and autoResetMurdEnabled and not hasFlingedMurdererThisLife do
        if hasKnife() or (autoShootMurdEnabled and hasGun()) then break end
        local murd = getMurd()
        if murd and murd.Character then
            local hum = murd.Character:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                resetPlayer(murd, 3)
                hasFlingedMurdererThisLife = true
                break
            end
        end
        task.wait(0.5)
    end
end

-- 🚨 OPTIMIZED COIN AURA (No more FPS drops) 🚨
local auraData = { enabled = false, thread = nil, radius = 8 }
local cachedContainers = {}
local lastContainerScan = 0

local function getOptimizedCoinParts()
    if tick() - lastContainerScan > 1 then
        lastContainerScan = tick()
        cachedContainers = {}
        for _, map in ipairs(Workspace:GetChildren()) do
            local container = map:FindFirstChild("CoinContainer")
            if container then table.insert(cachedContainers, container) end
        end
    end
    local parts = {}
    for _, container in ipairs(cachedContainers) do
        if container.Parent then
            for _, descendant in ipairs(container:GetDescendants()) do
                if descendant:IsA("BasePart") and descendant:FindFirstChild("TouchInterest") then
                    table.insert(parts, descendant)
                end
            end
        end
    end
    return parts
end

local function startAura()
    if auraData.enabled then return end
    auraData.enabled = true
    auraData.thread = task.spawn(function()
        while auraData.enabled do
            task.wait(0.05) -- 20 times a sec instead of 60
            local character = player.Character
            local rootPart = character and character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                local rootPos = rootPart.Position
                for _, part in ipairs(getOptimizedCoinParts()) do
                    if (rootPos - part.Position).Magnitude <= auraData.radius then
                        touch(rootPart, part)
                    end
                end
            end
        end
    end)
end

local function stopAura()
    auraData.enabled = false
    if auraData.thread then
        task.cancel(auraData.thread)
        auraData.thread = nil
    end
end

-- 🚨 MAIN EVENT LISTENERS 🚨
task.spawn(function()
    local CoinCollected = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Gameplay"):WaitForChild("CoinCollected")
    CoinCollected.OnClientEvent:Connect(function(_, currentCoins, maxCoins)
        if currentCoins < maxCoins then return end
        local role = getMyRole() or getRole()
        
        if (role == "Murderer" or hasKnife()) and autoKillAllEnabled then
            task.spawn(function()
                local timeout = tick() + 15
                while tick() < timeout and not hasKnife() do task.wait(0.1) end
                if hasKnife() then
                    for i = 1, 3 do
                        killAll()
                        if i < 3 then task.wait(2.5) end
                    end
                end
            end)
            return
        end

        if autoShootMurdEnabled then
            if hasGun() then startShootingMurderer() else
                if shootLoopThread then task.cancel(shootLoopThread) end
                shootLoopThread = task.spawn(function()
                    while player.Character and not hasGun() do task.wait(0.5) end
                    if player.Character and hasGun() then startShootingMurderer() else shootLoopThread = nil end
                end)
            end
        end
    end)
end)

RootMaid:GiveTask(player.CharacterAdded:Connect(function()
    hasExecutedThisLife = false
    hasFlingedMurdererThisLife = false
    if noRenderEnabled then
        task.wait(0.5)
        RunService:Set3dRenderingEnabled(false)
        CreateBlackScreen()
    end
    if shootLoopThread then task.cancel(shootLoopThread) shootLoopThread = nil end
    task.spawn(function()
        task.wait(1.5)
        flingMurdererOnRespawn()
    end)
end))

-- 🚨 UI TOGGLES 🚨
combat_section:AddToggle("Disable 3D Rendering", function(v) SetNoRenderState(v) end)

combat_section:AddToggle("Auto-Kill All", function(v)
    autoKillAllEnabled = v
    if v then
        task.spawn(function()
            while autoKillAllEnabled do
                if not hasExecutedThisLife and hasKnife() then
                    hasExecutedThisLife = true
                    task.wait(1.0)
                    killAllExceptOne()
                    break
                end
                task.wait(0.1)
            end
        end)
    end
end)

combat_section:AddToggle("Auto-Shoot Murd", function(v) autoShootMurdEnabled = v end)

combat_section:AddToggle("Auto-Reset Murderer", function(v)
    autoResetMurdEnabled = v
    updateNoclip()
    if v and player.Character and not hasFlingedMurdererThisLife then task.spawn(flingMurdererOnRespawn) end
end)

combat_section:AddToggle("Auto-Reset Sheriff", function(v)
    autoResetSheriffEnabled = v
    if v then startSheriffFling() else stopSheriffFling() end
    updateNoclip()
end)

combat_section:AddToggle("Auto-Reset All", function(v) toggleResetAll(v) end)

combat_section:AddToggle("Coin Aura", function(v) if v then startAura() else stopAura() end end)

combat_section:AddSlider("Coin Aura Radius", 1, 8, 8, function(value) auraData.radius = value end)

combat_section:AddToggle("Auto-Grab Gun", function(enabled)
    autoGGEnabled = enabled
    autoGGMaid:DoCleaning()
    if enabled then
        autoGGMaid:GiveTask(task.spawn(function()
            while autoGGEnabled do
                if player.Character and Workspace:FindFirstChild("GunDrop", true) and not hasGun() then
                    local root = player.Character:FindFirstChild("HumanoidRootPart")
                    local gunDrop = Workspace:FindFirstChild("GunDrop", true)
                    if root and gunDrop then touch(root, gunDrop) end
                end
                task.wait(0.5)
            end
        end))
    end
end)

combat_section:AddPlayerDropdown("Whitelist Player", function(p)
    if not whitelist[p.UserId] then
        whitelist[p.UserId] = true
        shared.Notify(p.Name .. " whitelisted.", 2)
    end
end)

combat_section:AddButton("Clear Whitelist", function()
    whitelist = {}
    shared.Notify("Whitelist cleared.", 2)
end)

setupAntiVoid()

RootMaid:GiveTask(player.Idled:Connect(function()
    vU:CaptureController()
    vU:ClickButton2(Vector2.new())
end))

RootMaid:GiveTask(function()
    if trueAntiVoidConnection then trueAntiVoidConnection:Disconnect() end
    workspace.FallenPartsDestroyHeight = originalDestroyHeight
    if shootLoopThread then task.cancel(shootLoopThread) end
    stopAura()
    CleanupNoRender()
    if sheriffFlingMaid then sheriffFlingMaid:Destroy() end
    if resetAllMaid then resetAllMaid:Destroy() end
    autoGGMaid:DoCleaning()
    setNoclip(false)
end)

shared.Notify("Autofarm+ Optimized Loaded!", 1)
