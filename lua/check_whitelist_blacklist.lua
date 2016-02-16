-- Check the whitelist and blacklist sets for the given key
for _, key in ipairs(KEYS) do
    local is_set_member = redis.call('SISMEMBER', whitelist_key, key)
    if tonumber(is_set_member) > 0 then
        return 0
    end

    is_set_member = redis.call('SISMEMBER', blacklist_key, key)
    if tonumber(is_set_member) > 0 then
        return 2
    end
end
