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
            or #expected ~= 8 or #replacement ~= 8 then return false, 'payload' end
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

