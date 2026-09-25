-- HD2-Addon: mods/purfff/cremator_10x_damage

local create_base_api = (function()
    -- paste windows_api.lua here
    -- Adapted from CowboyBingus/SentryAimRetention; boolean drive or allowlisted setting payloads only.
return function()
    local ffi = require('ffi')
    assert(ffi.abi('64bit'), 'Windows x64 is required')
    ffi.cdef [[
        void *GetModuleHandleA(const char *name);
        uint32_t GetModuleFileNameW(void *module, uint16_t *path, uint32_t capacity);
        void *GetCurrentProcess(void);
        uint64_t GetTickCount64(void);
        int ReadProcessMemory(void *process, const void *address, void *buffer, size_t size, size_t *read);
        int WriteProcessMemory(void *process, void *address, const void *buffer, size_t size, size_t *written);
        typedef struct {
            void *base; void *allocation_base; uint32_t allocation_protection;
            uint16_t partition; uint16_t reserved; size_t size;
            uint32_t state; uint32_t protection; uint32_t type;
        } CrematorMemoryRegion;
        size_t VirtualQuery(const void *address, void *region, size_t size);
        void *CreateFileW(const uint16_t *path, uint32_t access, uint32_t share, void *security,
                          uint32_t disposition, uint32_t flags, void *template_file);
        int ReadFile(void *file, void *buffer, uint32_t size, uint32_t *read, void *overlapped);
        int CloseHandle(void *handle);
        int32_t BCryptOpenAlgorithmProvider(void **algorithm, const uint16_t *name,
                                            const uint16_t *provider, uint32_t flags);
        int32_t BCryptCloseAlgorithmProvider(void *algorithm, uint32_t flags);
        int32_t BCryptCreateHash(void *algorithm, void **hash, void *object, uint32_t object_size,
                                 const void *secret, uint32_t secret_size, uint32_t flags);
        int32_t BCryptHashData(void *hash, const void *data, uint32_t size, uint32_t flags);
        int32_t BCryptFinishHash(void *hash, void *digest, uint32_t size, uint32_t flags);
        int32_t BCryptDestroyHash(void *hash);
    ]]
    local kernel, bcrypt = ffi.load('kernel32'), ffi.load('bcrypt')
    local process = kernel.GetCurrentProcess()
    local query = ffi.cast('size_t (*)(const void *, void *, size_t)', kernel.VirtualQuery)
    local api = {}
    function api.time() return tonumber(kernel.GetTickCount64()) / 1000 end

    function api.module(name)
        local handle = kernel.GetModuleHandleA(name)
        if handle == nil then return nil end
        return ffi.cast('uint8_t *', handle)
    end

    function api.read(address, size)
        local buffer, count = ffi.new('uint8_t[?]', size), ffi.new('size_t[1]')
        if kernel.ReadProcessMemory(process, address, buffer, size, count) == 0 or count[0] ~= size then
            return nil
        end
        return ffi.string(buffer, size)
    end

    local function write_exact(address,expected,value)
        if type(expected)~='string' or type(value)~='string' or #expected~=#value or (#value~=1 and #value~=4 and #value~=8) then return false end
        local region=ffi.new('CrematorMemoryRegion[1]')
        if query(address,region,ffi.sizeof(region[0]))~=ffi.sizeof(region[0]) then return false end
        if region[0].state~=0x1000 or region[0].type~=0x20000 or region[0].protection~=4 then return false end
        local first=ffi.cast('uintptr_t',address)
        if first<ffi.cast('uintptr_t',region[0].base) or first+#value>ffi.cast('uintptr_t',region[0].base)+region[0].size then return false end
        if api.read(address,#expected)~=expected then return false end
        local count=ffi.new('size_t[1]')
        return kernel.WriteProcessMemory(process,address,value,#value,count)~=0 and count[0]==#value
            and api.read(address,#value)==value
    end
    function api.write_byte(address, expected, value)
        if (expected~=0 and expected~=1) or (value~=0 and value~=1) then return false end
        return write_exact(address,string.char(expected),string.char(value))
    end
    function api.write_setting(address,expected,value)
        -- Only the two explicit enhancement payloads and their reversals.
        local damage='\xd0\x07\0\0\xd0\x07\0\0';local boosted='\x80\x0c\0\0\x80\x0c\0\0'
        local demo='\x1e\0\0\0';local improved='\x28\0\0\0'
        if not ((expected==damage and value==boosted) or (expected==boosted and value==damage)
            or (expected==demo and value==improved) or (expected==improved and value==demo)) then return false end
        return write_exact(address,expected,value)
    end

    function api.pointer(bytes, offset)
        offset = offset or 0
        if not bytes or offset < 0 or offset + 8 > #bytes then return nil end
        local value = ffi.new('uintptr_t[1]')
        ffi.copy(value, bytes:sub(offset + 1, offset + 8), 8)
        if value[0] < 0x10000 or value[0] >= 0x800000000000 then return nil end
        return ffi.cast('uint8_t *', value[0])
    end

    function api.module_hash(module)
        local path = ffi.new('uint16_t[32768]')
        local length = kernel.GetModuleFileNameW(module, path, 32768)
        assert(length > 0 and length < 32768, 'Cannot resolve module file')
        local file = kernel.CreateFileW(path, 0x80000000, 7, nil, 3, 0x08000000, nil)
        assert(file ~= ffi.cast('void *', -1), 'Cannot read module file')
        local algorithm, hash = ffi.new('void *[1]'), ffi.new('void *[1]')
        local ok, result = pcall(function()
            local name = ffi.new('uint16_t[7]', {83, 72, 65, 50, 53, 54, 0})
            assert(bcrypt.BCryptOpenAlgorithmProvider(algorithm, name, nil, 0) == 0, 'SHA256 unavailable')
            assert(bcrypt.BCryptCreateHash(algorithm[0], hash, nil, 0, nil, 0, 0) == 0, 'SHA256 creation failed')
            local buffer, count = ffi.new('uint8_t[1048576]'), ffi.new('uint32_t[1]')
            while true do
                assert(kernel.ReadFile(file, buffer, 1048576, count, nil) ~= 0, 'Module file read failed')
                if count[0] == 0 then break end
                assert(bcrypt.BCryptHashData(hash[0], buffer, count[0], 0) == 0, 'SHA256 update failed')
            end
            local digest, hex = ffi.new('uint8_t[32]'), {}
            assert(bcrypt.BCryptFinishHash(hash[0], digest, 32, 0) == 0, 'SHA256 finish failed')
            for i = 0, 31 do hex[#hex + 1] = string.format('%02X', digest[i]) end
            return table.concat(hex)
        end)
        if hash[0] ~= nil then bcrypt.BCryptDestroyHash(hash[0]) end
        if algorithm[0] ~= nil then bcrypt.BCryptCloseAlgorithmProvider(algorithm[0], 0) end
        kernel.CloseHandle(file)
        if not ok then error(result) end
        return result
    end
    return api
end

end)()

local make_api = (function()
    -- paste patch_api.lua here
    -- Bounded memory metadata walk and two allowlisted data writes.
return function(create_base_api)
    local ffi = require('ffi')
    local api = create_base_api()
    ffi.cdef [[
        int VirtualProtect(void *address, size_t size, uint32_t protection, uint32_t *old_protection);
    ]]
    local kernel = ffi.load('kernel32')
    local process = kernel.GetCurrentProcess()
    local query = ffi.cast('size_t (*)(const void *, void *, size_t)', kernel.VirtualQuery)

    local function region(address, length, protection)
        address = ffi.cast('uint8_t *', address)
        local info = ffi.new('CrematorMemoryRegion[1]')
        if query(address, info, ffi.sizeof(info[0])) ~= ffi.sizeof(info[0]) then return nil end
        local r = info[0]
        if r.state ~= 0x1000 or r.type ~= 0x20000 or r.protection ~= protection then return nil end
        local first, base = tonumber(ffi.cast('uintptr_t', address)), tonumber(ffi.cast('uintptr_t', r.base))
        if first < base or first + length > base + tonumber(r.size) then return nil end
        return r
    end

    function api.find_spray_targets()
        local found, seen, cursor, queries = {}, {}, 0, 0
        local info = ffi.new('CrematorMemoryRegion[1]')
        -- Current-build offset confirmed across two independent game launches.
        -- Query metadata only; callers read small headers at these exact addresses.
        while cursor < 0x800000000000 do
            queries = queries + 1
            if queries > 131072 then return nil, 'metadata_budget' end
            if query(ffi.cast('void *', cursor), info, ffi.sizeof(info[0])) ~= ffi.sizeof(info[0]) then break end
            local r = info[0]
            local base = tonumber(ffi.cast('uintptr_t', r.base))
            local size = tonumber(r.size)
            local next_address = base + size
            if next_address <= cursor then break end
            if r.state == 0x1000 and r.type == 0x20000 and r.protection == 2 then
                local allocation = tonumber(ffi.cast('uintptr_t', r.allocation_base))
                local target = allocation + 0x2c38cfc
                if target >= base and target + 6136 <= next_address and not seen[target] then
                    found[#found + 1] = ffi.cast('uint8_t *', target)
                    seen[target] = true
                    if #found > 32 then return nil, 'candidate_budget' end
                end
            end
            cursor = next_address
        end
        return found
    end

    local function write_exact(address, expected, replacement, readonly)
        address = ffi.cast('uint8_t *', address)
        if type(expected) ~= 'string' or type(replacement) ~= 'string'
            or #expected ~= #replacement
            or (#expected ~= 8 and #expected ~= 24) then
            return false, 'payload'
        end
        local protection = readonly and 2 or 4
        if not region(address, 8, protection) then return false, 'region' end
        if api.read(address, 8) ~= expected then return false, 'changed' end
        local old = ffi.new('uint32_t[1]')
        if readonly and kernel.VirtualProtect(address, 8, 4, old) == 0 then return false, 'protect' end
        local wrote, count = false, ffi.new('size_t[1]')
        if api.read(address, 8) == expected then
            wrote = kernel.WriteProcessMemory(process, address, replacement, 8, count) ~= 0
                and count[0] == 8 and api.read(address, 8) == replacement
        end
        local restored = true
        if readonly then
            local ignored = ffi.new('uint32_t[1]')
            restored = kernel.VirtualProtect(address, 8, old[0], ignored) ~= 0
        end
        if not restored then return false, 'protect_restore' end
        if not wrote then return false, 'write' end
        return true
    end
    function api.write_damage(address, old, new) return write_exact(address, old, new, false) end
    function api.write_effect(address, old, new) return write_exact(address, old, new, true) end
    return api
end


end)(create_base_api)

local main = (function()
    -- paste main.lua here
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
    local damage_old, damage_new = raw('030000000300000004000000040000000400000004000000'),raw('e8030000e803000006000000060000000600000006000000')
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
            .. ' damage_17=' .. (boost_damage and 'damage_17=1000/1000_AP6_shared_with_sentry_and_lumberer' or '3/3_unchanged')
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
        assert(
    expected_damage:sub(5, 28) == raw('030000000300000004000000040000000400000004000000'),'snapshot_damage_ap')
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

end)

local c = {
    version = "0.6.0-100x",

    exe_sha256 = "F5FEE03DCFDB2E553A4752C283590950AC13316B376D8196AA556FF0400D5F06",
    dll_sha256 = "2E2C3B7C2500646DADD5F2B4C6E0504DBB7E7896139F64CDDC0D1813C718F51E",

    spray_header = "4c444c44010000002611558ee0170000",

    spray_row = "3333333f00002041000000009fcd846b0000000000000000a7518c2b81efc7ce00000000000000000000000000000000000000400000a040f42937f52293728b00000000365300f00000000000000000697fd8a0f695081600000000000000000000000000000000000000400000a040e5d8eca8ab7df1a42dfcee18d2649d81a77cc40600000000000000000000000000000000000000000000000000000000000000400000a04010f3a4db684f840b00000000ebefade0449491d0000000000100000000000000110000000200000001000000f02ccfebf768669103000000",

    damage_row = "110000000300000003000000040000000400000004000000040000000a0000000500000005000000010000000500000000004040430000000000004006000000000080400000000000000000",

    original_effect = "e5d8eca8ab7df1a4",
    long_effect = "c46328a42256d1e3",

    cremator_hash = "9507a7635f18a878",
    sentry_hash = "582896febac30c82",
    lumberer_hash = "268732d6e2be3607",

    damage_code = "486bd04c4803178b02498914c4443b47",

    heavy_payload = "2000000000000040",

    variant = "damage_only"
}

main(make_api, c)