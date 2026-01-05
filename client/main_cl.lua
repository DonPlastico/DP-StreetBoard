local QBCore = nil
local ESX = nil
local PlayerData = {}

-- ==========================================================
-- 1. INICIALIZACIÓN Y UTILIDADES
-- ==========================================================

CreateThread(function()
    if Config.Framework == "qb" then
        QBCore = exports["qb-core"]:GetCoreObject()
    elseif Config.Framework == "esx" then
        ESX = exports["es_extended"]:getSharedObject()
    end
end)

local function SendNotify(msg, type)
    if Config.Framework == "qb" then
        QBCore.Functions.Notify(msg, type or "primary")
    elseif Config.Framework == "esx" then
        ESX.ShowNotification(msg)
    end
end

-- ==========================================================
-- 2. LÓGICA DEL NÚCLEO
-- ==========================================================

local BoardEngine = {
    Active = false,
    IsAttached = false,
    DriverRef = nil,
    PropRef = nil,
    DummyPed = nil,
    LoadedModels = {},
    LastJumpTime = 0,
    UIState = {
        Shown = false,
        Mode = nil
    }
}

-- Cargar modelos en memoria
function BoardEngine.RequestAssets(assetList)
    for _, asset in pairs(assetList) do
        if IsModelValid(asset) then
            RequestModel(asset)
            while not HasModelLoaded(asset) do
                Wait(10)
            end
        else
            RequestAnimDict(asset)
            while not HasAnimDictLoaded(asset) do
                Wait(10)
            end
        end
        table.insert(BoardEngine.LoadedModels, asset)
    end
end

function BoardEngine.CleanupAssets()
    for _, asset in pairs(BoardEngine.LoadedModels) do
        if IsModelValid(asset) then
            SetModelAsNoLongerNeeded(asset)
        else
            RemoveAnimDict(asset)
        end
    end
    BoardEngine.LoadedModels = {}
end

-- Función principal de despliegue
function BoardEngine.Deploy()
    if DoesEntityExist(BoardEngine.DriverRef) then
        return
    end

    local pPed = PlayerPedId()
    local pCoords = GetEntityCoords(pPed)
    local pHeading = GetEntityHeading(pPed)
    local forwardVec = GetEntityForwardVector(pPed)

    BoardEngine.RequestAssets({GetHashKey(Config.PhysicsVehicle), 68070371, GetHashKey(Config.PropModel),
                               "pickup_object", "move_strafe@stealth", "move_crouch_proto"})

    local spawnPos = pCoords + forwardVec * 2.0
    BoardEngine.DriverRef = CreateVehicle(GetHashKey(Config.PhysicsVehicle), spawnPos, pHeading, true, false)
    BoardEngine.PropRef = CreateObject(GetHashKey(Config.PropModel), 0.0, 0.0, 0.0, true, true, true)

    while not DoesEntityExist(BoardEngine.DriverRef) or not DoesEntityExist(BoardEngine.PropRef) do
        Wait(5)
    end

    SetEntityNoCollisionEntity(BoardEngine.DriverRef, pPed, false)
    SetEntityCollision(BoardEngine.DriverRef, false, true)
    SetEntityVisible(BoardEngine.DriverRef, false)

    AttachEntityToEntity(BoardEngine.PropRef, BoardEngine.DriverRef, GetPedBoneIndex(pPed, 28422), 0.0, 0.0, -0.40, 0.0,
        0.0, 90.0, false, true, true, true, 1, true)

    BoardEngine.DummyPed = CreatePed(12, 68070371, spawnPos, pHeading, true, true)
    SetEntityInvincible(BoardEngine.DummyPed, true)
    SetEntityVisible(BoardEngine.DummyPed, false)
    FreezeEntityPosition(BoardEngine.DummyPed, true)
    TaskWarpPedIntoVehicle(BoardEngine.DummyPed, BoardEngine.DriverRef, -1)

    while not IsPedInVehicle(BoardEngine.DummyPed, BoardEngine.DriverRef) do
        Wait(0)
    end

    -- ============================================================
    -- BLOQUEO DE INVENTARIOS MODERNOS (qb-inventory / ox_inventory)
    -- ============================================================
    -- 1. Bloqueamos las "puertas" (aunque sea una bici) para que qb-target/inventory no deje abrirlo
    SetVehicleDoorsLocked(BoardEngine.DriverRef, 2)

    -- 2. Avisamos a inventarios modernos (como ox_inventory o nuevos qb-inventory) de que este vehículo NO tiene maletero.
    if Entity(BoardEngine.DriverRef).state then
        Entity(BoardEngine.DriverRef).state:set("noTrunk", true, true)
        Entity(BoardEngine.DriverRef).state:set("cantAccessTrunk", true, true)
    end
    -- ============================================================

    BoardEngine.InteractMode("place")
    BoardEngine.RuntimeLoop()
end

-- Gestión de montar/desmontar y recoger
function BoardEngine.InteractMode(action)
    local pPed = PlayerPedId()

    if action == "place" then
        AttachEntityToEntity(BoardEngine.DriverRef, pPed, GetPedBoneIndex(pPed, 28422), -0.1, 0.0, -0.2, 70.0, 0.0,
            270.0, 1, 1, 0, 0, 2, 1)
        TaskPlayAnim(pPed, "pickup_object", "pickup_low", 8.0, -8.0, -1, 0, 0, false, false, false)
        Wait(800)
        DetachEntity(BoardEngine.DriverRef, false, true)
        PlaceObjectOnGroundProperly(BoardEngine.DriverRef)

    elseif action == "pickup" then
        TaskPlayAnim(pPed, "pickup_object", "pickup_low", 8.0, -8.0, -1, 0, 0, false, false, false)
        Wait(600)
        AttachEntityToEntity(BoardEngine.DriverRef, pPed, GetPedBoneIndex(pPed, 28422), -0.1, 0.0, -0.2, 70.0, 0.0,
            270.0, 1, 1, 0, 0, 2, 1)
        Wait(900)
        BoardEngine.Destroy()
    end
end

function BoardEngine.Destroy()
    -- Limpieza de UI
    exports['DP-TextUI']:OcultarUI('board_e')
    exports['DP-TextUI']:OcultarUI('board_f')
    exports['DP-TextUI']:OcultarUI('board_space')
    BoardEngine.UIState.Shown = false

    DetachEntity(BoardEngine.DriverRef)
    DeleteEntity(BoardEngine.PropRef)
    DeleteVehicle(BoardEngine.DriverRef)
    DeleteEntity(BoardEngine.DummyPed)
    BoardEngine.CleanupAssets()
    BoardEngine.IsAttached = false
    BoardEngine.Active = false
    SetPedRagdollOnCollision(PlayerPedId(), false)

    -- AQUÍ: Devolvemos el item al inventario
    TriggerServerEvent('DP-StreetBoard:server:PickUp')
    SendNotify(Config.Lang['collected'], 'success')
end

function BoardEngine.LinkPlayer(toggle)
    local pPed = PlayerPedId()
    if toggle then
        TaskPlayAnim(pPed, "move_strafe@stealth", "idle", 8.0, 8.0, -1, 1, 1.0, false, false, false)
        AttachEntityToEntity(pPed, BoardEngine.DriverRef, 20, 0.0, 0, 0.7, 0.0, 0.0, -15.0, true, true, false, true, 1,
            true)
        SetEntityCollision(pPed, true, true)
        TriggerServerEvent("DP-StreetBoard:server:SyncAnim")
    else
        DetachEntity(pPed, false, false)
        StopAnimTask(pPed, "move_strafe@stealth", "idle", 1.0)
        StopAnimTask(pPed, "move_crouch_proto", "idle_intro", 1.0)
        TaskVehicleTempAction(BoardEngine.DummyPed, BoardEngine.DriverRef, 3, 1)
    end
    BoardEngine.IsAttached = toggle
end

-- ==========================================================
-- GESTIÓN INTELIGENTE DE UI
-- ==========================================================
function BoardEngine.ManageUI(dist)
    if dist > 1.6 then
        if BoardEngine.UIState.Shown then
            exports['DP-TextUI']:OcultarUI('board_e')
            exports['DP-TextUI']:OcultarUI('board_f')
            exports['DP-TextUI']:OcultarUI('board_space')
            BoardEngine.UIState.Shown = false
            BoardEngine.UIState.Mode = nil
        end
        return
    end

    BoardEngine.UIState.Shown = true

    if BoardEngine.IsAttached then
        -- MODO MONTADO: Mostrar Saltar y Bajar (F)
        if BoardEngine.UIState.Mode ~= 'mounted' then
            exports['DP-TextUI']:OcultarUI('board_e')
            exports['DP-TextUI']:MostrarUI('board_f', Config.Lang['ui_dismount'], 'F', false) -- Cambiado a F
            exports['DP-TextUI']:MostrarUI('board_space', Config.Lang['ui_jump'], 'SPACE', false)
            BoardEngine.UIState.Mode = 'mounted'
        end
    else
        -- MODO A PIE: Mostrar Recoger y Montar (F)
        if BoardEngine.UIState.Mode ~= 'foot' then
            exports['DP-TextUI']:OcultarUI('board_space')
            exports['DP-TextUI']:MostrarUI('board_e', Config.Lang['ui_pickup'], 'E', false)
            exports['DP-TextUI']:MostrarUI('board_f', Config.Lang['ui_mount'], 'F', false) -- Cambiado a F
            BoardEngine.UIState.Mode = 'foot'
        end
    end
end

-- Loop principal
function BoardEngine.RuntimeLoop()
    BoardEngine.Active = true

    CreateThread(function()
        while BoardEngine.Active and DoesEntityExist(BoardEngine.DriverRef) do
            Wait(0)

            -- Esto impide que el juego desbloquee el vehículo al interactuar con él.
            SetVehicleDoorsLocked(BoardEngine.DriverRef, 2)

            local pPed = PlayerPedId()
            local pCoords = GetEntityCoords(pPed)
            local boardCoords = GetEntityCoords(BoardEngine.DriverRef)
            local dist = #(pCoords - boardCoords)

            BoardEngine.InputManager(dist)
            BoardEngine.ManageUI(dist)

            if dist <= Config.DetachDistance then
                if not NetworkHasControlOfEntity(BoardEngine.DummyPed) then
                    NetworkRequestControlOfEntity(BoardEngine.DummyPed)
                end
                if not NetworkHasControlOfEntity(BoardEngine.DriverRef) then
                    NetworkRequestControlOfEntity(BoardEngine.DriverRef)
                end
            else
                TaskVehicleTempAction(BoardEngine.DummyPed, BoardEngine.DriverRef, 6, 2500)
            end
        end

        -- Limpieza al salir del bucle
        exports['DP-TextUI']:OcultarUI('board_e')
        exports['DP-TextUI']:OcultarUI('board_f')
        exports['DP-TextUI']:OcultarUI('board_space')
        BoardEngine.UIState.Shown = false
        BoardEngine.UIState.Mode = nil
    end)
end

function BoardEngine.InputManager(dist)
    local pressPick = IsControlJustPressed(0, 38) -- E
    -- CAMBIADO DE 113 (G) A 23 (F - Enter Vehicle)
    local pressMount = IsControlJustReleased(0, 23)
    local startJump = IsControlJustPressed(0, 22) -- Space

    if dist <= 1.5 then
        if pressPick and not BoardEngine.IsAttached then
            BoardEngine.InteractMode("pickup")
            return
        elseif pressMount then
            if BoardEngine.IsAttached then
                BoardEngine.LinkPlayer(false)
            elseif not IsPedRagdoll(PlayerPedId()) then
                Wait(200)
                BoardEngine.LinkPlayer(true)
            end
        end
    end

    if dist < Config.DetachDistance then
        local speed = GetEntitySpeed(BoardEngine.DriverRef) * 3.6
        ForceVehicleEngineAudio(BoardEngine.DriverRef, 0)

        if BoardEngine.IsAttached then
            if BoardEngine.CheckRagdoll(speed) then
                BoardEngine.LinkPlayer(false)
                SetPedToRagdoll(PlayerPedId(), 5000, 4000, 0, true, true, false)
                BoardEngine.IsAttached = false
            end
        end

        if BoardEngine.IsAttached then
            local isOverSpeed = speed > Config.MaxVelocity
            local inputW = IsControlPressed(0, 32)
            local inputS = IsControlPressed(0, 33)
            local inputA = IsControlPressed(0, 34)
            local inputD = IsControlPressed(0, 35)

            if inputW and not inputS and not isOverSpeed then
                TaskVehicleTempAction(BoardEngine.DummyPed, BoardEngine.DriverRef, 9, 1)
            end
            if inputS and not inputW then
                TaskVehicleTempAction(BoardEngine.DummyPed, BoardEngine.DriverRef, 22, 1)
            end
            if inputA and inputS then
                TaskVehicleTempAction(BoardEngine.DummyPed, BoardEngine.DriverRef, 13, 1)
            elseif inputD and inputS then
                TaskVehicleTempAction(BoardEngine.DummyPed, BoardEngine.DriverRef, 14, 1)
            elseif inputA and inputW then
                TaskVehicleTempAction(BoardEngine.DummyPed, BoardEngine.DriverRef, 7, 1)
            elseif inputD and inputW then
                TaskVehicleTempAction(BoardEngine.DummyPed, BoardEngine.DriverRef, 8, 1)
            elseif inputA then
                TaskVehicleTempAction(BoardEngine.DummyPed, BoardEngine.DriverRef, 4, 1)
            elseif inputD then
                TaskVehicleTempAction(BoardEngine.DummyPed, BoardEngine.DriverRef, 5, 1)
            end
            if not inputW and not inputS then
                TaskVehicleTempAction(BoardEngine.DummyPed, BoardEngine.DriverRef, 6, 2500)
            end

            if startJump and not IsEntityInAir(BoardEngine.DriverRef) and
                (GetGameTimer() - BoardEngine.LastJumpTime > Config.JumpCooldown) then
                BoardEngine.PerformJump()
            end
        else
            TaskVehicleTempAction(BoardEngine.DummyPed, BoardEngine.DriverRef, 6, 1000)
        end
    end
end

function BoardEngine.CheckRagdoll(speed)
    local rot = GetEntityRotation(BoardEngine.DriverRef)
    if (rot.x < -60.0 or rot.x > 60.0) and IsEntityInAir(BoardEngine.DriverRef) and speed < 5.0 then
        return true
    end
    if HasEntityCollidedWithAnything(PlayerPedId()) and speed > 15.0 then
        return true
    end
    if IsPedDeadOrDying(PlayerPedId(), false) then
        return true
    end
    return false
end

function BoardEngine.PerformJump()
    local pPed = PlayerPedId()
    TaskPlayAnim(pPed, "move_crouch_proto", "idle_intro", 5.0, 8.0, -1, 1, 0, false, false, false)

    local charge = 0
    while IsControlPressed(0, 22) do
        Wait(10)
        if charge < 100 then
            charge = charge + 2
        end
    end

    local jumpBoost = (Config.JumpForce * charge) / 100
    if jumpBoost < (Config.JumpForce * 0.2) then
        jumpBoost = Config.JumpForce * 0.3
    end
    if jumpBoost > Config.JumpForce then
        jumpBoost = Config.JumpForce
    end

    StopAnimTask(pPed, "move_crouch_proto", "idle_intro", 1.0)

    if BoardEngine.IsAttached then
        local vel = GetEntityVelocity(BoardEngine.DriverRef)
        SetEntityVelocity(BoardEngine.DriverRef, vel.x, vel.y, vel.z + jumpBoost)
        TaskPlayAnim(pPed, "move_strafe@stealth", "idle", 8.0, 2.0, -1, 1, 1.0, false, false, false)
        BoardEngine.LastJumpTime = GetGameTimer()
    end
end

RegisterNetEvent("DP-StreetBoard:client:Activate", function()
    BoardEngine.Deploy()
end)

RegisterNetEvent("DP-StreetBoard:client:SyncAnim", function(targetSrc)
    local myId = PlayerId()
    local targetPlayer = GetPlayerFromServerId(targetSrc)
    if targetPlayer ~= -1 and targetPlayer ~= myId then
        local targetPed = GetPlayerPed(targetPlayer)
        if DoesEntityExist(targetPed) and IsEntityOnScreen(targetPed) then
            local dict = "move_strafe@stealth"
            if not HasAnimDictLoaded(dict) then
                RequestAnimDict(dict)
                while not HasAnimDictLoaded(dict) do
                    Wait(10)
                end
            end
            TaskPlayAnim(targetPed, dict, "idle", 8.0, 8.0, -1, 1, 1.0, false, false, false)
        end
    end
end)
