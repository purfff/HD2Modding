-- Build-time constants are inserted by build.py. Only current-build data is touched.
return function(make_api, c)
    if rawget(_G, 'CrematorBoost') then return end
    local boost_damage = c.variant == 'damage_only' or c.variant == 'native_range'
    local swap_effect = c.variant == 'range_only'
    local add_heavy = c.variant == 'native_burning'
    local modify_damage = boost_damage or add_heavy
    local state = {version = c.version, variant = c.variant, status = 'starting', writes = 0}
    rawset(_G, 'CrematorBoost', state)
    local directory = os.getenv('LOCALAPPDATA')
    local log_file = directory and io.open(directory .. '/CrematorBoost.log', 'a')
    if not log_file then state.status = 'log_open_failed'; print('[CrematorBoost] log_open_failed'); return end
    local api, game, started, effect_lease, damage_lease, observed_damage, stopped, disabled
    local next_lookup, last_check, next_cleanup, last_wait, last_wait_reason = 0, 0, 0, 0, nil
    local function log(s)
        log_file:write(string.format('t=%.3f %s\n', api and api.time() or 0, s))
        log_file:flush()
    end
    local function raw(hex) return (hex:gsub('..', function(x) return string.char(tonumber(x, 16)) end)) end
    local spray_header, expected_row = raw(c.spray_header), raw(c.spray_row)
    local expected_damage, original_effect, long_effect = raw(c.damage_row), raw(c.original_effect), raw(c.long_effect)
    local damage_old, damage_new = raw('0300000003000000'), raw('1e0000001e000000')
    local damage_offset = add_heavy and 68 or 4
    if add_heavy then
        damage_old, damage_new = expected_damage:sub(69, 76), raw(c.heavy_payload)
        assert(damage_old == string.rep('\0', 8), 'status_slot_occupied')
    end
    local modified_row = expected_row:sub(1, 112) .. long_effect .. expected_row:sub(121)
    local modified_damage = expected_damage:sub(1, damage_offset) .. damage_new .. expected_damage:sub(damage_offset + 9)
    local active_damage = modify_damage and modified_damage or expected_damage
    local cremator, sentry, lumberer = raw(c.cremator_hash), raw(c.sentry_hash), raw(c.lumberer_hash)

    local function u32(s, offset)
        local a, b, d, e = s:byte(offset + 1, offset + 4)
        return a + b * 256 + d * 65536 + e * 16777216
    end
    local function damage()
        local slot = game + 0x37c60c0 + 17 * 8
        local pointer = api.read(slot, 8)
        local address = pointer and api.pointer(pointer)
        if not address then return nil, 'damage_pointer' end
        local record = api.read(address, 76)
        if record ~= expected_damage then return nil, 'damage_record' end
        return {slot = slot, pointer = pointer, address = address}
    end
    local function spray(address)
        local header = api.read(address, 24)
        if not header or header:sub(1, 16) ~= spray_header then return nil end
        local map = api.read(address + 24, 736)
        if not map then return nil end
        local indexes = {}
        for i = 0, 45 do
            local key = map:sub(i * 16 + 1, i * 16 + 8)
            if key == cremator then indexes.cremator = u32(map, i * 16 + 8) end
            if key == sentry then indexes.sentry = u32(map, i * 16 + 8) end
            if key == lumberer then indexes.lumberer = u32(map, i * 16 + 8) end
        end
        if indexes.cremator == nil or indexes.sentry == nil or indexes.lumberer == nil then return nil end
        for _, index in pairs(indexes) do if index >= 24 then return nil end end
        local row = address + 24 + 736 + indexes.cremator * 224
        local sentry_row = address + 24 + 736 + indexes.sentry * 224
        local lumberer_row = address + 24 + 736 + indexes.lumberer * 224
        if api.read(row, 224) ~= expected_row then return nil end
        for _, other in ipairs({sentry_row, lumberer_row}) do
            local data = api.read(other, 224)
            if not data or data:sub(113, 120) ~= long_effect or u32(data, 200) ~= 17 then return nil end
        end
        return {table = address, row = row, effect = row + 112}
    end
    local function cleanup()
        local okay = true
        if damage_lease then
            local lease = damage_lease
            if api.read(lease.slot, 8) == lease.pointer and api.read(lease.address, 76) == modified_damage then
                local wrote = api.write_damage(lease.address + damage_offset, damage_new, damage_old)
                if wrote then damage_lease = nil; log('RESTORED damage') else okay = false end
            elseif api.read(lease.slot, 8) == lease.pointer and api.read(lease.address, 76) == expected_damage then
                damage_lease = nil
            else okay = false end
        end
        if effect_lease then
            local lease = effect_lease
            local header = api.read(lease.table, 16)
            local row = api.read(lease.row, 224)
            if header == spray_header and row == modified_row then
                local wrote = api.write_effect(lease.effect, long_effect, original_effect)
                if wrote then effect_lease = nil; log('RESTORED effect') else okay = false end
            elseif header == spray_header and row == expected_row then
                effect_lease = nil
            else okay = false end
        end
        return okay
    end
    local function apply(s)
        local d, reason = damage()
        if not d then return nil, reason end
        if (swap_effect and (not s or api.read(s.row, 224) ~= expected_row))
            or api.read(d.address, 76) ~= expected_damage
            or api.read(d.slot, 8) ~= d.pointer then return nil, 'settings_changed' end
        if swap_effect then
            effect_lease = s
            local wrote, why = api.write_effect(s.effect, original_effect, long_effect)
            if not wrote then cleanup(); return nil, 'effect_' .. tostring(why) end
            state.writes = state.writes + 1
        end
        if modify_damage then
            damage_lease = d
            local wrote, why = api.write_damage(d.address + damage_offset, damage_old, damage_new)
            if not wrote then cleanup(); return nil, 'damage_' .. tostring(why) end
            state.writes = state.writes + 1
        end
        observed_damage = d
        state.status = 'applied'
        log('APPLIED variant=' .. c.variant .. ' Cremator_effect=' .. (swap_effect and 'long_range_experimental' or 'original')
            .. ' damage_17=' .. (boost_damage and '4/4_shared_with_sentry_and_lumberer' or '3/3_unchanged')
            .. (add_heavy and ' BurningHeavy=32 value=2 shared_with_sentry_and_lumberer; original_statuses_preserved' or ''))
        return true
    end
    local function locate_spray()
        local targets, reason = api.find_spray_targets()
        if not targets then return nil, reason end
        local found
        for _, address in ipairs(targets) do
            local match = spray(address)
            if match then
                if found then return nil, 'spray_ambiguous' end
                found = match
            end
        end
        if found then return found end
        return nil, 'spray_not_ready'
    end
    local function wait_data(now, reason)
        state.status = 'waiting_data'
        if now - started >= 600 then error('data_wait_timeout:' .. reason) end
        if reason ~= last_wait_reason or now - last_wait >= 30 then
            last_wait, last_wait_reason = now, reason
            log('WAIT ' .. reason .. ' retry=2s locator=fixed_offset')
        end
    end
    local function sample()
        local now = api.time()
        if disabled then
            if now >= next_cleanup then
                next_cleanup = now + 2
                if cleanup() then stopped = true end
            end
            return
        end
        if state.status == 'applied' then
            if now - last_check >= 5 then
                last_check = now
                if (swap_effect and (not effect_lease or api.read(effect_lease.row, 224) ~= modified_row))
                    or not observed_damage
                    or api.read(observed_damage.slot, 8) ~= observed_damage.pointer
                    or api.read(observed_damage.address, 76) ~= active_damage then
                    error('modified_settings_changed')
                end
            end
            return
        end
        if now < next_lookup then return end
        next_lookup = now + 2
        local s, reason
        if swap_effect then s, reason = locate_spray() end
        if modify_damage or s then
            local applied, why = apply(s)
            if not applied then
                if why == 'damage_pointer' or why == 'damage_record' then wait_data(now, why)
                else error(why) end
            end
        elseif reason == 'spray_not_ready' then
            wait_data(now, reason)
        elseif reason then
            error(reason)
        end
    end

    local ok, error_message = pcall(function()
        log('SESSION version=' .. c.version .. ' variant=' .. tostring(c.variant) .. ' wall_time=' .. os.date('%Y-%m-%dT%H:%M:%S'))
        assert(modify_damage ~= swap_effect, 'invalid_variant')
        local loader = rawget(_G, 'CowboyBingusModLoader')
        assert(loader and loader.api == 1 and loader.version >= 16, 'shared_loader_v16_required')
        api = make_api()
        started = api.time()
        game = assert(api.module('game.dll'), 'game_dll_unavailable')
        local exe = assert(api.module(nil), 'exe_unavailable')
        assert(api.module_hash(exe) == c.exe_sha256 and api.module_hash(game) == c.dll_sha256,
            'unsupported_game_build')
        local code = raw(c.damage_code)
        assert(api.read(game + 0x11f8dd6, #code) == code, 'damage_map_code_changed')
        assert(#expected_row == 224 and #expected_damage == 76 and #spray_header == 16,
            'snapshot_length')
        assert(expected_row:sub(113, 120) == original_effect and u32(expected_row, 200) == 17,
            'snapshot_links')
        assert(expected_damage:sub(5, 12) == raw('0300000003000000'), 'snapshot_damage')
        if add_heavy then assert(damage_new == raw('2000000000000040'), 'heavy_payload') end
        log('READY variant=' .. c.variant .. ' build_verified; retry=2s')
        assert(type(update) == 'function', 'update_unavailable')
        local previous, previous_shutdown = update, shutdown
        local function after(called, ...)
            if not called then
                disabled = true; cleanup(); log('END original_update_failed')
                log_file:close(); error((...), 0)
            end
            if not stopped then
                local worked, why = pcall(sample)
                if not worked then
                    disabled = true; state.status = 'disabled'; next_cleanup = 0
                    log('DISABLED ' .. tostring(why) .. ' cleanup=' .. tostring(cleanup()))
                end
            end
            return ...
        end
        update = function(...) return after(pcall(previous, ...)) end
        shutdown = function(...)
            stopped = true
            local cleaned = cleanup()
            log('END writes=' .. state.writes .. ' cleanup=' .. tostring(cleaned))
            log_file:close()
            if previous_shutdown then return previous_shutdown(...) end
        end
        state.status = 'searching'
    end)
    if not ok then
        cleanup(); state.status = 'disabled'; log('DISABLED ' .. tostring(error_message)); log_file:close()
    end
end
