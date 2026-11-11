#include "smc.h"
#include <string.h>

enum {
    kSMCHandleYPCEvent = 2,
    kSMCReadKey = 5,
    kSMCWriteKey = 6,
    kSMCGetKeyFromIndex = 8,
    kSMCGetKeyInfo = 9,
};

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyInfo;

typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParam;

io_connect_t bk_smc_open(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;
    io_connect_t conn = 0;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &conn);
    IOObjectRelease(service);
    return result == KERN_SUCCESS ? conn : 0;
}

void bk_smc_close(io_connect_t conn) {
    if (conn) IOServiceClose(conn);
}

uint32_t bk_smc_fourcc(const char *key) {
    uint32_t code = 0;
    for (int i = 0; i < 4 && key[i]; i++) code = (code << 8) | (uint8_t)key[i];
    return code;
}

void bk_smc_fourcc_string(uint32_t code, char out[5]) {
    out[0] = (char)(code >> 24);
    out[1] = (char)(code >> 16);
    out[2] = (char)(code >> 8);
    out[3] = (char)code;
    out[4] = 0;
}

static kern_return_t bk_smc_call(io_connect_t conn, SMCParam *input, SMCParam *output) {
    size_t outSize = sizeof(SMCParam);
    kern_return_t result = IOConnectCallStructMethod(conn, kSMCHandleYPCEvent, input, sizeof(SMCParam), output, &outSize);
    if (result != KERN_SUCCESS) return result;
    return output->result == 0 ? KERN_SUCCESS : kIOReturnError;
}

kern_return_t bk_smc_key_info(io_connect_t conn, uint32_t key, uint32_t *outSize, uint32_t *outType) {
    SMCParam input = {0}, output = {0};
    input.key = key;
    input.data8 = kSMCGetKeyInfo;
    kern_return_t result = bk_smc_call(conn, &input, &output);
    if (result != KERN_SUCCESS) return result;
    if (outSize) *outSize = output.keyInfo.dataSize;
    if (outType) *outType = output.keyInfo.dataType;
    return KERN_SUCCESS;
}

kern_return_t bk_smc_read(io_connect_t conn, uint32_t key, BKSMCValue *outValue) {
    SMCParam input = {0}, output = {0};
    input.key = key;
    input.data8 = kSMCGetKeyInfo;
    kern_return_t result = bk_smc_call(conn, &input, &output);
    if (result != KERN_SUCCESS) return result;
    SMCKeyInfo info = output.keyInfo;

    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = key;
    input.keyInfo.dataSize = info.dataSize;
    input.data8 = kSMCReadKey;
    result = bk_smc_call(conn, &input, &output);
    if (result != KERN_SUCCESS) return result;

    memset(outValue, 0, sizeof(*outValue));
    outValue->key = key;
    outValue->dataSize = info.dataSize > 32 ? 32 : info.dataSize;
    outValue->dataType = info.dataType;
    memcpy(outValue->bytes, output.bytes, outValue->dataSize);
    return KERN_SUCCESS;
}

kern_return_t bk_smc_write(io_connect_t conn, uint32_t key, const uint8_t *bytes, uint32_t size) {
    uint32_t expected = 0;
    kern_return_t result = bk_smc_key_info(conn, key, &expected, NULL);
    if (result != KERN_SUCCESS) return result;
    if (expected != size || size > 32) return kIOReturnBadArgument;

    SMCParam input = {0}, output = {0};
    input.key = key;
    input.data8 = kSMCWriteKey;
    input.keyInfo.dataSize = size;
    memcpy(input.bytes, bytes, size);
    return bk_smc_call(conn, &input, &output);
}

kern_return_t bk_smc_key_at_index(io_connect_t conn, uint32_t index, uint32_t *outKey) {
    SMCParam input = {0}, output = {0};
    input.data8 = kSMCGetKeyFromIndex;
    input.data32 = index;
    kern_return_t result = bk_smc_call(conn, &input, &output);
    if (result != KERN_SUCCESS) return result;
    *outKey = output.key;
    return KERN_SUCCESS;
}
