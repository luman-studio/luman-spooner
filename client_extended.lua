function CutDigits(val)
    return math.floor(val * 1000) / 1000
end

RegisterNUICallback('close', function(data, cb)
	DisableSpoonerMode()
	cb({})
end)

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

RegisterNUICallback('pauseAnimation', function(data, cb)
	local entity = data.handle
	local anim = GetAnimationInfo(entity)
	if anim and DoesEntityExist(entity) then
		local time = GetEntityAnimCurrentTime(entity, anim.dict, anim.name)
		PausedAnimations[entity] = { dict = anim.dict, name = anim.name, time = time }
		RequestControl(entity)
		if GetEntityType(entity) == 3 then
			StopEntityAnim(entity, anim.name, anim.dict, 0.0)
		else
			ClearPedTasksImmediately(entity)
		end
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
			PlayAnimation(entity, anim)
			Wait(0)
			SetEntityAnimCurrentTime(entity, anim.dict, anim.name, paused.time)
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
			PlayAnimation(entity, anim)
			Wait(0)
			SetEntityAnimCurrentTime(entity, anim.dict, anim.name, time)
			Wait(0)
			if GetEntityType(entity) == 3 then
				StopEntityAnim(entity, anim.name, anim.dict, 0.0)
			else
				ClearPedTasksImmediately(entity)
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

-------------------
-- Player Bucket --
-------------------
AddEventHandler('spooner:onSpoonerEnabled', function()
	TriggerServerEvent('spooner:requestPlayerRoutingBucket', PlayerPedId())
end)

RegisterNetEvent('spooner:onRequestPlayerRoutingBucket', function(bucket)
	SendNUIMessage({
		type = 'onRequestPlayerRoutingBucket',
		bucket = bucket,
	})
end)

RegisterNetEvent('spooner:onPlayerBucketChange', function(bucket)
	SendNUIMessage({
		type = 'onRequestPlayerRoutingBucket',
		bucket = bucket,
	})
end)

-------------------------------------------------------
-- Disable collision for entity white it is selected --
-------------------------------------------------------
local hadCollisionDisabled = false
AddEventHandler('spooner:onEntitySelected', function(entity)
	if not entity or not DoesEntityExist(entity) then
		return
	end

	-- Disable collision while entity selected
	hadCollisionDisabled = GetEntityCollisionDisabled(entity)
	SetEntityCollision(entity, false)
end)

AddEventHandler('spooner:onEntityUnselected', function(entity)
	if not entity or not DoesEntityExist(entity) then
		return
	end

	-- Keep collision disabled if it was before selection
	if not hadCollisionDisabled then
		SetEntityCollision(entity, true)
	end
end)

---------------
-- Interiors --
---------------
InteriorsHash = {}
if Interiors ~= nil then
	for k,v in ipairs(Interiors) do
		InteriorsHash[GetHashKey(v.name)] = v.name 
	end
end

------------------
-- Notification --
------------------
function notify(message)
    -- GTA V notification natives don't exist in RedM, so guard them.
    if SetNotificationTextEntry then
        SetNotificationTextEntry('STRING')
        AddTextComponentString(message .. '    ~l~[' .. GetGameTimer() .. ']')
        DrawNotification(false, false)
        PlaySoundFrontend(-1, "DLC_VW_CONTINUE", "dlc_vw_table_games_frontend_sounds", 1)
    end

    TriggerEvent('chat:addMessage', { args = { '[Spooner]', message } })
end
RegisterNUICallback('notify', function(data, cb)
	local msg = data.message
	notify(msg)
	cb({})
end)


---------------
-- UI Loaded --
---------------
uiLoaded = false
RegisterNUICallback('loaded', function(data, cb)
	uiLoaded = true
	cb({})
end)