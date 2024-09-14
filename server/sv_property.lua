Property = {
    property_id = nil,
    propertyData = nil,
    playersInside = nil,   -- src
    playersInGarden = nil,   -- src
    playersDoorbell = nil, -- src

    raiding = false,
}
Property.__index = Property

function Property:new(propertyData)
    local self = setmetatable({}, Property)

    self.property_id = tostring(propertyData.property_id)
    self.propertyData = propertyData

    self.playersInside = {}
    self.playersInGarden = {}
    self.playersDoorbell = {}

    local stashName = ("property_%s"):format(propertyData.property_id)
    local stashConfig = Config.Shells[propertyData.shell].stash

    for k, v in ipairs(propertyData.furnitures) do
        if v.type == 'storage' then
            Framework[Config.Inventory].RegisterInventory(k == 1 and stashName or stashName..v.id, 'Property: ' ..  (propertyData.street or propertyData.apartment or 'Unknown') .. ' #'.. propertyData.property_id or propertyData.apartment or stashName, stashConfig)
        end
    end

    return self
end

function Property:PlayerEnter(src)
    local _src = tostring(src)
    local isMlo = self.propertyData.shell == 'mlo'
    local isIpl = self.propertyData.apartment and Config.Apartments[self.propertyData.apartment].interior

    self.playersInside[_src] = true

    if not isMlo then
        -- TODO: add vSync weather stop
        --TriggerClientEvent('qb-weathersync:client:DisableSync', src)
    end

    TriggerClientEvent('ps-housing:client:enterProperty', src, self.property_id)

    if next(self.playersDoorbell) then
        TriggerClientEvent("ps-housing:client:updateDoorbellPool", src, self.property_id, self.playersDoorbell)
        if self.playersDoorbell[_src] then
            self.playersDoorbell[_src] = nil
        end
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    local charid = xPlayer.getIdentifier()

    if self:CheckForAccess(charid) then
        insideMeta.property_id = self.property_id
        xPlayer.setMeta('housing', {inside = true})
    end

    if not isMlo or isIpl then
        local bucket = tonumber(self.property_id) -- because the property_id is a string
        SetPlayerRoutingBucket(src, bucket)
    end
end

function Property:PlayerLeave(src)
    local _src = tostring(src)
    self.playersInside[_src] = nil

    -- TODO: add vSync weather starter
    --TriggerClientEvent('qb-weathersync:client:EnableSync', src)

    local xPlayer = ESX.GetPlayerFromId(src)
    local charid = xPlayer.getIdentifier()

    if self:CheckForAccess(charid) then
        insideMeta.property_id = nil
        xPlayer.setMeta('housing', {inside = false})
    end

    SetPlayerRoutingBucket(src, 0)
end

function Property:CheckForAccess(charid)
    if self.propertyData.owner == charid then return true end
    return lib.table.contains(self.propertyData.has_access, charid)
end

function Property:AddToDoorbellPoolTemp(src)
    local _src = tostring(src)

    local name = GetCharName(src)

    self.playersDoorbell[_src] = {
        src = src,
        name = name
    }

    for src, _ in pairs(self.playersInside) do
        local targetSrc = tonumber(src)

        Framework[Config.Notify].Notify(targetSrc, "Someone is at the door.", "info")
        TriggerClientEvent("ps-housing:client:updateDoorbellPool", targetSrc, self.property_id, self.playersDoorbell)
    end

    Framework[Config.Notify].Notify(src, "You rang the doorbell. Just wait...", "info")

    SetTimeout(10000, function()
        if self.playersDoorbell[_src] then
            self.playersDoorbell[_src] = nil
            Framework[Config.Notify].Notify(src, "No one answered the door.", "error")
        end

        for src, _ in pairs(self.playersInside) do
            local targetSrc = tonumber(src)

            TriggerClientEvent("ps-housing:client:updateDoorbellPool", targetSrc, self.property_id, self.playersDoorbell)
        end
    end)
end

function Property:RemoveFromDoorbellPool(src)
    local _src = tostring(src)

    if self.playersDoorbell[_src] then
        self.playersDoorbell[_src] = nil
    end

    for src, _ in pairs(self.playersInside) do
        local targetSrc = tonumber(src)

        TriggerClientEvent("ps-housing:client:updateDoorbellPool", targetSrc, self.property_id, self.playersDoorbell)
    end
end

function Property:StartRaid()
    self.raiding = true

    for src, _ in pairs(self.playersInside) do
        local targetSrc = tonumber(src)
        Framework[Config.Notify].Notify(targetSrc, "This Property is being Raided.", "error")
    end

    SetTimeout(Config.RaidTimer * 60000, function()
        self.raiding = false
    end)
end

function Property:UpdateFurnitures(furnitures, isGarden)
    local newfurnitures = {}

    for i = 1, #furnitures do
        newfurnitures[i] = {
            id = furnitures[i].id,
            label = furnitures[i].label,
            object = furnitures[i].object,
            position = furnitures[i].position,
            rotation = furnitures[i].rotation,
            type = furnitures[i].type
        }
    end

    self.propertyData.furnitures = newfurnitures

    MySQL.update("UPDATE properties SET furnitures = @furnitures WHERE property_id = @property_id", {
        ["@furnitures"] = json.encode(newfurnitures),
        ["@property_id"] = self.property_id
    })

    if isGarden then
        for src, _ in pairs(self.playersInGarden) do
            TriggerClientEvent("ps-housing:client:updateFurniture", tonumber(src), self.property_id, furnitures, true)
        end
        return
    end

    for src, _ in pairs(self.playersInside) do
        TriggerClientEvent("ps-housing:client:updateFurniture", tonumber(src), self.property_id, furnitures)
    end
end

function Property:UpdateDescription(data)
    local description = data.description
    local realtorSrc = data.realtorSrc

    if self.propertyData.description == description then return end

    self.propertyData.description = description

    MySQL.update("UPDATE properties SET description = @description WHERE property_id = @property_id", {
        ["@description"] = description,
        ["@property_id"] = self.property_id
    })

    TriggerClientEvent("ps-housing:client:updateProperty", -1, "UpdateDescription", self.property_id, description)

    Framework[Config.Logs].SendLog("**Changed Description** of property with id: " .. self.property_id .. " by: " .. GetPlayerName(realtorSrc))

    Debug("Changed Description of property with id: " .. self.property_id, "by: " .. GetPlayerName(realtorSrc))
end

function Property:UpdatePrice(data)
    local price = data.price
    local realtorSrc = data.realtorSrc

    if self.propertyData.price == price then return end

    self.propertyData.price = price

    MySQL.update("UPDATE properties SET price = @price WHERE property_id = @property_id", {
        ["@price"] = price,
        ["@property_id"] = self.property_id
    })

    TriggerClientEvent("ps-housing:client:updateProperty", -1, "UpdatePrice", self.property_id, price)

    Framework[Config.Logs].SendLog("**Changed Price** of property with id: " .. self.property_id .. " by: " .. GetPlayerName(realtorSrc))

    Debug("Changed Price of property with id: " .. self.property_id, "by: " .. GetPlayerName(realtorSrc))
end

function Property:UpdateForSale(data)
    local forsale = data.forsale
    local realtorSrc = data.realtorSrc

    self.propertyData.for_sale = forsale

    MySQL.update("UPDATE properties SET for_sale = @for_sale WHERE property_id = @property_id", {
        ["@for_sale"] = forsale and 1 or 0,
        ["@property_id"] = self.property_id
    })

    TriggerClientEvent("ps-housing:client:updateProperty", -1, "UpdateForSale", self.property_id, forsale)

    Framework[Config.Logs].SendLog("**Changed For Sale** of property with id: " .. self.property_id .. " by: " .. GetPlayerName(realtorSrc))

    Debug("Changed For Sale of property with id: " .. self.property_id, "by: " .. GetPlayerName(realtorSrc))
end

function Property:UpdateShell(data)
    local shell = data.shell
    local realtorSrc = data.realtorSrc

    if self.propertyData.shell == shell then return end

    self.propertyData.shell = shell

    MySQL.update("UPDATE properties SET shell = @shell WHERE property_id = @property_id", {
        ["@shell"] = shell,
        ["@property_id"] = self.property_id
    })

    TriggerClientEvent("ps-housing:client:updateProperty", -1, "UpdateShell", self.property_id, shell)

    Framework[Config.Logs].SendLog("**Changed Shell** of property with id: " .. self.property_id .. " by: " .. GetPlayerName(realtorSrc))

    Debug("Changed Shell of property with id: " .. self.property_id, "by: " .. GetPlayerName(realtorSrc))
end

function Property:addMloDoorsAccess(charid)
    if self.propertyData.shell ~= 'mlo' then return end

    if DoorResource == 'ox' then
        local ox_doorlock = exports.ox_doorlock
        for i=1 , self.propertyData.door_data.count do
            local door = ox_doorlock:getDoorFromName(('ps_mloproperty%s_%s'):format(self.property_id, i))
            local data = door.characters or {}
            table.insert(data, charid)
            ox_doorlock:editDoor(door.id, {characters = data})
        end
    else
        local qb_doorlock = exports['qb-doorlock']
        for i=1 , self.propertyData.door_data.count do
            local id = ('ps_mloproperty%s_%s'):format(self.property_id, i)
            local door = qb_doorlock:getDoor(id)
            local data = door.authorizedCitizenIDs or {}
            data[citizenid] = true
            qb_doorlock:updateDoor(id, {authorizedCitizenIDs = data})
        end
    end
end

function Property:removeMloDoorsAccess(charid)
    if self.propertyData.shell ~= 'mlo' then return end

    if DoorResource == 'ox' then
        local ox_doorlock = exports.ox_doorlock
        for i = 1, self.propertyData.door_data.count do
            local door = ox_doorlock:getDoorFromName(('ps_mloproperty%s_%s'):format(self.property_id, i))
            local data = door.characters or {}
            for index, id in ipairs(data) do
                if id == charid then
                    table.remove(data, index)
                    break
                end
            end
            ox_doorlock:editDoor(door.id, {characters = data})
        end
    else
        local qb_doorlock = exports['qb-doorlock']
        for i = 1, self.propertyData.door_data.count do
            local id = ('ps_mloproperty%s_%s'):format(self.property_id, i)
            local door = qb_doorlock:getDoor(id)
            local data = door.authorizedCitizenIDs or {}
            data[citizenid] = nil
            qb_doorlock:updateDoor(id, {authorizedCitizenIDs = data})
        end
    end
end

function Property:UpdateOwner(data)
    local targetSrc = data.targetSrc
    local realtorSrc = data.realtorSrc

    if not realtorSrc then Debug("No Realtor Src found") return end
    if not targetSrc then Debug("No Target Src found") return end

    local previousOwner = self.propertyData.owner

    local targetPlayer  = xPlayer.GetPlayerFromId(tonumber(targetSrc))
    if not targetPlayer then return end

    local PlayerData = targetPlayer.PlayerData -- TODO: may not work in ESX
    local bank = xPlayer.getAccount("bank").money
    local charid = targetPlayer.getIdentifier()

    self:addMloDoorsAccess(charid)
    if self.propertyData.shell == 'mlo' and DoorResource == 'qb' then
        Framework[Config.Notify].Notify(targetSrc, "Go far away and come back for the door to update and open/close.", "error")
    end

    if self.propertyData.owner == charid then
        Framework[Config.Notify].Notify(targetSrc, "You already own this property", "error")
        Framework[Config.Notify].Notify(realtorSrc, "Client already owns this property", "error")
        return
    end

    --add callback 
    local targetAllow = lib.callback.await("ps-housing:cb:confirmPurchase", targetSrc, self.propertyData.price, self.propertyData.street, self.propertyData.property_id)

    if targetAllow ~= "confirm" then
        Framework[Config.Notify].Notify(targetSrc, "You did not confirm the purchase", "info")
        Framework[Config.Notify].Notify(realtorSrc, "Client did not confirm the purchase", "error")
        return
    end

    if bank < self.propertyData.price then
            Framework[Config.Notify].Notify(targetSrc, "You do not have enough money in your bank account", "error")
            Framework[Config.Notify].Notify(realtorSrc, "Client does not have enough money in their bank account", "error")
        return
    end

    targetPlayer.removeAccountMoney('bank', self.propertyData.price)
    --targetPlayer.Functions.RemoveMoney('bank', self.propertyData.price, "Bought Property: " .. self.propertyData.street .. " " .. self.property_id)

    local prevPlayer = ESX.GetPlayerFromIdentifier(previousOwner)
    local realtor = ESX.GetPlayerFromId(tonumber(realtorSrc))
    local realtorGradeLevel = realtor.getJob().grade

    local commission = math.floor(self.propertyData.price * Config.Commissions[realtorGradeLevel])
    local totalAfterCommission = self.propertyData.price - commission

    if Config.QBManagement then
        exports['qb-banking']:AddMoney(realtor.PlayerData.job.name, totalAfterCommission)
    else
        if prevPlayer ~= nil then
            Framework[Config.Notify].Notify(prevPlayer.PlayerData.source, "Sold Property: " .. self.propertyData.street .. " " .. self.property_id, "success")
            prevPlayer.addAccountMoney('bank', totalAfterCommission)

        elseif previousOwner then
            MySQL.Async.execute('UPDATE `players` SET `bank` = `bank` + @price WHERE `charid` = @charid', {
                ['@charid'] = previousOwner,
                ['@price'] = totalAfterCommission
            })
        end
    end
    
    realtor.addAccountMoney('bank', commission)
    --realtor.Functions.AddMoney('bank', commission, "Commission from Property: " .. self.propertyData.street .. " " .. self.property_id)

    self.propertyData.owner = charid

    MySQL.update("UPDATE properties SET owner_charid = @owner_charid, for_sale = @for_sale WHERE property_id = @property_id", {
        ["@owner_charid"] = charid,
        ["@for_sale"] = 0,
        ["@property_id"] = self.property_id
    })

    self.propertyData.furnitures = {} -- to be fetched on enter

    TriggerClientEvent("ps-housing:client:updateProperty", -1, "UpdateOwner", self.property_id, charid)
    TriggerClientEvent("ps-housing:client:updateProperty", -1, "UpdateForSale", self.property_id, 0)
    
    Framework[Config.Logs].SendLog("**House Bought** by: **"..prevPlayer.getName().."** for $"..self.propertyData.price.." from **".. realtor.getName() .."** !")

    Framework[Config.Notify].Notify(targetSrc, "You have bought the property for $"..self.propertyData.price, "success")
    Framework[Config.Notify].Notify(realtorSrc, "Client has bought the property for $"..self.propertyData.price, "success")
end

function Property:UpdateImgs(data)
    local imgs = data.imgs
    local realtorSrc = data.realtorSrc

    self.propertyData.imgs = imgs

    MySQL.update("UPDATE properties SET extra_imgs = @extra_imgs WHERE property_id = @property_id", {
        ["@extra_imgs"] = json.encode(imgs),
        ["@property_id"] = self.property_id
    })

    TriggerClientEvent("ps-housing:client:updateProperty", -1, "UpdateImgs", self.property_id, imgs)

    Framework[Config.Logs].SendLog("**Changed Images** of property with id: " .. self.property_id .. " by: " .. GetPlayerName(realtorSrc))

    Debug("Changed Imgs of property with id: " .. self.property_id, "by: " .. GetPlayerName(realtorSrc))
end


function Property:UpdateDoor(data)
    local door = data.door

    if not door then return end
    local realtorSrc = data.realtorSrc

    local newDoor = {
        x = math.floor(door.x * 10000) / 10000,
        y = math.floor(door.y * 10000) / 10000,
        z = math.floor(door.z * 10000) / 10000,
        h = math.floor(door.h * 10000) / 10000,
        length = door.length or 1.5,
        width = door.width or 2.2,
        locked = door.locked or false,
    }

    self.propertyData.door_data = newDoor

    self.propertyData.street = data.street
    self.propertyData.region = data.region


    MySQL.update("UPDATE properties SET door_data = @door, street = @street, region = @region WHERE property_id = @property_id", {
        ["@door"] = json.encode(newDoor),
        ["@property_id"] = self.property_id,
        ["@street"] = data.street,
        ["@region"] = data.region
    })

    TriggerClientEvent("ps-housing:client:updateProperty", -1, "UpdateDoor", self.property_id, newDoor, data.street, data.region)

    Framework[Config.Logs].SendLog("**Changed Door** of property with id: " .. self.property_id .. " by: " .. GetPlayerName(realtorSrc))

    Debug("Changed Door of property with id: " .. self.property_id, "by: " .. GetPlayerName(realtorSrc))
end

function Property:UpdateHas_access(data)
    local has_access = data or {}

    self.propertyData.has_access = has_access

    MySQL.update("UPDATE properties SET has_access = @has_access WHERE property_id = @property_id", {
        ["@has_access"] = json.encode(has_access), --Array of charid's
        ["@property_id"] = self.property_id
    })

    TriggerClientEvent("ps-housing:client:updateProperty", -1, "UpdateHas_access", self.property_id, has_access)

    Debug("Changed Has Access of property with id: " .. self.property_id)
end

function Property:UpdateGarage(data)
    local garage = data.garage
    local realtorSrc = data.realtorSrc

    local newData = {}

    if data ~= nil then 
        newData = {
            x = math.floor(garage.x * 10000) / 10000,
            y = math.floor(garage.y * 10000) / 10000,
            z = math.floor(garage.z * 10000) / 10000,
            h = math.floor(garage.h * 10000) / 10000,
            length = garage.length or 3.0,
            width = garage.width or 5.0,
        }
    end

    self.propertyData.garage_data = newData

    MySQL.update("UPDATE properties SET garage_data = @garageCoords WHERE property_id = @property_id", {
        ["@garageCoords"] = json.encode(newData),
        ["@property_id"] = self.property_id
    })
    
    TriggerClientEvent("ps-housing:client:updateProperty", -1, "UpdateGarage", self.property_id, newData)

    Framework[Config.Logs].SendLog("**Changed Garage** of property with id: " .. self.property_id .. " by: " .. GetPlayerName(realtorSrc))

    Debug("Changed Garage of property with id: " .. self.property_id, "by: " .. GetPlayerName(realtorSrc))
end

function Property:UpdateApartment(data)
    local apartment = data.apartment
    local realtorSrc = data.realtorSrc
    local targetSrc = data.targetSrc

    self.propertyData.apartment = apartment

    MySQL.update("UPDATE properties SET apartment = @apartment WHERE property_id = @property_id", {
        ["@apartment"] = apartment,
        ["@property_id"] = self.property_id
    })

    Framework[Config.Notify].Notify(realtorSrc, "Changed Apartment of property with id: " .. self.property_id .." to ".. apartment, "success")

    Framework[Config.Notify].Notify(targetSrc, "Changed Apartment to " .. apartment, "success")

    Framework[Config.Logs].SendLog("**Changed Apartment** with id: " .. self.property_id .. " by: **" .. GetPlayerName(realtorSrc) .. "** for **" .. GetPlayerName(targetSrc) .."**")

    TriggerClientEvent("ps-housing:client:updateProperty", -1, "UpdateApartment", self.property_id, apartment)

    Debug("Changed Apartment of property with id: " .. self.property_id, "by: " .. GetPlayerName(realtorSrc))
end

function Property:DeleteProperty(data)
    local realtorSrc = data.realtorSrc
    local propertyid = self.property_id
    local realtorName = GetPlayerName(realtorSrc)

    MySQL.Async.execute("DELETE FROM properties WHERE property_id = @property_id", {
        ["@property_id"] = propertyid
    }, function (rowsChanged)
        if rowsChanged > 0 then
            Debug("Deleted property with id: " .. propertyid, "by: " .. realtorName)
        end
    end)

    TriggerClientEvent("ps-housing:client:removeProperty", -1, propertyid)

    Framework[Config.Notify].Notify(realtorSrc, "Property with id: " .. propertyid .." has been removed.", "info")

    Framework[Config.Logs].SendLog("**Property Deleted** with id: " .. propertyid .. " by: " .. realtorName)

    PropertiesTable[propertyid] = nil
    self = nil

    Debug("Deleted property with id: " .. propertyid, "by: " .. realtorName)
end

function Property.Get(property_id)
    return PropertiesTable[tostring(property_id)]
end

RegisterNetEvent('ps-housing:server:enterGarden', function (property_id)
    local src = source
    local property = Property.Get(property_id)

    if not property then
        Debug("Properties returned", json.encode(PropertiesTable, {indent = true}))
        return
    end

    property.playersInGarden[tostring(src)] = true
end)

RegisterNetEvent('ps-housing:server:enterProperty', function (property_id)
    local src = source
    Debug("Player is trying to enter property", property_id)

    local property = Property.Get(property_id)

    if not property then
        Debug("Properties returned", json.encode(PropertiesTable, {indent = true}))
        return
    end

    local charid = ESX.GetPlayerFromId(src)

    if property:CheckForAccess(charid) then
        Debug("Player has access to property")
        property:PlayerEnter(src)
        Debug("Player entered property")
        return
    end

    local ringDoorbellConfirmation = lib.callback.await('ps-housing:cb:ringDoorbell', src)
    if ringDoorbellConfirmation == "confirm" then
        property:AddToDoorbellPoolTemp(src)
        Debug("Ringing doorbell")
        return
    end
end)

RegisterNetEvent("ps-housing:server:showcaseProperty", function(property_id)
    local src = source

    local property = Property.Get(property_id)

    if not property then 
        Debug("Properties returned", json.encode(PropertiesTable, {indent = true}))
        return 
    end


    local xPlayer = ESX.GetPlayerFromId(src)
    local job = xPlayer.getJob()
    local jobName = xPlayer.getName()

    if RealtorJobs[jobName] then
        local showcase = lib.callback.await('ps-housing:cb:showcase', src)
        if showcase == "confirm" then
            property:PlayerEnter(src)
            return
        end
    end
end)

RegisterNetEvent('ps-housing:server:raidProperty', function(property_id)
    local src = source
    Debug("Player is trying to raid property", property_id)

    local property = Property.Get(property_id)

    if not property then 
        Debug("Properties returned", json.encode(PropertiesTable, {indent = true}))
        return 
    end

    local Player = ESX.GetPlayerFromId(src)
    if not Player then return end
    local PlayerData = Player.PlayerData -- TODO: may not work for esx
    local job = Player.getJob()
    local jobName = Player.getName()
    local gradeAllowed = tonumber(job.grade.level) >= Config.MinGradeToRaid
    local raidItem = Config.RaidItem

    -- Check if the police officer has the "stormram" item
    local hasStormRam = (Config.Inventory == "ox" and exports.ox_inventory:Search(src, "count", raidItem) > 0) or Player.Functions.GetItemByName(raidItem)

    local isAllowedToRaid = PoliceJobs[jobName] and gradeAllowed
    if isAllowedToRaid then
        if hasStormRam then
            if not property.raiding then
                local confirmRaid = lib.callback.await('ps-housing:cb:confirmRaid', src, (property.propertyData.street or property.propertyData.apartment) .. " " .. property.property_id, property_id)
                if confirmRaid == "confirm" then
                    property:StartRaid(src)
                    property:PlayerEnter(src)
                    Framework[Config.Notify].Notify(src, "Raid started", "success")

                    if Config.ConsumeRaidItem then
                        -- Remove the "stormram" item from the officer's inventory
                        if Config.Inventory == 'ox' then
                            exports.ox_inventory:RemoveItem(src, raidItem, 1)
                        else
                            if lib.checkDependency('qb-inventory', '2.0.0') then
                                TriggerClientEvent("qb-inventory:client:ItemBox", src, QBCore.Shared.Items[raidItem], "remove")
                                exports['qb-inventory']:RemoveItem(source, raidItem, 1)
                            else
                                TriggerClientEvent("inventory:client:ItemBox", src, QBCore.Shared.Items[raidItem], "remove")
                                TriggerEvent("inventory:server:RemoveItem", src, raidItem, 1)
                            end
                        end
                    end

                    if property.propertyData.shell == 'mlo' then
                        if DoorResource == 'ox' then
                            local ox_doorlock = exports.ox_doorlock
                            for i=1 , property.propertyData.door_data.count do
                                local door = ox_doorlock:getDoorFromName(('ps_mloproperty%s_%s'):format(property.property_id, i))
                                ox_doorlock:setDoorState(door.id, 0)
                            end
                        else
                            for i=1 , property.propertyData.door_data.count do
                                local id = ('ps_mloproperty%s_%s'):format(property.property_id, i)
                                TriggerEvent('qb-doorlock:server:updateState', id, false, false, false, false, true, true, src)
                            end
                        end
                    end
                end
            else
                Framework[Config.Notify].Notify(src, "Raid in progress", "success")
                property:PlayerEnter(src)
            end
        else
            Framework[Config.Notify].Notify(src, "You need a stormram to perform a raid", "error")
        end
    else
        if not PoliceJobs[jobName] then
            Framework[Config.Notify].Notify(src, "Only police officers are permitted to perform raids", "error")
        elseif not gradeAllowed then
            Framework[Config.Notify].Notify(src, "You must be a higher rank before performing a raid", "error")
        end
    end
end)

lib.callback.register('ps-housing:cb:getFurnitures', function(_, property_id)
    local property = Property.Get(property_id)
    if not property then return end
    return property.propertyData.furnitures or {}
end)

lib.callback.register('ps-housing:cb:getPlayersInProperty', function(source, property_id)
    local property = Property.Get(property_id)
    if not property then return end

    local players = {}

    for src, _ in pairs(property.playersInside) do
        local targetSrc = tonumber(src)
        if targetSrc ~= source then
            local name = GetCharName(targetSrc)

            players[#players + 1] = {
                src = targetSrc,
                name = name
            }
        end
    end

    return players or {}
end)

RegisterNetEvent('ps-housing:server:leaveProperty', function (property_id)
    local src = source
    local property = Property.Get(property_id)

    if not property then return end

    property:PlayerLeave(src)
end)

-- When player presses doorbell, owner can let them in and this is what is triggered
RegisterNetEvent("ps-housing:server:doorbellAnswer", function (data) 
    local src = source
    local targetSrc = data.targetSrc

    local property = Property.Get(data.property_id)
    if not property then return end
    
    if not property.playersInside[tostring(src)] then return end
    property:RemoveFromDoorbellPool(targetSrc)
    
    property:PlayerEnter(targetSrc)
end)

--@@ NEED TO REDO THIS DOG SHIT
-- I think its not bad anymore but if u got a better idea lmk
RegisterNetEvent("ps-housing:server:buyFurniture", function(property_id, items, price, isGarden)
    local src = source

    local xPlayer = ESX.GetPlayerFromId(src)
    local charid = xPlayer.getIdentifier()

    local property = Property.Get(property_id)
    if not property then return end

    if not property:CheckForAccess(charid) then return end

    price = tonumber(price)

    if price > xPlayer.getMoney() then
        Framework[Config.Notify].Notify(src, "You do not have enough money!", "error")
        return
    end

    if price <= xPlayer.getMoney() then
        xPlayer.removeMoney(price)
    end

    local propertyData = property.propertyData
    local numFurnitures = #propertyData.furnitures
    local firstStorage = true

    for _, v in ipairs(propertyData.furnitures) do
        if v.type == 'storage' then
            firstStorage = false
            break
        end
    end

    for i = 1, #items do
        local item = items[i]
        if item.type == 'storage' then
            local stashName = ("property_%s"):format(propertyData.property_id)
            local stashConfig = Config.Shells[propertyData.shell].stash
            Framework[Config.Inventory].RegisterInventory(firstStorage and stashName or stashName..item.id, 'Property: ' ..  propertyData.street .. ' #'.. propertyData.property_id or propertyData.apartment or stashName, stashConfig)
        end
        numFurnitures = numFurnitures + 1
        propertyData.furnitures[numFurnitures] = item
    end

    property:UpdateFurnitures(propertyData.furnitures, isGarden)

    Framework[Config.Notify].Notify(src, "You bought furniture for $" .. price, "success")

    Framework[Config.Logs].SendLog("**Player ".. GetPlayerName(src) .. "** bought furniture for **$" .. price .. "**")

    Debug("Player bought furniture for $" .. price, "by: " .. GetPlayerName(src))
end)

RegisterNetEvent("ps-housing:server:openQBInv", function(data) -- TODO: do npt need in esx
    local src = source
    local stashId, stashData, propertyId in data

    local property = Property.Get(propertyId)
    if not property then return end

    local citizenid = GetCitizenid(src)
    if not property:CheckForAccess(citizenid) then return end

    exports['qb-inventory']:OpenInventory(src, stashId, stashData)
end)

RegisterNetEvent("ps-housing:server:removeFurniture", function(property_id, itemid)
    local src = source
    
    local property = Property.Get(property_id)
    if not property then return end
    
    local charid = ESX.GetPlayerFromId(src).getIdentifier()
    if not property:CheckForAccess(charid) then return end

    local currentFurnitures = property.propertyData.furnitures

    for k, v in ipairs(currentFurnitures) do
        if v.id == itemid then
            table.remove(currentFurnitures, k)
            break
        end
    end

    property:UpdateFurnitures(currentFurnitures)
end)

-- @@ VERY BAD 
-- I think its not bad anymore but if u got a better idea lmk
RegisterNetEvent("ps-housing:server:updateFurniture", function(property_id, item)
    local src = source

    local property = Property.Get(property_id)
    if not property then return end

    local charid = ESX.GetPlayerFromId(src).getIdentifier()
    if not property:CheckForAccess(charid) then return end

    local currentFurnitures = property.propertyData.furnitures

    for k, v in ipairs(currentFurnitures) do
        if v.id == item.id then
            currentFurnitures[k] = item
            Debug("Updated furniture", json.encode(item))
            break
        end
    end

    property:UpdateFurnitures(currentFurnitures)
end)

RegisterNetEvent("ps-housing:server:addAccess", function(property_id, srcToAdd)
    local src = source

    local charid = ESX.GetPlayerFromId(src).getIdentifier()
    local property = Property.Get(property_id)
    if not property then return end

    if not property.propertyData.owner == charid then
        -- hacker ban or something
        Framework[Config.Notify].Notify(src, "You are not the owner of this property!", "error")
        return
    end

    local has_access = property.propertyData.has_access

    local targetPlayer = ESX.GetPlayerFromid(srcToAdd)
    local targetCharid = targetPlayer.getIdentifier()

    if not property:CheckForAccess(targetCharid) then
        has_access[#has_access+1] = targetCharid
        property:addMloDoorsAccess(targetCharid)
        property:UpdateHas_access(has_access)

        Framework[Config.Notify].Notify(src, "You added access to " .. targetPlayer.getName(), "success")
        Framework[Config.Notify].Notify(srcToAdd, "You got access to this property!", "success")
    else
        Framework[Config.Notify].Notify(src, "This person already has access to this property!", "error")
    end
end)

-- TODO: probably not needed for esx
RegisterNetEvent("ps-housing:server:qbxRegisterHouse", function(property_id)
    local property = Property.Get(property_id)
    if not property then return end

    local propertyData = property.propertyData
    local label = propertyData.street .. property.property_id .. " Garage"
    local garageData = propertyData.garage_data
    local coords = vec4(garageData.x, garageData.y, garageData.z, garageData.h)

    exports.qbx_garages:RegisterGarage('housegarage-'..property_id, {
        label = label,
        vehicleType = 'car',
        groups = propertyData.owner,
        accessPoints = {
            {
                coords = coords,
                spawn = coords,
            }
        },
    })
end)

RegisterNetEvent("ps-housing:server:removeAccess", function(property_id, charidToRemove)
    local src = source

    local charid = ESX.GetPlayerFromId(src)
    local property = Property.Get(property_id)
    if not property then return end

    if not property.propertyData.owner == charid then
        -- hacker ban or something
        Framework[Config.Notify].Notify(src, "You are not the owner of this property!", "error")
        return
    end

    local has_access = property.propertyData.has_access

    if property:CheckForAccess(charidToRemove) then
        for i = 1, #has_access do
            if has_access[i] == charidToRemove then
                table.remove(has_access, i)
                break
            end
        end 

        property:removeMloDoorsAccess(charidToRemove)
        property:UpdateHas_access(has_access)

        local playerToAdd = ESX.GetPlayerFromIdentifier(charidToRemove)
        local removePlayerData = ESX.GetPlayerFromIdentifier(charidToRemove)
        local srcToRemove = removePlayerData.source -- TODO: may not work in esx

        Framework[Config.Notify].Notify(src, "You removed access from " .. removePlayerData.getName(), "success")

        if srcToRemove then
            Framework[Config.Notify].Notify(srcToRemove, "You lost access to " .. (property.propertyData.street or property.propertyData.apartment) .. " " .. property.property_id, "error")
        end
    else
        Framework[Config.Notify].Notify(src, "This person does not have access to this property!", "error")
    end
end)

lib.callback.register("ps-housing:cb:getPlayersWithAccess", function (source, property_id)
    local src = source
    local charidSrc = ESX.GetPlayerFromId(src).getIdentifier()
    local property = Property.Get(property_id)
    
    if not property then return end
    if property.propertyData.owner ~= charidSrc then return end

    local withAccess = {}
    local has_access = property.propertyData.has_access

    for i = 1, #has_access do
        local charid = has_access[i]
        local Player = ESX.GetPlayerFromIdentifier(charid)
        if Player then
            withAccess[#withAccess + 1] = {
                charid = charid,
                name = Player.getName()
            }
        end
    end

    return withAccess
end)

lib.callback.register('ps-housing:cb:getPropertyInfo', function (source, property_id)
    local src = source
    local property = Property.Get(property_id)

    if not property then return end

    local xPlayer = ESX.GetPlayerFromId(src)
    local job = xPlayer.getJob()
    local jobName = job.name

    if RealtorJobs[jobName] then return end

    local data = {}

    local ownerPlayer, ownerName

    local ownerCid = property.propertyData.owner
    if ownerCid then
        ownerPlayer = ESX.GetPlayerFromIdentifier(ownerCid)
        ownerName = ownerPlayer.getName()
    else
        ownerName = "No Owner"
    end

    data.owner = ownerName
    data.street = property.propertyData.street
    data.region = property.propertyData.region
    data.description = property.propertyData.description
    data.for_sale = property.propertyData.for_sale
    data.price = property.propertyData.price
    data.shell = property.propertyData.shell
    data.property_id = property.property_id

    return data
end)

RegisterNetEvent('ps-housing:server:resetMetaData', function()
    local src = source
    local Player = ESX.GetPlayerFromId(src)

    insideMeta.property_id = nil
    Player.setMeta('housing', {inside = true})
end)
