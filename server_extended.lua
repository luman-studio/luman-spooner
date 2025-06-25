RegisterNetEvent('spooner:requestPlayerRoutingBucket', function(netId)
	local playerId = source
	TriggerClientEvent('spooner:onRequestPlayerRoutingBucket', playerId, GetPlayerRoutingBucket(playerId))
end)

AddEventHandler('onPlayerBucketChange', function(playerId, bucket, oldBucket)
    TriggerClientEvent('spooner:onPlayerBucketChange', playerId, bucket, oldBucket)
end)