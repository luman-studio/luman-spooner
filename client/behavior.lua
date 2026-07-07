-- ============================================================================
-- spooner :: client/behavior.lua
-- Patrol + Lasso behavior, favourites, init NUI callback, speeds, teleport, clone entity, misc callbacks
--
-- Part of the split client.lua. All spooner client modules share one Lua state
-- and _G, so globals defined in any module are visible to the others.
-- ============================================================================

-- ===================== Patrol + Lasso behavior =====================
-- The ped runs from point A to point B while aiming a lasso (the game twirls it
-- over the head). On reaching B it teleports back to A and runs the leg again.
-- The behavior is stored on the ped (Database[ped].behavior) so it is saved with
-- Saved/MP peds and restarted when they are spawned.

BehaviorPeds = BehaviorPeds or {}   -- [rider] = true while its behavior thread runs
PendingBehavior = nil               -- { entity = ..., a = {x,y,z} } while picking B

local function EquipLasso(ped)
	EquipWeaponInHand(ped, GetHashKey(Config.PatrolLassoWeapon))
end

-- A mounted ped can't be given a pedestrian go-to task directly (RDR2 fights it:
-- the ped tries to dismount, the horse jerks, nobody actually walks/rides anywhere).
-- Movement must be tasked on the MOVER (the horse, if mounted); the lasso weapon
-- and twirl animation must be tasked on the RIDER (the ped itself).
-- `entity` may be either the rider or (if already resolved, e.g. from a grabbed
-- horse) the mount itself — both directions are handled via the MountRider map.
function ResolvePatrolActors(entity)
	local mount = GetMount(entity)

	if mount and mount ~= 0 and DoesEntityExist(mount) then
		return entity, mount -- entity is the rider; its mount does the moving
	end

	local riderOf = MountRider and MountRider[entity]
	if riderOf and DoesEntityExist(riderOf) and GetMount(riderOf) == entity then
		return riderOf, entity -- entity is itself the mount; riderOf sits on it
	end

	return entity, entity -- not mounted: same entity walks and twirls
end

function StopPatrolLasso(entity)
	local rider = ResolvePatrolActors(entity)

	BehaviorPeds[rider] = nil

	if Database[rider] then
		Database[rider].behavior = nil
	end

	if DoesEntityExist(rider) then
		-- If mounted, only drop the secondary twirl task, not the rider's own
		-- internal "riding" task — clearing that would dismount it into a T-pose,
		-- same as the loop bug this is meant to avoid.
		if GetMount(rider) ~= 0 then
			ClearPedSecondaryTask(rider)
		else
			ClearPedTasks(rider)
		end
	end
end

function StartPatrolLasso(entity, a, b)
	if not DoesEntityExist(entity) then
		return
	end

	local rider, mover = ResolvePatrolActors(entity)

	-- Store the route as an offset (B - A) so it saves with Saved/MP peds and can be
	-- replayed relative to wherever the ped is later spawned.
	if Database[rider] then
		Database[rider].behavior = {
			type = 'patrolLasso',
			offset = { x = b.x - a.x, y = b.y - a.y, z = b.z - a.z }
		}
	end

	BehaviorPeds[rider] = true

	RequestControl(rider)
	RequestControl(mover)
	SetBlockingOfNonTemporaryEvents(rider, true)

	CreateThread(function()
		while DoesEntityExist(rider) and DoesEntityExist(mover) and BehaviorPeds[rider] do
			-- (re)start each leg at A. Clear the MOVER's previous leg task first, or the
			-- new go-to task won't re-trigger movement and it just stands at B.
			-- Do NOT clear the rider's tasks when mounted: RDR2 keeps the rider seated
			-- in the saddle via its own internal "riding" task, and clearing it drops
			-- the rider out of the seat pose (it ends up standing inside the horse).
			ClearPedTasksImmediately(mover)

			SetEntityCoordsNoOffset(mover, a.x, a.y, a.z)
			PlaceOnGroundProperly(mover)

			-- Make sure the lasso is out and in the RIDER's hand (not the mover's)
			EquipLasso(rider)

			-- Stop the previous leg's twirl clip specifically (the SECONDARY task
			-- slot), without touching the rider's other tasks (e.g. the seated-on-mount
			-- pose). Without this, the new TaskPlayAnim call below just layers onto
			-- the still-running previous loop instead of restarting it from frame 0,
			-- which is why the twirl looked like it "started from the middle".
			ClearPedSecondaryTask(rider)
			Wait(50)

			local twirl = Config.LassoTwirlAnim

			if twirl and twirl.dict and twirl.dict ~= '' then
				-- The mover runs/rides to B (drives the legs/gait), then the twirl clip
				-- is layered on the RIDER's upper body only via a bone-mask filter.
				TaskGoStraightToCoord(mover, b.x, b.y, b.z, Config.PatrolMoveSpeed, Config.PatrolTimeout, GetEntityHeading(mover), Config.PatrolReachDist)

				RequestAnimDict(twirl.dict)
				local t = 0
				while not HasAnimDictLoaded(twirl.dict) and t < 100 do
					Wait(0)
					t = t + 1
				end

				Wait(50) -- let the go-to task take hold first

				-- Plain TaskPlayAnim, looped by the engine's own REPEAT flag. Direct
				-- call (not PlayAnimation()) so we can pass the bone-mask filter, which
				-- PlayAnimation() hardcodes to ''.
				TaskPlayAnim(rider, twirl.dict, twirl.name, twirl.blendIn or 1.0, twirl.blendOut or 1.0, -1, twirl.flag or 25, 0.0, false, false, false, twirl.filter or '', false)
			else
				-- Default: mover runs to B, rider aims the lasso ahead (stays in hand)
				TaskGoToCoordWhileAimingAtCoord(mover, b.x, b.y, b.z, b.x, b.y, b.z + 1.0, Config.PatrolMoveSpeed, false, 0.5, 0.5, true, 0, false, GetHashKey('FIRING_PATTERN_FULL_AUTO'))
			end

			local elapsed = 0

			while DoesEntityExist(mover) and BehaviorPeds[rider] do
				Wait(200)
				elapsed = elapsed + 200

				-- Watchdog: if the twirl clip isn't playing anymore (the engine may not
				-- honour REPEAT forever on a secondary task, so it can quietly stop after
				-- a pass), restart it right away so the twirl never visibly cuts out for
				-- more than a beat while the ped is still en route.
				if twirl and twirl.dict and twirl.dict ~= '' and DoesEntityExist(rider) then
					if not IsEntityPlayingAnim(rider, twirl.dict, twirl.name, 3) then
						TaskPlayAnim(rider, twirl.dict, twirl.name, twirl.blendIn or 1.0, twirl.blendOut or 1.0, -1, twirl.flag or 25, 0.0, false, false, false, twirl.filter or '', false)
					end
				end

				local pos = GetEntityCoords(mover)
				local dist = #(pos - vector3(b.x, b.y, b.z))

				if dist <= Config.PatrolReachDist or elapsed >= Config.PatrolTimeout then
					break
				end
			end
		end

		BehaviorPeds[rider] = nil
	end)
end

-- Start (or restart) a ped's stored behavior relative to its current position.
-- Used when a Saved/MP ped that carries a behavior is placed.
function RestartBehavior(entity)
	local rider, mover = ResolvePatrolActors(entity)
	local beh = Database[rider] and Database[rider].behavior

	if beh and beh.type == 'patrolLasso' and beh.offset and not BehaviorPeds[rider] then
		local x, y, z = table.unpack(GetEntityCoords(mover))
		local a = { x = x, y = y, z = z }
		local b = { x = x + beh.offset.x, y = y + beh.offset.y, z = z + beh.offset.z }
		StartPatrolLasso(rider, a, b)
	end
end

RegisterNUICallback('setupPatrolLasso', function(data, cb)
	local handle = data.handle

	if DoesEntityExist(handle) and GetEntityType(handle) == 1 then
		local rider, mover = ResolvePatrolActors(handle)
		local x, y, z = table.unpack(GetEntityCoords(mover))
		PendingBehavior = { entity = rider, a = { x = x, y = y, z = z } }

		notify('Aim at point B and press ' .. (Config.isRDR and 'Left Mouse' or 'LMB') .. ' — press Right Mouse to cancel')
	end

	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('clearPatrolLasso', function(data, cb)
	if DoesEntityExist(data.handle) then
		StopPatrolLasso(data.handle)
	end
	cb({})
end)

RegisterNUICallback('spawnSavedPed', function(data, cb)
	ClearPreview()

	local saved = LoadSavedPed(data.name)

	if saved then
		CurrentSpawn = {
			modelName = saved.name,
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
			name = saved.name,
			model = ResolveModelHash(saved.model),
			x = spawnPos.x,
			y = spawnPos.y,
			z = spawnPos.z,
			pitch = 0.0,
			roll = 0.0,
			yaw = yaw2,
			collisionDisabled = false,
			isVisible = true,
			outfit = saved.outfit or -1,
			isInGroup = false,
			animation = saved.animation,
			scenario = saved.scenario,
			weapons = saved.weapons,
			walkStyle = saved.walkStyle,
			scale = saved.scale,
			pedConfigFlags = saved.pedConfigFlags,
			blockNonTemporaryEvents = saved.blockNonTemporaryEvents
		})

		if entity then
			PlaceOnGroundProperly(entity)

			-- Carry over a stored behavior; it starts when the ped is placed
			if saved.behavior and Database[entity] then
				Database[entity].behavior = saved.behavior
			end

			-- Re-spawn and re-attach any props that were saved with the ped
			if saved.attachments then
				for _, att in ipairs(saved.attachments) do
					local child = SpawnObject(att.name, ResolveModelHash(att.model), spawnPos.x, spawnPos.y, spawnPos.z, 0.0, 0.0, 0.0, false, true)

					if child then
						local a = att.attachment
						AttachEntity(child, entity, a.bone, a.x, a.y, a.z, a.pitch, a.roll, a.yaw, a.useSoftPinning, a.collision, a.vertex, a.fixedRot)
					end
				end
			end

			TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
			AttachedEntity = entity
			TriggerEvent('spooner:onEntitySelected', AttachedEntity)
		end
	end

	SetNuiFocus(false, false)
	cb({})
end)

function GetFavourites()
	local content = GetResourceKvpString('favourites')

	if content then
		return json.decode(content)
	end
end

RegisterNUICallback('init', function(data, cb)
	local bones

	if Config.isRDR then
		bones = Bones
	else
		bones = {}

		for boneName, _ in pairs(Bones) do
			table.insert(bones, boneName)
		end

		table.sort(bones)
	end

	cb({
		peds = json.encode(Peds),
		vehicles = json.encode(Vehicles),
		objects = json.encode(Objects),
		scenarios = json.encode(Scenarios),
		weapons = json.encode(Weapons),
		animations = json.encode(Animations),
		propsets = json.encode(Propsets),
		pickups = json.encode(Pickups),
		particles = json.encode(Particles),
		bones = json.encode(bones),
		walkStyleBases = json.encode(WalkStyleBases),
		walkStyles = json.encode(WalkStyles),
		adjustSpeed = AdjustSpeed,
		rotateSpeed = RotateSpeed,
		favourites = GetFavourites()
	})
end)

RegisterNUICallback('setAdjustSpeed', function(data, cb)
	AdjustSpeed = data.speed * 1.0
	cb({})
end)

RegisterNUICallback('setRotateSpeed', function(data, cb)
	RotateSpeed = data.speed * 1.0
	cb({})
end)

function GetTeleportTarget()
	local ped = PlayerPedId()
	local veh = GetVehiclePedIsIn(ped, false)
	local mnt = GetMount(ped)
	return (veh == 0 and (mnt == 0 and ped or mnt) or veh)
end

function TeleportToCoords(x, y, z, h)
	local ent = GetTeleportTarget()
	FreezeEntityPosition(ent, true)
	SetEntityCoords(ent, x, y, z, 0, 0, 0, 0, 0)
	SetEntityHeading(ent, h)
	FreezeEntityPosition(ent, false)
end

RegisterNUICallback('goToEntity', function(data, cb)
	if Permissions.properties.goTo then
		DisableSpoonerMode()
		local x, y, z = table.unpack(GetEntityCoords(data.handle))
		TeleportToCoords(x, y, z, 0.0)
	end
	cb({})
end)

-- Clone only the entity itself (model, animation, scenario, weapons, etc.).
-- Attachment handling (to its parent / its children) is done by the callers below.
function CloneEntityBody(entity)
	local props = GetEntityProperties(entity)

	if props.type == 1 then
		-- Capture the currently equipped/drawn weapon so the clone holds the same
		-- one. ClonePed alone doesn't carry this over, and props.weapons is often
		-- empty for a live ped that was never added to Database (e.g. an actual
		-- MP/player character), so it wouldn't otherwise be reproduced at all.
		local weaponInHand = nil

		local okC, _, curHash = pcall(GetCurrentPedWeapon, entity, true)
		if okC and curHash and curHash ~= 0 then
			weaponInHand = curHash
		end

		if not weaponInHand then
			local okS, selHash = pcall(GetSelectedPedWeapon, entity)
			if okS and selHash and selHash ~= 0 then
				weaponInHand = selHash
			end
		end

		props.handle = ClonePed(entity, true, true, true)
		local clone = SpawnPed(props)

		if clone and weaponInHand and weaponInHand ~= GetHashKey('WEAPON_UNARMED') then
			EquipWeaponInHand(clone, weaponInHand)
		end

		return clone
	elseif props.type == 2 then
		return SpawnVehicle(props.name, props.model, props.x, props.y, props.z, props.pitch, props.roll, props.yaw, props.collisionDisabled, props.isVisible)
	elseif props.type == 3 then
		local clone = SpawnObject(props.name, props.model, props.x, props.y, props.z, props.pitch, props.roll, props.yaw, props.collisionDisabled, props.isVisible, props.lightsIntensity, props.lightsColour, props.lightsType)

		-- A particle-effect anchor is a plain object to SpawnObject (it doesn't know
		-- about the .particle field), so the effect has to be restarted by hand.
		-- Alpha re-applied for the same reason as in LoadDatabase (see there).
		if clone and props.particle then
			SetEntityAlpha(clone, 0, false)
			Database[clone].particle = props.particle
			ParticleHandles[clone] = PlayParticleEffect(clone, props.particle.dict, props.particle.fx, props.particle.scale)
		end

		return clone
	elseif props.type == 5 then
		return SpawnPickup(props.name, props.model, props.x, props.y, props.z)
	end

	return nil
end

-- Return all database entities currently attached to the given entity
function GetAttachedChildren(entity)
	local children = {}

	for child, props in pairs(Database) do
		if child ~= entity and props.attachment and props.attachment.to == entity then
			table.insert(children, child)
		end
	end

	return children
end

-- Clone an entity together with every prop/entity attached to it (recursively),
-- re-attaching each cloned child to the cloned parent with the same offsets.
function CloneEntityTree(entity)
	-- Snapshot children and their attachment offsets before cloning,
	-- since cloning adds new entries to the Database.
	local children = GetAttachedChildren(entity)
	local childAttachments = {}

	for _, child in ipairs(children) do
		local a = Database[child].attachment
		childAttachments[child] = {
			bone           = a.bone,
			x              = a.x,
			y              = a.y,
			z              = a.z,
			pitch          = a.pitch,
			roll           = a.roll,
			yaw            = a.yaw,
			useSoftPinning = a.useSoftPinning,
			collision      = a.collision,
			vertex         = a.vertex,
			fixedRot       = a.fixedRot
		}
	end

	local clone = CloneEntityBody(entity)

	if not clone then
		return nil
	end

	for _, child in ipairs(children) do
		local childClone = CloneEntityTree(child)

		if childClone then
			local a = childAttachments[child]
			AttachEntity(childClone, clone, a.bone, a.x, a.y, a.z, a.pitch, a.roll, a.yaw, a.useSoftPinning, a.collision, a.vertex, a.fixedRot)
		end
	end

	return clone
end

function CloneEntity(entity)
	local props = GetEntityProperties(entity)
	local clone = CloneEntityTree(entity)

	if not clone then
		return nil
	end

	-- Re-attach the clone to whatever the original was attached to
	if props.attachment and props.attachment.to ~= 0 then
		AttachEntity(clone, props.attachment.to, props.attachment.bone, props.attachment.x, props.attachment.y, props.attachment.z, props.attachment.pitch, props.attachment.roll, props.attachment.yaw, props.attachment.useSoftPinning, props.attachment.collision, props.attachment.vertex, props.attachment.fixedRot)
	end

	return clone
end

RegisterNUICallback('cloneEntity', function(data, cb)
	if Permissions.properties.clone and CanModifyEntity(data.handle) then
		local clone = CloneEntity(data.handle)

		if clone then
			OpenPropertiesMenuForEntity(clone)
		end
	end

	cb({})
end)

RegisterNUICallback('closeHelpMenu', function(data, cb)
	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('getIntoVehicle', function(data, cb)
	if Permissions.properties.vehicle.getin then
		DisableSpoonerMode()
		RequestControl(data.handle)
		TaskWarpPedIntoVehicle(PlayerPedId(), data.handle, -1)
	end
	cb({})
end)

RegisterNUICallback('repairVehicle', function(data, cb)
	if Permissions.properties.vehicle.repair and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		SetVehicleFixed(data.handle)
	end
	cb({})
end)

RegisterNUICallback('attackPed', function(data, cb)
	if Permissions.properties.ped.attack and CanModifyEntity(data.handle) then
		RequestControl(data.handle)
		TaskCombatPed(data.handle, data.ped)
	end
	cb {}
end)

