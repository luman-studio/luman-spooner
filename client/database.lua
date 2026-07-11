-- ============================================================================
-- spooner :: client/database.lua
-- Database UI updates, properties menu, place-on-ground, attach, save/load/list databases
--
-- Part of the split client.lua. All spooner client modules share one Lua state
-- and _G, so globals defined in any module are visible to the others.
-- ============================================================================

function UpdateDatabase()
	local entities = {}
	local propsets = {}
	local pickups = {}

	for entity, properties in pairs(Database) do
		if properties.type == 4 then
			table.insert(propsets, entity)
		elseif properties.type == 5 then
			table.insert(pickups, entity)
		else
			table.insert(entities, entity)
		end
	end

	for _, entity in ipairs(entities) do
		if DoesEntityExist(entity) then
			AddEntityToDatabase(entity)
		elseif Database[entity].isSelf then
			RemoveEntityFromDatabase(entity)
		else
			Database[entity].exists = false
		end
	end

	for _, propset in ipairs(propsets) do
		if DoesPropsetExist(propset) then
			AddEntityToDatabase(propset)
		else
			Database[propset].exists = false
		end
	end

	for _, pickup in ipairs(pickups) do
		if DoesPickupExist(pickup) then
			AddEntityToDatabase(pickup)
		else
			Database[pickup].exists = false
		end
	end
end

function CanModifyEntity(entity)
	if EntityIsInDatabase(entity) then
		if NetworkGetEntityIsNetworked(entity) then
			return Permissions.modify.own.networked
		else
			return Permissions.modify.own.nonNetworked
		end
	else
		if NetworkGetEntityIsNetworked(entity) then
			return Permissions.modify.other.networked
		else
			return Permissions.modify.other.nonNetworked
		end
	end
end

function OpenPropertiesMenuForEntity(entity)
	if not CanModifyEntity(entity) then
		SetNuiFocus(false, false)
		return
	end

	SendNUIMessage({
		type = 'openPropertiesMenu',
		entity = entity
	})
	SetNuiFocus(true, true)
end

RegisterNUICallback('openPropertiesMenuForEntity', function(data, cb)
	OpenPropertiesMenuForEntity(data.entity)
	cb({})
end)

function getDataForPropertiesMenu(entity)
	return {
		entity = entity,
		properties = json.encode(GetEntityProperties(entity)),
		inDb = EntityIsInDatabase(entity),
		hasNetworkControl = NetworkHasControlOfEntity(entity)
	}
end

RegisterNUICallback('updatePropertiesMenu', function(data, cb)
	local entity = data.handle
	local data = getDataForPropertiesMenu(entity)
	cb(data)
end)

RegisterNUICallback('invincibleOn', function(data, cb)
	if Permissions.properties.invincible and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetEntityInvincible(data.handle, true)
	end
	cb({})
end)

RegisterNUICallback('invincibleOff', function(data, cb)
	if Permissions.properties.invincible and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetEntityInvincible(data.handle, false)
	end
	cb({})
end)

function PlacePedOnGroundProperly(ped)
	local x, y, z = table.unpack(GetEntityCoords(ped))
	local found, groundz, normal = GetGroundZAndNormalFor_3dCoord(x, y, z)
	if found then
		SetEntityCoordsNoOffset(ped, x, y, groundz + normal.z, true)
	end
end

function PlaceOnGroundProperly(entity)
	local r1 = GetEntityRotation(entity, 2)

	-- Temporarily detach any props attached to this entity so the ground placement
	-- is computed from the entity's OWN bounds (e.g. a ped's feet) and not from an
	-- attached prop, which would otherwise push the ped off the ground. The props
	-- are re-attached with the exact same offsets right after.
	local children = GetAttachedChildren(entity)
	local childData = {}

	for _, child in ipairs(children) do
		local a = Database[child].attachment
		childData[child] = {
			bone = a.bone, x = a.x, y = a.y, z = a.z,
			pitch = a.pitch, roll = a.roll, yaw = a.yaw,
			useSoftPinning = a.useSoftPinning, collision = a.collision,
			vertex = a.vertex, fixedRot = a.fixedRot
		}
		DetachEntity(child, true, true)
	end

	if Config.isRDR then
		PlaceEntityOnGroundProperly(entity, false)
	else
		local type = GetEntityType(entity)

		if type == 2 then
			SetVehicleOnGroundProperly(entity)
		elseif type == 3 then
			PlaceObjectOnGroundProperly(entity, false)
		end
	end

	-- Only adjust the ground height: restore the entity's full original rotation
	-- (pitch, roll and yaw) so grabbing/holding never tilts it to the terrain and
	-- the rotation the user set while holding is kept exactly on placement.
	SetEntityRotation(entity, r1.x, r1.y, r1.z, 2)

	-- Re-attach the props with their original offsets
	for _, child in ipairs(children) do
		local a = childData[child]
		AttachEntity(child, entity, a.bone, a.x, a.y, a.z, a.pitch, a.roll, a.yaw, a.useSoftPinning, a.collision, a.vertex, a.fixedRot)
	end
end

RegisterNUICallback('placeEntityHere', function(data, cb)
	if Permissions.properties.position and CanModifyEntity(data.handle) then
		local x, y, z = table.unpack(GetCamCoord(Cam))
		local pitch, roll, yaw = table.unpack(GetCamRot(Cam, 2))

		local spawnPos, entity, distance = GetInView(x, y, z, pitch, roll, yaw)

		RequestControl(data.handle)
		SetEntityCoordsNoOffset(data.handle, spawnPos.x, spawnPos.y, spawnPos.z)
		PlaceOnGroundProperly(data.handle)

		x, y, z = table.unpack(GetEntityCoords(data.handle))
		pitch, roll, yaw = table.unpack(GetEntityRotation(data.handle, 2))

		cb({
			x = x,
			y = y,
			z = z,
			pitch = pitch,
			roll = roll,
			yaw = yaw
		})
	else
		cb({})
	end
end)

function PrepareDatabaseForSave()
	local db = json.decode(json.encode(Database))
	local ped = PlayerPedId()

	for entity, props in pairs(db) do
		if props.attachment.to == ped then
			props.attachment.to = -1
		end
	end

	db[tostring(ped)] = nil

	return {
		spawn = db,
		delete = DeletedEntities
	}
end

function SaveDatabase(name)
	UpdateDatabase()
	SaveDatabaseInKvs(name, PrepareDatabaseForSave())
end

function RemoveDeletedEntity(x, y, z, hash)
	local handle = GetClosestObjectOfType(x, y, z, 1.0, hash, false, false, false)

	if handle ~= 0 then
		DeleteEntity(handle)
	end
end

function AttachEntity(from, to, bone, x, y, z, pitch, roll, yaw, useSoftPinning, collision, vertex, fixedRot)
	if not bone then
		bone = 0
	end

	AttachEntityToEntity(GetAttachValues(
		from, to, bone, x, y, z, pitch, roll, yaw, useSoftPinning, collision, vertex, fixedRot
	))

	if EntityIsInDatabase(from) then
		AddEntityToDatabase(from, nil, {
			to = to,
			bone = bone,
			x = x,
			y = y,
			z = z,
			pitch = pitch,
			roll = roll,
			yaw = yaw,
			useSoftPinning = useSoftPinning,
			collision = collision,
			vertex = vertex,
			fixedRot = fixedRot
		})
	end
end

function GetAttachValues(from, to, bone, x, y, z, pitch, roll, yaw, useSoftPinning, collision, vertex, fixedRot)
	local boneIndex = GetBoneIndex(to, bone)
	local p9 = false
	local isPed = false
	local p15 = false
	local p16 = false
	return from, to, boneIndex, x, y, z, pitch, roll, yaw, p9, useSoftPinning, collision, isPed, vertex, fixedRot, p15, p16
end

function LoadDatabase(db, relative, replace)
	if replace then
		RemoveAllFromDatabase()
	end

	local ax = 0.0
	local ay = 0.0
	local az = 0.0

	local spawns = {}
	local handles = {}

	-- For backwards compatibility with older DB format
	if not (db.spawn and db.delete) then
		db = {spawn = db, delete = {}}
	end

	if StoreDeleted then
		for _, deleted in pairs(db.delete) do
			RemoveDeletedEntity(deleted.x, deleted.y, deleted.z, deleted.model)
			table.insert(DeletedEntities, deleted)
		end
	end

	for entity, props in pairs(db.spawn) do
		if relative then
			ax = ax + props.x
			ay = ay + props.y
			az = az + props.z
		end

		table.insert(spawns, {entity = tonumber(entity), props = props})
	end

	local dx, dy, dz

	local rot = GetCamRot(Cam, 2)

	if relative then
		ax = ax / #spawns
		ay = ay / #spawns
		az = az / #spawns

		local pos = GetCamCoord(Cam)
		local spawnPos, entity, distance = GetInView(pos.x, pos.y, pos.z, rot.x, rot.y, rot.z)

		dx = spawnPos.x - ax
		dy = spawnPos.y - ay
		dz = spawnPos.z - az
	end

	local r = math.rad(rot.z)
	local cosr = math.cos(r)
	local sinr = math.sin(r)

	for _, spawn in ipairs(spawns) do
		local entity

		local x, y, z, pitch, roll, yaw

		if relative then
			x = (((spawn.props.x - ax) * cosr - (spawn.props.y - ay) * sinr + ax) + dx) * 1.0
			y = (((spawn.props.y - ay) * cosr + (spawn.props.x - ax) * sinr + ay) + dy) * 1.0
			z = (spawn.props.z + dz) * 1.0
			pitch = spawn.props.pitch * 1.0
			roll = spawn.props.roll * 1.0
			yaw = (spawn.props.yaw + rot.z) * 1.0
		else
			x = spawn.props.x * 1.0
			y = spawn.props.y * 1.0
			z = spawn.props.z * 1.0
			pitch = spawn.props.pitch * 1.0
			roll = spawn.props.roll * 1.0
			yaw = spawn.props.yaw * 1.0
		end

		spawn.props.x = x
		spawn.props.y = y
		spawn.props.z = z
		spawn.props.pitch = pitch
		spawn.props.roll = roll
		spawn.props.yaw = yaw

		if spawn.props.type == 1 then
			entity = SpawnPed(spawn.props)
		elseif spawn.props.type == 2 then
			entity = SpawnVehicle(spawn.props.name, spawn.props.model, x, y, z, pitch, roll, yaw, spawn.props.collisionDisabled, spawn.props.isVisible)
		elseif spawn.props.type == 5 then
			entity = SpawnPickup(spawn.props.name, spawn.props.model, x, y, z)
		else
			entity = SpawnObject(spawn.props.name, spawn.props.model, x, y, z, pitch, roll, yaw, spawn.props.collisionDisabled, spawn.props.isVisible, spawn.props.lightsIntensity, spawn.props.lightsColour, spawn.props.lightsType, spawn.props.isFrozen)
		end

		if entity and relative then
			PlaceOnGroundProperly(entity)
		end

		-- Particle-effect anchors are plain objects to SpawnObject (it doesn't know
		-- about the .particle field), so the effect has to be restarted by hand here.
		-- Alpha (not SetEntityVisible) re-applied too: SpawnObject only reset
		-- visibility from the saved isVisible flag, which alpha-hidden anchors report
		-- as true, so it wouldn't otherwise be hidden again on reload.
		if entity and spawn.props.particle then
			SetEntityAlpha(entity, 0, false)
			Database[entity].particle = spawn.props.particle
			ParticleHandles[entity] = PlayParticleEffect(entity, spawn.props.particle.dict, spawn.props.particle.fx, spawn.props.particle.scale)
		end

		handles[spawn.entity] = entity
	end

	for _, spawn in ipairs(spawns) do
		if spawn.props.quaternion then
			local x = spawn.props.quaternion.x
			local y = spawn.props.quaternion.y
			local z = spawn.props.quaternion.z
			local w = -spawn.props.quaternion.w

			SetEntityQuaternion(handles[spawn.entity], x, y, z, w)
		end

		if spawn.props.attachment and spawn.props.attachment.to ~= 0 then
			local from  = handles[spawn.entity]
			local to    = spawn.props.attachment.to == -1 and PlayerPedId() or handles[spawn.props.attachment.to]
			local bone  = spawn.props.attachment.bone
			local x     = spawn.props.attachment.x + 0.0
			local y     = spawn.props.attachment.y + 0.0
			local z     = spawn.props.attachment.z + 0.0
			local pitch = spawn.props.attachment.pitch + 0.0
			local roll  = spawn.props.attachment.roll + 0.0
			local yaw   = spawn.props.attachment.yaw + 0.0
			local useSoftPinning = spawn.props.attachment.useSoftPinning
			local collision = spawn.props.attachment.collision
			local vertex = spawn.props.attachment.vertex or 0
			local fixedRot = spawn.props.attachment.fixedRot

			if type(bone) == 'number' then
				bone = FindBoneName(to, bone)
			end

			if useSoftPinning == nil then
				useSoftPinning = true
			end

			if collision == nil then
				collision = true
			end

			if fixedRot == nil then
				fixedRot = true
			end

			AttachEntity(from, to, bone, x, y, z, pitch, roll, yaw, useSoftPinning, collision, vertex, fixedRot)

			AddEntityToDatabase(from, nil, {
				to = to,
				bone = bone,
				x = x,
				y = y,
				z = z,
				pitch = pitch,
				roll = roll,
				yaw = yaw,
				useSoftPinning = useSoftPinning,
				collision = collision,
				vertex = vertex,
				fixedRot = fixedRot
			})
		end
	end
end

function LoadSavedDatabase(name, relative, replace)
	local db = LoadDatabaseFromKvs(name)

	if db then
		LoadDatabase(db, relative, replace)
	end
end

function GetSavedDatabases()
	local dbs = {}

	local handle = StartFindKvp('DB_')

	while true do
		local kvp = FindKvp(handle)

		if kvp then
			table.insert(dbs, string.sub(kvp, 4))
		else
			break
		end
	end

	EndFindKvp(handle)

	table.sort(dbs)

	return dbs
end

function DeleteDatabase(name)
	DeleteResourceKvp('DB_' .. name)
end

RegisterNUICallback('saveDb', function(data, cb)
	SaveDatabase(data.name)
	cb(json.encode(GetSavedDatabases()))
end)

RegisterNUICallback('loadDb', function(data, cb)
	LoadSavedDatabase(data.name, data.relative, data.replace)
	cb({})
end)

RegisterNUICallback('deleteDb', function(data, cb)
	DeleteDatabase(data.name)
	cb({})
end)

