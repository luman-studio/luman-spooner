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

-- ===================== Random outfit (shop-item) components =====================
-- Builds and applies an explicit { category = shopItemHash } config using the real
-- clothing hash database in data/rdr3/outfits.lua and ApplyShopItemToPed — this is
-- the actual per-slot mechanism RDR3's own clothing store uses, unlike the black-box
-- SetRandomOutfitVariation/SetPedOutfitPreset natives. The resulting table is plain
-- data (category -> hash), so it can be saved to KVP as-is and re-applied exactly.

-- Layered alternatives, not stackable items — a random outfit keeps at most one
-- from each group (e.g. an open coat should never also get a closed coat or vest
-- piled on top of it).
local OUTERWEAR_GROUP = { 'CoatClosed', 'Coat', 'Vest' }
local NECKWEAR_GROUP = { 'NeckTies', 'NeckWear' }

-- When one of these slots changes, RDR3 doesn't recompute layer culling on its own:
-- a neckerchief tucked under a coat collar gets suppressed and stays invisible until
-- something forces a recompute (which is why cycling its wearable state made it pop
-- in). Re-pushing every equipped garment after a neck/outerwear change forces that
-- recompute. Kept deliberately narrow (neck + outerwear only) so every OTHER
-- clothing slot behaves exactly as it did before.
local CUSTOM_RELAYER_CATEGORIES = {
	NeckWear = true, NeckTies = true,
	Coat = true, CoatClosed = true, Vest = true
}

-- Applies a previously picked/saved { category = hash } config to a ped.
function ApplyOutfitComponents(ped, components)
	if not components then
		return
	end

	-- A freshly CreatePed'd horse spawns with NO base coat/body variation set — its
	-- body mesh simply doesn't render (you get a floating saddle/bridle/mane while
	-- the flesh is invisible) until an outfit variation is seeded. World/menu horses
	-- get this from the game; a horse we rebuild from saved tack must do it itself,
	-- BEFORE layering the tack on top. (Humans go through SetRandomOutfitVariation in
	-- spawn.lua's non-outfitComponents branch instead, so only horses need it here.)
	if IsEntityHorse(ped) then
		pcall(SetRandomOutfitVariation, ped, true)
		UpdatePedVariation(ped)
	end

	for _, hash in pairs(components) do
		pcall(ApplyShopItemToPed, ped, hash)
	end

	UpdatePedVariation(ped)
end

-- Strip the runtime-only template handle before writing to KVP (a ped/entity handle
-- means nothing after a restart) and persist the rest.
function SaveMpPedToKvs(entry)
	local persisted = {
		name = entry.name,
		model = entry.model,
		components = entry.components,
		outfitComponents = entry.outfitComponents,
		weapons = entry.weapons,
		animation = entry.animation,
		scenario = entry.scenario,
		outfit = entry.outfit,
		behavior = entry.behavior,
		weaponInHand = entry.weaponInHand,
		bodyBuild = entry.bodyBuild,
		waist = entry.waist,
		eyebrowStyle = entry.eyebrowStyle,
		eyebrowColor = entry.eyebrowColor,
		hairGroup = entry.hairGroup,
		hairColor = entry.hairColor,
		beardGroup = entry.beardGroup
	}

	if entry.horse then
		persisted.horse = {
			model = entry.horse.model,
			components = entry.horse.components,
			outfitComponents = entry.horse.outfitComponents
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
		-- effort); it may fail to create, but that must not block saving. If this ped
		-- was built by "Create Random" (or a previous disk restore), we already know
		-- its exact per-slot shop-item config and can persist that directly — far more
		-- reliable than CaptureComponents, which relies on ped component-variation
		-- natives RDR3 doesn't actually have.
		local template = CreatePedTemplate(handle)
		local db = Database[handle] or {}
		local components = CaptureComponents(handle)
		local outfitComponents = db.outfitComponents

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
			outfitComponents = outfitComponents,
			weapons = db.weapons or {},
			animation = db.animation,
			scenario = db.scenario,
			outfit = db.outfit or -1,
			behavior = db.behavior,
			weaponInHand = weaponInHand,
			-- Body build/waist/eyebrows/hair/beard aren't part of outfitComponents (they're
			-- driven by EquipMetaPedOutfit / the eyebrow overlay texture / their own shop-
			-- item slots, not the generic component system) — without these the live clone
			-- template still shows them fine (same session), but a from-scratch respawn
			-- after a restart (no live template) silently loses them. See
			-- ApplyExtraHumanCustomization, which re-applies these on that respawn path.
			bodyBuild = db.bodyBuild,
			waist = db.waist,
			eyebrowStyle = db.eyebrowStyle,
			eyebrowColor = db.eyebrowColor,
			hairGroup = db.hairGroup,
			hairColor = db.hairColor,
			beardGroup = db.beardGroup
		}

		-- Save the horse it is riding, if any
		local mount = GetMount(handle)
		if mount and mount ~= 0 and DoesEntityExist(mount) then
			entry.horse = {
				template = CreatePedTemplate(mount),
				model = GetEntityModel(mount),
				components = CaptureComponents(mount),
				-- The horse's tack (saddle/mane/tail/etc, see the Horse tack editor
				-- below) lives entirely in outfitComponents, same shop-item system as
				-- human clothing — components alone (the old drawable/texture snapshot)
				-- doesn't carry it, which is why a saved horse came back bare after a
				-- restart before this was captured.
				outfitComponents = Database[mount] and Database[mount].outfitComponents
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
	-- rebuild the look. outfitComponents (per-slot shop-item hashes, built by
	-- "Create Random" or captured at save time) is the reliable path; components
	-- (old drawable/texture snapshot) is kept only as a last-resort fallback for
	-- entries saved before this existed — it's a no-op on RDR3 in practice.
	local ped = SpawnPed(props)

	if ped then
		WaitForPedReadyToRender(ped)

		if pedEntry.outfitComponents and next(pedEntry.outfitComponents) then
			ApplyOutfitComponents(ped, pedEntry.outfitComponents)
		elseif IsModelAHorse(props.model) then
			-- Horse saved without any custom tack: still needs a base coat/body
			-- variation seeded or its body mesh won't render (see ApplyOutfitComponents).
			SetRandomOutfitVariation(ped, true)
			UpdatePedVariation(ped)
		else
			ApplyComponents(ped, pedEntry.components)
			UpdatePedVariation(ped)
		end

		SetEntityVisible(ped, true)
		Database[ped].outfitComponents = pedEntry.outfitComponents

		-- Body build/waist/eyebrows/hair/beard aren't part of outfitComponents (see
		-- ApplyExtraHumanCustomization) — only relevant for a human rider, never the
		-- horse (which goes through this same function for its own tack outfitComponents).
		if not IsModelAHorse(props.model) then
			local gender = (props.model == GetHashKey('mp_female')) and 'female' or 'male'
			ApplyExtraHumanCustomization(ped, gender, pedEntry)
		end
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

		-- Face the camera, not away from it — see SpawnBareMpPed for why +180.
		local yaw2 = yaw + 180.0
		if yaw2 < 0.0 then
			yaw2 = yaw2 + 360.0
		elseif yaw2 >= 360.0 then
			yaw2 = yaw2 - 360.0
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

-- Spawns a bare mp_male/mp_female ped in view of the camera, with no outfit applied
-- yet (keepAppearance = true so SpawnPed's own outfit logic doesn't touch it) —
-- used by the "Create Custom" manual editor below.
local function SpawnBareMpPed(gender)
	local model = gender == 'female' and 'mp_female' or 'mp_male'
	local hash = ResolveModelHash(model)

	if not LoadModel(hash) then
		return nil
	end

	local x, y, z = table.unpack(GetCamCoord(Cam))
	local pitch, roll, yaw = table.unpack(GetCamRot(Cam, 2))
	local spawnPos = GetInView(x, y, z, pitch, roll, yaw)

	-- Face the camera (i.e. the player), not away from it — this ped immediately
	-- becomes AttachedEntity/selected below, which applies the usual frozen/T-pose
	-- +180 pre-offset (see spooner:onEntitySelected) on top of whatever's stored
	-- here, so start from camera yaw + 180 to land on "facing the camera" after that.
	local yaw2 = yaw + 180.0
	if yaw2 < 0.0 then
		yaw2 = yaw2 + 360.0
	elseif yaw2 >= 360.0 then
		yaw2 = yaw2 - 360.0
	end

	local ped = SpawnPed({
		model = hash,
		name = model,
		x = spawnPos.x, y = spawnPos.y, z = spawnPos.z,
		pitch = 0.0, roll = 0.0, yaw = yaw2,
		collisionDisabled = false,
		isVisible = true,
		keepAppearance = true, -- we drive the outfit ourselves, in the right order
		isInGroup = false,
		blockNonTemporaryEvents = false
	})

	if ped then
		WaitForPedReadyToRender(ped)
	end

	return ped
end

local function SelectSpawnedMpPed(ped)
	CurrentSpawn = nil
	PlaceOnGroundProperly(ped)
	TriggerEvent('spooner:onEntityUnselected', AttachedEntity)
	AttachedEntity = ped
	TriggerEvent('spooner:onEntitySelected', AttachedEntity)
end

-- ===================== Custom Ped editor (manual per-slot picker) =====================
-- Same component config format as "Create Random" (category -> shop-item hash),
-- but built by hand: every category is exposed as a cyclable option (prev/next, or
-- typing an index directly), plus "None" for anything but the required base slots,
-- so the player can assemble any exact combination themselves.
--
-- Heads/BodiesUpper/BodiesLower are NOT plain option lists like clothing — RDR3's
-- skin-tone groups use different index ranges per part (e.g. "black" is head index
-- 21 but body/legs index 6), so cycling them independently produces mismatched skin
-- tones between face and body. Skin Tone is its own row that picks the tone group;
-- Head/Body/Legs Shape pick which template *within* that group, so tone always
-- stays in sync across all three.

local CUSTOM_BODY_ROW_FIELD = {
	SkinTone = 'tone',
	HeadShape = 'headShape',
	BodyShape = 'bodyShape',
	LegsShape = 'legsShape',
	BodyBuild = 'bodyBuild',
	Waist = 'waist',
	HairStyle = 'hairGroup',
	HairColor = 'hairColor',
	BeardStyle = 'beardGroup',
	Eyebrows = 'eyebrowStyle',
	EyebrowColor = 'eyebrowColor'
}

local CUSTOM_BODY_ROW_ORDER = {
	'SkinTone', 'HeadShape', 'BodyShape', 'LegsShape', 'BodyBuild', 'Waist',
	'HairStyle', 'HairColor', 'BeardStyle', 'Eyebrows', 'EyebrowColor'
}

-- Which section each row is grouped under in the editor UI (see
-- renderCustomMpPed/createCustomPedRow in saved_entities.js, which insert a header
-- whenever a row's group differs from the previous one). Generic session.list
-- categories (Shirt, Pant, Hat, ...) aren't listed here — they default to 'Clothing'
-- in SerializeCustomCategories.
local CUSTOM_BODY_ROW_GROUP = {
	SkinTone = 'Body', HeadShape = 'Body', BodyShape = 'Body', LegsShape = 'Body',
	BodyBuild = 'Body', Waist = 'Body',
	HairStyle = 'Hair', HairColor = 'Hair', BeardStyle = 'Hair', Eyebrows = 'Hair', EyebrowColor = 'Hair'
}

-- Rows that allow "None" (0) — everything else in CUSTOM_BODY_ROW_ORDER always has
-- some value selected (there's no meaningful "no skin tone"). Hair and Beard can
-- both legitimately be bald/clean-shaven; Hair Color has nothing to be "none" of.
local CUSTOM_BODY_ROW_OPTIONAL = {
	HairStyle = true, BeardStyle = true
}

-- Real body-build/weight component hashes, equipped via EquipMetaPedOutfit (the
-- "meta ped outfit" native, not the plain shop-item slot system) — same mechanism
-- and same hashes RDR3's own MP character creator uses. EquipMetaPedOutfitExtra
-- (raw preset index, tried first) turned out to only ever affect the head/face,
-- never the actual body — these two component sets are what really reshapes it:
-- Build swaps the torso/limb mesh (athletic/heavy/etc.), Waist layers a separate
-- belly/girth component that still shows through worn clothing. Not known to be
-- gender-specific (no separate list exists for mp_female either upstream), so the
-- same hashes are used for both.
local CUSTOM_BODY_BUILD_HASHES = {
	61606861, -1241887289, -369348190, 32611963, -20262001, -369348190
}

local CUSTOM_WAIST_HASHES = {
	-2045421226, -1745814259, -325933489, -1065791927, -844699484, -1273449080,
	927185840, 149872391, 399015098, -644349862, 1745919061, 1004225511,
	1278600348, 502499352, -2093198664, -1837436619, 1736416063, 2040610690,
	-1173634986, -867801909, 1960266524
}

-- Hair and Beard used to live here (flattened style+color option lists) but moved
-- to the dedicated HairStyle/BeardStyle/HairColor rows above — see the "Hair /
-- Beard / Hair Color" section below for why.
local CUSTOM_CATEGORY_ORDER = {
	'Eyes', 'Teeth',
	'Shirt', 'Pant', 'Skirt', 'Dress', 'Boots', 'Belt', 'Suspender', 'Vest',
	'Coat', 'CoatClosed', 'Poncho', 'Cloak', 'Hat', 'Glove', 'Gauntlets',
	'EyeWear', 'Mask', 'NeckTies', 'NeckWear', 'Bracelet', 'RingLh', 'RingRh',
	'Buckle', 'Spurs', 'Chap', 'Spats', 'Armor', 'Badge', 'Satchels', 'Holster',
	'Gunbelt', 'gunbelt_accs', 'Accessories'
}

-- Categories where the *equipped item itself* can have more than one worn position
-- (RDR3 "wearable states") — e.g. a bandana/neckerchief pulled down vs up over the
-- face. Only NeckWear gets the extra toggle button; Hat/Mask/NeckTies were tried
-- too but didn't produce a reliably useful look, so they were dropped.
local CUSTOM_WEARABLE_STATE_CATEGORIES = {
	NeckWear = true
}

-- Found by testing in-game: most wearable-state indices for a given item are either
-- indistinguishable or broken-looking — these are the only ones actually worth
-- cycling through via the toggle button. 0 is NeckWear's default/initial state, so
-- it can be toggled back down, not just up.
local CUSTOM_WEARABLE_STATE_ALLOWED = {
	NeckWear = { 0, 5, 6, 7 }
}

-- Categories that always have something equipped (no "None" option).
local CUSTOM_REQUIRED_CATEGORIES = {
	Eyes = true, Teeth = true
}

-- Optional categories that still start with something equipped (rather than "None")
-- so the ped isn't naked the moment the editor opens.
local CUSTOM_DEFAULT_DRESSED = {
	Shirt = true, Pant = true, Boots = true
}

local function GetBodyRowCount(session, row)
	local tone = PedBodyData and PedBodyData[session.tone]

	if row == 'SkinTone' then
		return #(PedBodyData or {})
	elseif row == 'HeadShape' then
		return tone and #tone.heads or 0
	elseif row == 'BodyShape' then
		return tone and #tone.bodies or 0
	elseif row == 'LegsShape' then
		return tone and #tone.legs or 0
	elseif row == 'BodyBuild' then
		return #CUSTOM_BODY_BUILD_HASHES
	elseif row == 'Waist' then
		return #CUSTOM_WAIST_HASHES
	elseif row == 'Eyebrows' then
		return PedEyebrowData and #PedEyebrowData or 0
	elseif row == 'HairStyle' then
		local groups = PedHairData and PedHairData[session.gender]
		return groups and #groups or 0
	elseif row == 'HairColor' then
		return PedHairColorNames and #PedHairColorNames or 0
	elseif row == 'BeardStyle' then
		-- Male only — no female beard data exists. Returning 0 here makes
		-- SerializeCustomCategories skip the row entirely for a female session.
		return (session.gender == 'male' and PedBeardData) and #PedBeardData or 0
	elseif row == 'EyebrowColor' then
		return PedEyebrowColorPalette and #PedEyebrowColorPalette or 0
	end

	return 0
end

-- Body build (fat/thin/muscular) and waist/belly girth — equipped via
-- EquipMetaPedOutfit (see its comment in core.lua for why, not
-- EquipMetaPedOutfitExtra), so applied separately from ApplyBodyAppearance.
local function ApplyBodyBuild(session)
	local hash = session.bodyBuild and session.bodyBuild >= 1 and CUSTOM_BODY_BUILD_HASHES[session.bodyBuild]

	if hash then
		pcall(EquipMetaPedOutfit, session.ped, hash)
	end
end

local function ApplyWaist(session)
	local hash = session.waist and session.waist >= 1 and CUSTOM_WAIST_HASHES[session.waist]

	if hash then
		pcall(EquipMetaPedOutfit, session.ped, hash)
	end
end

-- Re-applies Heads/BodiesUpper/BodiesLower from the session's current tone + shape
-- indices. Called any time tone OR any of the three shapes changes, since a tone
-- change has to cascade to all three to keep them matching.
local function ApplyBodyAppearance(session)
	local tone = PedBodyData and PedBodyData[session.tone]

	if not tone then
		return
	end

	local genderLetter = session.gender == 'female' and 'F' or 'M'

	local headTemplate = tone.heads[session.headShape]
	local bodyTemplate = tone.bodies[session.bodyShape]
	local legsTemplate = tone.legs[session.legsShape]

	if headTemplate then
		pcall(ApplyShopItemToPed, session.ped, GetHashKey(string.format(headTemplate, genderLetter)))
	end

	if bodyTemplate then
		pcall(ApplyShopItemToPed, session.ped, GetHashKey(string.format(bodyTemplate, genderLetter)))
	end

	if legsTemplate then
		pcall(ApplyShopItemToPed, session.ped, GetHashKey(string.format(legsTemplate, genderLetter)))
	end
end

-- Eyebrows aren't a shop-item component (see PedEyebrowData in data/rdr3/bodies.lua)
-- — RDR3 draws them as a "head overlay" composited into a standalone texture, which
-- is then handed to the ped's "heads" component. That composite has to be rebuilt
-- from scratch every time (there's no "just add one layer to what's already there"),
-- and it has to be rebuilt any time the base head texture changes too — which is
-- exactly what happens whenever ApplyBodyAppearance re-equips Heads for a tone/shape
-- change, so every caller of ApplyBodyAppearance calls this right after.
local function ApplyEyebrows(session)
	if session.eyebrowTextureId then
		pcall(ClearPedHeadTexture, session.eyebrowTextureId)
		pcall(ReleasePedHeadTexture, session.eyebrowTextureId)
		session.eyebrowTextureId = nil
	end

	local tone = PedBodyData and PedBodyData[session.tone]
	local base = PedHeadBaseTexture and PedHeadBaseTexture[session.gender]

	if not tone or not tone.albedo or not base then
		return
	end

	local genderLetter = session.gender == 'female' and 'F' or 'M'

	local okReq, textureId = pcall(RequestPedHeadTexture,
		GetHashKey(string.format(tone.albedo, genderLetter)),
		GetHashKey(base.normal),
		GetHashKey(base.material))

	if not okReq or not textureId or textureId < 0 then
		return
	end

	local style = session.eyebrowStyle and session.eyebrowStyle >= 1 and PedEyebrowData[session.eyebrowStyle]

	if style then
		-- normalHash/materialHash are always 1/0 here, not the style's own normal/ma
		-- fields — matches VORPCORE's own overlay calls exactly; those two fields go
		-- unused there too. The palette+tint below is what actually colors the brows.
		local okLayer, layerId = pcall(AddPedHeadTextureLayer, textureId, style.id, 1, 0, 0, 1.0, 0)

		if okLayer and layerId and layerId >= 0 then
			-- The overlay's own LUT selection — VORPCORE always uses METAPED_TINT_MAKEUP
			-- here for eyebrows specifically, regardless of which color is picked; only
			-- the tint primary color below actually changes with the Eyebrow Color row.
			local colorName = PedEyebrowColorPalette and session.eyebrowColor and PedEyebrowColorPalette[session.eyebrowColor]
			local tint = GetHashKey(colorName or 'METAPED_TINT_MAKEUP')

			pcall(SetPedHeadTextureLayerPalette, textureId, layerId, GetHashKey('METAPED_TINT_MAKEUP'))
			pcall(SetPedHeadTextureLayerTint, textureId, layerId, tint, 0, 0)
			pcall(SetPedHeadTextureLayerSheetGridIndex, textureId, layerId, 1)
			pcall(SetPedHeadTextureLayerAlpha, textureId, layerId, 1.0)
		end
	end

	local waited = 0
	while not IsPedHeadTextureValid(textureId) and waited < 200 do
		Wait(0)
		waited = waited + 1
	end

	pcall(UpdatePedHeadTexture, textureId)
	pcall(ApplyPedHeadTexture, session.ped, GetHashKey('heads'), textureId)

	session.eyebrowTextureId = textureId
end

-- ===================== Hair / Beard / Hair Color =====================
-- Hair and Beard are style-group -> color-variant shop items (PedHairData/
-- PedBeardData in data/rdr3/bodies.lua), not a flat option list like the generic
-- clothing categories below — Style picks the group (haircut/beard shape), and
-- Color is ONE shared control that recolors Hair, Beard, and (as a best-effort
-- tint) Eyebrows together, instead of hunting down the same shade three times.
-- That shared-color coupling is exactly why these live here as dedicated rows
-- instead of in session.list (the generic system re-applies one fixed hash per
-- row, with no notion of "recompute using some other row's current state").

local function GetHairGroups(session)
	return PedHairData and PedHairData[session.gender]
end

local function GetBeardGroups(session)
	-- Male only — no female beard data exists.
	return session.gender == 'male' and PedBeardData or nil
end

-- Finds the variant in `group` whose hashname matches this exact style group +
-- color name (style group numbers are 1-based and zero-padded to 3 digits in the
-- hashname, matching the group's position in the data table). Exact match, not a
-- suffix search — "BLONDE" is itself a suffix of "DARK_BLONDE"/"LIGHT_BLONDE", so
-- anything looser would pick the wrong variant.
local function FindColorVariant(group, genderLetter, itemType, groupIndex, colorName)
	if not group then
		return nil
	end

	local expected = ('CLOTHING_ITEM_%s_%s_%03d_%s'):format(genderLetter, itemType, groupIndex, colorName)

	for _, variant in ipairs(group) do
		if variant.hashname == expected then
			return variant
		end
	end

	return nil
end

local function ApplyHair(session)
	if session.hairAppliedHash then
		pcall(RemoveShopItemFromPed, session.ped, session.hairAppliedHash)
		session.hairAppliedHash = nil
	end

	local groups = GetHairGroups(session)
	local group = groups and session.hairGroup and session.hairGroup >= 1 and groups[session.hairGroup]

	if not group then
		return
	end

	local genderLetter = session.gender == 'female' and 'F' or 'M'
	local colorName = PedHairColorNames and session.hairColor and PedHairColorNames[session.hairColor]
	local variant = (colorName and FindColorVariant(group, genderLetter, 'HAIR', session.hairGroup, colorName)) or group[1]

	if variant then
		pcall(ApplyShopItemToPed, session.ped, variant.hash)
		session.hairAppliedHash = variant.hash
	end
end

local function ApplyBeard(session)
	if session.beardAppliedHash then
		pcall(RemoveShopItemFromPed, session.ped, session.beardAppliedHash)
		session.beardAppliedHash = nil
	end

	local groups = GetBeardGroups(session)
	local group = groups and session.beardGroup and session.beardGroup >= 1 and groups[session.beardGroup]

	if not group then
		return
	end

	local colorName = PedHairColorNames and session.hairColor and PedHairColorNames[session.hairColor]
	local variant = (colorName and FindColorVariant(group, 'M', 'BEARD', session.beardGroup, colorName)) or group[1]

	if variant then
		pcall(ApplyShopItemToPed, session.ped, variant.hash)
		session.beardAppliedHash = variant.hash
	end
end

-- The shared Hair/Beard color control — re-applies whatever styles are currently
-- selected, picking the new color's variant within each. Eyebrows have their own
-- separate Eyebrow Color row (see ApplyEyebrows) — RDR3's eyebrow overlay tint
-- isn't drawn from the same 17 named Hair/Beard color variants, so there's no
-- reliable way to keep it in sync with this one automatically.
local function ApplyHairColor(session)
	ApplyHair(session)
	ApplyBeard(session)
end

local function FlattenCustomCategoryOptions(category, gender, genderLetter)
	local options = {}

	if category == 'Eyes' then
		for _, template in ipairs(PedEyeData or {}) do
			table.insert(options, GetHashKey(string.format(template, genderLetter)))
		end
	elseif category == 'Teeth' then
		for _, template in ipairs(PedTeethData or {}) do
			table.insert(options, GetHashKey(string.format(template, genderLetter)))
		end
	else
		local groups = PedOutfitData and PedOutfitData[gender] and PedOutfitData[gender][category]

		for _, group in ipairs(groups or {}) do
			for _, variant in ipairs(group) do
				table.insert(options, variant.hash)
			end
		end
	end

	return options
end

-- Builds the ordered category list for a fresh editor session: each entry is
-- { category, options = {hash, ...}, index (0 = None), required, appliedHash }.
-- `list` preserves display order; `byName` points at the same entry tables for
-- O(1) lookup when a cycle/set-index request comes in from the UI.
local function BuildCustomCategories(gender)
	local genderLetter = gender == 'female' and 'F' or 'M'
	local seen = {}
	local order = {}

	for _, category in ipairs(CUSTOM_CATEGORY_ORDER) do
		seen[category] = true
		table.insert(order, category)
	end

	if PedOutfitData and PedOutfitData[gender] then
		local extra = {}

		for category in pairs(PedOutfitData[gender]) do
			if not seen[category] then
				table.insert(extra, category)
			end
		end

		table.sort(extra)

		for _, category in ipairs(extra) do
			table.insert(order, category)
		end
	end

	local list = {}
	local byName = {}

	for _, category in ipairs(order) do
		local options = FlattenCustomCategoryOptions(category, gender, genderLetter)

		if #options > 0 then
			local required = CUSTOM_REQUIRED_CATEGORIES[category] or false
			local index = (required or CUSTOM_DEFAULT_DRESSED[category]) and math.random(#options) or 0

			local entry = { category = category, options = options, index = index, required = required }

			table.insert(list, entry)
			byName[category] = entry
		end
	end

	return list, byName
end

-- (Re)applies every entry's current pick to the session's ped. Applying a new shop
-- item to a category replaces whatever was in that slot already — RemoveShopItemFromPed
-- is only needed to actually clear a slot down to "None". This matters here (unlike
-- a single manual cycle) because a re-randomize can flip an already-equipped slot
-- (e.g. a coat) back to "None" — without removing it, the old item stays stuck on
-- the ped even though the session no longer thinks it's equipped.
local function ApplyCustomPedComponents(session)
	for _, entry in ipairs(session.list) do
		if entry.index > 0 then
			local hash = entry.options[entry.index]
			pcall(ApplyShopItemToPed, session.ped, hash)
			entry.appliedHash = hash
			entry.wearableStateIndex = 0
		else
			if entry.appliedHash then
				pcall(RemoveShopItemFromPed, session.ped, entry.appliedHash)
			end
			entry.appliedHash = nil
			entry.wearableStateIndex = nil
		end
	end

	UpdatePedVariation(session.ped)
end

local function GetCustomPedComponents(session)
	local components = {}

	local tone = PedBodyData and PedBodyData[session.tone]

	if tone then
		local genderLetter = session.gender == 'female' and 'F' or 'M'
		local headTemplate = tone.heads[session.headShape]
		local bodyTemplate = tone.bodies[session.bodyShape]
		local legsTemplate = tone.legs[session.legsShape]

		if headTemplate then
			components.Heads = GetHashKey(string.format(headTemplate, genderLetter))
		end

		if bodyTemplate then
			components.BodiesUpper = GetHashKey(string.format(bodyTemplate, genderLetter))
		end

		if legsTemplate then
			components.BodiesLower = GetHashKey(string.format(legsTemplate, genderLetter))
		end
	end

	for _, entry in ipairs(session.list) do
		if entry.appliedHash then
			components[entry.category] = entry.appliedHash
		end
	end

	return components
end

-- ===================== Horse tack editor =====================
-- Horses are ped type 1 like humans but wear tack (saddles, saddlebags, manes,
-- tails, etc.) instead of clothing/body components. The tack items are still
-- ordinary metaped shop items (see data/rdr3/tack.lua / HorseTack), so the same
-- ApplyShopItemToPed/RemoveShopItemFromPed/UpdatePedVariation primitives drive
-- them. A horse session reuses the exact same #mp-custom-menu UI and cycle/set
-- callbacks as the human editor; the shared functions branch on session.isHorse.

-- key -> its HorseTack category table, built once for O(1) lookup.
local HorseTackByKey = {}

for _, cat in ipairs(HorseTack or {}) do
	HorseTackByKey[cat.key] = cat
end

-- Which flat tack categories the "Randomize All" button touches — just the main
-- pieces. Everything else (stirrups, horns, lanterns, bedrolls, accessories,
-- horseshoes) is set to None so a randomized horse gets the essentials without
-- being buried in every accessory at once.
local HORSE_RANDOM_MAIN = {
	saddles = true, saddlebags = true, bridles = true, blankets = true
}

-- Mane/tail are style groups with colour variants (see HorseManes/HorseTails in
-- data/rdr3/tack.lua), so each is exposed as TWO editor rows — a Style row and a
-- Color row — exactly like human Hair Style + Hair Color. These map a special row
-- key to its data table + which session slot it drives.
local HorseHairRows = {
	ManeStyle = { data = HorseManes, slot = 'mane', kind = 'style', label = 'Mane Style' },
	ManeColor = { data = HorseManes, slot = 'mane', kind = 'color', label = 'Mane Color' },
	TailStyle = { data = HorseTails, slot = 'tail', kind = 'style', label = 'Tail Style' },
	TailColor = { data = HorseTails, slot = 'tail', kind = 'color', label = 'Tail Color' }
}

-- Rebuilds Database[horse].outfitComponents from the session's currently-applied
-- tack, so a saved MP ped's horse (entry.horse.outfitComponents) — and anything
-- else that re-applies that table via ApplyOutfitComponents — round-trips the tack.
-- Mane/tail land under fixed keys ('manes'/'tails') so they hydrate back cleanly.
local function StoreHorseTack(session)
	local components = {}

	for key, slot in pairs(session.tack) do
		if slot.appliedHash then
			components[key] = slot.appliedHash
		end
	end

	if session.mane.appliedHash then components.manes = session.mane.appliedHash end
	if session.tail.appliedHash then components.tails = session.tail.appliedHash end

	if Database[session.ped] then
		Database[session.ped].outfitComponents = components
	end
end

-- Applies the current style+colour of a mane/tail slot: removes the previously
-- applied variant hash, then applies the colour variant of the selected style
-- (clamped to what that style actually has). style 0 = None (bare).
local function ApplyHorseHair(session, slotName, data)
	local slot = session[slotName]

	if slot.appliedHash then
		pcall(RemoveShopItemFromPed, session.ped, slot.appliedHash)
		slot.appliedHash = nil
	end

	if slot.style > 0 and data and data.styles[slot.style] then
		local colors = data.styles[slot.style].colors
		slot.color = math.max(1, math.min(slot.color, #colors))
		local hash = colors[slot.color]
		pcall(ApplyShopItemToPed, session.ped, hash)
		slot.appliedHash = hash
	end

	UpdatePedVariation(session.ped)
	StoreHorseTack(session)
end

-- Reverse-maps a known mane/tail hash back to (style, colour) so the editor opens
-- reflecting what's on the horse.
local function HydrateHorseHair(slot, data, knownHash)
	if not (knownHash and data) then
		return
	end

	for si, style in ipairs(data.styles) do
		for ci, hash in ipairs(style.colors) do
			if hash == knownHash then
				slot.style = si
				slot.color = ci
				slot.appliedHash = knownHash
				return
			end
		end
	end
end

-- Reverse-maps any already-applied tack hashes (from Database[horse].outfitComponents,
-- populated by a prior edit or a restored saved horse) back to row indices so the
-- editor opens reflecting what's on the horse instead of all-None.
local function StartHorseTackSession(horse)
	-- Clean up a leftover temp "Create Custom" human ped, same as StartCustomizeSession,
	-- so switching from the human editor straight to a horse doesn't orphan it.
	if CustomPedSession and CustomPedSession.isTemp and CustomPedSession.ped and CustomPedSession.ped ~= horse and DoesEntityExist(CustomPedSession.ped) then
		RemoveEntity(CustomPedSession.ped)
	end

	local session = {
		ped = horse,
		isHorse = true,
		isTemp = false,
		tack = {},
		mane = { style = 0, color = 1, appliedHash = nil },
		tail = { style = 0, color = 1, appliedHash = nil }
	}

	local known = Database[horse] and Database[horse].outfitComponents

	for _, cat in ipairs(HorseTack or {}) do
		local slot = { index = 0, appliedHash = nil }
		local knownHash = known and known[cat.key]

		if knownHash then
			for i, item in ipairs(cat.items) do
				if item.hash == knownHash then
					slot.index = i
					slot.appliedHash = knownHash
					break
				end
			end
		end

		session.tack[cat.key] = slot
	end

	HydrateHorseHair(session.mane, HorseManes, known and known.manes)
	HydrateHorseHair(session.tail, HorseTails, known and known.tails)

	CustomPedSession = session

	Database[horse] = Database[horse] or {}
	Database[horse].outfitComponents = Database[horse].outfitComponents or {}

	return session
end

local function SerializeHorseTack(session)
	local rows = {}

	for _, cat in ipairs(HorseTack or {}) do
		local slot = session.tack[cat.key]

		table.insert(rows, {
			category = cat.key,
			label = cat.label,
			index = slot and slot.index or 0,
			count = #cat.items,
			required = false,
			group = 'Tack'
		})
	end

	-- Mane & Tail: Style row always shown; Color row only when a style is selected
	-- (there's nothing to colour on a bare mane, and the colour count is per-style).
	local function addHair(styleKey, colorKey, slot, data)
		table.insert(rows, {
			category = styleKey,
			label = HorseHairRows[styleKey].label,
			index = slot.style,
			count = data and #data.styles or 0,
			required = false,
			group = 'Mane & Tail'
		})

		if slot.style > 0 and data and data.styles[slot.style] then
			table.insert(rows, {
				category = colorKey,
				label = HorseHairRows[colorKey].label,
				index = slot.color,
				count = #data.styles[slot.style].colors,
				required = true,
				group = 'Mane & Tail'
			})
		end
	end

	addHair('ManeStyle', 'ManeColor', session.mane, HorseManes)
	addHair('TailStyle', 'TailColor', session.tail, HorseTails)

	return rows
end

-- Applies/removes the tack item at newIndex for one category (0 = None). Mirrors the
-- generic-clothing branch of SetCustomRowIndex: remove the previously-applied hash
-- first (tack slots don't auto-replace), then apply the new one. Mane/tail Style and
-- Color rows are handled via ApplyHorseHair instead.
local function SetHorseRowIndex(session, key, newIndex)
	local hair = HorseHairRows[key]

	if hair then
		local slot = session[hair.slot]

		if hair.kind == 'style' then
			slot.style = newIndex
		else
			slot.color = newIndex
		end

		ApplyHorseHair(session, hair.slot, hair.data)

		if hair.kind == 'style' then
			return newIndex, hair.data and #hair.data.styles or 0
		else
			local style = hair.data and hair.data.styles[slot.style]
			return slot.color, style and #style.colors or 0
		end
	end

	local cat = HorseTackByKey[key]
	local slot = session.tack[key]

	if not cat or not slot then
		return nil
	end

	if slot.appliedHash then
		pcall(RemoveShopItemFromPed, session.ped, slot.appliedHash)
		slot.appliedHash = nil
	end

	slot.index = newIndex

	if newIndex > 0 then
		local hash = cat.items[newIndex].hash
		pcall(ApplyShopItemToPed, session.ped, hash)
		slot.appliedHash = hash
	end

	UpdatePedVariation(session.ped)
	StoreHorseTack(session)

	return newIndex, #cat.items
end

local function GetHorseRowState(session, key)
	local hair = HorseHairRows[key]

	if hair then
		local slot = session[hair.slot]

		if hair.kind == 'style' then
			return slot.style, hair.data and #hair.data.styles or 0, false
		end

		local style = hair.data and hair.data.styles[slot.style]
		return slot.color, style and #style.colors or 0, true
	end

	local cat = HorseTackByKey[key]
	local slot = session.tack[key]

	if not cat or not slot then
		return nil
	end

	return slot.index, #cat.items, false
end

local function RandomizeHorseTack(session)
	-- Only the main pieces (see HORSE_RANDOM_MAIN) get a random item; the rest are
	-- cleared to None. Saddle is always given one (a random horse without a saddle
	-- reads as a mistake); the other mains include a None chance.
	for _, cat in ipairs(HorseTack or {}) do
		if cat.key == 'saddles' then
			SetHorseRowIndex(session, cat.key, math.random(1, #cat.items))
		elseif HORSE_RANDOM_MAIN[cat.key] then
			SetHorseRowIndex(session, cat.key, math.random(0, #cat.items))
		else
			SetHorseRowIndex(session, cat.key, 0)
		end
	end

	-- Mane and tail: always give a style, with a random colour within it.
	for _, pair in ipairs({ { 'ManeStyle', 'mane', HorseManes }, { 'TailStyle', 'tail', HorseTails } }) do
		local data = pair[3]

		if data and #data.styles > 0 then
			local styleIdx = math.random(1, #data.styles)
			session[pair[2]].color = math.random(1, #data.styles[styleIdx].colors)
			SetHorseRowIndex(session, pair[1], styleIdx)
		end
	end
end

local function SerializeCustomCategories(session)
	if session.isHorse then
		return SerializeHorseTack(session)
	end

	local rows = {}

	for _, row in ipairs(CUSTOM_BODY_ROW_ORDER) do
		local count = GetBodyRowCount(session, row)

		-- 0 only happens for BeardStyle on a female session (no data exists) — skip
		-- the row entirely rather than showing a useless empty 0/0 control.
		if count > 0 then
			table.insert(rows, {
				category = row,
				index = session[CUSTOM_BODY_ROW_FIELD[row]],
				count = count,
				required = not CUSTOM_BODY_ROW_OPTIONAL[row],
				group = CUSTOM_BODY_ROW_GROUP[row]
			})
		end
	end

	for _, entry in ipairs(session.list) do
		table.insert(rows, {
			category = entry.category,
			index = entry.index,
			count = #entry.options,
			required = entry.required,
			hasState = CUSTOM_WEARABLE_STATE_CATEGORIES[entry.category] or false,
			group = 'Clothing'
		})
	end

	return rows
end

-- Cycles the currently-equipped item in `category` to its next wearable state, but
-- only among the curated CUSTOM_WEARABLE_STATE_ALLOWED indices for that category
-- (not every state the item has — most of those are indistinguishable or broken).
-- No-ops if the item doesn't actually have that many states, or the slot is empty.
local function CycleWearableState(session, category)
	local entry = session.byName[category]
	local allowed = CUSTOM_WEARABLE_STATE_ALLOWED[category]

	if not entry or not entry.appliedHash or not allowed or #allowed == 0 then
		return 0, 0
	end

	local isMpFemale = session.gender == 'female'
	local okCount, count = pcall(GetShopItemNumWearableStates, entry.appliedHash, isMpFemale)

	if not okCount or not count or count <= 1 then
		return 0, (okCount and count) or 0
	end

	-- Clamp (rather than drop) indices past what this specific item actually has —
	-- different items in the same category can have different state counts, and
	-- silently excluding an out-of-range index could leave the whole allowed list
	-- empty, making the button do nothing at all for that item.
	local validAllowed = {}
	local seen = {}

	for _, idx in ipairs(allowed) do
		local clamped = math.min(idx, count - 1)

		if not seen[clamped] then
			seen[clamped] = true
			table.insert(validAllowed, clamped)
		end
	end

	if #validAllowed == 0 then
		return 0, count
	end

	local currentPos = nil

	for i, idx in ipairs(validAllowed) do
		if idx == entry.wearableStateIndex then
			currentPos = i
			break
		end
	end

	local nextPos = currentPos and (currentPos % #validAllowed) + 1 or 1
	local nextIndex = validAllowed[nextPos]

	entry.wearableStateIndex = nextIndex

	local okState, stateHash = pcall(GetShopItemWearableStateByIndex, entry.appliedHash, nextIndex, isMpFemale)

	if okState and stateHash then
		pcall(UpdateShopItemWearableState, session.ped, entry.appliedHash, stateHash, true)
		UpdatePedVariation(session.ped)
	end

	return entry.wearableStateIndex, count
end

RegisterNUICallback('customPedToggleWearableState', function(data, cb)
	local session = CustomPedSession

	-- Horse tack rows have no wearable-state toggle button (session.byName is nil for
	-- horse sessions), so guard against it ever being called on one.
	if session and not session.isHorse and session.ped and DoesEntityExist(session.ped) then
		local stateIndex, stateCount = CycleWearableState(session, data.category)
		cb(json.encode({ stateIndex = stateIndex, stateCount = stateCount }))
		return
	end

	cb(json.encode({}))
end)

-- Picks a random skin tone + head/body/legs shape within it (all in sync, see
-- ApplyBodyAppearance).
local function RandomizeCustomBodyAppearance(session)
	if not (PedBodyData and #PedBodyData > 0) then
		return
	end

	session.tone = math.random(#PedBodyData)

	local tone = PedBodyData[session.tone]

	session.headShape = math.random(#tone.heads)
	session.bodyShape = math.random(#tone.bodies)
	session.legsShape = math.random(#tone.legs)
	session.bodyBuild = math.random(#CUSTOM_BODY_BUILD_HASHES)
	session.waist = math.random(#CUSTOM_WAIST_HASHES)

	-- Never randomize down to "None" (0) — that's the exact "face with no eyebrows"
	-- problem this row exists to fix, so a randomize pass should always leave some
	-- style equipped, just not always the same one.
	if PedEyebrowData and #PedEyebrowData > 0 then
		session.eyebrowStyle = math.random(#PedEyebrowData)
	end

	if PedEyebrowColorPalette and #PedEyebrowColorPalette > 0 then
		session.eyebrowColor = math.random(#PedEyebrowColorPalette)
	end

	if PedHairColorNames and #PedHairColorNames > 0 then
		session.hairColor = math.random(#PedHairColorNames)
	end

	-- Hair, unlike Eyebrows/Beard, is always given a style (a bald randomized ped
	-- looks like a mistake, not a choice).
	local hairGroups = GetHairGroups(session)
	if hairGroups and #hairGroups > 0 then
		session.hairGroup = math.random(#hairGroups)
	end

	-- Beard stays a chance roll, same as "Create Random" (Config.RandomBeardChance) —
	-- most male peds shouldn't come out with a beard by default.
	local beardGroups = GetBeardGroups(session)
	if beardGroups and #beardGroups > 0 and math.random() <= (Config.RandomBeardChance or 0) then
		session.beardGroup = math.random(#beardGroups)
	else
		session.beardGroup = 0
	end
end

-- Randomizes session.list the same way "Create Random" does (Config.RandomOutfitChance
-- + Config.RandomBeardChance + the Coat/CoatClosed/Vest and NeckTies/NeckWear
-- exclusivity groups) — most categories end up "None", not every accessory equipped
-- at once.
local function RandomizeCustomList(session)
	local byName = session.byName

	local function pick(category, forceOn)
		local entry = byName[category]

		if not entry then
			return
		end

		if forceOn then
			entry.index = math.random(#entry.options)
			return
		end

		local chance = Config.RandomOutfitChance[category]
		entry.index = (chance and math.random() <= chance) and math.random(#entry.options) or 0
	end

	for _, entry in ipairs(session.list) do
		entry.index = 0
	end

	pick('Pant', true)
	pick('Skirt', true)
	pick('Shirt', true)
	pick('Boots', true)
	pick('Eyes', true)
	pick('Teeth', true)

	-- Hair/Beard are randomized separately now — see RandomizeCustomBodyAppearance.

	for category in pairs(Config.RandomOutfitChance) do
		pick(category, false)
	end

	for _, group in ipairs({ OUTERWEAR_GROUP, NECKWEAR_GROUP }) do
		local kept = nil

		for _, category in ipairs(group) do
			local entry = byName[category]

			if entry and entry.index > 0 then
				if kept then
					entry.index = 0
				else
					kept = category
				end
			end
		end
	end
end

-- Spawns a brand-new temp ped to edit (MP Peds -> Create Custom). Only ever deletes
-- a *previous temp* ped on re-entry — never touches a ped handed in via
-- StartCustomizeSession (Ped Options -> Customize), which is a real, already-placed
-- entity the player owns and must not get deleted out from under them.
local function StartCustomPedSession(gender)
	if CustomPedSession and CustomPedSession.isTemp and CustomPedSession.ped and DoesEntityExist(CustomPedSession.ped) then
		RemoveEntity(CustomPedSession.ped)
	end

	CustomPedSession = nil

	local ped = SpawnBareMpPed(gender)

	if not ped then
		return nil
	end

	local list, byName = BuildCustomCategories(gender)

	CustomPedSession = {
		ped = ped, gender = gender, list = list, byName = byName,
		tone = 1, headShape = 1, bodyShape = 1, legsShape = 1, bodyBuild = 1, waist = 1,
		eyebrowStyle = 1, eyebrowColor = 1,
		hairGroup = 1, hairColor = 1, beardGroup = 0,
		isTemp = true
	}

	RandomizeCustomBodyAppearance(CustomPedSession)
	ApplyBodyAppearance(CustomPedSession)
	ApplyHair(CustomPedSession)
	ApplyBeard(CustomPedSession)
	ApplyEyebrows(CustomPedSession)
	ApplyBodyBuild(CustomPedSession)
	ApplyWaist(CustomPedSession)
	ApplyCustomPedComponents(CustomPedSession)
	SetEntityVisible(ped, true)

	Database[ped].outfitComponents = GetCustomPedComponents(CustomPedSession)
	Database[ped].bodyBuild = CustomPedSession.bodyBuild
	Database[ped].eyebrowStyle = CustomPedSession.eyebrowStyle
	Database[ped].eyebrowColor = CustomPedSession.eyebrowColor
	Database[ped].waist = CustomPedSession.waist
	Database[ped].hairGroup = CustomPedSession.hairGroup
	Database[ped].hairColor = CustomPedSession.hairColor
	Database[ped].beardGroup = CustomPedSession.beardGroup

	SelectSpawnedMpPed(ped)

	return CustomPedSession
end

-- If we already know exactly what's applied to this ped (Database[ped].outfitComponents,
-- tracked ever since it was built by Create Random/Create Custom, or restored from a
-- saved MP ped), reverse-map those known hashes back to row indices so the editor
-- reflects reality instead of starting blank. Peds we have no record for (an
-- ordinary NPC, the player, anything not created through this system) simply don't
-- match anything and every row falls back to its blank starting position.
local function HydrateCustomSessionFromComponents(session, components)
	local genderLetter = session.gender == 'female' and 'F' or 'M'

	if PedBodyData and (components.Heads or components.BodiesUpper or components.BodiesLower) then
		for toneIndex, tone in ipairs(PedBodyData) do
			local matchedTone = false

			if components.Heads then
				for shapeIndex, template in ipairs(tone.heads) do
					if GetHashKey(string.format(template, genderLetter)) == components.Heads then
						session.tone = toneIndex
						session.headShape = shapeIndex
						matchedTone = true
						break
					end
				end
			end

			if matchedTone then
				if components.BodiesUpper then
					for shapeIndex, template in ipairs(tone.bodies) do
						if GetHashKey(string.format(template, genderLetter)) == components.BodiesUpper then
							session.bodyShape = shapeIndex
							break
						end
					end
				end

				if components.BodiesLower then
					for shapeIndex, template in ipairs(tone.legs) do
						if GetHashKey(string.format(template, genderLetter)) == components.BodiesLower then
							session.legsShape = shapeIndex
							break
						end
					end
				end

				break
			end
		end
	end

	for _, entry in ipairs(session.list) do
		local hash = components[entry.category]

		if hash then
			for optIndex, optHash in ipairs(entry.options) do
				if optHash == hash then
					entry.index = optIndex
					entry.appliedHash = hash
					entry.wearableStateIndex = 0
					break
				end
			end
		end
	end
end

-- Re-applies the body-build/waist/eyebrow/hair/beard extras a saved MP ped's rider
-- carries — none of these are part of outfitComponents (they're driven by
-- EquipMetaPedOutfit / the eyebrow overlay texture / their own shop-item slots, not
-- the generic per-category component system ApplyOutfitComponents covers), so a
-- from-scratch respawn (no live clone template — e.g. after a resource/server
-- restart) needs this extra pass or the ped comes back missing all of it, even
-- though its base clothing/skin-tone shape (real outfitComponents) is fine.
--
-- Global (not local): called from SpawnMpPedFromEntry, which is defined earlier in
-- this file than the Apply*/Hydrate helpers this uses — Lua only resolves GLOBAL
-- names at call time, so the earlier definition can still reach this by name as
-- long as the whole file (and this function) has finished loading before it's
-- actually invoked, which is always true (it only runs from a NUI callback).
function ApplyExtraHumanCustomization(ped, gender, pedEntry)
	local session = {
		ped = ped,
		gender = gender,
		tone = 1, headShape = 1, bodyShape = 1, legsShape = 1,
		bodyBuild = pedEntry.bodyBuild or 1,
		waist = pedEntry.waist or 1,
		eyebrowStyle = pedEntry.eyebrowStyle or 1,
		eyebrowColor = pedEntry.eyebrowColor or 1,
		hairGroup = pedEntry.hairGroup or 1,
		hairColor = pedEntry.hairColor or 1,
		beardGroup = pedEntry.beardGroup or 0,
		list = {}
	}

	-- Re-derive tone (needed for the eyebrow overlay's base head texture) from the
	-- Heads/BodiesUpper/BodiesLower hashes already in outfitComponents — the exact
	-- same reverse-lookup StartCustomizeSession uses, rather than persisting tone
	-- separately.
	if pedEntry.outfitComponents and next(pedEntry.outfitComponents) then
		pcall(HydrateCustomSessionFromComponents, session, pedEntry.outfitComponents)
	end

	pcall(ApplyBodyBuild, session)
	pcall(ApplyWaist, session)
	pcall(ApplyHair, session)
	pcall(ApplyBeard, session)
	pcall(ApplyEyebrows, session)
	pcall(UpdatePedVariation, ped)

	if Database[ped] then
		Database[ped].bodyBuild = session.bodyBuild
		Database[ped].waist = session.waist
		Database[ped].eyebrowStyle = session.eyebrowStyle
		Database[ped].eyebrowColor = session.eyebrowColor
		Database[ped].hairGroup = session.hairGroup
		Database[ped].hairColor = session.hairColor
		Database[ped].beardGroup = session.beardGroup
	end
end

-- Opens the same editor on a ped that already exists in the world (Properties ->
-- Ped Options -> Customize) instead of spawning a fresh one. If this ped was built
-- by our own system (Create Random/Create Custom/a saved MP ped), its exact look is
-- already known (Database[ped].outfitComponents) and gets restored into the editor
-- via HydrateCustomSessionFromComponents. Otherwise (an ordinary NPC, the player,
-- anything we have no record for) there's no reliable way to read back what's
-- equipped, so every row starts blank — the ped's current look is left untouched
-- either way; nothing is applied here, only once the player interacts with a row.
local function StartCustomizeSession(ped, gender)
	-- Only clean up a *different, stale* temp ped left over from a previous Create
	-- Custom session — if the ped being customized now happens to be that same temp
	-- ped (e.g. it was left in the world and later re-selected), it must not be
	-- deleted out from under the very session that's about to edit it.
	if CustomPedSession and CustomPedSession.isTemp and CustomPedSession.ped and CustomPedSession.ped ~= ped and DoesEntityExist(CustomPedSession.ped) then
		RemoveEntity(CustomPedSession.ped)
	end

	local list, byName = BuildCustomCategories(gender)

	for _, entry in ipairs(list) do
		if not entry.required then
			entry.index = 0
		end
	end

	local session = {
		ped = ped, gender = gender, list = list, byName = byName,
		tone = 1, headShape = 1, bodyShape = 1, legsShape = 1,
		bodyBuild = (Database[ped] and Database[ped].bodyBuild) or 1,
		waist = (Database[ped] and Database[ped].waist) or 1,
		eyebrowStyle = (Database[ped] and Database[ped].eyebrowStyle) or 1,
		eyebrowColor = (Database[ped] and Database[ped].eyebrowColor) or 1,
		hairGroup = (Database[ped] and Database[ped].hairGroup) or 1,
		hairColor = (Database[ped] and Database[ped].hairColor) or 1,
		beardGroup = (Database[ped] and Database[ped].beardGroup) or 0,
		isTemp = false
	}

	local knownComponents = Database[ped] and Database[ped].outfitComponents

	if knownComponents and next(knownComponents) then
		HydrateCustomSessionFromComponents(session, knownComponents)
	end

	CustomPedSession = session

	Database[ped] = Database[ped] or {}
	Database[ped].outfitComponents = Database[ped].outfitComponents or {}

	return CustomPedSession
end

RegisterNUICallback('openCustomMpPed', function(data, cb)
	local session = nil

	if Permissions.spawn.ped then
		local gender = data.gender == 'female' and 'female' or 'male'
		session = StartCustomPedSession(gender)
	end

	if session then
		cb(json.encode({ gender = session.gender, genderLocked = false, handle = session.ped, categories = SerializeCustomCategories(session) }))
	else
		cb(json.encode({}))
	end
end)

-- Ped Options -> Customize: edit the selected, already-existing ped in place.
-- Horses (ped type 1, but IsModelAHorse) get the tack editor instead of the human
-- clothing/body editor — the UI is the same #mp-custom-menu, just different rows.
RegisterNUICallback('openCustomizePed', function(data, cb)
	local ped = tonumber(data.handle)
	local session = nil
	local isHorse = false

	if Permissions.spawn.ped and ped and DoesEntityExist(ped) and GetEntityType(ped) == 1 then
		if IsEntityHorse(ped) then
			session = StartHorseTackSession(ped)
			isHorse = true
		else
			local model = GetEntityModel(ped)
			local gender = (model == GetHashKey('mp_female')) and 'female' or 'male'
			session = StartCustomizeSession(ped, gender)
		end
	end

	if session then
		-- genderLocked hides the gender row in the UI — always true here (an existing
		-- ped's model is fixed; a horse has no gender row at all).
		cb(json.encode({ gender = session.gender or 'male', genderLocked = true, isHorse = isHorse, handle = session.ped, categories = SerializeCustomCategories(session) }))
	else
		cb(json.encode({}))
	end
end)

RegisterNUICallback('customPedSetGender', function(data, cb)
	local session = nil

	-- Switching gender means spawning a different model, which only makes sense
	-- for the temp "Create Custom" ped — never for an existing ped being customized.
	if Permissions.spawn.ped and (not CustomPedSession or CustomPedSession.isTemp) then
		local gender = data.gender == 'female' and 'female' or 'male'
		session = StartCustomPedSession(gender)
	end

	if session then
		cb(json.encode({ gender = session.gender, genderLocked = false, handle = session.ped, categories = SerializeCustomCategories(session) }))
	else
		cb(json.encode({}))
	end
end)

-- Shared by customPedCycle (relative) and customPedSetIndex (absolute): moves the
-- given row to newIndex (already clamped/wrapped by the caller) and re-applies it.
local function SetCustomRowIndex(session, category, newIndex)
	if session.isHorse then
		return SetHorseRowIndex(session, category, newIndex)
	end

	if CUSTOM_BODY_ROW_FIELD[category] then
		session[CUSTOM_BODY_ROW_FIELD[category]] = newIndex

		if category == 'BodyBuild' then
			ApplyBodyBuild(session)
		elseif category == 'Waist' then
			ApplyWaist(session)
		elseif category == 'Eyebrows' or category == 'EyebrowColor' then
			ApplyEyebrows(session)
		elseif category == 'HairStyle' then
			ApplyHair(session)
		elseif category == 'BeardStyle' then
			ApplyBeard(session)
		elseif category == 'HairColor' then
			ApplyHairColor(session)
		else
			-- Tone/head/body/legs shape all re-equip Heads, which rebuilds the head's
			-- base texture — the eyebrow overlay (composited on top of it) has to be
			-- rebuilt right along with it or it reverts to the bare head underneath.
			ApplyBodyAppearance(session)
			ApplyEyebrows(session)
		end

		UpdatePedVariation(session.ped)

		Database[session.ped].outfitComponents = GetCustomPedComponents(session)
		Database[session.ped].bodyBuild = session.bodyBuild
		Database[session.ped].waist = session.waist
		Database[session.ped].eyebrowStyle = session.eyebrowStyle
		Database[session.ped].eyebrowColor = session.eyebrowColor
		Database[session.ped].hairGroup = session.hairGroup
		Database[session.ped].hairColor = session.hairColor
		Database[session.ped].beardGroup = session.beardGroup

		return newIndex, GetBodyRowCount(session, category)
	end

	local entry = session.byName[category]

	if not entry then
		return nil
	end

	-- Unlike Heads/BodiesUpper/BodiesLower (handled entirely separately via
	-- ApplyBodyAppearance), a general clothing category doesn't reliably swap to a
	-- different item in the same slot just by applying the new one on top — the old
	-- item has to actually be removed first, or cycling through options can look
	-- like nothing is happening.
	if entry.appliedHash then
		pcall(RemoveShopItemFromPed, session.ped, entry.appliedHash)
		entry.appliedHash = nil
	end

	entry.index = newIndex

	if newIndex == 0 then
		entry.wearableStateIndex = nil
	else
		local hash = entry.options[newIndex]
		pcall(ApplyShopItemToPed, session.ped, hash)
		entry.appliedHash = hash
		entry.wearableStateIndex = 0
	end

	-- Only for neck/outerwear changes: re-push every equipped garment so a bandana
	-- tucked under a coat isn't left culled (see CUSTOM_RELAYER_CATEGORIES). Other
	-- categories fall straight through to a plain variation update, unchanged.
	if CUSTOM_RELAYER_CATEGORIES[category] then
		local isMpFemale = session.gender == 'female'

		for _, other in ipairs(session.list) do
			if other.appliedHash then
				pcall(ApplyShopItemToPed, session.ped, other.appliedHash)

				-- Keep a non-default wearable state (e.g. bandana over the face) across
				-- the re-apply — re-applying resets it to state 0 otherwise.
				if other.wearableStateIndex and other.wearableStateIndex > 0 then
					local okState, stateHash = pcall(GetShopItemWearableStateByIndex, other.appliedHash, other.wearableStateIndex, isMpFemale)

					if okState and stateHash then
						pcall(UpdateShopItemWearableState, session.ped, other.appliedHash, stateHash, true)
					end
				end
			end
		end
	end

	UpdatePedVariation(session.ped)

	Database[session.ped].outfitComponents = GetCustomPedComponents(session)

	return newIndex, #entry.options
end

local function GetCustomRowState(session, category)
	if session.isHorse then
		return GetHorseRowState(session, category)
	end

	if CUSTOM_BODY_ROW_FIELD[category] then
		return session[CUSTOM_BODY_ROW_FIELD[category]] or 1, GetBodyRowCount(session, category), not CUSTOM_BODY_ROW_OPTIONAL[category]
	end

	local entry = session.byName[category]

	if not entry then
		return nil
	end

	return entry.index, #entry.options, entry.required
end

RegisterNUICallback('customPedCycle', function(data, cb)
	local session = CustomPedSession

	if session and session.ped and DoesEntityExist(session.ped) then
		local index, count, required = GetCustomRowState(session, data.category)

		if index then
			local minIndex = required and 1 or 0
			local direction = (data.direction == -1) and -1 or 1
			local newIndex = index + direction

			if newIndex > count then
				newIndex = minIndex
			elseif newIndex < minIndex then
				newIndex = count
			end

			local finalIndex, finalCount = SetCustomRowIndex(session, data.category, newIndex)

			-- A horse mane/tail Style change adds/removes its Color row (and the Color
			-- count is per-style), so hand back the whole row list and let the UI
			-- re-render rather than patching a single row.
			if session.isHorse then
				cb(json.encode({ index = finalIndex, count = finalCount, categories = SerializeCustomCategories(session) }))
				return
			end

			cb(json.encode({ index = finalIndex, count = finalCount }))
			return
		end
	end

	cb(json.encode({}))
end)

-- Lets the player type an exact option number, or jump straight to "None" (0) via
-- the dedicated clear button — both go through the same clamp-and-apply path.
RegisterNUICallback('customPedSetIndex', function(data, cb)
	local session = CustomPedSession

	if session and session.ped and DoesEntityExist(session.ped) then
		local index, count, required = GetCustomRowState(session, data.category)

		if index then
			local minIndex = required and 1 or 0
			local requested = math.floor(tonumber(data.index) or 0)
			local newIndex = math.max(minIndex, math.min(count, requested))

			local finalIndex, finalCount = SetCustomRowIndex(session, data.category, newIndex)

			if session.isHorse then
				cb(json.encode({ index = finalIndex, count = finalCount, categories = SerializeCustomCategories(session) }))
				return
			end

			cb(json.encode({ index = finalIndex, count = finalCount }))
			return
		end
	end

	cb(json.encode({}))
end)

RegisterNUICallback('customPedRandomizeAll', function(data, cb)
	local session = CustomPedSession

	if session and session.isHorse and session.ped and DoesEntityExist(session.ped) then
		RandomizeHorseTack(session)

		cb(json.encode({ gender = 'male', genderLocked = true, isHorse = true, handle = session.ped, categories = SerializeCustomCategories(session) }))
		return
	end

	if session and session.ped and DoesEntityExist(session.ped) then
		RandomizeCustomBodyAppearance(session)
		RandomizeCustomList(session)

		ApplyBodyAppearance(session)
		ApplyHair(session)
		ApplyBeard(session)
		ApplyEyebrows(session)
		ApplyBodyBuild(session)
		ApplyWaist(session)
		ApplyCustomPedComponents(session)
		SetEntityVisible(session.ped, true)

		Database[session.ped].outfitComponents = GetCustomPedComponents(session)
		Database[session.ped].bodyBuild = session.bodyBuild
		Database[session.ped].waist = session.waist
		Database[session.ped].eyebrowStyle = session.eyebrowStyle
		Database[session.ped].eyebrowColor = session.eyebrowColor
		Database[session.ped].hairGroup = session.hairGroup
		Database[session.ped].hairColor = session.hairColor
		Database[session.ped].beardGroup = session.beardGroup

		cb(json.encode({ gender = session.gender, genderLocked = not session.isTemp, handle = session.ped, categories = SerializeCustomCategories(session) }))
		return
	end

	cb(json.encode({}))
end)

RegisterNUICallback('closeCustomMpPed', function(data, cb)
	-- Once the editor is closed, its ped is "placed" like any other spawned ped —
	-- clear the session so a later Create Custom doesn't treat it as a leftover
	-- disposable draft and delete it out from under the player.
	CustomPedSession = nil

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

