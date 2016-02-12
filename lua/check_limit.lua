-- Credit: http://www.dr-josiah.com/2014/11/introduction-to-rate-limiting-with_26.html

-- Return specific code for whitelisted keys
if is_whitelisted then
  return 0
end

-- Return specific code for blacklisted keys
if is_blacklisted then
  return 1
end

-- handle cleanup and limit checks
for i, limit in ipairs(limits) do
    local duration = limit[1]
    longest_duration = math.max(longest_duration, duration)

    local precision = limit[3] or duration
    precision = math.min(precision, duration)

    local blocks = math.ceil(duration / precision)
    local saved = {}

    table.insert(saved_keys, saved)
    saved.block_id = math.floor(now / precision)
    saved.trim_before = saved.block_id - blocks + 1
    saved.count_key = duration .. ':' .. precision .. ':'
    saved.ts_key = saved.count_key .. 'o'

    for j, key in ipairs(KEYS) do
        local old_ts = redis.call('HGET', key, saved.ts_key)
        old_ts = old_ts and tonumber(old_ts) or saved.trim_before
        if old_ts > now then
            -- don't write in the past
            return 1
        end

        -- discover what needs to be cleaned up
        local decr = 0
        local dele = {}
        local trim = math.min(saved.trim_before, old_ts + blocks)
        for old_block = old_ts, trim - 1 do
            local bkey = saved.count_key .. old_block
            local bcount = redis.call('HGET', key, bkey)
            if bcount then
                decr = decr + tonumber(bcount)
                table.insert(dele, bkey)
            end
        end

        -- handle cleanup
        local cur
        if #dele > 0 then
            redis.call('HDEL', key, unpack(dele))
            cur = redis.call('HINCRBY', key, saved.count_key, -decr)
        else
            cur = redis.call('HGET', key, saved.count_key)
        end

        cur = tonumber(cur or '0')

        local key_stats = {}
        local violated = cur + weight > limit[2]

        table.insert(key_stats, cur)
        table.insert(key_stats, violated)
        table.insert(key_stats, now + precision)
        table.insert(return_val, key_stats)

        -- Return immediately if we have any violations
        if violated then
            return cjson.encode(return_val)
        end
    end
end
