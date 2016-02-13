-- Check the whitelist set for the given key
for _, key in ipairs(KEYS) do
    local is_set_member = redis.call('SISMEMBER', whitelist_key, key)
    is_set_member = tonumber(is_set_member)
    if is_set_member > 0 then
        return 0
    end
end
