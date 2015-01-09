-- there is enough resources, update the counts
for i, limit in ipairs(limits) do
    local saved = saved_keys[i]

    for j, key in ipairs(KEYS) do
        -- update the current timestamp, count, and bucket count
        redis.call('HSET', key, saved.ts_key, saved.trim_before)
        redis.call('HINCRBY', key, saved.count_key, weight)
        redis.call('HINCRBY', key, saved.count_key .. saved.block_id, weight)
    end
end

-- We calculated the longest-duration limit so we can EXPIRE
-- the whole HASH for quick and easy idle-time cleanup :)
if longest_duration > 0 then
    for _, key in ipairs(KEYS) do
        redis.call('EXPIRE', key, longest_duration)
    end
end

return 0
