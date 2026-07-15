-- ============================================================================
-- spooner :: client/nui_entity.lua
-- Entity manipulation NUI callbacks (attach, health, visibility, tasks, weapons, lights, config flags, etc.)
--
-- Part of the split client.lua. All spooner client modules share one Lua state
-- and _G, so globals defined in any module are visible to the others.
-- ============================================================================

RegisterNUICallback('requestControl', function(data, cb)
	if CanModifyEntity(data.handle) then
		RequestControl(data.handle)
	end
	cb({})
end)

RegisterNUICallback('getDatabase', function(data, cb)
	UpdateDatabase()
	cb({
		properties = json.encode(GetEntityProperties(data.handle)),
		database = json.encode(Database)
	})
end)

RegisterNUICallback('attachTo', function(data, cb)
	if Permissions.properties.attachments and CanModifyEntity(data.from) then
		local from = data.from
		local to = data.to
		local bone = data.bone
		local useSoftPinning = data.useSoftPinning
		local collision = data.collision
		local vertex = data.vertex
		local fixedRot = data.fixedRot

		if not to then
			local props = GetEntityProperties(from)

			if props.attachment.to ~= 0 then
				to = props.attachment.to
			else
				cb({})
				return
			end
		end

		local x, y, z, pitch, roll, yaw

		if data.keepPos then
			local x1, y1, z1 = table.unpack(GetEntityCoords(from))
			x, y, z = table.unpack(GetOffsetFromEntityGivenWorldCoords(to, x1, y1, z1))
			pitch, roll, yaw = table.unpack(GetEntityRotation(from, 2) - GetEntityRotation(to, 2))
		else
			x = data.x and data.x * 1.0 or 0.0
			y = data.y and data.y * 1.0 or 0.0
			z = data.z and data.z * 1.0 or 0.0
			pitch = data.pitch and data.pitch * 1.0 or 0.0
			roll = data.roll and data.roll * 1.0 or 0.0
			yaw = data.yaw and data.yaw * 1.0 or 0.0
		end

		if type(bone) == 'number' then
			bone = FindBoneName(to, bone)
		end

		RequestControl(from)
		AttachEntity(from, to, bone, x, y, z, pitch, roll, yaw, useSoftPinning, collision, vertex, fixedRot)
	end

	cb({})
end)

RegisterNUICallback('closeMenu', function(data, cb)
	SetNuiFocus(false, false)
	cb({})
end)

function TryDetach(handle)
	if Permissions.properties.attachments and CanModifyEntity(handle) then
		RequestControl(handle)
		DetachEntity(handle, false, true)

		if EntityIsInDatabase(handle) then
			AddEntityToDatabase(handle, nil, {
				to = 0,
				x = 0.0,
				y = 0.0,
				z = 0.0,
				pitch = 0.0,
				roll = 0.0,
				yaw = 0.0
			})
		end
	end
end

RegisterNUICallback('detach', function(data, cb)
	TryDetach(data.handle)
	cb({})
end)

RegisterNUICallback('setEntityHealth', function(data, cb)
	if Permissions.properties.health and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetEntityHealth(data.handle, data.health, 0)
	end
	cb({})
end)

RegisterNUICallback('setEntityVisible', function(data, cb)
	if Permissions.properties.visible and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetEntityVisible(data.handle, true)
	end
	cb({})
end)

RegisterNUICallback('setEntityInvisible', function(data, cb)
	if Permissions.properties.visible and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetEntityVisible(data.handle, false)
	end
	cb({})
end)

RegisterNUICallback('gravityOn', function(data, cb)
	if Permissions.properties.gravity and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetEntityHasGravity(data.handle, true)
	end
	cb({})
end)

RegisterNUICallback('gravityOff', function(data, cb)
	if Permissions.properties.gravity and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetEntityHasGravity(data.handle, false)
	end
	cb({})
end)

-- A scenario spawns its own props (a bottle, a book, a broom...) as plain game
-- objects attached to the ped — NOT spooner-tracked entities, so GetAttachedChildren
-- (which reads the Database) never sees them, and clearing the ped's tasks doesn't
-- always destroy them (a bottle in particular tends to stay stuck on the ped). Sweep
-- the object pool for anything attached to this ped that spooner doesn't own and
-- delete it. Call this WHILE the prop is still attached (before clearing tasks), or
-- the prop may have already detached and no longer resolve back to the ped.
function RemoveScenarioProps(ped)
	if not DoesEntityExist(ped) then
		return
	end

	for _, obj in ipairs(GetGamePool('CObject')) do
		if DoesEntityExist(obj) and GetEntityAttachedTo(obj) == ped and not EntityIsInDatabase(obj) then
			SetEntityAsMissionEntity(obj, true, true)
			DeleteEntity(obj)
		end
	end
end

RegisterNUICallback('performScenario', function(data, cb)
	if Permissions.properties.ped.scenario and CanModifyEntity(data.handle) then
		local oldScenario = Database[data.handle] and Database[data.handle].scenario

		RequestControl(data.handle)

		-- Remove props that were attached to the ped before the new scenario
		for _, child in ipairs(GetAttachedChildren(data.handle)) do
			RemoveEntity(child)
		end

		-- Delete the old scenario's own game-spawned props (bottle, etc.) while they're
		-- still attached, before the task clear below (see RemoveScenarioProps).
		RemoveScenarioProps(data.handle)

		-- Abruptly end the current scenario so its prop is cleaned up
		ClearPedTasksImmediately(data.handle)

		-- Wait until the ped has actually left the old scenario, otherwise the
		-- new scenario won't spawn its own prop on the first try
		if oldScenario then
			local hash = GetHashKey(oldScenario)
			local tries = 0
			while IsPedUsingScenarioHash(data.handle, hash) and tries < 20 do
				Wait(25)
				tries = tries + 1
			end
		end

		Wait(100)

		startScenario(data.handle, data.scenario)

		if Database[data.handle] then
			Database[data.handle].animation = nil
			Database[data.handle].scenario = data.scenario
		end
	end

	cb({})
end)

-- Returns the categorized emote list (data/rdr3/emotes.lua) for the UI to render.
-- RDR3-only; on GTA the Emotes global is never defined, so this hands back an empty
-- list and the menu button stays effectively unusable.
RegisterNUICallback('getEmotes', function(data, cb)
	cb(json.encode(Emotes or {}))
end)

RegisterNUICallback('performEmote', function(data, cb)
	if Permissions.properties.ped.scenario and CanModifyEntity(data.handle) and data.emote then
		RequestControl(data.handle)

		-- An emote is a full-body scripted clip like a scenario/animation — clear
		-- whatever pose is running first so it doesn't fight the emote, and drop the
		-- other two so only one "pose" is ever the stored/re-applied one.
		ClearPedTasksImmediately(data.handle)
		Wait(50)

		-- Set the stored emote BEFORE playing: PlayEmote's loop thread keeps going
		-- only while Database[ped].emote still equals this one, so it has to be in
		-- place first.
		if Database[data.handle] then
			Database[data.handle].animation = nil
			Database[data.handle].scenario = nil
			Database[data.handle].emote = data.emote
		end

		PlayEmote(data.handle, data.emote)
	end

	cb({})
end)

RegisterNUICallback('stopEmote', function(data, cb)
	if Permissions.properties.ped.scenario and CanModifyEntity(data.handle) then
		RequestControl(data.handle)

		if Database[data.handle] then
			Database[data.handle].emote = nil
		end

		StopEmoteLoop(data.handle)
		ClearPedTasksImmediately(data.handle)
	end

	cb({})
end)

function TryClearTasks(handle)
	if Permissions.properties.ped.clearTasks and CanModifyEntity(handle) then
		RequestControl(handle)

		-- Delete the scenario's own game-spawned prop (bottle, etc.) while it's still
		-- attached, before the task clear releases it (see RemoveScenarioProps). This
		-- is the Stop Scenario path.
		RemoveScenarioProps(handle)

		ClearPedTasks(handle)

		if Database[handle] then
			Database[handle].scenario = nil
			Database[handle].animation = nil
			Database[handle].emote = nil
		end
	end
end

function TryStopEntityAnim(handle)
	local animation = GetAnimationInfo(handle)
	if animation then
		StopEntityAnim(handle, animation.name, animation.dict, -1000.0)
	end
	if Database[handle] then
		Database[handle].scenario = nil
		Database[handle].animation = nil
		Database[handle].emote = nil
	end
end

RegisterNUICallback('clearPedTasks', function(data, cb)
	TryClearTasks(data.handle)
	cb({})
end)

-- Clear the ped's tasks (stops animation/scenario) and delete every prop
-- attached to it.
RegisterNUICallback('clearTasksAndProps', function(data, cb)
	local entity = data.handle

	if Permissions.properties.ped.clearTasks and CanModifyEntity(entity) then
		RequestControl(entity)

		-- Delete the scenario's game-spawned props (bottle, etc.) while still attached,
		-- before the task clear releases them.
		RemoveScenarioProps(entity)

		-- Abrupt clear so a scenario instantly releases/cleans its own prop
		ClearPedTasksImmediately(entity)

		if Database[entity] then
			Database[entity].scenario = nil
			Database[entity].animation = nil
			Database[entity].emote = nil
		end
	end

	-- Delete every prop attached to the ped via the spooner
	for _, child in ipairs(GetAttachedChildren(entity)) do
		RemoveEntity(child)
	end

	cb({})
end)

RegisterNUICallback('clearPedTasksImmediately', function(data, cb)
	if Permissions.properties.ped.clearTasks and CanModifyEntity(data.handle) then
		RequestControl(data.handle)

		-- Delete the scenario's game-spawned props while still attached (see
		-- RemoveScenarioProps), before the abrupt clear.
		RemoveScenarioProps(data.handle)

		ClearPedTasksImmediately(data.handle)

		if Database[data.handle] then
			Database[data.handle].scenario = nil
			Database[data.handle].animation = nil
			Database[data.handle].emote = nil
		end
	end

	cb({})
end)

RegisterNUICallback('setOutfit', function(data, cb)
	if Permissions.properties.ped.outfit and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetPedOutfitPreset(data.handle, data.outfit)

		if EntityIsInDatabase(data.handle) then
			Database[data.handle].outfit = data.outfit
		end
	end

	cb({})
end)

function AddToGroup(ped)
	local group = GetPlayerGroup(PlayerId())
	SetPedAsGroupMember(ped, group)
	SetGroupSeparationRange(group, -1)
	SetPedCanTeleportToGroupLeader(ped, group, true)
	BlipAddForEntity(Config.GroupMemberBlipSprite, ped)
end

RegisterNUICallback('addToGroup', function(data, cb)
	if Permissions.properties.ped.group and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		AddToGroup(data.handle)
	end
	cb({})
end)

RegisterNUICallback('removeFromGroup', function(data, cb)
	if Permissions.properties.ped.group and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		RemovePedFromGroup(data.handle)
		RemoveBlip(GetBlipFromEntity(data.handle))
	end
	cb({})
end)

RegisterNUICallback('collisionOn', function(data, cb)
	if Permissions.properties.collision and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetEntityCollision(data.handle, true, true)
	end
	cb({})
end)

RegisterNUICallback('collisionOff', function(data, cb)
	if Permissions.properties.collision and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetEntityCollision(data.handle, false, false)
	end
	cb({})
end)

RegisterNUICallback('giveWeapon', function(data, cb)
	if Permissions.properties.ped.weapon and CanModifyEntity(data.handle) then
		RequestControl(data.handle)

		if Config.isRDR then
			GiveWeaponToPed_2(data.handle, GetHashKey(data.weapon), 500, true, false, 0, false, 0.5, 1.0, 0, false, 0.0, false)
		else
			GiveWeaponToPed(data.handle, GetHashKey(data.weapon), 500, false, true)
		end

		if Database[data.handle] then
			table.insert(Database[data.handle].weapons, data.weapon)
		end
	end
	cb({})
end)

RegisterNUICallback('removeAllWeapons', function(data, cb)
	if Permissions.properties.ped.weapon and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		RemoveAllPedWeapons(data.handle, true, true)

		if Database[data.handle] then
			Database[data.handle].weapons = {}
		end
	end
	cb({})
end)

-- Holster/sheath whatever weapon the ped is currently holding — it goes back to
-- its holster/back slot on the body instead of being deleted (unlike Remove All
-- Weapons, the ped keeps the weapon, it's just no longer drawn/in hand).
RegisterNUICallback('holsterWeapon', function(data, cb)
	if Permissions.properties.ped.weapon and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetCurrentPedWeapon(data.handle, GetHashKey('WEAPON_UNARMED'), true)
	end
	cb({})
end)

RegisterNUICallback('resurrectPed', function(data, cb)
	if Permissions.properties.ped.resurrect and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		ResurrectPed(data.handle)
	end
	cb({})
end)

RegisterNUICallback('setOnMount', function(data, cb)
	if Permissions.properties.ped.mount and CanModifyEntity(data.handle) then
		SetPedOnMount(data.handle, data.entity, -1, false)
	end
	cb({})
end)

RegisterNUICallback('engineOn', function(data, cb)
	if Permissions.properties.vehicle.engine and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetVehicleEngineOn(data.handle, true, true)
	end
	cb({})
end)

RegisterNUICallback('engineOff', function(data, cb)
	if Permissions.properties.vehicle.engine and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetVehicleEngineOn(data.handle, false, true)
	end
	cb({})
end)

RegisterNUICallback('setLightsIntensity', function(data, cb)
	if Permissions.properties.lights and CanModifyEntity(data.handle) then
		local intensity = data.intensity and data.intensity * 1.0 or 0.0

		RequestControl(data.handle)
		SetLightsIntensityForEntity(data.handle, intensity)

		if EntityIsInDatabase(data.handle) then
			Database[data.handle].lightsIntensity = intensity
		end
	end

	cb({})
end)

RegisterNUICallback('setLightsColour', function(data, cb)
	if Permissions.properties.lights and CanModifyEntity(data.handle) then
		local red = data.red and data.red or 0
		local green = data.green and data.green or 0
		local blue = data.blue and data.blue or 0

		RequestControl(data.handle)
		SetLightsColorForEntity(data.handle, red, green, blue)

		if EntityIsInDatabase(data.handle) then
			Database[data.handle].lightsColour = {
				red = red,
				green = green,
				blue = blue
			}
		end
	end

	cb({})
end)

RegisterNUICallback('setLightsType', function(data, cb)
	if Permissions.properties.lights and CanModifyEntity(data.handle) then
		local type = data.type and data.type or 0

		RequestControl(data.handle)
		SetLightsTypeForEntity(data.handle, type)

		if EntityIsInDatabase(data.handle) then
			Database[data.handle].lightsType = type
		end
	end

	cb({})
end)

RegisterNUICallback('setVehicleLightsOn', function(data, cb)
	if Permissions.properties.vehicle.lights and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetVehicleLights(data.handle, false)
	end
	cb({})
end)

RegisterNUICallback('setVehicleLightsOff', function(data, cb)
	if Permissions.properties.vehicle.lights and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetVehicleLights(data.handle, true)
	end
	cb({})
end)

RegisterNUICallback('aiOn', function(data, cb)
	if Permissions.properties.ped.ai and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetBlockingOfNonTemporaryEvents(data.handle, false)

		if Database[data.handle] then
			Database[data.handle].blockNonTemporaryEvents = false
		end
	end

	cb({})
end)

RegisterNUICallback('aiOff', function(data, cb)
	if Permissions.properties.ped.ai and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetBlockingOfNonTemporaryEvents(data.handle, true)

		if Database[data.handle] then
			Database[data.handle].blockNonTemporaryEvents = true
		end
	end

	cb({})
end)

RegisterNUICallback('setPlayerModel', function(data, cb)
	if Permissions.properties.ped.changeModel and data.modelName then
		local model = ResolveModelHash(data.modelName)

		if LoadModel(model) then
			SetPlayerModel(PlayerId(), model, true)
		end
	end
	cb({
		handle = PlayerPedId()
	})
end)

RegisterNUICallback('playAnimation', function(data, cb)
	if Permissions.properties.ped.animation and CanModifyEntity(data.handle) then
		local blendInSpeed = data.blendInSpeed and data.blendInSpeed * 1.0 or 1.0
		local blendOutSpeed = data.blendOutSpeed and data.blendOutSpeed * 1.0 or 1.0
		local duration = data.duration and data.duraction or -1
		local flag = data.flag and data.flag or 1
		local playbackRate = data.playbackRate and data.playbackRate * 1.0 or 0.0

		RequestControl(data.handle)

		local animation = {
			dict = data.dict,
			name = data.name,
			blendInSpeed = blendInSpeed,
			blendOutSpeed = blendOutSpeed,
			duration = duration,
			flag = flag,
			playbackRate = playbackRate,
			filter = data.filter
		}

		if PlayAnimation(data.handle, animation) and Database[data.handle] then
			Database[data.handle].animation = animation
			Database[data.handle].scenario = nil
		end

		-- Always store animation info
		-- Later it can be needed for animation stop and copy to clipboard
		StoreAnimationInfo(data.handle, animation)

		-- Update the "Clear Tasks" prompt right here instead of only relying on the
		-- periodic Database-driven refresh (UpdateDbEntities): that loop only looks
		-- at entities actually tracked in Database, and the player's own ped isn't
		-- always in there (e.g. if "Add to DB" was never used on yourself), so the
		-- prompt could get stuck on even for an Allow-Running (non-blocking) anim.
		if Config.isRDR and ClearTasksPrompt and data.handle == PlayerPedId() then
			if animation.filter == 'BONEMASK_UPPERONLY' then
				if ClearTasksPrompt:isEnabled() then
					ClearTasksPrompt:setEnabledAndVisible(false)
				end
			elseif Permissions.properties.ped.clearTasks and not ClearTasksPrompt:isEnabled() then
				ClearTasksPrompt:setEnabledAndVisible(true)
			end
		end
	end

	cb({})
end)

-- Return the animation currently applied to an entity so the UI can store it
-- and later re-apply it via the normal playAnimation flow (paste).
RegisterNUICallback('copyAnimation', function(data, cb)
	local entity = data.handle
	local anim = GetAnimationInfo(entity)

	-- Fallback: the animation may still be stored on the entity's database entry
	if not anim and Database[entity] then
		anim = Database[entity].animation
	end

	if anim and anim.dict and anim.name then
		cb({
			ok           = true,
			dict         = anim.dict,
			name         = anim.name,
			blendInSpeed = anim.blendInSpeed,
			blendOutSpeed = anim.blendOutSpeed,
			duration     = anim.duration,
			flag         = anim.flag,
			playbackRate = anim.playbackRate,
			filter       = anim.filter
		})
	else
		cb({ ok = false })
	end
end)

-- Return the scenario an entity is running so the UI can re-apply it (paste).
-- For world/ambient peds we detect it by testing every known scenario hash.
RegisterNUICallback('copyScenario', function(data, cb)
	local entity = data.handle

	if not DoesEntityExist(entity) then
		return cb({ ok = false })
	end

	-- 1) Scenario we applied via the spooner
	local scenario = Database[entity] and Database[entity].scenario

	-- 2) Otherwise try to detect a world ped's active scenario
	if not scenario and Scenarios then
		for _, name in ipairs(Scenarios) do
			if IsPedUsingScenarioHash(entity, GetHashKey(name)) then
				scenario = name
				break
			end
		end
	end

	if scenario then
		cb({ ok = true, scenario = scenario })
	else
		cb({ ok = false })
	end
end)

RegisterNUICallback('loadPermissions', function(data, cb)
	cb(json.encode(Permissions))
end)

RegisterNUICallback('knockOffProps', function(data, cb)
	if Permissions.properties.ped.knockOffProps and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		KnockOffPedProp(data.handle, true, true, true, true)
	end

	cb({})
end)

RegisterNUICallback('setWalkStyle', function(data, cb)
	if Permissions.properties.ped.walkStyle and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetWalkStyle(data.handle, data.base, data.style)
	end

	cb({})
end)

RegisterNUICallback('setStoreDeleted', function(data, cb)
	if StoreDeleted then
		StoreDeleted = false
		DeletedEntities = {}
	else
		StoreDeleted = true
	end

	cb({})
end)

RegisterNUICallback('clonePedToTarget', function(data, cb)
	if Permissions.properties.ped.cloneToTarget and CanModifyEntity(data.target) then
		RequestControl(data.target)
		ClonePedToTarget(data.handle, data.target)
	end

	cb({})
end)

RegisterNUICallback('lookAtEntity', function(data, cb)
	if Permissions.properties.ped.lookAtEntity and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		TaskLookAtEntity(data.handle, data.target, -1)
	end

	cb({})
end)

RegisterNUICallback('clearLookAt', function(data, cb)
	if Permissions.properties.ped.lookAtEntity and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		TaskClearLookAt(data.handle)
	end

	cb({})
end)

RegisterNUICallback('registerAsNetworked', function(data, cb)
	if Permissions.properties.registerAsNetworked and CanModifyEntity(data.handle) then
		NetworkRegisterEntityAsNetworked(data.handle)
	end

	cb({})
end)

RegisterNUICallback('saveFavourites', function(data, cb)
	SetResourceKvp('favourites', json.encode(data.favourites))
	cb({})
end)

RegisterNUICallback('cleanPed', function(data, cb)
	if Permissions.properties.ped.clean and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		ClearPedEnvDirt(data.handle)
		ClearPedDamageDecalByZone(data.handle, 10, "ALL")
		ClearPedBloodDamage(data.handle)
	end
	cb({})
end)

RegisterNUICallback('setScale', function(data, cb)
	if Permissions.properties.ped.scale and CanModifyEntity(data.handle) then
		local scale = data.scale or 1.0

		if scale < 0.1 then
			scale = 0.1
		elseif scale > 10.0 then
			scale = 10.0
		end

		RequestControl(data.handle)
		SetPedScale(data.handle, scale + 0.0)

		if Database[data.handle] then
			Database[data.handle].scale = scale
		end
	end

	cb({})
end)

RegisterNUICallback('selectEntity', function(data, cb)
	if CanModifyEntity(data.handle) then
		TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
		if AttachedEntity == data.handle then
			AttachedEntity = nil
		else
			if not Cam then
				EnableSpoonerMode()
			end

			AttachedEntity = data.handle
			TriggerEvent('spooner:onEntitySelected', AttachedEntity)
		end
	end
	cb({})
end)

function TryClonePed(handle)
	if Permissions.properties.ped.clone and CanModifyEntity(handle) then
		RequestControl(handle)
		local clone = CloneEntity(handle)
		Citizen.Wait(500)
		ClonePedToTarget(handle, clone)
	end
end

RegisterNUICallback('clonePed', function(data, cb)
	TryClonePed(data.handle)
	cb({})
end)

function GetPedConfigFlagsWithDescr(ped)
	local flags = GetPedConfigFlags(ped)

	local flagsWithDescr = {}

	for flag, value in pairs(flags) do
		local descr = PedConfigFlags[flag]

		if descr then
			flagsWithDescr[tostring(flag)] = {descr = descr, value = value}
		elseif value then
			flagsWithDescr[tostring(flag)] = {descr = "", value = true}
		end
	end

	return flagsWithDescr
end

RegisterNUICallback('getPedConfigFlags', function(data, cb)
	cb(GetPedConfigFlagsWithDescr(data.handle))
end)

function TrySetPedConfigFlag(handle, flag, value)
	if Permissions.properties.ped.configFlags and CanModifyEntity(handle) then
		RequestControl(handle)
		SetPedConfigFlag(handle, flag, value)
	end
end

RegisterNUICallback('setPedConfigFlag', function(data, cb)
	TrySetPedConfigFlag(data.handle, data.flag, data.value)
	cb(GetPedConfigFlagsWithDescr(data.handle))
end)

function TryGoToWaypoint(handle)
	if Permissions.properties.ped.goToWaypoint and CanModifyEntity(handle) then
		RequestControl(handle)

		local coords = GetWaypointCoords()
		local groundZ = GetHeightmapBottomZForPosition(coords.x, coords.y)

		local vehicle = GetVehiclePedIsIn(handle, false)

		if vehicle == 0 then
			TaskGoToCoordAnyMeans(handle, coords.x, coords.y, groundZ, 1.0, 0, 0, 0, 0.5)
		else
			TaskVehicleDriveToCoord(handle, vehicle, coords.x, coords.y, groundZ, 2.0, 0, GetEntityModel(vehicle), 67108864, 0.5, 0.0)
		end
	end
end

RegisterNUICallback('goToWaypoint', function(data, cb)
	TryGoToWaypoint(data.handle)
	cb({})
end)

function TryPedGoToEntity(handle, entity)
	if Permissions.properties.ped.goToEntity and CanModifyEntity(handle) then
		RequestControl(handle)

		local vehicle = GetVehiclePedIsIn(handle, false)

		if vehicle == 0 then
			TaskGoToEntity(handle, entity, -1, 1.0, 1.0, 0.0, 0)
		else
			TaskVehicleDriveToCoord(handle, vehicle, GetEntityCoords(entity), 2.0, 0, GetEntityModel(vehicle), 67108864, 0.5, 0.0)
		end
	end
end

RegisterNUICallback('pedGoToEntity', function(data, cb)
	TryPedGoToEntity(data.handle, data.entity)
	cb({})
end)

function FocusEntity(entity)
	FocusTarget = entity
	FocusTargetPos = GetEntityCoords(entity)

	if not FreeFocus then
		StopCamPointing(Cam)
		PointCamAtEntity(Cam, entity)
	end
end

function UnfocusEntity()
	FocusTarget = nil
	StopCamPointing(Cam)
end

function TryFocusEntity(handle)
	if Permissions.properties.focus then
		if not Cam then
			EnableSpoonerMode()
		end

		FocusEntity(handle)
	end
end

RegisterNUICallback('focusEntity', function(data, cb)
	if FocusTarget == data.handle then
		UnfocusEntity()
	else
		TryFocusEntity(data.handle)
	end

	cb({})
end)

function TryEnterVehicle(handle, entity)
	if Permissions.properties.ped.enterVehicle and CanModifyEntity(handle) then
		if IsVehicleSeatFree(entity, -1) then
			TaskWarpPedIntoVehicle(handle, entity, -1)
		else
			TaskWarpPedIntoVehicle(handle, entity, -2)
		end
	end
end

RegisterNUICallback('enterVehicle', function(data, cb)
	TryEnterVehicle(data.handle, data.entity)
	cb({})
end)

-- Temporary function to migrate old kvs keys of DBs to the new kvs key format
function MigrateOldSavedDbs()
	local handle = StartFindKvp("")

	while true do
		local kvp = FindKvp(handle)

		if kvp then
			if kvp ~= 'favourites' and string.sub(kvp, 1, 3) ~= 'DB_' and not GetResourceKvpString('DB_' .. kvp) then
				SetResourceKvp('DB_' .. kvp, GetResourceKvpString(kvp))
				print('Migrated old DB: ' .. kvp)
				DeleteResourceKvp(kvp)
			end
		else
			break
		end
	end

	EndFindKvp(handle)
end
RegisterCommand('spooner_migrate_old_dbs', function(source, args, raw)
	MigrateOldSavedDbs()
end)


-- ============================================================================
-- Merged from the former client_extended.lua
-- ============================================================================

RegisterNUICallback('getAttachmentSettings', function(data, cb)
	local props = GetEntityProperties(data.handle)
	if not props or not props.attachment or props.attachment.to == 0 then return cb({value = 'nil'}) end
	
	local from = data.handle
	local clipboard = ('AttachEntityToEntity(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)'):format(
		GetAttachValues(from, props.attachment.to, props.attachment.bone, props.attachment.x, props.attachment.y, props.attachment.z, props.attachment.pitch, props.attachment.roll, props.attachment.yaw, props.attachment.useSoftPinning, props.attachment.collision, props.attachment.vertex, props.attachment.fixedRot)
	)
	cb({value = clipboard})
end)

----------------
-- Animations --
----------------

local animationInfo = {}

function StoreAnimationInfo(entity, animation)
	animationInfo[tostring(entity)] = animation
end

function GetAnimationInfo(entity)
	return animationInfo[tostring(entity)]
end

RegisterNUICallback('getAnimationSettings', function(data, cb)
	local animation = GetAnimationInfo(data.handle)
	if not animation then return cb({value = 'nil'}) end
	
	local entity = data.handle
	local clipboard = ''
	if GetEntityType(entity) == 3 then
		clipboard = ("PlayEntityAnim(%s, '%s', '%s', %s, %s, %s, %s, %s, %s)"):format(
			GetAnimationValues(entity, animation)
		)
	else
		clipboard = ("TaskPlayAnim(%s, '%s', '%s', %s, %s, %s, %s, %s, %s, %s, %s, '%s', %s)"):format(
			GetAnimationValues(entity, animation)
		)
	end

	cb({value = clipboard})
end)

RegisterNUICallback('stopAnimation', function(data, cb)
	local entity = data.handle
	ClearPausedAnimation(entity)
	if GetEntityType(entity) == 3 then -- object
		TryStopEntityAnim(entity)
	else -- ped
		TryClearTasks(entity)
	end
	cb({})
end)

----------------------------
-- Animation Timeline/Pause
----------------------------

local PausedAnimations = {}

function IsAnimationPaused(entity)
	return PausedAnimations[entity] ~= nil
end

function ClearPausedAnimation(entity)
	PausedAnimations[entity] = nil
end

-- Ensures the clip is an active anim task on the entity so its playback speed and
-- current time can be manipulated. Returns false if it couldn't be (re)applied.
local function EnsureAnimPlaying(entity, anim)
	if IsEntityPlayingAnim(entity, anim.dict, anim.name, 3) then
		return true
	end
	PlayAnimation(entity, anim)
	Wait(0)
	return IsEntityPlayingAnim(entity, anim.dict, anim.name, 3)
end

-- Freeze the currently-playing clip in place at the given phase [0..1]. Setting the
-- playback speed to 0 holds the pose (instead of clearing the task, which removed
-- the animation entirely and left the ped/object with no pose to scrub).
local function FreezeAnimAt(entity, anim, time)
	SetEntityAnimSpeed(entity, anim.dict, anim.name, 0.0)
	SetEntityAnimCurrentTime(entity, anim.dict, anim.name, time)
end

RegisterNUICallback('pauseAnimation', function(data, cb)
	local entity = data.handle
	local anim = GetAnimationInfo(entity)
	if anim and DoesEntityExist(entity) then
		RequestControl(entity)
		-- Capture the frame the user currently sees (only replay if the clip fell off).
		local time = 0.0
		if EnsureAnimPlaying(entity, anim) then
			time = GetEntityAnimCurrentTime(entity, anim.dict, anim.name)
			FreezeAnimAt(entity, anim, time)
		end
		PausedAnimations[entity] = { dict = anim.dict, name = anim.name, time = time }
	end
	cb({})
end)

RegisterNUICallback('resumeAnimation', function(data, cb)
	local entity = data.handle
	local paused = PausedAnimations[entity]
	if paused and DoesEntityExist(entity) then
		local anim = GetAnimationInfo(entity)
		if anim then
			RequestControl(entity)
			-- Restore playback from the paused frame at the clip's normal speed.
			local rate = anim.playbackRate
			if not rate or rate == 0.0 then rate = 1.0 end
			if EnsureAnimPlaying(entity, anim) then
				SetEntityAnimCurrentTime(entity, anim.dict, anim.name, paused.time)
				SetEntityAnimSpeed(entity, anim.dict, anim.name, rate)
			end
		end
		PausedAnimations[entity] = nil
	end
	cb({})
end)

RegisterNUICallback('setAnimationTime', function(data, cb)
	local entity = data.handle
	local time = data.time * 1.0
	local anim = GetAnimationInfo(entity)
	if anim and DoesEntityExist(entity) then
		RequestControl(entity)
		if PausedAnimations[entity] then
			PausedAnimations[entity].time = time
			-- Keep the clip frozen while scrubbing to the requested frame.
			if EnsureAnimPlaying(entity, anim) then
				FreezeAnimAt(entity, anim, time)
			end
		else
			SetEntityAnimCurrentTime(entity, anim.dict, anim.name, time)
		end
	end
	cb({})
end)

RegisterNUICallback('getAnimationTime', function(data, cb)
	local entity = data.handle
	local anim = GetAnimationInfo(entity)
	local time = 0.0
	local isPaused = PausedAnimations[entity] ~= nil
	if isPaused then
		time = PausedAnimations[entity].time
	elseif anim and DoesEntityExist(entity) then
		time = GetEntityAnimCurrentTime(entity, anim.dict, anim.name)
	end
	cb({ time = time, isPaused = isPaused, hasAnimation = anim ~= nil })
end)

----------------------
-- Entity Offset Tool
----------------------

RegisterNUICallback('getEntityOffset', function(data, cb)
	local entity = data.handle
	local reference = data.reference

	if DoesEntityExist(entity) and DoesEntityExist(reference) then
		local pos1 = GetEntityCoords(entity)
		local pos2 = GetEntityCoords(reference)
		local rot1 = GetEntityRotation(entity, 2)
		local rot2 = GetEntityRotation(reference, 2)

		local localOffset = GetOffsetFromEntityGivenWorldCoords(reference, pos1.x, pos1.y, pos1.z)

		local dPitch = rot1.x - rot2.x
		local dRoll = rot1.y - rot2.y
		local dYaw = rot1.z - rot2.z

		cb({
			worldX = string.format('%.4f', pos1.x - pos2.x),
			worldY = string.format('%.4f', pos1.y - pos2.y),
			worldZ = string.format('%.4f', pos1.z - pos2.z),
			localX = string.format('%.4f', localOffset.x),
			localY = string.format('%.4f', localOffset.y),
			localZ = string.format('%.4f', localOffset.z),
			dPitch = string.format('%.2f', dPitch),
			dRoll = string.format('%.2f', dRoll),
			dYaw = string.format('%.2f', dYaw),
			distance = string.format('%.4f', #(pos1 - pos2))
		})
	else
		cb({ error = true })
	end
end)

--
RegisterNUICallback('physicsPush', function(data, cb)
	-- TODO: Check Permissions.properties.physics
	if CanModifyEntity(data.handle) then
		RequestControl(data.handle)

		--
		local x, y, z = 0.0, 0.0, -0.5
		local object = data.handle
		unfreezeEntity(object)
		local off = GetObjectOffsetFromCoords(GetEntityCoords(object), GetEntityHeading(object), x*50.0, y*50.0, z*50.0)
        local di = (GetEntityCoords(object) - off) / 10.0
        local s1, s2, s3 = 5.0, 5.0, 5.0
        ApplyForceToEntity(object, 1, di.x * s1, di.y * s2, di.z * s3, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
	end
	cb({})
end)

-- ===================== Ped Emotions (facial mood) =====================
-- RDR3's facial mood system is a "this frame" native — it has to be refreshed
-- every tick to stick, unlike a one-shot animation. ActivePedMoods tracks which
-- peds currently have a mood active; a background thread keeps refreshing them.
-- Hashes are the real fwFacialAnimRequest__Mood enum values (see
-- Halen84/RDR3-Native-Flags-And-Enums) — a curated, recognisable subset of the
-- ~100 that exist (many are combat/horse/weather states, not expressions).
local PedMoods = {
	{ label = 'Normal', hash = 3569615413 },
	{ label = 'Happy', hash = 746733444 },
	{ label = 'Talking Happy', hash = 1697543443 },
	{ label = 'Angry', hash = 137506481 },
	{ label = 'Sad', hash = 1164001287 },
	{ label = 'Scared', hash = 3716590166 },
	{ label = 'Nervous', hash = 3652126712 },
	{ label = 'Confused', hash = 2595289108 },
	{ label = 'Disgust', hash = 1116928067 },
	{ label = 'Shocked', hash = 2583247227 },
	{ label = 'Smug', hash = 3347446607 },
	{ label = 'Cocky', hash = 3070686211 },
	{ label = 'Cautious', hash = 3104036806 },
	{ label = 'Curious', hash = 3537998118 },
	{ label = 'Intimidated', hash = 816500609 },
	{ label = 'Intimidating', hash = 3132314318 },
	{ label = 'Seductive', hash = 456668268 },
	{ label = 'Bitchy', hash = 1201781013 },
	{ label = 'Drunk', hash = 3032813660 },
	{ label = 'Tired', hash = 2403592533 },
	{ label = 'Injured', hash = 3014186447 },
	{ label = 'Cower', hash = 970990189 },
	{ label = 'Panic', hash = 3729996742 },
	{ label = 'Sleeping', hash = 188835728 }
}

local PedMoodsByLabel = {}
for _, mood in ipairs(PedMoods) do
	PedMoodsByLabel[mood.label] = mood.hash
end

ActivePedMoods = ActivePedMoods or {}

CreateThread(function()
	while true do
		for ped, moodHash in pairs(ActivePedMoods) do
			if DoesEntityExist(ped) then
				pcall(RequestPedFacialMoodThisFrame, ped, moodHash)
			else
				ActivePedMoods[ped] = nil
			end
		end

		Wait(0)
	end
end)

RegisterNUICallback('getPedMoods', function(data, cb)
	local labels = {}

	for _, mood in ipairs(PedMoods) do
		table.insert(labels, mood.label)
	end

	cb(json.encode(labels))
end)

RegisterNUICallback('setPedMood', function(data, cb)
	if CanModifyEntity(data.handle) then
		local moodHash = PedMoodsByLabel[data.mood]

		if moodHash then
			ActivePedMoods[data.handle] = moodHash
		end
	end

	cb({})
end)

RegisterNUICallback('clearPedMood', function(data, cb)
	ActivePedMoods[data.handle] = nil
	cb({})
end)
