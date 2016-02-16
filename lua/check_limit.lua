-- Credit: http://www.dr-josiah.com/2014/11/introduction-to-rate-limiting-with_26.html

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
    saved.count_key = duration .. ':' .. precision .. ':'
    saved.ts_key = saved.count_key .. 'o'

    for j, key in ipairs(KEYS) do
        local old_ts = redis.call('HGET', key, saved.ts_key)
        old_ts = old_ts and tonumber(old_ts) or now
        if old_ts > now then
            -- don't write in the past
            return cjson.encode(return_val)
        end

        -- discover what needs to be cleaned up
        local trim_before = saved.block_id - blocks + 1
        -- This computes the trim before for the last ts stored for this key
        local old_trim_before = math.ceil(old_ts / precision) - blocks + 1
        local decr = 0
        local dele = {}
        local trim = math.min(trim_before, old_trim_before + blocks)
        for old_block = old_trim_before, trim - 1 do
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

        local is_violated = cur + weight > limit[2]
        local req_count = cur
        local last_ts

        -- If this request will violate the rate limit, the leave req_count set
        -- to whatever it's currently set to and use the last successful request
        -- timestamp to compute the reset timestamp. If this request will
        -- succeed, we add the weight to req_count and use now to compute the
        -- reset timestamp.
        if is_violated then
          last_ts = old_ts
        else
          req_count = req_count + weight
          last_ts = now
        end

        table.insert(key_stats, req_count)
        table.insert(key_stats, is_violated)
        table.insert(key_stats, last_ts + duration)
        table.insert(return_val, key_stats)

        -- Return immediately if we have any violations
        if is_violated then
            return cjson.encode(return_val)
        end
    end
end
