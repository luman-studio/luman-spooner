-- ============================================================================
-- spooner :: client/entities.lua
-- Entity type/model/view helpers, in-memory database accessors, model loading, walk styles
--
-- Part of the split client.lua. All spooner client modules share one Lua state
-- and _G, so globals defined in any module are visible to the others.
-- ============================================================================

function GetSpoonerEntityType(entity)
	return Database[entity] and Database[entity].type or GetEntityType(entity)
end

function GetSpoonerEntityModel(entity)
	return Database[entity] and Database[entity].model or GetEntityModel(entity)
end

function GetInView(x1, y1, z1, pitch, roll, yaw)
	local rx = -math.sin(math.rad(yaw)) * math.abs(math.cos(math.rad(pitch)))
	local ry =  math.cos(math.rad(yaw)) * math.abs(math.cos(math.rad(pitch)))
	local rz =  math.sin(math.rad(pitch))

	local x2 = x1 + rx * 10000.0
	local y2 = y1 + ry * 10000.0
	local z2 = z1 + rz * 10000.0

	local retval, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(StartShapeTestRay(x1, y1, z1, x2, y2, z2, -1, -1, 1))

	if entityHit <= 0 or GetEntityType(entityHit) == 0 then
		return endCoords, nil, 0
	end

	local entityCoords = GetEntityCoords(entityHit)

	local distance = #(vector3(x1, y1, z1) - entityCoords)

	if distance >= 100.0 then
		return endCoords, nil, distance
	end

	return endCoords, entityHit, distance
end

function GetModelName(model)
	for _, name in ipairs(Peds) do
		if model == GetHashKey(name) then
			return name
		end
	end

	for _, name in ipairs(Vehicles) do
		if model == GetHashKey(name) then
			return name
		end
	end

	for _, name in ipairs(Objects) do
		if model == GetHashKey(name) then
			return name
		end
	end

	for _, name in ipairs(Pickups) do
		if model == GetHashKey(name) then
			return name
		end
	end

	return tostring(model)
end

function GetPlayerFromPed(ped)
	for _, playerId in ipairs(GetActivePlayers()) do
		if ped == GetPlayerPed(playerId) then
			return playerId
		end
	end

	return nil
end

function GetBoneIndex(entity, bone)
	if type(bone) == 'number' then
		return bone
	else
		if Config.isRDR then
			return GetEntityBoneIndexByName(entity, bone)
		else
			return GetPedBoneIndex(entity, Bones[bone])
		end
	end
end

function FindBoneName(entity, boneIndex)
	if Config.isRDR then
		for _, boneName in ipairs(Bones) do
			if GetEntityBoneIndexByName(entity, boneName) == boneIndex then
				return boneName
			end
		end

		return boneIndex
	else
		for boneName, boneId in pairs(Bones) do
			if GetPedBoneIndex(entity, boneId) == boneIndex then
				return boneName
			end
		end

		return boneIndex
	end
end

function GetPedConfigFlags(ped)
	local flags = {}

	for i = 0, 600 do
		flags[i] = GetPedConfigFlag(ped, i)
	end

	return flags
end

function GetLiveEntityProperties(entity)
	local model = GetEntityModel(entity)
	local x, y, z = table.unpack(GetEntityCoords(entity))
	local pitch, roll, yaw = table.unpack(GetEntityRotation(entity, 2))
	local isPlayer = IsPedAPlayer(entity)
	local player = isPlayer and GetPlayerFromPed(entity)
	local type = GetEntityType(entity)

	return {
		name = GetModelName(model),
		type = type,
		model = model,
		x = CutDigits(x),
		y = CutDigits(y),
		z = CutDigits(z),
		pitch = CutDigits(pitch),
		roll = CutDigits(roll),
		yaw = CutDigits(yaw),
		health = GetEntityHealth(entity),
		outfit = -1,
		isInGroup = IsPedGroupMember(entity, GetPlayerGroup(PlayerId())),
		collisionDisabled = GetEntityCollisionDisabled(entity),
		blockNonTemporaryEvents = false,
		isSelf = entity == PlayerPedId(),
		playerName = player and GetPlayerName(player),
		weapons = {},
		isFrozen = Config.isRDR and IsEntityFrozen(entity) or false,
		isVisible = IsEntityVisible(entity),
		pedConfigFlags = type == 1 and GetPedConfigFlags(entity) or nil,
		attachment = {
			to = GetEntityAttachedTo(entity),
			x = 0.0,
			y = 0.0,
			z = 0.0,
			pitch = 0.0,
			roll = 0.0,
			yaw = 0.0
		},
		netId = NetworkGetEntityIsNetworked(entity) and NetworkGetNetworkIdFromEntity(entity),
		exists = true
	}
end

function AddEntityToDatabase(entity, name, attachment)
	if not entity then
		return nil
	end

	if not name and Database[entity] then
		name = Database[entity].name
	end

	local model = Database[entity] and Database[entity].model
	local type = Database[entity] and Database[entity].type

	local outfit = Database[entity] and Database[entity].outfit or -1

	local attachBone, attachX, attachY, attachZ, attachPitch, attachRoll, attachYaw, attachSoftPinning, attachCollision, attachVertex, attachFixedRot

	local lightsIntensity = Database[entity] and Database[entity].lightsIntensity or nil
	local lightsColour = Database[entity] and Database[entity].lightsColour or nil
	local lightsType = Database[entity] and Database[entity].lightsType or nil

	local animation = Database[entity] and Database[entity].animation
	local scenario = Database[entity] and Database[entity].scenario
	local emote = Database[entity] and Database[entity].emote

	local blockNonTemporaryEvents = Database[entity] and Database[entity].blockNonTemporaryEvents or false

	local weapons = Database[entity] and Database[entity].weapons or {}

	local walkStyle = Database[entity] and Database[entity].walkStyle

	local scale = Database[entity] and Database[entity].scale

	local particle = Database[entity] and Database[entity].particle

	local outfitComponents = Database[entity] and Database[entity].outfitComponents
	local bodySize = Database[entity] and Database[entity].bodySize

	if attachment then
		attachBone        = attachment.bone
		attachX           = attachment.x
		attachY           = attachment.y
		attachZ           = attachment.z
		attachPitch       = attachment.pitch
		attachRoll        = attachment.roll
		attachYaw         = attachment.yaw
		attachSoftPinning = attachment.useSoftPinning
		attachCollision   = attachment.collision
		attachVertex      = attachment.vertex
		attachFixedRot    = attachment.fixedRot
	else
		attachBone        = (Database[entity] and Database[entity].attachment.bone)
		attachX           = (Database[entity] and Database[entity].attachment.x              or 0.0)
		attachY           = (Database[entity] and Database[entity].attachment.y              or 0.0)
		attachZ           = (Database[entity] and Database[entity].attachment.z              or 0.0)
		attachPitch       = (Database[entity] and Database[entity].attachment.pitch          or 0.0)
		attachRoll        = (Database[entity] and Database[entity].attachment.roll           or 0.0)
		attachYaw         = (Database[entity] and Database[entity].attachment.yaw            or 0.0)
		attachSoftPinning = (Database[entity] and Database[entity].attachment.useSoftPinning or false)
		attachCollision   = (Database[entity] and Database[entity].attachment.collision      or true)
		attachVertex      = (Database[entity] and Database[entity].attachment.vertex         or 0)
		attachFixedRot    = (Database[entity] and Database[entity].attachment.fixedRot       or true)
	end

	local isFrozen = Database[entity] and Database[entity].isFrozen

	Database[entity] = GetLiveEntityProperties(entity)

	if name then
		Database[entity].name = name
	end

	if model then
		Database[entity].model = model
	end

	if type then
		Database[entity].type = type
	end

	Database[entity].outfit = outfit

	Database[entity].attachment.bone = attachBone
	Database[entity].attachment.x = attachX
	Database[entity].attachment.y = attachY
	Database[entity].attachment.z = attachZ
	Database[entity].attachment.pitch = attachPitch
	Database[entity].attachment.roll = attachRoll
	Database[entity].attachment.yaw = attachYaw
	Database[entity].attachment.useSoftPinning = attachSoftPinning
	Database[entity].attachment.collision = attachCollision
	Database[entity].attachment.vertex = attachVertex
	Database[entity].attachment.fixedRot = attachFixedRot

	Database[entity].lightsIntensity = lightsIntensity
	Database[entity].lightsColour = lightsColour
	Database[entity].lightsType = lightsType

	Database[entity].animation = animation
	Database[entity].scenario = scenario
	Database[entity].emote = emote

	Database[entity].blockNonTemporaryEvents = blockNonTemporaryEvents

	Database[entity].weapons = weapons

	Database[entity].walkStyle = walkStyle

	Database[entity].scale = scale

	Database[entity].particle = particle

	Database[entity].outfitComponents = outfitComponents
	Database[entity].bodySize = bodySize

	if not Config.isRDR then
		Database[entity].isFrozen = isFrozen
	end

	return Database[entity]
end

function RemoveEntityFromDatabase(entity)
	Database[entity] = nil
end

function GetEntityPropertiesFromDatabase(entity)
	return AddEntityToDatabase(entity)
end

function EntityIsInDatabase(entity)
	return Database[entity] ~= nil
end

function GetEntityProperties(entity)
	if EntityIsInDatabase(entity) then
		return GetEntityPropertiesFromDatabase(entity)
	else
		return GetLiveEntityProperties(entity)
	end
end

function GetDatabaseSize()
	local n = 0

	for entity, props in pairs(Database) do
		n = n + 1
	end

	return n
end

function IsDatabaseFull()
	return Permissions.maxEntities and GetDatabaseSize() >= Permissions.maxEntities
end

function ResolveModelHash(name)
	if type(name) == 'number' then
		return name
	end
	if type(name) == 'string' then
		local n = tonumber(name)
		if n then
			return math.floor(n)
		end
	end
	return GetHashKey(name)
end

function LoadModel(model)
	if IsModelInCdimage(model) then
		RequestModel(model)

		while not HasModelLoaded(model) do
			Wait(0)
		end

		return true
	else
		return false
	end
end

function SetWalkStyle(ped, base, style)
	Citizen.InvokeNative(0x923583741DC87BCE, ped, base)
	Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, style)

	if Database[ped] then
		Database[ped].walkStyle = {
			base = base,
			style = style
		}
	end
end


-- ============================================================================
-- Merged from the former client_extended.lua
-- ============================================================================

function CutDigits(val)
    return math.floor(val * 1000) / 1000
end

---------------
-- Interiors --
---------------
InteriorsHash = {}
if Interiors ~= nil then
	for k,v in ipairs(Interiors) do
		InteriorsHash[GetHashKey(v.name)] = v.name 
	end
end
