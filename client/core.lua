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

function IsPedReadyToRender(ped)
	return Citizen.InvokeNative(0xA0BC8FAED8CFEB3C, ped)
end

function WaitForPedReadyToRender(ped, timeoutTicks)
	local waited = 0
	while not IsPedReadyToRender(ped) and waited < (timeoutTicks or 200) do
		Wait(0)
		waited = waited + 1
	end
end

-- Forces the ped's meta-ped outfit/component state to actually render. RDR3's own
-- native comment: "needed after first creation, or when component or texture/overlay
-- is changed" — without this, SetPedOutfitPreset/SetRandomOutfitVariation silently
-- have no visible effect on a freshly spawned ped.
function UpdatePedVariation(ped)
	Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, false, true, true, true, false)
	Citizen.InvokeNative(0xAAB86462966168CE, ped, true)
end

-- Applies a single clothing "shop item" (a specific drawable+texture, identified by
-- its joaat hash) to one component slot on a ped. This is the actual native RDR3's
-- own clothing store/character creator uses to dress a ped piece by piece — unlike
-- SetRandomOutfitVariation/SetPedOutfitPreset (whole-outfit black boxes), this lets
-- us build and remember an explicit per-slot config. Called twice (isMp false/true)
-- since it's ambiguous up front which mode a given ped model expects.
function ApplyShopItemToPed(ped, componentHash)
	Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, componentHash, false, false, false)
	Citizen.InvokeNative(0xD3A7B003ED343FD9, ped, componentHash, false, true, false)
end

function RemoveShopItemFromPed(ped, componentHash)
	Citizen.InvokeNative(0x0D7FFA1B2F69ED82, ped, componentHash, 0, false)
end

-- Removes every equipped shop item in a whole category (by category hash, e.g.
-- joaat('saddles')) in one call — used to clear a horse's current saddle/mane/etc.
-- before applying a new one, since these tack slots don't auto-replace on apply.
function RemoveShopItemFromPedByCategory(ped, categoryHash)
	Citizen.InvokeNative(0xDF631E4BCE1B1FC4, ped, categoryHash, 0, false)
end

-- True if the given model hash is a horse. RDR3 horses are ped type 1 like humans,
-- so this native (0x772A1969F649E902 _IS_THIS_MODEL_A_HORSE) is the reliable way to
-- tell a horse apart from a person for the tack-vs-clothing editor split.
function IsModelAHorse(model)
	return Citizen.InvokeNative(0x772A1969F649E902, model)
end

-- Convenience: is this live entity a horse ped?
function IsEntityHorse(entity)
	return DoesEntityExist(entity) and GetEntityType(entity) == 1 and IsModelAHorse(GetEntityModel(entity))
end

-- "Wearable states" are how RDR3 handles a single item having more than one worn
-- position — e.g. a bandana/neckerchief pulled down around the neck vs pulled up
-- over the face, a hat on the head vs held/hanging. Same shop item hash throughout;
-- only its state changes.
function GetShopItemNumWearableStates(componentHash, isMpFemale)
	return Citizen.InvokeNative(0xFFCC2DB2D9953401, componentHash, isMpFemale, true)
end

function GetShopItemWearableStateByIndex(componentHash, stateIndex, isMpFemale)
	return Citizen.InvokeNative(0x6243635AF2F1B826, componentHash, stateIndex, isMpFemale, true)
end

function UpdateShopItemWearableState(ped, componentHash, wearableState, isMp)
	Citizen.InvokeNative(0x66B957AAC2EAAEAB, ped, componentHash, wearableState, 0, isMp, 1)
end

-- Body/face build presets — a completely different system from the shop-item
-- component slots above: `component` is a plain fixed index (not a hash) into a
-- small internal table. Per RDR3's own native comment: body build is component
-- 124-128 for mp_male / 110-115 for mp_female; face build is a separate 110-123 /
-- 96-109 range. Multiple ranges stack independently. In practice (confirmed by
-- testing) this only ever visibly affects the head/face — see EquipMetaPedOutfit
-- below for what actually reshapes the body.
function EquipMetaPedOutfitExtra(ped, component)
	Citizen.InvokeNative(0xA5BAE410B03E7371, ped, component, 0, 1)
end

-- The native RDR3's own MP character creator actually uses for body build/weight:
-- unlike EquipMetaPedOutfitExtra above (a raw preset index, face-only in practice),
-- this takes a real shop-item hash — the "build" and "waist" options are just
-- ordinary component hashes (see CUSTOM_BODY_BUILD_HASHES/CUSTOM_WAIST_HASHES in
-- peds.lua) equipped through the "meta ped outfit" system rather than
-- ApplyShopItemToPed's plain component slot.
function EquipMetaPedOutfit(ped, componentHash)
	Citizen.InvokeNative(0x1902C4CFCC5BE57C, ped, componentHash)
end

-- RDR3's "head overlay" (makeup) texture system — how eyebrows, blush, lipstick,
-- freckles, ageing etc. actually get drawn. Unlike the shop-item components above,
-- these aren't baked into a head template's texture; a head with no overlay applied
-- can render with no eyebrows at all. The natives build a standalone composited
-- texture (base head albedo/normal/material + N overlay layers), then hand it to a
-- ped's "heads" component to display. Wrapped for ApplyEyebrows in peds.lua.

-- Creates a new texture override (base head albedo/normal/material) and returns its
-- handle. Up to 32 can exist at once across all peds — release ones no longer needed.
function RequestPedHeadTexture(albedoHash, normalHash, materialHash)
	return Citizen.InvokeNative(0xC5E7204F322E49EB, albedoHash, normalHash, materialHash)
end

-- Removes every overlay layer from a texture override (does not free the handle).
function ClearPedHeadTexture(textureId)
	Citizen.InvokeNative(0xB63B9178D0F58D82, textureId)
end

-- Frees a texture override created by RequestPedHeadTexture.
function ReleasePedHeadTexture(textureId)
	Citizen.InvokeNative(0x6BEFAA907B076859, textureId)
end

-- Adds one overlay layer (e.g. one eyebrow style) to a texture override and returns
-- its layer index, used by the Set*Layer* calls below.
function AddPedHeadTextureLayer(textureId, albedoHash, normalHash, materialHash, blendType, texAlpha, sheetGridIndex)
	return Citizen.InvokeNative(0x86BB5FF45F193A02, textureId, albedoHash, normalHash, materialHash, blendType, texAlpha, sheetGridIndex)
end

function SetPedHeadTextureLayerPalette(textureId, layerId, paletteHash)
	Citizen.InvokeNative(0x1ED8588524AC9BE1, textureId, layerId, paletteHash)
end

function SetPedHeadTextureLayerTint(textureId, layerId, primary, secondary, tertiary)
	Citizen.InvokeNative(0x2DF59FFE6FFD6044, textureId, layerId, primary, secondary, tertiary)
end

function SetPedHeadTextureLayerSheetGridIndex(textureId, layerId, index)
	Citizen.InvokeNative(0x3329AAE2882FC8E4, textureId, layerId, index)
end

function SetPedHeadTextureLayerAlpha(textureId, layerId, alpha)
	Citizen.InvokeNative(0x6C76BC24F8BB709A, textureId, layerId, alpha)
end

function IsPedHeadTextureValid(textureId)
	return Citizen.InvokeNative(0x31DC8D3F216D8509, textureId)
end

-- Must be called once after building/editing a texture override, or its component
-- renders solid black — also what actually pushes overlay edits to the GPU texture.
function UpdatePedHeadTexture(textureId)
	Citizen.InvokeNative(0x92DAABA2C1C10B0E, textureId)
end

function ApplyPedHeadTexture(ped, componentHash, textureId)
	Citizen.InvokeNative(0x0B46E25761519058, ped, componentHash, textureId)
end

-- Sets a facial "mood" (happy, angry, scared...) for THIS FRAME ONLY — like most
-- "this frame" RDR3/GTA natives it has to be called every tick to stay applied,
-- it isn't a persistent state change.
function RequestPedFacialMoodThisFrame(ped, moodHash, p2)
	Citizen.InvokeNative(0x8B3B71C80A29A4BB, ped, moodHash, p2 or 6)
end

function BlipAddForEntity(blipHash, entity)
	return Citizen.InvokeNative(0x23F74C2FDA6E7C61, blipHash, entity)
end

-- Bit 0x04 on the horse's internal component flags, marking it as under scripted
-- control. Without this the game doesn't know a *scripted* seating is legit, so a
-- later scripted movement task (see StartMovement in behavior.lua) picks generic
-- ped-walk locomotion instead of the mounted gait, and the rider pops out of the
-- seat pose into a T-pose the moment the horse starts moving. No effect on non-horses.
function SetHorseScriptedFlag(mount, toggle)
	Citizen.InvokeNative(0xB8AB265426CFE6DD, mount, toggle)
end

-- Confirmed against Rockstar's own decompiled mounted-patrol AI script
-- (region_law_patrol_creator.ysc.c): the mount/seat relationship is a persistent
-- attachment state, independent of the task system, so a plain pedestrian navmesh
-- task on the RIDER makes the engine route locomotion through the horse it's
-- already seated on automatically — no mount-aware task or flag needed on the
-- horse itself. See StartMovement in behavior.lua.
function TaskFollowNavMeshToCoord(ped, x, y, z, speed, timeout, stoppingRange, flags, heading)
	Citizen.InvokeNative(0x15D3A79D4E44B913, ped, x, y, z, speed, timeout, stoppingRange, flags, heading)
end

function SetPedOnMount(ped, mount, seatIndex, p3)
	Citizen.InvokeNative(0x028F76B6E78246EB, ped, mount, seatIndex, p3)
	SetHorseScriptedFlag(mount, true)

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
