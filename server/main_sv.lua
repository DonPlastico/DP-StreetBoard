local QBCore = nil
local ESX = nil

-- Detectar Framework al inicio
if Config.Framework == "qb" then
    QBCore = exports["qb-core"]:GetCoreObject()
elseif Config.Framework == "esx" then
    ESX = exports["es_extended"]:getSharedObject()
end

-- 1. Registrar el Item Usable (AHORA QUITA EL ITEM)
if Config.Framework == "qb" then
    QBCore.Functions.CreateUseableItem(Config.ItemName, function(source, item)
        local Player = QBCore.Functions.GetPlayer(source)
        -- Quitamos el item primero para evitar dupes
        if Player.Functions.RemoveItem(Config.ItemName, 1) then
            -- Efecto visual de qb-inventory (Caja Roja)
            TriggerClientEvent('inventory:client:ItemBox', source, QBCore.Shared.Items[Config.ItemName], "remove")
            TriggerClientEvent('DP-StreetBoard:client:Activate', source)
        end
    end)
elseif Config.Framework == "esx" then
    ESX.RegisterUsableItem(Config.ItemName, function(source)
        local xPlayer = ESX.GetPlayerFromId(source)
        xPlayer.removeInventoryItem(Config.ItemName, 1)
        TriggerClientEvent('DP-StreetBoard:client:Activate', source)
    end)
end

-- 2. Evento para DEVOLVER el item al recogerlo
RegisterNetEvent('DP-StreetBoard:server:PickUp', function()
    local src = source
    if Config.Framework == "qb" then
        local Player = QBCore.Functions.GetPlayer(src)
        if Player.Functions.AddItem(Config.ItemName, 1) then
            -- Efecto visual de qb-inventory (Caja Verde)
            TriggerClientEvent('inventory:client:ItemBox', src, QBCore.Shared.Items[Config.ItemName], "add")
        end
    elseif Config.Framework == "esx" then
        local xPlayer = ESX.GetPlayerFromId(src)
        xPlayer.addInventoryItem(Config.ItemName, 1)
    end
end)

-- 3. Evento de Sincronización
RegisterNetEvent("DP-StreetBoard:server:SyncAnim", function()
    local src = source
    TriggerClientEvent("DP-StreetBoard:client:SyncAnim", -1, src)
end)
