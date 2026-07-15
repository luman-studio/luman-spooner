-- ============================================================================
-- spooner :: client/behavior.lua
-- Patrol + Lasso behavior, favourites, init NUI callback, speeds, teleport, clone entity, misc callbacks
--
-- Part of the split client.lua. All spooner client modules share one Lua state
-- and _G, so globals defined in any module are visible to the others.
-- ============================================================================

-- ===================== Movements behavior =====================
-- A ped moves from point A (its current position) to point B, with flags:
--   run   -- run (Config.PatrolRunSpeed) vs walk (Config.PatrolWalkSpeed)
--   lasso -- put the lasso in hand and twirl it over the head while moving
--   loop  -- on reaching B, teleport back to A and go again forever; when off it
--            walks/rides A->B once and STOPS at B.
-- The config is stored on the ped (Database[ped].behavior) so it saves with
-- Saved/MP peds and the scene DB, and restarts when the ped is spawned/placed.

BehaviorPeds = BehaviorPeds or {}   -- [rider] = true while its behavior thread runs
PendingBehavior = nil               -- { entity, a = {x,y,z}, opts } while picking B

local function EquipLasso(ped)
	EquipWeaponInHand(ped, GetHashKey(Config.PatrolLassoWeapon))
end

-- Movement, the lasso weapon and the twirl animation are all tasked on the RIDER
-- (the ped itself) — the mount/seat relationship is a persistent attachment state
-- independent of the task system, so the engine routes locomotion through whatever
-- the rider is seated on automatically (confirmed against R*'s own decompiled
-- mounted-patrol AI script). Tasking the MOVER (horse) directly instead is what
-- causes a dismount: it makes the horse behave like an independent walking ped and
-- fight the fact that it's carrying a rider.
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

function StopMovement(entity)
	local rider, mover = ResolvePatrolActors(entity)

	BehaviorPeds[rider] = nil

	if Database[rider] then
		Database[rider].behavior = nil
	end

	if DoesEntityExist(rider) then
		-- Freezing below is what actually halts visible movement; clearing the go-to
		-- task here is just cleanup so it doesn't silently keep running underneath.
		ClearPedTasks(rider)

		-- Freeze right away rather than waiting for the movement thread's own loop to
		-- notice BehaviorPeds went nil and freeze on its next tick — StartMovement's
		-- thread does the same once it exits, this just removes the one-frame gap.
		FreezeEntityPosition(rider, true)
	end

	if mover ~= rider and DoesEntityExist(mover) then
		FreezeEntityPosition(mover, true)
	end
end

-- Backwards-compatible alias (older callers / saved data may reference the name).
StopPatrolLasso = StopMovement

-- Moves `entity` from A to B. opts = { run, lasso, loop } (all booleans).
function StartMovement(entity, a, b, opts)
	if not DoesEntityExist(entity) then
		return
	end

	opts = opts or {}
	local run   = opts.run   and true or false
	local lasso = opts.lasso and true or false
	local loop  = opts.loop  and true or false

	local rider, mover = ResolvePatrolActors(entity)

	-- Store the route as an offset (B - A) plus the flags, so it saves with Saved/MP
	-- peds and the scene DB and can be replayed relative to wherever the ped is later
	-- spawned.
	if Database[rider] then
		Database[rider].behavior = {
			type = 'movement',
			offset = { x = b.x - a.x, y = b.y - a.y, z = b.z - a.z },
			run = run,
			lasso = lasso,
			loop = loop
		}
	end

	BehaviorPeds[rider] = true

	RequestControl(rider)
	RequestControl(mover)
	SetBlockingOfNonTemporaryEvents(rider, true)

	local mounted = rider ~= mover

	-- Belt-and-suspenders: entities mounted before this flag existed (e.g. restored
	-- from an older saved scene) never got it set in SetPedOnMount. Safe/cheap to
	-- reassert here every time movement starts.
	if mounted then
		SetHorseScriptedFlag(mover, true)
	end

	-- Tasked movement does nothing on a frozen entity — every ped placed by spooner
	-- stays frozen permanently once placed (see spooner:onEntityUnselected in
	-- main.lua), so a ped/horse just picked from Properties is almost always frozen
	-- and would otherwise sit dead still no matter what task it's given. Unfreeze
	-- both halves of a mounted pair (the horse carries the rider along as it moves,
	-- so both need to be free) or just the one ped when not mounted. Re-frozen once
	-- the movement actually stops (see the thread's end and StopMovement below), to
	-- match every other placed entity staying put until explicitly moved again.
	FreezeEntityPosition(rider, false)
	if mounted then
		FreezeEntityPosition(mover, false)
	end

	local speed = run and Config.PatrolRunSpeed or Config.PatrolWalkSpeed
	local twirl = lasso and Config.LassoTwirlAnim or nil

	CreateThread(function()
		while DoesEntityExist(rider) and DoesEntityExist(mover) and BehaviorPeds[rider] do
			-- (re)start each leg at A. When mounted, the horse+rider seat/attachment is
			-- a persistent state independent of the task system (confirmed against R*'s
			-- own decompiled mounted-patrol AI script), so clearing/re-tasking the RIDER
			-- does not drop it out of the saddle — clearing/tasking the MOVER (horse)
			-- directly is what causes that, because it makes the horse behave like an
			-- independent walking ped and fight the fact that it's carrying a rider.
			if mounted then
				-- Soft clear (not Immediate) so the seat/riding task isn't yanked out
				-- from under the rider mid-frame.
				ClearPedTasks(rider)
				-- Teleport the horse back to A, then re-seat the rider: warping the mount
				-- unseats it, so SetPedOnMount puts it straight back in the saddle.
				SetEntityCoordsNoOffset(mover, a.x, a.y, a.z)
				PlaceOnGroundProperly(mover)
				SetPedOnMount(rider, mover, -1, false)
			else
				ClearPedTasksImmediately(mover)
				SetEntityCoordsNoOffset(mover, a.x, a.y, a.z)
				PlaceOnGroundProperly(mover)
			end

			if lasso then
				-- Make sure the lasso is out and in the RIDER's hand (not the mover's).
				EquipLasso(rider)
				Wait(50)
			end

			-- Movement is tasked on the RIDER (the ped itself, mounted or not) — the
			-- engine routes locomotion through the horse it's seated on automatically.
			-- TaskGoToCoordAnyMeans's "preferred vehicle" param was tried and rejected:
			-- passing the horse there confuses its any-means pathing and pops the rider
			-- off immediately. TaskFollowNavMeshToCoord has no such param.
			TaskFollowNavMeshToCoord(rider, b.x, b.y, b.z, speed, Config.PatrolTimeout, Config.PatrolReachDist, 0, 0.0)

			if twirl and twirl.dict and twirl.dict ~= '' then
				-- The mover runs/rides to B (drives the legs/gait), then the twirl clip
				-- is layered on the RIDER's upper body only via a bone-mask filter.
				RequestAnimDict(twirl.dict)
				local t = 0
				while not HasAnimDictLoaded(twirl.dict) and t < 100 do
					Wait(0)
					t = t + 1
				end

				Wait(50) -- let the go-to task take hold first

				TaskPlayAnim(rider, twirl.dict, twirl.name, twirl.blendIn or 1.0, twirl.blendOut or 1.0, -1, twirl.flag or 25, 0.0, false, false, false, twirl.filter or '', false)
			end

			local elapsed = 0

			while DoesEntityExist(mover) and BehaviorPeds[rider] do
				Wait(200)
				elapsed = elapsed + 200

				-- Watchdog: if the twirl clip isn't playing anymore (the engine may not
				-- honour REPEAT forever on a secondary task, so it can quietly stop after
				-- a pass), restart it right away so the twirl never visibly cuts out.
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

			-- Not looping: reached B (or timed out) — stop here, leaving the ped at B.
			if not loop then
				break
			end
		end

		BehaviorPeds[rider] = nil

		-- Movement has ended (arrived with loop off, or the loop was stopped
		-- elsewhere) — freeze again so it stays put like every other placed entity,
		-- instead of being left free to be shoved around by physics/other peds.
		if DoesEntityExist(rider) then
			FreezeEntityPosition(rider, true)
		end

		if mounted and DoesEntityExist(mover) then
			FreezeEntityPosition(mover, true)
		end

		-- A one-shot movement is finished the moment it arrives; drop the lasso twirl
		-- but leave the ped standing where it arrived. It also no longer carries a live
		-- looping behavior, so clear the stored config (a looped one is cleared via the
		-- Stop button / StopMovement instead).
		if not loop and DoesEntityExist(rider) then
			if lasso then
				ClearPedSecondaryTask(rider)
			end

			if Database[rider] then
				Database[rider].behavior = nil
			end
		end
	end)
end

-- Backwards-compatible alias for the old lasso-patrol signature (always run + lasso
-- + loop), used by any legacy caller.
function StartPatrolLasso(entity, a, b)
	StartMovement(entity, a, b, { run = true, lasso = true, loop = true })
end

-- Start (or restart) a ped's stored behavior relative to its current position.
-- Used when a Saved/MP ped (or scene DB ped) that carries a behavior is placed.
function RestartBehavior(entity)
	local rider, mover = ResolvePatrolActors(entity)
	local beh = Database[rider] and Database[rider].behavior

	if beh and beh.offset and not BehaviorPeds[rider] and (beh.type == 'movement' or beh.type == 'patrolLasso') then
		local x, y, z = table.unpack(GetEntityCoords(mover))
		local a = { x = x, y = y, z = z }
		local b = { x = x + beh.offset.x, y = y + beh.offset.y, z = z + beh.offset.z }

		local opts
		if beh.type == 'patrolLasso' then
			-- Legacy "Patrol + Lasso" saved before the flags existed: always run,
			-- lasso and loop, matching the old fixed behavior.
			opts = { run = true, lasso = true, loop = true }
		else
			opts = { run = beh.run, lasso = beh.lasso, loop = beh.loop }
		end

		StartMovement(rider, a, b, opts)
	end
end

RegisterNUICallback('setupMovement', function(data, cb)
	local handle = data.handle

	if DoesEntityExist(handle) and GetEntityType(handle) == 1 then
		local rider, mover = ResolvePatrolActors(handle)
		local x, y, z = table.unpack(GetEntityCoords(mover))
		PendingBehavior = {
			entity = rider,
			a = { x = x, y = y, z = z },
			opts = {
				run = data.run and true or false,
				lasso = data.lasso and true or false,
				loop = data.loop and true or false
			}
		}

		notify('Aim at point B and press ' .. (Config.isRDR and 'Left Mouse' or 'LMB') .. ' — press Right Mouse to cancel')
	end

	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('clearMovement', function(data, cb)
	if DoesEntityExist(data.handle) then
		StopMovement(data.handle)
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

		-- Face the camera, not away from it — this ped immediately becomes
		-- AttachedEntity/selected below, which applies the frozen/T-pose +180
		-- pre-offset (see spooner:onEntitySelected) on top of whatever's stored
		-- here, so start from camera yaw + 180 to land on "facing the camera".
		local yaw2 = yaw + 180.0
		if yaw2 < 0.0 then
			yaw2 = yaw2 + 360.0
		elseif yaw2 >= 360.0 then
			yaw2 = yaw2 - 360.0
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

