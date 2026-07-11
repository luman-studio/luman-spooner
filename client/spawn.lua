-- ============================================================================
-- spooner :: client/spawn.lua
-- Spawning objects, vehicles, peds, propsets, particles, pickups; entity removal and KVS helpers
--
-- Part of the split client.lua. All spooner client modules share one Lua state
-- and _G, so globals defined in any module are visible to the others.
-- ============================================================================

function SpawnObject(name, model, x, y, z, pitch, roll, yaw, collisionDisabled, isVisible, lightsIntensity, lightsColour, lightsType)
	if not Permissions.spawn.object then
		return nil
	end

	if IsDatabaseFull() then
		return nil
	end

	if not LoadModel(model) then
		return nil
	end

	local object = CreateObjectNoOffset(model, x, y, z, true, false, true)

	SetModelAsNoLongerNeeded(model)

	if not object or object < 1 then
		return nil
	end

	SetEntityRotation(object, pitch, roll, yaw, 2)

	FreezeEntityPosition(object, true)

	if collisionDisabled then
		SetEntityCollision(object, false, false)
	end

	if isVisible == false then
		SetEntityVisible(object, false)
	end

	if lightsIntensity then
		SetLightsIntensityForEntity(object, lightsIntensity)
	end

	if lightsColour then
		SetLightsColorForEntity(object, lightsColour.red, lightsColour.green, lightsColour.blue)
	end

	if lightsType then
		SetLightsTypeForEntity(object, lightsType)
	end

	AddEntityToDatabase(object, name)

	if not Config.isRDR and Database[object] then
		Database[object].isFrozen = true
	end

	return object
end

function SpawnVehicle(name, model, x, y, z, pitch, roll, yaw, collisionDisabled, isVisible)
	if not Permissions.spawn.vehicle then
		return nil
	end

	if IsDatabaseFull() then
		return nil
	end

	if not LoadModel(model) then
		return nil
	end

	local veh = CreateVehicle(model, x, y, z, 0.0, true, false)

	SetModelAsNoLongerNeeded(model)

	if not veh or veh < 1 then
		return nil
	end

	SetEntityRotation(veh, pitch, roll, yaw, 2)

	if collisionDisabled then
		FreezeEntityPosition(veh, true)
		SetEntityCollision(veh, false, false)
	end

	if isVisible == false then
		SetEntityVisible(veh, false)
	end

	-- Weird fix for the hot air balloon, otherwise it doesn't move with the wind and only travels straight up.
	if model == GetHashKey('hotairballoon01') then
		SetVehicleAsNoLongerNeeded(veh)
	end

	AddEntityToDatabase(veh, name)

	if not Config.isRDR and Database[veh] then
		Database[veh].isFrozen = collisionDisabled
	end

	return veh
end

function PlayAnimation(entity, anim)
	if not DoesAnimDictExist(anim.dict) then
		print('Error: Anim doesnt exist (dict, name)', anim.dict, anim.name)
		return false
	end

	RequestAnimDict(anim.dict)

	while not HasAnimDictLoaded(anim.dict) do
		Wait(0)
	end

	if GetEntityType(entity) == 3 then -- object
		PlayEntityAnim(GetAnimationValues(entity, anim))
	else -- ped
		TaskPlayAnim(GetAnimationValues(entity, anim))
	end

	RemoveAnimDict(anim.dict)

	print('Anim played (dict, name):', anim.dict, anim.name)
	return true
end

function GetAnimationValues(entity, anim)
	if GetEntityType(entity) == 3 then -- object
		return entity, anim.name, anim.dict, anim.blendInSpeed, true, true, false, 0.0, 0
	else -- ped
		-- filter is a bone-mask (e.g. 'BONEMASK_UPPERONLY') so the clip can be played
		-- on the upper body only, leaving the legs free for normal locomotion. Empty
		-- string (default) animates the whole body as before.
		return entity, anim.dict, anim.name, anim.blendInSpeed, anim.blendOutSpeed, anim.duration, anim.flag, anim.playbackRate, false, false, false, anim.filter or '', false
	end
end

-- Global (called from spawn.lua, nui_entity.lua and main.lua)
function startScenario(ped, scenario)
	if Config.isRDR then
		TaskStartScenarioInPlace(ped, GetHashKey(scenario), -1)
	else
		TaskStartScenarioInPlace(ped, scenario, -1)
	end
end

function SpawnPed(props)
	if not Permissions.spawn.ped then
		return nil
	end

	if IsDatabaseFull() then
		return nil
	end

	-- Use specified ped / spawn new one
	if DoesEntityExist(props.handle) then
		ped = props.handle
	else
		if not LoadModel(props.model) then
			return nil
		end

		if Config.isRDR then
			ped = CreatePed_2(props.model, props.x, props.y, props.z, 0.0, true, false)
		else
			ped = CreatePed(0, props.model, props.x, props.y, props.z, 0.0, true, false)
		end
	end

	SetModelAsNoLongerNeeded(props.model)

	if not ped or ped < 1 then
		return nil
	end

	SetEntityRotation(ped, props.pitch, props.roll, props.yaw, 2)

	if props.collisionDisabled then
		FreezeEntityPosition(ped, true)
		SetEntityCollision(ped, false, false)
	end

	if props.isVisible == false then
		SetEntityVisible(ped, false)
	end

	-- keepAppearance is set when spawning from a ClonePed template (MP peds); in that
	-- case the clone already carries the exact look, so don't touch the outfit or it
	-- would be randomised/overwritten.
	if not props.keepAppearance then
		if props.outfit == -1 then
			SetRandomOutfitVariation(ped, true)
		else
			SetPedOutfitPreset(ped, props.outfit)
		end

		-- Without this, RDR3 silently applies the outfit change internally but never
		-- pushes it to the renderer on a freshly spawned ped ("needed after first
		-- creation" per the native's own comment).
		UpdatePedVariation(ped)
	end

	if props.isInGroup then
		AddToGroup(ped)
	end

	if props.animation then
		PlayAnimation(ped, props.animation)
	end

	if props.scenario then
		Wait(500)
		startScenario(ped, props.scenario)
	end

	if props.blockNonTemporaryEvents then
		SetBlockingOfNonTemporaryEvents(ped, true)
	end

	if props.weapons then
		for _, weapon in ipairs(props.weapons) do
			if Config.isRDR then
				GiveWeaponToPed_2(ped, GetHashKey(weapon), 500, true, false, 0, false, 0.5, 1.0, 0, false, 0.0, false)
			else
				GiveWeaponToPed(ped, GetHashKey(weapon), 500, false, true)
			end
		end
	end

	if props.walkStyle then
		SetWalkStyle(ped, props.walkStyle.base, props.walkStyle.style)
	end

	if props.scale then
		SetPedScale(ped, props.scale)
	end

	if props.pedConfigFlags then
		for flag, value in pairs(props.pedConfigFlags) do
			SetPedConfigFlag(ped, tonumber(flag), value)
		end
	end

	AddEntityToDatabase(ped, props.name)
	Database[ped].outfit = props.outfit
	Database[ped].animation = props.animation
	Database[ped].scenario = props.scenario
	Database[ped].blockNonTemporaryEvents = props.blockNonTemporaryEvents
	Database[ped].weapons = props.weapons
	Database[ped].walkStyle = props.walkStyle
	Database[ped].scale = props.scale

	if not Config.isRDR and Database[ped] then
		Database[ped].isFrozen = props.collisionDisabled
	end

	return ped
end

function WaitForPropSetToLoad(propSet)
	local timeWaited = 0

	while not IsPropSetFullyLoaded(propSet) and timeWaited <= 500 do
		Wait(100)
		timeWaited = timeWaited + 100
	end

	return true
end

function SpawnPropset(name, model, x, y, z, heading)
	if not Permissions.spawn.propset then
		return nil
	end

	if IsDatabaseFull() then
		return nil
	end

	-- Spawn the propset
	RequestPropset(model)

	while not HasPropsetLoaded(model) do
		Wait(0)
	end

	local propset = CreatePropset(model, x, y, z, 0, heading, 0.0, false, false)

	ReleasePropset(hash)

	if not propset or propset < 1 then
		return nil
	end

	-- Give the propset time to fully load
	WaitForPropSetToLoad(propset)

	-- Objects spawned as part of a propset are not networked, so clone
	-- those objects into your DB as new, networked objects, then delete
	-- the propset.
	local itemset = CreateItemset(true)
	local size = GetEntitiesFromPropset(propset, itemset, 0, false, false)

	if size > 0 then
		for i = 0, size - 1 do
			CloneEntity(GetIndexedItemInItemset(i, itemset))
		end
	end

	if IsItemsetValid(itemset) then
		DestroyItemset(itemset)
	end

	DeletePropset(propset, false, false)

	return nil
end

ParticleHandles = ParticleHandles or {} -- [anchor entity] = running particle FX handle

-- Load a particle dictionary (async) and start a looped effect on the given
-- entity. Returns the particle FX handle (needed to stop it later), or nil.
function PlayParticleEffect(entity, dict, fx, scale)
	RequestNamedPtfxAsset(dict)

	local tries = 0
	while not HasNamedPtfxAssetLoaded(dict) and tries < 200 do
		Wait(10)
		tries = tries + 1
	end

	if not HasNamedPtfxAssetLoaded(dict) then
		return nil
	end

	UseParticleFxAsset(dict)

	return StartParticleFxLoopedOnEntity(fx, entity, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, scale or 1.0, false, false, false, false)
end

-- A placed particle is an invisible "anchor" object with the effect attached to it
-- (StartParticleFxLoopedOnEntity), so it can be grabbed, moved, rotated, deleted
-- and saved/loaded exactly like any other spooner object.
function SpawnParticleEffect(name, x, y, z, pitch, roll, yaw, scale)
	if not Permissions.spawn.particle then
		return nil
	end

	if IsDatabaseFull() then
		return nil
	end

	-- name is "dict/fx"
	local dict, fx = string.match(name, '^(.-)/(.+)$')

	if not dict or not fx then
		return nil
	end

	local anchorModel = GetHashKey(Config.ParticleAnchorModel)

	if not LoadModel(anchorModel) then
		return nil
	end

	local entity = CreateObjectNoOffset(anchorModel, x, y, z, true, false, true)

	SetModelAsNoLongerNeeded(anchorModel)

	if not entity or entity < 1 then
		return nil
	end

	SetEntityRotation(entity, pitch, roll, yaw, 2)
	-- Hide the anchor via alpha, NOT SetEntityVisible(false): the latter appears to
	-- also cull/stop rendering a particle effect attached to the entity (it would
	-- flash briefly then vanish). Alpha 0 keeps the entity "visible" to the engine's
	-- own tracking, just fully transparent, so the attached FX keeps rendering.
	SetEntityAlpha(entity, 0, false)
	SetEntityCollision(entity, false, false)
	FreezeEntityPosition(entity, true)

	AddEntityToDatabase(entity, name)

	Database[entity].isFrozen = true
	Database[entity].particle = {
		dict = dict,
		fx = fx,
		scale = scale or 1.0
	}

	ParticleHandles[entity] = PlayParticleEffect(entity, dict, fx, scale or 1.0)

	return entity
end

function SpawnPickup(name, model, x, y, z)
	if not Permissions.spawn.pickup then
		return nil
	end

	if IsDatabaseFull() then
		return nil
	end

	if not IsPickupTypeValid(model) then
		return nil
	end

	-- Fix pickups with OneSync: flag 32 (LowPriority)
	local pickup = CreatePickup(model, x, y, z, 32, 0, false, 0, 0, 0.0, 0)

	if not pickup or pickup < 1 then
		return nil
	end

	AddEntityToDatabase(pickup, name)
	Database[pickup].model = model
	Database[pickup].type = 5

	return pickup
end

function RequestControl(entity)
	local type = GetEntityType(entity)

	if type < 1 or type > 3 then
		return
	end

	NetworkRequestControlOfEntity(entity)
end

function CanDeleteEntity(entity)
	if EntityIsInDatabase(entity) then
		if NetworkGetEntityIsNetworked(entity) then
			return Permissions.delete.own.networked
		else
			return Permissions.delete.own.nonNetworked
		end
	else
		if NetworkGetEntityIsNetworked(entity) then
			return Permissions.delete.other.networked
		else
			return Permissions.delete.other.nonNetworked
		end
	end
end

function StoreDeletedEntity(entity)
	local props = GetLiveEntityProperties(entity)

	table.insert(DeletedEntities, {
		x = props.x,
		y = props.y,
		z = props.z,
		model = props.model,
	})
end

function RemoveEntity(entity)
	if not CanDeleteEntity(entity) then
		return
	end

	if IsPedAPlayer(entity) then
		return
	end

	-- Stop and forget any particle effect anchored to this entity so its FX handle
	-- doesn't leak once the (invisible) anchor object is deleted.
	if ParticleHandles and ParticleHandles[entity] then
		if DoesParticleFxLoopedExist(ParticleHandles[entity]) then
			RemoveParticleFx(ParticleHandles[entity], false)
		end
		ParticleHandles[entity] = nil
	end

	local entityType = GetSpoonerEntityType(entity)

	if entityType == 4 then
		DeletePropset(entity)
	elseif entityType == 5 then
		RemovePickup(entity)
	else
		if StoreDeleted and not EntityIsInDatabase(entity) then
			StoreDeletedEntity(entity)
		end

		RequestControl(entity)
		SetEntityAsMissionEntity(entity, true, true)
		DeleteEntity(entity)
	end

	RemoveEntityFromDatabase(entity)
end

function RemoveAllFromDatabase()
	local entities = {}
	for handle, info in pairs(Database) do
		table.insert(entities, handle)
	end
	for _, handle in ipairs(entities) do
		RemoveEntity(handle)
	end
end

function SaveDatabaseInKvs(name, db)
	SetResourceKvp('DB_' .. name, json.encode(db))
end

function LoadDatabaseFromKvs(name)
	return json.decode(GetResourceKvpString('DB_' .. name))
end

AddEventHandler('onResourceStop', function(resourceName)
	if GetCurrentResourceName() == resourceName then
		DisableSpoonerMode()

		if Config.CleanUpOnStop then
			RemoveAllFromDatabase()
		end

		-- Clean up the hidden MP-ped template clones so they don't leak (the
		-- persisted KVP entries themselves are left alone and reload on next start)
		if ClearMpPedTemplates then
			ClearMpPedTemplates()
		end
	end
end)

