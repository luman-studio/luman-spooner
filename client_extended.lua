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
	if GetEntityType(entity) == 3 then -- object
		TryStopEntityAnim(entity)
	else -- ped
		TryClearTasks(entity)
	end
	cb({})
end)

--
RegisterNUICallback('physicsPush', function(data, cb)
	-- TODO: Check Permissions.properties.physics
	if CanModifyEntity(data.handle) then
		RequestControl(data.handle)

		--
		local x, y, z = 0.0, 0.0, -1.0
		local object = data.handle
		SetEntityHeading(object, GetEntityHeading(PlayerPedId())) -- for direction
        local off = GetObjectOffsetFromCoords(GetEntityCoords(object), GetEntityHeading(object), x*50.0, y*50.0, z*50.0)
        local di = (GetEntityCoords(object) - off) / 10.0
        local s1, s2, s3 = 5.0, 5.0, 5.0
        ApplyForceToEntity(object, 1, di.x * s1, di.y * s2, di.z * s3, 0.0, 0.0, 0.0, 0, false, true, true, false, true)
	end
	cb({})
end)