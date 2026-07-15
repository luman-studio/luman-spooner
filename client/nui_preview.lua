-- ============================================================================
-- spooner :: client/nui_preview.lua
-- Spawn-menu NUI callbacks and entity preview (SpawnPreview/ClearPreview) callbacks
--
-- Part of the split client.lua. All spooner client modules share one Lua state
-- and _G, so globals defined in any module are visible to the others.
-- ============================================================================

RegisterNUICallback('closeSpawnMenu', function(data, cb)
	SetNuiFocus(false, false)
	cb({})
end)

function Contains(list, item)
	for _, value in ipairs(list) do
		if value == item then
			return true
		end
	end
	return false
end

RegisterNUICallback('closePedMenu', function(data, cb)
	if data.modelName and (Permissions.spawn.byName or Contains(Peds, data.modelName)) then
		CurrentSpawn = {
			modelName = data.modelName,
			type = 1
		}
	end
	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('closeVehicleMenu', function(data, cb)
	if data.modelName and (Permissions.spawn.byName or Contains(Vehicles, data.modelName)) then
		CurrentSpawn = {
			modelName = data.modelName,
			type = 2
		}
	end
	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('closeObjectMenu', function(data, cb)
	-- Clear preview when closing menu
	ClearObjectPreview()

	if data.modelName and (Permissions.spawn.byName or Contains(Objects, data.modelName)) then
		CurrentSpawn = {
			modelName = data.modelName,
			type = 3
		}
	end
	SetNuiFocus(false, false)
	cb({})
end)

RegisterNUICallback('spawnAndAttachObject', function(data, cb)
	-- Clear preview first
	ClearObjectPreview()

	if data.modelName and (Permissions.spawn.byName or Contains(Objects, data.modelName)) then
		-- Remember selection so it can be re-spawned with the spawn control (E)
		CurrentSpawn = {
			modelName = data.modelName,
			type = 3
		}

		-- Get spawn position from camera view
		local x, y, z = table.unpack(GetCamCoord(Cam))
		local pitch, roll, yaw = table.unpack(GetCamRot(Cam, 2))
		local spawnPos = GetInView(x, y, z, pitch, roll, yaw)

		-- Calculate yaw from camera
		local yaw2 = yaw
		if yaw2 < 0.0 then
			yaw2 = yaw2 + 360.0
		end

		-- Spawn the object
		local entity = SpawnObject(data.modelName, ResolveModelHash(data.modelName), spawnPos.x, spawnPos.y, spawnPos.z, 0.0, 0.0, yaw2, false, true, nil, nil, nil)

		if entity then
			PlaceOnGroundProperly(entity)

			-- Attach to camera immediately
			TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
			AttachedEntity = entity
			TriggerEvent('spooner:onEntitySelected', AttachedEntity)
		end
	end
	SetNuiFocus(false, false)
	cb({})
end)

-- ============================================================================
-- Unified Preview System
-- ============================================================================

-- Preview types: 'ped', 'vehicle', 'object', 'propset', 'pickup', 'particle'
local PreviewType = nil
local PreviewParticleHandle = nil
-- Propsets and pickups aren't ordinary CreateObject entities (they use their own
-- CreatePropset/CreatePickup APIs), so they can't live in PreviewEntity — tracked
-- separately here and torn down in ClearPreview alongside it.
local PreviewPropset = nil
local PreviewPickup = nil

function ClearPreview()
	if PreviewParticleHandle and DoesParticleFxLoopedExist(PreviewParticleHandle) then
		RemoveParticleFx(PreviewParticleHandle, false)
	end
	PreviewParticleHandle = nil

	if PreviewEntity and DoesEntityExist(PreviewEntity) then
		DeleteEntity(PreviewEntity)
	end
	PreviewEntity = nil

	if PreviewPropset and PreviewPropset > 0 and DoesPropsetExist(PreviewPropset) then
		DeletePropset(PreviewPropset, false, false)
	end
	PreviewPropset = nil

	if PreviewPickup and PreviewPickup > 0 then
		RemovePickup(PreviewPickup)
	end
	PreviewPickup = nil

	PreviewModelName = nil
	PreviewType = nil
end

-- Legacy alias for backward compatibility
function ClearObjectPreview()
	ClearPreview()
end

function SpawnPreview(modelName, entityType)
	-- Don't spawn if same model already previewing (any of the three preview kinds).
	if PreviewModelName == modelName and (
		(PreviewEntity and DoesEntityExist(PreviewEntity))
		or (PreviewPropset and PreviewPropset > 0 and DoesPropsetExist(PreviewPropset))
		or (PreviewPickup and PreviewPickup > 0)
	) then
		return
	end

	-- Clear existing preview first
	ClearPreview()

	-- Particles use a different loading path entirely: modelName is "dict/fx", not
	-- a real model, so the generic ResolveModelHash/IsModelInCdimage check below
	-- doesn't apply. The preview is the same invisible anchor + attached looped FX
	-- used for the real spawn, just not added to Database.
	if entityType == 'particle' then
		local dict, fx = string.match(modelName, '^(.-)/(.+)$')

		if not dict or not fx then
			return
		end

		local anchorModel = GetHashKey(Config.ParticleAnchorModel)

		if not LoadModel(anchorModel) then
			return
		end

		CreateThread(function()
			local requestedModel = modelName

			if PreviewModelName ~= nil then
				SetModelAsNoLongerNeeded(anchorModel)
				return
			end

			if not Cam then
				SetModelAsNoLongerNeeded(anchorModel)
				return
			end

			local x, y, z = table.unpack(GetCamCoord(Cam))
			local pitch, roll, yaw = table.unpack(GetCamRot(Cam, 2))
			local spawnPos, _, _ = GetInView(x, y, z, pitch, roll, yaw)

			PreviewEntity = CreateObjectNoOffset(anchorModel, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false)

			SetModelAsNoLongerNeeded(anchorModel)

			if PreviewEntity and PreviewEntity > 0 then
				PreviewModelName = requestedModel
				PreviewType = 'particle'

				-- See SpawnParticleEffect: alpha 0, not SetEntityVisible(false), or the
				-- attached particle gets culled along with the entity.
				SetEntityAlpha(PreviewEntity, 0, false)
				SetEntityCollision(PreviewEntity, false, false)
				FreezeEntityPosition(PreviewEntity, true)

				PreviewParticleHandle = PlayParticleEffect(PreviewEntity, dict, fx, 1.0)
			end
		end)

		return
	end

	-- Propsets aren't a single CreateObject model — they expand into a set of props
	-- via the propset API. Load + create the real propset in front of the camera as
	-- the preview (torn down via DeletePropset in ClearPreview). It doesn't follow
	-- the cursor like PreviewEntity does — it's a stationary "what does this look
	-- like" preview at the moment of selection.
	if entityType == 'propset' then
		local propModel = ResolveModelHash(modelName)

		RequestPropset(propModel)

		CreateThread(function()
			local requestedModel = modelName
			local tries = 0

			while not HasPropsetLoaded(propModel) and tries < 200 do
				Wait(10)
				tries = tries + 1

				-- Selection changed/cleared while loading — abort.
				if PreviewModelName ~= nil then
					ReleasePropset(propModel)
					return
				end
			end

			if not HasPropsetLoaded(propModel) or not Cam then
				ReleasePropset(propModel)
				return
			end

			local x, y, z = table.unpack(GetCamCoord(Cam))
			local pitch, roll, yaw = table.unpack(GetCamRot(Cam, 2))
			local spawnPos = GetInView(x, y, z, pitch, roll, yaw)

			PreviewPropset = CreatePropset(propModel, spawnPos.x, spawnPos.y, spawnPos.z, 0, yaw, 0.0, false, false)

			ReleasePropset(propModel)

			if PreviewPropset and PreviewPropset > 0 then
				PreviewModelName = requestedModel
				PreviewType = 'propset'
			end
		end)

		return
	end

	-- Pickups use the pickup API (a pickup type hash, not an object model), so create
	-- a real pickup in front of the camera as the preview (removed via RemovePickup in
	-- ClearPreview). Stationary, same as the propset preview above.
	if entityType == 'pickup' then
		local pickupModel = ResolveModelHash(modelName)

		if not IsPickupTypeValid(pickupModel) or not Cam then
			return
		end

		local x, y, z = table.unpack(GetCamCoord(Cam))
		local pitch, roll, yaw = table.unpack(GetCamRot(Cam, 2))
		local spawnPos = GetInView(x, y, z, pitch, roll, yaw)

		-- Flags: 32 (LowPriority, as the real spawn uses) + 8 (SNAP_TO_GROUND) so the
		-- pickup lands on the surface instead of dropping through it. Some pickup
		-- models still settle via physics, so also freeze their object on the ground
		-- below as a backstop.
		PreviewPickup = CreatePickup(pickupModel, spawnPos.x, spawnPos.y, spawnPos.z, 32 + 8, 0, false, 0, 0, 0.0, 0)

		if PreviewPickup and PreviewPickup > 0 then
			PreviewModelName = modelName
			PreviewType = 'pickup'

			local createdPickup = PreviewPickup

			CreateThread(function()
				-- The pickup's visible object isn't available the same frame it's
				-- created — wait for it, then pin it to the ground so it can't fall.
				local tries = 0
				local obj = 0

				while tries < 50 do
					Wait(0)
					tries = tries + 1

					-- Preview changed/cleared while waiting — stop.
					if PreviewPickup ~= createdPickup then
						return
					end

					obj = Citizen.InvokeNative(0x5099BC55630B25AE, createdPickup) -- GET_PICKUP_OBJECT

					if obj and obj > 0 and DoesEntityExist(obj) then
						break
					end
				end

				if obj and obj > 0 and DoesEntityExist(obj) then
					PlaceOnGroundProperly(obj)
					FreezeEntityPosition(obj, true)
				end
			end)
		end

		return
	end

	local model = ResolveModelHash(modelName)

	-- Check if model is valid and can be loaded
	if not IsModelInCdimage(model) then
		return
	end

	RequestModel(model)

	-- Wait for model to load with timeout (async)
	CreateThread(function()
		local timeout = 50
		local requestedModel = modelName
		local requestedType = entityType
		while not HasModelLoaded(model) and timeout > 0 do
			Wait(10)
			timeout = timeout - 1
			-- Check if preview was cancelled or changed
			if PreviewModelName ~= nil then
				return
			end
		end

		if not HasModelLoaded(model) then
			return
		end

		-- Get spawn position in front of camera
		if Cam then
			local x, y, z = table.unpack(GetCamCoord(Cam))
			local pitch, roll, yaw = table.unpack(GetCamRot(Cam, 2))
			local spawnPos, _, _ = GetInView(x, y, z, pitch, roll, yaw)

			-- Create preview entity based on type
			if requestedType == 'ped' then
				-- Frozen peds (no active task) consistently render 180° from whatever
				-- heading is stored (see spooner:onEntitySelected in main.lua) — offset it
				-- here too so the preview visually faces the same way the ped actually
				-- ends up facing once spawned (heading 0).
				if Config.isRDR then
					PreviewEntity = CreatePed_2(model, spawnPos.x, spawnPos.y, spawnPos.z, 180.0, false, false)
				else
					PreviewEntity = CreatePed(0, model, spawnPos.x, spawnPos.y, spawnPos.z, 180.0, false, false)
				end
			elseif requestedType == 'vehicle' then
				PreviewEntity = CreateVehicle(model, spawnPos.x, spawnPos.y, spawnPos.z, 0.0, false, false)
			else
				-- Default: object
				PreviewEntity = CreateObjectNoOffset(model, spawnPos.x, spawnPos.y, spawnPos.z, false, false, false)
			end

			SetModelAsNoLongerNeeded(model)

			if PreviewEntity and PreviewEntity > 0 then
				PreviewModelName = requestedModel
				PreviewType = requestedType

				-- Set random outfit for peds (otherwise they're invisible)
				if requestedType == 'ped' then
					SetRandomOutfitVariation(PreviewEntity, true)
				end

				-- Make it semi-transparent and non-solid
				SetEntityAlpha(PreviewEntity, 180, false)
				SetEntityCollision(PreviewEntity, false, false)
				FreezeEntityPosition(PreviewEntity, true)
			end
		end
	end)
end

-- Preview callbacks for all entity types
RegisterNUICallback('previewPed', function(data, cb)
	if data.modelName then
		SpawnPreview(data.modelName, 'ped')
	end
	cb({})
end)

RegisterNUICallback('previewVehicle', function(data, cb)
	if data.modelName then
		SpawnPreview(data.modelName, 'vehicle')
	end
	cb({})
end)

RegisterNUICallback('previewObject', function(data, cb)
	if data.modelName then
		SpawnPreview(data.modelName, 'object')
	end
	cb({})
end)

RegisterNUICallback('previewPropset', function(data, cb)
	if data.modelName then
		SpawnPreview(data.modelName, 'propset')
	end
	cb({})
end)

RegisterNUICallback('previewPickup', function(data, cb)
	if data.modelName then
		SpawnPreview(data.modelName, 'pickup')
	end
	cb({})
end)

RegisterNUICallback('previewParticle', function(data, cb)
	if data.modelName then
		SpawnPreview(data.modelName, 'particle')
	end
	cb({})
end)

-- Clear preview callbacks
RegisterNUICallback('clearPedPreview', function(data, cb)
	ClearPreview()
	cb({})
end)

RegisterNUICallback('clearVehiclePreview', function(data, cb)
	ClearPreview()
	cb({})
end)

RegisterNUICallback('clearObjectPreview', function(data, cb)
	ClearPreview()
	cb({})
end)

RegisterNUICallback('clearPropsetPreview', function(data, cb)
	ClearPreview()
	cb({})
end)

RegisterNUICallback('clearPickupPreview', function(data, cb)
	ClearPreview()
	cb({})
end)

RegisterNUICallback('clearParticlePreview', function(data, cb)
	ClearPreview()
	cb({})
end)

