-- ============================================================================
-- spooner :: client/peds.lua
-- Saved Peds, MP Peds (session clones), and saved Animation+Prop presets
--
-- Part of the split client.lua. All spooner client modules share one Lua state
-- and _G, so globals defined in any module are visible to the others.
-- ============================================================================

-- Saved Peds: persist a single ped (model + animation/scenario + extras) so it
-- can be re-spawned later from the "Saved Peds" category in the spawn menu.

local SAVED_PED_PREFIX = 'SAVEDPED_'

function BuildSavedPedProps(handle, savedName)
	if not DoesEntityExist(handle) then
		return nil
	end

	local db = Database[handle] or {}
	local model = db.model or GetEntityModel(handle)

	-- Capture any props attached to the ped so they can be re-spawned and
	-- re-attached when the saved ped is loaded.
	local attachments = {}
	for _, child in ipairs(GetAttachedChildren(handle)) do
		local cdb = Database[child]
		if cdb and cdb.attachment then
			local a = cdb.attachment
			table.insert(attachments, {
				name = cdb.name,
				model = cdb.model,
				type = cdb.type,
				attachment = {
					bone = a.bone,
					x = a.x, y = a.y, z = a.z,
					pitch = a.pitch, roll = a.roll, yaw = a.yaw,
					useSoftPinning = a.useSoftPinning,
					collision = a.collision,
					vertex = a.vertex,
					fixedRot = a.fixedRot
				}
			})
		end
	end

	return {
		savedName = savedName,
		name = db.name or GetModelName(model),
		model = model,
		outfit = db.outfit or -1,
		animation = db.animation,
		scenario = db.scenario,
		weapons = db.weapons or {},
		walkStyle = db.walkStyle,
		scale = db.scale,
		pedConfigFlags = db.pedConfigFlags or (GetEntityType(handle) == 1 and GetPedConfigFlags(handle) or nil),
		blockNonTemporaryEvents = db.blockNonTemporaryEvents or false,
		attachments = attachments,
		behavior = db.behavior
	}
end

function SaveSavedPed(props)
	SetResourceKvp(SAVED_PED_PREFIX .. props.savedName, json.encode(props))
end

function LoadSavedPed(name)
	local content = GetResourceKvpString(SAVED_PED_PREFIX .. name)
	return content and json.decode(content)
end

function GetSavedPeds()
	local peds = {}

	local handle = StartFindKvp(SAVED_PED_PREFIX)

	while true do
		local kvp = FindKvp(handle)

		if kvp then
			table.insert(peds, string.sub(kvp, #SAVED_PED_PREFIX + 1))
		else
			break
		end
	end

	EndFindKvp(handle)

	table.sort(peds)

	return peds
end

function DeleteSavedPed(name)
	DeleteResourceKvp(SAVED_PED_PREFIX .. name)
end

RegisterNUICallback('saveCurrentPed', function(data, cb)
	if data.name and data.name ~= '' and DoesEntityExist(data.handle) then
		local props = BuildSavedPedProps(data.handle, data.name)

		if props then
			SaveSavedPed(props)
		end
	end

	cb(json.encode(GetSavedPeds()))
end)

RegisterNUICallback('getSavedPeds', function(data, cb)
	cb(json.encode(GetSavedPeds()))
end)

RegisterNUICallback('deleteSavedPed', function(data, cb)
	DeleteSavedPed(data.name)
	cb({})
end)

RegisterNUICallback('renameSavedPed', function(data, cb)
	if data.oldName and data.newName and data.newName ~= '' and data.newName ~= data.oldName then
		local saved = LoadSavedPed(data.oldName)

		if saved then
			saved.savedName = data.newName
			SaveSavedPed(saved)
			DeleteSavedPed(data.oldName)
		end
	end

	cb(json.encode(GetSavedPeds()))
end)

-- ===================== MP Peds =====================
-- MP (freemode) ped appearance is captured two ways:
--  - A hidden ClonePed "template" for the CURRENT session — exact, zero-effort,
--    used whenever it's still alive (fast path, perfect fidelity).
--  - A component-variation snapshot (drawable/texture/palette per slot), which is
--    what actually gets written to disk (KVP) and survives a resource/server
--    restart. It won't capture things a plain component copy can't (e.g. custom
--    face sliders), but it reproduces clothing/hair/etc. closely for most looks.

SavedMpPeds = SavedMpPeds or {}

local MP_PED_PREFIX = 'MPPED_'

-- Snapshot a ped's component variations (drawable/texture/palette per slot).
function CaptureComponents(ped)
	local components = {}

	for i = 0, Config.MpPedComponentSlots do
		local okD, drawable = pcall(GetPedDrawableVariation, ped, i)

		if okD and drawable and drawable >= 0 then
			local okT, texture = pcall(GetPedTextureVariation, ped, i)
			local okP, palette = pcall(GetPedPaletteVariation, ped, i)

			components[tostring(i)] = {
				drawable = drawable,
				texture = (okT and texture) or 0,
				palette = (okP and palette) or 0
			}
		end
	end

	return components
end

-- Re-apply a captured component snapshot to a freshly spawned ped.
function ApplyComponents(ped, components)
	if not components then
		return
	end

	for idxStr, comp in pairs(components) do
		local idx = tonumber(idxStr)

		if idx then
			pcall(SetPedComponentVariation, ped, idx, comp.drawable, comp.texture or 0, comp.palette or 0)
		end
	end
end

-- Strip the runtime-only template handle before writing to KVP (a ped/entity handle
-- means nothing after a restart) and persist the rest.
function SaveMpPedToKvs(entry)
	local persisted = {
		name = entry.name,
		model = entry.model,
		components = entry.components,
		weapons = entry.weapons,
		animation = entry.animation,
		scenario = entry.scenario,
		outfit = entry.outfit,
		behavior = entry.behavior,
		weaponInHand = entry.weaponInHand
	}

	if entry.horse then
		persisted.horse = {
			model = entry.horse.model,
			components = entry.horse.components
		}
	end

	SetResourceKvp(MP_PED_PREFIX .. entry.name, json.encode(persisted))
end

function DeleteMpPedFromKvs(name)
	DeleteResourceKvp(MP_PED_PREFIX .. name)
end

-- Load every persisted MP ped back into SavedMpPeds at resource start. These
-- entries have no `template` (clones don't survive a restart), so spawnMpPed
-- falls back to rebuilding the look from `components`.
function LoadMpPedsFromKvs()
	local handle = StartFindKvp(MP_PED_PREFIX)

	while true do
		local kvp = FindKvp(handle)

		if kvp then
			local content = GetResourceKvpString(kvp)
			local ok, data = pcall(json.decode, content or '')

			if ok and data and data.name then
				SavedMpPeds[data.name] = data
			end
		else
			break
		end
	end

	EndFindKvp(handle)
end

LoadMpPedsFromKvs()

local function CreatePedTemplate(ped)
	local clone = ClonePed(ped, true, true, true)

	if not clone or clone < 1 then
		return nil
	end

	SetEntityAsMissionEntity(clone, true, true)
	SetEntityVisible(clone, false)
	SetEntityCollision(clone, false, false)
	FreezeEntityPosition(clone, true)
	SetEntityInvincible(clone, true)
	ClearPedTasksImmediately(clone)
	SetBlockingOfNonTemporaryEvents(clone, true)

	return clone
end

-- Reset the flags a fresh clone may inherit from the (hidden) template
local function PrepareClone(handle)
	SetEntityVisible(handle, true)
	FreezeEntityPosition(handle, false)
	SetEntityCollision(handle, true, true)
	SetEntityInvincible(handle, false)
	SetBlockingOfNonTemporaryEvents(handle, false)
end

-- Give a weapon and put it in the ped's hand (loading the weapon asset first, or the
-- ped ends up "holding" nothing / the weapon renders in the wrong place).
function EquipWeaponInHand(ped, hash)
	if not hash or hash == 0 or hash == GetHashKey('WEAPON_UNARMED') then
		return
	end

	RequestWeaponAsset(hash, 31, 0)
	local tries = 0
	while not HasWeaponAssetLoaded(hash) and tries < 100 do
		Wait(0)
		tries = tries + 1
	end

	if Config.isRDR then
		GiveWeaponToPed_2(ped, hash, 500, true, false, 0, false, 0.5, 1.0, 0, false, 0.0, false)
	else
		GiveWeaponToPed(ped, hash, 500, false, true)
	end

	SetCurrentPedWeapon(ped, hash, true)
	SetPedCurrentWeaponVisible(ped, true, false, false, false)
end

local function DeleteTemplate(handle)
	if handle and DoesEntityExist(handle) then
		SetEntityAsMissionEntity(handle, true, true)
		DeleteEntity(handle)
	end
end

function GetMpPedNames()
	local names = {}
	for name in pairs(SavedMpPeds) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function DeleteMpPed(name)
	local entry = SavedMpPeds[name]

	if entry then
		DeleteTemplate(entry.template)
		if entry.horse then
			DeleteTemplate(entry.horse.template)
		end
		SavedMpPeds[name] = nil
	end

	DeleteMpPedFromKvs(name)
end

-- Resource-stop cleanup only: destroys the hidden same-session clone templates so
-- they don't leak. Does NOT touch the KVP-persisted entries — those must survive
-- the restart (unlike DeleteMpPed, which is for an explicit user delete).
function ClearMpPedTemplates()
	for _, entry in pairs(SavedMpPeds) do
		DeleteTemplate(entry.template)
		if entry.horse then
			DeleteTemplate(entry.horse.template)
		end
		entry.template = nil
		if entry.horse then
			entry.horse.template = nil
		end
	end
end

RegisterNUICallback('saveCurrentMpPed', function(data, cb)
	local handle = data.handle
	local name = data.name

	if name and name ~= '' and DoesEntityExist(handle) and GetEntityType(handle) == 1 then
		DeleteMpPed(name) -- replace any existing entry with the same name (memory + disk)

		-- The clone template is a same-session convenience (perfect fidelity, zero
		-- effort); it may fail to create, but that must not block saving — the
		-- component snapshot below is what actually gets persisted to disk.
		local template = CreatePedTemplate(handle)
		local components = CaptureComponents(handle)

		local db = Database[handle] or {}

		-- Capture the in-hand weapon safely; these natives may be absent on some
		-- builds and must not abort the whole save if they error.
		local weaponInHand = nil

		local okC, _, curHash = pcall(GetCurrentPedWeapon, handle, true)
		if okC and curHash and curHash ~= 0 then
			weaponInHand = curHash
		end

		if not weaponInHand then
			local okS, selHash = pcall(GetSelectedPedWeapon, handle)
			if okS and selHash and selHash ~= 0 then
				weaponInHand = selHash
			end
		end

		local entry = {
			name = name,
			template = template,
			model = GetEntityModel(handle),
			components = components,
			weapons = db.weapons or {},
			animation = db.animation,
			scenario = db.scenario,
			outfit = db.outfit or -1,
			behavior = db.behavior,
			weaponInHand = weaponInHand
		}

		-- Save the horse it is riding, if any
		local mount = GetMount(handle)
		if mount and mount ~= 0 and DoesEntityExist(mount) then
			entry.horse = {
				template = CreatePedTemplate(mount),
				model = GetEntityModel(mount),
				components = CaptureComponents(mount)
			}
		end

		SavedMpPeds[name] = entry
		SaveMpPedToKvs(entry)
	end

	cb(json.encode(GetMpPedNames()))
end)

RegisterNUICallback('getMpPeds', function(data, cb)
	cb(json.encode(GetMpPedNames()))
end)

RegisterNUICallback('deleteMpPed', function(data, cb)
	DeleteMpPed(data.name)
	cb({})
end)

RegisterNUICallback('renameMpPed', function(data, cb)
	if data.oldName and data.newName and data.newName ~= '' and data.newName ~= data.oldName then
		local entry = SavedMpPeds[data.oldName]

		if entry then
			entry.name = data.newName
			SavedMpPeds[data.newName] = entry
			SavedMpPeds[data.oldName] = nil

			DeleteMpPedFromKvs(data.oldName)
			SaveMpPedToKvs(entry)
		end
	end

	cb(json.encode(GetMpPedNames()))
end)

-- Spawn one MP ped/horse from a saved entry: uses the exact same-session clone
-- template when it's still alive, otherwise rebuilds the look from the saved
-- component snapshot (the path used after a resource/server restart).
local function SpawnMpPedFromEntry(pedEntry, x, y, z, yaw, extraProps)
	local props = {
		model = ResolveModelHash(pedEntry.model),
		name = GetModelName(pedEntry.model),
		x = x, y = y, z = z,
		pitch = 0.0, roll = 0.0, yaw = yaw,
		collisionDisabled = false,
		isVisible = true,
		outfit = pedEntry.outfit or -1,
		keepAppearance = true,
		isInGroup = false,
		blockNonTemporaryEvents = false
	}

	for k, v in pairs(extraProps or {}) do
		props[k] = v
	end

	if pedEntry.template and DoesEntityExist(pedEntry.template) then
		local clone = ClonePed(pedEntry.template, true, true, true)

		if not clone or clone <= 0 then
			return nil
		end

		PrepareClone(clone)
		props.handle = clone

		return SpawnPed(props)
	end

	-- No live template (e.g. after a restart/rejoin): spawn the base model and
	-- rebuild the look from the saved component variations.
	local ped = SpawnPed(props)

	if ped then
		-- A freshly created freemode/MP ped model is "bare" (no default outfit) and
		-- renders invisible/transparent until it's given at least a default set of
		-- component variations — this is what other RedM menus do before applying a
		-- custom look, and what was missing here. Then layer the saved look on top
		-- and force visibility, since the engine doesn't reliably turn it back on by
		-- itself once components are set.
		pcall(SetPedDefaultComponentVariation, ped)
		ApplyComponents(ped, pedEntry.components)
		SetEntityVisible(ped, true)
	end

	return ped
end

RegisterNUICallback('spawnMpPed', function(data, cb)
	ClearPreview()

	local entry = SavedMpPeds[data.name]

	if entry then
		local x, y, z = table.unpack(GetCamCoord(Cam))
		local pitch, roll, yaw = table.unpack(GetCamRot(Cam, 2))
		local spawnPos = GetInView(x, y, z, pitch, roll, yaw)

		local yaw2 = yaw
		if yaw2 < 0.0 then
			yaw2 = yaw2 + 360.0
		end

		local ped = SpawnMpPedFromEntry(entry, spawnPos.x, spawnPos.y, spawnPos.z, yaw2, {
			animation = entry.animation,
			scenario = entry.scenario,
			weapons = entry.weapons
		})

		if ped and entry.behavior and Database[ped] then
			Database[ped].behavior = entry.behavior
		end

		-- Put the ped's in-hand weapon (e.g. lasso) back into its hand; cloning keeps
		-- it holstered, so it looks missing / ends up in the wrong place.
		if ped and entry.weaponInHand and entry.weaponInHand ~= 0 and entry.weaponInHand ~= GetHashKey('WEAPON_UNARMED') then
			EquipWeaponInHand(ped, entry.weaponInHand)
		end

		local grabTarget = ped
		local grabNoFreeze = false

		-- Re-spawn the horse and put the ped on it
		if ped and entry.horse then
			local horse = SpawnMpPedFromEntry(entry.horse, spawnPos.x, spawnPos.y, spawnPos.z, yaw2)

			if horse then
				PlaceOnGroundProperly(horse)

				-- The lasso in RDR2 lives on the horse (saddle rope). The clone/rebuild
				-- carries it, so it dangles under the horse. The rider already holds his
				-- own, so strip the horse's weapons to remove the extra rope.
				RemoveAllPedWeapons(horse, true)

				-- Let both fully stream in, then seat the rider. Mounting a
				-- just-created horse in the same frame leaves the rider standing
				-- in a T-pose at the horse's centre.
				Wait(300)
				SetPedOnMount(ped, horse, -1, false)

				-- Grab the HORSE so the pair can still be positioned, but WITHOUT
				-- freezing it (freezing dismounts the rider into a T-pose).
				grabTarget = horse
				grabNoFreeze = true
			end
		end

		if ped then
			CurrentSpawn = nil
			PlaceOnGroundProperly(grabTarget)
			GrabNoFreeze = grabNoFreeze
			TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
			AttachedEntity = grabTarget
			TriggerEvent('spooner:onEntitySelected', AttachedEntity)
		end
	end

	SetNuiFocus(false, false)
	cb({})
end)

-- ===================== Saved Animation + Prop presets =====================
-- Captures a ped's current animation and its first attached prop as one reusable
-- preset (persisted to disk), so it can be applied later to any other ped: play
-- the animation and re-spawn+attach the same prop with the same bone/offset.

local ANIMPROP_PREFIX = 'ANIMPROP_'

SavedAnimProps = SavedAnimProps or {}

-- In-session clipboard filled by "Copy Animation + Prop"; "Save" persists whatever
-- is currently held here under a name.
local CopiedAnimationProp = nil

function SaveAnimPropToKvs(entry)
	SetResourceKvp(ANIMPROP_PREFIX .. entry.name, json.encode(entry))
end

function DeleteAnimPropFromKvs(name)
	DeleteResourceKvp(ANIMPROP_PREFIX .. name)
end

function LoadAnimPropsFromKvs()
	local handle = StartFindKvp(ANIMPROP_PREFIX)

	while true do
		local kvp = FindKvp(handle)

		if kvp then
			local content = GetResourceKvpString(kvp)
			local ok, data = pcall(json.decode, content or '')

			if ok and data and data.name then
				SavedAnimProps[data.name] = data
			end
		else
			break
		end
	end

	EndFindKvp(handle)
end

LoadAnimPropsFromKvs()

function GetAnimPropNames()
	local names = {}
	for name in pairs(SavedAnimProps) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function DeleteAnimProp(name)
	SavedAnimProps[name] = nil
	DeleteAnimPropFromKvs(name)
end

RegisterNUICallback('copyAnimationProp', function(data, cb)
	local entity = data.handle

	local anim = GetAnimationInfo(entity)
	if not anim and Database[entity] then
		anim = Database[entity].animation
	end

	-- Capture every prop currently attached to the ped, not just one.
	local props = {}

	for _, child in ipairs(GetAttachedChildren(entity)) do
		local cdb = Database[child]

		if cdb then
			local a = cdb.attachment

			table.insert(props, {
				name = cdb.name,
				model = cdb.model,
				attachment = {
					bone = a.bone,
					x = a.x, y = a.y, z = a.z,
					pitch = a.pitch, roll = a.roll, yaw = a.yaw,
					useSoftPinning = a.useSoftPinning,
					collision = a.collision,
					vertex = a.vertex,
					fixedRot = a.fixedRot
				}
			})
		end
	end

	if anim or #props > 0 then
		CopiedAnimationProp = {
			animation = anim,
			props = props
		}

		cb({ ok = true, hasAnimation = anim ~= nil, propCount = #props })
	else
		CopiedAnimationProp = nil
		cb({ ok = false })
	end
end)

RegisterNUICallback('saveAnimationProp', function(data, cb)
	if data.name and data.name ~= '' and CopiedAnimationProp then
		local entry = {
			name = data.name,
			animation = CopiedAnimationProp.animation,
			props = CopiedAnimationProp.props
		}

		SavedAnimProps[data.name] = entry
		SaveAnimPropToKvs(entry)
	end

	cb(json.encode(GetAnimPropNames()))
end)

RegisterNUICallback('getAnimProps', function(data, cb)
	cb(json.encode(GetAnimPropNames()))
end)

RegisterNUICallback('deleteAnimProp', function(data, cb)
	DeleteAnimProp(data.name)
	cb({})
end)

RegisterNUICallback('renameAnimProp', function(data, cb)
	if data.oldName and data.newName and data.newName ~= '' and data.newName ~= data.oldName then
		local entry = SavedAnimProps[data.oldName]

		if entry then
			entry.name = data.newName
			SavedAnimProps[data.newName] = entry
			SavedAnimProps[data.oldName] = nil

			DeleteAnimPropFromKvs(data.oldName)
			SaveAnimPropToKvs(entry)
		end
	end

	cb(json.encode(GetAnimPropNames()))
end)

RegisterNUICallback('applyAnimProp', function(data, cb)
	local entity = data.handle
	local entry = SavedAnimProps[data.name]

	if entry and DoesEntityExist(entity) and CanModifyEntity(entity) then
		RequestControl(entity)

		if entry.animation and Permissions.properties.ped.animation then
			if PlayAnimation(entity, entry.animation) and Database[entity] then
				Database[entity].animation = entry.animation
				Database[entity].scenario = nil
			end
			StoreAnimationInfo(entity, entry.animation)
		end

		-- Support both the new multi-prop format (entry.props, an array) and the
		-- older single-prop format (entry.prop) from before this saved more than one.
		local propsList = entry.props
		if (not propsList or #propsList == 0) and entry.prop then
			propsList = { entry.prop }
		end

		if propsList and Permissions.spawn.object and Permissions.properties.attachments then
			local x, y, z = table.unpack(GetEntityCoords(entity))

			for _, propEntry in ipairs(propsList) do
				local child = SpawnObject(propEntry.name, ResolveModelHash(propEntry.model), x, y, z, 0.0, 0.0, 0.0, false, true)

				if child then
					local a = propEntry.attachment
					AttachEntity(child, entity, a.bone, a.x, a.y, a.z, a.pitch, a.roll, a.yaw, a.useSoftPinning, a.collision, a.vertex, a.fixedRot)
				end
			end
		end
	end

	cb({})
end)

