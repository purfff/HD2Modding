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
