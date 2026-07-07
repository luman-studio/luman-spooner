-- ============================================================================
-- spooner :: client/nui_spawn.lua
-- Spawn-and-attach NUI callbacks, particle/pickup menus, freeze/rotation/coords callbacks
--
-- Part of the split client.lua. All spooner client modules share one Lua state
-- and _G, so globals defined in any module are visible to the others.
-- ============================================================================

-- ============================================================================
-- Spawn and Attach callbacks for all entity types
-- ============================================================================

RegisterNUICallback('spawnAndAttachPed', function(data, cb)
	ClearPreview()

	if data.modelName and (Permissions.spawn.byName or Contains(Peds, data.modelName)) then
		-- Remember selection so it can be re-spawned with the spawn control (E)
		CurrentSpawn = {
			modelName = data.modelName,
			type = 1
		}

		local x, y, z = table.unpack(GetCamCoord(Cam))
		local pitch, roll, yaw = table.unpack(GetCamRot(Cam, 2))
		local spawnPos = GetInView(x, y, z, pitch, roll, yaw)

		local yaw2 = yaw
		if yaw2 < 0.0 then
			yaw2 = yaw2 + 360.0
		end

		local entity = SpawnPed({
			name = data.modelName,
			model = ResolveModelHash(data.modelName),
			x = spawnPos.x,
			y = spawnPos.y,
			z = spawnPos.z,
			pitch = 0.0,
			roll = 0.0,
			yaw = yaw2,
			collisionDisabled = false,
			isVisible = true,
			outfit = -1,
			isInGroup = false,
			blockNonTemporaryEvents = false
		})

		if entity then
			PlaceOnGroundProperly(entity)
			TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
			AttachedEntity = entity
			TriggerEvent('spooner:onEntitySelected', AttachedEntity)
		end
	end
	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('spawnAndAttachVehicle', function(data, cb)
	ClearPreview()

	if data.modelName and (Permissions.spawn.byName or Contains(Vehicles, data.modelName)) then
		-- Remember selection so it can be re-spawned with the spawn control (E)
		CurrentSpawn = {
			modelName = data.modelName,
			type = 2
		}

		local x, y, z = table.unpack(GetCamCoord(Cam))
		local pitch, roll, yaw = table.unpack(GetCamRot(Cam, 2))
		local spawnPos = GetInView(x, y, z, pitch, roll, yaw)

		local yaw2 = yaw
		if yaw2 < 0.0 then
			yaw2 = yaw2 + 360.0
		end

		local entity = SpawnVehicle(data.modelName, ResolveModelHash(data.modelName), spawnPos.x, spawnPos.y, spawnPos.z, 0.0, 0.0, yaw2, false, true)

		if entity then
			PlaceOnGroundProperly(entity)
			TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
			AttachedEntity = entity
			TriggerEvent('spooner:onEntitySelected', AttachedEntity)
		end
	end
	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('spawnAndAttachPropset', function(data, cb)
	ClearPreview()

	if data.modelName and (Permissions.spawn.byName or Contains(Propsets, data.modelName)) then
		-- Remember selection so it can be re-spawned with the spawn control (E)
		CurrentSpawn = {
			modelName = data.modelName,
			type = 4
		}

		local x, y, z = table.unpack(GetCamCoord(Cam))
		local pitch, roll, yaw = table.unpack(GetCamRot(Cam, 2))
		local spawnPos = GetInView(x, y, z, pitch, roll, yaw)

		local yaw2 = yaw
		if yaw2 < 0.0 then
			yaw2 = yaw2 + 360.0
		end

		local entity = SpawnPropset(data.modelName, ResolveModelHash(data.modelName), spawnPos.x, spawnPos.y, spawnPos.z, yaw2)

		if entity then
			PlaceOnGroundProperly(entity)
			TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
			AttachedEntity = entity
			TriggerEvent('spooner:onEntitySelected', AttachedEntity)
		end
	end
	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('closePropsetMenu', function(data, cb)
	if data.modelName and (Permissions.spawn.byName or Contains(Propsets, data.modelName)) then
		CurrentSpawn = {
			modelName = data.modelName,
			type = 4
		}
	end
	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('spawnAndAttachParticle', function(data, cb)
	ClearPreview()

	if data.modelName and (Permissions.spawn.byName or Contains(Particles, data.modelName)) then
		-- Remember selection so it can be re-spawned with the spawn control (E)
		CurrentSpawn = {
			modelName = data.modelName,
			type = 6
		}

		local x, y, z = table.unpack(GetCamCoord(Cam))
		local pitch, roll, yaw = table.unpack(GetCamRot(Cam, 2))
		local spawnPos = GetInView(x, y, z, pitch, roll, yaw)

		local yaw2 = yaw
		if yaw2 < 0.0 then
			yaw2 = yaw2 + 360.0
		end

		local entity = SpawnParticleEffect(data.modelName, spawnPos.x, spawnPos.y, spawnPos.z, 0.0, 0.0, yaw2, 1.0)

		if entity then
			PlaceOnGroundProperly(entity)
			TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
			AttachedEntity = entity
			TriggerEvent('spooner:onEntitySelected', AttachedEntity)
		end
	end
	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('closeParticleMenu', function(data, cb)
	if data.modelName and (Permissions.spawn.byName or Contains(Particles, data.modelName)) then
		CurrentSpawn = {
			modelName = data.modelName,
			type = 6
		}
	end
	SetNuiFocus(false, false)
	cb({})
end)

-- List every particle effect currently placed in the world (an object entity in
-- Database with a .particle field), so they can be found/selected/deleted without
-- having to physically locate them.
RegisterNUICallback('getPlacedParticles', function(data, cb)
	local list = {}

	for entity, props in pairs(Database) do
		if props.particle then
			table.insert(list, {
				handle = entity,
				name = props.name,
				exists = DoesEntityExist(entity)
			})
		end
	end

	table.sort(list, function(a, b) return a.handle < b.handle end)

	cb(json.encode(list))
end)

RegisterNUICallback('setParticleScale', function(data, cb)
	if Permissions.properties.position and CanModifyEntity(data.handle) then
		local scale = data.scale and data.scale * 1.0 or 1.0
		local fxHandle = ParticleHandles[data.handle]

		if fxHandle and DoesParticleFxLoopedExist(fxHandle) then
			SetParticleFxLoopedScale(fxHandle, scale)
		end

		if Database[data.handle] and Database[data.handle].particle then
			Database[data.handle].particle.scale = scale
		end
	end

	cb({})
end)

RegisterNUICallback('closePickupMenu', function(data, cb)
	if data.modelName and (Permissions.spawn.byName or Contains(Pickups, data.modelName)) then
		CurrentSpawn = {
			modelName = data.modelName,
			type = 5
		}
	end
	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('closeDatabase', function(data, cb)
	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('deleteEntity', function(data, cb)
	RemoveEntity(data.handle)
	cb({
		database = json.encode(Database)
	})
end)

RegisterNUICallback('removeAllFromDatabase', function(data, cb)
	RemoveAllFromDatabase()
	cb({})
end)

RegisterNUICallback('closePropertiesMenu', function(data, cb)
	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('closeSaveLoadDbMenu', function(data, cb)
	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('addEntityToDatabase', function(data, cb)
	AddEntityToDatabase(data.handle)

	if not KeepSelfInDb and data.handle == PlayerPedId() then
		KeepSelfInDb = true
	end

	cb({})
end)

RegisterNUICallback('addCustomEntityToDatabase', function(data, cb)
	if not Permissions.maxEntities and Permissions.modify.other then
		AddEntityToDatabase(data.handle)

		if not KeepSelfInDb and data.handle == PlayerPedId() then
			KeepSelfInDb = true
		end
	end

	cb{database = json.encode(Database)}
end)

RegisterNUICallback('removeEntityFromDatabase', function(data, cb)
	if not Permissions.maxEntities and Permissions.modify.other then
		RemoveEntityFromDatabase(data.handle)

		if KeepSelfInDb and data.handle == PlayerPedId() then
			KeepSelfInDb = false
		end
	end
	cb({})
end)

function freezeEntity(handle)
	if Permissions.properties.freeze and CanModifyEntity(handle) then
		RequestControl(handle)
		FreezeEntityPosition(handle, true)
		if not Config.isRDR and Database[handle] then
			Database[handle].isFrozen = true
		end
	end
end
RegisterNUICallback('freezeEntity', function(data, cb)
	freezeEntity(data.handle)
	cb({})
end)

function unfreezeEntity(handle)
	if Permissions.properties.freeze and CanModifyEntity(handle) then
		RequestControl(handle)
		FreezeEntityPosition(handle, false)

		if not Config.isRDR and Database[handle] then
			Database[handle].isFrozen = false
		end
	end
end
RegisterNUICallback('unfreezeEntity', function(data, cb)
	unfreezeEntity(data.handle)
	cb({})
end)

RegisterNUICallback('setEntityRotation', function(data, cb)
	if Permissions.properties.rotation and CanModifyEntity(data.handle) then
		local pitch = data.pitch and data.pitch * 1.0 or 0.0
		local roll  = data.roll  and data.roll  * 1.0 or 0.0
		local yaw   = data.yaw   and data.yaw   * 1.0 or 0.0

		RequestControl(data.handle)
		SetEntityRotation(data.handle, pitch, roll, yaw, 2)
	end

	cb({})
end)

RegisterNUICallback('setEntityCoords', function(data, cb)
	if Permissions.properties.position and CanModifyEntity(data.handle) then
		local x = data.x and data.x * 1.0 or 0.0
		local y = data.y and data.y * 1.0 or 0.0
		local z = data.z and data.z * 1.0 or 0.0

		RequestControl(data.handle)
		SetEntityCoordsNoOffset(data.handle, x, y, z)
	end

	cb({})
end)

RegisterNUICallback('resetRotation', function(data, cb)
	if Permissions.properties.rotation and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetEntityRotation(data.handle, 0.0, 0.0, 0.0, 2)
	end
	cb({})
end)

