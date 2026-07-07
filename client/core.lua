-- ============================================================================
-- spooner :: client/core.lua
-- Shared state, native compatibility wrappers, spooner mode toggle, commands, init/permissions handlers
--
-- Part of the split client.lua. All spooner client modules share one Lua state
-- and _G, so globals defined in any module are visible to the others.
-- ============================================================================

-- ============================================================================
-- Shared client state
--
-- These values are intentionally GLOBAL (not `local`) so they can be shared
-- across the split client modules (client/*.lua). In FiveM/RedM every
-- client_script of a resource runs in the same Lua state and shares _G, so
-- globals declared here in core.lua are visible to every other module.
-- ============================================================================
Database = {}

Cam = nil
Speed = Config.Speed
AdjustSpeed = Config.AdjustSpeed
RotateSpeed = Config.RotateSpeed
AttachedEntity = nil
RotateMode = 2
AdjustMode = 4
SpeedMode = 0
PlaceOnGround = false
CurrentSpawn = nil
ShowControls = true
KeepSelfInDb = true
FocusTarget = nil
FocusTargetPos = nil
FreeFocus = false
showEntityHandles = false
CameraLookActive = false

-- Preview entity for prop browser
PreviewEntity = nil
PreviewModelName = nil

-- SpoonerPrompts, ClearTasksPrompt, DetachPrompt are globals (assigned below for RDR)

if Config.isRDR then
	SpoonerPrompts = UipromptGroup:new("Spooner", false)

	ClearTasksPrompt = Uiprompt:new(`INPUT_INTERACT_NEG`, "Clear Tasks", SpoonerPrompts)
	ClearTasksPrompt:setHoldMode(true)
	ClearTasksPrompt:setOnHoldModeJustCompleted(function()
	       TryClearTasks(PlayerPedId())
	end)

	DetachPrompt = Uiprompt:new(`INPUT_INTERACT_LEAD_ANIMAL`, "Detach", SpoonerPrompts)
	DetachPrompt:setHoldMode(true)
	DetachPrompt:setOnHoldModeJustCompleted(function()
	       TryDetach(PlayerPedId())
	end)
end

StoreDeleted = false
DeletedEntities = {}

Permissions = {}

Permissions.maxEntities = 0

Permissions.spawn = {}
Permissions.spawn.ped = false
Permissions.spawn.vehicle = false
Permissions.spawn.object = false
Permissions.spawn.propset = false
Permissions.spawn.pickup = false
Permissions.spawn.particle = false

Permissions.delete = {}
Permissions.delete.own = {}
Permissions.delete.own.networked = false
Permissions.delete.own.nonNetworked = false
Permissions.delete.other = {}
Permissions.delete.other.networked = false
Permissions.delete.other.nonNetworked = false

Permissions.modify = {}
Permissions.modify.own = {}
Permissions.modify.own.networked = false
Permissions.modify.own.nonNetworked = false
Permissions.modify.other = {}
Permissions.modify.other.networked = false
Permissions.modify.other.nonNetworked = false

Permissions.properties = {}
Permissions.properties.freeze = false
Permissions.properties.position = false
Permissions.properties.goTo = false
Permissions.properties.rotation = false
Permissions.properties.health = false
Permissions.properties.invincible = false
Permissions.properties.visible = false
Permissions.properties.gravity = false
Permissions.properties.collision = false
Permissions.properties.clone = false
Permissions.properties.attachments = false
Permissions.properties.lights = false
Permissions.properties.registerAsNetworked = false
Permissions.properties.focus = false

Permissions.properties.ped = {}
Permissions.properties.ped.changeModel = false
Permissions.properties.ped.outfit = false
Permissions.properties.ped.group = false
Permissions.properties.ped.scenario = false
Permissions.properties.ped.animation = false
Permissions.properties.ped.clearTasks = false
Permissions.properties.ped.weapon = false
Permissions.properties.ped.mount = false
Permissions.properties.ped.enterVehicle = false
Permissions.properties.ped.resurrect = false
Permissions.properties.ped.ai = false
Permissions.properties.ped.knockOffProps = false
Permissions.properties.ped.walkStyle = false
Permissions.properties.ped.clone = false
Permissions.properties.ped.cloneToTarget = false
Permissions.properties.ped.lookAtEntity = false
Permissions.properties.ped.clean = false
Permissions.properties.ped.scale = false
Permissions.properties.ped.configFlags = false
Permissions.properties.ped.goToWaypoint = false
Permissions.properties.ped.goToEntity = false
Permissions.properties.ped.attack = false

Permissions.properties.vehicle = {}
Permissions.properties.vehicle.repair = false
Permissions.properties.vehicle.getin = false
Permissions.properties.vehicle.engine = false
Permissions.properties.vehicle.lights = false

RegisterNetEvent('spooner:init')
RegisterNetEvent('spooner:toggle')
RegisterNetEvent('spooner:openDatabaseMenu')
RegisterNetEvent('spooner:openSaveDbMenu')
RegisterNetEvent('spooner:refreshPermissions')

function SetLightsIntensityForEntity(entity, intensity)
	Citizen.InvokeNative(0x07C0F87AAC57F2E4, entity, intensity)
end

function SetLightsColorForEntity(entity, red, green, blue)
	Citizen.InvokeNative(0x6EC2A67962296F49, entity, red, green, blue)
end

function SetLightsTypeForEntity(entity, type)
	Citizen.InvokeNative(0xAB72C67163DC4DB4, entity, type)
end

function CreatePed_2(modelHash, x, y, z, heading, isNetwork, thisScriptCheck, p7, p8)
	return Citizen.InvokeNative(0xD49F9B0955C367DE, modelHash, x, y, z, heading, isNetwork, thisScriptCheck, p7, p8)
end

function SetRandomOutfitVariation(ped, p1)
	Citizen.InvokeNative(0x283978A15512B2FE, ped, p1)
end

function BlipAddForEntity(blipHash, entity)
	return Citizen.InvokeNative(0x23F74C2FDA6E7C61, blipHash, entity)
end

function SetPedOnMount(ped, mount, seatIndex, p3)
	Citizen.InvokeNative(0x028F76B6E78246EB, ped, mount, seatIndex, p3)

	-- Track the mount -> rider relationship so behaviors (e.g. Patrol + Lasso) can
	-- tell the mount to move while animating/arming the actual rider.
	MountRider = MountRider or {}
	MountRider[mount] = ped
end

function IsUsingKeyboard(padIndex)
	return Citizen.InvokeNative(0xA571D46727E2B718, padIndex)
end

function RequestPropset(hash)
	return Citizen.InvokeNative(0xF3DE57A46D5585E9, hash)
end

function ReleasePropset(hash)
	return Citizen.InvokeNative(0xB1964A83B345B4AB, hash)
end

function HasPropsetLoaded(hash)
	return Citizen.InvokeNative(0x48A88FC684C55FDC, hash)
end

function CreatePropset(hash, x, y, z, p4, p5, p6, p7, p8)
	return Citizen.InvokeNative(0xE65C5CBA95F0E510, hash, x, y, z, p4, p5, p6, p7, p8)
end

function DeletePropset(propSet, p1, p2)
	return Citizen.InvokeNative(0x58AC173A55D9D7B4, propSet, p1, p2)
end

function DoesPropsetExist(propSet)
	return Citizen.InvokeNative(0x7DDDCF815E650FF5, propSet)
end

function GetEntitiesFromPropset(propSet, itemSet, p2, p3, p4)
	return Citizen.InvokeNative(0x738271B660FE0695, propSet, itemSet, p2, p3, p4)
end

function IsPickupTypeValid(pickupHash)
	return Citizen.InvokeNative(0x007BD043587F7C82, pickupHash)
end

function IsEntityFrozen(entity)
	return Citizen.InvokeNative(0x083D497D57B7400F, entity)
end

function IsPedUsingScenarioHash(ped, scenarioHash)
	return Citizen.InvokeNative(0x34D6AC1157C8226C, ped, scenarioHash)
end

function IsPropSetFullyLoaded(propSet)
	return Citizen.InvokeNative(0xF42DB680A8B2A4D9, propSet)
end

function PlaceEntityOnGroundProperly(entity, p1)
	return Citizen.InvokeNative(0x9587913B9E772D29, entity, p1)
end

function EnableSpoonerMode()
	local x, y, z = table.unpack(GetGameplayCamCoord())
	local pitch, roll, yaw = table.unpack(GetGameplayCamRot(2))
	local fov = GetGameplayCamFov()
	Cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
	SetCamCoord(Cam, x, y, z)
	SetCamRot(Cam, pitch, roll, yaw, 2)
	SetCamFov(Cam, fov)
	RenderScriptCams(true, true, 500, true, true)

	if FocusTarget then
		FocusEntity(FocusTarget)
	end

	SendNUIMessage({
		type = 'showSpoonerHud'
	})

	TriggerEvent('spooner:onSpoonerEnabled')
end

function DisableSpoonerMode()
	if Cam then
		RenderScriptCams(false, true, 500, true, true)
		SetCamActive(Cam, false)
		DetachCam(Cam)
		DestroyCam(Cam, true)
		Cam = nil
	end

	TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
	AttachedEntity = nil

	-- Clear any preview entity
	if ClearObjectPreview then
		ClearObjectPreview()
	end

	SendNUIMessage({
		type = 'hideSpoonerHud'
	})

	CameraLookActive = false
	SetNuiFocus(false, false)
end

function ToggleSpoonerMode()
	if Cam then
		DisableSpoonerMode()
	else
		EnableSpoonerMode()
	end
end


function OpenDatabaseMenu()
	UpdateDatabase()
	SendNUIMessage({
		type = 'openDatabase',
		database = json.encode(Database)
	})
	SetNuiFocus(true, true)
end

function OpenSaveDbMenu()
	SendNUIMessage({
		type = 'openSaveLoadDbMenu',
		databaseNames = json.encode(GetSavedDatabases())
	})
	SetNuiFocus(true, true)
end

RegisterCommand('spooner', function(source, args, raw)
	TriggerServerEvent('spooner:toggle')
end, false)

RegisterCommand('spooner_db', function(source, args, raw)
	TriggerServerEvent('spooner:openDatabaseMenu')
end, false)

RegisterCommand('spooner_savedb', function(source, args, raw)
	TriggerServerEvent('spooner:openSaveDbMenu')
end, false)

AddEventHandler('spooner:toggle', ToggleSpoonerMode)
AddEventHandler('spooner:openDatabaseMenu', OpenDatabaseMenu)
AddEventHandler('spooner:openSaveDbMenu', OpenSaveDbMenu)

local mainThreadActivated = false
AddEventHandler('spooner:init', function(permissions)
	-- Deactivate current thread if activate
	if mainThreadActivated then
		mainThreadActivated = false
		Wait(0)
	end

	-- Wait for UI loading
	while not uiLoaded do Wait(0) end

	-- Update in-UI permissions
	Permissions = permissions
	SendNUIMessage({
		type = 'updatePermissions',
		permissions = json.encode(permissions)
	})

	-- Activate main thread
	mainThreadActivated = true
	while mainThreadActivated do
		MainSpoonerUpdates()

		if Config.isRDR then
			SpoonerPrompts:handleEvents()
		end

		drawEntityHandles()

		Wait(0)
	end
end)

AddEventHandler('spooner:refreshPermissions', function()
	TriggerServerEvent('spooner:init')
end)


-- ============================================================================
-- Merged from the former client_extended.lua
-- ============================================================================

RegisterNUICallback('close', function(data, cb)
	DisableSpoonerMode()
	cb({})
end)

-------------------
-- Player Bucket --
-------------------
AddEventHandler('spooner:onSpoonerEnabled', function()
	TriggerServerEvent('spooner:requestPlayerRoutingBucket', PlayerPedId())
end)

RegisterNetEvent('spooner:onRequestPlayerRoutingBucket', function(bucket)
	SendNUIMessage({
		type = 'onRequestPlayerRoutingBucket',
		bucket = bucket,
	})
end)

RegisterNetEvent('spooner:onPlayerBucketChange', function(bucket)
	SendNUIMessage({
		type = 'onRequestPlayerRoutingBucket',
		bucket = bucket,
	})
end)

------------------
-- Notification --
------------------
function notify(message)
    -- GTA V notification natives don't exist in RedM, so guard them.
    if SetNotificationTextEntry then
        SetNotificationTextEntry('STRING')
        AddTextComponentString(message .. '    ~l~[' .. GetGameTimer() .. ']')
        DrawNotification(false, false)
        PlaySoundFrontend(-1, "DLC_VW_CONTINUE", "dlc_vw_table_games_frontend_sounds", 1)
    end

    TriggerEvent('chat:addMessage', { args = { '[Spooner]', message } })
end
RegisterNUICallback('notify', function(data, cb)
	local msg = data.message
	notify(msg)
	cb({})
end)

---------------
-- UI Loaded --
---------------
uiLoaded = false
RegisterNUICallback('loaded', function(data, cb)
	uiLoaded = true
	cb({})
end)
